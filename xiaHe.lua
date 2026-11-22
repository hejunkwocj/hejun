-- ============================================================
-- UVA Panel v47：全能状态栏 (FPS+Ping) + 互动透视 + 极简UI
-- 作者: H831288he9 | 纯客户端
-- ============================================================

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")
local Lighting = game:GetService("Lighting")
local VirtualUser = game:GetService("VirtualUser")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TextChatService = game:GetService("TextChatService")
local PathfindingService = game:GetService("PathfindingService")
local Stats = game:GetService("Stats") -- 用于获取 Ping

local LP = Players.LocalPlayer
local Camera = Workspace.CurrentCamera
local AUTHOR_NAME = "H831288he9"

if _G.UVA_Conns then
    for _, c in ipairs(_G.UVA_Conns) do if c and c.Connected then c:Disconnect() end end
end
local Conns = {}
_G.UVA_Conns = Conns
local function addConn(c) table.insert(Conns, c); return c end

local states = {
    Fly = false, FlySpeed = 60, Noclip = false,
    WalkSpeed = 16, JumpPower = 50, CustomGravity = 196.2,
    ESP = false, ESPColor = true, ESPOutline = true, ESPDist = true, ESPName = true,
    InteractESP = false, 
    NPCESP = false, NPCAura = false, NPCAuraDist = 30,
    Fullbright = false, ClickTP = false, AntiVoid = false, InfJump = false, AutoClick = false,
    AntiFling = false, AutoInteract = false, InteractRadius = 20,
    QuickInteract = false, QuickInteractDist = 30, FlingPower = 1000,
    Filter = 0,
    HitboxMultiplier = 1.0,
    InstantAim = false, InstantAimFOV = 300, AimPart = "Head",
    AimLockPersistent = false, AimLockSmooth = 30, AimLockAutoFire = false,
    ShowFOVCircle = false,
    KillAura = false, KillAuraRange = 20, KillAuraAutoPickup = true,
    AntiStun = false, AntiFall = false,
    BulletWallbang = false, BulletTrack = false, BulletTrackRange = 60,
    AutoPickupTool = false, AutoPickupRange = 15,
    AutoRespawn = false, HUD = false,
    ShowCoords = false,
    SafeWalkSpeed = 100, 
    ShowTopRightHud = true, -- 新增加：右上角状态栏开关
    FPS = 0
}

local carState = { CarFly = false, CarBoost = false, CarSpeed = 120, CarBoostPower = 250 }
local carBV, carBG
local chatState = { enabled = false, message = "大家好！", totalCount = 10, interval = 2, sentCount = 0 }
local blackHoleData = { active = false, conn = nil, glow = nil, radius = 30, pull = 150, spin = 60 }

local walkActive = false

_G.FlyUpPressed = false
_G.FlyDownPressed = false
_G.CarForwardPressed = false
_G.CarBackwardPressed = false
_G.CarLeftPressed = false
_G.CarRightPressed = false

local flyBV, flyBG, noclipConn, antiAfkConn
local savedCFrame = nil
local lastValidCFrame = nil

local function getParts()
    local char = LP.Character
    if not char then return nil end
    local hrp = char:FindFirstChild("HumanoidRootPart")
    local hum = char:FindFirstChildOfClass("Humanoid")
    if hrp and hum and hum.Health > 0 then return char, hrp, hum end
    return nil
end

local function getVehicle()
    local _, _, hum = getParts()
    if not hum then return nil end
    local seat = hum.SeatPart
    if not seat then return nil end
    return seat, (seat.AssemblyRootPart or seat)
end

local function teleportTo(hrp, targetCFrame)
    if not hrp then return end
    hrp.CFrame = targetCFrame
    hrp.AssemblyLinearVelocity = Vector3.zero
    hrp.AssemblyAngularVelocity = Vector3.zero
    _G.UVA_TP_Grace = os.clock() + 0.5
end

local function applyStats()
    local _, _, hum = getParts()
    if hum then
        pcall(function()
            hum.WalkSpeed = states.WalkSpeed
            hum.UseJumpPower = true
            hum.JumpPower = states.JumpPower
        end)
    end
    workspace.Gravity = states.CustomGravity
end

local function stopFly()
    if not states.Fly then return end
    states.Fly = false
    if flyBV then flyBV:Destroy(); flyBV = nil end
    if flyBG then flyBG:Destroy(); flyBG = nil end
    local _, _, hum = getParts()
    if hum then pcall(function() hum.WalkSpeed = states.WalkSpeed end) end
end

local function startFly()
    if states.Fly then return end
    local _, _, hum = getParts()
    if not hum then return end
    states.Fly = true
    hum.WalkSpeed = 1
end

local function stopCarFly()
    carState.CarFly = false
    if carBV and not carState.CarBoost then carBV:Destroy(); carBV = nil end
    if carBG and not carState.CarBoost then carBG:Destroy(); carBG = nil end
end

local function stopCarBoost()
    carState.CarBoost = false
    if not carState.CarFly then
        if carBV then carBV:Destroy(); carBV = nil end
        if carBG then carBG:Destroy(); carBG = nil end
    end
end

local function stopNoclip()
    states.Noclip = false
    if noclipConn then noclipConn:Disconnect(); noclipConn = nil end
end

local function startNoclip()
    if states.Noclip then return end
    states.Noclip = true
    noclipConn = addConn(RunService.Stepped:Connect(function()
        local char = LP.Character
        if not char then return end
        for _, p in ipairs(char:GetDescendants()) do
            if p:IsA("BasePart") then p.CanCollide = false end
        end
    end))
end

local function toggleFullbright(on)
    if on then
        Lighting.Brightness = 3
        Lighting.OutdoorAmbient = Color3.fromRGB(255,255,255)
        Lighting.Ambient = Color3.fromRGB(255,255,255)
        Lighting.FogEnd = 100000
        Lighting.GlobalShadows = false
    else
        Lighting.Brightness = 2
        Lighting.OutdoorAmbient = Color3.fromRGB(128,128,128)
        Lighting.Ambient = Color3.fromRGB(0,0,0)
        Lighting.FogEnd = 10000
        Lighting.GlobalShadows = true
    end
end

local function setupAntiAFK()
    if antiAfkConn then antiAfkConn:Disconnect() end
    antiAfkConn = addConn(LP.Idled:Connect(function()
        VirtualUser:CaptureController()
        VirtualUser:ClickButton2(Vector2.new())
    end))
end

local antiStunConn = nil
local function stopAntiStun()
    states.AntiStun = false
    if antiStunConn then antiStunConn:Disconnect(); antiStunConn = nil end
end
local function startAntiStun()
    if states.AntiStun then return end
    states.AntiStun = true
    antiStunConn = addConn(RunService.Heartbeat:Connect(function()
        if not states.AntiStun then return end
        local _, _, hum = getParts(); if not hum then return end
        pcall(function()
            if hum.WalkSpeed <= 0.1 then hum.WalkSpeed = states.WalkSpeed end
            if hum.JumpPower <= 0.1 then hum.JumpPower = states.JumpPower end
            if hum.PlatformStand then hum.PlatformStand = false end
            if hum.Sit then hum.Sit = false end
        end)
        pcall(function()
            local st = hum:GetState()
            if st == Enum.HumanoidStateType.Physics or st == Enum.HumanoidStateType.PlatformStanding
                or st == Enum.HumanoidStateType.FallingDown or st == Enum.HumanoidStateType.Ragdoll then
                hum:ChangeState(Enum.HumanoidStateType.Running)
            end
        end)
    end))
end

local antiFallConn = nil
local function stopAntiFall()
    states.AntiFall = false
    if antiFallConn then antiFallConn:Disconnect(); antiFallConn = nil end
