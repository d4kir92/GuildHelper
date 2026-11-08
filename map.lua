local _, GuildHelper = ...
if GuildHelper.CreateGuildMap == nil then return end
GuildHelper.GuildMap = GuildHelper:CreateGuildMap({
    owner = "GuildHelper",
    priority = 20
})
if GuildHelper.GuildMap then
    GuildHelper.GuildMap.Send = function(message)
        GuildHelper.Sync:Send(message, "map-position", GuildHelper.GuildMap.prefix)

        return true
    end
end
