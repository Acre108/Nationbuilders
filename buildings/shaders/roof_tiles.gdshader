shader_type spatial;
render_mode cull_disabled;
uniform vec4 tile_colour : source_color = vec4(0.65,0.32,0.22,1.0);
uniform float weathering = 0.0;
void fragment() {
    vec2 courses = UV / vec2(0.32,0.22);
    float row = floor(courses.y);
    vec2 cell = fract(vec2(courses.x + mod(row,2.0)*0.5,courses.y));
    float scallop = cell.y - (0.62 + 0.34*sqrt(max(0.0,1.0-pow((cell.x-0.5)*2.0,2.0))));
    float seam = 1.0-smoothstep(0.01,0.045,abs(scallop));
    float variation = fract(sin(dot(vec2(floor(courses.x+mod(row,2.0)*0.5),row),vec2(12.9898,78.233)))*43758.5453);
    float age = sin(UV.x*1.7+sin(UV.y*0.9))*sin(UV.y*2.3+UV.x*0.3);
    vec3 aged = mix(tile_colour.rgb,tile_colour.rgb*vec3(0.64,0.69,0.59),weathering*(0.5+age*0.5));
    ALBEDO = aged*(0.93+variation*(0.12+weathering*0.32))*(1.0-seam*0.22);
    ROUGHNESS = 0.92;
}
