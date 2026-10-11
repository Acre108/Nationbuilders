shader_type spatial;
render_mode cull_disabled, diffuse_lambert, specular_disabled;
#include "res://atmosphere/shaders/atmosphere_clouds.gdshaderinc"
#include "res://atmosphere/shaders/atmosphere_ground.gdshaderinc"
global uniform float foliage_gust_scale;
#include "res://render/village_art.gdshaderinc"
uniform sampler2D nature_texture : source_color, hint_default_white, filter_linear_mipmap;
uniform vec4 nature_colour : source_color = vec4(1.0);
uniform float nature_alpha_cut = 0.0;
uniform vec4 nature_recolour : source_color = vec4(1.0, 1.0, 1.0, 0.0);
varying vec3 world_position;
varying float leaf;
varying vec3 crown_position;
varying vec3 world_normal;
varying float tree_tone;
uniform int map_plant_kind = 0;
uniform float map_wind_scale = 0.0;
void vertex() {
	leaf = COLOR.g;
	crown_position = VERTEX;
	tree_tone = fract(sin(dot(MODEL_MATRIX[3].xz, vec2(17.13, 37.71))) * 4217.3);
	if (leaf > 0.5 && map_plant_kind == 1) {
		// Rounded crown normals soften leaf-card noise at map scale.
		NORMAL = normalize(mix(NORMAL, normalize(VERTEX - vec3(0.0, 0.55, 0.0)), 0.8));
	}
	if (map_plant_kind > 0) {
		float root_weight = pow(clamp(UV2.x, 0.0, 1.0), 1.7);
		float gust = village_gust(MODEL_MATRIX[3].xyz, village_wind_time);
		vec3 world_bend = vec3(village_wind_direction.x, 0.0, village_wind_direction.y);
		vec3 local_bend = normalize(inverse(mat3(MODEL_MATRIX)) * world_bend);
		float strength = 0.09 * map_wind_scale * village_wind_strength / 0.16 * gust;
		VERTEX += local_bend * root_weight * strength;
		NORMAL = normalize(NORMAL - local_bend * root_weight * strength * 0.5);
	}
	world_normal = normalize(MODEL_NORMAL_MATRIX * NORMAL);
	world_position = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}
void fragment() {
	vec4 texel = texture(nature_texture, UV) * nature_colour;
	if (leaf > 0.5 && map_plant_kind == 1) {
		vec4 clustered = textureLod(nature_texture, UV, village_canopy_fullness * 1.5) * nature_colour;
		texel = mix(texel, clustered, village_canopy_fullness);
	}
	if (texel.a < nature_alpha_cut * 0.45) discard;
	vec3 base = texel.rgb;
	if (nature_recolour.a > 0.0) {
		float detail = dot(base, vec3(0.2126, 0.7152, 0.0722)) / max(dot(nature_recolour.rgb, vec3(0.2126, 0.7152, 0.0722)), 0.001);
		base = mix(base, nature_recolour.rgb * clamp(detail, 0.3, 1.6), nature_recolour.a);
	}
	if (leaf > 0.5 && map_plant_kind == 1) {
		float facing = max(0.0, dot(normalize(world_normal), normalize(atmosphere_sun_direction)));
		float cluster = fract(sin(dot(floor(crown_position * 4.0), vec3(17.13, 37.71, 91.17))) * 4217.3);
		float detail = 0.35 + floor(cluster * 3.0) / 3.0 * 0.5;
		vec3 cool = mix(vec3(0.045, 0.12, 0.10), vec3(0.12, 0.24, 0.14), detail);
		vec3 warm = mix(vec3(0.26, 0.32, 0.07), vec3(0.54, 0.48, 0.12), detail);
		float sunward = smoothstep(0.32, 0.88, facing);
		vec3 canopy = mix(cool, warm, sunward * village_canopy_highlights);
		canopy *= mix(0.90, 1.10, tree_tone);
		base = mix(base, canopy, village_forest_darkness);
		if (!FRONT_FACING) NORMAL = -NORMAL;
	}
	ALBEDO = atmosphere_wet_albedo(village_colour_grade(base, world_normal)) * atmosphere_cloud_colour(world_position);
	ROUGHNESS = 1.0;
	BACKLIGHT = vec3(0.035 * leaf);
}
