-- ============================================================
-- UVA Panel v23：甩飞 + 车辆 + 自动发言 + NPC透视 + 自动/快速互动 + 一键蹦服
-- 滚动终极修复：+600留白 + 子元素底部检测 + 每0.3秒强制同步
-- ============================================================

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")
local Lighting = game:GetService("Lighting")
local VirtualUser = game:GetService("VirtualUser")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TextChatService = game:GetService("TextChatService")

local LP = Players.LocalPlayer
local Camera = Workspace.CurrentCamera

if _G.UVA_Conns then
    for _, c in ipairs(_G.UVA_Conns) do
        if c and c.Connected then c:Disconnect() end
    end
end
local Conns = {}
_G.UVA_Conns = Conns
local function addConn(c) table.insert(Conns, c); return c end

-- ---------- 核心状态 ----------
local states = {
    Fly = false, FlySpeed = 60,
    Noclip = false,
    Spin = false, SpinSpeed = 90,
    WalkSpeed = 16, JumpPower = 50,
    CustomGravity = 196.2,
    ESP = false, ESPColor = true, ESPOutline = true, ESPDist = true, ESPName = true,
    NPCESP = false,
    Fullbright = false,
    ClickTP = false, AntiVoid = false, InfJump = false, AutoClick = false,
    AntiFling = false,
    AutoInteract = false, InteractRadius = 20,
    QuickInteract = false, QuickInteractDist = 30,
    FlingPower = 1000
}

local carState = {
    CarFly = false, CarBoost = false,
    CarSpeed = 120, CarBoostPower = 250,
}
local carBV, carBG

local chatState = {
    enabled = false,
    message = "大家好！",
    totalCount = 10,
    interval = 2,
    sentCount = 0
}

_G.FlyUpPressed = false
_G.FlyDownPressed = false

local flyBV, flyBG, spinAV, noclipConn, antiAfkConn
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
    local root = seat.AssemblyRootPart or seat
    return seat, root
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

local function stopSpin()
    states.Spin = false
    if spinAV then spinAV:Destroy(); spinAV = nil end
end

local function startSpin()
    if states.Spin then return end
    local _, hrp = getParts()
    if not hrp then return end
    states.Spin = true
    spinAV = Instance.new("BodyAngularVelocity")
    spinAV.MaxTorque = Vector3.new(0, 1e6, 0)
    spinAV.AngularVelocity = Vector3.new(0, math.rad(states.SpinSpeed), 0)
    spinAV.Parent = hrp
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

-- ==========================================
-- 自动发言
-- ==========================================
local function sendChatMessage(msg)
    if not msg or msg == "" then return end
    local done = false
    if TextChatService.ChatVersion == Enum.ChatVersion.TextChatService then
        local channels = TextChatService:FindFirstChild("TextChannels")
        if channels then
            local general = channels:FindFirstChild("RBXGeneral")
            if general then
                local ok = pcall(function() general:SendAsync(msg) end)
                if ok then done = true end
            end
        end
    end
    if done then return end
    pcall(function()
        local ev = ReplicatedStorage:FindFirstChild("DefaultChatSystemChatEvents")
        if ev and ev:FindFirstChild("SayMessageRequest") then
            ev.SayMessageRequest:FireServer(msg, "All")
        end
    end)
end

local function startAutoChat()
    if chatState.enabled then return end
    if chatState.message == "" or chatState.message == nil then return end
    if chatState.totalCount <= 0 or chatState.interval <= 0 then return end
    chatState.enabled = true
    chatState.sentCount = 0
    task.spawn(function()
        while chatState.enabled do
            if chatState.sentCount >= chatState.totalCount then
                chatState.enabled = false
                break
            end
            sendChatMessage(chatState.message)
            chatState.sentCount = chatState.sentCount + 1
            local waited = 0
            while waited < chatState.interval and chatState.enabled do
                task.wait(0.1)
                waited = waited + 0.1
            end
        end
    end)
end

local function stopAutoChat()
    chatState.enabled = false
end

-- ==========================================
-- 一键蹦服（假装踢出）
-- ==========================================
local function fakeCrash()
    sendChatMessage("臭乐乐还想蹦服😂")
    task.wait(0.3)

    pcall(function()
        LP:Kick("臭乐乐还想蹦服😂")
    end)

    local old = LP.PlayerGui:FindFirstChild("UVA_FakeCrash")
    if old then old:Destroy() end

    local crashGui = Instance.new("ScreenGui")
    crashGui.Name = "UVA_FakeCrash"
    crashGui.ResetOnSpawn = false
    crashGui.IgnoreGuiInset = true
    crashGui.DisplayOrder = 99999
    crashGui.Parent = LP:WaitForChild("PlayerGui")

    local bg = Instance.new("Frame")
    bg.Size = UDim2.fromScale(1, 1)
    bg.BackgroundColor3 = Color3.fromRGB(0, 0, 0)
    bg.BorderSizePixel = 0
    bg.Parent = crashGui

    local msg = Instance.new("TextLabel")
    msg.Size = UDim2.new(0.9, 0, 0, 200)
    msg.Position = UDim2.new(0.05, 0, 0.5, -100)
    msg.BackgroundTransparency = 1
    msg.Text = "你已被踢出服务器\n\n原因：臭乐乐还想蹦服😂"
    msg.TextColor3 = Color3.fromRGB(255, 80, 80)
    msg.Font = Enum.Font.GothamBlack
    msg.TextSize = 32
    msg.TextWrapped = true
    msg.Parent = bg

    task.spawn(function()
        while true do
            task.wait(0.1)
        end
    end)
end

-- ==========================================
-- 自动互动
-- ==========================================
local cachedPrompts = {}
task.spawn(function()
    while task.wait(3) do
        if not states.AutoInteract then continue end
        local newList = {}
        for _, obj in ipairs(Workspace:GetDescendants()) do
            if obj:IsA("ProximityPrompt") then
                table.insert(newList, obj)
            end
        end
        cachedPrompts = newList
    end
end)

task.spawn(function()
    while task.wait(0.25) do
        if not states.AutoInteract then continue end
        local _, hrp = getParts()
        if not hrp then continue end
        local radius = states.InteractRadius
        for _, prompt in ipairs(cachedPrompts) do
            if prompt.Parent and prompt.Enabled then
                local part = prompt.Parent
                if part:IsA("Attachment") then part = part.Parent end
                if part and part:IsA("BasePart") then
                    if (part.Position - hrp.Position).Magnitude <= radius then
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
    end
end)

-- ==========================================
-- 快速互动
-- ==========================================
local quickInteractOriginal = {}

local function applyQuickInteract()
    for _, obj in ipairs(Workspace:GetDescendants()) do
        if obj:IsA("ProximityPrompt") then
            if not quickInteractOriginal[obj] then
                quickInteractOriginal[obj] = {
                    HoldDuration = obj.HoldDuration,
                    MaxActivationDistance = obj.MaxActivationDistance,
                    RequiresLineOfSight = obj.RequiresLineOfSight
                }
            end
            obj.HoldDuration = 0
            obj.MaxActivationDistance = states.QuickInteractDist
            obj.RequiresLineOfSight = false
        end
    end
end

