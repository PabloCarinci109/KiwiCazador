--[[
	AutoTest.server.lua  (SOLO en builds de prueba)
	Recorre los 6 modos automaticamente y revisa que arranquen bien:
	arena, teleport, armas, kiwi, bunker, baules de equipo y cierre.
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
local Config = require(modulos.Shared.Config)

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
	check(esperar(function() return sesion.phase == "countdown" end, 25) ~= nil, modeId .. ": paso a cuenta regresiva")
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
	check(tieneTool(player, "cuchillo"), modeId .. ": cuchillo mariposa de fabrica")
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
	check(GameManager.getSession(player) == nil, modeId .. ": volvio al lobby")
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
		end
	end
	local antes = sesion.stats[player].hp
	sesion:damagePlayer(player, nil, "prueba", 15, nil, "prueba")
	check(sesion.stats[player].hp < antes, "solo: el dano baja la vida")
end

local function extrasColosal(sesion)
	check(sesion.isColosal, "colosal: modo marcado")
	check(sesion.arena and sesion.arena.safeZone ~= nil, "colosal: zona segura existe")
	check(sesion.kiwi ~= nil and sesion.kiwi.giant == true, "colosal: kiwi gigante")
end

local function extrasMulti(sesion)
	check(sesion.isMulti, "multi: modo marcado")
	check(#sesion.players >= 1, "multi: jugador dentro")
end

local function extrasAsedio(sesion)
	check(sesion.fort ~= nil, "asedio: bunker construido")
	check(sesion.fortChests ~= nil, "asedio: baules de equipo")
	check(sesion.kiwi ~= nil and sesion.kiwi.leash ~= nil, "asedio: kiwi con nido")
	check(sesion.teamsReady and sesion.teamOf[player] ~= nil, "asedio: equipos repartidos")

	local side = sesion.teamOf[player] or "attack"
	local mio = sesion.fortChests and sesion.fortChests[side]
	local otro = sesion.fortChests and sesion.fortChests[side == "attack" and "defend" or "attack"]
	local character = player.Character

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
end

-- Arranque --------------------------------------------------------------
local player = Players:GetPlayers()[1]
if not player then
	player = Players.PlayerAdded:Wait()
end
task.wait(8)
print("[AUTO-TEST] jugador: " .. player.Name .. " (v" .. require(modulos.Shared.Config).Version .. ")")

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
