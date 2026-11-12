shader_type spatial;
// Животные (этап 9): коробки модели с узором, который рисуется по координатам модели (не по
// миру — узор не «плывёт» при ходьбе). COLOR — основной цвет, CUSTOM0.rgb — второй цвет,
// CUSTOM0.a — узор: 0 шерсть-волос, 1 пятна, 2 руно, 3 перья, 4 кожа, 5 рог/копыто, 6 глаз, 7 клюв.
// Узор даёт и альбедо, и рельеф (нормаль из производных высоты), и шероховатость.

render_mode cull_back, depth_draw_opaque;

uniform float wet = 0.0;
uniform float hurt = 0.0;

varying vec3 p_model;
varying vec4 col2;

float hash3(vec3 p) {
	p = fract(p * 0.3183099 + vec3(0.71, 0.113, 0.419));
	p *= 17.0;
	return fract(p.x * p.y * p.z * (p.x + p.y + p.z));
}

float vnoise(vec3 p) {
	vec3 i = floor(p);
	vec3 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(mix(hash3(i), hash3(i + vec3(1, 0, 0)), f.x), mix(hash3(i + vec3(0, 1, 0)), hash3(i + vec3(1, 1, 0)), f.x), f.y),
		mix(mix(hash3(i + vec3(0, 0, 1)), hash3(i + vec3(1, 0, 1)), f.x), mix(hash3(i + vec3(0, 1, 1)), hash3(i + vec3(1, 1, 1)), f.x), f.y), f.z);
}

float fbm(vec3 p) {
	return vnoise(p) * 0.55 + vnoise(p * 2.1) * 0.28 + vnoise(p * 4.3) * 0.17;
}

// Клетки руна: расстояние до ближайшей «кудряшки».
float curls(vec3 p) {
	vec3 i = floor(p);
	float d = 9.0;
	for (int z = -1; z <= 1; z++)
	for (int y = -1; y <= 1; y++)
	for (int x = -1; x <= 1; x++) {
		vec3 c = i + vec3(float(x), float(y), float(z));
		vec3 o = vec3(hash3(c), hash3(c + 3.1), hash3(c + 7.7));
		d = min(d, length(p - c - o));
	}
	return d;
}

void vertex() {
	p_model = VERTEX;
	col2 = CUSTOM0;
}

// Высота и цвет узора в точке модели (блоки: 1 = 16 px).
void pattern(vec3 p, int kind, vec3 c1, vec3 c2, out vec3 alb, out float h, out float rough) {
	vec3 q = p * 16.0;
	if (kind == 1) {
		// Пятна: крупные пятна неправильной формы + шерсть.
		float n = fbm(q * 0.11 + vec3(3.0));
		float m = smoothstep(0.52, 0.56, n);
		float hair = vnoise(vec3(q.x * 2.0, q.y * 0.35, q.z * 2.0));
		alb = mix(c1, c2, m) * (0.88 + 0.2 * hair);
		h = hair * 0.4;
		rough = 0.85;
	} else if (kind == 2) {
		float d = curls(q * 0.9);
		float b = 1.0 - smoothstep(0.15, 0.75, d);
		alb = mix(c2, c1, b) * (0.9 + 0.12 * vnoise(q * 3.0));
		h = b;
		rough = 0.95;
	} else if (kind == 3) {
		// Перья: ряды чешуек сверху вниз.
		vec2 r = vec2(q.x + q.z, q.y * 1.6);
		float row = floor(r.y);
		float cell = fract(r.x * 0.8 + row * 0.5);
		float edge = smoothstep(0.0, 0.9, fract(r.y)) * (0.6 + 0.4 * abs(cell - 0.5) * 2.0);
		alb = mix(c1, c2, edge * 0.7) * (0.92 + 0.12 * vnoise(q * 2.0));
		h = 1.0 - edge;
		rough = 0.8;
	} else if (kind == 4) {
		float n = fbm(q * 0.6);
		alb = mix(c1, c2, smoothstep(0.45, 0.8, n) * 0.6) * (0.94 + 0.08 * vnoise(q * 4.0));
		h = n * 0.3;
		rough = 0.6;
	} else if (kind == 5) {
		float band = 0.5 + 0.5 * sin(q.y * 3.0 + vnoise(q) * 2.0);
		alb = c1 * (0.8 + 0.25 * band);
		h = band * 0.3;
		rough = 0.45;
	} else if (kind == 6) {
		alb = c1;
		h = 0.0;
		rough = 0.08;
	} else if (kind == 7) {
		alb = c1 * (0.85 + 0.2 * clamp(q.z * 0.2, 0.0, 1.0));
		h = 0.0;
		rough = 0.4;
	} else {
		// Волос: короткие пряди вдоль тела, лёгкая неравномерность цвета.
		float strand = vnoise(vec3(q.x * 2.4, q.y * 0.5, q.z * 2.4));
		float patch = fbm(q * 0.15);
		alb = mix(c1, c2, smoothstep(0.62, 0.7, patch) * 0.85) * (0.86 + 0.24 * strand);
		h = strand * 0.5;
		rough = 0.88;
	}
}

void fragment() {
	int kind = int(round(col2.a * 10.0));
	vec3 alb;
	float h;
	float rough;
	pattern(p_model, kind, COLOR.rgb, col2.rgb, alb, h, rough);
	// Рельеф из производных высоты узора (bump по Миккельсену, в пространстве вида).
	vec3 dpdx = dFdx(VERTEX);
	vec3 dpdy = dFdy(VERTEX);
	vec3 n = normalize(NORMAL);
	vec3 r1 = cross(dpdy, n);
	vec3 r2 = cross(n, dpdx);
	float det = dot(dpdx, r1);
	vec3 grad = sign(det) * (dFdx(h) * r1 + dFdy(h) * r2) * 0.025;
	NORMAL = normalize(abs(det) * n - grad);
	ALBEDO = mix(alb * (1.0 - 0.35 * wet), vec3(0.9, 0.15, 0.1), hurt * 0.55);
	ROUGHNESS = mix(rough, 0.25, wet * 0.7);
	SPECULAR = kind == 6 ? 0.9 : 0.35;
	AO = 0.85 + 0.15 * h;
}
