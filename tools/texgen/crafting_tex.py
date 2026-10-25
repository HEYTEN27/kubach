"""Рецепты текстур этапа 6 (ремесло): доски пород дерева, металлические блоки, кирпичная
кладка и текстуры моделей станций — шкура на раме, холст, угли, копоть, кожа мехов."""
import math

import numpy as np

from noise import fbm, value_noise, worley, blur, normalize
from recipes import Tex, colorize, hex_rgb, lerp_img, ones, solid
from furniture import planks as _planks, _metal


def planks_block(ctx):
    """Доски: 4 доски вдоль, у каждой свой тон и волокна, сучки, щели, гвозди; цвет — порода."""
    alb, h, rough = _planks(ctx, boards=4, horizontal=True, base=ctx.color, gap=1.6)
    s = ctx.size
    # Лёгкий износ: светлее по центру досок, затёртые края.
    wear = fbm(s, 5, ctx.rng, 3)
    alb = alb * (0.94 + 0.12 * wear)[..., None]
    return Tex(np.clip(alb, 0, 1), ones(ctx, 0.0), normalize(h), np.clip(rough, 0.05, 1), ones(ctx, 0.0),
               normal_strength=2.2)


PATINA = {
    "copper": ("#3f9a7a", 0.35), "bronze": ("#4f8a68", 0.22), "iron": ("#7a4226", 0.3),
    "steel": ("#6a5a50", 0.06), "gold": ("#b08a30", 0.05), "silver": ("#4a4a50", 0.25),
}


