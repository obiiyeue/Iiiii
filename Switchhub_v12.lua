--[[
    ╔═══════════════════════════════════════════════════════════╗
    ║         Switch Hub - Bounty Hunting Ultimate V12          ║
    ║                    By: tbobiito                           ║
    ╚═══════════════════════════════════════════════════════════╝
    V12 REWRITE - Fix hoàn toàn:
    ✅ Không bị rớt khi spam skill - dùng CFrame teleport mỗi Heartbeat
    ✅ Equip đúng Melee (slot 1) và Sword (slot 2) theo thứ tự backpack
    ✅ Skill loop: 1 thread duy nhất, không spawn mới mỗi frame
    ✅ Timer 60s chỉ bắt đầu khi đã đến gần target
    ✅ Bám sát target liên tục, không bị mất
    ✅ Noclip tự bật khi load
    ✅ Spam hop khi không có player
]]

repeat task.wait() until game:IsLoaded()
repeat task.wait() until game.Players.LocalPlayer
repeat task.wait() until game.Players.LocalPlayer.Character

-- ══════════════════════════════════════════════
-- SERVICES
-- ══════════════════════════════════════════════
local Players     = game:GetService("Players")
local RunService  = game:GetService("RunService")
local HttpService = game:GetService("HttpService")
local TeleportSvc = game:GetService("TeleportService")
local RS          = game:GetService("ReplicatedStorage")
local VIM         = game:GetService("VirtualInputManager")

local lp   = Players.LocalPlayer
local pGui = lp:WaitForChild("PlayerGui")

-- ══════════════════════════════════════════════
-- CONFIG
-- ══════════════════════════════════════════════
local CFG = {
    AttackDist    = 8,
    FlySpeed      = 350,
    MaxHuntTime   = 60,
    SkillKeys     = {
        Melee = {Enum.KeyCode.Z, Enum.KeyCode.X, Enum.KeyCode.C, Enum.KeyCode.V},
        Sword = {Enum.KeyCode.Z, Enum.KeyCode.X, Enum.KeyCode.C},
    },
    SkipList      = {},
    JoinedServers = {},
    SafeHP        = 500,
    MaxHP         = 2000,
    MinHopPlayers = 9,
    MaxHopPlayers = 16,
}

-- ══════════════════════════════════════════════
-- STATE
-- ══════════════════════════════════════════════
local ST = {
    On          = true,
    Noclip      = true,
    Target      = nil,
    HuntStart   = nil,
    Flying      = false,
    InSafe      = false,
    Arrived     = false,
    WeaponPhase = "Melee",
}

-- ══════════════════════════════════════════════
-- CHARACTER
-- ══════════════════════════════════════════════
local Char, Hum, HRP

local function RefreshChar()
    Char = lp.Character
    if not Char then return end
    Hum  = Char:FindFirstChildOfClass("Humanoid")
    HRP  = Char:FindFirstChild("HumanoidRootPart")
end
RefreshChar()

-- Forward declare
local FindTarget, SetTarget, StopFly

lp.CharacterAdded:Connect(function(c)
    Char = c
    Hum  = c:WaitForChild("Humanoid")
    HRP  = c:WaitForChild("HumanoidRootPart")
    ST.Target  = nil
    ST.Flying  = false
    ST.Arrived = false
    ST.InSafe  = false
    ST.HuntStart = nil
    task.wait(2)
    if ST.On then
        local t = FindTarget()
        if t then SetTarget(t) end
    end
end)

-- ══════════════════════════════════════════════
-- UI
-- ══════════════════════════════════════════════
pcall(function()
    local o = game:GetService("CoreGui"):FindFirstChild("SwitchHubUI")
    if o then o:Destroy() end
end)
pcall(function()
    local o = pGui:FindFirstChild("SwitchHubUI")
    if o then o:Destroy() end
end)

