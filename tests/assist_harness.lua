-- The assistant, step 1 (docs/specs/115.md, section 11; #125).
--
--   lua5.1 tests/assist_harness.lua ./HelloForever <out_SV.lua> <out_truth.json>
--
-- The sections below need the mock client of fights_harness_v4.lua, so they are spliced into
-- its source before its logout section, as fights_harness_more.lua does. It runs the whole
-- harness plus these sections, and exits non-zero on any failure.
local path = (arg[0] or "tests/assist_harness.lua"):gsub("assist_harness%.lua$", "fights_harness_v4.lua")
local f = assert(io.open(path, "r"))
local src = f:read("*a")
f:close()
local marker = 'realprint("== 30. logout")'
local at = assert(src:find(marker, 1, true), "the harness has no logout section to splice before")

local more = [==[
-- Region methods the real client has, which the assistant's bar uses (GetLeft, GetTop).
REGION[#REGION + 1] = "GetLeft"
REGION[#REGION + 1] = "GetTop"
function IMPL:GetLeft() return self.left or 300 end
function IMPL:GetTop() return self.top or 700 end
local check0 = check
local function check(name, cond, detail)
  check0(name, cond)
  if not cond and detail then realprint("       -> " .. tostring(detail)) end
end
realprint("== A1. the assistant: languages")
do
  local A = ns.Assist or {}
  local L = A.Lang or {}
  local function places(s) local out = {} for p in tostring(s):gmatch("%%[sd]") do out[#out + 1] = p end return table.concat(out) end
  local en, yue = L.en, L.yue
  check("assist: an English and a Cantonese table", type(en) == "table" and type(yue) == "table")
  local missing, wrong, n = {}, {}, 0
  for code, t in pairs(L) do
    for k, v in pairs(en or {}) do
      n = n + 1
      if t[k] == nil then missing[#missing + 1] = code .. "." .. k
      elseif places(t[k]) ~= places(v) then wrong[#wrong + 1] = code .. "." .. k end
    end
  end
  check("assist: every table has every pattern of en (" .. n .. " looked at)", n > 20 and #missing == 0, table.concat(missing, " "))
  check("assist: ...with the same places for numbers and names", #wrong == 0, table.concat(wrong, " "))
end

realprint("== A2. the assistant off is 0.11.0's behaviour")
local assistBoar -- the mobs of the fights below
do
  local A = ns.Assist or {}
  local function settle() for _ = 1, 60 do advance(0.5) if ns.fightStatus.state == "idle" then return end end end
  slash("fights read"); settle()
  local s = HelloForeverDB.settings
  check("assist: off by default; outside on; English", s.assist == false and s.assistOutside == true and s.assistLang == "en")
  check("assist: HelloForeverAssist.on is false", type(HelloForeverAssist) == "table" and HelloForeverAssist.on == false)
  local n0 = count()
  assistBoar = { { "Creature-0-1-1200", 4100, "Card Boar" } }
  for i = 1, 4 do advance(2); fightOnce(1200 + i, "Card Boar", 10 + i, { mobs = assistBoar }); settle() end
  check("assist off: the fights are saved", count() == n0 + 4)
  local bar = _G.HelloForeverAssistBar
  check("assist off: no card and no bar", #((A.Cards and A.Cards()) or { 1 }) == 0 and (bar == nil or not bar:IsShown()))
  check("assist off: no counts saved", C().assist == nil)
  local p0 = #printed
  slash("assist test")
  check("assist off: /hello assist test says it is off and makes no card",
    #printed == p0 + 1 and printed[#printed]:find("off", 1, true) ~= nil and #((A.Cards and A.Cards()) or { 1 }) == 0)
end

realprint("== A3. the window opens with the assistant off and the panel hidden")
do
  slash("hide")
  slash("assist")
  local w = _G.HelloForeverAssistWindow
  check("assist: /hello assist opens the window with the assistant off and the panel hidden", w ~= nil and w:IsShown())
  if w then
    check("assist off: the sample card's button is greyed", w.sample and w.sample.off == true)
    if w.sample then w.sample.scripts.OnClick(w.sample) end
    local A = ns.Assist or {}
    check("assist off: ...and a click on it makes no card and leaves the assistant off",
      #((A.Cards and A.Cards()) or { 1 }) == 0 and HelloForeverAssist.on == false and HelloForeverDB.settings.assist == false)
    w:Hide()
  end
  slash("show")
end

realprint("== A4. each control of the window changes the setting its command changes")
do
  slash("assist")
  local w = _G.HelloForeverAssistWindow
  local s = HelloForeverDB.settings
  local function click(b) if b and b.scripts.OnClick then b.scripts.OnClick(b, "LeftButton") end end
  -- a command for each setting, and the control for the same (docs/specs/115.md, section 4)
  click(w and w.onCheck)
  check("assist window: the check 'on' sets settings.assist as /hello assist on does", s.assist == true and HelloForeverAssist.on == true)
  slash("assist off")
  check("assist: /hello assist off", s.assist == false and HelloForeverAssist.on == false)
  slash("assist on")
  check("assist: /hello assist on", s.assist == true and HelloForeverAssist.on == true)
  click(w and w.outsideCheck)
  check("assist window: the check 'outside' sets settings.assistOutside", s.assistOutside == false)
  slash("assist outside on")
  check("assist: /hello assist outside on", s.assistOutside == true)
  click(w and w.lang and w.lang.yue)
  check("assist window: the language button 'yue' sets settings.assistLang", s.assistLang == "yue")
  slash("assist lang en")
  check("assist: /hello assist lang en", s.assistLang == "en")
  slash("assist mute bags")
  check("assist: /hello assist mute bags", s.assistMuted and s.assistMuted.bags == true)
  local row = w and w.muted and w.muted[1]
  check("assist window: the muted subject has a row with a button to take it back", row and row:IsShown() and row.key == "bags")
  click(row and row.unmute)
  check("assist window: ...and its button takes it back as /hello assist unmute does", s.assistMuted.bags == nil)
  local controls = { assist = w and w.onCheck, assistOutside = w and w.outsideCheck, assistLang = w and w.lang, assistMuted = w and w.muted }
  local without = {}
  for _, key in ipairs({ "assist", "assistOutside", "assistLang", "assistMuted" }) do
    if controls[key] == nil then without[#without + 1] = key end
  end
  check("assist window: every setting that has a command has a control", #without == 0, table.concat(without, " "))
  check("assist window: the sample button is live with the assistant on", w and w.sample and not w.sample.off)
  if w then w:Hide() end
end

realprint("== A5. the fight card")
do
  local A = ns.Assist or {}
  local function settle() for _ = 1, 60 do advance(0.5) if ns.fightStatus.state == "idle" then return end end end
  local function shown() return A.Shown and A.Shown() end
  local bar = function() return _G.HelloForeverAssistBar end
  -- The four fights of A2 are in the baseline; a fifth has three earlier fights that know each number.
  advance(2); fightOnce(1210, "Card Boar", 12, { mobs = assistBoar }); settle()
  local c = shown()
  check("assist: after a counted fight with a usual value, the fight card", c and c.id == "fight" and c.kind == "event" and c.prio == 3 and c.src == "addon",
    c and (c.id .. " " .. c.text) or "none")
  check("assist: ...its text from the en pattern, with the enemy and the usual value",
    c and c.text:find("Card Boar", 1, true) and c.text:find("usual", 1, true))
  check("assist: ...it says what it stands on", c and c.basis and c.basis:find("4 fights", 1, true))
  check("assist: ...and the bar shows it", bar() and bar():IsShown() and bar().text:GetText() == (c and c.text))
  check("assist: the card and the chat line come from one function", type(ns.BaselineCompare) == "function")
  -- a first fight against another enemy: no usual value, no card; the old card goes with the next fight
  advance(2); fightOnce(1211, "New Wolf", 12, { mobs = { { "Creature-0-1-1211", 4101, "New Wolf" } } }); settle()
  check("assist: a fight with no usual value gives no card, and the last fight's card goes", shown() == nil and not bar():IsShown())
  -- two enemies: not counted, no card
  advance(2); fightOnce(1212, "Pair", 12, { mobs = { assistBoar[1], { "Creature-0-1-1212", 4101, "New Wolf" } } }); settle()
  check("assist: a fight against two enemies gives no card", shown() == nil)
  -- a death: prio 2
  advance(2); fightOnce(1213, "Card Boar", 14, { mobs = assistBoar, died = true }); settle()
  c = shown()
  check("assist: a fight with a death gives prio 2", c and c.id == "fight" and c.prio == 2)
  -- 120 s
  advance(119)
  check("assist: the card stays 120 s", shown() ~= nil)
  advance(3)
  check("assist: ...and goes after", shown() == nil and not bar():IsShown())
  -- the counts
  local n = C().assist and C().assist.fight
  check("assist: the counts say how often the card was shown", n and n.shown == 2 and (n.away or 0) == 0 and type(n.t) == "number")
  for sid = 1200, 1213 do sessions[sid] = nil end
end

realprint("== A6. order, sent away, muted, the key, the limit")
do
  local A = ns.Assist or {}
  local Put, Drop = A.Put or function() return false end, A.Drop or function() end
  local function shown() local c = A.Shown and A.Shown() return c and c.id end
  local bar = _G.HelloForeverAssistBar
  local function rightClick() bar.scripts.OnMouseUp(bar, "RightButton") end
  local T = time()
  local function card(id, kind, prio, o)
    o = o or {}
    return { id = id, kind = kind, prio = prio, text = o.text or (id .. " text"), basis = "test", src = o.src or "addon", at = o.at or time(), ttl = o.ttl or 600 }
  end
  Put(card("low", "event", 3, { at = T - 5 }))
  Put(card("mid", "event", 2, { at = T - 10 }))
  Put(card("low2", "event", 3, { at = T }))
  check("assist: the bar shows the lowest prio first", shown() == "mid")
  check("assist: ...the count of the others waiting", bar.count:GetText() == "+2")
  rightClick()
  check("assist: a right-click sends the shown card away; among equal prio the newest shows", shown() == "low2")
  Put(card("mid", "event", 2, { at = T - 10 }))
  check("assist: an event card sent away does not come back with the same key and time", shown() == "low2")
  Drop("low"); Drop("low2")
  -- state cards
  Put(card("bags", "state", 2))
  check("assist: a state card shows", shown() == "bags")
  rightClick()
  Put(card("bags", "state", 2, { text = "bags: 1 free" }))
  check("assist: a state card sent away stays away while its condition holds, also when its numbers change", shown() == nil)
  Put(card("bags", "state", 1))
  check("assist: ...and shows again when its prio number goes down", shown() == "bags")
  rightClick()
  Drop("bags")
  Put(card("bags", "state", 1))
  check("assist: ...and shows again when its condition ended and came back", shown() == "bags")
  local counts = C().assist and C().assist.bags
  check("assist: the counts say how often it was sent away", counts and counts.away == 2)
  -- muted
  slash("assist mute bags")
  check("assist: a muted subject is not shown", shown() == nil)
  Put(card("bags", "state", 1))
  check("assist: ...also when it comes again", shown() == nil)
  slash("assist unmute bags")
  Drop("bags"); Put(card("bags", "state", 2))
  check("assist: unmuted, it shows again", shown() == "bags")
  Drop("bags")
  -- the key: a card from outside never takes the place of one of the addon's
  Put(card("same", "event", 3, { text = "the addon's" }))
  Put(card("same", "event", 3, { text = "from outside", src = "companion" }))
  local keys = {}
  for _, x in ipairs(A.Cards()) do keys[#keys + 1] = x.key end
  table.sort(keys)
  check("assist: a card from outside is known by out:<id>, beside the addon's card of that id", table.concat(keys, ",") == "out:same,same")
  Drop("same"); Drop("out:same")
  -- a card without its ground is not shown
  check("assist: a card without a basis is refused", Put({ id = "nobasis", kind = "event", prio = 3, text = "x", src = "addon", at = time(), ttl = 60 }) == false)
  -- the limit of 20
  for i = 1, 20 do Put(card("e" .. i, "event", i <= 10 and 3 or 2, { at = T + i })) end
  check("assist: 20 cards are held", #A.Cards() == 20)
  Put(card("e21", "event", 1, { at = T + 30 }))
  local has = {}
  for _, x in ipairs(A.Cards()) do has[x.key] = true end
  check("assist: a twenty-first takes the place of the oldest event card of the highest prio number", #A.Cards() == 20 and has.e21 and not has.e1 and has.e2)
  for i = 1, 21 do Drop("e" .. i) end
  for i = 1, 20 do Put(card("s" .. i, "state", 3)) end
  check("assist: with no event card, a twenty-first is refused", Put(card("s21", "state", 1)) == false and #A.Cards() == 20)
  for i = 1, 20 do Drop("s" .. i) end
  -- at most 50 keys in the counts, the oldest t goes first
  C().assist = {}
  for i = 1, 55 do advance(1); Put(card("k" .. i, "event", 1)); Drop("k" .. i) end
  local nk = 0
  for _ in pairs(C().assist) do nk = nk + 1 end
  check("assist: the counts keep at most 50 keys, the oldest going first", nk == 50 and C().assist.k1 == nil and C().assist.k55 ~= nil)
end

realprint("== A7. quiet in a fight")
do
  local A = ns.Assist or {}
  local bar = _G.HelloForeverAssistBar
  A.Put({ id = "before", kind = "event", prio = 3, text = "before the fight", basis = "test", src = "addon", at = time(), ttl = 600 })
  check("assist: the card before the fight is on the bar", bar:IsShown() and bar.text:GetText() == "before the fight")
  inCombat = true; restrictState = 2
  fire("PLAYER_REGEN_DISABLED")
  A.Put({ id = "during", kind = "event", prio = 1, text = "made in the fight", basis = "test", src = "addon", at = time(), ttl = 600 })
  check("assist: in combat the bar keeps what it shows", bar.text:GetText() == "before the fight")
  bar.scripts.OnMouseUp(bar, "RightButton")
  check("assist: ...and a right-click does nothing", bar.text:GetText() == "before the fight" and #A.Cards() == 2)
  slash("assist")
  local w = _G.HelloForeverAssistWindow
  check("assist window: in combat it opens", w:IsShown())
  local was = HelloForeverDB.settings.assistOutside
  check("assist window: in combat its controls are greyed", w.outsideCheck.off == true and w.onCheck.off == true)
  w.outsideCheck.off = nil -- a control not greyed yet (a window drawn before the fight) is still dropped
  w.outsideCheck.scripts.OnClick(w.outsideCheck)
  check("assist window: in combat a click on a control is dropped", HelloForeverDB.settings.assistOutside == was)
  w.close.scripts.OnClick(w.close)
  check("assist window: ...and it closes", not w:IsShown())
  inCombat = false; restrictState = 0
  fire("PLAYER_REGEN_ENABLED"); advance(3)
  check("assist: after the fight the waiting card shows", bar.text:GetText() == "made in the fight")
  check("assist: ...and a click on a control is not kept for later", HelloForeverDB.settings.assistOutside == was)
  A.Drop("before"); A.Drop("during")
end

realprint("== A8. the sample card, in each language; the ways in")
do
  local A = ns.Assist or {}
  local bar = _G.HelloForeverAssistBar
  slash("assist test")
  local c = A.Shown and A.Shown()
  check("assist: /hello assist test shows a sample card in English", c and c.id == "test" and c.text == A.Lang.en.sample and bar.text:GetText() == c.text)
  advance(31)
  check("assist: ...for 30 s", A.Shown() == nil)
  slash("assist lang yue")
  slash("assist test")
  check("assist: ...and in Cantonese", A.Shown() and A.Shown().text == A.Lang.yue.sample and A.Lang.yue.sample ~= A.Lang.en.sample)
  slash("assist lang en")
  A.Drop("test")
  slash("assist lang xx")
  check("assist: an unknown language is refused", HelloForeverDB.settings.assistLang == "en" and printed[#printed]:find("en", 1, true))
  -- the bar's tooltip
  A.Put({ id = "tip", kind = "event", prio = 3, text = "tip", basis = "8 fights at level 14", detail = "one\ntwo", src = "addon", at = time() - 120, ttl = 600 })
  bar.scripts.OnEnter(bar)
  local tip = table.concat(tipLines, "|")
  check("assist: the tooltip has the detail, then who made it, the basis and the age",
    tip:find("one|two", 1, true) and tip:find("8 fights at level 14", 1, true) and tip:find("2 min", 1, true), tip)
  A.Drop("tip")
  -- the window's ways in: the bar, the menu, the fight window
  local w = _G.HelloForeverAssistWindow
  A.Put({ id = "way", kind = "event", prio = 3, text = "way", basis = "test", src = "addon", at = time(), ttl = 600 })
  w:Hide(); bar.scripts.OnMouseUp(bar, "LeftButton")
  check("assist: a left-click on the bar opens the window", w:IsShown())
  w:Hide()
  HelloForeverFrame.scripts.OnMouseUp(HelloForeverFrame, "RightButton")
  local entry, box
  for _, it in ipairs(menuItems) do
    if it.text == "Assistant" and it.fn then entry = it end
    if it.text == "Assistant on" and it.isSel then box = it end
  end
  check("assist: the panel's menu has an entry and a check box for the assistant", entry ~= nil and box ~= nil and box.isSel() == true)
  if entry then entry.fn() end
  check("assist: ...the entry opens the window", w:IsShown())
  w:Hide()
  local fw = _G.HelloForeverFights
  if not (fw and fw:IsShown()) then ns.UI.ToggleFights() end
  fw = _G.HelloForeverFights
  check("assist: the fight window has a button for the assistant", fw and fw.assist ~= nil)
  if fw and fw.assist then fw.assist.scripts.OnClick(fw.assist) end
  check("assist: ...which opens the window", w:IsShown())
  w:Hide(); if fw and fw:IsShown() then ns.UI.ToggleFights() end
  -- the settings page, where the client has one
  local cat
  Settings = { RegisterCanvasLayoutCategory = function(frame, name) cat = { frame = frame, name = name } return cat end,
    RegisterAddOnCategory = function(c) cat.added = (c == cat) end }
  if A.SettingsPage then A.SettingsPage() end
  local open = cat and cat.frame and cat.frame.open
  check("assist: a page in the game's settings, with a button that opens the window", cat and cat.added and open ~= nil)
  if open then open.scripts.OnClick(open) end
  check("assist: ...which opens it", w:IsShown())
  w:Hide(); Settings = nil
  A.Drop("way")
end

realprint("== A9. a rule that fails three times is off; the fight is still saved")
do
  local A = ns.Assist or {}
  local function settle() for _ = 1, 60 do advance(0.5) if ns.fightStatus.state == "idle" then return end end end
  local real = ns.BaselineCompare
  ns.BaselineCompare = function() error("broken on purpose") end
  local n0 = count()
  for i = 1, 3 do advance(2); fightOnce(1220 + i, "Card Boar", 12, { mobs = assistBoar }); settle() end
  check("assist: the fights are saved while the rule fails", count() == n0 + 3)
  check("assist: a rule that failed three times is off", A.RulesOff and A.RulesOff().fight == true)
  ns.BaselineCompare = real
  advance(2); fightOnce(1224, "Card Boar", 12, { mobs = assistBoar }); settle()
  check("assist: ...for the session", A.Shown() == nil)
  local p0 = #printed
  slash("debug")
  local said = false
  for i = p0 + 1, #printed do if printed[i]:find("assistant", 1, true) and printed[i]:find("fight", 1, true) then said = true end end
  check("assist: /hello debug says the rule is off", said)
  for sid = 1220, 1224 do sessions[sid] = nil end
  slash("assist off")
  check("assist: off again leaves no card", #A.Cards() == 0 and not _G.HelloForeverAssistBar:IsShown() and HelloForeverAssist.on == false)
end

realprint("== A10. review round 1: the bar's place in a fight, every entry under pcall, the expiry")
do
  local A = ns.Assist
  local function settle() for _ = 1, 60 do advance(0.5) if ns.fightStatus.state == "idle" then return end end end
  slash("assist on")
  local bar = _G.HelloForeverAssistBar
  A.Put({ id = "place", kind = "event", prio = 3, text = "place", basis = "test", src = "addon", at = time(), ttl = 600 })
  local s0 = bar.scale
  local function anchor() local p = bar.points[1] return #bar.points == 1 and p and p[2] end
  check("assist: out of a fight the bar hangs under the panel", anchor() == HelloForeverFrame)
  bar.left, bar.top = 321, 654
  inCombat = true; restrictState = 2; fire("PLAYER_REGEN_DISABLED")
  check("assist: in a fight the bar is pinned where it is", anchor() == UIParent and bar.points[1][4] == 321 and bar.points[1][5] == 654)
  slash("scale 2")
  HelloForeverFrame.scripts.OnDragStart(HelloForeverFrame); HelloForeverFrame.scripts.OnDragStop(HelloForeverFrame)
  check("assist: in combat a new panel scale or place does not change the bar",
    bar.scale == s0 and anchor() == UIParent and bar.points[1][4] == 321 and bar.points[1][5] == 654)
  inCombat = false; restrictState = 0; fire("PLAYER_REGEN_ENABLED"); advance(3)
  check("assist: ...after the fight the bar takes the scale and hangs under the panel again", bar.scale == 2 and anchor() == HelloForeverFrame)
  slash("scale 1"); A.Drop("place")
  -- a widget call that fails inside the assistant stops at the assistant
  rawset(bar.text, "SetText", function() error("SetText broken on purpose") end)
  local ok = pcall(slash, "assist test")
  check("assist: a failing widget call in /hello assist test does not escape the command", ok)
  ok = pcall(A.Put, { id = "direct", kind = "event", prio = 1, text = "direct", basis = "test", src = "addon", at = time(), ttl = 600 })
  check("assist: ...nor a card put from elsewhere (a rule, a timer)", ok)
  A.Drop("direct")
  rawset(bar.text, "SetText", nil)
  A.Drop("test")
  local realDebug = A.Debug
  A.Debug = function() error("Debug broken on purpose") end
  slash("debug")
  check("assist: a failing assistant does not stop /hello debug", printed[#printed]:find("fights: api=true", 1, true) ~= nil)
  A.Debug = realDebug
  local realCmd = A.Command
  A.Command = function() error("Command broken on purpose") end
  ok = pcall(slash, "assist list")
  check("assist: a failing assistant command says so and does not escape", ok and printed[#printed]:find("assistant failed", 1, true) ~= nil)
  A.Command = realCmd
  -- an event card goes ttl after its own time, not ttl after it came
  A.Put({ id = "late", kind = "event", prio = 3, text = "late", basis = "test", src = "addon", at = time() - 50, ttl = 60 })
  advance(11)
  check("assist: an event card goes ttl after its time", A.Shown() == nil)
  -- the call from the capture: an assistant that fails at its entry does not touch the fight
  local realFight = ns.AssistFight
  ns.AssistFight = function() error("AssistFight broken on purpose") end
  local n0, e0 = count(), ns.fightStatus.errors
  advance(2); fightOnce(1230, "Card Boar", 12, { mobs = assistBoar }); settle()
  check("assist: a failing assistant entry leaves the fight saved and the reader without an error",
    count() == n0 + 1 and ns.fightStatus.errors == e0 and ns.fightStatus.state == "idle")
  ns.AssistFight = realFight
  sessions[1230] = nil
end

realprint("== A11. the window holds every card and every muted subject")
do
  local A = ns.Assist
  for i = 1, 8 do A.Put({ id = "w" .. i, kind = "event", prio = 3, text = "card " .. i, basis = "test", src = "addon", at = time() + i, ttl = 600 }) end
  slash("assist")
  local w = _G.HelloForeverAssistWindow
  check("assist window: the first rows show the first cards, and the head says how many", w.rows[1].text:GetText() == "card 8" and w.cardsHead:GetText():find("/ 8", 1, true))
  w.cardArea.scripts.OnMouseWheel(w.cardArea, -1)
  check("assist window: the wheel shows the next card", w.rows[1].text:GetText() == "card 7")
  w.cardArea.scripts.OnMouseWheel(w.cardArea, -5)
  check("assist window: ...down to the last", w.rows[6].text:GetText() == "card 1" and w.rows[1].text:GetText() == "card 6")
  for i = 1, 8 do A.Drop("w" .. i) end
  for i = 1, 7 do slash("assist mute m" .. i) end
  check("assist window: five muted rows, and the head says how many", w.muted[5].key == "m5" and w.mutedLabel:GetText():find("/ 7", 1, true))
  w.mutedArea.scripts.OnMouseWheel(w.mutedArea, -2)
  check("assist window: the wheel shows the other muted subjects", w.muted[1].key == "m3" and w.muted[5].key == "m7")
  for i = 1, 7 do slash("assist unmute m" .. i) end
  w:Hide()
  slash("assist off")
end

realprint("== A12. step 2: cards from outside, the question, the window's topics and state line (#127)")
do
  local A = ns.Assist
  slash("assist on")
  local function card(o)
    local c = { id = "session", kind = "event", prio = 3, src = "companion", at = time() - 5, ttl = 600, text = "from outside", basis = "the strip" }
    for k, v in pairs(o or {}) do c[k] = v end
    return c
  end
  local function link(o)
    local t = { strip = true, session = 4711, seq = 1, t = time(), cards = { card() }, left = 150, taken = 1, refused = 0 }
    for k, v in pairs(o or {}) do t[k] = v end
    return t
  end
  local function keys() local out = {} for _, c in ipairs(A.Cards()) do out[#out + 1] = c.key end table.sort(out) return table.concat(out, ",") end
  HelloLinkAssist = link()
  advance(1.5)
  check("a card HelloLink took shows, known by out:<id>", keys() == "out:session" and A.Shown() and A.Shown().text == "from outside")
  check("HelloForeverAssist says the card shown and the language", HelloForeverAssist.shown == "out:session" and HelloForeverAssist.lang == "en")
  local n0 = C().assist and C().assist["out:session"] and C().assist["out:session"].shown or 0
  local function pending() local k = 0 for _, t in ipairs(timers) do if t.once and not t.done then k = k + 1 end end return k end
  local t0 = pending()
  advance(5)
  check("the same set read again each second is not shown again, and starts no timer", (C().assist["out:session"].shown or 0) == n0 and pending() <= t0,
    t0 .. " -> " .. pending())
  HelloLinkAssist = link({ cards = {} })
  advance(1.5)
  check("a set without the card removes it", keys() == "")
  HelloLinkAssist = link({ cards = { card({ src = "addon" }), card({ id = "two", kind = "zz" }) } })
  advance(1.5)
  check("a card from outside is checked again: one with src addon or a bad field is not taken", keys() == "")
  HelloLinkAssist = link()
  slash("assist outside off"); advance(1.5)
  check("with outside off no card from outside", keys() == "")
  slash("assist outside on"); advance(1.5)
  check("...and on again it comes back", keys() == "out:session")
  HelloLinkAssist = link({ strip = false, cards = {} })
  advance(1.5)
  check("with the strip off (HelloLink says so) no card from outside", keys() == "")
  HelloLinkAssist = link()
  advance(1.5)
  inCombat = true; restrictState = 2; fire("PLAYER_REGEN_DISABLED")
  HelloLinkAssist = link({ cards = { card({ text = "changed in the fight" }) } })
  advance(1.5)
  check("in a fight the set is not read", A.Cards()[1] and A.Cards()[1].text == "from outside")
  inCombat = false; restrictState = 0; fire("PLAYER_REGEN_ENABLED"); advance(3)
  check("...after it, it is", A.Shown() and A.Shown().text == "changed in the fight")
  HelloLinkAssist = nil
  advance(1.5)
  check("without HelloLink no card from outside", keys() == "")
  -- the question
  local p0 = #printed
  slash("ask session")
  check("/hello ask without HelloLink says so and asks nothing", printed[#printed]:find("nothing was asked", 1, true) ~= nil and HelloForeverAssist.ask == nil)
  HelloLinkAssist = link({ cards = {}, re = nil })
  advance(1.5) -- the tick reads it
  slash("ask bad topic!")
  check("a topic that is not a word is refused", printed[#printed]:find("use /hello ask", 1, true) ~= nil and HelloForeverAssist.ask == nil)
  slash("ask session")
  local q = HelloForeverAssist.ask
  check("/hello ask: the question goes into HelloForeverAssist with its number, topic and time",
    q and q.n == 1 and q.topic == "session" and q.t == time())
  check("...and the bar says it was asked", A.Shown() and A.Shown().id == "ask" and A.Shown().text == A.Lang.en.asked:format("session"))
  HelloLinkAssist = link({ re = 1, cards = { card({ id = "answer", text = "the answer" }) } })
  advance(1.5)
  check("the answer (a set whose re is the question's number) takes the asked card away and shows",
    keys() == "out:answer" and A.Shown().text == "the answer")
  slash("ask session")
  check("a second question has the next number", HelloForeverAssist.ask.n == 2)
  advance(31)
  check("no answer in 30 s: the card says so", A.Shown() and A.Shown().id == "ask" and A.Shown().text == A.Lang.en.no_answer and A.Shown().prio == 2)
  A.Drop("ask")
  HelloLinkAssist = link({ left = 0, cards = {} })
  advance(1.5)
  slash("ask session")
  check("no slot left: the card says so and nothing is asked", A.Shown() and A.Shown().text == A.Lang.en.no_slot and HelloForeverAssist.ask.n == 2)
  A.Drop("ask")
  -- the window
  HelloLinkAssist = link({ cards = {}, left = 123 })
  advance(1.5)
  slash("assist")
  local w = _G.HelloForeverAssistWindow
  check("the window has a button for the topic, live with the assistant on", w.topics and w.topics.session and not w.topics.session.off)
  check("the state line says the slots left and when a set was last taken",
    w.stateLine:GetText():find("123", 1, true) ~= nil and w.stateLine:GetText():find("s ago", 1, true) ~= nil, w.stateLine:GetText())
  w.topics.session.scripts.OnClick(w.topics.session)
  check("the topic's button asks as the command does", HelloForeverAssist.ask.n == 3 and HelloForeverAssist.ask.topic == "session")
  A.Drop("ask")
  HelloLinkAssist = link({ strip = false, cards = {} })
  advance(1.5) -- the tick reads it
  w:Hide(); w:Show()
  check("the state line says the strip is off", w.stateLine:GetText() == A.Lang.en.state_off)
  slash("assist off")
  w:Hide(); w:Show()
  check("with the assistant off the topic's button is greyed", w.topics.session.off == true)
  w.topics.session.scripts.OnClick(w.topics.session)
  check("...and asks nothing", HelloForeverAssist.ask.n == 3 and HelloForeverAssist.on == false)
  slash("ask session")
  check("/hello ask with the assistant off says so", printed[#printed]:find("off", 1, true) ~= nil and HelloForeverAssist.ask.n == 3)
  slash("assist lang yue")
  check("HelloForeverAssist follows the language", HelloForeverAssist.lang == "yue")
  slash("assist lang en")
  w:Hide()
  HelloLinkAssist = nil
end

realprint("== A13. review round 1 of #130: rawget only, a copy read out of combat, every field compared")
do
  local A = ns.Assist
  slash("assist on")
  local function card(o)
    local c = { id = "session", kind = "event", prio = 3, src = "companion", at = time() - 5, ttl = 600, text = "from outside", basis = "the strip" }
    for k, v in pairs(o or {}) do c[k] = v end
    return c
  end
  local function link(o)
    local t = { strip = true, session = 4711, seq = 1, t = time(), cards = { card() }, left = 150, taken = 1, refused = 0 }
    for k, v in pairs(o or {}) do t[k] = v end
    return t
  end
  local function keys() local out = {} for _, c in ipairs(A.Cards()) do out[#out + 1] = c.key end table.sort(out) return table.concat(out, ",") end
  -- a state card from outside sent away comes back when its condition ended and came back
  local bags = card({ id = "bags", kind = "state", prio = 2, text = "bags: 2 free" })
  HelloLinkAssist = link({ cards = { bags } }); advance(1.5)
  local bar = _G.HelloForeverAssistBar
  check("an outside state card shows", A.Shown() and A.Shown().key == "out:bags")
  bar.scripts.OnMouseUp(bar, "RightButton")
  advance(1.5)
  check("...sent away, it stays away while the sets carry it", keys() == "")
  HelloLinkAssist = link({ cards = {} }); advance(1.5)
  HelloLinkAssist = link({ cards = { bags } }); advance(1.5)
  check("...and shows again after a set came without it", keys() == "out:bags")
  -- every field compared: src and ttl (the same at, so only that field differs)
  local AT = time() - 5
  HelloLinkAssist = link({ cards = { card({ at = AT }) } }); advance(1.5)
  HelloLinkAssist = link({ cards = { card({ at = AT, src = "ai" }) } }); advance(1.5)
  check("a change of src alone is taken", A.Cards()[1] and A.Cards()[1].src == "ai" and bar.text:GetText():sub(1, 3) == "AI ")
  HelloLinkAssist = link({ cards = { card({ at = AT, src = "ai", ttl = 10 }) } }); advance(1.5)
  advance(6)
  check("a change of ttl alone is taken (the card goes at its new time)", keys() == "")
  -- rawget only: a table with a metatable runs no code
  local calls = 0
  local trap = { __index = function() calls = calls + 1 return nil end }
  HelloLinkAssist = setmetatable(link({ cards = { setmetatable(card(), trap) } }), trap)
  setmetatable(HelloLinkAssist.cards, trap)
  advance(3)
  check("HelloLink's table and its cards are read with rawget only: no __index runs", calls == 0, calls)
  -- a table not as the spec has it counts as absent
  HelloLinkAssist = link(); HelloLinkAssist.strip = nil; advance(1.5)
  check("a table without strip counts as absent: no card, and a question is not asked", keys() == "")
  local n = HelloForeverAssist.ask and HelloForeverAssist.ask.n or 0
  slash("ask session")
  check("...and /hello ask says HelloLink is not there", (HelloForeverAssist.ask and HelloForeverAssist.ask.n or 0) == n)
  for label, bad in pairs({ ["an at that is NaN"] = { at = 0 / 0 }, ["a negative ttl"] = { ttl = -5 }, ["a text of two lines"] = { text = "one\ntwo" } }) do
    HelloLinkAssist = link({ cards = { card(bad) } }); advance(1.5)
    check("a card with " .. label .. " is not taken", keys() == "")
  end
  -- out of combat only: in a fight a command reads the copy, not HelloLink's table
  HelloLinkAssist = link({ cards = {} }); advance(1.5)
  inCombat = true; restrictState = 2; fire("PLAYER_REGEN_DISABLED")
  HelloLinkAssist = setmetatable({}, { __index = function() error("read in a fight") end })
  local ok = pcall(slash, "ask session")
  check("in a fight /hello ask asks from the copy read before it, and HelloLink's table is not touched",
    ok and HelloForeverAssist.ask.n == n + 1)
  inCombat = false; restrictState = 0; fire("PLAYER_REGEN_ENABLED"); advance(3)
  A.Drop("ask")
  -- the answer is taken also with outside off
  HelloLinkAssist = link({ cards = {} }); advance(1.5)
  slash("assist outside off")
  slash("ask session")
  local asked = HelloForeverAssist.ask.n
  HelloLinkAssist = link({ cards = {}, re = asked }); advance(1.5)
  advance(31)
  check("with outside off the answer still takes the asked card away; no 'no answer' later",
    not (A.Shown() and A.Shown().id == "ask"))
  slash("assist outside on")
  -- the state line follows the slots left with no card change
  HelloLinkAssist = link({ cards = {}, left = 100 }); advance(1.5)
  slash("assist")
  local w = _G.HelloForeverAssistWindow
  HelloLinkAssist = link({ cards = {}, left = 99 }); advance(1.5)
  check("the open window's state line follows the slots left", w.stateLine:GetText():find("99", 1, true) ~= nil, w.stateLine:GetText())
  w:Hide()
  HelloLinkAssist = nil; advance(1.5)
  slash("assist off")
end

realprint("== A14. the state line while the assistant is off (#131, the game check of 15 Nov 2026)")
do
  slash("assist off")
  local live = { id = "while-off", kind = "event", prio = 1, src = "companion", at = time() - 5, ttl = 600, text = "must not show", basis = "test" }
  HelloLinkAssist = { strip = true, session = 4711, seq = 1, t = time(), cards = { live }, left = 77, taken = 1, refused = 0 }
  advance(1.5)
  check("with the assistant off a good card from HelloLink is not taken", #ns.Assist.Cards() == 0)
  slash("assist")
  local w = _G.HelloForeverAssistWindow
  check("with the assistant off the state line says what HelloLink says, not that it is not loaded",
    w.stateLine:GetText():find("77", 1, true) ~= nil, w.stateLine:GetText())
  HelloLinkAssist = { strip = false, session = 4711, cards = {} }
  advance(1.5)
  check("...and follows it while the window is open", w.stateLine:GetText() == ns.Assist.Lang.en.state_off, w.stateLine:GetText())
  check("...and takes no card while off", #ns.Assist.Cards() == 0)
  w:Hide()
  HelloLinkAssist = nil; advance(1.5)
end

realprint("== A15. the target card (#136)")
do
  local A = ns.Assist
  local function settle() for _ = 1, 60 do advance(0.5) if ns.fightStatus.state == "idle" then return end end end
  slash("assist on")
  local tguid
  local realGUID = UnitGUID
  UnitGUID = function(u) if u == "target" then return tguid end return realGUID(u) end
  local function target(g) tguid = g; fire("PLAYER_TARGET_CHANGED"); advance(0.2) end
  local function card() for _, c in ipairs(A.Cards()) do if c.id == "target" then return c end end end
  local mobs = { { "Creature-0-1-1300", 4200, "Target Boar" } }
  local GUID = "Creature-0-6848-1-6-4200-3A407B17AB"
  target(GUID)
  check("no card for a creature with no fights", card() == nil)
  for i, d in ipairs({ 10, 12 }) do advance(2); fightOnce(1300 + i, "Target Boar", d, { mobs = mobs }); settle() end
  target(nil); target(GUID)
  check("no card under 3 fights", card() == nil)
  advance(2); fightOnce(1303, "Target Boar", 14, { mobs = mobs }); settle()
  target(nil); target(GUID)
  check("a card at exactly 3 fights", card() and card().text == "Target Boar: usual 12 s, taken 40, died 0 of 3", card() and card().text)
  advance(2); fightOnce(1304, "Target Boar", 16, { mobs = mobs }); settle()
  target(nil)
  check("no card without a target", card() == nil)
  target(GUID)
  local c = card()
  check("the target card: the usual length, damage taken and deaths of its key", c and c.text == "Target Boar: usual 13 s, taken 40, died 0 of 4" and c.kind == "state" and c.prio == 3,
    c and c.text)
  check("...it says what it stands on", c and c.basis == ("4 fights at level %d"):format(P.level))
  check("...and the bar shows it", A.Shown() and A.Shown().id == "target")
  local n0 = C().assist.target and C().assist.target.shown
  advance(2)                                   -- a later second: a card put again would be a new one
  target(GUID)
  check("the same target again is not a new card", C().assist.target.shown == n0)
  target("Player-1-0ABCDEF")
  check("a player is no creature: the card goes", card() == nil)
  target("Creature-0-6848-1-6-4200-")
  check("a GUID not as the client gives it: no card", card() == nil)
  local asked, realCall = 0, ns.Call
  ns.Call = function(fn, ...) if fn == UnitGUID then asked = asked + 1 end return realCall(fn, ...) end
  target(setmetatable({}, getmetatable(S())))
  ns.Call = realCall
  check("a secret GUID: no card, and the GUID was read through the guard that drops a secret", card() == nil and asked >= 1, asked)
  -- another level, the same creature
  P.level = P.level + 1
  target(GUID)
  check("at another level the key is another: no card", card() == nil)
  P.level = P.level - 1
  -- in combat the rule does not run; after the fight it does
  target(nil)
  inCombat = true; restrictState = 2; fire("PLAYER_REGEN_DISABLED")
  target(GUID)
  check("in combat a new target gives no card", card() == nil)
  inCombat = false; restrictState = 0; fire("PLAYER_REGEN_ENABLED"); advance(3)
  check("...after the fight it does", card() ~= nil)
  -- a death makes it prio 2
  advance(2); fightOnce(1305, "Target Boar", 15, { mobs = mobs, died = true }); settle()
  target(nil); target(GUID)
  c = card()
  check("after a death against it the card is prio 2 and counts it", c and c.prio == 2 and c.text:find("died 1 of 5", 1, true), c and c.text)
  -- sent away, then the target goes and comes back: the card shows again (section 3)
  local bar = _G.HelloForeverAssistBar
  if A.Shown() and A.Shown().id == "target" then bar.scripts.OnMouseUp(bar, "RightButton") end
  target(GUID)
  check("sent away, it stays away while the target stays", card() == nil)
  target(nil); target(GUID)
  check("...and shows again after the target went and came back", card() ~= nil)
  -- a death seen, with fewer than 3 fights that know whether they died: still prio 2
  C().baseline["4300:" .. P.level] = { name = "Half Known", t = time(), fights = {
    { key = "hf1-h-1", dur = 10, taken = 50, died = true }, { key = "hf1-h-2", dur = 12, taken = 50 }, { key = "hf1-h-3", dur = 14, taken = 50 } } }
  target("Creature-0-6848-1-6-4300-AB12")
  c = card()
  check("a death seen with fewer than 3 that know: prio 2, and no death count in the text",
    c and c.prio == 2 and c.text == "Half Known: usual 12 s, taken 50", c and (c.prio .. " " .. c.text))
  C().baseline["4300:" .. P.level] = nil
  slash("assist lang yue"); target(nil); target(GUID)
  c = card()
  check("in Cantonese", c and c.text:find("平時", 1, true) ~= nil, c and c.text)
  slash("assist lang en")
  UnitGUID = realGUID
  target(nil)
  for sid = 1301, 1305 do sessions[sid] = nil end
  slash("assist off")
end
realprint("== A16. the gold card: hours of play from the timeline")
do
  local A = ns.Assist
  local PlayHours = ns.PlayHours or function() return nil end -- missing: each check fails by name
  local realTL = C().timeline
  local function joined(h) return h and table.concat(h, " ") end
  -- A timeline as TimelineTick writes it: a keyframe, then an entry a tick (300 s) while in the
  -- game; `money` only when it changed.
  local function play(tl, from, to, changes)
    for t = from + 300, to, 300 do tl[#tl + 1] = { t = t, last = t, n = 1, money = changes[t - from] } end
  end
  local t0 = time() - 30 * 3600
  -- Hour gains 15000 and 32000, two hours logged out, then 20000 and 1200 s more.
  local tl = { { t = t0, last = t0, n = 1, k = true, zone = "Z", subzone = "", level = 20, xp = 0, money = 10000 } }
  play(tl, t0, t0 + 7200, { [1500] = 25000, [5100] = 57000 })
  local L = t0 + 14400
  tl[#tl + 1] = { t = L, last = L, n = 1, k = true, zone = "Z", subzone = "", level = 20, xp = 0, money = 57000 }
  play(tl, L, L + 4800, { [1500] = 77000 })
  local hours, since, lastAt = PlayHours(tl)
  check("play hours, newest first, counted back from the last moment; the logged-out gap not counted",
    joined(hours) == "20000 32000 15000" and lastAt == L + 4800, tostring(joined(hours)) .. " / " .. tostring(lastAt))
  local sinceOk = type(since) == "function"
  check("...the play after a moment: none in the gap", sinceOk and since(t0 + 3600) == 3600 + 4800, sinceOk and since(t0 + 3600))
  check("...a gap is only a gap when no tick spans it",
    joined(PlayHours({ { t = t0, last = t0, n = 1, money = 0 }, { t = t0 + 300, last = t0 + 7200, n = 1, money = 0 } })) == "0 0")
  check("a timeline that knows no money gives no hours", PlayHours({ { t = t0, last = t0 + 4000, n = 1 } }) == nil)
  check("a change of money at the moment an hour ends belongs to that hour",
    joined(PlayHours({ { t = t0, last = t0 + 3600, n = 1, money = 0 }, { t = t0 + 3600, last = t0 + 7200, n = 1, money = 500 },
      { t = t0 + 7200, last = t0 + 7200, n = 1, money = 600 } })) == "100 500")
  local trimmed = {}
  for _, e in ipairs(tl) do if e.t >= t0 + 1000 then trimmed[#trimmed + 1] = e end end
  check("a trim of the timeline's head moves no recent hour", joined(PlayHours(trimmed)) == "20000 32000",
    joined(PlayHours(trimmed)))

  -- The card: four complete hours before this login, in one stretch of play.
  local function card() for _, c in ipairs(A.Cards()) do if c.id == "gold" then return c end end end
  local function tick() ns.Notify("TIMELINE"); advance(0.2) end
  local h = { { t = t0, last = t0, n = 1, k = true, zone = "Z", subzone = "", level = 20, xp = 0, money = 0 } }
  play(h, t0, t0 + 14400, { [1800] = 15000, [5400] = 47000, [9000] = 67000, [12600] = 79000 })
  slash("assist on")
  C().timeline = h
  ns.ResetSession() -- a login
  tick()
  check("hours played before this login give no card, though there are four", card() == nil)
  play(h, t0 + 14400, t0 + 18000, { [1800] = 91005 })  -- an hour of play: +12005
  tick()
  local c = card()
  check("after an hour of play: the gold card, against the median of the earlier hours",
    c and c.text == "This hour: 1 g 20 s 5 c, usual 1 g 75 s" and c.kind == "event" and c.prio == 3, c and c.text)
  check("...it says what it stands on", c and c.basis == "median of 4 earlier hours of play", c and c.basis)
  A.Drop("gold")
  tick()
  check("no more play: no new card", card() == nil)
  play(h, t0 + 18000, t0 + 19800, { [600] = 90700 })   -- half an hour: -305
  tick()
  check("half an hour of play: no card", card() == nil)
  play(h, t0 + 19800, t0 + 21600, {})
  tick()
  c = card()
  check("the next full hour: a card; an hour that cost money",
    c and c.text == "This hour: -3 s 5 c, usual 1 g 50 s" and c.basis == "median of 5 earlier hours of play", c and c.text)
  A.Drop("gold")
  for i = #h, 1, -1 do if h[i].t < t0 + 2000 then table.remove(h, i) end end   -- the head trimmed
  tick()
  check("a trim of the timeline's head gives no card", card() == nil)
  slash("assist lang yue")
  play(h, t0 + 21600, t0 + 25200, { [600] = 100700 })
  tick()
  c = card()
  check("in Cantonese", c and c.text == "呢個鐘：1 g，平時 1 g 20 s 2 c" and c.basis == "之前 4 個鐘嘅中位數", c and c.text)
  slash("assist lang en")
  A.Drop("gold")
  inCombat = true; restrictState = 2; fire("PLAYER_REGEN_DISABLED")
  play(h, t0 + 25200, t0 + 28800, { [600] = 110700 })
  tick()
  check("in a fight: no gold card", card() == nil)
  inCombat = false; restrictState = 0; fire("PLAYER_REGEN_ENABLED"); advance(3)
  check("...after the fight it comes", card() ~= nil)
  A.Drop("gold")
  -- too few earlier hours
  local few = { { t = t0, last = t0, n = 1, k = true, money = 0 } }
  play(few, t0, t0 + 7200, { [1800] = 100 })
  C().timeline = few
  ns.ResetSession()
  tick()
  play(few, t0 + 7200, t0 + 10800, { [1800] = 200 })
  tick()
  check("with fewer than 3 earlier hours: no gold card", card() == nil)
  -- money the client cannot give is not written as 0
  C().timeline = realTL
  local n0, money = #realTL, P.money
  P.money = nil
  ns.TimelineTick(true)
  check("money the client cannot give: the timeline tick is skipped, not written as 0", #realTL == n0, #realTL - n0)
  P.money = money
  -- TimelineTick says so to its listeners
  local heard = 0
  ns.Listen("TIMELINE", function() heard = heard + 1 end)
  ns.TimelineTick(false)
  check("TimelineTick tells its listeners (the gold card's rule)", heard == 1, heard)
  slash("assist off")
end
realprint("== A17. the ammo card")
do
  local A = ns.Assist
  local ammo, itemName = nil, "Rough Arrow"
  local realInvId, realItemInfo, realInfo = GetInventoryItemID, GetItemInfo, C_Container.GetContainerItemInfo
  GetInventoryItemID = function(unit, slot) if slot == 0 then return ammo end if realInvId then return realInvId(unit, slot) end end
  GetItemInfo = function(id) if id == 2512 then return itemName end end
  local function card() for _, c in ipairs(A.Cards()) do if c.id == "ammo" then return c end end end
  local function bags() fire("BAG_UPDATE_DELAYED"); advance(0.3) end
  local saved = { bagItems[0][2], bagItems[0][3] }
  slash("assist on")
  bagItems[0][2] = { id = 2512, count = 150 }
  bags()
  check("no ammunition in its slot: no card, whatever the bags hold", card() == nil)
  ammo = 2512
  fire("PLAYER_EQUIPMENT_CHANGED"); advance(0.3)
  local c = card()
  check("the ammunition slot holds an item, the bags fewer than 200: the card, prio 2",
    c and c.text == "Rough Arrow: 150 left" and c.kind == "state" and c.prio == 2, c and c.text)
  check("...it says what it stands on", c and c.basis == "the ammunition slot and the bags", c and c.basis)
  bagItems[0][3] = { id = 2512, count = 100 }
  bags()
  check("200 or more, all stacks counted: no card", card() == nil)
  bagItems[0][3] = nil; bagItems[0][2].count = 40
  bags()
  c = card()
  check("under 50: prio 1", c and c.prio == 1 and c.text == "Rough Arrow: 40 left", c and (c.prio .. " " .. c.text))
  local shown = C().assist.ammo and C().assist.ammo.shown
  advance(2); bags()
  check("the same count again is not a new card", shown ~= nil and (C().assist.ammo and C().assist.ammo.shown) == shown, shown)
  -- The secret mock is a table, which a type check would refuse too: the check is that the
  -- guard was asked about the value (a real secret is a number, and passes a type check).
  local realIsSecret, asked = ns.IsSecret, {}
  ns.IsSecret = function(v) if getmetatable(v) == SECRET_MT then asked[#asked + 1] = "secret" end return realIsSecret(v) end
  bagItems[0][2].count = S()
  bags()
  check("a secret stack count: no card, not a smaller count; the guard was asked about it", card() == nil and #asked >= 1, #asked)
  bagItems[0][2].count = 40
  C_Container.GetContainerItemInfo = function(bag, slot) if slot == 5 then error("not now") end return realInfo(bag, slot) end
  bags()
  check("a slot that cannot be read: no card, not a count without it", card() == nil)
  C_Container.GetContainerItemInfo = realInfo
  asked = {}
  ammo = S()
  fire("PLAYER_EQUIPMENT_CHANGED"); advance(0.3)
  check("a secret ammunition slot: no card; the guard was asked about it", card() == nil and #asked >= 1, #asked)
  ns.IsSecret = realIsSecret
  ammo, itemName = 2512, nil
  bags()
  check("an item the client has no name for yet: the word for ammunition", card() and card().text == "Ammunition: 40 left", card() and card().text)
  itemName = "Rough Arrow"
  inCombat = true; restrictState = 2; fire("PLAYER_REGEN_DISABLED")
  bagItems[0][2].count = 39
  bags()
  check("in a fight the count waits (a shot changes it)", card() and card().text == "Ammunition: 40 left", card() and card().text)
  inCombat = false; restrictState = 0; fire("PLAYER_REGEN_ENABLED"); advance(3)
  check("...after the fight it is read", card() and card().text == "Rough Arrow: 39 left", card() and card().text)
  slash("assist lang yue"); bagItems[0][2].count = 38; bags()
  check("in Cantonese", card() and card().text == "Rough Arrow：剩 38" and card().basis == "彈藥格同背包", card() and card().text)
  slash("assist lang en")
  slash("assist off")
  slash("assist on"); advance(0.3)
  check("turned on with few arrows already: the card, with no bag or gear event", card() and card().text == "Rough Arrow: 38 left",
    card() and card().text)
  ammo = nil
  fire("PLAYER_EQUIPMENT_CHANGED"); advance(0.3)
  check("the ammunition taken off: the card goes", card() == nil)
  bagItems[0][2], bagItems[0][3] = saved[1], saved[2]
  GetInventoryItemID, GetItemInfo = realInvId, realItemInfo
  bags()
  slash("assist off")
end
realprint("== A18. the bags card")
do
  local A = ns.Assist
  local free = 10
  C_Container.CalculateTotalNumberOfFreeBagSlots = function() return free end
  local function card() for _, c in ipairs(A.Cards()) do if c.id == "bags" then return c end end end
  local function bags() fire("BAG_UPDATE_DELAYED"); advance(0.3) end
  slash("assist on")
  bags()
  check("10 free bag slots: no card", card() == nil)
  free = 2; bags()
  local c = card()
  check("2 free: the card, prio 2", c and c.text == "Bags: 2 free" and c.kind == "state" and c.prio == 2, c and c.text)
  check("...it says what it stands on", c and c.basis == "the game's count of free bag slots", c and c.basis)
  free = 0; bags()
  check("none free: prio 1", card() and card().prio == 1 and card().text == "Bags: 0 free", card() and card().text)
  local shown = C().assist.bags and C().assist.bags.shown
  advance(2); bags()
  check("the same count again is not a new card", shown ~= nil and (C().assist.bags and C().assist.bags.shown) == shown, shown)
  local realIsSecret, asked = ns.IsSecret, 0
  ns.IsSecret = function(v) if getmetatable(v) == SECRET_MT then asked = asked + 1 end return realIsSecret(v) end
  free = S(); bags()
  check("a secret count: no card, not a count of 0; the guard was asked about it", card() == nil and asked >= 1, asked)
  ns.IsSecret = realIsSecret
  free = 1; bags()
  C_Container.CalculateTotalNumberOfFreeBagSlots = function() error("not now") end
  bags()
  check("a count the client fails to give: the card goes", card() == nil)
  C_Container.CalculateTotalNumberOfFreeBagSlots = function() return free end
  bags()
  local before = card() ~= nil
  C_Container.CalculateTotalNumberOfFreeBagSlots = nil
  bags()
  check("a client without the call: the card there goes", before and card() == nil, before)
  C_Container.CalculateTotalNumberOfFreeBagSlots = function() return free end
  inCombat = true; restrictState = 2; fire("PLAYER_REGEN_DISABLED")
  bags()
  check("in a fight the rule waits", card() == nil)
  inCombat = false; restrictState = 0; fire("PLAYER_REGEN_ENABLED"); advance(3)
  check("...after the fight it runs", card() and card().text == "Bags: 1 free", card() and card().text)
  slash("assist lang yue"); free = 2; bags()
  check("in Cantonese", card() and card().text == "背包：剩 2 格" and card().basis == "遊戲計嘅背包空格", card() and card().text)
  slash("assist lang en")
  slash("assist off"); slash("assist on"); advance(0.3)
  check("turned on with full bags already: the card, with no bag event", card() and card().text == "Bags: 2 free", card() and card().text)
  free = 3; bags()
  check("3 free: the card goes", card() == nil)
  C_Container.CalculateTotalNumberOfFreeBagSlots = nil
  slash("assist off")
end
realprint("== A19. the settings window: every setting and action that had a command only")
do
  local s = HelloForeverDB.settings
  slash("settings")
  local w = _G.HelloForeverSettings
  check("/hello settings opens the settings window", w ~= nil and w:IsShown())
  local c = w and w.controls or {}
  local function click(key) local b = c[key] if b and b.scripts.OnClick then b.scripts.OnClick(b, "LeftButton") end end
  -- each command of /hello that sets something or acts, and the control that stands for it
  local COMMANDS = { show = "show", hide = "show", lock = "lock", unlock = "lock", scale = "scale+",
    resetpos = "resetpos", announce = "announce", baseline = "baseline", ["baseline reset"] = "baseline reset",
    combatlog = "combatlog auto", budget = "budget+", purge = "purge 30", assist = "assist" }
  local missing = {}
  for cmd, key in pairs(COMMANDS) do if not c[key] then missing[#missing + 1] = cmd end end
  check("every command that sets something or acts has a control", next(COMMANDS) ~= nil and #missing == 0, table.concat(missing, " "))
  local shown, locked, scale, announce, baseline, mode, budget = s.shown, s.locked, s.scale, s.announce, s.baseline, s.combatLog, s.budgetMB
  click("show"); click("lock"); click("announce"); click("baseline")
  check("the toggles: panel shown, locked, the fight line, the baseline line",
    s.shown == not shown and s.locked == not locked and s.announce == not announce and s.baseline == not baseline)
  check("...and the window says so", c.lock ~= nil and c.lock.label.text:find(s.locked and "[x]" or "[  ]", 1, true) ~= nil, c.lock and c.lock.label.text)
  click("show"); click("lock"); click("announce"); click("baseline")
  click("scale+")
  check("scale + is a tenth more, and the panel has it", math.abs(s.scale - (scale + 0.1)) < 1e-9 and math.abs((HelloForeverFrame.scale or 0) - s.scale) < 1e-9, s.scale)
  click("scale-")
  check("...and - a tenth less", math.abs(s.scale - scale) < 1e-9, s.scale)
  local logs0 = #logCalls
  click("combatlog on")
  check("the combat log file: on turns the client's combat log on", logCalls[#logCalls] == true and #logCalls > logs0, #logCalls - logs0)
  click("combatlog auto")
  check("the combat log file: auto", s.combatLog == "auto" and c["combatlog auto"] ~= nil and c["combatlog auto"].label.text:find("[x]", 1, true) ~= nil)
  click("combatlog " .. (mode or "off"))
  for _ = 1, 30 do click("budget+") end
  check("the budget goes up to 20 MB and no further", s.budgetMB == 20, s.budgetMB)
  for _ = 1, 30 do click("budget-") end
  check("...and down to 1 MB", s.budgetMB == 1, s.budgetMB)
  s.budgetMB = budget
  ns.db.pos = { "TOP", 0, -40 }
  click("resetpos")
  check("reset position", ns.db.pos == nil)
  -- an action that empties data asks for a second click
  C().baseline = { ["1:1"] = { name = "Kept", fights = {} } }
  click("baseline reset")
  check("empty the baseline, one click: nothing emptied, the button asks again",
    C().baseline["1:1"] ~= nil and c["baseline reset"] ~= nil and c["baseline reset"].label.text:find("Click again", 1, true) ~= nil)
  advance(6); click("baseline reset")
  check("...a second click after 5 s only asks again", C().baseline["1:1"] ~= nil)
  click("baseline reset")
  check("...a second click within 5 s empties it", C().baseline["1:1"] == nil)
  local asked, realPurge = {}, ns.FightsPurge
  ns.FightsPurge = function(days) asked[#asked + 1] = days return 0, 0 end
  click("purge 90")
  check("drop old fights, one click: nothing dropped", #asked == 0)
  click("purge 90")
  check("...the second click drops the fights over 90 days", asked[1] == 90, asked[1])
  click("purge 30"); click("purge 30")
  check("...and the other button over 30 days", asked[2] == 30, asked[2])
  ns.FightsPurge = realPurge
  local function tickWin() if w.scripts.OnUpdate then w.scripts.OnUpdate(w, 0.6) end end
  -- a command changes a setting while the window is open: the window follows
  slash("lock")
  tickWin()
  check("a setting changed by a command shows in the open window", c.lock and c.lock.label.text:find("[x]", 1, true) ~= nil, c.lock and c.lock.label.text)
  slash("unlock")
  click("baseline reset"); advance(6); tickWin()
  check("a second click's time over: the button's own text again", c["baseline reset"] and c["baseline reset"].label.text == "Empty the fight baseline",
    c["baseline reset"] and c["baseline reset"].label.text)
  click("assist")
  check("open the assistant", _G.HelloForeverAssistWindow ~= nil and _G.HelloForeverAssistWindow:IsShown())
  if _G.HelloForeverAssistWindow then _G.HelloForeverAssistWindow:Hide() end
  slash("settings")
  check("/hello settings again closes it", w ~= nil and not w:IsShown())
  local panel = HelloForeverFrame
  panel.scripts.OnMouseUp(panel, "RightButton")
  local item
  for _, it in ipairs(menuItems) do if it.text == "Settings" then item = it end end
  if item then item.fn() end
  check("the panel's menu opens it", item ~= nil and w ~= nil and w:IsShown())
  if w then w:Hide() end
end
]==]

local chunk = assert(loadstring(src:sub(1, at - 1) .. more .. src:sub(at), "=fights_harness_v4+assist"))
chunk(...)
