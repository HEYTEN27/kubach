"""Рецепты мебели и хранилищ (этап 4): доски с волокнами и щелями, металлические полосы с
заклёпками, замки, ящики комода, клёпки бочки с обручами, ящик с раскосом; спрайт факела."""
import math

import numpy as np
from PIL import Image, ImageDraw

from noise import fbm, value_noise, blur, normalize
from recipes import Tex, colorize, hex_rgb, lerp_img, ones, solid, shade, _rgba


def _grain(s, rng, horizontal=True):
    """Волокна древесины вдоль доски."""
    aniso = (0.12, 1.6) if horizontal else (1.6, 0.12)
    g = fbm(s, 10, rng, 4, aniso=aniso)
    knots = fbm(s, 3, rng, 2)
    return g, knots


def planks(ctx, boards=4, horizontal=True, base=None, gap=2):
    """Доски: у каждой свой тон, волокна, тёмные щели между досками и шляпки гвоздей."""
    s = ctx.size
    rng = ctx.rng
    base = np.array(base if base is not None else ctx.color)
    g, knots = _grain(s, rng, horizontal)
    coord = np.mgrid[0:s, 0:s][0 if horizontal else 1]
    across = np.mgrid[0:s, 0:s][1 if horizontal else 0]
    bw = s / boards
    idx = np.floor(coord / bw).astype(int)
    tone = 0.82 + 0.3 * rng.random(boards + 1)
    shift = rng.random(boards + 1) * s
    mod = tone[idx] * (0.78 + 0.32 * g + 0.08 * (knots - 0.5))
    albedo = colorize(base, mod)
    # Сучки — тёмные овалы.
    for _ in range(2):
        b = int(rng.integers(0, boards))
        cy = (b + 0.5) * bw
        cx = rng.random() * s
        yy, xx = (coord - cy), ((across - cx + s / 2) % s - s / 2)
        k = np.exp(-(yy ** 2) / (bw * 0.08) ** 2 - (xx ** 2) / (bw * 0.22) ** 2)
        albedo *= (1 - 0.45 * k)[..., None]
    local = coord - idx * bw
    edge = np.minimum(local, bw - local)
    groove = np.clip(1 - edge / gap, 0, 1)
    albedo *= (1 - 0.55 * groove)[..., None]
    height = 0.6 * g - 0.5 * groove
    # Гвозди у концов досок.
    for b in range(boards):
        for end in (0.08, 0.92):
            cy = (b + 0.5) * bw
            cx = (end * s + shift[b] * 0) % s
            d = np.sqrt((coord - cy) ** 2 + (across - cx) ** 2) if horizontal else np.sqrt((coord - cy) ** 2 + (across - cx) ** 2)
            nail = np.clip(1.6 - d, 0, 1)
            albedo = lerp_img(albedo, solid(ctx, (0.25, 0.24, 0.24)), nail)
            height += nail * 0.3
    return albedo, normalize(height), 0.8 + 0.1 * g


def _band(s, pos, width, horizontal=True):
    c = np.mgrid[0:s, 0:s][0 if horizontal else 1]
    return (np.abs(c - pos) < width / 2).astype(float)


def _metal(ctx, mask, color, rivets=True, spacing=None):
    """Металлическая полоса: блик по краю, пятна ржавчины, заклёпки."""
    s = ctx.size
    rng = ctx.rng
    n = fbm(s, 12, rng, 3)
    rust = np.clip((fbm(s, 6, rng, 3) - 0.62) * 4, 0, 1)
    col = colorize(color, 0.75 + 0.4 * n)
    col = lerp_img(col, colorize(hex_rgb("#7a4a2a"), 0.8 + 0.3 * n), rust * 0.6)
    edge = mask - blur(mask, 1)
    col *= (1 + 0.5 * np.clip(edge, 0, 1))[..., None]
    height = mask * 0.7
    if rivets:
        sp = spacing or s // 4
        ys, xs = np.mgrid[0:s, 0:s]
        cy = np.round(ys / sp) * sp
        cx = np.round(xs / sp) * sp
        r = np.sqrt((ys - cy - sp / 2) ** 2 + (xs - cx - sp / 2) ** 2)
        riv = np.clip(2.2 - r, 0, 1) * (mask > 0.5)
        col = lerp_img(col, colorize(color, 1.3 * ones(ctx)), riv)
        height += riv * 0.4
    return col, height, 0.35 + 0.3 * rust


def _apply(alb, h, rough, mask, malb, mh, mrough, metal):
    alb = lerp_img(alb, malb, mask)
    h = np.where(mask > 0.5, 0.5 + mh * 0.5, h * 0.6)
    rough = np.where(mask > 0.5, mrough, rough)
    metal = np.maximum(metal, (mask > 0.5) * 0.85)
    return alb, h, rough, metal


