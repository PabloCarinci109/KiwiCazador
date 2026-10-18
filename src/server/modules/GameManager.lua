--[[
	GameManager.lua  (servidor)
	Maneja las partidas: quien entra, en que arena, fases de la ronda
	(cuenta regresiva / caza / resultados), el kiwi de cada sesion, los
	premios y el regreso al lobby.

	Modos:
		facil / normal / dificil  -> individual, hay que atrapar N kiwis
		colosal                   -> sobrevive al kiwi gigante escondiéndote
		multi                     -> todos juntos, gana el primero
--]]

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local Lighting = game:GetService("Lighting")

local Shared = require(script.Parent.Shared)
local Config = require(Shared.Config)
local Net = require(Shared.Net)
local Util = require(Shared.Util)

local WorldBuilder = require(script.Parent.WorldBuilder)
local KiwiController = require(script.Parent.KiwiController)
local ToolService = require(script.Parent.ToolService)
local Actions = require(script.Parent.Actions)
local Weather = require(script.Parent.Weather)

local GameManager = {}

local Session = {}
Session.__index = Session

local world
local sessions = {}
local playerSession = {}
local sessionCounter = 0

local COLOR = {
	good = Color3.fromRGB(102, 209, 130),
	bad = Color3.fromRGB(232, 108, 100),
	warn = Color3.fromRGB(238, 196, 92),
	info = Color3.fromRGB(200, 214, 226),
	fx = Color3.fromRGB(160, 200, 255),
}

-- ===============================================================
-- Iluminacion (cambia segun el mapa y se restaura al salir)
-- ===============================================================
local function applyLighting(preset)
	if not preset then
		return
	end
	-- La luz final la compone Weather: preset de la arena + hora + clima
	Weather.setBase(preset)
end

local function applyZoneLighting(arena)
	local zone = arena and arena.zone
	local preset = zone and Config.ZoneLight[zone.theme or "bosque"]
	applyLighting(preset or Config.LightDefault)
end

-- ===============================================================
-- Utilidades de jugador
-- ===============================================================
local function getRoot(player)
	local character = player.Character
	if not character then
		return nil
	end
	return character:FindFirstChild("HumanoidRootPart")
end

local function setFrozen(player, frozen)
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if humanoid then
		humanoid.WalkSpeed = frozen and 0 or Config.Player.sprintSpeed
		humanoid.JumpPower = frozen and 0 or 50
		humanoid.UseJumpPower = true
	end
end

-- Oculta el cuerpo entero dentro de un escondite (invisible para todos)
local function setBodyHidden(player, hidden)
	local character = player.Character
	if not character then
		return
	end
	for _, item in ipairs(character:GetDescendants()) do
		if item:IsA("BasePart") then
			if hidden then
				if item:GetAttribute("HideT") == nil then
					item:SetAttribute("HideT", item.Transparency)
					item.Transparency = 1
				end
			else
				local saved = item:GetAttribute("HideT")
				if saved ~= nil then
					item.Transparency = saved
					item:SetAttribute("HideT", nil)
				end
			end
		end
	end
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if humanoid then
		humanoid.DisplayDistanceType = hidden and Enum.HumanoidDisplayDistanceType.None
			or Enum.HumanoidDisplayDistanceType.Viewer
	end
end

local function leaderstatsFor(player)
	local stats = player:FindFirstChild("leaderstats")
	if not stats then
		stats = Instance.new("Folder")
		stats.Name = "leaderstats"
		stats.Parent = player
	end

	local function stat(name, default)
		local value = stats:FindFirstChild(name)
		if not value then
			value = Instance.new("IntValue")
			value.Name = name
			value.Value = default
			value.Parent = stats
		end
		return value
	end

	return {
		stats = stats,
		caught = stat("Kiwis", 0),
		coins = stat("Monedas", 0),
	}
end

local function addCoins(player, amount)
	local stats = leaderstatsFor(player)
	stats.coins.Value = stats.coins.Value + amount
	return stats.coins.Value
end

local function addCaught(player, amount)
	local stats = leaderstatsFor(player)
	stats.caught.Value = stats.caught.Value + amount
end

-- ===============================================================
-- SESION
-- ===============================================================
function Session.new(modeId, rng)
	local self = setmetatable({}, Session)
	sessionCounter = sessionCounter + 1
	self.id = sessionCounter
	self.rng = rng or Random.new()
	self.modeId = modeId
	self.players = {}
	self.stats = {}
	self.projectiles = {}
	self.finished = false
	self.needRespawn = false
	self.respawnAt = 0
	self.kiwi = nil
	self.winner = nil
	self.arena = nil
	self.updateTimer = 0
	self.traps = {}
	self.hidden = {}
	self.hideSpot = {}
	self.isColosal = modeId == "colosal"
	self.isAsedio = modeId == "asedio"
	self.mapVote = {}
	self.chosenMap = nil
	self.voteDone = false
	self.knocked = {}
	self.looted = {}       -- quien ya saco su arma del baul de equipo (asedio)
	self.fort = nil        -- bunker del asedio (se destruye al terminar)
	self.fortChests = nil

	if modeId == "asedio" then
		self.isMulti = false
		self.diff = Config.Difficulties[Config.Asedio.baseDifficulty]
		self.name = Config.Asedio.name
		self.tag = Config.Asedio.tag
		self.color = Config.Asedio.color
		self.timeLimit = Config.Asedio.roundTime
		self.teamOf = {}
		self.teams = { attack = {}, defend = {} }
		self.teamScore = { attack = 0, defend = 0 }
		self.asedioRound = 1
		self.teamsReady = false
		-- Como el multijugador: entre todos votan el mapa y arranca.
		self.phase = "vote"
		self.phaseEnds = os.clock() + Config.Vote.multiTime
	elseif modeId == "multi" then
		self.isMulti = true
		self.diff = Config.Difficulties[Config.Multiplayer.baseDifficulty]
		self.name = Config.Multiplayer.name
		self.tag = Config.Multiplayer.tag
		self.color = Config.Multiplayer.color
		self.timeLimit = Config.Multiplayer.timeLimit
		-- La espera inicial es la votacion de mapa: votan todos y arranca.
		self.phase = "vote"
		self.phaseEnds = os.clock() + Config.Vote.multiTime
	else
		self.isMulti = false
		self.diff = Config.Difficulties[modeId] or Config.Difficulties.normal
		self.name = self.diff.name
		self.tag = self.diff.tag
		self.color = self.diff.color
		self.timeLimit = self.diff.round.timeLimit
		-- Modo solo: elige el mapa el jugador y arranca enseguida.
		self.phase = "vote"
		self.phaseEnds = os.clock() + Config.Vote.soloTime
	end

	return self
end

function Session:modeColorTable()
	return Util.colorToTable(self.color)
end

function Session:notify(player, text, color, duration)
	Net.get("Notify"):FireClient(player, text, Util.colorToTable(color or COLOR.info), duration or 4)
end

function Session:notifyAll(text, color, duration)
	for _, player in ipairs(self.players) do
		self:notify(player, text, color, duration)
	end
end

function Session:event(kind, data)
	Net.get("WorldEvent"):FireAllClients(kind, data)
end

-- ---------------- herramientas / trampas ----------------
-- Entrega las herramientas segun el modo (colosal solo el rastreador,
-- multijugador suma el rifle de pintura).
function Session:giveTools(player)
	if self.isAsedio then
		local side = self:asedioSide(player)
		local only = side == "defend" and Config.Asedio.toolsDefend or Config.Asedio.toolsAttack
		ToolService.give(player, only)
		-- Pistola de equipo: revolver con balas de sobra (estilo Counter)
		ToolService.giveLoot(player, "revolver", Config.Asedio.revolverUses or 40)
		return
	end
	local only = self.diff.tools
	if self.isMulti then
		only = Config.Multiplayer.tools
	end
	ToolService.give(player, only)
	if not only and not self.isColosal and not self.isMulti and #self.players >= 2 then
		ToolService.giveTool(player, "pintura")
	end
end

function Session:placeTrap(player, pos)
	if self.isColosal then
		return
	end

	local cfg = Config.Trampa
	local mine = {}
	for _, trap in ipairs(self.traps) do
		if trap.owner == player then
			table.insert(mine, trap)
		end
	end

	if #mine >= cfg.maxActive then
		self:removeTrap(mine[1])
	end

	local trap = {
		model = Actions.makeTrapModel(pos),
		pos = Vector3.new(pos.X, pos.Y, pos.Z),
		owner = player,
		armed = true,
	}
	table.insert(self.traps, trap)
end

function Session:removeTrap(trap)
	for index, other in ipairs(self.traps) do
		if other == trap then
			table.remove(self.traps, index)
			break
		end
	end
	trap.armed = false
	if trap.model then
		trap.model:Destroy()
		trap.model = nil
	end
end

function Session:removeTrapsOf(player)
	for index = #self.traps, 1, -1 do
		local trap = self.traps[index]
		if trap.owner == player then
			self:removeTrap(trap)
		end
	end
end

function Session:clearTraps()
	for _, trap in ipairs(self.traps) do
		trap.armed = false
		if trap.model then
			trap.model:Destroy()
			trap.model = nil
		end
	end
	self.traps = {}
end

