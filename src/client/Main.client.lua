--[[
	Main.client.lua  (cliente)
	Une todo del lado del jugador:
		- menu del lobby y HUD
		- teclas de caminar (Shift) y sigilo (Ctrl)
		- uso de las herramientas (red, rifle, rastreador, trampa, pintura)
		- efectos, sonidos y brujula del rastreador
--]]

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local Debris = game:GetService("Debris")
local TweenService = game:GetService("TweenService")

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("KiwiShared", 30)
if not Shared then
	error("[Kiwi Cazador] Falta ReplicatedStorage.KiwiShared (revisa el README)")
end

local Config = require(Shared.Config)
local Net = require(Shared.Net)
local Util = require(Shared.Util)

local HUD = require(script.Parent.modules.HUD)
local ViewModel = require(script.Parent.modules.ViewModel)
local WeatherFX = require(script.Parent.modules.WeatherFX)

local player = Players.LocalPlayer
local remotes = Net.init()

-- Lluvia y nieve: efectos locales que siguen a la camara
WeatherFX.start()

local state = { active = false, phase = "none", diff = nil }
local sprinting = false
local sneaking = false
local gameMenuOpen = false
local switchPending = false
local glockBurst = false -- la Glock-18 arranca tiro a tiro; el clic derecho la pone en ráfaga
local shotBloom = 0 -- el punto de mira se abre un toque al disparar
local speedFov = nil -- al correr la camara abre un poco el FOV (se siente mas rapido)
local cooldowns = {
	red = { left = 0, total = 1 },
	rifle = { left = 0, total = 1 },
	rastreador = { left = 0, total = 1 },
	trampa = { left = 0, total = 1 },
	pintura = { left = 0, total = 1 },
	relente = { left = 0, total = 1 },
}
local eatCam = nil

-- ===============================================================
-- Sonidos y efectos
-- ===============================================================
local function soundAt(soundId, position, volume, pitch)
	if not soundId or soundId == "" then
		return
	end

	local holder = Instance.new("Part")
	holder.Name = "FxSonido"
	holder.Size = Vector3.new(1, 1, 1)
	holder.Anchored = true
	holder.CanCollide = false
	holder.CanQuery = false
	holder.CanTouch = false
	holder.Transparency = 1
	holder.Position = position
	holder.Parent = workspace

	local sound = Instance.new("Sound")
	sound.SoundId = soundId
	sound.Volume = volume or 1
	sound.RollOffMaxDistance = 260
	sound.RollOffMinDistance = 8
	if pitch then
		sound.PlaybackSpeed = pitch
	end
	sound.Parent = holder
	sound:Play()
	Debris:AddItem(holder, 5)
end

local function sound2D(soundId, volume, pitch)
	if not soundId or soundId == "" then
		return
	end
	local sound = Instance.new("Sound")
	sound.SoundId = soundId
	sound.Volume = volume or 1
	sound.Parent = player:FindFirstChildOfClass("PlayerGui") or workspace
	if pitch then
		sound.PlaybackSpeed = pitch
	end
	sound:Play()
	Debris:AddItem(sound, 5)
end

-- ===============================================================
-- Pasos: solo se escuchan al correr. Con Shift (caminar) o agachado
-- no haces ruido. Ademas se apaga el sonido de pasos por defecto.
-- ===============================================================
local pasoAcumulado = {}

local function sonidoPaso(position, volume, pitch)
	local holder = Instance.new("Part")
	holder.Name = "FxPaso"
	holder.Size = Vector3.new(1, 1, 1)
	holder.Anchored = true
	holder.CanCollide = false
	holder.CanQuery = false
	holder.CanTouch = false
	holder.Transparency = 1
	holder.Position = position
	holder.Parent = workspace

	local sound = Instance.new("Sound")
	sound.SoundId = Config.Sounds.steps
	sound.Volume = volume
	sound.RollOffMinDistance = 5
	sound.RollOffMaxDistance = 85
	sound.PlaybackSpeed = pitch or 1
	sound.Parent = holder
	sound:Play()
	Debris:AddItem(holder, 3)
end

local function updatePasos(dt)
	local umbral = (Config.Footsteps and Config.Footsteps.runSpeed) or 19
	for _, other in ipairs(Players:GetPlayers()) do
		local character = other.Character
		local root = character and character:FindFirstChild("HumanoidRootPart")
		local humanoid = character and character:FindFirstChildOfClass("Humanoid")

		-- Apaga el "Running" que trae Roblox por defecto: asi solo suenan
		-- nuestros pasos, y solo cuando corresponde
		if root then
			local porDefecto = root:FindFirstChild("Running")
			if not porDefecto then
				local emisor = root:FindFirstChildOfClass("AudioEmitter")
				porDefecto = emisor and emisor:FindFirstChild("Running")
			end
			if porDefecto and (porDefecto:IsA("Sound") or porDefecto:IsA("AudioPlayer")) then
				porDefecto.Volume = 0
			end
		end

		local pisa = root and humanoid and humanoid.Health > 0
			and humanoid.FloorMaterial ~= Enum.Material.Air
		if pisa then
			local v = root.AssemblyLinearVelocity
			local rapidez = math.sqrt(v.X * v.X + v.Z * v.Z)
			if rapidez >= umbral then
				local acumulado = (pasoAcumulado[other] or 0) + dt
				local intervalo = math.clamp(10.5 / math.max(rapidez, 1), 0.24, 0.6)
				if acumulado >= intervalo then
					acumulado = 0
					-- Un tono distinto por jugador para no sonar todos igual
					local tono = 0.94 + (other.UserId % 4) * 0.03
					sonidoPaso(root.Position + Vector3.new(0, -1.7, 0), other == player and 0.4 or 0.5, tono)
				end
				pasoAcumulado[other] = acumulado
			else
				pasoAcumulado[other] = nil
			end
		else
			pasoAcumulado[other] = nil
		end
	end
end

-- ===============================================================
-- Disparos armados por capas (los sonidos de Roblox no traen balas)
-- Cada estilo mezcla un golpe grave distorsionado (boom), un chasquido
-- seco (crack) y una cola corta del estampido. Los Sound se reutilizan
-- de un pool para no crear instancias en cada rafaga automatica.
-- ===============================================================
local GUN_SHOT = {
	-- estilo = { { sonido, volumen, tono, distorsion }, ... }
	pistol = { { "gunBoom", 0.50, 1.15, 0.30 }, { "gunCrack", 0.45, 1.55, 0.50 }, { "gunTail", 0.15, 1.65, 0.00 } },
	smg = { { "gunBoom", 0.45, 1.25, 0.30 }, { "gunCrack", 0.42, 1.65, 0.45 }, { "gunTail", 0.13, 1.75, 0.00 } },
	rifle = { { "gunBoom", 0.62, 0.95, 0.45 }, { "gunCrack", 0.50, 1.30, 0.55 }, { "gunTail", 0.26, 1.40, 0.00 } },
	heavy = { { "gunBoom", 0.72, 0.85, 0.50 }, { "gunCrack", 0.54, 1.20, 0.60 }, { "gunTail", 0.36, 1.30, 0.05 } },
	shotgun = { { "gunBoom", 0.80, 0.72, 0.55 }, { "gunCrack", 0.50, 1.05, 0.60 }, { "gunTail", 0.50, 1.05, 0.10 } },
	sniper = { { "gunBoom", 0.82, 0.82, 0.50 }, { "gunCrack", 0.62, 1.15, 0.65 }, { "gunTail", 0.45, 1.15, 0.15 } },
	dart = { { "gunCrack", 0.30, 1.45, 0.15 }, { "dartShot", 0.30, 1.30, 0.00 } },
	rocket = { { "gunBoom", 0.70, 0.60, 0.25 }, { "gunCrack", 0.25, 0.85, 0.10 }, { "dartShot", 0.35, 0.55, 0.00 } },
}

-- Arma -> estilo de sonido
local GUN_STYLE = {
	revolver = "pistol", glock = "pistol",
	mp5 = "smg",
	ak = "rifle", m4 = "rifle",
	rifle = "dart", pintura = "dart", relente = "dart",
	escopeta = "shotgun",
	sniper = "sniper",
	cohete = "rocket",
}

local GUN_POOL_SIZE = 16
local gunPool = {}
local gunPoolIndex = 0

local function gunPlay(soundId, volume, pitch, distortion)
	local slot = (gunPoolIndex % GUN_POOL_SIZE) + 1
	gunPoolIndex = gunPoolIndex + 1
	local entry = gunPool[slot]
	if not entry then
		local sound = Instance.new("Sound")
		sound.Parent = player:FindFirstChildOfClass("PlayerGui") or workspace
		local dist = Instance.new("DistortionSoundEffect")
		dist.Level = distortion or 0
		dist.Parent = sound
		local eq = Instance.new("EqualizerSoundEffect")
		eq.LowGain = 5
		eq.MidGain = -2
		eq.HighGain = 2
		eq.Parent = sound
		entry = { sound = sound, dist = dist, lastId = nil }
		gunPool[slot] = entry
	end
	local sound = entry.sound
	if entry.lastId ~= soundId then
		sound.SoundId = soundId
		entry.lastId = soundId
	end
	sound.Volume = volume
	sound.PlaybackSpeed = pitch or 1
	entry.dist.Level = distortion or 0
	sound.TimePosition = 0
	sound:Play()
end

local function gunshot(style)
	local layers = GUN_SHOT[style]
	if not layers then
		return
	end
	for _, layer in ipairs(layers) do
		local id = Config.Sounds[layer[1]]
		if id then
			gunPlay(id, layer[2], layer[3], layer[4])
		end
	end
end

