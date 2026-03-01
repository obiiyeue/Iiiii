-- ============================================================
-- BOUNTY HUNTER PRO - BLOX FRUITS
-- Tích hợp: Attack, Aimbot, Fly, SafeZone, ServerHop, UI
-- ============================================================

repeat task.wait() until game:IsLoaded() and game.Players.LocalPlayer

-- ======================== SERVICES ========================
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local TweenService = game:GetService("TweenService")
local HttpService = game:GetService("HttpService")
local StarterGui = game:GetService("StarterGui")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local VirtualUser = game:GetService("VirtualUser")

local LocalPlayer = Players.LocalPlayer
local Camera = workspace.CurrentCamera
local Mouse = LocalPlayer:GetMouse()

-- ======================== CONFIG (từ script ngoài) ========================
getgenv().Team = getgenv().Team or "Pirates"

getgenv().Config = getgenv().Config or {
    ["SafeZone"] = {
        ["Enable"] = true,
        ["LowHealth"] = 4500,
        ["MaxHealth"] = 6000,
        ["Teleport Y"] = 9999
    },
    ["Hop Server"] = {
        ["Enable"] = true,
        ["Hop When No Target"] = true,
        ["Hop When Low Player"] = false,
        ["Min Player"] = 0,
        ["Delay Hop"] = 1,
        ["Save Joined Server"] = true
    },
    ["Select Region"] = {
        ["Enabled"] = true,
        ["Region"] = {
            ["Singapore"] = true,
            ["United States"] = false,
            ["Netherlands"] = false,
            ["Germany"] = false,
            ["India"] = false,
            ["Australia"] = false
        }
    },
    ["Setting"] = {
        ["World"] = 3,
        ["Fast Delay"] = 0.45,
        ["Url"] = "",
        ["Server Hop"] = 1
    },
    ["Auto turn on v4"] = true,
    ["Items"] = {
        ["Melee"] = {
            Enable = true,
            Delay = 0.4,
            Skills = {
                Z = {Enable = true, HoldTime = 0.3},
                X = {Enable = true, HoldTime = 0.2},
                C = {Enable = true, HoldTime = 0.5}
            }
        },
        ["Sword"] = {
            Enable = true,
            Delay = 0.5,
            Skills = {
                Z = {Enable = true, HoldTime = 1},
                X = {Enable = true, HoldTime = 0}
            }
        }
    }
}

local Config = getgenv().Config
local FastDelay = Config["Setting"]["Fast Delay"] or 0.45

-- ======================== STATE ========================
local State = {
    Running = true,
    Target = nil,
    TargetTimer = 0,
    InSafeZone = false,
    UIVisible = true,
    KillCount = 0,
    VisitedServers = {},
    LastHopTime = 0,
    CurrentJobId = game.JobId,
    ChaseTimeout = 120, -- 2 phút
}

-- ======================== REMOTE EVENT SETUP (Attack Code) ========================
local v1 = next
local RemoteSources = {
    ReplicatedStorage:FindFirstChild("Util"),
    ReplicatedStorage:FindFirstChild("Common"),
    ReplicatedStorage:FindFirstChild("Remotes"),
    ReplicatedStorage:FindFirstChild("Assets"),
    ReplicatedStorage:FindFirstChild("FX"),
}
local u4 = nil
local u5 = nil
local v3 = nil

for _, v6 in ipairs(RemoteSources) do
    if v6 then
        for _, v10 in ipairs(v6:GetChildren()) do
            if v10:IsA('RemoteEvent') and v10:GetAttribute('Id') then
                u5 = v10:GetAttribute('Id')
                u4 = v10
            end
        end
        v6.ChildAdded:Connect(function(p11)
            if p11:IsA('RemoteEvent') and p11:GetAttribute('Id') then
                u5 = p11:GetAttribute('Id')
                u4 = p11
            end
        end)
    end
end

-- ======================== AIMBOT SETTINGS ========================
getgenv().AimSettings = {
    Enabled = true,
    AimPart = "HumanoidRootPart",
    MaxDistance = 2000,
    PrioritizeLowHP = true,
    LowHPWeight = 0.5,
    Prediction = 0.135,
    Smoothness = 0.06,
    TeamCheck = true,
    ShowFOV = true,
    FOVSize = 150
}

local FOVCircle = Drawing.new("Circle")
FOVCircle.Color = Color3.fromRGB(255, 80, 80)
FOVCircle.Thickness = 1.5
FOVCircle.Filled = false
FOVCircle.Transparency = 1
FOVCircle.NumSides = 64
FOVCircle.Radius = getgenv().AimSettings.FOVSize

