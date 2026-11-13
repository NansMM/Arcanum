-- Arcanum — core: namespace, events, settings, careful reading of "secret" values.
--
-- WoW Forever applies Midnight's addon rules: in combat, the game makes most data "secret"
-- (auras, cooldowns, mana). An addon can display them in a widget, but can neither
-- compare them nor compute with them. So Arcanum never reads a value without checking that it is readable.
local ADDON, ns = ...

ns.L = setmetatable({}, { __index = function(_, key) return key end })

local GetMeta = (C_AddOns and C_AddOns.GetAddOnMetadata) or GetAddOnMetadata
ns.VERSION = (GetMeta and GetMeta(ADDON, "Version")) or "2.1.0"

local pcall, type, pairs, ipairs = pcall, type, pairs, ipairs

-- ------------------------------------------------------------------ errors
local function report(err)
  ns.errorCount = (ns.errorCount or 0) + 1
  ns.lastError = tostring(err)
  local handler = geterrorhandler and geterrorhandler()
  if handler then handler(err) else print(err) end
end
ns.Report = report

-- ------------------------------------------------------------------ secret values
local S = {}
ns.Secret = S

function S.Is(v)
  return issecretvalue ~= nil and issecretvalue(v) == true
end

function S.IsTable(t)
  return issecrettable ~= nil and issecrettable(t) == true
end

-- The value if it is readable, otherwise nil.
function S.Plain(v)
  if S.Is(v) or v == nil then return nil end   -- order matters: comparing a secret raises an error
  return v
end

-- A readable number, otherwise nil.
function S.Num(v)
  if S.Is(v) or type(v) ~= "number" then return nil end
  return v
end

-- Protected call: guarded functions raise an error or return nothing when the data is secret.
function S.Call(fn, ...)
  if type(fn) ~= "function" then return nil end
  local ok, a, b, c, d = pcall(fn, ...)
  if not ok then return nil end
  return a, b, c, d
end

-- Does the game have the secret values system?
S.RESTRICTED = issecretvalue ~= nil

-- ------------------------------------------------------------------ events
local eventFrame = CreateFrame("Frame")
local handlers = {}

