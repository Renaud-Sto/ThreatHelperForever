-- Pure threat logic: no WoW API. The adapter reads the game into a snapshot, this module
-- decides how close the tank is to losing aggro. Unknown values stay nil, never zero.
--
-- Snapshot fields (all optional):
--   active        true when the player is in combat with an attackable target
--   status        UnitThreatSituation("player", "target"): 0 not tanking lower, 1 not tanking
--                 higher, 2 tanking but someone is higher (insecure), 3 securely tanking
--   lead          UnitThreatLeadSituation("player", "target"): 0..3 none/yellow/orange/red,
--                 how close the second on the list is (Forever source; meaning to confirm in game)
--   pctLead       UnitThreatPercentageOfLead("player", "target"): the player's threat as a
--                 percentage of the second's; 0 when nobody else has threat
--   me            { scaled } from UnitDetailedThreatSituation("player", "target")
--   others        list of { name = string|nil, scaled = number|nil, tanking = bool }
--                 scaled = UnitDetailedThreatSituation(member, "target") scaledPercentage,
--                 the share of the threat that member needs to pull (100 = pulls)
--   looseMobs     enemies in combat with the player that are not on the player
local _, ns = ...

local Threat = {}
ns.Threat = Threat

-- Ordered levels: a higher rank is worse.
Threat.LEVELS = { "idle", "untouched", "unknown", "safe", "warn", "danger", "lost" }
Threat.RANK = {}
for i, name in ipairs(Threat.LEVELS) do Threat.RANK[name] = i end

local function worse(a, b)
    return Threat.RANK[a] >= Threat.RANK[b] and a or b
end

local function isNumber(v) return type(v) == "number" and v == v end   -- not NaN

-- The member closest to pulling: { name, scaled } or nil when nobody has a known value.
function Threat.topOther(others)
    local best
    if type(others) ~= "table" then return nil end
    for _, o in ipairs(others) do
        if type(o) == "table" and not o.tanking and isNumber(o.scaled) then
            if not best or o.scaled > best.scaled then best = { name = o.name, scaled = o.scaled } end
        end
    end
    return best
end

-- Someone else in the group holds the target.
local function otherTanking(others)
    if type(others) ~= "table" then return nil end
    for _, o in ipairs(others) do
        if type(o) == "table" and o.tanking then return o end
    end
    return nil
end

-- settings: { warnPct = 75, dangerPct = 90 }
-- Returns { level, top = { name, scaled } | nil, margin = number | nil, holder = name | nil }
function Threat.evaluate(snap, settings)
    settings = settings or {}
    local warnPct = isNumber(settings.warnPct) and settings.warnPct or 75
    local dangerPct = isNumber(settings.dangerPct) and settings.dangerPct or 90
    local result = { level = "idle" }
    if type(snap) ~= "table" or not snap.active then return result end

    local holder = otherTanking(snap.others)
    if snap.status == 0 or snap.status == 1 or (snap.status == nil and holder) then
        -- A target the player has not hit yet (own threat 0) is not a lost one: measured
        -- 2026-10-17 (build 70450), switching to a fresh mob gave status 0 and scaled 0.
        if type(snap.me) == "table" and snap.me.scaled == 0 then
            result.level = "untouched"
            return result
        end
        result.level = "lost"
        result.holder = holder and holder.name or snap.mobTarget
        return result
    end

    local level = "unknown"
    local top = Threat.topOther(snap.others)
    -- The second derived from UnitThreatPercentageOfLead, the player's threat as a share of
    -- the second's (measured 2026-10-17: 100 while insecure, 129, 184, 13900). The second
    -- pulls at 110 % in melee (130 % at range): assume melee, the earlier warning. It counts
    -- even when members have values: the second may be outside the group (2026-11-05, an
    -- escort NPC kept taking threat), so the closer of the two wins.
    if isNumber(snap.pctLead) and snap.pctLead > 0 then
        local derived = { scaled = math.min(100, 10000 / snap.pctLead / 1.1), derived = true }
        -- The best member explains the derived second when it is the same unit: equal for a
        -- melee member, 1.3 / 1.1 times lower at range (journal 2026-11-05, 5 dungeons: 637
        -- samples, member 20 vs derived 24 for a caster). Only a gap no member can explain
        -- means a unit outside the group (1 point of slack for rounding).
        if not top or derived.scaled * 1.1 / 1.3 > top.scaled + 1 then
            -- Outside the group unless a member's value is unreadable (it may be that one).
            local hidden = false
            for _, o in ipairs(type(snap.others) == "table" and snap.others or {}) do
                if type(o) == "table" and not o.tanking and not isNumber(o.scaled) then hidden = true end
            end
            derived.outside = not hidden
            top = derived
        end
    end
    -- A percentage is shown only from a real number: a member value, the derived second, or
    -- a percentage of lead of 0 (nobody else on the list). Through a nameplate token the
    -- values are secret and only the states are left (journal 2026-11-05, build 70790: 138
    -- samples, scaled and pctLead SECRET on every plate, readable through "target").
    result.measured = top ~= nil or snap.pctLead == 0
    if top then
        result.top = top
        result.margin = math.max(0, 100 - top.scaled)
        if top.scaled >= dangerPct then level = "danger"
        elseif top.scaled >= warnPct then level = "warn"
        else level = "safe" end
    elseif snap.status == 3 or snap.status == 2 then
        -- No member value (solo, or values secret on a boss): fall back on the state.
        level = "safe"
    end

    if snap.status == 2 then level = worse(level, "danger") end
    -- The lead state only when the percentage is unknown: at the pull it read 3 (red) while
    -- the percentage was 0 and nobody else had threat (measured 2026-10-17), a false alarm.
    if snap.pctLead == nil then
        if snap.lead == 3 then level = worse(level, "danger")
        elseif snap.lead == 2 then level = worse(level, "warn") end
    end

    result.level = level
    return result