def chest(ctx, side=True, kind="wood"):
    s = ctx.size
    if kind == "iron":
        n = fbm(s, 8, ctx.rng, 3)
        alb = colorize(ctx.color, 0.8 + 0.3 * n)
        h = 0.4 * n
        rough = 0.45 + 0.1 * n
        metal = ones(ctx, 0.9)
        # Панели с рёбрами.
        frame = np.maximum(_band(s, s * 0.06, s * 0.12), _band(s, s * 0.94, s * 0.12))
        frame = np.maximum(frame, np.maximum(_band(s, s * 0.06, s * 0.12, False), _band(s, s * 0.94, s * 0.12, False)))
        malb, mh, mr = _metal(ctx, frame, np.array(ctx.color) * 0.8)
        alb, h, rough, metal = _apply(alb, h, rough, frame, malb, mh, mr, metal)
    else:
        alb, h, rough = planks(ctx, boards=4 if side else 5, horizontal=True)
        metal = ones(ctx, 0.0)
        iron = hex_rgb("#5a5c60")
        bands = []
        if side:
            bands = [(s * 0.08, s * 0.1, False), (s * 0.92, s * 0.1, False)]
            if kind == "reinforced":
                bands += [(s * 0.5, s * 0.08, True), (s * 0.08, s * 0.08, True), (s * 0.92, s * 0.08, True)]
        else:
            bands = [(s * 0.22, s * 0.1, False), (s * 0.78, s * 0.1, False)]
            if kind == "reinforced":
                bands += [(s * 0.5, s * 0.1, True)]
        for pos, w, hor in bands:
            m = _band(s, pos, w, hor)
            malb, mh, mr = _metal(ctx, m, iron, spacing=s // 5)
            alb, h, rough, metal = _apply(alb, h, rough, m, malb, mh, mr, metal)
    if side:
        # Замок: пластина и скважина по центру верхней трети.
        ys, xs = np.mgrid[0:s, 0:s]
        plate = ((np.abs(xs - s / 2) < s * 0.09) & (np.abs(ys - s * 0.42) < s * 0.11)).astype(float)
        malb, mh, mr = _metal(ctx, plate, hex_rgb("#b08a3a"), rivets=False)
        alb, h, rough, metal = _apply(alb, h, rough, plate, malb, mh, mr, metal)
        hole = ((np.abs(xs - s / 2) < s * 0.018) & (np.abs(ys - s * 0.44) < s * 0.045)).astype(float)
        alb *= (1 - 0.85 * hole)[..., None]
        h -= hole * 0.5
        # Щель крышки.
        lid = _band(s, s * 0.3, 2.0)
        alb *= (1 - 0.5 * lid)[..., None]
        h -= lid * 0.4
    return Tex(np.clip(alb, 0, 1), ones(ctx, 0.0), normalize(h), np.clip(rough, 0.05, 1), metal, normal_strength=2.4)


def dresser(ctx, side=True):
    s = ctx.size
    alb, h, rough = planks(ctx, boards=3 if side else 4, horizontal=not side)
    if not side:
        return Tex(np.clip(alb, 0, 1), ones(ctx, 0.0), h, rough, normal_strength=2.0)
    ys, xs = np.mgrid[0:s, 0:s]
    # Три ящика: рамка-фаска и ручки.
    face = colorize(np.array(ctx.color) * 1.08, 0.85 + 0.25 * fbm(s, 10, ctx.rng, 3, aniso=(0.12, 1.6)))
    metal = ones(ctx, 0.0)
    for k in range(3):
        y0, y1 = s * (0.06 + k * 0.31), s * (0.33 + k * 0.31)
        drawer = ((ys > y0) & (ys < y1) & (xs > s * 0.07) & (xs < s * 0.93)).astype(float)
        inner = blur(drawer, 2)
        alb = lerp_img(alb, face, drawer)
        bevel = np.clip(drawer - inner, 0, 1) * 3
        alb *= (1 - 0.3 * np.clip(bevel, 0, 1))[..., None]
        h = np.where(drawer > 0.5, 0.65 + 0.2 * inner, h * 0.5)
        r = np.sqrt((ys - (y0 + y1) / 2) ** 2 + (xs - s / 2) ** 2)
        knob = np.clip(s * 0.045 - r, 0, 1)
        alb = lerp_img(alb, solid(ctx, hex_rgb("#b08a3a")), knob)
        h += knob * 0.3
        metal = np.maximum(metal, knob * 0.9)
    return Tex(np.clip(alb, 0, 1), ones(ctx, 0.0), normalize(h), np.where(metal > 0.5, 0.3, rough), metal, normal_strength=2.2)


def barrel(ctx, side=True):
    s = ctx.size
    if side:
        alb, h, rough = planks(ctx, boards=6, horizontal=False, gap=1.5)
        # Бочка выпуклая: середина светлее.
        xs = np.mgrid[0:s, 0:s][1]
        alb *= (0.85 + 0.2 * np.sin(np.pi * ((xs % (s / 6)) / (s / 6))))[..., None]
        metal = ones(ctx, 0.0)
        for pos in (s * 0.15, s * 0.85):
            m = _band(s, pos, s * 0.09)
            malb, mh, mr = _metal(ctx, m, hex_rgb("#4a4c50"), spacing=s // 3)
            alb, h, rough, metal = _apply(alb, h, rough, m, malb, mh, mr, metal)
        return Tex(np.clip(alb, 0, 1), ones(ctx, 0.0), normalize(h), rough, metal, normal_strength=2.4)
    alb, h, rough = planks(ctx, boards=5, horizontal=True, gap=1.2)
    ys, xs = np.mgrid[0:s, 0:s] + 0.5
    r = np.sqrt((ys - s / 2) ** 2 + (xs - s / 2) ** 2) / s
    ring = ((r > 0.42) & (r < 0.5)).astype(float)
    outside = (r >= 0.5).astype(float)
    malb, mh, mr = _metal(ctx, ring, hex_rgb("#4a4c50"), rivets=False)
    metal = ones(ctx, 0.0)
    alb, h, rough, metal = _apply(alb, h, rough, ring, malb, mh, mr, metal)
    alb = lerp_img(alb, colorize(np.array(ctx.color) * 0.6, 0.8 + 0.3 * fbm(s, 6, ctx.rng, 2)), outside)
    plug = np.clip(s * 0.05 - np.sqrt((ys - s * 0.65) ** 2 + (xs - s * 0.62) ** 2), 0, 1)
    alb *= (1 - 0.4 * plug)[..., None]
    return Tex(np.clip(alb, 0, 1), ones(ctx, 0.0), normalize(h), rough, metal, normal_strength=2.0)


def crate(ctx):
    s = ctx.size
    alb, h, rough = planks(ctx, boards=4, horizontal=True)
    ys, xs = np.mgrid[0:s, 0:s]
    frame_w = s * 0.13
    frame = ((xs < frame_w) | (xs > s - frame_w) | (ys < frame_w) | (ys > s - frame_w)).astype(float)
    diag = (np.abs(xs - ys) < frame_w * 0.55).astype(float) * (1 - frame)
    lighter = colorize(np.array(ctx.color) * 1.12, 0.85 + 0.25 * fbm(s, 10, ctx.rng, 3, aniso=(0.12, 1.6)))
    for m in (frame, diag):
        alb = lerp_img(alb, lighter, m)
        h = np.where(m > 0.5, 0.8, h * 0.6)
        edge = np.clip(m - blur(m, 1), 0, 1)
        alb *= (1 - 0.35 * edge)[..., None]
    return Tex(np.clip(alb, 0, 1), ones(ctx, 0.0), normalize(h), rough, normal_strength=2.2)


def torch(ctx):
    """Спрайт факела: палка с обмоткой и пламенем (пламя светится — ORM.A)."""
    s = ctx.size
    rng = ctx.rng
    k = 4
    big = s * k
    img = Image.new("RGBA", (big, big), (0, 0, 0, 0))
    glow = Image.new("L", (big, big), 0)
    d = ImageDraw.Draw(img)
    dg = ImageDraw.Draw(glow)
    cx = big / 2
    d.rectangle([cx - k * 4, big * 0.38, cx + k * 4, big], fill=_rgba((0.42, 0.29, 0.16)))
    d.rectangle([cx - k * 4, big * 0.38, cx - k * 2, big], fill=_rgba((0.5, 0.36, 0.2)))
    for y in range(int(big * 0.36), int(big * 0.5), k * 3):
        d.rectangle([cx - k * 5, y, cx + k * 5, y + k * 2], fill=_rgba((0.55, 0.47, 0.32)))
    for layer, (col, scale) in enumerate([((0.95, 0.42, 0.08), 1.0), ((1.0, 0.7, 0.2), 0.7), ((1.0, 0.93, 0.6), 0.4)]):
        w = big * 0.13 * scale
        top = big * (0.1 + 0.08 * layer)
        pts = [(cx - w, big * 0.38), (cx + w, big * 0.38), (cx + w * 0.4, top + big * 0.08), (cx + rng.normal() * k, top),
               (cx - w * 0.5, top + big * 0.1)]
        d.polygon(pts, fill=_rgba(col))
        dg.polygon(pts, fill=255)
    img = img.resize((s, s), Image.LANCZOS)
    glow = glow.resize((s, s), Image.LANCZOS)
    a = np.asarray(img).astype(float) / 255
    alpha = (a[..., 3] > 0.4).astype(float)
    albedo = np.where(alpha[..., None] > 0, a[..., :3] / np.maximum(a[..., 3:4], 1e-3), np.array(ctx.color)[None, None, :])
    t = Tex(np.clip(albedo, 0, 1), alpha, blur(alpha, 1), 0.8 * ones(ctx), normal_strength=1.0, emissive=False)
    t.emission = (np.asarray(glow).astype(float) / 255) * alpha
    return t
