shader_type spatial;

// Distant trees: one camera-facing card per tree, textured from an atlas that
// TreeImpostorBaker renders at runtime from the real tree meshes.
//
// The atlas has one row per tree variant and 8 columns, one per view angle
// round the tree. Each card picks the column nearest the angle the camera is
// actually seeing its tree from (in the tree's own frame, so instance yaw is
// honoured), and stands up round the Y axis only -- trees seen from a hillside
// should not lean back towards the camera.
//
// Lighting is live, not baked: the atlas stores albedo and the clump normals,
// so an impostor lights exactly like its full tree as the sun moves. Colours
// in the atlas pass through the same sRGB encode as any rendered viewport;
// both samplers use source_color to undo it (for the normals that decoding is
// a numeric round trip, not colour management).
render_mode cull_disabled, world_vertex_coords;

#include "res://foliage/shaders/foliage_common.gdshaderinc"
#include "res://foliage/shaders/foliage_distance.gdshaderinc"
#include "res://render/village_art.gdshaderinc"
#include "res://foliage/shaders/tree_wind.gdshaderinc"
#include "res://foliage/shaders/tree_lod.gdshaderinc"


group_uniforms tree_impostor;
uniform sampler2D impostor_albedo : source_color, filter_linear_mipmap, repeat_disable;
uniform sampler2D impostor_normal : source_color, filter_linear_mipmap, repeat_disable;
uniform int impostor_rows = 1;
uniform int impostor_frames = 8;
// Per row: (frame size in metres, frame centre height above the root).
uniform vec2 impostor_row_size[32];
uniform float impostor_alpha_scissor : hint_range(0.0, 1.0) = 0.5;
// Per row: canopy backlight, roughness, specular. Painted trees and card
// understory share one atlas/draw, but must retain their own light response.
uniform vec3 impostor_surface[32];

varying vec2 v_atlas_uv;
varying vec3 v_axis_x;
varying vec3 v_axis_y;
varying vec3 v_axis_z;
varying float v_root_distance;
varying float v_tint;
varying vec3 v_world;
varying vec3 v_surface;

void vertex() {
	vec3 root = MODEL_MATRIX[3].xyz;
	float scale = length(MODEL_MATRIX[1].xyz);
	mat3 basis = mat3(MODEL_MATRIX[0].xyz, MODEL_MATRIX[1].xyz, MODEL_MATRIX[2].xyz) / scale;
	v_axis_x = basis[0];
	v_axis_y = basis[1];
	v_axis_z = basis[2];

	int row = clamp(int(INSTANCE_CUSTOM.b * float(impostor_rows) + 0.5), 0, impostor_rows - 1);
	vec2 frame = impostor_row_size[row] * scale;
	v_surface = impostor_surface[row];

	vec3 to_camera = CAMERA_POSITION_WORLD - root;
	to_camera.y = 0.0;
	to_camera = length(to_camera) > 0.001 ? normalize(to_camera) : vec3(0.0, 0.0, 1.0);
	vec3 right = normalize(cross(vec3(0.0, 1.0, 0.0), to_camera));

	// View angle in the tree's own frame -> atlas column.
	vec3 local = transpose(basis) * to_camera;
	float angle = atan(local.x, local.z);
	float step_angle = 6.2831853 / float(impostor_frames);
	int column = int(mod(round(angle / step_angle), float(impostor_frames)));

	// The mesh is a unit quad with UV (0,0) top-left.
	vec2 corner = vec2(UV.x - 0.5, 0.5 - UV.y);
	vec3 position = root + right * corner.x * frame.x + vec3(0.0, frame.y + corner.y * frame.x, 0.0);

	// Same sway as the tree it stands in for, by normalised height.
	float tree_height = frame.y * 2.0;
	float h = clamp((position.y - root.y) / max(tree_height, 0.1), 0.0, 1.0);
	VERTEX = position + tree_sway(root, h, tree_height, TIME);
	v_world = VERTEX;

	v_atlas_uv = vec2((float(column) + UV.x) / float(impostor_frames), (float(row) + UV.y) / float(impostor_rows));
	v_root_distance = distance(CAMERA_POSITION_WORLD, root);
	// A little per-tree brightness variation, as the full trees get from
	// their palette jitter.
	v_tint = 0.92 + 0.16 * INSTANCE_CUSTOM.r;
}

void fragment() {
	vec4 albedo = texture(impostor_albedo, v_atlas_uv);
	ALPHA = albedo.a;
	ALPHA_SCISSOR_THRESHOLD = impostor_alpha_scissor;
	if (tree_impostor_fade(v_root_distance) <= tree_dither(FRAGCOORD.xy)) {
		discard;
	}
	ALBEDO = foliage_apply_distance_tint(albedo.rgb * v_tint, v_world, CAMERA_POSITION_WORLD);

	vec3 model_normal = texture(impostor_normal, v_atlas_uv).rgb * 2.0 - 1.0;
	vec3 world_normal = normalize(mat3(v_axis_x, v_axis_y, v_axis_z) * model_normal);
	NORMAL = normalize((VIEW_MATRIX * vec4(world_normal, 0.0)).xyz);

	ROUGHNESS = v_surface.y;
	SPECULAR = v_surface.z;
	BACKLIGHT = vec3(v_surface.x) * ALBEDO;
}
