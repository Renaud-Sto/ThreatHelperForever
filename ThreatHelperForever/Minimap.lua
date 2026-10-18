-- The minimap button: left click opens the settings window, right click locks or unlocks
-- the frames, a left drag moves it around the minimap. The LibDBIcon convention without
-- the library (recipe of the wow-addon-dev skill, adapted from CraftProfit's
-- UI/MinimapButton.lua, measured in game on Forever): 31x31, strata MEDIUM, level 8, nil
-- parent then SetParent(Minimap), OnUpdate only during a drag, never made while hidden.
local _, ns = ...
local L = ns.L

local Minimap_ = {}
ns.Minimap = Minimap_

Minimap_.NAME = "ThreatHelperForeverMinimapButton"
Minimap_.SIZE, Minimap_.LEVEL = 31, 8
Minimap_.DEFAULT_ANGLE = 200
-- The addon's own icon (Media/icon.tga, 64x64, made by tools/make_icon.ps1 from the
-- artwork renaud generated, 2026-10-18). A file shipped by the addon has no game file id,
-- so it is used as is; the game icon stays as a fallback for a client that cannot load it.
Minimap_.ICON = "Interface\\AddOns\\ThreatHelperForever\\Media\\icon"
Minimap_.ICON_FALLBACK = "Interface\\Icons\\Ability_Warrior_DefensiveStance"
local BORDER = "Interface\\Minimap\\MiniMap-TrackingBorder"
local BACKGROUND = "Interface\\Minimap\\UI-Minimap-Background"
local HIGHLIGHT = "Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight"

local function finite(v) return type(v) == "number" and v == v and v ~= math.huge and v ~= -math.huge end

-- Pure helpers ----------------------------------------------------------------------

-- Direction from the minimap centre to the cursor, degrees in [0, 360), 0 to the right.
function Minimap_.angleFromCursor(cx, cy, mx, my)
    if not (finite(cx) and finite(cy) and finite(mx) and finite(my)) then return nil end
    return math.deg(math.atan2(cy - my, cx - mx)) % 360
end

-- Offset of the button's centre from the minimap's centre (round or square minimap).
function Minimap_.offset(angle, radius, square)
    if not finite(angle) then angle = Minimap_.DEFAULT_ANGLE end
    if not finite(radius) or radius < 0 then radius = 0 end
    local rad = math.rad(angle % 360)
    local x, y = math.cos(rad), math.sin(rad)
    if not square then return x * radius, y * radius end
    local diag = math.max(0, math.sqrt(2 * radius * radius) - 10)
    return math.max(-radius, math.min(x * diag, radius)), math.max(-radius, math.min(y * diag, radius))
end

-- Widget ----------------------------------------------------------------------------

local button

local function map() return type(_G.Minimap) == "table" and _G.Minimap or nil end
local function settings() return ns.Main.db.settings end

local function isSquare()
    if type(_G.GetMinimapShape) ~= "function" then return false end
    local ok, shape = pcall(_G.GetMinimapShape)
    return ok and shape == "SQUARE"
end

local function place(angle)
    local m = map()
    if not button or not m then return end
    local width = type(m.GetWidth) == "function" and m:GetWidth() or nil
    if not finite(width) or width <= 0 then width = 140 end
    local x, y = Minimap_.offset(angle, width / 2 + 5, isSquare())
    button:ClearAllPoints()
    button:SetPoint("CENTER", m, "CENTER", x, y)
end

function Minimap_.iconPath()
    return Minimap_.ICON
end

local function cursorAngle()
    local m = map()
    if not m or type(_G.GetCursorPosition) ~= "function" then return nil end
    local cx, cy = _G.GetCursorPosition()
    local scale = type(m.GetEffectiveScale) == "function" and m:GetEffectiveScale() or 1
    if not finite(scale) or scale <= 0 then scale = 1 end
    local mx, my = m:GetCenter()
    if not finite(cx) or not finite(cy) then return nil end
    return Minimap_.angleFromCursor(cx / scale, cy / scale, mx, my)
