#!/usr/bin/env python3
"""Generates Arcanum's textures (32-bit TGA) in Arcanum/Media.

No dependencies: shapes are rasterised with the primitives in shapes.py (4x4 supersampling).
The textures are white (tinted in game), except the logo.
Usage: python tools/make_media.py
"""
import math
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import shapes as mm  # noqa: E402

mm.OUT = os.path.join(os.path.dirname(HERE), "Arcanum", "Media")

DIAMOND = [(0.5, 0.03), (0.88, 0.5), (0.5, 0.97), (0.12, 0.5)]


def shrink(pts, k, cx=0.5, cy=0.5):
    return [(cx + (x - cx) * k, cy + (y - cy) * k) for x, y in pts]


def grey(cov, level=1.0):
    v = int(round(255 * level))
    return [(v, v, v, int(round(c * 255))) for c in cov]


def make_diamond():
    """Charge crystal: four facets of different brightness, for depth once tinted."""
    S = 64
    top, right, bottom, left = DIAMOND
    mid = (0.5, 0.5)
    facets = [
        (mm.poly([top, mid, left]), 1.00),     # top left: the brightest
        (mm.poly([top, right, mid]), 0.80),
        (mm.poly([left, mid, bottom]), 0.66),
        (mm.poly([mid, right, bottom]), 0.50),  # bottom right: the darkest
    ]
    covs = [(mm.coverage(S, S, f), lvl) for f, lvl in facets]
    px = []
    for i in range(S * S):
        a = sum(c[i] for c, _ in covs)
        if a <= 0:
            px.append((255, 255, 255, 0))
            continue
        lvl = sum(c[i] * l for c, l in covs) / a
        v = int(round(255 * lvl))
        px.append((v, v, v, int(round(mm.clamp(a) * 255))))
    mm.write_tga("diamond", S, S, px)
    edge = mm.sub(mm.poly(DIAMOND), mm.poly(shrink(DIAMOND, 0.80)))
    mm.write_tga("diamond-edge", S, S, mm.white(mm.coverage(S, S, edge)))


def make_glow():
    S = 64   # soft gradient: the game scales it up with no visible loss
    px = []
    for y in range(S):
        for x in range(S):
            d = math.hypot((x + 0.5) / S - 0.5, (y + 0.5) / S - 0.5) * 2
            a = mm.clamp(1 - d) ** 2.2
            px.append((255, 255, 255, int(round(a * 255))))
    mm.write_tga("glow", S, S, px)


def make_halo():
    """Diffuse ring: a wave that expands when a proc fires."""
    S = 64
    px = []
    for y in range(S):
        for x in range(S):
            d = math.hypot((x + 0.5) / S - 0.5, (y + 0.5) / S - 0.5) * 2
            a = math.exp(-((d - 0.78) / 0.085) ** 2)
            px.append((255, 255, 255, int(round(mm.clamp(a) * 255))))
    mm.write_tga("halo", S, S, px)


def make_roundsq():
    S = 64
    full = mm.rrect(0, 0, 1, 1, 0.24)
    mm.write_tga("roundsq", S, S, mm.white(mm.coverage(S, S, full)))



def make_circle():
    mm.write_tga("circle", 64, 64, mm.white(mm.coverage(64, 64, mm.circle(0.5, 0.5, 0.5))))


def make_fade():
    """Horizontal gradient, transparent → opaque (divider lines in the settings)."""
    w, h = 128, 8
    px = [(255, 255, 255, int(round(255 * ((x + 0.5) / w) ** 1.4))) for y in range(h) for x in range(w)]
    mm.write_tga("grad-h", w, h, px)


def make_spark():
    """Four-pointed spark."""
    S = 64
    px = []
    for y in range(S):
        for x in range(S):
            u, v = (x + 0.5) / S - 0.5, (y + 0.5) / S - 0.5
            d = math.hypot(u, v) * 2
            core = math.exp(-(d / 0.16) ** 2)
            ray = math.exp(-(abs(u) / 0.022) ** 2) * mm.clamp(1 - abs(v) * 2.1) ** 1.5
            ray += math.exp(-(abs(v) / 0.022) ** 2) * mm.clamp(1 - abs(u) * 2.1) ** 1.5
            px.append((255, 255, 255, int(round(mm.clamp(core + ray) * 255))))
    mm.write_tga("spark", S, S, px)


def make_logo():
    S = 64
    bg = mm.coverage(S, S, mm.rrect(0, 0, 1, 1, 0.22))
    gem = mm.coverage(S, S, mm.poly(shrink(DIAMOND, 0.66)))
    facet = mm.coverage(S, S, mm.poly([shrink(DIAMOND, 0.66)[0], (0.5, 0.5), shrink(DIAMOND, 0.66)[3]]))
    px = []
    for y in range(S):
        for x in range(S):
            i = y * S + x
            u, v = (x + 0.5) / S, (y + 0.5) / S
            d = math.hypot(u - 0.5, v - 0.5) * 2
            t = mm.clamp(1 - d) ** 1.3
            base = (int(18 + 70 * t), int(12 + 30 * t), int(40 + 110 * t))
            g = gem[i]
            lit = (236, 214, 255) if facet[i] > 0.5 else (176, 124, 255)
            r = base[0] * (1 - g) + lit[0] * g
            gg = base[1] * (1 - g) + lit[1] * g
            b = base[2] * (1 - g) + lit[2] * g
            px.append((int(r), int(gg), int(b), int(round(bg[i] * 255))))
    mm.write_tga("logo", S, S, px)


def polar_tex(name, size, inside, ss=3):
    """White texture defined in polar coordinates: inside(r, angle, u, v) -> bool, r in [0, 0.5]."""
    px = []
    inv = 1.0 / (ss * ss)
    for y in range(size):
        for x in range(size):
            c = 0
            for sy in range(ss):
                v = (y + (sy + 0.5) / ss) / size - 0.5
                for sx in range(ss):
                    u = (x + (sx + 0.5) / ss) / size - 0.5
                    if inside(math.hypot(u, v), math.atan2(v, u), u, v):
                        c += 1
            px.append(c * inv)
    mm.write_tga(name, size, size, [(255, 255, 255, int(round(v * 255))) for v in px])


def make_edge():
    """Border of the round icons."""
    polar_tex("circle-edge", 64, lambda r, a, u, v: 0.43 <= r <= 0.5, ss=4)


def main():
    make_edge()
    make_diamond()
    make_glow()
    make_halo()
    make_roundsq()
    make_circle()
    make_fade()
    make_spark()
    make_logo()
    print("Textures written to " + mm.OUT)


if __name__ == "__main__":
    main()
