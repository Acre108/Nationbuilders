shader_type sky;

// The SpacesOS skyscape.
//
// Base: a port of PlacesOS's skybox.ts, which painted a six-face canvas
// cubemap -- zenith-to-horizon gradient, a darker ground band, sparse stars and
// a soft sun disc. Drawn analytically here so the colours move with the clock.
// All colours arrive as uniforms from AtmosphereModel; the shader owns shape.
//
// On top, new in SpacesOS:
//   * a sunward horizon glow at dawn and dusk, and a cooler pink band opposite
//     (the "belt of Venus"), so the horizon is no longer one colour all round;
//   * two cloud layers: high cirrus wisps streaked along the wind, and a
//     cumulus deck lit from the sun's side with bright thin edges near the sun;
//   * the cumulus deck is the SAME field the ground takes its cloud shadows
//     from (atmosphere_clouds.gdshaderinc), so shadows sit under their clouds.
//
// No TIME anywhere: drift is integrated on the CPU and arrives as globals, so
// a change of wind speed changes the drift rate without a jump.

#include "res://atmosphere/shaders/atmosphere_clouds.gdshaderinc"

group_uniforms bands;
uniform vec3 sky_zenith : source_color = vec3(0.45, 0.55, 0.7);
uniform vec3 sky_horizon : source_color = vec3(0.85, 0.8, 0.72);
uniform vec3 sky_ground : source_color = vec3(0.25, 0.27, 0.28);
uniform float horizon_softness : hint_range(0.05, 1.0) = 0.35;
// PlacesOS drew its skybox at intensity 0.8.
uniform float sky_energy : hint_range(0.0, 4.0) = 0.8;

group_uniforms glow;
// 0..1: how much dawn/dusk glow there is (AtmosphereModel.Frame.twilight).
uniform float horizon_glow : hint_range(0.0, 1.0) = 0.0;
uniform vec3 glow_colour : source_color = vec3(1.0, 0.6, 0.36);
uniform vec3 belt_colour : source_color = vec3(0.82, 0.62, 0.68);

group_uniforms sun;
uniform vec3 sun_disc_colour : source_color = vec3(1.0, 0.91, 0.72);
uniform float sun_disc_size : hint_range(0.001, 0.1) = 0.018;
uniform float sun_glow : hint_range(0.0, 1.0) = 0.35;
// 1 when LIGHT0 is the moon: a fixed-brightness, smaller, softer-haloed disc.
uniform float moon_disc : hint_range(0.0, 1.0) = 0.0;

group_uniforms lightning;
// 0..1, set per frame by Lightning (already distance- and accessibility-scaled).
uniform float lightning_flash : hint_range(0.0, 1.0) = 0.0;
// Unit vector towards the strike, a little above the horizon.
uniform vec3 lightning_direction = vec3(0.0, 0.5, -0.86);
uniform vec3 lightning_colour : source_color = vec3(0.8, 0.86, 1.0);

group_uniforms stars;
uniform float star_amount : hint_range(0.0, 1.0) = 0.0;
// PlacesOS drew only 42-66 stars over the whole sky, so this is low on purpose.
uniform float star_density : hint_range(0.0, 0.05) = 0.006;
uniform float star_seed = 0.0;

group_uniforms clouds;
uniform vec3 cloud_lit : source_color = vec3(1.0);
uniform vec3 cloud_shade : source_color = vec3(0.6, 0.63, 0.68);
// How far towards the sun the cumulus looks for its own shadow, metres on the
// deck. Larger = broader shading across each cloud.
uniform float cloud_self_shadow_reach = 260.0;
// High streaky layer. 0 hides it.
uniform float cirrus_amount : hint_range(0.0, 1.0) = 0.5;
// Wind direction in XZ; cirrus streaks lie along it.
uniform vec2 cirrus_direction = vec2(1.0, 0.0);
uniform float cirrus_height = 7000.0;

float hash13(vec3 p) {
	p = fract(p * 0.1031);
	p += dot(p, p.zyx + 31.32);
	return fract((p.x + p.y) * p.z);
}

float star_field(vec3 dir) {
	vec3 cell = floor(dir * 90.0);
	float h = hash13(cell + star_seed);
	if (h > star_density) {
		return 0.0;
	}
	vec3 centre = (cell + vec3(hash13(cell + 1.7), hash13(cell + 5.3), hash13(cell + 9.1))) / 90.0;
	float d = length(normalize(centre) - dir) * 90.0;
	return smoothstep(0.35, 0.0, d) * (0.5 + 0.5 * hash13(cell + 3.3));
}

// Gradient bands plus the dawn/dusk glow. `toward` is 1 facing the sun's
// compass bearing and 0 facing away, regardless of height.
vec3 sky_colour(vec3 dir, float toward) {
	float y = dir.y;
	vec3 col;
	if (y >= 0.0) {
		col = mix(sky_horizon, sky_zenith, smoothstep(0.0, horizon_softness, y));
	} else {
		col = mix(sky_horizon, sky_ground, smoothstep(0.0, 0.12, -y));
	}
	float above = max(y, 0.0);
	// Sunward glow: strongest on the horizon under the sun, climbing a little
	// way up the sky. Below the horizon it fades fast into the ground band.
	float glow = pow(toward, 4.0) * exp(-above * 5.0) * smoothstep(-0.12, 0.0, y);
	col = mix(col, glow_colour, clamp(glow * horizon_glow, 0.0, 1.0) * 0.85);
	// Opposite the sun: a low cool-pink band.
	float belt = pow(1.0 - toward, 3.0) * exp(-abs(y - 0.06) * 16.0);
	col = mix(col, belt_colour, clamp(belt * horizon_glow * 0.45, 0.0, 1.0));
	return col;
}

