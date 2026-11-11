// Вода, лёд, стекло, лава (поверхность "transparent"). Вода (альфа строки блока < 1) — шейдер
// воды из water.gdshaderinc; лава — бегущая непрозрачная жидкость; лёд и стекло — по альфе текстуры.
shader_type spatial;
render_mode blend_mix, depth_draw_always, cull_disabled, diffuse_burley, specular_schlick_ggx;

#include "res://src/world/render/block_common.gdshaderinc"
#include "res://src/world/render/water.gdshaderinc"

void vertex() {
	KB_VERTEX_COMMON
	KB_TANGENTS
}

void fragment() {
	bool liquid = v_block.a >= 0.0;
	bool water = liquid && v_block.a < 0.99;
	bool flowing = water && v_block.a < 0.71;
	vec2 tuv = kb_face_uv(UV, v_face_axis);
	bool side = abs(v_n.y) < 0.5;
	if (liquid) {
		// Бока жидкости (падающая струя, водопад) бегут вниз, верх — по течению ветра.
		tuv += side ? vec2(0.0, TIME * 1.4) : vec2(TIME * 0.03, TIME * 0.017);
	}
	KbSample s = kb_sample(tuv, v_world, v_n, v_info);
	vec4 L = kb_light(v_local, v_n);
	float sky = kb_curve(L.x);
	vec3 base = kb_tinted(v_info.x < 0.0 ? v_block.rgb : s.albedo.rgb, v_tint, 1.0);
	if (!water) {
		ALBEDO = base * mix(1.0, kb_cloud_shadow(v_world), sky);
		ALPHA = liquid ? 1.0 : clamp(s.albedo.a, 0.3, 1.0);
		NORMAL_MAP = vec3(s.normal_ts.xy * 0.5 + 0.5, 1.0);
		NORMAL_MAP_DEPTH = liquid ? 0.35 : normal_depth;
		ROUGHNESS = liquid ? 0.3 : s.orm.g;
		SPECULAR = 0.5;
		AO = mix(cave_ambient, 1.0, sky);
		AO_LIGHT_AFFECT = 1.0;
		EMISSION = ALBEDO * (L.yzw * block_light_energy + s.orm.a * v_info.w);
	} else {
		vec2 wp = v_world.xz + vec2(world_origin.xz);
		float exposed = smoothstep(0.9, 0.99, L.x);
		// Нормаль: волны Герстнера + детальная текстура + круги (в мировых осях → оси грани).
		vec2 nxy;
		if (!side) {
			vec2 wdir = length(wind.xy) > 0.01 ? normalize(wind.xy) : vec2(1.0, 0.0);
			vec3 g = kw_gerstner(wp, TIME, wdir, wind.z * exposed);
			KbSample s2 = kb_sample(kb_face_uv(UV, v_face_axis) * 0.6 + vec2(-TIME * 0.021, TIME * 0.026), v_world, v_n, v_info);
			vec2 rip = kw_ripples(wp) + kb_ripples(wp, TIME) * rain_wetness.y * 3.0 * exposed;
			// Мировые (x, z) → оси верхней грани: касательная +X, бинормаль −Z.
			nxy = vec2(g.x, -g.z) / max(g.y, 0.2) + (s.normal_ts.xy + s2.normal_ts.xy) * 0.35 + vec2(rip.x, -rip.y);
		} else {
			nxy = s.normal_ts.xy * 0.8;
		}
		NORMAL_MAP = vec3(clamp(nxy * 0.5 + 0.5, 0.0, 1.0), 1.0);
		NORMAL_MAP_DEPTH = 1.0;
		ROUGHNESS = side ? 0.25 : 0.02;
		SPECULAR = 0.5;
		AO = mix(cave_ambient, 1.0, sky);
		AO_LIGHT_AFFECT = 1.0;
		vec3 wcol = base * mix(1.0, kb_cloud_shadow(v_world), sky);
		float light = max(mix(0.04, 1.0, daylight) * sky, max(L.y, max(L.z, L.w)) * 0.6);
		if (water_quality <= 0) {
			ALBEDO = wcol;
			ALPHA = 0.72;
			EMISSION = ALBEDO * L.yzw * block_light_energy;
		} else {
			// Нормаль во вьюпорте после карты нормалей: NORMAL ещё геометрическая — берём свою.
			vec3 vn = normalize(NORMAL + (TANGENT * nxy.x + BINORMAL * nxy.y) * 0.6);
			vec2 ruv = SCREEN_UV + (vn - NORMAL).xy * refraction * 3.0;
			float surf = -VERTEX.z;
			float scene = kw_linear_depth(ruv, INV_PROJECTION_MATRIX);
			if (scene < surf) {
				// За водой то, что перед ней (рука, лодка): без сдвига.
				ruv = SCREEN_UV;
				scene = kw_linear_depth(ruv, INV_PROJECTION_MATRIX);
			}
			float thick = clamp(scene - surf, 0.0, 64.0);
			if (FRONT_FACING == false) {
				thick = min(thick, 2.0);   // взгляд из-под воды: туман даёт подводный режим
			}
			vec3 under = textureLod(screen_tex, ruv, 0.0).rgb;
			// Каустика на дне (по мировой точке дна), гаснет с глубиной и ночью.
			vec3 bottom = (INV_VIEW_MATRIX * vec4(kw_view_pos(ruv, INV_PROJECTION_MATRIX), 1.0)).xyz;
			vec2 bwp = bottom.xz + vec2(world_origin.xz);
			float caust = kw_caustic(bwp, TIME) * daylight * exposed * exp(-thick * 0.35) * smoothstep(0.0, 0.6, thick);
			under *= 1.0 + caust * 1.6;
			vec3 trans = exp(-absorb * thick);
			vec3 deep = wcol * light * 0.55;
			vec3 col = under * trans + deep * (1.0 - trans);
			// Пена: у берега (тонкий слой) и на падающей воде.
			float fnoise = texture(cloud_noise, wp * 0.35 + vec2(TIME * 0.05, 0.0)).g;
			float foam = (1.0 - smoothstep(0.0, 0.45, thick)) * smoothstep(0.35, 0.7, fnoise);
			if (side && flowing) {
				float streak = texture(cloud_noise, vec2(tuv.x * 0.6, tuv.y * 0.15)).g;
				foam = max(foam, smoothstep(0.5, 0.8, streak) * 0.8);
			}
			col = mix(col, vec3(0.92, 0.95, 0.97) * light, clamp(foam, 0.0, 0.85));
			float fres = 0.02 + 0.98 * pow(1.0 - clamp(dot(vn, VIEW), 0.0, 1.0), 5.0);
			if (water_ssr && !side && FRONT_FACING) {
				vec4 r = kw_ssr(VERTEX, vn, VIEW, PROJECTION_MATRIX, INV_PROJECTION_MATRIX);
				col = mix(col, r.rgb, r.a * fres);
				SPECULAR = mix(0.5, 0.05, r.a);
			}
			ALBEDO = vec3(0.0);
			ALPHA = 1.0;
			EMISSION = col * (1.0 - fres * 0.6) + L.yzw * block_light_energy * wcol * 0.3;
		}
	}
}
