-- Luau | supermarket_menu.lua | Roblox client | PC/keyboard + mouse/touch UI
-- Menu v1.14: esteira com cliques em sequencia e pendencias limitadas; pagamento preservado.
-- Sem bibliotecas externas; nao envia RemoteEvents ou RemoteFunctions.

local Players = game:GetService("Players")
local UIS = game:GetService("UserInputService")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local player = Players.LocalPlayer
assert(player, "Execute no contexto do cliente Roblox.")
local playerGui = player:WaitForChild("PlayerGui", 15)
assert(playerGui, "PlayerGui nao encontrado.")

local GUI_NAME = "ZyonSupermarketLocalPanel"
local oldGui = playerGui:FindFirstChild(GUI_NAME)
if oldGui then oldGui:Destroy() end

local C = {
    bg = Color3.fromRGB(17, 21, 30),
    card = Color3.fromRGB(26, 32, 44),
    input = Color3.fromRGB(35, 43, 58),
    line = Color3.fromRGB(49, 60, 78),
    text = Color3.fromRGB(235, 241, 250),
    muted = Color3.fromRGB(158, 174, 195),
    accent = Color3.fromRGB(74, 223, 175),
    dark = Color3.fromRGB(13, 38, 31),
    amber = Color3.fromRGB(242, 195, 110),
}
local WIDTH, HEIGHT, HEADER = 464, 460, 72
local MIN_SPEED, MAX_SPEED = 8, 100
local state = {
    alive = true, minimized = false, capturing = false,
    key = Enum.KeyCode.T, speed = 16, speedEnabled = false,
    humanoid = nil, original = nil, lastApplied = nil,
    captureToken = 0, drag = nil, sliding = nil, reportOpen = false,
}
local connections = {}
local characterConnection
local notice, refreshSpeed, refreshKey
local autoController

local function connect(signal, callback)
    local connection = signal:Connect(callback)
    table.insert(connections, connection)
    return connection
end

local function new(class, properties, parent)
    local object = Instance.new(class)
    for key, value in pairs(properties) do object[key] = value end
    object.Parent = parent
    return object
end

local function round(object, radius)
    new("UICorner", { CornerRadius = UDim.new(0, radius or 10) }, object)
end

local function label(parent, text, x, y, width, height, size, color)
    return new("TextLabel", {
        BackgroundTransparency = 1, Position = UDim2.fromOffset(x, y),
        Size = UDim2.fromOffset(width, height), Text = text,
        Font = Enum.Font.Gotham, TextSize = size or 14,
        TextColor3 = color or C.text, TextXAlignment = Enum.TextXAlignment.Left,
        TextYAlignment = Enum.TextYAlignment.Center, TextWrapped = true,
    }, parent)
end

local function button(parent, text, x, y, width, height, color)
    local object = new("TextButton", {
        Position = UDim2.fromOffset(x, y), Size = UDim2.fromOffset(width, height),
        BackgroundColor3 = color or C.input, BorderSizePixel = 0,
        Text = text, TextColor3 = C.text, TextSize = 13,
        Font = Enum.Font.GothamMedium, AutoButtonColor = true,
    }, parent)
    round(object, 8)
    return object
end

local gui = new("ScreenGui", {
    Name = GUI_NAME, ResetOnSpawn = false, IgnoreGuiInset = true,
    ZIndexBehavior = Enum.ZIndexBehavior.Sibling, DisplayOrder = 80,
}, playerGui)
local screen = new("Frame", {
    Name = "Screen", BackgroundTransparency = 1,
    Size = UDim2.fromScale(1, 1), Active = false,
}, gui)
local panel = new("Frame", {
    Name = "Panel", Size = UDim2.fromOffset(WIDTH, HEIGHT),
    BackgroundColor3 = C.bg, BorderSizePixel = 0,
    Active = true, ClipsDescendants = true,
}, screen)
round(panel, 16)
new("UIStroke", { Color = C.line, Thickness = 1 }, panel)
local scale = new("UIScale", { Scale = 1 }, panel)

local dragArea = new("TextButton", {
    Name = "DragHeader", BackgroundTransparency = 1,
    Position = UDim2.fromOffset(0, 0), Size = UDim2.fromOffset(WIDTH - 96, HEADER),
    Text = "", AutoButtonColor = false,
}, panel)
local brand = label(dragArea, "ZYON  /  SUPERMARKET", 20, 14, 320, 24, 16)
brand.Font = Enum.Font.GothamBold
local keyHint = label(dragArea, "T · ocultar / mostrar", 20, 39, 320, 18, 11, C.muted)
local minimize = button(panel, "−", WIDTH - 88, 19, 32, 32)
local hide = button(panel, "×", WIDTH - 48, 19, 32, 32)
local tabsBar = new("Frame", {
    BackgroundTransparency = 1, Position = UDim2.fromOffset(20, 80),
    Size = UDim2.fromOffset(WIDTH - 40, 36),
}, panel)
local body = new("Frame", {
    BackgroundTransparency = 1, Position = UDim2.fromOffset(20, 132),
    Size = UDim2.fromOffset(WIDTH - 40, 278),
}, panel)
local footer = label(panel, "Pronto. Arraste pelo título.", 20, HEIGHT - 38, WIDTH - 40, 26, 11, C.muted)

notice = function(text)
    if state.alive then footer.Text = text end
end

local pages, tabs = {}, {}
local function selectTab(name)
    for key, page in pairs(pages) do
        page.Visible = key == name
        tabs[key].BackgroundColor3 = key == name and C.accent or C.card
        tabs[key].TextColor3 = key == name and C.dark or C.muted
    end
    state.sliding = nil
    state.capturing = false
    state.captureToken = state.captureToken + 1
    if refreshKey then refreshKey() end
end
for index, name in ipairs({ "Movimento", "Tecla e menu", "Caixa e saldo" }) do
    local tab = button(tabsBar, name, (index - 1) * 144, 0, 136, 36)
    tabs[name] = tab
    pages[name] = new("Frame", {
        Name = "Page" .. index, BackgroundTransparency = 1,
        Size = UDim2.fromScale(1, 1), Visible = false,
    }, body)
    connect(tab.Activated, function() selectTab(name) end)
end

