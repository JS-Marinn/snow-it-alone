# Emergent snow physics — Snow It Alone

This document describes the snow physics system implemented in the
prototype. The guiding idea is that **there are no guided missions and no
assembly buttons**: four systems cooperate and the snowman, the wall
or the sculpture appear as a consequence of the same rules.

```
SYSTEM 1  continuous GPU terrain (height, loose snow, cohesion, avalanches)
     ▲                                        ▲
     │ mass transfer (dump / scoop)           │ rolling and furrow
     │                                        │
SYSTEM 2  physical shovel        ◄──────►  SYSTEM 3  3D balls and chunks
(resistance, load, dumping,                (R³ accretion, dynamic mass and
 patting, sculpting)                        inertia, reabsorption)
                                                   ▲
                                                   │
                                           SYSTEM 4  universal assembly
                                           (stacking by deformation, pinning)
```

## System 1 — Continuous terrain (`shaders/snow_sim.glsl`, `scripts/snow_field.gd`)

`RGBA32F` texture 512×512 in ping-pong over an 8 × 12 m field (32 cm of
virgin snow), with **strict mass conservation**:

| Channel | Meaning |
|---|---|
| R | total height (1.0 = `snow_depth` metres) |
| G | **loose**, movable snow (only this fraction can flow) |
| B | **cohesion / moisture** (modulates the internal friction angle) |
| A | relaxation scratch: `+scale` = cell at rest, `−scale` = flowing |

**Two-phase angle of repose (hysteresis):** a cell at rest must exceed the
*static* angle (`dynamic + hysteresis`, 32° + 8° by default)
to start moving, and a cell already in motion settles at the
*dynamic* angle. Cohesion raises both: dry snow (B≈0) flows at 32°, wet
and packed snow (B→1) holds 54°.

Compute shader modes:

| Mode | Function |
|---|---|
| 0 | The blade collects the snow under the plate (`max_cut` > 0 → chisel: sculpting) |
| 1 | The blade deposits its load in front of it, forming a heap |
| 2 | Stamps: boot print (sinks and compacts) and radial clearing (salt breaks cohesion) |
| 3 | **DUMP**: injects free volume with a conical profile, flagged as loose and wet snow |
| 4-5 | Granular relaxation in two passes (output scale + transfer) |
| 6 | Statistics, probes and **volume removed per operation** |
| 7 | **TAMP**: flattens by diffusion and settles plastically by pushing mass outwards |
| 8 | **HARVEST**: cylindrical mowing along a segment (accretion and sculpting) |
| 9 | Reduced 64×64 mirror for CPU gameplay queries |

**CPU mirror:** every frame the GPU writes a 64×64 summary (mean height,
mean loose snow, mean cohesion and maximum height per block) that the CPU reads
asynchronously. It is used to resolve the player's support on the heaps,
the shovel's resistance, the rolling of the balls and the pinning of objects,
without reading the full texture.

Relevant public API: `dump_snow(pos, kg, radio)`, `tamp(pos, radio, fuerza)`,
`request_harvest(owner, desde, hasta, radio, profundidad)`,
`carve_shovel(pos, dir, ancho, largo, corte_máximo)`, `get_height_at(pos)`,
`get_support_snow_height(pos)`, `get_cohesion_at(pos)`, `get_loose_fraction_at(pos)`.

### Rendering and simulation: a single filtered value

The simulation grid has texels of **1.56 × 2.34 cm** (512² over 8 × 12 m)
and the snow mesh has one vertex every **2.5 cm** (`mesh_subdiv_x/z` = 320 × 480).
Sampling the map raw with that grid mismatch produced **aliasing**: the
edges of what had been collected came out in dark "teeth" with inverted normals.

That is why `materials/snow_deform.gdshader` always reads the map through the same
footprint filter `sample_height()`, whose radius (`smooth_uv`) is set by `SnowField`
from the actual mesh subdivision. **Displacement, colour mask and normals use
that same filtered value**, so geometry and lighting agree and the
edge stays clean. Associated settings:

- Narrow snow→pavement mask (`smoothstep(0.010, 0.060, h)`) → clean edge.
- Environment `SSAO` softened (radius 1.15 · intensity 0.85): it used to darken
  the bottom of the hollows too much.
- Lighter pavement (wet slate) so that the contrast with the snow does not
  turn any irregularity into a black patch.
- The **viewmodel casts no shadow** (`GeometryInstance3D.SHADOW_CASTING_SETTING_OFF`):
  the shovel plates are very thin and with a low sun their shadow stretched into
  a blue "needle" over the snow.

