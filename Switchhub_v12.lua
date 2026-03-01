-- ================================================================
-- BOUNTY HUNTER PRO v2 - BLOX FRUITS
-- Fix: Skill không block thread, bay ổn định, attack liên tục
-- ================================================================
repeat task.wait() until game:IsLoaded() and game.Players.LocalPlayer

-- ==================== SERVICES ====================
local Players        = game:GetService("Players")
local RunService     = game:GetService("RunService")
local UIS            = game:GetService("UserInputService")
local HttpService    = game:GetService("HttpService")
local StarterGui     = game:GetService("StarterGui")
local RS             = game:GetService("ReplicatedStorage")
local TS             = game:GetService("TeleportService")
local VIM            = game:GetService("VirtualInputManager")

local LP             = Players.LocalPlayer
local Camera         = workspace.CurrentCamera

-- ==================== CONFIG ====================
getgenv().Team = getgenv().Team or "Pirates"
getgenv().Config = getgenv().Config or {
    ["SafeZone"]     = { ["Enable"]=true, ["LowHealth"]=4500, ["MaxHealth"]=6000, ["Teleport Y"]=9999 },
    ["Hop Server"]   = { ["Enable"]=true, ["Hop When No Target"]=true, ["Delay Hop"]=1, ["Save Joined Server"]=true },
    ["Setting"]      = { ["World"]=3, ["Fast Delay"]=0.45, ["Url"]="", ["Server Hop"]=1 },
    ["Auto turn on v4"] = true,
    ["Items"] = {
        ["Melee"] = {
            Enable = true, Delay = 0.4,
            Skills = {
                Z = {Enable=true, HoldTime=0.3},
                X = {Enable=true, HoldTime=0.2},
                C = {Enable=true, HoldTime=0.5},
            }
        },
        ["Sword"] = {
            Enable = true, Delay = 0.5,
            Skills = {
                Z = {Enable=true, HoldTime=1.0},
                X = {Enable=true, HoldTime=0.0},
            }
        },
    }
}

local CFG        = getgenv().Config
local FastDelay  = CFG["Setting"]["Fast Delay"] or 0.45

-- ==================== STATE ====================
local S = {
    Running       = true,
    Target        = nil,        -- Player object
    TargetTimer   = 0,
    InSafeZone    = false,
    UIVisible     = true,
    KillCount     = 0,
    Visited       = {},
    LastHop       = 0,
    ChaseTimeout  = 120,        -- 2 phút
    JobId         = game.JobId,
    AttackEnabled = true,
    SkillCooldowns= {},         -- {keyName = lastUsedTick}
}

-- ==================== REMOTE FINDER ====================
local NetRemote, NetSeed = nil, nil
local function ScanRemotes(folder)
    if not folder then return end
    for _, v in ipairs(folder:GetChildren()) do
        if v:IsA("RemoteEvent") and v:GetAttribute("Id") then
            NetRemote = v
            NetSeed   = v:GetAttribute("Id")
        end
    end
    folder.ChildAdded:Connect(function(v)
        if v:IsA("RemoteEvent") and v:GetAttribute("Id") then
            NetRemote = v
            NetSeed   = v:GetAttribute("Id")
        end
    end)
end
for _, name in ipairs({"Util","Common","Remotes","Assets","FX"}) do
    ScanRemotes(RS:FindFirstChild(name))
end

-- ==================== HELPERS ====================
local function GetChar()  return LP.Character end
local function GetHRP()   local c=GetChar(); return c and c:FindFirstChild("HumanoidRootPart") end
local function GetHum()   local c=GetChar(); return c and c:FindFirstChild("Humanoid") end

local function IsAlive(player)
    if not player or not player.Character then return false end
    local h = player.Character:FindFirstChild("Humanoid")
    return h and h.Health > 0
end

-- Xóa body mover theo tên
local function ClearMover(name)
    local hrp = GetHRP()
    if hrp then
        local obj = hrp:FindFirstChild(name)
        if obj then obj:Destroy() end
    end
end

-- Tạo/cập nhật BodyVelocity
local function SetBV(vel)
    local hrp = GetHRP()
    if not hrp then return end
    local bv = hrp:FindFirstChild("__BV__") or Instance.new("BodyVelocity")
    bv.Name        = "__BV__"
    bv.MaxForce    = Vector3.new(1e9,1e9,1e9)
    bv.Velocity    = vel
    bv.P           = 1e5
    bv.Parent      = hrp