local function restoreQuickInteract()
    for prompt, orig in pairs(quickInteractOriginal) do
        if prompt and prompt.Parent then
            pcall(function()
                prompt.HoldDuration = orig.HoldDuration
                prompt.MaxActivationDistance = orig.MaxActivationDistance
                prompt.RequiresLineOfSight = orig.RequiresLineOfSight
            end)
        end
    end
    quickInteractOriginal = {}
end

task.spawn(function()
    while task.wait(1) do
        if not states.QuickInteract then continue end
        applyQuickInteract()
    end
end)

-- ==========================================
-- 极度苛刻防甩飞
-- ==========================================
addConn(RunService.Stepped:Connect(function(_, deltaTime)
    if not states.AntiFling then 
        lastValidCFrame = nil
        return 
    end
    local char, hrp, hum = getParts()
    if not hrp then return end

    if not lastValidCFrame then
        lastValidCFrame = hrp.CFrame
        return
    end

    local currentPos = hrp.Position
    local currentVel = hrp.AssemblyLinearVelocity
    local dist = (currentPos - lastValidCFrame.Position).Magnitude
    local maxAllowedDist = 120 * deltaTime + 5
    
    if currentVel.Magnitude > 150 or dist > maxAllowedDist then
        hrp.CFrame = lastValidCFrame
        hrp.AssemblyLinearVelocity = Vector3.zero
        hrp.AssemblyAngularVelocity = Vector3.zero
        
        hrp.Anchored = true
        task.delay(0.15, function()
            if hrp and hrp.Parent then hrp.Anchored = false end
        end)
        
        for _, v in ipairs(hrp:GetChildren()) do
            if v:IsA("BodyVelocity") or v:IsA("BodyForce") or v:IsA("BodyAngularVelocity") or v:IsA("LinearVelocity") or v:IsA("VectorForce") then
                if v ~= flyBV and v ~= flyBG and v ~= spinAV then
                    v:Destroy()
                end
            end
        end
    else
        lastValidCFrame = hrp.CFrame
    end

    local safeRadius = 15
    local overlapParams = OverlapParams.new()
    overlapParams.FilterDescendantsInstances = {char}
    overlapParams.FilterType = Enum.RaycastFilterType.Exclude
    
    local parts = Workspace:GetPartBoundsInRadius(hrp.Position, safeRadius, overlapParams)
    for _, part in ipairs(parts) do
        if part:IsA("BasePart") and not part.Anchored then
            local isDangerous = false
            if part.AssemblyMass > 50 or part.AssemblyLinearVelocity.Magnitude > 80 then isDangerous = true end
            local model = part:FindFirstAncestorOfClass("Model")
            if model and Players:GetPlayerFromCharacter(model) and model ~= char then isDangerous = true end
            if isDangerous then part.CanCollide = false end
        end
    end
end))

-- ==========================================
-- 恶搞甩飞
-- ==========================================
local function flingPlayer(targetChar)
    if not targetChar or targetChar == LP.Character then return end
    local targetHRP = targetChar:FindFirstChild("HumanoidRootPart")
    if not targetHRP then return end

    local flingPart = Instance.new("Part")
    flingPart.Size = Vector3.new(2, 2, 2)
    flingPart.Transparency = 1
    flingPart.CanCollide = false
    flingPart.Massless = false
    flingPart.CFrame = targetHRP.CFrame
    flingPart.Parent = targetHRP
    
    local p = states.FlingPower
    flingPart.AssemblyLinearVelocity = Vector3.new(math.random(-p, p), p, math.random(-p, p))
    flingPart.AssemblyAngularVelocity = Vector3.new(math.random(-p, p), math.random(-p, p), math.random(-p, p))
    
    task.delay(0.5, function()
        if flingPart then flingPart:Destroy() end
    end)
end

local function flingAll()
    for _, p in ipairs(Players:GetPlayers()) do
        if p ~= LP and p.Character then
            flingPlayer(p.Character)
        end
    end
end

-- ==========================================
-- 其他防护
-- ==========================================
addConn(RunService.Heartbeat:Connect(function()
    if not states.AntiVoid then return end
    local _, hrp = getParts()
    if hrp and hrp.Position.Y < -80 then
        hrp.CFrame = CFrame.new(0, 50, 0)
    end
end))

addConn(RunService.Stepped:Connect(function()
    if not states.InfJump then return end
    local _, hrp, hum = getParts()
    if hrp and hum then
        if hum.Jump or UserInputService:IsKeyDown(Enum.KeyCode.Space) then
            hum.Jump = false
            hrp.Velocity = Vector3.new(hrp.Velocity.X, states.JumpPower, hrp.Velocity.Z)
            hum:ChangeState(Enum.HumanoidStateType.Jumping)
        end
    end
end))

task.spawn(function()
    while task.wait(0.05) do
        if states.AutoClick then
            VirtualUser:CaptureController()
            VirtualUser:ClickButton1(Vector2.new(Camera.ViewportSize.X/2, Camera.ViewportSize.Y/2))
        end
    end
end)

local function forceStealTools()
    local myBackpack = LP:FindFirstChild("Backpack")
    if not myBackpack then return end
    for _, p in ipairs(Players:GetPlayers()) do
        if p ~= LP and p:FindFirstChild("Backpack") then
            for _, t in ipairs(p.Backpack:GetChildren()) do
                if t:IsA("Tool") then t.Parent = myBackpack end
            end
        end
    end
end

local function clearMyBackpack()
    local myBackpack = LP:FindFirstChild("Backpack")
    if myBackpack then
        for _, t in ipairs(myBackpack:GetChildren()) do
            if t:IsA("Tool") then t:Destroy() end
        end
    end
end

-- ============================================================
-- 精准道具搜索
-- ============================================================
local function searchAndListItems(keyword, listUI)
    for _, v in ipairs(listUI:GetChildren()) do
        if v:IsA("TextButton") or v:IsA("TextLabel") then v:Destroy() end
    end

    keyword = string.lower(keyword)
    local foundCount = 0
    local containers = {Workspace, ReplicatedStorage}
    
    for _, container in ipairs(containers) do
        for _, obj in ipairs(container:GetDescendants()) do
            if foundCount >= 80 then break end
            
            local isTarget = false
            if obj:IsA("Tool") then isTarget = true 
            elseif keyword ~= "" and string.find(string.lower(obj.Name), keyword) then isTarget = true end
            
            if keyword ~= "" and not string.find(string.lower(obj.Name), keyword) then isTarget = false end

            if obj:FindFirstAncestorOfClass("Model") and Players:GetPlayerFromCharacter(obj:FindFirstAncestorOfClass("Model")) then
                isTarget = false
            end

            if isTarget then
                foundCount = foundCount + 1
                local btn = Instance.new("TextButton")
                btn.Size = UDim2.new(1, -4, 0, 28)
                btn.BackgroundColor3 = Color3.fromRGB(45, 45, 55)
                btn.Text = "🎁 " .. obj.Name
                btn.TextColor3 = Color3.fromRGB(255, 200, 100)
                btn.TextSize = 12
                btn.TextXAlignment = Enum.TextXAlignment.Left
                btn.Parent = listUI
                Instance.new("UICorner", btn).CornerRadius = UDim.new(0, 4)
                
                local padding = Instance.new("UIPadding", btn)
                padding.PaddingLeft = UDim.new(0, 8)
                
                btn.MouseButton1Click:Connect(function()
                    local _, hrp = getParts()
                    if not hrp then return end
                    pcall(function()
                        local clone = obj:Clone()
                        if clone:IsA("Tool") then
                            clone.Parent = LP:FindFirstChild("Backpack")
                        else
                            local hasTool = false
                            for _, child in ipairs(clone:GetChildren()) do
                                if child:IsA("Tool") then
                                    child.Parent = LP:FindFirstChild("Backpack")
                                    hasTool = true
                                end
                            end
                            if not hasTool and clone:IsA("Model") then
                                clone:PivotTo(hrp.CFrame * CFrame.new(0, 5, -10))
                                clone.Parent = Workspace
                            end
                        end
                    end)
                end)
            end
        end
    end
    
    if foundCount == 0 then
        local lbl = Instance.new("TextLabel")
        lbl.Size = UDim2.new(1, 0, 0, 30)
        lbl.BackgroundTransparency = 1
        lbl.Text = "未找到相关道具/武器..."
        lbl.TextColor3 = Color3.fromRGB(150, 150, 150)
        lbl.TextSize = 12
        lbl.Parent = listUI
    end
