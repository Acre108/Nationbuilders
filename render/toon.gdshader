shader_type spatial;
render_mode diffuse_lambert, specular_disabled;
#include "res://atmosphere/shaders/atmosphere_clouds.gdshaderinc"
#include "res://atmosphere/shaders/atmosphere_ground.gdshaderinc"
varying vec3 world_position;
void vertex() {
	world_position = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}
void fragment() {
	ALBEDO = atmosphere_wet_albedo(COLOR.rgb) * atmosphere_cloud_shade(world_position);
	ROUGHNESS = 1.0;
}
void light() {
	float shade = dot(NORMAL, LIGHT);
	float band = shade > 0.65 ? 1.0 : (shade > 0.1 ? 0.72 : 0.40);
	float illumination = band * ATTENUATION;
	// Dither only actual cast shadows and the darkest lighting band.
	if (ATTENUATION < 0.7 || shade <= 0.1) {
		float checker = mod(floor(FRAGCOORD.x) + floor(FRAGCOORD.y), 2.0) - 0.5;
		illumination = max(0.0, illumination + checker * 0.065);
	}
	DIFFUSE_LIGHT += ALBEDO * LIGHT_COLOR * illumination / 3.14159265;
}
