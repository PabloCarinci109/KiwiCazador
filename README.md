# 🥝 Kiwi Cazador

Juego completo de Roblox hecho **100% con código**: no hay que construir nada en Studio.
El servidor genera el lobby, las arenas, los escondites, el kiwi, las herramientas y toda la
interfaz cuando inicia la partida.

> **Objetivo:** cazar al kiwi (el pajarito de Nueva Zelanda) antes de que se esconda otra vez.
> Puedes atraparlo con la **red de captura**, dormirlo con el **rifle tranquilizante** (clic derecho: mira),
> dejarle una **trampa de fruta**... o esconderte de un **kiwi gigante** en el modo Colosal.

---

## Modos de juego

| Modo | Qué es |
| --- | --- |
| **Fácil** | Kiwi lento y confiado. Ideal para aprender el mapa. |
| **Normal** | El kiwi escucha tus pasos, se esconde y corre cuando lo asustas. |
| **Difícil** | Rapidísimo, desconfiado y solo duerme un momento. Además **no ves su estado** en el HUD. |
| **Multijugador** | 🪶 ¡Supervivencia! Un **kiwi gigante** caza a todos: va **comiéndose jugadores** uno por uno y **gana el último que quede vivo** (hasta 12 jugadores). Llevas rastreador, **rifle ralentizador** y el **rifle de pintura** para frenar a los rivales. |
| **Kiwi Colosal** | 🪶 ¡El cazador cazado! Un **kiwi gigante** te huele y te persigue: **escóndete y sobrevive**. A mitad de ronda se activa la **ZONA SEGURA** en el centro: **entra al círculo y ganas al instante**, pero el kiwi te **corta el paso** y ronda el borde — frénalo con el ralentizador, esquívalo y métete. Llevas el rastreador y un **rifle ralentizador** (no lo duerme: lo frena unos segundos). |
| **Asedio al Kiwi** | ⚔️ **¡5 contra 5!** Un equipo (**Defensores**) cuida al kiwi en su casa y el otro (**Cazadores**) entra a **capturarlo con la red** (o **dormirlo** con el rifle y tocarlo) antes de que se acabe el tiempo. **Al mejor de 3 rondas**: si te noquean, volvés al spawn de tu equipo a los 7 segundos. Los Cazadores llevan red, rifle tranquilizante, rastreador y pintura; todos llevan **revólver de equipo**. |

En los modos de un jugador hay que atrapar **3 kiwis** antes de que se acabe el tiempo.
El juego corre hasta **5 partidas a la vez** (una por arena); si todas están ocupadas, aparece
un aviso y puedes intentarlo de nuevo en unos segundos.

### Mapas y votación (nuevo en 1.3.0)

- Al elegir un modo **se vota el mapa**: 5 lugares inspirados en Nueva Zelanda —
  **Bosque de Kauri**, **Dunas de Te Paki**, **Ciudad de Auckland**, **Costa de Totara** y
  **Alpes del Sur** — más la opción **AL AZAR**. Con un solo jugador elige igual; si hay varios,
  gana el más votado (empate se decide al azar) y todos ven el resultado en el HUD.
- Cada mapa se construye distinto: **tema, materiales, props e iluminación propios**. Dunas con
  **cactus y médanos**, Costa con **palmeras**, Alpes con **pinos nevados**, Ciudad con
  **postes de luz, bancos y la Sky Tower**. La **hora, la niebla y la luz** cambian en cada mapa.
- **No se puede salir del mapa:** la Ciudad cierra con **murallones de edificio** (fachadas con
  ventanas, cornisas, torres en las esquinas y skyline de fondo); las zonas de naturaleza y dunas
  cierran con **montañas de roca** alrededor (y el Bosque suma una línea de **kauris gigantes**).
- Las **casas ahora son de dos pisos** (con escalera, planta alta decorada y un **baúl extra**
  arriba) y el granero tiene **silos** de metal al lado. Se puede subir a mirar el mapa desde arriba.

### Asedio 5 vs 5 y estilo Counter (nuevo en 1.4.0, arreglo de arranque en 1.4.1)

