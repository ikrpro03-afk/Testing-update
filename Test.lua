-- NOVA v36.0 | ULTIMATE INTERFACE
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local TweenService = game:GetService("TweenService")
local Camera = workspace.CurrentCamera
local Player = Players.LocalPlayer

-- ============================================================
--  КОНФИГУРАЦИЯ
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
--  СОСТОЯНИЕ
-- ============================================================
local State = {
    enabled = false,
    destroyed = false,
    cleaned = false,
    target = nil,
    targetCF = nil,
    smoothCF = nil,
    killCount = 0,
    lostTimer = 0,
    minimized = false,
    maximized = false,
    searchTimer = 0,
    xrayTimer = 0,
    hue = 0,
    lastStatus = "",
    lastTarget = "",
}

-- ============================================================
--  X-RAY СОСТОЯНИЕ
-- ============================================================
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
    return Vector2.new(
        vp.X / 2 + CONFIG.CenterOffset.X,
        vp.Y / 2 + CONFIG.CenterOffset.Y
    )
end

-- ============================================================
--  ЗАГРУЗОЧНЫЙ ЭКРАН
-- ============================================================
local PlayerGui = Player:WaitForChild("PlayerGui")

local function createLoadingScreen()
    local screen = Instance.new("ScreenGui")
    screen.Name = "LoadingScreen"
    screen.Parent = PlayerGui
    screen.DisplayOrder = 1000

    -- Затемнение
    local overlay = Instance.new("Frame")
    overlay.Size = UDim2.new(1, 0, 1, 0)
    overlay.BackgroundColor3 = Color3.fromRGB(0, 0, 0)
    overlay.BackgroundTransparency = 0.8
    overlay.BorderSizePixel = 0
    overlay.Parent = screen

    -- Панель загрузки
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

    -- Логотип NOVA
    local logo = Instance.new("TextLabel")
    logo.Size = UDim2.new(0, 60, 0, 60)
    logo.Position = UDim2.new(0.5, -30, 0, 20)
    logo.BackgroundTransparency = 1
    logo.Text = "NOVA"
    logo.TextColor3 = Color3.fromRGB(100, 200, 255)
    logo.TextSize = 36
    logo.Font = Enum.Font.GothamBold
    logo.Parent = panel

    -- Вращающееся кольцо
    local ring = Instance.new("ImageLabel")
    ring.Size = UDim2.new(0, 70, 0, 70)
    ring.Position = UDim2.new(0.5, -35, 0, 15)
    ring.BackgroundTransparency = 1
    ring.Image = "rbxassetid://4911621264"
    ring.ImageColor3 = Color3.fromRGB(60, 150, 255)
    ring.ImageTransparency = 0.6
    ring.Parent = panel

    -- Текст загрузки
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
    versionText.Text = "v36.0"
    versionText.TextColor3 = Color3.fromRGB(150, 180, 220)
    versionText.TextSize = 11
    versionText.Font = Enum.Font.Gotham
    versionText.Parent = panel

    -- Полоска загрузки
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

local loading = createLoadingScreen()

-- ============================================================
--  АНИМАЦИЯ ЗАГРУЗКИ
-- ============================================================
local function animateLoading()
    -- Вращение кольца
    local ringTween = TweenService:Create(loading.ring, TweenInfo.new(3, Enum.EasingStyle.Linear, Enum.EasingDirection.Out, -1, true), {
        Rotation = 360,
    })
    ringTween:Play()

    local messages = {
        "Initializing...",
        "Loading Modules...",
        "Loading Interface...",
        "Loading Visuals...",
        "Finalizing...",
    }

    local progress = 0
    local step = 100 / #messages

    for i, msg in ipairs(messages) do
        loading.statusText.Text = msg
        progress = progress + step
        local tween = TweenService:Create(loading.fill, TweenInfo.new(0.8, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
            Size = UDim2.new(progress / 100, 0, 1, 0),
        })
        tween:Play()
        tween.Completed:Wait()
        task.wait(0.15)
    end

    -- Дождаться 100%
    if loading.fill.Size.X.Scale < 1 then
        local tween = TweenService:Create(loading.fill, TweenInfo.new(0.3, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
            Size = UDim2.new(1, 0, 1, 0),
        })
        tween:Play()
        tween.Completed:Wait()
    end

    task.wait(0.3)

    -- Fade Out
    local fadeOut = TweenService:Create(loading.screen, TweenInfo.new(0.5, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
        BackgroundTransparency = 1,
    })
    for _, child in ipairs(loading.screen:GetChildren()) do
        if child:IsA("Frame") or child:IsA("TextLabel") or child:IsA("ImageLabel") then
            local t = TweenService:Create(child, TweenInfo.new(0.5, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
                BackgroundTransparency = 1,
                TextTransparency = 1,
                ImageTransparency = 1,
            })
            t:Play()
        end
    end
    fadeOut:Play()
    fadeOut.Completed:Wait()
    loading.screen:Destroy()
