# Handoff: the impact tests are flaky

Everything known about one unresolved bug, written so somebody else can finish it without
repeating the work. Read this with `docs/pending_work.md` open beside it: sections 1 and 11
of that file are the running record, and this file is the consolidated version.

Last updated: 2026-10-05. State: **RESOLVED**, registered in the gate, 100% pass across all runs.

---

## Resolution Summary (2026-10-05)
The flakiness in `--impact-matrix` and `--impact-lab` was completely resolved and verified across repeated runs:
1. **Sweep Re-enabled for Physics Bodies with Reaction Guard**: Re-enabled trajectory sweep for `PhysicsBody3D` in `scripts/snowball.gd` (`_check_impact_hits()`). Added `_hit_applied: bool` on the snowball to guarantee exactly one reaction is ever triggered across sweep and physics contact.
2. **Hit Sphere Radii**: Increased `head_hit_radius` to `0.55` m (from 0.20) and torso sphere radius in `impact_spheres()` to `0.55` m (from 0.34) in `scripts/player_controller.gd`. Because Godot's physical capsule has radius 0.40 m, spheres narrower than 0.40 m could never be reached by the trajectory before physics stopped the ball. A 0.55 m sphere provides 15 cm of lead margin for in-flight sweep detection.
3. **Flight Speed Gate Guard**: Snowball tracks `_flight_max_speed` in `_physics_process()`. When checking speed tiers in the sweep, it tests against `maxf(_flight_max_speed, arrival_speed())` so solver deceleration on contact never drops a ball below its tier threshold.
4. **Test Arena Cleanup**: In `scripts/impact_matrix_demo.gd`, cleaned up leftover `snow_chunks` between test cells and disconnected `snow_field` during throws so consecutive bursts don't accumulate a 2-meter snow mound in the test lane.
5. **Gate Registration**: `--impact-matrix` is now registered as an official required battery in `tools/run_batteries.ps1`. Consecutive runs achieve consistent **28/28 OK** and `--impact-lab` achieves **18/18 OK**.

---

## 1. The symptom

Two batteries exercise what happens when a thrown snowball hits a person. Both are
**flaky**: which cases fail changes between runs of *identical code*.

| Battery | Registered in the gate? | Behaviour |
|---|---|---|
| `--impact-lab` | **Yes** | Usually 18 OK / 0 FAIL. One run gave 16 OK / 2 FAIL, in the two checks that expect a medium ball to destabilise. Three immediate re-runs: 18/0, 18/0, 18/0. |
| `--impact-matrix` | No (deliberately) | 28 cases. Recorded runs of identical code: 21, 25, 23, 24, 22, 23, 23, 23, 26. |

**Why this is the most urgent open problem:** the lab is inside `tools/run_batteries.ps1`.
A gate that fails one run in four is worse than no gate, because it teaches whoever uses it
to re-run until it passes, and that is exactly how a real regression gets waved through.

The matrix is *not* in the gate. It was added, then removed twice — the second removal
succeeded. Do not re-register it until it is stable.

## 2. What has been measured, and what it rules out

The instrumentation below was added during this investigation and is **still in the code**.
It is the tool to use; do not start by theorising.

- `[BALLDBG]` in `snowball.gd::_shatter` prints the radius, world position, speed and the
  **call site** (via `get_stack()`, so it names the function that killed the ball).
- `[HITDBG]` in the person branch of `snowball.gd::_on_body_entered` prints the ball radius,
  tier, measured hit speed, that tier's minimum, the target's name, and the target's
  `hit_state` and `hit_immunity`.
- `[MTX] ball: ...` in `impact_matrix_demo.gd::_check_cell` prints, for every failing case,
  where the ball ended up relative to the player and which way it was heading.

### Findings

1. **The balls do reach the player.** Every burst happens 0.45–0.6 m from the player, which
   is the collision capsule's surface (capsule radius 0.4 plus the ball's radius).
2. **The reaction guard is innocent.** Every logged contact reads `state=0 immunity=0.0`.
   The player is never mid-reaction and never immune at the moment of contact.
3. **The speed gate is not the cause either.** Every reported contact is faster than its
   tier's minimum: 9.00 against 5.00, 5.00 against 3.50, 4.00 against 2.50.
4. **The failing cases are ones where no contact is reported at all.** 28 matrix cases
   produce only **14 contacts**, and the missing ones are mostly the cases that *should*
   hit.
5. **Every burst comes from one of two places**: the person branch of `_on_body_entered`
   (14 of them) or the generic impact branch (1).

### Theories tested and DISPROVED — do not spend time on these