> **1.9.3:** llegaron las **granadas**: cada baúl suelta un **pack** (1 fragmentación, 1 humo,
> 1 molotov y 2 flashes) que se lanza con clic y vuela con física real. La **Glock-18 ya no
> tiene mira**: su clic derecho cambia entre tiro a tiro y **ráfaga de 3 (estilo CS2)**. El
> **rifle tranquilizante inmoviliza 3 s** al rival que toca y el **francotirador noquea de un
> solo disparo**. La **M4A1 ahora tiene silenciador** (en la mano y en el modelo) y sus tiros
> **apenas se escuchan**. Además se sacó de todos los mapas el **cartel gigante con el nombre
> de la zona** ("Alpes del Sur", etc.) que se veía durante la partida.
> **1.9.2:** el **lanzamisiles destroza el mapa** (vuela casas y graneros, autos y el tren, tira
> árboles; todo se recompone solo a los ~30 s), ya no tapa la mira al apuntar, el **arco y la flecha
> se ven con el zoom** (la flecha sale volando y se recupera clavada), el **recoil es mucho más suave**
> y el **rifle de pintura ciega 4 s** si da en la cabeza. El **cuchillo mariposa** queda garantizado
> en la mochila de todos los modos.
> **1.9.1:** arreglado el **asedio** (un error de teleport hacía que los jugadores quedaran en el
> lobby sin armas ni kiwi: el spawn devolvía la posición en vez del CFrame completo). El nido del
> kiwi ahora es un **bunker de los Defensores**: muralla con **troneras**, **portón** al frente,
> **dos ductos de ventilación** (se entra agachado) y un **túnel cubierto** por atrás, más
> **barricadas de bolsas de arena**. Cada equipo tiene su **baúl**: de ahí sacás **UNA sola arma
> por ronda** (el arma es para vos; el baúl sigue abierto para el resto). El arsenal de baúles
> quedó en **10 armas** (salió el cuchillo). Y los **pasos ahora suenan solo al correr**: con
> **Shift** (caminar) o **Ctrl** (agachado) vas en silencio, y se apagó el sonido de pasos que
> Roblox trae por defecto. Además llegó el **cuchillo mariposa**: va **de fábrica para todos**
> (no sale de los baúles), se **abre con un giro** al equiparlo, el **clic** pega un **zarpazo**
> corto y con **F** lo hacés **girar en la mano** (estilo CS2). Y el mundo ahora tiene **clima y
> hora**: el sol va **oscureciendo** con el correr de la partida y cada tanto cambia el tiempo
> al azar (**sol, lluvia o nieve**); cuando **nieva**, caen los copos y la nieve **se acumula en
> el piso y los techos** (el mapa se ve nevado) hasta que para y se derrite sola.

> **1.8.0:** el personaje ahora **corre siempre** (con **Shift** camina despacio y hace menos
> ruido) y en partida el **mouse queda oculto y centrado** (se fue la manito que tapaba el punto
> de mira). La cámara **abre un poco el FOV al correr** para sentir la velocidad. El
> **lanzallamas** deja **fuego prendido donde pega** (paredes, objetos, gente): si esa llama
> arde 5 segundos o más, **quema a quien esté cerca, incluso a vos**. Y al equiparlo cargás una
> **mochila de combustible** visible en tercera persona: si un enemigo **le dispara al tanque,
> explota y te vuela el 80% de la vida**.

> **1.7.0:** el **punto de mira central** ahora sí queda en el centro de la pantalla (antes
> estaba pegado a la barra de arriba) y se ve **siempre en partida, incluso sin armas**. La
> **mira del francotirador** es mucho más grande y se adapta a tu pantalla, con bastante menos
> negro. El **lanzallamas** ahora tira un **chorro de fuego visible** que saca **10% de la vida
> por segundo** durante hasta 10 segundos seguidos; si te pasás de ese tiempo **te quemás vos
> también**, así que hay que soltar el gatillo (12 usos = 12 segundos de combustible).

> **1.6.0:** el **punto de mira central** ahora se ve bien (a la cadera y al apuntar, en cualquier
> vista); las armas tienen **sonido propio de disparo** (boom grave + chasquido + cola, armado por
> capas) y el **lanzamisiles se ve como un RPG de verdad** (tubo gordo con el cohete asomando).
> De paso: menos trabajo por frame (sonidos reutilizados en pool, HUD con caché) para que corra
> más fluido.

