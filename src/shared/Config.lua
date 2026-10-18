--[[
	Config.lua
	Configuracion central de "Kiwi Cazador".
	Todo el balance del juego vive aqui: cambia estos numeros para
	hacer la caceria mas facil, mas dificil o simplemente distinta.

	Este modulo lo usan el servidor y el cliente, asi que solo debe
	contener datos (nada de logica con efectos).
--]]

local Config = {}

Config.Version = "1.3.0"
Config.GameName = "Kiwi Cazador"
Config.GameTagline = "Reserva de vida silvestre de Nueva Zelanda"

-- ===============================================================
-- MUNDO
-- ===============================================================
Config.World = {
	ArenaCount = 5,           -- cuantas partidas pueden correr a la vez
	ArenaSize = 560,          -- lado del terreno de cada arena (studs)
	ArenaSpacing = 900,       -- distancia entre el centro de cada arena
	Seed = 421337,            -- semilla base de los mapas
	RandomMaps = true,        -- cada servidor genera mapas distintos (escondites aleatorios)
	FloorY = 0,               -- altura del suelo
	VoidY = -70,              -- si un jugador baja de aqui, se le rescata
	Gravity = 165,
}

Config.Lobby = {
	Size = 140,
	SpawnOffset = Vector3.new(0, 5, 34),
}

-- Mapas jugables: cada arena es un mapa distinto y se eligen por votacion.
-- id: se usa en la votacion; theme: como se construye el mapa.
Config.Zones = {
	{
		id = "bosque", name = "Bosque de Kauri", theme = "bosque",
		hint = "Arboles gigantes y helechos",
		grass = Color3.fromRGB(74, 118, 72), ground = Enum.Material.LeafyGrass,
		tree = Color3.fromRGB(88, 62, 44),
		wall = Color3.fromRGB(204, 190, 166), roof = Color3.fromRGB(148, 76, 54), floor = Color3.fromRGB(104, 84, 64),
		fence = Color3.fromRGB(96, 74, 52),
		pond = { color = Color3.fromRGB(64, 122, 150), material = Enum.Material.Water, scale = 1 },
	},
	{
		id = "dunas", name = "Dunas de Te Paki", theme = "dunas",
		hint = "Arena, cactus y medanos",
		grass = Color3.fromRGB(214, 188, 136), ground = Enum.Material.Sand,
		tree = Color3.fromRGB(122, 138, 82),
		wall = Color3.fromRGB(198, 172, 128), roof = Color3.fromRGB(150, 108, 72), floor = Color3.fromRGB(166, 138, 100),
		fence = Color3.fromRGB(158, 128, 88),
		pond = { color = Color3.fromRGB(74, 168, 160), material = Enum.Material.Water, scale = 0.7 },
	},
	{
		id = "ciudad", name = "Ciudad de Auckland", theme = "ciudad",
		hint = "Calles, plazas y torre mirador",
		grass = Color3.fromRGB(118, 120, 124), ground = Enum.Material.Concrete,
		tree = Color3.fromRGB(86, 96, 72),
		wall = Color3.fromRGB(196, 190, 182), roof = Color3.fromRGB(72, 76, 84), floor = Color3.fromRGB(96, 96, 100),
		fence = Color3.fromRGB(124, 126, 132),
		pond = false,
	},
	{
		id = "costa", name = "Costa de Totara", theme = "costa",
		hint = "Playa, palmeras y mar",
		grass = Color3.fromRGB(224, 204, 156), ground = Enum.Material.Sand,
		tree = Color3.fromRGB(118, 88, 58),
		wall = Color3.fromRGB(206, 196, 176), roof = Color3.fromRGB(96, 132, 140), floor = Color3.fromRGB(150, 126, 96),
		fence = Color3.fromRGB(120, 96, 66),
		pond = { color = Color3.fromRGB(38, 108, 158), material = Enum.Material.Water, scale = 1.7 },
	},
	{
		id = "alpes", name = "Alpes del Sur", theme = "alpes",
		hint = "Nieve, pinos y lago congelado",
		grass = Color3.fromRGB(238, 242, 248), ground = Enum.Material.Snow,
		tree = Color3.fromRGB(70, 56, 46),
		wall = Color3.fromRGB(160, 130, 96), roof = Color3.fromRGB(110, 78, 58), floor = Color3.fromRGB(104, 84, 66),
		fence = Color3.fromRGB(122, 98, 74),
		pond = { color = Color3.fromRGB(176, 214, 232), material = Enum.Material.Ice, scale = 1 },
	},
}

