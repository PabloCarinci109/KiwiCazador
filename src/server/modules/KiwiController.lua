--[[
	KiwiController.lua  (servidor)
	El cerebro del kiwi: percibe jugadores, se esconde, huye, se cansa
	y se duerme con el tranquilizante.

	Maquina de estados:
		wander  -> camina tranquilo (a veces rumbo a un escondite)
		flee    -> corre asustado hacia un escondite lejano (gasta energia)
		tired   -> se cansa, camina lento y es facil de alcanzar
		hidden  -> adentro de un escondite, invisible
		sedated -> dormido por un dardo
		caught  -> capturado, fin de la historia
--]]

local Players = game:GetService("Players")

local KiwiModel = require(script.Parent.KiwiModel)

local Shared = require(script.Parent.Shared)
local Config = require(Shared.Config)

local KiwiController = {}
KiwiController.__index = KiwiController

local WHISKER_ANGLES = { 0, math.rad(38), math.rad(-38), math.rad(75), math.rad(-75) }

local function clamp(v, min, max)
	if v < min then
		return min
	elseif v > max then
		return max
	end
	return v
end

local function flat(v)
	return Vector3.new(v.X, 0, v.Z)
end

local function rotateFlat(dir, radians)
	local cos, sin = math.cos(radians), math.sin(radians)
	return Vector3.new(dir.X * cos - dir.Z * sin, 0, dir.X * sin + dir.Z * cos)
end

function KiwiController.new(arena, kiwiCfg, rng, callbacks, opts)
	local self = setmetatable({}, KiwiController)

	opts = opts or {}
	self.arena = arena
	self.cfg = kiwiCfg
	self.rng = rng or Random.new()
	self.callbacks = callbacks or {}
	self.brain = opts.brain or "hider"
	self.giant = self.brain == "seeker"
	self.leash = opts.leash
	-- Kiwi de corral (asedio): espera plantado en su casa, girando apenas
	-- para mirar a quien se arrima; no se pasea por el mapa.
	self.estatico = opts.estatico and true or false

	self.rig = KiwiModel.build(arena.folder, opts.scale)
	self.model = self.rig.model
	self.rideHeight = self.rig.rideHeight or KiwiModel.RideHeight

	self.pos = opts.spawn or arena.kiwiSpawn or arena.center
	-- Piso local: el corral del asedio esta sobre el piso de la casa
	self.baseY = opts.floorY or arena.floorY
	self.pos = Vector3.new(self.pos.X, self.baseY + self.rideHeight, self.pos.Z)
	self.facing = Vector3.new(0, 0, 1)
	self.lastGroundY = self.baseY
	self.animPhase = 0
	self.alert = 0
	self.stamina = kiwiCfg.stamina or 10
	self.state = "wander"
	self.stateTime = 0
	self.hideTimer = 0
	self.noHideTimer = 0
	self.sedateLeft = 0
	self.spotIndex = nil
	self.lastSpotIndex = nil
	self.goalSpot = nil
	self.goalPos = self.pos
	self.threat = nil
	self.threatDist = math.huge
	self.defeated = false
	self.travelTime = 0
	self.playersInArena = {}
	self.goalBait = nil
	self.baitTimer = 0
	self.peckCooldown = 0
	self.peckAnim = 0
	self.trapTimer = 0
	self.trapScare = 0
	self.slowLeft = 0
	self.slowFactor = 1
	self.searchQueue = nil
	self.biteIndex = 0
	self.huntUntil = 0
	self.roarAt = 0
	self.sniffIndex = nil
	self.sniffUntil = 0
	self.sniffStep = 0

	self.moveParams = RaycastParams.new()
	self.moveParams.FilterType = Enum.RaycastFilterType.Include
	self.moveParams.FilterDescendantsInstances = { arena.ground, arena.propsFolder }
	self.moveParams.IgnoreWater = true

	-- Cartelito de "Z z z" cuando esta dormido
	local billboard = Instance.new("BillboardGui")
	billboard.Name = "Dormido"
	billboard.Size = UDim2.fromScale(6, 3)
	billboard.StudsOffsetWorldSpace = Vector3.new(0, 2.6 * (opts.scale or 1), 0)
	billboard.AlwaysOnTop = false
	billboard.Enabled = false
	billboard.Parent = self.rig.body

	local label = Instance.new("TextLabel")
	label.Size = UDim2.fromScale(1, 1)
	label.BackgroundTransparency = 1
	label.Font = Enum.Font.GothamBlack
	label.TextScaled = true
	label.TextColor3 = Color3.fromRGB(235, 240, 255)
	label.TextStrokeTransparency = 0.2
	label.Text = "z Z z"
	label.Parent = billboard
	self.sleepGui = billboard

	self.touchConn = self.rig.body.Touched:Connect(function(hit)
		if self.state ~= "sedated" or self.defeated then
			return
		end
		local character = hit and hit:FindFirstAncestorOfClass("Model")
		local player = character and Players:GetPlayerFromCharacter(character)
		if player and self.callbacks.onTouchCapture then
			self.callbacks.onTouchCapture(self, player)
		end
	end)

	if self.brain == "seeker" then
		self:applyGiantLook()
		self.rig:setVisible(true)
		self.state = "patrol"
		self.goalPos = self:randomPointInArena()
	else
		self:goWander()
	end
	return self
end

-- ===============================================================
-- Consultas
-- ===============================================================
function KiwiController:isHidden()
	return self.state == "hidden"
end

function KiwiController:isSedated()
	return self.state == "sedated"
end

function KiwiController:getPosition()
	return self.pos
end

