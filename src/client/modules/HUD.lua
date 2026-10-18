--[[
	HUD.lua  (cliente)
	Construye TODA la interfaz por codigo: menu del lobby, HUD de la
	partida, avisos, panel de resultados y brujula del rastreador.

	Nada de esto necesita que armes GUIs en Studio.
--]]

local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")
local Debris = game:GetService("Debris")

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("KiwiShared")
local Config = require(Shared.Config)
local Util = require(Shared.Util)

local HUD = {}

local player = Players.LocalPlayer
local gui
local parts = {}
local tracker = { active = false, until_ = 0, pos = nil, hidden = false }
local callbacks = {}

local COLOR = {
	panel = Color3.fromRGB(14, 16, 20),
	panelSoft = Color3.fromRGB(26, 30, 36),
	accent = Color3.fromRGB(102, 209, 130),
	text = Color3.fromRGB(238, 241, 244),
	muted = Color3.fromRGB(148, 156, 164),
}

local function new(className, props, parent)
	local instance = Instance.new(className)
	for key, value in pairs(props or {}) do
		instance[key] = value
	end
	if parent then
		instance.Parent = parent
	end
	return instance
end

local function corner(radius, parent)
	return new("UICorner", { CornerRadius = UDim.new(0, radius) }, parent)
end

local function stroke(color, thickness, transparency, parent)
	return new("UIStroke", {
		Color = color,
		Thickness = thickness or 1,
		Transparency = transparency or 0.4,
		ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
	}, parent)
end

local function padding(px, parent)
	return new("UIPadding", {
		PaddingTop = UDim.new(0, px),
		PaddingBottom = UDim.new(0, px),
		PaddingLeft = UDim.new(0, px),
		PaddingRight = UDim.new(0, px),
	}, parent)
end

