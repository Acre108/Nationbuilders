shader_type spatial;
render_mode unshaded, fog_disabled, cull_disabled, depth_draw_never, depth_test_disabled;
uniform sampler2D screen_texture : hint_screen_texture, repeat_disable, filter_nearest;
uniform sampler2D depth_texture : hint_depth_texture, repeat_disable, filter_nearest;
uniform sampler2D normals : hint_normal_roughness_texture, repeat_disable, filter_nearest;
uniform bool enabled = true;
uniform vec3 ink : source_color = vec3(0.10, 0.16, 0.16);

void vertex() {
	POSITION = vec4(VERTEX.xy, 1.0, 1.0);
}
float linear_depth(vec2 uv, mat4 inverse_projection) {
	float depth = texture(depth_texture, uv).r;
	vec4 point = inverse_projection * vec4(uv * 2.0 - 1.0, depth, 1.0);
	return -point.z / point.w;
}
void fragment() {
	vec2 px = 1.0 / VIEWPORT_SIZE;
	float center_depth = linear_depth(SCREEN_UV, INV_PROJECTION_MATRIX);
	vec3 normal = texture(normals, SCREEN_UV).rgb * 2.0 - 1.0;
	float edge = 0.0;
	vec2 offsets[4] = vec2[](vec2(1,0),vec2(-1,0),vec2(0,1),vec2(0,-1));
	for (int i = 0; i < 4; i++) {
		vec2 uv = SCREEN_UV + offsets[i] * px;
		float other = linear_depth(uv, INV_PROJECTION_MATRIX);
		vec3 neighbor = texture(normals, uv).rgb * 2.0 - 1.0;
		// Draw on the far side only: one native pixel at silhouettes.
		edge = max(edge, step(0.30, center_depth - other));
		edge = max(edge, step(0.65, length(normal - neighbor)) * step(0.01, center_depth - other));
	}
	vec3 color = texture(screen_texture, SCREEN_UV).rgb;
	ALBEDO = enabled ? mix(color, ink, edge * 0.68) : color;
}
