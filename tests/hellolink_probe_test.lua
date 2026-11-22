-- /hlink probe api (HelloLink/Probe.lua): every probe answers, an error stays in its own
-- line, a secret value is named and never indexed, no other addon's writing function is
-- called, the window events run only their own probes, and only the last 8 runs are kept.
-- The format-2 probes (#213): each value of a unit, aura, cooldown or action as it comes back,
-- and their runs at the first target, in the first fight and in the first raid.
--   lua5.1 tests/hellolink_probe_test.lua
local fails, checks = 0, 0
local function check(ok, what)
    checks = checks + 1
    if not ok then fails = fails + 1; print("FAIL " .. what) end
end

local function boom() error("a secret value was used") end
local SECRET = setmetatable({}, { __tostring = boom, __index = boom, __eq = boom, __lt = boom, __le = boom,
    __concat = boom, __len = boom, __call = boom })
local calls, events, handler = {}, {}, nil
local function count(name) return function(...) calls[name] = (calls[name] or 0) + 1; return ... end end
local SECRET_UNIT = "secret unit token"   -- a secret string, as the client gives one
_G.issecretvalue = function(v) return rawequal(v, SECRET) or rawequal(v, SECRET_UNIT) end
_G.time = function() return 1794516378 end
_G.debugprofilestop = os.clock
_G.C_Timer = { After = function(_, fn) fn() end }
_G.CreateFrame = function()
    return { RegisterEvent = function(_, e)
        if e == "ACTION_RANGE_CHECK_UPDATE" then error("unknown event " .. e) end   -- an event this client lacks
        if e == "ACTIONBAR_SLOT_CHANGED" then return false end                     -- or one it says no to
        events[e] = true
        return true
    end, SetScript = function(_, _, fn) handler = fn end }
end
_G.C_Map = { GetBestMapForUnit = function() return 1429 end, GetPlayerMapPosition = function() return SECRET end }
_G.C_Container = { GetContainerNumFreeSlots = function(bag) return 4, bag == 4 and 1 or 0 end,
    GetItemCooldown = function() return 0, 0, 1 end }
_G.C_TooltipInfo = { GetInventoryItem = function(_, slot)
    if slot == 16 then return SECRET end
    return { repairCost = slot == 5 and 1234 or 0, lines = {} }
end }
_G.C_TaxiMap = { GetTaxiNodesForMap = function() return SECRET end }
_G.C_Item = { GetItemCount = function() return 1 end }
-- the windows' getters (#232, part D)
_G.GetMerchantNumItems = function() return 2 end
_G.C_MerchantFrame = { GetItemInfo = function(i) return { name = "Light Leather", price = 100, stackCount = 1 } end }
_G.GetNumLootItems = function() return 2 end
_G.GetLootSlotInfo = function(i) return 133, "Linen Cloth", 3 end
_G.GetLootSlotLink = function() return SECRET end
_G.GetQuestID = function() return 783 end
_G.GetTitleText = function() return "A Threat Within" end
_G.GetNumSpellTabs = function() return 2 end
_G.GetSpellBookItemName = function(i, kind) if i == 1 and kind == "spell" then return "Attack", "" end end
_G.C_TradeSkillUI = { GetFilteredRecipeIDs = function() return { 2329, 3170 } end,   -- as this client's window lists them
    GetRecipeInfo = function(id) return { recipeID = id, name = "Elixir" } end,
    GetBaseProfessionInfo = function() return { professionName = "Alchemy", skillLevel = 75 } end }
_G.GetBindLocation = function() return SECRET end
_G.GetQuestsCompleted = function() return { [783] = true, [5] = true } end
_G.GetNumFactions = function() error(setmetatable({}, { __tostring = function() error("no text") end })) end
_G.GetNumTalentTabs = function() return 3 end
_G.UnitLevel = function() return 1 end
_G.GetRealmID = function() return 93 end
_G.GetRealmName = function() error("no name") end
_G.GetNormalizedRealmName = function() return "LivingFlame" end
_G.GetAutoCompleteRealms = function() return { "LivingFlame", "Other Realm" } end
_G.C_AutoComplete = { GetAutoCompleteRealms = function() return { "LivingFlame" } end }
-- the account (HelloLink 1.17.0): a BattleTag's shape only, never its text; each call alone
local bnPassed = {}
_G.BNGetInfo = function() return 7, "FakeTag#1234", 3, "", false, false, false end
_G.BNConnected = function() return true end
_G.C_BattleNet = {
    GetAccountInfoByGUID = function(g)
        bnPassed[#bnPassed + 1] = g
        return { battleTag = "FakeTag#1234", accountName = "Fake Person",
            gameAccountInfo = { realmName = "", realmID = 93, realmDisplayName = "Living Flame" } }
    end,
    GetGameAccountInfoByGUID = function() error("no info") end,
}
_G.RXP = {
    orphanedList = { 290 },
    GetOrphanedQuests = count("GetOrphanedQuests"),
    targeting = { GetCurrentTargets = function() return { "Defias Thug" }, {}, {}, { "Mother Fang" } end },
    arrowFrame = { element = { step = { index = 2 } } },
    currentGuide = { steps = { {}, { elements = { { tag = "accept", questId = 290 }, { tag = "goto" } } }, {} } },
}
_G.Auctionator = { API = { v1 = { RegisterForDBUpdate = count("RegisterForDBUpdate"),
    GetAuctionPriceByItemID = function() return 77 end, GetAuctionAgeByItemID = function() return 2 end } } }
-- the full name (0.8.1): each getter alone; a secret GUID is never passed on
local guidSecret, passed = false, {}
_G.UnitGUID = function(u)
    if guidSecret then return SECRET end
    return u == "playertarget" and "Creature-0-1-2-3-299-0000" or "Player-1-0000ABCD"
end
_G.UnitFullName = function() return "Fake", "LivingFlame" end
_G.GetUnitName = function(_, withRealm) if withRealm == true then error("no name") end return "Fake" end
_G.GetPlayerInfoByGUID = function(g)
    passed[#passed + 1] = g
    return "Hunter", "HUNTER", "Night Elf", "NightElf", 3, "Fake Family", ""
end
_G.PlayerLocation = { CreateFromGUID = function(_, g) passed[#passed + 1] = g; return { guid = g } end }
_G.C_PlayerInfo = { GetName = function() return SECRET end }
-- format 2 (0.8.2)
local targetOn, raid, fighting = true, false, true
_G.UnitExists = function(u)
    return u == "player" or (u == "target" and targetOn) or u == "nameplate3"
end
_G.UnitName = function() return "Fake" end
_G.UnitHealth = function() return SECRET end
_G.UnitHealthMax = function() return 100 end
_G.UnitPosition = function() error("no position") end
_G.IsInRaid = function() return raid end
_G.UnitAffectingCombat = function() return fighting end
_G.C_UnitAuras = { GetAuraDataByIndex = function(unit, i, filter)
    if unit == "player" and filter == "HELPFUL" and i == 1 then
        return { spellId = 13165, name = "Aspect of the Hawk", applications = 0, expirationTime = SECRET }
    end
    if unit == "target" and filter == "HARMFUL" and i == 1 then return SECRET end
    if unit == "target" and filter == "HELPFUL" then error("refused") end
end }
_G.UnitAura = function(unit, _, filter)
    if unit == "player" and filter == "HELPFUL" then error("no aura") end
    return "Rend", 1, 3
end
_G.C_Spell = { GetSpellCooldown = function(id) if id == 75 then return { startTime = 0, duration = 0 } end end }
-- the native action bar, four used slots (only the first three are sampled)
_G.C_ActionBar = { HasAction = function(slot) return slot == 2 or slot == 5 or slot == 7 or slot == 9 end,
    GetActionCooldown = function() return SECRET end, GetActionUseCount = function() return 7 end }
_G.GetActionInfo = function() return "spell", 75, "spell" end
local memoryUpdates = 0
_G.UpdateAddOnMemoryUsage = function() memoryUpdates = memoryUpdates + 1 end
_G.SkillUpForever = { API = { minor = 6, Professions = count("Professions"), Subscribe = count("Subscribe") } }

local ns = {}
assert(loadfile("HelloLink/Probe.lua"))("HelloLink", ns)
check(type(ns.ProbeApi) == "function", "the probe is exported")
check(events.PLAYER_ENTERING_WORLD and events.TAXIMAP_OPENED and events.MERCHANT_SHOW and events.PLAYER_TARGET_CHANGED
    and events.PLAYER_REGEN_DISABLED and events.GROUP_ROSTER_UPDATE, "the six events are registered")
handler(nil, "PLAYER_ENTERING_WORLD")
local db = _G.HelloLinkDB
check(type(db) == "table" and #db.probe == 1 and db.probe[1].why == "login" and db.probe[1].at == 1794516378,
    "a login run is kept, with its time")
local r = db.probe[1].results
check(#r == 50, "fifty probes answer, got " .. #r)
local function line(name, rs)
    for _, l in ipairs(rs or r) do if l:sub(1, #name) == name then return l end end
    return ""
end
check(line("bag family 0-5"):find("4={1=4, 2=1}", 1, true) ~= nil, "bag 4's family is read: " .. line("bag family"))
local repair = line("repair C_TooltipInfo")
check(repair:find("5=repairCost 1234", 1, true) and repair:find("16=<secret>", 1, true) and not repair:find("ERROR"),
    "the repair cost is read, a secret tooltip named: " .. repair)
check(line("hearth"):find("<secret>", 1, true) ~= nil, "a secret bind is named, not read: " .. line("hearth"))
check(line("taxi"):find("first <secret>", 1, true) and not line("taxi"):find("ERROR"), "a secret taxi list is not indexed: " .. line("taxi"))
check(line("SPF Estimate"):find("position <secret>", 1, true) ~= nil, "a secret position is named, not used: " .. line("SPF"))
check(line("reputation"):find("ERROR", 1, true) ~= nil, "an error whose text fails stays in its own line: " .. line("reputation"))
check(line("talents"):find("tabs=3", 1, true) ~= nil, "the next probe still answers: " .. line("talents"))
check(line("completed quests"):find("GetQuestsCompleted n=2", 1, true) ~= nil, "completed quests are counted")
check(line("RXP step now"):find('"accept":290', 1, true) ~= nil, "the step's tags are read: " .. line("RXP step now"))
check(line("RXP orphans"):find("orphanedList {1=290}", 1, true) ~= nil, "the orphans are read as they are: " .. line("RXP orphans"))
check(line("RXP targets"):find("Mother Fang", 1, true) ~= nil, "RXP's targets are read")
check(line("Auctionator"):find("price(2589)=77", 1, true) ~= nil, "an auction price is read")
check(line("realm"):find('GetRealmID=93 | GetRealmName=ERROR | GetNormalizedRealmName="LivingFlame" | GetAutoCompleteRealms={1="LivingFlame", 2="Other Realm"} | C_AutoComplete.GetAutoCompleteRealms={1="LivingFlame"}', 1, true) ~= nil,
    "the realm id and names are read, each alone: " .. line("realm"))
check(line("account"):find('BNGetInfo=presence 7, tag <12 bytes, # then 4 characters> | BNConnected=true | guid=Player-1-<hex> | '
    .. 'GetAccountInfoByGUID=tag <12 bytes, # then 4 characters>, realmName "", realmID 93, realmDisplayName "Living Flame" | '
    .. 'GetGameAccountInfoByGUID=ERROR', 1, true) ~= nil, "the account line gives the BattleTag's shape and the realm, each call alone: "
    .. line("account"))
check(not line("account"):find("FakeTag", 1, true) and not line("account"):find("Fake Person", 1, true),
    "the account line never gives the BattleTag or the account name")
check(#bnPassed == 1 and bnPassed[1] == "Player-1-0000ABCD", "the GUID is passed to the account call")
check(line("SkillUp"):find("minor=6", 1, true) ~= nil, "SkillUp's API is looked at")
check(line("fullName"):find('UnitFullName=("Fake", "LivingFlame") | GetUnitName=ERROR | UnitNameUnmodified=("absent") | '
    .. 'GetPlayerInfoByGUID=("Hunter", "HUNTER", "Night Elf", "NightElf", 3, "Fake Family", "") | C_PlayerInfo.GetName=(<secret>)',
    1, true) ~= nil, "the full-name getters answer, each alone, a secret named: " .. line("fullName"))
check(#passed == 2 and passed[1] == "Player-1-0000ABCD" and passed[2] == "Player-1-0000ABCD", "the GUID is passed to the two that take it")
-- format 2: each value alone, a secret named, an error in its own place
local tl = line("unit target")
check(tl:find('UnitExists=(true) UnitGUID=("Player-1-0000ABCD") UnitName=("Fake") UnitLevel=(1)', 1, true)
    and tl:find("UnitHealth=(<secret>) UnitHealthMax=(100)", 1, true) and tl:find("UnitPosition=ERROR ", 1, true) and tl:find("no position UnitThreatSituation=", 1, true)
    and tl:find("UnitInRange=(\"absent\")", 1, true), "a unit's values each answer alone, a secret named, an error kept in its place: " .. tl)
check(line("unit focus"):find("UnitExists=(false)", 1, true) ~= nil, "a unit that is not there says so: " .. line("unit focus"))
check(line("unit player"):find('UnitThreatSituation=("absent") UnitGUID=("Creature-0-1-2-3-299-0000")', 1, true) ~= nil,
    "the unit's target is asked: " .. line("unit player"))
local ah = line("auras player HELPFUL")
check(ah:find("C_UnitAuras n=1 first {spellId=13165, name=\"Aspect of the Hawk\", applications=0, duration=nil, expirationTime=<secret>", 1, true)
    and ah:find("| UnitAura=ERROR ", 1, true) and ah:find("no aura", 1, true), "an aura's fields are read, a secret one named; a global that fails keeps them: " .. ah)
local tb = line("auras target HELPFUL")
check(tb:find('C_UnitAuras ERROR ', 1, true) and tb:find('refused | UnitAura=("Rend", 1, 3)', 1, true),
    "a refused native call keeps its error's text and the global's answer (0.8.3): " .. tb)
local th = line("auras target HARMFUL")
check(th:find("C_UnitAuras n=0 aura 1 <secret> first {}", 1, true) and not th:find("ERROR", 1, true),
    "a secret aura is named and never indexed: " .. th)
local ab = line("action bar")
check(ab:find("C_ActionBar.HasAction used in slots 1-120: 4 | 2: C_ActionBar.GetActionInfo=(\"absent\") GetActionInfo=(\"spell\", 75, \"spell\") "
    .. "C_ActionBar.GetActionCooldown=(<secret>)", 1, true) and ab:find("C_ActionBar.GetActionUseCount=(7)", 1, true) and ab:find("| 7: ", 1, true) and not ab:find("| 9: ", 1, true),
    "the native action bar: four used, the first three read, a secret cooldown named: " .. ab)
check(line("nameplates"):find("units n=1 | nameplate3 UnitExists=(true)", 1, true) ~= nil, "the first nameplate is read as a unit: " .. line("nameplates"))
check(line("cooldowns"):find('| 75: C_Spell.GetSpellCooldown=({', 1, true) ~= nil and line("cooldowns"):find('| 1130: ', 1, true) ~= nil
    and line("hunter") ~= "" and line("addon cost") ~= "",
    "the cooldown, hunter and cost lines answer")
guidSecret, passed = true, {}
ns.ProbeApi("command")
check(#passed == 0 and line("fullName", db.probe[1].results):find("GetPlayerInfoByGUID=(\"<secret guid>\")", 1, true) ~= nil,
    "a secret GUID is named and never passed on: " .. line("fullName", db.probe[1].results))
check(#bnPassed == 1 and line("account", db.probe[1].results):find(
    "guid=<secret> | GetAccountInfoByGUID=no guid | GetGameAccountInfoByGUID=no guid", 1, true) ~= nil,
    "the account line names a secret GUID and passes it to no call: " .. line("account", db.probe[1].results))
guidSecret = false
table.remove(db.probe, 1)
-- review of #278: odd answers (a table for the tag, a value that fails to format, an error whose
-- text holds the tag) give a type or the fixed word ERROR, never the tag, and the next call goes on
do
    local keptInfo, keptBN = _G.BNGetInfo, _G.C_BattleNet
    local hostile = setmetatable({}, { __pairs = function() error("FakeTag#1234") end,
        __tostring = function() return "FakeTag#1234" end })
    _G.BNGetInfo = function() return hostile, { battleTag = "FakeTag#1234" } end
    _G.C_BattleNet = {
        GetAccountInfoByGUID = function() error("FakeTag#1234") end,
        GetGameAccountInfoByGUID = function() return { realmName = { "FakeTag#1234" }, realmID = "FakeTag#1234",
            realmDisplayName = "FakeTag#1234" } end,
    }
    ns.ProbeApi("command")
    local l = line("account", db.probe[1].results)
    check(l:find("BNGetInfo=presence <table>, tag <table> | BNConnected=true | guid=Player-1-<hex> | "
        .. "GetAccountInfoByGUID=ERROR | GetGameAccountInfoByGUID=tag nil, realmName <table>, realmID <string>, realmDisplayName <12 bytes, # then 4 characters>", 1, true) ~= nil
        and not l:find("FakeTag", 1, true), "odd answers give a type or ERROR, never the tag, and the next call goes on: " .. l)
    _G.BNGetInfo, _G.C_BattleNet = keptInfo, keptBN
    table.remove(db.probe, 1)
end
-- review round 1: a UnitGUID that is missing or fails skips the two calls that need it, and the
-- three unit-based answers stay
local realGuid = _G.UnitGUID
local UNIT_THREE = 'UnitFullName=("Fake", "LivingFlame") | GetUnitName=ERROR | UnitNameUnmodified=("absent") | '
for _, case in ipairs({ { "missing", nil, "absent" }, { "failing", function() error("no guid") end, "ERROR" } }) do
    _G.UnitGUID, passed = case[2], {}
    ns.ProbeApi("command")
    local l = line("fullName", db.probe[1].results)
    check(#passed == 0 and l:find(UNIT_THREE .. 'GetPlayerInfoByGUID=("' .. case[3] .. '") | C_PlayerInfo.GetName=("' .. case[3] .. '")', 1, true) ~= nil,
        "a " .. case[1] .. " UnitGUID skips the GUID calls and keeps the other three: " .. l)
    table.remove(db.probe, 1)
end
_G.UnitGUID = realGuid
check(next(calls) == nil, "no writing or building function of another addon is called")
handler(nil, "PLAYER_ENTERING_WORLD")
check(#db.probe == 1, "one login run a session")
handler(nil, "TAXIMAP_OPENED")
check(#db.probe[1].results == 1 and line("taxi", db.probe[1].results) ~= "", "a flight master runs the taxi probe only")
handler(nil, "MERCHANT_SHOW")
check(#db.probe[1].results == 2 and line("GetRepairAllCost", db.probe[1].results) ~= "", "a merchant runs the repair probes only")
-- the windows (#232, part D): each window's probe once a session, into probeWindows by its name, never
-- pushing a run out of `probe` (review of #268); the answers as the client gives them
do
  local w = db.probeWindows or {}
  check(w["window merchant"] and w["window merchant"].why == "MERCHANT_SHOW"
    and w["window merchant"].result:find("GetMerchantNumItems=(2)", 1, true) ~= nil
    and w["window merchant"].result:find("C_MerchantFrame.GetItemInfo=({", 1, true) ~= nil,
    "a merchant's window answers go to probeWindows: " .. tostring(w["window merchant"] and w["window merchant"].result))
  local runs = #db.probe
  handler(nil, "LOOT_OPENED")
  local loot = (db.probeWindows["window loot"] or {}).result or ""
  check(#db.probe == runs and loot:find("GetNumLootItems=(2)", 1, true) ~= nil and loot:find('GetLootSlotInfo=(133, "Linen Cloth", 3)', 1, true) ~= nil
    and loot:find("GetLootSlotLink=(<secret>)", 1, true) ~= nil, "a loot window's answers, no run in probe: " .. loot)
  handler(nil, "GOSSIP_SHOW")                -- a gossip, maybe with no quest: it samples once
  local atGossip = (db.probeWindows["window quest"] or {}).why
  handler(nil, "GOSSIP_SHOW")
  handler(nil, "QUEST_DETAIL")               -- a quest window after it still samples (review of #268)
  local atDetail = db.probeWindows["window quest"].why
  handler(nil, "QUEST_COMPLETE")             -- then the quest window is done for the session
  handler(nil, "QUEST_GREETING")             -- a greeting after it keeps the quest window's sample
  local quest = db.probeWindows["window quest"]
  check(atGossip == "GOSSIP_SHOW" and atDetail == "QUEST_DETAIL" and quest.why == "QUEST_DETAIL" and #db.probe == runs
    and quest.result:find("GetQuestID=(783)", 1, true) ~= nil and quest.result:find('GetTitleText=("A Threat Within")', 1, true) ~= nil,
    "a gossip samples once, a quest window after it once, the newest kept: " .. tostring(atGossip) .. " " .. tostring(atDetail))
  handler(nil, "TRADE_SKILL_SHOW")
  local trade = (db.probeWindows["window trade skill"] or {}).result or ""
  local recipe = trade:match("GetRecipeInfo%(first%)=(%b{})") or ""
  local base = trade:match("GetBaseProfessionInfo=%((%b{})%)") or ""
  check(trade:find("GetFilteredRecipeIDs n=2", 1, true) ~= nil and recipe:find('"name"="Elixir"', 1, true) ~= nil
    and recipe:find('"recipeID"=2329', 1, true) ~= nil and base:find('"skillLevel"=75', 1, true) ~= nil
    and base:find('"professionName"="Alchemy"', 1, true) ~= nil,
    "a profession's window: its level and one recipe's details: " .. trade)
  -- a recipe getter that fails keeps the profession's other answers; the spellbook's answers (a command run)
  local realFiltered = C_TradeSkillUI.GetFilteredRecipeIDs
  C_TradeSkillUI.GetFilteredRecipeIDs = function() error("no recipes") end
  ns.ProbeApi("command")
  local t2, book = line("window trade skill", db.probe[1].results), line("spellbook", db.probe[1].results)
  C_TradeSkillUI.GetFilteredRecipeIDs = realFiltered
  check(t2:find("recipes ERROR", 1, true) ~= nil and t2:find('"skillLevel"=75', 1, true) ~= nil,
    "a failing recipe list keeps the profession's level: " .. t2)
  check(book:find("GetNumSpellTabs=(2)", 1, true) ~= nil and book:find('GetSpellBookItemName=("Attack", "")', 1, true) ~= nil,
    "the spellbook's answers: " .. book)
  table.remove(db.probe, 1)
  check(events.LOOT_OPENED and events.QUEST_DETAIL and events.QUEST_PROGRESS and events.QUEST_COMPLETE and events.QUEST_GREETING
    and events.GOSSIP_SHOW and events.TRADE_SKILL_SHOW, "the window events are registered")
end
-- the format-2 runs: once at the first target, a second into the first fight, in the first raid
local updates = memoryUpdates
check(updates > 0, "a login or command run updates the addons' memory")
-- 0.8.3: no `addon cost` in these runs: UpdateAddOnMemoryUsage took 55 to 78 ms in the game (20 Nov 2026)
local function f2run(why) return db.probe[1].why == why and #db.probe[1].results == 22 and line("unit target", db.probe[1].results) ~= ""
    and line("addon cost", db.probe[1].results) == "" and memoryUpdates == updates
    and line("taxi", db.probe[1].results) == "" end
-- the events counted for format 3 (#232, part D): counted only, no run; an event this client lacks
-- is named refused; the spell-cast events by unit kind, a secret unit not read
do
    local before = #db.probe
    local function fire(e, ...) if events[e] then handler(nil, e, ...) end end   -- as the client: registered only
    fire("ACTIONBAR_UPDATE_USABLE")
    fire("ACTIONBAR_UPDATE_USABLE")
    fire("ACTION_USABLE_CHANGED", { { slot = 7, usable = true, noMana = false } })   -- a batch, as the client sends it
    fire("UNIT_SPELLCAST_START", "nameplate3", "Cast-3-0-0-0-133-0", 133)
    fire("UNIT_SPELLCAST_START", SECRET, "x", 1)
    fire("UNIT_SPELLCAST_START", "target", "Cast-3-0-0-0-133-1", 133)
    fire("UNIT_SPELLCAST_CHANNEL_START", SECRET_UNIT, "y", 2)
    check(#db.probe == before, "a counted event runs no probe")
    ns.ProbeApi("command")
    local l = line("events seen", db.probe[1].results)
    check(l:find("ACTIONBAR_UPDATE_USABLE=2 last ()", 1, true) ~= nil and l:find("ACTION_RANGE_CHECK_UPDATE=refused", 1, true) ~= nil
        and l:find("UNIT_SPELLCAST_START=3 units nameplate:1,target:1 last (\"target\", \"Cast-3-0-0-0-133-1\", 133)", 1, true) ~= nil
        and l:find("ACTION_USABLE_CHANGED=1 last ({1={", 1, true) ~= nil and l:find("\"slot\"=7", 1, true) ~= nil
        and l:find("\"usable\"=true", 1, true) ~= nil and l:find("\"noMana\"=false", 1, true) ~= nil and l:find("ACTIONBAR_SLOT_CHANGED=refused", 1, true) ~= nil
        and l:find("UNIT_SPELLCAST_CHANNEL_START=1 last", 1, true) ~= nil and not l:find("secret:", 1, true)
        and l:find("ACTIONBAR_UPDATE_STATE=0 last none", 1, true) ~= nil, "the events are counted: " .. l)
    check(l:find("<secret>", 1, true) ~= nil, "a secret argument is named, not read: " .. l)
    table.remove(db.probe, 1)
    updates = memoryUpdates   -- that command run updated the memory: the format-2 runs below must not
end
local runs = #db.probe
targetOn = false
handler(nil, "PLAYER_TARGET_CHANGED")
check(#db.probe == runs, "a target change with no target runs nothing")
targetOn = true
handler(nil, "PLAYER_TARGET_CHANGED")
check(f2run("target"), "the first target runs the format-2 probes only")
handler(nil, "PLAYER_TARGET_CHANGED")
check(#db.probe == runs + 1, "once a session")
fighting = false
handler(nil, "PLAYER_REGEN_DISABLED")
check(#db.probe == runs + 1, "a fight over before its second is no combat run")
fighting = true
handler(nil, "PLAYER_REGEN_DISABLED")
check(f2run("combat"), "the next fight runs the format-2 probes only")
handler(nil, "PLAYER_REGEN_DISABLED")
check(#db.probe == runs + 2, "once a session in a fight")
handler(nil, "GROUP_ROSTER_UPDATE")
check(db.probe[1].why == "combat", "a group change out of a raid runs nothing")
raid = true
handler(nil, "GROUP_ROSTER_UPDATE")
check(f2run("raid"), "the first raid runs the format-2 probes only")
_G.UnitLevel = function() return setmetatable({}, { __pairs = boom, __index = boom }) end
local realPairs = pairs
pairs = function(t) if getmetatable(t) and getmetatable(t).__pairs then error("cannot format") end return realPairs(t) end
ns.ProbeApi("command")
pairs = realPairs
check(db.probe[1].why == "command" and db.probe[1].level == "ERROR" and #db.probe[1].results == 50,
    "a metadata value that cannot be formatted is ERROR, and the run is kept")
for _ = 1, 10 do ns.ProbeApi("command") end
check(#db.probe == 8 and db.probe[1].why == "command" and #db.probe[1].results == 50, "the last 8 runs are kept, newest first")
print(("== %d checks, %d failed"):format(checks, fails))
os.exit(fails == 0 and 0 or 1)