end
local function startAntiFall()
    if states.AntiFall then return end
    states.AntiFall = true
    antiFallConn = addConn(RunService.Heartbeat:Connect(function()
        if not states.AntiFall then return end
        local _, hrp, hum = getParts(); if not hrp or not hum then return end
        pcall(function() hum.FallDamageEnabled = false end)
        local vel = hrp.AssemblyLinearVelocity
        if vel.Y < -60 then hrp.AssemblyLinearVelocity = Vector3.new(vel.X, -40, vel.Z) end
        local rayParams = RaycastParams.new()
        rayParams.FilterDescendantsInstances = {LP.Character}
        rayParams.FilterType = Enum.RaycastFilterType.Exclude
        local result = Workspace:Raycast(hrp.Position, Vector3.new(0, -15, 0), rayParams)
        if result and vel.Y < -25 then hrp.AssemblyLinearVelocity = Vector3.new(vel.X, 0, vel.Z) end
    end))
end

-- ============================================================
-- FPS 与 右上角 HUD 模块
-- ============================================================
local topRightHud = Instance.new("ScreenGui")
topRightHud.Name = "UVA_TopRightHUD"
topRightHud.ResetOnSpawn = false
topRightHud.IgnoreGuiInset = true
topRightHud.DisplayOrder = 999
topRightHud.Parent = LP:WaitForChild("PlayerGui")

local hudFrame = Instance.new("Frame")
hudFrame.Size = UDim2.fromOffset(190, 108) -- 加高以容纳四行
hudFrame.Position = UDim2.new(1, -200, 0, 10)
hudFrame.BackgroundColor3 = Color3.fromRGB(25, 25, 30)
hudFrame.BackgroundTransparency = 0.4
hudFrame.BorderSizePixel = 0
hudFrame.Parent = topRightHud
Instance.new("UICorner", hudFrame).CornerRadius = UDim.new(0, 8)
local hudStroke = Instance.new("UIStroke", hudFrame)
hudStroke.Color = Color3.fromRGB(0, 255, 100)
hudStroke.Thickness = 1.5

local function createHudLabel(text, yOffset, color)
    local lbl = Instance.new("TextLabel")
    lbl.Size = UDim2.new(1, -10, 0, 24)
    lbl.Position = UDim2.new(0, 10, 0, yOffset)
    lbl.BackgroundTransparency = 1
    lbl.Text = text
    lbl.TextColor3 = color or Color3.fromRGB(0, 255, 100)
    lbl.Font = Enum.Font.GothamBold
    lbl.TextSize = 14
    lbl.TextXAlignment = Enum.TextXAlignment.Left
    lbl.Parent = hudFrame
    return lbl
end

local playerCountLbl = createHudLabel("👥 人数: 0", 6, Color3.fromRGB(0, 255, 100))
local npcCountLbl    = createHudLabel("🤖 NPC: 0", 30, Color3.fromRGB(255, 200, 100))
local pingLbl        = createHudLabel("📶 延迟: 0 ms", 54, Color3.fromRGB(0, 200, 255))
local fpsLbl         = createHudLabel("📈 FPS: 0", 78, Color3.fromRGB(255, 100, 100))

-- FPS 计算
local fpsCount = 0
local lastFpsTime = os.clock()
addConn(RunService.RenderStepped:Connect(function()
    fpsCount = fpsCount + 1
    if os.clock() - lastFpsTime >= 1 then
        states.FPS = fpsCount
        fpsCount = 0
        lastFpsTime = os.clock()
    end
end))

-- HUD 刷新逻辑
task.spawn(function()
    while task.wait(2) do
        if not topRightHud or not topRightHud.Parent then break end
        topRightHud.Enabled = states.ShowTopRightHud
        if not states.ShowTopRightHud then continue end

        -- 1. 人数
        local pCount = #Players:GetPlayers()
        -- 2. NPC 数量
        local npcCount = 0
        for _, obj in ipairs(Workspace:GetDescendants()) do
            if obj:IsA("Humanoid") then
                local char = obj.Parent
                if char and char:IsA("Model") and not Players:GetPlayerFromCharacter(char) then
                    npcCount = npcCount + 1
                end
            end
        end
        -- 3. 延迟 (Ping)
        local ping = 0
        local ok, pingItem = pcall(function() return Stats.Network.ServerStatsItem["Data Ping"] end)
        if ok and pingItem then
            ping = math.floor(pingItem:GetValue())
        else
            ping = math.floor(LP:GetNetworkPing() * 1000)
        end
        -- 4. FPS
        local fps = states.FPS

        playerCountLbl.Text = "👥 人数: " .. pCount
        npcCountLbl.Text = "🤖 NPC: " .. npcCount
        pingLbl.Text = "📶 延迟: " .. ping .. " ms"
        
        -- 延迟颜色判定
        if ping > 150 then pingLbl.TextColor3 = Color3.fromRGB(255, 100, 100)
        elseif ping > 80 then pingLbl.TextColor3 = Color3.fromRGB(255, 200, 100)
        else pingLbl.TextColor3 = Color3.fromRGB(0, 200, 255) end

        fpsLbl.Text = "📈 FPS: " .. fps
        -- FPS 颜色判定
        if fps < 30 then fpsLbl.TextColor3 = Color3.fromRGB(255, 100, 100)
        elseif fps < 60 then fpsLbl.TextColor3 = Color3.fromRGB(255, 200, 100)
        else fpsLbl.TextColor3 = Color3.fromRGB(0, 255, 100) end
    end
end)

-- ============================================================
-- 可互动透视模块
-- ============================================================
local interactESPData = {}
local function refreshInteractESP()
    for obj, data in pairs(interactESPData) do
        if data.hl then data.hl:Destroy() end
        if data.bb then data.bb:Destroy() end
        interactESPData[obj] = nil
    end
    
    if not states.InteractESP then return end
    
    for _, obj in ipairs(Workspace:GetDescendants()) do
        if obj:IsA("ProximityPrompt") or obj:IsA("ClickDetector") then
            local target = obj.Parent
            if target:IsA("Attachment") then target = target.Parent end
            
            if target and (target:IsA("BasePart") or target:IsA("Model")) and not interactESPData[target] then
                local hl = Instance.new("Highlight")
                hl.Adornee = target
                hl.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
                hl.FillColor = Color3.fromRGB(255, 255, 0)
                hl.OutlineColor = Color3.fromRGB(255, 255, 200)
                hl.FillTransparency = 0.5
                hl.Parent = target
                
                local posPart = target:IsA("BasePart") and target or target:FindFirstChildWhichIsA("BasePart")
                local bb, lbl
                if posPart then
                    bb = Instance.new("BillboardGui")
                    bb.Adornee = posPart
                    bb.Size = UDim2.new(0, 120, 0, 30)
                    bb.StudsOffset = Vector3.new(0, 3, 0)
                    bb.AlwaysOnTop = true
                    bb.Parent = target
                    
                    lbl = Instance.new("TextLabel")
                    lbl.Size = UDim2.fromScale(1, 1)
                    lbl.BackgroundTransparency = 1
                    lbl.Text = "🔧 " .. target.Name
                    lbl.TextColor3 = Color3.fromRGB(255, 255, 0)
                    lbl.TextStrokeTransparency = 0.3
                    lbl.TextSize = 13
                    lbl.Font = Enum.Font.GothamBold
                    lbl.Parent = bb
                end
                interactESPData[target] = { hl = hl, bb = bb, lbl = lbl }
            end
        end
    end
end

task.spawn(function()
    while task.wait(3) do
        if states.InteractESP then refreshInteractESP() end
    end
end)

