shader_type spatial;

// The sea and any lakes (WaterLayer): flat planes, coarse next to the real
// terrain mesh. Neither needs its own shape -- wherever the ground rises
// above the water it simply occludes the plane through ordinary depth
// testing, and that occlusion is against the terrain's real, fine-resolution
// mesh, so the shoreline you actually see is already terrain-accurate.
//
// Wave silhouette therefore cannot come from mesh detail (the plane is far too
// coarse for that up close) -- it is split in two instead: a broad, slow
// vertical swell in the vertex shader for large-scale movement, and a
// fragment-only normal perturbation for surface ripple, which reads as detail
// at any mesh resolution. Both scroll with the wind, and both react to
// foliage_gust_scale / foliage_wind_scroll -- the same two globals
// AtmosphereSystem already sets every frame for the grass and terrain (see
// foliage/shaders/foliage_common.gdshaderinc) -- so a storm roughens the sea
// for free, no new plumbing.
//
// The swell is the one place this shader DOES need to know how deep the
// water is, and the flat plane cannot tell it that on its own: blind vertical
// displacement, applied right up to a shore where the ground sits at nearly
// the water's own height, pushes the surface through the ground and back
// every cycle -- which on a shallow grade reads as the shore surging in and
// out ("tides") rather than a still edge with a rippling surface further out.
// water_depth_map fixes this with the same knowledge the growth mask already
// has (LandformTerrainProvider.water_depth_grid(), baked by WaterDepthMap):
// the swell fades to nothing in shallow water and only grows once there is
// real depth to move. See docs/WATER.md, *Terrain-aware water*.
render_mode world_vertex_coords, blend_mix, depth_draw_opaque, cull_back, diffuse_lambert, specular_schlick_ggx;

// The horizon handover every foliage surface uses: fades towards the
// location's distance_tint, and carries cloud shadow and the atmosphere's
// wetness onto albedo. Included directly rather than through
// foliage_common.gdshaderinc: water shares none of that include's grass
// colour/palette contract, only this one shared tail function (see
// debris.gdshader, which makes the same choice for the same reason).
#include "res://foliage/shaders/foliage_distance.gdshaderinc"

group_uniforms water;
uniform sampler2D water_palette : source_color, hint_default_white, filter_linear, repeat_disable;
// Depth buffer captured before transparent objects draw -- the opaque scene,
// i.e. the ground beneath this water pixel. Reconstructing a world/view depth
// from it is what lets a single flat plane still shade shallow water near a
// shore differently from the open sea, with no terrain sampling at all.
uniform sampler2D depth_tex : hint_depth_texture, repeat_disable, filter_nearest;
uniform float water_shallow_depth : hint_range(0.1, 40.0) = 4.0;

// Baked by WaterDepthMap (procedural) or ImportedSea.bed_texture() (a real
// coastline). R: depth of still water that does not follow the sea (lakes),
// 0 elsewhere. G: height of the bed under the sea (ground plus seabed). The
// sea's depth is computed here against the live level, water_sea_level_now
// (SeaState), so a moving sea level reshapes the swell fade with no rebake
// (docs/SEA_PLAN.md, SEA1). World XZ rectangle it covers, same (x, z, width,
// depth) layout as terrain_mask_bounds/terrain_zone_bounds. Default bounds
// are a harmless placeholder -- FoliageLocation always sets both together,
// and a location with no water at all leaves the map unset; water_depth_at()
// then reads no depth anywhere, which is exactly "no swell fade needed".
uniform sampler2D water_depth_map : hint_default_black, filter_linear, repeat_disable;
uniform bool water_has_depth_map = false;
uniform vec4 water_depth_bounds = vec4(-4000.0, -4000.0, 8000.0, 8000.0);
uniform float water_sea_level_now = 0.0;

