--[[
	Util.lua
	Ayudantes pequenos y sin estado que usan tanto el servidor como el cliente.
--]]

local TweenService = game:GetService("TweenService")
local Debris = game:GetService("Debris")

local Util = {}

function Util.clamp(value, min, max)
	if value < min then
		return min
	elseif value > max then
		return max
	end
	return value
end

function Util.lerp(a, b, t)
	return a + (b - a) * t
end

function Util.round(n)
	return math.floor(n + 0.5)
end

function Util.formatTime(seconds)
	seconds = math.max(0, math.floor(seconds))
	local minutes = math.floor(seconds / 60)
	return string.format("%d:%02d", minutes, seconds % 60)
end

-- Distancia ignorando el eje Y: casi siempre queremos distancia "en el suelo"
function Util.flatDistance(a, b)
	local dx = a.X - b.X
	local dz = a.Z - b.Z
	return math.sqrt(dx * dx + dz * dz)
end

function Util.newRandom(seed)
	return Random.new(seed or os.time())
end

function Util.shuffle(list, rng)
	rng = rng or Random.new()
	for i = #list, 2, -1 do
		local j = rng:NextInteger(1, i)
		list[i], list[j] = list[j], list[i]
	end
	return list
end

function Util.pick(list, rng)
	rng = rng or Random.new()
	return list[rng:NextInteger(1, #list)]
end

--[[
	Util.makePart{ ClassName = "Part", Name = ..., Size = ..., ... }
	Crea una instancia y le aplica todas las propiedades indicadas.
	Parent se asigna al final (es mas rapido y evita que la parte
	provoque replicacion a medio configurar).
--]]
function Util.makePart(props)
	local className = props.ClassName or "Part"
	local instance = Instance.new(className)

	for key, value in pairs(props) do
		if key ~= "ClassName" and key ~= "Parent" then
			instance[key] = value
		end
	end

	if props.Parent then
		instance.Parent = props.Parent
	end

	return instance
end

-- Parte "sosa": anclada, sin colisiones raras y sin caras con textura
function Util.makeSolid(props)
	props = props or {}
	if props.Anchored == nil then props.Anchored = true end
	props.CanCollide = props.CanCollide == true
	props.CanQuery = props.CanQuery ~= false
	props.CanTouch = props.CanTouch == true
	props.TopSurface = Enum.SurfaceType.Smooth
	props.BottomSurface = Enum.SurfaceType.Smooth
	return Util.makePart(props)
end

function Util.hideStuds(part)
	if part:IsA("BasePart") then
		if part.TopSurface ~= nil and (part:IsA("Part") or part:IsA("WedgePart")) then
			part.TopSurface = Enum.SurfaceType.Smooth
			part.BottomSurface = Enum.SurfaceType.Smooth
		end
	end
	return part
end

function Util.tween(instance, goal, time, style, direction)
	local info = TweenInfo.new(
		time or 0.25,
		style or Enum.EasingStyle.Quad,
		direction or Enum.EasingDirection.Out
	)
	local tween = TweenService:Create(instance, info, goal)
	tween:Play()
	return tween
end

function Util.destroyAfter(instance, seconds)
	Debris:AddItem(instance, seconds)
	return instance
end

-- Color3 -> {r, g, b} en 0..255 (util para mandar color por RemoteEvent)
function Util.colorToTable(color)
	return { math.floor(color.R * 255), math.floor(color.G * 255), math.floor(color.B * 255) }
end

function Util.colorFromTable(t)
	if type(t) ~= "table" then
		return Color3.fromRGB(255, 255, 255)
	end
	return Color3.fromRGB(t[1] or 255, t[2] or 255, t[3] or 255)
end

return Util
