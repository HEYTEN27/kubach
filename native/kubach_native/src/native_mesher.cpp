#include "native_mesher.h"

#include <godot_cpp/classes/mesh.hpp>
#include <godot_cpp/core/class_db.hpp>
#include <godot_cpp/variant/packed_vector2_array.hpp>
#include <godot_cpp/variant/packed_vector3_array.hpp>

#include <algorithm>
#include <cmath>
#include <cstdint>

using namespace godot;

namespace kubach {

namespace {

// Коды из BlockDef.
constexpr int RENDER_INVISIBLE = 0;
constexpr int RENDER_OPAQUE = 1;
constexpr int RENDER_CUTOUT = 2;
constexpr int RENDER_TRANSLUCENT = 3;
constexpr int RENDER_LIQUID = 4;
constexpr int SHAPE_CUBE = 0;
constexpr int SHAPE_CROSS = 1;
constexpr int TINT_NONE = 0;
constexpr int TINT_FOLIAGE = 2;

constexpr int P = 18;
constexpr int PY = 324;
constexpr int PAD_VOLUME = 5832;
constexpr int STRIDE[3] = { 1, PY, P };
constexpr int AXIS_U[3] = { 2, 0, 0 };
constexpr int AXIS_V[3] = { 1, 2, 1 };
constexpr int TINT_N = 5;
const Color NEUTRAL(0.5f, 0.5f, 0.5f, 1.0f);
const Vector2 PLANT_UV[4] = { Vector2(0, 1), Vector2(1, 1), Vector2(1, 0), Vector2(0, 0) };

inline float ratio(float v, float base) {
	return std::clamp(v / std::max(base, 0.02f), 0.0f, 2.0f) * 0.5f;
}

// GenRandom.mix / hash3 / unit — те же 64-битные операции, что и в GDScript (там int — int64
// с переполнением по модулю 2^64 и арифметическим сдвигом).
inline int64_t mul(int64_t a, int64_t b) {
	return (int64_t)((uint64_t)a * (uint64_t)b);
}
inline int64_t add(int64_t a, int64_t b) {
	return (int64_t)((uint64_t)a + (uint64_t)b);
}
inline int64_t mix(int64_t h) {
	h = mul(h ^ (h >> 30), -4658895280553007687LL);
	h = mul(h ^ (h >> 27), -7723592293110705685LL);
	return h ^ (h >> 31);
}
inline int64_t hash2(int64_t seed, int64_t a, int64_t b, int64_t salt) {
	return mix(add(mix(add(mix(seed ^ mul(salt, -7046029254386353131LL)), a)), b));
}
inline int64_t hash3(int64_t seed, int64_t a, int64_t b, int64_t c, int64_t salt) {
	return mix(add(hash2(seed, a, b, salt), c));
}
inline double unit(int64_t h) {
	return (double)((h >> 11) & 0x1FFFFFFFFFFFFFLL) / 9007199254740992.0;
}

struct Surface {
	PackedVector3Array verts;
	PackedVector3Array normals;
	PackedColorArray colors;
	PackedVector2Array uvs;
	PackedVector2Array uv2s;
	PackedInt32Array indices;
	int quads = 0;

	// block — числовой ID блока (UV2.x); quad_uv — явные UV (растения), верх получает вес ветра 1.
	void add_quad(const Vector3 pts[4], const Vector3 &n, const Color cols[4], int block,
			const Vector2 *quad_uv = nullptr) {
		Vector3 e1 = pts[1] - pts[0];
		Vector3 e2 = pts[2] - pts[0];
		bool flip = e1.cross(e2).dot(n) > 0.0f;
		int base = verts.size();
		int ua, va;
		if (std::fabs(n.y) > 0.5f) {
			ua = 0;
			va = 2;
		} else if (std::fabs(n.x) > 0.5f) {
			ua = 2;
			va = 1;
		} else {
			ua = 0;
			va = 1;
		}
		for (int c = 0; c < 4; c++) {
			verts.push_back(pts[c]);
			normals.push_back(n);
			colors.push_back(cols[c]);
			if (quad_uv != nullptr) {
				uvs.push_back(quad_uv[c]);
				uv2s.push_back(Vector2((float)block, 1.0f - quad_uv[c].y));
			} else {
				uvs.push_back(Vector2(pts[c][ua], pts[c][va]));
				uv2s.push_back(Vector2((float)block, 0.0f));
			}
		}
		if (flip) {
			const int idx[6] = { base, base + 2, base + 1, base, base + 3, base + 2 };
			for (int i : idx) {
				indices.push_back(i);
			}
		} else {
			const int idx[6] = { base, base + 1, base + 2, base, base + 2, base + 3 };
			for (int i : idx) {
				indices.push_back(i);
			}
		}
		quads++;
	}

