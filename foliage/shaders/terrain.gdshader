shader_type spatial;

// The far half of the horizon handover. Beyond grass streaming range there is
// no grass geometry at all, so this shader has to BE the grass: same include,
// same uniforms, same palette. See foliage_common.gdshaderinc.
render_mode world_vertex_coords;

#include "res://foliage/shaders/foliage_common.gdshaderinc"
#include "res://foliage/shaders/foliage_distance.gdshaderinc"
// Swash (SEA5): the surf's run-up on the beach, from the sea's own wave.
#include "res://foliage/shaders/sea_surf.gdshaderinc"

group_uniforms terrain;
// Blended in on steep faces so cliffs and cut banks do not read as vertical
// lawn. Slope is the one place terrain legitimately stops looking like grass.
uniform vec3 terrain_slope_colour : source_color = vec3(0.42, 0.36, 0.28);
uniform float terrain_slope_begin : hint_range(0.0, 1.0) = 0.55;
uniform float terrain_slope_end : hint_range(0.0, 1.0) = 0.8;
uniform float terrain_roughness : hint_range(0.0, 1.0) = 0.95;
// The location's painted growth mask (FoliageProfile.growth_mask), the same
// one the placers read. Where it says "no grass" the ground has to stop
// looking like grass too, or a path reads as mown lawn instead of a path.
uniform sampler2D terrain_growth_mask : hint_default_white, filter_linear, repeat_disable;
// World XZ rectangle the mask covers: (x, z, width, depth).
uniform vec4 terrain_mask_bounds = vec4(-1000.0, -1000.0, 2000.0, 2000.0);
uniform vec3 terrain_bare_colour : source_color = vec3(0.45, 0.38, 0.28);
// Optional normalized land cover, independent of the editable painted mask.
uniform bool terrain_has_site_mask = false;
uniform sampler2D terrain_site_mask : filter_linear, repeat_disable;
// A partial imported site (ImportedSite.is_partial(): 4 km of detail inside an
// 8 km crop): observed data fades out over terrain_site_fade metres inside its
// edge (half-size terrain_site_half). 0 = the site covers the crop.
uniform float terrain_site_fade = 0.0;
// Coastal and heath habitats (ImportedSite habitat mask, same bounds as the
// site mask): R dune grassland, G heath, B open sand or beach. Ground colours
// are the DUNE and HEATH recipes' ground tints (rgb, strength); open sand
// takes the dune tint at full strength.
uniform bool terrain_has_habitats = false;
uniform sampler2D terrain_habitat_mask : hint_default_black, filter_linear, repeat_disable;
uniform vec4 terrain_dune_ground = vec4(0.66, 0.61, 0.48, 0.0);
uniform vec4 terrain_heath_ground = vec4(0.30, 0.24, 0.20, 0.0);
uniform float terrain_site_half = 1.0e9;

// ImportedSite.coverage(): 1 inside the site, 0 beyond a partial site.
float site_coverage(vec2 xz) {
	if (terrain_site_fade <= 0.0) {
		return 1.0;
	}
	return smoothstep(0.0, terrain_site_fade, terrain_site_half - max(abs(xz.x), abs(xz.y)));
}

// Close-range detail: fine colour breakup and a detail normal, so the ground
// between clumps reads as dense turf rather than a smooth painted plane. Fades
// out by terrain_detail_distance, where nobody can resolve it and it would
// only alias. No geometry, no extra draw calls.
uniform float terrain_detail_strength : hint_range(0.0, 1.0) = 0.6;
// Detail features per metre.
uniform float terrain_detail_scale : hint_range(0.1, 8.0) = 3.0;
uniform float terrain_detail_distance = 40.0;
// Close up, ground that grass grows on sits darker than the grass itself, as
// if in its shade. Ground lighter than the blades above it is what makes the
// gaps between clumps read as flat pale sheets. Fades with the detail, so far
// terrain still matches the grass colour for the horizon handover.
uniform float terrain_under_grass_shade : hint_range(0.0, 1.0) = 0.3;
// Wet weather (atmosphere_ground.gdshaderinc). Bare soil soaks darker than
// turf and turns glossy; puddles collect in its flat hollows and reflect the
// sky. 0 disables puddles for a location (sandy ground that drains).
uniform float terrain_wet_soil_darkening : hint_range(0.0, 1.0) = 0.4;
uniform float terrain_puddle_amount : hint_range(0.0, 1.0) = 1.0;
// Puddle hollows per metre: larger = more, smaller puddles.
uniform float terrain_puddle_scale : hint_range(0.005, 0.5) = 0.05;

