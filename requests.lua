local _, GuildHelper = ...
local Sync, Groups, Feedback = GuildHelper.Sync, GuildHelper.Groups, GuildHelper.Feedback
local Requests = {pending = {}, replay = {}, query = "", filter = "all"}
Requests.RETENTION = 30 * 86400
Requests.MAXOPEN = 10
Requests.MAXQUANTITY = 9999
Requests.MAXMONEY = 9999999999
Requests.MODES = {"S", "V"}
Requests.MODESET = {S = true, V = true}
Requests.CATEGORIES = {"M", "G", "A", "W", "X"}
Requests.CATEGORYSET = {M = true, G = true, A = true, W = true, X = true}
Requests.ICONS = {M = "INV_Fabric_Linen_01", G = "INV_Misc_Coin_01", A = "INV_Chest_Chain", W = "INV_Sword_04", X = "INV_Misc_QuestionMark"}
Requests.ITEMCLASSES = {[2] = "W", [4] = "A", [7] = "M"}
GuildHelper.Requests = Requests

function Requests:GetStore()
    local guild = Sync:GetGuildKey()
    if guild ~= self.guild then
        self.guild = guild
        self.pending, self.replay = {}, {}
        self.lastRequest, self.replayAt = nil, nil
        self.selected, self.draft = nil, nil
    end

    if not guild then return end
    GHTAB = GHTAB or {}
    GHTAB.REQUESTS = GHTAB.REQUESTS or {}
    GHTAB.REQUESTS[guild] = GHTAB.REQUESTS[guild] or {}
    local store = GHTAB.REQUESTS[guild]
    if self.migrated ~= guild then
        self.migrated = guild
        for _, bucket in pairs(store) do
            bucket.helpers, bucket.comments = bucket.helpers or {}, bucket.comments or {}
            if bucket.request and not bucket.request.mode then bucket.request.mode = "S" end
        end
    end

    return store
end

function Requests:GetSeen()
    if not self.guild then return {} end
    GHTAB.REQUESTSEEN = GHTAB.REQUESTSEEN or {}
    GHTAB.REQUESTSEEN[self.guild] = GHTAB.REQUESTSEEN[self.guild] or {}

    return GHTAB.REQUESTSEEN[self.guild]
end

function Requests:Created(id)
    return tonumber(id:sub(1, 8), 16) or 0
end

function Requests:IsFresh(revision)
    local now = GetServerTime()

    return revision >= now - self.RETENTION and revision <= now + 86400
end

function Requests:Prune(store)
    local seen = self:GetSeen()
    for id, bucket in pairs(store or {}) do
        local revision = bucket.request and bucket.request.revision or 0
        for _, helper in pairs(bucket.helpers or {}) do revision = max(revision, helper.revision) end
        for _, comment in pairs(bucket.comments or {}) do revision = max(revision, comment.revision) end
        if not self:IsFresh(revision) then
            store[id] = nil
            seen[id] = nil
        end
    end
end

function Requests:Pack(row)
    if row.kind == "H" then return table.concat({"H", row.id, row.name, row.revision, row.state}, "~") end
    if row.kind == "C" then return table.concat({"C", row.id, row.name, row.revision, row.cid, row.text}, "~") end

    return table.concat({"Q", row.id, row.name, row.revision, row.status, row.mode, row.category, row.item, row.quantity, row.gold, row.text}, "~")
end

function Requests:Unpack(packet)
    local kind, id, name, revision, payload = packet:match("^([QHC])~(%x+)~([^~]+)~(%d+)~(.*)$")
    local author = name and Groups:Name(name)
    if not author or #id > 32 or #id < 9 or #revision > 12 then return end
    local row = {kind = kind, id = id, name = name, author = author, revision = tonumber(revision)}
    if kind == "H" then
        if payload ~= "0" and payload ~= "1" then return end
        row.state = payload

        return row
    end

    if kind == "C" then
        local cid, text = payload:match("^(%x+)~(.+)$")
        if not cid or #cid > 32 or #cid < 9 or Groups:CleanText(text, 240) ~= text then return end
        row.cid, row.text = cid, text

        return row
    end

    local status, mode, category, item, quantity, gold, text = payload:match("^([ODX])~(%u)~(%u)~(%d+)~(%d+)~(%d+)~(.*)$")
    if not status or #item > 10 or #quantity > 4 or #gold > 10 then return end
    item, quantity, gold = tonumber(item), tonumber(quantity), tonumber(gold)
    if not self.MODESET[mode] or not self.CATEGORYSET[category] or item > 2147483647 then return end
    if quantity < 1 or quantity > self.MAXQUANTITY or gold > self.MAXMONEY then return end
    if Groups:CleanText(text, 120) ~= text then return end
    row.status, row.mode, row.category, row.item, row.quantity, row.gold, row.text = status, mode, category, item, quantity, gold, text

    return row