local SG = Instance.new("ScreenGui")
SG.Name            = "SwitchHubUI"
SG.ResetOnSpawn    = false
SG.ZIndexBehavior  = Enum.ZIndexBehavior.Sibling
SG.DisplayOrder    = 999
SG.IgnoreGuiInset  = true
pcall(function() SG.Parent = game:GetService("CoreGui") end)
if not SG.Parent or SG.Parent == game then SG.Parent = pGui end

local BgImg = Instance.new("ImageLabel", SG)
BgImg.Size               = UDim2.fromScale(1,1)
BgImg.BackgroundTransparency = 1
BgImg.Image              = "rbxassetid://16060333448"
BgImg.ImageTransparency  = 0.5
BgImg.ScaleType          = Enum.ScaleType.Stretch
BgImg.ZIndex             = 1

local function MakeLabel(text, color, sizeY, posY)
    local lbl = Instance.new("TextLabel", SG)
    lbl.Size                  = UDim2.new(1,0,0,sizeY)
    lbl.Position              = UDim2.new(0,0,0.5,posY)
    lbl.BackgroundTransparency = 1
    lbl.Text                  = text
    lbl.TextColor3            = color
    lbl.TextScaled            = true
    lbl.Font                  = Enum.Font.Gotham
    lbl.TextStrokeTransparency = 0.3
    lbl.TextStrokeColor3      = Color3.fromRGB(0,0,0)
    lbl.ZIndex                = 5
    return lbl
end

local TitleLbl  = MakeLabel("Switch Hub", Color3.fromRGB(80,200,255), 180, -220)
TitleLbl.Font   = Enum.Font.GothamBold
TitleLbl.TextStrokeTransparency = 0
TitleLbl.TextStrokeColor3 = Color3.fromRGB(255,255,255)

local SubLbl    = MakeLabel("Kill ALL  •  350 Speed  •  Spam Hop  •  Noclip AUTO", Color3.fromRGB(220,220,220), 44, -38)
local TargetLbl = MakeLabel("🎯  Searching...", Color3.fromRGB(255,255,255), 40, 14)
local StatusLbl = MakeLabel("⚡  Starting...", Color3.fromRGB(100,255,100), 36, 60)
local TimerLbl  = MakeLabel("", Color3.fromRGB(255,200,50), 30, 100)

local function MakeBtn(text, color, size, pos)
    local btn = Instance.new("TextButton", SG)
    btn.Size             = size
    btn.Position         = pos
    btn.BackgroundColor3 = color
    btn.BorderSizePixel  = 0
    btn.Text             = text
    btn.TextColor3       = Color3.fromRGB(255,255,255)
    btn.TextSize         = 22
    btn.Font             = Enum.Font.GothamBold
    btn.ZIndex           = 10
    Instance.new("UICorner", btn).CornerRadius = UDim.new(0,14)
    return btn
end

local SkipBtn   = MakeBtn("⏭  Skip",       Color3.fromRGB(255,255,255), UDim2.fromOffset(150,55), UDim2.new(1,-160,0,15))
SkipBtn.TextColor3 = Color3.fromRGB(0,0,0)
local ToggleBtn = MakeBtn("✅  ON",         Color3.fromRGB(40,200,90),   UDim2.fromOffset(150,55), UDim2.new(1,-160,0,80))
local NoclipBtn = MakeBtn("🧱  Noclip OFF", Color3.fromRGB(80,80,80),    UDim2.fromOffset(150,55), UDim2.new(0,10,0,15))
NoclipBtn.TextSize = 18

-- ══════════════════════════════════════════════
-- ATTACK REMOTE
-- ══════════════════════════════════════════════
local u4, u5 = nil, nil
local function FindBypassRemote()
    for _, name in ipairs({"Util","Common","Remotes","Assets","FX"}) do
        local f = RS:FindFirstChild(name)
        if not f then continue end
        for _, child in pairs(f:GetChildren()) do
            if child:IsA("RemoteEvent") and child:GetAttribute("Id") then
                u5 = child:GetAttribute("Id"); u4 = child
            end
        end
        pcall(function()
            f.ChildAdded:Connect(function(c)
                if c:IsA("RemoteEvent") and c:GetAttribute("Id") then
                    u5 = c:GetAttribute("Id"); u4 = c
                end
            end)
        end)
    end
