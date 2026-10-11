shader_type spatial;
render_mode cull_disabled, world_vertex_coords;

#include "res://foliage/shaders/foliage_common.gdshaderinc"
#include "res://foliage/shaders/foliage_distance.gdshaderinc"
#include "res://render/village_art.gdshaderinc"
#include "res://foliage/shaders/tree_wind.gdshaderinc"
#include "res://foliage/shaders/tree_lod.gdshaderinc"

uniform sampler2D nature_texture : source_color, hint_default_white, filter_linear_mipmap;
uniform vec4 nature_colour : source_color = vec4(1.0);
uniform float nature_alpha_cut = 0.0;
uniform float leaf_translucency = 0.3;
uniform int tree_bake_mode = 0;
uniform bool nature_shadow_caster = false;
// Optional hue replacement (NatureAssetCatalogue.ASSET_RECOLOURS): rgb = target
// colour, a = amount. Keeps the texture's light/dark detail, swaps its hue --
// for multi-coloured textures a plain nature_colour multiply cannot pull to
// one colour without tipping some strands another way.
uniform vec4 nature_recolour : source_color = vec4(1.0, 1.0, 1.0, 0.0);
varying vec3 v_world;
varying float v_distance;
varying float v_variation;
varying vec3 v_model_normal;
varying vec3 v_world_normal;
varying vec3 v_crown_position;
varying float v_tree_tone;

void vertex() {
	v_crown_position = VERTEX - MODEL_MATRIX[3].xyz;
	v_tree_tone = fract(sin(dot(MODEL_MATRIX[3].xz, vec2(17.13, 37.71))) * 4217.3);
	v_model_normal = normalize(inverse(mat3(MODEL_MATRIX)) * NORMAL);
	v_world_normal = NORMAL;
	if (village_art_enabled && COLOR.g > 0.5) {
		vec3 crown = normalize(VERTEX - MODEL_MATRIX[3].xyz - vec3(0.0, UV2.y * 0.55, 0.0));
		v_world_normal = normalize(mix(NORMAL, crown, 0.75));
		NORMAL = v_world_normal;
	}
	v_distance = distance(CAMERA_POSITION_WORLD, MODEL_MATRIX[3].xyz);
	v_variation = INSTANCE_CUSTOM.x;
	VERTEX = tree_displace(VERTEX, MODEL_MATRIX, UV2, COLOR.g, TIME);
	v_world = VERTEX;
}

void fragment() {
	vec4 texel = texture(nature_texture, UV) * nature_colour;
	if (village_art_enabled && COLOR.g > 0.5) {
		// Coarser mip coverage closes subpixel holes without adding leaf cards.
		vec4 clustered = textureLod(nature_texture, UV, village_canopy_fullness * 2.5) * nature_colour;
		texel = mix(texel, clustered, village_canopy_fullness);
	}
	float cutoff = village_art_enabled ? nature_alpha_cut * mix(1.0, 0.45, village_canopy_fullness) : nature_alpha_cut;
	if (texel.a < cutoff) { discard; }
	if (tree_bake_mode == 0 && !nature_shadow_caster && tree_impostor_fade(v_distance) > tree_dither(FRAGCOORD.xy)) { discard; }
	vec3 base = texel.rgb * mix(0.94, 1.06, v_variation);
	if (nature_recolour.a > 0.0) {
		const vec3 LUMA = vec3(0.2126, 0.7152, 0.0722);
		float detail = dot(base, LUMA) / max(dot(nature_recolour.rgb, LUMA), 0.001);
		base = mix(base, nature_recolour.rgb * clamp(detail, 0.3, 1.6), nature_recolour.a);
	}
	ALBEDO = foliage_apply_distance_tint(base, v_world, CAMERA_POSITION_WORLD);
	if (village_art_enabled && tree_bake_mode == 0) {
		float facing = max(0.0, dot(normalize(v_world_normal), normalize(atmosphere_sun_direction)));
		float detail = clamp(dot(base, vec3(0.3, 0.55, 0.15)) * 2.4, 0.0, 1.0);
		// Crown-space clusters stay attached to the leaves as the tree sways.
		float cluster = fract(sin(dot(floor(v_crown_position*mix(4.0,2.0,village_canopy_readability)),vec3(17.13,37.71,91.17)))*4217.3);
		detail = mix(floor(detail * 4.0 + 0.5) / 4.0, 0.35+floor(cluster*3.0)/3.0*0.5, mix(0.65,0.30,village_canopy_readability));
		vec3 cool = mix(vec3(0.025, 0.085, 0.080), vec3(0.10, 0.22, 0.13), detail);
		cool += vec3(0.025, 0.045, 0.035) * village_canopy_readability;
		vec3 warm = mix(vec3(0.24, 0.30, 0.055), vec3(0.57, 0.48, 0.085), detail);
		float rim = smoothstep(0.35, 0.88, facing);
		vec3 canopy = mix(cool, warm, floor(rim * 3.0 + 0.5) / 3.0 * village_canopy_highlights);
		// Modest root-seeded tone variation separates overlapping tree masses.
		canopy *= mix(1.0, mix(0.82,1.18,v_tree_tone), village_canopy_readability);
		ALBEDO = mix(ALBEDO, canopy * atmosphere_cloud_colour(v_world), COLOR.g * village_forest_darkness);
		ALBEDO = village_colour_grade(ALBEDO, v_world_normal);
	}
	ROUGHNESS = 0.9;
	// Leaf cards have two sides, but crown lighting has one outward normal.
	// Undo the renderer's back-face flip to keep highlights in connected masses.
	if (village_art_enabled && COLOR.g > 0.5 && !FRONT_FACING) { NORMAL = -NORMAL; }
	SPECULAR = 0.08;
	BACKLIGHT = vec3(leaf_translucency * COLOR.g);
	if (tree_bake_mode != 0) {
		ALBEDO = vec3(0.0);
		EMISSION = tree_bake_mode == 1 ? base : normalize(v_model_normal) * 0.5 + 0.5;
	}
}
