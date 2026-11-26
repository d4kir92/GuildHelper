local _, GuildHelper = ...
local Sync = {}
GuildHelper.Sync = Sync
Sync.PREFIX = "GuildHelper"
Sync.SEND_THROTTLE = 15
Sync.ANSWER_THROTTLE = 120
Sync.lastSend = 0
Sync.listeners = {}
Sync.BURST = 1
Sync.MAXTRIES = 20
Sync.tokens = Sync.BURST
Sync.queue = {}
Sync.pump = CreateFrame("Frame")
Sync.pump:SetScript("OnUpdate", function(_, elapsed) Sync:Pump(elapsed) end)
Sync.GUILDTABLES = {"MEMBERDATA", "FEEDBACK", "ORDERS", "EVENTS", "GROUPS", "BRIDGE", "BRIDGEDATA", "MAINS", "ONLINEHISTORY"}
Sync.CHARTABLES = {"FEEDBACKUNREAD", "GROUPSVIEWED", "BANK"}
Sync.migrated = {}
function Sync:GetGuildKey()
    if not IsInGuild() then return nil end
    local guild = GetGuildInfo("player")
    if guild == nil then return nil end
    local realm = GetRealmName and GetRealmName()
    if not GuildHelper:CanAccessValue(realm) or type(realm) ~= "string" then realm = "" end
    if IsLoggedIn and not IsLoggedIn() then return guild .. "-" .. realm end
    realm = self:GetGuildRealm(guild, realm)
    if realm ~= "" and not self.migrated[guild] then
        self.migrated[guild] = true
        self:MigrateGuildKey(guild .. "-", guild .. "-" .. realm)
    end

    return guild .. "-" .. realm
end

function Sync:GetGuildRealm(guild, realm)
    GHTABPC = GHTABPC or {}
    if realm ~= "" then
        GHTABPC.REALM = realm

        return realm
    end

    local known = GHTABPC.REALM or self:FindGuildRealm(guild)
    if known then GHTABPC.REALM = known end

    return known or ""
end

