# Implementation plan — Systems and mechanics

> **Scope of this document:** build the *systems* and the *mechanics* of the
> game. **There is no content**: no levels, no scenario, no final art. Everything is
> validated in a temporary **Playground** (§4).
>
> Sibling document: `plan_juego.md` (design and product). When something changes here,
> it is noted there.
>
> Marks: ✅ already exists in the prototype · ⬜ to do · 🔧 extension of something that exists.

---

## 0. Working rules and "done"

### 0.1 The project's three invariants

1. **Solo and co-op are equally good.** No system is designed "for co-op and we will
   see about solo later" or the other way round. **Every spec sheet declares its behavior with N=1 and with
   N=2**, and both cases go into the tests. Co-op is not a mode: it is a
   system variable (`player_count`), and the game is sized with **session
   rules** (§2.G.25), not by trimming levels.
2. **Mass is conserved.** Any new mechanic (compacting, melting, blowing,
   pushing a player) has to balance in the snowpack's ledger. A test
   is mandatory in every phase.
3. **No content in this phase.** If something needs a pretty level to
   be tested, it is badly conceived: it is tested in the Playground.

### 0.2 Definition of Done for a system

- [ ] Spec sheet completed in this document (API, data, exported parameters).
- [ ] Implemented **without text literals** (everything a translation key from day 1).
- [ ] **Zero magic numbers**: every parameter `@export` or a data resource.
- [ ] Declared and tested with **N=1 and N=2**.
- [ ] Its own automated test in the Playground or in a battery (§6).
- [ ] No regression: the existing batteries (`--phys-demo`, `--carve-quality`,
      `--ball-shape`) stay green.
- [ ] Frame budget respected (≤ 3 ms of simulation, see `plan_juego.md`).

### 0.3 Conventions

- One folder per family (`scripts/player/`, `scripts/tools/`, `scripts/balls/`,
  `scripts/session/`, `scripts/progression/`, `scripts/ui/`, `scripts/net/`,
  `scripts/playground/`).
- **Communication through signals**, not through cross-references: the HUD does not know the
  movement engine; it listens.
- A system never writes into another: it asks (API) or notifies (signal).

---

## 1. Layers and system map

```
Layer 6  PLATFORM       Steam · saving · network · telemetry
Layer 5  PRESENTATION   HUD · menus · settings · i18n · audio · VFX · photo
Layer 4  PROGRESSION    objectives · seals · economy · achievements (shared)
Layer 3  SESSION        player_count · mode (Work/Ruckus/Duel) · scaling
Layer 2  PLAYER         movement engine · states · tools · interaction
Layer 1  PHYSICAL WORLD balls · grabbable objects · containers · vehicles · dummies
Layer 0  SIMULATION ✅  granular snowpack with conserved mass
```

Every dependency goes **downward**. Layer 0 exists and works; the work is
in layers 1–6.

---

## 2. System spec sheets

### A. Simulation core (layer 0) — extensions 🔧

| # | System | Responsibility | Key API | Status |
|---|---|---|---|---|
| 1 | `SnowField` | Granular snowpack, ops and mass | `carve/dump/tamp/harvest` ✅ | ✅ |
| 2 | `SnowSurfaceQuery` | **Surface type and friction per position** | `surface_at(pos) → {friction, depth, compact, slush}` | 🔧 |
| 3 | `SnowCompaction` | **Compact** snow without removing it (new GPU op) | `compact(pos, radius, amount)` | ⬜ |
| 4 | `MassZone` | Volumes that accept/expel mass and account for it | `accepts(pos)`, `mass_in()`, `signal mass_changed` | ⬜ |
| 5 | `MassLedger` | Total ledger (snowpack + balls + containers + fragments) | `total_mass()`, `report()` | 🔧 |

**2. `SnowSurfaceQuery`** is the piece that makes movement, the
tools and the bunny hop work. It combines channels that already exist (height, loose snow,
cohesion) into a *surface type* reading:

| Type | Condition | Friction | Effect |
|---|---|---|---|
| Clear / compacted | `h < 0.02` or `compact > 0.7` | very low | you run and keep momentum |
| Powder snow | `cohesion < 0.35` and `compact < 0.4` | high | you sink, speed is cut |
| Wet / heavy snow | `cohesion > 0.7` | medium-high | it feels heavy, it sticks |
| Slush / ice | `slush > 0.6` | nearly none | you slip, you do not brake |

