--[[
	Actions.lua  (servidor)
	Resuelve lo que pasa cuando un jugador usa una herramienta:
		red          -> lanzar la red (captura o espanta)
		rifle        -> disparar un dardo tranquilizante (proyectil real)
		rastreador   -> ping con la direccion del kiwi
		trampa       -> dejar una fruta trampa para el kiwi
		pintura      -> disparar pintura a otros jugadores

	Todo se valida aca: distancias, conos de vision, recargas y estado
	del kiwi. El cliente solo pide la accion, nunca decide el resultado.
--]]

local Players = game:GetService("Players")

local Shared = require(script.Parent.Shared)
local Config = require(Shared.Config)
local Net = require(Shared.Net)
local Util = require(Shared.Util)

local ToolService = require(script.Parent.ToolService)

local Actions = {}

local DART_LENGTH = 0.9
local DART_THICKNESS = 0.22
local NET_HALF_ANGLE = math.rad(55)   -- medio cono de la red
local AIM_TOLERANCE = math.rad(75)    -- cuanto puede desviarse la mira del dardo

-- ===============================================================
-- Utilidades
-- ===============================================================
local function getRoot(player)
	local character = player.Character
	if not character then
		return nil, nil
	end
	return character, character:FindFirstChild("HumanoidRootPart")
end

local function flat(v)
	return Vector3.new(v.X, 0, v.Z)
end

local function flatDistance(a, b)
	return flat(a - b).Magnitude
end

-- Direccion "hacia donde mira" el jugador: usamos la mira que manda el
-- cliente, pero saneada (nunca detras del personaje y con largo fijo).
local function aimDirection(player, root, data)
	local muzzle = root.Position + Vector3.new(0, 1.1, 0)
	local aim = data and data.aim
	local dir
	if typeof(aim) == "Vector3" and (aim - muzzle).Magnitude > 0.2 then
		dir = (aim - muzzle).Unit
	else
		dir = root.CFrame.LookVector
	end

	-- Si el cliente manda una direccion ridicula, cae a la del personaje
	local look = root.CFrame.LookVector
	if flat(dir):Dot(flat(look)) < math.cos(AIM_TOLERANCE) then
		dir = look
	end
	return muzzle, dir
end

function Actions.makeDartParams(character, dartPart)
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = { character, dartPart }
	params.IgnoreWater = true
	return params
end

-- ===============================================================
-- RED DE CAPTURA
-- ===============================================================
function Actions.net(session, player, data)
	local cfg = session.diff.red
	local character, root = getRoot(player)
	if not root then
		return
	end

	if ToolService.getRemaining(player, "red") > 0 then
		return
	end
	ToolService.startCooldown(player, "red", cfg.cooldown)

	local muzzle, dir = aimDirection(player, root, data)
	session:event("netswing", { pos = root.Position, userId = player.UserId })

	local kiwi = session.kiwi
	if not kiwi or kiwi.defeated then
		return
	end

	local kiwiPos = kiwi:getPosition()

	-- 1) El kiwi esta escondido: buscamos en el escondite mas cercano
	if kiwi:isHidden() then
		local spot = session.arena:nearestSpot(root.Position, cfg.range + 8)
		if not spot then
			session:notify(player, Config.Text.FlushFail, Color3.fromRGB(180, 180, 180))
			return
		end

		local toSpot = flat(spot.hidePoint - root.Position)
		local inCone = toSpot.Magnitude < 0.1 or flat(dir):Dot(toSpot.Unit) > math.cos(NET_HALF_ANGLE)
		if inCone and kiwi.spotIndex == spot.id then
			kiwi:flush()
			session:notify(player, Config.Text.Flushed, Color3.fromRGB(255, 210, 120))
		else
			session:notify(player, Config.Text.FlushFail, Color3.fromRGB(180, 180, 180))
			session:event("rustle", { pos = spot.hidePoint })
		end
		return
	end

	-- 2) Kiwi a la vista: hay que estar cerca y apuntando
	local toKiwi = kiwiPos - (root.Position + Vector3.new(0, 1.1, 0))
	local distance = toKiwi.Magnitude
	local inCone = distance < 0.1 or dir:Dot(toKiwi.Unit) > math.cos(NET_HALF_ANGLE)

	if distance > cfg.range or not inCone then
		return
	end

	if kiwi:isSedated() then
		session:capture(player, "red")
		return
	end

	if session.rng:NextNumber() <= cfg.chance then
		session:capture(player, "red")
	else
		session:notify(player, Config.Text.NetMiss, Color3.fromRGB(255, 150, 140))
		kiwi:flush()
	end