function KiwiController:getStateHint()
	if self.brain == "seeker" then
		if self.slowLeft > 0 then
			return "¡ralentizado!"
		elseif self.state == "eat" then
			return "comiéndose a alguien"
		elseif self.state == "sniff" then
			return "husmeando un escondite"
		elseif self.state == "hunt" then
			return "te anda buscando"
		elseif self.state == "busy" then
			return "satisfecho"
		end
		return "paseando"
	end
	if self.defeated then
		return "capturado"
	elseif self.state == "hidden" then
		return "escondido"
	elseif self.state == "sedated" then
		return "dormido"
	elseif self.state == "flee" then
		return "huyendo"
	elseif self.state == "tired" then
		return "cansado"
	elseif self.state == "trapped" then
		return "¡atrapado en una fruta!"
	end
	return "al acecho"
end

function KiwiController:setState(state)
	if self.state == state then
		return
	end
	self.state = state
	self.stateTime = 0
	if self.callbacks.onStateChange then
		self.callbacks.onStateChange(self, state)
	end
end

function KiwiController:emit(kind, data)
	if self.callbacks.onEvent then
		self.callbacks.onEvent(kind, data or {})
	end
end

-- ===============================================================
-- Percepcion
-- ===============================================================
function KiwiController:sense(dt, players)
	local cfg = self.cfg
	local threat, threatDist = nil, math.huge

	for _, p in ipairs(players) do
		local d = (p.pos - self.pos).Magnitude
		if d < threatDist then
			threat, threatDist = p, d
		end
	end
	self.threat = threat
	self.threatDist = threatDist

	local stimulus = 0
	if threat then
		local dist = threatDist
		local radius = cfg.detectionRadius
		local visual = 0

		if dist <= radius then
			local toPlayer = (threat.pos - self.pos).Magnitude > 0.01
				and (threat.pos - self.pos).Unit or Vector3.new(0, 0, 1)
			local facing = flat(self.facing).Magnitude > 0.01 and flat(self.facing).Unit or Vector3.new(0, 0, 1)
			local dot = facing:Dot(flat(toPlayer))
			local limit = math.cos(math.rad(cfg.fieldOfView * 0.5))
			if dot >= limit or dist < radius * 0.35 then
				visual = 1 - (dist / radius)
			end
		end

		local audio = 0
		if threat.noise > 0.05 then
			local hearRange = radius * 1.5
			audio = threat.noise * math.max(0, 1 - (dist / hearRange))
		end

		stimulus = math.max(visual, audio)
	end

	if stimulus > 0.001 then
		self.alert = math.min(1, self.alert + stimulus * cfg.alertGain * 3 * dt)
	else
		self.alert = math.max(0, self.alert - cfg.alertDecay * dt)
	end
end

function KiwiController:panicRadius()
	local noise = self.threat and self.threat.noise or 0
	return self.cfg.flushBase + noise * 12
end

-- ===============================================================
-- Movimiento
-- ===============================================================
function KiwiController:groundY(pos)
	-- Rayo corto justo arriba del kiwi: si mira desde muy arriba "engancha"
	-- techos o pisos altos (casas de dos pisos) y se teletransporta arriba.
	local origin = Vector3.new(pos.X, pos.Y + 2.2, pos.Z)
	local result = workspace:Raycast(origin, Vector3.new(0, -70, 0), self.moveParams)
	if result then
		self.lastGroundY = result.Position.Y
	end
	return self.lastGroundY
end

function KiwiController:whiskers(dir)
	local reach = 4.6 * math.max(1, (self.rig.scale or 1) * 0.55)
	local origin = self.pos + Vector3.new(0, 1.6 * (self.rig.scale or 1), 0)
	for _, angle in ipairs(WHISKER_ANGLES) do
		local probe = rotateFlat(dir, angle)
		local hit = workspace:Raycast(origin, probe * reach, self.moveParams)
		if not hit then
			return probe
		end
	end
	-- Todo bloqueado: seguimos derecho. El kiwi es chico y puede colarse;
	-- girar en redondo aqui solo lo dejaria trabado.
	return nil
end

-- ===============================================================
-- Picotazo defensivo (kiwi normal)
-- ===============================================================
--[[
	Si un cazador lo acorrala (sin salida hacia ningun lado) y lo tiene
	encima, el kiwi se defiende: un picotazo que saca el 10% de la vida.
]]
function KiwiController:stepPeck(dt)
	self.peckCooldown = math.max(0, (self.peckCooldown or 0) - dt)
	if self.peckAnim > 0 then
		self.peckAnim = math.max(0, self.peckAnim - dt)
	end
	if self.peckCooldown > 0 or self.defeated then
		return
	end
	if self.state == "hidden" or self.state == "sedated" or self.state == "trapped" then
		return
	end

	local cfg = Config.KiwiPeck
	local best, bestDist = nil, cfg.range
	for _, entry in ipairs(self.playersInArena or {}) do
		if entry.pos and not entry.hidden then
			local to = flat(entry.pos - self.pos)
			local d = to.Magnitude
			if d <= bestDist and d > 0.1 then
				best, bestDist = entry, d
			end
		end
	end
	if not best then
		return
	end

	-- Acorralado de verdad: todas las salidas (bigotes) tapadas
	if self:whiskers(self.facing) ~= nil then
		return
	end

	self.peckCooldown = cfg.cooldown
	self.peckAnim = 0.5
	local to = flat(best.pos - self.pos)
	if to.Magnitude > 0.1 then
		self.facing = to.Unit
	end
	self:emit("peck", { player = best.player, pos = self.pos + self.facing * 1.2 })
end

function KiwiController:currentSpeed()
	local speed
	if self.brain == "seeker" then
		if self.state == "hunt" then
			speed = self.cfg.huntSpeed or 26
		else
			speed = self.cfg.patrolSpeed or 12
		end
	elseif self.state == "flee" then
		speed = self.cfg.fleeSpeed
	elseif self.state == "tired" then
		speed = self.cfg.tiredSpeed
	else
		speed = self.cfg.wanderSpeed
	end
	if self.slowLeft > 0 then
		speed = speed * self.slowFactor
	end
	return speed