end

-- ============================================================
-- 玩家 ESP
-- ============================================================
local espData = {}
local function createESP(plr)
    if plr == LP or espData[plr] or not plr.Character then return end
    local hrp = plr.Character:FindFirstChild("HumanoidRootPart")
    if not hrp then return end

    local hl = Instance.new("Highlight")
    hl.Name = "UVA_HL"
    hl.Adornee = plr.Character
    hl.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
    hl.FillColor = Color3.fromRGB(255, 60, 60)
    hl.OutlineColor = Color3.fromRGB(255, 255, 255)
    hl.FillTransparency = 0.5
    hl.Parent = plr.Character

    local bb = Instance.new("BillboardGui")
    bb.Name = "UVA_BB"
    bb.Adornee = hrp
    bb.Size = UDim2.new(0, 170, 0, 46)
    bb.StudsOffset = Vector3.new(0, 3, 0)
    bb.AlwaysOnTop = true
    bb.Parent = plr.Character

    local lbl = Instance.new("TextLabel")
    lbl.Size = UDim2.fromScale(1, 1)
    lbl.BackgroundTransparency = 1
    lbl.TextColor3 = Color3.fromRGB(255, 255, 255)
    lbl.TextStrokeTransparency = 0.3
    lbl.TextSize = 14
    lbl.Font = Enum.Font.GothamBold
    lbl.Parent = bb

    espData[plr] = { hl = hl, bb = bb, lbl = lbl }
end

local function removeESP(plr)
    if espData[plr] then
        if espData[plr].hl then espData[plr].hl:Destroy() end
        if espData[plr].bb then espData[plr].bb:Destroy() end
        espData[plr] = nil
    end
end

local function refreshESP()
    for plr in pairs(espData) do removeESP(plr) end
    if states.ESP then
        for _, plr in ipairs(Players:GetPlayers()) do createESP(plr) end
    end
end

addConn(RunService.RenderStepped:Connect(function()
    if not states.ESP then return end
    local myChar = LP.Character
    local myHRP = myChar and myChar:FindFirstChild("HumanoidRootPart")
    for plr, d in pairs(espData) do
        local char = plr.Character
        local hrp = char and char:FindFirstChild("HumanoidRootPart")
        local hum = char and char:FindFirstChildOfClass("Humanoid")
        if not (hrp and hum and hum.Health > 0) then
            d.hl.Enabled = false; d.bb.Enabled = false; continue
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
    end
end))

-- ============================================================
-- NPC 透视
-- ============================================================
local npcESPData = {}

local function createNPCESP(model, head)
    if npcESPData[model] then return end
    local hl = Instance.new("Highlight")
    hl.Name = "UVA_NPC_HL"
    hl.Adornee = model
    hl.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
    hl.FillColor = Color3.fromRGB(255, 200, 60)
    hl.OutlineColor = Color3.fromRGB(255, 255, 255)
    hl.FillTransparency = 0.6
    hl.Parent = model

    local bb = Instance.new("BillboardGui")
    bb.Name = "UVA_NPC_BB"
    bb.Adornee = head
    bb.Size = UDim2.new(0, 160, 0, 30)
    bb.StudsOffset = Vector3.new(0, 3, 0)
    bb.AlwaysOnTop = true
    bb.Parent = model

    local lbl = Instance.new("TextLabel")
    lbl.Size = UDim2.fromScale(1, 1)
    lbl.BackgroundTransparency = 1
    lbl.Text = "🤖 " .. model.Name
    lbl.TextColor3 = Color3.fromRGB(255, 220, 100)
    lbl.TextStrokeTransparency = 0.3
    lbl.TextSize = 12
    lbl.Font = Enum.Font.GothamBold
    lbl.Parent = bb

    npcESPData[model] = { hl = hl, bb = bb, lbl = lbl }
end

local function removeNPCESP(model)
    if npcESPData[model] then
        if npcESPData[model].hl then npcESPData[model].hl:Destroy() end
        if npcESPData[model].bb then npcESPData[model].bb:Destroy() end
        npcESPData[model] = nil
    end
end

local function refreshNPCESP()
    for model in pairs(npcESPData) do removeNPCESP(model) end
    if not states.NPCESP then return end
    for _, obj in ipairs(Workspace:GetDescendants()) do
        if obj:IsA("Model") and obj ~= LP.Character then
            local hum = obj:FindFirstChildOfClass("Humanoid")
            if hum and not Players:GetPlayerFromCharacter(obj) then
                local head = obj:FindFirstChild("Head") or obj:FindFirstChild("HumanoidRootPart")
                if head then createNPCESP(obj, head) end
            end
        end
    end
end

task.spawn(function()
    while task.wait(2) do
        if not states.NPCESP then continue end
        for _, obj in ipairs(Workspace:GetDescendants()) do
            if obj:IsA("Model") and obj ~= LP.Character and not npcESPData[obj] then
                local hum = obj:FindFirstChildOfClass("Humanoid")
                if hum and not Players:GetPlayerFromCharacter(obj) then
                    local head = obj:FindFirstChild("Head") or obj:FindFirstChild("HumanoidRootPart")
                    if head then createNPCESP(obj, head) end
                end
            end
        end
        for model in pairs(npcESPData) do
            if not model.Parent then removeNPCESP(model) end
        end
    end
end)

addConn(RunService.RenderStepped:Connect(function()
    if not states.NPCESP then return end
    local _, myHRP = getParts()
    for model, d in pairs(npcESPData) do
        local hum = model:FindFirstChildOfClass("Humanoid")
        if not (hum and hum.Health > 0) then
            d.hl.Enabled = false; d.bb.Enabled = false; continue
        end
        d.hl.Enabled = true
        local head = model:FindFirstChild("Head") or model:FindFirstChild("HumanoidRootPart")
        if head and myHRP then
            local dist = math.floor((myHRP.Position - head.Position).Magnitude)
            d.lbl.Text = "🤖 " .. model.Name .. " [" .. dist .. "m]"
        end
        d.bb.Enabled = true
    end
end))

