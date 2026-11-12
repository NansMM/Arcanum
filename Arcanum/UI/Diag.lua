-- Arcanum — diagnostic : un rapport à copier-coller qui dit ce que le jeu laisse lire.
--
-- Les règles de WoW Forever changent d'une version à l'autre. Ce rapport montre, pour chaque sort et
-- chaque proc, d'où Arcanum tire son information (aura, coût, surbrillance, sorts lancés), et garde le
-- fil des derniers changements d'état : de quoi corriger vite si un proc n'apparaît pas.
local ADDON, ns = ...
local UI, State, Spells, S = ns.UI, ns.State, ns.Spells, ns.Secret
local C = UI.C
local L = ns.L

local Diag = {}
ns.Diag = Diag

local LOG_MAX = 60
local log = {}
local frame

local function record(text)
  log[#log + 1] = string.format("%7.1f  %s%s", GetTime() % 10000, State.restricted and "[combat] " or "", text)
  if #log > LOG_MAX then table.remove(log, 1) end
end

ns:On("STACKS", function(n, old)
  if not State.demo then record(string.format("charges %d -> %d (%s)", old or 0, n, tostring(State.stacksSource))) end
end)
ns:On("PROC", function(key)
  if State.demo then return end
  local p = State[key]
  record("proc " .. key .. " (" .. tostring(type(p) == "table" and p.source or "?") .. ")")
end)
ns:On("PROC_END", function(key) if not State.demo then record("fin " .. key) end end)
ns:On("CAST", function(key) record("sort " .. key) end)
ns:On("NEXT", function(key, reason)
  if not State.demo then record("conseil " .. tostring(key) .. " (" .. tostring(reason) .. ")") end
end)

local function show(v)
  if S.Is(v) then return "<secret>" end
  if v == nil then return "nil" end
  if type(v) == "number" then return (v % 1 == 0) and tostring(v) or string.format("%.2f", v) end
  return tostring(v)
end

local function secrecy(id)
  local CS = C_Secrets
  if not CS then return "-" end
  local base, now = "?", "?"
  if CS.GetSpellAuraSecrecy then
    local ok, lvl = pcall(CS.GetSpellAuraSecrecy, id)
    if ok and not S.Is(lvl) and lvl ~= nil then
      base = ({ [0] = "jamais", [1] = "toujours", [2] = "selon contexte" })[lvl] or tostring(lvl)
    end
  end
  if CS.ShouldSpellAuraBeSecret then
    local ok, r = pcall(CS.ShouldSpellAuraBeSecret, id)
    if ok and not S.Is(r) and r ~= nil then now = r and "secrète" or "lisible" end
  end
  return base .. ", maintenant " .. now
end

function Diag.Report()
  local out = {}
  local function add(fmt, ...) out[#out + 1] = select("#", ...) > 0 and string.format(fmt, ...) or fmt end
  local version, build, _, interface = "?", "?", nil, "?"
  if GetBuildInfo then version, build, _, interface = GetBuildInfo() end
  local _, class = UnitClass("player")
  add("Arcanum %s — diagnostic", ns.VERSION)
  add("Client %s (%s), interface %s, langue %s", show(version), show(build), show(interface), show(GetLocale and GetLocale()))
  add("Classe %s, niveau %s", show(class), show(UnitLevel and UnitLevel("player")))
  add("Valeurs secrètes : %s · auras cachées maintenant : %s · combat : %s",
    S.RESTRICTED and "oui" or "non", State.restricted and "oui" or "non", State.combat and "oui" or "non")
  add("Erreurs Lua : %d%s", ns.errorCount or 0, ns.lastError and (" · dernière : " .. ns.lastError) or "")

  add("")
  add("SORTS (clé, nom, rang le plus haut, connu, coût annoncé)")
  local keys = {}
  for key in pairs(Spells.DEF) do keys[#keys + 1] = key end
  table.sort(keys)
  for _, key in ipairs(keys) do
    local def = Spells.DEF[key]
    local cost, why = Spells.Cost(key)
    add("  %-11s %-28s id %-8s %-5s coût %s", key, show(def.name), show(def.best or def.id),
      def.known and "connu" or "-", cost and show(cost) or ("(" .. tostring(why) .. ")"))
  end

  add("")
  add("NOMS POUR LES MACROS (les espaces spéciales sont écrites en clair)")
  for _, key in ipairs({ "eureka", "pom", "wrath" }) do
    local name = Spells.Name(key)
    if name then
      local visible = name:gsub("\194\160", "[espace insécable]"):gsub("\226\128\175", "[espace fine insécable]")
      add("  %-8s %s", key, visible)
    end
  end

  add("")
  add("AURAS (lecture maintenant · secret par identifiant)")
  for _, key in ipairs({ "blast", "barrage", "clear", "power", "pom", "heat" }) do
    local def = Spells.DEF[key]
    local st, a = State.ReadAura(key)
    local detail = ""
    if st == "up" then
      detail = string.format(" charges %s, durée %s, fin %s", show(a.applications), show(a.duration), show(a.expirationTime))
    end
    add("  %-8s %s%s", key, st, detail)
    for _, id in ipairs(def.auras or { def.id }) do add("             %d : %s", id, secrecy(id)) end
  end

  add("")
  add("ÉTAT")
  add("  prochain sort : %s (%s)%s", tostring(State.next), tostring(State.nextReason),
    State.cast and (" · en cours : " .. tostring(State.cast.key)) or "")
  add("  charges %d (source %s), fin dans %s s", State.stacks, tostring(State.stacksSource),
    State.stacksExpire and show(State.stacksExpire - GetTime()) or "?")
  for _, key in ipairs({ "barrage", "clear", "power", "pom", "eureka" }) do
    local p = State[key]
    add("  %-8s %s%s", key, p.active and "actif" or "-", p.active and (" (source " .. tostring(p.source) .. ")") or "")
  end
  add("  heat     charges %s, prêt %s", show(State.heat.stacks), tostring(State.heat.ready))
  local glow = {}
  for id in pairs(State.overlay) do glow[#glow + 1] = tostring(id) end
  add("  surbrillances actives : %s", #glow > 0 and table.concat(glow, ", ") or "aucune")
  local icons = {}
  for _, key in ipairs({ "barrage", "clear", "heat", "power", "pom" }) do
    if State.cdm[key] ~= nil then icons[#icons + 1] = key .. "=" .. (State.cdm[key] and "actif" or "éteint") end
  end
  add("  Gestionnaire de temps de recharge (buffs suivis) : %s",
    #icons > 0 and table.concat(icons, ", ") or "aucune icône de proc trouvée")

  add("")
  add("APPRIS EN JEU")
  local l = ns.db and ns.db.learn or {}
  local parts = {}
  for k, v in pairs(l.dur or {}) do parts[#parts + 1] = k .. "=" .. show(v) end
  add("  durées : %s", #parts > 0 and table.concat(parts, ", ") or "aucune (valeurs par défaut)")
  parts = {}
  for k, v in pairs(l.cd or {}) do parts[#parts + 1] = k .. "=" .. show(v) end
  add("  recharges : %s", #parts > 0 and table.concat(parts, ", ") or "aucune")
  add("  Déflagration : fenêtre des charges %s s, coût de base %s, surcoût par charge %s, le coût suit les charges : %s",
    show(l.abWindow or State.Duration("blast")), show(l.abBase), show(l.abStep), tostring(l.costTracks))
  add("  Barrage vu par surbrillance : %s · par coût : %s · Idées claires vues par coût : %s",
    tostring(l.mbGlow or false), tostring(l.mbCost or false), tostring(l.ccCost or false))

  add("")
  add("JOURNAL (%d derniers changements)", #log)
  for _, line in ipairs(log) do add("  " .. line) end
  return table.concat(out, "\n")
end

local function build()
  local f = CreateFrame("Frame", "ArcanumDiag", UIParent)
  f:SetSize(620, 520)
  f:SetPoint("CENTER")
  f:SetFrameStrata("DIALOG")
  f:SetToplevel(true)
  f:SetClampedToScreen(true)
  f:EnableMouse(true)
  f:SetMovable(true)
  f:RegisterForDrag("LeftButton")
  f:SetScript("OnDragStart", f.StartMoving)
  f:SetScript("OnDragStop", f.StopMovingOrSizing)
  f:Hide()
  tinsert(UISpecialFrames, "ArcanumDiag")
  UI.Panel(f, C.edge, 0.55, "BACKGROUND", -2, -1)
  UI.Panel(f, C.ink, 0.97, "BACKGROUND", -1, 0)

  local title = UI.Text(f, 16, C.text, UI.FONT.title)
  title:SetPoint("TOPLEFT", 20, -18)
  title:SetText(L["Diagnostic d'Arcanum"])
  local hint = UI.Text(f, 11, C.muted)
  hint:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -4)
  hint:SetText(L["Le texte est sélectionné : Ctrl+C pour le copier. Échap pour fermer."])

  local box = CreateFrame("Frame", nil, f)
  box:SetPoint("TOPLEFT", 16, -62)
  box:SetPoint("BOTTOMRIGHT", -16, 16)
  if box.SetClipsChildren then box:SetClipsChildren(true) end
  UI.Panel(box, C.panel, 1, "BACKGROUND", 0)
  local eb = CreateFrame("EditBox", nil, box)
  eb:SetMultiLine(true)
  eb:SetAutoFocus(false)
  eb:SetFont(UI.FONT.body, 12, "")
  eb:SetTextColor(C.text[1], C.text[2], C.text[3], 1)
  eb:SetPoint("TOPLEFT", 12, -10)
  eb:SetPoint("BOTTOMRIGHT", -12, 10)
  eb:SetMaxLetters(0)
  -- lecture seule : toute frappe remet le rapport
  eb:SetScript("OnTextChanged", function(self, user)
    if user and f.text then self:SetText(f.text); self:HighlightText() end
  end)
  eb:SetScript("OnEscapePressed", function() f:Hide() end)
  box:EnableMouse(true)
  box:SetScript("OnMouseDown", function() eb:SetFocus(); eb:HighlightText() end)
  f.eb = eb
  frame = f
  return f
end

function Diag.Show()
  local f = frame or build()
  local ok, text = pcall(Diag.Report)
  f.text = ok and text or ("Rapport impossible : " .. tostring(text))
  f.eb:SetText(f.text)
  f:Show()
  f:Raise()
  f.eb:SetFocus()
  f.eb:HighlightText()
end
