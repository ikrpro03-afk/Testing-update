-- NOVA v46.0 – СУПЕР-ОПТИМИЗИРОВАННАЯ (без аллокаций, Top-5, без sort)
-- Все улучшения применены: O(n) поиск, переиспользование таблиц, разделение потоков.

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local TweenService = game:GetService("TweenService")
local Camera = workspace.CurrentCamera
local Player = Players.LocalPlayer
local PlayerGui = Player:WaitForChild("PlayerGui")

-- ============================================================
-- КОНСТАНТЫ
-- ============================================================
local WINDOW_W, WINDOW_H = 260, 340
local HEADER_H = 40
local ICON_SIZE = 38
local ICON_SPACING = 6
local MAX_RAYCAST_CANDIDATES = 5  -- сколько ближайших целей проверяем на видимость
local GUI_UPDATE_INTERVAL = 0.15   -- обновление текста раз в 0.15 с
local XRAY_POSITION_INTERVAL = 0.025 -- обновление позиций боксов

-- ============================================================
-- НАСТРОЙКИ
-- ============================================================
local Settings = {
    AimPart = "Head",
    BackupPart = "UpperTorso",
    FOV = 50,
    Smoothness = 0.85,
    PredictionStrength = 0.6,
    BulletSpeed = 1800,
    LostTimeout = 0.1,
    SearchInterval = 0.05,
    DistanceLimit = 250,
    ShowFOV = true,
    CrosshairStyle = "DOT",
    CenterOffset = Vector2.new(0, 0),
    RandomAim = false,
}

-- ============================================================
-- СОСТОЯНИЕ
-- ============================================================
local AimState = {
    enabled = false,
    target = nil,
    targetCF = nil,
    smoothCF = nil,
    killCount = 0,
    lostTimer = 0,
    searchTimer = 0,
    randomAimPart = nil, -- выбранная часть для RandomAim
}
local VisualState = {
    xrayEnabled = true,
    xrayTimer = 0,
    hue = 0,
    partsCache = {},
    boxes = {},
    boxPool = {},
    poolSize = 0,
    xrayContainer = nil,
}
local GUIState = {
    destroyed = false,
    minimized = false,
    maximized = false,
    friendlyOpen = false,
    lastStatus = "",
    lastTarget = "",
    guiUpdateTimer = 0,
}

-- ============================================================
-- ЛОКАЛЬНЫЙ СПИСОК ИГРОКОВ (обновляется событиями)
-- ============================================================
local localPlayers = {}
local function updatePlayersList()
    localPlayers = {}
    for _, plr in ipairs(Players:GetPlayers()) do
        if plr ~= Player then
            table.insert(localPlayers, plr)
        end
    end
end
Players.PlayerAdded:Connect(function(plr)
    if plr ~= Player then
        table.insert(localPlayers, plr)
        -- подписываемся на CharacterAdded для очистки кэша
        plr.CharacterAdded:Connect(function()
            VisualState.partsCache[plr] = nil
        end)
    end
end)
Players.PlayerRemoving:Connect(function(plr)
    for i, p in ipairs(localPlayers) do
        if p == plr then
            table.remove(localPlayers, i)
            break
        end
    end
    VisualState.partsCache[plr] = nil
    releaseBox(plr)
end)
-- подписываемся на существующих игроков
for _, plr in pairs(Players:GetPlayers()) do
    if plr ~= Player then
        plr.CharacterAdded:Connect(function()
            VisualState.partsCache[plr] = nil
        end)
    end
end
updatePlayersList()

-- ============================================================
-- УТИЛИТЫ (оптимизированные)
-- ============================================================
local Utils = {}

function Utils.isValidPlayer(plr)
    if not plr or not plr.Parent then return false end
    local char = plr.Character
    if not char or not char.Parent then return false end
    local hum = char:FindFirstChild("Humanoid")
    return hum and hum.Health > 0
end

-- Кэш частей с полем _list
function Utils.getCachedParts(plr)
    if not plr then return nil end
    local cached = VisualState.partsCache[plr]
    if cached and cached._valid and cached._char == plr.Character then
        return cached
    end
    local char = plr.Character
    if not char or not char.Parent then return nil end
    local parts = {}
    parts._char = char
    parts._valid = true

    local names = {"Head","HumanoidRootPart","UpperTorso","Torso","LowerTorso","LeftFoot","RightFoot","LeftHand","RightHand"}
    for _, name in ipairs(names) do
        local p = char:FindFirstChild(name)
        if p then parts[name] = p end
    end

    -- Список частей для X-Ray (только нужные для бокса)
    local xrayNames = {"Head","HumanoidRootPart","LeftFoot","RightFoot"}
    local list = {}
    for _, name in ipairs(xrayNames) do
        local p = parts[name]
        if p and p.Parent then table.insert(list, p) end
    end
    parts._list = list

    VisualState.partsCache[plr] = parts
    return parts
end

function Utils.getAimPart(plr)
    local parts = Utils.getCachedParts(plr)
    if not parts then return nil end
    local partName
    if Settings.RandomAim and AimState.randomAimPart then
        partName = AimState.randomAimPart
    else
        partName = Settings.AimPart
    end
    local part = parts[partName]
    if part and part.Parent then return part end
    local backup = parts[Settings.BackupPart] or parts.HumanoidRootPart or parts.Torso
    if backup and backup.Parent then return backup end
    return nil
end

function Utils.getScreenPos(part)
    if not part or not part.Parent then return nil end
    local pos, onScreen = Camera:WorldToViewportPoint(part.Position)
    if not onScreen then return nil end
    return Vector2.new(pos.X, pos.Y)
end

function Utils.getVelocity(plr)
    local parts = Utils.getCachedParts(plr)
    if not parts then return Vector3.new(0,0,0) end
    local root = parts.HumanoidRootPart
    return root and root.AssemblyLinearVelocity or Vector3.new(0,0,0)
end

function Utils.getCenter()
    local vp = Camera.ViewportSize
    return Vector2.new(vp.X/2 + Settings.CenterOffset.X, vp.Y/2 + Settings.CenterOffset.Y)
end

-- Оптимизированная видимость без Unit
function Utils.isVisible(plr, raycastParams, distLimit)
    if not Utils.isValidPlayer(plr) then return false end
    local part = Utils.getAimPart(plr)
    if not part or not part.Parent then return false end
    local origin = Camera.CFrame.Position
    local offset = part.Position - origin
    local distance = offset.Magnitude
    if distance > distLimit then return false end
    local result = workspace:Raycast(origin, offset, raycastParams) -- offset вместо direction*Unit
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
-- FRIENDLY (по UserId)
-- ============================================================
local Friendly = { dict = {} }

