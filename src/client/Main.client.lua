--[[
	Main.client.lua  (cliente)
	Une todo del lado del jugador:
		- menu del lobby y HUD
		- teclas de correr (Shift) y sigilo (Ctrl)
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

local player = Players.LocalPlayer
local remotes = Net.init()

local state = { active = false, phase = "none", diff = nil }
local sprinting = false
local sneaking = false
local shotBloom = 0 -- el punto de mira se abre un toque al disparar
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
local firstPerson = false -- vista en primera persona (tecla V)

local function applySpeed()
	local hum = humanoid()
	if not hum then
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

	if not state.active then
		if hum.WalkSpeed ~= Config.Player.walkSpeed then
			hum.WalkSpeed = Config.Player.walkSpeed
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
		hum.WalkSpeed = Config.Player.sprintSpeed
	else
		hum.WalkSpeed = Config.Player.walkSpeed
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
	local first = scoped or (firstPerson and state.active and state.phase == "playing")
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

-- Armas que apuntan (y que por lo tanto muestran la vista de arma)
local SCOPE_WEAPONS = {
	rifle = true, pintura = true, relente = true, revolver = true,
	arco = true, sniper = true, cuchillo = true, lanzallamas = true, cohete = true,
}

-- Vista de arma estilo Counter: se ve en primera persona y al apuntar.
-- Con la telescopica puesta el arma se esconde (solo queda la mira).
local function refreshViewmodel()
	local playing = state.active and state.phase == "playing"
	local show = playing and (scoped or firstPerson)
	ViewModel.setWeapon(equippedId)
	ViewModel.setVisible(show)
	ViewModel.setAds(scoped and equippedId ~= "sniper" and 1 or 0)
	ViewModel.setHidden(scoped and equippedId == "sniper")
	-- El arma "de verdad" del personaje se esconde cuando manda la vista
	setWeaponHidden(scoped or (show and ViewModel.hasWeapon(equippedId)))
end

local function scopeFov(id, level)
	local weapons = Config.Scope.weapons or {}
	if id == "sniper" then
		return (level or 1) >= 2 and (weapons.sniper2 or 7) or (weapons.sniper or 14)
	end
	return weapons[id] or Config.Scope.fov
end

local function setScope(enabled, level)
	enabled = enabled and true or false
	local lvl = enabled and math.max(1, level or 1) or 0
	if scoped == enabled and scopeLevel == lvl then
		return
	end
	scoped = enabled
	scopeLevel = lvl

	-- Telescopica del francotirador: pantalla negra con circulo (Counter)
	local sniperScope = scoped and equippedId == "sniper"
	HUD.setScope(scoped, sniperScope)
	if sniperScope then
		HUD.setScopeZoom(lvl >= 2 and "10x" or "5x")
	end

	refreshViewmodel()
	UserInputService.MouseIconEnabled = not scoped

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
	UserInputService.MouseBehavior = scoped and Enum.MouseBehavior.LockCenter or Enum.MouseBehavior.Default
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

	remotes.ToolAction:FireServer(toolId, { aim = aimPoint(), scoped = scoped, sneak = sneaking })

	local total = cooldown and cooldown.total or 1
	if cooldown then
		cooldown.left = total
	end

	if toolId == "red" then
		sound2D(Config.Sounds.netSwing, 0.8)
	elseif toolId == "rifle" then
		sound2D(Config.Sounds.dartShot, 0.8)
	elseif toolId == "trampa" then
		sound2D(Config.Sounds.trapSet, 0.6, 0.8)
	elseif toolId == "pintura" then
		sound2D(Config.Sounds.paintShot, 0.7)
	elseif toolId == "relente" then
		sound2D(Config.Sounds.dartShot, 0.8, 1.2)
	elseif toolId == "cohete" then
		sound2D(Config.Sounds.dartShot, 1, 0.55)
	elseif toolId == "revolver" then
		sound2D(Config.Sounds.dartHit, 0.5, 1.6)
	elseif toolId == "arco" then
		sound2D(Config.Sounds.netSwing, 0.6, 1.4)
	elseif toolId == "sniper" then
		sound2D(Config.Sounds.dartShot, 0.95, 0.72)
	elseif toolId == "cuchillo" then
		sound2D(Config.Sounds.netSwing, 0.55, 1.3)
	elseif toolId == "lanzallamas" then
		sound2D(Config.Sounds.dartShot, 0.7, 0.55)
	end

	-- Patada del arma (estilo Counter)
	local RECOIL = {
		rifle = 0.45, pintura = 0.45, relente = 0.45, sniper = 1.1,
		revolver = 0.7, cohete = 1.0, arco = 0.5, cuchillo = 0.35, lanzallamas = 0.3,
	}
	ViewModel.recoil(RECOIL[toolId] or 0)
	ViewModel.flash()

	-- Patada de camara estilo Counter Blox: 2 * (1 - control) grados
	local shootCfg = Config.Shoot and Config.Shoot.weapons and Config.Shoot.weapons[toolId]
	local control = shootCfg and shootCfg.recoil or 72
	local kick = math.rad(2 * (1 - control / 100))
	ViewModel.kickCamera(kick * (1 + math.random() * 0.5), kick * (math.random() * 4 - 2))

	shotBloom = math.min(20, shotBloom + 8)
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
	if input.UserInputType == Enum.UserInputType.MouseButton2 then
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
	if input.KeyCode == Enum.KeyCode.LeftShift then
		sprinting = true
		applySpeed()
	elseif input.KeyCode == Enum.KeyCode.Tab then
		HUD.setScoreboardVisible(true)
	elseif input.KeyCode == Enum.KeyCode.LeftControl or input.KeyCode == Enum.KeyCode.LeftAlt
		or input.KeyCode == Enum.KeyCode.C then
		sneaking = true
		applySpeed()
	elseif input.KeyCode == Enum.KeyCode.V then
		if state.active and state.phase == "playing" then
			firstPerson = not firstPerson
			applyCameraMode()
			refreshViewmodel()
			sound2D(Config.Sounds.ui, 0.35)
		end
	end
end)

UserInputService.InputEnded:Connect(function(input)
	if input.KeyCode == Enum.KeyCode.LeftShift then
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
-- Punto de mira estilo Counter: se abre al moverse o disparar
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
	local error = math.max(cfg.spread or 0, 0) + speed * (cfg.vel or 0)
	if scoped then
		error = cfg.adsPerfect and 0 or error * ((Config.Shoot and Config.Shoot.adsDiv) or 0.35)
	elseif sneaking then
		error = error / ((Config.Shoot and Config.Shoot.crouchDiv) or 1.6)
	end
	local dead = cfg.dead or (Config.Shoot and Config.Shoot.dead) or 0
	if error < dead then
		error = 0
	end
	return error / ((Config.Shoot and Config.Shoot.div) or 6)
end

local lastCross = nil
RunService.RenderStepped:Connect(function(dt)
	shotBloom = math.max(0, shotBloom - dt * 30)
	local show = state.active and state.phase == "playing" and not scoped and not hiddenNow
		and equippedId ~= nil and ViewModel.hasWeapon(equippedId)
	if show ~= lastCross then
		lastCross = show
		HUD.setCrosshair(show, 6, 9)
	end
	if show then
		local grados = spreadErrorLocal(equippedId)
		HUD.setCrosshair(true, 5 + math.min(grados * 5, 30) + shotBloom * 0.55,
			7 + math.min(grados * 2, 10))
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
		setScope(false)
		refreshViewmodel()
		HUD.hideResult()
		HUD.hideVote()
		HUD.setMenuVisible(true)
		HUD.setMenuStatus("")
		HUD.fade(false, 0.5)
		applySpeed()
		return
	end

	state.active = true
	state.phase = newState.phase
	state.modeId = newState.modeId
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
		firstPerson = state.hidden
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
	elseif kind == "dartshot" then
		soundAt(Config.Sounds.dartShot, position or Vector3.new(), 0.9)
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
			soundAt(Config.Sounds.dartHit, position, 1, 0.6)
			burst(position, (cfg and cfg.color) or Color3.fromRGB(255, 186, 120), 46)
			if distanceToLocal(position) < 70 then
				sound2D(Config.Sounds.roar, 0.5, 0.7)
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
			for i = 1, 5 do
				task.delay(i * 0.055, function()
					burst(position + dir * (2 + i * 2.3), Color3.fromRGB(255, 140 + i * 14, 60), 16)
				end)
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
			firstPerson = false
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
			firstPerson = false
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
HUD.init(player:WaitForChild("PlayerGui"), {
	onJoin = function(modeId)
		sound2D(Config.Sounds.ui, 0.6)
		HUD.setMenuStatus("Entrando a la partida...", Color3.fromRGB(238, 196, 92))
		remotes.RequestJoin:FireServer(modeId)
	end,
	onVote = function(mapId)
		sound2D(Config.Sounds.ui, 0.5)
		remotes.VoteMap:FireServer(mapId)
	end,
	onLeave = function()
		sound2D(Config.Sounds.ui, 0.5)
		remotes.RequestLeave:FireServer()
	end,
})

-- ===============================================================
-- Bucle del cliente
-- ===============================================================
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

	local remaining = {}
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
