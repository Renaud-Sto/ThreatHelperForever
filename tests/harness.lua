-- Template from the wow-addon-dev skill (copied from CraftProfit, MIT): a dependency-free
-- test harness for LuaJIT / Lua 5.1. Run from the project root: luajit tests/run.lua
-- H.ADDON is the addon folder (the one holding the TOC); rename it with the addon.
local H = { passed = 0, failed = 0, failures = {}, ADDON = "ThreatHelperForever" }
local currentFile = "?"

function H.setFile(name) currentFile = name end

-- `path` holds the tables being printed (ancestors only): a cycle prints <cycle>.
local function dump(v, indent, path)
    indent = indent or ""
    path = path or {}
    if type(v) == "string" then return string.format("%q", v) end
    if type(v) ~= "table" then return tostring(v) end
    if path[v] then return "<cycle>" end
    path[v] = true
    local keys = {}
    for k in pairs(v) do keys[#keys + 1] = k end
    table.sort(keys, function(a, b) return tostring(a) < tostring(b) end)
    local parts = {}
    for _, k in ipairs(keys) do
        parts[#parts + 1] = indent .. "  " .. tostring(k) .. " = " .. dump(v[k], indent .. "  ", path)
    end
    path[v] = nil
    return "{\n" .. table.concat(parts, ",\n") .. "\n" .. indent .. "}"
end
H.dump = dump

local function deepEqual(a, b, seen)
    if a == b then return true end
    if type(a) ~= type(b) or type(a) ~= "table" then return false end
    seen = seen or {}
    seen[a] = seen[a] or {}
    if seen[a][b] then return true end
    seen[a][b] = true
    for k, v in pairs(a) do
        if not deepEqual(v, b[k], seen) then return false end
    end
    for k in pairs(b) do
        if a[k] == nil then return false end
    end
    return true
end

function H.eq(actual, expected)
    if not deepEqual(actual, expected) then
        error("expected " .. dump(expected) .. "\n     got " .. dump(actual), 2)
    end
end

function H.truthy(v)
    if not v then error("expected a truthy value, got " .. dump(v), 2) end
end

function H.falsy(v)
    if v then error("expected a falsy value, got " .. dump(v), 2) end
end

-- Passes when fn() throws; returns the error message.
function H.raises(fn)
    local ok, err = pcall(fn)
    if ok then error("expected an error, but none was raised", 2) end
    return err
end

local function withTraceback(err)
    return tostring(err) .. debug.traceback("", 2)
end

function H.test(name, fn)
    local ok, err = xpcall(fn, withTraceback)
    if ok then
        H.passed = H.passed + 1
    else
        H.failed = H.failed + 1
        local msg = currentFile .. " :: " .. name .. "\n   " .. (tostring(err):gsub("\n", "\n   "))
        H.failures[#H.failures + 1] = msg
        print("FAIL " .. msg)
    end
end

-- Loads addon files (names without ".lua") in order into one fresh namespace, the way
-- WoW does it: each file receives (addonName, ns) as varargs. For pure modules.
function H.newNS(...)
    local ns = {}
    for _, name in ipairs({ ... }) do
        local chunk, err = loadfile(H.ADDON .. "/" .. name .. ".lua")
        if not chunk then error(err, 2) end
        chunk(H.ADDON, ns)
    end
    return ns
end

-- Loads one addon file inside an optional fake global environment (tests/fakewow.lua).
function H.loadModule(name, ns, env)
    local chunk, err = loadfile(H.ADDON .. "/" .. name .. ".lua")
    if not chunk then error(err, 2) end
    if env then setfenv(chunk, env) end
    return chunk(H.ADDON, ns)
end

-- The file names the TOC lists, in order ("##" metadata, "#" comments and blank lines skipped).
function H.tocFiles()
    local files = {}
    local f = assert(io.open(H.ADDON .. "/" .. H.ADDON .. ".toc"))
    for line in f:lines() do
        line = line:gsub("\r$", "")
        if not line:match("^#") and line:match("%S") then files[#files + 1] = line:match("^%s*(.-)%s*$") end
    end
    f:close()
    return files
end

return H