> **1.5.1:** al apuntar (clic derecho) el arma baja al costado y en el centro queda un
> **puntito de mira** bien fino: ya no tapa la vista. El aro de mira grande con vidrio negro
> ahora es **solo del francotirador** (5x, segundo clic 10x); el resto de las armas apunta
> directo con el puntito.

> **1.5.0:** primera persona **fija** durante la partida (estilo Counter Blox), el arma pasa
> **al costado** de la pantalla para no tapar la vista, la **cruz es más chica** y los baúles
> ahora sueltan el **arsenal Counter**: **AK-47, M4A1, MP5, Glock-18 y Escopeta** (además del
> revólver, francotirador, arco, cuchillo, lanzallamas y lanzacohetes de siempre).

> **1.4.1:** el juego **no iniciaba en ningún modo** (WorldBuilder no importaba Config y el armado
> del mundo fallaba al arrancar: "attempt to index nil with 'City'"). Ya está corregido: si el
> Output muestra esa clase de error, actualizá a la build 1.4.1 o superior.

- **Nuevo modo Asedio al Kiwi (5 vs 5):** el juego reparte **Cazadores** y **Defensores** en
  equipos parejos. El kiwi vive en su **casa del nido** (con **correa**: no se aleja de la casa) y
  los Defensores lo cuidan; los Cazadores entran a **capturarlo con la red** (o tocarlo si está
  enganchado). **Ronda de 150 segundos**, punto para quien capture / para los Defensores si se
  acaba el tiempo, y **gana el primero a 2 rondas**. Al noquearte, **volvés a tu spawn a los 7 s**.
  No hay **fuego amigo** y los equipos se identifican con **colores y brillo entre paredes**.
- **Tiros estilo Counter Blox:** la dispersión depende del **movimiento**, hay **zona muerta**,
  **reducción al apuntar/agacharse**, **retroceso con patada de arma y de cámara** (vuelve sola),
  **caída de daño por distancia** y **¡TIRO A LA CABEZA!** (aviso dorado y multiplicador fuerte).
- **Miras de verdad:** con el francotirador, clic derecho cicla **5x → 10x → sin mira**; sin mira
  es un **noscope impreciso** y con mira el disparo sale **perfecto** (y caminás más lento).
  El rifle tranquilizante, el de pintura y el ralentizador también tienen su **mira** (clic derecho).
- **HUD estilo Counter:** barra de **marcador de equipos y ronda** arriba, **vida grande** abajo a
  la izquierda (verde → ámbar → roja), **punto de mira dinámico** que se abre al moverse o
  disparar, **tabla de posiciones con Tab** y **fogonazo** del cañón en el arma en primera persona.
- **Movilidad:** el personaje **corre siempre**; **Shift** lo hace **caminar despacio** y
  **Ctrl / Alt / C** agacharse en sigilo (la cámara baja y el arma se afirma: menos dispersión).
  **V** cambia a primera persona.
- **Clima y hora:** el día avanza solo (amanece, **oscurece** y vuelve a aclarar) y el tiempo
  cambia al azar: **sol, lluvia o nieve**. Con la nevada caen los copos, la nieve **se acumula en
  el piso** y blanquea el mapa entero; cuando para, se derrite sola.
- **Créditos:** las fórmulas de disparo, retroceso, cabeza y zoom están inspiradas en el código
  público de **Counter Blox: Sauce - Restored** (licencia MIT) — ver [`LICENSE-CB.md`](LICENSE-CB.md).

---

## Cómo se juega

1. Al entrar apareces en el **lobby**. En pantalla tienes el menú para elegir modo.
2. Al elegir un modo, una cuenta atrás te lleva a la arena con tus herramientas
   (en Kiwi Colosal: rastreador y rifle ralentizador):

| Tecla | Acción |
| --- | --- |
| **Click** | Usar la herramienta equipada (en las **automáticas** deja el clic **apretado** para rafaguear) |
| **Click derecho** | Apuntar con zoom leve y **puntito central** en cualquier arma (con el **francotirador** en cambio entra la telescópica 5x/10x) |
| **1 / 2 / 3 / 4 / 5** | Cambiar de herramienta (red / rifle / rastreador / trampa / pintura; en Colosal: rastreador / ralentizador) |
| **Shift** | Caminar despacio (hacés menos ruido; por defecto corrés, y el kiwi te oye antes) |
| **Ctrl**, **Alt** o **C** | Agachado en sigilo (casi no te oye; la cámara baja y el arma se afirma: menos dispersión) |
| **F** | Con el **cuchillo mariposa** (de fábrica para todos): lo hacés **girar en la mano**, estilo CS2 |
| **E** | **Esconderte** en un armario, barril o pajar / **abrir un baúl**. Dentro del escondite, E otra vez te saca |
| **Tab** | **Tabla estilo Counter** (equipos, marcador y capturas en Asedio) + tabla de jugadores de Roblox |

