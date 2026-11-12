-- Arcanum — le HUD : un cercle runique.
--
-- Au centre, le prochain sort à lancer ; sa couleur dit pourquoi (violet : cycle normal, rose : Barrage
-- de projectiles, bleu clair : Idées claires, or : gros dégâts, bleu : mana). Autour, un anneau, et
-- chaque information à sa place fixe :
--   * au-dessus du cercle, un cristal par charge visée (un de plus quand le jeu en offre une) ;
--   * l'arc lumineux qui se vide autour de l'anneau : les 18 secondes de leur fenêtre ;
--   * à gauche et à droite, serties dans l'anneau : les gros temps de recharge, avec leur icône ;
--   * en bas : un orbe de couleur par proc actif, avec un voile qui grandit à mesure qu'il s'épuise ;
--   * sous le cercle, hors combat : ce qu'il manque avant d'engager (Intelligence des Arcanes, armure, gemme).
-- En mode suivi seul (sans conseil), le centre montre à la place les procs actifs, en grandes icônes ;
-- et quand c'est le moment du burst, l'icône du sort à lancer s'y affiche, cerclée d'or, pendant que les
-- gemmes des temps de recharge prêts grossissent et battent en or.
-- Une gemme dont la recharge finit dans quelques secondes prend un bord doré et un chiffre.
-- En mode multi-cibles le cercle passe à l'orange ; l'icône rougit quand la cible est hors de portée.
-- Pendant une incantation, le prochain sort ne change pas : il se découvre à mesure que le sort part.
-- Exception : des Idées claires pendant un sort bon marché. L'icône passe alors à la Déflagration, un
-- bord blanc bat vite autour d'elle : interromps ton sort.
--
-- Tout est animé à la main dans un seul OnUpdate (approche douce vers une cible) : pas de groupes
-- d'animation à synchroniser, et le rendu reste fluide quel que soit le nombre d'images par seconde.
local ADDON, ns = ...
local UI, State, Spells, S = ns.UI, ns.State, ns.Spells, ns.Secret
local C = UI.C
local L = ns.L

local Hud = {}
ns.Hud = Hud

local sin, cos, rad, min, max = math.sin, math.cos, math.rad, math.min, math.max

local R = 62                          -- rayon de l'anneau
local RING_SIZE = R / 0.465           -- taille d'affichage des textures d'anneau (leur trait est à 46,5 % du bord)
local ROOT_W, ROOT_H = 210, 236
local HUB_Y = -40                     -- haut du cercle, depuis le haut du HUD
local MAIN = 64                       -- prochain sort
local CR_W, CR_H = 22, 28             -- cristaux de charge
local CR_RADIUS = R + 20              -- ils flottent au-dessus de l'anneau, sans le recouvrir
local CR_STEP = 22                    -- écart entre deux cristaux, en degrés
local CD_SIZE = 28                    -- gros temps de recharge
local CD_ANGLE = { 200, 340, 170, 10, 225 }
local BADGE = 16                      -- orbes de proc
local MANA_W, MANA_H = 110, 4
local REMIND = 20                     -- rappels avant le combat
local REMIND_Y = -40                  -- leur centre, sous le cercle

-- Gros temps de recharge sertis dans l'anneau, s'ils sont connus.
local CDS = { "pom", "eureka", "power", "berserking", "bloodfury" }
local DEMO_CDS = { pom = true, eureka = true }
local REASON_COLOR = {
  arcane = C.arcane, burst = C.power, barrage = C.barrage, clear = C.clear, heat = C.heat, mana = C.mana,
  aoe = C.heat,   -- mode multi-cibles : tout le cercle passe à l'orange
}
local ACTIVE_COLOR = { pom = C.pom, eureka = C.power, power = C.power }
-- Procs montrés en orbe de couleur ; angle : leur place en bas de l'anneau ; spell : le sort que le proc
-- améliore, dont l'icône sert en mode suivi seul.
local PROCS = {
  { key = "barrage", color = C.barrage, angle = 250, spell = "missiles" },
  { key = "clear", color = C.clear, angle = 290, spell = "blast" },
  { key = "heat", color = C.heat, angle = 270, spell = "pyro" },
}
-- Les sons sont des sons du jeu (« kit » : leur identifiant ; « alt » : celui joué si ce client ne connaît
-- pas le premier). Le joueur peut en choisir d'autres (/arc son burst 888), ou déposer ses propres fichiers
-- dans Sounds (« file »).
-- « say » : le mot prononcé quand le joueur a choisi la voix du jeu.
local PROC_SOUND = {
  barrage = { kit = 3175, file = "barrage", color = C.barrage, say = "Barrage" },      -- ping de la mini-carte
  clear = { kit = 18019, file = "clear", color = C.clear, say = "Idées claires" },     -- notification Battle.net
  heat = { kit = 3175, file = "barrage", color = C.heat, say = "Pyro" },
}
local BURST_SOUND = { kit = 3071, alt = 8960, file = "burst", say = "Burst" }   -- Témérité, sinon l'appel de préparation
local SOUND_DEF = { clear = PROC_SOUND.clear, barrage = PROC_SOUND.barrage, burst = BURST_SOUND }
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