function Friendly.isFriendly(plr)
    return plr and Friendly.dict[plr.UserId] == true or false
end
function Friendly.add(plr) if plr then Friendly.dict[plr.UserId] = true end end
function Friendly.remove(plr) if plr then Friendly.dict[plr.UserId] = nil end end
function Friendly.toggle(plr)
    if Friendly.isFriendly(plr) then Friendly.remove(plr); return false
    else Friendly.add(plr); return true end
end
function Friendly.clear() Friendly.dict = {} end

-- ============================================================
-- ЗАГРУЗОЧНЫЙ ЭКРАН (упрощённый)
-- ============================================================
local function createLoadingScreen()
    -- ... (без изменений, оставляем как в предыдущей версии)
    local screen = Instance.new("ScreenGui")
    screen.Name = "LoadingScreen"
    screen.Parent = PlayerGui
    screen.DisplayOrder = 1000
    local overlay = Instance.new("Frame")
    overlay.Size = UDim2.new(1,0,1,0)
    overlay.BackgroundColor3 = Color3.fromRGB(0,0,0)
    overlay.BackgroundTransparency = 0.8
    overlay.BorderSizePixel = 0
    overlay.Parent = screen
    local panel = Instance.new("Frame")
    panel.Size = UDim2.new(0,360,0,200)
    panel.Position = UDim2.new(0.5,-180,0.5,-100)
    panel.BackgroundColor3 = Color3.fromRGB(12,18,40)
    panel.BackgroundTransparency = 0.05
    panel.BorderSizePixel = 0
    panel.ClipsDescendants = true
    panel.Parent = screen
    local panelCorner = Instance.new("UICorner")
    panelCorner.CornerRadius = UDim.new(0,20)
    panelCorner.Parent = panel
    local panelStroke = Instance.new("UIStroke")
    panelStroke.Color = Color3.fromRGB(60,150,255)
    panelStroke.Thickness = 1.5
    panelStroke.Transparency = 0.5
    panelStroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
    panelStroke.Parent = panel
    local logo = Instance.new("TextLabel")
    logo.Size = UDim2.new(0,60,0,60)
    logo.Position = UDim2.new(0.5,-30,0,20)
    logo.BackgroundTransparency = 1
    logo.Text = "NOVA"
    logo.TextColor3 = Color3.fromRGB(100,200,255)
    logo.TextSize = 36
    logo.Font = Enum.Font.GothamBold
    logo.Parent = panel
    local ring = Instance.new("ImageLabel")
    ring.Size = UDim2.new(0,70,0,70)
    ring.Position = UDim2.new(0.5,-35,0,15)
    ring.BackgroundTransparency = 1
    ring.Image = "rbxassetid://4911621264"
    ring.ImageColor3 = Color3.fromRGB(60,150,255)
    ring.ImageTransparency = 0.6
    ring.Parent = panel
    local statusText = Instance.new("TextLabel")
    statusText.Size = UDim2.new(1,0,0,20)
    statusText.Position = UDim2.new(0,0,0,90)
    statusText.BackgroundTransparency = 1
    statusText.Text = "Loading..."
    statusText.TextColor3 = Color3.fromRGB(200,220,255)
    statusText.TextSize = 14
    statusText.Font = Enum.Font.Gotham
    statusText.Parent = panel
    local versionText = Instance.new("TextLabel")
    versionText.Size = UDim2.new(1,0,0,16)
    versionText.Position = UDim2.new(0,0,0,115)
    versionText.BackgroundTransparency = 1
    versionText.Text = "v46.0"
    versionText.TextColor3 = Color3.fromRGB(150,180,220)
    versionText.TextSize = 11
    versionText.Font = Enum.Font.Gotham
    versionText.Parent = panel
    local progressBar = Instance.new("Frame")
    progressBar.Size = UDim2.new(0,280,0,4)
    progressBar.Position = UDim2.new(0.5,-140,0,145)
    progressBar.BackgroundColor3 = Color3.fromRGB(30,50,80)
    progressBar.BorderSizePixel = 0
    progressBar.Parent = panel
    local barCorner = Instance.new("UICorner")
    barCorner.CornerRadius = UDim.new(0,2)
    barCorner.Parent = progressBar
    local fill = Instance.new("Frame")
    fill.Size = UDim2.new(0,0,1,0)
    fill.BackgroundColor3 = Color3.fromRGB(60,150,255)
    fill.BorderSizePixel = 0
    fill.Parent = progressBar
    local fillCorner = Instance.new("UICorner")
    fillCorner.CornerRadius = UDim.new(0,2)
    fillCorner.Parent = fill
    return { screen = screen, ring = ring, statusText = statusText, fill = fill }
end

