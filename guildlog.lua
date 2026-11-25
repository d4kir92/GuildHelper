local _, GuildHelper = ...
local Theme, Groups, Sync, Dashboard = GuildHelper.Theme, GuildHelper.Groups, GuildHelper.Sync, GuildHelper.Dashboard
local Log = {
    KEEP = 5000,
    KEEPDAYS = 365,
    SCANDELAY = 3,
    MAXAGE = 86400 * 30,
    LEVELS = {
        CLASSIC = {40, 60},
        TBC = {30, 60, 70},
        WRATH = {20, 40, 60, 70, 80},
        CATA = {20, 40, 60, 70, 80, 85},
        MISTS = {20, 40, 60, 70, 80, 85, 90}
    },
    TESTACHIEVEMENT = 6,
    PROFESSIONCAPS = {CLASSIC = 300, TBC = 375, WRATH = 450, CATA = 525, MISTS = 600},
    CLEARWINDOW = 900,
    FINALNPCS = {
        CATA = {
            [645] = {39705},
            [643] = {44566},
            [725] = {42333},
            [657] = {43875},
            [670] = {40484},
            [644] = {39378},
            [755] = {44819},
            [36] = {49541},
            [33] = {46964},
            [568] = {23863},
            [859] = {52155},
            [938] = {54432},
            [939] = {54969},
            [940] = {54938}
        },
        CLASSIC = {
        [389] = {11519},
        [36] = {639},
        [43] = {3654},
        [33] = {4275},
        [48] = {4829},
        [34] = {1716},
        [90] = {7800},
        [47] = {4421},
        [129] = {7358},
        [70] = {2748},
        [209] = {7267},
        [349] = {12201},
        [109] = {8443, 5709},
        [230] = {9019},
        [229] = {9568, 10363},
        [289] = {1853}
        }
    },
    WINGS = {
        [189] = {
            {id = 189001, label = "LID_WING_GRAVEYARD", npcs = {4543}, encounters = {445}},
            {id = 189002, label = "LID_WING_LIBRARY", npcs = {6487}, encounters = {447}},
            {id = 189003, label = "LID_WING_ARMORY", npcs = {3975}, encounters = {448}},
            {id = 189004, label = "LID_WING_CATHEDRAL", npcs = {3977}, encounters = {450}}
        },
        [429] = {
            {id = 429003, label = "LID_WING_EAST", npcs = {11492}, encounters = {346}},
            {id = 429002, label = "LID_WING_WEST", npcs = {11486}, encounters = {361}},
            {id = 429001, label = "LID_WING_NORTH", npcs = {11501}, encounters = {368}}
        },
        [329] = {
            {id = 329001, label = "LID_WING_LIVING", npcs = {10813}, encounters = {478}},
            {id = 329002, label = "LID_WING_UNDEAD", npcs = {10440}, encounters = {484}}
        }
    },
    FINALNPCLAYERS = {CLASSIC = {"CLASSIC"}, TBC = {"CLASSIC"}, WRATH = {"CLASSIC"}, CATA = {"CLASSIC", "CATA"}, MISTS = {"CLASSIC", "CATA"}},
    types = {},
    order = {},
    testEntries = {}
}

GuildHelper.Log = Log

function Log:Now()
    return GetServerTime and GetServerTime() or time()
end

function Log:RegisterType(kind, definition)
    if self.types[kind] == nil then tinsert(self.order, kind) end
    definition.kind = kind
    self.types[kind] = definition
end

function Log:GetStore()
    local guild = Sync:GetGuildKey()
    if not guild then return nil end
    GHTAB = GHTAB or {}
    GHTAB.GUILDLOG = GHTAB.GUILDLOG or {}
    local store = GHTAB.GUILDLOG[guild] or {}
    GHTAB.GUILDLOG[guild] = store
    store.entries = store.entries or {}
    store.levels = nil
    store.roster = store.roster or {}
    store.profs = store.profs or {}

    return store
end

function Log:Key(kind, name, value, run)
    local key = kind .. ":" .. name .. ":" .. tostring(value)
    if run then key = key .. ":" .. tostring(run) end

    return key
end

function Log:Add(kind, name, value, stamp, exact, extra)
    local store = self:GetStore()
    local definition = self.types[kind]
    local raw = name
    local display = type(name) == "string" and strsplit("-", name) or nil
    name = Groups:Name(name)
    if not store or not definition or not name then return false end
    extra = extra or {}
    if display and display ~= "" then extra.display, extra.full = display, raw end
    exact = exact and true or nil
    local key = self:Key(kind, name, value, extra.run)
    local entry = store.entries[key]
    if entry then
        if entry.exact and not exact then return false end
        if entry.exact == exact and entry.time <= stamp then return false end
        entry.time, entry.exact = stamp, exact
    else
        entry = {kind = kind, name = name, value = value, time = stamp, exact = exact}
        store.entries[key] = entry
        entry.isNew = true
    end
    if extra then
        for field, data in pairs(extra) do entry[field] = data end
    end
    if entry.isNew then
        entry.isNew = nil
        self:Notify(entry)
    end
    self:Prune(store)
    self:Refresh()

    return true
end

function Log:GetNotifyOptions()
    local list = {}
    for _, filter in ipairs(self.FILTERS) do
        if not filter.available or filter.available() then
            tinsert(list, {key = "LOGNOTIFY" .. strupper(filter.key), default = false, label = filter.label, display = true})
        end
    end

    return list
end