-- ===============================================================
-- MENU DEL LOBBY
-- ===============================================================
local function buildMenu(parent)
	local menu = new("Frame", {
		Name = "Menu",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.new(0, 660, 0, 690),
		BackgroundColor3 = COLOR.panel,
		BackgroundTransparency = 0.08,
		BorderSizePixel = 0,
	}, parent)
	corner(18, menu)
	stroke(COLOR.accent, 1.5, 0.45, menu)
	padding(22, menu)

	new("TextLabel", {
		Name = "Titulo",
		Size = UDim2.new(1, 0, 0, 44),
		BackgroundTransparency = 1,
		Font = Enum.Font.GothamBlack,
		TextScaled = true,
		TextColor3 = COLOR.text,
		Text = "KIWI CAZADOR",
	}, menu)

	new("TextLabel", {
		Name = "Subtitulo",
		Position = UDim2.new(0, 0, 0, 48),
		Size = UDim2.new(1, 0, 0, 22),
		BackgroundTransparency = 1,
		Font = Enum.Font.Gotham,
		TextSize = 15,
		TextColor3 = COLOR.muted,
		Text = "Atrapa al kiwi de Nueva Zelanda antes de que se esconda otra vez",
	}, menu)

	local grid = new("Frame", {
		Name = "Modos",
		Position = UDim2.new(0, 0, 0, 82),
		Size = UDim2.new(1, 0, 0, 384),
		BackgroundTransparency = 1,
	}, menu)

	new("UIGridLayout", {
		CellSize = UDim2.new(0.485, 0, 0, 118),
		CellPadding = UDim2.new(0.03, 0, 0, 12),
		SortOrder = Enum.SortOrder.LayoutOrder,
	}, grid)

	parts.modeButtons = {}
	for index, modeId in ipairs(Config.ModeOrder) do
		local info
		if modeId == "multi" then
			info = Config.Multiplayer
		else
			info = Config.Difficulties[modeId]
		end

		local button = new("TextButton", {
			Name = modeId,
			LayoutOrder = index,
			BackgroundColor3 = COLOR.panelSoft,
			BackgroundTransparency = 0.05,
			BorderSizePixel = 0,
			AutoButtonColor = false,
			Text = "",
		}, grid)
		corner(12, button)
		local border = stroke(info.color, 1.5, 0.35, button)

		new("TextLabel", {
			Name = "Nombre",
			Position = UDim2.new(0, 14, 0, 10),
			Size = UDim2.new(1, -28, 0, 24),
			BackgroundTransparency = 1,
			Font = Enum.Font.GothamBold,
			TextSize = 19,
			TextXAlignment = Enum.TextXAlignment.Left,
			TextColor3 = info.color,
			Text = info.name,
		}, button)

		new("TextLabel", {
			Name = "Etiqueta",
			Position = UDim2.new(0, 14, 0, 34),
			Size = UDim2.new(1, -28, 0, 18),
			BackgroundTransparency = 1,
			Font = Enum.Font.Gotham,
			TextSize = 12,
			TextXAlignment = Enum.TextXAlignment.Left,
			TextColor3 = COLOR.muted,
			Text = info.tag,
		}, button)

		new("TextLabel", {
			Name = "Descripcion",
			Position = UDim2.new(0, 14, 0, 52),
			Size = UDim2.new(1, -28, 0, 56),
			BackgroundTransparency = 1,
			Font = Enum.Font.Gotham,
			TextSize = 13,
			TextWrapped = true,
			TextXAlignment = Enum.TextXAlignment.Left,
			TextYAlignment = Enum.TextYAlignment.Top,
			TextColor3 = COLOR.text,
			TextTransparency = 0.15,
			Text = info.blurb,
		}, button)

		if callbacks.onJoin then
			button.MouseButton1Click:Connect(function()
				callbacks.onJoin(modeId)
			end)
		end
		button.MouseEnter:Connect(function()
			TweenService:Create(button, TweenInfo.new(0.15), { BackgroundColor3 = Color3.fromRGB(40, 46, 54) }):Play()
		end)
		button.MouseLeave:Connect(function()
			TweenService:Create(button, TweenInfo.new(0.15), { BackgroundColor3 = COLOR.panelSoft }):Play()
		end)

		parts.modeButtons[modeId] = { button = button, border = border }
	end

	local status = new("TextLabel", {
		Name = "Estado",
		Position = UDim2.new(0, 0, 0, 470),
		Size = UDim2.new(1, 0, 0, 22),
		BackgroundTransparency = 1,
		Font = Enum.Font.GothamMedium,
		TextSize = 14,
		TextColor3 = COLOR.accent,
		Text = "",
	}, menu)
	parts.status = status

	local help = new("Frame", {
		Name = "Ayuda",
		Position = UDim2.new(0, 0, 0, 498),
		Size = UDim2.new(1, 0, 0, 138),
		BackgroundColor3 = COLOR.panelSoft,
		BackgroundTransparency = 0.35,
		BorderSizePixel = 0,
	}, menu)
	corner(12, help)
	padding(14, help)

	new("TextLabel", {
		Size = UDim2.new(1, 0, 0, 18),
		BackgroundTransparency = 1,
		Font = Enum.Font.GothamBold,
		TextSize = 14,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextColor3 = COLOR.accent,
		Text = "CÓMO JUGAR",
	}, help)

	new("TextLabel", {
		Position = UDim2.new(0, 0, 0, 22),
		Size = UDim2.new(1, 0, 1, -22),
		BackgroundTransparency = 1,
		Font = Enum.Font.Gotham,
		TextSize = 13,
		TextWrapped = true,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextYAlignment = Enum.TextYAlignment.Top,
		TextColor3 = COLOR.text,
		TextTransparency = 0.2,
		Text = "1) Red: atrapa al kiwi de cerca.\n"
			.. "2) Rifle tranquilizante: clic derecho para apuntar con la mira; lo duerme y lo recoges al tocarlo.\n"
			.. "3) Rastreador: te dice dirección y distancia.\n"
			.. "4) Trampa de fruta (1 por jugador): el kiwi queda atrapado 3 s; ve por él o disparale.\n"
			.. "5) Rifle de pintura: mancha, marca (se ve entre las paredes) y frena. Clic derecho: mira.\n"
			.. "En Kiwi Colosal llevas rastreador y rifle ralentizador (frena al gigante, no lo duerme).\n"
			.. "V: vista en primera persona. Caminar despacio (Ctrl) hace menos ruido. Correr (Shift) lo espanta.",
	}, help)

	return menu
end