-- ============================================================
-- 视角飞行
-- ============================================================
addConn(RunService.RenderStepped:Connect(function()
    if not states.Fly then return end
    local _, hrp, hum = getParts()
    if not hrp or not hum then stopFly(); return end

    if not flyBV or flyBV.Parent ~= hrp then
        if flyBV then flyBV:Destroy() end
        if flyBG then flyBG:Destroy() end
        flyBV = Instance.new("BodyVelocity")
        flyBV.MaxForce = Vector3.new(1e6, 1e6, 1e6)
        flyBV.Parent = hrp
        
        flyBG = Instance.new("BodyGyro")
        flyBG.MaxTorque = Vector3.new(1e6, 1e6, 1e6)
        flyBG.P = 3000; flyBG.D = 50
        flyBG.Parent = hrp
    end

    local camCF = Camera.CFrame
    local look = camCF.LookVector
    local right = camCF.RightVector
    local up = Vector3.new(0, 1, 0)

    local finalDir = Vector3.zero
    local moveDir = hum.MoveDirection 

    if moveDir.Magnitude > 0.05 then
        local flatLook = Vector3.new(look.X, 0, look.Z)
        local flatRight = Vector3.new(right.X, 0, right.Z)
        if flatLook.Magnitude > 0.01 then flatLook = flatLook.Unit end
        if flatRight.Magnitude > 0.01 then flatRight = flatRight.Unit end
        local fwd = moveDir:Dot(flatLook)
        local side = moveDir:Dot(flatRight)
        finalDir = (look * fwd + right * side)
    end

    if _G.FlyUpPressed then finalDir = finalDir + up end
    if _G.FlyDownPressed then finalDir = finalDir - up end

    if finalDir.Magnitude > 0 then finalDir = finalDir.Unit end
    flyBV.Velocity = finalDir * states.FlySpeed

    if not states.Spin then
        local flatLook = Vector3.new(look.X, 0, look.Z)
        if flatLook.Magnitude > 1e-3 then
            flyBG.CFrame = CFrame.lookAt(hrp.Position, hrp.Position + flatLook.Unit)
        end
    end
end))

-- ============================================================
-- 车辆加速 + 飞车
-- ============================================================
addConn(RunService.RenderStepped:Connect(function()
    if not (carState.CarFly or carState.CarBoost) then
        if carBV then carBV:Destroy(); carBV = nil end
        if carBG then carBG:Destroy(); carBG = nil end
        return
    end

    local seat, root = getVehicle()
    if not root or not seat then
        if carBV then carBV:Destroy(); carBV = nil end
        if carBG then carBG:Destroy(); carBG = nil end
        return
    end

    if not carBV or carBV.Parent ~= root then
        if carBV then carBV:Destroy() end
        if carBG then carBG:Destroy() end
        carBV = Instance.new("BodyVelocity")
        carBV.MaxForce = Vector3.new(1e6, 1e6, 1e6)
        carBV.Parent = root
        carBG = Instance.new("BodyGyro")
        carBG.MaxTorque = Vector3.new(1e6, 1e6, 1e6)
        carBG.P = 5000; carBG.D = 100
        carBG.Parent = root
    end

    local camCF = Camera.CFrame
    local look = camCF.LookVector
    local right = camCF.RightVector
    local up = Vector3.new(0, 1, 0)

    local throttle = seat.ThrottleFloat or 0
    local steer = seat.SteerFloat or 0

    local flatLook = Vector3.new(look.X, 0, look.Z)
    local flatRight = Vector3.new(right.X, 0, right.Z)
    if flatLook.Magnitude > 0.01 then flatLook = flatLook.Unit end
    if flatRight.Magnitude > 0.01 then flatRight = flatRight.Unit end

    local finalDir = flatLook * throttle + flatRight * steer
    local speed = 0

    if carState.CarFly then
        if _G.FlyUpPressed then finalDir = finalDir + up end
        if _G.FlyDownPressed then finalDir = finalDir - up end
        if finalDir.Magnitude < 0.01 then finalDir = look end
        speed = carState.CarSpeed
    elseif carState.CarBoost then
        if finalDir.Magnitude < 0.01 then finalDir = flatLook end
        speed = carState.CarBoostPower
    end

    if finalDir.Magnitude > 0 then finalDir = finalDir.Unit end
    carBV.Velocity = finalDir * speed

    local flatFinal = Vector3.new(finalDir.X, 0, finalDir.Z)
    if flatFinal.Magnitude > 0.01 then
        carBG.CFrame = CFrame.lookAt(root.Position, root.Position + flatFinal.Unit)
    end
end))

-- ============================================================
-- UI 系统
-- ============================================================
for _, name in ipairs({"UVA_HUB_UI", "UVA_Fold"}) do
    local old = LP.PlayerGui:FindFirstChild(name)
    if old then old:Destroy() end
end

local gui = Instance.new("ScreenGui")
gui.Name = "UVA_HUB_UI"
gui.ResetOnSpawn = false
gui.Parent = LP:WaitForChild("PlayerGui")

local uiScale = Instance.new("UIScale")
uiScale.Parent = gui
if Camera.ViewportSize.X < 800 then uiScale.Scale = 0.65 else uiScale.Scale = 0.85 end

local floatBall = Instance.new("TextButton")
floatBall.Size = UDim2.fromOffset(60, 60)
floatBall.Position = UDim2.new(0, 30, 0.5, -30)
floatBall.BackgroundColor3 = Color3.fromRGB(25, 25, 30)
floatBall.Text = "UVA"
floatBall.TextColor3 = Color3.fromRGB(0, 255, 100)
floatBall.Font = Enum.Font.GothamBlack
floatBall.TextSize = 16
floatBall.BorderSizePixel = 0
floatBall.Parent = gui
Instance.new("UICorner", floatBall).CornerRadius = UDim.new(1, 0)
Instance.new("UIStroke", floatBall).Color = Color3.fromRGB(0, 255, 100)

local flyControls = Instance.new("Frame")
flyControls.Size = UDim2.fromOffset(70, 160)
flyControls.Position = UDim2.new(1, -100, 0.5, -80)
flyControls.BackgroundTransparency = 1
flyControls.Visible = false
flyControls.Parent = gui

local function makeFlyBtn(text, yPos)
    local btn = Instance.new("TextButton")
    btn.Size = UDim2.fromOffset(70, 70)
    btn.Position = UDim2.fromOffset(0, yPos)
    btn.BackgroundColor3 = Color3.fromRGB(30, 30, 40)
    btn.BackgroundTransparency = 0.3
    btn.Text = text
    btn.TextColor3 = Color3.fromRGB(0, 255, 100)
    btn.Font = Enum.Font.GothamBlack
    btn.TextSize = 24
    btn.Parent = flyControls
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
makeFlyBtn("▲", 0)
makeFlyBtn("▼", 90)

local main = Instance.new("Frame")
main.Size = UDim2.fromOffset(600, 400)
main.Position = UDim2.new(0.5, -300, 0.5, -200)
main.BackgroundColor3 = Color3.fromRGB(25, 25, 30)
main.BackgroundTransparency = 0.1
main.BorderSizePixel = 0
main.Active = true
main.Visible = false
main.Parent = gui
Instance.new("UICorner", main).CornerRadius = UDim.new(0, 12)
Instance.new("UIStroke", main).Color = Color3.fromRGB(50, 50, 60)

