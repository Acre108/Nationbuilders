shader_type spatial;

// Canopy shader for card-canopy trees: crossed-at-random quads textured from
// the leaf-cluster atlas, alpha-scissored. `leaf_sprite_mode` can switch the
// atlas off, for a canopy mesh with no sprite of its own, so every fragment
// renders opaque instead.
//
// Lighting comes from CLUMP NORMALS baked into the mesh, not from the geometry:
// each vertex's normal points out from the centre of the leaf clump it belongs
// to (blended towards the canopy centre). A canopy then shades like a few soft
// rounded masses -- the painterly stylised-tree look -- instead of hundreds of
// individually lit cards. Same idea as the grass's forced +Y normal, one level
// up.
//
// Colour comes from the shared palette machinery with the location's TREE
// palette bound to foliage_palette, so leaves take the same wind colour shift
// and world colour field as the grass beneath them.
render_mode cull_disabled, world_vertex_coords;

#include "res://foliage/shaders/foliage_common.gdshaderinc"
#include "res://foliage/shaders/foliage_distance.gdshaderinc"
#include "res://render/village_art.gdshaderinc"
#include "res://foliage/shaders/tree_wind.gdshaderinc"
#include "res://foliage/shaders/tree_lod.gdshaderinc"


group_uniforms tree_leaf;
uniform sampler2D leaf_sprite_atlas : hint_default_white, filter_linear_mipmap, repeat_disable;
// False for a canopy mesh with no sprite of its own: it must stay opaque.
uniform bool leaf_sprite_mode = true;
uniform float leaf_alpha_scissor : hint_range(0.0, 1.0) = 0.5;
// How strongly the sprite's per-leaf brightness modulates the palette colour.
uniform float leaf_sprite_tone : hint_range(0.0, 1.0) = 0.7;
// Darkening towards the canopy's interior (COLOR.r). Cheap stand-in for the
// self-shadowing a dense crown has; keeps the lit shell reading as a surface.
uniform float leaf_interior_darkening : hint_range(0.0, 1.0) = 0.3;
uniform float leaf_translucency : hint_range(0.0, 1.0) = 0.3;
uniform float leaf_roughness : hint_range(0.0, 1.0) = 0.85;
// Impostor bake: 0 renders normally. 1 writes albedo, 2 writes the
// model-space normal (encoded 0..1), both as EMISSION into an unlit bake
// viewport -- see TreeImpostorBaker.
uniform int tree_bake_mode = 0;

varying vec3 v_world;
varying float v_interior;
varying float v_palette_shift;
varying float v_variation;
varying float v_root_distance;

void vertex() {
	// COLOR: r = interior depth (0 shell, 1 core), g = flutter weight,
	// b = palette shift + 0.5 (per species / per original material).
	v_interior = COLOR.r;
	v_palette_shift = COLOR.b - 0.5;
	v_variation = INSTANCE_CUSTOM.x;
	VERTEX = tree_displace(VERTEX, MODEL_MATRIX, UV2, COLOR.g, TIME);
	v_world = VERTEX;
	v_root_distance = distance(CAMERA_POSITION_WORLD, MODEL_MATRIX[3].xyz);
}

void fragment() {
	float t = foliage_palette_t(v_world, TIME, v_variation);
	t = clamp(t + v_palette_shift - v_interior * 0.15, 0.0, 1.0);
	vec3 base = texture(foliage_palette, vec2(t, 0.5)).rgb;

	// Written unconditionally, as in grass.gdshader: with the atlas unbound
	// `hint_default_white` gives alpha 1 and tone 1, so a solid canopy goes
	// through the same path fully opaque.
	vec4 sprite = texture(leaf_sprite_atlas, UV);
	ALPHA = sprite.a;
	ALPHA_SCISSOR_THRESHOLD = leaf_alpha_scissor;
	base *= mix(1.0, sprite.r, leaf_sprite_tone * float(leaf_sprite_mode));
	base *= 1.0 - v_interior * leaf_interior_darkening;
	ALBEDO = foliage_apply_distance_tint(base, v_world, CAMERA_POSITION_WORLD);

	// Same back-face correction as the grass: cull_disabled negates NORMAL on
	// back faces, which would light the far side of every card as if it faced
	// away from its clump.
	if (!FRONT_FACING) {
		NORMAL = -NORMAL;
	}

	ROUGHNESS = leaf_roughness;
	SPECULAR = 0.15;
	BACKLIGHT = vec3(leaf_translucency) * base;

	if (tree_impostor_fade(v_root_distance) > tree_dither(FRAGCOORD.xy)) {
		discard;
	}
	if (tree_bake_mode > 0) {
		EMISSION = tree_bake_mode == 1 ? ALBEDO : (INV_VIEW_MATRIX * vec4(NORMAL, 0.0)).xyz * 0.5 + 0.5;
		ALBEDO = vec3(0.0);
		BACKLIGHT = vec3(0.0);
		SPECULAR = 0.0;
	}
}