-- Arrow Drawing cho Aimbot
local AimArrow = Drawing.new("Triangle")
AimArrow.Color = Color3.fromRGB(0, 255, 100)
AimArrow.Filled = true
AimArrow.Transparency = 0.7
AimArrow.Visible = false

-- ======================== NOCLIP + ANTI GRAVITY ========================
local function SetNoclip(enabled)
    local char = LocalPlayer.Character
    if char then
        for _, part in pairs(char:GetDescendants()) do
            if part:IsA("BasePart") then
                part.CanCollide = not enabled
            end
        end
    end
end

local function SetGravity(enabled)
    workspace.Gravity = enabled and 196.2 or 0
end

local function SetBodyVelocity(char, velocity)
    local hrp = char and char:FindFirstChild("HumanoidRootPart")
    if hrp then
        local bv = hrp:FindFirstChild("__BV__") or Instance.new("BodyVelocity")
        bv.Name = "__BV__"
        bv.MaxForce = Vector3.new(1e9, 1e9, 1e9)
        bv.Velocity = velocity
        bv.Parent = hrp
    end
end

local function ClearBodyVelocity(char)
    local hrp = char and char:FindFirstChild("HumanoidRootPart")
    if hrp then
        local bv = hrp:FindFirstChild("__BV__")
        if bv then bv:Destroy() end
    end
end

-- ======================== JOIN TEAM ========================
local function JoinTeam()
    pcall(function()
        local teamName = getgenv().Team or "Pirates"
        for _, team in pairs(game.Teams:GetTeams()) do
            if team.Name:lower():find(teamName:lower()) then
                local joinRemote = ReplicatedStorage:FindFirstChild("JoinTeam") 
                    or ReplicatedStorage:FindFirstChild("Remotes") and ReplicatedStorage.Remotes:FindFirstChild("JoinTeam")
                if joinRemote then
                    joinRemote:FireServer(team)
                end
            end
        end
    end)
end

-- ======================== SERVER HOP ========================
local function GetServerList()
    local servers = {}
    local ok, result = pcall(function()
        local url = "https://games.roblox.com/v1/games/" .. game.PlaceId .. "/servers/Public?sortOrder=Asc&limit=100"
        local data = HttpService:JSONDecode(game:HttpGet(url))
        for _, s in pairs(data.data) do
            if s.id ~= State.CurrentJobId and not State.VisitedServers[s.id] then
                if s.playing and s.playing > 0 then
                    table.insert(servers, s)
                end
            end
        end
    end)
    return servers
end

