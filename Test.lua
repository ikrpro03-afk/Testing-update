-- NOVA v38.0 | COMPLETE REWORK
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local TweenService = game:GetService("TweenService")
local Camera = workspace.CurrentCamera
local Player = Players.LocalPlayer

-- ============================================================
--  КОНФИГУРАЦИЯ AIM LOCK
-- ============================================================
local CONFIG = {
    AimPart = "Head",
    BackupPart = "UpperTorso",
    FOV = 50,
    Smoothness = 0.85,
    DistanceLimit = 250,
    PredictionStrength = 0.6,
    BulletSpeed = 1800,
    LostTimeout = 0.1,
    SearchInterval = 0.05,
    XRayUpdateInterval = 0.025,
    ShowFOV = true,
    CrosshairStyle = "DOT",
    CenterOffset = Vector2.new(0, 0),
}
local DIST_LIMIT_SQ = CONFIG.DistanceLimit * CONFIG.DistanceLimit

-- ============================================================
--  СОСТОЯНИЕ AIM LOCK
-- ============================================================
local State = {
    enabled = false,
    destroyed = false,
    target = nil,
    targetCF = nil,
    smoothCF = nil,
    killCount = 0,
    lostTimer = 0,
    searchTimer = 0,
    xrayTimer = 0,
    hue = 0,
}
local XRayState = {
    enabled = true,
    boxes = {},
    container = nil,
    partsCache = {},
    cacheTimers = {},
    CACHE_DURATION = 0.5,
}

-- ============================================================
--  ЦЕНТР ЭКРАНА
-- ============================================================
local function getCenter()
    local vp = Camera.ViewportSize
    return Vector2.new(vp.X / 2 + CONFIG.CenterOffset.X, vp.Y / 2 + CONFIG.CenterOffset.Y)
end

-- ============================================================
--  GUI (ЗАГРУЗКА + ОСНОВНОЙ)
-- ============================================================
local PlayerGui = Player:WaitForChild("PlayerGui")

-- -------------------- ЗАГРУЗОЧНЫЙ ЭКРАН --------------------
local function createLoadingScreen()
    local screen = Instance.new("ScreenGui")
    screen.Name = "LoadingScreen"
    screen.Parent = PlayerGui
    screen.DisplayOrder = 1000

    local overlay = Instance.new("Frame")
    overlay.Size = UDim2.new(1, 0, 1, 0)
    overlay.BackgroundColor3 = Color3.fromRGB(0, 0, 0)
    overlay.BackgroundTransparency = 0.8
    overlay.BorderSizePixel = 0
    overlay.Parent = screen

    local panel = Instance.new("Frame")
    panel.Size = UDim2.new(0, 360, 0, 200)
    panel.Position = UDim2.new(0.5, -180, 0.5, -100)
    panel.BackgroundColor3 = Color3.fromRGB(12, 18, 40)
    panel.BackgroundTransparency = 0.05
    panel.BorderSizePixel = 0
    panel.ClipsDescendants = true
    panel.Parent = screen

    local panelCorner = Instance.new("UICorner")
    panelCorner.CornerRadius = UDim.new(0, 20)
    panelCorner.Parent = panel

    local panelStroke = Instance.new("UIStroke")
    panelStroke.Color = Color3.fromRGB(60, 150, 255)
    panelStroke.Thickness = 1.5
    panelStroke.Transparency = 0.5
    panelStroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
    panelStroke.Parent = panel

    local logo = Instance.new("TextLabel")
    logo.Size = UDim2.new(0, 60, 0, 60)
    logo.Position = UDim2.new(0.5, -30, 0, 20)
    logo.BackgroundTransparency = 1
    logo.Text = "NOVA"
    logo.TextColor3 = Color3.fromRGB(100, 200, 255)
    logo.TextSize = 36
    logo.Font = Enum.Font.GothamBold
    logo.Parent = panel

    local ring = Instance.new("ImageLabel")
    ring.Size = UDim2.new(0, 70, 0, 70)
    ring.Position = UDim2.new(0.5, -35, 0, 15)
    ring.BackgroundTransparency = 1
    ring.Image = "rbxassetid://4911621264"
    ring.ImageColor3 = Color3.fromRGB(60, 150, 255)
    ring.ImageTransparency = 0.6
    ring.Parent = panel

    local statusText = Instance.new("TextLabel")
    statusText.Size = UDim2.new(1, 0, 0, 20)
    statusText.Position = UDim2.new(0, 0, 0, 90)
    statusText.BackgroundTransparency = 1
    statusText.Text = "Loading..."
    statusText.TextColor3 = Color3.fromRGB(200, 220, 255)
    statusText.TextSize = 14
    statusText.Font = Enum.Font.Gotham
    statusText.Parent = panel

    local versionText = Instance.new("TextLabel")
    versionText.Size = UDim2.new(1, 0, 0, 16)
    versionText.Position = UDim2.new(0, 0, 0, 115)
    versionText.BackgroundTransparency = 1
    versionText.Text = "v38.0"
    versionText.TextColor3 = Color3.fromRGB(150, 180, 220)
    versionText.TextSize = 11
    versionText.Font = Enum.Font.Gotham
    versionText.Parent = panel

    local progressBar = Instance.new("Frame")
    progressBar.Size = UDim2.new(0, 280, 0, 4)
    progressBar.Position = UDim2.new(0.5, -140, 0, 145)
    progressBar.BackgroundColor3 = Color3.fromRGB(30, 50, 80)
    progressBar.BorderSizePixel = 0
    progressBar.Parent = panel

    local barCorner = Instance.new("UICorner")
    barCorner.CornerRadius = UDim.new(0, 2)
    barCorner.Parent = progressBar

    local fill = Instance.new("Frame")
    fill.Size = UDim2.new(0, 0, 1, 0)
    fill.BackgroundColor3 = Color3.fromRGB(60, 150, 255)
    fill.BorderSizePixel = 0
    fill.Parent = progressBar

    local fillCorner = Instance.new("UICorner")
    fillCorner.CornerRadius = UDim.new(0, 2)
    fillCorner.Parent = fill

    return {
        screen = screen,
        ring = ring,
        statusText = statusText,
        fill = fill,
        panel = panel,
        logo = logo,
        versionText = versionText,
        progressBar = progressBar,
    }
