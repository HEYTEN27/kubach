// Небо этапа 7 (разделы 3.1, 3.3, 16 ТЗ): градиент рассеяния с зарёй, диск солнца с ореолом,
// луна с фазой (освещённость полусферы по направлению на солнце, пепельный свет), звёзды и
// Млечный Путь (панорама, медленно вращается за ночь), 2.5D-облака по ветру (плоскость на
// высоте cloud_height, та же текстура и тот же сдвиг, что у теней облаков в шейдерах блоков),
// пасмурная серость, дымка у горизонта, вспышка молнии. Все значения выставляет GraphicsRig.
shader_type sky;

uniform vec3 sun_dir = vec3(0.0, 0.7, -0.7);
uniform vec3 moon_dir = vec3(0.0, -0.7, 0.7);
uniform vec3 sun_color : source_color = vec3(1.0, 0.97, 0.92);
uniform float daylight = 1.0;
uniform float moon_phase = 0.5;
uniform float moon_light = 0.2;
uniform float moon_radius = 0.04;
uniform float sun_radius = 0.0095;
uniform sampler2D moon_tex : source_color, filter_linear, repeat_disable;
uniform sampler2D stars_tex : source_color, filter_linear, repeat_enable;
uniform mat3 star_rotation = mat3(1.0);
uniform float star_brightness = 1.0;
uniform sampler2D clouds_tex : filter_linear_mipmap, repeat_enable;
// Позиция камеры на плоскости облаков в долях плитки (с ветровым сдвигом).
uniform vec2 cloud_origin = vec2(0.0);
uniform float cloud_height = 180.0;
uniform float cloud_tile = 1024.0;
uniform float cloud_cover = 0.3;
uniform int cloud_quality = 2;
// Пасмурная темнота 0…1 (гроза, ливень).
uniform float darkness = 0.0;
uniform float fog_amount = 0.0;
uniform vec3 fog_color : source_color = vec3(0.6, 0.65, 0.7);
uniform vec3 dust_color : source_color = vec3(0.78, 0.66, 0.46);
uniform float dust = 0.0;
uniform float flash = 0.0;

const vec3 ZENITH_DAY = vec3(0.16, 0.34, 0.74);
const vec3 HORIZON_DAY = vec3(0.6, 0.73, 0.9);
const vec3 ZENITH_NIGHT = vec3(0.0025, 0.004, 0.012);
const vec3 HORIZON_NIGHT = vec3(0.014, 0.02, 0.04);
const vec3 TWILIGHT = vec3(1.0, 0.42, 0.16);
const vec3 OVERCAST = vec3(0.55, 0.58, 0.62);

// Плотность облаков в точке плоскости uv (в плитках). detail — мелкие клочья (качество «высокое»).
float cloud_density(vec2 uv, float cover, bool detail) {
	float d = texture(clouds_tex, uv).r;
	if (detail) {
		d = d * 0.72 + texture(clouds_tex, uv * 4.3 + vec2(0.37, 0.11)).g * 0.28;
	}
	float thr = mix(0.86, 0.12, cover);
	return smoothstep(thr, thr + 0.22, d);
}

