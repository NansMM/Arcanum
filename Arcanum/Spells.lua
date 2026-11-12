-- Arcanum — catalogue des sorts du mage Arcanes.
--
-- Sur WoW Forever, chaque rang d'un sort a son propre identifiant et les noms dépendent de la langue du
-- jeu. On part donc d'un identifiant de référence, on lit son nom dans le client, puis on retrouve tous
-- les rangs dans le grimoire par ce nom.
local ADDON, ns = ...
local S = ns.Secret

local Spells = {}
ns.Spells = Spells

local pairs, ipairs, type, tonumber = pairs, ipairs, type, tonumber

-- id : identifiant de référence ; auras : identifiants possibles de l'amélioration correspondante.
Spells.DEF = {
  -- cycle
  blast     = { id = 400574, auras = { 400574, 400573 } },   -- Déflagration des Arcanes (charges)
  missiles  = { id = 5143 },                                 -- Projectiles des Arcanes
  wrath     = { id = 1326079 },                              -- Courroux des Arcanes
  barrage   = { id = 400588, auras = { 400589, 400588 } },   -- Barrage de projectiles (talent, proc 400589)
  clear     = { id = 12536, auras = { 12536 }, talent = 11213, extra = { 11213 } },  -- Idées claires (Concentration des Arcanes)
  power     = { id = 12042, auras = { 12042 } },             -- Pouvoir des Arcanes
  pom       = { id = 12043, auras = { 12043 } },             -- Présence spirituelle
  evoc      = { id = 12051 },                                -- Évocation
  -- variante Arcanes / Feu
  pyro      = { id = 11366 },                                -- Explosion pyrotechnique
  fireblast = { id = 2136 },                                 -- Trait de feu
  heat      = { id = 400624, auras = { 400625, 400624 } },   -- Échauffement (talent, charges 400625)
  -- gros temps de recharge de race
  eureka    = { id = 1259817, alt = { 1259813, 1259823, 1259812, 1259821 } },  -- Eureka (racial gnome, un identifiant par classe)
  shoot     = { id = 5019 },                                 -- Tir (baguette)
  berserking = { id = 20554 },
  bloodfury = { id = 20572 },
  -- autres sorts de dégâts : ils comptent pour les charges et la Présence spirituelle
  fireball  = { id = 133 },
  frostbolt = { id = 116 },
  frostfire = { id = 401502 },
  explosion = { id = 1449 },
  scorch    = { id = 2948 },
  flamestrike = { id = 2120 },
  cone      = { id = 120 },
  blizzard  = { id = 10 },
  poly      = { id = 118 },
  -- améliorations à avoir avant le combat
  intellect = { id = 1459 },                                 -- Intelligence des Arcanes
  brilliance = { id = 23028 },                               -- Illumination des Arcanes (version de groupe)
  magearmor = { id = 6117 },
  icearmor  = { id = 7302 },
  frostarmor = { id = 168 },
}

-- Gemmes de mana (objets), de la meilleure à la moins bonne, et les sorts qui les invoquent.
Spells.GEMS = { 8008, 8007, 5513, 5514 }
Spells.GEM_SPELLS = { 10054, 10053, 3552, 759 }

local idToKey = {}     -- [identifiant de sort] = clé
local nameToKey = {}   -- [nom localisé] = clé

local function spellName(id)
  if C_Spell and C_Spell.GetSpellName then
    local name = S.Plain(S.Call(C_Spell.GetSpellName, id))
    if type(name) == "string" and name ~= "" then return name end
  end
  if GetSpellInfo then
    local name = S.Plain(S.Call(GetSpellInfo, id))
    if type(name) == "string" and name ~= "" then return name end
  end
  return nil
end
Spells.Name = function(key)
  local def = Spells.DEF[key]
  return def and def.name or nil
end

local function isKnown(id)
  local bank = Enum and Enum.SpellBookSpellBank and Enum.SpellBookSpellBank.Player or 0
  if C_SpellBook and C_SpellBook.IsSpellKnown then
    local known = S.Plain(S.Call(C_SpellBook.IsSpellKnown, id, bank))
    if known == true then return true end
  end
  if IsPlayerSpell then
    local known = S.Plain(S.Call(IsPlayerSpell, id))
    if known == true then return true end
  end
  if IsSpellKnown then
    local known = S.Plain(S.Call(IsSpellKnown, id))
    if known == true then return true end
  end
  return false