-- Votacion de mapa: al entrar a una partida cada jugador elige el mapa.
-- Con un solo jugador (o si todos ya votaron) arranca al instante.
Config.Vote = {
	multiTime = 18,    -- tiempo de votacion en Multijugador
	soloTime = 20,     -- tiempo maximo si el jugador no elige en modos solo
	revealTime = 1.2,  -- pausa despues del voto antes de la cuenta regresiva
}

-- Iluminacion por mapa: se aplica al arrancar la ronda y se restaura al salir.
-- ambient/outdoor/brightness: colores de luz; fog: niebla; clock: hora del dia.
Config.LightDefault = {
	ambient = Color3.fromRGB(70, 70, 70),
	outdoor = Color3.fromRGB(128, 128, 128),
	brightness = 2,
	fog = Color3.fromRGB(192, 192, 192),
	fogStart = 0,
	fogEnd = 100000,
	clock = 14,
}

Config.ZoneLight = {
	bosque = { ambient = Color3.fromRGB(74, 80, 70), outdoor = Color3.fromRGB(120, 130, 118), brightness = 2, fog = Color3.fromRGB(168, 188, 178), fogStart = 220, fogEnd = 950, clock = 15.2 },
	dunas = { ambient = Color3.fromRGB(118, 104, 84), outdoor = Color3.fromRGB(176, 154, 122), brightness = 2.6, fog = Color3.fromRGB(226, 202, 158), fogStart = 180, fogEnd = 850, clock = 14 },
	ciudad = { ambient = Color3.fromRGB(94, 98, 106), outdoor = Color3.fromRGB(132, 138, 148), brightness = 1.9, fog = Color3.fromRGB(176, 184, 196), fogStart = 200, fogEnd = 900, clock = 16.2 },
	costa = { ambient = Color3.fromRGB(108, 118, 130), outdoor = Color3.fromRGB(158, 172, 188), brightness = 2.4, fog = Color3.fromRGB(198, 218, 234), fogStart = 260, fogEnd = 1150, clock = 13.2 },
	alpes = { ambient = Color3.fromRGB(150, 160, 176), outdoor = Color3.fromRGB(202, 212, 226), brightness = 2.8, fog = Color3.fromRGB(224, 234, 246), fogStart = 200, fogEnd = 1000, clock = 12 },
}

-- ===============================================================
-- HERRAMIENTAS (nombre / descripcion que ve el jugador)
-- ===============================================================
Config.Tools = {
	order = { "red", "rifle", "rastreador", "trampa", "pintura", "relente" },
	red = {
		id = "red",
		name = "Red de Captura",
		tooltip = "Click: lanzar la red. Atrapa al kiwi de cerca.",
		color = Color3.fromRGB(96, 160, 220),
	},
	rifle = {
		id = "rifle",
		name = "Rifle Tranquilizante",
		tooltip = "Click: disparar un dardo. Duerme al kiwi unos segundos.",
		color = Color3.fromRGB(210, 180, 90),
	},
	rastreador = {
		id = "rastreador",
		name = "Rastreador",
		tooltip = "Click: pista de la dirección y distancia del kiwi.",
		color = Color3.fromRGB(102, 209, 150),
	},
	trampa = {
		id = "trampa",
		name = "Trampa de Fruta",
		tooltip = "Click: deja una fruta trampa. El kiwi hambriento cae solo.",
		color = Color3.fromRGB(238, 130, 150),
	},
	pintura = {
		id = "pintura",
		name = "Rifle de Pintura",
		tooltip = "Click: dispara pintura. En multijugador frena a los demás cazadores.",
		color = Color3.fromRGB(230, 120, 190),
	},
	relente = {
		id = "relente",
		name = "Rifle Ralentizador",
		tooltip = "Click: aguja que ralentiza al kiwi gigante unos segundos.",
		color = Color3.fromRGB(110, 220, 235),
	},
}

