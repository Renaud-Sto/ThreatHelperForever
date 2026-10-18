-- The small threat frame and the centre-screen alert, drawn like Forever's own nameplate
-- health bar (Blizzard_NamePlates.xml / Blizzard_NamePlateUnitFrame.lua, branch forever):
-- fill "UI-HUD-CoolDownManager-Bar", frame "UI-HUD-CoolDownManager-Bar-BG" at (-2, 3) to
-- (6, -6), border "UI-HUD-CoolDownManager-Selected-yellow" tinted by the threat level.
-- Unknown atlases fall back on plain colour textures. Nil parent then SetParent.
local ADDON, ns = ...
local L = ns.L

local UI = {}
ns.UI = UI

UI.WIDTH, UI.HEIGHT = 196, 52
UI.BAR_WIDTH, UI.BAR_HEIGHT = 184, 16
UI.ATLAS = {
    fill = "UI-HUD-CoolDownManager-Bar",
    frame = "UI-HUD-CoolDownManager-Bar-BG",
    border = "UI-HUD-CoolDownManager-Selected-yellow",
}

UI.COLORS = {
    idle = { 0.5, 0.5, 0.5 },
    untouched = { 0.6, 0.6, 0.6 },
    unknown = { 0.6, 0.6, 0.6 },
    safe = { 0.15, 0.8, 0.15 },
    warn = { 1, 0.82, 0 },
    danger = { 1, 0.45, 0 },
    lost = { 1, 0.1, 0.1 },
}

local function font(parent, objects)
    local fs = parent:CreateFontString(nil, "OVERLAY")
    for _, name in ipairs(objects) do
        if type(_G[name]) == "table" then
            if type(fs.SetFontObject) == "function" then fs:SetFontObject(_G[name]) end
            break
        end
    end
    fs:SetJustifyH("LEFT")
    fs:SetWordWrap(false)
    return fs
end

local function hasAtlas(name)
    if type(C_Texture) ~= "table" or type(C_Texture.GetAtlasInfo) ~= "function" then return false end
    local ok, info = pcall(C_Texture.GetAtlasInfo, name)
    return ok and type(info) == "table"
end

-- One atlas per texture for life (native-ui.md); a plain colour when the atlas is missing.
local function texture(parent, layer, sublevel, atlas, r, g, b, a)
    local t = parent:CreateTexture(nil, layer, nil, sublevel)
    if atlas and hasAtlas(atlas) then
        t:SetAtlas(atlas)
        t.isAtlas = true
    else
        t:SetColorTexture(r, g, b, a)
        t.isAtlas = false
    end
    return t
end

local function savePosition(frame)
    local left, top = frame:GetLeft(), frame:GetTop()
    if type(left) == "number" and type(top) == "number" then
        frame:ClearAllPoints()
        frame:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", left, top)
        local db = ns.Main and ns.Main.db
        if db then db.settings.pos = { x = left, y = top } end
    end
end

