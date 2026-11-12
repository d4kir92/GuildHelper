local _, GuildHelper = ...
local Events = {
    roles = {TANK = "LID_ROLETANK", HEALER = "LID_ROLEHEALER", DAMAGER = "LID_ROLEDAMAGER"},
    statuses = {A = "LID_EVENT_ACCEPT", T = "LID_EVENT_TENTATIVE", D = "LID_EVENT_DECLINE"},
    pending = {},
    pendingDeletions = {},
    replay = {},
}
GuildHelper.Events = Events

local Sync, Groups, Feedback = GuildHelper.Sync, GuildHelper.Groups, GuildHelper.Feedback

function Events:Day(year, month, day)
    return time({year = year, month = month, day = day, hour = 12})
end

function Events:ParseDate(dayText, timeText)
    local year, month, day = dayText:match("^(%d%d%d%d)%-(%d%d)%-(%d%d)$")
    local hour, minute = timeText:match("^(%d%d?):(%d%d)$")
    year, month, day = tonumber(year), tonumber(month), tonumber(day)
    hour, minute = tonumber(hour), tonumber(minute)
    if not year or year < 2004 or year > 2099 or month < 1 or month > 12 or day < 1 or day > 31 then return end
    if not hour or hour > 23 or minute > 59 then return end
    local stamp = self:Day(year, month, day)
    if date("%Y-%m-%d", stamp) == dayText then return dayText .. format(" %02d:%02d", hour, minute) end
end

function Events:GetClock()
    if C_DateAndTime and C_DateAndTime.GetCurrentCalendarTime then
        local clock = C_DateAndTime.GetCurrentCalendarTime()
        if clock and clock.year and clock.month and clock.monthDay and clock.hour and clock.minute then
            return {year = clock.year, month = clock.month, day = clock.monthDay, hour = clock.hour, min = clock.minute, sec = 0}, true
        end
    end

    return date("*t"), false
end

function Events:Today()
    local clock = self:GetClock()
    return self:Day(clock.year, clock.month, clock.day)
end

function Events:PlannedClock(stamp)
    local clock, realmTime = self:GetClock()
    if not realmTime then return date("%Y-%m-%d %H:%M", stamp) end
    if C_DateAndTime.GetCalendarTimeFromEpoch then
        local now = C_DateAndTime.GetCalendarTimeFromEpoch(GetServerTime())
        if now and now.year == clock.year and now.month == clock.month and now.monthDay == clock.day and
            now.hour == clock.hour and now.minute == clock.min then
            local planned = C_DateAndTime.GetCalendarTimeFromEpoch(stamp)
            if planned then
                return format("%04d-%02d-%02d %02d:%02d", planned.year, planned.month, planned.monthDay, planned.hour, planned.minute)
            end
        end
    end
    local utc = date("!*t")
    utc.sec = 0
    local offset = floor((time(clock) - time(utc)) / 900 + 0.5) * 900

    return date("!%Y-%m-%d %H:%M", stamp + offset)
end

function Events:GetStore()
    local guild = Sync:GetGuildKey()
    if guild ~= self.guild then
        self.guild = guild
        self.pending, self.pendingDeletions, self.replay = {}, {}, {}
        self.lastRequest, self.replayAt = nil, nil
        self.selected, self.draft = nil, nil
    end
    if not guild then return end
    GHTAB = GHTAB or {}
    GHTAB.EVENTS = GHTAB.EVENTS or {}
    GHTAB.EVENTS[guild] = GHTAB.EVENTS[guild] or {}

    return GHTAB.EVENTS[guild]
end

function Events:Get(id)
    local store = self:GetStore()
    return store and id and store[id]
end

function Events:GetIcon(id)
    local bucket = self:Get(id)
    if bucket and bucket.event and bucket.event.revision then return bucket.event.icon end
    return bucket and bucket.icon and bucket.icon.icon
end

function Events:ForeverPlayerName()
    if not GuildHelper:IsForever() then return end
    local _, ownName = GuildHelper:GetPlayerCharacterKey()
    if ownName then return ownName end

    local name = GetUnitName and GetUnitName("player", false)
    if GuildHelper:CanAccessValues(name) and name and name:find("%s") then return GuildHelper.Members:ShortName(name) end
    local first, surname = UnitName("player")
    if not GuildHelper:CanAccessValues(first, surname) or not first then return end
    if first:find("%s") then return GuildHelper.Members:ShortName(first) end
    if surname and surname ~= "" then return first .. " " .. surname end
