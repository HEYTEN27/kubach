"""Текстуры неба и погоды (этап 7): панорама ночного неба (звёзды разной яркости и цвета,
Млечный Путь с пылевыми прожилками), диск луны с морями и кратерами, бесшовный шум облаков
(R — крупная форма, G — мелкая детализация) и спрайты частиц: капля дождя, снежинка, градина,
брызги, листья, пыль."""
import math
import os

import numpy as np
from PIL import Image, ImageDraw, ImageFilter

from noise import fbm, value_noise, worley, blur, normalize


def night_sky(path, w=2048, h=1024, seed=7):
    """Равнопромежуточная панорама: x — азимут, y — высота (верх — зенит)."""
    rng = np.random.default_rng(seed)
    ys, xs = np.mgrid[0:h, 0:w]
    lat = (0.5 - (ys + 0.5) / h) * math.pi        # +π/2 зенит … −π/2 надир
    lon = (xs + 0.5) / w * 2 * math.pi
    # Единичный вектор и полоса Млечного Пути — большой круг под наклоном.
    vx, vy, vz = np.cos(lat) * np.cos(lon), np.sin(lat), np.cos(lat) * np.sin(lon)
    tilt = math.radians(62)
    n = np.array([0.0, math.cos(tilt), math.sin(tilt)])
    band_d = vx * n[0] + vy * n[1] + vz * n[2]
    band = np.exp(-(band_d / 0.22) ** 2)
    core = np.exp(-((vx - 0.55) ** 2 + (vy - 0.1) ** 2 + (vz - 0.6) ** 2) / 0.5)
    cloud = fbm(512, 10, rng, 6)
    cloud = np.array(Image.fromarray((cloud * 255).astype(np.uint8)).resize((w, h), Image.BILINEAR)) / 255.0
    dust = fbm(512, 24, rng, 5)
    dust = np.array(Image.fromarray((dust * 255).astype(np.uint8)).resize((w, h), Image.BILINEAR)) / 255.0
    glow = band * (0.35 + 0.65 * cloud) * (0.6 + 0.8 * core)
    lanes = np.clip((dust - 0.55) * 3.0, 0, 1) * band
    glow = np.clip(glow - lanes * 0.6, 0, 1)
    img = np.zeros((h, w, 3))
    img += glow[..., None] * np.array([0.16, 0.15, 0.2])
    img += (glow ** 2)[..., None] * np.array([0.12, 0.1, 0.08]) * (1 + core[..., None])
    # Звёзды: больше в полосе, цвет по «температуре», немного ярких с ореолом.
    count = 9000
    sx = rng.integers(0, w, count)
    sy = (np.arcsin(rng.uniform(-1, 1, count)) / math.pi + 0.5) * h
    sy = np.clip((h - 1 - sy).astype(int), 0, h - 1)
    extra = rng.random(count) < band[sy, sx] * 0.7
    mag = rng.power(6, count) * (1.0 + extra * 0.6)
    temps = rng.random(count)
    cols = np.stack([0.75 + 0.25 * temps, 0.8 + 0.1 * temps, 1.0 - 0.3 * temps], -1)
    for i in range(count):
        b = mag[i] ** 3
        img[sy[i], sx[i]] += cols[i] * b * 1.6
    bright = np.argsort(mag)[-60:]
    halo = np.zeros((h, w))
    for i in bright:
        halo[sy[i], sx[i]] += mag[i] * 4
    halo = np.array(Image.fromarray(np.clip(halo * 60, 0, 255).astype(np.uint8)).filter(ImageFilter.GaussianBlur(2))) / 255.0
    img += halo[..., None] * np.array([0.8, 0.85, 1.0])
    img = np.clip(img, 0, 1)
    Image.fromarray((img ** (1 / 1.4) * 255).astype(np.uint8), "RGB").save(path)