end

-- ===============================================================
-- RIFLE TRANQUILIZANTE
-- ===============================================================
function Actions.rifle(session, player, data)
	local cfg = session.diff.rifle
	local character, root = getRoot(player)
	if not root then
		return
	end

	if ToolService.getRemaining(player, "rifle") > 0 then
		return
	end

	local muzzle, dir = aimDirection(player, root, data)

	local dartPart = Util.makePart({
		Name = "Dardo",
		ClassName = "Part",
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(DART_LENGTH, DART_THICKNESS, DART_THICKNESS),
		Color = Color3.fromRGB(226, 232, 240),
		Material = Enum.Material.SmoothPlastic,
		Anchored = true,
		CanCollide = false,
		CanQuery = false,
		CanTouch = false,
		CFrame = CFrame.lookAt(muzzle + dir * 1.2, muzzle + dir * 2.2) * CFrame.Angles(0, math.rad(90), 0),
		Parent = workspace,
	})
	Util.destroyAfter(dartPart, 6)

	local dart = {
		kind = "dart",
		part = dartPart,
		pos = muzzle + dir * 1.2,
		dir = dir,
		speed = cfg.speed,
		life = 1.6,
		player = player,
		params = Actions.makeDartParams(character, dartPart),
	}

	table.insert(session.projectiles, dart)
	ToolService.startCooldown(player, "rifle", cfg.cooldown)
	session:event("dartshot", { pos = muzzle, dir = dir })
end

--[[
	RIFLE RALENTIZADOR (Kiwi Colosal): no lo duerme, lo frena unos segundos.
]]
function Actions.relente(session, player, data)
	local cfg = Config.Relente
	local character, root = getRoot(player)
	if not root then
		return
	end

	if ToolService.getRemaining(player, "relente") > 0 then
		return
	end

	local muzzle, dir = aimDirection(player, root, data)

	local dartPart = Util.makePart({
		Name = "Aguja",
		ClassName = "Part",
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(DART_LENGTH, DART_THICKNESS, DART_THICKNESS),
		Color = Config.Tools.relente.color,
		Material = Enum.Material.Neon,
		Anchored = true,
		CanCollide = false,
		CanQuery = false,
		CanTouch = false,
		CFrame = CFrame.lookAt(muzzle + dir * 1.2, muzzle + dir * 2.2) * CFrame.Angles(0, math.rad(90), 0),
		Parent = workspace,
	})
	Util.destroyAfter(dartPart, 6)

	local dart = {
		kind = "slow",
		part = dartPart,
		pos = muzzle + dir * 1.2,
		dir = dir,
		speed = cfg.speed,
		life = cfg.life,
		player = player,
		params = Actions.makeDartParams(character, dartPart),
	}

	table.insert(session.projectiles, dart)
	ToolService.startCooldown(player, "relente", cfg.cooldown)
	session:event("dartshot", { pos = muzzle, dir = dir })
end

