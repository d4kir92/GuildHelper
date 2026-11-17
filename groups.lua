local _, GuildHelper = ...
local Groups = {}
GuildHelper.Groups = Groups
Groups.live = {}
Groups.seen = {}
Groups.sent = {}
Groups.applySent = {}
Groups.signupSnapshots = {}
Groups.signupSerial = 0
Groups.mode = "L"
Groups.modes = {
    {value = "L", label = "LID_GROUPLIVE"},
    {value = "P", label = "LID_GROUPPLANNED"},
    {value = "Q", label = "LID_GROUPQUEST"},
    {value = "Z", label = "LID_ZONE"}
}
Groups.role = "DAMAGER"
Groups.draft = {
    Q = {note = ""},
    Z = {note = ""},
    L = {
        note = ""
    },
    P = {
        note = "",
        TANK = 1,
        HEALER = 1,
        DAMAGER = 3,
        hour = 20,
        minute = 0
    }
}

Groups.TTL = 95
Groups.INTERVAL = 30
Groups.PLANINTERVAL = 60
Groups.KEEP = 3600
Groups.DAYS = 14
Groups.MAXPLANNED = 5
Groups.CATEGORY = 2
Groups.ROW = 66
Groups.roleOrder = {TANK = 1, HEALER = 2, DAMAGER = 3, NONE = 4}
Groups.WEEKDAYS = {"WEEKDAY_SUNDAY", "WEEKDAY_MONDAY", "WEEKDAY_TUESDAY", "WEEKDAY_WEDNESDAY", "WEEKDAY_THURSDAY", "WEEKDAY_FRIDAY", "WEEKDAY_SATURDAY"}
function Groups:Name(name)
    if type(name) ~= "string" or name == "" or #name > 96 or name:find("[~|%c#]") then return nil end
    if not name:find("-", 1, true) then name = name .. "-" .. (GetRealmName() or ""):gsub("%s", "") end

    return strlower(name:gsub("%s", ""))
end

function Groups:Self()
    local name, realm = (UnitFullName or UnitName)("player")

    return self:Name(name and (name .. "-" .. ((realm and realm ~= "") and realm or GetRealmName() or "")) or UnitName("player"))
end

