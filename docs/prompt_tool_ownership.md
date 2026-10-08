# Prompt: tools are bought, you start with only the hand

Hand this file over whole. It is self-contained.

---

You are working on **Snow It Alone** (working title "Snow It Together"), a co-op
snow-shovelling game in **Godot 4.7.2**, one programmer. Code, comments, UI text and docs are
in **English**; reply in whatever language you are asked in.

- **Repository:** `C:\Users\MrSeb\.gemini\antigravity\scratch\snow_it_alone`
- **Godot:** `C:\Users\MrSeb\Downloads\Godot_v4.7.2-stable_win64.exe\Godot_v4.7.2-stable_win64_console.exe`
- **Run:** `& $godot --path $repo --quit-after 2400 -- --<flag>`

## What the owner asked for

> "The tools must also be bought. You start with only the hand. The Playground must have the
> tools from the start. The tools will be bought in a shop, which will be added later."

So: build the ownership model and the purchase API **now**, with no shop UI. The shop comes
later and should need nothing but wiring.

## Read first

| File | Why |
|---|---|
| `docs/economy_placeholder.md` | Currency, the payout formula, and which numbers are placeholders. None of its prices are decisions. |
| `docs/pending_work.md` | Section 13 in particular: if an approach fails twice, stop refining it. |
| `docs/spec_i18n.md` | Every new player-visible string goes into `locale/strings.csv`. |

## The blocker to solve first, or the game has no way to start

> **Current implementation note:** this is a historical prompt section. The bank payout route
> has since been removed; the disposal machine is the only snow sink and payout path. Do not
> restore a bank sink to satisfy the old steps below; follow `docs/architecture.md` and the
> supplied `GAME_SPEC.md` instead.

The bank payout lives in `snow_chunk.gd:85`, which means **chunks**, not balls. A player who
owns only the hand cannot blow chunks. So the question is: **can they earn anything at all?**

If a packed ball thrown into the bank pays nothing, the game is unsolvable from a fresh save.
**Verify this before writing any ownership code, and report what you find:**

1. Spawn nothing. Give the player the hand only. In the Playground, pack a ball, roll it to
   the bank, throw it in, and print the coin balance.
2. If the balance does not move, **extend the payout to any snow that arrives in the bank**
   from a ball or a chunk, and say so in the commit. A bank that only pays for one tool is a
   soft lock.
3. This must become a check in the battery described at the end: **with only the hand, the
   coin balance must be able to increase.**

## What to build

1. **A hands state in the tool enum.** Today `enum ToolType { SHOVEL = 0, BLOWER = 1, SALT = 2 }`
   in `player_controller.gd`. Add `HANDS = 3` and make it the default. With `HANDS` selected,
   the tool processing is skipped and only the hand verbs run: pack, carry, throw, roll.
2. **An owned set.** Ownership is per save, not per run. It belongs with whatever already
   persists in the save slots, and `--save-roundtrip` must cover it.
3. **A purchase API.** `can_afford(tool)`, `price(tool)`, `purchase(tool)` returning success or
   failure. A purchase that cannot be afforded must change **nothing**: no coins deducted, no
   tool granted. This is the same all-or-nothing rule the hand packing now follows.
4. **Cycling never selects an unowned tool.** The tool switch must walk the owned set only.
5. **The HUD shows only owned tools.**
6. **The Playground and every diagnostic and battery grant what they need, explicitly.**
   The "hand only" rule applies to the real game, not to the development scene and not to the
   tests. If a battery needs the shovel, it grants the shovel; it must not depend on the
   default. Say in the commit that you did this.
7. **Placeholder prices for owning each tool**, in the same spirit as
   `docs/economy_placeholder.md`: shovel, blower and salt each with a placeholder unlock price
   and the word `placeholder` beside it. Salt stays parked for balance work; the mechanism
   still exists for it.
8. **No shop UI.** Do not build a menu. The API is the deliverable.

## Strings

New player-visible strings (tool names, "not owned", purchase failures, the balance) go into
`locale/strings.csv` and through `tr()`. Diagnostics and battery output stay English and are
never translated.

## Acceptance: a battery, not an opinion

Add `--tool-ownership` and register it in `tools/run_batteries.ps1` (`Gpu = $false` if it can
be, `$true` otherwise). Checks, at minimum:

1. A fresh save owns **only** the hand; the tool enum reports `HANDS`.
2. **With only the hand, the coin balance can increase** by packing, rolling and delivering a
   ball to the bank. This is the anti-soft-lock check.
3. Purchasing an affordable tool deducts **exactly** its price and grants it.
4. Purchasing an unaffordable tool fails, deducts **nothing**, and grants **nothing**.
5. Ownership survives a save and load round trip.
6. Cycling never selects an unowned tool.
7. In the Playground, all tools are owned from the start.

Extend `--save-roundtrip` for the persistence half rather than duplicating it.

## Never break these

| Battery | Must stay at |
|---|---|
| `--save-roundtrip` | 21 OK / 0, plus the new ownership checks |
| `--impact-lab` | 18 OK / 0 |
| `--impact-matrix` | 28 OK / 0 |
| `--phys-demo` | 36 OK / 0 |
| `--beetle-roll` | 6 OK / 0 |
| `--hand-pack` | 12 OK / 0 |
| `--contact-burst` | 4 OK / 0 |
| the whole gate | ALL GREEN |

The gate currently reports 14 batteries and 250 checks. Never commit on red.

Commit as: `feat: tools are owned and purchased, and you start with only the hand`

## Rules that have cost the most time here

1. **Read a file before editing it.** The editor requires a prior read; bulk replacement while
   it is blocked invalidates that and causes cascading failures.
2. **Never `class_name` in a new script.** It needs the editor's class cache and a command-line
   run then fails with "Identifier not declared". Use `const X = preload("res://scripts/x.gd")`.
3. **Measure first, change one thing, then measure three times.** Single runs have twice proven
   worthless here.
4. **A battery that hangs or aborts without a verdict is a FAILURE.** A hang is a symptom.
5. **If a fix fails twice, stop refining it.** Produce three alternatives from different frames,
   including a cheaper one and a design change.
6. **PowerShell 5.1**: no `pwsh`, no `&`, no inline `if` expressions, no ternary, and piping a
   `foreach` statement is a parse error.
7. **Non-ASCII is mangled when the console reads your command.** Use ASCII-only anchors and
   build symbols as `[char]0x2192`.
8. **Never kill the user's Godot editor.** Kill only what you started, matched by command line.
9. **If you have MCP tools for Godot, use them** — the bundled `addons/godot_ai` exists to
   serve a client like yours, and asking the running editor what is in the scene beats a log.
   If you do not have them, fall back to the log plus `read_image` on the diagnostics' PNGs.
   Do not assume either way: say which you used.

## Definition of done

The anti-soft-lock check passing, the seven ownership checks in place, tools granted explicitly
everywhere they are needed, the whole gate green, and a commit message that states **how a
player owning only the hand earns their first coin** — measured, not assumed.
