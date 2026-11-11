// Нативный клеточный автомат жидкостей. Повторяет src/fluids/fluid_sim.gd один в один
// (тест tests/unit/fluids/test_native_fluid.gd сравнивает мир после шагов). Читает блоки прямо
// из ChunkColumn/ChunkSection (GDScript-объекты), лениво и с кэшем на шаг, поэтому работает
// только в главном потоке; свои записи держит в наложении и отдаёт списком изменений.
#pragma once

#include <godot_cpp/classes/ref_counted.hpp>
#include <godot_cpp/variant/array.hpp>
#include <godot_cpp/variant/dictionary.hpp>
#include <godot_cpp/variant/packed_byte_array.hpp>
#include <godot_cpp/variant/packed_int32_array.hpp>
#include <godot_cpp/variant/vector2i.hpp>

#include <cstdint>
#include <unordered_map>
#include <unordered_set>
#include <vector>

namespace kubach {

struct FCell {
	int x, y, z;
	bool operator==(const FCell &o) const { return x == o.x && y == o.y && z == o.z; }
};

struct FCellHash {
	size_t operator()(const FCell &c) const {
		uint64_t h = (uint64_t)(uint32_t)c.x * 0x9E3779B97F4A7C15ULL;
		h ^= (uint64_t)(uint32_t)c.y * 0xC2B2AE3D27D4EB4FULL + (h << 6) + (h >> 2);
		h ^= (uint64_t)(uint32_t)c.z * 0x165667B19E3779F9ULL + (h << 6) + (h >> 2);
		return (size_t)h;
	}
};

// Упорядоченное множество клеток: порядок вставки, без повторов (как Dictionary в GDScript).
struct FOrderedSet {
	std::vector<FCell> list;
	std::unordered_set<FCell, FCellHash> set;
	void add(const FCell &c) {
		if (set.insert(c).second) {
			list.push_back(c);
		}
	}
	void clear() {
		list.clear();
		set.clear();
	}
};

class NativeFluid : public godot::RefCounted {
	GDCLASS(NativeFluid, godot::RefCounted)

public:
	void setup(const godot::PackedByteArray &p_fluid, const godot::PackedByteArray &p_level,
			const godot::PackedByteArray &p_source, const godot::PackedByteArray &p_solid,
			const godot::PackedByteArray &p_replace, int p_fire, int p_bedrock, const godot::Array &p_level_blocks,
			const godot::PackedInt32Array &p_min_spread, const godot::PackedByteArray &p_extinguish,
			const godot::Dictionary &p_reactions, int p_min_y, int p_max_y);

	void wake(int x, int y, int z);
	void add_active(int x, int y, int z);
	int active_count() const;
	godot::PackedInt32Array active_list() const;
	void clear_active();

	// Шаг: columns — Dictionary Vector2i → ChunkColumn. Возвращает { changes: [x, y, z, блок]…,
	// sleep: [cx, cz, x, y, z]…, reactions: [x, y, z]…, cells, changes_count }.
	godot::Dictionary step(const godot::Dictionary &p_columns, int p_steps, const godot::Vector2i &p_center,
			int p_radius, int p_max_cells);

protected:
	static void _bind_methods();

private:
	struct SectionView {
		bool ready = false;
		int uniform = 0;
		godot::PackedInt32Array blocks;
		const int32_t *ptr = nullptr;
		// Своя копия после первой записи на этом шаге (вместо наложения — чтение без хэша).
		std::vector<int32_t> local;
	};
	struct ColumnView {
		bool loaded = false;
		godot::Array sections;
		std::vector<SectionView> views;
	};

	std::vector<uint8_t> fluid, level, source, solid, replace;
	std::vector<std::vector<int>> level_blocks;
	std::vector<int> min_spread;
	std::vector<uint8_t> extinguish;
	std::unordered_map<int64_t, std::pair<int, int>> react;
	int fire = 0;
	int bedrock = 0;
	int min_y = -256;
	int max_y = 320;

	FOrderedSet active;
	// Состояние шага.
	const godot::Dictionary *columns = nullptr;
	std::unordered_map<int64_t, ColumnView> col_cache;
	int64_t last_key = INT64_MIN;
	ColumnView *last_view = nullptr;
	std::unordered_set<FCell, FCellHash> written;
	std::vector<FCell> write_order;
	FOrderedSet next;
	std::unordered_set<FCell, FCellHash> bodies;
	std::vector<int32_t> sleep_out;
	std::vector<int32_t> react_out;
	int steps = 0;
	godot::Vector2i center;
	int radius = -1;

	int get(int x, int y, int z);
	SectionView *view(int x, int y, int z, bool &loaded);
	void set(int x, int y, int z, int b);
	int level_at(int f, int b) const;
	bool is_source(int b) const { return b > 0 && source[b] == 1; }
	void wake_next(const FCell &p);
	void sleep_cell(int cx, int cz, const FCell &p);
	bool in_radius(int cx, int cz) const;
	int cell(const FCell &p);
	int reactions(const FCell &p, int f);
	int pressure(const FCell &start, int f);
	bool supported(const FCell &c, int f);
	void put(const FCell &p, int f, int lvl);
};

} // namespace kubach