-- ===============================================================
-- HUD DE PARTIDA
-- ===============================================================
local function buildSessionHud(parent)
	local hud = new("Frame", {
		Name = "Partida",
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		Visible = false,
	}, parent)
	parts.hud = hud

	-- Barra superior
	local top = new("Frame", {
		Name = "Barra",
		Position = UDim2.new(0, 0, 0, 10),
		Size = UDim2.new(1, -20, 0, 64),
		BackgroundColor3 = COLOR.panel,
		BackgroundTransparency = 0.2,
		BorderSizePixel = 0,
	}, hud)
	parts.hud = hud
	corner(14, top)
	stroke(Color3.fromRGB(60, 70, 80), 1, 0.5, top)

	local modeLabel = new("TextLabel", {
		Name = "Modo",
		Position = UDim2.new(0, 16, 0, 8),
		Size = UDim2.new(0, 260, 0, 22),
		BackgroundTransparency = 1,
		Font = Enum.Font.GothamBold,
		TextSize = 18,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextColor3 = COLOR.accent,
		Text = "",
	}, top)
	parts.modeLabel = modeLabel

	local arenaLabel = new("TextLabel", {
		Name = "Arena",
		Position = UDim2.new(0, 16, 0, 32),
		Size = UDim2.new(0, 300, 0, 20),
		BackgroundTransparency = 1,
		Font = Enum.Font.Gotham,
		TextSize = 13,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextColor3 = COLOR.muted,
		Text = "",
	}, top)
	parts.arenaLabel = arenaLabel

	local objective = new("TextLabel", {
		Name = "Objetivo",
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 10),
		Size = UDim2.new(0, 320, 0, 24),
		BackgroundTransparency = 1,
		Font = Enum.Font.GothamMedium,
		TextSize = 16,
		TextColor3 = COLOR.text,
		Text = "",
	}, top)
	parts.objective = objective

	local progress = new("TextLabel", {
		Name = "Progreso",
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 34),
		Size = UDim2.new(0, 320, 0, 20),
		BackgroundTransparency = 1,
		Font = Enum.Font.GothamBold,
		TextSize = 15,
		TextColor3 = COLOR.accent,
		Text = "",
	}, top)
	parts.progress = progress

	local timer = new("TextLabel", {
		Name = "Reloj",
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -16, 0, 8),
		Size = UDim2.new(0, 120, 0, 30),
		BackgroundTransparency = 1,
		Font = Enum.Font.GothamBlack,
		TextSize = 26,
		TextXAlignment = Enum.TextXAlignment.Right,
		TextColor3 = COLOR.text,
		Text = "0:00",
	}, top)
	parts.timer = timer

	local leave = new("TextButton", {
		Name = "Salir",
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -16, 0, 40),
		Size = UDim2.new(0, 90, 0, 22),
		BackgroundColor3 = Color3.fromRGB(70, 40, 40),
		BorderSizePixel = 0,
		AutoButtonColor = true,
		Font = Enum.Font.GothamMedium,
		TextSize = 13,
		TextColor3 = COLOR.text,
		Text = "Salir",
	}, top)
	corner(8, leave)
	leave.MouseButton1Click:Connect(function()
		if callbacks.onLeave then
			callbacks.onLeave()
		end
	end)

	-- Panel lateral: estado del kiwi, marcador y herramientas
	local side = new("Frame", {
		Name = "Lateral",
		Position = UDim2.new(1, -230, 0, 84),
		Size = UDim2.new(0, 220, 0, 320),
		BackgroundTransparency = 1,
	}, hud)

	local kiwiState = new("Frame", {
		Name = "EstadoKiwi",
		Size = UDim2.new(1, 0, 0, 46),
		BackgroundColor3 = COLOR.panel,
		BackgroundTransparency = 0.2,
		BorderSizePixel = 0,
	}, side)
	corner(12, kiwiState)
	padding(10, kiwiState)
	local kiwiLabel = new("TextLabel", {
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		Font = Enum.Font.GothamBold,
		TextScaled = true,
		TextColor3 = COLOR.text,
		Text = "El kiwi: ?",
	}, kiwiState)
	parts.kiwiLabel = kiwiLabel

	local score = new("Frame", {
		Name = "Marcador",
		Position = UDim2.new(0, 0, 0, 56),
		Size = UDim2.new(1, 0, 0, 96),
		BackgroundColor3 = COLOR.panel,
		BackgroundTransparency = 0.2,
		BorderSizePixel = 0,
	}, side)
	corner(12, score)
	padding(10, score)
	new("TextLabel", {
		Name = "Titulo",
		Size = UDim2.new(1, 0, 0, 16),
		BackgroundTransparency = 1,
		Font = Enum.Font.GothamBold,
		TextSize = 12,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextColor3 = COLOR.muted,
		Text = "CAZADORES",
	}, score)
	local scoreList = new("Frame", {
		Name = "Lista",
		Position = UDim2.new(0, 0, 0, 18),
		Size = UDim2.new(1, 0, 1, -18),
		BackgroundTransparency = 1,
	}, score)
	new("UIListLayout", {
		SortOrder = Enum.SortOrder.LayoutOrder,
		Padding = UDim.new(0, 2),
	}, scoreList)
	parts.scoreList = scoreList

	local tools = new("Frame", {
		Name = "Herramientas",
		Position = UDim2.new(0, 0, 0, 162),
		Size = UDim2.new(1, 0, 0, 130),
		BackgroundTransparency = 1,
	}, side)
	new("UIListLayout", {
		SortOrder = Enum.SortOrder.LayoutOrder,
		Padding = UDim.new(0, 4),
	}, tools)
	parts.toolChips = {}
	for index, toolId in ipairs(Config.Tools.order) do
		local info = Config.Tools[toolId]
		local chip = new("Frame", {
			Name = toolId,
			LayoutOrder = index,
			Size = UDim2.new(1, 0, 0, 22),
			BackgroundColor3 = COLOR.panel,
			BackgroundTransparency = 0.25,
			BorderSizePixel = 0,
		}, tools)
		corner(6, chip)
		local name = new("TextLabel", {
			Name = "Nombre",
			Position = UDim2.new(0, 8, 0, 0),
			Size = UDim2.new(1, -70, 1, 0),
			BackgroundTransparency = 1,
			Font = Enum.Font.GothamMedium,
			TextSize = 12,
			TextXAlignment = Enum.TextXAlignment.Left,
			TextColor3 = info.color,
			Text = info.name,
		}, chip)
		local state = new("TextLabel", {
			Name = "Estado",
			AnchorPoint = Vector2.new(1, 0.5),
			Position = UDim2.new(1, -8, 0.5, 0),
			Size = UDim2.new(0, 60, 1, 0),
			BackgroundTransparency = 1,
			Font = Enum.Font.GothamBold,
			TextSize = 12,
			TextXAlignment = Enum.TextXAlignment.Right,
			TextColor3 = COLOR.muted,
			Text = "Listo",
		}, chip)
		local fill = new("Frame", {
			Name = "Carga",
			Position = UDim2.new(0, 0, 1, -3),
			Size = UDim2.new(1, 0, 0, 3),
			BackgroundColor3 = info.color,
			BorderSizePixel = 0,
		}, chip)
		parts.toolChips[toolId] = { chip = chip, state = state, fill = fill }
		parts.toolChips[toolId].name = name
	end

	-- Brujula del rastreador
	local compass = new("Frame", {
		Name = "Brujula",
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 100),
		Size = UDim2.new(0, 150, 0, 150),
		BackgroundTransparency = 1,
		Visible = false,
	}, hud)
	parts.compass = compass

	local ring = new("Frame", {
		Name = "Anillo",
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = COLOR.panel,
		BackgroundTransparency = 0.18,
		BorderSizePixel = 0,
	}, compass)
	corner(999, ring)
	stroke(COLOR.accent, 2, 0.25, ring)

	-- Rosa de los vientos: las letras y marcas giran con la camara
	local marks = {}
	for _, entry in ipairs({ { "N", 0 }, { "E", 90 }, { "S", 180 }, { "O", 270 } }) do
		local label = new("TextLabel", {
			Name = "Cardinal" .. entry[1],
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.5, 0.5),
			Size = UDim2.new(0, 18, 0, 16),
			BackgroundTransparency = 1,
			Font = Enum.Font.GothamBold,
			TextSize = 13,
			TextColor3 = entry[1] == "N" and Color3.fromRGB(232, 108, 100) or COLOR.text,
			Text = entry[1],
		}, ring)
		table.insert(marks, { gui = label, azimuth = entry[2] })
	end
	for _, azimuth in ipairs({ 45, 135, 225, 315 }) do
		local tick = new("Frame", {
			Name = "Marca" .. azimuth,
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.5, 0.5),
			Size = UDim2.new(0, 3, 0, 10),
			BackgroundColor3 = COLOR.muted,
			BorderSizePixel = 0,
		}, ring)
		table.insert(marks, { gui = tick, azimuth = azimuth })
	end
	parts.compassMarks = marks

	local needle = new("Frame", {
		Name = "Aguja",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.new(0, 8, 0, 84),
		BackgroundColor3 = Color3.fromRGB(158, 165, 174),
		BorderSizePixel = 0,
		Rotation = 0,
	}, ring)
	corner(4, needle)
	local tip = new("Frame", {
		Name = "Punta",
		Size = UDim2.new(1, 0, 0, 24),
		BackgroundColor3 = COLOR.accent,
		BorderSizePixel = 0,
	}, needle)
	corner(4, tip)
	parts.needle = needle
	parts.needleTip = tip

	local hub = new("Frame", {
		Name = "Centro",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.new(0, 12, 0, 12),
		BackgroundColor3 = Color3.fromRGB(30, 36, 44),
		BorderSizePixel = 0,
	}, ring)
	corner(999, hub)

	local distanceLabel = new("TextLabel", {
		Name = "Distancia",
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 1, 8),
		Size = UDim2.new(1, 40, 0, 22),
		BackgroundTransparency = 1,
		Font = Enum.Font.GothamBold,
		TextSize = 16,
		TextColor3 = COLOR.accent,
		Text = "",
	}, compass)
	parts.compassDistance = distanceLabel

	return hud
