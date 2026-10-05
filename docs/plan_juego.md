# Game plan — Snow It Together (working title)

> Design and technical plan document. **None of this is implemented yet**: it serves
> to decide before building. What already exists in the prototype is marked with
> ✅ and what is missing with ⬜.

---

## 0. Executive summary

**Snow It Together** is a first-person snow-clearing simulator,
*cozy*, **playable solo and in 2-player online co-op**, with a granular snow
engine of **conserved mass** as its central differentiator.

- **Genre:** cozy cleaning sim + emergent physics sandbox + prank co-op.
- **Price:** **€6.99** (in line with the reference) + **free demo**.
- **Length:** 1.5–2.5 h for the first solo run · **6–9 h for 100%**
  (the Winter Book demands **2–3 runs** with different challenges) · unlimited
  sandbox and snowball duel.
- **Direct reference:** *Leaf it Alone* (Eternity, 2025) — same "clear to 100%"
  loop, same low-cost aesthetic, same text-only languages.
- **Differentiator 1 — snow is matter:** there a mask is erased; here it does not
  disappear, it moves. Every level is a logistics puzzle (*where do I put it?*).
- **Differentiator 2 — co-op is physical and rowdy:** tasks are not divided,
  objects are shared, and **ruining your partner's work is a designed
  mechanic**, not an accident that has to be punished.

**The bet:** the niche is crying out for co-op and nobody has given it to it. A co-op
where two people pass balls to each other, lift together and wreck each other's
freshly made pile is a different product in a market that sells 292 k copies at €6.

**The three layers of playtime** (this is what makes it last without expensive
content): working · **playing with each other** · collecting and discovering
secrets. The plan spreads the effort across all three, not only the first.

---

## 1. Reference and market gap