function Log:Notify(entry)
    local definition = self.types[entry.kind]
    local Notifications = GuildHelper.Notifications
    if not definition or not entry.exact or not Notifications or entry.time < Notifications.started or entry.time < self:Now() - 600 then return end
    if GuildHelper:GetConfig("LOGNOTIFY" .. strupper(definition.filter or entry.kind), false) ~= true then return end
    if not definition.group and Groups:IsSelfName(entry.name) then return end
    local seenKey = "log:" .. entry.kind .. ":" .. tostring(entry.value) .. ":" .. (definition.group and tostring(entry.run or entry.time) or entry.name)
    if Notifications.seen[seenKey] then return end
    Notifications.seen[seenKey] = true
    C_Timer.After(1, function()
        local view = entry
        if definition.group then
            local store, list = self:GetStore(), {}
            for _, other in pairs(store and store.entries or {}) do
                if other.kind == entry.kind and other.value == entry.value and abs(other.time - entry.time) <= self.CLEARWINDOW then
                    if Groups:IsSelfName(other.name) then return end
                    tinsert(list, other)
                end
            end
            table.sort(list, function(a, b) return a.time > b.time end)
            view = self:MergeClears(list)[1] or entry
        end
        Notifications:LogEntry(self:FormatEntry(view))
    end)
end

function Log:Prune(store)
    local list = {}
    local cutoff = self:Now() - self.KEEPDAYS * 86400
    for key, entry in pairs(store.entries) do
        if entry.time < cutoff then
            store.entries[key] = nil
        else
            tinsert(list, {key = key, time = entry.time})
        end
    end
    if #list <= self.KEEP then return end
    table.sort(list, function(a, b) return a.time > b.time end)
    for index = self.KEEP + 1, #list do store.entries[list[index].key] = nil end
end

function Log:GetEntries()
    local store = self:GetStore()
    local list = {}
    if not store then return list end
    for _, source in ipairs({store.entries, self.testEntries}) do
        for _, entry in pairs(source) do
            local definition = self.types[entry.kind]
            if definition and not self:IsHidden(definition.filter or entry.kind)
                and (not self.rangeFrom or entry.time >= self.rangeFrom) and (not self.rangeTo or entry.time <= self.rangeTo) then
                tinsert(list, entry)
            end
        end
    end
    table.sort(list, function(a, b)
        if a.time ~= b.time then return a.time > b.time end
        if (a.order or 0) ~= (b.order or 0) then return (a.order or 0) > (b.order or 0) end
        if a.name ~= b.name then return a.name < b.name end
        return tostring(a.value) > tostring(b.value)
    end)

    return self:MergeClears(list)
end

function Log:MergeClears(list)
    local result, groups = {}, {}
    for _, entry in ipairs(list) do
        local definition = self.types[entry.kind]
        if definition.group then
            local groupKey = entry.kind .. ":" .. tostring(entry.value)
            local group = groups[groupKey]
            if group and group.time - entry.time <= self.CLEARWINDOW then
                if not group.names[entry.name] then
                    group.names[entry.name] = true
                    tinsert(group.members, entry)
                end
                group.exact = group.exact or entry.exact
                group.instanceName = group.instanceName or entry.instanceName
            else
                group = {kind = entry.kind, value = entry.value, time = entry.time, exact = entry.exact, order = entry.order,
                    name = entry.name, instanceName = entry.instanceName, members = {entry}, names = {[entry.name] = true}}
                groups[groupKey] = group
                tinsert(result, group)
            end
        else
            tinsert(result, entry)
        end
    end

    return result
end

function Log:Send(kind, value, stamp)
    Sync:Send(table.concat({"GL", kind, value, stamp}, "~"), "log:" .. kind .. ":" .. value)
end

function Log:OnMessage(message, sender)
    if #message > 250 or Groups:IsSelfName(sender) then return end
    local kind, value, stamp, names = message:match("^GL~(%a+)~(%d+)~(%d+)~(.+)$")
    if kind then
        self:ReceiveMembers(kind, tonumber(value), tonumber(stamp), names)
        return
    end
    kind, value, stamp = message:match("^GL~(%a+)~(%d+)~(%d+)$")
    local definition = kind and self.types[kind]
    if not definition or not definition.receive then return end
    value, stamp = tonumber(value), tonumber(stamp)
    local now = self:Now()
    if not value or not stamp or stamp > now + 300 or stamp < now - self.MAXAGE then return end
    definition.receive(self, sender, value, stamp)
end

function Log:ReceiveMembers(kind, value, stamp, names)
    local definition = self.types[kind]
    local now = self:Now()
    if not definition or not definition.group or not value or not stamp or stamp > now + 300 or stamp < now - self.MAXAGE then return end
    for name in names:gmatch("[^,]+") do
        local level, classFile, member = self:RosterMember(name)
        if level then self:Add(kind, member, value, stamp, true, {class = classFile, run = stamp}) end
    end
end

function Log:GetInstance()
    if not GetInstanceInfo then return nil end
    local name, instanceType, _, _, _, _, _, instanceID = GetInstanceInfo()
    local kind = instanceType == "party" and "dungeon" or (instanceType == "raid" and "raid" or nil)
    if not kind or type(instanceID) ~= "number" then return nil end

    return kind, instanceID, name
end

function Log:FindWing(instanceID, field, value)
    for _, wing in ipairs(self.WINGS[instanceID] or {}) do
        for _, id in ipairs(wing[field]) do
            if id == value then return wing end
        end
    end
end