end

-- ===============================================================
-- MIRA DEL RIFLE TRANQUILIZANTE (clic derecho)
-- ===============================================================
local function buildScope(parent)
	local scope = new("Frame", {
		Name = "Mira",
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		Visible = false,
		ZIndex = 20,
	}, parent)
	parts.scope = scope

	local ring = new("Frame", {
		Name = "Anillo",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.new(0, 180, 0, 180),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
	}, scope)
	corner(999, ring)
	stroke(Color3.fromRGB(235, 240, 245), 1.5, 0.25, ring)

	local function tick(name, size, position)
		new("Frame", {
			Name = name,
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = position,
			Size = size,
			BackgroundColor3 = Color3.fromRGB(235, 240, 245),
			BackgroundTransparency = 0.15,
			BorderSizePixel = 0,
		}, ring)
	end

	tick("Arriba", UDim2.new(0, 1.5, 0, 30), UDim2.new(0.5, 0, 0.5, -70))
	tick("Abajo", UDim2.new(0, 1.5, 0, 30), UDim2.new(0.5, 0, 0.5, 70))
	tick("Izquierda", UDim2.new(0, 30, 0, 1.5), UDim2.new(0.5, -70, 0.5, 0))
	tick("Derecha", UDim2.new(0, 30, 0, 1.5), UDim2.new(0.5, 70, 0.5, 0))

	local dot = new("Frame", {
		Name = "Punto",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.new(0, 3, 0, 3),
		BackgroundColor3 = Color3.fromRGB(235, 240, 245),
		BackgroundTransparency = 0.05,
		BorderSizePixel = 0,
	}, ring)
	corner(999, dot)

	new("TextLabel", {
		Name = "Etiqueta",
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0.5, 100),
		Size = UDim2.new(0, 260, 0, 16),
		BackgroundTransparency = 1,
		Font = Enum.Font.GothamBold,
		TextSize = 11,
		TextColor3 = Color3.fromRGB(200, 210, 220),
		TextTransparency = 0.25,
		Text = "MIRA - clic derecho para salir",
	}, scope)

	return scope