end

-- Tous les sorts du grimoire, rangés par nom : { [nom] = { { id, rang }, … } }
local function scanSpellBook()
  local byName = {}
  local SB = C_SpellBook
  if not (SB and SB.GetNumSpellBookSkillLines and SB.GetSpellBookSkillLineInfo and SB.GetSpellBookItemInfo) then
    return byName
  end
  local bank = Enum and Enum.SpellBookSpellBank and Enum.SpellBookSpellBank.Player or 0
  local lines = S.Num(S.Call(SB.GetNumSpellBookSkillLines)) or 0
  for line = 1, lines do
    local info = S.Call(SB.GetSpellBookSkillLineInfo, line)
    if type(info) == "table" and S.Num(info.itemIndexOffset) and S.Num(info.numSpellBookItems) then
      for i = info.itemIndexOffset + 1, info.itemIndexOffset + info.numSpellBookItems do
        local item = S.Call(SB.GetSpellBookItemInfo, i, bank)
        local id = type(item) == "table" and S.Num(item.spellID) or nil
        if id and not item.isOffSpec then
          local name = S.Plain(item.name)
          if type(name) ~= "string" or name == "" then name = spellName(id) end
          if name then
            local sub = S.Plain(item.subName)
            if (type(sub) ~= "string" or sub == "") and C_Spell and C_Spell.GetSpellSubtext then
              sub = S.Plain(S.Call(C_Spell.GetSpellSubtext, id))
            end
            local rank = type(sub) == "string" and tonumber(sub:match("%d+")) or 0
            local list = byName[name]
            if not list then list = {}; byName[name] = list end
            list[#list + 1] = { id = id, rank = rank or 0 }
          end
        end
      end
    end
  end
  return byName
end

-- L'aura de ce sort reste-t-elle lisible en combat ? Le jeu classe chaque sort une fois pour toutes
-- (jamais secret, toujours, selon le contexte). true / false, ou nil si le client ne le dit pas.
local function auraNeverSecret(def)
  local CS = C_Secrets
  if not (CS and CS.GetSpellAuraSecrecy) then return nil end
  local never = Enum and Enum.SecrecyLevel and Enum.SecrecyLevel.NeverSecret or 0
  for _, id in ipairs(def.auras or def.ids) do
    local ok, level = pcall(CS.GetSpellAuraSecrecy, id)
    if ok and not S.Is(level) and level == never then return true end
  end
  return false
end

-- Relit le grimoire : noms, rangs, sorts connus. À rappeler quand les sorts ou les talents changent.
function Spells.Refresh()
  idToKey, nameToKey = {}, {}
  local book = scanSpellBook()
  for key, def in pairs(Spells.DEF) do
    def.key = key
    def.name = spellName(def.id) or def.name
    if not def.name and def.alt then
      for _, id in ipairs(def.alt) do
        def.name = spellName(id)
        if def.name then break end
      end
    end
    def.ids = { def.id }
    def.best = def.id
    def.lowest = nil
    def.known = false
    local entries = def.name and book[def.name]
    if entries then
      local top, low = -1, nil
      for _, e in ipairs(entries) do
        if e.id ~= def.id then def.ids[#def.ids + 1] = e.id end
        if e.rank > top then top = e.rank; def.best = e.id end
        if e.rank > 0 and (not low or e.rank < low) then low = e.rank; def.lowest = e.id end
      end
      def.known = true
      -- le grimoire peut ne montrer que le dernier rang : l'identifiant de référence est le rang 1
      if def.lowest ~= def.id and isKnown(def.id) then def.lowest = def.id end
    elseif isKnown(def.id) or (def.talent and isKnown(def.talent)) then
      def.known = true
    end
    def.auraPlain = auraNeverSecret(def)
    def.baseCD = nil
    for _, id in ipairs(def.ids) do idToKey[id] = key end
    for _, list in ipairs({ def.auras or {}, def.extra or {} }) do
      for _, id in ipairs(list) do
        if not idToKey[id] then idToKey[id] = key end
      end
    end
    if def.name then nameToKey[def.name] = key end
  end
  ns:Fire("SPELLS")
end

function Spells.Get(key)
  return Spells.DEF[key]
end

function Spells.Known(key)
  local def = Spells.DEF[key]
  return def ~= nil and def.known == true
end

-- Identifiant du plus haut rang connu.
function Spells.Best(key)
  local def = Spells.DEF[key]
  return def and def.best or nil
end

-- Identifiant du plus bas rang connu (le rang 1 en général) ; à défaut, le plus haut.
function Spells.Lowest(key)
  local def = Spells.DEF[key]
  return def and (def.lowest or def.best) or nil
end

-- Clé du catalogue pour un sort lancé (par identifiant, puis par nom : un rang absent du grimoire).
function Spells.KeyOf(spellID)
  local key = idToKey[spellID]
  if key then return key end
  local name = spellName(spellID)
  key = name and nameToKey[name] or nil
  if key then idToKey[spellID] = key end
  return key
end

function Spells.Icon(key)
  local id = Spells.Best(key)
  if not id then return nil end
  if C_Spell and C_Spell.GetSpellTexture then
    local icon = S.Plain(S.Call(C_Spell.GetSpellTexture, id))
    if icon then return icon end
  end
  if GetSpellTexture then return S.Plain(S.Call(GetSpellTexture, id)) end
  return nil
end

-- Coût en mana du sort, tel que le jeu l'annonce maintenant (charges et procs compris).
-- Retourne : coût, ou nil + "aucun" (le jeu n'annonce aucun coût) ou nil + "illisible".
function Spells.Cost(key)
  return Spells.CostOf(Spells.Best(key))
end

-- Le même, pour un identifiant de sort précis (un rang donné).
function Spells.CostOf(id)
  if not (id and C_Spell and C_Spell.GetSpellPowerCost) then return nil, "illisible" end
  local ok, costs = pcall(C_Spell.GetSpellPowerCost, id)
  if not ok then return nil, "illisible" end
  if S.Is(costs) then return nil, "illisible" end
  if costs == nil then return nil, "aucun" end
  if type(costs) ~= "table" or S.IsTable(costs) then return nil, "illisible" end
  local found = false
  for _, entry in ipairs(costs) do
    if type(entry) == "table" and not S.IsTable(entry) then
      local kind = S.Plain(entry.type)
      if kind == nil or kind == 0 then   -- 0 : mana
        local cost = S.Num(entry.cost)
        if cost == nil then return nil, "illisible" end
        return cost
      end
      found = true
    end
  end
  if found then return nil, "illisible" end
  return nil, "aucun"
end

-- Temps d'incantation annoncé (secondes), ou nil.
function Spells.CastTime(key)
  local id = Spells.Best(key)
  if not (id and C_Spell and C_Spell.GetSpellInfo) then return nil end
  local info = S.Call(C_Spell.GetSpellInfo, id)
  if type(info) ~= "table" or S.IsTable(info) then return nil end
  local ms = S.Num(info.castTime)
  return ms and ms / 1000 or nil
end

-- Temps de recharge de base (secondes), ou nil.
function Spells.BaseCooldown(key)
  local def = Spells.DEF[key]
  if not def then return nil end
  if def.baseCD == nil then   -- ne change pas d'une passe à l'autre : lu une fois
    local ms = GetSpellBaseCooldown and S.Num(S.Call(GetSpellBaseCooldown, def.best))
    def.baseCD = (ms and ms > 0) and ms / 1000 or false
  end
  return def.baseCD or nil
end

-- La meilleure gemme de mana en sac : identifiant d'objet, quantité. nil si aucune.
function Spells.Gem()
  local count = C_Item and C_Item.GetItemCount or GetItemCount
  if not count then return nil end
  for _, itemID in ipairs(Spells.GEMS) do
    local n = S.Num(S.Call(count, itemID, false, true))
    if n and n > 0 then return itemID, n end
  end
  return nil
end

-- Le sort d'invocation de gemme de mana que le personnage connaît (le meilleur), ou nil.
function Spells.GemSpell()
  for _, id in ipairs(Spells.GEM_SPELLS) do
    if isKnown(id) then return id end
  end
  return nil
end

-- Icône d'un sort par identifiant.
function Spells.IconOf(id)
  if id and C_Spell and C_Spell.GetSpellTexture then
    return S.Plain(S.Call(C_Spell.GetSpellTexture, id))
  end
  return nil
end