> **Vista estilo Counter Blox:** durante la partida la cámara es **siempre en primera persona**
> (en el lobby y la votación queda libre), con el **arma al costado** para no tapar la pantalla
> y una **cruz chica** que se abre solo cuando te movés o disparás. Al apuntar el arma se
> corre **bien abajo** y queda nada más que el **puntito central** para tirar preciso.

### Herramientas

- **Red de captura** 🕸️ — es lo único que atrapa de un golpe si estás cerca (tiene probabilidad,
  más baja en Difícil). También sirve para **buscar en un escondite**: si apuntas al escondite
  correcto, el kiwi sale disparado.
- **Rifle tranquilizante** 💉 — dispara un dardo. Si le das, el kiwi **se duerme unos segundos**:
  acércate y **tócalo** para recogerlo. Ojo, despierta y sale corriendo. Con **clic derecho**
  entra la **mira**: vista en **primera persona** (ya no te tapa la cabeza), zoom leve y el
  **puntito central** para apuntar.
- **Rastreador** 🧭 — pulsa click y aparece la **brújula** en el centro del HUD: **aguja hacia el
  kiwi**, **rosa de los vientos** (N/E/S/O) que gira con tu cámara y la **distancia** abajo. La
  aguja cambia de color según el estado: verde si está a la vista, ámbar si está escondido. Tiene enfriamiento.
- **Trampa de fruta** 🍓 — **una sola por jugador** (poner otra reemplaza la anterior). Déjala y
  **aléjate despacio**: el kiwi la huele desde cualquier rincón (incluso **sale de su escondite** a
  comerla) y si pasa cerca… queda **enganchado 3 segundos** forcejeando. Esa es tu ventana: corre a
  atraparlo a mano o dispárale el dardo. Si no vas, **se suelta y escapa** (y por un rato no vuelve
  a pisar fruta).
- **Rifle de pintura** 🎨 — aparece **solo en multijugador** (tecla 5) y tiene **mira** (clic
  derecho). Mancha a los demás cazadores: los deja **marcados 15 segundos** (brillo rosa y
  etiqueta que **se ven entre las paredes**, ideal para encontrarlos) y **lentos 3 segundos**.
  Si le pegás al kiwi, también queda marcado un rato.
- **Rifle ralentizador** 🧊 — aparece **solo en Kiwi Colosal** (tecla junto al rastreador) y tiene
  **mira**. Sus agujas **no duermen** al gigante: lo dejan **lento 8 segundos** con un tinte frío,
  ojos celestes y un cartel **"¡RALENTIZADO!"** que se ve entre paredes. Tu ventana para escapar.
- **Arsenal estilo Counter Blox** 🔫 — sale de los **baúles** y trae las clásicas de Counter:
  **AK-47** (34 de daño, automática), **M4A1** (30, automática y precisa), **MP5** (22, muy
  manejable), **Glock-18** (26, pistola) y **Escopeta** (8 perdigones: de cerca es letal).
  Las automáticas **se disparan dejando el clic apretado**; con **clic derecho** apuntás y la
  dispersión se cierra. Junto al **Revólver**, el **Francotirador**, el **Arco**, el
  **Lanzallamas** y el **Lanzacohetes** (y el **tranquilizante** de siempre).
- **Cuchillo mariposa** 🔪 — no sale de los baúles: lo llevan **todos de fábrica** en cualquier
  modo. Al equiparlo se **abre con un giro** (estilo CS2), el **clic** pega un **zarpazo** rápido
  y **F** lo hace **girar en la mano**.

### Escondites y baúles (1.2.0, ampliados en 1.3.0)

