-- From the wow-addon-dev skill: runs every tests/test_*.lua (not fakewow.lua or
-- harness.lua). Run from the project root: luajit tests/run.lua
local H = dofile("tests/harness.lua")

local files = {}
-- io.popen runs cmd.exe on Windows and sh elsewhere.
local windows = package.config:sub(1, 1) == "\\"
local p = io.popen(windows and "dir /b tests\\test_*.lua 2>nul" or "ls tests/test_*.lua 2>/dev/null")
for line in p:lines() do
    line = line:gsub("\r$", "")
    if windows then line = "tests/" .. line end
    files[#files + 1] = line
end
p:close()
table.sort(files)

if #files == 0 then
    print("no test files found")
    os.exit(1)
end

for _, f in ipairs(files) do
    H.setFile(f)
    local chunk, err = loadfile(f)
    local ok, e = chunk ~= nil, err
    if chunk then ok, e = pcall(chunk, H) end
    if not ok then
        H.failed = H.failed + 1
        H.failures[#H.failures + 1] = f .. ": " .. tostring(e)
        print("FAIL " .. f .. ": " .. tostring(e))
    end
end

print(string.format("%d passed, %d failed", H.passed, H.failed))
os.exit(H.failed == 0 and 0 or 1)
