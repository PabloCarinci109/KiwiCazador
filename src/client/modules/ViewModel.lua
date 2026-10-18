--[[
	ViewModel.lua  (cliente)
	Arma en primera persona estilo Counter: el arma se ve pegada a la
	camara, con bamboleo al caminar, inercia al girar la vista, patada
	al disparar y pose de mira (clic derecho). El francotirador con la
	telescopica puesta esconde el arma y deja solo la mira.

	Son puras partes de adorno pegadas a la camara (CanCollide = false,
	CanQuery = false): no tocan la fisica ni pasan por el servidor.
--]]

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

local player = Players.LocalPlayer

local ViewModel = {}

local folder        -- carpeta viva dentro de la camara
local models = {}   -- cache de armas construidas
local currentId
local current
local visible = false
local hiddenByScope = false
local ads = 0          -- 0 = cadera, 1 = apuntando
local adsGoal = 0
local bobPhase = 0
local sway = Vector2.new(0, 0)
local lastCamCF = nil
local recoil = 0       -- patada: se va sola
local recoilRoll = 0   -- volcado al azar de la patada (estilo Counter)
local camKick = Vector2.new(0, 0) -- patada de camara (radianes)
local flashTimer = 0   -- fogonazo del canon

-- Posicion del arma respecto de la camara
local HIP = CFrame.new(0.85, -0.95, -1.45)
local ADS = CFrame.new(0.02, -0.55, -1.1)

-- ===============================================================
-- Construccion de las armas (cajas simples, estilo Counter)
-- ===============================================================
local function piece(model, size, cf, color, material, shape)
	local p = Instance.new("Part")
	p.Name = "Pieza"
	p.Size = size
	p.CFrame = cf
	p.Color = color or Color3.fromRGB(40, 42, 48)
	p.Material = material or Enum.Material.Metal
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.CastShadow = false
	p.Locked = true
	p.Massless = true
	if shape then
		p.Shape = shape
	end
	p.Parent = folder
	table.insert(model.pieces, { part = p, cf = cf })
	return p
end

-- Rifle base (tranquilizante, pintura y relente comparten cuerpo)
local function buildRifle(tint, accent)
	local model = { pieces = {} }
	piece(model, Vector3.new(0.62, 0.85, 3.1), CFrame.new(0, -0.1, -0.6), Color3.fromRGB(52, 55, 62))
	piece(model, Vector3.new(0.26, 0.26, 2.4), CFrame.new(0, 0.06, -2.9), Color3.fromRGB(34, 36, 42))
	piece(model, Vector3.new(0.5, 0.75, 1.5), CFrame.new(0, -0.28, 1.6), tint or Color3.fromRGB(122, 92, 62), Enum.Material.Wood)
	piece(model, Vector3.new(0.42, 0.95, 0.75), CFrame.new(0, -0.85, -0.55) * CFrame.Angles(math.rad(14), 0, 0), Color3.fromRGB(44, 47, 54))
	piece(model, Vector3.new(0.4, 0.95, 0.6), CFrame.new(0, -0.9, 0.8) * CFrame.Angles(math.rad(-12), 0, 0), Color3.fromRGB(40, 42, 48))
	piece(model, Vector3.new(0.3, 0.28, 1.15), CFrame.new(0, 0.6, -0.7), accent or Color3.fromRGB(58, 62, 70))
	model.muzzle = Vector3.new(0, 0.06, -4.15)
	return model
end

-- Francotirador: cañon largo, apagallamas y telescopica grande
local function buildSniper()
	local model = { pieces = {} }
	piece(model, Vector3.new(0.6, 0.8, 3.0), CFrame.new(0, -0.1, -0.4), Color3.fromRGB(46, 52, 50))
	piece(model, Vector3.new(0.22, 0.22, 3.2), CFrame.new(0, 0.08, -3.4), Color3.fromRGB(30, 34, 34))
	piece(model, Vector3.new(0.5, 0.5, 0.45), CFrame.new(0, 0.08, -4.95), Color3.fromRGB(62, 68, 68))
	piece(model, Vector3.new(0.5, 0.75, 1.8), CFrame.new(0, -0.32, 1.55), Color3.fromRGB(58, 72, 60), Enum.Material.WoodPlanks)
	piece(model, Vector3.new(0.44, 1.0, 0.7), CFrame.new(0, -0.88, -0.35) * CFrame.Angles(math.rad(12), 0, 0), Color3.fromRGB(40, 44, 44))
	-- Telescopica (cilindro apoyado a lo largo del arma)
	piece(model, Vector3.new(2.1, 0.4, 0.4), CFrame.new(0, 0.8, -0.9) * CFrame.Angles(0, math.rad(90), 0),
		Color3.fromRGB(22, 24, 28), nil, Enum.PartType.Cylinder)
	piece(model, Vector3.new(0.18, 0.42, 0.42), CFrame.new(0, 0.8, -1.98) * CFrame.Angles(0, math.rad(90), 0),
		Color3.fromRGB(60, 70, 74), Enum.Material.Glass, Enum.PartType.Cylinder)
	piece(model, Vector3.new(0.16, 0.34, 0.34), CFrame.new(0, 0.8, 0.18) * CFrame.Angles(0, math.rad(90), 0),
		Color3.fromRGB(60, 70, 74), Enum.Material.Glass, Enum.PartType.Cylinder)
	piece(model, Vector3.new(0.16, 0.16, 0.16), CFrame.new(0, 0.8, -2.14), Color3.fromRGB(140, 235, 255), Enum.Material.Neon)
	model.muzzle = Vector3.new(0, 0.08, -5.25)
	return model
