class_name BuildingIndirectLighting
extends Node

## Derived GI lifetime. A completed command invalidates the field immediately,
## then recreates it after the renderer has observed removal/new geometry.
## Plan gestures do not replace the shell until their command is committed.
var environment: Environment
var quality_level: FoliageQuality.Level = FoliageQuality.Level.HIGH
var indirect_enabled := true
var geometry_root: Node3D
var revision := 0
var ready_revision := 0
var pending_frames := 0

func _ready() -> void:
	set_process(false)

func refresh(geometry: Node3D) -> void:
	geometry_root = geometry
	revision += 1
	environment.sdfgi_enabled = false
	if is_instance_valid(geometry_root): LightingSettings.configure_building_geometry(geometry_root)
	pending_frames = 2
	set_process(true)

func set_quality(level: FoliageQuality.Level) -> void:
	quality_level = level
	LightingSettings.apply_environment_quality(environment,level)
	refresh(geometry_root)
	if is_instance_valid(geometry_root): BuildingLocalLights.set_quality(geometry_root,level)

func set_enabled(value: bool) -> void:
	indirect_enabled = value
	refresh(geometry_root)

func _process(_delta: float) -> void:
	pending_frames -= 1
	if pending_frames > 0: return
	LightingSettings.apply_building_indirect(environment,quality_level,
		indirect_enabled and is_instance_valid(geometry_root))
	ready_revision = revision
	set_process(false)

func _exit_tree() -> void:
	if environment != null: environment.sdfgi_enabled = false
