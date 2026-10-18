--[[
	ToolService.lua  (servidor)
	Fabrica las herramientas del cazador (red, rifle, rastreador,
trampa de fruta y rifle de pintura),
	se las entrega a los jugadores cuando arranca una partida y controla
	los tiempos de recarga de cada una.

	Las herramientas se guardan como plantillas en ServerStorage y se
	clonan al Backpack: asi nadie las tiene en el lobby.
--]]

local ServerStorage = game:GetService("ServerStorage")
local Players = game:GetService("Players")

local Shared = require(script.Parent.Shared)
local Config = require(Shared.Config)
local Util = require(Shared.Util)

local ToolService = {}

local TEMPLATE_FOLDER = "KiwiTools"
ToolService.cooldowns = {}

local function newHandle(props)
	props.Name = "Handle"
	props.Anchored = false
	props.CanCollide = false
	props.Massless = true
	props.TopSurface = Enum.SurfaceType.Smooth
	props.BottomSurface = Enum.SurfaceType.Smooth
	return Util.makePart(props)
end

-- Pieza extra pegada al mango (se mueve con el arma)
local function weldPiece(handle, props)
	props.Anchored = false
	props.CanCollide = false
	props.Massless = true
	props.TopSurface = Enum.SurfaceType.Smooth
	props.BottomSurface = Enum.SurfaceType.Smooth
	local piece = Util.makePart(props)
	local weld = Instance.new("WeldConstraint")
	weld.Part0 = handle
	weld.Part1 = piece
	weld.Parent = handle
	return piece
end

local function buildNet(parent)
	local tool = Instance.new("Tool")
	tool.Name = Config.Tools.red.name
	tool.ToolTip = Config.Tools.red.tooltip
	tool.CanBeDropped = false
	tool.RequiresHandle = true
	tool:SetAttribute("ToolId", "red")
	tool.Grip = CFrame.new(0, -1.6, 0)

	local handle = newHandle({
		Size = Vector3.new(0.24, 4.6, 0.24),
		Color = Color3.fromRGB(140, 108, 70),
		Material = Enum.Material.Wood,
		Parent = tool,
	})

	-- Aro de la red
	weldPiece(handle, {
		Name = "Aro",
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(0.35, 7, 7),
		CFrame = handle.CFrame * CFrame.new(0, 2.6, 0) * CFrame.Angles(0, 0, math.rad(90)),
		Color = Color3.fromRGB(96, 160, 220),
		Material = Enum.Material.SmoothPlastic,
		Transparency = 0.25,
		Parent = tool,
	})

	weldPiece(handle, {
		Name = "Malla",
		Size = Vector3.new(6.4, 0.18, 6.4),
		CFrame = handle.CFrame * CFrame.new(0, 2.6, 0),
		Color = Color3.fromRGB(232, 238, 245),
		Material = Enum.Material.Fabric,
		Transparency = 0.45,
		Parent = tool,
	})

	tool.Parent = parent
	return tool
end

local function buildRifle(parent)
	local tool = Instance.new("Tool")
	tool.Name = Config.Tools.rifle.name
	tool.ToolTip = Config.Tools.rifle.tooltip
	tool.CanBeDropped = false
	tool.RequiresHandle = true
	tool:SetAttribute("ToolId", "rifle")
	tool.Grip = CFrame.new(0, -0.35, 0.5) * CFrame.Angles(math.rad(-90), 0, 0)

	local handle = newHandle({
		Size = Vector3.new(0.4, 0.7, 2.4),
		Color = Color3.fromRGB(94, 74, 54),
		Material = Enum.Material.Wood,
		Parent = tool,
	})

	weldPiece(handle, {
		Name = "Canon",
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(2.6, 0.28, 0.28),
		CFrame = handle.CFrame * CFrame.new(0, 0.22, -0.4) * CFrame.Angles(0, math.rad(90), 0),
		Color = Color3.fromRGB(58, 60, 64),
		Material = Enum.Material.Metal,
		Parent = tool,
	})

	weldPiece(handle, {
		Name = "Mira",
		Size = Vector3.new(0.18, 0.5, 0.5),
		CFrame = handle.CFrame * CFrame.new(0, 0.6, -0.5),
		Color = Color3.fromRGB(210, 180, 90),
		Material = Enum.Material.Metal,
		Parent = tool,
	})

	weldPiece(handle, {
		Name = "Cargador",
		Size = Vector3.new(0.4, 1.1, 0.4),
		CFrame = handle.CFrame * CFrame.new(0, -0.7, 0.3),
		Color = Color3.fromRGB(74, 78, 84),
		Material = Enum.Material.Metal,
		Parent = tool,
	})

	tool.Parent = parent
	return tool
