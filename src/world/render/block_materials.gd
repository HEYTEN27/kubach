class_name BlockMaterials
extends RefCounted
## Материалы поверхностей мешера: opaque, cutout, transparent, plants (этап 3).
##
## Общие материалы — с постоянным светом light_const (по материалу на значение, кэш for_const()).
## Секции с неоднородным светом получают свои копии с 3D-текстурой света (for_light()).

const SURFACES: Array[StringName] = [&"opaque", &"cutout", &"transparent", &"plants"]
const SHADERS := {
	&"opaque": "res://src/world/render/block_opaque.gdshader",
	&"cutout": "res://src/world/render/block_cutout.gdshader",
	&"transparent": "res://src/world/render/block_transparent.gdshader",
	&"plants": "res://src/world/render/block_plants.gdshader",
}

var textures: BlockTextures
## Поверхность → общий ShaderMaterial (полный дневной свет неба).
var shared := {}
var _const_cache := {}   # [поверхность, Color] → ShaderMaterial


func _init(p_textures: BlockTextures) -> void:
	textures = p_textures
	for surf: StringName in SURFACES:
		var m := ShaderMaterial.new()
		m.shader = load(SHADERS[surf]) as Shader
		m.set_shader_parameter(&"albedo_tex", textures.albedo)
		m.set_shader_parameter(&"normal_tex", textures.normal)
		m.set_shader_parameter(&"orm_tex", textures.orm)
		m.set_shader_parameter(&"block_info", textures.block_info)
		if surf == &"transparent":
			m.render_priority = 1
		shared[surf] = m


## Материал поверхности с 3D-текстурой света секции.
func for_light(surf: StringName, light: Texture3D) -> ShaderMaterial:
	var m: ShaderMaterial = shared[surf].duplicate()
	m.set_shader_parameter(&"use_light_tex", true)
	m.set_shader_parameter(&"light_tex", light)
	return m


## Материал с постоянным светом: x — небо 0…1, yzw — блочный свет (значения квантованы).
func for_const(surf: StringName, light: Color) -> ShaderMaterial:
	if light == Color(1, 0, 0, 0):
		return shared[surf]
	var key := [surf, light]
	var m: ShaderMaterial = _const_cache.get(key)
	if m == null:
		m = shared[surf].duplicate()
		m.set_shader_parameter(&"light_const", Vector4(light.r, light.g, light.b, light.a))
		_const_cache[key] = m
	return m


## Общий параметр для всех материалов (например, normal_depth из настроек графики).
func set_param(param: StringName, value: Variant) -> void:
	for m: ShaderMaterial in shared.values():
		m.set_shader_parameter(param, value)
	for m: ShaderMaterial in _const_cache.values():
		m.set_shader_parameter(param, value)