end

local function SetBP(pos)
    local hrp = GetHRP()
    if not hrp then return end
    local bp = hrp:FindFirstChild("__BP__") or Instance.new("BodyPosition")
    bp.Name        = "__BP__"
    bp.MaxForce    = Vector3.new(1e9,1e9,1e9)
    bp.D           = 300
    bp.P           = 5e4
    bp.Position    = pos
    bp.Parent      = hrp
end

local function SetBG(cf)
    local hrp = GetHRP()
    if not hrp then return end
    local bg = hrp:FindFirstChild("__BG__") or Instance.new("BodyGyro")
    bg.Name        = "__BG__"
    bg.MaxTorque   = Vector3.new(1e9,1e9,1e9)
    bg.D           = 200
    bg.CFrame      = cf
    bg.Parent      = hrp
end

local function ClearFly()
    ClearMover("__BV__")
    ClearMover("__BP__")
    ClearMover("__BG__")
end

-- Tắt/bật gravity
local function Gravity(on) workspace.Gravity = on and 196.2 or 0 end

-- Noclip liên tục (dùng loop riêng)
local NoclipEnabled = true
RunService.Stepped:Connect(function()
    if not NoclipEnabled then return end
    local c = GetChar()
    if not c then return end
    for _, p in ipairs(c:GetDescendants()) do
        if p:IsA("BasePart") and p.CanCollide then
            p.CanCollide = false
        end
    end
end)

-- ==================== SKILL SYSTEM (NON-BLOCKING) ====================
-- Mỗi skill chạy trong coroutine riêng, KHÔNG dùng task.wait() block thread chính
local SkillQueue = {}   -- {key, holdTime, spawnTime}

-- Hàm nhấn phím thực sự qua VIM
local function PressKey(keyCode, hold)
    task.spawn(function()
        -- Nhấn xuống
        pcall(function() VIM:SendKeyEvent(true,  keyCode, false, game) end)
        if hold and hold > 0 then
            task.wait(hold)
        end
        -- Nhả ra
        pcall(function() VIM:SendKeyEvent(false, keyCode, false, game) end)
    end)
end

-- Spam skill theo weaponType, chạy song song hoàn toàn
local SkillThreads = {}
local function StopAllSkillThreads()
    for k,v in pairs(SkillThreads) do
        if v and coroutine.status(v)~="dead" then
            pcall(function() task.cancel(v) end)
        end
        SkillThreads[k] = nil
    end
end

local function StartSkillLoop(wType)
    StopAllSkillThreads()
    local wCFG = CFG["Items"][wType]
    if not wCFG or not wCFG.Enable then return end

    for keyName, skillCFG in pairs(wCFG.Skills or {}) do
        if skillCFG.Enable then
            local delay   = wCFG.Delay or FastDelay
            local hold    = skillCFG.HoldTime or 0
            local keyEnum = Enum.KeyCode[keyName]
            if keyEnum then
                -- Mỗi skill chạy vòng lặp riêng, độc lập hoàn toàn
                SkillThreads[keyName] = task.spawn(function()
                    while S.AttackEnabled and S.Running do
                        PressKey(keyEnum, hold)
                        task.wait(delay)
                    end
                end)
            end
        end
    end
end

