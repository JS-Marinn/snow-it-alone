# Work Status & Pending Items

Current state of the project: what is done, what remains genuinely open, and the hard-won
environment rules and method notes. Written down so nothing depends on memory.

Last updated: 2026-10-05.
Status: **13 batteries registered in `tools/run_batteries.ps1` · 244 checks passing (ALL GREEN)**.

---

## 1. What is genuinely pending (open roadmap items)

- **Milestone 5 (H4 · Surface system)**:
  Extract the surface query out of `player_controller.gd` into its own module; compaction op;
  footprints; **slope sliding** (the last open line of §3.1).
- **Milestone 6 (H6 · Player split)**:
  Motor / state / avatar / camera refactor. Pure refactor with no new behaviour, required
  before local/online co-op to cleanly separate input and body simulation.
- **Milestone 10 (H7 · Local duo)**:
  `Grabbable`, `TwoPersonCarry`, `Container`, `BallHandoff`, rescue. Two players on one machine
  to validate co-op verbs before netcode.
- **Architectural cleanup from Milestone 7**:
  `PlayerState` and `ImpactResolver` standalone extraction from `player_controller.gd` (the
  training dummy still duplicates parts of the impact resolution logic).

---

## 2. Done (solved sections & milestones)

### Diagnostics harmlessness (Task 1)
- **Problem**: Diagnostics previously wrote directly to `user://settings.json` and `user://bindings.json`,
  corrupting the player's real preferences (inverted mouse, volume lowered to 0.33, Space unmapped, pseudo-locale).