end

function KiwiController:moveToward(goal, speed, dt)
	local toGoal = flat(goal - self.pos)
	local dist = toGoal.Magnitude
	if dist < 1.6 then
		return true
	end

	local dir = toGoal.Unit
	local avoid = self:whiskers(dir)
	local finalDir = dir
	if avoid ~= nil and avoid ~= dir then
		finalDir = dir:Lerp(flat(avoid), 0.85)
		if finalDir.Magnitude > 0.01 then
			finalDir = finalDir.Unit
		else
			finalDir = flat(avoid)
		end
	end

	-- Separacion del jugador mas cercano: instinto de no chocar con el.
	-- (El kiwi gigante si quiere chocar: persigue a proposito.)
	if self.brain ~= "seeker" and self.threat and self.threatDist < 12 then
		local away = flat(self.pos - self.threat.pos)
		if away.Magnitude > 0.01 then
			finalDir = (finalDir + away.Unit * 0.9)
			if finalDir.Magnitude > 0.01 then
				finalDir = finalDir.Unit
			else
				finalDir = away.Unit
			end
		end
	end

	self.pos = self.arena:clampToBounds(self.pos + finalDir * speed * dt)
	-- Asedio: el kiwi nunca se aleja demasiado de su casa
	if self.leash then
		local away = self.pos - self.leash.pos
		local flatAway = Vector3.new(away.X, 0, away.Z)
		local radius = self.leash.radius or 40
		if flatAway.Magnitude > radius then
			local pulled = self.leash.pos + flatAway.Unit * radius
			self.pos = Vector3.new(pulled.X, self.pos.Y, pulled.Z)
		end
	end
	local gy = self:groundY(self.pos)
	self.pos = Vector3.new(self.pos.X, gy + self.rideHeight, self.pos.Z)

	-- Giro suave hacia la direccion de movimiento
	local blend = math.min(1, dt * 6)
	local newFacing = flat(self.facing):Lerp(finalDir, blend)
	if newFacing.Magnitude > 0.01 then
		self.facing = newFacing.Unit
	end

	return false
end

-- ===============================================================
-- Escondites
-- ===============================================================
function KiwiController:chooseSpot(needsClear)
	local bestIndex, bestScore = nil, -math.huge

	for index, spot in ipairs(self.arena.spots) do
		local clear = true
		local nearestPlayer = math.huge
		for _, p in ipairs(self.playersInArena or {}) do
			local d = (p.pos - spot.hidePoint).Magnitude
			if d < nearestPlayer then
				nearestPlayer = d
			end
		end
		if nearestPlayer < spot.radius + 14 then
			clear = false
		end
		if spot == self.arena.spots[self.spotIndex] then
			clear = false
		end

		-- Asedio: solo le interesan los escondites cerca de su casa
		local farFromHome = self.leash
			and (spot.hidePoint - self.leash.pos).Magnitude > (self.leash.radius or 40) * 1.5
		if (clear or not needsClear) and not farFromHome then
			local score = 0
			score = score - (spot.hidePoint - self.pos).Magnitude * 0.55
			score = score + spot.cover * 70 * self.cfg.coverPreference
			if index == self.lastSpotIndex then
				score = score - 18
			end
			if needsClear and clear then
				score = score + 40
			end
			if nearestPlayer < 45 then
				score = score - (45 - nearestPlayer) * 1.2
			end
			score = score + self.rng:NextNumber() * 10
			if score > bestScore then
				bestIndex, bestScore = index, score
			end
		end
	end

	return bestIndex
end

function KiwiController:randomPointInArena()
	if self.leash then
		-- Deambula alrededor de su casa (modo Asedio)
		local angle = self.rng:NextNumber(0, math.pi * 2)
		local radius = self.rng:NextNumber(6, self.leash.radius or 40)
		local point = self.leash.pos + Vector3.new(math.cos(angle) * radius, 0, math.sin(angle) * radius)
		return self.arena:clampToBounds(point)
	end
	local half = self.arena.halfSize - 30
	local angle = self.rng:NextNumber(0, math.pi * 2)
	local radius = self.rng:NextNumber(20, half)
	local point = self.arena.center + Vector3.new(math.cos(angle) * radius, 0, math.sin(angle) * radius)
	return self.arena:clampToBounds(point)
end

function KiwiController:goWander()
	self.goalBait = nil
	self:setRustle(self.spotIndex, false)
	-- Nunca se esconde donde hay un jugador parado al lado: si no hay
	-- ningun escondite limpio, camina a campo abierto (y es tu oportunidad).
	local spotIndex = self:chooseSpot(true)
	if spotIndex and self.noHideTimer <= 0 and self.rng:NextNumber() < 0.8 then
		local spot = self.arena.spots[spotIndex]
		self.goalSpot = spotIndex
		self.goalPos = spot.hidePoint
	else
		self.goalSpot = nil
		self.goalPos = self:randomPointInArena()
	end
	self.travelTime = 0
	self:setState("wander")
end

--[[
	Las particulas de "algo se mueve entre las hojas" viven en el
	escondite, asi que las prendemos y apagamos desde aca.
--]]
function KiwiController:setRustle(index, enabled)
	local spot = index and self.arena.spots[index]
	if spot and spot.emitter then
		spot.emitter.Enabled = enabled
	end
end

-- Salir del escondite por las buenas (se le acabo la paciencia)
function KiwiController:leaveSpot()
	self:setRustle(self.spotIndex, false)
	self.spotIndex = nil
	self.rig:setVisible(true)
	self.noHideTimer = math.max(self.noHideTimer, 0.5)
	self:emit("leave", { pos = self.pos })
	self:goWander()
