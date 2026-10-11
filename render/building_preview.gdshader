shader_type spatial;
render_mode blend_mix, shadows_disabled;
uniform vec4 tint : source_color = vec4(0.66, 0.77, 0.42, 1.0);

void fragment() {
	ALBEDO = mix(COLOR.rgb, tint.rgb, 0.45);
	ALPHA = 0.45;
	ROUGHNESS = 1.0;
	SPECULAR = 0.0;
}
