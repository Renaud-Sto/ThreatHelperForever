-- Entry point: saved settings, events, the update loop, alerts and the /aggro command.
-- * Saved variables are read at ADDON_LOADED for this addon only, repaired in place.
-- * Silent at login: chat only answers a player's command.
-- * Updates are coalesced (threat events fire in bursts) and a 0.5 s ticker runs in combat only.
local ADDON, ns = ...
local L = ns.L

local Main = {}
ns.Main = Main

Main.DEFAULTS = {
    settings = { shown = true, locked = true, sound = true, warnPct = 75, dangerPct = 90,
        plate = true, plateAll = true, plateDX = 6, plateDY = 0, list = true, listRows = 8,
        alerts = true, minimap = { hide = false, angle = 200 },
        colors = {
            safe = { 0.15, 0.8, 0.15 }, warn = { 1, 0.82, 0 }, danger = { 1, 0.45, 0 }, lost = { 1, 0.1, 0.1 },
        } },
}
Main.SOUNDS = { warn = "ALARM_CLOCK_WARNING_3", danger = "RAID_WARNING", lost = "RAID_WARNING" }

function Main.say(text)
    DEFAULT_CHAT_FRAME:AddMessage("|cff66ccffThreatHelper|r " .. tostring(text))
end

-- Diagnostic line: in chat and kept in ThreatHelperForeverLog.trace (last 300), so Claude can read
-- it from the SavedVariables file after a /reload instead of a screenshot.
Main.TRACE_MAX = 300
function Main.trace(text)
    Main.say(text)
    local log = Main.log
    if type(log) ~= "table" then return end
    if type(log.trace) ~= "table" then log.trace = {} end
    log.trace[#log.trace + 1] = date("%H:%M:%S") .. " " .. tostring(text)
    while #log.trace > Main.TRACE_MAX do table.remove(log.trace, 1) end
end

-- Fills missing keys of `db` from `defaults`, in place; a value of the wrong type is reset.
function Main.repair(db, defaults)
    for k, v in pairs(defaults) do
        if type(v) == "table" then
            if type(db[k]) ~= "table" then db[k] = {} end
            Main.repair(db[k], v)
        elseif type(db[k]) ~= type(v) then
            db[k] = v
        end
    end
    return db
end

function Main.init()
    if type(ThreatHelperForeverDB) ~= "table" then ThreatHelperForeverDB = {} end
    Main.db = Main.repair(ThreatHelperForeverDB, Main.DEFAULTS)
    local s = Main.db.settings
    s.plateX, s.plateY = nil, nil            -- 0.4.0 offsets, measured from the wrong anchor
    if not (s.warnPct >= 10 and s.dangerPct > s.warnPct and s.dangerPct <= 100) then
        s.warnPct, s.dangerPct = Main.DEFAULTS.settings.warnPct, Main.DEFAULTS.settings.dangerPct
    end
    if type(ThreatHelperForeverLog) ~= "table" then ThreatHelperForeverLog = {} end
    Main.log = ns.Log.repair(ThreatHelperForeverLog)
    ns.Log.endFight(Main.log, GetTime())     -- a /reload in combat leaves a fight open
    ns.Locale.select(GetLocale())
    Main.alertState = {}
    Main.applyColors()
    ns.UI.build(s)
    ns.List.build(s)
    ns.Minimap.apply()
    Main.ready = true
    Main.update()
end

-- The colours chosen in the settings window, copied into the palette every frame reads.
function Main.applyColors()
    for level, c in pairs(Main.db.settings.colors) do
        if type(c) == "table" and type(c[1]) == "number" then ns.UI.COLORS[level] = { c[1], c[2], c[3] } end
    end
end

-- After any change made in the settings window or a command.
function Main.applySettings()
    local s = Main.db.settings
    if not s.locked then s.shown = true end
    Main.applyColors()
    ns.UI.setLocked(s.locked)
    ns.List.setLocked(s.locked)
    ns.Minimap.apply()
    Main.update()
    ns.Options.refresh()
end

function Main.toggleLock()
    local s = Main.db.settings
    s.locked = not s.locked
    Main.say(s.locked and L.LOCKED or L.UNLOCKED)
    Main.applySettings()
end

function Main.resetSettings()
    local s = Main.db.settings
    for k in pairs(s) do s[k] = nil end
    Main.repair(Main.db, Main.DEFAULTS)
    ns.UI.applyPosition(s)
    ns.List.applyPosition(s)
    Main.say(L.RESET)
    Main.applySettings()
end

-- TOC AddonCompartmentFunc: the client calls it with (addonName, mouseButton).
function ThreatHelperForever_OnCompartmentClick(_, mouseButton)
    if not Main.ready then return end
    if mouseButton == "RightButton" then Main.toggleLock() else ns.Options.toggle() end
end

function Main.visible(result)
    local s = Main.db.settings
    return s.shown and (not s.locked or result.level ~= "idle")
end

function Main.alertText(result)
    local level = result.level
    local name = result.top and result.top.name or L.SOMEONE
    local pct = math.floor((ns.Threat.hold(result) or 0) + 0.5)
    if level == "warn" then return string.format(L.ALERT_warn, name, pct) end
    if level == "danger" then
        return result.top and string.format(L.ALERT_danger, name, pct) or L.ALERT_danger_nodata
    end
    if result.holder then return string.format(L.ALERT_lost_holder, result.holder) end
    return L.ALERT_lost
end

function Main.playSound(level)
    if not Main.db.settings.sound or type(SOUNDKIT) ~= "table" then return end
    local id = SOUNDKIT[Main.SOUNDS[level]]
    if type(id) == "number" and type(PlaySound) == "function" then pcall(PlaySound, id, "Master") end
end

function Main.raise(result)
    local message = Main.alertText(result)
    if Main.db.settings.alerts then ns.UI.alert(result.level, message) end
    if Main.log then ns.Log.note(Main.log, GetTime(), "alert", result.level .. ": " .. message) end
    Main.playSound(result.level)
end

function Main.update()
    if not Main.ready then return end
    -- A running /aggro test owns the display until it ends.
    if Main.demoUntil and GetTime() < Main.demoUntil then return end
    Main.demoUntil = nil
    local snap = ns.Adapter.read()
    local result = ns.Threat.evaluate(snap, Main.db.settings)
    Main.last = result
    ns.UI.render(result, snap.looseMobs)
    Main.renderPlates(result, snap)
    Main.renderList()
    ns.UI.frame:SetShown(Main.visible(result))
    if ns.Threat.shouldAlert(Main.alertState, result.level, GetTime()) then Main.raise(result) end
    Main.journal(snap, result)
end

-- Fight journal (Log.lua): raw API values while in combat, only when they change.
function Main.journal(snap, result)
    local fight = Main.log.enabled and ns.Log.currentFight(Main.log)
    if not fight then return end
    if not fight.info.build and snap.active then
        for k, v in pairs(ns.Adapter.fightInfo()) do fight.info[k] = v end
    end
    local sample = ns.Adapter.rawSample()
    sample.level = result.level
    sample.top = result.top and result.top.name or nil
    sample.loose = snap.looseMobs
    ns.Log.sample(Main.log, GetTime(), sample)
end

-- One percentage per nameplate: every mob in combat with the player, or the target only.
function Main.renderPlates(result, snap)
    local s = Main.db.settings
    local entries = {}
    if s.plate and s.plateAll then
        for _, m in ipairs(ns.Adapter.plates()) do
            entries[#entries + 1] = {
                result = ns.Threat.evaluate(m.snap, s), myScaled = m.snap.me and m.snap.me.scaled, plate = m.plate,
            }
        end
    elseif s.plate then
        entries[1] = { result = result, myScaled = snap.me and snap.me.scaled, plate = ns.Adapter.targetPlate() }
    end
    ns.UI.renderPlates(entries, s)
end

function Main.renderList()
    local s = Main.db.settings
    if not ns.List.frame then return end
    local rows = s.list and ns.Adapter.listRows() or {}
    for _, row in ipairs(rows) do row.result = ns.Threat.evaluate(row.snap, s) end
    ns.List.render(ns.List.sort(rows), s)
end

-- Coalesces bursts of threat events into one update a tenth of a second later.
function Main.requestUpdate()
    if Main.pending then return end
    Main.pending = true
    C_Timer.After(0.1, function()
        Main.pending = false
        Main.update()
    end)
end

function Main.startTicker()
    if Main.ticker then return end
    Main.ticker = C_Timer.NewTicker(0.5, Main.requestUpdate)
end

function Main.stopTicker()
    if Main.ticker then Main.ticker:Cancel() end
    Main.ticker = nil
end

local UPDATE_EVENTS = {
    UNIT_THREAT_LIST_UPDATE = true, UNIT_THREAT_SITUATION_UPDATE = true,
    PLAYER_TARGET_CHANGED = true, GROUP_ROSTER_UPDATE = true,
    NAME_PLATE_UNIT_ADDED = true, NAME_PLATE_UNIT_REMOVED = true,
}

function Main.onEvent(event, arg1, arg2)
    if event == "ADDON_LOADED" then
        if arg1 == ADDON then Main.init() end
        return
    end
    -- A blocked action is the only sign of taint: report it, for this addon only.
    if event == "MACRO_ACTION_BLOCKED" or event == "MACRO_ACTION_FORBIDDEN" then
        if ns.List.debug then Main.trace(event .. ": " .. tostring(arg1) .. " " .. tostring(arg2)) end
        return
    end
    if event == "ADDON_ACTION_BLOCKED" or event == "ADDON_ACTION_FORBIDDEN" then
        if arg1 == ADDON then
            Main.trace(event .. ": " .. tostring(arg2))
            if Main.log then ns.Log.note(Main.log, GetTime(), "event", event .. ": " .. tostring(arg2)) end
        end
        return
    end
    if not Main.ready then return end
    if event == "PLAYER_REGEN_DISABLED" then
        if Main.log.enabled then
            ns.Log.startFight(Main.log, GetTime(), { when = date("%Y-%m-%d %H:%M:%S") })
        end
        Main.startTicker()
        Main.requestUpdate()
    elseif event == "PLAYER_REGEN_ENABLED" then
        Main.stopTicker()
        Main.update()
        ns.Log.endFight(Main.log, GetTime())
    elseif UPDATE_EVENTS[event] then
        Main.requestUpdate()
    end
end

-- The player types thresholds as a hold ("warn 25": warn when my hold drops under 25 %);
-- they are stored as the other's share (warnPct = 100 - 25).
local function setPct(key, value, okText)
    local s = Main.db.settings
    local n = tonumber(value)
    local stored = n and (100 - n)
    local warn = key == "warnPct" and stored or s.warnPct
    local danger = key == "dangerPct" and stored or s.dangerPct
    if not n or warn < 10 or danger <= warn or danger > 100 then
        Main.say(L.BAD_PCT)
        return
    end
    s[key] = stored
    Main.say(string.format(okText, n))
    Main.update()
end

-- /aggro test: the three alerts, a second and a half apart.
-- /aggro test: for 6 seconds, shows what losing the aggro looks like: the frame, the three
-- alerts a second and a half apart, and on every nameplate on screen one of the levels
-- (safe, warn, danger, lost in turn). Real updates wait until it ends.
Main.DEMO_SECONDS = 6
Main.DEMO_PLATES = {
    { result = { level = "safe", top = { scaled = 42 } } },
    { result = { level = "warn", top = { scaled = 78 } } },
    { result = { level = "danger", top = { scaled = 93 } } },
    { result = { level = "lost" } },
}

function Main.demo()
    local samples = {
        { level = "warn", top = { name = "Bob", scaled = 78 } },
        { level = "danger", top = { name = "Bob", scaled = 93 } },
        { level = "lost", holder = "Bob" },
    }
    Main.demoUntil = GetTime() + Main.DEMO_SECONDS
    ns.UI.render(samples[2], 1)
    ns.UI.frame:Show()
    local entries = {}
    for i, p in ipairs(ns.Adapter.visiblePlates()) do
        local d = Main.DEMO_PLATES[(i - 1) % #Main.DEMO_PLATES + 1]
        entries[i] = { result = d.result, myScaled = d.myScaled, plate = p.plate }
    end
    local s = Main.db.settings
    ns.UI.renderPlates(entries, { plate = true, plateDX = s.plateDX, plateDY = s.plateDY })
    if #entries == 0 then Main.say(L.TEST_NO_PLATES) end
    for i, result in ipairs(samples) do
        C_Timer.After((i - 1) * 1.5, function()
            ns.UI.render(result, 1)
            Main.raise(result)
        end)
    end
    C_Timer.After(Main.DEMO_SECONDS, function()
        Main.demoUntil = nil
        Main.update()
    end)
end

local function slash(msg)
    if not Main.ready then return end
    local cmd, rest = (msg or ""):match("^%s*(%S*)%s*(.-)%s*$")
    cmd = (cmd or ""):lower()
    local s = Main.db.settings
    if cmd == "show" then
        s.shown = true; Main.say(L.SHOWN); Main.update()
    elseif cmd == "hide" then
        s.shown = false; Main.say(L.HIDDEN); Main.update()
    elseif cmd == "lock" then
        s.locked = true; ns.UI.setLocked(true); ns.List.setLocked(true); Main.say(L.LOCKED)
        Main.update()
    elseif cmd == "unlock" then
        s.locked = false; s.shown = true; ns.UI.setLocked(false); ns.List.setLocked(false)
        Main.say(L.UNLOCKED)
        Main.update()
    elseif cmd == "warn" then
        setPct("warnPct", rest, L.WARN_SET)
    elseif cmd == "danger" then
        setPct("dangerPct", rest, L.DANGER_SET)
    elseif cmd == "sound" then
        s.sound = rest:lower() ~= "off"
        Main.say(s.sound and L.SOUND_ON or L.SOUND_OFF)
    elseif cmd == "log" then
        local arg = rest:lower()
        if arg == "clear" then
            Main.log.fights = {}
            Main.log.loose = nil
            ns.Log.endFight(Main.log, GetTime())
            Main.say(L.LOG_CLEARED)
        else
            Main.log.enabled = arg ~= "off"
            Main.say(string.format(Main.log.enabled and L.LOG_ON or L.LOG_OFF, #Main.log.fights))
        end
    elseif cmd == "plate" then
        local what, n = rest:lower():match("^(%S*)%s*(%S*)")
        if (what == "x" or what == "y") and tonumber(n) then
            s[what == "x" and "plateDX" or "plateDY"] = tonumber(n)
        else
            s.plate = what ~= "off"
            if what == "all" or what == "target" then s.plateAll = what == "all" end
        end
        local mode = not s.plate and L.OFF or (s.plateAll and L.PLATE_ALL or L.PLATE_TARGET)
        Main.say(string.format(L.PLATE_SET, mode, s.plateDX, s.plateDY))
        Main.update()
    elseif cmd == "list" then
        s.list = rest:lower() ~= "off"
        Main.say(s.list and L.LIST_ON or L.LIST_OFF)
        Main.update()
    elseif cmd == "debug" then
        ns.List.debug = rest:lower() ~= "off"
        Main.trace("debug " .. (ns.List.debug and "on" or "off"))
    elseif cmd == "test" then
        Main.demo()
    elseif cmd == "probe" then
        Main.trace("probe, in combat=" .. tostring(ns.List.inCombat()))
        for _, line in ipairs(ns.Adapter.probe()) do Main.trace(line) end
        Main.say(L.PROBE_DONE)
    elseif cmd == "reset" then
        Main.resetSettings()
    elseif cmd == "" or cmd == "options" or cmd == "config" then
        ns.Options.toggle()
    elseif cmd == "minimap" then
        s.minimap.hide = not s.minimap.hide
        Main.applySettings()
    else
        Main.say(L.HELP)
    end
end

SLASH_THREATHELPERFOREVER1 = "/aggro"
SLASH_THREATHELPERFOREVER2 = "/threathelper"
SlashCmdList.THREATHELPERFOREVER = slash

local frame = CreateFrame("Frame")
for _, event in ipairs({
    "ADDON_LOADED", "ADDON_ACTION_BLOCKED", "ADDON_ACTION_FORBIDDEN", "MACRO_ACTION_BLOCKED", "MACRO_ACTION_FORBIDDEN",
    "PLAYER_REGEN_DISABLED", "PLAYER_REGEN_ENABLED", "PLAYER_TARGET_CHANGED", "GROUP_ROSTER_UPDATE",
    "UNIT_THREAT_LIST_UPDATE", "UNIT_THREAT_SITUATION_UPDATE",
    "NAME_PLATE_UNIT_ADDED", "NAME_PLATE_UNIT_REMOVED",
}) do
    pcall(frame.RegisterEvent, frame, event)
end
frame:SetScript("OnEvent", function(_, event, ...) Main.onEvent(event, ...) end)
