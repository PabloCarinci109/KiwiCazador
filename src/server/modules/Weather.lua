--[[
	Weather.lua  (servidor)
	Clima y paso del tiempo.

	- El reloj del mundo avanza solo: amanece, atardece y se hace de
	  noche (la luz del mapa se va apagando con el correr de la
	  partida).
	- Cada tanto el clima cambia al azar: sol, lluvia o nieve.
	- Cuando nieva, el mapa se va tapando de blanco (la nieve se
	  acumula en el piso) y cuando para, se derrite de a poco.
	- El estado viaja al cliente por atributos del workspace
	  ("Clima", "ClimaFuerza", "Nieve"): el cliente dibuja la lluvia
	  y los copos, y aca se compone la luz y la niebla.

	GameManager llama a Weather.setBase(preset) cada vez que cambia
	de arena/modo; de ahi en mas la luz final la compone este modulo
	(preset + hora + clima + nieve acumulada).
--]]

local Lighting = game:GetService("Lighting")
local Players = game:GetService("Players")

local Shared = require(script.Parent.Shared)
local Config = require(Shared.Config)
local Net = require(Shared.Net)
local Util = require(Shared.Util)

local Weather = {}

local SNOW = Config.Weather.snowColor

-- Luau no permite multiplicar Color3 por un numero: se escala a mano.
local function escala(color, k)
	return Color3.new(color.R * k, color.G * k, color.B * k)
end

local state = {
	clock = 14,      -- hora del mundo (0 a 24)
	kind = "sol",    -- sol | lluvia | nieve
	force = 0,       -- 0 a 1: que tan metido esta el clima
	accum = 0,       -- 0 a 1: nieve acumulada en el piso
	painted = 0,     -- ultimo accum que se pinto en el mapa
	nextAt = 0,      -- cuando vuelve a sortear el clima
	base = nil,      -- preset de luz de la arena (sin clima)
}

local world
local painting = false
local snapshot = setmetatable({}, { __mode = "k" }) -- parte -> color original

local CLIMA_COLOR = {
	sol = Color3.fromRGB(252, 220, 128),
	lluvia = Color3.fromRGB(128, 168, 220),
	nieve = Color3.fromRGB(224, 236, 250),
}

-- ===============================================================
-- Hora del mundo
-- ===============================================================
-- Cuanta luz queda segun la hora: 1 = pleno dia, de noche queda Config.Weather.night
local function dayLum(clock)
	local w = Config.Weather
	if clock >= w.dawnEnd and clock <= w.duskStart then
		return 1
	end
	if clock > w.duskStart and clock < w.duskStart + 3 then
		return 1 - (1 - w.night) * ((clock - w.duskStart) / 3)
	end
	if clock >= w.duskStart + 3 or clock <= 5 then
		return w.night
	end
	return w.night + (1 - w.night) * ((clock - 5) / (w.dawnEnd - 5))
end

-- ===============================================================
-- Luz compuesta: preset de la arena + hora + clima + nieve acumulada
-- ===============================================================
function Weather.apply()
	local w = Config.Weather
	local preset = state.base or Config.LightDefault
	local lum = dayLum(state.clock)
	local f = state.force

	local ambient = escala(preset.ambient, 0.35 + 0.65 * lum)
	local outdoor = escala(preset.outdoor, 0.35 + 0.65 * lum)
	local brightness = preset.brightness * (0.40 + 0.60 * lum)
	local fog = escala(preset.fog, 0.45 + 0.55 * lum)
	local fogStart = preset.fogStart
	local fogEnd = preset.fogEnd

	if state.kind == "lluvia" then
		ambient = escala(ambient, 1 - 0.25 * f)
		outdoor = escala(outdoor, 1 - 0.30 * f)
		brightness = brightness * (1 - 0.35 * f)
		fog = fog:Lerp(Color3.fromRGB(100, 108, 122), 0.60 * f)
		fogStart = fogStart * (1 - 0.45 * f)
		fogEnd = fogEnd * (1 - 0.55 * f)
	elseif state.kind == "nieve" then
		ambient = ambient:Lerp(Color3.fromRGB(172, 180, 196), 0.50 * f)
		outdoor = outdoor:Lerp(Color3.fromRGB(200, 208, 224), 0.55 * f)
		brightness = brightness * (1 - 0.18 * f)
		fog = fog:Lerp(w.snowFog, 0.75 * f)
		fogStart = fogStart * (1 - 0.40 * f)
		fogEnd = fogEnd * (1 - 0.60 * f)
	end

	-- El piso nevado devuelve luz
	if state.accum > 0 then
		ambient = escala(ambient, 1 + 0.25 * state.accum)
		outdoor = escala(outdoor, 1 + 0.20 * state.accum)
	end

	Lighting.Ambient = ambient
	Lighting.OutdoorAmbient = outdoor
	Lighting.Brightness = brightness
	Lighting.FogColor = fog
	Lighting.FogStart = fogStart
	Lighting.FogEnd = fogEnd
	Lighting.ClockTime = state.clock

	-- Con mal tiempo la atmosfera se espesa
	local atmosphere = Lighting:FindFirstChildOfClass("Atmosphere")
	if atmosphere then
		atmosphere.Density = 0.28 + 0.22 * f
		atmosphere.Haze = 1.1 + 1.3 * f
	end
end

