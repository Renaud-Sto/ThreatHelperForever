-- Locale tables (pure, no WoW API; Main passes GetLocale()). ns.L never returns nil.
local _, ns = ...

local Locale = { tables = {}, current = "enUS" }
ns.Locale = Locale

function Locale.register(code, tbl) Locale.tables[code] = tbl end

function Locale.select(code)
    if type(code) ~= "string" or not Locale.tables[code] then code = "enUS" end
    Locale.current = code
end

ns.L = setmetatable({}, { __index = function(_, key)
    local t = Locale.tables[Locale.current]
    local text = t and t[key]
    if text == nil then text = Locale.tables.enUS and Locale.tables.enUS[key] end
    return text == nil and tostring(key) or text
end })