end

local function buildRevolver()
	local model = { pieces = {} }
	piece(model, Vector3.new(0.34, 0.5, 0.9), CFrame.new(0, 0, -0.35), Color3.fromRGB(96, 100, 110))
	piece(model, Vector3.new(0.42, 0.42, 0.62), CFrame.new(0, 0.02, -0.15) * CFrame.Angles(0, 0, 0),
		Color3.fromRGB(150, 154, 164), nil, Enum.PartType.Cylinder)  -- tambor
	piece(model, Vector3.new(0.2, 0.2, 1.5), CFrame.new(0, 0.08, -1.4), Color3.fromRGB(60, 64, 72))
	piece(model, Vector3.new(0.34, 0.8, 0.5), CFrame.new(0, -0.62, 0.28) * CFrame.Angles(math.rad(-16), 0, 0),
		Color3.fromRGB(96, 66, 42), Enum.Material.Wood)
	model.muzzle = Vector3.new(0, 0.08, -2.25)
	return model
end

local function buildArco()
	local model = { pieces = {} }
	-- Arco curvado con 3 tramos + cuerda
	piece(model, Vector3.new(0.22, 2.0, 0.22), CFrame.new(0, 0.9, -0.6) * CFrame.Angles(0, 0, math.rad(-24)), Color3.fromRGB(112, 84, 54), Enum.Material.Wood)
	piece(model, Vector3.new(0.22, 2.0, 0.22), CFrame.new(0, -0.9, -0.6) * CFrame.Angles(0, 0, math.rad(24)), Color3.fromRGB(112, 84, 54), Enum.Material.Wood)
	piece(model, Vector3.new(0.16, 0.16, 0.16), CFrame.new(-0.42, 0, -0.6), Color3.fromRGB(150, 196, 118), Enum.Material.Neon)
	piece(model, Vector3.new(0.08, 3.4, 0.08), CFrame.new(-0.42, 0, -0.6), Color3.fromRGB(232, 236, 240), Enum.Material.SmoothPlastic)
	-- Mano/puño
	piece(model, Vector3.new(0.4, 0.5, 0.5), CFrame.new(0, 0, -0.6), Color3.fromRGB(120, 90, 58), Enum.Material.Fabric)
	model.muzzle = Vector3.new(-0.42, 0, -0.9)
	return model
end

local function buildCuchillo()
	local model = { pieces = {} }
	piece(model, Vector3.new(0.3, 0.7, 0.4), CFrame.new(0, -0.7, -0.4), Color3.fromRGB(62, 46, 34), Enum.Material.Wood)
	piece(model, Vector3.new(0.85, 0.16, 0.45), CFrame.new(0, -0.28, -0.4), Color3.fromRGB(130, 134, 144))
	piece(model, Vector3.new(0.72, 2.3, 0.12), CFrame.new(0, 0.95, -0.4), Color3.fromRGB(226, 232, 240))
	piece(model, Vector3.new(0.1, 2.2, 0.14), CFrame.new(0.3, 0.95, -0.4), Color3.fromRGB(255, 255, 255), Enum.Material.Neon)
	model.muzzle = Vector3.new(0, 2.2, -0.4)
	return model
end

