#!/usr/bin/env python3
"""Drawing primitives for Arcanum's textures (32-bit TGA, top-left origin).

No dependencies: vector shapes rasterised with 4x4 supersampling.
"""
import math
import os
import struct

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT = os.path.join(ROOT, "Arcanum", "Media")
SS = 4


# ---------------------------------------------------------------- TGA writing
def write_tga(name, w, h, rgba):
    path = os.path.join(OUT, name + ".tga")
    os.makedirs(os.path.dirname(path), exist_ok=True)
    header = struct.pack("<BBBHHBHHHHBB", 0, 0, 2, 0, 0, 0, 0, 0, w, h, 32, 0x28)
    data = bytearray()
    for (r, g, b, a) in rgba:
        data += bytes((b, g, r, a))
    with open(path, "wb") as f:
        f.write(header + bytes(data))


def clamp(x, a=0.0, b=1.0):
    return a if x < a else b if x > b else x


def coverage(w, h, inside):
    out = []
    inv = 1.0 / (SS * SS)
    for y in range(h):
        for x in range(w):
            c = 0
            for sy in range(SS):
                v = (y + (sy + 0.5) / SS) / h
                for sx in range(SS):
                    u = (x + (sx + 0.5) / SS) / w
                    if inside(u, v):
                        c += 1
            out.append(c * inv)
    return out


def white(cov):
    return [(255, 255, 255, int(round(c * 255))) for c in cov]


# ---------------------------------------------------------------- primitives
def circle(cx, cy, r):
    r2 = r * r
    return lambda u, v: (u - cx) ** 2 + (v - cy) ** 2 <= r2


def ring(cx, cy, r, t):
    lo, hi = (r - t) ** 2, r * r
    return lambda u, v: lo <= (u - cx) ** 2 + (v - cy) ** 2 <= hi


def rect(x0, y0, x1, y1):
    return lambda u, v: x0 <= u <= x1 and y0 <= v <= y1


def rrect(x0, y0, x1, y1, r):
    def f(u, v):
        if not (x0 <= u <= x1 and y0 <= v <= y1):
            return False
        cx = min(max(u, x0 + r), x1 - r)
        cy = min(max(v, y0 + r), y1 - r)
        return (u - cx) ** 2 + (v - cy) ** 2 <= r * r
    return f


def seg(x0, y0, x1, y1, w):
    dx, dy = x1 - x0, y1 - y0
    L = dx * dx + dy * dy
    rr = (w / 2) ** 2

    def f(u, v):
        t = 0 if L == 0 else clamp(((u - x0) * dx + (v - y0) * dy) / L)
        px, py = x0 + t * dx, y0 + t * dy
        return (u - px) ** 2 + (v - py) ** 2 <= rr
    return f


def poly(pts):
    n = len(pts)

    def f(u, v):
        inside = False
        j = n - 1
        for i in range(n):
            xi, yi = pts[i]
            xj, yj = pts[j]
            if (yi > v) != (yj > v) and u < (xj - xi) * (v - yi) / (yj - yi) + xi:
                inside = not inside
            j = i
        return inside
    return f


def union(*fs):
    return lambda u, v: any(f(u, v) for f in fs)


def sub(a, *bs):
    return lambda u, v: a(u, v) and not any(b(u, v) for b in bs)


def inter(a, b):
    return lambda u, v: a(u, v) and b(u, v)


def star_pts(cx, cy, R, r, n):
    pts = []
    for i in range(n * 2):
        ang = -math.pi / 2 + i * math.pi / n
        rad = R if i % 2 == 0 else r
        pts.append((cx + math.cos(ang) * rad, cy + math.sin(ang) * rad))
    return pts


def bezier(p0, p1, p2, steps=24):
    pts = []
    for i in range(steps + 1):
        t = i / steps
        a, b, c = (1 - t) ** 2, 2 * (1 - t) * t, t * t
        pts.append((a * p0[0] + b * p1[0] + c * p2[0], a * p0[1] + b * p1[1] + c * p2[1]))
    return pts