local function card(parent, y, height)
    local frame = new("Frame", {
        Position = UDim2.fromOffset(0, y), Size = UDim2.fromOffset(424, height),
        BackgroundColor3 = C.card, BorderSizePixel = 0,
    }, parent)
    round(frame, 12)
    return frame
end

local movement = pages["Movimento"]
local speedCard = card(movement, 0, 188)
label(speedCard, "Velocidade de movimento", 16, 12, 280, 24, 15)
label(speedCard, "Controle local · studs por segundo", 16, 37, 280, 20, 11, C.muted)
local toggle = button(speedCard, "OFF", 344, 18, 64, 30)
local speedValue = new("TextBox", {
    Position = UDim2.fromOffset(332, 70), Size = UDim2.fromOffset(76, 36),
    BackgroundColor3 = C.input, BorderSizePixel = 0, Text = "16",
    ClearTextOnFocus = false, Font = Enum.Font.GothamMedium,
    TextSize = 16, TextColor3 = C.text,
}, speedCard)
round(speedValue, 8)
label(speedCard, "Valor escolhido", 16, 76, 240, 24, 13, C.muted)
local trackHit = new("TextButton", {
    Position = UDim2.fromOffset(16, 112), Size = UDim2.fromOffset(392, 30),
    Text = "", BackgroundTransparency = 1, AutoButtonColor = false,
}, speedCard)
local track = new("Frame", {
    Position = UDim2.new(0, 0, 0.5, -3), Size = UDim2.new(1, 0, 0, 6),
    BackgroundColor3 = C.input, BorderSizePixel = 0,
}, trackHit)
round(track, 3)
local fill = new("Frame", {
    Size = UDim2.fromScale(0, 1), BackgroundColor3 = C.accent, BorderSizePixel = 0,
}, track)
round(fill, 3)
local thumb = new("Frame", {
    AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0, 0.5),
    Size = UDim2.fromOffset(16, 16), BackgroundColor3 = C.accent, BorderSizePixel = 0,
}, track)
round(thumb, 8)
label(speedCard, tostring(MIN_SPEED), 16, 146, 50, 20, 11, C.muted)
local maxLabel = label(speedCard, tostring(MAX_SPEED), 358, 146, 50, 20, 11, C.muted)
maxLabel.TextXAlignment = Enum.TextXAlignment.Right
local liveSpeed = label(movement, "Aguardando personagem…", 0, 198, 424, 22, 12, C.muted)
local restore = button(movement, "Restaurar velocidade", 0, 234, 206, 36)
label(movement, "O servidor pode corrigir o valor.", 220, 231, 204, 42, 11, C.muted)

local function restoreSpeed()
    local humanoid = state.humanoid
    if humanoid and humanoid.Parent and state.original and state.lastApplied
        and math.abs(humanoid.WalkSpeed - state.lastApplied) < 0.01 then
        humanoid.WalkSpeed = state.original
    end
    state.lastApplied = nil
end

local function applySpeed()
    if state.speedEnabled and state.humanoid and state.humanoid.Parent then
        state.humanoid.WalkSpeed = state.speed
        state.lastApplied = state.speed
    end
end

refreshSpeed = function()
    local ratio = (state.speed - MIN_SPEED) / (MAX_SPEED - MIN_SPEED)
    fill.Size = UDim2.fromScale(ratio, 1)
    thumb.Position = UDim2.fromScale(ratio, 0.5)
    if UIS:GetFocusedTextBox() ~= speedValue then speedValue.Text = tostring(state.speed) end
    toggle.Text = state.speedEnabled and "ON" or "OFF"
    toggle.BackgroundColor3 = state.speedEnabled and C.accent or C.input
    toggle.TextColor3 = state.speedEnabled and C.dark or C.muted
end

local function setSpeed(value)
    if not value or value ~= value or math.abs(value) == math.huge then
        speedValue.Text = tostring(state.speed)
        notice("Digite um número entre 8 e 100.")
        return
    end
    state.speed = math.clamp(math.floor(value + 0.5), MIN_SPEED, MAX_SPEED)
    applySpeed()
    refreshSpeed()
end

connect(speedValue.FocusLost, function()
    setSpeed(tonumber((speedValue.Text:gsub(",", "."))))
    speedValue.Text = tostring(state.speed)
end)
connect(toggle.Activated, function()
    if state.speedEnabled then
        restoreSpeed()
        state.speedEnabled = false
        notice("Controle de velocidade desativado.")
    else
        if state.humanoid then state.original = state.humanoid.WalkSpeed end
        state.speedEnabled = true
        applySpeed()
        notice("Controle local ativado; verifique a velocidade observada.")
    end
    refreshSpeed()
end)
connect(restore.Activated, function()
    restoreSpeed()
    state.speedEnabled = false
    local value = state.humanoid and state.humanoid.WalkSpeed or 16
    setSpeed(value)
    notice("Controle desligado; valor anterior restaurado quando ainda aplicável.")
end)

local settings = pages["Tecla e menu"]
local keyCard = card(settings, 0, 126)
label(keyCard, "Ocultar e mostrar o painel", 16, 12, 390, 26, 15)
label(keyCard, "Clique na tecla e pressione outra. Esc cancela.", 16, 42, 390, 24, 12, C.muted)
local keyButton = button(keyCard, "T", 16, 78, 150, 32)
local resetKey = button(keyCard, "Voltar para T", 182, 78, 226, 32)
label(settings, "− recolhe o painel à barra de título.\n× oculta tudo; a tecla escolhida traz o painel de volta.\nO atalho fica suspenso enquanto você digita.", 0, 139, 424, 70, 12, C.muted)
local unload = button(settings, "Encerrar script", 0, 234, 206, 36)
label(settings, "Remove o menu e desliga o controle.", 220, 231, 204, 42, 11, C.muted)

refreshKey = function()
    keyButton.Text = state.capturing and "Pressione uma tecla…" or state.key.Name
    keyHint.Text = state.key.Name .. " · ocultar / mostrar"
end
local function cancelCapture()
    state.capturing = false
    state.captureToken = state.captureToken + 1
    refreshKey()
