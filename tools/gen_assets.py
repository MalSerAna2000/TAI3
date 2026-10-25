#!/usr/bin/env python3
"""Генератор ассетов проекта «Темный Бог Надувных Замков».

Все текстуры (PNG) и звуки (Ogg Vorbis) синтезируются процедурно: каждая
текстура/трек уникальны (без дублирования файлов). PNG-исходники высокого
разрешения — при экспорте на Android Godot сожмёт их в ETC2/ASTC.

Использование:  python3 tools/gen_assets.py [--scale 1.0]
--scale масштабирует разрешения текстур (итоговый размер проекта).
Требуются: numpy, pillow, soundfile.
"""
import argparse
import os
import numpy as np
from PIL import Image, ImageDraw, ImageFilter

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
TEX = os.path.join(ROOT, "assets", "textures")
AUD = os.path.join(ROOT, "assets", "audio")
os.makedirs(TEX, exist_ok=True)
os.makedirs(AUD, exist_ok=True)
rng = np.random.default_rng(20251025)
SCALE = 1.0

# ------------------------------------------------------------------ утилиты
def res(n):
    return max(64, int(round(n * SCALE)))

def fbm(w, h, exponent=2.0, seed=1, aniso=(1.0, 1.0)):
    """Тайлящийся фрактальный шум через обратный FFT (периодические границы)."""
    r = np.random.default_rng(seed)
    fy = np.fft.fftfreq(h)[:, None] * aniso[1]
    fx = np.fft.fftfreq(w)[None, :] * aniso[0]
    freq = np.sqrt(fx * fx + fy * fy)
    freq[0, 0] = 1.0
    amp = freq ** (-exponent)
    phase = r.uniform(0, 2 * np.pi, (h, w))
    spec = amp * np.exp(1j * phase)
    img = np.fft.ifft2(spec).real
    img -= img.min()
    img /= (img.max() + 1e-9)
    return img.astype(np.float32)

def mix3(base_h, c_dark, c_mid, c_light):
    """Трёхцветный градиент по высотной карте -> RGB float 0..1."""
    h = np.clip(base_h, 0, 1)
    lo = np.clip(h * 2, 0, 1)[..., None]
    hi = np.clip(h * 2 - 1, 0, 1)[..., None]
    dark = np.array(c_dark, dtype=np.float32)
    mid = np.array(c_mid, dtype=np.float32)
    light = np.array(c_light, dtype=np.float32)
    return dark * (1 - lo) + mid * lo * (1 - hi) + light * hi

def to_img(rgb):
    return Image.fromarray((np.clip(rgb, 0, 1) * 255).astype(np.uint8))

def save(img, name):
    path = os.path.join(TEX, name + ".png")
    img.save(path, optimize=False)
    print("tex", name, img.size, f"{os.path.getsize(path)/1048576:.1f} MB")

def normal_from_height(hgt, strength=2.0):
    dx = (np.roll(hgt, -1, axis=1) - np.roll(hgt, 1, axis=1)) * strength
    dy = (np.roll(hgt, -1, axis=0) - np.roll(hgt, 1, axis=0)) * strength
    n = np.stack([-dx, dy, np.ones_like(hgt)], axis=-1)
    n /= np.linalg.norm(n, axis=-1, keepdims=True) + 1e-9
    return to_img(n * 0.5 + 0.5)

def gray_tex(hgt, lo=0.2, hi=1.0):
    g = lo + np.clip(hgt, 0, 1) * (hi - lo)
    return to_img(np.stack([g, g, g], axis=-1))

def speckle(rgb, amount, seed):
    r = np.random.default_rng(seed)
    n = (r.random(rgb.shape[:2]).astype(np.float32) - 0.5) * amount
    return rgb + n[..., None]

def quilt(w, h, cells=6):
    """Стёганые ромбы надувных камер ПВХ: высотная карта подушек."""
    yy, xx = np.mgrid[0:h, 0:w].astype(np.float32)
    u = (xx + yy) / w * cells
    v = (xx - yy) / w * cells
    q = np.abs(np.sin(u * np.pi)) * np.abs(np.sin(v * np.pi))
    return np.power(q, 0.65).astype(np.float32)

# ------------------------------------------------------------------ текстуры земли
def tex_grass():
    s = res(4096)  # герой-текстура ландшафта крупным планом
    hgt = fbm(s, s, 1.9, 101)
    patch = fbm(s, s, 2.6, 102)
    rgb = mix3(hgt * 0.65 + patch * 0.35, (0.05, 0.12, 0.02), (0.13, 0.3, 0.07), (0.35, 0.5, 0.16))
    dry = fbm(s, s, 2.2, 103)
    dry_mask = np.clip((dry - 0.62) * 3, 0, 1)[..., None]
    rgb = rgb * (1 - dry_mask) + np.array([0.45, 0.42, 0.18], dtype=np.float32) * dry_mask
    rgb = speckle(rgb, 0.16, 104)
    img = to_img(rgb)
    d = ImageDraw.Draw(img)
    r = np.random.default_rng(105)
    for _ in range(int(9000 * SCALE)):
        x, y = r.integers(0, s, 2)
        ln = r.integers(3, 9)
        col = (int(40 + r.random() * 60), int(110 + r.random() * 90), int(25 + r.random() * 40))
        d.line([(x, y), (x + r.integers(-2, 3), y - ln)], fill=col, width=1)
    save(img, "grass_albedo")
    save(normal_from_height(hgt * 0.6 + fbm(s, s, 1.2, 106) * 0.4, 1.6), "grass_normal")
    s2 = res(1024)
    save(gray_tex(fbm(s2, s2, 1.8, 107), 0.75, 1.0), "grass_roughness")
    save(gray_tex(fbm(s2, s2, 2.0, 108), 0.45, 1.0), "grass_ao")

def tex_rock():
    s = res(2048)
    hgt = fbm(s, s, 1.6, 201)
    ridge = 1.0 - np.abs(fbm(s, s, 1.7, 202) * 2 - 1)
    rgb = mix3(hgt * 0.6 + ridge * 0.4, (0.1, 0.1, 0.11), (0.32, 0.32, 0.34), (0.62, 0.62, 0.65))
    crack = np.clip((np.abs(fbm(s, s, 1.3, 203) - 0.5) - 0.015) * 30, 0, 1)[..., None]
    rgb = rgb * crack + np.array([0.05, 0.05, 0.05], dtype=np.float32) * (1 - crack)
    strata = (np.sin(np.linspace(0, 40 * np.pi, s)) * 0.04).astype(np.float32)
    rgb = speckle(rgb + strata[:, None, None], 0.12, 204)
    save(to_img(rgb), "rock_albedo")
    save(normal_from_height(hgt, 3.0), "rock_normal")
    save(gray_tex(speckle(fbm(s, s, 1.7, 205)[..., None], 0.1, 206)[..., 0], 0.8, 1.0), "rock_roughness")
    save(gray_tex(fbm(s, s, 1.8, 207), 0.4, 1.0), "rock_ao")