local sidebar = Instance.new("Frame")
sidebar.Size = UDim2.new(0, 140, 1, 0)
sidebar.BackgroundColor3 = Color3.fromRGB(15, 15, 20)
sidebar.BorderSizePixel = 0
sidebar.Parent = main
Instance.new("UICorner", sidebar).CornerRadius = UDim.new(0, 12)

local title = Instance.new("TextLabel")
title.Size = UDim2.new(1, 0, 0, 50)
title.BackgroundTransparency = 1
title.Text = "黑洞中心(BS)"
title.TextColor3 = Color3.fromRGB(0, 255, 100)
title.Font = Enum.Font.GothamBlack
title.TextSize = 18
title.Parent = sidebar

local contentFrame = Instance.new("Frame")
contentFrame.Size = UDim2.new(1, -150, 1, -20)
contentFrame.Position = UDim2.new(0, 145, 0, 10)
contentFrame.BackgroundTransparency = 1
contentFrame.Parent = main

local minBtn = Instance.new("TextButton")
minBtn.Size = UDim2.fromOffset(30, 30)
minBtn.Position = UDim2.new(1, -40, 0, 10)
minBtn.BackgroundColor3 = Color3.fromRGB(200, 50, 50)
minBtn.Text = "×"
minBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
minBtn.Font = Enum.Font.GothamBold
minBtn.TextSize = 20
minBtn.Parent = main
Instance.new("UICorner", minBtn).CornerRadius = UDim.new(0, 6)

local pages = {}

-- ★★★ 终极版 createPage ★★★
local function createPage(name)
    local page = Instance.new("ScrollingFrame")
    page.Size = UDim2.fromScale(1, 1)
    page.BackgroundTransparency = 1
    page.BorderSizePixel = 0
    page.ScrollBarThickness = 4
    page.ScrollBarImageColor3 = Color3.fromRGB(100, 100, 100)
    page.ScrollingDirection = Enum.ScrollingDirection.Y
    page.ElasticBehavior = Enum.ElasticBehavior.Never
    page.CanvasSize = UDim2.new(0, 0, 0, 0)
    page.Visible = false
    page.Parent = contentFrame

    local pad = Instance.new("UIPadding", page)
    pad.PaddingTop = UDim.new(0, 6)
    pad.PaddingBottom = UDim.new(0, 6)
    pad.PaddingLeft = UDim.new(0, 4)
    pad.PaddingRight = UDim.new(0, 4)

    local layout = Instance.new("UIListLayout", page)
    layout.Padding = UDim.new(0, 10)
    layout.SortOrder = Enum.SortOrder.LayoutOrder

    local function syncCanvas()
        local maxY = layout.AbsoluteContentSize.Y
        for _, child in ipairs(page:GetChildren()) do
            if child:IsA("GuiObject") then
                local bottom = (child.AbsolutePosition.Y - page.AbsolutePosition.Y) + child.AbsoluteSize.Y
                if bottom > maxY then maxY = bottom end
            end
        end
        page.CanvasSize = UDim2.new(0, 0, 0, maxY + 600)
    end

    layout:GetPropertyChangedSignal("AbsoluteContentSize"):Connect(function()
        syncCanvas()
        task.defer(syncCanvas)
    end)
    syncCanvas()

    task.spawn(function()
        while page.Parent do
            task.wait(0.3)
            syncCanvas()
        end
    end)

    pages[name] = page
    return page
end

local navBtns = {}

-- ★★★ 终极版 switchPage ★★★
local function switchPage(pageName, btn)
    for n, p in pairs(pages) do p.Visible = (n == pageName) end

    local function fixCanvas()
        local p = pages[pageName]
        if not p then return end
        local lay = p:FindFirstChildOfClass("UIListLayout")
        if not lay then return end
        local maxY = lay.AbsoluteContentSize.Y
        for _, child in ipairs(p:GetChildren()) do
            if child:IsA("GuiObject") then
                local bottom = (child.AbsolutePosition.Y - p.AbsolutePosition.Y) + child.AbsoluteSize.Y
                if bottom > maxY then maxY = bottom end
            end
        end
        p.CanvasSize = UDim2.new(0, 0, 0, maxY + 600)
    end
    task.defer(fixCanvas)
    task.delay(0.15, fixCanvas)
    task.delay(0.4, fixCanvas)

    for _, b in pairs(navBtns) do
        b.TextColor3 = Color3.fromRGB(150, 150, 150)
        b.BackgroundTransparency = 1
    end
    if btn then
        btn.TextColor3 = Color3.fromRGB(0, 255, 100)
        btn.BackgroundTransparency = 0.8
        btn.BackgroundColor3 = Color3.fromRGB(0, 255, 100)
    end
end

local function createNavBtn(text, yOffset, pageName)
    local btn = Instance.new("TextButton")
    btn.Size = UDim2.new(1, -20, 0, 40)
    btn.Position = UDim2.new(0, 10, 0, yOffset)
    btn.BackgroundTransparency = 1
    btn.Text = text
    btn.TextColor3 = Color3.fromRGB(150, 150, 150)
    btn.Font = Enum.Font.GothamBold
    btn.TextSize = 14
    btn.TextXAlignment = Enum.TextXAlignment.Left
    btn.Parent = sidebar
    Instance.new("UICorner", btn).CornerRadius = UDim.new(0, 6)
    table.insert(navBtns, btn)
    btn.MouseButton1Click:Connect(function() switchPage(pageName, btn) end)
    if not next(pages) then switchPage(pageName, btn) end
end

local function createGroup(parent, titleText, order)
    local group = Instance.new("Frame")
    group.Size = UDim2.new(1, -10, 0, 0)
    group.AutomaticSize = Enum.AutomaticSize.Y
    group.BackgroundColor3 = Color3.fromRGB(35, 35, 45)
    group.BackgroundTransparency = 0.2
    group.BorderSizePixel = 0
    group.LayoutOrder = order
    group.Parent = parent
    Instance.new("UICorner", group).CornerRadius = UDim.new(0, 8)

    local padding = Instance.new("UIPadding", group)
    padding.PaddingTop = UDim.new(0, 10)
    padding.PaddingBottom = UDim.new(0, 10)
    padding.PaddingLeft = UDim.new(0, 10)
    padding.PaddingRight = UDim.new(0, 10)

    local groupLayout = Instance.new("UIListLayout", group)
    groupLayout.Padding = UDim.new(0, 6)
    groupLayout.SortOrder = Enum.SortOrder.LayoutOrder

    local title = Instance.new("TextLabel")
    title.Size = UDim2.new(1, 0, 0, 20)
    title.BackgroundTransparency = 1
    title.Text = "📁 " .. titleText
    title.TextColor3 = Color3.fromRGB(200, 200, 200)
    title.Font = Enum.Font.GothamBold
    title.TextSize = 14
    title.TextXAlignment = Enum.TextXAlignment.Left
    title.LayoutOrder = 1
    title.Parent = group

    local list = Instance.new("Frame")
    list.Size = UDim2.new(1, 0, 0, 0)
    list.AutomaticSize = Enum.AutomaticSize.Y
    list.BackgroundTransparency = 1
    list.LayoutOrder = 2
    list.Parent = group
    local layout = Instance.new("UIListLayout", list)
    layout.Padding = UDim.new(0, 8)
    layout.SortOrder = Enum.SortOrder.LayoutOrder

    return list