-- ---------------- kiwi gigante ----------------
function Session:giantCatch(player)
	if not player or self.phase ~= "playing" or not self.stats[player] then
		return
	end

	self.eaten = self.eaten or {}
	if self.eaten[player] then
		return
	end
	self.eaten[player] = true

	local name = player.DisplayName ~= "" and player.DisplayName or player.Name
	self:notifyAll(string.format(Config.Text.GiantEaten, name), COLOR.bad, 5)
	self:notify(player, Config.Text.DeathSubtitle, COLOR.bad, 4)
	self:event("giantcatch", { pos = self.kiwi and self.kiwi:getPosition(), userId = player.UserId })

	-- Queda "siendo comido" dos segundos (congelado) antes de volver al lobby
	setFrozen(player, true)

	task.delay(Config.Round.EatHold, function()
		self.eaten[player] = nil
		if self.stats[player] then
			setFrozen(player, false)
			self:removePlayer(player, true)
			-- De vuelta al lobby con el menu a la vista: asi elige otro modo facil
			Net.get("SessionUpdate"):FireClient(player, { active = false })
			Net.get("Notify"):FireClient(player, Config.Text.EatenMenu, Util.colorToTable(COLOR.info), 5)
		end
	end)
end

function Session:trapCatch(bait)
	if not bait then
		return
	end

	local owner = bait.owner
	self:removeTrap(bait)

	if not owner or not self.stats[owner] then
		self:notifyAll(Config.Text.TrapEaten, COLOR.info)
		return
	end

	local name = owner.DisplayName ~= "" and owner.DisplayName or owner.Name
	self:notifyAll(string.format(Config.Text.TrapStuck, name, Config.Trampa.holdTime), COLOR.good)
	self:event("trapcatch", { pos = bait.pos })

	if self.kiwi and not self.kiwi.defeated then
		self.kiwi:trapHold(Config.Trampa.holdTime)
	end
end

-- ---------------- daño entre cazadores ----------------
-- Las armas de baul hieren a los jugadores. Al kiwi SOLO lo relentizan.
-- sourceLabel: cuando el daño no viene de un cazador (auto, tren, kiwi...)
-- se usa ese texto en lugar del mensaje de "te dio con X".
function Session:damagePlayer(victim, attacker, weaponName, amount, pos, sourceLabel)
	if not self.stats[victim] or self.phase ~= "playing" then
		return
	end
	if self.knocked[victim] then
		return
	end

	-- Asedio: no hay fuego amigo entre companeros de equipo
	if self.isAsedio and attacker and attacker ~= victim then
		local mine = self.teamOf[attacker]
		local theirs = self.teamOf[victim]
		if mine and theirs and mine == theirs then
			self:notify(attacker, "¡Es de tu equipo!", COLOR.warn, 3)
			return
		end
	end

	local data = self.stats[victim]
	amount = math.max(1, math.floor(amount + 0.5))
	data.hp = math.max(0, (data.hp or Config.Player.maxHealth) - amount)
	data.lastHurt = os.clock()

	local msg
	if sourceLabel then
		msg = string.format(Config.Text.HurtGeneric, sourceLabel, amount)
	else
		local attackerName = "el mapa"
		if attacker and attacker ~= victim then
			attackerName = attacker.DisplayName ~= "" and attacker.DisplayName or attacker.Name
		end
		msg = string.format(Config.Text.HurtMsg, attackerName, weaponName, amount)
	end
	self:notify(victim, msg, COLOR.bad, 3)
	self:event("hurt", { pos = pos, userId = victim.UserId, amount = amount })
	self:sendUpdate(victim)

	if data.hp <= 0 then
		self:knockout(victim, attacker)
	end
end

-- Dardo tranquilizante: deja inmovil al cazador unos segundos. El estado
-- viaja como atributo "Dormido" en el Humanoid: asi el gobernador de
-- velocidad (cliente y servidor) lo respeta y no puede esquivarlo.
function Session:stun(victim, seconds, attacker)
	if not self.stats[victim] or self.knocked[victim] then
		return false
	end
	local character = victim.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if not humanoid then
		return false
	end

	seconds = seconds or (Config.Tranq and Config.Tranq.stunTime) or 3
	humanoid:SetAttribute("Dormido", true)
	setFrozen(victim, true)

	task.delay(seconds, function()
		if humanoid.Parent then
			humanoid:SetAttribute("Dormido", false)
			if not self.knocked[victim] then
				setFrozen(victim, false)
			end
		end
	end)

	local vname = victim.DisplayName ~= "" and victim.DisplayName or victim.Name
	if attacker and attacker ~= victim then
		local aname = attacker.DisplayName ~= "" and attacker.DisplayName or attacker.Name
		self:notifyAll(string.format(Config.Text.TranqShout, aname, vname), Color3.fromRGB(160, 230, 170), 3)
	else
		self:notifyAll(string.format(Config.Text.TranqShout, "El dardo", vname), Color3.fromRGB(160, 230, 170), 3)
	end
	return true
end

function Session:knockout(victim, attacker)
	if self.knocked[victim] or not self.stats[victim] then
		return
	end
	self.knocked[victim] = true

	local vname = victim.DisplayName ~= "" and victim.DisplayName or victim.Name
	local aname = "la reserva"
	if attacker and attacker ~= victim then
		aname = attacker.DisplayName ~= "" and attacker.DisplayName or attacker.Name
	end
	self:notifyAll(string.format(Config.Text.KoedAll, aname, vname), COLOR.warn, 5)
	self:event("ko", { userId = victim.UserId })
	setFrozen(victim, true)

	-- Asedio: los noqueados vuelven a su spawn despues de unos segundos
	if self.isAsedio then
		self:notify(victim, string.format(Config.Text.AsedioRespawnWait, Config.Asedio.respawn), COLOR.warn, Config.Asedio.respawn)
		task.delay(Config.Asedio.respawn, function()
			self.knocked[victim] = nil
			if self.stats[victim] and not self.finished and self.phase ~= "ended" then
				self:asedioRespawn(victim)
			end
		end)
		return
	end

	task.delay(Config.Round.KoHold, function()
		self.knocked[victim] = nil
		if self.stats[victim] then
			setFrozen(victim, false)
			self:removePlayer(victim, true)
			-- Igual que cuando te come el kiwi: al lobby con el menu listo
			Net.get("SessionUpdate"):FireClient(victim, { active = false })
			Net.get("Notify"):FireClient(victim, Config.Text.KoMenu, Util.colorToTable(COLOR.info), 5)
		end
	end)
end

function Session:stepHealth(dt)
	local max = Config.Player.maxHealth
	local now = os.clock()
	for _, player in ipairs(self.players) do
		local data = self.stats[player]
		if data and data.hp and data.hp < max and now - (data.lastHurt or 0) >= Config.Player.regenDelay then
			data.hp = math.min(max, data.hp + Config.Player.regen * dt)
		end
	end
end

-- ---------------- asedio (5 vs 5) ----------------
-- Cazadores (entran por el kiwi) y Defensores (lo cuidan en su casa).
local teamAttackCache, teamDefendCache

local function ensureTeams()
	local Teams = game:GetService("Teams")
	if teamAttackCache and teamAttackCache.Parent then
		return
	end
	teamAttackCache = Teams:FindFirstChild(Config.Asedio.teamAttack) or Instance.new("Team")
	teamAttackCache.Name = Config.Asedio.teamAttack
	teamAttackCache.TeamColor = BrickColor.new(Config.Asedio.colorAttack)
	teamAttackCache.AutoAssignable = false
	teamAttackCache.Parent = Teams

	teamDefendCache = Teams:FindFirstChild(Config.Asedio.teamDefend) or Instance.new("Team")
	teamDefendCache.Name = Config.Asedio.teamDefend
	teamDefendCache.TeamColor = BrickColor.new(Config.Asedio.colorDefend)
	teamDefendCache.AutoAssignable = false
	teamDefendCache.Parent = Teams
end

function Session:asedioSide(player)
	return self.teamOf[player] or "attack"
end

-- Un jugador que entra a mitad de partida se suma al equipo con menos gente
function Session:asedioAddToTeam(player)
	if self.teamOf[player] then
		return
	end
	local side = #self.teams.attack <= #self.teams.defend and "attack" or "defend"
	self.teamOf[player] = side
	table.insert(self.teams[side], player)
	ensureTeams()
	player.Neutral = false
	player.Team = side == "attack" and teamAttackCache or teamDefendCache
	local text = side == "attack" and Config.Text.AsedioTeamAttack or Config.Text.AsedioTeamDefend
	self:notify(player, text, side == "attack" and Config.Asedio.colorAttack or Config.Asedio.colorDefend, 8)
end

-- Reparte los equipos al azar, mitad y mitad, al arrancar la partida
function Session:assignTeams()
	if not self.isAsedio then
		return
	end
	ensureTeams()
	local list = {}
	for _, player in ipairs(self.players) do
		table.insert(list, player)
	end
	for i = #list, 2, -1 do
		local j = self.rng:NextInteger(1, i)
		list[i], list[j] = list[j], list[i]
	end
	self.teamOf = {}
	self.teams = { attack = {}, defend = {} }
	local counts = { attack = 0, defend = 0 }
	for _, player in ipairs(list) do
		local side = counts.attack <= counts.defend and "attack" or "defend"
		counts[side] = counts[side] + 1
		self.teamOf[player] = side
		table.insert(self.teams[side], player)
		player.Neutral = false
		player.Team = side == "attack" and teamAttackCache or teamDefendCache
	end
	self.teamsReady = true
	for _, player in ipairs(list) do
		local side = self.teamOf[player]
		local text = side == "attack" and Config.Text.AsedioTeamAttack or Config.Text.AsedioTeamDefend
		self:notify(player, text, side == "attack" and Config.Asedio.colorAttack or Config.Asedio.colorDefend, 8)
	end
end