local function burst(position, color, count)
	local holder = Instance.new("Part")
	holder.Name = "FxParticulas"
	holder.Size = Vector3.new(1, 1, 1)
	holder.Anchored = true
	holder.CanCollide = false
	holder.CanQuery = false
	holder.CanTouch = false
	holder.Transparency = 1
	holder.Position = position
	holder.Parent = workspace

	local emitter = Instance.new("ParticleEmitter")
	emitter.Color = ColorSequence.new(color)
	emitter.Size = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 1.6),
		NumberSequenceKeypoint.new(1, 0.15),
	})
	emitter.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.15),
		NumberSequenceKeypoint.new(1, 1),
	})
	emitter.Lifetime = NumberRange.new(0.35, 0.75)
	emitter.Speed = NumberRange.new(10, 22)
	emitter.SpreadAngle = Vector2.new(180, 180)
	emitter.Rate = 0
	emitter.LightEmission = 0.3
	emitter.Parent = holder
	emitter:Emit(count or 22)

	Debris:AddItem(holder, 2)
end

-- Fogonazo de luz que se apaga solo (explosiones y el molotov)
local function lightFlash(position, color, brillo, alcance)
	local holder = Instance.new("Part")
	holder.Name = "FxLuz"
	holder.Size = Vector3.new(0.2, 0.2, 0.2)
	holder.Anchored = true
	holder.CanCollide = false
	holder.CanQuery = false
	holder.CanTouch = false
	holder.Transparency = 1
	holder.Position = position
	holder.Parent = workspace

	local light = Instance.new("PointLight")
	light.Color = color
	light.Brightness = brillo
	light.Range = alcance
	light.Shadows = false
	light.Parent = holder

	Debris:AddItem(holder, 0.6)
	task.spawn(function()
		for i = 1, 9 do
			task.wait(0.05)
			if light and light.Parent then
				light.Brightness = brillo * (1 - i / 9)
			end
		end
	end)
end

-- ===============================================================
-- Lanzallamas: chorro de fuego visible (todo por codigo, sin assets)
-- ===============================================================
local flameRigs = {}

local function getFlameRig(key)
	local rig = flameRigs[key]
	if rig then
		return rig
	end
	local part = Instance.new("Part")
	part.Name = "ChorroLlama"
	part.Size = Vector3.new(0.4, 0.4, 0.4)
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.CastShadow = false
	part.Transparency = 1
	part.Parent = workspace

	local emitter = Instance.new("ParticleEmitter")
	emitter.Name = "Llama"
	emitter.Texture = "rbxasset://textures/particles/fire_main.dds"
	emitter.Color = ColorSequence.new({
		ColorSequenceKeypoint.new(0, Color3.fromRGB(255, 236, 170)),
		ColorSequenceKeypoint.new(0.35, Color3.fromRGB(255, 156, 58)),
		ColorSequenceKeypoint.new(0.75, Color3.fromRGB(232, 84, 22)),
		ColorSequenceKeypoint.new(1, Color3.fromRGB(120, 26, 8)),
	})
	emitter.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.12),
		NumberSequenceKeypoint.new(0.7, 0.55),
		NumberSequenceKeypoint.new(1, 1),
	})
	emitter.Size = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 1.3),
		NumberSequenceKeypoint.new(0.55, 3.2),
		NumberSequenceKeypoint.new(1, 4.8),
	})
	emitter.Lifetime = NumberRange.new(0.42, 0.68)
	emitter.Speed = NumberRange.new(19, 30)
	emitter.SpreadAngle = Vector2.new(5, 5)
	emitter.Acceleration = Vector3.new(0, 5, 0)
	emitter.Rotation = NumberRange.new(-180, 180)
	emitter.RotSpeed = NumberRange.new(-70, 70)
	emitter.LightEmission = 1
	emitter.LightInfluence = 0
	emitter.Rate = 65
	emitter.Enabled = false
	emitter.Parent = part

	-- Corazon blanco del chorro: nace pegado al pico y le da temperatura
	local nucleo = Instance.new("ParticleEmitter")
	nucleo.Name = "Nucleo"
	nucleo.Texture = "rbxasset://textures/particles/fire_main.dds"
	nucleo.Color = ColorSequence.new({
		ColorSequenceKeypoint.new(0, Color3.fromRGB(255, 252, 236)),
		ColorSequenceKeypoint.new(0.5, Color3.fromRGB(255, 226, 150)),
		ColorSequenceKeypoint.new(1, Color3.fromRGB(255, 172, 74)),
	})
	nucleo.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.2),
		NumberSequenceKeypoint.new(1, 1),
	})
	nucleo.Size = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.7),
		NumberSequenceKeypoint.new(1, 1.9),
	})
	nucleo.Lifetime = NumberRange.new(0.16, 0.28)
	nucleo.Speed = NumberRange.new(30, 42)
	nucleo.SpreadAngle = Vector2.new(2, 2)
	nucleo.LightEmission = 1
	nucleo.LightInfluence = 0
	nucleo.Rate = 70
	nucleo.Enabled = false
	nucleo.Parent = part

	-- Chispas que se desprenden del chorro y caen al piso
	local chispas = Instance.new("ParticleEmitter")
	chispas.Name = "Chispas"
	chispas.Texture = "rbxasset://textures/particles/sparkles_main.dds"
	chispas.Color = ColorSequence.new({
		ColorSequenceKeypoint.new(0, Color3.fromRGB(255, 226, 150)),
		ColorSequenceKeypoint.new(1, Color3.fromRGB(255, 138, 40)),
	})
	chispas.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.1),
		NumberSequenceKeypoint.new(0.7, 0.4),
		NumberSequenceKeypoint.new(1, 1),
	})
	chispas.Size = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.34),
		NumberSequenceKeypoint.new(1, 0.06),
	})
	chispas.Lifetime = NumberRange.new(0.5, 1.0)
	chispas.Speed = NumberRange.new(12, 26)
	chispas.SpreadAngle = Vector2.new(14, 14)
	chispas.Acceleration = Vector3.new(0, -34, 0)
	chispas.LightEmission = 1
	chispas.LightInfluence = 0
	chispas.Rate = 22
	chispas.Enabled = false
	chispas.Parent = part

	-- Humo agrisado que se desprende del chorro (misma textura del fuego,
	-- apagada: no hace falta ningun asset nuevo)
	local humo = Instance.new("ParticleEmitter")
	humo.Name = "Humo"
	humo.Texture = "rbxasset://textures/particles/fire_main.dds"
	humo.Color = ColorSequence.new({
		ColorSequenceKeypoint.new(0, Color3.fromRGB(96, 90, 86)),
		ColorSequenceKeypoint.new(1, Color3.fromRGB(52, 48, 46)),
	})
	humo.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.82),
		NumberSequenceKeypoint.new(0.6, 0.9),
		NumberSequenceKeypoint.new(1, 0.98),
	})
	humo.Size = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 2.2),
		NumberSequenceKeypoint.new(1, 5.4),
	})
	humo.Lifetime = NumberRange.new(1.0, 1.7)
	humo.Speed = NumberRange.new(5, 9)
	humo.SpreadAngle = Vector2.new(9, 9)
	humo.Acceleration = Vector3.new(0, 3.4, 0)
	humo.Rotation = NumberRange.new(-180, 180)
	humo.RotSpeed = NumberRange.new(-40, 40)
	humo.LightEmission = 0
	humo.LightInfluence = 1
	humo.Rate = 13
	humo.Enabled = false
	humo.Parent = part

	local light = Instance.new("PointLight")
	light.Name = "LuzLlama"
	light.Color = Color3.fromRGB(255, 150, 70)
	light.Range = 20
	light.Brightness = 2.1
	light.Shadows = false
	light.Enabled = false
	light.Parent = part

	rig = { part = part, emitters = { emitter, nucleo, chispas, humo }, light = light, until_ = 0 }
	flameRigs[key] = rig
	return rig
end

-- Enciende (o refresca) el chorro en esa posicion y direccion
local function flameAt(key, position, direction)
	local rig = getFlameRig(key)
	local look = direction.Magnitude > 0.01 and direction.Unit or Vector3.new(0, 0, -1)
	-- El chorro tiembla apenas al salir: nada de un cono rigido
	look = CFrame.Angles(math.rad(math.random(-14, 14) / 8), math.rad(math.random(-12, 12) / 8), 0) * look
	rig.part.CFrame = CFrame.lookAt(position, position + look)
	for _, em in ipairs(rig.emitters) do
		em.Enabled = true
	end
	rig.light.Enabled = true
	rig.light.Brightness = 2.1 + math.random() * 1.3
	rig.until_ = os.clock() + 0.4
end

-- Fuego que queda prendido donde pega el chorro (paredes, objetos, gente):
-- se apaga solo si dejás de alimentarlo
local fireSpots = {}

