// Общая часть шейдеров блоков (этап 3). Подключается из block_*.gdshader.
//
// Вершина: UV — координаты в блоках вдоль грани (greedy-прямоугольник), UV2.x — числовой ID
// блока, UV2.y — вес покачивания, COLOR.rgb × 2 — множитель тонирования биомом.
// Слой текстуры: block_info[грань, ID] = (первый слой, вариантов, поворот, свечение).
// Вариант и поворот выбираются хэшем мировой клетки — поэтому greedy-слияние граней не мешает.
//
// Освещение блоков: 3D-текстура секции 18³ (R — небо 0…1, GBA — цвет блочного света) или
// постоянное значение light_const, если свет в секции однородный (instance uniform не годится:
// их буфер ограничен 4096 экземплярами, а секций больше).

uniform sampler2DArray albedo_tex : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2DArray normal_tex : filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2DArray orm_tex : filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D block_info : filter_nearest, repeat_disable;
uniform sampler3D light_tex : filter_linear, repeat_disable;
uniform bool use_light_tex = false;
uniform float normal_depth = 1.0;
// Минимальная доля рассеянного света в полной темноте (пещеры почти чёрные без факела).
uniform float cave_ambient = 0.015;
uniform float block_light_energy = 1.6;
// Параллакс по карте высот (ORM.b) — пресет «Ультра».
uniform bool parallax = false;
uniform float parallax_scale = 0.045;
// Свет секции, если он однородный (без 3D-текстуры): x — небо, yzw — блочный свет.
uniform vec4 light_const = vec4(1.0, 0.0, 0.0, 0.0);

global uniform ivec3 world_origin;
global uniform vec4 wind;   // xy — направление, z — сила 0…1, w — порывы
// Тени облаков (этап 7): xy — сдвиг текстуры облаков (ветер + проекция от солнца), z — облачность,
// w — сила тени. Та же текстура и формула плотности, что в небе (src/graphics/sky.gdshader).
global uniform vec4 cloud_shadow;
// Мокрость: x — накопленная мокрость поверхностей 0…1, y — сила дождя сейчас (круги на лужах).
global uniform vec2 rain_wetness;
global uniform sampler2D cloud_noise : filter_linear_mipmap, repeat_enable;

const float KB_CLOUD_TILE = 1024.0;

varying flat vec4 v_info;
varying flat vec4 v_block;
varying flat int v_face_axis;   // 0 — X, 1 — Y, 2 — Z
varying vec3 v_world;
varying vec3 v_local;
varying vec3 v_tint;
varying flat vec3 v_n;

uint kb_hash(ivec3 c) {
	uint h = uint(c.x) * 0x8da6b343u ^ uint(c.y) * 0xd8163841u ^ uint(c.z) * 0xcb1ab31fu;
	h ^= h >> 16u;
	h *= 0x7feb352du;
	h ^= h >> 15u;
	h *= 0x846ca68bu;
	h ^= h >> 16u;
	return h;
}

// Общая часть vertex(): заполняет варинги (писать их можно только в vertex/fragment).
#define KB_VERTEX_COMMON \
	int kb_id = int(UV2.x + 0.5); \
	int kb_face = NORMAL.y > 0.5 ? 0 : (NORMAL.y < -0.5 ? 1 : 2); \
	v_info = texelFetch(block_info, ivec2(kb_face, kb_id), 0); \
	v_block = texelFetch(block_info, ivec2(3, kb_id), 0); \
	v_face_axis = abs(NORMAL.y) > 0.5 ? 1 : (abs(NORMAL.x) > 0.5 ? 0 : 2); \
	v_world = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz; \
	v_local = VERTEX; \
	v_tint = COLOR.rgb * 2.0; \
	v_n = NORMAL;

// Касательная и бинормаль осевой грани — текстурные оси, как в kb_face_uv(): бинормаль
// смотрит к верху картинки (нормали OpenGL).
#define KB_TANGENTS \
	if (abs(NORMAL.y) > 0.5) { TANGENT = vec3(1.0, 0.0, 0.0); BINORMAL = vec3(0.0, 0.0, -1.0); } \
	else if (abs(NORMAL.x) > 0.5) { TANGENT = vec3(0.0, 0.0, 1.0); BINORMAL = vec3(0.0, 1.0, 0.0); } \
	else { TANGENT = vec3(1.0, 0.0, 0.0); BINORMAL = vec3(0.0, 1.0, 0.0); }

