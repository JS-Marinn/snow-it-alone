# Prompt: make pushing a snowball grow it, like a beetle rolling dung

Hand this whole file to whoever implements it. It is self-contained.

---

You are working on **Snow It Alone** (working title "Snow It Together"), a co-op
snow-shovelling game in **Godot 4.7.2**, built by one programmer. Code, comments, UI text
and documentation are all in **English**. Your replies may be in any language.

- **Repository:** `C:\Users\MrSeb\.gemini\antigravity\scratch\snow_it_alone`
- **Godot:** `C:\Users\MrSeb\Downloads\Godot_v4.7.2-stable_win64.exe\Godot_v4.7.2-stable_win64_console.exe`
- **Run pattern:** `& $godot --path $repo --quit-after 2400 -- --<flag>`

## The request, in the owner's words

> "Make the snowball push like a dung beetle. Right now, holding **E** pushes the ball and it
> goes far away, but the goal is to make it grow progressively."

## What happens today

- `player_controller.gd::_ground_push()` runs every physics frame while **E** is held (after
  `interact_hold_time`, 0.25 s) and calls `snowball.gd::push(player_position, strength)`.
- `push()` applies `apply_force(dir * force, grip)` where
  `force = min(strength * PUSH_FORCE_NEWTONS, PUSH_MAX_ACCEL * mass)` — currently up to
  **260 N**, or 26 m/s² times mass.
- Nothing caps the speed that force can reach. A 25 kg ball accelerates away at roughly
  10 m/s² and leaves the player behind, so the player chases it instead of rolling it.
- **The growth system already exists and works.** `_try_harvest()` gathers snow into the ball
  as it rolls (`HARVEST_STEP`, `accretion_efficiency = 0.75`, `request_harvest` on the field),
  density rises with rolling (`LOOSE_DENSITY 150` → `PACKED_DENSITY 300` →
  `PACKED_DENSITY_COMPACT 470`), and radius grows up to `MAX_RADIUS = 0.55`.

**So the growth is not the missing part — the control is.** The ball must roll *with* the
player at a pace that lets it gather snow, instead of being launched.

## The design to implement

1. **Push towards a rolling speed, not with a raw force.** Introduce a target rolling speed
   (start at 1.8 m/s) and apply force only while the ball's speed *along the push direction*
   is below it. Above that, apply nothing. This alone fixes the escape.
2. **Make it get harder as it grows, which is the beetle idea.** Scale the target speed down
   with mass: `target = PUSH_SPEED * clamp(ref_mass / mass, 0.45, 1.0)`. A small ball rolls
   easily; a 100 kg one is a slow business. Keep a floor so it never stalls on a slope.
3. **Keep the roll, do not convert the push into a slide.** `push()` already applies the force
   at a grip point *below* the centre (`radius * 0.45`), which is what makes the ball roll
   forward rather than skid. Preserve that, and verify the angular velocity actually matches
   the rolling constraint (|v| ≈ |ω| · radius within tolerance).
4. **Keep the ball in front of the player.** Add a soft positional correction: if the ball has
   been pushed and ends up further than about 3 m away, stop pushing (the player must walk
   after it). If it is closer than about 1 m, do not push at all — pushing a ball you are
   standing on is what launches it.
5. **Grow on distance rolled, which is already how the harvest works.** Do not add a second
   growth path. If the growth per metre feels too slow, tune `accretion_efficiency` and the
   harvest radius, and say so in the commit.
6. **Feedback.** The player must be able to see progress. The ball's radius is visible; add
   the pushed ball's mass to the HUD hint line while it is being pushed (`label_toss_hint`
   already carries contextual text). Keep it in English and untranslated until the i18n pass
   covers it (see `docs/spec_i18n.md`).
7. **Do not break the existing checks in `--phys-demo`** (ground push, heavy carry, energy
   throws). If the behaviour change makes one of them wrong, **update the check deliberately
   and say so in the commit** — do not delete it.