-- ===============================================================
-- ARMAS DE BAUL (lanzamisiles, revolver, arco): proyectiles con empujon
-- ===============================================================
function Actions.fireWeapon(session, player, weaponId, data)
	local cfg = Config.Weapons[weaponId]
	if not cfg then
		return
	end

	local character, root = getRoot(player)
	if not root then
		return
	end

	if ToolService.getRemaining(player, weaponId) > 0 then
		return
	end

	if ToolService.lootUses(player, weaponId) <= 0 then
		return
	end

	local muzzle, dir = aimDirection(player, root, data)

	local dartPart = Util.makePart({
		Name = "Proyectil",
		ClassName = "Part",
		Size = cfg.size or Vector3.new(0.4, 0.4, 1.6),
		Color = cfg.color,
		Material = Enum.Material.Neon,
		Anchored = true,
		CanCollide = false,
		CanQuery = false,
		CanTouch = false,
		CFrame = CFrame.lookAt(muzzle + dir * 1.2, muzzle + dir * 2.2),
		Parent = workspace,
	})
	Util.destroyAfter(dartPart, 6)

	local dart = {
		kind = "weapon",
		weaponId = weaponId,
		part = dartPart,
		pos = muzzle + dir * 1.2,
		dir = dir,
		speed = cfg.speed,
		life = cfg.life,
		player = player,
		params = Actions.makeDartParams(character, dartPart),
	}

	table.insert(session.projectiles, dart)
	ToolService.startCooldown(player, weaponId, cfg.cooldown)
	ToolService.consumeLoot(player, weaponId)
	session:event("dartshot", { pos = muzzle, dir = dir })
end

function Actions.weaponHit(session, dart, pos)
	local cfg = Config.Weapons[dart.weaponId]
	if not cfg then
		return
	end

	-- El kiwi queda atontado (o muy lento) si le da directo o cerca
	local kiwi = session.kiwi
	if kiwi and not kiwi.defeated then
		local reach = math.max(cfg.blast or 0, 8)
		if (kiwi:getPosition() - pos).Magnitude <= reach then
			if kiwi:slow(cfg.slowFactor or 0.4, cfg.slowTime or 2) then
				session:notify(dart.player, string.format(Config.Text.BoomHit, cfg.name), cfg.color, 3)
			end
		end
	end

	-- Los cazadores cerca salen volando un poquito (tambien el que disparo)
	if (cfg.blast or 0) > 0 then
		for _, other in ipairs(session.players) do
			local _, otherRoot = getRoot(other)
			if otherRoot then
				local away = otherRoot.Position - pos
				local distance = away.Magnitude
				if distance <= cfg.blast and distance > 0.05 then
					local push = away.Unit * (cfg.knockback or 30)
					otherRoot.AssemblyLinearVelocity = Vector3.new(push.X, 24, push.Z)
				end
			end
		end
	end

	session:event("boom", { pos = pos, weapon = dart.weaponId })
	local shooterName = dart.player.DisplayName ~= "" and dart.player.DisplayName or dart.player.Name
	if (cfg.blast or 0) >= 10 then
		session:notifyAll(string.format(Config.Text.BoomShout, shooterName, cfg.name), cfg.color, 3)
	end
end

function Actions.stepProjectiles(session, dt)
	local projectiles = session.projectiles
	for i = #projectiles, 1, -1 do
		local dart = projectiles[i]
		local stepLen = dart.speed * dt
		dart.life = dart.life - dt

		local hit = workspace:Raycast(dart.pos, dart.dir * stepLen, dart.params)
		local remove = false

		if hit then
			remove = true
			if dart.kind == "paint" then
				local character = hit.Instance:FindFirstAncestorOfClass("Model")
				local victim = character and Players:GetPlayerFromCharacter(character)
				Actions.resolvePaint(session, dart, hit, victim)
			elseif dart.kind == "slow" then
				local kiwi = session.kiwi
				if kiwi and not kiwi.defeated and hit.Instance:IsDescendantOf(kiwi.model) then
					kiwi:slow(Config.Relente.factor, Config.Relente.time)
					local shooterName = dart.player.DisplayName ~= "" and dart.player.DisplayName or dart.player.Name
					session:notify(dart.player, string.format(Config.Text.SlowHit, Config.Relente.time), Config.Tools.relente.color)
					session:notifyAll(string.format(Config.Text.SlowAll, shooterName), Config.Tools.relente.color)
					session:event("slowhit", { pos = hit.Position })
				else
					session:event("dartmiss", { pos = hit.Position, normal = hit.Normal })
					session:notify(dart.player, Config.Text.SlowMiss, Color3.fromRGB(200, 200, 200))
				end
			elseif dart.kind == "weapon" then
				Actions.weaponHit(session, dart, hit.Position)
			else
				local kiwi = session.kiwi
				if kiwi and not kiwi.defeated and hit.Instance:IsDescendantOf(kiwi.model) then
					if kiwi:sedate(session.diff.kiwi.sedateTime, dart.player) then
						session:notify(dart.player, Config.Text.DartHit, Color3.fromRGB(160, 230, 170))
						session:event("darthit", { pos = hit.Position })
					end
				else
					session:event("dartmiss", { pos = hit.Position, normal = hit.Normal })
					session:notify(dart.player, Config.Text.DartMiss, Color3.fromRGB(200, 200, 200))
					ToolService.startCooldown(dart.player, "rifle", session.diff.rifle.cooldownOnMiss)
				end
			end
		else
			dart.pos = dart.pos + dart.dir * stepLen
			if dart.life <= 0 then
				remove = true
			elseif dart.kind == "paint" then
				dart.part.CFrame = CFrame.new(dart.pos)
			elseif dart.kind == "weapon" then
				dart.part.CFrame = CFrame.lookAt(dart.pos, dart.pos + dart.dir)
			else
				dart.part.CFrame = CFrame.lookAt(dart.pos, dart.pos + dart.dir) * CFrame.Angles(0, math.rad(90), 0)
			end
		end

		if remove then
			dart.part:Destroy()
			table.remove(projectiles, i)
		end
	end
