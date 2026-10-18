-- The settings window, opened from the minimap button or /aggro. Blizzard's own panel
-- (ButtonFrameTemplate, window recipe of the wow-addon-dev skill), check boxes
-- (UICheckButtonTemplate), buttons (UIPanelButtonTemplate); a segmented choice instead of a
-- dropdown (dropdowns crash Forever) and colour swatches instead of ColorPickerFrame (never
-- open a Blizzard panel from addon code). Built on first open; every templated frame is
-- created with a nil parent then SetParent; Escape closes it (UISpecialFrames).
local _, ns = ...
local L = ns.L

local Options = {}
ns.Options = Options

Options.NAME = "ThreatHelperForeverOptions"
Options.W, Options.H = 380, 530
Options.LEVELS = { "safe", "warn", "danger", "lost" }
Options.PALETTE = {
    { 0.15, 0.8, 0.15 }, { 0.6, 1, 0.2 }, { 1, 0.82, 0 }, { 1, 0.45, 0 },
    { 1, 0.1, 0.1 }, { 0.2, 0.6, 1 }, { 0.7, 0.3, 1 }, { 0.9, 0.9, 0.9 },
}
Options.STEP = 5
Options.controls = {}

local function settings() return ns.Main.db.settings end

local function sameColor(a, b)
    if type(a) ~= "table" or type(b) ~= "table" then return false end
    for i = 1, 3 do
        if type(a[i]) ~= "number" or math.abs(a[i] - b[i]) > 0.01 then return false end
    end
    return true
end
Options.sameColor = sameColor

-- Hold thresholds as the player sees them ("warn under 25 %"), stored as the other's share.
function Options.holdOf(key) return 100 - settings()[key] end

-- Moves a hold threshold by `delta`, keeping 0 <= danger < warn <= 90. Returns true if changed.
function Options.stepThreshold(key, delta)
    local s = settings()
    local warn, danger = 100 - s.warnPct, 100 - s.dangerPct
    if key == "warnPct" then warn = warn + delta else danger = danger + delta end
    if warn > 90 or danger < 0 or danger >= warn then return false end
    s.warnPct, s.dangerPct = 100 - warn, 100 - danger
    return true
end

local function changed()
    ns.Main.applySettings()
end

-- Widgets ---------------------------------------------------------------------------

local function label(parent, text, font, x, y)
    local fs = parent:CreateFontString(nil, "OVERLAY")
    if type(_G[font]) == "table" and type(fs.SetFontObject) == "function" then fs:SetFontObject(_G[font]) end
    fs:SetPoint("TOPLEFT", parent, "TOPLEFT", x, y)
    fs:SetJustifyH("LEFT")
    fs:SetText(text)
    return fs
end

