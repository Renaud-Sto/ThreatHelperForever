-- Fight journal for in-game testing: what the threat API really returns, written to the
-- ThreatHelperForeverLog saved variable so it can be read after /reload without the player typing
-- anything. Pure: the caller passes the table, the clock and already-encoded samples.
-- Never stores a secret: the adapter encodes them as the string "SECRET".
local _, ns = ...

local Log = {}
ns.Log = Log

Log.MAX_FIGHTS = 30
Log.MAX_SAMPLES = 300

-- One value as a storable string or number: "SECRET", "nil", a number rounded to `step`
-- (default 0.1; percentages use 1 so tiny changes do not fill the journal).
function Log.encode(v, isSecret, step)
    if isSecret and isSecret(v) then return "SECRET" end
    if v == nil then return "nil" end
    if type(v) == "number" then
        if v ~= v then return "NaN" end
        step = step or 0.1
        return math.floor(v / step + 0.5) * step
    end
    if type(v) == "boolean" or type(v) == "string" then return v end
    return type(v)
end

-- db: the ThreatHelperForeverLog table, repaired in place.
function Log.repair(db)
    if type(db.fights) ~= "table" then db.fights = {} end
    -- Off by default for players (1.0.0); turned on from the settings window or /aggro log on.
    if type(db.enabled) ~= "boolean" then db.enabled = false end
    return db
end

function Log.startFight(db, now, info)
    local fight = { start = now, info = info or {}, samples = {}, alerts = {}, events = {} }
    db.fights[#db.fights + 1] = fight
    while #db.fights > Log.MAX_FIGHTS do table.remove(db.fights, 1) end
    db.current = #db.fights
    db.lastSignature = nil
    return fight
end

function Log.currentFight(db)
    return db.current and db.fights[db.current] or nil
end

function Log.endFight(db, now)
    local fight = Log.currentFight(db)
    if fight then fight.duration = now - fight.start end
    db.current = nil
    db.lastSignature = nil
end

local function signature(sample)
    local parts = {}
    local keys = {}
    for k in pairs(sample) do if k ~= "t" then keys[#keys + 1] = k end end
    table.sort(keys)
    for _, k in ipairs(keys) do
        local v = sample[k]
        if type(v) == "table" then
            parts[#parts + 1] = k .. "=" .. signature(v)
        else
            parts[#parts + 1] = k .. "=" .. tostring(v)
        end
    end
    return "{" .. table.concat(parts, ",") .. "}"
end
Log.signature = signature

-- Adds `sample` to the current fight when it differs from the previous one.
-- Returns true when stored.
function Log.sample(db, now, sample)
    local fight = Log.currentFight(db)
    if not fight or #fight.samples >= Log.MAX_SAMPLES then return false end
    local sig = signature(sample)
    if sig == db.lastSignature then return false end
    db.lastSignature = sig
    sample.t = math.floor((now - fight.start) * 10 + 0.5) / 10
    fight.samples[#fight.samples + 1] = sample
    return true
end

-- Free-form line in the current fight (alerts, blocked actions), or in db.loose outside.
function Log.note(db, now, kind, text)
    local fight = Log.currentFight(db)
    local entry = { t = fight and math.floor((now - fight.start) * 10 + 0.5) / 10 or now, text = text }
    if fight then
        local list = kind == "alert" and fight.alerts or fight.events
        if #list < Log.MAX_SAMPLES then list[#list + 1] = entry end
    else
        if type(db.loose) ~= "table" then db.loose = {} end
        db.loose[#db.loose + 1] = entry
        while #db.loose > 50 do table.remove(db.loose, 1) end
    end
end

return Log
