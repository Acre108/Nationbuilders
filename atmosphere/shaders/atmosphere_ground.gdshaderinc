// How weather has left the ground: wet from rain, damp with dew.
//
// #included (via foliage_distance.gdshaderinc) by every foliage surface. The
// general darkening lives in foliage_apply_distance_tint(), so grass, flowers,
// trees and terrain darken together and the grass/terrain horizon handover
// still matches when wet. The soil-only effects -- gloss and puddles -- are in
// terrain.gdshader, because only the terrain knows where the ground is bare.
//
// atmosphere_wetness is a GLOBAL (project.godot [shader_globals]), integrated
// over time by AtmosphereSystem: it rises in rain, is topped up a little by
// mist as dew, and dries afterwards -- fastest in full sun. 0 with no
// AtmosphereSystem, and then nothing here does anything.

global uniform float atmosphere_wetness;

// Wet foliage and turf go a little darker and more saturated. Kept mild: it
// applies at every distance, so far terrain darkens in step with near grass.
const float ATMOSPHERE_WET_DARKENING = 0.16;

vec3 atmosphere_wet_albedo(vec3 albedo) {
	float w = atmosphere_wetness;
	vec3 darker = albedo * (1.0 - ATMOSPHERE_WET_DARKENING * w);
	// A touch more saturated: wet surfaces lose the grey film of dry dust.
	float grey = dot(darker, vec3(0.299, 0.587, 0.114));
	return mix(vec3(grey), darker, 1.0 + 0.15 * w);
}

// 0..1 puddle coverage on flat bare ground at a world position.
//
// `depth_noise` is any smooth 0..1 field; low values are hollows. Puddles
// appear only once the ground is properly soaked (wetness above ~0.35), then
// spread from the lowest hollows outward as it keeps raining. They drain the
// same way, deepest last, as wetness falls.
float atmosphere_puddle(float depth_noise, float bare, float slope) {
	float w = atmosphere_wetness;
	if (w <= 0.35 || bare <= 0.0) {
		return 0.0;
	}
	float level = mix(0.0, 0.45, smoothstep(0.35, 1.0, w));
	float water = 1.0 - smoothstep(level - 0.035, level, depth_noise);
	// Water only lies on the flat.
	float flat_ground = 1.0 - smoothstep(0.015, 0.06, slope);
	return water * bare * flat_ground;
}