local function HopServer()
    if tick() - State.LastHopTime < 5 then return end
    State.LastHopTime = tick()
    
    local servers = GetServerList()
    if #servers > 0 then
        local chosen = servers[math.random(1, #servers)]
        State.VisitedServers[chosen.id] = true
        task.delay(Config["Hop Server"]["Delay Hop"] or 1, function()
            game:GetService("TeleportService"):TeleportToPlaceInstance(game.PlaceId, chosen.id, LocalPlayer)
        end)
    else
        -- Reset visited nếu không còn server
        State.VisitedServers = {}
        HopServer()
    end
end

-- ======================== WEBHOOK ========================
local function SendWebhook(playerName, bounty)
    local url = Config["Setting"]["Url"] or ""
    if url == "" then return end
    pcall(function()
        local payload = HttpService:JSONEncode({
            embeds = {{
                title = "🏴‍☠️ Bounty Hunted!",
                description = "**Target:** " .. playerName .. "\n**Bounty:** " .. tostring(bounty) .. " 💰",
                color = 16711680
            }}
        })
        game:HttpPost(url, payload, false, "application/json")
    end)
end

-- ======================== ESP ========================
local ESPObjects = {}

local function CreateESP(player)
    if ESPObjects[player] then return end
    local billGui = Instance.new("BillboardGui")
    billGui.Size = UDim2.new(0, 200, 0, 50)
    billGui.StudsOffset = Vector3.new(0, 3, 0)
    billGui.AlwaysOnTop = true

    local nameLabel = Instance.new("TextLabel", billGui)
    nameLabel.Size = UDim2.new(1, 0, 0.6, 0)
    nameLabel.BackgroundTransparency = 1
    nameLabel.Text = player.Name
    nameLabel.TextColor3 = Color3.fromRGB(255, 255, 0)
    nameLabel.TextStrokeTransparency = 0
    nameLabel.Font = Enum.Font.GothamBold
    nameLabel.TextScaled = true

    local distLabel = Instance.new("TextLabel", billGui)
    distLabel.Size = UDim2.new(1, 0, 0.4, 0)
    distLabel.Position = UDim2.new(0, 0, 0.6, 0)
    distLabel.BackgroundTransparency = 1
    distLabel.TextColor3 = Color3.fromRGB(255, 200, 0)
    distLabel.TextStrokeTransparency = 0
    distLabel.Font = Enum.Font.Gotham
    distLabel.TextScaled = true

    ESPObjects[player] = {Gui = billGui, DistLabel = distLabel}

    local function UpdateESP()
        if player.Character and player.Character:FindFirstChild("HumanoidRootPart") then
            billGui.Parent = player.Character.HumanoidRootPart
            if LocalPlayer.Character and LocalPlayer.Character:FindFirstChild("HumanoidRootPart") then
                local dist = (player.Character.HumanoidRootPart.Position - LocalPlayer.Character.HumanoidRootPart.Position).Magnitude
                distLabel.Text = string.format("%.0f studs", dist)
            end
        end
    end

    RunService.RenderStepped:Connect(UpdateESP)
end

local function RemoveESP(player)
    if ESPObjects[player] then
        if ESPObjects[player].Gui then
            ESPObjects[player].Gui:Destroy()
        end
        ESPObjects[player] = nil
    end
end

for _, p in pairs(Players:GetPlayers()) do
    if p ~= LocalPlayer then CreateESP(p) end
end
Players.PlayerAdded:Connect(function(p) CreateESP(p) end)
Players.PlayerRemoving:Connect(function(p) RemoveESP(p) end)

-- ======================== TARGET SELECTION ========================
local function GetValidTargets()
    local targets = {}
    for _, p in pairs(Players:GetPlayers()) do
        if p ~= LocalPlayer and p.Character then
            local hum = p.Character:FindFirstChild("Humanoid")
            local hrp = p.Character:FindFirstChild("HumanoidRootPart")
            if hum and hrp and hum.Health > 0 then
                -- Team check
                if getgenv().AimSettings.TeamCheck and p.Team == LocalPlayer.Team then
                    continue
                end
                table.insert(targets, p)
            end
        end
    end
    return targets
end

local function GetNextTarget(exclude)
    local targets = GetValidTargets()
    if #targets == 0 then return nil end
    -- Không chọn lại người vừa kill hoặc skip
    for _, t in ipairs(targets) do
        if t ~= exclude then return t end
    end
    return targets[1]
end

-- ======================== SMART AIMBOT ========================
local function GetSmartAimTarget()
    local best = nil
    local bestScore = math.huge
    local char = LocalPlayer.Character
    if not char or not char:FindFirstChild("HumanoidRootPart") then return nil end

    for _, p in pairs(Players:GetPlayers()) do
        if p ~= LocalPlayer and p.Character then
            local hum = p.Character:FindFirstChild("Humanoid")
            local root = p.Character:FindFirstChild("HumanoidRootPart")
            if hum and root and hum.Health > 0 then
                if getgenv().AimSettings.TeamCheck and p.Team == LocalPlayer.Team then continue end
                
                local screenPos, onScreen = Camera:WorldToViewportPoint(root.Position)
                local mouseDist = (Vector2.new(screenPos.X, screenPos.Y) - UserInputService:GetMouseLocation()).Magnitude
                local realDist = (char.HumanoidRootPart.Position - root.Position).Magnitude
                
                if onScreen and mouseDist <= getgenv().AimSettings.FOVSize and realDist <= getgenv().AimSettings.MaxDistance then
                    local score = mouseDist
                    if getgenv().AimSettings.PrioritizeLowHP and hum.MaxHealth > 0 then
                        local hp = hum.Health / hum.MaxHealth
                        score = score * (hp + getgenv().AimSettings.LowHPWeight)
                    end
                    -- Ưu tiên target đang bị chase
                    if State.Target and p == State.Target then
                        score = score * 0.1
                    end
                    if score < bestScore then
                        bestScore = score
                        best = p
                    end
                end
            end
        end
    end
    return best
end

-- ======================== FLY TO TARGET ========================
local FlySpeed = 350

local function FlyToTarget(targetChar)
    local char = LocalPlayer.Character
    if not char then return end
    local hrp = char:FindFirstChild("HumanoidRootPart")
    local hum = char:FindFirstChild("Humanoid")
    if not hrp or not hum then return end

    -- Tắt gravity, bật noclip
    SetGravity(false)
    SetNoclip(true)
    hum.PlatformStand = true

    local targetHRP = targetChar and targetChar:FindFirstChild("HumanoidRootPart")
    if not targetHRP then
        hum.PlatformStand = false
        return
    end

    local startPos = hrp.Position
    local endPos = targetHRP.Position + Vector3.new(0, 2, 0)
    local direction = (endPos - startPos).Unit

    -- Bay thẳng không lên xuống (giữ Y cố định khi bay)
    local flatDir = Vector3.new(direction.X, 0, direction.Z).Unit
    local dist = (Vector3.new(endPos.X, startPos.Y, endPos.Z) - Vector3.new(startPos.X, startPos.Y, startPos.Z)).Magnitude

    -- Nếu quá gần thì không cần bay
    if dist < 10 then
        hum.PlatformStand = false
        return
    end

    -- Tween bay thẳng
    local bodyPos = Instance.new("BodyPosition")
    bodyPos.MaxForce = Vector3.new(1e9, 1e9, 1e9)
    bodyPos.D = 1000
    bodyPos.P = 100000
    bodyPos.Position = endPos
    bodyPos.Parent = hrp

    local bodyGyro = Instance.new("BodyGyro")
    bodyGyro.MaxTorque = Vector3.new(1e9, 1e9, 1e9)
    bodyGyro.D = 100
    bodyGyro.CFrame = CFrame.lookAt(hrp.Position, endPos)
    bodyGyro.Parent = hrp

    -- Tính thời gian bay
    local flyTime = dist / FlySpeed
    task.delay(flyTime + 0.5, function()
        if bodyPos.Parent then bodyPos:Destroy() end
        if bodyGyro.Parent then bodyGyro:Destroy() end
        hum.PlatformStand = false
    end)
end

-- ======================== SKILL SPAM ========================
local function UseSkills(weaponType)
    local items = Config["Items"]
    local wConfig = items and items[weaponType]
    if not wConfig or not wConfig.Enable then return end

    local delay = wConfig.Delay or FastDelay

    for key, skillData in pairs(wConfig.Skills or {}) do
        if skillData.Enable then
            task.spawn(function()
                -- Bấm xuống
                VirtualUser:Button1Down(Vector2.new(Camera.ViewportSize.X/2, Camera.ViewportSize.Y/2))
                task.wait(0.05)
                -- Dùng key skill
                VirtualUser:CaptureController()
                local success = pcall(function()
                    local keyCode = Enum.KeyCode[key]
                    if keyCode then
                        VirtualUser:Button1Up(Vector2.new(Camera.ViewportSize.X/2, Camera.ViewportSize.Y/2))
                        game:GetService("VirtualInputManager"):SendKeyEvent(true, keyCode, false, game)
                        task.wait(skillData.HoldTime or 0.1)
                        game:GetService("VirtualInputManager"):SendKeyEvent(false, keyCode, false, game)
                    end
                end)
                task.wait(delay)
            end)
        end
    end
end

-- ======================== AUTO ATTACK ========================
_G.AutoAttack = true

task.spawn(function()
    while task.wait(FastDelay) do
        if not _G.AutoAttack or not State.Running then continue end
        
        local char = LocalPlayer.Character
        local hrp = char and char:FindFirstChild("HumanoidRootPart")
        if not hrp then continue end

        local targets = {}
        for _, folder in ipairs({workspace:FindFirstChild("Enemies"), workspace:FindFirstChild("Characters")}) do
            if folder then
                for _, model in ipairs(folder:GetChildren()) do
                    local tHRP = model:FindFirstChild("HumanoidRootPart")
                    local tHum = model:FindFirstChild("Humanoid")
                    if model ~= char and tHRP and tHum and tHum.Health > 0 then
                        if (tHRP.Position - hrp.Position).Magnitude <= 60 then
                            for _, part in ipairs(model:GetChildren()) do
                                if part:IsA("BasePart") then
                                    table.insert(targets, {model, part})
                                end
                            end
                        end
                    end
                end
            end
        end

        -- Cũng nhắm vào State.Target nếu có
        if State.Target and State.Target.Character then
            local tHRP = State.Target.Character:FindFirstChild("HumanoidRootPart")
            local tHead = State.Target.Character:FindFirstChild("Head")
            if tHRP and (tHRP.Position - hrp.Position).Magnitude <= 80 then
                table.insert(targets, 1, {State.Target.Character, tHead or tHRP})
            end
        end

        local tool = char:FindFirstChildOfClass("Tool")
        if #targets > 0 and tool then
            local wType = tool:GetAttribute("WeaponType") or "Melee"
            pcall(function()
                local net = require(ReplicatedStorage.Modules.Net)
                net:RemoteEvent("RegisterHit", true)
                ReplicatedStorage.Modules.Net["RE/RegisterAttack"]:FireServer()
                
                local head = targets[1][1]:FindFirstChild("Head")
                if head then
                    ReplicatedStorage.Modules.Net["RE/RegisterHit"]:FireServer(
                        head, targets, {},
                        tostring(LocalPlayer.UserId):sub(2,4) .. tostring(coroutine.running()):sub(11,15)
                    )
                    if u4 then
                        pcall(function()
                            cloneref(u4):FireServer(
                                string.gsub("RE/RegisterHit", ".", function(p)
                                    return string.char(bit32.bxor(string.byte(p), math.floor(workspace:GetServerTimeNow() / 10 % 10) + 1))
                                end),
                                bit32.bxor(u5 + 909090, ReplicatedStorage.Modules.Net.seed:InvokeServer() * 2),
                                head, targets
                            )
                        end)
                    end
                end
            end)

            -- Spam skills theo config
            UseSkills(wType)
        end
    end
end)

-- ======================== AUTO V3/V4 ========================
task.spawn(function()
    while task.wait(1) do
        if not State.Running then break end
        pcall(function()
            -- V4
            if Config["Auto turn on v4"] then
                local v4Remote = ReplicatedStorage:FindFirstChild("Remotes") and ReplicatedStorage.Remotes:FindFirstChild("ActivateV4")
                if v4Remote then v4Remote:FireServer() end
            end
            -- V3
            local v3Remote = ReplicatedStorage:FindFirstChild("Remotes") and ReplicatedStorage.Remotes:FindFirstChild("ActivateV3")  
            if v3Remote then v3Remote:FireServer() end
        end)
    end
end)

-- ======================== SAFE ZONE ========================
task.spawn(function()
    while task.wait(0.5) do
        if not State.Running then break end
        if not Config["SafeZone"]["Enable"] then continue end

        local char = LocalPlayer.Character
        local hum = char and char:FindFirstChild("Humanoid")
        local hrp = char and char:FindFirstChild("HumanoidRootPart")
        if not hum or not hrp then continue end

        local lowHP = Config["SafeZone"]["LowHealth"]
        local maxHP = Config["SafeZone"]["MaxHealth"]
        local safeY = Config["SafeZone"]["Teleport Y"]

        if hum.Health <= lowHP and not State.InSafeZone then
            State.InSafeZone = true
            SetGravity(false)
            SetNoclip(true)
            -- Bay lên cao
            hrp.CFrame = CFrame.new(hrp.Position.X, safeY, hrp.Position.Z)
        elseif hum.Health >= maxHP and State.InSafeZone then
            State.InSafeZone = false
            SetGravity(true)
            SetNoclip(false)
            -- Bay xuống lại target
            if State.Target then
                FlyToTarget(State.Target.Character)
            end
        end
    end
end)

-- ======================== MAIN BOUNTY HUNT LOOP ========================
task.spawn(function()
    task.wait(3)
    JoinTeam()
    
    while State.Running do
        task.wait(0.1)
        if State.InSafeZone then continue end

        local char = LocalPlayer.Character
        local hrp = char and char:FindFirstChild("HumanoidRootPart")
        if not char or not hrp then task.wait(1) continue end

        -- Tìm target mới nếu chưa có
        if not State.Target or not State.Target.Character 
            or not State.Target.Character:FindFirstChild("Humanoid")
            or State.Target.Character.Humanoid.Health <= 0 then
            
            local prev = State.Target
            State.Target = GetNextTarget(prev)
            State.TargetTimer = tick()
            
            -- Nếu target vừa die -> webhook + chuyển target
            if prev and prev.Character and prev.Character:FindFirstChild("Humanoid") 
                and prev.Character.Humanoid.Health <= 0 then
                State.KillCount = State.KillCount + 1
                local bounty = 0
                pcall(function()
                    bounty = prev:GetAttribute("Bounty") or prev.leaderstats and prev.leaderstats.Bounty and prev.leaderstats.Bounty.Value or 0
                end)
                SendWebhook(prev.Name, bounty)
            end
        end

        -- Hết target -> hop server
        if not State.Target then
            if Config["Hop Server"]["Enable"] then
                HopServer()
            end
            task.wait(2)
            continue
        end

        -- Timeout 2 phút -> chuyển target
        if tick() - State.TargetTimer >= State.ChaseTimeout then
            local old = State.Target
            State.Target = GetNextTarget(old)
            State.TargetTimer = tick()
            continue
        end

        -- Bay đến target
        local targetHRP = State.Target.Character and State.Target.Character:FindFirstChild("HumanoidRootPart")
        if targetHRP then
            local dist = (targetHRP.Position - hrp.Position).Magnitude
            
            if dist > 15 then
                -- Bay thẳng đến target
                SetGravity(false)
                SetNoclip(true)
                
                local dir = (targetHRP.Position - hrp.Position).Unit
                -- Bay phẳng (không lên xuống) trừ khi target ở Y khác xa
                local targetPos = targetHRP.Position + Vector3.new(0, 2, 0)
                
                local bodyPos = hrp:FindFirstChild("__BP__") or Instance.new("BodyPosition")
                bodyPos.Name = "__BP__"
                bodyPos.MaxForce = Vector3.new(1e9, 1e9, 1e9)
                bodyPos.D = 500
                bodyPos.P = 50000
                bodyPos.Position = targetPos
                bodyPos.Parent = hrp
                
                local bodyGyro = hrp:FindFirstChild("__BG__") or Instance.new("BodyGyro")
                bodyGyro.Name = "__BG__"
                bodyGyro.MaxTorque = Vector3.new(1e9, 1e9, 1e9)
                bodyGyro.D = 100
                bodyGyro.CFrame = CFrame.lookAt(hrp.Position, targetPos)
                bodyGyro.Parent = hrp
                
                -- Đặt velocity để bay với tốc độ FlySpeed
                local bv = hrp:FindFirstChild("__BV2__") or Instance.new("BodyVelocity")
                bv.Name = "__BV2__"
                bv.MaxForce = Vector3.new(1e9, 1e9, 1e9)
                bv.Velocity = dir * FlySpeed
                bv.Parent = hrp
                
            else
                -- Đã đến gần -> dừng bay, tấn công
                for _, name in ipairs({"__BP__", "__BG__", "__BV2__"}) do
                    local obj = hrp:FindFirstChild(name)
                    if obj then obj:Destroy() end
                end
                SetGravity(false) -- Vẫn tắt gravity để không rớt khi spam skill
                SetNoclip(true)
                
                -- Bám sát target
                local bv = hrp:FindFirstChild("__BV2__") or Instance.new("BodyVelocity")
                bv.Name = "__BV2__"
                bv.MaxForce = Vector3.new(1e9, 1e9, 1e9)
                bv.Velocity = Vector3.new(0, 0, 0)
                bv.Parent = hrp
                hrp.CFrame = CFrame.new(targetHRP.Position + Vector3.new(0, 2, 0), targetHRP.Position)
            end
        end
    end
end)

-- ======================== AIMBOT LOOP ========================
local AimActive = false

UserInputService.InputBegan:Connect(function(input)
    if input.UserInputType == Enum.UserInputType.MouseButton2 then
        AimActive = true
    end
end)
UserInputService.InputEnded:Connect(function(input)
    if input.UserInputType == Enum.UserInputType.MouseButton2 then
        AimActive = false
    end
end)

RunService.RenderStepped:Connect(function()
    FOVCircle.Position = UserInputService:GetMouseLocation()
    FOVCircle.Visible = getgenv().AimSettings.ShowFOV
    FOVCircle.Radius = getgenv().AimSettings.FOVSize

    if not getgenv().AimSettings.Enabled then
        AimArrow.Visible = false
        return
    end

    -- Luôn aim vào State.Target nếu đang hunt
    local aimTarget = State.Target

    if not aimTarget or not aimTarget.Character then
        -- Fallback: tìm target gần nhất trong FOV
        aimTarget = nil
        local best = nil
        local bestDist = math.huge
        for _, p in pairs(Players:GetPlayers()) do
            if p ~= LocalPlayer and p.Character then
                local hum = p.Character:FindFirstChild("Humanoid")
                local root = p.Character:FindFirstChild("HumanoidRootPart")
                if hum and root and hum.Health > 0 then
                    local sp, onScreen = Camera:WorldToViewportPoint(root.Position)
                    if onScreen then
                        local d = (Vector2.new(sp.X, sp.Y) - UserInputService:GetMouseLocation()).Magnitude
                        if d < getgenv().AimSettings.FOVSize and d < bestDist then
                            bestDist = d
                            best = p
                        end
                    end
                end
            end
        end
        aimTarget = best
    end

    if aimTarget and aimTarget.Character then
        local aimPart = aimTarget.Character:FindFirstChild(getgenv().AimSettings.AimPart) 
            or aimTarget.Character:FindFirstChild("HumanoidRootPart")
        if aimPart then
            local velocity = aimPart.Velocity
            local predictedPos = aimPart.Position + (velocity * getgenv().AimSettings.Prediction)
            
            local curCFrame = Camera.CFrame
            local targetLook = CFrame.new(curCFrame.Position, predictedPos)
            Camera.CFrame = curCFrame:Lerp(targetLook, getgenv().AimSettings.Smoothness)

            -- Vẽ mũi tên chỉ vào target
            local screenPos, onScreen = Camera:WorldToViewportPoint(predictedPos)
            if onScreen then
                local center = Vector2.new(Camera.ViewportSize.X/2, Camera.ViewportSize.Y/2)
                local targetScreen = Vector2.new(screenPos.X, screenPos.Y)
                local arrowDir = (targetScreen - center).Unit
                local arrowLen = 20
                
                AimArrow.PointA = center + arrowDir * 60
                AimArrow.PointB = center + arrowDir * 60 + Vector2.new(-arrowDir.Y, arrowDir.X) * 8
                AimArrow.PointC = center + arrowDir * 60 - Vector2.new(-arrowDir.Y, arrowDir.X) * 8
                AimArrow.Visible = true
            else
                AimArrow.Visible = false
            end
        end
    else
        AimArrow.Visible = false
    end
end)

-- ======================== UI ========================
local ScreenGui = Instance.new("ScreenGui")
ScreenGui.Name = "BountyHunterUI"
ScreenGui.ResetOnSpawn = false
ScreenGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
ScreenGui.Parent = LocalPlayer.PlayerGui

-- ---- Nền mờ + Avatar + Chữ chính ----
local MainFrame = Instance.new("Frame", ScreenGui)
MainFrame.Size = UDim2.new(0, 400, 0, 250)
MainFrame.Position = UDim2.new(0.5, -200, 0.5, -125)
MainFrame.BackgroundColor3 = Color3.fromRGB(10, 10, 20)
MainFrame.BackgroundTransparency = 0.5
MainFrame.BorderSizePixel = 0
MainFrame.ZIndex = 10

local corner = Instance.new("UICorner", MainFrame)
corner.CornerRadius = UDim.new(0, 12)

-- Border glow
local stroke = Instance.new("UIStroke", MainFrame)
stroke.Color = Color3.fromRGB(0, 200, 255)
stroke.Thickness = 2
stroke.Transparency = 0.3

-- Avatar viền bao quanh
local AvatarFrame = Instance.new("Frame", MainFrame)
AvatarFrame.Size = UDim2.new(1, 0, 1, 0)
AvatarFrame.BackgroundTransparency = 1
AvatarFrame.ZIndex = 11

local AvatarImg = Instance.new("ImageLabel", AvatarFrame)
AvatarImg.Size = UDim2.new(1, 0, 1, 0)
AvatarImg.BackgroundTransparency = 1
AvatarImg.Image = "rbxthumb://type=AvatarHeadShot&id=16060333448&w=420&h=420"
AvatarImg.ImageTransparency = 0.5
AvatarImg.ScaleType = Enum.ScaleType.Stretch
AvatarImg.ZIndex = 11

local uiCornerAvt = Instance.new("UICorner", AvatarImg)
uiCornerAvt.CornerRadius = UDim.new(0, 12)

-- Tiêu đề lớn
local TitleLabel = Instance.new("TextLabel", MainFrame)
TitleLabel.Size = UDim2.new(1, 0, 0.3, 0)
TitleLabel.Position = UDim2.new(0, 0, 0.05, 0)
TitleLabel.BackgroundTransparency = 1
TitleLabel.Text = "Switch Hub ( Bounty )"
TitleLabel.TextColor3 = Color3.fromRGB(100, 200, 255)
TitleLabel.Font = Enum.Font.GothamBlack
TitleLabel.TextScaled = true
TitleLabel.ZIndex = 12

-- Target info
local TargetLabel = Instance.new("TextLabel", MainFrame)
TargetLabel.Size = UDim2.new(0.9, 0, 0.2, 0)
TargetLabel.Position = UDim2.new(0.05, 0, 0.42, 0)
TargetLabel.BackgroundTransparency = 1
TargetLabel.Text = "Target: None"
TargetLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
TargetLabel.Font = Enum.Font.GothamBold
TargetLabel.TextScaled = true
TargetLabel.ZIndex = 12

local DistLabel = Instance.new("TextLabel", MainFrame)
DistLabel.Size = UDim2.new(0.9, 0, 0.15, 0)
DistLabel.Position = UDim2.new(0.05, 0, 0.63, 0)
DistLabel.BackgroundTransparency = 1
DistLabel.Text = "Distance: --"
DistLabel.TextColor3 = Color3.fromRGB(200, 200, 200)
DistLabel.Font = Enum.Font.Gotham
DistLabel.TextScaled = true
DistLabel.ZIndex = 12

local KillLabel = Instance.new("TextLabel", MainFrame)
KillLabel.Size = UDim2.new(0.9, 0, 0.15, 0)
KillLabel.Position = UDim2.new(0.05, 0, 0.8, 0)
KillLabel.BackgroundTransparency = 1
KillLabel.Text = "Kills: 0"
KillLabel.TextColor3 = Color3.fromRGB(100, 255, 150)
KillLabel.Font = Enum.Font.Gotham
KillLabel.TextScaled = true
KillLabel.ZIndex = 12

-- ---- Toggle Button (góc trái, hình tròn) ----
local ToggleBtn = Instance.new("ImageButton", ScreenGui)
ToggleBtn.Size = UDim2.new(0, 55, 0, 55)
ToggleBtn.Position = UDim2.new(0, 15, 0.5, -27)
ToggleBtn.BackgroundColor3 = Color3.fromRGB(20, 20, 30)
ToggleBtn.BorderSizePixel = 0
ToggleBtn.ZIndex = 20

local toggleCorner = Instance.new("UICorner", ToggleBtn)
toggleCorner.CornerRadius = UDim.new(1, 0)

local toggleStroke = Instance.new("UIStroke", ToggleBtn)
toggleStroke.Color = Color3.fromRGB(255, 255, 255)
toggleStroke.Thickness = 2

local toggleAvt = Instance.new("ImageLabel", ToggleBtn)
toggleAvt.Size = UDim2.new(1, -4, 1, -4)
toggleAvt.Position = UDim2.new(0, 2, 0, 2)
toggleAvt.BackgroundTransparency = 1
toggleAvt.Image = "rbxthumb://type=AvatarHeadShot&id=16060333448&w=150&h=150"

local toggleAvtCorner = Instance.new("UICorner", toggleAvt)
toggleAvtCorner.CornerRadius = UDim.new(1, 0)

ToggleBtn.MouseButton1Click:Connect(function()
    State.UIVisible = not State.UIVisible
    MainFrame.Visible = State.UIVisible
end)

-- ---- Skip Player Button (góc phải trên) ----
local SkipBtn = Instance.new("TextButton", ScreenGui)
SkipBtn.Size = UDim2.new(0, 110, 0, 35)
SkipBtn.Position = UDim2.new(1, -125, 0, 15)
SkipBtn.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
SkipBtn.TextColor3 = Color3.fromRGB(0, 0, 0)
SkipBtn.Text = "⏭ Skip Player"
SkipBtn.Font = Enum.Font.GothamBold
SkipBtn.TextSize = 13
SkipBtn.BorderSizePixel = 0
SkipBtn.ZIndex = 20

local skipCorner = Instance.new("UICorner", SkipBtn)
skipCorner.CornerRadius = UDim.new(0, 8)

SkipBtn.MouseButton1Click:Connect(function()
    local old = State.Target
    State.Target = GetNextTarget(old)
    State.TargetTimer = tick()
end)

-- Update UI loop
RunService.RenderStepped:Connect(function()
    KillLabel.Text = "Kills: " .. State.KillCount
    
    if State.Target and State.Target.Character then
        TargetLabel.Text = "Target: " .. State.Target.Name
        local tHRP = State.Target.Character:FindFirstChild("HumanoidRootPart")
        local myHRP = LocalPlayer.Character and LocalPlayer.Character:FindFirstChild("HumanoidRootPart")
        if tHRP and myHRP then
            local d = math.floor((tHRP.Position - myHRP.Position).Magnitude)
            DistLabel.Text = "Distance: " .. d .. " studs"
        end
        
        -- Hiện thời gian còn lại
        local timeLeft = math.max(0, State.ChaseTimeout - (tick() - State.TargetTimer))
        TitleLabel.Text = string.format("Switch Hub ( Bounty ) | %ds", math.floor(timeLeft))
    else
        TargetLabel.Text = "Target: Searching..."
        DistLabel.Text = "Distance: --"
        TitleLabel.Text = "Switch Hub ( Bounty )"
    end
end)

-- ======================== CHARACTER RESPAWN HANDLER ========================
local function OnCharacterAdded(char)
    task.wait(1)
    SetGravity(false)
    SetNoclip(true)
    JoinTeam()
end

LocalPlayer.CharacterAdded:Connect(OnCharacterAdded)
if LocalPlayer.Character then OnCharacterAdded(LocalPlayer.Character) end

-- ======================== DONE ========================
print("[BountyHunter] Script loaded! Team: " .. (getgenv().Team or "Pirates"))
StarterGui:SetCore("SendNotification", {
    Title = "🏴‍☠️ Bounty Hunter Pro",
    Text = "Script đã kích hoạt! Team: " .. (getgenv().Team or "Pirates"),
    Duration = 5
})
