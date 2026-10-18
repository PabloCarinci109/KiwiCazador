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
-- Cada arma de baul tiene SU propio modelo (arco, revolver, sniper y
-- lanzamisiles no se parecen entre si).
local function prepareLootTool(id)
	local cfg = Config.Weapons[id]
	local tool = Instance.new("Tool")
	tool.Name = cfg.name
	tool.ToolTip = "Arma de baúl: usos limitados"
	tool.CanBeDropped = false
	tool.RequiresHandle = true
	tool:SetAttribute("ToolId", id)
	tool:SetAttribute("Loot", true)
	tool:SetAttribute("Uses", Config.Loot.uses)
	return tool
end

local function buildRevolverTool(id)
	local tool = prepareLootTool(id)
	tool.Grip = CFrame.new(0, -0.2, 0.4) * CFrame.Angles(math.rad(-90), 0, 0)
	local handle = newHandle({
		Size = Vector3.new(0.26, 0.95, 0.5),
		Color = Color3.fromRGB(122, 86, 58),
		Material = Enum.Material.Wood,
		Parent = tool,
	})
	weldPiece(handle, {
		Name = "Canon",
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(1.7, 0.2, 0.2),
		CFrame = handle.CFrame * CFrame.new(0, 0.45, -0.75) * CFrame.Angles(0, math.rad(90), 0),
		Color = Color3.fromRGB(184, 186, 200),
		Material = Enum.Material.Metal,
		Parent = tool,
	})
	weldPiece(handle, {
		Name = "Tambor",
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(0.44, 0.56, 0.56),
		CFrame = handle.CFrame * CFrame.new(0, 0.42, -0.32) * CFrame.Angles(0, math.rad(90), 0),
		Color = Color3.fromRGB(150, 152, 166),
		Material = Enum.Material.Metal,
		Parent = tool,
	})
	weldPiece(handle, {
		Name = "Martillo",
		Size = Vector3.new(0.14, 0.42, 0.3),
		CFrame = handle.CFrame * CFrame.new(0, 0.68, 0.24),
		Color = Color3.fromRGB(120, 122, 132),
		Material = Enum.Material.Metal,
		Parent = tool,
	})
	return tool
end

local function buildBowTool(id)
	local tool = prepareLootTool(id)
	tool.Grip = CFrame.new(0, -0.45, 0.35) * CFrame.Angles(math.rad(-90), 0, 0)
	local handle = newHandle({
		Size = Vector3.new(0.26, 1.0, 0.34),
		Color = Color3.fromRGB(126, 90, 58),
		Material = Enum.Material.Wood,
		Parent = tool,
	})
	local wood = Color3.fromRGB(146, 106, 66)
	weldPiece(handle, {
		Name = "LimbA1",
		Size = Vector3.new(0.18, 1.5, 0.26),
		CFrame = handle.CFrame * CFrame.new(0, 0.95, -0.12) * CFrame.Angles(math.rad(-14), 0, 0),
		Color = wood, Material = Enum.Material.Wood, Parent = tool,
	})
	weldPiece(handle, {
		Name = "LimbA2",
		Size = Vector3.new(0.18, 1.4, 0.26),
		CFrame = handle.CFrame * CFrame.new(0, 1.9, -0.55) * CFrame.Angles(math.rad(-34), 0, 0),
		Color = wood, Material = Enum.Material.Wood, Parent = tool,
	})
	weldPiece(handle, {
		Name = "LimbB1",
		Size = Vector3.new(0.18, 1.5, 0.26),
		CFrame = handle.CFrame * CFrame.new(0, -0.95, -0.12) * CFrame.Angles(math.rad(14), 0, 0),
		Color = wood, Material = Enum.Material.Wood, Parent = tool,
	})
	weldPiece(handle, {
		Name = "LimbB2",
		Size = Vector3.new(0.18, 1.4, 0.26),
		CFrame = handle.CFrame * CFrame.new(0, -1.9, -0.55) * CFrame.Angles(math.rad(34), 0, 0),
		Color = wood, Material = Enum.Material.Wood, Parent = tool,
	})
	weldPiece(handle, {
		Name = "Cuerda",
		Size = Vector3.new(0.07, 4.9, 0.07),
		CFrame = handle.CFrame * CFrame.new(0, 0, -0.94),
		Color = Color3.fromRGB(238, 238, 226),
		Material = Enum.Material.Fabric,
		Parent = tool,
	})
	return tool
