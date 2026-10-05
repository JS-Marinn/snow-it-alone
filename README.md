# Snow It Alone

Simulador táctil, atmosférico y *cozy* en primera persona desarrollado en **Godot 4.7 (Forward+)**, centrado en la limpieza, manipulación y **física granular** de la nieve en una pintoresca cabaña nórdica de montaña.

El proyecto nació inspirado en la satisfacción táctil y zen de juegos como *PowerWash Simulator*, combinada con la identidad visual vibrante, escultural y de materiales físicos curiosos al estilo *Donkey Kong Bananza* y los estándares de producción de Nintendo.

---

## 1. Pilares fundamentales del juego

### Física granular fiel en tiempo real (en GPU)
La nieve no es un simple efecto cosmético ni un plano estático: es un medio físico con **volumen real**, **conservación estricta de masa**, ángulo de reposo, cohesión y resistencia. Cada centímetro cúbico de nieve empujado o recogido existe dentro de la economía física del mundo.

### Atmósfera *cozy* y estilizada
Una cabaña de troncos cálida con chimenea humeante, rodeada de un bosque denso de pinos nevados, postes de madera y faroles rústicos de latón iluminados al atardecer. La experiencia combina el relax de despejar un patio invernal con la riqueza táctil de los materiales.

### Dirección de arte: *Pure Baked PBR*
Siguiendo directivas estrictas de arte técnico: cero shaders de distorsión procedimental dependientes de cámara en runtime. Superficies modeladas y texturizadas con coordenadas de objeto 3D sin costuras, horneadas a mapas PBR físicos estándar (Albedo, Normal, Roughness, Metallic) con biseles suaves y respuesta lumínica de pieza de museo.

> **Estado de esta directiva:** cumplida en el terreno y la escena (el desplazamiento de la nieve no depende de la cámara), **pendiente** en los objetos nuevos de juego (bolas, ramas, piedras, carbón), que hoy usan materiales planos creados en runtime.

---

## 2. Arquitectura técnica y tecnologías

El proyecto opera sobre una arquitectura de muy alto rendimiento orientada a exprimir el hardware sin micro-tirones:

```
                          ┌────────────────────────────────────────────────────────┐
                          │                    GPU ENGINE (Vulkan)                 │
                          │  - Forward+ Renderer                                   │
                          │  - Compute Shader: shaders/snow_sim.glsl               │
                          │  - Ping-Pong RGBA32F Storage Textures (Texture2DRD)    │
                          │  - Espejo reducido 64x64 (resumen para gameplay)       │
                          └───────────▲────────────────────────────────▲───────────┘
                                      │ Read/Write Storage             │ Sampling
                                      │                                │
┌─────────────────────────────────────┴────────┐        ┌──────────────┴──────────────────────────┐
│               SIMULACIÓN GPU                 │        │                 RENDERER                │
│             scripts/snow_field.gd            │        │     materials/snow_deform.gdshader      │
│  - Pipeline Compute asíncrono (RenderingDev) │        │  - Desplazamiento vertical por vértice  │
│  - Conservación de masa y volumen            │        │  - Cálculo de normales View-Space       │
│  - Ángulo de reposo bi-fásico y cohesión     │        │  - Sombra azulada en oquedades          │
│  - Cola de operaciones y sondas asíncronas   │        │  - Destellos sutiles de escarcha        │
└──────────────────────▲───────────────────────┘        └─────────────────────────────────────────┘
                       │ Llamadas de corte, vertido, palmeo y sondeo
┌──────────────────────┴──────────────────────────────────────────────────────────────────────────┐
│                                    GAMEPLAY & CONTROLADORES                                    │
│                                                                                                 │
│  scripts/player_controller.gd        scripts/snowball.gd      scripts/pin_prop.gd               │
│  - 1ª persona con bob/sway           - Acreción R³            - Clavado con PinJoint3D           │
│  - Sustentación sobre los montones   - Masa/inercia dinám.    - Extraíble tirando                │
│  - Pala, Turbina, Salero             - Rodadura y surco       scripts/props_system.gd            │
│  - Resistencia, vertido, palmeo      scripts/snow_chunk.gd    - Reparto de objetos y bolas       │
│  - Coger/cargar/lanzar               - Reabsorción de terrones                                   │
│                                                                                                 │
│  scripts/hud.gd  ·  scripts/sound_effects.gd  ·  scripts/main.gd                                │
└─────────────────────────────────────────────────────────────────────────────────────────────────┘
```