-- ============================================================
-- ПОСТРОЕНИЕ GUI (без изменений)
-- ============================================================
local function buildMainGUI()
    -- ... (полностью скопировать из предыдущей версии, т.к. он не меняется)
    local gui = Instance.new("ScreenGui")
    gui.Name = "NOVA_MAIN"
    gui.ResetOnSpawn = false
    gui.IgnoreGuiInset = true
    gui.Parent = PlayerGui
    gui.DisplayOrder = 999

    local main = Instance.new("Frame")
    main.Size = UDim2.new(0,WINDOW_W,0,WINDOW_H)
    main.Position = UDim2.new(0,20,0,20)
    main.BackgroundColor3 = Color3.fromRGB(10,18,42)
    main.BackgroundTransparency = 0.05
    main.BorderSizePixel = 0
    main.ClipsDescendants = true
    main.Parent = gui
    local corner = Instance.new("UICorner")
    corner.CornerRadius = UDim.new(0,16)
    corner.Parent = main
    local stroke = Instance.new("UIStroke")
    stroke.Color = Color3.fromRGB(60,150,255)
    stroke.Thickness = 1.5
    stroke.Transparency = 0.5
    stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
    stroke.Parent = main

    local header = Instance.new("Frame")
    header.Size = UDim2.new(1,0,0,HEADER_H)
    header.BackgroundColor3 = Color3.fromRGB(14,24,54)
    header.BackgroundTransparency = 0.1
    header.BorderSizePixel = 0
    header.Parent = main
    local hcorner = Instance.new("UICorner")
    hcorner.CornerRadius = UDim.new(0,16)
    hcorner.Parent = header

    local title = Instance.new("TextLabel")
    title.Size = UDim2.new(1,-120,1,0)
    title.Position = UDim2.new(0,14,0,0)
    title.BackgroundTransparency = 1
    title.Text = "NOVA"
    title.TextColor3 = Color3.fromRGB(200,230,255)
    title.TextSize = 16
    title.TextXAlignment = Enum.TextXAlignment.Left
    title.Font = Enum.Font.GothamBold
    title.Parent = header

    local function winBtn(text, x, color, cb)
        local btn = Instance.new("TextButton")
        btn.Size = UDim2.new(0,28,0,28)
        btn.Position = UDim2.new(1,x,0,6)
        btn.BackgroundColor3 = Color3.fromRGB(30,50,80)
        btn.BackgroundTransparency = 0.3
        btn.BorderSizePixel = 0
        btn.Text = text
        btn.TextColor3 = color
        btn.TextSize = 16
        btn.Font = Enum.Font.Gotham
        btn.Parent = header
        local bcorner = Instance.new("UICorner")
        bcorner.CornerRadius = UDim.new(0,8)
        bcorner.Parent = btn
        local bstroke = Instance.new("UIStroke")
        bstroke.Color = color
        bstroke.Thickness = 1
        bstroke.Transparency = 0.6
        bstroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
        bstroke.Parent = btn
        if cb then btn.MouseButton1Click:Connect(cb) end
        return btn
    end

    local minBtn = winBtn("─", -84, Color3.fromRGB(200,220,255))
    local maxBtn = winBtn("□", -56, Color3.fromRGB(200,220,255))
    local closeBtn = winBtn("✕", -28, Color3.fromRGB(255,100,100))

    local status = Instance.new("TextLabel")
    status.Size = UDim2.new(1,-20,0,18)
    status.Position = UDim2.new(0,10,0,HEADER_H+10)
    status.BackgroundTransparency = 1
    status.Text = "DISABLED"
    status.TextColor3 = Color3.fromRGB(200,220,240)
    status.TextSize = 10
    status.TextXAlignment = Enum.TextXAlignment.Left
    status.Font = Enum.Font.Gotham
    status.Parent = main

    local targetLabel = Instance.new("TextLabel")
    targetLabel.Size = UDim2.new(1,-20,0,18)
    targetLabel.Position = UDim2.new(0,10,0,HEADER_H+28)
    targetLabel.BackgroundTransparency = 1
    targetLabel.Text = "TARGET: NONE"
    targetLabel.TextColor3 = Color3.fromRGB(200,220,240)
    targetLabel.TextSize = 10
    targetLabel.TextXAlignment = Enum.TextXAlignment.Left
    targetLabel.Font = Enum.Font.Gotham
    targetLabel.Parent = main

    local killsLabel = Instance.new("TextLabel")
    killsLabel.Size = UDim2.new(1,-20,0,18)
    killsLabel.Position = UDim2.new(0,10,0,HEADER_H+46)
    killsLabel.BackgroundTransparency = 1
    killsLabel.Text = "KILLS: 0"
    killsLabel.TextColor3 = Color3.fromRGB(240,220,160)
    killsLabel.TextSize = 10
    killsLabel.TextXAlignment = Enum.TextXAlignment.Left
    killsLabel.Font = Enum.Font.Gotham
    killsLabel.Parent = main

    local divider = Instance.new("Frame")
    divider.Size = UDim2.new(1,-20,0,1)
    divider.Position = UDim2.new(0,10,0,HEADER_H+70)
    divider.BackgroundColor3 = Color3.fromRGB(80,140,255)
    divider.BackgroundTransparency = 0.4
    divider.BorderSizePixel = 0
    divider.Parent = main

    local iconNames = {"⏻","🎲","⌖","👁","🤝","⚙"}
    local iconBtns = {}
    local startX = (WINDOW_W - (ICON_SIZE*6 + ICON_SPACING*5)) / 2
    for i, icon in ipairs(iconNames) do
        local btn = Instance.new("TextButton")
        btn.Size = UDim2.new(0,ICON_SIZE,0,ICON_SIZE)
        btn.Position = UDim2.new(0,startX + (ICON_SIZE+ICON_SPACING)*(i-1),0,120)
        btn.BackgroundColor3 = Color3.fromRGB(16,24,50)
        btn.BackgroundTransparency = 0.3
        btn.BorderSizePixel = 0
        btn.Text = icon
        btn.TextColor3 = Color3.fromRGB(220,230,255)
        btn.TextSize = 18
        btn.Font = Enum.Font.Gotham
        btn.Parent = main
        local bcorner = Instance.new("UICorner")
        bcorner.CornerRadius = UDim.new(0,10)
        bcorner.Parent = btn
        local bstroke = Instance.new("UIStroke")
        bstroke.Color = Color3.fromRGB(60,150,255)
        bstroke.Thickness = 1.2
        bstroke.Transparency = 0.8
        bstroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
        bstroke.Parent = btn
        local glow = Instance.new("UIStroke")
        glow.Color = Color3.fromRGB(60,150,255)
        glow.Thickness = 2
        glow.Transparency = 0.8
        glow.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
        glow.Parent = btn
        glow.Visible = false
        iconBtns[icon] = { btn = btn, glow = glow }
    end

    local fovCircle = Instance.new("ImageLabel")
    fovCircle.Size = UDim2.new(0,Settings.FOV*2,0,Settings.FOV*2)
    fovCircle.Position = UDim2.new(0.5,-Settings.FOV,0.5,-Settings.FOV)
    fovCircle.BackgroundTransparency = 1
    fovCircle.Image = "rbxassetid://4911621264"
    fovCircle.ImageColor3 = Color3.fromRGB(255,255,255)
    fovCircle.ImageTransparency = 0.6
    fovCircle.Visible = false
    fovCircle.Parent = gui

    local crosshair = Instance.new("Frame")
    crosshair.Size = UDim2.new(0,0,0,0)
    crosshair.BackgroundTransparency = 1
    crosshair.Visible = false
    crosshair.Parent = gui
    local function updateCrosshair()
        local center = Utils.getCenter()
        crosshair.Position = UDim2.fromOffset(center.X, center.Y)
    end
    local function createDot()
        for _,c in pairs(crosshair:GetChildren()) do c:Destroy() end
        local dot = Instance.new("Frame")
        dot.Size = UDim2.new(0,3,0,3)
        dot.Position = UDim2.new(0.5,-1.5,0.5,-1.5)
        dot.BackgroundColor3 = Color3.fromRGB(255,255,255)
        dot.BorderSizePixel = 0
        dot.Parent = crosshair
        local dcorner = Instance.new("UICorner")
        dcorner.CornerRadius = UDim.new(1,0)
        dcorner.Parent = dot
    end
    createDot()
    updateCrosshair()

    local xrayHolder = Instance.new("Frame")
    xrayHolder.Size = UDim2.new(1,0,1,0)
    xrayHolder.BackgroundTransparency = 1
    xrayHolder.Parent = gui
    VisualState.xrayContainer = xrayHolder

    return {
        gui = gui,
        main = main,
        header = header,
        minBtn = minBtn,
        maxBtn = maxBtn,
        closeBtn = closeBtn,
        status = status,
        targetLabel = targetLabel,
        killsLabel = killsLabel,
        iconBtns = iconBtns,
        fovCircle = fovCircle,
        crosshair = crosshair,
        updateCrosshair = updateCrosshair,
        xrayHolder = xrayHolder,
    }
