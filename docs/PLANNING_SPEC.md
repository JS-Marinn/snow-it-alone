# SNOW IT ALONE — Planning Specification

**What this is.** Every design and planning detail this project has settled, in one place, so the
game can be rebuilt without re-deriving it. **It deliberately says nothing about architecture** —
no file layout, no class design, no engine structure. That is yours. What follows is *what the game
is* and *what each thing must do*, with the measured numbers that make each rule checkable.

**How to read it.** Every number here was read out of the running code, not remembered. Where a rule
exists because a specific wrong version was measured and discarded, the wrong version and its
measurement are included: those are the expensive parts, and they are the parts a rebuild will
otherwise repeat.

Language convention for the rebuild: **code, comments, UI and documentation in English.**

---

## 1. The game

**Snow It Alone** (working title: *Snow It Together*). A co-op snow-shovelling game, built in
Godot 4.7.2 by one programmer. Playable and enjoyable **solo** — a second player must be a bonus,
never a requirement.

The loop: snow falls and piles up; the player clears it with tools; the cleared area is progress;
delivered snow earns money; money buys tools. It is a labour game — the satisfaction is in the work
becoming visibly done.

### The core tension that governs the design

Snow is **mass**, and mass is conserved. That single rule produces most of the interesting
behaviour and most of the hard bugs:

- Shovelling does not destroy snow, it relocates it. Push it and it becomes a berm you must deal
  with later.
- Packing a ball removes snow from the pack and puts it in your hands.
- **The disposal machine is the only true sink** — the only place snow leaves the world. Everything
  before it is rearrangement.

A rebuild must decide this up front: *does mass leave the world anywhere else?* In the current
design the answer is no, and that is what makes the machine the destination.

---

## 2. The snow itself

This is the heart of the game and the most expensive thing to get wrong. **§2b describes the
technique; read it before designing anything else.** What follows here is the numeric envelope.

| Property | Value | Meaning |
|---|---|---|
| `TEX_SIZE` | 512 | Simulation grid (512² RGBA32F, ping-ponged) |
| `COARSE_SIZE` | 64 | CPU-readable mirror, the only thing gameplay reads |
| `MAX_OPS` | 12 | Field operations per frame — **a hard budget, see §2c** |
| `BUCKETS` | 192 | Sideways pressure-transfer buckets for the granular relaxation |
| `RELAX_ITERATIONS` | 8 | Relaxation iterations per frame |
| `SETTLE_TIME` | 2.5 s | Time for disturbed snow to settle |
| `DEPOSIT_LAMBDA` | 0.16 | Snowfall deposition falloff |
| `DEPOSIT_LENGTH` | 0.70 | Snowfall deposition radius scale |
| `RELAX_RATE` | 0.08 | Relaxation rate |
| `TAMP_SETTLE` | 0.03 | Height change from a tamp |
| `TAMP_COMPACT` | 0.85 | Compaction factor from a tamp |

### The rule that makes gameplay possible

**Everything gameplay reads comes from the 64-wide coarse mirror, and it is quantised.** Two
consequences, both measured, and both of which cost real time:

1. **A whole-field mass integral drifts by more than a small delivery.** Measured: the same
   untouched world read **23199.15 kg** and then **23202.04 kg**. The drift is several kilograms,
   while what gets delivered is a few. *Any rule of the form "the total mass must be unchanged" is
   unmeasurable at that scale.* If the rebuild needs mass accounting it needs a **ledger** — the
   per-operation volume the simulation already reports (mode 6, §2b) — not an integral.
2. **Small local changes are visible where totals are not.** A 22 cm harvest disc is readable even
   though the whole-field integral cannot resolve it. Measure locally, or keep a ledger.

### The four surface classes

Surfaces are classified by **cohesion and height**, and the classification drives player speed:

| Surface | Recognised by | Player speed multiplier |
|---|---|---|
| Cleared | height below ~0.03 m | fastest |
| Packed | cohesion ≥ 0.45 | fast |
| Snow | cohesion ≥ 0.35 | baseline |
| Powder | untouched dry snow | slowest |

Measured reference points: untouched dry snow sits near **cohesion 0.20**; a tamped strip near
**0.68**.

### Snowfall

Deposition is continuous, with a falloff (`DEPOSIT_LAMBDA = 0.16`, `DEPOSIT_LENGTH = 0.70`) so
drifts build where you would expect.

---

## 2b. THE PHYSICS TECHNIQUE — how the snow model actually works

**Read this section before designing anything.** The previous draft of this document described the
snow as "a GPU simulation with a coarse mirror", which is true and useless. This is the actual
model, taken from `shaders/snow_sim.glsl` and `docs/fisicas_nieve.md`.

### The representation: a heightfield with a material state

A **`RGBA32F` texture, 512 × 512, ping-ponged**, over the field. Four channels, and the choice of
what goes in each one *is* the model:

| Channel | Meaning |
|---|---|
| **R** | **Total height.** `1.0` means `snow_depth` metres |
| **G** | **Loose** — the movable fraction. **Only this part can flow** |
| **B** | **Cohesion / moisture** — modulates the internal friction angle |
| **A** | Relaxation scratch: `+scale` = the cell is at rest, `−scale` = the cell is flowing |

**The key idea: height alone is not snow.** The same height with different `G` and `B` behaves
completely differently — that is how dry powder and a packed path can look identical and walk
differently. A rebuild that models only height will not be able to express this game.

**Strict mass conservation** across the two-phase flow is a stated property of the system.

### The angle of repose, with hysteresis

This is the granular rule that makes heaps behave.

- A cell **at rest** must exceed the **static** angle to start moving: `dynamic + hysteresis`, by
  default **32° + 8° = 40°**.
- A cell **already moving** settles at the **dynamic** angle, **32°**.
- **Cohesion raises both.** Dry snow (`B ≈ 0`) flows at **32°**; wet and packed snow (`B → 1`) holds
  up to **54°**.

**Two-phase hysteresis is why a pile has a definite shape and does not creep.** A single angle makes
heaps melt into flat cones over time.

### The compute modes

Each mode is a dispatch. A rebuild needs an equivalent of every row, because together they are the
whole vocabulary of the material.

| Mode | Function |
|---|---|
| 0 | **Blade collects** the snow under the plate. `max_cut > 0` turns it into a **chisel**, which is how free sculpting works |
| 1 | **Blade deposits** its load in front of it, forming a heap |
| 2 | **Stamps**: boot print (sinks and compacts) and radial clearing (salt breaks cohesion) |
| 3 | **Dump**: injects free volume with a **conical profile**, flagged loose and wet |
| 4–5 | **Granular relaxation in two passes** (output scale + transfer) |
| 6 | **Statistics, probes, and the volume removed per operation** |
| 7 | **Tamp**: flattens by diffusion and settles plastically by pushing mass outwards |
| 8 | **Harvest**: cylindrical mowing along a segment (accretion and sculpting) |
| 9 | The reduced **64 × 64 mirror** for CPU queries |

**Mode 6 is where mass accounting comes from.** "Volume removed per operation" is a first-class
output of the simulation, which is what makes an exact ledger possible at all.

### The CPU mirror, and why gameplay must not read the full texture

Every frame the GPU writes a **64 × 64** summary — **mean height, mean loose snow, mean cohesion and
maximum height per block** — which the CPU reads **asynchronously**.

It resolves: the player's support on heaps, the shovel's resistance, the rolling of balls, and the
pinning of objects. **Gameplay never reads the 512² texture.**

**The consequence that has cost this project the most time:** the mirror is **quantised**, so:

