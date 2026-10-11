// Shared colour + wind model for every foliage surface in the game.
//
// This file is #included by BOTH grass.gdshader and terrain.gdshader, and it is
// the reason the horizon handover works. Part 4 of the foliage brief requires
// that where grass streaming stops, the terrain underneath already looks like
// grass -- no visible "edge of the lawn" ring around the player. The only
// reliable way to get that is for both surfaces to run *literally the same
// colour code* off *literally the same uniform values*, so there is no drift to
// tune out. Anything that changes the look belongs in here, not in one shader.
//
// Godot's #include is textual, so the uniforms below are re-declared in each
// including shader. That is deliberate: it guarantees both materials expose an
// identical uniform set, and FoliageProfile.apply_to() pushes one set of values
// into both. If you add a uniform here, add it to FoliageProfile too or the two
// surfaces will silently disagree.

group_uniforms foliage_colour;
// Greyscale tiling noise, sampled in world space and then mapped through the
// palette. Kept separate from the wind noise so a location can have large soft
// colour patches with fast fine-grained wind, or vice versa.
uniform sampler2D foliage_colour_noise : hint_default_white, filter_linear_mipmap, repeat_enable;
// The palette IS the location's identity -- a 1D gradient from the darkest
// shadowed green to the lightest sun-bleached tip. Swap per location or season.
uniform sampler2D foliage_palette : source_color, hint_default_white, filter_linear, repeat_disable;
// World units per tile of colour noise. Larger = broader patches.
uniform float foliage_colour_noise_scale : hint_range(0.001, 1.0) = 0.035;
// Blend of a second, much broader noise octave. Stops the tiling from reading
// as a repeating stamp at distance, which is exactly where the terrain shader
// is doing the work.
uniform float foliage_colour_octave_mix : hint_range(0.0, 1.0) = 0.35;
// Remaps noise before the palette lookup, so a palette can be used at full
// range or squeezed into part of itself without editing the gradient.
uniform float foliage_palette_offset : hint_range(-1.0, 1.0) = 0.0;
uniform float foliage_palette_contrast : hint_range(0.1, 3.0) = 1.0;

group_uniforms foliage_wind;
uniform sampler2D foliage_wind_noise : hint_default_white, filter_linear_mipmap, repeat_enable;
// Direction the wind travels across the world, XZ. Normalised in the function,
// so it does not need to be a unit vector in the inspector.
uniform vec2 foliage_wind_direction = vec2(1.0, 0.35);
uniform float foliage_wind_speed : hint_range(0.0, 2.0) = 0.12;
// How far a full-weight vertex is pushed, in world units.
uniform float foliage_wind_strength : hint_range(0.0, 2.0) = 0.28;
// World units per tile of wind noise. The terrain sets this MUCH larger than
// the grass does, so distant fields show broad rolling gust waves instead of
// per-blade noise that would alias into shimmer at range.
uniform float foliage_wind_noise_scale : hint_range(0.0005, 0.5) = 0.02;
// How much a gust lightens/darkens what it passes over. This is what makes wind
// readable on the distant terrain, where there is no geometry left to bend.
uniform float foliage_wind_colour_shift : hint_range(0.0, 1.0) = 0.18;

// Weather's hold on the wind, set once per frame by AtmosphereSystem through
// RenderingServer.global_shader_parameter_set() (declared in project.godot).
// GLOBAL rather than per-material so the weather reaches grass, terrain, flowers
// and both tree styles at once without knowing any of their materials -- and
// so it cannot reach some and miss others. With no AtmosphereSystem in the
// scene they sit at their defaults (1 and 0) and change nothing.
//
// foliage_gust_scale multiplies the whole gust field: a storm bends grass
// further, sways trees harder AND sweeps more colour across distant terrain,
// all from one number, so near and far stay in agreement.
global uniform float foliage_gust_scale;
// Extra scroll, in wind-noise UV units, integrated on the CPU. A storm's faster
// gusts are added HERE rather than by raising foliage_wind_speed: the shader
// scrolls by time * speed, so changing speed mid-game jumps the whole field by
// (elapsed seconds * delta) -- a visible snap. Integrating the extra distance
// frame by frame changes the rate smoothly.
global uniform vec2 foliage_wind_scroll;

// Signed gust field at a world position, nominally -1..1 (wider when the
// weather's gust scale is above 1).
//
// Scrolling a seamless tiling noise along the wind direction is what makes
// gusts read as *travelling* rather than as the whole field pulsing in place.
float foliage_wind_field(vec3 world_pos, float time) {
	vec2 dir = normalize(foliage_wind_direction);
	vec2 uv = world_pos.xz * foliage_wind_noise_scale - dir * (time * foliage_wind_speed) - foliage_wind_scroll;
	return (texture(foliage_wind_noise, uv).r * 2.0 - 1.0) * foliage_gust_scale;
}

