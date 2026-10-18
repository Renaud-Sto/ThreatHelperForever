-- Fight journal: pure module, then the whole addon writing ThreatHelperForeverLog during a fight.
local H = ...
local W = dofile("tests/fakewow.lua")
local ns = H.newNS("Log")
local Log = ns.Log

H.test("values are encoded without ever keeping a secret", function()
    local SECRET = {}
    local function isSecret(v) return v == SECRET end
    H.eq(Log.encode(SECRET, isSecret), "SECRET")
    H.eq(Log.encode(nil, isSecret), "nil")
    H.eq(Log.encode(12.345, isSecret), 12.3)
    H.eq(Log.encode(87.6, isSecret, 1), 88)
    H.eq(Log.encode(math.huge - math.huge, isSecret), "NaN")
    H.eq(Log.encode(true, isSecret), true)
end)

H.test("a fight keeps only samples that change, and old fights roll off", function()
    local db = Log.repair({})
    H.falsy(db.enabled)                              -- off by default for players
    H.falsy(Log.sample(db, 0, { status = 3 }))      -- no fight open
    Log.startFight(db, 100, { when = "x" })
    H.truthy(Log.sample(db, 100.5, { status = 3, members = { party1 = { scaled = 40 } } }))
    H.falsy(Log.sample(db, 101, { status = 3, members = { party1 = { scaled = 40 } } }))
    H.truthy(Log.sample(db, 102, { status = 3, members = { party1 = { scaled = 80 } } }))
    Log.note(db, 102, "alert", "warn: Bob")
    Log.endFight(db, 110)
    local fight = db.fights[1]
    H.eq(#fight.samples, 2)
    H.eq(fight.samples[2].t, 2)
    H.eq(fight.alerts, { { t = 2, text = "warn: Bob" } })
    H.eq(fight.duration, 10)
    for i = 1, Log.MAX_FIGHTS + 5 do Log.startFight(db, i) end
    H.eq(#db.fights, Log.MAX_FIGHTS)
end)

H.test("in game: a fight against a boss with secret values is journaled at combat end", function()
    local T = W.boot(H, { locale = "frFR" })
    local env = T.env
    env._G = env
    local SECRET = setmetatable({}, { __tostring = function() error("secret read") end })
    env.issecretvalue = function(v) return v == SECRET end
    local inCombat = false
    env.UnitAffectingCombat = function(u) return u == "player" and inCombat end
    env.UnitExists = function(u) return u == "target" or u == "party1" end
    env.UnitCanAttack = function(_, u) return u == "target" end
    env.UnitIsDead = function() return false end
    env.UnitIsUnit = function(a, b) return a == b end
    env.IsInRaid = function() return false end
    env.IsInGroup = function() return true end
    env.UnitName = function() return "Bob" end
    env.UnitClassification = function() return "worldboss" end
    env.GetBuildInfo = function() return "1.60.1", "70291", "Oct 1 2026", 16001 end
    env.UnitThreatSituation = function() return 3 end
    env.UnitDetailedThreatSituation = function(u)
        if u == "player" then return true, 3, 100, 100, 5000 end
        return SECRET, SECRET, SECRET, SECRET, SECRET
    end
    T.fire("ADDON_LOADED", H.ADDON)
    T.env.SlashCmdList.THREATHELPERFOREVER("log on")
    inCombat = true
    T.fire("PLAYER_REGEN_DISABLED"); T.run()
    T.clock = T.clock + 3
    T.fire("UNIT_THREAT_LIST_UPDATE", "target"); T.run()
    inCombat = false
    T.clock = T.clock + 2
    T.fire("PLAYER_REGEN_ENABLED")
    local log = env.ThreatHelperForeverLog
    H.eq(#log.fights, 1)
    local fight = log.fights[1]
    H.eq(fight.info.classification, "worldboss")
    H.eq(fight.info.build, "1.60.1.70291")
    H.eq(fight.duration, 5)
    local s = fight.samples[1]
    H.eq(s.status, 3)
    H.eq(s.lead, "MISSING")
    H.eq(s.me, { tank = true, st = 3, scaled = 100, raw = 100 })
    H.eq(s.members.party1, { tank = "SECRET", st = "SECRET", scaled = "SECRET", raw = "SECRET" })
    H.eq(s.level, "safe")
    H.falsy(log.current)
end)

H.test("/aggro log off stops new fights from being written", function()
    local T = W.boot(H)
    T.env._G = T.env
    T.fire("ADDON_LOADED", H.ADDON)
    T.env.SlashCmdList.THREATHELPERFOREVER("log off")
    T.fire("PLAYER_REGEN_DISABLED"); T.run()
    T.fire("PLAYER_REGEN_ENABLED")
    H.eq(#T.env.ThreatHelperForeverLog.fights, 0)
    T.env.SlashCmdList.THREATHELPERFOREVER("log on")
    H.truthy(T.env.ThreatHelperForeverLog.enabled)
end)
