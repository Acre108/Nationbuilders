# UI rules

Read this before adding to or changing the HUD ([view/overlays/village_hud.gd](../view/overlays/village_hud.gd)) or any other screen. These rules come from the player experience pass of 16 October 2026. Their aim is less information on screen and panels that read at a glance.

## The rule

**One fact per line, at most one "·" per line. Explanations go in tooltips. Anything the player can't act on goes under a Details fold. If a panel scrolls at 1280×720, it is too long.**

Ask of every line: does the player decide something with it? If not, fold it, put it in a tooltip, or cut it.

## What follows from it

### Panels

- **Lead with the decision.** Say first whether the building works and why not, then the controls (pay, stop workers). Inventory, prices, purses, owners and positions come after, under **Details ▸**.
- **Warnings are one red line,** such as "Short of carriers: 1 of 6 on shift". Don't add a neutral status line that only says things are fine ("Connected", "Roads connected").
- **Show a value only when it matters.** Frustration, unpaid wages and pay cuts appear when they are non-zero. Zeros and "none" are noise, except where the zero is the news, such as tax.
- **No sentences in panels.** If a line needs "because", "so" or "which", the reason belongs in a tooltip.
- **Panels share space, so open them one at a time.**
  - The left side holds the Treasury panel and the offer alerts.
  - The right side holds the inspector, the Factions panel, Options and Weather.
  - Opening a panel closes the others that use its space.
- **Panels fit their content and scroll only past the screen.** Never set a fixed height that leaves blank space or always scrolls.

### The top bar and the screen

- **Top left is village status, top right is navigation.**
  - The gold counter and the resource bar sit top left.
  - Factions, the world map and the cog sit top right.
- **Resources show by kind:** food, water, fuel, materials, ingredients and storage fill. A kind holds its goods; hovering breaks it down by good. Don't add single goods to the bar. New goods join a kind through their `categories` in goods.json, or through what they're used for.
- **One way to reach each thing.** All map overlays live in the Overlays menu (keys F3, F5, F6, F7). Don't add a second toggle for an overlay inside another panel.
- **Things that need a choice come to the player.** Faction offers appear as "!" alerts on the left edge, with a countdown clock behind the "!". Don't hide decisions inside a panel the player has to remember to open.
- **Developer tools stay hidden** (F12 or `-- --dev`). The weather panel is one. Player screens never show tuning sliders.

### Words and numbers

- **Sentence case** for statuses and labels: "Missing staple food", not "Missing Staple Food".
- **Goods are counted per minute; money per payday.** Write "24 Water/min" and "10 s per payday", not "1 water every 2.5 s". Convert ticks with `sim.TICKS_PER_SECOND`, never a literal 10 or 5.
- **Name families and places by name,** never by grid coordinates in the main view. Coordinates belong in Details.
- **Map keys:** a coloured ■ and two or three words per colour. What the colours mean goes in the key's tooltip.
- **Hints fade.** The placement card stops explaining roads and right-click after the first few placements (`HINT_PLACEMENTS`).

### Feedback

- **Every action the player takes answers back** with a sound and some motion, within a frame. Use [view/ui_sounds.gd](../view/ui_sounds.gd) for sounds; `ConstructionLayer.pop()` and `dust()` handle things appearing on the map.
  - Placing: a thunk and dust.
  - Demolishing: a lower thunk and dust.
  - Refused: a dull knock, along with the red toast.
- **The village's own good news gets the same treatment, quieter.**
  - A delivery to a site: a knock.
  - A building finishing: a pop and a chime.
  - Payday: a coin clink. The gold counter counts up, and "+12 s" rises from it in green, or in red for a loss.
- **Keep repeating sounds soft and rare.** `ui_sounds.gd` drops repeats within 60 ms. A sound that plays more than a few times a minute should sit well below the others.
- **Motion is short:** under half a second for pops and under two seconds for floating text. Nothing loops for attention except the offer clocks.

### Colours

Reuse the HUD's palette instead of adding new colours:

| Use | Colour |
| --- | --- |
| Body text | `#e4dfd2` |
| Headline or gold value | `#d6c288` |
| Muted or secondary | `#868f7a` |
| Label in a table | `#a9b39a` |
| Good, met | `#a8c38a` |
| Problem, unmet | `#d98c6f` |
| Food balance | `FOOD_COLOURS` in the HUD |

Never use colour alone to carry meaning: needs show ✓ or ✗ as well as green or red.

## Before you finish

- Look at the screenshot the view tests save (`tests/run_view_tests.gd` writes `artifacts/*.png`) at 1280×720.
- Count the lines of any panel you touched: fewer than before is the goal.