end

function Events:IsOwn(event)
    if not event then return false end
    if Groups:IsSelfName(event.author) then return true end
    local Members = GuildHelper.Members
    local fullName = self:ForeverPlayerName()
    if fullName and Groups:Name(fullName) == event.author then return true end
    local alias = Members:ForeverSurnameAlias(event.name)
    if not alias then return false end

    local member, ambiguous = Members:FindByName(event.name)
    if member then return Members:IsSelf(member) end
    if ambiguous then return false end

    local function matches(name)
        local key = Groups:Name(name)
        return key ~= nil and Members:ShortName(key) == alias
    end
    return matches(fullName) or matches(Groups:Self()) or matches(Sync:GetOwnName()) or matches(UnitName("player"))
end

function Events:GetLeader()
    for index = 1, GetNumGuildMembers() or 0 do
        local name, _, rank = GetGuildRosterInfo(index)
        if GuildHelper:CanAccessValues(name, rank) and name and rank == 0 then return Groups:Name(name) end
    end
end

function Events:CanDelete(event)
    if not event then return false end
    if self:IsOwn(event) then return true end
    if IsGuildLeader then return IsGuildLeader() == true end
    local leader = self:GetLeader()
    return leader ~= nil and Groups:IsSelfName(leader)
end

function Events:GetList()
    local list = {}
    for _, bucket in pairs(self:GetStore() or {}) do
        if bucket.event then tinsert(list, bucket.event) end
    end
    table.sort(list, function(a, b)
        if a.when ~= b.when then return a.when < b.when end
        return a.id < b.id
    end)
    return list
end

function Events:NewId()
    return format("%x%08x%08x", GetServerTime(), random(0, 0xffffff), random(0, 0xffffff))
end

function Events:Author()
    local key = GuildHelper:GetPlayerCharacterKey()
    if key then return key, Groups:Name(key) end

    local fullName = self:ForeverPlayerName()
    if fullName then
        local name = fullName .. "-" .. (GetRealmName() or ""):gsub("%s", "")
        return name, Groups:Name(name)
    end
    local name = Feedback:GetAuthor()
    if not Groups:IsSelfName(name) then name = Groups:Self() or name end
    if name ~= "" and not name:find("-", 1, true) then
        local _, realm = (UnitFullName or UnitName)("player")
        realm = realm and realm ~= "" and realm or (GetRealmName() or ""):gsub("%s", "")
        name = name .. "-" .. realm
    end

    return name, Groups:Name(name)
end

function Events:GetResponse(bucket)
    local _, author = self:Author()
    if bucket and bucket.responses[author] then return bucket.responses[author] end
    for _, response in pairs(bucket and bucket.responses or {}) do
        if self:IsOwn(response) then return response end
    end
end

function Events:NormalizeIcon(icon)
    if type(icon) ~= "string" and type(icon) ~= "number" then return end
    local id = tonumber(icon)
    if id then
        if id > 0 and id <= 2147483647 and id == floor(id) then return id end
        return
    end
    if type(icon) ~= "string" or #icon > 112 then return end
    local name = icon:lower():gsub("^interface[\\/]icons[\\/]", ""):gsub("%.blp$", ""):gsub("%.tga$", "")
    if name:match("^[%w_%-]+$") then return "Interface\\Icons\\" .. name end
end

function Events:IconMarkup(icon, size)
    if not icon then return "" end
    return format("|T%s:%d:%d|t ", icon, size, size)
end

function Events:Pack(row)
    if row.kind == "D" then return table.concat({"D", row.id, row.name, row.owner}, "~") end
    if row.kind == "I" then return table.concat({"I", row.id, row.name, row.icon}, "~") end
    if row.kind == "E" then
        local info = Feedback:Encode(row.info)
        if row.revision then
            return table.concat({"U", row.id, row.name, row.revision, row.icon or "", row.when, row.title, info}, "~")
        end
        return table.concat({"E", row.id, row.name, row.when, row.title, info}, "~")
    elseif row.kind == "R" then
        return table.concat({"R", row.id, row.name, row.revision, row.role, row.status, row.text}, "~")
    end
    return table.concat({"C", row.id, row.name, row.comment, row.revision, row.text}, "~")
end

