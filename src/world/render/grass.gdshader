// Плотная трава (MultiMesh): пучки из двух скрещённых спрайтов, покачивание на ветру,
// плавное «врастание» в землю у края радиуса. Цвет травы биома — в цвете экземпляра,
// INSTANCE_CUSTOM.r — доля света неба (под кронами меньше).
shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_disabled, diffuse_burley, specular_schlick_ggx;

uniform sampler2DArray albedo_tex : source_color, filter_linear_mipmap_anisotropic, repeat_disable;
uniform float layer = 0.0;
uniform vec3 sprite_color = vec3(0.4, 0.6, 0.3);
uniform float fade_start = 30.0;
uniform float fade_end = 44.0;
uniform float backlight = 0.45;
uniform float sway_amount = 0.16;

global uniform vec4 wind;

varying float v_sky;
varying float v_h;

void vertex() {
	vec3 world = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	float d = distance(world.xz, CAMERA_POSITION_WORLD.xz);
	float s = 1.0 - smoothstep(fade_start, fade_end, d);
	v_h = clamp(VERTEX.y / 0.6, 0.0, 1.0);
	VERTEX.y *= s;
	float phase = dot(NODE_POSITION_WORLD.xz + world.xz, vec2(0.37, 0.21));
	float gust = sin(TIME * 0.5 + world.x * 0.04 + world.z * 0.03) * 0.5 + 0.5;
	float sw = sin(TIME * (1.7 + wind.w) + phase) * (0.55 + 0.45 * gust);
	VERTEX.xz += (inverse(mat3(MODEL_MATRIX)) * vec3(wind.x, 0.0, wind.y)).xz * sw * wind.z * sway_amount * v_h * v_h * s;
	NORMAL = vec3(0.0, 1.0, 0.0);
	v_sky = INSTANCE_CUSTOM.r;
}

void fragment() {
	vec4 c = texture(albedo_tex, vec3(clamp(UV, vec2(0.002), vec2(0.998)), layer));
	ALBEDO = c.rgb / max(sprite_color, vec3(0.05)) * COLOR.rgb;
	ALPHA = c.a;
	ALPHA_SCISSOR_THRESHOLD = 0.5;
	ROUGHNESS = 0.85;
	AO = mix(0.5, 1.0, v_h) * v_sky;
	AO_LIGHT_AFFECT = 0.5;
	BACKLIGHT = ALBEDO * backlight * v_sky;
}