end

function Requests:RecordKey(row)
    if row.kind == "H" then return row.id .. ":H:" .. row.author end
    if row.kind == "C" then return row.id .. ":C:" .. row.cid end

    return row.id
end

function Requests:Merge(row)
    local store = self:GetStore()
    if not store or not self:IsFresh(row.revision) then return end
    local bucket = store[row.id]
    if not bucket then
        bucket = {helpers = {}, comments = {}}
        store[row.id] = bucket
    end

    bucket.comments = bucket.comments or {}
    local current
    if row.kind == "H" then
        if bucket.request and bucket.request.author == row.author then return end
        current = bucket.helpers[row.author]
    elseif row.kind == "C" then
        current = bucket.comments[row.cid]
        if current and current.author ~= row.author then return end
    else
        current = bucket.request
        if current and current.author ~= row.author then return end
        if current and current.status == "X" and row.status ~= "X" then return end
    end

    if current and (current.revision > row.revision or (current.revision == row.revision and self:Pack(current) >= self:Pack(row))) then
        if self:Pack(current) == self:Pack(row) then self.replay[self:RecordKey(row)] = nil end

        return
    end

    self.replay[self:RecordKey(row)] = nil
    if row.kind == "H" then
        bucket.helpers[row.author] = row
    elseif row.kind == "C" then
        bucket.comments[row.cid] = row
        if not current then self:NotifyComment(row, bucket) end
    else
        bucket.request = row
    end

    self:Changed()

    return true
end

function Requests:Changed()
    if self.changeQueued then return end
    self.changeQueued = true
    C_Timer.After(0.1, function()
        Requests.changeQueued = nil
        Requests:UpdateCount()
        if Requests.Refresh then Requests:Refresh() end
        if GuildHelper.Mail then GuildHelper.Mail:Refresh() end
    end)
end

