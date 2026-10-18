-- Template from the wow-addon-dev skill (adapted from CraftProfit, MIT): static checks that
-- catch, offline, mistakes only the game would otherwise reveal.
local H = ...

local function luaFilesOnDisk()
    local found = {}
    -- io.popen runs cmd.exe on Windows and sh elsewhere.
    local windows = package.config:sub(1, 1) == "\\"
    local p = io.popen(windows and ("cd " .. H.ADDON .. " && dir /s /b *.lua")
        or ("cd " .. H.ADDON .. " && find . -name '*.lua' | sed 's#^\\./##'"))
    local root
    for line in p:lines() do
        line = line:gsub("\r$", "")
        if windows then
            line = line:gsub("\\", "/")
            root = line:match("^(.*/" .. H.ADDON .. "/)")
            line = line:sub(#root + 1)
        end
        found[#found + 1] = line
    end
    p:close()
    table.sort(found)
    return found
end

local function read(path)
    local f = assert(io.open(path))
    local text = f:read("*a")
    f:close()
    return text
end

H.test("every file listed in the TOC exists, and every addon Lua file is listed once", function()
    local listed = {}
    for _, name in ipairs(H.tocFiles()) do
        if listed[name] then error("listed twice: " .. name) end
        listed[name] = true
        local f = io.open(H.ADDON .. "/" .. name)
        if not f then error("TOC lists a missing file: " .. name) end
        f:close()
    end
    for _, name in ipairs(luaFilesOnDisk()) do
        if not listed[name] then error("not in the TOC: " .. name) end
    end
end)

H.test("the TOC declares the interface and the saved variables", function()
    local text = read(H.ADDON .. "/" .. H.ADDON .. ".toc")
    H.truthy(text:find("## Interface: ", 1, true))
    H.truthy(text:find("## SavedVariables: ", 1, true))
end)

-- The Forever client raises "Division by zero" on a literal zero divisor (measured
-- 2026-10-08, build 1.60.1) where LuaJIT returns inf/NaN: build them from math.huge.
H.test("no addon file divides by a literal zero", function()
    local bad = {}
    for _, name in ipairs(luaFilesOnDisk()) do
        local n = 0
        for line in io.lines(H.ADDON .. "/" .. name) do
            n = n + 1
            local code = line:gsub("%-%-.*$", "")
            if code:match("/%s*0%f[%D]") and not code:match("/%s*0%.%d") then bad[#bad + 1] = name .. ":" .. n end
        end
    end
    if #bad > 0 then error("literal division by zero at " .. table.concat(bad, ", ")) end
end)

-- The game's sandbox has no io, require, loadfile, dofile, setfenv, getfenv or goto.
H.test("no addon file uses syntax or APIs missing from WoW's Lua 5.1", function()
    for _, name in ipairs(luaFilesOnDisk()) do
        local text = read(H.ADDON .. "/" .. name)
        for _, banned in ipairs({ "goto ", "require%(", "io%.", "loadfile", "dofile", "setfenv", "getfenv" }) do
            if text:find(banned) then error(name .. " uses " .. banned) end
        end
    end
end)
