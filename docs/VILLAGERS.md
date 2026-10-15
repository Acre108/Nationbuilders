# Villagers: workforce, food, happiness and money

**Status:** sections 1–5 are implemented. Section 5 (treasury controls and storehouse trade) landed on 14 October 2026. Later that day carriers became paid jobs, services were formalised, and happiness gained effects (3.1). Section 5.5 records the balance results. Section 6 lists open design questions.

Villagers are still counted per house, as in [DESIGN.md](DESIGN.md). Individual citizens are not simulated. This document covers how houses supply workers, how they get fed, how satisfied they are, and how they earn and spend money.

## 1. Workforce

- Workers belong to families (decided 15 October 2026, docs/PLAN-job-classes.md). Each village house holds one family, whose working adults are its workers; the 4 founding adults live in the first house. Jobs name a class (`jobs` in `buildings.json`). A worker may take a job of their class or a lower one, never a higher one, and jobs go round the families of a class so each family gets one before any gets a second (`sim/labour.gd`).
- Buildings are staffed in placement order. A building is staffed only when the whole crew it needs (`workers` in `buildings.json`) is free.
- **The player can stop any building that employs workers** (`set_workers_enabled(uid, false)`, or **Stop workers** in the inspector). A stopped building:
  - releases its workers to the next buildings in order;
  - shows the status "workers stopped";
  - receives no input deliveries, although carriers still collect any finished output.
- **Carriers are jobs too** (decided 14 October 2026). After buildings are staffed, each storehouse's carriers take idle workers, in placement order, up to its `carriers` count.
  - The storehouse's `crew` is how many of its carriers are on shift. Carriers already on a trip count toward the crew first, so they can finish it. The rest of the crew goes to idle carriers in order.
  - An off-shift carrier waits at its storehouse and takes no job.
  - The starter village has 10 workers. Its buildings take 5, so it runs 5 of 6 carriers. Every new workplace takes carriers away until more houses are built.
  - The storehouse inspector shows "n of 6 on shift" and "short of workers".
- The village's idle workers, those left after buildings and carriers, are reported each tick as `idle_workers`. The inspector shows them next to each building's crew.

This lets the player direct labour when there is not enough of it. For example, stop the woodcutter to staff the bakery, or to put more carriers on shift.

**Labour priority** (decided 15 October 2026). Each workplace, and each storehouse for its carriers, has a priority: low, normal (the default) or high, set in the inspector (`set_priority(uid, level)`).
- Workers fill high-priority jobs first, then normal, then low.
- Within a level, buildings are staffed in placement order before that level's carriers. So with every building at normal, carriers still come after buildings.
- A high-priority storehouse keeps its carriers on shift ahead of normal workplaces.

## 2. Food reaches houses by carrier

- Each house has a **pantry**: its six-slot `input` storage.
- Carriers keep the pantry stocked with every good the house's tier eats. The target is two consumption cycles of each good (`PANTRY_CYCLES`), capped at an equal share of the pantry.
- **Every delivery comes from the closest supply by road.** That is either a storehouse's stock or a producer's finished output, whichever has the shortest route to the house. A well next to a house supplies it directly. Producer inputs follow the same rule.
- Houses are stocked before workshop inputs: villagers eat first.
- When a house changes tier, carriers take pantry goods the new tier no longer eats (berries, after promotion to Villagers) back to their storehouse.
- A house without road access gets nothing. Its status reads "missing road access".

Distance now matters for housing. A house far from its supply waits longer for each delivery and ties up carriers for longer.

## 3. Happiness

- Each consumption cycle (`consume_every_ticks`), a house tries to eat each need on its own, from its pantry.
- A need missing at the start of the cycle still counts if it arrives before the cycle ends.
- **Happiness = needs met this cycle ÷ needs of the tier**, as a percentage. A Villager house with water and bread but no logs is at 67%.
- Shelter is not counted, since every house has it.
- **Service needs** (15 October 2026). A tier can need a service, listed in its `services` in `tiers.json`. Villagers need a **chapel**.
  - The need is met while a staffed building that `provides` it is within its `service_radius` (20 tiles for a chapel) of the house by road.
  - It counts like a good, so a Villager house has four needs. With water, bread and logs but no chapel, it is at 75%.
  - The chapel is a public service: the treasury pays its priest (5.2). It unlocks with Villagers and costs 12 logs.
  - Its inspector shows how many houses it serves.
  - Content validation requires every tier service to be provided by some building.

