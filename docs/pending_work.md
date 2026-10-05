# Work left pending

Things that are deliberately unfinished, what is known about each, and what the next
attempt should do. Written down so nothing here depends on remembering a conversation.

Last updated: 2026-10-05.

---

## 1. The impact matrix is flaky, and the cause is still open

**What it is.** `--impact-matrix` walks every combination the design specifies: three ball
sizes × three zones (face, body, graze) × three speeds, plus Work mode. 28 cases.

**Where it stands.** Roughly 4 of the 28 fail, and **which four changes between runs**.
Measured, identical code: 21, 25, 23, 24 out of 28. Because the failures wander, this is
a flaky battery rather than a wrong one, and it is **not registered in
`tools/run_batteries.ps1`**: a flaky gate is worse than no gate.

**What is known for certain.** The balls do reach the player. `[BALLDBG]` shows every
burst happening 0.45 to 0.6 m from the player, which is the collision capsule's surface,
and the reaction path itself behaves correctly in those cases (a below-threshold ball is
refused, as it should be).

**The specific open case.** `small / body / 6.0 m/s` fails with no hit recorded, and the
diagnostic shows that ball bursting at **5.0 m/s**. That is below the 7 m/s threshold the
generic impact branch uses, so that branch cannot be what broke it, and the burst is not
the player contact either. Something else is destroying these balls, and the next
measurement should be to print the call site of `_shatter` rather than only its position:
the position says where it died, not who killed it.

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
