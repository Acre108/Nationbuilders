# Villagers: workforce, food, happiness and money

**Status:** sections 1–4 are implemented. Section 5 is the agreed next phase. Section 6 lists open design questions.

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

Money is closed. The treasury, the payroll and every building's silver always sum to the founding treasury of 10 gold, and the tests check this.

### Prices come from the chain

**Every link in a chain pays the one before it.**
- The mill pays for its wheat.
- The bakery pays for its flour and water.
- A house pays for its bread.
- A storehouse pays for what it collects, and is paid for what it hands out.

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
- **Tax** is withheld at payday into the treasury: 10% of wages by default (`set_tax_percent`). **Tax is the treasury's only income.**
- **Public workers.** Buildings that sell nothing, such as the forester, are paid by the treasury at each payday: 10 s per worker.

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
  - **Affordability.** Placement fails with "Treasury needs …" when the treasury can't cover it. The build card shows what the treasury pays.
- **Demolition** returns a building's silver to the treasury.

A house costs the treasury 92 s: 42 s of logs and a 50 s purse. A windmill costs 80 s.

### How it behaves

In a 30-minute run of the default village with its mill and bakery:
- The treasury starts at 10 g and falls to about 5.7 g after the starter village and chain are built.
- Taxes then add about 10 s every 3 minutes with one house.
- Construction spending flows from storehouses to producers and on to households as wages. Building is what creates jobs.
- Workshop purses sit near zero because their silver is held as stocked inputs. Each sale returns it.
- A village that stops building slowly moves its silver into the treasury through tax. The player then either builds, which puts it back into wages, or lowers the tax.

The inspector shows the money at each building:

| Building | Shown |
| --- | --- |
| House | Savings, last payday's wage and tax, and each need's price |
| Workshop | What it sells, for how much, how much of that is wages, and its purse |
| Forester | That the treasury pays it |
| Storehouse | Its trading purse, the treasury in gold, and the tax rate |

## 5. Next phase: treasury controls and storehouse trade

**Status:** agreed on 11 October 2026; work starts 12 October. Each item gives the decision, the proposed design, and the choices still open. The recommended option is listed first.

### 5.1 Tax control

**Decision.** The player sets the tax rate in the HUD.

**Proposed design**
- A **Treasury panel**, opened from a gold counter at the top of the screen. It shows:
  - the treasury in gold;
  - the tax rate, with − and + in steps of 5%, from 0 to 50%;
  - last payday's tax income and public pay;
  - the reserves (5.2).
- The sim already supports this through `set_tax_percent`. The work is mostly HUD, plus a short history of income and spending per payday to display.
- Each house inspector keeps showing its own wage and tax, so the effect of a change is visible where villagers feel it.

**Still open**
- The README says global resource counters are hidden. Is a gold counter the agreed exception, or should the panel open from the cog or a storehouse instead?
- Should tax affect happiness, for example above 30%? Happiness changes are deferred, so the proposal is no for now.

### 5.2 Reserved funds

**Decision.** The player can set treasury gold aside for public pay or for capital spending.

**Proposed design**
- The treasury becomes three pots: **free**, a **public pay reserve** and a **capital reserve**. All three still count toward the conserved money total.
- **Public pay** (the forester, and later services such as the chapel) draws from the public pay reserve first, then from free gold. It never touches the capital reserve.
- **Construction** (materials and working money) draws from the capital reserve first, then from free gold. It never touches the public pay reserve.
- **Moving gold.** The player moves gold between free and either reserve in the Treasury panel.
- **Allocation.** Optionally, a share of each payday's tax income is set aside automatically. For example, "put 20% of taxes into public pay".
- **Building costs.** "Treasury needs …" counts only the gold construction can use. The build card shows which pot pays.

**Still open**
- **Allocation:** manual transfers only to start, with automatic allocation added later (recommended), or both from the start?
- **Unpaid public workers:**
  - they keep working unpaid, as now (recommended for now);
  - they stop work, like stopped workers, until paid;
  - or they keep working and their unhappiness waits for the happiness decision.
- **A reserve target?** For example, "keep 2 paydays of public pay reserved" and top it up automatically.

### 5.3 Storehouse buy and sell prices

**Decision.** Storehouses buy and sell at different prices.

**Proposed design**
- A storehouse **buys at the chain price and sells at a markup**: `sell = price + max(1, price × markup%)`, rounded to whole silver. The default markup is 25%, so bread costs 20 s from a storehouse instead of 16 s. The minimum of 1 s keeps the margin on cheap goods such as water.
- **Direct delivery stays at chain price.** A house fed straight from the bakery or well pays 16 s or 2 s. Living near a producer becomes cheaper than buying from storage, which rewards good layout.
- `spendable()` and `settle()` use the seller's selling price instead of one price per good.

**Still open**
- **Who pays the markup?** Households only (retail, recommended), or workshops too?
  - Charging workshops breaks the chain arithmetic: the bakery would pay more for flour than its bread price recovers.
  - Workshops would then need a margin of their own, or prices would have to include the markup.
- **Where the margin goes:**
  - It stays in the storehouse's trading purse, and anything above a purse cap (such as 2× its starting capital) goes to the treasury at payday (recommended). The treasury then has a second, trade-based income on top of tax.
  - Straight to the treasury on every sale. This is effectively a sales tax.
  - It stays in the storehouse only. This keeps the storehouse able to buy, but gives the treasury nothing.
- **Should the player set the markup** next to the tax rate in the Treasury panel?

### 5.4 After these land

- **Re-run the 30-minute balance probe** with taxes, reserves and markup together. A markup raises households' cost of living, so wages may need to rise to compensate. Check that a Villager house still stays fully happy at the default settings.
- **Tests:**
  - tax control through real HUD input;
  - reserves protect public pay from construction, and the reverse;
  - storehouse sales carry the markup while direct sales don't;
  - money is still conserved across all pots and purses.

## 6. Open questions

1. **What should happiness do?** Deferred for now. Options:
   - scale the workers a house provides;
   - feed village morale;
   - set the promotion and demotion thresholds.
2. **Should needs have weights?** At the moment water counts the same as logs. Survival needs (water, staple food) might count for more than tier goods.
3. **Labour priority.** On/off is the first step. A per-building priority (high / normal / low) may be needed once villages have 20+ buildings.
4. **Pantry size by tier.** Six slots fit three goods at two cycles each. Tier 3, with four or more goods, will need a larger pantry or a single cycle of stock.
5. **Treasury growth.** With one house, taxes add about 0.03 g a minute, and a new house costs 0.92 g. More houses widen the tax base. Storehouse margins (5.3) will add a second income. A higher default tax, or a gold cost on later buildings, may still be needed once Tier 3 exists.
