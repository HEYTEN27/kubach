// Нативный greedy-мешер секции 16×16×16. Повторяет src/world/mesh/greedy_mesher.gd один в один
// (тест tests/unit/world/test_native_mesher.gd сравнивает результаты). Потокобезопасен: после
// setup() только читает свои массивы, все рабочие буферы — локальные.
#pragma once

#include <godot_cpp/classes/ref_counted.hpp>
#include <godot_cpp/variant/array.hpp>
#include <godot_cpp/variant/dictionary.hpp>
#include <godot_cpp/variant/packed_byte_array.hpp>
#include <godot_cpp/variant/packed_color_array.hpp>
#include <godot_cpp/variant/packed_float32_array.hpp>
#include <godot_cpp/variant/packed_int32_array.hpp>
#include <godot_cpp/variant/vector3i.hpp>

#include <vector>

namespace kubach {

class NativeMesher : public godot::RefCounted {
	GDCLASS(NativeMesher, godot::RefCounted)

public:
	void setup(const godot::PackedByteArray &p_render, const godot::PackedByteArray &p_shape,
			const godot::PackedColorArray &p_color, const godot::PackedByteArray &p_tint,
			const godot::PackedFloat32Array &p_tint_strength, const godot::PackedFloat32Array &p_layer_h,
			const godot::PackedByteArray &p_opaque);

	godot::Dictionary mesh_section(const godot::Array &p_center, const godot::Array &p_neighbors,
			const godot::PackedColorArray &p_tints, int p_season, const godot::Vector3i &p_origin) const;

	godot::String version() const;

protected:
	static void _bind_methods();

private:
	std::vector<uint8_t> render;
	std::vector<uint8_t> shape;
	std::vector<godot::Color> color;
	std::vector<uint8_t> tint;
	std::vector<float> tint_strength;
	std::vector<float> layer_h;
	std::vector<uint8_t> opaque;
};

} // namespace kubach
