# Plan: introducing factions (phase 1, villages)

> **Goal:** factions in villages, as agreed in [FACTIONS.md](FACTIONS.md) §13. Factions gain power from their people's and property's silver. They are pleased or displeased by the player's choices. They pay the treasury through offers. Working-class houses are won by the unions or the populists.

## Decisions this plan follows (15 Oct 2026)

| Decision | What it means for this plan |
| --- | --- |
| The culture factions are replaced | Item 0 rewrites DESIGN.md and SUPPLY_CHAINS.md §8 |
| Alignment comes from house type | Each tier has a `class` in `tiers.json`. Settlers have no class; Villagers are working class, and the unions and populists compete for each house (FACTIONS.md §3.1). Townsfolk will be middle class, once Tier 3 exists |
| Villages are about offers, and not every faction is present | No strikes, riots or rent rises. Unions and populists arrive with the first Villager house. The biome decides which of the middle class, industrialists and aristocrats are interested, from none to three. The cultural elite never appears in a village |
| Factions bring outside money | Each faction brings its endowment when it arrives. The sim records it in `outside_money`, and the money total becomes `FOUNDING_TREASURY + outside_money` |
| No formal backing | Favour comes only from the stance table and from events. There is no endorsement command or UI |

Assumed, and easy to change: pledges lock the levers they cover.

## Where we are (15 Oct 2026)

- **Money** ([VILLAGERS.md](VILLAGERS.md)):
  - Silver moves between holders, and the total never changes.
  - The storehouse markup pays the carriers' wages.
  - Services (`"service": true`, the forester) are paid by the treasury.
  - Tax and markup are set in the sim (`set_tax_percent`, `set_markup_percent`). The Treasury panel has buttons for both.
- **Settled happiness and village morale** are done (`Needs.settled(house)`, −1 before the first full cycle; `Needs.morale(sim)`). Items 0–6 and 9 are built (15 Oct). Item 7, the HUD, is built too. Item 8, the balance soak, is next.
- **Saves:** new snapshot keys are listed in `LEGACY_ADDED` in `sim/campaign.gd`, so older saves load with defaults and there is no version bump.
- **Building kinds:** `content_db.gd` accepts `producer`, `house`, `storehouse`, `road` and `hall` (union halls and alehouses).

## Not in this plan

- Faction actions and demands.
- Arrears, eviction and buy-back.
- Patronage of the populists.
- Towns and the cultural elite's press.
- Loans.
- The nation layer.

These are FACTIONS.md phases 2–4.

## Work items (in order)

Each item ends with the headless suite passing (`tools/run_tests.ps1`), and with the view suite passing for item 7.

### 0. Documents
- [x] DESIGN.md: replace the "Cultures and factions" table with a short summary of the six class factions, linking to FACTIONS.md. Update the charter line ("pledges to its culture's faction") and the nation-turn wording.
- [x] SUPPLY_CHAINS.md §8: replace the culture demand table with a note that faction demands come from FACTIONS.md. The export values stay.
- [x] PLAN-world-map.md: note that banner colours will use the dominant faction.

### 1. Faction data, presence and coffers (headless)
- [x] `data/factions.json`: six rows. Each row has `id`, `name`, `class`, `colour`, `recruits` (unions and populists), `endowment` (gentry 200 s, industry 100 s, middle 50 s, all others 0 s), `dues_percent` (union 5, populist 2), `owner_share_percent` (20), `rent` by tier (5 s, 10 s), `coffer_cap`, `stance` weights (FACTIONS.md §4, village rows only) and `pledges`.
- [x] `data/tiers.json`: add `class` (`""` for Settlers, `"working"` for Villagers).
- [x] `data/biomes.json`: add `factions`, the interested middle and elite factions per biome:

  | Biome | Interested factions |
  | --- | --- |
  | Heartland | gentry, middle |
  | Riverland | middle, industry |
  | Coast | middle |
  | Highland hills | gentry, industry |
  | Mountain pass | industry |
  | Marsh | none |
  | Tundra | none |

  The default First Bread site uses heartland's list.