local function getFireSpot(key)
	local spot = fireSpots[key]
	if spot then
		return spot
	end
	local part = Instance.new("Part")
	part.Name = "FuegoImpacto"
	part.Size = Vector3.new(0.4, 0.4, 0.4)
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.CastShadow = false
	part.Transparency = 1
	part.Parent = workspace

	local emitter = Instance.new("ParticleEmitter")
	emitter.Name = "Llamas"
	emitter.Texture = "rbxasset://textures/particles/fire_main.dds"
	emitter.Color = ColorSequence.new({
		ColorSequenceKeypoint.new(0, Color3.fromRGB(255, 236, 170)),
		ColorSequenceKeypoint.new(0.35, Color3.fromRGB(255, 140, 52)),
		ColorSequenceKeypoint.new(1, Color3.fromRGB(130, 26, 8)),
	})
	emitter.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.25),
		NumberSequenceKeypoint.new(1, 1),
	})
	emitter.Size = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.9),
		NumberSequenceKeypoint.new(0.6, 1.7),
		NumberSequenceKeypoint.new(1, 2.6),
	})
	emitter.Lifetime = NumberRange.new(0.45, 0.9)
	emitter.Speed = NumberRange.new(3, 8)
	emitter.SpreadAngle = Vector2.new(30, 30)
	emitter.Acceleration = Vector3.new(0, 9, 0)
	emitter.Rotation = NumberRange.new(-180, 180)
	emitter.RotSpeed = NumberRange.new(-90, 90)
	emitter.Rate = 28
	emitter.LightEmission = 1
	emitter.LightInfluence = 0
	emitter.Enabled = false
	emitter.Parent = part

	-- Brasitas que saltan de la llama prendida
	local chispas = Instance.new("ParticleEmitter")
	chispas.Name = "Chispas"
	chispas.Texture = "rbxasset://textures/particles/sparkles_main.dds"
	chispas.Color = ColorSequence.new({
		ColorSequenceKeypoint.new(0, Color3.fromRGB(255, 214, 130)),
		ColorSequenceKeypoint.new(1, Color3.fromRGB(255, 120, 36)),
	})
	chispas.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.2),
		NumberSequenceKeypoint.new(1, 1),
	})
	chispas.Size = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.22),
		NumberSequenceKeypoint.new(1, 0.05),
	})
	chispas.Lifetime = NumberRange.new(0.4, 0.9)
	chispas.Speed = NumberRange.new(6, 14)
	chispas.SpreadAngle = Vector2.new(26, 26)
	chispas.Acceleration = Vector3.new(0, -26, 0)
	chispas.LightEmission = 1
	chispas.LightInfluence = 0
	chispas.Rate = 14
	chispas.Enabled = false
	chispas.Parent = part

	-- Humo corto subiendo de la llama
	local humo = Instance.new("ParticleEmitter")
	humo.Name = "Humo"
	humo.Texture = "rbxasset://textures/particles/fire_main.dds"
	humo.Color = ColorSequence.new({
		ColorSequenceKeypoint.new(0, Color3.fromRGB(92, 86, 82)),
		ColorSequenceKeypoint.new(1, Color3.fromRGB(50, 46, 44)),
	})
	humo.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.84),
		NumberSequenceKeypoint.new(1, 0.98),
	})
	humo.Size = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 1.0),
		NumberSequenceKeypoint.new(1, 2.6),
	})
	humo.Lifetime = NumberRange.new(0.7, 1.3)
	humo.Speed = NumberRange.new(3, 6)
	humo.SpreadAngle = Vector2.new(14, 14)
	humo.Acceleration = Vector3.new(0, 2.6, 0)
	humo.Rotation = NumberRange.new(-180, 180)
	humo.RotSpeed = NumberRange.new(-40, 40)
	humo.LightEmission = 0
	humo.LightInfluence = 1
	humo.Rate = 10
	humo.Enabled = false
	humo.Parent = part

	local light = Instance.new("PointLight")
	light.Name = "LuzFuego"
	light.Color = Color3.fromRGB(255, 140, 60)
	light.Range = 12
	light.Brightness = 1.3
	light.Shadows = false
	light.Enabled = false
	light.Parent = part

	spot = { part = part, emitters = { emitter, chispas, humo }, light = light, until_ = 0 }
	fireSpots[key] = spot
	return spot
end

-- Prende (o refresca) una llama pegada a la superficie donde choco el chorro
local function fireSpotAt(key, position, normal)
	local spot = getFireSpot(key)
	local up = normal and normal.Magnitude > 0.01 and normal.Unit or Vector3.new(0, 1, 0)
	local base = position + up * 0.25
	spot.part.CFrame = CFrame.lookAt(base, base + up)
	for _, em in ipairs(spot.emitters) do
		em.Enabled = true
	end
	spot.light.Enabled = true
	spot.until_ = os.clock() + 1.1
end

-- Raycast del chorro (se reusa: nada de tablas nuevas por frame)
local flameSpotParams = RaycastParams.new()
flameSpotParams.FilterType = Enum.RaycastFilterType.Exclude
flameSpotParams.IgnoreWater = true

-- Apaga los chorros y el fuego prendido que quedo sin refrescar (lo llama el Heartbeat)
local function flameCleanup()
	local now = os.clock()
	for _, rig in pairs(flameRigs) do
		if rig.emitters[1].Enabled and now > rig.until_ then
			for _, em in ipairs(rig.emitters) do
				em.Enabled = false
			end
			rig.light.Enabled = false
		elseif rig.light.Enabled then
			-- Mientras el chorro sale, la luz titila como fuego de verdad
			rig.light.Brightness = 1.7 + math.random() * 1.5
		end
	end
	for _, spot in pairs(fireSpots) do
		if spot.emitters[1].Enabled and now > spot.until_ then
			for _, em in ipairs(spot.emitters) do
				em.Enabled = false
			end
			spot.light.Enabled = false
		elseif spot.light.Enabled then
			spot.light.Brightness = 0.9 + math.random() * 0.9
		end
	end
end

-- Soplete: sonido en loop mientras sale el chorro
local flameSound = nil
local function setFlameSound(on)
	if on then
		if not flameSound then
			flameSound = Instance.new("Sound")
			flameSound.Name = "Soplete"
			flameSound.SoundId = Config.Sounds.flame
			flameSound.Looped = true
			flameSound.Volume = 0.42
			flameSound.PlaybackSpeed = 0.42
			flameSound.Parent = player:FindFirstChildOfClass("PlayerGui") or workspace
		end
		if not flameSound.IsPlaying then
			flameSound:Play()
		end
	elseif flameSound and flameSound.IsPlaying then
		flameSound:Stop()
	end
end

-- Trazadora estilo Counter: una linea neon que se apaga al instante
local function tracer(from, dir, length, color, thickness)
	local beam = Instance.new("Part")
	beam.Name = "FxTrazadora"
	beam.Anchored = true
	beam.CanCollide = false
	beam.CanQuery = false
	beam.CanTouch = false
	beam.CastShadow = false
	beam.Material = Enum.Material.Neon
	beam.Color = color or Color3.fromRGB(255, 240, 190)
	beam.Size = Vector3.new(thickness or 0.1, thickness or 0.1, length)
	local center = from + dir * (length * 0.5)
	beam.CFrame = CFrame.lookAt(center, center + dir)
	beam.Transparency = 0.2
	beam.Parent = workspace
	Debris:AddItem(beam, 0.09)
end

local function distanceToLocal(position)
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if not root then
		return math.huge
	end
	return (root.Position - position).Magnitude
end

-- ===============================================================
-- Velocidad y estado del personaje
-- ===============================================================
local function humanoid()
	local character = player.Character
	return character and character:FindFirstChildOfClass("Humanoid") or nil
end

local hiddenNow = false -- escondido en un armario/barril/pajar: no te moves
local scoped = false
local scopeLevel = 0
local equippedId = nil

local function applySpeed()
	local hum = humanoid()
	if not hum then
		return
	end

	-- Menú de partida abierto: el personaje queda quieto mientras elegís
	if gameMenuOpen then
		hum.WalkSpeed = 0
		hum.JumpPower = 0
		hum.UseJumpPower = true
		return
	end

	-- Escondido en un escondite: quieto hasta que salgas con E
	if hiddenNow then
		hum.WalkSpeed = 0
		hum.JumpPower = 0
		hum.UseJumpPower = true
		return
	end

	-- Manchado de pintura: el servidor controla la velocidad lenta
	if hum:GetAttribute("Pintado") then
		return
	end

	-- Dardo tranquilizante: dormido unos segundos, no te podes mover
	if hum:GetAttribute("Dormido") then
		hum.WalkSpeed = 0
		hum.JumpPower = 0
		hum.UseJumpPower = true
		return
	end

	if not state.active then
		if hum.WalkSpeed ~= Config.Player.sprintSpeed then
			hum.WalkSpeed = Config.Player.sprintSpeed
		end
		return
	end

	if state.phase ~= "playing" then
		hum.WalkSpeed = 0
		hum.JumpPower = 0
		hum.UseJumpPower = true
		return
	end

	-- Noqueado (asedio y otros modos): quieto hasta volver al combate
	if state.hp and state.hp <= 0 then
		hum.WalkSpeed = 0
		hum.JumpPower = 0
		hum.UseJumpPower = true
		return
	end

	hum.JumpPower = 50
	hum.UseJumpPower = true
	if sneaking then
		hum.WalkSpeed = Config.Player.sneakSpeed
	elseif sprinting then
		-- Shift apretado: caminar despacio
		hum.WalkSpeed = Config.Player.walkSpeed
	else
		-- Por defecto el personaje corre
		hum.WalkSpeed = Config.Player.sprintSpeed
	end

	-- Apuntando se camina mas lento (estilo Counter)
	if scoped then
		hum.WalkSpeed = math.min(hum.WalkSpeed, Config.Player.walkSpeed * 0.55)
	end

	-- Agachado la camara baja un poco (estilo Counter)
	local offset = sneaking and Vector3.new(0, -1.1, 0) or Vector3.new(0, 0, 0)
	if hum.CameraOffset ~= offset then
		hum.CameraOffset = offset
	end
end

-- ===============================================================
-- Mira del rifle (clic derecho para apuntar)
-- ===============================================================
local function applyCameraMode()
	-- Estilo Counter Blox: durante la partida se juega SIEMPRE en primera
	-- persona; en el lobby y la votacion la vista queda libre.
	local round = state.active and (state.phase == "playing" or state.phase == "countdown")
	local first = scoped or round
	local mode = first and Enum.CameraMode.LockFirstPerson or Enum.CameraMode.Classic
	if player.CameraMode ~= mode then
		player.CameraMode = mode
	end
