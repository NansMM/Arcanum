-- Arcanum — le HUD : quatre zones autour du personnage.
--
-- Le HUD est centré sur le personnage, et chaque information a son côté :
--   * à gauche : les Idées claires ; à droite : le Barrage de projectiles. Une grande icône (celle du
--     proc), cerclée de sa couleur, avec le temps restant, dans un décor au choix. Pas de proc : rien.
--   * en haut, seulement quand il y a des charges de Déflagration des Arcanes : un cristal par charge
--     visée (un de plus quand le jeu en offre une), et dessous la barre des 18 secondes de leur fenêtre ;
--   * au-dessus des charges, tant qu'elle est active : la Présence spirituelle ;
--   * en bas, hors combat : ce qu'il manque avant d'engager (Intelligence des Arcanes, armure, eau,
--     nourriture et gemme de mana à invoquer).
-- Les zones s'écartent du personnage avec le réglage « écartement ».
--
-- Tout est animé à la main dans un seul OnUpdate (approche douce vers une cible) : pas de groupes
-- d'animation à synchroniser, et le rendu reste fluide quel que soit le nombre d'images par seconde.
local ADDON, ns = ...
local UI, State, Spells = ns.UI, ns.State, ns.Spells
local C = UI.C
local L = ns.L

local Hud = {}
ns.Hud = Hud

local sin, min, max, ceil = math.sin, math.min, math.max, math.ceil

local PROC = 64                       -- icônes de proc, à gauche et à droite
local CR_W, CR_H, CR_GAP = 26, 34, 32 -- cristaux de charge, et l'écart entre deux cristaux
local BAR_W, BAR_H = 124, 4           -- barre de la fenêtre des charges
local POM = 46                        -- icône de la Présence spirituelle
local REMIND, REMIND_GAP = 30, 38     -- rappels avant le combat

-- Procs affichés, avec leur propre icône ; side : -1 à gauche du personnage, 1 à droite ; spell : le sort
-- que le proc améliore, dont l'icône sert si le jeu ne donne pas celle du proc.
local PROCS = {
  { key = "clear", color = C.clear, spell = "blast", side = -1 },
  { key = "barrage", color = C.barrage, spell = "missiles", side = 1 },
}
-- Décors dessinés autour d'un proc, à sa couleur, tant qu'il est affiché. file : la texture ; size : sa
-- taille, en nombre de fois celle de l'icône ; flip : retournée du côté droit ; spin : elle tourne
-- (radians par seconde) ; pulse : elle bat ; burst : son bond à l'arrivée du proc.
local DECORS = {
  croissants = { file = "decor-crescent", size = 2.6, flip = true, burst = 0.10 },
  losange = { file = "decor-lozenge", size = 2.1, burst = 0.14 },
  runes = { file = "decor-runes", size = 2.0, spin = 0.35, burst = 0.14 },
  eclat = { file = "decor-rays", size = 2.2, pulse = true, burst = 0.35 },
}
Hud.DECORS = { "aucun", "croissants", "losange", "runes", "eclat" }
Hud.DECOR_NAME = { aucun = "Aucun", croissants = "Croissants", losange = "Losange", runes = "Anneau de runes", eclat = "Éclat" }

-- Les sons sont des sons du jeu (« kit » : leur identifiant ; « alt » : celui joué si ce client ne connaît
-- pas le premier). Le joueur peut en choisir d'autres (réglages, ou /arc son barrage 888), ou déposer ses
-- propres fichiers dans Sounds (« file »). « say » : le mot prononcé quand il a choisi la voix du jeu.
local PROC_SOUND = {
  barrage = { kit = 3333, alt = 3175, file = "barrage", say = "Barrage" },      -- Projectiles des Arcanes, sinon le ping de la mini-carte
  clear = { kit = 4874, alt = 18019, file = "clear", say = "Idées claires" },   -- Idées claires (le sort), sinon la notification Battle.net
}
local SOUND_DEF = PROC_SOUND
-- Sons du jeu proposés par leur nom dans les réglages. Un identifiant que ce client ne joue pas est sauté.
local SOUNDS = {
  { 18019, "Notification Battle.net" },
  { 3175, "Ping de la mini-carte" },
  { 3081, "Message privé" },
  { 878, "Quête terminée" },
  { 888, "Montée de niveau" },
  { 8960, "Appel de préparation" },
  { 8959, "Alerte de raid" },
  { 8459, "File JcJ prête" },
  { 12889, "Réveil" },
  { 3071, "Témérité" },
  { 4874, "Idées claires (le sort)" },
  { 3333, "Projectiles des Arcanes" },
  { 3227, "Contresort" },
  { 1642, "Intelligence des Arcanes" },
}