Config.Tracker = {
	cooldown = 8,      -- segundos entre pings
	duration = 8,      -- cuanto tiempo se ve la brujula con la pista
	range = 900,       -- distancia maxima para dar la pista
}

-- Mira (clic derecho para apuntar). Cada arma puede tener su zoom.
Config.Scope = {
	fov = 30,          -- campo de vision mientras apuntas (mas chico = mas zoom)
	weapons = {
		sniper = 16,   -- el francotirador tiene el zoom mas fuerte
		revolver = 34,
		arco = 28,
	},
}

-- Trampa de fruta: el kiwi hambriento va solo hacia la fruta...
Config.Trampa = {
	cooldown = 10,     -- segundos entre trampas
	maxActive = 1,     -- una sola por jugador (poner otra reemplaza la anterior)
	placeRange = 24,   -- hasta donde puede dejarla
	attractRadius = 450,-- la huele desde practicamente toda la arena
	temptEvery = 6,    -- cada cuantos segundos el kiwi piensa en la fruta
	playerAvoid = 10,  -- el kiwi no va si hay un jugador pegado a la fruta
	catchDist = 5,     -- que cerca tiene que llegar para caer
	holdTime = 3,      -- segundos que el kiwi queda enganchado antes de zafar
	escapeScare = 10,  -- segundos en que no vuelve a caer en otra fruta
}

-- Rifle de pintura (molesta a otros jugadores: los mancha y los frena)
Config.PaintRifle = {
	cooldown = 1.6,
	speed = 135,
	life = 2.2,
	slowTime = 3.0,
	slowFactor = 0.45,
	markTime = 15,     -- segundos que queda marcado un jugador (se ve entre paredes)
	kiwiMarkTime = 12, -- segundos que queda marcado el kiwi si lo pintan
}

-- Rifle ralentizador (aparece solo en Kiwi Colosal): no lo duerme, lo frena
Config.Relente = {
	cooldown = 2.2,
	speed = 150,
	life = 1.8,
	factor = 0.4,      -- multiplicador de velocidad del kiwi mientras esta lento
	time = 8,          -- segundos que dura la ralentizacion
}

-- Zona segura (meta del modo Colosal en solitario): llega al refugio para ganar
Config.SafeZone = {
	radius = 15,          -- radio del refugio (studs)
	activateAfter = 60,   -- cuando se activa (segundos desde que empieza la ronda)
	attractEvery = 2.5,   -- cada cuanto el kiwi corta el paso hacia el refugio
}

-- Escondites para jugadores (armarios, barriles, pajares): tecla E
Config.Hide = {
	enterRange = 10,      -- distancia maxima para meterse en un escondite
	smellIndoor = 0.45,   -- el kiwi huele menos si estas dentro de una casa
	sniffTime = 3.2,      -- segundos que el kiwi husmea un escondite ocupado
	sniffCooldown = 35,   -- espera del kiwi antes de rehusmear el mismo sitio
	escapeCoins = 3,      -- monedas por escaparle a una husmeada
}

-- Baules de armas: aparecen en las casas y por el mapa
Config.Loot = {
	uses = 3,             -- usos por arma encontrada
	pickupRange = 12,     -- distancia para abrir el baul
	weapons = {
		{ id = "cohete", weight = 4 },
		{ id = "revolver", weight = 3 },
		{ id = "arco", weight = 3 },
		{ id = "sniper", weight = 3 },
	},
}

Config.Weapons = {
	cohete = {
		name = "Lanzamisiles",
		color = Color3.fromRGB(226, 96, 70),
		cooldown = 4.5,
		speed = 92,
		life = 5,
		blast = 16,
		damage = 40,    -- daño a otros cazadores (al kiwi solo lo relentiza)
		knockback = 92,
		slowFactor = 0.12,
		slowTime = 2.6,
		size = Vector3.new(0.9, 0.9, 2.2),
	},
	revolver = {
		name = "Revólver",
		color = Color3.fromRGB(184, 186, 200),
		cooldown = 1.1,
		speed = 230,
		life = 1.6,
		blast = 0,
		damage = 20,
		knockback = 38,
		slowFactor = 0.55,
		slowTime = 1.6,
		size = Vector3.new(0.35, 0.35, 1.4),
	},
	arco = {
		name = "Arco y flecha",
		color = Color3.fromRGB(150, 196, 118),
		cooldown = 1.9,
		speed = 165,
		life = 2.6,
		blast = 9,
		damage = 26,
		knockback = 24,
		slowFactor = 0.35,
		slowTime = 3.2,
		size = Vector3.new(0.22, 0.22, 2.0),
	},
	sniper = {
		name = "Francotirador",
		color = Color3.fromRGB(150, 220, 190),
		cooldown = 2.8,
		speed = 420,
		life = 5,
		blast = 0,
		damage = 48,    -- el golpe mas fuerte contra otros cazadores
		knockback = 58,
		slowFactor = 0.30,
		slowTime = 2.0,
		size = Vector3.new(0.22, 0.22, 2.6),
	},
}

