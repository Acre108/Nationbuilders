# Plan: classes for jobs, families and the first middle-class jobs

> **Goal:** jobs belong to a class, house types decide a household's class, money is earned and kept by families, and a village gets its first middle-class jobs, so the middle class has members, an income and a reason to lobby (FACTIONS.md §13, "Still open").

**Status:** scoped and decided 15 October 2026. House types go to nation-builder-ea (the buildings and tech-tree session); everything else is nation-builder-8e's. See "Who does what".

**Built so far (15 Oct, nation-builder-8e):** `sim/labour.gd` (job classes, staffing by class and family, wages credited to the families who worked); the storekeeper (30% of the markup; the storehouse row has one middle-class job); service pay by job class (20 s for a middle-class job); middle-class houses joining the middle class, paying 5% dues, and bringing it to a site that did not interest it; inspector lines for a workplace's families, a storehouse's keeper and a house's family and jobs; `tests/test_labour.gd`. **Waiting on nation-builder-ea's house types:** the per-house family draw (from its `family` ranges), the parson (the chapel gets its middle-class job once a Master's house exists, since an empty chapel would stall Tier 2), and the soak with Master's houses.

## Where we are

- **One anonymous pool of workers** (VILLAGERS.md §1): 4 founding adults, plus `workers_per_house` for each house's tier (6 for Settlers, 10 for Villagers). Workplaces are staffed by priority, then placement order, and take their whole crew or nobody. Carriers come after buildings at each priority level.
- **Wages are not tied to jobs** (VILLAGERS.md §4). Each sale's labour goes into one payroll. At payday the payroll is shared between all houses by the workers each provides, employed or not.
- **Class comes from the tier** (FACTIONS.md §13 item 2): Settlers have none, Villagers are working class, and Townsfolk (Tier 3, not built) would be middle class.
- **Jobs today**, by building: well 1, farm 2, woodcutter 2, forester 1 (service), mill 2, bakery 2, berry bushes 1, chapel 1 (service), fisher 1, woodshed 1, sawmill 2, pig farm 2, butcher 1, hunter 1, forager 1, plus 6 carriers per storehouse. That is 34 jobs, plus carriers, in the economy test village.

## Decisions (15 October 2026)

1. **Class follows house type.** There are three house types: **poor**, **middle** and **wealthy**. The existing homestead, with its Settlers and Villagers tiers, is the poor house. Tiers still decide needs and promotion within a type. This refines FACTIONS.md §13 item 2: a house type's class takes the place of a tier's class. Settlers stay unclassed and Villagers working class, both in the poor house.
2. **Money belongs to families.** A family is a single person, or a married couple, with or without children. Wages go to the family whose members did the work, not to every house in the village. **A family with no job is poor.** Its savings run down, and it falls behind on its needs and in favour.
3. **Higher classes may take lower-class work. Lower classes may not take higher-class work** unless they have the right education. A middle-class worker can fill a working-class job. A working-class worker cannot fill a middle-class job, so that job stays empty.
4. **No further class splits for now.** Farm hands and millers are both working class. *Note for later:* education is the likely way to open higher-class jobs to lower-class workers, and possibly to split classes further (choice C of the first scope).
5. **Starting numbers:** a storekeeper takes 30% of the storehouse markup, and a parson earns 20 s a payday from the treasury.

### Note for the school system (later)

- A school educates a household's children (or adults, at a cost). An educated working-class worker may take middle-class jobs.
- Education could also become the way into skilled jobs within a class (master miller, schoolmaster), if classes are later split further.
- Children need a family model (decision 2). For now children count only as family size.

## Proposal

### 1. Jobs name a class

Each workplace's crew is split by class in `buildings.json`, for example `"jobs":{"middle":1,"working":5}`. `workers` stays as the total, derived from `jobs`, so nothing that reads it changes. Classes rank: unclassed < working < middle < wealthy.

| Job class | Who may fill it |
| --- | --- |
| `""` (any) | Anyone |
| `working` | Working class, or anyone of a higher class. Unclassed workers (Settlers, founding adults) count as working for now, as they do today |
| `middle` | Middle class or wealthy only. Otherwise the job stays empty (decision 3), until schools exist |

Staffing keeps its order: priority, then placement, then carriers. Each job prefers its own class, then takes a higher class. A building whose middle-class job is empty still runs if its other jobs are filled (a storehouse without a keeper still sends carriers).

### 2. Workers belong to families, in houses

- **Every worker belongs to a family, and every family to a house.** Staffing records which family fills each job. This is derived each tick, so it is not saved.
- **Payday pays each family for its members' work.** A sale's labour is split between the families who made it, by job. A storekeeper's share and a parson's wage go to their families.
- **Savings are the family's.** Today a house's `silver` is the household's. With one family per village house, a house's `silver` is its family's. Town buildings for several families will need a purse per family.
- **Founding adults** become a founding family (or families) in the first house.

### 3. House types

| Type | Class | Families | Tiers | First example |
| --- | --- | --- | --- | --- |
| Poor | Unclassed (Settlers), working (Villagers) | One family in a village; several in town flats and slums (later) | Settlers → Villagers (existing) | The homestead |
| Middle | Middle | One family | One tier for now; its own basket | A "Master's house" |
| Wealthy | Wealthy | One family, plus servants later | Later | A manor, with the gentry (later) |

A house row in `buildings.json` gains `class`, which overrides the tier's class (FACTIONS.md §8 already expects town house types to name their class). A middle house's basket is water, a staple and fuel at first, plus a comfort once Tier 3 goods exist. It does not promote.

### 4. The first middle-class jobs

| Job | Building | Paid from | Why |
| --- | --- | --- | --- |
| **Storekeeper** | Storehouse, 1 per storehouse | 30% of the markup, before the rest pays the carriers | The shopkeeper is the middle class's trade, which ties its fortunes to the markup it already favours |
| **Parson** | Chapel (a service) | The treasury: 20 s a payday, above the 10 s service rate | Makes the chapel a middle-class institution, with a public lever in his pay |

Without a middle-class family to fill them, a storehouse runs with no keeper's share, and a chapel stands empty. So the first Master's house becomes a real goal at Tier 2.

### 5. Factions

- Middle-class houses belong to the middle class (FACTIONS.md §3). They need no contest.
- They pay **dues** (5%, like the unions), which funds its lobbying. This answers its open question about income.
- Its happiness stance term and its power read its own houses at last.

## Families and houses (decided 15 October 2026)

- **A village house holds one family:** a single adult, or a couple, with or without children. Its savings are that family's savings, so a house's `silver` keeps its meaning.
- **Houses built for several families are town buildings:** poor flats and slums, and middle-class apartments. They come with towns, each family with its own purse.
- **Children count as family size for now.** They are more mouths to feed but do no work, until schools make them people.
- **The village shrinks to family scale.** A house now supplies 1–2 workers instead of 6–10. A village needs more, smaller and cheaper houses for the same jobs, and the starter layout, the economy test village and house costs change with it.

## Who does what

| nation-builder-ea: house types | nation-builder-8e: everything else |
| --- | --- |
| House rows: the poor cottage (one family; Settlers → Villagers), the Master's house (middle), a reserved wealthy manor. Town flats, slums and apartments go in the plan for towns | Job classes: `jobs` per building, ranks, and validation |
| `class` on a house row, overriding the tier's class when present | Staffing by class and by family, with no upward fallback |
| Family size per house type: adults and children | Wages paid to the families whose members worked |
| Needs scaled by family size, and the middle house's basket | Storekeeper (30% of the markup) and parson (20 s a payday) |
| House size, cost and models; starter and economy-village layouts for more, smaller houses | Factions: middle-class houses aligned and paying dues, and the contest per family |
| Build menu entries | Saves, inspector lines for jobs and families, tests and the soak |

**The contract between the two.** A house row may carry `class`. A house's class is its row's `class` if present, else its tier's. Its working adults come from its family. ea's data names the adults and children per house type (and tier, if they differ). 8e's staffing reads the adults, and ea's needs read the family size.

## Work items

1. **Data and validation.** Add `jobs` per building, `class` per house row, family sizes per house type and tier, and the Master's house row.
2. **Families.** One family per village house, sized by ea's data, with a seeded mix of singles and couples, with or without children. Saves gain the family (`LEGACY_ADDED`: an older house becomes one family of its type's size, keeping its savings).
3. **Staffing by class and family.** Fill jobs from families, by class rank, with no upward fallback. Tests: higher classes fill lower jobs, never the reverse, priorities hold, and results are the same across batch sizes.
4. **Wages by family.** Pay the labour to the families who worked, and the keeper's share and parson's wage to theirs. Tests: idle families earn nothing, and the money invariant holds.
5. **The two jobs and the Master's house.** Tests: an empty keeper's job, an empty chapel, and a Master's house filling both.
6. **Factions.** Middle houses aligned with the middle class, dues, and their happiness and power. With one family per village house, the contest stays per house.
7. **HUD.** The inspector shows jobs by class and who fills them, families in a house (members, job, savings), and empty middle-class jobs ("needs a middle-class family"). The build menu lists the Master's house.
8. **Balance soak.** The economy test village with one or two Master's houses. Check family incomes (employed against idle), the middle class's dues and lobbying, and the treasury against the parson's wage.

