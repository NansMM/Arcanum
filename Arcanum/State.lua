-- Arcanum — moteur d'état : charges de Déflagration, procs, temps de recharge.
--
-- Hors combat, les auras sont lisibles : c'est la vérité, et l'addon en profite pour apprendre les durées
-- et les coûts réels. En combat, le jeu cache les auras aux addons. Arcanum s'appuie alors sur ce qui
-- reste lisible :
--   * tes propres sorts lancés (UNIT_SPELLCAST_SUCCEEDED) : chaque Déflagration ajoute une charge ;
--   * le coût en mana annoncé par le jeu : Projectiles gratuits = Barrage de projectiles,
--     tout gratuit = Idées claires, et le coût de la Déflagration donne le nombre exact de charges
--     (+100 % par charge) ;
--   * la surbrillance des boutons d'action (SPELL_ACTIVATION_OVERLAY_GLOW_SHOW).
-- Arcanum conseille et affiche ; il ne lance rien.
local ADDON, ns = ...
local S = ns.Secret
local Spells = ns.Spells

local State = {
  combat = false,
  restricted = false,
  stacks = 0,           -- charges de Déflagration des Arcanes (0 à 4)
  stacksExpire = nil,   -- GetTime() de fin, ou nil si inconnue
  stacksDur = nil,
  stacksSource = "aura",
  barrage = { active = false },
  clear = { active = false },
  power = { active = false },
  eureka = { active = false },   -- racial gnome : +10 % de dégâts, -10 % de coût sur les sorts suivants
  next = nil,                    -- clé du prochain sort conseillé
  nextReason = nil,
  cast = nil,                    -- sort en cours : { key, start, finish }
  pom = { active = false },
  heat = { stacks = nil, ready = false },
  demo = false,
}
ns.State = State

local MAX_STACKS = 4
local GCD_MAX = 1.6
local GRACE = 0.7   -- délai avant de croire un coût qui contredit un sort tout juste lancé

-- Durées par défaut, remplacées par celles lues en jeu dès qu'une aura est lisible.
local DEFAULT_DUR = { barrage = 15, clear = 15, power = 15, heat = 20, eureka = 8 }
-- Charges de Déflagration (mesuré en jeu, 1.60.1) : la première Déflagration ouvre une fenêtre de 18 s ;
-- les suivantes ajoutent une charge sans la prolonger, et aucun autre sort ne consomme les charges.
local BLAST_WINDOW = 18
local DEFAULT_CD = {
  wrath = 6, power = 180, pom = 180, evoc = 480, fireblast = 8, berserking = 180, bloodfury = 120, eureka = 120,
}

-- Autres sorts de dégâts : leur coût annoncé sert de témoin pour les procs.
local DAMAGE = {
  missiles = true, wrath = true, pyro = true, fireball = true, frostbolt = true, frostfire = true,
  explosion = true, fireblast = true, scorch = true, flamestrike = true, cone = true,
}
-- Sorts à incantation : ils consomment la Présence spirituelle.
local CAST_TIME = {
  blast = true, wrath = true, pyro = true, fireball = true, frostbolt = true, frostfire = true,
  scorch = true, flamestrike = true, poly = true,
}
-- Sorts dont le coût sert de témoin pour les Idées claires (tous gratuits = proc).
local COST_REFS = { "blast", "explosion", "fireball", "frostbolt", "frostfire", "scorch", "fireblast" }

local lastCast = {}      -- [clé] = GetTime() du dernier lancer réussi
local cost = {}          -- [clé] = coût actuel (nombre) ou nil
local seenCost = {}      -- [clé] = true si un coût > 0 a déjà été lu
local overlay = {}       -- [identifiant de sort] = true si le bouton est en surbrillance
local loadedAt = 0        -- GetTime() de la dernière entrée dans le monde (écran de chargement)
local stacksEnded = 0     -- GetTime() de la dernière fin de fenêtre constatée au minuteur

State.lastCast = lastCast
State.cost = cost
State.overlay = overlay

local function learn()
  return ns.db and ns.db.learn or {}
end

local function dur(key)
  local l = learn()
  if key == "blast" then return l.abWindow or BLAST_WINDOW end
  return (l.dur and l.dur[key]) or DEFAULT_DUR[key]
end
State.Duration = dur

-- ------------------------------------------------------------------ lecture des auras
local function aurasRestricted()
  if not S.RESTRICTED then return false end
  local CS = C_Secrets
  if CS and CS.ShouldAurasBeSecret then
    local ok, r = pcall(CS.ShouldAurasBeSecret)
    if ok and not S.Is(r) and r ~= nil then return r == true end
  end
  return State.combat
end

local function usableAura(a)
  return type(a) == "table" and not S.IsTable(a) and not S.Is(a.spellId)
end

