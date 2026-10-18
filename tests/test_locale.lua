-- Every language has the same keys, and the same format placeholders per key.
local H = ...
local ns = H.newNS("Locale", "Locales/enUS", "Locales/frFR")

local function placeholders(s)
    local out = {}
    for p in s:gmatch("%%[%d%.]*[sd%%]") do out[#out + 1] = p end
    return table.concat(out, " ")
end

H.test("frFR and enUS have the same keys and placeholders", function()
    local en, fr = ns.Locale.tables.enUS, ns.Locale.tables.frFR
    for k, v in pairs(en) do
        if fr[k] == nil then error("frFR misses " .. k) end
        if placeholders(v) ~= placeholders(fr[k]) then error("placeholders differ for " .. k) end
    end
    for k in pairs(fr) do
        if en[k] == nil then error("enUS misses " .. k) end
    end
end)

H.test("an unknown key or language never gives nil", function()
    ns.Locale.select("deDE")
    H.eq(ns.L.TITLE, "Threat")
    H.eq(ns.L.NOPE, "NOPE")
    ns.Locale.select("frFR")
    H.eq(ns.L.TITLE, "Menace")
end)
