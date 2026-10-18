--[[
	WorldBuilder.lua  (servidor)
	Genera TODO el mapa por codigo: el lobby, las arenas y los
	escondites del kiwi. No hace falta construir nada en Studio.

	Cada arena devuelve una tabla con:
		center, halfSize, floorY, folder, ground, propsFolder,
		spots   -> lista de escondites
		spawns  -> CFrames donde aparecen los jugadores
		kiwiSpawn, bounds, clampToBounds()
--]]

local Shared = require(script.Parent.Shared)
local Util = require(Shared.Util)

local WorldBuilder = {}

local Arena = {}
Arena.__index = Arena

local function clamp(v, min, max)
	if v < min then return min end
	if v > max then return max end
	return v
end

function Arena:clampToBounds(pos)
	local pad = 26
	local minX = self.center.X - self.halfSize + pad
	local maxX = self.center.X + self.halfSize - pad
	local minZ = self.center.Z - self.halfSize + pad
	local maxZ = self.center.Z + self.halfSize - pad
	return Vector3.new(clamp(pos.X, minX, maxX), pos.Y, clamp(pos.Z, minZ, maxZ))
end

function Arena:randomPoint(rng, margin)
	local m = margin or (self.halfSize - 30)
	local angle = rng:NextNumber(0, math.pi * 2)
	local radius = rng:NextNumber(15, m)
	return self:clampToBounds(self.center + Vector3.new(math.cos(angle) * radius, 0, math.sin(angle) * radius))
end

-- Escondite mas cercano a un punto (para saber donde "buscar" con la red)
function Arena:nearestSpot(position, maxDistance)
	local best, bestDist = nil, maxDistance or math.huge
	for _, spot in ipairs(self.spots) do
		local d = (spot.hidePoint - position).Magnitude
		if d < bestDist then
			best, bestDist = spot, d
		end
	end
	return best, bestDist
end

-- ===============================================================
-- Helpers de construccion
-- ===============================================================
local function part(props)
	return Util.makeSolid(props)
end

local function makeRustle(parentPart, color)
	local emitter = Instance.new("ParticleEmitter")
	emitter.Name = "Rustle"
	emitter.Texture = "rbxasset://textures/particles/sparkles_main.dds"
	emitter.Color = ColorSequence.new(color or Color3.fromRGB(120, 160, 90))
	emitter.LightEmission = 0.2
	emitter.Size = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.6),
		NumberSequenceKeypoint.new(1, 0.05),
	})
	emitter.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.35),
		NumberSequenceKeypoint.new(1, 1),
	})
	emitter.Lifetime = NumberRange.new(0.45, 0.9)
	emitter.Speed = NumberRange.new(4, 9)
	emitter.SpreadAngle = Vector2.new(60, 60)
	emitter.Rate = 14
	emitter.Rotation = NumberRange.new(0, 360)
	emitter.RotSpeed = NumberRange.new(-90, 90)
	emitter.Enabled = false
	emitter.Parent = parentPart
	return emitter
end

local function billboardText(adornee, text, color, size)
	local gui = Instance.new("BillboardGui")
	gui.Name = "Letrero"
	gui.Size = UDim2.fromScale(size or 14, (size or 14) * 0.28)
	gui.StudsOffsetWorldSpace = Vector3.new(0, 4, 0)
	gui.AlwaysOnTop = false
	gui.MaxDistance = 320
	gui.Adornee = adornee
	gui.Parent = adornee

	local label = Instance.new("TextLabel")
	label.Size = UDim2.fromScale(1, 1)
	label.BackgroundTransparency = 1
	label.Font = Enum.Font.GothamBold
	label.TextScaled = true
	label.TextColor3 = color or Color3.fromRGB(240, 240, 240)
	label.TextStrokeTransparency = 0.35
	label.Text = text
	label.Parent = gui
	return gui
end

-- ===============================================================
-- LOBBY
-- ===============================================================
local function buildLobby(cfg, parent, rng)
	local size = cfg.Lobby.Size
	local lobby = { folder = Instance.new("Folder") }
	lobby.folder.Name = "Lobby"
	lobby.folder.Parent = parent

	local floor = part({
		Name = "PisoLobby",
		Size = Vector3.new(size * 2, 6, size * 2),
		Position = Vector3.new(0, cfg.World.FloorY - 3, 0),
		Color = Color3.fromRGB(120, 128, 132),
		Material = Enum.Material.Cobblestone,
		CanCollide = true,
		Parent = lobby.folder,
	})
	lobby.floor = floor

	-- Borde de madera
	for i = 0, 3 do
		local angle = i * math.pi * 0.5
		part({
			Name = "Borde",
			Size = Vector3.new(size * 2 + 6, 3, 4),
			CFrame = CFrame.new(0, cfg.World.FloorY + 1.5, 0) * CFrame.Angles(0, angle, 0) * CFrame.new(0, 0, -size),
			Color = Color3.fromRGB(96, 70, 48),
			Material = Enum.Material.WoodPlanks,
			CanCollide = true,
			Parent = lobby.folder,
		})
	end

	-- Spawn de los jugadores
	local spawnLocation = Instance.new("SpawnLocation")
	spawnLocation.Name = "SpawnLobby"
	spawnLocation.Size = Vector3.new(16, 1, 16)
	spawnLocation.CFrame = CFrame.new(cfg.Lobby.SpawnOffset)
	spawnLocation.Anchored = true
	spawnLocation.CanCollide = true
	spawnLocation.TopSurface = Enum.SurfaceType.Smooth
	spawnLocation.Material = Enum.Material.WoodPlanks
	spawnLocation.Color = Color3.fromRGB(150, 120, 80)
	spawnLocation.Neutral = true
	spawnLocation.Duration = 0
	spawnLocation.Transparency = 0.25
	spawnLocation.Parent = lobby.folder
	lobby.spawn = CFrame.new(cfg.Lobby.SpawnOffset + Vector3.new(0, 4, 0))
	lobby.spawnLocation = spawnLocation

	-- Cartel principal
	local board = part({
		Name = "Cartel",
		Size = Vector3.new(46, 14, 1.4),
		CFrame = CFrame.new(0, cfg.World.FloorY + 16, -52),
		Color = Color3.fromRGB(38, 34, 30),
		Material = Enum.Material.WoodPlanks,
		Parent = lobby.folder,
	})
	part({
		Name = "PosteI",
		Size = Vector3.new(2, 18, 2),
		CFrame = CFrame.new(-18, cfg.World.FloorY + 8, -52),
		Color = Color3.fromRGB(72, 54, 38),
		Material = Enum.Material.Wood,
		CanCollide = true,
		Parent = lobby.folder,
	})
	part({
		Name = "PosteD",
		Size = Vector3.new(2, 18, 2),
		CFrame = CFrame.new(18, cfg.World.FloorY + 8, -52),
		Color = Color3.fromRGB(72, 54, 38),
		Material = Enum.Material.Wood,
		CanCollide = true,
		Parent = lobby.folder,
	})

	local surface = Instance.new("SurfaceGui")
	surface.Face = Enum.NormalId.Front
	surface.CanvasSize = Vector2.new(460, 140)
	surface.LightInfluence = 0.4
	surface.Parent = board

	local title = Instance.new("TextLabel")
	title.Size = UDim2.fromScale(1, 0.62)
	title.BackgroundTransparency = 1
	title.Font = Enum.Font.GothamBlack
	title.TextScaled = true
	title.TextColor3 = Color3.fromRGB(240, 235, 225)
	title.Text = "KIWI CAZADOR"
	title.Parent = surface

	local subtitle = Instance.new("TextLabel")
	subtitle.Position = UDim2.fromScale(0, 0.62)
	subtitle.Size = UDim2.fromScale(1, 0.3)
	subtitle.BackgroundTransparency = 1
	subtitle.Font = Enum.Font.Gotham
	subtitle.TextScaled = true
	subtitle.TextColor3 = Color3.fromRGB(150, 210, 160)
	subtitle.Text = cfg.GameTagline
	subtitle.Parent = surface

	-- Decoracion: unos kauris y helechos alrededor
	for i = 1, 10 do
		local angle = (i / 10) * math.pi * 2
		local radius = size + 12 + rng:NextNumber(0, 10)
		local pos = Vector3.new(math.cos(angle) * radius, cfg.World.FloorY, math.sin(angle) * radius)
		local height = rng:NextNumber(26, 40)
		part({
			Name = "Tronco",
			Size = Vector3.new(3.2, height, 3.2),
			Position = pos + Vector3.new(0, height * 0.5 - 1, 0),
			Color = Color3.fromRGB(84, 60, 44),
			Material = Enum.Material.Wood,
			Parent = lobby.folder,
		})
		for leaf = 1, 3 do
			local leafSize = 18 - leaf * 3
			part({
				Name = "Copa",
				Shape = Enum.PartType.Ball,
				Size = Vector3.new(leafSize, leafSize * 0.7, leafSize),
				Position = pos + Vector3.new(0, height - 4 + leaf * 3, 0),
				Color = Color3.fromRGB(58 + leaf * 4, 104 + leaf * 5, 62),
				Material = Enum.Material.LeafyGrass,
				Parent = lobby.folder,
			})
		end
	end

	return lobby
end