## System 2 — Physical shovel (`scripts/player_controller.gd`)

- **Real resistance, but never dragging yourself along**: there are two magnitudes
  kept separate on purpose.
  - *Physical reading* `F = μ·N + cut_k·width·snow_h + m·a` (`snow_resistance`
    in N): it is shown in the HUD and decides the **stall**.
  - *Forward drag* `push_drag = plow_drag_per_m·h·bite + load_drag_per_kg·kg`
    and speed `= base / (1 + push_drag)`: bounded by construction, so that
    the snow slows you down but never turns walking into dragging.

  Values measured with `--phys-demo`: empty shovel in virgin snow ≈ **80%** of
  the speed; full shovel (25 kg) clearing a path through a 45 cm heap ≈ **58%**
  (≈ 2.4 m/s). The shovel **only stalls** with a heap taller than the blade
  (`stuck_height_m`) or a resistance > `stuck_resistance`, and then it advances at
  `stuck_speed_factor` with a warning in the HUD: you get out by facing forward (fine
  cut), dumping or patting with `Q`.
- **Attack angle**: facing the ground the blade bites the whole layer; flat
  it works like a chisel and lifts thin shavings (free sculpting).
- **Flow-limited load**: the shovel does not fill up in one hit (max. 34 kg/s,
  25 kg of capacity).
- **Right click held** → the blade tilts and **pours** in a continuous stream
  under the blade, transferring mass to the terrain in real time.
- **Right click (short press)** → **parabolic throw** of chunks.
- **Q** → **patting**: flattens, compacts (G→0) and raises cohesion.

## System 3 — Rolling balls (`scripts/snowball.gd`)

- The support is resolved with a spring-damper along the
  **terrain normal** (critically damped, rest penetration
  ≈ 2.4 cm) and friction is applied to the **actual sliding at the contact
  point**, so that the torque produces pure rolling instead of braking the
  ball.
- **Accretion**: every 12 cm travelled the ball mows a strip the width of its
  footprint and absorbs the exact volume the GPU reports
  (`R = ∛(R³ + 3ΔV/4π)`), leaving the clean furrow behind.
  The mowing only joins points with **continuous contact with the snowpack**: the anchor is
  invalidated as soon as the ball is clearly in the air (thrown, falling or
  bouncing) and any jump larger than `MAX_HARVEST_STEP` (0.45 m) re-anchors without
  mowing. Without that, on landing after a throw a straight strip was scratched
  from the throw point to the landing point: an unnatural "line".
- **Dynamic mass and inertia, with increasing density**: `m = 4/3·π·R³·ρ(R)` and
  `ρ(R)` rises from **300 to 470 kg/m³** with size (the snow compacts and expels
  air as it rolls). The ball therefore weighs **more** than a pure R³: 2 kg with
  r=0.12 · 32 kg with r=0.28 · 73 kg with r=0.36 · 266 kg with r=0.52. Godot
  derives the inertia from the mass and the shape, so it updates itself.
- **Rolling resistance** that grows with the cube of the size: a small ball
  rolls a long way and a giant one is stopped almost immediately.
- **Push by FORCE, not by acceleration** (`PUSH_FORCE_NEWTONS` = 260 N, capped
  at 26 m/s²): the player pushes with their body and the same force moves a light
  ball a lot and a heavy one barely at all.
- **Chunks** (`scripts/snow_chunk.gd`): any fragment that loses its energy
  dissolves and **reintegrates its volume** into the snowpack.
- **Impact breakage** (`scripts/snow_burst.gd`): if a ball hits above
  `break_speed_threshold` (7 m/s) **it breaks apart**. 55% of its mass returns to
  the snowpack right at the point of impact (`dump_snow`) and the rest is spread in a
  shower of fragments with scatter velocities, plus a cloud of powdered
  snow and its sound. Rolling or falling gently does not break it. The mass is thus
  kept closed: what was a ball becomes a heap + chunks that are reabsorbed.
  - **Hook for final art**: the fragments and the cloud are **provisional**
    (spherical chunks and `CPUParticles3D`). It is enough to assign
    `SnowBurst.fragment_scene` / `SnowBurst.puff_scene` to a `PackedScene` for
    `_make_fragment()` to instantiate the real pre-fractured model; the rest of the
    system (mass, impulses, reabsorption) does not change.

## System 4 — Universal assembly (`scripts/snowball.gd`, `scripts/pin_prop.gd`, `scripts/props_system.gd`)