-- "up" + aura, "down" (absente, c'est sûr) ou "unknown" (le jeu la cache).
local function readAura(key)
  local def = Spells.Get(key)
  if not def or not C_UnitAuras then return "unknown" end
  local found
  if C_UnitAuras.GetPlayerAuraBySpellID then
    for _, id in ipairs(def.auras or def.ids or { def.id }) do
      local a = S.Call(C_UnitAuras.GetPlayerAuraBySpellID, id)
      if usableAura(a) then found = a; break end
    end
  end
  if not found and def.name and C_UnitAuras.GetAuraDataBySpellName then
    local a = S.Call(C_UnitAuras.GetAuraDataBySpellName, "player", def.name, "HELPFUL")
    if usableAura(a) then found = a end
  end
  if found then return "up", found end
  -- Absente ? Seulement si le jeu ne cache rien en ce moment, ou s'il déclare, maintenant, que cette
  -- aura-là n'est jamais secrète. (Ne pas s'en souvenir d'une lecture à l'autre : une aura lue une fois
  -- pendant une transition ne prouve rien pour la suite du combat.)
  if not State.restricted then return "down" end
  local CS = C_Secrets
  if CS and CS.ShouldSpellAuraBeSecret then
    local allPlain = true
    for _, id in ipairs(def.auras or def.ids or { def.id }) do
      local ok, r = pcall(CS.ShouldSpellAuraBeSecret, id)
      if not ok or S.Is(r) or r ~= false then allPlain = false; break end
    end
    if allPlain then return "down" end
  end
  return "unknown"
end
State.ReadAura = readAura

local function auraTimes(key, a)
  local expire, duration = S.Num(a.expirationTime), S.Num(a.duration)
  if duration and duration > 0 then
    local l = learn()
    if l.dur then l.dur[key] = duration end
  end
  if expire and expire <= 0 then expire = nil end
  return expire, (duration and duration > 0) and duration or dur(key)
end

-- ------------------------------------------------------------------ signaux lisibles en combat
local function readCosts()
  for key, def in pairs(Spells.DEF) do
    if def.known and (key == "missiles" or key == "blast" or DAMAGE[key]) then
      local c, why = Spells.Cost(key)
      if c and c > 0 then seenCost[key] = true end
      if c == nil and why == "aucun" and seenCost[key] then c = 0 end   -- le jeu n'annonce plus de coût : gratuit
      cost[key] = c
    else
      cost[key] = nil
    end
  end
end

-- true : tous les sorts témoins sont gratuits ; false : au moins un coûte ; nil : on ne sait pas.
local function refsFree()
  local any = false
  for _, key in ipairs(COST_REFS) do
    if seenCost[key] and cost[key] ~= nil then
      if cost[key] > 0 then return false end
      any = true
    end
  end
  -- « tout est gratuit » n'est pas cru juste après un écran de chargement : le jeu n'annonce pas encore les coûts
  if any and GetTime() - loadedAt >= 3 then return true end
  return nil
end

-- Le bouton d'un des rangs du sort est-il en surbrillance ? true, false ou nil (inconnu).
local function overlayed(key)
  local def = Spells.Get(key)
  if not def or not def.ids then return nil end
  local api = C_SpellActivationOverlay and C_SpellActivationOverlay.IsSpellOverlayed or IsSpellOverlayed
  local known = false
  for _, id in ipairs(def.ids) do
    if overlay[id] then return true end
    if api then
      local ok, r = pcall(api, id)
      if ok and not S.Is(r) and r ~= nil then
        known = true
        if r == true then return true end
      end
    end
  end
  if known then return false end
  return nil
end

