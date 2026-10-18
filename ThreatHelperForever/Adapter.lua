-- Game reads for the threat snapshot (Threat.lua decides). Every call is guarded: a missing
-- function, an error or a secret value gives nil, never a raise and never a fake zero.
--
-- Forever source (wow-ui-source branch forever, UnitDocumentation.lua, read 2026-10-17):
-- UnitThreatSituation / UnitThreatLeadSituation are "SecretWhenUnitThreatStateRestricted",
-- generally not secret for the player or an ally against a target, nameplate or boss.
-- UnitDetailedThreatSituation is "SecretWhenUnitThreatValuesRestricted": generally not
-- secret against a non-boss target, so on a boss the values may be secret and we fall back
-- on the states. To confirm in game with /aggro probe.
local _, ns = ...

local Adapter = {}
ns.Adapter = Adapter

local function isSecret(v)
    if issecretvalue == nil then return false end
    local ok, secret = pcall(issecretvalue, v)
    return not ok or secret == true
end
Adapter.isSecret = isSecret

-- Calls a global function by name under pcall; nil when it does not exist or fails.
local function call(name, ...)
    local fn = _G[name]
    if type(fn) ~= "function" then return nil end
    local res = { pcall(fn, ...) }
    if not res[1] then return nil end
    return unpack(res, 2, 5)
end
Adapter.call = call

local function num(v)
    if type(v) ~= "number" or isSecret(v) then return nil end
    return v
end

local function bool(v)
    if v == nil or isSecret(v) then return nil end
    return v and true or false
end

local function text(v)
    if type(v) ~= "string" or isSecret(v) then return nil end
    local ok, copy = pcall(function() return v .. "" end)
    return ok and copy ~= "" and copy or nil
end

Adapter.num, Adapter.bool, Adapter.text = num, bool, text