- **Stacking by snow bonding**: when a ball rests centred on another and
  both are almost still, a **physical joint** is consolidated
  (`Generic6DOFJoint3D` locked) that provides the mechanical stability of the snowman.
  A strong impact breaks it. The balls are **always clean spheres**: there is no
  added deformation geometry (verified by `--ball-shape`).
- **Pinning**: branches, stones, carrots and coal carry `sharpness`. If the
  tip penetrates snow with enough cohesion (or a ball) they are fixed with a
  real **`PinJoint3D`** or with kinematic freezing. They are extracted by pulling on
  them, they pop off if the ball rolls fast and **they fall on their own if the snow
  that holds them is shovelled away**.
- **Carrying with the hands** — `E` has three behaviours depending on how it is used:
  - **short press on something** → pick it up (or extract it if it is pinned);
  - **press on snow** → **pack** a ball: the mass is mowed from the snowpack
    with `request_harvest` and the ball is born **already in the hands**, at the carry
    point and in carry mode in the same frame, without falling to the ground;
  - **hold on a ball** → **push it glued to the ground**: it remains a
    dynamic body resting on the snowpack (it never lifts) and the force is
    bounded, so the heavier it is the harder it is to move.
  Right click while carrying **throws**. The grip adapts to size
  (`_carry_anchor`): a hand-sized ball at ~0.7 m and a large one at ~1.3 m.
- **Real weight when carrying** (designed for co-op), aiming to feel
  pleasant: *staggering costs CONTROL, not speed*.
  - Walking speed while carrying is `1/(1 + mass/300)` with a **floor of 75%**:
    17 kg → 95%, 124 kg → 75%. It never turns into dragging yourself along.
  - From **35 kg** the ball is held with **BOTH hands above the
    head** (anchored to the body, not to the view: looking at the ground does not sink it).
  - With more weight the player **staggers**: oscillating lateral drift, less
    acceleration control and camera sway, proportional to
    `stagger = (mass − 35)/(150 − 35)`.
  - The **grip** runs out (`0.05 + 0.22·stagger` per second) and, if it reaches zero,
    the ball **slips out of your hands**: the HUD warns from 30%.
  - **Throw**: the speed falls with mass in a **smoothed** way
    (`v = 9·(1.7/m)^0.30`) and with two hands there is an extra force ×1.8. Both throws leave flat along the aim: any arc comes from gravity, which is why throwing further means aiming up.
    It never beats the light ball: weight always takes away, but a large ball is
    thrown **with force** (146 kg → 3.6 m/s) instead of staying stuck.
    Measured: **1.7 kg → 7.5 m/s** versus **146 kg → 3.6 m/s**.
  - While you are carrying something, the tools are stowed (your hands are busy).

## Controls

| Key | Action |
|---|---|
| W A S D / Shift / Space | Move, run, jump |
| Left click | Push / cut snow |
| Right click held | Tilt the shovel and pour |
| Right click (tap) | Throw snow (or the carried object) |
| **Q** | Pat / flatten and compact |
| **E** (press) | Pick up objects and balls · pack snow with the hands |
| **E** (hold) | Push the ball glued to the ground, without lifting it |
| 1 2 3 | Shovel / Turbine / Salter |
| R / ESC | Restart level / release mouse |
| **H** | Show or hide the key help (starts hidden) |

## Automated verification

```
godot --path . -- --phys-demo
```

It runs a scripted sequence that checks the four systems, measures
**mass conservation** (snowpack + balls versus the initial state), verifies the weight and
carrying (**two hands, staggering without going slow, pushing with `E` held, throwing
by mass and impact breakage**) and saves captures `phys_01..12_*.png`. Expected
result: **36 OK / 0 failures**, with a mass error below 0.5%.

Data measured in the last run: shovelling 2.4 m/s · carrying 124 kg **3.13 m/s
(74% of the normal speed)** with stagger 0.77 · pushing with `E`: 0.84 m without
lifting the ball · throw 1.7 kg → **7.5 m/s**, 146 kg → **3.6 m/s** · breakage:
11 fragments and the snowpack rises from 0.320 to 0.588 m at the point of impact.

### Other diagnostic batteries

| Command | What it checks |
|---|---|
| `--ball-shape` | That the ball is **always spherical** (when growing and when stacking) and that **throwing it does not scratch a line** in the snowpack: it measures mesh, scale, rendered AABB and the height profile of the flight. |
| `--carve-quality` | Terrain quality when collecting: it opens a trench and a crater, dumps the height profile and saves captures. |
| `--plow-demo` | Original shovel pushing demo. |