end

-- ============================================================
-- FRIENDLY WINDOW с пулом строк
-- ============================================================
local function createFriendlyWindow()
    local gui = Instance.new("ScreenGui")
    gui.Name = "NOVA_FRIENDLY"
    gui.ResetOnSpawn = false
    gui.IgnoreGuiInset = true
    gui.Parent = PlayerGui
    gui.DisplayOrder = 998
    gui.Enabled = false

    local window = Instance.new("Frame")
    window.Size = UDim2.new(0,320,0,420)
    window.Position = UDim2.new(0.5,-160,0.5,-210)
    window.BackgroundColor3 = Color3.fromRGB(10,18,42)
    window.BackgroundTransparency = 0.05
    window.BorderSizePixel = 0
    window.ClipsDescendants = true
    window.Parent = gui
    local corner = Instance.new("UICorner")
    corner.CornerRadius = UDim.new(0,16)
    corner.Parent = window
    local stroke = Instance.new("UIStroke")
    stroke.Color = Color3.fromRGB(60,150,255)
    stroke.Thickness = 1.5
    stroke.Transparency = 0.5
    stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
    stroke.Parent = window

    local header = Instance.new("Frame")
    header.Size = UDim2.new(1,0,0,36)
    header.BackgroundColor3 = Color3.fromRGB(14,24,54)
    header.BackgroundTransparency = 0.1
    header.BorderSizePixel = 0
    header.Parent = window
    local hcorner = Instance.new("UICorner")
    hcorner.CornerRadius = UDim.new(0,16)
    hcorner.Parent = header

    local title = Instance.new("TextLabel")
    title.Size = UDim2.new(1,-60,1,0)
    title.Position = UDim2.new(0,14,0,0)
    title.BackgroundTransparency = 1
    title.Text = "FRIENDLY FAIR"
    title.TextColor3 = Color3.fromRGB(200,230,255)
    title.TextSize = 14
    title.TextXAlignment = Enum.TextXAlignment.Left
    title.Font = Enum.Font.GothamBold
    title.Parent = header

    local closeBtn = Instance.new("TextButton")
    closeBtn.Size = UDim2.new(0,28,0,28)
    closeBtn.Position = UDim2.new(1,-34,0,4)
    closeBtn.BackgroundColor3 = Color3.fromRGB(30,50,80)
    closeBtn.BackgroundTransparency = 0.3
    closeBtn.BorderSizePixel = 0
    closeBtn.Text = "✕"
    closeBtn.TextColor3 = Color3.fromRGB(255,100,100)
    closeBtn.TextSize = 16
    closeBtn.Font = Enum.Font.Gotham
    closeBtn.Parent = header

    local listFrame = Instance.new("ScrollingFrame")
    listFrame.Size = UDim2.new(1,-20,1,-50)
    listFrame.Position = UDim2.new(0,10,0,44)
    listFrame.BackgroundTransparency = 1
    listFrame.BorderSizePixel = 0
    listFrame.CanvasSize = UDim2.new(0,0,0,0)
    listFrame.ScrollBarThickness = 4
    listFrame.ScrollBarImageColor3 = Color3.fromRGB(60,150,255)
    listFrame.Parent = window

    -- Пул строк
    local rowPool = {}
    local function getRow()
        for _, row in ipairs(rowPool) do
            if not row.used then
                row.used = true
                row.frame.Visible = true
                return row
            end
        end
        -- создаём новую строку
        local frame = Instance.new("Frame")
        frame.Size = UDim2.new(1,0,0,32)
        frame.BackgroundColor3 = Color3.fromRGB(20,35,65)
        frame.BackgroundTransparency = 0.3
        frame.BorderSizePixel = 0
        frame.Visible = false
        frame.Parent = listFrame
        local rcorner = Instance.new("UICorner")
        rcorner.CornerRadius = UDim.new(0,6)
        rcorner.Parent = frame

        local name = Instance.new("TextLabel")
        name.Size = UDim2.new(1,-80,1,0)
        name.Position = UDim2.new(0,10,0,0)
        name.BackgroundTransparency = 1
        name.Text = ""
        name.TextColor3 = Color3.fromRGB(200,220,255)
        name.TextSize = 12
        name.TextXAlignment = Enum.TextXAlignment.Left
        name.Font = Enum.Font.Gotham
        name.Parent = frame

        local action = Instance.new("TextButton")
        action.Size = UDim2.new(0,30,0,26)
        action.Position = UDim2.new(1,-36,0,3)
        action.BackgroundColor3 = Color3.fromRGB(30,50,80)
        action.BackgroundTransparency = 0.5
        action.BorderSizePixel = 0
        action.Text = ""
        action.TextColor3 = Color3.fromRGB(255,255,255)
        action.TextSize = 16
        action.Font = Enum.Font.Gotham
        action.Parent = frame

        local tag = Instance.new("TextLabel")
        tag.Size = UDim2.new(0,50,1,0)
        tag.Position = UDim2.new(1,-100,0,0)
        tag.BackgroundTransparency = 1
        tag.Text = ""
        tag.TextColor3 = Color3.fromRGB(0,255,150)
        tag.TextSize = 10
        tag.Font = Enum.Font.GothamBold
        tag.TextXAlignment = Enum.TextXAlignment.Right
        tag.Parent = frame

        local row = { frame = frame, name = name, action = action, tag = tag, used = false }
        table.insert(rowPool, row)
        return row
    end

    local function releaseAllRows()
        for _, row in ipairs(rowPool) do
            row.used = false
            row.frame.Visible = false
        end
    end

    local function updateList()
        releaseAllRows()
        local count = 0
        for _, plr in ipairs(localPlayers) do
            count = count + 1
            local row = getRow()
            row.frame.Visible = true
            row.name.Text = plr.Name
            local isF = Friendly.isFriendly(plr)
            row.action.Text = isF and "🗑" or "➕"
            row.action.TextColor3 = isF and Color3.fromRGB(255,100,100) or Color3.fromRGB(100,255,150)
            row.tag.Text = isF and "FRIEND" or ""
            -- привязываем действие
            row.action.MouseButton1Click:Connect(function()
                Friendly.toggle(plr)
                if AimState.target == plr then AimState.target = nil end
                updateList()
            end)
        end
        listFrame.CanvasSize = UDim2.new(0,0,0, count*36 + 10)
    end

    return { gui = gui, update = updateList, closeBtn = closeBtn }