end

local function buildSniperTool(id)
	local tool = prepareLootTool(id)
	tool.Grip = CFrame.new(0, -0.2, 0.5) * CFrame.Angles(math.rad(-90), 0, 0)
	local handle = newHandle({
		Size = Vector3.new(0.34, 0.55, 1.5),
		Color = Color3.fromRGB(52, 58, 52),
		Material = Enum.Material.Metal,
		Parent = tool,
	})
	weldPiece(handle, {
		Name = "Culata",
		Size = Vector3.new(0.3, 0.85, 1.1),
		CFrame = handle.CFrame * CFrame.new(0, -0.45, 1.15) * CFrame.Angles(math.rad(14), 0, 0),
		Color = Color3.fromRGB(92, 66, 46),
		Material = Enum.Material.Wood,
		Parent = tool,
	})
	weldPiece(handle, {
		Name = "CanonLargo",
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(4.6, 0.2, 0.2),
		CFrame = handle.CFrame * CFrame.new(0, 0.28, -2.0) * CFrame.Angles(0, math.rad(90), 0),
		Color = Color3.fromRGB(44, 48, 46),
		Material = Enum.Material.Metal,
		Parent = tool,
	})
	weldPiece(handle, {
		Name = "MiraTelescopica",
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(1.25, 0.44, 0.44),
		CFrame = handle.CFrame * CFrame.new(0, 0.68, -0.55) * CFrame.Angles(0, math.rad(90), 0),
		Color = Color3.fromRGB(28, 30, 32),
		Material = Enum.Material.Metal,
		Parent = tool,
	})
	weldPiece(handle, {
		Name = "Lente",
		Shape = Enum.PartType.Ball,
		Size = Vector3.new(0.4, 0.4, 0.4),
		CFrame = handle.CFrame * CFrame.new(0, 0.68, -1.2),
		Color = Color3.fromRGB(120, 190, 220),
		Material = Enum.Material.Neon,
		Parent = tool,
	})
	weldPiece(handle, {
		Name = "Pata",
		Size = Vector3.new(0.1, 0.9, 0.1),
		CFrame = handle.CFrame * CFrame.new(-0.2, -0.45, -2.6) * CFrame.Angles(math.rad(14), 0, math.rad(16)),
		Color = Color3.fromRGB(44, 48, 46), Material = Enum.Material.Metal, Parent = tool,
	})
	weldPiece(handle, {
		Name = "PataB",
		Size = Vector3.new(0.1, 0.9, 0.1),
		CFrame = handle.CFrame * CFrame.new(0.2, -0.45, -2.6) * CFrame.Angles(math.rad(14), 0, math.rad(-16)),
		Color = Color3.fromRGB(44, 48, 46), Material = Enum.Material.Metal, Parent = tool,
	})
	return tool
end

