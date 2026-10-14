# Plan: closing Milestone 1 (week 4 gate)

> **Gate:** One chain playable: grain → flour → bread end to end, with carriers, storage and one house upgrade.

## Where we are (reviewed 15 Oct 2026)

The chain works in short runs and the codebase has grown well beyond the gate:

- **Tests:** current check counts and reference-seed timings (promotion and first bread, both around 23–36 simulated seconds) are in [VALIDATION.md](VALIDATION.md).
- **Since the gate brief:** worker stop/resume, house pantries stocked from the closest supply, happiness, and money in silver with chain-derived prices, wages, a 10% tax and a treasury that pays for construction (see [VILLAGERS.md](VILLAGERS.md)), building rotation, terrain relief and site packages ([WORLD_MAP.md](WORLD_MAP.md) phase 1), the 100 × 100 default map, the SpacesOS environment port, the village art pass, the medieval building kit and the hex world map ([PLAN-world-map.md](PLAN-world-map.md)).
- The sim is still pure, data-driven and deterministic, with conservation checks for every good. The view only sends commands.

**Status: every work item is done except the manual playtest (item 3).** Tag `m1-first-bread` once its notes are recorded. Household savings still drain over runs longer than an hour at default prices (see item 1); that is tracked in [VILLAGERS.md](VILLAGERS.md) §5.6 and does not block the gate.

### Blocker (fixed 14 Oct): the storehouse clogs and starves the chain

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
- [x] Remove unused SpacesOS imports: `assets/town`, `assets/props`, `content/furniture` and `content/furniture_overrides`.
- [x] Configure Git LFS for `*.glb`, `*.png`, `*.wav`, `*.blend`, `*.webp` and `*.jpg`, and commit the outstanding work (checkpoint `060104f`).
- [x] Commit the hex-village work that followed the checkpoint (`4e74c38`, 14 Oct).

### 1. Fix storage saturation (1–2 days), the blocker
- [x] Stop carriers hauling surplus to a storehouse once it holds enough of a good. The storehouse row in `buildings.json` has `"good_limit": 30`. `_find_job` checks it where carriers haul a producer's output to their storehouse, so producers then block at "output full". Pantry clean-outs and cargo returned after a cancelled job are exempt: they must always land somewhere.
- [x] Make sure goods houses need (bread first) can always be stored. Content validation requires `good_limit` × goods ≤ `storage_capacity` (30 × 6 = 180), so every good keeps room for its full limit and `village_sim.gd` needs no special case. Water was the clog, and it is itself a need, so limiting only non-need goods would not have fixed it. One caveat: founding stock above the limit (about 50 logs and 36 berries) can crowd other goods until it is used up.
- [x] Add a sim test with **two houses**: `tests/test_logistics.gd` runs the starter plus the chain, a second house and a forester for 60 simulated minutes. Both houses stay Villagers throughout, no good is ever crowded out of the storehouse, and logs hold steady. On the old code it fails: 32 minutes below Villagers, 44 minutes with the storehouse full, and logs down to 8. It differs from the brief in three ways:
  - It places a **forester**. The starter woodcutter clears every reachable tree by minute 3, so logs fall without one whatever storage does.
  - It sets the **retail markup to 0**, so household budgets cannot decide a logistics test (see the money finding below).
  - It drops **"stored bread recovers above zero"**. With money in place this depends on producers' working capital, not on storage space.
- [x] Re-run the soak with money in place: `tools/soak_village.gd` (two houses, a forester, seed 73). Before the fix, and without a forester, the storehouse is full by minute 6, logs reach 0 by minute 15 and both houses fall back to Settlers by minute 30. After it, with the forester, every good settles at 30 and logs never fall below 30. The remaining failure is money, covered in [VILLAGERS.md](VILLAGERS.md) §5.5:
  - At 25% markup, households run out of silver around minute 33 and fall back to Settlers.
  - At the new 10% default, both houses stay Villagers for the hour. But their savings fall from about 3.5 g to about 1 g by minute 60. In a 120-minute run both houses are down to 5 s and "cannot afford logs" by minute 90 (VILLAGERS.md §5.5).
  - At 0% markup, both houses stay Villagers for the hour. But the forester's pay drains the treasury to almost nothing, producers end with no silver, the bakery bakes only to order, and stored bread stays at 0.
- [x] Re-run the conservation and determinism tests. They pass, and the long-run test also checks that cached routes and reservations match a fresh search.

An earlier fix for the same freeze is on the unmerged `overnight-integration` branch (`491f8c2`): a `stock_limit` of 30, a "storehouse full" status, a starter forester and route caches. **Decided 14 Oct: keep this branch's fix.** `491f8c2` is superseded and should not be merged. Its "storehouse full" status is still worth reusing for item 2.

### 2. Make the cause visible (½ day)
- [x] When a producer's output can't be hauled because storage refuses it, the status says "storehouse full", or "storehouse has enough <good>" when the per-good limit stopped it, instead of "output full". A producer with no road to a storehouse still says "output full".
- [x] Show storehouse fill (`n / 180`) and key stocks in a small always-visible bar. It sits beside the gold counter and shows total fill across storehouses, bread, water and logs.
- [x] Inspector workers line: shows assigned / required, "stopped", and the village's idle workers.

### 3. Manual playtest without the helper (½ day)
The gate says "playable", but every recorded run uses scripted coordinates or the **Place mill + bakery** button.
- [ ] One person plays from a fresh start to Tier 2 and bread **using only the toolbar** (place, road, inspect), then keeps playing for 15+ minutes.
- [ ] Record the time to first bread, any confusion and any bugs in [VALIDATION.md](VALIDATION.md).
- [ ] Fix anything that blocks a first-time player. Smaller issues go on the week 7 list.

### 4. Sign-off
- [x] All suites green, including the new long-run stability test (`tools/run_tests.ps1 -Full`, 15 Oct).
- [ ] Playtest notes recorded.
- [x] [VALIDATION.md](VALIDATION.md) updated with the new numbers and a fresh `docs/first-bread.png`.
- [ ] Tag the commit `m1-first-bread`.

**Estimate: about 3 working days after the baseline commit.**

## Not in scope (week 7 gate, noted while reviewing)

These don't block M1, but they will matter soon:

- **Simulation performance: done 14 Oct.** Each speed-up is listed with the cost it removed:
  - Road frontage and route distances are cached per road revision. A* now runs only for the paths carriers actually walk.
  - Reservations are indexed by building slot, instead of `_reserved()` scanning every carrier on each call.
  - A carrier job search that found nothing is not repeated in the same tick until some job changes.
  - Suppliers a buyer cannot afford are skipped before routing.
  - A forestry search that found no site is not repeated until the land, roads or claims change.

  Mean tick cost (`tools/bench_village.gd --sim-only`): the starter fell from 4.8 ms to 0.10 ms, and a 40-building town from 70 ms to 3.1 ms, with p99 from 259 ms to 11 ms. Full snapshots are identical to the uncached code over 6 simulated minutes in four scenarios, including road cuts, demolition and stopped workers. Most of the town's remaining 3 ms is job searches; per-good supply lists are the next step if 3× speed stutters in play.
- **No goals, failure state, seasons or Tier 3.** Week 7 needs all of these ("hard, fun run… harsh sites sometimes fail"). Save/load now exists through campaign saves ([PLAN-world-map.md](PLAN-world-map.md) phase C).
- **Difficulty.** Reaching bread takes 36 seconds and needs no decisions. Week 7 needs real tension: finite deposits, worker scarcity and costs that bite.
- **Happiness has no effect yet.** See the open questions in [VILLAGERS.md](VILLAGERS.md) §6.
