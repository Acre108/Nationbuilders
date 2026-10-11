// Full tree <-> impostor handover, shared by tree_leaf, tree_bark and
// tree_impostor so the two sides stay exact complements.
//
// Over `tree_impostor_band` metres past `tree_impostor_start`, each pixel is
// drawn by the full tree or by the impostor, never both and never neither: the
// full tree discards where fade > dither, the impostor where fade <= dither,
// against the same screen-space dither. The switch reads as a short shimmer at
// distance rather than a pop.
//
// tree_impostor_start = 0 turns the handover off (no impostors baked yet, the
// shadow proxy, the impostor bake itself).

group_uniforms tree_lod;
uniform float tree_impostor_start = 0.0;
uniform float tree_impostor_band = 12.0;

// 0 = full tree, 1 = impostor, at distance `d` from the camera to the root.
float tree_impostor_fade(float d) {
	if (tree_impostor_start <= 0.0) {
		return 0.0;
	}
	return smoothstep(tree_impostor_start, tree_impostor_start + tree_impostor_band, d);
}

// Interleaved gradient noise: a stable per-pixel threshold in 0..1.
float tree_dither(vec2 frag) {
	return fract(52.9829189 * fract(dot(frag, vec2(0.06711056, 0.00583715))));
}