local root, mover, fight, prep, bar, barText, pomIcon
local procs, crystals, reminders, halos, ghosts = {}, {}, {}, {}, {}
local fightAlpha, prepAlpha = 0, 0
local shownFight, shownPrep = -1, -1                   -- dernières opacités données aux deux groupes
local hotBlend, pomBlend, pomShown = 0, 0, -1
local crystalsFor, crystalsAim, crystalsStill = -1, -1, false   -- état des cristaux au dernier dessin
local crystalsShown = -1                               -- nombre de cristaux affichés
local barOn, barSeconds = false, nil
local previewUntil = -1                                -- aperçu du décor demandé depuis les réglages, jusqu'à cette date

-- ------------------------------------------------------------------ géométrie
-- Tout se place depuis le centre du HUD, qui est le personnage.
local function spread()
  return ns.db.spread or 150
end

local function topY()
  return spread() * 0.9
end

local function bottomY()
  return -spread()
end

-- ------------------------------------------------------------------ halos (onde à l'arrivée d'un signal)
local function spawnHalo(anchor, color, from, to, life)
  if not root or not anchor then return end
  local h
  for _, x in ipairs(halos) do
    if not x.t0 then h = x; break end
  end
  if not h then
    if #halos >= 4 then return end
    h = { tex = UI.Tex(fight, "BACKGROUND", "halo", color, 0, "ADD", -3) }
    halos[#halos + 1] = h
  end
  h.tex:ClearAllPoints()
  h.tex:SetPoint("CENTER", anchor, "CENTER", 0, 0)
  h.t0, h.life, h.from, h.to, h.color = GetTime(), life or 0.5, from, to, color
end

local function animateHalos(now)
  for _, h in ipairs(halos) do
    if h.t0 then
      local t = (now - h.t0) / h.life
      if t >= 1 then
        h.t0 = nil
        h.tex:SetAlpha(0)
      else
        local e = 1 - (1 - t) * (1 - t)   -- ralentit en fin de course
        local size = h.from + (h.to - h.from) * e
        h.tex:SetSize(size, size)
        h.tex:SetVertexColor(h.color[1], h.color[2], h.color[3], (1 - t) * 0.75)
        h.tex:SetAlpha(1)
      end
    end
  end
end

-- ------------------------------------------------------------------ cristaux de charge
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

-- Nombre de cristaux à montrer : aucun sans charge ; sinon un par charge visée, et un de plus quand le
-- jeu offre une charge (Déflagration gratuite).
local function crystalCount()
  local n = State.stacks
  return n > 0 and min(4, max(State.Target(), n)) or 0
end

-- Aligne `shown` cristaux, centrés au-dessus du personnage ; les autres sont cachés.
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
  local target = State.Target()
  local full = n >= target
  local shown = crystalCount()
  if shown ~= crystalsShown then layoutCrystals(shown) end
  local blend = UI.Approach(hotBlend, full and 1 or 0, dt, 6)
  -- au repos (rien ne bouge, rien ne change) : on ne touche à aucune texture
  if blend == hotBlend and n == crystalsFor and target == crystalsAim and crystalsStill then return end
  hotBlend, crystalsFor, crystalsAim = blend, n, target
  local still = true
  local r, g, b = UI.Mix(C.arcane, C.hot, hotBlend)
  for i, f in ipairs(crystals) do
    local on = i <= n
    f.level = UI.Approach(f.level, on and 1 or 0, dt, on and 18 or 9)
    f.pop = UI.Approach(f.pop, 0, dt, 7)
    local settled = f.pop == 0 and f.level == (on and 1 or 0)
    if not settled then still = false end
    -- un cristal éteint et au repos est déjà dessiné. Cible atteinte : les cristaux s'éclaircissent et
    -- restent fixes ; ce qui bat en continu est réservé à ce qui demande une action (les procs).
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

-- ------------------------------------------------------------------ fenêtre des charges
-- Sous les cristaux, une barre qui se vide pendant les 18 secondes de la fenêtre, et les secondes restantes.
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
  local frac = 1   -- fin inconnue : barre pleine
  local expire, total = State.stacksExpire, State.stacksDur or State.Duration("blast")
  if expire and total and total > 0 then
    frac = min(1, max(0, (expire - now) / total))
    if frac < 0.25 then r, g, b = UI.MixTo(C.bad, r, g, b, frac / 0.25) end   -- la fenêtre va se fermer
  end
  bar:SetValue(frac)
  if bar.fill then bar.fill:SetVertexColor(r, g, b, 1) end
end

-- ------------------------------------------------------------------ icônes rondes
-- Une icône ronde : fond, icône masquée en cercle, voile de recharge, bord coloré, halo.
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

-- ------------------------------------------------------------------ procs, à gauche et à droite
local function refreshProcs()
  local show = ns.db.showProcs
  local preview = GetTime() < previewUntil   -- aperçu du décor : les deux icônes s'affichent sans proc
  for _, f in ipairs(procs) do
    local p = State[f.def.key]
    local active = show and (p.active or preview) and true or false
    if active ~= f.on then
      f.on = active
      if active then
        f.icon:SetTexture(Spells.Icon(f.def.key) or Spells.Icon(f.def.spell) or 134400)
        f.pop = 1
        f:Show()
      end
    end
    if active then
      if p.active and p.expire and p.duration and p.duration > 0 then
        setCooldown(f, p.expire - p.duration, p.duration)
      else
        setCooldown(f, 0, 0)   -- durée inconnue : icône pleine
      end
    end
  end
end

local function animateProcs(dt, now)
  for _, f in ipairs(procs) do
    if f.on or f.vis > 0 then
      f.vis = UI.Approach(f.vis, f.on and 1 or 0, dt, f.on and 14 or 10)
      f.pop = UI.Approach(f.pop, 0, dt, 7)
      f:SetAlpha(f.vis)
      if f.vis <= 0 and not f.on then
        f:Hide()
      else
        local c = f.def.color
        local pulse = 0.5 + 0.5 * sin(now * 4.4)
        f.glow:SetVertexColor(c[1], c[2], c[3], min(1, 0.30 + 0.16 * pulse + f.pop * 0.5))
        local s = PROC * (1.9 + f.pop * 0.7)   -- (pas de SetScale : il déplacerait l'icône)
        f.glow:SetSize(s, s)
        local d = f.decorDef
        if d then
          local size = PROC * d.size * (1 + f.pop * d.burst)   -- le décor bondit avec le proc
          f.decor:SetSize(size, size)
          if d.spin and f.decor.SetRotation then
            -- l'anneau tourne, plus vite dans les trois dernières secondes du proc
            local p = State[f.def.key]
            local hurry = p.active and p.expire and p.expire - now < 3
            f.spin = (f.spin or 0) + dt * d.spin * (hurry and 4 or 1)
            f.decor:SetRotation(f.spin)
          end
          if d.pulse then f.decor:SetAlpha(0.60 + 0.40 * pulse) end
        end
      end
    end
  end
end

-- ------------------------------------------------------------------ Présence spirituelle, au-dessus des charges
-- Tant qu'elle est active, son icône reste affichée : le prochain sort sera instantané.
local function refreshPom()
  local on = ns.db.showProcs and State.pom.active and true or false
  if on == pomIcon.on then return end
  pomIcon.on = on
  if on then
    pomIcon.icon:SetTexture(Spells.Icon("pom") or 134400)
    pomIcon.pop = 1
    if ns.db.flash then spawnHalo(pomIcon, C.pom, POM, POM + 80, 0.45) end
  end
end

local function animatePom(dt, now)
  pomBlend = UI.Approach(pomBlend, pomIcon.on and 1 or 0, dt, 12)
  pomIcon.pop = UI.Approach(pomIcon.pop, 0, dt, 7)
  if pomBlend ~= pomShown then
    pomShown = pomBlend
    pomIcon:SetAlpha(pomBlend)
  end
  if pomBlend <= 0 then return end
  local pulse = 0.5 + 0.5 * sin(now * 4.4)
  pomIcon.glow:SetVertexColor(C.pom[1], C.pom[2], C.pom[3], min(1, 0.32 + 0.18 * pulse + pomIcon.pop * 0.4))
  local s = POM * (2.0 + pomIcon.pop * 0.8)
  pomIcon.glow:SetSize(s, s)
end

-- ------------------------------------------------------------------ rappels avant le combat, en bas
local remindersShown = 0
local function refreshReminders(force)
  local list = State.reminders
  local n = #list
  local changed = force or n ~= remindersShown
  for i, f in ipairs(reminders) do
    if f.key ~= list[i] then changed = true end
  end
  if not changed then return end   -- la liste n'a pas bougé : rien à replacer
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
    if f.key then f.glow:SetVertexColor(C.manaLow[1], C.manaLow[2], C.manaLow[3], 0.30 + 0.30 * pulse) end
  end
end

-- ------------------------------------------------------------------ décor des procs
-- Donne à chaque proc le décor choisi dans les réglages (ou aucun).
local function applyDecor()
  local d = DECORS[ns.db.decor]
  for _, f in ipairs(procs) do
    f.decorDef = d
    if d then
      f.decor:SetTexture(UI.Media(d.file))
      f.decor:SetSize(PROC * d.size, PROC * d.size)
      if d.flip and f.def.side > 0 then
        f.decor:SetTexCoord(1, 0, 0, 1)   -- miroir : le croissant se place du côté extérieur
      else
        f.decor:SetTexCoord(0, 1, 0, 1)
      end
      if f.decor.SetRotation then f.decor:SetRotation(0) end
      f.spin = 0
      f.decor:SetAlpha(1)
      f.decor:Show()
    else
      f.decor:Hide()
    end
  end
end

-- Aperçu du décor, depuis les réglages : les deux icônes de proc s'affichent quelques secondes.
function Hud.PreviewDecor()
  if not root then return end
  previewUntil = GetTime() + 4
  Hud.Refresh()
end

-- ------------------------------------------------------------------ mise en page
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
  pomIcon:ClearAllPoints()
  pomIcon:SetPoint("CENTER", root, "CENTER", 0, topY() + CR_H / 2 + POM / 2 + 12)
  refreshReminders(true)
  -- repères montrés quand le HUD est déverrouillé : où tombera chaque zone
  local spots = { { -sp, 0, PROC }, { sp, 0, PROC }, { 0, topY(), CR_H }, { 0, bottomY(), REMIND } }
  for i, g in ipairs(ghosts) do
    g:ClearAllPoints()
    g:SetPoint("CENTER", root, "CENTER", spots[i][1], spots[i][2])
    g:SetSize(spots[i][3], spots[i][3])
  end
end

-- ------------------------------------------------------------------ position, verrouillage
local function applyPosition()
  local p = ns.db.point
  root:ClearAllPoints()
  root:SetPoint(p[1], UIParent, p[2], p[3], p[4])
  root:SetScale(ns.db.scale or 1)
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
  text:SetText(L["Glisse-moi · /arc verrou"])
  local tints = { C.clear, C.barrage, C.arcane, C.manaLow }
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
    if point and x and y then ns.db.point = { point, rel or point, x, y } end
  end)
end

-- ------------------------------------------------------------------ sons
-- Joue un son du jeu par son identifiant ; false si le jeu ne joue rien (identifiant inconnu de ce client).
local function playKit(id)
  local ok, played = pcall(PlaySound, id, "Master")
  return ok and played and true or false
end
Hud.PlayKit = playKit

-- La voix du jeu (synthèse vocale) : elle dit le mot au lieu de jouer un son. Retourne l'identifiant de la
-- voix réglée dans le jeu, sinon de la première installée ; nil si ce client n'en a aucune.
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

-- Dans l'ordre : le choix du joueur (un son du jeu, ou la voix) ; sinon son fichier déposé dans Sounds ;
-- sinon le son d'origine, puis son remplaçant. Retourne l'identifiant joué, "voix", "fichier", ou nil.
local function playSound(def, always)
  if not (always or ns.db.sound) then return nil end
  local chosen = type(ns.db.soundKit) == "table" and ns.db.soundKit[def.file]
  if chosen == "voix" then
    if speak(L[def.say]) then return "voix" end
  elseif chosen and playKit(chosen) then
    return chosen
  end
  local ok, played = pcall(PlaySoundFile, "Interface\\AddOns\\" .. ADDON .. "\\Sounds\\" .. def.file .. ".ogg", "Master")
  if ok and played then return "fichier" end
  if playKit(def.kit) then return def.kit end
  if def.alt and playKit(def.alt) then return def.alt end
  return nil
end

-- Le nom du son choisi pour un proc ("clear" ou "barrage"), pour les réglages.
function Hud.SoundName(key)
  local v = type(ns.db.soundKit) == "table" and ns.db.soundKit[key]
  if not v then return L["Par défaut"] end
  if v == "voix" then return L["Voix du jeu"] end
  for _, s in ipairs(SOUNDS) do
    if s[1] == v then return L[s[2]] end
  end
  return string.format(L["Son n° %d"], v)
end

function Hud.PreviewSound(key)
  local def = SOUND_DEF[key]
  return def and playSound(def, true) or nil
end

-- Passe au choix suivant (dir = 1) ou précédent (-1) et le fait entendre. Les choix : le son par défaut,
-- les sons nommés, la voix du jeu si ce client en a une, et le numéro tapé avec /arc son s'il n'est pas
-- dans la liste. Un son que le jeu ne joue pas est sauté.
function Hud.CycleSound(key, dir)
  local def = SOUND_DEF[key]
  if not def then return end
  if type(ns.db.soundKit) ~= "table" then ns.db.soundKit = {} end
  local cur = ns.db.soundKit[key] or false
  local list, at, listed = { false }, 1, cur == false
  for _, s in ipairs(SOUNDS) do list[#list + 1] = s[1] end
  if Hud.CanSpeak() then list[#list + 1] = "voix" end
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
    elseif v == "voix" then
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

-- /arc sons : fait entendre les deux sons, l'un après l'autre, et dit lequel est joué.
function Hud.TestSounds()
  local list = {
    { PROC_SOUND.clear, L["Idées claires"] },
    { PROC_SOUND.barrage, L["Barrage de projectiles"] },
  }
  for i, item in ipairs(list) do
    local function play()
      local what = playSound(item[1], true)
      local text = what == "fichier" and L["ton fichier"] or what == "voix" and L["voix du jeu"]
        or what and string.format(L["son du jeu %d"], what) or L["aucun son"]
      ns.Print(item[2] .. " : " .. text .. ".")
    end
    if i > 1 and C_Timer and C_Timer.After then C_Timer.After((i - 1) * 1.5, play) else play() end
  end
end

-- ------------------------------------------------------------------ boucle d'affichage
-- Les procs, les charges et la Présence spirituelle : visibles dès qu'il y a quelque chose à suivre.
local function wantedFight()
  local db = ns.db
  if not db.enabled then return 0 end
  if not db.locked or State.live or GetTime() < previewUntil then return 1 end
  return db.showIdle and db.idleAlpha or 0
end

-- Les rappels : visibles hors combat dès qu'il manque quelque chose, sauf au repos en ville (ils y
-- reviennent quand une cible hostile est choisie).
local function wantedPrep()
  local db = ns.db
  if not db.enabled or db.showReminders == false or #State.reminders == 0 then return 0 end
  if State.live then return 1 end
  local resting = IsResting and IsResting()
  return resting and 0 or 1
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
  if fightAlpha <= 0 then return end   -- rien à suivre : rien d'autre à faire pour cette image
  if ns.db.showCharges then
    animateCrystals(dt)
    animateBar(now)
  end
  animateProcs(dt, now)
  animatePom(dt, now)
  animateHalos(now)
end

function Hud.Refresh()
  if not root then return end
  local now = GetTime()
  refreshBar(now)
  refreshProcs()
  refreshPom()
  refreshReminders()
end

function Hud.Build()
  if root then return root end
  root = CreateFrame("Frame", "ArcanumHUD", UIParent)
  root:SetSize(400, 400)
  root:SetFrameStrata("MEDIUM")

  -- Deux groupes, chacun avec son opacité : le combat (procs, charges, Présence spirituelle) et la
  -- préparation (rappels).
  fight = CreateFrame("Frame", nil, root)
  fight:SetAllPoints()
  fight:SetAlpha(0)
  prep = CreateFrame("Frame", nil, root)
  prep:SetAllPoints()
  prep:SetAlpha(0)
  local level = root:GetFrameLevel()

  for i, def in ipairs(PROCS) do
    local f = makeRound(fight, PROC, true, true)   -- voile inversé : il grandit à mesure que le proc s'épuise
    f.def, f.vis, f.on = def, 0, false
    f.decor = UI.Tex(f, "BACKGROUND", nil, def.color, 1, nil, -1)
    f.decor:SetPoint("CENTER")
    f:SetFrameLevel(level + 4)
    f.ring:SetVertexColor(def.color[1], def.color[2], def.color[3], 1)
    f:SetAlpha(0)
    f:Hide()
    procs[i] = f
  end

  for i = 1, 4 do
    crystals[i] = makeCrystal(fight)
    crystals[i]:SetFrameLevel(level + 5)
  end
  bar = makeBar(fight)
  barText = UI.Text(bar, 12, C.muted, UI.FONT.body, "OUTLINE")
  barText:SetPoint("LEFT", bar, "RIGHT", 8, 0)

  pomIcon = makeRound(fight, POM, false)
  pomIcon.on = false
  pomIcon:SetFrameLevel(level + 5)
  pomIcon.icon:SetTexture(134400)
  pomIcon.ring:SetVertexColor(C.pom[1], C.pom[2], C.pom[3], 1)
  pomIcon:SetAlpha(0)

  for i = 1, 5 do
    local f = makeRound(prep, REMIND, false)
    f.ring:SetVertexColor(C.manaLow[1], C.manaLow[2], C.manaLow[3], 1)
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
  Hud.procs, Hud.crystals, Hud.reminders, Hud.bar, Hud.barText, Hud.pomIcon = procs, crystals, reminders, bar, barText, pomIcon
  return root
end

-- ------------------------------------------------------------------ branchements
ns:On("START", function() Hud.Build() end)

ns:On("STATE", Hud.Refresh)
ns:On("SPELLS", function() Hud.Layout() end)
ns:On("DEMO", function() Hud.Layout() end)

ns:On("SETTINGS", function()
  if not root then return end
  applyPosition()
  applyLock()
  Hud.Layout()
  Hud.Refresh()
end)

ns:On("STACKS", function(n, old)
  if not root then return end
  for i = (old or 0) + 1, n do
    if crystals[i] then crystals[i].pop = 1 end   -- le cristal bondit : pas besoin d'onde en plus
  end
end)

-- Un proc arrive : une onde part de son icône, à sa couleur, et son son retentit.
ns:On("PROC", function(key)
  if not root then return end
  local def = PROC_SOUND[key]
  if not def then return end
  if ns.db.flash and ns.db.showProcs then
    for _, f in ipairs(procs) do
      if f.def.key == key then spawnHalo(f, f.def.color, PROC, PROC + 80, 0.45) end
    end
  end
  if not State.demo then playSound(def) end
end)
