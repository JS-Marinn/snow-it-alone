# Plan de implementación — Sistemas y mecánicas

> **Alcance de este documento:** construir los *sistemas* y las *mecánicas* del
> juego. **No hay contenido**: ni niveles, ni escenario, ni arte final. Todo se
> valida en un **Playground** temporal (§4).
>
> Documento hermano: `plan_juego.md` (diseño y producto). Cuando algo cambie aquí,
> se anota allí.
>
> Marcas: ✅ ya existe en el prototipo · ⬜ por hacer · 🔧 extensión de algo existente.

---

## 0. Reglas de trabajo y "hecho"

### 0.1 Los tres invariantes del proyecto

1. **Solo y coop son igual de buenos.** Ningún sistema se diseña "para coop y ya se
   verá en solo" ni al revés. **Cada ficha declara su comportamiento con N=1 y con
   N=2**, y ambos casos entran en las pruebas. El cooperativo no es un modo: es una
   variable del sistema (`player_count`), y el juego se dimensiona con **reglas de
   sesión** (§2.G.25), no recortando niveles.
2. **La masa se conserva.** Cualquier mecánica nueva (compactar, derretir, volar,
   empujar a un jugador) tiene que cuadrar en el libro de cuentas del manto. Test
   obligatorio en cada fase.
3. **Nada de contenido en esta fase.** Si algo necesita un nivel bonito para
   probarse, está mal planteado: se prueba en el Playground.

### 0.2 Definition of Done de un sistema

- [ ] Ficha completada en este documento (API, datos, parámetros exportados).
- [ ] Implementado **sin literales de texto** (todo clave de traducción desde el día 1).
- [ ] **Cero números mágicos**: todo parámetro `@export` o recurso de datos.
- [ ] Declarado y probado con **N=1 y N=2**.
- [ ] Una prueba automática propia en el Playground o en una batería (§6).
- [ ] Sin regresión: las baterías existentes (`--phys-demo`, `--carve-quality`,
      `--ball-shape`) siguen en verde.
- [ ] Presupuesto de frame respetado (≤ 3 ms de simulación, ver `plan_juego.md`).

### 0.3 Convenciones

- Una carpeta por familia (`scripts/player/`, `scripts/tools/`, `scripts/balls/`,
  `scripts/session/`, `scripts/progression/`, `scripts/ui/`, `scripts/net/`,
  `scripts/playground/`).
- **Comunicación por señales**, no por referencias cruzadas: el HUD no conoce al
  motor de movimiento; escucha.
- Un sistema nunca escribe en otro: pide (API) o avisa (señal).

---

## 1. Capas y mapa de sistemas

```
Capa 6  PLATAFORMA      Steam · guardado · red · telemetría
Capa 5  PRESENTACIÓN    HUD · menús · ajustes · i18n · audio · VFX · foto
Capa 4  PROGRESO        objetivos · sellos · economía · logros (compartidos)
Capa 3  SESIÓN          player_count · modo (Trabajo/Jaleo/Duelo) · escalado
Capa 2  JUGADOR         motor de movimiento · estados · herramientas · interacción
Capa 1  MUNDO FÍSICO    bolas · objetos agarrables · contenedores · vehículos · dummies
Capa 0  SIMULACIÓN ✅   manto de nieve granular con masa conservada
```

Toda dependencia va **hacia abajo**. La capa 0 existe y funciona; el trabajo está
en las capas 1–6.

---

## 2. Fichas de sistemas

### A. Núcleo de simulación (capa 0) — extensiones 🔧

| # | Sistema | Responsabilidad | API clave | Estado |
|---|---|---|---|---|
| 1 | `SnowField` | Manto granular, ops y masa | `carve/dump/tamp/harvest` ✅ | ✅ |
| 2 | `SnowSurfaceQuery` | **Tipo de superficie y fricción por posición** | `surface_at(pos) → {friction, depth, compact, slush}` | 🔧 |
| 3 | `SnowCompaction` | **Compactar** nieve sin retirarla (nueva op de GPU) | `compact(pos, radius, amount)` | ⬜ |
| 4 | `MassZone` | Volúmenes que aceptan/expulsan masa y la contabilizan | `accepts(pos)`, `mass_in()`, `signal mass_changed` | ⬜ |
| 5 | `MassLedger` | Libro de cuentas total (manto + bolas + contenedores + fragmentos) | `total_mass()`, `report()` | 🔧 |