// Непрерывные текстурные координаты грани: верх/низ — (x, z), бока — (u, −y), чтобы верх
// текстуры был сверху блока.
vec2 kb_face_uv(vec2 uv, int face_axis) {
	return face_axis == 1 ? uv : vec2(uv.x, -uv.y);
}

struct KbSample {
	vec4 albedo;
	vec3 normal_ts;   // в осях (касательная, бинормаль, нормаль)
	float metal;
	vec4 orm;
};

// Выборка слоя с учётом варианта и поворота (поворот — на 0/90/180/270° по хэшу клетки).
// world — сценовая позиция фрагмента, n — нормаль грани, info — строка block_info.
KbSample kb_sample(vec2 tuv, vec3 world, vec3 n, vec4 info) {
	KbSample s;
	vec3 inside = world - n * 0.01;
	ivec3 cell = ivec3(floor(inside)) + world_origin;
	uint h = kb_hash(cell);
	float count = max(info.y, 1.0);
	float layer = info.x + float(h % uint(count));
	int rot = info.z > 0.5 ? int((h >> 8u) & 3u) : 0;
	vec2 f = fract(tuv);
	vec2 dx = dFdx(tuv);
	vec2 dy = dFdy(tuv);
	// Поворот координат вокруг центра клетки.
	mat2 r = mat2(1.0);
	if (rot == 1) {
		r = mat2(vec2(0.0, 1.0), vec2(-1.0, 0.0));
	} else if (rot == 2) {
		r = mat2(vec2(-1.0, 0.0), vec2(0.0, -1.0));
	} else if (rot == 3) {
		r = mat2(vec2(0.0, -1.0), vec2(1.0, 0.0));
	}
	vec2 suv = r * (f - 0.5) + 0.5;
	vec3 p = vec3(suv, layer);
	s.albedo = textureGrad(albedo_tex, p, r * dx, r * dy);
	vec4 nm = textureGrad(normal_tex, p, r * dx, r * dy);
	s.orm = textureGrad(orm_tex, p, r * dx, r * dy);
	s.metal = nm.a;
	// Нормаль из текстуры (OpenGL: зелёный — к верху картинки) → в оси грани без поворота.
	vec2 n_uv = vec2(nm.x * 2.0 - 1.0, -(nm.y * 2.0 - 1.0));   // в осях (u, v) текстуры
	vec2 n_face = transpose(r) * n_uv;                         // в осях tuv
	s.normal_ts = normalize(vec3(n_face.x, -n_face.y, nm.z * 2.0 - 1.0));
	return s;
}

// Слой и поворот для клетки (как в kb_sample): x — слой, y — номер поворота.
vec2 kb_layer_rot(vec3 world, vec3 n, vec4 info) {
	ivec3 cell = ivec3(floor(world - n * 0.01)) + world_origin;
	uint h = kb_hash(cell);
	float count = max(info.y, 1.0);
	return vec2(info.x + float(h % uint(count)), info.z > 0.5 ? float((h >> 8u) & 3u) : 0.0);
}

// Простой параллакс: сдвиг текстурных координат по высоте и направлению взгляда в осях грани.
vec2 kb_parallax(vec2 tuv, vec3 world, vec3 n, vec4 info, vec3 view_ts) {
	vec2 lr = kb_layer_rot(world, n, info);
	int rot = int(lr.y);
	mat2 r = mat2(1.0);
	if (rot == 1) {
		r = mat2(vec2(0.0, 1.0), vec2(-1.0, 0.0));
	} else if (rot == 2) {
		r = mat2(vec2(-1.0, 0.0), vec2(0.0, -1.0));
	} else if (rot == 3) {
		r = mat2(vec2(0.0, -1.0), vec2(1.0, 0.0));
	}
	vec2 suv = r * (fract(tuv) - 0.5) + 0.5;
	float h = textureLod(orm_tex, vec3(suv, lr.x), 0.0).b;
	return tuv + vec2(view_ts.x, -view_ts.y) / max(view_ts.z, 0.25) * (h - 0.5) * parallax_scale;
}

