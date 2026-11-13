-- Arcanum — Arcane mage spell catalog.
--
-- On WoW Forever, each rank of a spell has its own ID and names depend on the game's
-- language. So we start from a reference ID, read its name from the client, then find all
-- the ranks in the spellbook by that name.
local ADDON, ns = ...
local S = ns.Secret

local Spells = {}
ns.Spells = Spells

local pairs, ipairs, type, tonumber = pairs, ipairs, type, tonumber

-- id: reference ID; auras: possible IDs of the corresponding buff.
Spells.DEF = {
  -- what the HUD shows: charges, procs, active buffs
  blast     = { id = 400574, auras = { 400574, 400573 } },   -- Arcane Blast (charges)
  missiles  = { id = 5143 },                                 -- Arcane Missiles
  wrath     = { id = 1326079 },                              -- Arcane Wrath
  barrage   = { id = 400588, auras = { 400589, 400588 } },   -- Missile Barrage (talent, proc 400589)
  clear     = { id = 12536, auras = { 12536 }, talent = 11213, extra = { 11213 } },  -- Clearcasting (Arcane Concentration)
  power     = { id = 12042, auras = { 12042 } },             -- Arcane Power
  pom       = { id = 12043, auras = { 12043 } },             -- Presence of Mind
  -- a cast-time spell: like the ones below, it consumes Presence of Mind
  pyro      = { id = 11366 },                                -- Pyroblast
  -- racial buff shown while active
  eureka    = { id = 1259817, alt = { 1259813, 1259823, 1259812, 1259821 } },  -- Eureka (gnome racial, one ID per class)
  -- other spells: cast-time spells consume Presence of Mind, and some serve as cost references
  fireball  = { id = 133 },
  frostbolt = { id = 116 },
  frostfire = { id = 401502 },
  explosion = { id = 1449 },
  scorch    = { id = 2948 },
  flamestrike = { id = 2120 },
  poly      = { id = 118 },
  -- buffs to have before combat
  intellect = { id = 1459 },                                 -- Arcane Intellect
  brilliance = { id = 23028 },                               -- Arcane Brilliance (group version)
  magearmor = { id = 6117 },
  icearmor  = { id = 7302 },
  frostarmor = { id = 168 },
  -- (ranks: every rank, from first to last, in case the spellbook does not file them under a single name)
  water     = { id = 5504, ranks = { 5504, 5505, 5506, 6127, 10138, 10139, 10140, 468766 } },  -- Conjure Water
  food      = { id = 587, ranks = { 587, 597, 990, 6129, 10144, 10145, 28612 } },             -- Conjure Food
}

-- Mana gems (items), from best to worst, and the spells that conjure them.
Spells.GEMS = { 8008, 8007, 5513, 5514 }
Spells.GEM_SPELLS = { 10054, 10053, 3552, 759 }

local idToKey = {}     -- [spell ID] = key
local nameToKey = {}   -- [localized name] = key

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

-- All spells in the spellbook, grouped by name: { [name] = { { id, rank }, … } }
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
        if id and S.Plain(item.isOffSpec) ~= true then
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

-- Does this spell's aura stay readable in combat? The game classifies each spell once and for all
-- (never secret, always, depending on context). true / false, or nil if the client does not say.
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

-- Re-reads the spellbook: names, ranks, known spells. To be called again when spells or talents change.
function Spells.Refresh()
  idToKey, nameToKey = {}, {}
  local book = scanSpellBook()
  for key, def in pairs(Spells.DEF) do
    def.name = spellName(def.id) or def.name
    if not def.name and def.alt then
      for _, id in ipairs(def.alt) do
        def.name = spellName(id)
        if def.name then break end
      end
    end
    def.ids = { def.id }
    def.best = def.id
    def.known = false
    local entries = def.name and book[def.name]
    if entries then
      local top = -1
      for _, e in ipairs(entries) do
        if e.id ~= def.id then def.ids[#def.ids + 1] = e.id end
        if e.rank > top then top = e.rank; def.best = e.id end
      end
      def.known = true
    elseif isKnown(def.id) or (def.talent and isKnown(def.talent)) then
      def.known = true
    end
    if def.ranks then   -- the highest known rank, when the spellbook was not enough
      for i = #def.ranks, 1, -1 do
        if isKnown(def.ranks[i]) then
          if not def.known or def.best == def.id then def.best = def.ranks[i] end
          def.known = true
          break
        end
      end
    end
    def.auraPlain = auraNeverSecret(def)
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

-- ID of the highest known rank.
function Spells.Best(key)
  local def = Spells.DEF[key]
  return def and def.best or nil
end

-- Catalog key for a cast spell (by ID, then by name: a rank missing from the spellbook).
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

-- Mana cost of the spell, as the game announces it right now (charges and procs included).
-- Returns: cost, or nil + "none" (the game announces no cost) or nil + "unreadable".
function Spells.Cost(key)
  return Spells.CostOf(Spells.Best(key))
end

-- The same, for a specific spell ID (a given rank).
function Spells.CostOf(id)
  if not (id and C_Spell and C_Spell.GetSpellPowerCost) then return nil, "unreadable" end
  local ok, costs = pcall(C_Spell.GetSpellPowerCost, id)
  if not ok then return nil, "unreadable" end
  if S.Is(costs) then return nil, "unreadable" end
  if costs == nil then return nil, "none" end
  if type(costs) ~= "table" or S.IsTable(costs) then return nil, "unreadable" end
  local found = false
  for _, entry in ipairs(costs) do
    if type(entry) == "table" and not S.IsTable(entry) then
      local kind = S.Plain(entry.type)
      if kind == nil or kind == 0 then   -- 0: mana
        local cost = S.Num(entry.cost)
        if cost == nil then return nil, "unreadable" end
        return cost
      end
      found = true
    end
  end
  if found then return nil, "unreadable" end
  return nil, "none"
end

-- The mana gem conjuring spell the character knows (the best one), or nil.
function Spells.GemSpell()
  for _, id in ipairs(Spells.GEM_SPELLS) do
    if isKnown(id) then return id end
  end
  return nil
end

-- Conjured water and food, from best to worst (Forever database, 1.60.1):
-- each rank of Conjure Water or Conjure Food creates a different item. Only these items count:
-- bought water does not exempt you from conjuring some.
Spells.WATER = { 231778, 8079, 8078, 8077, 3772, 2136, 2288, 5350 }
Spells.FOOD = { 22895, 8076, 8075, 1487, 1114, 1113, 5349 }

local function carries(list)
  local count = C_Item and C_Item.GetItemCount or GetItemCount
  if not count then return false end
  for _, itemID in ipairs(list) do
    local n = S.Num(S.Call(count, itemID, false, true))
    if n and n > 0 then return true end
  end
  return false
end

-- Does the character have conjured water, conjured food?
function Spells.Supplies()
  return carries(Spells.WATER), carries(Spells.FOOD)
end

-- Is the mana gem created by this conjuring spell in the bags?
function Spells.HasGemOf(spellID)
  for i, id in ipairs(Spells.GEM_SPELLS) do
    if id == spellID then return carries({ Spells.GEMS[i] }) end
  end
  return false
end

-- Icon of a spell by ID.
function Spells.IconOf(id)
  if id and C_Spell and C_Spell.GetSpellTexture then
    return S.Plain(S.Call(C_Spell.GetSpellTexture, id))
  end
  return nil
end