end

-- Al apuntar se oculta el arma para ver limpio por la mira
local function setWeaponHidden(hidden)
	local character = player.Character
	if not character then
		return
	end
	for _, child in ipairs(character:GetChildren()) do
		if child:IsA("Tool") then
			for _, part in ipairs(child:GetDescendants()) do
				if part:IsA("BasePart") then
					part.LocalTransparencyModifier = hidden and 1 or 0
				end
			end
		end
	end
end

-- Armas que apuntan (y que por lo tanto muestran la vista de arma).
-- La Glock-18 no tiene mira (solo los rifles apuntan): su clic derecho
-- sirve para cambiar a ráfaga de 3.
local SCOPE_WEAPONS = {
	rifle = true, pintura = true, relente = true,
	arco = true, sniper = true, lanzallamas = true, cohete = true,
	ak = true, m4 = true, mp5 = true,
}

-- Vista de arma estilo Counter: se ve en primera persona y al apuntar.
-- Con la telescopica puesta el arma se esconde (solo queda la mira).
local function refreshViewmodel()
	local round = state.active and (state.phase == "playing" or state.phase == "countdown")
	local armed = equippedId ~= nil and ViewModel.hasWeapon(equippedId)
	local show = round and armed and not hiddenNow
	ViewModel.setWeapon(equippedId)
	ViewModel.setVisible(show)
	ViewModel.setAds(scoped and equippedId ~= "sniper" and 1 or 0)
	ViewModel.setHidden(scoped and equippedId == "sniper")
	-- En primera persona el arma "de verdad" del personaje no se usa:
	-- manda la vista estilo Counter (asi no se cruza con la cara)
	setWeaponHidden(round or scoped)
end

local function scopeFov(id, level)
	local weapons = Config.Scope.weapons or {}
	if id == "sniper" then
		return (level or 1) >= 2 and (weapons.sniper2 or 7) or (weapons.sniper or 14)
	end
	return weapons[id] or Config.Scope.fov
end

-- En partida (primera persona) el mouse queda oculto y centrado
local function inRoundNow()
	return state.active and (state.phase == "playing" or state.phase == "countdown")
end

local function setScope(enabled, level)
	enabled = enabled and true or false
	local lvl = enabled and math.max(1, level or 1) or 0
	if scoped == enabled and scopeLevel == lvl then
		return
	end
	scoped = enabled
	scopeLevel = lvl

	-- Telescopica del francotirador: pantalla negra con circulo (Counter).
	-- Las demas armas apuntan con el puntito central, sin aro encima.
	local sniperScope = scoped and equippedId == "sniper"
	HUD.setScope(sniperScope, sniperScope)
	if sniperScope then
		HUD.setScopeZoom(lvl >= 2 and "10x" or "5x")
	end

	refreshViewmodel()
	UserInputService.MouseIconEnabled = not scoped and not inRoundNow()

	local hum = humanoid()
	if hum then
		hum.AutoRotate = not scoped
	end

	local camera = workspace.CurrentCamera
	if camera then
		local goal = scoped and scopeFov(equippedId, lvl) or 70
		TweenService:Create(camera, TweenInfo.new(0.18, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
			FieldOfView = goal,
		}):Play()
	end

	-- Apuntando se pasa a primera persona: la mira ya no tapa la cabeza
	UserInputService.MouseBehavior = (scoped or inRoundNow())
		and Enum.MouseBehavior.LockCenter or Enum.MouseBehavior.Default
	applyCameraMode()
	applySpeed()

	sound2D(Config.Sounds.ui, 0.25, scoped and 1.5 or 1.1)
end

-- Que herramienta tiene el jugador en la mano ahora mismo
local function refreshEquipped()
	local found = nil
	local character = player.Character
	if character then
		for _, child in ipairs(character:GetChildren()) do
			if child:IsA("Tool") and child:GetAttribute("ToolId") then
				found = child:GetAttribute("ToolId")
				break
			end
		end
	end
	equippedId = found
	if not SCOPE_WEAPONS[equippedId] then
		setScope(false)
	end
	refreshViewmodel()
end

-- ===============================================================
-- Herramientas
-- ===============================================================
local function diffFor(modeId)
	if modeId == "multi" then
		return Config.Difficulties[Config.Multiplayer.baseDifficulty]
	end
	return Config.Difficulties[modeId] or Config.Difficulties.normal
end

local function aimPoint()
	local camera = workspace.CurrentCamera
	if not camera then
		return nil
	end

	if scoped then
		-- Con la mira puesta, el objetivo es el centro de la camara
		return camera.CFrame.Position + camera.CFrame.LookVector * 260
	end

	if UserInputService.MouseEnabled then
		local mouse = player:GetMouse()
		if mouse and mouse.Hit then
			return mouse.Hit.Position
		end
	end

	return camera.CFrame.Position + camera.CFrame.LookVector * 220
end

-- Rafaga automatica estilo Counter: mantene apretado y sigue disparando
local holdingFire = false
local autoJob = nil
local startAutoFire
local lastFlameCrackle = 0

-- Menú de partida (M): cambia de modo/mapa sin esperar a morir. Mientras
-- está abierto el personaje se queda quieto y el mouse vuelve a la mano.
local function setGameMenu(open)
	open = open == true and state.active == true
	if gameMenuOpen == open then
		return
	end
	gameMenuOpen = open
	if open then
		setScope(false)
		holdingFire = false
		HUD.setGameMenuInfo(state.modeId, state.modeName, state.arenaName, state.arenaId)
		HUD.setGameMenuVisible(true)
		UserInputService.MouseIconEnabled = true
		if UserInputService.MouseBehavior ~= Enum.MouseBehavior.Default then
			UserInputService.MouseBehavior = Enum.MouseBehavior.Default
		end
	else
		HUD.setGameMenuVisible(false)
		local inRound = state.active and (state.phase == "playing" or state.phase == "countdown")
		if inRound then
			UserInputService.MouseIconEnabled = false
			UserInputService.MouseBehavior = Enum.MouseBehavior.LockCenter
		else
			UserInputService.MouseIconEnabled = true
			UserInputService.MouseBehavior = Enum.MouseBehavior.Default
		end
	end
	applySpeed()
end

local function fireTool(toolId)
	if not state.active or state.phase ~= "playing" then
		sound2D(Config.Sounds.denied, 0.5)
		return
	end

	local cooldown = cooldowns[toolId]
	if cooldown and cooldown.left > 0 then
		sound2D(Config.Sounds.denied, 0.4)
		return
	end

	remotes.ToolAction:FireServer(toolId, {
		aim = aimPoint(),
		scoped = scoped,
		sneak = sneaking,
		-- La ráfaga de la Glock viaja al servidor (3 tiros por gatillo)
		burst = (toolId == "glock") and glockBurst or nil,
	})

	local total = cooldown and cooldown.total or 1
	if cooldown then
		cooldown.left = total
	end

	-- Sonido del arma: capas de boom + chasquido + cola segun el estilo
	if Config.Grenades[toolId] then
		-- Granada: quien tira avisa con un silbido corto; la mecha corre sola
		sound2D(Config.Sounds.netSwing, 0.6, 1.35)
		ViewModel.toss()
	elseif toolId == "m4" then
		-- M4A1 con silenciador: apenas un tic seco (casi no se escucha)
		gunPlay(Config.Sounds.gunCrack, 0.14, 1.75, 0)
	elseif GUN_STYLE[toolId] then
		gunshot(GUN_STYLE[toolId])
	elseif toolId == "red" then
		sound2D(Config.Sounds.netSwing, 0.8)
	elseif toolId == "trampa" then
		sound2D(Config.Sounds.trapSet, 0.6, 0.8)
	elseif toolId == "arco" then
		sound2D(Config.Sounds.netSwing, 0.6, 1.4)
	elseif toolId == "cuchillo" then
		sound2D(Config.Sounds.netSwing, 0.55, 1.3)
	elseif toolId == "lanzallamas" then
		-- El soplete va en loop aparte; esto es un chisporroteo cada tanto
		local now = os.clock()
		if now - lastFlameCrackle > 0.32 then
			lastFlameCrackle = now
			gunPlay(Config.Sounds.flame, 0.28, 0.62, 0.3)
		end
	end

	-- Patada del arma (estilo Counter)
	local RECOIL = {
		rifle = 0.25, pintura = 0.25, relente = 0.25, sniper = 0.6,
		revolver = 0.38, cohete = 0.55, arco = 0.28, cuchillo = 0.35, lanzallamas = 0.08,
		ak = 0.44, m4 = 0.38, mp5 = 0.28, glock = 0.28, escopeta = 0.52,
	}
	local shootCfg = Config.Shoot and Config.Shoot.weapons and Config.Shoot.weapons[toolId]
	-- Con la mira puesta el arma se afirma: menos patada de vista y de
	-- camara (el AK-47 apuntado es mucho mas estable, como pidio el jefe)
	local adsSoft = (scoped and shootCfg and shootCfg.adsRecoil) or 1
	if toolId == "cuchillo" then
		-- Cuchillo mariposa: pega un zarpazo (sin fogonazo ni patada de arma)
		ViewModel.slash()
	elseif Config.Grenades[toolId] then
		-- La granada ya se tiró: sin patada de arma
	else
		ViewModel.recoil((RECOIL[toolId] or 0) * adsSoft)
		ViewModel.flash()
	end

	-- Patada de camara estilo Counter Blox: 0.9 * (1 - control) grados
	-- (mas suave que la de Counter original: sube y vuelve sola)
	local control = shootCfg and shootCfg.recoil or 72
	local kick = math.rad(0.9 * (1 - control / 100)) * adsSoft
	ViewModel.kickCamera(kick * (1 + math.random() * 0.4), kick * (math.random() * 2 - 1))

	-- El chorro de fuego no abre la cruz como un balazo
	shotBloom = math.min(20, shotBloom + (toolId == "lanzallamas" and 2 or 8))

	-- Automaticas (AK, M4, MP5): si seguis apretando, la rafaga continua
	local wcfg = Config.Weapons[toolId]
	if wcfg and wcfg.auto and holdingFire then
		startAutoFire(toolId)
	end