### 3.1 What happiness does

Decided 14 October 2026. The rules live in [sim/needs.gd](../sim/needs.gd).

- **Settled happiness.** Happiness swings within a cycle: it starts at 0 and rises as goods are eaten. So effects use each house's **settled happiness**: the average of its last 3 completed cycles (`happiness_history`, `Needs.settled()`).
  - A new house, or one that has just changed tier, has none until its first full cycle, and is left out until then.
- **Promotion is unchanged.** A house with all of its needs met (100%) for `upgrade_after_ticks` moves up a tier.
- **Demotion threshold.** A house demotes when its settled happiness stays below its tier's `downgrade_below_happiness` (50%, `tiers.json`) for `downgrade_after_ticks`.
  - One missing good is survivable. A Villager house without logs settles at 66% and keeps its tier.
  - Two missing goods (33%) demote it.
  - The inspector shows the settled value, the threshold and the countdown.
- **Village morale and workplace speed.** Morale is the houses' settled happiness, averaged with each house weighted by the workers it provides. Morale is full while no house has settled.
  - Every workplace works at `50% + morale ÷ 2` of full speed (`Needs.work_speed()`): 100% at full morale, 83% at 66%, 50% at 0.
  - The sim spreads this evenly: at 75% speed, workplaces advance on 3 ticks in every 4.
  - Producers, workshops and forestry all slow. Carriers and houses do not.
  - Below full speed, a workplace's inspector shows "Speed 83% · village morale 66%".
- **Not done here.** Happiness does not change how many workers a house provides. Unhappy households will cause problems of their own through factions, such as striking unionists ([FACTIONS.md](FACTIONS.md) §6). Factions can read `Needs.settled()` per house.

## 4. Money

The rules live in [sim/economy.gd](../sim/economy.gd).

### Units

Money is held in whole **silver**, and 100 silver make 1 **gold**. Villagers and prices use silver. The treasury is the player's and is shown in gold. Silver keeps cheap goods whole: if prices were whole gold, every stage of a chain would at least double a good's price.

Money is closed. The treasury (reserves included), the payroll and every building's silver always sum to the founding treasury of 10 gold, and the tests check this.

### Prices come from the chain

**Every link in a chain pays the one before it.**
- The mill pays for its wheat.
- The bakery pays for its flour and water.
- A house pays for its bread.
- A storehouse pays for what it collects, and is paid for what it hands out. Households also pay it a markup, which goes to the payroll as its carriers' wages (5.3).

A good's price is its inputs plus the labour of the building that made it:

> price = inputs ÷ units made + ⌈ `WAGE` × workers × cycle ÷ payday ÷ units made ⌉

Here `WAGE` is 10 silver per worker per payday, and a payday is 200 ticks. Each stage adds its own labour, so goods further down a chain cost more:

| Good | Made by | Inputs | Labour | Price |
| --- | --- | --- | --- | --- |
| Water | Well | – | 2 s | **2 s** |
| Wheat | Wheat field | – | 4 s | **4 s** |
| Logs | Woodcutter | – | 7 s | **7 s** |
| Flour | Windmill | 4 s wheat | 5 s | **9 s** |
| Bread | Bakery | 9 s flour + 2 s water | 5 s | **16 s** |
| Berries | Berry bushes | – | 2 s | **2 s** |

Prices are worked out from `buildings.json` when the sim starts. A good that no building makes needs a `price` in `goods.json`, and content validation enforces this.

### Wages and taxes

- **Wages are paid per sale.** When a producer sells, it keeps the input part of the price to buy its next inputs. It passes the labour part to the **payroll**.
  - A workshop's purse therefore stays level, and a half-idle bakery never goes broke.
  - Wages follow what the village actually sells. Goods nobody buys earn no one anything.