function Log:GetWing(value)
    local instanceID = floor((tonumber(value) or 0) / 1000)
    for _, wing in ipairs(self.WINGS[instanceID] or {}) do
        if wing.id == value then return wing, instanceID end
    end
end

function Log:ClearName(entry)
    local wing, instanceID = self:GetWing(entry.value)
    if not wing then return entry.instanceName or self:InstanceName(entry.value) end

    return format("%s (%s)", entry.instanceName or self:InstanceName(instanceID), GuildHelper:Trans(wing.label))
end

function Log:InstanceName(instanceID)
    if GetRealZoneText then
        local ok, name = pcall(GetRealZoneText, instanceID)
        if ok and type(name) == "string" and name ~= "" then return name end
    end

    return "#" .. tostring(instanceID)
end

function Log:IsFinalBoss(instanceID, encounterID)
    if not EJ_GetInstanceForMap or not EJ_GetEncounterInfoByIndex or not C_Map or not C_Map.GetBestMapForUnit then return false end
    local mapID = C_Map.GetBestMapForUnit("player")
    local okInstance, journal = pcall(EJ_GetInstanceForMap, mapID or 0)
    if not okInstance or type(journal) ~= "number" or journal <= 0 then return false end
    local last
    for index = 1, 40 do
        local ok, name, _, _, _, _, _, dungeonEncounterID = pcall(EJ_GetEncounterInfoByIndex, index, journal)
        if not ok or not name then break end
        last = dungeonEncounterID
    end

    return last ~= nil and last == encounterID
end

function Log:GetGroupGuildMembers()
    local list = {}
    local count = GetNumGroupMembers and GetNumGroupMembers() or 0
    local prefix = IsInRaid and IsInRaid() and "raid" or "party"
    for index = 1, prefix == "raid" and count or count - 1 do
        local unit = prefix .. index
        local name, realm = UnitName(unit)
        if GuildHelper:CanAccessValues(name, realm) and name then
            local level, classFile, member = self:RosterMember(realm and realm ~= "" and (name .. "-" .. realm) or name)
            if level and not Groups:IsSelfName(member) then tinsert(list, {name = member, class = classFile}) end
        end
    end

    return list
end

function Log:OnEncounterEnd(encounterID, encounterName, success)
    if success ~= 1 and success ~= true then
        self:Debug("ENCOUNTER_END ohne Erfolg, ignoriert")
        return
    end
    local kind, instanceID, instanceName = self:GetInstance()
    if not kind or type(encounterID) ~= "number" then
        self:Debug("ENCOUNTER_END ignoriert: keine Dungeon-/Raid-Instanz oder ID unlesbar", kind, instanceID)
        return
    end
    self:CollectEncounter(kind, instanceID, instanceName, encounterID, encounterName)
    if GuildHelper.FinalEncounters then
        local value = GuildHelper.FinalEncounters[encounterID]
        self:Debug("Endboss-Daten:", encounterID, value and ("-> Endboss, Wert " .. value) or "-> kein Endboss")
        if value then self:RecordClear(kind, value, instanceName) end
        return
    end
    self:Debug("Keine Endboss-Datei geladen, prüfe Flügel/Encounter Journal")
    if self.WINGS[instanceID] then
        local wing = self:FindWing(instanceID, "encounters", encounterID)
        if wing then self:RecordClear(kind, wing.id, instanceName) end
        return
    end
    if not self:IsFinalBoss(instanceID, encounterID) then return end
    self:RecordClear(kind, instanceID, instanceName)
end

function Log:GetNpcID(guid)
    if type(guid) ~= "string" or not GuildHelper:CanAccessValue(guid) then return nil end
    local unitType, _, _, _, _, npcID = strsplit("-", guid)
    if unitType ~= "Creature" and unitType ~= "Vehicle" then return nil end

    return tonumber(npcID)
end

function Log:GetFinalNPCs(instanceID)
    local finals
    for _, layer in ipairs(self.FINALNPCLAYERS[GuildHelper:GetWoWBuild()] or {}) do
        finals = self.FINALNPCS[layer][instanceID] or finals
    end

    return finals
end

function Log:OnUnitDied(guid)
    if GuildHelper:IsForever() then return end
    local npcID = self:GetNpcID(guid)
    if not npcID then return end
    local kind, instanceID, instanceName = self:GetInstance()
    if kind then self:Debug("Kampflog UNIT_DIED NPC", npcID, "in", instanceID) end
    if kind and self.WINGS[instanceID] then
        local wing = self:FindWing(instanceID, "npcs", npcID)
        if wing then self:RecordClear(kind, wing.id, instanceName) end
        return
    end
    local finals = kind and self:GetFinalNPCs(instanceID)
    if not finals then return end
    for _, finalID in ipairs(finals) do
        if finalID == npcID then
            self:RecordClear(kind, instanceID, instanceName)
            return
        end
    end
end