def tex_sand_snow():
    s = res(2048)
    hgt = fbm(s, s, 2.1, 301)
    rgb = mix3(hgt, (0.55, 0.43, 0.25), (0.76, 0.64, 0.4), (0.92, 0.82, 0.58))
    save(to_img(speckle(rgb, 0.13, 302)), "sand_albedo")
    s2 = res(1024)
    save(normal_from_height(fbm(s2, s2, 1.4, 303), 1.1), "sand_normal")
    h2 = fbm(s2, s2, 2.4, 304)
    rgb2 = mix3(h2, (0.62, 0.7, 0.85), (0.85, 0.9, 0.98), (1.0, 1.0, 1.0))
    save(to_img(speckle(rgb2, 0.05, 305)), "snow_albedo")
    save(normal_from_height(fbm(res(512), res(512), 1.6, 306), 0.8), "snow_normal")

# ------------------------------------------------------------------ ПВХ и ткани
def tex_pvc(name, dark, mid, light, size, seed, extra_maps=True):
    s = res(size)
    q = quilt(s, s, 6)
    base = q * 0.72 + fbm(s, s, 2.3, seed) * 0.28
    rgb = mix3(base, dark, mid, light)
    seam = np.clip(q * 6 - 0.4, 0, 1)[..., None]
    rgb = rgb * (0.45 + 0.55 * seam)
    rgb = speckle(rgb, 0.11, seed + 1)  # микроплетение ткани ПВХ
    save(to_img(rgb), name + "_albedo")
    save(normal_from_height(base, 2.6), name + "_normal")
    if extra_maps:
        s2 = res(1024)
        save(gray_tex(quilt(s2, s2, 6) * 0.5 + fbm(s2, s2, 2.0, seed + 2) * 0.5, 0.18, 0.55), name + "_roughness")
        save(gray_tex(quilt(s2, s2, 6) * 0.7 + fbm(s2, s2, 2.1, seed + 7) * 0.3, 0.35, 1.0), name + "_ao")