end
FindBypassRemote()

-- ══════════════════════════════════════════════
-- ATTACK
-- ══════════════════════════════════════════════
local function GetAttackTargets()
    if not HRP then return {} end
    local list = {}
    local function scan(folder)
        if not folder then return end
        for _, char in pairs(folder:GetChildren()) do
            local root  = char:FindFirstChild("HumanoidRootPart")
            local human = char:FindFirstChild("Humanoid")
            if root and human and human.Health > 0 and char ~= Char then
                if (root.Position - HRP.Position).Magnitude <= 60 then
                    for _, part in pairs(char:GetChildren()) do
                        if part:IsA("BasePart") then
                            table.insert(list, {char, part})
                        end
                    end
                end
            end
        end
    end
    scan(workspace:FindFirstChild("Characters"))
    scan(workspace:FindFirstChild("Enemies"))
    return list
end

local function FireAttack(targets)
    if #targets == 0 then return end
    pcall(function()
        local Net  = RS.Modules.Net
        local head = targets[1][1]:FindFirstChild("Head") or targets[1][2]
        require(Net):RemoteEvent("RegisterHit", true)
        Net["RE/RegisterAttack"]:FireServer()
        Net["RE/RegisterHit"]:FireServer(head, targets, {},
            {Id=u5, Distance=60, EffectId="", Duration=1.5,
             Increment=0.08, Priority=0, OriginData={}, InCombo=false})
        if u4 then u4:FireServer(head, targets, {}) end
    end)
end

-- ══════════════════════════════════════════════
-- EQUIP - Melee = slot 1, Sword = slot 2
-- ══════════════════════════════════════════════
local function GetTools()
    local tools = {}
    for _, t in pairs(lp.Backpack:GetChildren()) do
        if t:IsA("Tool") then table.insert(tools, t) end
    end
    for _, t in pairs(Char and Char:GetChildren() or {}) do
        if t:IsA("Tool") then table.insert(tools, t) end
    end
    return tools
end

local SWORD_KEYWORDS = {"sword","katana","blade","saber","cutlass","rapier","knife","dagger"}

local function IsSword(name)
    name = name:lower()
    for _, kw in ipairs(SWORD_KEYWORDS) do
        if name:find(kw) then return true end
    end
    return false
end

local function EquipMelee()
    if not Char or not Hum then return end
    local tools = GetTools()
    -- Ưu tiên tool không phải sword
    for _, t in ipairs(tools) do
        if not IsSword(t.Name) then
            pcall(function() Hum:EquipTool(t) end)
            return
        end
    end
    -- Fallback: slot đầu tiên
    if tools[1] then pcall(function() Hum:EquipTool(tools[1]) end) end
end

local function EquipSword()
    if not Char or not Hum then return end
    local tools = GetTools()
    -- Ưu tiên tool là sword
    for _, t in ipairs(tools) do
        if IsSword(t.Name) then
            pcall(function() Hum:EquipTool(t) end)
            return
        end
    end
    -- Fallback: slot 2, nếu không có thì slot 1
    local t = tools[2] or tools[1]
    if t then pcall(function() Hum:EquipTool(t) end) end
end

local function EquipCurrent()
    if ST.WeaponPhase == "Melee" then EquipMelee() else EquipSword() end
end