- [x] `sim/content_db.gd` and `sim/world/world_data.gd`: validate the new fields and cross-reference the ids.
- [x] `sim/factions.gd` (new, a plain `RefCounted` like `economy.gd`):
  - The roster of present factions.
  - Arrival. The site's interested factions arrive at founding. The unions and populists arrive when the first house reaches a working-class tier.
  - Each faction's coffers. An arriving faction adds its endowment to its coffers and to `outside_money`, and a `FACTION_ARRIVED` event names it.
- [x] `sim/village_sim.gd`: hold the factions state, call `factions.payday()` from the economy's payday, and add the factions to `snapshot()`.
- [x] Tests (`tests/test_factions.gd`, registered in `tests/run_tests.gd`):
  - Arrival happens on its trigger, with the right endowment.
  - Marsh gets no middle or elite factions.
  - A village with no factions at all still runs.
  - **The money invariant:** the treasury, the payroll, every building's silver and every faction's coffers always sum to `FOUNDING_TREASURY + outside_money`.

### 2. Ownership and income
- [x] `sim/building.gd`: `owner` (`""` = Crown) and `aligned` (`""` or a faction id), in the snapshot.
- [x] `sim/economy.gd`:
  - **Owner's share in `settle()`.** For a faction-owned producer, `owner_share_percent` of the labour part goes to its owner's coffers instead of the payroll. For a faction-owned storehouse, the same share of the markup goes to the owner instead of the carriers' wages.
  - **At payday:**
    - A faction-owned storehouse's surplus goes to its owner.
    - Rent moves from a faction-owned house to the owner, up to the household's silver. Unpaid rent is not tracked in this phase.
    - Dues are taken from aligned houses' wages after tax.
  - **Coffers above the cap** are spent back into circulation. The unions and populists give relief to their member houses that cannot afford their basket. The other factions buy goods from the nearest storehouse at the chain price, and the goods leave the village as consumption. The unions' relief alone can be built first if the others need more design.
- [x] `sim/village_sim.gd`:
  - `sell_building(uid, faction)` pays book value × the favour multiplier (FACTIONS.md §5.1) from the faction's coffers into the treasury and sets `owner`. It fails, with `last_error`, if the faction is absent, the building is not in the faction's `buyers`, the coffers are short, or the building is a service or a well.
  - Demolishing a faction-owned building returns its purse to the owner's coffers.
- [x] `data/buildings.json`: add `buyers`. House: gentry. Farm: gentry. Mill, bakery and woodcutter: industry. Storehouse: middle.
- [x] Ledger keys: `deals`, and `rent`, `dues` and `owner_share` for the panel.
- [x] Tests: each income stream goes to the right coffers at the right rate; a sale moves silver and ownership; refusals; demolition; the money invariant through every path.

### 3. The contest for the working class
- [x] New building kind `hall`: no workers, inputs or outputs, with a `radius` and a `recruits_for` faction. Content validation accepts it, and the generic placeholder mesh draws it.
- [x] `data/buildings.json`: `union_hall` (recruits for the unions) and `alehouse` (recruits for the populists). Both unlock at Tier 2, have a radius of 8 and cost logs like a house. A hall belongs to its faction from the moment it is built.
- [x] `sim/factions.gd`: union and populist pull per working-class house each payday, from FACTIONS.md §3.1:
  - Union: employment share, wages paid in full, a union hall in radius, union neighbours within 6 tiles, relief received.
  - Populist: idle workers, needs unmet (from `Needs.settled`), markup above 10%, an alehouse in radius, populist neighbours.
- [x] Joining and leaving:
  - A house joins after a lead of 3 or more holds for 5 paydays, and leaves after a rival leads by 6 or more for 10 paydays. Streaks are stored on the building.
  - Only present factions pull.
  - A house that drops to Settlers loses its alignment.
- [x] Tests: joining and leaving thresholds; radius limits; neighbour clustering; Settlers are never recruited; demotion clears alignment; the same result across tick batch sizes.

### 4. Power and favour
- [x] Power per faction and the Crown, plus the unaligned share (FACTIONS.md §3). It is derived, so it is not saved.
- [x] Favour from −100 to +100. Each payday it moves 5 toward its target, computed from the village rows of the stance table. Each term is kept with its value for the panel.
- [x] Event jumps: offer accepted or declined, pledge kept or broken, house sold to a landlord, building demolished.
- [x] Tests: each stance term reads the right state; the drift step and clamp; absent factions have no favour.

