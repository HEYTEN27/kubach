// Вода, лёд, стекло (поверхность "transparent"). Вода — простая волнистая поверхность;
// полноценная вода с течениями — этап 7.
shader_type spatial;
render_mode blend_mix, depth_draw_always, cull_disabled, diffuse_burley, specular_schlick_ggx;

#include "res://src/world/render/block_common.gdshaderinc"

void vertex() {
	KB_VERTEX_COMMON
	KB_TANGENTS
}

void fragment() {
	bool liquid = v_block.a >= 0.0;
	vec2 tuv = kb_face_uv(UV, v_face_axis);
	if (liquid) {
		tuv += vec2(TIME * 0.03, TIME * 0.017);
	}
	KbSample s = kb_sample(tuv, v_world, v_n, v_info);
	ALBEDO = kb_tinted(v_info.x < 0.0 ? v_block.rgb : s.albedo.rgb, v_tint, 1.0);
	ALPHA = liquid ? v_block.a : clamp(s.albedo.a, 0.3, 1.0);
	NORMAL_MAP = vec3(s.normal_ts.xy * 0.5 + 0.5, 1.0);
	NORMAL_MAP_DEPTH = liquid ? 0.35 : normal_depth;
	ROUGHNESS = liquid ? 0.04 : s.orm.g;
	SPECULAR = 0.5;
	vec4 L = kb_light(v_local, v_n);
	float sky = kb_curve(L.x);
	AO = mix(cave_ambient, 1.0, sky);
	AO_LIGHT_AFFECT = 1.0;
	EMISSION = ALBEDO * (L.yzw * block_light_energy + s.orm.a * v_info.w);
}