-- El kiwi del asedio no come cazadores: da un picotazo y los tira lejos
function Session:asedioPounce(victim, pos)
	if not victim or not self.stats[victim] or self.phase ~= "playing" then
		return
	end
	local root = getRoot(victim)
	if root and pos then
		local away = root.Position - pos
		away = Vector3.new(away.X, 0, away.Z)
		if away.Magnitude < 0.5 then
			away = Vector3.new(0, 0, 1)
		end
		away = away.Unit * 42
		root.AssemblyLinearVelocity = Vector3.new(away.X, 18, away.Z)
	end
	self:event("peck", { pos = pos, userId = victim.UserId })
	self:damagePlayer(victim, nil, "picotazo", Config.KiwiPeck.damage, pos, Config.Text.AsedioPounce)
end

-- Vuelve al combate al noqueado (spawn de su equipo, vida llena y armas)
function Session:asedioRespawn(player)
	if not self.arena or not self.stats[player] then
		return
	end
	local data = self.stats[player]
	data.hp = Config.Player.maxHealth
	self:teleportToArena(player)
	self:giveTools(player)
	setFrozen(player, false)
	self:notify(player, Config.Text.AsedioBack, COLOR.good, 4)
	self:sendUpdate(player)
end

-- Limpia la ronda (kiwi, proyectiles, vida) antes de la siguiente
function Session:asedioReset()
	if self.kiwi then
		self.kiwi:destroy()
		self.kiwi = nil
	end
	for _, dart in ipairs(self.projectiles) do
		dart.part:Destroy()
	end
	self.projectiles = {}
	self:clearTraps()
	Actions.clearPickups(self)
	for _, player in ipairs(self.players) do
		if self.hideSpot[player] then
			self:exitSpot(player, true)
		end
		local data = self.stats[player]
		if data then
			data.hp = Config.Player.maxHealth
		end
		self.knocked[player] = nil
	end
end

-- Punto para un equipo: si llega a las rondas necesarias, se termina
function Session:asedioScore(side, reason)
	if not self.isAsedio or self.phase ~= "playing" then
		return
	end
	local score = self.teamScore
	score[side] = (score[side] or 0) + 1
	local attackName = Config.Asedio.teamAttack
	local defendName = Config.Asedio.teamDefend

	if reason == "capture" then
		self:notifyAll(string.format(Config.Text.AsedioCapture, attackName), Config.Asedio.colorAttack, 6)
	else
		self:notifyAll(string.format(Config.Text.AsedioTimeout, defendName), Config.Asedio.colorDefend, 6)
	end
	self:notifyAll(string.format("Marcador: %s %d - %d %s", attackName, score.attack, score.defend, defendName), COLOR.info, 6)

	if score.attack >= Config.Asedio.roundsToWin or score.defend >= Config.Asedio.roundsToWin then
		self.asedioWinner = score.attack >= Config.Asedio.roundsToWin and "attack" or "defend"
		local winnerName = self.asedioWinner == "attack" and attackName or defendName
		self:notifyAll(string.format(Config.Text.AsedioMatch, winnerName), COLOR.good, 8)
		self:endRound(nil, "teamwin")
		return
	end

	-- Siguiente ronda: descanso corto y vuelta a empezar en la casa
	self.asedioRound = (self.asedioRound or 1) + 1
	self:asedioReset()
	self:startCountdown()
	self.phaseEnds = os.clock() + Config.Asedio.breakTime
	self:notifyAll(string.format(Config.Text.AsedioNext, self.asedioRound), COLOR.info, Config.Asedio.breakTime)
	self:sendUpdates(true)
end

-- ---------------- trafico de la ciudad ----------------
-- Autos, colectivo y tren (solo en el mapa Ciudad). Se mueven por caminos
-- fijos y atropellan a los cazadores: mitad de la vida y empujon.
local function vehiclePose(veh, s)
	local pts, cum = veh.pts, veh.cum
	for i = 1, #pts - 1 do
		if s <= cum[i + 1] or i == #pts - 1 then
			local segLen = math.max(cum[i + 1] - cum[i], 0.001)
			local t = math.clamp((s - cum[i]) / segLen, 0, 1)
			local pos = pts[i]:Lerp(pts[i + 1], t)
			local dir = (pts[i + 1] - pts[i]).Unit
			if veh.dir < 0 then
				dir = -dir
			end
			return pos, dir
		end
	end
	return pts[1], Vector3.new(0, 0, 1)
end

local function placeVehicle(veh)
	-- Vehiculo destrozado por un cohete: no se mueve hasta repararse
	if veh.model and veh.model:GetAttribute("KiwiRoto") then
		return
	end
	local s = veh.dist
	if veh.dir < 0 then
		s = veh.total - s
	end
	local pos, dir = vehiclePose(veh, math.clamp(s, 0, veh.total))
	pos = Vector3.new(pos.X, veh.baseY or pos.Y, pos.Z)
	local cf = CFrame.lookAt(pos, pos + dir)
	veh.model:PivotTo(cf)
	veh.pose = cf
end

function Session:resetTraffic()
	local arena = self.arena
	if not arena or not arena.traffic then
		return
	end
	for _, veh in ipairs(arena.traffic) do
		veh.dist = veh.startDist or 0
		veh.dir = 1
		veh.waitUntil = 0
		veh.lastHit = {}
		placeVehicle(veh)
	end
end

function Session:stepTraffic(dt)
	local arena = self.arena
	if not arena or not arena.traffic or #arena.traffic == 0 then
		return
	end

	local now = os.clock()

	-- Semaforos: ciclo verde -> amarillo -> rojo (decorativo)
	if arena.semaphores then
		local phase = now % 11
		local active = "green"
		if phase >= 4.5 and phase < 6 then
			active = "yellow"
		elseif phase >= 6 then
			active = "red"
		end
		for _, sem in ipairs(arena.semaphores) do
			for name, part in pairs(sem) do
				local on = name == active
				part.Material = on and Enum.Material.Neon or Enum.Material.SmoothPlastic
				part.Transparency = on and 0 or 0.55
			end
		end
	end

	for _, veh in ipairs(arena.traffic) do
		local roto = veh.model and veh.model:GetAttribute("KiwiRoto")
		if not roto and (not veh.waitUntil or now >= veh.waitUntil) then
			veh.dist = veh.dist + veh.speed * dt
			if veh.dist >= veh.total then
				if veh.shuttle then
					veh.dist = 0
					veh.dir = -veh.dir
					veh.waitUntil = now + (veh.wait or 4)
				else
					veh.dist = veh.dist - veh.total
				end
			end
		end
		placeVehicle(veh)
		veh.lastHit = veh.lastHit or {}

		-- Atropello: si un cazador queda dentro del vehiculo pierde la mitad
		-- de la vida y sale volando.
		for _, player in ipairs(self.players) do
			local data = self.stats[player]
			local root = getRoot(player)
			if data and root and not self.knocked[player]
				and not (veh.model and veh.model:GetAttribute("KiwiRoto")) then
				if now - (veh.lastHit[player] or 0) >= Config.City.hitCooldown then
					local localPos = veh.pose:PointToObjectSpace(root.Position)
					if math.abs(localPos.X) <= veh.halfW + 2.2
						and math.abs(localPos.Z) <= veh.halfL + 2.2
						and math.abs(localPos.Y) <= 7 then
						veh.lastHit[player] = now
						local away = root.Position - veh.pose.Position
						away = Vector3.new(away.X, 0, away.Z)
						if away.Magnitude < 0.5 then
							away = veh.pose.LookVector
						end
						away = away.Unit * 62
						root.AssemblyLinearVelocity = Vector3.new(away.X, 24, away.Z)
						self:damagePlayer(player, nil, "atropello", Config.City.damage,
							veh.pose.Position, veh.label or "Te atropellaron")
					end
				end
			end
		end
	end
end

-- ---------------- jugadores ----------------
function Session:isFull()
	if self.isAsedio then
		return #self.players >= Config.Asedio.maxPlayers
	end
	if not self.isMulti then
		return #self.players >= 1
	end
	return #self.players >= Config.Multiplayer.maxPlayers
end

function Session:addPlayer(player)
	if self.stats[player] then
		return
	end

	self.stats[player] = { caught = 0, hp = Config.Player.maxHealth }
	table.insert(self.players, player)
	playerSession[player] = self
	ToolService.reset(player)
	if self.isAsedio and self.teamsReady then
		self:asedioAddToTeam(player)
	end

	if self.phase == "vote" then
		if self.voteDone then
			self:notify(player, "Entraste a la partida. Está por comenzar...", COLOR.good, 5)
		else
			self:notify(player, "Entraste a la partida. Vota el mapa para arrancar.", COLOR.good, 6)
		end
	elseif self.phase == "countdown" then
		local seconds = math.floor(self.phaseEnds - os.clock())
		self:notify(player, string.format("Entraste a la partida. Comienza en %d s", math.max(0, seconds)), COLOR.good)
		self:teleportToArena(player)
		self:giveTools(player)
	elseif self.phase ~= "ended" then
		self:teleportToArena(player)
		self:giveTools(player)
		if not self.isColosal then
			for _, other in ipairs(self.players) do
				if other ~= player then
					ToolService.giveTool(other, "pintura")
					self:notify(other, Config.Text.PvpRifleOn, Config.Tools.pintura.color, 6)
				end
			end
		end
		self:notify(player, "¡Te uniste a una partida en curso!", COLOR.warn)
	end

	self:sendUpdate(player)
end

