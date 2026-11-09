-- HelloForever / UI.lua
-- The on-screen parts: the XP panel (bar, rate, last fight), its tooltip and menu, and the
-- fight history window. Nothing here feeds the saved data; if a widget call fails on some
-- client the panel is switched off with one chat line and capture carries on.
--
-- Frames are plain (non-secure) and only ever show values that are not secret: XP, money,
-- and fight numbers that were read after combat.
local addonName, ns = ...

local type, pairs, ipairs, tostring, tonumber, pcall = type, pairs, ipairs, tostring, tonumber, pcall
local floor, min, max, abs = math.floor, math.min, math.max, math.abs
local sort, concat = table.sort, table.concat
local call = ns.Call

local UI = {}
ns.UI = UI

local WHITE = "Interface\\Buttons\\WHITE8x8"
local PANEL_W = 204
local PAD = 8

local fmtBig = _G.BreakUpLargeNumbers or tostring

local function classColor()
    local _, classFile = call(UnitClass, "player")
    local colors = _G.RAID_CLASS_COLORS
    local c = classFile and type(colors) == "table" and colors[classFile]
    if type(c) == "table" and c.r then return c.r, c.g, c.b end
    return 0.2, 1, 0.6
end

-- Flat dark panel with a 1 px outline and a class-coloured strip along the top.
local function skin(f, alpha, r, g, b)
    local bg = f:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    bg:SetColorTexture(0.04, 0.045, 0.06, alpha or 0.88)
    local function edge(a, b2, vertical)
        local t = f:CreateTexture(nil, "BORDER")
        t:SetColorTexture(0, 0, 0, 1)
        t:SetPoint(a)
        t:SetPoint(b2)
        if vertical then t:SetWidth(1) else t:SetHeight(1) end
    end
    edge("TOPLEFT", "TOPRIGHT")
    edge("BOTTOMLEFT", "BOTTOMRIGHT")
    edge("TOPLEFT", "BOTTOMLEFT", true)
    edge("TOPRIGHT", "BOTTOMRIGHT", true)
    local strip = f:CreateTexture(nil, "ARTWORK")
    strip:SetColorTexture(r, g, b, 0.9)
    strip:SetPoint("TOPLEFT", 1, -1)
    strip:SetPoint("TOPRIGHT", -1, -1)
    strip:SetHeight(2)
    return bg
end

local function label(parent, font, justify)
    local fs = parent:CreateFontString(nil, "OVERLAY", font or "GameFontHighlightSmall")
    fs:SetJustifyH(justify or "LEFT")
    fs:SetWordWrap(false)
    return fs
end

-- SetText only when the text changed (the panel refreshes once a second).
local function setText(fs, text)
    if fs._text ~= text then
        fs._text = text
        fs:SetText(text)
    end
end

----------------------------------------------------------------------
-- XP panel
----------------------------------------------------------------------
local panel
local rateKey, etaKey

local function savePosition(self)
    local point, _, relPoint, x, y = self:GetPoint()
    if point then ns.db.pos = { point, relPoint, x, y } end
end

local function restorePosition(self)
    local pos = ns.db.pos
    self:ClearAllPoints()
    if type(pos) == "table" and type(pos[1]) == "string" and type(pos[3]) == "number" then
        self:SetPoint(pos[1], UIParent, pos[2] or pos[1], pos[3], pos[4] or 0)
    else
        self:SetPoint("TOP", UIParent, "TOP", 0, -120)
    end
end

local function lastFightText()
    local s = ns.session.last
    local dim = false
    if not s then
        -- nothing fought yet this session: show the newest stored fight, dimmed
        local sum = ns.FightsSummary()
        for i = #sum, 1, -1 do
            if not sum[i].gap then s = sum[i] break end
        end
        dim = true
    end
    if not s then return nil end
    local name = tostring(s.name or "?")
    if #name > 22 then name = name:sub(1, 21) .. "." end
    return ("%s%s|r  %s  |cffffd100%s|r dps%s"):format(
        dim and "|cff808080" or "|cffd0d0d0", name, ns.FmtDur(s.dur or 0),
        ns.FmtNum(s.dps or 0), s.died and "  |cffff4040died|r" or "")