end

-- ============================================================
-- ОСНОВНАЯ ЛОГИКА (AIM, X-RAY) с пулом объектов
-- ============================================================
local raycastParams = RaycastParams.new()
raycastParams.FilterType = Enum.RaycastFilterType.Blacklist
raycastParams.FilterDescendantsInstances = {Player.Character}
Player.CharacterAdded:Connect(function(char)
    raycastParams.FilterDescendantsInstances = {char}
end)

-- Создание пула X-Ray боксов
local function ensurePoolSize(targetSize)
    while VisualState.poolSize < targetSize do
        VisualState.poolSize = VisualState.poolSize + 1
        local container = Instance.new("Frame")
        container.Size = UDim2.new(0,40,0,60)
        container.BackgroundTransparency = 1
        container.Visible = false
        container.Parent = VisualState.xrayContainer

        local border = Instance.new("Frame")
        border.Size = UDim2.new(1,0,1,0)
        border.BackgroundTransparency = 0.7
        border.BackgroundColor3 = Color3.fromHSV(0,1,1)
        border.BorderSizePixel = 0
        border.Parent = container
        local corner = Instance.new("UICorner")
        corner.CornerRadius = UDim.new(0,4)
        corner.Parent = border

        local outline = Instance.new("Frame")
        outline.Size = UDim2.new(1,0,1,0)
        outline.Position = UDim2.new(0,1,0,1)
        outline.Size = UDim2.new(1,-2,1,-2)
        outline.BackgroundTransparency = 1
        outline.BorderSizePixel = 2
        outline.BorderColor3 = Color3.fromHSV(0,1,1)
        outline.BackgroundColor3 = Color3.fromRGB(0,0,0)
        outline.BackgroundTransparency = 0.7
        outline.Parent = container
        local ocorner = Instance.new("UICorner")
        ocorner.CornerRadius = UDim.new(0,3)
        ocorner.Parent = outline

        local nameLabel = Instance.new("TextLabel")
        nameLabel.Size = UDim2.new(1,0,0,16)
        nameLabel.Position = UDim2.new(0,0,1,0)
        nameLabel.BackgroundTransparency = 1
        nameLabel.Text = ""
        nameLabel.TextColor3 = Color3.fromHSV(0,1,1)
        nameLabel.TextSize = 11
        nameLabel.Font = Enum.Font.GothamBold
        nameLabel.TextStrokeTransparency = 0.2
        nameLabel.TextStrokeColor3 = Color3.fromRGB(0,0,0)
        nameLabel.Parent = container

        VisualState.boxPool[#VisualState.boxPool+1] = {
            container = container,
            border = border,
            outline = outline,
            name = nameLabel,
            player = nil,
        }
    end
end

local function getBoxForPlayer(plr)
    for _, box in ipairs(VisualState.boxPool) do
        if box.player == nil then
            box.player = plr
            box.container.Visible = true
            box.name.Text = plr.Name
            return box
        end
    end
    ensurePoolSize(VisualState.poolSize + 1)
    return getBoxForPlayer(plr)
end

function releaseBox(plr)
    for _, box in ipairs(VisualState.boxPool) do
        if box.player == plr then
            box.player = nil
            box.container.Visible = false
            box.name.Text = ""
            break
        end
    end
end

local function clearAllBoxes()
    for _, box in ipairs(VisualState.boxPool) do
        box.player = nil
        box.container.Visible = false
        box.name.Text = ""
    end
end

-- Обновление одного бокса (использует parts._list)
local function updateBox(box, color)
    if not box or not box.player then return end
    local plr = box.player
    if not Utils.isValidPlayer(plr) or Friendly.isFriendly(plr) then
        releaseBox(plr)
        return
    end
    box.border.BackgroundColor3 = color
    box.outline.BorderColor3 = color
    box.name.TextColor3 = color

    local parts = Utils.getCachedParts(plr)
    if not parts then
        box.container.Visible = false
        return
    end
    local partList = parts._list
    if not partList or #partList == 0 then
        box.container.Visible = false
        return
    end
    local minX, maxX, minY, maxY
    for _, part in ipairs(partList) do
        if not part or not part.Parent then continue end
        local pos, onScreen = Camera:WorldToViewportPoint(part.Position)
        if onScreen then
            if not minX then
                minX, maxX, minY, maxY = pos.X, pos.X, pos.Y, pos.Y
            else
                if pos.X < minX then minX = pos.X end
                if pos.X > maxX then maxX = pos.X end
                if pos.Y < minY then minY = pos.Y end
                if pos.Y > maxY then maxY = pos.Y end
            end
        end
    end
    if not minX then box.container.Visible = false; return end
    local padding = 4
    local width = maxX - minX + padding*2
    local height = maxY - minY + padding*2
    width = math.max(width, 20)
    height = math.max(height, 30)
    box.container.Position = UDim2.new(0, minX - padding, 0, minY - padding)
    box.container.Size = UDim2.new(0, width, 0, height)
    box.container.Visible = true
end

