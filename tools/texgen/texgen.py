#!/usr/bin/env python3
"""texgen — процедурные PBR-текстуры блоков «Кубача» (раздел 16 ТЗ, правило 4).

Читает data/blocks.json и data/blocks/*.json, для каждого текстурного набора (поле textures
блока) рисует 2–4 бесшовных варианта и упаковывает их в три атласа-массива:

  blocks_albedo.webp  RGB — цвет (sRGB), A — покрытие (cutout) или маска тонирования биомом
  blocks_normal.webp  RGB — нормаль (OpenGL, Y вверх), A — metallic
  blocks_orm.webp     R — AO, G — roughness, B — height (для parallax), A — свечение

Слои идут сеткой COLUMNS × rows по SIZE пикселей; Godot импортирует их как Texture2DArray
(файлы .import пишутся здесь же). blocks_manifest.json связывает имя набора с первым слоем
и числом вариантов.

Запуск:  python3 tools/texgen/texgen.py [--size 128] [--only granite,turf_top] [--preview docs/textures_preview.png]
Детерминирован: одинаковые данные → одинаковые картинки.
"""
import argparse
import glob
import hashlib
import json
import math
import os
import re
import sys
import time

import numpy as np
from PIL import Image, ImageDraw

sys.path.insert(0, os.path.dirname(__file__))
import recipes as R  # noqa: E402
import furniture as F  # noqa: E402
import crafting_tex as CT  # noqa: E402
from noise import blur  # noqa: E402

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
OUT_DIR = os.path.join(ROOT, "assets", "textures", "generated")
COLUMNS = 32
FORMAT = 1


def load_blocks():
    files = [os.path.join(ROOT, "data", "blocks.json")] + sorted(glob.glob(os.path.join(ROOT, "data", "blocks", "*.json")))
    sets = {}
    for f in files:
        for e in json.load(open(f, encoding="utf-8"))["entries"]:
            t = e["textures"]
            for role in ("all", "top", "bottom", "side"):
                if role in t:
                    sets.setdefault(t[role], []).append((e, role))
    return sets


