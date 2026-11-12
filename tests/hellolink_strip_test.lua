-- HelloLink strip: what the addon draws for a text, turned into an image by
-- tools/hellolink_strip.py, decodes to the same text. Usage: lua tests/hellolink_strip_test.lua <scratch dir>
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
local secretNow, inCombat = {}, false
local SECRET = {}
issecretvalue = function(v) return v == SECRET end
InCombatLockdown = function() return inCombat end
GetPhysicalScreenSize = function() return 2560, 1440 end
local function api(name, value) _G[name] = function() if secretNow[name] then return SECRET end return value end end
api("UnitHealth", 100); api("UnitHealthMax", 120); api("UnitPower", 50); api("UnitPowerMax", 60); api("UnitLevel", 24)
api("GetMoney", 12345); api("UnitExists", true)
-- a cast returns several values; the spell id (the last) can be secret while the name is not
UnitCastingInfo = function() return "Aimed Shot", nil, nil, 1, 2, false, nil, false, secretNow.castId and SECRET or 19434 end
C_Map = { GetBestMapForUnit = function() return 1429 end,
  GetPlayerMapPosition = function() return { GetXY = function() if secretNow.xy then return SECRET, SECRET end return 0.5, 0.25 end } end }
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
  function w:SetValue(v) self.value = v end
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
-- draw at a scale that is not a whole number, away from the corner, on a noisy background
local function roundtrip(text, edit)
  slash("send " .. text)
  local cells = dump(DIR .. "/cells.txt", edit)
  sh(("%s render '%s/cells.txt' '%s/shot.bmp' --scale 1.875 --dx 37 --dy 61 --width 1400 --height 600"):format(TOOL, DIR, DIR))
  return sh(("%s read --image '%s/shot.bmp'"):format(TOOL, DIR)), cells
end

assert(loadfile("HelloLink/HelloLink.lua"))("HelloLink", {})
local a = roundtrip("why is my dps low?")
-- SEEN in the game on 12 Nov 2026: another addon draws a row of the same kind of
-- squares, 8 pixels high, at the very top-left, on top of ours. So ours starts lower.
check("the strip leaves the top edge free for another addon's row", strip.y <= -24 and strip.x == 0)
check("an ASCII text comes back from the image", a == "why is my dps low?\n")
local zh = "點解我呢區升得咁慢？ \"quoted\" \\ back"
check("Chinese and punctuation come back byte for byte", roundtrip(zh) == zh .. "\n")
local long = ("0123456789 abcdefghij "):rep(30) .. "end" -- the command trims spaces at the ends
local back, cells = roundtrip(long)
check("a text of several rows comes back", back == long .. "\n" and cells > 300)
local _, short = roundtrip("x")
check("a shorter text hides the squares of the longer one", short < 60)
check("a changed square is rejected by the checksum", roundtrip("checksum me", 30):find("no strip", 1, true) ~= nil)
local msg = slash("send " .. ("y"):rep(1401))
check("a text over the limit is refused in the game", msg:find("too long", 1, true) ~= nil)
slash("send hide me"); slash("hide")
check("/hlink hide takes the strip down", dump(DIR .. "/cells.txt") == 0)
sh(("%s render '%s/cells.txt' '%s/shot.bmp' --scale 2 --dx 0 --dy 0 --width 800 --height 300"):format(TOOL, DIR, DIR))
check("an image without a strip says so", sh(("%s read --image '%s/shot.bmp'"):format(TOOL, DIR)):find("no strip", 1, true) ~= nil)
-- Probes for docs/specs/29.md, section 9. ASSUMED: the client draws a square of N physical
-- pixels when asked for N * 768 / physicalHeight / effectiveScale UI units.
slash("hide")
local msg2 = slash("probe squares")
check("probe squares says what it drew", msg2:find("8, 4, 3 and 2", 1, true) ~= nil)
dump(DIR .. "/cells.txt")
local unit = 768 / 1440 / 0.7
sh(("%s render '%s/cells.txt' '%s/shot.bmp' --scale %.12f --dx 0 --dy 0 --width 1400 --height 200"):format(TOOL, DIR, DIR, 1 / unit))
local rep = sh(("%s probe --image '%s/shot.bmp'"):format(TOOL, DIR))
local clean = 0
for size, high in rep:gmatch("(%d) px: found, [%d.]+ px wide and (%d+) px high, 0 of 120 wrong") do
  if size == high then clean = clean + 1 end