end
connect(keyButton.Activated, function()
    state.capturing = true
    state.captureToken = state.captureToken + 1
    local token = state.captureToken
    refreshKey()
    notice("Pressione a nova tecla. Esc cancela.")
    task.delay(10, function()
        if state.alive and state.capturing and token == state.captureToken then
            cancelCapture()
            notice("Troca de tecla cancelada por tempo esgotado.")
        end
    end)
end)
connect(resetKey.Activated, function()
    state.key = Enum.KeyCode.T
    cancelCapture()
    notice("Atalho restaurado para T.")
end)
connect(unload.Activated, function() gui:Destroy() end)

local integration = pages["Caixa e saldo"]
local cashierCard = card(integration, 0, 98)
label(cashierCard, "Atendimento automático", 16, 10, 280, 25, 15)
local autoToggle = button(cashierCard, "OFF", 344, 10, 64, 30)
local autoStatus = label(cashierCard, "DESLIGADO · F8 INTERROMPE", 16, 38, 390, 18, 10, C.amber)
label(cashierCard, "Ative no caixa com esteira e mão do NPC visíveis. Produtos e pagamento automáticos. F8 interrompe.", 16, 59, 390, 33, 11, C.muted)
local moneyCard = card(integration, 110, 98)
label(moneyCard, "Give money", 16, 10, 390, 25, 15)
label(moneyCard, "INDISPONÍVEL NESTA VERSÃO", 16, 36, 390, 18, 10, C.amber)
label(moneyCard, "Não há uma operação de crédito identificada. Alterar um número local não comprova mudança no saldo salvo.", 16, 57, 390, 33, 11, C.muted)
local diagnose = button(integration, "Gerar diagnóstico local", 0, 234, 206, 36)
label(integration, "Abra o caixa antes. O relatório abre neste painel.", 220, 231, 204, 42, 11, C.muted)

local reportPanel = new("Frame", {
    Name = "DiagnosticReport", Position = UDim2.fromOffset(20, 80),
    Size = UDim2.fromOffset(424, 330), BackgroundColor3 = C.bg,
    BorderSizePixel = 0, ZIndex = 10, Active = true, Visible = false,
}, panel)
label(reportPanel, "Relatório do caixa", 0, 0, 288, 28, 16)
local closeReport = button(reportPanel, "Voltar", 336, 0, 88, 30)
label(reportPanel, "Selecione o texto, copie com Ctrl+C e cole no chat.", 0, 35, 424, 24, 11, C.muted)
local reportScroll = new("ScrollingFrame", {
    Position = UDim2.fromOffset(0, 68), Size = UDim2.fromOffset(424, 212),
    BackgroundColor3 = C.card, BorderSizePixel = 0,
    CanvasSize = UDim2.fromOffset(0, 0), AutomaticCanvasSize = Enum.AutomaticSize.Y,
    ScrollingDirection = Enum.ScrollingDirection.Y,
    ScrollBarThickness = 6, ScrollBarImageColor3 = C.accent,
}, reportPanel)
round(reportScroll, 8)
local reportText = new("TextBox", {
    Name = "ReportText", Position = UDim2.fromOffset(10, 8),
    Size = UDim2.new(1, -30, 0, 196), AutomaticSize = Enum.AutomaticSize.Y,
    BackgroundTransparency = 1, Text = "", ClearTextOnFocus = false,
    MultiLine = true, TextWrapped = true, RichText = false,
    Font = Enum.Font.Code, TextSize = 12, TextColor3 = C.text,
    TextXAlignment = Enum.TextXAlignment.Left,
    TextYAlignment = Enum.TextYAlignment.Top,
}, reportScroll)
local selectReport = button(reportPanel, "Selecionar tudo", 0, 294, 206, 36, C.accent)
selectReport.TextColor3 = C.dark
label(reportPanel, "Depois pressione Ctrl+C.", 220, 291, 204, 42, 11, C.muted)
local lastReport = ""

local function showReport(text)
    lastReport = text
    reportText.Text = text
    reportScroll.CanvasPosition = Vector2.new(0, 0)
    state.reportOpen = true
    reportPanel.Visible = true
    notice("Relatório aberto. Selecione, copie e envie no chat.")
end
connect(selectReport.Activated, function()
    reportText.Text = lastReport
    reportText:CaptureFocus()
    task.defer(function()
        if state.alive and state.reportOpen and reportText:IsFocused() then
            reportText.CursorPosition = #reportText.Text + 1
            reportText.SelectionStart = 1
            notice("Texto selecionado. Pressione Ctrl+C para copiar.")
        end
    end)
end)
connect(reportText.FocusLost, function()
    -- Restaura o relatorio caso alguma tecla tenha alterado o campo de copia.
    if state.alive then reportText.Text = lastReport end
end)
connect(closeReport.Activated, function()
    reportText:ReleaseFocus()
    state.reportOpen = false
    reportPanel.Visible = false
    notice("Relatório fechado. Gere novamente para atualizar os dados.")
end)