end

-- ===============================================================
-- RIFLE DE PINTURA (molesta a otros jugadores)
-- ===============================================================
function Actions.paint(session, player, data)
	local cfg = Config.PaintRifle
	local character, root = getRoot(player)
	if not root then
		return
	end

	if ToolService.getRemaining(player, "pintura") > 0 then
		return
	end

	local muzzle, dir = aimDirection(player, root, data)
	local color = Config.Tools.pintura.color

	local ball = Util.makePart({
		Name = "BolaPintura",
		ClassName = "Part",
		Shape = Enum.PartType.Ball,
		Size = Vector3.new(0.34, 0.34, 0.34),
		Color = color,
		Material = Enum.Material.SmoothPlastic,
		Anchored = true,
		CanCollide = false,
		CanQuery = false,
		CanTouch = false,
		CFrame = CFrame.new(muzzle + dir * 1.2),
		Parent = workspace,
	})
	Util.destroyAfter(ball, 6)

	local shot = {
		kind = "paint",
		part = ball,
		pos = muzzle + dir * 1.2,
		dir = dir,
		speed = cfg.speed,
		life = cfg.life,
		player = player,
		color = color,
		params = Actions.makeDartParams(character, ball),
	}

	table.insert(session.projectiles, shot)
	ToolService.startCooldown(player, "pintura", cfg.cooldown)
	session:event("paintshot", { pos = muzzle, dir = dir })
end

-- Mancha brillante visible a traves de las paredes (marca al pintado)
function Actions.markCharacter(character, color, duration, labelText, scale)
	if not character or not character.Parent then
		return
	end

	local oldHighlight = character:FindFirstChild("MarcaPintura")
	if oldHighlight then
		oldHighlight:Destroy()
	end
	local oldTag = character:FindFirstChild("EtiquetaPintura")
	if oldTag then
		oldTag:Destroy()
	end

	local highlight = Instance.new("Highlight")
	highlight.Name = "MarcaPintura"
	highlight.FillColor = color or Config.Tools.pintura.color
	highlight.OutlineColor = Color3.fromRGB(255, 255, 255)
	highlight.FillTransparency = 0.35
	highlight.OutlineTransparency = 0
	highlight.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
	highlight.Parent = character

	local anchor = character:FindFirstChild("Head") or character.PrimaryPart or character:FindFirstChildWhichIsA("BasePart")
	local tag
	if anchor then
		tag = Instance.new("BillboardGui")
		tag.Name = "EtiquetaPintura"
		tag.Size = UDim2.fromScale(3.6 * (scale or 1), 1.2 * (scale or 1))
		tag.StudsOffsetWorldSpace = Vector3.new(0, 3.4 * (scale or 1), 0)
		tag.AlwaysOnTop = true
		tag.Parent = anchor

		local text = Instance.new("TextLabel")
		text.Size = UDim2.fromScale(1, 1)
		text.BackgroundTransparency = 1
		text.Font = Enum.Font.GothamBlack
		text.TextScaled = true
		text.TextColor3 = color or Config.Tools.pintura.color
		text.TextStrokeTransparency = 0.25
		text.Text = labelText or "¡PINTADO!"
		text.Parent = tag
	end

	task.delay(duration, function()
		if highlight.Parent then
			highlight:Destroy()
		end
		if tag and tag.Parent then
			tag:Destroy()
		end
	end)
