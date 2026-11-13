-- Arcanum — diagnostics: a report to copy and paste, saying what the game lets addons read.
--
-- WoW Forever's rules change from one version to the next. The report shows, for each spell and each proc,
-- where Arcanum gets its information (aura, cost, button glow, spells cast), and keeps a log of the latest
-- state changes: enough to fix things quickly when a proc does not show up.
local ADDON, ns = ...
local UI, State, Spells, S = ns.UI, ns.State, ns.Spells, ns.Secret
local C = UI.C
local L = ns.L

local Diag = {}
ns.Diag = Diag

local LOG_MAX = 120
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
ns:On("PROC_END", function(key) if not State.demo then record("end " .. key) end end)
-- A channel fires one event per volley (six for Arcane Missiles): they are merged on one line, otherwise
-- they push what we are looking for out of the log.
local lastCast = {}   -- key, at, line (the log entry), prefix, count
ns:On("CAST", function(key)
  local now = GetTime()
  local line = log[#log]
  if lastCast.key == key and now - lastCast.at < 1.5 and line == lastCast.line then
    lastCast.at, lastCast.count = now, lastCast.count + 1
    lastCast.line = lastCast.prefix .. " x" .. lastCast.count
    log[#log] = lastCast.line
    return
  end
  record("cast " .. key)
  lastCast.key, lastCast.at, lastCast.count = key, now, 1
  lastCast.prefix, lastCast.line = log[#log], log[#log]
end)

local function show(v)
  if S.Is(v) then return "<secret>" end
  if v == nil then return "nil" end
  if type(v) == "number" then return (v % 1 == 0) and tostring(v) or string.format("%.2f", v) end
  return tostring(v)
end

local function yesno(v)
  return v and L["yes"] or L["no"]
end

-- Values the engine stores or returns as plain English words, shown in the client's language.
local WORD = {
  secret = L["secret"], readable = L["readable"], none = L["none"], unreadable = L["unreadable"],
  up = L["up"], down = L["down"], unknown = L["unknown"],
}
local function word(v)
  return WORD[v] or tostring(v)
end

local function secrecy(id)
  local CS = C_Secrets
  if not CS then return "-" end
  local base, now = "?", "?"
  if CS.GetSpellAuraSecrecy then
    local ok, lvl = pcall(CS.GetSpellAuraSecrecy, id)
    if ok and not S.Is(lvl) and lvl ~= nil then
      base = ({ [0] = L["never"], [1] = L["always"], [2] = L["depends on context"] })[lvl] or tostring(lvl)
    end
  end
  if CS.ShouldSpellAuraBeSecret then
    local ok, r = pcall(CS.ShouldSpellAuraBeSecret, id)
    if ok and not S.Is(r) and r ~= nil then now = r and L["secret"] or L["readable"] end
  end
  return string.format(L["%s, right now %s"], base, now)
end

function Diag.Report()
  local out = {}
  local function add(fmt, ...) out[#out + 1] = select("#", ...) > 0 and string.format(fmt, ...) or fmt end
  local version, build, _, interface = "?", "?", nil, "?"
  if GetBuildInfo then version, build, _, interface = GetBuildInfo() end
  local _, class = UnitClass("player")
  add(L["Arcanum %s — diagnostics"], ns.VERSION)
  add(L["Client %s (%s), interface %s, language %s"], show(version), show(build), show(interface), show(GetLocale and GetLocale()))
  add(L["Class %s, level %s"], show(class), show(UnitLevel and UnitLevel("player")))
  add(L["Secret values: %s · auras hidden right now: %s · in combat: %s"],
    yesno(S.RESTRICTED), yesno(State.restricted), yesno(State.combat))
  add(L["Lua errors: %d%s"], ns.errorCount or 0, ns.lastError and (" · " .. ns.lastError) or "")

  add("")
  add(L["SPELLS (key, name, highest rank, known, announced cost)"])
  local keys = {}
  for key in pairs(Spells.DEF) do keys[#keys + 1] = key end
  table.sort(keys)
  for _, key in ipairs(keys) do
    local def = Spells.DEF[key]
    local cost, why = Spells.Cost(key)
    add("  %-11s %-28s id %-8s %-6s %s", key, show(def.name), show(def.best or def.id),
      def.known and L["known"] or "-", cost and show(cost) or ("(" .. word(why) .. ")"))
  end

  add("")
  add(L["NAMES FOR MACROS (special spaces are spelled out)"])
  for _, key in ipairs({ "eureka", "pom", "wrath" }) do
    local name = Spells.Name(key)
    if name then
      local visible = name:gsub("\194\160", "[nbsp]"):gsub("\226\128\175", "[narrow nbsp]")
      add("  %-8s %s", key, visible)
    end
  end

  add("")
  add(L["AURAS (read right now · secrecy per spell id)"])
  for _, key in ipairs({ "blast", "barrage", "clear", "power", "pom", "eureka" }) do
    local def = Spells.DEF[key]
    local st, a = State.ReadAura(key)
    local detail = ""
    if st == "up" then
      detail = string.format(L[" stacks %s, duration %s, expires %s"], show(a.applications), show(a.duration), show(a.expirationTime))
    end
    add("  %-8s %s%s", key, word(st), detail)
    for _, id in ipairs(def.auras or { def.id }) do add("             %d: %s", id, secrecy(id)) end
  end

  add("")
  add(L["STATE"])
  add(L["  reminders: %s"], #State.reminders > 0 and table.concat(State.reminders, ", ") or L["none"])
  add(L["  charges %d (source %s), window ends in %s s"], State.stacks, tostring(State.stacksSource),
    State.stacksExpire and show(State.stacksExpire - GetTime()) or "?")
  for _, key in ipairs({ "barrage", "clear", "power", "pom", "eureka" }) do
    local p = State[key]
    add("  %-8s %s", key, p.active and string.format(L["active (source %s)"], tostring(p.source)) or "-")
  end
  local glow = {}
  for id in pairs(State.overlay) do glow[#glow + 1] = tostring(id) end
  add(L["  glowing buttons: %s"], #glow > 0 and table.concat(glow, ", ") or L["no button"])
  local icons = {}
  for _, key in ipairs({ "barrage", "clear", "power", "pom" }) do
    if State.cdm[key] ~= nil then icons[#icons + 1] = key .. "=" .. (State.cdm[key] and L["active"] or L["off"]) end
  end
  add(L["  Cooldown Manager (tracked buffs): %s"], #icons > 0 and table.concat(icons, ", ") or L["no proc icon found"])

  add("")
  add(L["LEARNED IN GAME"])
  local l = ns.db and ns.db.learn or {}
  local parts = {}
  for k, v in pairs(l.dur or {}) do parts[#parts + 1] = k .. "=" .. show(v) end
  add(L["  durations: %s"], #parts > 0 and table.concat(parts, ", ") or L["none (default values)"])
  add(L["  Arcane Blast: charge window %s s, base cost %s, extra cost per charge %s, cost follows charges: %s"],
    show(l.abWindow or State.Duration("blast")), show(l.abBase), show(l.abStep), yesno(l.costTracks))
  add(L["  Barrage seen by glow: %s · by cost: %s · Clearcasting seen by cost: %s"],
    yesno(l.mbGlow), yesno(l.mbCost), yesno(l.ccCost))

  add("")
  add(L["CHECKED IN GAME (what the game lets addons read in combat)"])
  local checks = l.checks or {}
  add(L["  player mana: %s"], checks.mana and word(checks.mana) or L["not seen yet"])
  add(L["  \"spell usable / not enough mana\": %s"], checks.usable and word(checks.usable) or L["not seen yet"])
  add(L["  spell cooldowns: %s"], checks.cooldown and word(checks.cooldown) or L["not seen yet"])

  add("")
  add(L["LOG (last %d changes)"], #log)
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
  title:SetText(L["Arcanum diagnostics"])
  local hint = UI.Text(f, 11, C.muted)
  hint:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -4)
  hint:SetText(L["The text is selected: Ctrl+C to copy it. Escape to close."])

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
  -- read-only: any keystroke puts the report back
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
  f.text = ok and text or (L["Could not build the report: "] .. tostring(text))
  f.eb:SetText(f.text)
  f:Show()
  f:Raise()
  f.eb:SetFocus()
  f.eb:HighlightText()
end