-- Group members and their pets, the player excluded.
function Adapter.groupUnits()
    local units = { "pet" }
    if bool(call("IsInRaid")) then
        for i = 1, 40 do
            units[#units + 1] = "raid" .. i
            units[#units + 1] = "raidpet" .. i
        end
    elseif bool(call("IsInGroup")) then
        for i = 1, 4 do
            units[#units + 1] = "party" .. i
            units[#units + 1] = "partypet" .. i
        end
    end
    return units
end

local function hostileTarget(unit)
    return bool(call("UnitExists", unit)) and bool(call("UnitCanAttack", "player", unit))
        and not bool(call("UnitIsDead", unit))
end

-- Threat snapshot against one mob unit ("target", "nameplate3"...), the player assumed in
-- combat with it. Group members are read unless `withMembers` is false (raids, all plates).
function Adapter.readMob(mob, withMembers)
    local snap = { others = {}, active = true }
    snap.status = num(call("UnitThreatSituation", "player", mob))
    snap.lead = num(call("UnitThreatLeadSituation", "player", mob))
    snap.pctLead = num(call("UnitThreatPercentageOfLead", "player", mob))
    local _, _, myScaled = call("UnitDetailedThreatSituation", "player", mob)
    snap.me = { scaled = num(myScaled) }
    -- Who the mob is hitting, grouped or not (2026-10-17: aggro was taken by a player
    -- outside the group, invisible through party units).
    local mobTarget = mob .. "target"
    if bool(call("UnitExists", mobTarget)) and not bool(call("UnitIsUnit", mobTarget, "player")) then
        snap.mobTarget = text((call("UnitName", mobTarget)))
    end
    if withMembers == false then return snap end

    for _, unit in ipairs(Adapter.groupUnits()) do
        if bool(call("UnitExists", unit)) and not bool(call("UnitIsUnit", unit, "player")) then
            local tanking, _, scaled = call("UnitDetailedThreatSituation", unit, mob)
            -- isSecret first: even comparing a secret with nil may raise.
            if isSecret(tanking) or isSecret(scaled) or tanking ~= nil or scaled ~= nil then
                snap.others[#snap.others + 1] = {
                    name = text((call("UnitName", unit))),
                    tanking = bool(tanking) or false,
                    scaled = num(scaled),
                }
            end
        end
    end
    return snap
end

function Adapter.read()
    local inCombat = bool(call("UnitAffectingCombat", "player"))
    if not (inCombat and hostileTarget("target")) then return { others = {}, active = false } end
    local snap = Adapter.readMob("target", true)

    -- Enemies whose threat list holds the player but who are not on the player.
    local loose = 0
    for i = 1, 40 do
        local unit = "nameplate" .. i
        if hostileTarget(unit) and not bool(call("UnitIsUnit", unit, "target")) then
            local st = num(call("UnitThreatSituation", "player", unit))
            if st == 0 or st == 1 then loose = loose + 1 end
        end
    end
    snap.looseMobs = loose
    return snap
end

local function plateFor(unit)
    if type(C_NamePlate) ~= "table" or type(C_NamePlate.GetNamePlateForUnit) ~= "function" then return nil end
    local ok, plate = pcall(C_NamePlate.GetNamePlateForUnit, unit)
    if not ok or type(plate) ~= "table" or isSecret(plate) then return nil end
    return plate
end

-- The list rows (List.lua): every living hostile nameplate whose threat list holds the
-- player, in combat: an array of { unit, name, isTarget, snap }.
function Adapter.listRows()
    local rows = {}
    if not bool(call("UnitAffectingCombat", "player")) then return rows end
    local withMembers = not bool(call("IsInRaid"))
    for i = 1, 40 do
        local unit = "nameplate" .. i
        if hostileTarget(unit) and num(call("UnitThreatSituation", "player", unit)) ~= nil then
            rows[#rows + 1] = {
                unit = unit,
                name = text((call("UnitName", unit))),
                isTarget = bool(call("UnitIsUnit", unit, "target")) == true,
                snap = Adapter.readMob(unit, withMembers),
            }
        end
    end
    return rows
end

-- Every nameplate on screen, in or out of combat (for /aggro test): { { unit, plate }, ... }.
function Adapter.visiblePlates()
    local list = {}
    for i = 1, 40 do
        local unit = "nameplate" .. i
        if bool(call("UnitExists", unit)) then
            local plate = plateFor(unit)
            if plate then list[#list + 1] = { unit = unit, plate = plate } end
        end
    end
    return list
end

-- Every shown enemy nameplate whose threat list holds the player, while in combat:
-- { { unit, plate, snap }, ... }. Members are read only outside raids (5 x 40 calls).
function Adapter.plates()
    local list = {}
    if not bool(call("UnitAffectingCombat", "player")) then return list end
    local withMembers = not bool(call("IsInRaid"))
    for i = 1, 40 do
        local unit = "nameplate" .. i
        if hostileTarget(unit) and num(call("UnitThreatSituation", "player", unit)) ~= nil then
            local plate = plateFor(unit)
            if plate then
                list[#list + 1] = { unit = unit, plate = plate, snap = Adapter.readMob(unit, withMembers) }
            end
        end
    end
    return list
end

-- The target's nameplate frame, or nil (no plate shown, or a forbidden one).
function Adapter.targetPlate()
    return plateFor("target")
end

-- Raw reads against the target for the fight journal (Log.lua): every value encoded,
-- secrets as "SECRET", missing functions as "MISSING". rawThreat is left out (it changes
-- on every hit and would fill the journal).
function Adapter.rawSample()
    local enc = ns.Log.encode
    local function read(name, ...)
        if type(_G[name]) ~= "function" then return { "MISSING" } end
        local res = { pcall(_G[name], ...) }
        if not res[1] then return { "ERR" } end
        return res
    end
    local function threatOf(unit)
        local res = read("UnitDetailedThreatSituation", unit, "target")
        if res[1] == "MISSING" or res[1] == "ERR" then return res[1] end
        -- isSecret first: even comparing a secret with nil may raise.
        if not isSecret(res[2]) and not isSecret(res[4]) and res[2] == nil and res[4] == nil then return "none" end
        return { tank = enc(res[2], isSecret), st = enc(res[3], isSecret),
            scaled = enc(res[4], isSecret, 1), raw = enc(res[5], isSecret, 1) }
    end
    local function one(name, ...)
        local res = read(name, ...)
        if res[1] == "MISSING" or res[1] == "ERR" then return res[1] end
        return enc(res[2], isSecret)
    end
    local sample = {
        status = one("UnitThreatSituation", "player", "target"),
        lead = one("UnitThreatLeadSituation", "player", "target"),
        pctLead = (function()
            local res = read("UnitThreatPercentageOfLead", "player", "target")
            if res[1] == "MISSING" or res[1] == "ERR" then return res[1] end
            return enc(res[2], isSecret, 1)
        end)(),
        me = threatOf("player"),
        members = {},
    }
    for _, unit in ipairs(Adapter.groupUnits()) do
        if bool(call("UnitExists", unit)) then sample.members[unit] = threatOf(unit) end
    end
    return sample
end

-- What the journal keeps about the fight itself, read once at its start.
function Adapter.fightInfo()
    local enc = ns.Log.encode
    local version, build, _, toc = call("GetBuildInfo")
    local inInstance, instanceType = call("IsInInstance")
    return {
        build = tostring(text(version) or "?") .. "." .. tostring(text(build) or "?"),
        toc = num(toc),
        classification = text((call("UnitClassification", "target"))),
        targetLevel = enc((call("UnitLevel", "target")), isSecret),
        raid = bool(call("IsInRaid")) or false,
        group = bool(call("IsInGroup")) or false,
        instance = bool(inInstance) or false,
        instanceType = text(instanceType),
    }
end

-- One line per raw read against the target, for /aggro probe: type, value or <SECRET>.
function Adapter.probe()
    local lines = {}
    local function show(label, ...)
        local parts = {}
        local n = select("#", ...)
        if n == 0 then parts[1] = "<nothing>" end
        for i = 1, n do
            local v = select(i, ...)
            if isSecret(v) then parts[#parts + 1] = "<SECRET>"
            else parts[#parts + 1] = type(v) .. ":" .. tostring(v) end
        end
        lines[#lines + 1] = label .. " = " .. table.concat(parts, ", ")
    end
    local function probeCall(name, ...)
        if type(_G[name]) ~= "function" then
            lines[#lines + 1] = name .. " = MISSING"
            return
        end
        local res = { pcall(_G[name], ...) }
        if not res[1] then
            lines[#lines + 1] = name .. " = ERR: " .. tostring(res[2])
            return
        end
        show(name, unpack(res, 2, 6))
    end
    probeCall("GetBuildInfo")
    probeCall("UnitThreatSituation", "player", "target")
    probeCall("UnitThreatLeadSituation", "player", "target")
    probeCall("UnitThreatPercentageOfLead", "player", "target")
    probeCall("UnitDetailedThreatSituation", "player", "target")
    probeCall("UnitDetailedThreatSituation", "pet", "target")
    probeCall("UnitDetailedThreatSituation", "party1", "target")
    probeCall("UnitClassification", "target")
    -- Mob list (List.lua): how the game evaluates the row rules, slot by slot.
    probeCall("InCombatLockdown")
    lines[#lines + 1] = "RegisterStateDriver = " .. type(_G.RegisterStateDriver)
    local function parse(cond)
        local ok, v = pcall(_G.SecureCmdOptionParse or error, cond .. " y; n")
        return ok and tostring(v) or "ERR"
    end
    lines[#lines + 1] = "secure @target exists=" .. parse("[@target,exists]") .. " harm=" .. parse("[@target,harm]")
    -- Which nameplate tokens the game uses right now (Lua), and what the secure parser sees.
    local used = {}
    for i = 1, 40 do
        local u = "nameplate" .. i
        if bool(call("UnitExists", u)) then
            used[#used + 1] = u .. "(lua=y secure=" .. parse("[@" .. u .. ",exists]") .. " harm=" .. parse("[@" .. u .. ",harm]") .. ")"
        end
    end
    lines[#lines + 1] = "plates in use: " .. (#used > 0 and table.concat(used, " ") or "none")
    if ns.List and ns.List.rows[1] then
        local states = {}
        for i, row in ipairs(ns.List.rows) do
            local ok, shown = pcall(row.face.IsShown, row.face)
            states[#states + 1] = i .. "=" .. ((ok and not isSecret(shown)) and tostring(shown) or "?")
        end
        lines[#lines + 1] = "rows shown: " .. table.concat(states, " ")
    end
    return lines
end

return Adapter