end

local function follow()
    local angle = cursorAngle()
    if angle then
        button.dragAngle = angle
        place(angle)
    end
end

local function stopDrag()
    if button.dragging ~= true then return end
    button.dragging = false
    button:SetScript("OnUpdate", nil)
    if finite(button.dragAngle) then settings().minimap.angle = button.dragAngle end
end

local function onUpdate()
    -- A mouse-up that never arrives (alt-tab) must not leave the drag running.
    if type(_G.IsMouseButtonDown) == "function" and not _G.IsMouseButtonDown("LeftButton") then
        follow()
        stopDrag()
        return
    end
    follow()
end

local function showTooltip(self)
    local tip = _G.GameTooltip
    if button.dragging == true or type(tip) ~= "table" then return end
    tip:SetOwner(self, "ANCHOR_LEFT")
    if type(_G.GameTooltip_SetTitle) == "function" then _G.GameTooltip_SetTitle(tip, "ThreatHelper Forever") end
    if type(_G.GameTooltip_AddInstructionLine) == "function" then
        for _, key in ipairs({ "MINIMAP_TIP_LEFT", "MINIMAP_TIP_RIGHT", "MINIMAP_TIP_DRAG" }) do
            _G.GameTooltip_AddInstructionLine(tip, L[key])
        end
    end
    tip:Show()
end

local function hideTooltip()
    if type(_G.GameTooltip) == "table" then _G.GameTooltip:Hide() end
end

local function texture(layer, path, w, h)
    local t = button:CreateTexture(nil, layer)
    t:SetTexture(path)
    t:SetSize(w, h)
    return t
end

function Minimap_.create()
    if button then return button end
    local m = map()
    if not m or settings().minimap.hide then return nil end
    -- Nil parent then SetParent: the minimap is a Blizzard frame (gamepad CreateFrame hook).
    button = CreateFrame("Button", Minimap_.NAME, nil)
    button:SetParent(m)
    button:SetSize(Minimap_.SIZE, Minimap_.SIZE)
    button:SetFrameStrata("MEDIUM")
    button:SetFrameLevel(Minimap_.LEVEL)
    button:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    button:RegisterForDrag("LeftButton")
    button:SetHighlightTexture(HIGHLIGHT)
    button.dragged, button.dragging, button.dragAngle = false, false, nil

    local bg = texture("BACKGROUND", BACKGROUND, 24, 24)
    bg:SetPoint("CENTER", button, "CENTER", 0, 1)
    local icon = texture("ARTWORK", Minimap_.iconPath(), 20, 20)
    if not pcall(icon.SetTexture, icon, Minimap_.iconPath()) then icon:SetTexture(Minimap_.ICON_FALLBACK) end
    icon:SetPoint("CENTER", button, "CENTER", 0, 1)
    local border = texture("OVERLAY", BORDER, 50, 50)
    border:SetPoint("TOPLEFT", button, "TOPLEFT", 0, 0)

    -- The release that ends a drag still fires OnClick: ignored while `dragged`.
    button:SetScript("OnMouseDown", function(self) self.dragged = false end)
    button:SetScript("OnClick", function(self, which)
        if self.dragged == true then return end
        if which == "RightButton" then ns.Main.toggleLock() else ns.Options.toggle() end
    end)
    button:SetScript("OnDragStart", function(self)
        self.dragged, self.dragging, self.dragAngle = true, true, nil
        hideTooltip()
        self:SetScript("OnUpdate", onUpdate)
    end)
    button:SetScript("OnDragStop", stopDrag)
    button:SetScript("OnHide", stopDrag)
    button:SetScript("OnEnter", showTooltip)
    button:SetScript("OnLeave", hideTooltip)
    Minimap_.button = button
    return button
end

-- Shows or hides the button as saved, making it on its first show.
function Minimap_.apply()
    if settings().minimap.hide then
        if button then button:Hide() end
        return
    end
    if not Minimap_.create() then return end
    place(settings().minimap.angle)
    button:Show()
end

return Minimap_
