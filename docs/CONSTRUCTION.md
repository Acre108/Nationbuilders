# Construction sites

Anything you place, apart from roads, goes up as a construction site. Carriers bring its materials, the building rises, and then it opens. The sim lives in [sim/village_sim.gd](../sim/village_sim.gd) (`sites`, `place()`, `_build_sites()`). The look is in [view/construction_layer.gd](../view/construction_layer.gd).

## How a site works

1. **Placing.** The tiles are taken straight away and trees on them are cleared. The treasury pays at once: it funds the site's purse with the price of the materials and the building's working money (a house's grant, a workshop's input purse, a storehouse's capital). Founding supplies that are still outside any storehouse go straight onto the site for free.
2. **Waiting for materials.** Carriers bring the cost one unit at a time, from the nearest storehouse or straight from a producer's output. The site pays the seller the chain price on delivery, never the household markup. Carriers serve sites after house pantries and before workshop inputs, oldest site first, so sites finish one by one instead of all creeping along together. A site with no road frontage says "No road".
3. **Building.** Once every unit is on site, it builds for `BUILD_TICKS_PER_MATERIAL` (15) ticks per unit of cost, with a minimum of `MIN_BUILD_TICKS` (30). Low morale slows building the way it slows every workplace. At 5 ticks a second:

   | Building | Cost | Build time |
   | --- | --- | --- |
   | Cottage, well | 3 logs | 9 s |
   | Farm, woodcutter, hunter | 4 logs | 12 s |
   | Mill, bakery | 8 logs | 24 s |
   | Storehouse, inn | 10 logs / 10 logs + 4 planks | 30 s / 42 s |
   | Chapel | 12 logs | 36 s |

4. **Finished.** The materials count as consumed. The site joins `buildings` and takes up its role: a storehouse gets its carriers, and a hall joins its faction. The rest of its purse becomes its working money. The event log records "<Building> finished at tick N".

While it is a site, it isn't in `sim.buildings`. That means it has no workers, needs, family, owner or faction pull, and nothing else in the village counts it. `sim.structure(uid)` finds either a building or a site.

## Promised stock

Placement checks `available(good)`: stock minus whatever sites are still owed. Two sites can't count on the same logs. Logs a carrier has picked up for a site count as on their way. Logs a carrier is still walking to collect are still in stock, so they count as owed.

## Cancelling

Demolish, or **Cancel** in the site's inspector, clears a site. Its delivered materials go back to the nearest storehouse with room (anything that doesn't fit is lost), and the unspent purse goes back to the treasury. Carriers already on their way turn back with their loads.

## Where sites are off

`construction_sites` is off by default, and these build instantly:

- the founding layouts (`Scenario`), which are founded already built;
- sims made for tests of other systems.

Play turns it on: a new village in the view, and a village founded in the campaign. A save from before sites existed loads with it on.

## Feedback

These follow the Feedback rules in [UI.md](UI.md):

- **Placing:** a wooden thunk and a puff of dust. The plot pops up with scaffold poles and a pale blueprint of the building.
- **Each delivery:** a soft knock as the unit drops onto the pile in its good's colour. The pile stacks crosswise, like a woodpile.
- **Building:** the blueprint gives way to the real building, rising out of the plot as the pile is used up.
- **Finished:** the building pops in with dust and a two-note chime.
- **Inspector:** status ("Waiting for materials", "Building · N s left", or a red "No road"), each material as have/need, a progress bar for the current stage, and **Cancel**. The purse, build time and position are under Details.

## Not yet

- **Builders as a job:** today building needs only time, not a worker.
- **Upgrades as sites:** house tier changes are still instant.
- **Construction priority:** a way to move a site up the queue.