void sky() {
	vec3 dir = EYEDIR;
	vec3 sun = normalize(atmosphere_sun_direction);
	vec2 dir_xz = length(dir.xz) > 1e-4 ? normalize(dir.xz) : vec2(0.0);
	vec2 sun_xz = length(sun.xz) > 1e-4 ? normalize(sun.xz) : vec2(0.0, 1.0);
	float toward = dot(dir_xz, sun_xz) * 0.5 + 0.5;
	float to_sun = max(dot(dir, sun), 0.0);

	vec3 col = sky_colour(dir, toward);

	if (dir.y > 0.0) {
		col += vec3(star_field(dir)) * star_amount * (1.0 - atmosphere_cloud_cover);
	}

	if (LIGHT0_ENABLED) {
		float d = dot(dir, LIGHT0_DIRECTION);
		float size = sun_disc_size * mix(1.0, 0.8, moon_disc);
		float disc = smoothstep(cos(size), cos(size * 0.6), d);
		float glow = pow(max(d, 0.0), mix(48.0, 160.0, moon_disc)) * sun_glow;
		float up = smoothstep(-0.02, 0.02, LIGHT0_DIRECTION.y);
		float strength = mix(min(LIGHT0_ENERGY, 1.5), 1.0, moon_disc);
		col += (sun_disc_colour * disc * mix(4.0, 2.2, moon_disc) + LIGHT0_COLOR * glow) * up * strength;
	}

	if (dir.y > 0.0) {
		// Both layers melt into the horizon haze rather than ending on a line.
		float fade = smoothstep(0.0, 0.16, dir.y);

		// --- Cirrus: high, thin, streaked along the wind. Drawn first: it is
		// behind the cumulus. Catches dawn/dusk colour hardest, as real high
		// cloud does -- it is still in sunlight after the ground is not.
		if (cirrus_amount > 0.001) {
			vec2 p = POSITION.xz + dir.xz / (dir.y + 0.04) * cirrus_height;
			vec2 w = length(cirrus_direction) > 1e-4 ? normalize(cirrus_direction) : vec2(1.0, 0.0);
			vec2 local = vec2(dot(p, w), dot(p, vec2(-w.y, w.x)));
			// Streaks four times longer than wide, and big: at this height a
			// small tile repeats many times across the sky and reads as a comb.
			vec2 uv = local / vec2(ATMOSPHERE_CLOUD_TILE * 10.0, ATMOSPHERE_CLOUD_TILE * 2.5) + atmosphere_cloud_offset * 0.6;
			// Warp by a broader sample so the streaks bend and vary in spacing.
			uv += (texture(atmosphere_cloud_noise, uv * 0.31 + 0.17).rg - 0.5) * 0.5;
			float n = texture(atmosphere_cloud_noise, uv).r;
			// Patchy: whole regions of the sky have none.
			float patch = smoothstep(0.42, 0.68, texture(atmosphere_cloud_noise, uv * 0.23 + 0.61).r);
			float wisps = smoothstep(0.55, 0.85, n) * patch * cirrus_amount;
			// Fade out well above the horizon, where the projection stretches
			// the texture into lines.
			float high = smoothstep(0.06, 0.35, dir.y);
			vec3 cirrus = mix(cloud_lit, glow_colour, horizon_glow * 0.75 * (0.4 + 0.6 * toward));
			col = mix(col, cirrus, wisps * 0.5 * high);
		}

		// --- Cumulus: the deck shared with the ground shadows.
		if (atmosphere_cloud_cover > 0.001) {
			vec2 deck = POSITION.xz + dir.xz / (dir.y + 0.06) * atmosphere_cloud_deck_height;
			float d = atmosphere_cloud_density(deck);
			if (d > 0.001) {
				// Fake volume: if there is more cloud between this point and
				// the sun, this point is in its own cloud's shadow.
				float d_sun = atmosphere_cloud_density(deck + sun_xz * cloud_self_shadow_reach);
				float lit = clamp(0.68 - (d_sun - d) * 1.6, 0.12, 1.0);
				vec3 cloud = mix(cloud_shade, cloud_lit, lit);
				// Warm undersides at dawn and dusk, strongest on the sun side.
				cloud = mix(cloud, glow_colour * max(cloud_lit.r, 0.4), horizon_glow * 0.45 * toward * (1.0 - lit * 0.5));
				// Silver lining: thin edges glow when you look near the sun.
				float rim = (1.0 - d) * pow(to_sun, 5.0);
				cloud += sun_disc_colour * rim * 1.4 * float(LIGHT0_ENABLED);
				col = mix(col, cloud, d * 0.94 * fade);
			}
		}
	}

	// Lightning: the whole sky lifts, strongest round the strike, where the
	// cloud base is lit from inside.
	if (lightning_flash > 0.0) {
		float toward_strike = max(dot(dir, normalize(lightning_direction)), 0.0);
		col += lightning_colour * lightning_flash * (0.25 + 1.4 * pow(toward_strike, 6.0)) * smoothstep(-0.1, 0.05, dir.y);
	}

	COLOR = col * sky_energy;
}
