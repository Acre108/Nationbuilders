shader_type spatial;
render_mode diffuse_lambert, specular_disabled;
void fragment() {
	ALBEDO = COLOR.rgb;
	ROUGHNESS = 1.0;
}
void light() {
	float shade = dot(NORMAL, LIGHT);
	float band = shade > 0.65 ? 1.0 : (shade > 0.1 ? 0.72 : 0.40);
	float illumination = band * ATTENUATION;
	// Dither only actual cast shadows and the darkest lighting band.
	if (ATTENUATION < 0.7 || shade <= 0.1) {
		float checker = mod(floor(FRAGCOORD.x) + floor(FRAGCOORD.y), 2.0) - 0.5;
		illumination = max(0.0, illumination + checker * 0.065);
	}
	DIFFUSE_LIGHT += ALBEDO * LIGHT_COLOR * illumination / 3.14159265;
}