-- ============================================================
-- 通知模块
-- ============================================================
local function showNotification(text)
    local notif = LP.PlayerGui:FindFirstChild("UVA_Notif")
    if notif then notif:Destroy() end
    notif = Instance.new("ScreenGui")
    notif.Name = "UVA_Notif"; notif.ResetOnSpawn = false
    notif.Parent = LP:WaitForChild("PlayerGui")
    local lbl = Instance.new("TextLabel")
    lbl.Size = UDim2.new(0, 400, 0, 60)
    lbl.Position = UDim2.new(0.5, -200, 0, 80)
    lbl.BackgroundColor3 = Color3.fromRGB(0, 0, 0)
    lbl.BackgroundTransparency = 0.2
    lbl.Text = text; lbl.TextColor3 = Color3.fromRGB(0, 255, 100)
    lbl.Font = Enum.Font.GothamBold; lbl.TextSize = 16
    lbl.TextWrapped = true; lbl.Parent = notif
    Instance.new("UICorner", lbl).CornerRadius = UDim.new(0, 8)
    Instance.new("UIStroke", lbl).Color = Color3.fromRGB(0, 255, 100)
    task.delay(4, function() if notif then notif:Destroy() end end)
end

-- ============================================================
-- 核心逻辑
-- ============================================================
local function walkToPlayer(targetPlayer)
    if not targetPlayer then return end
    if walkActive then showNotification("寻路进行中") return end
    local _, myHRP, myHum = getParts()
    if not myHRP or not myHum then showNotification("你当前没有角色") return end
    local targetChar = targetPlayer.Character
    local targetHRP = targetChar and targetChar:FindFirstChild("HumanoidRootPart")
    if not targetHRP then showNotification("目标没有角色") return end

    walkActive = true
    local originalWS = myHum.WalkSpeed
    local runSpeed = states.SafeWalkSpeed or 100
    task.spawn(function()
        local path = PathfindingService:CreatePath({AgentRadius = 2, AgentHeight = 5, AgentCanJump = true})
        local ok = pcall(function() path:ComputeAsync(myHRP.Position, targetHRP.Position) end)
        if ok and path.Status == Enum.PathStatus.Success then
            for i, wp in ipairs(path:GetWaypoints()) do
                if not walkActive then break end
                if i == 1 then continue end
                local _, curHRP, curHum = getParts()
                if not curHRP or not curHum then break end
                curHum.WalkSpeed = runSpeed
                if wp.Action == Enum.PathWaypointAction.Jump then curHum.Jump = true end
                curHum:MoveTo(wp.Position)
                local wpStart = os.clock()
                while walkActive and os.clock() - wpStart < 6 do
                    task.wait(0.1)
                    local _, curHRP2 = getParts()
                    if not curHRP2 then break end
                    local tHRP2 = targetPlayer.Character and targetPlayer.Character:FindFirstChild("HumanoidRootPart")
                    if tHRP2 and (curHRP2.Position - tHRP2.Position).Magnitude < 5 then walkActive = false; break end
                    if (curHRP2.Position - wp.Position).Magnitude < 4 then break end
                end
            end
        else
            local maxT = 25; local startT = os.clock()
            while walkActive and os.clock() - startT < maxT do
                task.wait(0.15)
                local _, curHRP, curHum = getParts()
                if not curHRP or not curHum then break end
                local tHRP = targetPlayer.Character and targetPlayer.Character:FindFirstChild("HumanoidRootPart")
                if not tHRP then break end
                if (curHRP.Position - tHRP.Position).Magnitude < 5 then break end
                curHum.WalkSpeed = runSpeed; curHum:MoveTo(tHRP.Position)
            end
        end
        if myHum and myHum.Parent then
            pcall(function() myHum:MoveTo(myHRP.Position); myHum.WalkSpeed = originalWS end)
        end
        walkActive = false
    end)
end

local originalHitboxes = {}
task.spawn(function()
    while task.wait(0.5) do
        if states.HitboxMultiplier ~= 1.0 then
            for _, p in ipairs(Players:GetPlayers()) do
                if p.Character then
                    for _, partName in ipairs({"Head", "HumanoidRootPart", "Torso", "UpperTorso", "LowerTorso"}) do
                        local part = p.Character:FindFirstChild(partName)
                        if part then
                            if not originalHitboxes[part] then originalHitboxes[part] = part.Size end
                            part.Size = originalHitboxes[part] * states.HitboxMultiplier
                        end
                    end
                end
            end
        else
            for part, origSize in pairs(originalHitboxes) do
                if part and part.Parent then part.Size = origSize end
            end
            originalHitboxes = {}
        end
    end
end)

local function getClosestTarget()
    local closest, shortestDist = nil, math.huge
    local center = Camera.ViewportSize / 2
    for _, p in ipairs(Players:GetPlayers()) do
        if p ~= LP and p.Character then
            local hum = p.Character:FindFirstChildOfClass("Humanoid")
            if hum and hum.Health > 0 then
                local targetPart = p.Character:FindFirstChild(states.AimPart) or p.Character:FindFirstChild("HumanoidRootPart")
                if targetPart then
                    local screenPos, onScreen = Camera:WorldToViewportPoint(targetPart.Position)
                    if onScreen then
                        local d = (Vector2.new(screenPos.X, screenPos.Y) - center).Magnitude
                        if d <= states.InstantAimFOV then
                            local dist = (Camera.CFrame.Position - targetPart.Position).Magnitude
                            if dist < shortestDist then shortestDist = dist; closest = targetPart end
                        end
                    end
                end
            end
        end
    end
    return closest
end

local aimLastFire = 0
UserInputService.InputBegan:Connect(function(input, gpe)
    if gpe or not states.InstantAim or states.AimLockPersistent then return end
    if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
        local target = getClosestTarget()
        if target then
            Camera.CFrame = CFrame.lookAt(Camera.CFrame.Position, target.Position)
        end
    end
end)

RunService.RenderStepped:Connect(function()
    if not states.InstantAim or not states.AimLockPersistent then return end
    local target = getClosestTarget()
    if target then
        local targetCF = CFrame.lookAt(Camera.CFrame.Position, target.Position)
        local alpha = 1 - (states.AimLockSmooth / 100)
        Camera.CFrame = Camera.CFrame:Lerp(targetCF, alpha)
        if states.AimLockAutoFire and os.clock() - aimLastFire > 0.15 then
            aimLastFire = os.clock()
            local tool = LP.Character and LP.Character:FindFirstChildOfClass("Tool")
            if tool then pcall(function() tool:Activate() end) end
        end
    end
end)

local cachedPrompts = {}
task.spawn(function()
    while task.wait(3) do
        if not states.AutoInteract then continue end
        local newList = {}
        for _, obj in ipairs(Workspace:GetDescendants()) do
            if obj:IsA("ProximityPrompt") then table.insert(newList, obj) end
        end
        cachedPrompts = newList
    end
end)

task.spawn(function()
    while task.wait(0.25) do
        if not states.AutoInteract then continue end
        local _, hrp = getParts(); if not hrp then continue end
        for _, prompt in ipairs(cachedPrompts) do
            if prompt.Parent and prompt.Enabled then
                local part = prompt.Parent
                if part:IsA("Attachment") then part = part.Parent end
                if part and part:IsA("BasePart") and (part.Position - hrp.Position).Magnitude <= states.InteractRadius then
                    task.spawn(function()
                        pcall(function()
                            prompt:InputHoldBegin()
                            task.wait(math.max(prompt.HoldDuration or 0, 0.05) + 0.05)
                            prompt:InputHoldEnd()
                        end)
                    end)
                end
            end
        end
    end
end)