-- ══════════════════════════════════════════════
-- HITBOX
-- ══════════════════════════════════════════════
local function MakeHitbox(p)
    pcall(function()
        local c = p.Character; if not c then return end
        local root = c:FindFirstChild("HumanoidRootPart")
        local head = c:FindFirstChild("Head")
        if root then root.Size = Vector3.new(35,35,35); root.Transparency = 0.8; root.CanCollide = false end
        if head then head.Size = Vector3.new(35,35,35); head.Transparency = 0.8; head.CanCollide = false end
    end)
end

-- ══════════════════════════════════════════════
-- SKILL LOOP - 1 thread duy nhất, tự quản lý
-- ══════════════════════════════════════════════
local skillActive = false

local function StartSkillLoop()
    if skillActive then return end
    skillActive = true
    task.spawn(function()
        while skillActive do
            if not (ST.On and ST.Arrived and ST.Target) then
                task.wait(0.1)
            else
                local keys = ST.WeaponPhase == "Melee"
                    and CFG.SkillKeys.Melee
                    or  CFG.SkillKeys.Sword
                for _, k in ipairs(keys) do
                    if not skillActive then break end
                    pcall(function() VIM:SendKeyEvent(true,  k, false, game) end)
                    task.wait(0.05)
                    pcall(function() VIM:SendKeyEvent(false, k, false, game) end)
                    task.wait(0.08)
                end
            end
        end
    end)
end

local function StopSkillLoop()
    skillActive = false
end

-- Bắt đầu skill loop ngay (tự kiểm tra điều kiện bên trong)
StartSkillLoop()

-- ══════════════════════════════════════════════
-- ANTI-FALL: Heartbeat giữ vị trí khi đang attack
-- Đây là fix cốt lõi cho việc bị rớt xuống biển
-- ══════════════════════════════════════════════
local lockPosition = nil  -- Vector3 hoặc nil

RunService.Heartbeat:Connect(function()
    if not lockPosition then return end
    if not HRP then return end
    if not ST.Arrived then lockPosition = nil; return end

    -- Nếu lệch quá 3 studs → kéo về ngay
    if (HRP.Position - lockPosition).Magnitude > 3 then
        HRP.CFrame = CFrame.new(lockPosition)
    end
end)

-- ══════════════════════════════════════════════
-- FLY + CHASE
-- ══════════════════════════════════════════════
StopFly = function()
    ST.Flying    = false
    lockPosition = nil
    StopSkillLoop()
    -- Dọn body movers
    pcall(function()
        if not HRP then return end
        for _, v in pairs(HRP:GetChildren()) do
            if v:IsA("BodyVelocity") or v:IsA("BodyGyro") or v:IsA("BodyPosition") then
                v:Destroy()
            end
        end
    end)
end

local function FlyToTarget()
    if not ST.Target or not ST.Target.Character then StopFly(); return end
    if not HRP then StopFly(); return end
    if ST.Flying then return end
    ST.Flying = true

    -- Khởi động lại skill loop (đã bị stop trước đó)
    StartSkillLoop()

    task.spawn(function()
        local bv = Instance.new("BodyVelocity")
        bv.MaxForce = Vector3.new(1e9, 1e9, 1e9)
        bv.Velocity = Vector3.zero
        bv.Parent   = HRP

        local bg = Instance.new("BodyGyro")
        bg.MaxTorque = Vector3.new(0, 1e9, 0)
        bg.D  = 200
        bg.P  = 3000
        bg.Parent = HRP

        while ST.Flying and ST.Target do
            local tc = ST.Target and ST.Target.Character
            if not tc or not HRP then break end
            local tRoot = tc:FindFirstChild("HumanoidRootPart")
            if not tRoot then break end

            local tPos   = tRoot.Position + Vector3.new(0, 3, 0)
            local myPos  = HRP.Position
            local dist   = (tPos - myPos).Magnitude

            -- Hướng mặt về target
            bg.CFrame = CFrame.new(myPos, Vector3.new(tPos.X, myPos.Y, tPos.Z))

            if dist <= CFG.AttackDist then
                -- SÁT TARGET: dừng bay, khoá vị trí bằng Heartbeat
                bv.Velocity  = Vector3.zero
                lockPosition = tRoot.Position + Vector3.new(0, 3, 0)

                if not ST.Arrived then
                    ST.Arrived = true
                    if not ST.HuntStart then
                        ST.HuntStart = tick()
                        print("⏱ Timer — arrived: "..ST.Target.Name)
                    end
                end

                task.spawn(function() FireAttack(GetAttackTargets()) end)

            elseif dist <= CFG.AttackDist + 10 then
                -- VÙNG ĐỆM: tiến chậm
                lockPosition = nil
                local dir   = (tPos - myPos).Unit
                bv.Velocity = dir * 80
                if not ST.Arrived then
                    ST.Arrived = true
                    if not ST.HuntStart then ST.HuntStart = tick() end
                end
                task.spawn(function() FireAttack(GetAttackTargets()) end)

            else
                -- XA: bay nhanh
                lockPosition = nil
                ST.Arrived   = false
                local dir    = (tPos - myPos).Unit
                bv.Velocity  = dir * CFG.FlySpeed
            end

            task.wait(0.05)
        end

        pcall(function() bv:Destroy() end)
        pcall(function() bg:Destroy() end)
        ST.Flying = false
    end)
