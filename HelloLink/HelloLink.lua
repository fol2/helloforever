-- HelloLink (spike): does text written by a program outside the game reach the running
-- game without /reload?
--
-- The way in: the client reads a load-on-demand addon's file from disk at the moment the
-- addon is loaded. `tools/hellolink.py install` creates slot addons HelloLink_S001.. before
-- the client starts; `tools/hellolink.py write` puts the same text into every slot; each
-- /hlink loads the next unused slot and shows what it holds. A slot loads once per UI
-- session, so a session has as many polls as there are slots; /reload gives them back.
-- Mechanism described by chelinho139/wow-ai (MIT); nothing here is copied from it.
-- UNVERIFIED in the game: see plan/05-assistant-link.md.
local function say(msg)
    print("|cff66ccffHelloLink|r: " .. msg)
end

local slot, lastSeq = 0, 0

local function loadSlot(name)
    local fn = (_G.C_AddOns and _G.C_AddOns.LoadAddOn) or _G.LoadAddOn
    if type(fn) ~= "function" then return false, "no LoadAddOn on this client" end
    local ok, loaded, why = pcall(fn, name)
    if not ok then return false, loaded end
    return loaded, why
end

local function poll()
    slot = slot + 1
    local name = ("HelloLink_S%03d"):format(slot)
    _G.HelloLink_Inbox = nil
    local ok, why = loadSlot(name)
    local d = _G.HelloLink_Inbox
    if not ok or type(d) ~= "table" then
        say(("no slot left (%s: %s). /reload gives the slots back."):format(name, tostring(why)))
        return
    end
    if d.seq == lastSeq then
        say(("nothing new (slot %d)."):format(slot))
        return
    end
    lastSeq = d.seq
    say(("slot %d, message %s:"):format(slot, tostring(d.seq)))
    for line in tostring(d.text):gmatch("[^\n]+") do print("  " .. line) end
end

-- Is ReloadUI allowed without a key press? If it is, the UI reloads and the last line never
-- shows. (HelloForever's /hello afkreload depends on the answer.)
local function reloadTest()
    say("calling ReloadUI from a timer in 3 s. Do not press anything.")
    _G.C_Timer.After(3, function()
        local ok, err = pcall(_G.ReloadUI)
        say(("still here, so the reload was refused (%s). ReloadUI needs a key press on this client.")
            :format(ok and "no error" or tostring(err)))
    end)
end

SLASH_HELLOLINK1 = "/hlink"
SlashCmdList["HELLOLINK"] = function(msg)
    if (msg or ""):lower():match("^%s*reloadtest") then return reloadTest() end
    poll()
end
