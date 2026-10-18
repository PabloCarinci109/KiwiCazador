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
-- Shared devuelve la carpeta ReplicatedStorage.KiwiShared: ahi vive Config
local Shared = require(modulos.Shared)
local Config = require(Shared.Config)

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
local function extrasSolo(sesion)
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
		end
	end
	local antes = sesion.stats[player].hp
	sesion:damagePlayer(player, nil, "prueba", 15, nil, "prueba")
	check(sesion.stats[player].hp < antes, "solo: el dano baja la vida")
	check(sesion.arena and sesion.arena.safeZone == nil, "solo: sin zona segura de colosal en este mapa")
end

local function extrasColosal(sesion)
	check(sesion.isColosal, "colosal: modo marcado")
	check(sesion.arena and sesion.arena.safeZone ~= nil, "colosal: zona segura existe")
	check(sesion.safeZoneFolder ~= nil and sesion.safeZoneFolder.Name == "ZonaSeguraColosal",
		"colosal: la zona se arma solo para su partida")
	check(sesion.kiwi ~= nil and sesion.kiwi.giant == true, "colosal: kiwi gigante")
end

local function extrasMulti(sesion)
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

print(string.format("[AUTO-TEST] FIN: %d pruebas, %d fallos", pruebas, fallos))