local function buildLanzallamas()
	local model = { pieces = {} }
	piece(model, Vector3.new(0.36, 0.7, 1.6), CFrame.new(0.2, 0, -0.8), Color3.fromRGB(70, 70, 66))
	piece(model, Vector3.new(1.7, 0.34, 0.34), CFrame.new(0.2, 0.1, -2.0) * CFrame.Angles(0, math.rad(90), 0),
		Color3.fromRGB(96, 96, 90), nil, Enum.PartType.Cylinder)
	piece(model, Vector3.new(0.5, 0.55, 0.55), CFrame.new(0.2, 0.1, -2.9) * CFrame.Angles(0, math.rad(90), 0),
		Color3.fromRGB(52, 52, 50), nil, Enum.PartType.Cylinder)
	piece(model, Vector3.new(0.3, 0.3, 0.3), CFrame.new(0.2, 0.1, -3.24), Color3.fromRGB(255, 150, 60), Enum.Material.Neon)
	-- Mochila con tanques
	piece(model, Vector3.new(0.32, 0.32, 1.5), CFrame.new(-0.35, -0.75, 0.6) * CFrame.Angles(0, 0, math.rad(90)),
		Color3.fromRGB(178, 76, 58), nil, Enum.PartType.Cylinder)
	piece(model, Vector3.new(0.32, 0.32, 1.5), CFrame.new(0.22, -0.75, 0.6) * CFrame.Angles(0, 0, math.rad(90)),
		Color3.fromRGB(178, 76, 58), nil, Enum.PartType.Cylinder)
	model.muzzle = Vector3.new(0.2, 0.1, -3.45)
	return model
end

local function buildCohete()
	local model = { pieces = {} }
	piece(model, Vector3.new(0.85, 0.85, 3.6), CFrame.new(0, 0.15, -1.1) * CFrame.Angles(0, math.rad(90), 0),
		Color3.fromRGB(70, 84, 66), nil, Enum.PartType.Cylinder)
	piece(model, Vector3.new(0.95, 0.95, 0.4), CFrame.new(0, 0.15, -2.85) * CFrame.Angles(0, math.rad(90), 0),
		Color3.fromRGB(48, 52, 48), nil, Enum.PartType.Cylinder)
	piece(model, Vector3.new(0.4, 0.9, 0.6), CFrame.new(0, -0.5, -0.5) * CFrame.Angles(math.rad(-10), 0, 0),
		Color3.fromRGB(52, 56, 52))
	piece(model, Vector3.new(0.3, 0.3, 0.7), CFrame.new(0, 0.8, -1.2), Color3.fromRGB(40, 44, 40))
	piece(model, Vector3.new(0.16, 0.16, 0.16), CFrame.new(0, 0.95, -1.5), Color3.fromRGB(200, 80, 60), Enum.Material.Neon)
	model.muzzle = Vector3.new(0, 0.15, -3.2)
	return model
end

local BUILDERS = {
	rifle = function() return buildRifle(nil, nil) end,
	pintura = function() return buildRifle(Color3.fromRGB(120, 84, 108), Color3.fromRGB(230, 120, 190)) end,
	relente = function() return buildRifle(Color3.fromRGB(96, 116, 126), Color3.fromRGB(110, 220, 235)) end,
	sniper = buildSniper,
	revolver = buildRevolver,
	arco = buildArco,
	cuchillo = buildCuchillo,
	lanzallamas = buildLanzallamas,
	cohete = buildCohete,
}

-- ===============================================================
-- Carpeta viva (se recrea si cambia la camara)
-- ===============================================================
local function ensureFolder()
	local camera = workspace.CurrentCamera
	if not camera then
		return nil
	end
	if folder and folder.Parent ~= camera then
		folder = nil
		models = {}
		current = nil
		currentId = nil
	end
	if not folder then
		folder = Instance.new("Folder")
		folder.Name = "VistaArmas"
		folder.Parent = camera
	end
	return folder
end

-- ===============================================================
-- API
-- ===============================================================
function ViewModel.setWeapon(id)
	if not id then
		currentId = nil
		current = nil
		return
	end
	if id == currentId then
		return
	end
	currentId = id
	current = nil
	if not BUILDERS[id] then
		return
	end
	ensureFolder()
	if not folder then
		return
	end
	if not models[id] then
		models[id] = BUILDERS[id]()
	end
	current = models[id]
	-- Fogonazo: una bolita neon en la boca del canon
	if current and not current.flash then
		local flash = piece(current, Vector3.new(0.72, 0.5, 0.5),
			CFrame.new(current.muzzle or Vector3.new(0, 0, -2)) * CFrame.Angles(0, math.rad(90), 0),
			Color3.fromRGB(255, 236, 168), Enum.Material.Neon, Enum.PartType.Cylinder)
		flash.Transparency = 1
		flash.CastShadow = false
		current.flash = flash
	end
	-- Deja la pose ya lista para que no se vea saltar
	ads = adsGoal
end

function ViewModel.setVisible(value)
	visible = value and true or false
end

function ViewModel.setAds(goal)
	adsGoal = math.clamp(goal or 0, 0, 1)