def moon(path, s=256, seed=11):
    """Диск луны: светлые материки, тёмные моря, кратеры с валом и тенью, альфа — диск."""
    rng = np.random.default_rng(seed)
    ys, xs = np.mgrid[0:s, 0:s]
    cx = (xs - s / 2 + 0.5) / (s / 2)
    cy = (ys - s / 2 + 0.5) / (s / 2)
    r = np.sqrt(cx ** 2 + cy ** 2)
    base = fbm(s, 4, rng, 5)
    maria = np.clip((fbm(s, 3, rng, 4) - 0.48) * 3.2, 0, 1)
    maria = blur(maria, 3)
    alb = 0.8 + 0.14 * base - 0.55 * maria
    h = np.zeros((s, s))
    for _ in range(70):
        x, y = rng.uniform(-0.9, 0.9, 2)
        rr = rng.power(0.18) * 0.1 + 0.012
        d = np.sqrt((cx - x) ** 2 + (cy - y) ** 2) / rr
        bowl = np.clip(1 - d, 0, 1) ** 1.5
        rim = np.exp(-((d - 1.0) / 0.25) ** 2)
        h += -bowl * 0.5 + rim * 0.2
        alb += rim * 0.035 - bowl * 0.03
        if rng.random() < 0.1:
            # Лучевая система молодого кратера.
            ang = np.arctan2(cy - y, cx - x)
            rays = np.clip(np.cos(ang * rng.integers(7, 13)) - 0.6, 0, 1) * np.exp(-np.clip(d - 1, 0, None) / 4)
            alb += rays * 0.12 * (d > 1)
    h = blur(h, 1)
    shade = np.clip(1 + (np.roll(h, 1, 1) - h) * 0.9, 0.75, 1.2)
    alb = np.clip(alb * shade, 0, 1)
    limb = np.clip(1 - r ** 4 * 0.35, 0, 1)
    a = np.clip((1 - r) * s * 0.5, 0, 1)
    img = np.zeros((s, s, 4))
    img[..., 0] = alb * limb * 0.98
    img[..., 1] = alb * limb * 0.97
    img[..., 2] = alb * limb * 0.92
    img[..., 3] = a
    Image.fromarray((np.clip(img, 0, 1) * 255).astype(np.uint8), "RGBA").save(path)


def clouds(path, s=512, seed=19):
    """Бесшовный шум облаков: R — кучевая форма (fbm + Worley), G — мелкие клочья."""
    rng = np.random.default_rng(seed)
    big = fbm(s, 4, rng, 6)
    f1, f2, _ = worley(s, 6, rng)
    puffs = 1 - np.clip(f1 / 0.9, 0, 1)
    shape = normalize(0.65 * big + 0.35 * puffs)
    detail = normalize(fbm(s, 24, rng, 4) * 0.7 + (1 - np.clip(worley(s, 20, rng)[0], 0, 1)) * 0.3)
    img = np.zeros((s, s, 3))
    img[..., 0] = shape
    img[..., 1] = detail
    img[..., 2] = normalize(fbm(s, 8, rng, 3))
    Image.fromarray((img * 255).astype(np.uint8), "RGB").save(path)