-- ==================== AUTO ATTACK (FIRE REMOTE) ====================
-- Chạy ở thread riêng tốc độ cao, KHÔNG phụ thuộc skill loop
task.spawn(function()
    while true do
        task.wait(FastDelay * 0.5)   -- Nhanh gấp đôi FastDelay
        if not S.AttackEnabled or not S.Running or S.InSafeZone then continue end

        local c   = GetChar()
        local hrp = GetHRP()
        if not c or not hrp then continue end

        -- Thu thập tất cả mục tiêu xung quanh (60 studs)
        local targets = {}
        for _, folder in ipairs({workspace:FindFirstChild("Enemies"), workspace:FindFirstChild("Characters")}) do
            if folder then
                for _, model in ipairs(folder:GetChildren()) do
                    if model ~= c then
                        local mHRP = model:FindFirstChild("HumanoidRootPart")
                        local mHum = model:FindFirstChild("Humanoid")
                        if mHRP and mHum and mHum.Health > 0 then
                            if (mHRP.Position - hrp.Position).Magnitude <= 60 then
                                for _, part in ipairs(model:GetChildren()) do
                                    if part:IsA("BasePart") then
                                        table.insert(targets, {model, part})
                                        break
                                    end
                                end
                            end
                        end
                    end
                end
            end
        end

        -- Ưu tiên State.Target vào đầu danh sách
        if S.Target and IsAlive(S.Target) then
            local tHRP = S.Target.Character:FindFirstChild("HumanoidRootPart")
            if tHRP then
                local dist = (tHRP.Position - hrp.Position).Magnitude
                if dist <= 80 then
                    local head = S.Target.Character:FindFirstChild("Head")
                    table.insert(targets, 1, {S.Target.Character, head or tHRP})
                end
            end
        end

        if #targets == 0 then continue end

        local tool = c:FindFirstChildOfClass("Tool")
        if not tool then continue end

        local wType = tool:GetAttribute("WeaponType") or "Melee"

        -- Gửi remote attack (từ file gốc)
        pcall(function()
            local net = require(RS.Modules.Net)
            net:RemoteEvent("RegisterHit", true)
            RS.Modules.Net["RE/RegisterAttack"]:FireServer()

            local head = targets[1][1]:FindFirstChild("Head")
            if head then
                RS.Modules.Net["RE/RegisterHit"]:FireServer(
                    head, targets, {},
                    tostring(LP.UserId):sub(2,4)..tostring(coroutine.running()):sub(11,15)
                )
                -- Bypass cloneref
                if NetRemote and NetSeed then
                    pcall(function()
                        local seed = RS.Modules.Net.seed:InvokeServer()
                        cloneref(NetRemote):FireServer(
                            string.gsub("RE/RegisterHit", ".", function(p)
                                return string.char(bit32.bxor(string.byte(p),
                                    math.floor(workspace:GetServerTimeNow()/10%10)+1))
                            end),
                            bit32.bxor(NetSeed+909090, seed*2),
                            head, targets
                        )
                    end)
                end
            end
        end)

        -- Bắt đầu skill loop cho weapon hiện tại (tự detect đổi vũ khí)
        if not SkillThreads["_active_" .. wType] then
            StopAllSkillThreads()
            SkillThreads["_active_" .. wType] = true
            StartSkillLoop(wType)
        end
    end
end)

-- ==================== FLY SYSTEM (Ổn định, không rớt) ====================
local FLY_SPEED = 350

-- Vòng lặp bay chính chạy mỗi frame
RunService.Heartbeat:Connect(function(dt)
    if S.InSafeZone or not S.Running then return end

    local hrp = GetHRP()
    local hum = GetHum()
    if not hrp or not hum then return end

    if not S.Target or not IsAlive(S.Target) then
        -- Không có target: hover tại chỗ (không rớt)
        SetBV(Vector3.new(0,0,0))
        return
    end

    local tChar = S.Target.Character
    local tHRP  = tChar and tChar:FindFirstChild("HumanoidRootPart")
    if not tHRP then return end

    local myPos = hrp.Position
    local tPos  = tHRP.Position + Vector3.new(0, 3, 0)
    local dist  = (tPos - myPos).Magnitude

    hum.PlatformStand = true
    Gravity(false)

    if dist > 8 then
        -- BAY ĐẾN TARGET: tính hướng thẳng, bỏ qua Y nếu Y gần nhau
        local dir
        local yDiff = math.abs(tPos.Y - myPos.Y)
        if yDiff < 5 then
            -- Bay phẳng
            dir = Vector3.new(tPos.X - myPos.X, 0, tPos.Z - myPos.Z).Unit
        else
            -- Bay theo góc tự nhiên
            dir = (tPos - myPos).Unit
        end

        local vel = dir * FLY_SPEED
        SetBV(vel)
        SetBG(CFrame.lookAt(myPos, myPos + dir))
        ClearMover("__BP__")
    else
        -- ĐÃ ĐẾN NƠI: Bám sát, đứng yên không rớt
        SetBV(Vector3.new(0,0,0))
        -- Xoay nhìn vào target
        SetBG(CFrame.lookAt(myPos, tHRP.Position))
        -- Cố định vị trí
        SetBP(Vector3.new(myPos.X, tPos.Y, myPos.Z))
    end
end)