group_uniforms water_waves;
uniform sampler2D water_ripple_noise : hint_default_white, filter_linear_mipmap, repeat_enable;
uniform float water_swell_height : hint_range(0.0, 1.0) = 0.12;
uniform float water_swell_scale : hint_range(5.0, 400.0) = 60.0;
uniform float water_swell_speed : hint_range(0.0, 1.0) = 0.06;
uniform float water_swell_depth_fade : hint_range(0.0, 20.0) = 2.0;
uniform float water_ripple_strength : hint_range(0.0, 2.0) = 0.35;
uniform float water_ripple_scale : hint_range(0.01, 2.0) = 0.12;
// FoliageProfile.apply_to_water_material(): the location's own wind, so the
// sea's ripples travel the same way the grass bends, not a second direction
// authored separately that could drift from it.
uniform vec2 water_wind_direction = vec2(1.0, 0.35);
uniform float water_wind_speed = 0.12;

group_uniforms water_shading;
uniform float water_fresnel_strength : hint_range(0.0, 1.0) = 0.6;
uniform float water_fresnel_power : hint_range(0.5, 8.0) = 3.0;
uniform float water_roughness : hint_range(0.0, 1.0) = 0.05;

group_uniforms water_flow;
// Imported (fitted) water, docs/WATER.md W5. Per instance, z selects the mesh:
//   0  the sea, LandformTerrainProvider lakes, draped rivers: the
//      wind-driven still-water path, untouched.
//   2  a waterfall's falling curtain (WaterLayer._build_fall_mesh): x =
//      speed (m/s), y = width (m); UV (0..1 across, metres down the fall).
//   3  the water field meshed with the ground (TerrainProvider.
//      build_water_arrays()): rivers and lakes as one surface. Vertex colour
//      rg = flow (TerrainProvider.WATER_FLOW_RANGE), b = foam; UV2.x = the
//      water's width, which picks its shading scale.
//   4  a whole imported lake's far mesh (WaterLayer): mode 3 at rest, so the
//      handover between them cannot be seen.
instance uniform vec3 water_flow = vec3(0.0);
// Horizontal distance from the camera inside which (x) / beyond which (y)
// this instance is not drawn, 0 = no limit: the ground's water field stops
// where the ground's streaming stops being guaranteed, and a lake's far mesh
// starts exactly there.
instance uniform vec2 water_cut = vec2(0.0);
// A real coastline (ImportedSea): the sea plane (water_is_sea, set only on
// WaterLayer's sea) draws only where the sea reaches, so ground below sea
// level behind the shore is not flooded. The beach and dunes rise above the
// plane and hide it at the shore itself, so the coarse reach only needs to
// tell open sea from inland. Lakes and rivers never read it.
instance uniform float water_is_sea = 0.0;
uniform bool water_sea_masked = false;
uniform sampler2D water_sea_reach : hint_default_white, filter_linear, repeat_disable;
uniform vec4 water_sea_bounds = vec4(-12000.0, -12000.0, 24000.0, 24000.0);
// The near grid's reach (SEA6, ImportedSea.near_reach_texture): 10 m over
// the world, handing back to the 50 m reach over its last
// water_sea_near_fade metres. ImportedSea.reach()'s blend.
uniform bool water_sea_near = false;
uniform sampler2D water_sea_near_reach : hint_default_white, filter_linear, repeat_disable;
// Spill heights (SEA6), each grid's own texture; off = the sea floods its
// whole reach (an older sidecar).
uniform bool water_sea_spill_on = false;
uniform sampler2D water_sea_spill : hint_default_black, filter_linear, repeat_disable;
uniform bool water_sea_near_spill_on = false;
uniform sampler2D water_sea_near_spill : hint_default_black, filter_linear, repeat_disable;
uniform vec4 water_sea_near_bounds = vec4(-4200.0, -4200.0, 8400.0, 8400.0);
uniform float water_sea_near_fade = 100.0;

