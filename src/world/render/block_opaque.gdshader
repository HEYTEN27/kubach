// Непрозрачные кубы и слои (поверхность "opaque" мешера). Альфа albedo — маска тонирования.
shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_back, diffuse_burley, specular_schlick_ggx;

#include "res://src/world/render/block_common.gdshaderinc"

void vertex() {
	KB_VERTEX_COMMON
	KB_TANGENTS
}

void fragment() {
	KbSample s = kb_sample(kb_face_uv(UV, v_face_axis), v_world, v_n, v_info);
	vec3 base = s.albedo.rgb;
	if (v_info.x < 0.0) {
		base = v_block.rgb;
	}
	ALBEDO = kb_tinted(base, v_tint, s.albedo.a);
	NORMAL_MAP = vec3(s.normal_ts.xy * 0.5 + 0.5, 1.0);
	NORMAL_MAP_DEPTH = normal_depth;
	ROUGHNESS = s.orm.g;
	METALLIC = s.metal;
	vec4 L = kb_light(v_local, v_n);
	float sky = kb_curve(L.x);
	AO = s.orm.r * mix(cave_ambient, 1.0, sky);
	AO_LIGHT_AFFECT = 1.0;
	EMISSION = ALBEDO * (L.yzw * block_light_energy + s.orm.a * v_info.w);
}
