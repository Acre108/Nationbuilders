shader_type spatial;

// cull_disabled: blades are single-sided geometry seen from every angle.
// world_vertex_coords: wind is a world-space field, so bending is computed
//   directly in world space. Without this we would need inverse(MODEL_MATRIX)
//   per vertex to get back to model space, which is pure waste on a surface
//   that can push six figures of vertices.
// Alpha-scissored, not blended: sprite cards cut their clump out of the atlas
//   (see fragment()). Blade-geometry styles run the same path with alpha 1.
render_mode cull_disabled, world_vertex_coords;

#include "res://foliage/shaders/foliage_common.gdshaderinc"
#include "res://foliage/shaders/foliage_distance.gdshaderinc"
#include "res://render/village_art.gdshaderinc"

group_uniforms grass;
// Extra darkening towards the base of the blade. Cheap fake AO that stops a
// dense field reading as a flat bright carpet.
uniform float grass_root_darkening : hint_range(0.0, 1.0) = 0.35;
// Blades are lit with a forced +Y normal (see below), which makes them read as
// one soft surface. This dials a little of the true blade normal back in so the
// field is not completely flat-shaded.
uniform float grass_normal_rounding : hint_range(0.0, 1.0) = 0.15;
uniform float grass_translucency : hint_range(0.0, 1.0) = 0.45;
uniform float grass_roughness : hint_range(0.0, 1.0) = 0.9;
// Sampled at the same palette coordinate as the stem, and blended in by the
// mesh's vertex-colour red channel (1 on petals, 0 on stems -- see
// GrassTuftBuilder). This keeps a flower's head on its own palette while its
// stem stays the same green as the surrounding grass. Unused by plain grass
// tufts, whose vertex colour is 0 everywhere.
uniform sampler2D foliage_petal_palette : source_color, hint_default_white, filter_linear, repeat_disable;

group_uniforms grass_sprite;
// 2x2 atlas of clump sprites from tools/blender/make_grass_sprites.py.
// RGB is per-blade brightness, NOT colour -- colour always comes from the
// palette, so one atlas serves every location and season.
uniform sampler2D grass_sprite_atlas : hint_default_white, filter_linear_mipmap, repeat_disable;
// False for the blade-geometry clump styles and for flowers, which carry no
// sprite and must stay fully opaque.
uniform bool grass_sprite_mode = true;
// Imported pack meshes retain texture UV; their height weight is in UV2.x.
uniform bool nature_pack_mode = false;
// Meadow patches (MeadowPatches, Z4): nature-pack tufts carry their patch's
// lushness in INSTANCE_CUSTOM.y, which pack meshes do not use for an atlas
// tile. Thin patches shift up the palette (lighter, drier), lush ones down.
// 0 = off, the default, so a random atlas value is never read as a patch.
uniform float grass_patch_contrast : hint_range(0.0, 1.0) = 0.0;
uniform sampler2D nature_texture : source_color, hint_default_white, filter_linear_mipmap;
uniform vec4 nature_colour : source_color = vec4(1.0);
// Grass, not flowers: the pack's texture keeps each blade's shading, but the
// colour comes from the location's palette, as for every other grass style.
// The texel is divided by the texture's own mean colour (alpha-weighted,
// NatureMeshBuilder.mean_colour()), so a texture's overall tint -- the pack's
// is a bright lime -- drops out and only its variation is kept. This also
// keeps the near and far grass, which use different textures, the same colour.
uniform float nature_palette_tint : hint_range(0.0, 1.0) = 0.0;
uniform vec3 nature_mean_colour = vec3(0.5);
uniform float grass_alpha_scissor : hint_range(0.0, 1.0) = 0.5;
// How strongly the sprite's per-blade brightness modulates the palette colour.
uniform float grass_sprite_tone : hint_range(0.0, 1.0) = 0.8;

group_uniforms grass_lod;
// Which distance band this material draws: 0 = none (every tuft at full size,
// at any distance -- the --card test and LOD-off comparisons), 1 = near,
// 2 = far. Set by GrassLayer; see GrassChunk for how the bands are split.
//
// Transitions are per tuft, never per pixel. Each tuft shrinks to its root at
// a distance chosen from its LOD rank (INSTANCE_CUSTOM.w), so a band boundary
// reads as the field gradually thinning rather than as screen-door dither,
// which crawls when the camera moves.
uniform int grass_lod_band = 0;
// Distance at which the near band has fully handed over to the far band.
uniform float grass_lod_near_end = 32.0;
// Distance at which the last far-band tuft has shrunk into the terrain.
uniform float grass_lod_far_end = 90.0;
// Depth of the thinning zone before each of those two distances.
uniform float grass_lod_fade = 8.0;
// Fraction of tufts (by rank) that survive into the far band.
uniform float grass_lod_far_keep = 0.4;
// How much wider a far-band tuft is drawn, to cover the ground the dropped
// tufts left. Near tufts that survive grow into this across the fade zone, so
// the swap at near_end is between two tufts of identical size.
uniform float grass_lod_far_widen = 1.5;
// Distance over which one tuft shrinks away. Short, so individual tufts do not
// visibly deflate, but not zero, so they do not pop.
uniform float grass_lod_swap_span = 2.0;
// Tints the far band, to see where the handover sits. Debug only.
uniform bool grass_lod_debug = false;

