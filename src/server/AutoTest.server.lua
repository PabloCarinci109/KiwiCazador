--[[
	AutoTest.server.lua  (SOLO en builds de prueba)
	Recorre los 6 modos automaticamente y revisa que arranquen bien:
	arena, teleport, armas, kiwi, castillo, extraccion, baules de equipo
	y cierre.
	Se incluye en el lugar unicamente al compilar con KIWI_AUTOTEST=1
	(ver tools/build_rbxlx.py). No va en el entregable normal.
--]]

local Players = game:GetService("Players")

local KiwiServer = script.Parent
local modulos = KiwiServer:WaitForChild("modules", 30)
if not modulos then
	return
end
local GameManager = require(modulos.GameManager)
local Weather = require(modulos.Weather)
local Destruction = require(modulos.Destruction)
local Actions = require(modulos.Actions)
local WorldBuilder = require(modulos.WorldBuilder)
-- Shared devuelve la carpeta ReplicatedStorage.KiwiShared: ahi vive Config
local Shared = require(modulos.Shared)
local Config = require(Shared.Config)
local Net = require(Shared.Net)

local pruebas, fallos = 0, 0

local function check(ok, nombre, extra)
	pruebas = pruebas + 1
	if ok then
		print("[AUTO-TEST] OK    " .. nombre)
	else
		fallos = fallos + 1
		print("[AUTO-TEST] FALLA " .. nombre .. (extra and (" -> " .. tostring(extra)) or ""))
	end
end

local function esperar(cond, timeout)
	local t0 = os.clock()
	while os.clock() - t0 < (timeout or 30) do
		local v = cond()
		if v then
			return v
		end
		task.wait(0.25)
	end
	return nil
end

local function raizDe(player)
	local character = player.Character
	return character and character:FindFirstChild("HumanoidRootPart")
end

local function contarArmas(player)
	local backpack = player:FindFirstChildOfClass("Backpack")
	local total = 0
	if backpack then
		for _, item in ipairs(backpack:GetChildren()) do
			if item:IsA("Tool") then
				total = total + 1
			end
		end
	end
	return total
end

local function tieneTool(player, toolId)
	for _, container in ipairs({ player:FindFirstChildOfClass("Backpack"), player.Character }) do
		if container then
			for _, item in ipairs(container:GetChildren()) do
				if item:IsA("Tool") and item:GetAttribute("ToolId") == toolId then
					return true
				end
			end
		end
	end
	return false
end

-- Puesto de una herramienta en la barra (solo la mochila: ahi vive el orden)
local function posicionTool(player, toolId)
	local backpack = player:FindFirstChildOfClass("Backpack")
	if not backpack then
		return 0
	end
	local puesto = 0
	for _, item in ipairs(backpack:GetChildren()) do
		if item:IsA("Tool") then
			puesto = puesto + 1
			if item:GetAttribute("ToolId") == toolId then
				return puesto
			end
		end
	end
	return 0
end

local function usosDe(player, toolId)
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

-- El jugador se declara a nivel de archivo: lo usan tanto el corredor de
-- modos como las pruebas extra (se completa en el arranque, mas abajo).
local player

-- Para diagnosticar el equipamiento si algo falta
local function nombresMochila(p)
	local nombres = {}
	for _, container in ipairs({ p:FindFirstChildOfClass("Backpack"), p.Character }) do
		if container then
			for _, item in ipairs(container:GetChildren()) do
				if item:IsA("Tool") then
					table.insert(nombres, item.Name)
				end
			end
		end
	end
	return #nombres > 0 and table.concat(nombres, ", ") or "(vacia)"
end

