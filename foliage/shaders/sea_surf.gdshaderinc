// Surf on a real coastline (docs/SEA_PLAN.md, SEA5). Shared by the sea
// (water.gdshader: the near patch's wave geometry, and every sea pixel's wave
// normals and foam) and the ground (terrain.gdshader: swash on the beach), so
// the breaking line, its foam and the swash running up the sand come from
// one wave and stay in step.
//
// Wave fronts follow the coast field (ImportedSea.coast_texture(): the
// signed distance to the mean-sea-level shoreline, smoothed, and the
// direction surf travels), so crests run parallel to the shore and travel
// in: phase = 2 pi (distance / wavelength + time / period). Height shoals by
// Green's law, H = H0 (h_ref / h)^(1/4), and is capped at the breaking
// ratio, H <= 0.78 h, against the LIVE depth -- so the surf zone moves with
// the tide by itself. Where Green's law passes the cap the wave is breaking:
// its crest sharpens and foams. Sea state: SurfSettings' calm height,
// raised by the storm through foliage_gust_scale (1 clear .. 2 storm), the
// same global that bends the grass. Off (surf_enabled false) without a coast
// field. Stylised on purpose: one wave train, no spectrum, no refraction
// beyond what the coast field's shape gives.
//
// The including shader must declare `global uniform float
// foliage_gust_scale;` (foliage_common.gdshaderinc does).

uniform bool surf_enabled = false;
// RGB float: R signed distance to the shoreline (m, + offshore), GB the
// world XZ direction surf travels. Same (x, z, width, depth) bounds layout
// as the sea's other maps.
uniform sampler2D surf_coast : hint_default_black, filter_linear, repeat_disable;
uniform vec4 surf_coast_bounds = vec4(-12000.0, -12000.0, 24000.0, 24000.0);
// The coast texture's B is north; world Z is north times this
// (ImportedSea.coast_z_sign: -1 where north is -Z).
uniform float surf_coast_z_sign = -1.0;
// WaterProfile surf_*: deep-water height in calm weather (m), its gain at
// full storm (H0 x (1 + gain)), period (s), wavelength (m), the depth the
// height is quoted at, how far offshore surf is drawn (m), and the swash's
// run-up as a fraction of the wave height.
uniform float surf_height = 0.35;
uniform float surf_storm_gain = 3.0;
uniform float surf_period = 8.0;
uniform float surf_wavelength = 36.0;
uniform float surf_reference_depth = 8.0;
uniform float surf_range = 700.0;
uniform float surf_runup = 0.7;

const float SURF_BREAKING = 0.78;
const float SURF_TAU = 6.28318530718;
// Swash runs up the beach from the water: it fades out from a third of this
// to this many metres inland of the mean-sea-level coastline.
const float SURF_SWASH_INLAND = 60.0;

// R signed distance, GB direction; distance far offshore off the map.
vec3 surf_coast_at(vec2 xz) {
	vec2 uv = (xz - surf_coast_bounds.xy) / surf_coast_bounds.zw;
	if (any(lessThan(uv, vec2(0.0))) || any(greaterThan(uv, vec2(1.0)))) {
		return vec3(1.0e6, 1.0, 0.0);
	}
	vec3 c = texture(surf_coast, uv).rgb;
	return vec3(c.r, c.g, c.b * surf_coast_z_sign);
}

// Offshore wave height now: calm, raised by the storm.
float surf_sea_height() {
	return surf_height * (1.0 + surf_storm_gain * clamp(foliage_gust_scale - 1.0, 0.0, 1.0));
}

// Along-shore coordinate (m), for the wave's sets and crest wiggle.
float surf_along(vec2 xz, vec2 dir) {
	return dot(xz, vec2(-dir.y, dir.x));
}

// Wave phase (radians) at a coast point: crests move down the distance.
float surf_phase(vec3 coast, vec2 xz, float time) {
	float along = surf_along(xz, normalize(coast.gb + vec2(1.0e-5, 0.0)));
	return SURF_TAU * (coast.r / surf_wavelength + time / surf_period) + 0.9 * sin(along * 0.011);
}

// Sets: groups of bigger waves, varying along the shore and slowly in time.
float surf_sets(vec2 xz, vec2 dir, float time) {
	float along = surf_along(xz, dir);
	return 0.7 + 0.3 * sin(along * 0.009 + time * 0.07) * sin(along * 0.0037 - time * 0.031 + 1.3);
}

