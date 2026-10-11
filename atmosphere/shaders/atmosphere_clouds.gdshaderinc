// The one cloud field: drawn by the sky, and cast as shadows on the ground.
//
// #included by atmosphere/shaders/sky.gdshader AND by
// foliage/shaders/foliage_distance.gdshaderinc (so terrain, grass, both tree
// styles and the impostors). Both sides evaluate the SAME density function off
// the SAME globals, which is what makes a shadow on the meadow sit exactly
// under the cloud that casts it, and drift with it.
//
// Everything is a GLOBAL uniform, set each frame by AtmosphereSystem, for the
// same reason the wind multipliers are (see foliage_common.gdshaderinc): one
// write reaches every material, and none can be missed. Declared in
// project.godot [shader_globals]. With no AtmosphereSystem in the scene,
// atmosphere_cloud_shadow is 0 and the ground pays one uniform branch, nothing
// more.
//
// Geometry: the clouds are a flat deck ATMOSPHERE_CLOUD_HEIGHT metres up. The
// sky finds the deck point along the view ray from the camera; the ground finds
// it along the ray towards the sun. Same deck, same noise, so they agree.

global uniform sampler2D atmosphere_cloud_noise : filter_linear_mipmap, repeat_enable;
// Drift, in noise tiles, integrated on the CPU along the foliage wind.
global uniform vec2 atmosphere_cloud_offset;
// 0 clear .. 1 overcast.
global uniform float atmosphere_cloud_cover;
// How dark a full cloud shadow is on the ground. 0 = no shadows at all (also
// the value with no atmosphere, at night and indoors).
global uniform float atmosphere_cloud_shadow;
// Unit vector TOWARDS the sun, world space.
global uniform vec3 atmosphere_sun_direction;

const float ATMOSPHERE_CLOUD_HEIGHT = 1200.0;
// World metres per noise tile at the deck. The noise has features about a
// quarter of a tile across, so clouds come out a few hundred metres wide.
const float ATMOSPHERE_CLOUD_TILE = 3200.0;
// Per-material scale lets the compact village share the sky field at metres,
// while imported landscapes retain the original kilometre-scale deck.
uniform float atmosphere_cloud_tile_size = 3200.0;
uniform float atmosphere_cloud_deck_height = 1200.0;
uniform float atmosphere_cloud_bands = 0.0;
uniform vec3 atmosphere_cloud_tint : source_color = vec3(1.0);

// Cumulus density 0..1 at a point on the deck, world XZ metres.
float atmosphere_cloud_density(vec2 deck_xz) {
	vec2 uv = deck_xz / atmosphere_cloud_tile_size + atmosphere_cloud_offset;
	float n = texture(atmosphere_cloud_noise, uv).r * 0.6
		+ texture(atmosphere_cloud_noise, uv * 2.3 + 0.37).r * 0.4;
	// simulated-clouds.ts shaping (PlacesOS), with the threshold slid by cover.
	float threshold = mix(0.72, 0.18, atmosphere_cloud_cover);
	float c = clamp((n - threshold) / 0.34, 0.0, 1.0);
	c = c * c * (3.0 - 2.0 * c);
	return atmosphere_cloud_bands > 0.0 ? floor(c * atmosphere_cloud_bands + 0.5) / atmosphere_cloud_bands : c;
}

// Where the ray from `world_pos` towards the sun meets the deck.
vec2 atmosphere_sun_deck_point(vec3 world_pos) {
	vec3 sun = normalize(atmosphere_sun_direction);
	// Clamp so a sun on the horizon does not throw the lookup to infinity; the
	// shadow strength is already near zero by then.
	float up = max(sun.y, 0.08);
	return world_pos.xz + sun.xz / up * (atmosphere_cloud_deck_height - world_pos.y);
}


// Multiplier for a surface's albedo: 1 in sunlight, lower under a cloud.
//
// Applied to albedo, not to the sun's light alone -- the foliage shaders use
// Godot's built-in lighting and have no light() function to hook -- so a
// shadow also dims a little of the ambient. At the strengths used that reads
// as a cloud shadow, and it keeps every foliage surface on one code path.
float atmosphere_cloud_shade(vec3 world_pos) {
	if (atmosphere_cloud_shadow <= 0.0) {
		return 1.0;
	}
	return 1.0 - atmosphere_cloud_density(atmosphere_sun_deck_point(world_pos)) * atmosphere_cloud_shadow;
}

vec3 atmosphere_cloud_colour(vec3 world_pos) {
	float shade = atmosphere_cloud_shade(world_pos);
	return shade * mix(vec3(1.0), atmosphere_cloud_tint, (1.0 - shade) * 2.0);
}
