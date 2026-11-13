-- Arcanum — the HUD: four zones around the character.
--
-- The HUD is centered on the character, and each piece of information has its own side:
--   * left: Clearcasting; right: Missile Barrage. A large icon (the proc's own), ringed in its color,
--     with the time left, flanked by a rune arc (the decoration). No proc: nothing.
--   * top, only while there are Arcane Blast charges: one crystal per charge, and below them the
--     bar of the 18 seconds of their window;
--   * above the charges, while active: Presence of Mind, Eureka and Arcane Power;
--   * bottom, out of combat: what is missing before pulling (Arcane Intellect, armor, water, food
--     and a mana gem to conjure).
-- The zones move away from the character with the "spread" setting.
--
-- Everything is animated by hand in a single OnUpdate (easing towards a target): no animation
-- groups to keep in sync, and rendering stays smooth whatever the frame rate.
local ADDON, ns = ...
local UI, State, Spells = ns.UI, ns.State, ns.Spells
local C = UI.C
local L = ns.L

local Hud = {}
ns.Hud = Hud

local sin, min, max, ceil = math.sin, math.min, math.max, math.ceil

local MAX_CHARGES = 4                 -- maximum Arcane Blast charges
local PROC = 64                       -- proc icons, left and right
local CR_W, CR_H, CR_GAP = 26, 34, 32 -- charge crystals, and the gap between two crystals
local BAR_W, BAR_H = 124, 4           -- charge window bar
local POM, POM_GAP = 46, 10           -- active buff icons (Presence of Mind, Eureka), and their gap
local REMIND, REMIND_GAP = 30, 38     -- pre-combat reminders

-- Procs shown, each with its own icon; side: -1 left of the character, 1 right; spell: the spell the
-- proc improves, whose icon is used if the game does not provide the proc's.
local PROCS = {
  { key = "clear", color = C.clear, spell = "blast", side = -1 },
  { key = "barrage", color = C.barrage, spell = "missiles", side = 1 },
}
-- Buffs shown above the charges while they are active; timed: with the time left.
local BUFFS = {
  { key = "pom", color = C.pom },
  { key = "eureka", color = C.gold, timed = true },
  { key = "power", color = C.arcane, timed = true },
}
-- The proc decoration: the proc alert artwork painted by Blizzard for Arcane Missiles, read from the
-- game files (file: its id). It is a large arc engraved with runes, twice as tall as it is wide (w, h,
-- in multiples of the icon size), placed on the outer side of the icon (offset) and flipped on the
-- right side. It keeps its purple for Missile Barrage; for Clearcasting it is turned grey then tinted
-- with the proc's color (grey). burst: its pop when it arrives.
local DECOR = { file = 449486, grey = { clear = true }, w = 2.0, h = 4.0, offset = 0.75, burst = 0.08 }

-- The sounds are game sounds ("kit": their id; "alt": the one played if this client does not know the
-- first). The player can pick others (settings, or /arc sound barrage 888), or drop their own files
-- into Sounds ("file"). "say": the word spoken when they chose the game voice.
local PROC_SOUND = {
  barrage = { kit = 3333, alt = 3175, file = "barrage", say = "Missile Barrage" },      -- Arcane Missiles, else the minimap ping
  clear = { kit = 4874, alt = 18019, file = "clear", say = "Clearcasting" },   -- Clearcasting (the spell), else the Battle.net notification
}
-- Game sounds offered by name in the settings. An id this client does not play is skipped.
local SOUNDS = {
  { 18019, "Battle.net notification" },
  { 3175, "Minimap ping" },
  { 3081, "Whisper" },
  { 878, "Quest complete" },
  { 888, "Level up" },
  { 8960, "Ready check" },
  { 8959, "Raid warning" },
  { 8459, "PvP queue ready" },
  { 12889, "Alarm clock" },
  { 3071, "Recklessness" },
  { 4874, "Clearcasting (the spell)" },
  { 3333, "Arcane Missiles" },
  { 3227, "Counterspell" },
  { 1642, "Arcane Intellect" },
}

local root, mover, fight, prep, bar, barText
local procs, buffs, crystals, reminders, halos, ghosts = {}, {}, {}, {}, {}, {}
local fightAlpha, prepAlpha = 0, 0
local fightHidden = true                               -- the combat group is fully transparent
local resting = false                                  -- resting in a city (read on each state pass, not each frame)
local shownFight, shownPrep = -1, -1                   -- last opacities given to the two groups
local hotBlend = 0
local crystalsFor, crystalsStill = -1, false           -- crystal state at the last draw
local crystalsShown = -1                               -- number of crystals shown
local barOn, barSeconds = false, nil
local previewUntil = -1                                -- decoration preview from the settings, until this time

-- ------------------------------------------------------------------ geometry
-- Everything is placed from the center of the HUD, which is the character.
local function spread()
  return ns.db.spread or 150
end

local function topY()
  return spread() * 0.9
end

local function bottomY()
  return -spread()
end

-- ------------------------------------------------------------------ halos (wave when a signal arrives)
local function spawnHalo(anchor, color, from, to, life)
  if not root or not anchor then return end
  local h
  for _, x in ipairs(halos) do
    if not x.t0 then h = x; break end
  end
  if not h then
    if #halos >= 4 then return end
    h = { tex = UI.Tex(fight, "BACKGROUND", "halo", color, 1, "ADD", -3) }
    h.tex:SetAlpha(0)
    halos[#halos + 1] = h
  end
  h.tex:ClearAllPoints()
  h.tex:SetPoint("CENTER", anchor, "CENTER", 0, 0)
  h.t0, h.life, h.from, h.to, h.color = GetTime(), life, from, to, color
end

local function animateHalos(now)
  for _, h in ipairs(halos) do
    if h.t0 then
      local t = (now - h.t0) / h.life
      if t >= 1 then
        h.t0 = nil
        h.tex:SetAlpha(0)
      else
        local e = 1 - (1 - t) * (1 - t)   -- slows down at the end of its course
        local size = h.from + (h.to - h.from) * e
        h.tex:SetSize(size, size)
        h.tex:SetVertexColor(h.color[1], h.color[2], h.color[3])
        h.tex:SetAlpha((1 - t) * 0.75)   -- the wave fades as it widens
      end
    end
  end
end

-- ------------------------------------------------------------------ charge crystals
local function makeCrystal(parent)
  local f = CreateFrame("Frame", nil, parent)
  f:SetSize(CR_W, CR_H)
  f.glow = UI.Tex(f, "BACKGROUND", "glow", C.arcane, 0, "ADD", -1)
  f.glow:SetPoint("CENTER")
  f.glow:SetSize(CR_W * 3, CR_H * 2.6)
  f.socket = UI.Tex(f, "BORDER", "diamond", C.socket, 0.95)
  f.socket:SetAllPoints()
  f.fill = UI.Tex(f, "ARTWORK", "diamond", C.arcane, 0)
  f.fill:SetPoint("CENTER")
  f.fill:SetSize(CR_W, CR_H)
  f.edge = UI.Tex(f, "OVERLAY", "diamond-edge", C.edge, 0.45)
  f.edge:SetAllPoints()
  f.spark = UI.Tex(f, "OVERLAY", "spark", C.arcaneHi, 0, "ADD", 2)
  f.spark:SetSize(20, 20)
  f.spark:SetPoint("CENTER", -5, 7)
  f.level, f.pop = 0, 0
  f:Hide()
  return f
end

-- Number of crystals to show: one per charge, none without a charge.
local function crystalCount()
  return min(MAX_CHARGES, max(0, State.stacks))
end

-- Lines up `shown` crystals, centered above the character; the others are hidden.
local function layoutCrystals(shown)
  crystalsShown = shown
  for i, f in ipairs(crystals) do
    if i <= shown and ns.db.showCharges then
      f:ClearAllPoints()
      f:SetPoint("CENTER", root, "CENTER", (i - (shown + 1) / 2) * CR_GAP, topY())
      f:Show()
    else
      f:Hide()
    end
  end
end

local function animateCrystals(dt)
  local n = State.stacks
  local full = n >= MAX_CHARGES   -- at maximum charges, the crystals brighten
  local shown = crystalCount()
  if shown ~= crystalsShown then layoutCrystals(shown) end
  local blend = UI.Approach(hotBlend, full and 1 or 0, dt, 6)
  -- at rest (nothing moves, nothing changes): no texture is touched
  if blend == hotBlend and n == crystalsFor and crystalsStill then return end
  hotBlend, crystalsFor = blend, n
  local still = true
  local r, g, b = UI.Mix(C.arcane, C.hot, hotBlend)
  for i, f in ipairs(crystals) do
    local on = i <= n
    f.level = UI.Approach(f.level, on and 1 or 0, dt, on and 18 or 9)
    f.pop = UI.Approach(f.pop, 0, dt, 7)
    local settled = f.pop == 0 and f.level == (on and 1 or 0)
    if not settled then still = false end
    -- a crystal that is off and at rest is already drawn. Target reached: the crystals brighten and
    -- stay still; continuous pulsing is reserved for what calls for an action (the procs).
    if not (settled and not on and f.drawnOff) then
      local scale = 1 + f.pop * 0.6
      f.fill:SetSize(CR_W * scale, CR_H * scale)
      f.fill:SetVertexColor(r, g, b, f.level)
      local gs = 1 + f.pop * 0.45
      f.glow:SetSize(CR_W * 3 * gs, CR_H * 2.6 * gs)
      f.glow:SetVertexColor(r, g, b, min(1, f.level * (0.40 + 0.25 * hotBlend) + f.pop * 0.55))
      local er, eg, eb = UI.Mix(C.edge, C.arcaneHi, f.level)
      f.edge:SetVertexColor(er, eg, eb, 0.45 + 0.55 * f.level)
      f.spark:SetVertexColor(1, 1, 1, f.level * (0.50 + 0.35 * hotBlend))
      f.drawnOff = settled and not on
    end
  end
  crystalsStill = still
end

-- ------------------------------------------------------------------ charge window
-- Under the crystals, a bar that drains over the 18 seconds of the window, and the seconds left.
local function makeBar(parent)
  local b = CreateFrame("StatusBar", nil, parent)
  b:SetSize(BAR_W, BAR_H)
  b:SetStatusBarTexture(UI.WHITE)
  b.fill = b:GetStatusBarTexture()
  b:SetMinMaxValues(0, 1)
  b:SetValue(1)
  local bg = UI.Tex(b, "BACKGROUND", nil, C.socket, 0.90)
  bg:SetPoint("TOPLEFT", -1, 1)
  bg:SetPoint("BOTTOMRIGHT", 1, -1)
  b:SetAlpha(0)
  return b
end

local function refreshBar(now)
  local on = ns.db.showCharges and State.stacks > 0
  if on ~= barOn then
    barOn = on
    bar:SetAlpha(on and 1 or 0)
    if not on then
      barSeconds = nil
      barText:SetText("")
    end
  end
  if not on then return end
  local expire = State.stacksExpire
  local left = expire and ceil(expire - now) or nil
  if left and left < 0 then left = 0 end
  if left ~= barSeconds then
    barSeconds = left
    barText:SetText(left and string.format("%d s", left) or "")
  end
end

local function animateBar(now)
  if not barOn then return end
  local r, g, b = UI.Mix(C.arcane, C.hot, hotBlend)
  local frac = 1   -- end unknown: full bar
  local expire, total = State.stacksExpire, State.stacksDur or State.Duration("blast")
  if expire and total and total > 0 then
    frac = min(1, max(0, (expire - now) / total))
    if frac < 0.25 then r, g, b = UI.MixTo(C.bad, r, g, b, frac / 0.25) end   -- the window is about to close
  end
  if frac ~= bar.frac then
    bar.frac = frac
    bar:SetValue(frac)
  end
  if bar.fill then bar.fill:SetVertexColor(r, g, b, 1) end
end

-- ------------------------------------------------------------------ round icons
-- A round icon: background, icon masked to a circle, cooldown swipe, colored edge, halo.
local function makeRound(parent, size, numbers, reverse)
  local b = CreateFrame("Frame", nil, parent)
  b:SetSize(size, size)
  b.size, b.pop = size, 0
  b.glow = UI.Tex(b, "BACKGROUND", "glow", C.arcane, 0, "ADD", -2)
  b.glow:SetPoint("CENTER")
  b.glow:SetSize(size * 2.0, size * 2.0)
  b.back = UI.Tex(b, "BACKGROUND", "circle", C.ink, 0.96, nil, 0)
  b.back:SetPoint("TOPLEFT", -2, 2)
  b.back:SetPoint("BOTTOMRIGHT", 2, -2)
  b.icon = b:CreateTexture(nil, "ARTWORK")
  b.icon:SetAllPoints()
  b.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
  if b.CreateMaskTexture then
    local mask = b:CreateMaskTexture()
    mask:SetTexture(UI.Media("circle"), "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
    mask:SetAllPoints(b.icon)
    b.icon:AddMaskTexture(mask)
  end
  local ok, cd = pcall(CreateFrame, "Cooldown", nil, b, "CooldownFrameTemplate")
  if not ok or not cd then cd = CreateFrame("Cooldown", nil, b) end
  cd:SetAllPoints()
  if cd.SetSwipeTexture then pcall(cd.SetSwipeTexture, cd, UI.Media("circle"), 0.02, 0.01, 0.06, 0.76) end
  if cd.SetSwipeColor then pcall(cd.SetSwipeColor, cd, 0.02, 0.01, 0.06, 0.76) end
  if cd.SetDrawEdge then pcall(cd.SetDrawEdge, cd, false) end
  if cd.SetDrawBling then pcall(cd.SetDrawBling, cd, false) end
  if cd.SetHideCountdownNumbers then pcall(cd.SetHideCountdownNumbers, cd, not numbers) end
  if reverse and cd.SetReverse then pcall(cd.SetReverse, cd, true) end
  if numbers and cd.GetCountdownFontString then
    local okF, fs = pcall(cd.GetCountdownFontString, cd)
    if okF and fs and fs.SetFont then pcall(fs.SetFont, fs, UI.FONT.body, 18, "OUTLINE") end
  end
  b.cd = cd
  b.over = CreateFrame("Frame", nil, b)
  b.over:SetAllPoints()
  b.over:SetFrameLevel(cd:GetFrameLevel() + 2)
  b.ring = UI.Tex(b.over, "OVERLAY", "circle-edge", C.edge, 0.9)
  b.ring:SetPoint("TOPLEFT", -2, 2)
  b.ring:SetPoint("BOTTOMRIGHT", 2, -2)
  return b
end

local function setCooldown(b, start, duration)
  if b._s == start and b._d == duration then return end
  b._s, b._d = start, duration
  pcall(b.cd.SetCooldown, b.cd, start, duration, 1)
end

-- ------------------------------------------------------------------ procs, left and right
local function refreshProcs()
  local show = ns.db.showProcs
  local preview = GetTime() < previewUntil   -- decoration preview: both icons show without a proc
  for _, f in ipairs(procs) do
    local p = State[f.def.key]
    local active = show and (p.active or preview) and true or false
    if active ~= f.on then
      f.on = active
      if active then
        f.icon:SetTexture(Spells.Icon(f.def.key) or Spells.Icon(f.def.spell) or 134400)
        f.pop = 1
        if ns.db.flash and f.decorDef then f.echoT0 = GetTime() end   -- the light wave: an echo of the decoration
        f:Show()
      end
    end
    if active then
      if p.active and p.expire and p.duration and p.duration > 0 then
        setCooldown(f, p.expire - p.duration, p.duration)
      else
        setCooldown(f, 0, 0)   -- duration unknown: full icon
      end
    end
  end
end

local function animateProcs(dt, now)
  for _, f in ipairs(procs) do
    if f.on or f.vis > 0 then
      f.vis = UI.Approach(f.vis, f.on and 1 or 0, dt, f.on and 14 or 10)
      f.pop = UI.Approach(f.pop, 0, dt, 7)
      if f.vis ~= f.shown then
        f.shown = f.vis
        f:SetAlpha(f.vis)
      end
      if f.vis <= 0 and not f.on then
        f:Hide()
      else
        local c = f.def.color
        local pulse = 0.5 + 0.5 * sin(now * 4.4)
        f.glow:SetVertexColor(c[1], c[2], c[3], min(1, 0.30 + 0.16 * pulse + f.pop * 0.5))
        if f.pop ~= f.popDrawn then   -- sizes only move while the icon pops
          f.popDrawn = f.pop
          local s = PROC * (1.9 + f.pop * 0.7)   -- (no SetScale: it would move the icon)
          f.glow:SetSize(s, s)
          if f.decorDef then
            local k = 1 + f.pop * f.decorDef.burst   -- the decoration pops with the proc
            f.decor:SetSize(f.decorW * k, f.decorH * k)
          end
        end
        local d = f.decorDef
        if d then
          f.decor:SetAlpha(0.60 + 0.40 * pulse)   -- and pulses gently
          -- the light wave: an echo of the decoration, which expands and fades
          if f.echoT0 then
            local t = (now - f.echoT0) / 0.6
            if t >= 1 then
              f.echoT0 = nil
              f.echo:SetAlpha(0)
            else
              local e = 1 + 0.45 * (1 - (1 - t) * (1 - t))   -- slows down at the end of its course
              f.echo:SetSize(f.decorW * e, f.decorH * e)
              f.echo:SetAlpha((1 - t) * 0.8)
            end
          end
        end
      end
    end
  end
end

-- ------------------------------------------------------------------ active buffs, above the charges
-- Presence of Mind (the next spell will be instant) and Eureka (with its time left): their icon
-- stays shown while the buff is active. Only one: centered; both: side by side.
local function layoutBuffs()
  local n, i = 0, 0
  for _, f in ipairs(buffs) do
    if f.on then n = n + 1 end
  end
  for _, f in ipairs(buffs) do
    if f.on then
      i = i + 1
      f:ClearAllPoints()
      f:SetPoint("CENTER", root, "CENTER", (i - (n + 1) / 2) * (POM + POM_GAP), topY() + CR_H / 2 + POM / 2 + 12)
    end
  end
end

local function refreshBuffs()
  local show = ns.db.showProcs
  local changed = false
  for _, f in ipairs(buffs) do
    local p = State[f.def.key]
    local on = show and p.active and true or false
    if on ~= f.on then
      f.on, changed = on, true
      if on then
        f.icon:SetTexture(Spells.Icon(f.def.key) or 134400)
        f.pop = 1
      end
    end
    if on then
      if p.expire and p.duration and p.duration > 0 then
        setCooldown(f, p.expire - p.duration, p.duration)
      else
        setCooldown(f, 0, 0)   -- no duration (Presence of Mind): full icon
      end
    end
  end
  if not changed then return end
  layoutBuffs()
  if ns.db.flash then
    for _, f in ipairs(buffs) do
      if f.on and f.pop == 1 then spawnHalo(f, f.def.color, POM, POM + 80, 0.45) end   -- the one that just arrived
    end
  end
end

local function animateBuffs(dt, now)
  local pulse = 0.5 + 0.5 * sin(now * 4.4)
  for _, f in ipairs(buffs) do
    if f.on or f.vis > 0 then
      f.vis = UI.Approach(f.vis, f.on and 1 or 0, dt, 12)
      f.pop = UI.Approach(f.pop, 0, dt, 7)
      if f.vis ~= f.shown then
        f.shown = f.vis
        f:SetAlpha(f.vis)
      end
      if f.vis > 0 then
        local c = f.def.color
        f.glow:SetVertexColor(c[1], c[2], c[3], min(1, 0.32 + 0.18 * pulse + f.pop * 0.4))
        if f.pop ~= f.popDrawn then
          f.popDrawn = f.pop
          local s = POM * (2.0 + f.pop * 0.8)
          f.glow:SetSize(s, s)
        end
      end
    end
  end
end

-- ------------------------------------------------------------------ pre-combat reminders, at the bottom
local remindersShown = 0
local function refreshReminders(force)
  local list = State.reminders
  local n = #list
  local changed = force or n ~= remindersShown
  for i, f in ipairs(reminders) do
    if f.key ~= list[i] then changed = true end
  end
  if not changed then return end   -- the list has not changed: nothing to reposition
  remindersShown = n
  for i, f in ipairs(reminders) do
    local key = list[i]
    f.key = key
    if key then
      f.icon:SetTexture((key == "gemspell" and Spells.IconOf(Spells.GemSpell()) or Spells.Icon(key)) or 134400)
      f:ClearAllPoints()
      f:SetPoint("CENTER", root, "CENTER", (i - (n + 1) / 2) * REMIND_GAP, bottomY())
      f:Show()
    else
      f:Hide()
    end
  end
end

local function animateReminders(now)
  local pulse = 0.5 + 0.5 * sin(now * 3.0)
  for _, f in ipairs(reminders) do
    if f.key then f.glow:SetVertexColor(C.amber[1], C.amber[2], C.amber[3], 0.30 + 0.30 * pulse) end
  end
end

-- ------------------------------------------------------------------ proc decoration
-- Gives each proc its decoration, or none when the setting is off.
local function applyDecor()
  local d = ns.db.decor and DECOR or nil
  for _, f in ipairs(procs) do
    f.decorDef = d
    f.echoT0 = nil
    if d then
      local grey = d.grey[f.def.key] == true
      local c = grey and f.def.color or C.text   -- (the original arc keeps its colors; grey, it takes the proc's)
      f.decorW, f.decorH = PROC * d.w, PROC * d.h
      -- the decoration, and its echo: the same image, for the light wave when the proc arrives
      for _, tex in ipairs({ f.decor, f.echo }) do
        tex:SetTexture(d.file)
        tex:SetDesaturated(grey)
        tex:SetSize(f.decorW, f.decorH)
        tex:ClearAllPoints()
        tex:SetPoint("CENTER", f, "CENTER", f.def.side * PROC * d.offset, 0)
        tex:SetVertexColor(c[1], c[2], c[3], 1)
        if f.def.side > 0 then
          tex:SetTexCoord(1, 0, 0, 1)   -- mirror: the arc sits on the outer side
        else
          tex:SetTexCoord(0, 1, 0, 1)
        end
        tex:Show()
      end
      f.decor:SetAlpha(1)
    else
      f.decor:Hide()
      f.echo:Hide()
    end
    f.echo:SetAlpha(0)   -- (the echo only shows when a proc arrives)
  end
end

-- Decoration preview, from the settings: both proc icons show for a few seconds.
function Hud.PreviewDecor()
  if not root then return end
  previewUntil = GetTime() + 4
  Hud.Refresh()
  -- (the icons may already be shown by the previous preview: the wave restarts anyway)
  for _, f in ipairs(procs) do
    if f.on then
      f.pop = 1
      if ns.db.flash and f.decorDef then f.echoT0 = GetTime() end
    end
  end
end

-- ------------------------------------------------------------------ layout
function Hud.Layout()
  if not root then return end
  local sp = spread()
  root:SetSize(2 * sp + PROC + 24, 2 * sp + 2 * POM + 60)
  for _, f in ipairs(procs) do
    f:ClearAllPoints()
    f:SetPoint("CENTER", root, "CENTER", f.def.side * sp, 0)
  end
  applyDecor()
  layoutCrystals(crystalCount())
  bar:ClearAllPoints()
  bar:SetPoint("CENTER", root, "CENTER", 0, topY() - CR_H / 2 - 10)
  layoutBuffs()
  refreshReminders(true)
  -- markers shown when the HUD is unlocked: where each zone will land
  local spots = { { -sp, 0, PROC }, { sp, 0, PROC }, { 0, topY(), CR_H }, { 0, bottomY(), REMIND } }
  for i, g in ipairs(ghosts) do
    g:ClearAllPoints()
    g:SetPoint("CENTER", root, "CENTER", spots[i][1], spots[i][2])
    g:SetSize(spots[i][3], spots[i][3])
  end
end

-- ------------------------------------------------------------------ position, locking
-- The position is saved in screen units. A frame's anchor offsets are in its own scaled units, hence the
-- division: without it, changing the size would move a HUD that has been dragged.
local function applyPosition()
  local p, scale = ns.db.point, ns.db.scale or 1
  root:SetScale(scale)
  root:ClearAllPoints()
  root:SetPoint(p[1], UIParent, p[2], p[3] / scale, p[4] / scale)
end

local function applyLock()
  local unlocked = not ns.db.locked
  root:EnableMouse(unlocked)
  mover:SetShown(unlocked)
end

local function makeMover()
  mover = CreateFrame("Frame", nil, root)
  mover:SetAllPoints()
  mover:SetFrameLevel(root:GetFrameLevel() + 20)
  UI.Panel(mover, C.arcane, 0.10, "BACKGROUND", 0)
  local text = UI.Text(mover, 11, C.arcaneHi, UI.FONT.title)
  text:SetPoint("CENTER", 0, 0)
  text:SetText(L["Drag me · /arc lock"])
  local tints = { C.clear, C.barrage, C.arcane, C.amber }
  for i = 1, 4 do
    ghosts[i] = UI.Tex(mover, "ARTWORK", "circle", tints[i], 0.35)
  end
  mover:Hide()
  root:SetMovable(true)
  root:SetClampedToScreen(true)
  root:RegisterForDrag("LeftButton")
  root:SetScript("OnDragStart", function(self)
    if not ns.db.locked and not (InCombatLockdown and InCombatLockdown()) then self:StartMoving() end
  end)
  root:SetScript("OnDragStop", function(self)
    self:StopMovingOrSizing()
    local point, _, rel, x, y = self:GetPoint(1)
    local scale = ns.db.scale or 1
    if point and x and y then ns.db.point = { point, rel or point, x * scale, y * scale } end
  end)
end

-- ------------------------------------------------------------------ sounds
-- Plays a game sound by its id; false if the game plays nothing (id unknown to this client).
local function playKit(id)
  local ok, played = pcall(PlaySound, id, "Master")
  return ok and played and true or false
end
Hud.PlayKit = playKit

-- The game voice (text-to-speech): it says the word instead of playing a sound. Returns the id of the
-- voice set in the game, else of the first one installed; nil if this client has none.
local function voiceID()
  if not (C_VoiceChat and C_VoiceChat.SpeakText and C_VoiceChat.GetTtsVoices) then return nil end
  local ok, voices = pcall(C_VoiceChat.GetTtsVoices)
  if not ok or type(voices) ~= "table" or not voices[1] then return nil end
  local wanted
  if C_TTSSettings and C_TTSSettings.GetVoiceOptionID then
    local okW, id = pcall(C_TTSSettings.GetVoiceOptionID, 0)
    if okW and type(id) == "number" then wanted = id end
  end
  local first
  for _, v in ipairs(voices) do
    if type(v) == "table" and type(v.voiceID) == "number" then
      if v.voiceID == wanted then return wanted end
      first = first or v.voiceID
    end
  end
  return first
end

local function speak(text)
  local id = voiceID()
  if not id then return false end
  return (pcall(C_VoiceChat.SpeakText, id, text, 0, 100)) and true or false
end

function Hud.CanSpeak()
  return voiceID() ~= nil
end

-- In order: the player's choice (a game sound, or the voice); else their file dropped into Sounds;
-- else the original sound, then its fallback. Returns the id played, "voice", "file", or nil.
local function playSound(def, always)
  if not (always or ns.db.sound) then return nil end
  local chosen = type(ns.db.soundKit) == "table" and ns.db.soundKit[def.file]
  if chosen == "voice" then
    if speak(L[def.say]) then return "voice" end
  elseif chosen and playKit(chosen) then
    return chosen
  end
  local ok, played = pcall(PlaySoundFile, "Interface\\AddOns\\" .. ADDON .. "\\Sounds\\" .. def.file .. ".ogg", "Master")
  if ok and played then return "file" end
  if playKit(def.kit) then return def.kit end
  if def.alt and playKit(def.alt) then return def.alt end
  return nil
end

-- The name of the sound chosen for a proc ("clear" or "barrage"), for the settings.
function Hud.SoundName(key)
  local v = type(ns.db.soundKit) == "table" and ns.db.soundKit[key]
  if not v then return L["Default"] end
  if v == "voice" then return L["Game voice"] end
  for _, s in ipairs(SOUNDS) do
    if s[1] == v then return L[s[2]] end
  end
  return string.format(L["Sound #%d"], v)
end

function Hud.PreviewSound(key)
  local def = PROC_SOUND[key]
  return def and playSound(def, true) or nil
end

-- Moves to the next choice (dir = 1) or the previous one (-1) and plays it. The choices: the default
-- sound, the named sounds, the game voice if this client has one, and the number typed with
-- /arc sound if it is not in the list. A sound the game does not play is skipped.
function Hud.CycleSound(key, dir)
  local def = PROC_SOUND[key]
  if not def then return end
  if type(ns.db.soundKit) ~= "table" then ns.db.soundKit = {} end
  local cur = ns.db.soundKit[key] or false
  local list, at, listed = { false }, 1, cur == false
  for _, s in ipairs(SOUNDS) do list[#list + 1] = s[1] end
  if Hud.CanSpeak() then list[#list + 1] = "voice" end
  for i, v in ipairs(list) do
    if v == cur then at, listed = i, true end
  end
  if not listed then
    list[#list + 1] = cur
    at = #list
  end
  for step = 1, #list do
    local v = list[(at - 1 + dir * step) % #list + 1]
    if v == false then
      ns.db.soundKit[key] = nil
      playSound(def, true)
      return
    elseif v == "voice" then
      if speak(L[def.say]) then
        ns.db.soundKit[key] = v
        return
      end
    elseif playKit(v) then
      ns.db.soundKit[key] = v
      return
    end
  end
end

-- /arc sounds: plays both sounds, one after the other, and says which one is played.
function Hud.TestSounds()
  local list = {
    { PROC_SOUND.clear, L["Clearcasting"] },
    { PROC_SOUND.barrage, L["Missile Barrage"] },
  }
  for i, item in ipairs(list) do
    local function play()
      local what = playSound(item[1], true)
      local text = what == "file" and L["your file"] or what == "voice" and L["game voice"]
        or what and string.format(L["game sound %d"], what) or L["no sound"]
      ns.Print(string.format(L["%s: %s."], item[2], text))
    end
    if i > 1 and C_Timer and C_Timer.After then C_Timer.After((i - 1) * 1.5, play) else play() end
  end
end

-- ------------------------------------------------------------------ display loop
-- The procs, the charges and the active buffs: visible as soon as there is something to track, while the
-- HUD is unlocked, and during a decoration preview.
local function wantedFight()
  local db = ns.db
  if not db.enabled then return 0 end
  return (not db.locked or State.live or GetTime() < previewUntil) and 1 or 0
end

-- The group has just become invisible, or something ended while it was: icons that are no longer wanted go
-- straight to their hidden state. Their fade only runs while the group is visible, so without this they
-- would flash at the start of the next fight.
local function settleHidden()
  for _, f in ipairs(procs) do
    if not f.on and f.vis > 0 then
      f.vis, f.shown, f.echoT0 = 0, 0, nil
      f:SetAlpha(0)
      f.echo:SetAlpha(0)
      f:Hide()
    end
  end
  for _, f in ipairs(buffs) do
    if not f.on and f.vis > 0 then
      f.vis, f.shown = 0, 0
      f:SetAlpha(0)
    end
  end
  for _, h in ipairs(halos) do
    if h.t0 then
      h.t0 = nil
      h.tex:SetAlpha(0)
    end
  end
end

-- The reminders: visible out of combat as soon as something is missing, except when resting in town
-- (there they come back when a hostile target is selected).
local function wantedPrep()
  local db = ns.db
  if not db.enabled or db.showReminders == false or #State.reminders == 0 then return 0 end
  return (State.live or not resting) and 1 or 0
end

local function onUpdate(_, dt)
  local now = GetTime()
  fightAlpha = UI.Approach(fightAlpha, wantedFight(), dt, 9)
  if fightAlpha ~= shownFight then
    shownFight = fightAlpha
    fight:SetAlpha(fightAlpha)
  end
  prepAlpha = UI.Approach(prepAlpha, wantedPrep(), dt, 9)
  if prepAlpha ~= shownPrep then
    shownPrep = prepAlpha
    prep:SetAlpha(prepAlpha)
  end
  if prepAlpha > 0 then animateReminders(now) end
  if fightAlpha <= 0 then   -- nothing to track: nothing else to do this frame
    if not fightHidden then
      fightHidden = true
      settleHidden()
    end
    return
  end
  fightHidden = false
  if ns.db.showCharges then
    animateCrystals(dt)
    animateBar(now)
  end
  animateProcs(dt, now)
  animateBuffs(dt, now)
  animateHalos(now)
end

function Hud.Refresh()
  if not root then return end
  local now = GetTime()
  refreshBar(now)
  refreshProcs()
  refreshBuffs()
  refreshReminders()
  if #State.reminders > 0 then resting = IsResting and IsResting() and true or false end
  if fightHidden then settleHidden() end
end

function Hud.Build()
  if root then return root end
  root = CreateFrame("Frame", "ArcanumHUD", UIParent)
  root:SetSize(400, 400)
  root:SetFrameStrata("MEDIUM")

  -- Two groups, each with its own opacity: combat (procs, charges, active buffs) and preparation
  -- (reminders).
  fight = CreateFrame("Frame", nil, root)
  fight:SetAllPoints()
  fight:SetAlpha(0)
  prep = CreateFrame("Frame", nil, root)
  prep:SetAllPoints()
  prep:SetAlpha(0)
  local level = root:GetFrameLevel()

  for i, def in ipairs(PROCS) do
    local f = makeRound(fight, PROC, true, true)   -- reversed swipe: it grows as the proc runs out
    f.def, f.vis, f.on = def, 0, false
    f.decor = UI.Tex(f, "BACKGROUND", nil, def.color, 1, nil, -1)
    f.decor:SetPoint("CENTER")
    f.echo = UI.Tex(f, "BACKGROUND", nil, def.color, 1, "ADD", -1)
    f.echo:SetPoint("CENTER")
    f.echo:SetAlpha(0)
    f:SetFrameLevel(level + 4)
    f.ring:SetVertexColor(def.color[1], def.color[2], def.color[3], 1)
    f:SetAlpha(0)
    f:Hide()
    procs[i] = f
  end

  for i = 1, MAX_CHARGES do
    crystals[i] = makeCrystal(fight)
    crystals[i]:SetFrameLevel(level + 5)
  end
  bar = makeBar(fight)
  barText = UI.Text(bar, 12, C.muted, UI.FONT.body, "OUTLINE")
  barText:SetPoint("LEFT", bar, "RIGHT", 8, 0)

  for i, def in ipairs(BUFFS) do
    local f = makeRound(fight, POM, def.timed, def.timed)   -- (Eureka: time left in digits, growing swipe)
    f.def, f.vis, f.on = def, 0, false
    f:SetFrameLevel(level + 5)
    f.icon:SetTexture(134400)
    f.ring:SetVertexColor(def.color[1], def.color[2], def.color[3], 1)
    if def.timed and f.cd.GetCountdownFontString then
      local okF, fs = pcall(f.cd.GetCountdownFontString, f.cd)
      if okF and fs and fs.SetFont then pcall(fs.SetFont, fs, UI.FONT.body, 15, "OUTLINE") end
    end
    f:SetPoint("CENTER", root, "CENTER", 0, 0)
    f:SetAlpha(0)
    buffs[i] = f
  end

  for i = 1, 5 do
    local f = makeRound(prep, REMIND, false)
    f.ring:SetVertexColor(C.amber[1], C.amber[2], C.amber[3], 1)
    f:Hide()
    reminders[i] = f
  end

  makeMover()
  applyPosition()
  applyLock()
  Hud.Layout()

  local driver = CreateFrame("Frame")
  driver:SetScript("OnUpdate", function(self, dt)
    local ok, err = pcall(onUpdate, self, dt)
    if not ok then ns.Report(err) end
  end)
  Hud.root, Hud.fight, Hud.prep = root, fight, prep
  Hud.procs, Hud.crystals, Hud.reminders, Hud.bar, Hud.barText = procs, crystals, reminders, bar, barText
  Hud.buffs, Hud.pomIcon, Hud.eurekaIcon, Hud.powerIcon = buffs, buffs[1], buffs[2], buffs[3]
  return root
end

-- ------------------------------------------------------------------ wiring
ns:On("START", function() Hud.Build() end)

ns:On("STATE", Hud.Refresh)
ns:On("SPELLS", function() Hud.Layout() end)
ns:On("DEMO", function() Hud.Layout() end)

ns:On("SETTINGS", function(key)
  if not root then return end
  applyPosition()
  applyLock()
  Hud.Layout()
  Hud.Refresh()
  if key == "decor" and ns.db.decor then Hud.PreviewDecor() end   -- the decoration was just turned on: show it
end)

ns:On("STACKS", function(n, old)
  if not root then return end
  for i = (old or 0) + 1, n do
    if crystals[i] then crystals[i].pop = 1 end   -- the crystal pops: no need for a wave on top
  end
end)

-- A proc arrives: its sound plays. Without the decoration, a round wave leaves its icon; with the
-- decoration, the wave is an echo of the arc (see refreshProcs).
ns:On("PROC", function(key)
  if not root then return end
  local def = PROC_SOUND[key]
  if not def or not ns.db.enabled then return end
  -- found again after a loading screen: already announced (the demo, which starts with a reset, plays its own)
  if not State.demo and GetTime() < (State.quietUntil or 0) then return end
  if ns.db.flash and ns.db.showProcs then
    for _, f in ipairs(procs) do
      if f.def.key == key and not f.decorDef then spawnHalo(f, f.def.color, PROC, PROC + 80, 0.45) end
    end
  end
  playSound(def)   -- (in the demo as well: it shows what a proc sounds like)
end)