// Altitude (TerrainProfile, pushed by apply_to_terrain_material()). Same
// formulas as TerrainProfile.altitude_rock() / altitude_snow(), which the
// grass and tree placers use, so growth stops exactly where the ground turns.
// Deliberately NOT part of `bare` below: puddles are gated on `bare`, and
// they have no business on a mountainside or a snowfield.
uniform float terrain_rock_line = 5000.0;
uniform float terrain_snow_line = 6000.0;
uniform float terrain_altitude_band = 40.0;
uniform vec3 terrain_snow_colour : source_color = vec3(0.91, 0.93, 0.95);
// Triplanar break-up for both rock targets below (slope AND altitude rock
// share one texture, since they are the same material). See
// foliage_triplanar_noise() in foliage_common.gdshaderinc for why this is
// triplanar noise rather than a modelled rock texture.
uniform float terrain_rock_scale : hint_range(0.05, 4.0) = 0.35;
uniform float terrain_rock_facet_strength : hint_range(0.0, 1.0) = 0.4;

// Shoreline (WaterProfile.apply_to_terrain_material(), W2 of the water
// system). Same smoothstep-banded formula as WaterProfile.water_mask(), so
// grass stops growing exactly where the ground here reads as underwater --
// the same "one formula, two places" rule altitude uses above.
// terrain_water_level sits at WaterProfile.OFF_HEIGHT (far below any real
// sea_level) when a location has no water, so both terms below are then 0
// everywhere and this is a no-op.
uniform float terrain_water_level = -100000.0;
uniform float terrain_shore_band : hint_range(0.05, 20.0) = 1.0;
// A real coastline (ImportedSea): the band above applies only within the
// sea's reach, so ground below sea level behind the shore (polders) stays dry
// land. Off: everywhere is in reach, as before.
uniform bool terrain_sea_masked = false;
uniform sampler2D terrain_sea_reach : hint_default_white, filter_linear, repeat_disable;
uniform vec4 terrain_sea_bounds = vec4(-12000.0, -12000.0, 24000.0, 24000.0);
// The near grid's reach (SEA6): as water.gdshader's water_sea_reach_at().
uniform bool terrain_sea_near = false;
uniform sampler2D terrain_sea_near_reach : hint_default_white, filter_linear, repeat_disable;
uniform bool terrain_sea_spill_on = false;
uniform sampler2D terrain_sea_spill : hint_default_black, filter_linear, repeat_disable;
uniform bool terrain_sea_near_spill_on = false;
uniform sampler2D terrain_sea_near_spill : hint_default_black, filter_linear, repeat_disable;
uniform vec4 terrain_sea_near_bounds = vec4(-4200.0, -4200.0, 8400.0, 8400.0);
uniform float terrain_sea_near_fade = 100.0;

// A tidal sea (SeaState, SEA4 of docs/SEA_PLAN.md). The foreshore -- in
// reach, below high water (WaterProfile.sea_high_water(), the level the
// growth mask bands around) -- takes the foreshore colour, mapped sand
// excepted, whatever the live level. Ground the tide has left keeps a wet
// sheen that fades over terrain_wet_sand_hours: terrain_tide_history[k] is
// the highest level over the last k * terrain_tide_history_step hours
// ([0] = the live level). Off without a tide.
uniform bool terrain_sea_tidal = false;
uniform float terrain_sea_high_water = -100000.0;
uniform vec3 terrain_foreshore_colour : source_color = vec3(0.64, 0.58, 0.47);
uniform float terrain_tide_history[9];
uniform float terrain_tide_history_step = 0.5;
uniform float terrain_wet_sand_hours = 3.0;

// Hours since ground at height y was last under the sea: 0 when it is now,
// 1e6 when not within the history. SeaState.hours_since_covered().
float tide_hours_since_covered(float y) {
	float prev = terrain_tide_history[0];
	if (y <= prev) {
		return 0.0;
	}
	for (int k = 1; k < 9; k++) {
		float m = terrain_tide_history[k];
		if (m >= y) {
			return (float(k - 1) + (y - prev) / max(m - prev, 0.0001)) * terrain_tide_history_step;
		}
		prev = m;
	}
	return 1.0e6;
}

// As water.gdshader's water_sea_reach_at(), in two halves so a pixel reads
// the textures once and gates them at two levels: (reach, spill) here, and
// sea_gate() below -- the reach, where `level` tops the spill height.
vec2 sea_reach_spill(vec2 xz) {
	if (!terrain_sea_masked) {
		return vec2(1.0, -10000.0);
	}
	vec2 uv = (xz - terrain_sea_bounds.xy) / terrain_sea_bounds.zw;
	vec2 rs = vec2(texture(terrain_sea_reach, uv).r, terrain_sea_spill_on ? texture(terrain_sea_spill, uv).r : -10000.0);
	if (terrain_sea_near) {
		vec2 half_size = terrain_sea_near_bounds.zw * 0.5;
		vec2 centre = terrain_sea_near_bounds.xy + half_size;
		float cover = clamp((half_size.x - max(abs(xz.x - centre.x), abs(xz.y - centre.y))) / terrain_sea_near_fade, 0.0, 1.0);
		if (cover > 0.0) {
			vec2 near_uv = (xz - terrain_sea_near_bounds.xy) / terrain_sea_near_bounds.zw;
			rs.x = mix(rs.x, texture(terrain_sea_near_reach, near_uv).r, cover);
			if (cover >= 0.5) {
				rs.y = terrain_sea_near_spill_on ? texture(terrain_sea_near_spill, near_uv).r : -10000.0;
			}
		}
	}
	return rs;
}