local function correrModo(player, modeId, extra)
	print("[AUTO-TEST] ===== MODO " .. modeId .. " =====")
	GameManager.requestJoin(player, modeId)
	local sesion = GameManager.getSession(player)
	check(sesion ~= nil, modeId .. ": sesion creada")
	if not sesion then
		return
	end

	if sesion.phase == "vote" then
		sesion:castVote(player, "random")
	end
	check(esperar(function()
		return sesion.phase == "countdown" or sesion.phase == "playing"
	end, 25) ~= nil, modeId .. ": paso a cuenta regresiva")
	check(esperar(function() return sesion.phase == "playing" end, 20) ~= nil, modeId .. ": paso a juego")
	task.wait(1.5)

	local arena = sesion.arena
	local root = raizDe(player)
	check(arena ~= nil, modeId .. ": arena asignada")
	if arena and root then
		local lejos = (root.Position - arena.center).Magnitude
		check(lejos < arena.halfSize + 60, modeId .. ": jugador teleportado a la arena", string.format("dist=%d", lejos))
	else
		check(root ~= nil, modeId .. ": personaje con raiz")
	end
	check(contarArmas(player) > 0, modeId .. ": recibio herramientas", string.format("tools=%d", contarArmas(player)))
	if not esperar(function()
		return tieneTool(player, "cuchillo")
	end, 8) then
		check(false, modeId .. ": cuchillo mariposa de fabrica", "mochila: " .. nombresMochila(player))
	else
		check(true, modeId .. ": cuchillo mariposa de fabrica")
	end
	-- La barra: la red atrapa kiwis 1 y el cuchillo mariposa 2. En los modos
	-- sin red (o con la red puesta en la mano) el cuchillo queda primero.
	local posCuchillo = posicionTool(player, "cuchillo")
	local posRed = posicionTool(player, "red")
	local ordenOk
	if posRed == 0 then
		ordenOk = posCuchillo == 0 or posCuchillo == 1
	else
		ordenOk = posRed == 1 and (posCuchillo == 0 or posCuchillo == 2)
	end
	check(ordenOk, modeId .. ": barra ordenada (red 1 / cuchillo 2)", "mochila: " .. nombresMochila(player))
	check(sesion.kiwi ~= nil, modeId .. ": el kiwi existe")

	if extra then
		local ok, err = pcall(extra, sesion)
		check(ok, modeId .. ": pruebas extra", err)
	end

	local okEnd = pcall(function()
		sesion:endRound(nil, "test")
	end)
	check(okEnd, modeId .. ": termino la ronda")
	pcall(function()
		sesion.phase = "ended"
		sesion.phaseEnds = os.clock() - 1
	end)
	check(esperar(function() return sesion.finished end, 20) ~= nil, modeId .. ": sesion cerrada")
	if not sesion.finished then
		pcall(function()
			sesion:finish()
		end)
	end
	-- "Volvio al lobby": la sesion termina. Ojo: el juego puede armar una
	-- sesion nueva enseguida, asi que vale si salio de ESTA sesion.
	check(esperar(function()
		local actual = GameManager.getSession(player)
		return actual == nil or actual ~= sesion
	end, 8) ~= nil, modeId .. ": volvio al lobby")
	check(GameManager.getRematch(player) ~= nil, modeId .. ": revancha anotada en la misma arena")
	task.wait(1)
end

-- Pruebas extra por modo ------------------------------------------------
-- Revisa que todos los puntos de aparicion de la arena caigan en el piso
-- firme del mapa: nada de colinas, techos ni paredes (es el chequeo del
-- respawn en todos los modos). Ignora personajes y al kiwi: si uno esta
-- parado arriba del punto no significa que el piso este mal.
local function spawnsEnPiso(arena, label, ignoreModel)
	if not arena or not arena.spawns then
		check(false, label .. ": la arena tiene spawns")
		return
	end
	local params = RaycastParams.new()
	params.IgnoreWater = true
	params.FilterType = Enum.RaycastFilterType.Exclude
	local ignorar = {}
	for _, pl in ipairs(Players:GetPlayers()) do
		if pl.Character then
			table.insert(ignorar, pl.Character)
		end
	end
	if ignoreModel then
		table.insert(ignorar, ignoreModel)
	end
	params.FilterDescendantsInstances = ignorar
	local malos, total = 0, 0
	local idxMalo, dyMalo, tocaMalo = nil, nil, nil
	for idx, spawn in ipairs(arena.spawns) do
		total = total + 1
		local p = spawn.Position
		local ray = workspace:Raycast(Vector3.new(p.X, arena.floorY + 120, p.Z), Vector3.new(0, -300, 0), params)
		local dy = ray and (ray.Position.Y - arena.floorY) or -999
		if not ray or dy < -1.5 or dy > 3 then
			malos = malos + 1
			if not idxMalo then
				idxMalo = idx
				dyMalo = dy
				tocaMalo = ray and (ray.Instance.Name .. " de " .. tostring(ray.Instance.Parent and ray.Instance.Parent.Name)) or "nada"
			end
		end
	end
	local detalle = "malos=" .. malos .. "/" .. total
	if idxMalo then
		detalle = detalle .. " #" .. idxMalo .. " dy=" .. string.format("%.1f", dyMalo) .. " toca=" .. tocaMalo
	end
	check(total >= 4 and malos == 0, label .. ": los spawns caen en piso firme", detalle)
end

