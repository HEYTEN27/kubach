"""Текстуры фермы (этап 9): стадии роста культур (crop_<id>_<k>) по облику культуры из
data/crops.json — злаки с колосом, корнеплоды с ботвой и выглядывающим корнем, кочаны, лозы с
опорой и плодами, тыквенные с плетями, высокие (кукуруза, подсолнечник), кусты с ягодами, травы;
грядка сухая и политая (борозды, комья), сорняк, увядшее растение, стекло с бликами и рамкой,
компост. Каждая стадия — своя картинка: всходы → молодое → рост → цветение/завязь → спелое."""
import json
import math
import os

import numpy as np
from PIL import Image, ImageDraw

from noise import blur, fbm, value_noise
from recipes import Tex, hex_rgb, shade, _rgba
import recipes as R

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))


def load_crops():
    path = os.path.join(ROOT, "data", "crops.json")
    if not os.path.exists(path):
        return []
    return json.load(open(path, encoding="utf-8"))["entries"]


def derived_blocks():
    """Блоки стадий, которые Registry выводит из data/crops.json (то же имя, текстура, цвет)."""
    out = []
    for c in load_crops():
        n = int(c.get("stages", 5))
        for k in range(n):
            col = c.get("fruit_color", "#d8b860") if k == n - 1 else c.get("leaf_color", "#4f8a36")
            out.append({"id": f"crop_{c['id']}_{k}", "material": "plant", "render": "cutout", "shape": "cross",
                        "map_color": col, "textures": {"all": f"crop_{c['id']}_{k}"}, "tags": ["crop", "plant"],
                        "_crop": c, "_stage": k, "_stages": n})
    return out


def classify(name, e):
    if name.startswith("crop_") and "_crop" in e:
        return (lambda ctx, c=e["_crop"], k=e["_stage"], n=e["_stages"]: crop(ctx, c, k, n)), 1, False
    table = {
        "farmland_top": (lambda c: farmland(c, False), 3, True),
        "farmland_wet_top": (lambda c: farmland(c, True), 3, True),
        "weed": (weed, 2, False),
        "withered_crop": (withered, 2, False),
        "glass": (glass, 1, False),
        "tex_compost": (compost, 2, True),
    }
    return table.get(name)


def _sprite(img, s, col, rough=0.75):
    img = img.resize((s, s), Image.LANCZOS)
    a = np.asarray(img).astype(float) / 255
    alpha = (a[..., 3] > 0.4).astype(float)
    albedo = np.where(alpha[..., None] > 0, a[..., :3] / np.maximum(a[..., 3:4], 1e-3), np.array(col)[None, None, :])
    height = blur(alpha, 2)
    return Tex(np.clip(albedo, 0, 1), alpha, height, rough + 0.0 * height, normal_strength=1.0)


