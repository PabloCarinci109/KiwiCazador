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
local reparentDirty = true -- hay que reacomodar piezas (arma/visibilidad)
-- Animacion del cuchillo mariposa (estilo CS2): giro al equiparlo, F = inspeccion
local FX = { kind = nil, t = 0, dur = 0 }
local knifeOpen = 1    -- 1 = hoja abierta, 0 = plegada

-- Posicion del arma respecto de la camara (estilo Counter Blox: al costado,
-- bien abajo a la derecha y con una leve inclinacion, para no tapar la vista)
local HIP = CFrame.new(0.5, -1.25, -2.7) * CFrame.Angles(math.rad(1.5), math.rad(6), math.rad(-6))
-- Apuntando: el arma se corre al centro pero bien abajo, para que el
-- puntito de mira quede despejado (estilo Counter Blox)
local ADS = CFrame.new(0.05, -1.0, -2.35)
-- Poses de mira por arma: al apuntar ninguna tapa el puntito central.
-- El arco y el lanzamisiles son grandotes: se corren bien a la derecha.
local ADS_POSES = {
	arco = CFrame.new(0.58, -1.0, -2.05) * CFrame.Angles(0, math.rad(-10), math.rad(2)),
	cohete = CFrame.new(1.0, -1.4, -2.8) * CFrame.Angles(0, math.rad(-8), math.rad(2)),
	escopeta = CFrame.new(0.16, -1.02, -2.3),
	revolver = CFrame.new(0.12, -0.95, -2.2),
	lanzallamas = CFrame.new(0.4, -1.1, -2.45) * CFrame.Angles(0, math.rad(-6), 0),
}

-- ===============================================================
-- Construccion de las armas (cajas simples, estilo Counter)
-- ===============================================================
local function piece(model, size, cf, color, material, shape, anim)
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
	table.insert(model.pieces, { part = p, cf = cf, anim = anim })
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
	-- Mira de hierro: punto delantero y alza trasera
	piece(model, Vector3.new(0.09, 0.32, 0.09), CFrame.new(0, 0.32, -3.8), Color3.fromRGB(28, 30, 34))
	piece(model, Vector3.new(0.2, 0.2, 0.1), CFrame.new(0, 0.8, -0.22), Color3.fromRGB(28, 30, 34))
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
-- Flecha lista en la cuerda: se ve al apuntar y "sale" al disparar
	piece(model, Vector3.new(0.07, 0.07, 2.7), CFrame.new(-0.16, 0.02, -1.32), Color3.fromRGB(206, 178, 126), Enum.Material.Wood)
	piece(model, Vector3.new(0.12, 0.12, 0.26), CFrame.new(-0.16, 0.02, -2.72), Color3.fromRGB(206, 212, 222), Enum.Material.Metal)
	piece(model, Vector3.new(0.3, 0.03, 0.36), CFrame.new(-0.16, 0.02, -0.36), Color3.fromRGB(196, 74, 68), Enum.Material.Fabric)
	piece(model, Vector3.new(0.03, 0.3, 0.36), CFrame.new(-0.16, 0.02, -0.36), Color3.fromRGB(196, 74, 68), Enum.Material.Fabric)
	-- Mano/puño
	piece(model, Vector3.new(0.4, 0.5, 0.5), CFrame.new(0, 0, -0.6), Color3.fromRGB(120, 90, 58), Enum.Material.Fabric)
	model.muzzle = Vector3.new(-0.16, 0.02, -2.9)
	return model
end

-- Cuchillo mariposa estilo CS2: dos mangos de acero y la hoja que gira
-- sobre el pivote. El modelo se guarda ABIERTO; "closed" es el giro que
-- devuelve cada pieza a la pose plegada para las animaciones (apertura).
local function buildCuchillo()
	local model = { pieces = {} }
	local acero = Color3.fromRGB(206, 212, 222)
	local aceroOscuro = Color3.fromRGB(150, 156, 168)
	local pivote = { pivot = Vector3.new(0, -0.28, -0.40), closed = CFrame.Angles(math.rad(-180), 0, 0) }
	-- Mangos alineados (el de abajo esta en la mano)
	piece(model, Vector3.new(0.16, 0.95, 0.30), CFrame.new(-0.09, -0.765, -0.40), aceroOscuro)
	piece(model, Vector3.new(0.16, 0.95, 0.30), CFrame.new(0.09, -0.765, -0.40), aceroOscuro)
	piece(model, Vector3.new(0.30, 0.10, 0.32), CFrame.new(0, -0.28, -0.40), acero)
	-- Hoja (abre y cierra girando sobre el pivote)
	piece(model, Vector3.new(0.10, 1.15, 0.28), CFrame.new(0, 0.295, -0.40), acero, nil, nil, pivote)
	piece(model, Vector3.new(0.30, 0.30, 0.28), CFrame.new(0, 0.94, -0.40) * CFrame.Angles(0, 0, math.rad(45)), acero, nil, nil, pivote)
	piece(model, Vector3.new(0.10, 1.05, 0.10), CFrame.new(0.068, 0.275, -0.40), Color3.fromRGB(255, 255, 255), Enum.Material.Neon, nil, pivote)
	model.muzzle = Vector3.new(0, 1.12, -0.40)
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

