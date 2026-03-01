-- ================================================================
-- BOUNTY HUNTER PRO v3 - BLOX FRUITS
-- + Auto switch Melee/Sword + spam skill
-- + Fullscreen avatar bg
-- + UI mới: Switch Hub to giữa màn hình
-- + Aimbot tự aim khi dùng skill
-- ================================================================
repeat task.wait() until game:IsLoaded() and game.Players.LocalPlayer

-- ==================== SERVICES ====================
local Players    = game:GetService("Players")
local RunService = game:GetService("RunService")
local UIS        = game:GetService("UserInputService")
local HttpService = game:GetService("HttpService")
local StarterGui = game:GetService("StarterGui")
local RS         = game:GetService("ReplicatedStorage")
local TS         = game:GetService("TeleportService")
local VIM        = game:GetService("VirtualInputManager")

local LP         = Players.LocalPlayer
local Camera     = workspace.CurrentCamera

-- ==================== CONFIG ====================
getgenv().Team = getgenv().Team or "Pirates"
getgenv().Config = getgenv().Config or {
    ["SafeZone"]  = {["Enable"]=true,["LowHealth"]=4500,["MaxHealth"]=6000,["Teleport Y"]=9999},
    ["Hop Server"]= {["Enable"]=true,["Hop When No Target"]=true,["Delay Hop"]=1,["Save Joined Server"]=true},
    ["Setting"]   = {["World"]=3,["Fast Delay"]=0.45,["Url"]="",["Server Hop"]=1},
    ["Auto turn on v4"]=true,
    ["Items"]={
        ["Melee"]={Enable=true,Delay=0.4,Skills={
            Z={Enable=true,HoldTime=0.3},
            X={Enable=true,HoldTime=0.2},
            C={Enable=true,HoldTime=0.5},
        }},
        ["Sword"]={Enable=true,Delay=0.5,Skills={
            Z={Enable=true,HoldTime=1.0},
            X={Enable=true,HoldTime=0.0},
        }},
    }
}

local CFG       = getgenv().Config
local FastDelay = CFG["Setting"]["Fast Delay"] or 0.45

-- ==================== STATE ====================
local S = {
    Running        = true,
    Target         = nil,
    TargetTimer    = 0,
    InSafeZone     = false,
    UIVisible      = true,
    KillCount      = 0,
    Visited        = {},
    LastHop        = 0,
    ChaseTimeout   = 120,
    JobId          = game.JobId,
    AttackEnabled  = true,
    CurrentWeapon  = "Melee",
    WeaponSwapTimer= 0,
    SkillActive    = false,
}

-- ==================== REMOTE FINDER ====================
local NetRemote, NetSeed = nil, nil
local function ScanRemotes(folder)
    if not folder then return end
    for _, v in ipairs(folder:GetChildren()) do
        if v:IsA("RemoteEvent") and v:GetAttribute("Id") then
            NetRemote=v; NetSeed=v:GetAttribute("Id")
        end
    end
    folder.ChildAdded:Connect(function(v)
        if v:IsA("RemoteEvent") and v:GetAttribute("Id") then
            NetRemote=v; NetSeed=v:GetAttribute("Id")
        end
    end)
end
for _, n in ipairs({"Util","Common","Remotes","Assets","FX"}) do
    ScanRemotes(RS:FindFirstChild(n))
end

-- ==================== HELPERS ====================
local function GetChar() return LP.Character end
local function GetHRP()  local c=GetChar(); return c and c:FindFirstChild("HumanoidRootPart") end
local function GetHum()  local c=GetChar(); return c and c:FindFirstChild("Humanoid") end

local function IsAlive(p)
    if not p or not p.Character then return false end
    local h=p.Character:FindFirstChild("Humanoid")
    return h and h.Health>0
end

local function ClearMover(name)
    local hrp=GetHRP(); if hrp then local o=hrp:FindFirstChild(name); if o then o:Destroy() end end
end

local function SetBV(vel)
    local hrp=GetHRP(); if not hrp then return end
    local bv=hrp:FindFirstChild("__BV__") or Instance.new("BodyVelocity")
    bv.Name="__BV__"; bv.MaxForce=Vector3.new(1e9,1e9,1e9); bv.Velocity=vel; bv.P=1e5; bv.Parent=hrp
end

local function SetBP(pos)
    local hrp=GetHRP(); if not hrp then return end
    local bp=hrp:FindFirstChild("__BP__") or Instance.new("BodyPosition")
    bp.Name="__BP__"; bp.MaxForce=Vector3.new(1e9,1e9,1e9); bp.D=300; bp.P=5e4; bp.Position=pos; bp.Parent=hrp
end

