#!/usr/bin/env python3
"""Иконки предметов (этап 4): изометрические кубики блоков из атласа текстур и нарисованные
иконки остальных предметов (инструменты, одежда, еда…) по полю icon в data/items.json.

Выход: assets/textures/generated/items_icons.png (сетка 16 × N по 64 px) и items_icons.json
{ "size": 64, "columns": 16, "icons": { id: индекс } }.
Запуск: python3 tools/texgen/icons.py (texgen.py вызывает его сам после атласов).
"""
import glob
import json
import math
import os
import sys

import numpy as np
from PIL import Image, ImageDraw, ImageFilter

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
GEN = os.path.join(ROOT, "assets", "textures", "generated")
ICON = 64
CANVAS = 256
COLUMNS = 16


def hex_rgb(h):
    h = h.lstrip("#")
    return tuple(int(h[i:i + 2], 16) for i in (0, 2, 4))


def load_entries(pattern_files):
    out = []
    for f in pattern_files:
        if os.path.exists(f):
            out += json.load(open(f, encoding="utf-8"))["entries"]
    return out


def block_items():
    files = [os.path.join(ROOT, "data", "blocks.json")] + sorted(glob.glob(os.path.join(ROOT, "data", "blocks", "*.json")))
    out = []
    for e in load_entries(files):
        if e.get("item", True) is False or e.get("material") == "liquid" or float(e.get("hardness", 1.0)) < 0:
            continue
        out.append(e)
    return out


class Atlas:
    def __init__(self):
        self.m = json.load(open(os.path.join(GEN, "blocks_manifest.json"), encoding="utf-8"))
        self.img = Image.open(os.path.join(GEN, "blocks_albedo.webp")).convert("RGBA")
        self.size = self.m["size"]

    def layer(self, name):
        s = self.m["sets"].get(name)
        if s is None:
            return None
        r, c = divmod(s["first"], self.m["columns"])
        return self.img.crop((c * self.size, r * self.size, (c + 1) * self.size, (r + 1) * self.size))


def face(canvas, tex, origin, a, b, shade, opaque=True):
    """Наложить квадратную текстуру на параллелограмм origin + u·a + v·b."""
    t = np.asarray(tex).astype(np.float32)
    n = t.shape[0]
    h, w = canvas.shape[:2]
    ys, xs = np.mgrid[0:h, 0:w] + 0.5
    m = np.array([[a[0], b[0]], [a[1], b[1]]], dtype=np.float64)
    inv = np.linalg.inv(m)
    px = xs - origin[0]
    py = ys - origin[1]
    u = inv[0, 0] * px + inv[0, 1] * py
    v = inv[1, 0] * px + inv[1, 1] * py
    inside = (u >= 0) & (u < 1) & (v >= 0) & (v < 1)
    ui = np.clip((u * n).astype(int), 0, n - 1)
    vi = np.clip((v * n).astype(int), 0, n - 1)
    src = t[vi, ui]
    alpha = src[..., 3] / 255.0 if not opaque else np.ones(src.shape[:2])
    alpha = alpha * inside
    rgb = src[..., :3] * shade
    canvas[..., :3] = canvas[..., :3] * (1 - alpha[..., None]) + rgb * alpha[..., None]
    canvas[..., 3] = np.maximum(canvas[..., 3], alpha * 255)


def iso_cube(top, side, opaque=True, height=1.0, alpha_scale=1.0):
    c = np.zeros((CANVAS, CANVAS, 4), dtype=np.float32)
    L = 100.0
    a = (L * math.cos(math.pi / 6), L * 0.5)
    b = (-L * math.cos(math.pi / 6), L * 0.5)
    hgt = L * height
    o = (CANVAS / 2, (CANVAS - (L + hgt)) / 2)
    d = (0.0, hgt)
    side_img = side
    if height < 1.0:
        n = side.size[1]
        side_img = side.crop((0, 0, side.size[0], max(1, int(n * height)))).resize(side.size, Image.NEAREST)
    face(c, side_img, (o[0] + b[0], o[1] + b[1]), a, d, 0.8, opaque)
    f = (o[0] + a[0] + b[0], o[1] + a[1] + b[1])
    face(c, side_img, f, (-b[0], -b[1]), d, 0.62, opaque)
    face(c, top, o, a, b, 1.0, opaque)
    c[..., 3] *= alpha_scale
    return Image.fromarray(np.clip(c, 0, 255).astype(np.uint8), "RGBA")