function Events:Unpack(packet)
    local kind, id, name, payload = packet:match("^([ERCIUD])~([0-9a-f]+)~([^~]+)~(.*)$")
    local author = name and Groups:Name(name)
    if not author or #id > 32 then return end
    local row = {kind = kind, id = id, name = name, author = author}
    if kind == "D" then
        row.owner = Groups:Name(payload)
        if not row.owner then return end
    elseif kind == "I" then
        row.icon = self:NormalizeIcon(payload)
        if not row.icon then return end
    elseif kind == "E" or kind == "U" then
        if kind == "U" then
            local revision, icon, details = payload:match("^(%d+)~([^~]*)~(.*)$")
            if not revision or #revision > 12 or tonumber(revision) == 0 then return end
            row.kind, row.revision = "E", tonumber(revision)
            row.icon = self:NormalizeIcon(icon)
            if icon ~= "" and not row.icon then return end
            payload = details
        end
        local when, title, info = payload:match("^([^~]+)~([^~]+)~(.*)$")
        local dayText, timeText
        if when then dayText, timeText = when:match("^(%S+) (%S+)$") end
        if not dayText or self:ParseDate(dayText, timeText) ~= when then return end
        row.title = Groups:CleanText(title, 120)
        if row.title == "" then return end
        row.when = when
        row.info = Feedback:CleanBody(Feedback:Decode(info))
    elseif kind == "R" then
        local revision, role, status, body = payload:match("^(%d+)~([A-Z]+)~([ATD])~(.*)$")
        if not revision or #revision > 12 or not self.roles[role] then return end
        row.revision, row.role, row.status = tonumber(revision), role, status
        row.text = Groups:CleanText(body, 240)
    else
        local comment, revision, body = payload:match("^([0-9a-f]+)~(%d+)~(.*)$")
        if not comment or #comment > 32 or #revision > 12 then return end
        row.comment, row.revision = comment, tonumber(revision)
        row.text = Groups:CleanText(body, 240)
    end
    return row
end

function Events:RecordKey(row)
    if row.kind == "I" then return row.id .. ":I" end
    if row.kind == "R" then return row.id .. ":R:" .. row.author end
    if row.kind == "C" then return row.id .. ":C:" .. row.comment end
    return row.id
end

function Events:Merge(row)
    local store = self:GetStore()
    if not store then return end
    local bucket = store[row.id]
    if not bucket then
        bucket = {responses = {}, comments = {}}
        store[row.id] = bucket
    end
    local key = self:RecordKey(row)
    if bucket.deleted then
        if row.kind ~= "E" or row.author == bucket.deleted.owner then return end
        bucket.deleted = nil
    end
    if row.kind == "I" and bucket.event and (bucket.event.revision or bucket.event.author ~= row.author) then return end
    local current = row.kind == "I" and bucket.icon or row.kind == "E" and bucket.event or
        row.kind == "R" and bucket.responses[row.author] or row.kind == "C" and bucket.comments[row.comment]
    if current and current.author ~= row.author then return end
    if current and ((current.revision or 0) > (row.revision or 0) or
        ((current.revision or 0) == (row.revision or 0) and self:Pack(current) > self:Pack(row))) then return end

    self.replay[key] = nil
    if current and self:Pack(current) == self:Pack(row) then return end
    if row.kind == "I" then
        bucket.icon = row
    elseif row.kind == "E" then
        bucket.event = row
        if bucket.icon and (row.revision or bucket.icon.author ~= row.author) then
            bucket.icon = nil
            self.replay[row.id .. ":I"] = nil
        end
    elseif row.kind == "R" then
        bucket.responses[row.author] = row
    else
        bucket.comments[row.comment] = row
    end
    if self.OnChanged then self:OnChanged() end
    return true
end

function Events:MergeDeletion(row)
    local store = self:GetStore()
    if not store then return end
    local bucket = store[row.id]
    if bucket and bucket.event and bucket.event.author ~= row.owner then return end
    local previous = bucket and bucket.deleted
    local packet = self:Pack(row)
    if previous then
        if previous.owner ~= row.owner then return end
        local previousByOwner, byOwner = previous.author == previous.owner, row.author == row.owner
        if previousByOwner and not byOwner then return end
        if previousByOwner == byOwner and self:Pack(previous) > packet then return end
    end

    self.replay[row.id] = nil
    if previous and self:Pack(previous) == packet then return end
    if bucket then
        self.replay[row.id .. ":I"] = nil
        for _, rows in ipairs({bucket.responses, bucket.comments}) do
            for _, entry in pairs(rows) do self.replay[self:RecordKey(entry)] = nil end
        end
    end
    store[row.id] = {deleted = row, responses = {}, comments = {}}
    if self.selected == row.id then self.selected = nil end
    if self.draft and self.draft.event == row.id then self.draft = nil end
    if self.OnChanged then self:OnChanged() end
    return true
