shader_type spatial;
render_mode cull_disabled;

// Procedural windows for geographic placeholder walls. Not a facade kit: one
// generic grid per storey, so the future building editor still replaces the
// whole placeholder. Mesh inputs (PlaceholderWindows):
//   UV.x  metres along this wall, UV.y metres above the wall base
//   UV2.x this wall's length, UV2.y the building's seed (negative = no windows)
//   COLOR.r wall height / 64
// After dusk a seeded share of windows glows warm (atmosphere_night_lights).

global uniform float atmosphere_night_lights;

uniform vec3 wall_colour : source_color = vec3(0.788, 0.757, 0.675);
uniform vec3 glass_colour : source_color = vec3(0.17, 0.2, 0.24);
uniform vec3 frame_colour : source_color = vec3(0.86, 0.85, 0.8);
uniform vec3 lit_colour : source_color = vec3(1.0, 0.6, 0.28);
uniform float storey = 3.0;
uniform float bay = 3.2;
uniform vec2 window_size = vec2(1.2, 1.4);
uniform float sill = 0.95;
// Share of windows lit at full night.
uniform float lit_share : hint_range(0.0, 1.0) = 0.45;
uniform float lit_energy = 1.4;

float hash(vec3 p) {
	p = fract(p * 0.1031);
	p += dot(p, p.zyx + 31.32);
	return fract((p.x + p.y) * p.z);
}

void fragment() {
	ALBEDO = wall_colour;
	ROUGHNESS = 0.95;
	float seed = UV2.y;
	float wall_len = UV2.x;
	float wall_h = COLOR.r * 64.0;
	int bays = int(floor(wall_len / bay));
	if (seed >= 0.0 && bays >= 1 && wall_h >= storey * 0.9) {
		float margin = (wall_len - float(bays) * bay) * 0.5;
		float along = UV.x - margin;
		float cell_x = floor(along / bay);
		float fx = along - cell_x * bay - bay * 0.5;
		// Base sits 0.5 m below the lowest ground point; floors count from there.
		float h = UV.y - 0.5;
		float cell_y = floor(h / storey);
		float fy = h - cell_y * storey - sill;
		// Only full storeys below the wall top, and bays inside the wall.
		bool inside = cell_x >= 0.0 && cell_x < float(bays) && h >= 0.0
			&& (cell_y + 1.0) * storey <= wall_h + 0.2;
		vec2 half_size = window_size * 0.5;
		vec2 q = vec2(abs(fx), abs(fy - half_size.y));
		if (inside && q.x < half_size.x + 0.08 && q.y < half_size.y + 0.08) {
			if (q.x < half_size.x && q.y < half_size.y) {
				float h1 = hash(vec3(cell_x, cell_y, seed));
				float h2 = hash(vec3(cell_y + 7.1, cell_x * 1.3, seed + 3.7));
				// Lit windows come on at slightly different times through dusk.
				float on = step(h1, lit_share) * smoothstep(h2 * 0.5, h2 * 0.5 + 0.3, atmosphere_night_lights);
				ALBEDO = glass_colour;
				ROUGHNESS = 0.18;
				SPECULAR = 0.6;
				vec3 tint = mix(lit_colour, vec3(1.0, 0.78, 0.52), h2 * 0.5);
				// Brighter low in the pane: a lamp inside, not a lightbox.
				float falloff = mix(1.0, 0.7, clamp((fy - half_size.y) / window_size.y + 0.5, 0.0, 1.0));
				EMISSION = tint * on * lit_energy * mix(0.6, 1.0, h1 / max(lit_share, 0.001)) * falloff;
			} else {
				ALBEDO = frame_colour;
				ROUGHNESS = 0.7;
			}
		}
	}
}