-- ==================== SAFE ZONE ====================
task.spawn(function()
    while task.wait(0.3) do
        if not S.Running then break end
        if not CFG["SafeZone"]["Enable"] then continue end

        local hum = GetHum()
        local hrp = GetHRP()
        if not hum or not hrp then continue end

        local low  = CFG["SafeZone"]["LowHealth"]
        local full = CFG["SafeZone"]["MaxHealth"]
        local safeY= CFG["SafeZone"]["Teleport Y"]

        if hum.Health > 0 and hum.Health <= low and not S.InSafeZone then
            S.InSafeZone = true
            S.AttackEnabled = false
            StopAllSkillThreads()
            ClearFly()
            -- Teleport lên cao để hồi máu
            hrp.CFrame = CFrame.new(hrp.Position.X, safeY, hrp.Position.Z)
            -- Bay lên (hover)
            Gravity(false)
            SetBV(Vector3.new(0,0,0))

        elseif S.InSafeZone and hum.Health >= full then
            S.InSafeZone = false
            S.AttackEnabled = true
            -- Bay xuống lại target
            Gravity(false)
        end
    end
end)

-- ==================== TARGET MANAGEMENT ====================
local function GetAllTargets()
    local list = {}
    for _, p in ipairs(Players:GetPlayers()) do
        if p ~= LP and IsAlive(p) then
            if not (getgenv().AimSettings and getgenv().AimSettings.TeamCheck and p.Team == LP.Team) then
                table.insert(list, p)
            end
        end
    end
    return list
end

