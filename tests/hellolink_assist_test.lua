-- What HelloLink takes from the slot file's `assist` part (docs/specs/115.md, section 6; #127):
-- the hand-written vector, each refusal, the doubled `|`, and the count of slots left.
-- Usage: lua5.1 tests/hellolink_assist_test.lua
local fails, n = 0, 0
local function check(name, cond, detail)
  n = n + 1
  if not cond then fails = fails + 1 end
  print((cond and "PASS " or "FAIL ") .. name .. ((not cond and detail) and ("  -> " .. tostring(detail)) or ""))
end

SlashCmdList, C_Timer = {}, { After = function() end }
local ns = {}
assert(loadfile("HelloLink/HelloLink.lua"))("HelloLink", ns)
local chunk = loadfile("HelloLink/Assist.lua")
check("HelloLink has Assist.lua", chunk ~= nil)
if chunk then chunk("HelloLink", ns) end
local take = ns.AssistTake or function() return {} end

-- the vector, written by hand from the spec
dofile("tests/vectors/assist_inbox.lua")
local V = HelloLink_Inbox
local T = 1794516378
local a = take(V, 4711, T)
local c = a.cards and a.cards[1]
check("the hand-made set is taken for its session", a == HelloLinkAssist and a.taken == 1 and a.refused == 0 and c ~= nil)
check("...with its card as written", c and c.id == "session" and c.kind == "event" and c.prio == 3 and c.src == "companion"
  and c.at == 1794516370 and c.ttl == 600 and c.text == "This session: 42 fights, 1 death, 14,200 XP an hour"
  and c.basis == "the strip since 20:14")
check("...and seq, t, re, the session and the strip on", a.seq == 12 and a.t == T and a.re == 3 and a.session == 4711 and a.strip == true)
check("the slots left: the file's count less the slots used", a.left == 200 - (ns.SlotsUsed and ns.SlotsUsed() or -1))

-- A copy of the vector's part, changed by `f`, taken at `now`.
local function deep(t) if type(t) ~= "table" then return t end local o = {} for k, v in pairs(t) do o[k] = deep(v) end return o end
local function try(f, now, session)
  local inbox = deep(V)
  f(inbox.assist, inbox)
  return take(inbox, session or 4711, now or T)
end
local function refusedSet(name, f, now, session)
  take(V, 4711, T) -- a good set first: a set that is not taken removes its cards
  local r = try(f, now, session)
  check("not taken: " .. name, #r.cards == 0 and r.taken == 0, (#r.cards) .. " cards")
end
refusedSet("a set of another session (left from before a /reload)", function() end, T, 4712)
refusedSet("t more than 180 s before the client's time", function() end, T + 181)
refusedSet("t more than 5 s after it", function() end, T - 6)
check("taken: t 180 s before, and 5 s after", #try(function() end, T + 180).cards == 1 and #try(function() end, T - 5).cards == 1)
refusedSet("no assist part", function(_, inbox) inbox.assist = nil end)
refusedSet("a session that is no whole number", function(s) s.session = 4711.5 end)
refusedSet("a seq that is a string", function(s) s.seq = "12" end)
refusedSet("an re that is negative", function(s) s.re = -1 end)
refusedSet("nine cards", function(s) for i = 2, 9 do s.cards[i] = deep(s.cards[1]) end end)
refusedSet("cards that are no list", function(s) s.cards.x = s.cards[1] end)
check("a set with no re is taken, re absent", try(function(s) s.re = nil end).re == nil)

-- one card dropped and counted, the others taken
local function oneBad(name, f)
  local r = try(function(s)
    s.cards[2] = deep(s.cards[1]); s.cards[2].id = "bad"
    f(s.cards[2])
  end)
  check("dropped and counted: " .. name, #r.cards == 1 and r.cards[1].id == "session" and r.taken == 1 and r.refused == 1)
end
oneBad("no basis", function(x) x.basis = nil end)
oneBad("an empty text", function(x) x.text = "" end)
oneBad("a src of addon", function(x) x.src = "addon" end)
oneBad("an at after t", function(x) x.at = T + 1 end)
oneBad("a ttl under 10", function(x) x.ttl = 9 end)
oneBad("a prio of 4", function(x) x.prio = 4 end)
oneBad("a kind that is neither", function(x) x.kind = "news" end)
oneBad("an id with a space", function(x) x.id = "a b" end)
oneBad("an id of 25 letters", function(x) x.id = string.rep("a", 25) end)
oneBad("a text of 121 bytes", function(x) x.text = string.rep("x", 121) end)
oneBad("a text of two lines", function(x) x.text = "one\ntwo" end)
oneBad("a text that is not UTF-8", function(x) x.text = "bad \255 byte" end)
oneBad("a detail of 7 lines", function(x) x.detail = "1\n2\n3\n4\n5\n6\n7" end)
do
  local r = try(function(s) s.cards[2] = "not a card" end)
  check("dropped and counted: a card that is no table", #r.cards == 1 and r.refused == 1)
end
local r = try(function(s) s.cards[1].colour = "red"; s.cards[1].detail = "line one\nline two" end)
check("a field the addon does not know is ignored; a detail of two lines is taken",
  #r.cards == 1 and r.cards[1].colour == nil and r.cards[1].detail == "line one\nline two")
r = try(function(s) s.cards[1].text = "|cffff0000red|r and |Hitem:1|h[x]|h"; s.cards[1].basis = "a|b" end)
check("every | of a text from outside is doubled, so no code is drawn",
  r.cards[1].text == "||cffff0000red||r and ||Hitem:1||h[x]||h" and r.cards[1].basis == "a||b")
r = try(function(s) s.cards[1].src = "ai" end)
check("a card of src ai is taken", #r.cards == 1 and r.cards[1].src == "ai")

-- the strip off: no cards from outside
if ns.AssistStrip then ns.AssistStrip(false) end
check("with the strip off the table says so and holds no card", HelloLinkAssist.strip == false and #HelloLinkAssist.cards == 0)
if ns.AssistStrip then ns.AssistStrip(true) end
-- no slot left
if ns.AssistNoSlot then ns.AssistNoSlot() end
check("when the slots are used up the table says none is left", HelloLinkAssist.left == 0)

-- The encoder: a text is data, never code (quotes, backslashes, ]], line breaks, bytes that are
-- not UTF-8). tests/vectors/hard.lua is what the Rust writer makes (reader/hellolink/tests/
-- processes/slots.rs checks its bytes); Lua must read it back byte for byte.
dofile("tests/vectors/hard.lua")
check("the encoder's text comes back from Lua byte for byte",
  X == "say \"hi\" \\ back ]] end --[[ x\nline two\r\0 nul \195\169 \228\189\160\229\165\189\255\254 end", X)
local hc = HelloLink_Inbox.assist.cards[1]
check("...and a hard card comes back as written; a field the spec does not have is not written",
  hc.text == "a \"quote\" ]] and \\ and\nbreak" and hc.basis == "\195\169 ]=] [[x]]" and hc.extra == nil)

print(("== %d checks, %d failed"):format(n, fails))
os.exit(fails == 0 and 0 or 1)