end

-- -------------------- ОСНОВНОЙ GUI (ИКОНКИ) --------------------
local function buildMainGUI()
    local gui = Instance.new("ScreenGui")
    gui.Name = "NOVA_MAIN"
    gui.ResetOnSpawn = false
    gui.IgnoreGuiInset = true
    gui.Parent = PlayerGui
    gui.DisplayOrder = 999
    gui.Enabled = false  -- сначала скрыт

    local main = Instance.new("Frame")
    main.Size = UDim2.new(0, 260, 0, 280)
    main.Position = UDim2.new(0, 20, 0, 20)
    main.BackgroundColor3 = Color3.fromRGB(10, 18, 42)
    main.BackgroundTransparency = 0.05
    main.BorderSizePixel = 0
    main.ClipsDescendants = true
    main.Parent = gui

    local mainCorner = Instance.new("UICorner")
    mainCorner.CornerRadius = UDim.new(0, 16)
    mainCorner.Parent = main

    local mainStroke = Instance.new("UIStroke")
    mainStroke.Color = Color3.fromRGB(60, 150, 255)
    mainStroke.Thickness = 1.5
    mainStroke.Transparency = 0.5
    mainStroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
    mainStroke.Parent = main

    local header = Instance.new("Frame")
    header.Size = UDim2.new(1, 0, 0, 36)
    header.BackgroundColor3 = Color3.fromRGB(14, 24, 54)
    header.BackgroundTransparency = 0.1
    header.BorderSizePixel = 0
    header.Parent = main

    local headerCorner = Instance.new("UICorner")
    headerCorner.CornerRadius = UDim.new(0, 16)
    headerCorner.Parent = header

    local title = Instance.new("TextLabel")
    title.Size = UDim2.new(1, -60, 1, 0)
    title.Position = UDim2.new(0, 14, 0, 0)
    title.BackgroundTransparency = 1
    title.Text = "NOVA"
    title.TextColor3 = Color3.fromRGB(200, 230, 255)
    title.TextSize = 15
    title.TextXAlignment = Enum.TextXAlignment.Left
    title.Font = Enum.Font.GothamBold
    title.Parent = header

    local closeBtn = Instance.new("TextButton")
    closeBtn.Size = UDim2.new(0, 28, 0, 28)
    closeBtn.Position = UDim2.new(1, -34, 0, 4)
    closeBtn.BackgroundTransparency = 1
    closeBtn.Text = "✕"
    closeBtn.TextColor3 = Color3.fromRGB(200, 200, 200)
    closeBtn.TextSize = 16
    closeBtn.Font = Enum.Font.Gotham
    closeBtn.Parent = header

    local status = Instance.new("TextLabel")
    status.Size = UDim2.new(1, -20, 0, 18)
    status.Position = UDim2.new(0, 10, 0, 44)
    status.BackgroundTransparency = 1
    status.Text = "DISABLED"
    status.TextColor3 = Color3.fromRGB(200, 220, 240)
    status.TextSize = 10
    status.TextXAlignment = Enum.TextXAlignment.Left
    status.Font = Enum.Font.Gotham
    status.Parent = main

    local targetLabel = Instance.new("TextLabel")
    targetLabel.Size = UDim2.new(1, -20, 0, 18)
    targetLabel.Position = UDim2.new(0, 10, 0, 62)
    targetLabel.BackgroundTransparency = 1
    targetLabel.Text = "TARGET: NONE"
    targetLabel.TextColor3 = Color3.fromRGB(200, 220, 240)
    targetLabel.TextSize = 10
    targetLabel.TextXAlignment = Enum.TextXAlignment.Left
    targetLabel.Font = Enum.Font.Gotham
    targetLabel.Parent = main

    local killsLabel = Instance.new("TextLabel")
    killsLabel.Size = UDim2.new(1, -20, 0, 18)
    killsLabel.Position = UDim2.new(0, 10, 0, 80)
    killsLabel.BackgroundTransparency = 1
    killsLabel.Text = "KILLS: 0"
    killsLabel.TextColor3 = Color3.fromRGB(240, 220, 160)
    killsLabel.TextSize = 10
    killsLabel.TextXAlignment = Enum.TextXAlignment.Left
    killsLabel.Font = Enum.Font.Gotham
    killsLabel.Parent = main

    local divider = Instance.new("Frame")
    divider.Size = UDim2.new(1, -20, 0, 1)
    divider.Position = UDim2.new(0, 10, 0, 104)
    divider.BackgroundColor3 = Color3.fromRGB(80, 140, 255)
    divider.BackgroundTransparency = 0.4
    divider.BorderSizePixel = 0
    divider.Parent = main

    -- Иконки: Power, Crosshair, Eye, Settings
    local iconSize = 48
    local spacing = 12
    local startX = (260 - iconSize * 4 - spacing * 3) / 2

    local function createIconButton(icon, col, row)
        local btn = Instance.new("TextButton")
        btn.Size = UDim2.new(0, iconSize, 0, iconSize)
        btn.Position = UDim2.new(0, startX + (iconSize + spacing) * col, 0, 116 + (iconSize + spacing) * row)
        btn.BackgroundColor3 = Color3.fromRGB(16, 24, 50)
        btn.BackgroundTransparency = 0.3
        btn.BorderSizePixel = 0
        btn.Text = icon
        btn.TextColor3 = Color3.fromRGB(220, 230, 255)
        btn.TextSize = 20
        btn.Font = Enum.Font.Gotham
        btn.Parent = main

        local corner = Instance.new("UICorner")
        corner.CornerRadius = UDim.new(0, 10)
        corner.Parent = btn

        local stroke = Instance.new("UIStroke")
        stroke.Color = Color3.fromRGB(60, 150, 255)
        stroke.Thickness = 1.2
        stroke.Transparency = 0.8
        stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
        stroke.Parent = btn

        -- Нажатие (без hover, т.к. телефон)
        local pressTween = TweenService:Create(btn, TweenInfo.new(0.08, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
            Size = UDim2.new(0, iconSize - 4, 0, iconSize - 4),
        })
        local releaseTween = TweenService:Create(btn, TweenInfo.new(0.08, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
            Size = UDim2.new(0, iconSize, 0, iconSize),
        })
        btn.MouseButton1Down:Connect(function()
            releaseTween:Cancel()
            pressTween:Play()
        end)
        btn.MouseButton1Up:Connect(function()
            pressTween:Cancel()
            releaseTween:Play()
        end)

        -- Активное свечение (управляется извне)
        local glow = Instance.new("UIStroke")
        glow.Color = Color3.fromRGB(60, 150, 255)
        glow.Thickness = 2
        glow.Transparency = 0.8
        glow.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
        glow.Parent = btn
        glow.Visible = false

        return btn, glow
    end

    local btnPower, glowPower = createIconButton("⏻", 0, 0)
    local btnCrosshair, glowCrosshair = createIconButton("⌖", 1, 0)
    local btnEye, glowEye = createIconButton("👁", 2, 0)
    local btnSettings, glowSettings = createIconButton("⚙", 3, 0)

    -- FOV и прицел
    local fovCircle = Instance.new("ImageLabel")
    fovCircle.Size = UDim2.new(0, CONFIG.FOV * 2, 0, CONFIG.FOV * 2)
    fovCircle.Position = UDim2.new(0.5, -CONFIG.FOV, 0.5, -CONFIG.FOV)
    fovCircle.BackgroundTransparency = 1
    fovCircle.Image = "rbxassetid://4911621264"
    fovCircle.ImageColor3 = Color3.fromRGB(255, 255, 255)
    fovCircle.ImageTransparency = 0.6
    fovCircle.Visible = false
    fovCircle.Parent = gui

    local crosshair = Instance.new("Frame")
    crosshair.Size = UDim2.new(0, 0, 0, 0)
    crosshair.BackgroundTransparency = 1
    crosshair.Visible = false
    crosshair.Parent = gui

    local function updateCrosshairPosition()
        local center = getCenter()
        crosshair.Position = UDim2.fromOffset(center.X, center.Y)
    end

    local function createDot()
        for _, c in pairs(crosshair:GetChildren()) do c:Destroy() end
        local dot = Instance.new("Frame")
        dot.Size = UDim2.new(0, 3, 0, 3)
        dot.Position = UDim2.new(0.5, -1.5, 0.5, -1.5)
        dot.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
        dot.BorderSizePixel = 0
        dot.Parent = crosshair
        local corner = Instance.new("UICorner")
        corner.CornerRadius = UDim.new(1, 0)
        corner.Parent = dot
    end

    local function createCross()
        for _, c in pairs(crosshair:GetChildren()) do c:Destroy() end
        local size, thick = 12, 1.5
        local parts = {
            {x = -size/2, y = -thick/2, w = size, h = thick},
            {x = -thick/2, y = -size/2, w = thick, h = size},
        }
        for _, data in ipairs(parts) do
            local part = Instance.new("Frame")
            part.Size = UDim2.new(0, data.w, 0, data.h)
            part.Position = UDim2.new(0.5, data.x, 0.5, data.y)
            part.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
            part.BorderSizePixel = 0
            part.Parent = crosshair
        end
    end

    if CONFIG.CrosshairStyle == "DOT" then createDot() else createCross() end
    updateCrosshairPosition()

    -- X-Ray контейнер – теперь это Frame (не Folder)
    local xrayHolder = Instance.new("Frame")
    xrayHolder.Size = UDim2.new(1, 0, 1, 0)
    xrayHolder.BackgroundTransparency = 1
    xrayHolder.Parent = gui
    XRayState.container = xrayHolder

    return {
        gui = gui,
        main = main,
        closeBtn = closeBtn,
        status = status,
        targetLabel = targetLabel,
        killsLabel = killsLabel,
        btnPower = btnPower,
        btnCrosshair = btnCrosshair,
        btnEye = btnEye,
        btnSettings = btnSettings,
        glowPower = glowPower,
        glowCrosshair = glowCrosshair,
        glowEye = glowEye,
        glowSettings = glowSettings,
        fovCircle = fovCircle,
        crosshair = crosshair,
        updateCrosshair = updateCrosshairPosition,
        xrayHolder = xrayHolder,
    }