end

-- Busca la fruta trampa mas cercana que valga la pena (sin jugadores pegados)
function KiwiController:findBait(players, baits)
	if not baits or (self.trapScare and self.trapScare > 0) then
		return nil
	end
	local best, bestD = nil, math.huge
	for _, bait in ipairs(baits) do
		if bait.armed then
			local d = (bait.pos - self.pos).Magnitude
			if d < bestD then
				local clear = true
				for _, p in ipairs(players) do
					if (p.pos - bait.pos).Magnitude < Config.Trampa.playerAvoid then
						clear = false
						break
					end
				end
				if clear then
					best, bestD = bait, d
				end
			end
		end
	end
	return best
end

-- Sale del escondite directo a la fruta (el hambre puede mas)
function KiwiController:leaveForBait(bait)
	self:setRustle(self.spotIndex, false)
	self.spotIndex = nil
	self.rig:setVisible(true)
	self.noHideTimer = math.max(self.noHideTimer, 1.5)
	self:emit("leave", { pos = self.pos })
	self.goalBait = bait
	self.goalSpot = nil
	self.goalPos = bait.pos
	self.travelTime = 0
	self:setState("wander")
end

-- Cayo en una fruta trampa: forcejea enganchado unos segundos y despues zafa
function KiwiController:trapHold(seconds)
	self.trapTimer = seconds
	self.goalBait = nil
	self.goalSpot = nil
	self.travelTime = 0
	self:setRustle(self.spotIndex, false)
	self.spotIndex = nil
	self.rig:setVisible(true)
	self.rig:setTouchable(true)
	self:setState("trapped")
end

function KiwiController:hide(index)
	local spot = self.arena.spots[index]
	if not spot then
		self:goWander()
		return
	end

	self:setRustle(self.spotIndex, false)
	self.spotIndex = index
	self.lastSpotIndex = index
	self.pos = spot.hidePoint
	self.hideTimer = self.rng:NextNumber(self.cfg.hideMin, self.cfg.hideMax)
	self.goalSpot = nil
	self.goalPos = self.pos
	self.alert = math.min(self.alert, 0.35)
	self.travelTime = 0
	self:setRustle(index, true)
	self.rig:setVisible(false)
	self:setState("hidden")
	self:emit("hide", { spot = spot, pos = self.pos })
end

function KiwiController:flush()
	local spot = self.arena.spots[self.spotIndex]
	self.spotIndex = nil
	self.noHideTimer = self.cfg.noHideAfterFlush
	self.alert = 1
	self:setRustle(spot and spot.id, false)
	self.rig:setVisible(true)
	self:emit("flush", { spot = spot, pos = self.pos })
	self:startFlee(self.threat)
end

-- ===============================================================
-- Huida / cansancio
-- ===============================================================
function KiwiController:startFlee(threat)
	self.goalBait = nil
	local bestIndex, bestScore = nil, -math.huge
	local threatPos = threat and threat.pos or (self.pos + self.facing * 50)

	for index, spot in ipairs(self.arena.spots) do
		-- Un escondite con gente encima no sirve de nada
		local nearestPlayer = math.huge
		for _, p in ipairs(self.playersInArena or {}) do
			local d = (p.pos - spot.hidePoint).Magnitude
			if d < nearestPlayer then
				nearestPlayer = d
			end
		end

		if nearestPlayer >= spot.radius + 10 then
			local away = (spot.hidePoint - threatPos).Magnitude
			local travel = (spot.hidePoint - self.pos).Magnitude
			local score = away * 1.0 - travel * 0.45 + spot.cover * 45 * self.cfg.coverPreference
			if index == self.spotIndex or index == self.lastSpotIndex then
				score = score - 30
			end
			score = score + self.rng:NextNumber() * 12
			if score > bestScore then
				bestIndex, bestScore = index, score
			end
		end
	end

	if bestIndex and (self.arena.spots[bestIndex].hidePoint - threatPos).Magnitude > 45 then
		self.goalSpot = bestIndex
		self.goalPos = self.arena.spots[bestIndex].hidePoint
	else
		-- Sin escondites libres: corre a campo abierto (y ahi lo ves)
		self.goalSpot = nil
		local away = flat(self.pos - threatPos)
		local dir = away.Magnitude > 0.1 and away.Unit or Vector3.new(1, 0, 0)
		if self.rng:NextNumber() < 0.5 then
			self.goalPos = self:randomPointInArena()
		else
			self.goalPos = self.arena:clampToBounds(self.pos + dir * 90)
		end
	end

	self.travelTime = 0
	self:setState("flee")
end

function KiwiController:staminaUpdate(dt)
	local cfg = self.cfg
	if self.state == "flee" then
		self.stamina = self.stamina - dt
		if self.stamina <= 0 then
			self.stamina = 0
			self:setState("tired")
			self:emit("tired")
		end
	elseif self.state == "tired" then
		self.stamina = math.min(cfg.stamina, self.stamina + cfg.staminaRegen * 0.75 * dt)
		if self.stamina >= cfg.stamina * 0.6 then
			self.goalSpot = nil
			self:goWander()
		end
	else
		self.stamina = math.min(cfg.stamina, self.stamina + cfg.staminaRegen * dt)
	end
end

-- ===============================================================
-- Dormir / capturar
-- ===============================================================
function KiwiController:sedate(seconds, player)
	if self.defeated or self.state == "sedated" then
		return false
	end

	self.rig:setVisible(true)
	self.rig:setTouchable(true)
	self.state = "sedated"
	self.stateTime = 0
	self.sedateLeft = seconds
	self.spotIndex = nil
	self.goalSpot = nil
	self.sleepGui.Enabled = true
	self.alert = 0
	if self.callbacks.onStateChange then
		self.callbacks.onStateChange(self, "sedated")
	end
	self:emit("sedate", { player = player })
	return true