- **Payday** (every 20 s) pays each family what its members earned: a producer's labour goes to its crew's families, a storehouse's markup to its storekeeper (30%) and carriers, and a service's pay to its staff. **A family with no job earns nothing.** Silver nobody earned (a sale while a building stood unstaffed) is shared between houses by workers, with spare silver rotating, as all wages were before 15 October 2026.
- **Tax** is withheld at payday into the treasury: 15% of wages by default (raised from 10% on 15 October 2026; see 5.5), set in the Treasury panel (5.1). Tax and storehouse surpluses (5.3) are the treasury's income.
- **Public services.** Buildings marked `"service": true` in `buildings.json` (the forester so far) sell nothing. The treasury pays their workers at each payday: 10 s per worker, from the public pay reserve first (5.2). Unpaid public workers keep working, and their frustration grows. Content validation requires every producer that sells nothing to be a service.

### Spending

- **Households** pay for each delivery to their pantry.
  - A carrier is sent only if the buyer's silver, minus deliveries already on their way to it, covers the price. This applies to every buyer, not only houses.
  - A house that can't pay goes without: "cannot afford bread".
  - When pantry food is taken back after a tier change, the storehouse buys it back.
- **The treasury spends gold on construction:**
  - **Materials.** It buys construction logs from storehouses at their price. Founding supplies are free.
  - **Working money.** It gives the new building its starting silver:
    - a house: 50 s;
    - a storehouse: 100 s, for trading;
    - a workshop: enough to fill its inputs once (24 s for a mill, 33 s for a bakery).
  - **Affordability.** Placement fails with "Treasury needs …" when the gold construction may use (everything but the public pay reserve, 5.2) can't cover it. The build card shows what the treasury pays.
- **Demolition** returns a building's silver to the treasury.

A house costs the treasury 92 s: 42 s of logs and a 50 s purse. A windmill costs 80 s.

### How it behaves

Before section 5, in a 30-minute run of the default village with its mill and bakery (see 5.5 for current results):
- The treasury starts at 10 g and falls to about 5.7 g after the starter village and chain are built.
- Taxes then add about 10 s every 3 minutes with one house.
- Construction spending flows from storehouses to producers and on to households as wages. Building is what creates jobs.
- Workshop purses sit near zero because their silver is held as stocked inputs. Each sale returns it.
- A village that stops building slowly moves its silver into the treasury through tax. The player then either builds, which puts it back into wages, or lowers the tax.

The inspector shows the money at each building:

| Building | Shown |
| --- | --- |
| House | Savings, last payday's wage and tax, and each need's price direct and from a storehouse |
| Workshop | What it sells, for how much, how much of that is wages, and its purse |
| Forester | That it is a public service, its upkeep, what it was paid last payday, and its frustration |
| Storehouse | Carriers on shift and their wages so far, its trading purse and purse cap, its markup, the treasury in gold, and the tax rate |

## 5. Treasury controls and storehouse trade

**Status:** agreed on 11 October 2026 and implemented on 14 October 2026. The player chose:
- manual reserve transfers first, with automatic allocation later;
- unpaid public workers keep working, but a frustration counter goes up;
- only households pay the storehouse markup;
- the margin stays in the storehouse up to a purse cap, and the rest goes to the treasury.

The rules live in [sim/economy.gd](../sim/economy.gd). The panel is in [view/overlays/village_hud.gd](../view/overlays/village_hud.gd).

### 5.1 Gold counter and Treasury panel

- A **gold counter** at the top left shows the treasury. It is the one global counter on the play screen.
- Clicking it opens the **Treasury panel**:
  - the treasury in gold, split into free gold and the two reserves (5.2), with −1 g / +1 g transfer buttons;
  - **tax on wages**, with − and + in steps of 5%, from 0 to 50% (`set_tax_percent`);
  - the **storehouse markup** (5.3), with − and + in steps of 5%;
  - **last payday**: tax, storehouse surplus, demolition refunds, public pay and construction, plus any public wages left unpaid;
  - **net per payday** for the last 6 paydays, newest first;
  - construction spent since the last payday;
  - **services**: each public service type, how many, its upkeep per payday, and any wages left unpaid;
  - public workers' frustration.