varying float v_height;      // 0 at root, 1 at tip
varying float v_variation;   // per-instance colour jitter
varying float v_petal;       // 0 stem, 1 flower head
varying vec3 v_world;
varying vec2 v_atlas_uv;
varying float v_far;
varying float v_patch;

// Size multiplier for this tuft at distance `d`, and (in .y) how far it has
// widened towards its far-band footprint. `rank` is the tuft's LOD rank.
vec2 lod_scale(float d, float rank) {
	float span = max(grass_lod_swap_span, 0.01);
	float keep = clamp(grass_lod_far_keep, 0.0001, 1.0);
	if (grass_lod_band == 1) {
		if (rank >= keep) {
			// Dropped at range: vanishes somewhere inside the fade zone, spread
			// evenly by rank so the field thins gradually.
			float t = (rank - keep) / max(1.0 - keep, 0.0001);
			float gone = grass_lod_near_end - grass_lod_fade * (1.0 - t);
			return vec2(1.0 - smoothstep(gone - span, gone, d), 0.0);
		}
		// Survives: widens across the fade zone, then hands over at near_end.
		float widen = smoothstep(grass_lod_near_end - grass_lod_fade, grass_lod_near_end, d);
		return vec2(1.0 - smoothstep(grass_lod_near_end - span, grass_lod_near_end, d), widen);
	}
	if (grass_lod_band == 2) {
		// Exact complement of the near band's survivor, so at every distance
		// the two draws of one tuft sum to one full-size tuft.
		float grow = smoothstep(grass_lod_near_end - span, grass_lod_near_end, d);
		float t = rank / keep;
		float gone = grass_lod_far_end - grass_lod_fade * (1.0 - t);
		return vec2(grow * (1.0 - smoothstep(gone - span, gone, d)), 1.0);
	}
	return vec2(1.0, 0.0);
}

void vertex() {
	// UV.y carries the normalised height up the blade, baked by the tuft
	// builder. Using UV rather than VERTEX.y keeps the bend weight correct when
	// an instance is randomly scaled -- VERTEX.y would make tall tufts bend
	// proportionally more and short ones less.
	v_height = nature_pack_mode ? UV2.x : UV.y;
	v_variation = INSTANCE_CUSTOM.x;
	// Pack meshes use COLOR for NatureMeshBuilder's own flags, not petals; read
	// as one, it turned every pack blade into a flower head (petal palette, no
	// root shade).
	v_petal = nature_pack_mode ? 0.0 : COLOR.r;

	// Atlas tile = (this instance's variant + this quad's index) mod 4, so one
	// card shows three different clump sprites crossed and the combination
	// differs per instance. UV.y is height, so texture V is its flip.
	float variant = floor(INSTANCE_CUSTOM.y * 4.0 + 0.5);
	float tile = mod(variant + UV2.x, 4.0);
	vec2 tile_origin = vec2(mod(tile, 2.0), floor(tile * 0.5));
	v_atlas_uv = (vec2(UV.x, 1.0 - UV.y) + tile_origin) * 0.5;
	if (nature_pack_mode) { v_atlas_uv = UV; }
	v_patch = INSTANCE_CUSTOM.y;

	// Per-instance phase offset, so adjacent tufts do not move in lockstep even
	// where they sample nearly the same point of the wind field.
	// LOD. The tuft's root is the instance origin; world_vertex_coords means
	// VERTEX is already world space here and MODEL_MATRIX includes the
	// instance transform. Shrink/widen about the root so a tuft sinks into the
	// ground rather than collapsing towards its middle.
	vec3 root = MODEL_MATRIX[3].xyz;
	vec2 lod = lod_scale(distance(CAMERA_POSITION_WORLD, root), INSTANCE_CUSTOM.w);
	vec3 offset = VERTEX - root;
	offset.xz *= mix(1.0, grass_lod_far_widen, lod.y);
	VERTEX = root + offset * lod.x;
	v_far = float(grass_lod_band == 2);

	float phase = INSTANCE_CUSTOM.z * 6.2831853;
	float gust = foliage_wind_field(VERTEX, TIME + sin(phase) * 0.35);
	if (village_art_enabled) { gust = village_gust(root, TIME); }

	// Weight by height squared: roots stay planted, tips travel. Linear weight
	// makes the whole tuft slide like it is unrooted.
	float bend_weight = v_height * v_height;
	vec2 dir = normalize(foliage_wind_direction);
	// Scaled with the tuft, or a shrunken tuft keeps a full-size sway and its
	// tip swings far outside its own footprint.
	vec3 bend = vec3(dir.x, 0.0, dir.y) * gust * foliage_wind_strength * bend_weight * lod.x;

	// Drop the tip slightly as it bends sideways, so the blade pivots in an arc
	// instead of stretching. Keeps tufts from visibly growing in strong wind.
	bend.y -= abs(gust) * foliage_wind_strength * bend_weight * lod.x * 0.25;

	VERTEX += bend;
	v_world = VERTEX;

	// The brief's key lighting trick: force normals up so a field of separate
	// cards lights as one soft unified surface rather than thousands of
	// individually shaded slivers. The tuft mesh already bakes +Y, but instances
	// can be tilted to follow terrain slope, so re-assert it in world space here
	// -- otherwise grass on a hillside would drift back to per-card shading.
	NORMAL = normalize(mix(vec3(0.0, 1.0, 0.0), NORMAL, grass_normal_rounding));
}

