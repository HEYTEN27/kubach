"""Рецепты текстур по материалам. Каждый рецепт возвращает Tex: albedo, alpha, height,
roughness, metallic. Нормали и AO считает texgen.py по высоте.

alpha: для cutout-блоков (листва, растения) — покрытие; для непрозрачных — маска тонирования
цветом биома (1 — красить, 0 — нет; у дёрна красится только трава на боковой грани).
"""
from dataclasses import dataclass, field
import colorsys
import math

import numpy as np
from PIL import Image, ImageDraw, ImageFilter

from noise import fbm, value_noise, worley, warp, blur, normalize, dots, ridged, hash01


@dataclass
class Tex:
    albedo: np.ndarray            # (S, S, 3) 0..1
    alpha: np.ndarray             # (S, S) 0..1
    height: np.ndarray            # (S, S) 0..1
    rough: np.ndarray             # (S, S) 0..1
    metal: np.ndarray = None      # (S, S) 0..1
    normal_strength: float = 2.0
    emissive: bool = False


@dataclass
class Ctx:
    size: int
    rng: np.random.Generator
    color: tuple                  # базовый цвет блока (map_color), 0..1
    block: dict                   # запись блока из data/
    role: str                     # all/top/bottom/side
    variant: int
    name: str
    extra: dict = field(default_factory=dict)

    @property
    def tags(self):
        return self.block.get("tags", [])


def hex_rgb(h):
    h = h.lstrip("#")
    return tuple(int(h[i:i + 2], 16) / 255.0 for i in (0, 2, 4))


def shade(color, k):
    return np.clip(np.array(color) * k, 0, 1)


def hue_shift(color, dh=0.0, ds=0.0, dv=0.0):
    h, s, v = colorsys.rgb_to_hsv(*color)
    return colorsys.hsv_to_rgb((h + dh) % 1.0, min(1, max(0, s + ds)), min(1, max(0, v + dv)))


def colorize(base, mod):
    """base (3,) × поле модуляции (S,S) → (S,S,3)."""
    return np.clip(np.array(base)[None, None, :] * mod[..., None], 0, 1)


def lerp_img(a, b, t):
    return a * (1 - t[..., None]) + b * t[..., None]


def solid(ctx, rgb):
    return np.broadcast_to(np.array(rgb), (ctx.size, ctx.size, 3)).copy()


def ones(ctx, v=1.0):
    return np.full((ctx.size, ctx.size), v)


# ---------------------------------------------------------------------------------------------
# Камень

STONE_STYLE = {
    # id: (стиль, минералы [(цвет, доля)], трещины, шероховатость)
    "granite": ("grains", [("#e8d8cc", 0.22), ("#2a2624", 0.16), ("#c49080", 0.25)], 0.6, 0.78),
    "diorite": ("grains", [("#f2f0ea", 0.35), ("#2c2c2c", 0.25)], 0.5, 0.75),
    "gabbro": ("grains", [("#1c1d1e", 0.4), ("#5a5c58", 0.25)], 0.5, 0.7),
    "andesite": ("grains", [("#6e6c66", 0.3), ("#a8a59e", 0.12)], 0.6, 0.8),
    "basalt": ("pores", [], 0.7, 0.82),
    "tuff": ("pores", [("#a49e80", 0.3)], 0.4, 0.92),
    "pumice": ("pores", [], 0.2, 0.95),
    "obsidian": ("glass", [], 0.3, 0.12),
    "limestone": ("layers", [("#e0dac6", 0.1)], 0.5, 0.85),
    "sandstone": ("layers", [("#e8d6a0", 0.2)], 0.3, 0.9),
    "red_sandstone": ("layers", [("#c8704a", 0.2)], 0.3, 0.9),
    "dolomite": ("layers", [("#efe8dc", 0.15)], 0.5, 0.82),
    "chalk": ("layers", [("#ffffff", 0.1)], 0.3, 0.95),
    "shale": ("layers", [("#4a4844", 0.2)], 0.6, 0.8),
    "conglomerate": ("pebbles", [], 0.3, 0.85),
    "marble": ("veins", [("#bcb8b4", 0.0)], 0.2, 0.35),
    "slate": ("foliated", [("#3a3f46", 0.3)], 0.4, 0.7),
    "quartzite": ("grains", [("#f4ece8", 0.3), ("#c8b8b0", 0.2)], 0.4, 0.5),
    "gneiss": ("foliated", [("#d8d0c8", 0.35), ("#3a3634", 0.3)], 0.5, 0.75),
    "serpentinite": ("veins", [("#8ab88a", 0.0)], 0.4, 0.4),
    "deepslate": ("foliated", [("#2e2e34", 0.3)], 0.6, 0.75),
    "peridotite": ("grains", [("#6a8a3a", 0.35), ("#2a3020", 0.2)], 0.5, 0.75),
    "kimberlite": ("breccia", [("#2f3a38", 0.3), ("#6a7a70", 0.2)], 0.5, 0.85),
    "bedrock": ("chaos", [], 1.0, 0.95),
    "calcite": ("crystal", [], 0.3, 0.35),
    "quartz": ("crystal", [], 0.3, 0.2),
    "rock_salt": ("crystal", [], 0.4, 0.3),
    "rubble": ("pebbles", [], 0.4, 0.9),
    "sinter": ("layers", [("#f0e8d0", 0.2)], 0.3, 0.8),
}


