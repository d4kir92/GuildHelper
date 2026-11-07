local _, GuildHelper = ...
if GuildHelper.CreateGuildMap == nil then return end
GuildHelper.GuildMap = GuildHelper:CreateGuildMap({
    owner = "GuildHelper",
    priority = 20
})