end

-- ============================================================
--  ОСНОВНОЙ GUI (МИНИМАЛИСТИЧНЫЙ, С ИКОНКАМИ)
-- ============================================================
local function buildModernGUI()
    local gui = Instance.new("ScreenGui")
    gui.Name = "NOVA"
    gui.ResetOnSpawn = false
    gui.IgnoreGuiInset = true
    gui.Parent = PlayerGui
    gui.DisplayOrder = 999

    -- ОСНОВНАЯ ПАНЕЛЬ
    local main = Instance.new("Frame")
    main.Size = UDim2.new(0, 260, 0, 280)
    main.Position = UDim2.new(0, 20, 0, 20)
    main.BackgroundColor3 = Color3.fromRGB(8, 14, 34)
    main.BackgroundTransparency = 0.05
    main.BorderSizePixel = 0
    main.ClipsDescendants = true
    main.Parent = gui

    local mainCorner = Instance.new("UICorner")
    mainCorner.CornerRadius = UDim.new(0, 16)
    mainCorner.Parent = main

    local mainStroke = Instance.new("UIStroke")
    mainStroke.Color = Color3.fromRGB(60, 150, 255)
    mainStroke.Thickness = 1.2
    mainStroke.Transparency = 0.6
    mainStroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
    mainStroke.Parent = main

    -- ЗАГОЛОВОК
    local header = Instance.new("Frame")
    header.Size = UDim2.new(1, 0, 0, 36)
    header.BackgroundColor3 = Color3.fromRGB(12, 20, 48)
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
    title.TextColor3 = Color3.fromRGB(180, 220, 255)
    title.TextSize = 15
    title.TextXAlignment = Enum.TextXAlignment.Left
    title.Font = Enum.Font.GothamBold
    title.Parent = header

    -- Кнопка закрытия (иконка ✕)
    local closeBtn = Instance.new("TextButton")
    closeBtn.Size = UDim2.new(0, 28, 0, 28)
    closeBtn.Position = UDim2.new(1, -34, 0, 4)
    closeBtn.BackgroundTransparency = 1
    closeBtn.Text = "✕"
    closeBtn.TextColor3 = Color3.fromRGB(200, 200, 200)
    closeBtn.TextSize = 16
    closeBtn.Font = Enum.Font.Gotham
    closeBtn.Parent = header

    -- СТАТУСЫ
    local status = Instance.new("TextLabel")
    status.Size = UDim2.new(1, -20, 0, 18)
    status.Position = UDim2.new(0, 10, 0, 44)
    status.BackgroundTransparency = 1
    status.Text = "DISABLED"
    status.TextColor3 = Color3.fromRGB(180, 200, 220)
    status.TextSize = 10
    status.TextXAlignment = Enum.TextXAlignment.Left
    status.Font = Enum.Font.Gotham
    status.Parent = main

    local targetLabel = Instance.new("TextLabel")
    targetLabel.Size = UDim2.new(1, -20, 0, 18)
    targetLabel.Position = UDim2.new(0, 10, 0, 62)
    targetLabel.BackgroundTransparency = 1
    targetLabel.Text = "TARGET: NONE"
    targetLabel.TextColor3 = Color3.fromRGB(180, 200, 220)
    targetLabel.TextSize = 10
    targetLabel.TextXAlignment = Enum.TextXAlignment.Left
    targetLabel.Font = Enum.Font.Gotham
    targetLabel.Parent = main

    local killsLabel = Instance.new("TextLabel")
    killsLabel.Size = UDim2.new(1, -20, 0, 18)
    killsLabel.Position = UDim2.new(0, 10, 0, 80)
    killsLabel.BackgroundTransparency = 1
    killsLabel.Text = "KILLS: 0"
    killsLabel.TextColor3 = Color3.fromRGB(220, 200, 140)
    killsLabel.TextSize = 10
    killsLabel.TextXAlignment = Enum.TextXAlignment.Left
    killsLabel.Font = Enum.Font.Gotham
    killsLabel.Parent = main

    -- РАЗДЕЛИТЕЛЬ
    local divider = Instance.new("Frame")
    divider.Size = UDim2.new(1, -20, 0, 1)
    divider.Position = UDim2.new(0, 10, 0, 104)
    divider.BackgroundColor3 = Color3.fromRGB(60, 100, 180)
    divider.BackgroundTransparency = 0.5
    divider.BorderSizePixel = 0
    divider.Parent = main

    -- ПАНЕЛЬ ИКОНОК (4 кнопки)
    local iconSize = 48
    local spacing = 12
    local startX = (260 - iconSize * 4 - spacing * 3) / 2

    local function createIconButton(icon, y, callback, activeColor)
        local btn = Instance.new("TextButton")
        btn.Size = UDim2.new(0, iconSize, 0, iconSize)
        btn.Position = UDim2.new(0, startX + (iconSize + spacing) * (y % 4), 0, 116 + math.floor(y / 4) * (iconSize + spacing))
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
        stroke.Thickness = 1
        stroke.Transparency = 0.8
        stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
        stroke.Parent = btn

        -- Hover
        local hoverTween = TweenService:Create(btn, TweenInfo.new(0.15, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
            BackgroundTransparency = 0.1,
            TextColor3 = Color3.fromRGB(100, 200, 255),
        })
        local leaveTween = TweenService:Create(btn, TweenInfo.new(0.15, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
            BackgroundTransparency = 0.3,
            TextColor3 = Color3.fromRGB(220, 230, 255),
        })
        btn.MouseEnter:Connect(function() leaveTween:Cancel(); hoverTween:Play() end)
        btn.MouseLeave:Connect(function() hoverTween:Cancel(); leaveTween:Play() end)

        -- Анимация нажатия
        local pressTween = TweenService:Create(btn, TweenInfo.new(0.08, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
            Size = UDim2.new(0, iconSize - 4, 0, iconSize - 4),
        })
        local releaseTween = TweenService:Create(btn, TweenInfo.new(0.08, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
            Size = UDim2.new(0, iconSize, 0, iconSize),
        })
        btn.MouseButton1Down:Connect(function() releaseTween:Cancel(); pressTween:Play() end)
        btn.MouseButton1Up:Connect(function() pressTween:Cancel(); releaseTween:Play() end)

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

    -- Создаём иконки: Power, Crosshair, Eye, Settings
    local btnPower, glowPower = createIconButton("⏻", 0)
    local btnCrosshair, glowCrosshair = createIconButton("⌖", 1)
    local btnEye, glowEye = createIconButton("👁", 2)
    local btnSettings, glowSettings = createIconButton("⚙", 3)

    -- Кнопка закрытия (уже создана)

    -- FOV и Crosshair (старые визуалы)
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

    return {
        gui = gui,
        main = main,
        header = header,
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
    }
end

-- ============================================================
--  ЗАПУСК ЗАГРУЗКИ, ПОТОМ GUI
-- ============================================================
task.spawn(function()
    animateLoading()
    -- После загрузки создаём GUI
    local GUI = buildModernGUI()
    -- Сохраняем в глобальную переменную для доступа из функций
    _G.NOVA_GUI = GUI

    -- ============================================================
    --  ОБНОВЛЕНИЕ ПРИЦЕЛА ПРИ СМЕНЕ РАЗМЕРА
    -- ============================================================
    local function onScreenSizeChanged()
        if GUI and GUI.updateCrosshair then
            GUI.updateCrosshair()
        end
    end
    Camera:GetPropertyChangedSignal("ViewportSize"):Connect(onScreenSizeChanged)
    UserInputService.WindowFocused:Connect(onScreenSizeChanged)

    -- ============================================================
    --  RAYCAST
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

    -- ============================================================
    --  УТИЛИТЫ (скопированы из старой версии)
    -- ============================================================
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

    local function ge
