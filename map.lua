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
if GuildHelper.GuildMap then
    GuildHelper:RegisterSharedSettings({
        keys = {"GUILDMEMBERPINS", "GUILDMEMBERLEVEL", "GUILDMEMBERNAME", "GUILDMEMBERSHARE", "GUILDMEMBERZONES"},
        getDB = function()
            GHTABPC = GHTABPC or {}

            return GHTABPC
        end,
        get = function(key)
            local value = GHTABPC[key]
            if value == nil and MAUTTAB then value = MAUTTAB[key] end
            if value == nil then value = key == "GUILDMEMBERPINS" or key == "GUILDMEMBERSHARE" or key == "GUILDMEMBERZONES" end
            GHTABPC[key] = value

            return value
        end,
        set = function(key, value) GuildHelper:SetConfig(key, value) end,
        onChange = function()
            GuildHelper.GuildMap.Refresh()
            GuildHelper.Settings:UpdateMap()
        end
    })
end