// The wave over `depth` metres of water at `xz`, in two parts that share one
// coast lookup and one Green's law (surf_both() for a pixel that needs
// both):
//   wave  = (height about the still level, d height / dx, d height / dz,
//            breaking 0..1);
//   shade = (crest foam, trailing whitewater, wave face, surf presence),
//            each 0..1.
// All zero on dry ground, beyond surf_range, or off.
//
// The wave is a peaked crest over broad troughs, steeper once breaking,
// centred so the mean water level stays put. Of the shade: the crest foam
// is a crisp line along a breaking crest; the whitewater trails seawards of
// it, thinning (the caller breaks it up with lace), and the further past
// breaking a wave is (Green's law over the cap: the inner surf zone, a
// storm) the longer the trail -- an inner surf zone in a storm is mostly
// white; the face is the steep shoreward side of every wave that has
// shoaled to a visible height, drawn darker and more opaque so the waves
// read against the sky's reflection; presence is how much of a wave there
// is at all, for damping the wind ripple under the surf.
void surf_both(vec2 xz, float depth, float time, bool with_shade, out vec4 wave, out vec4 shade) {
	wave = vec4(0.0);
	shade = vec4(0.0);
	if (!surf_enabled || depth <= 0.0) {
		return;
	}
	vec3 coast = surf_coast_at(xz);
	if (coast.r > surf_range || coast.r < -surf_range) {
		return;
	}
	vec2 dir = normalize(coast.gb + vec2(1.0e-5, 0.0));
	float h0 = surf_sea_height() * surf_sets(xz, dir, time);
	float green = h0 * pow(surf_reference_depth / max(depth, 0.05), 0.25);
	float cap = SURF_BREAKING * depth;
	float over = green / max(cap, 0.001);
	float height = min(green, cap);
	float breaking = smoothstep(0.85, 1.15, over);
	float fade = 1.0 - smoothstep(surf_range * 0.6, surf_range, coast.r);
	float phase = surf_phase(coast, xz, time);
	float c01 = 0.5 + 0.5 * cos(phase);
	float sharp = mix(1.6, 4.0, breaking);
	float lead = pow(max(c01, 1.0e-4), sharp - 1.0);
	float shape = lead * c01;
	float mean = mix(0.37, 0.24, breaking);
	float d_shape = sharp * lead * (-0.5 * sin(phase));
	// d phase / d xz = (2 pi / L) * grad(distance) = -(2 pi / L) * dir.
	vec2 slope = height * d_shape * (-SURF_TAU / surf_wavelength) * dir;
	wave = vec4(height * (shape - mean), slope, breaking) * fade;
	if (!with_shade) {
		return;
	}
	// Position in the cycle: 0 on the crest, negative shorewards of it
	// (crests travel down the distance), positive seawards.
	float u = fract(phase / SURF_TAU + 0.5) - 0.5;
	float crest = breaking * (1.0 - smoothstep(0.012, 0.045, abs(u + 0.01)));
	float bore = smoothstep(1.2, 2.5, over);
	float trail = breaking * smoothstep(0.0, 0.03, u) * (1.0 - smoothstep(0.04, mix(0.3, 0.75, bore), u));
	trail = max(trail, breaking * bore * 0.55);
	float face = smoothstep(0.08, 0.5, height) * smoothstep(-0.2, -0.06, u) * (1.0 - smoothstep(-0.03, 0.0, u));
	shade = vec4(crest, trail, face, smoothstep(0.1, 0.6, height)) * fade;
}

// The wave alone (see surf_both()), for the surf patch's vertices.
vec4 surf_wave(vec2 xz, float depth, float time) {
	vec4 wave;
	vec4 shade;
	surf_both(xz, depth, time, false, wave, shade);
	return wave;
}

// The swash on a beach `above` metres over the live level at `xz`: (film
// 0..1, foam line 0..1). The front climbs fast and draws back slowly, once
// a wave, reaching surf_runup x the breaking wave's height at most.
vec2 surf_swash(vec2 xz, float above, float time) {
	if (!surf_enabled || above < 0.0) {
		return vec2(0.0);
	}
	vec3 coast = surf_coast_at(xz);
	// Only on the shore itself: low ground further inland (a hollow in the
	// upper beach) is within the run-up's height but no wave reaches it.
	if (coast.r > surf_range || coast.r < -SURF_SWASH_INLAND) {
		return vec2(0.0);
	}
	float shore = smoothstep(-SURF_SWASH_INLAND, -SURF_SWASH_INLAND * 0.33, coast.r);
	vec2 dir = normalize(coast.gb + vec2(1.0e-5, 0.0));
	float reach = surf_runup * surf_sea_height() * surf_sets(xz, dir, time);
	if (above > reach) {
		return vec2(0.0);
	}
	float u = fract(surf_phase(coast, xz, time) / SURF_TAU);
	float front = reach * (u < 0.22 ? smoothstep(0.0, 0.22, u) : 1.0 - smoothstep(0.22, 1.0, u));
	float film = (1.0 - smoothstep(front - 0.02, front + 0.01, above)) * (1.0 - 0.5 * above / max(reach, 0.001));
	float line = (1.0 - smoothstep(0.0, 0.035, abs(above - front))) * smoothstep(0.02, 0.1, front) * step(u, 0.6);
	return vec2(film, line) * shore;
}