void fragment() {
	// One palette coordinate, two palettes. Sampling both at the same t is what
	// keeps a flower head tonally related to the grass it stands in instead of
	// looking pasted on, and it means a gust moves stem and petal together.
	float t = foliage_palette_t(v_world, TIME, v_variation);
	if (nature_pack_mode && grass_patch_contrast > 0.0) {
		t = clamp(t + (0.5 - v_patch) * grass_patch_contrast, 0.0, 1.0);
	}
	vec3 stem = texture(foliage_palette, vec2(t, 0.5)).rgb;
	vec3 petal = texture(foliage_petal_palette, vec2(t, 0.5)).rgb;
	vec3 base = mix(stem, petal, v_petal);
	if (village_art_enabled) { base = mix(base, base * vec3(0.40, 0.65, 0.67), v_patch * village_forest_darkness); }

	// Written unconditionally rather than inside an `if (grass_sprite_mode)`:
	// the blade-geometry and flower materials simply leave grass_sprite_atlas
	// unbound, and its `hint_default_white` gives alpha 1, so they stay fully
	// opaque through the same code path with no branch needed.
	vec4 sprite = texture(grass_sprite_atlas, v_atlas_uv);
	if (nature_pack_mode) {
		vec4 packed_texel = texture(nature_texture, v_atlas_uv) * nature_colour;
		vec3 detail = clamp(packed_texel.rgb / max(nature_mean_colour, vec3(0.02)), vec3(0.4), vec3(1.8));
		base = mix(packed_texel.rgb, base * detail, nature_palette_tint);
		sprite = vec4(1.0, 1.0, 1.0, packed_texel.a);
	}
	ALPHA = sprite.a;
	// Alpha scissor rather than blending: hundreds of thousands of overlapping
	// cards cannot be depth-sorted, so blending would swim as the camera moves.
	// Scissoring keeps grass in the opaque pass at the cost of a depth prepass.
	ALPHA_SCISSOR_THRESHOLD = grass_alpha_scissor;
	// Darken by the sprite's per-blade tone so blades within one clump read as
	// separate overlapping leaves rather than one flat stencil.
	base *= mix(1.0, sprite.r, grass_sprite_tone * float(grass_sprite_mode));

	// Darken towards the root. Squared so the gradient sits low on the blade
	// and the visible upper half stays in the palette's brighter range.
	float root_shade = mix(1.0 - grass_root_darkening, 1.0, v_height * v_height);
	ALBEDO = base * mix(root_shade, 1.0, v_petal);
	ALBEDO = foliage_apply_distance_tint(ALBEDO, v_world, CAMERA_POSITION_WORLD);
	if (village_art_enabled) { ALBEDO = village_colour_grade(ALBEDO, vec3(0.0, 1.0, 0.0)); }
	if (grass_lod_debug && v_far > 0.5) {
		ALBEDO = mix(ALBEDO, vec3(0.9, 0.2, 0.15), 0.6);
	}

	// Undo Godot's automatic back-face normal flip.
	//
	// `cull_disabled` makes Godot negate NORMAL on back faces, which is right for
	// solid geometry and wrong for this surface: the whole point of forcing +Y
	// (see vertex()) is that a field of cards lights as ONE soft surface. A
	// flipped card gets -Y, loses all diffuse, and renders as a flat wash of
	// BACKLIGHT -- which is what those pale translucent-looking panels scattered
	// through the field actually were. They were never an alpha bug; the pixels
	// were passing the scissor and simply being lit as if facing away from the
	// sun. Restoring +Y here makes both sides of a card light identically.
	if (!FRONT_FACING) {
		NORMAL = -NORMAL;
	}

	ROUGHNESS = grass_roughness;
	SPECULAR = 0.1;
	// Light bleeding through a blade lit from behind -- the single biggest
	// contributor to grass looking soft rather than plastic at low sun angles.
	BACKLIGHT = vec3(grass_translucency) * base;
}
