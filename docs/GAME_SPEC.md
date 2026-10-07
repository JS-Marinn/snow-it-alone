# SNOW IT ALONE — Design & Technical Specification

**For: a new team, with no prior knowledge of this project.**
**Purpose: to design and build this game.**

You are being handed a fully-specified game design. Nothing here is a proposal — every rule, value
and behaviour in this document is a **decision that has been settled**, and most of them were
settled by testing alternatives and discarding them. The measurements that decided them are
included, because a number you can check is worth more than an instruction you have to trust.

**What this document does NOT say** is how to structure the code. No file layout, no class design,
no engine architecture. That is yours, and it should come from your own judgement about the tools
you are using.

**Language convention: code, comments, UI and all documentation in English.**

---

## 1. What this game is

**Snow It Alone.** A co-op snow-shovelling game. First person. **One or two players.**

The loop: snow falls and piles up; the player clears it with tools; the cleared area is progress;
delivered snow earns money; money buys better tools. It is a **labour game** — the satisfaction
comes from work becoming visibly done, and from a material that behaves like a material.

### The co-op rule, and it cuts both ways

**Build it as a co-operative game from the start, and make it perfectly playable alone.**

These are not in tension if the design is right, and getting them out of order is expensive — **a
co-op game retrofitted onto a single-player design is two games in one codebase**, and a
single-player mode bolted onto a co-op design is a mode nobody plays.

**So both are first-class, from the first day:**

- **Co-op first in the design:** division of labour is a design material. Two players can split a
  field, one can shovel while the other hauls, one can load while the other drives the machine.
  **Any mechanic that only one player can operate is a mechanic that halves in co-op** — decide
  deliberately whether that is intended.
- **Solo always in the design:** every co-op feature needs a solo answer — a way for one player to
  accomplish it, even if it takes longer. **A feature that is impossible alone is not a feature, it
  is a wall.**
- **The work scales, not the rules.** With two players there is twice the snow and twice the hands.
  **Do not resolve co-op by changing what a tool does** — the same shovel must behave the same way
  whether one or two people are holding shovels. Scale the *job*, not the *physics*.
- **Nothing may depend on a second player being present to be understandable.** If a player cannot
  tell what their partner is doing and why it matters, the co-op is decorative.
- **Test both, always.** Every acceptance check in §12 should be runnable in both configurations
  where the system touches cooperation. **A check that only ever ran solo does not prove the game
  works solo, and it proves nothing at all about co-op.**

**The safe anti-pattern to avoid:** designing for one player and "adding multiplayer later". By the
time it is added, every system has a single-player assumption baked into it — who owns the tool, who
gets the money, whose aim decides the pack. Those are cheap to decide now and very expensive to
change later.

### The one rule that produces most of the game

**Snow is mass, and mass is conserved.** Everything interesting follows from it:

- Shovelling does not destroy snow, it **relocates** it. Push it and it becomes a berm you must deal
  with later.
- Packing a ball takes snow out of the pack and puts it in your hands.
- **The disposal machine is the only true sink** — the only place snow leaves the world. Everything
  before it is rearrangement.

**Decide this explicitly before building anything: does mass leave the world anywhere else?** In this
design, it does not, and that is what makes the machine the destination of all work.

### The second rule: no assembly buttons

**There are no guided missions and no assembly buttons.** Four cooperating systems — the terrain, the
shovel, the balls, and physical assembly — produce the snowman, the wall or the sculpture as a
**consequence of the same rules**. Nothing is placed by a menu.

This is the heart of the design. If a feature can be replaced by a button that spawns the result, it
is the wrong feature.

### The third rule: the NUMBERS ARE YOURS, the INVARIANTS ARE NOT

This document contains a great many values — densities, rates, speeds, prices, thresholds. **Read
them as starting points, not as specifications.** They are recorded because they are known to work
and because a number you can check beats an instruction you have to trust, but **tuning them is
expected and encouraged**, and on several of them you are explicitly the designer.

**What is yours to plan and tune, freely:**

- **Progression and upgrade values** — how much better each tool becomes, what improvements cost, how
  long a level should take, how the difficulty of the work grows.
- **The snow's tuning** — how deep it starts, how fast it falls, how heavy it is to move, how quickly
  it settles, how much a shovel holds, how far a ball flies.
- **Economy numbers** — payout per kilogram, tool prices, anything about money.
- **Feel numbers** — movement speeds, throw speeds, carry penalties, camera behaviour, the weight of
  everything in the hands.

**What is NOT yours to change**, because it is an invariant the design rests on:

- **Mass is conserved.** Snow is relocated, never deleted, except at the disposal machine.
- **The mass the field gives up is the mass the blade receives.** The rate limits the *cut*; nothing
  scales what is kept.
- **Payout is per kilogram on the running total**, never per delivery.
- **Gathering requires close aim, decided by one predicate shared with the reticle.**
- **The snow's model structure** — the four channels, the two-phase angle of repose with hysteresis,
  cohesion as a real quantity. The *values* are yours; the *shape* of the model is what makes the
  game work.

### How the numbers should feel — the design target

**Comfortable and fun. Pleasurable to use. Nothing exaggerated.**

This is a labour game, and its fantasy is **satisfying work** — not power, not spectacle. That
points the numbers in a specific direction:

- **Effort is the content, but exhaustion is not.** Clearing snow should feel like *doing* something,
  and never like fighting the controls. If the player is fighting the interface instead of the snow,
  the numbers are wrong.
- **Restraint over drama.** Do not make a shovel lift a mountain, do not make a ball fly like a
  cannon, do not make money arrive fast. **The pleasure is in a job going well, and that pleasure
  needs room to exist** — it disappears the moment the work is trivial.
- **Improvement should be felt as relief, not as superpower.** An upgraded tool should make the same
  job *easier and smoother*, not make the job vanish. **The best upgrade is one the player notices
  they are no longer thinking about.**
- **Nothing should feel like a grind, and nothing should feel like a cheat.** Between those two is a
  band, and that band is the target.
- **When two values conflict, prefer the one that makes the moment-to-moment feel better**, because
  this game is played in the moment — there is no story to carry a bad minute.
- **Measure the feel, do not assume it.** The loop's income per minute, the time to clear a level,
  and the speed of each tool are all measurable, and §12 describes how. **A tuning change without a
  measurement is a guess**, and guesses are how a comfortable game becomes a tedious one.

*If you re-plan these values and something changes meaning, the invariants above are what must still
hold. That is the whole contract: **your numbers, these rules.***

---

## 2. The snow — the technique

> **This is a GPU heightfield-deformable-terrain technique with granular materials** — a texture-based
> heightfield simulated on the GPU, with material state per texel and a granular relaxation solver.
> The family is the one used by *Red Faction: Guerrilla* for destructible terrain and by *God of War*
> for snow.
>
> **Do not confuse it with two things whose names sound similar:**
>
> - ***Donkey Kong Country*** (Rare, 1994) is famous for **pre-rendered sprites produced on SGI
>   workstations** — computer-modelled imagery baked into 2D art. That is a rendering-pipeline choice
>   and has nothing to do with simulating a deformable material.
> - ***Donkey Kong Bananza*** (Nintendo, 2025) is a **voxel** engine — its world is voxels, and almost
>   everything in it can be destroyed. **This is genuinely a different technique from the one
>   specified here**, and the choice between them is a design decision this game has already made.
>   **Read §2.13 before assuming voxels would be better**, because for a snow-shovelling game they
>   very probably are not — and the reason is a limitation of the heightfield that must be accepted
>   knowingly rather than discovered later.

> **You are expected to IMPROVE this model.** The five specific failures that must be fixed are in
> **§2.14**, and **every improvement must be judged on PERFORMANCE first** — see §2.12.

> **The values in this section are starting points you may tune. The MODEL STRUCTURE is not** — the
> four channels, the two-phase angle of repose with hysteresis, cohesion as a real quantity, and the
> mass invariant. See §1, *the numbers are yours, the invariants are not.*

**This is the most important section. Read it before designing anything else.** The snow is not a
texture the tools paint on; it is a simulated material, and the model's structure is what makes the
rest of the game possible.

### 2.1 The representation: a heightfield with a material state

A **`RGBA32F` texture, 512 × 512, ping-ponged**, over the field. Four channels — and the choice of
what goes in each one **is** the model:

| Channel | Meaning |
|---|---|
| **R** | **Total height.** `1.0` means `snow_depth` metres |
| **G** | **Loose** — the movable fraction. **Only this part can flow** |
| **B** | **Cohesion / moisture** — modulates the internal friction angle |
| **A** | Relaxation scratch: `+scale` = the cell is at rest, `−scale` = the cell is flowing |

**The key idea: height alone is not snow.** The same height with different `G` and `B` behaves
completely differently. That is how dry powder and a packed path can look identical and walk
differently. **A model with only height cannot express this game** — it can show where snow is, but
not what kind it is.

**Mass conservation across the two-phase flow is a stated property of the system.** It is the
invariant the whole design rests on.

### 2.2 The angle of repose, with hysteresis

This is the granular rule that makes heaps behave like heaps.

- A cell **at rest** must exceed the **static** angle to start moving: `dynamic + hysteresis`, by
  default **32° + 8° = 40°**.
- A cell **already moving** settles at the **dynamic** angle, **32°**.
- **Cohesion raises both.** Dry snow (`B ≈ 0`) flows at **32°**; wet and packed snow (`B → 1`) holds
  up to **54°**.

**The two phases are why a pile keeps a definite shape instead of creeping flat.** A single angle
makes every heap melt into a shallow cone over time.

### 2.3 The compute modes — the material's whole vocabulary

Each mode is one dispatch. Together they are everything the snow can do.

| Mode | Function |
|---|---|
| 0 | **Blade collects** the snow under the plate. A `max_cut > 0` turns it into a **chisel**, which is how free sculpting works |
| 1 | **Blade deposits** its load in front of it, forming a heap |
| 2 | **Stamps**: boot print (sinks and compacts) and radial clearing (salt breaks cohesion) |
| 3 | **Dump**: injects free volume with a **conical profile**, flagged loose and wet |
| 4–5 | **Granular relaxation in two passes** (output scale, then transfer) |
| 6 | **Statistics, probes, and the volume removed per operation** |
| 7 | **Tamp**: flattens by diffusion and settles plastically by pushing mass outwards |
| 8 | **Harvest**: cylindrical mowing along a segment (accretion and sculpting) |
| 9 | The reduced **64 × 64 mirror** for gameplay queries |

**Mode 6 is load-bearing for design, not just telemetry.** "Volume removed per operation" is a
first-class output, and it is what makes exact mass accounting possible at all. Without it,
everything downstream has to estimate.

### 2.4 Gameplay must never read the full texture

Every frame the GPU writes a **64 × 64** summary — **mean height, mean loose snow, mean cohesion and
maximum height per block** — which the CPU reads **asynchronously**.

That mirror resolves: the player's support on heaps, the shovel's resistance, the rolling of balls,
and the pinning of objects. **Gameplay reads the mirror, not the 512² texture.**

**The mirror is quantised, and that has a design consequence:**

> A whole-field mass integral drifts by several kilograms while the things being delivered weigh a
> few kilograms. This is not an implementation detail — it means **"the total mass must not change"
> is not a usable rule at the scale of a delivery.**
>
> **Mass accounting must be a ledger** — an exact counter taken where the snow is removed, using
> mode 6's per-operation volume — **never an integral over the field.**
>
> And the flip side: **a small local change IS readable.** A 22 cm harvest disc resolves, even though
> the whole-field total cannot. **Measure locally, or keep a ledger.**

### 2.5 Resolution, and the aliasing trap

| Quantity | Value |
|---|---|
| Simulation texel | **1.56 × 2.34 cm** (512² over 8 × 12 m) |
| Snow mesh vertex spacing | **2.5 cm** (`mesh_subdiv_x/z` = 320 × 480) |

