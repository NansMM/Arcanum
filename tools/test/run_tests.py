#!/usr/bin/env python3
"""Arcanum test bench: a simulated WoW Forever mage (Lua 5.1), with the secret values of combat.

Usage: python tools/test/run_tests.py   (needs the "lupa" module: pip install lupa)

The simulated client is French by default (the mock's spell names are French, to prove the addon never
depends on English names); Game(pre='Mock.locale = "enUS"') simulates an English one.
"""
import os
import re
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(os.path.dirname(HERE))
ADDON = os.path.join(ROOT, "Arcanum").replace("\\", "/")
MOCK = os.path.join(HERE, "mock.lua").replace("\\", "/")
from lupa import lua51  # noqa: E402

FAILS = []

AB, AM, WRATH, AP, POM, FIREBALL, EUREKA = 400574, 25345, 1326079, 12042, 12043, 133, 1259817
EXPLOSION = 1449
BLAST_AURA = ('Mock.auras["Déflagration des Arcanes"] = '
              '{ spellId = 400574, applications = %d, duration = 8, expirationTime = Mock.now + 8 }')
CHAT_PREFIX = "|cffb07cffArcanum|r "


def check(cond, label):
    print(("  ok   " if cond else "  FAIL ") + label)
    if not cond:
        FAILS.append(label)


class Game:
    def __init__(self, pre=None, login=True):
        self.lua = lua51.LuaRuntime(unpack_returned_tuples=True)
        self.lua.globals().dofile(MOCK)
        self.M = self.lua.globals().Mock
        if pre:
            self.lua.execute(pre)
        self.ns = self.M.load(ADDON, "Arcanum.toc", "Arcanum")
        self.M.fire("ADDON_LOADED", "Arcanum")
        if login:
            self.M.fire("PLAYER_LOGIN")
            self.M.fire("PLAYER_ENTERING_WORLD", True, False)
            self.M.advance(3.2)   # past the guard delay that follows a loading screen

    @property
    def S(self):
        return self.ns.State

    def buffed(self):
        """The character arrives buffed: no reminder before combat."""
        self.run('Mock.auras["Intelligence des Arcanes"] = { spellId = 1459, applications = 0, duration = 1800, expirationTime = Mock.now + 1800 }')
        self.run('Mock.auras["Armure du mage"] = { spellId = 6117, applications = 0, duration = 1800, expirationTime = Mock.now + 1800 }')
        self.run('Mock.fire("UNIT_AURA", "player", {})')

    def run(self, code):
        return self.lua.execute(code)

    def errors(self):
        return list(self.M.errors.values())

    def chat(self):
        """Everything the addon has printed to the chat window, without its "Arcanum" prefix."""
        return [line.replace(CHAT_PREFIX, "", 1) for line in self.M.chat.values()]

    def slash(self, msg):
        """Types "/arc <msg>"; returns the lines the addon printed in answer."""
        before = len(self.chat())
        self.lua.globals().SlashCmdList.ARCANUM(msg)
        return self.chat()[before:]

    def sound_files(self):
        """The sound files the addon has asked the game to play, by file name."""
        return [path.split("\\")[-1] for path in (self.M.soundFiles or {}).values()]

    def spoken(self):
        """What the addon has asked the game's text-to-speech voice to say."""
        return list(self.M.spoken.values())

    def fight(self):
        self.M.target = True
        self.M.setCombat(True)
        self.M.advance(0.2)

    def cast(self, spell, wait=0.3):
        self.M.cast(spell)
        self.M.advance(wait)


def no_errors(g, label):
    errs = g.errors()
    check(len(errs) == 0 and (g.ns.errorCount or 0) == 0, "%s: no Lua errors" % label)
    for e in errs[:8]:
        print("        ", e)


# ---------------------------------------------------------------------- locale keys read from the sources
LUA_STRING = r'"((?:[^"\\\n]|\\.)*)"'
L_LITERAL = re.compile(r'(?<![A-Za-z0-9_])L\[\s*' + LUA_STRING + r'\s*\]')
L_INDIRECT = re.compile(r'(?<![A-Za-z0-9_])L\[\s*(?!["\s])')


def lua_code(text):
    """Lua source without its comments; string literals are left untouched."""
    out, i, n = [], 0, len(text)
    while i < n:
        c = text[i]
        if c in "\"'":                                  # a string: copied as is, up to its closing quote
            j = i + 1
            while j < n and text[j] != c:
                j += 2 if text[j] == "\\" else 1
            out.append(text[i:j + 1])
            i = j + 1
        elif text.startswith("--", i):
            long = re.match(r"--\[(=*)\[", text[i:])
            if long:                                    # --[[ block comment ]]
                end = text.find("]" + long.group(1) + "]", i)
                i = n if end < 0 else end + len(long.group(1)) + 2
            else:                                       # -- comment, up to the end of the line
                end = text.find("\n", i)
                i = n if end < 0 else end
        else:
            out.append(c)
            i += 1
    return "".join(out)


def lua_unescape(s):
    """The value of a Lua string literal, given what is written between its quotes."""
    simple = {"n": b"\n", "t": b"\t", "r": b"\r", "a": b"\a", "b": b"\b", "f": b"\f", "v": b"\v"}
    out = bytearray()
    i = 0
    while i < len(s):
        if s[i] != "\\":
            out += s[i].encode("utf-8")
            i += 1
            continue
        digits = re.match(r"\d{1,3}", s[i + 1:])
        if digits:                                      # \194\160: a byte, by its decimal value
            out.append(int(digits.group(0)))
            i += 1 + len(digits.group(0))
        else:                                           # \" \\ \n …
            out += simple.get(s[i + 1], s[i + 1].encode("utf-8"))
            i += 2
    return out.decode("utf-8")


def lua_table(code, name):
    """The text of `local <name> = { … }` in comment-free Lua code, braces included."""
    start = re.search(r"\blocal\s+%s\s*=\s*\{" % re.escape(name), code)
    if not start:
        raise ValueError("table %s not found" % name)
    i, depth = start.end() - 1, 0
    while i < len(code):
        c = code[i]
        if c in "\"'":
            j = i + 1
            while j < len(code) and code[j] != c:
                j += 2 if code[j] == "\\" else 1
            i = j
        elif c == "{":
            depth += 1
        elif c == "}":
            depth -= 1
            if depth == 0:
                return code[start.end() - 1:i + 1]
        i += 1
    raise ValueError("table %s is not closed" % name)


# Strings that reach L[...] through a variable: file -> { expression inside L[...]: (table, pattern) }.
INDIRECT_KEYS = {
    "UI/Hud.lua": {
        "def.say": ("PROC_SOUND", r"\bsay\s*=\s*" + LUA_STRING),    # the word the game voice says
        "s[2]": ("SOUNDS", LUA_STRING),                             # the names of the game sounds on offer
    },
    "UI/Options.lua": {
        "SOUND_LABEL[key]": ("SOUND_LABEL", LUA_STRING),            # the proc named by /arc sound
        "line": ("HELP", LUA_STRING),                               # the help lines
    },
}