end

startAutoFire = function(toolId)
	if autoJob then
		return
	end
	autoJob = toolId
	task.spawn(function()
		local wcfg = Config.Weapons[toolId]
		local step = (wcfg and wcfg.cooldown or 0.12) * 1.08
		while autoJob == toolId and holdingFire and equippedId == toolId
			and state.active and state.phase == "playing" do
			task.wait(step)
			if autoJob ~= toolId or not holdingFire then
				break
			end
			fireTool(toolId)
		end
		if autoJob == toolId then
			autoJob = nil
		end
	end)
end

local hookedTools = {}

local function hookTool(tool)
	if not tool:IsA("Tool") then
		return
	end
	local toolId = tool:GetAttribute("ToolId")
	if not toolId or hookedTools[tool] then
		return
	end
	hookedTools[tool] = true

	tool.Activated:Connect(function()
		fireTool(toolId)
	end)

	tool.Destroying:Connect(function()
		hookedTools[tool] = nil
	end)
end

local function hookContainer(container)
	if not container then
		return
	end
	for _, child in ipairs(container:GetChildren()) do
		hookTool(child)
	end
	container.ChildAdded:Connect(function(child)
		hookTool(child)
		refreshEquipped()
	end)
	container.ChildRemoved:Connect(refreshEquipped)
end

player.CharacterAdded:Connect(function(character)
	task.wait(0.2)
	hookContainer(player:FindFirstChildOfClass("Backpack"))
	hookContainer(character)
	refreshEquipped()
	applySpeed()
	remotes.RequestState:FireServer()
end)

-- ===============================================================
-- Teclas
-- ===============================================================
UserInputService.InputBegan:Connect(function(input, processed)
	if processed then
		return
	end

	-- M: abre o cierra el menú de partida para cambiar modo/mapa
	if input.KeyCode == Enum.KeyCode.M then
		if state.active then
			setGameMenu(not gameMenuOpen)
		end
		return
	end
	-- Con el menú abierto no se dispara, no se apunta y no se camina
	if gameMenuOpen then
		return
	end

	if input.UserInputType == Enum.UserInputType.MouseButton1 then
		holdingFire = true
		local wcfg = equippedId and Config.Weapons[equippedId]
		if wcfg and wcfg.auto then
			startAutoFire(equippedId)
		end
		return
	end
	if input.UserInputType == Enum.UserInputType.MouseButton2 then
		-- La Glock-18 no tiene mira: su clic derecho pasa a ráfaga de 3
		-- tiros (estilo CS2) y avisa por el HUD.
		if equippedId == "glock" and state.active and state.phase == "playing" then
			glockBurst = not glockBurst
			HUD.notify(glockBurst and Config.Text.GlockBurstOn or Config.Text.GlockBurstOff,
				Color3.fromRGB(238, 196, 92), 3)
			sound2D(Config.Sounds.ui, 0.4, glockBurst and 1.5 or 1.05)
			return
		end
		-- Clic derecho: mira estilo Counter. El francotirador va ciclando
		-- la telescopica: 5x -> 10x -> sin mira.
		if SCOPE_WEAPONS[equippedId] and state.active and state.phase == "playing" then
			if equippedId == "sniper" then
				if not scoped then
					setScope(true, 1)
				elseif scopeLevel == 1 then
					setScope(true, 2)
				else
					setScope(false)
				end
			else
				setScope(not scoped, 1)
			end
		end
		return
	end
	if input.KeyCode == Enum.KeyCode.LeftShift or input.KeyCode == Enum.KeyCode.RightShift then
		-- Shift: caminar despacio (por defecto el personaje corre)
		sprinting = true
		applySpeed()
	elseif input.KeyCode == Enum.KeyCode.F then
		-- Cuchillo mariposa: F lo hace dar vueltas en la mano (estilo CS2)
		ViewModel.spin()
	elseif input.KeyCode == Enum.KeyCode.Tab then
		HUD.setScoreboardVisible(true)
	elseif input.KeyCode == Enum.KeyCode.LeftControl or input.KeyCode == Enum.KeyCode.LeftAlt
		or input.KeyCode == Enum.KeyCode.C then
		sneaking = true
		applySpeed()
	end
end)

UserInputService.InputEnded:Connect(function(input)
	if input.UserInputType == Enum.UserInputType.MouseButton1 then
		holdingFire = false
		return
	end
	if input.KeyCode == Enum.KeyCode.LeftShift or input.KeyCode == Enum.KeyCode.RightShift then
		sprinting = false
		applySpeed()
	elseif input.KeyCode == Enum.KeyCode.Tab then
		HUD.setScoreboardVisible(false)
	elseif input.KeyCode == Enum.KeyCode.LeftControl or input.KeyCode == Enum.KeyCode.LeftAlt
		or input.KeyCode == Enum.KeyCode.C then
		sneaking = false
		applySpeed()
	end
end)

-- ===============================================================
-- Punto de mira: se abre solo al correr o disparar. Quieto o caminando
-- (Shift) queda cerrado porque el tiro sale exacto, igual que en el
-- servidor.
-- ===============================================================
local function spreadErrorLocal(weaponId)
	local cfg = Config.Shoot and Config.Shoot.weapons and Config.Shoot.weapons[weaponId]
	if not cfg then
		return 0
	end
	local speed = 0
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if root then
		local v = root.AssemblyLinearVelocity
		speed = math.sqrt(v.X * v.X + v.Z * v.Z)
	end
	local walkSpeed = (Config.Player and Config.Player.walkSpeed) or 16
	local sprintSpeed = (Config.Player and Config.Player.sprintSpeed) or 24
	local moveFactor = 0
	if speed > walkSpeed + 0.75 then
		moveFactor = math.clamp((speed - walkSpeed) / math.max(1, sprintSpeed - walkSpeed), 0, 1.5)
	end
	local base = math.max(cfg.spread or 0, 0)
	local move = speed * (cfg.vel or 0) * moveFactor
	local crouchDiv = (Config.Shoot and Config.Shoot.crouchDiv) or 1.6
	if sneaking and not scoped then
		base = base / crouchDiv
		move = move / crouchDiv
	end
	local error
	if scoped then
		if cfg.adsPerfect then
			error = move
		else
			local ads = cfg.adsDiv or (Config.Shoot and Config.Shoot.adsDiv) or 0.35
			error = base * ads + move * (cfg.adsMoveDiv or (Config.Shoot and Config.Shoot.adsMoveDiv) or 0.7)
		end
	else
		error = base + move
	end
	local dead = cfg.dead or (Config.Shoot and Config.Shoot.dead) or 0
	if error < dead then
		error = 0
	end
	return error / ((Config.Shoot and Config.Shoot.div) or 6)
end

local lastCross = nil
local lastDot = nil
RunService.RenderStepped:Connect(function(dt)
	shotBloom = math.max(0, shotBloom - dt * 30)
	-- La telescopica del francotirador tapa la pantalla: ahi no va la cruz
	local sniperScope = scoped and equippedId == "sniper"
	local show = state.active and state.phase == "playing" and not hiddenNow
		and equippedId ~= nil and ViewModel.hasWeapon(equippedId)
		and not sniperScope
	if show ~= lastCross then
		lastCross = show
		HUD.setCrosshair(show, 4, 5, scoped)
	end
	if show then
		local grados = spreadErrorLocal(equippedId)
		-- Apuntando quedan las rayitas apagadas: manda el punto central
		HUD.setCrosshair(true, 3 + math.min(grados * 2.2, 12) + shotBloom * 0.35,
			4 + math.min(grados * 0.8, 4), scoped)
	end
	-- El punto central se ve SIEMPRE en partida, incluso sin armas
	local inRound = inRoundNow()
	local dotShow = inRound and not hiddenNow and not sniperScope
	if dotShow ~= lastDot then
		lastDot = dotShow
		HUD.setAimDot(dotShow)
	end

	-- Lanzallamas: mientras mantenes apretado sale el chorro de fuego
	local flaming = inRound and not hiddenNow and holdingFire and equippedId == "lanzallamas"
	setFlameSound(flaming)
	if flaming then
		local muzzlePos, look = ViewModel.getMuzzle()
		if muzzlePos and look then
			flameAt("local", muzzlePos, look)
			-- Donde pega el chorro queda fuego prendido
			flameSpotParams.FilterDescendantsInstances = player.Character and { player.Character } or {}
			local hit = workspace:Raycast(muzzlePos, look * 17, flameSpotParams)
			if hit then
				fireSpotAt("impact:local", hit.Position, hit.Normal)
			end
		end
	end

	-- En partida el mouse queda oculto y centrado: nada de manito sobre el punto.
	-- Con el menú de partida abierto vuelve a la mano para poder elegir.
	if gameMenuOpen then
		if not UserInputService.MouseIconEnabled then
			UserInputService.MouseIconEnabled = true
		end
		if UserInputService.MouseBehavior ~= Enum.MouseBehavior.Default then
			UserInputService.MouseBehavior = Enum.MouseBehavior.Default
		end
	elseif inRound then
		if UserInputService.MouseIconEnabled then
			UserInputService.MouseIconEnabled = false
		end
		if not scoped and UserInputService.MouseBehavior ~= Enum.MouseBehavior.LockCenter then
			UserInputService.MouseBehavior = Enum.MouseBehavior.LockCenter
		end
	elseif not scoped then
		if not UserInputService.MouseIconEnabled then
			UserInputService.MouseIconEnabled = true
		end
		if UserInputService.MouseBehavior ~= Enum.MouseBehavior.Default then
			UserInputService.MouseBehavior = Enum.MouseBehavior.Default
		end
	end
end)

