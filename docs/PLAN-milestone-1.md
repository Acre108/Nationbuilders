# Plan: closing Milestone 1 (week 4 gate)

> **Gate:** One chain playable: grain → flour → bread end to end, with carriers, storage and one house upgrade.

## Where we are (reviewed 11 Oct 2026)

On paper the gate is met, and a fresh run confirms it:

- Headless sim suite: **76 checks, 0 failures** (Godot 4.3).
- GPU/input suite: **22 checks, 0 failures** at review time. After the later HUD rework it is 30 checks with 3 failures on 4.3 (see `docs/VALIDATION.md`).
- Reference seed: Tier 2 at tick 237, first bread at tick 359.
- The code is in good shape. The sim is pure, data-driven and deterministic, with conservation checks for every good. The view only sends commands.

It is not ready to sign off yet. The chain stops working in a longer session, nobody has recorded a manual playtest, and the project has no version control.

### Blocker: the starter village stops working after about 20 minutes

The test suite only checks 5 minutes. A 30-minute headless run of the default scenario (mill and bakery placed at promotion) gives:

| Minute | House | Storehouse | Notes |
| --- | --- | --- | --- |
| 3 | Tier 2, satisfied | 179/180 | Already effectively full |
| 12 | Tier 2, satisfied | 180/180 | Water 42, flour 10, bread falling (18) |
| 21 | Tier 2, satisfied | 180/180 | Water 55, flour 22, bread 3 |
| 24 | **Tier 1** | 180/180 | Bread runs out, house downgrades |
| 27–30 | Switches between Tier 1 and 2 | 180/180 | — |

**Cause:** wells and woodcutters never stop producing, and leftover outputs always go to the storehouse. The single 180-slot store fills with water, logs and flour. After that, bread can only be stored when the house frees a slot, so the bakery shows "output full". The HUD never tells the player the storehouse is the problem.

## Work items (in order)

### 0. Baseline (½ day)
- [x] `git init` and commit the current tree as the baseline. `.gitignore` already excludes `.godot/` and `.tools/`.
- [x] Delete the stale failing logs (`artifacts/tests.log`, `tests-installed.log` show 63 checks / 1 failure from an earlier run) and the duplicate root `DESIGN.md`. Keep `docs/DESIGN.md`.
- [x] Delete `.tools/` (~350 MB of Godot 4.3 downloads).

### 1. Fix storage saturation (1–2 days), the blocker
- [ ] Stop carriers from hauling surplus to a storehouse once it holds enough of a good. The simplest version is a per-good storage limit in `buildings.json`, with a default such as 40, checked in `_try_job` for `inventory` targets. Producers then block at "output full", which matches the existing rules and keeps the logic data-driven.
- [ ] Reserve space for goods that houses need (bread first) so they can always be stored, or apply the limit only to non-need goods. Pick whichever keeps `village_sim.gd` simpler.
- [ ] Add a sim test: the starter village plus the chain helper stays at **Tier 2 for 30 simulated minutes** and bread stock never reaches 0 after the first bread. It must fail on the current code before the fix.
- [ ] Re-run the conservation and determinism tests.

### 2. Make the cause visible (½ day)
- [ ] When a producer's output can't be hauled because storage is full, show "storehouse full" instead of "output full".
- [ ] Show storehouse fill (`n / 180`) in the top stock bar.
- [ ] Fix the misleading inspector line "Workers: 0 / 14 available". It shows required vs. total workforce, not what is free. Show "staffed / unstaffed" and the free worker count.

### 3. Manual playtest without the helper (½ day)
The gate says "playable", but every recorded run uses scripted coordinates or the **Place mill + bakery** button.
- [ ] One person plays from a fresh start to Tier 2 and bread **using only the toolbar** (place, road, inspect), then keeps playing for 15+ minutes.
- [ ] Record the time to first bread, any confusion, and any bugs in `docs/VALIDATION.md`.
- [ ] Fix anything that blocks a first-time player. Smaller issues go on the week 7 list.

### 4. Settle the engine version (1 hour)
- [x] Decision: pin **Godot 4.3 stable**. `project.godot`, README and VALIDATION now say 4.3.
- [ ] Install Godot 4.3 locally. The engine at `C:\Program Files (x86)\Godot\Godot.exe` is 4.7.2, so the test wrapper's default still runs 4.7.2.
- [ ] Get the GPU/input suite green on 4.3 (3 build-menu/road failures).
- [ ] The `.uid` files are a Godot 4.4+ feature. 4.3 ignores them; keep or delete them, but don't open the project in 4.4+ by mistake, or it will rewrite `project.godot`.

### 5. Sign-off
- [ ] Both suites green, including the new 30-minute stability test.
- [ ] Playtest notes recorded.
- [ ] `docs/VALIDATION.md` updated with the new numbers and a fresh `docs/first-bread.png`.
- [ ] Tag the commit `m1-first-bread`.

**Estimate: about 3–4 working days.**

## Not in scope (week 7 gate, noted while reviewing)

These don't block M1, but they will matter soon:

- **Simulation performance.** Every house runs a nearest-store route search every tick. Every idle carrier searches all producers. `_reserved()` scans every carrier on each call. This is fine for about 7 buildings; at 15–40 buildings with several storehouses it needs profiling.
- **Houses use only the nearest storehouse.** Goods held in another store don't count, which will be confusing with several stores.
- **No failure state, seasons, Tier 3, save/load or variety in starting sites.** Week 7 requires all of these ("hard, fun run… harsh sites sometimes fail").
- **Difficulty.** Reaching bread takes 36 seconds and needs no decisions. Week 7 needs real tension.