**2. `SnowSurfaceQuery`** es la pieza que hace funcionar el movimiento, las
herramientas y el bunny hop. Combina canales que ya existen (altura, nieve suelta,
cohesión) en una lectura de *tipo de superficie*:

| Tipo | Condición | Fricción | Efecto |
|---|---|---|---|
| Despejado / compactado | `h < 0.02` o `compact > 0.7` | muy baja | corres y mantienes impulso |
| Nieve polvo | `cohesion < 0.35` y `compact < 0.4` | alta | te hundes, se corta la velocidad |
| Nieve húmeda / pesada | `cohesion > 0.7` | media-alta | pesa, se pega |
| Slush / hielo | `slush > 0.6` | casi nula | resbalas, no frenas |

**3. `SnowCompaction`** es una operación nueva del shader (modo 10) que **sube el
canal de compactación sin tocar la altura**: transferencia de masa cero, sólo cambio
de estado. Es lo que permite que el bunny hop trace caminos y que el palmeo tenga
sentido económico (compactar es *más barato* que retirar... pero no despeja el 100 %).

**5. `MassLedger`** convierte el invariante #2 en algo medible en tiempo real:
`manto + bolas + contenedores + fragmentos + agua = constante`. El HUD de desarrollo
lo muestra; las baterías lo verifican.

### B. Jugador (capa 2)

| # | Sistema | Responsabilidad | API clave | N=1 / N=2 |
|---|---|---|---|---|
| 6 | `PlayerMotor` | Movimiento con inercia: fricción por superficie, air control, bunny hop, deslizamiento, agacharse | `set_input()`, `speed`, `is_sliding` | idéntico |
| 7 | `PlayerState` | Máquina de estados: normal · cegado por nieve · desestabilizado · derribado · sepultado · montando | `apply_hit(tier, zone)`, `state`, señales | idéntico |
| 8 | `PlayerAvatar` | Cuerpo visible para el compañero + animación procedural | `pose_from(state, velocity)` | sólo en N=2 |
| 9 | `PlayerInteraction` | `E` (coger/apelmazar/empujar), patada, arrastrar, **agarrar al compañero** | `try_interact()`, `grab_partner()` | en N=1 el "compañero" no existe: se ignora |
| 10 | `PlayerCamera` | Cabeceo, tambaleo, roll, FOV dinámico, sacudida y **overlay de nieve en la cara** | `add_shake()`, `set_face_snow(0..1)` | idéntico |
| 11 | `PlayerAudio` | Pasos por superficie, esfuerzo, impacto, gritos | eventos | idéntico |

**7. `PlayerState`** es el sistema que recibe los impactos (§3.2) y **el único que
puede bloquear acciones**. Reglas duras:

- Un estado **nunca** quita progreso (invariante de diseño): sólo tiempo.
- **Inmunidad de 1,5 s** al salir de cualquier estado → no existe el *stun-lock*.
- En **modo Trabajo** los estados por impacto de bola **no se aplican** (inmunidad).
- Al **derribarse** se suelta lo que se llevaba en las manos (y eso es divertido y
  físicamente coherente).

### C. Herramientas (capa 2) — sistema de datos

| # | Sistema | Responsabilidad |
|---|---|---|
| 12 | `ToolSystem` | Marco común: ranuras, cambio, viewmodel, animaciones, estadísticas, mejoras 1–3 |
| 13 | `ToolDefinition` | **Recurso** que describe una herramienta (verbo, parámetros, coste, mejoras) |
| 14 | Verbos | `Carve/Push` (pala, empujadora) ✅ · `Blow` (turbina) ✅ · `Salt` (salero) ✅ · `Pick` (pico) ⬜ · `Rake` (rastrillo) ⬜ · `Melt` (manguera) ⬜ · `Pack` (manos) ✅ · `Tamp` ✅ · `Throw` ✅ |

Una herramienta nueva **no toca código**: es un `.tres` + un verbo ya existente.
Eso es lo que permite añadir las 8 sin inflar el proyecto.

### D. Bolas y proyectiles (capa 1)

