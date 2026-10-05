# Snow It Alone

A tactile, atmospheric and *cozy* first-person simulator developed in **Godot 4.7 (Forward+)**, focused on cleaning, manipulating and the **granular physics** of snow in a picturesque Nordic mountain cabin.

The project was born inspired by the tactile, zen satisfaction of games such as *PowerWash Simulator*, combined with the vibrant, sculptural visual identity and curious physical materials in the style of *Donkey Kong Bananza* and Nintendo's production standards.

---

## 1. Core pillars of the game

### Faithful real-time granular physics (on GPU)
Snow is not a mere cosmetic effect or a static plane: it is a physical medium with **real volume**, **strict mass conservation**, angle of repose, cohesion and resistance. Every cubic centimetre of snow pushed or collected exists within the physical economy of the world.

### *Cozy*, stylised atmosphere
A warm log cabin with a smoking chimney, surrounded by a dense forest of snowy pines, wooden posts and rustic brass lanterns lit at sunset. The experience combines the relaxation of clearing a winter yard with the tactile richness of the materials.

### Art direction: *Pure Baked PBR*
Following strict technical art directives: zero runtime camera-dependent procedural distortion shaders. Surfaces modelled and textured with seamless 3D object coordinates, baked into standard physical PBR maps (Albedo, Normal, Roughness, Metallic) with soft bevels and museum-piece light response.

> **Status of this directive:** met in the terrain and the scene (snow displacement does not depend on the camera), **pending** in the new game objects (snowballs, branches, stones, coal), which today use flat materials created at runtime.

---

## 2. Technical architecture and technologies

The project runs on a very high-performance architecture aimed at squeezing the hardware without micro-stutters:

```
                          ┌────────────────────────────────────────────────────────┐
                          │                    GPU ENGINE (Vulkan)                 │
                          │  - Forward+ Renderer                                   │
                          │  - Compute Shader: shaders/snow_sim.glsl               │
                          │  - Ping-Pong RGBA32F Storage Textures (Texture2DRD)    │
                          │  - Reduced 64x64 mirror (summary for gameplay)         │
                          └───────────▲────────────────────────────────▲───────────┘
                                      │ Read/Write Storage             │ Sampling
                                      │                                │
┌─────────────────────────────────────┴────────┐        ┌──────────────┴──────────────────────────┐
│               GPU SIMULATION                 │        │                 RENDERER                │
│             scripts/snow_field.gd            │        │     materials/snow_deform.gdshader      │
│  - Async Compute pipeline (RenderingDev)     │        │  - Vertical per-vertex displacement     │
│  - Mass and volume conservation              │        │  - View-Space normal computation        │
│  - Bi-phasic angle of repose and cohesion    │        │  - Bluish shadow in cavities            │
│  - Operation queue and async probes          │        │  - Subtle frost glints                  │
└──────────────────────▲───────────────────────┘        └─────────────────────────────────────────┘
                       │ Cut, pour, pat and probe calls
┌──────────────────────┴──────────────────────────────────────────────────────────────────────────┐
│                                     GAMEPLAY & CONTROLLERS                                      │
│                                                                                                 │
│  scripts/player_controller.gd        scripts/snowball.gd      scripts/pin_prop.gd               │
│  - First person with bob/sway        - Accretion R³           - Pinning with PinJoint3D         │
│  - Support on the snow piles         - Dynamic mass/inertia   - Removable by pulling            │
│  - Shovel, Turbine, Salt Shaker      - Rolling and groove      scripts/props_system.gd          │
│  - Resistance, pour, pat            scripts/snow_chunk.gd    - Object and ball spawning         │
│  - Pick up/carry/throw               - Clump reabsorption                                       │
│                                                                                                 │
│  scripts/hud.gd  ·  scripts/sound_effects.gd  ·  scripts/main.gd                                │
└─────────────────────────────────────────────────────────────────────────────────────────────────┘
```

### Simulation in a compute shader (`shaders/snow_sim.glsl`)

All snow deformation and transport happens directly on the GPU through Vulkan `RenderingDevice`. The simulation texture (512×512 RGBA32F) **is never downloaded to the CPU**: only a 64×64 texel summary is read (16 KB per frame, asynchronously) to feed the gameplay.

| Channel | Meaning |
|---|---|
| R | total height (1.0 = `snow_depth` metres) |
| G | **loose** movable snow (only this fraction can flow) |
| B | **cohesion / moisture** (modulates the internal friction angle) |
| A | relaxation scratch: `+scale` = cell at rest, `−scale` = flowing |