end

function KiwiController:wake()
	self.sleepGui.Enabled = false
	self.rig:setTouchable(false)
	self.noHideTimer = 1.5
	self.alert = 1
	self.stamina = math.max(self.cfg.stamina * 0.45, 2)
	self:emit("wake")
	self:startFlee(self.threat)
end

function KiwiController:capture(player)
	if self.defeated then
		return false
	end
	self.defeated = true
	self.state = "caught"
	self.sleepGui.Enabled = false
	self.rig:setTouchable(false)
	self:setRustle(self.spotIndex, false)
	self.spotIndex = nil
	self.goalSpot = nil
	self:emit("capture", { player = player, pos = self.pos })
	return true
end

-- Asedio: el kiwi capturado queda en brazos y lo posiciona el modo
-- cuadro a cuadro (patas encogidas, como cargado)
function KiwiController:holdAt(cf)
	self.pos = cf.Position
	self.facing = cf.LookVector
	self.held = true
	self.rig:update(cf, {
		phase = os.clock() * 3,
		legSwing = 0,
		legFold = 0.85,
		headPitch = 0.12,
	})
end

-- Lo sueltan (cayo el portador): queda apoyado en el piso donde estaba
function KiwiController:dropHold()
	self.held = false
	if self.pos then
		-- Al soltarlo baja al piso (no queda flotando a la altura de brazos)
		local groundY = self.lastGroundY or (self.arena and self.arena.floorY)
		if groundY and self.rideHeight then
			self.pos = Vector3.new(self.pos.X, groundY + self.rideHeight, self.pos.Z)
		end
		local cf = CFrame.lookAt(self.pos, self.pos + self.facing)
		self.rig:update(cf, {
			phase = 0,
			legSwing = 0,
			legFold = 0.55,
			headPitch = 0.22,
		})
	end
end

-- ===============================================================
-- Bucle principal
-- ===============================================================
function KiwiController:step(dt, players, baits)
	if self.defeated then
		return
	end

	self.playersInArena = players
	self.stateTime = self.stateTime + dt
	self.noHideTimer = math.max(0, self.noHideTimer - dt)

	if self.slowLeft > 0 then
		self.slowLeft = self.slowLeft - dt
		if self.slowLeft <= 0 then
			self.slowLeft = 0
			self:slowEnd()
		end
	end

	if self.brain == "seeker" then
		self:stepSeeker(dt, players)
		return
	end

	if self.state == "trapped" then
		self.trapTimer = self.trapTimer - dt
		-- Forcejea enganchado en la fruta (ventana para atraparlo)
		local wiggle = math.sin(self.stateTime * 22) * 0.25
		local cf = CFrame.lookAt(self.pos, self.pos + self.facing) * CFrame.Angles(0, wiggle, 0)
		self.rig:update(cf, {
			phase = self.stateTime * 8,
			legSwing = 0.55 * math.sin(self.stateTime * 18),
			headPitch = -0.15 + wiggle * 0.5,
		})
		if self.trapTimer <= 0 then
			-- Zafo: escapa asustado y por un rato no vuelve a pisar fruta
			self.trapScare = Config.Trampa.escapeScare
			self.alert = 1.2
			self.rig:setTouchable(false)
			self:emit("trapescape", { pos = self.pos })
			self:startFlee(nil)
		end
		return
	end

	if self.state == "hidden" then
		local spot = self.arena.spots[self.spotIndex]
		if spot then
			-- adentro del escondite: pose quieta y a esperar
			local cf = CFrame.lookAt(self.pos, self.pos + self.facing)
			self.rig:update(cf, {
				phase = 0,
				legSwing = 0,
				headPitch = 0.2 + math.sin(self.stateTime * 1.6) * 0.15,
			})
		end

		self:sense(dt, players)
		self.hideTimer = self.hideTimer - dt

		-- El hambre puede mas: si hay fruta puesta, sale del escondite a comer
		self.baitTimer = self.baitTimer - dt
		if self.baitTimer <= 0 and not (self.threat and self.threatDist <= self:panicRadius()) then
			self.baitTimer = Config.Trampa.temptEvery
			local best = self:findBait(players, baits)
			if best then
				self:leaveForBait(best)
				return
			end
		end

		if self.threat and self.threatDist <= self:panicRadius() then
			self:flush()
		elseif self.hideTimer <= 0 then
			self:leaveSpot()
		end
		return
	end

	if self.state == "sedated" then
		self.sedateLeft = self.sedateLeft - dt
		self:sleepPose()
		if self.sedateLeft <= 0 then
			self:wake()
		end
		return
	end

	if self.estatico then
		-- Kiwi del corral: quieto en su casa. Solo gira despacio para
		-- mirar al que se arrima y pega el picotazo defensivo si lo
		-- acorralan contra una pared (stepPeck se encarga del resto).
		local best, bestDist = nil, math.huge
		for _, entry in ipairs(players) do
			if entry.pos and not entry.hidden then
				local d = (entry.pos - self.pos).Magnitude
				if d < bestDist then
					best, bestDist = entry, d
				end
			end
		end
		self.threat = best
		self.threatDist = bestDist
		if best and bestDist < 24 then
			local to = flat(best.pos - self.pos)
			if to.Magnitude > 0.6 then
				local goal = to.Unit
				local paso = math.min(1, dt * 1.8)
				local girado = flat(self.facing) * (1 - paso) + goal * paso
				if girado.Magnitude > 0.01 then
					self.facing = girado.Unit
				end
			end
		end
		self:stepPeck(dt)
		self.animPhase = self.animPhase + dt * 2.5
		local peck = 0
		if self.peckAnim > 0 then
			peck = math.sin((1 - self.peckAnim / 0.5) * math.pi)
		end
		local cabeza = 0.18 + math.sin(self.stateTime * 1.5) * 0.08
		self.rig:update(CFrame.lookAt(self.pos, self.pos + self.facing), {
			phase = 0,
			legSwing = 0,
			headPitch = cabeza + peck * 0.8,
			beak = peck * 0.9,
		})
		return
	end

	self:sense(dt, players)
	self:staminaUpdate(dt)
	self:stepPeck(dt)

	if self.state ~= "flee" and self.state ~= "tired" then
		if self.alert >= 1 or (self.threat and self.threatDist <= self.cfg.flushBase) then
			self:startFlee(self.threat)
		end
	end

	if self.trapScare > 0 then
		self.trapScare = self.trapScare - dt
	end

	-- Hambre: de vez en cuando el kiwi huele las frutas trampa (mire donde mire)
	self.baitTimer = self.baitTimer - dt
	if self.state == "wander" and not self.goalBait and self.baitTimer <= 0 then
		self.baitTimer = Config.Trampa.temptEvery
		local best = self:findBait(players, baits)
		if best then
			self.goalBait = best
			self.goalSpot = nil
			self.goalPos = best.pos
			self.travelTime = 0
		end
	end

	-- Si pasa bien cerca de una fruta, cae igual (sin importar a donde iba)
	if self.state == "wander" and not self.goalBait and baits then
		for _, bait in ipairs(baits) do
			if bait.armed and (bait.pos - self.pos).Magnitude < Config.Trampa.catchDist then
				self:emit("trapcatch", { bait = bait, pos = self.pos })
				return
			end
		end
	end

	if self.goalBait then
		local bait = self.goalBait
		if not bait.armed or self.alert >= 0.95 then
			self.goalBait = nil
			self:goWander()
		end
	end

	local speed = self:currentSpeed()
	self.travelTime = self.travelTime + dt
	if self.travelTime > 26 then
		-- Se trabo en el camino (cerco, rocas, etc): cambia de plan
		self:goWander()
		return
	end

	local reached = self:moveToward(self.goalPos, speed, dt)

	-- Animacion de las patas proporcional a la velocidad
	local walkFactor = clamp(speed / 20, 0.25, 1.2)
	self.animPhase = self.animPhase + dt * (6 + speed * 0.55)
	local headPitch = 0.12 + (1 - self.alert) * 0.22 + math.sin(self.stateTime * 1.4) * 0.06
	local cf = CFrame.lookAt(self.pos, self.pos + self.facing)
	-- Picotazo: la cabeza baja de golpe cuando el kiwi se defiende
	local peck = 0
	if self.peckAnim > 0 then
		peck = math.sin((1 - self.peckAnim / 0.5) * math.pi)
	end
	self.rig:update(cf, {
		phase = self.animPhase,
		legSwing = walkFactor * 0.7,
		headPitch = headPitch + peck * 0.8,
		beak = peck * 0.9,
	})

	if reached then
		if self.goalBait then
			local bait = self.goalBait
			self.goalBait = nil
			self:emit("trapcatch", { bait = bait, pos = self.pos })
		elseif self.goalSpot and self.noHideTimer <= 0 then
			self:hide(self.goalSpot)
		else
			self:goWander()
		end
	end