// Greyscale 0..1 driving the palette lookup at a world position.
//
// `far` (0..1) hands the fine octave over to the broad one. Its ~29 m tile
// repeats as a visible lattice across kilometres of horizon ground, where it
// is sub-pixel detail anyway. Only the terrain passes anything but 0, and
// only beyond any grass (from 250 m, terrain.gdshader), so grass and ground still agree
// wherever both exist.
float foliage_colour_field_far(vec3 world_pos, float far) {
	vec2 uv = world_pos.xz * foliage_colour_noise_scale;
	float fine = texture(foliage_colour_noise, uv).r;
	// 0.37 is deliberately not a round fraction -- an integer ratio would make
	// the two octaves line up periodically and reintroduce visible tiling.
	float broad_a = texture(foliage_colour_noise, uv * 0.37 + vec2(0.5)).r;
	// The broad octave is all that survives mipmapping at distance, and alone
	// it repeated every ~77 m in an axis-aligned grid, plain to see from a hill
	// once the horizon ring made kilometres of ground visible. So cross-fade
	// it with a second copy, rotated and at another scale, under a much
	// broader sample (a ~470 m tile), itself rotated. Neither copy's lattice
	// survives the blend. A warp was tried first: strong enough to hide the
	// grid, it made the ground look like marbled liquid.
	mat2 rotate = mat2(vec2(0.8, 0.6), vec2(-0.6, 0.8));
	float broad_b = texture(foliage_colour_noise, rotate * uv * 0.29 + vec2(0.21, 0.63)).r;
	float macro = texture(foliage_colour_noise, rotate * uv * 0.061).r;
	float broad = mix(broad_a, broad_b, smoothstep(0.3, 0.7, macro));
	return mix(mix(fine, broad, foliage_colour_octave_mix), broad, far);
}

float foliage_colour_field(vec3 world_pos) {
	return foliage_colour_field_far(world_pos, 0.0);
}

// How much per-instance jitter overrides the world colour field. Grass wants
// this low (neighbouring tufts should agree, so the field reads as one meadow);
// flowers want it high, so individual blooms differ instead of a whole patch
// coming out the same shade.
uniform float foliage_variation_weight : hint_range(0.0, 1.0) = 0.25;

// Palette coordinate at a world position, in 0..1.
//
// Split out from the colour lookup so a shader can sample TWO palettes at the
// same coordinate -- that is how a flower keeps a green stem and a coloured
// head while both react to the same wind and colour field.
//
// `variation` is per-instance noise (grass passes INSTANCE_CUSTOM here, terrain
// passes 0.5) so neighbouring tufts differ slightly without needing the colour
// noise to be high frequency enough to separate them, which would shimmer.
float foliage_palette_t_far(vec3 world_pos, float time, float variation, float far) {
	float t = foliage_colour_field_far(world_pos, far);
	t = mix(t, variation, foliage_variation_weight);
	// Gusts push the palette lookup, not the final RGB, so a gust always moves
	// colour ALONG the location's own gradient. Tinting the RGB directly would
	// let wind introduce hues the palette never contained.
	t += foliage_wind_field(world_pos, time) * foliage_wind_colour_shift;
	t = (t - 0.5) * foliage_palette_contrast + 0.5 + foliage_palette_offset;
	return clamp(t, 0.0, 1.0);
}

float foliage_palette_t(vec3 world_pos, float time, float variation) {
	return foliage_palette_t_far(world_pos, time, variation, 0.0);
}

// The full foliage colour at a world position, before lighting.
vec3 foliage_surface_colour(vec3 world_pos, float time, float variation) {
	return texture(foliage_palette, vec2(foliage_palette_t(world_pos, time, variation), 0.5)).rgb;
}

// Triplanar sample of the shared colour-noise texture: three world-space
// projections (XZ top-down, ZY and XY side-on), blended by how much the
// surface normal faces each axis. A flat top-down UV stretches without limit
// along a vertical face -- the whole point of doing this triplanar instead.
//
// There is no modelled rock texture anywhere in this game; every surface
// here reads the SAME shared noise through a palette instead of a painted
// material (see foliage_colour_field() above). This keeps that idiom for
// rock and cliffs, just projected on all three axes rather than flat XZ --
// currently used by terrain.gdshader for altitude/slope rock and snow, and
// available for anything else that wants texture on a steep or vertical
// surface (e.g. procedural debris/boulders) without inventing a second look.
//
// `scale` is world units per tile, the same convention as
// foliage_colour_noise_scale. The blend weights are raised to a power so
// each face reads mostly from its own dominant projection rather than a
// soft three-way blur across the whole surface; 4.0 keeps that sharp without
// a visible hard seam where two projections meet.
float foliage_triplanar_noise(vec3 world_pos, vec3 world_normal, float scale) {
	vec3 blend = pow(abs(world_normal), vec3(4.0));
	blend /= max(blend.x + blend.y + blend.z, 0.0001);
	float nx = texture(foliage_colour_noise, world_pos.zy * scale).r;
	float ny = texture(foliage_colour_noise, world_pos.xz * scale).r;
	float nz = texture(foliage_colour_noise, world_pos.xy * scale).r;
	return nx * blend.x + ny * blend.y + nz * blend.z;
}