### 5. Offers and pledges
- [x] Offers in `sim/factions.gd`:
  - Every 5 paydays, staggered by faction, each present faction with no open offer may make one. The choice comes from the sim's seeded RNG in a stable order.
  - Offer types:
    - a **bid** for a Crown building the faction may buy;
    - a **pledge**: silver now for a lever kept for N paydays;
    - an **organising offer** (unions and populists): silver toward a hall placed within 8 tiles of a named house, paid on placement.
  - An offer expires after 3 paydays. Its value is capped by the faction's coffers.
- [x] Commands: `accept_offer(id)`, `decline_offer(id)` and `break_pledge(id)`.
- [x] Pledges:
  - `set_tax_percent` and `set_markup_percent` refuse a change the pledge forbids, with `last_error` naming the pledge.
  - A pledge kept to its end gives +10 favour. Breaking one costs −40 and blocks that faction's offers for 30 paydays.
  - Village pledges cover the tax cap, the markup cap or floor, no house sold to a landlord, no workplace stopped, and woodland kept.
- [x] Tests: determinism; expiry; coffers caps; each pledge's lock and penalty; accepting a bid equals `sell_building`.

**Choices made building items 4 and 5 (15 Oct), all constants in `sim/factions.gd`, open to the soak:**
- **Stance terms.** Tax and markup count points above 10%. Unpaid public workers count the average per payday over the ledger. Rent is the average per house, with Crown houses paying none. Happiness is a faction's aligned houses only, so the middle class, industry and gentry have no happiness term in a village. Woodland lost is the percent of the trees present when the faction arrived.
- **Event jumps.** Offer accepted +10, declined −5. Pledge kept +10, broken −40. Any sale: buyer +5. A house sold to a landlord: unions −5. Demolishing a faction's building: owner −15. An offer that lapses moves nothing.
- **Favour and price.** The sale multiplier is linear on each side of 0: 75% at −100 and 150% at +100.
- **Offers.** An offer's id is its faction's id. The choice uses an RNG seeded by the site seed, the tick and the faction, not the sim's RNG, so the rest of the sim is unchanged. A faction with under 10 s makes none.
- **Pledge value.** 10 s per payday for 10 paydays, × 50/100/150/200% by power band, capped by coffers.
- **Accepting a pledge applies its lever.** A tax or markup cap lowers the lever to 10%, and "no workplace stopped" restarts stopped workplaces. A markup floor or woodland pledge records today's level. A woodland pledge cannot lock anything, so a payday that finds fewer trees breaks it, with the usual penalty.
- **Organising offers** are accepted by placing the hall within 8 tiles of the named house. Its silver goes to the treasury as a deal. `accept_offer` refuses them, saying where to place the hall.
- **Not offered in villages yet:** public_workers_paid, no_new_union_hall, no_buy_backs, workshop_staffed and no_workshop_near_rented. Industry therefore only bids.
- **Saves.** Everything new sits in each faction's snapshot entry (favour, offer, pledges, blocked_until, sales, trees). The sim's top-level keys are unchanged. An entry with only the first three keys (coffers and flows) loads neutral, with no deals.

### 6. Saves
- [x] Add every new sim and building key to `snapshot()`, `from_snapshot` validation and `LEGACY_ADDED`.
- [x] Reject an unknown faction or owner, negative coffers, favour out of range, and offers or pledges that refer to missing buildings.
- [x] Tests: round-trip mid-pledge and mid-streak; older saves load with no factions present until their triggers; a malformed state is rejected.
- [ ] Legacy loads (item 1 note): a version-one save is founded again on load, so the site's factions arrive with their endowments, but the save's own events replace the founding "arrived" events. Working-class factions arrive one tick after load, and their arrival events carry the load tick. Decide whether migration should announce them.

### 7. HUD
- [x] **Faction chips** next to the gold counter: one per present faction, with its colour, power % and a favour face. They appear when the faction arrives.
- [x] **Factions panel**, opened from a chip and closed like the Treasury panel:
  - the power bar: Crown, factions and unaligned;
  - each faction's favour with its stance terms;
  - coffers;
  - open offers as cards with Accept and Decline;
  - running pledges with "Break pledge".