### Simulación en compute shader (`shaders/snow_sim.glsl`)

Toda la deformación y el transporte de nieve ocurre directamente en la GPU mediante Vulkan `RenderingDevice`. La textura de simulación (512×512 RGBA32F) **nunca se descarga a la CPU**: sólo se lee un resumen de 64×64 texeles (16 KB por frame, de forma asíncrona) que alimenta al gameplay.

| Canal | Significado |
|---|---|
| R | altura total (1.0 = `snow_depth` metros) |
| G | nieve **suelta** movilizable (sólo esta fracción puede fluir) |
| B | **cohesión / humedad** (modula el ángulo de fricción interna) |
| A | scratch de relajación: `+escala` = celda en reposo, `−escala` = en flujo |

| Modo | Función |
|---|---|
| 0 | **Recolección**: muestrea la nieve bajo la plancha y la acumula en cubetas internas de masa. Con `max_cut` > 0 la hoja trabaja como formón (esculpido de láminas finas). |
| 1 | **Depósito**: distribuye la nieve frente a la hoja con perfil longitudinal y dispersión lateral gaussiana, con bermas de desborde. |
| 2 | **Sellos**: huella de bota (hunde y compacta) y limpieza radial (la sal, además, rompe la cohesión). |
| 3 | **Vertido libre**: inyecta volumen con perfil cónico marcado como nieve suelta y húmeda. |
| 4-5 | **Relajación y ángulo de reposo**: evalúa el exceso de pendiente entre texeles y distribuye el flujo granular con **histéresis bi-fásica** (32° dinámico, +8° para arrancar desde el reposo; la cohesión lo eleva hasta 54°). |
| 6 | **Estadísticas y sondas**: lee de forma asíncrona progreso global, alturas locales y el volumen retirado por cada operación. |
| 7 | **Palmeo**: aplana por difusión y asienta plásticamente empujando la masa sobrante hacia fuera. |
| 8 | **Siega cilíndrica**: retira nieve a lo largo de un segmento y reporta el volumen exacto (acreción de bolas y esculpido). |
| 9 | **Espejo CPU**: resumen 64×64 (altura media, nieve suelta, cohesión y altura máxima por bloque). |

### Malla de nieve y shader (`materials/snow_deform.gdshader`)

Un plano de **8 × 12 metros** subdividido densamente (200 × 260 vértices) que eleva su geometría según el mapa de alturas, con cálculo analítico de normales por fragmento para evitar dientes de sierra, y que revela un pavimento de adoquines estilizados con asfalto oscuro cuando la nieve llega a cota cero.

---

## 3. Las herramientas del jugador

### [1] Pala quitanieves manual
La herramienta principal de trabajo físico.

- **Click izquierdo (empujar/cortar):** abre una zanja rectangular limpia frente a los pies. La nieve se acumula en un montón frontal creciente y se desborda por los extremos en bermas laterales. Mirando al frente la hoja corta **láminas finas** (esculpido libre).
- **Resistencia real, pero sin arrastrarse:** `F = μ·N + k_corte·ancho·h_nieve + M·a` se usa como lectura física y para decidir la traba, mientras que la velocidad de avance sale de un arrastre acotado `1/(1+arrastre)`. En la práctica: pala vacía en nieve virgen ≈ 80 % de la velocidad; pala llena (25 kg) paleando un montón de 45 cm ≈ 58 % (≈ 2,4 m/s). **La pala sólo se traba** ante un montón más alto que la hoja, y entonces basta con mirar al frente para cortar fino, verter, o palmear con `Q` para rebajarlo.
- **Click derecho mantenido (Tilt & Dump):** la hoja se inclina y **vierte** la carga en chorro continuo justo bajo la hoja, transfiriendo la masa al terreno en tiempo real para rellenar hoyos o amontonar donde se quiera.
- **Click derecho (pulsación corta):** **lanzamiento parabólico** de la carga como terrones físicos 3D volumétricos (`scripts/snow_chunk.gd`). Lanzados hacia los bancos laterales otorgan dinero y puntos extra.
- **Q (palmeo):** golpea la nieve con la cara plana; aplana, compacta y sube la cohesión, dejando la superficie firme.

