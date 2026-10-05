# Físicas emergentes de nieve — Snow It Alone

Este documento describe el sistema de físicas de nieve implementado en el
prototipo. La idea rectora es que **no hay misiones guiadas ni botones de
ensamblaje**: hay cuatro sistemas que cooperan y el muñeco de nieve, la muralla
o la escultura aparecen como consecuencia de las mismas reglas.

```
SISTEMA 1  terreno continuo GPU (altura, nieve suelta, cohesión, avalanchas)
     ▲                                        ▲
     │ transferencia de masa (dump / scoop)    │ rodadura y surco
     │                                        │
SISTEMA 2  pala física          ◄──────►  SISTEMA 3  bolas y terrones 3D
(resistencia, carga, vertido,                     (acreción R³, masa e inercia
 palmeo, esculpido)                                dinámicas, reabsorción)
                                                  ▲
                                                  │
                                          SISTEMA 4  ensamblaje universal
                                          (apilado por deformación, clavado)
```

## Sistema 1 — Terreno continuo (`shaders/snow_sim.glsl`, `scripts/snow_field.gd`)

Textura `RGBA32F` 512×512 en ping-pong sobre un campo de 8 × 12 m (32 cm de
nieve virgen), con **conservación estricta de masa**:

| Canal | Significado |
|---|---|
| R | altura total (1.0 = `snow_depth` metros) |
| G | nieve **suelta** movilizable (sólo esta fracción puede fluir) |
| B | **cohesión / humedad** (modula el ángulo de fricción interna) |
| A | scratch de relajación: `+escala` = celda en reposo, `−escala` = en flujo |

**Ángulo de reposo bi-fásico (histéresis):** una celda en reposo necesita
superar el ángulo *estático* (`dinámico + histéresis`, por defecto 32° + 8°)
para arrancar, y una celda ya en movimiento se asienta en el ángulo
*dinámico*. La cohesión eleva ambos: la nieve seca (B≈0) fluye a 32°, la nieve
húmeda y apelmazada (B→1) sostiene 54°.

Modos del compute shader:

| Modo | Función |
|---|---|
| 0 | La hoja recoge la nieve bajo la plancha (`max_cut` > 0 → formón: esculpido) |
| 1 | La hoja deposita la carga frente a ella formando montón |
| 2 | Sellos: huella de bota (hunde y compacta) y limpieza radial (la sal rompe la cohesión) |
| 3 | **DUMP**: inyecta volumen libre con perfil cónico, marcado como nieve suelta y húmeda |
| 4-5 | Relajación granular en dos pasadas (escala de salida + transferencia) |
| 6 | Estadísticas, sondas y **volumen retirado por operación** |
| 7 | **TAMP**: aplana por difusión y asienta plásticamente empujando masa hacia fuera |
| 8 | **HARVEST**: siega cilíndrica a lo largo de un segmento (acreción y esculpido) |
| 9 | Espejo reducido 64×64 para consultas de gameplay en CPU |

**Espejo CPU:** cada frame la GPU escribe un resumen 64×64 (altura media, nieve
suelta media, cohesión media y altura máxima por bloque) que la CPU lee de forma
asíncrona. Con él se resuelven la sustentación del jugador sobre los montones,
la resistencia de la pala, la rodadura de las bolas y el clavado de objetos, sin
leer la textura completa.

API pública relevante: `dump_snow(pos, kg, radio)`, `tamp(pos, radio, fuerza)`,
`request_harvest(owner, desde, hasta, radio, profundidad)`,
`carve_shovel(pos, dir, ancho, largo, corte_máximo)`, `get_height_at(pos)`,
`get_support_snow_height(pos)`, `get_cohesion_at(pos)`, `get_loose_fraction_at(pos)`.

### Render y simulación: un único dato filtrado

