-- HelloLink spike: text written by tools/hellolink.py reaches the addon through a
-- load-on-demand slot, with no reload. Usage: lua tests/hellolink_test.lua <AddOns dir>
-- where the dir was filled by `python3 tools/hellolink.py install <dir> --slots 3`.
-- ASSUMED client behaviour (plan/05): LoadAddOn reads the slot's file from disk when it is
-- called, once per slot per UI session, and returns false for a missing or loaded slot.
local DIR = assert(arg[1], "usage: hellolink_test.lua <AddOns dir>")
local TOOL = "python3 tools/hellolink.py"
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
write("first 你好 \"quoted\" \\ back\nline two")
local a = slash()
check("a poll shows the text the tool wrote, byte for byte", a:find("first 你好 \"quoted\" \\ back", 1, true) and a:find("line two", 1, true))
check("the poll used slot 1", loaded.HelloLink_S001 and not loaded.HelloLink_S002)
write("second")
local b = slash()
check("a newer write is seen by the next poll, through a fresh slot", b:find("second", 1, true) and loaded.HelloLink_S002)
local c = slash()
check("an unchanged inbox is reported as nothing new", c:find("nothing new", 1, true) and loaded.HelloLink_S003)
local d = slash()
check("an empty pool is reported, with the way out", d:find("no slot left", 1, true) and d:find("/reload", 1, true))
ReloadUI = function() error("blocked") end
slash("reloadtest"); for _, fn in ipairs(timers) do fn() end
check("reloadtest reports a refused reload instead of breaking", table.concat(out, "\n"):find("refused", 1, true))
print_real(("== %d checks, %d failed"):format(n, fails))
os.exit(fails == 0 and 0 or 1)
