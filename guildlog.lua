local _, GuildHelper = ...
local Theme, Groups, Sync, Dashboard = GuildHelper.Theme, GuildHelper.Groups, GuildHelper.Sync, GuildHelper.Dashboard
local Log = {
    KEEP = 500,
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

function Log:Key(kind, name, value)
    return kind .. ":" .. name .. ":" .. tostring(value)
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
    local key = self:Key(kind, name, value)
    local entry = store.entries[key]
    if entry then
        if entry.exact and not exact then return false end
        if entry.exact == exact and entry.time <= stamp then return false end
        entry.time, entry.exact = stamp, exact
    else
        entry = {kind = kind, name = name, value = value, time = stamp, exact = exact}
        store.entries[key] = entry
    end
    if extra then
        for field, data in pairs(extra) do entry[field] = data end
    end
    self:Prune(store)
    self:Refresh()

    return true
end

function Log:Prune(store)
    local list = {}
    for key, entry in pairs(store.entries) do tinsert(list, {key = key, time = entry.time}) end
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

    return list
end

function Log:Send(kind, value, stamp)
    Sync:Send(table.concat({"GL", kind, value, stamp}, "~"), "log:" .. kind .. ":" .. value)
end

function Log:OnMessage(message, sender)
    if #message > 120 or Groups:IsSelfName(sender) then return end
    local kind, value, stamp = message:match("^GL~(%a+)~(%d+)~(%d+)$")
    local definition = kind and self.types[kind]
    if not definition or not definition.receive then return end
    value, stamp = tonumber(value), tonumber(stamp)
    local now = self:Now()
    if not value or not stamp or stamp > now + 300 or stamp < now - self.MAXAGE then return end
    definition.receive(self, sender, value, stamp)
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
        if id and Sync.primaryProfessionIcons[id] then
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

Log.FILTERS = {
    {key = "level", label = "LID_LOGFILTERLEVEL"},
    {key = "join", label = "LID_LOGFILTERJOIN"},
    {key = "leave", label = "LID_LOGFILTERLEAVE"},
    {key = "rank", label = "LID_LOGFILTERRANK"},
    {key = "profession", label = "LID_LOGFILTERPROF", available = function() return Log:GetProfessionCap() ~= nil end},
    {key = "legacy", label = "LID_LOGFILTERLEGACY", available = function() return GuildHelper:IsForever() end}
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
    for index, sample in ipairs(samples) do
        self.testSerial = (self.testSerial or 0) + 1
        sample.name, sample.class, sample.time, sample.exact = name, classFile, now, index % 2 == 1 or nil
        sample.display, sample.full = strsplit("-", name), name
        sample.order = self.testSerial
        sample.value = sample.value or now
        tinsert(self.testEntries, sample)
    end
    self:Refresh()
end

function Log:FormatEntry(entry)
    local definition = self.types[entry.kind]
    local short = entry.display or strsplit("-", entry.name)
    local color = Theme:GetClassColor(entry.class)
    local full = entry.full or entry.display or entry.name
    short = format("|Hplayer:%s|h[%s]|h", full, short)
    if color then short = format("|cff%02x%02x%02x%s|r", color.r * 255, color.g * 255, color.b * 255, short) end

    local view = {short = short}
    for field, data in pairs(entry) do view[field] = data end

    return definition.text(view)
end

function Log:EnableLinks(line)
    if not line or line.logLinks or not line.SetHyperlinksEnabled then return end
    line.logLinks = true
    line:SetHyperlinksEnabled(true)
    line:SetScript("OnHyperlinkClick", function(_, link, text, button)
        if SetItemRef then SetItemRef(link, text, button) end
    end)
    line:SetScript("OnHyperlinkEnter", function(sel, link)
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

Log.events = CreateFrame("Frame")
Log.events:RegisterEvent("GUILD_ROSTER_UPDATE")
for _, event in ipairs({"PLAYER_LEVEL_UP", "ACHIEVEMENT_EARNED", "CHAT_MSG_GUILD_ACHIEVEMENT"}) do
    if not C_EventUtils or not C_EventUtils.IsEventValid or C_EventUtils.IsEventValid(event) then Log.events:RegisterEvent(event) end
end
Log.events:SetScript("OnEvent", function(_, event, arg1, arg2)
    if event == "PLAYER_LEVEL_UP" then
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
