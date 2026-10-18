-- Pure threat logic: levels, fallbacks when values are unknown, alert throttling.
local H = ...
local ns = H.newNS("Threat")
local T = ns.Threat

local function member(name, scaled, tanking) return { name = name, scaled = scaled, tanking = tanking or false } end

H.test("out of combat or without a target the level is idle", function()
    H.eq(T.evaluate(nil).level, "idle")
    H.eq(T.evaluate({ active = false, status = 3 }).level, "idle")
end)

H.test("the member closest to pulling decides safe, warn and danger", function()
    local s = { warnPct = 75, dangerPct = 90 }
    local r = T.evaluate({ active = true, status = 3, others = { member("A", 40), member("B", 60) } }, s)
    H.eq(r.level, "safe")
    H.eq(r.top, { name = "B", scaled = 60 })
    H.eq(r.margin, 40)
    H.eq(T.evaluate({ active = true, status = 3, others = { member("B", 75) } }, s).level, "warn")
    H.eq(T.evaluate({ active = true, status = 3, others = { member("B", 90) } }, s).level, "danger")
end)

H.test("losing the target is 'lost', with the new holder when known", function()
    local r = T.evaluate({ active = true, status = 1, others = { member("Mage", 100, true) } })
    H.eq(r.level, "lost")
    H.eq(r.holder, "Mage")
    H.eq(T.evaluate({ active = true, status = 0 }).level, "lost")
end)

H.test("insecure tanking (status 2) is at least danger, even with low member values", function()
    H.eq(T.evaluate({ active = true, status = 2, others = { member("B", 10) } }).level, "danger")
end)

H.test("secret or missing member values fall back on the states", function()
    H.eq(T.evaluate({ active = true, status = 3, others = { member("Helper", nil) } }).level, "safe")
    H.eq(T.evaluate({ active = true, status = 3, lead = 2 }).level, "warn")
    H.eq(T.evaluate({ active = true, status = 3, lead = 3 }).level, "danger")
    H.eq(T.evaluate({ active = true }).level, "unknown")
end)

H.test("NaN is never taken as a value", function()
    local nan = math.huge - math.huge
    H.eq(T.evaluate({ active = true, status = 3, others = { member("X", nan) } }).top, nil)
end)

H.test("alerts fire when the level gets worse, once per cooldown", function()
    local st = {}
    H.falsy(T.shouldAlert(st, "safe", 0))
    H.truthy(T.shouldAlert(st, "warn", 1))
    H.falsy(T.shouldAlert(st, "warn", 2))          -- same level
    H.truthy(T.shouldAlert(st, "danger", 3))
    H.falsy(T.shouldAlert(st, "warn", 4))          -- better
    H.falsy(T.shouldAlert(st, "safe", 5))
    H.falsy(T.shouldAlert(st, "danger", 6))        -- danger again within 4 s
    H.falsy(T.shouldAlert(st, "safe", 7))
    H.truthy(T.shouldAlert(st, "danger", 8))
    H.truthy(T.shouldAlert(st, "lost", 9))
end)

-- Rules from the fight journal of 2026-10-17 (build 1.60.1.70450).
H.test("a fresh target the player has not hit is 'untouched', not 'lost'", function()
    H.eq(T.evaluate({ active = true, status = 0, me = { scaled = 0 } }).level, "untouched")
    H.eq(T.evaluate({ active = true, status = 0, me = { scaled = 40 } }).level, "lost")
    H.eq(T.evaluate({ active = true, status = 1, me = {} }).level, "lost")
end)

H.test("without member values the second is derived from the percentage of lead", function()
    local r = T.evaluate({ active = true, status = 3, pctLead = 107 })
    H.eq(r.level, "warn")
    H.truthy(r.top.derived)
    H.eq(math.floor(r.top.scaled), 84)
    H.eq(T.evaluate({ active = true, status = 3, pctLead = 184 }).level, "safe")
    H.eq(T.evaluate({ active = true, status = 2, pctLead = 100 }).level, "danger")
    H.eq(T.evaluate({ active = true, status = 3, pctLead = 13900 }).level, "safe")
end)

H.test("the lead state is ignored when the percentage is known (red at the pull with 0 %)", function()
    H.eq(T.evaluate({ active = true, status = 3, lead = 3, pctLead = 0 }).level, "safe")
    H.eq(T.evaluate({ active = true, status = 3, lead = 3 }).level, "danger")
end)

H.test("the mob's target names the holder when nobody in the group has it", function()
    local r = T.evaluate({ active = true, status = 1, me = { scaled = 60 }, mobTarget = "Stranger" })
    H.eq(r.level, "lost")
    H.eq(r.holder, "Stranger")
end)

H.test("the number shown is the player's hold: 100 alone or safe, falling as others close in, 0 once lost", function()
    H.eq(T.hold({ level = "safe" }), 100)
    H.eq(T.hold({ level = "warn", top = { scaled = 80 } }), 20)
    H.eq(T.hold({ level = "danger", top = { scaled = 120 } }), 0)
    H.eq(T.hold({ level = "lost" }), 0)
    H.eq(T.hold({ level = "untouched" }), nil)
    H.eq(T.hold({ level = "idle" }), nil)
end)