end

-- ══════════════════════════════════════════════
-- WEAPON PHASE SWITCH mỗi 3s
-- ══════════════════════════════════════════════
task.spawn(function()
    while task.wait(3) do
        if not ST.On or not ST.Target or not ST.Arrived then continue end
        pcall(function()
            ST.WeaponPhase = ST.WeaponPhase == "Melee" and "Sword" or "Melee"
            EquipCurrent()
            print("🔄 Phase → "..ST.WeaponPhase)
        end)
    end
end)

-- ══════════════════════════════════════════════
-- FIND TARGET - bounty cao nhất
-- ══════════════════════════════════════════════
FindTarget = function()
    if not HRP then return nil end
    local best, bestBounty = nil, -1
    for _, p in pairs(Players:GetPlayers()) do
        if p == lp then continue end
        if table.find(CFG.SkipList, p.Name) then continue end
        local c = p.Character
        if not c then continue end
        local root = c:FindFirstChild("HumanoidRootPart")
        local h    = c:FindFirstChild("Humanoid")
        if not root or not h or h.Health <= 0 then continue end
        local bounty = p:GetAttribute("Bounty") or 0
        if bounty > bestBounty then
            bestBounty = bounty
            best       = p
        end
    end
    return best
end

-- ══════════════════════════════════════════════
-- SAFE ZONE / HP
-- ══════════════════════════════════════════════
local function CheckHP()
    if not Hum then return false end
    return Hum.Health < CFG.SafeHP
end

local function GoSafe()
    if ST.InSafe then return end
    ST.InSafe = true
    StopFly()
    ST.Target  = nil
    ST.Arrived = false
    if HRP then HRP.CFrame = HRP.CFrame * CFrame.new(0, 500, 0) end
    task.spawn(function()
        while ST.InSafe do
            if Hum and Hum.Health >= CFG.MaxHP then ST.InSafe = false end
            task.wait(1)
        end
        if ST.On then
            local t = FindTarget()
            if t then SetTarget(t) end
        end
    end)
end

-- ══════════════════════════════════════════════
-- SERVER HOP
-- ══════════════════════════════════════════════
local isHopping     = false
local hopAttempt    = 0
local cachedServers = {}
local lastFetch     = 0