function Session:removePlayer(player, silent)
	if not self.stats[player] then
		return
	end

	if self.hideSpot[player] then
		self:exitSpot(player, true)
	end

	self.stats[player] = nil
	if self.isAsedio and self.teamOf and self.teamOf[player] then
		local side = self.teamOf[player]
		self.teamOf[player] = nil
		local list = self.teams and self.teams[side]
		if list then
			for index, other in ipairs(list) do
				if other == player then
					table.remove(list, index)
					break
				end
			end
		end
	end
	for index, other in ipairs(self.players) do
		if other == player then
			table.remove(self.players, index)
			break
		end
	end

	if playerSession[player] == self then
		playerSession[player] = nil
	end

	self:removeTrapsOf(player)
	ToolService.clear(player)
	GameManager.returnToLobby(player, not silent)

	if not self.isColosal and not self.isMulti then
		for _, other in ipairs(self.players) do
			if ToolService.takeTool(other, "pintura") then
				self:notify(other, Config.Text.PvpRifleOff, COLOR.info, 4)
			end
		end
	end

	-- Multijugador: si solo queda uno, es el ganador de la ronda
	if self.isMulti and self.phase == "playing" then
		if #self.players == 1 then
			local last = self.players[1]
			local lastName = last.DisplayName ~= "" and last.DisplayName or last.Name
			self:notifyAll(string.format(Config.Text.LastAlive, lastName), COLOR.good, 6)
			self:endRound(last, "last")
		elseif #self.players == 0 then
			self:endRound(nil, "timeout")
		end
	end

	-- Votacion: si se fue un jugador y ya votaron todos, arranca la partida
	if self.phase == "vote" and not self.voteDone and #self.players > 0 and self:allVoted() then
		self:pickVoteWinner()
	end
end

function Session:prunePlayers()
	for index = #self.players, 1, -1 do
		local player = self.players[index]
		if not self.stats[player] then
			table.remove(self.players, index)
		end
	end
end

-- ---------------- votacion de mapa ----------------
local function zoneById(id)
	for _, zone in ipairs(Config.Zones) do
		if zone.id == id then
			return zone
		end
	end
	return nil
end

function Session:allVoted()
	if #self.players == 0 then
		return false
	end
	for _, player in ipairs(self.players) do
		if not self.mapVote[player] then
			return false
		end
	end
	return true
end

function Session:castVote(player, mapId)
	if self.phase ~= "vote" or self.voteDone or not self.stats[player] then
		return
	end
	if mapId ~= "random" and not zoneById(mapId) then
		return
	end
	self.mapVote[player] = mapId
	self:sendUpdate(player)
	if self:allVoted() then
		self:pickVoteWinner()
	end
end