// How much sea there is at `xz` with the sea at `level`: the reach (R),
// where the level tops the spill height (G, SEA6) -- the lowest sea level
// that gets there over the ground in between. ImportedSea.reach() and
// spill().
float water_sea_reach_at(vec2 xz, float level) {
	vec2 uv = (xz - water_sea_bounds.xy) / water_sea_bounds.zw;
	vec2 rs = vec2(texture(water_sea_reach, uv).r, water_sea_spill_on ? texture(water_sea_spill, uv).r : -10000.0);
	if (water_sea_near) {
		vec2 half_size = water_sea_near_bounds.zw * 0.5;
		vec2 centre = water_sea_near_bounds.xy + half_size;
		float cover = clamp((half_size.x - max(abs(xz.x - centre.x), abs(xz.y - centre.y))) / water_sea_near_fade, 0.0, 1.0);
		if (cover > 0.0) {
			vec2 near_uv = (xz - water_sea_near_bounds.xy) / water_sea_near_bounds.zw;
			rs.x = mix(rs.x, texture(water_sea_near_reach, near_uv).r, cover);
			if (cover >= 0.5) {
				rs.y = water_sea_near_spill_on ? texture(water_sea_near_spill, near_uv).r : -10000.0;
			}
		}
	}
	return rs.x * smoothstep(rs.y - 0.03, rs.y + 0.03, level);
}
// Shallow-to-deep range for a stream: a 4 m lake scale would leave a
// half-metre channel looking almost empty. Water from water_wide_start to
// _end metres wide moves over to the lake's scale (water_shallow_depth), so
// a river and the lake it runs into shade alike where their depths agree.
uniform float water_river_shallow_depth : hint_range(0.1, 10.0) = 0.9;
uniform float water_wide_start = 5.0;
uniform float water_wide_end = 16.0;
// Narrow water (up to water_narrow_end m wide, fully below _start) sits low
// between its banks: it catches less sky and is shaded. Without this a brook
// seen from a little way off is a bright white line of reflected sky.
uniform float water_narrow_start = 2.5;
uniform float water_narrow_end = 8.0;
uniform float water_narrow_reflection : hint_range(0.0, 1.0) = 0.3;
uniform float water_narrow_shade : hint_range(0.0, 1.0) = 0.3;
// Keep in step with TerrainProvider.WATER_FLOW_RANGE.
const float WATER_FLOW_RANGE = 4.0;
// A flow-map cycle: ripples are carried downstream for this long, then
// faded into a second copy half a cycle behind, so they never stretch out.
uniform float water_flow_cycle : hint_range(0.5, 10.0) = 2.5;
uniform float water_foam_strength : hint_range(0.0, 1.0) = 0.45;
uniform vec3 water_foam_colour : source_color = vec3(0.9, 0.94, 0.95);

global uniform float foliage_gust_scale;
global uniform vec2 foliage_wind_scroll;

// Surf (SEA5): sea_surf.gdshaderinc's wave. Every sea pixel takes its
// normals and foam; only the near surf patch (WaterLayer, a fine grid
// round the camera) is displaced by it, fading flat by `water_surf_patch`
// metres from the camera, where the coarse sea plane takes over. 0 = no
// displacement (the coarse plane, whose 135 m cells cannot carry a 36 m wave).
#include "res://foliage/shaders/sea_surf.gdshaderinc"
instance uniform float water_surf_patch = 0.0;
// Foam on breaking waves, before the lace texture thins it.
uniform float water_surf_foam : hint_range(0.0, 1.0) = 0.9;

varying vec3 v_world;
varying vec3 v_flow;
varying float v_width;

