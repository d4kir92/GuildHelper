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

function GuildHelper:ToggleWindow()
    GuildHelper.Window:Toggle()
end

function GuildHelper:InitMinimapButton()
    local icon = GuildHelper:GetAddonIcon()
    GuildHelper:CreateMinimapButton({
        ["name"] = "GuildHelper",
        ["icon"] = icon,
        ["dbtab"] = GHTABPC,
        ["vTT"] = {{format("|T%s:16:16:0:0|t GuildHelper", icon), "v" .. (GuildHelper:GetVersion() or "")}, {GuildHelper:Trans("LID_LEFTCLICK"), GuildHelper:Trans("LID_OPENWINDOW")}, {GuildHelper:Trans("LID_RIGHTCLICK"), GuildHelper:Trans("LID_HIDEMINIMAPBUTTON")}},
        ["funcL"] = function() GuildHelper:ToggleWindow() end,
        ["funcR"] = function() GuildHelper:HideMMBtn("GuildHelper") end,
        ["dbkey"] = "MMBTN"
    })
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
