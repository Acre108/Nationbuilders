# Plan: future refinements

These come from the gameplay-feel review of 16 October 2026 and from building construction sites ([CONSTRUCTION.md](CONSTRUCTION.md)). Each item says what is wrong and suggests a fix. All of them follow the rules in [UI.md](UI.md).

Already done: construction sites, and phase 1 feedback (sounds, pops and dust, and the payday count-up).

## Readability

1. **"s" means both silver and seconds.** "Payday every 40 s" sits next to "−3 g 81 s", and "8 g 16 s" reads like a duration. Give money its own look, such as a coin glyph, or "8g 16s" tinted silver and gold, and keep "s" for time alone. This touches `Economy.format()` and every HUD string that shows money.
2. **The operations overlay's colours fight instinct.** Green means "Could run at full capacity" and blue means "At full capacity", but players read green as best. Make it green for full, yellow for limited and red for down, and fold "ready" into green or show it as an outline. Swap the floating cubes, which look like debug markers, for a small round state icon above the roof.
3. **The "!" offer alerts use colour alone.** The circles differ only by ring colour, which breaks UI.md's rule. Put each faction's emblem or initial inside the circle.
4. **An offer card doesn't say which house it means.** While "They offer 60 s for the cottage" is open, highlight that house on the map, with an outline or a marker, and let a click on the card's text centre the camera on it.
5. **The food panel makes the player wait.** "Measuring food over the last two minutes…" gives no answer for two minutes. Show an early estimate in grey that firms up as it measures.
6. **"favour 0 ↓ −5" on the Factions panel is unclear:** is −5 a trend, a target or a penalty? Say what it is in words or a tooltip. Also label the unlabelled beige segment at the start of the power bar (the Crown?).
7. **The Treasury panel still has sentences,** such as "Payday every 40 s: tax comes in and…" and "none yet; a forester is the first". Move them into tooltips. "Building since then −3 g 81 s" needs plainer wording.
8. **Empty kinds look fine on the top bar.** Water 0 and fuel 0 show in the neutral colour while houses go without. A kind that is empty and needed should turn red, as food does.

## Feedback

9. **Production pulses:** when a workshop finishes a cycle, raise a small icon of its good from the roof, and briefly pulse that kind on the top bar. Make it a toggle in case busy villages get noisy.
10. **A kind reaching zero:** flash or shake its number once.
11. **New offers arrive silently:** slide each "!" in, with a soft bell.
12. **Volume:** add a sound effects volume in Options, with interface sounds on their own audio bus, as the weather has.

## Construction

13. **Builders as a job:** today building needs only time. A builder job, staffed from idle workers, would make labour a real trade-off.
14. **House upgrades as sites:** tier changes are still instant. An upgrade could show scaffolding and need materials.
15. **Site priority:** let the player move a site to the front of the delivery queue from its inspector.
16. **A building's appearance during construction:** the rising building is scaled vertically, which squashes it. A shader that reveals it from the ground up, or stages such as frame, walls and roof, would look better.

## Tests

Done on 13 November 2026: `tools/run_tests.ps1` stops a hung suite after a time limit and reports it as failed (exit code 124); the five stale view checks and the campaign chain fixture follow the current starter and generated sites; the quick tier skips the long runs and prints each file's time.

17. **The hour-long logistics run fails on the economy, not logistics.** "Both houses stay Villagers for an hour" reports 37 minutes below. Silver pools in the first cottage, the founders' home (417 to 531 silver over the hour), while the bakery holds none and cannot buy the flour sitting in the storehouse, the other cottages hover at 0 to 15 silver, and the treasury cannot pay the forester. Starter villages also have no chapel, so every Villager house misses one need. Decide how savings flow back (households spending surplus savings, founders as their own household, or a wage or price change), then retune the test, which still speaks of "both houses" from before family cottages.
18. **Two more full-tier checks fail, outside the village sim:** site generation's "Actual generated lake site keeps its basin and a natural clearing" (`-Sites`), and the art suite's "Zero breeze freezes crown deformation" (`-Art`), likely since the atmosphere changes of 16 October.
19. **The quick tier takes about a minute,** most of it in `test_factions.gd`. A carrier's job search costs about 0.6 ms in GDScript, repeated each tick while houses wait for goods nobody has; caching failed searches across ticks would be the next big saving.