// Depth (world units) at a world XZ position: the deeper of the still water
// and the sea at its live level, the sea gated by its reach on a real
// coastline. Outside the map's bounds reads as 0 (dry) rather than sampling
// garbage -- the water planes are sized generously (WaterLayer.reach, a
// basin's bounds grown a little) and can extend slightly past where the map
// itself was baked.
float water_depth_at(vec2 world_xz) {
	vec2 uv = (world_xz - water_depth_bounds.xy) / water_depth_bounds.zw;
	if (!water_has_depth_map || any(lessThan(uv, vec2(0.0))) || any(greaterThan(uv, vec2(1.0)))) {
		return 0.0;
	}
	vec2 still_bed = texture(water_depth_map, uv).rg;
	float sea = max(water_sea_level_now - still_bed.y, 0.0);
	if (water_sea_masked) {
		sea *= water_sea_reach_at(world_xz, water_sea_level_now);
	}
	return max(still_bed.x, sea);
}

void vertex() {
	if (water_flow.z > 3.5) {
		// A lake's far mesh: level, at rest.
		v_flow = vec3(0.0);
		v_width = 1000.0;
	} else if (water_flow.z > 2.5) {
		// The water field: level in its carved channels and basins, no swell
		// (it would lift the surface out over the banks).
		v_flow = vec3((COLOR.rg * 2.0 - 1.0) * WATER_FLOW_RANGE, COLOR.b);
		v_width = UV2.x;
		// Estuaries (SEA8): UV2.y is the tidal weight (ImportedRivers.
		// mark_tidal()). The river rises towards the live sea level by it --
		// never falls -- and its flow is held back as the flood comes in.
		float tide_w = UV2.y;
		if (tide_w > 0.0) {
			float raised = max(VERTEX.y, mix(VERTEX.y, water_sea_level_now, tide_w));
			v_flow.xy *= 1.0 - smoothstep(0.0, 0.5, raised - VERTEX.y);
			VERTEX.y = raised;
		}
	} else if (water_flow.z > 0.5) {
		v_flow = vec3(COLOR.rg * 2.0 - 1.0, COLOR.b);
		v_width = water_flow.y;
	} else {
		v_flow = vec3(1.0, 0.0, 0.0);
		v_width = 1000.0;
		vec2 dir = normalize(water_wind_direction);
		vec2 uv = VERTEX.xz / water_swell_scale - dir * (TIME * water_swell_speed) - foliage_wind_scroll * 0.2;
		float swell = texture(water_ripple_noise, uv).r * 2.0 - 1.0;
		// Terrain-aware: fade the swell out in shallow water so it cannot push
		// the surface through nearby dry ground -- see the class comment.
		float sea_depth = water_depth_at(VERTEX.xz);
		float depth_fade = smoothstep(0.0, max(water_swell_depth_fade, 0.001), sea_depth);
		float lift = swell * water_swell_height * foliage_gust_scale * depth_fade;
		if (water_surf_patch > 0.0) {
			float near = 1.0 - smoothstep(water_surf_patch * 0.7, water_surf_patch * 0.95, distance(VERTEX.xz, CAMERA_POSITION_WORLD.xz));
			lift += surf_wave(VERTEX.xz, sea_depth, TIME).x * near;
		}
		VERTEX.y += lift;
	}
	v_world = VERTEX;
}

// Ripple heights at `uv` and its two neighbours, for a normal.
vec3 _ripple(vec2 uv) {
	float e = 0.35;
	float h0 = texture(water_ripple_noise, uv).r;
	return vec3(h0, texture(water_ripple_noise, uv + vec2(e, 0.0)).r - h0, texture(water_ripple_noise, uv + vec2(0.0, e)).r - h0);
}