**3. `SnowCompaction`** is a new shader operation (mode 10) that **raises the
compaction channel without touching height**: zero mass transfer, only a change
of state. It is what lets the bunny hop trace paths and lets tamping have
economic sense (compacting is *cheaper* than removing... but does not clear 100%).

**5. `MassLedger`** turns invariant #2 into something measurable in real time:
`snowpack + balls + containers + fragments + water = constant`. The development HUD
displays it; the batteries verify it.

### B. Player (layer 2)

| # | System | Responsibility | Key API | N=1 / N=2 |
|---|---|---|---|---|
| 6 | `PlayerMotor` | Movement with inertia: friction per surface, air control, bunny hop, sliding, crouching | `set_input()`, `speed`, `is_sliding` | identical |
| 7 | `PlayerState` | State machine: normal · snow-blinded · destabilized · knocked down · buried · riding | `apply_hit(tier, zone)`, `state`, signals | identical |
| 8 | `PlayerAvatar` | Body visible to the partner + procedural animation | `pose_from(state, velocity)` | only in N=2 |
| 9 | `PlayerInteraction` | `E` (pick up/tamp/push), kick, drag, **grab the partner** | `try_interact()`, `grab_partner()` | in N=1 the "partner" does not exist: it is ignored |
| 10 | `PlayerCamera` | Head bob, sway, roll, dynamic FOV, shake and **snow overlay on the face** | `add_shake()`, `set_face_snow(0..1)` | identical |
| 11 | `PlayerAudio` | Footsteps per surface, effort, impact, shouts | events | identical |

**7. `PlayerState`** is the system that receives impacts (§3.2) and **the only one that
can block actions**. Hard rules:

- A state **never** takes away progress (design invariant): only time.
- **1.5 s immunity** when leaving any state → *stun-lock* does not exist.
- In **Work mode** the states from ball impact **are not applied** (immunity).
- When **knocked down** you drop what you were carrying in your hands (and that is fun and
  physically coherent).

### C. Tools (layer 2) — data system

| # | System | Responsibility |
|---|---|---|
| 12 | `ToolSystem` | Shared framework: slots, switching, viewmodel, animations, stats, upgrades 1–3 |
| 13 | `ToolDefinition` | **Resource** that describes a tool (verb, parameters, cost, upgrades) |
| 14 | Verbs | `Carve/Push` (shovel, pusher) ✅ · `Blow` (turbine) ✅ · `Salt` (salt shaker) ✅ · `Pick` (pickaxe) ⬜ · `Rake` (rake) ⬜ · `Melt` (hose) ⬜ · `Pack` (hands) ✅ · `Tamp` ✅ · `Throw` ✅ |

A new tool **does not touch code**: it is a `.tres` + a verb that already exists.
That is what makes it possible to add the 8 without inflating the project.

### D. Balls and projectiles (layer 1)

| # | System | Responsibility | Status |
|---|---|---|---|
| 15 | `SnowBall` | Physical ball: accretion, mass, density, stacking, breaking | ✅ |
| 16 | `BallTier` | **Classification by size** (small/medium/large) and thresholds | ⬜ |
| 17 | `BallBallistics` | Flight, parabola prediction for aiming, wind (optional) | ⬜ |
| 18 | `ImpactResolver` | **Decides the effect**: size × body zone × speed → state | ⬜ |
| 19 | `FaceSnow` | Snow layer on the face: overlay, auto-clearing, manual clearing | ⬜ |
| 20 | `BallHandoff` | Receiving/passing balls between players (`E` tap when close) | ⬜ |
| 21 | `TrainingDummy` | **Test dummy** that receives the same impacts as a player | ⬜ |

**21. `TrainingDummy` is key to invariant #1**: it implements the same interface
`ImpactReceiver` as the player, so **the entire impact system can be
tested and enjoyed solo** without depending on a second person. It is also what
makes the "hits" achievements attainable solo.

### E. Objects and physical cooperation (layer 1)