-- ===============================================================
-- Avisos del servidor
-- ===============================================================
remotes.SessionUpdate.OnClientEvent:Connect(function(newState)
	local wasActive = state.active
	local previousPhase = state.phase

	if not newState or not newState.active then
		state = { active = false, phase = "none", diff = nil }
		hiddenNow = false
		sprinting = false
		sneaking = false
		gameMenuOpen = false
		switchPending = false
		HUD.setGameMenuVisible(false)
		setScope(false)
		refreshViewmodel()
		HUD.hideResult()
		HUD.hideVote()
		HUD.setTeams(nil, nil, nil, nil)
		HUD.setMenuVisible(true)
		HUD.setMenuStatus("")
		HUD.fade(false, 0.5)
		applySpeed()
		return
	end

	state.active = true
	state.phase = newState.phase
	state.modeId = newState.modeId
	state.modeName = newState.modeName
	state.arenaName = newState.arenaName
	state.arenaId = newState.arenaId
	state.diff = diffFor(newState.modeId)
	state.hidden = newState.hidden == true
	state.hideSpot = newState.hideSpot
	state.hp = newState.hp
	if newState.vote then
		HUD.showVote(newState.vote)
	else
		HUD.hideVote()
	end
	applyCameraMode()
	if state.hidden ~= hiddenNow then
		hiddenNow = state.hidden
		if hiddenNow then
			setScope(false)
			sound2D(Config.Sounds.rustle, 0.5)
		else
			sound2D(Config.Sounds.ui, 0.35)
		end
		applyCameraMode()
		applySpeed()
	end
	refreshViewmodel()

	HUD.setMenuVisible(false)
	HUD.setMenuStatus("")

	if not wasActive or previousPhase ~= newState.phase then
		if newState.phase == "vote" then
			HUD.hideResult()
			HUD.fade(false, 0.4)
		elseif newState.phase == "countdown" then
			HUD.hideResult()
			HUD.fade(true, 0.25)
			task.delay(0.6, function()
				if state.phase == "countdown" or state.phase == "playing" then
					HUD.fade(false, 0.6)
				end
			end)
		elseif newState.phase == "playing" then
			HUD.hideResult()
			HUD.fade(false, 0.5)
		end
	end

	if state.diff then
		-- Algunos modos (Colosal) no tienen red ni rifle tranquilizante
		local redTotal = (state.diff.red and state.diff.red.cooldown) or 1
		local rifleTotal = (state.diff.rifle and state.diff.rifle.cooldown) or 1
		HUD.setToolTotals({
			red = redTotal,
			rifle = rifleTotal,
			rastreador = Config.Tracker.cooldown,
			trampa = Config.Trampa.cooldown,
			pintura = Config.PaintRifle.cooldown,
			relente = Config.Relente.cooldown,
		})
		cooldowns.red.total = redTotal
		cooldowns.rifle.total = rifleTotal
		cooldowns.rastreador.total = Config.Tracker.cooldown
		cooldowns.trampa.total = Config.Trampa.cooldown
		cooldowns.pintura.total = Config.PaintRifle.cooldown
		cooldowns.relente.total = Config.Relente.cooldown
	end

	HUD.updateState(newState)

	-- Asedio: marcador de equipos arriba (equipo propio, ronda y puntos)
	if newState.isAsedio and newState.teamScore then
		HUD.setTeams(newState.team, newState.teamScore, newState.round, newState.roundsToWin)
	else
		HUD.setTeams(nil, nil, nil, nil)
	end

	applySpeed()
end)

remotes.SessionEnd.OnClientEvent:Connect(function(result)
	HUD.showResult(result, Config.Round.EndScreen)
	sound2D(result.won and Config.Sounds.win or Config.Sounds.lose, 0.9)
	task.delay(1.5, function()
		HUD.fade(true, 1)
	end)
end)

remotes.Notify.OnClientEvent:Connect(function(text, colorTable, duration)
	HUD.notify(text, Util.colorFromTable(colorTable), duration)
end)

remotes.TrackerPing.OnClientEvent:Connect(function(data)
	HUD.setTracker(data)
	sound2D(Config.Sounds.ui, 0.5, 1.4)
end)