-- ===============================================================
-- ARENAS
-- ===============================================================
local function buildArena(index, zone, cfg, parent, rng)
	local self = setmetatable({}, Arena)
	self.index = index
	self.name = zone.name
	self.mapId = zone.id or ("map" .. index)
	self.zone = zone
	self.center = Vector3.new(index * cfg.World.ArenaSpacing, cfg.World.FloorY, 0)
	self.halfSize = cfg.World.ArenaSize * 0.5
	self.floorY = cfg.World.FloorY
	self.spots = {}
	self.spawns = {}
	self.indoors = {}
	self.enterList = {}
	self.chests = {}
	self.busy = false
	self.traffic = {}      -- autos, colectivo y tren (mapa Ciudad)
	self.semaphores = {}   -- semaforos que cambian de luz

	local folder = Instance.new("Folder")
	folder.Name = "Arena" .. index
	folder.Parent = parent
	self.folder = folder

	local props = Instance.new("Folder")
	props.Name = "Props"
	props.Parent = folder
	self.propsFolder = props

	local half = self.halfSize
	local center = self.center
	local floorY = self.floorY

	local function local3(dx, dz, y)
		return center + Vector3.new(dx, (y or 0), dz)
	end

	-- ---------------- Suelo ----------------
	self.ground = part({
		Name = "Terreno",
		Size = Vector3.new(half * 2, 10, half * 2),
		Position = center + Vector3.new(0, -5, 0),
		Color = zone.grass,
		Material = zone.ground or Enum.Material.LeafyGrass,
		CanCollide = true,
		Parent = folder,
	})

	-- ---------------- Limites ----------------
	for i = 0, 3 do
		part({
			Name = "MuroInvisible",
			Size = Vector3.new(half * 2 + 8, 40, 3),
			CFrame = CFrame.new(center + Vector3.new(0, 19, 0))
				* CFrame.Angles(0, i * math.pi * 0.5, 0)
				* CFrame.new(0, 0, -half),
			Transparency = 1,
			CanCollide = true,
			CanQuery = true,
			Parent = folder,
		})
	end

	-- ---------------- Limites del mapa (no se puede salir) ----------------
	-- Ciudad: murallones tipo edificio. Duna/naturaleza: montañas y arboles.
	local theme = zone.theme or "bosque"

	if theme == "ciudad" then
		-- Muralla de edificio alrededor de toda la manzana
		local wallH = 48
		local wallCol = Color3.fromRGB(148, 148, 152)
		local wallTrim = Color3.fromRGB(110, 112, 118)
		local glassCol = Color3.fromRGB(96, 132, 148)
		for i = 0, 3 do
			local side = CFrame.new(center) * CFrame.Angles(0, i * math.pi * 0.5, 0)
			part({
				Name = "MuroCiudad",
				Size = Vector3.new(half * 2 + 10, wallH, 5),
				CFrame = side * CFrame.new(0, wallH * 0.5, -half + 4),
				Color = wallCol,
				Material = Enum.Material.Concrete,
				CanCollide = true,
				Parent = props,
			})
			part({
				Name = "CornisaCiudad",
				Size = Vector3.new(half * 2 + 12, 2.4, 6.6),
				CFrame = side * CFrame.new(0, wallH + 1, -half + 4),
				Color = wallTrim,
				Material = Enum.Material.Concrete,
				CanCollide = true,
				Parent = props,
			})
			-- Tiras de ventanas (dos pisos de oficinas)
			for row = 0, 1 do
				for w = -6, 6 do
					local wx = w * 40
					if math.abs(wx) < half - 20 then
						part({
							Name = "VentanaCiudad",
							Size = Vector3.new(26, 9, 0.6),
							CFrame = side * CFrame.new(wx, 14 + row * 17, -half + 6.6),
							Color = glassCol,
							Material = Enum.Material.Glass,
							CanCollide = false,
							Parent = props,
						})
					end
				end
			end
		end
		-- Torres en las esquinas
		for sx = -1, 1, 2 do
			for sz = -1, 1, 2 do
				part({
					Name = "TorreEsquina",
					Size = Vector3.new(18, 62, 18),
					CFrame = CFrame.new(center + Vector3.new(sx * (half - 8), 31, sz * (half - 8))),
					Color = wallTrim,
					Material = Enum.Material.Concrete,
					CanCollide = true,
					Parent = props,
				})
			end
		end
		-- Skyline: edificios de fondo (afuera del area jugable)
		for i = 1, 16 do
			local a = (i / 16) * math.pi * 2
			local dist = half + rng:NextNumber(55, 130)
			local h = rng:NextNumber(70, 170)
			local w = rng:NextNumber(30, 56)
			part({
				Name = "Skyline",
				Size = Vector3.new(w, h, w),
				CFrame = CFrame.new(center + Vector3.new(math.cos(a) * dist, h * 0.5 - 6, math.sin(a) * dist)),
				Color = i % 3 == 0 and Color3.fromRGB(96, 102, 116) or Color3.fromRGB(74, 78, 90),
				Material = Enum.Material.Concrete,
				CanCollide = false,
				Parent = props,
			})
		end
	else
		-- Montañas de roca que cierran el mapa
		local palettes = {
			bosque = { Color3.fromRGB(92, 100, 84), Color3.fromRGB(112, 116, 98), Color3.fromRGB(74, 118, 72), Enum.Material.LeafyGrass },
			dunas = { Color3.fromRGB(188, 156, 106), Color3.fromRGB(208, 178, 128), Color3.fromRGB(226, 200, 148), Enum.Material.Sand },
			costa = { Color3.fromRGB(108, 98, 86), Color3.fromRGB(130, 118, 102), Color3.fromRGB(104, 122, 92), Enum.Material.Ground },
			alpes = { Color3.fromRGB(112, 120, 132), Color3.fromRGB(138, 148, 160), Color3.fromRGB(238, 244, 252), Enum.Material.Snow },
		}
		local pal = palettes[theme] or palettes.bosque
		local snowy = theme == "alpes"
		local sideLen = half * 2
		local count = math.floor(sideLen / 26)
		local ringDist = half - 9
		for side = 0, 3 do
			local sideCF = CFrame.new(center) * CFrame.Angles(0, side * math.pi * 0.5, 0)
			for i = 1, count do
				local x = -half + (i - 0.5) * (sideLen / count) + rng:NextNumber(-3, 3)
				local base = sideCF * CFrame.new(x, 0, -(ringDist + rng:NextNumber(-2, 4)))
				local h = rng:NextNumber(22, 48)
				local w = rng:NextNumber(26, 42)
				local d = rng:NextNumber(14, 22)
				part({
					Name = "Montana",
					Size = Vector3.new(w, h, d),
					CFrame = base * CFrame.new(0, h * 0.5 - 2, 0)
						* CFrame.Angles(rng:NextNumber(-0.08, 0.08), rng:NextNumber(-0.12, 0.12), rng:NextNumber(-0.08, 0.08)),
					Color = i % 2 == 0 and pal[1] or pal[2],
					Material = Enum.Material.Rock,
					CanCollide = true,
					Parent = props,
				})
				if snowy and i % 2 == 0 then
					part({
						Name = "NieveMontana",
						Size = Vector3.new(w * 0.68, h * 0.3, d * 0.68),
						CFrame = base * CFrame.new(0, h - h * 0.12 - 2, 0),
						Color = Color3.fromRGB(240, 246, 252),
						Material = Enum.Material.Snow,
						CanCollide = false,
						Parent = props,
					})
				end
			end
		end
		-- Esquinas montañosas (sin huecos)
		for sx = -1, 1, 2 do
			for sz = -1, 1, 2 do
				part({
					Name = "MontanaEsquina",
					Size = Vector3.new(44, 48, 44),
					CFrame = CFrame.new(center + Vector3.new(sx * (half - 8), 21, sz * (half - 8))),
					Color = pal[2],
					Material = Enum.Material.Rock,
					CanCollide = true,
					Parent = props,
				})
			end
		end
		-- Picos de fondo (paisaje)
		for i = 1, 14 do
			local a = (i / 14) * math.pi * 2 + rng:NextNumber(-0.1, 0.1)
			local dist = half + rng:NextNumber(50, 140)
			local size = rng:NextNumber(110, 210)
			part({
				Name = "PicoFondo",
				Shape = Enum.PartType.Ball,
				Size = Vector3.new(size, size * rng:NextNumber(0.8, 1.2), size),
				Position = center + Vector3.new(math.cos(a) * dist, -size * 0.28, math.sin(a) * dist),
				Color = pal[3],
				Material = pal[4],
				CanCollide = false,
				Parent = props,
			})
		end
		-- En el bosque ademas hay una linea de kauris gigantes
		if theme == "bosque" then
			for i = 1, 26 do
				local a = (i / 26) * math.pi * 2 + rng:NextNumber(-0.06, 0.06)
				local dist = half - 22 + rng:NextNumber(-6, 6)
				local pos = center + Vector3.new(math.cos(a) * dist, 0, math.sin(a) * dist)
				local hh = rng:NextNumber(40, 62)
				part({
					Name = "KauriGigante",
					Size = Vector3.new(4.4, hh, 4.4),
					Position = pos + Vector3.new(0, hh * 0.5, 0),
					Color = zone.tree,
					Material = Enum.Material.Wood,
					CanCollide = true,
					Parent = props,
				})
				part({
					Name = "CopaKauri",
					Shape = Enum.PartType.Ball,
					Size = Vector3.new(26, 20, 26),
					Position = pos + Vector3.new(0, hh + 6, 0),
					Color = Color3.fromRGB(58, 104, 60),
					Material = Enum.Material.LeafyGrass,
					CanCollide = false,
					Parent = props,
				})
			end
		end
	end

	-- ---------------- Colinas suaves (arena, nieve y medanos) ----------------
	if zone.theme ~= "ciudad" then
		for i = 1, 3 do
			local angle = rng:NextNumber(0, math.pi * 2)
			local radius = rng:NextNumber(half * 0.35, half * 0.7)
			local hillSize = rng:NextNumber(70, 110)
			part({
				Name = "Colina",
				Shape = Enum.PartType.Ball,
				Size = Vector3.new(hillSize, hillSize * 0.9, hillSize),
				Position = center + Vector3.new(math.cos(angle) * radius, -hillSize * 0.32, math.sin(angle) * radius),
				Color = Color3.fromRGB(zone.grass.R * 240, zone.grass.G * 240, zone.grass.B * 240),
				Material = zone.ground or Enum.Material.Ground,
				Parent = props,
			})
		end
	end

	-- ---------------- Agua del mapa (con fondo y borde de piedra) ----------------
	local pondCfg = zone.pond
	if pondCfg ~= false then
		local water = pondCfg or {}
		local scale = water.scale or 1
		local angle = rng:NextNumber(0, math.pi * 2)
		local radius = rng:NextNumber(half * 0.25, half * 0.55)
		local pondPos = center + Vector3.new(math.cos(angle) * radius, 0, math.sin(angle) * radius)
		local pondR = 26 * scale
		local icy = zone.theme == "alpes"

		-- Fondo (para que no se vea el pasto a traves del agua)
		part({
			Name = "FondoEstanque",
			Shape = Enum.PartType.Cylinder,
			Size = Vector3.new(0.5, pondR * 2 - 1.2, pondR * 2 - 1.2),
			CFrame = CFrame.new(pondPos + Vector3.new(0, 0.06, 0)) * CFrame.Angles(0, 0, math.rad(90)),
			Color = icy and Color3.fromRGB(178, 200, 214) or Color3.fromRGB(56, 66, 70),
			Material = icy and Enum.Material.Ice or Enum.Material.Slate,
			CanCollide = false,
			Parent = props,
		})

		-- Espejo de agua finito (antes era un cilindro grueso que parecia flotar)
		local pond = part({
			Name = "Estanque",
			Shape = Enum.PartType.Cylinder,
			Size = Vector3.new(0.6, pondR * 2, pondR * 2),
			CFrame = CFrame.new(pondPos + Vector3.new(0, 0.42, 0)) * CFrame.Angles(0, 0, math.rad(90)),
			Color = water.color or Color3.fromRGB(64, 122, 150),
			Material = water.material or Enum.Material.Water,
			Transparency = 0.25,
			CanCollide = false,
			Parent = props,
		})

		-- Borde de piedras: contiene el agua y se ve natural
		local rimColor = icy and Color3.fromRGB(212, 226, 236) or Color3.fromRGB(122, 118, 110)
		local rimMaterial = icy and Enum.Material.Ice or Enum.Material.Rock
		local rimCount = math.clamp(math.floor(pondR / 3), 10, 22)
		for i = 1, rimCount do
			local a = (i - 1) / rimCount * math.pi * 2 + rng:NextNumber(-0.08, 0.08)
			local size = rng:NextNumber(2.6, 4.8)
			part({
				Name = "BordeEstanque",
				Size = Vector3.new(size, rng:NextNumber(1.4, 2.6), size),
				CFrame = CFrame.new(pondPos + Vector3.new(math.cos(a) * (pondR - 1.4), 0.5, math.sin(a) * (pondR - 1.4)))
					* CFrame.Angles(0, rng:NextNumber(0, math.pi * 2), 0),
				Color = rimColor,
				Material = rimMaterial,
				CanCollide = true,
				Parent = props,
			})
		end

		for i = 1, 10 do
			local a = rng:NextNumber(0, math.pi * 2)
			part({
				Name = "Junco",
				Size = Vector3.new(0.5, rng:NextNumber(4, 7), 0.5),
				Position = pondPos + Vector3.new(math.cos(a) * (pondR + 2.5), 2.5, math.sin(a) * (pondR + 2.5)),
				Color = Color3.fromRGB(110, 132, 74),
				Material = Enum.Material.Grass,
				Parent = props,
			})
		end
		pond.CanQuery = true
	end

	-- ===============================================================
	-- Constructores de props / escondites
	-- ===============================================================
	local function addSpot(kind, name, mainPart, hidePoint, radius, cover)
		local point = Vector3.new(hidePoint.X, math.max(floorY + 0.1, hidePoint.Y or floorY), hidePoint.Z)

		-- Anclaje invisible en el punto exacto donde se mete el kiwi: ahi
		-- viven las particulas de "algo se mueve entre las hojas".
		local anchor = part({
			Name = "RustleAnchor",
			Size = Vector3.new(1, 1, 1),
			Position = point,
			Transparency = 1,
			CanCollide = false,
			CanQuery = false,
			Parent = props,
		})

		local spot = {
			id = #self.spots + 1,
			arena = self,
			kind = kind,
			name = name,
			hidePoint = point,
			radius = radius,
			cover = cover,
			part = mainPart,
			anchor = anchor,
		}
		spot.emitter = makeRustle(anchor)
		table.insert(self.spots, spot)
		return spot
	end

	--[[
		Escondite en el que el JUGADOR puede meterse (armario, barril, pajar):
		ademas del escondite del kiwi guarda como entrar, salir y la puerta.
	]]
	local function registerEnter(spot, opts)
		spot.enter = {
			inside = opts.inside,
			exit = opts.exit,
			door = opts.door,
			doorClosed = opts.doorClosed,
			doorOpen = opts.doorOpen,
			wobble = opts.wobble,
			wobbleCF = opts.wobble and opts.wobble.CFrame or nil,
			label = opts.label or "Escondite",
		}
		local prompt = Instance.new("ProximityPrompt")
		prompt.Name = "EntrarEscondite"
		prompt.ActionText = "Esconderse"
		prompt.ObjectText = spot.enter.label
		prompt.KeyboardKeyCode = Enum.KeyCode.E
		prompt.HoldDuration = 0
		prompt.MaxActivationDistance = 10
		prompt.RequiresLineOfSight = false
		prompt.Parent = opts.anchorPart or spot.part
		spot.enter.prompt = prompt
		spot.enterIndex = #self.enterList + 1
		table.insert(self.enterList, spot)
		return spot
	end

	-- Zona de interior: dentro de una casa el kiwi te huele menos
	local function addIndoor(cf, size)
		table.insert(self.indoors, { cf = cf, size = size })
	end

	-- Arbusto (escondite clasico)
	local function makeBush(pos, scale)
		scale = scale or rng:NextNumber(0.9, 1.35)
		local green = Color3.fromRGB(62 + rng:NextInteger(-8, 12), 112 + rng:NextInteger(-10, 14), 66)
		local main
		for i = 1, 4 do
			local ballSize = rng:NextNumber(4.5, 7) * scale
			local offset = Vector3.new(rng:NextNumber(-2.4, 2.4), rng:NextNumber(0.6, 2.2), rng:NextNumber(-2.4, 2.4)) * scale
			local ball = part({
				Name = "Arbusto",
				Shape = Enum.PartType.Ball,
				Size = Vector3.new(ballSize, ballSize * 0.85, ballSize),
				Position = pos + offset,
				Color = green,
				Material = Enum.Material.LeafyGrass,
				Parent = props,
			})
			if not main then
				main = ball
			end
		end
		return addSpot("arbusto", "Arbusto de manuka", main, pos + Vector3.new(0, 1.6, 0), 5.5 * scale, 0.72)
	end

	-- Helecho plateado
	local function makeFern(pos, scale)
		scale = scale or rng:NextNumber(0.9, 1.4)
		part({
			Name = "TroncoHelecho",
			Size = Vector3.new(0.9 * scale, 5 * scale, 0.9 * scale),
			Position = pos + Vector3.new(0, 2.5 * scale, 0),
			Color = Color3.fromRGB(92, 68, 46),
			Material = Enum.Material.Wood,
			Parent = props,
		})
		local main
		for i = 1, 7 do
			local angle = (i / 7) * math.pi * 2 + rng:NextNumber(-0.2, 0.2)
			local frond = part({
				Name = "Fronda",
				Size = Vector3.new(1.1 * scale, 0.3, 8 * scale),
				CFrame = CFrame.new(pos + Vector3.new(0, 5.2 * scale, 0))
					* CFrame.Angles(math.rad(-28), angle, 0)
					* CFrame.new(0, 0, -4 * scale),
				Color = Color3.fromRGB(96 + rng:NextInteger(-10, 10), 138 + rng:NextInteger(-12, 12), 88),
				Material = Enum.Material.Grass,
				Parent = props,
			})
			if not main then
				main = frond
			end
		end
		return addSpot("helecho", "Helecho gigante", main, pos + Vector3.new(0, 2, 0), 5 * scale, 0.6)
	end

	-- Tronco hueco
	local function makeLog(pos, angle)
		angle = angle or rng:NextNumber(0, math.pi)
		local axis = Vector3.new(math.cos(angle), 0, math.sin(angle))
		local main = part({
			Name = "TroncoHueco",
			Shape = Enum.PartType.Cylinder,
			Size = Vector3.new(15, 3.4, 3.4),
			CFrame = CFrame.new(pos + Vector3.new(0, 1.9, 0)) * CFrame.Angles(0, -angle, 0),
			Color = Color3.fromRGB(84, 62, 44),
			Material = Enum.Material.Wood,
			CanCollide = true,
			Parent = props,
		})
		part({
			Name = "Hueco",
			Shape = Enum.PartType.Cylinder,
			Size = Vector3.new(0.4, 2.4, 2.4),
			CFrame = CFrame.new(pos + axis * 7.6 + Vector3.new(0, 1.9, 0)) * CFrame.Angles(0, -angle, 0),
			Color = Color3.fromRGB(28, 22, 18),
			Material = Enum.Material.Slate,
			Parent = props,
		})
		return addSpot("tronco", "Tronco hueco", main, pos, 6, 0.85)
	end

	-- Grieta de rocas
	local function makeRocks(pos, scale)
		scale = scale or rng:NextNumber(1, 1.6)
		local main
		for i = 1, 3 do
			local ballSize = rng:NextNumber(6, 10) * scale
			local offset = Vector3.new(rng:NextNumber(-4, 4), rng:NextNumber(1.5, 3.5), rng:NextNumber(-4, 4))
			local rock = part({
				Name = "Roca",
				Shape = Enum.PartType.Ball,
				Size = Vector3.new(ballSize, ballSize * 0.8, ballSize),
				Position = pos + offset,
				Color = Color3.fromRGB(122, 124, 126),
				Material = Enum.Material.Rock,
				CanCollide = true,
				Parent = props,
			})
			if not main then
				main = rock
			end
		end
		return addSpot("roca", "Grieta entre rocas", main, pos + Vector3.new(0, 1.4, 0), 6 * scale, 0.9)
	end

	-- Madriguera
	local function makeBurrow(pos)
		local main = part({
			Name = "Monticulo",
			Shape = Enum.PartType.Ball,
			Size = Vector3.new(11, 6, 11),
			Position = pos + Vector3.new(0, 1.2, 0),
			Color = Color3.fromRGB(92, 74, 52),
			Material = Enum.Material.Ground,
			CanCollide = true,
			Parent = props,
		})
		part({
			Name = "Entrada",
			Shape = Enum.PartType.Cylinder,
			Size = Vector3.new(0.5, 3.6, 3.6),
			CFrame = CFrame.new(pos + Vector3.new(0, 1.5, -2.5)) * CFrame.Angles(0, math.rad(90), 0),
			Color = Color3.fromRGB(24, 20, 16),
			Material = Enum.Material.Slate,
			Parent = props,
		})
		return addSpot("madriguera", "Madriguera", main, pos, 6.5, 1.0)
	end

	-- Pasto alto
	local function makeGrassPatch(pos, scale)
		scale = scale or rng:NextNumber(1, 1.5)
		local main
		for i = 1, 8 do
			local blade = part({
				Name = "Pasto",
				Size = Vector3.new(rng:NextNumber(0.7, 1.6) * scale, rng:NextNumber(4, 6.5) * scale, rng:NextNumber(0.7, 1.6) * scale),
				CFrame = CFrame.new(pos + Vector3.new(rng:NextNumber(-5, 5), rng:NextNumber(1.5, 3), rng:NextNumber(-5, 5)))
					* CFrame.Angles(rng:NextNumber(-0.15, 0.15), rng:NextNumber(0, 6), rng:NextNumber(-0.15, 0.15)),
				Color = Color3.fromRGB(126, 142 + rng:NextInteger(-14, 14), 84),
				Material = Enum.Material.Grass,
				Transparency = 0.12,
				Parent = props,
			})
			if not main then
				main = blade
			end
		end
		return addSpot("pasto", "Pasto alto", main, pos + Vector3.new(0, 1, 0), 7 * scale, 0.5)
	end

	-- Cabana del guardabosques
	local function makeHut(pos, angle)
		angle = angle or 0
		local base = CFrame.new(pos) * CFrame.Angles(0, angle, 0)
		local wood = Color3.fromRGB(112, 84, 56)
		part({
			Name = "PisoCabana",
			Size = Vector3.new(20, 1, 16),
			CFrame = base * CFrame.new(0, 0.5, 0),
			Color = Color3.fromRGB(96, 88, 78),
			Material = Enum.Material.Slate,
			CanCollide = true,
			Parent = props,
		})
		part({
			Name = "ParedFondo",
			Size = Vector3.new(20, 9, 1),
			CFrame = base * CFrame.new(0, 4.8, -8),
			Color = wood,
			Material = Enum.Material.WoodPlanks,
			CanCollide = true,
			Parent = props,
		})
		part({
			Name = "ParedIzq",
			Size = Vector3.new(1, 9, 16),
			CFrame = base * CFrame.new(-10, 4.8, 0),
			Color = wood,
			Material = Enum.Material.WoodPlanks,
			CanCollide = true,
			Parent = props,
		})
		part({
			Name = "ParedDer",
			Size = Vector3.new(1, 9, 16),
			CFrame = base * CFrame.new(10, 4.8, 0),
			Color = wood,
			Material = Enum.Material.WoodPlanks,
			CanCollide = true,
			Parent = props,
		})
		local main = part({
			Name = "Techo",
			Size = Vector3.new(23, 1.2, 19),
			CFrame = base * CFrame.new(0, 9.4, 0),
			Color = Color3.fromRGB(70, 52, 38),
			Material = Enum.Material.WoodPlanks,
			CanCollide = true,
			Parent = props,
		})
		part({
			Name = "Viga",
			Size = Vector3.new(20, 1, 1),
			CFrame = base * CFrame.new(0, 9.9, -7),
			Color = Color3.fromRGB(60, 44, 32),
			Material = Enum.Material.Wood,
			Parent = props,
		})
		return addSpot("cabana", "Cabaña del guardabosques", main, pos, 10, 0.8)
	end

	-- Torre de observacion
	local function makeTower(pos)
		local wood = Color3.fromRGB(126, 96, 62)
		for sx = -1, 1, 2 do
			for sz = -1, 1, 2 do
				part({
					Name = "PataTorre",
					Size = Vector3.new(1.4, 16, 1.4),
					Position = pos + Vector3.new(sx * 5, 8, sz * 5),
					Color = wood,
					Material = Enum.Material.Wood,
					CanCollide = true,
					Parent = props,
				})
			end
		end
		local platform = part({
			Name = "PlataformaTorre",
			Size = Vector3.new(16, 1.2, 16),
			Position = pos + Vector3.new(0, 16.6, 0),
			Color = Color3.fromRGB(104, 78, 52),
			Material = Enum.Material.WoodPlanks,
			Parent = props,
		})
		part({
			Name = "Baranda",
			Size = Vector3.new(16, 3, 0.6),
			Position = pos + Vector3.new(0, 18.4, -8),
			Color = wood,
			Material = Enum.Material.Wood,
			Parent = props,
		})
		return addSpot("torre", "Bajo la torre", platform, pos, 8, 0.45)
	end

	-- Arbol decorativo (no es escondite, es obstaculo)
	local function makeTree(pos)
		local height = rng:NextNumber(22, 36)
		part({
			Name = "Tronco",
			Size = Vector3.new(2.8, height, 2.8),
			Position = pos + Vector3.new(0, height * 0.5, 0),
			Color = zone.tree,
			Material = Enum.Material.Wood,
			CanCollide = true,
			Parent = props,
		})
		for leaf = 1, 2 do
			local leafSize = rng:NextNumber(14, 20) - leaf * 2
			part({
				Name = "Copa",
				Shape = Enum.PartType.Ball,
				Size = Vector3.new(leafSize, leafSize * 0.72, leafSize),
				Position = pos + Vector3.new(rng:NextNumber(-2, 2), height - 3 + leaf * 3.5, rng:NextNumber(-2, 2)),
				Color = Color3.fromRGB(58 + leaf * 6, 104 + leaf * 6, 60),
				Material = Enum.Material.LeafyGrass,
				Parent = props,
			})
		end
	end

	-- Medano de arena (Dunas): limita la vista y da volumen
	local function makeDuneMound(pos, scale)
		scale = scale or rng:NextNumber(0.9, 1.5)
		for i = 1, 3 do
			local s = rng:NextNumber(16, 26) * scale
			part({
				Name = "Medano",
				Shape = Enum.PartType.Ball,
				Size = Vector3.new(s, s * 0.42, s),
				Position = pos + Vector3.new(rng:NextNumber(-7, 7), -s * 0.22 + rng:NextNumber(0, 2), rng:NextNumber(-7, 7)),
				Color = Color3.fromRGB(224, 200, 150),
				Material = Enum.Material.Sand,
				CanCollide = false,
				Parent = props,
			})
		end
	end

	-- Cactus (Dunas): escondite chico
	local function makeCactus(pos, scale)
		scale = scale or rng:NextNumber(0.85, 1.35)
		local green = Color3.fromRGB(96, 138, 84)
		local trunk = part({
			Name = "Cactus",
			Size = Vector3.new(2.2 * scale, 9 * scale, 2.2 * scale),
			Position = pos + Vector3.new(0, 4.5 * scale, 0),
			Color = green,
			Material = Enum.Material.Grass,
			CanCollide = true,
			Parent = props,
		})
		part({
			Name = "CactusBrazo",
			Size = Vector3.new(1.4 * scale, 4 * scale, 1.4 * scale),
			Position = pos + Vector3.new(1.7 * scale, 5.6 * scale, 0),
			Color = green,
			Material = Enum.Material.Grass,
			CanCollide = true,
			Parent = props,
		})
		return addSpot("arbusto", "Cactus", trunk, pos + Vector3.new(0, 1.6, 0), 4.6 * scale, 0.65)
	end

	-- Palmera (Costa)
	local function makePalm(pos, scale)
		scale = scale or rng:NextNumber(0.9, 1.3)
		local height = rng:NextNumber(20, 28) * scale
		part({
			Name = "TroncoPalmera",
			Size = Vector3.new(1.8 * scale, height, 1.8 * scale),
			CFrame = CFrame.new(pos + Vector3.new(0, height * 0.5, 0)) * CFrame.Angles(rng:NextNumber(-0.06, 0.06), 0, rng:NextNumber(-0.06, 0.06)),
			Color = zone.tree,
			Material = Enum.Material.Wood,
			CanCollide = true,
			Parent = props,
		})
		local top = pos + Vector3.new(0, height, 0)
		for i = 1, 5 do
			local a = (i - 1) * (math.pi * 2 / 5) + rng:NextNumber(-0.2, 0.2)
			part({
				Name = "HojaPalmera",
				Size = Vector3.new(12 * scale, 0.5, 2.6 * scale),
				CFrame = CFrame.new(top + Vector3.new(math.cos(a) * 4.6 * scale, rng:NextNumber(-1.5, 0.6), math.sin(a) * 4.6 * scale))
					* CFrame.Angles(0, -a, math.rad(-14)),
				Color = Color3.fromRGB(64, 122, 66),
				Material = Enum.Material.LeafyGrass,
				CanCollide = false,
				Parent = props,
			})
		end
	end

	-- Pino de nieve (Alpes)
	local function makePine(pos, scale)
		scale = scale or rng:NextNumber(0.9, 1.3)
		local height = rng:NextNumber(24, 34) * scale
		part({
			Name = "TroncoPino",
			Size = Vector3.new(2.4, height * 0.5, 2.4),
			Position = pos + Vector3.new(0, height * 0.25, 0),
			Color = zone.tree,
			Material = Enum.Material.Wood,
			CanCollide = true,
			Parent = props,
		})
		for level = 1, 3 do
			local width = (20 - level * 4) * scale
			part({
				Name = "CopaPino",
				Shape = Enum.PartType.Ball,
				Size = Vector3.new(width, width * 0.75, width),
				Position = pos + Vector3.new(0, height * (0.38 + level * 0.16), 0),
				Color = Color3.fromRGB(52 + level * 6, 88 + level * 6, 62),
				Material = Enum.Material.LeafyGrass,
				CanCollide = level == 1,
				Parent = props,
			})
		end
	end

	-- Poste de luz (Ciudad)
	local function makeLampPost(pos)
		part({
			Name = "Poste",
			Size = Vector3.new(0.7, 16, 0.7),
			Position = pos + Vector3.new(0, 8, 0),
			Color = Color3.fromRGB(58, 60, 66),
			Material = Enum.Material.Metal,
			CanCollide = true,
			Parent = props,
		})
		local lamp = part({
			Name = "Farol",
			Shape = Enum.PartType.Ball,
			Size = Vector3.new(2.6, 2.6, 2.6),
			Position = pos + Vector3.new(0, 16.6, 0),
			Color = Color3.fromRGB(255, 232, 168),
			Material = Enum.Material.Neon,
			CanCollide = false,
			Parent = props,
		})
		local light = Instance.new("PointLight")
		light.Color = Color3.fromRGB(255, 226, 158)
		light.Range = 34
		light.Brightness = 1.1
		light.Parent = lamp
	end

	-- Banco de plaza (Ciudad)
	local function makeBench(pos)
		local base = CFrame.new(pos) * CFrame.Angles(0, rng:NextNumber(0, math.pi * 2), 0)
		part({
			Name = "BancoAsiento",
			Size = Vector3.new(6, 0.6, 1.8),
			CFrame = base * CFrame.new(0, 2.2, 0),
			Color = Color3.fromRGB(126, 96, 62),
			Material = Enum.Material.WoodPlanks,
			CanCollide = true,
			Parent = props,
		})
		for _, dx in ipairs({ -2.4, 2.4 }) do
			part({
				Name = "PatasBanco",
				Size = Vector3.new(0.6, 2.2, 1.4),
				CFrame = base * CFrame.new(dx, 1.1, 0),
				Color = Color3.fromRGB(74, 76, 82),
				Material = Enum.Material.Metal,
				CanCollide = true,
				Parent = props,
			})
		end
	end

	-- Torre mirador de la ciudad (estilo Sky Tower)
	local function makeSkyTower(pos)
		local shaft = part({
			Name = "TorreFuste",
			Shape = Enum.PartType.Cylinder,
			Size = Vector3.new(120, 13, 13),
			CFrame = CFrame.new(pos + Vector3.new(0, 60, 0)) * CFrame.Angles(0, 0, math.rad(90)),
			Color = Color3.fromRGB(206, 214, 222),
			Material = Enum.Material.Concrete,
			CanCollide = true,
			Parent = props,
		})
		part({
			Name = "TorreMirador",
			Shape = Enum.PartType.Ball,
			Size = Vector3.new(26, 26, 26),
			Position = pos + Vector3.new(0, 108, 0),
			Color = Color3.fromRGB(120, 150, 180),
			Material = Enum.Material.Glass,
			CanCollide = true,
			Parent = props,
		})
		part({
			Name = "TorreAguja",
			Shape = Enum.PartType.Cylinder,
			Size = Vector3.new(46, 2.2, 2.2),
			CFrame = CFrame.new(pos + Vector3.new(0, 145, 0)) * CFrame.Angles(0, 0, math.rad(90)),
			Color = Color3.fromRGB(180, 190, 200),
			Material = Enum.Material.Metal,
			CanCollide = false,
			Parent = props,
		})
		local light = Instance.new("PointLight")
		light.Color = Color3.fromRGB(255, 120, 110)
		light.Range = 60
		light.Brightness = 2
		light.Parent = shaft
	end

	-- ===============================================================
	-- Casas con interiores (escondites de verdad) y baules de armas
	-- ===============================================================
	local HOUSE_WOOD = Color3.fromRGB(122, 92, 62)
	local HOUSE_WALL = zone.wall or Color3.fromRGB(204, 190, 166)
	local HOUSE_ROOF = zone.roof or Color3.fromRGB(148, 76, 54)
	local HOUSE_FLOOR = zone.floor or Color3.fromRGB(104, 84, 64)

	local function box(name, cf, size, color, material)
		return part({
			Name = name,
			Size = size,
			CFrame = cf,
			Color = color,
			Material = material or Enum.Material.WoodPlanks,
			CanCollide = true,
			Parent = props,
		})
	end

	local function makeCloset(base, label)
		local body = box("Armario", base * CFrame.new(0, 3.6, 0), Vector3.new(2.8, 7.2, 2.2), HOUSE_WOOD, Enum.Material.WoodPlanks)
		box("TapaArmario", base * CFrame.new(0, 7.1, 0), Vector3.new(3.0, 0.3, 2.4), Color3.fromRGB(92, 68, 46), Enum.Material.Wood)
		local hinge = base * CFrame.new(-1.35, 3.55, 1.18)
		local doorClosed = hinge * CFrame.new(1.35, 0, 0)
		local doorOpen = hinge * CFrame.Angles(0, math.rad(86), 0) * CFrame.new(1.35, 0, 0)
		local door = box("PuertaArmario", doorClosed, Vector3.new(2.7, 6.8, 0.3), Color3.fromRGB(110, 80, 54), Enum.Material.WoodPlanks)
		local spot = addSpot("armario", "Armario", body, base.Position, 2.6, 0.95)
		return registerEnter(spot, {
			inside = base * CFrame.new(0, 3.7, -0.1) * CFrame.Angles(0, math.rad(180), 0),
			exit = base * CFrame.new(0, 3.7, 3.6) * CFrame.Angles(0, math.rad(180), 0),
			door = door,
			doorClosed = doorClosed,
			doorOpen = doorOpen,
			label = label or "Armario",
			anchorPart = body,
		})
	end

	local function makeBarrelHide(base, label)
		local body = part({
			Name = "Barril",
			Shape = Enum.PartType.Cylinder,
			Size = Vector3.new(6.4, 3.6, 3.6),
			CFrame = base * CFrame.Angles(0, 0, math.rad(90)),
			Color = Color3.fromRGB(128, 90, 56),
			Material = Enum.Material.WoodPlanks,
			CanCollide = true,
			Parent = props,
		})
		for _, y in ipairs({ 1.5, 5.0 }) do
			part({
				Name = "AroBarril",
				Shape = Enum.PartType.Cylinder,
				Size = Vector3.new(0.5, 3.8, 3.8),
				CFrame = base * CFrame.new(0, y, 0) * CFrame.Angles(0, 0, math.rad(90)),
				Color = Color3.fromRGB(84, 84, 92),
				Material = Enum.Material.Metal,
				CanCollide = false,
				Parent = props,
			})
		end
		local spot = addSpot("barril", "Barril", body, base.Position, 2.4, 0.95)
		return registerEnter(spot, {
			inside = base * CFrame.new(0, 3.4, 0),
			exit = base * CFrame.new(0, 3.4, 3.4),
			wobble = body,
			label = label or "Barril",
			anchorPart = body,
		})
	end

	local function makeHayProp(base, label)
		local main = part({
			Name = "Pajar",
			Shape = Enum.PartType.Ball,
			Size = Vector3.new(8, 7.4, 8),
			CFrame = base * CFrame.new(0, 2.4, 0),
			Color = Color3.fromRGB(198, 170, 86),
			Material = Enum.Material.SmoothPlastic,
			CanCollide = true,
			Parent = props,
		})
		part({
			Name = "PajarChico",
			Shape = Enum.PartType.Ball,
			Size = Vector3.new(4.8, 4, 4.8),
			CFrame = base * CFrame.new(2.7, 1.3, 1.9),
			Color = Color3.fromRGB(208, 182, 98),
			Material = Enum.Material.SmoothPlastic,
			CanCollide = true,
			Parent = props,
		})
		local spot = addSpot("pajar", "Pajar", main, base.Position, 3.0, 1)
		return registerEnter(spot, {
			inside = base * CFrame.new(0, 3.3, 0),
			exit = base * CFrame.new(0, 3.3, 4.8),
			wobble = main,
			label = label or "Pajar",
			anchorPart = main,
		})
	end

	local function makeChestProp(base, label)
		local body = box("Baul", base * CFrame.new(0, 1.3, 0), Vector3.new(4.2, 2.6, 3.0), Color3.fromRGB(124, 84, 48), Enum.Material.WoodPlanks)
		box("AdornoBaul", base * CFrame.new(0, 1.3, 0), Vector3.new(4.35, 0.55, 3.15), Color3.fromRGB(214, 178, 74), Enum.Material.Metal, false)
		local hinge = base * CFrame.new(0, 2.6, -1.5)
		local lidClosed = hinge * CFrame.new(0, 0.25, 1.5)
		local lidOpen = hinge * CFrame.Angles(math.rad(-78), 0, 0) * CFrame.new(0, 0.25, 1.5)
		local lid = box("TapaBaul", lidClosed, Vector3.new(4.2, 0.5, 3.0), Color3.fromRGB(136, 96, 56), Enum.Material.WoodPlanks)
		local light = Instance.new("PointLight")
		light.Name = "BrilloBaul"
		light.Color = Color3.fromRGB(255, 214, 120)
		light.Range = 18
		light.Brightness = 1.4
		light.Parent = body
		local prompt = Instance.new("ProximityPrompt")
		prompt.Name = "AbrirBaul"
		prompt.ActionText = "Abrir"
		prompt.ObjectText = label or "Baúl"
		prompt.KeyboardKeyCode = Enum.KeyCode.E
		prompt.HoldDuration = 0
		prompt.MaxActivationDistance = 10
		prompt.RequiresLineOfSight = false
		prompt.Parent = body
		local chest = {
			body = body,
			lid = lid,
			lidClosed = lidClosed,
			lidOpen = lidOpen,
			light = light,
			prompt = prompt,
			used = false,
			center = base.Position,
		}
		table.insert(self.chests, chest)
		return chest
	end

	local function makeTable(cf, wood)
		box("Mesa", cf * CFrame.new(0, 2.4, 0), Vector3.new(4.6, 0.4, 2.6), wood, Enum.Material.Wood)
		for _, dx in ipairs({ -1.8, 1.8 }) do
			for _, dz in ipairs({ -0.9, 0.9 }) do
				box("PataMesa", cf * CFrame.new(dx, 1.15, dz), Vector3.new(0.4, 2.3, 0.4), wood, Enum.Material.Wood)
			end
		end
	end

	local function makeChair(cf, wood)
		box("Asiento", cf * CFrame.new(0, 1.4, 0), Vector3.new(1.8, 0.35, 1.8), wood, Enum.Material.Wood)
		box("Respaldo", cf * CFrame.new(0, 2.7, -0.75), Vector3.new(1.8, 2.4, 0.3), wood, Enum.Material.Wood)
		for _, dx in ipairs({ -0.7, 0.7 }) do
			for _, dz in ipairs({ -0.7, 0.7 }) do
				box("PataSilla", cf * CFrame.new(dx, 0.6, dz), Vector3.new(0.3, 1.2, 0.3), wood, Enum.Material.Wood)
			end
		end
	end

	local function makeBed(cf, wood)
		box("Cama", cf * CFrame.new(0, 1.1, 0), Vector3.new(6.4, 1.2, 3.2), wood, Enum.Material.Wood)
		box("Colchon", cf * CFrame.new(0, 2.0, 0), Vector3.new(6.0, 0.9, 2.9), Color3.fromRGB(226, 224, 216), Enum.Material.Fabric)
		box("Almohada", cf * CFrame.new(-2.2, 2.7, 0), Vector3.new(1.6, 0.5, 2.4), Color3.fromRGB(240, 240, 236), Enum.Material.Fabric)
	end

	local function makeShelfProp(cf, wood)
		box("Estante", cf * CFrame.new(0, 2.8, 0), Vector3.new(4.4, 5.6, 1.0), wood, Enum.Material.Wood)
	end

	local function makeCrateProp(cf, size, wood)
		box("Caja", cf * CFrame.new(0, size.Y * 0.5, 0), size, Color3.fromRGB(126, 94, 60), Enum.Material.WoodPlanks)
	end

	-- Cocina: mesada con pileta, heladera y horno con anafes
	local function makeKitchenCounter(cf, len, wood)
		box("Mesada", cf * CFrame.new(0, 2.9, 0), Vector3.new(len, 0.3, 2.2), Color3.fromRGB(196, 198, 202), Enum.Material.Slate)
		box("MuebleBajo", cf * CFrame.new(0, 1.45, 0), Vector3.new(len, 2.6, 1.9), wood, Enum.Material.WoodPlanks)
		box("Pileta", cf * CFrame.new(-len * 0.22, 2.95, 0), Vector3.new(2.6, 0.5, 1.5), Color3.fromRGB(164, 170, 176), Enum.Material.Metal)
		part({
			Name = "Grifo",
			Shape = Enum.PartType.Cylinder,
			Size = Vector3.new(1.3, 0.22, 0.22),
			CFrame = cf * CFrame.new(-len * 0.22, 3.55, -0.7) * CFrame.Angles(0, 0, math.rad(90)),
			Color = Color3.fromRGB(184, 190, 196),
			Material = Enum.Material.Metal,
			CanCollide = false,
			Parent = props,
		})
	end

	local function makeFridge(cf)
		box("Heladera", cf * CFrame.new(0, 3.2, 0), Vector3.new(3.0, 6.4, 3.0), Color3.fromRGB(226, 228, 232), Enum.Material.Metal)
		box("HeladeraPuerta", cf * CFrame.new(0, 3.2, 1.6), Vector3.new(2.7, 5.9, 0.2), Color3.fromRGB(206, 210, 216), Enum.Material.Metal)
		box("HeladeraManija", cf * CFrame.new(-1.05, 3.2, 1.85), Vector3.new(0.2, 2.6, 0.2), Color3.fromRGB(150, 156, 162), Enum.Material.Metal)
	end

	local function makeStove(cf)
		box("Horno", cf * CFrame.new(0, 1.6, 0), Vector3.new(3.2, 3.0, 2.6), Color3.fromRGB(210, 212, 216), Enum.Material.Metal)
		box("HornoPuerta", cf * CFrame.new(0, 1.7, 1.35), Vector3.new(2.5, 1.8, 0.2), Color3.fromRGB(56, 58, 62), Enum.Material.Glass)
		for i = 1, 4 do
			local dx = (i % 2 == 0) and 0.78 or -0.78
			local dz = (i <= 2) and -0.62 or 0.62
			part({
				Name = "Anafe",
				Shape = Enum.PartType.Cylinder,
				Size = Vector3.new(0.26, 1.15, 1.15),
				CFrame = cf * CFrame.new(dx, 3.24, dz) * CFrame.Angles(0, 0, math.rad(90)),
				Color = Color3.fromRGB(38, 38, 42),
				Material = Enum.Material.Metal,
				CanCollide = false,
				Parent = props,
			})
		end
	end

	-- Living: sofa, mesa ratona, alfombra y tele
	local function makeSofa(cf)
		local cloth = Color3.fromRGB(140, 150, 172)
		box("SofaAsiento", cf * CFrame.new(0, 1.3, 0), Vector3.new(7.0, 1.0, 2.9), cloth, Enum.Material.Fabric)
		box("SofaRespaldo", cf * CFrame.new(0, 2.7, 1.1), Vector3.new(7.0, 2.0, 0.8), cloth, Enum.Material.Fabric)
		box("SofaBrazoA", cf * CFrame.new(-3.2, 1.9, 0), Vector3.new(0.6, 2.0, 2.9), cloth, Enum.Material.Fabric)
		box("SofaBrazoB", cf * CFrame.new(3.2, 1.9, 0), Vector3.new(0.6, 2.0, 2.9), cloth, Enum.Material.Fabric)
	end

	local function makeCoffeeTable(cf)
		box("MesaRatona", cf * CFrame.new(0, 1.1, 0), Vector3.new(4.2, 0.3, 2.4), Color3.fromRGB(122, 90, 60), Enum.Material.Wood)
		for _, spot in ipairs({ { -1.7, -0.8 }, { 1.7, -0.8 }, { -1.7, 0.8 }, { 1.7, 0.8 } }) do
			part({
				Name = "PataRatona",
				Shape = Enum.PartType.Cylinder,
				Size = Vector3.new(1.1, 0.22, 0.22),
				CFrame = cf * CFrame.new(spot[1], 0.55, spot[2]) * CFrame.Angles(0, 0, math.rad(90)),
				Color = Color3.fromRGB(96, 70, 46),
				Material = Enum.Material.Wood,
				Parent = props,
			})
		end
	end

	local function makeRug(cf, color)
		return part({
			Name = "Alfombra",
			Size = Vector3.new(7, 0.12, 5),
			CFrame = cf * CFrame.new(0, 0.06, 0),
			Color = color or Color3.fromRGB(148, 70, 60),
			Material = Enum.Material.Fabric,
			CanCollide = false,
			Parent = props,
		})
	end

	local function makeTV(cf)
		box("Tele", cf * CFrame.new(0, 0, 0), Vector3.new(0.5, 4.4, 6.2), Color3.fromRGB(38, 40, 44), Enum.Material.Metal)
		box("TelePantalla", cf * CFrame.new(-0.3, 0.1, 0), Vector3.new(0.1, 3.6, 5.4), Color3.fromRGB(70, 112, 142), Enum.Material.Neon)
	end

	local function makeHouse(pos, angle, variant)
		local base = CFrame.new(pos) * CFrame.Angles(0, angle, 0)
		local big = variant == "farm"
		local W = big and 38 or 32
		local D = big and 28 or 24
		local floorH = 9.4
		local totalH = floorH * 2
		local wood = HOUSE_WOOD
		local floorPart = box("PisoCasa", base * CFrame.new(0, 0.3, 0), Vector3.new(W + 1.6, 0.6, D + 1.6), HOUSE_FLOOR, Enum.Material.Slate)

		-- Escalinata y toldo de entrada
		box("EscalonEntrada", base * CFrame.new(0, 0.3, D * 0.5 + 1.5), Vector3.new(8, 0.6, 3), HOUSE_FLOOR, Enum.Material.Slate)
		box("Toldo", base * CFrame.new(0, 7.9, D * 0.5 + 1.4), Vector3.new(9, 0.4, 3.0), wood, Enum.Material.WoodPlanks)

		local doorW = 6.4
		local sideW = (W - doorW) * 0.5
		box("ParedFrenteA", base * CFrame.new(-(doorW * 0.5 + sideW * 0.5), totalH * 0.5 + 0.6, D * 0.5), Vector3.new(sideW, totalH, 0.8), HOUSE_WALL, Enum.Material.Concrete)
		box("ParedFrenteB", base * CFrame.new(doorW * 0.5 + sideW * 0.5, totalH * 0.5 + 0.6, D * 0.5), Vector3.new(sideW, totalH, 0.8), HOUSE_WALL, Enum.Material.Concrete)
		box("DintelFrente", base * CFrame.new(0, floorH - 0.5, D * 0.5), Vector3.new(doorW, 2.2, 0.8), HOUSE_WALL, Enum.Material.Concrete)
		box("ParedFrenteC", base * CFrame.new(0, floorH + 0.6 + floorH * 0.5, D * 0.5), Vector3.new(doorW, floorH, 0.8), HOUSE_WALL, Enum.Material.Concrete)
		box("ParedFondo", base * CFrame.new(0, totalH * 0.5 + 0.6, -D * 0.5), Vector3.new(W, totalH, 0.8), HOUSE_WALL, Enum.Material.Concrete)
		box("ParedIzq", base * CFrame.new(-W * 0.5, totalH * 0.5 + 0.6, 0), Vector3.new(0.8, totalH, D), HOUSE_WALL, Enum.Material.Concrete)
		box("ParedDer", base * CFrame.new(W * 0.5, totalH * 0.5 + 0.6, 0), Vector3.new(0.8, totalH, D), HOUSE_WALL, Enum.Material.Concrete)

		-- Ventanas en las dos plantas
		box("VentanaA", base * CFrame.new(-W * 0.5, 5.4, D * 0.2), Vector3.new(1.0, 3.0, 3.4), Color3.fromRGB(88, 116, 128), Enum.Material.Glass)
		box("VentanaB", base * CFrame.new(W * 0.5, 5.4, -D * 0.2), Vector3.new(1.0, 3.0, 3.4), Color3.fromRGB(88, 116, 128), Enum.Material.Glass)
		box("VentanaC", base * CFrame.new(W * 0.22, 5.4, -D * 0.5), Vector3.new(3.2, 3.0, 1.0), Color3.fromRGB(88, 116, 128), Enum.Material.Glass)
		box("VentanaAltaA", base * CFrame.new(-W * 0.5, floorH + 5.4, D * 0.2), Vector3.new(1.0, 3.0, 3.4), Color3.fromRGB(88, 116, 128), Enum.Material.Glass)
		box("VentanaAltaB", base * CFrame.new(W * 0.5, floorH + 5.4, -D * 0.2), Vector3.new(1.0, 3.0, 3.4), Color3.fromRGB(88, 116, 128), Enum.Material.Glass)
		box("VentanaAltaC", base * CFrame.new(W * 0.3, floorH + 5.4, D * 0.5), Vector3.new(3.2, 3.0, 1.0), Color3.fromRGB(88, 116, 128), Enum.Material.Glass)

		box("MarcoIzq", base * CFrame.new(-doorW * 0.5 - 0.25, 3.9, D * 0.5), Vector3.new(0.5, 7.0, 1.1), wood, Enum.Material.Wood)
		box("MarcoDer", base * CFrame.new(doorW * 0.5 + 0.25, 3.9, D * 0.5), Vector3.new(0.5, 7.0, 1.1), wood, Enum.Material.Wood)

		-- Piso del segundo piso con hueco para la escalera
		local holeW = 5.8
		local holeZEnd = -D * 0.5 + D * 0.62
		local slabY = floorH + 0.55
		box("PisoAltoDerecha", base * CFrame.new(holeW * 0.5, slabY, 0), Vector3.new(W - holeW, 0.5, D), wood, Enum.Material.WoodPlanks)
		box("PisoAltoFrente", base * CFrame.new(-W * 0.5 + holeW * 0.5, slabY, (holeZEnd + D * 0.5) * 0.5), Vector3.new(holeW, 0.5, D * 0.5 - holeZEnd), wood, Enum.Material.WoodPlanks)
		box("BarandaEscalera", base * CFrame.new(-W * 0.5 + holeW + 0.2, slabY + 1.6, (-3.0 + holeZEnd) * 0.5), Vector3.new(0.3, 2.6, holeZEnd + 3.0), wood, Enum.Material.Wood)
		box("BarandaFrente", base * CFrame.new(-W * 0.5 + holeW * 0.5, slabY + 1.6, holeZEnd + 0.15), Vector3.new(holeW, 2.6, 0.3), wood, Enum.Material.Wood)

		-- Escalera de 12 escalones contra la pared izquierda
		local steps = 12
		local stepRise = floorH / steps
		local stepRun = (D - 5.5) / steps
		local stairX = -W * 0.5 + 2.9
		local stairZ0 = D * 0.5 - 2.5
		for i = 1, steps do
			box("Escalon", base * CFrame.new(stairX, 0.6 + i * stepRise - stepRise * 0.5, stairZ0 - (i - 1) * stepRun),
				Vector3.new(5.0, stepRise, stepRun + 0.25), wood, Enum.Material.WoodPlanks)
		end

		box("TechoCasa", base * CFrame.new(0, totalH + 1.1, 0), Vector3.new(W + 1.8, 0.6, D + 1.8), wood, Enum.Material.WoodPlanks)
		box("Chimenea", base * CFrame.new(W * 0.24, totalH + 3.6, -D * 0.18), Vector3.new(2.4, 6, 2.4), Color3.fromRGB(128, 84, 70), Enum.Material.Brick)
		local slope = math.rad(26)
		local slab = (W * 0.5 + 1.6) / math.cos(slope)
		part({
			Name = "TejadoA",
			Size = Vector3.new(slab, 0.7, D + 2.6),
			CFrame = base * CFrame.new(-W * 0.25 - 0.5, totalH + 2.4, 0) * CFrame.Angles(0, 0, slope),
			Color = HOUSE_ROOF,
			Material = Enum.Material.Slate,
			CanCollide = true,
			Parent = props,
		})
		part({
			Name = "TejadoB",
			Size = Vector3.new(slab, 0.7, D + 2.6),
			CFrame = base * CFrame.new(W * 0.25 + 0.5, totalH + 2.4, 0) * CFrame.Angles(0, 0, -slope),
			Color = HOUSE_ROOF,
			Material = Enum.Material.Slate,
			CanCollide = true,
			Parent = props,
		})

		-- Planta baja pensada para no trabar puerta ni escalera:
		-- la escalera usa la pared izquierda, la puerta el medio del frente
		-- y los muebles van contra las paredes (baul en el rincon del fondo).
		makeStove(base * CFrame.new(-6.6, 0.6, -D * 0.5 + 1.7))
		makeKitchenCounter(base * CFrame.new(1.6, 0.6, -D * 0.5 + 1.5), 12, wood)
		makeFridge(base * CFrame.new(9.4, 0.6, -D * 0.5 + 1.8))
		makeTable(base * CFrame.new(5.5, 0.6, 2.5), wood)
		makeChair(base * CFrame.new(5.5, 0.6, 5.6), wood)
		makeChair(base * CFrame.new(5.5, 0.6, -0.6), wood)
		makeChair(base * CFrame.new(2.4, 0.6, 2.5) * CFrame.Angles(0, math.rad(90), 0), wood)
		makeChair(base * CFrame.new(8.6, 0.6, 2.5) * CFrame.Angles(0, math.rad(-90), 0), wood)
		makeRug(base * CFrame.new(10.2, 0.6, 4.2))
		makeCoffeeTable(base * CFrame.new(10.6, 0.6, 4.2))
		makeSofa(base * CFrame.new(W * 0.5 - 2.0, 0.6, 4.2) * CFrame.Angles(0, math.rad(90), 0))
		makeTV(base * CFrame.new(W * 0.5 - 0.4, 4.7, 4.2))
		makeCloset(base * CFrame.new(W * 0.5 - 1.7, 0.6, -2) * CFrame.Angles(0, math.rad(-90), 0), "Armario")
		if big then
			makeCrateProp(base * CFrame.new(5.6, 0.6, -D * 0.5 + 4.4), Vector3.new(4, 3.2, 4), wood)
			makeBarrelHide(base * CFrame.new(-8.6, 0.6, D * 0.5 - 2.0), "Barril")
		end
		-- Baul pegado al rincon del frente (lejos de la puerta y la escalera)
		makeChestProp(base * CFrame.new(W * 0.5 - 2.2, 0.6, D * 0.5 - 2.2), "Baúl")

		addSpot("casa", "Casa", floorPart, (base * CFrame.new(5, 0, -5)).Position, 2.8, 0.9)
		addSpot("casa", "Casa", floorPart, (base * CFrame.new(-2, 0, 6)).Position, 2.8, 0.9)

		-- Planta alta: dos dormitorios con camas. No hay escondite (armario)
		-- aca arriba: el kiwi no sabe subir escaleras y seria una zona segura.
		local upY = floorH + 0.8
		makeBed(base * CFrame.new(0, upY, -D * 0.5 + 2.2), wood)
		makeBed(base * CFrame.new(10, upY, -D * 0.5 + 2.2), wood)
		makeCrateProp(base * CFrame.new(5.0, upY, -D * 0.5 + 2.0), Vector3.new(3, 3.4, 3), wood)
		makeShelfProp(base * CFrame.new(W * 0.5 - 1.6, upY, -2), wood)
		makeChestProp(base * CFrame.new(W * 0.5 - 2.2, upY, D * 0.5 - 2.2), "Baúl del piso")

		addIndoor(base, Vector3.new(W - 2, totalH, D - 2))
	end

	local function makeBarn(pos, angle)
		local base = CFrame.new(pos) * CFrame.Angles(0, angle, 0)
		local W, D, wallH = 26, 19, 11
		local wood = HOUSE_WOOD
		local barnRed = zone.barn or (theme == "ciudad" and Color3.fromRGB(118, 110, 102) or Color3.fromRGB(140, 62, 52))
		local floorPart = box("PisoGranero", base * CFrame.new(0, 0.3, 0), Vector3.new(W + 1.6, 0.6, D + 1.6), HOUSE_FLOOR, Enum.Material.Slate)

		local doorW = 10
		local sideW = (W - doorW) * 0.5
		box("GraneroFrenteA", base * CFrame.new(-(doorW * 0.5 + sideW * 0.5), wallH * 0.5 + 0.6, D * 0.5), Vector3.new(sideW, wallH, 0.8), barnRed, Enum.Material.WoodPlanks)
		box("GraneroFrenteB", base * CFrame.new(doorW * 0.5 + sideW * 0.5, wallH * 0.5 + 0.6, D * 0.5), Vector3.new(sideW, wallH, 0.8), barnRed, Enum.Material.WoodPlanks)
		box("GraneroDintel", base * CFrame.new(0, wallH - 1.4 + 0.6, D * 0.5), Vector3.new(doorW, 2.8, 0.8), barnRed, Enum.Material.WoodPlanks)
		box("GraneroFondo", base * CFrame.new(0, wallH * 0.5 + 0.6, -D * 0.5), Vector3.new(W, wallH, 0.8), barnRed, Enum.Material.WoodPlanks)
		box("GraneroIzq", base * CFrame.new(-W * 0.5, wallH * 0.5 + 0.6, 0), Vector3.new(0.8, wallH, D), barnRed, Enum.Material.WoodPlanks)
		box("GraneroDer", base * CFrame.new(W * 0.5, wallH * 0.5 + 0.6, 0), Vector3.new(0.8, wallH, D), barnRed, Enum.Material.WoodPlanks)
		box("GraneroTecho", base * CFrame.new(0, wallH + 1.1, 0), Vector3.new(W + 1.8, 0.6, D + 1.8), wood, Enum.Material.WoodPlanks)
		local slope = math.rad(24)
		local slab = (W * 0.5 + 1.6) / math.cos(slope)
		part({
			Name = "GraneroTejadoA",
			Size = Vector3.new(slab, 0.7, D + 2.6),
			CFrame = base * CFrame.new(-W * 0.25 - 0.5, wallH + 2.3, 0) * CFrame.Angles(0, 0, slope),
			Color = Color3.fromRGB(120, 64, 48),
			Material = Enum.Material.Slate,
			CanCollide = true,
			Parent = props,
		})
		part({
			Name = "GraneroTejadoB",
			Size = Vector3.new(slab, 0.7, D + 2.6),
			CFrame = base * CFrame.new(W * 0.25 + 0.5, wallH + 2.3, 0) * CFrame.Angles(0, 0, -slope),
			Color = Color3.fromRGB(120, 64, 48),
			Material = Enum.Material.Slate,
			CanCollide = true,
			Parent = props,
		})

		-- Silos de metal al lado del granero
		for _, side in ipairs({ -1, 1 }) do
			if rng:NextNumber(0, 1) < 0.6 then
				local sPos = base * CFrame.new(side * (W * 0.5 + 9), 0, -D * 0.2)
				part({
					Name = "Silo",
					Shape = Enum.PartType.Cylinder,
					Size = Vector3.new(26, 15, 15),
					CFrame = sPos * CFrame.new(0, 13, 0) * CFrame.Angles(0, 0, math.rad(90)),
					Color = Color3.fromRGB(196, 190, 178),
					Material = Enum.Material.Metal,
					CanCollide = true,
					Parent = props,
				})
				part({
					Name = "SiloTecho",
					Shape = Enum.PartType.Ball,
					Size = Vector3.new(15.5, 8, 15.5),
					CFrame = sPos * CFrame.new(0, 25.4, 0),
					Color = Color3.fromRGB(150, 74, 58),
					Material = Enum.Material.Metal,
					CanCollide = true,
					Parent = props,
				})
			end
		end

		makeHayProp(base * CFrame.new(-W * 0.24, 0.6, -D * 0.2), "Pajar")
		makeHayProp(base * CFrame.new(W * 0.24, 0.6, -D * 0.22), "Pajar")
		makeCrateProp(base * CFrame.new(W * 0.2, 0.6, D * 0.26), Vector3.new(5, 4.6, 5), wood)
		makeCrateProp(base * CFrame.new(W * 0.03, 0.6, D * 0.3), Vector3.new(4, 3.6, 4), wood)
		makeBarrelHide(base * CFrame.new(-W * 0.36, 0.6, D * 0.3), "Barril")
		makeChestProp(base * CFrame.new(-W * 0.04, 0.6, -D * 0.34), "Baúl del granero")

		addSpot("granero", "Granero", floorPart, (base * CFrame.new(-W * 0.3, 0, -D * 0.32)).Position, 3.0, 0.9)
		addSpot("granero", "Granero", floorPart, (base * CFrame.new(W * 0.3, 0, 0)).Position, 3.0, 0.9)
		addIndoor(base, Vector3.new(W - 2, wallH, D - 2))
	end

	-- ===============================================================
	-- Distribucion de props
	-- ===============================================================
	local occupied = {}

	local function freeSpot(minDist, margin)
		margin = margin or 34
		for _ = 1, 70 do
			local point = self:randomPoint(rng, half - margin)
			local ok = true
			for _, other in ipairs(occupied) do
				if (point - other).Magnitude < minDist then
					ok = false
					break
				end
			end
			if ok then
				table.insert(occupied, point)
				return point
			end
		end
		return nil
	end

	-- ===============================================================
	-- Vida de la ciudad: avenidas, tiendas, semaforos, autos y tren
	-- (solo el mapa Ciudad de Auckland)
	-- ===============================================================
	if theme == "ciudad" then
		local asphalt = Color3.fromRGB(46, 46, 52)
		local sidewalkCol = Color3.fromRGB(148, 146, 140)
		local R = half - 82            -- radio de la avenida circular
		local roadW = 34               -- ancho de la calzada
		local yRoad = floorY + 0.1

		-- Calzada: anillo cuadrado de cuatro tramos
		local tramos = {
			{ Vector3.new(0, 0, -R), Vector3.new(2 * R + roadW, 0.24, roadW) },
			{ Vector3.new(0, 0, R), Vector3.new(2 * R + roadW, 0.24, roadW) },
			{ Vector3.new(-R, 0, 0), Vector3.new(roadW, 0.24, 2 * R + roadW) },
			{ Vector3.new(R, 0, 0), Vector3.new(roadW, 0.24, 2 * R + roadW) },
		}
		for _, tramo in ipairs(tramos) do
			box("Avenida", CFrame.new(center.X + tramo[1].X, yRoad, center.Z + tramo[1].Z), tramo[2],
				asphalt, Enum.Material.Asphalt)
			-- Lineas blancas del medio
			local along = tramo[2].X > tramo[2].Z and tramo[2].X or tramo[2].Z
			local vertical = tramo[2].Z > tramo[2].X
			local n = math.floor(along / 22)
			for i = -n, n do
				local offset = i * 22
				local pos
				local size
				if vertical then
					pos = Vector3.new(center.X + tramo[1].X, yRoad + 0.18, center.Z + tramo[1].Z + offset)
					size = Vector3.new(0.8, 0.06, 6)
				else
					pos = Vector3.new(center.X + tramo[1].X + offset, yRoad + 0.18, center.Z + tramo[1].Z)
					size = Vector3.new(6, 0.06, 0.8)
				end
				box("LineaVia", CFrame.new(pos), size, Color3.fromRGB(228, 226, 214), Enum.Material.SmoothPlastic)
			end
			-- Aceras a los dos lados
			for _, side in ipairs({ -1, 1 }) do
				local off, sz
				if vertical then
					off = Vector3.new(side * (roadW * 0.5 + 2.5), 0, 0)
					sz = Vector3.new(5, 0.5, along)
				else
					off = Vector3.new(0, 0, side * (roadW * 0.5 + 2.5))
					sz = Vector3.new(along, 0.5, 5)
				end
				box("Acera", CFrame.new(center.X + tramo[1].X + off.X, floorY + 0.25, center.Z + tramo[1].Z + off.Z),
					sz, sidewalkCol, Enum.Material.Concrete)
			end
			-- Muestras ocupadas: que props y casas no invadan la avenida
			local samples = math.floor(along / 22)
			for i = -samples, samples do
				local offset = i * 22
				local p
				if vertical then
					p = Vector3.new(center.X + tramo[1].X, 0, center.Z + tramo[1].Z + offset)
				else
					p = Vector3.new(center.X + tramo[1].X + offset, 0, center.Z + tramo[1].Z)
				end
				table.insert(occupied, p)
			end
		end

		-- Tiendas y comercios bordeando la avenida (con cartel de codigo)
		local function makeShop(base, name, color)
			local W, D, H = 24, 15, 12
			box("Local", base * CFrame.new(0, H * 0.5 + 0.6, 0), Vector3.new(W, H, D),
				Color3.fromRGB(206, 198, 184), Enum.Material.Concrete)
			box("LocalTecho", base * CFrame.new(0, H + 1.0, 0), Vector3.new(W + 1.4, 0.6, D + 1.4),
				Color3.fromRGB(120, 96, 78), Enum.Material.Slate)
			box("Vitrina", base * CFrame.new(-3.4, 4.6, D * 0.5 + 0.1), Vector3.new(15, 6.4, 0.4),
				Color3.fromRGB(120, 170, 186), Enum.Material.Glass)
			box("PuertaLocal", base * CFrame.new(W * 0.32, 3.6, D * 0.5 + 0.12), Vector3.new(4.2, 7.0, 0.4),
				Color3.fromRGB(60, 54, 48), Enum.Material.WoodPlanks)
			for i = 0, 5 do
				local tone = (i % 2 == 0) and color or Color3.fromRGB(238, 236, 228)
				part({
					Name = "Toldo",
					Size = Vector3.new(3.2, 0.22, 3.6),
					CFrame = base * CFrame.new(-8.25 + i * 3.3, 8.7, D * 0.5 + 1.7) * CFrame.Angles(math.rad(-16), 0, 0),
					Color = tone,
					Material = Enum.Material.Fabric,
					CanCollide = false,
					Parent = props,
				})
			end
			local sign = box("Cartel", base * CFrame.new(0, 10.7, D * 0.5 + 0.15), Vector3.new(16, 2.4, 0.4),
				Color3.fromRGB(58, 52, 48), Enum.Material.WoodPlanks)
			local gui = Instance.new("SurfaceGui")
			gui.Name = "CartelGui"
			gui.Face = Enum.NormalId.Back
			gui.LightInfluence = 0
			gui.CanvasSize = Vector2.new(800, 120)
			gui.Parent = sign
			local label = Instance.new("TextLabel")
			label.Size = UDim2.fromScale(1, 1)
			label.BackgroundTransparency = 1
			label.Font = Enum.Font.GothamBold
			label.TextScaled = true
			label.TextColor3 = Color3.fromRGB(250, 244, 230)
			label.Text = name
			label.Parent = gui
		end

		local SHOPS = {
			{ name = "Panaderia", color = Color3.fromRGB(226, 152, 72) },
			{ name = "Kiosco", color = Color3.fromRGB(112, 196, 120) },
			{ name = "Heladeria", color = Color3.fromRGB(120, 190, 226) },
			{ name = "Ferreteria", color = Color3.fromRGB(206, 96, 84) },
			{ name = "Cafe", color = Color3.fromRGB(150, 106, 74) },
			{ name = "Supermercado", color = Color3.fromRGB(228, 200, 90) },
		}
		for i, shop in ipairs(SHOPS) do
			local a = math.rad(25 + (i - 1) * 60)
			local pos = center + Vector3.new(math.sin(a), 0, math.cos(a)) * (R - 40)
			pos = Vector3.new(pos.X, 0, pos.Z)
			makeShop(CFrame.new(pos + Vector3.new(0, floorY, 0)) * CFrame.Angles(0, a, 0), shop.name, shop.color)
			table.insert(occupied, pos)
		end

		-- Semaforos en las cuatro esquinas de la avenida
		local function makeTrafficLight(pos)
			box("PosteSemaforo", CFrame.new(pos + Vector3.new(0, 7.5, 0)), Vector3.new(0.5, 15, 0.5),
				Color3.fromRGB(58, 58, 62), Enum.Material.Metal)
			box("CabezaSemaforo", CFrame.new(pos + Vector3.new(0, 14.6, 0)), Vector3.new(1.4, 4.0, 1.0),
				Color3.fromRGB(40, 42, 46), Enum.Material.Metal)
			local lights = {}
			local function bulb(name, color, dy)
				lights[name] = part({
					Name = name,
					Shape = Enum.PartType.Ball,
					Size = Vector3.new(0.85, 0.85, 0.85),
					Position = pos + Vector3.new(0, 14.6 + dy, 0.62),
					Color = color,
					Material = Enum.Material.SmoothPlastic,
					CanCollide = false,
					Parent = props,
				})
			end
			bulb("red", Color3.fromRGB(210, 60, 50), 1.25)
			bulb("yellow", Color3.fromRGB(220, 180, 60), 0)
			bulb("green", Color3.fromRGB(70, 190, 110), -1.25)
			table.insert(self.semaphores, lights)
		end
		for _, corner in ipairs({ { 1, 1 }, { 1, -1 }, { -1, 1 }, { -1, -1 } }) do
			local p = center + Vector3.new(corner[1] * (R + 26), floorY, corner[2] * (R + 26))
			makeTrafficLight(p)
			table.insert(occupied, Vector3.new(p.X, 0, p.Z))
		end

		-- Vias del tren pegadas al muro norte
		local trackZ = center.Z - (half - 44)
		local trackHalf = half - 30
		box("ViaA", CFrame.new(center.X, floorY + 0.15, trackZ - 1.2), Vector3.new(trackHalf * 2, 0.3, 0.5),
			Color3.fromRGB(120, 122, 128), Enum.Material.Metal)
		box("ViaB", CFrame.new(center.X, floorY + 0.15, trackZ + 1.2), Vector3.new(trackHalf * 2, 0.3, 0.5),
			Color3.fromRGB(120, 122, 128), Enum.Material.Metal)
		local sleeperN = math.floor(trackHalf / 12)
		for i = -sleeperN, sleeperN do
			box("Durmiente", CFrame.new(center.X + i * 12, floorY + 0.05, trackZ), Vector3.new(2.0, 0.3, 3.6),
				Color3.fromRGB(96, 74, 54), Enum.Material.WoodPlanks)
		end
		local railSamples = math.floor(trackHalf / 26)
		for i = -railSamples, railSamples do
			table.insert(occupied, Vector3.new(center.X + i * 26, 0, trackZ))
		end

		-- Vehiculos: partes de adorno que mueve GameManager (sin fisica)
		local function vehiclePart(model, name, size, cf, color, material, shape)
			local p = part({
				Name = name,
				Size = size,
				CFrame = cf,
				Color = color,
				Material = material or Enum.Material.Metal,
				Anchored = true,
				CanCollide = false,
				CanQuery = false,
				CanTouch = false,
				CastShadow = true,
				Parent = model,
			})
			if shape then
				p.Shape = shape
			end
			p.Massless = true
			return p
		end

		local CAR_COLORS = {
			Color3.fromRGB(176, 66, 58), Color3.fromRGB(64, 110, 176),
			Color3.fromRGB(202, 172, 70), Color3.fromRGB(96, 160, 110),
			Color3.fromRGB(220, 220, 224), Color3.fromRGB(120, 90, 160),
		}

		local function makeCar(color)
			local model = Instance.new("Model")
			model.Name = "Auto"
			model.Parent = folder
			local body = vehiclePart(model, "Chasis", Vector3.new(5.0, 1.8, 11.0), CFrame.new(0, 0, 0),
				color, Enum.Material.SmoothPlastic)
			vehiclePart(model, "Cabina", Vector3.new(4.6, 1.5, 5.4), CFrame.new(0, 1.55, 0.4),
				Color3.fromRGB(150, 180, 196), Enum.Material.Glass)
			vehiclePart(model, "TechoAuto", Vector3.new(4.2, 0.3, 5.6), CFrame.new(0, 2.3, 0.4),
				color, Enum.Material.SmoothPlastic)
			for _, z in ipairs({ -3.6, 3.6 }) do
				for _, x in ipairs({ -2.6, 2.6 }) do
					vehiclePart(model, "Rueda", Vector3.new(1.0, 2.8, 2.8),
						CFrame.new(x, -1.6, z) * CFrame.Angles(0, 0, math.rad(90)),
						Color3.fromRGB(34, 34, 36), Enum.Material.Rubber, Enum.PartType.Cylinder)
				end
			end
			vehiclePart(model, "LuzA", Vector3.new(0.9, 0.4, 0.3), CFrame.new(-1.5, 0.4, -5.6),
				Color3.fromRGB(255, 240, 190), Enum.Material.Neon)
			vehiclePart(model, "LuzB", Vector3.new(0.9, 0.4, 0.3), CFrame.new(1.5, 0.4, -5.6),
				Color3.fromRGB(255, 240, 190), Enum.Material.Neon)
			vehiclePart(model, "LuzTrasera", Vector3.new(3.6, 0.35, 0.25), CFrame.new(0, 0.5, 5.6),
				Color3.fromRGB(200, 50, 40), Enum.Material.Neon)
			model.PrimaryPart = body
			return model
		end

		local function makeBus()
			local model = Instance.new("Model")
			model.Name = "Colectivo"
			model.Parent = folder
			local body = vehiclePart(model, "ChasisBus", Vector3.new(5.6, 3.2, 22), CFrame.new(0, 0, 0),
				Color3.fromRGB(70, 120, 190), Enum.Material.SmoothPlastic)
			vehiclePart(model, "VentanasBus", Vector3.new(5.7, 1.3, 16), CFrame.new(0, 0.9, 0),
				Color3.fromRGB(150, 190, 205), Enum.Material.Glass)
			vehiclePart(model, "TechoBus", Vector3.new(5.2, 0.3, 22.4), CFrame.new(0, 1.75, 0),
				Color3.fromRGB(238, 238, 240), Enum.Material.SmoothPlastic)
			vehiclePart(model, "FranjaBus", Vector3.new(5.65, 0.5, 22.1), CFrame.new(0, -0.6, 0),
				Color3.fromRGB(230, 230, 234), Enum.Material.SmoothPlastic)
			for _, z in ipairs({ -7.5, 0, 7.5 }) do
				for _, x in ipairs({ -2.9, 2.9 }) do
					vehiclePart(model, "RuedaBus", Vector3.new(1.1, 3.0, 3.0),
						CFrame.new(x, -1.7, z) * CFrame.Angles(0, 0, math.rad(90)),
						Color3.fromRGB(32, 32, 34), Enum.Material.Rubber, Enum.PartType.Cylinder)
				end
			end
			vehiclePart(model, "LuzBusA", Vector3.new(1.0, 0.5, 0.3), CFrame.new(-1.8, -0.5, -11.1),
				Color3.fromRGB(255, 240, 190), Enum.Material.Neon)
			vehiclePart(model, "LuzBusB", Vector3.new(1.0, 0.5, 0.3), CFrame.new(1.8, -0.5, -11.1),
				Color3.fromRGB(255, 240, 190), Enum.Material.Neon)
			model.PrimaryPart = body
			return model
		end

		local function makeTrain()
			local model = Instance.new("Model")
			model.Name = "Tren"
			model.Parent = folder
			local body = vehiclePart(model, "Locomotora", Vector3.new(6.0, 4.6, 30), CFrame.new(0, 0, 8),
				Color3.fromRGB(214, 178, 60), Enum.Material.Metal)
			vehiclePart(model, "Vagon", Vector3.new(6.0, 4.2, 34), CFrame.new(0, -0.1, -24),
				Color3.fromRGB(194, 74, 64), Enum.Material.Metal)
			vehiclePart(model, "VentanaVagon", Vector3.new(6.1, 1.2, 26), CFrame.new(0, 0.4, -24),
				Color3.fromRGB(150, 190, 205), Enum.Material.Glass)
			vehiclePart(model, "TechoTren", Vector3.new(5.4, 0.3, 62), CFrame.new(0, 2.4, -8),
				Color3.fromRGB(92, 84, 76), Enum.Material.Metal)
			vehiclePart(model, "LuzTren", Vector3.new(1.2, 1.2, 0.4), CFrame.new(0, 0.6, -8.4),
				Color3.fromRGB(255, 246, 200), Enum.Material.Neon)
			for _, z in ipairs({ 18, 14, -8, -14, -30, -36 }) do
				for _, x in ipairs({ -3.1, 3.1 }) do
					vehiclePart(model, "RuedaTren", Vector3.new(1.0, 2.6, 2.6),
						CFrame.new(x, -2.4, z) * CFrame.Angles(0, 0, math.rad(90)),
						Color3.fromRGB(40, 40, 44), Enum.Material.Metal, Enum.PartType.Cylinder)
				end
			end
			model.PrimaryPart = body
			return model
		end

		-- Camino del anillo (esquinas cortadas para que doblen suave)
		local lane = R + 8
		local ringPts = {}
		for k = 0, 7 do
			local ang = k * math.pi / 4
			local c, s = math.cos(ang), math.sin(ang)
			local m = math.max(math.abs(c), math.abs(s))
			local len = lane / m
			if k % 2 == 1 then
				len = len * 0.92
			end
			table.insert(ringPts, center + Vector3.new(c * len, 0, s * len))
		end
		local ringCum, ringTotal = { 0 }, 0
		for i = 1, #ringPts - 1 do
			ringTotal = ringTotal + (ringPts[i + 1] - ringPts[i]).Magnitude
			ringCum[i + 1] = ringTotal
		end

		-- Deja el vehiculo estacionado en su punto de partida
		local function parkVehicle(veh)
			local s = veh.startDist or 0
			for i = 1, #veh.pts - 1 do
				if s <= veh.cum[i + 1] or i == #veh.pts - 1 then
					local segLen = math.max(veh.cum[i + 1] - veh.cum[i], 0.001)
					local t = math.clamp((s - veh.cum[i]) / segLen, 0, 1)
					local pos = veh.pts[i]:Lerp(veh.pts[i + 1], t)
					local dir = (veh.pts[i + 1] - veh.pts[i]).Unit
					local base = Vector3.new(pos.X, veh.baseY, pos.Z)
					veh.model:PivotTo(CFrame.lookAt(base, base + dir))
					return
				end
			end
		end

		local function addVehicle(veh)
			table.insert(self.traffic, veh)
			parkVehicle(veh)
		end

		for i, color in ipairs({ CAR_COLORS[1], CAR_COLORS[2], CAR_COLORS[3] }) do
			addVehicle({
				model = makeCar(color),
				pts = ringPts, cum = ringCum, total = ringTotal,
				dist = 0, startDist = ringTotal * (i - 1) * 0.31, dir = 1,
				speed = Config.City.speedCar,
				baseY = floorY + 3.05,
				halfW = 3.2, halfL = 6.2,
				label = Config.Text.CarHit,
			})
		end
		addVehicle({
			model = makeBus(),
			pts = ringPts, cum = ringCum, total = ringTotal,
			dist = 0, startDist = ringTotal * 0.52, dir = 1,
			speed = Config.City.speedBus,
			baseY = floorY + 3.25,
			halfW = 3.6, halfL = 12.0,
			label = Config.Text.BusHit,
		})

		local trainPts = {
			Vector3.new(center.X - trackHalf, 0, trackZ),
			Vector3.new(center.X + trackHalf, 0, trackZ),
		}
		local trainTotal = (trainPts[2] - trainPts[1]).Magnitude
		addVehicle({
			model = makeTrain(),
			pts = trainPts, cum = { 0, trainTotal }, total = trainTotal,
			dist = 0, startDist = 0, dir = 1,
			speed = Config.City.speedTrain,
			shuttle = true, wait = Config.City.trainWait,
			baseY = floorY + 3.75,
			halfW = 3.9, halfL = 30,
			label = Config.Text.TrainHit,
		})
	end

	-- Zona central despejada para que aparezca el kiwi
	table.insert(occupied, center + Vector3.new(0, 0, 0))

	if theme == "bosque" then
		for i = 1, 34 do
			local p = freeSpot(22)
			if p then
				makeBush(p)
			end
		end

		for i = 1, 16 do
			local p = freeSpot(24)
			if p then
				makeFern(p)
			end
		end

		for i = 1, 12 do
			local p = freeSpot(26)
			if p then
				makeLog(p)
			end
		end

		for i = 1, 15 do
			local p = freeSpot(26)
			if p then
				makeRocks(p)
			end
		end

		for i = 1, 12 do
			local p = freeSpot(28)
			if p then
				makeBurrow(p)
			end
		end

		for i = 1, 18 do
			local p = freeSpot(26)
			if p then
				makeGrassPatch(p)
			end
		end

		for i = 1, 40 do
			local p = freeSpot(18)
			if p then
				makeTree(p)
			end
		end
	elseif theme == "dunas" then
		for i = 1, 14 do
			local p = freeSpot(24)
			if p then
				makeCactus(p)
			end
		end

		for i = 1, 16 do
			local p = freeSpot(26)
			if p then
				makeDuneMound(p)
			end
		end

		for i = 1, 16 do
			local p = freeSpot(24)
			if p then
				makeRocks(p)
			end
		end

		for i = 1, 8 do
			local p = freeSpot(28)
			if p then
				makeBurrow(p)
			end
		end

		for i = 1, 6 do
			local p = freeSpot(26)
			if p then
				makeGrassPatch(p)
			end
		end
	elseif theme == "ciudad" then
		for i = 1, 14 do
			local p = freeSpot(22)
			if p then
				makeTree(p)
			end
		end

		for i = 1, 8 do
			local p = freeSpot(22)
			if p then
				makeBush(p)
			end
		end

		for i = 1, 14 do
			local p = freeSpot(20)
			if p then
				makeLampPost(p)
			end
		end

		for i = 1, 8 do
			local p = freeSpot(22)
			if p then
				makeBench(p)
			end
		end

		for i = 1, 6 do
			local p = freeSpot(26)
			if p then
				makeRocks(p)
			end
		end
	elseif theme == "costa" then
		for i = 1, 20 do
			local p = freeSpot(22)
			if p then
				makePalm(p)
			end
		end

		for i = 1, 10 do
			local p = freeSpot(22)
			if p then
				makeBush(p)
			end
		end

		for i = 1, 12 do
			local p = freeSpot(26)
			if p then
				makeLog(p)
			end
		end

		for i = 1, 10 do
			local p = freeSpot(26)
			if p then
				makeRocks(p)
			end
		end

		for i = 1, 10 do
			local p = freeSpot(26)
			if p then
				makeGrassPatch(p)
			end
		end
	elseif theme == "alpes" then
		for i = 1, 30 do
			local p = freeSpot(20)
			if p then
				makePine(p)
			end
		end

		for i = 1, 12 do
			local p = freeSpot(26)
			if p then
				makeRocks(p)
			end
		end

		for i = 1, 8 do
			local p = freeSpot(26)
			if p then
				makeLog(p)
			end
		end

		for i = 1, 6 do
			local p = freeSpot(28)
			if p then
				makeBurrow(p)
			end
		end
	end

	do
		local function freeSpotFallback(minDist, margins)
			for _, margin in ipairs(margins) do
				local point = freeSpot(minDist, margin)
				if point then
					return point
				end
			end
			return nil
		end

		local function faceCenter(point)
			return math.atan2(center.X - point.X, center.Z - point.Z)
		end

		local function placeNear(origin, gaps, minClear, build)
			local dir = rng:NextNumber(0, math.pi * 2)
			for _, gap in ipairs(gaps) do
				local cand = origin + Vector3.new(math.cos(dir) * gap, 0, math.sin(dir) * gap)
				if (cand - center).Magnitude < half - 58 then
					local clear = true
					for _, other in ipairs(occupied) do
						if (Vector3.new(cand.X, 0, cand.Z) - Vector3.new(other.X, 0, other.Z)).Magnitude < minClear then
							clear = false
							break
						end
					end
					if clear then
						table.insert(occupied, cand)
						build(cand)
						return cand
					end
				end
			end
			return nil
		end

		-- La aldea: casa, casona y granero (con interiores y baules)
		local anchor = freeSpotFallback(56, { 78, 56, 36, 22 })
		if anchor then
			makeHouse(anchor, faceCenter(anchor), "cabin")
			placeNear(anchor, { 48, 54, 60, 40 }, 50, function(cand)
				makeHouse(cand, faceCenter(cand), "farm")
			end)
			placeNear(anchor, { 56, 60, 66, 48 }, 50, function(cand)
				makeBarn(cand, faceCenter(cand))
			end)
		end

		-- Casa del Nido: la usa el modo Asedio (5 vs 5) como guarida del
		-- kiwi. Existe en todos los mapas para que el asedio tenga su casa.
		local nestSpot = freeSpotFallback(58, { 84, 58, 40, 26 })
		if nestSpot then
			makeHouse(nestSpot, faceCenter(nestSpot), "farm")
			self.nest = { pos = nestSpot }
		else
			self.nest = { pos = anchor or center }
		end

		-- Una casa mas lejos para variar el mapa
		local farHouse = freeSpotFallback(52, { 72, 52, 34, 20 })
		if farHouse then
			makeHouse(farHouse, faceCenter(farHouse), rng:NextNumber(0, 1) < 0.5 and "cabin" or "farm")
		end

		-- La ciudad suma una casa mas y su torre mirador
		if theme == "ciudad" and anchor then
			placeNear(anchor, { 64, 74, 50, 36 }, 52, function(cand)
				makeHouse(cand, faceCenter(cand), "farm")
			end)
			local skySpot = freeSpotFallback(54, { 82, 60, 40, 24 })
			if skySpot then
				makeSkyTower(skySpot)
			end
		end

		-- Baules sueltos por el mapa
		for i = 1, 2 do
			local chestSpot = freeSpotFallback(30, { 60, 42, 26 })
			if chestSpot then
				makeChestProp(CFrame.new(chestSpot) * CFrame.Angles(0, rng:NextNumber(0, math.pi * 2), 0), "Baúl")
			end
		end

		-- Torre mirador de madera (en la ciudad la reemplaza la torre alta)
		if theme ~= "ciudad" then
			local towerPos = freeSpotFallback(44, { 70, 48, 30, 18 })
			if towerPos then
				makeTower(towerPos)
			end
		end
	end

	-- ===============================================================
	-- Spawns y punto de aparicion del kiwi
	-- ===============================================================
	for i = 1, 4 do
		local baseAngle = (i - 1) * math.pi * 0.5 + math.rad(45)
		local dist = half - 45
		-- Busca un angulo donde no haya props solidos cerca (roca, cabana, etc.)
		local bestAngle = baseAngle
		for attempt = 0, 11 do
			local angle = baseAngle + attempt * math.rad(9)
			local candidate = center + Vector3.new(math.cos(angle) * dist, 0, math.sin(angle) * dist)
			local clear = true
			for _, other in ipairs(occupied) do
				if (Vector3.new(other.X, 0, other.Z) - candidate).Magnitude < 24 then
					clear = false
					break
				end
			end
			if clear then
				bestAngle = angle
				break
			end
		end
		local pos = center + Vector3.new(math.cos(bestAngle) * dist, 4, math.sin(bestAngle) * dist)
		table.insert(self.spawns, CFrame.lookAt(pos, Vector3.new(center.X, pos.Y, center.Z)))
	end

	self.kiwiSpawn = center + Vector3.new(rng:NextNumber(-45, 45), 0, rng:NextNumber(-45, 45))

	local sign = part({
		Name = "LetreroZona",
		Size = Vector3.new(1, 12, 22),
		CFrame = CFrame.new(center + Vector3.new(0, 6, -half + 26)),
		Color = Color3.fromRGB(42, 38, 34),
		Material = Enum.Material.WoodPlanks,
		CanCollide = true,
		Parent = folder,
	})
	billboardText(sign, zone.name, Color3.fromRGB(236, 230, 214), 16)

	-- Zona segura (meta del modo Colosal): el refugio circular del centro
	local zoneRadius = (cfg.SafeZone and cfg.SafeZone.radius) or 15
	local function zonePart(name, shape, size, cf, color, transparency)
		local piecePart = Instance.new("Part")
		piecePart.Name = name
		piecePart.Shape = shape
		piecePart.Size = size
		piecePart.CFrame = cf
		piecePart.Color = color
		piecePart.Material = Enum.Material.Neon
		piecePart.Transparency = transparency
		piecePart.Anchored = true
		piecePart.CanCollide = false
		piecePart.CanQuery = false
		piecePart.CanTouch = false
		piecePart.Parent = folder
		return piecePart
	end

	local zoneRing = zonePart("ZonaSegura", Enum.PartType.Cylinder,
		Vector3.new(0.3, zoneRadius * 2, zoneRadius * 2),
		CFrame.new(center + Vector3.new(0, 0.15, 0)) * CFrame.Angles(0, 0, math.rad(90)),
		Color3.fromRGB(90, 110, 130), 0.4)

	local zoneBeam = zonePart("HazZona", Enum.PartType.Cylinder,
		Vector3.new(130, 3, 3),
		CFrame.new(center + Vector3.new(0, 65, 0)) * CFrame.Angles(0, 0, math.rad(90)),
		Color3.fromRGB(120, 255, 190), 0.85)

	local zoneLight = Instance.new("PointLight")
	zoneLight.Name = "LuzZona"
	zoneLight.Color = Color3.fromRGB(120, 255, 190)
	zoneLight.Range = 42
	zoneLight.Brightness = 0
	zoneLight.Parent = zoneRing

	local zoneLabelPart = Instance.new("Part")
	zoneLabelPart.Name = "RotuloZona"
	zoneLabelPart.Size = Vector3.new(1, 1, 1)
	zoneLabelPart.CFrame = CFrame.new(center + Vector3.new(0, 7, 0))
	zoneLabelPart.Transparency = 1
	zoneLabelPart.Anchored = true
	zoneLabelPart.CanCollide = false
	zoneLabelPart.CanQuery = false
	zoneLabelPart.CanTouch = false
	zoneLabelPart.Parent = folder

	local zoneGui = Instance.new("BillboardGui")
	zoneGui.Name = "RotuloZona"
	zoneGui.Size = UDim2.fromScale(14, 3)
	zoneGui.AlwaysOnTop = true
	zoneGui.Parent = zoneLabelPart

	local zoneLabel = Instance.new("TextLabel")
	zoneLabel.Size = UDim2.fromScale(1, 1)
	zoneLabel.BackgroundTransparency = 1
	zoneLabel.Font = Enum.Font.GothamBlack
	zoneLabel.TextScaled = true
	zoneLabel.TextColor3 = Color3.fromRGB(150, 200, 220)
	zoneLabel.TextStrokeTransparency = 0.25
	zoneLabel.Text = "ZONA SEGURA (se activa mas tarde)"
	zoneLabel.Parent = zoneGui

	self.safeZone = {
		center = center,
		radius = zoneRadius,
		active = false,
		ring = zoneRing,
		beam = zoneBeam,
		light = zoneLight,
		label = zoneLabel,
	}

	return self