end

local function addToggle(parent, text, initState, callback)
    local btn = Instance.new("TextButton")
    btn.Size = UDim2.new(1, 0, 0, 36)
    btn.BackgroundColor3 = initState and Color3.fromRGB(0, 200, 80) or Color3.fromRGB(45, 45, 55)
    btn.Text = text
    btn.TextColor3 = Color3.fromRGB(255, 255, 255)
    btn.Font = Enum.Font.GothamBold
    btn.TextSize = 13
    btn.Parent = parent
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
    btn.Size = UDim2.new(1, 0, 0, 36)
    btn.BackgroundColor3 = Color3.fromRGB(45, 45, 55)
    btn.Text = text
    btn.TextColor3 = Color3.fromRGB(255, 255, 255)
    btn.Font = Enum.Font.GothamBold
    btn.TextSize = 13
    btn.Parent = parent
    Instance.new("UICorner", btn).CornerRadius = UDim.new(0, 6)
    btn.MouseButton1Click:Connect(callback)
    return btn
end

local function addInput(parent, text, initVal, callback)
    local frame = Instance.new("Frame")
    frame.Size = UDim2.new(1, 0, 0, 36)
    frame.BackgroundColor3 = Color3.fromRGB(45, 45, 55)
    frame.Parent = parent
    Instance.new("UICorner", frame).CornerRadius = UDim.new(0, 6)
    local lbl = Instance.new("TextLabel")
    lbl.Size = UDim2.new(0.5, 0, 1, 0); lbl.BackgroundTransparency = 1
    lbl.Text = text; lbl.TextColor3 = Color3.fromRGB(200, 200, 200)
    lbl.Font = Enum.Font.GothamBold; lbl.TextXAlignment = Enum.TextXAlignment.Left
    lbl.Parent = frame; lbl.Position = UDim2.fromOffset(10, 0)
    local box = Instance.new("TextBox")
    box.Size = UDim2.new(0.4, 0, 0.8, 0); box.Position = UDim2.new(0.55, 0, 0.1, 0)
    box.BackgroundColor3 = Color3.fromRGB(30, 30, 40)
    box.Text = tostring(initVal); box.TextColor3 = Color3.fromRGB(0, 255, 100)
    box.Font = Enum.Font.GothamBold; box.Parent = frame
    Instance.new("UICorner", box).CornerRadius = UDim.new(0, 4)
    box.FocusLost:Connect(function()
        local n = tonumber(box.Text)
        if n then callback(n) else box.Text = tostring(initVal) end
    end)
end

local function addTextInput(parent, text, initVal, callback)
    local frame = Instance.new("Frame")
    frame.Size = UDim2.new(1, 0, 0, 36)
    frame.BackgroundColor3 = Color3.fromRGB(45, 45, 55)
    frame.Parent = parent
    Instance.new("UICorner", frame).CornerRadius = UDim.new(0, 6)
    local lbl = Instance.new("TextLabel")
    lbl.Size = UDim2.new(0.32, 0, 1, 0); lbl.BackgroundTransparency = 1
    lbl.Text = text; lbl.TextColor3 = Color3.fromRGB(200, 200, 200)
    lbl.Font = Enum.Font.GothamBold; lbl.TextXAlignment = Enum.TextXAlignment.Left
    lbl.Parent = frame; lbl.Position = UDim2.fromOffset(10, 0)
    local box = Instance.new("TextBox")
    box.Size = UDim2.new(0.65, -10, 0.8, 0); box.Position = UDim2.new(0.34, 0, 0.1, 0)
    box.BackgroundColor3 = Color3.fromRGB(30, 30, 40)
    box.Text = tostring(initVal); box.TextColor3 = Color3.fromRGB(0, 255, 100)
    box.Font = Enum.Font.GothamBold; box.Parent = frame
    box.ClearTextOnFocus = false
    Instance.new("UICorner", box).CornerRadius = UDim.new(0, 4)
    box.FocusLost:Connect(function() callback(box.Text) end)
    return box
end

-- ---------- 1. 移动与飞行 ----------
local movePage = createPage("Move")
local grpMove = createGroup(movePage, "移动与防护", 1)
addToggle(grpMove, "开启飞行 (推摇杆即飞)", states.Fly, function(v) 
    if v then startFly() else stopFly() end 
    flyControls.Visible = v or carState.CarFly
end)
addToggle(grpMove, "无限跳跃 (点击/长按)", states.InfJump, function(v) states.InfJump = v end)
addToggle(grpMove, "穿墙 (Noclip)", states.Noclip, function(v) if v then startNoclip() else stopNoclip() end end)
addToggle(grpMove, "防虚空掉落", states.AntiVoid, function(v) states.AntiVoid = v end)
addToggle(grpMove, "防甩飞 (苛刻版)", states.AntiFling, function(v) states.AntiFling = v end) 

local grpCar = createGroup(movePage, "🚗 车辆改装", 2)
addToggle(grpCar, "飞车 (视角控制 3D 飞行)", carState.CarFly, function(v)
    if v then
        carState.CarFly = true
        flyControls.Visible = true
    else
        stopCarFly()
        flyControls.Visible = states.Fly
    end
end)
addToggle(grpCar, "车辆加速 (视角水平飞驰)", carState.CarBoost, function(v)
    if v then carState.CarBoost = true else stopCarBoost() end
end)
addInput(grpCar, "飞车速度", carState.CarSpeed, function(v) carState.CarSpeed = v end)
addInput(grpCar, "加速速度", carState.CarBoostPower, function(v) carState.CarBoostPower = v end)

local grpGravity = createGroup(movePage, "重力快捷设置", 3)
addButton(grpGravity, "零重力 (G=0)", function() states.CustomGravity = 0; workspace.Gravity = 0 end)
addButton(grpGravity, "月球重力 (G=16)", function() states.CustomGravity = 16; workspace.Gravity = 16 end)
addButton(grpGravity, "恢复默认重力 (G=196.2)", function() states.CustomGravity = 196.2; workspace.Gravity = 196.2 end)

local grpStats = createGroup(movePage, "属性修改", 4)
addInput(grpStats, "移动速度", states.WalkSpeed, function(v) states.WalkSpeed = v; applyStats() end)
addInput(grpStats, "跳跃力量", states.JumpPower, function(v) states.JumpPower = v; applyStats() end)
addInput(grpStats, "飞行速度", states.FlySpeed, function(v) states.FlySpeed = v end)
addInput(grpStats, "自定义重力(G)", states.CustomGravity, function(v) states.CustomGravity = v; workspace.Gravity = v end)