-- ESP 模块
local espData = {}
addConn(RunService.RenderStepped:Connect(function()
    if not states.ESP then return end
    local myChar = LP.Character
    local myHRP = myChar and myChar:FindFirstChild("HumanoidRootPart")
    
    for _, plr in ipairs(Players:GetPlayers()) do
        if plr ~= LP then
            local char = plr.Character
            local hrp = char and char:FindFirstChild("HumanoidRootPart")
            local hum = char and char:FindFirstChildOfClass("Humanoid")
            
            if hrp and hum and hum.Health > 0 then
                local d = espData[plr]
                if not d or not d.hl or not d.hl.Parent or d.currentChar ~= char then
                    if espData[plr] then
                        if espData[plr].hl then espData[plr].hl:Destroy() end
                        if espData[plr].bb then espData[plr].bb:Destroy() end
                        espData[plr] = nil
                    end
                    local hl = Instance.new("Highlight")
                    hl.Name = "UVA_HL"; hl.Adornee = char; hl.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
                    hl.FillColor = Color3.fromRGB(255, 60, 60); hl.OutlineColor = Color3.fromRGB(255, 255, 255)
                    hl.FillTransparency = 0.5; hl.Parent = char
                    
                    local bb = Instance.new("BillboardGui")
                    bb.Name = "UVA_BB"; bb.Adornee = hrp; bb.Size = UDim2.new(0, 170, 0, 46)
                    bb.StudsOffset = Vector3.new(0, 3, 0); bb.AlwaysOnTop = true; bb.Parent = char
                    
                    local lbl = Instance.new("TextLabel")
                    lbl.Size = UDim2.fromScale(1, 1); lbl.BackgroundTransparency = 1; lbl.TextColor3 = Color3.fromRGB(255, 255, 255)
                    lbl.TextStrokeTransparency = 0.3; lbl.TextSize = 14; lbl.Font = Enum.Font.GothamBold; lbl.Parent = bb
                    
                    d = { hl = hl, bb = bb, lbl = lbl, currentChar = char }
                    espData[plr] = d
                end
                
                d.hl.Enabled = states.ESPColor or states.ESPOutline
                d.hl.FillTransparency = states.ESPColor and 0.5 or 1
                d.hl.OutlineTransparency = states.ESPOutline and 0 or 1
                
                local dist = myHRP and math.floor((myHRP.Position - hrp.Position).Magnitude) or 0
                local lines = {}
                if states.ESPName then table.insert(lines, plr.Name) end
                if states.ESPDist then table.insert(lines, "[" .. dist .. "m]") end
                d.bb.Enabled = #lines > 0
                d.lbl.Text = table.concat(lines, " ")
            else
                local d = espData[plr]
                if d then
                    if d.hl then d.hl.Enabled = false end
                    if d.bb then d.bb.Enabled = false end
                end
            end
        end
    end
end))

-- 飞行 / 防甩飞
addConn(RunService.RenderStepped:Connect(function()
    if not states.Fly then return end
    local _, hrp, hum = getParts(); if not hrp or not hum then stopFly(); return end
    if not flyBV or flyBV.Parent ~= hrp then
        if flyBV then flyBV:Destroy() end
        if flyBG then flyBG:Destroy() end
        flyBV = Instance.new("BodyVelocity"); flyBV.MaxForce = Vector3.new(1e6, 1e6, 1e6); flyBV.Parent = hrp
        flyBG = Instance.new("BodyGyro"); flyBG.MaxTorque = Vector3.new(1e6, 1e6, 1e6); flyBG.P = 3000; flyBG.D = 50; flyBG.Parent = hrp
    end
    local camCF = Camera.CFrame
    local look = camCF.LookVector; local right = camCF.RightVector; local up = Vector3.new(0, 1, 0)
    local finalDir = Vector3.zero
    local moveDir = hum.MoveDirection
    if moveDir.Magnitude > 0.05 then
        local flatLook = Vector3.new(look.X, 0, look.Z)
        local flatRight = Vector3.new(right.X, 0, right.Z)
        if flatLook.Magnitude > 0.01 then flatLook = flatLook.Unit end
        if flatRight.Magnitude > 0.01 then flatRight = flatRight.Unit end
        finalDir = (look * moveDir:Dot(flatLook) + right * moveDir:Dot(flatRight))
    end
    if _G.FlyUpPressed then finalDir = finalDir + up end
    if _G.FlyDownPressed then finalDir = finalDir - up end
    if finalDir.Magnitude > 0 then finalDir = finalDir.Unit end
    flyBV.Velocity = finalDir * states.FlySpeed
    local flatLook = Vector3.new(look.X, 0, look.Z)
    if flatLook.Magnitude > 1e-3 then flyBG.CFrame = CFrame.lookAt(hrp.Position, hrp.Position + flatLook.Unit) end
end))

addConn(RunService.Stepped:Connect(function(_, deltaTime)
    if not states.AntiFling then lastValidCFrame = nil; return end
    local _, hrp = getParts(); if not hrp then return end
    if _G.UVA_TP_Grace and os.clock() < _G.UVA_TP_Grace then lastValidCFrame = hrp.CFrame; return end
    if not lastValidCFrame then lastValidCFrame = hrp.CFrame; return end
    local dist = (hrp.Position - lastValidCFrame.Position).Magnitude
    if hrp.AssemblyLinearVelocity.Magnitude > 150 or dist > (120 * deltaTime + 5) then
        hrp.CFrame = lastValidCFrame
        hrp.AssemblyLinearVelocity = Vector3.zero
        hrp.AssemblyAngularVelocity = Vector3.zero
        hrp.Anchored = true
        task.delay(0.15, function() if hrp and hrp.Parent then hrp.Anchored = false end end)
    else
        lastValidCFrame = hrp.CFrame
    end
end))

local function flingPlayer(targetChar)
    if not targetChar or targetChar == LP.Character then return end
    local targetHRP = targetChar:FindFirstChild("HumanoidRootPart")
    if not targetHRP then return end
    local p = states.FlingPower
    local box = Instance.new("Part")
    box.Size = Vector3.new(15, 15, 15); box.Transparency = 1; box.CanCollide = true; box.Massless = false
    box.CustomPhysicalProperties = PhysicalProperties.new(500, 0.3, 0.5, 1, 1)
    box.CFrame = targetHRP.CFrame; box.Parent = Workspace
    local weld = Instance.new("WeldConstraint")
    weld.Part0 = box; weld.Part1 = targetHRP; weld.Parent = box
    box.AssemblyLinearVelocity = Vector3.new(math.random(-p, p), p * 1.5, math.random(-p, p))
    task.delay(0.5, function() if box then box:Destroy() end end)
end

-- ============================================================
-- UI 框架
-- ============================================================
for _, name in ipairs({"UVA_HUB_UI", "UVA_Fold"}) do
    local old = LP.PlayerGui:FindFirstChild(name)
    if old then old:Destroy() end
end
local gui = Instance.new("ScreenGui")
gui.Name = "UVA_HUB_UI"; gui.ResetOnSpawn = false
gui.Parent = LP:WaitForChild("PlayerGui")
local uiScale = Instance.new("UIScale"); uiScale.Parent = gui
if Camera.ViewportSize.X < 800 then uiScale.Scale = 0.65 else uiScale.Scale = 0.85 end

local floatBall = Instance.new("TextButton")
floatBall.Size = UDim2.fromOffset(60, 60)
floatBall.Position = UDim2.new(0, 30, 0.5, -30)
floatBall.BackgroundColor3 = Color3.fromRGB(25, 25, 30)
floatBall.Text = "UVA"; floatBall.TextColor3 = Color3.fromRGB(0, 255, 100)
floatBall.Font = Enum.Font.GothamBlack; floatBall.TextSize = 16
floatBall.BorderSizePixel = 0; floatBall.Parent = gui
Instance.new("UICorner", floatBall).CornerRadius = UDim.new(1, 0)
Instance.new("UIStroke", floatBall).Color = Color3.fromRGB(0, 255, 100)

