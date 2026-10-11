shader_type spatial;
render_mode diffuse_lambert, specular_schlick_ggx;

#include "res://atmosphere/shaders/atmosphere_clouds.gdshaderinc"
#include "res://atmosphere/shaders/atmosphere_ground.gdshaderinc"
global uniform float foliage_gust_scale;
#include "res://render/village_art.gdshaderinc"
uniform bool village_crop = false;
// 0 plain, 1 roof, 2 plaster, 3 timber door, 4 window.
uniform int village_surface_kind = 0;

varying vec3 world_position;
varying vec3 world_normal;
varying vec3 object_position;

float surface_hash(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }

void vertex() {
	world_position = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	object_position = VERTEX;
	world_normal = normalize(MODEL_NORMAL_MATRIX * NORMAL);
	if (village_crop) {
		vec2 bend = village_wind_direction * village_gust(world_position, TIME) * village_wind_strength;
		VERTEX.xz += bend * step(0.0, VERTEX.y);
		world_position = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	}
}

void fragment() {
	vec3 base = village_art_enabled ? village_colour_grade(COLOR.rgb, world_normal) : COLOR.rgb;
	if (village_surface_kind == 1) {
		// World-sized clay courses stagger across existing roof triangles.
		vec2 course = vec2(object_position.z / 0.30, (object_position.y + abs(object_position.x) * 0.18) / 0.19);
		course.x += mod(floor(course.y), 2.0) * 0.5;
		vec2 tile = fract(course);
		float seam = max(1.0-step(0.055,tile.x), 1.0-step(0.10,tile.y));
		float rim = step(0.86,tile.y);
		float tone = surface_hash(floor(course));
		base *= 1.0 + (tone-0.5) * 0.17 * village_surface_detail;
		base *= 1.0 - seam * village_surface_detail * 0.32;
		base += COLOR.rgb * rim * village_surface_detail * 0.12;
	} else if (village_surface_kind == 2) {
		vec2 wall = abs(world_normal.z) > 0.5 ? world_position.xy : world_position.zy;
		// A two-course stone foot and a few chips in otherwise quiet plaster.
		vec2 stone = vec2(wall.x / 0.23, world_position.y / 0.12);
		stone.x += mod(floor(stone.y),2.0) * 0.5;
		vec2 joint = fract(stone);
		float mortar = max(1.0-step(0.09,joint.x), 1.0-step(0.13,joint.y));
		vec3 foundation = vec3(0.23,0.20,0.14) * mix(0.75,1.20,surface_hash(floor(stone)));
		foundation *= 1.0-mortar*0.48;
		base = mix(base, foundation, step(world_position.y,0.32)*village_surface_detail);
		float chip = step(0.965,surface_hash(floor(wall*11.0)));
		base *= 1.0-chip*village_surface_detail*0.16;
	} else if (village_surface_kind == 3) {
		float joint = 1.0-step(0.09,fract(UV.x*5.0));
		base *= 1.0-joint*village_surface_detail*0.35;
	} else if (village_surface_kind == 4) {
		float frame = max(step(0.80,abs(UV.x*2.0-1.0)),step(0.80,abs(UV.y*2.0-1.0)));
		float mullion = max(1.0-step(0.08,abs(UV.x-0.5)),1.0-step(0.055,abs(UV.y-0.5)));
		base = mix(vec3(0.055,0.037,0.026),COLOR.rgb*0.55,max(frame,mullion));
	}
	ALBEDO = atmosphere_wet_albedo(base) * atmosphere_cloud_colour(world_position);
	ROUGHNESS = 0.9;
	SPECULAR = 0.08;
}