local function SetBG(cf)
    local hrp=GetHRP(); if not hrp then return end
    local bg=hrp:FindFirstChild("__BG__") or Instance.new("BodyGyro")
    bg.Name="__BG__"; bg.MaxTorque=Vector3.new(1e9,1e9,1e9); bg.D=200; bg.CFrame=cf; bg.Parent=hrp
end

local function ClearFly() ClearMover("__BV__"); ClearMover("__BP__"); ClearMover("__BG__") end
local function Gravity(on) workspace.Gravity = on and 196.2 or 0 end

-- Noclip liên tục mỗi frame
local NoclipEnabled = true
RunService.Stepped:Connect(function()
    if not NoclipEnabled then return end
    local c=GetChar(); if not c then return end
    for _,p in ipairs(c:GetDescendants()) do
        if p:IsA("BasePart") and p.CanCollide then p.CanCollide=false end
    end
end)

-- ==================== WEAPON SWITCH ====================
local WEAPON_SWAP_INTERVAL = 3.5

local function FindToolByType(wType)
    local char=GetChar(); if not char then return nil end
    local held=char:FindFirstChildOfClass("Tool")
    if held and held:GetAttribute("WeaponType")==wType then return held end
    for _,t in ipairs(LP.Backpack:GetChildren()) do
        if t:IsA("Tool") and t:GetAttribute("WeaponType")==wType then return t end
    end
    return nil
end

local function EquipTool(tool)
    if not tool then return end
    pcall(function() local hum=GetHum(); if hum then hum:EquipTool(tool) end end)
end

local function SwapWeapon()
    -- Ưu tiên đổi sang loại kia, nếu không có thì giữ nguyên
    local next_w = S.CurrentWeapon=="Melee" and "Sword" or "Melee"
    local tool = FindToolByType(next_w)
    if tool then
        S.CurrentWeapon = next_w
        EquipTool(tool)
    else
        -- Không có thì thử tìm loại hiện tại
        local cur = FindToolByType(S.CurrentWeapon)
        if cur then EquipTool(cur) end
    end
end

-- ==================== SKILL SYSTEM (NON-BLOCKING) ====================
local SkillThreads = {}

local function StopSkills()
    for k,v in pairs(SkillThreads) do
        pcall(function() if v and type(v)~="boolean" then task.cancel(v) end end)
        SkillThreads[k]=nil
    end
    S.SkillActive=false
end

local function PressKey(keyCode, hold)
    task.spawn(function()
        S.SkillActive=true
        pcall(function() VIM:SendKeyEvent(true,keyCode,false,game) end)
        if hold and hold>0 then task.wait(hold) end
        pcall(function() VIM:SendKeyEvent(false,keyCode,false,game) end)
        task.wait(0.05)
        S.SkillActive=false
    end)
end

local function StartSkillLoop(wType)
    StopSkills()
    local wCFG=CFG["Items"][wType]
    if not wCFG or not wCFG.Enable then return end
    for keyName,skillCFG in pairs(wCFG.Skills or {}) do
        if skillCFG.Enable then
            local delay=math.max(wCFG.Delay or FastDelay, 0.05)
            local hold=skillCFG.HoldTime or 0
            local keyEnum=Enum.KeyCode[keyName]
            if keyEnum then
                SkillThreads[keyName]=task.spawn(function()
                    while S.AttackEnabled and S.Running do
                        PressKey(keyEnum,hold)
                        task.wait(delay)
                    end
                end)
            end
        end
    end
end