La rejilla de simulación tiene texeles de **1,56 × 2,34 cm** (512² sobre 8 × 12 m)
y la malla de nieve un vértice cada **2,5 cm** (`mesh_subdiv_x/z` = 320 × 480).
Muestrear el mapa a pelo con esa diferencia de rejillas producía **aliasing**: los
bordes de lo recogido salían en "dientes" oscuros y con normales invertidas.

Por eso `materials/snow_deform.gdshader` lee el mapa siempre por el mismo filtro
de huella `sample_height()`, cuyo radio (`smooth_uv`) fija `SnowField` a partir de
la subdivisión real de la malla. **Desplazamiento, máscara de color y normales usan
ese mismo valor filtrado**, de modo que geometría e iluminación coinciden y el
borde queda limpio. Ajustes asociados:

- Máscara nieve→pavimento estrecha (`smoothstep(0.010, 0.060, h)`) → borde limpio.
- `SSAO` del entorno suavizado (radio 1,15 · intensidad 0,85): antes oscurecía en
  exceso el fondo de las oquedades.
- Pavimento más claro (pizarra húmeda) para que el contraste con la nieve no
  convierta cualquier irregularidad en una mancha negra.
- El **viewmodel no proyecta sombra** (`GeometryInstance3D.SHADOW_CASTING_SETTING_OFF`):
  las planchas de la pala son muy finas y con sol rasante su sombra se estiraba en
  una "aguja" azul sobre la nieve.

## Sistema 2 — Pala física (`scripts/player_controller.gd`)

- **Resistencia real, pero sin arrastrarse**: hay dos magnitudes separadas a
  propósito.
  - *Lectura física* `F = μ·N + k_corte·ancho·h_nieve + M·a` (`snow_resistance`
    en N): se muestra en el HUD y decide la **traba**.
  - *Arrastre de avance* `push_drag = plow_drag_per_m·h·bite + load_drag_per_kg·kg`
    y velocidad `= base / (1 + push_drag)`: acotado por construcción, de modo que
    la nieve frena pero nunca convierte andar en arrastrarse.

  Valores medidos con `--phys-demo`: pala vacía en nieve virgen ≈ **80 %** de la
  velocidad; pala llena (25 kg) abriendo paso en un montón de 45 cm ≈ **58 %**
  (≈ 2,4 m/s). La pala **sólo se traba** con un montón más alto que la hoja
  (`stuck_height_m`) o una resistencia > `stuck_resistance`, y entonces avanza al
  `stuck_speed_factor` con aviso en el HUD: se sale mirando al frente (corte
  fino), vertiendo o palmeando con `Q`.
- **Ángulo de ataque**: mirando al suelo la hoja muerde toda la capa; llana
  trabaja como formón y levanta láminas finas (esculpido libre).
- **Carga limitada por caudal**: la pala no se llena de un golpe (máx. 34 kg/s,
  25 kg de capacidad).
- **Click derecho mantenido** → la hoja se inclina y **vierte** en chorro
  continuo bajo la hoja, transfiriendo masa al terreno en tiempo real.
- **Click derecho (pulsación corta)** → **lanzamiento parabólico** de terrones.
- **Q** → **palmeo**: aplana, compacta (G→0) y sube la cohesión.

## Sistema 3 — Bolas rodantes (`scripts/snowball.gd`)

- La sustentación se resuelve con un resorte-amortiguador a lo largo de la
  **normal del terreno** (críticamente amortiguado, penetración en reposo
  ≈ 2,4 cm) y la fricción se aplica sobre el **deslizamiento real en el punto
  de contacto**, de modo que el par genera rodadura pura en lugar de frenar la
  bola.
- **Acreción**: cada 12 cm de recorrido la bola siega una franja del ancho de su
  huella y absorbe el volumen exacto que la GPU reporta
  (`R = ∛(R³ + 3ΔV/4π)`), dejando el surco limpio detrás.
  La siega sólo une puntos con **contacto continuo con el manto**: el ancla se
  invalida en cuanto la bola queda claramente en el aire (lanzada, cayendo o
  rebotando) y cualquier salto mayor de `MAX_HARVEST_STEP` (0,45 m) reancla sin
  segar. Sin eso, al aterrizar tras un lanzamiento se arañaba una franja recta
  desde el punto de lanzamiento hasta el de caída: una "línea" antinatural.