Config.Player = {
	walkSpeed = 16,
	sprintSpeed = 24,
	sneakSpeed = 7,
	maxHealth = 100,   -- vida de los cazadores (las armas de baul hieren)
	regen = 4,         -- vida por segundo fuera de combate
	regenDelay = 6,    -- segundos sin recibir daño para regenerar
}

-- ===============================================================
-- DIFICULTADES
-- ===============================================================
-- kiwi.*      -> cerebro y cuerpo del animal
-- red.*       -> red de captura
-- rifle.*     -> rifle tranquilizante
-- round.*     -> reglas de la partida
--
-- Redaccion rapida de los valores del kiwi:
--   detectionRadius : a que distancia te "ve" si estas en su campo de vision
--   alertGain       : que tan rapido se asusta con el estimulo (mayor = mas nervioso)
--   alertDecay      : que tan rapido se tranquiliza cuando no hay nadie
--   flushBase       : radio a tu alrededor en el que sale disparado aunque vayas despacio
--   stamina         : segundos que puede correr antes de cansarse
--   coverPreference : 0 = le da igual donde esconderse, 1 = siempre el mejor escondite
Config.Difficulties = {
	facil = {
		id = "facil",
		name = "Fácil",
		tag = "Aventura",
		color = Color3.fromRGB(102, 209, 130),
		blurb = "Kiwi lento y confiado. Perfecto para aprender el mapa.",
		showKiwiState = true,
		kiwi = {
			wanderSpeed = 10,
			relocateSpeed = 16,
			fleeSpeed = 21,
			tiredSpeed = 8,
			detectionRadius = 22,
			fieldOfView = 170,
			alertGain = 0.40,
			alertDecay = 0.55,
			flushBase = 6,
			hideMin = 3.0,
			hideMax = 6.5,
			stamina = 8,
			staminaRegen = 1.5,
			sedateTime = 7.0,
			coverPreference = 0.30,
			noHideAfterFlush = 3.0,
		},
		red = { range = 18, cooldown = 1.0, chance = 0.90 },
		rifle = { range = 170, cooldown = 3.0, speed = 105, cooldownOnMiss = 1.5 },
		round = { quota = 3, timeLimit = 420, reward = 45, winBonus = 120, timeBonus = 0.4 },
	},

	normal = {
		id = "normal",
		name = "Normal",
		tag = "Cacería",
		color = Color3.fromRGB(238, 196, 92),
		blurb = "El kiwi escucha tus pasos y corre cuando lo asustas.",
		showKiwiState = true,
		kiwi = {
			wanderSpeed = 12,
			relocateSpeed = 20,
			fleeSpeed = 25,
			tiredSpeed = 9,
			detectionRadius = 30,
			fieldOfView = 150,
			alertGain = 0.62,
			alertDecay = 0.38,
			flushBase = 9,
			hideMin = 4.0,
			hideMax = 9.0,
			stamina = 12,
			staminaRegen = 1.2,
			sedateTime = 5.0,
			coverPreference = 0.60,
			noHideAfterFlush = 4.0,
		},
		red = { range = 16, cooldown = 1.1, chance = 0.78 },
		rifle = { range = 160, cooldown = 3.5, speed = 110, cooldownOnMiss = 2.0 },
		round = { quota = 3, timeLimit = 360, reward = 80, winBonus = 220, timeBonus = 0.6 },
	},

	dificil = {
		id = "dificil",
		name = "Difícil",
		tag = "Pesadilla",
		color = Color3.fromRGB(232, 108, 100),
		blurb = "Rapidísimo, desconfiado y solo duerme un momento. Suerte.",
		showKiwiState = false,
		kiwi = {
			wanderSpeed = 15,
			relocateSpeed = 26,
			fleeSpeed = 31,
			tiredSpeed = 12,
			detectionRadius = 40,
			fieldOfView = 130,
			alertGain = 0.90,
			alertDecay = 0.22,
			flushBase = 13,
			hideMin = 6.0,
			hideMax = 13.0,
			stamina = 18,
			staminaRegen = 1.0,
			sedateTime = 3.5,
			coverPreference = 0.95,
			noHideAfterFlush = 5.0,
		},
		red = { range = 14, cooldown = 1.2, chance = 0.62 },
		rifle = { range = 150, cooldown = 4.0, speed = 115, cooldownOnMiss = 2.5 },
		round = { quota = 3, timeLimit = 300, reward = 140, winBonus = 420, timeBonus = 1.0 },
	},

	colosal = {
		id = "colosal",
		name = "Kiwi Colosal",
		tag = "¡Escóndete!",
		color = Color3.fromRGB(120, 209, 190),
		blurb = "Un kiwi gigante te busca por la reserva. Escóndete y sobrevive hasta que se aburra.",
		showKiwiState = true,
		giant = true,
		tools = { "rastreador", "relente" },
		kiwi = {
			patrolSpeed = 13,
			huntSpeed = 27,
			catchDist = 7,
			detectRadius = 80,
			noiseRadius = 130,
			loseInterest = 7,
			scale = 4.2,
			roarEvery = 18,
		},
		round = { quota = 1, timeLimit = 240, reward = 70, winBonus = 200, timeBonus = 0.5 },
	},
}