function Requests:Send(row)
    local packet = self:Pack(row)
    local parts = {}
    while #packet > 0 do
        local part = Feedback:Cut(packet, 200)
        tinsert(parts, part)
        packet = packet:sub(#part + 1)
    end

    local token = GuildHelper.Events:NewId()
    for index, part in ipairs(parts) do
        Sync:Send(format("RQ~%s~%d~%d~%s", token, index, #parts, part), nil, nil, self.guild)
    end
end

function Requests:Author()
    return GuildHelper.Events:Author()
end

function Requests:IsOwn(row)
    return row ~= nil and Groups:IsSelfName(row.author)
end

function Requests:Get(id)
    local store = self:GetStore()
    local bucket = store and store[id]

    return bucket and bucket.request, bucket
end

function Requests:IsHelping(bucket)
    for author, helper in pairs(bucket and bucket.helpers or {}) do
        if helper.state == "1" and Groups:IsSelfName(author) then return true end
    end

    return false
end

function Requests:Helpers(bucket)
    local list = {}
    for _, helper in pairs(bucket and bucket.helpers or {}) do
        if helper.state == "1" then tinsert(list, helper) end
    end

    table.sort(list, function(a, b) return a.revision < b.revision end)

    return list
end

function Requests:CountOwnOpen()
    local count = 0
    for _, bucket in pairs(self:GetStore() or {}) do
        local row = bucket.request
        if row and row.status == "O" and self:IsOwn(row) then count = count + 1 end
    end

    return count
end

function Requests:GetSubscriptions()
    local subscriptions = GuildHelper:GetConfig("REQUESTSUBSCRIPTIONS", {})
    subscriptions[self.guild or ""] = subscriptions[self.guild or ""] or {}

    return subscriptions[self.guild or ""]
end

function Requests:SetSubscribed(id, subscribed)
    self:GetSubscriptions()[id] = subscribed
end

function Requests:IsSubscribed(bucket)
    local row = bucket and bucket.request
    if not row then return false end
    local subscribed = self:GetSubscriptions()[row.id]
    if subscribed ~= nil then return subscribed end
    if self:IsOwn(row) or self:IsHelping(bucket) then return true end
    for _, comment in pairs(bucket.comments or {}) do
        if Groups:IsSelfName(comment.author) then return true end
    end

    return false
end

function Requests:GetComments(bucket)
    local list = {}
    for _, comment in pairs(bucket and bucket.comments or {}) do tinsert(list, comment) end
    table.sort(list, function(a, b)
        if a.revision ~= b.revision then return a.revision < b.revision end

        return a.cid < b.cid
    end)

    return list
end

function Requests:Comment(id, text)
    local row = self:Get(id)
    text = Groups:CleanText(text, 240)
    if not row or row.status == "X" or text == "" then return end
    local name, author = self:Author()
    if not author then return end
    local comment = {kind = "C", id = id, name = name, author = author, revision = GetServerTime(), cid = GuildHelper.Events:NewId(), text = text}
    if self:Merge(comment) then
        self:Send(comment)

        return true
    end
end

function Requests:NotifyComment(comment, bucket)
    local notifications = GuildHelper.Notifications
    if not notifications or not bucket.request or Groups:IsSelfName(comment.author) then return end
    if comment.revision < (notifications.started or 0) - 60 or not self:IsSubscribed(bucket) then return end
    notifications:RequestComment(comment)
end

function Requests:Open(id)
    if not self:Get(id) then return end
    self.draft, self.selected = nil, id
    GuildHelper.Window.frame:Show()
    GuildHelper.Window:SelectPage("requests")
end

function Requests:Publish(mode, category, item, quantity, gold, text)
    local name, author = self:Author()
    if not author or not self:GetStore() then return end
    local row = {kind = "Q", id = GuildHelper.Events:NewId(), name = name, author = author, revision = GetServerTime(), status = "O",
        mode = mode, category = category, item = item, quantity = quantity, gold = gold, text = text}
    if not self:Unpack(self:Pack(row)) then return end
    if self:Merge(row) then
        self:GetSeen()[row.id] = true
        self:Send(row)

        return row.id
    end
end

function Requests:SetStatus(id, status)
    local row = self:Get(id)
    if not row or not self:IsOwn(row) or row.status == "X" then return end
    local copy = {}
    for key, value in pairs(row) do copy[key] = value end
    copy.status, copy.revision = status, max(GetServerTime(), row.revision + 1)
    if self:Merge(copy) then self:Send(copy) end
end

function Requests:Help(id, helping)
    local row, bucket = self:Get(id)
    if not row or self:IsOwn(row) or row.status ~= "O" then return end
    local name, author = self:Author()
    if not author then return end
    local previous = bucket.helpers[author]
    local helper = {kind = "H", id = id, name = name, author = author, state = helping and "1" or "0",
        revision = max(GetServerTime(), previous and previous.revision + 1 or 0)}
    if self:Merge(helper) then self:Send(helper) end
end

function Requests:CountUnread()
    local store = self:GetStore()
    if not store then return 0 end
    local seen, count = self:GetSeen(), 0
    for id, bucket in pairs(store) do
        local row = bucket.request
        if row and row.status == "O" and not seen[id] and not self:IsOwn(row) then count = count + 1 end
    end

    return count
end

function Requests:UpdateCount()
    local window = GuildHelper.Window
    if window and window.UpdateNavCount then window:UpdateNavCount("requests", self:CountUnread()) end
end

function Requests:Request()
    local store = self:GetStore()
    if not store then return end
    local now = GetTime()
    if self.lastRequest and now - self.lastRequest < 60 then return end
    self.lastRequest = now
    self:Prune(store)
    Sync:Send("RQ~Q~" .. self:Digest(store), "RQ~Q", nil, self.guild)
end

function Requests:Shareable(store)
    local records = {}
    for _, bucket in pairs(store) do
        if bucket.request then records[bucket.request.id] = bucket.request end
        for _, helper in pairs(bucket.helpers) do records[self:RecordKey(helper)] = helper end
        for _, comment in pairs(bucket.comments or {}) do records[self:RecordKey(comment)] = comment end
    end

    return records
end

function Requests:Digest(store)
    local count, hash = 0, 0
    for _, row in pairs(self:Shareable(store)) do
        count = count + 1
        hash = (hash + Feedback:Hash(self:Pack(row))) % 2147483647
    end

    return count .. "~" .. hash
end

function Requests:OnMessage(message, sender)
    local store = self:GetStore()
    if not store or Groups:IsSelfName(sender) then return end
    local digest = message:match("^RQ~Q~(%d+~%d+)$")
    if digest then
        if not self.replayAt and digest ~= self:Digest(store) then
            self.replayAt = GetTime() + random(20, 90) / 10
            self.replay = self:Shareable(store)
        end

        return
    end

    local token, index, count, part = message:match("^RQ~(%x+)~(%d%d?)~(%d%d?)~(.*)$")
    if not token or #token > 32 then return end
    index, count = tonumber(index), tonumber(count)
    if index < 1 or index > count or count > 8 or #part > 200 then return end
    local key = sender .. ":" .. token
    local pending = self.pending[key]
    if not pending then
        pending = {count = count, received = 0, expires = GetTime() + 120}
        self.pending[key] = pending
    end

    if pending.count ~= count or pending[index] then return end
    pending[index], pending.received = part, pending.received + 1
    if pending.received < count then return end
    self.pending[key] = nil
    local row = self:Unpack(table.concat(pending, "", 1, count))
    if row then self:Merge(row) end
end

function Requests:Tick()
    self:GetStore()
    local now = GetTime()
    for key, pending in pairs(self.pending) do
        if pending.expires < now then self.pending[key] = nil end
    end

    if not self.replayAt or now < self.replayAt or #Sync.queue > 0 then return end
    local key, row = next(self.replay)
    if not key then
        self.replayAt = nil

        return
    end

    if row.kind ~= "Q" and self.replay[row.id] then key, row = row.id, self.replay[row.id] end
    self.replay[key] = nil
    self:Send(row)
end

function Requests:MailEntry(list, row, key, name)
    local title, icon = self:Display(row)
    local recipient = GuildHelper.Mail:Recipient(name)
    tinsert(list, {
        key = key,
        incoming = true,
        label = title,
        icon = icon,
        material = row.item > 0 and row.item or nil,
        prefix = row.item > 0 and format("%dx", row.quantity) or nil,
        value = strsplit("-", recipient),
        recipient = recipient,
        subject = Feedback:Cut(title, 60),
        money = row.gold,
        items = row.item > 0 and {{options = {row.item}, quantity = row.quantity}} or {}
    })
end

function Requests:MailEntries(list)
    for id, bucket in pairs(self:GetStore() or {}) do
        local row = bucket.request
        if row and row.status == "O" and (row.item > 0 or row.gold > 0) then
            if row.mode == "V" and self:IsOwn(row) then
                for _, helper in ipairs(self:Helpers(bucket)) do
                    self:MailEntry(list, row, "R" .. id .. ":" .. helper.author, helper.name)
                end
            elseif row.mode == "S" and not self:IsOwn(row) and self:IsHelping(bucket) then
                self:MailEntry(list, row, "R" .. id, row.name)
            end
        end
    end
end

function Requests:Display(row)
    if row.item > 0 then
        local name, loaded = GuildHelper.Recipes:ItemName(row.item)

        return loaded and name or (row.text ~= "" and row.text or name), GuildHelper.Recipes:MaterialIcon(row.item)
    end

    if row.text ~= "" then return row.text, "Interface\\Icons\\" .. self.ICONS[row.category] end

    return GuildHelper.Orders:FormatTip(row.gold), "Interface\\Icons\\" .. self.ICONS.G
end

Requests.events = CreateFrame("Frame")
Requests.events:RegisterEvent("PLAYER_LOGIN")
Requests.events:RegisterEvent("PLAYER_GUILD_UPDATE")
Requests.events:RegisterEvent("GET_ITEM_INFO_RECEIVED")
Requests.events:SetScript("OnEvent", function(_, event)
    if event == "GET_ITEM_INFO_RECEIVED" then
        if Requests.page and Requests.page:IsVisible() then Requests:Changed() end

        return
    end

    Requests:GetStore()
    C_Timer.After(10, function() Requests:Request() end)
    Requests:Changed()
end)
Requests.elapsed = 0
Requests.events:SetScript("OnUpdate", function(_, elapsed)
    Requests.elapsed = Requests.elapsed + elapsed
    if Requests.elapsed < 1 then return end
    Requests.elapsed = 0
    if Requests.replayAt or next(Requests.pending) then Requests:Tick() end
end)