def classify(name, uses):
    """Рецепт, число вариантов и разрешён ли поворот для набора."""
    e, role = uses[0]
    bid = e["id"]
    mat = e["material"]
    tags = e.get("tags", [])
    shape = e.get("shape", "cube")
    furn = {
        "chest_wood_side": lambda c: F.chest(c, True, "wood"), "chest_wood_top": lambda c: F.chest(c, False, "wood"),
        "chest_reinforced_side": lambda c: F.chest(c, True, "reinforced"),
        "chest_reinforced_top": lambda c: F.chest(c, False, "reinforced"),
        "chest_iron_side": lambda c: F.chest(c, True, "iron"), "chest_iron_top": lambda c: F.chest(c, False, "iron"),
        "dresser_side": lambda c: F.dresser(c, True), "dresser_top": lambda c: F.dresser(c, False),
        "barrel_side": lambda c: F.barrel(c, True), "barrel_top": lambda c: F.barrel(c, False),
        "crate": F.crate, "torch": F.torch, "campfire": F.campfire,
        "sleeping_bag_top": lambda c: F.bed(c, False, "sleeping_bag"), "sleeping_bag_side": lambda c: F.bed(c, True, "sleeping_bag"),
        "bed_top": lambda c: F.bed(c, False, "bed"), "bed_side": lambda c: F.bed(c, True, "bed"),
        "double_bed_top": lambda c: F.bed(c, False, "double_bed"), "double_bed_side": lambda c: F.bed(c, True, "double_bed"),
    }
    if name in furn:
        return furn[name], 1, False
    ct = CT.classify(name, e)
    if ct is not None:
        return ct
    if name in ("turf_top", "mycelium_top"):
        return R.turf_top, 3, True
    if name in ("turf_side", "mycelium_side"):
        if name == "mycelium_side":
            return (lambda c: R.turf_side(c, grass_color=c.color, dirt_color=R.hex_rgb("#7a5a3c"))), 2, False
        return R.turf_side, 3, False
    if name == "loam":
        return (lambda c: R.soil(c, base=R.hex_rgb("#7a5a3c"))), 3, True
    if bid == "lava":
        return R.lava, 2, True
    if mat == "liquid":
        return R.water, 1, True
    if shape == "layer":
        return R.layer_top, 2, bid != "water_lily"
    if shape == "cross":
        return R.plant, 2, False
    if bid == "cactus":
        return R.cactus, 2, False
    if mat == "stone":
        if "coral" in tags:
            return R.coral, 2, True
        if bid == "geyser_vent":
            return geyser, 1, False
        if bid in R.STONE_STYLE or bid == "bauxite":
            return R.stone, 4, True
        if "ore" in tags or "gem" in tags:
            return R.ore, 3, True
        return R.stone, 4, True
    if mat == "soil":
        if bid in ("red_sand", "silica_sand"):
            return R.sand, 3, True
        if bid == "bog_iron_ore":
            return (lambda c: R.soil(c, pebbles=0.35, base=R.hex_rgb("#5d4a35"))), 3, True
        style = {
            "chernozem": dict(pebbles=0.02, crumbs=1.0),
            "clay": dict(pebbles=0.0, cracks=True, crumbs=0.2),
            "red_clay": dict(pebbles=0.0, cracks=True, crumbs=0.2),
            "ochre_clay": dict(pebbles=0.0, cracks=True, crumbs=0.2),
            "peat": dict(pebbles=0.0, roots=True, crumbs=0.8),
            "silt": dict(pebbles=0.0, cracks=True, crumbs=0.3),
            "permafrost": dict(pebbles=0.12, crumbs=0.5),
            "podzol": dict(pebbles=0.05, roots=True, crumbs=0.6),
        }.get(bid, {})
        return (lambda c, st=style: R.soil(c, **st)), 3, True
    if mat == "sand":
        return R.sand, 3, True
    if mat == "gravel":
        if bid == "gold_gravel":
            return gold_gravel, 3, True
        return R.gravel, 3, True
    if mat == "snow":
        return R.snow, 2, True
    if mat == "ice":
        return (lambda c: R.ice(c, packed=bid == "packed_ice")), 2, True
    if mat == "wood":
        if "mushroom" in tags:
            return (R.fibrous if bid == "mushroom_stem" else R.mushroom_cap), 2, bid != "mushroom_stem"
        if role == "side" or name.endswith("_bark"):
            return R.bark, 2, False
        return R.log_end, 2, True
    if mat == "leaves":
        needles = any(k in bid for k in ("needles", "fir", "pine", "cedar", "larch"))
        fronds = any(k in bid for k in ("palm", "bamboo"))
        return (lambda c: R.leaves(c, needles=needles, fronds=fronds)), 2, True
    if mat == "plant":
        return R.plant, 2, False
    return R.stone, 2, True


def geyser(ctx):
    t = R.stone(ctx, style="layers", minerals=[("#f0e8d0", 0.2)], cracks=0.2, rough=0.8, base=R.hex_rgb("#d9cfb6"))
    s = ctx.size
    ys, xs = np.mgrid[0:s, 0:s]
    r = np.sqrt((ys - s / 2) ** 2 + (xs - s / 2) ** 2) / s
    hole = r < 0.18
    t.albedo = np.where(hole[..., None], np.array((0.12, 0.1, 0.09)), t.albedo)
    rim = (r >= 0.18) & (r < 0.26)
    t.albedo = np.where(rim[..., None], t.albedo * np.array((1.05, 0.95, 0.75)), t.albedo)
    t.height = np.where(hole, 0.0, t.height + rim * 0.3)
    return t


