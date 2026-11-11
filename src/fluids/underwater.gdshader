// Взгляд из-под воды (этап 8): лёгкое колыхание картинки, оттенок воды и затемнение по краям.
shader_type canvas_item;

uniform sampler2D screen_tex : hint_screen_texture, filter_linear_mipmap;
uniform vec4 tint : source_color = vec4(0.2, 0.45, 0.55, 1.0);
uniform float strength = 1.0;

void fragment() {
	vec2 uv = SCREEN_UV;
	vec2 wob = vec2(sin(uv.y * 28.0 + TIME * 1.9), cos(uv.x * 23.0 + TIME * 1.6)) * 0.0035 * strength;
	vec3 c = textureLod(screen_tex, uv + wob, 0.0).rgb;
	c = mix(c, c * tint.rgb * 1.7, 0.5 * strength);
	float v = smoothstep(0.95, 0.35, length(uv - 0.5));
	COLOR = vec4(c * mix(0.55, 1.0, v), 1.0);
}