- [x] **Treasury panel:** a padlock and the faction's name on a pledged lever (tax and markup).
- [x] **Inspector:**
  - the owner;
  - for a house, its class, alignment and both pulls, with "joins in N paydays";
  - "Offer for sale", listing bids from present buyers.
- [x] **Class overlay**, a key and an options toggle like Deposits: houses coloured by alignment, hall and alehouse radii.
- [x] `tests/run_view_tests.gd`: chips appear on arrival; the panel opens and closes; Accept and Decline work through real input; the sale button; a padlocked lever refuses changes; the overlay toggles.

**As built (15 Oct):** chips sit under the gold counter: a face in the faction's colour (smiling from +25, frowning at −25) and its power share, with name, band and favour in the tooltip. Any chip opens the Factions panel, which lists offers and pledges first, then the power bar, then each faction's favour, the target it is heading for, the stance terms behind it, its coffers and last payday's flows. An organising offer's Accept is disabled, reading "Place the hall to accept". The Treasury ledger gains a "Faction deals" line. The class overlay is an options toggle and F5. It colours working-class houses (grey while unaligned) with a ground plate and a marker above the roof, and tints the road tiles within each hall's reach, the same road distance its pull uses. A key sits bottom left. The view suite saves `artifacts/factions-panel.png`, `treasury-pledged.png` and `class-overlay.png`.

### 8. Balance soak

**Known from item 2's hour-long test (15 Oct):**
- **Coffers are a money sink.** The cap is 400 s, and no faction reached it in an hour (gentry 282 s), so nothing flowed back. Try caps of 50–100 s, or spend a share of all income each payday. Item 5's offers are the other main outflow.
- **A village with a sold house, mill and storehouse stalls by about minute 10.** Wages reach 0 and rent goes unpaid on 157 of 180 paydays.
- **The same village with no sales also stalls, by about minute 30.** nation-builder-e1 traced this to the test village, not a bug:
  - With no services, the treasury can spend money only on construction, so tax drains households.
  - Without a forester, logs run out by minutes 3–20.
  - Without a chapel, Villager houses top out at 75% happiness.
- **Soak baseline.** Use the playtest/logistics layout instead: starter, chain, forester (placed away from the centre), chapel and two houses. Each 10 s/payday of service upkeep needs about one more Tier 2 house at 15% tax to balance.
- **The middle class can never buy a storehouse.** Its 50 s endowment is far below the book value (about 200 s), and a storehouse is its only income. Raise the endowment, or lower storehouse book value.

- [ ] Extend `tools/soak_village.gd` with faction columns: coffers, favour, members and offers.
- [ ] Run 60 minutes on seed 73 and on a marsh seed. Targets, from FACTIONS.md §11:
  - With no hall or alehouse, at least half of the Villager houses are unaligned at minute 30.
  - With a hall and an alehouse each serving half the houses, both factions hold members at minute 60.
  - With no deals, every faction ends between −30 and +30 favour.
  - Selling every house takes the unions below −25 within 15 minutes, and Tier 2 still holds.
  - Accepting every union offer returns at least 1 g per 20 minutes with 3 or more union houses.
- [ ] Record the results in FACTIONS.md as §14, tune the weights in `factions.json`, and update README.md (play notes, public sim API).

### 9. World map (small)
- [x] The hex panel lists the factions a site would interest, so where the player settles decides who comes.

## Coordination

- **Order.** Item 0 can run at any time. Items 1–6 change the same sim files, so they run one at a time, in order, and only after nation-builder-e1 has finished with them. Item 7 follows item 6, and item 8 follows item 7. Item 9 can follow item 1.
- **One writer per file at a time.** Agents announce the files they are editing before starting, and any other session working in the tree is told.
- **Commits.** Commits happen only when the user asks. Each item is left with its tests passing so it can be committed on its own.

## Risks

- **HUD clutter.** The gold counter is the one global counter. Chips appear only for present factions, and harsh sites have fewer.
- **Offer pacing.** Too many offers become noise, and too few leave villages flat. The soak decides the period.
- **Money pooling in coffers.** Spending above the cap must work from the start, or factions become a drain like the early treasury.
- **Pull tuning.** If houses all align within minutes, the contest is not a game. The soak target protects this.
