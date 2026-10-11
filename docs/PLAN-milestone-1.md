# Plan: closing Milestone 1 (week 4 gate)

> **Gate:** One chain playable: grain → flour → bread end to end, with carriers, storage and one house upgrade.

## Where we are (reviewed 11 Oct 2026, evening)

The chain works in short runs and the codebase has grown well beyond the gate:

- **Engine: undecided.** Commit `a686133` pinned Godot 4.3 stable. The current working tree runs on **4.7.2** (Forward+), because the imported SpacesOS lighting and atmosphere need its newer API; 4.3 cannot run them. See work item 0.
- **Tests:** current check counts and reference-seed timings (promotion and first bread, both around 23–36 simulated seconds) are in [VALIDATION.md](VALIDATION.md).
- **Since the gate brief:** worker stop/resume, house pantries stocked from the closest supply, happiness, and money in silver with chain-derived prices, wages, a 10% tax and a treasury that pays for construction (see [VILLAGERS.md](VILLAGERS.md)), building rotation, terrain relief and site packages ([WORLD_MAP.md](WORLD_MAP.md) phase 1), the 100 × 100 default map, the SpacesOS environment port, the village art pass and the medieval building kit.
- The sim is still pure, data-driven and deterministic, with conservation checks for every good. The view only sends commands.

It is not ready to sign off. The storage blocker below is still open, nobody has recorded a manual playtest, and most of the work since commit `c7c0fee` is uncommitted.

### Blocker: the storehouse clogs and starves the chain

The test suite only checks 5 minutes. A 60-minute headless run before money was added of the starter village (seed 73, mill and bakery placed at promotion) gives:

| Minute | House | Storehouse | Stored bread | Water | Logs | Bakery |
| --- | --- | --- | --- | --- | --- | --- |
| 3 | Tier 2 | 162/180 | 19 | 25 | 74 | working |
| 6 | Tier 2 | **180/180** | 24 | 41 | 77 | output full |
| 15 | Tier 2 | 180/180 | 5 | 59 | 70 | output full |
| 24 | Tier 2 | 180/180 | 0 | 83 | 58 | output full |
| 60 | Tier 2 | 180/180 | 0–2 | 105 | 40 | output full |

**Cause:** wells and woodcutters never stop producing, and leftover outputs always go to the storehouse. The single 180-slot store fills with water within six minutes. After that the bakery and woodcutter can only hand goods straight to the house pantry.

**Effect:** the single house now stays at Tier 2, because pantries take bread directly from the bakery. Any second house would starve. Construction logs drain steadily (74 → 40) because the woodcutter can't unload, so the player gradually loses the ability to build. The 33 starting berries also sit in the store forever after promotion. The HUD never tells the player the storehouse is the problem.

## Work items (in order)

### 0. Baseline
- [x] `git init` and a first commit. `.gitignore` excludes `.godot/`, `.tools/` and `artifacts/`.
- [x] Delete the stale failing logs, the duplicate root `DESIGN.md` and `.tools/`.
- [ ] Settle the engine. Either keep **4.7.2** and the SpacesOS environment, or return to **4.3** and drop or rework the environment port. Until this is decided, nobody re-pins either way.
- [x] Remove unused SpacesOS imports: `assets/town`, `assets/props`, `content/furniture` and `content/furniture_overrides`.
- [ ] Configure Git LFS for `*.glb`, `*.png`, `*.wav` and `*.blend` (`assets/` is about 177 MB), then commit the outstanding work in logical chunks: environment port, art and buildings, sim and HUD, world map.

### 1. Fix storage saturation (1–2 days), the blocker
- [ ] Stop carriers hauling surplus to a storehouse once it holds enough of a good. The simplest version is a per-good storage limit in `buildings.json`, for example a default of 40, checked in `_try_job` for `inventory` targets. Producers then block at "output full", which matches the existing rules and keeps the logic data-driven.
- [ ] Make sure goods houses need (bread first) can always be stored: either reserve space for them, or apply the limit only to non-need goods. Pick whichever keeps `village_sim.gd` simpler.
- [ ] Add a sim test with **two houses**: the starter village plus the chain stays at Tier 2 for 60 simulated minutes, stored bread recovers above zero, and construction logs don't fall. It must fail on the current code before the fix.
- [ ] Re-run the soak with money in place first: households that cannot afford goods change the flows, so re-measure before choosing the fix.
- [ ] Re-run the conservation and determinism tests.

### 2. Make the cause visible (½ day)
- [ ] When a producer's output can't be hauled because storage is full, show "storehouse full" instead of "output full".
- [ ] Show storehouse fill (`n / 180`) and key stocks in a small always-visible bar. Global resource counters are currently hidden, and the fill only appears in the storehouse inspector.
- [x] Inspector workers line: shows assigned / required, "stopped", and the village's idle workers.

### 3. Manual playtest without the helper (½ day)
The gate says "playable", but every recorded run uses scripted coordinates or the **Place mill + bakery** button.
- [ ] One person plays from a fresh start to Tier 2 and bread **using only the toolbar** (place, road, inspect), then keeps playing for 15+ minutes.
- [ ] Record the time to first bread, any confusion and any bugs in [VALIDATION.md](VALIDATION.md).
- [ ] Fix anything that blocks a first-time player. Smaller issues go on the week 7 list.

### 4. Sign-off
- [ ] All suites green, including the new long-run stability test.
- [ ] Playtest notes recorded.
- [ ] [VALIDATION.md](VALIDATION.md) updated with the new numbers and a fresh `docs/first-bread.png`.
- [ ] Tag the commit `m1-first-bread`.

**Estimate: about 3 working days after the baseline commit.**

## Not in scope (week 7 gate, noted while reviewing)

These don't block M1, but they will matter soon:

- **Simulation performance.** The 60-minute soak above took about 3.5 ms per tick with 7 buildings. Houses and idle carriers search routes every tick, and `_reserved()` scans every carrier on each call. At 20–40 buildings and 3× speed this is likely to stutter. Profile, then cache routes per road revision and index reservations.
- **No goals, failure state, seasons, Tier 3 or save/load.** Week 7 needs all of these ("hard, fun run… harsh sites sometimes fail"). Snapshots already capture all state, so save/load needs a loader rather than new state.
- **Difficulty.** Reaching bread takes 36 seconds and needs no decisions. Week 7 needs real tension: finite deposits, worker scarcity and costs that bite.
- **Happiness has no effect yet.** See the open questions in [VILLAGERS.md](VILLAGERS.md) §5.
- **Pixel mode removal.** Smooth full-resolution rendering is the long-term look (see [DESIGN.md](DESIGN.md#art-direction)). The optional pixel view, its disconnected palette, outline and toon shaders, and the pixel-specific view and art checks are to be removed.