end

-- ===============================================================
-- Kiwi gigante (modo colosal): patrulla, huele a los cazadores y los atrapa
-- ===============================================================
function KiwiController:applyGiantLook()
	self.rig:setColorTint(Color3.fromRGB(92, 66, 50))
	for _, eye in ipairs(self.rig.eyes) do
		eye.Color = Color3.fromRGB(228, 60, 44)
		eye.Material = Enum.Material.Neon
	end
	local glow = self.rig.head:FindFirstChild("FuriaKiwi")
	if not glow then
		glow = Instance.new("PointLight")
		glow.Name = "FuriaKiwi"
		glow.Color = Color3.fromRGB(230, 70, 50)
		glow.Range = 26
		glow.Brightness = 1.6
		glow.Parent = self.rig.head
	end
end

--[[
	Ralentizador (Kiwi Colosal): el gigante no se duerme, se frena.
	Se marca con un tinte frio, ojos celestes y un cartel bien visible.
]]
function KiwiController:slow(factor, seconds)
	if self.defeated then
		return false
	end
	self.slowFactor = factor or 0.5
	self.slowLeft = seconds or 6

	if self.brain == "seeker" then
		self.rig:setColorTint(Color3.fromRGB(110, 150, 175))
		for _, eye in ipairs(self.rig.eyes) do
			eye.Color = Color3.fromRGB(140, 220, 240)
		end
	end

	local body = self.rig.body
	if body and not body:FindFirstChild("LetreroLento") then
		local gui = Instance.new("BillboardGui")
		gui.Name = "LetreroLento"
		gui.Size = UDim2.fromScale(9, 2.4)
		gui.StudsOffsetWorldSpace = Vector3.new(0, 4.6 * (self.rig.scale or 1), 0)
		gui.AlwaysOnTop = true
		gui.Parent = body

		local label = Instance.new("TextLabel")
		label.Size = UDim2.fromScale(1, 1)
		label.BackgroundTransparency = 1
		label.Font = Enum.Font.GothamBlack
		label.TextScaled = true
		label.TextColor3 = Color3.fromRGB(140, 220, 240)
		label.TextStrokeTransparency = 0.2
		label.Text = "¡RALENTIZADO!"
		label.Parent = gui
	end

	self:emit("slow", { pos = self.pos })
	return true
end