function Sync:FindGuildRealm(guild)
    local prefix = guild .. "-"
    local counts = {}
    for _, name in ipairs(self.GUILDTABLES) do
        for key, value in pairs(GHTAB and GHTAB[name] or {}) do
            if type(key) == "string" and #key > #prefix and strsub(key, 1, #prefix) == prefix then
                local realm = strsub(key, #prefix + 1)
                local size = 1
                if type(value) == "table" then
                    for _ in pairs(value) do
                        size = size + 1
                    end
                end

                counts[realm] = (counts[realm] or 0) + size
            end
        end
    end

    local best, bestCount = nil, 0
    for realm, count in pairs(counts) do
        if count > bestCount then best, bestCount = realm, count end
    end

    return best
end

function Sync:MergeSaved(target, source)
    if type(target) ~= "table" or type(source) ~= "table" or source[1] ~= nil or target[1] ~= nil then return source end
    for key, value in pairs(source) do
        target[key] = self:MergeSaved(target[key], value)
    end

    return target
end

function Sync:MigrateGuildKey(old, new)
    for _, list in ipairs({{GHTAB, self.GUILDTABLES}, {GHTABPC, self.CHARTABLES}}) do
        for _, name in ipairs(list[2]) do
            local tab = list[1] and list[1][name]
            if type(tab) == "table" and tab[old] ~= nil then
                tab[new] = self:MergeSaved(tab[new], tab[old])
                tab[old] = nil
            end
        end
    end
end

function Sync:GetStore()
    local key = self:GetGuildKey()
    if key == nil then return nil end
    GHTAB = GHTAB or {}
    GHTAB.MEMBERDATA = GHTAB.MEMBERDATA or {}
    GHTAB.MEMBERDATA[key] = GHTAB.MEMBERDATA[key] or {}

    return GHTAB.MEMBERDATA[key]
end

function Sync:GetData(shortName)
    local store = self:GetStore()
    if store == nil or shortName == nil then return nil end

    return store[self:GetKey(shortName)]
end

function Sync:GetKey(name)
    local shortName = strsplit("-", name)

    return strlower(shortName)
end

function Sync:GetOwnName()
    local _, ownName = GuildHelper:GetPlayerCharacterKey()
    if not GuildHelper:IsForever() then return ownName or UnitName("player") end

    local name = UnitName("player")
    if GuildHelper:CanAccessValue(name) and name and self:GetKey(name):find("%s") then return ownName or name end

    local guid = UnitGUID("player")
    if not GuildHelper:CanAccessValue(guid) or not guid then return ownName end
    for index = 1, GetNumGuildMembers() or 0 do
        local memberName, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, memberGUID = GetGuildRosterInfo(index)
        if GuildHelper:CanAccessValues(memberGUID, memberName) and memberGUID == guid and memberName then return memberName end
    end

    return ownName
end

function Sync:OnUpdate(callback)
    tinsert(self.listeners, callback)
end

function Sync:Notify()
    for _, callback in ipairs(self.listeners) do
        callback()
    end
end

function Sync:GetOwnItemLevel()
    if GetAverageItemLevel then
        local _, equipped = GetAverageItemLevel()
        if equipped and equipped > 0 then return floor(equipped) end
    end

    local value = GuildHelper:GetInspectILvl("player")
    if value and value > 0 then return floor(value) end

    return nil
end

Sync.professionNames = {
    [129] = {enUS = "First Aid", deDE = "Erste Hilfe"},
    [164] = {enUS = "Blacksmithing", deDE = "Schmiedekunst"},
    [165] = {enUS = "Leatherworking", deDE = "Lederverarbeitung"},
    [171] = {enUS = "Alchemy", deDE = "Alchimie"},
    [182] = {enUS = "Herbalism", deDE = "Kräuterkunde"},
    [185] = {enUS = "Cooking", deDE = "Kochkunst"},
    [186] = {enUS = "Mining", deDE = "Bergbau"},
    [197] = {enUS = "Tailoring", deDE = "Schneiderei"},
    [202] = {enUS = "Engineering", deDE = "Ingenieurskunst"},
    [333] = {enUS = "Enchanting", deDE = "Verzauberkunst"},
    [356] = {enUS = "Fishing", deDE = "Angeln"},
    [393] = {enUS = "Skinning", deDE = "Kürschnerei"},
    [755] = {enUS = "Jewelcrafting", deDE = "Juwelierskunst"},
    [773] = {enUS = "Inscription", deDE = "Inschriftenkunde"},
    [794] = {enUS = "Archaeology", deDE = "Archäologie"},
    [633] = {enUS = "Lockpicking", deDE = "Schlossknacken"},
    [3012] = {enUS = "Comprehension", deDE = "Verständnis"},
}

Sync.classProfessions = {[633] = 136058, [3012] = 135933}

Sync.primaryProfessionIcons = {
    [164] = 136241,
    [165] = 133611,
    [171] = 136240,
    [182] = 136246,
    [186] = 136248,
    [197] = 136249,
    [202] = 136243,
    [333] = 136244,
    [393] = 134366,
    [755] = 134071,
    [773] = 237171
}

function Sync:GetProfessionName(id, fallback)
    if id and C_TradeSkillUI then
        local name
        if C_TradeSkillUI.GetTradeSkillDisplayName then
            name = C_TradeSkillUI.GetTradeSkillDisplayName(id)
        end

        if (not name or name == "") and C_TradeSkillUI.GetProfessionInfoBySkillLineID then
            local info = C_TradeSkillUI.GetProfessionInfoBySkillLineID(id)
            name = info and info.professionName
        end

        if name and name ~= "" then return name end
    end

    local names = self.professionNames[id]

    return names and names[GetLocale()] or fallback
end

function Sync:GetProfessionID(name, id)
    if id and id > 0 then return id end
    for skillLineID, names in pairs(self.professionNames) do
        if name == names.enUS or name == names.deDE then return skillLineID end
    end

    for skillLineID in pairs(self.professionNames) do
        if name == self:GetProfessionName(skillLineID) then return skillLineID end
    end
end

function Sync:GetPrimaryProfessions(data)
    local professions, seen = {}, {}
    for _, entry in ipairs(data and data.professions or {}) do
        local id = self:GetProfessionID(entry[1], entry[4])
        local icon = self.primaryProfessionIcons[id]
        if icon and not seen[id] then
            seen[id] = true
            tinsert(professions, {icon = icon, sortName = strlower(self:GetProfessionName(id, entry[1]))})
        end
    end

    table.sort(professions, function(a, b) return a.sortName < b.sortName end)

    return professions
end

Sync.gatheringProfessions = {[182] = true, [186] = true, [393] = true}

function Sync:IsCraftingProfession(id)
    return id ~= nil and self.primaryProfessionIcons[id] ~= nil and not self.gatheringProfessions[id]
end

function Sync:GroupProfessions(entries, getID)
    local crafting, gathering, secondary, class = {}, {}, {}, {}
    for _, entry in ipairs(entries) do
        local id = getID(entry)
        if self.gatheringProfessions[id] then
            tinsert(gathering, entry)
        elseif id == 129 or id == 185 or id == 356 or id == 794 then
            tinsert(secondary, entry)
        elseif self.classProfessions[id] then
            tinsert(class, entry)
        else
            tinsert(crafting, entry)
        end
    end

    local splits = {}
    for _, group in ipairs({gathering, secondary, class}) do
        if #group > 0 then
            if #crafting > 0 then tinsert(splits, #crafting + 1) end
            for _, entry in ipairs(group) do tinsert(crafting, entry) end
        end
    end
    return crafting, splits
end

function Sync:GetOwnProfessions()
    local list, seen = {}, {}
    local professionAPI = GetProfessions and GetProfessionInfo
    if professionAPI then
        local indices = {GetProfessions()}
        for i = 1, 6 do
            local index = indices[i]
            if index then
                local name, _, rank, maxRank, _, _, skillLineID = GetProfessionInfo(index)
                if name then
                    local id = self:GetProfessionID(name, skillLineID)
                    if id then seen[id] = true end
                    tinsert(list, {name, rank or 0, maxRank or 0, id})
                end
            end
        end
    end

    if GetNumSkillLines and GetSkillLineInfo then
        local header = nil
        for i = 1, GetNumSkillLines() do
            local name, isHeader, _, rank, _, _, maxRank = GetSkillLineInfo(i)
            if isHeader then
                header = name
            elseif name then
                local id = self:GetProfessionID(name)
                local wanted = (id and self.classProfessions[id]) or
                    (not professionAPI and (header == TRADE_SKILLS or (SECONDARY_SKILLS and header == SECONDARY_SKILLS)))
                if wanted and not (id and seen[id]) then
                    if id then seen[id] = true end
                    tinsert(list, {name, rank or 0, maxRank or 0, id})
                end
            end
        end
    end

    if C_TradeSkillUI and C_TradeSkillUI.GetProfessionInfoBySkillLineID then
        for id in pairs(self.classProfessions) do
            if not seen[id] then
                local ok, info = pcall(C_TradeSkillUI.GetProfessionInfoBySkillLineID, id)
                if ok and type(info) == "table" and (info.skillLevel or 0) > 0 then
                    seen[id] = true
                    tinsert(list, {self:GetProfessionName(id, info.professionName), info.skillLevel, info.maxSkillLevel or 0, id})
                end
            end
        end
    end

    return list
end

function Sync:BuildInfo()
    local parts = {"I", tostring(self:GetOwnItemLevel() or 0)}
    for _, prof in ipairs(self:GetOwnProfessions()) do
        tinsert(parts, format("%s;%d;%d;%s", prof[1], prof[2], prof[3], tostring(prof[4] or "")))
    end

    return table.concat(parts, "~")
end

function Sync:GetEntry(shortName)
    local store = self:GetStore()
    if store == nil then return nil end
    local key = self:GetKey(shortName)
    store[key] = store[key] or {}
    store[key].time = time()

    return store[key]
end

function Sync:Store(shortName, ilvl, professions, own)
    local entry = self:GetEntry(shortName)
    if entry == nil then return end
    entry.ilvl = ilvl and ilvl > 0 and ilvl or nil
    entry.professions = professions
    if GuildHelper.Recipes then GuildHelper.Recipes:Prune(entry, professions, own) end
    self:Notify()
end

function Sync:Trace(...)
    if self.debug then print("[GuildHelper Sync]", ...) end
end

function Sync:BuildSpecs()
    local parts = {"S", GuildHelper.Specs:GetMainName() or ""}
    for _, entry in ipairs(GuildHelper.Specs:GetOwn()) do
        tinsert(parts, format("%s;%s;%s", entry.role or "", entry.spec or "", tostring(entry.icon or "")))
    end

    return table.concat(parts, "~")
end

function Sync:ParseSpecs(shortName, message)
    local entry = self:GetEntry(shortName)
    if entry == nil then return end
    local parts = {strsplit("~", message)}
    local specs = {}
    for slot = 1, #GuildHelper.Specs.SLOTS do
        local role, spec, icon = strsplit(";", parts[slot + 2] or "")
        specs[slot] = {
            role = role or "",
            spec = spec or "",
            icon = tonumber(icon) or (icon ~= "" and icon or nil)
        }
    end

    entry.main = parts[2] or ""
    self:Trace("S", shortName, "Main:", entry.main ~= "" and entry.main or "(leer)")
    entry.specs = specs
    if parts[#GuildHelper.Specs.SLOTS + 3] ~= nil then entry.twitch = parts[#GuildHelper.Specs.SLOTS + 3] end
    self:Notify()
end

function Sync:SendSpecs()
    GuildHelper.Specs:MigrateMain()
    local message = self:BuildSpecs()
    local name = self:GetOwnName()
    if name then self:ParseSpecs(name, message) end
    local entry = name and self:GetEntry(name)
    if entry then entry.twitch = GuildHelper.Specs:GetTwitch() end
    self:Notify()
    self:Send(message, "S")
    self:Send("T~" .. GuildHelper.Specs:GetTwitch(), "T")
    local main = GuildHelper.Specs:GetMainName()
    self:Trace("Gespeicherter Main:", main or "(leer)", "Gilde:", self:GetGuildKey() or "(keine)")
    self:Send("M~" .. (main or ""), "M")
end

function Sync:Parse(shortName, message, own)
    local parts = {strsplit("~", message)}
    local professions = {}
    for i = 3, #parts do
        local name, rank, maxRank, skillLineID = strsplit(";", parts[i])
        if name and name ~= "" then
            tinsert(professions, {name, tonumber(rank) or 0, tonumber(maxRank) or 0, tonumber(skillLineID)})
        end
    end

    self:Store(shortName, tonumber(parts[2]), professions, own)
end

function Sync:Send(message, key, prefix, guild, target)
    if (target == nil and not IsInGuild()) or type(message) ~= "string" or #message > 255 then return end
    for _, item in ipairs(self.queue) do
        if item.guild == guild and item.target == target and item.prefix == (prefix or self.PREFIX) and ((key and item.key == key) or item.message == message) then
            item.message = message
            item.tries = 0

            return
        end
    end

    tinsert(self.queue, {
        message = message,
        prefix = prefix or self.PREFIX,
        key = key,
        guild = guild,
        target = target,
        tries = 0,
        bankRank = strsub(message, 1, 3) == "BK~" and GuildHelper.Bank and GuildHelper.Bank.rank or nil
    })

    self:Pump(0)
end

function Sync:Transmit(message, prefix, target)
    local ok, result = false, nil
    local channel = type(target) == "string" and "WHISPER" or (target and "CHANNEL" or "GUILD")
    if C_ChatInfo and C_ChatInfo.SendAddonMessage then
        ok, result = pcall(C_ChatInfo.SendAddonMessage, prefix or self.PREFIX, message, channel, target)
    elseif SendAddonMessage then
        ok, result = pcall(SendAddonMessage, prefix or self.PREFIX, message, channel, target)
    end

    if (prefix or self.PREFIX) == self.PREFIX and strsub(message, 1, 2) == "M~" then
        self:Trace("Versand:", message, ok and "API-Ergebnis:" or "API-Fehler:", tostring(result))
    end
    if self.debug then
        local command, id = message:match("^F~([AW])~[^~]+~([^~]+)")
        if command then self:Trace("Gruppenanmeldung Versand:", command, id, ok and "API-Ergebnis:" or "API-Fehler:", ok and tostring(result) or "") end
    end
    if not ok or result == false then return false end
    local codes = Enum and Enum.SendAddonMessageResult
    if type(result) == "number" and codes then return result == codes.Success end

    return true
end

function Sync:Pump(elapsed)
    self.tokens = min(self.BURST, self.tokens + elapsed)
    if #self.queue == 0 then return end
    if not IsInGuild() then
        for index = #self.queue, 1, -1 do
            if self.queue[index].target == nil then tremove(self.queue, index) end
        end

        if #self.queue == 0 then return end
    end

    while self.tokens >= 1 and #self.queue > 0 do
        local item = self.queue[1]
        if item.bankRank and GuildHelper.Bank and not GuildHelper.Bank:CanTransmit(item.message, item.target, item.bankRank) then
            tremove(self.queue, 1)
        elseif item.guild and item.guild ~= self:GetGuildKey() then
            tremove(self.queue, 1)
        elseif not self:Transmit(item.message, item.prefix, item.target) then
            item.tries = item.tries + 1
            if item.tries >= self.MAXTRIES then tremove(self.queue, 1) end
            self.tokens = 0

            return
        else
            tremove(self.queue, 1)
            self.tokens = self.tokens - 1
        end
    end
end

function Sync:SendAvatar()
    local sex = UnitSex("player")
    if not GuildHelper:CanAccessValues(sex) or (sex ~= 2 and sex ~= 3) then return end
    local _, race = UnitRace("player")
    if GuildHelper:CanAccessValues(race) and type(race) == "string" and race:match("^[A-Za-z]+$") and #race <= 32 then
        race = race:lower()
        self:Trace("Volksavatar senden:", race, sex)
        self:Send(format("R~%s~%d", race, sex), "R")
    else
        self:Send(format("R~%d", sex), "R")
    end
end

function Sync:SendInfo(force)
    if not IsInGuild() then return end
    local now = GetTime()
    if not force and now - self.lastSend < self.SEND_THROTTLE then
        self:ScheduleInfo(self.SEND_THROTTLE - (now - self.lastSend) + 1)

        return
    end

    self.lastSend = now
    local message = self:BuildInfo()
    local name = self:GetOwnName()
    if name then self:Parse(name, message, true) end
    self:Send(message, "I")
    if name and GuildHelper.Recipes then GuildHelper.Recipes:ReplayRemovals(self:GetData(name)) end
    self:SendSpecs()
    self:SendAvatar()
    if GuildHelper.Layer then GuildHelper.Layer:Send(true) end
    local version = GuildHelper:GetVersion()
    if type(version) == "string" and version ~= "" then self:Send("V~" .. version, "V") end
    if GuildHelper.Bridge then GuildHelper.Bridge:SendMember() end
end

function Sync:ScheduleInfo(delay)
    if self.pending then return end
    self.pending = true
    C_Timer.After(delay, function()
        Sync.pending = false
        Sync:SendInfo()
    end)
end

function Sync:OnMessage(message, channel, sender)
    if (channel ~= "GUILD" and channel ~= "WHISPER") or type(message) ~= "string" or type(sender) ~= "string" then return end
    if not GuildHelper:CanAccessValues(message, sender) then
        self:Trace("Gildennachricht vom Client gesperrt")

        return
    end
    if channel == "GUILD" and GuildHelper.History then GuildHelper.History:Heard(sender) end
    if strsub(message, 1, 3) == "BK~" and GuildHelper.Bank then
        GuildHelper.Bank:OnMessage(message, channel, sender)
        return
    end
    if channel ~= "GUILD" then return end
    if strsub(message, 1, 3) == "EV~" and GuildHelper.Events then
        GuildHelper.Events:OnMessage(message, sender)

        return
    end
    if strsub(message, 1, 3) == "GL~" and GuildHelper.Log then
        GuildHelper.Log:OnMessage(message, sender)

        return
    end
    if strsub(message, 1, 3) == "BR~" and GuildHelper.Bridge then
        GuildHelper.Bridge:OnGuildMessage(message, sender)

        return
    end
    if strsub(message, 1, 3) == "GR~" and GuildHelper.Bridge then
        GuildHelper.Bridge:OnLiveRepeatMessage(message, sender)

        return
    end
    if strsub(message, 1, 2) == "F~" and GuildHelper.Groups then
        GuildHelper.Groups:OnMessage(message, sender)

        return
    end
    if strsub(message, 1, 1) == "O" and GuildHelper.Orders then
        GuildHelper.Orders:OnMessage(message, sender)

        return
    end
    local shortName = strsplit("-", sender)
    local senderKey = self:GetKey(shortName)
    local playerKey = self:GetKey(UnitName("player") or "")
    if senderKey:match("^%S+") == playerKey:match("^%S+") then
        local ownName = self:GetOwnName()
        if ownName and senderKey == self:GetKey(ownName) then return end
    end
    local kind = strsub(message, 1, 1)
    if kind == "I" then
        self:Parse(shortName, message)
    elseif kind == "S" then
        self:ParseSpecs(shortName, message)
    elseif kind == "T" then
        local entry = self:GetEntry(shortName)
        if entry then
            entry.twitch = strsub(message, 3)
            self:Notify()
        end
    elseif kind == "M" then
        local entry = self:GetEntry(shortName)
        if entry then
            entry.main = strsub(message, 3)
            self:Trace("M empfangen:", shortName, "Main:", entry.main ~= "" and entry.main or "(leer)")
            self:Notify()
        end
    elseif kind == "R" then
        if #message > 36 then return end
        local race, sex = message:match("^R~([a-z]+)~([23])$")
        sex = sex or message:match("^R~([23])$")
        if not sex then return end
        local entry = self:GetEntry(shortName)
        local gender = sex == "2" and "male" or "female"
        self:Trace("Volksavatar empfangen:", shortName, race, gender)
        if entry and (entry.portraitGender ~= gender or (race and entry.portraitRace ~= race)) then
            entry.portraitRace = race or entry.portraitRace
            entry.portraitGender = gender
            self:Notify()
        end
    elseif kind == "V" then
        local version = message:match("^V~([%w%.%-]+)$")
        local entry = version and #version <= 24 and self:GetEntry(shortName)
        if entry and entry.version ~= version then
            entry.version = version
            self:Notify()
        end
    elseif kind == "L" and GuildHelper.Layer then
        GuildHelper.Layer:OnMessage(shortName, message)
    elseif kind == "H" and GuildHelper.History then
        GuildHelper.History:OnMessage(message, sender)
    elseif kind == "P" and GuildHelper.Recipes then
        GuildHelper.Recipes:OnMessage(message, shortName)
    elseif kind == "Q" then
        if GuildHelper.Bridge then GuildHelper.Bridge:OnQuery() end
        self:ScheduleInfo(max(0, self.ANSWER_THROTTLE - (GetTime() - self.lastSend)) + random(2, 12))
    end
end

function Sync:Init()
    GuildHelper:AddSlash("ghsyncdebug", function()
        Sync.debug = not Sync.debug
        print("[GuildHelper Sync]", Sync.debug and "Debug an" or "Debug aus")
        if Sync.debug then
            Sync:SendSpecs()
            Sync:SendAvatar()
            Sync:Send("Q")
        end
    end)

    if C_ChatInfo and C_ChatInfo.RegisterAddonMessagePrefix then
        C_ChatInfo.RegisterAddonMessagePrefix(self.PREFIX)
    elseif RegisterAddonMessagePrefix then
        RegisterAddonMessagePrefix(self.PREFIX)
    end

    local events = CreateFrame("Frame")
    events:RegisterEvent("CHAT_MSG_ADDON")
    events:RegisterEvent("PLAYER_EQUIPMENT_CHANGED")
    events:RegisterUnitEvent("UNIT_INVENTORY_CHANGED", "player")
    events:RegisterEvent("SKILL_LINES_CHANGED")
    events:RegisterEvent("PLAYER_GUILD_UPDATE")
    if GuildHelper:IsForever() then events:RegisterEvent("GUILD_ROSTER_UPDATE") end
    events:SetScript("OnEvent", function(_, event, prefix, message, channel, sender)
        if event == "CHAT_MSG_ADDON" then
            if prefix == Sync.PREFIX then Sync:OnMessage(message, channel, sender) end
        elseif event == "GUILD_ROSTER_UPDATE" then
            if GuildHelper.Specs:MigrateMain() then Sync:SendSpecs() end
        else
            if event == "SKILL_LINES_CHANGED" and GuildHelper.Recipes then
                local name = Sync:GetOwnName()
                local entry = name and Sync:GetData(name)
                if entry and entry.recipes and next(entry.recipes) and GuildHelper.Recipes:Prune(entry, Sync:GetOwnProfessions(), true) then
                    Sync:Notify()
                end
            end
            Sync:ScheduleInfo(5)
        end
    end)

    C_Timer.After(8, function()
        Sync:SendInfo(true)
        Sync:Send("Q")
    end)
end