float sea_gate(vec2 rs, float level) {
	return rs.x * smoothstep(rs.y - 0.03, rs.y + 0.03, level);
}

// Environment zones (ZoneMap, EnvironmentZones). R holds the raw grove noise;
// zone_families() below is EnvironmentZones.families() -- GroveScatter's remap
// and per-family cover threshold -- so ground and trees agree on where woods
// are. Both covers 0 = off.
uniform sampler2D terrain_zone_map : hint_default_black, filter_linear, repeat_disable;
uniform vec4 terrain_zone_bounds = vec4(0.0, 0.0, 1.0, 1.0);
// The same inputs over the playable world at ~4 m a pixel, for the near-range
// forest floor; the coarse map above covers the horizon ring. Off = coarse
// map everywhere.
uniform sampler2D terrain_zone_near_map : hint_default_black, filter_linear, repeat_disable;
uniform vec4 terrain_zone_near_bounds = vec4(0.0, 0.0, 1.0, 1.0);
uniform bool terrain_zone_near = false;
uniform float terrain_broadleaf_cover = 0.0;
uniform float terrain_conifer_cover = 0.0;
uniform float terrain_fir_cover = 0.0;
// EnvironmentZones.stems: 1 / spacing^2 for broadleaf, conifer, fir.
uniform vec3 terrain_family_stems = vec3(1.0);
// Observed zones (an imported site's zone mask, A = mapped forest): woodland
// follows the mapped forest, each family at its cover relative to the
// dominant one (EnvironmentZones.relative_families_from_value()).
uniform bool terrain_observed = false;
uniform sampler2D terrain_observed_map : hint_default_black, filter_linear, repeat_disable;
uniform vec4 terrain_observed_bounds = vec4(0.0, 0.0, 1.0, 1.0);
uniform vec3 terrain_relative_covers = vec3(0.0);
// Woodland floor (ZoneRecipe.ground_tint / ground_tint_strength): rgb tint,
// a = strength. Drawn up close and handing over to the far woodland colour
// below over terrain_woodland_start..end.
uniform vec4 terrain_conifer_floor = vec4(0.27, 0.21, 0.14, 0.0);
uniform vec4 terrain_broadleaf_floor = vec4(0.21, 0.23, 0.12, 0.0);
// Far woodland: beyond the distance trees are drawn to, the ground darkens
// where woods stand, so wooded hills on the horizon do not read as bare lawn.
uniform vec3 terrain_woodland_colour : source_color = vec3(0.18, 0.29, 0.13);
uniform float terrain_woodland_strength : hint_range(0.0, 1.0) = 0.7;
// Fades in over this range of camera distance: where real trees stop.
uniform float terrain_woodland_start = 450.0;
uniform float terrain_woodland_end = 600.0;

// EnvironmentZones.GROVE_RAMP and woodland_from_value().
float zone_family(float value, float cover) {
	if (cover <= 0.0) {
		return 0.0;
	}
	float threshold = 1.0 - cover;
	return smoothstep(threshold - 0.1, threshold + 0.1, value);
}

// x = broadleaf, y = conifer, z = fir, before terrain masks.
// EnvironmentZones.families().
vec3 zone_families(vec2 world_xz) {
	vec2 near_uv = (world_xz - terrain_zone_near_bounds.xy) / terrain_zone_near_bounds.zw;
	float n;
	if (terrain_zone_near && all(greaterThanEqual(near_uv, vec2(0.0))) && all(lessThanEqual(near_uv, vec2(1.0)))) {
		n = texture(terrain_zone_near_map, near_uv).r * 2.0 - 1.0;
	} else {
		vec2 zone_uv = (world_xz - terrain_zone_bounds.xy) / terrain_zone_bounds.zw;
		n = texture(terrain_zone_map, zone_uv).r * 2.0 - 1.0;
	}
	float value = clamp(0.5 + n * 1.1, 0.0, 1.0);
	vec3 inferred = vec3(zone_family(value, terrain_broadleaf_cover), zone_family(value, terrain_conifer_cover), zone_family(value, terrain_fir_cover));
	if (terrain_observed) {
		vec2 observed_uv = (world_xz - terrain_observed_bounds.xy) / terrain_observed_bounds.zw;
		float forest = texture(terrain_observed_map, observed_uv).a;
		vec3 mapped = forest * vec3(zone_family(value, terrain_relative_covers.x), zone_family(value, terrain_relative_covers.y), zone_family(value, terrain_relative_covers.z));
		// EnvironmentZones.families(): inferred groves beyond a partial site.
		return mix(inferred, mapped, site_coverage(world_xz));
	}
	return inferred;
}