-- Lanzamisiles estilo RPG: tubo grueso con el cohete asomando, empuñaduras
-- de madera y hombrera. Se tiene que ver GRANDE, nada de pistola.
local function buildCohete()
	local model = { pieces = {} }
	-- Tubo principal
	piece(model, Vector3.new(3.7, 0.72, 0.72), CFrame.new(0, 0.55, -1.0) * CFrame.Angles(0, math.rad(90), 0),
		Color3.fromRGB(88, 98, 68), nil, Enum.PartType.Cylinder)
	-- Campana trasera y refuerzo delantero
	piece(model, Vector3.new(0.55, 1.0, 1.0), CFrame.new(0, 0.55, 0.95) * CFrame.Angles(0, math.rad(90), 0),
		Color3.fromRGB(52, 58, 46), nil, Enum.PartType.Cylinder)
	piece(model, Vector3.new(0.5, 0.86, 0.86), CFrame.new(0, 0.55, -2.95) * CFrame.Angles(0, math.rad(90), 0),
		Color3.fromRGB(62, 70, 52), nil, Enum.PartType.Cylinder)
	-- Cohete asomando con ojiva roja
	piece(model, Vector3.new(1.2, 0.24, 0.24), CFrame.new(0, 0.55, -3.5) * CFrame.Angles(0, math.rad(90), 0),
		Color3.fromRGB(74, 78, 72), nil, Enum.PartType.Cylinder)
	piece(model, Vector3.new(0.6, 0.4, 0.4), CFrame.new(0, 0.55, -4.15) * CFrame.Angles(0, math.rad(90), 0),
		Color3.fromRGB(226, 96, 70), nil, Enum.PartType.Cylinder)
	piece(model, Vector3.new(0.4, 0.26, 0.26), CFrame.new(0, 0.55, -4.5) * CFrame.Angles(0, math.rad(90), 0),
		Color3.fromRGB(178, 58, 44), nil, Enum.PartType.Cylinder)
	-- Mira de hierro plegada
	piece(model, Vector3.new(0.09, 0.4, 0.09), CFrame.new(-0.15, 1.05, -2.1), Color3.fromRGB(42, 46, 40))
	piece(model, Vector3.new(0.09, 0.4, 0.09), CFrame.new(0.15, 1.05, -2.1), Color3.fromRGB(42, 46, 40))
	-- Empuñadura de pistola + guardamonte + empuñadura delantera
	piece(model, Vector3.new(0.3, 0.72, 0.44), CFrame.new(0, -0.02, -0.05) * CFrame.Angles(math.rad(-14), 0, 0),
		Color3.fromRGB(110, 76, 46), Enum.Material.Wood)
	piece(model, Vector3.new(0.12, 0.3, 0.5), CFrame.new(0, -0.2, -0.42), Color3.fromRGB(44, 46, 42))
	piece(model, Vector3.new(0.26, 0.62, 0.36), CFrame.new(0, -0.02, -1.5) * CFrame.Angles(math.rad(-10), 0, 0),
		Color3.fromRGB(110, 76, 46), Enum.Material.Wood)
	-- Hombrera trasera
	piece(model, Vector3.new(0.36, 0.8, 0.55), CFrame.new(0, 0.5, 1.4), Color3.fromRGB(60, 64, 54))
	model.muzzle = Vector3.new(0, 0.55, -4.7)
	return model
end

-- ===== Arsenal estilo Counter Blox =====
local function buildAK()
	return buildRifle(Color3.fromRGB(150, 96, 52), Color3.fromRGB(70, 74, 84))
end

