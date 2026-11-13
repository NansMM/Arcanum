-- Jeu simulé pour tester Arcanum (Lua 5.1) : un mage de WoW Forever, avec les règles des valeurs secrètes.
--
-- En combat (M.combat), comme dans le vrai client :
--   * les auras ne sont plus lisibles (GetPlayerAuraBySpellID ne renvoie rien) ;
--   * les temps de recharge et le mana arrivent en valeurs secrètes : les comparer ou calculer avec
--     lève une erreur, seuls les widgets les acceptent ;
--   * le coût des sorts, les sorts lancés et la surbrillance des boutons restent lisibles.
-- Le simulateur est strict : appeler une méthode de widget qui n'existe pas lève une erreur.
local M = {
  now = 1000, combat = false, events = {}, unitEvents = {}, updaters = {}, errors = {},
  auras = {},        -- [nom] = { spellId, applications, duration, expirationTime }
  cooldowns = {},    -- [id] = { start, duration }
  overlays = {},
  neverSecret = {},  -- [nom d'aura] = true : lisible même en combat
  class = "MAGE", level = 60,
  mana = 5000, manaMax = 8000,
  costAware = true,  -- le coût annoncé suit-il les charges et les procs ?
  widgetCalls = {},
}
Mock = M

-- ------------------------------------------------------------------ valeurs secrètes
local SECRET = setmetatable({}, { __mode = "k" })
function M.secret(real)
  local v = newproxy(false)
  SECRET[v] = real == nil and true or real
  return v
end
function issecretvalue(v) return SECRET[v] ~= nil end
function issecrettable(t) return false end
local function reveal(v) if SECRET[v] ~= nil then return SECRET[v] end return v end
local function restricted() return M.combat end

-- ------------------------------------------------------------------ sorts
-- nom français, comme dans un client frFR : l'addon ne doit dépendre d'aucun nom anglais.
M.spells = {
  [400574] = { name = "Déflagration des Arcanes", cost = 100, cast = 1500, known = true },
  [5143] = { name = "Projectiles des Arcanes", cost = 85, cast = 0, rank = 1, known = true },
  [5144] = { name = "Projectiles des Arcanes", cost = 140, cast = 0, rank = 2, known = true },
  [25345] = { name = "Projectiles des Arcanes", cost = 655, cast = 0, rank = 8, known = true },
  [1326079] = { name = "Courroux des Arcanes", cost = 300, cast = 3500, known = true, cd = 6 },
  [400588] = { name = "Barrage de projectiles", passive = true, known = true },
  [12536] = { name = "Idées claires" },
  [11213] = { name = "Concentration des Arcanes", passive = true, known = true },
  [12042] = { name = "Pouvoir des Arcanes", cost = 0, known = true, cd = 180 },
  [12043] = { name = "Présence spirituelle", cost = 0, known = true, cd = 180 },
  [12051] = { name = "Évocation", cost = 0, known = true, cd = 480 },
  [11366] = { name = "Explosion pyrotechnique", cost = 125, cast = 6000, known = false },
  [2136] = { name = "Trait de feu", cost = 40, cast = 0, known = true, cd = 8 },
  [400624] = { name = "Échauffement" },
  [2139] = { name = "Contresort", cost = 100, known = true, cd = 30 },
  [1953] = { name = "Transfert", cost = 120, known = true, cd = 15 },
  [122] = { name = "Nova de givre", cost = 55, known = true, cd = 25 },
  [11958] = { name = "Bloc de glace", known = false },
  [1259817] = { name = "Eurêka !", known = true, cd = 120 },
  [5019] = { name = "Tir", known = true },
  [20554] = { name = "Berserker", known = false },
  [20572] = { name = "Fureur sanguinaire", known = false },
  [133] = { name = "Boule de feu", cost = 30, cast = 1500, rank = 1, known = true },
  [116] = { name = "Éclair de givre", cost = 25, cast = 1500, rank = 1, known = true },
  [8400] = { name = "Boule de feu", cost = 140, cast = 3000, rank = 5, known = true },
  [8406] = { name = "Éclair de givre", cost = 100, cast = 3000, rank = 5, known = true },
  [1459] = { name = "Intelligence des Arcanes", cost = 60, known = true },
  [6117] = { name = "Armure du mage", cost = 80, known = true },
  [7302] = { name = "Armure de glace", cost = 80, known = true },
  [10] = { name = "Blizzard", cost = 320, known = true },
  [401502] = { name = "Éclair de givrefeu", known = false },
  [1449] = { name = "Explosion des Arcanes", cost = 75, known = true },
  [2948] = { name = "Brûlure", known = false },
  [2120] = { name = "Choc de flammes", cost = 330, cast = 3000, known = true },
  [120] = { name = "Cône de froid", known = false },
  [118] = { name = "Métamorphose", cost = 60, cast = 1500, known = true },
  [10054] = { name = "Invocation d'un rubis de mana", known = true },
  [5504] = { name = "Invocation d'eau", cost = 60, known = true },
  [587] = { name = "Invocation de nourriture", cost = 60, known = true },
  [430] = { name = "Boisson" },
  [433] = { name = "Nourriture" },
}
M.items = { [8008] = 1, [8079] = 20, [8076] = 20 }   -- en sac : une gemme de mana, de l'eau et de la nourriture invoquées
M.itemSpells = {}   -- [objet] = nom de son effet d'utilisation (« Boisson », « Nourriture »…)
M.resting = false   -- au repos en ville

local function auraOf(name) return M.auras[name] end

-- Coût annoncé par le jeu, charges et procs compris (si costAware).
local function currentCost(id)
  local sp = M.spells[id]
  if not sp or not sp.cost then return nil end
  local cost = sp.cost
  if not M.costAware then return cost end
  if auraOf("Idées claires") then return 0 end
  if sp.name == "Projectiles des Arcanes" and auraOf("Barrage de projectiles") then return 0 end
  if sp.name == "Déflagration des Arcanes" then
    local a = auraOf("Déflagration des Arcanes")
    if a then cost = cost * (1 + a.applications) end   -- +100 % par charge (mesuré en jeu)
  end
  if auraOf("Pouvoir des Arcanes") then cost = cost * 0.7 end
  if auraOf("Eurêka !") then cost = cost * 0.9 end
  return cost
end
M.currentCost = currentCost

C_Spell = {}
function C_Spell.GetSpellName(id) local sp = M.spells[id]; return sp and sp.name or nil end
function C_Spell.GetSpellSubtext(id) local sp = M.spells[id]; return sp and sp.rank and ("Rang " .. sp.rank) or "" end
function C_Spell.GetSpellTexture(id) return M.spells[id] and (130000 + id % 1000) or nil end
function C_Spell.GetSpellPowerCost(id)
  local cost = currentCost(id)
  if cost == nil then return nil end
  if cost == 0 and M.freeMeansNil then return nil end
  return { { type = 0, cost = cost, minCost = cost, name = "MANA" } }
end
function C_Spell.IsSpellUsable(id)   -- lisible en combat : utilisable, mana insuffisant
  local cost = currentCost(id) or 0
  local enough = M.mana >= cost
  return enough, not enough
end
function C_Spell.IsSpellInRange(id, unit)   -- lisible en combat ; nil sans cible
  if M.target ~= true then return nil end
  return M.inRange ~= false
end
function C_Spell.GetSpellInfo(id)
  local sp = M.spells[id]
  if not sp then return nil end
  local cast = sp.cast or 0
  if sp.name == "Explosion pyrotechnique" and M.pyroInstant then cast = 0 end
  return { name = sp.name, iconID = 130000, castTime = cast, spellID = id, minRange = 0, maxRange = 30 }
end
function C_Spell.GetSpellCooldown(id)
  if not M.spells[id] then return nil end
  local cd = M.cooldowns[id] or { start = 0, duration = 0 }
  if restricted() then
    return { startTime = M.secret(cd.start), duration = M.secret(cd.duration), isEnabled = M.secret(true), modRate = M.secret(1) }
  end
  return { startTime = cd.start, duration = cd.duration, isEnabled = true, modRate = 1 }
end
function C_Spell.GetSpellCooldownDuration(id, ignoreGCD)
  if not M.spells[id] then return nil end
  return { _durationObject = true, id = id }
end
function GetSpellBaseCooldown(id) local sp = M.spells[id]; return sp and sp.cd and sp.cd * 1000 or 0 end

Enum = { SpellBookSpellBank = { Player = 0, Pet = 1 }, PowerType = { Mana = 0 } }
C_SpellBook = {}
local function book()
  local list = {}
  for id, sp in pairs(M.spells) do
    if sp.known then list[#list + 1] = { spellID = id, name = sp.name, isPassive = sp.passive or false, subName = sp.rank and ("Rang " .. sp.rank) or "" } end
  end
  table.sort(list, function(a, b) return a.spellID < b.spellID end)
  return list
end
function C_SpellBook.GetNumSpellBookSkillLines() return 1 end
function C_SpellBook.GetSpellBookSkillLineInfo(i) return { name = "Arcanes", itemIndexOffset = 0, numSpellBookItems = #book() } end
function C_SpellBook.GetSpellBookItemInfo(i, bank) return book()[i] end
function C_SpellBook.IsSpellKnown(id, bank) local sp = M.spells[id]; return sp ~= nil and sp.known == true end

C_SpellActivationOverlay = {}
function C_SpellActivationOverlay.IsSpellOverlayed(id) return M.overlays[id] == true end

-- ------------------------------------------------------------------ auras
C_UnitAuras = {}
local function auraData(name)
  local a = M.auras[name]
  if not a then return nil end
  if restricted() and not M.neverSecret[name] then return nil end   -- RequiresNonSecretAura : ne renvoie rien
  return { spellId = a.spellId, name = name, applications = a.applications or 0, duration = a.duration or 0,
    expirationTime = a.expirationTime or 0, auraInstanceID = 1 }
end
function C_UnitAuras.GetPlayerAuraBySpellID(id)
  local sp = M.spells[id]
  if not sp then return nil end
  local a = M.auras[sp.name]
  if a and a.spellId == id then return auraData(sp.name) end
  return nil
end
function C_UnitAuras.GetAuraDataBySpellName(unit, name, filter)
  if unit ~= "player" then error("unité inattendue", 2) end
  return auraData(name)
end

C_Secrets = {}
function C_Secrets.ShouldAurasBeSecret() return restricted() end
function C_Secrets.ShouldSpellAuraBeSecret(id)   -- par sort : une aura « jamais secrète » reste lisible
  local sp = M.spells[id]
  if sp and M.neverSecret[sp.name] then return false end
  return restricted()
end
function C_Secrets.GetSpellAuraSecrecy(id)   -- 0 : jamais secrète ; 2 : selon le contexte (le cas courant)
  local sp = M.spells[id]
  if sp and M.neverSecret[sp.name] then return 0 end
  return 2
end

-- ------------------------------------------------------------------ unités
function UnitClass(unit) return "Mage", M.class end
function UnitLevel(unit) return M.level end
function UnitPower(unit, kind) if restricted() then return M.secret(M.mana) end return M.mana end
function UnitPowerMax(unit, kind) return M.manaMax end
function UnitPowerPercent(unit, kind, unmodified, curve) error("courbe non simulée") end
function UnitCastingInfo(unit)   -- le sort en cours du joueur reste lisible en combat
  local c = M.casting
  if not c then return nil end
  return M.spells[c.id].name, M.spells[c.id].name, 130000, c.startMs, c.endMs, false, "Cast-3-0", false, c.id
end
function UnitChannelInfo(unit) return nil end
function M.startCast(id, seconds)
  M.casting = { id = id, startMs = M.now * 1000, endMs = (M.now + seconds) * 1000 }
  M.fire("UNIT_SPELLCAST_START", "player", "Cast-3-0", id)
end
function M.stopCast()
  M.casting = nil
  M.fire("UNIT_SPELLCAST_STOP", "player", "Cast-3-0", 0)
end
function UnitExists(unit) return M.target == true end
function UnitCanAttack(a, b) return M.target == true end
function UnitIsDead(unit) return false end
function InCombatLockdown() return M.combat end
function GetTime() return M.now end
function GetBuildInfo() return "1.60.1", "70888", "Nov 10 2026", 16001 end
function GetLocale() return "frFR" end
function PlaySound(id, channel)
  M.sounds = (M.sounds or 0) + 1
  M.lastKit = id
  if id == 999999 then return nil end   -- identifiant inconnu : le jeu ne joue rien
  return true
end
-- Synthèse vocale : une voix installée d'origine ; Mock.voices = {} pour un client sans voix.
M.voices = { { voiceID = 7, name = "Hortense" } }
M.spoken = {}
C_VoiceChat = {}
function C_VoiceChat.GetTtsVoices() return M.voices end
function C_VoiceChat.SpeakText(voiceID, text, rate, volume, overlap)
  if type(voiceID) ~= "number" or type(text) ~= "string" or type(rate) ~= "number" or type(volume) ~= "number" then
    error("SpeakText : arguments invalides", 2)
  end
  M.spoken[#M.spoken + 1] = text
end
C_TTSSettings = {}
function C_TTSSettings.GetVoiceOptionID(kind) return 7 end
-- (le fichier « ne joue pas » : l'addon retombe alors sur PlaySound, que les tests comptent)
function PlaySoundFile(path, channel)
  M.soundFiles = M.soundFiles or {}
  M.soundFiles[#M.soundFiles + 1] = path
  return false
end
function geterrorhandler() return function(err) M.errors[#M.errors + 1] = tostring(err) end end
function tinsert(t, v) table.insert(t, v) end
UISpecialFrames = {}
-- macros du joueur : { name, icon, body, perCharacter }
M.macros = {}
function GetMacroIndexByName(name)
  for i, m in ipairs(M.macros) do if m.name == name then return i end end
  return 0
end
function CreateMacro(name, icon, body, perCharacter)
  if M.combat then error("action protégée en combat", 2) end
  if #name > 16 then error("nom de macro trop long", 2) end
  if #body > 255 then error("macro trop longue", 2) end
  M.macros[#M.macros + 1] = { name = name, icon = icon, body = body, perCharacter = perCharacter }
  return #M.macros
end
function EditMacro(index, name, icon, body)
  if M.combat then error("action protégée en combat", 2) end
  local m = M.macros[index]
  if not m then error("macro inconnue", 2) end
  m.name, m.body = name or m.name, body or m.body
  return index
end
SlashCmdList = {}
C_AddOns = { GetAddOnMetadata = function(addon, field) return M.meta and M.meta[field] end }
C_Item = {
  GetItemCount = function(id) return M.items[id] or 0 end,
  GetItemIconByID = function(id) return 134000 + id % 100 end,
  GetItemSpell = function(id) return M.itemSpells[id] end,
}
-- (les sacs : tous les objets de M.items, rangés dans le sac à dos par identifiant croissant)
local function bagSlots()
  local ids = {}
  for id, n in pairs(M.items) do
    if n and n > 0 then ids[#ids + 1] = id end
  end
  table.sort(ids)
  return ids
end
C_Container = {
  GetItemCooldown = function(id) return 0, 0, 1 end,
  GetContainerNumSlots = function(bag) return bag == 0 and #bagSlots() or 0 end,
  GetContainerItemID = function(bag, slot) return bag == 0 and bagSlots()[slot] or nil end,
}
function IsResting() return M.resting == true end

-- ------------------------------------------------------------------ widgets (stricts)
local function num(v, what)
  if SECRET[v] ~= nil then error("valeur secrète refusée pour " .. what, 3) end
  if type(v) ~= "number" or v ~= v then error("nombre attendu pour " .. what .. ", reçu " .. tostring(v), 3) end
end
local function numOrSecret(v, what)   -- les widgets d'affichage acceptent les secrets
  if SECRET[v] ~= nil then return end
  if type(v) ~= "number" or v ~= v then error("nombre attendu pour " .. what .. ", reçu " .. tostring(v), 3) end
end
local POINTS = { TOPLEFT = 1, TOP = 1, TOPRIGHT = 1, LEFT = 1, CENTER = 1, RIGHT = 1, BOTTOMLEFT = 1, BOTTOM = 1, BOTTOMRIGHT = 1 }
local LAYERS = { BACKGROUND = 1, BORDER = 1, ARTWORK = 1, OVERLAY = 1, HIGHLIGHT = 1 }
local STRATA = { BACKGROUND = 1, LOW = 1, MEDIUM = 1, HIGH = 1, DIALOG = 1, FULLSCREEN = 1, TOOLTIP = 1 }

local Region = {}
function Region:SetPoint(point, a, b, c, d)
  if not POINTS[point] then error("ancre invalide : " .. tostring(point), 2) end
  local rel, relPoint, x, y = a, b, c, d
  if type(a) == "number" then rel, relPoint, x, y = nil, point, a, b end
  if type(rel) == "string" then rel, relPoint, x, y = nil, rel, b, c end
  if relPoint ~= nil and not POINTS[relPoint] then error("ancre relative invalide : " .. tostring(relPoint), 2) end
  if x ~= nil then num(x, "x") end
  if y ~= nil then num(y, "y") end
  self._points = self._points or {}
  self._points[#self._points + 1] = { point, rel, relPoint or point, x or 0, y or 0 }
end
function Region:ClearAllPoints() self._points = {} end
function Region:SetAllPoints(rel) self._points = { { "TOPLEFT", rel, "TOPLEFT", 0, 0 } } end
function Region:GetPoint(i) local p = self._points and self._points[i or 1]; if p then return p[1], p[2], p[3], p[4], p[5] end end
function Region:SetSize(w, h) num(w, "largeur"); num(h, "hauteur"); self._w, self._h = w, h end
function Region:SetWidth(w) num(w, "largeur"); self._w = w end
function Region:SetHeight(h) num(h, "hauteur"); self._h = h end
function Region:GetWidth() return self._w or 0 end
function Region:GetHeight() return self._h or 0 end
function Region:Show() self._shown = true end
function Region:Hide() self._shown = false end
function Region:SetShown(v) self._shown = v and true or false end
function Region:IsShown() return self._shown ~= false end
function Region:SetAlpha(a) numOrSecret(a, "alpha"); self._alpha = a end
function Region:GetAlpha() return self._alpha or 1 end
function Region:GetParent() return self._parent end

local function class(...)
  local c = {}
  for _, base in ipairs({ ... }) do for k, v in pairs(base) do c[k] = v end end
  return c
end

local Texture = class(Region)
function Texture:SetTexture(t, wrapH, wrapV)
  if t ~= nil and type(t) ~= "string" and type(t) ~= "number" then error("texture invalide : " .. tostring(t), 2) end
  self._tex = t
end
function Texture:SetTexCoord(...) for i = 1, select("#", ...) do num((select(i, ...)), "coordonnée") end end
function Texture:SetVertexColor(r, g, b, a)
  numOrSecret(r, "r"); numOrSecret(g, "g"); numOrSecret(b, "b"); if a ~= nil then numOrSecret(a, "a") end
  self._color = { r, g, b, a }
  if a ~= nil then self._alpha = a end   -- comme en jeu : l'opacité donnée ici est celle de SetAlpha
end
function Texture:SetBlendMode(m) if m ~= "ADD" and m ~= "BLEND" then error("fusion invalide", 2) end end
function Texture:SetDesaturated(v) self._desat = v end
function Texture:SetRotation(radians) num(radians, "rotation"); self._rotation = radians end
-- groupe d'animation du moteur (rotation continue)
local Anim = {}
function Anim:SetDegrees(d) num(d, "degrés") end
function Anim:SetDuration(s) num(s, "durée"); if s <= 0 then error("durée nulle", 2) end end
function Anim:SetOrigin(point, x, y) if not POINTS[point] then error("origine invalide", 2) end; num(x, "x"); num(y, "y") end
local Group = {}
function Group:CreateAnimation(kind)
  if kind ~= "Rotation" then error("animation inconnue : " .. tostring(kind), 2) end
  return setmetatable({}, { __index = Anim })
end
function Group:SetLooping(mode) if mode ~= "REPEAT" and mode ~= "NONE" and mode ~= "BOUNCE" then error("boucle invalide", 2) end end
function Group:Play() self.playing = true end
function Group:Stop() self.playing = false end
function Group:IsPlaying() return self.playing == true end
function Texture:CreateAnimationGroup()
  local g = setmetatable({}, { __index = Group })
  M.spinners = M.spinners or {}
  M.spinners[#M.spinners + 1] = g
  return g
end
function Texture:AddMaskTexture(mask) if not mask or mask._type ~= "MaskTexture" then error("masque invalide", 2) end end
function Texture:SetTextureSliceMargins(l, t, r, b) num(l, "marge") end
function Texture:SetTextureSliceMode(mode) end

local Font = class(Region)
function Font:SetFont(path, size, flags)
  if type(path) ~= "string" then error("police invalide", 2) end
  num(size, "taille")
  if flags ~= nil and type(flags) ~= "string" then error("options de police invalides", 2) end
end
function Font:SetText(t)
  if t ~= nil and type(t) ~= "string" and type(t) ~= "number" then error("texte invalide : " .. tostring(t), 2) end
  self._text = t ~= nil and tostring(t) or ""
end
function Font:GetText() return self._text end
function Font:SetTextColor(r, g, b, a) num(r, "r"); num(g, "g"); num(b, "b") end
function Font:SetShadowOffset(x, y) num(x, "x"); num(y, "y") end
function Font:SetShadowColor(r, g, b, a) num(r, "r") end
function Font:SetJustifyH(j) if j ~= "LEFT" and j ~= "CENTER" and j ~= "RIGHT" then error("justification invalide", 2) end end
function Font:GetStringWidth() return #(self._text or "") * 6 end

local function region(kind, parent, methods)
  return setmetatable({ _type = kind, _parent = parent }, {
    __index = function(_, k)
      local v = methods[k]
      -- une méthode du jeu commence par une majuscule : l'appeler sans qu'elle existe est une faute
      if v == nil and type(k) == "string" and k:find("^[A-Z]") then
        error("méthode inconnue : " .. kind .. ":" .. k, 2)
      end
      if v ~= nil then M.ops = (M.ops or 0) + 1 end   -- chaque appel de méthode de widget est compté
      return v
    end,
  })
end

local Frame = class(Region)
function Frame:CreateTexture(name, layer, template, sub)
  if layer ~= nil and not LAYERS[layer] then error("couche invalide : " .. tostring(layer), 2) end
  if sub ~= nil then num(sub, "sous-couche"); if sub < -8 or sub > 7 then error("sous-couche hors limites", 2) end end
  return region("Texture", self, Texture)
end
function Frame:CreateMaskTexture() return region("MaskTexture", self, Texture) end
function Frame:CreateFontString(name, layer) return region("FontString", self, Font) end
function Frame:SetScript(h, fn)
  if fn ~= nil and type(fn) ~= "function" then error("script invalide pour " .. tostring(h), 2) end
  self._scripts[h] = fn
  if h == "OnUpdate" then M.updaters[self] = fn end
end
function Frame:GetScript(h) return self._scripts[h] end
function Frame:RegisterEvent(e)
  if not M.knownEvents[e] then error("événement inconnu : " .. tostring(e), 2) end
  M.events[e] = M.events[e] or {}
  M.events[e][self] = true
end
function Frame:RegisterUnitEvent(e, unit)
  if not M.knownEvents[e] then error("événement inconnu : " .. tostring(e), 2) end
  M.unitEvents[e] = M.unitEvents[e] or {}
  M.unitEvents[e][self] = unit
end
function Frame:SetFrameStrata(s) if not STRATA[s] then error("strate invalide", 2) end end
function Frame:SetFrameLevel(l) num(l, "niveau"); self._level = l end
function Frame:GetFrameLevel() return self._level or 1 end
function Frame:SetToplevel(v) end
function Frame:SetClampedToScreen(v) end
function Frame:EnableMouse(v) self._mouse = v end
function Frame:SetMovable(v) end
function Frame:RegisterForDrag(b) end
function Frame:StartMoving() end
function Frame:StopMovingOrSizing() end
function Frame:SetScale(s) num(s, "échelle"); if s <= 0 then error("échelle nulle", 2) end; self._scale = s end
function Frame:SetClipsChildren(v) end
function Frame:Raise() end

local Cooldown = class(Frame)
function Cooldown:SetCooldown(start, duration, modRate)
  num(start, "début"); num(duration, "durée")   -- code d'addon : les secrets sont refusés ici
  self._cd = { start, duration }
  M.widgetCalls.SetCooldown = (M.widgetCalls.SetCooldown or 0) + 1
end
function Cooldown:SetCooldownFromDurationObject(obj, clearIfZero)
  if type(obj) ~= "table" or not obj._durationObject then error("objet durée attendu", 2) end
  self._cd = obj
  M.widgetCalls.DurationObject = (M.widgetCalls.DurationObject or 0) + 1
end
function Cooldown:SetSwipeTexture(t, r, g, b, a) end
function Cooldown:SetSwipeColor(r, g, b, a) num(r, "r") end
function Cooldown:SetDrawEdge(v) end
function Cooldown:SetDrawBling(v) end
function Cooldown:SetHideCountdownNumbers(v) end
function Cooldown:SetReverse(v) end
function Cooldown:SetDrawSwipe(v) end
function Cooldown:GetCountdownFontString() return region("FontString", self, Font) end

local StatusBar = class(Frame)
function StatusBar:SetStatusBarTexture(t) self._bar = region("Texture", self, Texture) end
function StatusBar:GetStatusBarTexture() return self._bar end
function StatusBar:SetMinMaxValues(lo, hi) numOrSecret(lo, "min"); numOrSecret(hi, "max") end
function StatusBar:SetValue(v)
  numOrSecret(v, "valeur")
  self._value = v
  M.widgetCalls.SetValue = (M.widgetCalls.SetValue or 0) + 1
  if SECRET[v] ~= nil then M.widgetCalls.SecretValue = (M.widgetCalls.SecretValue or 0) + 1 end
end

local EditBox = class(Frame, Font)
function EditBox:SetMultiLine(v) end
function EditBox:SetAutoFocus(v) end
function EditBox:SetMaxLetters(n) end
function EditBox:SetFocus() end
function EditBox:HighlightText() end

local Button = class(Frame)

local KINDS = { Frame = Frame, Button = Button, Cooldown = Cooldown, StatusBar = StatusBar, EditBox = EditBox }
UIParent = nil
function CreateFrame(kind, name, parent, template)
  local methods = KINDS[kind]
  if not methods then error("type de cadre inconnu : " .. tostring(kind), 2) end
  if template ~= nil and template ~= "CooldownFrameTemplate" then error("modèle inconnu : " .. tostring(template), 2) end
  local f = region(kind, parent, methods)
  rawset(f, "_scripts", {})
  if name then
    _G[name] = f
    M.named = M.named or {}
    M.named[name] = f
  end
  return f
end
UIParent = CreateFrame("Frame", "UIParent")

M.knownEvents = {}
for _, e in ipairs({
  "ADDON_LOADED", "PLAYER_LOGIN", "PLAYER_ENTERING_WORLD", "PLAYER_REGEN_DISABLED", "PLAYER_REGEN_ENABLED",
  "PLAYER_DEAD", "UNIT_AURA", "PLAYER_TARGET_CHANGED", "UNIT_SPELLCAST_SUCCEEDED", "UNIT_SPELLCAST_CHANNEL_START",
  "SPELL_UPDATE_COOLDOWN", "SPELL_UPDATE_CHARGES", "SPELL_UPDATE_USABLE", "BAG_UPDATE_COOLDOWN", "BAG_UPDATE_DELAYED",
  "SPELL_ACTIVATION_OVERLAY_GLOW_SHOW", "SPELL_ACTIVATION_OVERLAY_GLOW_HIDE", "SPELLS_CHANGED",
  "TRAIT_CONFIG_UPDATED", "PLAYER_LEVEL_UP", "UNIT_POWER_FREQUENT", "UNIT_MAXPOWER",
  "UNIT_SPELLCAST_START", "UNIT_SPELLCAST_STOP", "UNIT_SPELLCAST_FAILED", "UNIT_SPELLCAST_INTERRUPTED",
  "UNIT_SPELLCAST_CHANNEL_STOP", "UNIT_SPELLCAST_DELAYED",
  -- PLAYER_TALENT_UPDATE n'existe pas dans ce client : l'enregistrer lève une erreur, comme en jeu
}) do M.knownEvents[e] = true end

-- ------------------------------------------------------------------ Gestionnaire de temps de recharge
-- Les icônes de « Buffs suivis » de Blizzard : elles répondent IsActive() en clair, même en combat.
C_CooldownViewer = {}
function C_CooldownViewer.GetCooldownViewerCooldownInfo(cooldownID)
  local spell = M.cdmSpells and M.cdmSpells[cooldownID]
  return spell and { spellID = spell, linkedSpellIDs = {} } or nil
end
function M.trackBuff(cooldownID, spellID, auraName)
  M.cdmSpells = M.cdmSpells or {}
  M.cdmSpells[cooldownID] = spellID
  local viewer = _G.BuffIconCooldownViewer
  if not viewer then
    viewer = { items = {} }
    function viewer:GetChildren() return unpack(self.items) end
    _G.BuffIconCooldownViewer = viewer
  end
  viewer.items[#viewer.items + 1] = {
    cooldownID = cooldownID,
    IsActive = function() return M.auras[auraName] ~= nil end,
    auraInstanceID = M.secret(7),
  }
end

-- ------------------------------------------------------------------ pilotage du test
function M.fire(event, ...)
  local list = M.events[event]
  if list then
    for f in pairs(list) do
      local fn = f._scripts.OnEvent
      if fn then fn(f, event, ...) end
    end
  end
  local units = M.unitEvents[event]
  if units then
    local unit = ...
    for f, want in pairs(units) do
      local fn = f._scripts.OnEvent
      if fn and unit == want then fn(f, event, ...) end
    end
  end
end

function M.advance(seconds, step)
  step = step or 0.05
  local n = math.floor(seconds / step + 0.5)
  for _ = 1, n do
    M.now = M.now + step
    for f, fn in pairs(M.updaters) do fn(f, step) end
  end
end

-- Le joueur lance un sort : le jeu applique ses effets, puis prévient l'addon.
function M.cast(id)
  local sp = M.spells[id]
  local name = sp.name
  if name == "Déflagration des Arcanes" then
    -- mesuré en jeu : la première Déflagration ouvre une fenêtre de 18 s, les suivantes ajoutent une
    -- charge sans la prolonger (l'aura annonce alors le temps restant), aucun autre sort ne consomme
    local a = M.auras[name]
    if a then
      a.applications = math.min(4, a.applications + 1)
      a.duration = a.expirationTime - M.now
    else
      M.auras[name] = { spellId = 400574, applications = 1, duration = 18, expirationTime = M.now + 18 }
    end
  end
  if name == "Projectiles des Arcanes" then M.auras["Barrage de projectiles"] = nil; M.overlays[id] = nil end
  if sp.cost and sp.cost > 0 then M.auras["Idées claires"] = nil end
  if name == "Pouvoir des Arcanes" then
    M.auras[name] = { spellId = 12042, applications = 0, duration = 15, expirationTime = M.now + 15 }
  end
  if name == "Eurêka !" then
    M.auras[name] = { spellId = 1259817, applications = 0, duration = 8, expirationTime = M.now + 8 }
  end
  if name == "Présence spirituelle" then M.auras[name] = { spellId = 12043, applications = 0, duration = 0, expirationTime = 0 } end
  if sp.cast and sp.cast > 0 then M.auras["Présence spirituelle"] = nil end
  if sp.cd then M.cooldowns[id] = { start = M.now, duration = sp.cd } end
  M.fire("UNIT_SPELLCAST_SUCCEEDED", "player", "Cast-3-0", id)
  M.fire("UNIT_AURA", "player", {})
  M.fire("SPELL_UPDATE_COOLDOWN")
end

-- Une canalisation, comme dans le vrai jeu : un UNIT_SPELLCAST_SUCCEEDED par salve.
function M.channel(id, ticks, interval)
  M.cast(id)
  for _ = 2, ticks do
    M.advance(interval)
    M.fire("UNIT_SPELLCAST_SUCCEEDED", "player", "Cast-3-0", id)
  end
end

function M.proc(name, id, duration)
  M.auras[name] = { spellId = id, applications = 0, duration = duration or 15, expirationTime = M.now + (duration or 15) }
  M.fire("UNIT_AURA", "player", {})
end

function M.expire()   -- le jeu retire les auras arrivées à terme, et le signale
  local gone = false
  for name, a in pairs(M.auras) do
    if a.expirationTime and a.expirationTime > 0 and a.expirationTime <= M.now then M.auras[name] = nil; gone = true end
  end
  if gone then M.fire("UNIT_AURA", "player", {}) end
end

-- Un temps de recharge démarre : le jeu le signale.
function M.setCooldown(id, duration)
  M.cooldowns[id] = { start = M.now, duration = duration }
  M.fire("SPELL_UPDATE_COOLDOWN")
end

function M.setCombat(on)
  M.combat = on
  M.fire(on and "PLAYER_REGEN_DISABLED" or "PLAYER_REGEN_ENABLED")
end

-- ------------------------------------------------------------------ compteur d'appels au jeu
-- Chaque fonction du jeu appelée par l'addon est comptée : le banc de test mesure ainsi ce que coûte
-- une seconde de combat, et vérifie que l'addon reste économe.
M.calls = {}
function M.resetCalls() M.calls = {} end
function M.totalCalls()
  local n = 0
  for _, v in pairs(M.calls) do n = n + v end
  return n
end
local function counted(space, tbl)
  for name, fn in pairs(tbl) do
    if type(fn) == "function" then
      local label = space .. name
      tbl[name] = function(...)
        M.calls[label] = (M.calls[label] or 0) + 1
        return fn(...)
      end
    end
  end
end
counted("C_Spell.", C_Spell)
counted("C_UnitAuras.", C_UnitAuras)
counted("C_Secrets.", C_Secrets)
counted("C_SpellBook.", C_SpellBook)
counted("C_Item.", C_Item)
counted("C_Container.", C_Container)
counted("C_SpellActivationOverlay.", C_SpellActivationOverlay)
for _, name in ipairs({ "UnitPower", "UnitPowerMax", "UnitExists", "UnitCanAttack", "UnitIsDead",
  "UnitCastingInfo", "UnitChannelInfo", "GetSpellBaseCooldown" }) do
  local fn = _G[name]
  _G[name] = function(...)
    M.calls[name] = (M.calls[name] or 0) + 1
    return fn(...)
  end
end

-- ------------------------------------------------------------------ variables globales
-- Un addon ne doit rien laisser traîner dans l'espace global, à part ce qu'il déclare (réglages
-- enregistrés, commandes, cadres nommés). Toute autre écriture globale est relevée.
M.leaks = {}
local ALLOWED = { ArcanumDB = true, SLASH_ARCANUM1 = true, SLASH_ARCANUM2 = true,
  ArcanumHUD = true, ArcanumOptions = true, ArcanumDiag = true, BuffIconCooldownViewer = true }
function M.watchGlobals()
  setmetatable(_G, { __newindex = function(t, k, v)
    if not ALLOWED[k] then M.leaks[#M.leaks + 1] = tostring(k) end
    rawset(t, k, v)
  end })
end

-- ------------------------------------------------------------------ chargement de l'addon
M.meta = {}
function M.load(dir, toc, addon)
  M.ns = {}
  M.watchGlobals()
  local files = {}
  for line in io.lines(dir .. "/" .. toc) do
    line = line:gsub("\r", "")
    local k, v = line:match("^## ([%w]+): (.+)$")
    if k then M.meta[k] = v elseif line ~= "" and not line:find("^#") then files[#files + 1] = line end
  end
  for _, line in ipairs(files) do
    local chunk, err = loadfile(dir .. "/" .. line:gsub("\\", "/"))
    if not chunk then error("syntaxe : " .. err) end
    chunk(addon, M.ns)
  end
  return M.ns
end
