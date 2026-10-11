extends Resource
## Village-only art direction. Geometry, camera and simulation never read this.
@export_group("Sun and shade")
@export_range(0.0, 1.0) var sun_warmth := 0.72
@export_range(0.0, 3.0) var sun_intensity := 1.75
@export var shadow_tint := Color("637f91")
@export_range(0.0, 1.0) var ambient_fill := 0.58
@export_range(0.5, 2.0) var exposure := 1.0
@export_range(0.0, 1.0) var surface_detail := 0.65
@export_range(0.0, 1.0) var canopy_highlights := 0.75
@export_range(0.0, 1.0) var canopy_fullness := 0.65
@export_range(0.0, 1.0) var canopy_readability := 0.65
@export_range(0.0, 1.0) var ao_strength := 0.75
## World azimuth gives upper-left screen light at the original camera angle.
@export_range(-180.0, 180.0) var sun_azimuth := -50.0
@export_range(0.0, 1.0) var palette_grade := 0.32
@export_group("Ground and canopy")
@export_range(0.0, 1.0) var terrain_variation := 0.65
@export_range(0.0, 1.0) var forest_darkness := 0.80
@export_range(0.0, 0.4) var meadow_detail_cover := 0.16
@export_range(1, 3) var grass_patch_density := 2
@export_range(0.0, 1.0) var flower_patch_density := 0.28
@export var grass_sun := Color("bbc16a")
@export var grass_shade := Color("698954")
@export var forest_floor := Color("24463e")
@export var roof_terracotta := Color("ad5937")
@export var plaster_cream := Color("e4cfa1")
@export var path_ochre := Color("c7aa7b")
@export var crop_gold := Color("dfb543")
@export var water_turquoise := Color("398fa4")
@export_group("Environmental motion")
@export_range(0.0, 1.0) var cloud_shadow_opacity := 0.22
@export_range(32.0, 160.0) var cloud_tile_size := 72.0
@export_range(0.0, 0.02, 0.0001) var cloud_speed := 0.0015
@export var wind_direction := Vector2(1.0, 0.35)
@export_range(0.0, 0.3) var wind_strength := 0.16
@export_range(0.0, 0.1) var wind_speed := 0.028
@export_range(0.0, 1.0) var particle_density := 0.18
@export_range(0.0, 1.0) var water_glints := 0.65

func apply_material(target: ShaderMaterial) -> void:
	target.set_shader_parameter("village_art_enabled", true)
	target.set_shader_parameter("village_grade", palette_grade)
	target.set_shader_parameter("village_forest_darkness", forest_darkness)
	target.set_shader_parameter("village_surface_detail", surface_detail)
	target.set_shader_parameter("village_canopy_highlights", canopy_highlights)
	target.set_shader_parameter("village_canopy_fullness", canopy_fullness)
	target.set_shader_parameter("village_canopy_readability", canopy_readability)
	target.set_shader_parameter("village_wind_strength", wind_strength)
	target.set_shader_parameter("village_wind_direction", wind_direction.normalized())
	target.set_shader_parameter("village_wind_speed", wind_speed)
	target.set_shader_parameter("atmosphere_cloud_tile_size", cloud_tile_size)
	target.set_shader_parameter("atmosphere_cloud_deck_height", 18.0)
	target.set_shader_parameter("atmosphere_cloud_bands", 5.0)
	target.set_shader_parameter("atmosphere_cloud_tint", Color("a8bac9"))
