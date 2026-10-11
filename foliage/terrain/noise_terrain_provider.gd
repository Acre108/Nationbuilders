class_name NoiseTerrainProvider
extends TerrainProvider

## Procedural rolling-hill terrain, used by both test scenes.
##
## Two noise octaves, matching the shape language the PlacesOS Godot spike
## already used (FastNoiseLite, TYPE_VALUE_CUBIC) -- broad landform plus a
## finer bumpiness pass. Real locations will subclass TerrainProvider and read
## elevation data instead; nothing outside this file assumes noise.
##
## Deterministic: seeded FastNoiseLite gives every client the same ground, which
## is what lets grass placement be derived locally and never networked.

const MASK_EPSILON := 0.001

var seed: int = 1337:
	set(value):
		seed = value
		_configure()

## Peak-to-trough height of the broad landform, world units.
var landform_amplitude: float = 14.0
## World units per landform feature. Larger = wider, gentler hills.
var landform_scale: float = 260.0
## Fine surface detail on top of the landform.
var detail_amplitude: float = 1.1
var detail_scale: float = 22.0

## Slope limits, expressed as the ground normal's Y component: 1.0 is dead
## flat, 0.0 is a vertical wall. At or above `grass_normal_full` grass grows at
## full density; below `grass_normal_none` none grows; between the two it thins
## out, which is what keeps hillsides from ending in a hard contour line.
##
## Named after the normal rather than "slope" deliberately -- an earlier pass
## called these slope_begin/slope_end and the sense got inverted, which silently
## rejected every placement on flat ground and produced a field with no grass
## in it at all.
var grass_normal_full: float = 0.62
var grass_normal_none: float = 0.42


var _landform := FastNoiseLite.new()
var _detail := FastNoiseLite.new()


func _init(initial_seed: int = 1337) -> void:
	seed = initial_seed


func _configure() -> void:
	_landform.noise_type = FastNoiseLite.TYPE_VALUE_CUBIC
	_landform.seed = seed
	_landform.frequency = 1.0 / landform_scale

	_detail.noise_type = FastNoiseLite.TYPE_VALUE_CUBIC
	_detail.seed = seed + 7919
	_detail.frequency = 1.0 / detail_scale


func get_height(x: float, z: float) -> float:
	var landform := _landform.get_noise_2d(x, z) * landform_amplitude
	var detail := _detail.get_noise_2d(x, z) * detail_amplitude
	return landform + detail


func growth_mask_for(x: float, z: float, normal: Vector3) -> float:
	# Slope first: it is the cheap test and rejects most of what gets rejected.
	# smoothstep already returns 1.0 for flat ground (normal.y -> 1.0), so this
	# must NOT be inverted.
	var slope_mask := smoothstep(grass_normal_none, grass_normal_full, normal.y)
	if slope_mask <= MASK_EPSILON:
		return 0.0
	# The painted mask (paths, clearings) comes from the base class.
	return slope_mask * sample_painted_mask(x, z)