- **Casas de verdad:** cada arena tiene una **aldea** con casa, casona y **granero**, con **interiores completos**:
  mesa, sillas, cama, estantes, cajas... y **escondites adentro**: **armario** (la puerta se abre),
  **barril** y **pajar**. Además hay una casa más lejos y **baúles** sueltos por el mapa.
- **Esconderte (E):** acércate y pulsa **E**. Te mete adentro, la puerta se cierra, tu cuerpo **desaparece**
  (invisible para todos, en primera persona) y el kiwi **no te huele** mientras estés escondido.
  **E otra vez** para salir. Un escondite aguanta **una persona a la vez**.
- **Dentro de las casas hueles menos:** si el kiwi gigante te busca dentro de una casa, tu olor
  se reduce al 45%: las paredes y el techo ayudan.
- **El kiwi husmea tu escondite:** si el gigante pasa cerca de un escondite **ocupado**, se planta
  enfrente y **husmea 3,2 segundos** (cabeceo, sonidos y partículas). Si te quedas, **te encuentra y te
  come**. Si **sales a mitad**, te llevas **+3 monedas de escape**... pero el kiwi te persigue
  **al instante**. Ese es el momento "casi" del escondite. El mismo sitio no lo vuelve a husmear ~35 s.
- **Baúles de armas (4 armas, modelos distintos):** cada baúl da **un arma aleatoria con 3 usos**:
  **Lanzamisiles** 💥 (tubo RPG, explosión en área), **Revólver** 🔫 (tiro rápido), **Arco y flecha** 🏹
  (arco real con cuerda, silencioso) y **Rifle francotirador** 🎯 (mira telescópica, el más dañino).
  Solo puedes llevar **un arma de baúl a la vez** (abrir otro baúl la cambia), aparece en tu mochila
  con su **tecla automática** y los baúles **se recargan cada ronda**.
- **Duelo entre cazadores (nuevo en 1.3.0):** todos los jugadores tienen **100 de vida** con
  **regeneración** (4/s tras 6 s sin recibir golpes). Las armas de baúl ahora **hacen daño a otros
  jugadores**: cohete **40** (en área, con empujón), revólver **20**, arco **26**, francotirador **48**.
  Si te quedas sin vida quedas **KO** y vuelves al menú de modos. **Al kiwi las armas no le hacen daño:
  solo lo frenan** (y el lanzamisiles lo empuja), perfecto para escapar o ganar la zona segura.
- Las armas de baúl **empujan a los jugadores** (también a ti si disparas de muy cerca) y **frenan al
  kiwi gigante**: perfectas para ganar la zona segura o sobrevivir en multijugador.

### El kiwi

- Pasea por la arena, se esconde en **más de 100 escondites** (arbustos, troncos huecos,
  madrigueras, helechos, cabañas, la torre...) y se aburre: cambia de escondite cada cierto rato.
- **Mapas aleatorios:** cada servidor arma la reserva distinto: escondites, rocas y árboles cambian
  de lugar (y cada arena tiene su propio paisaje), así que memorizar el mapa solo sirve a medias.
- **Pistas para encontrarlo:** si está escondido cerca oirás un **susurro de arbustos** (partículas y sonido),
  y en Fácil/Normal el HUD te dice qué está haciendo (`escondido`, `huyendo`, `dormido`...).
- Si te acercas demasiado, **sale disparado** aunque vayas en silencio. Si lo persigues mucho,
  al final se **cansa** (y ahí es tu momento).
- Si disparas un dardo a un escondite, el dardo lo atraviesa: a un kiwi escondido **hay que sacarlo**
  con la red o acercándose.
- **Kiwi Colosal:** un kiwi **4 veces más grande**, con ojos rojos brillantes, patrulla la reserva,
  **te huele** (más si corres o saltas), **husmea los armarios, barriles y pajares** donde te escondas
  y no entra a la **zona segura** (ronda el borde esperándote). Si te alcanza, **te come** con una
  animación de mordiscos y cámara de cine: aparece **"¡TE COMIÓ EL KIWI!"** y vuelves al lobby
  (quedas fuera de la ronda). Sobrevive hasta que se acabe el tiempo o **entra al círculo para ganar**.
  El rastreador te dice si **te anda buscando** y con el **ralentizador** (o un arma de baúl) lo frenas.

### Recompensas