// Свет клетки перед гранью: x — небо 0…1, yzw — блочный свет.
// local — позиция в секции, n — нормаль грани.
vec4 kb_light(vec3 local, vec3 n) {
	if (!use_light_tex) {
		return light_const;
	}
	// Срезы текстуры идут по Y (см. VoxelLight.make_images): координаты (x, z, y).
	vec3 p = (local + n * 0.5 + 1.0) / 18.0;
	return texture(light_tex, p.xzy);
}

// Уровень света 0…1 → яркость (каждая ступень на 20% темнее, как в воксельных играх).
float kb_curve(float level) {
	return level <= 0.001 ? 0.0 : pow(0.8, (1.0 - level) * 15.0);
}

vec3 kb_tinted(vec3 albedo, vec3 tint, float mask) {
	return albedo * mix(vec3(1.0), tint, mask);
}

// Доля прямого света под облаками 0…1 в сценовой точке world. Приближение: тень гасит
// альбедо освещённых небом граней (свет из light() трогать дорого).
float kb_cloud_shadow(vec3 world) {
	if (cloud_shadow.w <= 0.001) {
		return 1.0;
	}
	vec2 uv = (world.xz + vec2(world_origin.xz)) / KB_CLOUD_TILE + cloud_shadow.xy;
	float d = texture(cloud_noise, uv).r;
	float thr = mix(0.86, 0.12, cloud_shadow.z);
	return 1.0 - smoothstep(thr, thr + 0.22, d) * cloud_shadow.w;
}

// Круги от капель: смещение нормали (в осях грани) на клетках по 0,5 блока, два слоя.
vec2 kb_ripples(vec2 p, float t) {
	vec2 sum = vec2(0.0);
	for (int i = 0; i < 2; i++) {
		vec2 q = p * 2.0 + float(i) * 0.37;
		vec2 c = floor(q);
		uint h = kb_hash(ivec3(ivec2(c), 17 + i));
		vec2 off = vec2(float(h & 255u), float((h >> 8u) & 255u)) / 255.0 - 0.5;
		float ph = fract(t * (1.1 + 0.3 * float(i)) + float((h >> 16u) & 255u) / 255.0);
		vec2 d = fract(q) - 0.5 - off * 0.4;
		float r = length(d) + 1e-4;
		float ring = exp(-pow((r - ph * 0.42) / 0.035, 2.0)) * (1.0 - ph);
		sum += d / r * ring;
	}
	return sum * 0.6;
}

// Мокрые поверхности под открытым небом (sky_level — свет неба 0…1): темнее и глянцевее,
// на верхних гранях — лужи по низкочастотному шуму, на лужах — круги от капель.
void kb_wet(inout vec3 albedo, inout float rough, inout vec2 nrm_xy, vec3 world, vec3 n, float sky_level, float t) {
	if (rain_wetness.x <= 0.001) {
		return;
	}
	float exposed = smoothstep(0.9, 0.99, sky_level);
	bool top = n.y > 0.5;
	float wet = rain_wetness.x * exposed * (top ? 1.0 : 0.55);
	albedo *= mix(1.0, 0.58 + 0.2 * (1.0 - rough), wet);
	rough = mix(rough, 0.2, wet);
	if (top) {
		vec2 wp = world.xz + vec2(world_origin.xz);
		float pn = texture(cloud_noise, wp / 41.0).b * 0.75 + texture(cloud_noise, wp / 13.0).g * 0.25;
		float puddle = smoothstep(0.6, 0.66, pn) * smoothstep(0.35, 0.85, rain_wetness.x) * exposed;
		albedo *= mix(1.0, 0.6, puddle);
		rough = mix(rough, 0.03, puddle);
		nrm_xy = mix(nrm_xy, kb_ripples(wp, t) * rain_wetness.y, puddle);
	}
}
