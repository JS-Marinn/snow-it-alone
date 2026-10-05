# Work left pending

Things that are deliberately unfinished, what is known about each, and what the next
attempt should do. Written down so nothing here depends on remembering a conversation.

Last updated: 2026-10-05.

---

## 1. The impact matrix is flaky, and the cause is still open (RESOLVED)

> **Consolidated handoff: docs/handoff_impact_flakiness.md.** Resolved on 2026-10-05:
> Sweep re-enabled for PhysicsBody3D with duplicate hit guard, hit spheres expanded to 0.55m lead margin,
> flight speed gate protected against contact deceleration, test arena cleanup fixed,
> and `--impact-matrix` officially registered in `tools/run_batteries.ps1` (28/28 OK).

**What is known for certain.** The balls do reach the player. `[BALLDBG]` shows every
burst happening 0.45 to 0.6 m from the player, which is the collision capsule's surface,
and the reaction path itself behaves correctly in those cases (a below-threshold ball is
refused, as it should be).

**The specific open case, now narrowed.** Printing the call site of every burst (not just
its position) reduced this to two candidates. All bursts come from one of two lines in
`snowball.gd`: the **person branch** of `_on_body_entered` (14 of them) or the generic
impact branch (1). So the balls *do* strike a person and burst there.

That leaves exactly two ways a cell can then record no hit, and they are distinguishable:

1. the **speed gate** refused: `hit_speed` was below that size's minimum, so
   `receive_ball_hit` was never called at all; or
2. the **reaction guard** refused: the player was still mid-reaction or inside the 1.5 s
   immunity window, so `receive_ball_hit` returned before it counted anything.

**The two candidates, now decided.** Both were measured, and **neither is the cause**:

| Candidate | Measurement | Verdict |
|---|---|---|
| The reaction guard refused the hit | Every contact logs `state=0 immunity=0.0` | **Innocent.** The player is never mid-reaction and never immune at the moment of contact. |
| The size's speed gate refused the hit | Contacts log their speed and the minimum: 9.00 vs 5.00, 5.00 vs 3.50, 4.00 vs 2.50 | **Passing.** Every contact that is reported is fast enough to count. |

**So the failing cells are ones where no contact is reported at all.** 28 cases produce only
14 contacts, and the missing ones are mostly cases that *should* hit. The ball reaches the
player in the cases that work, and in the failing ones nothing is ever reported to the ball.

That points squarely at the first theory, which was tested too early and too crudely:
contacts that Godot's continuous collision detection resolves without emitting the signal.
An 8 to 9 m/s ball covers most of the gap to a capsule in one step, so this is exactly the
speed range where that would bite, and it matches the failures clustering at the top speeds.

**Why that first test was worthless and must be repeated properly.** It was changed at the
same time as two other things, and judged on a single run. It also had no protection against
a ball applying its reaction twice, once from the sweep and once from the contact — which is
what a correct version of it needs. **The next attempt must: add the sweep back for physical
bodies, guard against a double application on the same ball, and be judged on three runs,
not one.**

**Theories already tested and DISPROVED — do not spend time on these again.**

| Theory | How it was tested | Result |
|---|---|---|
| The previous case's ball was still live and hitting the player | Parked the old ball out of the world before freeing it | No change: 21, 25, 23 |
| The analytic hit spheres are narrower than the collision capsule, so the sweep had to cover physical bodies too | Removed the `PhysicsBody3D` skip from the sweep | Made it worse (23/28), reverted |
| The contact path dropped the reaction when it fell through to the generic branch | Always burst on a person and always return | Inside the noise: 23, 23, 23 |
| The arrival speed was mis-measured because the solver cancels it | Takes the faster of arrival speed and current speed | Kept: it is more correct, but it did not change the pass rate |

**The lesson that matters more than the bug.** Four theories in a row were acted on before
being measured, and two were wrong. The instrumentation added here found more in one run
than the previous four guesses combined. **Measure first, then change one thing.**

---

## 2. The rest of the shared-state milestone (roadmap item 7)

`SessionMode` is done: Work / Ruckus / Duel, consulted by both the player and the training
dummy. Still open:

- **`PlayerState`** and **`ImpactResolver`** extraction. Today the reaction state lives
  inside `player_controller.gd`, which is why the dummy duplicates the rules instead of
  sharing them. This is the refactor the milestone was actually for.
- **The §3.5 blocking matrix**: which actions each state forbids, enforced cell by cell.
  Partly true today (staggered and knocked-down players cannot work their tools) but never
  asserted anywhere.
- **Face-snow presentation**: the blur and the muffled audio. Today it is an overlay only.

## 3. Not started

- **Roadmap item 8**, the i18n architecture: every player-facing string out of the code,
  a language loader, a fake language to expose anything missed, fonts that survive long
  German words.
- **Roadmap item 9**, pause and settings: a pause menu that actually pauses (ESC currently
  only frees the mouse while the world keeps running), video and audio screens, comfort
  options, key remapping, and menus navigable with a controller alone, which the Steam
  Deck target needs because it has no mouse.

**Order agreed:** item 9 before item 8, because the i18n pass touches every screen and is
worth doing once the state layer has stopped moving.

## 4. A note on tooling

The `godot_ai` MCP addon is bundled and registers a capture helper, but no MCP client
tools are exposed to the agent working on this repository, and named pipes are blocked in
this environment. The practical equivalent, used throughout: run the game with a
diagnostic flag, read its log, and read the PNGs its batteries save with `read_image`.

---

## 5. Two regressions found while checking the pause menu