Cada kiwi atrapado da **monedas** según la dificultad, más bonos por ganar la ronda y por el tiempo
sobrante. También ganas **+3 monedas** cada vez que escapas de un husmeo saliendo del escondite
justo a tiempo. Las monedas y los kiwis aparecen en el **leaderstats** (Tab) y la tabla final de la ronda.
*(De momento no se guardan entre servidores: eso es lo primero en la lista de "Próximos pasos".)*

---

## Contenido del proyecto

```
kiwi-cazador/
├── KiwiCazador.rbxlx             # Lugar listo para abrir en Studio (generado)
├── default.project.json          # Mapa del proyecto para Rojo
├── tools/
│   └── build_rbxlx.py            # Regenera el .rbxlx desde src/
└── src/
    ├── shared/                   # Se sube a ReplicatedStorage.KiwiShared
    │   ├── Config.lua            # TODO el balance del juego (dificultades, precios, textos)
    │   ├── Net.lua               # Remotes compartidos
    │   └── Util.lua              # Utilidades comunes
    ├── server/                   # Se sube a ServerScriptService.KiwiServer
    │   ├── Main.server.lua       # Punto de entrada del servidor
    │   └── modules/
    │       ├── GameManager.lua   # Sesiones, arenas, fases, recompensas
    │       ├── WorldBuilder.lua  # Genera lobby + 5 arenas con escondites
    │       ├── KiwiController.lua# Cerebro del kiwi (estados, huida, cansancio)
    │       ├── KiwiModel.lua     # Cuerpo del kiwi hecho con Partes
    │       ├── Actions.lua       # Red, dardos, trampas de fruta, pintura, ralentizador y rastreador
    │       ├── ToolService.lua   # Construye y entrega las herramientas
    │       └── Shared.lua        # Acceso a la carpeta compartida
    └── client/                   # Se sube a StarterPlayerScripts.KiwiClient
        ├── Main.client.lua       # Entrada del cliente (input, efectos, teclas)
        └── modules/
            └── HUD.lua           # Menú, HUD, avisos, resultados y brújula
```

---

## Instalación

### Opción A — Abrir el archivo listo `KiwiCazador.rbxlx` (la más fácil)

El repo incluye **`KiwiCazador.rbxlx`**: un lugar de Roblox completo con los 13 scripts adentro,
generado desde `src/`. No hay que instalar nada.

1. En Roblox Studio: `File → Open from File…` y elige `KiwiCazador.rbxlx`.
2. Dale **Play** para probar (deberías aparecer en el lobby con el menú de modos).
3. Para subirlo a Roblox: `File → Publish to Roblox` (ver **Publicar en Roblox** más abajo).

Si más adelante cambias el código de `src/`, regenera el archivo con:

```bash
python3 tools/build_rbxlx.py
```

### Opción B — Con Rojo (recomendada si vas a editar el código)