local function buildM4()
	local model = buildRifle(Color3.fromRGB(72, 80, 94), Color3.fromRGB(90, 130, 190))
	-- M4A1 con silenciador: caño grueso y largo al frente del cañón
	piece(model, Vector3.new(0.42, 0.42, 0.22), CFrame.new(0, 0.06, -4.05), Color3.fromRGB(52, 55, 62))
	piece(model, Vector3.new(0.34, 0.34, 1.45), CFrame.new(0, 0.06, -4.88), Color3.fromRGB(30, 32, 36))
	piece(model, Vector3.new(0.4, 0.4, 0.16), CFrame.new(0, 0.06, -5.66), Color3.fromRGB(48, 50, 56))
	model.muzzle = Vector3.new(0, 0.06, -5.78)
	return model
end

local function buildMP5()
	local model = { pieces = {} }
	piece(model, Vector3.new(0.5, 0.6, 1.5), CFrame.new(0, -0.06, -0.3), Color3.fromRGB(60, 66, 76))
	piece(model, Vector3.new(0.22, 0.22, 1.3), CFrame.new(0, 0.2, -1.7), Color3.fromRGB(40, 44, 50))
	piece(model, Vector3.new(0.18, 0.18, 0.4), CFrame.new(0, 0.2, -2.4), Color3.fromRGB(30, 33, 38))
	piece(model, Vector3.new(0.34, 0.55, 0.5), CFrame.new(0, -0.55, 0.35) * CFrame.Angles(math.rad(-10), 0, 0), Color3.fromRGB(48, 52, 60))
	piece(model, Vector3.new(0.2, 0.45, 0.3), CFrame.new(0, -0.42, -0.5) * CFrame.Angles(math.rad(-14), 0, 0), Color3.fromRGB(44, 48, 54))
	piece(model, Vector3.new(0.26, 0.24, 0.7), CFrame.new(0, 0.36, -0.5), Color3.fromRGB(210, 160, 60))
	model.muzzle = Vector3.new(0, 0.2, -2.55)
	return model
end

local function buildGlock()
	local model = { pieces = {} }
	piece(model, Vector3.new(0.3, 0.42, 1.15), CFrame.new(0, 0.08, -0.55), Color3.fromRGB(58, 60, 68))
	piece(model, Vector3.new(0.26, 0.52, 0.44), CFrame.new(0, -0.34, -0.02) * CFrame.Angles(math.rad(-8), 0, 0), Color3.fromRGB(46, 48, 54))
	piece(model, Vector3.new(0.5, 0.14, 0.14), CFrame.new(0, 0.08, -1.35) * CFrame.Angles(0, math.rad(90), 0),
		Color3.fromRGB(80, 84, 94), nil, Enum.PartType.Cylinder)
	piece(model, Vector3.new(0.1, 0.1, 0.1), CFrame.new(0, 0.33, -0.95), Color3.fromRGB(236, 238, 244), Enum.Material.SmoothPlastic)
	model.muzzle = Vector3.new(0, 0.08, -1.6)
	return model
end

local function buildEscopeta()
	local model = { pieces = {} }
	piece(model, Vector3.new(0.36, 0.5, 1.4), CFrame.new(0, -0.1, 1.1), Color3.fromRGB(118, 80, 50), Enum.Material.Wood)
	piece(model, Vector3.new(0.34, 0.5, 1.3), CFrame.new(0, 0, -0.35), Color3.fromRGB(66, 70, 76))
	piece(model, Vector3.new(2.4, 0.22, 0.22), CFrame.new(0, 0.16, -1.75) * CFrame.Angles(0, math.rad(90), 0),
		Color3.fromRGB(52, 54, 60), nil, Enum.PartType.Cylinder)
	piece(model, Vector3.new(0.34, 0.28, 0.9), CFrame.new(0, -0.16, -1.55), Color3.fromRGB(96, 74, 52), Enum.Material.Wood)
	piece(model, Vector3.new(0.22, 0.22, 0.6), CFrame.new(0, -0.05, -0.9), Color3.fromRGB(58, 62, 68))
	model.muzzle = Vector3.new(0, 0.16, -3.0)
	return model
end