-- ------------------------------------------------------------------ Gestionnaire de temps de recharge
-- Le Gestionnaire de Blizzard (Options > Améliorations de jeu) voit tes buffs en combat. Si un proc est
-- dans ses « Buffs suivis », son icône répond IsActive() en clair : Arcanum la lit, sans rien modifier.
local CDM_VIEWERS = { "BuffIconCooldownViewer", "BuffBarCooldownViewer" }
local CDM_KEYS = { "barrage", "clear", "heat", "power", "pom" }
local cdmKey = {}      -- [cooldownID] = clé, ou false
local cdm = {}         -- [clé] = true / false, relu à chaque passe
local cdmGone = {}     -- [clé] = depuis quand l'icône dit « inactif »
local cdmSeen = {}     -- [clé] = true si l'icône s'est déjà montrée active (preuve qu'elle est tenue à jour)
State.cdm = cdm

local function cdmKeyFor(cooldownID, f)
  local cached = cdmKey[cooldownID]
  if cached ~= nil then return cached or nil end
  local ids = {}
  local function add(v)
    v = S.Num(v)
    if v then ids[#ids + 1] = v end
  end
  if C_CooldownViewer and C_CooldownViewer.GetCooldownViewerCooldownInfo then
    local info = S.Call(C_CooldownViewer.GetCooldownViewerCooldownInfo, cooldownID)
    if type(info) == "table" and not S.IsTable(info) then
      add(info.spellID); add(info.overrideSpellID); add(info.overrideTooltipSpellID)
      local linked = info.linkedSpellIDs
      if type(linked) == "table" and not S.IsTable(linked) then
        for _, v in ipairs(linked) do add(v) end
      end
    end
  end
  for _, m in ipairs({ "GetSpellID", "GetBaseSpellID", "GetAuraSpellID" }) do
    if type(f[m]) == "function" then add((S.Call(f[m], f))) end
  end
  local found
  for _, id in ipairs(ids) do
    local key = Spells.KeyOf(id)
    if key then
      for _, k in ipairs(CDM_KEYS) do
        if k == key then found = key end
      end
    end
    if found then break end
  end
  if #ids > 0 then cdmKey[cooldownID] = found or false end
  return found
end

local function readIcons(...)
  for i = 1, select("#", ...) do
    local f = select(i, ...)
    if type(f) == "table" then
      local id = S.Num(f.cooldownID)
      if not id and type(f.GetCooldownID) == "function" then id = S.Num((S.Call(f.GetCooldownID, f))) end
      local key = id and cdmKeyFor(id, f)
      if key then
        local active
        if type(f.IsActive) == "function" then
          local v = S.Call(f.IsActive, f)
          if not S.Is(v) and type(v) == "boolean" then active = v end
        end
        if active == nil then
          local v = f.isActive
          if not S.Is(v) and type(v) == "boolean" then active = v end
        end
        if active ~= nil then cdm[key] = cdm[key] or active end
      end
    end
  end
end

local cdmScanned = -1
local function scanCDM(now)
  if now - cdmScanned < 0.25 then return end
  cdmScanned = now
  for _, k in ipairs(CDM_KEYS) do cdm[k] = nil end
  for _, name in ipairs(CDM_VIEWERS) do
    local viewer = _G[name]
    if type(viewer) == "table" and type(viewer.GetChildren) == "function" then
      pcall(readIcons, viewer:GetChildren())
    end
  end
  for _, k in ipairs(CDM_KEYS) do
    if cdm[k] == false then cdmGone[k] = cdmGone[k] or now else cdmGone[k] = nil end
    if cdm[k] == true then cdmSeen[k] = true end
  end
end

-- true : l'icône est active ; false : inactive depuis une demi-seconde (et digne de foi) ; nil : rien à en tirer.
local function cdmSays(key, now)
  if cdm[key] == true then return true end
  if cdm[key] == false and cdmSeen[key] and cdmGone[key] and now - cdmGone[key] >= 0.5 then return false end
  return nil
end

-- ------------------------------------------------------------------ procs
local function setProc(p, key, active, source, expire, duration, now)
  if active then
    if not p.active then
      p.active, p.since = true, now
      p.source = source
      p.duration = duration or dur(key)
      p.expire = expire or (p.duration and now + p.duration) or nil
      ns:Fire("PROC", key)
    else
      p.source = source
      if expire then p.expire = expire end
      if duration then p.duration = duration end
    end
  elseif p.active then
    p.active, p.since, p.expire, p.source = false, nil, nil, nil
    ns:Fire("PROC_END", key)
  end
end

local function updateClear(now)
  local p = State.clear
  local l = learn()
  local st, a = readAura("clear")
  local free = refsFree()
  if free == true then l.ccCost = true end   -- preuve : le coût annoncé suit bien les Idées claires
  if st == "up" then
    local expire, duration = auraTimes("clear", a)
    setProc(p, "clear", true, "aura", expire, duration, now)
  elseif st == "down" then
    setProc(p, "clear", false)
  elseif cdmSays("clear", now) == true then
    setProc(p, "clear", true, "gestionnaire", nil, nil, now)
    if p.expire and now >= p.expire then p.expire = nil end
  elseif free == true then
    setProc(p, "clear", true, "coût", nil, nil, now)
    if p.expire and now >= p.expire then p.expire = nil end
  elseif cdmSays("clear", now) == false then
    setProc(p, "clear", false)
  elseif free == false and l.ccCost then
    setProc(p, "clear", false)
  elseif p.active and p.expire and now >= p.expire then
    setProc(p, "clear", false)
  end
end

local function updateBarrage(now)
  local p = State.barrage
  local l = learn()
  local st, a = readAura("barrage")
  local settled = now - (lastCast.missiles or 0) > GRACE   -- le coût met un instant à revenir après le lancer
  local glow = overlayed("missiles")
  local cm, free = cost.missiles, refsFree()
  local byGlow = glow == true
  local byCost = cm == 0 and free == false
  if byGlow then l.mbGlow = true end   -- preuves : ces signaux existent bien dans ce client
  if byCost then l.mbCost = true end
  if st == "up" then
    local expire, duration = auraTimes("barrage", a)
    setProc(p, "barrage", true, "aura", expire, duration, now)
    return
  elseif st == "down" then
    setProc(p, "barrage", false)
    return
  end
  local icon = cdmSays("barrage", now)
  if icon == true then
    setProc(p, "barrage", true, "gestionnaire", nil, nil, now)
  elseif byGlow then
    setProc(p, "barrage", true, "surbrillance", nil, nil, now)
  elseif byCost then
    if settled then setProc(p, "barrage", true, "coût", nil, nil, now) end
  elseif icon == false then
    setProc(p, "barrage", false)
  elseif l.mbGlow and glow == false then
    setProc(p, "barrage", false)
  elseif l.mbCost and cm ~= nil and cm > 0 then
    setProc(p, "barrage", false)          -- les Projectiles coûtent du mana : pas de Barrage
  elseif p.active and p.expire and now >= p.expire then
    setProc(p, "barrage", false)          -- signal masqué (Idées claires) : on s'en remet à la durée
  end
  -- Le signal dit encore « actif » après la durée apprise : on garde le proc, sans minuteur.
  if p.active and p.expire and now >= p.expire then p.expire = nil end
end

local function updatePower(now)
  local p = State.power
  local st, a = readAura("power")
  if st == "up" then
    local expire, duration = auraTimes("power", a)
    setProc(p, "power", true, "aura", expire, duration, now)
  elseif st == "down" then
    setProc(p, "power", false)
  elseif cdmSays("power", now) ~= nil then
    setProc(p, "power", cdmSays("power", now), "gestionnaire", nil, nil, now)
  elseif p.active and p.expire and now >= p.expire then
    setProc(p, "power", false)
  end
end

local function updateEureka(now)
  local p = State.eureka
  local st, a = readAura("eureka")
  if st == "up" then
    local expire, duration = auraTimes("eureka", a)
    setProc(p, "eureka", true, "aura", expire, duration, now)
  elseif st == "down" then
    setProc(p, "eureka", false)
  elseif p.active and p.expire and now >= p.expire then
    setProc(p, "eureka", false)
  end
end

local function updatePom(now)
  local p = State.pom
  local st = readAura("pom")
  if st == "up" then
    setProc(p, "pom", true, "aura", nil, nil, now)
    p.expire = nil
  elseif st == "down" then
    setProc(p, "pom", false)
  elseif cdmSays("pom", now) ~= nil then
    setProc(p, "pom", cdmSays("pom", now), "gestionnaire", nil, nil, now)
  elseif p.active and p.since and now - p.since > 60 then
    setProc(p, "pom", false)
  end
  if p.active then p.expire = nil end
end

local function updateHeat(now)
  local h = State.heat
  if not Spells.Known("pyro") then
    h.stacks, h.ready, h.expire = nil, false, nil
    return
  end
  local st, a = readAura("heat")
  local was = h.ready
  if st == "up" then
    h.stacks = S.Num(a.applications) or 1
    if h.stacks < 1 then h.stacks = 1 end
    h.expire = auraTimes("heat", a)
    h.ready = h.stacks >= 3
  elseif st == "down" then
    h.stacks, h.expire, h.ready = 0, nil, false
  else
    h.expire = nil
    local glow = overlayed("pyro")
    local instant = Spells.CastTime("pyro") == 0 and not State.pom.active
    h.ready = glow == true or instant
    if cdmSays("heat", now) == false and not h.ready then
      h.stacks = 0      -- l'icône du Gestionnaire est éteinte : plus d'Échauffement
    else
      h.stacks = nil    -- le nombre de charges reste caché en combat
    end
  end
  if h.ready and not was then ns:Fire("PROC", "heat") end
end

-- ------------------------------------------------------------------ charges de Déflagration
local function setStacks(n, expire, source)
  local old = State.stacks
  State.stacks = n
  State.stacksExpire = n > 0 and expire or nil
  State.stacksSource = source
  if n ~= old then ns:Fire("STACKS", n, old) end
end

local function updateBlast(now)
  local l = learn()
  local st, a = readAura("blast")
  local c = cost.blast
  if st == "up" then
    local n = S.Num(a.applications) or 1
    if n < 1 then n = 1 end
    if n > MAX_STACKS then n = MAX_STACKS end
    local expire, duration = S.Num(a.expirationTime), S.Num(a.duration)
    if expire and expire <= 0 then expire = nil end
    -- La durée de l'aura n'est celle de la fenêtre entière qu'à la première charge : ensuite le jeu
    -- annonce le temps qu'il restait à l'arrivée de la dernière charge.
    if n == 1 and duration and duration > 0 then l.abWindow = duration end
    State.stacksDur = dur("blast")
    setStacks(n, expire, "aura")
    -- Le coût suit-il les charges ? On l'apprend ici, quand la vérité est connue.
    if l.abBase and c and c > 0 and not State.power.active and not State.eureka.active then
      local ratio = c / l.abBase
      if ratio >= 1.35 then
        l.costTracks = true
        l.abStep = (ratio - 1) / n
      end
    end
  elseif st == "down" then
    setStacks(0, nil, "aura")
    if c and c > 0 and not State.power.active and not State.clear.active and not State.eureka.active then
      l.abBase = c
    end
  else
    -- En combat : les charges viennent des Déflagrations lancées (voir onCast) ; on vérifie ici la fin
    -- de la fenêtre et, quand il est fiable, le coût annoncé, qui donne le nombre exact de charges.
    State.stacksDur = dur("blast")
    local cast = lastCast.blast
    if State.stacksSource == "aura" and State.stacks == 0 and cast and now - cast < 1.5 then
      setStacks(1, cast + State.stacksDur, "sorts")   -- Déflagration finie à l'instant où le combat commence
    end
    if State.stacks > 0 and State.stacksExpire and now >= State.stacksExpire then
      setStacks(0, nil, "durée")
      stacksEnded = now
    end
    -- Pas pendant le Pouvoir des Arcanes ni Eureka (ils changent le coût), ni juste après une
    -- Déflagration (le coût met un instant à suivre). Un coût nul (Idées claires) ne dit rien.
    if l.costTracks and l.abBase and l.abStep and l.abStep > 0 and c and c > 0
      and not State.power.active and not State.eureka.active and now - (cast or 0) > GRACE
      and now - stacksEnded > GRACE then
      local x = (c / l.abBase - 1) / l.abStep
      local n = math.floor(x + 0.5)
      if math.abs(x - n) < 0.2 and n >= 0 and n <= MAX_STACKS and n ~= State.stacks then
        setStacks(n, State.stacksExpire, "coût")   -- fin de fenêtre gardée si on la connaît
      end
    end
  end
end

-- ------------------------------------------------------------------ sorts lancés
local function onCast(spellID)
  spellID = S.Num(spellID)
  if not spellID then return end
  local key = Spells.KeyOf(spellID)
  if not key then return end
  local now = GetTime()
  if lastCast[key] and now - lastCast[key] < 0.25 then return end   -- même lancer vu par deux événements
  lastCast[key] = now

  if key == "blast" and State.restricted then
    if State.stacks > 0 and (not State.stacksExpire or State.stacksExpire > now) then
      -- une charge de plus ; la fenêtre ouverte par la première Déflagration n'est pas prolongée
      local n = State.stacks + 1
      if n > MAX_STACKS then n = MAX_STACKS end
      setStacks(n, State.stacksExpire, "sorts")
    else
      setStacks(1, now + dur("blast"), "sorts")   -- première charge : la fenêtre s'ouvre
    end
  end

  if key == "missiles" and State.barrage.active and State.barrage.source ~= "aura"
    and State.barrage.source ~= "gestionnaire" then
    setProc(State.barrage, "barrage", false)
  end
  if key == "eureka" then
    setProc(State.eureka, "eureka", true, "sorts", now + dur("eureka"), dur("eureka"), now)
  end
  if key == "power" then
    setProc(State.power, "power", true, "sorts", now + dur("power"), dur("power"), now)
  elseif key == "pom" then
    setProc(State.pom, "pom", true, "sorts", nil, nil, now)
    State.pom.expire = nil
  elseif CAST_TIME[key] and State.pom.active and State.pom.source ~= "aura"
    and State.pom.source ~= "gestionnaire" then
    setProc(State.pom, "pom", false)
  end
  State.dirty = true
  ns:Fire("CAST", key)
end
State.OnCast = onCast

-- ------------------------------------------------------------------ temps de recharge
-- Retourne une table réutilisable : start/duration lisibles, ou object (durée secrète à donner au widget).
-- onCD : true, false, ou nil si on ne sait pas.
local cdInfo = {}
local readyMemo = {}   -- [clé] = fin de recharge lue quand elle était lisible
function State.Cooldown(key)
  local r = cdInfo[key]
  if not r then r = {}; cdInfo[key] = r end
  r.start, r.duration, r.modRate, r.object, r.onCD, r.readyAt = nil, nil, nil, nil, nil, nil
  local now = GetTime()
  if State.demo then
    local d = State.demoCD and State.demoCD[key]
    if d and d.start + d.duration > now then
      r.start, r.duration, r.modRate, r.onCD, r.readyAt = d.start, d.duration, 1, true, d.start + d.duration
    else
      r.start, r.duration, r.onCD = 0, 0, false
    end
    return r
  end
  local id = Spells.Best(key)
  if not id or not (C_Spell and C_Spell.GetSpellCooldown) then return r end
  local info = S.Call(C_Spell.GetSpellCooldown, id)
  if type(info) == "table" and not S.IsTable(info) then
    local start, duration = S.Num(info.startTime), S.Num(info.duration)
    if start and duration then
      r.start, r.duration, r.modRate = start, duration, S.Num(info.modRate) or 1
      local enabled = info.isEnabled
      if S.Is(enabled) then enabled = true end
      r.onCD = duration > GCD_MAX and enabled ~= false and enabled ~= 0 and start + duration > now
      if r.onCD then
        r.readyAt = start + duration
        readyMemo[key] = r.readyAt
        local l = learn()
        if l.cd then l.cd[key] = duration end
      else
        readyMemo[key] = nil
      end
      return r
    end
  end
  -- Valeurs secrètes : le widget saura dessiner la durée ; pour « prêt ou non », on part du dernier lancer.
  if C_Spell.GetSpellCooldownDuration then
    r.object = S.Call(C_Spell.GetSpellCooldownDuration, id, true)
  end
  local cast = lastCast[key]
  local l = learn()
  local cd = (l.cd and l.cd[key]) or Spells.BaseCooldown(key) or DEFAULT_CD[key]
  local readyAt = cast and cd and cast + cd or nil
  local memo = readyMemo[key]
  if memo and (not readyAt or memo > readyAt) then readyAt = memo end
  if readyAt and readyAt > now then
    r.readyAt, r.onCD = readyAt, true
  else
    r.onCD = false   -- ni lancé ni en recharge à notre connaissance : considéré prêt
  end
  return r
end

-- Gemme de mana : objet, quantité, temps de recharge lisible.
local gemInfo = {}
function State.Gem()
  local r = gemInfo
  r.itemID, r.count, r.start, r.duration, r.onCD = nil, 0, nil, nil, nil
  if State.demo then return r end
  local itemID, count = Spells.Gem()
  if not itemID then return r end
  r.itemID, r.count = itemID, count
  local get = C_Container and C_Container.GetItemCooldown or GetItemCooldown
  if get then
    local start, duration = S.Call(get, itemID)
    start, duration = S.Num(start), S.Num(duration)
    if start and duration then
      r.start, r.duration = start, duration
      r.onCD = duration > GCD_MAX and start + duration > GetTime()
    end
  end
  return r
end

-- ------------------------------------------------------------------ prochain sort
-- Le sort à lancer ensuite. La priorité part du cycle Arcanes du guide Method (patch 1.60.1), adaptée à
-- ce qui a été mesuré en jeu : chaque charge double le coût de la Déflagration suivante, et rien ne les
-- consomme. On vise donc un nombre de charges (« charges visées », 2 par défaut), puis on en profite
-- avec des sorts qui ne coûtent pas plus cher :
--   1. Pouvoir des Arcanes dès qu'il est prêt ;
--   2. Projectiles des Arcanes sur un Barrage de projectiles ;
--   3. Déflagration sur des Idées claires (elle est gratuite, et la charge en plus aussi) ;
--   4. hors combat, sans charge : Courroux en ouverture (réglable) ;
--      charges visées atteintes, Courroux prêt : Eureka, puis Présence spirituelle, puis Courroux ;
--   5. gemme de mana, puis Évocation, sous 15 % de mana ;
--   6. sous les charges visées : Déflagration ;
--   7. charges visées atteintes : Éclair de givre ou Boule de feu (le moins cher), qui profitent des
--      charges et peuvent déclencher un Barrage ;
--   8. si le mana ne suit plus : Courroux, gemme de mana, Évocation, le sort le moins cher, la baguette.
-- Le réglage « conseiller les gros temps de recharge » retire Pouvoir des Arcanes, Eureka et Présence
-- spirituelle du conseil, pour les garder sous la main.
-- La variante Feu ajoute l'Explosion pyrotechnique sur 3 charges d'Échauffement et le Trait de feu.
-- Pendant une incantation ou une canalisation, le conseil ne bouge pas : il change quand le sort est
-- parti. Avec l'option « anticiper », il montre au contraire le sort d'après dès le début de
-- l'incantation, en tenant compte de ce que le sort en cours va changer (une charge de plus…).
local DEMO_KNOWN = { blast = true, wrath = true, missiles = true, pom = true, eureka = true, evoc = true }

local function known(key)
  if State.demo then return DEMO_KNOWN[key] == true end
  return Spells.Known(key)
end

local function ready(key)
  if not known(key) then return false end
  return State.Cooldown(key).onCD ~= true
end

-- false seulement si le jeu dit que le mana manque pour ce sort (cette réponse reste lisible en combat).
local function affordable(key)
  if State.demo then return true end
  local id = Spells.Best(key)
  if not (id and C_Spell and C_Spell.IsSpellUsable) then return true end
  local ok, usable, noMana = pcall(C_Spell.IsSpellUsable, id)
  if not ok or S.Is(usable) or S.Is(noMana) then return true end
  return noMana ~= true
end

-- true sous 15 % de mana, false au-dessus, nil si le jeu cache le mana.
local function manaLow()
  if State.demo or not (UnitPower and UnitPowerMax) then return nil end
  local cur = S.Num((S.Call(UnitPower, "player", 0)))
  local top = S.Num((S.Call(UnitPowerMax, "player", 0)))
  if cur and top and top > 0 then return cur / top < 0.15 end
  return nil
end

-- Le sort en cours d'incantation ou de canalisation : clé, début, fin (secondes). nil si aucun.
local castInfo = {}
local function readCast()
  State.cast = nil
  if State.demo then return end
  local key, startMs, endMs
  if UnitCastingInfo then
    local ok, _, _, _, s, e, _, _, _, spellID = pcall(UnitCastingInfo, "player")
    spellID = ok and S.Num(spellID) or nil
    if spellID then key, startMs, endMs = Spells.KeyOf(spellID) or "?", S.Num(s), S.Num(e) end
  end
  if not key and UnitChannelInfo then
    local ok, _, _, _, s, e, _, _, spellID = pcall(UnitChannelInfo, "player")
    spellID = ok and S.Num(spellID) or nil
    if spellID then key, startMs, endMs = Spells.KeyOf(spellID) or "?", S.Num(s), S.Num(e) end
  end
  -- (une incantation dont la fin est passée depuis un moment n'est plus en cours : on ne reste pas figé)
  if key and startMs and endMs and endMs > startMs and endMs / 1000 > GetTime() - 0.3 then
    castInfo.key, castInfo.start, castInfo.finish = key, startMs / 1000, endMs / 1000
    State.cast = castInfo
  end
end

-- Une gemme de mana en sac, prête à l'emploi ?
local function gemReady()
  if State.demo then return false end
  local gem = State.Gem()
  return gem.itemID ~= nil and gem.onCD ~= true
end

-- Le moins cher des deux sorts, parmi ceux qui sont connus et que le mana permet. nil si aucun.
local function cheapest(a, b)
  local okA = known(a) and affordable(a)
  local okB = known(b) and affordable(b)
  if okA and okB then
    return (cost[b] or math.huge) < (cost[a] or math.huge) and b or a
  end
  return okA and a or (okB and b) or nil
end

-- Nombre de charges visées (la démonstration joue le cycle complet, à 4 charges).
function State.Target()
  if State.demo then return MAX_STACKS end
  local db = ns.db or ns.DEFAULTS
  return db.targetStacks or 2
end

local function hostileTarget()
  if not (UnitExists and UnitCanAttack) then return false end
  local exists = S.Plain(S.Call(UnitExists, "target"))
  if not exists then return false end
  local hostile = S.Plain(S.Call(UnitCanAttack, "player", "target"))
  local dead = S.Plain(S.Call(UnitIsDead, "target"))
  return (hostile and not dead) and true or false
end

-- Retourne la clé du sort conseillé et la raison ("burst", "arcane", "barrage", "clear", "heat", "mana").
local function computeNext()
  local need = State.Target()
  local stacks = State.stacks
  local barrage, clear, pomActive = State.barrage.active, State.clear.active, State.pom.active
  local wrathReady = ready("wrath")
  local cast = State.cast
  if cast then
    if cast.key == "blast" then
      stacks = stacks > 0 and math.min(MAX_STACKS, stacks + 1) or 1
      clear = false
    elseif cast.key == "wrath" then
      wrathReady = false
    elseif cast.key == "missiles" then
      barrage = false
    end
    if CAST_TIME[cast.key] then pomActive = false end
  end
  local fighting = State.demo or State.combat or hostileTarget()
  local db = ns.db or ns.DEFAULTS
  local burst = State.demo or db.adviseBurst ~= false   -- conseiller les gros temps de recharge ?

  if burst and fighting and not State.power.active and ready("power") then return "power", "burst" end
  -- Le Barrage d'abord : les Projectiles sont gratuits, et une Déflagration lancée pendant qu'il est
  -- actif peut en déclencher un autre, qui serait perdu. (La Présence spirituelle, si elle est déjà
  -- active, n'est pas dépensée par une canalisation : elle attend le Courroux.)
  if barrage and known("missiles") then return "missiles", "barrage" end
  if known("pyro") then
    if State.heat.ready then return "pyro", "heat" end
    if ready("fireblast") and affordable("fireblast") then return "fireblast", "heat" end
  end
  local wrathNow = wrathReady and affordable("wrath")
  -- Présence spirituelle déjà lancée : elle va au Courroux, même sous des Idées claires
  if wrathNow and pomActive then return "wrath", "burst" end
  -- Les Idées claires vont à la Déflagration, le sort le plus cher : le Courroux les dépenserait aussi,
  -- pour deux fois moins de mana économisé, et la charge offerte serait perdue
  if clear and known("blast") then return "blast", "clear" end
  -- Ouverture : hors combat, le premier sort ne coûte pas de temps de combat. Autant y mettre la plus
  -- longue incantation, le Courroux (3,5 s, coût fixe), puis monter les charges une fois le combat lancé.
  if db.openWrath ~= false and wrathNow and stacks == 0 and not State.combat and not State.demo then
    return "wrath", "arcane"
  end
  if wrathNow and stacks >= need then
    if burst and not State.eureka.active and ready("eureka") then return "eureka", "burst" end
    if burst and ready("pom") then return "pom", "burst" end
    return "wrath", "arcane"
  end
  if State.combat and manaLow() == true then
    if gemReady() then return "gem", "mana" end
    if ready("evoc") then return "evoc", "mana" end
  end
  if stacks >= need then
    -- charges visées atteintes : une Déflagration de plus coûterait encore plus cher, un sort bon marché
    -- profite autant des charges
    local filler = cheapest("frostbolt", "fireball")
    if filler then return filler, "arcane" end
  end
  if known("blast") and affordable("blast") then return "blast", "arcane" end
  -- le mana ne suit plus
  if wrathNow then return "wrath", "arcane" end
  if State.combat and gemReady() then return "gem", "mana" end
  if State.combat and ready("evoc") then return "evoc", "mana" end
  local cheap = cheapest("frostbolt", "fireball")   -- du moins cher au plus cher
  if cheap then return cheap, "mana" end
  if known("missiles") and affordable("missiles") then return "missiles", "mana" end
  if known("shoot") then return "shoot", "mana" end
  for _, key in ipairs({ "blast", "frostbolt", "fireball" }) do
    if known(key) then return key, "arcane" end
  end
  return nil
end

local function updateNext()
  local db = ns.db or ns.DEFAULTS
  if State.cast and State.next and not db.anticipate then return end   -- on attend la fin du sort en cours
  local key, reason = computeNext()
  if key ~= State.next or reason ~= State.nextReason then
    local old = State.next
    State.next, State.nextReason = key, reason
    ns:Fire("NEXT", key, reason, old)
  end
end

-- L'affichage a-t-il quelque chose à montrer ?
function State.Live()
  if State.demo or State.combat then return true end
  if State.stacks > 0 or State.barrage.active or State.clear.active or State.power.active or State.pom.active then
    return true
  end
  return hostileTarget()
end

-- ------------------------------------------------------------------ boucle
function State.Update()
  local now = GetTime()
  State.dirty = false
  if State.demo then
    State.DemoTick(now)
  else
    State.restricted = aurasRestricted()
    readCosts()
    scanCDM(now)
    updatePower(now)
    updateEureka(now)
    updateClear(now)
    updateBarrage(now)
    updatePom(now)
    updateHeat(now)
    updateBlast(now)
  end
  readCast()
  updateNext()
  ns:Fire("STATE")
end

function State.Reset()
  State.stacks, State.stacksExpire, State.stacksSource = 0, nil, "aura"
  for _, p in ipairs({ State.barrage, State.clear, State.power, State.pom, State.eureka }) do
    p.active, p.since, p.expire, p.source = false, nil, nil, nil
  end
  State.heat.stacks, State.heat.ready = nil, false
  for k in pairs(overlay) do overlay[k] = nil end
  State.dirty = true
end

-- ------------------------------------------------------------------ démonstration
-- Un cycle scénarisé, pour voir le HUD sans combattre : /arc demo
local DEMO_LEN = 11
local DEMO_STEPS = { 0.6, 1.6, 2.6, 3.6, 4.4, 5.2, 6.0, 7.0, 9.5 }
function State.SetDemo(on)
  on = on and true or false
  if State.demo == on then return end
  State.demo = on
  State.Reset()
  State.demoStart = GetTime()
  State.demoStep = -1
  State.demoCD = {}
  ns:Fire("DEMO", on)
  State.Update()
end

function State.DemoTick(now)
  local t = (now - State.demoStart) % DEMO_LEN
  local step = #DEMO_STEPS
  for i, limit in ipairs(DEMO_STEPS) do
    if t < limit then step = i - 1; break end
  end
  if step == State.demoStep then return end
  State.demoStep = step
  if step == 0 then                 -- repos
    State.demoCD = {}
    setStacks(0, nil, "démo")
    for _, key in ipairs({ "barrage", "clear", "power", "pom", "eureka" }) do setProc(State[key], key, false) end
  elseif step >= 1 and step <= 4 then   -- quatre Déflagrations
    State.stacksDur = 9
    setStacks(step, step == 1 and now + 9 or State.stacksExpire, "démo")
    if step == 2 then
      setProc(State.clear, "clear", true, "démo", now + 15, 15, now)       -- Idées claires
    elseif step == 3 then
      setProc(State.clear, "clear", false)
      setProc(State.barrage, "barrage", true, "démo", now + 15, 15, now)   -- Barrage de projectiles
    elseif step == 4 then
      setProc(State.barrage, "barrage", false)                             -- dépensé par les Projectiles
    end
  elseif step == 5 then             -- Eureka
    setProc(State.eureka, "eureka", true, "démo", now + 8, 8, now)
    State.demoCD.eureka = { start = now, duration = 120 }
  elseif step == 6 then             -- Présence spirituelle
    setProc(State.pom, "pom", true, "démo", nil, nil, now)
    State.demoCD.pom = { start = now, duration = 180 }
  elseif step == 7 then             -- Courroux instantané
    setProc(State.pom, "pom", false)
    State.demoCD.wrath = { start = now, duration = 6 }
  elseif step == 8 then             -- Courroux en recharge : on patiente
  elseif step == 9 then             -- fin de la fenêtre des charges
    setStacks(0, nil, "démo")
    setProc(State.eureka, "eureka", false)
  end
end

-- ------------------------------------------------------------------ événements
local function playerOnly(unit)
  return not S.Is(unit) and unit == "player"
end

ns:On("START", function()
  Spells.Refresh()

  local ticker = CreateFrame("Frame")
  local acc = 0
  ticker:SetScript("OnUpdate", function(_, elapsed)
    acc = acc + elapsed
    local interval = State.Live() and 0.1 or 0.5
    if State.dirty or acc >= interval then
      acc = 0
      local ok, err = pcall(State.Update)
      if not ok then ns.Report(err) end
    end
  end)

  ns:RegisterEvent("PLAYER_REGEN_DISABLED", function() State.combat = true; State.dirty = true end)
  ns:RegisterEvent("PLAYER_REGEN_ENABLED", function() State.combat = false; State.dirty = true end)
  ns:RegisterEvent("PLAYER_ENTERING_WORLD", function()
    loadedAt = GetTime()
    State.combat = InCombatLockdown and InCombatLockdown() and true or false
    if not State.demo then State.Reset() end
  end)
  ns:RegisterEvent("PLAYER_DEAD", function() if not State.demo then State.Reset() end end)
  ns:RegisterUnitEvent("UNIT_AURA", "player", function(_, unit) if playerOnly(unit) then State.dirty = true end end)
  ns:RegisterEvent("PLAYER_TARGET_CHANGED", function() State.dirty = true end)

  ns:RegisterUnitEvent("UNIT_SPELLCAST_SUCCEEDED", "player", function(_, unit, _, spellID)
    if playerOnly(unit) and not State.demo then onCast(spellID) end
  end)
  ns:RegisterUnitEvent("UNIT_SPELLCAST_CHANNEL_START", "player", function(_, unit, _, spellID)
    if playerOnly(unit) and not State.demo then onCast(spellID) end
  end)

  -- début, fin ou interruption d'une incantation : le conseil porte sur le sort d'après
  local function casting(_, unit) if playerOnly(unit) then State.dirty = true end end
  for _, event in ipairs({ "UNIT_SPELLCAST_START", "UNIT_SPELLCAST_STOP", "UNIT_SPELLCAST_FAILED",
    "UNIT_SPELLCAST_INTERRUPTED", "UNIT_SPELLCAST_CHANNEL_STOP", "UNIT_SPELLCAST_DELAYED" }) do
    ns:RegisterUnitEvent(event, "player", casting)
  end

  local function cooldowns() State.dirty = true; ns:Fire("COOLDOWNS") end
  ns:RegisterEvent("SPELL_UPDATE_COOLDOWN", cooldowns)
  ns:RegisterEvent("SPELL_UPDATE_CHARGES", cooldowns)
  ns:RegisterEvent("SPELL_UPDATE_USABLE", function() State.dirty = true end)
  ns:RegisterEvent("BAG_UPDATE_COOLDOWN", cooldowns)
  ns:RegisterEvent("BAG_UPDATE_DELAYED", cooldowns)

  ns:RegisterEvent("SPELL_ACTIVATION_OVERLAY_GLOW_SHOW", function(_, spellID)
    spellID = S.Num(spellID)
    if spellID then overlay[spellID] = true; State.dirty = true end
  end)
  ns:RegisterEvent("SPELL_ACTIVATION_OVERLAY_GLOW_HIDE", function(_, spellID)
    spellID = S.Num(spellID)
    if spellID then overlay[spellID] = nil; State.dirty = true end
  end)

  local function respec() Spells.Refresh(); State.dirty = true end
  ns:RegisterEvent("SPELLS_CHANGED", respec)
  ns:RegisterEvent("PLAYER_TALENT_UPDATE", respec)
  ns:RegisterEvent("TRAIT_CONFIG_UPDATED", respec)
  ns:RegisterEvent("PLAYER_LEVEL_UP", respec)

  State.combat = InCombatLockdown and InCombatLockdown() and true or false
  State.dirty = true
end)
