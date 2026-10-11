shader_type spatial;
render_mode cull_disabled;
// Seasonal tint from SiteCropLayer: rgb target colour, a amount (0 = the
// mesh's own green). Keeps each face's relative brightness.
uniform vec4 crop_tint : source_color = vec4(1.0, 1.0, 1.0, 0.0);
varying vec3 colour;
void vertex() {
	vec3 origin=(MODEL_MATRIX*vec4(VERTEX,1.0)).xyz;
	float bend=pow(clamp(VERTEX.y/2.0,0.0,1.0),2.0);
	VERTEX.x+=sin(TIME*1.5+origin.x*.3+origin.z*.25)*.035*bend;
	colour=COLOR.rgb;
}
void fragment() {
	const vec3 LUMA=vec3(.2126,.7152,.0722);
	float detail=dot(colour,LUMA)/max(dot(crop_tint.rgb,LUMA),.001);
	ALBEDO=mix(colour,crop_tint.rgb*clamp(detail,.5,1.5),crop_tint.a);
	ROUGHNESS=.9;
	SPECULAR=.15;
}