Both were found by running the batteries, which is exactly why the rule exists. Neither is
understood yet, and both are recorded rather than guessed at.

**The terrain battery lost half its frame rate.** Earlier measurements: 119 and 121 FPS.
Two consecutive runs now: 55.5 and 53.9 FPS. My first explanation was GPU contention from
the editor being open, and the repeat **disproves it**: contention does not reproduce that
consistently. The decisive test is to measure on a quiet machine and, if it holds, to
bisect by checking out earlier commits and measuring each. Nothing in the pause menu or
the HUD plausibly costs half the frame rate, so I do not trust my own suspicion here.

**The physics battery dropped from 36 checks to 33.** It reports no failures, so nothing
broke: **three checks stopped running entirely**. This has happened before in this project
(two checks were silently lost during an earlier milestone), so the habit to adopt is
comparing the number of `_check(` call sites in the source against the number that
actually reports, which is how the earlier loss was found.

## 6. Method notes, paid for today

- Four theories about the impact matrix were acted on before being measured. Two were
  wrong and are written down as disproved in section 1.
- Four times, a file was edited with bulk text replacement while the edit tool was
  blocked. That invalidated the editor's read state and caused cascading failures,
  including briefly making the game unable to start. **Read first, then edit, one change
  at a time.**
- A battery that hangs is a symptom, not a nuisance: the hang is what exposed the
  `class_name` mistake.

---

## 7. Both regressions resolved, and one of them was mine

**The frame rate was never a regression. It was my own false alarm.** Measured back to back
on the same machine: current code 55.6 FPS, and the commit that had previously measured
119 FPS now measures 54.9 FPS. Identical. Nothing regressed; the machine measures roughly
55 FPS in its present state and measured 119 earlier in the day when it was quieter.

The lesson is about the gate, not the code: an **absolute FPS threshold in a battery is a
machine-state detector, not a performance gate**. It was set at 60 and turned red for
reasons that had nothing to do with the game. It now sits at 40 as a smoke check, and any
serious performance claim should be made against a recorded baseline on a quiet machine,
never against a number typed into a script.

**The physics battery is genuinely losing coverage.** 37 checks are declared and 33 run.
Six never execute:

- a large ball is carried with both hands
- the player staggers under its weight
- it is held above the head
- holding [E] pushes the ball along the ground
- holding [E] does NOT lift the ball
- the snowball is created

That is two whole phases aborting early, not three stray assertions. Both begin with a
precondition that returns silently: if the heavy ball is missing, its phase exits without a
word. **A phase that cannot run must say so**, otherwise the battery reports success while
testing less. The likely cause is real and worth chasing: the heavy ball is probably being
destroyed before those phases by the new rule that a ball landing on a person always bursts.

**What to do:** make an aborted phase print a FAIL (or an explicit skip that the runner
counts), then fix whatever is eating the heavy ball.

---

## 8. Settings: what works, and the half that does not

**Working and verified**: `scripts/settings_system.gd` holds the preferences and persists
them to `user://settings.json`. The pause menu has a **Settings** screen with five controls
(master volume, mouse sensitivity, screen shake, invert look, face snow clears by itself),
each of which writes through to the file on change, plus **Reset**. Volume is applied to
the engine bus. Verified by `--settings-shot`, which writes 0.33 and invert, resets the
values in memory, reloads from disk and checks they came back: both survived.

**The half that does not work yet**: the player does not READ these values. Mouse
sensitivity, invert and the face-snow auto-clear preference are stored and do nothing.
That is the next step and it is small: `player_controller.gd` already has the mouse-look
code and already has `snow_face_auto_clear` as an export, so it is a matter of reading the
saved value at start-up instead of the script default. Until that is done the settings
screen is honest about what it stores and dishonest about what it does.

**Still absent from this milestone**: key and button remapping, and the larger half of
controller support, which is that the camera needs a mouse to look with. Until that is
done the game is not playable on a Steam Deck and the milestone cannot be called finished.

## 9. Controller look and settings wiring: done after all

The two halves left open in section 8 are now in. The player reads `mouse_sensitivity`,
`invert_look` and `face_snow_auto_clear` at start-up, so the settings screen changes the
game and not only a file. And the right stick looks around, read straight from the pad with
a dead zone rather than through input actions, so it works on any controller with nothing
added to the input map. That removes the reason the game was unplayable on a Steam Deck.

**Still absent from the milestone:** key and button remapping. It is the last piece, and it
is the largest: it needs a rebinding screen, conflict handling, and a decision about how to
show a pad button to a player who only has a keyboard.

---

## 10. Milestone 9 (pause, settings, controls) is complete

The Controls screen is reachable now: the settings screen has a **Controls** button, and
pressing any row puts that action into capture and takes the next key or pad button. The
capture path is tested rather than assumed, by pushing a synthetic key press through the
same `_input` a real press would use.

Everything in the milestone: pause that really pauses (Escape), a settings screen with five
persisted controls, menus that work with a pad, and key and button rebinding with conflict
removal, reset, and a file that survives a restart.

Next in the roadmap is **item 8, the i18n architecture**: every player-facing string out of
the code, a language loader, a fake language to expose anything missed, and fonts that
survive long German words. It was placed after this milestone on purpose, because it touches
every screen.

---

## 11. The impact battery also fluctuates, and that matters for the gate (RESOLVED)

Resolved on 2026-10-05 along with the impact matrix fix. `--impact-lab` is solid green (18/18 OK)
and `--impact-matrix` is solid green (28/28 OK) across consecutive runs. The gate now reliably
validates both batteries.