def crop(ctx, c, k, n):
    s = ctx.size
    rng = ctx.rng
    q = 4
    big = s * q
    img = Image.new("RGBA", (big, big), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    leaf = hex_rgb(c.get("leaf_color", "#4f8a36"))
    fruit = hex_rgb(c.get("fruit_color", "#d8b860"))
    fl = c.get("flower_color", "")
    flower = hex_rgb(fl) if fl and len(fl.lstrip("#")) == 6 else None
    form = c.get("form", "grain")
    g = (k + 1) / n                 # доля роста 0.2 … 1
    ripe = k == n - 1
    blooming = k == n - 2
    # Спелые злаки желтеют.
    def green(v=1.0):
        base = leaf
        if form == "grain" and ripe:
            base = tuple(0.55 * np.array(leaf) + 0.45 * np.array(fruit))
        return shade(base, v * (0.8 + 0.4 * rng.random()))

    def blade(x0, h, lean, w, col):
        d.polygon([(x0 - w, big), (x0 + w, big), (x0 + lean, big - h)], fill=_rgba(col))

    def leaf_at(x, y, ang, L, W, col):
        pts = []
        for t in np.linspace(0, 1, 9):
            r = W * math.sin(math.pi * t)
            pts.append((x + math.cos(ang) * L * t - math.sin(ang) * r, y + math.sin(ang) * L * t + math.cos(ang) * r))
        for t in np.linspace(1, 0, 9):
            r = -W * math.sin(math.pi * t)
            pts.append((x + math.cos(ang) * L * t - math.sin(ang) * r, y + math.sin(ang) * L * t + math.cos(ang) * r))
        d.polygon(pts, fill=_rgba(col))
        d.line([(x, y), (x + math.cos(ang) * L * 0.9, y + math.sin(ang) * L * 0.9)], fill=_rgba(shade(col, 0.75)), width=q)

    if form == "grain":
        count = int(6 + 14 * g)
        hmax = big * (0.25 + 0.7 * g)
        for _ in range(count):
            x = big * (0.12 + 0.76 * rng.random())
            h = hmax * (0.75 + 0.25 * rng.random())
            lean = (rng.random() - 0.5) * big * 0.12
            blade(x, h, lean, q * 1.6, green())
            if k >= n - 2:
                hx, hy = x + lean, big - h
                col = fruit if ripe else shade(leaf, 1.15)
                if c["id"] in ("buckwheat",):
                    col = flower if (flower and not ripe) else fruit
                    for j in range(5):
                        d.ellipse([hx - q * 4 + rng.normal() * q * 3, hy + j * q * 3, hx + q * 4, hy + j * q * 3 + q * 4], fill=_rgba(col))
                elif c["id"] in ("flax",) and not ripe and flower:
                    d.ellipse([hx - q * 5, hy - q * 5, hx + q * 5, hy + q * 5], fill=_rgba(flower))
                elif c["id"] in ("oats", "millet", "rice"):
                    for j in range(6):
                        a = math.pi / 2 + (j - 2.5) * 0.35
                        px, py = hx + math.cos(a) * q * 10, hy + j * q * 4
                        d.ellipse([px - q * 2.5, py - q * 3.5, px + q * 2.5, py + q * 3.5], fill=_rgba(shade(col, 0.9 + 0.1 * j / 6)))
                else:
                    ln = q * (14 if ripe else 10)
                    d.rounded_rectangle([hx - q * 2.6, hy - ln * 0.2, hx + q * 2.6, hy + ln], radius=q * 2, fill=_rgba(col))
                    for j in range(5):
                        yy = hy + j * ln / 5
                        d.line([(hx - q * 2.5, yy), (hx + q * 2.5, yy + q * 1.5)], fill=_rgba(shade(col, 0.7)), width=q)
                    if c["id"] in ("barley", "wheat", "rye", "triticale"):
                        for j in range(4):
                            d.line([(hx, hy + j * q * 3), (hx + (j % 2 * 2 - 1) * q * 4, hy - q * 8)], fill=_rgba(shade(col, 0.85)), width=max(1, q // 2))
    elif form in ("root", "herb"):
        count = int(4 + 8 * g)
        for i in range(count):
            x = big * (0.5 + (rng.random() - 0.5) * 0.5)
            ang = -math.pi / 2 + (rng.random() - 0.5) * 1.6
            L = big * (0.2 + 0.5 * g) * (0.7 + 0.3 * rng.random())
            if c["id"] in ("carrot", "dill", "parsley"):
                # Перистые листья.
                x2, y2 = x + math.cos(ang) * L, big + math.sin(ang) * L
                d.line([(x, big), (x2, y2)], fill=_rgba(green(0.9)), width=q)
                for t in range(8):
                    px = x + (x2 - x) * t / 8
                    py = big + (y2 - big) * t / 8
                    for sgn in (-1, 1):
                        d.line([(px, py), (px + sgn * q * 6, py - q * 4)], fill=_rgba(green()), width=q)
                if c["id"] == "dill" and k >= n - 2:
                    d.ellipse([x2 - q * 8, y2 - q * 4, x2 + q * 8, y2 + q * 4], fill=_rgba(fruit))
            elif c["id"] in ("onion", "garlic"):
                d.line([(x, big), (x + math.cos(ang) * L * 0.5, big + math.sin(ang) * L)], fill=_rgba(green()), width=q * 3)
            else:
                leaf_at(x, big - q * 4, ang, L, q * (6 + 6 * g), green())
        if k >= n - 2:
            # Корень выглядывает из земли.
            x = big * 0.5
            r = big * (0.06 + 0.06 * g)
            if c["id"] in ("carrot", "radish", "beet", "turnip", "potato", "onion", "garlic"):
                d.ellipse([x - r, big - r * 1.1, x + r, big + r * 0.9], fill=_rgba(fruit))
                d.ellipse([x - r * 0.5, big - r, x - r * 0.1, big - r * 0.6], fill=_rgba(shade(fruit, 1.25)))
        if flower and blooming and c["id"] == "potato":
            for _ in range(4):
                px, py = big * (0.3 + 0.4 * rng.random()), big * (0.3 + 0.2 * rng.random())
                d.ellipse([px - q * 4, py - q * 4, px + q * 4, py + q * 4], fill=_rgba(flower))
                d.ellipse([px - q, py - q, px + q, py + q], fill=_rgba((0.95, 0.85, 0.2)))
    elif form == "leafy":
        cx, cy = big * 0.5, big * (1 - 0.18 * g)
        for i in range(int(6 + 8 * g)):
            ang = -math.pi / 2 + (i / (6 + 8 * g) - 0.5) * 2.6
            leaf_at(cx, big - q * 2, ang, big * (0.2 + 0.32 * g), q * (8 + 6 * g), green())
        if c["id"] == "cabbage" and k >= 2:
            r = big * (0.1 + 0.16 * g)
            d.ellipse([cx - r, cy - r, cx + r, cy + r], fill=_rgba(fruit))
            for j in range(3):
                d.arc([cx - r * (0.9 - j * 0.25), cy - r * (0.9 - j * 0.25), cx + r * (0.9 - j * 0.25), cy + r * 0.5],
                      200, 340, fill=_rgba(shade(fruit, 0.8)), width=q * 2)
    elif form in ("vine", "tall"):
        tall = form == "tall"
        if not tall and k >= 1:
            # Опора-колышек.
            d.rectangle([big * 0.48, big * (1 - 0.95 * g), big * 0.52, big], fill=_rgba(hex_rgb("#8a6a44")))
        stems = 1 if tall else 2
        for si in range(stems):
            x0 = big * (0.5 + (si - 0.5) * 0.2)
            top = big * (1 - (0.35 + 0.6 * g) * (1.0 if tall else 0.95))
            pts = [(x0 + math.sin(t * 6 + si) * q * 6 * (not tall), big - (big - top) * t) for t in np.linspace(0, 1, 12)]
            d.line(pts, fill=_rgba(green(0.85)), width=q * (5 if tall else 2))
            for j, (px, py) in enumerate(pts[2::2]):
                side = 1 if j % 2 else -1
                leaf_at(px, py, -math.pi / 2 + side * (0.9 if tall else 1.2), big * (0.16 if tall else 0.11) * (0.6 + 0.4 * g),
                        q * (5 if tall else 6), green())
            if tall and c["id"] == "sunflower" and k >= n - 2:
                hx, hy = pts[-1]
                r = big * (0.12 + 0.06 * g)
                for p in range(16):
                    a = p / 16 * 2 * math.pi
                    d.ellipse([hx + math.cos(a) * r - q * 5, hy + math.sin(a) * r - q * 3, hx + math.cos(a) * r + q * 5,
                               hy + math.sin(a) * r + q * 3], fill=_rgba(flower or (0.95, 0.8, 0.1)))
                d.ellipse([hx - r * 0.75, hy - r * 0.75, hx + r * 0.75, hy + r * 0.75], fill=_rgba(fruit))
            elif tall and c["id"] == "corn" and k >= n - 2:
                px, py = pts[6]
                d.ellipse([px - q * 5, py - q * 12, px + q * 7, py + q * 14], fill=_rgba(fruit if ripe else shade(leaf, 1.2)))
                d.line([(px, py - q * 12), (px + q * 4, py - q * 22)], fill=_rgba((0.7, 0.5, 0.3)), width=q)
            elif not tall and k >= n - 2:
                for j, (px, py) in enumerate(pts[3::2]):
                    if ripe or rng.random() < 0.5:
                        col = fruit if ripe else (flower or shade(fruit, 0.7))
                        if c["id"] in ("grape",):
                            for b in range(7):
                                bx = px + (b % 3 - 1) * q * 3.2
                                by = py + (b // 3) * q * 3.5
                                d.ellipse([bx - q * 2, by - q * 2, bx + q * 2, by + q * 2], fill=_rgba(col))
                        elif c["id"] in ("peas", "beans") and ripe:
                            d.rounded_rectangle([px, py, px + q * 4, py + q * 14], radius=q * 2, fill=_rgba(shade(leaf, 1.2) if c["id"] == "peas" else col))
                        elif c["id"] == "hops":
                            d.ellipse([px - q * 3, py - q * 4, px + q * 3, py + q * 4], fill=_rgba(col))
                        else:
                            w = q * (3 if not ripe else (4 if c["id"] != "cucumber" else 3))
                            hgt = q * (4 if c["id"] in ("tomato",) else 9)
                            d.ellipse([px - w, py - hgt * 0.4, px + w, py + hgt], fill=_rgba(col))
    elif form == "gourd":
        for i in range(int(3 + 5 * g)):
            ang = -math.pi + rng.random() * math.pi
            x0 = big * 0.5
            L = big * (0.2 + 0.3 * g)
            pts = [(x0 + math.cos(ang) * L * t, big * 0.92 + math.sin(ang) * L * t * 0.35) for t in np.linspace(0, 1, 6)]
            d.line(pts, fill=_rgba(green(0.8)), width=q * 2)
            for px, py in pts[1::2]:
                leaf_at(px, py, -math.pi / 2 + (rng.random() - 0.5), big * 0.12 * (0.6 + 0.6 * g), q * 9, green())
        if blooming and flower:
            d.ellipse([big * 0.45, big * 0.7, big * 0.55, big * 0.8], fill=_rgba(flower))
        if ripe:
            r = big * (0.18 if c["id"] in ("pumpkin", "watermelon", "melon") else 0.1)
            cx, cy = big * 0.5, big - r
            if c["id"] == "zucchini":
                d.rounded_rectangle([cx - r * 2, cy - r * 0.6, cx + r * 2, cy + r], radius=r * 0.6, fill=_rgba(fruit))
            else:
                d.ellipse([cx - r * 1.15, cy - r, cx + r * 1.15, cy + r], fill=_rgba(fruit))
                for j in range(5 if c["id"] == "pumpkin" else 4):
                    xx = cx - r + j * r * 2 / (4 if c["id"] == "pumpkin" else 3)
                    d.arc([xx - r * 0.3, cy - r, xx + r * 0.3, cy + r], 270, 90, fill=_rgba(shade(fruit, 0.75)), width=q * 2)
                if c["id"] == "watermelon":
                    for j in range(6):
                        xx = cx - r + j * r * 0.4
                        d.line([(xx, cy - r * 0.9), (xx + r * 0.1, cy + r * 0.9)], fill=_rgba(shade(fruit, 0.6)), width=q * 2)
    else:  # bush
        h = big * (0.3 + 0.6 * g)
        for _ in range(int(30 + 70 * g)):
            x = big * (0.5 + (rng.random() - 0.5) * (0.4 + 0.5 * g))
            y = big - h * rng.random() ** 0.7
            d.ellipse([x - q * 5, y - q * 4, x + q * 5, y + q * 4], fill=_rgba(green()))
        for _ in range(3):
            x = big * (0.4 + 0.2 * rng.random())
            d.line([(x, big), (x + rng.normal() * q * 6, big - h * 0.8)], fill=_rgba(hex_rgb("#5a4030")), width=q * 2)
        if blooming and flower:
            for _ in range(10):
                x = big * (0.5 + (rng.random() - 0.5) * 0.8)
                y = big - h * rng.random()
                d.ellipse([x - q * 3, y - q * 3, x + q * 3, y + q * 3], fill=_rgba(flower))
        if ripe:
            nb = 18 if c["id"] != "cotton" else 8
            for _ in range(nb):
                x = big * (0.5 + (rng.random() - 0.5) * 0.8)
                y = big - h * (0.1 + 0.85 * rng.random())
                r = q * (3.5 if c["id"] not in ("strawberry", "cotton") else 5)
                if c["id"] == "tea":
                    continue
                d.ellipse([x - r, y - r, x + r, y + r], fill=_rgba(fruit))
                d.ellipse([x - r * 0.4, y - r * 0.6, x, y - r * 0.2], fill=_rgba(shade(fruit, 1.35)))
    return _sprite(img, s, leaf)


def farmland(ctx, wet):
    s = ctx.size
    rng = ctx.rng
    base = hex_rgb("#4a3222") if wet else hex_rgb("#7a5638")
    n = fbm(s, 8, rng, 4)
    clods = value_noise(s, 24, rng)
    ys = np.arange(s)[:, None] * np.ones((1, s))
    furrow = 0.5 + 0.5 * np.cos(ys / s * 2 * math.pi * 4)
    height = 0.55 * furrow + 0.3 * clods + 0.15 * n
    shade_k = 0.72 + 0.4 * height
    albedo = np.array(base)[None, None, :] * shade_k[..., None]
    # Комья и мелкие камешки на гребнях.
    stones = (value_noise(s, 48, rng) > 0.86) & (furrow > 0.6)
    albedo[stones] = np.array(hex_rgb("#9a8a78"))
    if wet:
        albedo *= 0.9
        rough = 0.45 + 0.25 * (1 - furrow)
    else:
        rough = 0.9 - 0.05 * furrow
    return Tex(np.clip(albedo, 0, 1), np.ones((s, s)), height, rough)


def weed(ctx):
    s = ctx.size
    rng = ctx.rng
    q = 4
    big = s * q
    img = Image.new("RGBA", (big, big), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    col = hex_rgb("#5a7a34")
    for i in range(7):
        x = big * (0.2 + 0.6 * rng.random())
        ang = -math.pi / 2 + (rng.random() - 0.5) * 1.8
        L = big * (0.3 + 0.35 * rng.random())
        for t in range(10):
            px = x + math.cos(ang) * L * t / 10
            py = big + math.sin(ang) * L * t / 10
            w = (1 - t / 10) * q * 7 * (1 + 0.5 * math.sin(t * 1.7))
            d.ellipse([px - w, py - q * 3, px + w, py + q * 3], fill=_rgba(shade(col, 0.75 + 0.4 * rng.random())))
    for _ in range(3):
        x, y = big * (0.3 + 0.4 * rng.random()), big * (0.3 + 0.3 * rng.random())
        d.ellipse([x - q * 3, y - q * 3, x + q * 3, y + q * 3], fill=_rgba((0.95, 0.85, 0.2)))
    return _sprite(img, s, col)


def withered(ctx):
    s = ctx.size
    rng = ctx.rng
    q = 4
    big = s * q
    img = Image.new("RGBA", (big, big), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    col = hex_rgb("#8a7a4a")
    for _ in range(9):
        x = big * (0.2 + 0.6 * rng.random())
        top = big * (0.35 + 0.4 * rng.random())
        mid = (x + (rng.random() - 0.5) * big * 0.2, (big + top) / 2)
        end = (mid[0] + (rng.random() - 0.5) * big * 0.35, top + big * 0.1 * rng.random())
        c = shade(col, 0.7 + 0.4 * rng.random())
        d.line([(x, big), mid, end], fill=_rgba(c), width=q * 2)
        d.ellipse([end[0] - q * 4, end[1] - q * 2, end[0] + q * 4, end[1] + q * 2], fill=_rgba(shade(c, 0.85)))
    return _sprite(img, s, col, rough=0.9)


def glass(ctx):
    s = ctx.size
    rng = ctx.rng
    ys, xs = np.mgrid[0:s, 0:s] / s
    alpha = np.full((s, s), 0.18)
    albedo = np.ones((s, s, 3)) * np.array(hex_rgb("#d8e8f0"))
    # Рамка и пузырьки; диагональные блики.
    frame = (xs < 0.05) | (xs > 0.95) | (ys < 0.05) | (ys > 0.95)
    alpha[frame] = 0.85
    albedo[frame] = np.array(hex_rgb("#8a9aa4"))
    streak = np.abs(((xs + ys) % 0.5) - 0.12) < 0.025
    alpha[streak & ~frame] = 0.45
    albedo[streak & ~frame] = 1.0
    bubbles = value_noise(s, 40, rng) > 0.93
    alpha[bubbles & ~frame] = 0.3
    height = np.where(frame, 1.0, 0.5) + 0.02 * fbm(s, 6, rng, 3)
    return Tex(np.clip(albedo, 0, 1), alpha, height, np.where(frame, 0.5, 0.05), normal_strength=0.6)


def compost(ctx):
    s = ctx.size
    rng = ctx.rng
    n = fbm(s, 10, rng, 5)
    chips = value_noise(s, 30, rng)
    base = np.array(hex_rgb("#3e2a1a"))
    albedo = base[None, None, :] * (0.7 + 0.6 * n[..., None])
    straw = chips > 0.8
    albedo[straw] = np.array(hex_rgb("#a08a4a")) * (0.8 + 0.3 * n[straw][..., None])
    green = (chips < 0.08)
    albedo[green] = np.array(hex_rgb("#4a6a2a"))
    return Tex(np.clip(albedo, 0, 1), np.ones((s, s)), 0.6 * n + 0.4 * chips, 0.95 + 0.0 * n)
