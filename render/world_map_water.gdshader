shader_type spatial;
render_mode diffuse_lambert, specular_schlick_ggx;
#include "res://atmosphere/shaders/atmosphere_clouds.gdshaderinc"
global uniform float foliage_gust_scale;
#include "res://render/village_art.gdshaderinc"
uniform float map_water_glints = 0.55;
varying vec3 world_position;
void vertex() {
	world_position = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}
void fragment() {
	vec2 cell = floor(world_position.xz / vec2(0.85, 0.55));
	vec2 local = fract(world_position.xz / vec2(0.85, 0.55));
	float seed = fract(sin(dot(cell, vec2(127.1, 311.7))) * 43758.5453);
	float phase = village_environment_time * 0.20 + seed * 7.0;
	float event = pow(max(0.0, sin(phase)), 12.0) * step(0.91, seed);
	float line = (1.0 - smoothstep(0.0, 0.025 + fwidth(local.y), abs(local.y - 0.5)));
	line *= 1.0 - smoothstep(0.12, 0.20, abs(local.x - 0.5));
	float glint = event * line * map_water_glints * max(atmosphere_sun_direction.y, 0.0);
	float ripple = sin(world_position.x * 1.3 + world_position.z * 2.1 + village_environment_time * 0.3) * 0.012;
	ALBEDO = COLOR.rgb * (1.0 + ripple) * atmosphere_cloud_colour(world_position);
	EMISSION = vec3(0.45, 0.50, 0.30) * glint;
	ROUGHNESS = 0.85;
	SPECULAR = 0.08;
}
