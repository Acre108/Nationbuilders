shader_type spatial;
render_mode unshaded, cull_disabled, shadows_disabled;
uniform float ao_strength = 0.75;
uniform vec3 shadow_colour : source_color = vec3(0.10, 0.18, 0.15);
void fragment() {
	float radius = length((UV - 0.5) * 2.0);
	float opacity = (1.0 - smoothstep(0.30, 1.0, radius)) * ao_strength;
	// Ordered cutout keeps contact edges in the opaque pixel pass.
	float threshold = mod(FRAGCOORD.x + mod(FRAGCOORD.y, 2.0) * 2.0, 4.0) / 4.0;
	if (opacity <= threshold) { discard; }
	ALBEDO = shadow_colour;
}