end

function Events:Delete(id)
    local bucket = self:Get(id)
    local event = bucket and bucket.event
    if not self:CanDelete(event) then return end
    local name, author
    if self:IsOwn(event) then
        name, author = event.name, event.author
    else
        name, author = self:Author()
    end
    if not author then return end
    local row = {kind = "D", id = id, name = name, author = author, owner = event.author}
    if self:MergeDeletion(row) then self:Send(row) end
end

function Events:ReceiveDeletion(row, sender)
    if row.author == row.owner then
        self:MergeDeletion(row)
        return
    end
    local leader = self:GetLeader()
    if leader then
        if row.author == leader or Groups:Name(sender) == leader then self:MergeDeletion(row) end
    else
        local first = next(self.pendingDeletions) == nil
        self.pendingDeletions[row.id .. ":" .. row.author] = {row = row, sender = sender, expires = GetTime() + 120}
        if first then GuildHelper.Members:RequestRoster() end
    end
end

function Events:RetryDeletions()
    if not next(self.pendingDeletions) then return end
    local leader = self:GetLeader()
    if not leader then return end
    local now = GetTime()
    for key, pending in pairs(self.pendingDeletions) do
        self.pendingDeletions[key] = nil
        if pending.expires >= now and (pending.row.author == leader or Groups:Name(pending.sender) == leader) then
            self:MergeDeletion(pending.row)
        end
    end
end