	Array to_arrays() const {
		if (quads == 0) {
			return Array();
		}
		Array arrays;
		arrays.resize(Mesh::ARRAY_MAX);
		arrays[Mesh::ARRAY_VERTEX] = verts;
		arrays[Mesh::ARRAY_NORMAL] = normals;
		arrays[Mesh::ARRAY_COLOR] = colors;
		arrays[Mesh::ARRAY_TEX_UV] = uvs;
		arrays[Mesh::ARRAY_TEX_UV2] = uv2s;
		arrays[Mesh::ARRAY_INDEX] = indices;
		return arrays;
	}
};

const Vector3i NEIGHBOR_DIRS[6] = {
	Vector3i(-1, 0, 0), Vector3i(1, 0, 0), Vector3i(0, -1, 0),
	Vector3i(0, 1, 0), Vector3i(0, 0, -1), Vector3i(0, 0, 1),
};

} // namespace

void NativeMesher::setup(const PackedByteArray &p_render, const PackedByteArray &p_shape,
		const PackedColorArray &p_color, const PackedByteArray &p_tint,
		const PackedFloat32Array &p_tint_strength, const PackedFloat32Array &p_layer_h,
		const PackedByteArray &p_opaque) {
	render.assign(p_render.ptr(), p_render.ptr() + p_render.size());
	shape.assign(p_shape.ptr(), p_shape.ptr() + p_shape.size());
	color.assign(p_color.ptr(), p_color.ptr() + p_color.size());
	tint.assign(p_tint.ptr(), p_tint.ptr() + p_tint.size());
	tint_strength.assign(p_tint_strength.ptr(), p_tint_strength.ptr() + p_tint_strength.size());
	layer_h.assign(p_layer_h.ptr(), p_layer_h.ptr() + p_layer_h.size());
	opaque.assign(p_opaque.ptr(), p_opaque.ptr() + p_opaque.size());
}

String NativeMesher::version() const {
	return "kubach_native 2";
}

Dictionary NativeMesher::mesh_section(const Array &p_center, const Array &p_neighbors,
		const PackedColorArray &p_tints, int p_season, const Vector3i &p_origin) const {
	Dictionary result;
	result["opaque"] = Array();
	result["cutout"] = Array();
	result["transparent"] = Array();
	result["plants"] = Array();
	result["quads"] = 0;

	const int cu = p_center[0];
	const PackedInt32Array cb = p_center[1];
	const bool c_all_opaque = p_center[2];
	const bool c_special = p_center[3];
	const int32_t *cbp = cb.ptr();
	const bool c_uniform = cb.size() == 0;
	if (c_uniform && render[cu] == RENDER_INVISIBLE) {
		return result;
	}
	if (c_all_opaque) {
		bool all = true;
		for (int i = 0; i < 6; i++) {
			Variant nb = p_neighbors[i];
			if (nb.get_type() != Variant::ARRAY || !(bool)((Array)nb)[2]) {
				all = false;
				break;
			}
		}
		if (all) {
			return result;
		}
	}

	// Массив с полями 18³.
	std::vector<int32_t> pad(PAD_VOLUME, 0);
	for (int y = 0; y < 16; y++) {
		for (int z = 0; z < 16; z++) {
			int dst = 1 + (z + 1) * P + (y + 1) * PY;
			int src = (z << 4) | (y << 8);
			for (int x = 0; x < 16; x++) {
				pad[dst + x] = c_uniform ? cu : cbp[src + x];
			}
		}
	}
	for (int i = 0; i < 6; i++) {
		Variant nbv = p_neighbors[i];
		if (nbv.get_type() != Variant::ARRAY) {
			continue;
		}
		Array nb = nbv;
		int nu = nb[0];
		PackedInt32Array nbl = nb[1];
		const int32_t *nblp = nbl.ptr();
		bool nb_uniform = nbl.size() == 0;
		if (nb_uniform && nu == 0) {
			continue;
		}
		const Vector3i dir = NEIGHBOR_DIRS[i];
		for (int a = 0; a < 16; a++) {
			for (int b = 0; b < 16; b++) {
				int x, y, z, px, py, pz;
				if (dir.x != 0) {
					x = dir.x < 0 ? 15 : 0;
					y = a;
					z = b;
					px = dir.x < 0 ? -1 : 16;
					py = a;
					pz = b;
				} else if (dir.y != 0) {
					x = a;
					y = dir.y < 0 ? 15 : 0;
					z = b;
					px = a;
					py = dir.y < 0 ? -1 : 16;
					pz = b;
				} else {
					x = a;
					y = b;
					z = dir.z < 0 ? 15 : 0;
					px = a;
					py = b;
					pz = dir.z < 0 ? -1 : 16;
				}
				int v = nb_uniform ? nu : nblp[x | (z << 4) | (y << 8)];
				pad[(px + 1) + (pz + 1) * P + (py + 1) * PY] = v;
			}
		}
	}

	const bool tinting = p_tints.size() == 8 * TINT_N * TINT_N;
	const Color *tp = p_tints.ptr();
	auto block_color = [&](int b, double lx, double lz) -> Color {
		int t = tint[b];
		if (t == TINT_NONE || !tinting) {
			return NEUTRAL;
		}
		int ch = p_season * 2 + (t == TINT_FOLIAGE ? 1 : 0);
		int off = ch * TINT_N * TINT_N;
		double gx = std::clamp(lx / 4.0, 0.0, 4.0);
		double gz = std::clamp(lz / 4.0, 0.0, 4.0);
		int ix = std::min((int)gx, 3);
		int iz = std::min((int)gz, 3);
		double fx = gx - ix;
		double fz = gz - iz;
		Color c0 = tp[off + iz * TINT_N + ix].lerp(tp[off + iz * TINT_N + ix + 1], (float)fx);
		Color c1 = tp[off + (iz + 1) * TINT_N + ix].lerp(tp[off + (iz + 1) * TINT_N + ix + 1], (float)fx);
		const Color base = color[b];
		const Color mixed = base.lerp(c0.lerp(c1, (float)fz), tint_strength[b]);
		return Color(ratio(mixed.r, base.r), ratio(mixed.g, base.g), ratio(mixed.b, base.b), 1.0f);
	};

	Surface s_opaque, s_cutout, s_transparent, s_plants;
	const bool boundary_only = c_uniform && render[cu] != RENDER_CUTOUT && shape[cu] == SHAPE_CUBE;
	int32_t mask[256];

	for (int d = 0; d < 3; d++) {
		const int sd = STRIDE[d];
		const int u_axis = AXIS_U[d];
		const int v_axis = AXIS_V[d];
		const int su = STRIDE[u_axis];
		const int sv = STRIDE[v_axis];
		for (int s : { -1, 1 }) {
			const int nstep = s * sd;
			int k_from = 0, k_to = 16;
			if (boundary_only) {
				k_from = s < 0 ? 0 : 15;
				k_to = k_from + 1;
			}
			for (int k = k_from; k < k_to; k++) {
				bool any = false;
				const int base = (k + 1) * sd + su + sv;
				for (int vv = 0; vv < 16; vv++) {
					const int row = base + vv * sv;
					for (int uu = 0; uu < 16; uu++) {
						const int pi = row + uu * su;
						const int a = pad[pi];
						int m = 0;
						const int ra = render[a];
						if (ra != RENDER_INVISIBLE && shape[a] == SHAPE_CUBE) {
							const int b = pad[pi + nstep];
							const int rb = render[b];
							if (rb == RENDER_INVISIBLE) {
								m = a;
							} else if (opaque[b] != 1 && (a != b || ra == RENDER_CUTOUT)) {
								m = a;
							}
						}
						mask[uu + vv * 16] = m;
						any = any || m != 0;
					}
				}
				if (!any) {
					continue;
				}
				// Greedy-слияние.
				const float f = (float)(k + (s > 0 ? 1 : 0));
				for (int vv = 0; vv < 16; vv++) {
					int uu = 0;
					while (uu < 16) {
						const int m = mask[uu + vv * 16];
						if (m == 0) {
							uu++;
							continue;
						}
						int w = 1;
						while (uu + w < 16 && mask[uu + w + vv * 16] == m) {
							w++;
						}
						int h = 1;
						bool grow = true;
						while (vv + h < 16 && grow) {
							const int r = (vv + h) * 16;
							for (int i = 0; i < w; i++) {
								if (mask[uu + i + r] != m) {
									grow = false;
									break;
								}
							}
							if (grow) {
								h++;
							}
						}
						for (int j = 0; j < h; j++) {
							for (int i = 0; i < w; i++) {
								mask[uu + i + (vv + j) * 16] = 0;
							}
						}
						const int rr = render[m];
						Surface &surf = (rr == RENDER_TRANSLUCENT || rr == RENDER_LIQUID) ? s_transparent
								: (rr == RENDER_CUTOUT ? s_cutout : s_opaque);
						Vector3 n;
						n[d] = (float)s;
						Vector3 pts[4];
						Color cols[4];
						for (int c = 0; c < 4; c++) {
							Vector3 p;
							p[d] = f;
							p[u_axis] = (float)(uu + ((c == 1 || c == 2) ? w : 0));
							p[v_axis] = (float)(vv + (c >= 2 ? h : 0));
							pts[c] = p;
							cols[c] = block_color(m, p.x, p.z);
						}
						surf.add_quad(pts, n, cols, m);
						uu += w;
					}
				}
			}
		}
	}

	if (c_special) {
		for (int y = 0; y < 16; y++) {
			for (int z = 0; z < 16; z++) {
				for (int x = 0; x < 16; x++) {
					const int b = c_uniform ? cu : cbp[x | (z << 4) | (y << 8)];
					const int sh = shape[b];
					if (sh == SHAPE_CUBE) {
						continue;
					}
					const Color c = block_color(b, x + 0.5, z + 0.5);
					const Color cols[4] = { c, c, c, c };
					if (sh == SHAPE_CROSS) {
						const int64_t hsh = hash3(0, p_origin.x + x, p_origin.y + y, p_origin.z + z, 5);
						const double ox = (unit(hsh) - 0.5) * 0.3;
						const double oz = (unit(mix(hsh)) - 0.5) * 0.3;
						const float x0 = (float)(x + 0.15 + ox);
						const float x1 = (float)(x + 0.85 + ox);
						const float z0 = (float)(z + 0.15 + oz);
						const float z1 = (float)(z + 0.85 + oz);
						const Vector3 n1 = Vector3(1, 0, -1).normalized();
						const Vector3 n2 = Vector3(1, 0, 1).normalized();
						const Vector3 q1[4] = { Vector3(x0, y, z0), Vector3(x1, y, z1), Vector3(x1, y + 1, z1), Vector3(x0, y + 1, z0) };
						const Vector3 q2[4] = { Vector3(x0, y, z1), Vector3(x1, y, z0), Vector3(x1, y + 1, z0), Vector3(x0, y + 1, z1) };
						s_plants.add_quad(q1, n1, cols, b, PLANT_UV);
						s_plants.add_quad(q2, n2, cols, b, PLANT_UV);
					} else {
						Surface &ls = render[b] == RENDER_CUTOUT ? s_cutout : s_opaque;
						const float top = (float)((double)y + (double)layer_h[b]);
						const int pi = (x + 1) + (z + 1) * P + (y + 1) * PY;
						const Vector3 qt[4] = { Vector3(x, top, z), Vector3(x + 1, top, z), Vector3(x + 1, top, z + 1), Vector3(x, top, z + 1) };
						ls.add_quad(qt, Vector3(0, 1, 0), cols, b);
						if (opaque[pad[pi - 1]] != 1) {
							const Vector3 q[4] = { Vector3(x, y, z), Vector3(x, y, z + 1), Vector3(x, top, z + 1), Vector3(x, top, z) };
							ls.add_quad(q, Vector3(-1, 0, 0), cols, b);
						}
						if (opaque[pad[pi + 1]] != 1) {
							const Vector3 q[4] = { Vector3(x + 1, y, z), Vector3(x + 1, y, z + 1), Vector3(x + 1, top, z + 1), Vector3(x + 1, top, z) };
							ls.add_quad(q, Vector3(1, 0, 0), cols, b);
						}
						if (opaque[pad[pi - P]] != 1) {
							const Vector3 q[4] = { Vector3(x, y, z), Vector3(x + 1, y, z), Vector3(x + 1, top, z), Vector3(x, top, z) };
							ls.add_quad(q, Vector3(0, 0, -1), cols, b);
						}
						if (opaque[pad[pi + P]] != 1) {
							const Vector3 q[4] = { Vector3(x, y, z + 1), Vector3(x + 1, y, z + 1), Vector3(x + 1, top, z + 1), Vector3(x, top, z + 1) };
							ls.add_quad(q, Vector3(0, 0, 1), cols, b);
						}
					}
				}
			}
		}
	}

	result["opaque"] = s_opaque.to_arrays();
	result["cutout"] = s_cutout.to_arrays();
	result["transparent"] = s_transparent.to_arrays();
	result["plants"] = s_plants.to_arrays();
	result["quads"] = s_opaque.quads + s_cutout.quads + s_transparent.quads + s_plants.quads;
	return result;
}

void NativeMesher::_bind_methods() {
	ClassDB::bind_method(D_METHOD("setup", "render", "shape", "color", "tint", "tint_strength", "layer_h", "opaque"), &NativeMesher::setup);
	ClassDB::bind_method(D_METHOD("mesh_section", "center", "neighbors", "tints", "season", "origin"), &NativeMesher::mesh_section,
			DEFVAL(PackedColorArray()), DEFVAL(1), DEFVAL(Vector3i()));
	ClassDB::bind_method(D_METHOD("version"), &NativeMesher::version);
}

} // namespace kubach
