shader_type spatial;

// Rocks, logs and fallen trees: solid, static geometry. No wind (they do not
// sway), no foliage palette (colour is baked per vertex by DebrisBuilder, not
// looked up), no impostor handover (see DebrisLayer's class comment for why).
// The one thing debris shares with every other foliage surface is the
// horizon handover: it eases towards the location's distance tint exactly
// like grass, terrain and trees, so it does not stand out as the one thing
// out there that stays saturated at range.
render_mode world_vertex_coords;

#include "res://foliage/shaders/foliage_distance.gdshaderinc"

group_uniforms debris;
uniform float debris_roughness : hint_range(0.0, 1.0) = 0.9;
uniform float debris_specular : hint_range(0.0, 1.0) = 0.08;

varying vec3 v_world;

void vertex() {
	v_world = VERTEX;
}

void fragment() {
	ALBEDO = foliage_apply_distance_tint(COLOR.rgb, v_world, CAMERA_POSITION_WORLD);
	ROUGHNESS = debris_roughness;
	SPECULAR = debris_specular;
}