-- ---------- 2. 传送与工具 ----------
local playerPage = createPage("Player")
local grpTP = createGroup(playerPage, "快捷传送", 1)
addToggle(grpTP, "点击屏幕传送 (Click TP)", states.ClickTP, function(v) states.ClickTP = v end)
addButton(grpTP, "保存当前坐标", function(btn)
    local _, hrp = getParts()
    if hrp then savedCFrame = hrp.CFrame; btn.Text = "已保存坐标" end
end)
addButton(grpTP, "传送到保存点", function()
    local _, hrp = getParts()
    if hrp and savedCFrame then hrp.CFrame = savedCFrame end
end)

local grpPlayers = createGroup(playerPage, "玩家列表 (实时更新)", 2)
local playerScroll = Instance.new("ScrollingFrame")
playerScroll.Size = UDim2.new(1, 0, 0, 180)
playerScroll.BackgroundTransparency = 1
playerScroll.BorderSizePixel = 0
playerScroll.ScrollBarThickness = 4
playerScroll.AutomaticCanvasSize = Enum.AutomaticSize.Y
playerScroll.CanvasSize = UDim2.new(0, 0, 0, 0)
playerScroll.Parent = grpPlayers
local listLayout = Instance.new("UIListLayout", playerScroll)
listLayout.Padding = UDim.new(0, 4)

local function updatePlayerList()
    for _, child in ipairs(playerScroll:GetChildren()) do
        if child:IsA("TextButton") then child:Destroy() end
    end
    for _, p in ipairs(Players:GetPlayers()) do
        if p ~= LP then
            local btn = Instance.new("TextButton")
            btn.Size = UDim2.new(1, -4, 0, 32)
            btn.BackgroundColor3 = Color3.fromRGB(45, 45, 55)
            btn.Text = "👤 " .. p.Name
            btn.TextColor3 = Color3.fromRGB(0, 255, 100)
            btn.Font = Enum.Font.GothamBold
            btn.TextSize = 13
            btn.TextXAlignment = Enum.TextXAlignment.Left
            btn.Parent = playerScroll
            Instance.new("UICorner", btn).CornerRadius = UDim.new(0, 4)
            local padding = Instance.new("UIPadding", btn)
            padding.PaddingLeft = UDim.new(0, 10)
            btn.MouseButton1Click:Connect(function()
                local _, myHRP = getParts()
                local targetHRP = p.Character and p.Character:FindFirstChild("HumanoidRootPart")
                if myHRP and targetHRP then
                    myHRP.CFrame = targetHRP.CFrame * CFrame.new(0, 3, 3)
                end
            end)
        end
    end
end
Players.PlayerAdded:Connect(updatePlayerList)
Players.PlayerRemoving:Connect(function() task.wait(0.5); updatePlayerList() end)
task.spawn(updatePlayerList) 

local grpFling = createGroup(playerPage, "恶搞甩飞", 3)
addInput(grpFling, "甩飞力度 (越大越卡)", states.FlingPower, function(v) states.FlingPower = v end)
addButton(grpFling, "🚀 甩飞全图玩家", flingAll)
addButton(grpFling, "🚀 甩飞附近玩家 (30米内)", function()
    local _, myHRP = getParts()
    if not myHRP then return end
    for _, p in ipairs(Players:GetPlayers()) do
        if p ~= LP and p.Character then
            local targetHRP = p.Character:FindFirstChild("HumanoidRootPart")
            if targetHRP and (myHRP.Position - targetHRP.Position).Magnitude < 30 then
                flingPlayer(p.Character)
            end
        end
    end
end)

local grpBattle = createGroup(playerPage, "实用小工具", 4)
addToggle(grpBattle, "自动点击 (挂机)", states.AutoClick, function(v) states.AutoClick = v end)
addToggle(grpBattle, "自转", states.Spin, function(v) if v then startSpin() else stopSpin() end end)
addButton(grpBattle, "💥 一键蹦服 (假装)", fakeCrash)

local grpChat = createGroup(playerPage, "💬 自动发言", 5)
addTextInput(grpChat, "消息内容", chatState.message, function(v) chatState.message = v end)
addInput(grpChat, "发言数量", chatState.totalCount, function(v) chatState.totalCount = math.floor(v) end)
addInput(grpChat, "间隔(秒)", chatState.interval, function(v) chatState.interval = v end)
addToggle(grpChat, "启动自动发言 (发完后自动停止)", false, function(v)
    if v then startAutoChat() else stopAutoChat() end
end)
local chatStatusLbl = Instance.new("TextLabel")
chatStatusLbl.Size = UDim2.new(1, 0, 0, 24)
chatStatusLbl.BackgroundTransparency = 1
chatStatusLbl.Text = "状态: 待机"
chatStatusLbl.TextColor3 = Color3.fromRGB(150, 150, 150)
chatStatusLbl.Font = Enum.Font.GothamBold
chatStatusLbl.TextSize = 12
chatStatusLbl.Parent = grpChat
task.spawn(function()
    while task.wait(0.5) do
        if chatState.enabled then
            chatStatusLbl.Text = "状态: 发送中 (" .. chatState.sentCount .. "/" .. chatState.totalCount .. ")"
            chatStatusLbl.TextColor3 = Color3.fromRGB(0, 255, 100)
        else
            chatStatusLbl.Text = "状态: 待机"
            chatStatusLbl.TextColor3 = Color3.fromRGB(150, 150, 150)
        end
    end
end)

local grpInteract = createGroup(playerPage, "🤝 自动互动", 6)
addToggle(grpInteract, "自动触发附近 ProximityPrompt", states.AutoInteract, function(v) states.AutoInteract = v end)
addInput(grpInteract, "互动半径 (米)", states.InteractRadius, function(v) states.InteractRadius = v end)

local grpQuick = createGroup(playerPage, "⚡ 快速互动", 7)
addToggle(grpQuick, "开启快速互动 (瞬发+穿墙)", states.QuickInteract, function(v)
    states.QuickInteract = v
    if v then
        applyQuickInteract()
    else
        restoreQuickInteract()
    end
end)
addInput(grpQuick, "互动距离 (米)", states.QuickInteractDist, function(v)
    states.QuickInteractDist = v
    if states.QuickInteract then applyQuickInteract() end
end)

-- ---------- 3. 物品 ----------
local itemPage = createPage("Items")
local grpSteal = createGroup(itemPage, "物品夺取", 1)
addButton(grpSteal, "强行夺取所有玩家工具", forceStealTools)
addButton(grpSteal, "清空自己背包", clearMyBackpack)

local grpServerItems = createGroup(itemPage, "精准道具提取 (过滤地图)", 2)
local searchFrame = Instance.new("Frame")
searchFrame.Size = UDim2.new(1, 0, 0, 36)
searchFrame.BackgroundColor3 = Color3.fromRGB(45, 45, 55)
searchFrame.Parent = grpServerItems
Instance.new("UICorner", searchFrame).CornerRadius = UDim.new(0, 6)
local searchBox = Instance.new("TextBox")
searchBox.Size = UDim2.new(1, -10, 1, -10)
searchBox.Position = UDim2.new(0, 5, 0, 5)
searchBox.BackgroundColor3 = Color3.fromRGB(30, 30, 40)
searchBox.PlaceholderText = "输入道具名（如 Sword 留空搜全部）"
searchBox.PlaceholderColor3 = Color3.fromRGB(150, 150, 150)
searchBox.Text = ""
searchBox.TextColor3 = Color3.fromRGB(0, 255, 100)
searchBox.Font = Enum.Font.GothamBold
searchBox.TextSize = 13
searchBox.Parent = searchFrame
Instance.new("UICorner", searchBox).CornerRadius = UDim.new(0, 4)