def stone(ctx, style=None, minerals=None, cracks=None, rough=None, base=None):
    s = ctx.size
    rng = ctx.rng
    bid = ctx.block.get("id", "")
    st = STONE_STYLE.get(bid, ("grains", [], 0.5, 0.8))
    style = style or st[0]
    minerals = minerals if minerals is not None else st[1]
    cracks = st[2] if cracks is None else cracks
    rough_base = st[3] if rough is None else rough
    base = base or ctx.color

    large = fbm(s, 3, rng, 4)
    fine = fbm(s, 16, rng, 3)
    height = 0.45 * large + 0.25 * fine
    mod = 0.82 + 0.3 * large + 0.12 * (fine - 0.5)
    albedo = colorize(base, mod)
    rough_map = rough_base + 0.08 * (fine - 0.5)

    if style in ("grains", "breccia"):
        f1, f2, ids = worley(s, 22 if style == "grains" else 9, rng)
        cell_rand = hash01(ids, 3)
        acc = 0.0
        for col, frac in minerals:
            sel = (cell_rand >= acc) & (cell_rand < acc + frac)
            acc += frac
            c = np.array(hex_rgb(col))
            tint = 0.85 + 0.25 * fine
            albedo = np.where(sel[..., None], c[None, None, :] * tint[..., None], albedo)
            height = np.where(sel, height + 0.08, height)
        edge = np.clip((f2 - f1) * 4, 0, 1)
        albedo *= (0.85 + 0.15 * edge)[..., None]
    elif style == "layers":
        warp_n = fbm(s, 4, rng, 3)
        y = np.mgrid[0:s, 0:s][0] / s
        bands = np.sin((y * (5 + ctx.variant) + warp_n * 0.6) * 2 * math.pi)
        bands2 = np.sin((y * 13 + warp_n * 1.4) * 2 * math.pi)
        mod_b = 1.0 + 0.09 * bands + 0.05 * bands2
        albedo *= mod_b[..., None]
        height += 0.08 * bands2
        for col, frac in minerals:
            spots = value_noise(s, 32, rng) > 1 - frac * 0.6
            albedo = np.where(spots[..., None], lerp_img(albedo, solid(ctx, hex_rgb(col)), ones(ctx, 0.5)), albedo)
        # Окаменелости и пустотки — редкие округлые ямки.
        pits, _, _ = dots(s, 20, rng, 0.12, 0.18)
        albedo *= (1 - 0.25 * pits)[..., None]
        height -= pits * 0.15
    elif style == "foliated":
        n = fbm(s, 4, rng, 3)
        y = np.mgrid[0:s, 0:s][0] / s
        x = np.mgrid[0:s, 0:s][1] / s
        bands = np.sin((y * 9 + x * 1.0 + n * 1.2) * 2 * math.pi)
        thin = np.sin((y * 31 + n * 3) * 2 * math.pi)
        col_a = np.array(hex_rgb(minerals[0][0])) if minerals else np.array(base) * 1.2
        col_b = np.array(hex_rgb(minerals[1][0])) if len(minerals) > 1 else np.array(base) * 0.7
        t = np.clip(bands * 0.5 + 0.5, 0, 1) ** 2
        albedo = lerp_img(albedo, colorize(col_a, ones(ctx)), t * 0.55)
        albedo = lerp_img(albedo, colorize(col_b, ones(ctx)), np.clip(-thin, 0, 1) * 0.35)
        height += 0.1 * thin
    elif style == "veins":
        n = fbm(s, 3, rng, 5)
        vein = np.exp(-np.abs(n - 0.5) * 60)
        n2 = fbm(s, 5, rng, 4)
        vein2 = np.exp(-np.abs(n2 - 0.5) * 120) * 0.6
        vc = np.array(hex_rgb(minerals[0][0])) if minerals else np.array(base) * 0.6
        albedo = lerp_img(albedo, colorize(vc, ones(ctx)), np.clip(vein + vein2, 0, 1) * 0.8)
        rough_map -= 0.1 * vein
    elif style == "pores":
        holes, rel, _ = dots(s, 16, rng, 0.45 if bid != "pumice" else 0.8, 0.22)
        # Пора: тёмное дно, светлая кромка сверху (свет падает сверху-слева).
        albedo *= (1 - 0.55 * holes)[..., None]
        height -= holes * 0.35
        small, _, _ = dots(s, 40, rng, 0.35, 0.25)
        albedo *= (1 - 0.35 * small)[..., None]
        height -= small * 0.15
        for col, frac in minerals:
            spots, _, _ = dots(s, 24, rng, frac, 0.3)
            albedo = lerp_img(albedo, solid(ctx, hex_rgb(col)), spots * 0.5)
    elif style == "glass":
        n = fbm(s, 2, rng, 3)
        albedo = colorize(base, 0.7 + 0.6 * n)
        f1, f2, _ = worley(s, 5, rng)
        conch = np.sin(f1 * 18) * 0.5 + 0.5
        height = 0.3 * n + 0.15 * conch
        albedo += (conch[..., None] * 0.08)
        rough_map = rough_base + 0.05 * conch
    elif style == "pebbles":
        return gravel(ctx, big=True, base=base)
    elif style == "chaos":
        n = fbm(s, 5, rng, 5)
        f1, f2, _ = worley(s, 10, rng)
        albedo = colorize(base, 0.6 + 0.8 * n)
        light = (value_noise(s, 40, rng) > 0.88)
        albedo = np.where(light[..., None], colorize((0.55, 0.55, 0.58), ones(ctx)), albedo)
        height = 0.6 * n + 0.3 * (f2 - f1)
    elif style == "crystal":
        f1, f2, ids = worley(s, 6, rng)
        facet = hash01(ids, 3)
        albedo = colorize(base, 0.85 + 0.25 * facet)
        edge = np.clip((f2 - f1) * 6, 0, 1)
        albedo *= (0.8 + 0.2 * edge)[..., None]
        height = 0.5 * facet + 0.3 * edge
        rough_map = rough_base + 0.1 * (1 - edge)

    # Трещины: края ячеек Worley, только часть из них, с искажением.
    if cracks > 0:
        f1, f2, ids = worley(s, 4 + ctx.variant % 3, rng)
        dxn = fbm(s, 6, rng, 2) - 0.5
        dyn = fbm(s, 6, rng, 2) - 0.5
        edge = warp(f2 - f1, dxn, dyn, s * 0.06)
        keep = warp(hash01(ids, 5) * 100, dxn, dyn, s * 0.06) < cracks * 70
        crack = (edge < 0.035) & keep
        crack_soft = np.clip(1 - edge / 0.07, 0, 1) * keep
        albedo *= (1 - 0.45 * crack_soft)[..., None]
        height -= 0.35 * crack_soft
    # Сколы: неглубокие пятна.
    chips = fbm(s, 6, rng, 2)
    chip = np.clip((chips - 0.72) * 8, 0, 1)
    height -= 0.12 * chip
    albedo *= (1 + 0.06 * chip)[..., None]
    return Tex(np.clip(albedo, 0, 1), ones(ctx, 0.0), normalize(height), np.clip(rough_map, 0.05, 1), normal_strength=2.6)