// EnvironmentZones.conifer_share(): conifer share of woodland by expected stems.
float zone_conifer_share(vec3 families) {
	float broadleaf = families.x * terrain_family_stems.x;
	float conifer = families.y * terrain_family_stems.y + families.z * terrain_family_stems.z;
	return conifer / max(broadleaf + conifer, 0.000001);
}

// Field crops (ImportedSite fields mask, CropCatalogue): B crop id, A row
// angle (0..1 = 0..PI from +X toward +Z), read per texel -- never filtered,
// since neighbouring ids and angles do not average. The site mask's farmland
// channel still blends the field edge. Per crop, for the location's day:
// terrain_crop_field = field colour + cover over soil, terrain_crop_rows =
// (row spacing, stripe width, stripe strength, tramlines).
// Painted zone overrides (Location Studio S4, ZoneOverrides.shader_image()):
// R = EnvironmentZones.Zone index, G = strength, over the painted tiles'
// bounding box at 2 m a texel. Nearest filtering: the same pixel the CPU
// workers sample (ZoneOverrides.sample()).
uniform bool terrain_has_zone_paint = false;
uniform sampler2D terrain_zone_paint : filter_nearest, repeat_disable;
uniform vec4 terrain_zone_paint_bounds = vec4(0.0, 0.0, 1.0, 1.0);
// Each zone recipe's ground tint (linear rgb, strength a), by zone index.
uniform vec4 terrain_zone_tints[16];

// vec2(zone, strength); zone -1 where nothing is painted.
vec2 zone_paint(vec2 xz) {
	if (!terrain_has_zone_paint) {
		return vec2(-1.0, 0.0);
	}
	vec2 uv = (xz - terrain_zone_paint_bounds.xy) / terrain_zone_paint_bounds.zw;
	if (any(lessThan(uv, vec2(0.0))) || any(greaterThanEqual(uv, vec2(1.0)))) {
		return vec2(-1.0, 0.0);
	}
	vec2 texel = texture(terrain_zone_paint, uv).rg;
	return texel.g > 0.0 ? vec2(floor(texel.r * 255.0 + 0.5), texel.g) : vec2(-1.0, 0.0);
}

uniform bool terrain_has_fields = false;
uniform sampler2D terrain_fields_mask : filter_nearest, repeat_disable;
uniform vec4 terrain_crop_field[16];
uniform vec4 terrain_crop_rows[16];
uniform vec3 terrain_field_soil : source_color = vec3(0.35, 0.30, 0.25);

float field_stripes(vec2 xz, vec2 direction, float spacing, float width) {
	float row = dot(xz, vec2(-direction.y, direction.x)) / spacing;
	float aa = max(fwidth(row), 0.0001);
	float line = 1.0 - smoothstep(width - aa, width + aa, abs(fract(row) - 0.5) * 2.0);
	// Average coverage once a stripe is smaller than a pixel.
	return mix(line, width, smoothstep(0.35, 0.9, aa));
}

vec3 field_surface(vec2 xz, vec2 mask_uv) {
	vec3 soil = terrain_field_soil * mix(0.86, 1.08, texture(foliage_colour_noise, xz * 0.004).r)
		* mix(0.94, 1.04, texture(foliage_colour_noise, xz * 0.09).r);
	if (!terrain_has_fields) {
		return soil;
	}
	ivec2 size = textureSize(terrain_fields_mask, 0);
	vec4 texel = texelFetch(terrain_fields_mask, clamp(ivec2(mask_uv * vec2(size)), ivec2(0), size - 1), 0);
	int id = clamp(int(texel.b * 255.0 + 0.5), 0, 15);
	vec4 field = terrain_crop_field[id];
	vec4 rows = terrain_crop_rows[id];
	float angle = texel.a * PI;
	vec2 direction = vec2(cos(angle), sin(angle));
	float patches = texture(foliage_colour_noise, xz * 0.006 + vec2(float(id) * 0.37)).r;
	// Rows gather the plant cover into stripes; stubble shows as straw rows.
	float stripe = field_stripes(xz, direction, rows.x, rows.y);
	float cover = clamp(field.a * mix(1.0, stripe / max(rows.y, 0.05), rows.z), 0.0, 1.0);
	vec3 colour = mix(soil, field.rgb * mix(0.9, 1.08, patches), cover);
	// Tramlines: a pair of wheel tracks every ~20 m, once the crop covers.
	float tram = rows.w * smoothstep(0.3, 0.6, field.a) * field_stripes(xz, direction, 19.8, 0.08);
	return mix(colour, soil, 0.65 * tram);
}

