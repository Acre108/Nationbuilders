shader_type spatial;
render_mode cull_disabled;

uniform int surface_kind = 0;
uniform bool two_tracks = false;
uniform float route_width = 3.0;
uniform vec4 asphalt_colour : source_color = vec4(.30,.32,.32,1.0);
uniform vec4 gravel_colour : source_color = vec4(.57,.53,.43,1.0);
uniform vec4 earth_colour : source_color = vec4(.40,.34,.24,1.0);
uniform vec4 grass_colour : source_color = vec4(.32,.40,.20,1.0);
uniform vec4 paving_colour : source_color = vec4(.48,.36,.29,1.0);
uniform vec4 shoulder_colour : source_color = vec4(.42,.39,.28,1.0);
varying vec3 world_position;

float grain(vec2 p) { return fract(sin(dot(floor(p),vec2(127.1,311.7)))*43758.5453); }
void vertex() { world_position = (MODEL_MATRIX * vec4(VERTEX,1.0)).xyz; }
void fragment() {
	float fine = grain(world_position.xz*18.0);
	float broad = grain(world_position.xz*1.7);
	vec3 colour = asphalt_colour.rgb;
	if (surface_kind==1) colour=gravel_colour.rgb;
	if (surface_kind==2) colour=earth_colour.rgb;
	if (surface_kind==3) colour=grass_colour.rgb;
	if (surface_kind==4) colour=paving_colour.rgb;
	colour *= .91 + fine*.13 + broad*.05;
	float edge = abs(UV.x-.5)*2.0;
	float shoulder = smoothstep(.80,.98,edge);
	colour = mix(colour,shoulder_colour.rgb,shoulder*.65);
	if (two_tracks) {
		float rut = 1.0-smoothstep(.08,.18,abs(abs(UV.x-.5)-.28));
		colour=mix(grass_colour.rgb,colour,rut);
	}
	if (surface_kind==4) {
		vec2 tile=vec2(UV.x*route_width/.22,UV.y/.32);
		tile.x+=mod(floor(tile.y),2.0)*.5;
		vec2 seam=min(fract(tile),1.0-fract(tile));
		colour*=mix(.7,1.0,smoothstep(.025,.065,min(seam.x,seam.y)));
	}
	ALBEDO=colour;
	ROUGHNESS=.96;
	SPECULAR=.1;
	// Slightly irregular edges with an opaque centre; no broad beige halo.
	ALPHA=1.0-smoothstep(.94,.995,edge+(fine-.5)*.025);
	ALPHA_SCISSOR_THRESHOLD=.35;
}
