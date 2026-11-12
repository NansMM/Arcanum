#!/usr/bin/env python3
"""Aperçu du HUD d'Arcanum : compose les vraies textures de l'addon selon la mise en page de UI/Hud.lua.

Ce n'est pas une capture du jeu : les icônes de sorts et les textes sont remplacés par des aplats.
Sert à juger les formes, les couleurs et les halos sans lancer WoW. Aucune dépendance.
Usage : python tools/preview.py   ->   docs/apercu.png
"""
import math
import os
import struct
import zlib

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
MEDIA = os.path.join(ROOT, "Arcanum", "Media")
OUT = os.path.join(ROOT, "docs", "apercu.png")

K = 2.4                      # échelle du rendu
W, H = int(848 * K), int(216 * K)

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
    """Dessine une texture centrée en (cx, cy), taille (w, h) en unités du HUD (y vers le bas)."""
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
                # arc restant, comme le voile d'un widget Cooldown : part du haut, dans le sens horaire
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


def pill(cx, cy, w, h, color, alpha):
    blit("circle", cx - w / 2 + h / 4, cy, h / 2, h, color, alpha, uv=(0, 0.5, 0, 1))
    blit("circle", cx + w / 2 - h / 4, cy, h / 2, h, color, alpha, uv=(0.5, 1, 0, 1))
    blit(None, cx, cy, w - h, h, color, alpha)


def card(cx, cy, w, color, frac):
    blit("glow", cx, cy, w * 1.45, 26 * 3.2, color, 0.30, add=True)
    pill(cx, cy, w + 3, 29, color, 0.55)
    pill(cx, cy, w, 26, C["ink"], 0.92)
    blit("circle", cx - w / 2 + 13, cy, 20, 20, mix(color, C["ink"], 0.35), 1)
    blit(None, cx - w / 2 + 34 + 34, cy, 68, 3, C["text"], 0.80)                 # libellé (aplat)
    blit(None, cx + w / 2 - 19, cy, 14, 8, color, 0.95)                          # secondes (aplat)
    lw = (w - 26) * frac
    blit(None, cx - w / 2 + 13 + lw / 2, cy + 10, lw, 2, color, 0.9)


def icon(cx, cy, size, tint, hint=None, active=None, cooldown=0.0):
    if hint:
        blit("roundsq-glow", cx, cy, size * 1.78, size * 1.78, hint, 0.85, add=True)
    if active:
        blit("roundsq-glow", cx, cy, size * 1.7, size * 1.7, active, 0.45, add=True)
    blit("roundsq", cx, cy, size + 4, size + 4, C["ink"], 0.94)
    blit("roundsq", cx, cy, size, size, mix(tint, C["ink"], 0.45 + 0.35 * cooldown), 1)
    blit("glow", cx - size * 0.12, cy - size * 0.14, size * 0.9, size * 0.9, mix(tint, C["white"], 0.5), 0.5 * (1 - cooldown), add=True)
    if cooldown > 0:
        blit("roundsq", cx, cy + size * (1 - cooldown) / 2, size, size * cooldown, (0.02, 0.01, 0.06), 0.72,
             uv=(0, 1, 1 - cooldown, 1))
    ring = hint or active or C["edge"]
    blit("roundsq-edge", cx, cy, size + 2, size + 2, ring, 1.0 if (hint or active) else 0.55)


def round_icon(cx, cy, size, tint, ring, glow=0.0, cooldown=0.0):
    if glow:
        blit("glow", cx, cy, size * 2.0, size * 2.0, ring, glow, add=True)
    blit("circle", cx, cy, size + 4, size + 4, C["ink"], 0.96)
    blit("circle", cx, cy, size, size, mix(tint, C["ink"], 0.42 + 0.3 * cooldown), 1)
    blit("glow", cx - size * 0.12, cy - size * 0.14, size * 0.9, size * 0.9, mix(tint, C["white"], 0.5), 0.5 * (1 - cooldown), add=True)
    if cooldown > 0:
        blit("circle", cx, cy, size, size, (0.02, 0.01, 0.06), 0.76, sweep=cooldown)
    blit("circle-edge", cx, cy, size + 4, size + 4, ring, 0.95)