- **Masa e inercia dinámicas, con densidad creciente**: `m = 4/3·π·R³·ρ(R)` y
  `ρ(R)` sube de **300 a 470 kg/m³** con el tamaño (la nieve se compacta y expulsa
  aire al rodar). La bola pesa por tanto **más** que un R³ puro: 2 kg con
  r=0,12 · 32 kg con r=0,28 · 73 kg con r=0,36 · 266 kg con r=0,52. La inercia la
  deriva Godot de la masa y la forma, así que se actualiza sola.
- **Resistencia a la rodadura** que crece con el cubo del tamaño: una bola
  pequeña rueda lejos y una gigante se frena casi de inmediato.
- **Empuje por FUERZA, no por aceleración** (`PUSH_FORCE_NEWTONS` = 260 N, con tope
  de 26 m/s²): el jugador empuja con el cuerpo y la misma fuerza mueve mucho una
  bola ligera y apenas una pesada.
- **Terrones** (`scripts/snow_chunk.gd`): todo fragmento que pierde su energía
  se disuelve y **reintegra su volumen** al manto.
- **Rotura por impacto** (`scripts/snow_burst.gd`): si una bola golpea a más de
  `break_speed_threshold` (7 m/s) **se deshace**. El 55 % de su masa vuelve al
  manto justo en el punto del golpe (`dump_snow`) y el resto se reparte en una
  lluvia de fragmentos con velocidades de dispersión, más una nube de nieve
  pulverizada y su sonido. Rodar o caer suave no la rompe. La masa queda así
  cerrada: lo que era bola pasa a montón + terrones que se reabsorben.
  - **Gancho para arte final**: los fragmentos y la nube son **provisionales**
    (terrones esféricos y `CPUParticles3D`). Basta con asignar
    `SnowBurst.fragment_scene` / `SnowBurst.puff_scene` a un `PackedScene` para
    que `_make_fragment()` instancie el modelo real pre-fracturado; el resto del
    sistema (masa, impulsos, reabsorción) no cambia.

## Sistema 4 — Ensamblaje universal (`scripts/snowball.gd`, `scripts/pin_prop.gd`, `scripts/props_system.gd`)

- **Apilado por unión de nieve**: cuando una bola se posa centrada sobre otra y
  ambas están casi quietas, se consolida una **unión física**
  (`Generic6DOFJoint3D` bloqueado) que aporta la estabilidad mecánica del muñeco.
  Un impacto fuerte la rompe. Las bolas son **siempre esferas limpias**: no hay
  geometría de deformación añadida (lo verifica `--ball-shape`).
- **Clavado**: ramas, piedras, zanahorias y carbón llevan `sharpness`. Si la
  punta penetra nieve con suficiente cohesión (o una bola) se fijan con un
  **`PinJoint3D`** real o con congelación cinemática. Se extraen tirando de
  ellas, saltan si la bola rueda rápido y **se caen solas si se palea la nieve
  que las sostiene**.
- **Carga con las manos** — `E` tiene tres comportamientos según cómo se use:
  - **pulsación corta sobre algo** → cogerlo (o extraerlo si está clavado);
  - **pulsación sobre nieve** → **apelmazar** una bola: la masa se siega del manto
    con `request_harvest` y la bola nace **ya en las manos**, en el punto de
    agarre y en modo carga en el mismo frame, sin caer al suelo;
  - **mantener sobre una bola** → **empujarla pegada al suelo**: sigue siendo un
    cuerpo dinámico apoyado en el manto (nunca se levanta) y la fuerza está
    acotada, así que cuanto más pesa más cuesta moverla.
  Click derecho mientras se carga **lanza**. El agarre se adapta al tamaño
  (`_carry_anchor`): una bola de mano a ~0,7 m y una grande a ~1,3 m.