end

-- The label for the closest other: its name, "not in group" for a derived second outside
-- the group, "someone" otherwise.
function Threat.who(top, L)
    if top.name then return top.name end
    return top.outside and L.OUTSIDE or L.SOMEONE
end

-- The player's hold on the mob, the number shown everywhere (renaud 2026-10-18: "100 % =
-- the aggro I have, 0 = the aggro I do not have"): 100 minus the closest other's share of
-- what pulls, 100 when nobody else has threat, 0 once lost; nil when there is nothing to show,
-- including a held mob whose values are secret (never a fake 100).
function Threat.hold(result)
    local level = result and result.level
    if level == "lost" then return 0 end
    if (level == "safe" or level == "warn" or level == "danger") and result.measured then
        local other = result.top and result.top.scaled or 0
        return math.max(0, math.min(100, 100 - other))
    end
    return nil
end

-- Last real hold seen on each mob (through "target", where the values are readable), by GUID: { [guid] = { hold, level, at } }. Plates of other mobs only get the
-- states (journal 2026-11-05), so the last number fills in for a few seconds.
Threat.MEMORY_SECONDS = 6

function Threat.remember(store, guid, result, now)
    if type(store) ~= "table" or type(guid) ~= "string" then return end
    local hold = Threat.hold(result)
    if hold == nil or result.level == "lost" then
        store[guid] = nil
        return
    end
    store[guid] = { hold = hold, level = result.level, at = now }
end

function Threat.recall(store, guid, now, maxAge)
    if type(store) ~= "table" or type(guid) ~= "string" then return nil end
    local k = store[guid]
    if not k then return nil end
    if now - k.at > (maxAge or Threat.MEMORY_SECONDS) then
        store[guid] = nil
        return nil
    end
    return k
end

-- What a plate (or a list row) shows: a percentage { kind = "pct", value, level, stale },
-- the insecure alert { kind = "alert" }, a live "held" mark { kind = "ok" }, or nil.
-- Live losses and insecure states win over a remembered number.
function Threat.plateLabel(result, known)
    local level = result and result.level
    local hold = Threat.hold(result)
    if level == "lost" then return { kind = "pct", value = 0, level = level } end
    if hold ~= nil then return { kind = "pct", value = hold, level = level } end
    if level == "danger" then return { kind = "alert", level = level } end
    if level == "safe" or level == "warn" then
        if known then return { kind = "pct", value = known.hold, level = known.level, stale = true } end
        return { kind = "ok", level = level }
    end
    return nil
end

-- Alert or not on a change of level. state = { level, at = { [level] = time } } is kept by
-- the caller. An alert fires when the level gets worse than before (warn, danger, lost),
-- at most once per `cooldown` seconds for the same level.
function Threat.shouldAlert(state, level, now, cooldown)
    cooldown = cooldown or 4
    local prev = state.level or "idle"
    state.level = level
    state.at = state.at or {}
    if level ~= "warn" and level ~= "danger" and level ~= "lost" then return false end
    if Threat.RANK[level] <= Threat.RANK[prev] then return false end
    local last = state.at[level]
    if last and now - last < cooldown then return false end
    state.at[level] = now
    return true
end

return Threat
