--[[
	WeatherFX.lua  (cliente)
	Dibuja el clima del lado del jugador:

		- lluvia: rayas finas que caen alrededor de la camara
		  (parts locales: no viajan al servidor)
		- nieve: copos con particulas (textura de estrella)

	Lee los atributos que publica el servidor en el workspace:
		"Clima" (sol | lluvia | nieve) y "ClimaFuerza" (0 a 1).

	La luz, la niebla y la nieve acumulada del piso las maneja el
	servidor en Lighting; aca solo se ven los copos y las gotas.
--]]

local RunService = game:GetService("RunService")

local WeatherFX = {}

local RAIN_MAX = 90
local RAIN_RADIUS = 27    -- radio alrededor de la camara donde cae la lluvia
local RAIN_TOP = 22       -- altura sobre la camara donde nace la gota
local RAIN_BOTTOM = -9    -- a esta altura bajo la camara, la gota se recicla

local RAIN_COLOR = Color3.fromRGB(168, 190, 216)
local RAIN_TRANSPARENCY = 0.35

local started = false
local gotas = {}
local nube
local copos
local fuerza = 0

-- ===============================================================
-- Lluvia (rayas)
-- ===============================================================
local function nacimientoGota(g)
	local camera = workspace.CurrentCamera
	if not camera then
		return
	end
	local base = camera.CFrame.Position
	local angulo = math.random() * math.pi * 2
	local radio = math.sqrt(math.random()) * RAIN_RADIUS
	g.parte.Position = Vector3.new(
		base.X + math.cos(angulo) * radio,
		base.Y + RAIN_TOP + math.random() * 10,
		base.Z + math.sin(angulo) * radio
	)
end

local function nuevaGota()
	local parte = Instance.new("Part")
	parte.Name = "GotaLluvia"
	parte.Size = Vector3.new(0.07, 0.8 + math.random() * 0.7, 0.07)
	parte.Color = RAIN_COLOR
	parte.Material = Enum.Material.SmoothPlastic
	parte.Transparency = 1
	parte.Anchored = true
	parte.CanCollide = false
	parte.CanQuery = false
	parte.CanTouch = false
	parte.CastShadow = false
	parte.Position = Vector3.new(0, -600, 0)
	parte.Parent = workspace
	local g = { parte = parte, vy = 80 + math.random() * 30 }
	nacimientoGota(g)
	return g
end

-- ===============================================================
-- Nieve (copos de particulas)
-- ===============================================================
local function armarNube()
	if nube and nube.Parent then
		return
	end
	nube = Instance.new("Part")
	nube.Name = "ClimaNube"
	nube.Size = Vector3.new(64, 2, 64) -- el "techo" del que caen los copos
	nube.Transparency = 1
	nube.Anchored = true
	nube.CanCollide = false
	nube.CanQuery = false
	nube.CanTouch = false
	nube.CastShadow = false
	nube.Parent = workspace

	copos = Instance.new("ParticleEmitter")
	copos.Name = "Copos"
	copos.Texture = "rbxasset://textures/particles/sparkles_main.dds"
	copos.LightEmission = 0.35
	copos.LightInfluence = 0.45
	copos.Color = ColorSequence.new(Color3.fromRGB(255, 255, 255))
	copos.Size = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.42),
		NumberSequenceKeypoint.new(1, 0.6),
	})
	copos.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.12),
		NumberSequenceKeypoint.new(0.85, 0.4),
		NumberSequenceKeypoint.new(1, 0.85),
	})
	copos.Lifetime = NumberRange.new(7, 12)
	copos.Rate = 0
	copos.Speed = NumberRange.new(2.5, 5)
	copos.SpreadAngle = Vector2.new(14, 14)
	copos.Acceleration = Vector3.new(2.4, -2.2, 1.6)
	copos.Drag = 0.35
	copos.Rotation = NumberRange.new(0, 360)
	copos.RotSpeed = NumberRange.new(-42, 42)
	copos.VelocityInheritance = 0.05
	copos.EmissionDirection = Enum.NormalId.Bottom
	copos.Shape = Enum.ParticleEmitterShape.Box
	copos.Enabled = false
	copos.Parent = nube
end

-- ===============================================================
-- Cuadro a cuadro
-- ===============================================================
local function paso(dt)
	local camera = workspace.CurrentCamera
	if not camera then
		return
	end

	local kind = workspace:GetAttribute("Clima") or "sol"
	local objetivo = workspace:GetAttribute("ClimaFuerza") or 0
	if kind == "sol" then
		objetivo = 0
	end
	fuerza = fuerza + (objetivo - fuerza) * math.min(1, dt * 4)

	-- Lluvia
	local activas = 0
	if kind == "lluvia" then
		activas = math.floor(RAIN_MAX * math.clamp(fuerza, 0, 1) + 0.5)
	end
	for i = 1, RAIN_MAX do
		local g = gotas[i]
		if not g then
			g = nuevaGota()
			gotas[i] = g
		end
		local parte = g.parte
		if i <= activas then
			if parte.Transparency ~= RAIN_TRANSPARENCY then
				parte.Transparency = RAIN_TRANSPARENCY
			end
			parte.Position = parte.Position + Vector3.new(2.2 * dt, -g.vy * dt, 1.2 * dt)
			if parte.Position.Y < camera.CFrame.Position.Y + RAIN_BOTTOM then
				nacimientoGota(g)
			end
		elseif parte.Transparency ~= 1 then
			parte.Transparency = 1
		end
	end

	-- Nieve
	if kind == "nieve" and fuerza > 0.02 then
		armarNube()
		if nube and copos then
			nube.CFrame = CFrame.new(camera.CFrame.Position + Vector3.new(0, 26, 0))
			copos.Enabled = true
			copos.Rate = 160 * math.clamp(fuerza, 0, 1)
		end
	elseif copos and copos.Enabled then
		copos.Enabled = false
		copos.Rate = 0
	end
end

function WeatherFX.start()
	if started then
		return
	end
	started = true
	RunService.RenderStepped:Connect(paso)
end

return WeatherFX