-- Обновление X-Ray (вызывается из Heartbeat)
local function updateXRay()
    if GUIState.destroyed then return end
    if not VisualState.xrayEnabled then
        clearAllBoxes()
        return
    end

    VisualState.xrayTimer = VisualState.xrayTimer + 0.016 -- примерно 60fps, но не критично
    local updatePos = VisualState.xrayTimer >= XRAY_POSITION_INTERVAL
    if updatePos then VisualState.xrayTimer = 0 end

    local color = Color3.fromHSV(VisualState.hue, 1, 1)
    -- обновляем hue для следующего вызова (можно делать отдельно)
    VisualState.hue = (VisualState.hue + 0.0032) % 1  -- 0.2 * dt, dt примерно 0.016

    -- Обновляем цвета всех боксов
    for _, box in ipairs(VisualState.boxPool) do
        if box.player then
            box.border.BackgroundColor3 = color
            box.outline.BorderColor3 = color
            box.name.TextColor3 = color
        end
    end

    if not updatePos then return end

    -- Освобождаем боксы для невалидных или дружественных
    for _, box in ipairs(VisualState.boxPool) do
        if box.player then
            if not Utils.isValidPlayer(box.player) or Friendly.isFriendly(box.player) then
                releaseBox(box.player)
            end
        end
    end

    -- Собираем активных игроков прямо из localPlayers без создания новой таблицы
    local activeCount = 0
    for _, plr in ipairs(localPlayers) do
        if Utils.isValidPlayer(plr) and not Friendly.isFriendly(plr) then
            activeCount = activeCount + 1
        end
    end
    ensurePoolSize(activeCount)

    -- Распределяем боксы (без создания usedBoxes)
    local boxIndex = 1
    for _, plr in ipairs(localPlayers) do
        if Utils.isValidPlayer(plr) and not Friendly.isFriendly(plr) then
            -- ищем, есть ли уже бокс для этого игрока
            local assigned = false
            for i = boxIndex, #VisualState.boxPool do
                if VisualState.boxPool[i].player == plr then
                    assigned = true
                    -- меняем местами, чтобы не искать снова
                    if i ~= boxIndex then
                        VisualState.boxPool[i], VisualState.boxPool[boxIndex] = VisualState.boxPool[boxIndex], VisualState.boxPool[i]
                    end
                    boxIndex = boxIndex + 1
                    break
                end
            end
            if not assigned then
                -- берём первый свободный бокс, начиная с boxIndex
                local found = false
                for i = boxIndex, #VisualState.boxPool do
                    if VisualState.boxPool[i].player == nil then
                        local box = VisualState.boxPool[i]
                        box.player = plr
                        box.container.Visible = true
                        box.name.Text = plr.Name
                        if i ~= boxIndex then
                            VisualState.boxPool[i], VisualState.boxPool[boxIndex] = VisualState.boxPool[boxIndex], VisualState.boxPool[i]
                        end
                        boxIndex = boxIndex + 1
                        found = true
                        break
                    end
                end
                -- если не нашли, то расширяем пул (но мы уже ensurePoolSize)
                if not found then
                    ensurePoolSize(VisualState.poolSize + 1)
                    -- повторяем попытку (рекурсивно не надо, просто добавили)
                    local box = VisualState.boxPool[VisualState.poolSize]
                    box.player = plr
                    box.container.Visible = true
                    box.name.Text = plr.Name
                    if VisualState.poolSize ~= boxIndex then
                        VisualState.boxPool[VisualState.poolSize], VisualState.boxPool[boxIndex] = VisualState.boxPool[boxIndex], VisualState.boxPool[VisualState.poolSize]
                    end
                    boxIndex = boxIndex + 1
                end
            end
        end
    end

    -- Все боксы, начиная с boxIndex, должны быть свободными (освобождаем)
    for i = boxIndex, #VisualState.boxPool do
        if VisualState.boxPool[i].player then
            releaseBox(VisualState.boxPool[i].player)
        end
    end

    -- Обновляем позиции всех занятых боксов (первые boxIndex-1)
    for i = 1, boxIndex - 1 do
        updateBox(VisualState.boxPool[i], color)
    end
end

-- ============================================================
-- AIM (оптимизированный поиск Top-5 без сортировки)
-- ============================================================
-- Используем фиксированные переменные для хранения топ-5 кандидатов
local topCandidates = {
    {plr = nil, dist = math.huge},
    {plr = nil, dist = math.huge},
    {plr = nil, dist = math.huge},
    {plr = nil, dist = math.huge},
    {plr = nil, dist = math.huge},
}
-- Чтобы не создавать новые таблицы, переиспользуем эти

local function findBestTarget()
    if not Camera or not Player.Character or not Player.Character.Parent then return nil end
    local center = Utils.getCenter()
    local camPos = Camera.CFrame.Position
    local fovSq = Settings.FOV * Settings.FOV
    local limitSq = Settings.DistanceLimit * Settings.DistanceLimit

    -- Инициализируем топ-5 с бесконечными расстояниями
    for i = 1, MAX_RAYCAST_CANDIDATES do
        topCandidates[i].plr = nil
        topCandidates[i].dist = math.huge
    end

    -- Проходим по всем игрокам, обновляем топ-5
    for _, plr in ipairs(localPlayers) do
        if not Utils.isValidPlayer(plr) or Friendly.isFriendly(plr) then continue end
        local part = Utils.getAimPart(plr)
        if not part or not part.Parent then continue end
        local offset = part.Position - camPos
        local worldDistSq = offset:Dot(offset)
        if worldDistSq > limitSq then continue end
        local screenPos = Utils.getScreenPos(part)
        if not screenPos then continue end
        local dx = screenPos.X - center.X
        local dy = screenPos.Y - center.Y
        local dist = dx*dx + dy*dy
        if dist < fovSq then
            -- вставляем в топ-5
            for i = 1, MAX_RAYCAST_CANDIDATES do
                if dist < topCandidates[i].dist then
                    -- сдвигаем остальные
                    for j = MAX_RAYCAST_CANDIDATES, i+1, -1 do
                        topCandidates[j].plr = topCandidates[j-1].plr
                        topCandidates[j].dist = topCandidates[j-1].dist
                    end
                    topCandidates[i].plr = plr
                    topCandidates[i].dist = dist
                    break
                end
            end
        end
    end

    -- Проверяем видимость для топ-5 (по порядку)
    for i = 1, MAX_RAYCAST_CANDIDATES do
        local plr = topCandidates[i].plr
        if plr and Utils.isVisible(plr, raycastParams, Settings.DistanceLimit) then
            return plr
        end
    end
    return nil
end