-- Returns false if the event does not exist in this client (registering it would raise an error).
function ns:RegisterEvent(event, fn)
  local list = handlers[event]
  if not list then
    if not pcall(eventFrame.RegisterEvent, eventFrame, event) then return false end
    list = {}
    handlers[event] = list
  end
  list[#list + 1] = fn
  return true
end

eventFrame:SetScript("OnEvent", function(_, event, ...)
  local list = handlers[event]
  if not list then return end
  for i = 1, #list do
    local ok, err = pcall(list[i], event, ...)
    if not ok then report(err) end
  end
end)

-- Event limited to one unit (avoids being woken up by the auras of the whole raid).
function ns:RegisterUnitEvent(event, unit, fn)
  local f = CreateFrame("Frame")
  if not (f.RegisterUnitEvent and pcall(f.RegisterUnitEvent, f, event, unit)) then
    return ns:RegisterEvent(event, fn)
  end
  f:SetScript("OnEvent", function(_, ev, ...)
    local ok, err = pcall(fn, ev, ...)
    if not ok then report(err) end
  end)
  return true
end

-- ------------------------------------------------------------------ internal bus
local listeners = {}

function ns:On(message, fn)
  local list = listeners[message]
  if not list then list = {}; listeners[message] = list end
  list[#list + 1] = fn
end

function ns:Fire(message, ...)
  local list = listeners[message]
  if not list then return end
  for i = 1, #list do
    local ok, err = pcall(list[i], ...)
    if not ok then report(err) end
  end
end

-- ------------------------------------------------------------------ settings
ns.DEFAULTS = {
  enabled = true,
  locked = true,
  scale = 1.0,
  point = { "CENTER", "CENTER", 0, 0 },      -- anchor, screen anchor, x, y: the HUD is centered on the character
  spread = 150,           -- spread: distance between the character and the zones (procs, charges, reminders)
  decor = true,           -- proc decoration: the game's rune arc, on the outer side of each icon
  showCharges = true,     -- charge crystals above the character, when there are charges
  showProcs = true,       -- proc icons: Clearcasting on the left, Missile Barrage on the right, Arcane Power, Presence of Mind and Eureka at the top
  showReminders = true,   -- out of combat, flag what is missing: Arcane Intellect, armor, conjured water, food and mana gem
  sound = true,
  soundKit = {},          -- game sounds chosen in place of the original ones: [clear|barrage] = ID, or "voice"
  flash = true,           -- light wave when a proc arrives: an echo of the rune arc (a ring, without decoration)
}

-- Settings from previous versions, which no longer exist (next-spell advice, burst, old decorations).
local RETIRED = { "wrathStacks", "thrifty", "spin", "showNext", "showMana", "showCooldowns", "soonSeconds", "chargeArt",
  "burstRemind", "showIdle", "idleAlpha", "fillerRank", "burstOne", "cutForClear", "openWrath", "adviseBurst", "anticipate", "targetStacks" }

-- What the addon learns in game when data is readable (out of combat): real durations and costs.
local LEARN_DEFAULTS = {
  dur = {},        -- [aura key] = duration in seconds
  abBase = nil,    -- cost of Arcane Blast with no charge
  abStep = nil,    -- extra cost per charge (1.75 = +175%)
  costTracks = false,  -- does the cost really follow the charges? (checked once out of combat)
}

local function copyDefaults(dst, src)
  for k, v in pairs(src) do
    if dst[k] == nil then
      if type(v) == "table" then
        local t = {}
        for i, x in pairs(v) do t[i] = x end
        dst[k] = t
      else
        dst[k] = v
      end
    end
  end
end

function ns.InitDB()
  if type(ArcanumDB) ~= "table" then ArcanumDB = {} end
  local db = ArcanumDB
  copyDefaults(db, ns.DEFAULTS)
  if type(db.learn) ~= "table" then db.learn = {} end
  copyDefaults(db.learn, LEARN_DEFAULTS)
  if type(db.point) ~= "table" or #db.point < 4 then db.point = { "CENTER", "CENTER", 0, 0 } end
  local saved = db.version or 1   -- version of the saved settings, before upgrade
  for _, key in ipairs(RETIRED) do db[key] = nil end
  db.learn.cd = nil
  if type(db.learn.dur) == "table" then db.learn.dur.blast = nil end   -- replaced by abWindow (18 s window)
  if type(db.soundKit) ~= "table" then db.soundKit = {} end
  db.soundKit.burst = nil
  for key, value in pairs(db.soundKit) do
    if value == "voix" then db.soundKit[key] = "voice" end   -- 2.0: values saved in English
  end
  if saved < 5 then db.point = { "CENTER", "CENTER", 0, 0 } end   -- 1.0: the HUD is re-centered on the character
  if saved < 6 then
    -- 2.0: the position is saved in screen units (it was in the HUD's own scaled units)
    local scale, p = type(db.scale) == "number" and db.scale or 1, db.point
    if type(p[3]) == "number" and type(p[4]) == "number" then p[3], p[4] = p[3] * scale, p[4] * scale end
    if type(db.learn.checks) == "table" then   -- observations of the removed burst macro check
      db.learn.checks.burstGap, db.learn.checks.pomChannel = nil, nil
    end
  end
  if db.decor == "aucun" then   -- 1.4: a single decoration, shown or not (before: a decoration name)
    db.decor = false
  elseif type(db.decor) ~= "boolean" then
    db.decor = true
  end
  if type(db.spread) ~= "number" or db.spread < 80 or db.spread > 320 then db.spread = 150 end
  db.version = 6
  ns.db = db
  return db
end

function ns.ResetDB()
  ArcanumDB = nil
  ns.InitDB()
  ns:Fire("SETTINGS")
end

function ns.Set(key, value)
  if not ns.db then return end
  ns.db[key] = value
  ns:Fire("SETTINGS", key)
end

-- ------------------------------------------------------------------ misc
function ns.Print(msg)
  print("|cffb07cffArcanum|r " .. tostring(msg))
end

function ns.IsMage()
  local _, class = UnitClass("player")
  return class == "MAGE"
end

-- ------------------------------------------------------------------ startup
ns:RegisterEvent("ADDON_LOADED", function(_, name)
  if name ~= ADDON then return end
  ns.InitDB()
end)

-- Starts the engine and the HUD (once only).
function ns.Start()
  if ns.started then return end
  ns.started = true
  ns:Fire("START")
end

ns:RegisterEvent("PLAYER_LOGIN", function()
  if not ns.db then ns.InitDB() end
  ns.isMage = ns.IsMage()
  if not ns.isMage then return end   -- the addon stays dormant on other classes
  ns.Start()
end)
