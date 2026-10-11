shader_type canvas_item;
render_mode unshaded;
uniform sampler2D color_lut : filter_nearest, repeat_disable;
uniform bool enabled = true;

void fragment() {
	vec4 source = texture(TEXTURE, UV);
	vec3 color = source.rgb;
	vec3 cube = floor(clamp(color,0.0,1.0) * 15.0 + 0.5);
	vec2 lookup = vec2((cube.r + cube.b * 16.0 + 0.5) / 256.0, (cube.g + 0.5) / 16.0);
	COLOR = vec4(enabled ? texture(color_lut, lookup).rgb : source.rgb, source.a);
}
