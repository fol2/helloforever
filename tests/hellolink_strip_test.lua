-- HelloLink's slash command after format 0 and most probes were removed (#45): /hlink send
-- gives the question to the strip (object 1) and draws nothing of its own; /hlink probe depth
-- draws rows that tools/hellolink_strip.py reads back. Usage: lua tests/hellolink_strip_test.lua <scratch dir>
-- ASSUMED client behaviour (plan/05, section 3): textures are drawn where SetPoint puts them,
-- in the colour SetColorTexture names, and a screenshot shows them.
local DIR = assert(arg[1], "usage: hellolink_strip_test.lua <scratch dir>")
local TOOL = "python3 tools/hellolink_strip.py"
local out = {}
print_real = print
print = function(...) out[#out + 1] = table.concat({ ... }, " ") end
SlashCmdList = {}
local timers = {}
C_Timer = { After = function(_, fn) timers[#timers + 1] = fn end }
GetPhysicalScreenSize = function() return 2560, 1440 end
local textures = {}
local function widget()
  local w = { shown = true }
  for _, m in ipairs({ "SetFrameStrata", "SetFrameLevel", "SetIgnoreParentScale", "SetScale", "ClearAllPoints", "SetAllPoints", "RegisterEvent", "UnregisterEvent" }) do w[m] = function() end end
  function w:SetScript(kind, fn) if kind == "OnUpdate" then self.onUpdate = fn else self.onEvent = fn end end
  function w:GetEffectiveScale() return 0.7 end
  function w:SetSize(a, b) self.w, self.h = a, b end
  function w:SetPoint(_, _, _, x, y) self.x, self.y = x or 0, y or 0 end
  function w:SetColorTexture(r, g, b) self.r, self.g, self.b = r, g, b end
  function w:Show() self.shown = true end
  function w:Hide() self.shown = false end
  function w:CreateTexture() local t = widget(); t.parent = self; textures[#textures + 1] = t; return t end
  -- a status bar: its fill texture is drawn from the bar's own value, not from a position
  function w:SetStatusBarTexture(t) t.fillOf = self end
  function w:SetMinMaxValues(_, max) self.max = max end
  function w:SetValue(v) assert(v ~= nil, "SetValue(nil)"); self.value = v end
  return w
end
local strip, frames = nil, {}
CreateFrame = function(kind, _, parent)
  local f = widget(); frames[#frames + 1] = f
  if kind == "StatusBar" then f.barParent = parent else strip = strip or f end
  return f
end
UIParent = widget()

local fails, n = 0, 0
local function check(name, cond) n = n + 1; if not cond then fails = fails + 1 end print_real((cond and "PASS " or "FAIL ") .. name) end
local function slash(m) out = {}; SlashCmdList["HELLOLINK"](m) return table.concat(out, "\n") end
local function sh(cmd) local p = assert(io.popen(cmd .. " 2>&1")); local s = p:read("*a"); p:close(); return s end

-- the squares on screen, as "x y w h r g b" in UI units (y grows downwards)
local function dump(path, edit)
  local f = assert(io.open(path, "w"))
  local k = 0
  for _, t in ipairs(textures) do
    local bar = t.fillOf
    if bar then
      if bar.shown and bar.barParent.shown and bar.max and bar.max > 0 then
        f:write(("%.9g %.9g %.9g %.9g 1 1 1\n"):format(bar.barParent.x + bar.x, -(bar.barParent.y + bar.y), bar.w * bar.value / bar.max, bar.h))
      end
    elseif t.shown and t.parent.shown then
      k = k + 1
      local r, g, b = t.r, t.g, t.b
      if edit and k == edit then r = 1 - r end
      f:write(("%.9g %.9g %.9g %.9g %g %g %g\n"):format(t.parent.x + t.x, -(t.parent.y + t.y), t.w, t.h, r, g, b))
    end
  end
  f:close()
  return k
end
local asked = {}
local ns = { StripQuestion = function(text) asked[#asked + 1] = text return true end }
assert(loadfile("HelloLink/HelloLink.lua"))("HelloLink", ns)
local unit = 768 / 1440 / 0.7

-- /hlink send: the question goes to the strip, and nothing else is drawn (#45).
local said = slash("send why is my dps low?")
check("/hlink send gives the text to the strip as the question", asked[1] == "why is my dps low?")
check("... draws no squares of its own (format 0 is gone)", dump(DIR .. "/cells.txt") == 0 and #frames == 0)
check("... and says where the question went", said:find("question", 1, true) ~= nil)
check("a question over the limit is refused", slash("send " .. ("y"):rep(1401)):find("too long", 1, true) ~= nil and #asked == 1)
check("an empty question is refused", slash("send"):find("use /hlink send", 1, true) ~= nil and #asked == 1)
local off = { StripQuestion = function() return false end }
assert(loadfile("HelloLink/HelloLink.lua"))("HelloLink", off)
check("with the strip off the question is not sent, and it says so", slash("send hello"):find("strip is off", 1, true) ~= nil)
assert(loadfile("HelloLink/HelloLink.lua"))("HelloLink", ns)

-- The probes that were for the spike are gone; each name says how to use the one left.
for _, gone in ipairs({ "probe squares", "probe bars", "probe curves", "probe secrets" }) do
  check("/hlink " .. gone .. " is gone: it names /hlink probe depth and draws nothing",
    slash(gone):find("use /hlink probe depth", 1, true) ~= nil and dump(DIR .. "/cells.txt") == 0)
end
local before = #timers
check("/hlink reloadtest is gone: it calls nothing", slash("reloadtest"):find("use /hlink", 1, true) ~= nil and #timers == before)

-- P6: how many colours can a square carry? A palette, then a known pattern.
check("probe depth refuses a depth it cannot draw", slash("probe depth 9"):find("use /hlink probe depth", 1, true) ~= nil)
for _, try in ipairs({ { 2, 2 }, { 4, 2 }, { 8, 1 } }) do
  slash("hide")
  slash(("probe depth %d %d"):format(try[1], try[2]))
  dump(DIR .. "/cells.txt")
  sh(("%s render '%s/cells.txt' '%s/shot.bmp' --scale %.12f --dx 0 --dy 0 --width 1400 --height 200"):format(TOOL, DIR, DIR, 1 / unit))
  local want = ("depth %d levels (%d bits a square), %d px: 0 of 240 wrong"):format(try[1], ({ [2] = 3, [4] = 6, [8] = 9 })[try[1]], try[2])
  check("the reader engine reads " .. want, sh(("%s probe --image '%s/shot.bmp'"):format(TOOL, DIR)):find(want, 1, true) ~= nil)
end
slash("hide")
check("/hlink hide takes the depth rows down", dump(DIR .. "/cells.txt") == 0)
check("the reader has no format-0 command left", sh(("%s read --image '%s/shot.bmp'"):format(TOOL, DIR)):find("invalid choice", 1, true) ~= nil)

print_real(("== %d checks, %d failed"):format(n, fails))
os.exit(fails == 0 and 0 or 1)
