# Factions: three classes, six factions

**Status:** design agreed on 15 October 2026 (section 13). Phase 1 is planned in [PLAN-factions.md](PLAN-factions.md). Nothing is implemented yet.

This document scopes a faction system for a fictional 18th century moving into an industrial revolution. It builds on the money model in [VILLAGERS.md](VILLAGERS.md) §4–5 and would replace the culture factions in [DESIGN.md](DESIGN.md).

| Class | Factions |
| --- | --- |
| Working class | **Trade unions** · **Populists** |
| Middle class | **Middle class** |
| Elite | **Industrialists** (new money and manufacture) · **Aristocrats** (nobles by blood and landed wealth) · **Cultural elite** (the educated and the press) |

The system has three jobs:

1. **Money is power.** Silver held by a faction's people and property strengthens it.
2. **Balance or back.** The factions want conflicting things. The player keeps them content or picks sides. This matters most in towns.
3. **Money comes back out.** Factions pay the treasury when the player does what they like. A union lobbies for a policy; a landlord buys houses.

**How it plays.** Early in a village nobody is organised. Houses that become Villagers earn wages and join the working class, but at first they belong to no faction. A union hall draws the households around it into the unions. An alehouse, unemployment or empty pantries draw them to the populists. Aristocrats and industrialists arrive with capital to buy houses and mills, and the middle class buys the storehouses as shops. A treasury short of gold can sell a house to a landlord: the gold arrives at once, the household pays rent, and the unions resent it. In a town all six factions are present. The cultural elite's press colours how every faction sees the Crown, and every lever helps some factions and costs others.

## 1. Setting and what this replaces

- Villages are the 1700s countryside: farms, mills, woodland and a squire. Towns are the new industry: workshops, manufactories, crowded housing, shops and printing presses, fed from the villages.
- **Replaced:** the culture → faction table in DESIGN.md (Clan Council, Merchant League, Church) and the demand table in [SUPPLY_CHAINS.md](SUPPLY_CHAINS.md) §8. Class factions exist in every settlement. There is no longer one pledged faction per culture.
- **Kept:** the charter result's `faction` field (`sim/world/run_result.gd`). It records the dominant faction at charter (§9).
- **Outside this scope:** DESIGN.md's "medieval to modern" pitch, art for towns (brick, chimneys) and renaming the medieval chains. The timber-frame village kit already suits an 18th-century countryside.

## 2. The factions

| Faction | Class | Their people | Their property | Income | Pays the player for |
| --- | --- | --- | --- | --- | --- |
| Trade unions (`union`) | Working | Working-class houses it wins (§3.1) | Union halls; co-operative workshops later | Dues: 5% of members' wages | Pledges; organising |
| Populists (`populist`) | Working | Working-class houses it wins (§3.1) | Alehouses | Penny dues: 2% of members' wages; gifts from elite patrons | Pledges; organising |
| Middle class (`middle`) | Middle | Tier 3 Townsfolk; town shopkeepers' and clerks' houses | Storehouses, which serve as shops; markets later | The owner's share of its shops' markup | Storehouses, pledges |
| Industrialists (`industry`) | Elite | Town manufacturers' townhouses | Workshops | The owner's share of their workshops' sales | Workshops, pledges |
| Aristocrats (`gentry`) | Elite | Town manors | Houses and fields | Rent; the owner's share from fields | Houses, fields, pledges |
| Cultural elite (`culture`) | Elite | Town scholars' houses | Printing presses, schools, theatres (town) | Press and theatre sales; patronage | Pledges, often paid in favourable press instead of silver |

**The two working-class factions are rivals for the same households.**
- **Unions** organise at work. They want wages, jobs and paid public workers, and they sympathise with reform.
- **Populists** organise in the street. They want cheap bread, order, tradition and festivals, and they distrust every elite, the press most of all.

Each faction is the other's counterweight. A player facing a strong union can grow the populists to contain it, and the reverse.

The main conflicts (the full picture is the stance table in §4):

