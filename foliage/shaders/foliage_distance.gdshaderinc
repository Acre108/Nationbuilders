// Distance tint: every foliage surface -- terrain, grass, trees, impostors --
// eases towards the location's distance tint with range, the same way.
//
// This is the painterly half of the horizon handover. Grass geometry ends,
// full trees become impostors, ground drops to coarse meshes -- and each of
// those boundaries is easier to miss when everything out there has already
// cooled towards the sky by the same amount at the same distance. Applied to
// ALBEDO, so it is lit like the surface: a stylised aerial perspective, not a
// replacement for the environment's fog (which still applies on top).
//
// Kept out of foliage_common.gdshaderinc on purpose: that file is shared with
// the atmosphere system, and this has no business in the colour/wind model.
// Its uniforms are set in FoliageProfile._apply_shared() like the rest, so
// every surface gets identical values.

// Live weather rides along here -- cloud shadows and wetness -- because this
// is the one function every foliage surface already runs last on its albedo.
// See atmosphere/shaders/atmosphere_clouds.gdshaderinc and
// atmosphere_ground.gdshaderinc.
#include "res://atmosphere/shaders/atmosphere_clouds.gdshaderinc"
#include "res://atmosphere/shaders/atmosphere_ground.gdshaderinc"

group_uniforms foliage_distance;
// 1 on live surfaces. TreeImpostorBaker sets 0 on its bake copies: cloud
// shadow and wetness at the moment of the bake would otherwise be painted into
// every impostor for the rest of the session.
uniform float foliage_live_weather_weight : hint_range(0.0, 1.0) = 1.0;
uniform vec3 foliage_distance_tint : source_color = vec3(0.68, 0.75, 0.79);
uniform float foliage_distance_tint_strength : hint_range(0.0, 1.0) = 0.0;
uniform float foliage_distance_tint_start = 80.0;
uniform float foliage_distance_tint_end = 700.0;

vec3 foliage_apply_distance_tint(vec3 albedo, vec3 world_pos, vec3 camera_pos) {
	// Shadow first, then the tint: far away, both shadow and sun fade into the
	// same haze, as they would through real air.
	albedo = mix(albedo, atmosphere_wet_albedo(albedo), foliage_live_weather_weight);
	albedo *= mix(vec3(1.0), atmosphere_cloud_colour(world_pos), foliage_live_weather_weight);
	float t = smoothstep(foliage_distance_tint_start, foliage_distance_tint_end, distance(world_pos, camera_pos));
	return mix(albedo, foliage_distance_tint, t * foliage_distance_tint_strength);
}
