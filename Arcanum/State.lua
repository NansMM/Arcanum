-- Arcanum — state engine: Arcane Blast charges, procs, active buffs, pre-combat reminders.
--
-- Out of combat, auras are readable: that is the truth, and the addon uses it to learn the real durations
-- and costs. In combat, the game hides auras from addons. Arcanum then relies on what
-- remains readable:
--   * your own spell casts (UNIT_SPELLCAST_SUCCEEDED): each Arcane Blast adds a charge;
--   * the mana cost announced by the game: free Arcane Missiles = Missile Barrage,
--     everything free = Clearcasting, and the cost of Arcane Blast gives the exact number of charges
--     (the extra cost per charge is learned out of combat);
--   * the action button glow (SPELL_ACTIVATION_OVERLAY_GLOW_SHOW).
-- Arcanum only displays; it advises nothing and casts nothing.
local ADDON, ns = ...
local S = ns.Secret
local Spells = ns.Spells

local State = {
  combat = false,
  restricted = false,
  stacks = 0,           -- Arcane Blast charges (0 to 4)
  stacksExpire = nil,   -- GetTime() at expiry, or nil if unknown
  stacksDur = nil,
  stacksSource = "aura",
  barrage = { active = false },
  clear = { active = false },
  power = { active = false },    -- Arcane Power: it changes spell costs, and therefore how charges are read
  eureka = { active = false },   -- gnome racial: +10% damage, -10% cost on the following spells
  pom = { active = false },
  reminders = {},                -- what is missing before combat: { key, … }
  demo = false,
}
ns.State = State

local MAX_STACKS = 4
local GRACE = 0.7   -- delay before trusting a cost that contradicts a spell just cast

-- Default durations, replaced by those read in game as soon as an aura is readable.
local DEFAULT_DUR = { barrage = 15, clear = 15, power = 15, eureka = 8 }
-- Arcane Blast charges (measured in game, 1.60.1): the first Arcane Blast opens an 18 s window;
-- later ones add a charge without extending it, and no other spell consumes the charges.
local BLAST_WINDOW = 18
-- Spells with a cast time: they consume Presence of Mind.
local CAST_TIME = {
  blast = true, wrath = true, pyro = true, fireball = true, frostbolt = true, frostfire = true,
  scorch = true, flamestrike = true, poly = true,
}
-- Spells whose cost serves as the reference for Clearcasting (all free = proc).
local COST_REFS = { "blast", "frostbolt", "fireball", "explosion" }

local lastCast = {}      -- [key] = GetTime() of the last successful cast
local cost = {}          -- [key] = current cost (number) or nil
local seenCost = {}      -- [key] = true if a cost > 0 has already been read
local overlay = {}       -- [spell ID] = true if the button is glowing
local loadedAt = 0        -- GetTime() of the last world entry (loading screen)

-- What the game announces only changes when it sends an event. Each family of readings is therefore
-- kept in memory as long as nothing has made it stale; a safety re-read happens from time to time,
-- in case an event is missed.
local auraEpoch = 0       -- advances when the player's auras may have changed
local costsStale, costsAt = true, -10
local targetStale, targetAt = true, -10

-- Delay of the safety re-read: short when the HUD is tracking something, long when it is hidden.
local function slack()
  return State.live and 1 or 3
end

local function staleAll()
  auraEpoch = auraEpoch + 1
  costsStale, targetStale = true, true
  State.dirty = true
end
ns:On("SPELLS", staleAll)
local stacksEnded = 0     -- GetTime() of the last window end observed by the timer

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

-- ------------------------------------------------------------------ aura reading
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

-- "up" + aura, "down" (absent, for sure) or "unknown" (the game hides it).
local auraCache = {}   -- [key] = { epoch, at, restricted, status, aura, expire }

local function queryAura(def)
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
  -- Absent? Only if the game is hiding nothing right now, or if it classifies this aura as "never
  -- secret". (Do not remember this from one read to the next: an aura read once during a
  -- transition proves nothing for the rest of the fight.)
  if not State.restricted or def.auraPlain == true then return "down" end
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