| # | System | Responsibility |
|---|---|---|
| 22 | `Grabbable` | Shared interface: pick up, carry, drop, throw, two hands |
| 23 | `TwoPersonCarry` | **Two-person grip**: splits weight, mitigates wobble and grip drain, synchronizes poses |
| 24 | `Container` | Wheelbarrow, bucket, truck box: fill, empty, weigh (real mass) |
| 25 | `Vehicle` | Quad with plow and sled: driving, passenger, blade that mows, tipping over |
| 26 | `Pushable` | Push with the body or between two (force that adds up) |

### F. Pranks and social states (layer 3)

| # | System | Responsibility |
|---|---|---|
| 27 | `SessionMode` | **Work / Ruckus / Duel**: governs whether balls affect players |
| 28 | `PrankStats` | Per-player counters: balls thrown/received, times buried, piles destroyed, kg re-scattered |
| 29 | `Chronicle` | Final summary with absurd awards (assembled from `PrankStats`) |
| 30 | `DuelMode` | Scoreboard, rounds, arena mutators |

### G. Session, progression and achievements (layers 3–4)

| # | System | Responsibility | Note |
|---|---|---|---|
| 31 | `SessionRules` | Match rules: `player_count`, mode, difficulty/assistance | —— |
| 32 | `PlayerCountScaler` | **Makes N=1 and N=2 feel equally good** (§3.4) | the most delicate system |
| 33 | `ObjectiveSystem` | Composable conditions evaluated per tick + level seals | —— |
| 34 | `ProgressionSystem` | Money, stars, unlocks, upgrades | —— |
| 35 | `AchievementSystem` | **SHARED achievements** of the match (§2.G.35) | —— |
| 36 | `SaveSystem` | Profiles, versioned schema, mid-level saving | —— |

**35. `AchievementSystem` — shared achievements.** Two rules that are verified
automatically:

1. **They unlock for the whole match**: if it is earned in co-op, **both players**
   receive it (same achievement, same time, no splitting). The host validates and
   emits; the client applies it. No "I got it and you did not".
2. **All of them are attainable solo.** An achievement can never require a second
   person (`--ach-check` verifies it: every achievement declares `solo_attainable = true`
   and the conditions are evaluated in a one-player Playground, using
   `TrainingDummy`/targets when the achievement talks about impacts).

Counter progress is also **shared**: it adds up both players'.

### H. Presentation and platform (layers 5–6)

| # | System | Responsibility |
|---|---|---|
| 37 | `UIManager` | Screen flow and focus (gamepad and mouse) |
| 38 | `HUD` | % cleared, mass, tool, load, objectives, state warnings (blinded/knocked down) |
| 39 | `SettingsSystem` | Video · audio · controls · game · accessibility · network · data (live application) |
| 40 | `InputManager` | Remapping, per-device pRuckusts, *hold/toggle*, auto-bhop |
| 41 | `LocalizationManager` | Keys, per-language plurals, locale format, QA mode |
| 42 | `AudioManager` | Buses, snow layers per surface/tool, music by progress |
| 43 | `VFXManager` | Lifted snow, break cloud ✅, impacts, footprints |
| 44 | `PhotoMode` | Free camera, filters, poses |
| 45 | `NetworkManager` | Host/join, op replication, RLE resync, prediction, lobby |
| 46 | `PerfGuard` | Simulation presets, sim at 30 Hz, frame budget, telemetry |

---

## 3. Mechanics: numeric specifications

### 3.1 Movement and bunny hop ✅ **Implemented** (in `player_controller.gd`)