local flyControls = Instance.new("Frame")
flyControls.Size = UDim2.fromOffset(70, 160)
flyControls.Position = UDim2.new(1, -100, 0.5, -120)
flyControls.BackgroundTransparency = 1; flyControls.Visible = false; flyControls.Parent = gui
local function makeFlyBtn(text, yPos)
    local btn = Instance.new("TextButton")
    btn.Size = UDim2.fromOffset(70, 70); btn.Position = UDim2.fromOffset(0, yPos)
    btn.BackgroundColor3 = Color3.fromRGB(30, 30, 40); btn.BackgroundTransparency = 0.3; btn.Text = text
    btn.TextColor3 = Color3.fromRGB(0, 255, 100); btn.Font = Enum.Font.GothamBlack; btn.TextSize = 24; btn.Parent = flyControls
    btn.Active = true
    Instance.new("UICorner", btn).CornerRadius = UDim.new(1, 0)
    btn.InputBegan:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.Touch or input.UserInputType == Enum.UserInputType.MouseButton1 then
            if text == "▲" then _G.FlyUpPressed = true else _G.FlyDownPressed = true end
        end
    end)
    btn.InputEnded:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.Touch or input.UserInputType == Enum.UserInputType.MouseButton1 then
            if text == "▲" then _G.FlyUpPressed = false else _G.FlyDownPressed = false end
        end
    end)
end
makeFlyBtn("▲", 0); makeFlyBtn("▼", 90)

local main = Instance.new("Frame")
main.Size = UDim2.fromOffset(600, 400); main.Position = UDim2.new(0.5, -300, 0.5, -200)
main.BackgroundColor3 = Color3.fromRGB(25, 25, 30); main.BackgroundTransparency = 0.1; main.BorderSizePixel = 0
main.Active = true; main.Visible = false; main.Parent = gui
Instance.new("UICorner", main).CornerRadius = UDim.new(0, 12)
Instance.new("UIStroke", main).Color = Color3.fromRGB(50, 50, 60)

local sidebar = Instance.new("Frame")
sidebar.Size = UDim2.new(0, 140, 1, 0); sidebar.BackgroundColor3 = Color3.fromRGB(15, 15, 20)
sidebar.BorderSizePixel = 0; sidebar.Parent = main
Instance.new("UICorner", sidebar).CornerRadius = UDim.new(0, 12)

local titleLbl = Instance.new("TextLabel")
titleLbl.Size = UDim2.new(1, 0, 0, 50); titleLbl.BackgroundTransparency = 1; titleLbl.Text = "XL"
titleLbl.TextColor3 = Color3.fromRGB(0, 255, 100); titleLbl.Font = Enum.Font.GothamBlack; titleLbl.TextSize = 22; titleLbl.Parent = sidebar

local contentFrame = Instance.new("Frame")
contentFrame.Size = UDim2.new(1, -150, 1, -20); contentFrame.Position = UDim2.new(0, 145, 0, 10)
contentFrame.BackgroundTransparency = 1; contentFrame.Parent = main

local minBtn = Instance.new("TextButton")
minBtn.Size = UDim2.fromOffset(30, 30); minBtn.Position = UDim2.new(1, -40, 0, 10)
minBtn.BackgroundColor3 = Color3.fromRGB(200, 50, 50); minBtn.Text = "×"; minBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
minBtn.Font = Enum.Font.GothamBold; minBtn.TextSize = 20; minBtn.Parent = main
Instance.new("UICorner", minBtn).CornerRadius = UDim.new(0, 6)

local scrollUpBtn = Instance.new("TextButton")
scrollUpBtn.Size = UDim2.fromOffset(32, 32)
scrollUpBtn.Position = UDim2.new(1, -40, 0, 45)
scrollUpBtn.BackgroundColor3 = Color3.fromRGB(0, 200, 80)
scrollUpBtn.BackgroundTransparency = 0.3
scrollUpBtn.Text = "▲"; scrollUpBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
scrollUpBtn.Font = Enum.Font.GothamBlack; scrollUpBtn.TextSize = 16
scrollUpBtn.BorderSizePixel = 0; scrollUpBtn.ZIndex = 10; scrollUpBtn.Parent = main
Instance.new("UICorner", scrollUpBtn).CornerRadius = UDim.new(0, 6)

local scrollDownBtn = scrollUpBtn:Clone()
scrollDownBtn.Position = UDim2.new(1, -40, 0, 82)
scrollDownBtn.Text = "▼"; scrollDownBtn.Parent = main

local pages = {}
local function createPage(name)
    local page = Instance.new("ScrollingFrame")
    page.Size = UDim2.fromScale(1, 1); page.BackgroundTransparency = 1; page.BorderSizePixel = 0
    page.ScrollBarThickness = 10; page.ScrollBarImageColor3 = Color3.fromRGB(0, 255, 100)
    page.AutomaticCanvasSize = Enum.AutomaticSize.Y
    page.CanvasSize = UDim2.new(0, 0, 0, 0)
    page.Visible = false; page.Parent = contentFrame
    local pad = Instance.new("UIPadding", page)
    pad.PaddingTop = UDim.new(0, 6); pad.PaddingBottom = UDim.new(0, 40)
    pad.PaddingLeft = UDim.new(0, 4); pad.PaddingRight = UDim.new(0, 4)
    local layout = Instance.new("UIListLayout", page)
    layout.Padding = UDim.new(0, 10); layout.SortOrder = Enum.SortOrder.LayoutOrder
    pages[name] = page; return page
end

local function getCurrentPage()
    for n, p in pairs(pages) do
        if p.Visible then return p end
    end
    return nil
end

scrollUpBtn.MouseButton1Click:Connect(function()
    local p = getCurrentPage()
    if p then p.CanvasPosition = Vector2.new(p.CanvasPosition.X, math.max(0, p.CanvasPosition.Y - 200)) end
end)
scrollDownBtn.MouseButton1Click:Connect(function()
    local p = getCurrentPage()
    if p then p.CanvasPosition = Vector2.new(p.CanvasPosition.X, p.CanvasPosition.Y + 200) end
end)

local navBtns = {}
local function switchPage(pageName, btn)
    for n, p in pairs(pages) do p.Visible = (n == pageName) end
    for _, b in pairs(navBtns) do
        b.TextColor3 = Color3.fromRGB(150, 150, 150); b.BackgroundTransparency = 1
    end
    if btn then
        btn.TextColor3 = Color3.fromRGB(0, 255, 100)
        btn.BackgroundTransparency = 0.8
        btn.BackgroundColor3 = Color3.fromRGB(0, 255, 100)
    end
end

local function createNavBtn(text, yOffset, pageName)
    local btn = Instance.new("TextButton")
    btn.Size = UDim2.new(1, -20, 0, 40); btn.Position = UDim2.new(0, 10, 0, yOffset)
    btn.BackgroundTransparency = 1; btn.Text = text; btn.TextColor3 = Color3.fromRGB(150, 150, 150)
    btn.Font = Enum.Font.GothamBold; btn.TextSize = 14
    btn.TextXAlignment = Enum.TextXAlignment.Left; btn.Parent = sidebar
    Instance.new("UICorner", btn).CornerRadius = UDim.new(0, 6)
    table.insert(navBtns, btn)
    btn.MouseButton1Click:Connect(function() switchPage(pageName, btn) end)
    if not next(pages) then switchPage(pageName, btn) end
end

