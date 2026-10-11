# SpacesOS environment port

Imported on 11 October 2026 from the local SpacesOS working tree, based on
commit `b58a9f5152648afe4cbf1ae4bc2417a33a59072f`. The source project was not
modified. [spacesos-import.json](spacesos-import.json) records copied paths.

The complete `foliage/`, `lighting/`, and `atmosphere/` modules are included,
along with their transitive runtime code, the nature asset pack and weather
audio. Asset import settings and script UIDs are retained. Generated caches,
downloaded source packs, saved locations, and SpacesOS application/editor scenes
are not imported. The supporting `buildings/`, `props/`, and `scripts/` files
satisfy the modules' shared class dependencies; Nation Builder still starts its
own village scene.

### What the village uses

Only part of the import runs in the game. The village builds three nature
models (`spruce`, `oak`, `lake_boulder_1`), grass tufts, the whole
atmosphere module, all weather audio and `LightingSettings`. The other 81
nature models and the custom willow are kept on purpose for later biomes. The
streamed terrain, water, shoreline, debris, crop, zone, tree-layer, interior and
street-light code is unused but kept, because the imported scripts reference
each other by class name and removing files breaks compilation.

On 11 October 2026 the unused town (street lamp), Buchenhain prop and furniture
assets were removed: `assets/town`, `assets/props`, `content/furniture` and
`content/furniture_overrides`. Their loaders (`SiteStreetLights`,
`SitePropCatalogue`, `FurnitureCatalogue`) still compile but would find nothing.
The import manifest still lists them as a record of the original copy, and
`tools/port_spacesos.cjs` can restore them from the SpacesOS tree.

## Village integration

- `view/village_foliage.gd` uses `NatureMeshBuilder`, `GrassTuftBuilder`,
  `FoliageMultiMesh`, and `FoliageProfile` to render mixed oak/spruce trees,
  rocks, and wind-driven grass. Meshes are cached and grass is batched.
- Placement follows the simulation grid (now 100 by 100 by default). Buildings and
  roads hide trees/rocks and remove grass in their cells; demolition restores
  vegetation. Presentation uses its own seeded RNG and never changes sim state.
- `LightingSettings` configures the sun, AgX display response, ambient light,
  shadows and occlusion. `AtmosphereSystem` drives time, sky, clouds, rain,
  mist, lightning, audio, wetness, and wind. Toon materials also receive the
  imported cloud-shadow and wet-surface functions.
- The base adaptation inside the imported modules is the optional
  `AtmosphereSystem.weather_focus`: orthographic rain and local weather use
  the camera's ground focus instead of its elevated position.
- The subsequent [village art pass](VILLAGE_ART.md) adds opt-in canopy/wind
  shading and per-material cloud scale, density bands and tint. Imported
  location materials retain their original defaults. `VillageAtmosphere`
  applies the village's lighting profile before the normal sky/weather update.
- The village renders smoothly at full resolution. The original 32-colour
  lookup, screen outline, and dithered toon light were disconnected so the
  imported colors render directly, and the optional pixel view is being
  removed (see [DESIGN.md](DESIGN.md#art-direction)). Old terrain, buildings,
  roads, carriers, goods, and HUD colors now use the imported material families.
  The default is a fixed clear
  afternoon at 16:00; restart restores it. Weather animation runs in real time,
  independently of simulation pause/speed.

The full streamed terrain, water, habitat, crop, interior-lighting, and
street-light APIs are available in the copied modules. The current village
uses its own grid, relief and medieval building models; it does not instantiate
SpacesOS geographic locations, building interiors, street lamps, or streaming.

## Controls

| Key | Action |
| --- | --- |
| `[` / `]` | Move time backward / forward one hour |
| `;` / `'` | Move time backward / forward 15 minutes |
| `0` | Toggle a two-minute day/night cycle |
| `5` / `6` / `7` / `8` / `9` | Storm / mist / clear / cloudy / rain |
| `-` / `=` | Reduce / increase weather intensity |
| `B` | Trigger lightning |
| `\` | Toggle dry / soaked surfaces |

## Import and verification

Use **Godot 4.7.2 Forward+**. The old 4.3 pin cannot support the imported
lighting API. Opening the project in the editor imports assets and registers
the shared GDScript classes. For a fresh command-line checkout, run
`godot --headless --editor --import --path .` first.

```powershell
./tools/run_tests.ps1
./tools/run_tests.ps1 -View
./tools/run_tests.ps1 -Environment
```

At the time of the port, 78 simulation, 66 view/input/render and 251
environment checks passed on Windows with an NVIDIA RTX 3060 Ti; current counts
are in [VALIDATION.md](VALIDATION.md). Environment checks cover loaded meshes, road carving/regrowth, untouched simulation state,
day/night lighting, rain/wind/wetness, ground-focused rain, and restart/exit.
Screenshots are saved to `artifacts/environment-day.png`,
`environment-night.png`, and `environment-rain.png`.

Godot logs a host root-certificate-store error in this sandbox; the local
rendering and tests complete successfully without network access.

The original system notes are preserved under [spacesos/](spacesos/):
[foliage](spacesos/FOLIAGE.md), [atmosphere](spacesos/ATMOSPHERE.md),
[lighting](spacesos/LIGHTING.md), and [nature assets](spacesos/NATURE_PACK.md).
Those notes describe SpacesOS and may link to tools or location documents that
belong to the source project.
