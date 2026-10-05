# Plan de juego — Snow It Together (título provisional)

> Documento de diseño y plan técnico. **Nada de esto está implementado aún**: sirve
> para decidir antes de construir. Lo que ya existe en el prototipo se marca con
> ✅ y lo que falta con ⬜.

---

## 0. Resumen ejecutivo

**Snow It Together** es un simulador de limpieza de nieve en primera persona,
*cozy*, **jugable en solitario y en cooperativo online de 2 jugadores**, con un
motor de nieve granular de **masa conservada** como diferencial central.

- **Género:** cleaning sim cozy + sandbox de física emergente + cooperativo de broma.
- **Precio:** **6,99 €** (alineado con la referencia) + **demo gratuita**.
- **Duración:** 1,5–2,5 h la primera pasada en solitario · **6–9 h el 100 %**
  (el libro del invierno exige **2–3 vueltas** con retos distintos) · sandbox y
  duelo de bolas ilimitados.
- **Referencia directa:** *Leaf it Alone* (Eternity, 2025) — mismo bucle de
  "limpia al 100 %", misma estética de bajo coste, mismos idiomas solo-texto.
- **Diferencial 1 — la nieve es materia:** allí se borra una máscara; aquí no
  desaparece, se mueve. Cada nivel es un puzle de logística (*¿dónde la echo?*).
- **Diferencial 2 — el cooperativo es físico y gamberro:** no se reparten tareas,
  se comparten objetos, y **arruinarle el trabajo a tu compañero es una mecánica
  diseñada**, no un accidente que haya que castigar.

**La apuesta:** el nicho pide cooperativo a gritos y nadie se lo ha dado. Un coop
donde dos personas se pasan bolas, levantan entre las dos y se destrozan la pila
recién hecha es un producto distinto en un mercado que vende 292 k copias a 6 €.

**Las tres capas de tiempo de juego** (esto es lo que hace que dure sin contenido
caro): trabajar · **jugar entre tú y tu compañero** · coleccionar y descubrir
secretos. El plan reparte el esfuerzo entre las tres, no sólo en la primera.

---

## 1. Referencia y hueco de mercado