def locale_keys_used():
    """Every key the addon passes to L[...]: (keys, indirect lookups this function does not know)."""
    used, unknown = set(), []
    for folder, dirs, files in os.walk(ADDON):
        dirs[:] = [d for d in dirs if d != "Locales"]
        for name in sorted(files):
            if not name.endswith(".lua"):
                continue
            path = os.path.join(folder, name)
            rel = os.path.relpath(path, ADDON).replace("\\", "/")
            with open(path, encoding="utf-8") as fh:
                code = lua_code(fh.read())
            used.update(lua_unescape(m.group(1)) for m in L_LITERAL.finditer(code))
            known = INDIRECT_KEYS.get(rel, {})
            for m in L_INDIRECT.finditer(code):
                depth, j = 1, m.end()
                while j < len(code) and depth > 0:      # up to the bracket that closes L[
                    depth += {"[": 1, "]": -1}.get(code[j], 0)
                    j += 1
                expr = code[m.end():j - 1].strip()
                if expr not in known:
                    unknown.append("%s: L[%s]" % (rel, expr))
            for table, pattern in known.values():
                used.update(lua_unescape(s) for s in re.findall(pattern, lua_table(code, table)))
    return used, unknown


def main():
    print("Startup")
    g = Game()
    check(g.ns.started is True, "the HUD starts for a mage")
    check(g.M.named["ArcanumHUD"] is not None, "the ArcanumHUD frame exists")
    sp = g.ns.Spells
    check(sp.Known("blast") and sp.Known("wrath") and sp.Known("missiles"), "rotation spells recognised by their French names")
    check(sp.Best("missiles") == AM, "the highest rank of Arcane Missiles is kept (rank 8)")
    check(sp.KeyOf(5144) == "missiles", "a lower rank is tied to the same spell")
    check(not sp.Known("pyro"), "Pyroblast not learned: the Fire variant is ignored")
    check(sp.Known("eureka") and sp.Best("eureka") == EUREKA, "Eureka (gnome racial) recognised")
    no_errors(g, "startup")

    other = Game(pre='Mock.class = "WARRIOR"')
    check(not other.ns.started, "the addon stays asleep on a warrior")
    said = other.slash("")
    check(not other.ns.started and said == ["est fait pour les mages. Tape /arc demo pour voir le HUD quand même."],
          "/arc does not start the HUD on another class, and says why")
    other.slash("demo")
    other.M.advance(3)
    check(other.ns.started and other.S.demo, "/arc demo works on any class")
    no_errors(other, "warrior")

    print("Out of combat: the truth comes from the auras")
    g.cast(AB)
    check(g.S.stacks == 1 and g.S.stacksSource == "aura", "1 charge read from the aura")
    g.cast(AB)
    g.cast(AB)
    check(g.S.stacks == 3, "3 charges read from the aura")
    learn = g.ns.db.learn
    check(learn.abBase == 100, "Arcane Blast base cost learned (100)")
    check(learn.costTracks is True and abs(learn.abStep - 1.0) < 0.01, "extra cost per charge learned (+100 %)")
    check(learn.abWindow == 18, "charge window learned at the first charge (18 s)")
    g.M.advance(17.0)
    g.M.expire()
    g.M.advance(0.3)
    check(g.S.stacks == 3, "17 s after the first Arcane Blast: the charges are still there")
    g.M.advance(1.0)
    g.M.expire()
    g.M.advance(0.3)
    check(g.S.stacks == 0, "the charges drop 18 s after the first Arcane Blast")

    print("In combat: auras hidden, charges tracked from the spells cast")
    g.fight()
    check(g.S.restricted is True, "auras are secret in combat")
    t0 = g.M.now
    for i in range(1, 5):
        g.cast(AB)
        check(g.S.stacks == i, "Arcane Blast %d: %d charge(s)" % (i, i))
    check(g.S.stacksSource == "casts", "source: spells cast")
    g.cast(AB)
    check(g.S.stacks == 4, "never more than 4 charges")
    g.cast(EUREKA)
    check(g.S.eureka.active and g.S.eureka.source == "casts", "Eureka cast: active, known from the cast")
    g.cast(POM)
    check(g.S.pom.active and g.S.pom.source == "casts", "Presence of Mind cast: active, known from the cast")
    g.cast(WRATH)
    check(not g.S.pom.active, "Presence of Mind spent by Arcane Wrath (a spell with a cast time)")
    check(g.S.stacks == 4, "Arcane Wrath does not consume the charges")
    g.cast(FIREBALL)
    g.cast(AM)
    check(g.S.stacks == 4, "Fireball and Arcane Missiles do not consume the charges")
    g.M.advance(t0 + 17.6 - g.M.now)
    g.M.expire()
    check(g.S.stacks == 4, "17.6 s after the first Arcane Blast: 4 charges")
    g.M.advance(0.8)
    g.M.expire()
    g.M.advance(0.3)
    check(g.S.stacks == 0, "the 18 s window is not extended by the following Arcane Blasts")

    print("In combat: procs seen through the cost of spells")
    g.cast(AB)
    g.M.proc("Barrage de projectiles", 400588)
    g.M.advance(0.3)
    check(g.S.barrage.active and g.S.barrage.source == "cost", "Missile Barrage detected (Arcane Missiles are free)")
    badge = g.run("for _, f in ipairs(Mock.ns.Hud.procs) do if f.def.key == 'barrage' then return f end end")
    check(badge.on is True and badge._shown is True and badge.cd._cd[2] == 15 and badge._points[1][4] > 0,
          "Missile Barrage icon shown on the right of the character, with its 15 s")
    check(not g.S.clear.active, "no false Clearcasting alert")
    g.M.proc("Idées claires", 12536)
    g.M.advance(0.3)
    check(g.S.clear.active and g.S.clear.source == "cost", "Clearcasting detected (everything is free)")
    check(g.S.barrage.active, "Missile Barrage stays known during Clearcasting")
    g.cast(AM)
    g.M.proc("Idées claires", 12536)
    g.M.advance(0.3)
    g.M.proc("Barrage de projectiles", 400588)
    g.M.advance(0.3)
    g.cast(AB)
    check(not g.S.clear.active, "Clearcasting spent")
    check(g.S.barrage.active, "Missile Barrage still there")
    g.cast(AM)
    check(not g.S.barrage.active, "Missile Barrage spent by Arcane Missiles")
    g.M.advance(1.0)
    check(not g.S.barrage.active, "no ghost Missile Barrage coming back")
    check(badge.on is False and badge._shown is False, "Missile Barrage icon removed")
    check(g.S.stacks == 2, "2 charges, counted despite the procs")

    print("In combat: Arcane Missiles channel, one volley after another")
    g.M.proc("Barrage de projectiles", 400588)
    g.M.advance(0.3)
    check(g.S.barrage.active, "Missile Barrage active")
    g.M.channel(AM, 5, 0.5)
    g.M.advance(1.0)
    check(not g.S.barrage.active, "five volleys: Missile Barrage is spent once, and no ghost comes back")
    g.M.proc("Barrage de projectiles", 400588)
    g.M.channel(AM, 3, 0.5)
    g.M.proc("Barrage de projectiles", 400588)               # a volley triggers a new one
    g.M.advance(1.0)
    check(g.S.barrage.active, "Missile Barrage triggered again during the channel: it shows up again")
    g.cast(AM)
    g.M.advance(1.0)

    print("Loading screen: no false alert")
    z = Game()
    z.fight()
    z.cast(AB)
    z.run('Mock.fire("PLAYER_ENTERING_WORLD", false, true)')
    z.run('Mock.freeMeansNil = true; for id, sp in pairs(Mock.spells) do sp.saved, sp.cost = sp.cost, sp.cost and 0 end')
    z.M.advance(1.0)
    check(not z.S.clear.active, "costs missing right after a loading screen: no Clearcasting announced")
    z.run('for id, sp in pairs(Mock.spells) do sp.cost = sp.saved end')
    z.M.advance(3.0)
    check(not z.S.clear.active, "costs back: still nothing")
    no_errors(z, "loading screen")

    print("In combat: number of charges read from the cost")
    g.cast(AB)
    check(g.S.stacks == 3, "3 charges")
    g.run(BLAST_AURA % 2)                                    # the game has 2, the addon counts 3
    g.M.advance(1.0)
    check(g.S.stacks == 2 and g.S.stacksSource == "cost", "gap corrected: 2 charges read from the cost")
    g.run('Mock.auras["Déflagration des Arcanes"] = nil')   # the game removes them without the addon seeing a spell
    g.M.advance(1.0)
    check(g.S.stacks == 0, "charges removed by the game: seen when the cost is back to its base")
    g.run(BLAST_AURA % 3)
    g.M.advance(1.0)
    check(g.S.stacks == 3, "charges there without any spell seen (reload in combat): read from the cost")
    g.M.advance(8.5)
    g.M.expire()
    g.M.advance(0.5)
    check(g.S.stacks == 0, "charges expired")

    print("In combat: Arcane Power, Presence of Mind")
    g.cast(AP)
    check(g.S.power.active, "Arcane Power active after the cast")
    g.cast(POM)
    check(g.S.pom.active, "Presence of Mind active")
    g.cast(AB)
    check(not g.S.pom.active, "Presence of Mind spent by a spell with a cast time")
    check(g.S.stacks == 1, "Arcane Power (reduced cost) does not distort the charges")
    g.M.advance(15.5)
    g.M.expire()
    g.M.advance(0.3)
    check(not g.S.power.active, "Arcane Power over after 15 s")
    no_errors(g, "combat")

    print("Charge crystals: one per charge")
    t = Game()
    crystals = lambda: len([f for f in t.ns.Hud.crystals.values() if f._shown])
    t.fight()
    t.M.advance(0.2)
    check(crystals() == 0, "no charge: no crystal shown")
    t.cast(EXPLOSION)
    check(t.S.stacks == 0 and crystals() == 0, "Arcane Explosion builds no charge")
    t.cast(AB)
    check(crystals() == 1, "1 charge: a single crystal shown")
    t.cast(AB)
    t.cast(AB)
    t.cast(AB)
    t.M.advance(0.3)
    check(t.S.stacks == 4 and crystals() == 4, "4 charges: one crystal per charge")
    no_errors(t, "charge crystals")

    print("Reminders before combat")
    r2 = Game()
    r2.M.advance(1.2)
    check(list(r2.S.reminders.values()) == ["intellect", "magearmor"], "Arcane Intellect and armor missing")
    shown = [f for f in r2.ns.Hud.reminders.values() if f.key]
    check(len(shown) == 2 and all(f._shown for f in shown) and all(f._points[1][5] < 0 for f in shown)
          and r2.ns.Hud.prep._alpha > 0.9, "two reminders shown below the character")
    r2.buffed()
    r2.run('Mock.items[8079] = nil; Mock.items[8076] = nil; Mock.fire("BAG_UPDATE_DELAYED")')
    r2.M.advance(1.2)
    check(list(r2.S.reminders.values()) == ["water", "food"], "buffed but without conjured water or food: two reminders")
    r2.run('Mock.items[1179] = 5; Mock.fire("BAG_UPDATE_DELAYED")')
    r2.M.advance(1.2)
    check(list(r2.S.reminders.values()) == ["water", "food"], "bought water does not count: it has to be conjured")
    r2.run('Mock.items[5350] = 10; Mock.fire("BAG_UPDATE_DELAYED")')
    r2.M.advance(1.2)
    check(list(r2.S.reminders.values()) == ["food"], "conjured water of a low rank: it counts, the reminder goes away")
    r2.run('Mock.items[22895] = 5; Mock.items[8008] = nil; Mock.fire("BAG_UPDATE_DELAYED")')
    r2.M.advance(1.2)
    check(list(r2.S.reminders.values()) == ["gemspell"], "food conjured, but no mana gem left: mana gem reminder")
    gem = [f for f in r2.ns.Hud.reminders.values() if f.key][0]
    check(gem._shown is True and gem.icon._tex == 130054, "the reminder carries the icon of the spell that conjures the gem")
    r2.run('Mock.items[8007] = 1; Mock.fire("BAG_UPDATE_DELAYED")')
    r2.M.advance(1.2)
    check(list(r2.S.reminders.values()) == ["gemspell"], "a gem of a lower rank is not enough: the best one is still to conjure")
    r2.run('Mock.items[8008] = 1; Mock.fire("BAG_UPDATE_DELAYED")')
    r2.M.advance(2.5)
    check(len(list(r2.S.reminders.values())) == 0 and r2.ns.Hud.prep._alpha == 0, "everything is ready: no reminder")
    r2.run('Mock.resting = true; Mock.auras["Armure du mage"] = nil; Mock.fire("UNIT_AURA", "player", {})')
    r2.M.advance(1.5)
    check(list(r2.S.reminders.values()) == ["magearmor"] and r2.ns.Hud.prep._alpha == 0,
          "resting in a city: the reminder waits, without showing")
    r2.run('Mock.resting = false')
    r2.M.advance(0.8)
    check(r2.ns.Hud.prep._alpha > 0.9, "out of the city: the reminder shows")
    r2.fight()
    r2.M.advance(1.2)
    check(len(list(r2.S.reminders.values())) == 0, "in combat: no reminder (auras are hidden)")
    no_errors(r2, "reminders")

    print("In-game checks recorded for the diagnostics")
    v = Game(pre='Mock.neverSecret["Présence spirituelle"] = true')
    v.fight()
    v.cast(AB)
    checks = v.ns.db.learn.checks
    check(checks.mana == "secret" and checks.usable == "readable" and checks.cooldown == "secret",
          "mana secret, \"usable\" readable, cooldowns secret: observed in combat")
    v.M.proc("Barrage de projectiles", 400588)
    v.cast(POM)
    v.M.channel(AM, 3, 0.5)
    v.M.advance(0.5)
    check(v.S.pom.active and v.S.pom.source == "aura",
          "Presence of Mind, whose aura stays readable in combat, is kept through Arcane Missiles")
    v.slash("diag")
    report = v.M.named["ArcanumDiag"].text
    check("VÉRIFICATIONS EN JEU" in report and "mana du joueur : caché" in report
          and "mana insuffisant » : lisible" in report,
          "the diagnostics report the in-game checks, in the client's language")
    check("cast missiles x3" in report, "log: the volleys of a channel fit on one line")
    v.cast(WRATH)
    check(not v.S.pom.active, "Arcane Wrath then spends it: its aura is gone")
    no_errors(v, "in-game checks")

    print("Presence of Mind cast before combat")
    pm = Game()
    pm.M.target = True
    pm.M.advance(0.3)
    pm.cast(POM)                                             # out of combat: the aura is read
    check(pm.S.pom.active and pm.S.pom.source == "aura", "Presence of Mind read from its aura")
    pm.cast(WRATH)                                           # it goes away with Arcane Wrath…
    pm.M.setCombat(True)                                     # …and combat starts: the aura can no longer be read
    pm.M.advance(0.3)
    pm.cast(AB)
    check(not pm.S.pom.active, "in combat, the spell cast ends Presence of Mind (it does not stay \"active\")")
    no_errors(pm, "Presence of Mind")

    print("Around the character: procs, charges, Presence of Mind")
    f = Game()
    hud = f.ns.Hud
    proc = lambda key: f.run("for _, b in ipairs(Mock.ns.Hud.procs) do if b.def.key == '%s' then return b end end" % key)
    left, right = proc("clear"), proc("barrage")
    check(left._points[1][4] == -150 and right._points[1][4] == 150 and left._points[1][5] == 0,
          "Clearcasting on the left of the character, Missile Barrage on the right")
    f.fight()
    f.M.advance(0.3)
    check(hud.fight._alpha > 0.9 and not left._shown and not right._shown, "in combat without a proc: the sides stay empty")
    check(not any(c._shown for c in hud.crystals.values()) and hud.bar._alpha == 0, "no charge: neither crystals nor bar")
    f.cast(AB)
    shown = [c for c in hud.crystals.values() if c._shown]
    check(f.S.stacks == 1 and len(shown) == 1 and all(c._points[1][5] > 100 for c in shown),
          "one charge: a crystal appears above the character")
    check(hud.bar._alpha == 1 and hud.barText._text in ("18 s", "17 s"), "below the crystals, the bar of their window and its seconds")
    pom, eur, power = hud.pomIcon, hud.eurekaIcon, hud.powerIcon
    check(pom.on is False and pom._alpha == 0 and eur.on is False and eur._alpha == 0,
          "neither Presence of Mind nor Eureka: nothing above the charges")
    f.cast(EUREKA)
    f.M.advance(0.4)
    check(f.S.eureka.active and eur.on is True and eur._alpha > 0.9 and eur.icon._tex == 130817 and eur.cd._cd[2] == 8,
          "Eureka active: its icon shows, with its 8 s")
    check(eur._points[1][4] == 0 and eur._points[1][5] > shown[0]._points[1][5], "above the charges, centred")
    f.cast(POM)
    f.M.advance(0.4)
    check(f.S.pom.active and pom.on is True and pom._alpha > 0.9 and pom.icon._tex == 130043
          and pom._points[1][5] > shown[0]._points[1][5], "Presence of Mind active: its icon shows above the charges")
    check(pom._points[1][4] == -28 and eur._points[1][4] == 28, "both active: side by side")
    f.cast(WRATH)
    f.M.advance(0.6)
    check(not f.S.pom.active and pom.on is False and pom._alpha == 0, "spent by Arcane Wrath: the icon goes away")
    check(eur.on is True and eur._points[1][4] == 0, "Eureka, still active, moves back to the centre")
    f.M.advance(7)
    check(not f.S.eureka.active and eur.on is False and eur._alpha == 0, "Eureka over: its icon goes away")
    check(power.on is False and power._alpha == 0, "Arcane Power not cast: no icon")
    f.cast(AP)
    f.M.advance(0.4)
    check(f.S.power.active and power.on is True and power._alpha > 0.9 and power.icon._tex == 130042
          and power.cd._cd[2] == 15 and power._points[1][4] == 0 and power._points[1][5] > shown[0]._points[1][5],
          "Arcane Power active: its icon shows above the charges, centered, with its 15 s")
    f.M.advance(15.5)
    check(not f.S.power.active and power.on is False and power._alpha == 0, "Arcane Power over: its icon goes away")
    played = lambda name: f.sound_files().count(name + ".ogg")
    check(played("burst") == 0, "no burst sound any more")
    f.M.proc("Barrage de projectiles", 400588)
    f.M.advance(0.6)
    check(played("barrage") == 1, "Missile Barrage has its sound")
    check(f.S.barrage.active and right.on is True and right._shown is True and right._w == 64 and right.cd._cd[2] == 15
          and right.icon._tex == 130588, "Missile Barrage shows on the right, with its own icon and its 15 s")
    check(left.on is False, "nothing on the left as long as there is no Clearcasting")
    f.M.proc("Idées claires", 12536)
    f.M.advance(0.3)
    check(left.echo._tex == 449486 and 0 < left.echo._alpha < 0.8 and left.echo._w > left.decor._w,
          "when the proc fires, the light wave is an echo of its decoration, growing wider")
    check(right.echo._alpha == 0, "the wave of Missile Barrage, which fired earlier, has faded out")
    check(left.on is True and left._shown is True and left.icon._tex == 130536 and right.on is True,
          "Clearcasting shows on the left, with its own icon, at the same time")
    check(left.decor._shown is True and left.decor._tex == 449486 and right.decor._tex == 449486,
          "the proc decoration: the game's rune arc, by its file id")
    check(left.decor._desat is True and not right.decor._desat,
          "the same arc on both sides: greyed and tinted for Clearcasting, as is for Missile Barrage")
    check(abs(left.decor._h - 256) < 12 and abs(left.decor._w - 128) < 6
          and left.decor._points[1][4] == -48 and right.decor._points[1][4] == 48,
          "large arcs, on the outer side of each proc")
    said = f.slash("decor")
    check(f.ns.db.decor is False and left.decor._shown is False and right.decor._shown is False and left._shown is True
          and said == ["décor des procs masqué."], "/arc decor: the procs stay, without decoration")
    said = f.slash("decor")
    check(f.ns.db.decor is True and left.decor._shown is True and left.echo._tex == 449486
          and said == ["décor des procs affiché."], "/arc decor again: the decoration is back, and the wave gets its image back")
    f.M.advance(0.8)
    check(left.echo._alpha == 0 and right.echo._alpha == 0, "once the wave has passed, only the decoration is left")
    f.run('Mock.ns.Set("spread", 200)')
    check(left._points[1][4] == -200 and right._points[1][4] == 200, "spread setting: the zones move away from the character")
    f.slash("ecart 120")
    check(f.ns.db.spread == 120 and left._points[1][4] == -120, "/arc ecart 120 (French alias of spread): the zones move closer")
    said = f.slash("ecart 20")
    check(f.ns.db.spread == 120 and said == ["écartement entre 80 et 320, par exemple /arc ecart 150."],
          "/arc ecart 20: out of range, refused")
    f.run('Mock.ns.Set("showProcs", false)')
    f.M.advance(0.6)
    check(right.on is False and not right._shown, "\"procs\" setting off: the icons go away")
    f.run('Mock.ns.Set("showProcs", true)')
    f.M.setCombat(False)
    f.run('Mock.auras = {}; Mock.fire("UNIT_AURA", "player", {})')
    f.slash("demo")
    sides, charges, pom_seen, eur_seen, power_seen = set(), set(), False, False, False
    demo_sounds = len(f.sound_files())
    for _ in range(240):
        f.M.advance(0.05)
        pom_seen = pom_seen or pom.on is True
        eur_seen = eur_seen or eur.on is True
        power_seen = power_seen or power.on is True
        sides.update(k for k, b in (("clear", left), ("barrage", right)) if b.on)
        charges.add(f.S.stacks)
    check(sides == {"clear", "barrage"}, "the demo shows both procs, each on its side")
    check(charges == {0, 1, 2, 3, 4}, "the charges building up")
    check(pom_seen and eur_seen and power_seen, "Presence of Mind, Eureka and Arcane Power")
    heard = f.sound_files()[demo_sounds:]
    check("clear.ogg" in heard and "barrage.ogg" in heard, "the demo plays the sound of each proc")
    f.slash("demo")
    f.M.advance(0.5)
    check(not any(b.on for b in hud.procs.values()) and f.S.stacks == 0 and not any(c._shown for c in hud.crystals.values()),
          "end of the demo: everything goes out")
    before = len(f.sound_files())
    f.run('Mock.ns.Set("sound", false)')
    said = f.slash("sons")
    check(f.sound_files()[before:] == ["clear.ogg", "barrage.ogg"], "/arc sons (French alias of sounds) plays both sounds, even with sounds off")
    check(said == ["Idées claires : son du jeu 4874.", "Barrage de projectiles : son du jeu 3333."],
          "and says, in French, which sound each proc plays")
    check(f.M.lastKit == 3333, "no file and no choice: Missile Barrage plays the Arcane Missiles sound")
    f.run('Mock.ns.Hud.PreviewSound("clear")')
    check(f.M.lastKit == 4874, "and Clearcasting plays the sound of the Clearcasting spell")
    f.slash("son 4874")
    check(f.M.lastKit == 4874 and f.ns.db.soundKit.barrage is None, "/arc son 4874: plays a game sound, without changing anything")
    f.slash("son barrage 3071")
    check(f.ns.db.soundKit.barrage == 3071 and f.M.lastKit == 3071, "/arc son barrage 3071: that game sound is picked for Missile Barrage")
    before = len(f.sound_files())
    f.slash("sons")
    check(f.sound_files()[before:] == ["clear.ogg"] and f.M.lastKit == 3071, "Missile Barrage then plays the picked sound, without looking for a file")
    f.slash("son clear 999999")
    check(f.ns.db.soundKit.clear is None, "id unknown to the game: the choice is not kept")
    f.slash("son barrage")
    check(f.ns.db.soundKit.barrage is None, "/arc son barrage: back to the default sound")
    f.slash("son burst 3071")
    check(f.ns.db.soundKit.burst is None, "/arc son burst: that cue no longer exists")
    f.run('Mock.ns.Hud.PreviewDecor()')
    f.M.advance(0.6)
    check(left.on is True and right.on is True and hud.fight._alpha > 0.9, "decoration preview: both procs show out of combat")
    f.M.advance(0.3)
    check(left.echo._alpha == 0, "the preview's wave is over: only the decoration is left")
    f.run('Mock.ns.Hud.PreviewDecor()')
    f.M.advance(0.2)
    check(0 < left.echo._alpha < 0.8, "a new preview starts the wave again, even with the procs already shown")
    f.run('Mock.ns.Set("decor", false)')
    check(left.echo._alpha == 0 and left.decor._shown is False, "hiding the decoration during the preview turns off the arc and its echo")
    f.run('Mock.ns.Set("decor", true)')
    check(left.on is True and left.decor._shown is True, "showing it again displays it on the HUD right away")
    f.M.advance(5.5)
    check(left.on is False and right.on is False, "then they go away after a few seconds")
    f.slash("verrou")
    check(f.ns.db.locked is False, "/arc verrou (French alias of lock): the HUD unlocks to be moved")
    f.slash("verrou")
    no_errors(f, "around the character")

    print("Saved variables from earlier versions")
    m = Game(pre='ArcanumDB = { version = 4, point = { "CENTER", "CENTER", 0, -170 }, showNext = false, '
                 'showMana = true, scale = 1.2, targetStacks = 3, decor = "fleurs" }')
    check(m.ns.db.decor is True, "an old decoration name in the saved settings: the decoration is shown")
    m2 = Game(pre='ArcanumDB = { version = 5, decor = "aucun" }')
    check(m2.ns.db.decor is False, "the old choice \"aucun\" (none): the decoration stays hidden")
    check(m.ns.db.point[3] == 0 and m.ns.db.point[4] == 0 and m.ns.db.spread == 150,
          "upgrade from a 0.12: the HUD is centred on the character again")
    check(m.ns.db.showNext is None and m.ns.db.showMana is None and m.ns.db.targetStacks is None and m.ns.db.scale == 1.2,
          "the settings of the old ring and of the advice are forgotten, the others kept")
    old = Game(pre='ArcanumDB = { version = 2, wrathStacks = 3, thrifty = true }')
    check(old.ns.db.wrathStacks is None and old.ns.db.thrifty is None and old.ns.db.targetStacks is None
          and old.ns.db.version == 6, "settings from a 0.x: the advice thresholds are dropped, nothing takes their place")
    m3 = Game(pre='ArcanumDB = { version = 5, soundKit = { barrage = "voix" }, targetStacks = 3, burstOne = true, '
                  'fillerRank = "max", cutForClear = true, openWrath = true, adviseBurst = false, anticipate = true, '
                  'learn = { cd = { power = 180 } } }')
    db = m3.ns.db
    check(db.soundKit.barrage == "voice" and m3.run('return Mock.ns.Hud.SoundName("barrage")') == "Voix du jeu",
          "upgrade to 2.0: the saved sound choice \"voix\" becomes \"voice\"")
    check(all(db[key] is None for key in ("targetStacks", "burstOne", "fillerRank", "cutForClear", "openWrath",
                                          "adviseBurst", "anticipate")),
          "upgrade to 2.0: the settings of the advice engine are deleted")
    check(db.learn.cd is None, "upgrade to 2.0: the learned cooldowns are deleted")
    check(db.version == 6, "upgrade to 2.0: the saved variables are at version 6")
    for game in (m, m2, old, m3):
        game.M.advance(1.0)
    no_errors(m, "settings upgrade from 0.12")
    no_errors(m3, "settings upgrade to 2.0")

    print("Sounds by their name")
    q = Game()
    name = lambda key: q.run('return Mock.ns.Hud.SoundName("%s")' % key)
    check(name("barrage") == "Par défaut", "settings: the Missile Barrage sound is the default one")
    q.run('Mock.ns.Hud.CycleSound("barrage", 1)')
    check(q.ns.db.soundKit.barrage == 18019 and q.M.lastKit == 18019 and name("barrage") == "Notification Battle.net",
          "next arrow: the first named sound is picked and played")
    q.run('Mock.ns.Hud.CycleSound("barrage", -1); Mock.ns.Hud.CycleSound("barrage", -1)')
    check(q.ns.db.soundKit.barrage == "voice" and name("barrage") == "Voix du jeu" and q.spoken()[-1] == "Barrage de projectiles",
          "previous arrow from the default: the game voice says the proc's name, in French")
    q.run('Mock.voices = {}; Mock.ns.Hud.CycleSound("barrage", 1)')
    check(q.ns.db.soundKit.barrage is None, "next arrow from the voice: back to the default sound")
    q.run('Mock.ns.Hud.CycleSound("barrage", -1)')
    check(q.ns.db.soundKit.barrage == 1642, "client without a text-to-speech voice: the voice is not offered")
    said = q.slash("son clear voix")
    check(q.ns.db.soundKit.clear is None and said == ["ce client n'a aucune voix de synthèse installée : choix inchangé."],
          "/arc son clear voix without a voice installed: nothing changed")
    q.run('Mock.voices = { { voiceID = 7 } }')
    said = q.slash("son clear voix")
    check(q.ns.db.soundKit.clear == "voice" and q.spoken()[-1] == "Idées claires" and said == ["Idées claires : voix du jeu."],
          "/arc son clear voix (French alias of voice): the voice says \"Idées claires\"")
    q.slash("son barrage 1234")
    check(name("barrage") == "Son n° 1234", "a number outside the list shows as is")
    q.run('Mock.ns.Hud.CycleSound("barrage", 1)')
    check(q.ns.db.soundKit.barrage is None, "and stays one of the choices: the next arrow goes back to the default")
    q.slash("")
    check(q.M.named["ArcanumOptions"]._shown is True and q.M.named["ArcanumOptions"]._w < 400,
          "the settings open, in a single column")
    no_errors(q, "sounds by their name")

    print("Frugality: game calls and display operations")
    def cost(setup, seconds=10.0):
        q = Game()
        q.buffed()
        setup(q)
        q.M.advance(1.0)
        q.M.resetCalls()
        q.M.ops = 0
        q.M.advance(seconds)
        return q.M.totalCalls() / seconds, q.M.ops / (seconds / 0.05), q

    def in_combat(q):
        q.fight()
        q.cast(AB)
        q.cast(AB)

    calls, ops, q = cost(in_combat)
    print("        in combat: %.0f game calls per second, %.1f display operations per frame" % (calls, ops))
    check(calls < 80, "in combat: fewer than 80 game calls per second")
    check((q.M.calls["C_UnitAuras.GetPlayerAuraBySpellID"] or 0) == 0 and (q.M.calls["C_UnitAuras.GetAuraDataBySpellName"] or 0) == 0,
          "in combat: no aura asked from the game (it hides them)")
    check(ops < 45, "in combat: fewer than 45 display operations per frame")
    calls, ops, q = cost(lambda q: None)
    print("        HUD hidden: %.0f game calls per second, %.1f display operations per frame" % (calls, ops))
    check(calls < 25, "HUD hidden: fewer than 25 game calls per second")
    check(ops < 2, "HUD hidden: almost no display operation")
    leaks = sorted(set(q.M.leaks.values()))
    check(len(leaks) == 0, "no unexpected global variable%s" % (leaks and ": %s" % ", ".join(leaks) or ""))

    print("Leaving combat: back to the truth")
    g.M.advance(3.0)
    g.M.expire()
    g.M.advance(0.3)
    check(g.S.stacks == 0, "window over")
    g.cast(AB)
    g.cast(AB)
    g.M.setCombat(False)
    g.M.advance(0.3)
    check(g.S.stacks == 2 and g.S.stacksSource == "aura", "charges read from the aura again")

    print("Button glow (client where the cost does not follow the procs)")
    h = Game(pre="Mock.costAware = false")
    h.fight()
    h.cast(AB)
    h.cast(AB)
    check(h.S.stacks == 2, "charges tracked without the help of the cost")
    h.M.advance(1.5)
    check(h.S.stacks == 2, "the cost, unchanged, does not reset the charges")
    h.run('Mock.overlays[25345] = true; Mock.fire("SPELL_ACTIVATION_OVERLAY_GLOW_SHOW", 25345)')
    h.M.advance(0.2)
    check(h.S.barrage.active and h.S.barrage.source == "glow", "Missile Barrage detected by the button glow")
    h.run('Mock.overlays[25345] = nil; Mock.fire("SPELL_ACTIVATION_OVERLAY_GLOW_HIDE", 25345)')
    h.M.advance(0.2)
    check(not h.S.barrage.active, "glow over: Missile Barrage removed")
    h.M.advance(15)
    check(h.S.stacks == 2, "15 s later: still 2 charges")
    h.M.advance(3)
    check(h.S.stacks == 0, "without any other signal, the charges drop at the end of the 18 s window")
    no_errors(h, "button glow")

    print("Blizzard's Cooldown Manager (tracked buffs)")
    c = Game(pre='Mock.costAware = false; Mock.trackBuff(41, 400588, "Barrage de projectiles"); '
                 'Mock.trackBuff(42, 11213, "Idées claires")')
    c.fight()
    c.M.advance(1.0)
    check(not c.S.barrage.active and not c.S.clear.active, "icons off: no proc")
    c.M.proc("Barrage de projectiles", 400589)
    c.M.advance(0.2)
    check(c.S.barrage.active and c.S.barrage.source == "manager", "Missile Barrage read from the Cooldown Manager icon")
    c.M.proc("Idées claires", 12536)
    c.M.advance(0.4)
    check(c.S.clear.active and c.S.clear.source == "manager", "Clearcasting read from the icon (talent 11213)")
    c.cast(AM)
    c.M.advance(0.7)
    check(not c.S.barrage.active, "icon off for half a second: Missile Barrage removed")
    c.slash("diag")
    check("barrage=éteint" in c.M.named["ArcanumDiag"].text, "the diagnostics show the Cooldown Manager icons")
    no_errors(c, "Cooldown Manager")

    print("Aura readable in combat (spell flagged \"never secret\")")
    k = Game(pre='Mock.neverSecret["Déflagration des Arcanes"] = true')
    k.fight()
    k.cast(AB)
    k.cast(AB)
    check(k.S.stacks == 2 and k.S.stacksSource == "aura", "charges read from the aura even in combat")
    k.cast(FIREBALL)
    check(k.S.stacks == 2, "Fireball: the aura keeps its 2 charges")
    k.run('Mock.auras["Déflagration des Arcanes"] = nil; Mock.fire("UNIT_AURA", "player", {})')
    k.M.advance(0.3)
    check(k.S.stacks == 0, "aura gone and known to be readable: 0 charge")
    no_errors(k, "readable aura")

    print("Cost missing when the spell is free (GetSpellPowerCost returns nil)")
    n = Game(pre="Mock.freeMeansNil = true")
    n.fight()
    n.cast(AB)
    n.M.proc("Barrage de projectiles", 400588)
    n.M.advance(0.3)
    check(n.S.barrage.active, "Missile Barrage detected when the game no longer announces a cost")
    no_errors(n, "nil cost")

    print("First Arcane Blast cast right before combat")
    r = Game()
    r.M.target = True
    r.run('Mock.fire("UNIT_SPELLCAST_SUCCEEDED", "player", "Cast-3-0", 400574)')   # the spell goes off…
    r.M.setCombat(True)                                                            # …combat starts
    r.run(BLAST_AURA % 1)
    r.M.advance(0.3)
    check(r.S.stacks == 1, "the charge is not lost")
    no_errors(r, "start of combat")

    print("Display, settings, demo")
    d = Game()
    d.slash("")
    check(d.M.named["ArcanumOptions"]._shown is True, "/arc opens the settings")
    said = d.slash("demo")
    check(d.S.demo is True and said == ["démonstration lancée (/arc demo pour l'arrêter)."], "/arc demo starts the demo")
    seen = set()
    for _ in range(240):
        d.M.advance(0.05)
        seen.add(d.S.stacks)
    check(seen == {0, 1, 2, 3, 4}, "the demo plays the whole cycle (0 to 4 charges)")
    d.slash("demo")
    d.M.advance(0.5)
    check(d.S.demo is False and d.S.stacks == 0, "demo stopped: state back to zero")
    d.slash("scale 130")
    hud = d.M.named["ArcanumHUD"]
    check(abs(d.ns.db.scale - 1.3) < 1e-6 and abs(hud._scale - 1.3) < 1e-6, "/arc scale 130")
    said = d.slash("lock")
    check(d.ns.db.locked is False and hud._mouse is True and said == ["HUD déverrouillé : fais-le glisser, puis /arc verrou."],
          "/arc lock unlocks the HUD")
    d.M.advance(0.5)
    group = d.ns.Hud.fight
    check(group._alpha > 0.9, "HUD unlocked: visible")
    said = d.slash("lock")
    d.M.advance(1.0)
    check(group._alpha < 0.05 and said == ["HUD verrouillé."], "HUD locked, out of combat, without a target: hidden")
    d.M.target = True
    d.run('Mock.fire("PLAYER_TARGET_CHANGED")')
    d.M.advance(1.0)
    check(group._alpha > 0.9, "hostile target: HUD visible")
    for key in ("showCharges", "showProcs", "showReminders", "showReminders", "enabled", "enabled"):
        d.run('Mock.ns.Set("%s", not Mock.ns.db.%s)' % (key, key))
        d.M.advance(0.2)
    d.slash("diag")
    report = d.M.named["ArcanumDiag"].text
    check("Déflagration des Arcanes" in report and "JOURNAL" in report, "/arc diag builds the report")
    d.fight()
    d.cast(AB)
    d.slash("diag")
    report = d.M.named["ArcanumDiag"].text
    check("charges 0 -> 1 (casts)" in report, "the diagnostics log keeps the state changes")
    said = d.slash("macro")
    check(len(d.M.macros) == 0 and said == ["les macros ne se modifient pas en combat. Réessaie hors combat."],
          "/arc macro refused in combat")
    d.M.setCombat(False)
    d.slash("macro")
    body = d.M.macros[1].body
    check(body == "#showtooltip Courroux des Arcanes\n/cast Eurêka !\n/stopcasting\n/cast Présence spirituelle\n/stopcasting\n/cast Courroux des Arcanes",
          "/arc macro: Eureka, Presence of Mind, Arcane Wrath, separated by /stopcasting, with the game's names")
    d.run('Mock.spells[12043].known = false; Mock.fire("SPELLS_CHANGED")')
    d.slash("macro")
    check(len(d.M.macros) == 1 and "Présence" not in d.M.macros[1].body, "run again: the macro is updated, not duplicated")
    d.slash("reset")
    check(d.ns.db.scale == 1 and d.ns.db.locked is True, "/arc reset restores the settings")
    help_fr = d.slash("aide")
    check(len(help_fr) == 12 and help_fr[0] == "/arc : ouvrir les réglages" and "/arc verrou : déplacer ou fixer le HUD" in help_fr
          and "/arc taille 120 : taille du HUD en pourcentage" in help_fr, "an unknown word prints the help, in French")
    check(d.slash("conseil") == help_fr and d.slash("aoe") == help_fr and d.S.aoe is None,
          "the removed commands (conseil, aoe) only print the help")
    no_errors(d, "display")

    print("Regressions found by the code review")
    r = Game()
    r.buffed()
    r.M.advance(1.2)
    hud = r.ns.Hud
    left, right = r.run("return Mock.ns.Hud.procs[1]"), r.run("return Mock.ns.Hud.procs[2]")
    stuck = 0
    for phase in range(10):   # the preview can end at any moment between two state passes
        r.M.advance(0.1 * phase + 0.03)
        r.run("Mock.ns.Hud.PreviewDecor()")
        r.M.advance(7)
        stuck += sum(1 for f in (left, right) if f.on or f.vis != 0 or f._shown or f.echo._alpha != 0)
    check(stuck == 0, "after a decoration preview the proc icons are fully hidden, whenever it ends (no flash at the next fight)")
    r.fight()
    r.cast(POM)
    r.M.advance(0.5)
    pom = hud.pomIcon
    r.run('Mock.ns.Set("enabled", false)')
    r.M.advance(1.5)
    r.cast(WRATH)             # Presence of Mind ends while the HUD is switched off
    r.M.advance(1.5)
    r.run('Mock.ns.Set("enabled", true)')
    r.M.advance(0.05)
    check(pom.on is False and pom.vis == 0 and pom._alpha == 0,
          "a buff that ended while the HUD was switched off does not flash when it is switched back on")

    r.run('Mock.ns.Set("enabled", false); Mock.lastKit = nil')
    before = len(r.sound_files())
    r.M.proc("Barrage de projectiles", 400588)
    r.M.advance(0.6)
    check(r.S.barrage.active and len(r.sound_files()) == before and r.M.lastKit is None,
          "HUD switched off: a proc plays no sound")
    r.run('Mock.ns.Set("enabled", true)')
    r.cast(AM)
    r.M.setCombat(False)
    r.M.advance(1.5)

    before = len(r.sound_files())
    r.M.proc("Idées claires", 12536)
    r.M.advance(0.5)
    check(r.S.clear.active and len(r.sound_files()) == before + 1, "a proc is announced once when it fires")
    r.slash("demo")
    r.M.advance(1)
    r.slash("demo")
    r.M.advance(1.5)
    check(r.S.clear.active and len(r.sound_files()) == before + 1,
          "found again after the demo stops: the same proc is not announced a second time")
    r.run('Mock.fire("PLAYER_ENTERING_WORLD", false, true)')
    r.M.advance(1.5)
    check(r.S.clear.active and len(r.sound_files()) == before + 1, "nor after a loading screen")
    no_errors(r, "review: display and sounds")

    d = Game()                # Arcane Intellect and armor missing: two reminders on screen
    d.M.advance(1.2)
    check(len(list(d.S.reminders.values())) == 2 and d.ns.Hud.prep._alpha > 0.9, "two reminders before the demo")
    d.slash("demo")
    d.M.advance(2.5)
    check(len(list(d.S.reminders.values())) == 0 and d.ns.Hud.prep._alpha == 0, "the demo clears the reminders from the screen")
    d.slash("demo")
    d.M.advance(2.5)
    check(len(list(d.S.reminders.values())) == 2, "they come back when it stops")
    no_errors(d, "review: demo")

    k = Game(pre="Mock.costAware = false")   # a client where only the button glow shows Missile Barrage
    k.fight()
    k.run('Mock.overlays[25345] = true; Mock.fire("SPELL_ACTIVATION_OVERLAY_GLOW_SHOW", 25345)')
    k.M.advance(0.3)
    before = len(k.sound_files())
    check(k.S.barrage.active and k.S.barrage.source == "glow", "Missile Barrage seen by the button glow")
    k.cast(AM, 0.3)           # the cast spends it; the game has not sent the end of the glow yet
    check(not k.S.barrage.active and len(k.sound_files()) == before,
          "glow still lit right after Arcane Missiles: the proc just spent is not announced again")
    k.run('Mock.fire("SPELL_ACTIVATION_OVERLAY_GLOW_HIDE", 25345)')
    k.M.advance(1.5)
    check(not k.S.barrage.active and len(k.sound_files()) == before, "and stays off once the glow ends")
    no_errors(k, "review: late glow")

    z = Game()
    frame = z.M.named["ArcanumHUD"]
    z.run('Mock.ns.db.point = { "CENTER", "CENTER", 100, -50 }; Mock.ns.Set("scale", 2)')
    check(frame._scale == 2 and frame._points[1][4] == 50 and frame._points[1][5] == -25,
          "the position is kept in screen units: doubling the size halves the anchor offsets, the HUD does not move")
    z.run('Mock.ns.Set("scale", 1)')
    check(frame._points[1][4] == 100 and frame._points[1][5] == -50, "back to normal size: same place")
    old = Game(pre='ArcanumDB = { version = 5, scale = 2, point = { "CENTER", "CENTER", 40, 10 }, showIdle = true, '
                   'idleAlpha = 0.5, learn = { checks = { burstGap = 0.2, pomChannel = "conservée", mana = "secret" } } }')
    check(old.ns.db.point[3] == 80 and old.ns.db.point[4] == 20,
          "a position saved by 1.x (in the HUD's scaled units) is converted, so the HUD stays where it was")
    check(old.ns.db.showIdle is None and old.ns.db.idleAlpha is None and old.ns.db.learn.checks.burstGap is None
          and old.ns.db.learn.checks.pomChannel is None and old.ns.db.learn.checks.mana == "secret",
          "the setting that showed nothing and the old burst observations are dropped; the rest is kept")
    no_errors(old, "review: saved position")

    print("The game's Options > AddOns list")
    o = Game()
    cats = list(o.M.settingsCategories.values())
    check(len(cats) == 1 and cats[0].name == "Arcanum" and o.M.named["ArcanumOptionsPanel"] is not None,
          "Arcanum registers one panel in the game's AddOns list")
    o.run('Mock.ns.Options.Refresh()')
    o.slash("")
    window = o.M.named["ArcanumOptions"]
    check(window._shown is True, "/arc still opens Arcanum's own window")
    o.run('Mock.ns.Set("showCharges", false); Mock.ns.Options.Refresh()')
    check(o.ns.db.showCharges is False, "a change refreshes both copies of the settings without error")
    o.fight()
    o.M.advance(0.3)
    no_errors(o, "game options panel")
    bare = Game(pre="Settings = nil")
    check(len(list(bare.M.settingsCategories.values())) == 0 and bare.ns.Options.category is None,
          "a client without that list gets no panel")
    bare.slash("")
    check(bare.M.named["ArcanumOptions"]._shown is True, "and /arc works there all the same")
    no_errors(bare, "client without the game's options list")

    print("English client")
    e = Game(pre='Mock.locale = "enUS"')
    check(e.run("return next(Mock.ns.L)") is None, "no translation is loaded: the strings stay in English")
    e.slash("")
    check(e.M.named["ArcanumOptions"]._shown is True, "/arc opens the settings window")
    name = lambda key: e.run('return Mock.ns.Hud.SoundName("%s")' % key)
    check(name("barrage") == "Default", "the Missile Barrage sound is named \"Default\"")
    e.run('Mock.ns.Hud.CycleSound("barrage", 1)')
    check(e.ns.db.soundKit.barrage == 18019 and name("barrage") == "Battle.net notification",
          "next arrow: \"Battle.net notification\"")
    help_en = e.slash("help")
    commands = ("/arc: ", "/arc demo: ", "/arc lock: ", "/arc scale 120: ", "/arc spread 150: ", "/arc decor: ", "/arc sounds: ",
                "/arc sound 3071: ", "/arc sound barrage voice: ", "/arc macro: ", "/arc diag: ", "/arc reset: ")
    check([line[:len(start)] for line, start in zip(help_en, commands)] == list(commands) and len(help_en) == len(commands),
          "the help lists the English commands")
    check(not any(word in line for line in help_en for word in ("verrou", "taille", "ecart", "sons", "voix", " : ")),
          "and none of their French aliases")
    hud = e.M.named["ArcanumHUD"]
    said = e.slash("lock")
    check(e.ns.db.locked is False and hud._mouse is True and said == ["HUD unlocked: drag it, then /arc lock."],
          "/arc lock unlocks the HUD")
    said = e.slash("lock")
    check(e.ns.db.locked is True and hud._mouse is False and said == ["HUD locked."], "/arc lock again locks it")
    e.slash("scale 130")
    check(abs(e.ns.db.scale - 1.3) < 1e-6 and abs(hud._scale - 1.3) < 1e-6, "/arc scale 130")
    e.slash("spread 120")
    left = e.run("for _, b in ipairs(Mock.ns.Hud.procs) do if b.def.key == 'clear' then return b end end")
    check(e.ns.db.spread == 120 and left._points[1][4] == -120, "/arc spread 120")
    said = e.slash("sound barrage")
    check(e.ns.db.soundKit.barrage is None and said == ["Missile Barrage: default sound."], "/arc sound barrage: back to the default sound")
    before = len(e.sound_files())
    said = e.slash("sounds")
    check(e.sound_files()[before:] == ["clear.ogg", "barrage.ogg"]
          and said == ["Clearcasting: game sound 4874.", "Missile Barrage: game sound 3333."],
          "/arc sounds plays both sounds and names them in English")
    said = e.slash("sound barrage 3071")
    check(e.ns.db.soundKit.barrage == 3071 and e.M.lastKit == 3071 and said == ["Missile Barrage: game sound 3071."],
          "/arc sound barrage 3071 picks that game sound")
    said = e.slash("sound barrage voice")
    check(e.ns.db.soundKit.barrage == "voice" and e.spoken()[-1] == "Missile Barrage" and name("barrage") == "Game voice"
          and said == ["Missile Barrage: game voice."], "/arc sound barrage voice: the game voice says \"Missile Barrage\"")
    e.slash("diag")
    report = e.M.named["ArcanumDiag"].text
    check("Arcanum" in report and "LOG" in report and "JOURNAL" not in report, "/arc diag builds the report, in English")
    e.slash("verrou")
    check(e.ns.db.locked is False, "French alias on an English client: /arc verrou")
    e.slash("verrou")
    e.slash("taille 120")
    check(abs(e.ns.db.scale - 1.2) < 1e-6 and abs(hud._scale - 1.2) < 1e-6, "French alias: /arc taille 120")
    e.slash("ecart 150")
    check(e.ns.db.spread == 150 and left._points[1][4] == -150, "French alias: /arc ecart 150")
    before, words = len(e.sound_files()), len(e.spoken())
    said = e.slash("sons")
    check(e.sound_files()[before:] == ["clear.ogg"] and e.spoken()[words:] == ["Missile Barrage"]
          and said == ["Clearcasting: game sound 4874.", "Missile Barrage: game voice."], "French alias: /arc sons")
    e.slash("son clear voix")
    check(e.ns.db.soundKit.clear == "voice" and e.spoken()[-1] == "Clearcasting", "French aliases: /arc son clear voix")
    e.M.advance(1.0)
    no_errors(e, "English client")

    print("Translations: every string has its French version")
    used, unknown = locale_keys_used()
    fr = Game()
    french = set(fr.run("local keys = {} for key in pairs(Mock.ns.L) do keys[#keys + 1] = key end return keys").values())
    missing, unused = sorted(used - french), sorted(french - used)
    check(len(used) > 0 and len(french) > 0 and not unknown,
          "the strings passed to L[...] are found in the sources (%d), the French ones in frFR.lua (%d)%s"
          % (len(used), len(french), unknown and "; lookups this check does not know: %s" % ", ".join(unknown) or ""))
    check(not missing, "every string the code passes to L[...] has a French translation%s"
          % (missing and "; missing from frFR.lua: %s" % ", ".join(repr(key) for key in missing) or ""))
    check(not unused, "every French translation is used by the code%s"
          % (unused and "; unused in frFR.lua: %s" % ", ".join(repr(key) for key in unused) or ""))

    print()
    if FAILS:
        print("%d check(s) failed:" % len(FAILS))
        for label in FAILS:
            print("  " + label)
        sys.exit(1)
    print("All tests pass.")


if __name__ == "__main__":
    main()