// A river's surface: ripples stretched along and scrolling down the channel
// in its own (across, along) frame, so they follow every bend without the
// smearing a world-space scroll would show; foam where the bed steepens and
// a thin lapping line at the waterline. Returns (colour, alpha); writes the
// view-space normal through `normal`.
vec4 _flowing_surface(vec3 colour, float depth, float depth_m, vec2 uv, vec3 flow, vec3 world,
		inout vec3 normal, mat4 view_matrix, vec3 camera, float time, bool falling) {
	vec2 dir = length(flow.xy) > 0.01 ? normalize(flow.xy) : vec2(1.0, 0.0);
	// UV.x runs from the left bank (+perpendicular) to the right one.
	vec2 across_dir = -vec2(-dir.y, dir.x);
	vec2 channel = vec2(uv.x * water_flow.y, uv.y);
	float speed = water_flow.x;
	vec2 a_uv = vec2(channel.x * 1.6, (channel.y - time * speed) * 0.5) * water_ripple_scale * 1.5;
	vec2 b_uv = vec2(channel.x * 2.4 + 0.37, (channel.y - time * speed * 1.35) * 0.9) * water_ripple_scale * 2.1;
	vec3 ra = _ripple(a_uv);
	vec3 rb = _ripple(b_uv);
	float gx = ra.y + rb.y * 0.5;
	float gz = ra.z + rb.z * 0.5;
	float ripple = water_ripple_strength * (0.8 + 0.4 * foliage_gust_scale);
	vec2 slope = (across_dir * gx + dir * gz) * ripple;
	vec3 world_normal = normalize(vec3(-slope.x, 1.0, -slope.y));
	if (falling) {
		// A curtain keeps its own (outward, arcing) normal; ripples on a
		// vertical sheet would light it as if it were lying flat.
		world_normal = normalize((inverse(view_matrix) * vec4(normal, 0.0)).xyz);
	} else {
		normal = normalize((view_matrix * vec4(world_normal, 0.0)).xyz);
	}

	float ndotv = clamp(dot(world_normal, normalize(camera - world)), 0.0, 1.0);
	// Softer than the open water's: a narrow stream seen at a grazing angle
	// otherwise turns into a white line.
	colour = mix(colour, vec3(1.0), pow(1.0 - ndotv, water_fresnel_power) * water_fresnel_strength * 0.5);

	float streak = texture(water_ripple_noise, vec2(channel.x * 0.5, (channel.y - time * speed * 1.1) * 0.08)).r;
	// White water only where the bed actually steepens; calm reaches stay clear.
	float rapids = smoothstep(0.66, 0.84, streak) * clamp(flow.z * 2.5, 0.0, 1.0);
	float lap = smoothstep(0.0, 0.04, depth_m) * (1.0 - smoothstep(0.08, 0.22, depth_m)) * smoothstep(0.4, 0.7, ra.x);
	float foam = clamp(max(rapids, lap), 0.0, 1.0) * water_foam_strength;
	if (falling) {
		// Falling water is aerated almost all the way through: streaks of
		// clearer water in a white sheet, never see-through.
		float sheet = texture(water_ripple_noise, vec2(channel.x * 0.35, (channel.y - time * speed) * 0.05)).r;
		foam = mix(0.55, 0.95, smoothstep(0.3, 0.7, sheet));
		colour = mix(colour, water_foam_colour, foam);
		return vec4(colour, mix(0.7, 0.92, foam));
	}
	colour = mix(colour, water_foam_colour, foam);
	return vec4(colour, max(clamp(depth * 3.0, 0.0, 0.92), foam * 0.85 * smoothstep(0.0, 0.03, depth_m)));
}

// Ripple slope (x, z) and height at `p` (world XZ). Deliberately in the
// world's own axes: rotating world coordinates into the local flow direction
// shears the pattern wherever that direction changes (by hundreds of metres'
// worth at a world position hundreds of metres out), which drew faceted
// chevrons across every bend.
vec3 _ripple_frame(vec2 p) {
	vec3 ra = _ripple(p * water_ripple_scale * 1.5);
	vec3 rb = _ripple(p * water_ripple_scale * 2.7 + vec2(0.37, 0.61));
	return vec3(ra.y + rb.y * 0.5, ra.z + rb.z * 0.5, ra.x);
}

