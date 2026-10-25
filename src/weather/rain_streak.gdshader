// Капля дождя (проход отрисовки GPU-частиц): вытянутый штрих вдоль скорости частицы
// (флаг align_y процесса частиц), повёрнутый к камере вокруг этой оси.
shader_type spatial;
render_mode unshaded, blend_mix, depth_draw_never, cull_disabled, skip_vertex_transform, shadows_disabled, fog_disabled;

uniform sampler2D streak_tex : source_color, filter_linear_mipmap;
uniform vec2 size = vec2(0.02, 0.5);
uniform vec4 tint : source_color = vec4(0.8, 0.85, 0.94, 0.6);
// Яркость по дневному свету (ночью капли почти не видно).
uniform float brightness = 1.0;

void vertex() {
	vec3 center = (MODEL_MATRIX * vec4(0.0, 0.0, 0.0, 1.0)).xyz;
	vec3 up = normalize(MODEL_MATRIX[1].xyz);
	vec3 cam = INV_VIEW_MATRIX[3].xyz;
	vec3 side = normalize(cross(up, cam - center));
	vec3 wp = center + side * VERTEX.x * size.x * 2.0 + up * VERTEX.y * size.y * 2.0;
	VERTEX = (VIEW_MATRIX * vec4(wp, 1.0)).xyz;
	NORMAL = vec3(0.0, 0.0, 1.0);
}

void fragment() {
	vec4 t = texture(streak_tex, UV);
	ALBEDO = tint.rgb * brightness;
	ALPHA = t.a * tint.a * COLOR.a;
}
