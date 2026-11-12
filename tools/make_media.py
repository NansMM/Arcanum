#!/usr/bin/env python3
"""Génère les textures d'Arcanum (TGA 32 bits) dans Arcanum/Media.

Aucune dépendance : formes rastérisées avec les primitives de shapes.py (suréchantillonnage 4x4).
Les textures sont blanches (teintées en jeu), sauf le logo.
Usage : python tools/make_media.py
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
    """Cristal de charge : quatre facettes d'éclat différent, pour le relief une fois teinté."""
    S = 64
    top, right, bottom, left = DIAMOND
    mid = (0.5, 0.5)
    facets = [
        (mm.poly([top, mid, left]), 1.00),     # haut gauche : la plus claire
        (mm.poly([top, right, mid]), 0.80),
        (mm.poly([left, mid, bottom]), 0.66),
        (mm.poly([mid, right, bottom]), 0.50),  # bas droite : la plus sombre
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
    S = 128
    px = []
    for y in range(S):
        for x in range(S):
            d = math.hypot((x + 0.5) / S - 0.5, (y + 0.5) / S - 0.5) * 2
            a = mm.clamp(1 - d) ** 2.2
            px.append((255, 255, 255, int(round(a * 255))))
    mm.write_tga("glow", S, S, px)


def make_halo():
    """Anneau diffus : onde qui s'élargit quand un proc arrive."""
    S = 128
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
    edge = mm.sub(full, mm.rrect(0.055, 0.055, 0.945, 0.945, 0.19))
    mm.write_tga("roundsq-edge", S, S, mm.white(mm.coverage(S, S, edge)))
    # halo de la forme, pour l'icône « à lancer »
    px = []
    G = 128
    for y in range(G):
        for x in range(G):
            u, v = (x + 0.5) / G, (y + 0.5) / G
            # distance au carré arrondi inscrit (marge 0.2)
            m, r = 0.20, 0.14
            cx = min(max(u, m + r), 1 - m - r)
            cy = min(max(v, m + r), 1 - m - r)
            d = math.hypot(u - cx, v - cy) - r
            a = 1.0 if d <= 0 else math.exp(-(d / 0.075) ** 2)
            px.append((255, 255, 255, int(round(mm.clamp(a) * 255))))
    mm.write_tga("roundsq-glow", G, G, px)


def make_circle():
    mm.write_tga("circle", 64, 64, mm.white(mm.coverage(64, 64, mm.circle(0.5, 0.5, 0.5))))


def make_fade():
    w, h = 128, 8
    px = []
    for y in range(h):
        for x in range(w):
            a = math.sin(math.pi * (x + 0.5) / w) ** 1.6
            px.append((255, 255, 255, int(round(a * 255))))
    mm.write_tga("fade-h", w, h, px)
    # dégradé horizontal plein → transparent (traînée des barres)
    px = [(255, 255, 255, int(round(255 * ((x + 0.5) / w) ** 1.4))) for y in range(h) for x in range(w)]
    mm.write_tga("grad-h", w, h, px)


def make_shine():
    S = 64
    px = []
    for y in range(S):
        for x in range(S):
            u, v = (x + 0.5) / S, (y + 0.5) / S
            d = abs((u - 0.5) + (v - 0.5) * 0.45)
            a = math.exp(-(d / 0.13) ** 2)
            px.append((255, 255, 255, int(round(mm.clamp(a) * 255))))
    mm.write_tga("shine", S, S, px)


def make_spark():
    """Étincelle à quatre branches."""
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


def polar_tex(name, size, inside, ss=3, soft=False):
    """Texture blanche définie en coordonnées polaires : inside(r, angle, u, v) -> bool, r dans [0, 0.5]."""
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
    if soft:
        # bords doux (moyenne 3x3) : un trait net scintille quand la texture tourne, un trait doux non
        blurred = []
        for y in range(size):
            for x in range(size):
                total, n = 0.0, 0
                for dy in (-1, 0, 1):
                    for dx in (-1, 0, 1):
                        xx, yy = x + dx, y + dy
                        if 0 <= xx < size and 0 <= yy < size:
                            total += px[yy * size + xx]
                            n += 1
                blurred.append(total / n)
        peak = max(blurred) or 1.0
        px = [min(1.0, v / peak) for v in blurred]
    mm.write_tga(name, size, size, [(255, 255, 255, int(round(v * 255))) for v in px])


def near(angle, count, half_width):
    """L'angle est-il à moins de half_width (radians) d'une des `count` graduations régulières ?"""
    step = 2 * math.pi / count
    d = (angle + math.pi) % step
    return min(d, step - d) <= half_width


def make_runic():
    """Cercle runique : anneau, graduations runiques, bande du minuteur (découpée en arc par un widget
    Cooldown), bord des icônes rondes.

    Ces textures tournent en jeu. Elles sont donc dessinées à leur taille d'affichage (128 px pour
    133 px à l'écran) et aucun trait ne fait moins de 2 px : une texture plus grande, réduite par le jeu,
    ou un trait plus fin, scintille quand il tourne."""
    S = 128
    polar_tex("ring", S, lambda r, a, u, v: 0.456 <= r <= 0.474, ss=4)
    polar_tex("arc", S, lambda r, a, u, v: 0.451 <= r <= 0.479, ss=4)
    polar_tex("circle-edge", 128, lambda r, a, u, v: 0.43 <= r <= 0.5)

    def runes(r, a, u, v):
        if 0.400 <= r <= 0.424 and near(a, 36, 0.020):      # graduations fines (2 px)
            return True
        if 0.380 <= r <= 0.430 and near(a, 12, 0.027):      # graduations longues (2,7 px)
            return True
        if 0.330 <= r <= 0.346:                             # filet intérieur (2 px)
            return True
        # petits losanges entre les graduations longues
        step = 2 * math.pi / 12
        d = ((a + math.pi + step / 2) % step) - step / 2
        return abs(r - 0.365) / 0.020 + abs(d * r) / 0.014 <= 1
    polar_tex("runes", S, runes, ss=4, soft=True)


def main():
    make_runic()
    make_diamond()
    make_glow()
    make_halo()
    make_roundsq()
    make_circle()
    make_fade()
    make_shine()
    make_spark()
    make_logo()
    print("Textures écrites dans " + mm.OUT)


if __name__ == "__main__":
    main()
