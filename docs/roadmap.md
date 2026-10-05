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

| # | Milestone | Evidence & Commits |
|---|---|---|
| **H0** | Engine core: granular snow simulation, three tools, balls, stacking, mass conservation | physics 36 OK · ball shape 8 OK · 118 FPS |
| **H1** | Movement on the Quake model: ground friction, air acceleration, the bunny hop as a skill | movement 11 OK |
| **H2** | Ball impacts on people: three size tiers, face snow with a manual wipe, stagger, knock-down, training dummy | impacts 18 OK |
| **H·saves** | Three save slots, menu with Continue/New/Delete, autosave | saves 21 OK |
| **1 (H15a)** | Project licence (MIT) and third-party asset inventory | [`8bb67b8`](https://github.com/JS-Marinn/snow-it-alone/commit/8bb67b8) · `LICENSE` and `docs/asset_licenses.md` |
| **2 (H15b)** | English documentation and README | [`9255b61`](https://github.com/JS-Marinn/snow-it-alone/commit/9255b61) · English `README.md` and design specs |
| **3 (H3)** | The Playground: measurement and testing arena | [`3f19daa`](https://github.com/JS-Marinn/snow-it-alone/commit/3f19daa), [`bbf18e1`](https://github.com/JS-Marinn/snow-it-alone/commit/bbf18e1) · playground 11 OK |
| **4 (H14a)** | Universal battery runner and GitHub Actions CI gate | [`8d232e3`](https://github.com/JS-Marinn/snow-it-alone/commit/8d232e3) · `tools/run_batteries.ps1` · `.github/workflows/gate.yml` |
| **7 (H5)** | Shared state, session modes, impact matrix, and face snow presentation | [`072dcff`](https://github.com/JS-Marinn/snow-it-alone/commit/072dcff), [`1591075`](https://github.com/JS-Marinn/snow-it-alone/commit/1591075), [`5fb5f1e`](https://github.com/JS-Marinn/snow-it-alone/commit/5fb5f1e) · impact matrix 28 OK · face snow shot verified |
| **8 (H11a)** | i18n architecture and multilingual typography | [`4c9d96c`](https://github.com/JS-Marinn/snow-it-alone/commit/4c9d96c), [`8b65450`](https://github.com/JS-Marinn/snow-it-alone/commit/8b65450) · translations 17 OK · Noto Sans CJK |
| **9 (H10a)** | Real pause menu, settings screen, controls rebinding, and controller support | [`8135e0d`](https://github.com/JS-Marinn/snow-it-alone/commit/8135e0d), [`f9f9c40`](https://github.com/JS-Marinn/snow-it-alone/commit/f9f9c40), [`ce79950`](https://github.com/JS-Marinn/snow-it-alone/commit/ce79950), [`05a2df2`](https://github.com/JS-Marinn/snow-it-alone/commit/05a2df2), [`a539d09`](https://github.com/JS-Marinn/snow-it-alone/commit/a539d09), [`228e10f`](https://github.com/JS-Marinn/snow-it-alone/commit/228e10f) · diagnostics safety 71 OK |

Total verified now: **222 checks** across ten batteries.

---

## Order from here

| # | Milestone | Effort | Depends on | Exit criterion |
|---|---|---|---|---|
| 5 | **H4 · Surface system.** Extract the surface query out of the player controller into its own module; compaction op; footprints; **slope sliding** (the last open line of §3.1). | M | H3 | four distinct frictions measured · sliding on 10° and 20° · compacting changes no mass |
| 6 | **H6 · Player split: motor / state / avatar / camera.** Pure refactor, no new behaviour. Co-op needs it, and it is cheapest now while the batteries can prove nothing changed. | M | H3 | batteries produce **identical** numbers · controller down from ~1400 lines |
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