// The water field (modes 3 and 4): one surface for rivers and lakes. Ripples
// ride the flow by the flow-map method -- two copies of the ripple pattern
// carried downstream, each faded out as it gets stretched and back in from
// where it started, half a cycle apart -- so they follow every bend and turn
// into a tributary's stem without any per-river UV. Where the flow dies
// away (lakes) the wind ripples of still water take over. Returns (colour,
// alpha); writes the view-space normal through `normal`.
vec4 _field_surface(float depth_m, vec3 flow, float width, vec3 world, inout vec3 normal,
		mat4 view_matrix, vec3 camera, float time) {
	float speed = length(flow.xy);
	float flowing = smoothstep(0.05, 0.5, speed);
	float scale = mix(water_river_shallow_depth, water_shallow_depth, smoothstep(water_wide_start, water_wide_end, width));
	float depth = clamp(depth_m / scale, 0.0, 1.0);
	vec3 colour = texture(water_palette, vec2(depth, 0.5)).rgb;
	float narrow = 1.0 - smoothstep(water_narrow_start, water_narrow_end, width);
	colour *= 1.0 - water_narrow_shade * narrow;

	float p0 = fract(time / water_flow_cycle);
	float p1 = fract(time / water_flow_cycle + 0.5);
	float w0 = 1.0 - abs(p0 * 2.0 - 1.0);
	vec3 r0 = _ripple_frame(world.xz - flow.xy * p0 * water_flow_cycle);
	vec3 r1 = _ripple_frame(world.xz - flow.xy * p1 * water_flow_cycle + vec2(5.3, 2.9));
	vec3 running = r0 * w0 + r1 * (1.0 - w0);
	float running_strength = water_ripple_strength * (0.8 + 0.4 * foliage_gust_scale);

	vec2 wind = normalize(water_wind_direction);
	vec2 ruv = world.xz * water_ripple_scale - wind * (time * water_wind_speed * 2.0) - foliage_wind_scroll;
	vec3 still = _ripple(ruv);
	vec2 ruv2 = world.xz * water_ripple_scale * 2.3 + wind.yx * (time * water_wind_speed * 3.1);
	vec3 still2 = _ripple(ruv2);
	vec2 still_slope = vec2(still.y + still2.y * 0.5, still.z + still2.z * 0.5) * water_ripple_strength * foliage_gust_scale;

	vec2 slope = mix(still_slope, running.xy * running_strength, flowing);
	vec3 world_normal = normalize(vec3(-slope.x, 1.0, -slope.y));
	normal = normalize((view_matrix * vec4(world_normal, 0.0)).xyz);

	float ndotv = clamp(dot(world_normal, normalize(camera - world)), 0.0, 1.0);
	// Softer on running water: a narrow stream seen at a grazing angle
	// otherwise turns into a white line.
	float fresnel = pow(1.0 - ndotv, water_fresnel_power) * water_fresnel_strength * mix(1.0, 0.5, flowing)
		* mix(1.0, water_narrow_reflection, narrow);
	colour = mix(colour, vec3(1.0), fresnel);

	// White water where the bed steepens (foam, carried by the flow), and a
	// thin lapping line at the waterline.
	// Flecks of white water carried by the flow (world axes, as above).
	// Smaller flecks on narrower water.
	float fleck = mix(0.35, 0.9, narrow);
	float s0 = texture(water_ripple_noise, (world.xz - flow.xy * p0 * water_flow_cycle) * fleck).r;
	float s1 = texture(water_ripple_noise, (world.xz - flow.xy * p1 * water_flow_cycle) * fleck + vec2(0.41, 0.17)).r;
	float streak = s0 * w0 + s1 * (1.0 - w0);
	float rapids = smoothstep(mix(0.62, 0.74, narrow), 0.86, streak) * clamp(flow.z * 2.5, 0.0, 1.0) * mix(1.0, 0.6, narrow);
	float ripple_height = mix(still.x, running.z, flowing);
	float lap = smoothstep(0.0, 0.04, depth_m) * (1.0 - smoothstep(0.08, 0.22, depth_m)) * smoothstep(0.4, 0.7, ripple_height);
	float foam = clamp(max(rapids, lap), 0.0, 1.0) * water_foam_strength;
	colour = mix(colour, water_foam_colour, foam);
	return vec4(colour, max(clamp(depth * 3.0, 0.0, 0.92), foam * 0.85 * smoothstep(0.0, 0.03, depth_m)));
}

