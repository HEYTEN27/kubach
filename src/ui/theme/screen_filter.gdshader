// Экранный фильтр настроек: гамма, яркость и коррекция цветов для дальтонизма
// (daltonize: симуляция по Machado 2009, ошибка переносится в различимые каналы).
shader_type canvas_item;

uniform sampler2D screen : hint_screen_texture, filter_linear;
uniform float gamma = 1.0;
uniform float brightness = 1.0;
uniform int mode = 0;   // 0 — нет, 1 — протанопия, 2 — дейтеранопия, 3 — тританопия

void fragment() {
	vec3 c = texture(screen, SCREEN_UV).rgb;
	if (mode > 0) {
		mat3 sim;
		if (mode == 1) {
			sim = mat3(vec3(0.152286, 0.114503, -0.003882), vec3(1.052583, 0.786281, -0.048116), vec3(-0.204868, 0.099216, 1.051998));
		} else if (mode == 2) {
			sim = mat3(vec3(0.367322, 0.280085, -0.011820), vec3(0.860646, 0.672501, 0.042940), vec3(-0.227968, 0.047413, 0.968881));
		} else {
			sim = mat3(vec3(1.255528, -0.078411, 0.004733), vec3(-0.076749, 0.930809, 0.691367), vec3(-0.178779, 0.147602, 0.303900));
		}
		vec3 err = c - sim * c;
		c += vec3(0.0, err.r * 0.7 + err.g, err.r * 0.7 + err.b);
	}
	c = pow(max(c * brightness, vec3(0.0)), vec3(1.0 / gamma));
	COLOR = vec4(clamp(c, 0.0, 1.0), 1.0);
}