function Events:Send(row)
    local packet = self:Pack(row)
    local parts = {}
    while #packet > 0 do
        local part = Feedback:Cut(packet, 200)
        tinsert(parts, part)
        packet = packet:sub(#part + 1)
    end
    local token = self:NewId()
    for index, part in ipairs(parts) do
        Sync:Send(format("EV~%s~%d~%d~%s", token, index, #parts, part), nil, nil, self.guild)
    end
end

function Events:Publish(when, title, info, icon)
    local name, author = self:Author()
    if not author or not self:GetStore() then return end
    local row = {kind = "E", id = self:NewId(), name = name, author = author, when = when, title = title,
        info = Feedback:CleanBody(info)}
    if self:Merge(row) then
        self:Send(row)
        icon = self:NormalizeIcon(icon)
        if icon then
            local iconRow = {kind = "I", id = row.id, name = name, author = author, icon = icon}
            if self:Merge(iconRow) then self:Send(iconRow) end
        end
        return row.id
    end
end

function Events:UpdateEvent(id, when, title, info, icon)
    local bucket = self:Get(id)
    local current = bucket and bucket.event
    if not self:IsOwn(current) then return end
    info = Feedback:CleanBody(info)
    icon = self:NormalizeIcon(icon)
    if current.when == when and current.title == title and current.info == info and self:GetIcon(id) == icon then return id end
    local revision = max(GetServerTime(), (current.revision or 0) + 1)
    local row = {kind = "E", id = id, name = current.name, author = current.author,
        revision = revision, when = when, title = title, info = info, icon = icon}
    if self:Merge(row) then
        self:Send(row)
        return id
    end
end

function Events:Respond(id, role, status, value)
    local bucket = self:Get(id)
    local name, author = self:Author()
    if not bucket or not bucket.event or not author or not self.roles[role] or not self.statuses[status] then return end
    local old = self:GetResponse(bucket)
    local revision = max(GetServerTime(), old and old.revision + 1 or 0)
    local row = {kind = "R", id = id, name = old and old.name or name, author = old and old.author or author,
        revision = revision, role = role, status = status, text = Groups:CleanText(value, 240)}
    if self:Merge(row) then self:Send(row) end
end

function Events:Comment(id, value, comment)
    local bucket = self:Get(id)
    local name, author = self:Author()
    if not bucket or not bucket.event or not author then return end
    local text = Groups:CleanText(value, 240)
    local previous = comment and bucket.comments[comment]
    if comment and (not previous or not self:IsOwn(previous)) then return end
    if not comment and text == "" then return end
    local revision = max(GetServerTime(), previous and previous.revision + 1 or 0)
    local row = {kind = "C", id = id, name = previous and previous.name or name, author = previous and previous.author or author,
        comment = comment or self:NewId(), revision = revision, text = text}
    if self:Merge(row) then
        self:Send(row)
        return true
    end
end

function Events:Request()
    local store = self:GetStore()
    if not store then return end
    local now = GetTime()
    if self.lastRequest and now - self.lastRequest < 60 then return end
    self.lastRequest = now
    Sync:Send("EV~Q~" .. self:Digest(store), "EV~Q", nil, self.guild)
end

function Events:Shareable(store)
    local records = {}
    for _, bucket in pairs(store) do
        if bucket.deleted then
            records[bucket.deleted.id] = bucket.deleted
        elseif bucket.event then
            records[bucket.event.id] = bucket.event
            if bucket.icon then records[self:RecordKey(bucket.icon)] = bucket.icon end
            for _, rows in ipairs({bucket.responses, bucket.comments}) do
                for _, row in pairs(rows) do records[self:RecordKey(row)] = row end
            end
        end
    end
    return records
end

function Events:Digest(store)
    local count, hash = 0, 0
    for _, row in pairs(self:Shareable(store)) do
        count = count + 1
        hash = (hash + Feedback:Hash(self:Pack(row))) % 2147483647
    end
    return count .. "~" .. hash
end

function Events:ScheduleReplay(store)
    if self.replayAt then return end
    self.replayAt = GetTime() + random(20, 90) / 10
    self.replay = self:Shareable(store)
end

function Events:OnMessage(message, sender)
    local store = self:GetStore()
    if not store or Groups:IsSelfName(sender) then return end
    local digest = message:match("^EV~Q~(%d+~%d+)$")
    if digest then
        if not self.replayAt and digest ~= self:Digest(store) then self:ScheduleReplay(store) end
        return
    end
    local token, index, count, part = message:match("^EV~([0-9a-f]+)~(%d%d?)~(%d%d?)~(.*)$")
    if not token or #token > 32 then return end
    index, count = tonumber(index), tonumber(count)
    if index < 1 or index > count or count > 24 or #part > 200 then return end
    local key = sender .. ":" .. token
    local pending = self.pending[key]
    if not pending then
        pending = {count = count, received = 0, expires = GetTime() + 120}
        self.pending[key] = pending
    end
    if pending.count ~= count or pending[index] then return end
    pending[index], pending.received = part, pending.received + 1
    if pending.received == count then
        self.pending[key] = nil
        local row = self:Unpack(table.concat(pending, "", 1, count))
        if row and row.kind == "D" then
            self:ReceiveDeletion(row, sender)
        elseif row then
            self:Merge(row)
        end
    end
end

function Events:Tick()
    self:GetStore()
    local now = GetTime()
    for key, pending in pairs(self.pending) do
        if pending.expires < now then self.pending[key] = nil end
    end
    for key, pending in pairs(self.pendingDeletions) do
        if pending.expires < now then self.pendingDeletions[key] = nil end
    end
    if not self.replayAt or now < self.replayAt or #Sync.queue > 0 then return end
    local key, row = next(self.replay)
    if not key then
        self.replayAt = nil
        return
    end
    if row.kind ~= "E" and self.replay[row.id] then
        key, row = row.id, self.replay[row.id]
    end
    self.replay[key] = nil
    self:Send(row)
end

local frame = CreateFrame("Frame")
frame:RegisterEvent("PLAYER_LOGIN")
frame:RegisterEvent("PLAYER_GUILD_UPDATE")
frame:RegisterEvent("GUILD_ROSTER_UPDATE")
frame:SetScript("OnEvent", function(_, event)
    Events:GetStore()
    if event == "GUILD_ROSTER_UPDATE" then
        Events:RetryDeletions()
        return
    end
    C_Timer.After(8, function() Events:Request() end)
    if Events.OnChanged then Events:OnChanged() end
end)
local elapsedTotal = 0
frame:SetScript("OnUpdate", function(_, elapsed)
    elapsedTotal = elapsedTotal + elapsed
    if elapsedTotal < 1 then return end
    elapsedTotal = 0
    if Events.replayAt or next(Events.pending) or next(Events.pendingDeletions) then Events:Tick() end
end)
