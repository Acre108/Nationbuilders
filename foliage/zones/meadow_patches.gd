class_name MeadowPatches
extends RefCounted

## Large-scale variety inside meadows (environment zones Z4): lush and thin
## patches 20-60 m across, flower clusters, and which flower grows where.
## Real meadows are not uniform turf -- damp hollows grow tall and lush,
## dry knolls short and pale, and wild flowers grow in drifts of one kind.
##
## Worker-safe and deterministic: read-only FastNoiseLite fields seeded from
## the world seed, plus a positional hash, so GrassPlacer (placement) and
## GrassChunk.prepare() (which mesh a tuft draws with) can both ask without
## extra random draws and without changing PlacementResult or carving.

const LUSH_SALT := 0x4D3A01
const BLOOM_SALT := 0x4D3A02
const HUE_SALT := 0x4D3A03

## From the MEADOW zone recipe (ZoneRecipe.tall_grass_share etc.).
var tall_share: float = 0.0
var patchiness: float = 0.0
var bloom_clustering: float = 0.0

var _lush: FastNoiseLite
var _bloom: FastNoiseLite
var _hue: FastNoiseLite
## 1 / mean drift strength, measured once over a large area, so bloom_factor()
## averages 1 whatever the noise's distribution.
var _bloom_norm: float = 1.0
## With observed zones: where variety applies (EnvironmentZones.variety_at()),
## so mown gardens and fields stay even. Null = everywhere.
var zones: EnvironmentZones


static func for_profile(profile: FoliageProfile) -> MeadowPatches:
	var meadow := profile.zone_recipes()[EnvironmentZones.Zone.MEADOW]
	if meadow.tall_grass_share <= 0.0 and meadow.grass_patchiness <= 0.0 and meadow.bloom_clustering <= 0.0:
		return null
	var patches := MeadowPatches.new()
	patches.tall_share = meadow.tall_grass_share
	patches.patchiness = meadow.grass_patchiness
	patches.bloom_clustering = meadow.bloom_clustering
	patches._lush = _noise(profile.world_seed ^ LUSH_SALT, 1.0 / 45.0, 3)
	patches._bloom = _noise(profile.world_seed ^ BLOOM_SALT, 1.0 / 22.0, 2)
	patches._hue = _noise(profile.world_seed ^ HUE_SALT, 1.0 / 60.0, 1)
	var total := 0.0
	for j in 64:
		for i in 64:
			total += patches._drift(-4000.0 + i * 125.0 + 7.0, -4000.0 + j * 125.0 + 11.0)
	patches._bloom_norm = 1.0 / maxf(total / 4096.0, 0.05)
	return patches


static func _noise(seed_value: int, frequency: float, octaves: int) -> FastNoiseLite:
	var noise := FastNoiseLite.new()
	noise.noise_type = FastNoiseLite.TYPE_VALUE_CUBIC
	noise.seed = seed_value
	noise.frequency = frequency
	noise.fractal_octaves = octaves
	return noise


## 0 = thin, dry patch; 1 = lush hollow. Spread over most of 0..1.
func lush(x: float, z: float) -> float:
	return clampf(0.5 + _lush.get_noise_2d(x, z) * 1.3, 0.0, 1.0)


## Tuft height multiplier from the patch: short on thin ground, tall in lush.
func height_scale(x: float, z: float) -> float:
	var h := lerpf(1.0 - 0.45 * patchiness, 1.0 + 0.5 * patchiness, lush(x, z))
	return lerpf(1.0, h, zones.variety_at(x, z)) if zones != null else h


## grass.gdshader's grass_patch_contrast for this patchiness: how far a
## thin patch shifts up the palette (lighter, drier) and a lush one down.
func patch_contrast() -> float:
	return 0.9 * patchiness


## Multiplier on flower_chance: flowers gather in drifts instead of a uniform
## sprinkle. Averages roughly 1 over a large area, so a location's overall
## flower count stays near what flower_chance says.
func bloom_factor(x: float, z: float) -> float:
	var f := lerpf(1.0, _drift(x, z) * _bloom_norm, bloom_clustering)
	return f * zones.variety_at(x, z) if zones != null else f


func _drift(x: float, z: float) -> float:
	return smoothstep(0.0, 0.35, _bloom.get_noise_2d(x, z))


## Probability that a grass tuft here draws as tall grass.
func tall_chance(x: float, z: float) -> float:
	var l := lush(x, z)
	var chance := tall_share * smoothstep(0.35, 0.85, l) * 1.6
	return chance * zones.variety_at(x, z) if zones != null else chance


## Which of `count` flower sets a flower here draws with: mostly the drift's
## own kind, with a sprinkling of others.
func flower_set(x: float, z: float, count: int) -> int:
	if count <= 1:
		return 0
	var roll := position_hash(x * 1.37, z * 0.91)
	if roll < 0.2:
		return mini(int(roll / 0.2 * count), count - 1)
	var region := clampf(0.5 + _hue.get_noise_2d(x, z) * 1.6, 0.0, 0.9999)
	return int(region * count)


## 0..1 from a world position, stable across runs and engine versions (no
## Godot hash()). Used where a tuft needs a roll and no draw may be added.
static func position_hash(x: float, z: float) -> float:
	var h := int(floor(x * 64.0)) * 73856093 ^ int(floor(z * 64.0)) * 19349663
	h = (h ^ (h >> 13)) & 0xFFFFFFFF
	h = (h * 0x5BD1E995) & 0xFFFFFFFF
	h = h ^ (h >> 15)
	return float(h & 0xFFFFFF) / float(0x1000000)