local function NextTarget(exclude)
    local all = GetAllTargets()
    if #all == 0 then return nil end
    -- Lọc bỏ exclude
    local filtered = {}
    for _, p in ipairs(all) do
        if p ~= exclude then table.insert(filtered, p) end
    end
    if #filtered == 0 then return all[1] end
    return filtered[math.random(1, #filtered)]
end

-- ==================== WEBHOOK ====================
local function Webhook(name, bounty)
    local url = CFG["Setting"]["Url"] or ""
    if url=="" then return end
    pcall(function()
        local body = HttpService:JSONEncode({
            embeds = {{
                title = "🏴‍☠️ Bounty Killed!",
                description = "**Player:** "..name.."\n**Bounty:** 💰 "..tostring(bounty),
                color = 3447003
            }}
        })
        game:HttpPost(url, body, false, "application/json")
    end)
end

-- ==================== SERVER HOP ====================
local function HopServer()
    if tick() - S.LastHop < 5 then return end
    S.LastHop = tick()
    task.spawn(function()
        local ok, result = pcall(function()
            return HttpService:JSONDecode(game:HttpGet(
                "https://games.roblox.com/v1/games/"..game.PlaceId.."/servers/Public?sortOrder=Asc&limit=100"
            ))
        end)
        if not ok or not result or not result.data then return end

        local servers = {}
        for _, sv in ipairs(result.data) do
            if sv.id ~= S.JobId and not S.Visited[sv.id] and sv.playing and sv.playing > 0 then
                table.insert(servers, sv)
            end
        end

        if #servers == 0 then
            -- Reset visited nếu hết server
            S.Visited = {}
            return
        end

        local chosen = servers[math.random(1,#servers)]
        S.Visited[chosen.id] = true
        task.wait(CFG["Hop Server"]["Delay Hop"] or 1)
        pcall(function() TS:TeleportToPlaceInstance(game.PlaceId, chosen.id, LP) end)
    end)
end

-- ==================== MAIN HUNT LOOP ====================
task.spawn(function()
    task.wait(3)

    -- Auto join team
    pcall(function()
        local teamName = getgenv().Team
        for _, t in ipairs(game.Teams:GetTeams()) do
            if t.Name:lower():find(teamName:lower()) then
                local remote = (RS:FindFirstChild("Remotes") and RS.Remotes:FindFirstChild("JoinTeam"))
                    or RS:FindFirstChild("JoinTeam")
                if remote then remote:FireServer(t) end
            end
        end
    end)

    while S.Running do
        task.wait(0.15)

        if S.InSafeZone then continue end

        -- Kiểm tra target còn sống không
        if not IsAlive(S.Target) then
            local killed = S.Target
            S.Target = nil

            -- Nếu có target vừa chết -> đếm kill + webhook
            if killed then
                S.KillCount = S.KillCount + 1
                local bounty = 0
                pcall(function()
                    bounty = killed:GetAttribute("Bounty")
                        or (killed.leaderstats and killed.leaderstats:FindFirstChild("Bounty") and killed.leaderstats.Bounty.Value)
                        or 0
                end)
                Webhook(killed.Name, bounty)
            end

            -- Tìm target mới ngay
            S.Target = NextTarget(killed)
            S.TargetTimer = tick()

            -- Reset skill thread khi đổi target
            StopAllSkillThreads()
            SkillThreads = {}
        end

        -- Timeout 2 phút -> skip
        if S.Target and (tick() - S.TargetTimer) >= S.ChaseTimeout then
            local old = S.Target
            S.Target = NextTarget(old)
            S.TargetTimer = tick()
            StopAllSkillThreads()
            SkillThreads = {}
        end

        -- Hết target -> hop server
        if not S.Target then
            if CFG["Hop Server"]["Enable"] then
                HopServer()
            end
            task.wait(2)
            continue
        end
    end
end)

-- ==================== AUTO V3/V4 ====================
task.spawn(function()
    while task.wait(2) do
        if not S.Running then break end
        pcall(function()
            local remotes = RS:FindFirstChild("Remotes")
            if CFG["Auto turn on v4"] then
                local v4 = remotes and remotes:FindFirstChild("ActivateV4")
                if v4 then v4:FireServer() end
            end
            local v3 = remotes and remotes:FindFirstChild("ActivateV3")
            if v3 then v3:FireServer() end
        end)
    end
end)

-- ==================== AIMBOT ====================
getgenv().AimSettings = getgenv().AimSettings or {
    Enabled        = true,
    AimPart        = "HumanoidRootPart",
    MaxDistance    = 2000,
    PrioritizeLowHP= true,
    LowHPWeight    = 0.5,
    Prediction     = 0.135,
    Smoothness     = 0.07,
    TeamCheck      = true,
    ShowFOV        = true,
    FOVSize        = 150,
}

-- FOV Circle
local FOVCircle = Drawing.new("Circle")
FOVCircle.Color         = Color3.fromRGB(255,80,80)
FOVCircle.Thickness     = 1.5
FOVCircle.Filled        = false
FOVCircle.Transparency  = 1
FOVCircle.NumSides      = 64
FOVCircle.Radius        = getgenv().AimSettings.FOVSize

-- Mũi tên aimbot
local Arrow = Drawing.new("Triangle")
Arrow.Color        = Color3.fromRGB(0,255,120)
Arrow.Filled       = true
Arrow.Transparency = 0.5
Arrow.Visible      = false

-- Line từ giữa màn hình đến target
local AimLine = Drawing.new("Line")
AimLine.Color        = Color3.fromRGB(255,200,0)
AimLine.Thickness    = 1.5
AimLine.Transparency = 0.6
AimLine.Visible      = false

RunService.RenderStepped:Connect(function()
    local mousePos = UIS:GetMouseLocation()
    FOVCircle.Position = mousePos
    FOVCircle.Visible  = getgenv().AimSettings.ShowFOV
    FOVCircle.Radius   = getgenv().AimSettings.FOVSize

    if not getgenv().AimSettings.Enabled then
        Arrow.Visible   = false
        AimLine.Visible = false
        return
    end

    -- Target ưu tiên là State.Target đang chase
    local aimTarget = (IsAlive(S.Target) and S.Target) or nil

    -- Nếu không có State.Target thì tìm trong FOV
    if not aimTarget then
        local bestScore = math.huge
        for _, p in ipairs(Players:GetPlayers()) do
            if p ~= LP and IsAlive(p) then
                if getgenv().AimSettings.TeamCheck and p.Team == LP.Team then continue end
                local root = p.Character:FindFirstChild("HumanoidRootPart")
                if root then
                    local sp, onScreen = Camera:WorldToViewportPoint(root.Position)
                    if onScreen then
                        local d = (Vector2.new(sp.X,sp.Y) - mousePos).Magnitude
                        local hum = p.Character:FindFirstChild("Humanoid")
                        local score = d
                        if getgenv().AimSettings.PrioritizeLowHP and hum and hum.MaxHealth>0 then
                            score = score * (hum.Health/hum.MaxHealth + getgenv().AimSettings.LowHPWeight)
                        end
                        if d <= getgenv().AimSettings.FOVSize and score < bestScore then
                            bestScore = score
                            aimTarget = p
                        end
                    end
                end
            end
        end
    end

    if aimTarget and aimTarget.Character then
        local aimPart = aimTarget.Character:FindFirstChild(getgenv().AimSettings.AimPart)
            or aimTarget.Character:FindFirstChild("HumanoidRootPart")
        if not aimPart then
            Arrow.Visible   = false
            AimLine.Visible = false
            return
        end

        -- Prediction
        local vel          = aimPart.Velocity
        local predicted    = aimPart.Position + vel * getgenv().AimSettings.Prediction

        -- Smooth camera
        local cur  = Camera.CFrame
        local look = CFrame.new(cur.Position, predicted)
        Camera.CFrame = cur:Lerp(look, getgenv().AimSettings.Smoothness)

        -- Vẽ mũi tên + line
        local sp, onScreen = Camera:WorldToViewportPoint(predicted)
        if onScreen then
            local center  = Vector2.new(Camera.ViewportSize.X/2, Camera.ViewportSize.Y/2)
            local tScreen = Vector2.new(sp.X, sp.Y)
            local dir2D   = (tScreen - center)
            local unitDir = dir2D.Magnitude > 0 and dir2D.Unit or Vector2.new(0,-1)
            local tip     = center + unitDir * math.min(dir2D.Magnitude, 80)
            local perp    = Vector2.new(-unitDir.Y, unitDir.X)

            Arrow.PointA  = tip
            Arrow.PointB  = tip - unitDir*18 + perp*8
            Arrow.PointC  = tip - unitDir*18 - perp*8
            Arrow.Visible = true

            AimLine.From    = center
            AimLine.To      = tScreen
            AimLine.Visible = true
        else
            -- Target off screen: vẽ mũi tên ở rìa màn hình
            local center  = Vector2.new(Camera.ViewportSize.X/2, Camera.ViewportSize.Y/2)
            local sp2, _  = Camera:WorldToViewportPoint(predicted)
            local edgeDir = (Vector2.new(sp2.X, sp2.Y) - center).Unit
            local edge    = center + edgeDir * 120
            local perp    = Vector2.new(-edgeDir.Y, edgeDir.X)
            Arrow.PointA  = edge
            Arrow.PointB  = edge - edgeDir*18 + perp*8
            Arrow.PointC  = edge - edgeDir*18 - perp*8
            Arrow.Visible = true
            AimLine.Visible = false
        end
    else
        Arrow.Visible   = false
        AimLine.Visible = false
    end
end)

-- ==================== ESP ====================
local ESPs = {}
local function MakeESP(player)
    if ESPs[player] then return end
    local bg = Instance.new("BillboardGui")
    bg.Size          = UDim2.new(0, 160, 0, 45)
    bg.StudsOffset   = Vector3.new(0, 3.5, 0)
    bg.AlwaysOnTop   = true

    local nameL = Instance.new("TextLabel", bg)
    nameL.Size              = UDim2.new(1,0,0.55,0)
    nameL.BackgroundTransparency = 1
    nameL.Text              = player.Name
    nameL.TextColor3        = Color3.fromRGB(255,220,50)
    nameL.TextStrokeTransparency = 0
    nameL.Font              = Enum.Font.GothamBold
    nameL.TextScaled        = true

    local distL = Instance.new("TextLabel", bg)
    distL.Size              = UDim2.new(1,0,0.45,0)
    distL.Position          = UDim2.new(0,0,0.55,0)
    distL.BackgroundTransparency = 1
    distL.TextColor3        = Color3.fromRGB(200,200,200)
    distL.TextStrokeTransparency = 0
    distL.Font              = Enum.Font.Gotham
    distL.TextScaled        = true

    ESPs[player] = {Gui=bg, DistL=distL}

    RunService.RenderStepped:Connect(function()
        local char = player.Character
        if char and char:FindFirstChild("HumanoidRootPart") then
            bg.Parent = char.HumanoidRootPart
            local myHRP = GetHRP()
            if myHRP then
                local d = math.floor((char.HumanoidRootPart.Position - myHRP.Position).Magnitude)
                distL.Text = d.." studs"
                -- Highlight target đang chase
                nameL.TextColor3 = (S.Target == player) and Color3.fromRGB(255,80,80) or Color3.fromRGB(255,220,50)
            end
        end
    end)
end

for _, p in ipairs(Players:GetPlayers()) do if p~=LP then MakeESP(p) end end
Players.PlayerAdded:Connect(function(p) MakeESP(p) end)
Players.PlayerRemoving:Connect(function(p)
    if ESPs[p] then
        if ESPs[p].Gui then ESPs[p].Gui:Destroy() end
        ESPs[p] = nil
    end
end)

-- ==================== UI ====================
-- Dọn UI cũ nếu có
local oldGui = LP.PlayerGui:FindFirstChild("BountyUI")
if oldGui then oldGui:Destroy() end

local SG = Instance.new("ScreenGui", LP.PlayerGui)
SG.Name          = "BountyUI"
SG.ResetOnSpawn  = false
SG.ZIndexBehavior= Enum.ZIndexBehavior.Sibling

-- === Main Panel ===
local Main = Instance.new("Frame", SG)
Main.Size                 = UDim2.new(0, 380, 0, 230)
Main.Position             = UDim2.new(0.5,-190, 0.5,-115)
Main.BackgroundColor3     = Color3.fromRGB(8,10,18)
Main.BackgroundTransparency = 0.45
Main.BorderSizePixel      = 0
Main.ZIndex               = 10

Instance.new("UICorner", Main).CornerRadius = UDim.new(0,14)

local stroke = Instance.new("UIStroke", Main)
stroke.Color       = Color3.fromRGB(0,180,255)
stroke.Thickness   = 2
stroke.Transparency= 0.2

-- Avatar nền mờ bao phủ panel
local AvatarBG = Instance.new("ImageLabel", Main)
AvatarBG.Size                  = UDim2.new(1,0,1,0)
AvatarBG.BackgroundTransparency= 1
AvatarBG.Image                 = "rbxthumb://type=AvatarHeadShot&id=16060333448&w=420&h=420"
AvatarBG.ImageTransparency     = 0.5
AvatarBG.ScaleType             = Enum.ScaleType.Stretch
AvatarBG.ZIndex                = 11
Instance.new("UICorner", AvatarBG).CornerRadius = UDim.new(0,14)

-- Title
local Title = Instance.new("TextLabel", Main)
Title.Size               = UDim2.new(1,0,0.28,0)
Title.Position           = UDim2.new(0,0,0.03,0)
Title.BackgroundTransparency=1
Title.Text               = "Switch Hub ( Bounty )"
Title.TextColor3         = Color3.fromRGB(80,200,255)
Title.Font               = Enum.Font.GothamBlack
Title.TextScaled         = true
Title.ZIndex             = 13

-- Target
local TargLbl = Instance.new("TextLabel", Main)
TargLbl.Size             = UDim2.new(0.9,0,0.18,0)
TargLbl.Position         = UDim2.new(0.05,0,0.35,0)
TargLbl.BackgroundTransparency=1
TargLbl.Text             = "🎯 Target: Searching..."
TargLbl.TextColor3       = Color3.fromRGB(255,255,255)
TargLbl.Font             = Enum.Font.GothamBold
TargLbl.TextScaled       = true
TargLbl.ZIndex           = 13

-- Distance
local DistLbl = Instance.new("TextLabel", Main)
DistLbl.Size             = UDim2.new(0.9,0,0.15,0)
DistLbl.Position         = UDim2.new(0.05,0,0.54,0)
DistLbl.BackgroundTransparency=1
DistLbl.Text             = "📏 Distance: --"
DistLbl.TextColor3       = Color3.fromRGB(180,180,180)
DistLbl.Font             = Enum.Font.Gotham
DistLbl.TextScaled       = true
DistLbl.ZIndex           = 13

-- Kill + Timer
local StatusLbl = Instance.new("TextLabel", Main)
StatusLbl.Size           = UDim2.new(0.9,0,0.14,0)
StatusLbl.Position       = UDim2.new(0.05,0,0.70,0)
StatusLbl.BackgroundTransparency=1
StatusLbl.Text           = "💀 Kills: 0  |  ⏱ 120s"
StatusLbl.TextColor3     = Color3.fromRGB(100,255,140)
StatusLbl.Font           = Enum.Font.GothamBold
StatusLbl.TextScaled     = true
StatusLbl.ZIndex         = 13

-- SafeZone indicator
local SafeLbl = Instance.new("TextLabel", Main)
SafeLbl.Size             = UDim2.new(0.9,0,0.12,0)
SafeLbl.Position         = UDim2.new(0.05,0,0.85,0)
SafeLbl.BackgroundTransparency=1
SafeLbl.Text             = ""
SafeLbl.TextColor3       = Color3.fromRGB(255,100,100)
SafeLbl.Font             = Enum.Font.GothamBold
SafeLbl.TextScaled       = true
SafeLbl.ZIndex           = 13

-- === Toggle Button (Góc trái, tròn) ===
local TogBtn = Instance.new("ImageButton", SG)
TogBtn.Size              = UDim2.new(0,55,0,55)
TogBtn.Position          = UDim2.new(0,12,0.5,-27)
TogBtn.BackgroundColor3  = Color3.fromRGB(15,15,25)
TogBtn.BorderSizePixel   = 0
TogBtn.ZIndex            = 25
Instance.new("UICorner", TogBtn).CornerRadius = UDim.new(1,0)

local togStroke = Instance.new("UIStroke", TogBtn)
togStroke.Color    = Color3.fromRGB(255,255,255)
togStroke.Thickness= 2

local togAvt = Instance.new("ImageLabel", TogBtn)
togAvt.Size                   = UDim2.new(1,-6,1,-6)
togAvt.Position               = UDim2.new(0,3,0,3)
togAvt.BackgroundTransparency = 1
togAvt.Image                  = "rbxthumb://type=AvatarHeadShot&id=16060333448&w=150&h=150"
Instance.new("UICorner", togAvt).CornerRadius = UDim.new(1,0)

TogBtn.MouseButton1Click:Connect(function()
    S.UIVisible = not S.UIVisible
    Main.Visible = S.UIVisible
end)

-- === Skip Player Button (Góc phải trên) ===
local SkipBtn = Instance.new("TextButton", SG)
SkipBtn.Size             = UDim2.new(0,120,0,36)
SkipBtn.Position         = UDim2.new(1,-135,0,12)
SkipBtn.BackgroundColor3 = Color3.fromRGB(255,255,255)
SkipBtn.TextColor3       = Color3.fromRGB(0,0,0)
SkipBtn.Text             = "⏭  Skip Player"
SkipBtn.Font             = Enum.Font.GothamBold
SkipBtn.TextSize         = 13
SkipBtn.BorderSizePixel  = 0
SkipBtn.ZIndex           = 25
Instance.new("UICorner", SkipBtn).CornerRadius = UDim.new(0,8)

SkipBtn.MouseButton1Click:Connect(function()
    local old = S.Target
    S.Target = NextTarget(old)
    S.TargetTimer = tick()
    StopAllSkillThreads()
    SkillThreads = {}
end)

-- UI Update
RunService.RenderStepped:Connect(function()
    -- Kill + Timer
    local timeLeft = S.Target and math.max(0, S.ChaseTimeout-(tick()-S.TargetTimer)) or 0
    StatusLbl.Text = string.format("💀 Kills: %d  |  ⏱ %ds", S.KillCount, math.floor(timeLeft))

    if IsAlive(S.Target) then
        local tChar = S.Target.Character
        TargLbl.Text = "🎯 Target: " .. S.Target.Name

        local tHRP  = tChar:FindFirstChild("HumanoidRootPart")
        local myHRP = GetHRP()
        if tHRP and myHRP then
            local d = math.floor((tHRP.Position-myHRP.Position).Magnitude)
            DistLbl.Text = "📏 Distance: "..d.." studs"
        end
        Title.Text = string.format("Switch Hub ( Bounty ) | %ds", math.floor(timeLeft))
    else
        TargLbl.Text = "🎯 Target: Searching..."
        DistLbl.Text = "📏 Distance: --"
        Title.Text   = "Switch Hub ( Bounty )"
    end

    SafeLbl.Text = S.InSafeZone and "🛡 SAFE ZONE - Recovering HP..." or ""
end)

-- ==================== RESPAWN HANDLER ====================
LP.CharacterAdded:Connect(function(char)
    task.wait(1.5)
    Gravity(false)
    NoclipEnabled = true
    -- Rejoin team
    pcall(function()
        local teamName = getgenv().Team
        for _, t in ipairs(game.Teams:GetTeams()) do
            if t.Name:lower():find(teamName:lower()) then
                local r = (RS:FindFirstChild("Remotes") and RS.Remotes:FindFirstChild("JoinTeam")) or RS:FindFirstChild("JoinTeam")
                if r then r:FireServer(t) end
            end
        end
    end)
end)
if LP.Character then
    Gravity(false)
    NoclipEnabled = true
end

-- ==================== INIT NOTIFICATION ====================
print("[BountyHunter Pro v2] Loaded | Team: "..(getgenv().Team or "Pirates"))
pcall(function()
    StarterGui:SetCore("SendNotification", {
        Title   = "🏴‍☠️ Bounty Hunter Pro v2",
        Text    = "Loaded! Team: "..(getgenv().Team or "Pirates"),
        Duration= 5
    })
end)