def particles(out_dir, size=64):
    rng = np.random.default_rng(5)
    os.makedirs(out_dir, exist_ok=True)
    ys, xs = np.mgrid[0:size, 0:size]
    cx = (xs - size / 2 + 0.5) / (size / 2)
    cy = (ys - size / 2 + 0.5) / (size / 2)
    r = np.sqrt(cx ** 2 + cy ** 2)
    # Капля: вытянутый штрих, светлее к низу.
    streak = np.clip(1 - np.abs(cx) * 1.4, 0, 1) ** 1.5 * np.clip(1 - np.abs(cy) * 1.05, 0, 1)
    rain = np.zeros((size, size, 4))
    rain[..., :3] = np.array([0.75, 0.82, 0.92])
    rain[..., 3] = streak * (0.45 + 0.55 * (cy + 1) / 2)
    # Снежинка: шесть лучей с отростками + мягкий центр.
    flake = Image.new("L", (size * 4, size * 4), 0)
    d = ImageDraw.Draw(flake)
    c = size * 2
    for k in range(6):
        a = k * math.pi / 3
        ex, ey = c + math.cos(a) * size * 1.7, c + math.sin(a) * size * 1.7
        d.line([(c, c), (ex, ey)], fill=255, width=7)
        for t in (0.45, 0.75):
            bx, by = c + math.cos(a) * size * 1.7 * t, c + math.sin(a) * size * 1.7 * t
            for s2 in (-1, 1):
                d.line([(bx, by), (bx + math.cos(a + s2 * 0.7) * size * 0.4, by + math.sin(a + s2 * 0.7) * size * 0.4)], fill=255, width=5)
    flake = np.array(flake.resize((size, size), Image.LANCZOS)) / 255.0
    snow = np.zeros((size, size, 4))
    snow[..., :3] = 1.0
    snow[..., 3] = np.clip(flake + np.clip(1 - r * 3, 0, 1) * 0.6, 0, 1)
    # Градина: матовый шарик с бликом.
    hail = np.zeros((size, size, 4))
    hail[..., :3] = (0.82 + 0.18 * np.clip(1 - np.sqrt((cx + 0.3) ** 2 + (cy + 0.3) ** 2) * 2, 0, 1))[..., None]
    hail[..., 3] = np.clip((1 - r) * 6, 0, 1)
    # Брызги: кольцо капель.
    splash = np.zeros((size, size, 4))
    splash[..., :3] = np.array([0.8, 0.86, 0.95])
    ring = np.exp(-((r - 0.6) / 0.12) ** 2) * (0.5 + 0.5 * np.sin(np.arctan2(cy, cx) * 7))
    splash[..., 3] = np.clip(ring * 0.9, 0, 1)
    # Листья: лист с черешком и жилкой (цвет — осенний, тонируется частицей).
    leaf = Image.new("RGBA", (size * 4, size * 4), (0, 0, 0, 0))
    d = ImageDraw.Draw(leaf)
    d.ellipse([size * 0.9, size * 0.6, size * 3.1, size * 3.4], fill=(255, 255, 255, 255))
    d.line([(size * 2, size * 3.3), (size * 2, size * 3.9)], fill=(200, 200, 200, 255), width=10)
    d.line([(size * 2, size * 0.8), (size * 2, size * 3.3)], fill=(170, 170, 170, 255), width=6)
    leaf = np.array(leaf.resize((size, size), Image.LANCZOS)) / 255.0
    leaf[..., :3] *= (0.85 + 0.15 * value_noise(size, 8, rng))[..., None]
    # Пыль: мягкое неровное облачко.
    dust = np.zeros((size, size, 4))
    dust[..., :3] = np.array([0.78, 0.68, 0.5])
    dust[..., 3] = np.clip((1 - r) * (0.5 + 0.5 * fbm(size, 6, rng, 3)), 0, 1) * 0.7
    for name, img in (("rain", rain), ("snowflake", snow), ("hail", hail), ("splash", splash), ("leaf", leaf),
                      ("dust", dust)):
        Image.fromarray((np.clip(img, 0, 1) * 255).astype(np.uint8), "RGBA").save(os.path.join(out_dir, name + ".png"))


def build(out_dir):
    sky = os.path.join(out_dir, "sky")
    os.makedirs(sky, exist_ok=True)
    night_sky(os.path.join(sky, "night_sky.png"))
    moon(os.path.join(sky, "moon.png"))
    clouds(os.path.join(sky, "clouds.png"))
    particles(os.path.join(out_dir, "particles"))


if __name__ == "__main__":
    build(os.path.join(os.path.dirname(__file__), "..", "..", "assets", "textures", "generated"))