local function createGroup(parent, titleText, order)
    local group = Instance.new("Frame")
    group.Size = UDim2.new(1, -10, 0, 0); group.AutomaticSize = Enum.AutomaticSize.Y
    group.BackgroundColor3 = Color3.fromRGB(35, 35, 45); group.BackgroundTransparency = 0.2
    group.BorderSizePixel = 0; group.LayoutOrder = order; group.Parent = parent
    Instance.new("UICorner", group).CornerRadius = UDim.new(0, 8)
    local padding = Instance.new("UIPadding", group)
    padding.PaddingTop = UDim.new(0, 10); padding.PaddingBottom = UDim.new(0, 10)
    padding.PaddingLeft = UDim.new(0, 10); padding.PaddingRight = UDim.new(0, 10)
    local groupLayout = Instance.new("UIListLayout", group)
    groupLayout.Padding = UDim.new(0, 6); groupLayout.SortOrder = Enum.SortOrder.LayoutOrder
    local title = Instance.new("TextLabel")
    title.Size = UDim2.new(1, 0, 0, 20); title.BackgroundTransparency = 1
    title.Text = "📁 " .. titleText; title.TextColor3 = Color3.fromRGB(200, 200, 200)
    title.Font = Enum.Font.GothamBold; title.TextSize = 14
    title.TextXAlignment = Enum.TextXAlignment.Left; title.LayoutOrder = 1; title.Parent = group
    local list = Instance.new("Frame")
    list.Size = UDim2.new(1, 0, 0, 0); list.AutomaticSize = Enum.AutomaticSize.Y
    list.BackgroundTransparency = 1; list.LayoutOrder = 2; list.Parent = group
    local layout = Instance.new("UIListLayout", list)
    layout.Padding = UDim.new(0, 8); layout.SortOrder = Enum.SortOrder.LayoutOrder
    return list
end

local function addToggle(parent, text, initState, callback)
    local btn = Instance.new("TextButton")
    btn.Size = UDim2.new(1, 0, 0, 36)
    btn.BackgroundColor3 = initState and Color3.fromRGB(0, 200, 80) or Color3.fromRGB(45, 45, 55)
    btn.Text = text; btn.TextColor3 = Color3.fromRGB(255, 255, 255)
    btn.Font = Enum.Font.GothamBold; btn.TextSize = 13; btn.Parent = parent
    Instance.new("UICorner", btn).CornerRadius = UDim.new(0, 6)
    local state = initState
    btn.MouseButton1Click:Connect(function()
        state = not state
        btn.BackgroundColor3 = state and Color3.fromRGB(0, 200, 80) or Color3.fromRGB(45, 45, 55)
        callback(state)
    end)
end

local function addButton(parent, text, callback)
    local btn = Instance.new("TextButton")
    btn.Size = UDim2.new(1, 0, 0, 36); btn.BackgroundColor3 = Color3.fromRGB(45, 45, 55)
    btn.Text = text; btn.TextColor3 = Color3.fromRGB(255, 255, 255)
    btn.Font = Enum.Font.GothamBold; btn.TextSize = 13; btn.Parent = parent
    Instance.new("UICorner", btn).CornerRadius = UDim.new(0, 6)
    btn.MouseButton1Click:Connect(callback); return btn
end

local function addInput(parent, text, initVal, callback)
    local frame = Instance.new("Frame")
    frame.Size = UDim2.new(1, 0, 0, 36); frame.BackgroundColor3 = Color3.fromRGB(45, 45, 55); frame.Parent = parent
    Instance.new("UICorner", frame).CornerRadius = UDim.new(0, 6)
    local lbl = Instance.new("TextLabel")
    lbl.Size = UDim2.new(0.5, 0, 1, 0); lbl.BackgroundTransparency = 1
    lbl.Text = text; lbl.TextColor3 = Color3.fromRGB(200, 200, 200)
    lbl.Font = Enum.Font.GothamBold; lbl.TextXAlignment = Enum.TextXAlignment.Left
    lbl.Parent = frame; lbl.Position = UDim2.fromOffset(10, 0)
    local box = Instance.new("TextBox")
    box.Size = UDim2.new(0.4, 0, 0.8, 0); box.Position = UDim2.new(0.55, 0, 0.1, 0)
    box.BackgroundColor3 = Color3.fromRGB(30, 30, 40); box.Text = tostring(initVal)
    box.TextColor3 = Color3.fromRGB(0, 255, 100)
    box.Font = Enum.Font.GothamBold; box.Parent = frame
    Instance.new("UICorner", box).CornerRadius = UDim.new(0, 4)
    box.FocusLost:Connect(function()
        local n = tonumber(box.Text)
        if n then callback(n) else box.Text = tostring(initVal) end
    end)
end

-- ============================================================
-- 页面构建
-- ============================================================
-- Move 页
local movePage = createPage("Move")
local grpMove = createGroup(movePage, "移动与防护", 1)
addToggle(grpMove, "开启飞行 (推摇杆即飞)", states.Fly, function(v) if v then startFly() else stopFly() end; flyControls.Visible = v or carState.CarFly end)
addToggle(grpMove, "无限跳跃", states.InfJump, function(v) states.InfJump = v end)
addToggle(grpMove, "穿墙 (Noclip)", states.Noclip, function(v) if v then startNoclip() else stopNoclip() end end)
addToggle(grpMove, "防虚空掉落", states.AntiVoid, function(v) states.AntiVoid = v end)
addToggle(grpMove, "防甩飞 (苛刻版)", states.AntiFling, function(v) states.AntiFling = v end)
local grpProtect = createGroup(movePage, "🛡️ 防击晕 & 防摔落", 2)
addToggle(grpProtect, "防击晕", states.AntiStun, function(v) if v then startAntiStun() else stopAntiStun() end end)
addToggle(grpProtect, "防摔落伤害", states.AntiFall, function(v) if v then startAntiFall() else stopAntiFall() end end)
local grpCar = createGroup(movePage, "🚗 车辆改装", 3)
addToggle(grpCar, "飞车 (视角控制 3D 飞行)", carState.CarFly, function(v)
    if v then carState.CarFly = true; flyControls.Visible = true
    else stopCarFly(); flyControls.Visible = states.Fly end
end)
addToggle(grpCar, "车辆加速", carState.CarBoost, function(v)
    if v then carState.CarBoost = true else stopCarBoost() end
end)
addInput(grpCar, "飞车速度", carState.CarSpeed, function(v) carState.CarSpeed = v end)
addInput(grpCar, "加速速度", carState.CarBoostPower, function(v) carState.CarBoostPower = v end)
local grpGravity = createGroup(movePage, "重力快捷设置", 4)
addButton(grpGravity, "零重力 (G=0)", function() states.CustomGravity = 0; workspace.Gravity = 0 end)
addButton(grpGravity, "月球重力 (G=16)", function() states.CustomGravity = 16; workspace.Gravity = 16 end)
addButton(grpGravity, "恢复默认重力 (G=196.2)", function() states.CustomGravity = 196.2; workspace.Gravity = 196.2 end)
local grpStats = createGroup(movePage, "属性修改", 5)
addInput(grpStats, "移动速度", states.WalkSpeed, function(v) states.WalkSpeed = v; applyStats() end)
addInput(grpStats, "跳跃力量", states.JumpPower, function(v) states.JumpPower = v; applyStats() end)
addInput(grpStats, "飞行速度", states.FlySpeed, function(v) states.FlySpeed = v end)
addInput(grpStats, "自定义重力(G)", states.CustomGravity, function(v) states.CustomGravity = v; workspace.Gravity = v end)

