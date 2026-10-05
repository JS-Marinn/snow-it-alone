# Roadmap — the milestones, ordered easiest first

Operational order I work in, one milestone at a time, each ending in a green
battery and a commit. It sits between two existing documents and contradicts
neither:

- `docs/plan_juego.md` §17 — the **product** split (M0 engine, M1 vertical slice,
  M2 co-op, M3 content, M4 polish) and the 9–12 month shape.
- `docs/plan_implementacion.md` §5 — the **systems** split, phases 0–10.

**Ordering rule:** easiest first, subject to dependencies. Two milestones whose
halves differ wildly in difficulty are split so the easy half is not held hostage
by the hard one (that is what the `a`/`b` suffixes are).

**Definition of done for every milestone:** its battery is green *and* the older
batteries are still green *and* it is committed with a Conventional Commit. A
milestone that cannot be verified is not finished.

Effort: **XS** minutes · **S** a session or two · **M** several · **L** a long haul.

---

## Done

| # | Milestone | Evidence |
|---|---|---|
| **H0** | Engine core: granular snow simulation, three tools, balls, stacking, mass conservation | physics 36 OK · ball shape 8 OK · 120 FPS |
| **H1** | Movement on the Quake model: ground friction, air acceleration, the bunny hop as a skill | movement 11 OK |
| **H2** | Ball impacts on people: three size tiers, face snow with a manual wipe, stagger, knock-down, training dummy | impacts 18 OK |
| **H·saves** | Three save slots, menu with Continue/New/Delete, autosave | saves 21 OK |

Total verified now: **94 checks** across six batteries.

---

## Order from here