### [2] Turbina quitanieves motorizada (Snowblower)
Diseñada para desintegrar rápidamente grandes volúmenes de nieve. Absorbe la nieve frontal en un radio amplio y proyecta un chorro direccional hacia los laterales, con audio de motor a combustión continua.

### [3] Esparcidor de sal térmica (Thermal Salt Shaker)
Herramienta química/térmica para disolver parches delgados y películas resbaladizas. Derrite la nieve en un radio circular revelando el asfalto mojado, y **reduce la cohesión a cero**, de modo que la nieve tratada fluye como arena seca.

### Manos libres (construcción emergente)
- **E:** coger bolas y objetos (o extraerlos si están clavados) y **apelmazar nieve** con las manos. La bola apelmazada nace **directamente en las manos**, lista para lanzar con click derecho, sin caer al suelo.
- **Click derecho mientras se carga:** lanzar el objeto o la bola con el impulso heredado del movimiento de la mano.

---

## 4. Física emergente de construcción (sin botones de ensamblaje)

El muñeco de nieve no es una misión guiada: es el resultado natural de las mismas reglas que permiten hacer una muralla, una escultura o una pista de trineo.

- **Bolas rodantes (Sistema 3, `scripts/snowball.gd`):** la sustentación se resuelve con un apoyo elástico a lo largo de la normal del terreno y la fricción se aplica sobre el **deslizamiento real en el punto de contacto**, así que el par genera rodadura pura. Cada 12 cm de recorrido la bola siega una franja y absorbe el volumen exacto que reporta la GPU, creciendo según `R = ∛(R³ + 3ΔV/4π)` y dejando el surco limpio detrás. La densidad **crece con el tamaño** (300 → 470 kg/m³), así que pesa más que un R³ puro: 2 kg con 12 cm de radio, 32 kg con 28 cm, 266 kg con 52 cm. Una bola pequeña rueda lejos y una gigante se frena casi de inmediato.
- **Apilado por unión de nieve (Sistema 4):** cuando una bola se posa centrada sobre otra y ambas están casi quietas, se consolida una unión física (`Generic6DOFJoint3D`) que aporta la estabilidad mecánica del muñeco. Un impacto fuerte la rompe. Las bolas son siempre **esferas limpias**, sin geometría de deformación añadida.
- **Peso y acarreo (preparado para cooperativo):** *tambalearse cuesta control, no velocidad*. La velocidad al andar cargando es `1/(1 + masa/300)` con **suelo del 75 %**; a partir de **35 kg** la bola se lleva **con las dos manos por encima de la cabeza** y el jugador **se tambalea** (deriva lateral, menos control, balanceo de cámara) hasta que el **agarre se agota** y la bola puede escapársele. El lanzamiento cae con la masa de forma suavizada (`v = 9·(1,7/m)^0,30`, extra ×1,8 a dos manos): **1,7 kg → 7,5 m/s** y **146 kg → 3,6 m/s**, con fuerza pero menos que una bola normal. Mientras cargas, las herramientas se guardan.
- **Rotura por impacto (`scripts/snow_burst.gd`):** una bola que golpea a más de 7 m/s **se deshace**: el 55 % de su masa vuelve al manto en el punto del golpe y el resto sale en una lluvia de fragmentos con su nube de nieve pulverizada. Rodar o caer suave no la rompe. Los fragmentos y la nube son **provisionales**, con gancho (`SnowBurst.fragment_scene` / `puff_scene`) para sustituirlos por modelos reales pre-fracturados sin tocar la física.
- **Clavado físico (`scripts/pin_prop.gd`):** ramas, piedras, zanahorias y carbón se fijan con un `PinJoint3D` real (o congelación cinemática) cuando su punta penetra nieve compacta o una bola. Se extraen tirando de ellas, saltan si la bola rueda rápido y **se caen solas si se palea la nieve que las sostiene**.
- **Reabsorción de terrones:** todo fragmento que pierde su energía cinética se disuelve y reintegra su volumen al manto, de modo que la masa del sistema no se pierde por el camino.

---

## 5. Entorno y escenario

- **Cabaña nórdica cozy** (`cozy_cottage.glb`): madera rústica tallada con aleros nevados, chimenea y ventanas iluminadas.
- **Bosque de pinos estilizados**: mallas distribuidas alrededor de la propiedad para crear sensación de aislamiento y calidez.
- **Farolas de latón Poly Haven** (`lantern_01.glb`): montadas sobre postes de madera con luz omnidireccional cálida que proyecta sombras suaves sobre los montículos de nieve.
- **Bancos de descanso** (`bench.glb`) y bordillos de madera rústica.