| Mode | Function |
|---|---|
| 0 | **Collection**: samples the snow under the blade and accumulates it in internal mass buckets. With `max_cut` > 0 the blade works as a chisel (sculpting thin shavings). |
| 1 | **Deposit**: distributes the snow in front of the blade with a longitudinal profile and Gaussian lateral spread, with overflow berms. |
| 2 | **Stamps**: boot print (sinks and compacts) and radial clearing (salt also breaks the cohesion). |
| 3 | **Free pour**: injects volume with a conical profile marked as loose and wet snow. |
| 4-5 | **Relaxation and angle of repose**: evaluates the excess slope between texels and distributes the granular flow with **bi-phasic hysteresis** (32° dynamic, +8° to start from rest; cohesion raises it up to 54°). |
| 6 | **Statistics and probes**: asynchronously reads global progress, local heights and the volume removed by each operation. |
| 7 | **Patting**: flattens by diffusion and settles plastically by pushing the surplus mass outwards. |
| 8 | **Cylindrical mowing**: removes snow along a segment and reports the exact volume (snowball accretion and sculpting). |
| 9 | **CPU mirror**: 64×64 summary (average height, loose snow, cohesion and maximum height per block). |

### Snow mesh and shader (`materials/snow_deform.gdshader`)

A plane of **8 × 12 metres** densely subdivided (200 × 260 vertices) that raises its geometry according to the height map, with analytical per-fragment normal calculation to avoid sawtooth artifacts, and that reveals a pavement of stylised cobblestones with dark asphalt when the snow reaches zero level.

---

## 3. The player's tools

### [1] Manual snow shovel
The main physical work tool.

- **Left click (push/cut):** opens a clean rectangular trench in front of your feet. The snow accumulates in a growing frontal pile and overflows at the ends into lateral berms. Looking straight ahead the blade cuts **thin shavings** (free sculpting).
- **Real resistance, but without crawling:** `F = μ·N + cut_k·width·snow_h + m·a` is used as a physical reading and to decide the jam, while the advance speed comes from a bounded drag `1/(1+drag)`. In practice: empty shovel in virgin snow ≈ 80% of speed; full shovel (25 kg) shovelling a 45 cm pile ≈ 58% (≈ 2.4 m/s). **The shovel only jams** against a pile taller than the blade, and then it is enough to look straight ahead to cut thin, pour, or pat with `Q` to lower it.
- **Right click held (Tilt & Dump):** the blade tilts and **pours** the load in a continuous stream right under the blade, transferring the mass to the terrain in real time to fill holes or pile it up wherever you want.
- **Right click (short press):** **parabolic throw** of the load as volumetric 3D physical clumps (`scripts/snow_chunk.gd`). Thrown towards the side banks they grant money and extra points.
- **Q (patting):** strikes the snow with the flat face; it flattens, compacts and raises cohesion, leaving the surface firm.

### [2] Motorised snow turbine (Snowblower)
Designed to rapidly disintegrate large volumes of snow. It absorbs the snow in front of it over a wide radius and projects a directional jet towards the sides, with continuous combustion-engine audio.

### [3] Thermal salt spreader (Thermal Salt Shaker)
Chemical/thermal tool for dissolving thin patches and slippery films. It melts the snow over a circular radius, revealing the wet asphalt, and **reduces cohesion to zero**, so that the treated snow flows like dry sand.

### Free hands (emergent construction)
- **E:** pick up snowballs and objects (or extract them if they are pinned) and **pack snow** with your hands. The packed snowball is born **directly in your hands**, ready to be thrown with right click, without falling to the ground.
- **Right click while carrying:** throw the object or the snowball with the impulse inherited from the hand's movement.

---

## 4. Emergent construction physics (no assembly buttons)

The snowman is not a guided mission: it is the natural result of the same rules that allow you to build a wall, a sculpture or a sledding track.

- **Rolling snowballs (System 3, `scripts/snowball.gd`):** support is resolved with an elastic contact along the terrain normal and friction is applied on the **real slip at the contact point**, so the torque produces pure rolling. Every 12 cm of travel the snowball mows a strip and absorbs the exact volume reported by the GPU, growing according to `R = ∛(R³ + 3ΔV/4π)` and leaving the groove clean behind. Density **grows with size** (300 → 470 kg/m³), so it weighs more than a pure R³: 2 kg at 12 cm radius, 32 kg at 28 cm, 266 kg at 52 cm. A small snowball rolls far and a giant one brakes almost immediately.
- **Stacking by snow bonding (System 4):** when a snowball comes to rest centred on another and both are almost still, a physical bond (`Generic6DOFJoint3D`) consolidates that provides the snowman's mechanical stability. A strong impact breaks it. Snowballs are always **clean spheres**, with no added deformation geometry.
- **Weight and carrying (ready for co-op):** *staggering costs control, not speed*. Walking speed while carrying is `1/(1 + mass/300)` with a **75% floor**; from **35 kg** the snowball is carried **with both hands above the head** and the player **staggers** (lateral drift, less control, camera sway) until the **grip runs out** and the snowball may slip away from them. The throw drops off with mass in a smoothed way (`v = 9·(1.7/m)^0.30`, extra ×1.8 two-handed): **1.7 kg → 7.5 m/s** and **146 kg → 3.6 m/s**, with force but less than a normal snowball. While you carry it, the tools are stowed.
- **Impact breakage (`scripts/snow_burst.gd`):** a snowball that hits at more than 7 m/s **falls apart**: 55% of its mass returns to the snowpack at the point of impact and the rest comes out in a shower of fragments with their cloud of pulverised snow. Rolling or falling softly does not break it. The fragments and the cloud are **provisional**, with hooks (`SnowBurst.fragment_scene` / `puff_scene`) to replace them with real pre-fractured models without touching the physics.
- **Physical pinning (`scripts/pin_prop.gd`):** branches, stones, carrots and coal are fixed with a real `PinJoint3D` (or kinematic freezing) when their tip penetrates compact snow or a snowball. They are extracted by pulling on them, they pop out if the snowball rolls fast and **they fall on their own if the snow holding them is shovelled away**.
- **Clump reabsorption:** every fragment that loses its kinetic energy dissolves and reintegrates its volume into the snowpack, so that the system's mass is not lost along the way.

