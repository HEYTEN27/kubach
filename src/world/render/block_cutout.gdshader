// Листва и тонкие слои (поверхность "cutout"): альфа-тест, просвечивание на солнце.
shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_back, diffuse_burley, specular_schlick_ggx;

#include "res://src/world/render/block_common.gdshaderinc"

uniform float backlight = 0.35;

void vertex() {
	KB_VERTEX_COMMON
	KB_TANGENTS
}

void fragment() {
	KbSample s = kb_sample(kb_face_uv(UV, v_face_axis), v_world, v_n, v_info);
	ALBEDO = kb_tinted(v_info.x < 0.0 ? v_block.rgb : s.albedo.rgb, v_tint, 1.0);
	ALPHA = v_info.x < 0.0 ? 1.0 : s.albedo.a;
	ALPHA_SCISSOR_THRESHOLD = 0.5;
	NORMAL_MAP = vec3(s.normal_ts.xy * 0.5 + 0.5, 1.0);
	NORMAL_MAP_DEPTH = normal_depth;
	ROUGHNESS = s.orm.g;
	vec4 L = kb_light(v_local, v_n);
	float sky = kb_curve(L.x);
	AO = s.orm.r * mix(cave_ambient, 1.0, sky);
	AO_LIGHT_AFFECT = 1.0;
	BACKLIGHT = ALBEDO * backlight * sky;
	EMISSION = ALBEDO * L.yzw * block_light_energy;
}