- **Peso real al transportar** (pensado para cooperativo), buscando que sea
  agradable: *tambalearse cuesta CONTROL, no velocidad*.
  - La velocidad al andar cargando es `1/(1 + masa/300)` con **suelo del 75 %**:
    17 kg → 95 %, 124 kg → 75 %. Nunca se convierte en arrastrarse.
  - A partir de **35 kg** la bola se sujeta con las **DOS manos por encima de la
    cabeza** (anclaje al cuerpo, no a la vista: mirar al suelo no la hunde).
  - Con más peso el jugador **se tambalea**: deriva lateral oscilante, menos
    control de aceleración y balanceo de cámara, proporcionales a
    `stagger = (masa − 35)/(150 − 35)`.
  - El **agarre** se agota (`0,05 + 0,22·stagger` por segundo) y, si llega a cero,
    la bola **se le escapa de las manos**: el HUD avisa a partir del 30 %.
  - **Lanzamiento**: la velocidad cae con la masa de forma **suavizada**
    (`v = 9·(1,7/m)^0,30`) y a dos manos hay un extra de fuerza ×1,8 con más arco.
    Nunca supera a la bola ligera: el peso siempre resta, pero una bola grande se
    lanza **con fuerza** (146 kg → 3,6 m/s) en vez de quedarse clavada.
    Medido: **1,7 kg → 7,5 m/s** frente a **146 kg → 3,6 m/s**.
  - Mientras llevas algo, las herramientas se guardan (las manos están ocupadas).

## Controles

| Tecla | Acción |
|---|---|
| W A S D / Shift / Espacio | Moverse, correr, saltar |
| Click izquierdo | Empujar / cortar nieve |
| Click derecho mantenido | Inclinar la pala y verter |
| Click derecho (toque) | Lanzar nieve (o el objeto cargado) |
| **Q** | Palmear / aplanar y compactar |
| **E** (pulsación) | Coger objetos y bolas · apelmazar nieve con las manos |
| **E** (mantener) | Empujar la bola pegada al suelo, sin levantarla |
| 1 2 3 | Pala / Turbina / Salero |
| R / ESC | Reiniciar nivel / liberar ratón |
| **H** | Mostrar u ocultar la ayuda de teclas (empieza oculta) |

## Verificación automática

```
godot --path . -- --phys-demo
```

Ejecuta una secuencia guionizada que comprueba los cuatro sistemas, mide la
**conservación de masa** (manto + bolas frente al inicial), verifica el peso y el
acarreo (**dos manos, tambaleo sin ir lento, empuje con `E` mantenida, lanzamiento
por masa y rotura por impacto**) y guarda capturas `phys_01..12_*.png`. Resultado
esperado: **36 OK / 0 fallos**, con un error de masa inferior al 0,5 %.

Datos medidos en la última ejecución: paleado 2,4 m/s · cargando 124 kg **3,13 m/s
(74 % de la velocidad normal)** con tambaleo 0,77 · empuje con `E`: 0,84 m sin
levantar la bola · lanzamiento 1,7 kg → **7,5 m/s**, 146 kg → **3,6 m/s** · rotura:
11 fragmentos y el manto sube de 0,320 a 0,588 m en el punto del golpe.

### Otras baterías de diagnóstico

| Comando | Qué comprueba |
|---|---|
| `--ball-shape` | Que la bola es **siempre esférica** (al crecer y al apilarse) y que **lanzarla no araña una línea** en el manto: mide malla, escala, AABB renderizado y el perfil de alturas del vuelo. |
| `--carve-quality` | Calidad del terreno al recoger: abre zanja y cráter, vuelca el perfil de alturas y guarda capturas. |
| `--plow-demo` | Demo original de empuje con la pala. |