local function buildRocketTool(id)
	local cfg = Config.Weapons[id]
	local tool = prepareLootTool(id)
	tool.Grip = CFrame.new(0, -0.75, 0.55) * CFrame.Angles(math.rad(-90), 0, 0)
	local handle = newHandle({
		Size = Vector3.new(0.34, 0.95, 0.7),
		Color = Color3.fromRGB(60, 62, 56),
		Material = Enum.Material.Plastic,
		Parent = tool,
	})
	weldPiece(handle, {
		Name = "Tubo",
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(4.6, 1.05, 1.05),
		CFrame = handle.CFrame * CFrame.new(0, 0.9, -1.6) * CFrame.Angles(0, math.rad(90), 0),
		Color = Color3.fromRGB(96, 106, 74),
		Material = Enum.Material.Metal,
		Parent = tool,
	})
	weldPiece(handle, {
		Name = "Escapes",
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(0.7, 1.25, 1.25),
		CFrame = handle.CFrame * CFrame.new(0, 0.9, 0.75) * CFrame.Angles(0, math.rad(90), 0),
		Color = Color3.fromRGB(48, 50, 46),
		Material = Enum.Material.Metal,
		Parent = tool,
	})
	weldPiece(handle, {
		Name = "Cabeza",
		Shape = Enum.PartType.Ball,
		Size = Vector3.new(0.95, 0.95, 0.95),
		CFrame = handle.CFrame * CFrame.new(0, 0.9, -4.1),
		Color = cfg.color,
		Material = Enum.Material.Metal,
		Parent = tool,
	})
	weldPiece(handle, {
		Name = "MiraCohete",
		Size = Vector3.new(0.22, 0.6, 0.7),
		CFrame = handle.CFrame * CFrame.new(0, 1.6, -0.9),
		Color = Color3.fromRGB(58, 60, 64),
		Material = Enum.Material.Metal,
		Parent = tool,
	})
	weldPiece(handle, {
		Name = "Punta",
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(0.55, 0.5, 0.5),
		CFrame = handle.CFrame * CFrame.new(0, 0.9, -4.7) * CFrame.Angles(0, math.rad(90), 0),
		Color = Color3.fromRGB(198, 72, 52),
		Material = Enum.Material.Metal,
		Parent = tool,
	})
	weldPiece(handle, {
		Name = "Hombro",
		Size = Vector3.new(0.34, 0.75, 0.55),
		CFrame = handle.CFrame * CFrame.new(0, 0.75, 1.35),
		Color = Color3.fromRGB(60, 62, 56),
		Material = Enum.Material.Plastic,
		Parent = tool,
	})
	weldPiece(handle, {
		Name = "Empunadura",
		Size = Vector3.new(0.22, 0.5, 0.3),
		CFrame = handle.CFrame * CFrame.new(0, 0.28, -2.15) * CFrame.Angles(math.rad(-12), 0, 0),
		Color = Color3.fromRGB(74, 60, 40),
		Material = Enum.Material.Wood,
		Parent = tool,
	})
	return tool
end

-- Cuchillo mariposa: va de fabrica para todos (no es arma de baul).
-- Modelo abierto de balisong: dos mangos de acero alineados y la hoja
-- saliendo del pivote. La animacion estilo CS2 vive en la vista del cliente.
local function buildKnifeTool(parent)
	local tool = Instance.new("Tool")
	tool.Name = Config.Weapons.cuchillo.name
	tool.ToolTip = "Cuchillo mariposa: zarpazo corto. F para girarlo"
	tool.CanBeDropped = false
	tool.RequiresHandle = true
	tool:SetAttribute("ToolId", "cuchillo")
	tool.Grip = CFrame.new(0, -0.4, 0.15) * CFrame.Angles(math.rad(-90), 0, 0)
	local acero = Color3.fromRGB(198, 204, 214)
	local aceroOscuro = Color3.fromRGB(132, 138, 150)

	-- Mango en la mano (el Handle) y el gemelo pegado al lado
	local handle = newHandle({
		Size = Vector3.new(0.18, 0.85, 0.36),
		Color = aceroOscuro,
		Material = Enum.Material.Metal,
		Parent = tool,
	})
	weldPiece(handle, {
		Name = "MangoB",
		Size = Vector3.new(0.18, 0.85, 0.36),
		CFrame = handle.CFrame * CFrame.new(0.24, 0, 0),
		Color = aceroOscuro,
		Material = Enum.Material.Metal,
		Parent = tool,
	})
	weldPiece(handle, {
		Name = "Pivote",
		Size = Vector3.new(0.46, 0.12, 0.4),
		CFrame = handle.CFrame * CFrame.new(0.12, 0.5, 0),
		Color = acero,
		Material = Enum.Material.Metal,
		Parent = tool,
	})
	weldPiece(handle, {
		Name = "Hoja",
		Size = Vector3.new(0.12, 1.7, 0.3),
		CFrame = handle.CFrame * CFrame.new(0.12, 1.42, 0),
		Color = Color3.fromRGB(228, 234, 244),
		Material = Enum.Material.Metal,
		Parent = tool,
	})
	weldPiece(handle, {
		Name = "Punta",
		Size = Vector3.new(0.44, 0.44, 0.3),
		CFrame = handle.CFrame * CFrame.new(0.12, 2.42, 0) * CFrame.Angles(0, 0, math.rad(45)),
		Color = Color3.fromRGB(228, 234, 244),
		Material = Enum.Material.Metal,
		Parent = tool,
	})
	weldPiece(handle, {
		Name = "Filo",
		Size = Vector3.new(0.1, 1.5, 0.1),
		CFrame = handle.CFrame * CFrame.new(0.2, 1.35, 0),
		Color = Color3.fromRGB(255, 255, 255),
		Material = Enum.Material.Neon,
		Parent = tool,
	})
	return tool