function Log:RecordClear(kind, instanceID, instanceName)
    local stamp = self:Now()
    self.lastClear = self.lastClear or {}
    if self.lastClear[instanceID] and stamp - self.lastClear[instanceID] < self.CLEARWINDOW then
        self:Debug("Clear übersprungen (schon erfasst):", kind, instanceID)
        return
    end
    self.lastClear[instanceID] = stamp
    local own = self:OwnName()
    if not own then
        self:Debug("Clear übersprungen: eigener Name unbekannt")
        return
    end
    self:Debug("Clear erfasst:", kind, instanceID, instanceName, "als", own)
    local _, classFile = UnitClass("player")
    self:Add(kind, own, instanceID, stamp, true, {class = classFile, run = stamp, instanceName = instanceName})
    self:Send(kind, instanceID, stamp)
    local names = {}
    for _, member in ipairs(self:GetGroupGuildMembers()) do
        self:Add(kind, member.name, instanceID, stamp, true, {class = member.class, run = stamp, instanceName = instanceName})
        tinsert(names, member.name)
    end
    local head = table.concat({"GL", kind, instanceID, stamp}, "~") .. "~"
    local chunk, part = {}, 0
    local function flush()
        if #chunk == 0 then return end
        part = part + 1
        Sync:Send(head .. table.concat(chunk, ","), "logmembers:" .. stamp .. ":" .. part)
        chunk = {}
    end
    for _, name in ipairs(names) do
        if #head + #table.concat(chunk, ",") + #name + 1 > 200 then flush() end
        tinsert(chunk, name)
    end
    flush()
end

function Log:CollectEncounter(kind, instanceID, instanceName, encounterID, encounterName)
    if not GuildHelper.FeedbackShare or not GuildHelper.FeedbackShare:IsDeveloper() then return end
    GHTAB.ENCOUNTERS = GHTAB.ENCOUNTERS or {}
    local build = GuildHelper:IsForever() and "FOREVER" or GuildHelper:GetWoWBuild()
    GHTAB.ENCOUNTERS[build] = GHTAB.ENCOUNTERS[build] or {}
    local instances = GHTAB.ENCOUNTERS[build]
    local instance = instances[instanceID] or {bosses = {}, count = 0}
    instances[instanceID] = instance
    instance.name, instance.kind = instanceName, kind
    local boss = instance.bosses[encounterID]
    if not boss then
        instance.count = instance.count + 1
        boss = {order = instance.count, kills = 0}
        instance.bosses[encounterID] = boss
    end
    boss.name, boss.kills, boss.last = encounterName, boss.kills + 1, self:Now()
    instance.lastKill = encounterID
    print("[GuildHelper]", "Boss erfasst:", tostring(encounterName), encounterID, "in", tostring(instanceName), instanceID, (GuildHelper.FinalEncounters and GuildHelper.FinalEncounters[encounterID] or (not GuildHelper.FinalEncounters and self:IsFinalBoss(instanceID, encounterID))) and "(Endboss)" or "")
end

function Log:GetLevelList()
    if GuildHelper:IsForever() then return self.LEVELS.CLASSIC end

    return self.LEVELS[GuildHelper:GetWoWBuild()] or self.LEVELS.CLASSIC
end

function Log:GetLevelMilestones()
    if self.milestones then return self.milestones end
    local list = {}
    for _, level in ipairs(self:GetLevelList()) do list[level] = true end
    self.milestones = list

    return list
end

function Log:RosterMember(name)
    local key = Groups:Name(name)
    if not key then return nil end
    for index = 1, GetNumGuildMembers() or 0 do
        local member, _, _, level, _, _, _, _, _, _, classFile = GetGuildRosterInfo(index)
        if member and GuildHelper:CanAccessValues(member, level) and Groups:Name(member) == key then return level, classFile, member end
    end
end

function Log:ScanRoster()
    local store = self:GetStore()
    local total = GetNumGuildMembers and GetNumGuildMembers() or 0
    if not store or total == 0 then return end
    local milestones = self:GetLevelMilestones()
    local now = self:Now()
    local exact = self.live
    local baseline = next(store.roster) ~= nil
    local seen, complete = {}, true
    for index = 1, total do
        local name, rankName, rankIndex, level, _, _, _, _, _, _, classFile = GetGuildRosterInfo(index)
        local key = GuildHelper:CanAccessValues(name, rankName, rankIndex, level) and Groups:Name(name)
        if key and type(level) == "number" and level > 0 and type(rankIndex) == "number" then
            seen[key] = true
            local previous = store.roster[key]
            local extra = {class = classFile}
            if previous then
                for milestone = previous.level + 1, level do
                    if milestones[milestone] then self:Add("level", name, milestone, now, exact, extra) end
                end
                if previous.rank ~= rankIndex and rankName then
                    self:Add(rankIndex < previous.rank and "promote" or "demote", name, now, now, exact, {class = classFile, rank = rankName})
                end
            elseif baseline then
                self:Add("join", name, now, now, exact, extra)
            end
            store.roster[key] = {level = level, rank = rankIndex, class = classFile, display = name}
        else
            complete = false
        end
    end
    local missing = {}
    for key in pairs(store.roster) do
        if not seen[key] then tinsert(missing, key) end
    end
    local showOffline = not GetGuildRosterShowOffline or GetGuildRosterShowOffline()
    if complete and showOffline and #missing <= max(3, floor(total * 0.1)) then
        for _, key in ipairs(missing) do
            self:Add("leave", store.roster[key].display or key, now, now, exact, {class = store.roster[key].class})
            store.roster[key] = nil
        end
    end
    self.live = true
end

function Log:FullName(shortName)
    for index = 1, GetNumGuildMembers() or 0 do
        local name, _, _, level, _, _, _, _, _, _, classFile = GetGuildRosterInfo(index)
        if name and GuildHelper:CanAccessValues(name, level) and (strsplit("-", name)) == shortName then return name, classFile end
    end

    return shortName
end