def ore(ctx):
    """Руда: порода-хозяин + вкрапления минерала (металл блестит, самоцвет — кристаллы)."""
    s = ctx.size
    tags = ctx.tags
    deep = "deep" in tags
    host_color = (0.28, 0.28, 0.31) if deep else (0.52, 0.5, 0.48)
    host = stone(ctx, style="foliated" if deep else "grains",
                 minerals=[("#3a3a40", 0.2)] if deep else [("#6a6662", 0.2), ("#8a8682", 0.15)],
                 cracks=0.4, rough=0.82, base=host_color)
    rng = ctx.rng
    metal_tags = {"copper", "tin", "iron", "lead", "zinc", "nickel", "silver", "gold", "platinum"}
    is_metal = any(t in metal_tags for t in tags)
    gem = "gem" in tags
    fuel = "coal" in tags
    # Вкрапления неправильной формы: Worley с искажением домена, разного размера.
    f1, f2, ids = worley(s, 6 if gem else 8, rng)
    dxn = fbm(s, 8, rng, 3) - 0.5
    dyn = fbm(s, 8, rng, 3) - 0.5
    f1 = warp(f1, dxn, dyn, s * 0.07)
    ids = warp(ids, dxn, dyn, s * 0.07)
    sel = hash01(ids, 6) < (0.45 if not gem else 0.32)
    size_k = 0.25 + 0.2 * hash01(ids, 7)
    rel = f1 / size_k
    blob = sel & (rel < 1.0)
    # Мелкая сыпь вокруг крупных зёрен.
    specks, _, _ = dots(s, 30, rng, 0.25 if not gem else 0.1, 0.3)
    specks = specks * (~blob)
    c = np.array(ctx.color)
    if gem:
        facet = np.floor(hash01(ids, 8) * 7) / 7.0
        tint = 0.7 + 0.5 * facet + 0.35 * np.clip(1 - rel, 0, 1) ** 2
    else:
        tint = 0.75 + 0.35 * fbm(s, 24, rng, 2) + 0.25 * np.clip(1 - rel, 0, 1)
    mineral = colorize(c, tint)
    rim = blob & (rel > 0.78)
    albedo = np.where(blob[..., None], mineral, host.albedo)
    albedo = np.where(rim[..., None], albedo * 0.7, albedo)
    albedo = lerp_img(albedo, colorize(c, 0.9 * ones(ctx)), specks * 0.8)
    height = host.height + blob * (0.25 if gem else 0.14) * np.clip(1.2 - rel, 0, 1) + specks * 0.05
    rough = np.where(blob, 0.15 if gem else (0.3 if is_metal else (0.45 if fuel else 0.6)), host.rough)
    metal = np.where(blob & is_metal, 0.9, 0.0) + specks * (0.8 if is_metal else 0.0)
    return Tex(albedo, ones(ctx, 0.0), normalize(height), rough, metal, normal_strength=2.6)


# ---------------------------------------------------------------------------------------------
# Почвы, песок, гравий, снег, лёд

def soil(ctx, pebbles=0.08, roots=False, cracks=False, crumbs=0.5, base=None):
    s = ctx.size
    rng = ctx.rng
    base = base or ctx.color
    n = fbm(s, 6, rng, 4)
    g = value_noise(s, 64, rng)
    albedo = colorize(base, 0.78 + 0.35 * n + 0.18 * (g - 0.5) * crumbs)
    height = 0.5 * n + 0.3 * g * crumbs
    rough = 0.9 + 0.05 * (g - 0.5)
    if pebbles > 0:
        peb, rel, ids = dots(s, 10, rng, pebbles * 2.5, 0.32)
        # Камешек: свой оттенок, выпуклость, светлый верх и тень снизу.
        tone = 0.7 + 0.5 * hash01(ids, 9)
        pcol = colorize((0.5, 0.47, 0.43), tone * (0.9 + 0.1 * g))
        dome = np.sqrt(np.clip(1 - rel ** 2, 0, 1))
        pcol *= (0.75 + 0.35 * dome)[..., None]
        albedo = lerp_img(albedo, pcol, peb)
        shadow = np.clip(np.roll(peb, 2, 0) - peb, 0, 1)
        albedo *= (1 - 0.35 * shadow)[..., None]
        height += peb * dome * 0.5
    if roots:
        for _ in range(5):
            r = fbm(s, 3, rng, 3)
            line = np.exp(-np.abs(r - 0.5) * 90)
            albedo = lerp_img(albedo, colorize(shade(base, 1.5), ones(ctx)), line * 0.5)
            height += line * 0.1
    if cracks:
        f1, f2, _ = worley(s, 5, rng)
        cr = np.clip(1 - (f2 - f1) / 0.05, 0, 1)
        albedo *= (1 - 0.5 * cr)[..., None]
        height -= cr * 0.4
    return Tex(np.clip(albedo, 0, 1), ones(ctx, 0.0), normalize(height), rough, normal_strength=1.8)


def sand(ctx, base=None):
    s = ctx.size
    rng = ctx.rng
    base = base or ctx.color
    fine = value_noise(s, 128, rng)
    n = fbm(s, 4, rng, 3)
    y = np.mgrid[0:s, 0:s][0] / s
    ripple = np.sin((y * 6 + n * 0.8) * 2 * math.pi) * 0.5 + 0.5
    albedo = colorize(base, 0.85 + 0.15 * n + 0.12 * (fine - 0.5) + 0.05 * ripple)
    dark = value_noise(s, 128, rng) > 0.9
    albedo *= np.where(dark, 0.7, 1.0)[..., None]
    height = 0.3 * ripple + 0.3 * fine
    return Tex(np.clip(albedo, 0, 1), ones(ctx, 0.0), normalize(height), 0.92 + 0.04 * fine, normal_strength=1.2)


def gravel(ctx, big=False, base=None):
    s = ctx.size
    rng = ctx.rng
    base = base or ctx.color
    f1, f2, ids = worley(s, 7 if big else 11, rng)
    r = hash01(ids, 4)
    stone_tone = 0.7 + 0.6 * r
    hue = np.floor(hash01(ids, 10) * 3)
    col = np.array(base)[None, None, :] * stone_tone[..., None]
    col = np.where((hue == 1)[..., None], col * np.array([1.05, 1.0, 0.92]), col)
    col = np.where((hue == 2)[..., None], col * np.array([0.92, 0.95, 1.05]), col)
    dome = np.clip((f2 - f1) * 3.2, 0, 1)
    grit = value_noise(s, 64, rng)
    albedo = col * (0.55 + 0.45 * dome)[..., None] * (0.92 + 0.16 * grit)[..., None]
    height = dome * (0.8 + 0.2 * r) + 0.1 * grit
    return Tex(np.clip(albedo, 0, 1), ones(ctx, 0.0), normalize(height), 0.78 + 0.1 * grit, normal_strength=3.0)