end

local function buildTracker(parent)
	local tool = Instance.new("Tool")
	tool.Name = Config.Tools.rastreador.name
	tool.ToolTip = Config.Tools.rastreador.tooltip
	tool.CanBeDropped = false
	tool.RequiresHandle = true
	tool:SetAttribute("ToolId", "rastreador")
	tool.Grip = CFrame.new(0, -0.3, 0)

	local handle = newHandle({
		Size = Vector3.new(1.1, 0.6, 1.6),
		Color = Color3.fromRGB(46, 52, 58),
		Material = Enum.Material.Metal,
		Parent = tool,
	})

	weldPiece(handle, {
		Name = "Pantalla",
		Size = Vector3.new(0.85, 0.12, 1.2),
		CFrame = handle.CFrame * CFrame.new(0, 0.34, 0) * CFrame.Angles(math.rad(-25), 0, 0),
		Color = Color3.fromRGB(102, 209, 150),
		Material = Enum.Material.Neon,
		Parent = tool,
	})

	weldPiece(handle, {
		Name = "Antena",
		Size = Vector3.new(0.1, 1.5, 0.1),
		CFrame = handle.CFrame * CFrame.new(0.4, 1.0, 0.6),
		Color = Color3.fromRGB(150, 156, 160),
		Material = Enum.Material.Metal,
		Parent = tool,
	})

	local light = Instance.new("PointLight")
	light.Color = Color3.fromRGB(102, 209, 150)
	light.Range = 12
	light.Brightness = 1.4
	light.Parent = handle

	tool.Parent = parent
	return tool
end

local function buildTrap(parent)
	local tool = Instance.new("Tool")
	tool.Name = Config.Tools.trampa.name
	tool.ToolTip = Config.Tools.trampa.tooltip
	tool.CanBeDropped = false
	tool.RequiresHandle = true
	tool:SetAttribute("ToolId", "trampa")
	tool.Grip = CFrame.new(0, -0.6, 0)

	local handle = newHandle({
		Size = Vector3.new(1.5, 0.24, 1.5),
		Color = Color3.fromRGB(120, 92, 60),
		Material = Enum.Material.Wood,
		Parent = tool,
	})

	-- cuatro varillas armando la jaula
	for i = 1, 4 do
		local angle = math.rad(45 + (i - 1) * 90)
		weldPiece(handle, {
			Name = "Varilla" .. i,
			Size = Vector3.new(0.1, 1.5, 0.1),
			CFrame = handle.CFrame * CFrame.new(math.cos(angle) * 0.62, 0.7, math.sin(angle) * 0.62)
				* CFrame.Angles(math.rad(18), 0, math.rad(-18)),
			Color = Color3.fromRGB(150, 118, 80),
			Material = Enum.Material.Wood,
			Parent = tool,
		})
	end

	-- la fruta: irresistible
	weldPiece(handle, {
		Name = "Fruta",
		Shape = Enum.PartType.Ball,
		Size = Vector3.new(0.62, 0.62, 0.62),
		CFrame = handle.CFrame * CFrame.new(0, 0.45, 0),
		Color = Color3.fromRGB(226, 70, 80),
		Material = Enum.Material.SmoothPlastic,
		Parent = tool,
	})

	weldPiece(handle, {
		Name = "Hoja",
		Size = Vector3.new(0.42, 0.06, 0.22),
		CFrame = handle.CFrame * CFrame.new(0.1, 0.78, 0) * CFrame.Angles(0, math.rad(20), math.rad(-18)),
		Color = Color3.fromRGB(96, 170, 92),
		Material = Enum.Material.LeafyGrass,
		Parent = tool,
	})

	tool.Parent = parent
	return tool
