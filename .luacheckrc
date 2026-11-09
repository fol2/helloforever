-- luacheck configuration for the HelloForever addon and its test harness.
std = "lua51"
max_line_length = false
codes = true
exclude_files = { "tests/*_SV.lua" }

files["HelloForever/*.lua"] = {
    ignore = { "211/addonName" }, -- every file opens with `local addonName, ns = ...`
    globals = {
        "HelloForeverDB", "SlashCmdList", "SLASH_HELLOFOREVER1",
        "HelloForever_OnAddonCompartmentClick", "HelloForever_OnAddonCompartmentEnter",
        "HelloForever_OnAddonCompartmentLeave",
    },
    read_globals = {
        "CreateFrame", "UIParent", "GetTime", "time", "date", "C_Timer",
        "UnitName", "GetRealmName", "UnitLevel", "UnitXP", "UnitXPMax", "UnitClass", "UnitRace",
        "UnitFactionGroup", "UnitStat", "UnitAttackPower", "UnitRangedAttackPower", "UnitArmor",
        "GetMoney", "GetXPExhaustion", "GetRealZoneText", "GetZoneText", "GetSubZoneText",
        "GetCritChance", "GetRangedCritChance", "GetHitModifier", "GetSpellHitModifier",
        "GetDodgeChance", "GetParryChance", "GetBlockChance",
        "GetInventoryItemLink", "GetInventoryItemID",
    },
}

files["tests/*.lua"] = {
    ignore = { "111", "112", "113", "121", "122", "131", "211", "212", "213", "311", "411", "421", "431", "432", "542", "611", "612", "631" },
}