varying vec3 v_world;
varying vec3 v_world_normal;
// Imported river channels (TerrainProvider.water_marks(), baked into vertex
// colour by build_chunk_arrays): x = riverbed, y = damp bank. Off unless the
// provider carves channels -- other ground meshes carry no colour at all.
uniform bool terrain_water_marks = false;
uniform vec3 terrain_riverbed_colour : source_color = vec3(0.36, 0.33, 0.27);
varying vec2 v_marks;

// Narrow imported streams, painted where the ground is too coarse to mesh
// their water (ImportedRivers.stream_field(): RG = offset to the nearest
// centre line, B = its half-width, A = 1 in reach; bounds x, z, width,
// depth). Fades in over the last stretch before `terrain_stream_start` (the
// ground's near ring), from where only channels two lattice cells wide get
// water geometry.
uniform bool terrain_streams = false;
uniform sampler2D terrain_stream_field : filter_linear, repeat_disable;
uniform vec4 terrain_stream_bounds = vec4(0.0, 0.0, 1.0, 1.0);
uniform float terrain_stream_start = 160.0;
uniform vec3 terrain_stream_colour : source_color = vec3(0.16, 0.24, 0.29);

// Horizon ring only (TerrainLayer.configure_as_horizon): (depth, start, end).
// Within `start` metres of the camera the vertex drops `depth` metres,
// easing back to true height by `end`, so the horizon hides under the ground
// layer wherever that exists. Zero on ground chunks: a no-op.
instance uniform vec3 terrain_sink = vec3(0.0);

void vertex() {
	if (terrain_sink.x > 0.0) {
		float d = distance(VERTEX.xz, CAMERA_POSITION_WORLD.xz);
		VERTEX.y -= terrain_sink.x * (1.0 - smoothstep(terrain_sink.y, terrain_sink.z, d));
	}
	v_world = VERTEX;
	v_world_normal = NORMAL;
	v_marks = terrain_water_marks ? COLOR.rg : vec2(0.0);
}