end

-- ===============================================================
-- AVISOS Y RESULTADOS
-- ===============================================================
local function buildNotices(parent)
	local holder = new("Frame", {
		Name = "Avisos",
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 82),
		Size = UDim2.new(0, 420, 0, 200),
		BackgroundTransparency = 1,
	}, parent)
	new("UIListLayout", {
		SortOrder = Enum.SortOrder.LayoutOrder,
		Padding = UDim.new(0, 6),
		HorizontalAlignment = Enum.HorizontalAlignment.Center,
	}, holder)
	parts.noticeHolder = holder
	parts.noticeCount = 0
	return holder
end

local function buildResult(parent)
	local result = new("Frame", {
		Name = "Resultado",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.new(0, 460, 0, 330),
		BackgroundColor3 = COLOR.panel,
		BackgroundTransparency = 0.05,
		BorderSizePixel = 0,
		Visible = false,
	}, parent)
	corner(18, result)
	local resultBorder = stroke(COLOR.accent, 2, 0.35, result)
	padding(24, result)
	parts.result = result
	parts.resultBorder = resultBorder

	local title = new("TextLabel", {
		Size = UDim2.new(1, 0, 0, 40),
		BackgroundTransparency = 1,
		Font = Enum.Font.GothamBlack,
		TextScaled = true,
		TextColor3 = COLOR.accent,
		Text = "",
	}, result)
	parts.resultTitle = title

	local subtitle = new("TextLabel", {
		Position = UDim2.new(0, 0, 0, 46),
		Size = UDim2.new(1, 0, 0, 40),
		BackgroundTransparency = 1,
		Font = Enum.Font.Gotham,
		TextSize = 15,
		TextWrapped = true,
		TextColor3 = COLOR.text,
		TextTransparency = 0.15,
		Text = "",
	}, result)
	parts.resultSubtitle = subtitle

	local lines = new("TextLabel", {
		Position = UDim2.new(0, 0, 0, 94),
		Size = UDim2.new(1, 0, 0, 70),
		BackgroundTransparency = 1,
		Font = Enum.Font.GothamMedium,
		TextSize = 15,
		TextYAlignment = Enum.TextYAlignment.Top,
		TextColor3 = COLOR.text,
		Text = "",
	}, result)
	parts.resultLines = lines

	local rankingTitle = new("TextLabel", {
		Position = UDim2.new(0, 0, 0, 168),
		Size = UDim2.new(1, 0, 0, 18),
		BackgroundTransparency = 1,
		Font = Enum.Font.GothamBold,
		TextSize = 13,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextColor3 = COLOR.muted,
		Text = "TABLA",
	}, result)

	local ranking = new("Frame", {
		Position = UDim2.new(0, 0, 0, 190),
		Size = UDim2.new(1, 0, 0, 110),
		BackgroundTransparency = 1,
	}, result)
	new("UIListLayout", {
		SortOrder = Enum.SortOrder.LayoutOrder,
		Padding = UDim.new(0, 3),
	}, ranking)
	parts.resultRanking = ranking
	parts.resultRankingTitle = rankingTitle

	local footer = new("TextLabel", {
		Position = UDim2.new(0, 0, 1, -22),
		Size = UDim2.new(1, 0, 0, 20),
		BackgroundTransparency = 1,
		Font = Enum.Font.Gotham,
		TextSize = 13,
		TextColor3 = COLOR.muted,
		Text = "",
	}, result)
	parts.resultFooter = footer

	return result
end

