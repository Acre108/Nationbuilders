# Villagers: workforce, food, happiness and money

**Status:** sections 1–5 are implemented. Section 5 (treasury controls and storehouse trade) landed on 14 October 2026; section 5.5 records its balance results. Section 6 lists open design questions.

Villagers are still counted per house, as in [DESIGN.md](DESIGN.md). Individual citizens are not simulated. This document covers how houses supply workers, how they get fed, how satisfied they are, and how they earn and spend money.

## 1. Workforce

- The village has one pool of workers: 4 founding adults plus each house's `workers_per_house` for its tier (`tiers.json`).
- Buildings are staffed in placement order. A building is staffed only when the whole crew it needs (`workers` in `buildings.json`) is free.
- **The player can stop any building that employs workers** (`set_workers_enabled(uid, false)`, or **Stop workers** in the inspector). A stopped building:
  - releases its workers to the next buildings in order;
  - shows the status "workers stopped";
  - receives no input deliveries, although carriers still collect any finished output.
- The village's idle workers are reported each tick as `idle_workers`. The inspector shows them next to each building's crew.

This lets the player direct labour when there is not enough of it. For example, stop the woodcutter to staff the bakery.

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
- Tier rules are unchanged:
  - A house with all of its needs met (100%) counts toward promotion.
  - A house with any need unmet counts toward demotion after `downgrade_after_ticks`.
- Shelter is not counted, since every house has it. Services such as the chapel will count as needs once they exist.

Happiness has no mechanical effect yet. It is shown in the inspector and recorded in the snapshot. What it should affect is open question 1 in section 6.

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
- A storehouse pays for what it collects, and is paid for what it hands out. Households also pay it a markup (5.3).

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
| Berries | nobody | – | – | **2 s** (base `price` in `goods.json`) |

Prices are worked out from `buildings.json` when the sim starts. A good that no building makes needs a `price` in `goods.json`, and content validation enforces this.

### Wages and taxes

- **Wages are paid per sale.** When a producer sells, it keeps the input part of the price to buy its next inputs. It passes the labour part to the **payroll**.
  - A workshop's purse therefore stays level, and a half-idle bakery never goes broke.
  - Wages follow what the village actually sells. Goods nobody buys earn no one anything.
- **Payday** (every 20 s) shares the payroll between houses by the workers each provides. Spare silver rotates between houses.
- **Tax** is withheld at payday into the treasury: 10% of wages by default, set in the Treasury panel (5.1). Tax and storehouse surpluses (5.3) are the treasury's income.
- **Public workers.** Buildings that sell nothing, such as the forester, are paid by the treasury at each payday: 10 s per worker, from the public pay reserve first (5.2). Unpaid public workers keep working, and their frustration grows.

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
| Forester | That the treasury pays it, what it was paid last payday, and its frustration |
| Storehouse | Its trading purse and purse cap, its markup, the treasury in gold, and the tax rate |

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
  - the storehouse markup (5.3), shown but not yet adjustable;
  - **last payday**: tax, storehouse surplus, demolition refunds, public pay and construction, plus any public wages left unpaid;
  - **net per payday** for the last 6 paydays, newest first;
  - construction spent since the last payday;
  - public workers' frustration.
- The panel closes with ×, Escape, or by opening options, weather or the build menu.
- Tax does not affect happiness. Happiness changes are still deferred.
- The sim keeps a ledger: `period` accumulates since the last payday, and `ledger` holds the last `LEDGER_PAYDAYS` (6) closed paydays.

### 5.2 Reserves and public pay

- The treasury has three parts: **free gold**, a **public pay reserve** and a **capital reserve**. The reserves are parts of `treasury`, not extra money, so the money total is unchanged.
- The player moves gold by hand: `transfer_reserve("public" | "capital", amount)`. A positive amount moves free gold into the reserve and a negative one moves it back. It moves at most what is there, and fails only if nothing moves.
- **Public pay** (the forester, and later services) draws on the public pay reserve first, then free gold. It never touches the capital reserve.
- **Construction** (materials and working money) draws on the capital reserve first, then free gold. It never touches the public pay reserve.
  - Placement fails with "Treasury needs … outside the public pay reserve" when only reserved gold would cover it.
  - The build card's "have" figure counts only gold construction can use.
