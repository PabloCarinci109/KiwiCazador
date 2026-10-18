--[[
	KiwiModel.lua  (servidor)
	Construye el kiwi usando puras Parts (sin meshes ni animaciones
	externas) y expone :update() para posarlo cuadro a cuadro.

	El modelo mira hacia -Z, que es la direccion "adelante" de Roblox,
	asi que funciona directo con CFrame.lookAt().
--]]

local KiwiModel = {}
KiwiModel.__index = KiwiModel

local COLORS = {
	body = Color3.fromRGB(112, 84, 62),
	head = Color3.fromRGB(122, 94, 70),
	beak = Color3.fromRGB(216, 196, 168),
	leg = Color3.fromRGB(198, 172, 138),
	eye = Color3.fromRGB(22, 18, 16),
}

local BODY_SIZE = Vector3.new(2.2, 2.1, 2.9)
local HEAD_OFFSET = Vector3.new(0, 0.80, -1.15)
local HEAD_SIZE = Vector3.new(1.5, 1.35, 1.5)
local LEG_LENGTH = 1.0
local HIP_OFFSET = Vector3.new(0.5, -0.70, 0.10)

-- Altura a la que debe ir el centro del cuerpo para que las patas toquen el suelo
KiwiModel.RideHeight = 1.78

local function piece(className, name, size, color, material, shape, parent)
	local part = Instance.new(className)
	part.Name = name
	part.Size = size
	part.Color = color
	part.Material = material
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = true
	part.CanTouch = false
	if shape then
		part.Shape = shape
	end
	if part:IsA("Part") then
		part.TopSurface = Enum.SurfaceType.Smooth
		part.BottomSurface = Enum.SurfaceType.Smooth
	end
	part.Parent = parent
	return part
end

function KiwiModel.build(parent, scale)
	local self = setmetatable({}, KiwiModel)
	local S = scale or 1

	local model = Instance.new("Model")
	model.Name = "Kiwi"
	model.Parent = parent

	local body = piece("Part", "Cuerpo", BODY_SIZE * S, COLORS.body, Enum.Material.Fabric, Enum.PartType.Ball, model)
	local head = piece("Part", "Cabeza", HEAD_SIZE * S, COLORS.head, Enum.Material.Fabric, Enum.PartType.Ball, model)
	local beak = piece("Part", "Pico", Vector3.new(1.25, 0.26, 0.26) * S, COLORS.beak, Enum.Material.SmoothPlastic, Enum.PartType.Cylinder, model)

	local eyes = {}
	for i = 1, 2 do
		local eye = piece("Part", "Ojo" .. i, Vector3.new(0.26, 0.26, 0.26) * S, COLORS.eye, Enum.Material.SmoothPlastic, Enum.PartType.Ball, model)
		eyes[i] = eye
	end

	local legs = {}
	for i = 1, 2 do
		local side = (i == 1) and -1 or 1
		local legPart = piece("Part", "Pata" .. i, Vector3.new(0.18 * S, LEG_LENGTH * S, 0.18 * S), COLORS.leg, Enum.Material.SmoothPlastic, Enum.PartType.Cylinder, model)
		legPart.Shape = Enum.PartType.Block
		local foot = piece("Part", "Pie" .. i, Vector3.new(0.42, 0.14, 0.78) * S, COLORS.leg, Enum.Material.SmoothPlastic, Enum.PartType.Block, model)
		legs[i] = {
			part = legPart,
			foot = foot,
			hip = Vector3.new(HIP_OFFSET.X * side * S, HIP_OFFSET.Y * S, HIP_OFFSET.Z * S),
			phaseOffset = (i == 1) and 0 or math.pi,
		}
	end

	-- Cola: un mechon chiquito, los kiwis no tienen cola de verdad
	local tail = piece("Part", "Cola", Vector3.new(0.8, 0.4, 0.5) * S, COLORS.body, Enum.Material.Fabric, Enum.PartType.Ball, model)

	local parts = { body, head, beak, eyes[1], eyes[2], legs[1].part, legs[1].foot, legs[2].part, legs[2].foot, tail }

	self.model = model
	self.body = body
	self.head = head
	self.beak = beak
	self.eyes = eyes
	self.legs = legs
	self.tail = tail
	self.parts = parts
	self.scale = S
	self.legLength = LEG_LENGTH * S
	self.rideHeight = KiwiModel.RideHeight * S

	model.PrimaryPart = body
	self:setVisible(false)
	return self
end

--[[
	Visibilidad / interaccion. Cuando el kiwi esta escondido se vuelve
	invisible y deja de ser detectable por rayos (los dardos pasan de largo).
--]]
function KiwiModel:setVisible(visible, camoAlpha)
	self.visible = visible
	local alpha = 0
	if not visible then
		alpha = camoAlpha or 1
	end
	for _, part in ipairs(self.parts) do
		part.Transparency = alpha
		part.CanQuery = visible
	end
	self.body.CanTouch = false
end

function KiwiModel:setTouchable(touchable)
	self.body.CanTouch = touchable
end

function KiwiModel:setColorTint(color)
	self.body.Color = color
	self.head.Color = color
	self.tail.Color = color
end

function KiwiModel:getPosition()
	return self.body.CFrame.Position
end

--[[
	update(rootCF, pose)
	rootCF : CFrame del centro del cuerpo (posicion + giro + balanceo)
	pose   : {
		phase     = angulo de animacion de las patas,
		legSwing  = 0..1 amplitud del paso,
		headPitch = radianes (positivo = mira al suelo),
		legFold   = 0..1 patas encogidas (dormido),
		beak      = radianes (abre el pico al comer),
	}
--]]
function KiwiModel:update(rootCF, pose)
	pose = pose or {}
	local S = self.scale or 1

	local bodyCF = rootCF
	self.body.CFrame = bodyCF
	self.tail.CFrame = bodyCF * CFrame.new(0, 0.15 * S, 1.45 * S)

	local legSwing = pose.legSwing or 0
	local legFold = pose.legFold or 0

	local headCF = bodyCF * CFrame.new(HEAD_OFFSET * S) * CFrame.Angles(pose.headPitch or 0, 0, 0)
	self.head.CFrame = headCF
	self.beak.CFrame = headCF * CFrame.new(0, -0.16 * S, -0.72 * S) * CFrame.Angles(math.rad(-12), math.rad(90), 0)
		* CFrame.Angles(0, pose.beak or 0, 0)
	self.eyes[1].CFrame = headCF * CFrame.new(-0.42 * S, 0.16 * S, -0.52 * S)
	self.eyes[2].CFrame = headCF * CFrame.new(0.42 * S, 0.16 * S, -0.52 * S)

	for _, leg in ipairs(self.legs) do
		local angle = math.sin((pose.phase or 0) + leg.phaseOffset) * legSwing
		local hip = bodyCF * CFrame.new(leg.hip)
		local full = hip * CFrame.Angles(angle, 0, 0)
		local length = self.legLength * (1 - 0.45 * legFold)
		leg.part.CFrame = full * CFrame.new(0, -length * 0.5, 0)
		leg.part.Size = Vector3.new(0.18 * S, length, 0.18 * S)
		leg.foot.CFrame = full * CFrame.new(0, -length, -0.16 * S)
	end
end

function KiwiModel:destroy()
	if self.model then
		self.model:Destroy()
		self.model = nil
	end
end

return KiwiModel