end

function ViewModel.setHidden(value)
	hiddenByScope = value and true or false
end

function ViewModel.recoil(amount)
	recoil = math.min(1.6, recoil + (amount or 0.5))
	recoilRoll = (math.random() * 2 - 1) * 0.18 * (amount or 0.5)
end

-- Patada de camara estilo Counter Blox: sube de golpe y vuelve sola
function ViewModel.kickCamera(pitch, yaw)
	camKick = Vector2.new(camKick.X + (pitch or 0), camKick.Y + (yaw or 0))
end

function ViewModel.flash()
	flashTimer = 0.055
end

function ViewModel.hasWeapon(id)
	return BUILDERS[id or currentId] ~= nil
end

function ViewModel.getMuzzle()
	local camera = workspace.CurrentCamera
	if not camera or not current then
		return nil
	end
	local base = camera.CFrame * HIP:Lerp(ADS, ads)
	local world = base * (current.muzzle or Vector3.new(0, 0, -2))
	return world, camera.CFrame.LookVector
end

-- ===============================================================
-- Bucle (despues de que la camara se mueve, asi no tiembla)
-- ===============================================================
local function stepUnbound(dt)
	local camera = workspace.CurrentCamera
	if not camera then
		return
	end

	ads = ads + (adsGoal - ads) * math.min(dt * 11, 1)
	recoil = recoil * math.max(0, 1 - dt * 9)
	flashTimer = math.max(0, flashTimer - dt)

	local show = visible and current and not hiddenByScope
	for _, model in pairs(models) do
		local parent = (model == current and show) and folder or nil
		for _, item in ipairs(model.pieces) do
			if item.part.Parent ~= parent then
				item.part.Parent = parent
			end
		end
	end

	local camCF = camera.CFrame

	-- Patada de camara (se aplica despues de que la camara se movio)
	if math.abs(camKick.X) > 0.00002 or math.abs(camKick.Y) > 0.00002 then
		local kicked = camCF * CFrame.Angles(camKick.X, camKick.Y, 0)
		camera.CFrame = kicked
		camCF = kicked
		camKick = camKick * math.max(0, 1 - dt * 9)
	end

	if not (current and show) then
		lastCamCF = camCF
		return
	end

	-- Inercia: el arma se atrasa un poco cuando giras la vista
	if lastCamCF then
		local look = camCF.LookVector
		local lastLook = lastCamCF.LookVector
		local yaw = math.atan2(look.X, look.Z) - math.atan2(lastLook.X, lastLook.Z)
		if yaw > math.pi then
			yaw = yaw - math.pi * 2
		elseif yaw < -math.pi then
			yaw = yaw + math.pi * 2
		end
		local pitch = math.asin(math.clamp(look.Y, -1, 1)) - math.asin(math.clamp(lastLook.Y, -1, 1))
		local interesting = Vector2.new(
			math.clamp(yaw * 6, -0.09, 0.09),
			math.clamp(pitch * 6, -0.09, 0.09))
		sway = sway:Lerp(interesting, math.min(dt * 9, 1))
	else
		sway = Vector2.new(0, 0)
	end

	-- Bamboleo al caminar
	local speed = 0
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if root then
		local v = root.AssemblyLinearVelocity
		speed = math.sqrt(v.X * v.X + v.Z * v.Z)
	end
	bobPhase = bobPhase + dt * (4 + speed * 0.85)
	local bobAmt = math.clamp(speed / 16, 0, 1) * (1 - ads * 0.75)
	local bobX = math.cos(bobPhase) * 0.05 * bobAmt
	local bobY = math.abs(math.sin(bobPhase)) * 0.045 * bobAmt

	local base = camCF * HIP:Lerp(ADS, ads)
		* CFrame.new(bobX + sway.X * 2.6, bobY + sway.Y * 2.2, recoil * 0.5)
	local final = base * CFrame.Angles(-sway.Y * 2.4 - recoil * 0.2, -sway.X * 2.4, recoilRoll * recoil * 2)

	for _, item in ipairs(current.pieces) do
		item.part.CFrame = final * item.cf
	end

	-- Fogonazo: se ve un instante al disparar
	if current.flash then
		if flashTimer > 0 then
			local s = 0.5 + math.random() * 0.4
			current.flash.Size = Vector3.new(0.72 * s, s, s)
			current.flash.Transparency = 0
		elseif current.flash.Transparency ~= 1 then
			current.flash.Transparency = 1
		end
	end

	lastCamCF = camCF
end

RunService:BindToRenderStep("KiwiVistaArmas", Enum.RenderPriority.Camera.Value + 1, stepUnbound)

return ViewModel
