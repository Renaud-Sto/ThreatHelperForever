-- The list of mobs in combat with the player, sorted by danger (lowest hold first), in the
-- style of the Menace frame. Display only.
--
-- History (2026-10-18, build 70450): renaud first chose rows that target their mob on click.
-- Forever forbids it: the secure macro parser refuses nameplate tokens
-- ("[@nameplate1,exists]" false while UnitExists is true), and a SecureActionButtonTemplate
-- with unit "nameplateN" and type "target" received every click (15 logged) without ever
-- changing the target, with no blocked-action event. With no click to protect, the rows are
-- plain frames: they can be sorted, packed and shown or hidden at any time, even in combat.
local _, ns = ...
local L = ns.L

local List = {}
ns.List = List

List.ROW_W, List.ROW_H, List.GAP, List.HEADER = 190, 18, 4, 16
List.rows = {}

-- Kept for the other modules: nothing in the list is protected any more.
function List.inCombat()
    return type(InCombatLockdown) == "function" and InCombatLockdown() == true
end

local function savePosition(frame)
    local left, top = frame:GetLeft(), frame:GetTop()
    if type(left) == "number" and type(top) == "number" then
        frame:ClearAllPoints()
        frame:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", left, top)
        local db = ns.Main and ns.Main.db
        if db then db.settings.listPos = { x = left, y = top } end
    end
end

local function buildRow(container, i)
    local U = ns.UI
    local face = CreateFrame("Frame", nil, container)
    face:SetSize(List.ROW_W, List.ROW_H)
    face:SetPoint("TOPLEFT", container, "TOPLEFT", 0, -(List.HEADER + (i - 1) * (List.ROW_H + List.GAP)))
    local back = U.texture(face, "BACKGROUND", 0, U.ATLAS.frame, 0, 0, 0, 0.7)
    if back.isAtlas then
        back:SetPoint("TOPLEFT", face, "TOPLEFT", -2, 3)
        back:SetPoint("BOTTOMRIGHT", face, "BOTTOMRIGHT", 6, -6)
    else
        back:SetAllPoints(face)
    end
    local fill = U.texture(face, "ARTWORK", 0, U.ATLAS.fill, 1, 1, 1, 1)
    fill:SetPoint("TOPLEFT", face, "TOPLEFT", 0, 0)
    fill:SetPoint("BOTTOMLEFT", face, "BOTTOMLEFT", 0, 0)
    fill:SetWidth(1)
    local border = U.texture(face, "OVERLAY", 0, U.ATLAS.border, 1, 1, 1, 0)
    if border.isAtlas then
        border:SetPoint("TOPLEFT", back, "TOPLEFT", -3, 2)
        border:SetPoint("BOTTOMRIGHT", back, "BOTTOMRIGHT", 0, 2)
    end
    border:Hide()
    local name = U.font(face, { "SystemFont_NamePlate", "GameFontHighlightSmall" })
    name:SetPoint("LEFT", face, "LEFT", 5, 0)
    name:SetPoint("RIGHT", face, "RIGHT", -40, 0)
    local pct = U.font(face, { "SystemFont_NamePlate", "GameFontHighlightSmall" })
    pct:SetPoint("RIGHT", face, "RIGHT", -5, 0)
    pct:SetJustifyH("RIGHT")
    face:Hide()
    return { face = face, fill = fill, border = border, name = name, pct = pct }
end

function List.build(settings)
    if List.frame then return List.frame end
    local f = CreateFrame("Frame", "ThreatHelperForeverList", nil)
    f:SetParent(UIParent)
    f:Hide()
    List.frame = f
    f:SetSize(List.ROW_W, List.HEADER + settings.listRows * (List.ROW_H + List.GAP))
    f:SetFrameStrata("MEDIUM")
    f:SetClampedToScreen(true)
    f:SetMovable(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", function(self) if not settings.locked then self:StartMoving() end end)
    f:SetScript("OnDragStop", function(self) self:StopMovingOrSizing(); savePosition(self) end)
    List.applyPosition(settings)

    local handle = f:CreateTexture(nil, "BACKGROUND")
    handle:SetColorTexture(0, 0, 0, 0.35)
    handle:SetAllPoints(f)
    List.handle = handle
    local title = ns.UI.font(f, { "GameFontNormalSmall" })
    title:SetPoint("TOPLEFT", f, "TOPLEFT", 2, -1)
    title:SetText(L.LIST_TITLE)
    List.title = title

    for i = 1, settings.listRows do List.rows[i] = buildRow(f, i) end
    List.setLocked(settings.locked)
    return f
end

function List.applyPosition(settings)
    local f = List.frame
    if not f then return end
    f:ClearAllPoints()
    local pos = settings.listPos
    if type(pos) == "table" and type(pos.x) == "number" and type(pos.y) == "number" then
        f:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", pos.x, pos.y)
    else
        f:SetPoint("TOPLEFT", UIParent, "CENTER", 120, -150)
    end
end

function List.setLocked(locked)
    if not List.frame then return end
    List.frame:EnableMouse(not locked)
    List.handle:SetShown(not locked)
end

-- Shown when the list is on, and unlocked or with mobs to show.
function List.wanted(settings, count)
    return settings.list and (not settings.locked or (count or 0) > 0)
end

function List.setShown(shown)
    if List.frame then List.frame:SetShown(shown) end
    return true
end

-- The order of the rows: lowest hold first (the mob about to go), unknown last.
function List.sort(rows)
    table.sort(rows, function(a, b)
        local ha, hb = ns.Threat.hold(a.result), ns.Threat.hold(b.result)
        if ha == nil then return false end
        if hb == nil then return true end
        if ha ~= hb then return ha < hb end
        return (a.name or "") < (b.name or "")
    end)
    return rows
end

-- rows: an array of { name, result, isTarget }, already sorted; extra rows are hidden.
function List.render(rows, settings)
    if not List.frame then return end
    local U = ns.UI
    for i, r in ipairs(List.rows) do
        local data = rows[i]
        if data then
            local result = data.result or { level = "untouched" }
            local hold = ns.Threat.hold(result)
            local c = U.COLORS[result.level] or U.COLORS.unknown
            r.name:SetText(data.name or "?")
            r.pct:SetText(hold and string.format("%d%%", math.floor(hold + 0.5)) or "")
            r.pct:SetTextColor(1, 1, 1)         -- white over the coloured fill (green on green was unreadable)
            local width = math.max(1, List.ROW_W * (hold or 0) / 100)
            r.fill:SetWidth(width)
            if r.fill.isAtlas then r.fill:SetTexCoord(0, width / List.ROW_W, 0, 1) end
            r.fill:SetVertexColor(c[1], c[2], c[3])
            r.fill:SetShown((hold or 0) > 0)
            r.border:SetShown(data.isTarget == true)
            r.face:SetAlpha(hold and 1 or 0.5)
            r.face:Show()
        else
            r.face:Hide()
        end
    end
    local shown = math.min(#rows, #List.rows)
    List.frame:SetHeight(List.HEADER + math.max(1, shown) * (List.ROW_H + List.GAP))
    List.setShown(List.wanted(settings, shown))
end

return List
