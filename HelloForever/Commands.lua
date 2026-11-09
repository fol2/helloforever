-- HelloForever / Commands.lua
-- The /hello slash command.
local addonName, ns = ...

local type, tostring, tonumber, pairs, next = type, tostring, tonumber, pairs, next
local floor = math.floor
local call = ns.Call

local function say(msg)
    _G.print(ns.PREFIX .. ": " .. msg)
end

local function printApiUsed()
    local a = ns.ApiUsed()
    local c = ns.Char()
    if type(a) ~= "table" or next(a) == nil then
        a = (c.snapshot and c.snapshot._apiUsed) or {}
    end
    _G.print(ns.PREFIX .. " debug _apiUsed:")
    _G.print("  talents=" .. tostring(a.talents)
        .. " cfgType=" .. tostring(a.talentConfigType)
        .. " tabs=" .. tostring(a.talentTabs)
        .. " scanned=" .. tostring(a.talentNodesScanned)
        .. " learned=" .. tostring(a.talentLeaves)
        .. " unspent=" .. tostring(a.talentUnspent))
    _G.print("  talentFirst3=" .. tostring(a.talentFirst))
    local s = c.snapshot
    local tt = s and s.talents
    if type(tt) == "table" and type(tt.tabs) == "table" then
        local parts = {}
        for i = 1, #tt.tabs do
            local tb = tt.tabs[i]
            parts[#parts + 1] = tostring(tb.name) .. "=" .. tostring(tb.points)
        end
        _G.print("  talentTabs: " .. table.concat(parts, "  ")
            .. (tt.spec and ("  spec=" .. tostring(tt.spec.name) .. "#" .. tostring(tt.spec.id)) or ""))
    end
    _G.print("  skills=" .. tostring(a.skills) .. " count=" .. tostring(a.skillCount))
    _G.print("  reputations=" .. tostring(a.reputations) .. " count=" .. tostring(a.repCount))
    _G.print("  quests=" .. tostring(a.quests) .. " count=" .. tostring(a.questCount))
    _G.print("  equipped=" .. tostring(a.equipped) .. " count=" .. tostring(a.equippedCount))
    if s then
        local eqN = 0
        if type(s.equipped) == "table" then for _ in pairs(s.equipped) do eqN = eqN + 1 end end
        _G.print(("  snapshot reason=%s valid=%s level=%s xp=%s/%s money=%s eq=%d tal=%d sk=%d q=%d")
            :format(
                tostring(s.reason), tostring(s._valid),
                tostring(s.level), tostring(s.xp), tostring(s.xpMax),
                tostring(s.money), eqN,
                type(s.talents) == "table" and type(s.talents.nodes) == "table" and #s.talents.nodes or 0,
                type(s.skills) == "table" and #s.skills or 0,
                type(s.quests) == "table" and #s.quests or 0
            ))
    else
        _G.print("  (no snapshot yet)")
    end
    local cl = ns.ClientInfo()
    _G.print(("  client=%s build=%s toc=%s project=%s secrets=%s combat=%s"):format(
        tostring(cl.version), tostring(cl.build), tostring(cl.toc), tostring(_G.WOW_PROJECT_ID),
        tostring(type(_G.issecretvalue) == "function"), tostring(ns.InCombat())))
    _G.print(ns.FightsDebugLine())
end

local HELP = {
    "/hello                     status and this list",
    "/hello ui                  fight history window (or click the panel)",
    "/hello show | hide         XP panel on / off",
    "/hello lock | unlock       pin the panel / allow dragging",
    "/hello scale <0.5-2.5>     panel size",
    "/hello resetpos            put the panel back at the top of the screen",
    "/hello reset               restart the session counters (XP/h, gold, fights)",
    "/hello snap                force a character snapshot",
    "/hello fights [n|read]     last n fights in chat / re-read the meter now",
    "/hello levels [n]          level-up log",
    "/hello announce on|off     one chat line per captured fight",
    "/hello export              fight-log size, budget and trim status",
    "/hello budget <MB>         fight-log size budget per character (1-20)",
    "/hello purge <days>        drop stored fights older than <days> days",
    "/hello combatlog on|off|auto",
    "/hello debug               API / fight-log diagnostics",
}

local function printStatus()
    local level = call(UnitLevel, "player")
    local zone = call(GetZoneText) or "?"
    local sub = call(GetSubZoneText)
    if sub and sub ~= "" then zone = zone .. " - " .. sub end
    say(("level %s, in %s."):format(tostring(level or "?"), zone))
    local perHour, eta = ns.XPRate()
    local n, days, _, bytes, _, budget = ns.FightsStats()
    _G.print(("  v%s  XP/h %s  level in %s  fights %d in %d day(s), %.0f of %.0f KB"):format(
        ns.version, ns.FmtNum(perHour), eta and ns.FmtDur(eta) or "--", n, days, bytes / 1024, budget / 1024))
end

local function onOff(rest, current)
    if rest == "on" then return true end
    if rest == "off" then return false end
    if rest == "" or rest == "toggle" then return not current end
    return nil
end

local commands = {}

commands.help = function()
    printStatus()
    for i = 1, #HELP do _G.print("  " .. HELP[i]) end
end

commands.reset = function()
    ns.ResetSession()
    say("XP counter reset.")
end

commands.snap = function()
    if ns.InCombat() then
        ns.AfterCombat("snap", function() ns.TakeSnapshot("slash") end)
        say("in combat: snapshot queued until the fight ends.")
        return
    end
    local snap = ns.TakeSnapshot("slash")
    say(("snapshot saved (level %s, %s, valid=%s)."):format(
        tostring(snap.level), tostring(snap.zone), tostring(snap._valid)))
end

commands.debug = function()
    -- Force a live collect so the API trace is fresh, without overwriting a good snapshot
    -- with a wipe (TakeSnapshot guards) and never mid-fight.
    if not ns.InCombat() then ns.TakeSnapshot("debug") end
    printApiUsed()
end

commands.fights = function(rest)
    if rest == "read" then ns.FightsKick("slash") end
    local n = tonumber(rest)
    n = n and floor(n) or 5
    if n < 1 then n = 1 elseif n > 50 then n = 50 end
    ns.PrintFights(n)
end

commands.export = function()
    ns.PrintExport()
end

commands.levels = function(rest)
    local n = tonumber(rest)
    ns.PrintLevels(n and n >= 1 and floor(n) or 10)
end

commands.combatlog = function(rest)
    if rest ~= "on" and rest ~= "off" and rest ~= "auto" then
        say("combatlog = " .. tostring(ns.settings.combatLog or "off") .. " (use /hello combatlog on|off|auto)")
        return
    end
    ns.SetCombatLogMode(rest)
    say("combatlog set to " .. rest)
end

commands.announce = function(rest)
    local v = onOff(rest, ns.settings.announce)
    if v == nil then
        say("announce = " .. (ns.settings.announce and "on" or "off") .. " (use /hello announce on|off)")
        return
    end
    ns.settings.announce = v
    say("fight announcements " .. (v and "on" or "off") .. ".")
end

commands.budget = function(rest)
    local mb = tonumber(rest)
    if not mb or mb < 1 or mb > 20 then
        say(("fight-log budget = %s MB per character (use /hello budget <1-20>)"):format(tostring(ns.settings.budgetMB)))
        return
    end
    ns.settings.budgetMB = mb
    say(("fight-log budget set to %s MB. Days older than a week are trimmed once the log is past it."):format(tostring(mb)))
end

commands.purge = function(rest)
    local days = tonumber(rest)
    if not days or days < 1 then
        say("use /hello purge <days> to drop stored fights older than that many days (at least 1).")
        return
    end
    local fights, buckets = ns.FightsPurge(floor(days))
    say(("purged %d fight(s) in %d day(s) older than %d day(s)."):format(fights, buckets, floor(days)))
end

local function ui() return ns.UI end

commands.ui = function()
    if ui() then ui().ToggleFights() end
end
commands.show = function()
    if ui() then ui().SetShown(true) end
    say("panel shown.")
end
commands.hide = function()
    if ui() then ui().SetShown(false) end
    say("panel hidden (/hello show brings it back).")
end
commands.toggle = function()
    if ui() then ui().SetShown(not ns.settings.shown) end
end
commands.lock = function()
    ns.settings.locked = true
    say("panel locked.")
end
commands.unlock = function()
    ns.settings.locked = false
    say("panel unlocked; drag it with the left mouse button.")
end
commands.scale = function(rest)
    local v = tonumber(rest)
    if not v then
        say(("scale = %s (use /hello scale <0.5-2.5>)"):format(tostring(ns.settings.scale)))
        return
    end
    if ui() then ui().SetScale(v) else ns.settings.scale = v end
    say("scale set to " .. tostring(ns.settings.scale) .. ".")
end
commands.resetpos = function()
    if ui() then ui().ResetPosition() else ns.db.pos = nil end
    say("panel position reset.")
end

SLASH_HELLOFOREVER1 = "/hello"
SlashCmdList["HELLOFOREVER"] = function(msg)
    msg = (msg or ""):match("^%s*(.-)%s*$") or ""
    local cmd, rest = msg:match("^(%S+)%s*(.*)$")
    cmd = cmd and cmd:lower() or ""
    rest = (rest or ""):lower()
    if not ns.db then ns.InitDB() end
    local fn = commands[cmd]
    if fn then
        fn(rest)
        return
    end
    if cmd ~= "" then say("unknown command '" .. cmd .. "'.") end
    commands.help()
end