Data from *Leaf it Alone* ([Steam](https://store.steampowered.com/app/3981100/),
[VORYTHIC](https://vorythic.com/games/3778/leaf-it-alone)):

| Data | Value | Reading for us |
|---|---|---|
| Price | €5.99 | Small scale; do not compete with a AAA budget |
| Sales | ~292 k copies | A real, profitable niche with a minimal team |
| Rating | 95% positive | A well-made "cozy" game forgives the lack of content |
| Length | 1.6 h main · 5.5 h full | 8–12 levels of 5–15 min are enough |
| Languages | **13, interface only** | i18n is mandatory and **no voice-over is needed** |
| Tags | Cleaning, Relaxing, **Incremental**, Physics, First-Person, Controller | Satisfying numerical progression + gamepad |
| Minimum specs | GTX 960, 4 GB RAM, 1 GB disk | **Our technical risk #1**: the GPU sim |
| Multiplayer | Store page: *single-player*. Forum: *"why does it have a coop tag?"* | **The gap is here** |
| Accessibility | Camera comfort, Custom volume, Playable without timed input, Save anytime | The genre's minimum checklist |
| Extras | Achievements, leaderboards, Steam Cloud, implicit photo mode | Cheap and expected |

**Conclusion:** we copy the *chassis* (loop, tone, price, 13 languages, gamepad,
save-anytime) and we differentiate ourselves with **real physics + co-op**.

---

## 2. Design pillars

1. **Snow is matter, not a texture.** Nothing is erased: everything moves. The mass
   of the world is conserved (this is already a hard rule of the prototype ✅).
2. **Shared physical work is the fun.** Co-op does not divide tasks,
   it *shares* them: objects that need two people.
3. **Movement is a toy.** Running, sliding and **bunny hop** have
   real inertia and feel good; the terrain you work is what lets you go
   fast. Getting around is fun in itself.
4. **Chaos between friends is content, not a bug.** Throwing balls at each other,
   burying each other, tipping over the other's wheelbarrow and laughing: the game
   **celebrates it and measures it**, and everything is **reversible** (progress is
   never lost). No punishment, no toxicity.
5. **Relax by default, chaos optional.** No fail states, no timers,
   no QTEs. Stress is activated (challenges, storms, duel), not imposed.
6. **Objectives by world state, not scripted steps.** "Clear 90%"
   and "leave the snow in the truck" are measurable and allow any solution.
7. **Collect and discover.** Hidden gifts and secrets that the community
   tears apart: they give a second (and third) reason to return to every level.

**What we are NOT:** neither survival, nor crafting, nor horror, nor scarce-resource
management, nor a troll game. If a mechanic adds anxiety without adding
satisfaction, or lets someone *genuinely* ruin another's game, it is out.

**Golden rule of rowdiness:** *every prank has to be funny for the person
receiving it*. If the victim is not laughing, it is badly designed.

---

## 3. Fantasy, tone and setting

> **The location is UNDECIDED** and it does not constrain any mechanic. What follows
> describes the tone, not a fixed setting: any place with snow to remove and
> objects to move will do. Nothing in the design depends on it being an alpine
> village, a housing estate or a ski resort.

**Fantasy:** it has snowed enormously and it has to be cleared. It is done alone or with
someone, without hurry and without enemies: mountains of snow, a job to fulfil and time
to cause mischief with whoever is with you.

- **Tone:** warm, bright, slightly absurd. *Physical* humour (you fall, the
  avalanche buries you, the snowman collapses), never humiliating between players.
- **Setting:** a small alpine valley. Player's house → street → square → ski
  slope → frozen river → cable car. A single *hub* (the village square) with
  properties around it: it keeps art cheap and gives a sense of a continuous world.
- **Time of day and weather** as cheap content variation: dawn, grey day,
  golden sunset, light snowfall, blizzard (advanced level).

---

## 4. Game loop

| Scale | Duration | Content | Reward |
|---|---|---|---|
| **Micro** | 10–60 s | Choose tool → apply it → the snow moves → it sounds good, snow flies, the % goes up | *Juice*: sound, particles, a number going up |
| **Meso** | 5–15 min | One level: clear to X%, optional objectives, take the snow to its destination | Money, stars, next unlock |
| **Macro** | 1.5–3 h | The season: clear the valley, upgrade tools, epilogue | Final snowman, sandbox, challenges |

**Typical co-op session (20–40 min):** lobby → 2–3 levels → shop → "one more".
It must be possible to join and leave **at any moment** (drop-in/drop-out).

**Retention hook:** the "% cleared" counter going up + the sound of the
shovel. It is addictive for the same reason *Leaf it Alone* is "Incremental": numbers
that go up and a surface that is visually cleaned.

---

## 5. Mechanics

### 5.1 Movement and interaction ✅
First person, walk/run/jump on the snow (the player *sinks* according to the
height of the snowpack ✅), no weapons. Interaction: `E` (tap = pick up/tamp;
hold = push along the ground ✅), left click = tool, right click = throw/
pour ✅. Free-hand mode (no tool) for carrying objects ✅.

### 5.1.1 Inertia, sliding and bunny hop ⬜ (decision made)

Movement stops being "walking with brakes" and becomes **a skill with a
ceiling**, because getting around a snowy village has to be fun in itself.
Four pieces:

**1. Friction by surface.** The ground does not brake the same everywhere:

| Surface | Friction | Feel |
|---|---|---|
| Cleared path / compacted snow (tamped, trodden) | Very low | You run and keep your momentum |
| Powder snow (virgin, dry) | High | You sink, your speed is cut |
| Ice / slush (salt + snow) | Almost none | You slip, you cannot brake |
| Downhill | — | You gain speed on your own |

**2. Bunny hop.** If you chain jumps at the right rhythm **you do not pay the
landing friction**: you keep your speed and, combined with *air strafe*, you increase
it up to a **cap of 1.6× the run speed**. The cap is deliberate: we want a
satisfying movement skill, not an exploit that breaks the game.

**3. Snow is what gives the bunny hop its meaning** (this is the beautiful part): it
only works well on **compacted or cleared** surface; in deep powder you sink and lose
the momentum. And here is the hook-up with the rest of the game: **on landing you leave
the snow compacted**, so hopping in a straight line **traces a trodden path**. Players
will discover on their own that hopping in a line is the quick way to make a
trail — and that afterwards you run much faster along that trail. It is an emergent
mechanic, consistent with conserved mass (you compact, you do not remove) and it
reinforces pillar 1.

**4. Mobility toys** (each cheap to make and very sellable in a GIF):
- **Shovel riding** (ride): downhill on the blade, with tilt
  control and snow flying.
- **Sled**: in the hub and in 1–2 levels; it carries snow *or* a partner.
- **Shovel quad** (advanced levels): solo it is your force multiplier;
  with two people it is a two-person toy (one drives, the other loads and holds on).
- **Kick**: a light hit that pushes balls and props. It is useful for playing football
  with the balls while you move around, and it is the basis of half a dozen pranks.

**Technical cost:** low. It is the player controller (friction by surface
querying the snowpack ✅ height/cohesion queries already exist), a speed
multiplier with a cap and two or three physics objects.

**Accessibility:** bunny hop is **optional**; there is an *auto-bhop* setting
(hold jump) and maximum speed does not depend on mastering it. On gamepad, jump on
A/cross and sprint on trigger or stick click.

**Also to add ⬜:** crouching, rolling/falling and getting up (physical comedy), climbing
onto piles, grabbing and dragging, light aim/zoom for the balls.

### 5.2 Snow as a material ✅
Rules that already exist and are the heart of the game:

- Conserved mass: carving (carve/harvest), dumping (dump), tamping (tamp),
  pouring and reabsorption of fragments.
- Simulation channels: height, loose snow, cohesion/moisture and phase (at rest /
  flowing) → **two-phase hysteresis**: virgin snow holds vertical walls,
  dry snow crumbles at the angle of repose.
- Angle of repose according to moisture; salt reduces cohesion; tamping compacts.
- Deformable surface rendered by mesh + filtered normals ✅.

**To exploit further (⬜):**
- **Persistent footprints and tracks** (footprints, wheels, shovel marks) — cheap
  and sold as *juice*.
- **Snow that gets dirty** (soil, leaves) and can be cleaned again → replayability.
- **Ice** as a distinct material (hard, slippery, breaks with a pickaxe) and
  **water/slush** as a legitimate mass outlet (drain, river).
- **Crusts** (hard layers) in advanced levels.

### 5.3 Tools

Every tool is **a physical verb**, not a skin. They are upgraded separately.

| # | Tool | Verb | Strong at | Weak at | Upgrade | Co-op hack |
|---|---|---|---|---|---|---|
| 1 | **Shovel** ✅ | cuts, pushes, loads, tamps, throws | everything, slow | volume | capacity, edge, force | carry between two |
| 2 | **Snowplow / pusher** ⬜ | pushes large volumes | wide surfaces | detail, edges | width, angle, weight | push between two |
| 3 | **Turbine/blower** ✅ | throws loose snow into the air | fast, piles | compact/wet snow | flow rate, range | direct the jet |
| 4 | **Salt spreader** ✅ | de-coheres, melts, creates slush | ice, crusts | volume | radius, flow rate | — |
| 5 | **Pickaxe/axe** ⬜ | breaks ice and crusts | hard layers | loose snow | damage, speed | — |
| 6 | **Rake** ⬜ | levels thin layers | finish, precision | volume | width, fineness | — |
| 7 | **Wheelbarrow / sled** ⬜ | carries mass | logistics | steep terrain | capacity, wheels | **two people** for the full one |
| 8 | **Hose / steam** ⬜ | melts (mass → water, drains) | late game | slow, makes things wet | flow rate, range | — |
| 9 | **Snowballs** ✅ | play, push, break | fun | work | mass, grip | **passing balls** |

**Tool progression:** 3 levels per tool (basic → pro → industrial),
with visible stats and a change you can *feel* (not just numbers: the pro blower
reaches roofs, the pro shovel cuts layers that used to bounce off).

### 5.4 Balls, stacking and building ✅
Already exists: making with the hands, rolling and growing by accretion, increasing
density (300→470 kg/m³), carrying with one/two hands with wobble and grip, throwing by
mass, physical joining when stacking, breaking on impact with fragments and returning
mass to the snowpack.

**Its role in the game:**
- **A real work tool**: rolling a large ball compacts a path, plugs a
  drain, acts as a counterweight or as a step to climb onto a roof.
- **The social toy par excellence** (see §6.6): passing balls, duels, pranks.
- **Snowman: an optional and fun extra, NOT an objective.** It can be built
  in the hub and in the sandbox with the three balls and the accessories ✅ (carrot,
  coal, branches); the game recognises it with an achievement and an ornament for the
  village, and it works as a showcase for the cosmetics. Nothing in the campaign depends
  on it: it is a toy for whoever wants to amuse themselves.
- **Aiming**: targets, buckets and a ball-basket mini-game (the basis of the duel and
  of a couple of level challenges).

### 5.5 Objectives and evaluation ⬜
**Composable** system (every objective is a condition evaluated per tick):

| Type | Example | Measurement |
|---|---|---|
| Coverage | "Clear 90% of the path" | % of cells with height < threshold ✅ (% already exists) |
| Mass destination | "All the snow to the truck" | Mass accumulated in a valid zone |
| Precision | "Do not cut the hedge" | Prop integrity |
| Construction | "Make a 3-ball snowman" | Joint graph ✅ (the joint exists) |
| Recovery | "Find the 5 lost tools" | Objects dug up |
| Time (optional) | "Before noon" | Only in challenge mode |
| Team | "Both of you on the same task at once" | Proximity + same action |

**Evaluation:** 1–3 stars according to coverage + optionals + efficiency (kg moved
per minute). Stars pay more money; **they never block progress** (you can always
keep playing the next level).

### 5.6 Economy and progression ⬜
- **Money** per kg of snow *well placed* (at a valid destination) + bonus for
  optionals + co-op bonus (simultaneous work).
- **Shop**: new tools + upgrades + cosmetics (shovels, gloves, hat,
  ball colours, wheelbarrow stickers).
- **No microtransactions.** Everything is earned by playing.
- **Statistics panel**: kg moved, m² cleared, balls thrown, snowmen,
  avalanches triggered, total time, "snow efficiency".
- **Unlocks by progress**, not by money: levels open when you complete the
  previous one; money buys convenience.

### 5.7 Hazards and optional chaos
By default **nothing can fail**. Toggleable:
- **Avalanches**: snow above a certain angle can break loose and
  bury a player (you free yourself, no death: 2 s of "ouch!" and on you go).
- **Roofs**: the snow on a roof falls all at once; whoever is underneath is buried.
- **Thin ice**: falling into the water = a soaking and back to the edge.
- **Blizzard**: it snows while you clear (advanced level; the mass that falls is real).
- **Work mode** (optional): fatigue, weight that genuinely slows you down, no assists.

### 5.8 Game modes
1. **Campaign** (1 player **or** 2 in co-op, both experiences complete): 10
   levels + epilogue. **100% of progress is achievable solo**; co-op
   adds its own layer of extra stamps without blocking anything (§5.9).
2. **Sandbox / Free field**: all tools, infinite snow, no objectives.
   It is the engine's calling card and the magnet for creator content.
3. **Snowball duel** (§6.6): arena, 1v1 or 2v2, scoreboard and 2-minute rounds.
4. **Challenges**: same seed and objectives for everyone, global leaderboard.
5. **Season 2 (NG+)**: the valley snows over again with **different snow** (§5.9).
6. **Photo** (inside any mode): free camera, poses, filters.

### 5.9 Replayability: the Winter Book (2–3 runs for 100%) ⬜

The game is not completed in one run, and **not because of grind, but because the
challenges contradict each other**. Every level records in the *Winter Book*:

- **3 stamps per level, mutually exclusive in the same run:**

| Stamp | Challenge | Example |
|---|---|---|
| **Clean and fast** | Efficiency | Finish under the target time or with X kg/min |
| **Immaculate** | No wreckage | Do not break props, do not leave piles outside the zone, do not step on protected areas |
| **With style** | Restricted method | Shovel only, no blower, balls only, without using the truck |

  Since they do not fit in a single run, **getting all three forces you to repeat the
  level** (and to play it another way, which is the important part).
- **Campaign challenges** (a genuinely new run): the whole campaign without buying
  upgrades · without the blower · in **Work mode** · night only · all the gifts
  in a single run.
- **Solo/co-op parity rule:** *everything that counts towards 100% can be
  achieved solo*. The challenges that need two people (not throwing a single
  ball, or throwing 200) exist as **companionship stamps**: they give cosmetics and
  pride, they are shown off in the Book, but they **do not block anyone's 100%**.
- **Shared achievements:** a single achievement set. In co-op they unlock
  **for both players at once** and the counters add up both players' work; and
  **no achievement requires a second person** (the impact ones are earned against
  targets and training snowmen). That way both modes are equally complete.
- **Season 2 (NG+)**: the same levels with **the snowpack changed** — dry powder
  (does not hold walls), hard crust (has to be picked), wet heavy snow (it sticks
  and weighs double) and more total mass. It is **almost free content with the feel of a
  new game**, because all the difficulty lives in the material, not in the setting.

**Result:** 1.5–2.5 h for the first run, **6–9 h for the complete Book**, and every
run changes *how* it is played, not only how much.

### 5.10 Collectibles and secrets ⬜

**24 Christmas gifts** (they unlock cosmetics: hats, gloves, shovel skins,
special balls, ornaments for the village and the snowman; **never gameplay power**):

- **12 in the levels**: always somewhere that demands good use of a tool —
  inside a pile you have to shovel, on a roof you reach with a ball,
  frozen in the ice (you have to break it), at the bottom of a well, under a car,
  in a chimney, buried where the dog is looking.
- **12 in the village (hub)**: accessible only with skill (a chain of bunny hops,
  a sled jump, blowing the snow off a cornice, sliding down a cable).
- **Visual and subtle** hints (a ribbon peeking out, an icy glint, a dog that
  insists) — never a map icon with an arrow. Searching is part of the game.

**6 very well hidden easter eggs**, designed for **the community to tear them
apart** (that is free marketing: threads, videos, "has anyone seen…?"):

1. A **yeti** that appears if you leave a level untouched and at night for 3 minutes.
2. A **buried door** at a specific point in the hub → a small developer room.
3. The **golden snowball**: sink 10 in a row without missing in the hub bucket.
4. The **well**: if you throw in a specific object, it changes the village weather forever.
5. **Curling / minigolf** in a frozen puddle hidden behind a fence.
6. A **tribute to the genre**: a buried leaf blower, covered in leaves.

**Design criterion:** no written hints, but always **deducible** from a
visual or audio oddity. A secret nobody can find is not a secret, it is
lost content; one found by chance on the first day is not a
secret. Gifts and secrets feed achievements, and achievements are the third
run of the Winter Book.

---

## 6. Co-op design (the differentiator)

### 6.1 Why co-op (of 2) and not "single + co-op bolted on"
Co-op changes the design from the ground up, it is not added afterwards. **Exactly 2
players** (not 4): it is the number that makes physical logistics intimate and readable,
that the netcode is affordable and that levels can be sized well. And since the
game must also be playable solo, co-op leans on three things:

- **Shared snow is the common toy.** Everything one moves, the other sees
  and can undo. It is the recipe for comic chaos without needing a script.
- **Heavy objects are the social excuse.** The 35 kg two-handed
  threshold already exists ✅; we add that **a partner reduces the wobble and the grip
  cost** (both holding = you can carry it further). That turns "carrying something" into
  a conversation.
- **Emergent combos are infinite content**: one blows the snow into the air and
  the other packs it; one cuts the base and the other pushes the cornice; one climbs
  on top of the pile and the other carries them off rolling.
- **Shared time is part of the product** (§6.6): between two, the game is also
  about throwing balls and wrecking each other's pile. That is playtime that costs no
  content.

### 6.2 Co-op verbs (closed and verifiable list)

| Verb | Mechanic | Status |
|---|---|---|
| **Passing balls** | throw with physical momentum, receive by pressing `E` nearby | ⬜ receive (throw ✅) |
| **Lifting between two** | if both hold it, ÷ wobble and ÷ grip cost | ⬜ |
| **Pushing between two** | wheelbarrow/object: the forces add up, it moves much more | ⬜ |
| **Boosting a partner** | climb on a ball/pile and the other pushes | ⬜ (physics already allows it) |
| **Work chain** | one carves and throws, the other receives and stacks | ⬜ |
| **Rescue** | dig out a partner buried by an avalanche | ⬜ |
| **Synchronicity** | objectives that reward both being on the same task | ⬜ |
| **Ping/gestures** | mark a point in the world, point, wave, throw a ball | ⬜ |

### 6.3 Session structure and lobby ⬜
- **2-player online** through Steam (lobby + invite via overlay). "Local
  co-op" is covered by **Remote Play Together**, which is free and already works on
  Deck: zero extra work and it covers the couch.
- **Session mode choice** (this governs the whole social layer):
  **Work** (nothing the other does affects you) · **Ruckus** (default, with
  friends: balls and pranks take effect) · **Duel** (ball arena).
- **Drop-in/drop-out** at any moment; whoever joins syncs with the
  current state of the snow.
- **Lobby**: two slots, ready, level choice, session mode, cosmetic, and
  **quick pings** in the world (mark a point, point, ask for help).
- **Shared pause**: host only, with a warning.
- **Host**: total authority (and scoreboard authority, see §6.5). If it drops,
  "resume from save" is offered (no live migration).
- **Privacy**: by default **friends only** — Ruckus mode with strangers is
  fun or a headache, depending on the day.

### 6.4 Anti-frustration and scaling
- **No lost progress, ever.** Not money, not stars, not unlocks. What can be lost
  is time and pride, and that is recovered by cleaning again.
- **Damage between players depends on the session mode** (§6.3): in *Work*, the
  balls pass through (they do not affect); in *Ruckus*, they take effect with exaggerated
  and always reversible reactions; in *Duel*, it is the objective.
- **Shared** objectives, **individual** statistics and a **chronicle** at the
  end that also rewards pranks (§6.6): competing without anyone losing.
- No player can **block** another: no locked doors, no
  unique unrecoverable objects (if something falls into the river, it comes back; if
  something breaks, it can be made again with snow).
- "No failure": staying buried, falling into the water or wrecking the other's pile does
  not cost progress. It is only paid for in time and laughs.
- **The division of work between 1 and 2 players is designed explicitly** with the
  `PlayerCountScaler` system (see `plan_implementacion.md` §3.4): **requirements are
  scaled, never the physics**, and solo you are never asked for something that needs
  two hands. Both modes must feel equally good, not "one good and the other a
  consolation prize".

### 6.5 Netcode (the technical part, without embellishment)

**The problem:** the snowpack is a 512² RGBA32F texture on the GPU. It cannot be
replicated per frame. **The solution: replicate operations, not pixels.**

- **Host authority.** The host runs the canonical simulation and applies every
  operation. Clients send operation *requests* (carving, dumping,
  tamping, ball carving, pouring) with parameters already validated on the client for
  an immediate local response.
- **Replication:**
  1. `op_apply` (reliable RPC) with the same uniform package the GPU uses
     (position, radius, depth, mode, op index).
  2. **Optimistic local prediction** on the client for its own shovel (the player
     sees their groove instantly) + reconciliation: if the host rejects or corrects, the
     client re-applies the confirmed ops on a clean copy.
  3. **Periodic resync**: every 10 s and when a player joins, the host sends an
     **RLE patch** (only changed cells) or a **reduced map** (e.g. 128²
     quantised to 16 bits in 4 channels ≈ 128 KB) compressed. Budget:
     **≤ 30 KB/s per client in normal operation**, peaks of 150 KB on resync.
  4. **Sufficient determinism**: the shader has to be audited to avoid
     `sin/cos/pow/exp/normalize` on the relaxation path (they are not
     bit-exact across GPUs) and to stick to `+ - * / min max clamp step mix`.
     Accepted tolerance: ±1 texel of drift, which the periodic resync cleans up.
     If the audit fails, **plan B**: the host sends RLE patches every 2 s and the
     client does not simulate, it only interpolates (more traffic, zero risk).
- **Bodies (players, balls, props):** `MultiplayerSynchronizer` with the authoritative
  host and client interpolation. Special cases:
  - A ball **in a client's hands** → local prediction of the carry, the host
    validates the position and the throw (the impulse is calculated on the host from
    the mass and the look direction).
  - **Stacking joints** (weld): only the host creates/breaks them; they are replicated
    as an event.
  - **Breaking on impact**: a host event (position, mass, seed) so that the
    fragments come out the same on every screen.
- **Target latency budget:** playable up to 120 ms. For a cozy game
  without fine aiming it is acceptable; snow does not need perfect interpolation.
- **Initial level load:** the initial state of the snowpack is generated with a **shared
  seed** (deterministic on every machine, without transferring the texture).
- **Service:** Steam Datagram Relay (no ports, no NAT to configure) +
  Steam Lobby. It is what the player expects from a €7 game.

**DECISION MADE (option 4 of the previous plan).** With 2 players and this scope,
**plan A is implemented exactly as described above: the client simulates, predicts its
own ops and the host corrects with periodic RLE patches**. Reasons:

1. The client simulates because that is what *feels* right (your shovel responds on the
   frame in which you move it) and because we already have the engine built: not
   simulating would mean inventing a fake presentation layer.
2. The host remains the authority for the **scoreboard** (mass and %), so a
   drift in the client's texture is cosmetic and never affects progress or
   achievements: there can be no cheating or odd scores.
3. **Mandatory 2-week spike** before committing to the co-op milestone: two
   headless instances replicating ops + resync, measuring (a) mass drift per
   minute, (b) KB/s per client, (c) ms of network CPU. Acceptance thresholds:
   **drift < 0.5% per level and < 30 KB/s on average**.
4. If the spike fails those thresholds, plan B is already defined and **it does not change
   the game design**: the client stops simulating and only interpolates the host's
   patches (more traffic and less immediacy, same fun). And if the shader's determinism
   causes problems, the resync is cut to every 2 s and that is it: in a cozy game
   nobody is going to notice a groove that appears 2 seconds late.

---

### 6.6 Balls, pranks and states: the social layer ⬜

The exact numbers live in `plan_implementacion.md` §3.2; here is the design.

**Impact of balls on players** (only in **Ruckus** and **Duel** mode; in
**Work** the balls do not affect). The ball has to come **thrown**, not rolling:

| Ball | To the **body** | To the **face** |
|---|---|---|
| **Small** (r < 0.18 m · 1–8 kg) | nothing (only sound and a splash) | **face full of snow** |
| **Medium** (0.18–0.34 m · 8–60 kg) | **destabilised 1 s** | destabilised 1 s **+ snow in the face** |
| **Large** (r ≥ 0.34 m · > 60 kg) | **knocked down 2 s** (drops what they were carrying) | knocked down 2 s **+ snow in the face** |

- **Snow in the face**: it clears itself in **3.5 s** or the player wipes it off
  **manually in 0.6 s**. It does not immobilise: you can walk and hear, you see badly.
  *Normal* setting (it clears itself) / *Realistic* (manual only).
- **Anti-`stun-lock`**: 1.5 s of immunity on leaving any state. A knockdown can never
  be chained on the same person.

**The catalogue of pranks** (each with its own animation and sound, which is what
makes it funny): ball to the face · snow down the collar · burying your partner
(you free yourself by mashing) · blocking the turbine outlet · tipping the wheelbarrow ·
pushing a giant ball downhill at them · trampling their freshly made pile · knocking
their hat off with a ball · leaving footprints on the surface they have just smoothed ·
blocking their door with a snow wall.

**The rules that keep this from being toxic:**
1. **Everything is reversible.** Not money, not stars, not progress. Only time and pride.
2. **It is celebrated and measured.** At the end of the level, a **chronicle** with absurd awards:
   *Best partner*, *Worst partner*, *Most balls thrown*, *Buried 4 times*,
   *Work ruined: 38 kg*, *Tallest pile destroyed*. It is what turns
   "you wrecked it" into "let's do it again".
3. **The victim laughs** (golden rule of pillar 4). If they do not laugh, the prank is
   badly designed.
4. **Session mode** (§6.3): whoever wants to work can; chaos is a choice.

**Snowball duel** (a separate mode, cheap because the mechanic already exists): arena,
2-minute rounds, scoreboard, mutators (giant balls, slippery ice, infinite
snow).

**Solo, this layer does not disappear**: ricochets can leave you with a face
full of snow, and there are **training snowmen** with the same reactions to
practise on and for achievements.

---

## 7. Content: levels

10 levels + sandbox. Each one introduces **one new tool or idea** and
reuses the valley's modular kit.

| # | Level | New idea | Main objective | Optionals |
|---|---|---|---|---|
| 1 | **Entrance** ✅ | shovel, tamping, throwing | clear the path to 90% | do not step on the flowerbed |
| 2 | **The buried car** | mass destination (it cannot be left on top) | free the car | do not scratch the bodywork |
| 3 | **Roof and gutters** | height and avalanche onto your partner | bring the snow down from the roof | leave the gutters clear |
| 4 | **Garden and hedges** | precision (rake, edges) | clear without damaging the hedge | collect 3 lost toys |
| 5 | **Market square** | wheelbarrow and piles | clear the square and fill the truck | make a 2 m pile |
| 6 | **Slope and ski lift** | incline, angle of repose, slides | secure the slope | trigger a controlled slide |
| 7 | **Frozen river** | ice, slush, drain | open the way | fish something out of the ice |
| 8 | **Village street** | pure co-op logistics | load the truck between two | finish with both of you on the task |
| 9 | **Cable car** | verticality, risk | clear the station | climb onto the platform |
| 10 | **Storm / epilogue** | everything together + final snowman | clear the valley | the biggest possible snowman |

**Modular art kit:** 1 base terrain + 1 set of alpine buildings + 1 set of
props (fences, cars, benches, mailboxes, signs, skis) + 1 set of trees +
1 set of rocks/ice. With that and light/weather variations, 10 levels are realistic
for a small team.

**Level authoring (⬜):** a data format (`.tres`/JSON) with: terrain (initial height
map), prop list, mass destination zones, objectives, weather,
allowed tools and lighting. An editor script that exports the level.
That way the sandbox and the challenges reuse the same system.

---

## 8. Art and audio direction

**Art**
- The current style ✅ (low poly, pastel palette, clean shapes) is the right one:
  cheap, readable and it holds up well on small screens.
- Needed ⬜: viewmodels of the 8 tools with animation (idle, use, tilt,
  hit, stow), **visible body of the other player** (capsule + procedural
  arms are enough), prop set, UI icons, particle set (kicked-up
  snow, break cloud ✅ exists, footprints, slush splash).
- Snow performance: deformable mesh + surface detail (sparkles, footprints)
  as cheap *decals*.

**Audio** (key in this genre: **it is 50% of the satisfaction**)
- Layers of snow *crunch* according to material, depth and tool.
- Sounds of "scoop", "tip over", "soft impact", "broken crust", "water".
- Ambience: wind by altitude, crows, distant village, radio in the house.
- **Adaptive music by progress:** more instruments as the % of
  clearing goes up. It is an extremely cheap dopamine trick.
- Voices: none dubbed (for cost). Only short subtitled exclamations
  ("ouch!", "watch out above!"). Co-op uses system/Steam voice.

---

## 9. UX / UI: screen map

```
[Boot: logo → shader compilation/settings load]
   ↓
[MAIN MENU] — live 3D scene in the background (slow camera over the snowy village)
 ├── Continue
 ├── New game ─────────────► [Profile/slot selector]
 ├── Co-op ────────────────► [LOBBY] ──► [Level] ──► [Results]
 ├── Levels ───────────────► [Valley map / card grid]
 ├── Workshop (shop) ──────► [Tools + upgrades + cosmetics]
 ├── Extras ───────────────► [Achievements · Statistics · Gallery (photo mode) · Credits]
 ├── Options ──────────────► [Video · Audio · Controls · Game · Accessibility · Network · Data]
 └── Quit
```

**In-game**
- **HUD** (diegetic, minimal): % cleared and remaining mass, money, current
  tool + load ✅, active objectives with a tick, destination zone marker,
  subtle compass, partner indicators (name, colour, volley ping), contextual
  hints ✅ (one line, no invasive tutorials).
- **Pause** (host in co-op): resume · objectives · options · invite (host) ·
  leave · "take a photo".
- **Results**: final %, kg moved, efficiency, time, stars, money
  earned, per-player contribution bars, automatic screenshot.

**Critical flows to look after**
1. From "opening the game" to "I am shovelling": **≤ 3 clicks / ≤ 20 s**.
2. From "I am being called to play" to "I am in" (overlay invite): ≤ 60 s.
3. Changing tool without opening menus (wheel or 1-8).
4. Always knowing what is missing without reading anything (bar + marker in the world).
5. Leaving and coming back in without losing progress (save on leaving the level).

---

## 10. Settings (complete catalogue)

| Category | Options |
|---|---|
| **Video** | Preset (Low/Medium/High/Ultra/**Auto**) · resolution · windowed/borderless/exclusive · **resolution scaling** (0.5–1.0) · VSync · FPS limit · FOV · motion blur · depth of field · bloom · shadows (quality/distance) · SSAO · volumetric fog · **snow quality** (sim resolution 256/384/512/768 + mesh subdivision) · particle density · draw distance · HDR · gamma/brightness · sharpness |
| **Audio** | Master · music · effects · ambience · voices · output device · **mono mode** · dynamic range compression · ducking · "reduce repetitive sounds" |
| **Controls** | Full remapping (keyboard+mouse and gamepad) · presets · sensitivity (and per zoom) · invert X/Y · dead zone · response curve · vibration · **hold vs toggle** (sprint, crouch, `E`, pouring) · button inversion · pRuckusts by device (Xbox/PS/Switch) · Steam Input |
| **Game** | Language · **units (metric/imperial)** · difficulty/assistance (Relax ↔ Work) · autosave · tutorial hints · objective markers · mass warnings · telemetry (opt-in) |
| **Accessibility** | Subtitles (enable/size/background) · **UI size** (80–150%) · colour blindness (3 palettes + high contrast) · motion/camera reduction · **disable head bob** · *screen shake* sensitivity · no timed input (genre rule) · hold-to-press toggleable · everything remappable · HUD text-to-speech (optional) |
| **Network** | Region · ping limit · voice (enable/push-to-talk/per-player volume/mute) · privacy (friends-only invites / open) · show player pings |
| **Data** | Save slots · export/import progress · delete progress · Steam Cloud status · save version |

**Settings design rules:** every change applies **live**; everything is saved
in a user configuration file separate from the game save;
"Restore defaults" per category; and no setting can make the game unplayable
(if a preset is too low, a warning is shown).

---

## 11. i18n and accessibility

### Target languages (phase 1) — the reference's 13
English, Spanish (Spain + Latin America as variants), French, German, Italian,
Portuguese (Brazil), Polish, Russian, Czech, Simplified Chinese, Traditional Chinese,
Japanese, Korean. **Text only** (interface + subtitles), no voice-over.

### i18n architecture
- **Semantic keys**, never concatenated literals:
  `HUD_CLEARED_PCT` = `Despejado: {pct}%`.
- **Plurals from day 1** with per-language rules (`tr_n`): Czech/Polish/Russian
  have 3–4 forms. It is the classic mistake that forces texts to be redone.
- **No assumed grammatical gender**: write neutrally or with per-language
  variants (in Spanish the words for "ball / pile" change gender; avoid adjectives
  about the player's objects).
- **Locale format** for numbers, units and dates (`1.234,5 kg` vs `1,234.5 kg`),
  plus the metric/imperial switch.
- **No text in images**; all text goes through the translation system.

### Fonts and layout
- One family with full coverage (e.g. Noto Sans) + an explicit **fallback
  chain** for CJK and Cyrillic (Godot does not do complete automatic *fallback*).
- **Room for +40% length** (German and Russian grow) and an overflow
  test with **pseudo-localisation** (accented and lengthened text).
- CJK line breaks (without spaces) verified in the text boxes.

### Pipeline
1. Extract keys from the code into a source CSV/PO in the repo.
2. Upload to a TMS (Crowdin/Lokalise/Weblate) for translators.
3. Import compiled translations + **CI that fails if a key is missing in any
   language**.
4. QA mode in the game: it highlights untranslated keys at runtime.
5. Translation credits and font licences.

### Accessibility (the minimum the genre demands)
Subtitles · UI size · colour blindness · motion reduction · **no timed
input** · save anytime · full gamepad support · everything remappable ·
a single gamepad is possible · visual warnings as well as sound ones (an avalanche is
**seen** before it is heard, and the warning is subtitled).

---

## 12. Technical architecture

**Already exists ✅ (engine core)**
`SnowField` (512² GPU ping-pong sim, 64² CPU mirror for queries, op queue,
volume per operation), `snow_sim.glsl` (10 modes), `SnowBall`, `PinProp`,
`PropsSystem`, `SnowChunk`, player controller with tools, HUD, materials
and **3 automatic diagnostic batteries** (`--phys-demo`, `--carve-quality`,
`--ball-shape`). That is a huge asset: it is the foundation of the engine and of the QA.

**Missing ⬜ (the game around the engine)**

| System | Responsibility |
|---|---|
| `GameManager` | State machine: boot → menu → lobby → level → results. Scene loading and transitions. |
| `SettingsSystem` | User config, live application, presets, persistence. |
| `SaveSystem` | Slots, versioned schema, migration, autosave, Steam Cloud. |
| `LocalizationManager` | Language, plurals, locale format, QA mode. |
| `InputManager` | Remapping, per-device pRuckusts, hold/toggle. |
| `AudioManager` | Buses, adaptive music by progress, ducking. |
| `ProgressionSystem` | Money, unlocks, upgrades, statistics. |
| `ObjectiveSystem` | Composable conditions evaluated per tick + final evaluation. |
| `LevelDefinition` | Level data format + loader + editor tool. |
| `NetworkManager` | Host/join, op replication, resync, lobby, session. |
| `PhotoMode` | Free camera, filters, poses, saving. |
| `Achievements` / `Leaderboards` | Steamworks. |
| `Telemetry` (opt-in) | Performance and game funnels, anonymous. |

**Principles**
- **Simulation and presentation separated**: the sim never depends on the render (it
  allows the decoupled simulation tick and the operation-based netcode).
- **All game data in resources**, not in code: tools, levels,
  objectives and texts are data → modding and balancing without touching scripts.
- **A single source of truth for mass**: any future addition (water, ice,
  dirt) goes through the same ledger.

---

## 13. Saving, data and telemetry

- **Save anytime** (genre requirement): on completing a level, on exit and
  every N minutes during play.
- **What is saved:** progress (levels, stars, money, upgrades, cosmetics),
  statistics, settings, and — if the player wants it — **the state of a half-finished
  level** (reduced height map 128² compressed ≈ 30–60 KB per level, not the full texture).
- **Versioned schema** with migration and a backup before overwriting;
  if the save is corrupted, the previous one is recovered and the player is warned.
- **Multiple profiles** (shared room: each person their own progress).
- **Optional** and anonymous **telemetry**: fps, simulation ms, time per level, drop-off
  point, tool usage. It is for balancing, not for monetising.

---

## 14. Performance and compatibility

**Target:** 60 fps at 1080p on an average machine (the genre demands GTX 960 /
4 GB RAM) and running on Steam Deck with the Medium preset.

- **The GPU simulation is the risk.** A layered plan:
  - Simulation resolution presets (256/384/512/768) and mesh subdivision presets.
  - **30 Hz simulation decoupled from the render** (snow does not need 60 Hz).
  - Permanent measurement of simulation ms in the development HUD.
  - **Plan B for weak GPUs**: a "simplified snow" mode (256² sim and
    relaxation every 2 frames) or, at the extreme, small fields per level.
- **Per-frame budget** (16.6 ms at 60 fps): simulation ≤ 3 ms · snow render
  ≤ 4 ms · the rest ≤ 9 ms.
- **Compatibility:** validate on recent Intel integrated graphics, GTX 1050/960, Deck
  and an AMD GPU; Vulkan (Forward+) is the target, with the "low" preset explicitly tested.
- **Load times:** < 10 s per level (seed generation + asynchronous loading).

---

## 15. QA, CI and automatic batteries

The project already has a diagnostic culture that has to be turned into **continuous
integration gates**:

| Battery | Checks | Status |
|---|---|---|
| `--phys-demo` | 36 checks: mass, tools, carrying, pushing, throwing, breaking | ✅ |
| `--carve-quality` | Terrain quality and FPS with a dense mesh | ✅ |
| `--ball-shape` | Clean spheres, density, no false grooves | ✅ |
| `--save-roundtrip` | Save → load → same state and same mass | ⬜ |
| `--i18n-check` | No key untranslated in any language | ⬜ |
| `--settings-apply` | All settings apply live and persist | ⬜ |
| `--net-smoke` | Two headless instances: ops, resync, mass drift < 1% | ⬜ |
| `--perf-gate` | Minimum fps per preset in a stress scene | ⬜ |

In addition: **human playtests** at every milestone (3–5 people, observing without
guiding), and a list of "feelings" to validate: the first minute must be satisfying;
the sound must make you want to keep going; co-op must provoke laughter, not arguments.

---

## 16. Monetisation and publishing

- **Premium**, €6–12 depending on the final content. **No microtransactions, no battle pass.**
- **Public demo** (1 level + sandbox) — essential for the genre and for
  Steam Next Fest.
- DLC/updates: level packs (another season, another village), free cosmetics
  as a thank-you.
- Steam: achievements, leaderboards, Cloud, Rich Presence ("Cleaning the square · 2/4"),
  Remote Play Together (it allows free "local co-op" through streaming).
- Steam Deck: verification (target).
- Store page with GIFs of the *before/after* and of co-op chaos: that is the marketing.

---

## 17. Roadmap by milestones (with exit criteria)

> **The whole system comes before the content.** The fine detail (specs, numerical
> mechanics, Playground and 11 system phases) is in `plan_implementacion.md`
> §2–§5: **~5–6 months of systems** with 1–2 people, without touching content. The table
> below places those systems in the product plan.

| Milestone | Duration | Content | Exit criterion |
|---|---|---|---|
| **M0 — Engine** ✅ | done | Snow, tools, balls, assembly, batteries | 36 OK / 0 failures |
| **M1 — Vertical slice** | 6–8 wk | 1 complete level with menus, objectives, money, saving, settings (video/audio/controls), i18n (2 languages), gamepad, photo mode | 60 fps on the low preset; 20 fun minutes solo; 3 testers want to play more |
| **M2 — Co-op** | 6–10 wk | Network spike → 2-player online co-op: ops + resync, carry prediction, co-op verbs, lobby, nameplates | 30 min with 2 players over the internet without desyncing the % and **more fun than solo** |
| **M3 — Content** | 10–16 wk | 8–12 levels, workshop/upgrades, progression, achievements, sandbox, challenges, 13 languages, accessibility | Campaign completable in 1.5–3 h; 0 untranslated keys; full accessibility |
| **M4 — Polish and launch** | 6–8 wk | Performance, bugs, playtest, store page, trailer, demo, locs, Deck | Frame budget met on 4 configurations; demo with D1 retention > 25% |

**Total: 9–12 months** with 1–2 people + contracted art. The engine (the most
expensive part) is already done, which is what makes this schedule realistic.

---

## 18. Risks and mitigations

| Risk | Impact | Mitigation |
|---|---|---|
| Netcode over a deformable field | **High** | A 2-week spike before promising co-op; plan B (client only interpolating); replication by operations + RLE |
| Simulation performance on modest GPUs | **High** | Presets, 30 Hz sim, permanent measurement, simplified-snow plan B |
| The sandbox eats the game (scope creep) | Medium | Objectives and levels first; the sandbox is a mode, not the product |
| Co-op = "two people doing separate tasks" (boring) | **High** | Every level has **at least one object that needs two people** |
| Content (10 levels + art kit) | Medium | Modular kit + weather/light variations; 1 level / 2–3 weeks |
| Determinism across GPUs | Medium | Shader audit; ±1 texel tolerance; resync |
| Late i18n (reworking texts) | Medium | Plurals and locale format from day 1; pseudo-localisation in M1 |
| Player fatigue from money grind | Low | Levels unlock by progress; money buys convenience, not keys |

---

## 19. Success metrics

**Game (playtest):** time to first satisfaction < 60 s · % of the level
completed on quitting (high = it hooks) · "would you play another level?" · co-op
session length · laughs per minute (literally: it is a physical comedy game).

**Product:** demo-to-wishlist conversion · demo D1 retention ·
positive reviews (> 90% is the niche standard) · median hours 2–6 h ·
stability (0 crashes per 100 sessions).

**Technical:** simulation ms per preset · desync rate per co-op session ·
average traffic per client · p1 fps (the worst 1% of frames).

---

## 20. Decision status

### Closed

| Topic | Decision |
|---|---|
| **Co-op** | **Exactly 2 players**, online through Steam, with *Remote Play Together* for the couch. |
| **Solo and co-op** | **Both are first class.** 100% of progress is achievable solo; co-op adds extra stamps that block nothing. It is solved with a system (`PlayerCountScaler`), not by cutting levels. |
| **Price and scope** | **€6.99**, scope and length similar to the reference, compensating with **replayability** (2–3 runs for the Winter Book) and with the social layer. Free demo. |
| **Platforms** | **Steam + Steam Deck verified** and **full console gamepad support** (Xbox/PlayStation/Nintendo). |
| **Achievements** | **Shared**: a single set, they unlock for both at once in co-op, and **none requires a second person**. |
| **Snowman** | **An optional and fun extra**, never an objective. |
| **Netcode** | Authoritative host for the scoreboard + a client that simulates and predicts + correction via RLE patches, with a mandatory *spike* before the network phase (`plan_implementacion.md` §6.5 and §7.8). |
| **Session mode** | Work / **Ruckus** (default with friends) / Duel. |
| **Public lobbies** | **No** in v1: by default **friends only**. Ruckus with strangers does more harm than good; the Duel is also between friends. |
| **Title** | **Snow It Together**, working title. |
| **Location** | **Undecided** and with no impact on the design: no mechanic depends on the setting. |

### Open (decided with data, not before)

1. **Help for the solo player** if 100% solo turns out to be heavy going: a shovel quad,
   a neighbour who helps out, or nothing. The phase 5–6 playtest decides it.
2. **What else "Realistic mode" does** besides removing the automatic cleaning of the
   face (fatigue? real weight? no aim assistance?).
3. **Final setting** (once chosen): it only changes the art and the levels, not
   the systems.
4. **Duel content**: number of arenas and mutators, depending on how much people play it
   in the playtest.