-- ===============================================================
-- API
-- ===============================================================
function HUD.init(playerGui, handlers)
	callbacks = handlers or {}
	if parts.screen then
		parts.screen:Destroy()
	end

	local screen = new("ScreenGui", {
		Name = "KiwiCazador",
		ResetOnSpawn = false,
		IgnoreGuiInset = true,
		ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
	}, playerGui)
	parts.screen = screen

	buildMenu(screen)
	buildSessionHud(screen)
	buildNotices(screen)
	buildResult(screen)
	buildScope(screen)

	local fade = new("Frame", {
		Name = "Fade",
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = Color3.fromRGB(0, 0, 0),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		ZIndex = 50,
	}, screen)
	parts.fade = fade

	return parts
end

function HUD.setMenuVisible(visible)
	if parts.screen then
		local menu = parts.screen:FindFirstChild("Menu")
		local hud = parts.screen:FindFirstChild("Partida")
		if menu then menu.Visible = visible end
		if hud then hud.Visible = not visible end
	end
	if visible then
		HUD.clearTracker()
	end
end

function HUD.setMenuStatus(text, color)
	if parts.status then
		parts.status.Text = text or ""
		parts.status.TextColor3 = color or COLOR.accent
	end
end

function HUD.notify(text, color, duration)
	local holder = parts.noticeHolder
	if not holder then
		return
	end

	parts.noticeCount = parts.noticeCount + 1
	local toast = new("Frame", {
		Name = "Aviso",
		LayoutOrder = -parts.noticeCount,
		Size = UDim2.new(1, 0, 0, 32),
		BackgroundColor3 = COLOR.panel,
		BackgroundTransparency = 0.12,
		BorderSizePixel = 0,
	}, holder)
	corner(10, toast)
	stroke(color or COLOR.accent, 1.5, 0.35, toast)

	new("TextLabel", {
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		Font = Enum.Font.GothamMedium,
		TextSize = 15,
		TextColor3 = color or COLOR.text,
		Text = text,
	}, toast)

	task.delay(duration or 4, function()
		if toast.Parent then
			local tween = TweenService:Create(toast, TweenInfo.new(0.3), { BackgroundTransparency = 1 })
			tween:Play()
			local label = toast:FindFirstChildOfClass("TextLabel")
			if label then
				TweenService:Create(label, TweenInfo.new(0.3), { TextTransparency = 1 }):Play()
			end
			local border = toast:FindFirstChildOfClass("UIStroke")
			if border then
				TweenService:Create(border, TweenInfo.new(0.3), { Transparency = 1 }):Play()
			end
			Debris:AddItem(toast, 0.35)
		end
	end)
end

function HUD.updateState(state)
	if not state or not state.active then
		HUD.setMenuVisible(true)
		HUD.setMenuStatus("")
		return
	end

	HUD.setMenuVisible(false)

	local accent = Util.colorFromTable(state.modeColor)
	if parts.modeLabel then
		parts.modeLabel.Text = state.modeName
		parts.modeLabel.TextColor3 = accent
	end
	if parts.arenaLabel then
		if state.waiting then
			parts.arenaLabel.Text = string.format("Esperando jugadores... (%d)", state.playerCount or 1)
		else
			parts.arenaLabel.Text = "Reserva: " .. (state.arenaName or "?")
		end
	end
	if parts.objective then
		parts.objective.Text = state.objective or ""
	end
	if parts.timer then
		parts.timer.Text = Util.formatTime(state.timeLeft or 0)
		parts.timer.TextColor3 = ((state.timeLeft or 0) < 30) and Color3.fromRGB(232, 108, 100) or COLOR.text
	end
	-- Herramientas disponibles segun el modo
	if parts.toolChips then
		for toolId, chip in pairs(parts.toolChips) do
			local visible = true
			if state.limitedTools then
				visible = false
				for _, id in ipairs(state.limitedTools) do
					if id == toolId then
						visible = true
						break
					end
				end
			elseif toolId == "pintura" then
				visible = state.paint == true
			elseif toolId == "relente" then
				visible = false
			end
			chip.chip.Visible = visible
		end
	end

	if parts.progress then
		if state.phase == "waiting" then
			parts.progress.Text = "Preparando la cacería"
		elseif state.phase == "countdown" then
			parts.progress.Text = "Preparados..."
		elseif state.progressText then
			parts.progress.Text = state.progressText
		elseif state.isMulti then
			parts.progress.Text = "Atrapados: " .. tostring(state.caught or 0)
		else
			parts.progress.Text = string.format("Kiwis: %d / %d", state.caught or 0, state.quota or 0)
		end
	end
	if parts.kiwiLabel then
		local hint = state.kiwiState
		if hint then
			parts.kiwiLabel.Text = "El kiwi está: " .. hint
			parts.kiwiLabel.TextColor3 = (hint == "escondido") and COLOR.muted
				or (hint == "dormido") and COLOR.accent
				or Color3.fromRGB(238, 196, 92)
		else
			parts.kiwiLabel.Text = "Sin datos del kiwi"
			parts.kiwiLabel.TextColor3 = COLOR.muted
		end
		parts.kiwiLabel.TextScaled = false
		parts.kiwiLabel.TextSize = 14
	end

	-- Marcador
	local list = parts.scoreList
	if list then
		for _, child in ipairs(list:GetChildren()) do
			if child:IsA("Frame") then
				child:Destroy()
			end
		end
		for index, entry in ipairs(state.players or {}) do
			if index <= Config.Multiplayer.scoreboardSize then
				local row = new("Frame", {
					LayoutOrder = index,
					Size = UDim2.new(1, 0, 0, 16),
					BackgroundTransparency = 1,
				}, list)
				new("TextLabel", {
					Size = UDim2.new(1, -30, 1, 0),
					BackgroundTransparency = 1,
					Font = entry.isSelf and Enum.Font.GothamBold or Enum.Font.Gotham,
					TextSize = 13,
					TextXAlignment = Enum.TextXAlignment.Left,
					TextColor3 = entry.isSelf and COLOR.accent or COLOR.text,
					Text = (entry.isSelf and "> " or "") .. entry.name,
				}, row)
				new("TextLabel", {
					AnchorPoint = Vector2.new(1, 0),
					Position = UDim2.new(1, 0, 0, 0),
					Size = UDim2.new(0, 30, 1, 0),
					BackgroundTransparency = 1,
					Font = Enum.Font.GothamBold,
					TextSize = 13,
					TextXAlignment = Enum.TextXAlignment.Right,
					TextColor3 = COLOR.muted,
					Text = tostring(entry.caught),
				}, row)
			end
		end
	end

	-- La brujula solo se apaga cuando expira el ping (lo maneja Main)
