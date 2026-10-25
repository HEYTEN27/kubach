// Растения крестом (поверхность "plants"): двусторонние спрайты, покачивание на ветру.
shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_disabled, diffuse_burley, specular_schlick_ggx;

#include "res://src/world/render/block_common.gdshaderinc"

uniform float backlight = 0.45;
uniform float sway_amount = 0.12;

vec3 kb_wind_offset(vec3 world_pos, float weight, float time) {
	float phase = dot(world_pos.xz, vec2(0.37, 0.21));
	float gust = sin(time * 0.6 + world_pos.x * 0.05) * 0.5 + 0.5;
	float s = sin(time * (1.6 + wind.w) + phase) * (0.6 + 0.4 * gust);
	vec2 dir = wind.xy;
	return vec3(dir.x, 0.0, dir.y) * s * wind.z * sway_amount * weight * weight;
}

void vertex() {
	KB_VERTEX_COMMON
	VERTEX += kb_wind_offset(v_world, UV2.y, TIME);
	// Нормаль ближе к вертикали: крест освещается как пучок травы, а не как две плоскости.
	NORMAL = normalize(mix(NORMAL, vec3(0.0, 1.0, 0.0), 0.65));
}

void fragment() {
	vec4 c = texture(albedo_tex, vec3(clamp(UV, vec2(0.002), vec2(0.998)), v_info.x));
	vec4 orm = texture(orm_tex, vec3(clamp(UV, vec2(0.002), vec2(0.998)), v_info.x));
	vec4 L = kb_light(v_local, v_n);
	float sky = kb_curve(L.x);
	vec3 albedo = kb_tinted(v_info.x < 0.0 ? v_block.rgb : c.rgb, v_tint, 1.0);
	ALBEDO = albedo * mix(1.0, kb_cloud_shadow(v_world), sky) * mix(1.0, 0.8, rain_wetness.x * smoothstep(0.9, 0.99, L.x));
	ALPHA = v_info.x < 0.0 ? 1.0 : c.a;
	ALPHA_SCISSOR_THRESHOLD = 0.5;
	ROUGHNESS = mix(orm.g, 0.35, rain_wetness.x * smoothstep(0.9, 0.99, L.x));
	// Низ куста темнее — самозатенение.
	AO = mix(0.55, 1.0, UV2.y) * mix(cave_ambient, 1.0, sky);
	AO_LIGHT_AFFECT = 1.0;
	BACKLIGHT = ALBEDO * backlight * sky;
	// Пламя факела светится (ORM.A — маска свечения из texgen).
	EMISSION = albedo * (L.yzw * block_light_energy + orm.a * v_info.w);
}
