-- HelloLink's slash command after format 0 and most probes were removed (#45): /hlink send
-- gives the question to the strip (object 1) and draws nothing of its own; /hlink probe depth
-- draws its rows (the reader side of that probe, the spike's measurement, went with the Python
-- reader in #195 step 3c). The floor rows are read back by `reader/target/release/hellolink depth`,
-- so the Rust reader is built first. Usage: lua tests/hellolink_strip_test.lua <scratch dir>
-- ASSUMED client behaviour (plan/05, section 3): textures are drawn where SetPoint puts them,
-- in the colour SetColorTexture names, and a screenshot shows them.
local DIR = assert(arg[1], "usage: hellolink_strip_test.lua <scratch dir>")
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
  check(("/hlink probe depth %d %d draws its rows"):format(try[1], try[2]), dump(DIR .. "/cells.txt") > 0)
end
slash("hide")
do   -- /hlink probe lanes (#232, part C): depth 4 at 1 pixel, 4 whole lines of pattern, the lines in the first digit
  slash("probe lanes")
  local n = dump(DIR .. "/cells.txt")
  local rows = {}
  for l in io.lines(DIR .. "/cells.txt") do rows[#rows + 1] = l end
  local nine = rows[9] or ""
  local last = rows[#rows] or ""
  local function size(row) return tonumber(row:match("^%S+ %S+ (%S+)")) end
  local function top(row) return tonumber(row:match("^%S+ (%S+)")) end
  local lanesSide = size(nine)
  check(("/hlink probe lanes draws 10 + 64 + 4 lines of 256 squares (%d), its first levels digit 6 (4 lines, levels under 8)"):format(n),
    n == 10 + 64 + 1024 and nine:match(" 1 1 0$") ~= nil, nine)
  -- the pattern on exactly 4 screen lines of its own: its last square on the fifth line from the top
  -- (the palette's line, then 4), and 1-pixel squares, as depth 4 1 draws them (review of #267)
  slash("hide") slash("probe depth 4 1") dump(DIR .. "/cells.txt")
  local one
  for l in io.lines(DIR .. "/cells.txt") do one = one or l end
  slash("hide") slash("probe depth 4 2") dump(DIR .. "/cells.txt")
  local two
  for l in io.lines(DIR .. "/cells.txt") do two = two or l end
  check(("/hlink probe lanes: squares of 1 pixel (%s, depth 4 1: %s, depth 4 2: %s), the pattern on 4 lines of its own (last at %s)"):format(
    lanesSide, size(one), size(two), top(last) and top(last) / lanesSide), lanesSide == size(one) and math.abs(size(two) - 2 * lanesSide) < 1e-6
    and math.abs(top(last) - top(nine) - 4 * lanesSide) < 1e-3)
  -- the pattern's first square (the 75th drawn: 10 + 64 before it) starts the next line, not the palette's
  check("/hlink probe lanes: the pattern starts a line of its own", rows[75] and math.abs(top(rows[75]) - top(nine) - lanesSide) < 1e-3)
  check("probe depth refuses 5 lines", slash("probe depth 4 1 5"):find("use /hlink probe depth", 1, true) ~= nil)
end
do   -- the floor (#232, part C, "The computed palette", "Measure first", step 2): level k at
  -- lo + k * (1 - lo) / (L - 1) of full. The addon gives the client the fraction, not rounded;
  -- a byte is round(fraction * 255) to the nearest, as `hellolink render` makes it.
  -- The bytes of each level, written by hand: lo 0 gives 0, 85, 170, 255; lo 0.29 gives
  -- 0.29, 0.526667, 0.763333, 1 of full = 73.95, 134.3, 194.65, 255 = 74, 134, 195, 255.
  local floor = math.floor
  local function bytes(cmd)   -- the palette (rows 11 to 74) and every pattern square, as bytes
    slash("hide") slash(cmd) dump(DIR .. "/floor.txt")
    local rows, k = {}, 0
    for l in io.lines(DIR .. "/floor.txt") do
      k = k + 1
      if k > 10 then
        local r, g, b = l:match("(%S+) (%S+) (%S+)$")
        rows[#rows + 1] = { floor(r * 255 + 0.5), floor(g * 255 + 0.5), floor(b * 255 + 0.5) }
      end
    end
    return rows
  end
  local function palette(rows, B)   -- code i: red level i // 16, green (i // 4) % 4, blue i % 4
    for i = 0, 63 do
      local c, want = rows[i + 1], { B[floor(i / 16) + 1], B[floor(i / 4) % 4 + 1], B[i % 4 + 1] }
      if not c or c[1] ~= want[1] or c[2] ~= want[2] or c[3] ~= want[3] then return false, i end
    end
    for i = 65, #rows do   -- the pattern: every channel one of the four levels
      for ch = 1, 3 do
        local v = rows[i][ch]
        if v ~= B[1] and v ~= B[2] and v ~= B[3] and v ~= B[4] then return false, i end
      end
    end
    return #rows == 64 + 1024
  end
  local LO0, LO29 = { 0, 85, 170, 255 }, { 74, 134, 195, 255 }
  check("probe depth 4 1 4 (no floor): the levels at 0, 85, 170, 255, as before", palette(bytes("probe depth 4 1 4"), LO0))
  check("probe depth 4 1 4 0: the same", palette(bytes("probe depth 4 1 4 0"), LO0))
  check("probe depth 4 1 4 29: the palette and the pattern at 74, 134, 195, 255", palette(bytes("probe depth 4 1 4 29"), LO29))
  local r8 = bytes("probe depth 8 1 4 29") -- review of #288: the floor holds at 8 levels too
  check("probe depth 8 1 4 29: the darkest colour is 74, 74, 74 and the brightest 255, 255, 255",
    r8[1][1] == 74 and r8[1][2] == 74 and r8[1][3] == 74 and r8[512][1] == 255 and r8[512][2] == 255 and r8[512][3] == 255)
  check("probe depth refuses a floor of 91 per cent", slash("probe depth 4 1 4 91"):find("use /hlink probe depth", 1, true) ~= nil)
  check("probe depth takes a floor of 90 per cent", slash("probe depth 4 1 4 90"):find("floor 90", 1, true) ~= nil)
  check("probe depth refuses a floor that is not a whole number", slash("probe depth 4 1 4 2.5"):find("use /hlink probe depth", 1, true) ~= nil)
  -- the reader names squares by the palette as drawn: it reads a floor row without knowing the floor
  for _, cmd in ipairs({ "probe depth 4 1 4 29", "probe depth 8 1 4 29" }) do
    slash("hide") slash(cmd) dump(DIR .. "/floor.txt")
    local p = assert(io.popen(("reader/target/release/hellolink render '%s/floor.txt' '%s/floor.bmp' --scale %.12f --width 2560 --height 200 2>&1"
      .. " && reader/target/release/hellolink depth '%s/floor.bmp' 2>&1"):format(DIR, DIR, 1 / unit, DIR)))
    local said = p:read("*a") p:close()
    check(("hellolink depth reads the rows of /hlink %s with 0 wrong (%s)"):format(cmd, said:gsub("%s+$", "")),
      said:find('"wrong": 0,', 1, true) ~= nil and said:find('"lines": 4,', 1, true) ~= nil
      and said:find(('"levels": %s,'):format(cmd:match("depth (%d)")), 1, true) ~= nil)
  end
end
slash("hide")
check("/hlink hide takes the depth rows down", dump(DIR .. "/cells.txt") == 0)

-- The settings window (roadmap line 14): each /hlink strip setting has a control, and the
-- control sets it through ns.StripSet, the command's own checks. Last here: its textures are
-- not squares of the strip.
do
  local function more(w)
    for _, m in ipairs({ "SetClampedToScreen", "SetMovable", "EnableMouse", "RegisterForDrag", "SetJustifyH", "SetTextColor" }) do w[m] = function() end end
    w.StartMoving, w.StopMovingOrSizing = function() end, function() end
    function w:IsShown() return self.shown end
    function w:SetText(t) self.text = t end
    function w:CreateFontString() local fs = more(widget()) return fs end
    local realScript = w.SetScript
    function w:SetScript(kind, fn) if kind == "OnClick" or kind == "OnShow" then self[kind] = fn else realScript(self, kind, fn) end end
    local realShow = w.Show
    function w:Show() realShow(self) if self.OnShow then self.OnShow(self) end end
    return w
  end
  local realCreate = CreateFrame
  CreateFrame = function(...) return more(realCreate(...)) end
  local calls, st = {}, { on = true, x = 40, y = 6, size = 2, depth = "auto", dwell = 10, depthNow = 4 }
  -- a strip that takes the words as /hlink strip does, so each click's effect can be read back
  local fake = { StripState = function() return st end,
    StripSet = function(word, a, b)
      calls[#calls + 1] = table.concat({ word, a, b }, " ")
      if word == "on" or word == "off" then st.on = word == "on"
      elseif word == "size" then st.size = tonumber(a)
      elseif word == "depth" then st.depth = a == "auto" and "auto" or tonumber(a)
      elseif word == "dwell" then st.dwell = tonumber(a)
      elseif word == "at" then st.x, st.y = tonumber(a), tonumber(b) end
      return true
    end }
  assert(loadfile("HelloLink/HelloLink.lua"))("HelloLink", fake)
  slash("settings")
  local win
  for _, f in ipairs(frames) do if f.controls then win = f end end
  check("/hlink settings opens the strip's settings window", win ~= nil and win.shown)
  local c = win and win.controls or {}
  local need = { "on", "size 2", "size 3", "size 4", "depth auto", "depth 2", "depth 4", "dwell-", "dwell+",
    "x-10", "x-1", "x+1", "x+10", "y-10", "y-1", "y+1", "y+10", "at 0 0" }
  local missing = {}
  for _, k in ipairs(need) do if not c[k] then missing[#missing + 1] = k end end
  check("each /hlink strip setting has a control (on, size, depth, dwell, place)", #missing == 0, table.concat(missing, " "))
  local function click(k) calls = {} if c[k] and c[k].OnClick then c[k].OnClick(c[k]) end return calls[1] end
  local function label(k) return c[k] and c[k].label.text or "" end
  check("on: the strip off when it is on", click("on") == "off" and st.on == false and label("on"):find("[  ]", 1, true) ~= nil)
  check("...and on again", click("on") == "on" and st.on == true)
  for _, v in ipairs({ "4", "3", "2" }) do
    check("size " .. v .. ": its words, the strip's size, and its tick", click("size " .. v) == "size " .. v and st.size == tonumber(v)
      and label("size " .. v):find("[x]", 1, true) ~= nil)
  end
  for _, v in ipairs({ "2", "4", "auto" }) do
    check("depth " .. v .. ": its words, the strip's depth, and its tick", click("depth " .. v) == "depth " .. v
      and tostring(st.depth) == v and label("depth " .. v):find("[x]", 1, true) ~= nil)
  end
  check("a chunk stays 5 hundredths more", click("dwell+") == "dwell 15" and st.dwell == 15)
  check("...and 5 less", click("dwell-") == "dwell 10" and st.dwell == 10)
  st.dwell = 100
  check("...never over 100", click("dwell+") == "dwell 100")
  st.dwell = 5
  check("...never under 5", click("dwell-") == "dwell 5")
  st.dwell = 10
  local moves = { ["x+10"] = "at 50 6", ["x+1"] = "at 41 6", ["x-1"] = "at 39 6", ["x-10"] = "at 30 6",
    ["y+10"] = "at 40 16", ["y+1"] = "at 40 7", ["y-1"] = "at 40 5", ["y-10"] = "at 40 0" }
  for k, want in pairs(moves) do
    st.x, st.y = 40, 6
    check("place " .. k .. ": " .. want, click(k) == want)
  end
  st.x, st.y = 5, 3
  check("never left of 0", click("x-10") == "at 0 3")
  st.x, st.y = 5, 3
  check("never above 0", click("y-10") == "at 5 0")
  check("back to (0, 0)", click("at 0 0") == "at 0 0" and st.x == 0 and st.y == 0)
  st.x, st.y = 5, 6
  if win and win.OnUpdate then win.OnUpdate(win, 0.6) elseif win and win.onUpdate then win.onUpdate(win, 0.6) end
  check("the window says where the strip is", win and (win.state.text or ""):find("At (5, 6), 2 pixels a square, depth auto (now 4)", 1, true) ~= nil,
    win and win.state.text)
  -- a change by the command, or the depth the strip settles on, shows while the window is open
  st.size, st.depthNow = 4, 2
  local tickWin = win and (win.onUpdate or win.OnUpdate)
  if tickWin then tickWin(win, 0.6) end
  check("a change made elsewhere shows in the open window", label("size 4"):find("[x]", 1, true) ~= nil
    and (win.state.text or ""):find("(now 2)", 1, true) ~= nil, win and win.state.text)
  fake.StripState = function() return nil end
  if win then win:Hide(); win:Show() end
  check("before the strip is loaded it says so", win ~= nil and (win.state.text or ""):find("not loaded", 1, true) ~= nil)
  slash("settings")
  check("/hlink settings again closes it", win ~= nil and not win.shown)
  CreateFrame = realCreate
end

print_real(("== %d checks, %d failed"):format(n, fails))
os.exit(fails == 0 and 0 or 1)