end

local function buildPaintRifle(parent)
	local tool = Instance.new("Tool")
	tool.Name = Config.Tools.pintura.name
	tool.ToolTip = Config.Tools.pintura.tooltip
	tool.CanBeDropped = false
	tool.RequiresHandle = true
	tool:SetAttribute("ToolId", "pintura")
	tool.Grip = CFrame.new(0, -0.35, 0.5) * CFrame.Angles(math.rad(-90), 0, 0)

	local handle = newHandle({
		Size = Vector3.new(0.4, 0.7, 2.4),
		Color = Color3.fromRGB(74, 60, 84),
		Material = Enum.Material.Wood,
		Parent = tool,
	})

	weldPiece(handle, {
		Name = "Canon",
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(2.6, 0.28, 0.28),
		CFrame = handle.CFrame * CFrame.new(0, 0.22, -0.4) * CFrame.Angles(0, math.rad(90), 0),
		Color = Color3.fromRGB(80, 84, 92),
		Material = Enum.Material.Metal,
		Parent = tool,
	})

	weldPiece(handle, {
		Name = "Tanque",
		Shape = Enum.PartType.Ball,
		Size = Vector3.new(0.85, 0.85, 0.85),
		CFrame = handle.CFrame * CFrame.new(0.1, -0.55, 0.5),
		Color = Config.Tools.pintura.color,
		Material = Enum.Material.SmoothPlastic,
		Parent = tool,
	})

	weldPiece(handle, {
		Name = "Mira",
		Size = Vector3.new(0.18, 0.5, 0.5),
		CFrame = handle.CFrame * CFrame.new(0, 0.6, -0.5),
		Color = Color3.fromRGB(230, 120, 190),
		Material = Enum.Material.Metal,
		Parent = tool,
	})

	tool.Parent = parent
	return tool
end

local function buildRelente(parent)
	local tool = Instance.new("Tool")
	tool.Name = Config.Tools.relente.name
	tool.ToolTip = Config.Tools.relente.tooltip
	tool.CanBeDropped = false
	tool.RequiresHandle = true
	tool:SetAttribute("ToolId", "relente")
	tool.Grip = CFrame.new(0, -0.35, 0.5) * CFrame.Angles(math.rad(-90), 0, 0)

	local handle = newHandle({
		Size = Vector3.new(0.4, 0.7, 2.4),
		Color = Color3.fromRGB(56, 78, 92),
		Material = Enum.Material.Wood,
		Parent = tool,
	})

	weldPiece(handle, {
		Name = "Canon",
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(2.6, 0.28, 0.28),
		CFrame = handle.CFrame * CFrame.new(0, 0.22, -0.4) * CFrame.Angles(0, math.rad(90), 0),
		Color = Color3.fromRGB(96, 104, 116),
		Material = Enum.Material.Metal,
		Parent = tool,
	})

	weldPiece(handle, {
		Name = "Tubo",
		Shape = Enum.PartType.Ball,
		Size = Vector3.new(0.85, 0.85, 0.85),
		CFrame = handle.CFrame * CFrame.new(0.1, -0.55, 0.5),
		Color = Config.Tools.relente.color,
		Material = Enum.Material.Neon,
		Parent = tool,
	})

	weldPiece(handle, {
		Name = "Mira",
		Size = Vector3.new(0.18, 0.5, 0.5),
		CFrame = handle.CFrame * CFrame.new(0, 0.6, -0.5),
		Color = Color3.fromRGB(96, 140, 156),
		Material = Enum.Material.Metal,
		Parent = tool,
	})

	tool.Parent = parent
	return tool