| # | Sistema | Responsabilidad | Estado |
|---|---|---|---|
| 15 | `SnowBall` | Bola física: acreción, masa, densidad, apilado, rotura | ✅ |
| 16 | `BallTier` | **Clasificación por tamaño** (pequeña/mediana/grande) y umbrales | ⬜ |
| 17 | `BallBallistics` | Vuelo, predicción de parábola para apuntar, viento (opcional) | ⬜ |
| 18 | `ImpactResolver` | **Decide el efecto**: tamaño × zona del cuerpo × velocidad → estado | ⬜ |
| 19 | `FaceSnow` | Capa de nieve en la cara: overlay, auto-limpieza, limpieza manual | ⬜ |
| 20 | `BallHandoff` | Recibir/pasar bolas entre jugadores (pulsación de `E` cerca) | ⬜ |
| 21 | `TrainingDummy` | **Muñeco de pruebas** que recibe los mismos impactos que un jugador | ⬜ |

**21. `TrainingDummy` es clave para el invariante #1**: implementa la misma interfaz
`ImpactReceiver` que el jugador, así que **todo el sistema de impactos se puede
probar y disfrutar en solitario** sin depender de una segunda persona. Es también lo
que permite que los logros de "aciertos" sean obtenibles solo.

### E. Objetos y cooperación física (capa 1)

| # | Sistema | Responsabilidad |
|---|---|---|
| 22 | `Grabbable` | Interfaz común: coger, llevar, soltar, lanzar, dos manos |
| 23 | `TwoPersonCarry` | **Agarrar entre dos**: reparte peso, mitiga tambaleo y gasto de agarre, sincroniza poses |
| 24 | `Container` | Carretilla, cubo, caja del camión: llenar, vaciar, pesar (masa real) |
| 25 | `Vehicle` | Quad con pala y trineo: conducir, pasajero, pala que siega, volcar |
| 26 | `Pushable` | Empujar con el cuerpo o entre dos (fuerza que suma) |

### F. Gamberrismo y estados sociales (capa 3)

| # | Sistema | Responsabilidad |
|---|---|---|
| 27 | `SessionMode` | **Trabajo / Jaleo / Duelo**: gobierna si las bolas afectan a jugadores |
| 28 | `PrankStats` | Contadores por jugador: bolas lanzadas/recibidas, enterrados, pilas destruidas, kg re-esparcidos |
| 29 | `Chronicle` | Resumen final con premios absurdos (se ensambla de `PrankStats`) |
| 30 | `DuelMode` | Marcador, rondas, mutadores de arena |

### G. Sesión, progreso y logros (capas 3–4)

| # | Sistema | Responsabilidad | Nota |
|---|---|---|---|
| 31 | `SessionRules` | Reglas de la partida: `player_count`, modo, dificultad/asistencia | —— |
| 32 | `PlayerCountScaler` | **Hace que N=1 y N=2 se sientan igual de bien** (§3.4) | el sistema más delicado |
| 33 | `ObjectiveSystem` | Condiciones componibles evaluadas por tick + sellos de nivel | —— |
| 34 | `ProgressionSystem` | Dinero, estrellas, desbloqueos, mejoras | —— |
| 35 | `AchievementSystem` | **Logros COMPARTIDOS** de la partida (§2.G.35) | —— |
| 36 | `SaveSystem` | Perfiles, esquema versionado, guardado de nivel a medias | —— |

**35. `AchievementSystem` — logros compartidos.** Dos reglas que se verifican
automáticamente:

1. **Se desbloquean para toda la partida**: si se consigue en coop, lo reciben
   **los dos jugadores** (mismo logro, misma vez, sin reparto). El host valida y
   emite; el cliente lo aplica. Nada de "yo sí y tú no".
2. **Todos son obtenibles en solitario.** Un logro nunca puede exigir una segunda
   persona (`--ach-check` lo comprueba: cada logro declara `solo_attainable = true`
   y las condiciones se evalúan en un Playground de un jugador, usando
   `TrainingDummy`/dianas cuando el logro hable de impactos).

El progreso de los contadores también es **compartido**: suman lo de los dos.

### H. Presentación y plataforma (capas 5–6)