void fragment() {
	// Reconstruct the opaque scene's view-space depth under this pixel, and
	// compare it against this fragment's own -- see the uniform comment above.
	// In fragment(), VERTEX is always view space (world_vertex_coords only
	// affects the vertex stage), so -VERTEX.z is this pixel's own depth in the
	// same space the reconstruction below produces.
	float raw_depth = texture(depth_tex, SCREEN_UV).r;
	vec3 ndc = vec3(SCREEN_UV * 2.0 - 1.0, raw_depth);
	vec4 view = INV_PROJECTION_MATRIX * vec4(ndc, 1.0);
	view.xyz /= view.w;
	float scene_depth = -view.z;
	float water_depth_here = -VERTEX.z;
	float camera_distance = distance(v_world.xz, CAMERA_POSITION_WORLD.xz);
	if ((water_cut.x > 0.0 && camera_distance < water_cut.x) || (water_cut.y > 0.0 && camera_distance > water_cut.y)) {
		discard;
	}
	if (water_is_sea > 0.5 && water_sea_masked
			&& water_sea_reach_at(v_world.xz, water_sea_level_now) < 0.5) {
		discard;
	}
	bool field = water_flow.z > 2.5;
	bool falling = water_flow.z > 1.5 && !field;
	// Where the sea itself stands over a river or lake's water (a mouth, a
	// flooded estuary), the sea draws it: one surface, not two layers.
	if (field && water_sea_masked && v_world.y <= water_sea_level_now + 0.05
			&& water_sea_reach_at(v_world.xz, water_sea_level_now) >= 0.5) {
		discard;
	}
	float depth_m = max(scene_depth - water_depth_here, 0.0);
	float depth = clamp(depth_m / (falling ? water_river_shallow_depth : water_shallow_depth), 0.0, 1.0);

	vec3 colour = texture(water_palette, vec2(depth, 0.5)).rgb;
	ROUGHNESS = water_roughness;
	SPECULAR = 0.5;
	if (field) {
		vec3 field_normal = NORMAL;
		vec4 surface = _field_surface(depth_m, v_flow, v_width, v_world, field_normal, VIEW_MATRIX,
			CAMERA_POSITION_WORLD, TIME);
		NORMAL = field_normal;
		ALPHA = surface.a;
		ALBEDO = foliage_apply_distance_tint(surface.rgb, v_world, CAMERA_POSITION_WORLD);
		float narrow = 1.0 - smoothstep(water_narrow_start, water_narrow_end, v_width);
		SPECULAR = mix(0.5, 0.5 * water_narrow_reflection, narrow);
		ROUGHNESS = mix(water_roughness, 0.18, narrow);
	} else if (falling) {
		vec3 flow_normal = NORMAL;
		vec4 surface = _flowing_surface(colour, depth, depth_m, UV, v_flow, v_world,
			flow_normal, VIEW_MATRIX, CAMERA_POSITION_WORLD, TIME, true);
		NORMAL = flow_normal;
		ALPHA = surface.a;
		ALBEDO = foliage_apply_distance_tint(surface.rgb, v_world, CAMERA_POSITION_WORLD);
	} else {
		// Two ripple octaves, different scale and direction, so the pattern does
		// not repeat in lockstep -- the same anti-tiling reasoning as the
		// terrain's close-range colour noise (terrain.gdshader).
		vec2 dir = normalize(water_wind_direction);
		vec2 ruv = v_world.xz * water_ripple_scale - dir * (TIME * water_wind_speed * 2.0) - foliage_wind_scroll;
		float e = 0.35;
		float h0 = texture(water_ripple_noise, ruv).r;
		float hx = texture(water_ripple_noise, ruv + vec2(e, 0.0)).r - h0;
		float hz = texture(water_ripple_noise, ruv + vec2(0.0, e)).r - h0;
		vec2 ruv2 = v_world.xz * water_ripple_scale * 2.3 + dir.yx * (TIME * water_wind_speed * 3.1);
		float h0b = texture(water_ripple_noise, ruv2).r;
		float hxb = texture(water_ripple_noise, ruv2 + vec2(e, 0.0)).r - h0b;
		float hzb = texture(water_ripple_noise, ruv2 + vec2(0.0, e)).r - h0b;
		float ripple = water_ripple_strength * foliage_gust_scale;
		// Surf: the wave's slope, and whitewater where it breaks. Under the
		// surf the wave shape, not the wind chop, is what shows.
		float foam = 0.0;
		float face = 0.0;
		vec4 shade = vec4(0.0);
		vec4 wave = vec4(0.0);
		if (water_is_sea > 0.5 && surf_enabled) {
			// The depth over the ground actually drawn under this pixel (from
			// the depth buffer), not the coarse bed map: that map smears the
			// beach out over the first few tens of metres of sea, which is
			// exactly where the surf breaks.
			vec3 bed = (INV_VIEW_MATRIX * vec4(view.xyz, 1.0)).xyz;
			float sea_depth = raw_depth > 0.0 ? max(water_sea_level_now - bed.y, 0.0) : water_depth_at(v_world.xz);
			surf_both(v_world.xz, sea_depth, TIME, true, wave, shade);
			ripple *= 1.0 - 0.7 * shade.w;
		}
		vec3 world_normal = normalize(vec3(0.0, 1.0, 0.0) + vec3(-(hx + hxb * 0.5), 0.0, -(hz + hzb * 0.5)) * ripple);
		if (water_is_sea > 0.5 && surf_enabled) {
			world_normal = normalize(world_normal + vec3(-wave.y, 0.0, -wave.z));
			if (shade.x + shade.y > 0.001) {
				float lace = texture(water_ripple_noise, v_world.xz * 0.11 + vec2(0.0, TIME * 0.02)).r;
				float lace2 = texture(water_ripple_noise, v_world.xz * 0.31 - vec2(TIME * 0.03, 0.0)).r;
				float broken = smoothstep(0.45, 0.62, lace * 0.6 + lace2 * 0.4);
				foam = max(shade.x * mix(0.7, 1.0, lace2), shade.y * broken) * water_surf_foam;
			}
			face = shade.z;
		}
		NORMAL = normalize((VIEW_MATRIX * vec4(world_normal, 0.0)).xyz);

		float ndotv = clamp(dot(world_normal, normalize(CAMERA_POSITION_WORLD - v_world)), 0.0, 1.0);
		float fresnel = pow(1.0 - ndotv, water_fresnel_power) * water_fresnel_strength;
		// The wave face shows the water's own deep colour, not the sky.
		colour = mix(colour, vec3(1.0), fresnel * (1.0 - 0.75 * face));
		colour = mix(colour, texture(water_palette, vec2(0.7, 0.5)).rgb * 0.85, face * 0.55);
		colour = mix(colour, water_foam_colour, foam);
		ROUGHNESS = mix(water_roughness, 0.6, foam);
		// Foam scatters light: a touch of its own so it stays white under a
		// storm sky.
		EMISSION = water_foam_colour * foam * 0.12;

		ALBEDO = foliage_apply_distance_tint(colour, v_world, CAMERA_POSITION_WORLD);
		// Shallow water lets more of the (already blended-in) ground colour read
		// through, fading all the way to invisible right at the water's edge --
		// paired with the swell fade above, so the last sliver of a shore reads
		// as a soft blend into the (already damp-looking, per terrain.gdshader)
		// ground rather than a hard, animated line.
		ALPHA = max(clamp(depth * 3.0, 0.0, 0.92), max(face * 0.85, foam * 0.95) * smoothstep(0.0, 0.05, depth_m));
	}
}
