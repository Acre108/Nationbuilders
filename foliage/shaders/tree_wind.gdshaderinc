// Tree sway, shared by every part of a tree: leaves, bark and shadow proxy.
//
// #include AFTER foliage_common.gdshaderinc -- trees ride the same wind field as
// the grass, so a gust visibly crosses the meadow and then the grove, instead
// of the two moving to unrelated rhythms.
//
// Every part must call the SAME sway with the SAME inputs, or a canopy slides
// off its trunk and the shadow proxy swings out of step with the leaves it
// stands in for. So the inputs come only from things all three meshes carry
// identically: the instance origin (the tree's root), the instance scale, and
// UV2, which TreeCardBuilder bakes the same way into every part -- UV2.x is
// normalised height up the tree, UV2.y is the model-space tree height in
// metres.

group_uniforms tree_wind;
// Crown displacement at full gust, as a fraction of tree height.
uniform float tree_sway_strength : hint_range(0.0, 0.2) = 0.035;
// Leaf-level jitter at full gust, in metres. Leaves only (COLOR.g weights it).
uniform float tree_flutter_strength : hint_range(0.0, 0.3) = 0.05;

// Offset of a tree vertex at normalised height `h`, for a tree rooted at
// `root` that is `height` metres tall.
//
// The gust is sampled once, at the root, so the whole tree bends as one body.
// Sampling per vertex would stretch the crown between two different gusts.
// Height squared keeps the base planted, as the grass does.
vec3 tree_sway(vec3 root, float h, float height, float time) {
	if (tree_sway_strength <= 0.0) { return vec3(0.0); }
	float gust = foliage_wind_field(root, time);
	// A slow per-tree rock underneath the gusts, phase-shifted by position, so
	// a grove in steady wind does not freeze and neighbours do not move in
	// lockstep.
	float rock = sin(time * 0.9 + root.x * 0.31 + root.z * 0.47) * 0.3;
	float bend = (gust + rock) * tree_sway_strength * height * h * h;
	if (village_art_enabled) {
		// Keep a gentle rock between gusts; native rasterisation supplies the
		// pixel steps. Scale with height so crowns visibly lean over planted roots.
		float phase = dot(root.xz, vec2(0.31, 0.47));
		float rock = sin(village_wind_time * village_wind_speed * 32.0 + phase);
		bend = clamp(village_wind_strength * height * (village_gust(root, time) * 0.75 + rock * 0.15 * foliage_gust_scale), -0.45, 0.45) * h * h;
	}
	vec2 dir = normalize(foliage_wind_direction);
	if (village_art_enabled) { dir = normalize(village_wind_direction); }
	// Dip slightly as the crown leans, so the tree arcs rather than shears
	// taller.
	return vec3(dir.x * bend, -abs(bend) * h * 0.2, dir.y * bend);
}

// Leaf flutter: small, fast, per-vertex, and scaled by how gusty it is here so
// calm spots are calm. `weight` is 0 on anything that is not a leaf.
vec3 tree_flutter(vec3 world_vertex, float weight, float time) {
	if (village_art_enabled) { return vec3(0.0); }
	float gust = abs(foliage_wind_field(world_vertex, time));
	float phase = dot(world_vertex, vec3(3.1, 2.3, 4.7));
	vec3 wobble = vec3(sin(time * 5.3 + phase), sin(time * 4.1 + phase * 1.3) * 0.6, cos(time * 4.7 + phase));
	return wobble * tree_flutter_strength * (0.35 + gust) * weight;
}

// The full displacement for a tree vertex. Call from vertex() with
// world_vertex_coords on; MODEL_MATRIX carries the instance transform.
vec3 tree_displace(vec3 world_vertex, mat4 model, vec2 uv2, float leaf_weight, float time) {
	vec3 root = model[3].xyz;
	float scale = length(model[1].xyz);
	return world_vertex
		+ tree_sway(root, uv2.x, uv2.y * scale, time)
		+ tree_flutter(world_vertex, leaf_weight, time);
}