def sprite(tex):
    c = Image.new("RGBA", (CANVAS, CANVAS), (0, 0, 0, 0))
    t = tex.resize((int(CANVAS * 0.86), int(CANVAS * 0.86)), Image.NEAREST)
    c.alpha_composite(t, ((CANVAS - t.size[0]) // 2, (CANVAS - t.size[1]) // 2))
    return c


def block_icon(e, atlas):
    tex = e["textures"]
    top = atlas.layer(tex.get("top", tex.get("all")))
    side = atlas.layer(tex.get("side", tex.get("all")))
    if top is None or side is None:
        img = Image.new("RGBA", (CANVAS, CANVAS), hex_rgb(e["map_color"]) + (255,))
        return img
    # Тонирование: текстуры нарисованы цветом блока, а дёрн и листва в игре красятся биомом —
    # для иконки берём цвет блока (как в texgen).
    shape = e.get("shape", "cube")
    render = e.get("render", "opaque")
    if shape == "cross":
        return sprite(top)
    if shape == "layer":
        solid_layer = render != "cutout"
        if solid_layer:
            top = top.copy()
            top.putalpha(255)
            side = side.copy()
            side.putalpha(255)
        return iso_cube(top, side, solid_layer, height=max(0.12, float(e.get("layer_height", 0.125))))
    if render == "translucent":
        return iso_cube(top, side, True, alpha_scale=0.85)
    if render == "cutout":
        return iso_cube(top, side, False)
    if top.getchannel("A").getextrema()[1] > 0 and e.get("tint", "none") == "none":
        top = top.copy()
        top.putalpha(255)
    side = side.copy()
    side.putalpha(255)
    top = top.copy()
    top.putalpha(255)
    return iso_cube(top, side, True)


# ---------------------------------------------------------------------------------------------
# Нарисованные иконки предметов

def _c(rgb, k=1.0, a=255):
    return tuple(int(max(0, min(255, v * k))) for v in rgb) + (a,)


def draw_item(e):
    ic = e.get("icon", {})
    shape = ic.get("shape", "") or "misc"
    col = hex_rgb(ic.get("color", "#808080"))
    col2 = hex_rgb(ic.get("color2", "#5a4030"))
    wood = hex_rgb("#7a5a36")
    img = Image.new("RGBA", (CANVAS, CANVAS), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)

    def handle(x0, y0, x1, y1, w=14, c=wood):
        d.line([(x0, y0), (x1, y1)], fill=_c(c, 0.7), width=w + 6)
        d.line([(x0, y0), (x1, y1)], fill=_c(c), width=w)
        d.line([(x0 - 3, y0 - 3), (x1 - 3, y1 - 3)], fill=_c(c, 1.25), width=max(2, w // 4))

    if shape in ("pickaxe", "axe", "shovel", "hoe", "knife", "shears"):
        if shape == "shears":
            for sgn in (-1, 1):
                d.polygon([(128, 128), (128 + sgn * 70, 30), (128 + sgn * 50, 26)], fill=_c(col))
                d.ellipse([128 - sgn * 50 - 26, 160, 128 - sgn * 50 + 26, 212], outline=_c(col2), width=10)
                d.line([(128, 128), (128 - sgn * 50, 170)], fill=_c(col2), width=12)
        else:
            handle(60, 220, 190, 70 if shape != "knife" else 120)
            if shape == "pickaxe":
                d.polygon([(70, 70), (130, 40), (200, 60), (230, 110), (200, 90), (140, 70), (100, 90)], fill=_c(col))
                d.line([(80, 72), (130, 48), (195, 66)], fill=_c(col, 1.35), width=5)
            elif shape == "axe":
                d.polygon([(150, 40), (215, 30), (232, 100), (190, 110), (165, 85)], fill=_c(col))
                d.line([(215, 34), (230, 98)], fill=_c(col, 1.4), width=6)
            elif shape == "shovel":
                d.ellipse([160, 20, 236, 104], fill=_c(col))
                d.ellipse([170, 30, 210, 70], fill=_c(col, 1.25))
            elif shape == "hoe":
                d.polygon([(175, 50), (235, 55), (235, 80), (180, 75)], fill=_c(col))
            elif shape == "knife":
                d.polygon([(150, 125), (235, 40), (240, 52), (175, 135)], fill=_c(col))
                d.line([(158, 122), (232, 46)], fill=_c(col, 1.4), width=4)
    elif shape == "sword":
        d.polygon([(70, 186), (210, 46), (226, 30), (222, 62), (88, 196)], fill=_c(col))
        d.line([(80, 186), (214, 52)], fill=_c(col, 1.35), width=6)
        d.line([(50, 170), (106, 226)], fill=_c(col2, 1.3), width=16)
        handle(36, 240, 72, 204, 16, col2)
    elif shape == "spear":
        handle(30, 236, 190, 76, 12)
        d.polygon([(180, 86), (235, 21), (200, 96)], fill=_c(col))
        d.polygon([(180, 86), (235, 21), (170, 70)], fill=_c(col, 1.3))
    elif shape == "club":
        handle(50, 230, 150, 110, 16)
        d.ellipse([120, 40, 220, 140], fill=_c(col))
        d.ellipse([135, 52, 175, 92], fill=_c(col, 1.2))
    elif shape == "stick":
        handle(50, 220, 210, 40, 16, col)
        d.line([(130, 130), (170, 140)], fill=_c(col), width=8)
    elif shape == "fiber":
        for i in range(9):
            x = 70 + i * 13
            d.arc([x - 60, 40, x + 60, 260], 200, 300, fill=_c(col, 0.8 + 0.05 * i), width=7)
    elif shape == "shard":
        d.polygon([(80, 70), (170, 40), (210, 120), (150, 210), (70, 160)], fill=_c(col))
        d.polygon([(80, 70), (170, 40), (140, 110)], fill=_c(col, 1.4))
    elif shape == "hide":
        d.polygon([(60, 70), (110, 40), (150, 60), (200, 40), (220, 110), (200, 200), (140, 220), (70, 200), (40, 130)], fill=_c(col))
        d.polygon([(90, 90), (150, 80), (180, 150), (100, 170)], fill=_c(col, 1.15))
    elif shape == "cloth":
        d.rectangle([50, 70, 206, 200], fill=_c(col))
        for y in range(80, 200, 12):
            d.line([(50, y), (206, y)], fill=_c(col, 0.85), width=3)
        d.polygon([(50, 70), (206, 70), (190, 50), (66, 50)], fill=_c(col, 1.1))
    elif shape == "ball":
        d.ellipse([50, 60, 206, 216], fill=_c(col))
        for i in range(6):
            d.arc([50 + i * 8, 60 + i * 8, 206 - i * 8, 216 - i * 8], 20 * i, 20 * i + 200, fill=_c(col, 0.82), width=5)
    elif shape == "coil":
        for i in range(5):
            d.ellipse([50 + i * 10, 60 + i * 8, 206 - i * 10, 200 - i * 8], outline=_c(col, 0.9 + 0.05 * i), width=12)
    elif shape in ("cap", "helmet"):
        d.chord([50, 50, 206, 210], 180, 360, fill=_c(col))
        d.rectangle([44, 128, 212, 150], fill=_c(col2 if shape == "cap" else col, 0.85))
        if shape == "helmet":
            d.rectangle([118, 70, 138, 180], fill=_c(col, 1.3))
        else:
            d.rectangle([40, 140, 70, 200], fill=_c(col2, 0.9))
            d.rectangle([186, 140, 216, 200], fill=_c(col2, 0.9))
    elif shape in ("shirt", "coat", "plate"):
        body = [(60, 60), (100, 44), (156, 44), (196, 60), (236, 120), (206, 140), (190, 120), (190, 226 if shape == "coat" else 210),
                (66, 226 if shape == "coat" else 210), (66, 120), (50, 140), (20, 120)]
        d.polygon(body, fill=_c(col))
        d.polygon([(100, 44), (128, 80), (156, 44)], fill=_c(col, 0.7))
        if shape == "coat":
            d.rectangle([66, 200, 190, 226], fill=_c(col2))
            d.line([(128, 80), (128, 226)], fill=_c(col, 0.75), width=5)
        if shape == "plate":
            d.line([(128, 80), (128, 210)], fill=_c(col, 1.3), width=8)
    elif shape == "pants":
        d.polygon([(70, 40), (186, 40), (200, 230), (140, 230), (128, 110), (116, 230), (56, 230)], fill=_c(col))
        d.rectangle([70, 40, 186, 60], fill=_c(col, 0.75))
    elif shape == "boots":
        for x in (40, 140):
            d.polygon([(x, 60), (x + 50, 60), (x + 50, 170), (x + 80, 190), (x + 80, 220), (x, 220)], fill=_c(col))
            d.rectangle([x, 206, x + 80, 222], fill=_c(col, 0.6))
    elif shape == "gloves":
        for x, f in ((30, 1), (140, -1)):
            d.rounded_rectangle([x, 90, x + 86, 210], 20, fill=_c(col))
            d.rounded_rectangle([x + (60 if f > 0 else -10), 70, x + (96 if f > 0 else 26), 140], 14, fill=_c(col, 0.92))
            d.rectangle([x, 190, x + 86, 220], fill=_c(col, 0.75))
    elif shape in ("backpack", "quiver"):
        if shape == "quiver":
            d.rounded_rectangle([90, 60, 166, 230], 18, fill=_c(col))
            for i in range(4):
                d.line([(100 + i * 18, 60), (96 + i * 22, 20)], fill=_c(hex_rgb("#d8c090")), width=6)
        else:
            d.rounded_rectangle([50, 50, 206, 226], 34, fill=_c(col))
            d.rounded_rectangle([70, 120, 186, 200], 16, fill=_c(col, 0.85))
            d.rectangle([84, 40, 172, 70], fill=_c(col, 0.7))
            d.line([(128, 120), (128, 150)], fill=_c(col2 if col2 != col else col, 0.5), width=8)
    elif shape == "ring":
        d.ellipse([60, 80, 196, 216], outline=_c(col), width=22)
        d.ellipse([110, 46, 146, 82], fill=_c(hex_rgb("#6ab0d8")))
    elif shape == "amulet":
        d.arc([60, 20, 196, 170], 0, 180, fill=_c(col2), width=6)
        d.polygon([(128, 120), (170, 170), (128, 230), (86, 170)], fill=_c(col))
        d.polygon([(128, 130), (150, 168), (128, 196)], fill=_c(col, 1.3))
    elif shape == "shield":
        d.polygon([(48, 40), (208, 40), (208, 140), (128, 236), (48, 140)], fill=_c(col))
        d.rectangle([48, 40, 208, 56], fill=_c(col2))
        d.line([(128, 40), (128, 230)], fill=_c(col, 0.7), width=6)
        d.ellipse([108, 100, 148, 140], fill=_c(col2, 1.2))
    elif shape == "berries":
        rng = np.random.default_rng(sum(map(ord, e["id"])))
        d.polygon([(110, 40), (150, 60), (128, 90)], fill=_c(hex_rgb("#3f6a35")))
        for _ in range(9):
            x, y = 70 + rng.random() * 110, 80 + rng.random() * 110
            r = 22 + rng.random() * 8
            d.ellipse([x - r, y - r, x + r, y + r], fill=_c(col, 0.85 + 0.3 * rng.random()))
            d.ellipse([x - r * 0.5, y - r * 0.6, x - r * 0.1, y - r * 0.2], fill=_c(col, 1.6))
    elif shape == "bread":
        d.ellipse([30, 80, 226, 210], fill=_c(col))
        d.ellipse([46, 84, 210, 170], fill=_c(col, 1.25))
        for x in (80, 120, 160):
            d.line([(x, 100), (x + 24, 150)], fill=_c(col, 0.75), width=7)
    elif shape == "fish":
        d.ellipse([40, 90, 190, 170], fill=_c(col))
        d.polygon([(180, 130), (236, 90), (236, 170)], fill=_c(col, 0.85))
        d.ellipse([62, 112, 76, 126], fill=(30, 30, 30, 255))
    elif shape == "meat":
        d.ellipse([40, 70, 200, 200], fill=_c(col))
        d.ellipse([60, 86, 150, 150], fill=_c(col, 1.2))
        d.line([(180, 170), (230, 220)], fill=_c(hex_rgb("#ece6da")), width=18)
        d.ellipse([214, 204, 244, 234], fill=_c(hex_rgb("#ece6da")))
    elif shape in ("bowl", "cup"):
        if shape == "bowl":
            d.chord([40, 70, 216, 220], 0, 180, fill=_c(col2))
            d.ellipse([40, 100, 216, 150], fill=_c(col))
        else:
            d.rounded_rectangle([70, 80, 180, 220], 14, fill=_c(col2))
            d.ellipse([70, 70, 180, 104], fill=_c(col))
            d.arc([160, 110, 220, 180], 270, 90, fill=_c(col2), width=12)
            for x in (100, 125, 150):
                d.arc([x - 10, 20, x + 10, 70], 90, 270, fill=(220, 220, 220, 160), width=5)
    elif shape == "powder":
        d.polygon([(40, 210), (216, 210), (170, 120), (90, 120)], fill=_c(col))
        d.polygon([(90, 120), (170, 120), (150, 90), (110, 90)], fill=_c(col, 1.3))
    elif shape == "roll":
        d.ellipse([40, 90, 140, 200], fill=_c(col, 0.9))
        d.rectangle([90, 90, 200, 200], fill=_c(col))
        d.ellipse([150, 90, 250, 200], fill=_c(col, 1.05))
        d.ellipse([180, 125, 220, 165], fill=_c(col, 0.75))
    elif shape == "splint":
        for x in (80, 160):
            d.rectangle([x, 30, x + 26, 226], fill=_c(col))
        for y in (70, 128, 186):
            d.rectangle([66, y, 200, y + 18], fill=_c(col2))
    elif shape == "jar":
        d.rounded_rectangle([60, 90, 196, 220], 26, fill=_c(col))
        d.rectangle([70, 60, 186, 96], fill=_c(col2))
        d.ellipse([80, 110, 120, 150], fill=_c(col, 1.3))
    elif shape == "pills":
        d.rounded_rectangle([60, 40, 196, 220], 22, fill=_c(col))
        d.rectangle([60, 40, 196, 90], fill=_c(col2))
        for i in range(3):
            d.ellipse([86 + i * 30, 140, 112 + i * 30, 166], fill=_c(col2, 1.1))
    else:
        d.rounded_rectangle([60, 60, 196, 196], 24, fill=_c(col))
    # Обводка и мягкая тень сверху-слева → объём.
    alpha = img.getchannel("A")
    outline = alpha.filter(ImageFilter.MaxFilter(9))
    base = Image.new("RGBA", img.size, (24, 20, 18, 0))
    base.putalpha(outline)
    base.alpha_composite(img)
    return base


def build(out_dir=GEN):
    atlas = Atlas()
    icons = []
    ids = []
    for e in block_items():
        icons.append(block_icon(e, atlas))
        ids.append(e["id"])
    for e in load_entries([os.path.join(ROOT, "data", "items.json")] + sorted(glob.glob(os.path.join(ROOT, "data", "items", "*.json")))):
        icons.append(draw_item(e))
        ids.append(e["id"])
    rows = math.ceil(len(icons) / COLUMNS)
    sheet = Image.new("RGBA", (COLUMNS * ICON, rows * ICON), (0, 0, 0, 0))
    for i, img in enumerate(icons):
        r, c = divmod(i, COLUMNS)
        sheet.alpha_composite(img.resize((ICON, ICON), Image.LANCZOS), (c * ICON, r * ICON))
    path = os.path.join(out_dir, "items_icons.png")
    sheet.save(path, optimize=True)
    with open(os.path.join(out_dir, "items_icons.json"), "w", encoding="utf-8") as f:
        json.dump({"format": 1, "size": ICON, "columns": COLUMNS, "icons": {k: i for i, k in enumerate(ids)}}, f, ensure_ascii=False, indent=1)
    print(f"иконки: {len(icons)} → {path}")
    return path


if __name__ == "__main__":
    build(sys.argv[1] if len(sys.argv) > 1 else GEN)
