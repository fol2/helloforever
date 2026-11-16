-- HelloForever / Assistant.lua
-- The assistant, step 1 (docs/specs/115.md): a bar under the XP panel that shows one card at
-- a time, a window with every setting, and the addon's first card, `fight`. Off by default.
--
-- It cannot break the capture (decision 8): Fights.lua calls it under pcall after a record is
-- saved, and a rule that fails three times is off for the session. Nothing on the bar changes
-- in combat (decision 7). It reads no client value itself: the fight card is made from the
-- baseline's plain numbers (ns.BaselineCompare).
local addonName, ns = ...

local type, pairs, ipairs, tostring, tonumber, pcall = type, pairs, ipairs, tostring, tonumber, pcall
local floor, sort, concat = math.floor, table.sort, table.concat

local Assist = {}
ns.Assist = Assist
_G.HelloForeverAssist = { on = false } -- read by HelloLink (step 2) with rawget

----------------------------------------------------------------------
-- Languages (decision 14). en is the default and the fallback; a test holds that every table
-- has every pattern of en, with the same places for numbers and names.
----------------------------------------------------------------------
local L = {
    en = {
        sample = "A sample card: the assistant's bar sits here.",
        sample_basis = "a sample, not advice",
        fight = "%s: %s",
        part_dur = "%s s, usual %s s",
        part_dps = "%s dps, usual %s",
        part_taken = "taken %s, usual %s",
        part_died = "died",
        part_died_usual = "died, usual %d of %d",
        fight_basis = "%d fights at level %d",
        from_addon = "from the addon",
        from_companion = "from the companion",
        from_ai = "from AI",
        ago_s = "%d s ago",
        ago_min = "%d min ago",
        ago_h = "%d h ago",
        title = "Assistant",
        cards = "Cards",
        no_cards = "No card now.",
        is_off = "The assistant is off.",
        on = "The assistant is on",
        outside = "Take cards from the companion",
        lang = "Language",
        muted = "Muted subjects",
        none_muted = "None.",
        unmute = "Take back",
        away = "Away",
        mute = "Mute",
        sample_btn = "Show a sample card",
        settings = "Settings",
        in_combat = "In a fight: the controls wait.",
        open = "Open the assistant",
        asked = "asked: %s",
        no_answer = "no answer: is the companion running?",
        no_slot = "no slot left: /reload gives them back",
        ask_basis = "your question",
        topics = "Ask",
        state = "slots left: %s; last set: %s",
        state_never = "none yet",
        state_off = "The strip is off: no cards from the companion.",
        state_no_link = "HelloLink is not loaded: no cards from the companion.",
        target = "%s: %s",
        part_usual_dur = "usual %s s",
        part_usual_taken = "taken %s",
        part_died_of = "died %d of %d",
        gold = "This hour: %s, usual %s",
        gold_basis = "median of %d earlier hours of play",
        ammo = "%s: %d left",
        ammo_word = "Ammunition",
        ammo_basis = "the ammunition slot and the bags",
        bags = "Bags: %d free",
        bags_basis = "the game's count of free bag slots",
    },
    yue = {
        sample = "示範卡：助理嘅欄就喺呢度。",
        sample_basis = "示範，唔係建議",
        fight = "%s：%s",
        part_dur = "%s 秒，平時 %s 秒",
        part_dps = "每秒傷害 %s，平時 %s",
        part_taken = "捱咗 %s，平時 %s",
        part_died = "死咗",
        part_died_usual = "死咗，平時 %d 場死（共 %d 場）",
        fight_basis = "%d 場，等級 %d",
        from_addon = "由 addon 提供",
        from_companion = "由 companion 提供",
        from_ai = "由 AI 提供",
        ago_s = "%d 秒前",
        ago_min = "%d 分鐘前",
        ago_h = "%d 個鐘前",
        title = "助理",
        cards = "卡",
        no_cards = "而家冇卡。",
        is_off = "助理已經關咗。",
        on = "開啟助理",
        outside = "接收 companion 嘅卡",
        lang = "語言",
        muted = "已靜音嘅題目",
        none_muted = "冇。",
        unmute = "取消靜音",
        away = "收起",
        mute = "靜音",
        sample_btn = "顯示示範卡",
        settings = "設定",
        in_combat = "打緊交：控制要等打完。",
        open = "打開助理",
        asked = "已問：%s",
        no_answer = "冇回覆：companion 有冇開？",
        no_slot = "冇 slot 剩：/reload 會還返",
        ask_basis = "你嘅問題",
        topics = "問",
        state = "剩 %s 個 slot；上次收卡：%s",
        state_never = "未有",
        state_off = "Strip 關咗：收唔到 companion 嘅卡。",
        state_no_link = "HelloLink 未載入：收唔到 companion 嘅卡。",
        target = "%s：%s",
        part_usual_dur = "平時 %s 秒",
        part_usual_taken = "捱 %s",
        part_died_of = "死過 %d 次（%d 場）",
        gold = "呢個鐘：%s，平時 %s",
        gold_basis = "之前 %d 個鐘嘅中位數",
        ammo = "%s：剩 %d",
        ammo_word = "彈藥",
        ammo_basis = "彈藥格同背包",
        bags = "背包：剩 %d 格",
        bags_basis = "遊戲計嘅背包空格",
    },
}
local LANGS = { "en", "yue" }
local LANG_NAME = { en = "English", yue = "粵語" }
Assist.Lang = L

local function T(k)
    local t = L[ns.settings and ns.settings.assistLang] or L.en
    return t[k] or L.en[k]
end

local SEP = " \194\183 " -- " · "