def snow(ctx):
    s = ctx.size
    rng = ctx.rng
    n = fbm(s, 4, rng, 4)
    albedo = colorize(ctx.color, 0.92 + 0.1 * n)
    albedo[..., 2] = np.clip(albedo[..., 2] + 0.03 * (1 - n), 0, 1)
    sparkle = value_noise(s, 128, rng) > 0.97
    rough = np.where(sparkle, 0.2, 0.75)
    return Tex(np.clip(albedo, 0, 1), ones(ctx, 0.0), normalize(n), rough, normal_strength=0.8)


def ice(ctx, packed=False):
    s = ctx.size
    rng = ctx.rng
    n = fbm(s, 3, rng, 4)
    albedo = colorize(ctx.color, 0.85 + 0.25 * n)
    f1, f2, _ = worley(s, 4, rng)
    cr = np.clip(1 - (f2 - f1) / 0.03, 0, 1)
    albedo = lerp_img(albedo, colorize((0.92, 0.96, 1.0), ones(ctx)), cr * 0.7)
    bub = worley(s, 20, rng)[0] < 0.08
    albedo = np.where(bub[..., None], albedo * 1.15, albedo)
    alpha = ones(ctx, 0.0) if packed else 0.75 + 0.15 * cr
    return Tex(np.clip(albedo, 0, 1), alpha, normalize(n + cr * 0.3), 0.08 + 0.1 * cr, normal_strength=0.8)


def turf_top(ctx):
    """Дёрн сверху: тысячи коротких травинок разной длины и яркости, между ними — тень и земля."""
    s = ctx.size
    rng = ctx.rng
    k = 3
    big = s * k
    base = np.array(ctx.color)
    img = Image.new("RGB", (big, big), tuple(int(255 * c * 0.38) for c in base))
    hm = Image.new("L", (big, big), 0)
    d = ImageDraw.Draw(img)
    dh = ImageDraw.Draw(hm)
    clump = fbm(s, 4, rng, 3)
    count = 2600
    for i in range(count):
        x, y = rng.random(2) * big
        depth = i / count
        cl = clump[int(y / k) % s, int(x / k) % s]
        a = rng.random() * 2 * math.pi
        L = big * (0.012 + 0.02 * rng.random()) * (0.7 + 0.6 * cl)
        v = 0.5 + 0.55 * depth + 0.2 * (cl - 0.5) + 0.15 * rng.random()
        hue = hue_shift(tuple(base), (rng.random() - 0.5) * 0.06, (rng.random() - 0.5) * 0.1)
        col = tuple(int(255 * min(1, c * v)) for c in hue)
        hv = int(40 + 200 * depth)
        for ox in (-big, 0, big):
            for oy in (-big, 0, big):
                seg = [(x + ox, y + oy), (x + ox + math.cos(a) * L, y + oy + math.sin(a) * L)]
                d.line(seg, fill=col, width=k)
                dh.line(seg, fill=hv, width=k)
    img = img.resize((s, s), Image.LANCZOS)
    hm = hm.resize((s, s), Image.LANCZOS)
    albedo = np.asarray(img).astype(float) / 255
    height = np.asarray(hm).astype(float) / 255
    # Проплешины с землёй — маска тонирования там 0, чтобы земля не зеленела.
    bare = np.clip((fbm(s, 6, rng, 3) - 0.8) * 8, 0, 1)
    dirt = soil(ctx, pebbles=0.0, base=hex_rgb("#6a4e34"))
    albedo = lerp_img(albedo, dirt.albedo, bare * 0.85)
    tint = 1 - bare * 0.85
    height = height * (1 - bare) + dirt.height * 0.3 * bare
    return Tex(np.clip(albedo, 0, 1), tint, normalize(height), 0.9 + 0.05 * height, normal_strength=1.6)


def turf_side(ctx, grass_color=None, dirt_color=None):
    """Земля с бахромой травы сверху; маска тонирования — только трава."""
    s = ctx.size
    rng = ctx.rng
    dirt = soil(ctx, pebbles=0.06, base=dirt_color or hex_rgb("#7a5a3c"))
    top = turf_top(ctx)
    x = np.arange(s)
    edge = (0.16 + 0.08 * value_noise(s, 16, rng)[0] + 0.07 * value_noise(s, 48, rng)[1]) * s
    y = np.mgrid[0:s, 0:s][0]
    mask = (y < edge[None, :]).astype(float)
    # Отдельные травинки, свисающие ниже кромки.
    drops = value_noise(s, 64, rng)[2] > 0.72
    extra = (y < edge[None, :] + 8 * drops[None, :]) & (y >= edge[None, :])
    mask = np.maximum(mask, extra * 0.85)
    if grass_color is not None:
        top.albedo = colorize(grass_color, top.albedo.mean(axis=2) / max(1e-3, np.mean(grass_color)))
    albedo = lerp_img(dirt.albedo, top.albedo, mask)
    # Тень под кромкой.
    shadow = np.clip(1 - (y - edge[None, :]) / 6.0, 0, 1) * (1 - mask)
    albedo *= (1 - 0.25 * shadow)[..., None]
    height = np.where(mask > 0.5, top.height * 0.5 + 0.5, dirt.height * 0.8)
    return Tex(np.clip(albedo, 0, 1), mask, normalize(height), np.where(mask > 0.5, 0.9, dirt.rough), normal_strength=1.8)


# ---------------------------------------------------------------------------------------------
# Дерево