end

local function layoutPanel()
    local text = lastFightText()
    if text then
        setText(panel.fight, text)
        panel.fight:Show()
        panel:SetHeight(66)
    else
        panel.fight:Hide()
        panel:SetHeight(52)
    end
end

local function updateXP()
    if not panel then return end
    local cur, mx = call(UnitXP, "player"), call(UnitXPMax, "player")
    local lvl = call(UnitLevel, "player")
    local capped = not cur or not mx or mx <= 0
    panel.capped = capped
    if capped then
        setText(panel.level, "Level " .. tostring(lvl or "?"))
        setText(panel.pct, "max level")
        panel.bar:SetMinMaxValues(0, 1)
        panel.bar:SetValue(1)
        panel.bar:SetStatusBarColor(0.95, 0.75, 0.2)
        panel.rest:SetValue(0)
    else
        local rested = call(GetXPExhaustion) or 0
        setText(panel.level, "Level " .. tostring(lvl or "?"))
        setText(panel.pct, ("%.1f%%"):format(cur / mx * 100))
        panel.bar:SetMinMaxValues(0, mx)
        panel.bar:SetValue(cur)
        panel.rest:SetMinMaxValues(0, mx)
        panel.rest:SetValue(rested > 0 and min(mx, cur + rested) or 0)
        if rested > 0 then
            panel.bar:SetStatusBarColor(0.1, 0.45, 0.95) -- rested: blue
        else
            panel.bar:SetStatusBarColor(0.62, 0.2, 0.75) -- normal: purple
        end
    end
    rateKey, etaKey = nil, nil
end

-- Once a second while the panel is shown. The text is only rebuilt when the number it
-- shows actually changed.
local function updateRates()
    if not panel then return end
    if panel.capped then
        local _, perHour = ns.MoneyRate()
        local k = floor(perHour / 100)
        local e = floor((GetTime() - (ns.session.start or GetTime())) / 60)
        if k ~= rateKey then
            rateKey = k
            setText(panel.rate, ns.FmtMoney(k * 100) .. " /h")
        end
        if e ~= etaKey then
            etaKey = e
            setText(panel.eta, "session " .. ns.FmtDur(e * 60))
        end
        return
    end
    local perHour, eta = ns.XPRate()
    local k = floor(perHour + 0.5)
    local e = eta and (eta >= 3600 and floor(eta / 60) * 60 or floor(eta)) or -1
    if k ~= rateKey then
        rateKey = k
        setText(panel.rate, ("|cffffffff%s|r XP/h"):format(k >= 100000 and ns.FmtNum(k) or fmtBig(k)))
    end
    if e ~= etaKey then
        etaKey = e
        setText(panel.eta, e >= 0 and ("level in |cffffffff" .. ns.FmtDur(e) .. "|r") or "level in --")
    end
end

