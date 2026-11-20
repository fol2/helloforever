-- /hlink probe api (HelloLink 0.8.3): a format-2 call that fails keeps its error's text, and an
-- error that is a secret value is only named, never read (review of #216).
--   lua5.1 tests/hellolink_probe_errors_test.lua
local fails, checks = 0, 0
local function check(ok, what)
    checks = checks + 1
    if not ok then fails = fails + 1; print("FAIL " .. what) end
end

local function boom() error("a secret value was used") end
local SECRET = setmetatable({}, { __tostring = boom, __index = boom, __eq = boom, __lt = boom, __le = boom,
    __concat = boom, __len = boom, __call = boom })
_G.issecretvalue = function(v) return rawequal(v, SECRET) end
_G.CreateFrame = function() return { RegisterEvent = function() end, SetScript = function() end } end
_G.C_UnitAuras = { GetAuraDataByIndex = function(unit)
    if unit == "player" then error(SECRET) end
    error("Usage: C_UnitAuras.GetAuraDataByIndex(unit, index [, filter])")
end }
_G.UnitAura = function() error(SECRET) end
_G.UnitPosition = function() error(string.rep("x", 200), 0) end

local ns = {}
assert(loadfile("HelloLink/Probe.lua"))("HelloLink", ns)
ns.ProbeApi("command")
local function line(name)
    for _, l in ipairs(_G.HelloLinkDB.probe[1].results) do if l:sub(1, #name) == name then return l end end
    return ""
end
local a = line("auras player HELPFUL")
check(a:find("C_UnitAuras ERROR <secret> | UnitAura=ERROR <secret>", 1, true) ~= nil,
    "a secret error is named, never read, in both aura answers: " .. a)
local t = line("auras target HARMFUL")
check(t:find("C_UnitAuras ERROR ", 1, true) and t:find("Usage: C_UnitAuras.GetAuraDataByIndex", 1, true),
    "an error's text is kept: " .. t)
local u = line("unit player")
local text = u:match("UnitPosition=ERROR (x+)…")
check(text ~= nil and #text == 120, "a long error's text is cut to 120 bytes: " .. u:sub(1, 200))
print(("== %d checks, %d failed"):format(checks, fails))
os.exit(fails == 0 and 0 or 1)
