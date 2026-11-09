local _, GuildHelper = ...
if GuildHelper.CreateGuildInvite == nil then return end
GuildHelper.INVITEDEFAULTS = {
    LINKS = {"GUILDINVITELINKS", true},
    KEYWORD = {"GUILDINVITEKEYWORD", false},
    WORD = {"GUILDINVITEWORD", ""}
}

GuildHelper.GuildInvite = GuildHelper:CreateGuildInvite({
    owner = "GuildHelper",
    priority = 20,
    whisperOnly = true,
    get = function(key)
        local entry = GuildHelper.INVITEDEFAULTS[key]

        return entry and GuildHelper:GetConfig(entry[1], entry[2])
    end,
    trans = function(key) return GuildHelper:Trans(key) end
})
