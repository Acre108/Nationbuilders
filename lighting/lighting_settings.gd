class_name LightingSettings
extends RefCounted

## Shared direct-light/ambient policy. Atmosphere owns time and weather;
## this helper owns display response and bounded shadow/occlusion quality.
## Building GI is optional and separate from outdoor foliage quality.
## AgX keeps warm, saturated highlights (low sun, lamps) from shifting to
## yellow-white the way ACES did, and holds shadow detail at exposure 1.0.
const EXPOSURE := 1.0
const AGX_WHITE := 12.0
const AGX_CONTRAST := 1.15
## Warm fill: shade reads as sunlit-ground bounce rather than grey. Raised from
## 0.32/0.45 (cosy pass, Oct 2026) so canopy shade keeps visible detail.
const DAYLIGHT_FILL := 0.5
const DAYLIGHT_FILL_COLOUR := Color("#dccdb0")
const AMBIENT_DAY_SCALE := 0.7
const AMBIENT_NIGHT_SCALE := 0.22
## Share of the ambient taken from the sky's radiance, so shade still varies
## with direction (bluer from above, warmer near the horizon at dusk).
const AMBIENT_SKY_MIX := 0.25
const SUN_SCALE := 0.9
const AO_RADIUS := 0.6

static func make_daylight_environment(level: FoliageQuality.Level = FoliageQuality.Level.HIGH) -> Environment:
	var env := Environment.new()
	env.background_mode = Environment.BG_SKY
	var sky_material := ProceduralSkyMaterial.new()
	sky_material.sky_top_color = Color("#6f9fd0")
	sky_material.sky_horizon_color = Color("#cfd8d6")
	sky_material.ground_bottom_color = Color("#6a7361")
	sky_material.ground_horizon_color = Color("#cfd8d6")
	var sky := Sky.new()
	sky.sky_material = sky_material
	env.sky = sky
	apply_display(env)
	apply_ambient(env, DAYLIGHT_FILL_COLOUR, DAYLIGHT_FILL)
	apply_environment_quality(env, level)
	return env

static func apply_display(env: Environment) -> void:
	env.tonemap_mode = Environment.TONE_MAPPER_AGX
	env.tonemap_exposure = EXPOSURE
	env.tonemap_agx_white = AGX_WHITE
	env.tonemap_agx_contrast = AGX_CONTRAST
	env.adjustment_enabled = false
	# Subtle bloom on HDR highlights only (sun on pale walls, lamp bulbs). Not
	# tied to quality: colour intent stays identical across levels.
	env.glow_enabled = true
	env.glow_normalized = true
	env.glow_intensity = 0.4
	env.glow_strength = 1.0
	env.glow_bloom = 0.0
	env.glow_blend_mode = Environment.GLOW_BLEND_MODE_SOFTLIGHT
	env.glow_hdr_threshold = 1.1
	env.glow_hdr_scale = 1.5

static func apply_ambient(env: Environment, colour: Color, energy: float) -> void:
	# Mostly the explicit colour, so energy stays predictable, with a fixed
	# share of sky radiance for directional variation. Building GI still
	# excludes sky injection; this mix is the only sky term in the fill.
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY if env.sky != null else Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_sky_contribution = AMBIENT_SKY_MIX if env.sky != null else 0.0
	env.ambient_light_color = colour
	env.ambient_light_energy = maxf(0.0, energy)

static func apply_atmosphere(env: Environment, frame: AtmosphereModel.Frame,
	day_scale: float = AMBIENT_DAY_SCALE, night_scale: float = AMBIENT_NIGHT_SCALE,
	flash: float = 0.0) -> void:
	# Weather/time remain global; containment controls rain/audio, not the light
	# seen through windows. Spatial GI and local shadows handle shelter.
	apply_ambient(env, frame.ambient_colour,
		frame.ambient_outdoor_intensity * lerpf(night_scale, day_scale, frame.daylight) + flash * 1.2)