-- ==================== AUTO ATTACK ====================
local LastWeaponType = ""
task.spawn(function()
    while true do
        task.wait(FastDelay*0.5)
        if not S.AttackEnabled or not S.Running or S.InSafeZone then continue end

        local c=GetChar(); local hrp=GetHRP()
        if not c or not hrp then continue end

        -- Auto swap weapon theo interval
        if tick()-S.WeaponSwapTimer>=WEAPON_SWAP_INTERVAL then
            S.WeaponSwapTimer=tick()
            task.spawn(SwapWeapon)
        end

        -- Thu thập targets
        local targets={}
        for _,folder in ipairs({workspace:FindFirstChild("Enemies"),workspace:FindFirstChild("Characters")}) do
            if folder then
                for _,model in ipairs(folder:GetChildren()) do
                    if model~=c then
                        local mHRP=model:FindFirstChild("HumanoidRootPart")
                        local mHum=model:FindFirstChild("Humanoid")
                        if mHRP and mHum and mHum.Health>0 and (mHRP.Position-hrp.Position).Magnitude<=60 then
                            for _,part in ipairs(model:GetChildren()) do
                                if part:IsA("BasePart") then table.insert(targets,{model,part}); break end
                            end
                        end
                    end
                end
            end
        end

        -- Priority: S.Target vào đầu
        if IsAlive(S.Target) then
            local tHRP=S.Target.Character:FindFirstChild("HumanoidRootPart")
            local tHead=S.Target.Character:FindFirstChild("Head")
            if tHRP and (tHRP.Position-hrp.Position).Magnitude<=80 then
                table.insert(targets,1,{S.Target.Character,tHead or tHRP})
            end
        end

        if #targets==0 then continue end
        local tool=c:FindFirstChildOfClass("Tool")
        if not tool then continue end
        local wType=tool:GetAttribute("WeaponType") or S.CurrentWeapon

        -- Restart skill loop khi đổi vũ khí
        if wType~=LastWeaponType then
            LastWeaponType=wType
            task.spawn(function() StartSkillLoop(wType) end)
        end

        -- Fire remote
        pcall(function()
            local net=require(RS.Modules.Net)
            net:RemoteEvent("RegisterHit",true)
            RS.Modules.Net["RE/RegisterAttack"]:FireServer()
            local head=targets[1][1]:FindFirstChild("Head")
            if head then
                RS.Modules.Net["RE/RegisterHit"]:FireServer(
                    head,targets,{},
                    tostring(LP.UserId):sub(2,4)..tostring(coroutine.running()):sub(11,15)
                )
                if NetRemote and NetSeed then
                    pcall(function()
                        local seed=RS.Modules.Net.seed:InvokeServer()
                        cloneref(NetRemote):FireServer(
                            string.gsub("RE/RegisterHit",".",function(p)
                                return string.char(bit32.bxor(string.byte(p),
                                    math.floor(workspace:GetServerTimeNow()/10%10)+1))
                            end),
                            bit32.bxor(NetSeed+909090,seed*2),
                            head,targets
                        )
                    end)
                end
            end
        end)
    end
end)

-- ==================== FLY SYSTEM ====================
local FLY_SPEED=350
RunService.Heartbeat:Connect(function()
    if S.InSafeZone or not S.Running then return end
    local hrp=GetHRP(); local hum=GetHum()
    if not hrp or not hum then return end

    if not S.Target or not IsAlive(S.Target) then
        SetBV(Vector3.new(0,0,0)); return
    end

    local tHRP=S.Target.Character:FindFirstChild("HumanoidRootPart")
    if not tHRP then return end

    local myPos=hrp.Position
    local tPos=tHRP.Position+Vector3.new(0,3,0)
    local dist=(tPos-myPos).Magnitude

    hum.PlatformStand=true
    Gravity(false)

    if dist>8 then
        local yDiff=math.abs(tPos.Y-myPos.Y)
        local dir
        if yDiff<5 then
            dir=Vector3.new(tPos.X-myPos.X,0,tPos.Z-myPos.Z).Unit
        else
            dir=(tPos-myPos).Unit
        end
        SetBV(dir*FLY_SPEED)
        SetBG(CFrame.lookAt(myPos,myPos+dir))
        ClearMover("__BP__")
    else
        SetBV(Vector3.new(0,0,0))
        SetBG(CFrame.lookAt(myPos,tHRP.Position))
        SetBP(Vector3.new(myPos.X,tPos.Y,myPos.Z))
    end
end)

-- ==================== SAFE ZONE ====================
task.spawn(function()
    while task.wait(0.3) do
        if not S.Running then break end
        if not CFG["SafeZone"]["Enable"] then continue end
        local hum=GetHum(); local hrp=GetHRP()
        if not hum or not hrp then continue end
        local low=CFG["SafeZone"]["LowHealth"]
        local full=CFG["SafeZone"]["MaxHealth"]
        local safeY=CFG["SafeZone"]["Teleport Y"]
        if hum.Health>0 and hum.Health<=low and not S.InSafeZone then
            S.InSafeZone=true; S.AttackEnabled=false
            StopSkills(); ClearFly()
            hrp.CFrame=CFrame.new(hrp.Position.X,safeY,hrp.Position.Z)
            Gravity(false); SetBV(Vector3.new(0,0,0))
        elseif S.InSafeZone and hum.Health>=full then
            S.InSafeZone=false; S.AttackEnabled=true
            Gravity(false)
        end
    end
end)

-- ==================== TARGET MANAGEMENT ====================
local function GetAllTargets()
    local list={}
    for _,p in ipairs(Players:GetPlayers()) do
        if p~=LP and IsAlive(p) then table.insert(list,p) end
    end
    return list
end

