shader_type spatial;
render_mode world_vertex_coords;

#include "res://foliage/shaders/foliage_common.gdshaderinc"
#include "res://foliage/shaders/foliage_distance.gdshaderinc"
#include "res://render/village_art.gdshaderinc"
#include "res://foliage/shaders/tree_wind.gdshaderinc"
#include "res://foliage/shaders/tree_lod.gdshaderinc"


uniform sampler2D tree_paint_atlas : hint_default_white, filter_linear_mipmap, repeat_disable;
uniform float paint_strength = 0.65;
uniform float leaf_translucency = 0.12;
uniform int tree_bake_mode = 0;
varying vec3 v_world;
varying vec4 v_paint;
varying float v_variation;
varying float v_root_distance;

void vertex() {
	v_paint = COLOR;
	v_variation = INSTANCE_CUSTOM.r;
	VERTEX = tree_displace(VERTEX, MODEL_MATRIX, UV2, COLOR.g, TIME);
	v_world = VERTEX;
	v_root_distance = distance(CAMERA_POSITION_WORLD, MODEL_MATRIX[3].xyz);
}

void fragment() {
	float brush = texture(tree_paint_atlas, UV).r;
	float t = foliage_palette_t(v_world, TIME, v_variation);
	t += v_paint.b - 0.5 + (v_paint.a - 0.5) * 0.26 - v_paint.r * 0.09;
	t += (brush - 0.72) * paint_strength;
	vec3 base = texture(foliage_palette, vec2(clamp(t, 0.0, 1.0), 0.5)).rgb;
	base *= mix(0.78, 1.09, v_paint.a);
	base *= mix(vec3(0.91, 0.98, 1.06), vec3(1.06, 1.015, 0.91), v_paint.a);
	ALBEDO = foliage_apply_distance_tint(base, v_world, CAMERA_POSITION_WORLD);
	ROUGHNESS = 0.96;
	SPECULAR = 0.08;
	BACKLIGHT = vec3(leaf_translucency * 0.4) * base;
	if (tree_impostor_fade(v_root_distance) > tree_dither(FRAGCOORD.xy)) { discard; }
	if (tree_bake_mode > 0) {
		EMISSION = tree_bake_mode == 1 ? ALBEDO : (INV_VIEW_MATRIX * vec4(NORMAL, 0.0)).xyz * 0.5 + 0.5;
		ALBEDO = vec3(0.0);
		BACKLIGHT = vec3(0.0);
		SPECULAR = 0.0;
	}
}