function Groups:IsSelfName(name)
    local key = self:Name(name)
    if not key then return false end
    local own = self:Self()
    if key == own or key == self.selfSender then return true end
    local characterKey = GuildHelper:GetPlayerCharacterKey()
    if key == self:Name(characterKey) then return true end
    local member = GuildHelper.Members.GetSelf and GuildHelper.Members:GetSelf()
    if member and key == self:Name(member.name) then return true end

    local short = own and strsplit("-", own)
    return short ~= nil and key:sub(1, #short) == short and key == self:Name(GuildHelper.Sync:GetOwnName())
end

function Groups:IsOwn(entry)
    return entry ~= nil and entry.owner == self:Self()
end

function Groups:CleanText(value, limit)
    local text = (value or ""):gsub("[~|%c]", " "):gsub("%s+", " "):match("^%s*(.-)%s*$")
    local size = min(#text, max(0, limit))
    while size > 0 and text:byte(size + 1) and text:byte(size + 1) >= 128 and text:byte(size + 1) < 192 do
        size = size - 1
    end

    return text:sub(1, size)
end

function Groups:CheckGuild()
    local guild = GuildHelper.Sync:GetGuildKey()
    if guild ~= self.guild then
        self.guild = guild
        self.live = {}
        self.seen = {}
        self.sent = {}
        self.applySent = {}
        self.signupSnapshots = {}
        self.selected = nil
        self.editing = nil
        self.lastQuery = nil
        self.viewedListings = nil
        self.announcements = {}
    end

    return guild ~= nil
end

function Groups:GetViewedListings()
    if not self.guild then return end
    if not self.viewedListings then
        GHTABPC = GHTABPC or {}
        GHTABPC.GROUPSVIEWED = GHTABPC.GROUPSVIEWED or {}
        GHTABPC.GROUPSVIEWED[self.guild] = GHTABPC.GROUPSVIEWED[self.guild] or {}
        self.viewedListings = GHTABPC.GROUPSVIEWED[self.guild]
        local cutoff = time() - (self.DAYS + 2) * 86400
        for key, stamp in pairs(self.viewedListings) do
            if stamp < cutoff then self.viewedListings[key] = nil end
        end
    end
    return self.viewedListings
end

function Groups:CountUnread()
    if not self:CheckGuild() then return 0 end
    local viewed = self:GetViewedListings()
    local count = 0
    for _, listings in ipairs({self.live, self:GetPlanned()}) do
        for key, entry in pairs(listings) do
            if self:IsOwn(entry) then
                for _, applicant in pairs(entry.applicants or {}) do
                    if applicant.unread then count = count + 1 end
                end
            elseif not viewed[key] then
                count = count + 1
            end
        end
    end
    return count
end

function Groups:GetPlanned()
    if not self.guild then return nil end
    GHTAB = GHTAB or {}
    GHTAB.GROUPS = GHTAB.GROUPS or {}
    GHTAB.GROUPS[self.guild] = GHTAB.GROUPS[self.guild] or {}

    return GHTAB.GROUPS[self.guild]
end

function Groups:GetStore(kind)
    if kind == "P" then return self:GetPlanned() end

    return self.live
end

function Groups:Find(key)
    if not key then return nil end
    local planned = self:GetPlanned()

    return self.live[key] or (planned and planned[key])
end

function Groups:GetActivityMode(key)
    local prefix = key:sub(1, 1)
    if prefix == "q" then return "Q" end
    if prefix == "z" then return "Z" end

    return "L"
end

function Groups:GetListingMode(entry)
    return entry.kind == "P" and "P" or self:GetActivityMode(entry.activity)
end

function Groups:IsOutdoor(mode)
    return mode == "Q" or mode == "Z"
end

function Groups:GetOwnLive(mode)
    for _, entry in pairs(self.live) do
        if self:IsOwn(entry) and self:GetListingMode(entry) == mode then return entry end
    end

    return nil
end

function Groups:CountPlanned(owner)
    local count = 0
    for _, entry in pairs(self:GetPlanned() or {}) do
        if entry.owner == owner then count = count + 1 end
    end

    return count
end

function Groups:LevelRange(low, high)
    low = type(low) == "number" and low > 0 and low or nil
    high = type(high) == "number" and high > 0 and high or nil
    if low and high and high > low then return low, format("%d-%d", low, high) end
    if low or high then return low or high, tostring(low or high) end

    return nil, nil
end

Groups.loadingScreens = {
    [33] = 131869, [34] = 131870, [36] = 131833, [43] = 131882, [47] = 131865,
    [48] = 131823, [70] = 131876, [90] = 131841, [109] = 131872, [129] = 131864,
    [189] = 131852, [209] = 131885, [229] = 131825, [230] = 131824, [269] = 131830,
    [289] = 131868, [329] = 131871, [349] = 131850, [389] = 131862, [429] = 131835,
    [540] = 131844, [542] = 131844, [543] = 131844, [545] = 131832, [546] = 131832,
    [547] = 131832, [548] = 131832, [552] = 131875, [553] = 131875, [554] = 131875,
    [555] = 131821, [556] = 131821, [557] = 131821, [558] = 131821, [560] = 131830,
    [585] = 131874, [189001] = 131852, [189002] = 131852, [189003] = 131852, [189004] = 131852,
    [329001] = 131871, [329002] = 131871, [429001] = 131835, [429002] = 131835, [429003] = 131835
}

Groups.classicDungeonMaps = {
    [213] = 389, [219] = 209, [220] = 109, [221] = 48, [222] = 48, [223] = 48, [225] = 34,
    [226] = 90, [227] = 90, [228] = 90, [229] = 90, [230] = 70, [231] = 70,
    [235] = 429, [236] = 429, [237] = 429, [238] = 429, [239] = 429, [240] = 429,
    [242] = 230, [243] = 230, [246] = 540, [250] = 229, [251] = 229, [252] = 229,
    [253] = 229, [254] = 229, [255] = 229, [256] = 558, [257] = 558, [258] = 556,
    [259] = 556, [260] = 555, [261] = 542, [262] = 546, [263] = 545, [264] = 545,
    [265] = 547, [266] = 553, [267] = 554, [268] = 554, [269] = 552, [270] = 552,
    [271] = 552, [272] = 557, [273] = 269, [274] = 560, [279] = 43, [280] = 349,
    [281] = 349, [291] = 36, [292] = 36, [300] = 129, [301] = 47, [302] = 189,
    [303] = 189, [304] = 189, [305] = 189, [306] = 289, [307] = 289, [308] = 289,
    [309] = 289, [310] = 33, [311] = 33, [312] = 33, [313] = 33, [314] = 33,
    [315] = 33, [316] = 33, [317] = 329, [318] = 329, [347] = 543, [348] = 585, [349] = 585
}

Groups.foreverMapArt = {
    [2959] = 7963775, [2998] = 7963777, [2999] = 7963782, [3065] = 7963781,
    [16544] = 7963775, [16611] = 7963782, [16732] = 7963777, [16919] = 7963781,
    [900001] = 7963741, [900002] = 7963780, [900003] = 7963734, [900004] = 7963784, [900005] = 7963783
}

Groups.foreverLoadingScreens = {
    a2970 = 7963741,
    a2974 = 7963784,
    a2994 = 7963734,
    a3001 = 7963783,
    a3039 = 7963780,
    a3065 = 7963781,
    d3271 = 7963775,
    d3272 = 7963782,
    d3273 = 7963781,
    d3274 = 7963777
}

function Groups:GetDungeonArt(key, mapID, journalID, textureName, uiMapID)
    local forever = GuildHelper:IsForever()
    local wide = forever and (self.foreverLoadingScreens[key] or self.foreverMapArt[mapID] or self.foreverMapArt[uiMapID]) or nil
    if wide then return wide, {0.18, 0.82, 0.18, 0.82} end

    if not journalID and mapID and mapID > 0 and C_EncounterJournal and C_EncounterJournal.GetInstanceForGameMap then
        journalID = C_EncounterJournal.GetInstanceForGameMap(mapID)
    end
    local loreImage
    if journalID and journalID > 0 and EJ_GetInstanceInfo then
        local _, _, _, _, image, _, journalUiMap, _, _, journalMap = EJ_GetInstanceInfo(journalID)
        loreImage = image
        mapID = journalMap and journalMap > 0 and journalMap or mapID
        uiMapID = uiMapID or journalUiMap
    end

    local file = self.loadingScreens[mapID] or self.loadingScreens[self.classicDungeonMaps[uiMapID]]
    if not file and (forever or WOW_PROJECT_ID ~= WOW_PROJECT_MAINLINE) then
        file = self.loadingScreens[self.classicDungeonMaps[mapID]]
    end
    if file then return file, {0.13, 0.87, 0.21, 0.77} end
    if loreImage and loreImage > 0 then return loreImage end
    if type(textureName) == "string" and textureName ~= "" then
        return "Interface\\LFGFrame\\UI-LFG-BACKGROUND-" .. textureName
    end
end

function Groups:AddActivity(list, key, name, size, low, high, mapID, journalID, textureName, uiMapID)
    if type(name) ~= "string" or name == "" or list.map[key] then return end
    local level, range = self:LevelRange(low, high)
    local option = {
        value = key,
        label = range and format("%s (%s)", name, range) or name,
        level = level,
        size = (type(size) == "number" and size > 0) and size or 5
    }

    option.texture, option.texCoords = self:GetDungeonArt(key, mapID, journalID, textureName, uiMapID)
    list.map[key] = option
    list.count = list.count + 1
    tinsert(list, option)
end

function Groups:CollectFinder(list)
    if not C_LFGList or not C_LFGList.GetAvailableActivities or not C_LFGList.GetActivityInfoTable then return end
    local groups = {0}
    if C_LFGList.GetAvailableActivityGroups then
        local ok, ids = pcall(C_LFGList.GetAvailableActivityGroups, self.CATEGORY)
        for _, id in ipairs(ok and ids or {}) do
            tinsert(groups, id)
        end
    end

    for _, groupID in ipairs(groups) do
        local ok, ids = pcall(C_LFGList.GetAvailableActivities, self.CATEGORY, groupID)
        ids = ok and ids or {}
        if #ids > 0 and groupID > 0 and C_LFGList.GetActivityGroupInfo then
            local name = C_LFGList.GetActivityGroupInfo(groupID)
            if type(name) == "string" and name ~= "" then
                tinsert(list, {
                    header = true,
                    label = name
                })
            end
        end

        for _, id in ipairs(ids) do
            local info = C_LFGList.GetActivityInfoTable(id)
            if info then
                local low = (info.minLevelSuggestion or 0) > 0 and info.minLevelSuggestion or info.minLevel
                self:AddActivity(list, "a" .. id, info.fullName, info.maxNumPlayers, low, info.maxLevelSuggestion, info.mapID, nil, nil, info.uiMapID)
            end
        end
    end
end

function Groups:CollectDungeons(list)
    if not GetLFGDungeonInfo then return end
    for id = 1, 4000 do
        local name, typeID, subtypeID, minLevel, maxLevel, _, minRecLevel, maxRecLevel, _, _, textureName, difficulty, maxPlayers, _, _, _, _, _, _, _, _, mapID = GetLFGDungeonInfo(id)
        if name and typeID == 1 and (subtypeID == 1 or subtypeID == 2) then
            local label = name
            if subtypeID == 2 and difficulty and GetDifficultyInfo then
                local difficultyName = GetDifficultyInfo(difficulty)
                if difficultyName and difficultyName ~= "" then label = name .. " (" .. difficultyName .. ")" end
            end

            local hasRec = (minRecLevel or 0) > 0
            self:AddActivity(list, "d" .. id, label, maxPlayers, hasRec and minRecLevel or minLevel, hasRec and maxRecLevel or maxLevel, mapID, nil, textureName)
        end
    end
end

function Groups:CollectJournal(list)
    if not EJ_GetNumTiers or not EJ_SelectTier or not EJ_GetInstanceByIndex or not EJ_GetTierInfo then return end
    local previous = EJ_GetCurrentTier and EJ_GetCurrentTier()
    for tier = EJ_GetNumTiers(), 1, -1 do
        EJ_SelectTier(tier)
        local start = #list
        tinsert(list, {
            header = true,
            label = EJ_GetTierInfo(tier) or ""
        })

        local index = 1
        local id, name = EJ_GetInstanceByIndex(index, false)
        while id do
            self:AddActivity(list, "e" .. id, name, 5, nil, nil, nil, id)
            index = index + 1
            id, name = EJ_GetInstanceByIndex(index, false)
        end

        if #list == start + 1 then table.remove(list) end
    end

    if previous then EJ_SelectTier(previous) end
end

function Groups:SortActivities(list)
    local first = 1
    while first <= #list do
        if list[first].header then first = first + 1 end
        local last = first
        while list[last] and not list[last].header do
            last = last + 1
        end

        local segment = {}
        for index = first, last - 1 do
            tinsert(segment, list[index])
        end

        table.sort(segment, function(a, b)
            local la, lb = a.level or math.huge, b.level or math.huge
            if la ~= lb then return la < lb end

            return strlower(a.label) < strlower(b.label)
        end)
        for index, option in ipairs(segment) do
            list[first + index - 1] = option
        end

        first = last
    end
end

function Groups:GetActivities()
    if self.activities then return self.activities end
    if self.activityRetry and GetTime() < self.activityRetry then return self.noActivities end
    self.activityRetry = GetTime() + 30
    local list = {
        map = {},
        count = 0
    }

    self:CollectFinder(list)
    if list.count == 0 then
        list = {
            map = {},
            count = 0
        }

        self:CollectDungeons(list)
    end

    if list.count == 0 then
        list = {
            map = {},
            count = 0
        }

        self:CollectJournal(list)
    end

    list.cards = true
    self:SortActivities(list)
    if list.count > 0 then
        self.activities = list
    else
        self.noActivities = list
    end

    return list
end

function Groups:AddOutdoorActivity(list, key, name, range, level)
    if list.map[key] or not name or name == "" then return end
    local option = {value = key, label = range and format("[%s] %s", range, name) or name, name = name, level = level}
    list.map[key] = option
    tinsert(list, option)
end

function Groups:GetQuestActivities()
    if self.questActivities then return self.questActivities end
    local list = {map = {}}
    if C_QuestLog and C_QuestLog.GetNumQuestLogEntries and C_QuestLog.GetInfo then
        for index = 1, C_QuestLog.GetNumQuestLogEntries() or 0 do
            local info = C_QuestLog.GetInfo(index)
            if info and GuildHelper:CanAccessValues(info.questID, info.title, info.level, info.difficultyLevel)
                and not info.isHeader and not info.isHidden and type(info.questID) == "number" and info.questID > 0 then
                local level, label = self:LevelRange(info.level)
                if not level then level, label = self:LevelRange(info.difficultyLevel) end
                self:AddOutdoorActivity(list, "q" .. info.questID, info.title, label or "?", level)
            end
        end
    elseif GetNumQuestLogEntries and GetQuestLogTitle then
        self:CollectLegacyQuests(list)
    end

    self:SortOutdoorActivities(list)
    self.questActivities = list

    return list
end

function Groups:CollectLegacyQuests(list)
    local collapsed = {}
    self.scanningQuests = true
    if ExpandQuestHeader and CollapseQuestHeader then
        for index = GetNumQuestLogEntries() or 0, 1, -1 do
            local _, _, _, isHeader, isCollapsed = GetQuestLogTitle(index)
            if isHeader and isCollapsed then
                tinsert(collapsed, index)
                ExpandQuestHeader(index)
            end
        end
    end

    for index = 1, GetNumQuestLogEntries() or 0 do
        local title, level, _, isHeader, _, _, _, questID, _, _, _, _, _, _, _, isHidden = GetQuestLogTitle(index)
        if not isHeader and not isHidden and type(questID) == "number" and questID > 0 then
            local questLevel, range = self:LevelRange(level)
            self:AddOutdoorActivity(list, "q" .. questID, title, range or "?", questLevel)
        end
    end

    for index = #collapsed, 1, -1 do
        CollapseQuestHeader(collapsed[index])
    end
    self.scanningQuests = nil
end

function Groups:SortOutdoorActivities(list)
    table.sort(list, function(a, b)
        local levelA, levelB = a.level or 0, b.level or 0
        if levelA ~= levelB then return levelA > levelB end
        local nameA, nameB = strlower(a.name), strlower(b.name)
        if nameA == nameB then return a.value < b.value end
        return nameA < nameB
    end)
    list.count = #list
end

function Groups:GetFinderZoneLevels()
    local ranges = {}
    if not C_LFGList or not C_LFGList.GetAvailableCategories or not C_LFGList.GetAvailableActivities or not C_LFGList.GetActivityInfoTable then return ranges end

    for _, category in ipairs(C_LFGList.GetAvailableCategories() or {}) do
        if category ~= self.CATEGORY then
            for _, activityID in ipairs(C_LFGList.GetAvailableActivities(category) or {}) do
                local info = C_LFGList.GetActivityInfoTable(activityID)
                local low = info and info.minLevelSuggestion
                local high = info and info.maxLevelSuggestion
                if type(low) == "number" and low > 0 and type(high) == "number" and high >= low then
                    local levels = {low, high}
                    if info.shortName and info.shortName ~= "" then ranges[strlower(info.shortName)] = levels end
                    if info.fullName and info.fullName ~= "" then ranges[strlower(info.fullName)] = levels end
                end
            end
        end
    end

    return ranges
end

function Groups:GetZoneActivities()
    if self.zoneActivities then return self.zoneActivities end
    local list = {map = {}, count = 0}
    if not C_Map or not C_Map.GetMapChildrenInfo or not Enum or not Enum.UIMapType then return list end

    local finderLevels = self:GetFinderZoneLevels()
    for _, root in ipairs({946, 947, 1414, 1415, 1945}) do
        for _, info in ipairs(C_Map.GetMapChildrenInfo(root, Enum.UIMapType.Zone, true) or {}) do
            local key = "z" .. info.mapID
            if info.name and info.name ~= "" and not list.map[key] then
                local level, range
                if C_Map.GetMapLevels then
                    local ok, low, high = pcall(C_Map.GetMapLevels, info.mapID)
                    if ok and type(low) == "number" and type(high) == "number" and high >= low and low > 0 then
                        level, range = self:LevelRange(low, high)
                    end
                end

                local suggested = finderLevels[strlower(info.name)]
                if suggested and (not range or GuildHelper:IsForever()) then
                    level, range = self:LevelRange(suggested[1], suggested[2])
                end
                self:AddOutdoorActivity(list, key, info.name, range, level)
            end
        end
    end

    self:SortOutdoorActivities(list)
    if list.count > 0 then self.zoneActivities = list end

    return list
end

function Groups:GetModeActivities(mode)
    if mode == "Q" then return self:GetQuestActivities() end
    if mode == "Z" then return self:GetZoneActivities() end

    return self:GetActivities()
end

function Groups:GetActivity(key)
    if not key then return nil end

    local mode = self:GetActivityMode(key)
    if mode == "Q" then return self.questActivities and self.questActivities.map[key] end

    return self:GetModeActivities(mode).map[key]
end

function Groups:GetActivityName(entry)
    local activity = self:GetActivity(entry.activity)

    return activity and activity.label or entry.activityName or "?"
end

function Groups:GetGroupUnits()
    local units = {"player"}
    if IsInRaid and IsInRaid() then
        units = {}
        for index = 1, GetNumGroupMembers() do
            tinsert(units, "raid" .. index)
        end
    elseif GetNumSubgroupMembers then
        for index = 1, GetNumSubgroupMembers() do
            tinsert(units, "party" .. index)
        end
    end

    return units
end

function Groups:IsSolo()
    local units = self:GetGroupUnits()
    return #units == 1 and units[1] == "player"
end

function Groups:GetLiveRole(unit, own, solo, soloRole)
    local role = UnitGroupRolesAssigned and UnitGroupRolesAssigned(unit)
    if not GuildHelper:CanAccessValues(role) or not self.roleOrder[role] then role = "NONE" end
    if own and soloRole and (solo or role == "NONE") then return soloRole end
    return role
end

function Groups:SortRoster(roster)
    table.sort(roster, function(a, b)
        if a.role ~= b.role then return self.roleOrder[a.role] < self.roleOrder[b.role] end
        return a.name < b.name
    end)
end

function Groups:GetLiveRoster(soloRole)
    local units = self:GetGroupUnits()
    local solo = #units == 1 and units[1] == "player"
    local roster, guildMembers = {}, {}
    for _, member in ipairs(GuildHelper.Members.list) do
        if GuildHelper:CanAccessValues(member.guid) and member.guid then guildMembers[member.guid] = member end
    end
    for _, unit in ipairs(units) do
        if UnitExists(unit) then
            local name, realm = (UnitFullName or UnitName)(unit)
            if GuildHelper:CanAccessValues(name, realm) and name and name ~= "" then
                if realm and realm ~= "" then name = name .. "-" .. realm end
                local guid = UnitGUID and UnitGUID(unit)
                local member = GuildHelper:CanAccessValues(guid) and guildMembers[guid]
                local own = unit == "player" or (member and GuildHelper.Members:IsSelf(member))
                local rosterName = member and member.name or (own and GuildHelper.Sync:GetOwnName())
                name = self:CleanText(rosterName or name, 96)
                if self:Name(name) then
                    local role = self:GetLiveRole(unit, own, solo, soloRole)
                    if own and role == "NONE" then
                        local primary = GuildHelper.Specs:GetOwn()[1]
                        if primary and self.roleOrder[primary.role] then role = primary.role end
                    end
                    tinsert(roster, {name = name, role = role})
                end
            end
        end
    end
    self:SortRoster(roster)
    return roster
end

function Groups:GetLiveNeeds(size, soloRole)
    size = size or 5
    local needs = {
        TANK = size <= 5 and 1 or 2,
        HEALER = size <= 5 and 1 or max(2, floor(size / 5))
    }
    needs.DAMAGER = max(0, size - needs.TANK - needs.HEALER)
    local loose = 0
    local units = self:GetGroupUnits()
    local solo = #units == 1 and units[1] == "player"
    for _, unit in ipairs(units) do
        if UnitExists(unit) then
            local own = unit == "player" or (UnitIsUnit and UnitIsUnit(unit, "player"))
            local role = self:GetLiveRole(unit, own, solo, soloRole)
            if needs[role] and needs[role] > 0 then
                needs[role] = needs[role] - 1
            else
                loose = loose + 1
            end
        end
    end

    for _, role in ipairs({"DAMAGER", "HEALER", "TANK"}) do
        local used = min(loose, needs[role])
        needs[role] = needs[role] - used
        loose = loose - used
    end

    return needs
end

function Groups:GetRecruitmentNeeds(mode, activity, soloRole)
    if self:IsOutdoor(mode) then
        return {TANK = 0, HEALER = 0, DAMAGER = max(0, 5 - #self:GetGroupUnits())}
    end

    return self:GetLiveNeeds(activity and activity.size, soloRole)
end

function Groups:Total(entry)
    return (entry.TANK or 0) + (entry.HEALER or 0) + (entry.DAMAGER or 0)
end

function Groups:GetDraftTime()
    local draft = self.draft.P
    local stamp = date("*t", time() + (draft.day or 0) * 86400)
    stamp.hour = draft.hour
    stamp.min = draft.minute
    stamp.sec = 0

    return time(stamp)
end

function Groups:GetDayOffset(when)
    local today = date("*t")
    today.hour = 12
    today.min = 0
    today.sec = 0
    local target = date("*t", when)
    target.hour = 12
    target.min = 0
    target.sec = 0

    return floor((time(target) - time(today)) / 86400 + 0.5)
end

function Groups:DayLabel(when, offset)
    if offset == 0 then return GuildHelper:Trans("LID_TODAY") end
    if offset == 1 then return GuildHelper:Trans("LID_TOMORROW") end
    local weekday = _G[self.WEEKDAYS[tonumber(date("%w", when)) + 1]] or date("%a", when)

    return weekday .. " " .. date(GuildHelper:Trans("LID_GROUPDATEFORMAT"), when)
end

function Groups:FormatWhen(when)
    return self:DayLabel(when, self:GetDayOffset(when)) .. " " .. date("%H:%M", when)
end

function Groups:Send(message, key)
    if self.guild and #message <= 253 then
        self.lastSent = "F~" .. message
        self.lastSentTime = GetTime()
        GuildHelper.Sync:Send(self.lastSent, key and ("F~" .. key))
    end
end

function Groups:LearnSelf(message, sender)
    local own = UnitName("player")
    if not own or strlower(sender):sub(1, #own) ~= strlower(own) then return false end
    local parts = {strsplit("~", message)}
    local echo = message == self.lastSent and GetTime() - (self.lastSentTime or 0) < 10
    if not echo and parts[2] == "L" and parts[3] then
        for _, entry in ipairs(self:GetList()) do
            if self:IsOwn(entry) and entry.id == parts[3] then echo = true end
        end
    end

    if echo then
        self.selfSender = self:Name(sender)
        local planned = self:GetPlanned() or {}
        for _, store in ipairs({self.live, planned}) do
            for key, entry in pairs(store) do
                if entry.owner == self.selfSender and entry.owner ~= self:Self() then store[key] = nil end
            end
        end
    end

    return echo
end

function Groups:Broadcast(entry, syncSignups)
    if entry.kind == "L" then entry.expires = GetTime() + self.TTL end
    local text = table.concat({"L", entry.id, entry.kind, tostring(entry.when or 0), entry.activity, entry.TANK, entry.HEALER, entry.DAMAGER, entry.activityName}, "~")
    local firstBroadcast = not self.sent[entry.key]
    self.sent[entry.key] = GetTime()
    self:Send(text .. "~" .. self:CleanText(entry.note, 252 - #text), "G" .. entry.id)
    if firstBroadcast or syncSignups then self:BroadcastSignups(entry) end
    if entry.kind == "L" then self:BroadcastRoster(entry, firstBroadcast or syncSignups) end
end

function Groups:BroadcastRoster(entry, force)
    local roster = self:GetLiveRoster(entry.soloRole)
    local records = {}
    for _, member in ipairs(roster) do
        tinsert(records, "~" .. member.name .. "~" .. member.role)
    end
    local signature = table.concat(records)
    if not force and entry.rosterSignature == signature then return end
    entry.roster, entry.rosterSignature = roster, signature

    self.signupSerial = self.signupSerial + 1
    local header = "M~" .. entry.id .. "~" .. self.signupSerial .. "~"
    local chunks, payload = {}, ""
    for _, record in ipairs(records) do
        if #header + #payload + #record > 240 then
            tinsert(chunks, payload)
            payload = ""
        end
        payload = payload .. record
    end
    tinsert(chunks, payload)
    for index, chunk in ipairs(chunks) do
        self:Send(header .. index .. "~" .. #chunks .. chunk)
    end
end

function Groups:BroadcastSignups(entry)
    self.signupSerial = self.signupSerial + 1
    local header = "R~" .. entry.id .. "~" .. self.signupSerial .. "~"
    local chunks, payload = {}, ""
    for _, applicant in pairs(entry.applicants or {}) do
        if (entry.kind == "P" or (applicant.expires or 0) > GetTime()) and (entry[applicant.role] or 0) > 0 then
            local record = "~" .. applicant.name .. "~" .. applicant.role
            if #header + #payload + #record > 235 then
                chunks[#chunks + 1] = payload
                payload = ""
            end

            payload = payload .. record
        end
    end

    chunks[#chunks + 1] = payload
    for index, chunk in ipairs(chunks) do
        self:Send(header .. index .. "~" .. #chunks .. chunk)
    end
end

function Groups:BroadcastOwn()
    local delay = 0
    for _, entry in ipairs(self:GetList()) do
        if self:IsOwn(entry) then
            C_Timer.After(delay, function()
                if self:CheckGuild() and self:Find(entry.key) == entry then
                    self:Broadcast(entry, true)
                end
            end)
            delay = delay + 0.4
        end
    end
end

function Groups:Validate()
    if not self.guild then return false, "LID_NOGUILD" end
    local draft = self.draft[self.mode]
    local activity = draft.activity and self:GetModeActivities(self.mode).map[draft.activity]
    if not activity then return false, self:IsOutdoor(self.mode) and "LID_GROUPCHOOSEACTIVITY" or "LID_GROUPCHOOSE" end
    if self.mode ~= "P" then
        if self.mode == "L" and self:IsSolo() and not GuildHelper.Specs:GetRole(draft.soloRole) then return false, "LID_GROUPCHOOSEROLE" end
        if self:Total(self:GetRecruitmentNeeds(self.mode, activity, draft.soloRole)) == 0 then return false, "LID_GROUPFULL" end

        return true, self:GetOwnLive(self.mode) and "LID_GROUPACTIVE" or "LID_GROUPDRAFT"
    end

    local total = self:Total(draft)
    if total < 1 or total > 39 then return false, "LID_GROUPLIMIT" end
    if self:GetDraftTime() <= time() then return false, "LID_GROUPPAST" end
    if not self.editing and self:CountPlanned(self:Self()) >= self.MAXPLANNED then return false, "LID_GROUPMAXPLANNED" end

    return true, self.editing and "LID_GROUPEDITING" or "LID_GROUPDRAFT"
end

function Groups:IsReady()
    return not self.lastAction or GetTime() - self.lastAction >= 2
end

function Groups:Publish()
    if self.mode ~= "P" and self:GetChatCooldown() > 0 then return end
    if not self:CheckGuild() or not self:IsReady() or not self:Validate() then return end
    local owner = self:Self()
    if not owner then return end
    self.lastAction = GetTime()
    local draft = self.draft[self.mode]
    local activity = self:GetModeActivities(self.mode).map[draft.activity]
    local entry = self:GetCurrent()
    if not entry then
        local stamp = time()
        local id
        repeat
            id = stamp .. ":" .. random(100000000, 999999999)
        until not self:Find(owner .. "#" .. id)
        entry = {
            id = id,
            key = owner .. "#" .. id,
            routeByID = true,
            owner = owner,
            name = GuildHelper.Sync:GetOwnName() or UnitName("player"),
            kind = self.mode == "P" and "P" or "L",
            applicants = {}
        }

        self:GetStore(entry.kind)[entry.key] = entry
        if self.mode == "P" then self.editing = entry.key end
    end

    if entry.kind == "L" then
        entry.soloRole = draft.soloRole
        entry.chatRepeatMinutes = draft.chatRepeatMinutes
    end
    local counts = entry.kind == "L" and self:GetRecruitmentNeeds(self.mode, activity, entry.soloRole) or draft
    for _, role in ipairs(GuildHelper.Specs.ROLES) do
        entry[role.value] = counts[role.value]
    end

    entry.activity = activity.value
    entry.activityName = self:CleanText(activity.label, self:IsOutdoor(self.mode) and 110 or 64)
    entry.note = self:CleanText(draft.note, 110)
    entry.when = self.mode == "P" and self:GetDraftTime() or 0
    self.selected = entry.key
    entry.chatLanguage = draft.chatLanguage or GuildHelper:GetLanguage()
    self:Broadcast(entry)
    self:QueueAnnouncement(entry)
    self:TickAnnouncements()
    self:Refresh()
end

function Groups:SaveLiveForReload()
    local entries = {}
    for _, entry in pairs(self.live) do
        if self:IsOwn(entry) then tinsert(entries, entry) end
    end

    local saved = #entries > 0 and {guild = self.guild, entries = entries, signupSerial = self.signupSerial} or nil
    GuildHelper:SetConfig("GROUPLIVERELOAD", saved)
end

function Groups:RestoreLiveAfterReload()
    if not self.reloadReadyAt or GetTime() < self.reloadReadyAt then return end
    self.reloadReadyAt = nil
    local saved = GuildHelper:GetConfig("GROUPLIVERELOAD")
    GuildHelper:SetConfig("GROUPLIVERELOAD", nil)
    if not saved or saved.guild ~= self.guild then return end
    for _, entry in ipairs(saved.entries or {saved.entry}) do
        self:RestoreLiveEntry(entry, saved.signupSerial)
    end
end

function Groups:RestoreLiveEntry(entry, signupSerial)
    local mode = self:GetListingMode(entry)
    if not self:IsOwn(entry) or self:GetOwnLive(mode) then return end
    if entry.lastChatText and not entry.lastChatState then
        entry.lastChatState = self:GetLiveChatState(entry, entry.lastChatText)
    end

    local activity = self:GetActivity(entry.activity)
    local needs = self:GetRecruitmentNeeds(mode, activity, entry.soloRole)
    if self:Total(needs) == 0 then return end
    for _, role in ipairs(GuildHelper.Specs.ROLES) do
        entry[role.value] = needs[role.value]
    end

    self.signupSerial = max(self.signupSerial, signupSerial or 0)
    self.live[entry.key] = entry
    local draft = self.draft[mode]
    draft.activity, draft.note, draft.soloRole = entry.activity, entry.note, entry.soloRole
    draft.chatLanguage = entry.chatLanguage
    draft.chatRepeatMinutes = entry.chatRepeatMinutes
    if self.mode == mode then
        self.selected = entry.key
        self:SyncNote()
    end
    self:Broadcast(entry, true)
end

function Groups:Close(entry)
    if not entry then return end
    self:Send("D~" .. entry.id, "G" .. entry.id)
    local store = self:GetStore(entry.kind)
    if store then store[entry.key] = nil end
    if self.announcements then self.announcements[entry.key] = nil end
    if self.editing == entry.key then self.editing = nil end
    self:Refresh()
end

function Groups:GetCurrent()
    if self.mode ~= "P" then return self:GetOwnLive(self.mode) end
    local entry = self:Find(self.editing)
    if not entry then self.editing = nil end

    return entry
end

function Groups:CloseCurrent()
    self:Close(self:GetCurrent())
end

function Groups:Request()
    if not self:CheckGuild() then return end
    if self.lastQuery and GetTime() - self.lastQuery < 10 then return end
    self.lastQuery = GetTime()
    self:Send("Q")
end

function Groups:SendApplication(entry)
    self.applySent[entry.key] = GetTime()
    entry.applicants = entry.applicants or {}
    entry.applicants[self:Self()] = {
        name = GuildHelper.Sync:GetOwnName() or UnitName("player"),
        role = entry.applied,
        expires = entry.kind == "L" and GetTime() + self.TTL or nil
    }
    self:Send(table.concat({"A", entry.owner, entry.id, entry.applied}, "~"), "A" .. entry.key)
end

function Groups:Withdraw(entry)
    if not entry or not entry.applied then return end
    self:Send("W~" .. entry.owner .. "~" .. entry.id, "A" .. entry.key)
    entry.applied = nil
    if entry.applicants then entry.applicants[self:Self()] = nil end
end

function Groups:GetApplicationRole(entry)
    return self:IsOutdoor(self:GetListingMode(entry)) and "DAMAGER" or self.role
end

function Groups:Apply()
    if not self:CheckGuild() or not self:IsReady() then return end
    local entry = self:Find(self.selected)
    if not entry or self:IsOwn(entry) then return end
    self.lastAction = GetTime()
    local role = self:GetApplicationRole(entry)
    if entry.applied then
        self:Withdraw(entry)
    elseif (entry[role] or 0) > 0 then
        if entry.kind == "L" then
            for _, other in pairs(self.live) do
                self:Withdraw(other)
            end
        end

        entry.applied = role
        self:SendApplication(entry)
    end

    self:Refresh()
end

function Groups:ReadListing(owner, sender, parts)
    local id, kind, when, activity = parts[3], parts[4], tonumber(parts[5]), parts[6]
    if #id > 24 or not id:match("^%d+:%d+$") or (kind ~= "L" and kind ~= "P") or not when or not activity:match("^[adeqz]%d+$") then return false end
    local outdoor = self:IsOutdoor(self:GetActivityMode(activity))
    if outdoor and kind == "P" then return false end
    local name = self:CleanText(parts[10], outdoor and 110 or 64)
    if name == "" then return false end
    local now = time()
    if kind == "P" and (when < now - self.KEEP or when > now + (self.DAYS + 1) * 86400) then return false end
    local key = owner .. "#" .. id
    local store = self:GetStore(kind)
    local entry = store[key]
    if not entry and kind == "P" and self:CountPlanned(owner) >= self.MAXPLANNED then return false end
    entry = entry or {
        id = id,
        key = key,
        owner = owner,
        kind = kind
    }

    local counts = {}
    for index, role in ipairs(GuildHelper.Specs.ROLES) do
        local count = tonumber(parts[index + 6])
        if not count or count < 0 or count > 39 or count ~= floor(count) then return false end
        counts[role.value] = count
    end

    local total = self:Total(counts)
    if total > 39 or (kind == "L" and total < 1) then return false end
    if outdoor and (total > 4 or counts.TANK ~= 0 or counts.HEALER ~= 0) then return false end
    for role, count in pairs(counts) do
        entry[role] = count
    end
    entry.name = sender
    entry.when = kind == "P" and when or 0
    entry.activity = activity
    entry.activityName = name
    entry.note = self:CleanText(parts[11], 110)
    if kind == "L" then entry.expires = GetTime() + self.TTL end
    store[key] = entry
    self.seen[key] = GetTime()
    if GuildHelper.Notifications then
        GuildHelper.Notifications:NewEntry(key, owner, tonumber(id:match("^%d+")), kind == "L" and "NEWLIVE" or "NEWPLANNED", true)
    end

    return true
end

function Groups:ReadRoster(owner, parts)
    local entry = parts[3] and self.live[owner .. "#" .. parts[3]]
    local serial, index, total = tonumber(parts[4]), tonumber(parts[5]), tonumber(parts[6])
    if not entry or not serial or serial <= (entry.rosterSerial or 0) or serial ~= floor(serial) or not index or not total
        or index < 1 or index > total or total > 40 or index ~= floor(index) or total ~= floor(total)
        or #parts % 2 ~= 0 then return false end
    if index == 1 then entry.rosterSnapshot = {serial = serial, next = 1, total = total, members = {}} end
    local snapshot = entry.rosterSnapshot
    if not snapshot or snapshot.serial ~= serial or snapshot.next ~= index or snapshot.total ~= total then return false end
    for i = 7, #parts, 2 do
        local name, role = parts[i], parts[i + 1]
        if #snapshot.members >= 40 or not self:Name(name) or not self.roleOrder[role] then
            entry.rosterSnapshot = nil
            return false
        end
        tinsert(snapshot.members, {name = name, role = role})
    end
    snapshot.next = index + 1
    if index ~= total then return false end
    self:SortRoster(snapshot.members)
    entry.roster, entry.rosterSerial, entry.rosterSnapshot = snapshot.members, serial, nil
    return true
end

function Groups:ReadSignupSnapshot(owner, parts)
    local entry = parts[3] and self:Find(owner .. "#" .. parts[3])
    local serial, index, total = tonumber(parts[4]), tonumber(parts[5]), tonumber(parts[6])
    if not entry or self:IsOwn(entry) or not serial or not index or not total or index < 1 or index > total or total ~= floor(total) or #parts % 2 ~= 0 then return false end
    local snapshot = self.signupSnapshots[entry.key]
    if index == 1 then
        snapshot = {serial = serial, next = 1, total = total, applicants = {}, changes = {}, expires = GetTime() + self.TTL}
        self.signupSnapshots[entry.key] = snapshot
    end

    if not snapshot or snapshot.serial ~= serial or snapshot.next ~= index or snapshot.total ~= total then return false end
    for i = 7, #parts, 2 do
        local name, role = parts[i], parts[i + 1]
        local key = self:Name(name)
        if key and not self:IsSelfName(name) and GuildHelper.Specs:GetRole(role) and (entry[role] or 0) > 0 then
            snapshot.applicants[key] = {
                name = name,
                role = role,
                expires = entry.kind == "L" and GetTime() + self.TTL or nil
            }
        end
    end

    snapshot.next = index + 1
    if index ~= total then return false end
    for key in pairs(snapshot.changes) do
        snapshot.applicants[key] = entry.applicants[key]
    end

    local me = self:Self()
    if entry.applied and me and entry.applicants then
        snapshot.applicants[me] = entry.applicants[me]
    end

    entry.applicants = snapshot.applicants
    self.signupSnapshots[entry.key] = nil

    return true
end

function Groups:ReadApplication(owner, sender, parts)
    local target, id = self:Name(parts[3]), parts[4]
    if not target or not id or not id:match("^%d+:%d+$") then return false end
    local ownName = self:Self()
    local entry = self:Find((self:IsSelfName(target) and ownName or target) .. "#" .. id)
    if not entry and ownName and GuildHelper:IsForever() then
        local listing = self:Find(ownName .. "#" .. id)
        if listing and (listing.routeByID or self:Name(listing.name) == target) then entry = listing end
    end
    if not entry then
        GuildHelper.Sync:Trace("Gruppenanmeldung empfangen, Gruppen-ID nicht zugeordnet:", id)
        return false
    end
    entry.applicants = entry.applicants or {}
    if parts[2] == "W" and #parts == 4 then
        entry.applicants[owner] = nil
    elseif parts[2] == "A" and #parts == 5 and GuildHelper.Specs:GetRole(parts[5]) and (entry[parts[5]] or 0) > 0 then
        local previous = entry.applicants[owner]
        local isNew = previous == nil
        local own = self:IsOwn(entry)
        entry.applicants[owner] = {
            name = sender,
            role = parts[5],
            unread = own and (isNew or previous.unread) or nil,
            expires = entry.kind == "L" and GetTime() + self.TTL or nil
        }
        if isNew and own and GuildHelper.Notifications then
            GuildHelper.Notifications:Application(entry.key, owner, sender)
        end
    else
        return false
    end

    local snapshot = self.signupSnapshots[entry.key]
    if snapshot then snapshot.changes[owner] = true end

    return true
end

function Groups:OnMessage(message, sender)
    if not self:CheckGuild() or #message > 255 then return end
    local owner = self:Name(sender)
    if not owner or self:IsSelfName(sender) or self:LearnSelf(message, sender) then return end
    local parts = {strsplit("~", message)}
    local command = parts[2]
    local changed = false
    if command == "Q" and #parts == 2 then
        if not self.pendingReply and GetTime() - (self.lastReply or 0) >= 5 then
            self.pendingReply = true
            C_Timer.After(random(1, 3), function()
                self.pendingReply = nil
                self.lastReply = GetTime()
                if self:CheckGuild() then self:BroadcastOwn() end
            end)
        end

        return
    elseif command == "L" and #parts == 11 then
        changed = self:ReadListing(owner, sender, parts)
    elseif command == "D" and #parts == 3 then
        local key = owner .. "#" .. parts[3]
        local planned = self:GetPlanned()
        changed = self.live[key] ~= nil or planned[key] ~= nil
        self.live[key] = nil
        planned[key] = nil
    elseif command == "R" then
        changed = self:ReadSignupSnapshot(owner, parts)
    elseif command == "M" then
        changed = self:ReadRoster(owner, parts)
    elseif command == "A" or command == "W" then
        changed = self:ReadApplication(owner, sender, parts)
    end

    if command == "A" or command == "W" then
        GuildHelper.Sync:Trace(changed and "Gruppenanmeldung verarbeitet:" or "Gruppenanmeldung verworfen:", command, parts[4])
    end
    if changed then self:Refresh() end
end

function Groups:TickOwnLive(own, now)
    if self.dirty and (not self.rosterReadyAt or now >= self.rosterReadyAt) then
        local needs = self:GetRecruitmentNeeds(self:GetListingMode(own), self:GetActivity(own.activity), own.soloRole)
        if self:Total(needs) == 0 then
            self:Close(own)

            return
        end

        local changed = false
        for _, role in ipairs(GuildHelper.Specs.ROLES) do
            if own[role.value] ~= needs[role.value] then
                own[role.value] = needs[role.value]
                changed = true
            end
        end

        if changed then
            self:Broadcast(own)
        else
            self:BroadcastRoster(own)
        end
    end

    if now - (self.sent[own.key] or 0) >= self.INTERVAL then self:Broadcast(own) end
end

function Groups:Tick()
    if not self:CheckGuild() then return end
    self:RestoreLiveAfterReload()
    local now, stamp = GetTime(), time()
    for key, snapshot in pairs(self.signupSnapshots) do
        if snapshot.expires <= now or not self:Find(key) then self.signupSnapshots[key] = nil end
    end

    for _, entry in pairs(self.live) do
        if self:IsOwn(entry) then self:TickOwnLive(entry, now) end
    end
    self:TickAnnouncements()
    if not self.rosterReadyAt or now >= self.rosterReadyAt then self.dirty = nil end
    for key, entry in pairs(self.live) do
        if not self:IsOwn(entry) and (entry.expires or 0) <= now then
            self.live[key] = nil
        else
            for name, applicant in pairs(entry.applicants or {}) do
                if (applicant.expires or 0) <= now or (entry[applicant.role] or 0) == 0 then entry.applicants[name] = nil end
            end
        end
    end

    local planned = self:GetPlanned()
    for key, entry in pairs(planned) do
        if (entry.when or 0) + self.KEEP < stamp then
            if self:IsOwn(entry) then
                self:Close(entry)
            else
                planned[key] = nil
            end
        elseif self:IsOwn(entry) and now - (self.sent[key] or -self.PLANINTERVAL) >= self.PLANINTERVAL then
            self:Broadcast(entry)
        end
    end

    for _, entry in ipairs(self:GetList()) do
        if entry.applied then
            local interval = entry.kind == "L" and self.INTERVAL or self.PLANINTERVAL
            if entry.kind == "L" and (entry[entry.applied] or 0) == 0 then
                self:Withdraw(entry)
            elseif self.seen[entry.key] and now - self.seen[entry.key] < self.TTL and now - (self.applySent[entry.key] or -interval) >= interval then
                self:SendApplication(entry)
            end
        end
    end

    self:Refresh()
end

function Groups:CanInvite()
    if InCombatLockdown() then return false end
    if C_PartyInfo and C_PartyInfo.CanInvite then return C_PartyInfo.CanInvite() end

    return not IsInGroup() or UnitIsGroupLeader("player") or UnitIsGroupAssistant("player")
end

function Groups:Invite(applicant)
    if not applicant or not self:CanInvite() then return end
    if C_PartyInfo and C_PartyInfo.InviteUnit then
        C_PartyInfo.InviteUnit(applicant.name)
    elseif InviteUnit then
        InviteUnit(applicant.name)
    end
end

function Groups:Needs(entry)
    if entry.activity and self:IsOutdoor(self:GetListingMode(entry)) then
        return GuildHelper:Trans("LID_GROUPNEEDS") .. " " .. self:Total(entry)
    end

    local parts = {}
    for _, role in ipairs(GuildHelper.Specs.ROLES) do
        tinsert(parts, GuildHelper.Specs:GetIconString(GuildHelper.Specs.ROLEICONS, role.coords) .. tostring(entry[role.value] or 0))
    end

    return table.concat(parts, "   ")
end

function Groups:GetList(kind)
    local list = {}
    for _, entry in pairs(self.live) do
        if not kind or kind == self:GetListingMode(entry) then tinsert(list, entry) end
    end

    for _, entry in pairs(self:GetPlanned() or {}) do
        if not kind or kind == "P" then tinsert(list, entry) end
    end

    table.sort(list, function(a, b)
        if a.kind ~= b.kind then return a.kind == "L" end
        if a.kind == "P" and a.when ~= b.when then return a.when < b.when end
        local ownA, ownB = self:IsOwn(a), self:IsOwn(b)
        if ownA ~= ownB then return ownA end

        return a.key < b.key
    end)

    return list
end

function Groups:SetMode(mode)
    self.mode = mode
    self.selected = nil
    if GuildHelper.Members.menu then GuildHelper.Members.menu:Hide() end
    self:SyncNote()
    self:Refresh()
end

function Groups:LoadDraft(entry)
    local draft = self.draft.P
    draft.activity = entry.activity
    draft.note = entry.note or ""
    draft.chatLanguage = entry.chatLanguage or GuildHelper:GetLanguage()
    local stamp = date("*t", entry.when)
    draft.day = max(0, min(self.DAYS - 1, self:GetDayOffset(entry.when)))
    draft.hour = stamp.hour
    draft.minute = stamp.min - stamp.min % 5
    for index, role in ipairs(GuildHelper.Specs.ROLES) do
        draft[role.value] = entry[role.value] or 0
        self.countBoxes[index]:SetText(tostring(draft[role.value]))
    end

    self.editing = entry.key
    self:SyncNote()
end

function Groups:NewDraft()
    self.editing = nil
    self.draft.P.note = ""
    self:SyncNote()
    self:Refresh()
end

function Groups:SyncNote()
    if self.noteBox then self.noteBox:SetText(self.draft[self.mode].note or "") end
end

function Groups:Select(entry)
    self.selected = entry.key
    if self:IsOwn(entry) and entry.kind == "P" then self:LoadDraft(entry) end
    self:Refresh()
end

function Groups:Text(parent, key, x, y, size, color)
    local text = GuildHelper.Theme:Text(parent, size or 12, color or "muted")
    text:SetPoint("TOPLEFT", parent, "TOPLEFT", x, y)
    text:SetJustifyH("LEFT")
    if key then GuildHelper.Theme:SetTrans(text, key) end

    return text
end

function Groups:CreateBox(parent, letters, numeric)
    local Theme = GuildHelper.Theme
    local box = CreateFrame("EditBox", nil, parent, Theme:IsNative() and "InputBoxTemplate" or nil)
    box:SetHeight(28)
    box:SetAutoFocus(false)
    box:SetMaxLetters(letters)
    if numeric then box:SetNumeric(true) end
    if not Theme:IsNative() then
        box:SetTextInsets(8, 8, 0, 0)
        Theme:Panel(box, "control", "border", 6)
    end

    Theme:Track(box, "text", "text", 13)
    box:SetScript("OnEnterPressed", function(sel) sel:ClearFocus() end)
    box:SetScript("OnEscapePressed", function(sel) sel:ClearFocus() end)

    return box
end

function Groups:GetDayOptions()
    local options = {}
    local now = time()
    for day = 0, self.DAYS - 1 do
        tinsert(options, {
            value = day,
            label = self:DayLabel(now + day * 86400, day)
        })
    end

    return options
end

function Groups:GetNumberOptions(last, step)
    local options = {}
    for value = 0, last, step do
        tinsert(options, {
            value = value,
            label = format("%02d", value)
        })
    end

    return options
end

function Groups:BuildForm(content)
    local Members = GuildHelper.Members
    self.form = CreateFrame("Frame", nil, content)
    self.form:SetPoint("TOPLEFT", content, "TOPLEFT", 0, 0)
    self.form:SetPoint("TOPRIGHT", self.detail, "TOPLEFT", -12, 0)
    GuildHelper.Theme:Panel(self.form, "panel", "border", 9)
    self.activityLabel = self:Text(self.form, nil, 14, -17)
    self.activityPill = Members:CreatePill(self.form, "")
    self.activityPill:SetPoint("TOPLEFT", self.form, "TOPLEFT", 150, -10)
    self.activityPill:SetPoint("TOPRIGHT", self.form, "TOPRIGHT", -16, -10)
    self.activityPill.text:ClearAllPoints()
    self.activityPill.text:SetPoint("LEFT", self.activityPill, "LEFT", 8, 0)
    self.activityPill.text:SetPoint("RIGHT", self.activityPill, "RIGHT", -8, 0)
    self.activityPill.text:SetJustifyH("LEFT")
    self.activityPill.text:SetWordWrap(true)
    self.activityPill.text:SetMaxLines(2)
    self.activityPill.compactHeight = self.activityPill:GetHeight()
    self.activityPill.art = self.activityPill:CreateTexture(nil, "ARTWORK")
    self.activityPill.art:SetPoint("LEFT", self.activityPill, "LEFT", 4, 0)
    self.activityPill.art:SetSize(88, 50)
    self.activityPill.art:Hide()
    self.activityPill:SetScript("OnClick", function(button)
        local mode = self.mode
        local draft = self.draft[mode]
        Members:OpenMenu(button, self:GetModeActivities(mode), draft.activity, function(value)
            if not self:GetModeActivities(mode).map[value] then return end
            draft.activity = value
            self:Refresh()
        end)
    end)

    self.needsLabel = self:Text(self.form, "LID_GROUPNEEDS", 14, -51)
    self.liveNeeds = self:Text(self.form, nil, 150, -51, 12, "text")
    self.soloRolePill = Members:CreatePill(self.form, "")
    self.soloRolePill:SetPoint("LEFT", self.liveNeeds, "RIGHT", 16, 0)
    self.soloRolePill:SetScript("OnClick", function(button)
        local draft = self.draft.L
        local options = GuildHelper.Specs:GetRoleOptions()
        table.remove(options, 1)
        Members:OpenMenu(button, options, draft.soloRole, function(value)
            draft.soloRole = value
            self:Refresh()
        end)
    end)
    self.countLabels = {}
    self.countBoxes = {}
    for index, role in ipairs(GuildHelper.Specs.ROLES) do
        local roleValue = role.value
        local label = self:Text(self.form, nil, 150 + (index - 1) * 96, -48)
        local box = self:CreateBox(self.form, 2, true)
        box:SetPoint("TOPLEFT", label, "BOTTOMLEFT", 0, -2)
        box:SetWidth(42)
        box:SetText(tostring(self.draft.P[roleValue]))
        box:SetScript("OnTextChanged", function(sel)
            self.draft.P[roleValue] = max(0, floor(tonumber(sel:GetText()) or 0))
            self:Refresh()
        end)

        box:SetScript("OnEditFocusLost", function(sel) sel:SetText(tostring(self.draft.P[roleValue])) end)
        self.countLabels[index] = label
        self.countBoxes[index] = box
    end

    self.noteLabel = self:Text(self.form, "LID_GROUPNOTE", 14, -85)
    self.noteBox = self:CreateBox(self.form, 100)
    self.noteBox:SetPoint("TOPLEFT", self.noteLabel, "TOPLEFT", 136, 7)
    self.noteBox:SetPoint("RIGHT", self.form, "RIGHT", -16, 0)
    self.noteBox:SetScript("OnTextChanged", function(box) self.draft[self.mode].note = box:GetText() end)
    self.dateLabel = self:Text(self.form, "LID_GROUPDATE", 14, -143)
    self.dayPill = Members:CreatePill(self.form, "")
    self.dayPill:SetPoint("TOPLEFT", self.form, "TOPLEFT", 150, -136)
    self.dayPill:SetScript("OnClick", function(button)
        Members:OpenMenu(button, self:GetDayOptions(), self.draft.P.day, function(value)
            self.draft.P.day = value
            self:Refresh()
        end)
    end)

    self.hourPill = Members:CreatePill(self.form, "")
    self.hourPill:SetPoint("LEFT", self.dayPill, "RIGHT", 12, 0)
    self.hourPill:SetScript("OnClick", function(button)
        Members:OpenMenu(button, self:GetNumberOptions(23, 1), self.draft.P.hour, function(value)
            self.draft.P.hour = value
            self:Refresh()
        end)
    end)

    self.minutePill = Members:CreatePill(self.form, "")
    self.minutePill:SetPoint("LEFT", self.hourPill, "RIGHT", 6, 0)
    self.minutePill:SetScript("OnClick", function(button)
        Members:OpenMenu(button, self:GetNumberOptions(55, 5), self.draft.P.minute, function(value)
            self.draft.P.minute = value
            self:Refresh()
        end)
    end)

    self:BuildAnnouncementOptions(self.form)
    self.publish = Members:CreateButton(self.form, "LID_GROUPPUBLISH", true)
    self.publish:SetPoint("BOTTOMLEFT", self.form, "BOTTOMLEFT", 14, 12)
    self.publish:SetWidth(144)
    self.publish:SetScript("OnClick", function()
        self.noteBox:ClearFocus()
        self:Publish()
    end)

    self.new = Members:CreateButton(self.form, "LID_GROUPNEW")
    self.new:SetPoint("LEFT", self.publish, "RIGHT", 12, 0)
    self.new:SetWidth(104)
    self.new:SetScript("OnClick", function() self:NewDraft() end)
    self.close = Members:CreateButton(self.form, "LID_GROUPCLOSE")
    self.close:SetWidth(144)
    self.close:SetScript("OnClick", function() self:CloseCurrent() end)
    self.status = self:Text(self.form, nil, 14, 0)
    self.status:ClearAllPoints()
    self.status:SetPoint("BOTTOMLEFT", self.publish, "TOPLEFT", 0, 6)
    self.status:SetPoint("RIGHT", self.form, "RIGHT", -14, 0)
    self.status:SetWordWrap(true)
    self.status:SetHeight(34)
    self.status:SetJustifyV("TOP")
end

function Groups:BuildDetail(content)
    local Members, Dashboard = GuildHelper.Members, GuildHelper.Dashboard
    self.detail = Dashboard:CreateCard(content, "LID_GROUPDETAIL")
    self.detail:SetPoint("TOPRIGHT", content, "TOPRIGHT", 0, 0)
    self.detail:SetPoint("BOTTOMRIGHT", content, "BOTTOMRIGHT", 0, Members.BOTTOM)
    self.detail:SetWidth(320)
    self.detailTitle = self:Text(self.detail, nil, 14, -34, 14, "text")
    self.detailTitle:SetPoint("RIGHT", self.detail, "RIGHT", -14, 0)
    self.detailTitle:SetWordWrap(true)
    self.detailTitle:SetHeight(34)
    self.detailTitle:SetJustifyV("TOP")
    self.detailInfo = self:Text(self.detail, nil, 14, -70)
    self.detailInfo:SetPoint("RIGHT", self.detail, "RIGHT", -14, 0)
    self.detailNeeds = self:Text(self.detail, nil, 14, -90, 12, "text")
    self.detailNote = self:Text(self.detail, nil, 14, -110)
    self.detailNote:SetPoint("RIGHT", self.detail, "RIGHT", -14, 0)
    self.detailNote:SetWordWrap(true)
    self.detailNote:SetHeight(42)
    self.detailNote:SetJustifyV("TOP")
    self.rolePill = Members:CreatePill(self.detail, "")
    self.rolePill:SetPoint("TOPLEFT", self.detail, "TOPLEFT", 14, -158)
    self.rolePill:SetScript("OnClick", function(button)
        local options = GuildHelper.Specs:GetRoleOptions()
        table.remove(options, 1)
        Members:OpenMenu(button, options, self.role, function(value)
            self.role = value
            local entry = self:Find(self.selected)
            if entry and entry.applied and (entry[value] or 0) > 0 then
                entry.applied = value
                self:SendApplication(entry)
            end
            self:Refresh()
        end)
    end)

    self.apply = Members:CreateButton(self.detail, "LID_GROUPAPPLY", true)
    self.apply:SetPoint("TOPLEFT", self.detail, "TOPLEFT", 14, -194)
    self.apply:SetWidth(140)
    self.apply:SetScript("OnClick", function() self:Apply() end)
    self.whisper = Members:CreateButton(self.detail, "LID_WHISPER")
    self.whisper:SetPoint("LEFT", self.apply, "RIGHT", 10, 0)
    self.whisper:SetWidth(130)
    self.whisper:SetScript("OnClick", function()
        local entry = self:Find(self.selected)
        if not entry then return end
        if ChatFrame_SendTell then
            ChatFrame_SendTell(entry.name)
        elseif ChatFrameUtil and ChatFrameUtil.SendTell then
            ChatFrameUtil.SendTell(entry.name)
        end
    end)

    self.roster = Dashboard:CreateList(Dashboard:CreateCard(self.detail, "LID_MEMBERS"))
    self.roster:SetPoint("TOPLEFT", self.detail, "TOPLEFT", 6, -156)
    self.roster:SetPoint("TOPRIGHT", self.detail, "TOPRIGHT", -6, -156)
    self.roster:SetHeight(110)
    self.requests = Dashboard:CreateList(Dashboard:CreateCard(self.detail, "LID_GROUPAPPLICANTS"))
    self.requests:SetPoint("TOPLEFT", self.detail, "TOPLEFT", 6, -156)
    self.requests:SetPoint("BOTTOMRIGHT", self.detail, "BOTTOMRIGHT", -6, 6)
    self.requestRows = {}
end

function Groups:Build(content)
    local Members, Window, Dashboard = GuildHelper.Members, GuildHelper.Window, GuildHelper.Dashboard
    self.content = content
    local title = Window:CreatePageTitle(content, "LID_GROUPFINDER")
    self.modePills = {}
    local previous = title
    for index, mode in ipairs(self.modes) do
        local value = mode.value
        local pill = Members:CreatePill(content, "")
        pill:SetPoint("LEFT", previous, "RIGHT", index == 1 and 24 or 8, 0)
        pill:SetScript("OnClick", function() self:SetMode(value) end)
        self.modePills[value] = pill
        previous = pill
    end
    self.hint = self:Text(content, nil, Window.PADDING, -62, 11)
    self.hint:SetPoint("RIGHT", content, "RIGHT", -Window.MARGIN, 0)
    local scroll = CreateFrame("ScrollFrame", nil, content)
    scroll:SetPoint("TOPLEFT", content, "TOPLEFT", Window.PADDING, -84)
    scroll:SetPoint("BOTTOMRIGHT", content, "BOTTOMRIGHT", -Window.MARGIN, 8)
    local body = CreateFrame("Frame", nil, scroll)
    self.pageMinHeight = 700
    body:SetSize(max(1, scroll:GetWidth()), max(self.pageMinHeight, scroll:GetHeight()))
    scroll:SetScrollChild(body)
    scroll:EnableMouseWheel(true)
    scroll:SetScript("OnMouseWheel", function(_, delta) self:ScrollPage(delta) end)
    scroll:SetScript("OnSizeChanged", function(_, width, height)
        body:SetWidth(max(1, width))
        body:SetHeight(max(self.pageMinHeight, height))
    end)
    scroll:SetScript("OnScrollRangeChanged", function(sel)
        sel:SetVerticalScroll(min(sel:GetVerticalScroll(), sel:GetVerticalScrollRange()))
    end)
    self.pageScroll = scroll
    GuildHelper.Feedback:AddThumb(scroll, 2)
    self:BuildDetail(body)
    self:BuildForm(body)
    self.list = Dashboard:CreateList(Dashboard:CreateCard(body, "LID_GROUPLIST"))
    self.list.scrollPage = function(delta) self:ScrollPage(delta) end
    self.requests.scrollPage = self.list.scrollPage
    self.roster.scrollPage = self.list.scrollPage
    GuildHelper.Feedback:AddThumb(self.list.scroll, -4)
    GuildHelper.Feedback:AddThumb(self.roster.scroll, -4)
    GuildHelper.Feedback:AddThumb(self.requests.scroll, -4)
    self.list:SetPoint("TOPLEFT", self.form, "BOTTOMLEFT", 0, -12)
    self.list:SetPoint("BOTTOMRIGHT", self.detail, "BOTTOMLEFT", -12, 0)
    self.empty = self:Text(self.list, "LID_GROUPNONE", 14, -42)
    self.empty:SetPoint("RIGHT", self.list, "RIGHT", -14, 0)
    self.empty:SetWordWrap(true)
    self.rows = {}
    content.OnPageShow = function()
        Members:Scan()
        Members:RequestRoster()
        self:Request()
        self:SyncNote()
        self:Refresh()
    end

    content.OnPageHide = function()
        self.noteBox:ClearFocus()
        for _, box in ipairs(self.countBoxes) do
            box:ClearFocus()
        end

        if Members.menu then Members.menu:Hide() end
    end

    self:SyncNote()
    self:Refresh()
end

function Groups:ScrollPage(delta)
    local scroll = self.pageScroll
    if scroll then scroll:SetVerticalScroll(min(max(scroll:GetVerticalScroll() - delta * 40, 0), scroll:GetVerticalScrollRange())) end
end

function Groups:RefreshRoster(entry)
    local Dashboard, Members = GuildHelper.Dashboard, GuildHelper.Members
    local roster = entry.roster or {}
    local count = #roster
    self.roster:SetHeight(42 + max(1, count) * Dashboard.LINE)
    if count == 0 then
        Dashboard:SetLine(self.roster, 1, GuildHelper:Trans("LID_NODATA"), nil, nil, true)
    else
        for index, member in ipairs(roster) do
            local role = GuildHelper.Specs:Format(member, true)
            local guildMember = Members:FindByName(member.name)
            local name = Members:NameWithTwitch(guildMember, member.name)
            Dashboard:SetLine(self.roster, index, (role and role .. "  " or "") .. Members:RaceIconMarkup(guildMember, 14) .. name)
        end
    end
    Dashboard:FinishList(self.roster, max(1, count))
end

function Groups:RefreshRequests(entry)
    local names = {}
    for name in pairs(entry.applicants or {}) do
        tinsert(names, name)
    end

    table.sort(names)
    local canInvite = self:IsOwn(entry) and self:CanInvite()
    for index, name in ipairs(names) do
        local row = self.requestRows[index]
        if not row then
            row = CreateFrame("Frame", nil, self.requests.body)
            row:SetPoint("TOPLEFT", self.requests.body, "TOPLEFT", 0, -(index - 1) * 52)
            row:SetPoint("TOPRIGHT", self.requests.body, "TOPRIGHT", 0, -(index - 1) * 52)
            row:SetHeight(52)
            row.button = GuildHelper.Members:CreateButton(row, "LID_INVITE")
            row.button:SetPoint("RIGHT", row, "RIGHT", -4, 0)
            row.text = self:Text(row, nil, 8, -5, 12, "text")
            row.text:SetPoint("RIGHT", row.button, "LEFT", -6, 0)
            row.text:SetWordWrap(true)
            row.text:SetHeight(42)
            row.button:SetScript("OnClick", function() self:Invite(row.applicant) end)
            self.requestRows[index] = row
        end

        local applicant = entry.applicants[name]
        row.applicant = applicant
        local role = self:IsOutdoor(self:GetListingMode(entry)) and "" or "\n" .. GuildHelper.Specs:Format({role = applicant.role})
        row.text:SetText(applicant.name .. role)

        row.button:SetEnabled(canInvite)
        row:Show()
    end

    for index = #names + 1, #self.requestRows do
        self.requestRows[index]:Hide()
    end

    if not self.requests.empty then
        self.requests.empty = self:Text(self.requests.body, "LID_GROUPNOAPPLICANTS", 8, -5)
        self.requests.empty:SetPoint("RIGHT", self.requests.body, "RIGHT", -8, 0)
    end
    self.requests.empty:SetShown(#names == 0)
    self.requests.body:SetHeight(max(30, #names * 52))
end

function Groups:RefreshForm()
    local Members = GuildHelper.Members
    local planned = self.mode == "P"
    local draft = self.draft[self.mode]
    if planned and not draft.day then draft.day = tonumber(date("%H")) < draft.hour and 0 or 1 end
    for _, mode in ipairs(self.modes) do
        local pill = self.modePills[mode.value]
        Members:SetPillActive(pill, self.mode == mode.value)
        Members:SetPillText(pill, GuildHelper:Trans(mode.label) .. " (" .. #self:GetList(mode.value) .. ")")
    end
    local outdoor = self:IsOutdoor(self.mode)
    local activityLabel = self.mode == "Q" and "LID_GROUPQUEST" or (self.mode == "Z" and "LID_ZONE" or "LID_GROUPACTIVITY")
    self.activityLabel:SetText(GuildHelper:Trans(activityLabel))
    self.hint:SetText(GuildHelper:Trans(planned and "LID_GROUPHINTPLANNED" or "LID_GROUPHINTLIVE"))
    local activities = self:GetModeActivities(self.mode)
    local activity = draft.activity and activities.map[draft.activity]
    local pill = self.activityPill
    local texture = activity and activity.texture
    local height = activity and (outdoor and 36 or 55) or pill.compactHeight
    local extra = height - pill.compactHeight
    pill:SetHeight(height)
    pill.art:SetTexture(texture)
    pill.art:SetTexCoord(unpack(activity and activity.texCoords or {0, 1, 0, 1}))
    pill.art:SetShown(texture ~= nil)
    pill.text:SetPoint("LEFT", pill, "LEFT", texture and 100 or 8, 0)
    self.form:SetHeight((planned and 288 or 264) + extra)
    self.needsLabel:SetPoint("TOPLEFT", self.form, "TOPLEFT", 14, -51 - extra)
    self.liveNeeds:SetPoint("TOPLEFT", self.form, "TOPLEFT", 150, -51 - extra)
    self.noteLabel:SetPoint("TOPLEFT", self.form, "TOPLEFT", 14, (planned and -109 or -85) - extra)
    self.dateLabel:SetPoint("TOPLEFT", self.form, "TOPLEFT", 14, -143 - extra)
    self.dayPill:SetPoint("TOPLEFT", self.form, "TOPLEFT", 150, -136 - extra)
    self:RefreshAnnouncementOptions(planned, extra)
    local choose = outdoor and "LID_GROUPCHOOSEACTIVITY" or "LID_GROUPCHOOSE"
    local empty = outdoor and "LID_NODATA" or "LID_GROUPNOACTIVITIES"
    Members:SetPillText(self.activityPill, activity and activity.label or GuildHelper:Trans(activities.count > 0 and choose or empty))
    self.activityPill:SetEnabled(activities.count > 0)
    self.liveNeeds:SetShown(not planned)
    local showSoloRole = self.mode == "L" and self:IsSolo()
    self.soloRolePill:SetShown(showSoloRole)
    if showSoloRole then
        Members:SetPillText(self.soloRolePill, GuildHelper.Specs:Format({role = draft.soloRole}) or GuildHelper:Trans("LID_GROUPCHOOSEROLE"))
    end
    if not planned then
        local counts = self:GetRecruitmentNeeds(self.mode, activity, draft.soloRole)
        local needs = outdoor and tostring(self:Total(counts)) or self:Needs(counts)
        if not showSoloRole then needs = needs .. "   " .. GuildHelper:Trans("LID_GROUPFROMGROUP") end
        self.liveNeeds:SetText(needs)
    end
    for index, role in ipairs(GuildHelper.Specs.ROLES) do
        self.countLabels[index]:SetPoint("TOPLEFT", self.form, "TOPLEFT", 150 + (index - 1) * 96, -48 - extra)
        self.countLabels[index]:SetText(GuildHelper.Specs:Format({
            role = role.value
        }))

        self.countLabels[index]:SetShown(planned)
        self.countBoxes[index]:SetShown(planned)
    end

    self.dateLabel:SetShown(planned)
    self.dayPill:SetShown(planned)
    self.hourPill:SetShown(planned)
    self.minutePill:SetShown(planned)
    if planned then
        Members:SetPillText(self.dayPill, self:DayLabel(time() + draft.day * 86400, draft.day))
        Members:SetPillText(self.hourPill, format("%02d", draft.hour))
        Members:SetPillText(self.minutePill, format("%02d", draft.minute))
    end

    local current = self:GetCurrent()
    local ok, status = self:Validate()
    local cooldown = planned and 0 or self:GetChatCooldown()
    self.publish:SetEnabled(ok and self:IsReady() and cooldown == 0)
    GuildHelper.Theme:SetTrans(self.publish.text, current and "LID_GROUPUPDATE" or "LID_GROUPPUBLISH")
    if cooldown > 0 then
        self.publish.text:SetText(format("0:%02d", math.ceil(cooldown)))
    end
    self.publish:SetAlpha(cooldown > 0 and 0.55 or 1)
    self.new:SetShown(planned)
    self.new:SetEnabled(current ~= nil)
    self.close:ClearAllPoints()
    self.close:SetPoint("LEFT", planned and self.new or self.publish, "RIGHT", 12, 0)
    self.close:SetEnabled(current ~= nil)
    local text = GuildHelper:Trans(status)
    if planned and current then text = text .. ": " .. self:GetActivityName(current) .. " · " .. self:FormatWhen(current.when) end
    self.status:SetText(text)
end

function Groups:GetRow(index)
    local row = self.rows[index]
    if row then return row end
    row = CreateFrame("Button", nil, self.list.body)
    row:SetPoint("TOPLEFT", self.list.body, "TOPLEFT", 0, -(index - 1) * self.ROW)
    row:SetPoint("TOPRIGHT", self.list.body, "TOPRIGHT", 0, -(index - 1) * self.ROW)
    row:SetHeight(self.ROW - 4)
    row.bg = GuildHelper.Theme:Round(row, "navActive", 6)
    row.art = row:CreateTexture(nil, "ARTWORK")
    row.art:SetPoint("LEFT", row, "LEFT", 6, 0)
    row.art:SetSize(88, 50)
    row.tag = self:Text(row, nil, 0, 0, 12, "accent")
    row.tag:ClearAllPoints()
    row.tag:SetPoint("TOPRIGHT", row, "TOPRIGHT", -10, -9)
    row.tag:SetJustifyH("RIGHT")
    row.title = self:Text(row, nil, 10, -7, 14, "text")
    row.title:SetPoint("RIGHT", row.tag, "LEFT", -10, 0)
    row.title:SetWordWrap(false)
    row.info = self:Text(row, nil, 10, -27, 12, "text")
    row.info:SetPoint("RIGHT", row, "RIGHT", -10, 0)
    row.note = self:Text(row, nil, 10, -44, 11)
    row.note:SetPoint("RIGHT", row, "RIGHT", -10, 0)
    row.note:SetWordWrap(false)
    row:SetScript("OnClick", function(sel)
        local entry = self:Find(sel.key)
        if entry then self:Select(entry) end
    end)

    self.rows[index] = row

    return row
end

function Groups:RefreshList()
    local list = self:GetList(self.mode)
    local viewed = self:GetViewedListings()
    local selected = self:Find(self.selected)
    if not selected or self:GetListingMode(selected) ~= self.mode then self.selected = list[1] and list[1].key end
    for index, entry in ipairs(list) do
        if viewed and not self:IsOwn(entry) and not viewed[entry.key] then viewed[entry.key] = time() end
        local row = self:GetRow(index)
        row.key = entry.key
        local activity = self:GetActivity(entry.activity)
        local texture, texCoords
        if activity then
            texture, texCoords = activity.texture, activity.texCoords
        else
            local source, id = entry.activity:match("^([ade])(%d+)$")
            id = tonumber(id)
            if source == "a" and C_LFGList and C_LFGList.GetActivityInfoTable then
                local info = C_LFGList.GetActivityInfoTable(id)
                texture, texCoords = self:GetDungeonArt(entry.activity, info and info.mapID, nil, nil, info and info.uiMapID)
            elseif source == "d" and GetLFGDungeonInfo then
                local _, _, _, _, _, _, _, _, _, _, textureName, _, _, _, _, _, _, _, _, _, _, mapID = GetLFGDungeonInfo(id)
                texture, texCoords = self:GetDungeonArt(entry.activity, mapID, nil, textureName)
            elseif source == "e" then
                texture, texCoords = self:GetDungeonArt(entry.activity, nil, id)
            end
        end
        row.art:SetTexture(texture)
        row.art:SetTexCoord(unpack(texCoords or {0, 1, 0, 1}))
        row.art:SetShown(texture ~= nil)
        local textLeft = texture and 102 or 10
        row.title:SetPoint("TOPLEFT", row, "TOPLEFT", textLeft, -7)
        row.info:SetPoint("TOPLEFT", row, "TOPLEFT", textLeft, -27)
        row.note:SetPoint("TOPLEFT", row, "TOPLEFT", textLeft, -44)
        row.title:SetText(activity and activity.label or entry.activityName or "?")
        row.tag:SetText(entry.kind == "P" and self:FormatWhen(entry.when) or GuildHelper:Trans("LID_GROUPLIVETAG"))
        local name = Ambiguate and Ambiguate(entry.name or "", "guild") or entry.name or ""
        local info = name .. "   " .. self:Needs(entry)
        if entry.applied then
            local role = self:IsOutdoor(self:GetListingMode(entry)) and "" or " " .. GuildHelper.Specs:Format({role = entry.applied})
            info = info .. "   " .. GuildHelper:Trans("LID_GROUPSIGNED") .. role
        end

        row.info:SetText(info)
        row.note:SetText(entry.note or "")
        row.bg:SetShown(entry.key == self.selected)
        row:Show()
    end

    for index = #list + 1, #self.rows do
        self.rows[index]:Hide()
    end

    self.list.body:SetHeight(max(1, #list * self.ROW))
    self.empty:SetShown(#list == 0)
end

function Groups:RefreshDetail()
    local entry = self:Find(self.selected)
    local own = self:IsOwn(entry)
    local foreign = entry ~= nil and not own
    self.detailTitle:SetText(entry and self:GetActivityName(entry) or GuildHelper:Trans("LID_GROUPSELECT"))
    self.detailInfo:SetText(entry and ((entry.name or "") .. " · " .. (entry.kind == "P" and self:FormatWhen(entry.when) or GuildHelper:Trans("LID_GROUPLIVETAG"))) or "")
    self.detailNeeds:SetText(entry and self:Needs(entry) or "")
    self.detailNote:SetText(entry and entry.note or "")
    local showRoster = entry ~= nil and entry.kind == "L"
    self.roster:SetShown(showRoster)
    local rosterOffset = 0
    if showRoster then
        self:RefreshRoster(entry)
        rosterOffset = self.roster:GetHeight() + 8
    end
    self.rolePill:SetPoint("TOPLEFT", self.detail, "TOPLEFT", 14, -158 - rosterOffset)
    self.apply:SetPoint("TOPLEFT", self.detail, "TOPLEFT", 14, -194 - rosterOffset)
    self.requests:SetShown(entry ~= nil)
    self.requests:ClearAllPoints()
    local requestsTop = (own and 156 or 236) + rosterOffset
    self.requests:SetPoint("TOPLEFT", self.detail, "TOPLEFT", 6, -requestsTop)
    self.requests:SetPoint("BOTTOMRIGHT", self.detail, "BOTTOMRIGHT", -6, 6)
    self.pageMinHeight = max(700, requestsTop + 106 + GuildHelper.Members.BOTTOM)
    self.pageScroll:GetScrollChild():SetHeight(max(self.pageMinHeight, self.pageScroll:GetHeight()))
    self.rolePill:SetShown(foreign and not self:IsOutdoor(self:GetListingMode(entry)))
    self.apply:SetShown(foreign)
    self.whisper:SetShown(foreign)
    if entry then
        self:RefreshRequests(entry)
        if own then
            for _, applicant in pairs(entry.applicants or {}) do applicant.unread = nil end
        end
    end
    if not foreign then return end
    local applied = entry.applied
    GuildHelper.Members:SetPillText(self.rolePill, GuildHelper.Specs:Format({
        role = applied or self.role
    }))

    self.rolePill:SetEnabled(true)
    GuildHelper.Theme:SetTrans(self.apply.text, applied and "LID_GROUPWITHDRAW" or "LID_GROUPAPPLY")
    self.apply:SetEnabled(self:IsReady() and (applied ~= nil or (entry[self:GetApplicationRole(entry)] or 0) > 0))
end

function Groups:Refresh()
    if self.content and self.content:IsVisible() and self.list then
        self:RefreshForm()
        self:RefreshList()
        self:RefreshDetail()
    end
    GuildHelper.Window:UpdateNavCount("groups", self:CountUnread())
    if GuildHelper.Calendar then GuildHelper.Calendar:QueueRefresh() end
end

GuildHelper.Window:SetPageBuilder("groups", function(content) Groups:Build(content) end)
GuildHelper.Window:OnRebuild(function() Groups.content = nil end)
GuildHelper.Theme:OnRefresh(function() Groups:Refresh() end)
Groups.events = CreateFrame("Frame")
Groups.events:RegisterEvent("PLAYER_LOGIN")
Groups.events:RegisterEvent("PLAYER_ENTERING_WORLD")
Groups.events:RegisterEvent("PLAYER_GUILD_UPDATE")
Groups.events:RegisterEvent("PLAYER_LOGOUT")
Groups.events:RegisterEvent("GROUP_ROSTER_UPDATE")
Groups.events:RegisterEvent("GUILD_ROSTER_UPDATE")
Groups.events:RegisterEvent("QUEST_LOG_UPDATE")
if not C_EventUtils or not C_EventUtils.IsEventValid or C_EventUtils.IsEventValid("ROLE_CHANGED_INFORM") then Groups.events:RegisterEvent("ROLE_CHANGED_INFORM") end
if C_EventUtils == nil or C_EventUtils.IsEventValid == nil or C_EventUtils.IsEventValid("PLAYER_ROLES_ASSIGNED") then Groups.events:RegisterEvent("PLAYER_ROLES_ASSIGNED") end
Groups.events:SetScript("OnEvent", function(_, event, _, reloadingUI)
    if event == "PLAYER_LOGOUT" then
        Groups:SaveLiveForReload()
        for _, entry in pairs(Groups.live) do
            if Groups:IsOwn(entry) then
                Groups:Close(entry)
            else
                Groups:Withdraw(entry)
            end
        end
    elseif event == "QUEST_LOG_UPDATE" then
        if Groups.scanningQuests then return end
        Groups.questActivities = nil
        if Groups.content and Groups.content:IsVisible() and Groups.mode == "Q" then Groups:Refresh() end
    elseif event == "GUILD_ROSTER_UPDATE" then
        if Groups.content and Groups.content:IsVisible() then
            GuildHelper.Members:Scan()
            Groups:Refresh()
        end
    elseif event == "GROUP_ROSTER_UPDATE" or event == "PLAYER_ROLES_ASSIGNED" or event == "ROLE_CHANGED_INFORM" then
        Groups.dirty = true
        Groups.rosterReadyAt = GetTime() + 2
    else
        Groups:CheckGuild()
        if event == "PLAYER_ENTERING_WORLD" and not Groups.enteredWorld then
            Groups.enteredWorld = true
            if reloadingUI then
                Groups.reloadReadyAt = GetTime() + 2
            else
                GuildHelper:SetConfig("GROUPLIVERELOAD", nil)
            end
        end
        if event == "PLAYER_LOGIN" then
            Groups:RegisterChatRoleIcons()
            C_Timer.After(10, function() Groups:Request() end)
        end
        Groups:Refresh()
    end
end)

Groups.elapsed = 0
Groups.events:SetScript("OnUpdate", function(_, elapsed)
    Groups.elapsed = Groups.elapsed + elapsed
    if Groups.elapsed < 1 then return end
    Groups.elapsed = 0
    Groups:Tick()
end)
