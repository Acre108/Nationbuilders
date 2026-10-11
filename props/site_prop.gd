@tool
class_name SiteProp
extends Node3D

## Keep authored metre scale. The scene owns fixed collision and separate LODs.
@export var asset_id: StringName
@export var use_far_mesh := false:
	set(value):
		use_far_mesh = value
		if is_node_ready(): _apply_lod()

func _ready() -> void:
	_apply_lod()

func _apply_lod() -> void:
	var near := find_child(String(asset_id) + "_Near", true, false) as Node3D
	var far := find_child(String(asset_id) + "_Far", true, false) as Node3D
	if near: near.visible = not use_far_mesh
	if far: far.visible = use_far_mesh
