#include "native_fluid.h"

#include <godot_cpp/core/class_db.hpp>
#include <godot_cpp/variant/vector2i.hpp>

#include <algorithm>
#include <climits>

using namespace godot;

namespace kubach {

namespace {

constexpr int PRESSURE_CAP = 1024;
const FCell DIRS_SIDE[4] = { { 1, 0, 0 }, { -1, 0, 0 }, { 0, 0, 1 }, { 0, 0, -1 } };
const FCell DIRS_ALL[6] = { { 0, -1, 0 }, { 1, 0, 0 }, { -1, 0, 0 }, { 0, 0, 1 }, { 0, 0, -1 }, { 0, 1, 0 } };

inline FCell add(const FCell &a, const FCell &b) {
	return FCell{ a.x + b.x, a.y + b.y, a.z + b.z };
}

inline int64_t col_key(int cx, int cz) {
	return ((int64_t)cx << 32) ^ (int64_t)(uint32_t)cz;
}

} // namespace

void NativeFluid::setup(const PackedByteArray &p_fluid, const PackedByteArray &p_level, const PackedByteArray &p_source,
		const PackedByteArray &p_solid, const PackedByteArray &p_replace, int p_fire, int p_bedrock,
		const Array &p_level_blocks, const PackedInt32Array &p_min_spread, const PackedByteArray &p_extinguish,
		const Dictionary &p_reactions, int p_min_y, int p_max_y) {
	fluid.assign(p_fluid.ptr(), p_fluid.ptr() + p_fluid.size());
	level.assign(p_level.ptr(), p_level.ptr() + p_level.size());
	source.assign(p_source.ptr(), p_source.ptr() + p_source.size());
	solid.assign(p_solid.ptr(), p_solid.ptr() + p_solid.size());
	replace.assign(p_replace.ptr(), p_replace.ptr() + p_replace.size());
	fire = p_fire;
	bedrock = p_bedrock;
	level_blocks.clear();
	for (int i = 0; i < p_level_blocks.size(); i++) {
		PackedInt32Array lv = p_level_blocks[i];
		level_blocks.emplace_back(lv.ptr(), lv.ptr() + lv.size());
	}
	min_spread.assign(p_min_spread.ptr(), p_min_spread.ptr() + p_min_spread.size());
	extinguish.assign(p_extinguish.ptr(), p_extinguish.ptr() + p_extinguish.size());
	react.clear();
	Array keys = p_reactions.keys();
	for (int i = 0; i < keys.size(); i++) {
		Vector2i k = keys[i];
		Array v = p_reactions[keys[i]];
		react[col_key(k.x, k.y)] = { (int)v[0], (int)v[1] };
	}
	min_y = p_min_y;
	max_y = p_max_y;
}

void NativeFluid::wake(int x, int y, int z) {
	FCell p{ x, y, z };
	active.add(p);
	for (const FCell &d : DIRS_ALL) {
		active.add(add(p, d));
	}
}

void NativeFluid::add_active(int x, int y, int z) {
	active.add(FCell{ x, y, z });
}

int NativeFluid::active_count() const {
	return (int)active.list.size();
}

PackedInt32Array NativeFluid::active_list() const {
	PackedInt32Array out;
	out.resize(active.list.size() * 3);
	int32_t *w = out.ptrw();
	for (size_t i = 0; i < active.list.size(); i++) {
		w[i * 3] = active.list[i].x;
		w[i * 3 + 1] = active.list[i].y;
		w[i * 3 + 2] = active.list[i].z;
	}
	return out;
}

void NativeFluid::clear_active() {
	active.clear();
}

// --- Доступ к миру ---------------------------------------------------------------------------

NativeFluid::SectionView *NativeFluid::view(int x, int y, int z, bool &loaded) {
	const int cx = x >> 4;
	const int cz = z >> 4;
	const int64_t key = col_key(cx, cz);
	ColumnView *cvp = nullptr;
	if (key == last_key && last_view != nullptr) {
		cvp = last_view;
	} else {
		auto it = col_cache.find(key);
		if (it == col_cache.end()) {
			ColumnView cv;
			Variant v = columns->get(Vector2i(cx, cz), Variant());
			if (v.get_type() == Variant::OBJECT) {
				Object *o = v;
				if (o != nullptr) {
					cv.loaded = true;
					cv.sections = o->get("sections");
					cv.views.resize(cv.sections.size());
				}
			}
			it = col_cache.emplace(key, std::move(cv)).first;
		}
		cvp = &it->second;
		last_key = key;
		last_view = cvp;
	}
	ColumnView &cv = *cvp;
	loaded = cv.loaded;
	if (!cv.loaded) {
		return nullptr;
	}
	const int si = (y - min_y) >> 4;
	if (si < 0 || si >= (int)cv.views.size()) {
		return nullptr;
	}
	SectionView &sv = cv.views[si];
	if (!sv.ready) {
		sv.ready = true;
		Variant s = cv.sections[si];
		if (s.get_type() == Variant::OBJECT) {
			Object *so = s;
			if (so != nullptr) {
				sv.uniform = (int)so->get("uniform");
				sv.blocks = so->get("blocks");
				sv.ptr = sv.blocks.size() > 0 ? sv.blocks.ptr() : nullptr;
			}
		}
	}
	return &sv;
}

int NativeFluid::get(int x, int y, int z) {
	if (y >= max_y) {
		return 0;
	}
	if (y < min_y) {
		return bedrock;
	}
	bool loaded = false;
	SectionView *sv = view(x, y, z, loaded);
	if (!loaded) {
		return -1;
	}
	if (sv == nullptr) {
		return 0;
	}
	const int idx = (x & 15) | ((z & 15) << 4) | ((y & 15) << 8);
	if (!sv->local.empty()) {
		return sv->local[idx];
	}
	if (sv->ptr == nullptr) {
		return sv->uniform;
	}
	return sv->ptr[idx];
}

void NativeFluid::set(int x, int y, int z, int b) {
	if (y < min_y || y >= max_y) {
		return;
	}
	bool loaded = false;
	SectionView *sv = view(x, y, z, loaded);
	if (!loaded || sv == nullptr) {
		return;
	}
	if (sv->local.empty()) {
		sv->local.resize(4096);
		if (sv->ptr != nullptr) {
			std::copy(sv->ptr, sv->ptr + 4096, sv->local.begin());
		} else {
			std::fill(sv->local.begin(), sv->local.end(), sv->uniform);
		}
	}
	sv->local[(x & 15) | ((z & 15) << 4) | ((y & 15) << 8)] = b;
	FCell c{ x, y, z };
	if (written.insert(c).second) {
		write_order.push_back(c);
	}
}

// --- Правила (как в FluidSim) ----------------------------------------------------------------

int NativeFluid::level_at(int f, int b) const {
	if (b == 0) {
		return 0;
	}
	if (b < 0) {
		return -1;
	}
	if (fluid[b] == f) {
		return level[b];
	}
	if (replace[b] == 1) {
		return 0;
	}
	return -1;
}

void NativeFluid::wake_next(const FCell &p) {
	next.add(p);
	for (const FCell &d : DIRS_ALL) {
		next.add(add(p, d));
	}
}

void NativeFluid::sleep_cell(int cx, int cz, const FCell &p) {
	sleep_out.push_back(cx);
	sleep_out.push_back(cz);
	sleep_out.push_back(p.x);
	sleep_out.push_back(p.y);
	sleep_out.push_back(p.z);
}

bool NativeFluid::in_radius(int cx, int cz) const {
	if (radius < 0) {
		return true;
	}
	return std::abs(cx - center.x) <= radius && std::abs(cz - center.y) <= radius;
}

void NativeFluid::put(const FCell &p, int f, int lvl) {
	const int cur = get(p.x, p.y, p.z);
	if (is_source(cur)) {
		return;
	}
	const int b = lvl <= 0 ? 0 : level_blocks[f - 1][std::min(lvl, 8)];
	set(p.x, p.y, p.z, b);
	wake_next(p);
}

bool NativeFluid::supported(const FCell &c, int f) {
	const int b = get(c.x, c.y - 1, c.z);
	if (b < 0) {
		return false;
	}
	if (b == 0) {
		return false;
	}
	if (fluid[b] == f) {
		return level[b] == 8;
	}
	return solid[b] == 1 || replace[b] == 0;
}

int NativeFluid::reactions(const FCell &p, int f) {
	int n = 0;
	for (const FCell &d : DIRS_ALL) {
		const FCell q = add(p, d);
		const int nb = get(q.x, q.y, q.z);
		if (nb <= 0) {
			continue;
		}
		if (nb == fire && extinguish[f - 1] == 1) {
			set(q.x, q.y, q.z, 0);
			wake_next(q);
			n++;
			continue;
		}
		const int g = fluid[nb];
		if (g == 0 || g == f) {
			continue;
		}
		auto r = react.find(col_key(f, g));
		if (r == react.end()) {
			continue;
		}
		const int to = is_source(nb) ? r->second.first : r->second.second;
		if (to > 0) {
			set(q.x, q.y, q.z, to);
			react_out.push_back(q.x);
			react_out.push_back(q.y);
			react_out.push_back(q.z);
			wake_next(q);
			n++;
		}
	}
	return n;
}

int NativeFluid::pressure(const FCell &start, int f) {
	std::unordered_set<FCell, FCellHash> seen;
	seen.insert(start);
	std::vector<FCell> queue{ start };
	FCell donor{ 0, 0, 0 };
	int64_t donor_s = -((int64_t)1 << 40);
	bool donor_src = false;
	FCell recv{ 0, 0, 0 };
	int64_t recv_s = (int64_t)1 << 40;
	size_t qi = 0;
	while (qi < queue.size()) {
		const FCell c = queue[qi];
		qi++;
		if (queue.size() > (size_t)PRESSURE_CAP) {
			for (const FCell &x : queue) {
				bodies.insert(x);
			}
			return 0;
		}
		const int b = get(c.x, c.y, c.z);
		const int l = level[b];
		const int up = get(c.x, c.y + 1, c.z);
		const int64_t s = (int64_t)c.y * 8 + l;
		if ((up <= 0 || fluid[up] != f) && s > donor_s) {
			donor_s = s;
			donor = c;
			donor_src = is_source(b);
		}
		if (l < 8 && !is_source(b) && s < recv_s && supported(c, f)) {
			recv_s = s;
			recv = c;
		}
		for (const FCell &d : DIRS_ALL) {
			const FCell q = add(c, d);
			if (seen.count(q)) {
				continue;
			}
			const int nb = get(q.x, q.y, q.z);
			if (nb > 0 && fluid[nb] == f) {
				seen.insert(q);
				queue.push_back(q);
			} else if (level_at(f, nb) == 0) {
				seen.insert(q);
				const int64_t qs = (int64_t)q.y * 8;
				if (qs < recv_s && supported(q, f)) {
					recv_s = qs;
					recv = q;
				}
			}
		}
	}
	for (const FCell &x : queue) {
		bodies.insert(x);
	}
	if (donor_s - recv_s < min_spread[f - 1] || donor == recv) {
		return 0;
	}
	const int dl = level[get(donor.x, donor.y, donor.z)];
	const int rb = get(recv.x, recv.y, recv.z);
	const int rl = std::max(0, level_at(f, rb));
	int64_t t = std::min<int64_t>((donor_s - recv_s) / 2, 8 - rl);
	if (!donor_src) {
		t = std::min<int64_t>(t, dl);
	}
	if (t <= 0) {
		return 0;
	}
	put(recv, f, rl + (int)t);
	if (!donor_src) {
		put(donor, f, dl - (int)t);
	}
	return 2;
}

int NativeFluid::cell(const FCell &p) {
	const int b = get(p.x, p.y, p.z);
	if (b <= 0) {
		return 0;
	}
	const int f = fluid[b];
	if (f == 0) {
		return 0;
	}
	int changes = reactions(p, f);
	int lvl = level[b];
	const bool src = source[b] == 1;
	const std::vector<int> &levels = level_blocks[f - 1];
	if (levels[8] <= 0) {
		return changes;
	}
	// Вниз.
	const FCell below{ p.x, p.y - 1, p.z };
	const int bb = get(below.x, below.y, below.z);
	if (bb < 0) {
		sleep_cell(below.x >> 4, below.z >> 4, p);
		return changes;
	}
	const int bl = level_at(f, bb);
	if (bl >= 0 && bl < 8 && !is_source(bb)) {
		const int amount = std::min(lvl, 8 - bl);
		put(below, f, bl + amount);
		changes++;
		if (!src) {
			lvl -= amount;
			put(p, f, lvl);
			changes++;
		}
		if (lvl == 0) {
			return changes;
		}
		if (bl + amount < 8) {
			return changes;
		}
	}
	// Вбок.
	const int ms = min_spread[f - 1];
	const int start = steps % 4;
	for (int i = 0; i < 4; i++) {
		const FCell q = add(p, DIRS_SIDE[(start + i) % 4]);
		const int nb = get(q.x, q.y, q.z);
		if (nb < 0) {
			sleep_cell(q.x >> 4, q.z >> 4, p);
			continue;
		}
		if (lvl <= 0) {
			continue;
		}
		const int nl = level_at(f, nb);
		if (nl < 0 || is_source(nb)) {
			continue;
		}
		const int diff = lvl - nl;
		int need = ms;
		if (nl == 0) {
			const int under = level_at(f, get(q.x, q.y - 1, q.z));
			if (under >= 0 && under < 8) {
				need = 1;
			}
		}
		if (diff < need) {
			continue;
		}
		const int t = std::max(1, diff / 2);
		put(q, f, nl + t);
		changes++;
		if (!src) {
			lvl -= t;
			put(p, f, lvl);
			changes++;
		}
	}
	if (lvl > 0 && !src && changes == 0 && bodies.count(p) == 0) {
		changes += pressure(p, f);
	}
	return changes;
}

Dictionary NativeFluid::step(const Dictionary &p_columns, int p_steps, const Vector2i &p_center, int p_radius,
		int p_max_cells) {
	columns = &p_columns;
	steps = p_steps;
	center = p_center;
	radius = p_radius;
	col_cache.clear();
	last_key = INT64_MIN;
	last_view = nullptr;
	written.clear();
	write_order.clear();
	next.clear();
	bodies.clear();
	sleep_out.clear();
	react_out.clear();
	int changes = 0;
	int cells = 0;
	size_t i = 0;
	const std::vector<FCell> current = active.list;
	for (; i < current.size(); i++) {
		if (cells >= p_max_cells) {
			break;
		}
		const FCell &p = current[i];
		const int cx = p.x >> 4;
		const int cz = p.z >> 4;
		if (!in_radius(cx, cz)) {
			sleep_cell(cx, cz, p);
			continue;
		}
		cells++;
		changes += cell(p);
	}
	for (; i < current.size(); i++) {
		next.add(current[i]);
	}
	active.list.swap(next.list);
	active.set.swap(next.set);
	next.clear();

	Dictionary out;
	PackedInt32Array ch;
	ch.resize(write_order.size() * 4);
	int32_t *w = ch.ptrw();
	for (size_t k = 0; k < write_order.size(); k++) {
		const FCell &c = write_order[k];
		w[k * 4] = c.x;
		w[k * 4 + 1] = c.y;
		w[k * 4 + 2] = c.z;
		w[k * 4 + 3] = get(c.x, c.y, c.z);
	}
	PackedInt32Array sl;
	sl.resize(sleep_out.size());
	std::copy(sleep_out.begin(), sleep_out.end(), sl.ptrw());
	PackedInt32Array rc;
	rc.resize(react_out.size());
	std::copy(react_out.begin(), react_out.end(), rc.ptrw());
	out["changes"] = ch;
	out["sleep"] = sl;
	out["reactions"] = rc;
	out["cells"] = cells;
	out["changes_count"] = changes;
	columns = nullptr;
	col_cache.clear();
	last_key = INT64_MIN;
	last_view = nullptr;
	written.clear();
	return out;
}

void NativeFluid::_bind_methods() {
	ClassDB::bind_method(D_METHOD("setup", "fluid", "level", "source", "solid", "replace", "fire", "bedrock",
								 "level_blocks", "min_spread", "extinguish", "reactions", "min_y", "max_y"),
			&NativeFluid::setup);
	ClassDB::bind_method(D_METHOD("wake", "x", "y", "z"), &NativeFluid::wake);
	ClassDB::bind_method(D_METHOD("add_active", "x", "y", "z"), &NativeFluid::add_active);
	ClassDB::bind_method(D_METHOD("active_count"), &NativeFluid::active_count);
	ClassDB::bind_method(D_METHOD("active_list"), &NativeFluid::active_list);
	ClassDB::bind_method(D_METHOD("clear_active"), &NativeFluid::clear_active);
	ClassDB::bind_method(D_METHOD("step", "columns", "steps", "center", "radius", "max_cells"), &NativeFluid::step);
}

} // namespace kubach