end

-- Mochila de combustible: se ve en la espalda (tercera persona) mientras
-- usas el lanzallamas y se puede disparar: si le pegan, explota.
local function tankPiece(character, name, props)
	local part = Instance.new("Part")
	part.Name = name
	part.Size = props.size
	part.Color = props.color
	part.Shape = props.shape or Enum.PartType.Block
	part.Material = props.material or Enum.Material.Metal
	part.CanCollide = false
	part.CanTouch = false
	part.CanQuery = true
	part.CastShadow = false
	part.Massless = true
	part.TopSurface = Enum.SurfaceType.Smooth
	part.BottomSurface = Enum.SurfaceType.Smooth
	part:SetAttribute("Tanque", true)
	part.CFrame = props.cframe
	part.Parent = character
	local weld = Instance.new("WeldConstraint")
	weld.Part0 = props.torso
	weld.Part1 = part
	weld.Parent = part
	return part
end

local function attachFuelTank(character)
	if character:FindFirstChild("TanqueCombustible") then
		return
	end
	local torso = character:FindFirstChild("UpperTorso") or character:FindFirstChild("Torso")
	if not torso then
		return
	end
	local cf = torso.CFrame
	-- Local +Z mira para atras: la mochila va pegada a la espalda
	tankPiece(character, "TanqueCombustible", {
		torso = torso,
		size = Vector3.new(0.92, 1.15, 0.34),
		color = Color3.fromRGB(140, 60, 48),
		cframe = cf * CFrame.new(0, 0.12, 0.62),
	})
	tankPiece(character, "TanqueCombustible_Tanque", {
		torso = torso,
		shape = Enum.PartType.Cylinder,
		size = Vector3.new(0.95, 0.5, 0.5),
		color = Color3.fromRGB(178, 76, 58),
		cframe = cf * CFrame.new(0, 0.12, 0.85),
	})
	tankPiece(character, "TanqueCombustible_Valvula", {
		torso = torso,
		shape = Enum.PartType.Ball,
		size = Vector3.new(0.2, 0.2, 0.2),
		color = Color3.fromRGB(96, 220, 140),
		material = Enum.Material.Neon,
		cframe = cf * CFrame.new(0.3, 0.55, 0.8),
	})
end

local function detachFuelTank(character)
	if not character then
		return
	end
	for _, part in ipairs(character:GetChildren()) do
		if part:IsA("BasePart") and part:GetAttribute("Tanque") then
			part:Destroy()
		end
	end
end

ToolService.attachTank = attachFuelTank
ToolService.detachTank = detachFuelTank

-- La mochila se engancha al clon que recibe el jugador (las conexiones no se
-- copian al clonar la plantilla)
local function wireTool(tool)
	if tool:GetAttribute("ToolId") ~= "lanzallamas" then
		return
	end
	local worn = nil
	tool.Equipped:Connect(function()
		local parent = tool.Parent
		if parent and parent:IsA("Model") then
			worn = parent
			attachFuelTank(parent)
		end
	end)
	tool.Unequipped:Connect(function()
		if worn then
			detachFuelTank(worn)
			worn = nil
		end
	end)
	tool.Destroying:Connect(function()
		if worn then
			detachFuelTank(worn)
			worn = nil
		end
	end)
end

