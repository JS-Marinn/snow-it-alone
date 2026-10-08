# Economy: placeholder numbers

**Everything on this page is a placeholder.** None of it is a decision. It exists so the
provisional numbers have one home, and so that nobody mistakes them for something measured.

## Naming convention, so this cannot be ambiguous again

| Column | Unit | Meaning |
|---|---|---|
| `Coste (dev)` | **h** = hours | My programming time. Estimated, never measured. Multiply by 2 or 3 for real life. |
| `Precio (juego)` | **coins** | What the player pays. Placeholder until the income rate is measured. |

The mistake that caused three rounds of confusion: one column called "Coste" holding both
currencies at once, with the unit left implicit. Every placeholder from here on states its
unit and carries the word `placeholder`.

## What is real

| Fact | Value | Source |
|---|---|---|
| The snow disposal machine (only sink) | Payout for snow delivered to the machine | `scripts/disposal_machine.gd` |
| Disposal machine payout | `ceil(kg * 2.5)` coins per delivery (`PAYOUT_PER_KG = 2.5`) | `disposal_machine.gd:41` |
| Rationale for 2.5 coins/kg | Placeholder reward for delivering snow to the sole sink | Design specification |
| Snow banks | Scenery only; no payout and no mass removal | `scripts/snow_field.gd` |
| Worked example (machine) | A 25 kg delivery yields 63 coins | Derived |
| Income per minute | **Unknown** | This is the missing number |

## Placeholder prices

One ladder shared by every upgrade, each tier at 2.2x the previous.

| Tier | Price (coins, placeholder) | At 60 coins/min | At 150/min | At 300/min |
|---|---|---|---|---|
| 2 | 150 | 2.5 min | 1 min | 30 s |
| 3 | 330 | 5.5 min | 2 min | 1 min |
| 4 | 730 | 12 min | 5 min | 2.5 min |
| 5 | 1,600 | 27 min | 11 min | 5 min |
| 6 | 3,500 | 58 min | 23 min | 12 min |

The three time columns are the same prices at three assumed income rates, because the rate is
what is missing. Once it is measured, pick a column and delete the other two.

## Placeholder developer cost

| Work | Coste (dev, placeholder) |
|---|---|
| The money sink (a shop) | 4-6 h |
| Grip and steadier carry | 2 h |
| Rolling grows faster | 1 h |
| Shovel tiers 2-5 | 5 h |
| Aimed shovel toss | 3 h |
| Blower tiers 2-5 | 8 h |
| A ball that survives an impact | 4 h |
| **Total** | **27 h, realistically 50-80 h** |

## What must be measured before any price is final

| Measurement | Why it matters |
|---|---|
| Coins per minute with the shovel | The baseline rate |
| Coins per minute with the blower | Says whether one tool dominates the economy |
| Coins per minute with hands and a rolled ball | Whether the fun loop pays at all |
| Coins earned in a normal session | The real ceiling of the ladder |

This is one small battery: spawn each tool, play sixty seconds of typical use, report coins
per minute. About an hour of work, and it turns invented prices into arithmetic.

## The design question underneath, which is not a number

| Fact | Consequence |
|---|---|
| The disposal machine is the only income and sink | The economy channels the player into delivering snow to the machine |
| Carrying/transporting snow gives progress and payout | Shovels, blowers, and rolling balls are all loaders feeding the machine |
| The banks are preserved scenery | Snow can still be piled against banks, but bank deposit no longer pays |

That establishes a clear, unified game loop where the disposal machine is the single destination for removed snow.