-- ===============================================================
-- MODO MULTIJUGADOR
-- ===============================================================
-- Reutiliza la configuracion del kiwi de baseDifficulty, pero las
-- reglas cambian: gana el primero que atrape al kiwi.
Config.Multiplayer = {
	id = "multi",
	name = "Multijugador",
	tag = "¡Supervivencia!",
	color = Color3.fromRGB(160, 140, 245),
	blurb = "El kiwi gigante va comiendo cazadores: gana el último que quede vivo.",
	tools = { "rastreador", "relente", "pintura" },
	baseDifficulty = "normal",
	maxPlayers = 12,
	timeLimit = 300,
	scoreboardSize = 8,     -- cuantas filas ve el jugador
}

-- Orden en que se muestran los botones del menu
Config.ModeOrder = { "facil", "normal", "dificil", "colosal", "multi" }

-- ===============================================================
-- RONDA
-- ===============================================================
Config.Round = {
	Countdown = 4,           -- "3, 2, 1..." antes de empezar
	EndScreen = 10,          -- segundos de pantalla de resultados
	UpdateInterval = 0.5,    -- cada cuanto se refresca el HUD
	KiwiRespawnDelay = 1.0,  -- espera entre capturas (modo solo)
	EatHold = 2.6,           -- cuanto dura "comerse" a un cazador (modo Colosal)
	KoHold = 1.8,            -- cuanto dura un noqueado antes de volver al lobby
	HubReturn = true,        -- devolver al lobby al terminar
}