local function showTooltip(owner, anchor)
    local tip = _G.GameTooltip
    if not tip then return end
    local s = ns.session
    tip:SetOwner(owner, anchor or "ANCHOR_BOTTOMLEFT")
    tip:AddLine("HelloForever " .. ns.version, 0.2, 1, 0.6)
    local elapsed = GetTime() - (s.start or GetTime())
    tip:AddDoubleLine("Session", ns.FmtDur(elapsed), 0.8, 0.8, 0.8, 1, 1, 1)
    local perHour = ns.XPRate()
    tip:AddDoubleLine("XP gained", ("%s (%s/h)"):format(fmtBig(s.xp or 0), ns.FmtNum(perHour)), 0.8, 0.8, 0.8, 1, 1, 1)
    local rested, mx = call(GetXPExhaustion), call(UnitXPMax, "player")
    if rested and rested > 0 and mx and mx > 0 then
        tip:AddDoubleLine("Rested", ("%s (%.0f%%)"):format(fmtBig(rested), rested / mx * 100), 0.8, 0.8, 0.8, 0.4, 0.7, 1)
    end
    local delta, moneyRate = ns.MoneyRate()
    tip:AddDoubleLine("Gold", ("%s%s (%s/h)"):format(delta >= 0 and "+" or "", ns.FmtMoney(delta), ns.FmtMoney(moneyRate)),
        0.8, 0.8, 0.8, 1, 1, 1)
    if (s.fights or 0) > 0 then
        local avg = (s.fightSec or 0) > 0 and (s.dmg or 0) / s.fightSec or 0
        tip:AddDoubleLine("Fights", ("%d, %s dmg, %s dps avg"):format(s.fights, ns.FmtNum(s.dmg), ns.FmtNum(avg)),
            0.8, 0.8, 0.8, 1, 1, 1)
        if (s.bestDps or 0) > 0 then
            tip:AddDoubleLine("Best fight", ("%s dps (%s)"):format(ns.FmtNum(s.bestDps), tostring(s.bestName)),
                0.8, 0.8, 0.8, 1, 0.82, 0)
        end
        if (s.deaths or 0) > 0 then
            tip:AddDoubleLine("Deaths", tostring(s.deaths), 0.8, 0.8, 0.8, 1, 0.3, 0.3)
        end
    end
    local n, _, _, bytes, _, budget = ns.FightsStats()
    tip:AddDoubleLine("Fight log", ("%d fights, %.0f of %.0f KB"):format(n, bytes / 1024, budget / 1024),
        0.8, 0.8, 0.8, 0.7, 0.7, 0.7)
    tip:AddLine(" ")
    tip:AddLine("Click: fight history   Right-click: menu", 0.5, 0.5, 0.5)
    if not ns.settings.locked then tip:AddLine("Drag to move", 0.5, 0.5, 0.5) end
    tip:Show()
end
UI.ShowTooltip = showTooltip

local function hideTooltip()
    if _G.GameTooltip then _G.GameTooltip:Hide() end
end

local ticker

local function startTicker()
    if ticker then return end
    ticker = ns.Ticker(1, updateRates)
end

local function stopTicker()
    if ticker and ticker.Cancel then ticker:Cancel() end
    ticker = nil
end