- **Households: unions against populists** (§3.1).
- **Wages and jobs: unions against industrialists.** An owner's share of a sale is silver not paid in wages. Idle workers mean cheap labour for one side and unemployment for the other.
- **Rent: the working class against aristocrats.** Rent comes out of household savings.
- **Prices: the working class against the middle class.** Shopkeepers live on the markup.
- **Order: the middle class against strikes and riots,** whichever working-class faction causes them.
- **Land and bread: industrialists against aristocrats.** Woodcutters clear the gentry's hunting woods. In towns, a grain tariff makes bread dear for everyone except the landowners (§8).
- **Opinion: the cultural elite against populists and aristocrats.** The press mocks the crowd, the crowd distrusts the press, and the aristocrats want it licensed.

## 3. Power (job 1)

A village's money is fixed: it moves between holders, but the total never changes (VILLAGERS.md §4). Power is a faction's share of that total.

> power(f) = coffers(f) + savings of houses aligned with f + purses of workshops and storehouses f owns

- **Coffers** are a new money holder: each faction's own purse. Dues, rent and owners' shares collect there until the faction spends them.
- **Alignment** (who a house belongs to) depends on class:
  - **Settlers** have no class. They are subsistence households, too poor to organise.
  - **Working-class houses** (Villagers; town terraces) start unaligned. Unions and populists win them over, one house at a time (§3.1).
  - **Middle-class houses** (Tier 3 Townsfolk; town shopkeepers) belong to the middle class.
  - **Elite houses** in towns belong to their faction: townhouses to the industrialists, manors to the aristocrats, scholars' houses to the cultural elite.
- **A landlord does not own the household's savings.** A rented house's savings count for whoever the household is aligned with. The landlord gains only the rent.
- **The Crown is the player.** Crown power is the treasury plus the purses of Crown-owned workshops and storehouses.
- **The power bar** shows the Crown, the six factions and unaligned money as shares of the whole. Payroll waiting for payday is left out. The unaligned share is mostly working-class savings that no faction has won yet, so it shows what is left to win.

Power is zero-sum. Hoarding gold keeps the factions weak but starves households, and selling property moves power to the buyer.

| Share | Band | The faction can |
| --- | --- | --- |
| Below 5% | Weak | Make small offers only |
| 5–15% | Organised | Make offers and demands |
| 15–30% | Strong | Act on its favour (§6) |
| 30% or more | Dominant | Also apply its passive effect (§6) |

### 3.1 Winning the working class

> **Some working-class families are unaligned, and aligning them is part of the game.** A new Villager house belongs to no faction. Whether it joins the unions, joins the populists or stays its own depends on where it stands, how it lives and what the player does.

**Pull.** Each payday, every working-class house gets a pull score from each side:

| | Union pull | Populist pull |
| --- | --- | --- |
| Work | + the share of the village's workers employed · + wages paid in full last payday | + per idle worker |
| Living | | + per need unmet (happiness below 100%) · + markup above 10% |
| Places | + a union hall within its radius | + an alehouse within its radius |
| Neighbours | + per union house within 6 tiles | + per populist house within 6 tiles |
| Help | + union relief received (§7) | + a populist festival held (§7) |
| Backlash | − a strike cost the household its wages | − a riot hit the household's shop |

**Joining and leaving** work like promotion and demotion:
- An unaligned house joins a side once that side's pull leads by 3 or more for 5 paydays running.
- A member leaves only if the rival leads by 6 or more for 10 paydays.

This makes switching harder than joining, so houses do not flip back and forth. The neighbours term makes houses cluster: districts tend to become union streets or populist streets.

**The player's tools:**
- **Placement.** Union halls and alehouses have a radius, so the street plan decides who organises where.
- **Levers.** Employment, the markup and keeping pantries full each favour one side.
- **Organising offers.** A faction offers silver toward a union hall or alehouse at a spot it names (§5.3).
- **Leaving houses alone.** A house with no hall or alehouse nearby, a job and a full pantry may stay unaligned for a long time.