1. **A whole-field mass integral drifts by more than a small delivery.** Measured: the same
   untouched world read **23199.15 kg** and then **23202.04 kg**. That drift is several kilograms,
   while the things that get delivered are a few kilograms. **Any rule of the form "the total mass
   must not change" is unmeasurable at this scale.** Mass accounting needs a **ledger** — an exact
   counter taken where the snow is removed (mode 6's per-operation volume) — not an integral.
2. **Small local changes are visible where totals are not.** A 22 cm harvest disc is readable even
   though the whole-field integral cannot resolve it. **Measure locally, or keep a ledger.**

### Resolution, and the aliasing trap

| Quantity | Value |
|---|---|
| Simulation texel | **1.56 × 2.34 cm** (512² over 8 × 12 m) |
| Snow mesh vertex spacing | **2.5 cm** (`mesh_subdiv_x/z` = 320 × 480) |

**The two grids do not match, and sampling the map raw produced aliasing**: the edges of collected
snow came out in **dark "teeth" with inverted normals**.

**The rule: rendering must read the map through ONE filtered sample whose radius is derived from the
actual mesh subdivision**, and **displacement, colour mask and normals must all use that same
filtered value** so geometry and lighting agree. In the current build this is `sample_height()` with
its radius set from the mesh subdivision.

Three settings that go with it, each fixing a specific artefact:

- **A narrow snow→pavement mask** — `smoothstep(0.010, 0.060, h)` — for a clean edge.
- **Softened SSAO** (radius 1.15 · intensity 0.85): it used to darken the bottoms of hollows too
  much.
- **Lighter pavement** (wet slate), so contrast with the snow does not turn any irregularity into a
  black patch.
- **The viewmodel casts NO shadow.** The shovel plates are very thin, and with a low sun the shadow
  stretched into a blue "needle" over the snow.

### The public API the technique exposes

`dump_snow(pos, kg, radius)`, `tamp(pos, radius, strength)`,
`request_harvest(owner, from, to, radius, depth)`,
`carve_shovel(pos, dir, width, length, max_cut_m)`, `get_height_at(pos)`,
`get_support_snow_height(pos)`, `get_cohesion_at(pos)`, `get_loose_fraction_at(pos)`.

**`carve_shovel` must return what it removed.** That is the hook mass accounting hangs on. Its value
is estimated from a **probe with latency** — it can be **zero on the frame an operation is queued** —
so anything measuring mass must account for the queue, not just the call. See §2c.

### Bodies on snow: a spring along the terrain normal

Objects do not collide with a snow mesh. They ride a **spring-damper along the terrain normal**,
critically damped, with a rest penetration of about **2.4 cm**, and friction applied to the **actual
sliding at the contact point** so the torque produces **pure rolling** instead of braking the body.

| Constant | Value |
|---|---|
| `SUPPORT_STIFFNESS` | 400.0 |
| `SUPPORT_DAMPING` | 40.0 |
| `CONTACT_FRICTION` | 0.85 |
| `NORMAL_SAMPLE_OFFSET` | 0.16 m |

**A body riding the spring must NOT also collide with the terrain**, or it is supported twice.

### Accretion: how a ball grows

Every **12 cm travelled** the ball **mows a strip the width of its footprint** and absorbs the
**exact volume the GPU reports**, leaving the clean furrow behind:

```
R = ∛(R³ + 3ΔV / 4π)
```

**The mowing only joins points that were in continuous contact with the snowpack.** The anchor is
invalidated as soon as the ball is clearly in the air, and any jump larger than `MAX_HARVEST_STEP`
(**0.45 m**) re-anchors **without mowing**.

**Why that rule exists, measured:** without it, landing after a throw scratched a **straight strip
from the throw point to the landing point** — an unnatural "line" drawn across the snow.

### Density rises with size — the ball is NOT a pure R³

```
m = 4/3 · π · R³ · ρ(R)
```

**`ρ(R)` rises from 300 to 470 kg/m³** with size: the snow compacts and expels air as it rolls. **A
ball therefore weighs more than its volume at constant density.**

Measured reference masses: **2 kg at r = 0.12 · 32 kg at r = 0.28 · 73 kg at r = 0.36 · 266 kg at
r = 0.52.**

**Consequences that follow:**

- **Rolling resistance grows with the cube of the size.** A small ball rolls a long way; a giant one
  is stopped almost immediately.
- **Godot derives inertia from mass and shape**, so it updates itself — no separate inertia curve to
  maintain.
- **The push is by FORCE, not acceleration**, so the same force moves a light ball a lot and a heavy
  one barely at all.

> **⚠ A DOCUMENTATION DRIFT TO RESOLVE.** The technique document says `PUSH_FORCE_NEWTONS = 260 N`
> capped at **26 m/s²**. The code reads **380 N** capped at **32 m/s²**. Same for the break threshold:
> the document says **7 m/s**, the code says a tiered **2.5–5.0 m/s** depending on ball size (§5).
> **One of the two is stale and the document does not say which.** Do not carry either forward without
> checking against the build you are porting from.

### Breaking, and why mass stays closed

Above the break threshold a ball **breaks apart**, and the split is specified:

- **55 % of its mass returns to the snowpack right at the impact point** (`dump_snow`).
- **The rest is spread as a shower of fragments** with scatter velocities, plus a powdered-snow cloud
  and a sound.
- **Chunks that lose their energy dissolve and reintegrate their volume** into the pack.
- **Rolling or falling gently does not break it.**

So **what was a ball becomes a heap plus chunks that are reabsorbed** — the mass stays closed, which
is the same invariant as everywhere else.

**Hook for final art:** fragments and the cloud are **provisional** (spherical chunks and CPU
particles). Assigning a pre-fractured scene to the fragment and puff slots makes
`_make_fragment()` instantiate the real art, and **the rest of the system — mass, impulses,
reabsorption — does not change.** A rebuild should keep that seam.

### Stacking and pinning: the "no assembly buttons" design

The guiding idea of the whole physics document, in its own words: **there are no guided missions and
no assembly buttons** — four systems cooperate and the snowman, the wall or the sculpture appear as a
consequence of the same rules.

- **Stacking by snow bonding.** When a ball rests centred on another and both are almost still, a
  **physical joint is consolidated** (a locked 6-DOF joint) that gives the snowman its mechanical
  stability. **A strong impact breaks it.** The balls are **always clean spheres** — there is no added
  deformation geometry.
- **Pinning.** Branches, stones, carrots and coal carry a **`sharpness`**. If the tip penetrates snow
  with enough cohesion (or a ball) it is fixed with a **real pin joint** or by kinematic freezing.
  They are **extracted by pulling**, they **pop off if the ball rolls fast**, and they **fall on their
  own if the snow holding them is shovelled away.**

**That last clause is the design in one line:** an object is held by the snow, so removing the snow
removes the support. A rebuild should preserve it, because it is what makes the material feel like a
material rather than a surface.

---

## 2c. HOW THE SNOW IS BUILT — the construction method

This section was missing from the first draft and it is one of the most important ones: the game
**manufactures** its snow out of the same operations the tools use, and there is a measured rule
about how fast you are allowed to feed it.

### The field's defining properties

Everything about a level's snow comes from four exported numbers on the field:

| Property | Meaning |
|---|---|
| `field_width` | Metres, across |
| `field_length` | Metres, along |
| `snow_depth` | How deep a full pack is, in metres |
| `snow_density` | Kilograms per cubic metre |

From those the field computes its own budget at startup:

```
total_snow_kg = field_width × field_length × snow_depth × snow_density
```

The current level is **8 × 12 m**; the test scene is **10 × 40 m**. That is also how progress is
reported: cleared pixels over total pixels, scaled by `total_snow_kg`.

### The initial state

The field starts as **packed virgin snow**: compaction `G = 0` (immobile) with a **slight
cohesion**. It is not powder and it is not cleared; it is the undisturbed pack a fresh level
begins with.

### Constructing a surface: use the game's OWN operations

The four test lanes are **not** painted on and **not** written into an initial buffer. They are
**manufactured by queueing the same field operations the tools call**, and that is deliberate:

> so a lane cannot come to mean something the real tools would not produce.

The recipe, per 0.6 m step along the run:

| Lane | Built with | Parameters |
|---|---|---|
| **virgin** (x = -3.75) | *nothing* | It is the untouched pack |
| **packed** (x = -1.25) | `tamp` | radius 0.5, strength 1.0 |
| **shovelled** (x = +1.25) | `carve_shovel` | forward `(0, 0, 1)`, blade 0.9 × 1.2 m, depth 0.4 |
| **deep** (x = +3.75) | `dump_snow` | 70 kg per step at radius 0.45 |

**Accumulating across the run:** over a 36 m length that is roughly **171 operations**, and the
deep lane ends up holding on the order of **120 kg per step** in the denser variant used elsewhere
in the scene.

**Two properties worth carrying into a rebuild:**

- **Every surface is reproducible from operations.** Anyone can look at a lane and know exactly what
  the tools did to make it, which is what makes the lane a fair test surface.
- **Constructing with `dump_snow` means starting snow can be heavier than the model's own fall.**
  That is how a "deep" lane is made at all.

### THE RULE: feeding the simulation too fast DROPS operations silently

**The field's operation buffer is small** (`MAX_OPS = 12` per frame in the current build).

> **Measured:** feeding it too fast silently drops operations, **and the ones dropped are always the
> last of each batch.** This was found by watching **carves disappear while the tamps and dumps
> around them survived** — because the carve was queued last in each group.

**So construction must be deferred across frames, not run in one go**, with a conservative budget:

- Queue the operations as **deferred calls** rather than invoking them immediately, so the build can
  be spread over frames.
- Drain a **small fixed number per frame** — the current build uses **2** — and accept that building
  a large surface takes many frames.
- **Order matters within a batch**, because the last entries are the ones that get dropped. If a
  surface depends on several operations at one point, put the ones you cannot lose first.

**A rebuild should treat the operation buffer's size as a design constraint, not an implementation
detail.** It is the reason a level cannot simply "be built" in one frame, and a rebuild that assumes
otherwise will silently produce levels with pieces missing — and, worse, will produce them
*consistently wrong in the same way*, which reads like a design choice rather than a bug.

### What this means for a level's life cycle

1. **The level starts** as packed virgin snow at the configured depth and density.
2. **A builder queues operations** to shape it: lanes for tests, banks and piles for gameplay, a
   cleared path for a tutorial.
3. **The sim drains the queue** a few operations per frame until it is empty.
4. **The snow settles** (`SETTLE_TIME = 2.5 s`) before anything measures it. **Any test that measures
   the field must wait for the settle, and any test that consumes the operation buffer must not run
   concurrently with a build.**
5. **Gameplay operations join the same queue** — a shovel push is just more operations, which is
   exactly why the surfaces above are fair.

**A trap that follows from point 5:** a test that clears a strip and then measures what a tool does
to it is measuring **the same queue**. The current build spent four attempts on exactly this and the
resolution was to stop asking the world and count where the mass is removed. See §14.

---

## 3. Movement

A first-person, momentum-preserving controller. Counter-Strike-shaped on purpose.

| Property | Value |
|---|---|
| `walk_speed` | 4.2 |
| `sprint_speed` | 6.8 |
| `ground_accelerate` / `air_accelerate` | 12.0 / 12.0 |
| `ground_friction` | 5.0 |
| `ground_stop_speed` | 1.5 |
| `jump_velocity` | 5.2 |
| `gravity` | 18.0 |
| `air_wish_speed` | 1.0 |
| `chain_window` | 0.25 s |
| `bhop_cap_factor` | 2.0 |
| `mouse_sensitivity` | 0.0025 |
| `STICK_LOOK_SPEED` / `STICK_DEADZONE` | 2.4 / 0.18 |

**Design intentions, measured:**

- **Walking must feel fast; sprinting must clearly beat it.** Acceptance: walk 3.57 m/s mean,
  sprint 5.78 m/s mean, and **letting go must stop the player in under half a second**.
- **Hopping in a straight line must gain nothing** (5.78 m/s straight hop = sprint speed). An **air
  strafe does gain speed** (12.72 m/s) — bunny-hopping is an intended skill, not a bug.
- **A hop respects its ceiling** via `chain_window` + `bhop_cap_factor`.
- **Ground surface changes speed**: packed walking measured 4.41 m/s against slower powder.
- `auto_bhop` and `auto_bhop_min_speed` exist as options; default off.

### The pinned facing trap

The current build has a `_pin_player_facing` mechanism used by tests. A rebuild should decide
whether the player's facing is ever externally forced, because that is what made several movement
tests flaky.

---

## 4. The shovel

The default tool, and the one with the most design churn. **The current design has three verbs.**

### Shovel modes

The shovel has two **modes**, and the mode is chosen by whoever owns the player. LEGACY is the old
behaviour; LOAD_AND_PUSH is the one the owner asked for.

**LEGACY** — left button pushes a front and also flattens (tamping); right button pours and tosses.

**LOAD_AND_PUSH** — the mode that should be the default in a rebuild:

| Verb | Button | Behaviour |
|---|---|---|
| **Push** | LEFT (`shovel_push`) | Drives a front of snow forward **and picks up a residue while doing it** |
| **Release** | RIGHT (`shovel_load`) | Empties the blade where it is pointed, in one go |
| **Tamp** | `shovel_tamp` | **Not reachable in this mode.** Pressing does nothing — no effect, no message |

**In LOAD_AND_PUSH there is no throw.** The mode already has a way to move snow (the push) and does
not need a second way to throw it; the release frees the same button.

### The residue, and the value it must have

**Why a residue exists at all:** a real shovel dragged along the ground does not come up empty.
Something stays on the blade. It is also what gives the player a reason to push rather than only to
load.

| Constant | Value |
|---|---|
| `PUSH_RESIDUE_FACTOR` | **0.25** — the residue is a quarter of the deliberate load rate |

**Measured behaviour to reproduce:** pushing feeds **8.50 kg/s** against a declared residue of
8.50; deliberate loading feeds **34.00 kg/s**. The blade takes **17.000 kg in 2.00 s** — exactly
8.5 × 2.

### The mass rule — the single most expensive bug in this project

**The mass the field gives up is the mass the blade receives.**

The correct order of operations:

1. Decide how much the field may give up this frame: `allow = min(fill_rate × delta, room)`, where
   `room` is how much the blade can still hold. **The rate limits the CUT.**
2. Scale `allow` by `PUSH_RESIDUE_FACTOR` in LOAD_AND_PUSH. **Scaling what is cut is where a "pick
   up less" rule belongs.**
3. If `allow` is ~0, **cut nothing at all.** A full blade must stop taking snow out of the world,
   not remove it and drop it.
4. Take everything the field returned.

**What was there instead, and what it cost:**

```gdscript
# WRONG — 60% of the snow was deleted from the world every frame the shovel touched it
var added := minf(kg_cut * 0.4, fill_rate * delta + 0.35)
```

The field lost a kilogram and the blade gained 400 grams. In LOAD_AND_PUSH the same line scaled it
again by the residue fraction, so the blade kept **ten per cent** and ninety per cent vanished. This
was in the shipped game, not only in the new mode. It was measured as a **763 % mass-ledger error**
and was first misdiagnosed as a problem with the test's measurement window.

Two further traps found in the same block:

- **A per-frame floor distorts a rate.** `+ 0.35` per frame is 21 kg/s. With the floor in, pushing
  fed 12.49 kg/s against a declared 8.50.
- **`minf(kg_cut * 0.4, ...)` was almost certainly meant as "the shovel does not fill in one hit".**
  That intention is satisfied by rate-limiting the CUT, which is the only version of it that does
  not destroy snow.

### Blade physics

| Property | Value |
|---|---|
| `shovel_capacity_max` | 25.0 kg |
| `cut_resistance_per_m` | 52.0 |
| `stuck_resistance` | 140.0 |
| `stuck_height_m` | 0.58 m |
| `plow_drag_per_m` | 1.0 |
| `load_drag_per_kg` | 0.018 |
| `load_resistance_factor` | 0.18 |
| `fill_rate` | 34.0 kg/s |
| `dump_rate` | 9.0 kg/s |
| `tamp_radius` | 0.36 m |
| `BLADE_WALL_HEIGHT` | **0.30 m** |

**The jam rule:** snow taller than `BLADE_WALL_HEIGHT` jams the blade, and a jammed blade takes
nothing. The wall is the height of the shovel's side wall — above it snow spills over the edge
instead of being carried. A jam must be a **property of the blade**, not of a button, so it applies
to the deliberate load and the pushing front alike.

**Carrying cost:** an empty shovel in fresh snow runs at about 80 % speed; a full one (25 kg) at
about 60 %. Resistance must be felt but must never turn walking into crawling. Only a pile taller
than the wall really jams the shovel.

### Aiming, and the rule that took four attempts

**Gathering snow requires the aim point to be CLOSE.** This is the specification, in the owner's
words:

> "Gathering snow happens where the reticle is: if I look straight ahead instead of down, it must
> not gather snow."

| Property | Value |
|---|---|
| `PACK_REACH_STRICT` | **1.3 m** |
| `PACK_REACH_EXTENDED` | 2.4 m (legacy; not used for the decision) |
| `PACK_MIN_KG` | 0.435 kg |
| `PACK_HARVEST_RADIUS` | 0.22 m |
| `PACK_HARVEST_DEPTH` | 0.10 m |

**The trap:** the original gate was "the ray hit something" AND "there is snow at the aim point".
**Both pass while looking forward**, because looking forward puts the aim point on the ground metres
away, where there is plenty of snow. The missing requirement was distance, and the constant for it
already existed and was not applied to the decision.

**Two more rules that go with it:**

- **ONE predicate decides both the reticle state and the pack.** A reticle that says CAN_PACK while
  a tap does nothing — or a tap that packs while the reticle says OFF — is the bug class.
- **The door must close BEFORE anything is queued.** An earlier attempt gated the *queued* harvest
  instead and produced **a hole in the snow with no ball**: mass leaving the world with nothing
  accounting for it. That attempt was reverted, and the reason is worth keeping: the order of
  operations here is load-bearing.

**Measured acceptance for the rebuild:**

| Aim | Expected |
|---|---|
| Down at snow within reach | CAN_PACK; a ball of ~1.213 kg; a local hole of ~+0.0245 m |
| Forward along the ground | OFF; no ball; local height unchanged to within 0.0000 m |
| At the sky | OFF; no ball; no hole |
| Down at cleared ground | OFF; no ball; no hole |

### Two input details worth deciding once

- **`shovel_tamp` is a key (Q), not a mouse button.** In LOAD_AND_PUSH it must be inert.
- **Actions are named, never button numbers in code** — `shovel_push`, `shovel_load`, `shovel_toss`,
  `shovel_tamp`, `interact`, `jump`, `move_*`, `sprint`, `toggle_cursor` — so bindings can be
  swapped without touching logic.

---

## 5. The snowball

Packed snow is a rigid body with a support spring, and the ball is the game's most physics-heavy
object.

### Density — the number that governs everything

| Constant | Value | Meaning |
|---|---|---|
| `LOOSE_DENSITY` | 150 | Fresh snow |
| `PACKED_DENSITY` | 300 | Packed by hand |
| `PACKED_DENSITY_COMPACT` | **470** | Compacted |

**A ball's mass is its volume times its density, and the density depends on how it was made.** A
rebuild must decide whether compaction (470) is reachable and how.

| Property | Value |
|---|---|
| `MIN_RADIUS` / `MAX_RADIUS` | 0.07 m / 0.55 m |
| `SETTLE_TIME` | 0.30 s |

### The support spring — copy this, do not re-derive it

The convention, shared by every body that rides the snow (the ball, and any prop added later):

| Constant | Value |
|---|---|
| `SUPPORT_STIFFNESS` | **400.0** |
| `SUPPORT_DAMPING` | **40.0** |
| `CONTACT_FRICTION` | **0.85** |
| `NORMAL_SAMPLE_OFFSET` | 0.16 m |

**Rules that come with it:**

- A body riding the spring must **not also collide with the terrain**, or it gets double support.
- **Copy the block; use the same dampings.** Two bodies of the same weight in the same snow must
  behave the same. If they diverge, the player feels it and cannot say why.
- Applied inside the body's force integration, from the local snow height.

### Packing

Gathering removes snow from the pack and forms a ball whose radius comes from **the exact volume
removed**. Measured: packing at a valid aim point yields a **1.213 kg** ball and leaves a local hole
of **+0.0245 m**.

### Throwing

| Property | Value |
|---|---|
| `throw_ref_speed` | 9.0 m/s (for a reference light ball) |
| `throw_ref_mass` | 1.7 kg |
| `throw_mass_exponent` | 0.30 |
| `two_hands_throw_boost` | 1.8 |
| `two_hands_mass` | 35.0 kg |
| `THROW_GRACE_DURATION` | **0.35 s** |

**Speed falls with mass on a SOFTENED exponent (0.30, not the 0.5 of constant energy)** so large
balls stay throwable, and two-handed throws get a boost. **It never exceeds the light-ball speed:
weight always costs.**

**No lift is added to a throw.** The upward term used to add 3.4 m/s of climb to a 7.5 m/s throw —
about 25° over the crosshair — and inheriting the hand's motion pushed it sideways. **The arc is
gravity's job: to throw far, aim up.**

### The thrower's own body deflects the ball — the bug that hid for rounds

**A carried ball is held INSIDE the thrower's collision capsule.** Measured: the ball's centre sits
about **0.39 m** from the centre of the capsule's top sphere, which has a **0.4 m** radius, so it
overlaps its own thrower by roughly **0.16 m** before it is ever released. It is frozen while
carried, so nothing happens — and on release it unfreezes and the character body ejects it.

Measured, reading velocity in the same frame as the throw and then on the next step:

```
same frame: 9.000 m/s ( 0.18, -1.65, -8.85)   aimed straight at the target
next step:  4.500 m/s (-3.18, -1.29, -2.91)   half the speed, thrown sideways
```

**Exactly half, with the direction rotated.** This is not gravity, not drag and not aim, and no
amount of aiming can fix it. A thrown ball therefore never reached the disposal machine from any
distance — the game's only income was unreachable by throwing — and the fault was investigated as
an aiming problem, then as a machine problem, and was neither.

**The rule for the rebuild: the thrower must not collide with a ball it just threw, for the duration
of the throw grace.** The grace already exists to stop a ball bursting on its own thrower; the same
window should cover the collision that carries the impulse, rather than a second timer that can
disagree with the first.

### Bursting

| Tier | Radius | Minimum hit speed |
|---|---|---|
| Small | ≤ 0.18 m | 5.0 m/s |
| Medium | ≤ 0.34 m | 3.5 m/s |
| Large | > 0.34 m | 2.5 m/s |

**Only a hit that counts breaks the ball.** Bursting on any contact meant a player simply walking
into a big ball resting on the ground destroyed it, with nothing thrown and nothing recorded.

**Hard impact against anything shatters the ball** above a `break_speed_threshold`, and the mass is
split between the field and a burst of fragments.

### Carrying

| Property | Value |
|---|---|
| `carry_distance` | 1.15 m |
| `stagger_full_mass` | 150.0 kg |

The carry point is derived from the camera, the object's radius and `carry_distance`, offset **down**
and to the **side**. Past `two_hands_mass` the ball is held with both hands above the head and the
player begins to stagger.

**A carried ball can be thrown. Bare hands must be able to throw it** — the only code that listened
for the throw button used to live on the shovel path, so a player who packed a ball by hand and
picked it up had **no way to throw it**: the button did nothing.

---

## 6. The disposal machine — the game's only sink

The destination of all the work. Real-world reference for the fiction: a **two-stage snow blower
fed on site, throwing snow up its chute into a tipper truck**. In the real flow a loader brings it
snow; **in this game the player IS the loader**, which is why the machine stands still.

**No model is needed and none should be expected.** An interactable box with a collision shape and a
flat colour is correct. Looking provisional is the point.

### The rules — each one is a specification, not a description

| Rule | Consequence |
|---|---|
| **Inert** | It never moves, never looks for snow, never aims |
| **Instant** | No queue, no timers, no internal state |
| **Never jams** | The only mechanic is: it goes in, it is gone |
| **Pays** | Through the same coin path as everything else. **No second currency** |
| **Accepts any snow** | Chunks and balls, any size |
| **Nothing but snow is swallowed** | A body that is not snow is refused. *With containers cut (§7) this reads as "do not eat things that are not snow" rather than "do not eat the bucket" — same line of code, different justification, and the justification is what a future reader needs* |
| **Does not accept players** | **Explicitly**, not by collision-layer accident |

### The two entries, and why the split is the design

| Entry | What arrives | What handles it |
|---|---|---|
| **Reception zone** | Chunks and balls that fly in | Read the kg off the body, pay, free the body |
| **Explicit tipping** | Buckets and wheelbarrows tipped in | The tip action calls `accept(kg, position)` |

**The split makes "containers must be emptied into it" true by construction:** the zone cannot
swallow a container because it does not collect containers at all.

**The player refusal must be written in code and commented as such**, because layers get edited by
people in a hurry and a refusal written in code does not. The comment the current build carries, and
which a rebuild should keep in spirit: *"one day someone will change the collision layers."*

### Three geometry and detection facts, all measured

1. **The machine needs a real opening.** The first version had one solid collision box with the
   mouth drawn as a plate on its front. A thrown ball hit the box and **shattered** on it. Measured:
   a **1.211 kg ball delivered 0.068 kg**. The fix is a throat — sill, two jambs and a lintel,
   leaving an opening at the mouth's height and width. **After it, the ball arrives whole and no
   burst line appears in the log at all.**
2. **The reception zone must sit in FRONT of the mouth, not at the machine's origin.** Centred on
   the origin it was buried inside the machine's own collision box. The build's own documentation
   said "in front of the mouth" from the start; the code did not do it.
3. **A fast body can cross an area between two physics steps.** `body_entered` fires on the
   *crossing*, and a ball leaves the hand at about 8 m/s — 13 cm per step. The reliable test is the
   one asked every frame: poll what is inside the zone rather than wait to be told. **Keep a
   per-frame handled list so a body caught twice in one frame is not paid for twice.**

Relevant constants in the current build: `reception_radius` 1.1 m, `reception_height` 1.15 m,
mouth at `(0, 1.05, -0.65)`, machine body 1.70 × 1.50 × 1.20 m centred at y = 0.75.

### The invisible truck sells itself without art

Three things must be visible or audible, and none of them needs a model:

- **A visible output spout**, so it is clear where it spits.
- **Output sound**: the motor under load, and the thud of snow landing in the box.
- **A counter: "Snow sent: X kg".**

**All player-facing strings go through the translation table and `tr()`.** Diagnostic output stays
English.

### Placement is a placeholder, and should be labelled as one

First in the **test scene** (the Playground), and in the real level at a reachable spot: **one end of
the field, beyond the banks.** In the current level the field is 8 × 12 m and the bank collision
boxes are solid from x = 4.0 to 8.5 within z ±9, which is why the machine sits **past the end of the
field** rather than beside it. That reasoning is the kind of thing a rebuild will re-derive
painfully — record it.

---

## 7. Containers — DECIDED AGAINST

**Neither the bucket nor the wheelbarrow is part of this design.** Both are out: the bucket was cut
by the owner, and the wheelbarrow never worked (the defect is recorded below, for the record, so a
future rebuild that wants one knows what it cost).

**This changes the shape of the loop, and a rebuild must follow it through:**

- **There is no intermediate container.** The player moves snow with the **shovel** and the
  **blower**, and the snow reaches the disposal machine **thrown, or under its own momentum** — not
  carried in a container.
- **The machine's "explicit tipping" entry therefore has no caller.** The machine's rules still say
  `accept(kg, position)` exists as a second entry, and it still should: it is the API for "something
  other than a loose body delivers snow". **But with no containers in the design, nothing uses it
  yet.** A rebuild should either keep it as the documented extension point or drop it — and if it
  keeps it, it should say plainly that it is unused. An API with no caller that nobody labels as such
  is how the next person concludes the feature is half-built.
- **The machine's "containers must be emptied into it, never swallowed" rule becomes moot** in
  practice, because there are no containers to swallow. **Keep the refusal mechanism anyway** — the
  reception zone must still not accept anything that is not snow — but the *reason* changes from
  "do not eat the bucket" to "do not eat things that are not snow". Those are the same line of code
  with a different justification, and the justification is what a future reader needs.
- **The HUD's container line** and any "what are you carrying in a bucket" readout are gone with
  them.

**What the design loses, and should be a conscious choice:** a container is the natural way to move
a *large* amount of snow a long distance for a *small* price in effort. Without one, the economics of
"carry snow to the far end of the field" rests entirely on thrown balls and blown snow. **The
economy's numbers (§8) were set with the machine as the only destination and have never been timed**,
so this is exactly the kind of thing to re-measure rather than assume — if carrying becomes too
expensive in effort, the answer might be a container after all, or a shorter field, or a different
payout.

### For the record: why the wheelbarrow never worked

Kept because **two of the four causes are about support physics and two are about geometry**, and all
four were paid for. A rebuild that tries a wheeled vehicle will meet them again.

1. **A support spring on the tray AND on the wheels.** They disagreed (reference radii 0.42 against
   0.22) and threw the tray to **y = 1.17 m** at 3.5 m/s.
2. **A spring only on the wheels, with a hinge.** The hinge **did not transmit the tray's weight**:
   the tray rode *above* its own wheels (origin 0.449 m, wheel centres 0.486 m) and the wheels felt
   only their own weight — **31.5 N of support for a 137 N barrow**.
3. **Support applied off the centre of mass on uneven ground.** The surfaces under a 1 m wheelbase
   vary by centimetres, and one point reading 0.14 m deeper took **166 N** by itself — a third of the
   weight in one corner. **Pitch 0° → 50° in half a second.** The remedy used was support at the
   **centre of mass** plus a weak explicit levelling torque, so the support cannot rotate the object.
4. **Rolling resistance with the sign inverted**, applied always against the body's own `-heading`,
   so it **pushed** when the barrow rolled backwards. Measured: raising it from 0.04 to 0.12 made the
   barrow **faster** (1.71 → 2.96 m/s).

**And the defect that was never fixed:**

> The contact points are **in the ground plane by construction**: the body's origin **is** the wheel
> contact line. So a barrow at ride height has its three points **0.22 m "below" the snow**, and a
> spring read directly from there puts `400 × 14 × 0.22 = 5.5 kN` on a 14 kg body — **thirty-nine g**.
> That is why it left at 6 m/s, and why raising the rolling resistance made it faster: the resistance
> was fighting a fraction of a force that should not exist.
>
> **The spring must be measured from where the barrow RESTS**, which is **one wheel radius up**. The
> deepest point decides, so no contact is compressed more than the suspension allows.

**Also decided, and not to be undone without measuring:** wheels must not collide with layer 1 (the
ground), only layer 2 — geometry **plus** a spring are two supports that disagree and the pair is
unstable; every force needs a **NaN guard** (without them two of three runs reported `travelled nan m`
and sat still until timeout); and **the push must be clamped** so it cannot exceed its target speed
(measured: 2.29 m/s against a target of 1.43).

### If a carrying container is ever wanted again, this is the contract it must satisfy

Recorded so the API is not re-invented inconsistently. A container must expose:

| Member | Meaning |
|---|---|
| `capacity_kg` | How much it holds |
| `own_mass_kg` | Its own empty mass |
| `footprint_radius` | For support and interaction |
| `contents_kg` | What it currently holds |
| `fill(kg)` | Returns how much it actually took |
| `take(kg)` | Returns how much it actually gave |
| `empty_all()` | Empties and returns the contents |
| `free_space_kg()` | How much more it can take |
| `fill_ratio()` | Contents over capacity |

Group `snow_containers`. **`fill` returns what it took and never more than the free space** — that is
the mass invariant, and it is why the return values matter rather than being void.

**One trap from the previous build, worth not repeating:** three container classes declared a
`contents_changed` signal that **nothing connected to**, because the HUD **polled** `contents_kg`
every frame instead. That is not broken, but a signal that looks like the update path and is not one
is a **decoy** — the next person to write a container will connect to it, see nothing happen, and have
to work out why. **Either connect it or do not declare it.**

---
## 8. The economy

**Read `docs/economy_placeholder.md` beside this.** Every price is a placeholder, the word
`placeholder` is in the values, and the missing number is **income per minute**, because the game's
loop has never been timed.

### The sink that pays

| Fact | Value |
|---|---|
| The disposal machine is the only income | Snow destroyed by the machine |
| Declared payout | **`ceil(kg × 2.5)` coins per delivery** (`PAYOUT_PER_KG = 2.5`) |
| Rationale for 2.5 | Delivering snow across the field costs real time and effort. There is **no second payer to compare against**: the banks are scenery and do not pay (§8), so the machine sets the rate on its own |
| Worked example | A 25 kg delivery yields 63 coins |

### The bank does NOT pay — a settled decision, not an unfinished one

**The banks are scenery. They are not a snow destination and they do not pay.**

The previous build had them pay `ceil(kg × 1.5)` when snow landed on them, and that was the game's
only income before the machine existed. That payment is **turned off** and the decision for the
rebuild is that it **does not come back**: the disposal machine is the one destination, and a second
payer would split the loop and make the machine pointless.

**What is worth keeping from that change, because it will happen again:**

- **The payment flag was turned off, not the code deleted.** The mechanic stayed recoverable for a
  while, and the reasoning was recorded rather than the mechanism removed. A rebuild that decides to
  drop a payer should delete it *deliberately* and say so — but should know that the cheap version
  of that decision is a flag, and that the flag then carries an obligation: **the tests that assert
  the old behaviour must be updated, never deleted.** They asserted something that *was* true, and
  what changed is information. Several batteries and tests in the previous build had to be rewritten
  for exactly this, and each one records why.
- **A bank that still "reports a hit" while paying nothing is a trap.** In the previous build the
  bank kept answering yes to "did snow land on me?" and this was guarded by a field size check:
  **`check_snowbank_hit` refuses to report a hit on a field longer than 25 m**, which is why the 40 m
  test scene has no banks at all. A rebuild that keeps banks as scenery should decide what "the bank"
  means to gameplay, if anything, **explicitly** — otherwise it becomes a landmark that silently does
  nothing.

If banks return as *visual* features only, that should be their whole description: a geometry-shaped
place where snow accumulates because snow accumulates anywhere.

### The fragment-rounding trap — the most recent economy bug

Independent of what the payer is, and read this before writing any payout.

The machine emits **once per body it swallows**, and a thrown ball that breaks on arrival is many
small bodies.

```gdscript
# WRONG — every fragment is worth at least one coin
var coins := int(ceil(kg * PAYOUT_PER_KG))
```

Measured: a ball broke into eight pieces, the machine took **0.546 kg** and paid **8 coins**, where
the declared formula says **2**. **Four times the rate — and the more a ball shattered, the more it
was worth**, which is exactly backwards: breaking snow must not be a way to print money.

**The rule for the rebuild: pay on the RUNNING TOTAL, not on the delivery.**

```
coins = ceil(total_kg × rate) − already_paid
```

Why this shape:

- The declared rate is unchanged. A price per kilogram means a price per kilogram.
- **The per-delivery floor is the whole defect.** `ceil` treats every delivery as worth at least one
  coin, which is right for a whole load and wrong for a crumb.
- **It is marginally cheaper to the player's benefit of the doubt**: 3.70 kg then 5.394 kg pays 10
  then 13 (23 in all), where rounding each delivery separately pays 14 and overpays by one. Measured
  in both the game and the tests.
- It is deterministic and checkable: coins paid are always exactly `ceil(total × rate)`.

**And a mass rule that goes with it:** every kilogram in the blade must have left the field, and
every kilogram that left the field must be in the blade. The current build enforces this with
**ledgers** (exact counters where mass is removed) rather than integrals, for the reason in §2.

### Tool ownership

Tools are owned or not, and that gates their use. "Hands" are always owned. Ownership is
**persisted per save slot**, which means the answer to "what tools does the player own" currently
comes from a save file — and that is why several tests have to manipulate the save system to test the
player. A rebuild should consider whether ownership belongs to the save or to the session.

---

## 9. The player state machine and combat

Snow is not only a material; it is also a physical argument between players.

| Property | Value |
|---|---|
| `hit_reactions_enabled` | true |
| `head_hit_radius` | 0.55 |
| `stagger_time` | 1.0 s |
| `knockdown_time` | 2.0 s |
| `hit_immunity_time` | 1.5 s |
| `face_snow_time` | 3.5 s |
| `face_wipe_time` | 0.6 s |
| `snow_face_auto_clear` | true |

**States:** NORMAL, staggered, knocked down. **Staggered or knocked-down players cannot work their
tools** — this is a design rule, not an implementation detail.

**A ball to the face** blinds the player, and `E` wipes it off instead of doing anything else.
There is a **session mode** (`session_mode.gd`) that decides whether thrown snow is a prank or just
snow: **in Work mode a ball to the face is nothing at all.** That distinction is deliberate and
should survive a rebuild.

**Impact tiers and minimum speeds** are in §5. The `impact_targets` group is how a ball recognises a
person.

---

## 10. The HUD

**One HUD, used by every scene.** This is not a style note: the HUD subtree once existed **byte for
byte identically** in the level and the test scene, all 24 node ids included, and a reticle fix
reached the level and **not** the test scene because of it. The owner reported that as a bug. Then
the fix for it was **another copy**. **A capability cannot be allowed to exist in one scene and not
the other.**

### What it shows

| Element | Notes |
|---|---|
| Title | `SNOW IT TOGETHER - Entrance Path` |
| Progress bar + percentage | Level completion |
| Snow removed (kg) | |
| Money | `Money: $N` |
| **Snow sent (kg)** | "Snow sent: X kg", next to the money |
| Tool name | |
| Shovel load bar | |
| Toss hint | |
| Container line | Contents of a container being carried |
| Reticle | See below |
| Victory panel | Hidden until earned |
| Pause menu | See §11 |
| Controls panel | |
| Settings panel | |

### The reticle — five attempts, and the reasons

**A reticle is drawn at the centre of the screen, always visible, and its colour reflects state.**
The current states: OFF (dim), CAN_PACK (a ball can be gathered), CAN_CARVE (a tool can cut).

**Three separate defects, each measured:**

1. **The reticle was white on white snow.** Measured: centre luma **0.96** against snow at **0.99** —
   **three per cent of contrast**. It was drawn, centred to the pixel, and **invisible by
   construction**. The owner reported it, and the geometry log said everything was fine. **A dark dot
   on a light ring reads on snow** — and snow is where this game is played. Optional: the ring should
   be light so the dot still reads against something dark.
2. **A reticle whose existence depends on state can be absent for a reason nobody can see.** The
   current build shows it in **every** state, dim when there is nothing to do, and colours it when
   there is. If you want it hidden when idle, hide it **deliberately** and say why.
3. **The acceptance test must be in PIXELS, not code.** "It compiles" and "the game loads" are not
   checks that something is visible. Write the viewport to a file, read it back, and compare the
   centre of the screen against the snow around it. The current build does this and reports
   contrast and colour:
   - looking down at close snow: dot at **(640, 360)**, contrast **0.493–0.588**, red-ish
   - looking forward: dot at **(640, 360)**, contrast **0.396**, not red

**A measurement trap:** searching for "the darkest pixel within 2 px of the centre" can report the
*edge* of the dot rather than its middle, which makes a 5 px dot read as a 2 px offset. Prefer a
mass-centre or a bounding box, and state the criterion.

### The HUD's own visibility, and the pause bug

**Both UI bugs the owner reported came from the same family of mistakes.**

1. **The HUD was hiding itself.** The pause menu was `visible=true` and being drawn into a layer
   whose own `visible` was false, so pausing showed **no menu and no HUD at all**. Measured
   rectangles before the fix: the menu at `(0, 0)` size `260 × 0`, the title at `(0, 0)` size
   `1 × 30`. **A HUD that hides itself at startup is not a HUD.** *Something outside the HUD script
   was clearing the flag and a search for the writer did not find it.* The rebuild should make the
   HUD's visibility the HUD's own business and expose a named method if a feature ever needs to hide
   it.
2. **`set_anchors_preset(PRESET_FULL_RECT)` does not size a Control.** It sets the **anchors** and
   leaves the **offsets** alone, so a Control freshly added to a `CanvasLayer` stays **zero by zero**
   and centres its children inside nothing — the panel lands at the top-left. **Use
   `set_anchors_and_offsets_preset`.** This mistake was in **six** places, including the main menu's
   background and centre container — **the screen the game opens on.**

**Measured acceptance after the fix:** menu rect `(510, 229)` size `260 × 261`, centre
**(640, 359.5)** against a viewport centre of `(640, 360)` — **off by one pixel** — with the world
and the whole HUD visible in the screenshot.

**An honest caveat from the current build:** both fixes were made together and **which one cleared
the visibility flag was never isolated.** Do not assume.

---

## 11. Menus, settings and translation

### Pause

The pause menu lives **inside the HUD**, and the HUD must keep working while the game is paused —
it owns the menu, so being paused must not stop it reading the key that unpauses.

Contents: **Resume, Restart level, Settings, Quit to menu.** A controller must be able to drive it,
so the first action takes focus.

**Pausing must genuinely stop the world.** The current build's diagnostic checks the physics frame
counter while paused, because "a pause that only hides the world behind a panel would pass a
screenshot test".

**`ui_cancel` closes, in order:** the controls panel, then the settings panel, then toggles the
pause.

### Settings and controls

- Settings and controls are panels in the HUD, each centred, each with its own visibility.
- **Rebinding exists**, and the current implementation stores **physical keycodes**.
- **A measured no-op, worth not repeating:** "Reset controls" restored nothing, because every
  shipped binding has `keycode == 0` while the describe step only handled `keycode != 0`. **Bindings
  described and restored must agree about which key field they mean.**

### Translation

- **All player-facing strings** go through the translation table and `tr()`. **Diagnostic output stays
  English.**
- `locale/strings.csv` holds keys with an English column and a pseudo-locale column.
- **The pseudo-locale is generated, not typed**: accented vowels, bracketed, and **padded with `~` to
  at least 140 % of the English length**, so layout problems show up before a real translation does.
- **A build marker is printed at startup** — `[BUILD] <short hash>` — because "am I running the code
  I think I am?" has cost this project real time twice, and a screenshot cannot answer it. The stamp
  is a file written by a tool that knows the repository, not read from git at runtime, so an exported
  build can say which commit it is.

---

## 12. World, layout and placement facts

Values a rebuild will otherwise re-derive. **These are the current build's, not necessarily the
rebuild's** — but the *reasons* transfer.

### The level

| Fact | Value |
|---|---|
| Field | **8 × 12 m** |
| Bank collision | Solid from **x = 4.0 to 8.5**, within **z ±9** |
| Bank payment | **Does not report a hit on a field longer than 25 m** |
| Level title | `SNOW IT TOGETHER - Entrance Path` |
| Decoration | A pine forest and a cabin, built in code, **with `load()` calls on the level-start frame** |

### The test scene (Playground)

| Fact | Value |
|---|---|
| Field | **10 × 40 m** |
| Run | `RUN_START = -18`, `RUN_END = 18` |
| Four lanes at x | **-3.75 (virgin/powder), -1.25 (packed), +1.25 (shovelled), +3.75 (deep)** |
| Training dummies at z | 2, 10, 18 |
| Ramps | On the +x side at z = 4 and 12, **geometry only: a slope has no simulated snow yet** |
| Snow sent field | The Playground's field is 40 m, so **it has no banks at all** |
| Debug keys | `[B]` spawn ball, `[N]` ball size (0.10 / 0.24 / 0.45 m), `[V]` free camera, `[L]` measure field mass now, `[R]` restart, `[C]` run the scripted battery |

**The Playground is the measuring bench.** It is where a new system is tried before it goes into the
game, and it builds its own world by code: lanes, dummies, ramps and a disposal machine. (It used to
also place a bucket and a wheelbarrow; both are cut — see §7.)

**A warning paid for in this project:** the Playground and the level each build the world, and the
**nine jobs they both did** are where bugs hid. The specific one that cost the most: **the disposal
machine's payout arithmetic lived in both files and the copies had already drifted apart** — the test
scene's copy had a null guard the level's did not. A job that must be done in two places is a job
that will be done differently in one of them.

---

## 13. Audio

Procedural and file-based, requested by name.

| Group | Files |
|---|---|
| Steps | `snow_step_N.ogg`, `concrete_step_N.ogg`, `SnowWalk.ogg`, `SnowWalk2.ogg` |
| Shovel | `shovel_scrape_N.ogg`, `shovel_dig.ogg` |
| Thuds | `snow_thud_N.ogg` |
| Loops | `snowblower_loop.mp3`, `wind_loop.ogg`, `salt_pour.ogg` |
| Generated | coin, victory, and general WAV synthesis |

**Design note:** the machine exists without a model because it can be **heard** — a motor under load
and the thud of snow landing in a box. The same principle applies elsewhere: **sound is doing
narrative work in this game**, so it should not be an afterthought.

---

## 14. Verification — the rules that cost the most to learn

This is the part of the project most worth carrying over intact. **Most of the time lost went into
measurement, not into the game.**

### The gate is the only measurement that counts

Every system has an **acceptance battery**: a script that launches the real game with a flag,
exercises the system in the live simulation, and **prints a verdict**: `RESULT: N OK / M FAIL`. A
runner executes them all and fails unless every one passes.

| Battery | Flag | Expected |
|---|---|---|
| Save slots | `--save-roundtrip` | 34 |
| Ball shape | `--ball-shape` | 8 |
| Translations | `--i18n-check` | 17 |
| Diagnostics safety | `--diagnostics-harmless` | 71 |
| Movement | `--movement-lab` | 11 |
| Ball impacts | `--impact-lab` | 18 |
| Impact matrix | `--impact-matrix` | 28 |
| Physics | `--phys-demo` | 36 |
| Playground | `--playground-check` | 11 |
| Dung beetle roll | `--beetle-roll` | 6 |
| Contact burst | `--contact-burst` | 4 |
| Hand packing | `--hand-pack` | 12 |
| Disposal machine | `--disposal-machine` | 22 |
| Cel shading | `--toon-shot` | 6 |
| Tool ownership | `--tool-ownership` | 37 |
| Reticle and aim | `--reticle-act` | 33 |
| Reticle needs close snow | `--reticle-aim` | 23 |
| Shovel load and push | `--shovel-modes` | 17 |
| Snow carving | `--carve-quality` | diagnostic; FPS floor |

**Total: 395 checks when green.**

### The rules, each learned the hard way

1. **A battery that hangs or aborts without a verdict is a FAILURE, not a skip.** A crash must never
   be mistaken for a pass.
2. **A battery that cannot prepare itself must report failure, not return in silence.**
3. **A battery must be able to say WHICH object it measured.** Measured: a trace that read
   positions out of a node group was following the **wrong ball** for several rounds, because the
   group returns the first one and the test had created another earlier. **A trace that cannot name
   its subject is not a measurement.** Keep the exact reference.
4. **Measure velocity, not only position.** Position tells you where something ended up; velocity
   tells you whether it was ever thrown at all.
5. **Read the value in the SAME FRAME as the action.** Reading a frame later showed half the speed
   and hid the cause for rounds.
6. **A phase that awaits needs a guard flag, set BEFORE the await.** An `await` inside a phase makes
   the dispatcher start a **new coroutine every frame it is suspended**. This bit three separate
   times and cost whole phases of checks.
7. **Do not sleep once and read once.** A process having exited does not mean the OS has flushed its
   redirected output. The runner read a perfectly finished battery as **"no verdict printed
   (crashed?)"** at least three times, because it slept 250 ms once — and this sent investigations
   toward two false causes. **Poll for the verdict.**
8. **Do not rely on the physics step's timing to cover an asynchronous effect.** Packing is a
   *request*: the field removes the snow and only then does the ball reach the hands. A fixed wait was
   enough alone and not always enough in a full run. **Poll for the outcome, with a budget.**
9. **Anything measured from a queued GPU operation is measuring the queue.** The value can be zero on
   the frame of the call and arrive frames later.
10. **Never derive mass from a whole-field integral.** See §2. Keep a ledger.
11. **Verify visuals in PIXELS.** Open the PNG, and report position and colour.
12. **A `[BUILD]` marker at startup.** Already covered in §11; repeated because it prevents a whole
    class of wasted round.
13. **Log every battery run**, one log per battery plus an error log, and count the script errors in
    it.

### The doc-test pattern

Prose documentation rots; a test does not. Where a rule matters, the current project writes it as a
**test that reads the source and fails if the rule is broken**. The clearest example: the portable
shovel-mode module has a check that **reads its own file** and reports if it names a scene. Without
it, "it is portable" is an intention; with it, it is a fact that can stop a commit.

**Carry that pattern over.** It is the cheapest way to keep a design decision true.

### One genuine platform fault, unresolved

`Vulkan device was lost` appears intermittently **only inside a full run** — a battery that passes
every time alone, reported as crashed or failing, **a different battery each run**, with the device
loss in its error log. It has hit the disposal machine, the physics battery and the movement battery.
A pause between batteries **reduces it and does not fix it.**

The working theory is **accumulated driver state from creating and destroying a device once per
battery, back to back**. **The next step is to reduce the GPU work a single battery queues, not to
lengthen the pause.** If the rebuild runs its tests as separate processes, this will recur.

---

## 15. Open threads, stated plainly

So the rebuild does not inherit them silently.

1. **Containers are cut, and the design should be read with that in mind.** See §7: the machine's
   `accept()` entry has no caller, the cost of transporting snow rests only on thrown balls and blown
   snow, and **nothing has been timed.** If carrying turns out to be too expensive in effort, that is
   a decision to revisit with numbers — not a reason to assume a container will reappear.
2. **The push-accounting lesson is worth adopting directly, whatever the object:** **measure from the
   code that knows, not from the world.** After four attempts to derive a shovel push's mass from the
   field — total before/after, the field's own carve ledger, and waiting for the ledger to stop moving
   — every attempt read the same **137 kg**, because the test's own setup was in the sum and the field
   only knows the sum. It was solved by counting the kilograms where they are removed.
3. **`Vulkan device was lost`** — see §14.
4. **`load()` inside functions**, 35 sites, mostly once-and-cached. Tidiness, not a defect, except
   on the level-start frame where decoration assets are read.
5. **The three `contents_changed` signals nothing connects to** — §7.
6. **The main game has never been measured.** The batteries are clean; **nobody has measured playing
   the game.** If crashes happen while playing, that is the gap.
7. **The economy has no income-per-minute number.** The loop has never been timed. Until it is, no
   price in the game means anything.

---

## 16. Assets

`docs/asset_licenses.md` records the licences. Any rebuild must keep that record truthful — a
licence is not a detail you can reconstruct later.

---

## 17. The working rules this project runs on

Not style preferences. Each one exists because its absence cost time.

- **Read a file before editing it.** And do not look for "the nearest `if`" — **read the block**.
- **Measure first, change one thing, measure three times.**
- **If a fix fails twice, stop refining it and try three different framings.** Four attempts at the
  same framing is where the money goes.
- **If a text replacement matches more than once, reject it.**
- **The gate is the only measurement that counts.** Never `--quit-after`: it killed batteries before
  their verdict, and that was mistaken for a project problem three times.
- **Never claim a visual fix from a parser result.**
- **A comment should record the MEASURED cause** — the number, the wrong version, and why it was
  wrong. That is what stops a rebuild repeating it.
- **State what is not done, out loud, in the commit.** The most expensive misunderstandings were
  about what "green" covered.

---

## 18. The five things most likely to be got wrong again

If a rebuild reads only one section, this one.

1. **The mass rule.** The field gives up a kilogram and the blade takes **all of it**. The rate
   limits the **cut**, never what the blade keeps. A factor applied *after* removal is an
   unaccounted deletion. *(Cost: 60 % of all shovelled snow, silently, in the shipped game.)*
2. **Gathering needs CLOSE aim.** One predicate, shared by the reticle and the pack, gated **before**
   anything is queued — or you get a hole with no ball. *(Cost: four attempts.)*
3. **The thrower must not collide with the ball it just threw.** It is held inside the thrower's
   capsule by construction. *(Cost: rounds of chasing aim and machine geometry, and the game's only
   income was unreachable by throwing.)*
4. **Payout is per KILOGRAM, on the running total.** `ceil` per delivery makes every fragment worth a
   coin, and then breaking a ball is a way to print money. *(Cost: 4× the declared rate.)*
5. **`set_anchors_and_offsets_preset`, and let the HUD own its own visibility.** *(Cost: the pause
   menu and the main menu, both reported by the owner as "not appearing".)*

---

*Compiled from the running build at commit `5eeb8ed`. Every figure was read from the code or from a
measured log, not from memory. Where a claim was never verified, it is written as a hypothesis and
labelled one.*
