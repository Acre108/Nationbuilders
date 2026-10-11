// Opt-in village pass. Imported location materials keep their authored look.
uniform bool village_art_enabled = false;
uniform float village_grade = 0.32;
uniform float village_forest_darkness = 0.68;
uniform float village_surface_detail = 0.65;
uniform float village_canopy_highlights = 0.75;
uniform float village_canopy_fullness = 0.65;
uniform float village_canopy_readability = 0.65;
uniform float village_wind_strength = 0.16;
uniform vec2 village_wind_direction = vec2(1.0, 0.35);
uniform float village_wind_speed = 0.028;
global uniform float village_environment_time;
global uniform float village_wind_time;

// A continuous breeze with broad travelling gust fronts. All vegetation
// samples this field at its root, on the same weather-scaled clock.
float village_gust(vec3 p, float time) {
	time = village_wind_time;
	vec2 dir = normalize(village_wind_direction);
	float phase = dot(p.xz, dir) * 0.23 - time * village_wind_speed * 12.0;
	float front = pow(max(0.0, sin(phase)), 2.0);
	float envelope = 0.75 + 0.25 * sin(time * 0.17);
	float breeze = 0.22 + 0.08 * sin(phase * 0.65);
	return (breeze + front * envelope * 0.75) * foliage_gust_scale;
}

// Material hue stays intact. Broad lighting temperature separates warm
// highlights from cool shade, rather than boosting saturation globally.
vec3 village_colour_grade(vec3 base, vec3 normal) {
	float facing = max(0.0, dot(normalize(normal), normalize(atmosphere_sun_direction)));
	vec3 temperature = mix(vec3(0.77, 0.91, 1.08), vec3(1.10, 1.02, 0.82), facing);
	return base * mix(vec3(1.0), temperature, village_grade);
}