- **Unpaid public workers keep working.** Each worker left unpaid at a payday adds 1 to:
  - the building's `frustration`, shown in its inspector;
  - the village's `public_frustration`, shown in the Treasury panel. This village-wide count survives demolition. A faction system will later read it as trade union contentedness.
- A partly paid crew counts each worker whose wage was not covered. Frustration does not decay yet. When it should is a faction-system question.
- Not built yet: automatic allocation of tax income to reserves, and reserve targets ("keep 2 paydays of public pay").

### 5.3 Storehouse markup and purse cap

- **Storehouses sell to households at a markup:** `retail = price + max(1, round(price × markup%))`. The default markup is **10%**.
  - Bread costs 18 s from a storehouse and 16 s straight from the bakery.
  - Water costs 3 s from a storehouse and 2 s from a well. The 1 s minimum keeps a margin on cheap goods.
  - A markup of 0% removes the minimum too.
- **Everything else stays at chain price:** direct deliveries from producers, every workshop purchase, storehouses buying from producers or each other, pantry buy-backs, and the treasury buying construction logs. So the chain arithmetic is unchanged.
- `spendable()` and `settle()` use `sale_price(buyer, seller, good)`, so a carrier is sent only when the household can pay that seller's price. A house's status reads "cannot afford …" when its silver is below the storehouse price.
- **Purse cap.** The margin stays in the storehouse's trading purse. At payday, silver above the purse cap goes to the treasury as **storehouse surplus**. The cap is the larger of:
  - 2 g (`PURSE_CAP`, twice a storehouse's starting capital);
  - the silver needed to restock, up to the per-good `good_limit`, every good the village currently makes.

  A storehouse with empty shelves therefore keeps construction money and spends it on producers' output. A full storehouse passes its surplus to the treasury.
- The markup can be changed in the sim (`set_markup_percent`, 0–100%), but not yet from the HUD.

### 5.4 Saves

New sim snapshot keys: `public_reserve`, `capital_reserve`, `markup_percent`, `public_frustration`, `period` and `ledger`. Buildings gain `frustration`. Snapshots with reserves larger than the treasury, or with malformed ledger entries, are rejected. Version-one campaign saves load with these fields at their defaults.

### 5.5 Balance results

Hour-long headless soaks, seed 73 (`tools/soak_village.gd`, with the storehouse `good_limit` of 30):

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

**Tests.** `tests/test_sim.gd` (`_treasury` and `_money`) covers:
- tax limits;
- reserve transfers, and that construction and public pay each leave the other's reserve alone;
- frustration from unpaid public workers, who keep working;
- the markup only on household purchases from storehouses;
- the purse-cap sweep and ledger;
- snapshot round-trip and rejection;
- money conserved with reserves inside the treasury.

`tests/run_view_tests.gd` (`_check_treasury`) drives the gold counter, tax buttons and reserve buttons through real input. `tests/test_campaign.gd` checks that version-one saves without these fields still load.

### 5.6 Still open

- **Should the player set the markup** next to the tax rate? It is shown read-only for now.
- **Recycling the margin.** A storehouse's margin reaches households only through the treasury, when the player builds or pays public workers. If the player does neither, even the 10% default leaves households broke after about 90 minutes. Options:
  - pay carriers from the margin, as storehouse labour into the payroll;
  - automatic treasury spending, such as upkeep or services;
  - leave it to the player.
- **Automatic allocation and reserve targets** (5.2).
- **When frustration decays**, and what the trade union does with it.

## 6. Open questions

1. **What should happiness do?** Deferred for now. Options:
   - scale the workers a house provides;
   - feed village morale;
   - set the promotion and demotion thresholds.
2. **Should needs have weights?** At the moment water counts the same as logs. Survival needs (water, staple food) might count for more than tier goods.
3. **Labour priority.** On/off is the first step. A per-building priority (high / normal / low) may be needed once villages have 20+ buildings.
4. **Pantry size by tier.** Six slots fit three goods at two cycles each. Tier 3, with four or more goods, will need a larger pantry or a single cycle of stock.
5. **Treasury growth.** With one house, taxes add about 0.03 g a minute, and a new house costs 0.92 g. More houses widen the tax base. Storehouse surpluses (5.3) now add a second income; see 5.5 for how the two balance against public pay. A higher default tax, or a gold cost on later buildings, may still be needed once Tier 3 exists.
