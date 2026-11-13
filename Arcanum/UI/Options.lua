-- Arcanum — settings window and /arc commands.
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

-- ------------------------------------------------------------------ building blocks
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

-- Toggle: a clickable row, label on the left, pill switch on the right.
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

local function pillButton(parent, text, width, onClick)
  local b = CreateFrame("Button", nil, parent)
  b:SetSize(width, 28)
  local parts = UI.Pill(b, C.panelHi, 1)
  local fs = UI.Text(b, 12, C.text, UI.FONT.title)
  fs:SetPoint("CENTER", 0, 0)
  fs:SetText(text)
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

-- Stepped setting: label, "- value +".
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

-- Sound picker: "< name >". The arrows move to the next sound and play it; clicking the name replays it.
local function soundRow(parent, label, key, y)
  local text = UI.Text(parent, 13, C.text)
  text:SetPoint("TOPLEFT", 24, y - 7)
  text:SetText(label)
  local name
  local function refresh() name.label:SetText(ns.Hud.SoundName(key)) end
  local after = pillButton(parent, ">", 28, function() ns.Hud.CycleSound(key, 1); refresh() end)
  after:SetPoint("TOPRIGHT", -22, y)
  name = pillButton(parent, "", 150, function() ns.Hud.PreviewSound(key) end)
  name.label:SetFont(UI.FONT.body, 12, "")
  name:SetPoint("RIGHT", after, "LEFT", -4, 0)
  local before = pillButton(parent, "<", 28, function() ns.Hud.CycleSound(key, -1); refresh() end)
  before:SetPoint("RIGHT", name, "LEFT", -4, 0)
  refreshers[#refreshers + 1] = refresh
  return y - 34
end

-- ------------------------------------------------------------------ settings rows
-- Builds every setting in `parent` (a frame W wide), from `y` down, and returns the y under the last row.
-- Called twice: for Arcanum's own window (/arc) and for the panel in the game's Options > AddOns list. Both
-- copies register in `refreshers`, so a change made in one shows in the other.
local function fill(parent, y)
  y = sectionTitle(parent, L["Display"], y)
  y = toggle(parent, L["Enable the HUD"], "enabled", y)
  y = toggle(parent, L["Arcane Blast charges (top)"], "showCharges", y)
  y = toggle(parent, L["Procs and active buffs"], "showProcs", y)
  y = toggle(parent, L["Pre-combat reminders (bottom)"], "showReminders", y)
  y = toggle(parent, L["Proc decoration (rune arcs)"], "decor", y)
  y = stepper(parent, L["Size"], "scale", 0.6, 1.8, 0.05, function(v) return string.format("%d %%", v * 100 + 0.5) end, y)
  y = stepper(parent, L["Spread"], "spread", 80, 320, 10, function(v) return string.format("%d", v) end, y)

  y = sectionTitle(parent, L["Alerts"], y - 8)
  y = toggle(parent, L["Sound when a proc fires"], "sound", y)
  y = soundRow(parent, L["Clearcasting"], "clear", y - 2)
  y = soundRow(parent, L["Barrage"], "barrage", y)
  y = toggle(parent, L["Light wave"], "flash", y)

  local bw = (W - 44 - 16) / 3
  local move = pillButton(parent, "", bw, function()
    ns.Set("locked", not ns.db.locked)
    Options.Refresh()
  end)
  move:SetPoint("TOPLEFT", 22, y - 10)
  local demo = pillButton(parent, "", bw, function()
    State.SetDemo(not State.demo)
    Options.Refresh()
  end)
  demo:SetPoint("LEFT", move, "RIGHT", 8, 0)
  local diag = pillButton(parent, L["Diagnostics"], bw, function() ns.Diag.Show() end)
  diag:SetPoint("LEFT", demo, "RIGHT", 8, 0)
  refreshers[#refreshers + 1] = function()
    move.label:SetText(ns.db.locked and L["Move"] or L["Lock"])
    move:SetAccent(not ns.db.locked)
    demo.label:SetText(State.demo and L["Stop demo"] or L["Demo"])
    demo:SetAccent(State.demo)
  end
  return y - 10 - 28
end

-- ------------------------------------------------------------------ window
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
  sub:SetText(L["Arcane Mage HUD"] .. "  ·  v" .. ns.VERSION)

  local close = CreateFrame("Button", nil, f)
  close:SetSize(26, 26)
  close:SetPoint("TOPRIGHT", -14, -14)
  local cross = UI.Text(close, 18, C.muted, UI.FONT.body)
  cross:SetPoint("CENTER", 0, 0)
  cross:SetText("×")
  hover(close, function() cross:SetTextColor(1, 1, 1, 1) end,
    function() cross:SetTextColor(C.muted[1], C.muted[2], C.muted[3], 1) end)
  close:SetScript("OnClick", function() f:Hide() end)

  local y = fill(f, -70)
  f:SetSize(W, -y + 22)
  frame = f
  return f
end

function Options.Refresh()
  if not ns.db then return end
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

-- ------------------------------------------------------------------ the game's Options > AddOns list
-- The same settings, as a panel in the game's own options, for players who look for an addon's settings
-- there. /arc keeps opening Arcanum's window, which also works when the game's options cannot be opened.
-- A client without this part of the interface simply gets no panel.
local function registerInGame()
  if Options.category or not (Settings and Settings.RegisterCanvasLayoutCategory and Settings.RegisterAddOnCategory) then
    return
  end
  local panel = CreateFrame("Frame", "ArcanumOptionsPanel")
  panel:Hide()
  local title = UI.Text(panel, 18, C.text, UI.FONT.title)
  title:SetPoint("TOPLEFT", 22, -16)
  title:SetText("Arcanum")
  local sub = UI.Text(panel, 11, C.muted)
  sub:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -3)
  sub:SetText(L["Arcane Mage HUD"] .. "  ·  v" .. ns.VERSION)
  local hint = UI.Text(panel, 11, C.faint)
  hint:SetPoint("TOPLEFT", sub, "BOTTOMLEFT", 0, -3)
  hint:SetText(L["/arc opens these settings anywhere, even in combat."])
  local box = CreateFrame("Frame", nil, panel)   -- the rows anchor to a box as wide as Arcanum's own window
  box:SetSize(W, 10)
  box:SetPoint("TOPLEFT", 0, 0)
  fill(box, -78)
  panel:SetScript("OnShow", function() Options.Refresh() end)
  local ok, category = pcall(Settings.RegisterCanvasLayoutCategory, panel, "Arcanum")
  if not ok or not category then return end
  pcall(Settings.RegisterAddOnCategory, category)
  Options.category, Options.panel = category, panel
end
ns:On("START", function()
  local ok, err = pcall(registerInGame)
  if not ok then ns.Report(err) end
end)

-- ------------------------------------------------------------------ burst macro
-- Creates (or updates) the Eureka + Presence of Mind + Arcane Wrath macro with the exact names the game
-- gives the spells. Typing them by hand fails easily: in French, "Eurêka !" contains a non-breaking space
-- before the exclamation mark.
local MACRO_NAME = "ArcBurst"

local function makeMacro()
  local Spells = ns.Spells
  if InCombatLockdown and InCombatLockdown() then
    ns.Print(L["macros cannot be edited in combat. Try again out of combat."])
    return false
  end
  if not (CreateMacro and EditMacro and GetMacroIndexByName) then
    ns.Print(L["this client does not let addons create macros."])
    return false
  end
  local wrath = Spells.Known("wrath") and Spells.Name("wrath")
  if not wrath then
    ns.Print(L["your character does not know Arcane Wrath yet."])
    return false
  end
  -- After an instant spell, the game refuses the next spell of the same key press ("another action is in
  -- progress"). /stopcasting between two spells lifts that block: the classic Presence of Mind + spell macro.
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
    ns.Print(L["could not create the macro (no room left in your character macros?)."])
    return false
  end
  ns.Print(string.format(L["macro \"%s\" ready: %s. Open /macro, your character's tab, and drag it to your bar."],
    MACRO_NAME, table.concat(used, " + ")))
  return true
end
Options.MakeMacro = makeMacro

-- ------------------------------------------------------------------ sounds
-- /arc sounds                : play both sounds
-- /arc sound 3071            : play a game sound, by its id
-- /arc sound barrage 3071    : play that game sound when Missile Barrage fires (or "clear": Clearcasting)
-- /arc sound barrage voice   : have the game voice say the proc's name
-- /arc sound barrage         : back to the default sound
local SOUND_KEYS = { clear = "clear", clearcasting = "clear", claires = "clear", barrage = "barrage" }
local SOUND_LABEL = { clear = "Clearcasting", barrage = "Missile Barrage" }

local function soundCommand(arg)
  local a, b = arg:match("^(%S*)%s*(%S*)")
  if a == "" then
    ns.Hud.TestSounds()
    return
  end
  local id = tonumber(a)
  if id then
    ns.Print(string.format(ns.Hud.PlayKit(id) and L["game sound %d."] or L["the game plays nothing for sound %d."], id))
    return
  end
  local key = SOUND_KEYS[a]
  if not key then
    ns.Print(L["/arc sound 3071 plays a game sound; /arc sound barrage 3071 picks it (clear or barrage); /arc sound barrage goes back to the default."])
    return
  end
  if type(ns.db.soundKit) ~= "table" then ns.db.soundKit = {} end
  id = tonumber(b)
  if b == "voice" or b == "voix" then
    if ns.Hud.CanSpeak() then
      ns.db.soundKit[key] = "voice"
      ns.Hud.PreviewSound(key)
      ns.Print(string.format(L["%s: game voice."], L[SOUND_LABEL[key]]))
    else
      ns.Print(L["this client has no text-to-speech voice installed: nothing changed."])
    end
  elseif not id or id <= 0 then
    ns.db.soundKit[key] = nil
    ns.Print(string.format(L["%s: default sound."], L[SOUND_LABEL[key]]))
  elseif ns.Hud.PlayKit(id) then
    ns.db.soundKit[key] = id
    ns.Print(string.format(L["%s: game sound %d."], L[SOUND_LABEL[key]], id))
  else
    ns.Print(string.format(L["the game plays nothing for sound %d: nothing changed."], id))
  end
end

-- ------------------------------------------------------------------ commands
-- English commands, with their French aliases.
local HELP = {
  "/arc: open the settings",
  "/arc demo: watch the HUD play a full cycle",
  "/arc lock: move the HUD, then lock it in place",
  "/arc scale 120: HUD size, in percent",
  "/arc spread 150: distance between your character and the zones (80 to 320)",
  "/arc decor: show or hide the proc decoration (the rune arcs)",
  "/arc sounds: play both sounds (Clearcasting, Missile Barrage)",
  "/arc sound 3071: play a game sound; /arc sound barrage 3071: pick it (clear or barrage)",
  "/arc sound barrage voice: have the game voice say the proc's name; sounds can also be picked in the settings",
  "/arc macro: create the burst macro (Eureka + Presence of Mind + Arcane Wrath) with the exact spell names",
  "/arc diag: a report to copy (spells found, signals read in combat)",
  "/arc reset: restore the default settings",
}

local ALIAS = {
  [""] = "options", options = "options", config = "options",
  demo = "demo",
  lock = "lock", unlock = "lock", move = "lock", verrou = "lock", deplacer = "lock",
  scale = "scale", size = "scale", taille = "scale",
  spread = "spread", ecart = "spread", ["écart"] = "spread",
  decor = "decor", ["décor"] = "decor",
  sounds = "sound", sound = "sound", sons = "sound", son = "sound",
  macro = "macro",
  diag = "diag", report = "diag", rapport = "diag",
  reset = "reset",
}

SLASH_ARCANUM1 = "/arc"
SLASH_ARCANUM2 = "/arcanum"
SlashCmdList.ARCANUM = function(msg)
  if not ns.db then ns.InitDB() end
  msg = (msg or ""):lower():gsub("^%s+", ""):gsub("%s+$", "")
  local word, arg = msg:match("^(%S*)%s*(.-)$")
  local cmd = ALIAS[word]
  if not ns.started then
    if not ns.isMage and cmd ~= "demo" then
      ns.Print(L["is made for mages. Type /arc demo to see the HUD anyway."])
      return
    end
    ns.Start()
  end
  if cmd == "options" then
    Options.Toggle()
  elseif cmd == "demo" then
    State.SetDemo(not State.demo)
    ns.Print(State.demo and L["demo started (/arc demo to stop it)."] or L["demo stopped."])
    Options.Refresh()
  elseif cmd == "lock" then
    ns.Set("locked", not ns.db.locked)
    ns.Print(ns.db.locked and L["HUD locked."] or L["HUD unlocked: drag it, then /arc lock."])
    Options.Refresh()
  elseif cmd == "scale" then
    local v = tonumber(arg)
    if v and v >= 60 and v <= 180 then
      ns.Set("scale", v / 100)
      Options.Refresh()
    else
      ns.Print(L["size between 60 and 180, for example /arc scale 120."])
    end
  elseif cmd == "decor" then
    ns.Set("decor", not ns.db.decor)
    ns.Print(ns.db.decor and L["proc decoration shown."] or L["proc decoration hidden."])
    Options.Refresh()
  elseif cmd == "spread" then
    local v = tonumber(arg)
    if v and v >= 80 and v <= 320 then
      ns.Set("spread", v)
      Options.Refresh()
    else
      ns.Print(L["spread between 80 and 320, for example /arc spread 150."])
    end
  elseif cmd == "sound" then
    soundCommand(arg)
    Options.Refresh()
  elseif cmd == "macro" then
    makeMacro()
  elseif cmd == "diag" then
    ns.Diag.Show()
  elseif cmd == "reset" then
    ns.ResetDB()
    Options.Refresh()
    ns.Print(L["default settings restored."])
  else
    for _, line in ipairs(HELP) do ns.Print(L[line]) end
  end
end
