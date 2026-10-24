// Дальний рельеф (LOD): цвет по вершинам, без текстур. Внутри радиуса прорисованных чанков
// фрагменты отбрасываются — там рисуются настоящие блоки; рельеф опущен на 0,3 блока, поэтому
// в полосе перекрытия блоки всегда сверху и нет мерцания.
shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_back, diffuse_burley, specular_schlick_ggx;

uniform float clip_radius = 180.0;
uniform float roughness_value = 0.92;
uniform bool water = false;

void fragment() {
	vec3 world = (INV_VIEW_MATRIX * vec4(VERTEX, 1.0)).xyz;
	if (distance(world.xz, CAMERA_POSITION_WORLD.xz) < clip_radius) {
		discard;
	}
	ALBEDO = COLOR.rgb;
	ROUGHNESS = water ? 0.06 : roughness_value;
	SPECULAR = water ? 0.6 : 0.3;
}
