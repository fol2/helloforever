-- HelloLink spike: text written by tools/hellolink.py reaches the addon through a
-- load-on-demand slot, with no reload. Usage: lua tests/hellolink_test.lua <AddOns dir>
-- where the dir was filled by `python3 tools/hellolink.py install <dir> --slots 3`.
-- ASSUMED client behaviour (plan/05): LoadAddOn reads the slot's file from disk when it is
-- called, once per slot per UI session, and returns false for a missing or loaded slot.
local DIR = assert(arg[1], "usage: hellolink_test.lua <AddOns dir>")
local TOOL = "python3 " .. (os.getenv("HELLOLINK_TOOL") or "tools/hellolink.py")
local out, loaded, timers = {}, {}, {}
print_real = print
print = function(...) out[#out + 1] = table.concat({ ... }, " ") end
SlashCmdList = {}
C_Timer = { After = function(_, fn) timers[#timers + 1] = fn end }
C_AddOns = { LoadAddOn = function(name)
  if loaded[name] then return true end -- a loaded addon is not read again
  local chunk = loadfile(DIR .. "/" .. name .. "/Inbox.lua")
  if not chunk then return false, "MISSING" end
  loaded[name] = true
  chunk(name, {})
  return true
end }
local function write(text) -- the text goes in on stdin, so no shell quoting touches it
  local p = assert(io.popen(("%s write '%s' -"):format(TOOL, DIR), "w"))
  p:write(text); p:close()
end
local function slash(m) out = {}; SlashCmdList["HELLOLINK"](m or "") return table.concat(out, "\n") end
local fails, n = 0, 0
local function check(name, cond) n = n + 1; if not cond then fails = fails + 1 end print_real((cond and "PASS " or "FAIL ") .. name) end

assert(loadfile(DIR .. "/HelloLink/HelloLink.lua"))("HelloLink", {})
local FIRST = "first 你好 \"quoted\" \\ back\nline two\t1 tab and \0012 a control byte before a digit"
write(FIRST)
local a = slash()
check("the slot holds the text the tool wrote, byte for byte", HelloLink_Inbox.text == FIRST)
check("a poll shows it, line by line", a:find("first 你好 \"quoted\" \\ back", 1, true) and a:find("\n  line two\t1 tab", 1, true))
check("the poll used slot 1", loaded.HelloLink_S001 and not loaded.HelloLink_S002)
write("second")
local b = slash()
check("a newer write is seen by the next poll, through a fresh slot", b:find("second", 1, true) and loaded.HelloLink_S002)
local c = slash()
check("an unchanged inbox is reported as nothing new", c:find("nothing new", 1, true) and loaded.HelloLink_S003)
local d = slash()
check("an empty pool is reported, with the way out", d:find("no slot left", 1, true) and d:find("/reload", 1, true))
do -- sixteen writers at once: every slot ends with one writer's whole file, and no temporary file stays
  -- each writer's exit status is collected: a writer that lost the race must not pass unseen
  local rc = os.execute(("pids=; for i in 1 2 3 4 5 6 7 8 9 10 11 12 13 14 15 16; do %s write '%s' \"racer $i\" >/dev/null 2>&1 & pids=\"$pids $!\"; done; "
    .. "rc=0; for p in $pids; do wait $p || rc=1; done; exit $rc"):format(TOOL, DIR))
  local whole = rc == 0 or rc == true
  for i = 1, 3 do
    HelloLink_Inbox = nil
    local chunk = loadfile(("%s/HelloLink_S%03d/Inbox.lua"):format(DIR, i))
    if chunk then chunk() end
    whole = whole and type(HelloLink_Inbox) == "table" and tostring(HelloLink_Inbox.text):match("^racer %d+$") ~= nil
  end
  local ls = io.popen(("ls -A '%s'/HelloLink_S*"):format(DIR)); local names = ls:read("*a"); ls:close()
  check("concurrent writes leave whole files and no temporary file", whole and not names:find(".inbox-", 1, true))
end
-- the reader's request to the live-state strip rides in the same file (docs/specs/29.md, section 3)
os.execute(("%s write '%s' '' --strip-session 4711 >/dev/null"):format(TOOL, DIR))
HelloLink_Inbox = nil
local asked = loadfile(DIR .. "/HelloLink_S001/Inbox.lua")
if asked then asked() end
check("a slot written with --strip-session holds the request as a table the addon can read",
  type(HelloLink_Inbox) == "table" and type(HelloLink_Inbox.strip) == "table" and HelloLink_Inbox.strip.session == 4711 and HelloLink_Inbox.strip.depth == 2)
print_real(("== %d checks, %d failed"):format(n, fails))
os.exit(fails == 0 and 0 or 1)