local function check(parent, text, x, y, get, set)
    local c = CreateFrame("CheckButton", nil, nil, "UICheckButtonTemplate")
    c:SetParent(parent)
    c:SetSize(24, 24)
    c:SetPoint("TOPLEFT", parent, "TOPLEFT", x, y)
    local fs = type(c.Text) == "table" and c.Text or nil
    if not fs then
        fs = c:CreateFontString(nil, "OVERLAY")
        if type(_G.GameFontHighlight) == "table" then fs:SetFontObject(_G.GameFontHighlight) end
        fs:SetPoint("LEFT", c, "RIGHT", -2, 0)
    end
    fs:SetText(text)
    fs:SetJustifyH("LEFT")
    c:SetHitRectInsets(0, -260, 0, 0)
    c:SetScript("OnClick", function(self)
        local on = self:GetChecked() and true or false
        if type(_G.PlaySound) == "function" and type(_G.SOUNDKIT) == "table" then
            local id = _G.SOUNDKIT[on and "IG_MAINMENU_OPTION_CHECKBOX_ON" or "IG_MAINMENU_OPTION_CHECKBOX_OFF"]
            if type(id) == "number" then pcall(_G.PlaySound, id) end
        end
        set(on)
        changed()
    end)
    c.refresh = function() c:SetChecked(get() and true or false) end
    Options.controls[#Options.controls + 1] = c
    return c
end

local function button(parent, text, w, x, y, onClick)
    local b = CreateFrame("Button", nil, nil, "UIPanelButtonTemplate")
    b:SetParent(parent)
    b:SetSize(w, 22)
    b:SetPoint("TOPLEFT", parent, "TOPLEFT", x, y)
    b:SetText(text)
    local fs = type(b.Text) == "table" and b.Text or b:GetFontString()
    if type(fs) == "table" then
        fs:ClearAllPoints()
        fs:SetPoint("LEFT", b, "LEFT", 6, 0)
        fs:SetPoint("RIGHT", b, "RIGHT", -6, 0)
        fs:SetWordWrap(false)
    end
    b:SetScript("OnClick", function(self) if self:IsEnabled() then onClick(self) end end)
    return b
end

-- Segmented choice (instead of a dropdown): the chosen button keeps its highlight.
local function segmented(parent, x, y, w, choices, get, set)
    local buttons = {}
    for i, choice in ipairs(choices) do
        local b = button(parent, choice.text, w, x + (i - 1) * (w + 4), y, function()
            set(choice.value)
            changed()
        end)
        b.value = choice.value
        buttons[i] = b
    end
    local holder = { refresh = function()
        for _, b in ipairs(buttons) do
            if b.value == get() then b:LockHighlight() else b:UnlockHighlight() end
        end
    end }
    Options.controls[#Options.controls + 1] = holder
    return buttons
end

local function stepper(parent, text, x, y, key)
    label(parent, text, "GameFontHighlight", x, y - 4)
    local value = label(parent, "", "GameFontNormal", x + 268, y - 4)
    local minus = button(parent, "-", 24, x + 238, y, function()
        if Options.stepThreshold(key, -Options.STEP) then changed() end
    end)
    local plus = button(parent, "+", 24, x + 306, y, function()
        if Options.stepThreshold(key, Options.STEP) then changed() end
    end)
    local holder = { refresh = function() value:SetText(string.format("%d%%", Options.holdOf(key))) end }
    Options.controls[#Options.controls + 1] = holder
    return minus, plus, value
end

-- A row of colour swatches for one threat level; the chosen one gets a gold outline.
local function swatches(parent, level, x, y)
    local row = {}
    for i, color in ipairs(Options.PALETTE) do
        local b = CreateFrame("Button", nil, nil)
        b:SetParent(parent)
        b:SetSize(20, 20)
        b:SetPoint("TOPLEFT", parent, "TOPLEFT", x + (i - 1) * 24, y)
        local outline = b:CreateTexture(nil, "BACKGROUND")
        outline:SetColorTexture(1, 0.82, 0, 1)
        outline:SetPoint("TOPLEFT", b, "TOPLEFT", -2, 2)
        outline:SetPoint("BOTTOMRIGHT", b, "BOTTOMRIGHT", 2, -2)
        local swatch = b:CreateTexture(nil, "ARTWORK")
        swatch:SetColorTexture(color[1], color[2], color[3], 1)
        swatch:SetAllPoints(b)
        b:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square", "ADD")
        b.outline, b.color = outline, color
        b:SetScript("OnClick", function()
            settings().colors[level] = { color[1], color[2], color[3] }
            changed()
        end)
        row[i] = b
    end
    local holder = { refresh = function()
        for _, b in ipairs(row) do b.outline:SetShown(sameColor(settings().colors[level], b.color)) end
    end }
    Options.controls[#Options.controls + 1] = holder
    return row
end

-- Window ----------------------------------------------------------------------------

function Options.build()
    if Options.frame then return Options.frame end
    local f = CreateFrame("Frame", Options.NAME, nil, "ButtonFrameTemplate")
    f:SetParent(UIParent)
    f:Hide()
    Options.frame = f
    f:SetSize(Options.W, Options.H)
    f:SetFrameStrata("HIGH")
    if type(f.SetToplevel) == "function" then f:SetToplevel(true) end
    f:HookScript("OnShow", function(self) self:Raise(); Options.refresh() end)
    f:HookScript("OnMouseDown", function(self) self:Raise() end)
    f:SetClampedToScreen(true)
    f:SetMovable(true)
    f:EnableMouse(true)
    f:RegisterForDrag("LeftButton")
    if type(_G.ButtonFrameTemplate_HideAttic) == "function" then pcall(_G.ButtonFrameTemplate_HideAttic, f) end
    if type(_G.ButtonFrameTemplate_HidePortrait) == "function" then pcall(_G.ButtonFrameTemplate_HidePortrait, f) end
    if type(_G.ButtonFrameTemplate_HideButtonBar) == "function" then pcall(_G.ButtonFrameTemplate_HideButtonBar, f) end
    if type(f.SetTitle) == "function" then pcall(f.SetTitle, f, L.OPTIONS_TITLE) end
    f:SetScript("OnDragStart", f.StartMoving)
    f:SetScript("OnDragStop", function(self) self:StopMovingOrSizing() end)
    f:SetPoint("CENTER", UIParent, "CENTER", 0, 40)
    if type(_G.UISpecialFrames) == "table" then table.insert(_G.UISpecialFrames, Options.NAME) end

    local s = settings
    local x = 22
    label(f, L.OPT_DISPLAY, "GameFontNormal", x, -34)
    check(f, L.OPT_LOCKED, x, -52, function() return s().locked end, function(v) s().locked = v end)
    check(f, L.OPT_SHOWN, x, -76, function() return s().shown end, function(v) s().shown = v end)
    check(f, L.OPT_LIST, x, -100, function() return s().list end, function(v) s().list = v end)
    check(f, L.OPT_MINIMAP, x, -124, function() return not s().minimap.hide end,
        function(v) s().minimap.hide = not v end)
    label(f, L.OPT_PLATES, "GameFontHighlight", x + 4, -154)
    segmented(f, x + 2, -172, 104, {
        { text = L.OPT_PLATES_ALL, value = "all" },
        { text = L.OPT_PLATES_TARGET, value = "target" },
        { text = L.OPT_PLATES_OFF, value = "off" },
    }, function()
        if not s().plate then return "off" end
        return s().plateAll and "all" or "target"
    end, function(v)
        s().plate = v ~= "off"
        if v ~= "off" then s().plateAll = v == "all" end
    end)

    label(f, L.OPT_ALERTS, "GameFontNormal", x, -208)
    check(f, L.OPT_CENTER, x, -226, function() return s().alerts end, function(v) s().alerts = v end)
    check(f, L.OPT_SOUND, x, -250, function() return s().sound end, function(v) s().sound = v end)
    check(f, L.OPT_LOG, x, -274, function() return ns.Main.log.enabled end, function(v) ns.Main.log.enabled = v end)
    stepper(f, L.OPT_WARN, x + 4, -302, "warnPct")
    stepper(f, L.OPT_DANGER, x + 4, -328, "dangerPct")

    label(f, L.OPT_COLORS, "GameFontNormal", x, -364)
    for i, level in ipairs(Options.LEVELS) do
        local y = -384 - (i - 1) * 26
        label(f, L["LEVEL_" .. level], "GameFontHighlightSmall", x + 4, y - 4)
        swatches(f, level, x + 136, y)
    end

    button(f, L.OPT_TEST, 110, x, -Options.H + 38, function()
        ns.Main.demo()
    end)
    button(f, L.OPT_RESET, 150, Options.W - 172, -Options.H + 38, function()
        ns.Main.resetSettings()
    end)
    return f
end

function Options.refresh()
    if not Options.frame then return end
    for _, c in ipairs(Options.controls) do c.refresh() end
end

function Options.toggle()
    local f = Options.build()
    f:SetShown(not f:IsShown())
end

return Options