local function extrasSolo(sesion)
	spawnsEnPiso(sesion.arena, sesion.modeId or "solo", sesion.kiwi and sesion.kiwi.model)
	local chest = sesion.arena and sesion.arena.chests and sesion.arena.chests[1]
	check(chest ~= nil, "solo: hay baul en el mapa")
	if chest then
		local character = player.Character
		if character then
			character:PivotTo(CFrame.new(chest.center + Vector3.new(0, 4, 0)))
		end
		task.wait(0.3)
		sesion:openChest(player, chest)
		check(chest.used == true, "solo: el baul entrega un arma")
		check(sesion.stats[player].lastLoot ~= nil, "solo: arma asignada")
		check(tieneTool(player, "frag") and tieneTool(player, "humo")
			and tieneTool(player, "molotov") and tieneTool(player, "flash"),
			"solo: el baul entrega el pack de granadas")
		check(usosDe(player, "flash") == 2, "solo: la flash viene con 2 usos")
		-- Lanzar una granada de humo: vuela con fisica y detona sola
		local rootGranada = raizDe(player)
		if rootGranada then
			local okTiro = pcall(function()
				Actions.throwNade(sesion, player, "humo", Config.Grenades.humo,
					rootGranada.Position + Vector3.new(0, 2, 0), Vector3.new(0, 0.35, -1).Unit)
			end)
			check(okTiro, "solo: la granada se lanza sin errores")
			local volando = false
			for _, p in ipairs(sesion.projectiles or {}) do
				if p.kind == "grenade" then
					volando = true
				end
			end
			check(volando, "solo: la granada quedo volando con fisica")
			task.wait(2.4)
			local quedo = false
			for _, p in ipairs(sesion.projectiles or {}) do
				if p.kind == "grenade" then
					quedo = true
				end
			end
			check(not quedo, "solo: la granada detono sola con la mecha")

			-- La nube de humo: esferas que brotan y focos de particulas
			local hayBola, hayNube = false, false
			for _, parte in ipairs(workspace:GetChildren()) do
				if parte.Name == "HumoBola" then
					hayBola = true
				elseif parte.Name == "Humo" and parte:FindFirstChild("Nube") then
					hayNube = true
				end
			end
			check(hayBola and hayNube, "solo: la nube de humo brota de verdad")

			-- Molotov: al romperse arma el fuego de verdad (llamas, brasas,
			-- humo y mancha quemada) que despues se limpia solo
			local okFuego = pcall(function()
				Actions.throwNade(sesion, player, "molotov", Config.Grenades.molotov,
					rootGranada.Position + Vector3.new(0, 2, 0), Vector3.new(0, 0.9, -1).Unit)
			end)
			check(okFuego, "solo: el molotov se lanza sin errores")
			task.wait(2.5)
			local cuenta = { Llama = 0, Brasa = 0, Humo = 0, Quemado = 0 }
			for _, parte in ipairs(workspace:GetChildren()) do
				if cuenta[parte.Name] then
					cuenta[parte.Name] = cuenta[parte.Name] + 1
				end
			end
			check(cuenta.Llama > 0 and cuenta.Brasa > 0,
				"solo: el molotov prende fuego real",
				string.format("llamas=%d brasas=%d humo=%d", cuenta.Llama, cuenta.Brasa, cuenta.Humo))
			check(cuenta.Quemado > 0, "solo: el fuego deja mancha quemada")
			-- El fuego y su humo ahora son de particulas (textura de llama)
			local fuegoParticulas, humoParticulas = false, false
			for _, parte in ipairs(workspace:GetChildren()) do
				if parte.Name == "Llama" and parte:FindFirstChild("Fuego") then
					fuegoParticulas = true
				elseif parte.Name == "Humo" and parte:FindFirstChild("HumoGris") then
					humoParticulas = true
				end
			end
			check(fuegoParticulas, "solo: el fuego del molotov usa particulas")
			check(humoParticulas, "solo: el humo del fuego usa particulas")
		end
	end
	local antes = sesion.stats[player].hp
	sesion:damagePlayer(player, nil, "prueba", 15, nil, "prueba")
	check(sesion.stats[player].hp < antes, "solo: el dano baja la vida")
	check(sesion.arena and sesion.arena.safeZone == nil, "solo: sin zona segura de colosal en este mapa")
end

local function extrasColosal(sesion)
	spawnsEnPiso(sesion.arena, "colosal", sesion.kiwi and sesion.kiwi.model)
	check(sesion.isColosal, "colosal: modo marcado")
	check(sesion.arena and sesion.arena.safeZone ~= nil, "colosal: zona segura existe")
	check(sesion.safeZoneFolder ~= nil and sesion.safeZoneFolder.Name == "ZonaSeguraColosal",
		"colosal: la zona se arma solo para su partida")
	check(sesion.kiwi ~= nil and sesion.kiwi.giant == true, "colosal: kiwi gigante")