**The two grids do not match**, and sampling the map raw produces **aliasing**: the edges of
collected snow come out in **dark "teeth" with inverted normals**.

**The rule:** rendering must read the map through **one filtered sample whose radius is derived from
the actual mesh subdivision**, and **displacement, colour mask and normals must all use that same
filtered value**, so geometry and lighting agree and edges stay clean.

Four settings that fix specific artefacts, worth adopting:

- **A narrow snow→pavement mask** — `smoothstep(0.010, 0.060, h)` — for a clean edge.
- **Softened SSAO** (radius 1.15 · intensity 0.85); full strength darkens the bottoms of hollows.
- **Lighter pavement** (wet slate), so snow contrast does not turn every irregularity into a black
  patch.
- **The viewmodel casts NO shadow.** Shovel plates are very thin, and with a low sun the shadow
  stretches into a blue "needle" over the snow.

### 2.6 The public API the technique exposes

`dump_snow(pos, kg, radius)` · `tamp(pos, radius, strength)` ·
`request_harvest(owner, from, to, radius, depth)` ·
`carve_shovel(pos, dir, width, length, max_cut_m)` · `get_height_at(pos)` ·
`get_support_snow_height(pos)` · `get_cohesion_at(pos)` · `get_loose_fraction_at(pos)`

**`carve_shovel` must return what it removed.** That is the hook mass accounting hangs on. **Its
value comes from a probe and has latency — it can be zero on the frame an operation is queued**, so
anything measuring mass must account for the queue, not just the call. See §2.8.

### 2.7 Bodies on snow: a spring along the terrain normal

Objects do not collide with a snow mesh. They ride a **spring-damper along the terrain normal**,
critically damped, with a rest penetration of about **2.4 cm**, and friction applied to the **actual
sliding at the contact point** so the torque produces **pure rolling** instead of braking the body.

| Constant | Value |
|---|---|
| `SUPPORT_STIFFNESS` | 400.0 |
| `SUPPORT_DAMPING` | 40.0 |
| `CONTACT_FRICTION` | 0.85 |
| `NORMAL_SAMPLE_OFFSET` | 0.16 m |

**Two rules that go with it, and both are load-bearing:**

- **A body riding the spring must NOT also collide with the terrain**, or it is supported twice and
  the pair of supports is unstable.
- **Every body uses the same block with the same dampings.** Two bodies of the same weight in the
  same snow must behave the same, or the player feels the difference and cannot explain it.

### 2.8 How the snow is built at runtime

The field is **manufactured out of the same operations the tools use**. This is deliberate: it means
a surface cannot come to mean something the real tools would not produce.

**The field's defining properties** — everything about a level's snow comes from four numbers:

| Property | Meaning |
|---|---|
| `field_width` / `field_length` | Metres, across and along |
| `snow_depth` | How deep a full pack is, in metres |
| `snow_density` | Kilograms per cubic metre |

From those the field computes its own budget:

```
total_snow_kg = field_width × field_length × snow_depth × snow_density
```

Progress is reported the same way: cleared pixels over total pixels, scaled by `total_snow_kg`.

**The initial state** is **packed virgin snow**: compaction `G = 0` (immobile) with a **slight
cohesion**. Not powder, not cleared — the undisturbed pack a fresh level begins with.

**Building a surface** means queueing operations. A worked example — four test lanes 0.6 m apart
along a run, each demonstrating one material state:

| Lane | Built with | Parameters |
|---|---|---|
| **virgin** | *nothing* | It is the untouched pack |
| **packed** | `tamp` | radius 0.5, strength 1.0 |
| **shovelled** | `carve_shovel` | forward `(0, 0, 1)`, blade 0.9 × 1.2 m, depth 0.4 |
| **deep** | `dump_snow` | 70 kg per step at radius 0.45 |

**THE RULE: feeding the simulation too fast DROPS operations silently.**

> **Measured:** the operation buffer is small, and when it is fed too fast the operations that are
> dropped are **always the last of each batch**. This was found by watching **carves disappear while
> the tamps and dumps around them survived** — the carve was queued last in each group.

**So construction must be deferred across frames, not run in one go:**

- Queue operations as **deferred calls**, not immediate invocations.
- Drain a **small fixed number per frame** — **2** is the value in use — and accept that building a
  large surface takes many frames.
- **Order matters within a batch**, because the last entries are the ones lost. Put the operations
  you cannot lose first.

**Treat the operation buffer's size as a design constraint, not an implementation detail.** It is why
a level cannot simply "be built" in a single frame, and a team that assumes otherwise will get levels
that are consistently wrong in the same way — which reads like a design choice rather than a bug.

**A level's life cycle follows:**

1. The level starts as packed virgin snow at the configured depth and density.
2. A builder queues operations to shape it — lanes, banks, piles, a cleared path.
3. The simulation drains the queue, a couple of operations per frame.
4. **The snow settles** (`SETTLE_TIME = 2.5 s`) before anything measures it.
5. **Gameplay operations join the same queue** — a shovel push is just more operations.

**Two consequences of point 5:** anything that measures the field must wait for the settle, and a
test that clears a surface and then measures what a tool does to it is **measuring the same queue**.
See §12.

### 2.9 Snowfall

Continuous deposition with a falloff (`DEPOSIT_LAMBDA = 0.16`, `DEPOSIT_LENGTH = 0.70`), so drifts
build where you would expect.

### 2.10 The numeric envelope

| Property | Value | Meaning |
|---|---|---|
| `TEX_SIZE` | 512 | Simulation grid |
| `COARSE_SIZE` | 64 | The CPU mirror, the only thing gameplay reads |
| `MAX_OPS` | 12 | Field operations per frame — **a hard budget, see §2.8** |
| `BUCKETS` | 192 | Sideways pressure-transfer buckets for relaxation |
| `RELAX_ITERATIONS` | 8 | Relaxation iterations per frame |
| `SETTLE_TIME` | 2.5 s | Time for disturbed snow to settle |
| `RELAX_RATE` | 0.08 | Relaxation rate |
| `TAMP_SETTLE` | 0.03 | Height change from a tamp |
| `TAMP_COMPACT` | 0.85 | Compaction factor from a tamp |

### 2.11 The four surface classes

Surfaces are classified by **cohesion and height**, and the classification drives player speed:

| Surface | Recognised by | Player speed |
|---|---|---|
| Cleared | height below ~0.03 m | fastest |
| Packed | cohesion ≥ 0.45 | fast |
| Snow | cohesion ≥ 0.35 | baseline |
| Powder | untouched dry snow | slowest |

Reference points: **untouched dry snow sits near cohesion 0.20; a tamped strip near 0.68.**

### 2.12 PERFORMANCE — a first-class requirement, not an optimisation pass

**Improve this model, and judge every improvement on performance first.** A snow simulation is a
per-frame cost paid on every frame forever, and a technique that is elegant on paper and slow in a
full field is not an improvement.

**The budget is not a suggestion: the game must hold its frame rate on the target machine with the
field in its worst state** — mid-avalanche, several bodies riding the snow, two players, snow falling,
and the machine running. "It runs fine in an empty field" is not a measurement.

**The concrete rules that fall out of this:**

- **The simulation grid is a resolution/quality dial, not a constant to defend.** If a lower
  resolution still feels right at full field, take it. **Feel is the requirement; the number is a
  variable.**
- **Gameplay must read the small CPU mirror, never the full texture** (§2.4). This is already a
  performance rule as much as an accuracy one — a full-texture read stalls the CPU against the GPU.
- **There is a hard operation budget per frame** (§2.8). Exceeding it does not slow things down, it
  **silently drops work** — the worst kind of performance bug, because the game keeps running and
  quietly loses what the player did.
- **Relaxation is the expensive part.** Iterations and the active-region concept exist to bound it:
  **only relaxed where something was disturbed, and only as many iterations as the look requires.**
  An always-on full-field solver is the classic way this technique becomes unshippable.
- **Mesh resolution follows the simulation's, not the other way round.** The two grids must be chosen
  together, or the filtering that fixes aliasing (§2.5) costs more than it should.
- **Measure before and after, every time, and record the number.** A change to the physics with no
  frame-time measurement is a guess — and this is the single easiest place in the project for a
  "small" change to halve the frame rate.
- **Keep the cost visible.** A performance counter for the simulation (frame time, relay/dispatch
  cost, active region size) should exist from early on, because the day it is needed is not the day to
  build it.
- **The same applies to the bodies**: the number of balls and chunks alive at once is a design
  budget, not just a physics question. **Cap it deliberately and give the player a visible
  consequence** (chunks dissolving and reabsorbing is that mechanism — use it rather than letting the
  count grow).

**And the constraint that must not be traded away:** performance work may change *resolution,
frequency and iteration counts*, and must **not** change the **invariants** — mass conservation, the
mass rule of §4.3, or the model's structure. **Make it cheaper; never make it lie.**

### 2.13 Heightfield versus VOXELS — the choice, and the price of it