local function FetchServers()
    if tick() - lastFetch < 15 and #cachedServers > 0 then return cachedServers end
    lastFetch     = tick()
    cachedServers = {}
    pcall(function()
        local url  = "https://games.roblox.com/v1/games/"..game.PlaceId.."/servers/Public?sortOrder=Desc&limit=100"
        local data = HttpService:JSONDecode(game:HttpGet(url))
        local pref, fall = {}, {}
        for _, s in pairs(data.data or {}) do
            if s.id == game.JobId then continue end
            local n = tonumber(s.playing) or 0
            if n >= CFG.MinHopPlayers and n <= CFG.MaxHopPlayers then
                table.insert(pref, {id=s.id, playing=n})
            elseif n >= 3 then
                table.insert(fall, {id=s.id, playing=n})
            end
        end
        table.sort(pref, function(a,b) return a.playing > b.playing end)
        table.sort(fall, function(a,b) return a.playing > b.playing end)
        for _, s in ipairs(pref) do table.insert(cachedServers, s) end
        for _, s in ipairs(fall) do table.insert(cachedServers, s) end
    end)
    return cachedServers
end

local function HopServer()
    if isHopping then return end
    isHopping  = true
    hopAttempt = 0
    StatusLbl.Text = "🌐  Spam Hopping..."
    TargetLbl.Text = "🔄  Scanning servers..."
    if HRP then HRP.CFrame = HRP.CFrame * CFrame.new(0, 9999, 0) end
    task.spawn(function()
        while isHopping do
            hopAttempt = hopAttempt + 1
            local servers = FetchServers()
            local cands   = {}
            for _, s in ipairs(servers) do
                if not table.find(CFG.JoinedServers, s.id) then
                    table.insert(cands, s)
                end
            end
            if #cands == 0 then
                CFG.JoinedServers = {}
                cachedServers     = {}
                lastFetch         = 0
                StatusLbl.Text = "♻️  Reset list... (#"..hopAttempt..")"
                task.wait(1.5)
                continue
            end
            local chosen = cands[1]
            table.insert(CFG.JoinedServers, chosen.id)
            print("🌐 Hop #"..hopAttempt.." → "..chosen.playing.." players")
            StatusLbl.Text = "🌐  #"..hopAttempt.." → "..chosen.playing.." players"
            TargetLbl.Text = "🚀  Teleporting..."
            local ok = pcall(function()
                TeleportSvc:TeleportToPlaceInstance(game.PlaceId, chosen.id, lp)
            end)
            if ok then
                task.wait(6)
            else
                task.wait(0.5)
            end
        end
    end)
end

-- ══════════════════════════════════════════════
-- SET TARGET
-- ══════════════════════════════════════════════
SetTarget = function(p)
    StopFly()
    ST.Target    = p
    ST.Arrived   = false
    ST.HuntStart = nil

    if p then
        local bounty = p:GetAttribute("Bounty") or 0
        print("✅ TARGET: "..p.Name.." | 💰"..bounty)
        TargetLbl.Text = "🎯  "..p.Name.." | 💰"..bounty
        StatusLbl.Text = "🚀  Flying to "..p.Name.."..."
        TimerLbl.Text  = "⏱ Đang bay..."
        MakeHitbox(p)
        EquipCurrent()
        FlyToTarget()
    else
        TargetLbl.Text = "🎯  Searching..."
        StatusLbl.Text = "🔍  No target"
        TimerLbl.Text  = ""
    end
end

-- ══════════════════════════════════════════════
-- NOCLIP
-- ══════════════════════════════════════════════
local noclipConn = nil
local function SetNoclip(on)
    ST.Noclip = on
    if on then
        NoclipBtn.BackgroundColor3 = Color3.fromRGB(0,180,80)
        NoclipBtn.Text = "👻  Noclip ON"
        if not noclipConn then
            noclipConn = RunService.Stepped:Connect(function()
                pcall(function()
                    if not ST.Noclip or not Char then return end
                    for _, p in pairs(Char:GetDescendants()) do
                        if p:IsA("BasePart") and p.CanCollide then
                            p.CanCollide = false
                        end
                    end
                end)
            end)
        end
    else
        NoclipBtn.BackgroundColor3 = Color3.fromRGB(80,80,80)
        NoclipBtn.Text = "🧱  Noclip OFF"
        if noclipConn then noclipConn:Disconnect(); noclipConn = nil end
        pcall(function()
            if not Char then return end
            for _, p in pairs(Char:GetDescendants()) do
                if p:IsA("BasePart") then p.CanCollide = true end
            end
        end)
    end
