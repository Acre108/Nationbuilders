shader_type spatial;

// Trunks and branches, and the shadow proxy.
//
// Bark colour is per vertex (COLOR.rgb), baked from the species or from the
// source model's own material, so one material serves oak brown and birch
// white-and-black alike. It includes the foliage wind so the trunk sways with
// the exact function its canopy uses -- see tree_wind.gdshaderinc.
//
// The shadow proxy uses this material too. It is drawn shadows-only, so its
// colour never shows, but its sway must match the tree it stands in for or
// the shadow drifts off the canopy in a gust.
render_mode world_vertex_coords;

#include "res://foliage/shaders/foliage_common.gdshaderinc"
#include "res://foliage/shaders/foliage_distance.gdshaderinc"
#include "res://render/village_art.gdshaderinc"
#include "res://foliage/shaders/tree_wind.gdshaderinc"
#include "res://foliage/shaders/tree_lod.gdshaderinc"


group_uniforms tree_bark;
uniform float bark_roughness : hint_range(0.0, 1.0) = 0.9;
// Painted bark opts in with COLOR.a = 0.5; understory card stems stay unchanged.
uniform sampler2D tree_paint_atlas : hint_default_white, filter_linear_mipmap, repeat_disable;
uniform float bark_paint_strength = 0.0;
// Location-wide tint over the baked bark colours.
uniform vec3 bark_tint : source_color = vec3(1.0);
// Impostor bake: 0 renders normally. 1 writes albedo, 2 writes the
// model-space normal (encoded 0..1), both as EMISSION into an unlit bake
// viewport -- see TreeImpostorBaker.
uniform int tree_bake_mode = 0;

varying float v_root_distance;
varying vec3 v_world;

void vertex() {
	VERTEX = tree_displace(VERTEX, MODEL_MATRIX, UV2, 0.0, TIME);
	v_world = VERTEX;
	v_root_distance = distance(CAMERA_POSITION_WORLD, MODEL_MATRIX[3].xyz);
}

void fragment() {
	float value = texture(tree_paint_atlas, UV).r;
	float bark_value = UV.x > 0.5 ? mix(0.06, 1.1, value) : 0.65 + value * 0.5;
	float paint = mix(1.0, bark_value, bark_paint_strength * step(COLOR.a, 0.75));
	ALBEDO = foliage_apply_distance_tint(COLOR.rgb * bark_tint * paint, v_world, CAMERA_POSITION_WORLD);
	ROUGHNESS = bark_roughness;
	SPECULAR = 0.1;
	// The shadow proxy's material keeps tree_impostor_start at 0: in the
	// shadow pass the "camera" is the light, and a distance test against it
	// would throw the proxy away.
	if (tree_impostor_fade(v_root_distance) > tree_dither(FRAGCOORD.xy)) {
		discard;
	}
	if (tree_bake_mode > 0) {
		EMISSION = tree_bake_mode == 1 ? ALBEDO : (INV_VIEW_MATRIX * vec4(NORMAL, 0.0)).xyz * 0.5 + 0.5;
		ALBEDO = vec3(0.0);
		SPECULAR = 0.0;
	}
}
