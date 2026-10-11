shader_type spatial;
render_mode diffuse_lambert;
#include "res://atmosphere/shaders/atmosphere_clouds.gdshaderinc"
#include "res://atmosphere/shaders/atmosphere_ground.gdshaderinc"
global uniform float foliage_gust_scale;
#include "res://render/village_art.gdshaderinc"
uniform sampler2D ground_context : filter_nearest, repeat_disable;
uniform vec2 ground_world_size = vec2(40.0);
uniform float ao_strength = 0.75;
uniform float water_glints = 0.35;
varying vec3 world_position;
// TerrainRelief flags: x = water surface, y = vertical face (cliff, bank, edge).
varying vec2 surface_flags;

void vertex() {
	world_position = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	surface_flags = UV;
}

void fragment() {
	vec3 base = COLOR.rgb;
	// Flat legacy meshes carry no flags: water is whatever sits below the ground.
	bool water = surface_flags.x > 0.5 || (surface_flags.y < 0.5 && world_position.y < -0.04);
	vec4 context = texture(ground_context, world_position.xz / ground_world_size);
	if (!water) {
		// Narrow dark contact, then broader cool grass/soil around structures.
		base = mix(base, base * vec3(0.60, 0.76, 0.78), context.g * 0.6);
		base *= 1.0 - context.r * ao_strength * 0.68;
		// Short pigment strokes exist only inside the authored detail patches.
		vec2 stroke_cell = floor(world_position.xz * 9.0);
		float stroke_seed = fract(sin(dot(stroke_cell,vec2(12.9898,78.233)))*43758.5453);
		float stroke = step(0.78,stroke_seed) * step(fract(world_position.z*9.0),0.28);
		base *= 1.0 + (stroke_seed > 0.90 ? 0.22 : -0.18) * stroke * context.a * village_surface_detail;
		// Sparse quantised canopy dapples: most forest floor remains dark.
		vec2 p = floor(world_position.xz * 4.0);
		float dapple = step(0.96, fract(sin(dot(p, vec2(12.9898, 78.233))) * 43758.5453));
		base += vec3(0.035, 0.040, 0.009) * dapple * context.b * village_gust(world_position, TIME) * min(1.0, village_wind_strength * 10.0);
	}
	ALBEDO = atmosphere_wet_albedo(village_colour_grade(base, vec3(0.0, 1.0, 0.0))) * atmosphere_cloud_colour(world_position);
	ROUGHNESS = 0.95;
	SPECULAR = 0.05;
	if (water) {
		float shore_break = step(0.32,fract(sin(floor(world_position.z*10.0)*17.13)*4217.3));
		ALBEDO = mix(ALBEDO,vec3(0.30,0.46,0.40),context.b*shore_break*0.75);
		// Three-to-five native pixel horizontal glints, with stepped lifetimes.
		vec2 plane = vec2(dot(world_position, INV_VIEW_MATRIX[0].xyz), dot(world_position, INV_VIEW_MATRIX[1].xyz)) * 16.0;
		vec2 cell = floor(plane / vec2(23.0, 13.0));
		float seed = fract(sin(dot(cell, vec2(17.13, 91.71))) * 4217.3);
		float life = fract(TIME * 0.10 + seed);
		float live = step(1.0 - water_glints * 0.38, seed) * step(0.24, life) * step(life, 0.62);
		vec2 pixel = mod(floor(plane), vec2(23.0, 13.0));
		float line = step(9.0, pixel.x) * step(pixel.x, 13.0) * step(6.0, pixel.y) * step(pixel.y, 6.0);
		EMISSION = vec3(0.90, 0.65, 0.24) * live * line * max(0.0, atmosphere_sun_direction.y) * atmosphere_cloud_shade(world_position);
	}
}
