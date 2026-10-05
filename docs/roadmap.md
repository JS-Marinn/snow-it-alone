# Roadmap — the milestones from here

This is the operational order I work in, one milestone at a time, each ending in a
green battery and a commit. It sits between two existing documents and contradicts
neither:

- `docs/plan_juego.md` §17 — the **product** split (M0 engine, M1 vertical slice,
  M2 co-op, M3 content, M4 polish) and the 9–12 month shape.
- `docs/plan_implementacion.md` §5 — the **systems** split, phases 0–10, ~5–6 months.

This file is the day-to-day order: what gets built next, and what "done" means.

**Definition of done for every milestone below:** its battery is green *and* the
older batteries are still green *and* it is committed with a Conventional Commit.
A milestone that cannot be verified is not finished.

---

## Done

| # | Milestone | Evidence |
|---|---|---|
| **H0** | Engine core: granular snow simulation, three tools, balls, stacking, mass conservation | `--phys-demo` 36 OK, `--ball-shape` 8 OK, `--carve-quality` 120 FPS |
| **H1** | Movement on the Quake model: ground friction, air acceleration, the bunny hop as a skill | `--movement-lab` 11 OK |
| **H2** | Ball impacts on people: three size tiers, face snow with a manual wipe, stagger, knock-down, training dummy | `--impact-lab` 18 OK |
| **H·saves** | Three save slots, menu with Continue/New/Delete, autosave | `--save-roundtrip` 21 OK |

Total verified right now: **94 checks** across six batteries.

---

## Next

### H3 — Playground (the test bench) · small
The scene from `plan_implementacion.md` §4, and the reason it comes first: the
current field is 12 m long, so bunny-hop chains leave the simulation and slopes do
not exist at all. Nothing after this can be measured properly without it.

Flat pad · **long runway (≥ 60 m)** · four surfaces side by side (virgin, packed,
cleared, ice) · slopes at 5°, 10°, 20° · a low ledge for hops · dummies · a ball
spawner · live mass-ledger readout · free camera and a restart key.

**Exit:** the Playground loads; the mass ledger balances to ±0.05 % after a scripted
run; all six existing batteries still green.

### H4 — Surface system proper · medium
Extract `SnowSurfaceQuery` from the player controller into its own module, add the
compaction op and footprints, and implement **slope sliding** (the one line still
open in §3.1). Also the rule that hopping is only rewarding on packed ground.

**Exit:** four distinct frictions measured on the Playground; sliding on 10° and 20°;
compacting provably changes no mass; `--movement-lab` extended to cover slopes.

### H5 — Shared state, session modes and the full impact matrix · medium
`PlayerState` as its own thing (read by the player, by dummies and later by remote
peers), `SessionMode` (Work / Jaleo / Duel), `ImpactResolver` extracted out of
`snowball.gd`, the complete `--impact-matrix` (3 tiers × 3 zones × 3 speeds), the
state-blocking matrix from §3.5, and the missing face-snow presentation (blur,
muffled audio).

**Exit:** impact matrix green; Work mode provably inert; every cell of the blocking
matrix enforced.

### H6 — Player split: motor / state / avatar / camera · medium, low risk
Infrastructure, not features: this is the prerequisite for two players existing in
one world, and it makes the codebase maintainable before it grows. Pure refactor —
the batteries must produce **the same measured numbers** afterwards.

**Exit:** all batteries green with unchanged numbers; `player_controller.gd` down
from ~1400 lines to a motor plus small collaborating pieces.

### H7 — Physical co-operation, local duo · large
`Grabbable`, `TwoPersonCarry`, `Container`, `BallHandoff`, rescue. Two players on
one machine first, because that validates the co-op verbs — the actual differentiator
of this game — **before** netcode makes every bug twice as expensive.

**Exit:** `--local-duo` battery green: two-person lifting is 40 % less stagger, ball
hand-off works, tipping a container scales with mass².

### H8 — Solo/co-op parity · small
Real numbers for `PlayerCountScaler`, so a solo player and a pair get the same
challenge rather than an easier or impossible one.

**Exit:** `--coop-rules`: solo vs duo within ±15 % on the same level.

### H9 — Objectives, progression, achievements, the Winter Book · large
`ObjectiveSystem`, `ProgressionSystem`, and **shared** achievements (party-wide; none
obtainable only with a second person). Collectible gifts, hidden easter eggs, and the
2–3 run structure for 100 %. Extends the save schema.

**Exit:** `--ach-check` proves every achievement is reachable solo; the save round-trip
still green on the new schema.

### H10 — Presentation and UX · large
Pause, results screen with the chronicle, the full settings catalogue (video, audio,
controls, rebinding), photo mode, HUD polish, and **menu navigation with a gamepad
alone**.

**Exit:** `--settings-apply`, `--i18n-check`, and a controller-only pass through every
screen.

### H11 — Languages and accessibility · medium
The pipeline for the 13 target languages plus a pseudo-locale, fonts and layout that
survive long words, subtitles, colour-blind options, hold-vs-toggle, screen-shake
slider (this matters now that hits shake the camera), text size for the Deck.

**Exit:** zero untranslated keys; accessibility checklist complete.

### H12 — Level content · large
The vertical slice: one complete level with objectives, money and 20 minutes of fun
solo — then the 8–12 levels of M3, one commit per level.

**Exit:** the M1 criterion from §17 (60 fps on the low preset, 20 good minutes, testers
asking for more), then the campaign at 1.5–3 h.

### H13 — Online co-op · large
Network spike first, then `NetworkManager`: operations, RLE resync, carry prediction,
lobby, nameplates, Remote Play.

**Exit:** `--net-smoke`: drift under 0.5 % per level, under 30 KB/s, a 30-minute session
with two players over the internet.

### H14 — Performance, release, store · medium
Simulation presets, 30 Hz sim, frame budget, every battery as a merge gate, Steam Deck
checklist, store page, trailer, demo.

**Exit:** frame budget met on four configurations; demo retention D1 above 25 %.

---

## Parallel housekeeping (not milestones, but not to be forgotten)

- **Translate the docs and README into English.** The game's base language is English
  and the repo's prose is still Spanish.
- **`LICENSE`.** The repository is public with no licence, which means all rights
  reserved by default.
- **Third-party asset licences.** Verify every imported model, texture and sound and
  record the licence and source in the repo.

---

## Order and risk

The order is deliberate: **H3 → H4 → H5** finish the systems that are half-built and
give every later claim a place to be measured. **H6 → H7 → H8** build the co-op spine in
the cheapest possible order (structure, then local play, then parity) *before* netcode.
Content (H12) stays late on purpose: `plan_juego.md` §17 already says systems before
content, and building levels against a moving ruleset wastes them.

The two biggest risks stay the ones already named in the docs: **netcode** (H13, held
back until the verbs are proven locally) and **content volume** (H12, the only part
that scales with money rather than with cleverness).