static func apply_environment_quality(env: Environment, level: FoliageQuality.Level) -> void:
	# Forward+ is the production renderer. Keep the direct-light fallback
	# explicit on other renderers and Low; exposure/colour do not change.
	env.ssao_enabled = level >= FoliageQuality.Level.MEDIUM and RenderingServer.get_current_rendering_method() == "forward_plus"
	env.ssao_radius = AO_RADIUS
	env.ssao_intensity = 1.0
	env.ssao_power = 1.25
	env.ssao_detail = 0.35
	env.ssao_light_affect = 0.0
	env.ssao_ao_channel_affect = 0.0
	env.ssil_enabled = false
	env.sdfgi_enabled = false
	if env.get_meta("building_indirect_requested",false): apply_building_indirect(env,level)

static func apply_building_indirect(env: Environment, level: FoliageQuality.Level,
	requested: bool = true) -> void:
	env.set_meta("building_indirect_requested",requested)
	env.ssil_enabled = false
	env.sdfgi_min_cell_size = 0.1
	env.sdfgi_cascades = 4
	env.sdfgi_y_scale = Environment.SDFGI_Y_SCALE_50_PERCENT
	env.sdfgi_use_occlusion = true
	# Bounded interiors use sun/lamp bounce without global sky injection.
	# Exterior locations retain colour fill and the direct-light fallback.
	env.sdfgi_read_sky_light = false
	env.sdfgi_bounce_feedback = 0.3
	env.sdfgi_energy = 1.0
	env.sdfgi_enabled = requested and level >= FoliageQuality.Level.HIGH \
		and RenderingServer.get_current_rendering_method() == "forward_plus" \
		and DisplayServer.get_name() != "headless"

static func configure_building_geometry(node: Node, parent_visible: bool = true) -> void:
	var shown: bool = parent_visible and (not node is Node3D or node.visible)
	if node is GeometryInstance3D:
		node.gi_mode = GeometryInstance3D.GI_MODE_STATIC if shown \
			and node.get_parent().get_meta("slot","") != "glass" \
			and not node.get_meta("light_fixture",false) else GeometryInstance3D.GI_MODE_DISABLED
	for child in node.get_children(): configure_building_geometry(child,shown)

static func configure_sun(sun: DirectionalLight3D, quality: FoliageQuality = null) -> void:
	sun.rotation_degrees = Vector3(-38, 40, 0)
	sun.light_color = Color("#ffe8c4")
	sun.light_energy = 1.35
	sun.visible = true
	sun.light_bake_mode = Light3D.BAKE_DYNAMIC
	apply_shadows(sun, quality if quality != null else FoliageQuality.create(FoliageQuality.Level.HIGH))

static func apply_shadows(sun: DirectionalLight3D, quality: FoliageQuality) -> void:
	sun.shadow_enabled = true
	# Near architecture needs at least two cascades even when tree shadows
	# use the cheapest preset. Tree proxy visibility stays independently capped.
	if quality.directional_shadow_splits <= 2:
		sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_2_SPLITS
	else:
		sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_4_SPLITS
	sun.directional_shadow_max_distance = maxf(quality.directional_shadow_distance, quality.tree_shadow_distance + 20.0)
	sun.directional_shadow_split_1 = 0.1
	sun.directional_shadow_split_2 = 0.25
	sun.directional_shadow_split_3 = 0.55
	sun.directional_shadow_blend_splits = true
	sun.directional_shadow_fade_start = 0.85
	sun.shadow_bias = 0.04
	sun.shadow_normal_bias = 1.2
	# PCSS penumbra sampling is reserved for Ultra. High keeps filtered PCF
	# shadows: outdoor foliage makes the additional PCSS pass expensive.
	sun.light_angular_distance = 0.5 if quality.level == FoliageQuality.Level.ULTRA and quality.tree_soft_shadows and RenderingServer.get_current_rendering_method() == "forward_plus" else 0.0
	# Godot exposes the filter as renderer-global; each scene entry restores
	# its chosen preset, including returning to the standalone building editor.
	RenderingServer.directional_soft_shadow_filter_set_quality(
		(RenderingServer.SHADOW_QUALITY_SOFT_MEDIUM if quality.level == FoliageQuality.Level.ULTRA else RenderingServer.SHADOW_QUALITY_SOFT_LOW)
		if quality.tree_soft_shadows else RenderingServer.SHADOW_QUALITY_HARD)
