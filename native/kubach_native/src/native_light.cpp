#include "native_light.h"

#include <godot_cpp/core/class_db.hpp>
#include <godot_cpp/variant/color.hpp>
#include <godot_cpp/variant/packed_int32_array.hpp>

#include <algorithm>

using namespace godot;

namespace kubach {

namespace {

constexpr int OPAQUE = 15;
constexpr int SIDE = 48;
constexpr int PAD = 18;
constexpr int PAD_VOLUME = 5832;
constexpr int SECTIONS = 36;

bool non_air(const Variant &snap) {
	if (snap.get_type() != Variant::ARRAY) {
		return false;
	}
	Array a = snap;
	return (int)a[0] != 0 || ((PackedInt32Array)a[1]).size() != 0;
}

// Поиск в ширину (см. VoxelLight._spread): queue — вектор индексов, растёт по ходу.
void spread(const uint8_t *att, uint8_t *light, std::vector<int32_t> &queue, int sx, int sy, int sz, bool sky) {
	const int plane = sx * sz;
	size_t head = 0;
	while (head < queue.size()) {
		const int i = queue[head++];
		const int l = light[i];
		if (l <= 1) {
			continue;
		}
		const int x = i % sx;
		const int z = (i / sx) % sz;
		const int y = i / plane;
		for (int d = 0; d < 6; d++) {
			int n;
			switch (d) {
				case 0:
					if (x == 0) continue;
					n = i - 1;
					break;
				case 1:
					if (x == sx - 1) continue;
					n = i + 1;
					break;
				case 2:
					if (z == 0) continue;
					n = i - sx;
					break;
				case 3:
					if (z == sz - 1) continue;
					n = i + sx;
					break;
				case 4:
					if (y == 0) continue;
					n = i - plane;
					break;
				default:
					if (y == sy - 1) continue;
					n = i + plane;
					break;
			}
			const int f = att[n];
			if (f >= OPAQUE) {
				continue;
			}
			const int nl = (sky && d == 4 && l == 15) ? 15 - f : l - std::max(1, f);
			if (nl > light[n]) {
				light[n] = (uint8_t)nl;
				queue.push_back(n);
			}
		}
	}
}

void sky_light(const uint8_t *att, uint8_t *light, int sx, int sy, int sz) {
	const int plane = sx * sz;
	std::vector<int32_t> queue;
	queue.reserve(sx * sz * 32);
	for (int z = 0; z < sz; z++) {
		for (int x = 0; x < sx; x++) {
			int level = 15;
			for (int y = sy - 1; y >= 0 && level > 0; y--) {
				const int i = x + z * sx + y * plane;
				const int f = att[i];
				if (f >= OPAQUE) {
					break;
				}
				level -= f;
				if (level <= 0) {
					break;
				}
				light[i] = (uint8_t)level;
				queue.push_back(i);
			}
		}
	}
	spread(att, light, queue, sx, sy, sz, true);
}

void block_light(const uint8_t *att, const uint8_t *emit, int ch, uint8_t *light, int vol, int sx, int sy, int sz) {
	std::vector<int32_t> queue;
	for (int i = 0; i < vol; i++) {
		const int e = emit[i * 3 + ch];
		if (e > 0) {
			light[i] = (uint8_t)e;
			queue.push_back(i);
		}
	}
	if (!queue.empty()) {
		spread(att, light, queue, sx, sy, sz, false);
	}
}

} // namespace

void NativeLight::setup(const PackedByteArray &p_att, const PackedByteArray &p_emit) {
	att_table.assign(p_att.ptr(), p_att.ptr() + p_att.size());
	if (!att_table.empty()) {
		att_table[0] = 0;
	}
	emit_table.assign(p_emit.ptr(), p_emit.ptr() + p_emit.size());
}

PackedByteArray NativeLight::propagate_sky(const PackedByteArray &p_att, int sx, int sy, int sz) const {
	PackedByteArray out;
	out.resize(p_att.size());
	out.fill(0);
	sky_light(p_att.ptr(), out.ptrw(), sx, sy, sz);
	return out;
}

PackedByteArray NativeLight::propagate_block(const PackedByteArray &p_att, const PackedByteArray &p_emit, int ch,
		int sx, int sy, int sz) const {
	PackedByteArray out;
	out.resize(p_att.size());
	out.fill(0);
	block_light(p_att.ptr(), p_emit.ptr(), ch, out.ptrw(), (int)p_att.size(), sx, sy, sz);
	return out;
}

Array NativeLight::light_column(const Array &p_columns) const {
	Array out;
	out.resize(SECTIONS);
	const Color sky_full(1, 0, 0, 0);
	const Color dark(0, 0, 0, 0);
	int lo = SECTIONS;
	int hi = -1;
	for (int ci = 0; ci < 9; ci++) {
		Variant col = p_columns[ci];
		if (col.get_type() != Variant::ARRAY) {
			continue;
		}
		Array ca = col;
		for (int si = 0; si < SECTIONS; si++) {
			if (non_air(ca[si])) {
				lo = std::min(lo, si);
				hi = std::max(hi, si);
			}
		}
	}
	if (hi < 0) {
		for (int si = 0; si < SECTIONS; si++) {
			out[si] = sky_full;
		}
		return out;
	}
	const int sy = (hi + 1 - lo) * 16 + 1;
	const int plane = SIDE * SIDE;
	const int vol = plane * sy;
	std::vector<uint8_t> att(vol, 0);
	std::vector<uint8_t> emit((size_t)vol * 3, 0);
	const int nblocks = (int)att_table.size();
	for (int ci = 0; ci < 9; ci++) {
		const int ox = (ci % 3) * 16;
		const int oz = (ci / 3) * 16;
		Variant col = p_columns[ci];
		const bool loaded = col.get_type() == Variant::ARRAY;
		Array ca;
		if (loaded) {
			ca = col;
		}
		for (int si = lo; si <= hi; si++) {
			const int ry0 = (si - lo) * 16;
			if (!loaded) {
				for (int ly = 0; ly < 16; ly++) {
					for (int lz = 0; lz < 16; lz++) {
						uint8_t *row = &att[ox + (oz + lz) * SIDE + (ry0 + ly) * plane];
						std::fill(row, row + 16, (uint8_t)OPAQUE);
					}
				}
				continue;
			}
			Variant snap = ca[si];
			if (snap.get_type() != Variant::ARRAY) {
				continue;
			}
			Array sa = snap;
			const int u = sa[0];
			const PackedInt32Array bl = sa[1];
			const int32_t *blp = bl.ptr();
			const bool uniform = bl.size() == 0;
			for (int ly = 0; ly < 16; ly++) {
				for (int lz = 0; lz < 16; lz++) {
					const int base = ox + (oz + lz) * SIDE + (ry0 + ly) * plane;
					const int src = (lz << 4) | (ly << 8);
					for (int lx = 0; lx < 16; lx++) {
						const int b = uniform ? u : blp[src + lx];
						if (b <= 0 || b >= nblocks) {
							continue;
						}
						const int i = base + lx;
						att[i] = att_table[b];
						const int e = b * 3;
						emit[(size_t)i * 3] = emit_table[e];
						emit[(size_t)i * 3 + 1] = emit_table[e + 1];
						emit[(size_t)i * 3 + 2] = emit_table[e + 2];
					}
				}
			}
		}
	}
	std::vector<uint8_t> sky(vol, 0), r(vol, 0), g(vol, 0), b(vol, 0);
	sky_light(att.data(), sky.data(), SIDE, sy, SIDE);
	block_light(att.data(), emit.data(), 0, r.data(), vol, SIDE, sy, SIDE);
	block_light(att.data(), emit.data(), 1, g.data(), vol, SIDE, sy, SIDE);
	block_light(att.data(), emit.data(), 2, b.data(), vol, SIDE, sy, SIDE);

	auto neighbor_max = [&](int x, int y, int z) -> int {
		int ms = 0, mr = 0, mg = 0, mb = 0;
		for (int d = 0; d < 6; d++) {
			int nx = x, ny = y, nz = z;
			switch (d) {
				case 0: nx--; break;
				case 1: nx++; break;
				case 2: nz--; break;
				case 3: nz++; break;
				case 4: ny--; break;
				default: ny++; break;
			}
			if (nx < 0 || nx >= SIDE || nz < 0 || nz >= SIDE || ny < 0) {
				continue;
			}
			if (ny >= sy) {
				ms = 15;
				continue;
			}
			const int n = nx + nz * SIDE + ny * plane;
			if (att[n] >= OPAQUE) {
				continue;
			}
			ms = std::max(ms, (int)sky[n]);
			mr = std::max(mr, (int)r[n]);
			mg = std::max(mg, (int)g[n]);
			mb = std::max(mb, (int)b[n]);
		}
		return (ms << 24) | (mr << 16) | (mg << 8) | mb;
	};

	const int y0 = lo * 16;
	for (int si = 0; si < SECTIONS; si++) {
		if (si > hi) {
			out[si] = sky_full;
			continue;
		}
		if (si < lo) {
			out[si] = dark;
			continue;
		}
		const int ry = si * 16 - y0;
		PackedByteArray data;
		data.resize(PAD_VOLUME * 4);
		uint8_t *dp = data.ptrw();
		int first = -1;
		bool uniform = true;
		int o = 0;
		for (int py = 0; py < PAD; py++) {
			const int y = ry + py - 1;
			for (int pz = 0; pz < PAD; pz++) {
				const int z = 15 + pz;
				for (int px = 0; px < PAD; px++) {
					const int x = 15 + px;
					int v = 0;
					if (y >= sy) {
						v = 15 << 24;
					} else if (y >= 0) {
						const int i = x + z * SIDE + y * plane;
						if (att[i] >= OPAQUE) {
							v = neighbor_max(x, y, z);
						} else {
							v = (sky[i] << 24) | (r[i] << 16) | (g[i] << 8) | b[i];
						}
					}
					dp[o] = (uint8_t)(((v >> 24) & 15) * 17);
					dp[o + 1] = (uint8_t)(((v >> 16) & 15) * 17);
					dp[o + 2] = (uint8_t)(((v >> 8) & 15) * 17);
					dp[o + 3] = (uint8_t)((v & 15) * 17);
					if (first < 0) {
						first = v;
					} else if (v != first) {
						uniform = false;
					}
					o += 4;
				}
			}
		}
		if (uniform) {
			out[si] = Color(((first >> 24) & 15) / 15.0f, ((first >> 16) & 15) / 15.0f, ((first >> 8) & 15) / 15.0f,
					(first & 15) / 15.0f);
		} else {
			out[si] = data;
		}
	}
	return out;
}

void NativeLight::_bind_methods() {
	ClassDB::bind_method(D_METHOD("setup", "att", "emit"), &NativeLight::setup);
	ClassDB::bind_method(D_METHOD("light_column", "columns"), &NativeLight::light_column);
	ClassDB::bind_method(D_METHOD("propagate_sky", "att", "sx", "sy", "sz"), &NativeLight::propagate_sky);
	ClassDB::bind_method(D_METHOD("propagate_block", "att", "emit", "ch", "sx", "sy", "sz"), &NativeLight::propagate_block);
}

} // namespace kubach