local function readAura(key)
  local def = Spells.Get(key)
  if not def or not C_UnitAuras then return "unknown" end
  -- In combat, an aura the game does not classify as "never secret" is unreadable: no point asking for it.
  if State.restricted and def.auraPlain == false then return "unknown" end
  local now = GetTime()
  local c = auraCache[key]
  if c and c.restricted == State.restricted and not (c.expire and now >= c.expire) then
    if c.epoch == auraEpoch and now - c.at < slack() then
      return c.status, c.aura   -- nothing can have changed since the last read
    end
    if now - c.at < 0.1 then
      -- read less than a tenth of a second ago and aura events keep raining (a raid): the next pass will ask
      State.dirty = true
      return c.status, c.aura
    end
  end
  if not c then c = {}; auraCache[key] = c end
  local status, aura = queryAura(def)
  c.epoch, c.at, c.restricted, c.status, c.aura = auraEpoch, now, State.restricted, status, aura
  local expire = aura and S.Num(aura.expirationTime) or nil
  c.expire = (expire and expire > 0) and expire or nil
  return status, aura
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

-- ------------------------------------------------------------------ signals readable in combat
-- Only the costs that are used are read: Arcane Missiles (Missile Barrage) and the reference spells
-- (Clearcasting, charges). The list is rebuilt when the spellbook changes.
local costKeys = {}
ns:On("SPELLS", function()
  for i = #costKeys, 1, -1 do costKeys[i] = nil end
  for key in pairs(cost) do cost[key] = nil end
  if Spells.Known("missiles") then costKeys[#costKeys + 1] = "missiles" end
  for _, key in ipairs(COST_REFS) do
    if Spells.Known(key) then costKeys[#costKeys + 1] = key end
  end
end)

local function readCosts(now)
  local age = now - costsAt
  if age < 0.1 then   -- at most ten reads per second, even when events rain
    if costsStale then State.dirty = true end   -- (the next pass will read)
    return
  end
  if not costsStale and age < (State.live and 0.5 or 3) then return end
  costsStale, costsAt = false, now
  for i = 1, #costKeys do
    local key = costKeys[i]
    local c, why = Spells.Cost(key)
    if c and c > 0 then seenCost[key] = true end
    if c == nil and why == "none" and seenCost[key] then c = 0 end   -- the game no longer announces a cost: free
    cost[key] = c
  end
end

-- true: all reference spells are free; false: at least one has a cost; nil: unknown.
local function refsFree()
  local any = false
  for _, key in ipairs(COST_REFS) do
    if seenCost[key] and cost[key] ~= nil then
      if cost[key] > 0 then return false end
      any = true
    end
  end
  -- "everything is free" is not trusted right after a loading screen: the game does not announce costs yet
  if any and GetTime() - loadedAt >= 3 then return true end
  return nil
end

-- Is the button of one of the spell's ranks glowing? true, false or nil (unknown).
local overlayPoll = {}   -- [key] = { at, value }: last direct query
local function overlayed(key)
  local def = Spells.Get(key)
  if not def or not def.ids then return nil end
  for _, id in ipairs(def.ids) do
    if overlay[id] then return true end   -- reported by SPELL_ACTIVATION_OVERLAY_GLOW_SHOW
  end
  local now = GetTime()
  local p = overlayPoll[key]
  if p and now - p.at < 1 then return p.value end
  if not p then p = {}; overlayPoll[key] = p end
  p.at, p.value = now, nil
  local api = C_SpellActivationOverlay and C_SpellActivationOverlay.IsSpellOverlayed or IsSpellOverlayed
  if not api then return nil end
  local known = false
  for _, id in ipairs(def.ids) do
    local ok, r = pcall(api, id)
    if ok and not S.Is(r) and r ~= nil then
      known = true
      if r == true then p.value = true; return true end
    end
  end
  if known then p.value = false end
  return p.value
end

-- ------------------------------------------------------------------ Cooldown Manager
-- Blizzard's Cooldown Manager (Options > Gameplay Enhancements) sees your buffs in combat. If a proc is
-- in its "Tracked Buffs", its icon answers IsActive() in plain: Arcanum reads it, without modifying anything.
local CDM_VIEWERS = { "BuffIconCooldownViewer", "BuffBarCooldownViewer" }
local CDM_KEYS = { "barrage", "clear", "power", "pom" }
local cdmKey = {}      -- [cooldownID] = key, or false
local cdm = {}         -- [key] = true / false, re-read on every scan (five per second at most)
local cdmMiss = {}     -- [cooldownID] = when the icon last gave no spell id (asked again a few seconds later)
local cdmGone = {}     -- [key] = since when the icon has said "inactive"
local cdmSeen = {}     -- [key] = true if the icon has already shown as active (proof that it is kept up to date)
State.cdm = cdm

local function cdmKeyFor(cooldownID, f)
  local cached = cdmKey[cooldownID]
  if cached ~= nil then return cached or nil end
  local miss = cdmMiss[cooldownID]
  if miss and GetTime() - miss < 5 then return nil end
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
  if #ids > 0 then
    cdmKey[cooldownID] = found or false
  else
    cdmMiss[cooldownID] = GetTime()
  end
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
  if now - cdmScanned < 0.2 then return end
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

-- true: the icon is active; false: inactive for half a second (and trustworthy); nil: nothing to learn from it.
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

-- A proc kept past its learned duration because its signal still said "active" has no timer left. If that
-- signal then turns unreadable (neither yes nor no) for a few seconds, the proc ends: it must not stay lit
-- until the end of combat.
local function unconfirmed(p, now)
  return p.active and not p.expire and p.seen ~= nil and now - p.seen > 3
end

local function updateClear(now)
  local p = State.clear
  local l = learn()
  local st, a = readAura("clear")
  local free = refsFree()
  if free == true then l.ccCost = true end   -- proof: the announced cost does follow Clearcasting
  if st == "up" then
    local expire, duration = auraTimes("clear", a)
    setProc(p, "clear", true, "aura", expire, duration, now)
  elseif st == "down" then
    setProc(p, "clear", false)
  elseif cdmSays("clear", now) == true then
    setProc(p, "clear", true, "manager", nil, nil, now)
    if p.expire and now >= p.expire then p.expire = nil end
    p.seen = now
  elseif free == true then
    setProc(p, "clear", true, "cost", nil, nil, now)
    if p.expire and now >= p.expire then p.expire = nil end
    p.seen = now
  elseif cdmSays("clear", now) == false then
    setProc(p, "clear", false)
  elseif free == false and l.ccCost then
    setProc(p, "clear", false)
  elseif p.active and p.expire and now >= p.expire then
    setProc(p, "clear", false)
  elseif unconfirmed(p, now) then
    setProc(p, "clear", false)
  end
end

local function updateBarrage(now)
  local p = State.barrage
  local l = learn()
  local st, a = readAura("barrage")
  local settled = now - (lastCast.missiles or 0) > GRACE   -- the cost takes a moment to come back after the cast
  local glow = overlayed("missiles")
  local cm, free = cost.missiles, refsFree()
  local byGlow = glow == true
  local byCost = cm == 0 and free == false
  if byGlow then l.mbGlow = true end   -- proofs: these signals do exist in this client
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
    setProc(p, "barrage", true, "manager", nil, nil, now)
    p.seen = now
  elseif byGlow or byCost then
    -- right after Arcane Missiles, the glow and the cost still show the proc that was just spent
    if settled then
      setProc(p, "barrage", true, byGlow and "glow" or "cost", nil, nil, now)
      p.seen = now
    end
  elseif icon == false then
    setProc(p, "barrage", false)
  elseif l.mbGlow and glow == false then
    setProc(p, "barrage", false)
  elseif l.mbCost and cm ~= nil and cm > 0 then
    setProc(p, "barrage", false)          -- Arcane Missiles cost mana: no Missile Barrage
  elseif p.active and p.expire and now >= p.expire then
    setProc(p, "barrage", false)          -- signal masked (Clearcasting): fall back on the duration
  end
  -- The signal still says "active" after the learned duration: keep the proc, without a timer.
  if p.active and p.expire and now >= p.expire then p.expire = nil end
  if unconfirmed(p, now) then setProc(p, "barrage", false) end
end

local function updatePower(now)
  local p = State.power
  if not p.active and not Spells.Known("power") then return end
  local st, a = readAura("power")
  if st == "up" then
    local expire, duration = auraTimes("power", a)
    setProc(p, "power", true, "aura", expire, duration, now)
  elseif st == "down" then
    setProc(p, "power", false)
  elseif cdmSays("power", now) ~= nil then
    setProc(p, "power", cdmSays("power", now), "manager", nil, nil, now)
  elseif p.active and p.expire and now >= p.expire then
    setProc(p, "power", false)
  end
end

local function updateEureka(now)
  local p = State.eureka
  if not p.active and not Spells.Known("eureka") then return end
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
  if not p.active and not Spells.Known("pom") then return end
  local st = readAura("pom")
  if st == "up" then
    setProc(p, "pom", true, "aura", nil, nil, now)
    p.expire = nil
  elseif st == "down" then
    setProc(p, "pom", false)
  elseif cdmSays("pom", now) ~= nil then
    setProc(p, "pom", cdmSays("pom", now), "manager", nil, nil, now)
  elseif p.active and p.since and now - p.since > 60 then
    setProc(p, "pom", false)
  end
  if p.active then p.expire = nil end
end

-- ------------------------------------------------------------------ Arcane Blast charges
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
    -- The aura's duration is that of the whole window only at the first charge: after that the game
    -- announces the time that was left when the last charge arrived.
    if n == 1 and duration and duration > 0 then l.abWindow = duration end
    State.stacksDur = dur("blast")
    setStacks(n, expire, "aura")
    -- Does the cost follow the charges? We learn it here, when the truth is known.
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
    -- In combat: charges come from the Arcane Blasts cast (see onCast); here we check the end
    -- of the window and, when it is reliable, the announced cost, which gives the exact number of charges.
    State.stacksDur = dur("blast")
    local cast = lastCast.blast
    if State.stacksSource == "aura" and State.stacks == 0 and cast and now - cast < 1.5 then
      setStacks(1, cast + State.stacksDur, "casts")   -- Arcane Blast finished at the very moment combat starts
    end
    if State.stacks > 0 and State.stacksExpire and now >= State.stacksExpire then
      setStacks(0, nil, "timer")
      stacksEnded = now
    end
    -- Not during Arcane Power or Eureka (they change the cost), nor right after an
    -- Arcane Blast (the cost takes a moment to follow). A zero cost (Clearcasting) says nothing.
    if l.costTracks and l.abBase and l.abStep and l.abStep > 0 and c and c > 0
      and not State.power.active and not State.eureka.active and now - (cast or 0) > GRACE
      and now - stacksEnded > GRACE then
      local x = (c / l.abBase - 1) / l.abStep
      local n = math.floor(x + 0.5)
      if math.abs(x - n) < 0.2 and n >= 0 and n <= MAX_STACKS and n ~= State.stacks then
        setStacks(n, State.stacksExpire, "cost")   -- window end kept if we know it
      end
    end
  end
end

-- ------------------------------------------------------------------ spell casts
-- Can the spell just cast end this proc? Yes when the proc is inferred. A proc read from its aura before
-- combat can no longer be verified once auras are hidden: the cast ends it too. Not when Blizzard's
-- Cooldown Manager shows it: its icon is the truth.
local function inferred(p)
  return p.source ~= "manager" and (State.restricted or p.source ~= "aura")
end

local function onCast(spellID)
  spellID = S.Num(spellID)
  if not spellID then return end
  local key = Spells.KeyOf(spellID)
  if not key then return end
  local now = GetTime()
  if lastCast[key] and now - lastCast[key] < 0.25 then return end   -- same cast seen by two events
  lastCast[key] = now

  if key == "blast" and State.restricted then
    if State.stacks > 0 and (not State.stacksExpire or State.stacksExpire > now) then
      -- one more charge; the window opened by the first Arcane Blast is not extended
      local n = State.stacks + 1
      if n > MAX_STACKS then n = MAX_STACKS end
      setStacks(n, State.stacksExpire, "casts")
    else
      setStacks(1, now + dur("blast"), "casts")   -- first charge: the window opens
    end
  end

  if key == "missiles" and State.barrage.active and inferred(State.barrage) then
    setProc(State.barrage, "barrage", false)
  end
  if key == "eureka" then
    setProc(State.eureka, "eureka", true, "casts", now + dur("eureka"), dur("eureka"), now)
  end
  if key == "power" then
    setProc(State.power, "power", true, "casts", now + dur("power"), dur("power"), now)
  elseif key == "pom" then
    setProc(State.pom, "pom", true, "casts", nil, nil, now)
    State.pom.expire = nil
  elseif CAST_TIME[key] and State.pom.active and inferred(State.pom) then
    setProc(State.pom, "pom", false)
  end
  State.dirty = true
  ns:Fire("CAST", key)
end

local function hostileTarget()
  if not (UnitExists and UnitCanAttack) then return false end
  local exists = S.Plain(S.Call(UnitExists, "target"))
  if not exists then return false end
  local hostile = S.Plain(S.Call(UnitCanAttack, "player", "target"))
  local dead = S.Plain(S.Call(UnitIsDead, "target"))
  return (hostile and not dead) and true or false
end

-- ------------------------------------------------------------------ pre-combat reminders
-- Out of combat, buffs are readable: we flag what is missing before engaging.
local ARMORS = { "magearmor", "icearmor", "frostarmor" }
local remindedAt = -10
local function updateReminders(now)
  local list = State.reminders
  local db = ns.db or ns.DEFAULTS
  if State.restricted or State.demo or State.combat or db.showReminders == false then
    for i = #list, 1, -1 do list[i] = nil end
    remindedAt = -10
    return
  end
  if now - remindedAt < 1 then return end   -- out of combat, one read per second is enough
  remindedAt = now
  for i = #list, 1, -1 do list[i] = nil end
  if Spells.Known("intellect") and readAura("intellect") == "down" and readAura("brilliance") ~= "up" then
    list[#list + 1] = "intellect"
  end
  local armor, worn = nil, false
  for _, key in ipairs(ARMORS) do
    if Spells.Known(key) then
      armor = armor or key
      if readAura(key) == "up" then worn = true end
    end
  end
  if armor and not worn then list[#list + 1] = armor end
  -- water, food and mana gem: to conjure when the bags have run out
  if Spells.Known("water") or Spells.Known("food") then
    local water, food = Spells.Supplies()
    if Spells.Known("water") and not water then list[#list + 1] = "water" end
    if Spells.Known("food") and not food then list[#list + 1] = "food" end
  end
  local gemSpell = Spells.GemSpell()   -- the best gem the character can conjure
  if gemSpell and not Spells.HasGemOf(gemSpell) then list[#list + 1] = "gemspell" end
end

-- ------------------------------------------------------------------ in-game checks
-- What the game lets addons read in combat is written nowhere: Arcanum observes it and records it, for
-- the /arc diag report.
local function updateChecks(now)
  local l = learn()
  if type(l.checks) ~= "table" then l.checks = {} end
  local c = l.checks
  if State.restricted and not (c.mana and c.usable and c.cooldown) then
    if UnitPower then
      local ok, v = pcall(UnitPower, "player", 0)
      if ok then c.mana = S.Is(v) and "secret" or "readable" end
    end
    local id = Spells.Best("blast")
    if id and C_Spell and C_Spell.IsSpellUsable then
      local ok, usable, noMana = pcall(C_Spell.IsSpellUsable, id)
      if ok then c.usable = (S.Is(usable) or S.Is(noMana)) and "secret" or "readable" end
    end
    if id and C_Spell and C_Spell.GetSpellCooldown then
      local info = S.Call(C_Spell.GetSpellCooldown, id)
      if type(info) == "table" and not S.IsTable(info) then
        c.cooldown = S.Is(info.startTime) and "secret" or "readable"
      end
    end
  end
end

-- Does the display have something to show? Computed once per pass (State.live), read every frame.
local function refreshLive()
  State.live = State.demo or State.combat or State.hostile or State.stacks > 0 or State.barrage.active
    or State.clear.active or State.pom.active or State.eureka.active
end

-- ------------------------------------------------------------------ loop
function State.Update()
  local now = GetTime()
  State.dirty = false
  if targetStale or now - targetAt >= 0.5 then
    targetStale, targetAt = false, now
    State.hostile = hostileTarget()
  end
  if State.demo then
    State.DemoTick(now)
    updateReminders(now)   -- (clears them: the demo shows no reminder)
  else
    State.restricted = aurasRestricted()
    readCosts(now)
    scanCDM(now)
    updatePower(now)
    updateEureka(now)
    updateClear(now)
    updateBarrage(now)
    updatePom(now)
    updateBlast(now)
    updateReminders(now)
    updateChecks(now)
  end
  refreshLive()
  ns:Fire("STATE")
end

function State.Reset()
  State.stacks, State.stacksExpire, State.stacksSource = 0, nil, "aura"
  for _, p in ipairs({ State.barrage, State.clear, State.power, State.pom, State.eureka }) do
    p.active, p.since, p.expire, p.source = false, nil, nil, nil
  end
  for k in pairs(overlay) do overlay[k] = nil end
  -- procs found again after a reset are not announced twice (costs are trusted 3 s after a loading screen)
  State.quietUntil = GetTime() + 4
  State.dirty = true
end

-- ------------------------------------------------------------------ demo
-- A scripted cycle, to see the HUD without fighting: /arc demo
local DEMO_LEN = 11
local DEMO_STEPS = { 0.6, 1.6, 2.6, 3.6, 4.4, 5.2, 6.0, 7.0, 9.5 }
function State.SetDemo(on)
  on = on and true or false
  if State.demo == on then return end
  State.demo = on
  State.Reset()
  State.demoStart = GetTime()
  State.demoStep = -1
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
  if step == 0 then                 -- idle
    setStacks(0, nil, "demo")
    for _, key in ipairs({ "barrage", "clear", "power", "pom", "eureka" }) do setProc(State[key], key, false) end
  elseif step >= 1 and step <= 4 then   -- four Arcane Blasts
    State.stacksDur = 9
    setStacks(step, step == 1 and now + 9 or State.stacksExpire, "demo")
    if step == 2 then
      setProc(State.clear, "clear", true, "demo", now + 15, 15, now)       -- Clearcasting
    elseif step == 3 then
      setProc(State.barrage, "barrage", true, "demo", now + 15, 15, now)   -- Missile Barrage, as well
    elseif step == 4 then
      setProc(State.barrage, "barrage", false)                             -- spent by Arcane Missiles
      setProc(State.clear, "clear", false)                                 -- spent by Arcane Blast
    end
  elseif step == 5 then             -- Eureka
    setProc(State.eureka, "eureka", true, "demo", now + 8, 8, now)
  elseif step == 6 then             -- Presence of Mind
    setProc(State.pom, "pom", true, "demo", nil, nil, now)
  elseif step == 7 then             -- instant Arcane Wrath
    setProc(State.pom, "pom", false)
  elseif step == 9 then             -- end of the charge window
    setStacks(0, nil, "demo")
    setProc(State.eureka, "eureka", false)
  end
end

-- ------------------------------------------------------------------ events
local function playerOnly(unit)
  return not S.Is(unit) and unit == "player"
end

ns:On("START", function()
  Spells.Refresh()

  local ticker = CreateFrame("Frame")
  local acc = 0
  ticker:SetScript("OnUpdate", function(_, elapsed)
    acc = acc + elapsed
    -- 10 passes per second when there is something to track, 1 when the HUD is hidden; a game
    -- event brings the next pass forward, never exceeding 20 per second (events pour in during combat)
    local interval = State.live and 0.1 or 1
    if acc >= interval or (State.dirty and acc >= 0.05) then
      acc = 0
      local ok, err = pcall(State.Update)
      if not ok then ns.Report(err) end
    end
  end)

  ns:RegisterEvent("PLAYER_REGEN_DISABLED", function() State.combat = true; staleAll() end)
  ns:RegisterEvent("PLAYER_REGEN_ENABLED", function()
    State.combat = false
    staleAll()
  end)
  ns:RegisterEvent("PLAYER_ENTERING_WORLD", function()
    loadedAt = GetTime()
    staleAll()
    State.combat = InCombatLockdown and InCombatLockdown() and true or false
    if not State.demo then State.Reset() end
  end)
  ns:RegisterEvent("PLAYER_DEAD", function() if not State.demo then State.Reset() end end)
  ns:RegisterUnitEvent("UNIT_AURA", "player", function(_, unit)
    if playerOnly(unit) then
      auraEpoch = auraEpoch + 1
      costsStale = true      -- a proc changes spell costs
      State.dirty = true
    end
  end)
  ns:RegisterEvent("PLAYER_TARGET_CHANGED", function() targetStale = true; State.dirty = true end)

  -- a spell cast can change everything at once: auras and costs
  local function cast(_, unit, _, spellID)
    if not playerOnly(unit) then return end
    auraEpoch = auraEpoch + 1
    costsStale = true
    State.dirty = true
    if not State.demo then onCast(spellID) end
  end
  ns:RegisterUnitEvent("UNIT_SPELLCAST_SUCCEEDED", "player", cast)
  ns:RegisterUnitEvent("UNIT_SPELLCAST_CHANNEL_START", "player", cast)

  ns:RegisterEvent("SPELL_UPDATE_USABLE", function() costsStale = true; State.dirty = true end)
  -- the bags changed (something conjured or used up): read the reminders again right away
  ns:RegisterEvent("BAG_UPDATE_DELAYED", function() remindedAt = -10; State.dirty = true end)

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