local function NextTarget(exclude)
    local all=GetAllTargets()
    if #all==0 then return nil end
    local filtered={}
    for _,p in ipairs(all) do if p~=exclude then table.insert(filtered,p) end end
    if #filtered==0 then return all[1] end
    return filtered[math.random(1,#filtered)]
end

-- ==================== WEBHOOK ====================
local function Webhook(name,bounty)
    local url=CFG["Setting"]["Url"] or ""
    if url=="" then return end
    pcall(function()
        game:HttpPost(url,HttpService:JSONEncode({embeds={{
            title="🏴‍☠️ Bounty Killed!",
            description="**Player:** "..name.."\n**Bounty:** 💰 "..tostring(bounty),
            color=3447003
        }}}),false,"application/json")
    end)
end

-- ==================== SERVER HOP ====================
local function HopServer()
    if tick()-S.LastHop<5 then return end
    S.LastHop=tick()
    task.spawn(function()
        local ok,result=pcall(function()
            return HttpService:JSONDecode(game:HttpGet(
                "https://games.roblox.com/v1/games/"..game.PlaceId.."/servers/Public?sortOrder=Asc&limit=100"
            ))
        end)
        if not ok or not result or not result.data then return end
        local servers={}
        for _,sv in ipairs(result.data) do
            if sv.id~=S.JobId and not S.Visited[sv.id] and sv.playing and sv.playing>0 then
                table.insert(servers,sv)
            end
        end
        if #servers==0 then S.Visited={}; return end
        local chosen=servers[math.random(1,#servers)]
        S.Visited[chosen.id]=true
        task.wait(CFG["Hop Server"]["Delay Hop"] or 1)
        pcall(function() TS:TeleportToPlaceInstance(game.PlaceId,chosen.id,LP) end)
    end)
end

-- ==================== MAIN HUNT LOOP ====================
task.spawn(function()
    task.wait(3)
    pcall(function()
        local tn=getgenv().Team
        for _,t in ipairs(game.Teams:GetTeams()) do
            if t.Name:lower():find(tn:lower()) then
                local r=(RS:FindFirstChild("Remotes") and RS.Remotes:FindFirstChild("JoinTeam")) or RS:FindFirstChild("JoinTeam")
                if r then r:FireServer(t) end
            end
        end
    end)
    while S.Running do
        task.wait(0.15)
        if S.InSafeZone then continue end
        if not IsAlive(S.Target) then
            local killed=S.Target; S.Target=nil
            if killed then
                S.KillCount=S.KillCount+1
                local bounty=0
                pcall(function()
                    bounty=killed:GetAttribute("Bounty")
                        or (killed.leaderstats and killed.leaderstats:FindFirstChild("Bounty") and killed.leaderstats.Bounty.Value) or 0
                end)
                Webhook(killed.Name,bounty)
            end
            S.Target=NextTarget(killed)
            S.TargetTimer=tick()
            StopSkills(); SkillThreads={}
        end
        if S.Target and (tick()-S.TargetTimer)>=S.ChaseTimeout then
            local old=S.Target
            S.Target=NextTarget(old)
            S.TargetTimer=tick()
            StopSkills(); SkillThreads={}
        end
        if not S.Target then
            if CFG["Hop Server"]["Enable"] then HopServer() end
            task.wait(2)
        end
    end
end)

-- ==================== AUTO V3/V4 ====================
task.spawn(function()
    while task.wait(2) do
        if not S.Running then break end
        pcall(function()
            local rem=RS:FindFirstChild("Remotes")
            if CFG["Auto turn on v4"] then
                local v4=rem and rem:FindFirstChild("ActivateV4")
                if v4 then v4:FireServer() end
            end
            local v3=rem and rem:FindFirstChild("ActivateV3")
            if v3 then v3:FireServer() end
        end)
    end
end)

-- ==================== AIMBOT ====================
getgenv().AimSettings={
    Enabled=true,
    AimPart="HumanoidRootPart",
    MaxDistance=2000,
    PrioritizeLowHP=true,
    LowHPWeight=0.5,
    Prediction=0.135,
    Smoothness=0.07,
    SkillSmoothing=0.18,
    TeamCheck=true,
    ShowFOV=true,
    FOVSize=150,
}

local FOVCircle=Drawing.new("Circle")
FOVCircle.Color=Color3.fromRGB(255,80,80)
FOVCircle.Thickness=1.5
FOVCircle.Filled=false
FOVCircle.Transparency=1
FOVCircle.NumSides=64
FOVCircle.Radius=getgenv().AimSettings.FOVSize

local Arrow=Drawing.new("Triangle")
Arrow.Color=Color3.fromRGB(0,255,120)
Arrow.Filled=true
Arrow.Transparency=0.4
Arrow.Visible=false

local AimLine=Drawing.new("Line")
AimLine.Color=Color3.fromRGB(255,200,0)
AimLine.Thickness=1.5
AimLine.Transparency=0.5
AimLine.Visible=false

RunService.RenderStepped:Connect(function()
    local mousePos=UIS:GetMouseLocation()
    FOVCircle.Position=mousePos
    FOVCircle.Visible=getgenv().AimSettings.ShowFOV
    FOVCircle.Radius=getgenv().AimSettings.FOVSize

    if not getgenv().AimSettings.Enabled then
        Arrow.Visible=false; AimLine.Visible=false; return
    end

    -- Luôn ưu tiên S.Target (đang hunt)
    local aimTarget=IsAlive(S.Target) and S.Target or nil

    if not aimTarget then
        local bestScore=math.huge
        for _,p in ipairs(Players:GetPlayers()) do
            if p~=LP and IsAlive(p) then
                if getgenv().AimSettings.TeamCheck and p.Team==LP.Team then continue end
                local root=p.Character:FindFirstChild("HumanoidRootPart")
                if root then
                    local sp,onScreen=Camera:WorldToViewportPoint(root.Position)
                    if onScreen then
                        local d=(Vector2.new(sp.X,sp.Y)-mousePos).Magnitude
                        local hum=p.Character:FindFirstChild("Humanoid")
                        local score=d
                        if getgenv().AimSettings.PrioritizeLowHP and hum and hum.MaxHealth>0 then
                            score=score*(hum.Health/hum.MaxHealth+getgenv().AimSettings.LowHPWeight)
                        end
                        if d<=getgenv().AimSettings.FOVSize and score<bestScore then
                            bestScore=score; aimTarget=p
                        end
                    end
                end
            end
        end
    end

    if aimTarget and aimTarget.Character then
        local aimPart=aimTarget.Character:FindFirstChild(getgenv().AimSettings.AimPart)
            or aimTarget.Character:FindFirstChild("HumanoidRootPart")
        if not aimPart then Arrow.Visible=false; AimLine.Visible=false; return end

        local vel=aimPart.Velocity
        local predicted=aimPart.Position+vel*getgenv().AimSettings.Prediction

        -- Khi đang dùng skill: aim chặt hơn (smoothing lớn hơn = snap nhanh hơn)
        local smooth=S.SkillActive and getgenv().AimSettings.SkillSmoothing or getgenv().AimSettings.Smoothness

        local cur=Camera.CFrame
        Camera.CFrame=cur:Lerp(CFrame.new(cur.Position,predicted),smooth)

        local sp,onScreen=Camera:WorldToViewportPoint(predicted)
        local center=Vector2.new(Camera.ViewportSize.X/2,Camera.ViewportSize.Y/2)

        if onScreen then
            local tScreen=Vector2.new(sp.X,sp.Y)
            local dir2D=(tScreen-center)
            local unitDir=dir2D.Magnitude>0 and dir2D.Unit or Vector2.new(0,-1)
            local tip=center+unitDir*math.min(dir2D.Magnitude,100)
            local perp=Vector2.new(-unitDir.Y,unitDir.X)
            Arrow.PointA=tip
            Arrow.PointB=tip-unitDir*20+perp*9
            Arrow.PointC=tip-unitDir*20-perp*9
            Arrow.Visible=true
            AimLine.From=center; AimLine.To=tScreen; AimLine.Visible=true
        else
            local sp2,_=Camera:WorldToViewportPoint(predicted)
            local edgeDir=(Vector2.new(sp2.X,sp2.Y)-center).Unit
            local edge=center+edgeDir*130
            local perp=Vector2.new(-edgeDir.Y,edgeDir.X)
            Arrow.PointA=edge; Arrow.PointB=edge-edgeDir*20+perp*9; Arrow.PointC=edge-edgeDir*20-perp*9
            Arrow.Visible=true; AimLine.Visible=false
        end
    else
        Arrow.Visible=false; AimLine.Visible=false
    end
end)

-- ==================== ESP ====================
local ESPs={}
local function MakeESP(p)
    if ESPs[p] then return end
    local bg=Instance.new("BillboardGui")
    bg.Size=UDim2.new(0,160,0,45); bg.StudsOffset=Vector3.new(0,3.5,0); bg.AlwaysOnTop=true
    local nameL=Instance.new("TextLabel",bg)
    nameL.Size=UDim2.new(1,0,0.55,0); nameL.BackgroundTransparency=1
    nameL.TextStrokeTransparency=0; nameL.Font=Enum.Font.GothamBold; nameL.TextScaled=true
    local distL=Instance.new("TextLabel",bg)
    distL.Size=UDim2.new(1,0,0.45,0); distL.Position=UDim2.new(0,0,0.55,0)
    distL.BackgroundTransparency=1; distL.TextColor3=Color3.fromRGB(200,200,200)
    distL.TextStrokeTransparency=0; distL.Font=Enum.Font.Gotham; distL.TextScaled=true
    ESPs[p]={Gui=bg,DistL=distL,NameL=nameL}
    RunService.RenderStepped:Connect(function()
        local char=p.Character
        if char and char:FindFirstChild("HumanoidRootPart") then
            bg.Parent=char.HumanoidRootPart
            local myHRP=GetHRP()
            if myHRP then
                local d=math.floor((char.HumanoidRootPart.Position-myHRP.Position).Magnitude)
                distL.Text=d.." studs"
                local isTarget=(S.Target==p)
                nameL.Text=p.Name..(isTarget and " 🎯" or "")
                nameL.TextColor3=isTarget and Color3.fromRGB(255,60,60) or Color3.fromRGB(255,220,50)
            end
        end
    end)
end
for _,p in ipairs(Players:GetPlayers()) do if p~=LP then MakeESP(p) end end
Players.PlayerAdded:Connect(MakeESP)
Players.PlayerRemoving:Connect(function(p)
    if ESPs[p] then if ESPs[p].Gui then ESPs[p].Gui:Destroy() end; ESPs[p]=nil end
end)

-- ==================== UI ====================
local oldGui=LP.PlayerGui:FindFirstChild("BountyUI")
if oldGui then oldGui:Destroy() end

local SG=Instance.new("ScreenGui",LP.PlayerGui)
SG.Name="BountyUI"; SG.ResetOnSpawn=false
SG.ZIndexBehavior=Enum.ZIndexBehavior.Sibling
SG.IgnoreGuiInset=true

-- === FULLSCREEN AVATAR (bao phủ toàn màn hình) ===
local FullBG=Instance.new("ImageLabel",SG)
FullBG.Size=UDim2.new(1,0,1,0)
FullBG.Position=UDim2.new(0,0,0,0)
FullBG.BackgroundTransparency=1
FullBG.Image="rbxthumb://type=AvatarHeadShot&id=16060333448&w=420&h=420"
FullBG.ImageTransparency=0.5
FullBG.ScaleType=Enum.ScaleType.Stretch
FullBG.ZIndex=1

-- Overlay tối giúp text dễ đọc
local Overlay=Instance.new("Frame",SG)
Overlay.Size=UDim2.new(1,0,1,0)
Overlay.BackgroundColor3=Color3.fromRGB(0,0,5)
Overlay.BackgroundTransparency=0.55
Overlay.BorderSizePixel=0
Overlay.ZIndex=2

-- === CENTER HUD ===
-- Chữ "Switch Hub (Bounty)" to ở giữa
local HubTitle=Instance.new("TextLabel",SG)
HubTitle.Size=UDim2.new(0,620,0,85)
HubTitle.Position=UDim2.new(0.5,-310,0.5,-170)
HubTitle.BackgroundTransparency=1
HubTitle.Text="Switch Hub ( Bounty )"
HubTitle.TextColor3=Color3.fromRGB(100,215,255)
HubTitle.Font=Enum.Font.GothamBlack
HubTitle.TextScaled=true
HubTitle.TextStrokeTransparency=0.35
HubTitle.TextStrokeColor3=Color3.fromRGB(0,70,120)
HubTitle.ZIndex=10

-- Đường kẻ phân cách
local Divider=Instance.new("Frame",SG)
Divider.Size=UDim2.new(0,420,0,2)
Divider.Position=UDim2.new(0.5,-210,0.5,-75)
Divider.BackgroundColor3=Color3.fromRGB(80,180,255)
Divider.BackgroundTransparency=0.4
Divider.BorderSizePixel=0
Divider.ZIndex=10

-- Target name
local TargLine=Instance.new("TextLabel",SG)
TargLine.Size=UDim2.new(0,520,0,34)
TargLine.Position=UDim2.new(0.5,-260,0.5,-62)
TargLine.BackgroundTransparency=1
TargLine.Text="🎯 Target: Searching..."
TargLine.TextColor3=Color3.fromRGB(255,255,255)
TargLine.Font=Enum.Font.GothamBold
TargLine.TextScaled=true
TargLine.TextStrokeTransparency=0.25
TargLine.ZIndex=10

-- HP text
local HPLine=Instance.new("TextLabel",SG)
HPLine.Size=UDim2.new(0,520,0,28)
HPLine.Position=UDim2.new(0.5,-260,0.5,-22)
HPLine.BackgroundTransparency=1
HPLine.Text="❤️ HP: --"
HPLine.TextColor3=Color3.fromRGB(100,255,120)
HPLine.Font=Enum.Font.Gotham
HPLine.TextScaled=true
HPLine.TextStrokeTransparency=0.25
HPLine.ZIndex=10

-- HP bar background
local HPBarBG=Instance.new("Frame",SG)
HPBarBG.Size=UDim2.new(0,400,0,10)
HPBarBG.Position=UDim2.new(0.5,-200,0.5,10)
HPBarBG.BackgroundColor3=Color3.fromRGB(40,40,40)
HPBarBG.BackgroundTransparency=0.2
HPBarBG.BorderSizePixel=0
HPBarBG.ZIndex=10
Instance.new("UICorner",HPBarBG).CornerRadius=UDim.new(1,0)

local HPBar=Instance.new("Frame",HPBarBG)
HPBar.Size=UDim2.new(1,0,1,0)
HPBar.BackgroundColor3=Color3.fromRGB(80,255,120)
HPBar.BorderSizePixel=0
HPBar.ZIndex=11
Instance.new("UICorner",HPBar).CornerRadius=UDim.new(1,0)

-- Distance
local DistLine=Instance.new("TextLabel",SG)
DistLine.Size=UDim2.new(0,520,0,26)
DistLine.Position=UDim2.new(0.5,-260,0.5,26)
DistLine.BackgroundTransparency=1
DistLine.Text="📏 Distance: --"
DistLine.TextColor3=Color3.fromRGB(190,190,190)
DistLine.Font=Enum.Font.Gotham
DistLine.TextScaled=true
DistLine.TextStrokeTransparency=0.25
DistLine.ZIndex=10

-- Weapon đang dùng
local WepLine=Instance.new("TextLabel",SG)
WepLine.Size=UDim2.new(0,520,0,24)
WepLine.Position=UDim2.new(0.5,-260,0.5,57)
WepLine.BackgroundTransparency=1
WepLine.Text="⚔️ Weapon: Melee"
WepLine.TextColor3=Color3.fromRGB(255,185,50)
WepLine.Font=Enum.Font.Gotham
WepLine.TextScaled=true
WepLine.TextStrokeTransparency=0.25
WepLine.ZIndex=10

-- Kills + timer
local KillLine=Instance.new("TextLabel",SG)
KillLine.Size=UDim2.new(0,520,0,24)
KillLine.Position=UDim2.new(0.5,-260,0.5,86)
KillLine.BackgroundTransparency=1
KillLine.Text="💀 Kills: 0  |  ⏱ 120s"
KillLine.TextColor3=Color3.fromRGB(255,110,110)
KillLine.Font=Enum.Font.GothamBold
KillLine.TextScaled=true
KillLine.TextStrokeTransparency=0.25
KillLine.ZIndex=10

-- SafeZone
local SafeLine=Instance.new("TextLabel",SG)
SafeLine.Size=UDim2.new(0,520,0,28)
SafeLine.Position=UDim2.new(0.5,-260,0.5,115)
SafeLine.BackgroundTransparency=1
SafeLine.Text=""
SafeLine.TextColor3=Color3.fromRGB(255,80,80)
SafeLine.Font=Enum.Font.GothamBold
SafeLine.TextScaled=true
SafeLine.TextStrokeTransparency=0.2
SafeLine.ZIndex=10

-- Tất cả elements để toggle
local CenterElements={HubTitle,Divider,TargLine,HPLine,HPBarBG,DistLine,WepLine,KillLine,SafeLine}

-- === TOGGLE BUTTON: Góc trái trên, hình tròn, avatar ===
local TogBtn=Instance.new("ImageButton",SG)
TogBtn.Size=UDim2.new(0,60,0,60)
TogBtn.Position=UDim2.new(0,14,0,14)
TogBtn.BackgroundColor3=Color3.fromRGB(8,8,18)
TogBtn.BorderSizePixel=0
TogBtn.ZIndex=30
Instance.new("UICorner",TogBtn).CornerRadius=UDim.new(1,0)

local togStroke=Instance.new("UIStroke",TogBtn)
togStroke.Color=Color3.fromRGB(255,255,255); togStroke.Thickness=2.5

local togAvt=Instance.new("ImageLabel",TogBtn)
togAvt.Size=UDim2.new(1,-6,1,-6)
togAvt.Position=UDim2.new(0,3,0,3)
togAvt.BackgroundTransparency=1
togAvt.Image="rbxthumb://type=AvatarHeadShot&id=16060333448&w=150&h=150"
Instance.new("UICorner",togAvt).CornerRadius=UDim.new(1,0)

local TogLbl=Instance.new("TextLabel",SG)
TogLbl.Size=UDim2.new(0,88,0,16)
TogLbl.Position=UDim2.new(0,0,0,76)
TogLbl.BackgroundTransparency=1
TogLbl.Text="  Hide UI"
TogLbl.TextColor3=Color3.fromRGB(210,210,210)
TogLbl.Font=Enum.Font.Gotham
TogLbl.TextSize=11
TogLbl.ZIndex=30

TogBtn.MouseButton1Click:Connect(function()
    S.UIVisible=not S.UIVisible
    for _,e in ipairs(CenterElements) do e.Visible=S.UIVisible end
    FullBG.Visible=S.UIVisible
    Overlay.Visible=S.UIVisible
    TogLbl.Text=S.UIVisible and "  Hide UI" or "  Show UI"
end)

-- === SKIP BUTTON (Góc phải trên) ===
local SkipBtn=Instance.new("TextButton",SG)
SkipBtn.Size=UDim2.new(0,120,0,36)
SkipBtn.Position=UDim2.new(1,-134,0,14)
SkipBtn.BackgroundColor3=Color3.fromRGB(255,255,255)
SkipBtn.TextColor3=Color3.fromRGB(0,0,0)
SkipBtn.Text="⏭  Skip Player"
SkipBtn.Font=Enum.Font.GothamBold
SkipBtn.TextSize=13
SkipBtn.BorderSizePixel=0
SkipBtn.ZIndex=30
Instance.new("UICorner",SkipBtn).CornerRadius=UDim.new(0,8)

SkipBtn.MouseButton1Click:Connect(function()
    local old=S.Target
    S.Target=NextTarget(old)
    S.TargetTimer=tick()
    StopSkills(); SkillThreads={}
end)

-- ==================== UI UPDATE ====================
RunService.RenderStepped:Connect(function()
    local timeLeft=S.Target and math.max(0,S.ChaseTimeout-(tick()-S.TargetTimer)) or 0
    KillLine.Text=string.format("💀 Kills: %d  |  ⏱ %ds",S.KillCount,math.floor(timeLeft))
    WepLine.Text="⚔️ Weapon: "..(S.CurrentWeapon or "Melee")..(S.SkillActive and "  ✦ Skill!" or "")
    SafeLine.Text=S.InSafeZone and "🛡 SAFE ZONE — Recovering HP..." or ""

    if IsAlive(S.Target) then
        local tChar=S.Target.Character
        local tHum=tChar:FindFirstChild("Humanoid")
        local tHRP=tChar:FindFirstChild("HumanoidRootPart")
        local myHRP=GetHRP()
        TargLine.Text="🎯 Target: "..S.Target.Name
        if tHum and tHum.MaxHealth>0 then
            local pct=math.floor(tHum.Health/tHum.MaxHealth*100)
            HPLine.Text=string.format("❤️ HP: %d / %d  (%d%%)",
                math.floor(tHum.Health),math.floor(tHum.MaxHealth),pct)
            local ratio=tHum.Health/tHum.MaxHealth
            HPBar.Size=UDim2.new(math.clamp(ratio,0,1),0,1,0)
            HPBar.BackgroundColor3=ratio>0.5
                and Color3.fromRGB(80,255,120)
                or ratio>0.25
                and Color3.fromRGB(255,200,50)
                or Color3.fromRGB(255,60,60)
        end
        if tHRP and myHRP then
            local d=math.floor((tHRP.Position-myHRP.Position).Magnitude)
            DistLine.Text="📏 Distance: "..d.." studs"
        end
        HubTitle.Text=string.format("Switch Hub ( Bounty ) | %ds",math.floor(timeLeft))
    else
        TargLine.Text="🎯 Target: Searching..."
        HPLine.Text="❤️ HP: --"
        DistLine.Text="📏 Distance: --"
        HPBar.Size=UDim2.new(0,0,1,0)
        HubTitle.Text="Switch Hub ( Bounty )"
    end
end)

-- ==================== RESPAWN ====================
LP.CharacterAdded:Connect(function()
    task.wait(1.5)
    Gravity(false); NoclipEnabled=true
    pcall(function()
        local tn=getgenv().Team
        for _,t in ipairs(game.Teams:GetTeams()) do
            if t.Name:lower():find(tn:lower()) then
                local r=(RS:FindFirstChild("Remotes") and RS.Remotes:FindFirstChild("JoinTeam")) or RS:FindFirstChild("JoinTeam")
                if r then r:FireServer(t) end
            end
        end
    end)
end)
if LP.Character then Gravity(false); NoclipEnabled=true end

-- ==================== DONE ====================
print("[BountyHunter Pro v3] Loaded | Team: "..(getgenv().Team or "Pirates"))
pcall(function()
    StarterGui:SetCore("SendNotification",{
        Title="🏴‍☠️ Bounty Hunter Pro v3",
        Text="Loaded! Team: "..(getgenv().Team or "Pirates"),
        Duration=5
    })
end)