local function updateTargetCF(plr)
    if not plr or not Utils.isValidPlayer(plr) then return end
    if Friendly.isFriendly(plr) then
        AimState.target = nil
        AimState.targetCF = nil
        AimState.smoothCF = nil
        return
    end
    if not Camera then return end
    local part = Utils.getAimPart(plr)
    if not part or not part.Parent then return end
    local pos = part.Position
    local vel = Utils.getVelocity(plr)
    local distance = (pos - Camera.CFrame.Position).Magnitude
    local targetPos = pos
    if vel.Magnitude >= 0.1 then
        local flyTime = distance / Settings.BulletSpeed
        local predTime = flyTime * Settings.PredictionStrength
        targetPos = pos + vel * predTime
    end
    AimState.targetCF = CFrame.lookAt(Camera.CFrame.Position, targetPos)
end

local function processAim(dt)
    if GUIState.destroyed or not Camera then return end
    -- X-Ray обновляется отдельно в Heartbeat, здесь не вызываем
    if not AimState.enabled then return end
    AimState.searchTimer = AimState.searchTimer + dt

    if AimState.target and AimState.target.Parent and Utils.isValidPlayer(AimState.target) and not Friendly.isFriendly(AimState.target) then
        local part = Utils.getAimPart(AimState.target)
        local visible = part and part.Parent and Utils.isVisible(AimState.target, raycastParams, Settings.DistanceLimit)
        if visible then
            AimState.lostTimer = 0
            updateTargetCF(AimState.target)
            if AimState.targetCF then
                if AimState.smoothCF then
                    AimState.smoothCF = AimState.smoothCF:Lerp(AimState.targetCF, Settings.Smoothness)
                else
                    AimState.smoothCF = AimState.targetCF
                end
                if Camera then Camera.CFrame = AimState.smoothCF end
            end
            return
        else
            AimState.lostTimer = AimState.lostTimer + dt
            if AimState.lostTimer > Settings.LostTimeout then
                AimState.target = nil
                AimState.targetCF = nil
                AimState.smoothCF = nil
            end
        end
    end

    if AimState.searchTimer < Settings.SearchInterval then return end
    AimState.searchTimer = 0
    local newTarget = findBestTarget()
    if newTarget then
        AimState.target = newTarget
        AimState.lostTimer = 0
        AimState.smoothCF = nil
        AimState.targetCF = nil
        -- Если RandomAim включён, выбираем случайную часть один раз
        if Settings.RandomAim then
            local parts = {"Head", "HumanoidRootPart"}
            AimState.randomAimPart = parts[math.random(1,2)]
        else
            AimState.randomAimPart = nil
        end
        updateTargetCF(newTarget)
        if AimState.targetCF then
            AimState.smoothCF = AimState.targetCF
            if Camera then Camera.CFrame = AimState.smoothCF end
        end
    end
end

