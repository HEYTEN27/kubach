// Непрозрачные кубы и слои (поверхность "opaque" мешера). Альфа albedo — маска тонирования.
shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_back, diffuse_burley, specular_schlick_ggx;

#include "res://src/world/render/block_common.gdshaderinc"

void vertex() {
	KB_VERTEX_COMMON
	KB_TANGENTS
}

void fragment() {
	vec2 tuv = kb_face_uv(UV, v_face_axis);
	if (parallax && v_info.x >= 0.0) {
		vec3 view_ts = vec3(dot(VIEW, TANGENT), dot(VIEW, BINORMAL), dot(VIEW, NORMAL));
		tuv = kb_parallax(tuv, v_world, v_n, v_info, view_ts);
	}
	KbSample s = kb_sample(tuv, v_world, v_n, v_info);
	vec3 base = s.albedo.rgb;
	if (v_info.x < 0.0) {
		base = v_block.rgb;
	}
	vec3 albedo = kb_tinted(base, v_tint, s.albedo.a);
	vec4 L = kb_light(v_local, v_n);
	float sky = kb_curve(L.x);
	float rough = s.orm.g;
	vec2 nxy = s.normal_ts.xy;
	vec3 emit = albedo * (L.yzw * block_light_energy + s.orm.a * v_info.w);
	kb_wet(albedo, rough, nxy, v_world, v_n, L.x, TIME);
	ALBEDO = albedo * mix(1.0, kb_cloud_shadow(v_world), sky);
	NORMAL_MAP = vec3(nxy * 0.5 + 0.5, 1.0);
	NORMAL_MAP_DEPTH = normal_depth;
	ROUGHNESS = rough;
	METALLIC = s.metal;
	AO = s.orm.r * mix(cave_ambient, 1.0, sky);
	AO_LIGHT_AFFECT = 1.0;
	EMISSION = emit;
}