local function buildFlamethrowerTool(id)
	local cfg = Config.Weapons[id]
	local tool = prepareLootTool(id)
	tool.Grip = CFrame.new(0, -0.35, 0.3) * CFrame.Angles(math.rad(-90), 0, 0)
	local handle = newHandle({
		Size = Vector3.new(0.3, 0.8, 0.5),
		Color = Color3.fromRGB(70, 70, 66),
		Material = Enum.Material.Metal,
		Parent = tool,
	})
	weldPiece(handle, {
		Name = "Tubo",
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(3.6, 0.34, 0.34),
		CFrame = handle.CFrame * CFrame.new(0, 0.55, -1.4) * CFrame.Angles(0, math.rad(90), 0),
		Color = Color3.fromRGB(96, 96, 90),
		Material = Enum.Material.Metal,
		Parent = tool,
	})
	weldPiece(handle, {
		Name = "Boquilla",
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(0.7, 0.6, 0.6),
		CFrame = handle.CFrame * CFrame.new(0, 0.55, -3.2) * CFrame.Angles(0, math.rad(90), 0),
		Color = Color3.fromRGB(52, 52, 50),
		Material = Enum.Material.Metal,
		Parent = tool,
	})
	weldPiece(handle, {
		Name = "Piloto",
		Shape = Enum.PartType.Ball,
		Size = Vector3.new(0.42, 0.42, 0.42),
		CFrame = handle.CFrame * CFrame.new(0, 0.55, -3.7),
		Color = cfg.color,
		Material = Enum.Material.Neon,
		Parent = tool,
	})
	weldPiece(handle, {
		Name = "Mochila",
		Size = Vector3.new(1.5, 2.0, 0.8),
		CFrame = handle.CFrame * CFrame.new(0, -0.2, 0.7),
		Color = Color3.fromRGB(140, 60, 48),
		Material = Enum.Material.Metal,
		Parent = tool,
	})
	weldPiece(handle, {
		Name = "TanqueA",
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(1.6, 0.6, 0.6),
		CFrame = handle.CFrame * CFrame.new(-0.36, 0.35, 0.75) * CFrame.Angles(0, 0, math.rad(90)),
		Color = Color3.fromRGB(178, 76, 58),
		Material = Enum.Material.Metal,
		Parent = tool,
	})
	weldPiece(handle, {
		Name = "TanqueB",
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(1.6, 0.6, 0.6),
		CFrame = handle.CFrame * CFrame.new(0.36, 0.35, 0.75) * CFrame.Angles(0, 0, math.rad(90)),
		Color = Color3.fromRGB(178, 76, 58),
		Material = Enum.Material.Metal,
		Parent = tool,
	})
	return tool
end

-- Armas estilo Counter Blox (AK, M4, MP5, Glock, escopeta): cuerpo,
-- cañon, culata y cargador simples, como el resto de las armas de baul.
local COUNTER_TOOLS = {
	ak = {
		color = Color3.fromRGB(150, 104, 62), body = Vector3.new(0.24, 0.34, 1.5),
		len = 1.5, bore = 0.17, wood = true, stock = Color3.fromRGB(126, 90, 58),
	},
	m4 = {
		color = Color3.fromRGB(64, 70, 82), body = Vector3.new(0.24, 0.32, 1.6),
		len = 1.7, bore = 0.15,
	},
	mp5 = {
		color = Color3.fromRGB(58, 62, 72), body = Vector3.new(0.22, 0.30, 1.1),
		len = 1.0, bore = 0.15, stockY = 0.35,
	},
	glock = {
		color = Color3.fromRGB(70, 72, 80), body = Vector3.new(0.14, 0.24, 0.8),
		len = 0.55, bore = 0.13, stockY = 0.22,
	},
	escopeta = {
		color = Color3.fromRGB(96, 74, 54), body = Vector3.new(0.24, 0.32, 1.5),
		len = 1.7, bore = 0.22, wood = true, stock = Color3.fromRGB(118, 80, 50),
	},
}