end

function HUD.setCooldowns(remaining)
	for toolId, chip in pairs(parts.toolChips or {}) do
		local left = remaining[toolId] or 0
		local total = chip.total or 1
		local ratio = left > 0.05 and math.clamp(left / total, 0, 1) or 0

		if left > 0.05 then
			chip.state.Text = string.format("%.1fs", left)
			chip.state.TextColor3 = Color3.fromRGB(232, 108, 100)
			chip.name.TextTransparency = 0.5
		else
			chip.state.Text = "Listo"
			chip.state.TextColor3 = COLOR.muted
			chip.name.TextTransparency = 0
		end
		chip.fill.Size = UDim2.new(ratio, 0, 0, 3)
	end
end

function HUD.setToolTotals(totals)
	for toolId, chip in pairs(parts.toolChips or {}) do
		chip.total = totals[toolId] or 1
	end
end

function HUD.setTracker(data)
	if not data or not parts.compass then
		return
	end
	tracker.active = true
	tracker.until_ = os.clock() + (data.duration or 6)
	tracker.pos = data.pos
	tracker.hidden = data.hidden
	parts.compass.Visible = true
end

function HUD.clearTracker()
	tracker.active = false
	tracker.pos = nil
	if parts.compass then
		parts.compass.Visible = false
	end
end

function HUD.updateTracker()
	if not tracker.active or not parts.needle or not tracker.pos then
		return
	end
	if os.clock() > tracker.until_ then
		HUD.clearTracker()
		return
	end

	local camera = workspace.CurrentCamera
	if not camera then
		return
	end

	local localCharacter = player.Character
	local root = localCharacter and localCharacter:FindFirstChild("HumanoidRootPart")
	local from = root and root.Position or camera.CFrame.Position
	local direction = tracker.pos - from
	if direction.Magnitude < 0.01 then
		return
	end

	local inCamera = camera.CFrame:VectorToObjectSpace(direction)
	parts.needle.Rotation = math.deg(math.atan2(inCamera.X, -inCamera.Z))

	-- La rosa de los vientos gira con la camara (la N marca el norte real)
	local look = camera.CFrame.LookVector
	local yaw = math.deg(math.atan2(look.X, -look.Z))
	local radius = 64
	for _, mark in ipairs(parts.compassMarks or {}) do
		local angle = math.rad(mark.azimuth - yaw)
		mark.gui.Position = UDim2.new(0.5, radius * math.sin(angle), 0.5, -radius * math.cos(angle))
	end

	local color = tracker.hidden and Color3.fromRGB(238, 196, 92) or Color3.fromRGB(140, 240, 180)
	if parts.needleTip then
		parts.needleTip.BackgroundColor3 = color
	end
	parts.compassDistance.TextColor3 = color
	parts.compassDistance.Text = string.format("%d studs - %s",
		math.floor(direction.Magnitude),
		tracker.hidden and "escondido" or "a la vista")
end