local function buildPanel()
    local r, g, b = classColor()
    local f = CreateFrame("Frame", "HelloForeverFrame", UIParent)
    f:SetSize(PANEL_W, 52)
    f:SetClampedToScreen(true)
    f:SetMovable(true)
    f:EnableMouse(true)
    f:RegisterForDrag("LeftButton")
    skin(f, 0.88, r, g, b)

    f.level = label(f, "GameFontNormalSmall")
    f.level:SetPoint("TOPLEFT", PAD, -8)
    f.level:SetTextColor(r, g, b)
    f.pct = label(f, "GameFontHighlightSmall", "RIGHT")
    f.pct:SetPoint("TOPRIGHT", -PAD, -8)

    local track = f:CreateTexture(nil, "ARTWORK")
    track:SetColorTexture(1, 1, 1, 0.08)
    track:SetPoint("TOPLEFT", PAD, -22)
    track:SetPoint("TOPRIGHT", -PAD, -22)
    track:SetHeight(8)

    local level = f:GetFrameLevel()
    local rest = CreateFrame("StatusBar", nil, f)
    rest:SetPoint("TOPLEFT", PAD, -22)
    rest:SetPoint("TOPRIGHT", -PAD, -22)
    rest:SetHeight(8)
    rest:SetFrameLevel(level + 1)
    rest:SetStatusBarTexture(WHITE)
    rest:SetStatusBarColor(0.1, 0.45, 0.95, 0.35)
    rest:SetMinMaxValues(0, 1)
    rest:SetValue(0)
    f.rest = rest

    local bar = CreateFrame("StatusBar", nil, f)
    bar:SetPoint("TOPLEFT", PAD, -22)
    bar:SetPoint("TOPRIGHT", -PAD, -22)
    bar:SetHeight(8)
    bar:SetFrameLevel(level + 2)
    bar:SetStatusBarTexture(WHITE)
    bar:SetMinMaxValues(0, 1)
    bar:SetValue(0)
    f.bar = bar

    f.rate = label(f, "GameFontDisableSmall")
    f.rate:SetPoint("TOPLEFT", PAD, -35)
    f.eta = label(f, "GameFontDisableSmall", "RIGHT")
    f.eta:SetPoint("TOPRIGHT", -PAD, -35)

    f.fight = label(f, "GameFontHighlightSmall")
    f.fight:SetPoint("TOPLEFT", PAD, -49)
    f.fight:SetWidth(PANEL_W - PAD * 2)
    f.fight:Hide()

    f:SetScript("OnDragStart", function(self)
        if ns.settings.locked then return end
        self.dragged = true
        self:StartMoving()
    end)
    f:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        -- the position lives in HelloForeverDB.pos; keep the client's layout cache out of it
        self:SetUserPlaced(false)
        savePosition(self)
        ns.After(0.1, function() self.dragged = nil end)
    end)
    f:SetScript("OnMouseUp", function(self, button)
        if self.dragged then return end
        if button == "RightButton" then
            UI.OpenMenu(self)
        else
            UI.ToggleFights()
        end
    end)
    f:SetScript("OnEnter", function(self) showTooltip(self) end)
    f:SetScript("OnLeave", hideTooltip)
    f:SetScript("OnShow", function()
        updateXP()
        updateRates()
        startTicker()
    end)
    f:SetScript("OnHide", stopTicker)

    panel = f
    f:SetScale(tonumber(ns.settings.scale) or 1)
    restorePosition(f)
    layoutPanel()
    updateXP()
    updateRates()
    if ns.settings.shown then
        startTicker()
    else
        f:Hide()
    end
end

function UI.SetShown(shown)
    ns.settings.shown = shown and true or false
    if not panel then return end
    if shown then panel:Show() else panel:Hide() end
end

function UI.SetLocked(locked)
    ns.settings.locked = locked and true or false
end

function UI.SetScale(scale)
    scale = tonumber(scale) or 1
    if scale < 0.5 then scale = 0.5 elseif scale > 2.5 then scale = 2.5 end
    ns.settings.scale = scale
    if panel then
        panel:SetScale(scale)
        restorePosition(panel)
    end
end

function UI.ResetPosition()
    ns.db.pos = nil
    if panel then restorePosition(panel) end
end

