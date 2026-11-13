#!/usr/bin/env python3
"""Preview of Arcanum's HUD: composites the addon's real textures following the layout in UI/Hud.lua.

Three scenes: in combat (procs on either side of the character, charges above), out of combat (reminders
below the character), and the active buffs (Presence of Mind, Eureka, Arcane Power).

This is not a game screenshot: spell icons and text are replaced by flat colour blocks.
It is for judging shapes, colours and glows without launching WoW. No dependencies.
The proc backdrop (the rune arc, an image from the game) is not shown.
Usage: python tools/preview.py   ->   docs/preview.png
"""
import math
import os
import struct
import zlib

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
MEDIA = os.path.join(ROOT, "Arcanum", "Media")
OUT = os.path.join(ROOT, "docs", "preview.png")

K = 2.0                      # render scale
W, H = int(960 * K), int(400 * K)

C = dict(
    ink=(0.030, 0.024, 0.066), socket=(0.130, 0.108, 0.240), edge=(0.470, 0.380, 0.860),
    arcane=(0.690, 0.486, 1.000), arcaneHi=(0.900, 0.820, 1.000), hot=(0.870, 0.790, 1.000),
    barrage=(1.000, 0.450, 0.800), clear=(0.400, 0.860, 1.000), power=(1.000, 0.800, 0.400),
    pom=(0.560, 1.000, 0.840), heat=(1.000, 0.560, 0.240), mana=(0.340, 0.560, 1.000),
    text=(0.950, 0.930, 1.000), white=(1, 1, 1),
)

_cache = {}


def tga(name):
    if name in _cache:
        return _cache[name]
    data = open(os.path.join(MEDIA, name + ".tga"), "rb").read()
    w, h = struct.unpack("<HH", data[12:16])
    px = data[18:18 + w * h * 4]
    _cache[name] = (w, h, px)
    return _cache[name]


buf = [0.0] * (W * H * 3)


def background():
    for y in range(H):
        for x in range(W):
            u, v = x / W, y / H
            d = math.hypot(u - 0.5, v - 0.45)
            base = 0.085 - 0.05 * d
            i = (y * W + x) * 3
            buf[i], buf[i + 1], buf[i + 2] = base * 0.95, base * 1.0, base * 1.25


def blit(name, cx, cy, w, h, color, alpha=1.0, add=False, uv=(0, 1, 0, 1), rot=0.0, sweep=None):
    """Draws a texture centred on (cx, cy), size (w, h) in HUD units (y points down)."""
    if name is None:
        tw = th = 1
        px = None
    else:
        tw, th, px = tga(name)
    x0, y0 = (cx - w / 2) * K, (cy - h / 2) * K
    pw, ph = w * K, h * K
    u0, u1, v0, v1 = uv
    r, g, b = color
    for y in range(max(0, int(y0)), min(H, int(y0 + ph) + 1)):
        fy0 = (y + 0.5 - y0) / ph
        if fy0 < 0 or fy0 > 1:
            continue
        for x in range(max(0, int(x0)), min(W, int(x0 + pw) + 1)):
            fx = (x + 0.5 - x0) / pw
            fy = fy0
            if fx < 0 or fx > 1:
                continue
            if sweep is not None:
                # remaining arc, like the swipe of a Cooldown widget: starts at the top, clockwise
                ang = math.atan2(fx - 0.5, 0.5 - fy) % (2 * math.pi)
                if ang < (1 - sweep) * 2 * math.pi:
                    continue
            if rot:
                dx, dy = fx - 0.5, fy - 0.5
                fx = 0.5 + dx * math.cos(rot) + dy * math.sin(rot)
                fy = 0.5 - dx * math.sin(rot) + dy * math.cos(rot)
                if fx < 0 or fx > 1 or fy < 0 or fy > 1:
                    continue
            if px is None:
                tr = tg = tb = ta = 1.0
            else:
                gx = min(tw - 1.0, max(0.0, (u0 + (u1 - u0) * fx) * tw - 0.5))
                gy = min(th - 1.0, max(0.0, (v0 + (v1 - v0) * fy) * th - 0.5))
                ix, iy = int(gx), int(gy)
                jx, jy = min(tw - 1, ix + 1), min(th - 1, iy + 1)
                wx, wy = gx - ix, gy - iy
                tb = tg = tr = ta = 0.0
                for (qx, qy, wgt) in ((ix, iy, (1 - wx) * (1 - wy)), (jx, iy, wx * (1 - wy)),
                                      (ix, jy, (1 - wx) * wy), (jx, jy, wx * wy)):
                    o = (qy * tw + qx) * 4
                    al = px[o + 3] / 255 * wgt
                    tb += px[o] / 255 * al
                    tg += px[o + 1] / 255 * al
                    tr += px[o + 2] / 255 * al
                    ta += al
                if ta > 0:
                    tb, tg, tr = tb / ta, tg / ta, tr / ta
            a = ta * alpha
            if a <= 0:
                continue
            i = (y * W + x) * 3
            if add:
                buf[i] += tr * r * a
                buf[i + 1] += tg * g * a
                buf[i + 2] += tb * b * a
            else:
                buf[i] = buf[i] * (1 - a) + tr * r * a
                buf[i + 1] = buf[i + 1] * (1 - a) + tg * g * a
                buf[i + 2] = buf[i + 2] * (1 - a) + tb * b * a