function Log:CheckProfessions(shortName, professions, own)
    local store = self:GetStore()
    local cap = self:GetProfessionCap()
    if not store or not cap or type(professions) ~= "table" then return end
    local name, classFile = self:FullName(shortName)
    local key = Groups:Name(name)
    if not key then return end
    local known = store.profs[key]
    store.profs[key] = store.profs[key] or {}
    for _, entry in ipairs(professions) do
        local id, rank = Sync:GetProfessionID(entry[1], entry[4]), tonumber(entry[2]) or 0
        if Sync:IsCraftingProfession(id) then
            local previous = store.profs[key][id]
            if known and (previous or 0) < cap and rank >= cap then
                self:Add("profession", name, id, self:Now(), self.live or own, {class = classFile})
            end
            store.profs[key][id] = rank
        end
    end
end

function Log:GetProfessionCap()
    if GuildHelper:IsForever() then return 300 end

    return self.PROFESSIONCAPS[GuildHelper:GetWoWBuild()]
end

function Log:OnAchievement(id)
    local points = self:GetLegacyPoints(id)
    local own = self:OwnName()
    if not points or not own then return end
    local stamp = self:Now()
    local _, classFile = UnitClass("player")
    self:Add("legacy", own, id, stamp, true, {class = classFile})
    self:Send("legacy", id, stamp)
end

function Log:GetLegacyPoints(id)
    if not GuildHelper:IsForever() or not GetAchievementInfo or type(id) ~= "number" then return nil end
    local ok, achievementID, _, points = pcall(GetAchievementInfo, id)
    if not ok or achievementID ~= id or type(points) ~= "number" or points < 1 then return nil end

    return points
end

function Log:OnGuildAchievement(message, sender)
    if type(message) ~= "string" or not GuildHelper:CanAccessValues(message, sender) then return end
    local id = tonumber(message:match("|Hachievement:(%d+)"))
    if not id or not self:GetLegacyPoints(id) then return end
    local _, classFile, member = self:RosterMember(sender)
    self:Add("legacy", member or sender, id, self:Now(), true, {class = classFile})
end

function Log:OnLevelUp(level)
    if type(level) ~= "number" or not self:GetLevelMilestones()[level] then return end
    local own = self:OwnName()
    if not own then return end
    local stamp = self:Now()
    local _, classFile = UnitClass("player")
    self:Add("level", own, level, stamp, true, {class = classFile})
    self:Send("level", level, stamp)
end

Log:RegisterType("level", {
    text = function(entry) return format(GuildHelper:Trans("LID_LOGLEVEL"), entry.short, entry.value) end,
    receive = function(self, sender, value, stamp)
        if not self:GetLevelMilestones()[value] then return end
        local level, classFile, member = self:RosterMember(sender)
        if not level or level < value - 1 then return end
        self:Add("level", member, value, stamp, true, {class = classFile})
    end
})

Log:RegisterType("legacy", {
    text = function(entry)
        local points = Log:GetLegacyPoints(entry.value) or 1
        local ok, _, name = false, nil, nil
        if GetAchievementInfo then ok, _, name = pcall(GetAchievementInfo, entry.value) end
        if not ok or type(name) ~= "string" or name == "" then
            name = "#" .. tostring(entry.value)
        elseif GetAchievementLink then
            local okLink, link = pcall(GetAchievementLink, entry.value)
            if okLink and type(link) == "string" and link ~= "" then name = link end
        end
        return format(GuildHelper:Trans(points == 1 and "LID_LOGLEGACY" or "LID_LOGLEGACYS"), entry.short, name, points)
    end,
    receive = function(self, sender, value, stamp)
        if not self:GetLegacyPoints(value) then return end
        local level, classFile, member = self:RosterMember(sender)
        if not level then return end
        self:Add("legacy", member, value, stamp, true, {class = classFile})
    end
})

Log:RegisterType("profession", {
    text = function(entry)
        return format(GuildHelper:Trans("LID_LOGPROF"), entry.short, Sync:GetProfessionName(entry.value, "?"), Log:GetProfessionCap() or 0)
    end
})

Log:RegisterType("join", {text = function(entry) return format(GuildHelper:Trans("LID_LOGJOIN"), entry.short) end})
Log:RegisterType("leave", {text = function(entry) return format(GuildHelper:Trans("LID_LOGLEAVE"), entry.short) end})
Log:RegisterType("promote", {filter = "rank", text = function(entry) return format(GuildHelper:Trans("LID_LOGPROMOTE"), entry.short, entry.rank or "?") end})
Log:RegisterType("demote", {filter = "rank", text = function(entry) return format(GuildHelper:Trans("LID_LOGDEMOTE"), entry.short, entry.rank or "?") end})

for _, clearKind in ipairs({"dungeon", "raid"}) do
    local kind = clearKind
    Log:RegisterType(kind, {
        group = true,
        text = function(entry)
            return format(GuildHelper:Trans((entry.count or 1) > 1 and "LID_LOGCLEARS" or "LID_LOGCLEAR"), entry.short, Log:ClearName(entry))
        end,
        receive = function(self, sender, value, stamp)
            local level, classFile, member = self:RosterMember(sender)
            if level then self:Add(kind, member, value, stamp, true, {class = classFile, run = stamp}) end
        end
    })
end