-- ===============================================================
-- Nieve acumulada (el mapa se pinta de blanco de a poco)
-- ===============================================================
local function pintarParte(part, target, raiz)
	local material = part.Material
	if material == Enum.Material.Neon or material == Enum.Material.Glass
		or material == Enum.Material.ForceField then
		return
	end
	if part.Transparency >= 0.95 then
		return
	end
	-- Lo marcado con NoNieve no se tapa (el kiwi, por ejemplo)
	local nodo = part
	while nodo and nodo ~= raiz do
		if nodo:GetAttribute("NoNieve") then
			return
		end
		nodo = nodo.Parent
	end
	local base = snapshot[part]
	if not base then
		if target <= 0 then
			return
		end
		base = part.Color
		snapshot[part] = base
	end
	part.Color = base:Lerp(SNOW, target * Config.Weather.snowWhite)
end

-- Pinta todo el mapa de a tandas para no trabar el servidor
function Weather.paint(target)
	if painting or not world then
		return false
	end
	painting = true
	task.spawn(function()
		local roots = {}
		if world.lobby and world.lobby.folder then
			table.insert(roots, world.lobby.folder)
		end
		for _, arena in ipairs(world.arenas or {}) do
			if arena.folder then
				table.insert(roots, arena.folder)
			end
		end
		local n = 0
		for _, root in ipairs(roots) do
			for _, part in ipairs(root:GetDescendants()) do
				if part:IsA("BasePart") then
					pintarParte(part, target, root)
					n = n + 1
					if n >= 400 then
						n = 0
						task.wait()
					end
				end
			end
		end
		painting = false
	end)
	return true
end

-- ===============================================================
-- Clima
-- ===============================================================
local function sortear()
	local w = Config.Weather
	local total = 0
	for _, peso in pairs(w.weights) do
		total = total + peso
	end
	local sorteo = math.random() * total
	local elegido = "sol"
	for id, peso in pairs(w.weights) do
		sorteo = sorteo - peso
		if sorteo <= 0 then
			elegido = id
			break
		end
	end
	-- No repite el clima anterior: siempre hay un cambio a la vista
	if elegido == state.kind then
		if state.kind == "sol" then
			elegido = math.random() < 0.5 and "lluvia" or "nieve"
		elseif state.kind == "lluvia" then
			elegido = math.random() < 0.5 and "sol" or "nieve"
		else
			elegido = math.random() < 0.5 and "sol" or "lluvia"
		end
	end

	local rango = w.changeEvery
	state.nextAt = os.clock() + math.random(rango[1], rango[2])

	if elegido ~= state.kind then
		state.kind = elegido
		local texto = Config.Text.ClimaSol
		if elegido == "lluvia" then
			texto = Config.Text.ClimaLluvia
		elseif elegido == "nieve" then
			texto = Config.Text.ClimaNieve
		end
		for _, player in ipairs(Players:GetPlayers()) do
			Net.get("Notify"):FireClient(player, texto, Util.colorToTable(CLIMA_COLOR[elegido]), 5)
		end
	end
end

local function publicar(nombre, valor)
	if workspace:GetAttribute(nombre) ~= valor then
		workspace:SetAttribute(nombre, valor)
	end
end

function Weather.publish()
	publicar("Clima", state.kind)
	publicar("ClimaFuerza", math.floor(state.force * 50 + 0.5) / 50)
	publicar("Nieve", math.floor(state.accum * 50 + 0.5) / 50)
end

function Weather.tick(dt)
	local w = Config.Weather

	-- Paso del tiempo: un dia completo cada w.dayLength segundos
	state.clock = (state.clock + dt * 24 / w.dayLength) % 24

	if os.clock() >= state.nextAt then
		sortear()
	end

	local goal = (state.kind == "sol") and 0 or 1
	local step = dt / math.max(w.blend, 0.1)
	state.force = state.force + math.clamp(goal - state.force, -step, step)

	if state.kind == "nieve" and state.force > 0.35 then
		state.accum = math.min(1, state.accum + dt * w.snowGrow * state.force)
	elseif state.accum > 0 then
		state.accum = math.max(0, state.accum - dt * w.snowMelt)
	end

	Weather.apply()

	if math.abs(state.accum - state.painted) >= 0.035
		or (state.accum <= 0 and state.painted > 0) then
		if Weather.paint(state.accum) then
			state.painted = state.accum
		end
	end

	Weather.publish()
end

-- ===============================================================
-- API
-- ===============================================================
-- GameManager avisa que preset de luz corresponde (arena / lobby / modo)
function Weather.setBase(preset)
	if not preset then
		return
	end
	state.base = preset
	Weather.apply()
end

-- Solo para pruebas (AutoTest): clava un clima ya mismo
function Weather.force(kind)
	if kind ~= "sol" and kind ~= "lluvia" and kind ~= "nieve" then
		return
	end
	state.kind = kind
	state.force = (kind == "sol") and 0 or 1
	state.nextAt = os.clock() + 600
	Weather.apply()
	Weather.publish()
end

-- Arranca el reloj y el sorteo de clima (lo llama GameManager.init)
function Weather.start(gameWorld)
	world = gameWorld
	state.base = Config.LightDefault
	state.clock = Config.Weather.startClock or 15
	state.kind = "sol"
	state.force = 0
	state.accum = 0
	state.painted = 0
	local primero = Config.Weather.firstChange or Config.Weather.changeEvery
	state.nextAt = os.clock() + math.random(primero[1], primero[2])

	Weather.apply()
	Weather.publish()

	task.spawn(function()
		local last = os.clock()
		while true do
			task.wait(0.5)
			local now = os.clock()
			local dt = now - last
			last = now
			local ok, err = pcall(Weather.tick, dt)
			if not ok then
				warn("[Kiwi Cazador] clima: " .. tostring(err))
			end
		end
	end)
end

return Weather