def tex_laces():
    s = res(2048)
    q = quilt(s, s, 8)
    base = q * 0.6 + fbm(s, s, 2.2, 401) * 0.4
    rgb = mix3(base, (0.16, 0.01, 0.03), (0.42, 0.04, 0.08), (0.66, 0.14, 0.16))
    img = to_img(speckle(rgb, 0.05, 402))
    d = ImageDraw.Draw(img)
    cell = s // 8
    for gy in range(8):
        for gx in range(8):
            cx, cy = gx * cell + cell // 2, gy * cell + cell // 2
            for rr in (cell // 5, cell // 3):
                d.ellipse([cx - rr, cy - rr, cx + rr, cy + rr], outline=(230, 180, 180), width=2)
            d.ellipse([cx - 4, cy - 4, cx + 4, cy + 4], fill=(240, 200, 200))
    save(img, "lace_darkred_albedo")
    # Белое кружево с альфой (фестоны) для фартуков и рюшей
    s2 = res(1024)
    img2 = Image.new("RGBA", (s2, s2), (255, 255, 255, 0))
    d2 = ImageDraw.Draw(img2)
    step = s2 // 6
    for gy in range(6):
        for gx in range(6):
            x0, y0 = gx * step, gy * step
            d2.pieslice([x0, y0, x0 + step, y0 + step], 0, 180, fill=(255, 250, 250, 235))
            d2.arc([x0, y0, x0 + step, y0 + step], 0, 180, fill=(220, 210, 215, 255), width=3)
            for k in range(4):
                px = x0 + step * (k + 0.5) / 4
                d2.ellipse([px - 4, y0 + step * 0.55 - 4, px + 4, y0 + step * 0.55 + 4], fill=(0, 0, 0, 0))
    save(img2, "lace_white_albedo")

def tex_fabrics():
    s = res(2048)
    silk_h = fbm(s, s, 2.0, 501, aniso=(3.0, 0.4))
    rgb = mix3(silk_h, (0.72, 0.3, 0.4), (0.95, 0.55, 0.65), (1.0, 0.78, 0.82))
    save(to_img(speckle(rgb, 0.03, 502)), "silk_pink_albedo")
    s2 = res(1024)
    rgb2 = mix3(fbm(s2, s2, 2.0, 503, aniso=(3.0, 0.4)), (0.25, 0.45, 0.8), (0.5, 0.72, 1.0), (0.75, 0.88, 1.0))
    save(to_img(speckle(rgb2, 0.03, 504)), "silk_blue_albedo")
    # Деним: диагональный твил
    yy, xx = np.mgrid[0:s, 0:s].astype(np.float32)
    twill = 0.5 + 0.5 * np.sin((xx + yy) * 2.2)
    rgb3 = mix3(fbm(s, s, 2.1, 505) * 0.7 + twill * 0.3, (0.1, 0.18, 0.38), (0.22, 0.36, 0.66), (0.42, 0.56, 0.85))
    save(to_img(speckle(rgb3, 0.08, 506)), "denim_albedo")
    # Белый хлопок пижамы: faint клетка
    check = ((np.sin(xx * 0.11) > 0) ^ (np.sin(yy * 0.11) > 0)).astype(np.float32) * 0.05
    rgb4 = mix3(fbm(s, s, 2.3, 507) + check, (0.82, 0.82, 0.8), (0.93, 0.93, 0.91), (1.0, 1.0, 0.99))
    save(to_img(speckle(rgb4, 0.04, 508)), "cotton_white_albedo")
    # Волосы: вертикальные пряди
    hair_h = fbm(s, s, 1.5, 509, aniso=(6.0, 0.25))
    save(to_img(mix3(hair_h, (0.78, 0.78, 0.84), (0.94, 0.94, 0.98), (1.0, 1.0, 1.0))), "hair_white_albedo")
    save(to_img(mix3(hair_h, (0.005, 0.005, 0.01), (0.05, 0.05, 0.07), (0.16, 0.15, 0.2))), "hair_black_albedo")
    # Пеньковая верёвка
    s3 = res(512)
    yy3, xx3 = np.mgrid[0:s3, 0:s3].astype(np.float32)
    twist = 0.5 + 0.5 * np.sin((xx3 * 0.8 + yy3) * 0.55)
    rgb5 = mix3(fbm(s3, s3, 1.8, 510) * 0.55 + twist * 0.45, (0.3, 0.22, 0.1), (0.55, 0.43, 0.24), (0.75, 0.62, 0.4))
    save(to_img(speckle(rgb5, 0.12, 511)), "rope_hemp_albedo")
    # Кора и хвоя
    bark_h = 1.0 - np.abs(fbm(s, s, 1.5, 512, aniso=(5.0, 0.5)) * 2 - 1)
    save(to_img(mix3(bark_h, (0.1, 0.06, 0.03), (0.3, 0.2, 0.11), (0.5, 0.38, 0.24))), "bark_albedo")
    pine_h = fbm(s, s, 1.2, 513)
    save(to_img(speckle(mix3(pine_h, (0.02, 0.08, 0.03), (0.06, 0.22, 0.08), (0.16, 0.38, 0.14)), 0.2, 514)), "pine_albedo")

def tex_water_sky():
    s = res(2048)
    save(normal_from_height(fbm(s, s, 1.8, 601) * 0.7 + fbm(s, s, 1.2, 602) * 0.3, 1.4), "water_normal")
    # Дым воронки циклона: горизонтальные полосы с альфой
    streak = fbm(s, s, 1.7, 603, aniso=(0.35, 2.5))
    alpha = np.clip((streak - 0.28) * 2.4, 0, 1)
    rgba = np.zeros((s, s, 4), dtype=np.float32)
    rgba[..., 0] = 0.82
    rgba[..., 1] = 0.85
    rgba[..., 2] = 0.92
    rgba[..., 3] = alpha * 0.85
    save(Image.fromarray((rgba * 255).astype(np.uint8)), "cyclone_smoke")
    # Звёздное небо (прозрачная панорама-оболочка)
    w, h = res(4096), res(2048)
    img = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    r = np.random.default_rng(604)
    # Млечный путь: мягкая диагональная полоса
    for _ in range(260):
        t = r.random()
        x = t * w + r.normal(0, 120)
        y = h * (0.62 - t * 0.4) + r.normal(0, 90)
        rad = r.integers(20, 90)
        d.ellipse([x - rad, y - rad * 0.5, x + rad, y + rad * 0.5], fill=(170, 185, 230, int(r.integers(4, 14))))
    for _ in range(4200):
        x, y = r.random() * w, r.random() * h * 0.92
        b = int(120 + r.random() * 135)
        tone = r.random()
        col = (b, b, b, 255) if tone < 0.7 else (int(b * 0.75), int(b * 0.85), b, 255)
        rad = 1 if r.random() < 0.85 else 2
        d.ellipse([x - rad, y - rad, x + rad, y + rad], fill=col)
        if r.random() < 0.012:
            d.line([(x - 7, y), (x + 7, y)], fill=col, width=1)
            d.line([(x, y - 7), (x, y + 7)], fill=col, width=1)
    img = img.filter(ImageFilter.GaussianBlur(0.6))
    save(img, "sky_stars")
    # Луна
    s3 = res(512)
    moon_h = fbm(s3, s3, 2.0, 605)
    rgb = mix3(moon_h, (0.55, 0.58, 0.66), (0.82, 0.84, 0.9), (0.98, 0.98, 1.0))
    imgm = Image.new("RGBA", (s3, s3), (0, 0, 0, 0))
    mask = Image.new("L", (s3, s3), 0)
    dm = ImageDraw.Draw(mask)
    dm.ellipse([s3 * 0.14, s3 * 0.14, s3 * 0.86, s3 * 0.86], fill=255)
    imgm.paste(to_img(rgb), (0, 0), mask.filter(ImageFilter.GaussianBlur(2)))
    save(imgm, "moon")

# ------------------------------------------------------------------ лицо Бога и иконки
def _sprite_canvas(w, h):
    return Image.new("RGBA", (w, h), (0, 0, 0, 0))

def tex_face():
    w, h = 256, 320
    # Открытый красный аниме-глаз
    img = _sprite_canvas(w, h)
    d = ImageDraw.Draw(img)
    d.ellipse([18, 40, w - 18, h - 30], fill=(255, 252, 252, 255))
    cx, cy = w // 2, h // 2 + 6
    for rr, col in [(86, (120, 0, 10, 255)), (74, (190, 10, 25, 255)), (58, (235, 40, 55, 255)), (40, (255, 90, 100, 255))]:
        d.ellipse([cx - rr, cy - int(rr * 1.18), cx + rr, cy + int(rr * 1.18)], fill=col)
    d.ellipse([cx - 26, cy - 34, cx + 26, cy + 34], fill=(30, 0, 5, 255))
    d.ellipse([cx - 38, cy - 58, cx - 8, cy - 28], fill=(255, 255, 255, 255))
    d.ellipse([cx + 16, cy + 26, cx + 34, cy + 44], fill=(255, 255, 255, 230))
    d.arc([8, 18, w - 8, h - 8], 180, 360, fill=(25, 5, 8, 255), width=26)
    d.arc([8, 18, w - 8, h - 8], 200, 340, fill=(25, 5, 8, 255), width=30)
    d.arc([30, 60, w - 30, h - 16], 30, 150, fill=(60, 20, 25, 200), width=7)
    save(img, "eye_red_open")
    # >_< : счастливый зажмуренный глаз «>» (второй глаз зеркалится в игре)
    img = _sprite_canvas(w, h)
    d = ImageDraw.Draw(img)
    d.line([(52, 70), (196, h // 2), (52, h - 70)], fill=(35, 5, 10, 255), width=34, joint="curve")
    d.ellipse([180, h // 2 - 17, 214, h // 2 + 17], fill=(35, 5, 10, 255))
    d.ellipse([36, 54, 70, 88], fill=(35, 5, 10, 255))
    d.ellipse([36, h - 88, 70, h - 54], fill=(35, 5, 10, 255))
    save(img, "eye_happy")
    # Закрытый спокойный глаз (дуга)
    img = _sprite_canvas(w, h)
    d = ImageDraw.Draw(img)
    d.arc([30, 70, w - 30, h - 110], 195, 345, fill=(35, 8, 12, 255), width=22)  # дуга ∩ — довольный закрытый глаз
    for fx, fy in [(42, h // 2 - 6), (w // 2, h // 2 - 34), (w - 42, h // 2 - 6)]:
        d.line([(fx, fy), (fx - 8, fy + 22)], fill=(35, 8, 12, 255), width=10)
    save(img, "eye_closed")
    # Рты
    mw, mh = 256, 160
    img = _sprite_canvas(mw, mh)
    d = ImageDraw.Draw(img)
    d.arc([58, 10, mw - 58, 140], 20, 160, fill=(90, 20, 25, 255), width=13)
    save(img, "mouth_smile")
    img = _sprite_canvas(mw, mh)
    d = ImageDraw.Draw(img)
    d.ellipse([88, 25, mw - 88, 135], fill=(85, 8, 16, 255))
    d.pieslice([88, 55, mw - 88, 150], 0, 180, fill=(235, 110, 125, 255))
    d.ellipse([98, 30, mw - 98, 62], fill=(255, 245, 245, 255))
    save(img, "mouth_open")
    img = _sprite_canvas(mw, mh)
    d = ImageDraw.Draw(img)
    d.arc([38, 20, mw // 2 + 6, 120], 15, 165, fill=(90, 20, 25, 255), width=12)
    d.arc([mw // 2 - 6, 20, mw - 38, 120], 15, 165, fill=(90, 20, 25, 255), width=12)
    save(img, "mouth_cat")
    # Румянец
    img = _sprite_canvas(256, 128)
    d = ImageDraw.Draw(img)
    d.ellipse([28, 28, 228, 100], fill=(255, 130, 150, 160))
    img = img.filter(ImageFilter.GaussianBlur(14))
    save(img, "blush")
    # Сердечко частиц няшинга
    img = _sprite_canvas(256, 256)
    d = ImageDraw.Draw(img)
    d.ellipse([28, 30, 128, 130], fill=(245, 60, 95, 255))
    d.ellipse([128, 30, 228, 130], fill=(245, 60, 95, 255))
    d.polygon([(34, 96), (222, 96), (128, 232)], fill=(245, 60, 95, 255))
    d.ellipse([58, 52, 92, 84], fill=(255, 190, 205, 255))
    save(img, "heart")

def tex_menu_and_icon():
    w, h = res(2560), res(1440)
    # Вертикальный градиент ночного неба
    grad = np.zeros((h, w, 3), dtype=np.float32)
    for y in range(h):
        t = y / h
        top = np.array([0.012, 0.004, 0.05])
        mid = np.array([0.09, 0.02, 0.14])
        low = np.array([0.32, 0.06, 0.1])
        col = top * (1 - min(t * 1.6, 1)) + mid * min(t * 1.6, 1) if t < 0.62 else mid * (1 - (t - 0.62) / 0.38) + low * ((t - 0.62) / 0.38)
        grad[y, :, :] = col
    img = to_img(grad * (0.92 + fbm(w, h, 2.6, 701)[..., None] * 0.16))
    d = ImageDraw.Draw(img, "RGBA")
    r = np.random.default_rng(702)
    for _ in range(900):
        x, y = r.random() * w, r.random() * h * 0.55
        b = int(90 + r.random() * 165)
        d.ellipse([x - 1.5, y - 1.5, x + 1.5, y + 1.5], fill=(b, b, int(b * 1.05), 255))
    # Красная луна
    mx, my, mr = int(w * 0.78), int(h * 0.2), int(h * 0.115)
    for i in range(7, 0, -1):
        d.ellipse([mx - mr - i * 14, my - mr - i * 14, mx + mr + i * 14, my + mr + i * 14], fill=(255, 60, 70, 8))
    d.ellipse([mx - mr, my - mr, mx + mr, my + mr], fill=(235, 90, 95, 255))
    d.ellipse([mx - mr * 0.7, my - mr * 0.55, mx - mr * 0.2, my - mr * 0.05], fill=(205, 70, 80, 255))
    d.ellipse([mx + mr * 0.15, my + mr * 0.1, mx + mr * 0.55, my + mr * 0.5], fill=(210, 75, 85, 255))
    # Дальние горы и долина
    ridge = fbm(256, 1, 2.0, 703)[0]
    pts = [(int(w * i / 255), int(h * (0.62 + ridge[i] * 0.1))) for i in range(256)]
    d.polygon(pts + [(w, h), (0, h)], fill=(10, 6, 18, 255))
    ridge2 = fbm(256, 1, 2.0, 704)[0]
    pts2 = [(int(w * i / 255), int(h * (0.74 + ridge2[i] * 0.07))) for i in range(256)]
    d.polygon(pts2 + [(w, h), (0, h)], fill=(6, 3, 12, 255))
    # Силуэт НЗТБНЗ по центру: корпус, башни, крылья, светящиеся красный проём и глаза
    cx, base_y = w * 0.5, h * 0.8
    cw, chh = w * 0.17, h * 0.34
    dark = (26, 4, 10, 255)
    rim = (120, 22, 34, 255)
    def wing_poly(side):
        return [(cx + side * cw * 0.45, base_y - chh * 0.72),
                (cx + side * cw * 1.65, base_y - chh * 1.12),
                (cx + side * cw * 1.2, base_y - chh * 0.62),
                (cx + side * cw * 1.55, base_y - chh * 0.55),
                (cx + side * cw * 0.95, base_y - chh * 0.3),
                (cx + side * cw * 0.45, base_y - chh * 0.35)]
    d.polygon(wing_poly(-1), fill=dark)
    d.polygon(wing_poly(1), fill=dark)
    d.rounded_rectangle([cx - cw / 2, base_y - chh, cx + cw / 2, base_y], radius=int(cw * 0.06), fill=dark, outline=rim, width=3)
    for sx in (-0.62, 0.62):
        tx = cx + sx * cw
        d.rounded_rectangle([tx - cw * 0.075, base_y - chh * 1.42, tx + cw * 0.075, base_y], radius=8, fill=dark, outline=rim, width=2)
        d.polygon([(tx - cw * 0.11, base_y - chh * 1.42), (tx + cw * 0.11, base_y - chh * 1.42), (tx, base_y - chh * 1.68)], fill=dark)
    gw, gh = cw * 0.14, chh * 0.3
    d.rounded_rectangle([cx - gw / 2, base_y - gh, cx + gw / 2, base_y], radius=int(gw * 0.4), fill=(255, 70, 60, 255))
    d.rounded_rectangle([cx - gw / 2 + 5, base_y - gh + 7, cx + gw / 2 - 5, base_y], radius=int(gw * 0.3), fill=(255, 150, 110, 255))
    for ex in (-0.045, 0.045):
        exx = cx + ex * w
        eyy = base_y - chh * 0.78
        d.ellipse([exx - 7, eyy - 13, exx + 7, eyy + 13], fill=(255, 45, 55, 255))
    # Туман у земли
    for _ in range(46):
        x = r.random() * w
        y = h * (0.78 + r.random() * 0.16)
        rw = r.integers(int(w * 0.06), int(w * 0.2))
        d.ellipse([x - rw, y - rw * 0.09, x + rw, y + rw * 0.09], fill=(190, 170, 210, int(r.integers(7, 20))))
    img = img.filter(ImageFilter.GaussianBlur(0.7))
    arr = np.asarray(img).astype(np.float32) / 255.0
    arr = speckle(arr, 0.09, 705)
    img = to_img(arr)
    save(img, "menu_bg")
    # Иконка проекта
    s = 512
    icon = Image.new("RGBA", (s, s), (14, 2, 18, 255))
    di = ImageDraw.Draw(icon, "RGBA")
    di.ellipse([s * 0.66, s * 0.07, s * 0.92, s * 0.33], fill=(235, 90, 95, 255))
    di.rounded_rectangle([s * 0.3, s * 0.34, s * 0.7, s * 0.86], radius=26, fill=(120, 12, 24, 255), outline=(200, 60, 75, 255), width=5)
    di.polygon([(s * 0.3, s * 0.5), (s * 0.05, s * 0.3), (s * 0.22, s * 0.62)], fill=(120, 12, 24, 255))
    di.polygon([(s * 0.7, s * 0.5), (s * 0.95, s * 0.3), (s * 0.78, s * 0.62)], fill=(120, 12, 24, 255))
    di.rounded_rectangle([s * 0.45, s * 0.6, s * 0.55, s * 0.86], radius=14, fill=(255, 140, 100, 255))
    for ex in (0.42, 0.58):
        di.ellipse([s * ex - 8, s * 0.45, s * ex + 8, s * 0.52], fill=(255, 60, 70, 255))
    icon.save(os.path.join(ROOT, "icon.png"))
    print("tex icon.png (project root)")

# ------------------------------------------------------------------ аудио
SR = 44100

def save_ogg(name, data, peak=0.85):
    import soundfile as sf
    data = np.asarray(data, dtype=np.float32)
    if data.ndim == 1:
        data = np.column_stack([data, data])
    m = np.max(np.abs(data)) + 1e-9
    data = np.ascontiguousarray(data / m * peak, dtype=np.float32)
    path = os.path.join(AUD, name + ".ogg")
    # Качественное кодирование Ogg Vorbis (libvorbis -q 7, ~192 кбит/с) через ffmpeg;
    # промежуточный WAV пишем блоками (большие одноразовые записи роняют libsndfile).
    encoded = False
    try:
        import imageio_ffmpeg, subprocess, tempfile
        fd, wav = tempfile.mkstemp(suffix=".wav")
        os.close(fd)
        with sf.SoundFile(wav, "w", samplerate=SR, channels=data.shape[1], subtype="FLOAT") as f:
            step = 65536
            for i in range(0, len(data), step):
                f.write(data[i:i + step])
        cp = subprocess.run([imageio_ffmpeg.get_ffmpeg_exe(), "-y", "-v", "error", "-i", wav,
                             "-c:a", "libvorbis", "-q:a", "7", path], capture_output=True)
        os.remove(wav)
        encoded = cp.returncode == 0 and os.path.getsize(path) > 1000
    except Exception:
        encoded = False
    if not encoded:
        with sf.SoundFile(path, "w", samplerate=SR, channels=data.shape[1], format="OGG", subtype="VORBIS") as f:
            step = 65536
            for i in range(0, len(data), step):
                f.write(data[i:i + step])
    print("ogg", name, f"{len(data)/SR:.1f}s", f"{os.path.getsize(path)/1048576:.2f} MB")

def t_axis(sec):
    return np.arange(int(sec * SR)) / SR

def make_loop(data, fade_sec=1.5):
    n = int(fade_sec * SR)
    if len(data) <= n * 2:
        return data
    ramp = np.linspace(0, 1, n, dtype=np.float32)
    head = data[:n] * ramp[:, None] if data.ndim == 2 else data[:n] * ramp
    tail = data[-n:] * (1 - ramp)[:, None] if data.ndim == 2 else data[-n:] * (1 - ramp)
    body = data.copy()
    body[:n] = head + tail
    return body[:-n]

def fft_filter(x, kind, cutoff, order_roll=1.0):
    X = np.fft.rfft(x)
    f = np.fft.rfftfreq(len(x), 1 / SR)
    if kind == "low":
        g = 1.0 / (1.0 + (f / cutoff) ** (2 * order_roll * 2))
    elif kind == "high":
        g = 1.0 / (1.0 + (cutoff / np.maximum(f, 1)) ** 4)
    else:  # band
        g = np.exp(-0.5 * ((np.log(np.maximum(f, 1)) - np.log(cutoff)) / 0.5) ** 2)
    return np.fft.irfft(X * g, len(x)).astype(np.float32)

def noise_stereo(sec, seed):
    r = np.random.default_rng(seed)
    n = int(sec * SR)
    return np.column_stack([r.standard_normal(n), r.standard_normal(n)]).astype(np.float32)

def env_pulses(t, rate_hz, jitter_seed):
    r = np.random.default_rng(jitter_seed)
    base = 0.55 + 0.45 * np.sin(2 * np.pi * rate_hz * t + 0.7 * np.sin(2 * np.pi * 0.11 * t))
    return base.astype(np.float32)

def wind_tracks():
    for name, cutoff, gust_rate, hi_amt, seed in [
        ("wind_calm", 420, 0.09, 0.05, 11),
        ("wind_breeze", 750, 0.16, 0.22, 12),
        ("wind_storm", 1150, 0.3, 0.5, 13),
    ]:
        sec = 60
        t = t_axis(sec)
        raw = noise_stereo(sec, seed)
        out = np.zeros_like(raw)
        for ch in range(2):
            lo = fft_filter(raw[:, ch], "low", cutoff)
            hi = fft_filter(raw[:, ch], "band", 1400) * hi_amt
            out[:, ch] = lo + hi
        amp = env_pulses(t, gust_rate, seed + 50)
        out *= amp[:, None]
        # свистящие порывы у шторма
        if name == "wind_storm":
            whistle = np.sin(2 * np.pi * (620 + 180 * np.sin(2 * np.pi * 0.23 * t)) * t) * 0.05 * np.clip(np.sin(2 * np.pi * 0.07 * t), 0, 1)
            out += np.column_stack([whistle, whistle * 0.8]).astype(np.float32)
        save_ogg(name, make_loop(out, 2.5))

def roar_tracks():
    sec = 22
    t = t_axis(sec)
    raw = noise_stereo(sec, 21)
    out = np.zeros_like(raw)
    sweep = 300 + 240 * np.sin(2 * np.pi * 0.05 * t)
    for ch in range(2):
        lo = fft_filter(raw[:, ch], "low", 500)
        band = fft_filter(raw[:, ch], "band", 900)
        mod = (0.6 + 0.4 * np.sin(2 * np.pi * 0.11 * t + ch)).astype(np.float32)
        out[:, ch] = lo * 1.1 + band * mod
    save_ogg("suction_roar", make_loop(out, 2.0))
    sec = 32
    t = t_axis(sec)
    raw = noise_stereo(sec, 22)
    out = np.zeros_like(raw)
    for ch in range(2):
        lo = fft_filter(raw[:, ch], "low", 360)
        mid = fft_filter(raw[:, ch], "band", 700)
        out[:, ch] = lo * 1.4 + mid * (0.5 + 0.5 * np.sin(2 * np.pi * 0.31 * t + ch * 2.0))
    rumble = np.sin(2 * np.pi * 34 * t) * 0.22 * (0.6 + 0.4 * np.sin(2 * np.pi * 0.13 * t))
    out += np.column_stack([rumble, rumble]).astype(np.float32)
    save_ogg("cyclone_roar", make_loop(out, 2.5))

def flap_track():
    sec = 2.76  # 2 взмаха при ~0.72 Гц — близок к ритму крыльев в игре
    t = t_axis(sec)
    raw = noise_stereo(sec, 31)
    out = np.zeros_like(raw)
    pulse = np.clip(np.sin(2 * np.pi * 0.725 * t), 0, 1) ** 2
    for ch in range(2):
        out[:, ch] = fft_filter(raw[:, ch], "band", 520) * pulse
        out[:, ch] += fft_filter(raw[:, ch], "low", 240) * 0.5 * pulse
    save_ogg("wing_flap_loop", out)

def ambience_tracks():
    # Ночь: сверчки + сова + тихий ветер
    sec = 210
    t = t_axis(sec)
    out = np.zeros((len(t), 2), dtype=np.float32)
    raw = noise_stereo(sec, 41)
    for ch in range(2):
        out[:, ch] += fft_filter(raw[:, ch], "low", 300) * 0.16 * env_pulses(t, 0.05, 42)
    r = np.random.default_rng(43)
    for _ in range(900):  # сверчки: пакеты импульсов 4.3 кГц
        start = r.random() * (sec - 0.3)
        dur = r.uniform(0.05, 0.22)
        i0, i1 = int(start * SR), int((start + dur) * SR)
        tt = t[i0:i1] - start
        chirp = np.sin(2 * np.pi * r.uniform(4000, 4600) * tt) * np.clip(np.sin(np.pi * tt / dur), 0, 1) ** 2 * 0.05
        ch = int(r.integers(0, 2))
        out[i0:i1, ch] += chirp.astype(np.float32)
    for _ in range(14):  # сова
        start = r.random() * (sec - 2)
        for k, off in enumerate([0.0, 0.42]):
            dur = 0.3
            i0, i1 = int((start + off) * SR), int((start + off + dur) * SR)
            if i1 >= len(t):
                continue
            tt = t[i0:i1] - (start + off)
            hoot = np.sin(2 * np.pi * (340 - 40 * tt) * tt) * np.sin(np.pi * tt / dur) ** 2 * 0.14
            out[i0:i1, 0] += hoot.astype(np.float32)
            out[i0:i1, 1] += (hoot * 0.8).astype(np.float32)
    save_ogg("night_ambience", make_loop(out, 3.0))
    # День: птицы + бриз
    out = np.zeros((len(t), 2), dtype=np.float32)
    raw = noise_stereo(sec, 44)
    for ch in range(2):
        out[:, ch] += fft_filter(raw[:, ch], "band", 600) * 0.1 * env_pulses(t, 0.08, 45)
    r = np.random.default_rng(46)
    for _ in range(260):
        start = r.random() * (sec - 0.5)
        dur = r.uniform(0.08, 0.3)
        i0, i1 = int(start * SR), int((start + dur) * SR)
        tt = t[i0:i1] - start
        f0 = r.uniform(2200, 4200)
        freq = f0 * (1 + 0.25 * np.sin(2 * np.pi * r.uniform(14, 30) * tt))
        phase = 2 * np.pi * np.cumsum(freq) / SR
        chirp = np.sin(phase) * np.sin(np.pi * tt / dur) ** 1.5 * 0.075
        ch = int(r.integers(0, 2))
        out[i0:i1, ch] += chirp.astype(np.float32)
    save_ogg("day_ambience", make_loop(out, 3.0))
    # Берег водоёма
    sec = 90
    t = t_axis(sec)
    raw = noise_stereo(sec, 47)
    out = np.zeros((len(t), 2), dtype=np.float32)
    swell = (0.5 + 0.5 * np.sin(2 * np.pi * 0.09 * t)) ** 1.6
    for ch in range(2):
        out[:, ch] = fft_filter(raw[:, ch], "band", 480) * swell + fft_filter(raw[:, ch], "low", 200) * 0.3
    save_ogg("water_shore", make_loop(out, 3.0))

NOTE = {"C": 0, "C#": 1, "D": 2, "D#": 3, "E": 4, "F": 5, "F#": 6, "G": 7, "G#": 8, "A": 9, "A#": 10, "B": 11}

def freq(note, octave):
    return 440.0 * 2 ** ((NOTE[note] + (octave - 4) * 12 - 9) / 12.0)

def pluck(t, f, decay=2.2, harmonics=(1.0, 0.45, 0.18, 0.06)):
    y = np.zeros_like(t)
    for i, a in enumerate(harmonics):
        y += a * np.sin(2 * np.pi * f * (i + 1) * t) * np.exp(-decay * (1 + i * 0.7) * t)
    return y.astype(np.float32)

def pad(t, freqs, attack=3.0):
    y = np.zeros_like(t)
    for f in freqs:
        for det in (-2.5, 0.0, 2.5):
            tt = t * (1 + det / 100000.0)
            y += (np.sin(2 * np.pi * f * tt) + 0.4 * np.sin(2 * np.pi * f * 2 * tt) + 0.15 * np.sin(2 * np.pi * f * 3 * tt)) / 3
    env = np.clip(t / attack, 0, 1) * np.clip((t[-1] - t) / attack, 0, 1)
    return (y * env / max(len(freqs), 1)).astype(np.float32)

def add_note(out, t, start, f, dur, vol, pan=0.5, kind="pluck", decay=2.2):
    i0 = int(start * SR)
    i1 = min(len(t), int((start + dur) * SR))
    if i0 >= i1:
        return
    tt = t[i0:i1] - start
    if kind == "pluck":
        y = pluck(tt, f, decay)
    elif kind == "box":  # музыкальная шкатулка
        y = (np.sin(2 * np.pi * f * tt) + 0.35 * np.sin(2 * np.pi * f * 3.01 * tt) + 0.12 * np.sin(2 * np.pi * f * 5.7 * tt)) * np.exp(-3.4 * tt)
    else:  # флейта
        vib = 1 + 0.004 * np.sin(2 * np.pi * 5.2 * tt)
        y = np.sin(2 * np.pi * f * vib * tt) * np.clip(tt * 6, 0, 1) * np.clip((dur - tt) * 4, 0, 1)
    y = (y * vol).astype(np.float32)
    out[i0:i1, 0] += y * np.sqrt(1 - pan)
    out[i0:i1, 1] += y * np.sqrt(pan)

def add_pad(out, t, start, dur, freqs, vol):
    i0 = int(start * SR)
    i1 = min(len(t), int((start + dur) * SR))
    if i0 >= i1:
        return
    tt = t[i0:i1] - start
    y = pad(tt, freqs, attack=min(3.0, dur / 3))
    out[i0:i1, 0] += (y * vol).astype(np.float32)
    out[i0:i1, 1] += (y * vol * 0.96).astype(np.float32)

def music_tracks():
    # Меню: медленное минорное арпеджио + пэды
    sec = 180
    t = t_axis(sec)
    out = np.zeros((len(t), 2), dtype=np.float32)
    chords = [[("A", 2), ("A", 3), ("C", 4), ("E", 4)], [("F", 2), ("F", 3), ("A", 3), ("C", 4)],
              [("D", 2), ("D", 3), ("F", 3), ("A", 3)], [("E", 2), ("E", 3), ("G#", 3), ("B", 3)]]
    bar = 6.0
    for i in range(int(sec / bar)):
        ch = chords[i % 4]
        start = i * bar
        add_pad(out, t, start, bar * 1.15, [freq(n, o) for n, o in ch[:3]], 0.16)
        for k in range(8):
            n, o = ch[k % 4]
            add_note(out, t, start + k * bar / 8, freq(n, o + (1 if k >= 4 else 0)), 1.6, 0.13, 0.3 + 0.4 * (k % 2))
    save_ogg("music_menu", make_loop(out, 3.0))
    # Тёмный хоррор-эмбиент: диссонирующие пэды и редкие глубокие ноты
    sec = 210
    t = t_axis(sec)
    out = np.zeros((len(t), 2), dtype=np.float32)
    dark_chords = [[("D", 2), ("D", 3), ("F", 3), ("G#", 3)], [("D", 2), ("A#", 2), ("D", 3), ("F", 3)],
                   [("C", 2), ("C", 3), ("D#", 3), ("G", 3)], [("A#", 1), ("A#", 2), ("D", 3), ("F#", 3)]]
    bar = 12.0
    for i in range(int(sec / bar)):
        ch = dark_chords[i % 4]
        add_pad(out, t, i * bar, bar * 1.25, [freq(n, o) for n, o in ch], 0.14)
    r = np.random.default_rng(88)
    for _ in range(26):
        start = r.random() * (sec - 4)
        n, o = [("D", 2), ("F", 2), ("G#", 2), ("A#", 1), ("C", 3)][int(r.integers(0, 5))]
        add_note(out, t, start, freq(n, o), 3.5, 0.16, r.random(), decay=1.1)
    raw = noise_stereo(sec, 89)
    for chn in range(2):
        out[:, chn] += fft_filter(raw[:, chn], "low", 220) * 0.05 * env_pulses(t, 0.045, 90)
    save_ogg("music_dark_ambient", make_loop(out, 4.0))
    # Няшинг: колыбельная музыкальной шкатулки (пентатоника)
    sec = 210
    t = t_axis(sec)
    out = np.zeros((len(t), 2), dtype=np.float32)
    melody = [("E", 5), ("G", 5), ("A", 5), ("G", 5), ("E", 5), ("D", 5), ("C", 5), ("D", 5),
              ("E", 5), ("G", 5), ("A", 5), ("C", 6), ("A", 5), ("G", 5), ("E", 5), ("D", 5),
              ("C", 5), ("D", 5), ("E", 5), ("G", 5), ("E", 5), ("D", 5), ("C", 5), ("A", 4),
              ("C", 5), ("D", 5), ("E", 5), ("D", 5), ("C", 5), ("A", 4), ("G", 4), ("A", 4)]
    step = 0.62
    harmony = [[("C", 3), ("E", 3), ("G", 3)], [("F", 3), ("A", 3), ("C", 4)], [("A", 2), ("C", 3), ("E", 3)], [("G", 2), ("B", 2), ("D", 3)]]
    pos = 0.5
    idx = 0
    while pos < sec - 2:
        if idx % 8 == 0:
            add_pad(out, t, pos, step * 9, [freq(n, o) for n, o in harmony[(idx // 8) % 4]], 0.07)
        n, o = melody[idx % len(melody)]
        add_note(out, t, pos, freq(n, o), 1.6, 0.16, 0.5, kind="box")
        if idx % 4 == 2:
            add_note(out, t, pos + step * 0.5, freq(n, o) * 2, 0.9, 0.05, 0.62, kind="box")
        pos += step
        idx += 1
    save_ogg("music_nyashing", make_loop(out, 3.0))
    # Полёт: воздушные мажорные пэды и флейтовая мелодия
    sec = 180
    t = t_axis(sec)
    out = np.zeros((len(t), 2), dtype=np.float32)
    fly_chords = [[("C", 3), ("E", 3), ("G", 3)], [("G", 2), ("B", 2), ("D", 3)], [("A", 2), ("C", 3), ("E", 3)], [("F", 2), ("A", 2), ("C", 3)]]
    bar = 10.0
    for i in range(int(sec / bar)):
        add_pad(out, t, i * bar, bar * 1.2, [freq(n, o) for n, o in fly_chords[i % 4]], 0.13)
    flute_mel = [("G", 5), ("A", 5), ("C", 6), ("B", 5), ("A", 5), ("G", 5), ("E", 5), ("D", 5), ("E", 5), ("G", 5)]
    pos = 3.0
    idx = 0
    r = np.random.default_rng(91)
    while pos < sec - 4:
        n, o = flute_mel[idx % len(flute_mel)]
        dur = r.uniform(0.9, 1.8)
        add_note(out, t, pos, freq(n, o), dur, 0.11, 0.5, kind="flute")
        pos += dur + r.uniform(0.15, 0.7)
        idx += 1
    save_ogg("music_fly", make_loop(out, 3.0))

def sfx_tracks():
    # Боинги надувных поверхностей
    for i, f0 in enumerate([210, 250, 180], 1):
        sec = 0.55
        t = t_axis(sec)
        fcurve = f0 * (0.55 + 0.45 * np.exp(-9 * t)) * (1 + 0.5 * np.sin(2 * np.pi * 7 * t) * np.exp(-6 * t))
        phase = 2 * np.pi * np.cumsum(fcurve) / SR
        y = (np.sin(phase) + 0.4 * np.sin(2 * phase)) * np.exp(-5.5 * t)
        save_ogg(f"boing_{i}", y.astype(np.float32))
    # Скрипы ПВХ (ЧМ-рывки)
    r = np.random.default_rng(77)
    for i in range(1, 5):
        sec = float(r.uniform(0.2, 0.4))
        t = t_axis(sec)
        f0 = r.uniform(700, 1500)
        mod = r.uniform(25, 55)
        carrier = f0 * (1 + r.uniform(-0.4, 0.7) * t / sec)
        y = np.sin(2 * np.pi * carrier * t + 5.5 * np.sin(2 * np.pi * mod * t)) * np.sin(np.pi * t / sec) ** 1.5
        y += 0.3 * np.sin(2 * np.pi * carrier * 2.02 * t) * np.sin(np.pi * t / sec)
        save_ogg(f"pvc_squeak_{i}", y.astype(np.float32))
    # Шаги
    for i in (1, 2):
        sec = 0.11
        t = t_axis(sec)
        raw = noise_stereo(sec, 60 + i)
        y = fft_filter(raw[:, 0], "low", 380) * np.exp(-38 * t) + 0.6 * np.sin(2 * np.pi * 68 * t) * np.exp(-30 * t)
        save_ogg(f"step_soft_{i}", y.astype(np.float32))
    # Всплеск
    sec = 0.8
    t = t_axis(sec)
    raw = noise_stereo(sec, 66)
    y = fft_filter(raw[:, 0], "band", 900) * np.exp(-5 * t) + fft_filter(raw[:, 0], "low", 300) * 0.6 * np.exp(-8 * t)
    for k in range(6):
        s0 = 0.25 + k * 0.08
        i0, i1 = int(s0 * SR), int((s0 + 0.06) * SR)
        tt = t[i0:i1] - s0
        y[i0:i1] += 0.24 * np.sin(2 * np.pi * (1200 - 5000 * tt) * tt) * np.exp(-40 * tt)
    save_ogg("splash", y.astype(np.float32))
    # Скрип верёвки
    sec = 0.85
    t = t_axis(sec)
    fcurve = 95 + 55 * np.sin(np.pi * t / sec) ** 2
    y = np.sin(2 * np.pi * fcurve * t + 3.0 * np.sin(2 * np.pi * 13 * t)) * np.sin(np.pi * t / sec)
    raw = noise_stereo(sec, 67)
    y += 0.35 * fft_filter(raw[:, 0], "band", 500) * np.sin(np.pi * t / sec)
    save_ogg("rope_creak", y.astype(np.float32))
    # Шипение врат (надув)
    sec = 1.7
    t = t_axis(sec)
    raw = noise_stereo(sec, 68)
    env = np.sin(np.pi * t / sec) ** 1.2
    y = fft_filter(raw[:, 0], "band", 2400) * env + 0.5 * fft_filter(raw[:, 0], "high", 3500) * env
    save_ogg("gate_hiss", y.astype(np.float32))
    # Гром
    for i in (1, 2):
        sec = 3.6
        t = t_axis(sec)
        raw = noise_stereo(sec, 70 + i)
        y = fft_filter(raw[:, 0], "low", 180) * np.exp(-1.4 * t)
        y += fft_filter(raw[:, 0], "band", 1200) * 0.8 * np.exp(-14 * t)
        y *= 0.75 + 0.25 * np.sin(2 * np.pi * 0.7 * t + 1)
        save_ogg(f"thunder_{i}", y.astype(np.float32))
    # Волшебный перезвон
    sec = 1.4
    t = t_axis(sec)
    out = np.zeros((len(t), 2), dtype=np.float32)
    for k, (n, o) in enumerate([("E", 6), ("G", 6), ("A", 6), ("C", 7), ("E", 7)]):
        add_note(out, t, k * 0.09, freq(n, o), 1.1, 0.14, 0.35 + k * 0.07, kind="box")
    save_ogg("chime_magic", out)
    # Сердцебиение
    sec = 1.9
    t = t_axis(sec)
    y = np.zeros(len(t), dtype=np.float32)
    for beat in (0.05, 0.34, 1.02, 1.31):
        i0, i1 = int(beat * SR), int((beat + 0.22) * SR)
        tt = t[i0:i1] - beat
        y[i0:i1] += np.sin(2 * np.pi * 52 * tt) * np.exp(-16 * tt) * (1.0 if beat in (0.05, 1.02) else 0.7)
    save_ogg("heartbeat", y)
    # Мягкий храп/сонное дыхание
    sec = 2.2
    t = t_axis(sec)
    raw = noise_stereo(sec, 72)
    breath = np.sin(np.pi * t / sec) ** 2
    y = fft_filter(raw[:, 0], "band", 420) * breath * (0.8 + 0.3 * np.sin(2 * np.pi * 28 * t) * breath)
    save_ogg("snore_soft", y.astype(np.float32))

def main():
    global SCALE
    ap = argparse.ArgumentParser()
    ap.add_argument("--scale", type=float, default=1.0)
    args = ap.parse_args()
    SCALE = args.scale
    tex_grass()
    tex_rock()
    tex_sand_snow()
    tex_pvc("pvc_darkred", (0.12, 0.005, 0.02), (0.38, 0.03, 0.06), (0.62, 0.12, 0.14), 4096, 410)  # главный объект игры
    tex_pvc("pvc_white", (0.72, 0.7, 0.68), (0.9, 0.88, 0.86), (1.0, 0.99, 0.97), 2048, 420)
    tex_pvc("pvc_pink", (0.7, 0.3, 0.4), (0.92, 0.5, 0.6), (1.0, 0.72, 0.8), 1024, 430, extra_maps=False)
    tex_laces()
    tex_fabrics()
    tex_water_sky()
    tex_face()
    tex_menu_and_icon()
    wind_tracks()
    roar_tracks()
    flap_track()
    ambience_tracks()
    music_tracks()
    sfx_tracks()
    total = 0
    for base in (TEX, AUD):
        for f in os.listdir(base):
            total += os.path.getsize(os.path.join(base, f))
    print(f"ASSETS TOTAL: {total / 1048576:.1f} MB")

if __name__ == "__main__":
    main()