1. Instala [Rojo](https://rojo.space) si no lo tienes (cualquiera de estas):
   - `aftman add rojo-rbx/rojo` (o Foreman), o
   - `cargo install rojo`, o
   - descarga un binario desde la página de releases de Rojo.
2. Desde la carpeta `kiwi-cazador/`:
   ```bash
   rojo build -o KiwiCazador.rbxlx
   ```
3. Abre `KiwiCazador.rbxlx` en Roblox Studio y **Publica** el juego. Listo.

*Alternativa en vivo:* `rojo serve` + el plugin de Rojo en Studio (botón **Connect**) para
editar el código y ver los cambios sin reconstruir.

### Opción C — Pegar a mano en Studio (sin nada)

Crea estas carpetas y scripts **con estos nombres exactos** (importan las mayúsculas):

**1. ReplicatedStorage**
- Folder llamada `KiwiShared`
  - ModuleScript `Config` → pega `src/shared/Config.lua`
  - ModuleScript `Util` → pega `src/shared/Util.lua`
  - ModuleScript `Net` → pega `src/shared/Net.lua`

**2. ServerScriptService**
- Folder llamada `KiwiServer`
  - **Script** (normal, no LocalScript) llamado `Main` → pega `src/server/Main.server.lua`
  - Folder llamada `modules`
    - ModuleScript `GameManager` → `src/server/modules/GameManager.lua`
    - ModuleScript `WorldBuilder` → `src/server/modules/WorldBuilder.lua`
    - ModuleScript `KiwiController` → `src/server/modules/KiwiController.lua`
    - ModuleScript `KiwiModel` → `src/server/modules/KiwiModel.lua`
    - ModuleScript `Actions` → `src/server/modules/Actions.lua`
    - ModuleScript `ToolService` → `src/server/modules/ToolService.lua`
    - ModuleScript `Shared` → `src/server/modules/Shared.lua`
    - ModuleScript `Weather` → `src/server/modules/Weather.lua`

**3. StarterPlayer → StarterPlayerScripts**
- Folder llamada `KiwiClient`
  - **LocalScript** llamado `Main` → pega `src/client/Main.client.lua`
  - Folder llamada `modules`
    - ModuleScript `HUD` → pega `src/client/modules/HUD.lua`
    - ModuleScript `ViewModel` → pega `src/client/modules/ViewModel.lua`
    - ModuleScript `WeatherFX` → pega `src/client/modules/WeatherFX.lua`

> ⚠️ Si algo no carga, mira la sección **Problemas comunes** más abajo. El juego avisa
> con mensajes claros en el Output de Studio si falta una carpeta.

Consejos para el lugar en Studio:

- En `Workspace`, desactiva **StreamingEnabled** (el mapa se genera por código).
- Pon el máximo de jugadores que quieras en `Game Settings` (con 12 por partida ya sobra;
  caben varias partidas a la vez).
- No hace falta nada más: al dar **Play**, el servidor construye todo automáticamente.

---

## Publicar en Roblox

> Roblox Studio solo corre en Windows/Mac. En Linux se puede usar
> [Vinegar](https://vinegarhq.org) (o abrir el `.rbxlx` en una PC con Windows/Mac).

1. Abre `KiwiCazador.rbxlx` en Studio y dale **Play** un minuto para probar.
   Mira la ventana **Output**: debe aparecer `[Kiwi Cazador] v1.9.3 listo para cazar`.
2. `File → Publish to Roblox`: pon el nombre (`Kiwi Cazador`), una descripción y elige los
   dispositivos. La primera vez te crea la experiencia y ya queda subida.
3. Configura la página del juego en [create.roblox.com](https://create.roblox.com):
   icono, miniaturas y género. En **Game Settings** ajusta el máximo de jugadores (sugerido ~20).
4. Para actualizar el juego más adelante: cambias `src/`, corres `python3 tools/build_rbxlx.py`,
   abres el `.rbxlx` y `File → Publish to Roblox` otra vez (actualiza el mismo juego).
   No uses `Save to Roblox As…` porque crearía una experiencia nueva.

---

## Ajustar el juego (`src/shared/Config.lua`)

Casi todo lo interesante se toca en `Config.lua`, sección por sección:

| Qué quieres cambiar | Dónde |
| --- | --- |
| Otra semilla de mapa (otro layout) | `Config.World.Seed` |
| Tamaño / separación de arenas | `Config.World.ArenaSize` y `ArenaSpacing` |
| Cuántas partidas a la vez | `Config.World.ArenaCount` |
| Nombres/colores de las zonas | `Config.Zones` |
| Votación de mapa (tiempos) | `Config.Vote` |
| Iluminación y niebla por mapa | `Config.ZoneLight` y `Config.LightDefault` |
| Vida de jugadores y regeneración | `Config.Player` (hp, regen) |
| Velocidad de jugadores (correr/sigilo) | `Config.Player` |
| Kiwi más fácil o más listo | `Config.Difficulties.facil/normal/dificil.kiwi` |
| Red y rifle (alcance, enfriamiento, probabilidad) | `Config.Difficulties.*.red` y `*.rifle` |
| Cuántos kiwis por partida, tiempo, monedas | `Config.Difficulties.*.round` |
| Trampa de fruta (alcance, radio, enfriamiento) | `Config.Trampa` |
| Rifle de pintura (frenado, enfriamiento) | `Config.PaintRifle` |
| Mira del rifle (zoom) | `Config.Scope` |
| Kiwi gigante (velocidad, detección, tamaño) | `Config.Difficulties.colosal.kiwi` |
| Escondites (distancia, olor indoor, tiempo de husmeo, monedas de escape) | `Config.Hide` |
| Baúles (usos por arma, lista y probabilidad) | `Config.Loot` |
| Armas de baúl (velocidad, freno, empujón, daño PvP, enfriamiento) | `Config.Weapons` |
| Multijugador (jugadores, espera, tiempo) | `Config.Multiplayer` |
| Cuenta atrás, pantalla de resultados | `Config.Round` |
| Todos los mensajes que ve el jugador | `Config.Text` |
| Sonidos | `Config.Sounds` |

Cada dificultad incluye comentarios explicando cada número (campo de visión, radio de detección,
agotamiento, preferencia por el mejor escondite, etc.). **No necesitas tocar nada más.**

### Sonidos

De fábrica se usan sonidos incluidos en el cliente de Roblox (`rbxasset://sounds/...`),
así que **no hay que subir nada**. Si quieres sonidos propios, súbelos a Roblox y cambia los IDs
en `Config.Sounds`. Si algún sonido no carga, en Studio mira el Output y sustitúyelo por otro.

---

## Problemas comunes

| Síntoma | Causa y solución |
| --- | --- |
| Output: *"Falta la carpeta ReplicatedStorage.KiwiShared"* | El nombre de la carpeta no coincide exactamente (opción B), o falta `Config`/`Util`/`Net` dentro. |
| Output: *"Intenta requerir un ModuleScript..."* o errores de `require` | Algo no es del tipo correcto: los módulos deben ser **ModuleScript**, `Main` del servidor un **Script** y `Main` del cliente un **LocalScript**. |
| No aparece el menú | `KiwiClient` debe estar dentro de **StarterPlayerScripts** con su folder `modules` y el `HUD` adentro. |
| El kiwi "no aparece" | En Normal/Difícil empieza escondido a propósito: mira el HUD, escucha el susurro de arbustos o usa el rastreador. |
| "Todas las arenas están ocupadas" | Hay 5 partidas corriendo: espera unos segundos (las arenas se liberan al terminar cada ronda). |
| Un jugador cae al vacío | Se le rescata solo a la arena o al lobby automáticamente. |

---

## Cómo funciona por dentro (resumen técnico)

- **Servidor autoritativo:** el cliente solo manda "usé la red / disparé / ping del rastreador";
  el servidor valida distancia, dirección (cono), enfriamientos y estado del kiwi. No se puede *cheatar* fácil.
- **Kiwi sin física:** está hecho con Partes ancladas y una máquina de estados propia
  (`wander`, `flee`, `tired`, `hidden`, `sedated`, `caught`), sin Humanoid. El kiwi gigante del
  modo Colosal usa el mismo cuerpo escalado x4 con otro cerebro (`patrol`/`hunt`).
- **Esconderse** = ponerse invisible y `CanQuery = false`: por eso los dardos atraviesan a un kiwi
  escondido y hay que sacarlo del escondite (red apuntando al spot correcto o acercándose).
- **Escondites de jugador y baúles** son `ProximityPrompt` del **servidor** (tecla E): el cliente solo
  pulsa y el servidor valida distancia, ocupación y fase. El kiwi tiene un estado nuevo (`sniff`) que
  solo reacciona a escondites **ocupados**, con enfriamiento por sitio, y las armas de baúl llevan
  **usos** y recarga controlados en el servidor (`Actions.fireWeapon`).
- **5 arenas** generadas por semilla a 900 studs de distancia, con decenas de escondites cada una;
  los jugadores viajan por teleport entre lobby y arena.
- **HUD completa por código:** menú de modos, barra de objetivo/tiempo, brújula del rastreador,
  marcador multijugador, avisos y pantalla de resultados.

---

## Próximos pasos sugeridos

1. **Guardar progreso con DataStore** (`Monedas` y `Kiwis` ya viven en el `leaderstats`: es solo
   persistirlos y recargarlos al entrar).
2. **Tienda** en el lobby con herramientas cósmicas/skins de red usando las monedas.
3. **Más zonas y variaciones de mapa** (añade entradas a `Config.Zones` y cambia `Seed`).
4. **Sonidos y música propios** subidos a Roblox (para reemplazar los `rbxasset://`).
5. **Logros/insignias** (BadgeService) y tabla de líderes global.

---

Hecho para ser publicado: cambia lo que quieras en `Config.lua`, dale a **Publish** y a cazar kiwis. 🥝