def mix(a, b, t):
    return tuple(a[i] + (b[i] - a[i]) * t for i in range(3))


def round_icon(cx, cy, size, tint, ring, glow=0.0, cooldown=0.0):
    if glow:
        blit("glow", cx, cy, size * 2.0, size * 2.0, ring, glow, add=True)
    blit("circle", cx, cy, size + 4, size + 4, C["ink"], 0.96)
    blit("circle", cx, cy, size, size, mix(tint, C["ink"], 0.42 + 0.3 * cooldown), 1)
    blit("glow", cx - size * 0.12, cy - size * 0.14, size * 0.9, size * 0.9, mix(tint, C["white"], 0.5), 0.5 * (1 - cooldown), add=True)
    if cooldown > 0:
        blit("circle", cx, cy, size, size, (0.02, 0.01, 0.06), 0.76, sweep=cooldown)
    blit("circle-edge", cx, cy, size + 4, size + 4, ring, 0.95)


def scene(cx, cy, stacks=0, target=2, window=0.0, clear=None, barrage=None, pom=False, reminders=0, spread=110):
    """The four zones around the character, as laid out by UI/Hud.lua (with a reduced spread)."""
    # the character (a silhouette: it is not part of the HUD)
    body = (0.16, 0.15, 0.24)
    blit("circle", cx, cy + 62, 76, 16, (0.08, 0.07, 0.14), 0.9)
    blit("roundsq", cx, cy + 22, 40, 62, body, 0.95)
    blit("circle", cx, cy - 24, 30, 30, body, 0.95)
    # procs: Clearcasting on the left, Missile Barrage on the right (time left shown as a swipe)
    for side, proc, col in ((-1, clear, C["clear"]), (1, barrage, C["barrage"])):
        if proc is not None:
            round_icon(cx + side * spread, cy, 64, col, col, glow=0.40, cooldown=1 - proc)
    # charges: one crystal per target charge (one more when the game grants an extra), and their window bar
    top = cy - spread * 0.9
    full = stacks >= target
    col = C["hot"] if full else C["arcane"]
    full = stacks >= 4
    col = C["hot"] if full else C["arcane"]
    shown = stacks   # one crystal per charge
    if stacks > 0:   # (no charges: no crystals)
        for i in range(shown):
            x = cx + (i + 1 - (shown + 1) / 2) * 32
            on = i < stacks
            if on:
                blit("glow", x, top, 26 * 3, 34 * 2.6, col, 0.65 if full else 0.40, add=True)
            blit("diamond", x, top, 26, 34, C["socket"], 0.95)
            if on:
                blit("diamond", x, top, 26, 34, col, 1)
                blit("spark", x - 5, top - 7, 20, 20, C["white"], 0.85 if full else 0.5, add=True)
            blit("diamond-edge", x, top, 26, 34, C["arcaneHi"] if on else C["edge"], 1 if on else 0.45)
    if stacks > 0:
        by = top + 17 + 10
        blit(None, cx, by, 126, 6, C["socket"], 0.90)
        blit(None, cx - 62 + 124 * window / 2, by, 124 * window, 4, col, 1)
        blit(None, cx + 62 + 16, by, 14, 7, mix(C["text"], C["ink"], 0.35), 0.9)   # seconds (flat block)
    # active buffs (Presence of Mind, Eureka, Arcane Power): their icons side by side, above the charges
    if pom:
        round_icon(cx - 56, top - 17 - 23 - 12, 46, C["pom"], C["pom"], glow=0.50)
        round_icon(cx, top - 17 - 23 - 12, 46, C["power"], C["power"], glow=0.50, cooldown=0.35)
        round_icon(cx + 56, top - 17 - 23 - 12, 46, C["arcane"], C["arcane"], glow=0.50, cooldown=0.15)
    # pre-combat reminders, below the character
    amber = (1.000, 0.700, 0.300)
    for i in range(reminders):
        x = cx + (i + 1 - (reminders + 1) / 2) * 38
        round_icon(x, cy + spread, 30, mix(amber, C["ink"], 0.2), amber, glow=0.45)


def main():
    background()
    # in combat, two procs and three charges out of four; out of combat, three reminders; the three buffs active
    scene(200, 215, stacks=3, target=4, window=0.62, clear=0.6, barrage=0.85)
    scene(480, 215, reminders=3)
    scene(790, 215, stacks=4, target=4, window=0.45, pom=True)

    save(OUT)


def save(out):
    os.makedirs(os.path.dirname(out), exist_ok=True)
    raw = bytearray()
    for y in range(H):
        raw.append(0)
        for x in range(W):
            i = (y * W + x) * 3
            for c in range(3):
                v = buf[i + c]
                raw.append(255 if v >= 1 else int(max(0.0, v) ** (1 / 1.0) * 255))

    def chunk(kind, data):
        body = kind + data
        return struct.pack(">I", len(data)) + body + struct.pack(">I", zlib.crc32(body) & 0xFFFFFFFF)

    png = b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", struct.pack(">IIBBBBB", W, H, 8, 2, 0, 0, 0))
    png += chunk(b"IDAT", zlib.compress(bytes(raw), 9)) + chunk(b"IEND", b"")
    with open(out, "wb") as f:
        f.write(png)
    print("Preview written: " + out)


if __name__ == "__main__":
    main()
