// Вода (этап 8, раздел 10 ТЗ). Подключается из block_transparent.gdshader после block_common.
//
// - Волны: сумма 4 волн Герстнера (направления — от ветра) даёт нормаль поверхности, плюс две
//   бегущие детальные нормали из текстуры воды. Вершины не смещаются: верх воды — крупные
//   greedy-квады, смещение порвало бы стыки с берегом.
// - Высокое качество: рефракция (экранная текстура, сдвиг по нормали), глубинное затухание
//   (Бугер — Ламберт по толщине слоя из буфера глубины: мелко — прозрачно, глубоко — цвет воды
//   биома), каустика на дне, пена у берега и на падающей воде.
// - SSR (настройка): отражения марш-лучом по буферу глубины; где луч не попал — небо
//   (радиансная карта через обычный specular).
// - Круги от шагов и след плывущего (глобальный ripples: 4 источника x, z, возраст, сила) и
//   от капель дождя (rain_wetness.y).

uniform sampler2D screen_tex : hint_screen_texture, filter_linear_mipmap, repeat_disable;
uniform sampler2D depth_tex : hint_depth_texture, filter_nearest, repeat_disable;
// 0 — низкое (полупрозрачная), 1 — высокое (рефракция, глубина, каустика, пена).
uniform int water_quality = 1;
uniform bool water_ssr = false;
uniform float refraction = 0.06;
// Поглощение за блок толщины: красный гаснет быстрее — глубина синеет и зеленеет.
uniform vec3 absorb = vec3(0.42, 0.14, 0.09);
uniform float wave_strength = 1.0;

global uniform float daylight;
global uniform mat4 ripples;

// Нормаль суммы волн Герстнера в мировой точке p (xz), время t, сила ветра w.
vec3 kw_gerstner(vec2 p, float t, vec2 wdir, float w) {
	vec3 n = vec3(0.0, 1.0, 0.0);
	float amp = (0.25 + w) * wave_strength;
	for (int i = 0; i < 4; i++) {
		float fi = float(i);
		float ang = (fi - 1.5) * 0.55 + fi * fi * 0.13;
		vec2 d = normalize(mat2(vec2(cos(ang), sin(ang)), vec2(-sin(ang), cos(ang))) * wdir);
		float lambda = 7.0 / (1.0 + fi * 0.9);
		float k = TAU / lambda;
		float c = sqrt(9.8 / k);
		float a = 0.035 * lambda * amp / (1.0 + fi);
		float f = k * (dot(d, p) - c * t);
		float wa = k * a;
		n.x -= d.x * wa * cos(f);
		n.z -= d.y * wa * cos(f);
		n.y -= 0.4 * wa * sin(f);
	}
	return normalize(n);
}

// Расходящиеся круги от источников ripples: смещение нормали (мировые x, z).
vec2 kw_ripples(vec2 p) {
	vec2 sum = vec2(0.0);
	for (int i = 0; i < 4; i++) {
		vec4 r = ripples[i];
		if (r.w <= 0.0) {
			continue;
		}
		vec2 d = p - r.xy;
		float dist = length(d) + 1e-4;
		float front = r.z * 1.6;
		float ring = sin((dist - front) * 9.0) * exp(-pow((dist - front) / 0.5, 2.0));
		sum += d / dist * ring * r.w * exp(-r.z * 0.9);
	}
	return sum * 0.5;
}

float kw_linear_depth(vec2 uv, mat4 inv_proj) {
	float d = textureLod(depth_tex, uv, 0.0).r;
#if CURRENT_RENDERER == RENDERER_COMPATIBILITY
	vec3 ndc = vec3(uv, d) * 2.0 - 1.0;
#else
	vec3 ndc = vec3(uv * 2.0 - 1.0, d);
#endif
	vec4 v = inv_proj * vec4(ndc, 1.0);
	return -v.z / v.w;
}

vec3 kw_view_pos(vec2 uv, mat4 inv_proj) {
	float d = textureLod(depth_tex, uv, 0.0).r;
#if CURRENT_RENDERER == RENDERER_COMPATIBILITY
	vec3 ndc = vec3(uv, d) * 2.0 - 1.0;
#else
	vec3 ndc = vec3(uv * 2.0 - 1.0, d);
#endif
	vec4 v = inv_proj * vec4(ndc, 1.0);
	return v.xyz / v.w;
}

// Каустика: сетка светлых линий из двух бегущих слоёв шума.
float kw_caustic(vec2 p, float t) {
	float a = texture(cloud_noise, p * 0.11 + vec2(t * 0.013, t * 0.007)).g;
	float b = texture(cloud_noise, p * 0.13 - vec2(t * 0.009, -t * 0.011)).g;
	return pow(1.0 - abs(a - b), 9.0);
}

// Отражение марш-лучом в экранном пространстве: rgb — цвет, a — уверенность попадания.
vec4 kw_ssr(vec3 vpos, vec3 vn, vec3 view, mat4 proj, mat4 inv_proj) {
	vec3 r = normalize(reflect(-view, vn));
	if (r.z > 0.2) {
		return vec4(0.0);   // луч к камере — экран не знает, что там
	}
	float stepl = 0.4;
	vec3 p = vpos;
	for (int i = 0; i < 28; i++) {
		p += r * stepl;
		stepl *= 1.18;
		vec4 c = proj * vec4(p, 1.0);
		vec2 uv = c.xy / c.w * 0.5 + 0.5;
		if (uv.x < 0.0 || uv.x > 1.0 || uv.y < 0.0 || uv.y > 1.0) {
			return vec4(0.0);
		}
		float scene = kw_linear_depth(uv, inv_proj);
		float ray = -p.z;
		if (ray > scene && ray - scene < stepl * 2.5) {
			vec2 e = smoothstep(vec2(0.0), vec2(0.08), uv) * smoothstep(vec2(0.0), vec2(0.08), 1.0 - uv);
			return vec4(textureLod(screen_tex, uv, 0.0).rgb, e.x * e.y * (1.0 - float(i) / 28.0));
		}
	}
	return vec4(0.0);
}
