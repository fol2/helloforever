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
C_Timer = { After = function() end }
local textures = {}
local function widget()
  local w = { shown = true }
  for _, m in ipairs({ "SetFrameStrata", "SetIgnoreParentScale", "SetScale", "ClearAllPoints", "SetAllPoints" }) do w[m] = function() end end
  function w:SetSize(a, b) self.w, self.h = a, b end
  function w:SetPoint(_, _, _, x, y) self.x, self.y = x or 0, y or 0 end
  function w:SetColorTexture(r, g, b) self.r, self.g, self.b = r, g, b end
  function w:Show() self.shown = true end
  function w:Hide() self.shown = false end
  function w:CreateTexture() local t = widget(); textures[#textures + 1] = t; return t end
  return w
end
local strip
CreateFrame = function() strip = widget(); return strip end
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
    if t.shown and strip.shown then
      k = k + 1
      local r, g, b = t.r, t.g, t.b
      if edit and k == edit then r = 1 - r end
      f:write(("%g %g %g %g %g %g %g\n"):format(strip.x + t.x, -(strip.y + t.y), t.w, t.h, r, g, b))
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
print_real(("== %d checks, %d failed"):format(n, fails))
os.exit(fails == 0 and 0 or 1)