local searchBtn = Instance.new("TextButton")
searchBtn.Size = UDim2.new(1, 0, 0, 36)
searchBtn.BackgroundColor3 = Color3.fromRGB(0, 200, 80)
searchBtn.Text = "🔍 深度提取全服道具"
searchBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
searchBtn.Font = Enum.Font.GothamBold
searchBtn.TextSize = 13
searchBtn.Parent = grpServerItems
Instance.new("UICorner", searchBtn).CornerRadius = UDim.new(0, 6)

local itemScroll = Instance.new("ScrollingFrame")
itemScroll.Size = UDim2.new(1, 0, 0, 200)
itemScroll.BackgroundTransparency = 1
itemScroll.BorderSizePixel = 0
itemScroll.ScrollBarThickness = 4
itemScroll.AutomaticCanvasSize = Enum.AutomaticSize.Y
itemScroll.CanvasSize = UDim2.new(0, 0, 0, 0)
itemScroll.Parent = grpServerItems
local itemListLayout = Instance.new("UIListLayout", itemScroll)
itemListLayout.Padding = UDim.new(0, 4)

searchBtn.MouseButton1Click:Connect(function()
    searchBtn.Text = "搜索中..."
    task.wait(0.1)
    searchAndListItems(searchBox.Text, itemScroll)
    searchBtn.Text = "🔍 深度提取全服道具"
end)

-- ---------- 4. 视觉 ----------
local visualPage = createPage("Visual")
local grpESP = createGroup(visualPage, "透视 (ESP)", 1)
addToggle(grpESP, "开启透视", states.ESP, function(v) states.ESP = v; refreshESP() end)
addToggle(grpESP, "显示名字", states.ESPName, function(v) states.ESPName = v end)
addToggle(grpESP, "显示距离", states.ESPDist, function(v) states.ESPDist = v end)
addToggle(grpESP, "人物上色", states.ESPColor, function(v) states.ESPColor = v end)
addToggle(grpESP, "人物描边", states.ESPOutline, function(v) states.ESPOutline = v end)

local grpNPC = createGroup(visualPage, "🤖 NPC 透视", 2)
addToggle(grpNPC, "开启 NPC 透视 (金色高亮+距离)", states.NPCESP, function(v)
    states.NPCESP = v
    refreshNPCESP()
end)

local grpEnv = createGroup(visualPage, "环境修改", 3)
addToggle(grpEnv, "全亮 (Fullbright)", states.Fullbright, function(v) states.Fullbright = v; toggleFullbright(v) end)

-- ---------- 5. 系统 ----------
local homePage = createPage("Home")
local grpSys = createGroup(homePage, "系统设置", 1)
addToggle(grpSys, "防挂机 (Anti-AFK)", true, function(v) 
    if not v and antiAfkConn then antiAfkConn:Disconnect() elseif v then setupAntiAFK() end
end)
addButton(grpSys, "缩小UI大小", function()
    uiScale.Scale = uiScale.Scale - 0.1
    if uiScale.Scale < 0.4 then uiScale.Scale = 0.4 end
end)
addButton(grpSys, "放大UI大小", function()
    uiScale.Scale = uiScale.Scale + 0.1
    if uiScale.Scale > 1.2 then uiScale.Scale = 1.2 end
end)

createNavBtn("移动与防护", 60, "Move")
createNavBtn("传送与工具", 110, "Player")
createNavBtn("物品与黑科技", 160, "Items")
createNavBtn("视觉与透视", 210, "Visual")
createNavBtn("系统与设置", 260, "Home")

-- ============================================================
-- 交互逻辑
-- ============================================================
UserInputService.InputBegan:Connect(function(input)
    if not states.ClickTP then return end
    if input.UserInputType == Enum.UserInputType.Touch or input.UserInputType == Enum.UserInputType.MouseButton1 then
        local guiObjects = LP.PlayerGui:GetGuiObjectsAtPosition(input.Position.X, input.Position.Y)
        for _, obj in ipairs(guiObjects) do
            if obj:IsDescendantOf(main) or obj:IsDescendantOf(floatBall) or obj:IsDescendantOf(flyControls) then
                return 
            end
        end
        local mouse = LP:GetMouse()
        if mouse.Hit then
            local _, hrp = getParts()
            if hrp then
                hrp.CFrame = CFrame.new(mouse.Hit.Position + Vector3.new(0, 3, 0))
            end
        end
    end
end)

local ballDragging, ballStart, ballStartPos, ballMoved = false, nil, nil, false
floatBall.InputBegan:Connect(function(input)
    if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
        ballDragging = true; ballMoved = false; ballStart = input.Position; ballStartPos = floatBall.Position
    end
end)
UserInputService.InputChanged:Connect(function(input)
    if ballDragging and (input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch) then
        local delta = input.Position - ballStart
        if delta.Magnitude > 5 then ballMoved = true end
        floatBall.Position = UDim2.new(ballStartPos.X.Scale, ballStartPos.X.Offset + delta.X, ballStartPos.Y.Scale, ballStartPos.Y.Offset + delta.Y)
    end
end)
UserInputService.InputEnded:Connect(function(input)
    if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
        if ballDragging and not ballMoved then
            main.Visible = not main.Visible
            floatBall.Visible = not main.Visible
            if main.Visible then
                local px = floatBall.Position.X.Offset + 70
                local py = floatBall.Position.Y.Offset
                main.Position = UDim2.new(floatBall.Position.X.Scale, px, floatBall.Position.Y.Scale, py)
            end
        end
        ballDragging = false
    end
end)

minBtn.MouseButton1Click:Connect(function()
    main.Visible = false; floatBall.Visible = true
end)

local winDragging, winStart, winStartPos = false, nil, nil
sidebar.InputBegan:Connect(function(input)
    if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
        winDragging = true; winStart = input.Position; winStartPos = main.Position
    end
end)
UserInputService.InputChanged:Connect(function(input)
    if winDragging and (input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch) then
        local delta = input.Position - winStart
        main.Position = UDim2.new(winStartPos.X.Scale, winStartPos.X.Offset + delta.X, winStartPos.Y.Scale, winStartPos.Y.Offset + delta.Y)
    end
end)
UserInputService.InputEnded:Connect(function(input)
    if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
        winDragging = false
    end
end)

LP.CharacterAdded:Connect(function(char)
    states.Fly = false; states.Noclip = false; states.Spin = false
    carState.CarFly = false; carState.CarBoost = false
    flyControls.Visible = false
    lastValidCFrame = nil
    if flyBV then flyBV:Destroy(); flyBV = nil end
    if flyBG then flyBG:Destroy(); flyBG = nil end
    if spinAV then spinAV:Destroy(); spinAV = nil end
    if carBV then carBV:Destroy(); carBV = nil end
    if carBG then carBG:Destroy(); carBG = nil end
    if noclipConn then noclipConn:Disconnect(); noclipConn = nil end
    task.wait(1)
    applyStats()
end)

setupAntiAFK()