function KiwiController:slowEnd()
	if self.brain == "seeker" then
		self:applyGiantLook()
	end
	local body = self.rig.body
	if body then
		local gui = body:FindFirstChild("LetreroLento")
		if gui then
			gui:Destroy()
		end
	end
	self:emit("slowend", { pos = self.pos })
end

function KiwiController:goPatrol()
	self.goalSpot = nil
	self.goalBait = nil
	self.goalPos = self:randomPointInArena()
	self.travelTime = 0
	self:setState("patrol")
end

--[[
	El jugador salio del escondite mientras el kiwi husmeaba: el premio
	es suyo, pero el gigante le sale al paso al instante (el "casi").
]]
function KiwiController:sniffMiss(chasePos)
	if self.state ~= "sniff" then
		return
	end
	local index = self.sniffIndex
	self.sniffIndex = nil
	self.sniffStep = 0
	self:setState("patrol")
	if chasePos then
		self:goHuntZone(chasePos)
	end
	self:emit("sniffmiss", { pos = self.pos, index = index })
end

--[[
	Busqueda inteligente: escondites cerca de una posicion, para husmear
	cuando el kiwi pierde el rastro de un cazador.
]]
function KiwiController:spotsNear(position, radius, maxCount)
	local list = {}
	for _, spot in ipairs(self.arena.spots) do
		local d = (spot.hidePoint - position).Magnitude
		if d <= radius then
			table.insert(list, { spot = spot, d = d })
		end
	end
	table.sort(list, function(a, b)
		return a.d < b.d
	end)
	local out = {}
	for index = 1, math.min(maxCount, #list) do
		table.insert(out, list[index].spot)
	end
	return out
end

--[[
	El kiwi no entra a la zona segura: ronda su borde esperando.
]]
function KiwiController:avoidSafeZone()
	local zone = self.arena and self.arena.safeZone
	if not zone or not zone.active then
		return
	end
	local offset = flat(self.pos - zone.center)
	local radius = zone.radius + 1.5
	if offset.Magnitude < radius then
		local dir = offset.Magnitude > 0.1 and offset.Unit or flat(self.facing)
		if dir.Magnitude < 0.1 then
			dir = Vector3.new(1, 0, 0)
		end
		self.pos = Vector3.new(zone.center.X + dir.X * radius, self.pos.Y, zone.center.Z + dir.Z * radius)
	end
end

--[[
	Atraccion al refugio (el cazador esta cargando la zona segura).
]]
function KiwiController:goHuntZone(position)
	if self.defeated or self.state == "eat" then
		return
	end
	if self.state ~= "hunt" then
		self:setState("hunt")
		self.roarAt = 0
		self:emit("hunt", { pos = self.pos })
	end
	self.huntUntil = self.stateTime + 6
	self.goalPos = position
	self.searchQueue = nil
end

function KiwiController:stepSeeker(dt, players)
	local cfg = self.cfg

	if self.state == "eat" then
		-- Mordiscos de verdad: se yergue, se lanza hacia adelante y pica
		local t = self.stateTime
		local cycle = 0.86
		local phase = (t % cycle) / cycle
		local rear, strikeA = 0, 0
		if phase < 0.38 then
			rear = phase / 0.38
		elseif phase < 0.62 then
			strikeA = (phase - 0.38) / 0.24
		else
			strikeA = 1 - (phase - 0.62) / 0.38
		end

		local biteIndex = math.floor(t / cycle)
		if biteIndex ~= self.biteIndex then
			self.biteIndex = biteIndex
			self:emit("chomp", { pos = self.pos })
		end

		if self.eatTarget then
			local toTarget = flat(self.eatTarget - self.pos)
			local dist = toTarget.Magnitude
			if toTarget.Magnitude > 0.5 then
				self.facing = toTarget.Unit
			end
			if dist > 3.2 then
				self.pos = self.pos + toTarget.Unit * math.min(dist - 3.2, strikeA * 3.4 * dt)
			end
		end

		local lean = -0.30 * rear + 1.05 * strikeA
		local lift = 0.26 * rear - 0.20 * strikeA
		local base = self.pos + Vector3.new(0, lift, 0)
		local cf = CFrame.lookAt(base, base + self.facing)
		cf = cf * CFrame.Angles(lean, 0, math.sin(t * 24) * 0.05)
		self.rig:update(cf, {
			phase = 0,
			legSwing = 0.20 * strikeA,
			headPitch = 0.10 + 0.75 * strikeA,
			beak = 0.7 * strikeA,
		})

		if t > (Config.Round.EatHold or 2.6) then
			self.eatTarget = nil
			self.biteIndex = 0
			self:goPatrol()
		end
		return
	end

	if self.state == "sniff" then
		local spot = self.arena.spots[self.sniffIndex]
		local done = self.stateTime >= self.sniffUntil

		-- Se acerca al escondite y husmea pegado a la salida
		local toSpot = spot and flat(spot.hidePoint - self.pos) or Vector3.zero
		if toSpot.Magnitude > 3.4 then
			self.pos = self.pos + toSpot.Unit * math.min(toSpot.Magnitude - 3.4, 11 * dt)
		end
		if toSpot.Magnitude > 0.6 then
			self.facing = toSpot.Unit
		end

		local sniffCF = CFrame.lookAt(self.pos, self.pos + self.facing)
		sniffCF = sniffCF * CFrame.Angles(0, math.sin(self.stateTime * 7) * 0.10, 0)
		self.rig:update(sniffCF, {
			phase = 0,
			legSwing = 0.14 + 0.18 * math.sin(self.stateTime * 9),
			headPitch = 0.75 + math.sin(self.stateTime * 5.5) * 0.12,
			beak = 0.25 + math.max(0, math.sin(self.stateTime * 6)) * 0.4,
		})

		self.sniffStep = self.sniffStep + dt
		if self.sniffStep >= 0.9 then
			self.sniffStep = 0
			self:emit("sniff", { pos = self.pos, index = self.sniffIndex })
		end

		if done then
			local entered = spot and spot.enter
			local wasIndex = self.sniffIndex
			self.sniffIndex = nil
			self.sniffStep = 0
			if entered and spot.occupied then
				-- Sigue escondido: lo encuentra y se lo come
				self.eatTarget = (entered.exit and entered.exit.Position) or spot.hidePoint
				self.biteIndex = 0
				self:setState("eat")
				self:emit("sniffcatch", { pos = self.pos, index = wasIndex, player = spot.occupied })
			else
				self:emit("sniffmiss", { pos = self.pos, index = wasIndex })
				self:goPatrol()
			end
		end
		return
	end

	-- Huele un escondite ocupado cerca: se queda husmeando un rato
	if self.state ~= "busy" and not self.defeated then
		for index, spot in ipairs(self.arena.spots) do
			if spot.enter and spot.occupied then
				local cooling = spot.sniffCooldownUntil and spot.sniffCooldownUntil > os.clock()
				local zone = self.arena.safeZone
				local inZone = zone and zone.active and flat(spot.hidePoint - zone.center).Magnitude < zone.radius + 4
				if not cooling and not inZone and (spot.hidePoint - self.pos).Magnitude <= spot.radius + 6.5 then
					spot.sniffCooldownUntil = os.clock() + Config.Hide.sniffCooldown + Config.Hide.sniffTime
					self.sniffIndex = index
					self.sniffUntil = Config.Hide.sniffTime
					self.sniffStep = 0
					self.searchQueue = nil
					self.goalPos = self.pos
					self:setState("sniff")
					self:emit("sniffstart", { pos = self.pos, index = index, player = spot.occupied })
					break
				end
			end
		end
	end

	if self.state == "busy" then
		if self.stateTime > 4 then
			self:goPatrol()
		else
			local cf = CFrame.lookAt(self.pos, self.pos + self.facing)
			self.rig:update(cf, { phase = 0, legSwing = 0, headPitch = -0.1 })
			return
		end
	end

	-- Percibe a los cazadores: menos distancia y mas ruido = mas facil de oler.
	-- Al jugador escondido no lo huele: hay que husmear el escondite.
	local target, targetDist = nil, math.huge
	local detect = cfg.detectRadius or 80
	local noiseRange = cfg.noiseRadius or 130
	for _, p in ipairs(players) do
		if not p.hidden then
			local d = (p.pos - self.pos).Magnitude
			local range = detect + (p.noise or 0) * (noiseRange - detect)
			if d < range and d < targetDist then
				target, targetDist = p, d
			end
		end
	end

	if target then
		if self.state ~= "hunt" then
			self:setState("hunt")
			self.roarAt = 0
			self:emit("hunt", { pos = self.pos })
		end
		self.huntUntil = self.stateTime + (cfg.loseInterest or 7)
		self.goalPos = target.pos
		self.searchQueue = nil
	elseif self.state == "hunt" and self.stateTime > self.huntUntil then
		self:goPatrol()
	end

	if self.state == "hunt" and target then
		if self.stateTime >= self.roarAt then
			self.roarAt = self.stateTime + (cfg.roarEvery or 18)
			self:emit("roar", { pos = self.pos })
		end
		if targetDist <= (cfg.catchDist or 7) then
			self.eatTarget = target.pos
			self.biteIndex = 0
			local toVictim = flat(target.pos - self.pos)
			if toVictim.Magnitude > 0.5 then
				self.facing = toVictim.Unit
			end
			self.goalPos = self.pos
			self:setState("eat")
			self.travelTime = 0
			self:emit("catch", { player = target.player, pos = self.pos })
			return
		end
	end

	local speed = self:currentSpeed()
	self.travelTime = self.travelTime + dt
	if self.travelTime > 40 then
		self:goPatrol()
		return
	end

	local reached = self:moveToward(self.goalPos, speed, dt)
	self:avoidSafeZone()

	if reached and self.state == "hunt" then
		-- Perdio el rastro: husmea los escondites cercanos antes de rendirse
		if not self.searchQueue then
			self.searchQueue = self:spotsNear(self.goalPos, 170, 3)
		end
		local nextSpot = table.remove(self.searchQueue, 1)
		if nextSpot then
			self.goalPos = nextSpot.hidePoint
			self.travelTime = math.min(self.travelTime, 25)
		else
			self.searchQueue = nil
			self:goPatrol()
		end
	end

	local walkFactor = clamp(speed / 26, 0.3, 1.3)
	self.animPhase = self.animPhase + dt * (5 + speed * 0.5)
	local cf = CFrame.lookAt(self.pos, self.pos + self.facing)
	self.rig:update(cf, {
		phase = self.animPhase,
		legSwing = walkFactor * 0.85,
		headPitch = 0.10,
	})

	if reached and self.state == "patrol" then
		self:goPatrol()
	end
end

function KiwiController:sleepPose()
	local roll = math.sin(self.stateTime * 2) * 0.04
	local cf = CFrame.lookAt(self.pos - Vector3.new(0, 0.5, 0), self.pos - Vector3.new(0, 0.5, 0) + self.facing)
		* CFrame.Angles(0, 0, math.rad(72) + roll)
	self.rig:update(cf, {
		phase = 0,
		legSwing = 0,
		legFold = 1,
		headPitch = 0.5,
	})
end

function KiwiController:destroy()
	self:setRustle(self.spotIndex, false)
	if self.touchConn then
		self.touchConn:Disconnect()
		self.touchConn = nil
	end
	self.rig:destroy()
end

return KiwiController
