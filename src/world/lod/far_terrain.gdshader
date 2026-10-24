// Дальний рельеф (LOD): цвет по вершинам, без текстур. Внутри радиуса прорисованных чанков
// фрагменты отбрасываются — там рисуются настоящие блоки; рельеф опущен на 0,3 блока, поэтому
// в полосе перекрытия блоки всегда сверху и нет мерцания.
shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_back, diffuse_burley, specular_schlick_ggx;

uniform float clip_radius = 180.0;
// Центр прорисованных чанков (сценовые x, z) — игрок, а не камера: в виде от третьего лица
// и в меню камера смещена.
uniform vec2 clip_center = vec2(0.0);
uniform float roughness_value = 0.92;
uniform bool water = false;

void fragment() {
	vec3 world = (INV_VIEW_MATRIX * vec4(VERTEX, 1.0)).xyz;
	if (distance(world.xz, clip_center) < clip_radius) {
		discard;
	}
	ALBEDO = COLOR.rgb;
	ROUGHNESS = water ? 0.06 : roughness_value;
	SPECULAR = water ? 0.6 : 0.3;
}