def metal_block(ctx):
    """Блок металла: 4 кованые плиты со скосом, заклёпки по углам, царапины, патина/ржавчина."""
    s = ctx.size
    rng = ctx.rng
    metal_id = next((t for t in ctx.tags if t in PATINA), "iron")
    base = np.array(ctx.color)
    ys, xs = np.mgrid[0:s, 0:s]
    half = s // 2
    lx = xs % half
    ly = ys % half
    edge = np.minimum(np.minimum(lx, half - 1 - lx), np.minimum(ly, half - 1 - ly)).astype(float)
    bevel = np.clip(edge / 3.0, 0, 1)
    plate = (xs // half) + 2 * (ys // half)
    tone = 0.9 + 0.12 * rng.random(4)
    hammer = np.clip(worley(s, 14, rng)[0], 0, 1)
    n = fbm(s, 16, rng, 3)
    mod = tone[plate] * (0.85 + 0.15 * n) * (0.9 + 0.1 * hammer)
    alb = colorize(base, mod)
    # Царапины — короткие светлые штрихи.
    scratch = np.zeros((s, s))
    for _ in range(14):
        x0, y0 = rng.random() * s, rng.random() * s
        a = rng.random() * math.pi
        L = s * (0.05 + 0.15 * rng.random())
        for t in np.linspace(0, 1, int(L) + 1):
            x = int(x0 + math.cos(a) * L * t) % s
            y = int(y0 + math.sin(a) * L * t) % s
            scratch[y, x] = 1.0
    alb = lerp_img(alb, colorize(base, 1.2 * ones(ctx)), scratch * 0.3)
    # Шов между плитами и скос.
    alb *= (0.55 + 0.45 * bevel)[..., None]
    h = 0.55 * bevel + 0.15 * hammer + 0.1 * n - 0.2 * scratch
    # Заклёпки в углах плит.
    for cx in (half * 0.18, half * 0.82):
        for cy in (half * 0.18, half * 0.82):
            r = np.sqrt((lx - cx) ** 2 + (ly - cy) ** 2)
            riv = np.clip(2.6 - r, 0, 1)
            alb = lerp_img(alb, colorize(base, 1.25 * ones(ctx)), riv)
            h += riv * 0.45
    col, amount = PATINA[metal_id]
    pat = np.clip((fbm(s, 6, rng, 4) - (1.0 - amount)) * 4, 0, 1) * (1.0 - 0.6 * bevel + 0.3)
    pat = np.clip(pat, 0, 1)
    alb = lerp_img(alb, colorize(hex_rgb(col), 0.8 + 0.3 * n), pat * 0.8)
    rough = 0.28 + 0.25 * pat + 0.1 * n
    metal = np.clip(0.95 - pat * 0.8, 0, 1)
    return Tex(np.clip(alb, 0, 1), ones(ctx, 0.0), normalize(h), np.clip(rough, 0.05, 1), metal, normal_strength=2.6)


def bricks(ctx):
    """Кирпичная кладка со смещёнными рядами: тон каждого кирпича, сколы, раствор, копоть."""
    s = ctx.size
    rng = ctx.rng
    rows = 4
    rh = s / rows
    bw = s / 2
    ys, xs = np.mgrid[0:s, 0:s]
    row = np.floor(ys / rh).astype(int)
    off = (row % 2) * bw / 2
    col = np.floor(((xs + off) % s) / bw).astype(int)
    idx = row * 3 + col
    tone = 0.78 + 0.32 * rng.random(rows * 3 + 3)
    ly = ys - row * rh
    lx = (xs + off) % bw
    mortar_w = max(1.5, s / 48)
    edge = np.minimum(np.minimum(ly, rh - ly), np.minimum(lx, bw - lx))
    mortar = np.clip(1 - (edge - mortar_w * 0.5) / mortar_w, 0, 1)
    n = fbm(s, 12, rng, 4)
    pores = (value_noise(s, 48, rng) > 0.85).astype(float)
    brick = colorize(ctx.color, tone[idx] * (0.85 + 0.25 * n) * (1 - 0.15 * pores))
    # Сколы по краям кирпичей.
    chips = np.clip((fbm(s, 20, rng, 2) - 0.66) * 6, 0, 1) * np.clip(1 - edge / (mortar_w * 3), 0, 1)
    mort = colorize(hex_rgb("#b8ad98"), 0.85 + 0.2 * fbm(s, 24, rng, 2))
    alb = lerp_img(brick, mort, np.maximum(mortar, chips * 0.8))
    soot = np.clip((fbm(s, 4, rng, 3) - 0.6) * 3, 0, 1)
    alb *= (1 - 0.35 * soot)[..., None]
    h = (1 - mortar) * (0.6 + 0.2 * n) - chips * 0.4 - pores * 0.1
    rough = 0.85 + 0.1 * mortar
    return Tex(np.clip(alb, 0, 1), ones(ctx, 0.0), normalize(h), rough, ones(ctx, 0.0), normal_strength=2.8)


def hide(ctx):
    """Шкура, натянутая на раму: поры и прожилки, тёмная кромка, дырки шнуровки."""
    s = ctx.size
    rng = ctx.rng
    ys, xs = np.mgrid[0:s, 0:s]
    n = fbm(s, 6, rng, 4)
    veins = np.abs(fbm(s, 4, rng, 3) - 0.5) < 0.03
    pores = (value_noise(s, 64, rng) > 0.8).astype(float)
    cx, cy = (xs - s / 2) / (s / 2), (ys - s / 2) / (s / 2)
    rim = np.clip((np.maximum(np.abs(cx), np.abs(cy)) - 0.75) * 4, 0, 1)
    alb = colorize(ctx.color, (0.8 + 0.3 * n) * (1 - 0.1 * pores))
    alb = lerp_img(alb, alb * 0.75, veins.astype(float) * 0.6)
    alb *= (1 - 0.45 * rim)[..., None]
    h = 0.6 * n - 0.15 * pores - 0.2 * veins
    for i in range(6):
        p = (i + 0.5) / 6 * s
        for hx, hy in ((p, s * 0.05), (p, s * 0.95), (s * 0.05, p), (s * 0.95, p)):
            r = np.sqrt((xs - hx) ** 2 + (ys - hy) ** 2)
            hole = np.clip(2.2 - r, 0, 1)
            alb *= (1 - 0.8 * hole)[..., None]
            h -= hole * 0.5
    return Tex(np.clip(alb, 0, 1), ones(ctx, 0.0), normalize(h), 0.75 + 0.1 * n, ones(ctx, 0.0), normal_strength=1.8)


def cloth(ctx):
    """Холст: полотняное переплетение, узелки нити, складки, лёгкие пятна."""
    s = ctx.size
    rng = ctx.rng
    ys, xs = np.mgrid[0:s, 0:s]
    warp_ = np.sin(xs * math.pi / 2) * 0.5 + 0.5
    weft = np.sin(ys * math.pi / 2) * 0.5 + 0.5
    over = ((xs // 2 + ys // 2) % 2).astype(float)
    weave = over * warp_ + (1 - over) * weft
    slub = np.clip((fbm(s, 32, rng, 2) - 0.7) * 5, 0, 1)
    folds = fbm(s, 3, rng, 3)
    stains = np.clip((fbm(s, 5, rng, 3) - 0.7) * 3, 0, 1)
    alb = colorize(ctx.color, (0.82 + 0.14 * weave + 0.12 * slub) * (0.9 + 0.2 * folds) * (1 - 0.15 * stains))
    h = 0.4 * weave + 0.5 * folds + 0.2 * slub
    return Tex(np.clip(alb, 0, 1), ones(ctx, 0.0), normalize(h), 0.95 * ones(ctx), ones(ctx, 0.0), normal_strength=1.4)


def embers(ctx):
    """Угли: чёрные растрескавшиеся куски, в трещинах тлеет оранжевый жар (светится)."""
    s = ctx.size
    rng = ctx.rng
    f1, f2, _ = worley(s, 9, rng)
    cells = f2 - f1
    crack = np.clip(1 - cells / 0.12, 0, 1)
    n = fbm(s, 10, rng, 3)
    ash = np.clip((fbm(s, 7, rng, 3) - 0.6) * 3, 0, 1)
    coal = colorize(hex_rgb("#1c1816"), 0.7 + 0.5 * n)
    glow = np.array((1.0, 0.42, 0.08)) * (0.6 + 0.6 * n)[..., None]
    alb = lerp_img(coal, glow, crack)
    alb = lerp_img(alb, colorize(hex_rgb("#a8a29a"), 0.9 + 0.1 * n), ash * 0.7)
    h = 0.7 * (1 - crack) + 0.2 * n
    t = Tex(np.clip(alb, 0, 1), ones(ctx, 0.0), normalize(h), 0.9 * ones(ctx), ones(ctx, 0.0), normal_strength=2.2)
    t.emission = np.clip(crack * (0.6 + 0.4 * n), 0, 1)
    return t


def soot(ctx):
    """Копоть внутри топки: чёрный нагар с потёками и прожжёнными пятнами."""
    s = ctx.size
    rng = ctx.rng
    n = fbm(s, 8, rng, 4)
    drips = fbm(s, 6, rng, 3, aniso=(3.0, 0.3))
    burnt = np.clip((fbm(s, 5, rng, 3) - 0.65) * 3, 0, 1)
    alb = colorize(ctx.color, 0.7 + 0.4 * n + 0.2 * drips)
    alb = lerp_img(alb, colorize(hex_rgb("#5a2a1a"), 0.8 + 0.3 * n), burnt * 0.5)
    h = 0.5 * n + 0.3 * drips
    return Tex(np.clip(alb, 0, 1), ones(ctx, 0.0), normalize(h), 0.95 * ones(ctx), ones(ctx, 0.0), normal_strength=1.6)


def bellows(ctx):
    """Кожа мехов: гармошка складок поперёк, швы, потёртости на рёбрах."""
    s = ctx.size
    rng = ctx.rng
    ys = np.mgrid[0:s, 0:s][0]
    folds = 0.5 + 0.5 * np.cos(ys / s * math.pi * 10)
    n = fbm(s, 8, rng, 3)
    worn = np.clip(folds - 0.75, 0, 1) * 3 * n
    alb = colorize(ctx.color, (0.7 + 0.35 * folds) * (0.85 + 0.25 * n))
    alb = lerp_img(alb, colorize(hex_rgb("#8a6040"), 0.9 * ones(ctx)), np.clip(worn, 0, 1) * 0.6)
    h = 0.75 * folds + 0.15 * n
    return Tex(np.clip(alb, 0, 1), ones(ctx, 0.0), normalize(h), 0.7 + 0.1 * n, ones(ctx, 0.0), normal_strength=2.4)


def fire(ctx):
    """Блок огня (крест): несколько языков пламени от углей у земли, горячее ядро, искры;
    альфа — покрытие, ORM.A — свечение."""
    from PIL import Image, ImageDraw
    s = ctx.size
    rng = ctx.rng
    k = 4
    big = s * k
    img = Image.new("RGBA", (big, big), (0, 0, 0, 0))
    glow = Image.new("L", (big, big), 0)
    d = ImageDraw.Draw(img)
    dg = ImageDraw.Draw(glow)
    for layer, (col, scale) in enumerate([((0.85, 0.22, 0.04), 1.0), ((1.0, 0.5, 0.1), 0.75), ((1.0, 0.85, 0.45), 0.45)]):
        for t in range(4):
            cx = big * (0.2 + 0.2 * t) + rng.normal() * k * 3
            w = big * 0.13 * scale
            top = big * (0.05 + 0.18 * layer + 0.12 * rng.random())
            pts = [(cx - w, big * 0.98), (cx + w, big * 0.98), (cx + w * 0.5, top + big * 0.3),
                   (cx + rng.normal() * k * 4, top), (cx - w * 0.6, top + big * 0.35)]
            fill = tuple(int(255 * c) for c in col) + (235,)
            d.polygon(pts, fill=fill)
            dg.polygon(pts, fill=int(140 + 110 * layer / 2))
    for _ in range(10):
        x, y = rng.random() * big, rng.random() * big * 0.6
        r = k * (1 + rng.random())
        d.ellipse([x - r, y - r, x + r, y + r], fill=(255, 200, 90, 255))
        dg.ellipse([x - r, y - r, x + r, y + r], fill=255)
    img = img.resize((s, s), Image.LANCZOS)
    glow = np.array(glow.resize((s, s), Image.LANCZOS)) / 255.0
    a = np.array(img).astype(float) / 255.0
    t = Tex(np.clip(a[..., :3], 0, 1), a[..., 3], normalize(glow), 0.9 * ones(ctx), ones(ctx, 0.0), normal_strength=0.5)
    t.emission = glow
    return t


RECIPES = {"fire": fire, "hide": hide, "cloth": cloth, "embers": embers, "soot": soot, "bellows": bellows, "bricks": bricks}


def classify(name, block):
    """Рецепт для набора этапа 6 или None: (функция, вариантов, поворот)."""
    tags = block.get("tags", [])
    if name.endswith("_planks"):
        return planks_block, 2, False
    if "metal_block" in tags:
        return metal_block, 1, False
    if name in RECIPES:
        return RECIPES[name], (2 if name in ("bricks", "embers", "fire") else 1), name in ("embers", "soot", "cloth")
    return None


def particles(out_dir, size=64):
    """Текстуры частиц станций: язык пламени, клуб дыма, искра (RGBA PNG)."""
    import os
    from PIL import Image
    rng = np.random.default_rng(1234)
    ys, xs = np.mgrid[0:size, 0:size]
    cx = (xs - size / 2) / (size / 2)
    cy = (ys - size / 2) / (size / 2)
    r = np.sqrt(cx ** 2 + cy ** 2)
    n = fbm(size, 6, rng, 4)
    # Пламя: капля, сужающаяся кверху, горячее ядро, рваный край по шуму.
    shape = np.sqrt(cx ** 2 / np.clip(0.35 + 0.45 * (cy + 1) / 2, 0.05, 1) ** 2 + ((cy - 0.15) / 0.85) ** 2)
    edge = np.clip(1.0 - shape + 0.25 * (n - 0.5), 0, 1)
    core = np.clip(1.4 - shape * 1.6, 0, 1)
    flame = np.zeros((size, size, 4))
    flame[..., 0] = 1.0
    flame[..., 1] = np.clip(0.35 + 0.65 * core, 0, 1)
    flame[..., 2] = np.clip(0.05 + 0.6 * core ** 2, 0, 1)
    flame[..., 3] = np.clip(edge * 1.6, 0, 1)
    # Дым: клуб из нескольких шаров с мягким краем и внутренней неоднородностью.
    puff = np.zeros((size, size))
    for _ in range(5):
        ox, oy = rng.normal(0, 0.25, 2)
        rr = 0.35 + 0.2 * rng.random()
        puff = np.maximum(puff, np.clip(1 - np.sqrt((cx - ox) ** 2 + (cy - oy) ** 2) / rr, 0, 1))
    smoke = np.zeros((size, size, 4))
    smoke[..., :3] = (0.55 + 0.25 * n)[..., None]
    smoke[..., 3] = np.clip(puff * (0.6 + 0.5 * n), 0, 1) * 0.85
    # Искра: яркая точка с лучами.
    rays = np.clip(1 - np.minimum(np.abs(cx), np.abs(cy)) * 8, 0, 1) * np.clip(1 - r, 0, 1)
    spark = np.zeros((size, size, 4))
    spark[..., 0] = 1.0
    spark[..., 1] = np.clip(0.75 + 0.25 * np.clip(1 - r * 3, 0, 1), 0, 1)
    spark[..., 2] = np.clip(0.4 * np.clip(1 - r * 4, 0, 1), 0, 1)
    spark[..., 3] = np.clip(np.clip(1 - r * 2.2, 0, 1) ** 2 + rays * 0.8, 0, 1)
    os.makedirs(out_dir, exist_ok=True)
    for name, img in (("flame", flame), ("smoke", smoke), ("spark", spark)):
        Image.fromarray((np.clip(img, 0, 1) * 255).astype(np.uint8), "RGBA").save(os.path.join(out_dir, name + ".png"))