-- Ceguera de pintura: manchones que tapan toda la pantalla (golpe en la
-- cabeza con el rifle de pintura). Se arma 100% por codigo y se desvanece.
local paintBlindGui
local function paintBlind(duration, color)
	local plrGui = player:FindFirstChildOfClass("PlayerGui") or player:WaitForChild("PlayerGui")
	if not paintBlindGui or not paintBlindGui.Parent then
		paintBlindGui = Instance.new("ScreenGui")
		paintBlindGui.Name = "KiwiPinturaCeguera"
		paintBlindGui.IgnoreGuiInset = true
		paintBlindGui.DisplayOrder = 60
		paintBlindGui.ResetOnSpawn = false
		paintBlindGui.Parent = plrGui
	end
	for _, child in ipairs(paintBlindGui:GetChildren()) do
		child:Destroy()
	end
	duration = math.max(duration or 4, 0.5)
	local base = color or Color3.fromRGB(230, 120, 190)
	local blobs = {}

	-- Fondo oscuro + dos manchones enormes al centro (no se ve la mira)
	local fondo = Instance.new("Frame")
	fondo.Size = UDim2.fromScale(1, 1)
	fondo.BackgroundColor3 = Color3.fromRGB(20, 10, 24)
	fondo.BackgroundTransparency = 0.3
	fondo.BorderSizePixel = 0
	fondo.ZIndex = 1
	fondo.Parent = paintBlindGui
	table.insert(blobs, fondo)

	for i = 1, 30 do
		local blob = Instance.new("Frame")
		blob.AnchorPoint = Vector2.new(0.5, 0.5)
		blob.Position = UDim2.fromScale(math.random(-8, 88) / 100, math.random(-8, 88) / 100)
		local size = math.random(170, 520)
		if i <= 2 then
			size = math.random(620, 900)
			blob.Position = UDim2.fromScale(0.5, 0.5)
		end
		blob.Size = UDim2.fromOffset(size, size * (0.72 + math.random() * 0.6))
		blob.Rotation = math.random(0, 359)
		blob.BackgroundColor3 = base:Lerp(
			math.random() < 0.5 and Color3.fromRGB(18, 8, 20) or Color3.fromRGB(255, 250, 255),
			math.random() * 0.45)
		blob.BackgroundTransparency = 0.05 + math.random() * 0.2
		blob.BorderSizePixel = 0
		blob.ZIndex = 2 + i
		local corner = Instance.new("UICorner")
		corner.CornerRadius = UDim.new(0.5, 0)
		corner.Parent = blob
		blob.Parent = paintBlindGui
		table.insert(blobs, blob)
	end

	-- Al final se escurre: se desvanece y se limpia
	task.delay(math.max(duration - 1.4, 0.1), function()
		for _, b in ipairs(blobs) do
			if b.Parent then
				TweenService:Create(b, TweenInfo.new(1.4, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
					{ BackgroundTransparency = 1 }):Play()
			end
		end
	end)
	task.delay(duration + 0.4, function()
		for _, b in ipairs(blobs) do
			if b.Parent then
				b:Destroy()
			end
		end
	end)
end

-- Flashbang: pantallazo blanco que se apaga solo (con el zumbido del ring)
local flashGui
local function flashBlind(duration)
	local plrGui = player:FindFirstChildOfClass("PlayerGui") or player:WaitForChild("PlayerGui")
	if not flashGui or not flashGui.Parent then
		flashGui = Instance.new("ScreenGui")
		flashGui.Name = "KiwiFlash"
		flashGui.IgnoreGuiInset = true
		flashGui.DisplayOrder = 70
		flashGui.ResetOnSpawn = false
		flashGui.Parent = plrGui
	end
	for _, child in ipairs(flashGui:GetChildren()) do
		child:Destroy()
	end
	duration = math.max(duration or 2, 0.4)
	local frame = Instance.new("Frame")
	frame.Size = UDim2.fromScale(1, 1)
	frame.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
	frame.BackgroundTransparency = 0
	frame.BorderSizePixel = 0
	frame.ZIndex = 1
	frame.Parent = flashGui
	-- Primero baja apenas (el flash de verdad), despues se aclara la vista
	TweenService:Create(frame, TweenInfo.new(duration * 0.32, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
		BackgroundTransparency = 0.32,
	}):Play()
	task.delay(duration * 0.3, function()
		if frame.Parent then
			TweenService:Create(frame, TweenInfo.new(duration * 0.7, Enum.EasingStyle.Quad, Enum.EasingDirection.InOut), {
				BackgroundTransparency = 1,
			}):Play()
		end
	end)
	task.delay(duration + 0.3, function()
		if frame.Parent then
			frame:Destroy()
		end
	end)
end

remotes.WorldEvent.OnClientEvent:Connect(function(kind, data)
	data = data or {}
	local position = data.pos

	if kind == "countdown" then
		sound2D(Config.Sounds.countdown, 0.7)
	elseif kind == "start" then
		sound2D(Config.Sounds.start, 0.9)
		HUD.notify("A cazar al kiwi!", Color3.fromRGB(102, 209, 130), 3)
	elseif kind == "netswing" then
		if position and distanceToLocal(position) < 90 then
			soundAt(Config.Sounds.netSwing, position, 0.7)
		end
	elseif kind == "nadethrow" then
		-- Alguien tiró una granada: silbido corto si estas cerca
		if position and distanceToLocal(position) < 80 then
			soundAt(Config.Sounds.netSwing, position, 0.7, 1.45)
		end
	elseif kind == "nade" then
		-- Detonación de una granada del pack: cada tipo suena distinto
		local tipo = data.tipo
		if position then
			if tipo == "frag" then
				soundAt(Config.Sounds.gunBoom, position, 1, 0.55)
				burst(position, Color3.fromRGB(255, 180, 90), 46)
				lightFlash(position, Color3.fromRGB(255, 188, 120), 7, 34)
			elseif tipo == "humo" then
				soundAt(Config.Sounds.dartHit, position, 0.7, 0.6)
				burst(position, Color3.fromRGB(210, 214, 220), 44)
			elseif tipo == "molotov" then
				soundAt(Config.Sounds.gunBoom, position, 0.8, 0.9)
				soundAt(Config.Sounds.flame, position, 0.8, 0.75)
				burst(position, Color3.fromRGB(255, 140, 60), 34)
				lightFlash(position, Color3.fromRGB(255, 150, 60), 6, 28)
			elseif tipo == "flash" then
				soundAt(Config.Sounds.gunBoom, position, 0.9, 1.35)
				soundAt(Config.Sounds.flush, position, 0.7, 1.5)
				burst(position, Color3.fromRGB(255, 255, 240), 40)
			end
		end
	elseif kind == "flash" then
		-- Flashbang: te cegó (pantalla blanca + zumbido que se van solos)
		local dur = data.dur or 2
		flashBlind(dur)
		sound2D(Config.Sounds.flush, 0.5, 0.6)
		HUD.notify(string.format(Config.Text.FlashHit, math.max(1, math.floor(dur + 0.5))),
			Color3.fromRGB(245, 245, 245), math.max(1, dur))
	elseif kind == "dartshot" then
		if position then
			-- Sonido segun el arma: rifles graves, pistolas secas, dardos suaves
			local style = GUN_STYLE[data.weapon] or "rifle"
			if data.weapon == "m4" then
				-- M4A1 con silenciador: apenas se escucha (tic seco y corto)
				soundAt(Config.Sounds.gunCrack, position, 0.14, 1.75)
			elseif style == "dart" then
				soundAt(Config.Sounds.dartShot, position, 0.8, 1.15)
			elseif style == "shotgun" or style == "sniper" or style == "rocket" then
				soundAt(Config.Sounds.gunBoom, position, 0.9,
					style == "shotgun" and 0.78 or (style == "sniper" and 0.95 or 0.6))
			else
				soundAt(Config.Sounds.gunCrack, position, 0.8,
					style == "pistol" and 1.45 or (style == "smg" and 1.6 or 1.15))
			end
		end
		if position and data.tracer and data.dir then
			-- Estilo Counter: bala instantanea = trazadora, no proyectil
			tracer(position, data.dir, 240, Color3.fromRGB(255, 240, 190), 0.1)
		end
	elseif kind == "headshot" then
		if position then
			soundAt(Config.Sounds.dartHit, position, 1, 1.35)
			burst(position, Color3.fromRGB(255, 210, 90), 30)
		end
	elseif kind == "darthit" then
		if position then
			soundAt(Config.Sounds.dartHit, position, 1)
			burst(position, Color3.fromRGB(160, 240, 190), 26)
		end
	elseif kind == "dartmiss" then
		if position and distanceToLocal(position) < 60 then
			soundAt("rbxasset://sounds/impact_water.mp3", position, 0.5, 1.6)
			burst(position, Color3.fromRGB(200, 200, 200), 8)
		end
	elseif kind == "flush" then
		if position then
			if distanceToLocal(position) < 120 then
				soundAt(Config.Sounds.flush, position, 0.9)
			end
			burst(position, Color3.fromRGB(140, 180, 110), 18)
		end
		HUD.notify(Config.Text.KiwiRunning, Color3.fromRGB(238, 196, 92), 3)
	elseif kind == "rustle" then
		if position and distanceToLocal(position) < 45 then
			soundAt(Config.Sounds.rustle, position, 0.6)
			burst(position, Color3.fromRGB(120, 160, 90), 10)
		end
	elseif kind == "sedate" then
		if position then
			soundAt(Config.Sounds.dartHit, position, 0.6, 1.2)
			burst(position, Color3.fromRGB(180, 220, 255), 16)
		end
	elseif kind == "wake" then
		if position then
			soundAt(Config.Sounds.flush, position, 0.6, 1.2)
		end
	elseif kind == "captured" then
		if position then
			soundAt(Config.Sounds.netHit, position, 1)
			burst(position, Color3.fromRGB(255, 235, 160), 40)
		end
	elseif kind == "trap" then
		if position then
			soundAt(Config.Sounds.trapSet, position, 0.6, 0.8)
			burst(position, Color3.fromRGB(238, 170, 120), 12)
		end
	elseif kind == "trapcatch" then
		if position then
			soundAt(Config.Sounds.trapCatch, position, 1)
			burst(position, Color3.fromRGB(255, 120, 140), 34)
		end
	elseif kind == "trapescape" then
		if position then
			soundAt(Config.Sounds.trapCatch, position, 0.9, 0.7)
			burst(position, Color3.fromRGB(238, 170, 120), 18)
		end
	elseif kind == "paintshot" then
		soundAt(Config.Sounds.paintShot, position or Vector3.new(), 0.8)
	elseif kind == "painthit" then
		if position then
			soundAt(Config.Sounds.paintHit, position, 0.8)
			burst(position, Util.colorFromTable(data.color) or Color3.fromRGB(230, 120, 190), 26)
		end
	elseif kind == "paintblind" then
		-- Manchazo en la cara: no se ve nada unos segundos
		paintBlind(data.dur or 4, Util.colorFromTable(data.color))
	elseif kind == "slowhit" then
		if position then
			soundAt(Config.Sounds.dartHit, position, 0.9, 1.15)
			burst(position, Config.Tools.relente.color, 30)
		end
	elseif kind == "chomp" then
		if position then
			soundAt(Config.Sounds.dartHit, position, 1, 0.6)
			burst(position, Color3.fromRGB(232, 108, 100), 14)
		end
		if eatCam then
			eatCam.shakeUntil = os.clock() + 0.35
		end
	elseif kind == "hidestart" then
		if position and distanceToLocal(position) < 40 then
			soundAt(Config.Sounds.rustle, position, 0.7)
		end
	elseif kind == "hidestop" then
		if position and distanceToLocal(position) < 40 then
			soundAt(Config.Sounds.rustle, position, 0.5, 0.9)
		end
	elseif kind == "sniffstart" then
		if position and distanceToLocal(position) < 60 then
			soundAt(Config.Sounds.rustle, position, 0.8, 0.7)
		end
		if state.hidden and data.index == state.hideSpot then
			HUD.notify("¡El kiwi te está husmeando! Sal con E y corre", Color3.fromRGB(238, 150, 100), 4)
			sound2D(Config.Sounds.denied, 0.7)
		end
	elseif kind == "sniff" then
		if position and distanceToLocal(position) < 48 then
			soundAt(Config.Sounds.rustle, position, 0.5, 1.1)
			burst(position, Color3.fromRGB(198, 170, 86), 6)
		end
	elseif kind == "sniffmiss" then
		if position and distanceToLocal(position) < 60 then
			soundAt(Config.Sounds.rustle, position, 0.4, 0.8)
		end
	elseif kind == "sniffcatch" then
		if position then
			soundAt(Config.Sounds.roar, position, 1, 0.5)
			burst(position, Color3.fromRGB(232, 108, 100), 30)
		end
	elseif kind == "boom" then
		if position then
			local cfg = data.weapon and Config.Weapons[data.weapon]
			-- El tanque de combustible hace una explosion mas grande
			local tank = data.tank == true
			soundAt(Config.Sounds.gunBoom, position, tank and 1.2 or 1, 0.5)
			soundAt(Config.Sounds.dartHit, position, 0.85, 0.75)
			burst(position, (cfg and cfg.color) or Color3.fromRGB(255, 186, 120), tank and 90 or 46)
			if distanceToLocal(position) < (tank and 110 or 70) then
				sound2D(Config.Sounds.roar, tank and 0.75 or 0.5, 0.7)
			end
		end
	elseif kind == "weaponfx" then
		-- Animacion distinta para cada arma de baul
		local weapon = data.weapon
		local dir = data.dir or Vector3.new(0, 0, -1)
		if position and weapon == "sniper" then
			tracer(position, dir, 340, Color3.fromRGB(255, 246, 205), 0.13)
			burst(position + dir * 1.4, Color3.fromRGB(255, 232, 170), 8)
		elseif position and weapon == "revolver" then
			tracer(position, dir, 150, Color3.fromRGB(255, 224, 160), 0.09)
			burst(position + dir * 0.9, Color3.fromRGB(255, 208, 140), 6)
		elseif position and weapon == "cuchillo" then
			burst(position + dir * 3.2, Color3.fromRGB(230, 240, 250), data.hit and 16 or 7)
		elseif position and weapon == "lanzallamas" then
			-- Chorro continuo: cada aviso del servidor refresca el rig
			if data.user ~= player.UserId then
				local key = "r" .. tostring(data.user or 0)
				flameAt(key, position, dir)
				-- Y el fuego prendido donde pega su chorro
				local shooter = data.user and Players:GetPlayerByUserId(data.user)
				local rp = RaycastParams.new()
				rp.FilterType = Enum.RaycastFilterType.Exclude
				rp.FilterDescendantsInstances = shooter and shooter.Character and { shooter.Character } or {}
				rp.IgnoreWater = true
				local hit = workspace:Raycast(position, dir * 17, rp)
				if hit then
					fireSpotAt("impact:" .. key, hit.Position, hit.Normal)
				end
			end
		elseif position and weapon == "arco" then
			burst(position + dir * 1.2, Color3.fromRGB(180, 225, 150), 5)
		elseif position and weapon == "cohete" then
			burst(position + dir * 1.6, Color3.fromRGB(210, 205, 200), 10)
		end
	elseif kind == "arrowpick" then
		if position then
			burst(position, Color3.fromRGB(180, 230, 150), 12)
			if distanceToLocal(position) < 90 then
				soundAt(Config.Sounds.ui, position, 0.6, 1.4)
			end
		end
	elseif kind == "peck" then
		if position then
			if distanceToLocal(position) < 90 then
				soundAt(Config.Sounds.roar, position, 0.75, 1.7)
			end
			burst(position, Color3.fromRGB(240, 100, 90), 14)
		end
	elseif kind == "chestopen" then
		if position then
			soundAt(Config.Sounds.win, position, 0.7)
			burst(position, Color3.fromRGB(255, 214, 120), 40)
		end
	elseif kind == "safeactive" then
		sound2D(Config.Sounds.win, 0.8)
		if position then
			soundAt(Config.Sounds.countdown, position, 1)
			burst(position, Color3.fromRGB(140, 255, 200), 60)
		end
	elseif kind == "paintmiss" then
		if position and distanceToLocal(position) < 70 then
			soundAt(Config.Sounds.paintHit, position, 0.35, 1.5)
			burst(position, Util.colorFromTable(data.color) or Color3.fromRGB(230, 120, 190), 8)
		end
	elseif kind == "hunt" then
		if position and distanceToLocal(position) < 150 then
			soundAt(Config.Sounds.roar, position, 0.9, 0.55)
		end
	elseif kind == "roar" then
		if position then
			local distance = distanceToLocal(position)
			if distance < 200 then
				soundAt(Config.Sounds.roar, position, math.clamp(1.1 - distance / 260, 0.2, 1), 0.45)
				HUD.notify("¡El kiwi gigante ruge cerca!", Color3.fromRGB(232, 108, 100), 2)
			end
		end
	elseif kind == "giantcatch" then
		if position then
			soundAt(Config.Sounds.roar, position, 1, 0.4)
			burst(position, Color3.fromRGB(232, 108, 100), 44)
		end
		if data.userId == player.UserId then
			sound2D(Config.Sounds.lose, 0.8)
			-- Camara en tercera persona para ver como te come
			setScope(false)
			local now = os.clock()
			eatCam = {
				start = now,
				until_ = now + (Config.Round.EatHold or 2.6) + 0.15,
				kiwiPos = position,
				shakeUntil = 0,
			}
			-- El cartel de muerte entra un poco despues, para no tapar la escena
			task.delay(1.05, function()
				if eatCam then
					HUD.death(Config.Text.DeathTitle, Config.Text.DeathSubtitle)
				end
			end)
		end
	elseif kind == "hurt" then
		if data.userId == player.UserId then
			HUD.hurt(data.amount)
			sound2D(Config.Sounds.paintHit, 0.5, 0.8)
		elseif position and distanceToLocal(position) < 60 then
			soundAt(Config.Sounds.dartHit, position, 0.35, 1.4)
		end
	elseif kind == "ko" then
		if position then
			burst(position, Color3.fromRGB(232, 108, 100), 30)
		end
		if data.userId == player.UserId then
			setScope(false)
			sound2D(Config.Sounds.lose, 0.8)
			if state.modeId == "asedio" then
				HUD.death("¡TE NOQUEARON!", "Volvés al combate en unos segundos...")
			else
				HUD.death("¡TE NOQUEARON!", "Vuelves al lobby...")
			end
		end
	end
end)

-- ===============================================================
-- Botones del menu
-- ===============================================================
-- Cambia de partida desde el menú de juego (modo y/o mapa) sin esperar
-- a morir. El servidor saca al jugador de la sesión actual y lo mete en
-- una nueva; si se eligió mapa, arranca directo en ese mapa.
local function requestSwitch(modeId, mapId)
	if switchPending then
		return
	end
	switchPending = true
	setGameMenu(false)
	HUD.notify("Cambiando de partida...", Color3.fromRGB(238, 196, 92), 2)
	remotes.RequestSwitch:FireServer(modeId, mapId)
	task.delay(1.6, function()
		switchPending = false
	end)
end

HUD.init(player:WaitForChild("PlayerGui"), {
	onJoin = function(modeId)
		sound2D(Config.Sounds.ui, 0.6)
		HUD.setMenuStatus("Entrando a la partida...", Color3.fromRGB(238, 196, 92))
		if state.active then
			requestSwitch(modeId, nil)
		else
			remotes.RequestJoin:FireServer(modeId)
		end
	end,
	onVote = function(mapId)
		sound2D(Config.Sounds.ui, 0.5)
		remotes.VoteMap:FireServer(mapId)
	end,
	onLeave = function()
		sound2D(Config.Sounds.ui, 0.5)
		setGameMenu(false)
		remotes.RequestLeave:FireServer()
	end,
	onMenu = function()
		sound2D(Config.Sounds.ui, 0.4)
		setGameMenu(not gameMenuOpen)
	end,
	onCloseGameMenu = function()
		sound2D(Config.Sounds.ui, 0.4, 1.2)
		setGameMenu(false)
	end,
	onSwitchMode = function(modeId)
		if not state.active or not modeId then
			return
		end
		if modeId == state.modeId then
			setGameMenu(false)
			return
		end
		sound2D(Config.Sounds.ui, 0.6)
		requestSwitch(modeId, nil)
	end,
	onSwitchMap = function(mapId)
		if not state.active or not mapId or not state.modeId then
			return
		end
		if mapId == state.arenaId then
			setGameMenu(false)
			return
		end
		sound2D(Config.Sounds.ui, 0.6)
		requestSwitch(state.modeId, mapId)
	end,
})

-- ===============================================================
-- Bucle del cliente
-- ===============================================================
-- Tabla reutilizada: no crear basura nueva cada frame
local remainingCooldowns = {}
RunService.Heartbeat:Connect(function(dt)
	-- Si te esta comiendo el kiwi: camara de cine en tercera persona
	if eatCam then
		local camera = workspace.CurrentCamera
		local character = player.Character
		local root = character and character:FindFirstChild("HumanoidRootPart")
		local now = os.clock()
		if camera and root and now < eatCam.until_ then
			camera.CameraType = Enum.CameraType.Scriptable
			-- La camara se acerca de golpe: primer plano del kiwi comiendote
			local p = math.clamp((now - (eatCam.start or now)) / 0.55, 0, 1)
			local target = root.Position + Vector3.new(0, 1.5, 0)
			local away = target - (eatCam.kiwiPos or target)
			away = Vector3.new(away.X, 0, away.Z)
			if away.Magnitude < 0.1 then
				away = Vector3.new(0, 0, 1)
			end
			local flatAway = away.Unit
			local cf = CFrame.lookAt(
				target + flatAway * (15 - 6.5 * p) + Vector3.new(0, 5.6 - 2.6 * p, 0),
				target + flatAway * 1.6 + Vector3.new(0, 0.4, 0))
			if now < (eatCam.shakeUntil or 0) then
				cf = cf * CFrame.new((math.random() - 0.5) * 0.55, (math.random() - 0.5) * 0.45, 0)
			end
			camera.CFrame = cf
		else
			if camera then
				camera.CameraType = Enum.CameraType.Custom
			end
			eatCam = nil
			applyCameraMode()
		end
	end

	-- Con la mira puesta, el personaje gira junto con la camara
	if scoped and state.active and state.phase == "playing" then
		local camera = workspace.CurrentCamera
		local character = player.Character
		local root = character and character:FindFirstChild("HumanoidRootPart")
		if camera and root then
			local look = camera.CFrame.LookVector
			local flatLook = Vector3.new(look.X, 0, look.Z)
			if flatLook.Magnitude > 0.01 then
				root.CFrame = CFrame.lookAt(root.Position, root.Position + flatLook.Unit)
			end
		end
	end

	-- Efecto de velocidad: corriendo la camara abre un poco el FOV (se siente mas rapido)
	if state.active and state.phase == "playing" and not scoped then
		local character = player.Character
		local camera = workspace.CurrentCamera
		local root = character and character:FindFirstChild("HumanoidRootPart")
		if root and camera then
			local v = root.AssemblyLinearVelocity
			local flatSpeed = math.sqrt(v.X * v.X + v.Z * v.Z)
			local goal = 70 + math.clamp((flatSpeed - Config.Player.walkSpeed) * 0.5, 0, 7)
			speedFov = speedFov or camera.FieldOfView
			speedFov = speedFov + (goal - speedFov) * math.min(1, dt * 6)
			camera.FieldOfView = speedFov
		end
	else
		speedFov = nil
	end

	-- Chorros de llama y fuegos que quedaron viejos
	flameCleanup()

	-- Pasos: correr suena; caminar con Shift o agachado, no
	updatePasos(dt)

	local remaining = remainingCooldowns
	for toolId, data in pairs(cooldowns) do
		data.left = math.max(0, data.left - dt)
		remaining[toolId] = data.left
	end
	HUD.setCooldowns(remaining)
	HUD.updateTracker()
end)

hookContainer(player:WaitForChild("Backpack"))
if player.Character then
	hookContainer(player.Character)
end
remotes.RequestState:FireServer()