end

SetNoclip(true)

NoclipBtn.MouseButton1Click:Connect(function() SetNoclip(not ST.Noclip) end)

lp.CharacterAdded:Connect(function()
    if ST.Noclip then
        task.wait(0.5)
        if noclipConn then noclipConn:Disconnect(); noclipConn = nil end
        SetNoclip(true)
    end
end)

-- ══════════════════════════════════════════════
-- TOGGLE
-- ══════════════════════════════════════════════
ToggleBtn.MouseButton1Click:Connect(function()
    ST.On = not ST.On
    if ST.On then
        ToggleBtn.BackgroundColor3 = Color3.fromRGB(40,200,90)
        ToggleBtn.Text = "✅  ON"
        SetTarget(FindTarget())
    else
        StopFly()
        ST.Target  = nil
        ST.Arrived = false
        ToggleBtn.BackgroundColor3 = Color3.fromRGB(200,50,50)
        ToggleBtn.Text = "❌  OFF"
        StatusLbl.Text = "⏸  Paused"
        TimerLbl.Text  = ""
    end
end)

-- ══════════════════════════════════════════════
-- SKIP
-- ══════════════════════════════════════════════
SkipBtn.MouseButton1Click:Connect(function()
    pcall(function()
        if ST.Target then
            local name = ST.Target.Name
            table.insert(CFG.SkipList, name)
            task.delay(180, function()
                local idx = table.find(CFG.SkipList, name)
                if idx then table.remove(CFG.SkipList, idx) end
            end)
        end
        StopFly()
        ST.Arrived = false
        ST.Target  = nil
        local t = FindTarget()
        if t then SetTarget(t) else HopServer() end
    end)
end)

-- ══════════════════════════════════════════════
-- AUTO JOIN PIRATES
-- ══════════════════════════════════════════════
task.spawn(function()
    task.wait(2)
    pcall(function() RS.Remotes.CommF_:InvokeServer("JoinTeam","Pirates") end)
    pcall(function() RS.Remotes.CommF_:InvokeServer("ChooseTeam","Pirates") end)
    pcall(function()
        for _, sg in pairs(pGui:GetChildren()) do
            for _, v in pairs(sg:GetDescendants()) do
                if v:IsA("TextButton") then
                    local t = v.Text:lower()
                    if t:find("pirate") or t:find("hải tặc") then
                        v.MouseButton1Click:Fire()
                    end
                end
            end
        end
    end)
end)

-- ══════════════════════════════════════════════
-- MAIN LOOP - 0.05s tick
-- ══════════════════════════════════════════════
local noTargetTime = 0
local lastTargetHP = 0
local stuckTimer   = 0