end

function Actions.paintPlayer(session, victim, shooter, pos, color)
	local character = victim.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")

	if humanoid then
		humanoid:SetAttribute("Pintado", true)
		humanoid.WalkSpeed = Config.Player.walkSpeed * Config.PaintRifle.slowFactor
		task.delay(Config.PaintRifle.slowTime, function()
			if humanoid.Parent then
				humanoid:SetAttribute("Pintado", false)
				humanoid.WalkSpeed = Config.Player.walkSpeed
			end
		end)
	end

	Actions.markCharacter(character, color, Config.PaintRifle.markTime)

	local function nameOf(target)
		return target.DisplayName ~= "" and target.DisplayName or target.Name
	end

	session:notify(shooter, string.format(Config.Text.PaintHit, nameOf(victim)), color)
	session:notify(victim, string.format(Config.Text.PaintVictim, nameOf(shooter)), color)
end

function Actions.resolvePaint(session, shot, hit, victim)
	-- Al kiwi lo deja marcado un rato: mas facil de seguir
	local kiwi = session.kiwi
	if kiwi and not kiwi.defeated and hit.Instance:IsDescendantOf(kiwi.model) then
		Actions.markCharacter(kiwi.model, shot.color, Config.PaintRifle.kiwiMarkTime, "¡KIWI PINTADO!", 1)
		session:event("painthit", { pos = hit.Position, color = Util.colorToTable(shot.color) })
		session:notify(shot.player, Config.Text.PaintKiwiMark, Config.Tools.pintura.color)
		return
	end

	if victim and victim ~= shot.player and session.stats[victim] then
		Actions.paintPlayer(session, victim, shot.player, hit.Position, shot.color)
		session:event("painthit", { pos = hit.Position, color = Util.colorToTable(shot.color) })
		return
	end

	-- Si le pegaste a algo (piso, pared), solo queda la mancha
	session:event("paintmiss", { pos = hit.Position, normal = hit.Normal, color = Util.colorToTable(shot.color) })
end

-- ===============================================================
-- TRAMPA DE FRUTA
-- ===============================================================
function Actions.makeTrapModel(pos)
	local model = Instance.new("Model")
	model.Name = "TrampaDeFruta"
	model.Parent = workspace

	local base = Util.makePart({
		Name = "Base",
		Size = Vector3.new(2.0, 0.22, 2.0),
		Color = Color3.fromRGB(120, 92, 60),
		Material = Enum.Material.Wood,
		Anchored = true,
		CanCollide = false,
		CanQuery = false,
		CanTouch = false,
		CFrame = CFrame.new(pos + Vector3.new(0, 0.11, 0)),
		Parent = model,
	})

	for i = 1, 4 do
		local angle = math.rad(45 + (i - 1) * 90)
		Util.makePart({
			Name = "Varilla" .. i,
			Size = Vector3.new(0.14, 2.1, 0.14),
			Color = Color3.fromRGB(150, 118, 80),
			Material = Enum.Material.Wood,
			Anchored = true,
			CanCollide = false,
			CanQuery = false,
			CanTouch = false,
			CFrame = CFrame.new(pos + Vector3.new(math.cos(angle) * 0.85, 1.0, math.sin(angle) * 0.85))
				* CFrame.Angles(math.rad(18), 0, math.rad(-18)),
			Parent = model,
		})
	end

	Util.makePart({
		Name = "Fruta",
		Shape = Enum.PartType.Ball,
		Size = Vector3.new(0.7, 0.7, 0.7),
		Color = Color3.fromRGB(226, 70, 80),
		Material = Enum.Material.SmoothPlastic,
		Anchored = true,
		CanCollide = false,
		CanQuery = false,
		CanTouch = false,
		CFrame = CFrame.new(pos + Vector3.new(0, 0.55, 0)),
		Parent = model,
	})

	local glow = Instance.new("PointLight")
	glow.Color = Color3.fromRGB(255, 130, 120)
	glow.Range = 10
	glow.Brightness = 0.8
	glow.Parent = base

	return model