**Why align them, or not:**
- Aligned houses pay dues, and that money comes back to the treasury through lobbying.
- A friendly faction with members helps: union volunteers, or a loyal crowd that breaks a strike (§6).
- Unaligned houses make no demands and never strike or riot. However, they pay nothing either, and nobody organised stands with the Crown.
- A working class split between the two factions is the most stable arrangement. Each side holds the other back.

The inspector shows a house's alignment and both pulls: "Unaligned · union 7, populist 4 · joins the unions in 3 paydays". A **class overlay**, toggled like Deposits, colours houses by alignment and draws the radii of halls and alehouses.

When a house promotes to Tier 3 (Townsfolk), it becomes middle class and leaves its working-class faction (§13).

## 4. Favour (job 2)

Each faction has **favour** toward the player, from −100 to +100. It starts at 0. Power is how much a faction can do. Favour is whether it helps or hurts.

- Each payday, favour moves 5 points toward a **target**: the sum of the faction's column in the stance table, clamped to ±100.
- Events cause one-off jumps: an offer accepted or declined, a pledge kept or broken, a demand met or ignored.
- The Factions panel lists every term with its current value, so the player can always see why a faction feels the way it does.

**Stance table.** Each row reads a sim value or a lever. + raises the faction's target as the value rises, and − lowers it. ++ and −− count double.

| State or lever | Unions | Populists | Middle | Industry | Aristocrats | Cultural |
| --- | --- | --- | --- | --- | --- | --- |
| Tax on wages above 10% | − | − | | | | |
| Markup above 10% | − | −− | + | | | |
| Idle workers | − | − | | + | | |
| Public workers unpaid (last 6 paydays) | −− | | | | | |
| Average rent | − | − | | | + | |
| Houses sold to landlords (last 30 paydays) | − | | | | + | |
| Buildings it owns | | | + | + | + | + |
| Its households' average settled happiness (VILLAGERS.md) | + | + | + | + | + | + |
| Woodland lost since founding | | | | | − | |
| Strikes or riots under way | | − | −− | − | − | |
| Union power above 15% | | − | − | − | − | + |
| Populist power above 15% | − | | − | | | −− |
| *Town:* schools and libraries | | | + | | | ++ |
| *Town:* censorship | | + | − | | + | −− |
| *Town:* tax on profits | + | + | − | −− | − | |
| *Town:* wage floor | ++ | + | − | −− | | |
| *Town:* grain tariff | − | −− | − | − | ++ | |

The weight of one step for each row lives in `factions.json`. First-pass weights:

| Row | Weight of one step |
| --- | --- |
| Tax | 3 per point |
| Markup | 1 per point |
| Idle workers | 2 per worker |
| Unpaid public workers | 5 per worker |
| Rent | 1 per silver |
| Houses sold | 10 per house |
| Buildings owned | 5 per building |
| Happiness | 0.5 × (average − 50) |
| Woodland | 1 per point |
| Strikes and riots | 10 each |
| Power above 15% | 0.5 per point |

Most rows read values the sim already has: `tax_percent`, `markup_percent`, `idle_workers`, house `happiness`, the ledger's `unpaid` and the forestry tree count.

**The press.** Once the cultural elite is organised, its favour colours how everyone else sees the Crown.
- Press tone is the cultural elite's favour ÷ 10, from −10 to +10.
- It is added to every other faction's target, except the populists'. The populists distrust the press, so the tone is subtracted from their target.

**Pledges** are what lobbying buys (§5.2). While a pledge runs, the lever it covers is locked in the Treasury panel, with a padlock and the faction's name. The player can break the pledge from the panel: favour −40, and that faction makes no offers for 30 paydays. A pledge kept to the end gives +10.

**Demands** (phase 2) come from organised factions, with a deadline. Examples: "keep tax at or below 10% for 10 paydays", "pay the forester", "build a school". A demand pays nothing. Meeting it gives +15 favour; ignoring it gives −20.

