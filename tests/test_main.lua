-- The whole addon in the fake environment, with a scripted threat situation.
local H = ...
local W = dofile("tests/fakewow.lua")

-- world: { combat, target, status, lead, members = { unit = { name, tanking, scaled, secret } } }
local function boot(world, opts)
    local T = W.boot(H, opts)
    local env = T.env
    env._G = env
    local SECRET = setmetatable({}, { __tostring = function() error("secret read") end })
    env.issecretvalue = function(v) return v == SECRET end
    env.UnitAffectingCombat = function(u) return u == "player" and world.combat end
    env.UnitExists = function(u)
        if u == "target" then return world.target end
        return world.members[u] ~= nil
    end
    env.UnitCanAttack = function(_, u) return u == "target" end
    env.UnitIsDead = function() return false end
    env.UnitIsUnit = function(a, b) return a == b end
    env.IsInRaid = function() return false end
    env.IsInGroup = function() return next(world.members) ~= nil end
    env.UnitName = function(u) return world.members[u] and world.members[u].name end
    env.UnitThreatSituation = function(_, mob) if mob == "target" then return world.status end end
    env.UnitThreatLeadSituation = function() return world.lead end
    env.UnitDetailedThreatSituation = function(u)
        local m = world.members[u]
        if not m then return nil end
        if m.secret then return SECRET, 0, SECRET, SECRET, SECRET end
        return m.tanking or false, 0, m.scaled, 0, 0
    end
    env.SOUNDKIT = { RAID_WARNING = 8959, ALARM_CLOCK_WARNING_3 = 12889 }
    T.sounds = {}
    env.PlaySound = function(id) T.sounds[#T.sounds + 1] = id end
    env.GameFontNormalHuge = {}
    return T
end

local function alertText(T) return rawget(T.ns.UI.alertText, "text") end

H.test("loads, repairs saved data in place and stays silent at login", function()
    local T = boot({ members = {} })
    local saved = { settings = { warnPct = "x" }, keep = 1 }
    T.env.ThreatHelperForeverDB = saved
    T.fire("ADDON_LOADED", "Other")
    H.falsy(T.ns.Main.ready)
    T.fire("ADDON_LOADED", H.ADDON)
    H.truthy(T.ns.Main.ready)
    H.truthy(T.env.ThreatHelperForeverDB == saved)
    H.eq(saved.settings.warnPct, 75)
    H.eq(saved.keep, 1)
    H.eq(#T.chat, 0)
    H.falsy(T.ns.UI.frame.shown)            -- locked and out of combat: hidden
end)

H.test("templated frames are created with a nil parent, then moved under UIParent", function()
    local T = boot({ members = {} })
    local created = {}
    local create = T.env.CreateFrame
    T.env.CreateFrame = function(kind, name, parent, template)
        created[#created + 1] = { template = template, parent = parent }
        return create(kind, name, parent, template)
    end
    T.fire("ADDON_LOADED", H.ADDON)
    local templated = 0
    for _, c in ipairs(created) do
        if c.template then
            templated = templated + 1
            H.eq(c.parent, nil)
        end
    end
    H.eq(templated, 0)
    H.eq(T.ns.UI.frame.parent.name, "UIParent")
end)

H.test("a party member climbing on threat raises warn, danger, then lost, with sound", function()
    local world = { combat = true, target = true, status = 3, members = { party1 = { name = "Bob", scaled = 50 } } }
    local T = boot(world, { locale = "frFR" })
    T.fire("ADDON_LOADED", H.ADDON)
    H.eq(T.ns.Main.last.level, "safe")
    H.truthy(T.ns.UI.frame.shown)
    H.eq(rawget(T.ns.UI.who, "text"), "Bob")
    H.eq(rawget(T.ns.UI.pct, "text"), "50%")

    world.members.party1.scaled = 80
    T.clock = T.clock + 1
    T.fire("UNIT_THREAT_LIST_UPDATE", "target")
    T.fire("UNIT_THREAT_LIST_UPDATE", "target")
    H.eq(#T.timers, 1)                      -- the burst is coalesced
    T.run()
    H.eq(T.ns.Main.last.level, "warn")
    H.eq(alertText(T), "Bob se rapproche : ton aggro à 20 %")
    H.eq(T.sounds, { 12889 })

    world.members.party1.scaled = 95
    T.clock = T.clock + 1
    T.fire("UNIT_THREAT_SITUATION_UPDATE", "player"); T.run()
    H.eq(alertText(T), "DANGER : Bob, ton aggro à 5 % !")

    world.status = 1
    world.members.party1.tanking = true
    T.clock = T.clock + 1
    T.fire("UNIT_THREAT_LIST_UPDATE", "target"); T.run()
    H.eq(alertText(T), "AGGRO PERDUE sur Bob : PROVOCATION !")
    H.eq(T.sounds, { 12889, 8959, 8959 })
end)

H.test("secret member values never raise and fall back on the states", function()
    local world = { combat = true, target = true, status = 2, members = { party1 = { name = "Bob", secret = true } } }
    local T = boot(world)
    T.fire("ADDON_LOADED", H.ADDON)
    H.eq(T.ns.Main.last.level, "danger")
    H.eq(alertText(T), "DANGER: aggro slipping!")
end)

H.test("missing threat functions give 'unknown', not an error", function()
    local T = boot({ combat = true, target = true, members = {} })
    T.env.UnitThreatSituation = nil
    T.env.UnitThreatLeadSituation = nil
    T.fire("ADDON_LOADED", H.ADDON)
    H.eq(T.ns.Main.last.level, "unknown")
end)

H.test("the combat ticker runs only in combat", function()
    local T = boot({ combat = true, target = true, status = 3, members = {} })
    T.fire("ADDON_LOADED", H.ADDON)
    T.fire("PLAYER_REGEN_DISABLED")
    H.truthy(T.ns.Main.ticker)
    T.fire("PLAYER_REGEN_ENABLED")
    H.falsy(T.ns.Main.ticker)
end)

H.test("slash command: thresholds are checked, reset restores defaults, help otherwise", function()
    local T = boot({ members = {} })
    T.fire("ADDON_LOADED", H.ADDON)
    local s = T.env.ThreatHelperForeverDB.settings
    T.env.SlashCmdList.THREATHELPERFOREVER("warn 40")
    H.eq(s.warnPct, 60)
    T.env.SlashCmdList.THREATHELPERFOREVER("danger 50")
    H.eq(s.dangerPct, 90)
    T.env.SlashCmdList.THREATHELPERFOREVER("unlock")
    H.falsy(s.locked)
    H.truthy(T.ns.UI.frame.shown)
    T.env.SlashCmdList.THREATHELPERFOREVER("reset")
    H.eq(s.warnPct, 75)
    H.truthy(s.locked)
    T.env.SlashCmdList.THREATHELPERFOREVER("probe")
    T.env.SlashCmdList.THREATHELPERFOREVER("test"); T.run()
    T.env.SlashCmdList.THREATHELPERFOREVER("help")
    H.truthy(T.chat[#T.chat]:find("/aggro", 1, true))
end)

H.test("plate target: a discreet percentage follows the target's nameplate, hidden without one", function()
    local world = { combat = true, target = true, status = 3, members = { party1 = { name = "Bob", scaled = 82 } } }
    local T = boot(world)
    local plateFrame = W.frame("Frame", nil, nil)
    plateFrame.UnitFrame = W.frame("Frame", nil, plateFrame)
    local levelBox = W.frame("Frame", nil, plateFrame.UnitFrame)
    plateFrame.UnitFrame.PlayerLevelDiffFrame = levelBox
    local shownPlate = plateFrame
    T.env.C_NamePlate = { GetNamePlateForUnit = function() return shownPlate end }
    T.env.ThreatHelperForeverDB = { settings = { plateAll = false } }
    T.fire("ADDON_LOADED", H.ADDON)
    local plate = T.ns.UI.plates[1].frame
    H.truthy(plate.shown)
    H.eq(rawget(T.ns.UI.plates[1].text, "text"), "18%")
    H.eq(plate.points[1], { "LEFT", levelBox, "RIGHT", 6, 0 })
    levelBox.shown = false                      -- no level box: right of the plate's frame
    T.fire("NAME_PLATE_UNIT_ADDED", "nameplate1"); T.run()
    H.truthy(plate.points[1][2] == plateFrame.UnitFrame)
    H.eq(plate.parent.name, "UIParent")         -- anchored only, never parented to the plate
    shownPlate = nil
    T.fire("NAME_PLATE_UNIT_REMOVED", "nameplate1"); T.run()
    H.falsy(plate.shown)
    shownPlate = plateFrame
    T.env.SlashCmdList.THREATHELPERFOREVER("plate x 12")
    H.eq(plate.points[1][4], 12)
    T.env.SlashCmdList.THREATHELPERFOREVER("plate off")
    H.falsy(plate.shown)
end)

H.test("with the nameplate atlases known, the bar is drawn from them and cropped, not squeezed", function()
    local world = { combat = true, target = true, status = 3, members = { party1 = { name = "Bob", scaled = 50 } } }
    local atlases = {}
    for _, name in pairs({ "UI-HUD-CoolDownManager-Bar", "UI-HUD-CoolDownManager-Bar-BG", "UI-HUD-CoolDownManager-Selected-yellow" }) do
        atlases[name] = { width = 10, height = 10 }
    end
    local T = boot(world, { atlases = atlases })
    T.fire("ADDON_LOADED", H.ADDON)
    local fill = T.ns.UI.fill
    H.truthy(fill.isAtlas)
    H.eq(fill.width, T.ns.UI.BAR_WIDTH * 0.5)
    H.falsy(T.ns.UI.border.shown)               -- border only from "warn" up
end)

H.test("plate all: one percentage per mob in combat with the player, each with its own level", function()
    local world = { combat = true, target = true, status = 3, members = {} }
    local T = boot(world)
    local env = T.env
    -- Three nameplates: two mobs on the player's threat list, one never touched (nil status).
    local mobs = {
        nameplate1 = { status = 3, pctLead = 200 },        -- safe: second at 45 %
        nameplate2 = { status = 3, pctLead = 105 },        -- warn: second at 87 %
        nameplate3 = nil,
    }
    local frames = {}
    for unit in pairs({ nameplate1 = 1, nameplate2 = 1, nameplate3 = 1 }) do frames[unit] = W.frame("Frame") end
    env.C_NamePlate = { GetNamePlateForUnit = function(u) return frames[u] end }
    env.UnitExists = function(u) return u == "target" or frames[u] ~= nil end
    env.UnitCanAttack = function(_, u) return u == "target" or frames[u] ~= nil end
    env.UnitThreatSituation = function(_, mob)
        if mob == "target" then return world.status end
        return mobs[mob] and mobs[mob].status
    end
    env.UnitThreatPercentageOfLead = function(_, mob) return mobs[mob] and mobs[mob].pctLead end
    T.fire("ADDON_LOADED", H.ADDON)
    local texts = {}
    for _, p in ipairs(T.ns.UI.plates) do
        if p.frame.shown then texts[#texts + 1] = rawget(p.text, "text") end
    end
    table.sort(texts)
    H.eq(texts, { "13%", "55%" })
    -- Out of combat every percentage goes away.
    world.combat = false
    T.ns.Main.update()
    for _, p in ipairs(T.ns.UI.plates) do H.falsy(p.frame.shown) end
end)

H.test("/aggro test shows every level on the nameplates on screen, then gives the display back", function()
    local world = { combat = false, members = {} }
    local T = boot(world)
    local frames = {}
    for i = 1, 5 do frames["nameplate" .. i] = W.frame("Frame") end
    T.env.C_NamePlate = { GetNamePlateForUnit = function(u) return frames[u] end }
    T.env.UnitExists = function(u) return frames[u] ~= nil end
    T.fire("ADDON_LOADED", H.ADDON)
    T.env.SlashCmdList.THREATHELPERFOREVER("test")
    local texts = {}
    for i = 1, 5 do texts[i] = rawget(T.ns.UI.plates[i].text, "text") end
    H.eq(texts, { "58%", "22%", "7%", "0%", "58%" })
    H.truthy(T.ns.UI.frame.shown)
    T.fire("UNIT_THREAT_LIST_UPDATE", "target")
    while #T.timers > 0 do                          -- updates wait while the test runs
        local fn = table.remove(T.timers, 1)
        if #T.timers == 0 then T.clock = T.clock + T.ns.Main.DEMO_SECONDS end
        fn()
    end
    H.falsy(T.ns.Main.demoUntil)
    for i = 1, 5 do H.falsy(T.ns.UI.plates[i].frame.shown) end
    H.falsy(T.ns.UI.frame.shown)                    -- out of combat and locked: hidden again
end)

H.test("mob list: mobs in combat with the player, sorted by danger, packed, no secure frame", function()
    local world = { combat = true, target = true, status = 3, members = {} }
    local T = boot(world)
    local env = T.env
    -- nameplate4: hold 55 % (pctLead 200); nameplate1: hold 13 % (pctLead 105);
    -- nameplate2: friendly; nameplate3: hostile but not on the player's list.
    local mobs = {
        nameplate1 = { name = "Wrangler", status = 3, pctLead = 105 },
        nameplate3 = { name = "Far away" },
        nameplate4 = { name = "Stormer", status = 3, pctLead = 200 },
    }
    env.UnitExists = function(u) return u == "target" or u == "nameplate2" or mobs[u] ~= nil end
    env.UnitCanAttack = function(_, u) return u == "target" or mobs[u] ~= nil end
    env.UnitName = function(u) return mobs[u] and mobs[u].name end
    env.UnitIsUnit = function(a, b) return a == b or (a == "nameplate4" and b == "target") end
    env.UnitThreatSituation = function(_, mob)
        if mob == "target" then return world.status end
        return mobs[mob] and mobs[mob].status
    end
    env.UnitThreatPercentageOfLead = function(_, mob) return mobs[mob] and mobs[mob].pctLead end
    local templates = {}
    local create = env.CreateFrame
    env.CreateFrame = function(kind, name, parent, template)
        if template then templates[#templates + 1] = template end
        return create(kind, name, parent, template)
    end
    T.fire("ADDON_LOADED", H.ADDON)
    H.eq(templates, {})
    local rows = T.ns.List.rows
    H.eq(rawget(rows[1].name, "text"), "Wrangler")      -- the one about to go comes first
    H.eq(rawget(rows[1].pct, "text"), "13%")
    H.eq(rawget(rows[2].name, "text"), "Stormer")
    H.eq(rawget(rows[2].pct, "text"), "55%")
    H.truthy(rows[2].border.shown)                       -- the current target
    H.falsy(rows[3].face.shown)
    H.truthy(T.ns.List.frame.shown)
    -- Out of combat, locked: the list goes away.
    world.combat = false
    T.ns.Main.update()
    H.falsy(T.ns.List.frame.shown)
end)

H.test("mob list: /aggro unlock out of combat shows it, draggable; lock hides it again", function()
    local T = boot({ combat = false, members = {} })
    T.env.InCombatLockdown = function() return false end
    T.fire("ADDON_LOADED", H.ADDON)
    local list = T.ns.List.frame
    H.falsy(list.shown)
    T.env.SlashCmdList.THREATHELPERFOREVER("unlock")
    H.truthy(list.shown)
    H.truthy(T.ns.List.handle.shown)
    T.env.SlashCmdList.THREATHELPERFOREVER("lock")
    H.falsy(list.shown)
end)

H.test("diagnostic lines are kept in the saved log, capped", function()
    local T = boot({ combat = false, members = {} })
    T.fire("ADDON_LOADED", H.ADDON)
    T.env.SlashCmdList.THREATHELPERFOREVER("debug on")
    T.env.SlashCmdList.THREATHELPERFOREVER("probe")
    local trace = T.env.ThreatHelperForeverLog.trace
    H.truthy(#trace > 5)
    H.truthy(trace[1]:find("debug on", 1, true))
    for _ = 1, 400 do T.ns.Main.trace("x") end
    H.eq(#trace, T.ns.Main.TRACE_MAX)
end)

-- Settings window and minimap button -------------------------------------------------

local function bootWithMinimap(world)
    local T = boot(world or { combat = false, members = {} })
    T.env.Minimap = W.frame("Frame", "Minimap")
    T.env.GetFileIDFromPath = function() return 132341 end
    return T
end

H.test("the minimap button is made under the minimap, nil parent first, and can be hidden", function()
    local T = bootWithMinimap()
    local parents = {}
    local create = T.env.CreateFrame
    T.env.CreateFrame = function(kind, name, parent, template)
        if name == "ThreatHelperForeverMinimapButton" then parents[#parents + 1] = parent or false end
        return create(kind, name, parent, template)
    end
    T.fire("ADDON_LOADED", H.ADDON)
    local b = T.ns.Minimap.button
    H.truthy(b)
    H.eq(parents, { false })
    H.eq(b.parent.name, "Minimap")
    H.truthy(b.shown)
    T.env.SlashCmdList.THREATHELPERFOREVER("minimap")
    H.falsy(b.shown)
    H.truthy(T.env.ThreatHelperForeverDB.settings.minimap.hide)
end)

H.test("minimap clicks: left opens the settings, right toggles the lock; a drag is not a click", function()
    local T = bootWithMinimap()
    T.fire("ADDON_LOADED", H.ADDON)
    local b = T.ns.Minimap.button
    local click = rawget(b, "scripts").OnClick
    click(b, "LeftButton")
    H.truthy(T.ns.Options.frame.shown)
    click(b, "RightButton")
    H.falsy(T.env.ThreatHelperForeverDB.settings.locked)
    b.dragged = true
    click(b, "RightButton")
    H.falsy(T.env.ThreatHelperForeverDB.settings.locked)    -- the release of a drag changes nothing
end)

H.test("button placement follows the angle, round and square minimaps", function()
    local T = bootWithMinimap()
    local M = T.ns.Minimap
    local x, y = M.offset(0, 75, false)
    H.eq({ math.floor(x + 0.5), math.floor(y + 0.5) }, { 75, 0 })
    x, y = M.offset(45, 75, true)
    H.eq({ math.floor(x + 0.5), math.floor(y + 0.5) }, { 68, 68 })   -- a corner, 10 px in
    H.eq(M.angleFromCursor(10, 0, 0, 0), 0)
    H.eq(M.angleFromCursor(0, 10, 0, 0), 90)
    H.eq(M.angleFromCursor(0 / 1, math.huge, 0, 0), nil)
end)

H.test("settings window: built on first open, controls write the settings and apply them", function()
    local T = bootWithMinimap({ combat = true, target = true, status = 3, members = {} })
    T.fire("ADDON_LOADED", H.ADDON)
    H.falsy(T.ns.Options.frame)                     -- nothing built at login
    T.env.SlashCmdList.THREATHELPERFOREVER("")
    local O = T.ns.Options
    H.truthy(O.frame.shown)
    H.truthy(T.env.UISpecialFrames[1] == "ThreatHelperForeverOptions")
    local s = T.env.ThreatHelperForeverDB.settings
    -- Thresholds move by 5 and keep danger under warning.
    H.truthy(O.stepThreshold("warnPct", -5))
    H.eq(O.holdOf("warnPct"), 20)
    H.falsy(O.stepThreshold("dangerPct", 10))       -- 20 would reach the warning
    H.eq(O.holdOf("dangerPct"), 10)
    -- A colour swatch changes the palette every frame reads.
    s.colors.safe = { 0.2, 0.6, 1 }
    T.ns.Main.applySettings()
    H.eq(T.ns.UI.COLORS.safe, { 0.2, 0.6, 1 })
    -- Reset restores the defaults.
    T.ns.Main.resetSettings()
    H.eq(s.colors.safe, { 0.15, 0.8, 0.15 })
    H.eq(O.holdOf("warnPct"), 25)
end)

H.test("centre alerts can be switched off, the sound stays", function()
    local world = { combat = true, target = true, status = 3, members = { party1 = { name = "Bob", scaled = 50 } } }
    local T = boot(world)
    T.fire("ADDON_LOADED", H.ADDON)
    T.env.ThreatHelperForeverDB.settings.alerts = false
    world.members.party1.scaled = 95
    T.clock = T.clock + 1
    T.ns.Main.update()
    H.eq(rawget(T.ns.UI.alertText, "text"), nil)
    H.eq(#T.sounds, 1)
end)