-- Granadas del pack de los baúles (se ven en la mano y se lanzan con clic)
local function buildFrag()
	local model = { pieces = {} }
	piece(model, Vector3.new(0.46, 0.56, 0.46), CFrame.new(0, 0, 0), Color3.fromRGB(110, 122, 84))
	piece(model, Vector3.new(0.14, 0.14, 0.14), CFrame.new(0, 0.34, 0), Color3.fromRGB(64, 68, 54))
	piece(model, Vector3.new(0.4, 0.06, 0.08), CFrame.new(0.1, 0.34, 0), Color3.fromRGB(190, 192, 198))
	model.muzzle = Vector3.new(0, 0.3, -0.2)
	return model
end

local function buildHumo()
	local model = { pieces = {} }
	piece(model, Vector3.new(0.4, 0.62, 0.4), CFrame.new(0, 0, 0), Color3.fromRGB(148, 156, 164))
	piece(model, Vector3.new(0.16, 0.1, 0.16), CFrame.new(0, 0.36, 0), Color3.fromRGB(96, 102, 110))
	piece(model, Vector3.new(0.44, 0.06, 0.44), CFrame.new(0, 0.1, 0), Color3.fromRGB(120, 190, 220), Enum.Material.SmoothPlastic)
	piece(model, Vector3.new(0.44, 0.06, 0.44), CFrame.new(0, -0.14, 0), Color3.fromRGB(120, 190, 220), Enum.Material.SmoothPlastic)
	model.muzzle = Vector3.new(0, 0.3, -0.2)
	return model
end

local function buildMolotov()
	local model = { pieces = {} }
	piece(model, Vector3.new(0.34, 0.7, 0.34), CFrame.new(0, 0, 0), Color3.fromRGB(196, 108, 54))
	piece(model, Vector3.new(0.16, 0.24, 0.16), CFrame.new(0, 0.46, 0), Color3.fromRGB(168, 92, 46))
	piece(model, Vector3.new(0.26, 0.26, 0.26), CFrame.new(0, 0.7, 0), Color3.fromRGB(255, 176, 70), Enum.Material.Neon)
	model.muzzle = Vector3.new(0, 0.5, -0.2)
	return model
end

local function buildFlash()
	local model = { pieces = {} }
	piece(model, Vector3.new(0.38, 0.6, 0.38), CFrame.new(0, 0, 0), Color3.fromRGB(206, 208, 214))
	piece(model, Vector3.new(0.3, 0.16, 0.3), CFrame.new(0, 0.38, 0), Color3.fromRGB(120, 124, 132))
	piece(model, Vector3.new(0.12, 0.12, 0.12), CFrame.new(0, 0.52, 0), Color3.fromRGB(90, 94, 102))
	model.muzzle = Vector3.new(0, 0.4, -0.2)
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
	-- Arsenal Counter Blox
	ak = buildAK,
	m4 = buildM4,
	mp5 = buildMP5,
	glock = buildGlock,
	escopeta = buildEscopeta,
	-- Granadas del pack de los baúles
	frag = buildFrag,
	humo = buildHumo,
	molotov = buildMolotov,
	flash = buildFlash,
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
		folder:Destroy()
		folder = nil
		models = {}
		current = nil
		currentId = nil
		reparentDirty = true
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
		if currentId then
			reparentDirty = true
		end
		currentId = nil
		current = nil
		return
	end
	if id == currentId then
		return
	end
	reparentDirty = true
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
	-- Al sacar el cuchillo mariposa se abre con un giro (estilo CS2)
	if id == "cuchillo" then
		FX = { kind = "draw", t = 0, dur = 0.75 }
		knifeOpen = 0
	end
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
	value = value and true or false
	if visible ~= value then
		visible = value
		reparentDirty = true
	end
end

function ViewModel.setAds(goal)
	adsGoal = math.clamp(goal or 0, 0, 1)
end

function ViewModel.setHidden(value)
	value = value and true or false
	if hiddenByScope ~= value then
		hiddenByScope = value
		reparentDirty = true
	end
end

function ViewModel.recoil(amount)
	recoil = math.min(1.2, recoil + (amount or 0.5))
	recoilRoll = (math.random() * 2 - 1) * 0.13 * (amount or 0.5)
end

-- Patada de camara estilo Counter Blox: sube de golpe y vuelve sola
function ViewModel.kickCamera(pitch, yaw)
	camKick = Vector2.new(camKick.X + (pitch or 0), camKick.Y + (yaw or 0))
end

function ViewModel.flash()
	flashTimer = 0.055
end

-- Inspeccion (tecla F): la mariposa da dos vueltas en la mano
function ViewModel.spin()
	if currentId == "cuchillo" and visible and not hiddenByScope then
		FX = { kind = "inspect", t = 0, dur = 1.1 }
	end