task.spawn(function()
    task.wait(1)
    print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
    print("🔍 SWITCH HUB V12 — KILL ALL + SPAM HOP")
    print("👥 Players: "..#Players:GetPlayers())
    for _, p in pairs(Players:GetPlayers()) do
        if p ~= lp then
            print("→ "..p.Name.." | 💰"..(p:GetAttribute("Bounty") or 0))
        end
    end
    print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
    if ST.On then SetTarget(FindTarget()) end
end)

task.spawn(function()
    while task.wait(0.05) do
        if not ST.On then continue end
        pcall(function()
            if not HRP then RefreshChar(); return end
            if CheckHP() then GoSafe(); return end
            if ST.InSafe then return end

            -- Không có target
            if not ST.Target or not ST.Target.Character then
                if ST.Flying then StopFly() end
                ST.Arrived = false
                local t = FindTarget()
                if t then
                    noTargetTime = 0
                    isHopping    = false
                    SetTarget(t)
                else
                    noTargetTime = noTargetTime + 0.05
                    TargetLbl.Text = "🎯  No players... ("..math.floor(noTargetTime).."s)"
                    StatusLbl.Text = "🔍  Waiting..."
                    TimerLbl.Text  = ""
                    if noTargetTime >= 8 then
                        noTargetTime = 0
                        HopServer()
                    end
                end
                return
            end

            noTargetTime = 0

            local tc    = ST.Target.Character
            local tRoot = tc and tc:FindFirstChild("HumanoidRootPart")
            local tHum  = tc and tc:FindFirstChild("Humanoid")

            -- Target chết / mất
            if not tRoot or not tHum or tHum.Health <= 0 then
                isHopping  = false
                stuckTimer = 0
                SetTarget(FindTarget())
                return
            end

            -- Safe zone detect: HP không giảm 5s khi đang đánh
            if ST.Arrived then
                local hp = tHum.Health
                if hp >= lastTargetHP - 0.5 then
                    stuckTimer = stuckTimer + 0.05
                    if stuckTimer >= 5 then
                        stuckTimer = 0
                        print("⚠️ Safe zone: "..ST.Target.Name)
                        table.insert(CFG.SkipList, ST.Target.Name)
                        task.delay(60, function()
                            local idx = table.find(CFG.SkipList, ST.Target and ST.Target.Name or "")
                            if idx then table.remove(CFG.SkipList, idx) end
                        end)
                        local nxt = FindTarget()
                        if nxt then SetTarget(nxt) else HopServer() end
                        return
                    end
                else
                    stuckTimer = 0
                end
                lastTargetHP = hp
            else
                stuckTimer   = 0
                lastTargetHP = tHum.Health
            end

            -- Timer 60s
            if ST.HuntStart then
                local elapsed   = tick() - ST.HuntStart
                local remaining = math.max(0, CFG.MaxHuntTime - elapsed)
                TimerLbl.Text   = "⏱ "..math.floor(remaining).."s | "..ST.Target.Name
                if elapsed >= CFG.MaxHuntTime then
                    print("⏰ 60s up: "..ST.Target.Name)
                    table.insert(CFG.SkipList, ST.Target.Name)
                    task.delay(180, function()
                        local idx = table.find(CFG.SkipList, ST.Target and ST.Target.Name or "")
                        if idx then table.remove(CFG.SkipList, idx) end
                    end)
                    local nxt = FindTarget()
                    if nxt then SetTarget(nxt) else HopServer() end
                    return
                end
            else
                TimerLbl.Text = "⏱ Đang bay..."
            end

            -- UI update
            local dist   = (tRoot.Position - HRP.Position).Magnitude
            local bounty = ST.Target:GetAttribute("Bounty") or 0
            TargetLbl.Text = "🎯  "..ST.Target.Name.." | "..math.floor(dist).."m | ❤"..math.floor(tHum.Health).." | 💰"..bounty

            -- Giữ fly loop chạy
            if not ST.Flying then
                StatusLbl.Text = ST.Arrived
                    and "⚔  Attacking | "..ST.WeaponPhase
                    or  "🚀  Re-flying → "..ST.Target.Name
                FlyToTarget()
            else
                StatusLbl.Text = ST.Arrived
                    and "⚔  Attack + Lock | "..ST.WeaponPhase
                    or  "🚀  Flying → "..ST.Target.Name.." ("..math.floor(dist).."m)"
            end
        end)
    end
end)

-- ══════════════════════════════════════════════
-- NOTIFICATION
-- ══════════════════════════════════════════════
pcall(function()
    game:GetService("StarterGui"):SetCore("SendNotification", {
        Title   = "Switch Hub V12",
        Text    = "✅ Anti-Fall | Auto Equip | Timer Fix | No Freeze!",
        Duration = 5,
    })
end)
print("✅ Switch Hub V12 — Rewrite hoàn chỉnh!")