-- Combat 页
local combatPage = createPage("Combat")
local grpHitbox = createGroup(combatPage, "📦 碰撞箱大小调节", 1)
addInput(grpHitbox, "碰撞箱倍率 (0.1~5.0)", states.HitboxMultiplier, function(v) states.HitboxMultiplier = math.clamp(v, 0.1, 5.0) end)
addButton(grpHitbox, "恢复正常碰撞箱 (1.0)", function() states.HitboxMultiplier = 1.0 end)
local grpAim = createGroup(combatPage, "🎯 强化锁自瞄", 2)
addToggle(grpAim, "开启自瞄总开关", states.InstantAim, function(v) states.InstantAim = v end)
addToggle(grpAim, "锁定模式：持续锁定", states.AimLockPersistent, function(v) states.AimLockPersistent = v end)
addInput(grpAim, "平滑度 (0=瞬锁 100=不锁)", states.AimLockSmooth, function(v) states.AimLockSmooth = math.clamp(v, 0, 100) end)
addToggle(grpAim, "锁定时自动开火", states.AimLockAutoFire, function(v) states.AimLockAutoFire = v end)
local grpKillAura = createGroup(combatPage, "⚔️ 通用杀戮光环", 3)
addToggle(grpKillAura, "开启杀戮光环", states.KillAura, function(v) states.KillAura = v end)
addInput(grpKillAura, "光环半径 (米)", states.KillAuraRange, function(v) states.KillAuraRange = math.clamp(v, 1, 200) end)

-- Player 页
local playerPage = createPage("Player")
local grpTP = createGroup(playerPage, "快捷传送", 1)
addToggle(grpTP, "点击屏幕传送 (Click TP)", states.ClickTP, function(v) states.ClickTP = v end)
addButton(grpTP, "保存当前坐标", function(btn)
    local _, hrp = getParts()
    if hrp then savedCFrame = hrp.CFrame; btn.Text = "已保存坐标" end
end)
addButton(grpTP, "传送到保存点", function()
    local _, hrp = getParts()
    if hrp and savedCFrame then teleportTo(hrp, savedCFrame) end
end)
local grpWalk = createGroup(playerPage, "🚶 自动寻路设置", 2)
addInput(grpWalk, "寻路速度 (默认100)", states.SafeWalkSpeed, function(v) states.SafeWalkSpeed = math.clamp(v, 30, 500) end)
addButton(grpWalk, "⏹️ 停止寻路", function() walkActive = false end)
local grpPlayers = createGroup(playerPage, "玩家列表 (实时坐标)", 3)
addToggle(grpPlayers, "🆕 显示玩家实时坐标", false, function(v) states.ShowCoords = v end)

local playerScroll = Instance.new("ScrollingFrame")
playerScroll.Size = UDim2.new(1, 0, 0, 280); playerScroll.BackgroundTransparency = 1
playerScroll.BorderSizePixel = 0; playerScroll.ScrollBarThickness = 8
playerScroll.ScrollBarImageColor3 = Color3.fromRGB(0, 255, 100)
playerScroll.AutomaticCanvasSize = Enum.AutomaticSize.Y
playerScroll.CanvasSize = UDim2.new(0, 0, 0, 0); playerScroll.Parent = grpPlayers
local listLayout = Instance.new("UIListLayout", playerScroll); listLayout.Padding = UDim.new(0, 6)

local function updatePlayerList()
    for _, child in ipairs(playerScroll:GetChildren()) do
        if child:IsA("Frame") or child:IsA("TextButton") then child:Destroy() end
    end
    for _, p in ipairs(Players:GetPlayers()) do
        if p ~= LP then
            local container = Instance.new("Frame")
            container.Size = UDim2.new(1, -4, 0, 64)
            container.BackgroundColor3 = Color3.fromRGB(45, 45, 55)
            container.BorderSizePixel = 0
            container.Parent = playerScroll
            container.Name = "PlayerFrame_" .. p.Name
            Instance.new("UICorner", container).CornerRadius = UDim.new(0, 6)
            local nameLbl = Instance.new("TextLabel")
            nameLbl.Size = UDim2.new(1, -10, 0, 28); nameLbl.Position = UDim2.new(0, 8, 0, 2)
            nameLbl.BackgroundTransparency = 1; nameLbl.Text = "👤 " .. p.Name
            nameLbl.TextColor3 = Color3.fromRGB(0, 255, 100); nameLbl.Font = Enum.Font.GothamBold
            nameLbl.TextSize = 12; nameLbl.TextXAlignment = Enum.TextXAlignment.Left
            nameLbl.TextTruncate = Enum.TextTruncate.AtEnd; nameLbl.Parent = container

            local tpBtn = Instance.new("TextButton")
            tpBtn.Size = UDim2.new(0.48, -6, 0, 28); tpBtn.Position = UDim2.new(0.01, 0, 0, 32)
            tpBtn.BackgroundColor3 = Color3.fromRGB(0, 180, 100); tpBtn.Text = "🚀 传送"
            tpBtn.TextColor3 = Color3.fromRGB(255, 255, 255); tpBtn.Font = Enum.Font.GothamBold
            tpBtn.TextSize = 12; tpBtn.BorderSizePixel = 0; tpBtn.Parent = container
            Instance.new("UICorner", tpBtn).CornerRadius = UDim.new(0, 4)
            tpBtn.MouseButton1Click:Connect(function()
                local _, myHRP = getParts()
                local targetHRP = p.Character and p.Character:FindFirstChild("HumanoidRootPart")
                if myHRP and targetHRP then teleportTo(myHRP, targetHRP.CFrame * CFrame.new(0, 3, 3)) end
            end)
            local walkBtn = Instance.new("TextButton")
            walkBtn.Size = UDim2.new(0.48, -6, 0, 28); walkBtn.Position = UDim2.new(0.51, 0, 0, 32)
            walkBtn.BackgroundColor3 = Color3.fromRGB(0, 130, 200); walkBtn.Text = "🚶 寻路"
            walkBtn.TextColor3 = Color3.fromRGB(255, 255, 255); walkBtn.Font = Enum.Font.GothamBold
            walkBtn.TextSize = 12; walkBtn.BorderSizePixel = 0; walkBtn.Parent = container
            Instance.new("UICorner", walkBtn).CornerRadius = UDim.new(0, 4)
            walkBtn.MouseButton1Click:Connect(function() walkToPlayer(p) end)
        end
    end
end
Players.PlayerAdded:Connect(function() task.wait(0.5); updatePlayerList() end)
Players.PlayerRemoving:Connect(function() task.wait(0.5); updatePlayerList() end)
task.spawn(updatePlayerList)

task.spawn(function()
    while task.wait(0.5) do
        if not states.ShowCoords then continue end
        for _, p in ipairs(Players:GetPlayers()) do
            if p == LP then continue end
            local frame = playerScroll:FindFirstChild("PlayerFrame_" .. p.Name)
            if frame then
                local nameLbl = frame:FindFirstChildOfClass("TextLabel")
                local hrp = p.Character and p.Character:FindFirstChild("HumanoidRootPart")
                if nameLbl and hrp then
                    nameLbl.Text = string.format("👤 %s  📍 %.0f,%.0f,%.0f", p.Name, hrp.Position.X, hrp.Position.Y, hrp.Position.Z)
                end
            end
        end
    end
end)

local grpFling = createGroup(playerPage, "恶搞甩飞", 4)
addInput(grpFling, "碰撞速度", states.FlingPower, function(v) states.FlingPower = v end)
addButton(grpFling, "🚀 甩飞全图玩家", function()
    for _, p in ipairs(Players:GetPlayers()) do if p ~= LP and p.Character then flingPlayer(p.Character) end end
end)

-- Visual 页
local visualPage = createPage("Visual")
local grpESP = createGroup(visualPage, "透视 (ESP)", 1)
addToggle(grpESP, "开启玩家透视", states.ESP, function(v) 
    states.ESP = v
    if not v then
        for plr, d in pairs(espData) do
            if d.hl then d.hl:Destroy() end
            if d.bb then d.bb:Destroy() end
            espData[plr] = nil
        end
    end
end)
addToggle(grpESP, "显示名字", states.ESPName, function(v) states.ESPName = v end)
addToggle(grpESP, "显示距离", states.ESPDist, function(v) states.ESPDist = v end)
addToggle(grpESP, "人物上色", states.ESPColor, function(v) states.ESPColor = v end)
addToggle(grpESP, "人物描边", states.ESPOutline, function(v) states.ESPOutline = v end)

