// Нативное воксельное освещение (свет неба + цветной свет блоков). Повторяет
// src/world/light/voxel_light.gd один в один (тест tests/unit/world/test_voxel_light.gd
// сравнивает результаты). Потокобезопасен: после setup() только читает свои таблицы.
#pragma once

#include <godot_cpp/classes/ref_counted.hpp>
#include <godot_cpp/variant/array.hpp>
#include <godot_cpp/variant/packed_byte_array.hpp>

#include <cstdint>
#include <vector>

namespace kubach {

class NativeLight : public godot::RefCounted {
	GDCLASS(NativeLight, godot::RefCounted)

public:
	void setup(const godot::PackedByteArray &p_att, const godot::PackedByteArray &p_emit);
	godot::Array light_column(const godot::Array &p_columns) const;
	godot::PackedByteArray propagate_sky(const godot::PackedByteArray &p_att, int sx, int sy, int sz) const;
	godot::PackedByteArray propagate_block(const godot::PackedByteArray &p_att, const godot::PackedByteArray &p_emit,
			int ch, int sx, int sy, int sz) const;

protected:
	static void _bind_methods();

private:
	std::vector<uint8_t> att_table;
	std::vector<uint8_t> emit_table;
};

} // namespace kubach