---

## 5. Environment and setting

- **Cozy Nordic cabin** (`cozy_cottage.glb`): rustic carved wood with snowy eaves, chimney and lit windows.
- **Stylised pine forest**: meshes distributed around the property to create a sense of isolation and warmth.
- **Poly Haven brass lanterns** (`lantern_01.glb`): mounted on wooden posts with a warm omnidirectional light that casts soft shadows over the snow mounds.
- **Rest benches** (`bench.glb`) and rustic wooden kerbs.

---

## 6. Current development status

### Achieved
- First-person walking with soft and stable support; the player **rests on and climbs the real snow piles** (and descends into the hollow left behind when clearing).
- Full GPU simulation with a compute shader and **verified mass conservation** (error < 0.5% in the test battery).
- Granular rheology with **cohesion/moisture** and **bi-phasic angle of repose** (32° dynamic, 40° static, up to 54° in wet snow).
- Real piling in front of the shovel with lateral overflow, **resistance and jamming** of the shovel, and **patting** that flattens and compacts.
- **Smooth dumping (Tilt & Dump)** with right click held, and parabolic throw with a short press.
- **Rolling snowballs with mass accretion**, dynamic mass/inertia/collision, size-dependent rolling resistance and a clean groove (it only mows with continuous contact: throwing a snowball no longer leaves a line in the snow).
- **Universal assembly**: stable stacking with a clump of crushed snow at the contact (the snowball always spherical), physical pinning of objects and thin-sheet sculpting with the blade.
- Reabsorption of clumps into the snowpack (closed mass economy).
- Functional HUD with cleared percentage, kilograms removed, shovel load, accumulated money and **contextual warnings** (jammed shovel, load in the hands, snow packing).
- Footprints in the snow with reactive audio depending on whether you step on snow or clean pavement.
- Throwing physical clumps with detection of side banks for rewards.
- **Clean edges of what is collected**: the snow mesh (320×480) and the terrain shader share the same footprint filter, so the shovel cut and the turbine crater look sharp with a bevelled lip, without dark sawteeth or shadow spikes (the viewmodel does not cast a shadow).

### Pending / next steps
- **Pure Baked PBR** technical art for the new game objects (snowballs, branches, stones, coal, carrots): albedo/normal/roughness baked with object UVs.
- Real thermal behaviour of salt on the pavement material (wet, reflective and persistently slippery).
- Physical loading of objects onto the shovel (today they are carried with the hands) and dumping onto structures.
- Replace the side reward banks with playable geometry with interactive snow.
- Repository cleanup: there are test screenshots (`*_test.png`, `phys_*.png`, `carve_*.png`) and logs (`*_run.log`, `run_output.txt`) loose in the root.

---

## 7. Controls

| Key | Action |
|---|---|
| W A S D / Shift / Space | Move, run, jump |
| Left click | Push / cut snow |
| Right click held | Tilt the shovel and pour |
| Right click (tap) | Throw snow (or the carried object) |
| **Q** | Pat / flatten and compact |
| **E** (press) | Pick up objects and snowballs · pack snow with your hands |
| **E** (hold) | Push the snowball stuck to the ground, without lifting it |
| 1 / 2 / 3 | Shovel / Turbine / Salt Shaker |
| R / ESC | Restart level / release mouse |
| **H** | Show or hide the key help (hidden by default so it does not cover the scene) |

---

## 8. Automated verification

```
godot --path . -- --phys-demo     # 21 checks of the 4 systems + mass balance
godot --path . -- --plow-demo     # original shovel-push demo
```

The first one runs a scripted sequence, measures mass conservation (snowpack + snowballs versus the initial one) and saves screenshots `phys_01..10_*.png`. Expected result: **21 OK / 0 failures**.

Full technical detail of the four systems (channels, compute modes, public API and design decisions) in [`docs/fisicas_nieve.md`](docs/fisicas_nieve.md).