local grpEnv = createGroup(visualPage, "环境修改", 2)
addToggle(grpEnv, "全亮 (Fullbright)", states.Fullbright, function(v) states.Fullbright = v; toggleFullbright(v) end)
-- 新增：右上角状态栏开关
addToggle(grpEnv, "显示右上角状态栏", states.ShowTopRightHud, function(v) 
    states.ShowTopRightHud = v 
    if topRightHud then topRightHud.Enabled = v end
end)

local grpInteract = createGroup(visualPage, "🔧 可互动透视", 3)
addToggle(grpInteract, "开启互动透视 (黄色高亮)", states.InteractESP, function(v) 
    states.InteractESP = v
    refreshInteractESP()
end)

-- ============================================================
-- 导航按钮
-- ============================================================
createNavBtn("移动与防护", 55, "Move")
createNavBtn("🎯 战斗与自瞄", 100, "Combat")
createNavBtn("传送与工具", 145, "Player")
createNavBtn("视觉与透视", 190, "Visual")

-- 悬浮球
floatBall.Active = true
floatBall.Selectable = false
local ballDragging, ballMoved = false, false
local ballGrabOffsetX, ballGrabOffsetY = 0, 0
local ballStartPos = nil
local ballPressTime = 0
local ballLastClickTime = 0
local DRAG_THRESHOLD = 15
local CLICK_MAX_DURATION = 0.6
local CLICK_DEBOUNCE = 0.3

floatBall.InputBegan:Connect(function(input)
    if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
        ballDragging = true; ballMoved = false
        ballStartPos = input.Position; ballPressTime = os.clock()
        local absPos = floatBall.AbsolutePosition
        ballGrabOffsetX = input.Position.X - absPos.X
        ballGrabOffsetY = input.Position.Y - absPos.Y
        floatBall.BackgroundColor3 = Color3.fromRGB(45, 45, 55)
    end
end)

UserInputService.InputChanged:Connect(function(input)
    if not ballDragging then return end
    if input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch then
        local delta = input.Position - ballStartPos
        if not ballMoved and delta.Magnitude > DRAG_THRESHOLD then ballMoved = true end
        if ballMoved then
            local scale = uiScale.Scale or 1
            local vp = Camera.ViewportSize
            local ballPx = 60 * scale
            local newAbsX = math.clamp(input.Position.X - ballGrabOffsetX, 0, math.max(0, vp.X - ballPx))
            local newAbsY = math.clamp(input.Position.Y - ballGrabOffsetY, 0, math.max(0, vp.Y - ballPx))
            floatBall.Position = UDim2.fromOffset(newAbsX / scale, newAbsY / scale)
        end
    end
end)

UserInputService.InputEnded:Connect(function(input)
    if not ballDragging then return end
    if input.UserInputType ~= Enum.UserInputType.MouseButton1 and input.UserInputType ~= Enum.UserInputType.Touch then return end
    ballDragging = false
    floatBall.BackgroundColor3 = Color3.fromRGB(25, 25, 30)
    local pressDuration = os.clock() - ballPressTime
    local now = os.clock()
    if not ballMoved and pressDuration < CLICK_MAX_DURATION and (now - ballLastClickTime) > CLICK_DEBOUNCE then
        ballLastClickTime = now
        main.Visible = not main.Visible
        floatBall.Visible = not main.Visible
        if main.Visible then
            local scale = uiScale.Scale or 1
            local vp = Camera.ViewportSize
            local mainPxW, mainPxH = 600 * scale, 400 * scale
            local ballPx = 60 * scale
            local ballAbsX = floatBall.AbsolutePosition.X
            local ballAbsY = floatBall.AbsolutePosition.Y
            local posPxX, posPxY
            if (ballAbsX + ballPx / 2) < vp.X / 2 then
                posPxX = ballAbsX + ballPx + 10 * scale
            else
                posPxX = ballAbsX - mainPxW - 10 * scale
            end
            if (ballAbsY + ballPx / 2) < vp.Y / 2 then
                posPxY = ballAbsY
            else
                posPxY = ballAbsY + ballPx - mainPxH
            end
            posPxX = math.clamp(posPxX, 5 * scale, math.max(5 * scale, vp.X - mainPxW - 5 * scale))
            posPxY = math.clamp(posPxY, 5 * scale, math.max(5 * scale, vp.Y - mainPxH - 5 * scale))
            main.Position = UDim2.fromOffset(posPxX / scale, posPxY / scale)
        end
    end
end)

minBtn.MouseButton1Click:Connect(function() main.Visible = false; floatBall.Visible = true end)

local winDragging = false
local winStartAbsX, winStartAbsY = 0, 0
local winStartMouseX, winStartMouseY = 0, 0

sidebar.InputBegan:Connect(function(input)
    if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
        winDragging = true
        winStartAbsX = main.AbsolutePosition.X; winStartAbsY = main.AbsolutePosition.Y
        winStartMouseX = input.Position.X; winStartMouseY = input.Position.Y
        main.BackgroundColor3 = Color3.fromRGB(30, 30, 35)
    end
end)

UserInputService.InputChanged:Connect(function(input)
    if not winDragging then return end
    if input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch then
        local scale = uiScale.Scale or 1
        local vp = Camera.ViewportSize
        local mainPxW = main.AbsoluteSize.X
        local mainPxH = main.AbsoluteSize.Y
        local newAbsX = math.clamp(winStartAbsX + (input.Position.X - winStartMouseX), 0, math.max(0, vp.X - mainPxW))
        local newAbsY = math.clamp(winStartAbsY + (input.Position.Y - winStartMouseY), 0, math.max(0, vp.Y - mainPxH))
        main.Position = UDim2.fromOffset(newAbsX / scale, newAbsY / scale)
    end
end)

UserInputService.InputEnded:Connect(function(input)
    if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
        winDragging = false
        main.BackgroundColor3 = Color3.fromRGB(25, 25, 30)
    end
end)

-- Click TP
UserInputService.InputBegan:Connect(function(input)
    if not states.ClickTP then return end
    if input.UserInputType == Enum.UserInputType.Touch or input.UserInputType == Enum.UserInputType.MouseButton1 then
        local guiObjects = LP.PlayerGui:GetGuiObjectsAtPosition(input.Position.X, input.Position.Y)
        for _, obj in ipairs(guiObjects) do
            if obj:IsDescendantOf(main) or obj:IsDescendantOf(floatBall) or obj:IsDescendantOf(flyControls) then return end
        end
        local mouse = LP:GetMouse()
        if mouse.Hit then
            local _, hrp = getParts()
            if hrp then teleportTo(hrp, CFrame.new(mouse.Hit.Position + Vector3.new(0, 3, 0))) end
        end
    end
end)

-- 重生清理
LP.CharacterAdded:Connect(function(char)
    states.Fly = false; states.Noclip = false
    carState.CarFly = false; carState.CarBoost = false
    flyControls.Visible = false
    lastValidCFrame = nil; _G.UVA_TP_Grace = nil
    _G.CarForwardPressed = false; _G.CarBackwardPressed = false
    _G.CarLeftPressed = false; _G.CarRightPressed = false
    walkActive = false
    stopBlackHole()
    if flyBV then flyBV:Destroy(); flyBV = nil end
    if flyBG then flyBG:Destroy(); flyBG = nil end
    if carBV then carBV:Destroy(); carBV = nil end
    if carBG then carBG:Destroy(); carBG = nil end
    if noclipConn then noclipConn:Disconnect(); noclipConn = nil end
    setFilter(0); task.wait(1); applyStats()
    originalHitboxes = {}
end)

setupAntiAFK()
setupAuthorTag()
