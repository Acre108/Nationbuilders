class_name FoliageQuality
extends Resource

## The single foliage quality setting, ready to be driven from a graphics
## options menu.
##
## Everything a player would recognise as "lower the foliage setting" lives
## here: grass density, streaming radius, LOD distances, tree impostor distance
## and tree shadow quality. One knob, because these have to move together --
## halving density while keeping a 250 m streaming radius just makes a sparse
## field that still costs full CPU to generate.
##
## Presets are tuned against the brief's target: 60 fps at 1080p on a GTX 1660 /
## RX 5600 at HIGH. They are starting points to be corrected by the measured
## numbers from the benchmark scene, not measurements themselves -- see
## docs/FOLIAGE.md for what to lower first on weaker hardware.

enum Level { LOW, MEDIUM, HIGH, ULTRA }

@export var level: Level = Level.HIGH

@export_group("Grass")
## Multiplies FoliageProfile.base_density. The dominant cost in the whole
## system, and the first thing to lower on weak hardware.
@export_range(0.05, 2.0, 0.01) var density_scale: float = 1.0
## Radius around the camera within which grass chunks exist at all. Just past
## lod_far_end, so chunks are built before they come into view -- beyond
## lod_far_end grass is invisible, and streaming further only costs CPU.
## Second-most expensive grass knob: cost grows with the square of this.
@export_range(16.0, 512.0, 1.0) var streaming_radius: float = 110.0
## How far ground and trees exist. Past it, fog and sky. Tree impostors keep
## the far part of this cheap; the ground's detail drops with distance.
@export_range(100.0, 4000.0, 10.0) var view_distance: float = 600.0
## How far the coarse horizon ground reaches beyond view_distance, so distant
## hills stand on the skyline. Only terrain: no grass, trees or shadows out
## there. 0 = no horizon ring.
@export_range(0.0, 20000.0, 10.0) var horizon_distance: float = 6000.0
@export_range(1, 32) var blades_per_tuft: int = 11
@export_range(1, 8) var blade_segments: int = 4

@export_group("Grass LOD")
## Distance at which full-detail tufts give way to the reduced mesh.
@export_range(4.0, 200.0, 1.0) var lod_near_end: float = 32.0
## Distance past which grass geometry stops entirely and the terrain shader
## carries the look alone.
@export_range(8.0, 400.0, 1.0) var lod_far_end: float = 90.0
## Crossfade width for Godot's visibility ranges. Too small and chunks pop; too
## large and both LODs render together over a wide band.
@export_range(0.0, 40.0, 0.5) var lod_fade: float = 8.0
## Fraction of tufts that survive past lod_near_end into the far band, drawn
## wider with a cheaper mesh. The far band's cost is roughly proportional.
@export_range(0.05, 1.0, 0.01) var lod_far_keep: float = 0.4

@export_group("Trees")
@export_range(20.0, 1000.0, 5.0) var tree_impostor_distance: float = 140.0
@export_range(0.0, 400.0, 5.0) var tree_shadow_distance: float = 80.0
@export_range(0, 4) var directional_shadow_splits: int = 3
@export var tree_soft_shadows: bool = true
## Sun cascades also cover geographic buildings. Tree proxy casting retains
## its separate shorter tree_shadow_distance limit.
@export_range(40.0, 600.0, 5.0) var directional_shadow_distance: float = 160.0
## Multiplies cards for legacy comparison plants. Nature pack meshes keep
## their authored silhouettes; impostor distance and shadow range control cost.
@export_range(0.25, 2.0, 0.05) var tree_canopy_detail: float = 1.0


## Builds a preset. Callers should use this rather than constructing the
## resource directly, so the presets stay in one place.
static func create(preset: Level) -> FoliageQuality:
	var q := FoliageQuality.new()
	q.level = preset
	match preset:
		Level.LOW:
			q.density_scale = 0.25
			q.streaming_radius = 52.0
			q.view_distance = 300.0
			q.horizon_distance = 2500.0
			q.blades_per_tuft = 5
			q.blade_segments = 2
			q.lod_near_end = 14.0
			q.lod_far_end = 36.0
			q.lod_fade = 4.0
			q.lod_far_keep = 0.3
			q.tree_impostor_distance = 55.0
			q.tree_shadow_distance = 30.0
			q.directional_shadow_distance = 80.0
			q.directional_shadow_splits = 1
			q.tree_soft_shadows = false
			q.tree_canopy_detail = 0.5
		Level.MEDIUM:
			q.density_scale = 0.5
			q.streaming_radius = 76.0
			q.view_distance = 450.0
			q.horizon_distance = 4000.0
			q.blades_per_tuft = 8
			q.blade_segments = 3
			q.lod_near_end = 22.0
			q.lod_far_end = 60.0
			q.lod_fade = 6.0
			q.lod_far_keep = 0.35
			q.tree_impostor_distance = 90.0
			q.tree_shadow_distance = 50.0
			q.directional_shadow_distance = 120.0
			q.directional_shadow_splits = 2
			q.tree_soft_shadows = false
			q.tree_canopy_detail = 0.75
		Level.HIGH:
			q.density_scale = 1.0
			q.streaming_radius = 106.0
			q.view_distance = 600.0
			q.horizon_distance = 6000.0
			q.blades_per_tuft = 11
			q.blade_segments = 4
			q.lod_near_end = 32.0
			q.lod_far_end = 90.0
			q.lod_fade = 8.0
			q.lod_far_keep = 0.4
			q.tree_impostor_distance = 140.0
			q.tree_shadow_distance = 80.0
			q.directional_shadow_distance = 160.0
			q.directional_shadow_splits = 3
			q.tree_soft_shadows = true
			q.tree_canopy_detail = 1.0
		Level.ULTRA:
			q.density_scale = 1.8
			q.streaming_radius = 166.0
			q.view_distance = 900.0
			q.horizon_distance = 8000.0
			q.blades_per_tuft = 16
			q.blade_segments = 5
			q.lod_near_end = 55.0
			q.lod_far_end = 150.0
			q.lod_fade = 12.0
			q.lod_far_keep = 0.5
			q.tree_impostor_distance = 240.0
			q.tree_shadow_distance = 130.0
			q.directional_shadow_distance = 260.0
			q.directional_shadow_splits = 4
			q.tree_soft_shadows = true
			q.tree_canopy_detail = 1.3
	return q


static func level_name(preset: Level) -> String:
	match preset:
		Level.LOW: return "Low"
		Level.MEDIUM: return "Medium"
		Level.HIGH: return "High"
		Level.ULTRA: return "Ultra"
	return "Unknown"