- **Fix** ([`228e10f`](https://github.com/JS-Marinn/snow-it-alone/commit/228e10f)):
  `scripts/settings_system.gd` and `scripts/input_bindings.gd` now use an overridable `static var path: String = PATH`.
  Every `--*-shot` diagnostic redirects `path` to scratch files (`user://scratch_settings.json`, `user://scratch_bindings.json`)
  before writing and deletes them on exit. `en_XA` pseudo-locale is strictly non-persistent and only offered when `OS.is_debug_build()`.
- **Evidence**: Verified by acceptance battery `--diagnostics-harmless` (`scripts/diagnostics_harmless_demo.gd`),
  registered in `tools/run_batteries.ps1` (71/71 OK, `Gpu = $false`).

### i18n extraction & Multilingual Typography (Milestone 8 / Task 2)
- **Problem**: Player-facing text was hardcoded across script and scene files; default fonts had no CJK coverage.
- **Fix** ([`8b65450`](https://github.com/JS-Marinn/snow-it-alone/commit/8b65450), [`4c9d96c`](https://github.com/JS-Marinn/snow-it-alone/commit/4c9d96c)):
  All UI text extracted to `res://locale/strings.csv` with English fallback (`en`). Hardcoded English removed from scene files
  and populated dynamically via `tr()` in `_ready()` and `refresh_text()`. Downloaded and configured Noto Sans family (OFL licence)
  with full Latin, Cyrillic, Greek, Japanese, and Korean glyph support.
- **Evidence**: `--i18n-check` battery passes cleanly (17/17 OK, `Gpu = $false`). Visual inspection via `--cjk-shot`
  confirms zero missing glyphs (tofu) in Japanese and Korean menus.

### Physics battery coverage restoration (Task 3)
- **Problem**: `scripts/physics_demo.gd` was reporting 34 checks instead of its full suite because thrown snowballs
  immediately swept against the thrower's collision/impact spheres on release, causing the ball to self-burst
  and free itself before `_s_carry_check` could inspect it. In addition, early return guards previously returned silently.
- **Fix** ([`642112a`](https://github.com/JS-Marinn/snow-it-alone/commit/642112a)):
  Added a 0.35s thrower grace period (`throw_grace_timer` and `thrower`) in `scripts/snowball.gd` so released balls ignore
  their carrier in both sweep hit detection (`_check_impact_hits`) and contact resolution (`_on_body_entered`).
  Added explicit failure checks on early return guards in `_s_carry_check` and `_s_ground_push_check`.
- **Evidence**: Restored full coverage for all declared checks: `the carried ball follows the player`,
  `the throw releases the ball with impulse`, `holding [E] pushes the ball along the ground`, and `holding [E] does NOT lift the ball`.
  The physics battery now runs 36 unique checks with 0 failures (36 OK / 0 FAIL), accounting for the 4 early-exit guard branches.

### Face snow presentation & settings wiring (Milestone 7 / Task 4)
- **Problem**: Face snow was only a static TextureRect overlay; audio was unaffected; camera shake preference and auto-clear
  were not respected at runtime.
- **Fix** ([`5fb5f1e`](https://github.com/JS-Marinn/snow-it-alone/commit/5fb5f1e)):
  Added fullscreen canvas_item shader on `_face_blind_rect` in `scripts/hud.gd` that blurs the scene via mipmap LOD and darkens
  with a cold snowstorm tint proportional to `face_snow_amount`. Added a dynamic `AudioEffectLowPassFilter` on the `AudioServer`
  Master bus muffling audio down to 600 Hz when blinded and restoring to 20000 Hz / disabled when cleared. Wired
  `SettingsSystem.screen_shake` to scale hit camera wobble in `player_controller.gd`. Wired `SettingsSystem.face_snow_auto_clear`
  live in `player_controller.gd` so runtime menu changes take effect immediately.
- **Evidence**: `--face-snow-shot` diagnostic runs windowed and verifies bus effect enabled (`cutoff=600.0 Hz`),
  overlay alpha (`0.95`), and saves screenshot (`res://face_snow.png`).

### Impact matrix & impact lab flakiness (Milestone 7 / Section 1 & 11)
- **Problem**: High-speed snowballs were resolved by continuous collision detection without triggering signals or were cancelled
  by solver contact before speed measurement, causing intermittent failures across identical runs.
- **Fix** ([`1591075`](https://github.com/JS-Marinn/snow-it-alone/commit/1591075)):
  Continuous sweep re-enabled for `PhysicsBody3D` with duplicate hit guard (`_hit_applied`), expanded hit spheres (0.55m lead margin),
  flight speed history protected from damping, and test arena cleanup fixed.
- **Evidence**: Both `--impact-lab` (18/18 OK) and `--impact-matrix` (28/28 OK) are 100% green and registered in the test gate.

### Pause menu, settings screen, controls rebinding (Milestone 9 / Section 8, 9, 10)
- **Fix** ([`8135e0d`](https://github.com/JS-Marinn/snow-it-alone/commit/8135e0d), [`f9f9c40`](https://github.com/JS-Marinn/snow-it-alone/commit/f9f9c40), [`ce79950`](https://github.com/JS-Marinn/snow-it-alone/commit/ce79950), [`05a2df2`](https://github.com/JS-Marinn/snow-it-alone/commit/05a2df2), [`a539d09`](https://github.com/JS-Marinn/snow-it-alone/commit/a539d09)):
  Escape genuinely pauses the scene tree (`_set_paused`), settings screen with persisted preferences (`_build_settings_panel`),
  controls rebinding screen (`_build_controls_panel`), and gamepad/Steam Deck stick look navigation.

### Resting large snowball contact burst & false impact
- **Problem**: When a player walked into a large snowball (`r = 0.45`) resting on the ground without throwing it,
  the snowball burst and knocked down the player.
- **Measured Cause**:
  1. Walking into the ball caused the solver/push to accelerate the ball forward (away from the player) to ~3.64 m/s.
  2. `_on_body_entered` measured `hit_speed := maxf(arrival_speed(), linear_velocity.length())`, which sampled the post-collision
     shoved velocity (`3.64 m/s`), exceeding `TIER_MIN_SPEED[LARGE] = 2.5 m/s` despite the ball having `0.0 m/s` pre-contact speed.
  3. `_check_impact_hits` sweep hit detection tested `_segment_sphere_hit` against the player's 1.0 m total hit sphere radius
     without checking if the segment was moving towards the target, triggering on balls already in proximity being pushed away.
  4. `_push_touched_bodies` in `player_controller.gd` called `other.push(pos, strength)` without passing `self`, preventing
     `pusher` and `push_grace_timer` from protecting the player walking into the ball.
  5. `_flight_max_speed` in `snowball.gd` persisted past drop/flight speeds indefinitely even while resting grounded.
- **Fix**:
  1. In `snowball.gd::_on_body_entered`, required incoming pre-contact velocity (`arrival`) to be directed towards the target
     (`approach = arrival.dot(to_target) > 0.0`) using 3D closest impact sphere direction, rejecting stationary or retreating balls.
  2. Evaluated `hit_speed := maxf(arrival_speed(), approach)`, eliminating solver shove acceleration from impact speed.
  3. In `_segment_sphere_hit`, rejected segments moving away from or parallel to the target sphere (`proj <= 0.0`).
  4. Reset `_flight_max_speed = 0.0` when resting on the ground in `_integrate_forces`.
  5. Passed `self` as `by_node` to `other.push()` in `_push_touched_bodies`.
- **Evidence**: Added `--contact-burst` dual regression battery to `tools/run_batteries.ps1` (12 batteries total, 232 checks, 100% ALL GREEN):
  verifies (a) walking into a resting large ball for 2.0s does NOT burst the ball and does NOT knock down the player, and
  (b) a large ball thrown at the player DOES burst and DOES knock down the player.

### Hand packing mass conservation & clean refusal (no mounds / no ghost harvesting)
- **Problem**: When attempting to pack a snowball by hand in an area with little or scarce snow, snow was removed from the terrain without creating a snowball, causing permanent mass loss in violation of the game's $\pm 0.05\%$ physical conservation guarantee. Furthermore, a naive fallback returning snow with `dump_snow()` caused a localized mound/bump where there was flat or scarce ground.
- **Measured Cause**:
  1. `scripts/player_controller.gd` previously had an arbitrary cutoff `pack_min_kg = 0.4 kg` in `_on_op_volume_ready`, rejecting yields $< 0.4$ kg.
  2. The physical minimum snowball mass corresponding to `MIN_RADIUS = 0.07 m` in `scripts/snowball.gd` is $(4/3)\pi (0.07)^3 \times 300 = 0.43498 \approx 0.435$ kg.
  3. A safety net calling `dump_snow(_pack_harvest_pt, kg, PACK_HARVEST_RADIUS)` on rejected yields preserved total field mass, but deposited a radial conical mound, visibly altering the terrain geometry on refused attempts.
  4. Global mass verification in tests ($\sum \Delta m = 0$) was blind to this spatial redistribution.
- **Fix**:
  1. **Strict pre-check authority**: `player_controller.gd::_estimate_available_snow_kg()` and `_find_pack_target()` act as the sole authority. It checks minimum snow depth ($h_0 > 0.045$, sample points $> 0.015$) and effective cut volume. If insufficient snow is within reach, no harvest op is queued, `status_message` displays `tr("STATUS_NOT_ENOUGH_SNOW")`, and the snow field is never touched.
  2. **Elimination of `dump_snow` fallback**: Removed all calls to `dump_snow()` on refusal. If the probe rejects, zero requests are sent to the simulation; no snow is removed, and no mounds are dumped.
  3. **Mathematical radius inversion**: `SnowBall.radius_for_packed_mass(kg)` inverts `mass_for_radius(r)` via 24-step bisection to $< 10^{-6}$ kg machine precision.
  4. **Local height invariance assertions**: Added probe height delta assertions ($\Delta h < 0.001$ m) in both cleared ground and scarce snow phases of `--hand-pack`.
- **Evidence**: Extended `--hand-pack` acceptance battery (`scripts/hand_pack_demo.gd`), registered in `tools/run_batteries.ps1` (`Gpu = $true`, 12/12 OK). Total test gate passes all 13 batteries (244/244 checks, 100% ALL GREEN).

---

## 3. Environment traps & method notes (paid for in lost time)

1. **The headless trap (`--headless`)**: Headless mode lacks a viewport and rendering pipeline. Any test or
   battery relying on `RenderingServer`, canvas item shaders, fullscreen blurs, viewport textures, or
   screenshots will crash, return null textures, or produce invalid results in `--headless`. Batteries that
   exercise visual effects or screen captures must specify `Gpu = $true` in `tools/run_batteries.ps1` so
   they run windowed.
2. **The sweep trap (physics tunneling & solver damping)**: Fast snowballs (5–8 m/s) easily tunnel through
   collision capsules in discrete physics ticks, and the physics solver frequently zeroes `linear_velocity`
   before `_on_body_entered` fires. Dedicated sphere-segment sweeping (`_check_impact_hits`) with speed history
   tracking (`arrival_speed()`) is mandatory to guarantee hit detection independent of solver frame timings.
3. **The fallback to `tr()` trap**: Never hand-roll an ad-hoc translation lookup map or custom string dictionary.
   Always use Godot's built-in `TranslationServer`, `tr()`, and standard CSV imports configured with
   `internationalization/locale/fallback = "en"`. With this configuration, any missing key or partial translation
   seamlessly falls back to English rather than producing blank labels or runtime errors. Diagnostic messages
   and log outputs (`print("[PHYS] ...")`) must stay in English and never be added to translation CSVs.
4. **The bindings trap (diagnostics stomping on the player)**: Automated diagnostics and screenshots must never
   write to the player's active preference files (`user://settings.json`, `user://bindings.json`). Always redirect
   `SettingsSystem.path` and `InputBindings.path` to scratch files (`user://scratch_settings.json`,
   `user://scratch_bindings.json`) before calling `save()` and delete them on exit. Pseudo-locales (`en_XA`)
   must never be persisted to disk.
5. **Never use `class_name` for a new script**: It registers a global in the editor's class cache. A command-line
   run before the cache indexes the file will fail with "Identifier not declared". Use `const X = preload("res://scripts/x.gd")`.
6. **Read a file before editing it**: In the AI workspace, tools require an active file read before making modifications.
7. **Measure first, change one thing, then measure three times**: Guessing causes churn and disproved four theories
   in a row during the impact flakiness bug. Instrument with clear log tags (`[HITDBG]`, `[BALLDBG]`) and verify.
8. **An absolute FPS threshold in a battery is a machine-state detector, not a performance gate**:
   The snow carving test is a smoke check (budget 40 FPS), not a precision benchmark. Machine load fluctuates between 53 and 118 FPS.
9. **PowerShell version is 5.1**: No `pwsh` on PATH, no `&` background operator, no inline `if` expression, no ternary,
   and piping a `foreach` statement is a syntax error.
10. **Non-ASCII characters get mangled by console encoders**: Match on ASCII-only patterns in scripts and test assertions.
11. **Never kill the user's Godot editor**: Match processes strictly by command line and terminate only the child instances you launched.
12. **Tooling note**: The `godot_ai` MCP addon registers a capture helper, but named pipes are blocked in this environment.
   Running with diagnostic flags, reading stdout/err logs, and inspecting saved PNGs is the reliable workflow.
13. **The safety net trap (untested side-effects and measurement blind spots)**:
   Al especificar una red de seguridad, hay que decir qué medición la delataría. Aquí se escribió «devuélvelo al campo» sin exigir una prueba de dónde vuelve, y la prueba que se pidió —masa total— era justo la que no lo iba a ver. Restaurar masa con `dump_snow()` conservaba la masa global ($\sum \Delta m = 0$) pero depositaba un montículo radial que distorsionaba la superficie donde había suelo raso. La regla de diseño correcta es la autoridad previa absoluta: no tocar el terreno si no hay suficiente nieve, y verificar la invarianza de altura local ($\Delta h_{\text{local}} = 0$) en la batería de pruebas.