----------------------------------------------------------------------
-- Fight detail text (decoded on demand from the stored record)
----------------------------------------------------------------------
-- JSON round trips may hand an array back with string keys; accept both.
local function arr(t)
    if type(t) ~= "table" then return {} end
    if t[1] ~= nil then return t end
    local out = {}
    for k, v in pairs(t) do
        local i = tonumber(k)
        if i then out[#out + 1] = { i, v } end
    end
    sort(out, function(a, b) return a[1] < b[1] end)
    for i = 1, #out do out[i] = out[i][2] end
    return out
end

-- The player's source row of one meter type and that row's spell list.
local function mine(rec, typeName)
    local ty = type(rec.types) == "table" and rec.types[typeName]
    if type(ty) ~= "table" then return nil, {} end
    local sources, by = arr(ty.combatSources), arr(ty.bySource)
    for i = 1, #sources do
        if sources[i].isLocalPlayer then
            local b = by[i]
            return sources[i], type(b) == "table" and arr(b.combatSpells) or {}
        end
    end
    return nil, {}
end

local function byAmount(a, b) return (a.totalAmount or 0) > (b.totalAmount or 0) end

local function spellLabel(sp, useUnit)
    local name = ns.SpellName(sp.spellID) or ("spell " .. tostring(sp.spellID))
    if type(sp.creatureName) == "string" and sp.creatureName ~= "" then
        name = name .. " |cff808080(" .. sp.creatureName .. ")|r"
    end
    local det = sp.combatSpellDetails
    if useUnit and type(det) == "table" and type(det.unitName) == "string" and det.unitName ~= "" then
        name = det.unitName .. ": " .. name
    end
    return name
end

local function section(lines, title, src, spells, top, useUnit)
    if not src or (src.totalAmount or 0) <= 0 then return end
    lines[#lines + 1] = " "
    lines[#lines + 1] = ("|cffffd100%s|r  %s  |cff808080(%s/s)|r"):format(
        title, fmtBig(floor(src.totalAmount + 0.5)), ns.FmtNum(src.amountPerSecond or 0))
    local list = {}
    for i = 1, #spells do list[i] = spells[i] end
    sort(list, byAmount)
    for i = 1, min(top, #list) do
        local sp = list[i]
        local amount = sp.totalAmount or 0
        lines[#lines + 1] = ("  %s  |cffffffff%s|r |cff808080%.0f%%|r"):format(
            spellLabel(sp, useUnit), ns.FmtNum(amount), amount / src.totalAmount * 100)
    end
    if #list > top then
        lines[#lines + 1] = ("  |cff808080+ %d more|r"):format(#list - top)
    end
end

function UI.FightDetail(s)
    if s.gap then
        return ("|cffff8800Gap|r\n\nSession %s was reported by the meter but could not be read (%s)."):format(
            tostring(s.key), tostring(s.gap))
    end
    local lines = {}
    lines[1] = ("|cffffffff%s|r"):format(tostring(s.name or "?"))
    lines[2] = ("%s  |cff808080%s%s|r"):format(date("%Y-%m-%d %H:%M:%S", s.t or 0), ns.FmtDur(s.dur or 0),
        (s.rev or 1) > 1 and (", revision " .. s.rev) or "")
    local rec, why = ns.FightsLoad(s.key)
    if not rec then
        lines[#lines + 1] = " "
        lines[#lines + 1] = ("Damage %s (%s dps)"):format(ns.FmtNum(s.dmg), ns.FmtNum(s.dps))
        lines[#lines + 1] = ("Healing %s   Taken %s"):format(ns.FmtNum(s.heal), ns.FmtNum(s.taken))
        lines[#lines + 1] = " "
        lines[#lines + 1] = "|cff808080Details unavailable: " .. tostring(why) .. "|r"
        return concat(lines, "\n")
    end
    if rec.zone then
        lines[#lines + 1] = ("|cff808080%s%s, level %s|r"):format(tostring(rec.zone),
            (rec.subzone and rec.subzone ~= "") and (" - " .. rec.subzone) or "", tostring(rec.lvl or "?"))
    end
    local dsrc, dspells = mine(rec, "DamageDone")
    section(lines, "Damage", dsrc, dspells, 8)
    local hsrc, hspells = mine(rec, "HealingDone")
    section(lines, "Healing", hsrc, hspells, 4)
    local tsrc, tspells = mine(rec, "DamageTaken")
    section(lines, "Damage taken", tsrc, tspells, 5, true)
    if s.died then
        lines[#lines + 1] = " "
        lines[#lines + 1] = "|cffff4040Died in this fight|r"
        if type(rec.recaps) == "table" then
            for _, r in pairs(rec.recaps) do
                local events = arr(type(r) == "table" and r.events or nil)
                for i = 1, min(3, #events) do
                    local e = events[i]
                    if type(e) == "table" then
                        lines[#lines + 1] = ("  %s  |cffff8080-%s|r%s"):format(
                            tostring(e.sourceName or e.event or "?"), ns.FmtNum(e.amount or 0),
                            (e.overkill or 0) > 0 and (" |cff808080(overkill " .. ns.FmtNum(e.overkill) .. ")|r") or "")
                    end
                end
            end
        end
    end
    return concat(lines, "\n")
end

----------------------------------------------------------------------
-- Fight history window (built the first time it is opened)
----------------------------------------------------------------------
local ROWS = 15
local ROW_H = 19
local LIST_W = 330
local WIN_W, WIN_H = 640, 372

local win
local offset = 0
local selected

local function refreshWindow()
    if not win or not win:IsShown() then return end
    local sum = ns.FightsSummary()
    local n = #sum
    local maxOffset = max(0, n - ROWS)
    if offset > maxOffset then offset = maxOffset end
    if offset < 0 then offset = 0 end
    local selSummary
    for i = 1, ROWS do
        local row = win.rows[i]
        local s = sum[n - offset - i + 1] -- newest first
        row.summary = s
        if s then
            row.time:SetText(date("%H:%M", s.t or 0))
            if s.gap then
                row.name:SetText("|cffff8800gap|r (" .. tostring(s.gap) .. ")")
                row.dur:SetText("")
                row.dmg:SetText("")
                row.dps:SetText("")
            else
                row.name:SetText((s.died and "|cffff6060" or "|cffffffff") .. tostring(s.name or "?") .. "|r")
                row.dur:SetText(ns.FmtDur(s.dur or 0))
                row.dmg:SetText(ns.FmtNum(s.dmg))
                row.dps:SetText(ns.FmtNum(s.dps))
            end
            if selected == s.key then
                row.sel:Show()
                selSummary = s
            else
                row.sel:Hide()
            end
            row:Show()
        else
            row:Hide()
        end
    end
    local total, days, _, bytes, _, budget = ns.FightsStats()
    win.status:SetText(("%d fights in %d day(s), %.0f of %.0f KB.  Showing the newest %d."):format(
        total, days, bytes / 1024, budget / 1024, n))
    if n > ROWS then
        win.thumb:Show()
        local trackH = ROWS * ROW_H
        local h = max(16, trackH * ROWS / n)
        win.thumb:SetHeight(h)
        win.thumb:ClearAllPoints()
        win.thumb:SetPoint("TOPRIGHT", win.list, "TOPRIGHT", 0, -(trackH - h) * (maxOffset > 0 and offset / maxOffset or 0))
    else
        win.thumb:Hide()
    end
    if selSummary and win.detailKey ~= selected .. ":" .. tostring(selSummary.rev) then
        win.detailKey = selected .. ":" .. tostring(selSummary.rev)
        local ok, text = pcall(UI.FightDetail, selSummary)
        win.detail:SetText(ok and text or ("|cffff4040Could not read this fight:|r\n" .. tostring(text)))
    elseif not selected then
        win.detailKey = nil
        win.detail:SetText(n > 0 and "|cff808080Select a fight to see its breakdown.|r"
            or "|cff808080No fights yet. They are read the moment combat ends.|r")
    end
end

local function column(row, x, width, justify, font)
    local fs = label(row, font or "GameFontHighlightSmall", justify)
    fs:SetPoint("LEFT", x, 0)
    fs:SetWidth(width)
    return fs
end

local function buildWindow()
    local r, g, b = classColor()
    local f = CreateFrame("Frame", "HelloForeverFights", UIParent)
    f:SetSize(WIN_W, WIN_H)
    f:SetPoint("CENTER")
    f:SetFrameStrata("DIALOG")
    f:SetClampedToScreen(true)
    f:SetMovable(true)
    f:EnableMouse(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", f.StartMoving)
    f:SetScript("OnDragStop", f.StopMovingOrSizing)
    skin(f, 0.94, r, g, b)

    local title = label(f, "GameFontNormal")
    title:SetPoint("TOPLEFT", 12, -12)
    title:SetText("HelloForever  |cff808080fights|r")
    title:SetTextColor(r, g, b)

    local close = CreateFrame("Button", nil, f)
    close:SetSize(20, 20)
    close:SetPoint("TOPRIGHT", -6, -7)
    local x = label(close, "GameFontNormal", "CENTER")
    x:SetPoint("CENTER")
    x:SetText("x")
    close:SetScript("OnClick", function() f:Hide() end)
    close:SetScript("OnEnter", function() x:SetTextColor(1, 0.3, 0.3) end)
    close:SetScript("OnLeave", function() x:SetTextColor(1, 0.82, 0) end)

    -- column headers
    local head = CreateFrame("Frame", nil, f)
    head:SetSize(LIST_W, ROW_H)
    head:SetPoint("TOPLEFT", 12, -34)
    column(head, 4, 40, "LEFT", "GameFontDisableSmall"):SetText("Time")
    column(head, 46, 138, "LEFT", "GameFontDisableSmall"):SetText("Fight")
    column(head, 186, 44, "RIGHT", "GameFontDisableSmall"):SetText("Length")
    column(head, 232, 44, "RIGHT", "GameFontDisableSmall"):SetText("Damage")
    column(head, 278, 40, "RIGHT", "GameFontDisableSmall"):SetText("DPS")

    local list = CreateFrame("Frame", nil, f)
    list:SetSize(LIST_W, ROWS * ROW_H)
    list:SetPoint("TOPLEFT", head, "BOTTOMLEFT", 0, -2)
    list:EnableMouseWheel(true)
    list:SetScript("OnMouseWheel", function(_, delta)
        offset = offset - delta * 3
        refreshWindow()
    end)
    local listBg = list:CreateTexture(nil, "BACKGROUND")
    listBg:SetAllPoints()
    listBg:SetColorTexture(1, 1, 1, 0.03)
    f.list = list

    f.thumb = list:CreateTexture(nil, "OVERLAY")
    f.thumb:SetColorTexture(1, 1, 1, 0.25)
    f.thumb:SetWidth(3)
    f.thumb:Hide()

    f.rows = {}
    for i = 1, ROWS do
        local row = CreateFrame("Button", nil, list)
        row:SetSize(LIST_W - 6, ROW_H)
        row:SetPoint("TOPLEFT", 0, -(i - 1) * ROW_H)
        local hl = row:CreateTexture(nil, "HIGHLIGHT")
        hl:SetAllPoints()
        hl:SetColorTexture(1, 1, 1, 0.08)
        row.sel = row:CreateTexture(nil, "BACKGROUND")
        row.sel:SetAllPoints()
        row.sel:SetColorTexture(r, g, b, 0.22)
        row.sel:Hide()
        row.time = column(row, 4, 40, "LEFT", "GameFontDisableSmall")
        row.name = column(row, 46, 138, "LEFT")
        row.dur = column(row, 186, 44, "RIGHT")
        row.dmg = column(row, 232, 44, "RIGHT")
        row.dps = column(row, 278, 40, "RIGHT")
        row:SetScript("OnClick", function(self)
            if self.summary then
                selected = self.summary.key
                refreshWindow()
            end
        end)
        f.rows[i] = row
    end

    local detail = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    detail:SetPoint("TOPLEFT", list, "TOPRIGHT", 14, 0)
    detail:SetWidth(WIN_W - LIST_W - 12 - 14 - 12)
    detail:SetHeight(ROWS * ROW_H + ROW_H)
    detail:SetJustifyH("LEFT")
    detail:SetJustifyV("TOP")
    detail:SetWordWrap(true)
    f.detail = detail

    f.status = label(f, "GameFontDisableSmall")
    f.status:SetPoint("BOTTOMLEFT", 12, 10)

    f:SetScript("OnShow", refreshWindow)
    -- Escape closes it
    if type(_G.UISpecialFrames) == "table" then
        _G.UISpecialFrames[#_G.UISpecialFrames + 1] = "HelloForeverFights"
    end
    f:Hide()
    win = f
end

function UI.ToggleFights()
    if not win then
        local ok, err = pcall(buildWindow)
        if not ok then
            win = nil
            ns.Print("fight window unavailable on this client (" .. tostring(err) .. "); use /hello fights.")
            return
        end
    end
    if win:IsShown() then
        win:Hide()
    else
        offset = 0
        local sum = ns.FightsSummary()
        if not selected and #sum > 0 then selected = sum[#sum].key end
        win:Show()
        refreshWindow()
    end
end

----------------------------------------------------------------------
-- Menu (right-click on the panel)
----------------------------------------------------------------------
local SCALES = { 0.8, 0.9, 1, 1.1, 1.25, 1.5 }
local LOG_MODES = { "off", "on", "auto" }

local function buildMenu(_, root)
    root:CreateTitle("HelloForever " .. ns.version)
    root:CreateButton("Fight history", UI.ToggleFights)
    root:CreateButton("Take snapshot now", function()
        if ns.AfterCombat("snap", function() ns.TakeSnapshot("menu") end) then
            ns.Print("snapshot saved.")
        else
            ns.Print("in combat: snapshot queued until the fight ends.")
        end
    end)
    root:CreateButton("Reset session counters", function() ns.ResetSession() end)
    root:CreateDivider()
    root:CreateCheckbox("Lock position", function() return ns.settings.locked end,
        function() UI.SetLocked(not ns.settings.locked) end)
    root:CreateCheckbox("Announce fights in chat", function() return ns.settings.announce end,
        function() ns.settings.announce = not ns.settings.announce end)
    local scale = root:CreateButton("Scale")
    for _, v in ipairs(SCALES) do
        scale:CreateRadio(("%d%%"):format(floor(v * 100 + 0.5)),
            function(value) return abs((tonumber(ns.settings.scale) or 1) - value) < 0.01 end,
            function(value) UI.SetScale(value) end, v)
    end
    local log = root:CreateButton("Combat log file")
    for _, mode in ipairs(LOG_MODES) do
        log:CreateRadio(mode, function(value) return ns.settings.combatLog == value end,
            function(value) ns.SetCombatLogMode(value) end, mode)
    end
    root:CreateDivider()
    root:CreateButton("Reset position", UI.ResetPosition)
    root:CreateButton("Hide panel  (/hello show)", function() UI.SetShown(false) end)
end

function UI.OpenMenu(owner)
    local MU = _G.MenuUtil
    if type(MU) == "table" and type(MU.CreateContextMenu) == "function" then
        if pcall(MU.CreateContextMenu, owner, buildMenu) then return end
    end
    ns.Print("type /hello help for the options.")
end

----------------------------------------------------------------------
-- Addon compartment (minimap addon list); the TOC names these globals
----------------------------------------------------------------------
function _G.HelloForever_OnAddonCompartmentClick(_, button)
    if button == "RightButton" then
        UI.SetShown(not ns.settings.shown)
    else
        UI.ToggleFights()
    end
end

function _G.HelloForever_OnAddonCompartmentEnter(_, menuButton)
    if menuButton then pcall(showTooltip, menuButton, "ANCHOR_LEFT") end
end

function _G.HelloForever_OnAddonCompartmentLeave()
    hideTooltip()
end

----------------------------------------------------------------------
-- Wiring
----------------------------------------------------------------------
local function onFight()
    if panel then layoutPanel() end
    refreshWindow()
end

ns.Listen("XP", updateXP)
ns.Listen("FIGHT", onFight)
ns.Listen("SESSION", function()
    if not panel then return end
    layoutPanel()
    updateXP()
    updateRates()
end)

ns.On("PLAYER_LOGIN", function()
    local ok, err = pcall(buildPanel)
    if not ok then
        panel = nil
        ns.Print("XP panel unavailable on this client (" .. tostring(err) .. "). Data capture is not affected.")
    end
end)

ns.On("PLAYER_ENTERING_WORLD", function()
    if panel then
        layoutPanel()
        updateXP()
    end
end)