## Where to change the code

| File | What |
|---|---|
| `scripts/snowball.gd` | `push()`, and add the target-speed logic. Constants live at the top (`PUSH_FORCE_NEWTONS`, `PUSH_MAX_ACCEL`): add `PUSH_SPEED`, `PUSH_MIN_SPEED`, `PUSH_REF_MASS`, `PUSH_REACH_MIN`, `PUSH_REACH_MAX` |
| `scripts/player_controller.gd` | `_ground_push()` calls `push()`; pass the player's forward direction or read it from `global_position`, and enforce the distance window. `ground_push_strength` is an export — retune or replace it |
| `scripts/hud.gd` | The pushed mass in `_update_hint()` |
| `scripts/physics_demo.gd` | Extend the ground-push phase, or add the new battery below |

## Acceptance test — a battery, not an opinion

Add `--beetle-roll` and register it in `tools/run_batteries.ps1` (`Gpu = $true`, it needs the
snow simulation). The scenario: place the player on virgin snow, spawn a small ball in front,
press and hold `interact` with `_push_target` set (this is how `--phys-demo` already drives it),
and sample every frame for 12 seconds. It must check, at minimum:

1. **It does not escape.** The ball's distance from the player never exceeds ~3.5 m.
2. **It rolls.** The maximum speed reached stays within 15 % of the target for the ball's mass.
3. **It rolls rather than slides.** |v| matches |ω| · radius within 20 % while moving.
4. **It grows progressively.** Radius after 12 s is measurably larger than after 2 s, and the
   growth is monotonic in the samples (no shrinking).
5. **It gets harder as it grows.** The mean push speed in the last 4 seconds is lower than in
   the first 4.
6. **It does not stall.** The ball is still moving at the end, and its radius is above its
   starting radius by a stated threshold.

Print `[BEETLE] RESULT: N OK / M FAIL`. A battery that cannot set itself up must report a
failure, not return silently — this project has lost coverage that way before.

## Verification, before the commit

```powershell
& $godot --path $repo --quit-after 2400 -- --beetle-roll
& $godot --path $repo --quit-after 2400 -- --phys-demo
& "$repo\tools\run_batteries.ps1"     # must print ALL GREEN. Never commit on red.
```

Commit as: `feat: pushing a ball rolls it and grows it instead of launching it`

## Rules that have cost the most time here

1. **Read a file before editing it.** The editor requires a prior read; bulk text replacement
   while it is blocked invalidates that and causes cascading failures. Four files were
   invalidated in one session and one mistake left the game unable to start.
2. **Never `class_name` in a new script.** It needs the editor's class cache; a command-line
   run then fails with "Identifier not declared". Use `const X = preload("res://scripts/x.gd")`.
3. **Measure first, change one thing, then measure three times.** A single run of a battery has
   twice been shown to be worthless in this project.
4. **A battery that hangs or aborts without a verdict is a FAILURE.** A hang is a symptom:
   the one time it happened it was a parse error that had left the player script dead.
5. **PowerShell here is 5.1**: no `pwsh`, no `&`, no inline `if` expressions, no ternary, and
   piping a `foreach` statement is a parse error.
6. **Non-ASCII is mangled when the console reads your command.** Match with ASCII-only
   patterns; build symbols as `[char]0x2192`.
7. **Never kill the user's Godot editor.** Kill only processes you started, matched by command
   line.
8. **No MCP tools reach you.** Use the log and `read_image` on the PNGs diagnostics save.

## Things to decide while doing it, and say which you chose

- **Target speed.** 1.8 m/s is a starting point. Faster grows the ball sooner but is harder to
  steer; slower is the beetle feel but might bore. State the value you settled on and why.
- **Distance window.** 1 m to 3 m in front. If holding **E** at range should still reach the
  ball, say how.
- **Whether the push should also work on a ball the player is standing on** (the "beetle
  climbing its own ball" question). Default: no.