function HUD.showResult(result, seconds)
	if not parts.result then
		return
	end
	parts.result.Visible = true
	parts.resultTitle.Text = result.title or ""
	parts.resultSubtitle.Text = result.subtitle or ""
	parts.resultLines.Text = table.concat(result.lines or {}, "\n")
	parts.resultFooter.Text = string.format("Volviendo al lobby en %d s...", seconds or Config.Round.EndScreen)
	parts.resultBorder.Color = Util.colorFromTable(result.color)
	parts.resultTitle.TextColor3 = Util.colorFromTable(result.color)

	local list = parts.resultRanking
	for _, child in ipairs(list:GetChildren()) do
		if child:IsA("Frame") then
			child:Destroy()
		end
	end
	for index, entry in ipairs(result.ranking or {}) do
		local row = new("Frame", {
			LayoutOrder = index,
			Size = UDim2.new(1, 0, 0, 20),
			BackgroundTransparency = 1,
		}, list)
		new("TextLabel", {
			Size = UDim2.new(1, -50, 1, 0),
			BackgroundTransparency = 1,
			Font = entry.isWinner and Enum.Font.GothamBold or Enum.Font.Gotham,
			TextSize = 14,
			TextXAlignment = Enum.TextXAlignment.Left,
			TextColor3 = entry.isWinner and Util.colorFromTable(result.color)
				or (entry.isSelf and COLOR.accent or COLOR.text),
			Text = string.format("%d. %s%s", index, entry.name, entry.isSelf and " (tu)" or ""),
		}, row)
		new("TextLabel", {
			AnchorPoint = Vector2.new(1, 0),
			Position = UDim2.new(1, 0, 0, 0),
			Size = UDim2.new(0, 50, 1, 0),
			BackgroundTransparency = 1,
			Font = Enum.Font.GothamBold,
			TextSize = 14,
			TextXAlignment = Enum.TextXAlignment.Right,
			TextColor3 = COLOR.muted,
			Text = string.format("%d k", entry.caught),
		}, row)
	end
end

function HUD.hideResult()
	if parts.result then
		parts.result.Visible = false
	end
end

function HUD.death(title, subtitle)
	local screen = parts.screen
	if not screen then
		return
	end

	local overlay = parts.deathOverlay
	if not overlay then
		overlay = new("Frame", {
			Name = "Muerte",
			Size = UDim2.fromScale(1, 1),
			BackgroundColor3 = Color3.fromRGB(60, 8, 8),
			BackgroundTransparency = 1,
			BorderSizePixel = 0,
			Visible = false,
			ZIndex = 40,
		}, screen)
		parts.deathOverlay = overlay

		local box = new("Frame", {
			Name = "Caja",
			AnchorPoint = Vector2.new(0.5, 1),
			Position = UDim2.fromScale(0.5, 0.88),
			Size = UDim2.new(0.6, 0, 0, 150),
			BackgroundColor3 = Color3.fromRGB(24, 6, 8),
			BackgroundTransparency = 0.25,
			BorderSizePixel = 0,
		}, overlay)
		corner(14, box)
		stroke(Color3.fromRGB(232, 108, 100), 2, 0.2, box)

		parts.deathTitle = new("TextLabel", {
			Name = "Titulo",
			Position = UDim2.new(0, 0, 0, 18),
			Size = UDim2.new(1, 0, 0, 52),
			BackgroundTransparency = 1,
			Font = Enum.Font.GothamBlack,
			TextScaled = true,
			TextColor3 = Color3.fromRGB(255, 120, 110),
			Text = "¡MORISTE!",
		}, box)

		parts.deathSub = new("TextLabel", {
			Name = "Sub",
			Position = UDim2.new(0, 18, 0, 78),
			Size = UDim2.new(1, -36, 0, 44),
			BackgroundTransparency = 1,
			Font = Enum.Font.GothamMedium,
			TextWrapped = true,
			TextSize = 14,
			TextColor3 = Color3.fromRGB(240, 220, 220),
			Text = "",
		}, box)
	end

	parts.deathTitle.Text = title or "¡MORISTE!"
	parts.deathSub.Text = subtitle or ""
	overlay.Visible = true
	TweenService:Create(overlay, TweenInfo.new(0.25), { BackgroundTransparency = 0.5 }):Play()

	parts.deathCount = (parts.deathCount or 0) + 1
	local token = parts.deathCount
	task.delay(3.0, function()
		if parts.deathCount == token and overlay.Parent then
			TweenService:Create(overlay, TweenInfo.new(0.5), { BackgroundTransparency = 1 }):Play()
			task.delay(0.55, function()
				if parts.deathCount == token then
					overlay.Visible = false
				end
			end)
		end
	end)
end

function HUD.setScope(enabled)
	if parts.scope then
		parts.scope.Visible = enabled and true or false
	end
end

function HUD.fade(toBlack, duration)
	if not parts.fade then
		return
	end
	local goal = { BackgroundTransparency = toBlack and 0 or 1 }
	local tween = TweenService:Create(parts.fade, TweenInfo.new(duration or 0.4), goal)
	tween:Play()
	return tween
end

return HUD