def gold_gravel(ctx):
    t = R.gravel(ctx, base=R.hex_rgb("#80786f"))
    flecks = R.value_noise(ctx.size, 96, ctx.rng) > 0.9
    t.albedo = np.where(flecks[..., None], np.array((0.95, 0.78, 0.25)), t.albedo)
    t.metal = np.where(flecks, 1.0, 0.0)
    t.rough = np.where(flecks, 0.25, t.rough)
    return t


def seed_of(name, variant):
    return int.from_bytes(hashlib.sha256(f"{name}:{variant}".encode()).digest()[:8], "little")


def finish(tex, size):
    """Нормаль, AO и упаковка в RGBA8 три карты."""
    h = np.clip(tex.height, 0, 1)
    k = tex.normal_strength
    dx = (np.roll(h, -1, 1) - np.roll(h, 1, 1)) * 0.5
    dy = (np.roll(h, -1, 0) - np.roll(h, 1, 0)) * 0.5
    nx = -dx * k * size / 32
    ny = dy * k * size / 32
    nz = np.ones_like(h)
    ln = np.sqrt(nx * nx + ny * ny + nz * nz)
    normal = np.stack([nx / ln, ny / ln, nz / ln], -1) * 0.5 + 0.5
    cavity = blur(h, max(1, size // 32)) - h
    ao = np.clip(1.0 - cavity * 3.0, 0.35, 1.0)
    metal = tex.metal if tex.metal is not None else np.zeros_like(h)
    rough = np.clip(np.broadcast_to(tex.rough, h.shape), 0.04, 1.0)
    emit = np.ones_like(h) if tex.emissive else np.zeros_like(h)
    if getattr(tex, "emission", None) is not None:
        emit = np.clip(tex.emission, 0, 1)
    albedo = np.concatenate([np.clip(tex.albedo, 0, 1), np.clip(tex.alpha, 0, 1)[..., None]], -1)
    normal_m = np.concatenate([normal, metal[..., None]], -1)
    orm = np.stack([ao, rough, h, emit], -1)
    to8 = lambda a: (np.clip(a, 0, 1) * 255 + 0.5).astype(np.uint8)
    return to8(albedo), to8(normal_m), to8(orm)


def write_import(path, rows):
    """Godot: импортировать атлас как Texture2DArray с COLUMNS × rows слоёв.

    Если .import уже есть (Godot дописал в него uid и пути), меняем только число строк сетки.
    """
    rel = "res://" + os.path.relpath(path, ROOT).replace(os.sep, "/")
    imp = path + ".import"
    if os.path.exists(imp):
        text = open(imp, encoding="utf-8").read()
        text = re.sub(r"slices/horizontal=\d+", f"slices/horizontal={COLUMNS}", text)
        text = re.sub(r"slices/vertical=\d+", f"slices/vertical={rows}", text)
        with open(imp, "w", encoding="utf-8") as f:
            f.write(text)
        return
    with open(imp, "w", encoding="utf-8") as f:
        f.write(f"""[remap]

importer="2d_array_texture"
type="CompressedTexture2DArray"

[deps]

source_file="{rel}"

[params]

compress/mode=2
compress/high_quality=true
compress/lossy_quality=0.7
compress/hdr_compression=1
compress/channel_pack=0
mipmaps/generate=true
mipmaps/limit=-1
slices/horizontal={COLUMNS}
slices/vertical={rows}
""")


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--size", type=int, default=128)
    ap.add_argument("--only", default="")
    ap.add_argument("--preview", default=os.path.join(ROOT, "docs", "textures_preview.png"))
    ap.add_argument("--out", default=OUT_DIR)
    args = ap.parse_args()
    size = args.size
    sets = load_blocks()
    names = sorted(sets)
    if args.only:
        names = [n for n in names if n in args.only.split(",")]
    t0 = time.time()
    layers_albedo, layers_normal, layers_orm = [], [], []
    manifest = {"format": FORMAT, "size": size, "columns": COLUMNS, "sets": {}}
    for name in names:
        uses = sets[name]
        recipe, variants, rotate = classify(name, uses)
        e, role = uses[0]
        color = R.hex_rgb(e["map_color"])
        manifest["sets"][name] = {"first": len(layers_albedo), "count": variants, "rotate": rotate}
        for v in range(variants):
            ctx = R.Ctx(size, np.random.default_rng(seed_of(name, v)), color, e, role, v, name)
            tex = recipe(ctx)
            if e.get("render") == "cutout" and float(np.max(tex.alpha)) == 0.0:
                # В cutout-шейдере альфа — покрытие: сплошной слой (снег) не должен пропасть.
                tex.alpha = np.ones_like(tex.alpha)
            a, n, o = finish(tex, size)
            layers_albedo.append(a)
            layers_normal.append(n)
            layers_orm.append(o)
    count = len(layers_albedo)
    rows = math.ceil(count / COLUMNS)
    manifest["rows"] = rows
    manifest["layers"] = count
    os.makedirs(args.out, exist_ok=True)
    for label, layers in (("albedo", layers_albedo), ("normal", layers_normal), ("orm", layers_orm)):
        atlas = np.zeros((rows * size, COLUMNS * size, 4), dtype=np.uint8)
        for i, layer in enumerate(layers):
            r, c = divmod(i, COLUMNS)
            atlas[r * size:(r + 1) * size, c * size:(c + 1) * size] = layer
        path = os.path.join(args.out, f"blocks_{label}.webp")
        Image.fromarray(atlas, "RGBA").save(path, "WEBP", quality=96 if label != "albedo" else 94, method=6, exact=True)
        write_import(path, rows)
        print(f"{label}: {path} {os.path.getsize(path) / 1e6:.1f} МБ")
    with open(os.path.join(args.out, "blocks_manifest.json"), "w", encoding="utf-8") as f:
        json.dump(manifest, f, ensure_ascii=False, indent=1)
    print(f"наборов {len(names)}, слоёв {count}, сетка {COLUMNS}×{rows}, {time.time() - t0:.1f} с")
    if args.preview:
        preview(names, manifest, layers_albedo, layers_normal, size, args.preview)
    if not args.only and args.out == OUT_DIR:
        import icons
        icons.build(args.out)
        CT.particles(os.path.join(args.out, "particles"))
        import sky_tex
        sky_tex.build(args.out)


def preview(names, manifest, albedo, normal, size, path):
    """Лист-превью: albedo варианта 0 на шахматке, рядом нормаль; подпись — имя набора."""
    cell = 132
    cols = 12
    rows = math.ceil(len(names) / cols)
    sheet = Image.new("RGB", (cols * cell * 2, rows * (cell + 14)), (24, 26, 25))
    d = ImageDraw.Draw(sheet)
    checker = np.indices((size, size)).sum(0) // 8 % 2 * 40 + 70
    for i, name in enumerate(names):
        idx = manifest["sets"][name]["first"]
        a = albedo[idx].astype(float) / 255
        bg = np.repeat(checker[..., None], 3, -1) / 255
        cutout = a[..., 3].min() < 1.0 and a[..., 3].max() > 0.0 and not name.startswith(("turf", "mycelium"))
        rgb = a[..., :3] * a[..., 3:4] + bg * (1 - a[..., 3:4]) if cutout else a[..., :3]
        img = Image.fromarray((rgb * 255).astype(np.uint8)).resize((cell - 4, cell - 4), Image.NEAREST)
        nimg = Image.fromarray(normal[idx][..., :3]).resize((cell - 4, cell - 4), Image.NEAREST)
        r, c = divmod(i, cols)
        x = c * cell * 2
        y = r * (cell + 14)
        sheet.paste(img, (x + 2, y + 2))
        sheet.paste(nimg, (x + cell + 2, y + 2))
        d.text((x + 4, y + cell), name[:30], fill=(200, 210, 200))
    os.makedirs(os.path.dirname(path), exist_ok=True)
    sheet.save(path)
    print("превью:", path)


if __name__ == "__main__":
    main()