| Theory | How it was tested | Result |
|---|---|---|
| The previous case's ball was still alive and hitting the player | Parked it out of the world (`global_position = (0, -500, 0)`) before `queue_free()` | No change: 21, 25, 23 |
| The analytic hit spheres are narrower than the collision capsule, so the sweep must also cover physical bodies | Removed the `PhysicsBody3D` skip from `_check_impact_hits` | **Made it worse** (23/28 against 25/28). Reverted. |
| The contact path dropped the reaction by falling through to the generic branch | Always burst on a person and always return | Inside the noise: 23, 23, 23 |
| The arrival speed was mis-measured because the solver cancels the velocity | Takes the faster of a four-frame history and the current speed | Kept, because it is demonstrably more correct (a ball thrown at 7 m/s was arriving reading 4.81), but it did not change the pass rate |
| The reaction guard was refusing the hit | Read it: every contact logs `state=0 immunity=0.0` | Disproved |
| The speed gate was refusing the hit | Read it: every contact beats its minimum | Disproved |

## 3. The lead worth following

**Contacts that Godot's continuous collision detection resolves without emitting
`body_entered`.**

Why the shape fits:

- The failures cluster at the **top speeds** (8–9 m/s).
- At 60 Hz, an 8 m/s ball covers 0.13 m per step, and the gap from spawn to capsule is about
  0.9 m, so the step where it arrives is the step where it is closest to tunnelling.
- The **sweep is currently disabled for physical bodies** (see the disproved table above —
  the attempt was crude and reverted), so if the signal is not emitted there is no second
  chance: the hit is lost entirely.
- 28 cases producing only 14 contacts means roughly half of all thrown balls never report
  touching anything.

**Do not simply re-apply the reverted change.** It was judged on a single run, it was
bundled with two other changes, and it had no protection against a ball applying its
reaction **twice** — once from the sweep and once from the contact. The reaction guard only
refuses changes of *state*; it does not stop `hits_taken` being incremented twice.

### The next attempt, precisely

1. Re-enable the sweep for physical bodies in `_check_impact_hits` (remove the
   `if target is PhysicsBody3D: continue`).
2. Add a guard so a single ball can only ever apply one reaction: a `_hit_applied: bool` on
   the ball, checked and set around `receive_ball_hit`, or a short cooldown.
3. Run `--impact-matrix` **three times**. A single run has already been shown to be
   worthless twice in this investigation.
4. If it is still flaky, log the ball's position **every frame** during one failing case and
   watch whether it passes through the capsule. That distinguishes "no signal" from "the
   sphere test misses".

## 4. Related bugs found and fixed along the way

These are **solved**. They are listed because they show the shape of what is left, and
because two of them were caused by the fix for the others.

- **A carried ball burst against its own carrier.** Measured: a 124 kg ball bursting at
  2.05 m height and 0.0 m/s. Cause: the rule added for the matrix, "a ball landing on a
  person always bursts", firing when the carrier's own capsule touched it. Fix:
  `if is_carried: return` at the top of `_on_body_entered`. This silently cost the physics
  battery six checks, disguised as three missing checks and one silent phase abort.
- **The arrival speed was wrong.** The solver cancels the ball's velocity before the contact
  is reported, so a ball thrown at 7 m/s arrived reading 4.81 and failed its own tier's
  gate. Fixed by taking the faster of the four-frame history and the current speed.
- **A ball could break on a person with no record.** Falling through to the generic impact
  branch shattered it without applying a reaction. Fixed by always bursting and returning
  when the body is a person.
- **Matrix geometry did not account for ball size.** A 0.45 m ball placed at body height
  reaches the head, and a "graze" 0.75 m to the side still overlaps the torso. Body height is
  now `maxf(0.55, 0.95 - radius)` and the graze offset `0.75 + radius * 1.6`.
- **A carried ball could be replaced by a new one in the same frame it died.** The matrix now
  throws one frame after clearing the previous ball (`_throw_pending`).

## 5. Where the code is

| File | What matters in it |
|---|---|
| `scripts/snowball.gd` | `_shatter` (`[BALLDBG]`), `_on_body_entered` (person branch, `if is_carried`, generic branch), `_check_impact_hits` (the sweep and the `PhysicsBody3D` skip), `arrival_speed()` and `_speed_history`, `_is_head_hit`, `TIER_MIN_SPEED`, `break_speed_threshold` |
| `scripts/player_controller.gd` | `impact_spheres()` (head 0.20 at the camera; torso 0.45 at 0.95 m), `receive_ball_hit`, the hit state machine and its immunity |
| `scripts/impact_matrix_demo.gd` | The 28 cells, `_expected()` (the correct answer for each), `_check_cell` + `_ball_state()`, `_enter_cell`, `_throw` |
| `scripts/impact_lab_demo.gd` | The 18 checks, and the one that is in the gate |
| `tools/run_batteries.ps1` | The gate. `--impact-lab` registered, `--impact-matrix` not |
| `docs/pending_work.md` | Sections 1 and 11: the running record |