local root, mover, hub, main, plate, ring, timer, timerFull, mana, manaCurve, cueIcon
local crystals, cds, halos, badges, reminders, stage = {}, {}, {}, {}, {}, {}
local rootAlpha, hotBlend = 0, 0
local ringAlpha, cueBlend = 0.85, 0                    -- opacité de l'anneau ; signal de burst (0 à 1)
local cueShown = -1                                    -- dernière opacité donnée à l'icône de burst du centre
local stageCount = -1                                  -- nombre de procs affichés au centre (mode suivi seul)
local advising = true                                  -- le centre conseille-t-il le prochain sort ?
local shownAlpha = -1                                  -- dernière opacité donnée au cadre
local crystalsFor, crystalsAim, crystalsStill = -1, -1, false   -- état des cristaux au dernier dessin
local crystalsShown = -1                               -- nombre de cristaux affichés
local cooldownsDirty, lastFeed = true, 0
local reasonColor = { C.arcane[1], C.arcane[2], C.arcane[3] }   -- couleur courante, fondue vers la cible

-- Position sur l'anneau, depuis le centre du cercle.
local function onRing(angle, radius)
  local a = rad(angle)
  return (radius or R) * cos(a), (radius or R) * sin(a)
end

-- ------------------------------------------------------------------ halos (onde à l'arrivée d'un proc)
local function spawnHalo(color, from, to, life)
  if not root then return end
  local h
  for _, x in ipairs(halos) do
    if not x.t0 then h = x; break end
  end
  if not h then
    if #halos >= 4 then return end
    h = { tex = UI.Tex(root, "BACKGROUND", "halo", color, 0, "ADD", -3) }
    h.tex:SetPoint("CENTER", hub, "CENTER", 0, 0)
    halos[#halos + 1] = h
  end
  h.t0, h.life, h.from, h.to, h.color = GetTime(), life or 0.55, from or 60, to or 250, color
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
local function makeCrystal(parent, i)
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
  f.spark:SetSize(18, 18)
  f.spark:SetPoint("CENTER", -4, 6)
  f.level, f.pop = 0, 0
  f:Hide()
  return f
end

-- Dispose `shown` cristaux en arc, centrés au-dessus du cercle ; les autres sont cachés.
local function layoutCrystals(shown)
  crystalsShown = shown
  for i, f in ipairs(crystals) do
    if i <= shown and ns.db.showCharges then
      local x, y = onRing(90 + ((shown + 1) / 2 - i) * CR_STEP, CR_RADIUS)
      f:ClearAllPoints()
      f:SetPoint("CENTER", hub, "CENTER", x, y)
      f:Show()
    else
      f:Hide()
    end
  end
end

local function animateCrystals(dt, now)
  local n = State.stacks
  local target = State.Target()
  local full = n >= target
  -- un cristal par charge visée ; un de plus quand le jeu offre une charge (Déflagration gratuite)
  local shown = min(4, max(target, n))
  if shown ~= crystalsShown then layoutCrystals(shown) end
  local blend = UI.Approach(hotBlend, full and 1 or 0, dt, 6)
  -- au repos (rien ne pulse, rien ne change) : on ne touche à aucune texture
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
    -- restent fixes ; ce qui bat en continu est réservé à ce qui demande une action (procs, burst).
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

-- ------------------------------------------------------------------ icônes rondes
-- Une icône ronde sertie : fond, icône masquée en cercle, voile de recharge, bord coloré, halo.
local function makeRound(parent, size, numbers, reverse)
  local b = CreateFrame("Frame", nil, parent)
  b:SetSize(size, size)
  b.size, b.activeLevel, b.pop, b.cueLevel, b.soonLevel = size, 0, 0, 0, 0
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
    if okF and fs and fs.SetFont then pcall(fs.SetFont, fs, UI.FONT.body, 12, "OUTLINE") end
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

local function setCooldown(b, start, duration, modRate)
  if b._s == start and b._d == duration then return end
  b._s, b._d = start, duration
  pcall(b.cd.SetCooldown, b.cd, start, duration, modRate or 1)
end

-- Donne au widget le temps de recharge : nombres lisibles, ou objet « durée » quand ils sont secrets.
local function feedCooldown(b, info, force)
  if info.start and info.duration then
    if info.duration > 1.6 then
      setCooldown(b, info.start, info.duration, info.modRate)
    else
      setCooldown(b, 0, 0)   -- on ne montre pas le temps de recharge global
    end
  elseif info.secret then
    b._s, b._d = nil, nil
    if force and b.cd.SetCooldownFromDurationObject then
      local object = State.CooldownObject(b.key)
      if object then pcall(b.cd.SetCooldownFromDurationObject, b.cd, object, true) end
    end
  else
    setCooldown(b, 0, 0)
  end
end

-- ------------------------------------------------------------------ minuteur de la fenêtre des charges
-- Un widget Cooldown dont le voile est une bande en anneau : le jeu la découpe lui-même en arc, qui
-- rétrécit autour du cercle à mesure que les 18 secondes passent.
local function makeTimer(parent)
  local t = { frac = 0 }
  local ok, cd = pcall(CreateFrame, "Cooldown", nil, parent, "CooldownFrameTemplate")
  if not ok or not cd then cd = CreateFrame("Cooldown", nil, parent) end
  cd:SetSize(RING_SIZE, RING_SIZE)
  cd:SetPoint("CENTER", parent, "CENTER", 0, 0)
  if cd.SetSwipeTexture then pcall(cd.SetSwipeTexture, cd, UI.Media("arc"), C.arcane[1], C.arcane[2], C.arcane[3], 1) end
  if cd.SetDrawSwipe then pcall(cd.SetDrawSwipe, cd, true) end
  if cd.SetDrawEdge then pcall(cd.SetDrawEdge, cd, false) end
  if cd.SetDrawBling then pcall(cd.SetDrawBling, cd, false) end
  if cd.SetHideCountdownNumbers then pcall(cd.SetHideCountdownNumbers, cd, true) end
  t.cd = cd
  return t
end

local function refreshTimer()
  if not ns.db.showCharges or State.stacks <= 0 then
    setCooldown(timer, 0, 0)
    timerFull:SetAlpha(0)
    return
  end
  local expire, total = State.stacksExpire, State.stacksDur or State.Duration("blast")
  if expire and total and total > 0 then
    setCooldown(timer, expire - total, total)
    timerFull:SetAlpha(0)
  else
    setCooldown(timer, 0, 0)      -- fin inconnue : anneau plein
    timerFull:SetAlpha(1)
  end
end

local function animateTimer(now)
  local r, g, b = UI.Mix(C.arcane, C.hot, hotBlend)
  local expire, total = State.stacksExpire, State.stacksDur
  if State.stacks > 0 and expire and total and total > 0 then
    local frac = (expire - now) / total
    if frac < 0.25 then r, g, b = UI.MixTo(C.bad, r, g, b, max(0, frac) / 0.25) end   -- la fenêtre va se fermer
  end
  -- (on ne touche au widget que si la couleur a changé : le recolorer à chaque image le fait scintiller)
  if not timer.r or math.abs(r - timer.r) + math.abs(g - timer.g) + math.abs(b - timer.b) > 0.02 then
    timer.r, timer.g, timer.b = r, g, b
    if timer.cd.SetSwipeColor then pcall(timer.cd.SetSwipeColor, timer.cd, r, g, b, 1) end
    timerFull:SetVertexColor(r, g, b, 1)
  end
end

-- ------------------------------------------------------------------ prochain sort
local function nextIcon(key)
  if key == "gem" then
    local gem = State.Gem()
    local get = C_Item and C_Item.GetItemIconByID or GetItemIcon
    return gem.itemID and get and S.Plain(S.Call(get, gem.itemID)) or nil
  end
  return key and Spells.Icon(key) or nil
end

-- La cible est-elle hors de portée du sort conseillé ? (ce test reste lisible en combat)
local function outOfRange(id)
  if not (id and C_Spell and C_Spell.IsSpellInRange) then return false end
  local ok, inRange = pcall(C_Spell.IsSpellInRange, id, "target")
  return ok and not S.Is(inRange) and inRange == false
end

local function refreshMain()
  if not advising then return end
  local key, id = State.next, State.nextId
  if key ~= main.key then
    main.key = key
    main.icon:SetTexture(nextIcon(key) or 134400)
  end
  main.icon:SetAlpha(key and 1 or 0.35)
  -- hors de portée : l'icône rougit, comme sur les barres d'action
  local far = key ~= "gem" and outOfRange(id)
  if far ~= main.far then
    main.far = far
    if far then main.icon:SetVertexColor(1, 0.32, 0.32) else main.icon:SetVertexColor(1, 1, 1) end
  end
  -- rang à lancer, quand ce n'est pas le dernier (Éclair de givre de remplissage au rang 1)
  local label = ""
  if key and id and key ~= "gem" and id ~= Spells.Best(key) and id == Spells.Lowest(key) then label = "1" end
  if label ~= main.label then
    main.label = label
    main.rank:SetText(label)
  end
  -- pendant une incantation, l'icône se découvre à mesure que le sort en cours part
  local cast = State.cast
  if cast then
    setCooldown(main, cast.start, cast.finish - cast.start)
  else
    setCooldown(main, 0, 0)
  end
end

-- L'anneau et le bord de l'icône prennent la couleur du conseil.
local function animateSeal(dt, now)
  local cue = not advising and State.burst.on   -- mode « suivi seul » : c'est le moment du burst
  local target = cue and C.power or REASON_COLOR[State.nextReason] or C.arcane
  for i = 1, 3 do reasonColor[i] = UI.Approach(reasonColor[i], target[i], dt, 10) end
  local r, g, b = reasonColor[1], reasonColor[2], reasonColor[3]
  cueBlend = UI.Approach(cueBlend, cue and 1 or 0, dt, 10)
  -- l'icône du sort de burst à lancer, au centre : le regard y est déjà. Elle laisse la place à un proc
  -- affiché là.
  local shown = stageCount > 0 and 0 or cueBlend
  if shown ~= cueShown then
    cueShown = shown
    cueIcon:SetAlpha(shown)
  end
  if shown > 0 then
    cueIcon.glow:SetVertexColor(C.power[1], C.power[2], C.power[3], 0.35 + 0.25 * (0.5 + 0.5 * sin(now * 5.0)))
  end
  -- Avec des charges, l'anneau s'efface en piste sombre : l'arc de leur fenêtre se lit dessus. Il revient
  -- en pleine lumière, en or, quand c'est le moment du burst.
  local track = State.stacks > 0 and ns.db.showCharges and not cue
  ringAlpha = UI.Approach(ringAlpha, track and 0.32 or 0.85, dt, 8)
  local rr, rg, rb = UI.MixTo(C.edge, r, g, b, 0.55 + 0.40 * cueBlend)
  ring:SetVertexColor(rr, rg, rb, ringAlpha)
  if not advising then return end   -- mode « suivi seul » : pas d'icône de conseil à animer
  main.pop = UI.Approach(main.pop, 0, dt, 9)
  local urgent = State.nextReason ~= "arcane" and State.nextReason ~= nil
  -- respiration lente : assez pour vivre, pas assez pour clignoter
  local pulse = 0.5 + 0.5 * sin(now * (urgent and 3.2 or 1.8))

  -- pas de halo au repos : l'icône reste l'élément le plus lisible. Une lueur seulement quand il y a
  -- mieux à faire que le cycle normal, ou quand le conseil vient de changer.
  main.glow:SetVertexColor(r, g, b, min(1, (urgent and 0.30 + 0.10 * pulse or 0) + main.pop * 0.4))
  main.ring:SetVertexColor(r, g, b, 1)
  -- interruption conseillée : battement rapide, bien distinct de la respiration habituelle
  if State.interrupt then
    main.alertOn = true
    main.alert:SetVertexColor(1, 1, 1, 0.35 + 0.65 * (0.5 + 0.5 * sin(now * 20)))
  elseif main.alertOn then
    main.alertOn = false
    main.alert:SetVertexColor(1, 1, 1, 0)
  end
  local scale = 1 + main.pop * 0.16
  if scale ~= main.scale then
    main.scale = scale
    main:SetScale(scale)
  end
end

-- ------------------------------------------------------------------ orbes de proc
local function procState(key)
  if key == "heat" then return State.heat.ready, State.heat.expire, State.Duration("heat") end
  local p = State[key]
  return p.active, p.expire, p.duration
end

local function refreshBadges()
  local show = ns.db.showProcs and advising   -- (en mode suivi seul, les procs sont au centre)
  for _, f in ipairs(badges) do
    local active, expire, total = procState(f.def.key)
    active = show and active and true or false
    if active ~= f.on then
      f.on = active
      if active then
        f.pop = 1
        f:Show()
      end
    end
    if active then
      if expire and total and total > 0 then
        setCooldown(f, expire - total, total)
      else
        setCooldown(f, 0, 0)   -- durée inconnue : orbe plein
      end
    end
  end
end

local function animateBadges(dt, now)
  for _, f in ipairs(badges) do
    if f.on or f.vis > 0 then
      f.vis = UI.Approach(f.vis, f.on and 1 or 0, dt, f.on and 14 or 10)
      f.pop = UI.Approach(f.pop, 0, dt, 7)
      f:SetAlpha(f.vis)
      if f.vis <= 0 and not f.on then
        f:Hide()
      else
        local c = f.def.color
        local pulse = 0.5 + 0.5 * sin(now * 4.4)
        f.glow:SetVertexColor(c[1], c[2], c[3], min(1, 0.34 + 0.20 * pulse + f.pop * 0.5))
        local s = BADGE * (2.6 + f.pop * 1.6)   -- (pas de SetScale : il déplacerait la gemme sur l'anneau)
        f.glow:SetSize(s, s)
      end
    end
  end
end

-- ------------------------------------------------------------------ rappels avant le combat
-- Sous le cercle, hors combat : l'icône de ce qu'il manque (Intelligence des Arcanes, armure, gemme de mana).
local function reminderIcon(key)
  if key == "gemspell" then return Spells.IconOf(Spells.GemSpell()) end
  return Spells.Icon(key)
end

local remindersShown = 0
local function refreshReminders()
  local list = State.reminders
  local n = #list
  local changed = n ~= remindersShown
  for i, f in ipairs(reminders) do
    if f.key ~= list[i] then changed = true end
  end
  if not changed then return end   -- la liste n'a pas bougé : rien à replacer
  remindersShown = n
  for i, f in ipairs(reminders) do
    local key = list[i]
    f.key = key
    if key then
      f.icon:SetTexture(reminderIcon(key) or 134400)
      f:ClearAllPoints()
      f:SetPoint("CENTER", hub, "BOTTOM", (i - (n + 1) / 2) * 28, REMIND_Y)
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

-- ------------------------------------------------------------------ procs au centre (mode suivi seul)
-- Sans conseil, les procs sont l'information principale : chaque proc actif s'affiche en grande icône
-- au centre du cercle (l'icône du sort qu'il améliore, à la couleur du proc, avec le temps restant).
-- Un proc : une icône centrée. Deux ou trois : côte à côte, plus petites.
local STAGE_SIZE = { 56, 40, 32 }     -- taille des icônes selon le nombre de procs actifs
local STAGE_GAP = 6

local function layoutStage()
  local n = 0
  for _, f in ipairs(stage) do if f.on then n = n + 1 end end
  stageCount = n
  if n == 0 then return end
  local size = STAGE_SIZE[n] or STAGE_SIZE[#STAGE_SIZE]
  local x = -((n - 1) * (size + STAGE_GAP)) / 2
  for _, f in ipairs(stage) do
    if f.on then
      f.size = size
      f:SetSize(size, size)
      f:ClearAllPoints()
      f:SetPoint("CENTER", hub, "CENTER", x, 0)
      x = x + size + STAGE_GAP
    end
  end
end

local function refreshStage()
  local show = ns.db.showProcs and not advising
  local changed = false
  for _, f in ipairs(stage) do
    local active, expire, total = procState(f.def.key)
    active = show and active and true or false
    if active ~= f.on then
      f.on, changed = active, true
      if active then
        f.icon:SetTexture(Spells.Icon(f.def.spell) or 134400)
        f.pop = 1
        f:Show()
      end
    end
    if active then
      if expire and total and total > 0 then
        setCooldown(f, expire - total, total)
      else
        setCooldown(f, 0, 0)   -- durée inconnue : icône pleine
      end
    end
  end
  if changed then layoutStage() end
end

local function animateStage(dt, now)
  for _, f in ipairs(stage) do
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
        local s = (f.size or STAGE_SIZE[1]) * (1.9 + f.pop * 0.7)
        f.glow:SetSize(s, s)
      end
    end
  end
end

-- ------------------------------------------------------------------ burst au centre (mode suivi seul)
-- Le sort de burst à lancer maintenant : le premier gros temps de recharge signalé, dans l'ordre où ils
-- se lancent ; quand ils sont tous partis (Présence spirituelle active), le Courroux qui en profite.
-- Avec « burst en une icône » (la macro ArcBurst : Eurêka + Présence spirituelle + Courroux), une seule
-- touche fait tout : à la place d'Eurêka ou de la Présence spirituelle, on montre le Courroux, celle de
-- la macro. La démonstration, elle, déroule les sorts un à un.
local BURST_ORDER = { "power", "eureka", "pom", "berserking", "bloodfury" }
local IN_MACRO = { eureka = true, pom = true }
local function refreshCue()
  if advising or not State.burst.on then return end   -- (l'icône garde son image le temps de s'effacer)
  local key = "wrath"
  for _, k in ipairs(BURST_ORDER) do
    if State.burst[k] == true then key = k; break end
  end
  if IN_MACRO[key] and ns.db.burstOne ~= false and not State.demo then key = "wrath" end
  if key ~= cueIcon.key then
    cueIcon.key = key
    cueIcon.icon:SetTexture(Spells.Icon(key) or 134400)
  end
end

-- ------------------------------------------------------------------ gros temps de recharge
local function isVisible(key)
  if not ns.db.showCooldowns then return false end
  if State.demo then return DEMO_CDS[key] == true end
  return Spells.Known(key)
end

local function refreshCooldowns(now)
  -- en combat le widget est réalimenté quand le jeu signale un changement, et au pire toutes les 5 s :
  -- le réalimenter chaque seconde relançait son voile
  local force = cooldownsDirty or now - lastFeed > 5
  if force then cooldownsDirty, lastFeed = false, now end
  for _, b in ipairs(cds) do
    if b.visible then
      local info = State.Cooldown(b.key)
      feedCooldown(b, info, force)
      local p = State[b.key]
      b.active = type(p) == "table" and p.active or false
      b.cue = not advising and State.burst[b.key] == true   -- c'est le moment de le claquer
      -- bientôt prêt : l'icône reprend ses couleurs, et notre chiffre remplace celui du jeu
      local left = info.onCD == true and info.readyAt and info.readyAt - now or nil
      local soon = left ~= nil and left > 0 and left <= (ns.db.soonSeconds or 0)
      if soon ~= b.soon then
        b.soon = soon
        if b.cd.SetHideCountdownNumbers then pcall(b.cd.SetHideCountdownNumbers, b.cd, soon) end
        if not soon then
          b.soonShown = nil
          b.soonText:SetText("")
        end
      end
      if soon then
        local n = math.ceil(left)
        if n ~= b.soonShown then
          b.soonShown = n
          b.soonText:SetText(tostring(n))
        end
      end
      local dim = info.onCD == true and not b.active and not soon
      b.icon:SetDesaturated(dim)
      b.icon:SetAlpha(dim and 0.75 or 1)
    end
  end
end

-- Quatre états lisibles d'un coup d'œil : en recharge (grisé, voilé), bientôt prêt (en couleurs, bord doré
-- fixe, secondes restantes), prêt (net, bord discret), et « c'est le moment » : la gemme grossit, passe à
-- l'or et bat. Rien d'autre ne bat en or sur le HUD.
local function animateCooldowns(dt, now)
  local pulse = 0.5 + 0.5 * sin(now * 5.0)
  for _, b in ipairs(cds) do
    if b.visible then
      b.activeLevel = UI.Approach(b.activeLevel, b.active and 1 or 0, dt, 10)
      b.cueLevel = UI.Approach(b.cueLevel, b.cue and 1 or 0, dt, 10)
      b.soonLevel = UI.Approach(b.soonLevel, b.soon and 1 or 0, dt, 8)
      local a, k, s = b.activeLevel, b.cueLevel, b.soonLevel
      local r, g, bl = UI.Mix(ACTIVE_COLOR[b.key] or C.power, C.power, max(k, s))
      b.glow:SetVertexColor(r, g, bl, max(a * 0.7, k * (0.55 + 0.40 * pulse), s * 0.22))
      local er, eg, eb = UI.MixTo(C.edge, r, g, bl, max(a, k, s))
      b.ring:SetVertexColor(er, eg, eb, 0.9)
      local size = CD_SIZE * (1 + 0.25 * k)   -- (pas de SetScale : il déplacerait la gemme sur l'anneau)
      if size ~= b.size then
        b.size = size
        b:SetSize(size, size)
        b.glow:SetSize(size * 2.0, size * 2.0)
      end
    end
  end
end

-- ------------------------------------------------------------------ mana
-- En combat le mana est une valeur secrète : on la confie telle quelle à la barre, sans jamais la lire.
local function makeManaCurve()
  if not (C_CurveUtil and C_CurveUtil.CreateColorCurve and CreateColor and UnitPowerPercent) then return nil end
  local ok, curve = pcall(function()
    local c = C_CurveUtil.CreateColorCurve()
    c:AddPoint(0.00, CreateColor(C.bad[1], C.bad[2], C.bad[3], 1))
    c:AddPoint(0.15, CreateColor(C.bad[1], C.bad[2], C.bad[3], 1))        -- sous 15 % : Évocation
    c:AddPoint(0.28, CreateColor(C.manaLow[1], C.manaLow[2], C.manaLow[3], 1))
    c:AddPoint(0.45, CreateColor(C.mana[1], C.mana[2], C.mana[3], 1))
    c:AddPoint(1.00, CreateColor(C.mana[1], C.mana[2], C.mana[3], 1))
    return c
  end)
  return ok and curve or nil
end

local function colorMana()
  local color = UnitPowerPercent("player", 0, false, manaCurve)
  if color and color.GetRGB then mana.fill:SetVertexColor(color:GetRGB()) end
end

local function refreshMana()
  if not mana or not ns.db.showMana then return end
  if State.demo then
    local t = (GetTime() - (State.demoStart or 0)) % 11 / 11
    mana:SetMinMaxValues(0, 1)
    mana:SetValue(1 - 0.8 * t)
    return
  end
  local okMax, maxPower = pcall(UnitPowerMax, "player", 0)
  local okCur, power = pcall(UnitPower, "player", 0)
  if okMax and okCur then   -- ne rien tester ici : en combat ces valeurs sont secrètes
    pcall(mana.SetMinMaxValues, mana, 0, maxPower)
    pcall(mana.SetValue, mana, power)
  end
  if manaCurve then pcall(colorMana) end
end

local function makeMana(parent)
  local bar = CreateFrame("StatusBar", nil, parent)
  bar:SetSize(MANA_W, MANA_H)
  bar:SetStatusBarTexture(UI.WHITE)
  bar.fill = bar:GetStatusBarTexture()
  if bar.fill then bar.fill:SetVertexColor(C.mana[1], C.mana[2], C.mana[3], 1) end
  bar:SetMinMaxValues(0, 1)
  bar:SetValue(1)
  local bg = UI.Tex(bar, "BACKGROUND", nil, C.ink, 0.90)
  bg:SetPoint("TOPLEFT", -1, 1)
  bg:SetPoint("BOTTOMRIGHT", 1, -1)
  return bar
end

-- ------------------------------------------------------------------ mise en page
function Hud.Layout()
  if not root then return end
  local db = ns.db
  advising = db.showNext ~= false
  main:SetShown(advising)
  layoutCrystals(min(4, max(State.Target(), State.stacks)))
  local n = 0
  for _, b in ipairs(cds) do
    b.visible = isVisible(b.key)
    b:SetShown(b.visible)
    if b.visible then
      n = n + 1
      b.icon:SetTexture(Spells.Icon(b.key) or 134400)
      local x, y = onRing(CD_ANGLE[n] or CD_ANGLE[#CD_ANGLE])
      b:ClearAllPoints()
      b:SetPoint("CENTER", hub, "CENTER", x, y)
    end
  end
  mana:SetShown(db.showMana)
  cooldownsDirty = true
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
  UI.Panel(mover, C.arcane, 0.14, "BACKGROUND", 0)
  local text = UI.Text(mover, 10, C.arcaneHi, UI.FONT.title)
  text:SetPoint("TOP", 0, -6)
  text:SetText(L["Glisse-moi · /arc verrou"])
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

-- Le son du burst : une fois quand le moment arrive. Le signal peut s'éteindre et revenir aussitôt (un
-- Barrage à dépenser d'abord) : on ne le rejoue pas avant 8 secondes.
local burstSoundAt = -100
local function burstSound()
  local now = GetTime()
  if State.demo or now - burstSoundAt < 8 then return end
  burstSoundAt = now
  playSound(BURST_SOUND)
end

-- Rappel : le signal de burst reste allumé et aucun gros temps de recharge n'est lancé. L'onde et le son
-- sont redonnés une fois ; lancer un de ces sorts relance le délai pour les suivants.
local cueSince, cueReminded = nil, false
local function remindBurst(now)
  local lit = false
  if not advising and State.burst.on and not State.demo then
    for _, key in ipairs(CDS) do
      if State.burst[key] == true then lit = true; break end
    end
  end
  if not lit then
    cueSince = nil
    return
  end
  if not cueSince then
    cueSince, cueReminded = now, false
    return
  end
  local delay = ns.db.burstRemind or 0
  if cueReminded or delay <= 0 or now - cueSince < delay then return end
  cueReminded = true
  if ns.db.flash then spawnHalo(C.power, 2 * R, 2 * R + 70, 0.5) end
  burstSoundAt = now
  playSound(BURST_SOUND)
end

-- Le nom du son choisi pour un signal ("clear", "barrage" ou "burst"), pour les réglages.
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

-- /arc sons : fait entendre les trois sons, l'un après l'autre, et dit lequel est joué.
function Hud.TestSounds()
  local list = {
    { PROC_SOUND.clear, L["Idées claires"] },
    { PROC_SOUND.barrage, L["Barrage de projectiles"] },
    { BURST_SOUND, L["Moment du burst"] },
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
local function wantedAlpha()
  local db = ns.db
  if not db.enabled then return 0 end
  if not db.locked or State.live then return 1 end
  return db.showIdle and db.idleAlpha or 0
end

local function onUpdate(_, dt)
  local now = GetTime()
  rootAlpha = UI.Approach(rootAlpha, wantedAlpha(), dt, 9)
  if rootAlpha ~= shownAlpha then
    shownAlpha = rootAlpha
    root:SetAlpha(rootAlpha)
  end
  if rootAlpha <= 0 then return end   -- HUD masqué : rien d'autre à faire pour cette image
  animateSeal(dt, now)
  if ns.db.showCharges then
    animateCrystals(dt, now)
    animateTimer(now)
  end
  animateCooldowns(dt, now)
  animateBadges(dt, now)
  animateStage(dt, now)
  animateReminders(now)
  animateHalos(now)
end

function Hud.Refresh()
  if not root then return end
  local now = GetTime()
  refreshMain()
  refreshTimer()
  refreshBadges()
  refreshStage()
  refreshCue()
  refreshReminders()
  refreshCooldowns(now)
  refreshMana()
  remindBurst(now)
end

function Hud.Build()
  if root then return root end
  root = CreateFrame("Frame", "ArcanumHUD", UIParent)
  root:SetSize(ROOT_W, ROOT_H)
  root:SetFrameStrata("MEDIUM")
  root:SetAlpha(0)

  -- Le cercle : un cadre fixe auquel tout s'ancre (l'icône centrale bondit sans rien déplacer d'autre).
  hub = CreateFrame("Frame", nil, root)
  hub:SetSize(2 * R, 2 * R)
  hub:SetPoint("TOP", root, "TOP", 0, HUB_Y)
  plate = UI.Tex(hub, "BACKGROUND", "circle", C.ink, 0.34, nil, -6)
  plate:SetPoint("CENTER")
  plate:SetSize(2 * R + 6, 2 * R + 6)
  ring = UI.Tex(hub, "ARTWORK", "ring", C.edge, 0.85)
  ring:SetPoint("CENTER")
  ring:SetSize(RING_SIZE, RING_SIZE)
  timerFull = UI.Tex(hub, "ARTWORK", "arc", C.arcane, 1, nil, 1)
  timerFull:SetPoint("CENTER")
  timerFull:SetSize(RING_SIZE, RING_SIZE)
  timerFull:SetAlpha(0)

  local level = hub:GetFrameLevel()
  timer = makeTimer(hub)
  timer.cd:SetFrameLevel(level + 1)

  main = makeRound(hub, MAIN, false)
  main:SetPoint("CENTER", hub, "CENTER", 0, 0)
  main:SetFrameLevel(level + 3)
  main.icon:SetTexture(134400)
  -- signal « interromps » : un second bord, blanc, qui bat vite autour de l'icône
  main.alert = UI.Tex(main.over, "OVERLAY", "circle-edge", { 1, 1, 1 }, 0, "ADD", 2)
  main.alert:SetPoint("TOPLEFT", -7, 7)
  main.alert:SetPoint("BOTTOMRIGHT", 7, -7)
  main.rank = UI.Text(main.over, 12, C.text, UI.FONT.body, "OUTLINE")
  main.rank:SetPoint("BOTTOMRIGHT", -6, 5)

  -- mode suivi seul : l'icône du sort de burst à lancer, au centre du cercle, quand c'est le moment
  cueIcon = makeRound(hub, STAGE_SIZE[1], false)
  cueIcon:SetPoint("CENTER", hub, "CENTER", 0, 0)
  cueIcon:SetFrameLevel(level + 4)
  cueIcon.icon:SetTexture(134400)
  cueIcon.ring:SetVertexColor(C.power[1], C.power[2], C.power[3], 1)
  cueIcon:SetAlpha(0)

  for i = 1, 3 do
    local f = makeRound(root, REMIND, false)
    f.ring:SetVertexColor(C.manaLow[1], C.manaLow[2], C.manaLow[3], 1)
    f:Hide()
    reminders[i] = f
  end

  for i = 1, 4 do
    crystals[i] = makeCrystal(hub, i)
    crystals[i]:SetFrameLevel(level + 5)
  end
  layoutCrystals(State.Target())
  for i, key in ipairs(CDS) do
    local b = makeRound(hub, CD_SIZE, true)
    b.key = key
    b:SetFrameLevel(level + 5)
    b.soonText = UI.Text(b.over, 13, C.power, UI.FONT.body, "OUTLINE")   -- secondes restantes, quand c'est bientôt prêt
    b.soonText:SetPoint("CENTER", 0, 0)
    b:Hide()
    cds[i] = b
  end
  for i, def in ipairs(PROCS) do
    local f = makeRound(hub, BADGE, false, true)   -- voile inversé : il grandit à mesure que le proc s'épuise
    f.def, f.vis, f.on = def, 0, false
    local x, y = onRing(def.angle)
    f:SetPoint("CENTER", hub, "CENTER", x, y)
    f:SetFrameLevel(level + 6)
    -- un orbe : la couleur du proc, sans icône (c'est elle qui porte le sens), bord éclairci
    f.icon:SetTexture(UI.WHITE)
    f.icon:SetVertexColor(def.color[1], def.color[2], def.color[3], 1)
    local er, eg, eb = UI.MixTo(def.color, 1, 1, 1, 0.55)
    f.ring:SetVertexColor(er, eg, eb, 1)
    f:SetAlpha(0)
    f:Hide()
    badges[i] = f
  end

  for i, def in ipairs(PROCS) do
    local f = makeRound(hub, STAGE_SIZE[1], true, true)   -- avec le temps restant en chiffres
    f.def, f.vis, f.on = def, 0, false
    f:SetPoint("CENTER", hub, "CENTER", 0, 0)
    f:SetFrameLevel(level + 4)
    f.ring:SetVertexColor(def.color[1], def.color[2], def.color[3], 1)
    if f.cd.GetCountdownFontString then
      local okF, fs = pcall(f.cd.GetCountdownFontString, f.cd)
      if okF and fs and fs.SetFont then pcall(fs.SetFont, fs, UI.FONT.body, 15, "OUTLINE") end
    end
    f:SetAlpha(0)
    f:Hide()
    stage[i] = f
  end

  mana = makeMana(root)
  mana:SetPoint("TOP", hub, "BOTTOM", 0, -18)
  manaCurve = makeManaCurve()
  makeMover()

  applyPosition()
  applyLock()
  Hud.Layout()

  local driver = CreateFrame("Frame")
  driver:SetScript("OnUpdate", function(self, dt)
    local ok, err = pcall(onUpdate, self, dt)
    if not ok then ns.Report(err) end
  end)
  Hud.root, Hud.badges, Hud.main, Hud.reminders, Hud.crystals = root, badges, main, reminders, crystals
  Hud.stage, Hud.cds, Hud.cueIcon = stage, cds, cueIcon
  return root
end

-- ------------------------------------------------------------------ branchements
ns:On("START", function()
  Hud.Build()
  ns:RegisterUnitEvent("UNIT_POWER_FREQUENT", "player", refreshMana)
  ns:RegisterUnitEvent("UNIT_MAXPOWER", "player", refreshMana)
end)

ns:On("STATE", Hud.Refresh)
ns:On("SPELLS", function() Hud.Layout() end)
ns:On("DEMO", function() Hud.Layout() end)
ns:On("COOLDOWNS", function() cooldownsDirty = true end)

ns:On("SETTINGS", function()
  if not root then return end
  applyPosition()
  applyLock()
  Hud.Layout()
  Hud.Refresh()
end)

-- Le conseil change : l'icône bondit légèrement, pour que l'œil le remarque sans lire.
local advisedBurst = false
ns:On("NEXT", function(key, reason, old)
  if not root then return end
  if reason == "burst" and not advisedBurst then burstSound() end   -- le conseil passe au burst
  advisedBurst = reason == "burst"
  if key ~= old or State.interrupt then main.pop = 1 end
  if State.interrupt and ns.db.flash then spawnHalo(C.clear, 2 * R, 2 * R + 80, 0.45) end
end)

-- Mode « suivi seul » : le moment du burst arrive. Une onde dorée, en plus des gemmes qui battent.
ns:On("BURST", function(on)
  if not root or not on or advising then return end
  if ns.db.flash then spawnHalo(C.power, 2 * R, 2 * R + 70, 0.5) end
  burstSound()
end)

-- Un gros temps de recharge vient d'être lancé : le rappel du burst repart de zéro pour les suivants.
local IS_CD = {}
for _, key in ipairs(CDS) do IS_CD[key] = true end
ns:On("CAST", function(key)
  if IS_CD[key] and cueSince then cueSince, cueReminded = GetTime(), false end
end)

ns:On("STACKS", function(n, old)
  if not root then return end
  for i = (old or 0) + 1, n do
    if crystals[i] then crystals[i].pop = 1 end   -- le cristal bondit : pas besoin d'onde en plus
  end
end)

ns:On("PROC", function(key)
  if not root then return end
  local def = PROC_SOUND[key]
  if not def then return end
  if ns.db.flash then spawnHalo(def.color, 2 * R, 2 * R + 60, 0.45) end
  if not State.demo then playSound(def) end
end)
