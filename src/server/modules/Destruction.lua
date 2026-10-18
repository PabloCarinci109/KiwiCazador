--[[
	Destruction.lua  (servidor)
	Objetos rompibles del mapa: casas, graneros, autos, colectivo, tren
	y arboles. El lanzamisiles es lo unico que los destroza: al impacto,
	las partes marcadas dentro del radio se sueltan (Anchored = false) y
	salen despedidas. A los ~32 segundos el mapa se recompone solo, asi
	la partida sigue jugable ronda tras ronda.

	WorldBuilder marca las partes al construir
	(Destruction.marcar / registrarLista / registrarModelo) y Actions
	dispara Destruction.explosivo cuando estalla un cohete.
--]]

local Destruction = {}

local REPARACION = 32    -- segundos hasta que las partes vuelven a su lugar
local MAX_PARTES = 260   -- tope de partes sueltas por explosion (fisica sana)

local grupos = {}        -- { {tipo, partes = {{p, cf, anc}}, model, roto, suma, n} }

local function grupoNuevo(tipo, model)
	local g = {
		tipo = tipo, model = model, partes = {}, roto = false,
		suma = Vector3.new(0, 0, 0), n = 0,
	}
	table.insert(grupos, g)
	return g
end

local function sumarParte(g, p)
	if not p or not p:IsA("BasePart") then
		return
	end
	g.n = g.n + 1
	g.suma = g.suma + p.Position
	table.insert(g.partes, { p = p, cf = p.CFrame, anc = p.Anchored })
end

-- Una parte suelta (casas: se marca cada pared, piso, mueble, etc.)
function Destruction.marcar(p, tipo)
	local g = grupoNuevo(tipo or "casa")
	sumarParte(g, p)
end

-- Varias partes que vuelan juntas (arboles: tronco + copas)
function Destruction.registrarLista(tipo, lista)
	local g = grupoNuevo(tipo)
	for _, p in ipairs(lista) do
		sumarParte(g, p)
	end
end

-- Un modelo entero (autos, colectivo, tren)
function Destruction.registrarModelo(model, tipo)
	local g = grupoNuevo(tipo, model)
	for _, d in ipairs(model:GetDescendants()) do
		if d:IsA("BasePart") then
			sumarParte(g, d)
		end
	end
end

-- Cuantas partes rompibles hay en el mapa (lo usa el AutoTest)
function Destruction.count()
	local total = 0
	for _, g in ipairs(grupos) do
		total = total + #g.partes
	end
	return total
end

function Destruction.limpiar()
	grupos = {}
end

local function romper(g, pos, potencia, radio)
	g.roto = true
	local vehiculo = g.tipo == "vehiculo" and g.model
	if vehiculo and vehiculo.Parent then
		vehiculo:SetAttribute("KiwiRoto", true)
	end
	for _, e in ipairs(g.partes) do
		local p = e.p
		if p.Parent then
			p.Anchored = false
			local away = p.Position - pos
			if away.Magnitude < 0.8 then
				away = Vector3.new(0, 1, 0)
			end
			local fuerza = math.clamp(1 - (away.Magnitude / (radio + 6)), 0.35, 1)
			p.AssemblyLinearVelocity = away.Unit * potencia * fuerza
				+ Vector3.new(0, potencia * 0.32 * fuerza, 0)
			p.AssemblyAngularVelocity = Vector3.new(
				(math.random() - 0.5) * 12,
				(math.random() - 0.5) * 12,
				(math.random() - 0.5) * 12)
		end
	end

	-- Se recompone solo: el mapa no queda roto para siempre
	task.delay(REPARACION, function()
		for _, e in ipairs(g.partes) do
			local p = e.p
			if p.Parent then
				p.AssemblyLinearVelocity = Vector3.new(0, 0, 0)
				p.AssemblyAngularVelocity = Vector3.new(0, 0, 0)
				p.CFrame = e.cf
				p.Anchored = e.anc
			end
		end
		if vehiculo and vehiculo.Parent then
			vehiculo:SetAttribute("KiwiRoto", false)
		end
		g.roto = false
	end)
end

-- Estallido del lanzamisiles: rompe lo marcado dentro del radio
function Destruction.explosivo(pos, radio, potencia)
	radio = radio or 24
	potencia = math.clamp(potencia or 60, 20, 90)
	local candidatos = {}
	for _, g in ipairs(grupos) do
		if not g.roto and g.n > 0 then
			local centro = g.suma / g.n
			local d = (centro - pos).Magnitude
			if d <= radio then
				table.insert(candidatos, { g = g, d = d })
			end
		end
	end
	table.sort(candidatos, function(a, b)
		return a.d < b.d
	end)
	local partes = 0
	for _, c in ipairs(candidatos) do
		if partes + #c.g.partes > MAX_PARTES then
			break
		end
		partes = partes + #c.g.partes
		romper(c.g, pos, potencia, radio)
	end
end

return Destruction
