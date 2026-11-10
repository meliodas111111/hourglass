#!/usr/bin/env python3
"""
Generates bundled resources with no third-party dependencies:
  • App/Resources/Sounds/{chime,bell,gong,marimba}.wav — synthesized alert sounds (< 30 s, notification-safe)
  • App/Resources/Assets.xcassets — AppIcon (1024 px, rendered hourglass), AccentColor, LaunchBackground

    python3 Tools/generate_assets.py
Replace the icon with a designer-made one before release.
"""
import json
import math
import pathlib
import random
import struct
import wave
import zlib

ROOT = pathlib.Path(__file__).resolve().parent.parent
RES = ROOT / "App/Resources"
RATE = 44100


# ───────────────────────────────────────── sounds

def write_wav(path, samples):
    path.parent.mkdir(parents=True, exist_ok=True)
    peak = max(1e-9, max(abs(s) for s in samples))
    with wave.open(str(path), "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(RATE)
        w.writeframes(b"".join(struct.pack("<h", int(32767 * 0.85 * s / peak)) for s in samples))


def tone(partials, seconds, decay, attack=0.004, repeat_every=None, repeats=1):
    n = int(seconds * RATE)
    out = [0.0] * n
    for r in range(repeats):
        offset = int((repeat_every or 0) * r * RATE)
        for i in range(n - offset):
            t = i / RATE
            env = min(1.0, t / attack) * math.exp(-t * decay)
            v = sum(a * math.sin(2 * math.pi * f * t) * math.exp(-t * d) for f, a, d in partials)
            out[i + offset] += v * env
    return out


def make_sounds():
    snd = RES / "Sounds"
    # Bright two-note chime, played 3 times.
    write_wav(snd / "chime.wav", tone([(1318.5, 1, 1.2), (1975.5, .5, 2.0), (2637, .2, 3.0)], 4.0, 1.4, repeat_every=1.2, repeats=3))
    # Church-bell like inharmonic partials.
    write_wav(snd / "bell.wav", tone([(523.25, 1, .6), (1250, .6, 1.0), (1650, .4, 1.4), (2093, .25, 2.0), (2900, .1, 3.0)], 6.0, .5,
                                     repeat_every=2.0, repeats=3))
    # Deep gong.
    write_wav(snd / "gong.wav", tone([(98, 1, .25), (147, .6, .35), (233, .4, .5), (311, .3, .7), (440, .15, 1.0)], 8.0, .35, attack=.02))
    # Marimba arpeggio.
    notes = [523.25, 659.25, 783.99, 1046.5]
    out = [0.0] * int(4.0 * RATE)
    for k, f in enumerate(notes * 2):
        start = int(k * 0.18 * RATE)
        for i in range(int(0.9 * RATE)):
            if start + i >= len(out):
                break
            t = i / RATE
            out[start + i] += (math.sin(2 * math.pi * f * t) + .3 * math.sin(2 * math.pi * 4 * f * t) * math.exp(-t * 30)) * math.exp(-t * 6)
    write_wav(snd / "marimba.wav", out)


# ───────────────────────────────────────── png

def write_png(path, w, h, pixel):
    raw = bytearray()
    for y in range(h):
        raw.append(0)
        for x in range(w):
            raw.extend(pixel(x, y))
    def chunk(tag, data):
        return struct.pack(">I", len(data)) + tag + data + struct.pack(">I", zlib.crc32(tag + data) & 0xFFFFFFFF)
    png = b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", struct.pack(">IIBBBBB", w, h, 8, 2, 0, 0, 0))
    png += chunk(b"IDAT", zlib.compress(bytes(raw), 9)) + chunk(b"IEND", b"")
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_bytes(png)


def profile(u):
    u0 = 0.85
    if u <= u0:
        return math.sin(math.pi / 2 * u / u0)
    t = (u - u0) / (1 - u0)
    return 1 - 0.22 * t * t


def half_width(v):
    neck, maxh, rows = 0.02, 0.44, 0.01
    d = abs(v - 0.5)
    if d <= rows:
        return neck
    return neck + (maxh - neck) * profile(min(1, (d - rows) / (0.5 - rows)))


def make_icon():
    size = 1024
    rnd = random.Random(3)
    sand = [(184, 134, 47), (212, 164, 67), (230, 190, 98), (242, 213, 140)]
    noise = [[rnd.random() for _ in range(256)] for _ in range(256)]
    hg_w, hg_h = 0.50, 0.80          # hourglass box relative to the icon
    top, left = (1 - hg_h) / 2, (1 - hg_w) / 2
    cap = 0.05

    def pixel(x, y):
        nx, ny = x / size, y / size
        # Background radial gradient.
        r = math.hypot(nx - 0.5, ny - 0.45)
        bg = (int(40 + 60 * (1 - r)), int(30 + 40 * (1 - r)), int(60 + 50 * (1 - r)))
        lx, ly = (nx - left) / hg_w, (ny - top) / hg_h
        if not (0 <= lx <= 1 and 0 <= ly <= 1):
            return bytes(max(0, min(255, c)) for c in bg)
        if ly < cap or ly > 1 - cap:
            if abs(lx - 0.5) < 0.49:
                t = ly / cap if ly < cap else (1 - ly) / cap
                k = 0.65 + 0.35 * min(1, t / 0.45)
                return bytes(int(c * k) for c in (128, 79, 43))
            return bytes(bg)
        if 0.462 < abs(lx - 0.5) < 0.484:
            a = (abs(lx - 0.5) - 0.462) / 0.022
            k = 0.65 + 0.45 * math.sin(a * math.pi)
            return bytes(min(255, int(c * k)) for c in (128, 79, 43))
        v = (ly - cap) / (1 - 2 * cap)
        hw = half_width(v)
        dx = abs(lx - 0.5)
        if dx < hw:
            col = [int(c * 0.6 + 12) for c in bg]
            # Sand: 30 % left on top (near the neck), pile at the bottom, a thin stream.
            in_top = 0.33 < v < 0.5
            pile = v > 0.70 + 0.12 * (dx / 0.44) ** 0.9
            stream = 0.5 <= v < 0.78 and dx < 0.012
            if in_top or pile or stream:
                c = sand[int(noise[y % 256][x % 256] * 4) % 4]
                k = 0.92 + 0.16 * noise[(y * 7) % 256][(x * 3) % 256]
                col = [min(255, int(ch * k)) for ch in c]
            # Highlight streak.
            hx = (lx - 0.5) / hw
            s = math.exp(-((hx + 0.58) / 0.07) ** 2) * 0.35
            col = [min(255, int(ch * (1 - s) + 255 * s)) for ch in col]
            return bytes(col)
        if dx < hw + 0.012:
            return bytes(min(255, int(c * 0.4 + 150)) for c in bg)
        return bytes(bg)

    write_png(RES / "Assets.xcassets/AppIcon.appiconset/AppIcon.png", size, size, pixel)


def write_json(path, obj):
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(obj, indent=2) + "\n", encoding="utf-8")


def make_catalog():
    a = RES / "Assets.xcassets"
    write_json(a / "Contents.json", {"info": {"author": "xcode", "version": 1}})
    write_json(a / "AppIcon.appiconset/Contents.json", {
        "images": [{"filename": "AppIcon.png", "idiom": "universal", "platform": "ios", "size": "1024x1024"}],
        "info": {"author": "xcode", "version": 1}})

    def color(name, r, g, b):
        write_json(a / f"{name}.colorset/Contents.json", {
            "colors": [{"color": {"color-space": "srgb", "components": {
                "red": f"{r:.3f}", "green": f"{g:.3f}", "blue": f"{b:.3f}", "alpha": "1.000"}}, "idiom": "universal"}],
            "info": {"author": "xcode", "version": 1}})
    color("AccentColor", 0.902, 0.745, 0.384)
    color("LaunchBackground", 0.0, 0.0, 0.0)


if __name__ == "__main__":
    make_sounds()
    make_catalog()
    make_icon()
    print("assets generated")
