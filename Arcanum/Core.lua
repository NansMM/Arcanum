-- Arcanum — noyau : espace de noms, événements, réglages, lecture prudente des valeurs « secrètes ».
--
-- WoW Forever applique les règles d'addons de Midnight : en combat, le jeu rend « secrètes » la plupart
-- des données (auras, temps de recharge, mana). Un addon peut les afficher dans un widget, mais ni les
-- comparer ni calculer avec. Arcanum ne lit donc jamais une valeur sans vérifier qu'elle est lisible.
local ADDON, ns = ...

ns.ADDON = ADDON
ns.L = setmetatable({}, { __index = function(_, key) return key end })

local GetMeta = (C_AddOns and C_AddOns.GetAddOnMetadata) or GetAddOnMetadata
ns.VERSION = (GetMeta and GetMeta(ADDON, "Version")) or "0.8.0"

local pcall, type, pairs = pcall, type, pairs

-- ------------------------------------------------------------------ erreurs
local function report(err)
  ns.errorCount = (ns.errorCount or 0) + 1
  ns.lastError = tostring(err)
  local handler = geterrorhandler and geterrorhandler()
  if handler then handler(err) else print(err) end
end
ns.Report = report

-- ------------------------------------------------------------------ valeurs secrètes
local S = {}
ns.Secret = S

function S.Is(v)
  return issecretvalue ~= nil and issecretvalue(v) == true
end

function S.IsTable(t)
  return issecrettable ~= nil and issecrettable(t) == true
end

-- La valeur si elle est lisible, sinon nil.
function S.Plain(v)
  if S.Is(v) or v == nil then return nil end   -- l'ordre compte : comparer un secret lève une erreur
  return v
end

-- Un nombre lisible, sinon nil.
function S.Num(v)
  if S.Is(v) or type(v) ~= "number" then return nil end
  return v
end

-- Appel protégé : les fonctions gardées lèvent une erreur ou ne renvoient rien quand la donnée est secrète.
function S.Call(fn, ...)
  if type(fn) ~= "function" then return nil end
  local ok, a, b, c, d = pcall(fn, ...)
  if not ok then return nil end
  return a, b, c, d
end

-- Le jeu a-t-il le système de valeurs secrètes ?
S.RESTRICTED = issecretvalue ~= nil

-- ------------------------------------------------------------------ événements
local eventFrame = CreateFrame("Frame")
local handlers = {}

-- Retourne false si l'événement n'existe pas dans ce client (l'enregistrer lèverait une erreur).
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

-- Événement limité à une unité (évite d'être réveillé par les auras de tout le raid).
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

-- ------------------------------------------------------------------ bus interne
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

-- ------------------------------------------------------------------ réglages
ns.DEFAULTS = {
  enabled = true,
  locked = true,
  scale = 1.0,
  point = { "CENTER", "CENTER", 0, -170 },   -- ancre, ancre de l'écran, x, y
  showIdle = false,       -- afficher aussi hors combat, sans cible
  idleAlpha = 0.35,       -- opacité hors combat quand showIdle est actif
  showMana = false,       -- barre de mana sous le HUD
  showCooldowns = true,   -- gros temps de recharge de part et d'autre (Présence spirituelle, Eureka…)
  showCharges = true,     -- cristaux de charge au-dessus du prochain sort
  showProcs = true,       -- pastilles de proc sous le prochain sort (Barrage de projectiles, Idées claires)
  fillerRank = 1,         -- rang de l'Éclair de givre de remplissage : 1 (économe) ou "max" (plus de dégâts)
  burstOne = true,        -- montrer directement le Courroux pendant Eureka + Présence spirituelle (macro de burst)
  showReminders = true,   -- hors combat, signaler une amélioration manquante ou l'absence de gemme de mana
  cutForClear = true,     -- conseiller d'interrompre un sort bon marché quand des Idées claires arrivent
  openWrath = true,       -- hors combat, conseiller le Courroux pour engager
  adviseBurst = true,     -- conseiller les gros temps de recharge (Pouvoir des Arcanes, Eureka, Présence spirituelle)
  anticipate = false,     -- pendant une incantation, montrer déjà le sort d'après (sinon le conseil attend la fin)
  targetStacks = 2,       -- charges visées (2, 3 ou 4) : on monte jusque-là, puis Colère et sorts bon marché
  sound = true,
  flash = true,           -- petite onde autour du cercle quand un proc arrive
}

-- Ce que l'addon apprend en jeu quand les données sont lisibles (hors combat) : durées et coûts réels.
local LEARN_DEFAULTS = {
  dur = {},        -- [clé d'aura] = durée en secondes
  cd = {},         -- [clé de sort] = temps de recharge en secondes
  abBase = nil,    -- coût de la Déflagration sans charge
  abStep = nil,    -- surcoût par charge (1.75 = +175 %)
  costTracks = false,  -- le coût suit-il bien les charges ? (vérifié une fois hors combat)
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
  if type(db.point) ~= "table" or #db.point < 4 then db.point = { "CENTER", "CENTER", 0, -170 } end
  local saved = db.version or 1   -- version des réglages enregistrés, avant mise à niveau
  if saved < 3 then   -- 0.3 : « charges visées » remplace le seuil du Courroux et « garder le mana »
    if db.wrathStacks == 2 or db.wrathStacks == 3 then db.targetStacks = db.wrathStacks end
    db.wrathStacks, db.thrifty = nil, nil
  end
  if db.targetStacks ~= 2 and db.targetStacks ~= 3 and db.targetStacks ~= 4 then db.targetStacks = 2 end
  if db.fillerRank ~= 1 and db.fillerRank ~= "max" then db.fillerRank = 1 end
  if type(db.learn.dur) == "table" then db.learn.dur.blast = nil end   -- remplacé par abWindow (fenêtre de 18 s)
  db.spin = nil   -- 0.8 : plus de runes
  if saved < 2 then   -- 0.2 : HUD épuré, la barre de mana n'est plus affichée d'office
    db.showMana = false
  end
  db.version = 4
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

-- ------------------------------------------------------------------ divers
function ns.Print(msg)
  print("|cffb07cffArcanum|r " .. tostring(msg))
end

function ns.IsMage()
  local _, class = UnitClass("player")
  return class == "MAGE"
end

-- ------------------------------------------------------------------ démarrage
ns:RegisterEvent("ADDON_LOADED", function(_, name)
  if name ~= ADDON then return end
  ns.InitDB()
end)

-- Démarre le moteur et le HUD (une seule fois).
function ns.Start()
  if ns.started then return end
  ns.started = true
  ns:Fire("START")
end

ns:RegisterEvent("PLAYER_LOGIN", function()
  if not ns.db then ns.InitDB() end
  ns.isMage = ns.IsMage()
  if not ns.isMage then return end   -- l'addon reste endormi sur les autres classes
  ns.Start()
end)
