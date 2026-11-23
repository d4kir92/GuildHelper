local _, GuildHelper = ...
local Theme, Members, Sync, Dashboard = GuildHelper.Theme, GuildHelper.Members, GuildHelper.Sync, GuildHelper.Dashboard
local History = {
    SLOT = 900,
    DAY = 86400,
    RECENTDAYS = 35,
    KEEPDAYS = 400,
    BLOCK = 30,
    PACK = 10000,
    REQUESTEVERY = 1800,
    FOLLOWUP = 150,
    ANSWERAGAIN = 120,
    MAXANSWER = 60,
    CHART = 170,
    active = {},
    answered = {},
    answerTo = {},
    buckets = {}
}

GuildHelper.History = History
History.RANGES = {
    {
        key = "day",
        label = "LID_HISTORY24H",
        count = 96,
        step = 900,
        every = 24,
        format = "%H:%M"
    },
    {
        key = "week",
        label = "LID_HISTORYWEEK",
        count = 168,
        step = 3600,
        every = 24,
        format = "%a"
    },
    {
        key = "month",
        label = "LID_HISTORYMONTH",
        count = 30,
        step = 86400,
        every = 7
    },
    {
        key = "year",
        label = "LID_HISTORYYEAR",
        count = 52,
        step = 604800,
        every = 13
    }
}

function History:Now()
    return GetServerTime and GetServerTime() or time()
end

function History:GetStore()
    local guild = Sync:GetGuildKey()
    if not guild then return nil end
    GHTAB = GHTAB or {}
    GHTAB.ONLINEHISTORY = GHTAB.ONLINEHISTORY or {}
    local store = GHTAB.ONLINEHISTORY[guild] or {}
    GHTAB.ONLINEHISTORY[guild] = store
    store.slots = store.slots or {}
    store.days = store.days or {}

    return store
end

function History:Unpack(value)
    if type(value) ~= "number" then return nil end

    return floor(value / self.PACK), value % self.PACK
end

function History:Merge(current, online, users)
    local co, cu = self:Unpack(current)
    if co then online, users = max(online, co), max(users, cu) end
    local value = online * self.PACK + users

    return value, value ~= current
end

function History:IsPlausible(online, users)
    local total = GetNumGuildMembers and GetNumGuildMembers() or 0
    total = max(total or 0, 1000)

    return online and users and online >= 0 and users >= 0 and users <= online and online <= total and online == floor(online) and users == floor(users)
end

function History:PutDay(store, day, online, users)
    local value, changed = self:Merge(store.days[day], online, users)
    store.days[day] = value

    return changed
end

function History:PutSlot(store, slot, online, users)
    local value, changed = self:Merge(store.slots[slot], online, users)
    store.slots[slot] = value
    local dayChanged = self:PutDay(store, floor(slot * self.SLOT / self.DAY), online, users)

    return changed or dayChanged
end

function History:Prune(store)
    local today = floor(self:Now() / self.DAY)
    local firstSlot = (today - self.RECENTDAYS) * self.DAY / self.SLOT
    for slot in pairs(store.slots) do
        if slot < firstSlot then store.slots[slot] = nil end
    end

    for day in pairs(store.days) do
        if day < today - self.KEEPDAYS then store.days[day] = nil end
    end
end

function History:Heard(sender)
    if type(sender) ~= "string" then return end
    self.active[Sync:GetKey(sender)] = true
end

function History:Count()
    local total = GetNumGuildMembers and GetNumGuildMembers() or 0
    local ownGUID = UnitGUID and UnitGUID("player")
    local online, users = 0, 0
    for index = 1, total or 0 do
        local name, _, _, _, _, _, _, _, isOnline, _, _, _, _, _, _, _, guid = GetGuildRosterInfo(index)
        if GuildHelper:CanAccessValues(name, isOnline) and name then
            local key = Sync:GetKey(name)
            if isOnline then
                online = online + 1
                local own = ownGUID ~= nil and GuildHelper:CanAccessValues(guid, ownGUID) and guid == ownGUID
                if own or self.active[key] then users = users + 1 end
            else
                self.active[key] = nil
            end
        end
    end

    return online, min(users, online)
end