-- ============================================================
-- ЗАПУСК
-- ============================================================
local function main()
    -- Очистка старых GUI
    for _, v in ipairs(PlayerGui:GetChildren()) do
        if v.Name == "LoadingScreen" or v.Name == "NOVA_MAIN" or v.Name == "NOVA_FRIENDLY" then
            v:Destroy()
        end
    end

    -- Загрузочный экран
    local loading = createLoadingScreen()
    local ringTween = TweenService:Create(loading.ring, TweenInfo.new(1.2, Enum.EasingStyle.Linear, Enum.EasingDirection.Out, -1, false), {Rotation = 360})
    ringTween:Play()
    local messages = {"Initializing...","Loading Modules...","Loading Interface...","Loading Visuals...","Finalizing..."}
    local progress = 0
    local step = 100 / #messages
    for i, msg in ipairs(messages) do
        loading.statusText.Text = msg
        progress = progress + step
        local tween = TweenService:Create(loading.fill, TweenInfo.new(0.5, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {Size = UDim2.new(progress/100,0,1,0)})
        tween:Play()
        tween.Completed:Wait()
        task.wait(0.1)
    end
    task.wait(0.2)
    loading.screen:Destroy()

    -- Создаём GUI
    local GUI = buildMainGUI()
    local friendlyWindow = createFriendlyWindow()
    _G.NOVA_GUI = GUI

    -- Привязка кнопок
    local btns = GUI.iconBtns

    btns["⏻"].btn.MouseButton1Click:Connect(function()
        AimState.enabled = not AimState.enabled
        if AimState.enabled then
            btns["⏻"].glow.Visible = true
            btns["⏻"].glow.Color = Color3.fromRGB(0,255,100)
            btns["⏻"].glow.Transparency = 0.2
            GUI.fovCircle.Visible = true
            GUI.crosshair.Visible = true
            local target = findBestTarget()
            if target then
                AimState.target = target
                AimState.lostTimer = 0
                AimState.targetCF = nil
                AimState.smoothCF = nil
                if Settings.RandomAim then
                    local parts = {"Head", "HumanoidRootPart"}
                    AimState.randomAimPart = parts[math.random(1,2)]
                end
                updateTargetCF(target)
                if AimState.targetCF then
                    AimState.smoothCF = AimState.targetCF
                    if Camera then Camera.CFrame = AimState.smoothCF end
                end
                GUI.status.Text = "LOCKED: " .. target.Name
                GUI.targetLabel.Text = "TARGET: " .. target.Name
            else
                GUI.status.Text = "SEARCHING..."
                GUI.targetLabel.Text = "TARGET: NONE"
            end
        else
            btns["⏻"].glow.Visible = false
            GUI.fovCircle.Visible = false
            GUI.crosshair.Visible = false
            AimState.target = nil
            AimState.targetCF = nil
            AimState.smoothCF = nil
            clearAllBoxes()
            GUI.status.Text = "DISABLED"
            GUI.targetLabel.Text = "TARGET: NONE"
        end
    end)

    btns["🎲"].btn.MouseButton1Click:Connect(function()
        Settings.RandomAim = not Settings.RandomAim
        btns["🎲"].glow.Visible = Settings.RandomAim
        btns["🎲"].glow.Color = Settings.RandomAim and Color3.fromRGB(255,200,50) or Color3.fromRGB(60,150,255)
        btns["🎲"].glow.Transparency = Settings.RandomAim and 0.2 or 0.8
        if not Settings.RandomAim then
            AimState.randomAimPart = nil
        end
    end)

    btns["⌖"].btn.MouseButton1Click:Connect(function()
        if Settings.AimPart == "Head" then
            Settings.AimPart = "HumanoidRootPart"
            Settings.BackupPart = "Torso"
            GUI.status.Text = "AIM: BODY"
        else
            Settings.AimPart = "Head"
            Settings.BackupPart = "UpperTorso"
            GUI.status.Text = "AIM: HEAD"
        end
    end)

    btns["👁"].btn.MouseButton1Click:Connect(function()
        VisualState.xrayEnabled = not VisualState.xrayEnabled
        btns["👁"].glow.Visible = VisualState.xrayEnabled
        btns["👁"].glow.Color = VisualState.xrayEnabled and Color3.fromRGB(60,150,255) or Color3.fromRGB(255,255,255)
        btns["👁"].glow.Transparency = VisualState.xrayEnabled and 0.2 or 0.8
        if not VisualState.xrayEnabled then clearAllBoxes() end
    end)

    btns["🤝"].btn.MouseButton1Click:Connect(function()
        if GUIState.friendlyOpen then
            friendlyWindow.gui.Enabled = false
            GUIState.friendlyOpen = false
        else
            friendlyWindow.update()
            friendlyWindow.gui.Enabled = true
            GUIState.friendlyOpen = true
        end
    end)

    btns["⚙"].btn.MouseButton1Click:Connect(function()
        print("Settings – можно добавить меню настроек")
    end)

    -- Кнопки окна
    GUI.closeBtn.MouseButton1Click:Connect(function()
        GUI.gui:Destroy()
        friendlyWindow.gui:Destroy()
        GUIState.destroyed = true
        clearAllBoxes()
        if VisualState.xrayContainer then VisualState.xrayContainer:Destroy() end
    end)

    GUI.minBtn.MouseButton1Click:Connect(function()
        if GUIState.minimized then
            GUI.main:TweenSize(UDim2.new(0,WINDOW_W,0,WINDOW_H), "Out", "Quad", 0.3, true)
            for _, child in ipairs(GUI.main:GetChildren()) do
                if child:IsA("TextLabel") or child:IsA("TextButton") then child.Visible = true end
            end
            GUI.minBtn.Text = "─"
            GUIState.minimized = false
        else
            GUI.main:TweenSize(UDim2.new(0,WINDOW_W,0,HEADER_H), "Out", "Quad", 0.3, true)
            for _, child in ipairs(GUI.main:GetChildren()) do
                if child:IsA("TextLabel") or child:IsA("TextButton") then
                    if child ~= GUI.header then child.Visible = false end
                end
            end
            GUI.minBtn.Text = "□"
            GUIState.minimized = true
        end
    end)

    GUI.maxBtn.MouseButton1Click:Connect(function()
        if GUIState.maximized then
            GUI.main:TweenSize(UDim2.new(0,WINDOW_W,0,WINDOW_H), "Out", "Quad", 0.3, true)
            GUI.main:TweenPosition(UDim2.new(0,20,0,20), "Out", "Quad", 0.3, true)
            GUI.maxBtn.Text = "□"
            GUIState.maximized = false
        else
            GUI.main:TweenSize(UDim2.new(0,400,0,420), "Out", "Quad", 0.3, true)
            GUI.main:TweenPosition(UDim2.new(0.5,-200,0.5,-210), "Out", "Quad", 0.3, true)
            GUI.maxBtn.Text = "⧉"
            GUIState.maximized = true
        end
    end)

    -- Обработчики смены камеры
    local function onCameraChanged()
        Camera = workspace.CurrentCamera
        -- Перепривязываем события изменения размера
        if Camera then
            Camera:GetPropertyChangedSignal("ViewportSize"):Connect(function()
                if GUI.updateCrosshair then GUI.updateCrosshair() end
                if GUI.fovCircle then
                    GUI.fovCircle.Size = UDim2.new(0, Settings.FOV*2, 0, Settings.FOV*2)
                    GUI.fovCircle.Position = UDim2.new(0.5, -Settings.FOV, 0.5, -Settings.FOV)
                end
            end)
        end
    end
    workspace:GetPropertyChangedSignal("CurrentCamera"):Connect(onCameraChanged)
    onCameraChanged()

    -- Обновление friendly окна при изменении списка
    local function onPlayerListChange()
        if friendlyWindow.update then friendlyWindow.update() end
    end
    Players.PlayerAdded:Connect(onPlayerListChange)
    Players.PlayerRemoving:Connect(onPlayerListChange)

    -- Клавиатура
    UserInputService.InputBegan:Connect(function(input, processed)
        if processed or GUIState.destroyed then return end
        if input.KeyCode == Enum.KeyCode.One then
            btns["⏻"].btn.MouseButton1Click:Fire()
        elseif input.KeyCode == Enum.KeyCode.Two then
            btns["⌖"].btn.MouseButton1Click:Fire()
        elseif input.KeyCode == Enum.KeyCode.Three then
            btns["👁"].btn.MouseButton1Click:Fire()
        elseif input.KeyCode == Enum.KeyCode.Four then
            btns["🎲"].btn.MouseButton1Click:Fire()
        end
    end)

    -- Разделение: X-Ray на Heartbeat, прицел на RenderStepped
    RunService.Heartbeat:Connect(function()
        if GUIState.destroyed then return end
        updateXRay()
    end)

    RunService.RenderStepped:Connect(function(dt)
        if GUIState.destroyed then return end
        processAim(dt)

        -- Обновление GUI не чаще 0.15 секунды
        GUIState.guiUpdateTimer = GUIState.guiUpdateTimer + dt
        if GUIState.guiUpdateTimer >= GUI_UPDATE_INTERVAL then
            GUIState.guiUpdateTimer = 0
            local statusText = AimState.enabled and (AimState.target and "LOCKED: " .. AimState.target.Name or "SEARCHING...") or "DISABLED"
            local targetText = AimState.target and "TARGET: " .. AimState.target.Name or "TARGET: NONE"
            if statusText ~= GUIState.lastStatus then
                GUI.status.Text = statusText
                GUIState.lastStatus = statusText
            end
            if targetText ~= GUIState.lastTarget then
                GUI.targetLabel.Text = targetText
                GUIState.lastTarget = targetText
            end
            GUI.killsLabel.Text = "KILLS: " .. AimState.killCount
        end
    end)

    -- Уведомление
    game:GetService("StarterGui"):SetCore("SendNotification", {
        Title = "NOVA v46.0 (Super Optimized)",
        Text = "1 - Power | 2 - Head/Body | 3 - X-Ray | 4 - Random Aim",
        Duration = 3
    })
    print("✅ NOVA v46.0 SUPER OPTIMIZED LOADED")
end

-- Запуск
task.spawn(main)