- The panel closes with ×, Escape, or by opening options, weather or the build menu.
- Tax does not affect happiness.
- The sim keeps a ledger: `period` accumulates since the last payday, and `ledger` holds the last `LEDGER_PAYDAYS` (6) closed paydays.

### 5.2 Reserves and public pay

- The treasury has three parts: **free gold**, a **public pay reserve** and a **capital reserve**. The reserves are parts of `treasury`, not extra money, so the money total is unchanged.
- The player moves gold by hand: `transfer_reserve("public" | "capital", amount)`. A positive amount moves free gold into the reserve and a negative one moves it back. It moves at most what is there, and fails only if nothing moves.
- **Public pay** (the services of section 4, such as the forester) draws on the public pay reserve first, then free gold. It never touches the capital reserve.
- **Construction** (materials and working money) draws on the capital reserve first, then free gold. It never touches the public pay reserve.
  - Placement fails with "Treasury needs … outside the public pay reserve" when only reserved gold would cover it.
  - The build card's "have" figure counts only gold construction can use.
- **Unpaid public workers keep working.** Each worker left unpaid at a payday adds 1 to:
  - the building's `frustration`, shown in its inspector;
  - the village's `public_frustration`, shown in the Treasury panel. This village-wide count survives demolition. A faction system will later read it as trade union contentedness.
- A partly paid crew counts each worker whose wage was not covered. Frustration does not decay yet. When it should is a faction-system question.
- **Reserve target.** "Keep 2 paydays of services reserved" in the Treasury panel (`set_keep_service_reserve`) tops the public pay reserve up from free gold at each payday, to twice the services' upkeep. It runs after taxes, so new income funds it first. Off by default.
- Not built: automatic allocation of a share of income to the capital reserve.

### 5.3 Storehouse markup and purse cap

- **Storehouses sell to households at a markup:** `retail = price + max(1, round(price × markup%))`. The default markup is **10%**.
  - Bread costs 18 s from a storehouse and 16 s straight from the bakery.
  - Water costs 3 s from a storehouse and 2 s from a well. The 1 s minimum keeps a margin on cheap goods.
  - A markup of 0% removes the minimum too.