local function buildCounterTool(id)
	local spec = COUNTER_TOOLS[id]
	local tool = prepareLootTool(id)
	tool.Grip = CFrame.new(0, -0.2, 0.35) * CFrame.Angles(math.rad(-90), 0, 0)
	local handle = newHandle({
		Size = Vector3.new(0.26, 0.85, 0.4),
		Color = Color3.fromRGB(52, 56, 64),
		Parent = tool,
	})
	weldPiece(handle, {
		Name = "Cuerpo",
		Size = spec.body,
		CFrame = handle.CFrame * CFrame.new(0, 0.55, -0.6),
		Color = spec.color,
		Material = Enum.Material.Metal,
		Parent = tool,
	})
	weldPiece(handle, {
		Name = "Canon",
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(spec.len, spec.bore, spec.bore),
		CFrame = handle.CFrame * CFrame.new(0, 0.62, -(spec.len * 0.5 + 0.35)) * CFrame.Angles(0, math.rad(90), 0),
		Color = Color3.fromRGB(38, 40, 46),
		Material = Enum.Material.Metal,
		Parent = tool,
	})
	weldPiece(handle, {
		Name = "Culata",
		Size = Vector3.new(0.22, spec.stockY or 0.42, 0.85),
		CFrame = handle.CFrame * CFrame.new(0, 0.42, 0.35),
		Color = spec.stock or spec.color,
		Material = spec.wood and Enum.Material.Wood or Enum.Material.Metal,
		Parent = tool,
	})
	weldPiece(handle, {
		Name = "Cargador",
		Size = Vector3.new(0.16, 0.5, 0.3),
		CFrame = handle.CFrame * CFrame.new(0, 0.12, -0.5) * CFrame.Angles(math.rad(-14), 0, 0),
		Color = spec.color,
		Material = Enum.Material.Metal,
		Parent = tool,
	})
	return tool
end

local function buildLootTool(parent, id)
	if not Config.Weapons[id] then
		return nil
	end

	local tool
	if id == "revolver" then
		tool = buildRevolverTool(id)
	elseif id == "arco" then
		tool = buildBowTool(id)
	elseif id == "sniper" then
		tool = buildSniperTool(id)
	elseif id == "lanzallamas" then
		tool = buildFlamethrowerTool(id)
	elseif COUNTER_TOOLS[id] then
		tool = buildCounterTool(id)
	else
		tool = buildRocketTool(id)
	end

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
	buildKnifeTool(folder)
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
		-- (el cuchillo mariposa si va de fabrica para todos)
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
			wireTool(clone)
			clone.Parent = backpack
		end
	end

	-- Blindaje: el cuchillo mariposa va de fabrica SIEMPRE (en todos los
	-- modos y para todos los personajes), aunque la lista del modo lo olvide.
	local tieneCuchillo = false
	for _, item in ipairs(backpack:GetChildren()) do
		if item:IsA("Tool") and item:GetAttribute("ToolId") == "cuchillo" then
			tieneCuchillo = true
			break
		end
	end
	if not tieneCuchillo then
		for _, template in ipairs(folder:GetChildren()) do
			if template:GetAttribute("ToolId") == "cuchillo" then
				local clone = template:Clone()
				wireTool(clone)
				clone.Parent = backpack
				break
			end
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
			local clone = template:Clone()
			wireTool(clone)
			clone.Parent = backpack
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

function ToolService.addLootUses(player, toolId, amount)
	local cap = Config.Loot.uses
	local total = 0
	for _, container in ipairs({ player:FindFirstChildOfClass("Backpack"), player.Character }) do
		if container then
			for _, item in ipairs(container:GetChildren()) do
				if item:IsA("Tool") and item:GetAttribute("ToolId") == toolId then
					total = math.min(cap, (item:GetAttribute("Uses") or 0) + (amount or 1))
					item:SetAttribute("Uses", total)
				end
			end
		end
	end
	return total
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

-- ¿El arma es de baul? (las de baul se gastan: "Uses" / consumeLoot)
function ToolService.isLoot(player, toolId)
	for _, container in ipairs({ player:FindFirstChildOfClass("Backpack"), player.Character }) do
		if container then
			for _, item in ipairs(container:GetChildren()) do
				if item:IsA("Tool") and item:GetAttribute("ToolId") == toolId then
					return item:GetAttribute("Loot") == true
				end
			end
		end
	end
	return false
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