---

## 6. Estado actual del desarrollo

### Logrado
- Caminata en primera persona con sustentación suave y estable; el jugador **se apoya y sube a los montones reales** de nieve (y desciende al hueco que deja al despejar).
- Simulación completa en GPU con compute shader y **conservación de masa verificada** (error < 0,5 % en la batería de pruebas).
- Reología granular con **cohesión/humedad** y **ángulo de reposo bi-fásico** (32° dinámico, 40° estático, hasta 54° en nieve húmeda).
- Amontonamiento real frente a la pala con desborde lateral, **resistencia y traba** de la pala, y **palmeo** que aplana y compacta.
- **Volcado suave (Tilt & Dump)** con click derecho mantenido, y lanzamiento parabólico con pulsación corta.
- **Bolas rodantes con acreción de masa**, masa/inercia/colisión dinámicas, resistencia de rodadura por tamaño y surco limpio (sólo se siega con contacto continuo: lanzar una bola ya no deja una línea en la nieve).
- **Ensamblaje universal**: apilado estable con rodal de nieve aplastada en el contacto (la bola siempre esférica), clavado físico de objetos y esculpido de láminas con la hoja.
- Reabsorción de terrones en el manto (economía de masa cerrada).
- HUD funcional con porcentaje despejado, kilogramos retirados, carga de la pala, dinero acumulado y **avisos contextuales** (pala trabada, carga en las manos, nieve apelmazándose).
- Huellas de pisadas en la nieve con audio reactivo según si pisas nieve o pavimento limpio.
- Lanzamiento de terrones físicos con detección de bancos laterales para recompensas.
- **Bordes de lo recogido limpios**: la malla de nieve (320×480) y el shader del terreno comparten un mismo filtro de huella, así que el corte de la pala y el cráter de la turbina se ven nítidos y con labio biselado, sin dientes oscuros ni agujas de sombra (el viewmodel no proyecta sombra).

### Pendiente / siguientes pasos
- Arte técnico **Pure Baked PBR** para los objetos nuevos de juego (bolas, ramas, piedras, carbón, zanahorias): albedo/normal/roughness horneados con UV de objeto.
- Comportamiento térmico real de la sal sobre el material del pavimento (húmedo, reflectivo y resbaladizo de forma persistente).
- Carga física de objetos en la pala (hoy se cargan con las manos) y volcado sobre estructuras.
- Sustituir bancos laterales de premio por geometría jugable con nieve interactiva.
- Limpieza del repositorio: hay capturas de pruebas (`*_test.png`, `phys_*.png`, `carve_*.png`) y registros (`*_run.log`, `run_output.txt`) sueltos en la raíz.

---

## 7. Controles

| Tecla | Acción |
|---|---|
| W A S D / Shift / Espacio | Moverse, correr, saltar |
| Click izquierdo | Empujar / cortar nieve |
| Click derecho mantenido | Inclinar la pala y verter |
| Click derecho (toque) | Lanzar nieve (o el objeto cargado) |
| **Q** | Palmear / aplanar y compactar |
| **E** (pulsación) | Coger objetos y bolas · apelmazar nieve con las manos |
| **E** (mantener) | Empujar la bola pegada al suelo, sin levantarla |
| 1 / 2 / 3 | Pala / Turbina / Salero |
| R / ESC | Reiniciar nivel / liberar ratón |
| **H** | Mostrar u ocultar la ayuda de teclas (por defecto está oculta para no tapar la escena) |

---

## 8. Verificación automática

```
godot --path . -- --phys-demo     # 21 comprobaciones de los 4 sistemas + balance de masa
godot --path . -- --plow-demo     # demo original de empuje con la pala
```

La primera ejecuta una secuencia guionizada, mide la conservación de masa (manto + bolas frente al inicial) y guarda capturas `phys_01..10_*.png`. Resultado esperado: **21 OK / 0 fallos**.

Detalle técnico completo de los cuatro sistemas (canales, modos del compute, API pública y decisiones de diseño) en [`docs/fisicas_nieve.md`](docs/fisicas_nieve.md).