Log.FILTERS = {
    {key = "level", label = "LID_LOGFILTERLEVEL"},
    {key = "join", label = "LID_LOGFILTERJOIN"},
    {key = "leave", label = "LID_LOGFILTERLEAVE"},
    {key = "rank", label = "LID_LOGFILTERRANK"},
    {key = "profession", label = "LID_LOGFILTERPROF", available = function() return Log:GetProfessionCap() ~= nil end},
    {key = "legacy", label = "LID_LOGFILTERLEGACY", available = function() return GuildHelper:IsForever() end},
    {key = "dungeon", label = "LID_LOGFILTERDUNGEON"},
    {key = "raid", label = "LID_LOGFILTERRAID"}
}

function Log:ParseDate(text, endOfDay)
    text = strtrim(text or "")
    if text == "" then return nil end
    local day, month, year = text:match("^(%d%d?)%.(%d%d?)%.(%d%d%d%d)$")
    if not day then year, month, day = text:match("^(%d%d%d%d)%-(%d%d?)%-(%d%d?)$") end
    day, month, year = tonumber(day), tonumber(month), tonumber(year)
    if not day or month < 1 or month > 12 or day < 1 or day > 31 or year < 2000 or year > 2100 then return false end
    local stamp = time({year = year, month = month, day = day, hour = 0})

    return endOfDay and stamp + 86400 - 1 or stamp
end

function Log:UpdateRange()
    if not self.from or not self.to then return end
    local from, to = self:ParseDate(self.from:GetText()), self:ParseDate(self.to:GetText(), true)
    for box, value in pairs({[self.from] = from, [self.to] = to}) do
        if value == false then box:SetTextColor(1, 0.3, 0.3) else box:SetTextColor(Theme:GetColor("text")) end
    end
    self.rangeFrom, self.rangeTo = from or nil, to or nil
    self:Refresh()
end

function Log:CreateDateBox(content, label)
    local text = Theme:Text(content, 12, "muted")
    Theme:SetTrans(text, label)
    local box = Theme:FlatNative(CreateFrame("EditBox", nil, content, "InputBoxTemplate"))
    box:SetSize(92, 24)
    box:SetAutoFocus(false)
    box:SetMaxLetters(10)
    box:SetScript("OnTextChanged", function() self:UpdateRange() end)
    box:SetScript("OnEnterPressed", function(sel) sel:ClearFocus() end)
    box:SetScript("OnEscapePressed", function(sel) sel:SetText("") sel:ClearFocus() end)
    text:SetPoint("RIGHT", box, "LEFT", -8, 0)

    return box, text
end

function Log:OwnName()
    local name = Sync:GetOwnName()
    if type(name) == "string" and name ~= "" then return name end

    return Groups:Self()
end

function Log:IsHidden(filter)
    local hidden = GuildHelper:GetConfig("LOGHIDDEN", {})

    return hidden[filter] == true
end

function Log:ToggleFilter(filter)
    local hidden = GuildHelper:GetConfig("LOGHIDDEN", {})
    hidden[filter] = not hidden[filter] or nil
    self:Refresh()
end