end

--[[
	Armas de baul: aparecen al abrir un baul (una a la vez por jugador).
	Disparan un proyectil con empujon; recarga y usos los controla
	Actions.fireWeapon en el servidor.
]]
local function buildLootTool(parent, id)
	local cfg = Config.Weapons[id]
	if not cfg then
		return nil
	end

	local tool = Instance.new("Tool")
	tool.Name = cfg.name
	tool.ToolTip = "Arma de baúl: usos limitados"
	tool.CanBeDropped = false
	tool.RequiresHandle = true
	tool:SetAttribute("ToolId", id)
	tool:SetAttribute("Loot", true)
	tool:SetAttribute("Uses", Config.Loot.uses)
	tool.Grip = CFrame.new(0, -0.35, 0.5) * CFrame.Angles(math.rad(-90), 0, 0)

	local handle = newHandle({
		Size = Vector3.new(0.4, 0.7, 2.2),
		Color = Color3.fromRGB(58, 58, 66),
		Material = Enum.Material.Wood,
		Parent = tool,
	})

	weldPiece(handle, {
		Name = "Canon",
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(2.4, 0.32, 0.32),
		CFrame = handle.CFrame * CFrame.new(0, 0.24, -0.5) * CFrame.Angles(0, math.rad(90), 0),
		Color = cfg.color,
		Material = Enum.Material.Metal,
		Parent = tool,
	})

	weldPiece(handle, {
		Name = "Nucleo",
		Shape = Enum.PartType.Ball,
		Size = Vector3.new(0.7, 0.7, 0.7),
		CFrame = handle.CFrame * CFrame.new(0.12, -0.5, 0.55),
		Color = cfg.color,
		Material = Enum.Material.Neon,
		Parent = tool,
	})

	tool.Parent = parent
	return tool
end

local function buildLootTools(parent)
	for _, entry in ipairs(Config.Loot.weapons) do
		buildLootTool(parent, entry.id)
	end
end

function ToolService.build()
	local existing = ServerStorage:FindFirstChild(TEMPLATE_FOLDER)
	if existing then
		existing:Destroy()
	end

	local folder = Instance.new("Folder")
	folder.Name = TEMPLATE_FOLDER
	folder.Parent = ServerStorage

	buildNet(folder)
	buildRifle(folder)
	buildTracker(folder)
	buildTrap(folder)
	buildPaintRifle(folder)
	buildRelente(folder)
	buildLootTools(folder)

	ToolService.folder = folder
	return folder
end

-- ===============================================================
-- Entrega de herramientas
-- ===============================================================
function ToolService.give(player, only)
	local folder = ToolService.folder
	if not folder or not player.Parent then
		return
	end

	local backpack = player:FindFirstChildOfClass("Backpack")
	if not backpack then
		return
	end

	local allow
	if only then
		allow = {}
		for _, id in ipairs(only) do
			allow[id] = true
		end
	end

	-- Limpia lo que haya quedado de la partida anterior
	ToolService.clear(player)

	for _, template in ipairs(folder:GetChildren()) do
		local toolId = template:GetAttribute("ToolId")
		-- pintura, relente y las armas de baul solo se entregan cuando toca
		local locked = toolId == "pintura" or toolId == "relente"
		if not locked then
			for _, entry in ipairs(Config.Loot.weapons) do
				if entry.id == toolId then
					locked = true
					break
				end
			end
		end
		local allowed
		if allow then
			allowed = allow[toolId] == true
		else
			allowed = not locked
		end
		if allowed then
			local clone = template:Clone()
			clone.Parent = backpack
		end
	end

	ToolService.cooldowns[player] = {}
end