end

-- ============================================================
--  ЗАПУСК (ЗАГРУЗКА → GUI)
-- ============================================================
local loading = createLoadingScreen()

-- Анимация загрузки
task.spawn(function()
    local ringTween = TweenService:Create(loading.ring, TweenInfo.new(1.2, Enum.EasingStyle.Linear, Enum.EasingDirection.Out, -1, false), {
        Rotation = 360,
    })
    ringTween:Play()

    local messages = {"Initializing...", "Loading Modules...", "Loading Interface...", "Loading Visuals...", "Finalizing..."}
    local progress = 0
    local step = 100 / #messages
    for i, msg in ipairs(messages) do
        loading.statusText.Text = msg
        progress = progress + step
        local tween = TweenService:Create(loading.fill, TweenInfo.new(0.5, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
            Size = UDim2.new(progress / 100, 0, 1, 0),
        })
        tween:Play()
        tween.Completed:Wait()
        task.wait(0.1)
    end
    if loading.fill.Size.X.Scale < 1 then
        local tween = TweenService:Create(loading.fill, TweenInfo.new(0.2, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
            Size = UDim2.new(1, 0, 1, 0),
        })
        tween:Play()
        tween.Completed:Wait()
    end
    task.wait(0.2)

    -- Создаём GUI (пока скрыт)
    local GUI = buildMainGUI()
    _G.NOVA_GUI = GUI

    -- Закрываем загрузку (без твина ScreenGui)
    for _, child in ipairs(loading.screen:GetChildren()) do
        if child:IsA("Frame") or child:IsA("TextLabel") or child:IsA("ImageLabel") then
            local t = TweenService:Create(child, TweenInfo.new(0.3, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
                BackgroundTransparency = 1,
                TextTransparency = 1,
                ImageTransparency = 1,
            })
            t:Play()
        end
    end
    task.wait(0.35)
    loading.screen:Destroy()

    -- Показываем GUI
    GUI.gui.Enabled = true

    -- ============================================================
    --  ВСЯ ЛОГИКА AIM LOCK (СКОПИРОВАНА ИЗ РАБОЧЕЙ ВЕРСИИ)
    -- ============================================================
    local raycastParams = RaycastParams.new()
    raycastParams.FilterType = Enum.RaycastFilterType.Blacklist

    local function updateRaycastFilter(char)
        if char then
            raycastParams.FilterDescendantsInstances = {char}
        end
    end
    updateRaycastFilter(Player.Character)
    Player.CharacterAdded:Connect(updateRaycastFilter)

    local function isAlive(plr)
        if not plr or not plr.Parent then return false end
        if not plr.Character or not plr.Character.Parent then return false end
        local humanoid = plr.Character:FindFirstChild("Humanoid")
        return humanoid and humanoid.Health > 0
    end

    local function getAimPart(plr)
        if not plr or not plr.Character or not plr.Character.Parent then return nil end
        local char = plr.Character
        local part = char:FindFirstChild(CONFIG.AimPart)
        if part then return part end
        part = char:FindFirstChild(CONFIG.BackupPart)
        if part then return part end
        return char:FindFirstChild("HumanoidRootPart") or char:FindFirstChild("Torso")
    end

    local function getScreenPos(part)
        if not part or not part.Parent then return nil end
        local pos, onScreen = Camera:WorldToViewportPoint(part.Position)
        if not onScreen then return nil end
        return Vector2.new(pos.X, pos.Y)
    end

    local function getVelocity(plr)
        if not plr or not plr.Character or not plr.Character.Parent then return Vector3.new(0, 0, 0) end
        local root = plr.Character:FindFirstChild("HumanoidRootPart")
        if root then return root.AssemblyLinearVelocity end
        return Vector3.new(0, 0, 0)
    end

    local function isVisible(plr)
        if not plr or not plr.Character or not plr.Character.Parent then return false end
        if not Camera then return false end
        
        local part = getAimPart(plr)
        if not part or not part.Parent then return false end
        
        local origin = Camera.CFrame.Position
        local targetPos = part.Position
        local direction = (targetPos - origin).Unit
        local distance = (targetPos - origin).Magnitude
        
        if distance > CONFIG.DistanceLimit then return false end
        
        local result = workspace:Raycast(origin, direction * distance, raycastParams)
        if not result then return true end
        
        local hit = result.Instance
        local parent = hit.Parent
        while parent do
            if parent == plr.Character then return true end
            parent = parent.Parent
        end
        
        return false
    end

    -- ============================================================
    --  X-RAY
    -- ============================================================
    local XRAY_PARTS = {"Head", "HumanoidRootPart", "UpperTorso", "LowerTorso", "LeftFoot", "RightFoot", "LeftHand", "RightHand"}

    local function getCharacterParts(plr)
        if not plr or not plr.Character or not plr.Character.Parent then return {} end
        
        local cached = XRayState.partsCache[plr]
        if cached and XRayState.cacheTimers[plr] and os.clock() - XRayState.cacheTimers[plr] < XRayState.CACHE_DURATION then
            return cached
        end
        
        local char = plr.Character
        local parts = {}
        for _, name in ipairs(XRAY_PARTS) do
            local part = char:FindFirstChild(name)
            if part and part.Parent then
                table.insert(parts, part)
            end
        end
        if #parts < 3 then
            for _, child in ipairs(char:GetDescendants()) do
                if child:IsA("BasePart") and child.Parent then
                    table.insert(parts, child)
                end
            end
        end
        
        XRayState.partsCache[plr] = parts
        XRayState.cacheTimers[plr] = os.clock()
        return parts
    end

    local function clearPartsCache(plr)
        if plr then
            XRayState.partsCache[plr] = nil
            XRayState.cacheTimers[plr] = nil
        else
            XRayState.partsCache = {}
            XRayState.cacheTimers = {}
        end
    end

    local function removeBox(plr)
        local data = XRayState.boxes[plr]
        if data then
            if data.container and data.container.Parent then
                data.container:Destroy()
            end
            XRayState.boxes[plr] = nil
        end
    end

    local function clearAllBoxes()
        for plr in pairs(XRayState.boxes) do
            removeBox(plr)
        end
        XRayState.boxes = {}
    end

    local function createBox(plr)
        if XRayState.boxes[plr] then return end
        if not XRayState.container or not XRayState.container.Parent then return end
        
        local container = Instance.new("Frame")
        container.Size = UDim2.new(0, 40, 0, 60)
        container.BackgroundTransparency = 1
        container.Parent = XRayState.container
        
        local border = Instance.new("Frame")
        border.Size = UDim2.new(1, 0, 1, 0)
        border.BackgroundTransparency = 0.7
        border.BackgroundColor3 = Color3.fromHSV(0, 1, 1)
        border.BorderSizePixel = 0
        border.Parent = container
        local corner = Instance.new("UICorner")
        corner.CornerRadius = UDim.new(0, 4)
        corner.Parent = border
        
        local outline = Instance.new("Frame")
        outline.Size = UDim2.new(1, 0, 1, 0)
        outline.Position = UDim2.new(0, 1, 0, 1)
        outline.Size = UDim2.new(1, -2, 1, -2)
        outline.BackgroundTransparency = 1
        outline.BorderSizePixel = 2
        outline.BorderColor3 = Color3.fromHSV(0, 1, 1)
        outline.BackgroundColor3 = Color3.fromRGB(0, 0, 0)
        outline.BackgroundTransparency = 0.7
        outline.Parent = container
        local outlineCorner = Instance.new("UICorner")
        outlineCorner.CornerRadius = UDim.new(0, 3)
        outlineCorner.Parent = outline
        
        local nameLabel = Instance.new("TextLabel")
        nameLabel.Size = UDim2.new(1, 0, 0, 16)
        nameLabel.Position = UDim2.new(0, 0, 1, 0)
        nameLabel.BackgroundTransparency = 1
        nameLabel.Text = plr.Name
        nameLabel.TextColor3 = Color3.fromHSV(0, 1, 1)
        nameLabel.TextSize = 11
        nameLabel.Font = Enum.Font.GothamBold
        nameLabel.TextStrokeTransparency = 0.2
        nameLabel.TextStrokeColor3 = Color3.fromRGB(0, 0, 0)
        nameLabel.Parent = container
        
        XRayState.boxes[plr] = {
            container = container,
            border = border,
            outline = outline,
            name = nameLabel,
        }
    end

    local function updateBox(plr, hue)
        local data = XRayState.boxes[plr]
        if not data then return end
        if not data.container or not data.container.Parent then
            XRayState.boxes[plr] = nil
            return
        end
        if not plr or not plr.Character or not plr.Character.Parent then
            removeBox(plr)
            return
        end
        if not Camera then return end
        
        local color = Color3.fromHSV(hue, 1, 1)
        
        if data.border then data.border.BackgroundColor3 = color end
        if data.outline then data.outline.BorderColor3 = color end
        if data.name then data.name.TextColor3 = color end
        
        local parts = getCharacterParts(plr)
        if #parts == 0 then
            data.container.Visible = false
            return
        end
        
        local minX, maxX, minY, maxY = nil, nil, nil, nil
        
        for _, part in ipairs(parts) do
            if not part or not part.Parent then continue end
            local pos, onScreen = Camera:WorldToViewportPoint(part.Position)
            if onScreen then
                if minX == nil then
                    minX, maxX = pos.X, pos.X
                    minY, maxY = pos.Y, pos.Y
                else
                    if pos.X < minX then minX = pos.X end
                    if pos.X > maxX then maxX = pos.X end
                    if pos.Y < minY then minY = pos.Y end
                    if pos.Y > maxY then maxY = pos.Y end
                end
            end
        end
        
        if minX == nil then
            data.container.Visible = false
            return
        end
        
        local padding = 4
        local width = maxX - minX + padding * 2
        local height = maxY - minY + padding * 2
        
        width = math.max(width, 20)
        height = math.max(height, 30)
        
        data.container.Position = UDim2.new(0, minX - padding, 0, minY - padding)
        data.container.Size = UDim2.new(0, width, 0, height)
        data.container.Visible = true
    end

    local function updateXRay(dt)
        if State.destroyed then return end
        
        if not XRayState.enabled then
            clearAllBoxes()
            return
        end
        
        State.hue = (State.hue + dt * 0.2) % 1
        
        State.xrayTimer = State.xrayTimer + dt
        local shouldUpdatePos = State.xrayTimer >= CONFIG.XRayUpdateInterval
        if shouldUpdatePos then
            State.xrayTimer = 0
        end
        
        for plr, data in pairs(XRayState.boxes) do
            if data and data.container and data.container.Parent then
                local color = Color3.fromHSV(State.hue, 1, 1)
                if data.border then data.border.BackgroundColor3 = color end
                if data.outline then data.outline.BorderColor3 = color end
                if data.name then data.name.TextColor3 = color end
            end
        end
        
        if not shouldUpdatePos then
            return
        end
        
        for plr in pairs(XRayState.boxes) do
            if not plr or not plr.Parent or not isAlive(plr) then
                removeBox(plr)
            end
        end
        
        for _, plr in pairs(Players:GetPlayers()) do
            if plr ~= Player and plr.Parent and isAlive(plr) then
                createBox(plr)
                updateBox(plr, State.hue)
            end
        end
    end

    -- ============================================================
    --  ЛОГИКА АИМА
    -- ============================================================
    local function updateTargetCF(plr)
        if not plr or not isAlive(plr) then return end
        if not Camera then return end
        
        local part = getAimPart(plr)
        if not part or not part.Parent then return end
        
        local pos = part.Position
        local vel = getVelocity(plr)
        local distance = (pos - Camera.CFrame.Position).Magnitude
        
        local targetPos = pos
        if vel.Magnitude >= 0.1 then
            local flyTime = distance / CONFIG.BulletSpeed
            local predTime = flyTime * CONFIG.PredictionStrength
            targetPos = pos + vel * predTime
        end
        
        State.targetCF = CFrame.lookAt(Camera.CFrame.Position, targetPos)
    end

    local function findBestTarget()
        if not Camera or not Player.Character or not Player.Character.Parent then return nil end
        
        local center = getCenter()
        local best = nil
        local bestDist = math.huge
        local fovSq = CONFIG.FOV ^ 2
        local camPos = Camera.CFrame.Position
        
        local candidates = {}
        for _, plr in pairs(Players:GetPlayers()) do
            if plr ~= Player and plr.Parent and isAlive(plr) then
                local part = getAimPart(plr)
                if part and part.Parent then
                    local screenPos = getScreenPos(part)
                    if screenPos then
                        local dx = screenPos.X - center.X
                        local dy = screenPos.Y - center.Y
                        local dist = dx*dx + dy*dy
                        
                        if dist < fovSq then
                            local offset = part.Position - camPos
                            local worldDistSq = offset:Dot(offset)
                            if worldDistSq <= DIST_LIMIT_SQ then
                                table.insert(candidates, {
                                    player = plr,
                                    part = part,
                                    screenPos = screenPos,
                                    dist = dist,
                                })
                            end
                        end
                    end
                end
            end
        end
        
        for _, cand in ipairs(candidates) do
            if isVisible(cand.player) then
                if cand.dist < bestDist then
                    best = cand.player
                    bestDist = cand.dist
                end
            end
        end
        
        return best
    end

    local function isTargetInFOV(plr)
        if not plr or not plr.Character or not plr.Character.Parent then return false end
        if not Camera then return false end
        
        local part = getAimPart(plr)
        if not part or not part.Parent then return false end
        
        local screenPos = getScreenPos(part)
        if not screenPos then return false end
        
        local center = getCenter()
        local dx = screenPos.X - center.X
        local dy = screenPos.Y - center.Y
        local dist = dx*dx + dy*dy
        
        return dist < CONFIG.FOV ^ 2
    end

    local function processAim(dt)
        if State.destroyed then return end
        if not Camera then return end
        
        updateXRay(dt)
        
        if not State.enabled then
            return
        end
        
        State.searchTimer = State.searchTimer + dt
        
        if State.target and State.target.Parent and isAlive(State.target) then
            local part = getAimPart(State.target)
            local visible = part and part.Parent and isVisible(State.target)
            local inFOV = isTargetInFOV(State.target)
            
            if part and visible and inFOV then
                State.lostTimer = 0
                updateTargetCF(State.target)
                
                if State.targetCF then
                    if State.smoothCF then
                        State.smoothCF = State.smoothCF:Lerp(State.targetCF, CONFIG.Smoothness)
                    else
                        State.smoothCF = State.targetCF
                    end
                    
                    if Camera and State.smoothCF then
                        Camera.CFrame = State.smoothCF
                    end
                end
                
                if GUI.status and GUI.status.Parent then
                    GUI.status.Text = "LOCKED: " .. State.target.Name
                    GUI.status.TextColor3 = Color3.fromRGB(100, 255, 200)
                end
                if GUI.targetLabel and GUI.targetLabel.Parent then
                    GUI.targetLabel.Text = "TARGET: " .. State.target.Name
                    GUI.targetLabel.TextColor3 = Color3.fromRGB(100, 255, 200)
                end
                return
            end
            
            State.lostTimer = State.lostTimer + dt
            if State.lostTimer > CONFIG.LostTimeout then
                State.target = nil
                State.targetCF = nil
                State.smoothCF = nil
            end
        end
        
        if State.searchTimer < CONFIG.SearchInterval then
            return
        end
        State.searchTimer = 0
        
        local newTarget = findBestTarget()
        
        if newTarget then
            State.target = newTarget
            State.lostTimer = 0
            State.smoothCF = nil
            State.targetCF = nil
            
            updateTargetCF(newTarget)
            if State.targetCF then
                State.smoothCF = State.targetCF
                if Camera then
                    Camera.CFrame = State.smoothCF
                end
            end
            
            if GUI.status and GUI.status.Parent then
                GUI.status.Text = "LOCKED: " .. newTarget.Name
                GUI.status.TextColor3 = Color3.fromRGB(100, 255, 200)
            end
            if GUI.targetLabel and GUI.targetLabel.Parent then
                GUI.targetLabel.Text = "TARGET: " .. newTarget.Name
                GUI.targetLabel.TextColor3 = Color3.fromRGB(100, 255, 200)
            end
        else
            if State.target then
                State.target = nil
                State.targetCF = nil
                State.smoothCF = nil
            end
            
            if GUI.status and GUI.status.Parent then
                GUI.status.Text = "NO TARGET"
                GUI.status.TextColor3 = Color3.fromRGB(255, 200, 100)
            end
            if GUI.targetLabel and GUI.targetLabel.Parent then
                GUI.targetLabel.Text = "SEARCHING..."
                GUI.targetLabel.TextColor3 = Color3.fromRGB(255, 200, 100)
            end
        end
    end

    -- ============================================================
    --  УПРАВЛЕНИЕ (ПРИВЯЗКА К ИКОНКАМ)
    -- ============================================================
    local function toggleAim()
        if State.destroyed then return end
        
        State.enabled = not State.enabled
        
        if State.enabled then
            local target = findBestTarget()
            
            if target then
                State.target = target
                State.lostTimer = 0
                State.targetCF = nil
                State.smoothCF = nil
                State.searchTimer = 0
                State.xrayTimer = 0
                
                updateTargetCF(target)
                if State.targetCF and Camera then
                    State.smoothCF = State.targetCF
                    Camera.CFrame = State.smoothCF
                end
                
                if GUI.status and GUI.status.Parent then
                    GUI.status.Text = "LOCKED: " .. target.Name
                    GUI.status.TextColor3 = Color3.fromRGB(100, 255, 200)
                end
                if GUI.targetLabel and GUI.targetLabel.Parent then
                    GUI.targetLabel.Text = "TARGET: " .. target.Name
                    GUI.targetLabel.TextColor3 = Color3.fromRGB(100, 255, 200)
                end
            else
                State.target = nil
                if GUI.status and GUI.status.Parent then
                    GUI.status.Text = "NO TARGET"
                    GUI.status.TextColor3 = Color3.fromRGB(255, 200, 100)
                end
                if GUI.targetLabel and GUI.targetLabel.Parent then
                    GUI.targetLabel.Text = "SEARCHING..."
                    GUI.targetLabel.TextColor3 = Color3.fromRGB(255, 200, 100)
                end
            end
            
            if GUI.glowPower then
                GUI.glowPower.Visible = true
                GUI.glowPower.Color = Color3.fromRGB(0, 255, 100)
                GUI.glowPower.Transparency = 0.2
            end
            
            if GUI.fovCircle and GUI.fovCircle.Parent then
                GUI.fovCircle.Visible = CONFIG.ShowFOV
            end
            if GUI.crosshair and GUI.crosshair.Parent then
                GUI.crosshair.Visible = true
            end
            
            if not XRayState.container or not XRayState.container.Parent then
                -- контейнер уже создан в GUI
            end
        else
            State.target = nil
            State.targetCF = nil
            State.smoothCF = nil
            State.lostTimer = 0
            State.searchTimer = 0
            State.xrayTimer = 0
            State.killCount = 0
            
            if GUI.status and GUI.status.Parent then
                GUI.status.Text = "DISABLED"
                GUI.status.TextColor3 = Color3.fromRGB(200, 220, 240)
            end
            if GUI.targetLabel and GUI.targetLabel.Parent then
                GUI.targetLabel.Text = "TARGET: NONE"
                GUI.targetLabel.TextColor3 = Color3.fromRGB(200, 220, 240)
            end
            if GUI.killsLabel and GUI.killsLabel.Parent then
                GUI.killsLabel.Text = "KILLS: 0"
            end
            
            if GUI.glowPower then
                GUI.glowPower.Visible = false
            end
            
            if GUI.fovCircle and GUI.fovCircle.Parent then
                GUI.fovCircle.Visible = false
            end
            if GUI.crosshair and GUI.crosshair.Parent then
                GUI.crosshair.Visible = false
            end
            
            clearAllBoxes()
            clearPartsCache()
            if XRayState.container and XRayState.container.Parent then
                -- не уничтожаем контейнер, чистим боксы
            end
        end
    end

    local function switchAimPart()
        if CONFIG.AimPart == "Head" then
            CONFIG.AimPart = "HumanoidRootPart"
            CONFIG.BackupPart = "Torso"
            if GUI.status and GUI.status.Parent then
                GUI.status.Text = "AIM: BODY"
            end
        else
            CONFIG.AimPart = "Head"
            CONFIG.BackupPart = "UpperTorso"
            if GUI.status and GUI.status.Parent then
                GUI.status.Text = "AIM: HEAD"
            end
        end
    end

    local function toggleXRay()
        XRayState.enabled = not XRayState.enabled
        if GUI.glowEye then
            GUI.glowEye.Visible = XRayState.enabled
            GUI.glowEye.Color = XRayState.enabled and Color3.fromRGB(60, 150, 255) or Color3.fromRGB(255, 255, 255)
            GUI.glowEye.Transparency = XRayState.enabled and 0.2 or 0.8
        end
        if not XRayState.enabled then
            clearAllBoxes()
            clearPartsCache()
        end
    end

    -- ============================================================
    --  ПРИВЯЗКА КНОПОК
    -- ============================================================
    GUI.btnPower.MouseButton1Click:Connect(toggleAim)
    GUI.btnCrosshair.MouseButton1Click:Connect(switchAimPart)
    GUI.btnEye.MouseButton1Click:Connect(toggleXRay)
    GUI.btnSettings.MouseButton1Click:Connect(function()
        print("Settings clicked")
    end)

    GUI.closeBtn.MouseButton1Click:Connect(function()
        GUI.gui:Destroy()
        State.destroyed = true
        clearAllBoxes()
        clearPartsCache()
        if XRayState.container then
            XRayState.container:Destroy()
        end
    end)

    -- ============================================================
    --  ОБРАБОТЧИКИ ВЫХОДА ИГРОКА
    -- ============================================================
    Players.PlayerRemoving:Connect(function(plr)
        removeBox(plr)
        clearPartsCache(plr)
        if State.target == plr then
            State.target = nil
            State.targetCF = nil
            State.smoothCF = nil
        end
    end)

    for _, plr in pairs(Players:GetPlayers()) do
        if plr ~= Player then
            plr.CharacterAdded:Connect(function()
                clearPartsCache(plr)
            end)
            plr.CharacterRemoving:Connect(function()
                clearPartsCache(plr)
            end)
        end
    end

    -- ============================================================
    --  КЛАВИАТУРА
    -- ============================================================
    UserInputService.InputBegan:Connect(function(input, processed)
        if processed then return end
        if State.destroyed then return end
        
        if input.KeyCode == Enum.KeyCode.One then
            toggleAim()
        elseif input.KeyCode == Enum.KeyCode.Two then
            switchAimPart()
        elseif input.KeyCode == Enum.KeyCode.Three then
            toggleXRay()
        end
    end)

    -- ============================================================
    --  RENDERSTEP
    -- ============================================================
    RunService.RenderStepped:Connect(function(dt)
        if State.destroyed then return end
        pcall(processAim, dt)
    end)

    -- ============================================================
    --  УВЕДОМЛЕНИЕ
    -- ============================================================
    game:GetService("StarterGui"):SetCore("SendNotification", {
        Title = "NOVA v38",
        Text = "1 - Toggle | 2 - Head/Body | 3 - X-Ray",
        Duration = 3
    })

    print("✅ NOVA v38.0 LOADED")
    print("📌 1 - Toggle ON/OFF")
    print("📌 2 - Switch aim (HEAD ↔ BODY)")
    print("📌 3 - Toggle X-RAY (RGB)")
end)
