# Prompt: a large ball resting on the ground bursts when the player touches it

Hand this whole file over. It is self-contained, and it contains a failure to learn from.

---

You are working on **Snow It Alone** (working title "Snow It Together"), a co-op
snow-shovelling game in **Godot 4.7.2**, one programmer. Code, comments, UI and docs are in
**English**; reply in whatever language you are asked in.

- **Repository:** `C:\Users\MrSeb\.gemini\antigravity\scratch\snow_it_alone`
- **Godot:** `C:\Users\MrSeb\Downloads\Godot_v4.7.2-stable_win64.exe\Godot_v4.7.2-stable_win64_console.exe`
- **Run:** `& $godot --path $repo --quit-after 2400 -- --<flag>`

## The symptom, in the owner's words

> "The snowballs on the ground, if they are big, break on contact with the player without
> being thrown."

## Status: attempted twice, NOT fixed. Read this before changing anything.

- **`dc76e68` is committed and correct but insufficient.** It moved the burst *inside* the
  tier speed gate in both detection paths. Before it, any contact with a person burst the
  ball; now only a hit that *counts* does. The symptom persists, which means the ball is
  being *counted as hit* in the first place.
- **A second attempt was reverted.** It added a condition requiring the ball to be moving
  *towards* the person. It took `--impact-lab` from 18/0 to **7/18** and `--impact-matrix`
  from 28/0 to **16/28**. The reason is written at the bottom of this file as a trap: **do
  not repeat it without reading that.**
- Current state: `dc76e68`, tree clean, gate green (11 batteries, 228 checks).

## The four paths that can burst a ball

All in `scripts/snowball.gd`; find them by searching `_shatter(`.

| Line | Path | Its guard |
|---|---|---|
| 321 | `_integrate_forces`, the landing burst | `not was_grounded and absf(vn) > break_speed_threshold` (7.0, vertical) |
| 472 | the sweep in `_check_impact_hits` | inside the tier speed gate (since `dc76e68`) |
| 558 | the contact path in `_on_body_entered` | inside the tier speed gate (since `dc76e68`) |
| 563 | the generic branch of `_on_body_entered` | `speed > break_speed_threshold` (7.0, any direction) |

## The ruling hypothesis — a hypothesis, not a finding

`TIER_MIN_SPEED: Array[float] = [5.0, 3.5, 2.5]`. A **large** ball needs only **2.5 m/s** to
count as a hit. Walking into a big ball shoves it, and a shove may push its measured speed
over that, so the game concludes a real hit happened: the player is knocked down and, since
`dc76e68`, the ball bursts *legitimately*.

Look hard at **`arrival_speed()`**, which returns the **maximum of the last four frames**. A
short shove could leave a peak recorded even when the ball is nearly stationary at the moment
of contact. If that is what is happening, the gate is measuring a past peak rather than the
speed of arrival — and that would explain everything, including why raising no threshold has
helped.

## Do this, in this order

1. **Reproduce it as a diagnostic before changing any behaviour.** Add `--contact-burst`,
   registered in `tools/run_batteries.ps1` with `Gpu = $true`: place the player, spawn a
   **large** ball (`r = 0.45`) resting on virgin snow about 1.5 m ahead, walk the player into
   it with `Input.action_press("move_forward")` for 3 seconds, and record every frame the
   ball's speed, its four-frame maximum, its distance to the player, whether it burst, and
   from which call site. Print `[CONTACT] ...` lines plus a verdict.
   **Step 1 changes no behaviour.**
2. **Read the numbers and put the measured cause in the commit message**, not a theory.
3. **Then fix it**, deliberately choosing among these, and say which and why:
   - raise the LARGE tier's minimum (a design change — a heavy ball rolling into you *should*
     stagger you, so this is not obviously right);
   - require the ball to be genuinely **approaching**, using the **pre-contact** velocity;
   - mark the ball as *being pushed* and exclude it from reactions while pushed. The code
     already carries `push_grace_timer`, `throw_grace_timer`, `_push_target` and
     `_hit_applied` from an earlier fix — that machinery is the closest thing to this idea
     that already exists.
4. **Make the battery a real regression test, covering both directions:** a large ball resting
   on the ground with the player walking into it must **not** burst and must **not** knock the
   player down; a large ball **thrown** at the player must still do **both**. Either half
   alone would let the next fix break the other.

## The instrumentation that already exists

- `[BALLDBG]` in `_shatter` prints the radius, world position, speed **and the call site**
  (via `get_stack()`), so it names the function that killed the ball.
- `[HITDBG]` in the contact path prints the ball radius, tier, measured hit speed, that
  tier's minimum, the target's name, and its `hit_state` and `hit_immunity`.
- `[THROWDBG]` (if present) prints the throw's angle off the crosshair.

Use them. They were added for exactly this kind of question and they cost nothing.

## The trap that broke the last attempt

In `_on_body_entered`, the contact is reported **after the solver has already cancelled the
ball's velocity**. So `linear_velocity` there is the *post-collision* value and frequently
points **away** from the player. That is the entire reason `_prev_velocity` and
`arrival_speed()` exist.

A directional test written on `linear_velocity` in that branch refuses genuine hits. Measured:
it dropped `--impact-lab` to 7/18. Use the pre-contact velocity for anything directional, and
if a direction test still refuses real hits, **stop and measure rather than adjusting
thresholds**.

## Never break these

| Battery | Must stay at |
|---|---|
| `--impact-lab` | 18 OK / 0 |
| `--impact-matrix` | 28 OK / 0 |
| `--phys-demo` | 36 OK / 0 |
| `--beetle-roll` | 6 OK / 0 |
| the whole gate | ALL GREEN |

Never commit on red. If a change makes one of these fail, that is information, not an
obstacle — decide whether the change is wrong or the check is, and say so in the commit.

## Rules that have cost the most time here

1. **Read a file before editing it.** The editor requires a prior read; bulk text replacement
   while it is blocked invalidates that and cascades. Four files were invalidated in one
   session and one mistake left the game unable to start.
2. **Never `class_name` in a new script** — it needs the editor's class cache and a
   command-line run then fails with "Identifier not declared". Use `const X = preload(...)`.
3. **Measure first, change one thing, then measure three times.** A single run of a battery
   has twice proven worthless here.
4. **A battery that hangs or aborts without a verdict is a FAILURE.** A hang is a symptom.
5. **PowerShell 5.1**: no `pwsh`, no `&`, no inline `if` expressions, no ternary, and piping
   a `foreach` statement is a parse error.
6. **Non-ASCII is mangled when the console reads your command**, so an anchor with an arrow
   never matches. Use ASCII-only anchors and `[char]0x2192` for symbols.
7. **Never kill the user's Godot editor.** Kill only what you started, matched by command line.
8. **No MCP tools reach you.** Use the log and `read_image`.

## Definition of done

`--contact-burst` registered and covering both directions, the whole gate green, and a commit
message that states the **measured** cause. If the cause turns out to be something not listed
here, that is fine — say what it was.