void fragment() {
	float dist = distance(v_world, CAMERA_POSITION_WORLD);
	float near = (1.0 - smoothstep(terrain_detail_distance * 0.5, terrain_detail_distance, dist)) * terrain_detail_strength;

	// Two octaves of the colour noise at turf scale. The colour noise is
	// smooth at its authored scale; sampled this fine it becomes speckle.
	vec2 p = v_world.xz * terrain_detail_scale;
	float d1 = texture(foliage_colour_noise, p * 0.23).r;
	float d2 = texture(foliage_colour_noise, p * 0.61 + vec2(0.37, 0.71)).r;
	float detail = (d1 * 0.6 + d2 * 0.4) - 0.5;

	// variation = 0.5 (neutral): the per-instance jitter grass uses to separate
	// neighbouring tufts has no meaning on a continuous surface, and feeding it
	// anything else would shift terrain colour off the grass it must match.
	// The detail moves along the palette like everything else here, so it can
	// only ever introduce the location's own greens.
	// Beyond any grass (ultra streams it to ~170 m), drop the fine colour
	// octave: see foliage_colour_field_far().
	float far = smoothstep(250.0, 600.0, dist);
	float t = clamp(foliage_palette_t_far(v_world, TIME, 0.5, far) + detail * 0.5 * near, 0.0, 1.0);
	vec3 base = texture(foliage_palette, vec2(t, 0.5)).rgb;
	// Hollows between tufts sit darker.
	base *= 1.0 - max(-detail, 0.0) * 0.6 * near;

	// Detail normal from the same field's slope, so the speckle catches the
	// light like a surface of blades rather than a printed texture.
	float e = 0.08;
	float dx = texture(foliage_colour_noise, (p + vec2(e, 0.0)) * 0.23).r - d1;
	float dz = texture(foliage_colour_noise, (p + vec2(0.0, e)) * 0.23).r - d1;
	vec3 world_normal = normalize(v_world_normal + vec3(-dx, 0.0, -dz) * 6.0 * near);
	NORMAL = normalize((VIEW_MATRIX * vec4(world_normal, 0.0)).xyz);

	float slope = 1.0 - clamp(v_world_normal.y, 0.0, 1.0);
	float rock = smoothstep(terrain_slope_begin, terrain_slope_end, slope);
	// Altitude rock and snow computed here (not where they used to be, after
	// `ground` was already built) so a slope steep enough to also be past
	// rock_line -- exactly the case on a real mountain's near-vertical
	// faces -- combines with `rock` into ONE textured mix below instead of
	// two separate flat-colour mixes muddying toward the same target twice.
	float alt_rock = smoothstep(terrain_rock_line - terrain_altitude_band, terrain_rock_line + terrain_altitude_band, v_world.y);
	float snow = smoothstep(terrain_snow_line - terrain_altitude_band, terrain_snow_line + terrain_altitude_band, v_world.y)
		* smoothstep(0.62, 0.8, v_world_normal.y);
	float rock_amount = max(rock, alt_rock);
	float paint_rock = 0.0;
	{
		vec2 rock_paint = zone_paint(v_world.xz);
		paint_rock = rock_paint.x == 3.0 ? rock_paint.y : 0.0;
	}
	rock_amount = mix(rock_amount, 1.0, paint_rock);

	vec2 mask_uv = (v_world.xz - terrain_mask_bounds.xy) / terrain_mask_bounds.zw;
	float growth = 1.0;
	if (all(greaterThanEqual(mask_uv, vec2(0.0))) && all(lessThanEqual(mask_uv, vec2(1.0)))) {
		growth = texture(terrain_growth_mask, mask_uv).r;
	}
	// Full dirt only where almost nothing grows, blending across the rest of
	// the mask's edge. The placer is still putting down a few tufts in that
	// band; they should stand on mixed ground, not on a hard dirt line that
	// shows every card's straight bottom edge.
	float bare = 1.0 - smoothstep(0.05, 0.75, growth);
	// A river's bank: a strip of trodden, muddy ground at the waterline that
	// gives way to turf, rather than grass running straight into the water.
	// Patchy, so it never reads as a path laid along the stream.
	float bank_patches = mix(0.45, 1.0, texture(foliage_colour_noise, v_world.xz * 0.15).r);
	bare = max(bare, smoothstep(0.55, 0.95, v_marks.y) * 0.8 * bank_patches);
	// Painted zones (zone indices as EnvironmentZones.Zone): 1 conifer,
	// 2 broadleaf, 3 rock, 5 bare, 8 farmland. Painted bare ground is dirt.
	vec2 paint = zone_paint(v_world.xz);
	float paint_zone = paint.x;
	float paint_strength = paint.y;
	bool paint_woods = paint_zone == 1.0 || paint_zone == 2.0;
	bool paint_woody = paint_woods || paint_zone == 10.0;
	if (paint_zone == 5.0) {
		bare = mix(bare, 1.0, paint_strength);
	}

	float shade_near = 1.0 - smoothstep(terrain_detail_distance * 0.5, terrain_detail_distance, dist);
	base *= 1.0 - terrain_under_grass_shade * shade_near;
	// Bare ground: compacted earth with some patchiness, not one flat colour.
	vec3 bare_ground = terrain_bare_colour * mix(0.88, 1.07, texture(foliage_colour_noise, v_world.xz * 0.05).r);
	vec3 ground = mix(base, bare_ground, bare);
	vec2 site = vec2(1.0, 0.0);
	bool in_site = all(greaterThanEqual(mask_uv, vec2(0.0))) && all(lessThanEqual(mask_uv, vec2(1.0)));
	// A partial site's masks end at its edge; beyond, trees are unrestricted
	// and there are no mapped fields (ImportedSite.tree_mask()).
	if (terrain_has_site_mask && (in_site || terrain_site_fade <= 0.0)) {
		site = texture(terrain_site_mask, mask_uv).gb;
		site.x = mix(1.0, site.x, site_coverage(v_world.xz));
		// A painted zone replaces the mapped field (painted farmland gets
		// plain field ground below, not crop rows).
		site.y *= 1.0 - paint_strength;
		// Cultivated fields need their own surface; low wild grass is a proxy.
		if (site.y > 0.001) {
			ground = mix(ground, field_surface(v_world.xz, mask_uv), site.y);
		}
	}
	// Painted woodland and scrub allow woody growth; other painted zones clear
	// it (HeightmapTerrainProvider.site_tree_mask()).
	site.x = mix(site.x, paint_woody ? 1.0 : 0.0, paint_strength);
	if (paint_zone == 8.0) {
		float soil_grain = mix(0.9, 1.08, texture(foliage_colour_noise, v_world.xz * 0.21).r);
		ground = mix(ground, terrain_field_soil * soil_grain, paint_strength);
	}
	// Painted zones with a ground tint (wetland, garden, scrub...); woodland
	// floors are tinted with the woods below.
	if (paint_strength > 0.0 && !paint_woods) {
		vec4 tint = terrain_zone_tints[int(paint_zone)];
		ground = mix(ground, tint.rgb, paint_strength * tint.a);
	}
	float sand = 0.0;
	if (terrain_has_habitats && in_site) {
		vec3 habitat = texture(terrain_habitat_mask, mask_uv).rgb * site_coverage(v_world.xz) * (1.0 - paint_strength);
		float grain = mix(0.9, 1.08, texture(foliage_colour_noise, v_world.xz * 0.11).r);
		vec3 dune_ground = terrain_dune_ground.rgb * grain;
		ground = mix(ground, dune_ground, habitat.r * terrain_dune_ground.a);
		ground = mix(ground, terrain_heath_ground.rgb * grain, habitat.g * terrain_heath_ground.a);
		sand = habitat.b;
		ground = mix(ground, dune_ground, sand);
	}
	// The sea's reach and spill, read once for the pixel -- and not at all on
	// ground well above any water (most hillsides), where every use below
	// (foreshore, submerged, damp shore, swash) is zero anyway.
	vec2 sea_rs = terrain_sea_masked ? vec2(0.0, 10000.0) : vec2(1.0, -10000.0);
	if (terrain_sea_masked && v_world.y < max(terrain_water_level, terrain_sea_high_water) + terrain_shore_band * 3.0 + 4.0) {
		sea_rs = sea_reach_spill(v_world.xz);
	}
	// The tidal foreshore: sand-coloured ground the tide uncovers, not the
	// inland bare earth.
	float foreshore = 0.0;
	if (terrain_sea_tidal) {
		foreshore = sea_gate(sea_rs, terrain_sea_high_water + terrain_shore_band) * (1.0 - smoothstep(terrain_sea_high_water - terrain_shore_band, terrain_sea_high_water + terrain_shore_band, v_world.y));
		float grain = mix(0.9, 1.08, texture(foliage_colour_noise, v_world.xz * 0.11).r);
		ground = mix(ground, terrain_foreshore_colour * grain, foreshore * (1.0 - sand));
	}

	// Rock and snow share one triplanar sample (see foliage_triplanar_noise
	// in foliage_common.gdshaderinc): they sit right next to each other at
	// the snow line, and one shared sample means the two never show a seam
	// of mismatched noise where they meet. Guarded: a location whose bands
	// (or whose slopes) never trigger these pays nothing extra.
	if (rock_amount > 0.001 || snow > 0.001) {
		float rn = foliage_triplanar_noise(v_world, v_world_normal, terrain_rock_scale);
		// Facets: darker in the noise's low half, lighter in its high half --
		// the same "hollows sit darker" idea the turf detail above already
		// uses, just triplanar so it reads correctly on a cliff face too.
		vec3 rock_colour = terrain_slope_colour * mix(1.0 - terrain_rock_facet_strength, 1.0 + terrain_rock_facet_strength * 0.6, rn);
		ground = mix(ground, rock_colour, rock_amount);
		// Snow gets a much subtler version of the same break-up -- enough to
		// avoid a flat painted-white sheet, not enough to look craggy.
		vec3 snow_colour = terrain_snow_colour * mix(0.94, 1.03, rn);
		ground = mix(ground, snow_colour, snow);
	}

	// 1 fully underwater, easing out over terrain_shore_band either side --
	// WaterProfile.water_mask()'s own formula, so the grass mask and this
	// colour cutoff agree exactly on where the shore is.
	float submerged = 1.0 - smoothstep(terrain_water_level - terrain_shore_band, terrain_water_level + terrain_shore_band, v_world.y);
	float sea_here = sea_gate(sea_rs, terrain_water_level);
	submerged *= sea_here;

	if (terrain_broadleaf_cover > 0.0 || terrain_conifer_cover > 0.0 || terrain_fir_cover > 0.0 || paint_strength > 0.0) {
		vec3 families = zone_families(v_world.xz);
		// The families share one noise, so the strongest is the woodland
		// extent (EnvironmentZones.woodland_extent()).
		float woods = max(families.x, max(families.y, families.z));
		// Painted woodland fills to full cover; other painted zones clear it
		// (EnvironmentZones.painted_grove()).
		woods = mix(woods, paint_woods ? 1.0 : 0.0, paint_strength);
		// Trees keep off steep ground, bare paths, rock and snow; so does this.
		woods *= (1.0 - rock) * (1.0 - bare) * (1.0 - alt_rock) * (1.0 - snow) * (1.0 - paint_rock);
		woods *= site.x;
		float far_band = smoothstep(terrain_woodland_start, terrain_woodland_end, dist);
		// Up close: the floor under the trees, by family share as in
		// EnvironmentZones.weights_for(). Far: the canopy colour seen from
		// afar. One fades out as the other fades in, where real trees end.
		float conifer_share = zone_conifer_share(families);
		if (paint_woods) {
			conifer_share = mix(conifer_share, paint_zone == 1.0 ? 1.0 : 0.0, paint_strength);
		}
		vec4 floor_tint = mix(terrain_broadleaf_floor, terrain_conifer_floor, conifer_share);
		ground = mix(ground, floor_tint.rgb, woods * floor_tint.a * (1.0 - far_band));
		ground = mix(ground, terrain_woodland_colour, woods * terrain_woodland_strength * far_band);
	}
	// The lakebed: bare ground colour under water, not grass green showing
	// through the water plane's transparency. Same reasoning as rock and snow.
	// The sea's bed is the foreshore, coloured above, so it does not change
	// colour as the tide covers it.
	ground = mix(ground, terrain_bare_colour, submerged * (1.0 - foreshore));
	// A streambed: pebbly, darker than the bank, seen through clear shallows.
	if (v_marks.x > 0.001) {
		float pebbles = texture(foliage_colour_noise, v_world.xz * 0.9).r;
		ground = mix(ground, terrain_riverbed_colour * mix(0.7, 1.15, pebbles), v_marks.x);
		submerged = max(submerged, v_marks.x);
	}

	// Wet soil: only where the ground is bare (or rock, or submerged), so
	// grassed terrain keeps matching the grass for the horizon handover. Turf
	// gets the shared, milder darkening inside foliage_apply_distance_tint.
	float soil = max(bare, rock_amount * 0.5) * (1.0 - snow);
	// The shoreline itself reads damp regardless of weather -- a beach is not
	// "raining", it is next to water -- fading out a little beyond the narrow
	// grow/no-grow cutoff above.
	float shore_damp = 1.0 - smoothstep(0.0, terrain_shore_band * 3.0, abs(v_world.y - terrain_water_level));
	shore_damp *= min(sea_here * 2.0, 1.0);
	// A tide wets what it has covered, and only that: the band above the
	// live level dries out over the hours since the water left it, so wet
	// sand trails the ebb and the flood meets dry sand.
	// Above the live level only a thin swash line stays damp regardless.
	float wet_sand = 0.0;
	if (terrain_sea_tidal) {
		shore_damp *= 1.0 - smoothstep(0.0, 0.15, v_world.y - terrain_water_level);
		if (foreshore > 0.0) {
			wet_sand = foreshore * (1.0 - smoothstep(0.0, terrain_wet_sand_hours, tide_hours_since_covered(v_world.y)));
		}
	}
	// Swash: a sheet of water running up the beach and back with each wave,
	// a foam line at its front, over sand it leaves glossy (wet sand above).
	vec2 swash = vec2(0.0);
	if (surf_enabled && sea_here > 0.5) {
		swash = surf_swash(v_world.xz, v_world.y - terrain_water_level, TIME);
		shore_damp = max(shore_damp, swash.x);
	}
	shore_damp = max(shore_damp, v_marks.y);
	float soaked = max(max(atmosphere_wetness, shore_damp * 0.85) * max(max(soil, submerged), foreshore), wet_sand);
	ground *= 1.0 - terrain_wet_soil_darkening * soaked;
	float puddle = atmosphere_puddle(
		texture(foliage_colour_noise, v_world.xz * terrain_puddle_scale).r, bare, slope) * terrain_puddle_amount * (1.0 - submerged)
		* (1.0 - sand) * (1.0 - foreshore); // Sand drains; the tide clears the foreshore.
	// Standing water is dark; nearly all you see in it is the reflection.
	ground *= 1.0 - 0.6 * puddle;
	// A puddle is a flat mirror: drop the turf detail normal.
	NORMAL = normalize(mix(NORMAL, (VIEW_MATRIX * vec4(0.0, 1.0, 0.0, 0.0)).xyz, puddle));

	float stream = 0.0;
	if (terrain_streams) {
		vec2 suv = (v_world.xz - terrain_stream_bounds.xy) / terrain_stream_bounds.zw;
		if (all(greaterThanEqual(suv, vec2(0.0))) && all(lessThanEqual(suv, vec2(1.0)))) {
			vec4 field = texture(terrain_stream_field, suv);
			float off_line = length(field.rg) - field.b;
			float aa = max(fwidth(off_line), 0.05);
			float flat_dist = distance(v_world.xz, CAMERA_POSITION_WORLD.xz);
			stream = (1.0 - smoothstep(-aa, aa, off_line)) * step(0.5, field.a)
				* smoothstep(terrain_stream_start - 24.0, terrain_stream_start, flat_dist);
			ground = mix(ground, terrain_stream_colour, stream);
		}
	}

	// The swash sheet: thin water over the sand, darker and mirror-smooth,
	// with foam at its front.
	ground = mix(ground, ground * 0.7, swash.x * 0.6);
	ground = mix(ground, vec3(0.86, 0.9, 0.9), swash.y * 0.85);
	puddle = max(puddle, swash.x * 0.8 * (1.0 - swash.y));

	ALBEDO = foliage_apply_distance_tint(ground, v_world, CAMERA_POSITION_WORLD);

	ROUGHNESS = mix(mix(mix(terrain_roughness, 0.35, soaked), 0.04, puddle), 0.12, stream);
	SPECULAR = mix(mix(0.1, 0.5, max(soaked * 0.5, puddle)), 0.5, stream);
}