function Session:pickVoteWinner()
	if self.voteDone then
		return
	end
	self.voteDone = true

	local counts = {}
	local leader, leaderCount = nil, 0
	for _, player in ipairs(self.players) do
		local pick = self.mapVote[player]
		if pick then
			counts[pick] = (counts[pick] or 0) + 1
			if counts[pick] > leaderCount then
				leader, leaderCount = pick, counts[pick]
			end
		end
	end

	-- Empate: se decide al azar entre los mas votados
	if leader then
		local top = {}
		for id, count in pairs(counts) do
			if count == leaderCount then
				table.insert(top, id)
			end
		end
		leader = top[self.rng:NextInteger(1, #top)]
	end

	local zone = zoneById(leader)
	if not zone then
		zone = Config.Zones[self.rng:NextInteger(1, #Config.Zones)]
	end

	self.chosenMap = zone.id
	self.phaseEnds = os.clock() + Config.Vote.revealTime
	self:notifyAll(string.format(Config.Text.MapPickNotify, zone.name), COLOR.good, 4)
	self:sendUpdates(true)
end

-- ---------------- arenas ----------------
function Session:allocateArena(mapId)
	if self.arena then
		return true
	end
	local fallback
	for _, arena in ipairs(world.arenas) do
		if not arena.busy then
			if not fallback then
				fallback = arena
			end
			if not mapId or arena.mapId == mapId then
				arena.busy = true
				self.arena = arena
				return true
			end
		end
	end
	if fallback then
		fallback.busy = true
		self.arena = fallback
		return true
	end
	return false
end

-- Arma el bunker de los Defensores (solo asedio, una vez por partida)
function Session:buildFort()
	if self.fort or not self.arena or not self.arena.nest then
		return
	end
	local ok, fort = pcall(WorldBuilder.buildAsedioFort, self.arena)
	if not ok or not fort then
		warn("[Kiwi Cazador] no se pudo armar el bunker del asedio: " .. tostring(fort))
		return
	end
	self.fort = fort
	self.fortChests = fort.chests
	for side, chest in pairs(fort.chests) do
		chest.team = side
		chest.teamName = side == "attack" and Config.Asedio.teamAttack or Config.Asedio.teamDefend
		chest.prompt.Triggered:Connect(function(who)
			local session = playerSession[who]
			if session then
				session:openChest(who, chest)
			end
		end)
	end
end

function Session:spawnsFor(player)
	-- Asedio: cada equipo aparece alrededor de la casa del kiwi
	if self.isAsedio and self.arena and self.arena.nest then
		local nest = self.arena.nest.pos
		local side = self:asedioSide(player)
		local list = self.teams[side] or {}
		local index = 1
		for i, other in ipairs(list) do
			if other == player then
				index = i
				break
			end
		end
		local count = math.max(1, #list)
		local angle = (index - 1) / count * math.pi * 2
		local radius = 24
		if side == "attack" then
			radius = math.min(Config.Asedio.attackSpawn, (self.arena.halfSize or 150) - 34)
			angle = angle + 0.7
		end

		-- Busca suelo firme en ese angulo (avisa si el punto esta tapado)
		local function punto(radio)
			local p = nest + Vector3.new(math.cos(angle) * radio, 0, math.sin(angle) * radio)
			p = self.arena:clampToBounds(p)
			local params = RaycastParams.new()
			params.IgnoreWater = true
			local ray = workspace:Raycast(Vector3.new(p.X, nest.Y + 70, p.Z), Vector3.new(0, -220, 0), params)
			if ray then
				local dy = ray.Position.Y - nest.Y
				if dy >= -1 and dy <= 2.5 then
					return ray.Position, true
				end
			end
			return Vector3.new(p.X, self.arena.floorY or nest.Y, p.Z), false
		end

		local point, limpio = punto(radius)
		if side == "defend" and not limpio then
			-- El punto cayo sobre la casa de arriba: se corre hacia la muralla
			point = punto(math.min(30, (Config.Asedio.bunkerHalf or 34) - 4))
		end
		-- OJO: devuelve CFrame (lo usa character:PivotTo); antes daba Vector3
		return CFrame.lookAt(point + Vector3.new(0, 4, 0), Vector3.new(nest.X, point.Y + 4, nest.Z))
	end

	local index = 1
	for i, other in ipairs(self.players) do
		if other == player then
			index = i
			break
		end
	end
	local spawns = self.arena.spawns
	local spawn = spawns[((index - 1) % #spawns) + 1]
	return spawn + Vector3.new(0, 4, 0)
end

function Session:teleportToArena(player)
	if not self.arena then
		return
	end
	local character = player.Character
	if not character then
		return
	end
	local target = self:spawnsFor(player)
	if typeof(target) == "Vector3" then
		target = CFrame.new(target)
	end
	character:PivotTo(target)
	local root = getRoot(player)
	if root then
		root.AssemblyLinearVelocity = Vector3.new(0, 0, 0)
	end
end

function Session:returnAllToLobby()
	for _, player in ipairs(self.players) do
		GameManager.returnToLobby(player)
	end
end

-- ---------------- fases ----------------
function Session:startCountdown()
	if self.isAsedio and not self.teamsReady then
		self:assignTeams()
	end
	if self.isAsedio then
		self:buildFort()
	end
	self.phase = "countdown"
	self.phaseEnds = os.clock() + Config.Round.Countdown

	for _, player in ipairs(self.players) do
		self:teleportToArena(player)
		self:giveTools(player)
		setFrozen(player, true)
	end

	self:event("countdown", { pos = self.arena.spawns[1].Position, phase = self.phase })
	self:notifyAll(string.format("Partida %s en %s", self.name, self.arena.name), self.color, Config.Round.Countdown)
	self:sendUpdates(true)
end

function Session:startPlaying()
	self.phase = "playing"
	self.startedAt = os.clock()
	self.safeAttract = 0
	applyZoneLighting(self.arena)
	local enterList = self.arena and self.arena.enterList
	if enterList then
		for _, spot in ipairs(enterList) do
			spot.occupied = nil
			spot.sniffCooldownUntil = nil
		end
	end
	local chests = self.arena and self.arena.chests
	if chests then
		for _, chest in ipairs(chests) do
			chest.used = false
			chest.lid.CFrame = chest.lidClosed
			chest.light.Brightness = 1.4
			chest.prompt.Enabled = true
		end
	end
	-- Baules de equipo del asedio: se recargan para todos cada ronda
	self.looted = {}
	if self.fortChests then
		for _, chest in pairs(self.fortChests) do
			chest.lid.CFrame = chest.lidClosed
			chest.light.Brightness = 1.4
		end
	end
	local zone = self.arena and self.arena.safeZone
	if zone then
		zone.active = false
		if zone.ring then
			zone.ring.Color = Color3.fromRGB(90, 110, 130)
			zone.ring.Transparency = 0.4
		end
		if zone.beam then
			zone.beam.Transparency = 0.85
		end
		if zone.light then
			zone.light.Brightness = 0
		end
		if zone.label then
			zone.label.Text = "ZONA SEGURA (se activa mas tarde)"
			zone.label.TextColor3 = Color3.fromRGB(150, 200, 220)
		end
	end
	self:spawnKiwi()
	self:resetTraffic()
	self:sendUpdates(true)
	for _, player in ipairs(self.players) do
		setFrozen(player, false)
		if self.isAsedio then
			local side = self:asedioSide(player)
			self:notify(player, string.format(Config.Text.AsedioRound, self.asedioRound or 1,
				Config.Asedio.teamAttack, Config.Asedio.teamDefend,
				self.teamScore.attack or 0, self.teamScore.defend or 0),
				side == "attack" and Config.Asedio.colorAttack or Config.Asedio.colorDefend, 7)
		elseif self.isColosal or self.isMulti then
			self:notify(player, "¡Escóndete! El kiwi gigante ya salió a buscar.", COLOR.warn, 6)
		else
			self:notify(player, "¡A cazar al kiwi!", COLOR.good)
		end
	end
	if self.isAsedio and self.fort then
		self:notifyAll(Config.Text.AsedioChests, COLOR.info, 7)
	end
	self:event("start", { pos = self.arena.spawns[1].Position })
end

function Session:endRound(winner, reason)
	if self.phase == "ended" then
		return
	end

	self.phase = "ended"
	self.phaseEnds = os.clock() + Config.Round.EndScreen
	self.winner = winner
	self.reason = reason

	if self.kiwi then
		self.kiwi:destroy()
		self.kiwi = nil
	end
	for _, dart in ipairs(self.projectiles) do
		dart.part:Destroy()
	end
	self.projectiles = {}
	self:clearTraps()
	Actions.clearPickups(self)

	for _, player in ipairs(self.players) do
		if self.hideSpot[player] then
			self:exitSpot(player, true)
		end
		setFrozen(player, true)
		Net.get("SessionEnd"):FireClient(player, self:buildResult(player))
	end
end

function Session:buildResult(player)
	local data = self.stats[player] or { caught = 0 }
	local lines = {}
	local title, subtitle
	local won = false
	local coins = data.caught * self.diff.round.reward

	if self.isMulti then
		if self.reason == "last" and self.winner then
			local winnerName = self.winner.DisplayName ~= "" and self.winner.DisplayName or self.winner.Name
			title = "¡Ganó " .. winnerName .. "!"
			subtitle = "Último cazador en pie: el kiwi gigante se comió a los demás."
			won = (self.winner == player)
			if won then
				coins = coins + self.diff.round.winBonus
			end
		elseif self.winner then
			local winnerName = self.winner.DisplayName ~= "" and self.winner.DisplayName or self.winner.Name
			title = "Ganó " .. winnerName
			subtitle = "Ronda terminada."
			won = (self.winner == player)
			if won then
				coins = coins + self.diff.round.winBonus
			end
		else
			title = "Sobrevivieron los últimos"
			subtitle = "Se acabó el tiempo y el kiwi gigante no llegó a terminarlos."
			won = true
			coins = coins + self.diff.round.reward
		end
	elseif self.isAsedio then
		local side = self:asedioSide(player)
		local won = self.asedioWinner == side
		local attackName = Config.Asedio.teamAttack
		local defendName = Config.Asedio.teamDefend
		local score = self.teamScore or { attack = 0, defend = 0 }
		title = won and "¡Ganó tu equipo!" or "Perdiste la partida"
		subtitle = string.format("%s %d - %d %s", attackName, score.attack or 0, score.defend or 0, defendName)
		if won then
			coins = coins + (Config.Asedio.winBonus or 240)
		end
		table.insert(lines, string.format("Tu equipo: %s", side == "attack" and attackName or defendName))
		table.insert(lines, string.format("Capturas: %d", data.caught or 0))
	elseif self.isColosal then
		if self.reason == "safe" then
			title = "¡Llegaste al refugio!"
			subtitle = "Esquivaste al kiwi y entraste a la zona segura."
			won = true
			coins = coins + self.diff.round.reward + self.diff.round.winBonus
			table.insert(lines, string.format("Recompensa del refugio: %d monedas",
				self.diff.round.reward + self.diff.round.winBonus))
		elseif self.reason == "timeout" then
			title = "¡Sobreviviste!"
			subtitle = Config.Text.GiantSafe
			won = true
			coins = coins + self.diff.round.reward + self.diff.round.winBonus
			table.insert(lines, string.format("Recompensa por sobrevivir: %d monedas",
				self.diff.round.reward + self.diff.round.winBonus))
		else
			title = "El kiwi gigante te encontró"
			subtitle = "La próxima vez, escóndete mejor."
		end
	else
		local quota = self.diff.round.quota
		if self.reason == "quota" then
			title = "¡Cacería completada!"
			subtitle = string.format("Atrapaste %d de %d kiwis", data.caught, quota)
			won = true
			coins = coins + self.diff.round.winBonus
			local bonus = self:remainingSeconds()
			if bonus > 0 then
				coins = coins + math.floor(bonus * self.diff.round.timeBonus)
				table.insert(lines, string.format("Bono por tiempo: +%d monedas", math.floor(bonus * self.diff.round.timeBonus)))
			end
		else
			title = "Se escapó el kiwi"
			subtitle = string.format("Atrapaste %d de %d kiwis antes de que se acabara el tiempo", data.caught, quota)
		end
	end

	table.insert(lines, string.format("Kiwis atrapados: %d", data.caught))
	table.insert(lines, string.format("Monedas ganadas: %d", coins))

	local ranking = {}
	for _, other in ipairs(self.players) do
		local otherStats = self.stats[other]
		table.insert(ranking, {
			name = other.DisplayName ~= "" and other.DisplayName or other.Name,
			caught = otherStats and otherStats.caught or 0,
			isWinner = other == self.winner,
			isSelf = other == player,
		})
	end

	addCoins(player, coins)

	return {
		title = title,
		subtitle = subtitle,
		won = won,
		lines = lines,
		ranking = ranking,
		color = Util.colorToTable(won and COLOR.good or COLOR.bad),
		modeName = self.name,
		arenaName = self.arena and self.arena.name or "?",
	}
end

function Session:remainingSeconds()
	if self.phase == "playing" then
		return math.max(0, self.startedAt + self.timeLimit - os.clock())
	elseif self.phase == "vote" or self.phase == "countdown" or self.phase == "ended" then
		return math.max(0, self.phaseEnds - os.clock())
	end
	return 0
end

function Session:finish()
	if self.finished then
		return
	end
	self.finished = true
	applyLighting(Config.LightDefault)

	if self.kiwi then
		self.kiwi:destroy()
		self.kiwi = nil
	end
	for _, dart in ipairs(self.projectiles) do
		dart.part:Destroy()
	end
	self.projectiles = {}
	self:clearTraps()
	Actions.clearPickups(self)

	if self.fort then
		self.fort:Destroy()
		self.fort = nil
		self.fortChests = nil
	end

	if Config.Round.HubReturn then
		self:returnAllToLobby()
	end
	for _, player in ipairs(self.players) do
		if self.isAsedio then
			player.Team = nil
			player.Neutral = true
		end
		ToolService.clear(player)
		Net.get("SessionUpdate"):FireClient(player, { active = false })
		if playerSession[player] == self then
			playerSession[player] = nil
		end
	end

	if self.arena then
		self.arena.busy = false
		self.arena = nil
	end
end

-- ---------------- kiwi ----------------
function Session:spawnKiwi()
	if self.kiwi then
		self.kiwi:destroy()
		self.kiwi = nil
	end

	local cfg = self.diff.kiwi
	local opts
	if self.isAsedio then
		-- El kiwi vive en su casa: no se aleja del nido (modo 5 vs 5)
		opts = { brain = "hider" }
		local nest = self.arena and self.arena.nest
		if nest then
			opts.spawn = nest.pos
			opts.leash = { pos = nest.pos, radius = Config.Asedio.nestRadius }
		end
	elseif self.isColosal or self.isMulti then
		if self.isMulti then
			cfg = Config.Difficulties.colosal.kiwi
		end
		opts = { brain = "seeker", scale = cfg.scale or 4 }
	end

	self.kiwi = KiwiController.new(self.arena, cfg, self.rng, {
		onEvent = function(kind, data)
			self:onKiwiEvent(kind, data)
		end,
		onTouchCapture = function(kiwi, player)
			self:onKiwiTouch(kiwi, player)
		end,
	}, opts)
end

function Session:onKiwiEvent(kind, data)
	local pos = data and (data.pos or (data.spot and data.spot.hidePoint))
	if kind == "flush" then
		self:notifyAll(Config.Text.KiwiRunning, COLOR.warn)
		self:event("flush", { pos = pos })
	elseif kind == "sedate" then
		self:notifyAll(Config.Text.KiwiSleeping, COLOR.good)
		self:event("sedate", { pos = pos })
	elseif kind == "wake" then
		self:notifyAll(Config.Text.WakeUp, COLOR.bad)
		self:event("wake", { pos = pos })
	elseif kind == "tired" then
		self:notifyAll("¡El kiwi está agotado!", COLOR.info)
	elseif kind == "capture" then
		self:event("captured", { pos = pos })
	elseif kind == "trapcatch" then
		self:trapCatch(data and data.bait)
	elseif kind == "trapescape" then
		self:notifyAll(Config.Text.TrapEscaped, COLOR.warn)
		self:event("trapescape", { pos = pos })
	elseif kind == "slowend" then
		self:notifyAll(Config.Text.SlowEnd, COLOR.info)
	elseif kind == "hunt" then
		self:notifyAll("¡El kiwi gigante te escuchó! Corre.", COLOR.bad, 4)
		self:event("hunt", { pos = pos })
	elseif kind == "roar" then
		self:event("roar", { pos = pos })
	elseif kind == "chomp" then
		self:event("chomp", { pos = pos })
	elseif kind == "sniffstart" then
		self:event("sniffstart", { pos = pos, index = data and data.index })
		local victim = data and data.player
		if victim and self.stats[victim] then
			self:notify(victim, "¡El kiwi te está husmeando! Sal con E y corre", COLOR.bad, 4)
		end
	elseif kind == "sniff" then
		self:event("sniff", { pos = pos, index = data and data.index })
	elseif kind == "sniffmiss" then
		self:event("sniffmiss", { pos = pos, index = data and data.index })
	elseif kind == "sniffcatch" then
		local victim = data and data.player
		if victim and self.stats[victim] and self.hidden[victim] then
			self:exitSpot(victim, true)
			local name = victim.DisplayName ~= "" and victim.DisplayName or victim.Name
			self:notifyAll(string.format(Config.Text.SniffCaught, name), COLOR.bad, 5)
		end
		self:event("sniffcatch", { pos = pos, index = data and data.index })
		if victim and self.stats[victim] then
			if self.isAsedio then
				self:asedioPounce(victim, pos)
			else
				self:giantCatch(victim)
			end
		end
	elseif kind == "peck" then
		-- Kiwi acorralado: picotazo a quien lo tiene arrinconado
		local victim = data and data.player
		if victim and self.stats[victim] and self.phase == "playing" then
			local root = getRoot(victim)
			if root and pos then
				local away = root.Position - pos
				away = Vector3.new(away.X, 0, away.Z)
				if away.Magnitude < 0.5 then
					away = Vector3.new(0, 0, 1)
				end
				away = away.Unit * Config.KiwiPeck.knockback
				root.AssemblyLinearVelocity = Vector3.new(away.X, 16, away.Z)
			end
			self:event("peck", { pos = pos, userId = victim.UserId })
			self:damagePlayer(victim, nil, "picotazo", Config.KiwiPeck.damage, pos, Config.Text.PeckHit)
		end
	elseif kind == "catch" then
		local victim = data and data.player
		if self.isAsedio then
			self:asedioPounce(victim, pos)
		else
			self:giantCatch(victim)
		end
	end
end

function Session:onKiwiTouch(kiwi, player)
	if self.phase ~= "playing" or self.kiwi ~= kiwi then
		return
	end
	if not self.stats[player] then
		return
	end
	if kiwi.state == "trapped" then
		self:capture(player, "fruta")
	else
		self:capture(player, "manos")
	end
end

function Session:capture(player, method)
	if self.phase ~= "playing" or not self.kiwi or self.kiwi.defeated then
		return
	end
	local data = self.stats[player]
	if not data then
		return
	end

	-- Asedio: solo los Cazadores capturan; si toca un Defensor, no pasa nada
	if self.isAsedio then
		if self:asedioSide(player) ~= "attack" then
			self:notify(player, "¡Ese es tu kiwi! Cuídenlo de los Cazadores.", COLOR.warn, 4)
			return
		end
		self.kiwi:capture(player)
		data.caught = data.caught + 1
		addCaught(player, 1)
		addCoins(player, Config.Asedio.reward or 60)
		self:event("captured", { pos = self.kiwi and self.kiwi:getPosition() })
		self:asedioScore("attack", "capture")
		return
	end

	self.kiwi:capture(player)
	data.caught = data.caught + 1
	addCaught(player, 1)
	addCoins(player, self.diff.round.reward)

	local name = player.DisplayName ~= "" and player.DisplayName or player.Name
	if method == "manos" then
		self:notifyAll(name .. " atrapó al kiwi dormido!", COLOR.good)
	elseif method == "trampa" then
		self:notifyAll(string.format(Config.Text.TrapCaptured, name), COLOR.good)
	elseif method == "fruta" then
		self:notifyAll(name .. " aprovechó que estaba enganchado en la fruta!", COLOR.good)
	else
		self:notifyAll(name .. " atrapó al kiwi con la red!", COLOR.good)
	end
	self:event("captured", { pos = self.kiwi and self.kiwi:getPosition() })

	if self.isMulti then
		self:endRound(player, "captured")
		return
	end

	if data.caught >= self.diff.round.quota then
		self:endRound(player, "quota")
	else
		self.needRespawn = true
		self.respawnAt = os.clock() + Config.Round.KiwiRespawnDelay
		self:notify(player, string.format("Tienes %d de %d. El próximo kiwi ya casi aparece...", data.caught, self.diff.round.quota), COLOR.info)
	end
end

-- ---------------- escondites de jugador ----------------
function Session:enterSpot(player, index)
	if self.phase ~= "playing" then
		return
	end
	local arena = self.arena
	local spot = arena and arena.enterList and arena.enterList[index]
	if not spot or not spot.enter then
		return
	end

	local character = player.Character
	local root = getRoot(player)
	if not character or not root or self.hidden[player] then
		return
	end

	if spot.occupied and spot.occupied ~= player then
		self:notify(player, Config.Text.HideBusy, COLOR.warn, 3)
		return
	end

	if (root.Position - spot.enter.inside.Position).Magnitude > Config.Hide.enterRange then
		return
	end

	spot.occupied = player
	self.hidden[player] = true
	self.hideSpot[player] = index

	local prompt = spot.enter.prompt
	if prompt then
		prompt.ActionText = "Salir"
	end

	setFrozen(player, true)
	setBodyHidden(player, true)
	root.CFrame = spot.enter.inside
	root.AssemblyLinearVelocity = Vector3.zero
	if spot.enter.door and spot.enter.doorOpen then
		spot.enter.door.CFrame = spot.enter.doorOpen
	end

	local kiwi = self.kiwi
	if kiwi and kiwi.state == "sniff" and kiwi.sniffIndex == index then
		self:notify(player, "¡El kiwi ya estaba husmeando aquí! Aguanta o sal y corre", COLOR.bad, 4)
	end

	self:event("hidestart", { pos = spot.hidePoint, index = index })
	self:sendUpdate(player)
end

function Session:exitSpot(player, caught)
	local index = self.hideSpot[player]
	if not index then
		return
	end
	local arena = self.arena
	local spot = arena and arena.enterList and arena.enterList[index]

	self.hideSpot[player] = nil
	self.hidden[player] = nil
	if spot then
		spot.occupied = nil
		if spot.enter.door and spot.enter.doorClosed then
			spot.enter.door.CFrame = spot.enter.doorClosed
		end
		if spot.enter.wobble and spot.enter.wobbleCF then
			spot.enter.wobble.CFrame = spot.enter.wobbleCF
		end
		if spot.enter.prompt then
			spot.enter.prompt.ActionText = "Esconderse"
		end
	end

	setBodyHidden(player, false)
	local root = getRoot(player)
	if root and spot and spot.enter.exit then
		root.CFrame = spot.enter.exit
		root.AssemblyLinearVelocity = Vector3.zero
	end

	local kiwi = self.kiwi
	local sniffed = kiwi and kiwi.state == "sniff" and kiwi.sniffIndex == index
	if caught then
		setFrozen(player, true)
		return
	end

	setFrozen(player, false)
	self:event("hidestop", { index = index, pos = spot and spot.hidePoint })
	if sniffed then
		-- Salio justo mientras lo husmeaban: premio y el kiwi le sale
		-- al paso al instante (el "casi" clasico del escondite)
		addCoins(player, Config.Hide.escapeCoins)
		self:notify(player, string.format(Config.Text.HideEscape, Config.Hide.escapeCoins), COLOR.good, 4)
		kiwi:sniffMiss(root and root.Position or nil)
	end
	self:sendUpdate(player)
end

-- ---------------- baules de armas ----------------
-- Reparte un arma de baul (lo usan los baules comunes y los de equipo)
function Session:lootChest(player, chest)
	local weapons = Config.Loot.weapons
	local total = 0
	for _, entry in ipairs(weapons) do
		total = total + (entry.weight or 1)
	end

	-- Mas aleatorio: se evita repetir la ultima arma que saco ESE jugador
	-- (hasta 3 intentos), asi no toca siempre lo mismo.
	local stats = self.stats[player]
	local last = stats and stats.lastLoot
	local pick = weapons[1]
	for _ = 1, 3 do
		local roll = self.rng:NextInteger(1, math.max(total, 1))
		pick = weapons[1]
		for _, entry in ipairs(weapons) do
			roll = roll - (entry.weight or 1)
			if roll <= 0 then
				pick = entry
				break
			end
		end
		if pick.id ~= last then
			break
		end
	end
	if stats then
		stats.lastLoot = pick.id
	end

	-- Un arma de baul a la vez: la anterior se pierde
	for _, entry in ipairs(weapons) do
		ToolService.takeTool(player, entry.id)
	end
	ToolService.giveLoot(player, pick.id, pick.uses or Config.Loot.uses)

	-- Ademas del arma, cada baul suelta el pack de granadas
	ToolService.giveNadePack(player)

	local cfg = Config.Weapons[pick.id]
	self:notify(player, string.format(Config.Text.ChestLoot, cfg.name, pick.uses or Config.Loot.uses), cfg.color, 5)
	self:notify(player, Config.Text.ChestPack, Color3.fromRGB(188, 198, 210), 5)
	self:event("chestopen", { pos = chest.center })
	self:sendUpdate(player)
end

function Session:openChest(player, chest)
	if not chest then
		return
	end
	if self.phase ~= "playing" or self.hidden[player] then
		return
	end
	local root = getRoot(player)
	if not root or (root.Position - chest.center).Magnitude > Config.Loot.pickupRange + 2 then
		return
	end

	-- Baul de equipo (asedio): cada jugador saca UNA sola arma por ronda
	if chest.team then
		local side = self.teamOf[player] or "attack"
		if side ~= chest.team then
			self:notify(player, string.format(Config.Text.ChestTeamWrong, chest.teamName or chest.team), COLOR.warn, 4)
			return
		end
		if self.looted[player] then
			self:notify(player, Config.Text.ChestTeamDone, COLOR.warn, 4)
			return
		end
		self.looted[player] = true
		-- La tapa se abre y se vuelve a cerrar: el baul queda para el resto
		chest.lid.CFrame = chest.lidOpen
		task.delay(1.1, function()
			if chest.lid and chest.lid.Parent then
				chest.lid.CFrame = chest.lidClosed
			end
		end)
		self:lootChest(player, chest)
		return
	end

	if chest.used then
		return
	end
	chest.used = true
	chest.lid.CFrame = chest.lidOpen
	chest.light.Brightness = 0
	chest.prompt.Enabled = false
	self:lootChest(player, chest)
end

-- ---------------- bucle ----------------
function Session:buildPlayerList()
	local list = {}
	for _, player in ipairs(self.players) do
		local character = player.Character
		local root = character and character:FindFirstChild("HumanoidRootPart")
		local humanoid = character and character:FindFirstChildOfClass("Humanoid")
		if root and humanoid and humanoid.Health > 0 then
			local hidden = self.hidden[player] == true
			local indoor = false
			if not hidden and self.arena and self.arena.indoors then
				for _, room in ipairs(self.arena.indoors) do
					local rel = room.cf:PointToObjectSpace(root.Position)
					if math.abs(rel.X) <= room.size.X * 0.5
						and math.abs(rel.Z) <= room.size.Z * 0.5
						and rel.Y >= -2 and rel.Y <= room.size.Y + 3 then
						indoor = true
						break
					end
				end
			end
			local velocity = root.AssemblyLinearVelocity
			local speed = math.sqrt(velocity.X * velocity.X + velocity.Z * velocity.Z)
			local noise = math.clamp((speed - 6) / 14, 0, 1)
			if humanoid.FloorMaterial == Enum.Material.Air then
				noise = math.min(1, noise + 0.35)
			end
			if indoor then
				noise = noise * Config.Hide.smellIndoor
			end
			table.insert(list, {
				player = player,
				pos = root.Position,
				noise = noise,
				speed = speed,
				hidden = hidden,
				indoor = indoor,
			})
		end
	end
	return list
end

function Session:stepSafeZone(dt)
	local zone = self.arena and self.arena.safeZone
	if not zone then
		return
	end

	if not zone.active then
		local elapsed = os.clock() - (self.startedAt or os.clock())
		if elapsed >= Config.SafeZone.activateAfter then
			zone.active = true
			if zone.ring then
				zone.ring.Color = Color3.fromRGB(120, 255, 190)
				zone.ring.Transparency = 0.1
			end
			if zone.beam then
				zone.beam.Transparency = 0.35
			end
			if zone.light then
				zone.light.Brightness = 2.6
			end
			if zone.label then
				zone.label.Text = "¡ENTRA PARA GANAR!"
				zone.label.TextColor3 = Color3.fromRGB(150, 255, 200)
			end
			self.safeAttract = 0
			self:notifyAll(Config.Text.SafeActive, COLOR.good, 6)
			self:event("safeactive", { pos = zone.center })
		end
		return
	end

	local player = self.players[1]
	local root = player and getRoot(player)
	if not player or not root then
		return
	end

	-- Llego al refugio: gana al instante
	local offset = zone.center - root.Position
	offset = Vector3.new(offset.X, 0, offset.Z)
	if offset.Magnitude <= zone.radius then
		self:endRound(player, "safe")
		return
	end

	-- El kiwi le corta el paso: se planta entre el cazador y el refugio
	self.safeAttract = (self.safeAttract or 0) - dt
	if self.safeAttract <= 0 and self.kiwi and not self.kiwi.defeated then
		self.safeAttract = Config.SafeZone.attractEvery
		local blockPoint = root.Position
		if offset.Magnitude > 0.1 then
			blockPoint = root.Position + offset.Unit * math.min(offset.Magnitude * 0.5, 22)
		end
		self.kiwi:goHuntZone(blockPoint)
	end
end

function Session:step(dt)
	local now = os.clock()
	self:prunePlayers()

	if #self.players == 0 and self.phase ~= "ended" then
		self:finish()
		return
	end

	if self.phase == "vote" then
		if not self.voteDone then
			if self:allVoted() or now >= self.phaseEnds then
				self:pickVoteWinner()
			end
		elseif now >= self.phaseEnds then
			if self:allocateArena(self.chosenMap) then
				if self.chosenMap and self.arena.mapId ~= self.chosenMap then
					self:notifyAll(string.format(Config.Text.MapFallback, self.arena.name), COLOR.warn, 5)
				end
				self:startCountdown()
			else
				self.phaseEnds = now + 6
				self:notifyAll(Config.Text.NoArena, COLOR.warn, 5)
			end
		end
	elseif self.phase == "countdown" then
		if now >= self.phaseEnds then
			self:startPlaying()
		end
	elseif self.phase == "playing" then
		if self.timeLimit and now >= self.startedAt + self.timeLimit then
			if self.isAsedio then
				-- Se acabó el tiempo: punto para los Defensores
				self:asedioScore("defend", "timeout")
			else
				self:notifyAll("¡Se acabó el tiempo!", COLOR.bad)
				self:endRound(nil, "timeout")
			end
		else
			self:stepHealth(dt)
			self:stepTraffic(dt)
			if self.isColosal then
				self:stepSafeZone(dt)
			end
			if self.phase == "playing" then
				if self.needRespawn and now >= self.respawnAt then
					self.needRespawn = false
					self:spawnKiwi()
				end
				if self.kiwi then
					self.kiwi:step(dt, self:buildPlayerList(), self.traps)
				end
				Actions.stepProjectiles(self, dt)
			end
		end
	elseif self.phase == "ended" then
		if now >= self.phaseEnds then
			self:finish()
		end
	end

	self.updateTimer = self.updateTimer + dt
	if self.updateTimer >= Config.Round.UpdateInterval then
		self:sendUpdates()
	end
end

-- ---------------- estado hacia el cliente ----------------
function Session:sendUpdate(player)
	if not self.stats[player] then
		return
	end

	local data = self.stats[player]
	local quota = self.isMulti and 1 or self.diff.round.quota
	local objective
	local progressText
	if self.phase == "vote" then
		if self.isMulti or self.isAsedio then
			objective = "¡Voten el mapa de la partida!"
		else
			objective = "¡Elige el mapa de la partida!"
		end
		progressText = self.voteDone and "¡Arrancando!" or string.format("Votación: %d s",
			math.max(0, math.ceil(self.phaseEnds - os.clock())))
	elseif self.isMulti then
		objective = "Sobrevive al kiwi gigante: gana el último en pie"
		local kiwi = self.kiwi
		local root = getRoot(player)
		if kiwi and not kiwi.defeated and root and (kiwi:getPosition() - root.Position).Magnitude < 70 then
			progressText = "¡El kiwi gigante está cerca de ti!"
		else
			progressText = string.format("Cazadores vivos: %d", #self.players)
		end
	elseif self.isAsedio then
		local side = self:asedioSide(player)
		local kiwi = self.kiwi
		local root = getRoot(player)
		local near = kiwi and not kiwi.defeated and root
			and (kiwi:getPosition() - root.Position).Magnitude < 40
		if side == "attack" then
			objective = "Entra a la casa del kiwi y atrápalo"
			progressText = near and "¡El kiwi está cerca!" or "Busca la casa del kiwi"
		else
			objective = "Cuida al kiwi de los Cazadores"
			progressText = near and "¡El kiwi está contigo! Cúbrelo" or "El kiwi está en su casa"
		end
	elseif self.isColosal then
		local zone = self.arena and self.arena.safeZone
		if zone and zone.active then
			objective = "¡Corre a la ZONA SEGURA!"
			local kiwi = self.kiwi
			local root = getRoot(player)
			if kiwi and not kiwi.defeated and root and (kiwi:getPosition() - root.Position).Magnitude < 45 then
				progressText = "¡El kiwi te corta el paso! Frénalo y esquívalo"
			else
				progressText = "Entra al círculo para ganar"
			end
		else
			objective = "Escóndete del kiwi gigante"
			local kiwi = self.kiwi
			local root = getRoot(player)
			if kiwi and not kiwi.defeated and root then
				local distance = (kiwi:getPosition() - root.Position).Magnitude
				if distance < 70 then
					progressText = "¡Está muy cerca de ti!"
				else
					progressText = string.format("Cazadores escondidos: %d", #self.players)
				end
			else
				progressText = "¡Corre y escóndete!"
			end
		end
	else
		objective = string.format("Atrapa %d kiwis", quota)
	end

	if self.hidden[player] then
		progressText = "Escondido: pulsa E para salir"
	end

	local voteCounts = nil
	if self.phase == "vote" then
		voteCounts = {}
		for _, other in ipairs(self.players) do
			local pick = self.mapVote[other]
			if pick then
				voteCounts[pick] = (voteCounts[pick] or 0) + 1
			end
		end
	end

	local ranking = {}
	for _, other in ipairs(self.players) do
		local otherStats = self.stats[other]
		table.insert(ranking, {
			name = other.DisplayName ~= "" and other.DisplayName or other.Name,
			caught = otherStats and otherStats.caught or 0,
			isSelf = other == player,
			team = self.isAsedio and self.teamOf[other] or nil,
		})
	end
	table.sort(ranking, function(a, b)
		if a.caught == b.caught then
			return a.name < b.name
		end
		return a.caught > b.caught
	end)

	Net.get("SessionUpdate"):FireClient(player, {
		active = true,
		modeId = self.modeId,
		modeName = self.name,
		modeTag = self.tag,
		modeColor = self:modeColorTable(),
		phase = self.phase,
		timeLeft = self:remainingSeconds(),
		objective = objective,
		caught = data.caught,
		quota = quota,
		kiwiState = self.diff.showKiwiState and self.kiwi and self.kiwi:getStateHint() or nil,
		arenaName = self.arena and self.arena.name or nil,
		players = ranking,
		playerCount = #self.players,
		isMulti = self.isMulti,
		isAsedio = self.isAsedio or nil,
		team = self.isAsedio and self:asedioSide(player) or nil,
		teamScore = self.isAsedio and { attack = self.teamScore.attack, defend = self.teamScore.defend } or nil,
		round = self.isAsedio and self.asedioRound or nil,
		roundsToWin = self.isAsedio and Config.Asedio.roundsToWin or nil,
		waiting = self.phase == "vote",
		vote = self.phase == "vote" and {
			done = self.voteDone or false,
			chosen = self.chosenMap,
			mine = self.mapVote[player],
			total = #self.players,
			left = math.max(0, math.ceil(self.phaseEnds - os.clock())),
			counts = voteCounts,
		} or nil,
		hp = math.floor(data.hp or Config.Player.maxHealth),
		maxHp = Config.Player.maxHealth,
		progressText = progressText,
		hidden = self.hidden[player] == true or nil,
		hideSpot = self.hideSpot[player] or nil,
		limitedTools = self.isAsedio
			and (self:asedioSide(player) == "defend" and Config.Asedio.toolsDefend or Config.Asedio.toolsAttack)
			or self.diff.tools,
		paint = self.isAsedio or (not self.isColosal and (self.isMulti or #self.players >= 2)),
	})
end

function Session:sendUpdates(forced)
	if forced then
		self.updateTimer = 0
	end
	for _, player in ipairs(self.players) do
		self:sendUpdate(player)
	end
end

-- ===============================================================
-- GAME MANAGER
-- ===============================================================
function GameManager.init()
	Net.init()
	world = WorldBuilder.build(Config)
	ToolService.build()
	Weather.start(world)

	workspace.Gravity = Config.World.Gravity

	GameManager.world = world

	Players.PlayerAdded:Connect(function(player)
		GameManager.setupPlayer(player)
	end)

	for _, player in ipairs(Players:GetPlayers()) do
		GameManager.setupPlayer(player)
	end

	Players.PlayerRemoving:Connect(function(player)
		local session = playerSession[player]
		if session then
			session:removePlayer(player, true)
		end
		playerSession[player] = nil
	end)

	Net.get("RequestJoin").OnServerEvent:Connect(function(player, modeId)
		GameManager.requestJoin(player, modeId)
	end)

	Net.get("RequestLeave").OnServerEvent:Connect(function(player)
		GameManager.requestLeave(player)
	end)

	Net.get("RequestState").OnServerEvent:Connect(function(player)
		local session = playerSession[player]
		if session then
			session:sendUpdate(player)
		else
			Net.get("SessionUpdate"):FireClient(player, { active = false })
		end
	end)

	Net.get("VoteMap").OnServerEvent:Connect(function(player, mapId)
		local session = playerSession[player]
		if session and type(mapId) == "string" then
			session:castVote(player, mapId)
		end
	end)

	Net.get("ToolAction").OnServerEvent:Connect(function(player, toolId, data)
		local session = playerSession[player]
		if not session or type(toolId) ~= "string" then
			return
		end
		-- Noqueado: no puede disparar ni usar herramientas hasta volver
		if session.knocked[player] then
			return
		end
		if toolId ~= "red" and toolId ~= "rifle" and toolId ~= "rastreador"
			and toolId ~= "trampa" and toolId ~= "pintura" and toolId ~= "relente"
			and Config.Weapons[toolId] == nil
			and (Config.Grenades == nil or Config.Grenades[toolId] == nil) then
			return
		end
		local ok, err = pcall(Actions.run, session, player, toolId, data)
		if not ok then
			warn("[Kiwi Cazador] error en herramienta: " .. tostring(err))
		end
	end)

	-- Escondites y baules: cada arena conecta los avisos de sus prompts
	for _, arena in ipairs(world.arenas) do
		for _, spot in ipairs(arena.enterList or {}) do
			local prompt = spot.enter and spot.enter.prompt
			if prompt then
				local spotIndex = spot.enterIndex
				prompt.Triggered:Connect(function(who)
					local session = playerSession[who]
					if not session then
						return
					end
					if session.hideSpot[who] == spotIndex then
						session:exitSpot(who)
					elseif not session.hidden[who] then
						session:enterSpot(who, spotIndex)
					end
				end)
			end
		end
		for _, chest in ipairs(arena.chests or {}) do
			chest.prompt.Triggered:Connect(function(who)
				local session = playerSession[who]
				if session then
					session:openChest(who, chest)
				end
			end)
		end
	end

	RunService.Heartbeat:Connect(function(dt)
		GameManager.step(dt)
	end)

	print("[Kiwi Cazador] iniciado con " .. #world.arenas .. " arenas")
end

function GameManager.setupPlayer(player)
	leaderstatsFor(player)

	local function onCharacter(character)
		local session = playerSession[player]
		task.wait(0.6)
		if session and playerSession[player] == session then
			if session.hideSpot[player] then
				session:exitSpot(player, true)
			end
			if session.phase == "playing" or session.phase == "countdown" then
				session:teleportToArena(player)
				session:giveTools(player)
				setFrozen(player, session.phase == "countdown")
			else
				GameManager.sendToLobbySpawn(player)
			end
			session:sendUpdate(player)
		else
			GameManager.sendToLobbySpawn(player)
		end
	end

	if player.Character then
		task.spawn(onCharacter, player.Character)
	end
	player.CharacterAdded:Connect(onCharacter)

	-- Estado inicial del menu
	Net.get("SessionUpdate"):FireClient(player, { active = false })
end

function GameManager.sendToLobbySpawn(player)
	local character = player.Character
	if not character then
		return
	end
	local spawn = world.lobby.spawn
	character:PivotTo(CFrame.new(spawn.Position + Vector3.new(0, 3, 0)))
	local root = character:FindFirstChild("HumanoidRootPart")
	if root then
		root.AssemblyLinearVelocity = Vector3.new(0, 0, 0)
	end
end

function GameManager.returnToLobby(player, keepInPlace)
	if player.Parent then
		ToolService.clear(player)
		if not keepInPlace then
			GameManager.sendToLobbySpawn(player)
		end
	end
end

function GameManager.requestJoin(player, modeId)
	local current = playerSession[player]
	if current then
		if current.phase == "ended" then
			current:removePlayer(player, true)
		else
			Net.get("Notify"):FireClient(player, Config.Text.AlreadyIn, Util.colorToTable(COLOR.warn), 4)
			return
		end
	end

	if modeId == "multi" then
		local session
		for _, candidate in ipairs(sessions) do
			if candidate.modeId == "multi" and not candidate.finished
				and candidate.phase ~= "ended" and not candidate:isFull() then
				session = candidate
				break
			end
		end
		if not session then
			session = Session.new("multi", Random.new())
			table.insert(sessions, session)
		end
		session:addPlayer(player)
		return
	end

	if modeId == "asedio" then
		local session
		for _, candidate in ipairs(sessions) do
			if candidate.modeId == "asedio" and not candidate.finished
				and candidate.phase ~= "ended" and not candidate:isFull() then
				session = candidate
				break
			end
		end
		if not session then
			session = Session.new("asedio", Random.new())
			table.insert(sessions, session)
		end
		session:addPlayer(player)
		return
	end

	if not Config.Difficulties[modeId] then
		return
	end

	local session = Session.new(modeId, Random.new())
	table.insert(sessions, session)
	session:addPlayer(player)
	session:sendUpdate(player)
end

function GameManager.requestLeave(player)
	local session = playerSession[player]
	if not session then
		return
	end
	session:removePlayer(player, true)
	Net.get("SessionUpdate"):FireClient(player, { active = false })
end

function GameManager.step(dt)
	dt = math.min(dt, 0.1)

	for index = #sessions, 1, -1 do
		local session = sessions[index]
		local ok, err = pcall(function()
			session:step(dt)
		end)
		if not ok then
			warn("[Kiwi Cazador] error en la sesion " .. tostring(session.id) .. ": " .. tostring(err))
		end
		if session.finished then
			table.remove(sessions, index)
		end
	end

	-- Rescate de jugadores que caen al vacio
	for _, player in ipairs(Players:GetPlayers()) do
		local root = getRoot(player)
		if root and root.Position.Y < Config.World.VoidY then
			local session = playerSession[player]
			if session and session.phase ~= "ended" then
				session:teleportToArena(player)
			else
				GameManager.sendToLobbySpawn(player)
			end
		end
	end
end

function GameManager.getSession(player)
	return playerSession[player]
end

return GameManager