local function collectDiagnostic()
    local lines = {
        "Diagnóstico local v1.1 — " .. os.date("!%Y-%m-%dT%H:%M:%SZ"),
        "PlaceId=" .. tostring(game.PlaceId),
        "UniverseId=" .. tostring(game.GameId),
        "Só nomes e textos replicados; nenhum evento foi disparado.",
        "--- Eventos em ReplicatedStorage (máximo 250) ---",
    }
    local remoteLines = {}
    for _, object in ipairs(ReplicatedStorage:GetDescendants()) do
        if object:IsA("RemoteEvent") or object:IsA("RemoteFunction")
            or object:IsA("UnreliableRemoteEvent") then
            table.insert(remoteLines, object.ClassName .. " | " .. object:GetFullName())
        end
    end
    table.sort(remoteLines)
    for index = 1, math.min(#remoteLines, 250) do
        table.insert(lines, remoteLines[index])
    end
    table.insert(lines, "Total de eventos encontrados: " .. #remoteLines)
    table.insert(lines, "--- Textos do caixa no PlayerGui (máximo 80) ---")
    local terms = { "cash", "check", "register", "change", "pay", "total", "scan", "confirm", "caixa", "troco", "pagar", "compra" }
    local count = 0
    for _, object in ipairs(playerGui:GetDescendants()) do
        if not object:IsDescendantOf(gui) and (object:IsA("TextLabel") or object:IsA("TextButton")) then
            local haystack = string.lower(object.Name .. " " .. object.Text)
            local relevant = false
            for _, term in ipairs(terms) do
                if string.find(haystack, term, 1, true) then relevant = true; break end
            end
            if relevant then
                count = count + 1
                local text = (object.Text:gsub("[\r\n]", " ")):sub(1, 160)
                table.insert(lines, object:GetFullName() .. " | " .. text)
                if count >= 80 then break end
            end
        end
    end
    table.insert(lines, "--- FIM DO RELATÓRIO ---")
    return lines
end
connect(diagnose.Activated, function()
    local ok, lines = pcall(collectDiagnostic)
    if not ok then
        showReport("[Zyon] Falha ao gerar diagnóstico: " .. tostring(lines))
        notice("Falha no diagnóstico. Copie a mensagem exibida.")
        return
    end
    local tagged = {}
    for _, line in ipairs(lines) do
        table.insert(tagged, "[Zyon] " .. line)
    end
    showReport(table.concat(tagged, "\n"))
    for _, line in ipairs(tagged) do print(line) end
end)

local function clampPanel()
    local size = screen.AbsoluteSize
    local width = WIDTH * scale.Scale
    local height = (state.minimized and HEADER or HEIGHT) * scale.Scale
    local x = math.clamp(panel.Position.X.Offset, 8, math.max(8, size.X - width - 8))
    local y = math.clamp(panel.Position.Y.Offset, 8, math.max(8, size.Y - height - 8))
    panel.Position = UDim2.fromOffset(x, y)
end
local positioned = false
local function resize()
    local size = screen.AbsoluteSize
    if size.X <= 0 or size.Y <= 0 then return end
    scale.Scale = math.min(1, (size.X - 24) / WIDTH, (size.Y - 24) / HEIGHT)
    if not positioned then
        panel.Position = UDim2.fromOffset((size.X - WIDTH * scale.Scale) / 2, (size.Y - HEIGHT * scale.Scale) / 2)
        positioned = true
    end
    clampPanel()
end

local function setHidden(hidden)
    if not hidden and autoController and autoController.running() then
        autoController.stop("Pausado para abrir o menu.")
    end
    cancelCapture()
    state.drag, state.sliding = nil, nil
    local focused = UIS:GetFocusedTextBox()
    if focused and focused:IsDescendantOf(gui) then focused:ReleaseFocus() end
    gui.Enabled = not hidden
end
connect(hide.Activated, function() setHidden(true) end)
connect(minimize.Activated, function()
    cancelCapture()
    state.sliding = nil
    local focused = UIS:GetFocusedTextBox()
    if focused and focused:IsDescendantOf(gui) then focused:ReleaseFocus() end
    state.minimized = not state.minimized
    panel.Size = UDim2.fromOffset(WIDTH, state.minimized and HEADER or HEIGHT)
    tabsBar.Visible = not state.minimized
    body.Visible = not state.minimized
    footer.Visible = not state.minimized
    reportPanel.Visible = not state.minimized and state.reportOpen
    minimize.Text = state.minimized and "+" or "−"
    clampPanel()
end)

local function pointer(input)
    return input.UserInputType == Enum.UserInputType.MouseButton1
        or input.UserInputType == Enum.UserInputType.Touch
end
connect(dragArea.InputBegan, function(input)
    if pointer(input) then
        state.drag = { input = input, start = input.Position, origin = panel.Position }
    end
end)
local function slideAt(x)
    local width = track.AbsoluteSize.X
    if width <= 0 then return end
    local ratio = math.clamp((x - track.AbsolutePosition.X) / width, 0, 1)
    setSpeed(MIN_SPEED + ratio * (MAX_SPEED - MIN_SPEED))
end
connect(trackHit.InputBegan, function(input)
    if pointer(input) then
        local focused = UIS:GetFocusedTextBox()
        if focused == speedValue then focused:ReleaseFocus() end
        state.sliding = input
        slideAt(input.Position.X)
    end
end)
connect(UIS.InputChanged, function(input)
    if not gui.Enabled then return end
    local mouse = input.UserInputType == Enum.UserInputType.MouseMovement
    local drag = state.drag
    if drag and (input == drag.input or (mouse and drag.input.UserInputType == Enum.UserInputType.MouseButton1)) then
        local delta = input.Position - drag.start
        panel.Position = UDim2.fromOffset(drag.origin.X.Offset + delta.X, drag.origin.Y.Offset + delta.Y)
        clampPanel()
    end
    local sliding = state.sliding
    if sliding and (input == sliding or (mouse and sliding.UserInputType == Enum.UserInputType.MouseButton1)) then
        slideAt(input.Position.X)
    end
end)
connect(UIS.InputEnded, function(input)
    if state.drag and input == state.drag.input then state.drag = nil end
    if state.sliding == input then state.sliding = nil end
end)
connect(UIS.WindowFocusReleased, function()
    if autoController and autoController.running() then autoController.stop("Roblox perdeu o foco.") end
    state.drag, state.sliding = nil, nil
    cancelCapture()
end)
connect(UIS.InputBegan, function(input)
    if input.UserInputType ~= Enum.UserInputType.Keyboard or UIS:GetFocusedTextBox() then return end
    if state.capturing then
        if input.KeyCode == Enum.KeyCode.Unknown then return end
        if input.KeyCode == Enum.KeyCode.F8 then
            notice("F8 está reservado para interromper o atendimento.")
            return
        end
        if input.KeyCode == Enum.KeyCode.Escape then
            cancelCapture()
            notice("Troca de tecla cancelada.")
        else
            state.key = input.KeyCode
            cancelCapture()
            notice("Novo atalho: " .. state.key.Name .. ".")
        end
        return
    end
    -- Nao descarta teclas que tambem sejam usadas por outra interface do jogo.
    -- Campos de texto ja foram excluidos acima.
    if input.KeyCode == state.key then setHidden(gui.Enabled) end
end)

local function bindCharacter(character)
    if characterConnection then characterConnection:Disconnect(); characterConnection = nil end
    restoreSpeed()
    state.humanoid, state.original, state.lastApplied = nil, nil, nil
    local function attach(humanoid)
        if not state.alive or player.Character ~= character then return end
        state.humanoid = humanoid
        state.original = humanoid.WalkSpeed
        applySpeed()
    end
    local humanoid = character:FindFirstChildOfClass("Humanoid")
    if humanoid then
        attach(humanoid)
    else
        characterConnection = character.ChildAdded:Connect(function(child)
            if child:IsA("Humanoid") then
                if characterConnection then characterConnection:Disconnect(); characterConnection = nil end
                attach(child)
            end
        end)
    end
end
connect(player.CharacterAdded, bindCharacter)
connect(player.CharacterRemoving, function(character)
    if characterConnection then characterConnection:Disconnect(); characterConnection = nil end
    if state.humanoid and state.humanoid:IsDescendantOf(character) then
        restoreSpeed()
        state.humanoid, state.original, state.lastApplied = nil, nil, nil
    end
end)
local elapsed = 0
connect(RunService.Heartbeat, function(dt)
    elapsed = elapsed + dt
    if elapsed < 0.25 then return end
    elapsed = 0
    local humanoid = state.humanoid
    if not humanoid or not humanoid.Parent then
        liveSpeed.Text = "Aguardando personagem…"
        liveSpeed.TextColor3 = C.muted
        return
    end
    local observed = humanoid.WalkSpeed
    local changed = state.speedEnabled and math.abs(observed - state.speed) > 0.1
    liveSpeed.Text = string.format("WalkSpeed observado: %.1f%s", observed, changed and " · alterado pelo jogo" or "")
    liveSpeed.TextColor3 = changed and C.amber or C.muted
end)
connect(screen:GetPropertyChangedSignal("AbsoluteSize"), resize)
connect(gui.Destroying, function()
    if not state.alive then return end
    if autoController then autoController.stop("Menu encerrado.", false) end
    state.alive = false
    restoreSpeed()
    if characterConnection then characterConnection:Disconnect() end
    for _, connection in ipairs(connections) do connection:Disconnect() end
    table.clear(connections)
end)

-- Controller inserted into the menu after its UI and lifecycle handlers exist.
autoController = (function()
    local GuiService = game:GetService("GuiService")
    local active = false
    local generation = 0
    local transaction
    local driver, driverKind
    local paymentGui, paymentRoot, desk, detector
    local paymentConnections = {}
    local eventSerial = 0
    local scanSerial = 0
    local scanMisses = 0
    local nextScanAt = 0
    local pendingScans = {}
    local conveyorCursor = 1
    local transactionSerial = 0
    local lastStatus
    local lastManualClick = -math.huge
    local injectingMouse = false
    local syntheticReleaseSeen = false
    local function observeManualClick(input, released)
        if not active or input.UserInputType ~= Enum.UserInputType.MouseButton1 then return end
        if injectingMouse then
            if released then syntheticReleaseSeen = true end
            return
        end
        lastManualClick = os.clock()
    end
    connect(UIS.InputBegan, function(input) observeManualClick(input, false) end)
    connect(UIS.InputEnded, function(input) observeManualClick(input, true) end)

    local function report(message)
        if lastStatus == message then return end
        lastStatus = message
        if state.alive then autoStatus.Text = message; notice(message) end
        print("[ZyonAuto] " .. message)
    end

    local function paint()
        autoToggle.Text = active and "ON" or "OFF"
        autoToggle.BackgroundColor3 = active and C.accent or C.input
        autoToggle.TextColor3 = active and C.dark or C.muted
    end

    local function stop(message, show)
        local wasActive = active
        active = false
        generation = generation + 1
        transaction = nil
        table.clear(pendingScans)
        for _, connection in ipairs(paymentConnections) do connection:Disconnect() end
        table.clear(paymentConnections)
        if wasActive then
            paint()
            report(message or "Atendimento pausado.")
            if show ~= false and state.alive then gui.Enabled = true end
        end
    end

    local function shown(object)
        if not object or not object.Parent then return false end
        local item = object
        while item and item ~= playerGui do
            if item:IsA("GuiObject") and not item.Visible then return false end
            if item:IsA("ScreenGui") and not item.Enabled then return false end
            item = item.Parent
        end
        return item == playerGui
    end

    local function at(root, ...)
        local object = root
        for _, name in ipairs({ ... }) do
            object = object and object:FindFirstChild(name)
        end
        return object
    end

    local function cents(value)
        if type(value) ~= "number" or value ~= value or value < 0 or value > 100000 then return nil end
        return math.floor(value * 100 + 0.5)
    end

    local function check(token)
        if not active or generation ~= token or not state.alive then error("EXECUCAO_CANCELADA", 0) end
        if UIS:GetFocusedTextBox() or GuiService.MenuIsOpen then error("Feche o chat ou menu do Roblox para continuar.", 0) end
        if not shown(at(paymentGui, "Leave")) then error("O jogador saiu do caixa.", 0) end
        if not desk or not desk.Parent or not detector or not detector.Parent then error("Caixa removido.", 0) end
        local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
        if not root or (root.Position - detector.Position).Magnitude > 16 then error("Jogador distante do caixa selecionado.", 0) end
    end

    local function sendButton(position, down)
        if driverKind == "VirtualInput" then
            driver:SendMouseButton(position, Enum.UserInputType.MouseButton1, down, 0)
        else
            driver:SendMouseButtonEvent(position.X, position.Y, 0, down, game, 0)
        end
    end

    local function mouseIdle()
        return not UIS:IsMouseButtonPressed(Enum.UserInputType.MouseButton1)
            and os.clock() - lastManualClick >= 0.6
    end

    local function waitForMouseIdle(token)
        local waiting = false
        while true do
            check(token)
            if mouseIdle() then
                if waiting then report("Mouse livre; continuando o pagamento.") end
                return
            end
            if not waiting then
                report("Pagamento aguardando você soltar o mouse e parar de clicar.")
                waiting = true
            end
            task.wait(0.05)
        end
    end

    local FAST_CLICK = { hold = 0.025, gap = 0.03 }
    -- Cash buttons may acknowledge Activated before accepting another denomination.
    -- Small reduction from the 0.6s gap that worked in the user's latest test.
    local CASH_CLICK = { hold = 0.06, gap = 0.5 }

    local function press(position, token, timing)
        timing = timing or FAST_CLICK
        check(token)
        if UIS:IsMouseButtonPressed(Enum.UserInputType.MouseButton1) then
            return false -- A manual press won the race: yield without disabling the cashier.
        end
        local camera = workspace.CurrentCamera
        local viewport = camera and camera.ViewportSize
        if not viewport or position.X < 2 or position.Y < 60 or position.X > viewport.X - 2
            or position.Y > viewport.Y - 2 then error("Controle fora da área clicável da tela.", 0) end
        injectingMouse = true
        syntheticReleaseSeen = false
        local ok, reason = pcall(function()
            if driverKind == "VirtualInput" then driver:SendMousePosition(position)
            else driver:SendMouseMoveEvent(position.X, position.Y, game) end
            sendButton(position, true)
            task.wait(timing.hold)
            syntheticReleaseSeen = false
            sendButton(position, false)
            -- InputEnded can arrive on a later frame. Keep it inside the synthetic
            -- click window so our own release does not restart the manual idle delay.
            local releaseDeadline = os.clock() + 0.12
            while not syntheticReleaseSeen and os.clock() < releaseDeadline do task.wait() end
        end)
        if not ok then
            pcall(function() sendButton(position, false) end)
            injectingMouse = false
            error("Entrada virtual recusada: " .. tostring(reason), 0)
        end
        injectingMouse = false
        check(token)
        return true
    end

    local function click(buttonObject, token, timing)
        timing = timing or FAST_CLICK
        while true do
            waitForMouseIdle(token)
            if not buttonObject or not buttonObject:IsA("GuiButton") or not shown(buttonObject) or not buttonObject.Active then
                error("Botão esperado não está disponível.", 0)
            end
            local position = buttonObject.AbsolutePosition + buttonObject.AbsoluteSize / 2
            local screenGui = buttonObject:FindFirstAncestorOfClass("ScreenGui")
            if screenGui and not screenGui.IgnoreGuiInset then
                local inset = GuiService:GetGuiInset()
                position = position + inset
            end
            local activated = false
            local connection = buttonObject.Activated:Connect(function() activated = true end)
            local ok, result = pcall(press, position, token, timing)
            local deadline = os.clock() + 0.5
            while ok and result and active and generation == token and not activated and os.clock() < deadline do task.wait() end
            connection:Disconnect()
            if not ok then error(result, 0) end
            check(token)
            if result then
                if not activated then error("Clique não confirmado em " .. buttonObject.Name .. ". Confira se há uma janela sobre o caixa.", 0) end
                local settleDeadline = os.clock() + timing.gap
                repeat
                    check(token)
                    task.wait()
                until os.clock() >= settleDeadline
                return
            end
            -- No synthetic click was sent. Wait and validate the button again.
            task.wait(0.05)
        end
    end

    local denominations = {
        {5000, "CashImageFrame", "50DollorFrame"},
        {2000, "CashImageFrame", "20DollorFrame"},
        {1000, "CashImageFrame", "10DollorFrame"},
        {500, "CashImageFrame", "5DollorFrame"},
        {100, "CashImageFrame", "1DollorFrame"},
        {50, "CoinImageFrame", "50PennyFrame"},
        {25, "CoinImageFrame", "25PennyFrame"},
        {10, "CoinImageFrame", "10PennyFrame"},
        {5, "CoinImageFrame", "5PennyFrame"},
        {1, "CoinImageFrame", "1PennyFrame"},
    }

    local function finishPayment(current, token)
        local timing = current.kind == "Cash" and CASH_CLICK or FAST_CLICK
        local frame = at(paymentGui, "PaymentMethod", current.kind == "Cash" and "CashFrame" or "CardFrame")
        local deadline = os.clock() + 4
        while not shown(frame) and os.clock() < deadline do check(token); task.wait(0.05) end
        if not shown(frame) then error("Interface de pagamento não abriu.", 0) end
        check(token)
        if transaction ~= current then error("O pagamento mudou durante o atendimento.", 0) end

        -- A clear click establishes a fresh keypad/change selection before entering values.
        click(at(frame, "OperationFrame", "ClearBtn"), token, timing)
        if current.kind == "Card" then
            local valueLabel = at(frame, "TotalFrame", "NumberText")
            if not valueLabel or tonumber(valueLabel.Text) ~= 0 then error("O teclado do cartão não foi zerado.", 0) end
            local amount = string.format("%.2f", current.total / 100):gsub("%.00$", "")
            report("Cartão: preenchendo $" .. string.format("%.2f", current.total / 100))
            for index = 1, #amount do
                if transaction ~= current or not shown(frame) then error("Pagamento alterado durante a digitação.", 0) end
                local digit = amount:sub(index, index)
                click(at(frame, "NumberFrame", digit == "." and "BtnPoint" or "Btn" .. digit), token)
            end
            if cents(tonumber(valueLabel.Text)) ~= current.total then error("O valor exibido no cartão não corresponde ao total.", 0) end
        else
            local change = current.paid - current.total
            local remaining = change
            local plan = {}
            for _, denomination in ipairs(denominations) do
                local quantity = math.floor(remaining / denomination[1])
                remaining = remaining - quantity * denomination[1]
                if #plan + quantity > 80 then error("Troco exige mais de 80 cliques; conclua manualmente.", 0) end
                for _ = 1, quantity do table.insert(plan, denomination) end
            end
            if remaining ~= 0 then error("Não foi possível representar o troco.", 0) end
            report(string.format("Dinheiro: total $%.2f; recebido $%.2f; troco $%.2f (%d cliques).",
                current.total / 100, current.paid / 100, change / 100, #plan))
            for _, denomination in ipairs(plan) do
                if transaction ~= current or not shown(frame) then error("Pagamento alterado durante o troco.", 0) end
                click(at(frame, denomination[2], denomination[3], "ImageButton"), token, CASH_CLICK)
            end
        end
        check(token)
        if transaction ~= current or not shown(frame) then error("Pagamento mudou antes da confirmação.", 0) end
        click(at(frame, "OperationFrame", "OKBtn"), token, timing)
        deadline = os.clock() + 4
        while shown(frame) and os.clock() < deadline do check(token); task.wait(0.1) end
        if shown(frame) then error("A interface não encerrou o pagamento. Confira o caixa manualmente.", 0) end
        if transaction == current then transaction = nil end
        report("Interface de pagamento fechada; aguardando próximo cliente.")
        task.wait(0.2)
    end

    local mouse = player:GetMouse()
    local aimOffsets = {
        Vector3.zero,
        Vector3.new(0.35, 0, 0), Vector3.new(-0.35, 0, 0),
        Vector3.new(0, 0, 0.35), Vector3.new(0, 0, -0.35),
        Vector3.new(0, 0.35, 0), Vector3.new(0, -0.35, 0),
        Vector3.new(0.3, 0, 0.3), Vector3.new(-0.3, 0, -0.3),
    }
    -- Confirmed manual scan locations, deduplicated within 0.12 stud.
    -- Store detector-local fractions instead of pixels; project with the current camera.
    local conveyorPoints = {
        Vector3.new(0.093780517578, 0.500000000000, -0.181039866032),
        Vector3.new(0.136260986328, 0.499999937208, -0.171740831662),
        Vector3.new(0.174148559570, 0.500000000000, -0.161198395084),
        Vector3.new(0.214569091797, 0.500000000000, -0.173322197149),
        Vector3.new(0.256469726562, 0.500000000000, -0.143856339125),
        Vector3.new(0.285644531250, 0.500000000000, -0.111810358464),
        Vector3.new(0.151367187500, 0.500000000000, -0.106695511244),
        Vector3.new(0.115142822266, 0.500000000000, -0.121202711052),
        Vector3.new(0.092010498047, 0.500000000000, -0.105051092907),
        Vector3.new(0.137817382812, 0.500000000000, -0.194871139284),
        Vector3.new(0.310241699219, 0.499999937208, -0.190157308192),
        Vector3.new(0.343673706055, 0.500000000000, -0.194364194367),
        Vector3.new(0.428649902344, 0.500000000000, -0.160350964776),
        Vector3.new(0.496093750000, 0.500000000000, -0.135576238817),
    }
    local function resetConveyorSweep()
        conveyorCursor = 1
        table.clear(pendingScans)
    end
    local function takeConveyorPoint()
        local offset = conveyorPoints[conveyorCursor]
        conveyorCursor = conveyorCursor % #conveyorPoints + 1
        return offset
    end
    local CONVEYOR_CLICK = { hold = 0.045, gap = 0 }
    local SCAN_INTERVAL = 0.12
    local SCAN_RESPONSE_TIMEOUT = 0.65
    local MAX_PENDING_SCANS = 3
    local function movePointer(position)
        if driverKind == "VirtualInput" then driver:SendMousePosition(position)
        else driver:SendMouseMoveEvent(position.X, position.Y, game) end
    end

    local function clickWorldPart(part, token, allowedModel)
        check(token)
        if transaction or not mouseIdle() or not part or not part.Parent or not part:IsA("BasePart") then return false end
        local isProductDetector = part == detector and allowedModel == nil
        if not isProductDetector then
            if not allowedModel or (allowedModel.Name ~= "CashModel" and allowedModel.Name ~= "CardModel") then return false end
            if not part:IsDescendantOf(allowedModel) then return false end
        end
        local camera = workspace.CurrentCamera
        if not camera then return false end
        -- Generate only points actually visited; do not skip the rest of a prefetched batch.
        for candidate = 1, (isProductDetector and 6 or #aimOffsets) do
            check(token)
            if transaction or not mouseIdle() or not part.Parent then return false end
            local offset = isProductDetector and takeConveyorPoint() or aimOffsets[candidate]
            local worldPoint = part.CFrame:PointToWorldSpace(part.Size * offset)
            local point, onScreen = camera:WorldToViewportPoint(worldPoint)
            local size = camera.ViewportSize
            if onScreen and point.Z > 0 and point.X > 2 and point.Y > 60
                and point.X < size.X - 2 and point.Y < size.Y - 2 then
                local position = Vector2.new(point.X, point.Y)
                movePointer(position)
                -- Let the game update Mouse.Target and hover handlers before pressing.
                task.wait(isProductDetector and 0.025 or 0.08)
                check(token)
                if transaction or not mouseIdle() then return false end
                local target = mouse.Target
                if target == part or (target and allowedModel and target:IsDescendantOf(allowedModel)) then
                    -- Reserve before press: the server can answer while press yields.
                    local pending
                    if isProductDetector then
                        if #pendingScans >= MAX_PENDING_SCANS then return false end
                        pending = { sentAt = os.clock() }
                        table.insert(pendingScans, pending)
                        nextScanAt = math.max(nextScanAt, pending.sentAt + SCAN_INTERVAL)
                    end
                    local clicked = press(position, token, isProductDetector and CONVEYOR_CLICK or FAST_CLICK)
                    if pending and not clicked then
                        local index = table.find(pendingScans, pending)
                        if index then table.remove(pendingScans, index) end
                    end
                    if clicked and isProductDetector then return true, offset end
                    return clicked
                end
            end
        end
        return false
    end

    local function scanConveyor(token)
        if transaction or not mouseIdle() or os.clock() < nextScanAt then return false end
        local now = os.clock()
        while pendingScans[1] and now - pendingScans[1].sentAt >= SCAN_RESPONSE_TIMEOUT do
            table.remove(pendingScans, 1)
            scanMisses = math.min(scanMisses + 1, #conveyorPoints)
        end
        if #pendingScans >= MAX_PENDING_SCANS then return false end
        -- Keep a bounded sequence in flight, rather than waiting after each product.
        nextScanAt = now + (scanMisses >= #conveyorPoints and 0.3 or SCAN_INTERVAL)
        local clicked = clickWorldPart(detector, token, nil)
        if transaction then return true end
        if clicked then return true end -- Sent is not the same as registered.
        check(token)
        nextScanAt = os.clock() + 0.25
        return false
    end

    local function offeredPayment()
        local customers = at(workspace, "Resources", "Customer")
        if not customers then return nil end
        -- Restrict the search to the nearest customer, rather than another checkout's queue.
        local nearest, distance = nil, 12
        for _, customer in ipairs(customers:GetChildren()) do
            local root = customer:FindFirstChild("HumanoidRootPart") or customer:FindFirstChild("Head")
            if root and root:IsA("BasePart") then
                local delta = (root.Position - detector.Position).Magnitude
                if delta < distance then nearest, distance = customer, delta end
            end
        end
        if not nearest then return nil end
        local offers = {}
        for _, model in ipairs(nearest:GetDescendants()) do
            if model.Name == "CashModel" or model.Name == "CardModel" then
                local part = model and model:FindFirstChild("PP", true)
                local visibleParts = {}
                for _, object in ipairs(model:GetDescendants()) do
                    if object:IsA("BasePart") and object.Transparency < 0.95
                        and object.LocalTransparencyModifier < 0.95 then
                        table.insert(visibleParts, object)
                    end
                end
                if #visibleParts > 0 then
                    -- PP is the observed cash target; visible parts handle an offset pivot.
                    if part and part:IsA("BasePart") then
                        table.insert(offers, { part = part, model = model })
                    end
                    for index = 1, math.min(#visibleParts, 6) do
                        if visibleParts[index] ~= part then
                            table.insert(offers, { part = visibleParts[index], model = model })
                        end
                    end
                end
            end
        end
        return offers
    end

    local function collectOfferedPayment(token)
        -- Yield immediately to repeated manual clicks; never click the product detector.
        if not mouseIdle() then return end
        local offers = offeredPayment()
        if not offers then return end
        for _, offer in ipairs(offers) do
            check(token)
            if transaction or not mouseIdle() then return end
            if clickWorldPart(offer.part, token, offer.model) then
                report("Clicando no pagamento oferecido: " .. offer.model.Name)
                local deadline = os.clock() + 1.5
                repeat
                    check(token)
                    if transaction or not mouseIdle() then return end
                    task.wait(0.05)
                until os.clock() >= deadline
                return -- Wait for the next cycle before another attempt.
            end
        end
    end

    local function start()
        paymentGui = playerGui:FindFirstChild("PaymentGui")
        paymentRoot = at(ReplicatedStorage, "Events", "Payment")
        local methodEvent = paymentRoot and paymentRoot:FindFirstChild("PaymentMethodRE")
        local scanEvent = paymentRoot and paymentRoot:FindFirstChild("ScanGoodsRE")
        if not paymentGui or not methodEvent or not scanEvent or not shown(at(paymentGui, "Leave")) then
            report("Assuma o caixa antes de ativar."); return
        end
        if shown(at(paymentGui, "PaymentMethod", "CashFrame")) or shown(at(paymentGui, "PaymentMethod", "CardFrame")) then
            report("Conclua o pagamento atual; ative antes da próxima venda."); return
        end
        local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
        local building = at(workspace, "Resources", "Building")
        desk, detector = nil, nil
        local distance = 16
        if root and building then
            for _, candidate in ipairs(building:GetChildren()) do
                if candidate.Name == "CashierDesk" then
                    local part = at(candidate, "DetectorFolder", "Part")
                    if part and part:IsA("BasePart") then
                        local delta = (part.Position - root.Position).Magnitude
                        if delta < distance then desk, detector, distance = candidate, part, delta end
                    end
                end
            end
        end
        if not detector then report("Detector do caixa não encontrado próximo ao jogador."); return end
        local ok, value = pcall(function() return UIS:CreateVirtualInput() end)
        if ok and value then driver, driverKind = value, "VirtualInput"
        else
            ok, value = pcall(function() return game:GetService("VirtualInputManager") end)
            if not ok or not value then report("Entrada virtual indisponível neste ambiente."); return end
            driver, driverKind = value, "VirtualInputManager"
        end
        generation = generation + 1
        local token = generation
        active = true
        transaction = nil
        eventSerial = 0
        scanSerial, scanMisses, nextScanAt = 0, 0, 0
        resetConveyorSweep()
        lastManualClick = os.clock()
        paint()
        table.insert(paymentConnections, scanEvent.OnClientEvent:Connect(function(product, price)
            if not active then return end
            eventSerial = eventSerial + 1
            scanSerial = scanSerial + 1
            scanMisses = 0
            -- Events have no click ID; this bounds activity, not per-click attribution.
            if pendingScans[1] then table.remove(pendingScans, 1) end
            report("Produto registrado: " .. tostring(product) .. " ($" .. tostring(price) .. ")")
        end))
        table.insert(paymentConnections, methodEvent.OnClientEvent:Connect(function(kind, total, paid)
            if not active then return end
            local totalCents = cents(total)
            local paidCents = kind == "Cash" and cents(paid) or nil
            if (kind ~= "Cash" and kind ~= "Card") or not totalCents
                or (kind == "Cash" and (not paidCents or paidCents < totalCents)) then
                stop("Pagamento recebido com valores não reconhecidos."); return
            end
            if transaction then stop("Novo pagamento durante uma operação; confira o caixa."); return end
            transactionSerial = transactionSerial + 1
            transaction = { id = transactionSerial, kind = kind, total = totalCents, paid = paidCents }
            table.clear(pendingScans)
            eventSerial = eventSerial + 1
        end))
        gui.Enabled = false
        report("Atendimento completo ligado. Deixe esteira e mão do NPC visíveis e solte o mouse. F8 pausa.")
        task.spawn(function()
            local success, reason = pcall(function()
                while active and generation == token and state.alive do
                    check(token)
                    if transaction then
                        finishPayment(transaction, token)
                        check(token)
                        scanMisses, nextScanAt = 0, os.clock() + 0.35
                        resetConveyorSweep()
                    else
                        local sent = scanConveyor(token)
                        if not transaction and not sent and mouseIdle() then
                            collectOfferedPayment(token)
                        end
                        task.wait(0.025)
                    end
                end
            end)
            if not success and active and generation == token then stop(tostring(reason)) end
        end)
    end

    connect(autoToggle.Activated, function()
        if active then stop("Atendimento desligado.") else
            local ok, reason = pcall(start)
            if not ok then
                if active then stop(tostring(reason)) else report("Falha ao iniciar: " .. tostring(reason)) end
            end
        end
    end)
    connect(UIS.InputBegan, function(input)
        if input.KeyCode == Enum.KeyCode.F8 and active then stop("Atendimento interrompido por F8.") end
    end)
    return { stop = stop, running = function() return active end }
end)()


if player.Character then bindCharacter(player.Character) end
if state.humanoid then
    state.speed = math.clamp(math.floor(state.humanoid.WalkSpeed + 0.5), MIN_SPEED, MAX_SPEED)
end
selectTab("Movimento")
refreshSpeed()
refreshKey()
resize()
task.defer(function() if state.alive then resize() end end)
print("[Zyon] Menu v1.14 carregado. Esteira rápida com até 3 cliques pendentes. F8 interrompe.")