end

-- ===============================================================
-- API principal
-- ===============================================================
function WorldBuilder.build(cfg)
	-- Mapas aleatorios: cada servidor arma una reserva distinta
	local seed = cfg.World.Seed or 1
	if cfg.World.RandomMaps ~= false then
		seed = seed * 7919 + os.time() % 1000003 + math.random(0, 9999)
	end
	local rng = Random.new(seed)

	local root = Instance.new("Folder")
	root.Name = "KiwiWorld"
	root.Parent = workspace

	local lobby = buildLobby(cfg, root, rng)

	local arenas = {}
	for i = 1, cfg.World.ArenaCount do
		local zone = cfg.Zones[((i - 1) % #cfg.Zones) + 1]
		arenas[i] = buildArena(i, zone, cfg, root, rng)
	end

	-- Iluminacion de reserva natural
	local Lighting = game:GetService("Lighting")
	Lighting.Brightness = 2.6
	Lighting.ClockTime = 15.5
	Lighting.GeographicLatitude = -41.5
	Lighting.Ambient = Color3.fromRGB(82, 88, 96)
	Lighting.OutdoorAmbient = Color3.fromRGB(122, 132, 140)
	Lighting.FogColor = Color3.fromRGB(178, 198, 205)
	Lighting.FogEnd = 1400
	Lighting.FogStart = 320
	Lighting.EnvironmentDiffuseScale = 0.4
	Lighting.EnvironmentSpecularScale = 0.35

	if not Lighting:FindFirstChildOfClass("Atmosphere") then
		local atmosphere = Instance.new("Atmosphere")
		atmosphere.Density = 0.28
		atmosphere.Offset = 0.15
		atmosphere.Color = Color3.fromRGB(210, 220, 225)
		atmosphere.Decay = Color3.fromRGB(106, 112, 116)
		atmosphere.Glare = 0.25
		atmosphere.Haze = 1.1
		atmosphere.Parent = Lighting
	end

	local bloom = Instance.new("BloomEffect")
	bloom.Intensity = 0.45
	bloom.Size = 22
	bloom.Threshold = 1.4
	bloom.Parent = Lighting

	return {
		root = root,
		lobby = lobby,
		arenas = arenas,
	}
end

return WorldBuilder