function ToolService.clear(player)
	local backpack = player:FindFirstChildOfClass("Backpack")
	if backpack then
		for _, item in ipairs(backpack:GetChildren()) do
			if item:IsA("Tool") and item:GetAttribute("ToolId") then
				item:Destroy()
			end
		end
	end

	local character = player.Character
	if character then
		for _, item in ipairs(character:GetChildren()) do
			if item:IsA("Tool") and item:GetAttribute("ToolId") then
				item:Destroy()
			end
		end
	end

	ToolService.cooldowns[player] = nil
end

-- Entrega (o saca) UNA herramienta suelta, sin tocar el resto
function ToolService.giveTool(player, toolId)
	local folder = ToolService.folder
	if not folder then
		return
	end
	local backpack = player:FindFirstChildOfClass("Backpack")
	if not backpack then
		return
	end
	local containers = { backpack, player.Character }
	for _, container in ipairs(containers) do
		if container then
			for _, item in ipairs(container:GetChildren()) do
				if item:IsA("Tool") and item:GetAttribute("ToolId") == toolId then
					return
				end
			end
		end
	end
	for _, template in ipairs(folder:GetChildren()) do
		if template:GetAttribute("ToolId") == toolId then
			template:Clone().Parent = backpack
			return
		end
	end
end

function ToolService.giveLoot(player, toolId, uses)
	ToolService.giveTool(player, toolId)
	for _, container in ipairs({ player:FindFirstChildOfClass("Backpack"), player.Character }) do
		if container then
			for _, item in ipairs(container:GetChildren()) do
				if item:IsA("Tool") and item:GetAttribute("ToolId") == toolId then
					item:SetAttribute("Uses", uses)
				end
			end
		end
	end
end

function ToolService.lootUses(player, toolId)
	for _, container in ipairs({ player:FindFirstChildOfClass("Backpack"), player.Character }) do
		if container then
			for _, item in ipairs(container:GetChildren()) do
				if item:IsA("Tool") and item:GetAttribute("ToolId") == toolId then
					return item:GetAttribute("Uses") or 0
				end
			end
		end
	end
	return 0
end

function ToolService.consumeLoot(player, toolId)
	local left = 0
	for _, container in ipairs({ player:FindFirstChildOfClass("Backpack"), player.Character }) do
		if container then
			for _, item in ipairs(container:GetChildren()) do
				if item:IsA("Tool") and item:GetAttribute("ToolId") == toolId then
					left = math.max(0, (item:GetAttribute("Uses") or 0) - 1)
					if left <= 0 then
						item:Destroy()
					else
						item:SetAttribute("Uses", left)
					end
				end
			end
		end
	end
	return left
end

function ToolService.takeTool(player, toolId)
	local found = false
	local containers = { player:FindFirstChildOfClass("Backpack"), player.Character }
	for _, container in ipairs(containers) do
		if container then
			for _, item in ipairs(container:GetChildren()) do
				if item:IsA("Tool") and item:GetAttribute("ToolId") == toolId then
					found = true
					item:Destroy()
				end
			end
		end
	end
	return found
end

function ToolService.hasTools(player)
	local backpack = player:FindFirstChildOfClass("Backpack")
	if not backpack then
		return false
	end
	for _, item in ipairs(backpack:GetChildren()) do
		if item:IsA("Tool") and item:GetAttribute("ToolId") then
			return true
		end
	end
	return false
end

-- ===============================================================
-- Recargas
-- ===============================================================
function ToolService.startCooldown(player, toolId, seconds)
	if not ToolService.cooldowns[player] then
		ToolService.cooldowns[player] = {}
	end
	ToolService.cooldowns[player][toolId] = os.clock() + seconds
end

function ToolService.getRemaining(player, toolId)
	local list = ToolService.cooldowns[player]
	if not list or not list[toolId] then
		return 0
	end
	return math.max(0, list[toolId] - os.clock())
end

function ToolService.reset(player)
	ToolService.cooldowns[player] = {}
end

Players.PlayerRemoving:Connect(function(player)
	ToolService.cooldowns[player] = nil
end)

return ToolService