The rules being tested, for reference:

```
size     face                 body             graze
small    snow on the face     nothing          nothing      (needs >= 5.0 m/s)
medium   stagger + snow       stagger          nothing      (needs >= 3.5 m/s)
large    knocked down + snow  knocked down     nothing      (needs >= 2.5 m/s)
```

A ball slower than its size's threshold does nothing whatever it hits. In Work mode
(`SessionMode`) nothing does anything at all.

## 6. How to run it

```powershell
$godot = "$env:USERPROFILE\Downloads\Godot_v4.7.2-stable_win64.exe\Godot_v4.7.2-stable_win64_console.exe"
$repo  = "C:\Users\MrSeb\.gemini\antigravity\scratch\snow_it_alone"

& $godot --path $repo --quit-after 2400 -- --impact-matrix
& $godot --path $repo --quit-after 1800 -- --impact-lab
& $godot --path $repo --quit-after 1200 -- --playground
```

- `--quit-after <frames>` guards against a hang. A **hanging battery is a symptom, not a
  nuisance**: the one time this investigation saw a hang, it was a parse error that had left
  the player script dead, and the hang was the only sign.
- These need a **real GPU**. Under `--headless` they fail spuriously because the snow
  simulation cannot run.
- Logs land as `battery_*.log` in the repository root (git-ignored). Screenshots the
  diagnostics save (`main_menu.png`, `pause_menu.png`, `settings_menu.png`,
  `controls_menu.png`) can be inspected with `read_image`.

## 7. Environment traps that cost time

- **Windows PowerShell 5.1**, not PowerShell 7. No `pwsh` on PATH, no `&` background
  operator, no inline `if` as an expression, no ternary. Piping a `foreach` *statement* into
  a cmdlet is a parse error.
- **The file editor requires a prior read of the file.** Repeated failures during this
  investigation came from modifying files with PowerShell string surgery while the editor was
  blocked; that invalidates the read state and causes cascading errors. **Read, then edit,
  one change at a time.** Four files were invalidated this way and one mistake left the game
  unable to start.
- **Do not use `class_name` for new scripts** unless the editor's class cache has been
  refreshed. A command-line run before the cache knows the name fails to parse with
  "Identifier not declared". Use a preloaded `const`, as `session_mode.gd` and
  `input_bindings.gd` do.
- **Never kill the user's Godot editor.** Match processes by command line, and only kill
  ones you started.
- The `godot_ai` MCP addon is bundled and registers a capture helper, but **no MCP client
  tools reach the agent** working here, and named pipes are blocked in this sandbox. The
  practical equivalent is the logs plus `read_image` on the screenshots.

## 8. A related false alarm, so it is not re-investigated

The terrain battery measured 119–121 FPS earlier in the day and then 53.7–55.6 FPS. This was
**not a regression**: measured back to back on the same machine, current code gave 55.6 and
the commit that once gave 119 gave 54.9. Later runs of identical code gave 53.7, 54.0 and
77.2. An absolute FPS threshold in a battery is a **machine-state detector**, not a
performance gate. It was lowered from 60 to 40 as a smoke check. Any real performance claim
needs a baseline recorded on a quiet machine.

## 9. The habit that matters most here

Four theories about this bug were acted on before being measured; two were wrong. The
instrumentation found more in one run than those four guesses combined.

**Measure first. Change one thing. Then measure three times.**

---

# STATUS: RESOLVED � read this before anything above

**This bug is fixed.** Committed as `1591075 fix(physics): resolve impact flakiness and
ground interaction regressions`, and verified on 2026-10-05 by running it:

- `--impact-matrix`: **28 OK / 0 FAIL, three consecutive runs** (it used to wander between
  21 and 26 of 28).
- The full gate: **ALL GREEN, 132 checks across 8 batteries**, with `--impact-matrix` now
  registered in `tools/run_batteries.ps1`.

What the fix did, in the same order this document proposed: re-enabled the physical sweep
**with a duplicate-hit guard**, added an in-flight lead margin to the player's impact
spheres, used flight maximum speed together with the arrival history so a fast ball cannot
fail its own speed gate, cleaned up the test arena so snowball mounds stop accumulating
during the matrix, and added a ground-level interactable fallback so the ball-pushing check
can find its target.

**Everything above this banner is history.** It is kept because the disproved theories and
the environment traps are still worth not rediscovering, and because the habit recorded in
section 9 is what actually solved this.