function UI.build(settings)
    if UI.frame then return UI.frame end
    local f = CreateFrame("Frame", "ThreatHelperForeverFrame", nil)
    f:SetParent(UIParent)
    f:Hide()
    UI.frame = f
    f:SetSize(UI.WIDTH, UI.HEIGHT)
    f:SetFrameStrata("MEDIUM")
    f:SetClampedToScreen(true)
    f:SetMovable(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", function(self) if not settings.locked then self:StartMoving() end end)
    f:SetScript("OnDragStop", function(self) self:StopMovingOrSizing(); savePosition(self) end)
    UI.applyPosition(settings)

    -- Shown only while unlocked, so the player sees what to drag.
    local handle = f:CreateTexture(nil, "BACKGROUND")
    handle:SetColorTexture(0, 0, 0, 0.35)
    handle:SetAllPoints(f)

    local title = font(f, { "GameFontNormalSmall" })
    title:SetPoint("TOPLEFT", f, "TOPLEFT", 4, -2)
    title:SetText(L.TITLE)

    local status = font(f, { "GameFontHighlightSmall" })
    status:SetPoint("TOPRIGHT", f, "TOPRIGHT", -4, -2)
    status:SetJustifyH("RIGHT")

    -- The bar, as on a nameplate: frame behind, fill, border tinted by level.
    local bar = CreateFrame("Frame", nil, f)
    bar:SetSize(UI.BAR_WIDTH, UI.BAR_HEIGHT)
    bar:SetPoint("TOPLEFT", f, "TOPLEFT", 4, -17)

    local back = texture(bar, "BACKGROUND", 0, UI.ATLAS.frame, 0, 0, 0, 0.7)
    if back.isAtlas then
        back:SetPoint("TOPLEFT", bar, "TOPLEFT", -2, 3)
        back:SetPoint("BOTTOMRIGHT", bar, "BOTTOMRIGHT", 6, -6)
    else
        back:SetAllPoints(bar)
    end

    local fill = texture(bar, "ARTWORK", 0, UI.ATLAS.fill, 1, 1, 1, 1)
    fill:SetPoint("TOPLEFT", bar, "TOPLEFT", 0, 0)
    fill:SetPoint("BOTTOMLEFT", bar, "BOTTOMLEFT", 0, 0)
    fill:SetWidth(1)

    local border = texture(bar, "OVERLAY", 0, UI.ATLAS.border, 1, 1, 1, 0)
    if border.isAtlas then
        border:SetDesaturated(true)
        border:SetPoint("TOPLEFT", back, "TOPLEFT", -3, 2)
        border:SetPoint("BOTTOMRIGHT", back, "BOTTOMRIGHT", 0, 2)
    end

    local who = font(bar, { "SystemFont_NamePlate", "GameFontHighlight" })
    who:SetPoint("LEFT", bar, "LEFT", 6, 0)
    who:SetPoint("RIGHT", bar, "RIGHT", -44, 0)
    local pct = font(bar, { "SystemFont_NamePlate", "GameFontHighlight" })
    pct:SetPoint("RIGHT", bar, "RIGHT", -6, 0)
    pct:SetJustifyH("RIGHT")

    local detail = font(f, { "GameFontHighlightSmall" })
    detail:SetPoint("TOPLEFT", bar, "BOTTOMLEFT", 0, -6)
    detail:SetPoint("RIGHT", f, "RIGHT", -4, 0)

    UI.status, UI.fill, UI.border, UI.who, UI.pct, UI.detail, UI.handle = status, fill, border, who, pct, detail, handle
    UI.buildAlert()
    UI.buildPlate()
    UI.setLocked(settings.locked)
    return f
end

function UI.applyPosition(settings)
    local f = UI.frame
    if not f then return end
    f:ClearAllPoints()
    local pos = settings.pos
    if type(pos) == "table" and type(pos.x) == "number" and type(pos.y) == "number" then
        f:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", pos.x, pos.y)
    else
        f:SetPoint("CENTER", UIParent, "CENTER", 0, -180)
    end
end

function UI.setLocked(locked)
    if UI.frame then UI.frame:EnableMouse(not locked) end
    if UI.handle then UI.handle:SetShown(not locked) end
end

function UI.buildAlert()
    local a = CreateFrame("Frame", "ThreatHelperForeverAlert", nil)
    a:SetParent(UIParent)
    a:Hide()
    a:SetSize(600, 40)
    a:SetFrameStrata("HIGH")
    a:SetPoint("CENTER", UIParent, "CENTER", 0, 220)
    local fs = a:CreateFontString(nil, "OVERLAY")
    if type(fs.SetFontObject) == "function" and _G.GameFontNormalHuge then fs:SetFontObject(_G.GameFontNormalHuge) end
    fs:SetAllPoints(a)
    fs:SetJustifyH("CENTER")
    UI.alertFrame, UI.alertText = a, fs
    UI.alertToken = 0
end

-- Shows `message` in the centre for 2.5 s; a newer alert replaces it.
function UI.alert(level, message)
    if not UI.alertFrame then return end
    local c = UI.COLORS[level] or UI.COLORS.unknown
    UI.alertText:SetText(message)
    UI.alertText:SetTextColor(c[1], c[2], c[3])
    UI.alertFrame:Show()
    UI.alertToken = UI.alertToken + 1
    local token = UI.alertToken
    if C_Timer and type(C_Timer.After) == "function" then
        C_Timer.After(2.5, function()
            if token == UI.alertToken then UI.alertFrame:Hide() end
        end)
    end
end

-- Draws an evaluation (Threat.evaluate) and the loose-mob count.
function UI.render(result, looseMobs)
    if not UI.frame then return end
    local level = result.level
    local c = UI.COLORS[level] or UI.COLORS.unknown
    UI.status:SetText(L["LEVEL_" .. level])
    UI.status:SetTextColor(c[1], c[2], c[3])

    -- The bar is the player's hold: full when safe, empty once lost (the border stays red).
    local hold = ns.Threat.hold(result)
    local share = hold and hold / 100 or 0
    local width = math.max(1, UI.BAR_WIDTH * share)
    UI.fill:SetWidth(width)
    if UI.fill.isAtlas then UI.fill:SetTexCoord(0, width / UI.BAR_WIDTH, 0, 1) end
    UI.fill:SetVertexColor(c[1], c[2], c[3])
    UI.fill:SetShown(share > 0)
    UI.border:SetVertexColor(c[1], c[2], c[3])
    UI.border:SetShown(level == "warn" or level == "danger" or level == "lost")

    if level == "lost" then
        UI.who:SetText(result.holder or L.SOMEONE)
        UI.pct:SetText("")
    elseif hold then
        UI.who:SetText(result.top and (result.top.name or L.SOMEONE) or "")
        UI.pct:SetText(string.format("%d%%", math.floor(hold + 0.5)))
    else
        UI.who:SetText("")
        UI.pct:SetText("")
    end

    if type(looseMobs) == "number" and looseMobs > 0 then
        UI.detail:SetText(string.format(L.LOOSE, looseMobs))
    else
        UI.detail:SetText("")
    end
end

-- Percentages next to nameplates (the target's, or every mob in combat with the player).
-- Our own frames under UIParent, only ANCHORED to the nameplates: never parented into them
-- nor writing to them (taint rules). A small pool, reused from one update to the next.
-- SystemFont_NamePlate is the font of the plate's own health text (Blizzard_NamePlates.xml).
UI.PLATE_FONTS = { "SystemFont_NamePlate", "GameFontHighlightOutline", "GameFontHighlight" }

UI.plates = {}

function UI.buildPlate()
    local p = CreateFrame("Frame", nil, nil)
    p:SetParent(UIParent)
    p:Hide()
    p:SetSize(40, 14)
    p:SetFrameStrata("LOW")
    local fs = p:CreateFontString(nil, "OVERLAY")
    for _, name in ipairs(UI.PLATE_FONTS) do
        if type(_G[name]) == "table" then
            if type(fs.SetFontObject) == "function" then fs:SetFontObject(_G[name]) end
            break
        end
    end
    fs:SetPoint("LEFT", p, "LEFT", 0, 0)
    fs:SetJustifyH("LEFT")
    local entry = { frame = p, text = fs }
    UI.plates[#UI.plates + 1] = entry
    return entry
end

-- The number shown: the player's hold (Threat.hold), nil hides it.
function UI.plateValue(result)
    return ns.Threat.hold(result)
end

local function shown(frame)
    if type(frame) ~= "table" or type(frame.IsShown) ~= "function" then return false end
    local ok, v = pcall(frame.IsShown, frame)
    if not ok or (issecretvalue and issecretvalue(v)) then return false end
    return v == true
end

-- Right of the level box when the plate shows one (Forever: UnitFrame.PlayerLevelDiffFrame,
-- Camelot/Blizzard_NamePlateLevelFrame.xml, 5 px right of the health bar), else right of
-- the health bar, else the plate itself.
function UI.plateAnchor(plateFrame)
    local uf = type(plateFrame.UnitFrame) == "table" and plateFrame.UnitFrame or nil
    if not uf then return plateFrame end
    if shown(uf.PlayerLevelDiffFrame) then return uf.PlayerLevelDiffFrame end
    if shown(uf.LevelFrame) then return uf.LevelFrame end
    local hb = type(uf.HealthBarsContainer) == "table" and uf.HealthBarsContainer.healthBar
    if type(hb) == "table" then return hb end
    return uf
end

function UI.relativeScale(anchor)
    if type(anchor.GetEffectiveScale) ~= "function" or type(UIParent.GetEffectiveScale) ~= "function" then return nil end
    local ok1, a = pcall(anchor.GetEffectiveScale, anchor)
    local ok2, u = pcall(UIParent.GetEffectiveScale, UIParent)
    if not (ok1 and ok2) or type(a) ~= "number" or type(u) ~= "number" then return nil end
    if (issecretvalue and (issecretvalue(a) or issecretvalue(u))) or u <= 0 or a <= 0 then return nil end
    return a / u
end

-- Draws one percentage; plateFrame: a nameplate from C_NamePlate.GetNamePlateForUnit, or nil.
function UI.drawPlate(p, result, _, plateFrame, settings)
    local value = UI.plateValue(result)
    if not settings.plate or type(plateFrame) ~= "table" or value == nil then
        p.frame:Hide()
        return
    end
    local anchor = UI.plateAnchor(plateFrame)
    -- Nameplates live outside UIParent with their own scale: match it so the text has the
    -- size of the plate's own numbers.
    local scale = UI.relativeScale(anchor)
    if scale then p.frame:SetScale(scale) end
    p.frame:ClearAllPoints()
    local ok = pcall(p.frame.SetPoint, p.frame, "LEFT", anchor, "RIGHT", settings.plateDX, settings.plateDY)
    if not ok then
        p.frame:Hide()
        return
    end
    local c = UI.COLORS[result.level] or UI.COLORS.unknown
    p.text:SetText(string.format("%d%%", math.floor(value + 0.5)))
    p.text:SetTextColor(c[1], c[2], c[3])
    p.frame:Show()
end

-- entries: { { result, myScaled, plate }, ... }; extra pooled frames are hidden.
function UI.renderPlates(entries, settings)
    for i, e in ipairs(entries) do
        UI.drawPlate(UI.plates[i] or UI.buildPlate(), e.result, e.myScaled, e.plate, settings)
    end
    for i = #entries + 1, #UI.plates do UI.plates[i].frame:Hide() end
end

UI.font, UI.texture, UI.hasAtlas = font, texture, hasAtlas
UI.ADDON = ADDON
return UI