end
check("the reader finds the four probe rows, each a true square, and reads each without an error", clean == 4)
sh(("%s render '%s/cells.txt' '%s/shot.bmp' --scale %.12f --dx 0 --dy 0 --width 1400 --height 200"):format(TOOL, DIR, DIR, 1.1 / unit))
check("squares that are not whole pixels are reported as wrong, not as clean",
  sh(("%s probe --image '%s/shot.bmp'"):format(TOOL, DIR)):find("2 px: found, [%d.]+ px wide and 2 px high, 0 of 120 wrong") == nil)

local function onStrip()
  dump(DIR .. "/cells.txt")
  sh(("%s render '%s/cells.txt' '%s/shot.bmp' --scale 1.875 --dx 5 --dy 9 --width 1400 --height 600"):format(TOOL, DIR, DIR))
  return sh(("%s read --image '%s/shot.bmp'"):format(TOOL, DIR))
end
-- P5: the bars. The stub's bar is filled value / maximum wide, as the client's is.
slash("hide")
UnitExists = function(who) return who ~= "pet" end
UnitHealth = function(who) return who == "target" and 30 or 90 end
UnitHealthMax = function(who) return who == "target" and 40 or 120 end
check("probe bars says what it drew", slash("probe bars"):find("as bars", 1, true) ~= nil)
for _, f in ipairs(frames) do if f.onUpdate then f.onUpdate() end end
dump(DIR .. "/cells.txt")
sh(("%s render '%s/cells.txt' '%s/shot.bmp' --scale %.12f --dx 0 --dy 0 --width 1400 --height 200"):format(TOOL, DIR, DIR, 1 / unit))
check("the reader measures each bar: health 75%, power 83%, target health 75%, no pet 0%",
  sh(("%s probe --image '%s/shot.bmp'"):format(TOOL, DIR)):find("bars: health 75%, power 83%, target health 75%, pet health 0%", 1, true) ~= nil)
slash("hide")
api("UnitHealth", 100); api("UnitHealthMax", 120); api("UnitExists", true)

secretNow = { UnitHealth = true }
local s1 = slash("probe secrets")
check("probe secrets names a secret value and counts the readable ones",
  s1:find("secret: health, targetHealth, petHealth;", 1, true) ~= nil and s1:find("combat=no", 1, true) ~= nil
    and s1:find("position", 1, true) == nil and s1:find("cast,", 1, true) == nil)
check("and shows the sample through the strip", onStrip():find("now: combat=no", 1, true) ~= nil)
local armed
for _, f in ipairs(frames) do armed = armed or f.onEvent end
secretNow = { UnitHealth = true, castId = true, xy = true }
out = {}; armed(nil, "UNIT_SPELLCAST_START", "target")
check("another unit's cast is not sampled", #out == 0)
armed(nil, "UNIT_SPELLCAST_START", "player")
local s3 = table.concat(out, "\n")
check("a value is secret when any of its returns is: the cast's spell id, the position's coordinates",
  s3:find("casting: combat=no", 1, true) ~= nil and s3:find("secret: health, cast, targetHealth, petHealth, position;", 1, true) ~= nil)
inCombat = true; secretNow = { UnitHealth = true, UnitPower = true }
out = {}; armed(nil, "PLAYER_REGEN_DISABLED")
for i = 1, #timers do timers[i]() end -- the timers set so far, not the hide timer the send adds
local s2 = table.concat(out, "\n")
check("after the next pull it samples again, in combat", s2:find("combat=yes", 1, true) ~= nil and s2:find("secret: health, power", 1, true) ~= nil)
check("and shows that sample through the strip", onStrip():find("fight: combat=yes", 1, true) ~= nil)
print_real(("== %d checks, %d failed"):format(n, fails))
os.exit(fails == 0 and 0 or 1)