def hud(cx, cy, stacks, target, reason, tint, window, cooldowns, procs=(), stage=None, cue=False):
    """Le cercle tel que le dispose UI/Hud.lua."""
    R = 62
    S = R / 0.465
    urgent = reason is not C["arcane"]
    full = stacks >= target
    col = C["hot"] if full else C["arcane"]
    # (anneau : piste sombre sous l'arc de la fenêtre ; en or quand c'est le moment du burst)
    line = mix(C["edge"], C["power"], 0.95) if cue else mix(C["edge"], reason, 0.55)

    def on_ring(angle, radius=R):
        a = math.radians(angle)
        return cx + radius * math.cos(a), cy - radius * math.sin(a)

    blit("circle", cx, cy, 2 * R + 6, 2 * R + 6, C["ink"], 0.34)
    blit("ring", cx, cy, S, S, line, 0.85 if (cue or stacks == 0) else 0.32)
    if stacks > 0:
        blit("arc", cx, cy, S, S, col, 1, sweep=window)
    if stage is None:
        round_icon(cx, cy, 64, tint, reason, glow=0.35 if urgent else 0.0)
    else:
        # mode suivi seul : les procs actifs en grandes icônes au centre
        size = (56, 40, 32)[min(len(stage), 3) - 1] if stage else 0
        x = cx - (len(stage) - 1) * (size + 6) / 2
        for pcol, left in stage:
            round_icon(x, cy, size, pcol, pcol, glow=0.40, cooldown=1 - left)
            x += size + 6
    # un cristal par charge visée (un de plus quand le jeu en offre une), au-dessus du cercle
    shown = min(4, max(target, stacks))
    for i in range(shown):
        x, y = on_ring(90 + ((shown + 1) / 2 - (i + 1)) * 22, R + 20)
        on = i < stacks
        if on:
            blit("glow", x, y, 22 * 3, 28 * 2.6, col, 0.65 if full else 0.40, add=True)
        blit("diamond", x, y, 22, 28, C["socket"], 0.95)
        if on:
            blit("diamond", x, y, 22, 28, col, 1)
            blit("spark", x - 4, y - 6, 18, 18, C["white"], 0.85 if full else 0.5, add=True)
        blit("diamond-edge", x, y, 22, 28, C["arcaneHi"] if on else C["edge"], 1 if on else 0.45)
    # gros temps de recharge, sertis à gauche et à droite
    for angle, (ctint, active, cooldown) in zip((200, 340), cooldowns):
        x, y = on_ring(angle)
        if cue and cooldown == 0:   # c'est le moment : la gemme grossit et bat en or
            round_icon(x, y, 35, ctint, C["power"], glow=0.85, cooldown=0)
        else:
            round_icon(x, y, 28, ctint, active or C["edge"], glow=0.7 if active else 0.0, cooldown=cooldown)
    # orbes de proc, en bas : la couleur seule
    for angle, (pcol, left) in zip((250, 290), procs):
        if pcol:
            x, y = on_ring(angle)
            blit("glow", x, y, 16 * 2.6, 16 * 2.6, pcol, 0.45, add=True)
            blit("circle", x, y, 20, 20, C["ink"], 0.96)
            blit("circle", x, y, 16, 16, pcol, 1)
            blit("circle", x, y, 16, 16, (0.02, 0.01, 0.06), 0.76, sweep=1 - left)
            blit("circle-edge", x, y, 20, 20, mix(pcol, C["white"], 0.55), 1)


def main():
    background()
    # cycle normal (Déflagration, 1 charge sur 2 visées), Barrage de projectiles, puis mode suivi seul
    hud(118, 116, 1, 2, C["arcane"], C["arcane"], 0.86,
        [(C["pom"], None, 0.0), (C["power"], None, 0.0)])
    hud(322, 116, 2, 2, C["barrage"], C["barrage"], 0.55,
        [(C["pom"], None, 0.7), (C["power"], C["power"], 0.0)],
        procs=((C["barrage"], 0.8), (C["clear"], 0.45)))
    # mode suivi seul : pas de conseil, les deux procs au centre
    hud(526, 116, 2, 2, C["arcane"], C["arcane"], 0.55,
        [(C["pom"], None, 0.0), (C["power"], None, 0.4)],
        stage=((C["barrage"], 0.8), (C["clear"], 0.45)))
    # mode suivi seul : charges visées atteintes, c'est le moment du burst
    hud(730, 116, 2, 2, C["arcane"], C["arcane"], 0.70,
        [(C["pom"], None, 0.0), (C["power"], None, 0.0)],
        stage=(), cue=True)

    os.makedirs(os.path.dirname(OUT), exist_ok=True)
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
    with open(OUT, "wb") as f:
        f.write(png)
    print("Aperçu écrit : " + OUT)


if __name__ == "__main__":
    main()
