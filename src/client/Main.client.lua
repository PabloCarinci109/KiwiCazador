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

local player = Players.LocalPlayer
local remotes = Net.init()

local state = { active = false, phase = "none", diff = nil }
local sprinting = false
local sneaking = false
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

	hum.JumpPower = 50
	hum.UseJumpPower = true
	if sneaking then
		hum.WalkSpeed = Config.Player.sneakSpeed
	elseif sprinting then
		hum.WalkSpeed = Config.Player.sprintSpeed
	else
		hum.WalkSpeed = Config.Player.walkSpeed
	end
end

-- ===============================================================
-- Mira del rifle (clic derecho para apuntar)
-- ===============================================================
local scoped = false
local equippedId = nil
local firstPerson = false -- vista en primera persona (tecla V)

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

local function setScope(enabled)
	enabled = enabled and true or false
	if scoped == enabled then
		return
	end
	scoped = enabled
	HUD.setScope(scoped)
	setWeaponHidden(scoped)
	UserInputService.MouseIconEnabled = not scoped

	local hum = humanoid()
	if hum then
		hum.AutoRotate = not scoped
	end

	local camera = workspace.CurrentCamera
	if camera then
		local zoom = (Config.Scope.weapons and Config.Scope.weapons[equippedId]) or Config.Scope.fov
		local goal = scoped and zoom or 70
		TweenService:Create(camera, TweenInfo.new(0.18, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
			FieldOfView = goal,
		}):Play()
	end

	-- Apuntando se pasa a primera persona: la mira ya no tapa la cabeza
	UserInputService.MouseBehavior = scoped and Enum.MouseBehavior.LockCenter or Enum.MouseBehavior.Default
	applyCameraMode()

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
	if equippedId ~= "rifle" and equippedId ~= "pintura" and equippedId ~= "relente"
		and equippedId ~= "revolver" and equippedId ~= "arco" and equippedId ~= "sniper" then
		setScope(false)
	end
	setWeaponHidden(scoped)
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

	remotes.ToolAction:FireServer(toolId, { aim = aimPoint() })

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
	end
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
		-- Clic derecho: mira (rifle tranquilizante y rifle de pintura)
		if (equippedId == "rifle" or equippedId == "pintura" or equippedId == "relente"
			or equippedId == "revolver" or equippedId == "arco" or equippedId == "sniper")
			and state.active and state.phase == "playing" then
			setScope(not scoped)
		end
		return
	end
	if input.KeyCode == Enum.KeyCode.LeftShift then
		sprinting = true
		applySpeed()
	elseif input.KeyCode == Enum.KeyCode.LeftControl or input.KeyCode == Enum.KeyCode.LeftAlt then
		sneaking = true
		applySpeed()
	elseif input.KeyCode == Enum.KeyCode.V then
		if state.active and state.phase == "playing" then
			firstPerson = not firstPerson
			applyCameraMode()
			sound2D(Config.Sounds.ui, 0.35)
		end
	end
end)

UserInputService.InputEnded:Connect(function(input)
	if input.KeyCode == Enum.KeyCode.LeftShift then
		sprinting = false
		applySpeed()
	elseif input.KeyCode == Enum.KeyCode.LeftControl or input.KeyCode == Enum.KeyCode.LeftAlt then
		sneaking = false
		applySpeed()
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
			HUD.death("¡TE NOQUEARON!", "Vuelves al lobby...")
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