| # | Sistema | Responsabilidad |
|---|---|---|
| 37 | `UIManager` | Flujo de pantallas y foco (mando y ratón) |
| 38 | `HUD` | % despejado, masa, herramienta, carga, objetivos, avisos de estado (cegado/derribado) |
| 39 | `SettingsSystem` | Vídeo · audio · controles · juego · accesibilidad · red · datos (aplicación en vivo) |
| 40 | `InputManager` | Remapeo, prompts por dispositivo, *mantener/alternar*, auto-bhop |
| 41 | `LocalizationManager` | Claves, plurales por idioma, formato locale, modo QA |
| 42 | `AudioManager` | Buses, capas de nieve por superficie/herramienta, música por progreso |
| 43 | `VFXManager` | Nieve levantada, nube de rotura ✅, impactos, huellas |
| 44 | `PhotoMode` | Cámara libre, filtros, poses |
| 45 | `NetworkManager` | Host/join, replicación de ops, resync RLE, predicción, lobby |
| 46 | `PerfGuard` | Presets de simulación, sim a 30 Hz, presupuesto de frame, telemetría |

---

## 3. Mecánicas: especificaciones numéricas

### 3.1 Movimiento y bunny hop ✅ **Implementado** (en `player_controller.gd`)

**El modelo es el de Quake, no una aproximación propia.** Referencias: el
`PM_Accelerate`/`PM_Friction` de *Quake III* (`bg_pmove.c`) y el análisis de
[QW physics air](https://www.quakeworld.nu/wiki/QW_physics_air). Tres reglas lo
definen:

1. **En el suelo la fricción se aplica SIEMPRE, también andando**, y después se
   acelera hacia la velocidad deseada. Por eso el andar es contundente y está
   acotado: no hay deslizamiento.
2. **En el aire no hay fricción**, y la velocidad deseada se **recorta a un valor
   pequeño** (`air_wish_speed`). La aceleración se limita a `wishspeed − v·wishdir`,
   así que la única forma de ganar velocidad es **apuntar la dirección de empuje
   perpendicular a la velocidad** y dejar que la aceleración la rote. Eso es el
   *air strafe*.
3. **El salto sólo aporta velocidad vertical.** Su premio es **saltarse la fricción
   del frame de aterrizaje**: por eso el chequeo del salto va **antes** de la
   fricción, igual que en `PM_WalkMove`. Un jugador que sólo mantiene adelante y
   salta **no gana nada**.

| Parámetro | Valor implementado | Medido con `--movement-lab` |
|---|---|---|
| Andar / correr | 4,2 / 6,8 m/s | 3,57 / 6,12 m/s sobre polvo (×0,85) |
| `ground_accelerate` / `ground_friction` | 12 / 5 | el andar alcanza el objetivo exacto |
| `ground_stop_speed` | 1,5 m/s | —— |
| `air_accelerate` / `air_wish_speed` | 12 / 1,0 m/s | —— |
| Tope del bhop | **2,0 × carrera = 13,6 m/s** | la cadena llega al tope en 8 saltos |
| **Salto recto** (sólo adelante) | —— | run-up 5,99 → **5,78 m/s: no gana nada** |
| **Air strafe ideal** | —— | run-up 6,66 → **13,60 m/s (+104 %)** |
| Soltar el mando desde carrera | —— | **para en 0,37 s** |
| Superficie por cohesión | polvo ≥0,45 compactado | polvo x0,85/fricción x1,2 · compactado x1,05/fricción x0,8 |
| Compactación al aterrizar | `tamp` a 0,38 m, fuerza 0,18 | cada aterrizaje apelmaza y deja el suelo más rápido |
| Deslizamiento en pendiente | ⬜ pendiente del Playground | —— |
| Auto-bhop (accesibilidad) | `auto_bhop`, apagado por defecto | saltarse el ritmo; no da velocidad por sí solo |

**Prueba:** `--movement-lab` (10 comprobaciones) mide el andar/correr por superficie,
que soltar frena en menos de medio segundo, que **saltar en línea recta no gana
velocidad**, que **el air strafe sí** (con un bot que apunta el empuje perpendicular
a la velocidad, o sea el caso ideal), el tope y el recuento de cadena.

**Limitación conocida:** el nivel actual es corto (12 m de campo), así que las
cadenas largas salen del campo simulado. El Playground necesitará una pista larga
para medir la curva completa y las pendientes.

### 3.2 Impacto de bolas sobre jugadores ✅ **Implementado**

**Clasificación por tamaño** (radio medido, con la masa que sale de la densidad
variable). En código: `SnowBall.tier_for_radius()`.

| Categoría | Radio | Masa aprox. | Cómo se lanza |
|---|---|---|---|
| **Pequeña** | `r < 0,18 m` | 1–8 kg | una mano, rápido |
| **Mediana** | `0,18 ≤ r < 0,34 m` | 8–60 kg | una o dos manos, lento |
| **Grande** | `r ≥ 0,34 m` | > 60 kg | **dos manos**, sólo "heave" |

**Efectos** (requieren que la bola venga lanzada, no rodando):

| Categoría | Impacto en el **cuerpo** | Impacto en la **cara** | Velocidad mínima | Medido |
|---|---|---|---|---|
| **Pequeña** | Nada (sólo sonido y salpicadura) | **`NADIEVE`**: cara llena de nieve | 5,0 m/s | ✅ 3,3 s de nieve, sin desestabilizar |
| **Mediana** | **`DESESTABILIZADO` 1,0 s** | `DESESTABILIZADO` + **`NADIEVE`** | 3,5 m/s | ✅ estado 1, nieve 3,3 s |
| **Grande** | **`DERRIBADO` 2,0 s** | `DERRIBADO` + **`NADIEVE`** | 2,5 m/s | ✅ estado 2 y suelta la carga |

**`NADIEVE` (nieve en la cara)**:
- Duración **automática 3,5 s** y se quita sola.
- **Limpieza manual**: mantener la acción de interacción **[E]** la quita en
  **0,6 s**. Medido: 3,28 s de nieve → 0 en 0,9 s de limpieza.
- Efecto visual: overlay de nieve en pantalla, generado por código (una mancha
  blanca procedural, sin assets). **No inmoviliza**: puedes andar y usar
  herramientas; sólo ves mal.
- Ajuste `snow_face_auto_clear`: **Normal = sí** (se quita sola) · **Realista = no**
  (sólo manual). Es el "(esto en modo normal)" que pediste, convertido en ajuste.

**`DESESTABILIZADO` (1,0 s)**: se pierde el control fino — no se puede usar
herramienta, el movimiento conserva la inercia con vaivén lateral y la cámara se
balancea y tiembla.

**`DERRIBADO` (2,0 s)**: no se puede actuar; **se suelta lo que se llevaba** ✅
medido. La cámara cae hacia la nieve y se levanta con una curva, no de golpe.

**Reglas de convivencia (anti-frustración) 🔒 blindadas:**
- Ningún golpe entra **mientras dura un estado** ni durante los **1,5 s** de
  inmunidad al salir. Medido: tres bolas seguidas → `hits_taken` se queda en 1.
- `hit_reactions_enabled = false` es el "Modo Trabajo" (las bolas atraviesan).
  Por defecto **activado**, que es el Jaleo.
- Detección de **cara** analítica: dos esferas por persona (`impact_spheres()`,
  cabeza y torso) y la bola decide por altura. Sin *hitbox* extra.
- En **solitario**: hay un `TrainingDummy` en el nivel al lado del camino ✅ y
  recibe exactamente los mismos golpes que un jugador (probado).

**Dos caminos de detección, por una razón medida:** un jugador tiene cuerpo de
colisión y **para la bola antes** de que entre en las esferas analíticas, así que
su golpe se resuelve por el contacto real; el muñeco no tiene cuerpo, así que su
golpe lo resuelve un barrido del segmento. Mezclar los dos caminos contaría el
golpe dos veces, así que cada objetivo usa el suyo. Como el contacto se notifica
**después** de que el solver ya haya frenado la bola (medido: una bola de 7 m/s
llegaba con 4,81 m/s), la velocidad de llegada es la **máxima de los últimos 4
frames**.

**Prueba:** `--impact-lab` (18 comprobaciones): clasificación de los 3 tamaños,
cara/cuerpo por tamaño, duración y fin de cada estado, inmunidad, bola lenta que
no hace nada, limpieza manual y el muñeco de entrenamiento.

**Pendiente de este apartado:** el `--impact-matrix` completo (3 tamaños × 3 zonas ×
3 velocidades) cuando exista el `PlayerState` compartido con el modo de sesión, y el
desenfoque/audio amortiguado de `NADIEVE` (hoy sólo es el overlay).

### 3.3 Cooperación física ⬜

| Mecánica | Regla | N=1 / N=2 |
|---|---|---|
| **Levantar entre dos** | Si dos jugadores sostienen el mismo objeto: tambaleo × 0,4, gasto de agarre × 0,5, velocidad de carga × 1,25 | en N=1 el comportamiento actual ✅ |
| **Empujar entre dos** | Las fuerzas se suman, con el tope por objeto | en N=1 fuerza simple ✅ |
| **Pasar una bola** | Pulsación de `E` cerca de una bola en vuelo o rodando: se acopla a las manos | N=1: recoges del suelo ✅ |
| **Impulsar al compañero** | Subirse a un montón o a una bola y que el otro empuje | N=1: te subes solo |
| **Rescate** | Desenterrar al compañero sepultado (mash de acción) | N=1: te liberas tú |
| **Contenedores** | La masa dentro cuenta en el libro de cuentas; al volcar, sale de verdad | idéntico |

### 3.4 `PlayerCountScaler` — el sistema que iguala solo y coop ⬜

**Problema:** si dimensiono para 2, en solitario es un castigo; si dimensiono para 1,
en coop se acaba en tres minutos. **Solución: escalar los requisitos, nunca la
física.** La masa del mundo, la resistencia de la nieve y el peso de los objetos son
idénticos con 1 o 2 jugadores (es lo que hace que la física sea creíble y comparable).

| Qué escala | N=1 | N=2 |
|---|---|---|
| Requisito de cobertura del objetivo | × 1,0 | × 1,0 en zona común; las **zonas opcionales** se activan |
| Tiempo objetivo de los sellos | × 1,0 | × 1,55 |
| Objetivos opcionales disponibles | subconjunto | todos |
| Ayudas de solista | quad con pala / vecino (a decidir con playtest) | —— |
| Logros | **los mismos** (compartidos, todos obtenibles) | **los mismos** |

**Regla de oro:** con 2 jugadores se hace **más superficie en el mismo tiempo**, no
la misma superficie con el doble de prisa. Y en solitario **nunca** se pide lo que
requiere dos manos.

**Prueba:** `--coop-rules` evalúa el mismo objetivo con N=1 y N=2 simulados y
comprueba que la relación trabajo/requisito se mantiene dentro del ±15 %.

### 3.5 Estados y acciones: matriz de bloqueo

| Acción | Normal | Cegado (nieve) | Desestabilizado | Derribado | Sepultado |
|---|---|---|---|---|---|
| Andar / correr | ✅ | ✅ (peor visión) | parcial | ❌ | ❌ |
| Usar herramienta | ✅ | ✅ (peor puntería) | ❌ | ❌ | ❌ |
| Coger / llevar | ✅ | ✅ | ❌ | ❌ (suelta) | ❌ |
| Limpiarse la cara | —— | ✅ (manual 0,6 s) | ❌ | ❌ | ❌ |
| Bunny hop | ✅ | ✅ | ❌ | ❌ | ❌ |
| Liberarse | —— | —— | —— | ✅ (se levanta solo) | ✅ (mash) |

---

## 4. Playground — banco de pruebas temporal

Una sola escena neutral, `scenes/playground.tscn`, **sin escenario ni arte final**.
Es donde se prueba *todo* hasta que exista contenido.

**Contenido del Playground (mecánico, no artístico):**
- Explanada plana de 40×40 m con nieve a distintas profundidades por zonas
  (0 / 0,1 / 0,32 / 0,6 m) para probar fricción y hundimiento.
- **Rampa suave (20°)** y **rampa fuerte (35°)** para deslizamiento y aludes.
- **Pared y esquina** para rebotes de bolas (autoimpacto) y empujones.
- **Plataforma a 4 m** (tejado simulado) para probar caídas y avalanchas.
- **Foso / agua** para la salida legítima de masa.
- **Zona de destino de masa** (`MassZone`) y un contenedor pesado (`Container`).
- **Galería de dianas** + **2 `TrainingDummy`** con las mismas reacciones que un jugador.
- **Estantería con las 8 herramientas** y un **generador de bolas** con presets
  (pequeña / mediana / grande) y velocidad ajustable.
- **Quad con pala** y trineo.
- **Consola de depuración** con comandos:

```
pg.spawn ball small|medium|large [speed]
pg.hit dummy|self face|body
pg.state                 # estados activos, inmunidad, duraciones
pg.surface               # tipo de superficie y fricción bajo el jugador
pg.mass                  # libro de cuentas completo
pg.rules players=1|2     # fuerza el escalado de sesión (¡sin segundo jugador!)
pg.rules mode=work|chaos|duel
pg.timescale 0.25        # cámara lenta para ver impactos
pg.reload                # reinicia el manto y la masa
pg.log on|off            # telemetría a archivo
```

**`--local-duo` (modo de depuración):** dos jugadores en la misma máquina
(teclado + mando, o dos ventanas). Sirve para probar la cooperación física y los
estados sin red y sin esperar al hito de multijugador. **Reduce el riesgo del
coop a la mitad.**

---

## 5. Fases de implementación

Cada fase termina con sus pruebas en verde y **no empieza la siguiente sin ellas**.

| Fase | Duración | Contenido | Criterio de salida |
|---|---|---|---|
| **0 · Andamiaje** | 1–2 sem | Autoloads, `UIManager` mínimo, `SettingsSystem`/`SaveSystem`/`LocalizationManager` básicos, escena Playground, consola, `MassLedger` | El Playground carga, un jugador se mueve, el libro de cuentas cuadra, las 3 baterías antiguas siguen verdes |
| **1 · Movimiento** | 1–2 sem | `PlayerMotor` con inercia y bunny hop, `PlayerState`, `PlayerAvatar`, `PlayerCamera` | `--movement-lab`: curva de bhop con tope, 4 fricciones distintas, deslizamiento |
| **2 · Superficie** | 1 sem | `SnowSurfaceQuery`, `SnowCompaction` (op GPU 10), huellas | Compactar no cambia la masa (±0,05 %); el bhop funciona sólo en compactado |
| **3 · Herramientas** | 2 sem | `ToolSystem`, `ToolDefinition`, verbos migrados + pico, rastrillo, manguera; mejoras 1–3 | Cada herramienta mide kg/s y masa conservada en el Playground |
| **4 · Bolas e impactos** | 2 sem | `BallTier`, `BallBallistics`, `ImpactResolver`, `FaceSnow`, `TrainingDummy`, rebotes | `--impact-matrix` completa (3×3×3) + inmunidad + soltado + modo Trabajo |
| **5 · Cooperación física** | 2 sem | `Grabbable`, `TwoPersonCarry`, `Container`, `Vehicle`, `BallHandoff`, rescate | `--local-duo`: levantar entre dos, pasar bolas, volcar contenedor con masa cuadrada |
| **6 · Reglas de sesión** | 1 sem | `SessionRules`, `PlayerCountScaler`, `SessionMode`, `PrankStats`, `DuelMode` | `--coop-rules`: N=1 vs N=2 dentro del ±15 % |
| **7 · Progreso y logros** | 2 sem | `ObjectiveSystem`, `ProgressionSystem`, `AchievementSystem` compartido, guardado | `--save-roundtrip`, `--ach-check` (todos obtenibles en solitario) |
| **8 · Presentación** | 3 sem | HUD, pausa, resultados + crónica, menús, ajustes completos, remapeo, i18n + pseudo-loc, audio, modo foto | `--settings-apply`, `--i18n-check`, navegación de menús **sólo con mando** |
| **9 · Red** | 3–4 sem | Spike → `NetworkManager`: ops, resync RLE, predicción, lobby, Remote Play | `--net-smoke`: deriva < 0,5 %/nivel, < 30 KB/s, sesión de 30 min |
| **10 · Rendimiento y CI** | 1–2 sem | Presets de simulación, sim a 30 Hz, presupuesto de frame, todas las baterías como puertas | `--perf-gate` en 4 configuraciones; checklist de Deck |

**Total: ~20–26 semanas (5–6 meses)** de sistemas, sin contenido. Con el motor ya
hecho, es el camino más corto a un juego real.

---

## 6. Baterías de prueba (y CI)

Se suman a las tres que ya existen ✅. Todas corren **headless** y devuelven un
veredicto `N OK / M fallos` con salida de diagnóstico.

| Batería | Qué comprueba | Fase |
|---|---|---|
| `--phys-demo` ✅ | 36 comprobaciones del núcleo | —— |
| `--carve-quality` ✅ | Calidad del terreno y FPS | —— |
| `--ball-shape` ✅ | Esferas, densidad, surcos | —— |
| `--playground-smoke` | Que el Playground carga, el libro de cuentas cuadra y los sistemas responden | 0 |
| `--movement-lab` | Bhop con tope, 4 fricciones, deslizamiento, compactación | 1–2 |
| `--mass-invariant` | Masa total constante en 20 operaciones mezcladas (incluida compactar) | 2–3 |
| `--impact-matrix` | 3 tamaños × 3 zonas × 3 velocidades, inmunidad, soltado, modo Trabajo | 4 |
| `--coop-rules` | N=1 vs N=2: trabajo/requisito dentro del ±15 % | 6 |
| `--save-roundtrip` | Guardar → cargar → mismo estado, misma masa, esquema migrado | 7 |
| `--ach-check` | Todo logro obtenible en solitario; desbloqueo compartido en coop | 7 |
| `--i18n-check` | Ninguna clave sin traducir en ningún idioma | 8 |
| `--settings-apply` | Todos los ajustes se aplican en vivo y persisten | 8 |
| `--net-smoke` | Dos instancias: deriva de masa, tráfico, reconexión | 9 |
| `--perf-gate` | Presupuesto de frame por preset y configuración | 10 |

**Puerta de integración:** ningún cambio entra si alguna batería baja de verde.

---

## 7. Decisiones tomadas en este plan

1. **Coop de 2 exactos, y ambos modos son primera clase.** El número de jugadores es
   una *variable de sistema* (`SessionRules.player_count`), no una bifurcación del
   diseño. El escalado lo resuelve `PlayerCountScaler` escalando **requisitos**, no
   física.
2. **Logros compartidos.** Un único conjunto; en coop lo reciben los dos a la vez, y
   **ninguno exige una segunda persona** (verificado por `--ach-check`).
3. **La ubicación está sin decidir y no se tiene en cuenta.** El Playground es
   deliberadamente abstracto; el escenario no condiciona ninguna mecánica
   (nada de "nieve alpina" ni "pueblo": sólo *nieve*, *superficies* y *objetos*).
4. **Modo de sesión como sistema**: Trabajo / Jaleo / Duelo, con la matriz de
   impactos de §3.2.
5. **Anti-`stun-lock` por diseño**: inmunidad de 1,5 s tras cada estado.
6. **`TrainingDummy` y `--local-duo`** como herramientas de prueba: permiten validar
   el coop y los impactos **sin red y sin segunda persona**.
7. **La compactación es una op de GPU de masa cero**, y es lo que da sentido
   económico al palmeo y al bunny hop.
8. **Netcode:** host autoritativo del marcador, cliente que simula y predice sus
   ops, corrección por parches RLE, spike obligatorio antes de la fase 9.

## 8. Riesgos de este plan

| Riesgo | Mitigación |
|---|---|
| El motor de estados del jugador pelea con el `CharacterBody3D` (derribos, empujones) | Derribo **cinemático con animación** + empujes físicos; nunca convertir al jugador en cuerpo rígido |
| Sim a 30 Hz y la siega/compactación pierden masa | `--mass-invariant` en cada fase; tolerancia < 0,05 % |
| El bhop se convierte en exploit | Tope duro + pendiente de ganancia decreciente + pruebas de curva |
| El `PlayerCountScaler` se vuelve un nudo de casos especiales | Sólo 4 palancas (cobertura, tiempo, opcionales, ayudas) y una prueba de ratio |
| El coop se prueba tarde y mal | `--local-duo` desde la fase 5 y `TrainingDummy` desde la 4 |
| Determinismo del shader para la red | Auditoría en la fase 9 + plan B (cliente sólo interpola) |

## 9. Lo que NO se hace ahora

- Nada de niveles, escenarios, pueblo, historia ni arte final.
- Nada de tienda con economía balanceada (sólo el sistema, con datos de prueba).
- Nada de logros concretos (sólo el sistema y su regla de compartición).
- Nada de localizaciones reales (sólo las claves y la pseudo-localización).
- Nada de Steamworks real (sólo la interfaz y un *stub* que se pueda sustituir).