The obvious question on reading §2 is: ***Donkey Kong Bananza* destroys everything with voxels — why
not do that?** ([Nintendo's own account of the voxel work is worth reading](https://www.nintendo.com/au/news-and-articles/ask-the-developer-vol-19-donkey-kong-bananza-chapter-2/).)
It is a fair question and it deserves a real answer, because **this design has already chosen, and
the choice has a cost that must be accepted knowingly.**

**A heightfield stores ONE height per position `(x, z)`.** A voxel grid stores a volume, and can
therefore express **full 3D shape**: overhangs, tunnels, caves, and material suspended above empty
space. The practical difference:

| | **Heightfield** (this design) | **Voxels** (Bananza's family) |
|---|---|---|
| Shape it can express | A surface. One height per column | Anything, including overhangs and voids |
| Digging a tunnel | **Impossible** — you can only make the surface lower | Natural |
| Collapse / cave-in | **Not representable** | Natural, and a whole gameplay system |
| Memory | Small and fixed: one texture | **Scales with volume**, and is the defining cost |
| Per-frame simulation cost | Bounded by a fixed grid; cheap and predictable | Far heavier, and the hard problem is keeping it stable |
| Shader complexity | One texel, a few neighbours | Neighbourhood volume, meshing, and streaming |
| **What the player can do to it** | **Shape the surface: dig, push, pile, flatten, carve** | **Remove and destroy arbitrary material** |

**So the trade is stark and simple: a heightfield buys predictability and cost, and pays for them with
everything below the surface.**

**Why this game takes the heightfield:**

- **Snow is a surface material.** Snow falls from above, piles up, and is cleared from above. It does
  not form caves, and a snow tunnel is not a thing the fiction wants.
- **The core verb is SHAPING, not DESTROYING.** The player digs, pushes, piles, flattens and carves.
  All of those are surface operations, and all of them are cheaper and more stable on a heightfield
  than they would be on voxels.
- **Mass accounting is exact and simple** (§2.4): one value per column, and the ledger follows from
  it. In a voxel world, "how much snow did that push move" is a volumetric question.
- **Performance is a stated requirement** (§2.12). A heightfield's cost is fixed by the grid; a voxel
  world's cost is a problem to be solved continuously.

**What this design therefore CANNOT do, and must not be asked to:**

1. **No tunnels, caves or overhangs in snow.** If a level design calls for digging into a hillside and
   emerging on the other side, **that is a mesh problem, not a snow problem** — build it as static
   geometry that the snow surface sits on top of.
2. **No structural collapse of snow.** A roof of snow falling in is not representable. **Do not design
   a mechanic that depends on it** without changing the technique.
3. **Underneath an overhang, the heightfield still has a value.** There is no "empty" — a column has a
   height, and geometry above it is scenery. **This is the single most common source of confusion when
   mixing heightfield snow with arbitrary level geometry**, and it should be stated in the code.

**If a future design genuinely needs any of those three, the response is not to change the snow
technique — it is to reconsider whether the design needs them.** A game can be built around shaping a
surface for years. **A game built on both would pay for both.** And if the decision is ever revisited,
it should be revisited **early and with a measured prototype**, not by accreted exceptions on top of a
heightfield.

> **A note on combining them:** some games use a heightfield for the ground and voxels only where
> destruction matters. **That is a legitimate option and an expensive one** — two material systems mean
> two sets of rules, two collision paths, and two ways for mass to be lost. **It is not a free upgrade
> and should not be adopted casually.**

### 2.14 THE FIVE PHYSICS FAILURES THE NEXT BUILD MUST FIX

**These are the things the previous implementation got wrong, described from the player's side and
then located in the code.** They are the **first work item on the snow**, not a polish pass, and the
whole reason §2.12 says performance must be judged without letting the physics regress.

**The rule that ties all five together, and should be written into the code:**

> **NO OPERATION MAY REMOVE MASS WITHOUT AN EXACT ACCOUNT OF WHERE IT WENT.**
>
> Every removal is either **held** (in a blade or a hand), **relocated** (dumped somewhere as snow),
> or **delivered** (into the machine). Anything else is a deletion, and **a deletion is a bug even
> when it looks like the feature working** — because it is invisible, it accumulates, and it is the
> single hardest class of defect to find once the game is large.

**And the corollary, which is a gameplay requirement rather than an accounting one:**

> **A tool's verb must match what the player sees.** A blower that visibly deletes snow is not a
> blower; a pile with the wrong silhouette is not a pile. **The accounting above keeps the mass
> honest; the silhouette is what tells the player the mass is being moved rather than destroyed.**

#### Failure 1 — THE BLOWER DELETES THE SNOW instead of blowing it

**Reported:** *"the blower, instead of blowing the snow, makes it disappear completely."*
**This one is not an impression. It is measurably true.**

**What it does now:** the blower calls a **radial clearing operation centred on the aim point** — the
same primitive used for scattering salt. That primitive **removes a disc of snow and returns the
kilograms it removed**, and the blower does nothing with most of them. Snow chunks are spawned **only
30 % of the time**, and each chunk carries **only 30 % of the removed mass**:

```
kg_removed = carve(aim, radius 1.05, depth 0.40)     # removed from the field
if randf() < 0.30:                                   # 70 % of the time: nothing at all
    chunk.kg_weight = kg_removed * 0.30              # and even then, only 30 % of it
```

**So on 70 % of the ticks the snow is simply gone, and on the other 30 % about 70 % of it is still
gone.** To a player holding the trigger, that is a machine that erases snow, and **it is the correct
description of what the code does.**

**What a snow blower must do:** **take snow in at the intake and put the SAME MASS out through the
chute, in a visible stream, at speed.** Every kilogram the intake removes must appear as **flying
mass** — chunks, a stream, or a deposit where it lands — and when it lands it must **become snow
again**. The blower is a **transport** tool, never a sink.

**The design questions this raises, and they should be answered deliberately:**

- **Does the blower throw, or does it deposit?** A real blower throws over a distance. **Throwing is
  better here**, because the arc is visible, the accumulation is somewhere the player chose, and it
  keeps the machine's monopoly on deletion.
- **Does it sweep or does it point?** A real blower takes what its intake can reach as the player
  walks. **A radial carve at the aim point means the player aims at a spot and deletes a circle**,
  which does not match the fiction.
- **What happens to what it throws when it lands?** It must **rejoin the field as snow**, with its
  mass counted, and it must be placeable somewhere that matters — onto a bank, into the machine, or
  onto a pile the player will have to deal with.
- **Where does the mass come from, and does the intake have a shape?** The intake should have a
  **footprint and a capacity per second**, so the blower is a rate, not an event.
- **And it must respect the same aim rule as the shovel** (§4.5): a blower pointed at nothing blows
  nothing, and a blower pointed at the sky must not reach into the ground.

**Acceptance criterion:** *point the blower at a heap and hold. The heap loses mass, and an equal
mass is observably thrown and lands and rejoins the field. **The field's own mass ledger is
unchanged except for whatever ended up in the machine.** If either half of that sentence is false,
the blower is deleting snow.*

#### Failure 2 — THE SHOVEL PUSH DOES NOT FEEL LIKE SNOW

**Reported:** *"the shovel pushes it in a way that does not feel like snow."*

**What it does now:** the push **removes** snow (`carve_shovel`) and then **adds it back as a fresh
deposit in front of the player**. Two separate operations, and neither of them is a push. The result
is that the player **deletes a shape and spawns a shape**, rather than **shoving a mass**.

**What is wrong with that, and why it is felt:**

- **A real blade moves a CONTINUOUS FRONT.** The snow in front of the blade is not deleted and
  recreated — it is **shoved**, and the shove is resisted by the snow already there.
- **Snow is heavy and sticky.** A blade full of snow **slows the player down**, and the resistance
  **grows as the front grows**. Right now the work is done by the carve, so the *shoving* has no
  weight.
- **Snow spills.** When the front gets taller than the blade, **it should spill off the ends and over
  the top** — that is the shovel's whole vocabulary, and it is what makes a push strategic.
- **The pile must build where the blade goes**, continuously, not appear as a lump at the moment of
  the carve.
- **The player should feel the pile resisting.** Pushing into a tall drift must be **harder than
  pushing into a shallow one**, and that difference must be felt in movement, not only read in a HUD
  number.

**What is probably the right model, to be prototyped rather than assumed:** **treat the blade as a
moving wall that displaces snow rather than removing it** — a **directional** volume transfer along
the blade's facing, with the displaced snow going into whatever is in front, **spilling when it
cannot go anywhere**. Only the **residue that sticks to the blade** (§4.2) is actually *taken*, and
that is the only removal in the whole interaction.

**Acceptance criterion:** *push a full blade into a drift and the drift **moves ahead of the blade**;
the total mass of the field plus the blade is unchanged; and the player's speed drops as the front
grows. **Then push until the front is taller than the blade, and watch snow spill off the sides.**
None of those three is true today.*

#### Failure 3 — PILES ARE CONES INSTEAD OF THE EXPECTED SHAPE

**Reported:** *"the mounds of snow have a conical shape instead of the expected one."*

**What it does now:** the dump operation **injects free volume with a CONICAL profile.** That is
literally in the operation's own description (§2.3, mode 3). **A cone is a shape no real snow pile
has**, and the reason a real pile is not a cone is the same rule that governs everything else here:
**the angle of repose with hysteresis** (§2.2).

**What a snow pile should look like instead:**

- **A rounded, slumped dome with a broader base** — the profile of a material that has partly flowed
  and then stopped, not a straight-sided heap.
- **It should depend on how the snow arrived.** Dumped wet snow **slumps** and spreads. Thrown snow
  **piles steeper** where it lands and spatters outward. **Pushed snow forms a BERM with a ridge
  along the blade's path**, not a mound.
- **It should depend on what is underneath.** Snow landing on packed ground spreads; snow landing on
  deep powder builds differently.
- **The peak should not be a point.** The top of a real pile is a rounded plateau, and the sides near
  the top fall away faster than near the base.

**The likely cause is that the dump primitive bypasses the repose solver** — it injects a profile
directly instead of **adding mass and letting the angle-of-repose relaxation decide the shape.** If
that is so, **the fix is not to draw a better cone; it is to stop drawing a shape at all** and let
the granular rules produce it. That is also the design intent of §1's "no assembly buttons": the
form should be a **consequence** of the rules.

**Acceptance criterion:** *dump a bucket-sized mass onto flat snow and let it settle. The result is
**not a cone** — it has a rounded top and a slumped base — and its silhouette is **reproducible**,
because it comes from the same repose rule every time. **Then do it on powder and on packed ground
and get visibly different piles.***

#### Failure 4 — MASS DISAPPEARS IN OTHER PLACES TOO, AND NOBODY IS WATCHING

The blower is the worst case, but the same shape of defect — **an operation that removes and does not
account** — is the most likely thing to be wrong **everywhere**. **So the guard must be a rule, not a
fix for one tool:**

- **Every removal route increments a ledger** (§2.4), and the ledger says **which tool** did the
  removing.
- **A check exists whose only job is to prove the ledger closes**: total removed equals total held
  plus total delivered plus total re-dumped, within a stated tolerance.
- **That check runs on the whole game, not per tool**, so a new tool cannot be added without being
  caught.
- **A removal with no destination is a failure at the moment it happens**, in a debug build, with the
  tool's name in the message.

#### Failure 5 — THE PHYSICS IS NOT FELT, ONLY COMPUTED

Underneath the three reported symptoms there is one theme: **the simulation computes a result and the
player does not feel the process.** The shovel deletes and re-creates; the blower deletes; the pile is
drawn rather than formed.

**So the goal for the snow physics is not accuracy for its own sake — it is that the player can feel
the material through the controls.** Concretely:

- **Resistance that varies with what is being moved** — depth, weight, and cohesion.
- **Momentum in the material**: a pile that is shoved keeps going a little and settles.
- **Spilling and slumping as visible, predictable events**, not as a shape that was already there.
- **A delay between cause and result that matches the material's weight** — snow is not instant.

**And the constraint that keeps this from becoming a physics project with a game attached** (§1): the
verbs are **shaping** and **moving**, and they must all remain **comfortable and fun.** **If a more
accurate model makes the game less pleasant to play, the accurate model is wrong.**

---

## 3. Movement

> **Tuning values, not specifications.** These are recorded because they are known to work, and they
> are yours to plan and re-tune freely. See the design target in §1.

First person, momentum-preserving. The feel is deliberate: walking should be fast, jumping should
reward skill, and snow should slow you without ever becoming a drag.

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

### Acceptance criteria — these are the design, not tuning notes

- **Walking reaches a sensible speed; sprinting clearly beats it.** Reference: walk ~3.57 m/s mean,
  sprint ~5.78 m/s mean.
- **Letting go stops the player in under half a second.**
- **Hopping in a straight line gains nothing** (~5.78 m/s, same as sprint). **An air strafe DOES gain
  speed** (~12.72 m/s). **Bunny-hopping is an intended skill, not an exploit** — the ceiling comes
  from `chain_window` × `bhop_cap_factor`, not from banning it.
- **The surface changes your speed.** Measured on packed ground: 4.41 m/s, against slower powder.
- `auto_bhop` and `auto_bhop_min_speed` exist as options, **default off**.

### One design question to settle

Whether the player's facing is ever **externally forced** (pinned by a system rather than by input).
It is worth deciding explicitly, because a system that can rotate the camera will fight the player
and every movement test built on it.

---

## 4. The shovel

> **Tuning values, not specifications.** These are recorded because they are known to work, and they
> are yours to plan and re-tune freely. See the design target in §1. **The mass rule in §4.3 is the
> exception: that one is an invariant.**

The default tool, and the one with the most design behind it. **It has three verbs.**

### 4.1 Two modes; the new one is the design

The shovel supports a **legacy mode** (left button pushes *and flattens*; right button pours and
tosses) and the intended mode, **LOAD_AND_PUSH**.

**LOAD_AND_PUSH is the design.** Three verbs, three bindings, no ambiguity:

| Verb | Binding | Behaviour |
|---|---|---|
| **Push** | LEFT (`shovel_push`) | Drives a front of snow forward **and picks up a residue while doing it** |
| **Release** | RIGHT (`shovel_load`) | Empties the blade where it is pointed, in one go |
| **Tamp** | `shovel_tamp` | **Not reachable in this mode.** Pressing does nothing — no effect, no message |

**In LOAD_AND_PUSH there is no throw.** The mode already has a way to move snow (the push), so it
does not need a second way to throw it; the right button frees the load instead.

### 4.2 The residue, and why it exists

**A real shovel dragged along the ground does not come up empty.** Something stays on the blade.
It is also what gives the player a reason to push rather than only to load.

| Constant | Value |
|---|---|
| `PUSH_RESIDUE_FACTOR` | **0.25** — the residue is a quarter of the deliberate load rate |

**Verified behaviour:** pushing feeds **8.50 kg/s** against a declared residue of 8.50; deliberate
loading feeds **34.00 kg/s**; the blade takes **17.000 kg in 2.00 s**, exactly 8.5 × 2.

### 4.3 The mass rule — the most important line in the codebase

**The mass the field gives up is the mass the blade receives.**

The correct order of operations:

1. Decide how much the field may give up this frame: `allow = min(fill_rate × delta, room)`, where
   `room` is how much the blade can still hold. **The rate limits the CUT.**
2. In LOAD_AND_PUSH, scale `allow` by `PUSH_RESIDUE_FACTOR`. **Scaling what is cut is where a
   "pick up less" rule belongs.**
3. If `allow` is ~0, **cut nothing at all.** A full blade must stop taking snow out of the world, not
   remove it and drop it.
4. Take everything the field returned.

**Why this is stated so emphatically.** The obvious implementation is to subtract the snow from the
field, then apply a factor to what the blade keeps:

```
field loses kg_cut  →  blade receives kg_cut × 0.4     ← WRONG
```

That leaves **sixty per cent of the snow destroyed with nothing accounting for it** — silently, every
frame. It was measured as a **763 % mass-ledger error**. Two related traps in the same block:

- **A per-frame floor distorts a rate.** `+ 0.35` per frame is 21 kg/s. With it, pushing fed
  **12.49 kg/s** against a declared 8.50.
- **"The shovel does not fill in one hit" is a rate-limiting requirement, not a multiplier.** It is
  satisfied by limiting the cut, which is the only version that does not destroy snow.

**A factor applied after the removal is an unaccounted deletion.**

### 4.4 Blade behaviour

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

**Two magnitudes, kept separate on purpose — this is a design decision, not a detail:**

- **Physical resistance** — `F = μ·N + cut_k·width·snow_h + m·a` (Newtons). Shown in the HUD and used
  to decide the **stall**.
- **Forward drag** — bounded by construction, so snow slows you down but **never turns walking into
  dragging yourself along**. Reference: an empty shovel in fresh snow ≈ **80 %** of speed; a full one
  (25 kg) clearing a 45 cm heap ≈ **58 %** (≈ 2.4 m/s).

**The jam rule: snow taller than `BLADE_WALL_HEIGHT` jams the blade, and a jammed blade takes
nothing.** The wall is the height of the shovel's side wall — above it snow spills over the edge
instead of being carried. **A jam is a property of the blade, not of a button**, so it applies to
the deliberate load and the pushing front alike. The player gets out of a jam by facing forward
(fine cut), dumping, or tamping.

**The attack angle is a mechanic.** Facing the ground, the blade bites the whole layer; held flat it
works like a **chisel** and lifts thin shavings. That is how free sculpting works, and it should not
be flattened into a single behaviour.

### 4.5 Aiming — gathering requires CLOSE snow

**This is a specification, and it is easy to get wrong in a way that looks correct.**

> **Gathering snow happens where the reticle is. Looking straight ahead, instead of down, must not
> gather snow.**

| Property | Value |
|---|---|
| `PACK_REACH_STRICT` | **1.3 m** |
| `PACK_MIN_KG` | 0.435 kg |
| `PACK_HARVEST_RADIUS` | 0.22 m |
| `PACK_HARVEST_DEPTH` | 0.10 m |

**The trap, stated plainly so it is not repeated:** the intuitive gate is *"the ray hit something"*
AND *"there is snow at the aim point"*. **Both pass while looking forward**, because looking forward
puts the aim point on the ground **metres away**, where there is plenty of snow. The missing
requirement is **distance**.

**Two rules that go with it:**

- **ONE predicate decides both the reticle state and the pack.** A reticle that says CAN_PACK while a
  tap does nothing — or a tap that packs while the reticle says OFF — is the bug class.
- **The door must close BEFORE anything is queued.** Gating the *queued* harvest instead produces
  **a hole in the snow with no ball**: mass leaving the world with nothing accounting for it. **The
  order of operations here is load-bearing.**

**Acceptance criteria:**

| Aim | Expected |
|---|---|
| Down at snow within reach | CAN_PACK; a ball of ~1.213 kg; a local hole of ~+0.0245 m |
| Forward along the ground | OFF; no ball; local height unchanged to within 0.0000 m |
| At the sky | OFF; no ball; no hole |
| Down at cleared ground | OFF; no ball; no hole |

### 4.6 Controls, and their design constraints

| Key | Action |
|---|---|
| W A S D / Shift / Space | Move, sprint, jump |
| Left click | Push / cut snow |
| Right click | Release the load (LOAD_AND_PUSH) |
| `Q` | Tamp / flatten and compact — **inert in LOAD_AND_PUSH** |
| `E` press | Pick up objects and balls · pack snow with the hands |
| `E` hold | Push a ball glued to the ground, without lifting it |
| 1 2 3 | Shovel / blower / salt || `R` / `ESC` | Restart level / release mouse |
| `H` | Show or hide the key help (starts hidden) |

**Bindings must be named actions, never button numbers written in code** — `shovel_push`,
`shovel_load`, `shovel_toss`, `shovel_tamp`, `interact`, `jump`, `move_*`, `sprint`, `toggle_cursor`
— so they can be swapped without touching logic. This is a requirement, not a preference: rebinding
is a shipped feature (§9).

### 4.7 The blower — a TRANSPORT tool, and it must not delete snow

**The design intent, in one line: the blower takes snow in at the intake and puts the same mass out
through the chute, visibly, at speed.** It is the tool for moving **volume quickly over a distance** —
the counterpart to the shovel, which is precise and laborious.

**A snow blower is never a sink.** The disposal machine (§6) is the only place snow leaves the world,
and that rule does not bend for a powerful tool. **A blower that deletes snow makes the machine
pointless and the mass ledger a fiction.**

**What the implementation must satisfy, and each line is checkable:**

| Requirement | Why |
|---|---|
| **The intake has a rate and a footprint** | It takes a limited amount per second over a shape, not a discrete bite. A blower is a stream. |
| **Everything taken is thrown** | A visible arc of chunks carrying **the whole removed mass**, not a fraction of it |
| **Everything thrown lands as snow** | Whatever lands **rejoins the field with its mass counted** (§2.9, §5.3's reabsorption) |
| **The throw is aimed and bounded** | A real blower throws a certain distance; the player chooses the direction, and where it lands is a consequence |
| **Nothing happens when pointed at nothing** | Same close-aim rule as the shovel (§4.5) |
| **It does not reach the machine for free** | Snow thrown into the machine is delivered and paid for, like anything else — that is a legitimate use and should be satisfying |

**Failure 1 in §2.14 is this exact tool going wrong, with the measured numbers.** Read it before
implementing, because the shape of the mistake — *remove, then spawn a fraction of it, sometimes* —
is the natural first implementation and it is wrong by construction.

**Tuning direction (§1's design target):** the blower should be **fast and loud and satisfying**, and
should make the player feel like they are **clearing ground**, not erasing it. It should be
**bad at precision** — that is the shovel's job — and **good at volume**.

**Open design question worth answering deliberately:** does the blower *sweep* as the player walks, or
does it act on the aim point? **A real blower takes what its intake passes over**, which pairs with
walking and makes the tool about **choosing a path**, not choosing a spot. Decide it, and make the
intake shape match the answer.

---

## 5. The snowball

> **Tuning values, not specifications.** These are recorded because they are known to work, and they
> are yours to plan and re-tune freely. See the design target in §1.

Packed snow is a rigid body that rides the snow. It is the most physics-heavy object in the game and
the carrier of most of the emergent behaviour.

### 5.1 Density, and the fact that a ball is NOT a pure R³

```
m = 4/3 · π · R³ · ρ(R)
```

**`ρ(R)` rises from 300 to 470 kg/m³ with size** — the snow compacts and expels air as it rolls.
**A ball therefore weighs more than its volume at constant density would suggest**, and that is the
mechanism behind "a big ball feels completely different from a small one".

| Density | Value | Meaning |
|---|---|---|
| `LOOSE_DENSITY` | 150 | Fresh snow |
| `PACKED_DENSITY` | 300 | Packed by hand |
| `PACKED_DENSITY_COMPACT` | **470** | Compacted, and the top of the `ρ(R)` curve |

| Property | Value |
|---|---|
| `MIN_RADIUS` / `MAX_RADIUS` | 0.07 m / 0.55 m |
| `SETTLE_TIME` | 0.30 s |

**Reference masses:** **2 kg at r = 0.12 · 32 kg at r = 0.28 · 73 kg at r = 0.36 · 266 kg at
r = 0.52.** Notice that 0.28 → 0.52 (under twice the radius) is **eight times the mass**, not four.

**Consequences that follow, and should be design decisions:**

- **Rolling resistance grows with the cube of the size.** A small ball rolls a long way; a giant one
  is stopped almost immediately.
- **Inertia comes from mass and shape**, so it updates itself as the ball grows.
- **The push is by FORCE, not acceleration**, so the same force moves a light ball a lot and a heavy
  one barely at all.
- **Throwing speed falls with mass on a SOFTENED exponent** (`v = 9 · (1.7/m)^0.30`) — not the 0.5 of
  constant energy, which would punish large balls too hard to be playable. Two-handed throws get
  ×1.8. **It never exceeds the light-ball speed: weight always costs.** Measured: **1.7 kg → 7.5 m/s
  versus 146 kg → 3.6 m/s** — a heavy ball is thrown **with force**, not left stuck.
- **No lift is added to a throw.** The arc is gravity's job: to throw far, aim up. (An added upward
  term once put a 7.5 m/s throw 25° over the crosshair and, inheriting the hand's motion, pushed it
  sideways.)

> **⚠ Resolve these two against your own build.** A reference document and the code disagree, and one
> of them is stale: the push force is either **260 N capped at 26 m/s²** or **380 N capped at
> 32 m/s²**; and the break threshold is either a flat **7 m/s** or a **tiered 2.5–5.0 m/s** by ball
> size. Do not carry either forward unchecked.

### 5.2 Accretion — how a ball grows, and the rule that keeps it clean

Every **12 cm travelled** the ball **mows a strip the width of its footprint** and absorbs the
**exact volume the simulation reports**, leaving the clean furrow behind:

```
R = ∛(R³ + 3ΔV / 4π)
```

**The mowing only joins points that were in continuous contact with the snowpack.** The anchor is
invalidated as soon as the ball is clearly in the air (thrown, falling, bouncing), and any jump
larger than `MAX_HARVEST_STEP` (**0.45 m**) re-anchors **without mowing**.

> **Why that rule is not optional.** Without it, landing after a throw **scratches a straight strip
> from the throw point to the landing point** — an unnatural "line" drawn across the snow. It is the
> most visible artefact this system can produce.

### 5.3 Breaking, and why mass stays closed

Above the break threshold a ball **breaks apart**, and the split is specified:

- **55 % of its mass returns to the snowpack at the impact point** (a `dump_snow`).
- The rest is a **shower of fragments** with scatter velocities, plus a powdered-snow cloud.
- **Chunks that lose their energy dissolve and reintegrate their volume** into the pack.
- **Rolling or falling gently does not break it.**

So **what was a ball becomes a heap plus chunks that are reabsorbed** — **the mass stays closed**,
which is the same invariant as everywhere else. Breaking must never be a way to delete snow, and it
must never be a way to **create** it.

**Breaking is tiered by size** — a small ball needs a harder hit. The three tiers:

| Tier | Radius | Minimum hit speed |
|---|---|---|
| Small | ≤ 0.18 m | 5.0 m/s |
| Medium | ≤ 0.34 m | 3.5 m/s |
| Large | > 0.34 m | 2.5 m/s |

**Only a hit that counts breaks the ball.** Breaking on any contact means a player simply walking
into a big ball resting on the ground destroys it, with nothing thrown and nothing recorded.

**Hook for final art, worth keeping:** fragments and the cloud are **provisional** (spherical chunks
and CPU particles). Assigning a pre-fractured scene to the fragment and puff slots makes the code
instantiate the real art, and **the rest of the system — mass, impulses, reabsorption — does not
change.** Design the seam now even if the art comes much later.

### 5.4 Carrying

| Property | Value |
|---|---|
| `carry_distance` | 1.15 m |
| `two_hands_mass` | 35.0 kg |
| `stagger_full_mass` | 150.0 kg |

**The design goal: staggering costs CONTROL, not speed.** A carrying player must never feel like they
are dragging themselves along.

- **Walking speed while carrying** is `1/(1 + mass/300)` with a **floor of 75 %**. At 17 kg that is
  95 %; at 124 kg, 75 %. Measured: **124 kg → 3.13 m/s, 74 % of normal.**
- **From 35 kg the ball is held with BOTH hands above the head**, anchored to the **body**, not to
  the view — so looking at the ground does not sink it.
- **Above that the player staggers**: oscillating lateral drift, less acceleration control and camera
  sway, proportional to `stagger = (mass − 35)/(150 − 35)`.
- **The grip runs out** at `0.05 + 0.22·stagger` per second; if it reaches zero **the ball slips out
  of your hands**, and the HUD warns from 30 %.
- **While carrying, the tools are stowed** — your hands are busy. This includes the **throw**: bare
  hands must be able to throw a ball they are carrying.
- **The grip adapts to size:** a hand-sized ball at ~0.7 m, a large one at ~1.3 m.

**`E` has three behaviours, and all three are design:**

| Input | Behaviour |
|---|---|
| **Short press on an object** | Pick it up — or **extract it** if it is pinned |
| **Press on snow** | **Pack** a ball: mass is mowed from the pack, and the ball is born **already in the hands**, at the carry point and in carry mode **in the same frame**, without falling to the ground |
| **Hold on a ball** | **Push it glued to the ground** — it stays a dynamic body on the snowpack, it never lifts, and the force is bounded, so heavier means harder |

---

## 6. The disposal machine — the only sink

The destination of all the work, and the game's only income.

**Real-world reference for the fiction:** a **two-stage snow blower fed on site, throwing snow up its
chute into a tipper truck**. In the real flow a loader brings it snow — **in this game the player IS
the loader**, which is why the machine stands still.

**No model is needed and none should be expected.** An interactable box with a collision shape and a
flat colour is correct. **Looking provisional is the point.**

### 6.1 The rules

Each line is a specification, not a description.

| Rule | Consequence |
|---|---|
| **Inert** | It never moves, never looks for snow, never aims |
| **Instant** | No queue, no timers, no internal state |
| **Never jams** | The only mechanic is: it goes in, it is gone |
| **Pays** | Through the same coin path as everything else. **No second currency** |
| **Accepts any snow** | Chunks and balls, any size |
| **Nothing but snow is swallowed** | A body that is not snow is refused, so no prop or tool is ever eaten |
| **Does not accept players** | **Explicitly, in code, not by collision-layer accident** |

**On that last rule:** the refusal must be a **written check with a comment saying why**, because
collision layers get edited by people in a hurry and a refusal written in code does not. The note to
leave in the source is essentially: *"one day someone will change the collision layers."*

### 6.2 Two entries, and why the split is the design

| Entry | What arrives | What handles it |
|---|---|---|
| **Reception zone** (an area) | Chunks and balls that fly in | Read the kg off the body, pay, free the body |
| **Explicit delivery** | Something not a loose body, handed over | The delivery action calls `accept(kg, position)` |

**The split means "loose snow is caught, and a deliberate delivery is deliberate" by construction:**
the zone cannot pick up something that is not loose snow because it does not collect those at all.

> **A decision to make explicitly.** In the design as handed to you, `accept()` has **no caller** —
> there is no carrying container in this game (§10). **Keep it as the documented extension point and
> label it as currently unused**, or drop it. What must not happen is an API with no caller that
> nobody labels as such, because the next person concludes the feature is half-built.

### 6.3 Three geometry and detection facts

**Both were found by measurement, and both are easy to get wrong:**

1. **The machine needs a REAL opening.** A solid collision box with the mouth drawn as a plate on its
   front means a thrown ball **hits the box and shatters on it** — measured: a **1.211 kg ball
   delivered 0.068 kg**. The body must be built as a **throat** (sill, two jambs, a lintel) leaving a
   real opening at the mouth's height and width. After that change the ball arrives **whole**, with
   no burst event at all.
2. **The reception zone must sit IN FRONT of the mouth, not at the body's origin.** Centred on the
   origin it is buried inside the machine's own collision box, and a thrown ball never reaches its
   middle.
3. **A fast body can cross an area between two physics steps.** Entry events fire on the *crossing*,
   and a ball leaves the hand at about 8 m/s — **13 cm per step**. The reliable test is the one asked
   **every frame**: poll what is inside the zone rather than wait to be told. **Keep a per-frame
   handled list so a body caught twice in one frame is not paid for twice.**

**Reference dimensions** (the design's own): `reception_radius` 1.1 m, `reception_height` 1.15 m,
mouth at `(0, 1.05, −0.65)`, machine body **1.70 × 1.50 × 1.20 m** centred at y = 0.75.

### 6.4 The invisible truck sells itself without art

Three things must exist, and **none of them needs a model**:

- **A visible output spout**, so it is clear where it spits.
- **A counter: "Snow sent: X kg."**
- **Readable state at a glance** — the player must be able to tell, without stopping, that the
  machine is working and roughly how much has gone in.

**All player-facing strings go through the translation table and `tr()`** (§9). Diagnostic output
stays English.

### 6.5 Placement

Two placements are part of the design:

- **In the test scene** (see §10) — the machine is a fixed feature there.
- **In a level: at one end of the field, beyond the banks.** The reasoning is geometric: with an
  8 × 12 m field whose bank collision is solid from x = 4.0 to 8.5 within z ±9, there is no reachable
  spot beside the banks, so the machine sits **past the end of the field**. Work out the equivalent
  for whatever level shape is used — the principle is **reachable, and not competing with the banks
  for the same ground**.

**Placement is a placeholder and should be labelled as one.**

---

## 7. The economy

> **These numbers are yours, and they are the ones most in need of planning.** The one genuinely
> missing measurement is **income per minute** (§12). See the design target in §1: **comfortable
> and fun, nothing exaggerated.**

**Every price in this design is a placeholder and should be marked as such in the code.** The number
that is genuinely missing is **income per minute**, because the loop has never been timed. Until it
is, no price means anything.

### 7.1 The sink that pays

| Fact | Value |
|---|---|
| The disposal machine is the only income | Snow destroyed by the machine |
| Declared payout | **`ceil(kg × 2.5)` coins per delivery** (`PAYOUT_PER_KG = 2.5`) |
| Rationale for 2.5 | Delivering snow across the field costs real time and effort. There is **no second payer to compare against**, so the machine sets the rate on its own |
| Worked example | A 25 kg delivery yields **63 coins** |

### 7.2 The banks do NOT pay

**The banks are scenery. They are not a snow destination and they do not pay.**

This is a settled decision, not an unfinished one. A second payer would split the loop and make the
machine pointless.

**The trap to avoid, and it is subtle:** a bank that still **answers the question "did snow land on
me?"** while paying nothing. If banks exist as scenery, decide **explicitly** what, if anything, "the
bank" means to gameplay. Otherwise it is a landmark that silently does nothing — and a landmark that
answers queries it should not is worse than one that is purely visual.

If banks return as visual features, that should be their whole description: a geometry-shaped place
where snow accumulates, because snow accumulates anywhere.

### 7.3 Payout must be per KILOGRAM, on the RUNNING TOTAL

**This is the most recent and most instructive economy rule. Read it before writing any payout.**

The machine emits **once per body it swallows**, and a thrown ball that breaks on arrival is many
small bodies.

```
WRONG:  coins = ceil(kg × rate)          per delivery
RIGHT:  coins = ceil(total_kg × rate) − already_paid
```

**Why the wrong version is wrong, measured:** with `ceil` per delivery, every fragment is worth **at
least one coin**. A ball broke into eight pieces; the machine took **0.546 kg** and paid **8 coins**,
where the declared formula says **2**. **Four times the rate — and the more a ball shattered, the more
it was worth**, which is exactly backwards. **Breaking snow must not be a way to print money.**

**Why the right version is right:**

- The declared rate is unchanged. **A price per kilogram means a price per kilogram.**
- **The per-delivery floor is the entire defect.** `ceil` treats every delivery as worth at least one
  coin, which is right for a whole load and wrong for a crumb.
- **It is marginally cheaper, to the player's benefit of the doubt:** 3.70 kg then 5.394 kg pays 10
  then 13 (**23 in all**), where rounding each delivery separately pays 14 and overpays by one.
- **It is deterministic and checkable:** coins paid are always exactly `ceil(total × rate)`.

**And the mass rule that goes with it:** every kilogram in the blade must have left the field, and
every kilogram that left the field must be in the blade. **Enforce it with a ledger** — an exact
counter where mass is removed — **never with an integral over the field** (§2.4).

### 7.4 Tool ownership

Tools are **owned or not**, and that gates their use. "Hands" are always owned.

**A design question to settle: does ownership belong to the save, or to the session?** If it lives in
the save, then "what tools does the player own" is answered by a file, which makes the player object
depend on persistence — and every test of the player has to manipulate a save to test it.

---

## 8. The player, and snow as an argument

Snow is not only a material; it is a physical argument between players.

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
tools** — that is a design rule, not an implementation detail.

**A ball to the face** blinds the player, and `E` wipes it off instead of doing anything else.

**A session mode decides whether thrown snow is a prank or just snow:** in a **Work** mode, a ball to
the face is **nothing at all**. That distinction is deliberate and must survive.

Balls recognise people through an **`impact_targets`** group, which is also what the disposal machine
checks to refuse a player.

---

## 9. Interface

### 9.1 One interface, every scene

**There is ONE interface, used by every scene.** This is not a style note.

> In an earlier version of this design the interface's node tree existed **byte for byte identically**
> in two scenes, node ids included, and a fix to one of them **did not reach the other** because of
> it. The user reported the missing feature as a bug. **Then the fix was to add another copy.**

**Design rule: a capability must not be able to exist in one scene and not another.**

### 9.2 What is on screen

| Element | Notes |
|---|---|
| Title | The level's name |
| Progress bar + percentage | Level completion |
| Snow removed (kg) | |
| Money | `Money: $N` |
| **Snow sent (kg)** | `"Snow sent: X kg"`, next to the money |
| Tool name | |
| Shovel load bar | |
| Toss hint | |
| Reticle | See below |
| Victory panel | Hidden until earned |
| Pause menu, settings, controls | See §9.4 |

### 9.3 The reticle — always visible, and verified in pixels

**The reticle is a dot at the centre of the screen, always visible, whose colour reflects state.**
States: **OFF** (dim), **CAN_PACK** (a ball can be gathered), **CAN_CARVE** (a tool can cut).

**Three defects this design exists to avoid, each one real:**

1. **A white reticle on white snow is invisible.** Measured: centre luma **0.96** against snow at
   **0.99** — **three per cent of contrast**. It was drawn, centred to the pixel, and **invisible by
   construction**, while every log said it was fine. **A dark dot on a light ring reads on snow** —
   and snow is where this game is played. Make the ring light so the dot also reads against something
   dark.
2. **A reticle whose existence depends on state can be absent for a reason nobody can see.** Show it
   in **every** state — dim when there is nothing to do, coloured when there is. If it should be
   hidden when idle, hide it **deliberately** and write down why.
3. **The reticle must agree with what pressing does.** See §4.5: **one predicate** decides both.

**The acceptance test must be in PIXELS.** "It compiles" and "the game loads" are not checks that
something is visible. **Write the viewport to a file, read it back, and compare the centre of the
screen against the snow around it.** Report contrast and colour. Reference readings: looking down at
close snow, dot at **(640, 360)** on a 1280 × 720 viewport with contrast **0.49–0.59**; looking
forward, same position, contrast **0.396**.

**A measurement trap worth knowing:** searching for "the darkest pixel within N pixels of the centre"
can report the **edge** of the dot rather than its middle, which makes a 5 px dot read as a 2 px
offset. Prefer a mass-centre or a bounding box, and state the criterion.

### 9.4 Pause, settings, controls

**The pause menu lives inside the interface, and the interface must keep running while the game is
paused** — it owns the menu, so being paused must not stop it reading the key that unpauses.

Contents: **Resume, Restart level, Settings, Quit to menu.** A controller must be able to drive it, so
the first action takes focus.

**Pausing must genuinely stop the world, and the test must check that it does** — the world's own
clock is the thing to verify, because a pause that only hides the world behind a panel would pass a
screenshot test.

**`ui_cancel` closes in order:** the controls panel, then the settings panel, then toggles the pause.

**Rebinding is a shipped feature.** Store **physical keycodes**. *A trap found here: a "Reset controls"
feature restored nothing because every shipped binding had `keycode == 0` while the describe step only
handled `keycode != 0`. **Bindings described and restored must agree about which key field they
mean.***

### 9.5 Two layout rules that are load-bearing

Both of these produced visible, user-reported bugs.

1. **The interface must own its own visibility.** A hidden container means every correct layout inside
   it is invisible. A screen that hides itself at startup is not a screen. If something needs to hide
   it, expose a **named method** rather than flipping the property from elsewhere.
   > Measured, as it went wrong: the pause menu was `visible = true` and drawn into a layer whose own
   > visibility was false. Pausing showed **nothing at all** — no menu, no interface — and the
   > reported symptom was "the game just stops". Worth knowing: **the flag was being cleared from
   > outside the interface's own code, and searching for the writer did not find it.** Make this
   > impossible by construction: the interface sets its own visible state, and nothing else does.
2. **`set_anchors_preset(FULL_RECT)` does not size a Control.** It sets the **anchors** and leaves the
   **offsets** alone, so a Control added to a `CanvasLayer` stays **zero by zero** and centres its
   children inside nothing — the panel lands at the top-left, off screen. **Use
   `set_anchors_and_offsets_preset`.** This mistake appeared in **six** places in one build,
   including the main menu's background and centre container — **the screen the game opens on.**

**Acceptance criterion for a centred panel:** its centre against the viewport's, reported in pixels.
Reference: menu rect `(510, 229)` size `260 × 261`, centre **(640, 359.5)** against a viewport centre
of `(640, 360)` — **off by one pixel.**

### 9.6 Translation

- **All player-facing strings go through the translation table and `tr()`. Diagnostic output stays
  English.**
- `locale/strings.csv` holds keys with an English column and a pseudo-locale column.
- **The pseudo-locale is generated, not typed**: accented vowels, bracketed, and **padded with `~` to
  at least 140 % of the English length**, so layout problems show up before a real translation does.
  *This is the cheap way to find out that a button cannot hold a longer word.*
- **Print a build marker at startup** — `[BUILD] <short hash>`. **"Am I running the code I think I
  am?"** is a question that wastes whole days, and a screenshot cannot answer it. Write the hash into
  a file at build time rather than reading version control at runtime, so an exported build can say
  which commit it is.

### 9.7 Interface details that a professional build is expected to have

The items above are the load-bearing ones. **These are the rest of what a finished interface is
expected to cover** — treat this as a checklist, not an afterthought, because each of these is
individually small and collectively the difference between a prototype and a product.

**Moment to moment**

- **A crosshair or reticle state that never lies** (§9.3) — and no other indicator that duplicates it.
- **Immediate feedback for every action**: a press that does something must show *something* on the
  same frame — the load bar moving, a hit flash, a number changing. **A press with no visible
  response reads as a broken input even when the system worked.**
- **A refusal must say why.** "You cannot do that" is worse than useless. Every refused action
  (not enough snow, blade jammed, hands full, tool not owned) needs **a short, specific reason**, and
  it should be dismissible or self-clearing rather than modal.
- **Prompts for what is in reach**: when the player looks at something they can interact with, they
  should be able to tell. **Contextual prompts must not be spammy** — one prompt for the nearest
  candidate, not five overlapping labels.
- **A warning before a consequence, not after.** The grip warning at 30 % (§5.4) is the model to
  follow: **the player is told before they lose control of the load**, not after.

**Onboarding and discoverability**

- **Progressive disclosure of controls.** A player should be able to start without reading a manual,
  and the full control list should be available when they want it (and hideable; the help overlay
  starts hidden — §9.4).
- **Teach in context.** The first time a mechanic matters is when it should be explained — not in a
  wall of text before the level.
- **A solo player and two co-op players may need different explanations.** If a teaching step
  assumes a partner, it is wrong for half the sessions (§1).

**Menus and navigation**

- **Every screen reachable and exitable by keyboard, mouse and controller.** Not "mostly" — each
  panel needs a defined way in and a defined way out.
- **Consistent focus behaviour and a visible focus indicator**, since a controller has no cursor.
- **Sensible back behaviour**: `ui_cancel` walks outward one level at a time (§9.4), never dumping the
  player to the desktop and never trapping them.
- **A confirmation for anything destructive** (quit to menu, restart level, overwrite a save).
- **The main menu, the pause menu, settings and the level-complete screen all exist and all are
  reachable** — and each one is a screen the player will stare at, so none may be left as raw default
  styling.

**Settings, and the list is longer than it looks**

- **Display**: resolution, window mode, V-sync, frame-rate cap, brightness.
- **Graphics**: the quality level that drives the snow simulation's resolution and iteration counts
  (§2.12) — **this is a gameplay-relevant setting, so it must be adjustable and must not silently
  change the physics**, only its fidelity.
- **Audio**: master, and separate music and effects. **Include a mute and a volume of zero that
  behaves** (zero is a legal value, not a fallback to default).
- **Controls**: full rebinding (§9.4), plus reset to defaults, plus separate sensitivity for mouse
  and stick.
- **Accessibility**: at minimum a field of view slider, a subtitle/text-size option if text carries
  meaning, no colour-only signalling, and an option to reduce camera motion for players who need it.
  **This is a normal feature of a professional build, not a nice-to-have.**
- **Every setting persists** and is applied both at startup and the moment it changes.

**Failure states and edge cases**

- **Nothing may strand the player.** No unclimbable hole dug by the player's own shovel, no
  unreachable machine, no state where the only way out is to quit. If the game can be made
  unplayable by playing it, provide a way out (a manual respawn or restart level).
- **Pause must work at any moment**, including mid-anything (§9.4).
- **The interface must survive every state**: paused, carrying, staggered, victorious, empty, and
  loading. **A panel that assumes one state will be seen in the others.**
- **Window focus loss** must pause or otherwise not punish the player — alt-tabbing should not cost
  a level.

**Performance and polish**

- **No interface work in a per-frame loop that cannot justify it.** A label that changes rarely does
  not need rebuilding every frame (§2.4 has the same rule for the simulation).
- **No layout that assumes a specific resolution.** Every panel that is centred is centred, not
  offset by a hand-tuned number.
- **Transitions are short and skippable.** Loading, level start, victory.

### 9.8 Persistence — saves are a feature, and they must be frequent

**Save often, and save without the player asking.**

- **Autosave at every natural boundary**: level start, level complete, a purchase, and **every so
  often during play** — the interval is a tuning value, but there must be one. **Losing progress to a
  crash is a defect, not bad luck.**
- **Autosave must be cheap and invisible.** It must not hitch the frame, so it must not be doing
  expensive work synchronously on the game thread.
- **A save must be self-describing and versioned.** A save written by an older build must either load
  correctly or **fail with a clear message** — silently loading a mismatched save and corrupting a
  player's progress is the worst outcome available.
- **A visible, non-intrusive autosave indicator.** The player should be able to know their progress is
  safe without being interrupted.
- **Atomic writes.** Write to a temporary file and swap, so an interrupted save cannot destroy the
  previous one.
- **Keeping a previous save slot** is cheap insurance and worth it.
- **What must be in a save**: the player's tools and ownership, money, level progress, and any
  setting that is part of the world rather than the machine. **What must NOT be in a save**: the
  live snow field's simulation texture. **It is far too large to serialize, and it does not need to
  be** — a level is rebuilt from its initial state plus the level's durable progress. **Decide this
  early**, because "we will just save the snow" is a decision that kills a save system late.
- **Manual save and load** alongside the automatic one, in a slot UI that shows enough to identify
  each slot (a name or timestamp, progress, money).
- **Deleting a save asks for confirmation** (§9.7).

---

## 10. World and level layout

The design uses **two kinds of scene**, and the distinction is a working method worth keeping.

### 10.1 The test scene — the measuring bench

A development scene where a new system is tried **before** it goes into the game, with **every system
present and instrumented**.

**Its world is 10 × 40 m** and it contains:

| Feature | Detail |
|---|---|
| A run | `RUN_START = -18` to `RUN_END = 18` |
| **Four lanes**, at x | **-3.75 (virgin/powder) · -1.25 (packed) · +1.25 (shovelled) · +3.75 (deep)** |
| Training dummies | at z = 2, 10, 18 |
| Ramps | on the +x side at z = 4 and 12 — **geometry only** |
| A disposal machine | a fixed feature here |
| Debug keys | `[B]` spawn ball · `[N]` ball size 0.10/0.24/0.45 m · `[V]` free camera · `[L]` measure field mass now · `[R]` restart · `[C]` run the scripted check |

**The lanes are manufactured with the game's own field operations** (§2.8), which is what makes them
fair test surfaces: a lane cannot come to mean something the real tools would not produce.

**A warning from experience:** two scenes that each build a world will end up building it
**differently**. In one version the disposal machine's payout arithmetic was written out in both, and
the copies had **already drifted apart** — one had a null guard the other lacked. **A job that must be
done in two places is a job that will be done correctly in one of them.** Give shared work one home.

### 10.2 A level

| Fact | Value |
|---|---|
| Field | **8 × 12 m** |
| Snow | 32 cm of virgin snow |
| Bank collision | solid from **x = 4.0 to 8.5**, within **z ±9** |
| Decoration | a pine forest and a cabin |

**Placement principle for the machine:** reachable, and not competing with the banks for ground
(§6.5).

### 10.3 The physics design in its own terms

Worth quoting, because it is the whole idea in one diagram — four systems cooperating rather than a
tool doing a scripted thing:

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

---

## 11. NO CARRYING CONTAINERS — a settled decision

**The player does not carry a container of any kind.** Snow is moved with the **shovel**, the
**blower** and the **salt**, and it reaches the disposal machine **thrown, or under its own momentum**.
There is no vessel to fill, no vessel to tip, and no interface element for one.

**Follow this through, because it touches three other sections:**

- **The machine's `accept()` entry has no caller** (§6.2). **Keep it as the documented extension point
  and label it as currently unused**, or drop it. What must not happen is an API with no caller that
  nobody labels as such, because the next person concludes the feature is half-built.
- **The machine's rule** is **"nothing that is not snow is swallowed"** — not "do not swallow the
  vessel". Same check, different justification, and the justification is what a future reader needs.
- **No interface readout for carried contents** (§9.2).

### The cost, stated so it is a conscious choice

**A carrying container is the natural way to move a large amount of snow a long distance for a small
price in effort.** Without one, that job rests entirely on **thrown balls and blown snow** — and **the
economy has never been timed** (§7, §12).

**So this is the thing to measure first.** If moving snow across a field turns out to be too expensive
in effort, the answers are: a shorter field, a different payout, or a carrying container after all.
**Not a guess** — measure income per minute before deciding.

### If a carrying container is ever added, this is the contract it must satisfy

Recorded so the API is not invented inconsistently. It must expose:

| Member | Meaning |
|---|---|
| `capacity_kg` | How much it holds |
| `own_mass_kg` | Its own empty mass |
| `footprint_radius` | For support and interaction |
| `contents_kg` | What it currently holds |
| `fill(kg)` | Returns how much it **actually** took |
| `take(kg)` | Returns how much it **actually** gave |
| `empty_all()` | Empties and returns the contents |
| `free_space_kg()` | How much more it can take |
| `fill_ratio()` | Contents over capacity |

**`fill` returns what it took and never more than the free space** — that is the mass invariant, and it
is why the return values matter rather than being void.

**One trap from the past, worth not repeating:** three such classes declared a `contents_changed`
signal that **nothing connected to**, because the interface **polled** the value every frame instead.
That is not broken, but **a signal that looks like the update path and is not one is a decoy** — the
next person connects to it, sees nothing happen, and has to work out why. **Either connect it or do not
declare it.**

### For the record: if a WHEELED vehicle is ever attempted

**Two of the four causes below are about support physics and two are about geometry.** They were paid
for once; they do not need paying for twice.

1. **A support spring on both the body and the wheels.** They disagreed (reference radii 0.42 against
   0.22) and threw the body to **y = 1.17 m** at 3.5 m/s.
2. **A spring only on the wheels, with a hinge.** The hinge **did not transmit the body's weight**: the
   body rode *above* its own wheels (origin 0.449 m, wheel centres 0.486 m) and the wheels felt only
   their own weight — **31.5 N of support for a 137 N load**.
3. **Support applied off the centre of mass on uneven ground.** The surfaces under a 1 m wheelbase vary
   by centimetres, and one point reading 0.14 m deeper took **166 N** by itself — a third of the weight
   in one corner. **Pitch 0° → 50° in half a second.** The remedy is **support at the centre of mass**
   plus a weak explicit levelling torque, so the support cannot rotate the object.
4. **Rolling resistance with the sign inverted**, applied always against the body's own `-heading`, so
   it **pushed** when the vehicle rolled backwards. Measured: raising it from 0.04 to 0.12 made the
   vehicle **faster** (1.71 → 2.96 m/s).

**And the error that was never fixed, which is the one worth reading:**

> The contact points are **in the ground plane by construction**: the body's origin **is** the wheel
> contact line. So a vehicle at ride height has its three points **0.22 m "below" the snow**, and a
> spring read directly from there puts `400 × 14 × 0.22 = 5.5 kN` on a 14 kg body — **thirty-nine g**.
> That is why it left at 6 m/s, and why raising the rolling resistance made it faster: the resistance
> was fighting a fraction of a force that should not exist.
>
> **The spring must be measured from where the vehicle RESTS**, which is **one wheel radius up.** The
> deepest point decides, so no contact is compressed more than the suspension allows.

---

## 12. Verification — how this game is checked

**This section is design, not process.** The material behaviour in this game cannot be verified by
looking at it, and the design depends on measurement. Adopt the method or the rules above will not
hold.

### 12.1 Every system gets an executable check

Each system has a **check script** that launches the real game with a flag, exercises the system in
the **live simulation**, and **prints a verdict**:

```
RESULT: N OK / M FAIL
```

A **runner** executes them all and fails unless every one passes. This is the measurement that counts;
nothing else is treated as evidence that a system works.

**Reference set, with the counts the design expects:**

| Check | Flag | Expected |
|---|---|---|
| Save slots | `--save-roundtrip` | 34 |
| Ball shape | `--ball-shape` | 8 |
| Translations | `--i18n-check` | 17 |
| Diagnostics safety | `--diagnostics-harmless` | 71 |
| Movement | `--movement-lab` | 11 |
| Ball impacts | `--impact-lab` | 18 |
| Impact matrix | `--impact-matrix` | 28 |
| Physics (the four systems) | `--phys-demo` | 36 |
| Test scene | `--playground-check` | 11 |
| Dung beetle roll | `--beetle-roll` | 6 |
| Contact burst | `--contact-burst` | 4 |
| Hand packing | `--hand-pack` | 12 |
| Disposal machine | `--disposal-machine` | 22 |
| Cel shading | `--toon-shot` | 6 |
| Tool ownership | `--tool-ownership` | 37 |
| Reticle and aim | `--reticle-act` | 33 |
| Reticle needs close snow | `--reticle-aim` | 23 |
| Shovel load and push | `--shovel-modes` | 17 |
| Snow carving | `--carve-quality` | performance check, FPS floor |

**Total: 395 checks when green.**

### 12.2 The rules, every one of which was paid for

1. **A check that hangs or aborts without a verdict is a FAILURE, not a skip.** A crash must never be
   mistaken for a pass.
2. **A check that cannot prepare itself must report failure, not return in silence.**
3. **A check must be able to say WHICH object it measured.** A trace that read positions out of a
   node group was following the **wrong ball** for several rounds, because the group returns the
   first one and the test had created another earlier. **A trace that cannot name its subject is not a
   measurement.** Keep the exact reference.
4. **Measure velocity, not only position.** Position tells you where something ended up; **velocity
   tells you whether it was ever launched at all.**
5. **Read the value in the SAME FRAME as the action.** Reading a frame later showed half the speed and
   hid the cause for rounds.
6. **Anything that awaits needs a guard flag, set BEFORE the await.** An `await` inside a stepped
   sequence makes the driver start a **new instance every frame it is suspended**. This bit three
   separate times and cost whole sections of checks.
7. **Do not sleep once and read once.** A process having exited does not mean the operating system has
   flushed its redirected output. A runner read a perfectly finished check as **"no verdict printed
   (crashed?)"** at least three times because it slept 250 ms once — and that sent investigations
   toward two false causes. **Poll for the verdict.**
8. **Do not rely on frame timing to cover an asynchronous effect.** Packing is a **request**: the
   simulation removes the snow and only then does the ball reach the hands. A fixed wait was enough
   alone and not always enough under load. **Poll for the outcome, with a budget.**
9. **Anything measured from a queued simulation operation is measuring the queue.** The value can be
   zero on the frame of the call and arrive frames later.
10. **Never derive mass from a whole-field integral.** See §2.4. **Keep a ledger.**
11. **Verify visuals in PIXELS.** Open the image, report position and colour.
12. **Log every run**, one log per check plus an error log, and **count the script errors in it** —
    that count found a defect that was invisible when a check was run by hand.

### 12.3 The doc-test pattern — turn a design rule into a test

Prose documentation rots; a test does not. **Where a rule matters, write a test that reads the source
and fails if the rule is broken.**

The clearest example: a module that must stay portable has a check that **reads its own file** and
reports if it mentions a scene. Without it, "it is portable" is an intention; with it, it is a fact
that can stop a commit.

**Adopt this pattern aggressively. It is the cheapest way to keep a design decision true.**

### 12.4 One platform hazard to expect

**`Vulkan device was lost`** appeared intermittently **only inside a full run** — a check that passes
every time alone, reported as crashed or failing, **a different one each run**, with a device loss in
its error log. It hit three different checks. **A pause between checks reduced it and did not fix it.**

**The working theory: accumulated driver state from creating and destroying a device once per check,
back to back.** If checks run as separate processes, expect this. **The first thing to try is reducing
the GPU work a single check queues — not lengthening the pause.**

---

## 13. What is open — decisions still to make

Stated plainly so nothing is inherited by accident.

**0. THE SNOW PHYSICS IS THE FIRST WORK ITEM, NOT A LATER PASS.**
   **§2.14 lists five measured failures to fix** — the blower deletes snow instead of blowing it, the
   shovel push does not feel like snow, piles come out as cones, mass disappears unaccounted in
   several places, and the material is computed but not felt. **Fix these before building content on
   top of the material**, because every tool, every level and every balance number sits on it. **The
   governing rule is in §2.14: no operation may remove mass without an exact account of where it
   went.**

1. **Income per minute has never been measured.** **Every price is a placeholder.** This is the single
   most important open number, and §10 makes it urgent: with so little carrying capacity, the cost of transporting
   snow is untested.
2. **Whether a carried load is needed at all** — see §10. Decide with measurements, not taste.
3. **Ownership: save or session?** — see §7.4.
4. **Is the player's facing ever externally forced?** — see §3.
5. **One of two push-force values is stale** (260 N/26 m/s² versus 380 N/32 m/s²) and **one of two
   break thresholds** (a flat 7 m/s versus a tiered 2.5–5.0 m/s). Resolve against the build you start
   from; do not carry either forward unchecked.
6. **A small reticle offset was never resolved.** One measurement put the dot two pixels left of
   centre, another put it exactly at centre. **The measurement criterion itself was the suspect** —
   see the trap in §9.3. Treat "the reticle is centred" as unproven until measured with a
   criterion that cannot confuse a dot's edge with its middle.
7. **A GPU device-loss hazard** — see §12.4.

---

## 14. Working rules

Not preferences. Each exists because its absence cost time, and most of them cost it more than once.

- **Read a file before editing it.** And do not look for "the nearest `if`" — **read the whole
  block**.
- **Measure first, change one thing, measure three times.**
- **If a fix fails twice, stop refining it and try three different framings.** The fourth attempt at
  the same framing is where the money goes.
- **If a text replacement matches more than once, reject it.**
- **The measurement that counts is the full run**, not a single check. **Never** use a
  quit-after-N-seconds flag on a check: it kills checks before their verdict and then looks like a
  problem with the game.
- **Never claim a visual fix from a parser result.**
- **A comment should record the MEASURED cause** — the number, the version that was wrong, and why.
  That is what stops the next person repeating it.
- **State what is not done, out loud.** The most expensive misunderstandings are about what "green"
  actually covered.
- **A job that must be done in two places will be done correctly in one of them.** Give shared work
  one home.

---

## 15. Everything else a professional build needs

**This section exists so nothing is missing by accident.** It is a **checklist, not a
specification**: it names the work a professional release involves, and the expectation is that **you
add detail, reorder it, and cut what genuinely does not apply** — but that you do so **deliberately**,
having considered each line. **If a line here does not apply, say why. If it applies, plan it.**

**The single most important warning in this section:** none of these items is optional because the
game is small. **A small game still ships with a save system, a settings menu, a build process and a
licence file.** The failure mode is not choosing badly — it is not choosing at all, and discovering
the gap the week of release.

### 15.1 Production and project management

- **A production method and a milestone plan.** What "done" means for a level, a mechanic, a build.
- **A vertical slice before content volume.** One level, complete end to end, at final quality,
  before producing ten of them. **This is the cheapest possible way to find out the game is not fun.**
- **A scope decision, written down, with what is being cut.** Small games die of scope, not of
  ambition.
- **Version control discipline** — and this project **already requires it**: the build marker in §9.6
  assumes a single identifiable build, and the checks in §12 assume a runnable game at any commit.
- **An issue tracker** with the measured evidence attached to each defect, because §12's whole method
  is that a claim without a measurement is not a claim.
- **A definition of the target hardware**, since §2.12 sets a performance requirement that is
  meaningless without a machine to meet it on.
- **A schedule that includes the things nobody schedules**: bug triage, the tuning pass, and the
  "make it feel good" phase at the end, which is always longer than estimated.
- **A decision on the business model, early**, because it constrains design. (The reference answer
  for this project: **premium, no microtransactions, no battle pass.** If that changes, change it
  deliberately.)

### 15.2 Art

- **An art direction with a stated reference**, so that "does this look right" has an answer. The
  current look is **stylised, low-poly, cel-shaded**.
- **A cel-shading / toon pipeline** applied **consistently** — a single object outside the style reads
  worse than none of it applied.
- **An asset pipeline and naming convention**, and a folder discipline that keeps source art out of
  the shipped build.
- **Animation**: first-person hands and tools, and the world objects that move. **The viewmodel needs
  its own decisions**, including the shadow rule in §2.5.
- **VFX for the material**: impact sprays, the powder cloud on breakage, footprints, the machine's
  output. **The breakage system already has an art hook** (§5.3) — use it rather than rebuilding it.
- **A placeholder policy**: programmatic primitives are legitimate stand-ins, **but they must be
  marked as such in the code and tracked**, or they ship.

### 15.3 AUDIO — build the whole system, leave the tracks empty

**This is an instruction about scope, and it is specific: build the audio SYSTEM completely and
prepare a slot for every track. The tracks themselves are not needed — the owner will supply them.**

**So do not skip audio, and do not stub it either.** The failure this prevents is the common one: audio
is left until last because there is nothing to play, and then every sound is wired in a panic with
different conventions.

**What must exist, with no content in it:**

- **A named catalogue of every sound the game needs**, so the set is known before anything is
  recorded. It should cover at least:

  | Group | What is in it |
  |---|---|
  | Footsteps | Per surface: powder, packed, cleared, pavement, shallow water or slush |
  | Shovel | Scrape (looping, pitched by load and speed), bite/cut, jam, release/pour, tamp |
  | Blower | Motor loop with a load-dependent pitch, intake, output |
  | Salt | Pour loop, scatter |
  | Snow impacts | Light, medium, heavy, and a burst for breaking |
  | Bodies | Ball roll (looping, pitched by size and speed), ball settling, ball creaking under load |
  | The machine | Motor under load, feed thud, coin/payout chime, idle hum |
  | Interface | Menu move, menu confirm, menu back, refusal, purchase, autosave tick |
  | Player | Stagger, knockdown, hit by snow, face-full of snow, wipe |
  | Ambience | Wind loop, falling snow, distance |
  | Music | Menu, level, and the state changes between them |

- **A track definition with its metadata declared**, so that dropping a file in is the whole job. Each
  slot declares: a **name/key**, the **file path** it will load from, **looping or one-shot**,
  **bus/channel routing**, **base volume**, **pitch-randomisation range** (so repeated footsteps are
  not machine-gun-identical), **polyphony limit** and, where relevant, the **runtime parameter that
  drives its pitch or volume** (speed, load, size, distance).
- **The audio buses defined up front**: `Master`, `Music`, `SFX`, `Ambience`, `UI`. **All routing is
  through them from day one** — this is what makes the settings in §9.7 work, and retrofitting buses
  after the fact means touching every play call.
- **A missing file must be a warning, never a crash**, and must be visible in the log so an empty slot
  is obvious rather than silent.
- **Placeholders that make the silence informative**: a programmatic tone or noise on each wired-up
  event is better than nothing, because it proves the trigger fires. **A sound event that never
  fires is the actual bug, and a placeholder is how you find it before the real asset exists.**
- **Every event trigger wired to its slot**, so the game is audibly complete with placeholder tones and
  becomes real the moment files appear.
- **A debug facility**: a way to list the slots, see which are empty, and trigger any of them on
  demand. **The cheapest QA tool for audio is a test page**, and it costs an afternoon.
- **Document the format expected** (sample rate, mono or stereo, loop metadata, normalisation target)
  so the provided tracks drop in without a conversion pass.

**Why this matters even with no content:** a labour game is **heard more than watched** — a shovel
scraping, a ball thudding, snow compacting — and **audio is the cheapest way to make work feel
satisfying**. Leaving the system unbuilt because the tracks do not exist yet means the feel cannot be
evaluated at all, and the feel is the product.

### 15.4 The experience around the game — the things new developers skip

**This is the other half of "professional", and it is the half most often missing.** The list below is
not polish; **each item is something a player will hit, and each one is routinely left undone.**

**Menu structure, as a map to be designed — not discovered**

- **Every screen drawn out before it is built**: title, main menu, level select or loading, in-game
  HUD, pause, settings, controls/rebinding, save slots, credits, quit confirmation, and the
  level-complete and failure states.
- **The path in and out of every screen defined**, plus **how to get back** from anything (§9.7).
  A screen with no exit is a bug, not a rough edge.
- **The first-run experience decided**: what a brand-new player sees, what defaults they begin with,
  and **whether anything is explained or asked before they play**. Defaults are a design decision —
  a new player should never be handed a settings maze before their first minute of play.
- **A loading story**: what is shown, how long, whether it can be skipped, and **what happens on the
  very first launch**, which is always slower.

**Configuration, and the list is longer than most people expect**

- **Display**: resolution, window mode (windowed, borderless, fullscreen), V-sync, frame-rate cap,
  monitor selection for multi-monitor, and **brightness/gamma**.
- **Graphics quality that actually drives the simulation** — the preset levels must map to the snow
  resolution and iteration counts of §2.12, and **changing them must never change the physics**, only
  its fidelity.
- **Audio**: the buses above, each independently adjustable, **with 0 being a legal value** and a mute
  that remembers the previous levels.
- **Controls**: separate mouse and stick sensitivity, invert-Y (both axes), and **conflict detection
  when rebinding** so two actions cannot silently share a key.
- **Language selection**, and **whether it applies immediately or needs a restart** — decide, and say
  so in the interface.
- **Accessibility options** (§15.5) surfaced in the same place as everything else, not hidden.
- **Every setting persists** (§9.8), is applied at startup, and **survives a version change** —
  adding a new setting must not reset the others.
- **Restore defaults**, per section and globally.

**The states nobody designs until they break**

- **Save slots**: create, load, overwrite, delete, with confirmation and enough identity to tell them
  apart (§9.8).
- **Level select and progress presentation**, if there is one.
- **The "you have no save" and "your save is from a newer version" paths** — both are real, both are
  seen, and both are usually a blank screen.
- **The victory and failure screens**, including **what the player can do next**.
- **Quitting properly** — from the pause menu, from the main menu, and by closing the window, all of
  which should ask the same question and give the same answer.
- **The credits**, which are legally required in most jurisdictions and are always forgotten.
- **Window focus loss, alt-tab, and monitor changes** — decide the behaviour (§9.7).

**And the low-chrome details that separate a build from a product**

- **Localisation-ready layout** (§9.6) — nothing clipped when a German word is twice the length.
- **A visible version number** in the interface, matching the build marker (§9.6).
- **Mouse cursor behaviour**: captured in play, visible in menus, **and never trapped**.
- **Every default sensible out of the box**, because most players never open settings at all. **The
  defaults are the game that most people will play.**
- **A title screen that costs nothing to skip** on the second launch.

> **If a line here is not applicable, say so in the plan. Do not leave it unconsidered** — this list
> exists because "we will handle that later" is how a finished-looking game ships without a credits
> screen or a way to change the volume.


### 15.5 Accessibility

**Plan this before content exists, because retrofitting it is far harder.** At minimum:

- Full remapping of every control, on keyboard and controller (§9.4).
- A field-of-view slider, and **motion-reduction** options.
- **No colour-only signalling** — every colour-coded state also distinguishable by shape, position
  or text.
- **Text that scales**, and contrast that survives it.
- Subtitles/captions wherever audio carries information the player needs.
- **Difficulty that can be lowered without shame**, and a way past a stuck state that is not "quit"
  (§9.7).
- **Consider the player who cannot use two hands on a mouse or controller** before designing a
  two-button mechanic — or provide an alternative.

### 15.6 Quality assurance

- **A formal test plan.** The automated checks in §12 are its backbone, **not a substitute for
  playing the game**.
- **A bug severity definition** and a triage rhythm.
- **A soak test**: leave the game running for hours and verify nothing degrades. The GPU hazard in
  §12.4 is exactly the class of defect this finds.
- **Save/load testing**, including **corrupted saves and version mismatches** (§9.8).
- **A clean-install test**: a machine that has never had the game, with saves, settings file and
  shader cache all absent.
- **A playtest protocol**: who plays, how, what is observed, and **which measurements are taken**.
  **Playtesting a labour game is about whether the work is satisfying**, which is a different question
  from whether it functions.
- **A regression suite that grows with each fixed bug** — every defect found by play should become a
  check if it can be expressed as one.
- **A release checklist**, performed on the release candidate and not before.

### 15.7 Build, distribution and release

- **Reproducible builds**, and a version number that appears in the interface **and in the save file**.
- **The build marker from §9.6 wired into the real build**, not just the development run.
- **Export to the target platform(s) early**, not at the end. Exports break in their own specific
  ways.
- **A store presence**: page, screenshots, trailer, description — and **those are deliverables with
  deadlines**, not marketing afterthoughts.
- **Legal**: the **licence record** (§15.7), the age rating, and the EULA or privacy obligations if any
  data leaves the machine.
- **Crash reporting and a way to receive player feedback**, if the platform allows it — with the
  player's consent.
- **A rollback plan.** A broken release is worse than a late one.

### 15.8 Live and long-term

- **A patch process**, and a **save-format migration plan** (§9.8) for the day the format changes.
- **A content plan** for after release — or an explicit decision that there is none.
- **Telemetry is optional and must be consensual.** If the game has none, say so deliberately, because
  it means tuning has to come from playtests (§15.6) instead.
- **Localisation is a decision, not a default.** The infrastructure in §9.6 costs little and should
  exist regardless; **how many languages ship** is a budget question.

### 15.9 The engineering habits that make the rest possible

- **A single source of truth for shared work.** A job that must be done in two places will be done
  correctly in one of them (§10.1).
- **A check for every rule that matters** — the doc-test pattern in §12.3 is the cheap version.
- **Measure before and after every performance change**, and keep the numbers (§2.12).
- **A comment that records the measured cause**, not the intention.
- **State what is not done**, out loud, in every hand-over and every commit message.

> **If you are the AI reading this: treat §15 as the list of things you were told to CONSIDER rather
> than the list of things that were settled. Everything else in this document is settled. This section
> is where your judgement is wanted, and where you should add whatever a professional build needs that
> is not already named here.**

---

## 16. The five things most likely to be got wrong again

If only one section is read, read this one.

1. **The mass rule.** The field gives up a kilogram and the blade takes **all of it**. The rate limits
   the **cut**, never what the blade keeps. **A factor applied after the removal is an unaccounted
   deletion.** *(Cost when wrong: 60 % of all shovelled snow, destroyed silently.)*
2. **Gathering needs CLOSE aim.** One predicate, shared by the reticle and the pack, gated **before**
   anything is queued — or you get **a hole with no ball**. *(Cost when wrong: four attempts.)*
3. **The thrower must not collide with the ball it just threw.** It is held **inside** the thrower's
   capsule by construction, so it is ejected on release — measured as **9.000 m/s becoming 4.500 m/s,
   deflected sideways, in one physics step**. *(Cost when wrong: the game's only income was
   unreachable by throwing, and it was investigated as an aiming problem for a long time.)*
4. **Payout is per KILOGRAM, on the running total.** `ceil` per delivery makes every fragment worth a
   coin, and then **breaking a ball is a way to print money**. *(Cost when wrong: 4× the declared
   rate.)*
5. **Size the interface correctly and let it own its own visibility.** `set_anchors_and_offsets_preset`,
   not `set_anchors_preset`, and **a screen that hides itself at startup is not a screen.** *(Cost when
   wrong: the pause menu and the main menu both reported as "not appearing".)*

---

*Every value in this document was read out of a working implementation or from a measured log, not
estimated. Where two sources disagreed, the disagreement is recorded rather than resolved. Where a
claim was never verified, it is written as a question in §12.*