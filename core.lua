local _, GuildHelper = ...
function GuildHelper:GetConfig(key, value)
    GHTABPC = GHTABPC or {}
    if GHTABPC[key] == nil then GHTABPC[key] = value end

    return GHTABPC[key]
end

function GuildHelper:SetConfig(key, value)
    GHTABPC = GHTABPC or {}
    GHTABPC[key] = value
end

GuildHelper.LANGUAGES = {"enUS", "deDE", "esES", "esMX", "frFR", "itIT", "koKR", "ptBR", "ruRU", "zhCN", "zhTW"}
function GuildHelper:GetLanguage()
    local lang = GHTABPC and GHTABPC.LANGUAGE
    if lang and lang ~= "auto" then return lang end

    return GetLocale()
end

function GuildHelper:SetLanguage(value)
    GuildHelper:SetConfig("LANGUAGE", value)
    GuildHelper.Theme:RefreshTexts()
    GuildHelper.Theme:Refresh()
end

local baseTrans = GuildHelper.Trans
function GuildHelper:Trans(key, lang, ...)
    return baseTrans(self, key, lang or GuildHelper:GetLanguage(), ...)
end

function GuildHelper:ToggleWindow()
    GuildHelper.Window:Toggle()
end

function GuildHelper:GetMinimapTooltip(icon)
    return {{format("|T%s:16:16:0:0|t GuildHelper", icon), "v" .. (GuildHelper:GetVersion() or "")}, {GuildHelper:Trans("LID_LEFTCLICK"), GuildHelper:Trans("LID_OPENWINDOW")}, {GuildHelper:Trans("LID_RIGHTCLICK"), GuildHelper:Trans("LID_HIDEMINIMAPBUTTON")}}
end

function GuildHelper:InitMinimapButton()
    local icon = GuildHelper:GetAddonIcon()
    GuildHelper:GetConfig("MMBTN", true)
    local params = {
        ["name"] = "GuildHelper",
        ["icon"] = icon,
        ["dbtab"] = GHTABPC,
        ["vTT"] = GuildHelper:GetMinimapTooltip(icon),
        ["funcL"] = function() GuildHelper:ToggleWindow() end,
        ["funcR"] = function()
            GuildHelper:SetConfig("MMBTN", false)
            GuildHelper:HideMMBtn("GuildHelper")
        end,
        ["dbkey"] = "MMBTN"
    }

    GuildHelper:CreateMinimapButton(params)
    GuildHelper.Theme:OnRefresh(function() params.vTT = GuildHelper:GetMinimapTooltip(icon) end)
end

local loader = CreateFrame("Frame")
loader:RegisterEvent("PLAYER_LOGIN")
loader:SetScript("OnEvent", function(self, event)
    self:UnregisterEvent(event)
    GHTAB = GHTAB or {}
    GHTABPC = GHTABPC or {}
    GuildHelper:SetVersion()
    GuildHelper.Window:Create()
    GuildHelper.Sync:Init()
    GuildHelper.Members:Init()
    GuildHelper:InitMinimapButton()
    GuildHelper:AddSlash("guildhelper", GuildHelper.ToggleWindow)
    GuildHelper:AddSlash("guhe", GuildHelper.ToggleWindow)
end)