def bark(ctx):
    s = ctx.size
    rng = ctx.rng
    bid = ctx.block.get("id", "")
    base = ctx.color
    if bid.startswith("birch") or bid.startswith("aspen") or bid.startswith("dwarf_birch"):
        n = fbm(s, 4, rng, 3)
        albedo = colorize(base, 0.9 + 0.15 * n)
        # Чечевички — тёмные горизонтальные штрихи.
        stripe = fbm(s, 24, rng, 2, aniso=(1.0, 0.15))
        lent = stripe > 0.68
        albedo = np.where(lent[..., None], colorize((0.15, 0.13, 0.12), ones(ctx)), albedo)
        patches = fbm(s, 3, rng, 3) > 0.7
        albedo = np.where(patches[..., None], albedo * 0.55, albedo)
        height = 0.5 * n - 0.3 * lent
        return Tex(np.clip(albedo, 0, 1), ones(ctx, 0.0), normalize(height), 0.75 + 0.1 * n, normal_strength=1.6)
    if bid.startswith("bamboo"):
        return bamboo_block(ctx)
    # Глубокие узкие продольные трещины между широкими пластинами коры.
    n1 = fbm(s, 6, rng, 4, aniso=(0.17, 1.0))
    n2 = fbm(s, 11, rng, 3, aniso=(0.18, 1.0))
    jag = fbm(s, 16, rng, 2) - 0.5
    fiss = np.clip((ridged(n1 + 0.06 * jag) - 0.8) / 0.2, 0, 1)
    fiss = np.maximum(fiss, np.clip((ridged(n2 + 0.08 * jag) - 0.86) / 0.14, 0, 1) * 0.7)
    # Поперечные разломы пластин: короткие горизонтальные трещины.
    hb = np.clip((ridged(fbm(s, 4, rng, 3, aniso=(2.5, 0.35))) - 0.95) / 0.05, 0, 1)
    hb *= fbm(s, 8, rng, 2) > 0.62
    fiss = np.maximum(fiss, hb * 0.8)
    plates = 1 - fiss
    fine = fbm(s, 32, rng, 2, aniso=(0.4, 1.0))
    body = fbm(s, 4, rng, 3, aniso=(0.5, 1.5))
    albedo = colorize(base, (0.3 + 0.8 * plates) * (0.8 + 0.4 * body) + 0.2 * (fine - 0.5))
    # Выпуклые места пластин выцветают и сереют.
    grey = np.clip((body - 0.6) * 3, 0, 1) * plates
    albedo = lerp_img(albedo, colorize(np.array(base) * 0.5 + 0.25, ones(ctx)), grey * 0.35)
    moss = np.clip((fbm(s, 3, rng, 4) - 0.7) * 5, 0, 1) * (0.4 + 0.6 * (1 - body))
    albedo = lerp_img(albedo, colorize((0.3, 0.42, 0.18), 0.8 + 0.4 * fine), moss * 0.7)
    height = plates * (0.6 + 0.3 * body) + 0.12 * fine + moss * 0.1
    return Tex(np.clip(albedo, 0, 1), ones(ctx, 0.0), normalize(height), 0.86 + 0.1 * plates, normal_strength=3.4)


def log_end(ctx):
    """Торец бревна: годичные кольца с неравным шагом, радиальные трещины-клинья, кора по краю."""
    s = ctx.size
    rng = ctx.rng
    ys, xs = np.mgrid[0:s, 0:s] + 0.5
    c = s / 2 + (rng.random(2) - 0.5) * s * 0.1
    n = fbm(s, 4, rng, 3)
    ang = np.arctan2(ys - c[0], xs - c[1])
    r = np.sqrt((ys - c[0]) ** 2 + (xs - c[1]) ** 2) / s
    r_w = r * (1 + 0.06 * (n - 0.5)) + 0.012 * np.sin(ang * 3 + rng.random() * 6)
    # Неравный шаг колец: «время» растёт нелинейно с радиусом.
    years = 20 + 5 * ctx.variant
    t = (np.maximum(r_w, 0.0) / 0.45) ** 0.85 * years
    phase = t % 1.0
    late = np.clip((phase - 0.7) / 0.3, 0, 1)            # поздняя (тёмная) древесина
    wood = hue_shift(ctx.color, 0.0, -0.15, 0.22)
    fine = fbm(s, 32, rng, 2)
    albedo = colorize(wood, 0.95 - 0.28 * late + 0.08 * (n - 0.5) + 0.06 * (fine - 0.5))
    pith = np.clip(1 - r / 0.03, 0, 1)
    albedo *= (1 - 0.4 * pith)[..., None]
    # Кора: неровный обод.
    rim_r = 0.44 + 0.025 * (fbm(s, 6, rng, 2) - 0.5)
    bark_rim = r > rim_r
    inner = (r > rim_r - 0.03) & ~bark_rim                 # камбий — светлая полоска
    bark_col = colorize(shade(ctx.color, 0.75), 0.6 + 0.6 * fbm(s, 24, rng, 3))
    albedo = np.where(inner[..., None], albedo * 1.12, albedo)
    albedo = np.where(bark_rim[..., None], bark_col, albedo)
    # Радиальные трещины усушки: клинья, расширяющиеся к краю.
    height = 0.25 * (1 - late) + 0.05 * fine
    cracks = np.zeros((s, s))
    for _ in range(2 + int(rng.integers(0, 3))):
        a0 = rng.random() * 2 * math.pi
        length = 0.25 + 0.17 * rng.random()
        da = np.angle(np.exp(1j * (ang - a0 - 0.15 * (n - 0.5))))
        width = 0.004 + 0.05 * np.clip(r - (rim_r - length), 0, 1)
        w = np.clip(1 - np.abs(da) * r / np.maximum(width, 1e-4), 0, 1)
        w *= (r > rim_r - length) & (r < rim_r)
        cracks = np.maximum(cracks, w)
    albedo *= (1 - 0.65 * cracks)[..., None]
    height = np.where(bark_rim, 0.7 + 0.2 * n, height) - cracks * 0.5
    return Tex(np.clip(albedo, 0, 1), ones(ctx, 0.0), normalize(height), 0.8 + 0.1 * late, normal_strength=1.8)