## House types: built (15 October 2026, nation-builder-ea)

- **Cottage** (`house`, 2×1, 3 logs): the poor house, Settlers → Villagers, a family of 1–2 adults and 0–3 children. The starter has four. `Scenario.CHAIN` adds two more with the mill, bakery and woodshed.
- **Master's house** (`master_house`, 2×2, 8 logs + 2 planks, Tier 2): class `middle`, family of 1–2 adults and 0–2 children, `fixed_tier` 2 (the Villager basket), never promotes or demotes.
- **Inn** (`inn`, 3×2, 10 logs + 4 planks, Tier 2): class `working`, 4 single lodgers (`lodgers`), `fixed_tier` 2. Its `comfort` lifts the happiness of every house within 12 road tiles by 15 points while it has road access (`Needs.comfort`). The user asked for it on 15 October.
- **Manor** (`manor`, 3×3): class `elite`, `faction` gentry, `reserved`. It is in data but cannot be built and is hidden from the build menu.
- **Needs per mouth** (user decision): a family eats one basket every tier interval × `Needs.REFERENCE_MOUTHS` (6) ÷ mouths. Adults count 1 and children ½. Four mouths left the family-scale test village unable to feed itself.
- **Starting purse** (user decision): `Economy.GRANT_PER_ADULT` = 20 s per adult of the family drawn for the house, replacing the 50 s per house.
- **Economy test village**: 33 family houses (cottages, the inn and two Master's houses), two hunters, five berry bushes and six wells. Purses beyond the first eight houses arrive as outside money.
- **Open:** the test village hits a logistics ceiling after about 4 minutes. Twelve carriers moving one unit a trip cannot stock 33 pantries and feed the workshops, so production and wages fall. Carrier capacity or speed, or more storehouses, is a balance question for the soak (item 8). Three fixture timings also still fail (an unreachable house's downgrade, the campaign save's bread chain and the hour-long logistics run).

## Risks

- **Wages by family, and families of 1–2 workers, change every household's income and the village's scale.** Idle families become poor, which is intended, but the test village's 45% idle workforce (FACTIONS.md §14) will show as real poverty and demotion. The soak decides whether jobs or workers per house need rebalancing.
- **Families touch needs, the faction contest, saves and the HUD.** This is a larger change than the class split alone. Items 2–4 should land together, behind the soak.
- **Shared files.** Staffing, payday and needs are in `village_sim.gd`, `economy.gd` and `needs.gd`, which other sessions also edit. Coordinate before starting.

## Not in this scope

Tier 3 Townsfolk; wealthy houses and their servants (the row is reserved); schools and education (see the note above); further class splits; and strikes by class (FACTIONS.md §6, phase 2).