-- At most n bytes, never cutting a UTF-8 character.
local function cut(s, n)
    if #s <= n then return s end
    local i = n
    while i > 0 and s:byte(i + 1) and s:byte(i + 1) >= 128 and s:byte(i + 1) < 192 do i = i - 1 end
    return s:sub(1, i)
end

----------------------------------------------------------------------
-- State
----------------------------------------------------------------------
local cards = {}    -- key -> card (section 3)
local away = {}     -- state card key -> the prio it was sent away at; event: key .. "@" .. at -> true
local barCard       -- the card the bar shows
local fails, off = {}, {} -- rule name -> failures; rule name -> true when off for the session
local MAX_CARDS, MAX_COUNTS = 20, 50
local bar, win
local ask, askN = nil, 0 -- the last question {n, topic, t, answered}; questions this UI session
local TOPICS = { "session" }

-- HelloLink's plain table (docs/specs/115.md, section 6), as the tick last read it, out of
-- combat; nil when it was absent or not as the spec has it. Commands and the window read this
-- copy, never HelloLink's table itself.
local linkSnap
local function link() return linkSnap end

-- HelloForever's plain table for HelloLink: {on, lang, ask = {n, topic, t}, shown}.
local function publish()
    local g = _G.HelloForeverAssist
    g.on = ns.settings and ns.settings.assist == true or false
    g.lang = ns.settings and ns.settings.assistLang or "en"
    g.ask = ask and { n = ask.n, topic = ask.topic, t = ask.t } or nil
    g.shown = g.on and barCard and barCard.key or nil
end

local function isOn() return ns.settings and ns.settings.assist == true end

-- Every entry from the client (a script, a timer, a command) runs under pcall (decision 8).
local function safe(fn)
    return function(...) pcall(fn, ...) end
end

local function muted()
    local s = ns.settings
    if type(s.assistMuted) ~= "table" then s.assistMuted = {} end
    return s.assistMuted
end

-- The counts of section 9: how often a card key was shown and sent away.
local function count(key, field)
    local c = ns.Char()
    if type(c.assist) ~= "table" then c.assist = {} end
    local n = c.assist[key]
    if type(n) ~= "table" then
        local total, oldK, oldT = 0, nil, nil
        for k, x in pairs(c.assist) do
            total = total + 1
            local t = type(x) == "table" and tonumber(x.t) or 0
            if not oldT or t < oldT then oldK, oldT = k, t end
        end
        if total >= MAX_COUNTS then c.assist[oldK] = nil end
        n = { shown = 0, away = 0 }
        c.assist[key] = n
    end
    n[field] = (n[field] or 0) + 1
    n.t = time()
end