function History:Sample()
    if not IsInGuild() or not self.started or GetTime() - self.started < 45 then return end
    local store = self:GetStore()
    if not store then return end
    local online, users = self:Count()
    if online == 0 then return end
    if self:PutSlot(store, floor(self:Now() / self.SLOT), online, users) then self:Changed() end
    if not self.lastPrune or GetTime() - self.lastPrune > 3600 then
        self.lastPrune = GetTime()
        self:Prune(store)
    end
end

function History:Digest(text)
    if text == "" then return "00" end
    local value = GuildHelper.Feedback:Base36(GuildHelper.Feedback:Hash(text) % 1296)

    return strrep("0", 2 - #value) .. value
end

function History:DaySlots(store, day)
    local first = day * self.DAY / self.SLOT
    local parts = {}
    for index = 0, self.DAY / self.SLOT - 1 do
        local value = store.slots[first + index]
        if value then tinsert(parts, index .. ":" .. value) end
    end

    return parts
end

function History:DayText(store, day)
    local parts = self:DaySlots(store, day)
    if store.days[day] then tinsert(parts, "d" .. store.days[day]) end

    return table.concat(parts, ",")
end

function History:BlockDays(store, block, today)
    local parts = {}
    local last = min(block * self.BLOCK + self.BLOCK - 1, today - self.RECENTDAYS)
    for day = max(block * self.BLOCK, today - self.KEEPDAYS), last do
        local value = store.days[day]
        if value then tinsert(parts, day .. ":" .. value) end
    end

    return parts
end

function History:GetBlocks(today)
    local blocks = {}
    for block = floor((today - self.KEEPDAYS) / self.BLOCK), floor((today - self.RECENTDAYS) / self.BLOCK) do
        tinsert(blocks, block)
    end

    return blocks
end

function History:BuildDigests(store, today)
    local recent, old = {}, {}
    for day = today - self.RECENTDAYS + 1, today do
        tinsert(recent, self:Digest(self:DayText(store, day)))
    end

    for _, block in ipairs(self:GetBlocks(today)) do
        tinsert(old, self:Digest(table.concat(self:BlockDays(store, block, today), ",")))
    end

    return table.concat(recent), table.concat(old)
end

function History:Request()
    local store = self:GetStore()
    if not store then return end
    self.lastRequest = GetTime()
    local today = floor(self:Now() / self.DAY)
    local recent, old = self:BuildDigests(store, today)
    Sync:Send(table.concat({"H?", today, recent, old}, "~"), "H?", nil, Sync:GetGuildKey())
end

function History:OnRequest(sender, today, recent, old)
    local store = self:GetStore()
    today = tonumber(today)
    if not store or not today or abs(today - floor(self:Now() / self.DAY)) > 1 then return end
    local key = Sync:GetKey(sender)
    if self.answered[key] and GetTime() - self.answered[key] < self.ANSWERAGAIN then return end
    local mineRecent, mineOld = self:BuildDigests(store, today)
    if mineRecent == recent and mineOld == old then return end
    local token = {}
    self.answerTo[key] = token
    C_Timer.After(random(3, 10), function()
        if History.answerTo[key] ~= token then return end
        History.answerTo[key] = nil
        History.answered[key] = GetTime()
        History:Answer(key, today, recent, old)
    end)
end

function History:SendParts(head, parts, budget)
    local current, size = {}, #head
    for _, part in ipairs(parts) do
        if #current > 0 and size + #part + 1 > 250 then
            if budget.left <= 0 then return end
            budget.left = budget.left - 1
            Sync:Send(head .. table.concat(current, ","), nil, nil, Sync:GetGuildKey())
            current, size = {}, #head
        end

        tinsert(current, part)
        size = size + #part + 1
    end

    if #current > 0 and budget.left > 0 then
        budget.left = budget.left - 1
        Sync:Send(head .. table.concat(current, ","), nil, nil, Sync:GetGuildKey())
    end
end

function History:Answer(requester, today, recent, old)
    local store = self:GetStore()
    if not store then return end
    local budget = {
        left = self.MAXANSWER
    }

    for index = self.RECENTDAYS, 1, -1 do
        local day = today - self.RECENTDAYS + index
        local text = self:DayText(store, day)
        if text ~= "" and self:Digest(text) ~= strsub(recent or "", index * 2 - 1, index * 2) then
            local parts = self:DaySlots(store, day)
            if #parts > 0 then self:SendParts(table.concat({"HS", requester, day, ""}, "~"), parts, budget) end
            if store.days[day] then self:SendParts(table.concat({"HD", requester, ""}, "~"), {day .. ":" .. store.days[day]}, budget) end
        end
    end

    for index, block in ipairs(self:GetBlocks(today)) do
        local parts = self:BlockDays(store, block, today)
        if #parts > 0 and self:Digest(table.concat(parts, ",")) ~= strsub(old or "", index * 2 - 1, index * 2) then
            self:SendParts(table.concat({"HD", requester, ""}, "~"), parts, budget)
        end
    end
end

function History:ReadSlots(store, day, list)
    day = tonumber(day)
    local today = floor(self:Now() / self.DAY)
    if not day or day > today or day <= today - self.RECENTDAYS then return false end
    local changed = false
    local first = day * self.DAY / self.SLOT
    for item in string.gmatch(list or "", "[^,]+") do
        local index, value = item:match("^(%d+):(%d+)$")
        index, value = tonumber(index), tonumber(value)
        if index and value and index < self.DAY / self.SLOT then
            local online, users = self:Unpack(value)
            if self:IsPlausible(online, users) and self:PutSlot(store, first + index, online, users) then changed = true end
        end
    end

    return changed
end

function History:ReadDays(store, list)
    local today = floor(self:Now() / self.DAY)
    local changed = false
    for item in string.gmatch(list or "", "[^,]+") do
        local day, value = item:match("^(%d+):(%d+)$")
        day, value = tonumber(day), tonumber(value)
        if day and value and day <= today and day >= today - self.KEEPDAYS then
            local online, users = self:Unpack(value)
            if self:IsPlausible(online, users) and self:PutDay(store, day, online, users) then changed = true end
        end
    end

    return changed
end

function History:OnMessage(message, sender)
    if #message > 255 then return end
    local kind = strsub(message, 1, 3)
    if kind == "H?~" then
        local today, recent, old = message:match("^H%?~(%d+)~(%w*)~(%w*)$")
        if today then self:OnRequest(sender, today, recent, old) end

        return
    end

    local store = self:GetStore()
    if not store then return end
    local changed
    if kind == "HS~" then
        local requester, day, list = message:match("^HS~([^~]+)~(%d+)~(.*)$")
        if not requester then return end
        self.answerTo[requester] = nil
        changed = self:ReadSlots(store, day, list)
    elseif kind == "HD~" then
        local requester, list = message:match("^HD~([^~]+)~(.*)$")
        if not requester then return end
        self.answerTo[requester] = nil
        changed = self:ReadDays(store, list)
    end

    if changed then
        self.followUp = true
        self:Changed()
    end
end

function History:Changed()
    if self.refreshPending then return end
    self.refreshPending = true
    C_Timer.After(1, function()
        History.refreshPending = false
        if Dashboard:IsVisible() then History:UpdateChart() end
    end)
end

function History:GetRange()
    local wanted = GHTABPC and GHTABPC.HISTORYRANGE or "day"
    for _, range in ipairs(self.RANGES) do
        if range.key == wanted then return range end
    end

    return self.RANGES[1]
end

function History:SetRange(key)
    GHTABPC = GHTABPC or {}
    GHTABPC.HISTORYRANGE = key
    self:UpdateChart()
end

function History:Collect(store, range)
    local now = self:Now()
    local finish = (floor(now / range.step) + 1) * range.step
    local values = {}
    for index = 1, range.count do
        local start = finish - (range.count - index + 1) * range.step
        local online, users
        if range.step < self.DAY then
            for slot = start / self.SLOT, (start + range.step) / self.SLOT - 1 do
                local o, u = self:Unpack(store.slots[slot])
                if o then online, users = max(online or 0, o), max(users or 0, u) end
            end
        else
            for day = start / self.DAY, (start + range.step) / self.DAY - 1 do
                local o, u = self:Unpack(store.days[day])
                if o then online, users = max(online or 0, o), max(users or 0, u) end
            end
        end

        values[index] = {
            start = start,
            finish = start + range.step,
            online = online,
            users = users
        }
    end

    return values
end

function History:FormatTime(stamp, range)
    if range.format then return date(range.format, stamp) end

    return date(GuildHelper:Trans("LID_HISTORYDATEFMT"), stamp)
end

function History:GetBucket(index)
    local bucket = self.buckets[index]
    if bucket then return bucket end
    bucket = CreateFrame("Frame", nil, self.plot)
    bucket.total = bucket:CreateTexture(nil, "ARTWORK", nil, 1)
    Theme:Fill(bucket.total, "online")
    bucket.total:SetAlpha(0.35)
    bucket.users = bucket:CreateTexture(nil, "ARTWORK", nil, 2)
    Theme:Fill(bucket.users, "accent")
    bucket.total:SetPoint("BOTTOMLEFT")
    bucket.total:SetPoint("BOTTOMRIGHT")
    bucket.users:SetPoint("BOTTOMLEFT")
    bucket.users:SetPoint("BOTTOMRIGHT")
    bucket:EnableMouse(true)
    bucket:SetScript("OnEnter", function(sel)
        local value = sel.value
        if not value then return end
        local range = History:GetRange()
        GameTooltip:SetOwner(sel, "ANCHOR_TOP")
        GameTooltip:AddLine(History:FormatTime(value.start, range) .. " - " .. History:FormatTime(value.finish, range), 1, 1, 1)
        if value.online then
            GameTooltip:AddDoubleLine(GuildHelper:Trans("LID_ONLINENOW"), value.online, 0.7, 0.7, 0.7, 1, 1, 1)
            GameTooltip:AddDoubleLine(GuildHelper:Trans("LID_GUILDHELPERUSERS"), value.users, 0.7, 0.7, 0.7, 1, 1, 1)
        else
            GameTooltip:AddLine(GuildHelper:Trans("LID_HISTORYNODATA"), 0.7, 0.7, 0.7)
        end

        GameTooltip:Show()
    end)

    bucket:SetScript("OnLeave", function() GameTooltip:Hide() end)
    self.buckets[index] = bucket

    return bucket
end

function History:GetLabel(index)
    self.labels = self.labels or {}
    local label = self.labels[index]
    if label then return label end
    label = Theme:Text(self.card, 10, "muted")
    self.labels[index] = label

    return label
end

function History:CreateLegend(card, key, label, anchor)
    local swatch = card:CreateTexture(nil, "ARTWORK")
    swatch:SetSize(10, 10)
    Theme:Fill(swatch, key)
    if key == "online" then swatch:SetAlpha(0.35) end
    if anchor then
        swatch:SetPoint("LEFT", anchor, "RIGHT", 14, 0)
    else
        swatch:SetPoint("TOPLEFT", card, "TOPLEFT", 16, -40)
    end
    local text = Theme:Text(card, 11, "muted")
    text:SetPoint("LEFT", swatch, "RIGHT", 5, 0)
    Theme:SetTrans(text, label)

    return text
end

function History:CreateChart(parent)
    local card = Dashboard:CreateCard(parent, "LID_ONLINEHISTORY")
    card:SetHeight(self.CHART)
    self.card = card
    local legend = self:CreateLegend(card, "online", "LID_ONLINENOW")
    self:CreateLegend(card, "accent", "LID_GUILDHELPERUSERS", legend)
    self.pills = {}
    local anchor
    for index = #self.RANGES, 1, -1 do
        local range = self.RANGES[index]
        local pill = Members:CreatePill(card, GuildHelper:Trans(range.label))
        if anchor then
            pill:SetPoint("RIGHT", anchor, "LEFT", -6, 0)
        else
            pill:SetPoint("TOPRIGHT", card, "TOPRIGHT", -12, -10)
        end

        pill:SetScript("OnClick", function() History:SetRange(range.key) end)
        self.pills[range.key] = pill
        anchor = pill
    end

    self.maxLabel = Theme:Text(card, 10, "muted")
    self.maxLabel:SetPoint("TOPRIGHT", card, "TOPLEFT", 40, -58)
    self.maxLabel:SetJustifyH("RIGHT")
    self.zeroLabel = Theme:Text(card, 10, "muted")
    self.zeroLabel:SetPoint("BOTTOMRIGHT", card, "BOTTOMLEFT", 40, 26)
    self.zeroLabel:SetJustifyH("RIGHT")
    self.zeroLabel:SetText("0")
    local plot = CreateFrame("Frame", nil, card)
    plot:SetPoint("TOPLEFT", card, "TOPLEFT", 48, -62)
    plot:SetPoint("BOTTOMRIGHT", card, "BOTTOMRIGHT", -16, 28)
    self.plot = plot
    local top = Theme:Line(plot, "divider")
    top:SetPoint("TOPLEFT")
    top:SetPoint("TOPRIGHT")
    top:SetHeight(1)
    local base = Theme:Line(plot, "divider")
    base:SetPoint("BOTTOMLEFT")
    base:SetPoint("BOTTOMRIGHT")
    base:SetHeight(1)
    self.empty = Theme:Text(plot, 12, "muted")
    self.empty:SetPoint("CENTER")
    Theme:SetTrans(self.empty, "LID_HISTORYNODATA")
    plot:SetScript("OnSizeChanged", function() History:UpdateChart() end)

    return card
end

function History:UpdateChart()
    if not self.plot then return end
    local range = self:GetRange()
    for key, pill in pairs(self.pills) do
        Members:SetPillText(pill, GuildHelper:Trans(self:GetRangeLabel(key)))
        Members:SetPillActive(pill, key == range.key)
    end

    local store = self:GetStore()
    local values = store and self:Collect(store, range) or {}
    local width, height = self.plot:GetWidth(), self.plot:GetHeight()
    local top = 0
    for _, value in ipairs(values) do
        top = max(top, value.online or 0)
    end

    self.empty:SetShown(top == 0)
    self.maxLabel:SetText(top > 0 and tostring(top) or "")
    self.zeroLabel:SetShown(top > 0)
    local count = #values
    local step = count > 0 and width / count or 0
    local gap = step > 4 and 1 or 0
    for index = 1, max(count, #self.buckets) do
        local bucket = index <= count and self:GetBucket(index) or self.buckets[index]
        local value = values[index]
        if value and width > 0 and height > 0 then
            bucket.value = value
            bucket:ClearAllPoints()
            bucket:SetPoint("BOTTOMLEFT", self.plot, "BOTTOMLEFT", (index - 1) * step, 0)
            bucket:SetSize(max(1, step - gap), height)
            local online, users = value.online or 0, value.users or 0
            bucket.total:SetHeight(max(0.01, top > 0 and online / top * height or 0))
            bucket.users:SetHeight(max(0.01, top > 0 and users / top * height or 0))
            bucket.total:SetShown(online > 0)
            bucket.users:SetShown(users > 0)
            bucket:Show()
        elseif bucket then
            bucket.value = nil
            bucket:Hide()
        end
    end

    local labelIndex = 0
    for index = 1, count, range.every do
        labelIndex = labelIndex + 1
        local label = self:GetLabel(labelIndex)
        label:ClearAllPoints()
        label:SetPoint("TOPLEFT", self.plot, "BOTTOMLEFT", (index - 1) * step, -4)
        label:SetText(self:FormatTime(values[index].start, range))
        label:Show()
    end

    for index = labelIndex + 1, #(self.labels or {}) do
        self.labels[index]:Hide()
    end
end

function History:ResetChart()
    self.card, self.plot, self.pills, self.labels, self.maxLabel, self.zeroLabel, self.empty = nil, nil, nil, nil, nil, nil, nil
    self.buckets = {}
end

function History:GetRangeLabel(key)
    for _, range in ipairs(self.RANGES) do
        if range.key == key then return range.label end
    end
end

History.events = CreateFrame("Frame")
History.events:RegisterEvent("PLAYER_LOGIN")
History.events:SetScript("OnEvent", function()
    History.started = GetTime()
    C_Timer.After(40, function() History:Request() end)
    C_Timer.NewTicker(60, function()
        History:Sample()
        local since = History.lastRequest and GetTime() - History.lastRequest
        if not since or since >= History.REQUESTEVERY or (History.followUp and since >= History.FOLLOWUP) then
            History.followUp = false
            History:Request()
        end
    end)
end)