**There is no formal backing** (decided 15 October 2026). A faction is pleased or displeased only by what the player does: the levers, offers accepted or declined, pledges, placement and property sold. To back a faction, the player plays its way, and its rivals notice.

## 5. Deals (job 3)

A deal moves silver from a faction's coffers to the treasury in return for something the faction wants.

### 5.1 Property sales

What changes hands follows the building's kind:

| Kind | The owner receives | Who may buy (`buyers` in `buildings.json`) |
| --- | --- | --- |
| House | Rent each payday from household savings: 5 s at Tier 1, 10 s at Tier 2 (about a fifth of a Tier 2 house's wage) | Aristocrats |
| Producer | The owner's share: 20% of the labour part of each sale. The price is unchanged, so wages fall | Fields: aristocrats. Mill, bakery, woodcutter: industrialists. *Town:* printing press, theatre: cultural elite |
| Storehouse | The owner's share: 20% of the markup on each household sale, which would otherwise pay carrier wages. Also any surplus above the purse cap, which rarely builds up | Middle class |

Wells and services (`"service": true` in `buildings.json`, such as the forester) are not for sale. Union halls and alehouses belong to their faction as soon as they are built.

- **Price** = book value × favour multiplier. The multiplier runs from 0.75 at −100 favour, through 1.0 at 0, to 1.5 at +100. A faction can pay only what its coffers hold.
  - A house's book value is 12 paydays of its rent: 120 s at Tier 2.
  - A workshop's or storehouse's book value is its construction price plus the silver in its purse. The purse goes with it.
- **Who starts a sale.** The player can choose "Offer for sale" in the inspector, which lists the bids. Factions also make offers on their own (§5.3).
- **Buy-back.** The Crown can buy property back at its current sale price. The owner loses 15 favour.
- **Demolition.** Demolishing a faction's building returns its purse to that faction's coffers rather than the treasury, and costs 15 favour.

A village's Crown houses pay no rent, so selling a house costs the treasury no income. The cost falls on others: the household pays rent, and the working class resents it. Selling a storehouse also costs the treasury little. Its owner's share comes out of carrier wages, which gives the working class one more reason to dislike a high markup.

### 5.2 Lobbying

A faction pays for a pledge that lasts a number of paydays.

| Faction | Example pledges |
| --- | --- |
| Unions | Tax at or below 10% · every public worker paid · no house sold to a landlord · no workplace stopped |
| Populists | Markup at or below 10% · no new union hall · *town:* no grain tariff · *town:* the press licensed |
| Middle class | Markup kept at its current level or higher · *town:* tax on profits held · *town:* a market built |
| Industrialists | No buy-backs · keep a named workshop staffed · *town:* no wage floor |
| Aristocrats | Woodland kept above its current level · no new workshop next to a rented house · *town:* a grain tariff |
| Cultural elite | *Town:* no censorship · a school or library built |

The first-pass value is 10 s per payday pledged, scaled by the faction's power band. A union that collects 5% dues effectively pays the treasury for keeping the tax low.

The cultural elite has little silver. It usually pays in **favourable press** instead: +5 press tone for 10 paydays.

### 5.3 Offers

- Each faction has at most one open offer. An offer expires after 3 paydays.
- A faction offers only what its coffers can pay.
- **Organising offers.** The unions or populists offer to pay toward a union hall or alehouse at a spot they name, near the unaligned houses they want.
- Offers come from the sim's seeded RNG in a stable order, so replays stay deterministic.

### 5.4 Loans (phase 3)

Industrialists, aristocrats or the middle class lend the treasury gold, repaid with interest over a number of paydays.

## 6. Actions (phase 2)

A strong faction acts according to its favour. A dominant one also applies its passive effect.

| Faction | Favour +25 or more | Favour −25 or less | Dominant passive |
| --- | --- | --- | --- |
| Unions | **Volunteers:** unpaid public workers gain no frustration | **Strike:** workers leave the workplaces of whoever they blame (industrialist workshops, or Crown buildings) for 3 paydays | Wage floor: the owner's share falls to 10% |
| Populists | **Loyal crowd:** ends a union strike early | **Bread riot:** a crowd takes food from a storehouse to member houses without paying. The shop's owner and the middle class lose favour | Price cap: markup at most 5% |
| Middle class | **Subscription:** pays part of a public building | **Shops shut:** their storehouses stop selling to households for 3 paydays | Civic order: strikes and riots last half as long |
| Industrialists | **Investment:** pay half of a new workshop's construction and take a share of it | **Capital flight:** their coffers leave the settlement, and their workshops stop buying inputs | The owner's share rises to 30% |
| Aristocrats | **Patronage:** an interest-free loan, or a gift of logs | **Rent rise:** rent +50%. Arrears lead to eviction, and the house drops a tier | Rent rises slowly over time |
| Cultural elite | **Good report:** broken pledges cost half the usual favour | **Pamphlets:** unaligned working-class houses gain +2 union pull | Press tone counts double |

- A strike reuses the stopped-workers rule (VILLAGERS.md §1). The building releases its workers and gets no inputs, and its status reads "on strike".
- A bread riot moves goods but no silver, so the money total is unaffected.

## 7. The money loop

Every holder needs a way for money to come in and a way for it to go out, or money pools. VILLAGERS.md §5.5 already shows households hoarding and the treasury collecting.

| Holder | Money in | Money out |
| --- | --- | --- |
| Union coffers | Dues: 5% of members' wages | Lobbying · organising · **relief**: above a cap, it pays member houses that cannot afford their basket · strike pay |
| Populist coffers | Penny dues: 2% of members' wages · patrons' gifts | Lobbying · organising · **festivals**: above a cap, it buys bread from storehouses for member houses |
| Middle-class coffers | The owner's share of its storehouses' markup | Buying property · lobbying · subscriptions · loans |
| Industrialist coffers | Owners' shares | Buying property · investment · lobbying · **patronage** of the populists |
| Aristocrat coffers | Rent; owners' shares from fields | Buying property · lobbying · patronage · above a cap, buying goods from storehouses for the manor |
| Cultural-elite coffers | Owners' shares from presses and theatres (town) | Buying presses and schools · above a cap, commissions bought from storehouses |
| Treasury | Tax, occasional storehouse surplus, **deals** | Construction, public pay, **buy-backs** |

**Elite patronage of the populists.** While union power is above 15%, aristocrats and industrialists give part of their coffers above the cap to the populists. They fund the counterweight. The Factions panel shows each gift, so the player can see who is paying for the crowd (still open, §13).

Links to VILLAGERS.md §5.6:

- **Recycling the margin** is settled there: the storehouse markup pays carriers' wages. Factions add a second path for hoarded savings. Rent and dues drain them; deals, relief and festivals return them.
- **When frustration decays.** Union favour reads unpaid workers over the last 6 paydays, so the effect fades. `public_frustration` stays as a lifetime record.
- It also gives a reason to let the player set the markup: the middle class wants it high and the working class wants it low.

**Conservation.** The treasury, the payroll, every building's silver and every faction's coffers always sum to the founding treasury plus the factions' endowments. Endowments are starting money that lets a faction make its first offer. Suggested amounts: aristocrats 2 g, industrialists 1 g, middle class 0.5 g, all others 0 s. Each endowment arrives with its faction (§13).

## 8. Villages and towns

| | Village | Town |
| --- | --- | --- |
| Factions present | Some, never all. Unions and populists arrive with the first Villager house. The site's biome decides which of the middle class, industrialists and aristocrats take an interest, from none to three (`factions` in `biomes.json`). A harsh site attracts fewer factions and so gets fewer offers | All six |
| Working class | Villager houses, contested (§3.1) | Terraces, contested |
| Other households | Tier 3 Townsfolk → middle class | Shopkeepers' houses, townhouses, manors and scholars' houses, each with its own needs basket |
| Property for sale | Houses, workshops, storehouses, fields | Also manufactories, building plots, printing presses and theatres |
| Recruiting buildings | Union hall, alehouse | Also co-operative workshops; taverns that sell ale |
| Levers | Tax on wages, markup | Also tax on profits, rent control, a wage floor, a grain tariff and censorship |
| Actions (§6) | None: villages are about offers and favour | All |
| Food | Grown locally | Mostly imported from villages, whose fields the aristocrats may own |

- **The cultural elite is a town faction.** A village has a parson and a schoolmaster, not a press.
- **Class households reuse the needs system.** A manor is a house with a luxury basket (wine, fine cloth), and its happiness is an aristocrat stance term. Keeping a faction content partly means supplying its households. In towns, newspapers could become a good in middle-class and elite baskets, sold by the cultural elite's presses.
- **Grain tariff.** Imported grain pays a tariff into the treasury. Aristocrats like it because their village fields sell dearer. Everyone else dislikes dear bread, the populists most of all. This is the 18th-century Corn Law as one lever.
- **Censorship.** Licensing the press quiets the cultural elite's pamphlets but turns its favour sharply negative. Populists and aristocrats approve.
- **Towns do not exist yet.** Everything in the town column waits for the town phase. Villages can test the money model and the contest for the working class first.

## 9. Nation layer

- At charter, `run_result.faction` records the dominant faction, and the settlement's power shares add to the nation's totals.
- National power drives faction demands each nation turn (DESIGN.md core loop) and the banner colour on the world map ([PLAN-world-map.md](PLAN-world-map.md) §8).
- A faction's national strength sets its endowment in the next settlement. A strong aristocracy brings more capital to a new town.

## 10. Sim and data changes

| Area | Change |
| --- | --- |
| `data/factions.json` (new) | For each faction: id, name, class, colour, whether it recruits, the settlement types it appears in, endowment, dues, owner's share and rent rates, coffer cap, stance weights, rivals and pledge types |
| `data/tiers.json` | `class` per tier: `""` for Settlers, `working` for Villagers, `middle` for Townsfolk |
| `data/buildings.json` | `buyers`: the factions that may buy this building. `recruits_for` and `radius` for halls and alehouses. New rows: `union_hall`, `alehouse` (placeholder meshes at first) |
| `sim/content_db.gd` | Validate the above and cross-reference the ids |
| `sim/factions.gd` (new) | Power, favour drift, the stance table, press tone, recruitment, offers, pledges and actions. A plain `RefCounted`, like `economy.gd` |
| `sim/economy.gd` | `settle()`: the owner's share goes to its coffers. For a producer it comes from the labour part. For a storehouse it comes from the `work` value (markup = cost − chain price), split off before that value reaches the payroll as carrier wages. `payday()`: the rare storehouse surplus follows the owner, then dues and rent are collected, then `factions.payday()` runs. New ledger keys `deals` and `buybacks` |
| `sim/needs.gd` | No change. The happiness stance term and populist pull read `Needs.settled(house)` (−1 before the first full cycle counts as no data), and village morale comes from `morale(sim)` |
| `sim/building.gd` | `owner` (`""` = Crown), `aligned`, a pull streak for each recruiting faction, `arrears`, `strike_until`; add them to the snapshot |
| `sim/village_sim.gd` | `factions` state. Commands: `sell_building(uid, faction)`, `buy_back(uid)`, `accept_offer(id)`, `decline_offer(id)`, `break_pledge(id)`. `set_tax_percent` and `set_markup_percent` refuse changes a pledge locks, and `last_error` names the pledge |
| Saves | New snapshot keys. Campaign version 3. Version-2 saves load with Crown owners, unaligned houses, empty coffers and neutral favour |
| `view/overlays/village_hud.gd` | Faction chips beside the gold counter (power % and a favour face), shown once a faction is organised. A Factions panel: power bar, stance terms, press tone, patron gifts, pledges and offers. Padlocks on pledged levers. In the inspector: the owner, a house's alignment and pulls, "Offer for sale" and "Buy back". The class overlay |

## 11. Tests

`tests/test_sim.gd` (new `_factions`):

- Money is conserved with coffers through sales, rent, dues, owners' shares, patron gifts, relief, festivals, buy-backs and demolition.
- Rent, dues and owners' shares go to the right coffers at the right rates.
- **Recruitment:**
  - A house joins after its lead holds for the set number of paydays.
  - Leaving takes the larger lead for longer.
  - Settlers are never recruited.
  - Halls and alehouses count only within their radius.
  - Promotion to Townsfolk moves a house to the middle class.
- A pledged lever refuses changes. Breaking a pledge applies its penalty.
- Favour moves toward its target by the step. Each stance term reads the right state, and press tone is inverted for the populists.
- Offers and recruitment are the same across tick batch sizes.
- Snapshots round-trip and reject bad input: an unknown owner or alignment, negative coffers, favour out of range.
- Phase 2:
  - A strike releases its workers and ends on time.
  - A bread riot moves goods but no silver.

`tests/test_campaign.gd`: version-2 saves still load. `tests/run_view_tests.gd`: the panel, accepting and declining offers, the sale button and the class overlay, all through real input.

Soak targets (`tools/soak_village.gd`, 60 minutes, seed 73, default settings):

- With no union hall or alehouse, at least half of the Villager houses are still unaligned at minute 30.
- With a union hall serving half the houses and an alehouse serving the other half, both factions still hold members at minute 60.
- With no deals, every faction ends between −30 and +30 favour.
- Selling every house to landlords takes the unions below −25 within 15 minutes, and Tier 2 still holds.
- With 3 or more union houses, accepting every union offer returns at least 1 g to the treasury per 20 minutes.

## 12. Phases

1. **Ledger, landlords and the working class (villages, now).**
   - Data: `factions.json` with all six factions (the cultural elite stays dormant in villages), coffers, power bar, favour from the stance table.
   - The contest for the working class: pull, joining and leaving, the union hall and alehouse, and the class overlay.
   - Deals: house sales and rent, workshop and storehouse sales with owners' shares, union and populist pledges, and organising offers.
   - The Factions panel, saves, tests and the soak.

   This tests the money model and the recruitment contest before towns exist.
2. **Pressure.** Power bands, actions and dominant passives, demands, buy-back, patronage of the populists, arrears and eviction.

Phase 1 is broken into work items in [PLAN-factions.md](PLAN-factions.md).
3. **Towns.** Needs the town phase:
   - class housing and baskets;
   - the cultural elite, its presses and the press tone;
   - censorship, tax on profits, the wage floor, rent control and the grain tariff;
   - loans and manufactories.
4. **Nation.** The charter faction, national power, demands each nation turn, banner colours and endowments from national strength.

## 13. Decisions

**Decided 15 October 2026:**

1. **The culture factions are replaced.** Clan Council, Merchant League and the Church go. Cultures may survive as regional flavour, but they no longer decide factions.
2. **Alignment comes from house type.** The class follows the tier or house type: Settlers have none, Villagers are working class, Townsfolk are middle class, and town house types name their faction. Within the working class, a house's faction is still won by the unions or populists (§3.1).
3. **Villages are about offers.** They have no actions (strikes, riots, rent rises). Not every faction is present: the site decides (§8).
4. **Factions bring outside money.** Each brings an endowment when it arrives, and the money total grows by that amount.
5. **No formal backing.** Factions are pleased or displeased by the player's choices; there is no endorsement.

**Assumed for phase 1, open to change:**

- Pledges lock the levers they cover.
- Promotion to Townsfolk makes a household middle class. This does not matter until Tier 3 exists.

**Still open (later phases):**

- Is the press tone too indirect (town)?
- Should elites fund the populists (phase 2)?
- Should towns have a ban on unions, modelled on the Combination Acts?
