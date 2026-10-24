"""Бесшовный (периодический) шум для текстур: value-noise/fbm, Worley, искажение домена.

Всё периодично по размеру текстуры, поэтому текстура повторяется без швов (greedy-меш
кладёт одну и ту же текстуру на каждый блок большой грани).
"""
import numpy as np


def _smooth(t):
    return t * t * (3.0 - 2.0 * t)


def value_noise(size, cells, rng):
    """Периодический value-noise: решётка cells×cells, гладкая интерполяция. Значения 0..1."""
    lat = rng.random((cells, cells))
    coords = np.arange(size) * cells / size
    i0 = np.floor(coords).astype(int)
    f = _smooth(coords - i0)
    i1 = (i0 + 1) % cells
    i0 %= cells
    # Строки — y, столбцы — x.
    a = lat[np.ix_(i0, i0)]
    b = lat[np.ix_(i0, i1)]
    c = lat[np.ix_(i1, i0)]
    d = lat[np.ix_(i1, i1)]
    fx = f[None, :]
    fy = f[:, None]
    return (a * (1 - fx) + b * fx) * (1 - fy) + (c * (1 - fx) + d * fx) * fy


def fbm(size, cells, rng, octaves=4, persistence=0.5, aniso=(1, 1)):
    """Фрактальный шум. aniso — множители частоты по (y, x) для вытянутых узоров (кора, слои)."""
    total = np.zeros((size, size))
    amp = 1.0
    norm = 0.0
    c = cells
    for _ in range(octaves):
        cy = max(1, int(round(c * aniso[0])))
        cx = max(1, int(round(c * aniso[1])))
        total += amp * _value_noise_xy(size, cy, cx, rng)
        norm += amp
        amp *= persistence
        c *= 2
        if c > size:
            break
    return total / norm


def _value_noise_xy(size, cy, cx, rng):
    lat = rng.random((cy, cx))
    ys = np.arange(size) * cy / size
    xs = np.arange(size) * cx / size
    y0 = np.floor(ys).astype(int)
    x0 = np.floor(xs).astype(int)
    fy = _smooth(ys - y0)[:, None]
    fx = _smooth(xs - x0)[None, :]
    y1 = (y0 + 1) % cy
    x1 = (x0 + 1) % cx
    y0 %= cy
    x0 %= cx
    a = lat[np.ix_(y0, x0)]
    b = lat[np.ix_(y0, x1)]
    c = lat[np.ix_(y1, x0)]
    d = lat[np.ix_(y1, x1)]
    return (a * (1 - fx) + b * fx) * (1 - fy) + (c * (1 - fx) + d * fx) * fy


def worley(size, cells, rng, jitter=1.0):
    """Периодический Worley: (F1, F2, id ячейки) — расстояния в долях ячейки."""
    pts = rng.random((cells, cells, 2)) * jitter + (1 - jitter) * 0.5
    ys, xs = np.mgrid[0:size, 0:size] * (cells / size)
    cy = np.floor(ys).astype(int)
    cx = np.floor(xs).astype(int)
    f1 = np.full((size, size), 9.0)
    f2 = np.full((size, size), 9.0)
    ids = np.zeros((size, size), dtype=np.int64)
    for dy in (-1, 0, 1):
        for dx in (-1, 0, 1):
            ny = cy + dy
            nx = cx + dx
            py = pts[ny % cells, nx % cells, 0] + ny
            px = pts[ny % cells, nx % cells, 1] + nx
            d = np.sqrt((ys - py) ** 2 + (xs - px) ** 2)
            cid = (ny % cells) * cells + (nx % cells)
            closer = d < f1
            f2 = np.where(closer, f1, np.minimum(f2, d))
            ids = np.where(closer, cid, ids)
            f1 = np.where(closer, d, f1)
    return f1, f2, ids


def warp(field, dx, dy, strength):
    """Искажение домена: выборка field со сдвигом (dx, dy) в пикселях (с переносом)."""
    size = field.shape[0]
    ys, xs = np.mgrid[0:size, 0:size]
    sy = (ys + dy * strength).astype(int) % size
    sx = (xs + dx * strength).astype(int) % size
    return field[sy, sx]


def blur(field, radius=1):
    """Периодическое размытие квадратом (2r+1)²."""
    out = np.zeros_like(field)
    n = 0
    for dy in range(-radius, radius + 1):
        for dx in range(-radius, radius + 1):
            out += np.roll(np.roll(field, dy, 0), dx, 1)
            n += 1
    return out / n


def normalize(a):
    lo, hi = a.min(), a.max()
    return (a - lo) / (hi - lo + 1e-9)


def dots(size, cells, rng, frac, radius=0.3, jitter=1.0):
    """Круглые пятна на случайной доле ячеек Worley. Возвращает (маска 0..1 с мягким краем, F1, id)."""
    f1, _, ids = worley(size, cells, rng, jitter)
    sel = hash01(ids, 1) < frac
    rad = radius * (0.6 + 0.8 * hash01(ids, 2))
    soft = np.clip((rad - f1) / (0.25 * rad + 1e-6), 0, 1) * sel
    return soft, f1 / np.maximum(rad, 1e-6), ids


def ridged(field):
    """Гребни из шума: 1 у середины диапазона, 0 у краёв."""
    return 1.0 - np.abs(field * 2.0 - 1.0)


def hash01(ids, salt=0):
    """Хорошо перемешанный хэш id ячейки → 0..1 (линейные хэши дают полосы по диагонали)."""
    with np.errstate(over="ignore"):
        z = np.asarray(ids).astype(np.uint64) + np.uint64((salt * 0x9E3779B97F4A7C15) & 0xFFFFFFFFFFFFFFFF)
        z = (z ^ (z >> np.uint64(30))) * np.uint64(0xBF58476D1CE4E5B9)
        z = (z ^ (z >> np.uint64(27))) * np.uint64(0x94D049BB133111EB)
        z = z ^ (z >> np.uint64(31))
    return (z >> np.uint64(11)).astype(np.float64) / float(1 << 53)