-- ===============================================================
-- MENSAJES / TEXTOS
-- ===============================================================
Config.Text = {
	NoArena = "Todas las arenas están ocupadas. Intenta de nuevo en unos segundos.",
	AlreadyIn = "Ya estás en una partida.",
	KiwiHidden = "El kiwi se ha escondido...",
	KiwiRunning = "¡El kiwi corre entre los arbustos!",
	KiwiSleeping = "El kiwi está dormido: acércate y atrápalo.",
	NetHit = "¡Atrapaste al kiwi con la red!",
	NetMiss = "¡La red pasó de largo!",
	Flushed = "¡Lo sacaste de su escondite!",
	FlushFail = "Buscaste en un escondite vacío...",
	DartHit = "¡Dardo en el blanco! El kiwi está dormido.",
	DartMiss = "El dardo falló.",
	TrackerFound = "El rastreador detecta al kiwi",
	TrackerNothing = "El rastreador no capta nada cerca.",
	WakeUp = "¡El kiwi despertó y salió corriendo!",
	TrapPlaced = "Fruta colocada. Aléjate despacio y espera...",
	TrapCaptured = "¡El kiwi cayó en la trampa de fruta de %s!",
	TrapStuck = "¡El kiwi quedó atrapado en la fruta de %s! Tienes %d segundos para ir por él.",
	TrapEscaped = "¡El kiwi se soltó de la trampa y escapó!",
	TrapEaten = "El kiwi se comió la fruta y se fue...",
	PaintHit = "¡Diste a %s! Queda marcado un rato (se ve entre las paredes).",
	PaintVictim = "¡%s te manchó de pintura! Estás marcado y más lento.",
	PaintKiwiMark = "¡Pintaste al kiwi! Queda marcado un rato.",
	GiantFound = "%s fue descubierto por el kiwi gigante.",
	GiantSafe = "El kiwi gigante se aburrió de buscar. ¡Sobreviviste!",
	GiantEaten = "¡El kiwi gigante devoró a %s!",
	LastAlive = "¡%s es el último cazador en pie y gana la ronda!",
	SafeActive = "¡La ZONA SEGURA se activó! El kiwi te corta el paso: frénalo con el ralentizador y entra al círculo.",
	HideInside = "Escondido. Pulsa E para salir.",
	HideBusy = "¡Ya hay alguien escondido ahí!",
	HideEscape = "¡El kiwi husmeó tu escondite y escapaste! +%d monedas",
	ChestLoot = "¡Encontraste: %s! (%d usos)",
	WeaponOut = "Se te acabó: %s",
	BoomShout = "¡%s disparó el %s!",
	BoomHit = "¡Le diste con el %s!",
	SniffCaught = "¡El kiwi encontró a %s escondido y se lo comió!",
	EatenMenu = "El kiwi te comió. Elige otro modo para volver a jugar.",
	MapPickNotify = "¡Mapa elegido: %s!",
	MapFallback = "Ese mapa estaba ocupado: esta partida va en %s.",
	HurtMsg = "¡%s te dio con %s! (-%d de vida)",
	KoedAll = "¡%s dejó fuera a %s de un disparo!",
	KoMenu = "Te noquearon a tiros. Elige otro modo para volver a jugar.",
	DeathTitle = "¡TE COMIÓ EL KIWI!",
	DeathSubtitle = "Vuelves al lobby... la reserva no perdona.",
	SlowHit = "¡Diste al kiwi gigante! Va más lento por %d segundos.",
	SlowAll = "¡%s ralentizó al kiwi gigante!",
	SlowMiss = "La aguja pasó de largo.",
	SlowEnd = "El kiwi gigante recuperó su velocidad.",
	PvpRifleOn = "¡Llegó otro cazador! Recibiste el Rifle de Pintura (tecla 5).",
	PvpRifleOff = "Quedaste solo: el Rifle de Pintura se guardó.",
}

-- Sonidos incluidos en el cliente de Roblox (no requieren subir nada).
-- Si alguno no carga en tu version de Roblox, cambia el id por uno tuyo.
Config.Sounds = {
	countdown = "rbxasset://sounds/electronicpingshort.wav",
	start = "rbxasset://sounds/switch.wav",
	netSwing = "rbxasset://sounds/swordslash.wav",
	netHit = "rbxasset://sounds/snap.wav",
	dartShot = "rbxasset://sounds/unsheath.mp3",
	dartHit = "rbxasset://sounds/impact_explosion_03.mp3",
	flush = "rbxasset://sounds/swordlunge.wav",
	rustle = "rbxasset://sounds/action_footsteps_plastic.mp3",
	win = "rbxasset://sounds/electronicpingshort.wav",
	lose = "rbxasset://sounds/uuhhh.mp3",
	ui = "rbxasset://sounds/button.wav",
	denied = "rbxasset://sounds/switch.wav",
	trapSet = "rbxasset://sounds/switch.wav",
	trapCatch = "rbxasset://sounds/snap.wav",
	paintShot = "rbxasset://sounds/unsheath.mp3",
	paintHit = "rbxasset://sounds/impact_explosion_03.mp3",
	roar = "rbxasset://sounds/uuhhh.mp3",
}

return Config
