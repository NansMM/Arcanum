-- Arcanum — thème : couleurs, polices, textures et petites briques d'affichage.
local ADDON, ns = ...

local UI = {}
ns.UI = UI

local MEDIA = "Interface\\AddOns\\" .. ADDON .. "\\Media\\"

UI.FONT = {
  title = "Fonts\\FRIZQT__.TTF",
  body = "Fonts\\ARIALN.TTF",
}

UI.C = {
  ink = { 0.030, 0.024, 0.066 },        -- noir indigo : fonds
  panel = { 0.062, 0.052, 0.118 },      -- cartes
  panelHi = { 0.110, 0.094, 0.196 },
  socket = { 0.130, 0.108, 0.240 },     -- cristal vide
  edge = { 0.470, 0.380, 0.860 },       -- liserés
  arcane = { 0.690, 0.486, 1.000 },     -- violet des Arcanes
  arcaneHi = { 0.900, 0.820, 1.000 },
  hot = { 1.000, 0.560, 0.930 },        -- charges au maximum
  barrage = { 1.000, 0.450, 0.800 },    -- Barrage de projectiles
  clear = { 0.400, 0.860, 1.000 },      -- Idées claires
  power = { 1.000, 0.800, 0.400 },      -- Pouvoir des Arcanes
  pom = { 0.560, 1.000, 0.840 },        -- Présence spirituelle
  heat = { 1.000, 0.560, 0.240 },       -- Échauffement
  mana = { 0.340, 0.560, 1.000 },
  manaLow = { 1.000, 0.700, 0.300 },
  bad = { 0.980, 0.360, 0.420 },
  text = { 0.950, 0.930, 1.000 },
  muted = { 0.660, 0.630, 0.800 },
  faint = { 0.430, 0.400, 0.580 },
}

UI.WHITE = "Interface\\Buttons\\WHITE8X8"

function UI.Media(name)
  return MEDIA .. name
end

-- Texture teintée. file : nom dans Media, ou nil pour un aplat.
function UI.Tex(parent, layer, file, color, alpha, blend, sub)
  local t = parent:CreateTexture(nil, layer or "ARTWORK", nil, sub)
  t:SetTexture(file and (MEDIA .. file) or UI.WHITE)
  if color then t:SetVertexColor(color[1], color[2], color[3], alpha or 1) end
  if blend then t:SetBlendMode(blend) end
  return t
end

function UI.Color(region, color, alpha)
  region:SetVertexColor(color[1], color[2], color[3], alpha or 1)
end

function UI.Text(parent, size, color, font, flags)
  local fs = parent:CreateFontString(nil, "OVERLAY")
  fs:SetFont(font or UI.FONT.body, size or 12, flags or "")
  local c = color or UI.C.text
  fs:SetTextColor(c[1], c[2], c[3], 1)
  fs:SetShadowOffset(1, -1)
  fs:SetShadowColor(0, 0, 0, 0.85)
  return fs
end

-- Fond en pilule (bords ronds) : deux demi-cercles et un aplat. Retourne les trois textures.
function UI.Pill(frame, color, alpha, layer, sub)
  local h = frame:GetHeight()
  local left = UI.Tex(frame, layer or "BACKGROUND", "circle", color, alpha, nil, sub)
  left:SetTexCoord(0, 0.5, 0, 1)
  left:SetPoint("TOPLEFT")
  left:SetPoint("BOTTOMLEFT")
  left:SetWidth(h / 2)
  local right = UI.Tex(frame, layer or "BACKGROUND", "circle", color, alpha, nil, sub)
  right:SetTexCoord(0.5, 1, 0, 1)
  right:SetPoint("TOPRIGHT")
  right:SetPoint("BOTTOMRIGHT")
  right:SetWidth(h / 2)
  local mid = UI.Tex(frame, layer or "BACKGROUND", nil, color, alpha, nil, sub)
  mid:SetPoint("TOPLEFT", left, "TOPRIGHT")
  mid:SetPoint("BOTTOMRIGHT", right, "BOTTOMLEFT")
  return { left, mid, right }
end

-- Fond à coins arrondis pour les panneaux (texture étirée par neuf tranches si le client le permet).
function UI.Panel(frame, color, alpha, layer, sub, inset)
  local t = UI.Tex(frame, layer or "BACKGROUND", "roundsq", color, alpha, nil, sub)
  inset = inset or 0
  t:SetPoint("TOPLEFT", inset, -inset)
  t:SetPoint("BOTTOMRIGHT", -inset, inset)
  if t.SetTextureSliceMargins then
    pcall(t.SetTextureSliceMargins, t, 16, 16, 16, 16)
    if t.SetTextureSliceMode and Enum and Enum.UITextureSliceMode then
      pcall(t.SetTextureSliceMode, t, Enum.UITextureSliceMode.Stretched)
    end
  end
  return t
end

-- Approche douce d'une valeur vers sa cible (indépendante du nombre d'images par seconde).
function UI.Approach(cur, target, dt, speed)
  local k = dt * (speed or 12)
  if k > 1 then k = 1 end
  local v = cur + (target - cur) * k
  if math.abs(target - v) < 0.002 then return target end
  return v
end

function UI.Mix(a, b, t)
  return a[1] + (b[1] - a[1]) * t, a[2] + (b[2] - a[2]) * t, a[3] + (b[3] - a[3]) * t
end