end

-- Zarpazo: el cuchillo barre de costado al atacar
function ViewModel.slash()
	if currentId == "cuchillo" and visible and not hiddenByScope then
		FX = { kind = "slash", t = 0, dur = 0.24 }
	end
end

-- Lanzar granada: el brazo va para adelante y suelta la granada
function ViewModel.toss()
	if visible and not hiddenByScope then
		FX = { kind = "toss", t = 0, dur = 0.3 }
	end
end

function ViewModel.hasWeapon(id)
	return BUILDERS[id or currentId] ~= nil
end

function ViewModel.getMuzzle()
	local camera = workspace.CurrentCamera
	if not camera or not current then
		return nil
	end
	local base = camera.CFrame * HIP:Lerp(ADS_POSES[currentId] or ADS, ads)
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
	recoil = recoil * math.max(0, 1 - dt * 10)
	flashTimer = math.max(0, flashTimer - dt)

	local show = visible and current and not hiddenByScope
	-- Reacomodar piezas SOLO cuando algo cambio (no recorrer todo cada frame)
	if reparentDirty then
		reparentDirty = false
		for _, model in pairs(models) do
			local parent = (model == current and show) and folder or nil
			for _, item in ipairs(model.pieces) do
				if item.part.Parent ~= parent then
					item.part.Parent = parent
				end
			end
		end
	end

	local camCF = camera.CFrame

	-- Patada de camara (se aplica despues de que la camara se movio)
	if math.abs(camKick.X) > 0.00002 or math.abs(camKick.Y) > 0.00002 then
		local kicked = camCF * CFrame.Angles(camKick.X, camKick.Y, 0)
		camera.CFrame = kicked
		camCF = kicked
		camKick = camKick * math.max(0, 1 - dt * 10.5)
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

	local base = camCF * HIP:Lerp(ADS_POSES[currentId] or ADS, ads)
		* CFrame.new(bobX + sway.X * 2.6, bobY + sway.Y * 2.2, recoil * 0.4)
	local final = base * CFrame.Angles(-sway.Y * 2.4 - recoil * 0.14, -sway.X * 2.4, recoilRoll * recoil * 1.3)

	-- Animacion del cuchillo mariposa: apertura al equipar, giro (F) y zarpazo
	local animCF = nil
	if FX.kind then
		FX.t = FX.t + dt
		local raw = math.clamp(FX.t / FX.dur, 0, 1)
		if FX.kind == "draw" then
			local e = 1 - (1 - raw) ^ 2.4
			animCF = CFrame.Angles(0, 0, math.rad(360) * (1 - e))
				* CFrame.new(0, 0.16 * math.sin(math.pi * e), 0.14 * math.sin(math.pi * e))
			knifeOpen = math.clamp(e * 1.6, 0, 1)
		elseif FX.kind == "slash" then
			local swipe = math.sin(math.pi * raw)
			animCF = CFrame.Angles(math.rad(-16 * swipe), math.rad(-150 * swipe), math.rad(30 * swipe))
				* CFrame.new(0, 0.05 * swipe, -0.35 * swipe)
		elseif FX.kind == "toss" then
			-- Tiro de granada: el brazo sube y va para adelante
			local swipe = math.sin(math.pi * raw)
			animCF = CFrame.Angles(math.rad(-52 * swipe), 0, math.rad(-18 * swipe))
				* CFrame.new(0, 0.12 * swipe, -0.5 * swipe)
		elseif FX.kind == "inspect" then
			local e = raw * raw * (3 - 2 * raw)
			animCF = CFrame.Angles(0, 0, math.rad(720) * (1 - e))
				* CFrame.new(0, 0.12 * math.sin(math.pi * raw), 0)
		end
		if raw >= 1 then
			FX.kind = nil
		end
	end
	-- Si un zarpazo interrumpio la apertura, la hoja termina de abrirse sola
	if FX.kind ~= "draw" and knifeOpen < 1 then
		knifeOpen = math.min(1, knifeOpen + dt * 5)
	end

	local posed = animCF and final * animCF or final
	for _, item in ipairs(current.pieces) do
		local cf = item.cf
		local anim = item.anim
		if anim and knifeOpen < 1 then
			local rot = anim.closed:Lerp(CFrame.new(), knifeOpen)
			cf = CFrame.new(anim.pivot) * rot * CFrame.new(-anim.pivot) * cf
		end
		item.part.CFrame = posed * cf
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