Datos de *Leaf it Alone* ([Steam](https://store.steampowered.com/app/3981100/),
[VORYTHIC](https://vorythic.com/games/3778/leaf-it-alone)):

| Dato | Valor | Lectura para nosotros |
|---|---|---|
| Precio | 5,99 € | Escala pequeña; no competir con presupuesto AAA |
| Ventas | ~292 k copias | Nicho real y rentable con equipo mínimo |
| Nota | 95 % positivas | El "cozy" bien hecho perdona la falta de contenido |
| Duración | 1,6 h principal · 5,5 h completo | 8–12 niveles de 5–15 min bastan |
| Idiomas | **13, solo interfaz** | i18n es obligatorio y **no hace falta doblaje** |
| Etiquetas | Cleaning, Relaxing, **Incremental**, Physics, First-Person, Controller | Progresión numérica satisfactoria + mando |
| Mínimos | GTX 960, 4 GB RAM, 1 GB disco | **Nuestro riesgo técnico #1**: la sim GPU |
| Multijugador | Ficha: *un jugador*. Foro: *"¿por qué tiene etiqueta coop?"* | **El hueco está aquí** |
| Accesibilidad | Camera comfort, Custom volume, Playable without timed input, Save anytime | Checklist mínima del género |
| Extras | Logros, marcadores, Steam Cloud, modo foto implícito | Baratos y esperados |

**Conclusión:** copiamos el *chasis* (bucle, tono, precio, 13 idiomas, mando,
guarda-cuando-quieras) y nos diferenciamos en **física real + cooperativo**.

---

## 2. Pilares de diseño

1. **La nieve es materia, no textura.** Nada se borra: todo se mueve. La masa del
   mundo se conserva (es ya una regla dura del prototipo ✅).
2. **El trabajo físico compartido es la diversión.** El coop no reparte tareas,
   las *comparte*: objetos que necesitan dos personas.
3. **El movimiento es un juguete.** Correr, deslizarse y **bunny hop** tienen
   inercia real y se sienten bien; el terreno que trabajas es el que te permite ir
   rápido. Desplazarse es divertido por sí mismo.
4. **El caos entre amigos es contenido, no un fallo.** Tirarse bolas, enterrarse,
   volcar la carretilla del otro y reírse: el juego lo **celebra y lo mide**, y
   todo es **reversible** (nunca se pierde progreso). Sin castigo, sin toxicidad.
5. **Relax por defecto, caos opcional.** Sin estados de fallo, sin temporizadores,
   sin QTE. El estrés se activa (retos, tormentas, duelo), no se impone.
6. **Objetivos por estado del mundo, no por pasos guionizados.** "Despeja el 90 %"
   y "deja la nieve en el camión" son medibles y permiten cualquier solución.
7. **Coleccionar y descubrir.** Regalos escondidos y secretos que la comunidad
   destripa: dan una segunda (y tercera) razón para volver a cada nivel.

**Lo que NO somos:** ni survival, ni crafting, ni terror, ni gestión de recursos
escasos, ni un juego de trolls. Si una mecánica añade ansiedad sin añadir
satisfacción, o permite que alguien arruine la partida *de verdad* a otro, fuera.

**Regla de oro del gamberrismo:** *toda trastada tiene que ser graciosa para quien
la recibe*. Si el que la sufre no se ríe, está mal diseñada.

---

## 3. Fantasía, tono y escenario

> **La ubicación está SIN DECIDIR** y no condiciona ninguna mecánica. Lo que sigue
> describe el tono, no un escenario cerrado: sirve cualquier sitio donde haya nieve
> que quitar y objetos que mover. Nada del diseño depende de que sea un pueblo
> alpino, una urbanización o una estación de esquí.

**Fantasía:** ha nevado muchísimo y hay que despejar. Se hace solo o con alguien, sin
prisa y sin enemigos: montañas de nieve, un encargo que cumplir y tiempo para
hacer el gamberro con quien te acompañe.

- **Tono:** cálido, luminoso, ligeramente absurdo. Humor *físico* (te caes, la
  avalancha te sepulta, el muñeco se desmorona), nunca humillante entre jugadores.
- **Escenario:** un valle alpino pequeño. Casa del jugador → calle → plaza → pista
  de esquí → río helado → teleférico. Un solo *hub* (la plaza del pueblo) con
  propiedades alrededor: abarata el arte y da sensación de mundo continuo.
- **Hora del día y clima** como variación barata de contenido: amanecer, día gris,
  atardecer dorado, nevada suave, ventisca (nivel avanzado).

---

## 4. Bucle de juego

| Escala | Duración | Contenido | Recompensa |
|---|---|---|---|
| **Micro** | 10–60 s | Elegir herramienta → aplicarla → la nieve se mueve → suena bien, salta nieve, sube el % | *Juice*: sonido, partículas, número que sube |
| **Meso** | 5–15 min | Un nivel: despejar al X %, objetivos opcionales, llevar la nieve a su destino | Dinero, estrellas, desbloqueo siguiente |
| **Macro** | 1,5–3 h | La temporada: despejar el valle, mejorar herramientas, epílogo | Muñeco final, sandbox, retos |

**Sesión cooperativa típica (20–40 min):** lobby → 2–3 niveles → tienda → "una más".
Debe poder entrarse y salirse **en cualquier momento** (drop-in/drop-out).

**Gancho de retención:** el marcador de "% despejado" subiendo + el sonido de la
pala. Es adictivo por lo mismo que *Leaf it Alone* es "Incremental": números que
suben y una superficie que se limpia visualmente.

---

## 5. Mecánicas

### 5.1 Movimiento e interacción ✅
Primera persona, caminar/correr/saltar sobre la nieve (el jugador *se hunde* según
la altura del manto ✅), sin armas. Interacción: `E` (pulsación = coger/apelmazar;
mantener = empujar por el suelo ✅), click izq = herramienta, click der = lanzar/
verter ✅. Modo mano libre (sin herramienta) para llevar objetos ✅.

### 5.1.1 Inercia, deslizamiento y bunny hop ⬜ (decisión tomada)

El movimiento deja de ser "caminar con freno" y pasa a ser **una habilidad con
techo**, porque desplazarse por un pueblo nevado tiene que ser divertido en sí
mismo. Cuatro piezas:

**1. Fricción según la superficie.** El suelo no frena igual en todas partes:

| Superficie | Fricción | Sensación |
|---|---|---|
| Camino despejado / nieve compactada (palmeada, pisada) | Muy baja | Corres y mantienes impulso |
| Nieve polvo (virgen, seca) | Alta | Te hundes, se te corta la velocidad |
| Hielo / slush (sal + nieve) | Casi nula | Resbalas, no puedes frenar |
| Cuesta abajo | — | Ganas velocidad sola |

**2. Bunny hop.** Si encadenas saltos al ritmo correcto **no pagas la fricción del
aterrizaje**: conservas la velocidad y, combinándolo con *air strafe*, la aumentas
hasta un **tope del 1,6× de la carrera**. El tope es deliberado: queremos una
habilidad de desplazamiento satisfactoria, no un exploit que rompa el juego.

**3. La nieve le da sentido al bunny hop** (esto es lo bonito): sólo funciona bien
sobre superficie **compactada o despejada**; en polvo profundo te hundes y pierdes
el impulso. Y aquí está el enganche con el resto del juego: **al aterrizar dejas la
nieve compactada**, así que brincar en línea recta **traza un camino pisado**. Los
jugadores van a descubrir solos que brincar en fila es la forma rápida de hacer un
sendero — y que después por ese sendero se corre mucho más. Es una mecánica
emergente, coherente con la masa conservada (compactas, no retiras) y que refuerza
el pilar 1.

**4. Juguetes de movilidad** (cada uno barato de hacer y muy vendible en un GIF):
- **Deslizarse con la pala** (ride): pendiente abajo sobre la hoja, con control de
  inclinación y nieve saltando.
- **Trineo**: en el hub y en 1–2 niveles; transporta nieve *o* a un compañero.
- **Quad con pala** (niveles avanzados): en solitario es tu multiplicador de fuerza;
  con dos personas es un juguete de dos (uno conduce, el otro carga y aguanta).
- **Patada**: golpe ligero que empuja bolas y props. Sirve para jugar al fútbol con
  las bolas mientras te desplazas, y es la base de media docena de trastadas.

**Coste técnico:** bajo. Es el controlador de jugador (fricción por superficie
consultando el manto ✅ ya hay consultas de altura/cohesión), un multiplicador de
velocidad con tope y dos o tres objetos físicos.

**Accesibilidad:** el bunny hop es **opcional**; hay un ajuste de *auto-bhop*
(mantener salto) y la velocidad máxima no depende de dominarlo. En mando, salto en
A/cruz y carrera en gatillo o stick pulsado.

**Añadir además ⬜:** agacharse, rodar/caerse y levantarse (comedia física), subirse
a montones, agarrar y arrastrar, apuntar/zoom ligero para las bolas.

### 5.2 La nieve como material ✅
Reglas que ya existen y son el corazón del juego:

- Masa conservada: siega (carve/harvest), depósito (dump), apelmazado (tamp),
  vertido y reabsorción de fragmentos.
- Canales de simulación: altura, nieve suelta, cohesión/humedad y fase (en reposo /
  fluyendo) → **histeresis bi-fásica**: la nieve virgen aguanta paredes verticales,
  la nieve seca se desmorona en ángulo de reposo.
- Ángulo de reposo según humedad; la sal reduce cohesión; el palmeo compacta.
- Superficie deformable renderizada por malla + normales filtradas ✅.

**Explotar más (⬜):**
- **Pisadas y surcos persistentes** (huellas, ruedas, marcas de pala) — barato y
  vendido como *juice*.
- **Nieve que se ensucia** (tierra, hojas) y se puede re-limpiar → rejugabilidad.
- **Hielo** como material distinto (duro, resbaladizo, se rompe con pico) y
  **agua/slush** como salida legítima de masa (desagüe, río).
- **Costras** (capas duras) en niveles avanzados.

### 5.3 Herramientas

Cada herramienta es **un verbo físico**, no una skin. Se mejoran por separado.

| # | Herramienta | Verbo | Fuerte en | Débil en | Mejora | Ñapa coop |
|---|---|---|---|---|---|---|
| 1 | **Pala** ✅ | corta, empuja, carga, palmea, lanza | todo, lento | volumen | capacidad, filo, fuerza | cargar entre dos |
| 2 | **Quitanieves / empujadora** ⬜ | empuja grandes volúmenes | superficies amplias | detalle, bordes | ancho, ángulo, peso | empujar entre dos |
| 3 | **Turbina/sopladora** ✅ | lanza nieve suelta al aire | rápido, montones | nieve compacta/húmeda | caudal, alcance | dirigir el chorro |
| 4 | **Salero** ✅ | descohesiona, derrite, crea slush | hielo, costras | volumen | radio, caudal | — |
| 5 | **Pico/hacha** ⬜ | rompe hielo y costras | capas duras | nieve suelta | daño, velocidad | — |
| 6 | **Rastrillo** ⬜ | nivela capas finas | acabado, precisión | volumen | ancho, fino | — |
| 7 | **Carretilla / trineo** ⬜ | transporta masa | logística | terreno abrupto | capacidad, ruedas | **dos personas** para la llena |
| 8 | **Manguera / vapor** ⬜ | derrite (masa → agua, drena) | final del juego | lento, moja | caudal, alcance | — |
| 9 | **Bolas de nieve** ✅ | jugar, empujar, romper | diversión | trabajo | masa, agarre | **pasarse bolas** |

**Progresión de herramienta:** 3 niveles por herramienta (básica → pro → industrial),
con estadísticas visibles y cambio *sentido* (no solo números: la sopladora pro
alcanza tejados, la pala pro corta capas que antes rebotaban).

### 5.4 Bolas, apilado y construcción ✅
Ya existe: fabricar con las manos, rodar y crecer por acreción, densidad creciente
(300→470 kg/m³), acarreo a una/dos manos con tambaleo y agarre, lanzamiento por masa,
unión física al apilar, rotura por impacto con fragmentos y devolución de masa al manto.

**Su papel en el juego:**
- **Herramienta de trabajo real**: rodar una bola grande compacta un camino, tapa
  una boca de desagüe, hace de contrapeso o de escalón para subir a un tejado.
- **El juguete social por excelencia** (ver §6.6): pasarse bolas, duelos, trastadas.
- **Muñeco de nieve: extra opcional y divertido, NO objetivo.** Se puede construir
  en el hub y en el sandbox con las tres bolas y los accesorios ✅ (zanahoria,
  carbón, ramas); el juego lo reconoce con un logro y un adorno para el pueblo, y
  sirve de escaparate de los cosméticos. Nada de la campaña depende de él: es un
  juguete para el que quiera entretenerse.
- **Puntería**: dianas, cubos y un mini-juego de encestar bolas (base del duelo y
  de un par de retos de nivel).

### 5.5 Objetivos y evaluación ⬜
Sistema **componible** (cada objetivo es una condición evaluable por tick):

| Tipo | Ejemplo | Medición |
|---|---|---|
| Cobertura | "Despeja el 90 % del camino" | % de celdas con altura < umbral ✅ (% ya existe) |
| Destino de masa | "Toda la nieve al camión" | Masa acumulada en zona válida |
| Precisión | "No cortes el seto" | Integridad de props |
| Construcción | "Haz un muñeco de 3 bolas" | Grafo de uniones ✅ (existe la unión) |
| Recuperación | "Encuentra las 5 herramientas perdidas" | Objetos desenterrados |
| Tiempo (opcional) | "Antes del mediodía" | Sólo en modo reto |
| Equipo | "Los dos a la vez en la misma tarea" | Proximidad + misma acción |

**Evaluación:** 1–3 estrellas según cobertura + opcionales + eficiencia (kg movidos
por minuto). Las estrellas pagan más dinero; **nunca bloquean el avance** (siempre
se puede seguir jugando el siguiente nivel).

### 5.6 Economía y progresión ⬜
- **Dinero** por kg de nieve *bien colocada* (a destino válido) + bonus por
  opcionales + bonus coop (trabajo simultáneo).
- **Tienda**: herramientas nuevas + mejoras + cosméticos (palas, guantes, gorro,
  colores de bola, pegatinas de la carretilla).
- **Sin micropagos.** Todo se gana jugando.
- **Panel de estadísticas**: kg movidos, m² despejados, bolas lanzadas, muñecos,
  avalanchas provocadas, tiempo total, "snow efficiency".
- **Desbloqueo por progreso**, no por dinero: los niveles se abren al completar el
  anterior; el dinero compra comodidad.

### 5.7 Peligros y caos opcional
Por defecto **nada puede fallar**. Activables:
- **Avalanchas**: la nieve por encima de cierto ángulo puede desprenderse y
  sepultar a un jugador (se libera solo, sin muerte: 2 s de "¡ay!" y a seguir).
- **Tejados**: la nieve de un tejado cae de golpe; el que esté debajo queda enterrado.
- **Hielo fino**: caer al agua = remojón y volver al borde.
- **Ventisca**: nieva mientras limpias (nivel avanzado; la masa que cae es real).
- **Modo trabajo** (opcional): fatiga, peso que frena de verdad, sin ayudas.

### 5.8 Modos de juego
1. **Campaña** (1 jugador **o** 2 en coop, las dos experiencias completas): 10
   niveles + epílogo. **El 100 % del progreso es alcanzable en solitario**; el coop
   añade su propia capa de sellos extra sin bloquear nada (§5.9).
2. **Sandbox / Campo libre**: todas las herramientas, nieve infinita, sin objetivos.
   Es la carta de presentación del motor y el imán para contenido de creadores.
3. **Duelo de bolas** (§6.6): arena, 1v1 o 2v2, marcador y asaltos de 2 minutos.
4. **Retos**: misma semilla y objetivos para todos, marcador global.
5. **Temporada 2 (NG+)**: el valle se vuelve a nevar con **nieve distinta** (§5.9).
6. **Foto** (dentro de cualquier modo): cámara libre, poses, filtros.

### 5.9 Rejugabilidad: el Libro del Invierno (2–3 vueltas para el 100 %) ⬜

El juego no se completa en una pasada, y **no por grind, sino porque los retos se
contradicen entre sí**. Cada nivel guarda en el *Libro del Invierno*:

- **3 sellos por nivel, mutuamente excluyentes en una misma partida:**

| Sello | Reto | Ejemplo |
|---|---|---|
| **Limpio y rápido** | Eficiencia | Terminar bajo el tiempo objetivo o con X kg/min |
| **Impecable** | Sin destrozos | No romper props, no dejar montones fuera de zona, no pisar lo protegido |
| **Con estilo** | Método restringido | Sólo con la pala, sin sopladora, sólo con bolas, sin usar el camión |

  Como no caben en una sola vuelta, **conseguir los tres obliga a repetir el
  nivel** (y a jugarlo de otra manera, que es lo importante).
- **Retos de campaña** (partida nueva de verdad): toda la campaña sin comprar
  mejoras · sin sopladora · en **modo Trabajo** · sólo de noche · todos los regalos
  en una sola pasada.
- **Regla de paridad solo/coop:** *todo lo que cuenta para el 100 % se puede
  conseguir en solitario*. Los retos que necesitan dos personas (no lanzarse ni una
  bola, o lanzarse 200) existen como **sellos de compañía**: dan cosméticos y
  orgullo, se lucen en el Libro, pero **no bloquean el 100 %** de nadie.
- **Logros compartidos:** un único conjunto de logros. En coop se desbloquean
  **para los dos jugadores a la vez** y los contadores suman lo de ambos; y
  **ningún logro exige una segunda persona** (los de impactos se consiguen contra
  dianas y muñecos de entrenamiento). Así los dos modos son igual de completos.
- **Temporada 2 (NG+)**: los mismos niveles con **el manto cambiado** — polvo seco
  (no aguanta paredes), costra dura (hay que picar), nieve húmeda y pesada (se pega
  y pesa el doble) y más masa total. Es **contenido casi gratis con sensación de
  juego nuevo**, porque toda la dificultad vive en el material, no en el escenario.

**Resultado:** 1,5–2,5 h la primera vuelta, **6–9 h el Libro completo**, y cada
vuelta cambia *cómo* se juega, no sólo cuánto.

### 5.10 Coleccionables y secretos ⬜

**24 regalos navideños** (desbloquean cosméticos: gorros, guantes, pieles de pala,
bolas especiales, adornos para el pueblo y el muñeco; **nunca poder de juego**):

- **12 en los niveles**: siempre en un sitio que exige usar bien una herramienta —
  dentro de un montón que hay que palear, en un tejado al que se sube con una bola,
  congelado en el hielo (hay que romperlo), en el fondo de un pozo, bajo un coche,
  en una chimenea, enterrado donde el perro mira.
- **12 en el pueblo (hub)**: accesibles sólo con habilidad (cadena de bunny hops,
  salto con trineo, soplar la nieve de una cornisa, deslizarse por un cable).
- Pistas **visuales y sutiles** (un lazo asomando, un brillo helado, un perro que
  insiste) — nunca un icono de mapa con flecha. Buscar es parte del juego.

**6 huevos de pascua muy escondidos**, diseñados para que **la comunidad los
destripe** (eso es marketing gratis: hilos, vídeos, "¿alguien ha visto…?"):

1. Un **yeti** que aparece si dejas un nivel intacto y de noche durante 3 minutos.
2. Una **puerta enterrada** en un punto concreto del hub → pequeña sala de desarrollo.
3. La **bola de nieve dorada**: encestar 10 seguidas sin fallar en el cubo del hub.
4. El **pozo**: si tiras un objeto concreto, cambia el clima del pueblo para siempre.
5. **Curling / minigolf** en un charco helado escondido tras una valla.
6. Un **homenaje al género**: una sopladora de hojas enterrada, cubierta de hojas.

**Criterio de diseño:** sin pistas escritas, pero siempre **deducibles** por una
rareza visual o sonora. Un secreto que nadie puede encontrar no es un secreto, es
contenido perdido; uno que se encuentra por casualidad el primer día no es un
secreto. Los regalos y secretos alimentan logros, y los logros son la tercera
vuelta del Libro del Invierno.

---

## 6. Diseño cooperativo (el diferencial)

### 6.1 Por qué coop (de 2) y no "single + coop pegado"
El coop cambia el diseño desde la base, no se añade después. **2 jugadores exactos**
(no 4): es la cifra que hace que la logística física sea íntima y legible, que el
netcode sea asumible y que los niveles se puedan dimensionar bien. Y como el juego
también debe jugarse en solitario, el coop se apoya en tres cosas:

- **La nieve compartida es el juguete común.** Todo lo que uno mueve, el otro lo ve
  y lo puede deshacer. Es la receta del caos cómico sin necesidad de guion.
- **Los objetos pesados son la excusa social.** Ya existe el umbral de 35 kg a dos
  manos ✅; añadimos que **un compañero reduzca el tambaleo y el gasto de agarre**
  (los dos sostienen = se puede llevar más lejos). Eso convierte "llevar algo" en
  una conversación.
- **Los combos emergentes son el contenido infinito**: uno sopla la nieve al aire y
  el otro la empaqueta; uno corta la base y el otro empuja la cornisa; uno se sube
  encima del montón y el otro se lo lleva rodando.
- **El tiempo compartido es parte del producto** (§6.6): entre dos, el juego también
  va de tirarse bolas y de destrozarse la pila. Eso es tiempo de juego que no cuesta
  contenido.

### 6.2 Verbos cooperativos (lista cerrada y verificable)

| Verbo | Mecánica | Estado |
|---|---|---|
| **Pasarse bolas** | lanzar con impulso físico, recibir pulsando `E` cerca | ⬜ recibir (lanzar ✅) |
| **Levantar entre dos** | si ambos sostienen, ÷ tambaleo y ÷ gasto de agarre | ⬜ |
| **Empujar entre dos** | carretilla/objeto: fuerza suma, se mueve mucho más | ⬜ |
| **Impulsar a un compañero** | subirse a una bola/montón y que el otro empuje | ⬜ (física ya lo permite) |
| **Cadena de trabajo** | uno siega y lanza, otro recibe y apila | ⬜ |
| **Rescate** | desenterrar a un compañero sepultado por una avalancha | ⬜ |
| **Sincronía** | objetivos que premian estar los dos en la misma tarea | ⬜ |
| **Ping/gestos** | marcar un punto del mundo, señalar, saludar, tirar bola | ⬜ |

### 6.3 Estructura de sesión y lobby ⬜
- **Online de 2 jugadores** por Steam (lobby + invitación por overlay). El "coop
  local" se cubre con **Remote Play Together**, que es gratis y ya funciona en Deck:
  cero trabajo extra y cubre el sofá.
- **Elección de modo de sesión** (esto gobierna toda la capa social):
  **Trabajo** (nada de lo que haga el otro te afecta) · **Jaleo** (por defecto, con
  amigos: las bolas y las trastadas hacen efecto) · **Duelo** (arena de bolas).
- **Drop-in/drop-out** en cualquier momento; el que entra se sincroniza con el
  estado actual de la nieve.
- **Lobby**: dos slots, listo, elección de nivel, modo de sesión, cosmético, y
  **pings rápidos** en el mundo (marcar un punto, señalar, pedir ayuda).
- **Pausa compartida**: sólo el host, con aviso.
- **Host**: autoridad total (y autoridad del marcador, ver §6.5). Si se cae, se
  ofrece "reanudar desde el guardado" (sin migración en vivo).
- **Privacidad**: por defecto **sólo amigos** — el modo Jaleo con desconocidos es
  divertido o es un dolor de cabeza, según el día.

### 6.4 Anti-frustración y escalado
- **Nada de progreso perdido, nunca.** Ni dinero, ni estrellas, ni desbloqueos. Lo
  que se puede perder es tiempo y orgullo, y eso se recupera limpiando otra vez.
- **El daño entre jugadores depende del modo de sesión** (§6.3): en *Trabajo*, las
  bolas atraviesan (no afectan); en *Jaleo*, afectan con reacciones exageradas y
  siempre reversibles; en *Duelo*, es el objetivo.
- Objetivos **compartidos**, estadísticas **individuales** y una **crónica** al
  final que premia también las trastadas (§6.6): competir sin que nadie pierda.
- Ningún jugador puede **bloquear** a otro: nada de puertas cerradas, nada de
  objetos únicos irrecuperables (si algo cae al río, vuelve; si algo se rompe, se
  puede volver a fabricar con nieve).
- "Sin fallo": quedarse sepultado, caer al agua o destrozar la pila del otro no
  cuesta progreso. Sólo se paga en tiempo y en risas.
- **El reparto del trabajo entre 1 y 2 jugadores se diseña explícitamente** con el
  sistema `PlayerCountScaler` (ver `plan_implementacion.md` §3.4): se escalan
  **requisitos, nunca la física**, y en solitario nunca se pide algo que necesite
  dos manos. Ambos modos deben sentirse igual de bien, no "uno bien y otro de
  consolación".

### 6.5 Netcode (lo técnico, sin adornos)

**El problema:** el manto es una textura RGBA32F de 512² en GPU. No se puede
replicar por frame. **La solución: replicar operaciones, no píxeles.**

- **Autoridad del host.** El host corre la simulación canónica y aplica toda
  operación. Los clientes envían *peticiones* de operación (siega, depósito,
  palmeo, siega de bola, vertido) con parámetros ya validados en cliente para
  respuesta inmediata local.
- **Replicación:**
  1. `op_apply` (RPC fiable) con el mismo paquete de uniformes que usa la GPU
     (posición, radio, profundidad, modo, índice de op).
  2. **Predicción local optimista** en el cliente para su propia pala (el jugador
     ve su surco al instante) + reconciliación: si el host rechaza o corrige, el
     cliente vuelve a aplicar las ops confirmadas sobre una copia limpia.
  3. **Resync periódico**: cada 10 s y al entrar un jugador, el host manda un
     **parche RLE** (sólo celdas cambiadas) o un **mapa reducido** (p. ej. 128²
     cuantizado a 16 bits en 4 canales ≈ 128 KB) comprimido. Presupuesto:
     **≤ 30 KB/s por cliente en régimen normal**, picos de 150 KB en resync.
  4. **Determinismo suficiente**: hay que auditar el shader para evitar
     `sin/cos/pow/exp/normalize` en el camino de la relajación (no son
     bit-exactos entre GPUs) y quedarse en `+ - * / min max clamp step mix`.
     Tolerancia aceptada: ±1 téxel de deriva, que el resync periódico limpia.
     Si la auditoría falla, **plan B**: el host manda parches RLE cada 2 s y el
     cliente no simula, sólo interpola (más tráfico, cero riesgo).
- **Cuerpos (jugadores, bolas, props):** `MultiplayerSynchronizer` con el host
  autoritativo e interpolación en cliente. Casos especiales:
  - Bola **en las manos** de un cliente → predicción local del acarreo, el host
    valida la posición y el lanzamiento (el impulso se calcula en el host a partir
    de la masa y la mirada).
  - **Uniones de apilado** (weld): sólo el host las crea/rompe; se replican como
    evento.
  - **Rotura por impacto**: evento del host (posición, masa, semilla) para que los
    fragmentos salgan iguales en todas las pantallas.
- **Presupuesto de latencia objetivo:** jugable hasta 120 ms. Para un juego cozy
  sin puntería fina es aceptable; la nieve no necesita interpolación perfecta.
- **Carga inicial de nivel:** el estado inicial del manto se genera con **semilla
  compartida** (determinista en todas las máquinas, sin transferir la textura).
- **Servicio:** Steam Datagram Relay (sin puertos, sin NAT que configurar) +
  Steam Lobby. Es lo que espera el jugador de un juego de 7 €.

**DECISIÓN TOMADA (opción 4 del plan anterior).** Con 2 jugadores y este alcance, se
implementa **el plan A tal cual está descrito arriba: el cliente simula, predice sus
propias ops y el host corrige con parches RLE periódicos**. Motivos:

1. El cliente simula porque es lo que se *siente* bien (tu pala responde en el
   frame en que la mueves) y porque ya tenemos el motor hecho: no simulando habría
   que inventar una capa de presentación falsa.
2. El host sigue siendo la autoridad del **marcador** (masa y %), así que una
   deriva de la textura del cliente es cosmética y nunca afecta al progreso ni a
   los logros: no puede haber trampas ni puntuaciones raras.
3. **Spike obligatorio de 2 semanas** antes de comprometer el hito coop: dos
   instancias headless replicando ops + resync, midiendo (a) deriva de masa por
   minuto, (b) KB/s por cliente, (c) ms de CPU de red. Umbrales de aceptación:
   **deriva < 0,5 % por nivel y < 30 KB/s de media**.
4. Si el spike falla esos umbrales, el plan B ya está definido y **no cambia el
   diseño del juego**: el cliente deja de simular y sólo interpola los parches del
   host (más tráfico y menos inmediatez, misma diversión). Y si el determinismo del
   shader da problemas, se recorta el resync a cada 2 s y listo: en un juego cozy
   nadie va a notar un surco que aparece 2 segundos tarde.

---

### 6.6 Bolas, trastadas y estados: la capa social ⬜

Los números exactos viven en `plan_implementacion.md` §3.2; aquí está el diseño.

**Impacto de bolas sobre jugadores** (sólo en modo **Jaleo** y **Duelo**; en
**Trabajo** las bolas no afectan). La bola tiene que venir **lanzada**, no rodando:

| Bola | Al **cuerpo** | A la **cara** |
|---|---|---|
| **Pequeña** (r < 0,18 m · 1–8 kg) | nada (sólo sonido y salpicadura) | **cara llena de nieve** |
| **Mediana** (0,18–0,34 m · 8–60 kg) | **desestabilizado 1 s** | desestabilizado 1 s **+ nieve en la cara** |
| **Grande** (r ≥ 0,34 m · > 60 kg) | **derribado 2 s** (suelta lo que llevaba) | derribado 2 s **+ nieve en la cara** |

- **Nieve en la cara**: se quita sola en **3,5 s** o el jugador se la limpia
  **manualmente en 0,6 s**. No inmoviliza: se anda y se oye, se ve mal. Ajuste
  *Normal* (se quita sola) / *Realista* (sólo manual).
- **Anti-`stun-lock`**: inmunidad de 1,5 s al salir de cualquier estado. Nunca se
  puede encadenar un derribo sobre la misma persona.

**El catálogo de trastadas** (cada una con su animación y su sonido, que es lo que
la hace graciosa): bola a la cara · nieve por el cuello · enterrar al compañero
(se libera machacando) · tapar la salida de la turbina · volcar la carretilla ·
empujarle una bola gigante cuesta abajo · pisotear su pila recién hecha · tirarle el
gorro de un bolazo · dejar huellas en la superficie que acaba de alisar · taparle la
puerta con una pared de nieve.

**Las reglas que evitan que esto sea tóxico:**
1. **Todo es reversible.** Ni dinero, ni estrellas, ni progreso. Sólo tiempo y orgullo.
2. **Se celebra y se mide.** Al acabar el nivel, una **crónica** con premios absurdos:
   *Mejor compañero*, *Peor compañero*, *Más bolas lanzadas*, *Enterrado 4 veces*,
   *Trabajo arruinado: 38 kg*, *La pila más alta destruida*. Es lo que convierte
   "me lo has destrozado" en "lo repetimos".
3. **La víctima se ríe** (regla de oro del pilar 4). Si no se ríe, la trastada está
   mal diseñada.
4. **Modo de sesión** (§6.3): el que quiere trabajar puede; el caos es una elección.

**Duelo de bolas** (modo aparte, barato porque la mecánica ya existe): arena,
asaltos de 2 minutos, marcador, mutadores (bolas gigantes, hielo resbaladizo, nieve
infinita).

**En solitario esta capa no desaparece**: los rebotes pueden dejarte a ti con la cara
llena de nieve, y hay **muñecos de entrenamiento** con las mismas reacciones para
practicar y para los logros.

---

## 7. Contenido: niveles

10 niveles + sandbox. Cada uno introduce **una herramienta o una idea nueva** y
reutiliza el kit modular del valle.

| # | Nivel | Idea nueva | Objetivo principal | Opcionales |
|---|---|---|---|---|
| 1 | **Entrada** ✅ | pala, apelmazar, lanzar | despejar el camino al 90 % | no pisar el parterre |
| 2 | **El coche enterrado** | destino de masa (no se puede dejar encima) | liberar el coche | no rayar la chapa |
| 3 | **Tejado y canalones** | altura y avalancha sobre el compañero | bajar la nieve del tejado | dejar los canalones libres |
| 4 | **Jardín y setos** | precisión (rastrillo, bordes) | despejar sin dañar el seto | recoger 3 juguetes perdidos |
| 5 | **Plaza del mercado** | carretilla y pilas | despejar la plaza y llenar el camión | hacer una pila de 2 m |
| 6 | **Pista y remonte** | pendiente, ángulo de reposo, aludes | asegurar la pista | provocar un alud controlado |
| 7 | **Río helado** | hielo, slush, desagüe | abrir el paso | pescar algo del hielo |
| 8 | **Calle del pueblo** | logística coop pura | cargar el camión entre dos | terminar con los dos en la tarea |
| 9 | **Teleférico** | verticalidad, riesgo | despejar la estación | subir a la plataforma |
| 10 | **Tormenta / epílogo** | todo junto + muñeco final | despejar el valle | el muñeco más grande posible |

**Kit de arte modular:** 1 terreno base + 1 set de edificios alpinos + 1 set de
props (vallas, coches, bancos, buzones, carteles, esquis) + 1 set de árboles +
1 set de rocas/hielo. Con eso y variaciones de luz/clima, 10 niveles son realistas
para un equipo pequeño.

**Autoría de niveles (⬜):** formato de datos (`.tres`/JSON) con: terreno (mapa de
alturas inicial), lista de props, zonas de destino de masa, objetivos, clima,
herramientas permitidas e iluminación. Un script de editor que exporta el nivel.
Así el sandbox y los retos reutilizan el mismo sistema.

---

## 8. Dirección de arte y audio

**Arte**
- Estilo actual ✅ (bajo poligonaje, paleta pastel, formas limpias) es el correcto:
  barato, legible y aguanta bien en pantallas pequeñas.
- Necesario ⬜: viewmodels de las 8 herramientas con animación (idle, uso, inclinar,
  golpe, guardar), **cuerpo visible del otro jugador** (cápsula + brazos
  procedurales basta), set de props, iconos de UI, set de partículas (nieve
  levantada, nube de rotura ✅ existe, pisadas, salpicón de slush).
- Rendimiento de nieve: malla deformable + detalle de superficie (destellos, huellas)
  como *decals* baratos.

**Audio** (clave en este género: **es el 50 % de la satisfacción**)
- Capas de *crunch* de nieve según material, profundidad y herramienta.
- Sonidos de "scoop", "vuelco", "impacto blando", "costra rota", "agua".
- Ambiente: viento por altura, cuervos, pueblo lejano, radio de la casa.
- **Música adaptativa por progreso:** más instrumentos a medida que sube el % de
  limpieza. Es un truco de dopamina baratísimo.
- Voces: ninguna doblada (por coste). Sólo exclamaciones cortas y subtituladas
  ("¡ay!", "¡cuidado arriba!"). El coop usa voz del sistema/Steam.

---

## 9. UX / UI: mapa de pantallas

```
[Boot: logo → compilación de shaders/carga de ajustes]
   ↓
[MENÚ PRINCIPAL] — escena 3D viva de fondo (cámara lenta sobre el pueblo nevado)
 ├── Continuar
 ├── Nueva partida ─────────► [Selector de perfil/ranura]
 ├── Cooperativo ──────────► [LOBBY] ──► [Nivel] ──► [Resultados]
 ├── Niveles ──────────────► [Mapa del valle / rejilla de tarjetas]
 ├── Taller (tienda) ──────► [Herramientas + mejoras + cosméticos]
 ├── Extras ───────────────► [Logros · Estadísticas · Galería (modo foto) · Créditos]
 ├── Opciones ─────────────► [Vídeo · Audio · Controles · Juego · Accesibilidad · Red · Datos]
 └── Salir
```

**En partida**
- **HUD** (diegético, mínimo): % despejado y masa restante, dinero, herramienta
  actual + carga ✅, objetivos activos con palomita, marcador de zona de destino,
  brújula sutil, indicadores de compañeros (nombre, color, ping de volea), pistas
  contextuales ✅ (una línea, sin tutoriales invasivos).
- **Pausa** (host en coop): reanudar · objetivos · opciones · invitar (host) ·
  abandonar · "hacer foto".
- **Resultados**: % final, kg movidos, eficiencia, tiempo, estrellas, dinero
  ganado, barras de contribución por jugador, captura automática de pantalla.

**Flujos críticos a cuidar**
1. De "abrir el juego" a "estoy paleando": **≤ 3 clics / ≤ 20 s**.
2. De "me llaman para jugar" a "estoy dentro" (invitación por overlay): ≤ 60 s.
3. Cambiar de herramienta sin abrir menús (rueda o 1-8).
4. Saber siempre qué falta sin leer nada (barra + marcador en el mundo).
5. Salir y volver a entrar sin perder progreso (guarda al salir de nivel).

---

## 10. Ajustes (catálogo completo)

| Categoría | Opciones |
|---|---|
| **Vídeo** | Preset (Bajo/Medio/Alto/Ultra/**Auto**) · resolución · ventana/borderless/exclusiva · **escalado de resolución** (0,5–1,0) · VSync · límite FPS · FOV · desenfoque de movimiento · profundidad de campo · bloom · sombras (calidad/distancia) · SSAO · niebla volumétrica · **calidad de nieve** (resolución de sim 256/384/512/768 + subdivisión de malla) · densidad de partículas · distancia de dibujo · HDR · gamma/brillo · nitidez |
| **Audio** | Maestro · música · efectos · ambiente · voces · dispositivo de salida · **modo mono** · compresión dinámica · ducking · "reducir sonidos repetitivos" |
| **Controles** | Remapeo completo (teclado+ratón y mando) · presets · sensibilidad (y por zoom) · invertir X/Y · zona muerta · curva de respuesta · vibración · **mantener vs alternar** (correr, agachar, `E`, vertido) · inversión de botones · prompts según dispositivo (Xbox/PS/Switch) · Steam Input |
| **Juego** | Idioma · **unidades (métrico/imperial)** · dificultad/asistencia (Relax ↔ Trabajo) · autoguardado · pistas del tutorial · marcadores de objetivo · avisos de masa · telemetría (opt-in) |
| **Accesibilidad** | Subtítulos (activar/tamaño/fondo) · **tamaño de la UI** (80–150 %) · daltonismo (3 paletas + contraste alto) · reducción de movimiento/cámara · **desactivar cabeceo** · sensibilidad al *screen shake* · sin entradas temporizadas (regla del género) · mantener pulsado alternable · remapeo de todo · texto a voz del HUD (opcional) |
| **Red** | Región · límite de ping · voz (activar/push-to-talk/volumen por jugador/silenciar) · privacidad (invitación sólo amigos / abierto) · mostrar pings de jugador |
| **Datos** | Ranuras de guardado · exportar/importar progreso · borrar progreso · estado de Steam Cloud · versión del guardado |

**Reglas de diseño de ajustes:** todo cambio se aplica **en vivo**; todo se guarda
en un archivo de configuración de usuario separado del guardado de partida;
"Restaurar por defecto" por categoría; y ningún ajuste puede dejar el juego injugable
(si un preset es demasiado bajo, se avisa).

---

## 11. i18n y accesibilidad

### Idiomas objetivo (fase 1) — los 13 de la referencia
Inglés, Español (España + Latinoamérica como variantes), Francés, Alemán, Italiano,
Portugués (Brasil), Polaco, Ruso, Checo, Chino simplificado, Chino tradicional,
Japonés, Coreano. **Sólo texto** (interfaz + subtítulos), sin doblaje.

### Arquitectura i18n
- **Claves semánticas**, nunca literales concatenados:
  `HUD_CLEARED_PCT` = `Despejado: {pct}%`.
- **Plurales desde el día 1** con reglas por idioma (`tr_n`): checo/polaco/ruso
  tienen 3–4 formas. Es el error clásico que obliga a rehacer textos.
- **Sin género gramatical asumido**: redactar de forma neutra o con variantes por
  idioma (en español "la bola / el montón" cambia; evitar adjetivos sobre objetos
  del jugador).
- **Formato locale** de números, unidades y fechas (`1.234,5 kg` vs `1,234.5 kg`),
  más el conmutador métrico/imperial.
- **Nada de texto en imágenes**; todo texto pasa por el sistema de traducción.

### Fuentes y layout
- Una familia con cobertura completa (p. ej. Noto Sans) + **cadena de respaldo**
  explícita para CJK y cirílico (Godot no hace *fallback* automático completo).
- **Espacio para +40 % de longitud** (el alemán y el ruso crecen) y prueba de
  desbordamiento con **pseudo-localización** (texto acentuado y alargado).
- Saltos de línea CJK (sin espacios) verificados en las cajas de texto.

### Pipeline
1. Extraer claves del código a un CSV/PO fuente en el repo.
2. Subir a un TMS (Crowdin/Lokalise/Weblate) para traductores.
3. Importar traducciones compiladas + **CI que falla si falta una clave en algún
   idioma**.
4. Modo QA en el juego: resalta claves sin traducir en tiempo de ejecución.
5. Créditos de traducción y licencias de fuentes.

### Accesibilidad (lo mínimo exigible al género)
Subtítulos · tamaño de UI · daltonismo · reducción de movimiento · **sin entradas
temporizadas** · guarda cuando quieras · mando completo · todo remapeable ·
un solo mando posible · avisos visuales además de sonoros (una avalancha se **ve**
antes de oírse, y se subtitula el aviso).

---

## 12. Arquitectura técnica

**Ya existe ✅ (núcleo del motor)**
`SnowField` (sim GPU ping-pong 512², espejo CPU 64² para consultas, cola de ops,
volumen por operación), `snow_sim.glsl` (10 modos), `SnowBall`, `PinProp`,
`PropsSystem`, `SnowChunk`, controlador de jugador con herramientas, HUD, materiales
y **3 baterías de diagnóstico automáticas** (`--phys-demo`, `--carve-quality`,
`--ball-shape`). Eso es un activo enorme: es la base del motor y de la QA.

**Falta ⬜ (el juego alrededor del motor)**

| Sistema | Responsabilidad |
|---|---|
| `GameManager` | Máquina de estados: boot → menú → lobby → nivel → resultados. Carga de escenas y transiciones. |
| `SettingsSystem` | Config de usuario, aplicación en vivo, presets, persistencia. |
| `SaveSystem` | Ranuras, esquema versionado, migración, autoguardado, Steam Cloud. |
| `LocalizationManager` | Idioma, plurales, formato locale, modo QA. |
| `InputManager` | Remapeo, prompts por dispositivo, mantener/alternar. |
| `AudioManager` | Buses, música adaptativa por progreso, ducking. |
| `ProgressionSystem` | Dinero, desbloqueos, mejoras, estadísticas. |
| `ObjectiveSystem` | Condiciones componibles evaluadas por tick + evaluación final. |
| `LevelDefinition` | Formato de datos de nivel + cargador + herramienta de editor. |
| `NetworkManager` | Host/join, replicación de ops, resync, lobby, sesión. |
| `PhotoMode` | Cámara libre, filtros, poses, guardado. |
| `Achievements` / `Leaderboards` | Steamworks. |
| `Telemetry` (opt-in) | Rendimiento y embudos de juego, anónimo. |

**Principios**
- **Simulación y presentación separadas**: la sim nunca depende del render (permite
  el tick de simulación desacoplado y el netcode por ops).
- **Todo dato de juego en recursos**, no en código: herramientas, niveles,
  objetivos y textos son datos → modding y balance sin tocar scripts.
- **Una sola fuente de verdad para la masa**: cualquier añadido futuro (agua, hielo,
  suciedad) entra por el mismo libro de cuentas.

---

## 13. Guardado, datos y telemetría

- **Guarda cuando quieras** (requisito del género): al completar nivel, al salir y
  cada N minutos en partida.
- **Qué se guarda:** progreso (niveles, estrellas, dinero, mejoras, cosméticos),
  estadísticas, ajustes, y —si el jugador lo quiere— **el estado del nivel a medias**
  (mapa de alturas reducido 128² comprimido ≈ 30–60 KB por nivel, no la textura completa).
- **Esquema versionado** con migración y copia de seguridad antes de sobrescribir;
  si el guardado se corrompe, se recupera el anterior y se avisa.
- **Perfiles múltiples** (habitación compartida: cada uno su progreso).
- **Telemetría opcional** y anónima: fps, ms de simulación, tiempo por nivel, punto
  de abandono, uso de herramientas. Sirve para balancear, no para monetizar.

---

## 14. Rendimiento y compatibilidad

**Objetivo:** 60 fps a 1080p en un equipo del montón (el género exige GTX 960 /
4 GB de RAM) y funcionar en Steam Deck con preset Medio.

- **La simulación GPU es el riesgo.** Plan por capas:
  - Presets de resolución de simulación (256/384/512/768) y de subdivisión de malla.
  - **Simulación a 30 Hz desacoplada del render** (la nieve no necesita 60 Hz).
  - Medición permanente de ms de simulación en el HUD de desarrollo.
  - **Plan B para GPUs débiles**: modo "nieve simplificada" (sim a 256² y
    relajación cada 2 frames) o, en el extremo, campos pequeños por nivel.
- **Presupuesto por frame** (16,6 ms a 60 fps): simulación ≤ 3 ms · render de nieve
  ≤ 4 ms · resto ≤ 9 ms.
- **Compatibilidad:** validar en Intel integrada reciente, GTX 1050/960, Deck y una
  GPU AMD; Vulkan (Forward+) es el objetivo, con preset "bajo" probado explícitamente.
- **Tiempos de carga:** < 10 s por nivel (generación por semilla + carga asíncrona).

---

## 15. QA, CI y baterías automáticas

El proyecto ya tiene una cultura de diagnóstico que hay que convertir en **puertas
de integración continua**:

| Batería | Comprueba | Estado |
|---|---|---|
| `--phys-demo` | 36 comprobaciones: masa, herramientas, acarreo, empuje, lanzamiento, rotura | ✅ |
| `--carve-quality` | Calidad del terreno y FPS con malla densa | ✅ |
| `--ball-shape` | Esferas limpias, densidad, sin surcos falsos | ✅ |
| `--save-roundtrip` | Guardar → cargar → mismo estado y misma masa | ⬜ |
| `--i18n-check` | Ninguna clave sin traducir en ningún idioma | ⬜ |
| `--settings-apply` | Todos los ajustes se aplican en vivo y persisten | ⬜ |
| `--net-smoke` | Dos instancias headless: ops, resync, deriva de masa < 1 % | ⬜ |
| `--perf-gate` | Fps mínimos por preset en escena de estrés | ⬜ |

Además: **pruebas de juego humanas** cada hito (3–5 personas, observando sin guiar),
y una lista de "sensaciones" a validar: el primer minuto debe dar satisfacción; el
sonido debe dar ganas de seguir; el coop debe provocar risas, no discusiones.

---

## 16. Monetización y publicación

- **Premium**, 6–12 € según contenido final. **Sin micropagos, sin pase de batalla.**
- **Demo pública** (1 nivel + sandbox) — imprescindible para el género y para
  Steam Next Fest.
- DLC/actualizaciones: packs de niveles (otra estación, otro pueblo), cosméticos
  gratis como agradecimiento.
- Steam: logros, marcadores, Cloud, Rich Presence ("Limpiando la plaza · 2/4"),
  Remote Play Together (permite "coop local" gratis por streaming).
- Steam Deck: verificación (objetivo).
- Página de tienda con GIFs del *antes/después* y del caos coop: es el marketing.

---

## 17. Roadmap por hitos (con criterios de salida)

> **Antes del contenido va todo el sistema.** El detalle fino (fichas, mecánicas
> numéricas, Playground y 11 fases de sistemas) está en `plan_implementacion.md`
> §2–§5: **~5–6 meses de sistemas** con 1–2 personas, sin tocar contenido. La tabla
> de abajo sitúa esos sistemas en el plan de producto.

| Hito | Duración | Contenido | Criterio de salida |
|---|---|---|---|
| **M0 — Motor** ✅ | hecho | Nieve, herramientas, bolas, ensamblaje, baterías | 36 OK / 0 fallos |
| **M1 — Vertical slice** | 6–8 sem | 1 nivel completo con menús, objetivos, dinero, guardado, ajustes (vídeo/audio/controles), i18n (2 idiomas), mando, modo foto | 60 fps en preset bajo; 20 min divertidos en solitario; 3 testers quieren jugar más |
| **M2 — Coop** | 6–10 sem | Spike de red → coop 2 jugadores online: ops + resync, predicción de acarreo, verbos coop, lobby, nameplates | 30 min con 2 jugadores por internet sin desincronizar el % y **más divertido que en solitario** |
| **M3 — Contenido** | 10–16 sem | 8–12 niveles, taller/mejoras, progresión, logros, sandbox, retos, 13 idiomas, accesibilidad | Campaña terminable en 1,5–3 h; 0 claves sin traducir; accesibilidad completa |
| **M4 — Pulido y lanzamiento** | 6–8 sem | Rendimiento, bugs, playtest, página de tienda, tráiler, demo, locs, Deck | Presupuesto de frame cumplido en 4 configuraciones; demo con retención D1 > 25 % |

**Total: 9–12 meses** con 1–2 personas + arte contratado. El motor (lo más caro) ya
está hecho, que es lo que hace realista este calendario.

---

## 18. Riesgos y mitigaciones

| Riesgo | Impacto | Mitigación |
|---|---|---|
| Netcode sobre campo deformable | **Alto** | Spike de 2 semanas antes de prometer coop; plan B (cliente sólo interpolado); replicación por operaciones + RLE |
| Rendimiento de la sim en GPUs modestas | **Alto** | Presets, sim a 30 Hz, medición permanente, plan B de nieve simplificada |
| El sandbox se come el juego (scope creep) | Medio | Objetivos y niveles primero; el sandbox es un modo, no el producto |
| Coop = "dos haciendo tareas separadas" (aburrido) | **Alto** | Cada nivel tiene **al menos un objeto que necesita dos personas** |
| Contenido (10 niveles + kit de arte) | Medio | Kit modular + variaciones de clima/luz; 1 nivel / 2–3 semanas |
| Determinismo entre GPUs | Medio | Auditoría del shader; tolerancia ±1 téxel; resync |
| i18n tardía (retrabajo de textos) | Medio | Plurales y formato locale desde el día 1; pseudo-localización en M1 |
| Fatiga del jugador por grind de dinero | Bajo | Los niveles se desbloquean por progreso; el dinero compra comodidad, no llaves |

---

## 19. Métricas de éxito

**De juego (playtest):** tiempo hasta la primera satisfacción < 60 s · % de nivel
completado al abandonar (alto = engancha) · "¿jugarías otro nivel?" · duración de
sesión coop · risas por minuto (literal: es un juego de comedia física).

**De producto:** conversión de demo a lista de deseos · retención D1 de la demo ·
reseñas positivas (> 90 % es el estándar del nicho) · horas medianas 2–6 h ·
estabilidad (0 cuelgues por 100 sesiones).

**Técnicas:** ms de simulación por preset · tasa de desincronización por sesión coop ·
tráfico medio por cliente · fps p1 (el 1 % peor de los frames).

---

## 20. Estado de las decisiones

### Cerradas

| Tema | Decisión |
|---|---|
| **Cooperativo** | **2 jugadores exactos**, online por Steam, con *Remote Play Together* para el sofá. |
| **Solo y coop** | **Ambos son primera clase.** El 100 % del progreso es alcanzable en solitario; el coop añade sellos extra que no bloquean nada. Se resuelve con un sistema (`PlayerCountScaler`), no recortando niveles. |
| **Precio y alcance** | **6,99 €**, alcance y duración similares a la referencia, compensando con **rejugabilidad** (2–3 vueltas para el Libro del Invierno) y con la capa social. Demo gratuita. |
| **Plataformas** | **Steam + Steam Deck verificado** y **soporte completo de mando de consola** (Xbox/PlayStation/Nintendo). |
| **Logros** | **Compartidos**: un único conjunto, se desbloquean para los dos a la vez en coop, y **ninguno exige una segunda persona**. |
| **Muñeco de nieve** | **Extra opcional y divertido**, nunca objetivo. |
| **Netcode** | Host autoritativo del marcador + cliente que simula y predice + corrección por parches RLE, con *spike* obligatorio antes de la fase de red (`plan_implementacion.md` §6.5 y §7.8). |
| **Modo de sesión** | Trabajo / **Jaleo** (por defecto con amigos) / Duelo. |
| **Lobbies públicos** | **No** en la v1: por defecto **sólo amigos**. El Jaleo con desconocidos hace más daño que bien; el Duelo también es entre amigos. |
| **Título** | **Snow It Together**, provisional. |
| **Ubicación** | **Sin decidir** y sin impacto en el diseño: ninguna mecánica depende del escenario. |

### Abiertas (se deciden con datos, no antes)

1. **Ayuda al solista** si el 100 % en solitario resulta pesado: quad con pala,
   vecino que colabora, o nada. Lo decide el playtest de la fase 5–6.
2. **Qué más hace el "modo Realista"** además de quitar la limpieza automática de la
   cara (¿fatiga? ¿peso real? ¿sin ayudas de apuntado?).
3. **Escenario definitivo** (cuando se elija): sólo cambia el arte y los niveles, no
   los sistemas.
4. **Contenido del Duelo**: número de arenas y mutadores, según cuánto tire la gente
   en el playtest.