**The model is Quake's, not a homegrown approximation.** References:
*Quake III*'s `PM_Accelerate`/`PM_Friction` (`bg_pmove.c`) and the analysis at
[QW physics air](https://www.quakeworld.nu/wiki/QW_physics_air). Three rules
define it:

1. **On the ground friction is applied ALWAYS, also while walking**, and then you
   accelerate toward the desired speed. That is why walking feels weighty and is
   bounded: there is no sliding.
2. **In the air there is no friction**, and the desired speed is **clipped to a small
   value** (`air_wish_speed`). The acceleration is limited to `wishspeed − v·wishdir`,
   so the only way to gain speed is **to aim the push direction
   perpendicular to velocity** and let the acceleration rotate it. That is
   *air strafe*.
3. **Jumping only adds vertical speed.** Its reward is **skipping the friction
   of the landing frame**: that is why the jump check runs **before**
   friction, just like in `PM_WalkMove`. A player who only holds forward and
   jumps **gains nothing**.

| Parameter | Implemented value | Measured with `--movement-lab` |
|---|---|---|
| Walk / run | 4.2 / 6.8 m/s | 3.57 / 6.12 m/s on powder (×0.85) |
| `ground_accelerate` / `ground_friction` | 12 / 5 | walking reaches the exact target |
| `ground_stop_speed` | 1.5 m/s | —— |
| `air_accelerate` / `air_wish_speed` | 12 / 1.0 m/s | —— |
| Bhop cap | **2.0 × run = 13.6 m/s** | the chain reaches the cap in 8 jumps |
| **Straight jump** (forward only) | —— | run-up 5.99 → **5.78 m/s: gains nothing** |
| **Air strafe ideal** | —— | run-up 6.66 → **13.60 m/s (+104%)** |
| Releasing the stick from a run | —— | **stops in 0.37 s** |
| Surface by cohesion | powder ≥0.45 compacted | powder x0.85/friction x1.2 · compacted x1.05/friction x0.8 |
| Compaction on landing | `tamp` at 0.38 m, force 0.18 | every landing packs the snow down and leaves the ground faster |
| Sliding on slopes | ⬜ Playground slope | —— |
| Auto-bhop (accessibility) | `auto_bhop`, off by default | skipping the rhythm; it does not give speed by itself |

**Test:** `--movement-lab` (10 checks) measures walking/running per surface,
that releasing brakes in less than half a second, that **jumping in a straight line
gains no speed**, that **air strafe does** (with a bot that aims the push perpendicular
to velocity, that is, the ideal case), the cap and the chain count.

**Known limitation:** the current level is short (12 m of field), so the
long chains leave the simulated field. The Playground will need a long track
to measure the full curve and the slopes.

### 3.2 Ball impact on players ✅ **Implemented**

**Classification by size** (measured radius, with the mass that comes from the variable
density). In code: `SnowBall.tier_for_radius()`.

| Category | Radius | Approx. mass | How it is thrown |
|---|---|---|---|
| **Small** | `r < 0.18 m` | 1–8 kg | one hand, fast |
| **Medium** | `0.18 ≤ r < 0.34 m` | 8–60 kg | one or two hands, slow |
| **Large** | `r ≥ 0.34 m` | > 60 kg | **two hands**, "heave" only |

**Effects** (they require the ball to have been thrown, not rolling):

| Category | Impact on the **body** | Impact on the **face** | Minimum speed | Measured |
|---|---|---|---|---|
| **Small** | Nothing (only sound and splash) | **`NADIEVE`**: face full of snow | 5.0 m/s | ✅ 3.3 s of snow, without destabilizing |
| **Medium** | **`DESESTABILIZADO` 1.0 s** | `DESESTABILIZADO` + **`NADIEVE`** | 3.5 m/s | ✅ state 1, snow 3.3 s |
| **Large** | **`DERRIBADO` 2.0 s** | `DERRIBADO` + **`NADIEVE`** | 2.5 m/s | ✅ state 2 and it drops the load |

**`NADIEVE` (snow on the face)**:
- **Automatic duration 3.5 s** and it removes itself.
- **Manual clearing**: holding the interaction action **[E]** removes it in
  **0.6 s**. Measured: 3.28 s of snow → 0 in 0.9 s of clearing.
- Visual effect: snow overlay on screen, generated by code (a procedural
  white splotch, no assets). **It does not immobilize you**: you can walk and use
  tools; you just see badly.
- Setting `snow_face_auto_clear`: **Normal = yes** (it removes itself) · **Realistic = no**
  (manual only). It is the "(this in normal mode)" you asked for, turned into a setting.

**`DESESTABILIZADO` (1.0 s)**: fine control is lost — you cannot use a
tool, movement keeps inertia with a lateral sway and the camera
sways and trembles.

**`DERRIBADO` (2.0 s)**: you cannot act; **you drop what you were carrying** ✅
measured. The camera falls toward the snow and rises on a curve, not abruptly.

**Coexistence rules (anti-frustration) 🔒 hardened:**
- No hit lands **while a state lasts** or during the **1.5 s** of
  immunity on exit. Measured: three balls in a row → `hits_taken` stays at 1.
- `hit_reactions_enabled = false` is "Work Mode" (balls pass through).
  By default **enabled**, which is Ruckus.
- Analytic **face** detection: two spheres per person (`impact_spheres()`,
  head and torso) and the ball decides by height. No extra *hitbox*.
- In **solo**: there is a `TrainingDummy` in the level next to the path ✅ and
  it receives exactly the same hits as a player (tested).

**Two detection paths, for a measured reason:** a player has a collision
body and **stops the ball before** it enters the analytic spheres, so
its hit is resolved by the real contact; the dummy has no body, so its
hit is resolved by a segment sweep. Mixing the two paths would count the
hit twice, so each target uses its own. Since the contact is notified
**after** the solver has already slowed the ball (measured: a ball of 7 m/s
arrived at 4.81 m/s), the arrival speed is the **maximum of the last 4
frames**.

**Test:** `--impact-lab` (18 checks): classification of the 3 sizes,
face/body per size, duration and end of each state, immunity, a slow ball that
does nothing, manual clearing and the training dummy.

**Pending for this section:** the full `--impact-matrix` (3 sizes × 3 zones ×
3 speeds) once the `PlayerState` shared with the session mode exists, and the
blur/muffled audio of `NADIEVE` (today it is only the overlay).

### 3.3 Physical cooperation ⬜

| Mechanic | Rule | N=1 / N=2 |
|---|---|---|
| **Two-person lift** | If two players hold the same object: wobble × 0.4, grip drain × 0.5, carry speed × 1.25 | in N=1 the current behavior ✅ |
| **Two-person push** | The forces add up, with the per-object cap | in N=1 simple force ✅ |
| **Passing a ball** | `E` tap near a ball in flight or rolling: it couples to the hands | N=1: you pick it up from the ground ✅ |
| **Boosting the partner** | Climbing onto a pile or a ball and having the other one push | N=1: you climb by yourself |
| **Rescue** | Digging out a buried partner (action mash) | N=1: you free yourself |
| **Containers** | The mass inside counts in the ledger; when tipped over, it really comes out | identical |

### 3.4 `PlayerCountScaler` — the system that equalizes solo and co-op ⬜

**Problem:** if I size for 2, solo is a punishment; if I size for 1,
in co-op it is over in three minutes. **Solution: scale the requirements, never the
physics.** The world's mass, the snow's resistance and the objects' weight are
identical with 1 or 2 players (that is what makes the physics credible and comparable).

| What scales | N=1 | N=2 |
|---|---|---|
| Objective coverage requirement | × 1.0 | × 1.0 in the common zone; the **optional zones** activate |
| Target time of the seals | × 1.0 | × 1.55 |
| Optional objectives available | subset | all |
| Soloist aids | quad with plow / neighbor (to be decided with playtest) | —— |
| Achievements | **the same** (shared, all attainable) | **the same** |

**Golden rule:** with 2 players you clear **more surface in the same time**, not
the same surface twice as fast. And in solo, **nothing** is ever asked that
requires two hands.

**Test:** `--coop-rules` evaluates the same objective with simulated N=1 and N=2 and
checks that the work/requirement ratio stays within ±15%.

### 3.5 States and actions: blocking matrix

| Action | Normal | Blinded (snow) | Destabilized | Knocked down | Buried |
|---|---|---|---|---|---|
| Walk / run | ✅ | ✅ (worse vision) | partial | ❌ | ❌ |
| Use tool | ✅ | ✅ (worse aim) | ❌ | ❌ | ❌ |
| Pick up / carry | ✅ | ✅ | ❌ | ❌ (drops) | ❌ |
| Clear your face | —— | ✅ (manual 0.6 s) | ❌ | ❌ | ❌ |
| Bunny hop | ✅ | ✅ | ❌ | ❌ | ❌ |
| Free yourself | —— | —— | —— | ✅ (stands up on its own) | ✅ (mash) |

---

## 4. Playground — temporary test bench

A single neutral scene, `scenes/playground.tscn`, **with no scenario and no final art**.
It is where *everything* is tested until content exists.

**Playground contents (mechanical, not artistic):**
- Flat 40×40 m esplanade with snow at different depths by zone
  (0 / 0.1 / 0.32 / 0.6 m) to test friction and sinking.
- **Gentle ramp (20°)** and **steep ramp (35°)** for sliding and avalanches.
- **Wall and corner** for ball bounces (self-impact) and shoves.
- **Platform at 4 m** (simulated roof) to test falls and avalanches.
- **Pit / water** for the legitimate outflow of mass.
- **Mass destination zone** (`MassZone`) and a heavy container (`Container`).
- **Target gallery** + **2 `TrainingDummy`** with the same reactions as a player.
- **Rack with the 8 tools** and a **ball spawner** with presets
  (small / medium / large) and adjustable speed.
- **Quad with plow** and sled.
- **Debug console** with commands:

```
pg.spawn ball small|medium|large [speed]
pg.hit dummy|self face|body
pg.state                 # active states, immunity, durations
pg.surface               # surface type and friction under the player
pg.mass                  # full ledger
pg.rules players=1|2     # forces session scaling (no second player!)
pg.rules mode=work|ruckus|duel
pg.timescale 0.25        # slow motion to watch impacts
pg.reload                # resets the snowpack and the mass
pg.log on|off            # telemetry to file
```

**`--local-duo` (debug mode):** two players on the same machine
(keyboard + gamepad, or two windows). It serves to test physical cooperation and
states without network and without waiting for the multiplayer milestone. **It cuts
the co-op risk in half.**

---

## 5. Implementation phases

Each phase ends with its tests green and **the next one does not start without them**.

| Phase | Duration | Content | Exit criterion |
|---|---|---|---|
| **0 · Scaffolding** | 1–2 wk | Autoloads, minimal `UIManager`, basic `SettingsSystem`/`SaveSystem`/`LocalizationManager`, Playground scene, console, `MassLedger` | The Playground loads, a player moves, the ledger balances, the 3 old batteries stay green |
| **1 · Movement** | 1–2 wk | `PlayerMotor` with inertia and bunny hop, `PlayerState`, `PlayerAvatar`, `PlayerCamera` | `--movement-lab`: bhop curve with a cap, 4 different frictions, sliding |
| **2 · Surface** | 1 wk | `SnowSurfaceQuery`, `SnowCompaction` (GPU op 10), footprints | Compacting does not change mass (±0.05%); bhop works only on compacted snow |
| **3 · Tools** | 2 wk | `ToolSystem`, `ToolDefinition`, migrated verbs + pickaxe, rake, hose; upgrades 1–3 | Each tool measures kg/s and conserved mass in the Playground |
| **4 · Balls and impacts** | 2 wk | `BallTier`, `BallBallistics`, `ImpactResolver`, `FaceSnow`, `TrainingDummy`, bounces | full `--impact-matrix` (3×3×3) + immunity + dropping + Work mode |
| **5 · Physical cooperation** | 2 wk | `Grabbable`, `TwoPersonCarry`, `Container`, `Vehicle`, `BallHandoff`, rescue | `--local-duo`: two-person lift, passing balls, tipping a container with balanced mass |
| **6 · Session rules** | 1 wk | `SessionRules`, `PlayerCountScaler`, `SessionMode`, `PrankStats`, `DuelMode` | `--coop-rules`: N=1 vs N=2 within ±15% |
| **7 · Progression and achievements** | 2 wk | `ObjectiveSystem`, `ProgressionSystem`, shared `AchievementSystem`, saving | `--save-roundtrip`, `--ach-check` (all attainable solo) |
| **8 · Presentation** | 3 wk | HUD, pause, results + chronicle, menus, full settings, remapping, i18n + pseudo-loc, audio, photo mode | `--settings-apply`, `--i18n-check`, menu navigation **with gamepad only** |
| **9 · Network** | 3–4 wk | Spike → `NetworkManager`: ops, RLE resync, prediction, lobby, Remote Play | `--net-smoke`: drift < 0.5%/level, < 30 KB/s, 30 min session |
| **10 · Performance and CI** | 1–2 wk | Simulation presets, sim at 30 Hz, frame budget, all batteries as gates | `--perf-gate` in 4 configurations; Deck checklist |

**Total: ~20–26 weeks (5–6 months)** of systems, with no content. With the engine already
done, it is the shortest path to a real game.

---

## 6. Test batteries (and CI)

They add to the three that already exist ✅. All of them run **headless** and return a
verdict of `N OK / M fallos` with diagnostic output.

| Battery | What it checks | Phase |
|---|---|---|
| `--phys-demo` ✅ | 36 checks of the core | —— |
| `--carve-quality` ✅ | Terrain quality and FPS | —— |
| `--ball-shape` ✅ | Spheres, density, grooves | —— |
| `--playground-smoke` | That the Playground loads, the ledger balances and the systems respond | 0 |
| `--movement-lab` | Bhop with a cap, 4 frictions, sliding, compaction | 1–2 |
| `--mass-invariant` | Total mass constant across 20 mixed operations (including compacting) | 2–3 |
| `--impact-matrix` | 3 sizes × 3 zones × 3 speeds, immunity, dropping, Work mode | 4 |
| `--coop-rules` | N=1 vs N=2: work/requirement within ±15% | 6 |
| `--save-roundtrip` | Save → load → same state, same mass, migrated schema | 7 |
| `--ach-check` | Every achievement attainable solo; shared unlock in co-op | 7 |
| `--i18n-check` | No key untranslated in any language | 8 |
| `--settings-apply` | All settings apply live and persist | 8 |
| `--net-smoke` | Two instances: mass drift, traffic, reconnection | 9 |
| `--perf-gate` | Frame budget per preset and configuration | 10 |

**Integration gate:** no change goes in if any battery drops from green.

---

## 7. Decisions made in this plan

1. **Co-op of exactly 2, and both modes are first class.** The number of players is
   a *system variable* (`SessionRules.player_count`), not a fork in the
   design. Scaling is solved by `PlayerCountScaler` scaling **requirements**, not
   physics.
2. **Shared achievements.** A single set; in co-op both receive it at the same time, and
   **none requires a second person** (verified by `--ach-check`).
3. **The setting is undecided and is not taken into account.** The Playground is
   deliberately abstract; the scenario does not constrain any mechanic
   (no "alpine snow" and no "village": only *snow*, *surfaces* and *objects*).
4. **Session mode as a system**: Work / Ruckus / Duel, with the impact matrix
   from §3.2.
5. **Anti-`stun-lock` by design**: 1.5 s of immunity after each state.
6. **`TrainingDummy` and `--local-duo`** as test tools: they make it possible to validate
   co-op and impacts **without network and without a second person**.
7. **Compaction is a zero-mass GPU op**, and it is what gives economic meaning
   to tamping and to the bunny hop.
8. **Netcode:** scoreboard-authoritative host, client that simulates and predicts its
   ops, correction via RLE patches, mandatory spike before phase 9.

## 8. Risks of this plan

| Risk | Mitigation |
|---|---|
| The player state machine fights with `CharacterBody3D` (knockdowns, shoves) | **Cinematic knockdown with animation** + physical pushes; never turn the player into a rigid body |
| 30 Hz sim and mowing/compaction lose mass | `--mass-invariant` in every phase; tolerance < 0.05% |
| Bhop becomes an exploit | Hard cap + diminishing-returns slope + curve tests |
| `PlayerCountScaler` becomes a knot of special cases | Only 4 levers (coverage, time, optionals, aids) and a ratio test |
| Co-op is tested late and badly | `--local-duo` from phase 5 and `TrainingDummy` from phase 4 |
| Shader determinism for the network | Audit in phase 9 + plan B (client only interpolates) |

## 9. What is NOT done now

- No levels, scenarios, village, story or final art.
- No shop with a balanced economy (only the system, with test data).
- No specific achievements (only the system and its sharing rule).
- No real localizations (only the keys and pseudo-localization).
- No real Steamworks (only the interface and a *stub* that can be replaced).