-- Cards in the bar's order: the lowest prio first; among equals, the newest.
local function ordered()
    local list = {}
    for _, c in pairs(cards) do list[#list + 1] = c end
    sort(list, function(a, b)
        if a.prio ~= b.prio then return a.prio < b.prio end
        if a.at ~= b.at then return a.at > b.at end
        return a.key < b.key
    end)
    return list
end

local function prune()
    local now = time()
    for k, c in pairs(cards) do
        if c.kind == "event" and c.at + c.ttl <= now then cards[k] = nil end
    end
end

----------------------------------------------------------------------
-- The bar (section 4)
----------------------------------------------------------------------
local PRIO_COLOUR = { { 0.9, 0.2, 0.2 }, { 1, 0.82, 0 }, { 0.55, 0.55, 0.55 } }

local function ago(at)
    local d = time() - (tonumber(at) or time())
    if d < 60 then return T("ago_s"):format(d) end
    if d < 3600 then return T("ago_min"):format(floor(d / 60)) end
    return T("ago_h"):format(floor(d / 3600))
end

local function placeBar()
    if not bar then return end
    local panel = ns.UI and ns.UI.Panel and ns.UI.Panel()
    bar:SetScale(tonumber(ns.settings.scale) or 1)
    bar:ClearAllPoints()
    if panel then
        bar:SetPoint("TOP", panel, "BOTTOM", 0, -2) -- one point and a fixed width: freezeBar can pin it
    else
        bar:SetPoint("TOP", UIParent, "TOP", 0, -190)
    end
end

-- In a fight the bar stays where it is (decision 7): pinned to the screen, so a change of the
-- panel's scale or place moves it only after the fight (placeBar, through AfterCombat).
local function freezeBar()
    if not bar then return end
    local left, top = bar:GetLeft(), bar:GetTop()
    if type(left) ~= "number" or type(top) ~= "number" then return end
    bar:ClearAllPoints()
    bar:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", left, top)
end

local sendAway -- below

local function buildBar()
    local f = CreateFrame("Frame", "HelloForeverAssistBar", UIParent)
    f:SetSize(204, 18)
    f:SetClampedToScreen(true)
    f:EnableMouse(true)
    local bg = f:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    bg:SetColorTexture(0.04, 0.045, 0.06, 0.88)
    f.edge = f:CreateTexture(nil, "ARTWORK")
    f.edge:SetPoint("TOPLEFT")
    f.edge:SetPoint("BOTTOMLEFT")
    f.edge:SetWidth(3)
    f.text = ns.UI.Label(f, "GameFontHighlightSmall")
    f.text:SetPoint("LEFT", 8, 0)
    f.text:SetPoint("RIGHT", -26, 0)
    f.count = ns.UI.Label(f, "GameFontDisableSmall", "RIGHT")
    f.count:SetPoint("RIGHT", -6, 0)
    f:SetScript("OnMouseUp", safe(function(_, button)
        if ns.InCombat() then return end -- decision 7: clicks do nothing in a fight
        if button == "RightButton" then
            if barCard then sendAway(barCard) end
        else
            Assist.Open()
        end
    end))
    f:SetScript("OnEnter", safe(function(self)
        local c, tip = barCard, _G.GameTooltip
        if not c or not tip then return end
        tip:SetOwner(self, "ANCHOR_BOTTOM")
        if type(c.detail) == "string" then
            for line in c.detail:gmatch("[^\n]+") do tip:AddLine(line) end
        end
        tip:AddLine(T("from_" .. c.src) .. SEP .. c.basis .. SEP .. ago(c.at))
        tip:Show()
    end))
    f:SetScript("OnLeave", safe(function() if _G.GameTooltip then _G.GameTooltip:Hide() end end))
    f:Hide()
    bar = f
    placeBar()
end

local refreshWindow -- below

-- Shows the first card on the bar. Runs out of combat only (render queues it).
local function draw()
    prune()
    local list = isOn() and ordered() or {}
    local top = list[1]
    if top and (not barCard or barCard.key ~= top.key or barCard.at ~= top.at) then count(top.key, "shown") end
    barCard = top
    if not top then
        if bar then bar:Hide() end
    else
        if not bar then buildBar() end
        local rgb = PRIO_COLOUR[top.prio]
        bar.edge:SetColorTexture(rgb[1], rgb[2], rgb[3], 1)
        bar.text:SetText((top.src == "ai" and "AI " or "") .. top.text)
        bar.count:SetText(#list > 1 and ("+" .. (#list - 1)) or "")
        bar:Show()
    end
    publish()
    if refreshWindow then refreshWindow() end
end

local function render() ns.AfterCombat("assist-bar", safe(draw)) end

----------------------------------------------------------------------
-- The card store (section 3)
----------------------------------------------------------------------
local SRC = { addon = true, companion = true, ai = true }

local function whole(v, low, high)
    return type(v) == "number" and v == v and v >= low and v <= high and v == floor(v)
end

local function line(v) return type(v) == "string" and v ~= "" and not v:find("\n", 1, true) end

local function valid(c)
    return type(c) == "table" and type(c.id) == "string" and #c.id <= 24 and c.id:match("^[%w%-]+$") ~= nil
        and (c.kind == "state" or c.kind == "event") and (c.prio == 1 or c.prio == 2 or c.prio == 3)
        and line(c.text) and line(c.basis) and SRC[c.src] and whole(c.at, 0, 2 ^ 53)
        and (c.ttl == nil or whole(c.ttl, 10, 3600)) and (c.detail == nil or type(c.detail) == "string")
end

-- Holds a card; false when it is refused (off, not valid, muted, sent away, or no room).
function Assist.Put(c)
    if not isOn() or not valid(c) then return false end
    local key = c.src == "addon" and c.id or ("out:" .. c.id)
    if muted()[key] then return false end
    local card = { key = key, id = c.id, kind = c.kind, prio = c.prio, src = c.src, at = c.at,
        text = cut(c.text, 120), basis = cut(c.basis, 120), detail = c.detail and cut(c.detail, 600),
        ttl = math.min(3600, math.max(10, tonumber(c.ttl) or 60)) }
    if card.kind == "event" then
        if away[key .. "@" .. card.at] then return false end
    else
        local a = away[key]
        if a then
            if card.prio >= a then return false end
            away[key] = nil -- its prio number went down: it shows again
        end
    end
    if not cards[key] then
        local n, drop = 0, nil
        for _, x in pairs(cards) do
            n = n + 1
            if x.kind == "event" and (not drop or x.prio > drop.prio or (x.prio == drop.prio and x.at < drop.at)) then drop = x end
        end
        if n >= MAX_CARDS then
            if not drop then return false end
            cards[drop.key] = nil
        end
    end
    cards[key] = card
    if card.kind == "event" then ns.After(math.max(0, card.at + card.ttl - time()) + 0.1, render) end
    render()
    return true
end

-- Its condition ended (or the card is withdrawn): a state card sent away may show again later.
function Assist.Drop(key)
    cards[key] = nil
    away[key] = nil
    render()
end

sendAway = function(c)
    if not cards[c.key] then return end
    if c.kind == "event" then away[c.key .. "@" .. c.at] = true else away[c.key] = c.prio end
    cards[c.key] = nil
    count(c.key, "away")
    render()
end

function Assist.Cards() prune() return ordered() end
function Assist.Shown() return barCard end
function Assist.RulesOff() return off end

----------------------------------------------------------------------
-- Rules (section 5)
----------------------------------------------------------------------
local function runRule(name, fn, ...)
    if off[name] or not isOn() then return end
    local ok = pcall(fn, ...)
    if not ok then
        fails[name] = (fails[name] or 0) + 1
        if fails[name] >= 3 then off[name] = true end
    end
end

local function fightRule(bkey, name, fight, earlier)
    Assist.Drop("fight") -- until the next fight
    if not bkey then return end
    local cmp = ns.BaselineCompare(fight, earlier)
    if not cmp.compared then return end -- unknown gives no card (decision 5)
    local parts = {}
    for _, p in ipairs(cmp.parts) do
        if p.usual then parts[#parts + 1] = T("part_" .. p.field):format(ns.FmtNum(p.this), ns.FmtNum(p.usual)) end
    end
    if cmp.died then
        parts[#parts + 1] = cmp.diedKnown and T("part_died_usual"):format(cmp.diedUsual, cmp.diedKnown) or T("part_died")
    end
    local level = tonumber(tostring(bkey):match(":(%-?%d+)$")) or 0
    Assist.Put({ id = "fight", kind = "event", prio = cmp.died and 2 or 3, src = "addon", at = time(), ttl = 120,
        text = T("fight"):format(tostring(name or "?"), concat(parts, SEP)),
        basis = T("fight_basis"):format(cmp.earlier, level) })
end

-- The target card (section 5): out of combat, a creature whose key <creature id>:<player level>
-- holds at least 3 fights. The GUID and the level come through ns.Call: a secret or missing value
-- is nil, and gives no card (decision 5). Seen 15 Nov 2026: a hostile creature's GUID is readable
-- out of combat and not secret (plan/05).
local function targetRule()
    if ns.InCombat() then return end -- in combat the rule does not run; it runs when the fight ends
    local guid = ns.Call(_G.UnitGUID, "target")
    local id = type(guid) == "string" and (guid:match("^Creature%-%d+%-%d+%-%d+%-%d+%-(%d+)%-%x+$")
        or guid:match("^Vehicle%-%d+%-%d+%-%d+%-%d+%-(%d+)%-%x+$"))
    local level = ns.Call(_G.UnitLevel, "player")
    local u = id and type(level) == "number" and ns.BaselineUsual(id .. ":" .. level)
    local parts = {}
    if u then
        if u.dur then parts[#parts + 1] = T("part_usual_dur"):format(ns.FmtNum(u.dur)) end
        if u.taken then parts[#parts + 1] = T("part_usual_taken"):format(ns.FmtNum(u.taken)) end
        if u.known then parts[#parts + 1] = T("part_died_of"):format(u.died, u.known) end
    end
    if #parts == 0 then
        -- its condition ended: a card sent away may show again when it comes back (section 3)
        if cards.target or away.target then Assist.Drop("target") end
        return
    end
    local text = T("target"):format(tostring(u.name or "?"), concat(parts, ", "))
    local prio = u.anyDied and 2 or 3
    local have = cards.target
    if have and have.text == text and have.prio == prio then return end
    Assist.Put({ id = "target", kind = "state", prio = prio, src = "addon", at = time(), ttl = 3600, text = text,
        basis = T("fight_basis"):format(u.n, level) })
end

-- Copper as "1 g 20 s", "85 s", "-3 c": plain text, a card has no room for colour codes.
local function coins(c)
    local sign = c < 0 and "-" or ""
    c = math.abs(floor(c + 0.5))
    local g, s, k = floor(c / 10000), floor(c % 10000 / 100), c % 100
    local out = {}
    if g > 0 then out[#out + 1] = g .. " g" end
    if s > 0 then out[#out + 1] = s .. " s" end
    if k > 0 or #out == 0 then out[#out + 1] = k .. " c" end
    return sign .. concat(out, " ")
end

-- The gold card (section 5): after each 3600 s of play, the last hour of play (hours[1] of
-- ns.PlayHours, counted back from the timeline's last moment) against the median of the earlier
-- hours (the last GOLD_HOURS of them), when there are at least 3. The first look in a login only
-- notes the moment: hours played before it give no card. ponytail: the median of recent hours,
-- not of hours at this level; a level key when the money of low levels skews it.
local GOLD_HOURS = 20
local goldAt -- the timeline's moment of the last card, or of this login's first look
local function goldRule()
    local hours, since, lastAt = ns.PlayHours(ns.Char().timeline, GOLD_HOURS + 1)
    if not hours then return end
    if not goldAt then goldAt = lastAt return end
    if since(goldAt) < 3600 then return end
    goldAt = lastAt
    local earlier = {}
    for i = 2, #hours do earlier[#earlier + 1] = hours[i] end
    if #earlier < 3 then return end
    sort(earlier)
    local m = #earlier
    local usual = m % 2 == 1 and earlier[(m + 1) / 2] or floor((earlier[m / 2] + earlier[m / 2 + 1]) / 2)
    Assist.Put({ id = "gold", kind = "event", prio = 3, src = "addon", at = time(), ttl = 300,
        text = T("gold"):format(coins(hours[1]), coins(usual)), basis = T("gold_basis"):format(m) })
end
ns.Listen("SESSION", function() goldAt = nil end) -- a login: the hours played before it give no card
ns.Listen("TIMELINE", function() ns.AfterCombat("assist-gold", function() runRule("gold", goldRule) end) end)

-- `ok, value` of fn(...): ok is false when fn is missing, fails, or answers a secret. Unlike
-- ns.Call, "cannot read" is not "nothing": a slot that cannot be read is not an empty slot.
local function read(fn, ...)
    if type(fn) ~= "function" then return false end
    local ok, v = pcall(fn, ...)
    if not ok or ns.IsSecret(v) then return false end
    return true, v
end

-- The count of item `id` in the bags 0 to NUM_BAG_SLOTS (quivers and pouches are bags there),
-- or nil when any slot cannot be read: a count with a slot left out would be too low.
local function bagCount(id)
    local CC = _G.C_Container
    if type(CC) ~= "table" then return nil end
    local n = 0
    for bag = 0, tonumber(_G.NUM_BAG_SLOTS) or 4 do
        local okSlots, slots = read(CC.GetContainerNumSlots, bag)
        if not okSlots or type(slots) ~= "number" then return nil end
        for slot = 1, slots do
            local ok, info = read(CC.GetContainerItemInfo, bag, slot)
            if not ok or (info ~= nil and type(info) ~= "table") then return nil end
            if info then
                local item, stack = info.itemID, info.stackCount
                if ns.IsSecret(item) or ns.IsSecret(stack) or type(item) ~= "number" then return nil end
                if item == id then
                    if type(stack) ~= "number" then return nil end
                    n = n + stack
                end
            end
        end
    end
    return n
end

-- The ammo card (section 5): the ammunition slot (inventory slot 0, seen 13 Nov 2026) holds an
-- item and the bags hold fewer than 200 of it; prio 1 under 50. No ammunition, or a count that
-- cannot be read, gives no card (decision 5). Out of combat: a shot changes the count, so in a
-- fight the rule waits for the fight's end.
local function ammoRule()
    if ns.InCombat() then return end
    local okId, id = read(_G.GetInventoryItemID, "player", 0)
    local n = okId and type(id) == "number" and bagCount(id)
    if not n or n >= 200 then
        if cards.ammo or away.ammo then Assist.Drop("ammo") end
        return
    end
    local _, name = read(_G.C_Item and _G.C_Item.GetItemInfo or _G.GetItemInfo, id)
    if type(name) ~= "string" or name == "" then name = T("ammo_word") end
    local text, prio = T("ammo"):format(name, n), n < 50 and 1 or 2
    local have = cards.ammo
    if have and have.text == text and have.prio == prio then return end
    Assist.Put({ id = "ammo", kind = "state", prio = prio, src = "addon", at = time(), ttl = 3600, text = text,
        basis = T("ammo_basis") })
end
-- The bags card (section 5): 2 free bag slots or fewer, prio 1 at none. The count is the client's
-- own (C_Container.CalculateTotalNumberOfFreeBagSlots, which its mail frame uses; the forever
-- branch of its UI source): no card when it cannot be read (decision 5).
local function bagsRule()
    local CC = _G.C_Container
    local ok, free = read(type(CC) == "table" and CC.CalculateTotalNumberOfFreeBagSlots)
    if not ok or type(free) ~= "number" or free > 2 then
        if cards.bags or away.bags then Assist.Drop("bags") end
        return
    end
    local text, prio = T("bags"):format(free), free <= 0 and 1 or 2
    local have = cards.bags
    if have and have.text == text and have.prio == prio then return end
    Assist.Put({ id = "bags", kind = "state", prio = prio, src = "addon", at = time(), ttl = 3600, text = text,
        basis = T("bags_basis") })
end

-- The supplies (ammo, bags) after a change of the bags or the gear, out of combat.
local function suppliesChanged()
    ns.AfterCombat("assist-supplies", function()
        runRule("ammo", ammoRule)
        runRule("bags", bagsRule)
    end)
end
ns.On("BAG_UPDATE_DELAYED", suppliesChanged)
ns.On("PLAYER_EQUIPMENT_CHANGED", suppliesChanged)
ns.On("PLAYER_ENTERING_WORLD", suppliesChanged)

local function targetChanged() runRule("target", targetRule) end
ns.On("PLAYER_TARGET_CHANGED", targetChanged)
ns.On("PLAYER_LEVEL_UP", targetChanged)

-- Fights.lua calls this, under pcall, after a new fight is saved; bkey is nil when the fight
-- does not count for the baseline.
function ns.AssistFight(bkey, name, fight, earlier)
    runRule("fight", fightRule, bkey, name, fight, earlier)
    runRule("target", targetRule) -- the target's usual numbers may have changed
end

----------------------------------------------------------------------
-- Settings and commands (section 4)
----------------------------------------------------------------------
local function say(msg) ns.Print(msg) end

function Assist.SetOn(on)
    ns.settings.assist = on and true or false
    if not on then
        cards, away = {}, {}
    end
    publish()
    render()
    if on then suppliesChanged() end -- a state that held while the assistant was off shows now
end

local function setLang(code)
    if not L[code] then return false end
    ns.settings.assistLang = code
    publish()
    if refreshWindow then refreshWindow() end
    return true
end

local function setMuted(key, yes)
    muted()[key] = yes or nil
    if yes and cards[key] then cards[key] = nil end
    render()
end

----------------------------------------------------------------------
-- Cards from outside and the question (section 6). HelloLink takes a set at a look and leaves
-- it in HelloLinkAssist; this reads it once a second, out of combat, and checks each card again
-- (Put). A card from outside is known by out:<id>.
----------------------------------------------------------------------
local CARD_FIELDS = { "id", "kind", "prio", "src", "at", "ttl", "text", "basis", "detail" }

local function same(have, c)
    for _, k in ipairs(CARD_FIELDS) do
        if k ~= "text" and k ~= "basis" and k ~= "detail" and have[k] ~= c[k] then return false end
    end
    return have.text == cut(c.text, 120) and have.basis == cut(c.basis, 120)
        and have.detail == (c.detail and cut(c.detail, 600))
end

local function opt(v) return v == nil or whole(v, 0, 2 ^ 53) end

-- A copy of HelloLink's table made with rawget alone (no code of HelloLink runs: hard rule 2),
-- or nil when it is absent or not as section 6 has it.
local function readLink()
    local la = rawget(_G, "HelloLinkAssist")
    if type(la) ~= "table" then return nil end
    local snap = { strip = rawget(la, "strip"), left = rawget(la, "left"), seq = rawget(la, "seq"),
        t = rawget(la, "t"), re = rawget(la, "re"), cards = {} }
    if type(snap.strip) ~= "boolean" or not opt(snap.left) or not opt(snap.seq) or not opt(snap.t) or not opt(snap.re) then
        return nil
    end
    local list = rawget(la, "cards")
    if type(list) ~= "table" then return nil end
    for i = 1, 8 do
        local c = rawget(list, i)
        if c == nil then break end
        if type(c) == "table" then
            local copy = {}
            for _, k in ipairs(CARD_FIELDS) do copy[k] = rawget(c, k) end
            if (copy.src == "companion" or copy.src == "ai") and valid(copy) then snap.cards[#snap.cards + 1] = copy end
        end
    end
    return snap
end

local function sig(x)
    return x and (tostring(x.strip) .. ":" .. tostring(x.left) .. ":" .. tostring(x.t) .. ":" .. tostring(x.seq)) or "-"
end

local function syncOutside()
    if ns.InCombat() then return end
    local before = linkSnap
    linkSnap = readLink() -- also with the assistant off: the window's state line says what HelloLink says
    local la = linkSnap
    if not isOn() then
        if sig(before) ~= sig(la) and refreshWindow then refreshWindow() end
        return
    end
    local want = {}
    if la and la.strip then
        if ask and not ask.answered and la.re == ask.n then -- the answer came: the question's card goes
            ask.answered = true
            Assist.Drop("ask")
        end
        if ns.settings.assistOutside then
            for _, c in ipairs(la.cards) do
                local key = "out:" .. c.id
                want[key] = true
                if not (cards[key] and same(cards[key], c)) then Assist.Put(c) end
            end
        end
    end
    for key in pairs(cards) do
        if key:sub(1, 4) == "out:" and not want[key] then Assist.Drop(key) end
    end
    -- a state card from outside that was sent away: its condition ended when a set came without it
    for key in pairs(away) do
        if key:sub(1, 4) == "out:" and not key:find("@", 1, true) and not want[key] then away[key] = nil end
    end
    if sig(before) ~= sig(la) and refreshWindow then refreshWindow() end -- the state line
end
Assist.Sync = syncOutside

-- /hello ask <topic>, or a topic's button in the window.
function Assist.Ask(topic)
    if not isOn() then return say("the assistant is off (/hello assist on).") end
    if type(topic) ~= "string" or #topic > 24 or not topic:match("^[%a%-]+$") then
        return say("use /hello ask <topic>; the topics: " .. concat(TOPICS, ", ") .. ".")
    end
    local la = link()
    if not la or not la.strip then
        return say("the strip is off, or HelloLink is not loaded: nothing was asked.")
    end
    if la.left == 0 then
        Assist.Put({ id = "ask", kind = "event", prio = 2, src = "addon", at = time(), ttl = 60,
            text = T("no_slot"), basis = T("ask_basis") })
        return
    end
    askN = askN + 1
    ask = { n = askN, topic = topic, t = time() }
    publish()
    Assist.Put({ id = "ask", kind = "event", prio = 3, src = "addon", at = time(), ttl = 30,
        text = T("asked"):format(topic), basis = T("ask_basis") })
    local n = askN
    ns.After(30, safe(function()
        if ask and ask.n == n and not ask.answered then
            Assist.Put({ id = "ask", kind = "event", prio = 2, src = "addon", at = time(), ttl = 60,
                text = T("no_answer"), basis = T("ask_basis") })
        end
    end))
end

function Assist.Test()
    if not isOn() then
        say("the assistant is off (/hello assist on).")
        return
    end
    Assist.Put({ id = "test", kind = "event", prio = 3, src = "addon", at = time(), ttl = 30,
        text = T("sample"), basis = T("sample_basis") })
end

function Assist.Debug()
    local list = {}
    for name in pairs(off) do list[#list + 1] = name end
    sort(list)
    say(("assistant: %s, %d cards; rules off: %s"):format(isOn() and "on" or "off", #Assist.Cards(),
        #list > 0 and concat(list, ", ") or "none"))
end

function Assist.Command(rest)
    local verb, arg = (rest or ""):match("^(%S*)%s*(.-)%s*$")
    if verb == "" then
        Assist.Open()
    elseif verb == "on" or verb == "off" then
        Assist.SetOn(verb == "on")
        say("assistant " .. verb .. ".")
    elseif verb == "list" then
        local list = Assist.Cards()
        if #list == 0 then say(isOn() and "no card now." or "the assistant is off.") end
        for _, c in ipairs(list) do say(c.text .. SEP .. c.basis) end
    elseif verb == "mute" or verb == "unmute" then
        if arg == "" then return say("use /hello assist " .. verb .. " <key>") end
        setMuted(arg, verb == "mute")
        say(arg .. (verb == "mute" and " muted." or " unmuted."))
    elseif verb == "test" then
        Assist.Test()
    elseif verb == "outside" and (arg == "on" or arg == "off") then
        ns.settings.assistOutside = arg == "on"
        if refreshWindow then refreshWindow() end
        say("cards from the companion " .. arg .. ".")
    elseif verb == "lang" then
        if arg ~= "" and setLang(arg) then
            say("language: " .. arg .. ".")
        else
            say("languages: " .. concat(LANGS, ", ") .. " (/hello assist lang <code>).")
        end
    else
        say("use /hello assist [on|off|list|test|lang <code>|mute <key>|unmute <key>|outside on|off]")
    end
end

----------------------------------------------------------------------
-- The window (section 4): frames and buttons only.
----------------------------------------------------------------------
local W, ROWS, MUTED_ROWS = 360, 6, 5

local function button(parent, w, h, font) return ns.UI.Button(parent, w, h, font) end

local function grey(b, yes)
    b.off = yes or nil
    b:SetAlpha(yes and 0.4 or 1)
end

-- A click on a control: dropped in a fight and when the control is greyed, not kept for later.
local function act(fn)
    return safe(function(self)
        if ns.InCombat() or self.off then return end
        fn(self)
        if refreshWindow then refreshWindow() end
    end)
end

local function buildWindow()
    local r, g, b = ns.UI.ClassColor()
    local f = CreateFrame("Frame", "HelloForeverAssistWindow", UIParent)
    f:SetSize(W, 500)
    f:SetPoint("CENTER")
    f:SetFrameStrata("DIALOG")
    f:SetClampedToScreen(true)
    f:SetMovable(true)
    f:EnableMouse(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", f.StartMoving)
    f:SetScript("OnDragStop", f.StopMovingOrSizing)
    ns.UI.Skin(f, 0.94, r, g, b)

    f.title = ns.UI.Label(f, "GameFontNormal")
    f.title:SetPoint("TOPLEFT", 12, -12)
    f.title:SetTextColor(r, g, b)
    f.close = button(f, 20, 20, "GameFontNormal")
    f.close:SetPoint("TOPRIGHT", -6, -7)
    f.close.label:SetText("x")
    f.close:SetScript("OnClick", safe(function() f:Hide() end)) -- also in a fight

    local y = -36
    f.cardsHead = ns.UI.Label(f, "GameFontNormalSmall")
    f.cardsHead:SetPoint("TOPLEFT", 12, y)
    f.note = ns.UI.Label(f, "GameFontDisableSmall")
    f.note:SetPoint("TOPLEFT", 12, y - 16)
    f.rows = {}
    for i = 1, ROWS do
        local row = CreateFrame("Frame", nil, f)
        row:SetSize(W - 24, 30)
        row:SetPoint("TOPLEFT", 12, y - 16 - (i - 1) * 30)
        row.text = ns.UI.Label(row, "GameFontHighlightSmall")
        row.text:SetPoint("TOPLEFT", 0, -2)
        row.text:SetWidth(W - 130)
        row.sub = ns.UI.Label(row, "GameFontDisableSmall")
        row.sub:SetPoint("TOPLEFT", 0, -15)
        row.sub:SetWidth(W - 130)
        row.away = button(row, 46, 16)
        row.away:SetPoint("TOPRIGHT", -50, -2)
        row.away:SetScript("OnClick", act(function(self) if self.card then sendAway(self.card) end end))
        row.mute = button(row, 46, 16)
        row.mute:SetPoint("TOPRIGHT", 0, -2)
        row.mute:SetScript("OnClick", act(function(self) if self.card then setMuted(self.card.key, true) end end))
        row:Hide()
        f.rows[i] = row
    end
    -- More cards than rows: the wheel scrolls (section 4: the window has every card).
    f.cardOff, f.mutedOff = 0, 0
    local cardArea = CreateFrame("Frame", nil, f)
    cardArea:SetSize(W - 24, ROWS * 30)
    cardArea:SetPoint("TOPLEFT", 12, y - 16)
    cardArea:EnableMouseWheel(true)
    cardArea:SetScript("OnMouseWheel", safe(function(_, delta) f.cardOff = f.cardOff - delta refreshWindow() end))
    f.cardArea = cardArea

    y = y - 16 - ROWS * 30 - 10
    f.setHead = ns.UI.Label(f, "GameFontNormalSmall")
    f.setHead:SetPoint("TOPLEFT", 12, y)
    f.onCheck = button(f, W - 24, 18)
    f.onCheck:SetPoint("TOPLEFT", 12, y - 16)
    f.onCheck:SetScript("OnClick", act(function() Assist.SetOn(not isOn()) end))
    f.outsideCheck = button(f, W - 24, 18)
    f.outsideCheck:SetPoint("TOPLEFT", 12, y - 34)
    f.outsideCheck:SetScript("OnClick", act(function() ns.settings.assistOutside = not ns.settings.assistOutside end))
    f.langLabel = ns.UI.Label(f, "GameFontHighlightSmall")
    f.langLabel:SetPoint("TOPLEFT", 16, y - 56)
    f.lang = {}
    for i, code in ipairs(LANGS) do
        local lb = button(f, 64, 18)
        lb:SetPoint("TOPLEFT", 100 + (i - 1) * 68, y - 52)
        lb.label:SetText(LANG_NAME[code])
        lb:SetScript("OnClick", act(function() setLang(code) end))
        f.lang[code] = lb
    end
    f.mutedLabel = ns.UI.Label(f, "GameFontHighlightSmall")
    f.mutedLabel:SetPoint("TOPLEFT", 16, y - 76)
    f.muted = {}
    for i = 1, MUTED_ROWS do
        local row = CreateFrame("Frame", nil, f)
        row:SetSize(W - 40, 16)
        row:SetPoint("TOPLEFT", 28, y - 76 - i * 16)
        row.text = ns.UI.Label(row, "GameFontHighlightSmall")
        row.text:SetPoint("LEFT", 0, 0)
        row.unmute = button(row, 70, 16)
        row.unmute:SetPoint("RIGHT", 0, 0)
        row.unmute:SetScript("OnClick", act(function() if row.key then setMuted(row.key, false) end end))
        row:Hide()
        f.muted[i] = row
    end
    local mutedArea = CreateFrame("Frame", nil, f)
    mutedArea:SetSize(W - 40, MUTED_ROWS * 16)
    mutedArea:SetPoint("TOPLEFT", 28, y - 92)
    mutedArea:EnableMouseWheel(true)
    mutedArea:SetScript("OnMouseWheel", safe(function(_, delta) f.mutedOff = f.mutedOff - delta refreshWindow() end))
    f.mutedArea = mutedArea
    f.stateLine = ns.UI.Label(f, "GameFontDisableSmall")
    f.stateLine:SetPoint("BOTTOMLEFT", 12, 60)
    f.topicLabel = ns.UI.Label(f, "GameFontHighlightSmall")
    f.topicLabel:SetPoint("BOTTOMLEFT", 16, 40)
    f.topics = {}
    for i, topic in ipairs(TOPICS) do
        local tb = button(f, 80, 18)
        tb:SetPoint("BOTTOMLEFT", 100 + (i - 1) * 84, 36)
        tb.label:SetText(topic)
        tb:SetScript("OnClick", act(function() Assist.Ask(topic) end))
        f.topics[topic] = tb
    end
    f.sample = button(f, 160, 20)
    f.sample:SetPoint("BOTTOMLEFT", 12, 12)
    f.sample:SetScript("OnClick", act(function() Assist.Test() end))
    f:SetScript("OnShow", safe(function() refreshWindow() end))
    if type(_G.UISpecialFrames) == "table" then
        _G.UISpecialFrames[#_G.UISpecialFrames + 1] = "HelloForeverAssistWindow"
    end
    f:Hide()
    win = f
end

local function check(on) return (on and "|cff40ff40[x]|r " or "[  ] ") end

-- The offset into a list of n shown `rows` at a time, kept in range; and the head's range text.
local function page(at, n, rows)
    at = math.max(0, math.min(at, n - rows))
    return at, n > rows and ("  %d-%d / %d"):format(at + 1, at + rows, n) or ""
end

refreshWindow = function()
    if not win or not win:IsShown() then return end
    local fight = ns.InCombat()
    local on = isOn()
    win.title:SetText("HelloForever  |cff808080" .. T("title") .. "|r")
    local list = on and Assist.Cards() or {}
    local range
    win.cardOff, range = page(win.cardOff, #list, ROWS)
    win.cardsHead:SetText(T("cards") .. range)
    win.note:SetText(fight and T("in_combat") or (not on and T("is_off")) or (#list == 0 and T("no_cards")) or "")
    for i, row in ipairs(win.rows) do
        local c = list[i + win.cardOff]
        if c then
            row.text:SetText(c.text)
            row.sub:SetText(T("from_" .. c.src) .. SEP .. c.basis .. SEP .. ago(c.at))
            row.away.card, row.mute.card = c, c
            row.away.label:SetText(T("away"))
            row.mute.label:SetText(T("mute"))
            grey(row.away, fight)
            grey(row.mute, fight)
            row:Show()
        else
            row.away.card, row.mute.card = nil, nil
            row:Hide()
        end
    end
    win.setHead:SetText(T("settings"))
    win.onCheck.label:SetText(check(on) .. T("on"))
    win.outsideCheck.label:SetText(check(ns.settings.assistOutside) .. T("outside"))
    win.langLabel:SetText(T("lang"))
    for code, lb in pairs(win.lang) do
        lb.label:SetTextColor(1, code == ns.settings.assistLang and 0.82 or 1, code == ns.settings.assistLang and 0 or 1)
        grey(lb, fight)
    end
    grey(win.onCheck, fight)
    grey(win.outsideCheck, fight)
    local keys = {}
    for k in pairs(muted()) do keys[#keys + 1] = k end
    sort(keys)
    win.mutedOff, range = page(win.mutedOff, #keys, MUTED_ROWS)
    win.mutedLabel:SetText(T("muted") .. (#keys == 0 and ("  " .. T("none_muted")) or range))
    for i, row in ipairs(win.muted) do
        local key = keys[i + win.mutedOff]
        row.key = key
        if key then
            row.text:SetText(key)
            row.unmute.label:SetText(T("unmute"))
            grey(row.unmute, fight)
            row:Show()
        else
            row:Hide()
        end
    end
    win.sample.label:SetText(T("sample_btn"))
    grey(win.sample, fight or not on)
    win.topicLabel:SetText(T("topics"))
    for _, tb in pairs(win.topics) do grey(tb, fight or not on) end
    local la = link()
    if not la then
        win.stateLine:SetText(T("state_no_link"))
    elseif not la.strip then
        win.stateLine:SetText(T("state_off"))
    else
        local left, t = la.left, la.seq ~= nil and la.t or nil
        win.stateLine:SetText(T("state"):format(left ~= nil and tostring(left) or "?", type(t) == "number" and ago(t) or T("state_never")))
    end
end

-- Opens the window: from the bar, the panel's menu, the fight window, the settings page and
-- /hello assist. It opens with the assistant off, with no card and with the panel hidden.
function Assist.Open()
    if not win then
        local ok, err = pcall(buildWindow)
        if not ok then
            win = nil
            say("the assistant's window is unavailable on this client (" .. tostring(err) .. ").")
            return
        end
    end
    win:Show()
    refreshWindow()
end

-- A page in the game's settings with one button that opens the window (seen 15 Nov 2026:
-- Settings.RegisterCanvasLayoutCategory and RegisterAddOnCategory exist, plan/05 section 9).
function Assist.SettingsPage()
    local S = _G.Settings
    if type(S) ~= "table" or type(S.RegisterCanvasLayoutCategory) ~= "function"
        or type(S.RegisterAddOnCategory) ~= "function" then return end
    local f = CreateFrame("Frame")
    f.open = button(f, 180, 22, "GameFontNormal")
    f.open:SetPoint("TOPLEFT", 16, -16)
    f.open.label:SetText(T("open"))
    f.open:SetScript("OnClick", safe(function() Assist.Open() end))
    f.settings = button(f, 180, 22, "GameFontNormal")
    f.settings:SetPoint("TOPLEFT", 16, -44)
    f.settings.label:SetText("Settings")
    f.settings:SetScript("OnClick", safe(function() ns.UI.OpenSettings() end))
    S.RegisterAddOnCategory(S.RegisterCanvasLayoutCategory(f, "HelloForever"))
end

----------------------------------------------------------------------
-- Wiring
----------------------------------------------------------------------
ns.Listen("PANEL", function() ns.AfterCombat("assist-place", safe(placeBar)) end) -- decision 7
ns.On("PLAYER_LOGIN", function()
    muted()
    publish()
    pcall(Assist.SettingsPage)
    local tick = _G.C_Timer and _G.C_Timer.NewTicker
    if type(tick) == "function" then tick(1, safe(syncOutside)) end -- HelloLink's table, once a second
end)
local function combatChanged() if refreshWindow then pcall(refreshWindow) end end
ns.On("PLAYER_REGEN_DISABLED", function()
    pcall(freezeBar)
    combatChanged()
end)
ns.On("PLAYER_REGEN_ENABLED", function()
    ns.AfterCombat("assist-place", safe(placeBar))
    ns.AfterCombat("assist-target", targetChanged) -- a target picked in the fight
    combatChanged()
end)
