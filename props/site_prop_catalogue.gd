class_name SitePropCatalogue
extends RefCounted

## Authored site landmarks, distinct from editable buildings and scatter plants.
const ASSETS := ["pallet_tarp_shelter", "barrel_sauna", "timber_ring_frame", "root_deadwood_mound", "rustic_plank_bench", "red_mesh_chair", "fire_basket"]

static func scene_path(asset: String) -> String:
	return "res://assets/props/buchenhain/%s.tscn" % asset

static func create(asset: String, far: bool = false) -> SiteProp:
	if asset not in ASSETS:
		push_error("Unknown site prop: " + asset)
		return null
	var scene := load(scene_path(asset)) as PackedScene
	if scene == null: return null
	var prop := scene.instantiate() as SiteProp
	prop.use_far_mesh = far
	return prop