- **Everything else stays at chain price:** direct deliveries from producers, every workshop purchase, storehouses buying from producers or each other, pantry buy-backs, and the treasury buying construction logs. So the chain arithmetic is unchanged.
- `spendable()` and `settle()` use `sale_price(buyer, seller, good)`, so a carrier is sent only when the household can pay that seller's price. A house's status reads "cannot afford …" when its silver is below the storehouse price.
- **The markup pays the carriers** (decided 14 October 2026). The storehouse keeps the chain price, which restocks it. The markup goes to the payroll as its carriers' wages, like a producer's labour, and so returns to households at payday. `settle()` computes it as one `work` value, where a future owner's share can be split off ([FACTIONS.md](FACTIONS.md) §5.1). The inspector shows the carriers' wages so far (`wages_paid`).
- **Purse cap.** At payday, storehouse silver above the purse cap goes to the treasury as **storehouse surplus**. Now that the markup pays carriers, this is rare: mostly the founding logs the treasury buys back. The cap is the larger of:
  - 2 g (`PURSE_CAP`, twice a storehouse's starting capital);
  - the silver needed to restock, up to the per-good `good_limit`, every good the village currently makes.

  A storehouse with empty shelves therefore keeps construction money and spends it on producers' output. A full storehouse passes its surplus to the treasury.
- The player sets the markup in the Treasury panel (`set_markup_percent`, 0–100%, in steps of 5%).

### 5.4 Saves

New sim snapshot keys: `public_reserve`, `capital_reserve`, `markup_percent`, `public_frustration`, `period` and `ledger`. Buildings gain `frustration`, `wages_paid`, `crew` and `happiness_history` (at most 3 whole values from 0 to 100). Carriers' `_on_shift` is derived each tick and not saved. Snapshots with reserves larger than the treasury, or with malformed ledger entries, are rejected. Version-one campaign saves load with these fields at their defaults.

### 5.5 Balance results

**Current rules** (carriers paid from the markup and staffed from the workforce, happiness effects, 10% markup). Two-hour headless soaks, seed 73 (`tools/soak_village.gd`):

| Village | Tax | Result after 120 min |
| --- | --- | --- |
| 2 houses + forester | 10% (default) | Tier 2 throughout, with savings steady at about 5 g and 4.5 g. The treasury runs dry by minute 50: the forester's 10 s a payday is more than tax brings in, so it goes partly unpaid and frustration rises. |
| Same | **15%** | **Balanced.** Tier 2 throughout, with savings steady at 2.3–3.3 g. The treasury drifts from 4.9 g to 4.4 g, and the forester is paid. |
| Same | 20% | Households drained to about 5 s by minute 80 ("cannot afford logs"), still Tier 2. The treasury holds 9.5 g. |
| 1 house + forester | 10% | Tier 2 throughout. The house holds 9.8 g and the treasury 3 s, so the forester goes partly unpaid. |
| 1 house, no forester | 10% | Logs run out (no forester). At 66% the house keeps Tier 2, as intended, but tax moves its savings to the treasury. It cannot afford bread by minute 60 and is Tier 1 by minute 80. |

What changed:
- **The markup no longer drains households.** It comes back as carrier wages, so only tax leaves them. The two-house village that went broke by minute 90 now holds its savings.
- **Tax against services is now the balance.** With no service, tax slowly moves all money to the treasury. With one forester and two houses, 15% tax balances it. That is the Treasury panel's job, and the panel shows unpaid services.
- **Demotion is gentler.** A missing good costs morale and speed, not the tier.

**Playtest, 15 October 2026** (`tools/playtest_village.gd`, real input only, seed 73, 3× speed, 15% tax, 10% markup). The bot plays from the playable start through the toolbar, the build menu, map clicks, the inspector and the Treasury panel.
- It plants berry bushes and a forester, reaches Villagers at 0:22, builds a mill, bakery and chapel, gets first bread at 0:36, and adds a second house.
- Both houses are 100% happy (settled 100%) from minute 1 to minute 13. All 6 carriers stay on shift, and the chapel serves both houses.
- **Logs run out at about minute 14.** The forester was placed beside the village and reports "no planting space nearby" all game, because it keeps the clearing open. So the woodcutter runs out of trees. One house misses logs (75%), morale drops to 83%, and workplaces slow to 91%. The forester's placement card does not warn about this.
- **The treasury drains** from 3.84 g to 0.28 g in 15 minutes. The forester and chapel cost 20 s a payday, more than two houses' tax at 15%. Households save about 4.6 g each. The panel's "Net per payday" shows −10 to −12 s throughout. The player's levers are more houses, a higher tax, or dropping a service.
- **The bakery bakes to order.** It reads "missing input flour" with an empty purse while the storehouse holds 30 flour, but bread stock stayed at 5–19.
- The playtest found and fixed two inspector bugs: the house counted "4 of 3 needs", and the chapel showed an empty recipe.

**Earlier results, before carriers were paid** (14 October 2026). Hour-long headless soaks, seed 73 (`tools/soak_village.gd`, with the storehouse `good_limit` of 30):

| Village | Markup | Result after 60 min |
| --- | --- | --- |
| Starter + chain, 1 house, no forester | 25% | House out of silver by minute 30 ("cannot afford water"), Tier 1. Treasury 5.9 g → 8.0 g. |
| Same | 10% | Logs run out first (no forester, "no mature trees nearby"), then silver. Tier 1 by minute 40. |
| Same | 0% | Logs, then berries run out. Tier 1 by minute 50. |
| Starter + chain, 1 house + forester | 10% | Tier 2 all hour. Public pay empties the treasury by minute 30, so the forester goes partly unpaid. The house hoards about 8 g. |
| 2 houses + forester | 25% | Households drained by minute 30. Tier 1 by minute 50, then stuck: nobody makes berries. |
| Same | **10% (default)** | **Tier 2 all hour.** Savings fall from 3.5 g to 1.3 g and 0.8 g, and the treasury rises from 3.2 g to 5.9 g (minute 15 to 60). In a 2-hour run, both houses are down to 5 s by minute 90 and stay there ("cannot afford logs"). They are still Tier 2 at minute 120, but only just. The treasury holds 7.5 g that never comes back out. |
| Same | 5% | Tier 2 all hour, close to balanced: savings about 3 g, treasury 2.3 g. |
| Same, tax 5% | 10% | Tier 2. The treasury empties by minute 20, so public workers go unpaid. |

What this shows:
- **The treasury collects; only construction and public pay spend.** Bread, flour, wheat, water and logs are all labour. So what households spend at chain price comes back as wages, minus tax. The markup and tax drain households toward the treasury. Public pay and building are the only ways back.
- No single default balances every village. With no public workers, any markup or tax drains households. With a forester, public pay can drain the treasury. Balancing the two is the player's job in the Treasury panel. At 10%, two houses and a forester hold Tier 2 for the hour.
- Two of the failures are content gaps, not money: no village makes berries, and without a forester the woodcutter runs out of trees.
- 25% was the proposed markup, but it drained households within 30 minutes in every layout, so the default is now 10%. That only slows the drain: without the player building or adding public workers, households are broke by minute 90 (see 5.6, recycling the margin).

**Tests.** `tests/test_sim.gd` (`_treasury`, `_money`, `_carrier_jobs`, `_services` and `_happiness_effects`) covers:
- carriers staffed after buildings, with no more working than the crew;
- the markup paid to carriers through the payroll;
- service validation;
- settled happiness, the demotion threshold, morale, and half speed at zero morale;
- tax limits;
- reserve transfers, and that construction and public pay each leave the other's reserve alone;
- frustration from unpaid public workers, who keep working;
- the markup only on household purchases from storehouses;
- the purse-cap sweep and ledger;
- snapshot round-trip and rejection;
- money conserved with reserves inside the treasury.

`tests/run_view_tests.gd` (`_check_treasury`) drives the gold counter, tax buttons and reserve buttons through real input. `tests/test_campaign.gd` checks that version-one saves without these fields still load.

### 5.6 Settled and still open

Settled:
- 14 October 2026: the margin pays carriers, and the treasury spends on services (5.3, section 4).
- 15 October 2026: the player sets the markup (5.3), the default tax is 15% (5.5), the chapel is the second service (section 3), and a public pay reserve target exists (5.2).
- **When frustration decays** is left to factions. Union favour reads unpaid workers over the last 6 paydays, and `public_frustration` stays as a lifetime record ([FACTIONS.md](FACTIONS.md) §7).

Still open:
- Automatic allocation of a share of income to the capital reserve.

### 5.7 Economy test village

A fixed village for balance work at a larger scale than the soaks in 5.5. It has eight homesteads, every public service, and producers sized for eight Villager houses, so money is what is under test. It is `Scenario.economy_test(sim, halls)` in `sim/scenario.gd`.
- **Run it headless:** `Godot.exe --headless --path . --script tools/economy_village.gd -- [--minutes=30] [--tax=15] [--markup=10] [--reserve] [--halls] [--every=N]`. It prints one row a minute (tiers, happiness, morale, treasury, the minute's ledger, wages, household and storehouse purses, stock), then goods made and eaten per minute and a findings list.
- **Watch it in the game:** `Godot.exe --path . -- --scenario=economy` (milestone 1 map only).
- **Test:** `_economy_village` in `tests/test_sim.gd` checks that it builds, that every job is staffed, that every house touches a road and has a chapel in range, that every need has a maker, that all houses reach Villagers within 3 minutes, and that money is conserved.

**Layout** (milestone 1 coordinates; `=` road, `H` homestead, `+` chapel, `S` storehouse, `F` farm, `M` mill, `B` bakery, `W` well, `w` woodshed, `C` woodcutter, `P` forester, `E` berry bushes, `U`/`A` optional union hall and alehouse, `f` forest; columns run from x = −1 to x = 39):

```
  12 .f..f..f..f.....f..f..f..f......++.......
  13 f..f..f..f..f........f..f....HH.++.HH.HH.
  14 ..f..f..f..f..f..f........f..HH.++.HH.HH.
  15 .f..f..f..f.................=============
  16 f.....f..f...........=......=HH.HH.HH.HH.
  17 ..f..f..f............=......=HH.HH.HH.HH.
  18 .f..fFFF..fMMFFF.MM..=..BBEE=.SSS....EE..
  19 .....FFF.W.MMFFF.MMww=W.BBEE=.SSSfW.fEE..
  20 =========================================
  21 .CC.PP.BB.MMWFFFBBSSS=HH.CC....CC.PP.f..f
  22 .CCfPPfBBfMM.FFFBBSSS=HH.CC....CCfPPf....
  23 ........f..........AA=UU........f..f..f..
```

**Sizing**, per 200 ticks at full morale. Eight Villager houses eat 8 water, 8 staple and 8 fuel, and three bakeries use 12 more water.

| Chain | Buildings | Makes | Needed |
| --- | --- | --- | --- |
| Bread | 3 farms → 3 mills → 3 bakeries | 17 wheat, 13 flour, 12 bread | 8 bread |
| Fuel | 3 woodcutters → 1 woodshed | 9 logs, 13 firewood | 8 firewood (4 logs) |
| Water | 4 wells | 32 | 20 |
| Services | chapel, 2 foresters | — | 30 s upkeep a payday |
| Settler food | 2 berry bushes | 10 berries | only until promotion |

Jobs are 34, plus 12 carriers, against 52 workers at Settlers and 84 at Villagers. Founding logs are topped up to cover construction, plus 60 spare logs. Storehouses are placed last, so construction uses free founding stock. The treasury still pays each building's working money, which leaves 1.17 g after building.

**First run, 15 October 2026** (30 minutes, seed 73, 15% tax, 10% markup, staple and fuel needs):
- **Tiers hold, but nobody is well off.** All eight houses are Villagers from minute 3. Happiness is 75–100% and morale 85–97%. Three or four houses at a time read "cannot afford staple food" or "cannot afford fuel".
- **Wages do not cover a Villager's basket.** A house earns 18–25 s a payday after tax. Bread at 18 s, firewood at 6 s and water at 3 s retail cost 27 s. Savings fall from 50 s to about 20 s. 38 of 84 workers are idle, and idle workers earn nothing.
- **Storehouses keep the money.** The purse cap is the cost of restocking every good the village makes to its limit of 30. For this village that is about 13.5 g for an empty store (the bread chain alone is 12 g; firewood adds 1.5 g), so no surplus reaches the treasury: trade income was 0 for all 30 minutes. The first storehouse sat on 5–6.5 g. The second spent its 1 g on wheat that no mill fetched and was at 0 s from minute 15. After that it cannot buy from the eastern well or woodcutter, which read "output full".
- **The treasury cannot pay services.** Tax brings 69 s a minute against 90 s of upkeep (chapel and two foresters). 5.24 g of public pay went unpaid, and frustration reached 85.
- **Stock is always empty.** Bread was out in 93% of samples and fuel in 94%. Goods move straight to pantries as they are made, and several producers sit full beside a broke storehouse.

## 6. Open questions

1. **What should happiness do?** Settled on 14 October 2026: it sets the demotion threshold and workplace speed (3.1). Not chosen: scaling the workers a house provides; faction problems will take that role.
2. **Should needs have weights?** At the moment water counts the same as logs, and a chapel the same as bread. Survival needs (water, staple food) might count for more than tier goods. Left until Tier 3 adds more needs.
3. **Labour priority.** Settled on 15 October 2026: low, normal and high per workplace and per storehouse's carriers (section 1).
4. **Pantry size by tier.** Six slots fit three goods at two cycles each. Service needs such as the chapel take no pantry space. Tier 3, with four or more goods, will need a larger pantry or a single cycle of stock.
5. **Treasury growth.** With one house, taxes add about 0.03 g a minute, and a new house costs 0.92 g. More houses widen the tax base. At the 15% default, two houses pay for one public service (5.5). Each service adds 10 s a payday per worker, so every new chapel or forester needs roughly one more Tier 2 house. A gold cost on later buildings may still be needed once Tier 3 exists.