| # | Milestone | Effort | Depends on | Exit criterion |
|---|---|---|---|---|
| 1 | **H15a · `LICENSE` + third-party asset licences.** The repo is public with no licence, which means all rights reserved by default. Inventory every imported model, texture and sound, record source and licence. | XS | — | licence recorded · an asset-licence table exists in the repo · **needs your one-word decision on the licence itself** |
| 2 | **H15b · English docs and README.** The game's base language is English; the repo prose is still Spanish. | S | — | no Spanish left in `README.md` or `docs/` |
| 3 | **H3 · Playground.** A field 10 × 40 m (the main level's 12 m strip is why hop chains currently leave the simulation), the four surfaces the model actually has — virgin, packed, cleared, deep — ramps as static geometry, dummies, a ball spawner, an on-screen counter proving no snow is created or lost, free camera, restart key. **Measured constraint:** the simulation grid is a fixed 512² over the whole field, so a longer strip spends texel density along its length (12.8 texels/m over 40 m against 42.7 over 12 m). Acceptable for a development scene, and the coarse mirror the movement code reads is unaffected. **Also measured:** slopes cannot carry simulated snow, because the field is a horizontal plane; that needs rotated field instances and belongs to H4. "Ice" is not a surface the model has yet either. | S | — | Playground loads · that counter balances to ±0.05 % after a scripted run · six batteries still green |
| 4 | **H14a · One command that runs every test, and automatic checks on GitHub.** Today the six test batteries are run one at a time by hand, and only if I remember. This makes one command that runs all of them and stops at the first failure, plus a job on GitHub that runs the two that need no graphics card every time code is uploaded, so a broken upload gets a visible red mark instead of depending on my discipline. | S | — | one command runs all six and fails on any red · GitHub marks every upload with a tick or a cross |
| 5 | **H4 · Surface system.** Extract the surface query out of the player controller into its own module; compaction op; footprints; **slope sliding** (the last open line of §3.1). | M | H3 | four distinct frictions measured · sliding on 10° and 20° · compacting changes no mass |
| 6 | **H6 · Player split: motor / state / avatar / camera.** Pure refactor, no new behaviour. Co-op needs it, and it is cheapest now while the batteries can prove nothing changed. | M | H3 | batteries produce **identical** numbers · controller down from ~1400 lines |
| 7 | **H5 · Shared state, session modes, impact matrix.** `PlayerState`; `SessionMode` (Work / Ruckus / Duel); `ImpactResolver` extracted; full `--impact-matrix` (3×3×3); the §3.5 blocking matrix; face-snow blur and muffled audio. | M | H6 | matrix green · Work mode inert · every cell of the blocking matrix enforced |
| 8 | **H11a � fully specified in docs/spec_i18n.md, implement from there** � · Text that can be translated.** Move every piece of text the player can read out of the code and into files translators can work on, add the system that loads the right language at start-up, and add a fake language (deliberately absurd words) so any text I forgot to move becomes obvious on screen. Also fonts and layouts that survive long German words. | M | — | a check reports zero text still trapped in code |
| 9 | **H10a · A real pause menu, the settings screens, key remapping, and menus usable with a controller.** Today ESC only frees the mouse while the game keeps running, and every menu needs a mouse. This adds pause that actually pauses, screens for video (resolution, quality, fullscreen) and audio (volumes), sensitivity and comfort options (screen shake, face-snow auto-clear, hold-or-toggle for [E] and sprint), the ability to change any key or pad button and restore the defaults, and navigation with a controller alone — which the Steam Deck and console targets need, because they have no mouse. | M | — | every screen reachable with a controller only · settings survive quitting and restarting |
| 10 | **H7 · Local duo.** `Grabbable`, `TwoPersonCarry`, `Container`, `BallHandoff`, rescue. Two players on one machine, which validates the co-op verbs before netcode makes bugs expensive. | L | H6 | `--local-duo` green · duo lifting 40 % less stagger · hand-off works · tipping scales with mass² |
| 11 | **H8 · Solo/co-op parity.** Real numbers for `PlayerCountScaler`, so solo and a pair get the same challenge. | S | H7 | `--coop-rules`: solo vs duo within ±15 % on the same level |
| 12 | **H9 · Progression.** Objectives, shared achievements (all obtainable solo), collectible gifts, hidden easter eggs, the 2–3 run Winter Book, save schema extension. | L | H7 | `--ach-check` proves every achievement reachable solo · save round-trip green on the new schema |
| 13 | **H10b · Results, chronicle, photo mode.** The end-of-level payoff, including the two-player version. | M | H9 | results screen reflects a real session |
| 14 | **H12 · Content.** The vertical slice first: one complete level, objectives, money, 20 good minutes solo. Then the 8–12 levels, one commit each. | L | H9, H10b | M1 criterion: 60 fps on the low preset, testers asking for more |
| 15 | **H11b · The 13 languages and the accessibility pass.** Needs the text final, which is why it follows content. Translators are vendor work; layout, subtitles, colour-blind, hold-vs-toggle, screen-shake slider are mine. | M | H12 | zero untranslated keys · accessibility checklist complete |
| 16 | **H14b · Performance, Deck, store.** Simulation presets, 30 Hz sim, frame budget on four configurations, Deck checklist, store page, trailer, demo. | M | H12 | frame budget met · demo retention D1 above 25 % |
| 17 | **H13 · Online co-op.** First a small experiment to find out whether the snow simulation can survive a network at all. Then the real work: sending only what changed, catching the two games up when they disagree, guessing where a carried ball is between updates so it does not stutter, a lobby, and floating names over the other player. | L | H7, H8 | two players over the internet for 30 minutes with the level-completion percentage never drifting more than 0.5 % apart · under 30 KB/s |

---

## What this order buys, and what it costs

**Buys:** something verifiable almost immediately. Items 1–4 are all small, and item
3 (the Playground) is what makes every later number trustworthy — right now the snow
field is 12 m, so hop chains leave the simulation and slopes do not exist at all.
Nothing later can be measured honestly until it is built. Item 6 (the player split)
is also cheap *now* and gets much more expensive once two players exist.

**Costs — plainly:**

1. **The biggest product risk moves later.** The premise of the whole game is that
   two people clearing snow together is fun, and that is only proven at item 10. In
   the risk-first order it was item 5 of 14. So if co-op turns out not to be fun, we
   find that out later and with more work behind it. Everything before item 10 is
   still useful on its own, which is what makes this acceptable rather than reckless.
2. **Some UI gets built twice.** Pause and settings (item 9) are honest single-player
   work, but the results screen (item 13) and nameplates only make sense with two
   players in the room. I have kept those *after* item 10 deliberately, which is why
   H10 is split rather than moved wholesale.
3. **Content before netcode.** Levels built at item 14 will need re-balancing when
   H13 lands. `PlayerCountScaler` (item 11) is what keeps that from being a rewrite.

If that trade is not what you want once co-op has been proven locally, the fix is
cheap: items 12–13 can swap with 10–11 without breaking anything.