function Log:FindLegacyAchievement()
    if not GuildHelper:IsForever() or type(GetCategoryList) ~= "function" or type(GetCategoryNumAchievements) ~= "function" then return nil end
    local okList, categories = pcall(GetCategoryList)
    if not okList or type(categories) ~= "table" then return nil end
    local found = {}
    for _, category in ipairs(categories) do
        local okCount, count = pcall(GetCategoryNumAchievements, category, true)
        for index = 1, okCount and tonumber(count) or 0 do
            local ok, id = pcall(GetAchievementInfo, category, index)
            if ok and type(id) == "number" and self:GetLegacyPoints(id) then tinsert(found, id) end
        end
    end
    if #found == 0 then return nil end

    return found[random(1, #found)]
end

function Log:RandomGuildMember()
    local total = GetNumGuildMembers and GetNumGuildMembers() or 0
    for _ = 1, 10 do
        local name, _, _, level, _, _, _, _, _, _, classFile = GetGuildRosterInfo(random(1, max(1, total)))
        if name and GuildHelper:CanAccessValues(name, level) and not Groups:IsSelfName(name) then return name, classFile end
    end
end

function Log:AddTestEntries()
    local name = self:OwnName()
    if not name then return end
    local _, classFile = UnitClass("player")
    local rank = GetGuildInfo and select(2, GetGuildInfo("player")) or "?"
    local now = self:Now()
    local samples = {
        {kind = "level", value = self:GetLevelList()[1]},
        {kind = "level", value = self:GetLevelList()[#self:GetLevelList()]},
        {kind = "join"},
        {kind = "promote", rank = rank},
        {kind = "demote", rank = rank},
        {kind = "profession", value = 164},
        {kind = "legacy", value = self:FindLegacyAchievement() or self.TESTACHIEVEMENT},
        {kind = "leave"}
    }
    local zone = GetRealZoneText and GetRealZoneText() or "?"
    self.testPress = (self.testPress or 0) + 1
    local press = self.testPress
    for _, kind in ipairs({"dungeon", "raid"}) do
        tinsert(samples, {kind = kind, value = press, instanceName = zone})
        for _ = 1, kind == "raid" and 4 or 2 do
            local member, memberClass = self:RandomGuildMember()
            if member then tinsert(samples, {kind = kind, value = press, instanceName = zone, member = member, memberClass = memberClass}) end
        end
    end
    for index, sample in ipairs(samples) do
        self.testSerial = (self.testSerial or 0) + 1
        local sampleName = sample.member or name
        sample.name, sample.class, sample.time, sample.exact = Groups:Name(sampleName) or sampleName, sample.memberClass or classFile, now, index % 2 == 1 or nil
        sample.display, sample.full = strsplit("-", sampleName), sampleName
        sample.order = self.testSerial
        sample.value = sample.value or now
        tinsert(self.testEntries, sample)
    end
    self:Refresh()
end

function Log:FormatName(entry, plain)
    local short = entry.display or strsplit("-", entry.name)
    local color = Theme:GetClassColor(entry.class)
    if not plain then short = format("|Hplayer:%s|h[%s]|h", entry.full or entry.display or entry.name, short) end
    if color then short = format("|cff%02x%02x%02x%s|r", color.r * 255, color.g * 255, color.b * 255, short) end

    return short
end

function Log:FormatEntry(entry)
    local definition = self.types[entry.kind]
    local view = {}
    for field, data in pairs(entry) do view[field] = data end
    if entry.members and #entry.members > 1 then
        view.count = #entry.members
        view.short = "|cffffd100|Hghlog:players|h[" .. format(GuildHelper:Trans("LID_LOGPLAYERS"), view.count) .. "]|h|r"
    else
        view.short = self:FormatName(entry.members and entry.members[1] or entry)
    end

    return definition.text(view)
end

function Log:ShowPlayers(owner, entry)
    if not entry or not entry.members then return end
    GameTooltip:SetOwner(owner, "ANCHOR_CURSOR")
    GameTooltip:AddLine(format(GuildHelper:Trans("LID_LOGPLAYERS"), #entry.members))
    local names = {}
    for _, member in ipairs(entry.members) do tinsert(names, {sort = strlower(member.display or member.name), text = self:FormatName(member, true)}) end
    table.sort(names, function(a, b) return a.sort < b.sort end)
    for _, name in ipairs(names) do GameTooltip:AddLine(name.text) end
    GameTooltip:Show()
end

function Log:FindMember(name)
    local Members = GuildHelper.Members
    local key = Groups:Name(name)
    if not key then return nil end
    if #Members.list == 0 then Members:Scan() end
    for _, member in ipairs(Members.list) do
        if Groups:Name(member.name) == key then return member end
    end
end

function Log:EnableLinks(line)
    if not line or line.logLinks or not line.SetHyperlinksEnabled then return end
    line.logLinks = true
    line:SetHyperlinksEnabled(true)
    line:SetScript("OnHyperlinkClick", function(sel, link, text, button)
        if strsub(link, 1, 6) == "ghlog:" then return end
        local player = link:match("^player:(.+)$")
        if not player then
            if SetItemRef then SetItemRef(link, text, button) end
            return
        end
        local member = self:FindMember(player)
        if button == "RightButton" then
            if member then GuildHelper.Members:OpenPlayerMenu(member, sel) end
        elseif member then
            GuildHelper.Members:Whisper(member)
        end
    end)
    line:SetScript("OnHyperlinkEnter", function(sel, link)
        if strsub(link, 1, 6) == "ghlog:" then
            self:ShowPlayers(sel, sel.logEntry)
            return
        end
        if strsub(link, 1, 12) ~= "achievement:" then return end
        GameTooltip:SetOwner(sel, "ANCHOR_CURSOR")
        pcall(GameTooltip.SetHyperlink, GameTooltip, link)
        GameTooltip:Show()
    end)
    line:SetScript("OnHyperlinkLeave", function() GameTooltip:Hide() end)
end

function Log:Refresh()
    local card = self.card
    if not card or not card:IsVisible() then return end
    for key, pill in pairs(self.filterPills) do
        GuildHelper.Members:SetPillActive(pill, not self:IsHidden(key))
    end
    local entries = self:GetEntries()
    for index, entry in ipairs(entries) do
        local stamp = date("%d.%m.%Y %H:%M", entry.time)
        Dashboard:SetLine(card, index, self:FormatEntry(entry), entry.exact and stamp or ("~" .. stamp))
        self:EnableLinks(card.lines[index])
        card.lines[index].logEntry = entry
    end
    Dashboard:FinishList(card, #entries)
    self.empty:SetShown(#entries == 0)
end

function Log:Build(content)
    local Window = GuildHelper.Window
    local title = Window:CreatePageTitle(content, "LID_GUILDLOG")
    self.filterPills = {}
    local previous
    for _, filter in ipairs(self.FILTERS) do
        if not filter.available or filter.available() then
            local key = filter.key
            local pill = GuildHelper.Members:CreatePill(content, GuildHelper:Trans(filter.label))
            if previous then
                pill:SetPoint("LEFT", previous, "RIGHT", 8, 0)
            else
                pill:SetPoint("TOPLEFT", content, "TOPLEFT", Window.PADDING, -66)
            end
            pill:SetScript("OnClick", function() self:ToggleFilter(key) end)
            pill.label = filter.label
            self.filterPills[key] = pill
            previous = pill
        end
    end
    local toLabel
    self.to, toLabel = self:CreateDateBox(content, "LID_LOGTO")
    self.to:SetPoint("TOPRIGHT", content, "TOPRIGHT", -Window.MARGIN, -68)
    self.from = self:CreateDateBox(content, "LID_LOGFROM")
    self.from:SetPoint("RIGHT", toLabel, "LEFT", -14, 0)
    self.dateHint = Theme:Text(content, 11, "muted")
    self.dateHint:SetPoint("TOPRIGHT", self.to, "BOTTOMRIGHT", 0, -2)
    Theme:SetTrans(self.dateHint, "LID_LOGDATEHINT")
    local card = Dashboard:CreateCard(content, "LID_LOGENTRIES")
    card:SetPoint("TOPLEFT", content, "TOPLEFT", Window.PADDING, -110)
    card:SetPoint("BOTTOMRIGHT", content, "BOTTOMRIGHT", -Window.MARGIN, 16)
    Dashboard:CreateList(card)
    card.scrollPage = function() end
    self.card = card
    self.empty = Theme:Text(card, 13, "muted")
    self.empty:SetPoint("TOPLEFT", card, "TOPLEFT", 16, -40)
    Theme:SetTrans(self.empty, "LID_LOGEMPTY")
    self.hint = Theme:Text(content, 11, "muted")
    self.hint:SetPoint("LEFT", title, "RIGHT", 16, -1)
    Theme:SetTrans(self.hint, "LID_LOGHINT")
    self.test = GuildHelper.Members:CreateButton(content, "LID_LOGTEST")
    self.test:SetPoint("TOPRIGHT", content, "TOPRIGHT", -Window.MARGIN, -26)
    self.test:SetWidth(max(120, self.test.text:GetStringWidth() + 32))
    self.test:SetScript("OnClick", function() self:AddTestEntries() end)
    content.OnPageShow = function()
        self.test:SetShown(GuildHelper.FeedbackShare ~= nil and GuildHelper.FeedbackShare:IsDeveloper())
        self:ScanRoster()
        self:Refresh()
    end
end

function Log:DebugValue(value)
    if not GuildHelper:CanAccessValue(value) then return "<geheim>" end

    return tostring(value)
end

function Log:Debug(...)
    if not self.debug then return end
    local parts = {}
    for index = 1, select("#", ...) do parts[index] = self:DebugValue(select(index, ...)) end
    print("|cff33ff99[GuildHelper Log]|r " .. table.concat(parts, " "))
end

function Log:SetDebug(enabled)
    self.debug = enabled and true or nil
    GuildHelper:SetConfig("LOGDEBUG", self.debug == true)
    self.debugEvents = self.debugEvents or CreateFrame("Frame")
    for _, event in ipairs({"ENCOUNTER_START", "ENCOUNTER_END", "BOSS_KILL", "UNIT_DIED", "PARTY_KILL"}) do
        if self.debug then pcall(self.debugEvents.RegisterEvent, self.debugEvents, event) else pcall(self.debugEvents.UnregisterEvent, self.debugEvents, event) end
    end
    self.debugEvents:SetScript("OnEvent", function(_, event, ...)
        local kind, instanceID, instanceName = self:GetInstance()
        self:Debug(event, ...)
        self:Debug("  Instanz:", instanceName or "-", instanceID or "-", kind or "keine Dungeon-/Raid-Instanz")
    end)
    print("|cff33ff99[GuildHelper Log]|r Debug " .. (self.debug and "an" or "aus"))
end

GuildHelper:AddSlash("ghlogdebug", function()
    if not GuildHelper.FeedbackShare or not GuildHelper.FeedbackShare:IsDeveloper() then return end
    Log:SetDebug(not Log.debug)
end)

Log.events = CreateFrame("Frame")
Log.events:RegisterEvent("GUILD_ROSTER_UPDATE")
for _, event in ipairs({"PLAYER_LEVEL_UP", "ACHIEVEMENT_EARNED", "CHAT_MSG_GUILD_ACHIEVEMENT", "ENCOUNTER_END"}) do
    if not C_EventUtils or not C_EventUtils.IsEventValid or C_EventUtils.IsEventValid(event) then Log.events:RegisterEvent(event) end
end
if Log.FINALNPCLAYERS[GuildHelper:GetWoWBuild()] and CombatLogGetCurrentEventInfo then
    pcall(Log.events.RegisterEvent, Log.events, "COMBAT_LOG_EVENT_UNFILTERED")
end
Log.events:RegisterEvent("PLAYER_LOGIN")
Log.events:SetScript("OnEvent", function(_, event, arg1, arg2, _, _, arg5)
    if event == "PLAYER_LOGIN" then
        if GuildHelper:GetConfig("LOGDEBUG", false) == true and GuildHelper.FeedbackShare and GuildHelper.FeedbackShare:IsDeveloper() then Log:SetDebug(true) end
    elseif event == "COMBAT_LOG_EVENT_UNFILTERED" then
        local _, subEvent, _, _, _, _, _, destGUID = CombatLogGetCurrentEventInfo()
        if subEvent == "UNIT_DIED" then Log:OnUnitDied(destGUID) end
    elseif event == "ENCOUNTER_END" then
        Log:OnEncounterEnd(arg1, arg2, arg5)
    elseif event == "PLAYER_LEVEL_UP" then
        Log:OnLevelUp(arg1)
    elseif event == "ACHIEVEMENT_EARNED" then
        Log:OnAchievement(arg1)
    elseif event == "CHAT_MSG_GUILD_ACHIEVEMENT" then
        Log:OnGuildAchievement(arg1, arg2)
    elseif not Log.scanQueued then
        Log.scanQueued = true
        C_Timer.After(Log.SCANDELAY, function()
            Log.scanQueued = nil
            Log:ScanRoster()
        end)
    end
end)
hooksecurefunc(Sync, "Store", function(_, shortName, _, professions, own) Log:CheckProfessions(shortName, professions, own) end)
GuildHelper.Window:SetPageBuilder("log", function(content) Log:Build(content) end)
GuildHelper.Window:OnRebuild(function() Log.card = nil end)
GuildHelper.Theme:OnRefresh(function() Log:Refresh() end)