end

local function extrasMulti(sesion)
	spawnsEnPiso(sesion.arena, "multi", sesion.kiwi and sesion.kiwi.model)
	check(sesion.isMulti, "multi: modo marcado")
	check(#sesion.players >= 1, "multi: jugador dentro")
	check(sesion.arena and sesion.arena.safeZone == nil, "multi: sin zona segura de colosal en el mapa")
end

local function extrasAsedio(sesion)
	check(sesion.fort ~= nil, "asedio: castillo construido")
	check(sesion.arena and sesion.arena.safeZone == nil, "asedio: sin zona segura de colosal en el castillo")
	check(sesion.fort and sesion.fort.folder:FindFirstChild("Escalon") ~= nil, "asedio: escalera al techo")
	check(sesion.fort and sesion.fort.folder:FindFirstChild("CulvertPiso") ~= nil, "asedio: subterraneo secreto")
	check(Config.Asedio.roundTime == 300 and Config.Asedio.recoveryTime == 120, "asedio: reglas 5 min / 2 min de extraccion")
	check(sesion.fortChests ~= nil, "asedio: baules de equipo")
	check(sesion.kiwi ~= nil and sesion.kiwi.leash ~= nil, "asedio: kiwi con nido")

	-- El kiwi ahora espera quieto en su corralito adentro de la casa
	check(sesion.kiwi ~= nil and sesion.kiwi.estatico == true, "asedio: el kiwi espera quieto")
	check(sesion.fort ~= nil and sesion.fort.corral ~= nil and sesion.fort.corral.pos ~= nil, "asedio: el corral del kiwi esta armado")
	check(sesion.fort ~= nil and sesion.fort.folder:FindFirstChild("CorralPoste") ~= nil, "asedio: el cerco del corral existe")
	if sesion.kiwi ~= nil and sesion.fort ~= nil and sesion.fort.corral ~= nil then
		local p1 = sesion.kiwi:getPosition()
		local dist = (p1 - sesion.fort.corral.pos).Magnitude
		check(dist < (Config.Asedio.corralRadius + 3), "asedio: el kiwi arranca adentro del corral", string.format("%.1f", dist))
		-- Tiene que verse: el cerebro hider nace invisible y sin este
		-- chequeo el kiwi quedaba plantado pero transparente.
		local rigK = sesion.kiwi.rig
		check(rigK ~= nil and rigK.visible == true, "asedio: el kiwi del corral se ve (no esta invisible)")
		check(rigK ~= nil and rigK.body ~= nil and rigK.body.Transparency == 0, "asedio: el cuerpo del kiwi no es transparente",
			rigK and rigK.body and string.format("%.2f", rigK.body.Transparency) or "sin cuerpo")
		task.wait(1.2)
		local p2 = sesion.kiwi:getPosition()
		check((p1 - p2).Magnitude < 1.5, "asedio: el kiwi no se pasea (sigue en el corral)")
	end

	-- El respawn de los equipos tambien tiene que caer en piso firme
	local okSp, sp = pcall(function()
		return sesion:spawnsFor(player)
	end)
	local raySp = nil
	local tocaSp = "nada"
	if okSp and sp then
		local params = RaycastParams.new()
		params.IgnoreWater = true
		params.FilterType = Enum.RaycastFilterType.Exclude
		local ignorar = {}
		for _, pl in ipairs(Players:GetPlayers()) do
			if pl.Character then
				table.insert(ignorar, pl.Character)
			end
		end
		if sesion.kiwi and sesion.kiwi.model then
			table.insert(ignorar, sesion.kiwi.model)
		end
		params.FilterDescendantsInstances = ignorar
		raySp = workspace:Raycast(Vector3.new(sp.Position.X, sp.Position.Y + 60, sp.Position.Z), Vector3.new(0, -160, 0), params)
		if raySp then
			tocaSp = raySp.Instance.Name .. " de " .. tostring(raySp.Instance.Parent and raySp.Instance.Parent.Name)
		end
	end
	local dySp = raySp and (raySp.Position.Y - (sesion.arena.floorY or 0)) or -999
	check(okSp and raySp ~= nil and dySp >= -1.5 and dySp <= 3, "asedio: el respawn del equipo cae en piso firme",
		"dy=" .. string.format("%.1f", dySp) .. " toca=" .. tocaSp)

	check(sesion.teamsReady and sesion.teamOf[player] ~= nil, "asedio: equipos repartidos")

	-- La captura no da el punto al instante: el Cazador alza al kiwi y hay
	-- que llevarlo a la zona marcada y aguantarlo ahi 2 minutos. El jugador
	-- puede caer en cualquier equipo (los bandos se sortean): se prueban los
	-- dos caminos.
	local side = sesion.teamOf[player] or "attack"
	local okCap = pcall(function()
		if side == "attack" then
			sesion.kiwi:sedate(5, player)
			sesion:onKiwiTouch(sesion.kiwi, player)
		else
			sesion.kiwi:capture(player)
			sesion:asedioCarryStart(player)
		end
	end)
	check(okCap, "asedio: capturar al kiwi sin errores")
	check(sesion.carry ~= nil, "asedio: el kiwi queda en brazos")
	check(sesion.fort ~= nil and sesion.fort.zone ~= nil and sesion.fort.zone.pos ~= nil, "asedio: zona de extraccion marcada")
	if sesion.fort and sesion.fort.zone and sesion.arena then
		local zona = sesion.fort.zone.pos
		check(math.abs(zona.Y - sesion.arena.floorY) < 0.01, "asedio: la zona de extraccion esta apoyada en el piso",
			string.format("dy=%.2f", zona.Y - sesion.arena.floorY))
		local params = OverlapParams.new()
		params.FilterType = Enum.RaycastFilterType.Include
		params.FilterDescendantsInstances = { sesion.arena.folder }
		params.RespectCanCollide = true
		local blockers = 0
		for _, p in ipairs(workspace:GetPartBoundsInRadius(zona + Vector3.new(0, 4, 0), 9, params)) do
			local alto = (p.Position.Y + p.Size.Y * 0.5) - zona.Y
			local bajo = (p.Position.Y - p.Size.Y * 0.5) - zona.Y
			if p ~= sesion.arena.ground and not p:IsDescendantOf(sesion.fort.folder) and alto > 2.5 and bajo < 4 then
				blockers = blockers + 1
			end
		end
		check(blockers == 0, "asedio: la zona de extraccion esta despejada", "bloqueos=" .. blockers)
	end
	local character = player.Character
	if side == "attack" then
		-- Llevarlo a la zona: al entrar el portador lo deja plantado ahi
		-- y la cuenta de extraccion arranca sola
		local okLleva = false
		if character and sesion.fort.zone then
			okLleva = pcall(function()
				character:PivotTo(CFrame.new(sesion.fort.zone.pos + Vector3.new(0, 4, 0)))
			end)
		end
		local plantado = okLleva and esperar(function()
			return sesion.carry ~= nil and sesion.carry.by == nil
		end, 6) ~= nil
		check(plantado, "asedio: al entrar a la zona el kiwi queda plantado en el piso")
		task.wait(1.2)
		check(sesion.carry ~= nil and (sesion.carry.hold or 0) > 0.5, "asedio: la extraccion avanza en la zona")
		-- Plantado en la zona, un Cazador ya no se lo puede volver a llevar
		if character and sesion.kiwi then
			pcall(function()
				character:PivotTo(CFrame.new(sesion.kiwi:getPosition() + Vector3.new(0, 4, 0)))
			end)
		end
		task.wait(0.6)
		check(sesion.carry ~= nil and sesion.carry.by == nil, "asedio: en la zona no se levanta de nuevo")
		local okRescate = pcall(function()
			sesion:asedioRecover()
		end)
		check(okRescate and sesion.carry == nil, "asedio: el rescate corta la extraccion")
	else
		-- Defensor: al kiwi lo soltaron y acercarse lo rescata
		sesion.carry.by = nil
		local okSuelta = pcall(function()
			sesion.kiwi:dropHold()
		end)
		local okCerca = false
		if character and sesion.kiwi then
			okCerca = pcall(function()
				character:PivotTo(CFrame.new(sesion.kiwi:getPosition() + Vector3.new(0, 4, 0)))
			end)
		end
		local rescatado = okSuelta and okCerca and esperar(function()
			return sesion.carry == nil
		end, 6) ~= nil
		check(rescatado, "asedio: acercarse rescata al kiwi")
	end
	check(sesion.kiwi ~= nil and not sesion.kiwi.defeated, "asedio: el kiwi rescatado vuelve sano")

	local mio = sesion.fortChests and sesion.fortChests[side]
	local otro = sesion.fortChests and sesion.fortChests[side == "attack" and "defend" or "attack"]

	if otro and character then
		character:PivotTo(CFrame.new(otro.center + Vector3.new(0, 4, 0)))
		task.wait(0.3)
		sesion:openChest(player, otro)
		check(sesion.looted[player] ~= true, "asedio: el baul del otro equipo no entrega")
	end
	if mio and character then
		character:PivotTo(CFrame.new(mio.center + Vector3.new(0, 4, 0)))
		task.wait(0.3)
		sesion:openChest(player, mio)
		check(sesion.looted[player] == true, "asedio: mi baul entrega un arma")
		local armaAntes = sesion.stats[player].lastLoot
		sesion:openChest(player, mio)
		check(sesion.stats[player].lastLoot == armaAntes, "asedio: solo UNA arma por jugador")
	end

	local hpAntes = sesion.stats[player].hp
	sesion:damagePlayer(player, nil, "prueba", 20, nil, "prueba")
	check(sesion.stats[player].hp < hpAntes, "asedio: el dano funciona")

	sesion.knocked[player] = nil
	local okRespawn = pcall(function()
		sesion:asedioRespawn(player)
	end)
	check(okRespawn, "asedio: respawn sin errores")
	check(sesion.stats[player].hp == 100, "asedio: respawn con vida llena")

	-- Barrida total: si a un equipo lo noquean entero a la vez, el otro se
	-- lleva la ronda. Con un solo jugador se anota un companero de prueba
	-- del otro lado para poder verificarlo.
	local miLado = sesion:asedioSide(player)
	local rival = miLado == "attack" and "defend" or "attack"
	local antes = sesion.teamScore[rival] or 0
	local dummy = {}
	table.insert(sesion.teams[rival], dummy)
	sesion.stats[dummy] = { caught = 0 }
	sesion.knocked[player] = true
	local gano = esperar(function()
		return (sesion.teamScore[rival] or 0) > antes
	end, 6) ~= nil
	sesion.knocked[player] = nil
	sesion.stats[dummy] = nil
	for i = #sesion.teams[rival], 1, -1 do
		if sesion.teams[rival][i] == dummy then
			table.remove(sesion.teams[rival], i)
		end
	end
	check(gano, "asedio: equipo eliminado da la ronda al rival")
end

-- Arranque --------------------------------------------------------------
player = Players:GetPlayers()[1]
if not player then
	player = Players.PlayerAdded:Wait()
end
task.wait(8)
print("[AUTO-TEST] jugador: " .. player.Name .. " (v" .. Config.Version .. ")")

-- Mapas: las 5 arenas tienen que quedar sin montañas adentro (antes las
-- colinas tapaban las entradas de las casas) y con un lugar despejado y
-- apoyado en el piso para la zona de extracción del asedio.
do
	local world = GameManager.world
	if not world then
		esperar(function()
			return GameManager.world
		end, 15)
		world = GameManager.world
	end
	local arenas = world and world.arenas or {}
	check(#arenas == Config.World.ArenaCount, "mapas: estan las " .. Config.World.ArenaCount .. " arenas", "n=" .. #arenas)
	for _, arena in ipairs(arenas) do
		local label = "mapa " .. tostring(arena.mapId or "?")
		local adentro = 0
		if arena.propsFolder then
			for _, item in ipairs(arena.propsFolder:GetChildren()) do
				if item.Name == "Colina" then
					adentro = adentro + 1
				elseif item.Name == "Montana" or item.Name == "MontanaEsquina" then
					local semi = math.max(item.Size.X, item.Size.Z) * 0.5
					if math.abs(item.Position.X - arena.center.X) < arena.halfSize - semi
						and math.abs(item.Position.Z - arena.center.Z) < arena.halfSize - semi then
						adentro = adentro + 1
					end
				end
			end
		end
		check(adentro == 0, label .. ": sin montañas adentro de la arena", "n=" .. adentro)

		local tieneNido = arena.nest ~= nil and arena.nest.pos ~= nil
		check(tieneNido, label .. ": tiene nido del asedio")
		if tieneNido then
			local centro = Vector3.new(arena.nest.pos.X, arena.floorY, arena.nest.pos.Z)
			local H = WorldBuilder.asedioFortHalf(arena, centro)
			check(H >= 22, label .. ": entra el castillo del asedio", string.format("H=%.0f", H))
			local dir = arena.center - centro
			dir = Vector3.new(dir.X, 0, dir.Z)
			if dir.Magnitude < 1 then
				dir = Vector3.new(0, 0, 1)
			end
			dir = dir.Unit
			local pos = WorldBuilder.findExtractionSpot(arena, centro, dir, H)
			check(pos ~= nil, label .. ": hay lugar despejado para la extraccion")
			if pos then
				check(math.abs(pos.Y - arena.floorY) < 0.01, label .. ": la extraccion esta apoyada en el piso",
					string.format("dy=%.2f", pos.Y - arena.floorY))
				local params = OverlapParams.new()
				params.FilterType = Enum.RaycastFilterType.Include
				params.FilterDescendantsInstances = { arena.folder }
				params.RespectCanCollide = true
				local blockers = 0
				for _, p in ipairs(workspace:GetPartBoundsInRadius(pos + Vector3.new(0, 4, 0), 9, params)) do
					local alto = (p.Position.Y + p.Size.Y * 0.5) - pos.Y
					local bajo = (p.Position.Y - p.Size.Y * 0.5) - pos.Y
					if p ~= arena.ground and alto > 2.5 and bajo < 4 then
						blockers = blockers + 1
					end
				end
				check(blockers == 0, label .. ": la extraccion esta despejada", "bloqueos=" .. blockers)
			end
		end
	end
end

-- Escopeta: 100 de daño de cerca (8 perdigones de 12,5) y menos daño
-- a medida que el enemigo se aleja.
do
	local esc = Config.Weapons.escopeta
	local total = (esc.damage or 0) * (esc.pellets or 0)
	check(math.abs(total - 100) < 0.01, "escopeta: 100 de daño a corta distancia", string.format("%.1f", total))
	local cerca = Actions.damageAtDistance("escopeta", 5)
	local medio = Actions.damageAtDistance("escopeta", 32)
	local lejos = Actions.damageAtDistance("escopeta", 64)
	check(math.abs(cerca - 100) < 0.01, "escopeta: a 5 studs pega 100", string.format("%.1f", cerca))
	check(medio < cerca and lejos < medio, "escopeta: el daño baja con la distancia",
		string.format("5=%.1f 32=%.1f 64=%.1f", cerca, medio, lejos))
end

-- Precisión: quieto o caminando (Shift) el tiro es exacto; corriendo se
-- dispersa. Con la mira puesta pasa lo mismo.
do
	local quieto = { AssemblyLinearVelocity = Vector3.new(0, 0, 0) }
	local caminando = { AssemblyLinearVelocity = Vector3.new(Config.Player.walkSpeed, 0, 0) }
	local corriendo = { AssemblyLinearVelocity = Vector3.new(Config.Player.sprintSpeed, 0, 0) }
	local datos = { scoped = false }
	for _, id in ipairs({ "ak", "m4", "mp5", "glock", "escopeta", "revolver", "arco", "sniper", "cohete" }) do
		local eQuieto = Actions.spreadError(id, quieto, datos)
		local eCaminando = Actions.spreadError(id, caminando, datos)
		local eCorriendo = Actions.spreadError(id, corriendo, datos)
		check(eCaminando == eQuieto and eCorriendo > eCaminando,
			"armas: " .. id .. " pierde precision al correr",
			string.format("quieto=%.2f caminando=%.2f corriendo=%.2f", eQuieto, eCaminando, eCorriendo))
	end
	local adsQuieto = Actions.spreadError("m4", quieto, { scoped = true })
	local adsCaminando = Actions.spreadError("m4", caminando, { scoped = true })
	local adsCorriendo = Actions.spreadError("m4", corriendo, { scoped = true })
	check(adsQuieto == 0 and adsCaminando == 0 and adsCorriendo > 0,
		"armas: con la mira y corriendo tambien se dispersa",
		string.format("quieto=%.2f caminando=%.2f corriendo=%.2f", adsQuieto, adsCaminando, adsCorriendo))
	local sniperQuieto = Actions.spreadError("sniper", quieto, { scoped = true })
	local sniperCaminando = Actions.spreadError("sniper", caminando, { scoped = true })
	local sniperCorriendo = Actions.spreadError("sniper", corriendo, { scoped = true })
	check(sniperQuieto == 0 and sniperCaminando == 0 and sniperCorriendo > 0,
		"armas: el francotirador con mira es exacto quieto o caminando",
		string.format("quieto=%.2f caminando=%.2f corriendo=%.2f", sniperQuieto, sniperCaminando, sniperCorriendo))
end

-- Clima: estado publicado y una nevada de prueba (despues vuelve el sol)
check(workspace:GetAttribute("Clima") ~= nil, "clima: estado publicado en el workspace")
check(pcall(function()
	Weather.force("nieve")
end), "clima: forzar nevada sin errores")
check(esperar(function()
	return (workspace:GetAttribute("Nieve") or 0) > 0
end, 25) ~= nil, "clima: la nieve se acumula en el piso")
pcall(function()
	Weather.force("sol")
end)
task.wait(1)
check(workspace:GetAttribute("Clima") == "sol", "clima: vuelve el sol")

-- Mapa rompible: el lanzamisiles destroza casas, autos, trenes y arboles
check(Destruction.count() > 20, "mapa: objetos rompibles registrados", "n=" .. Destruction.count())
local pruebaRompe = Instance.new("Part")
pruebaRompe.Name = "PruebaRompe"
pruebaRompe.Anchored = true
pruebaRompe.CanCollide = false
pruebaRompe.Size = Vector3.new(2, 2, 2)
pruebaRompe.Position = Vector3.new(0, 500, 0)
pruebaRompe.Parent = workspace
Destruction.marcar(pruebaRompe, "prueba")
local okRompe = pcall(function()
	Destruction.explosivo(pruebaRompe.Position + Vector3.new(6, 0, 0), 30, 40)
end)
task.wait(0.5)
check(okRompe and pruebaRompe.Anchored == false, "mapa: el cohete suelta las partes golpeadas")
pruebaRompe:Destroy()

local casos = {
	{ id = "facil", extra = extrasSolo },
	{ id = "normal", extra = extrasSolo },
	{ id = "dificil", extra = extrasSolo },
	{ id = "colosal", extra = extrasColosal },
	{ id = "multi", extra = extrasMulti },
	{ id = "asedio", extra = extrasAsedio },
}

for _, caso in ipairs(casos) do
	local ok, err = pcall(correrModo, player, caso.id, caso.extra)
	if not ok then
		check(false, caso.id .. ": error inesperado", err)
		local sesion = GameManager.getSession(player)
		if sesion then
			pcall(function()
				sesion:finish()
			end)
		end
		task.wait(1)
	end
end

-- Menú de partida: cambiar de modo y de mapa sin esperar a morir.
do
	print("[AUTO-TEST] ===== MENU DE PARTIDA =====")
	check(Net.get("RequestSwitch") ~= nil, "menu: remote para cambiar de partida")

	local libres = esperar(function()
		for _, arena in ipairs(GameManager.world.arenas) do
			if arena.busy then
				return false
			end
		end
		return true
	end, 15)
	check(libres ~= nil, "menu: arenas libres para la prueba")

	GameManager.requestJoin(player, "facil")
	local s1 = GameManager.getSession(player)
	check(s1 ~= nil and s1.modeId == "facil", "menu: entra a una partida de prueba")
	task.wait(0.4)

	local s2 = GameManager.requestSwitch(player, "normal", "dunas")
	local actual = GameManager.getSession(player)
	check(actual ~= nil and actual ~= s1 and actual.modeId == "normal",
		"menu: cambia de modo sin morir")
	check(actual ~= nil and actual.arena ~= nil and actual.arena.mapId == "dunas",
		"menu: arranca en el mapa elegido", actual and actual.arena and actual.arena.mapId or "sin arena")
	check(actual ~= nil and (actual.phase == "countdown" or actual.phase == "playing"),
		"menu: la partida nueva arranca sola", actual and actual.phase or "?")

	task.wait(1.6)
	GameManager.requestSwitch(player, nil, "costa")
	local actual2 = GameManager.getSession(player)
	check(actual2 ~= nil and actual2 ~= actual and actual2.modeId == "normal",
		"menu: cambia de mapa sin cambiar de modo")
	check(actual2 ~= nil and actual2.arena ~= nil and actual2.arena.mapId == "costa",
		"menu: queda en el mapa elegido", actual2 and actual2.arena and actual2.arena.mapId or "sin arena")

	GameManager.requestLeave(player)
	check(esperar(function()
		return GameManager.getSession(player) == nil
	end, 8) ~= nil, "menu: vuelve al lobby")
end

-- El fuego de los molotovs no deja restos: al terminar las partidas no
-- puede quedar ninguna llama, brasa ni mancha prendida en el mundo.
local restosFuego = 0
for _, item in ipairs(workspace:GetChildren()) do
	local nombre = item.Name
	if nombre == "Llama" or nombre == "Brasa" or nombre == "Humo" or nombre == "Quemado" or nombre == "LuzFuego" then
		restosFuego = restosFuego + 1
	end
end
check(restosFuego == 0, "molotov: el fuego no queda prendido al terminar", "restos=" .. restosFuego)

print(string.format("[AUTO-TEST] FIN: %d pruebas, %d fallos", pruebas, fallos))