def bamboo_block(ctx):
    s = ctx.size
    rng = ctx.rng
    y = np.mgrid[0:s, 0:s][0]
    node = (y % (s // 4)) < 3
    n = fbm(s, 4, rng, 2, aniso=(0.3, 2))
    albedo = colorize(ctx.color, 0.85 + 0.25 * n)
    albedo = np.where(node[..., None], albedo * 0.7, albedo)
    return Tex(np.clip(albedo, 0, 1), ones(ctx, 0.0), normalize(n - node * 0.5), 0.6, normal_strength=2.0)


def leaves(ctx, needles=False, fronds=False):
    """Листва: множество листиков на прозрачном фоне, бесшовно (рисуем с переносом)."""
    s = ctx.size
    rng = ctx.rng
    k = 4
    big = s * k
    img = Image.new("RGBA", (big, big), (0, 0, 0, 0))
    hmap = Image.new("L", (big, big), 0)
    d = ImageDraw.Draw(img)
    dh = ImageDraw.Draw(hmap)
    base = np.array(ctx.color)
    count = 300 if needles else 260

    def put(draw_fn):
        for ox in (-big, 0, big):
            for oy in (-big, 0, big):
                draw_fn(ox, oy)

    for i in range(count):
        x, y = rng.random(2) * big
        a = rng.random() * 2 * math.pi
        # Порядок рисования = глубина: задние листья темнее, передние светлее и выше.
        depth = i / count
        v = 0.5 + 0.55 * depth + 0.25 * rng.random()
        col = tuple(int(255 * min(1, c * v)) for c in hue_shift(tuple(base), (rng.random() - 0.5) * 0.05)) + (255,)
        hv = int(60 + 180 * depth + 15 * rng.random())
        if needles:
            # Веточка: стебелёк и хвоинки по обе стороны под углом, к кончику короче.
            L = big * (0.05 + 0.03 * rng.random())
            nl = big * 0.022
            spread = 0.75 + 0.3 * rng.random()
            steps = 11
            twig = []
            for t in range(steps + 1):
                f = t / steps
                px, py = x + math.cos(a) * L * f, y + math.sin(a) * L * f
                ln = nl * (1.0 - 0.45 * f)
                for side in (-1, 1):
                    b = a + side * spread
                    twig.append(((px, py), (px + math.cos(b) * ln, py + math.sin(b) * ln)))
            stem_col = tuple(int(255 * min(1, c * v * 0.8)) for c in (0.45, 0.33, 0.2)) + (255,)

            def draw_twig(ox, oy, twig=twig, col=col, hv=hv, x=x, y=y, a=a, L=L, stem_col=stem_col):
                for p0, p1 in twig:
                    seg = [(p0[0] + ox, p0[1] + oy), (p1[0] + ox, p1[1] + oy)]
                    d.line(seg, fill=col, width=k)
                    dh.line(seg, fill=hv, width=k)
                stem = [(x + ox, y + oy), (x + math.cos(a) * L + ox, y + math.sin(a) * L + oy)]
                d.line(stem, fill=stem_col, width=k)
                dh.line(stem, fill=min(255, hv + 20), width=k)
            put(draw_twig)
        else:
            L = big * (0.045 if not fronds else 0.07)
            W = L * (0.45 if not fronds else 0.25)
            pts0 = []
            for t in range(16):
                ang = t / 16 * 2 * math.pi
                # Лист с острым кончиком и округлым основанием.
                px = math.cos(ang) * L
                py = math.sin(ang) * W * (1 - 0.35 * max(0.0, math.cos(ang)))
                pts0.append((px * math.cos(a) - py * math.sin(a), px * math.sin(a) + py * math.cos(a)))
            vein_col = tuple(int(255 * min(1, c * v * 1.15)) for c in base) + (255,)

            def draw_leaf(ox, oy, pts0=pts0, col=col, hv=hv, x=x, y=y, a=a, L=L, vein_col=vein_col):
                pts = [(x + px + ox, y + py + oy) for px, py in pts0]
                d.polygon(pts, fill=col)
                dh.polygon(pts, fill=hv)
                vein = [(x - math.cos(a) * L * 0.8 + ox, y - math.sin(a) * L * 0.8 + oy),
                        (x + math.cos(a) * L * 0.8 + ox, y + math.sin(a) * L * 0.8 + oy)]
                d.line(vein, fill=vein_col, width=max(1, k // 2))
                dh.line(vein, fill=min(255, hv + 25), width=max(1, k // 2))
            put(draw_leaf)
    img = img.resize((s, s), Image.LANCZOS)
    hmap = hmap.resize((s, s), Image.LANCZOS).filter(ImageFilter.GaussianBlur(0.7))
    a = np.asarray(img).astype(float) / 255
    alpha = (a[..., 3] > 0.45).astype(float)
    albedo = np.where(alpha[..., None] > 0, a[..., :3] / np.maximum(a[..., 3:4], 1e-3), base[None, None, :])
    h = np.asarray(hmap).astype(float) / 255
    return Tex(np.clip(albedo, 0, 1), alpha, h, 0.7 + 0.1 * h, normal_strength=2.0)


# ---------------------------------------------------------------------------------------------
# Растения (спрайты для креста — не бесшовные)

def _rgba(c, a=255):
    return tuple(int(255 * max(0, min(1, v))) for v in c) + (a,)


def plant(ctx):
    s = ctx.size
    rng = ctx.rng
    k = 4
    big = s * k
    img = Image.new("RGBA", (big, big), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    bid = ctx.block.get("id", "")
    tags = ctx.tags
    col = ctx.color
    green = hex_rgb("#4f7a33") if ctx.block.get("tint", "none") == "none" else col

    def blade(x0, height, lean, width, c):
        x1 = x0 + lean
        d.polygon([(x0 - width, big), (x0 + width, big), (x1, big - height)], fill=_rgba(c))

    def stem(x, top, c=green, w=None):
        d.line([(x, big), (x + rng.normal() * k * 2, top)], fill=_rgba(c), width=w or k * 2)

    if bid in ("grass", "tall_grass", "sedge", "feather_grass") or "grass" in tags and "flower" not in tags:
        n = 26 if bid != "tall_grass" else 34
        hmax = big * (0.55 if bid == "grass" else 0.95)
        for _ in range(n):
            x = big * (0.1 + 0.8 * rng.random())
            c = shade(col, 0.75 + 0.4 * rng.random())
            blade(x, hmax * (0.45 + 0.55 * rng.random()), (rng.random() - 0.5) * big * 0.25, k * 2.2, c)
        if bid == "feather_grass":
            for _ in range(10):
                x = big * (0.2 + 0.6 * rng.random())
                d.line([(x, big * 0.5), (x + (rng.random() - 0.3) * big * 0.4, big * 0.05)], fill=_rgba((0.95, 0.95, 0.9), 230), width=k)
    elif "flower" in tags:
        for _ in range(3 if bid not in ("lupine", "fireweed", "martagon_lily") else 2):
            x = big * (0.25 + 0.5 * rng.random())
            top = big * (0.25 + 0.3 * rng.random())
            stem(x, top)
            for i in range(3):
                ly = big - (big - top) * (0.3 + 0.2 * i)
                side = 1 if i % 2 else -1
                x2 = x + side * big * 0.12
                d.ellipse([min(x, x2), ly - k * 3, max(x, x2), ly + k * 3], fill=_rgba(shade(green, 0.9)))
            if bid in ("lupine", "fireweed", "heather", "sage", "thyme"):
                for j in range(8):
                    yy = top + j * k * 5
                    d.ellipse([x - k * 5, yy - k * 3, x + k * 5, yy + k * 3], fill=_rgba(shade(col, 0.85 + 0.03 * j)))
            elif bid in ("bellflower", "lily_of_the_valley", "snowdrop"):
                for j in range(3):
                    bx, by = x + (j - 1) * k * 10, top + j * k * 6
                    d.pieslice([bx - k * 6, by - k * 6, bx + k * 6, by + k * 8], 0, 180, fill=_rgba(col))
            else:
                r = big * (0.07 + 0.03 * rng.random())
                petals = 5 if bid not in ("chamomile", "yarrow", "edelweiss") else 12
                for p in range(petals):
                    a = p / petals * 2 * math.pi
                    px, py = x + math.cos(a) * r, top + math.sin(a) * r * 0.8
                    d.ellipse([px - r * 0.55, py - r * 0.4, px + r * 0.55, py + r * 0.4], fill=_rgba(col))
                center = (0.95, 0.8, 0.2) if bid in ("chamomile", "yarrow") else shade(col, 0.6)
                d.ellipse([x - r * 0.35, top - r * 0.35, x + r * 0.35, top + r * 0.35], fill=_rgba(center))
    elif "mushroom" in tags:
        x = big / 2 + rng.normal() * k * 6
        cap_w = big * (0.22 + 0.06 * rng.random())
        cap_y = big * (0.55 + 0.1 * rng.random())
        stem_col = (0.92, 0.88, 0.78) if bid not in ("chanterelle", "false_chanterelle") else col
        d.rectangle([x - cap_w * 0.25, cap_y, x + cap_w * 0.25, big], fill=_rgba(stem_col))
        if bid in ("chanterelle", "false_chanterelle"):
            d.polygon([(x - cap_w, cap_y - k * 6), (x + cap_w, cap_y - k * 6), (x, cap_y + cap_w * 0.5)], fill=_rgba(col))
        else:
            d.pieslice([x - cap_w, cap_y - cap_w * 0.8, x + cap_w, cap_y + cap_w * 0.6], 180, 360, fill=_rgba(col))
        if bid == "fly_agaric":
            for _ in range(7):
                sx = x + (rng.random() - 0.5) * cap_w * 1.4
                sy = cap_y - rng.random() * cap_w * 0.6
                d.ellipse([sx - k * 3, sy - k * 3, sx + k * 3, sy + k * 3], fill=_rgba((0.97, 0.97, 0.95)))
        if bid == "death_cap":
            d.rectangle([x - cap_w * 0.3, cap_y + big * 0.12, x + cap_w * 0.3, cap_y + big * 0.14], fill=_rgba((0.85, 0.85, 0.75)))
    elif "berry" in tags or bid in ("juniper", "labrador_tea"):
        leaf = hex_rgb("#3f6a35") if bid != "juniper" else hex_rgb("#3a5a50")
        for _ in range(60):
            x = big * (0.15 + 0.7 * rng.random())
            y = big * (0.35 + 0.65 * rng.random())
            d.ellipse([x - k * 6, y - k * 4, x + k * 6, y + k * 4], fill=_rgba(shade(leaf, 0.7 + 0.5 * rng.random())))
        if "berry" in tags:
            for _ in range(14):
                x = big * (0.2 + 0.6 * rng.random())
                y = big * (0.4 + 0.5 * rng.random())
                d.ellipse([x - k * 4, y - k * 4, x + k * 4, y + k * 4], fill=_rgba(col))
        if bid == "labrador_tea":
            for _ in range(5):
                x = big * (0.25 + 0.5 * rng.random())
                y = big * (0.3 + 0.2 * rng.random())
                d.ellipse([x - k * 6, y - k * 6, x + k * 6, y + k * 6], fill=_rgba((0.96, 0.96, 0.92)))
    elif bid in ("fern", "nettle", "plantain"):
        for f in range(4 if bid == "fern" else 5):
            x0 = big * (0.3 + 0.4 * rng.random())
            ang = -math.pi / 2 + (rng.random() - 0.5) * 1.6
            L = big * (0.7 if bid == "fern" else 0.45)
            for t in range(18):
                px = x0 + math.cos(ang) * L * t / 18
                py = big + math.sin(ang) * L * t / 18
                w = (1 - t / 18) * big * (0.12 if bid == "fern" else 0.08)
                d.ellipse([px - w, py - k * 3, px + w, py + k * 3], fill=_rgba(shade(col, 0.8 + 0.3 * rng.random())))
    elif bid == "reeds":
        for _ in range(9):
            x = big * (0.15 + 0.7 * rng.random())
            top = big * (0.05 + 0.25 * rng.random())
            d.line([(x, big), (x + rng.normal() * k * 3, top)], fill=_rgba(col), width=k * 2)
        for _ in range(3):
            x = big * (0.3 + 0.4 * rng.random())
            y = big * (0.15 + 0.15 * rng.random())
            d.rounded_rectangle([x - k * 4, y, x + k * 4, y + big * 0.16], radius=k * 3, fill=_rgba((0.42, 0.27, 0.15)))
    elif bid == "dead_bush" or bid == "lichen":
        c = col
        def branch(x, y, a, L, depth):
            if depth == 0 or L < k * 3:
                return
            x2, y2 = x + math.cos(a) * L, y + math.sin(a) * L
            d.line([(x, y), (x2, y2)], fill=_rgba(c), width=max(k, int(k * depth * 0.8)))
            for _ in range(2):
                branch(x2, y2, a + (rng.random() - 0.5) * 1.4, L * 0.68, depth - 1)
        for _ in range(3):
            branch(big * (0.4 + 0.2 * rng.random()), big, -math.pi / 2 + (rng.random() - 0.5) * 0.6, big * 0.3, 5)
    elif bid == "bamboo_stalk":
        x = big / 2
        d.rectangle([x - k * 7, 0, x + k * 7, big], fill=_rgba(col))
        for y in range(0, big, big // 4):
            d.rectangle([x - k * 8, y, x + k * 8, y + k * 3], fill=_rgba(shade(col, 0.65)))
        d.ellipse([x, big * 0.3, x + big * 0.25, big * 0.36], fill=_rgba(shade(col, 0.9)))
    else:
        for _ in range(20):
            x = big * (0.1 + 0.8 * rng.random())
            blade(x, big * (0.3 + 0.5 * rng.random()), (rng.random() - 0.5) * big * 0.2, k * 2, shade(col, 0.8 + 0.4 * rng.random()))

    img = img.resize((s, s), Image.LANCZOS)
    a = np.asarray(img).astype(float) / 255
    alpha = (a[..., 3] > 0.4).astype(float)
    albedo = np.where(alpha[..., None] > 0, a[..., :3] / np.maximum(a[..., 3:4], 1e-3), np.array(col)[None, None, :])
    height = blur(alpha, 2)
    return Tex(np.clip(albedo, 0, 1), alpha, height, 0.75 + 0.0 * height, normal_strength=1.0)


# ---------------------------------------------------------------------------------------------
# Прочее

def lava(ctx):
    s = ctx.size
    rng = ctx.rng
    f1, f2, _ = worley(s, 6, rng)
    n = fbm(s, 5, rng, 4)
    crust = np.clip((f2 - f1) * 5 - 0.15 + 0.4 * (n - 0.5), 0, 1)
    hot = np.array((1.0, 0.55, 0.12))
    dark = np.array((0.18, 0.07, 0.04))
    albedo = lerp_img(colorize(hot, 0.85 + 0.3 * n), colorize(dark, ones(ctx)), crust)
    return Tex(np.clip(albedo, 0, 1), ones(ctx, 0.0), normalize(crust), 0.6 + 0.3 * crust, normal_strength=2.0, emissive=True)


def water(ctx):
    s = ctx.size
    rng = ctx.rng
    n = fbm(s, 4, rng, 4)
    albedo = colorize(ctx.color, 0.85 + 0.3 * n)
    return Tex(albedo, ones(ctx, 0.0), n, ones(ctx, 0.05), normal_strength=0.6)


def coral(ctx):
    s = ctx.size
    rng = ctx.rng
    f1, f2, ids = worley(s, 14, rng)
    n = fbm(s, 6, rng, 3)
    bump = np.clip(1 - f1 * 2.2, 0, 1)
    albedo = colorize(ctx.color, 0.65 + 0.5 * bump + 0.15 * n)
    pores = f1 < 0.12
    albedo *= np.where(pores, 0.5, 1.0)[..., None]
    return Tex(np.clip(albedo, 0, 1), ones(ctx, 0.0), normalize(bump - pores * 0.5), 0.7, normal_strength=3.0)


def cactus(ctx):
    s = ctx.size
    rng = ctx.rng
    x = np.mgrid[0:s, 0:s][1] / s
    ribs = np.cos(x * 8 * math.pi) * 0.5 + 0.5
    n = fbm(s, 6, rng, 3)
    albedo = colorize(ctx.color, 0.7 + 0.4 * ribs + 0.1 * n)
    spines = (value_noise(s, 48, rng) > 0.93) & (ribs > 0.8)
    albedo = np.where(spines[..., None], colorize((0.9, 0.88, 0.7), ones(ctx)), albedo)
    return Tex(np.clip(albedo, 0, 1), ones(ctx, 0.0), normalize(ribs + spines * 0.5), 0.6, normal_strength=2.5)


def mushroom_cap(ctx):
    s = ctx.size
    rng = ctx.rng
    n = fbm(s, 4, rng, 3)
    albedo = colorize(ctx.color, 0.85 + 0.3 * n)
    if "red" in ctx.block.get("id", ""):
        f1, _, ids = worley(s, 5, rng)
        spot = (f1 < 0.22) & (hash01(ids, 11) < 0.6)
        albedo = np.where(spot[..., None], colorize((0.97, 0.95, 0.9), ones(ctx)), albedo)
        n = n + spot * 0.4
    return Tex(np.clip(albedo, 0, 1), ones(ctx, 0.0), normalize(n), 0.55, normal_strength=1.5)


def fibrous(ctx):
    s = ctx.size
    rng = ctx.rng
    n = fbm(s, 6, rng, 3, aniso=(0.25, 2.0))
    albedo = colorize(ctx.color, 0.85 + 0.25 * n)
    return Tex(np.clip(albedo, 0, 1), ones(ctx, 0.0), normalize(n), 0.75, normal_strength=1.5)


def layer_top(ctx):
    """Тонкие слои: снег, мох, лишайник, опавшая листва, кувшинка."""
    bid = ctx.block.get("id", "")
    if bid == "snow_layer":
        return snow(ctx)
    if bid == "water_lily":
        s = ctx.size
        rng = ctx.rng
        img = Image.new("RGBA", (s * 4, s * 4), (0, 0, 0, 0))
        d = ImageDraw.Draw(img)
        c = s * 2
        r = s * 1.6
        start = rng.random() * 360
        d.pieslice([c - r, c - r, c + r, c + r], start + 25, start + 360, fill=_rgba(ctx.color))
        d.ellipse([c - s * 0.3, c - s * 0.3, c + s * 0.3, c + s * 0.3], fill=_rgba((0.96, 0.92, 0.95)))
        img = img.resize((s, s), Image.LANCZOS)
        a = np.asarray(img).astype(float) / 255
        alpha = (a[..., 3] > 0.4).astype(float)
        albedo = np.where(alpha[..., None] > 0, a[..., :3] / np.maximum(a[..., 3:4], 1e-3), np.array(ctx.color)[None, None, :])
        return Tex(np.clip(albedo, 0, 1), alpha, alpha, ones(ctx, 0.3), normal_strength=1.0)
    if bid == "fallen_leaves":
        t = leaves(ctx)
        t.alpha = (t.alpha > 0.5).astype(float)
        return t
    # Мох и лишайник — пушистый слой с проплешинами.
    s = ctx.size
    rng = ctx.rng
    n = fbm(s, 6, rng, 4)
    fine = value_noise(s, 96, rng)
    alpha = (n + 0.2 * fine > 0.42).astype(float)
    albedo = colorize(ctx.color, 0.75 + 0.35 * fine + 0.2 * n)
    return Tex(np.clip(albedo, 0, 1), alpha, normalize(n + fine * 0.5), 0.95 * ones(ctx), normal_strength=2.5)
