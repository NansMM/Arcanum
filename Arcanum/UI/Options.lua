-- Arcanum — fenêtre de réglages et commandes /arc.
local ADDON, ns = ...
local UI, State = ns.UI, ns.State
local C = UI.C
local L = ns.L

local Options = {}
ns.Options = Options

local W = 348
local frame
local refreshers = {}

local function hover(f, onEnter, onLeave)
  f:EnableMouse(true)
  f:SetScript("OnEnter", onEnter)
  f:SetScript("OnLeave", onLeave)
end

-- ------------------------------------------------------------------ briques
local function sectionTitle(parent, text, y)
  local fs = UI.Text(parent, 10, C.faint, UI.FONT.title)
  fs:SetPoint("TOPLEFT", 22, y)
  fs:SetText(string.upper(text))
  local line = UI.Tex(parent, "ARTWORK", "grad-h", C.edge, 0.35)
  line:SetTexCoord(1, 0, 0, 1)
  line:SetHeight(1)
  line:SetPoint("LEFT", fs, "RIGHT", 10, 0)
  line:SetPoint("RIGHT", parent, "RIGHT", -22, 0)
  return y - 22
end

-- Interrupteur : une ligne cliquable, libellé à gauche, pastille à droite.
local function toggle(parent, label, key, y)
  local row = CreateFrame("Button", nil, parent)
  row:SetSize(W - 32, 28)
  row:SetPoint("TOPLEFT", 16, y)
  local bg = UI.Tex(row, "BACKGROUND", nil, { 1, 1, 1 }, 0)
  bg:SetAllPoints()
  local text = UI.Text(row, 13, C.text)
  text:SetPoint("LEFT", 8, 0)
  text:SetText(label)
  local sw = CreateFrame("Frame", nil, row)
  sw:SetSize(34, 18)
  sw:SetPoint("RIGHT", -8, 0)
  local track = UI.Pill(sw, C.socket, 1)
  local knob = UI.Tex(sw, "ARTWORK", "circle", C.text, 1)
  knob:SetSize(14, 14)
  local function refresh()
    local on = ns.db[key] and true or false
    for _, t in ipairs(track) do UI.Color(t, on and C.arcane or C.socket, 1) end
    knob:ClearAllPoints()
    knob:SetPoint(on and "RIGHT" or "LEFT", on and -2 or 2, 0)
    UI.Color(knob, on and { 1, 1, 1 } or C.muted, 1)
  end
  row:SetScript("OnClick", function()
    ns.Set(key, not ns.db[key])
    refresh()
  end)
  hover(row, function() bg:SetVertexColor(1, 1, 1, 0.05) end, function() bg:SetVertexColor(1, 1, 1, 0) end)
  refreshers[#refreshers + 1] = refresh
  return y - 30
end

local function pillButton(parent, text, width, onClick, accent)
  local b = CreateFrame("Button", nil, parent)
  b:SetSize(width, 28)
  local parts = UI.Pill(b, accent and C.arcane or C.panelHi, 1)
  local fs = UI.Text(b, 12, accent and C.ink or C.text, UI.FONT.title)
  fs:SetPoint("CENTER", 0, 0)
  fs:SetText(text)
  if accent then fs:SetShadowColor(0, 0, 0, 0) end
  b.label = fs
  b.SetAccent = function(_, on)
    for _, t in ipairs(parts) do UI.Color(t, on and C.arcane or C.panelHi, 1) end
    local c = on and C.ink or C.text
    fs:SetTextColor(c[1], c[2], c[3], 1)
    fs:SetShadowColor(0, 0, 0, on and 0 or 0.85)
  end
  hover(b, function() b:SetAlpha(0.85) end, function() b:SetAlpha(1) end)
  b:SetScript("OnClick", onClick)
  return b
end

-- Réglage par paliers : libellé, « − valeur + ».
local function stepper(parent, label, key, lo, hi, step, fmt, y)
  local text = UI.Text(parent, 13, C.text)
  text:SetPoint("TOPLEFT", 24, y - 7)
  text:SetText(label)
  local value = UI.Text(parent, 13, C.arcaneHi)
  local function refresh() value:SetText(fmt(ns.db[key])) end
  local function bump(delta)
    local v = math.floor((ns.db[key] + delta) / step + 0.5) * step
    if v < lo then v = lo elseif v > hi then v = hi end
    ns.Set(key, v)
    refresh()
  end
  local plus = pillButton(parent, "+", 28, function() bump(step) end)
  plus:SetPoint("TOPRIGHT", -22, y)
  value:SetPoint("RIGHT", plus, "LEFT", -10, 0)
  value:SetWidth(48)
  value:SetJustifyH("CENTER")
  local minus = pillButton(parent, "-", 28, function() bump(-step) end)
  minus:SetPoint("RIGHT", value, "LEFT", -10, 0)
  refreshers[#refreshers + 1] = refresh
  return y - 34
end

-- Choix entre deux valeurs.
local function choice(parent, label, key, values, y)
  local text = UI.Text(parent, 13, C.text)
  text:SetPoint("TOPLEFT", 24, y - 7)
  text:SetText(label)
  local buttons = {}
  local function refresh()
    for _, b in ipairs(buttons) do b:SetAccent(ns.db[key] == b.value) end
  end
  local anchor
  for i = #values, 1, -1 do
    local v = values[i]
    local b = pillButton(parent, tostring(v), type(v) == "string" and 46 or 36, function() ns.Set(key, v); refresh() end)
    b.value = v
    if anchor then b:SetPoint("RIGHT", anchor, "LEFT", -6, 0) else b:SetPoint("TOPRIGHT", -22, y) end
    anchor = b
    buttons[#buttons + 1] = b
  end
  refreshers[#refreshers + 1] = refresh
  return y - 34
end

-- ------------------------------------------------------------------ fenêtre
function Options.Build()
  if frame then return frame end
  local f = CreateFrame("Frame", "ArcanumOptions", UIParent)
  f:SetFrameStrata("DIALOG")
  f:SetToplevel(true)
  f:SetClampedToScreen(true)
  f:SetPoint("CENTER", 0, 40)
  f:EnableMouse(true)
  f:SetMovable(true)
  f:RegisterForDrag("LeftButton")
  f:SetScript("OnDragStart", f.StartMoving)
  f:SetScript("OnDragStop", f.StopMovingOrSizing)
  f:Hide()
  tinsert(UISpecialFrames, "ArcanumOptions")

  local glow = UI.Tex(f, "BACKGROUND", "glow", C.arcane, 0.16, "ADD", -8)
  glow:SetPoint("TOPLEFT", -90, 90)
  glow:SetPoint("BOTTOMRIGHT", 90, -90)
  UI.Panel(f, C.edge, 0.55, "BACKGROUND", -2, -1)
  UI.Panel(f, C.ink, 0.97, "BACKGROUND", -1, 0)

  local logo = UI.Tex(f, "ARTWORK", "logo")
  logo:SetSize(30, 30)
  logo:SetPoint("TOPLEFT", 20, -18)
  local title = UI.Text(f, 18, C.text, UI.FONT.title)
  title:SetPoint("TOPLEFT", logo, "TOPRIGHT", 10, -1)
  title:SetText("Arcanum")
  local sub = UI.Text(f, 11, C.muted)
  sub:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -3)
  sub:SetText(L["HUD du mage Arcanes"] .. "  ·  v" .. ns.VERSION)

  local close = CreateFrame("Button", nil, f)
  close:SetSize(26, 26)
  close:SetPoint("TOPRIGHT", -14, -14)
  local cross = UI.Text(close, 18, C.muted, UI.FONT.body)
  cross:SetPoint("CENTER", 0, 0)
  cross:SetText("×")
  hover(close, function() cross:SetTextColor(1, 1, 1, 1) end,
    function() cross:SetTextColor(C.muted[1], C.muted[2], C.muted[3], 1) end)
  close:SetScript("OnClick", function() f:Hide() end)

  local y = -70
  y = sectionTitle(f, L["Affichage"], y)
  y = toggle(f, L["Activer le HUD"], "enabled", y)
  y = toggle(f, L["Visible aussi hors combat"], "showIdle", y)
  y = toggle(f, L["Prochain sort conseillé"], "showNext", y)
  y = toggle(f, L["Cristaux de charge"], "showCharges", y)
  y = toggle(f, L["Orbes de proc"], "showProcs", y)
  y = toggle(f, L["Gros temps de recharge"], "showCooldowns", y)
  y = toggle(f, L["Barre de mana"], "showMana", y)
  y = toggle(f, L["Rappels avant le combat"], "showReminders", y)
  y = stepper(f, L["Taille"], "scale", 0.6, 1.8, 0.05, function(v) return string.format("%d %%", v * 100 + 0.5) end, y - 4)

  y = sectionTitle(f, L["Alertes"], y - 8)
  y = toggle(f, L["Son à l'arrivée d'un proc"], "sound", y)
  y = toggle(f, L["Onde lumineuse"], "flash", y)

  y = sectionTitle(f, L["Cycle"], y - 8)
  y = choice(f, L["Charges visées"], "targetStacks", { 2, 3, 4 }, y)
  y = choice(f, L["Rang du remplissage (Éclair de givre)"], "fillerRank", { 1, "max" }, y)
  y = toggle(f, L["Burst en une icône (macro ArcBurst)"], "burstOne", y)
  y = toggle(f, L["Engager à la Colère"], "openWrath", y)
  y = toggle(f, L["Interrompre pour des Idées claires"], "cutForClear", y)
  y = toggle(f, L["Conseiller les gros temps de recharge"], "adviseBurst", y)
  y = toggle(f, L["Anticiper pendant l'incantation"], "anticipate", y)

  local bw = (W - 44 - 16) / 3
  local move = pillButton(f, "", bw, function()
    ns.Set("locked", not ns.db.locked)
    Options.Refresh()
  end)
  move:SetPoint("TOPLEFT", 22, y - 10)
  local demo = pillButton(f, "", bw, function()
    State.SetDemo(not State.demo)
    Options.Refresh()
  end)
  demo:SetPoint("LEFT", move, "RIGHT", 8, 0)
  local diag = pillButton(f, L["Diagnostic"], bw, function() ns.Diag.Show() end)
  diag:SetPoint("LEFT", demo, "RIGHT", 8, 0)
  refreshers[#refreshers + 1] = function()
    move.label:SetText(ns.db.locked and L["Déplacer"] or L["Verrouiller"])
    move:SetAccent(not ns.db.locked)
    demo.label:SetText(State.demo and L["Arrêter la démo"] or L["Démonstration"])
    demo:SetAccent(State.demo)
  end
  y = y - 10 - 28

  f:SetSize(W, -y + 22)
  frame = f
  return f
end

function Options.Refresh()
  if not frame then return end
  for _, fn in ipairs(refreshers) do fn() end
end

function Options.Toggle()
  local f = Options.Build()
  if f:IsShown() then
    f:Hide()
  else
    Options.Refresh()
    f:Show()
    f:Raise()
  end
end

-- ------------------------------------------------------------------ macro de burst
-- Crée (ou met à jour) la macro Eureka + Présence spirituelle + Courroux avec les noms exacts que le jeu
-- donne aux sorts. Les taper à la main échoue facilement : en français, « Eurêka ! » contient une
-- espace insécable avant le point d'exclamation.
local MACRO_NAME = "ArcBurst"

local function makeMacro()
  local Spells = ns.Spells
  if InCombatLockdown and InCombatLockdown() then
    ns.Print(L["les macros ne se modifient pas en combat. Réessaie hors combat."])
    return false
  end
  if not (CreateMacro and EditMacro and GetMacroIndexByName) then
    ns.Print(L["ce client ne permet pas aux addons de créer une macro."])
    return false
  end
  local wrath = Spells.Known("wrath") and Spells.Name("wrath")
  if not wrath then
    ns.Print(L["ton personnage ne connaît pas encore le Courroux des Arcanes."])
    return false
  end
  -- Après un sort instantané, le jeu refuse le sort suivant du même appui (« une autre action est en
  -- cours »). /stopcasting entre deux sorts lève ce blocage : c'est la forme classique de la macro
  -- Présence spirituelle + sort.
  local lines, used = { "#showtooltip " .. wrath }, {}
  for _, key in ipairs({ "eureka", "pom" }) do
    local name = Spells.Known(key) and Spells.Name(key)
    if name then
      lines[#lines + 1] = "/cast " .. name
      lines[#lines + 1] = "/stopcasting"
      used[#used + 1] = name
    end
  end
  lines[#lines + 1] = "/cast " .. wrath
  used[#used + 1] = wrath
  local body = table.concat(lines, "\n")
  local okIndex, index = pcall(GetMacroIndexByName, MACRO_NAME)
  local ok
  if okIndex and type(index) == "number" and index > 0 then
    ok = pcall(EditMacro, index, MACRO_NAME, nil, body)
  else
    local id
    ok, id = pcall(CreateMacro, MACRO_NAME, 134400, body, true)
    ok = ok and id ~= nil
  end
  if not ok then
    ns.Print(L["impossible de créer la macro (plus de place dans tes macros de personnage ?)."])
    return false
  end
  ns.Print(string.format(L["macro « %s » prête : %s. Ouvre /macro, onglet de ton personnage, et glisse-la sur ta barre."],
    MACRO_NAME, table.concat(used, " + ")))
  return true
end
Options.MakeMacro = makeMacro

-- ------------------------------------------------------------------ commandes
local HELP = {
  "/arc : ouvrir les réglages",
  "/arc demo : voir le HUD conseiller un cycle complet",
  "/arc conseil : afficher ou masquer le prochain sort (sans lui : charges, procs et recharges seulement)",
  "/arc verrou : déplacer ou fixer le HUD",
  "/arc taille 120 : taille du HUD en pourcentage",
  "/arc aoe : mode multi-cibles (Choc de flammes, Explosion des Arcanes) ; il s'active aussi tout seul",
  "/arc macro : créer la macro de burst (Eureka + Présence spirituelle + Courroux) avec les noms exacts",
  "/arc diag : rapport à copier (sorts reconnus, signaux lus en combat)",
  "/arc reset : remettre les réglages d'origine",
}

SLASH_ARCANUM1 = "/arc"
SLASH_ARCANUM2 = "/arcanum"
SlashCmdList.ARCANUM = function(msg)
  if not ns.db then ns.InitDB() end
  msg = (msg or ""):lower():gsub("^%s+", ""):gsub("%s+$", "")
  local cmd, arg = msg:match("^(%S*)%s*(.-)$")
  if not ns.started then
    if not ns.isMage and cmd ~= "demo" then
      ns.Print(L["est fait pour les mages. Tape /arc demo pour voir le HUD quand même."])
      return
    end
    ns.Start()
  end
  if cmd == "" or cmd == "options" or cmd == "config" then
    Options.Toggle()
  elseif cmd == "demo" then
    State.SetDemo(not State.demo)
    ns.Print(State.demo and L["démonstration lancée (/arc demo pour l'arrêter)."] or L["démonstration arrêtée."])
    Options.Refresh()
  elseif cmd == "verrou" or cmd == "deplacer" or cmd == "lock" or cmd == "unlock" then
    ns.Set("locked", not ns.db.locked)
    ns.Print(ns.db.locked and L["HUD verrouillé."] or L["HUD déverrouillé : fais-le glisser, puis /arc verrou."])
    Options.Refresh()
  elseif cmd == "taille" or cmd == "scale" then
    local v = tonumber(arg)
    if v and v >= 60 and v <= 180 then
      ns.Set("scale", v / 100)
      Options.Refresh()
    else
      ns.Print(L["taille entre 60 et 180, par exemple /arc taille 120."])
    end
  elseif cmd == "conseil" or cmd == "suivi" then
    ns.Set("showNext", ns.db.showNext == false)
    ns.Print(ns.db.showNext and L["prochain sort conseillé au centre du cercle."]
      or L["mode suivi seul : charges, procs et temps de recharge, sans conseil."])
    Options.Refresh()
  elseif cmd == "aoe" or cmd == "zone" then
    State.SetAoe(not State.aoe)
    ns.Print(State.aoe and L["mode multi-cibles activé jusqu'à la fin du combat (/arc aoe pour l'arrêter)."]
      or L["mode multi-cibles arrêté."])
  elseif cmd == "macro" then
    makeMacro()
  elseif cmd == "diag" or cmd == "rapport" then
    ns.Diag.Show()
  elseif cmd == "reset" then
    ns.ResetDB()
    Options.Refresh()
    ns.Print(L["réglages d'origine rétablis."])
  else
    for _, line in ipairs(HELP) do ns.Print(line) end
  end
end