void sky() {
	vec3 dir = EYEDIR;
	float h = max(dir.y, 0.0);
	float grad = pow(1.0 - h, 3.0);
	float sun_h = sun_dir.y;
	float sun_dot = dot(dir, sun_dir);
	float overcast = smoothstep(0.55, 1.0, cloud_cover);
	float dim = 1.0 - darkness * 0.75;

	// Рассеяние: день ↔ ночь, заря у горизонта со стороны солнца.
	vec3 day = mix(ZENITH_DAY, HORIZON_DAY, grad);
	vec3 night = mix(ZENITH_NIGHT, HORIZON_NIGHT, grad);
	vec3 col = mix(night, day, daylight);
	float low = exp(-abs(sun_h) * 7.0);
	float toward = pow(sun_dot * 0.5 + 0.5, 3.0);
	col += TWILIGHT * low * toward * grad * 0.9 * (0.25 + daylight) * (1.0 - overcast);
	col = mix(col, col * vec3(1.05, 0.9, 1.1), low * (1.0 - toward) * 0.3);
	// Ореол солнца (рассеяние Ми).
	float sun_vis = smoothstep(-0.12, 0.02, sun_h);
	col += sun_color * (pow(max(sun_dot, 0.0), 48.0) * 0.5 + pow(max(sun_dot, 0.0), 6.0) * 0.08) * sun_vis * (1.0 - overcast * 0.85);

	// Пасмурное небо: серая пелена той же яркости, что день.
	vec3 grey = OVERCAST * mix(0.02, 1.0, daylight);
	if (dir.y > 0.0 && cloud_quality > 0) {
		// Сплошная облачность не ровная: тёмные и светлые пятна нижней кромки.
		vec2 ouv = cloud_origin * 1.7 + dir.xz / (dir.y + 0.1) * (cloud_height / cloud_tile) * 0.8;
		grey *= 0.8 + 0.4 * texture(clouds_tex, ouv).b * smoothstep(0.0, 0.25, dir.y);
	}
	col = mix(col, grey, overcast * 0.9);

	if (!AT_CUBEMAP_PASS) {
		// Звёзды и Млечный Путь.
		float night_k = pow(1.0 - daylight, 2.0) * star_brightness * (1.0 - overcast);
		if (night_k > 0.002 && dir.y > -0.05) {
			vec3 sd = star_rotation * dir;
			vec2 suv = vec2(atan(sd.z, sd.x) / TAU, 0.5 - asin(clamp(sd.y, -1.0, 1.0)) / PI);
			vec3 stars = textureLod(stars_tex, suv, 0.0).rgb;
			col += stars * stars * night_k * smoothstep(-0.05, 0.25, dir.y) * 1.4;
		}
		// Луна: полусфера, освещённая со стороны солнца.
		float md = dot(dir, moon_dir);
		if (md > cos(moon_radius * 1.05)) {
			vec3 up0 = abs(moon_dir.y) > 0.98 ? vec3(0.0, 0.0, -1.0) : vec3(0.0, 1.0, 0.0);
			vec3 right = normalize(cross(moon_dir, up0));
			vec3 up = cross(right, moon_dir);
			vec2 muv = vec2(dot(dir, right), dot(dir, up)) / sin(moon_radius);
			float r2 = dot(muv, muv);
			if (r2 < 1.0) {
				vec3 n = vec3(muv, sqrt(1.0 - r2));
				vec3 lgt = vec3(sin(moon_phase * TAU), 0.0, -cos(moon_phase * TAU));
				float lit = smoothstep(-0.04, 0.12, dot(n, lgt));
				vec4 t = texture(moon_tex, vec2(muv.x, -muv.y) * 0.5 + 0.5);
				vec3 mc = t.rgb * (lit * 1.5 + 0.035) * mix(1.0, 0.35, daylight);
				col = mix(col, col * (1.0 - lit * 0.3) + mc, t.a * (1.0 - overcast));
			}
		}
		col += vec3(0.55, 0.65, 1.0) * pow(max(md, 0.0), 300.0) * 0.06 * moon_light * (1.0 - daylight) * (1.0 - overcast);
		// Диск солнца.
		float disc = smoothstep(cos(sun_radius), cos(sun_radius * 0.85), sun_dot);
		col += sun_color * disc * 24.0 * sun_vis * (1.0 - overcast);
	}

	// Облака: плоскость над камерой, светлее со стороны солнца, снизу — темнее.
	if (cloud_quality > 0 && dir.y > 0.0) {
		vec2 uv = cloud_origin + dir.xz / (dir.y + 0.06) * (cloud_height / cloud_tile);
		bool hi = cloud_quality > 1 && !AT_CUBEMAP_PASS;
		float dens = cloud_density(uv, cloud_cover, hi);
		float thick = dens;
		if (hi) {
			// Самозатенение: плотность чуть ближе к солнцу.
			vec2 to_sun = normalize(sun_dir.xz + vec2(1e-4)) * 0.012;
			thick = cloud_density(uv + to_sun, cloud_cover, true);
		}
		vec3 lit_day = mix(vec3(1.02, 1.0, 0.98), sun_color * 1.05, 0.35) * (1.0 - thick * 0.38);
		vec3 lit = mix(vec3(0.018, 0.022, 0.034) * (0.4 + moon_light * 3.0), lit_day, daylight);
		lit += TWILIGHT * low * toward * 0.7 * daylight;
		lit = mix(lit, grey * 0.85, overcast * 0.6);
		lit += sun_color * pow(max(sun_dot, 0.0), 12.0) * 0.35 * daylight * (1.0 - thick);
		float fade = smoothstep(0.0, 0.18, dir.y);
		col = mix(col, lit, dens * fade * (1.0 - overcast * 0.5));
	}

	col *= dim;
	// Низ — цвет дымки: за краем LOD-рельефа нет тёмной полосы.
	if (dir.y < 0.0) {
		col = mix(col, mix(HORIZON_NIGHT, HORIZON_DAY * 0.92, daylight) * dim * mix(1.0, 0.7, overcast), smoothstep(0.0, -0.08, dir.y));
	}
	float haze = pow(1.0 - abs(dir.y), 4.0);
	col = mix(col, fog_color * mix(0.03, 1.0, daylight) * dim, clamp(fog_amount * (0.45 + 0.75 * haze), 0.0, 1.0));
	col = mix(col, dust_color * mix(0.04, 1.0, daylight), clamp(dust * (0.35 + 0.9 * haze), 0.0, 1.0));
	col += vec3(0.75, 0.8, 1.0) * flash * (0.4 + 0.6 * h);
	COLOR = col;
}
