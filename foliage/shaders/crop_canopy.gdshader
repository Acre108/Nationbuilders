shader_type spatial;
render_mode cull_disabled;
// Mid-distance crop canopy (SiteCropLayer._build_canopy): one material for
// every field. Per vertex: COLOR.rgb the crop's field colour for the day,
// COLOR.a 1 where the crop has tramlines, UV.x row spacing, UV2 row direction.
uniform float near_radius=85.0;
uniform vec4 furrow_shade : source_color=vec4(.62,.62,.58,1.0);
varying vec3 world_position;
varying vec3 leaf_colour;
varying float tramlines;
varying float row_spacing;
varying vec2 row_direction;

void vertex() {
	world_position=(MODEL_MATRIX*vec4(VERTEX,1.0)).xyz;
	leaf_colour=COLOR.rgb;
	tramlines=COLOR.a;
	row_spacing=max(UV.x,.1);
	row_direction=UV2;
}
void fragment() {
	vec2 across=vec2(-row_direction.y,row_direction.x);
	float row=dot(world_position.xz,across)/row_spacing;
	float width=max(fwidth(row),.025);
	float gap=abs(fract(row)-.5);
	float leaf=1.0-smoothstep(.32-width,.45+width,gap);
	// Two tyre lanes per machinery pass; no invented access roads through crops.
	float tram=abs(mod(row+11.0,22.0)-11.0);
	float wheel=tramlines*(1.0-smoothstep(.3-width,.6+width,abs(tram-1.0)));
	float near_blend=smoothstep(near_radius*.58,near_radius*.88,distance(CAMERA_POSITION_WORLD,world_position));
	float grain=sin(dot(world_position.xz,row_direction)*5.0)*.035;
	ALBEDO=mix(leaf_colour*furrow_shade.rgb,leaf_colour*(1.0+grain),leaf);
	ROUGHNESS=.95;
	SPECULAR=.1;
	ALPHA=leaf*(1.0-wheel)*near_blend;
	ALPHA_SCISSOR_THRESHOLD=.2;
}