end

function Actions.trap(session, player, data)
	local cfg = Config.Trampa
	local character, root = getRoot(player)
	if not root then
		return
	end

	if ToolService.getRemaining(player, "trampa") > 0 then
		return
	end

	local muzzle = root.Position + Vector3.new(0, 1.1, 0)
	local aim = data and data.aim
	local target
	if typeof(aim) == "Vector3" then
		target = aim
	else
		target = muzzle + root.CFrame.LookVector * 10
	end

	local toTarget = flat(target - muzzle)
	if toTarget.Magnitude > cfg.placeRange then
		toTarget = toTarget.Unit * cfg.placeRange
	end

	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Include
	params.FilterDescendantsInstances = { session.arena.ground }
	params.IgnoreWater = true

	local probe = root.Position + toTarget + Vector3.new(0, 12, 0)
	local groundHit = workspace:Raycast(probe, Vector3.new(0, -90, 0), params)

	local groundPos
	if groundHit then
		groundPos = groundHit.Position
	else
		local fallback = root.Position + flat(root.CFrame.LookVector) * 8
		groundPos = Vector3.new(fallback.X, session.arena.floorY, fallback.Z)
	end
	groundPos = session.arena:clampToBounds(groundPos)

	ToolService.startCooldown(player, "trampa", cfg.cooldown)
	session:placeTrap(player, groundPos)
	session:notify(player, Config.Text.TrapPlaced, Config.Tools.trampa.color)
	session:event("trap", { pos = groundPos, userId = player.UserId })
end

-- ===============================================================
-- RASTREADOR
-- ===============================================================
function Actions.tracker(session, player)
	local trackerCfg = Config.Tracker
	if ToolService.getRemaining(player, "rastreador") > 0 then
		return
	end

	ToolService.startCooldown(player, "rastreador", trackerCfg.cooldown)

	local kiwi = session.kiwi
	local _, root = getRoot(player)
	if not kiwi or kiwi.defeated or not root then
		session:notify(player, Config.Text.TrackerNothing, Color3.fromRGB(200, 200, 200))
		return
	end

	local kiwiPos = kiwi:getPosition()
	local distance = flatDistance(kiwiPos, root.Position)
	if distance > trackerCfg.range then
		session:notify(player, Config.Text.TrackerNothing, Color3.fromRGB(200, 200, 200))
		return
	end

	Net.get("TrackerPing"):FireClient(player, {
		pos = kiwiPos,
		hidden = kiwi:isHidden(),
		state = session.diff.showKiwiState and kiwi:getStateHint() or nil,
		distance = distance,
		duration = trackerCfg.duration,
	})

	session:notify(player, Config.Text.TrackerFound, Color3.fromRGB(120, 220, 170))
	session:event("ping", { pos = kiwiPos, userId = player.UserId })
end

-- ===============================================================
-- Punto de entrada
-- ===============================================================
local function hasTool(player, toolId)
	local containers = { player:FindFirstChildOfClass("Backpack"), player.Character }
	for _, container in ipairs(containers) do
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

function Actions.run(session, player, toolId, data)
	if session.phase ~= "playing" then
		return
	end

	local alive, root = getRoot(player)
	if not root or not alive:FindFirstChildOfClass("Humanoid") then
		return
	end

	if not hasTool(player, toolId) then
		return
	end

	data = data or {}

	if toolId == "red" then
		Actions.net(session, player, data)
	elseif toolId == "rifle" then
		Actions.rifle(session, player, data)
	elseif toolId == "rastreador" then
		Actions.tracker(session, player, data)
	elseif toolId == "trampa" then
		Actions.trap(session, player, data)
	elseif toolId == "pintura" then
		Actions.paint(session, player, data)
	elseif toolId == "relente" then
		Actions.relente(session, player, data)
	elseif Config.Weapons[toolId] then
		Actions.fireWeapon(session, player, toolId, data)
	end
end

return Actions
