local _, GuildHelper = ...
local Feedback = {}
GuildHelper.Feedback = Feedback
Feedback.PREFIX = "GuildHelperFB"
Feedback.MAXTITLE = 60
Feedback.MAXLETTERS = 1000
Feedback.MAXBYTES = 2000
Feedback.MAXCOMMENT = 150
Feedback.CHUNK = 100
Feedback.MAXMESSAGE = 240
Feedback.KEEPDELETED = 120 * 86400
Feedback.ANSWERWINDOW = 120
Feedback.REQUESTAGAIN = 300
Feedback.BURST = 6
Feedback.ROW = 60
Feedback.DIGITS = "0123456789abcdefghijklmnopqrstuvwxyz"
Feedback.filter = "A"
Feedback.queue = {}
Feedback.queued = {}
Feedback.tokens = Feedback.BURST
Feedback.pending = {}
Feedback.answerTo = {}
Feedback.answered = {}
Feedback.indexes = {}
Feedback.draft = {
    kind = "I",
    title = "",
    text = ""
}

function Feedback:Base36(value)
    value = floor(max(0, value or 0))
    if value == 0 then return "0" end
    local text = ""
    while value > 0 do
        local digit = value % 36
        text = strsub(self.DIGITS, digit + 1, digit + 1) .. text
        value = floor(value / 36)
    end

    return text
end

function Feedback:Hash(text)
    local hash = 5381
    for i = 1, #text do
        hash = (hash * 33 + strbyte(text, i)) % 2147483647
    end

    return hash
end

function Feedback:Cut(text, limit)
    if #text <= limit then return text end
    local size = limit
    while size > 0 and strbyte(text, size + 1) and strbyte(text, size + 1) >= 128 and strbyte(text, size + 1) < 192 do
        size = size - 1
    end

    return strsub(text, 1, size)
end

function Feedback:CleanTitle(value)
    return GuildHelper.Groups:CleanText(value, 120)
end

function Feedback:CleanBody(value)
    local text = (value or ""):gsub("\r\n", "\n"):gsub("\r", "\n"):gsub("|", ""):gsub("[%z\1-\9\11-\31]", " ")
    text = text:gsub("[ \t]+\n", "\n"):gsub("\n\n\n+", "\n\n"):match("^%s*(.-)%s*$")

    return self:Cut(text, self.MAXBYTES)
end

function Feedback:Encode(text)
    return (text:gsub("\\", "\\\\"):gsub("\n", "\\n"))
end

function Feedback:Decode(text)
    return (text:gsub("\\(.)", function(char) return char == "n" and "\n" or char end))
end

function Feedback:Chunks(text)
    local chunks = {}
    local pos = 1
    while pos <= #text do
        local stop = min(#text, pos + self.CHUNK - 1)
        while stop < #text and stop > pos and strbyte(text, stop + 1) >= 128 and strbyte(text, stop + 1) < 192 do
            stop = stop - 1
        end

        tinsert(chunks, strsub(text, pos, stop))
        pos = stop + 1
    end

    return chunks
end

function Feedback:CheckGuild()
    local guild = GuildHelper.Sync:GetGuildKey()
    if guild ~= self.guild then
        self.guild = guild
        self.pending = {}
        self.answerTo = {}
        self.answered = {}
        self.indexes = {}
        self.queue = {}
        self.queued = {}
        self.selected = nil
        self.composing = false
        self.editing = nil
        self.lastRequest = nil
        self.handledIndex = nil
        if guild then self:Prune() end
    end

    return guild ~= nil
end

function Feedback:GetUnread()
    if not self.guild then return end
    GHTABPC = GHTABPC or {}
    GHTABPC.FEEDBACKUNREAD = GHTABPC.FEEDBACKUNREAD or {}
    GHTABPC.FEEDBACKUNREAD[self.guild] = GHTABPC.FEEDBACKUNREAD[self.guild] or {entries = {}, comments = {}}
    return GHTABPC.FEEDBACKUNREAD[self.guild]
end

function Feedback:CountUnread()
    if not self:CheckGuild() then return 0 end
    local unread = self:GetUnread()
    local store = self:GetStore()
    local count = 0
    for id in pairs(unread.entries) do
        if self:Find(id) then count = count + 1 else unread.entries[id] = nil end
    end
    for id, comments in pairs(unread.comments) do
        local entry = self:Find(id)
        local subscribed = entry and self:IsSubscribed(entry)
        for cid in pairs(comments) do
            local comment = store.comments[id] and store.comments[id][cid]
            if not comment or comment.deleted then
                comments[cid] = nil
            elseif subscribed then
                count = count + 1
            end
        end
        if not next(comments) then unread.comments[id] = nil end
    end
    return count
end

function Feedback:GetStore()
    if not self.guild then return nil end
    GHTAB = GHTAB or {}
    GHTAB.FEEDBACK = GHTAB.FEEDBACK or {}
    GHTAB.FEEDBACK[self.guild] = GHTAB.FEEDBACK[self.guild] or {}
    local store = GHTAB.FEEDBACK[self.guild]
    store.entries = store.entries or {}
    store.votes = store.votes or {}
    store.comments = store.comments or {}

    return store
end

function Feedback:Prune()
    local store = self:GetStore()
    if not store then return end
    local now = time()
    for id, entry in pairs(store.entries) do
        if entry.deleted and now - entry.deleted > self.KEEPDELETED then store.entries[id] = nil end
    end
end

function Feedback:Self()
    return GuildHelper.Groups:Self()
end

function Feedback:IsOwn(entry)
    return entry ~= nil and not entry.deleted and GuildHelper.Groups:IsSelfName(entry.owner)
end

function Feedback:Rev(id)
    local store = self:GetStore()
    local entry = store and store.entries[id]
    if not entry then return nil end
    if entry.deleted then return "x" end
    local parts = {}
    for voter, vote in pairs(store.votes[id] or {}) do
        tinsert(parts, voter .. "," .. vote[1] .. "," .. vote[2])
    end

    for cid, comment in pairs(store.comments[id] or {}) do
        tinsert(parts, "#" .. cid .. (comment.deleted and "x" or ""))
    end

    if entry.edited then tinsert(parts, "!" .. entry.edited) end
    if #parts == 0 then return "0" end
    table.sort(parts)

    return self:Base36(self:Hash(table.concat(parts, ";")))
end

function Feedback:ValidId(id)
    return type(id) == "string" and id ~= "" and #id <= 16 and not id:find("[^%w]")
end

function Feedback:GetIndex()
    local store = self:GetStore()
    local items = {}
    if not store then return items end
    for id in pairs(store.entries) do
        tinsert(items, id .. ":" .. self:Rev(id))
    end

    table.sort(items)

    return items
end

function Feedback:GetSum()
    local items = self:GetIndex()

    return self:Base36(self:Hash(table.concat(items, ","))), #items
end

function Feedback:Queue(message)
    if not self.guild then return end
    GuildHelper.Sync:Send(message, nil, self.PREFIX)
end

function Feedback:Pump(elapsed)
end

function Feedback:SendVotes(id)
    local store = self:GetStore()
    local votes = store and store.votes[id]
    if not votes then return end
    local head = "V~" .. id .. "~"
    local parts = {}
    local size = #head
    for voter, vote in pairs(votes) do
        local item = voter .. "," .. vote[1] .. "," .. vote[2]
        if #parts > 0 and size + #item + 1 > self.MAXMESSAGE then
            self:Queue(head .. table.concat(parts, ";"))
            parts = {}
            size = #head
        end

        tinsert(parts, item)
        size = size + #item + 1
    end

    if #parts > 0 then self:Queue(head .. table.concat(parts, ";")) end
end

function Feedback:SendEntry(id)
    local store = self:GetStore()
    local entry = store and store.entries[id]
    if not entry then return end
    if entry.deleted then
        self:Queue(table.concat({"D", id, tostring(entry.deleted), entry.owner or ""}, "~"))

        return
    end

    local chunks = self:Chunks(entry.text or "")
    local fields = {entry.edited and "U" or "E", id, entry.kind, tostring(entry.created), tostring(#chunks), entry.owner, entry.version or "", entry.author or ""}
    if entry.edited then tinsert(fields, tostring(entry.edited)) end
    tinsert(fields, "")
    local header = table.concat(fields, "~")
    self:Queue(header .. self:Cut(entry.title, 254 - #header))
    for index, chunk in ipairs(chunks) do
        self:Queue("T~" .. id .. "~" .. index .. "~" .. self:Encode(chunk))
    end

    self:SendExtras(id)
end

function Feedback:SendComment(id, cid)
    local store = self:GetStore()
    local comment = store and store.comments[id] and store.comments[id][cid]
    if not comment then return end
    if comment.deleted then
        self:Queue(table.concat({"K", id, cid, tostring(comment.deleted), comment.owner or ""}, "~"))

        return
    end

    local header = table.concat({"C", id, cid, tostring(comment.created), comment.owner, comment.author or "", ""}, "~")
    self:Queue(header .. self:Cut(comment.text, 254 - #header))
end

function Feedback:SendExtras(id)
    self:SendVotes(id)
    local store = self:GetStore()
    for cid in pairs(store and store.comments[id] or {}) do
        self:SendComment(id, cid)
    end
end

function Feedback:Request(force)
    if not self:CheckGuild() then return end
    if not force and self.lastRequest and time() - self.lastRequest < self.REQUESTAGAIN then return end
    self.lastRequest = time()
    self.handledIndex = nil
    local sum, count = self:GetSum()
    self:Queue("Q~" .. sum .. "~" .. count)
end

function Feedback:SendIndex(requester)
    self.answered[requester] = time()
    local items = self:GetIndex()
    local chunks = {}
    local current = {}
    local size = 0
    local limit = self.MAXMESSAGE - #requester - 12
    for _, item in ipairs(items) do
        if #current > 0 and size + #item + 1 > limit then
            tinsert(chunks, table.concat(current, ","))
            current = {}
            size = 0
        end

        tinsert(current, item)
        size = size + #item + 1
    end

    tinsert(chunks, table.concat(current, ","))
    for index, chunk in ipairs(chunks) do
        self:Queue(table.concat({"X", requester, tostring(index), tostring(#chunks), chunk}, "~"))
    end
end

function Feedback:OnRequest(senderKey, sum)
    if sum == self:GetSum() or self.answerTo[senderKey] then return end
    local token = {}
    self.answerTo[senderKey] = token
    C_Timer.After(random(2, 9), function()
        if self.answerTo[senderKey] ~= token then return end
        self.answerTo[senderKey] = nil
        if self:CheckGuild() then self:SendIndex(senderKey) end
    end)
end

function Feedback:OnIndex(senderKey, requester, index, total, chunk)
    if not GuildHelper.Groups:IsSelfName(requester) then
        self.answerTo[requester] = nil

        return
    end

    if self.handledIndex then return end
    local state = self.indexes[senderKey]
    if not state or state.total ~= total or time() - state.time > 60 then
        state = {
            total = total,
            parts = {},
            count = 0,
            time = time()
        }

        self.indexes[senderKey] = state
    end

    if not state.parts[index] then
        state.parts[index] = chunk
        state.count = state.count + 1
    end

    if state.count < total then return end
    self.indexes[senderKey] = nil
    self.handledIndex = senderKey
    local theirs = {}
    for i = 1, total do
        for item in string.gmatch(state.parts[i] or "", "[^,]+") do
            local id, rev = strsplit(":", item)
            if id and rev then theirs[id] = rev end
        end
    end

    self:Compare(senderKey, theirs)
end

function Feedback:Compare(senderKey, theirs)
    local store = self:GetStore()
    if not store then return end
    local wanted = {}
    for id, rev in pairs(theirs) do
        local mine = self:Rev(id)
        if mine ~= rev then
            if mine == "x" then
                self:SendEntry(id)
            else
                tinsert(wanted, id)
                if mine and rev ~= "x" then
                    if store.entries[id].edited then
                        self:SendEntry(id)
                    else
                        self:SendExtras(id)
                    end
                end
            end
        end
    end

    for id in pairs(store.entries) do
        if theirs[id] == nil then self:SendEntry(id) end
    end

    local head = "G~" .. senderKey .. "~"
    local parts = {}
    local size = #head
    for _, id in ipairs(wanted) do
        if #parts > 0 and size + #id + 1 > self.MAXMESSAGE then
            self:Queue(head .. table.concat(parts, ","))
            parts = {}
            size = #head
        end

        tinsert(parts, id)
        size = size + #id + 1
    end

    if #parts > 0 then self:Queue(head .. table.concat(parts, ",")) end
end

function Feedback:OnGet(senderKey, indexer, list)
    if not GuildHelper.Groups:IsSelfName(indexer) then return end
    if not self.answered[senderKey] or time() - self.answered[senderKey] > self.ANSWERWINDOW then return end
    for id in string.gmatch(list or "", "[^,]+") do
        self:SendEntry(id)
    end
end

function Feedback:Accepts(entry)
    local current = self:GetStore().entries[entry.id]
    if not current then return true end
    if current.deleted or current.owner ~= entry.owner then return false end

    return (entry.edited or 0) > (current.edited or 0)
end

function Feedback:ReadHeader(parts, edit)
    local id, kind, created, count, owner = parts[2], parts[3], tonumber(parts[4]), tonumber(parts[5]), parts[6]
    if not id or #id > 16 or id:find("[^%w]") or (kind ~= "I" and kind ~= "B") or not created or not count or count > 40 then return end
    local edited = edit and tonumber(parts[9])
    if edit and not edited then return end
    owner = GuildHelper.Groups:Name(owner)
    local title = self:CleanTitle(table.concat(parts, "~", edit and 10 or 9))
    if not owner or title == "" then return end
    local entry = {
        id = id,
        kind = kind,
        created = created,
        owner = owner,
        version = GuildHelper.Groups:CleanText(parts[7], 20),
        author = GuildHelper.Groups:CleanText(parts[8], 48),
        title = title,
        edited = edited and floor(edited) or nil
    }

    if not self:Accepts(entry) then return end
    local pending = self.pending[id]
    if pending and (pending.entry.edited or 0) > (entry.edited or 0) and time() - pending.time < 60 then return end
    if count == 0 then
        entry.text = ""
        self:Commit(entry)

        return
    end

    self.pending[id] = {
        entry = entry,
        total = count,
        count = 0,
        chunks = {},
        time = time()
    }
end

function Feedback:ReadChunk(message)
    local id, index, text = message:match("^T~(%w+)~(%d+)~(.*)$")
    local pending = id and self.pending[id]
    index = tonumber(index)
    if not pending or not index or index > pending.total or pending.chunks[index] then return end
    pending.chunks[index] = self:Decode(text)
    pending.count = pending.count + 1
    if pending.count < pending.total then return end
    self.pending[id] = nil
    pending.entry.text = self:CleanBody(table.concat(pending.chunks))
    self:Commit(pending.entry)
end

function Feedback:Commit(entry)
    local store = self:GetStore()
    if not store or not self:Accepts(entry) then return end
    local isNew = store.entries[entry.id] == nil
    store.entries[entry.id] = entry
    if isNew and not GuildHelper.Groups:IsSelfName(entry.owner) then self:GetUnread().entries[entry.id] = true end
    if isNew and GuildHelper.Notifications then
        GuildHelper.Notifications:NewEntry(entry.id, entry.owner, entry.created, entry.kind == "B" and "NEWBUG" or "NEWIDEA")
    end
    self:Changed()
end

function Feedback:ReadVotes(id, list)
    local store = self:GetStore()
    if not id or not list or not store then return end
    local entry = store.entries[id]
    if entry and entry.deleted then return end
    local changed = false
    for item in string.gmatch(list, "[^;]+") do
        local voter, value, stamp = strsplit(",", item)
        voter = GuildHelper.Groups:Name(voter)
        value = tonumber(value)
        stamp = tonumber(stamp)
        if voter and value and stamp and value >= -1 and value <= 1 then
            store.votes[id] = store.votes[id] or {}
            local current = store.votes[id][voter]
            if not current or stamp > current[2] or (stamp == current[2] and value < current[1]) then
                store.votes[id][voter] = {floor(value), floor(stamp)}
                changed = true
            end
        end
    end

    if changed then self:Changed() end
end

function Feedback:ReadDelete(id, stamp, owner)
    local store = self:GetStore()
    stamp = tonumber(stamp)
    if not store or not id or #id > 16 or id:find("[^%w]") or not stamp then return end
    local entry = store.entries[id]
    if entry and entry.deleted then return end
    owner = GuildHelper.Groups:Name(owner)
    if entry and owner and entry.owner ~= owner then return end
    store.entries[id] = {
        id = id,
        owner = owner or (entry and entry.owner),
        deleted = stamp
    }

    store.votes[id] = nil
    store.comments[id] = nil
    self:SetSubscribed(id, nil)
    self.pending[id] = nil
    self:Changed()
end

function Feedback:ReadComment(parts)
    local store = self:GetStore()
    local id, cid, created = parts[2], parts[3], tonumber(parts[4])
    if not store or not self:ValidId(id) or not self:ValidId(cid) or not created then return end
    local entry = store.entries[id]
    if entry and entry.deleted then return end
    local owner = GuildHelper.Groups:Name(parts[5])
    local text = GuildHelper.Groups:CleanText(table.concat(parts, "~", 7), 254)
    if not owner or text == "" then return end
    store.comments[id] = store.comments[id] or {}
    if store.comments[id][cid] then return end
    store.comments[id][cid] = {
        id = cid,
        created = created,
        owner = owner,
        author = GuildHelper.Groups:CleanText(parts[6], 48),
        text = text
    }

    if not GuildHelper.Groups:IsSelfName(owner) and (not entry or self:IsSubscribed(entry)) then
        local comments = self:GetUnread().comments
        comments[id] = comments[id] or {}
        comments[id][cid] = true
    end
    if GuildHelper.Notifications then GuildHelper.Notifications:Comment(id, store.comments[id][cid]) end
    self:Changed()
end

function Feedback:ReadCommentDelete(id, cid, stamp, owner)
    local store = self:GetStore()
    stamp = tonumber(stamp)
    if not store or not self:ValidId(id) or not self:ValidId(cid) or not stamp then return end
    local entry = store.entries[id]
    if entry and entry.deleted then return end
    store.comments[id] = store.comments[id] or {}
    local comment = store.comments[id][cid]
    if comment and comment.deleted then return end
    owner = GuildHelper.Groups:Name(owner)
    if comment and owner and comment.owner ~= owner then return end
    store.comments[id][cid] = {
        id = cid,
        owner = owner or (comment and comment.owner),
        deleted = stamp
    }

    self:Changed()
end

function Feedback:OnMessage(message, channel, sender)
    if channel ~= "GUILD" or type(message) ~= "string" or type(sender) ~= "string" then return end
    if not GuildHelper:CanAccessValues(message, sender) or not self:CheckGuild() then return end
    local senderKey = GuildHelper.Groups:Name(sender)
    if not senderKey then return end
    local own = GuildHelper.Groups:IsSelfName(sender)
    local kind = strsub(message, 1, 2)
    if kind == "T~" then
        if not own then self:ReadChunk(message) end

        return
    end

    local parts = {strsplit("~", message)}
    if kind == "Q~" then
        if not own then self:OnRequest(senderKey, parts[2]) end
    elseif kind == "X~" then
        if not own then self:OnIndex(senderKey, parts[2] or "", tonumber(parts[3]) or 0, tonumber(parts[4]) or 0, parts[5] or "") end
    elseif kind == "G~" then
        if not own then self:OnGet(senderKey, parts[2] or "", parts[3]) end
    elseif kind == "E~" then
        if not own then self:ReadHeader(parts) end
    elseif kind == "U~" then
        if not own then self:ReadHeader(parts, true) end
    elseif kind == "V~" then
        self:ReadVotes(parts[2], parts[3])
    elseif kind == "D~" then
        self:ReadDelete(parts[2], parts[3], parts[4])
    elseif kind == "C~" then
        if not own then self:ReadComment(parts) end
    elseif kind == "K~" then
        self:ReadCommentDelete(parts[2], parts[3], parts[4], parts[5])
    end
end

function Feedback:NewId(used)
    used = used or self:GetStore().entries
    local id
    repeat
        local suffix = self:Base36(random(0, 46655))
        id = self:Base36(time()) .. strrep("0", 3 - #suffix) .. suffix
    until not used[id]

    return id
end

function Feedback:GetAuthor()
    local member = GuildHelper.Members.GetSelf and GuildHelper.Members:GetSelf()
    if member and member.name then return member.name end
    local name, realm = (UnitFullName or UnitName)("player")

    return name and (realm and realm ~= "" and (name .. "-" .. realm) or name) or ""
end

function Feedback:GetDraft()
    return self.editing and self.editDraft or self.draft
end

function Feedback:Edit(id)
    local entry = self:Find(id)
    if not self:IsOwn(entry) then return end
    self.editing = id
    self.editDraft = {
        kind = entry.kind,
        title = entry.title,
        text = entry.text or ""
    }

    self.composing = true
    self.confirm = nil
    self:Refresh()
    if self.titleBox then self.titleBox:SetFocus() end
end

function Feedback:StopEditing()
    self.editing = nil
    self.editDraft = nil
end

function Feedback:Save()
    local entry = self:Find(self.editing)
    local draft = self.editDraft
    if not self:IsOwn(entry) or not draft then return end
    local title = self:CleanTitle(draft.title)
    if title == "" then return end
    local text = self:CleanBody(draft.text)
    self.composing = false
    self.selected = entry.id
    self:StopEditing()
    if title ~= entry.title or text ~= (entry.text or "") or draft.kind ~= entry.kind then
        entry.kind = draft.kind
        entry.title = title
        entry.text = text
        entry.edited = max(time(), (entry.edited or entry.created or 0) + 1)
        self.pending[entry.id] = nil
        self:SendEntry(entry.id)
    end

    self:Changed()
end

function Feedback:Submit()
    if not self:CheckGuild() then return end
    if self.editing then return self:Save() end
    local title = self:CleanTitle(self.draft.title)
    local owner = self:Self()
    if title == "" or not owner then return end
    local entry = {
        id = self:NewId(),
        kind = self.draft.kind,
        created = time(),
        owner = owner,
        version = GuildHelper.Groups:CleanText(GuildHelper:GetVersion() or "", 20),
        author = GuildHelper.Groups:CleanText(self:GetAuthor(), 48),
        title = title,
        text = self:CleanBody(self.draft.text)
    }

    self:GetStore().entries[entry.id] = entry
    self:SetSubscribed(entry.id, true)
    self:SendEntry(entry.id)
    self.draft.title = ""
    self.draft.text = ""
    self.composing = false
    self.selected = entry.id
    if self.titleBox then
        self.titleBox:SetText("")
        self.textBox:SetText("")
    end

    self:Changed()
end

function Feedback:Delete(id)
    local store = self:GetStore()
    local entry = store and store.entries[id]
    if not self:IsOwn(entry) then return end
    store.entries[id] = {
        id = id,
        owner = entry.owner,
        deleted = time()
    }

    store.votes[id] = nil
    store.comments[id] = nil
    self:SetSubscribed(id, nil)
    self:SendEntry(id)
    self.selected = nil
    self:Changed()
end

function Feedback:AddComment(id, value)
    local store = self:GetStore()
    local owner = self:Self()
    local text = GuildHelper.Groups:CleanText(value, 254)
    if not self:Find(id) or not owner or text == "" then return false end
    store.comments[id] = store.comments[id] or {}
    local comment = {
        id = self:NewId(store.comments[id]),
        created = time(),
        owner = owner,
        author = GuildHelper.Groups:CleanText(self:GetAuthor(), 48),
        text = text
    }

    store.comments[id][comment.id] = comment
    self:SetSubscribed(id, true)
    self:SendComment(id, comment.id)
    self.scrollComments = true
    self:Changed()

    return true
end

function Feedback:IsOwnComment(comment)
    return comment ~= nil and not comment.deleted and GuildHelper.Groups:IsSelfName(comment.owner)
end

function Feedback:DeleteComment(id, cid)
    local store = self:GetStore()
    local comment = store and store.comments[id] and store.comments[id][cid]
    if not self:IsOwnComment(comment) then return end
    store.comments[id][cid] = {
        id = cid,
        owner = comment.owner,
        deleted = time()
    }

    self:SendComment(id, cid)
    self:Changed()
end

function Feedback:GetSubscriptions()
    local subscriptions = GuildHelper:GetConfig("FEEDBACKSUBSCRIPTIONS", {})
    subscriptions[self.guild] = subscriptions[self.guild] or {}

    return subscriptions[self.guild]
end

function Feedback:SetSubscribed(id, subscribed)
    self:GetSubscriptions()[id] = subscribed
end

function Feedback:IsSubscribed(entry)
    local subscribed = self:GetSubscriptions()[entry.id]
    if subscribed ~= nil then return subscribed end
    if self:IsOwn(entry) then return true end
    for _, comment in pairs(self:GetStore().comments[entry.id] or {}) do
        if self:IsOwnComment(comment) then return true end
    end

    return false
end

function Feedback:GetComments(id)
    local list = {}
    local store = self:GetStore()
    for _, comment in pairs(store and store.comments[id] or {}) do
        if not comment.deleted then tinsert(list, comment) end
    end

    table.sort(list, function(a, b)
        if a.created ~= b.created then return a.created < b.created end

        return a.id < b.id
    end)

    return list
end

function Feedback:GetVote(id, voter)
    local store = self:GetStore()
    local vote = store and store.votes[id] and store.votes[id][voter or self:Self() or ""]

    return vote and vote[1] or 0
end

function Feedback:Vote(id, value)
    local store = self:GetStore()
    local voter = self:Self()
    local entry = store and store.entries[id]
    if not entry or entry.deleted or not voter then return end
    if self:GetVote(id) == value then value = 0 end
    store.votes[id] = store.votes[id] or {}
    local current = store.votes[id][voter]
    store.votes[id][voter] = {value, max(time(), current and current[2] + 1 or 0)}
    self:Queue("V~" .. id .. "~" .. voter .. "," .. value .. "," .. store.votes[id][voter][2])
    self:Changed()
end

function Feedback:Count(id)
    local store = self:GetStore()
    local up, down = 0, 0
    for _, vote in pairs(store and store.votes[id] or {}) do
        if vote[1] > 0 then
            up = up + 1
        elseif vote[1] < 0 then
            down = down + 1
        end
    end

    return up, down
end

function Feedback:GetList(filter)
    local list = {}
    local store = self:GetStore()
    if not store then return list end
    for _, entry in pairs(store.entries) do
        if not entry.deleted and (filter == nil or filter == "A" or entry.kind == filter) then tinsert(list, entry) end
    end

    table.sort(list, function(a, b)
        if a.created ~= b.created then return a.created > b.created end

        return a.id > b.id
    end)

    return list
end

function Feedback:Find(id)
    local store = self:GetStore()
    local entry = id and store and store.entries[id]
    if entry and not entry.deleted then return entry end

    return nil
end

function Feedback:FormatDate(stamp)
    return date("%Y-%m-%d %H:%M", stamp or 0)
end

function Feedback:Changed()
    self:Refresh()
end

function Feedback:Text(parent, key, x, y, size, color)
    return GuildHelper.Groups:Text(parent, key, x, y, size, color)
end

function Feedback:UpdateThumb(scroll)
    local thumb = scroll.ghThumb
    local range = scroll:GetVerticalScrollRange()
    local view = scroll:GetHeight()
    if range <= 0 or view <= 0 then
        thumb:Hide()

        return
    end

    local track = view - 4
    local height = max(20, track * view / (view + range))
    thumb:SetHeight(height)
    thumb:ClearAllPoints()
    thumb:SetPoint("TOPLEFT", scroll, "TOPRIGHT", thumb.gap, -2 - (track - height) * min(1, scroll:GetVerticalScroll() / range))
    thumb:Show()
end

function Feedback:AddThumb(scroll, gap)
    local thumb = CreateFrame("Button", nil, scroll:GetParent())
    thumb:SetWidth(4)
    thumb:SetFrameLevel(scroll:GetFrameLevel() + 5)
    thumb.gap = gap or 1
    GuildHelper.Theme:Round(thumb, "thumb", 2)
    thumb:Hide()
    thumb:SetScript("OnMouseDown", function(sel)
        sel.startY = select(2, GetCursorPosition()) / sel:GetEffectiveScale()
        sel.startScroll = scroll:GetVerticalScroll()
        sel:SetScript("OnUpdate", function()
            local y = select(2, GetCursorPosition()) / sel:GetEffectiveScale()
            local free = scroll:GetHeight() - 4 - sel:GetHeight()
            local range = scroll:GetVerticalScrollRange()
            if free <= 0 or range <= 0 then return end
            scroll:SetVerticalScroll(min(max(sel.startScroll + (sel.startY - y) / free * range, 0), range))
        end)
    end)

    thumb:SetScript("OnMouseUp", function(sel) sel:SetScript("OnUpdate", nil) end)
    thumb:SetScript("OnHide", function(sel) sel:SetScript("OnUpdate", nil) end)
    scroll.ghThumb = thumb
    scroll:HookScript("OnScrollRangeChanged", function() self:UpdateThumb(scroll) end)
    scroll:HookScript("OnVerticalScroll", function() self:UpdateThumb(scroll) end)
    scroll:HookScript("OnSizeChanged", function() self:UpdateThumb(scroll) end)
    scroll:HookScript("OnShow", function() self:UpdateThumb(scroll) end)
end

function Feedback:CreateVote(parent, icon, tooltip, value)
    local Theme, Members = GuildHelper.Theme, GuildHelper.Members
    local button = Members:CreatePill(parent, "")
    button.icon = Theme:Icon(button, icon, 16, "text", "OVERLAY")
    button.icon:SetPoint("LEFT", button, "LEFT", 12, 0)
    button.text:ClearAllPoints()
    button.text:SetPoint("LEFT", button.icon, "RIGHT", 7, 0)
    button:SetWidth(72)
    button:HookScript("OnEnter", function(sel)
        GameTooltip:SetOwner(sel, "ANCHOR_TOP")
        GameTooltip:SetText(GuildHelper:Trans(tooltip))
        GameTooltip:Show()
    end)

    button:HookScript("OnLeave", function() GameTooltip:Hide() end)
    button:SetScript("OnClick", function()
        if self.selected then self:Vote(self.selected, value) end
    end)

    return button
end

function Feedback:SetVote(button, count, active)
    button.text:SetText(tostring(count))
    GuildHelper.Members:SetPillActive(button, active)
    GuildHelper.Theme:SetKey(button.icon, active and "accent" or "text")
end

function Feedback:BuildForm(side)
    local Theme, Members, Groups = GuildHelper.Theme, GuildHelper.Members, GuildHelper.Groups
    local form = CreateFrame("Frame", nil, side)
    form:SetAllPoints(side)
    self.form = form
    self:Text(form, "LID_FBTYPE", 16, -46)
    self.ideaPill = Members:CreatePill(form, "")
    self.ideaPill:SetPoint("TOPLEFT", form, "TOPLEFT", 120, -39)
    self.ideaPill:SetScript("OnClick", function()
        self:GetDraft().kind = "I"
        self:Refresh()
    end)

    self.bugPill = Members:CreatePill(form, "")
    self.bugPill:SetPoint("LEFT", self.ideaPill, "RIGHT", 8, 0)
    self.bugPill:SetScript("OnClick", function()
        self:GetDraft().kind = "B"
        self:Refresh()
    end)

    self:Text(form, "LID_FBTITLE", 16, -82)
    self.titleBox = Groups:CreateBox(form, self.MAXTITLE)
    self.titleBox:SetPoint("TOPLEFT", form, "TOPLEFT", 16, -100)
    self.titleBox:SetPoint("TOPRIGHT", form, "TOPRIGHT", -16, -100)
    self.titleBox:SetScript("OnTextChanged", function(box)
        self:GetDraft().title = box:GetText()
        self:RefreshForm()
    end)

    self.titleBox:SetScript("OnTabPressed", function() self.textBox:SetFocus() end)
    self:Text(form, "LID_FBTEXT", 16, -140)
    self.counter = self:Text(form, nil, 0, 0, 11)
    self.counter:ClearAllPoints()
    self.counter:SetPoint("TOPRIGHT", form, "TOPRIGHT", -16, -140)
    self.counter:SetJustifyH("RIGHT")
    local panel = CreateFrame("Frame", nil, form)
    panel:SetPoint("TOPLEFT", form, "TOPLEFT", 16, -158)
    panel:SetPoint("BOTTOMRIGHT", form, "BOTTOMRIGHT", -16, 60)
    panel.ghNoInside = true
    Theme:Panel(panel, "control", "border", 6)
    local scroll = CreateFrame("ScrollFrame", nil, panel)
    scroll:SetPoint("TOPLEFT", panel, "TOPLEFT", 9, -8)
    scroll:SetPoint("BOTTOMRIGHT", panel, "BOTTOMRIGHT", -9, 8)
    local box = CreateFrame("EditBox", nil, scroll)
    box:SetMultiLine(true)
    box:SetAutoFocus(false)
    box:SetMaxLetters(self.MAXLETTERS)
    box:SetSize(200, 20)
    box:SetTextInsets(0, 0, 2, 2)
    Theme:Track(box, "text", "text", 13)
    scroll:SetScrollChild(box)
    scroll:SetScript("OnSizeChanged", function(_, width) box:SetWidth(max(1, width or 1)) end)
    scroll:EnableMouseWheel(true)
    scroll:SetScript("OnMouseWheel", function(sel, delta) sel:SetVerticalScroll(min(max(sel:GetVerticalScroll() - delta * 26, 0), sel:GetVerticalScrollRange())) end)
    self:AddThumb(scroll, 3)
    box:SetScript("OnCursorChanged", function(_, _, y, _, height)
        local top = -y
        local view = scroll:GetVerticalScroll()
        local size = scroll:GetHeight()
        if top < view then
            scroll:SetVerticalScroll(top)
        elseif top + height > view + size then
            scroll:SetVerticalScroll(top + height - size)
        end
    end)

    box:SetScript("OnTextChanged", function(sel)
        self:GetDraft().text = sel:GetText()
        self:RefreshForm()
    end)

    box:SetScript("OnEscapePressed", function(sel) sel:ClearFocus() end)
    panel:EnableMouse(true)
    panel:SetScript("OnMouseDown", function() box:SetFocus() end)
    self.textBox = box
    self.version = self:Text(form, nil, 0, 0, 11)
    self.version:ClearAllPoints()
    self.version:SetPoint("BOTTOMLEFT", form, "BOTTOMLEFT", 16, 25)
    self.cancel = Members:CreateButton(form, "LID_FBCANCEL")
    self.cancel:SetPoint("BOTTOMRIGHT", form, "BOTTOMRIGHT", -16, 14)
    self.cancel:SetWidth(110)
    self.cancel:SetScript("OnClick", function()
        self.composing = false
        self:StopEditing()
        self:ClearFocus()
        self:Refresh()
    end)

    self.submit = Members:CreateButton(form, "LID_FBSUBMIT", true)
    self.submit:SetPoint("RIGHT", self.cancel, "LEFT", -10, 0)
    self.submit:SetWidth(130)
    self.submit:SetScript("OnClick", function()
        self:ClearFocus()
        self:Submit()
    end)
end

function Feedback:BuildDetail(side)
    local Members, Dashboard = GuildHelper.Members, GuildHelper.Dashboard
    local detail = CreateFrame("Frame", nil, side)
    detail:SetAllPoints(side)
    self.detail = detail
    self.detailKind = self:Text(detail, nil, 16, -40, 12, "accent")
    self.detailDate = self:Text(detail, nil, 0, 0, 11)
    self.detailDate:ClearAllPoints()
    self.detailDate:SetPoint("TOPRIGHT", detail, "TOPRIGHT", -16, -40)
    self.detailDate:SetJustifyH("RIGHT")
    self.detailTitle = self:Text(detail, nil, 16, -60, 15, "text")
    self.detailTitle:SetPoint("RIGHT", detail, "RIGHT", -16, 0)
    self.detailTitle:SetWordWrap(true)
    self.detailTitle:SetHeight(38)
    self.detailTitle:SetJustifyV("TOP")
    self.detailMeta = self:Text(detail, nil, 16, -100, 12)
    self.detailMeta:SetPoint("RIGHT", detail, "RIGHT", -16, 0)
    self.body = Dashboard:CreateTextCard(detail, "LID_FBTEXT")
    self.body:SetPoint("TOPLEFT", detail, "TOPLEFT", 8, -124)
    self.body:SetPoint("TOPRIGHT", detail, "TOPRIGHT", -8, -124)
    self.body:SetHeight(110)
    self:AddThumb(self.body.scroll)
    self.comments = Dashboard:CreateList(Dashboard:CreateCard(detail, "LID_FBCOMMENTS"))
    self.comments:SetPoint("TOPLEFT", self.body, "BOTTOMLEFT", 0, -8)
    self.comments:SetPoint("BOTTOMRIGHT", detail, "BOTTOMRIGHT", -8, 134)
    self.comments.rows = {}
    self:AddThumb(self.comments.scroll)
    self.comments.body:SetScript("OnSizeChanged", function(body, width)
        if width and width ~= self.commentWidth then
            self.commentWidth = width
            self:Refresh()
        end
    end)

    self.noComments = self:Text(self.comments, "LID_FBNOCOMMENTS", 16, -36)
    self.send = Members:CreateButton(detail, "LID_FBSEND")
    self.send:SetPoint("BOTTOMRIGHT", detail, "BOTTOMRIGHT", -16, 94)
    self.send:SetWidth(100)
    self.send:SetScript("OnClick", function() self:PostComment() end)
    self.commentBox = GuildHelper.Groups:CreateBox(detail, self.MAXCOMMENT)
    self.commentBox:SetPoint("LEFT", detail, "LEFT", 16, 0)
    self.commentBox:SetPoint("RIGHT", self.send, "LEFT", -8, 0)
    self.commentBox:SetPoint("TOP", self.send, "TOP", 0, -2)
    self.commentBox:SetScript("OnEnterPressed", function() self:PostComment() end)
    self.commentBox:SetScript("OnTextChanged", function(box) self.send:SetEnabled(GuildHelper.Groups:CleanText(box:GetText(), 254) ~= "") end)
    self.up = self:CreateVote(detail, "thumbup", "LID_FBUPVOTE", 1)
    self.up:SetPoint("BOTTOMLEFT", detail, "BOTTOMLEFT", 16, 16)
    self.down = self:CreateVote(detail, "thumbdown", "LID_FBDOWNVOTE", -1)
    self.down:SetPoint("LEFT", self.up, "RIGHT", 8, 0)
    self.bug = self:CreateVote(detail, "bug", "LID_FBAFFECTED", 1)
    self.bug:SetPoint("BOTTOMLEFT", detail, "BOTTOMLEFT", 16, 16)
    self.delete = Members:CreateButton(detail, "LID_FBDELETE")
    self.delete:SetPoint("BOTTOMRIGHT", detail, "BOTTOMRIGHT", -16, 54)
    self.subscribe = Members:CreateButton(detail, "LID_FBSUBSCRIBE")
    self.subscribe:SetPoint("BOTTOMRIGHT", detail, "BOTTOMRIGHT", -16, 14)
    self.subscribe:SetWidth(160)
    self.subscribe:SetScript("OnClick", function()
        local entry = self:Find(self.selected)
        if not entry then return end
        self:SetSubscribed(entry.id, not self:IsSubscribed(entry))
        self:RefreshDetail()
    end)
    self.delete:SetWidth(130)
    self.edit = Members:CreateButton(detail, "LID_FBEDIT")
    self.edit:SetPoint("RIGHT", self.delete, "LEFT", -8, 0)
    self.edit:SetWidth(100)
    self.edit:SetScript("OnClick", function() self:Edit(self.selected) end)
    self.delete:SetScript("OnClick", function()
        if self.confirm == self.selected then
            self.confirm = nil
            self:Delete(self.selected)
        else
            self.confirm = self.selected
            self:RefreshDetail()
        end
    end)

    self.noSelection = self:Text(detail, "LID_FBSELECT", 16, -44)
    self.noSelection:SetPoint("RIGHT", detail, "RIGHT", -16, 0)
    self.noSelection:SetWordWrap(true)
end

function Feedback:Compose()
    self:StopEditing()
    self.composing = true
    self.confirm = nil
    self:Refresh()
    if self.titleBox then self.titleBox:SetFocus() end
end

function Feedback:ClearFocus()
    if self.titleBox then
        self.titleBox:ClearFocus()
        self.textBox:ClearFocus()
        self.commentBox:ClearFocus()
    end
end

function Feedback:PostComment()
    if not self.commentBox or not self.selected then return end
    if self:AddComment(self.selected, self.commentBox:GetText()) then self.commentBox:SetText("") end
end

function Feedback:GetCommentRow(index)
    local Theme = GuildHelper.Theme
    local rows = self.comments.rows
    if rows[index] then return rows[index] end
    local row = CreateFrame("Frame", nil, self.comments.body)
    row.remove = CreateFrame("Button", nil, row)
    row.remove:SetSize(18, 18)
    row.remove:SetPoint("TOPRIGHT", row, "TOPRIGHT", -6, -2)
    row.remove.icon = Theme:Icon(row.remove, "close", 8, "muted")
    row.remove.icon:SetPoint("CENTER", row.remove, "CENTER", 0, 0)
    row.remove:SetScript("OnEnter", function(sel)
        Theme:SetKey(sel.icon, "text")
        GameTooltip:SetOwner(sel, "ANCHOR_TOP")
        GameTooltip:SetText(GuildHelper:Trans("LID_FBDELETECOMMENT"))
        GameTooltip:Show()
    end)

    row.remove:SetScript("OnLeave", function(sel)
        Theme:SetKey(sel.icon, "muted")
        GameTooltip:Hide()
    end)

    row.remove:SetScript("OnClick", function() self:DeleteComment(self.selected, row.cid) end)
    row.head = self:Text(row, nil, 10, -4, 11)
    row.head:SetPoint("RIGHT", row.remove, "LEFT", -6, 0)
    row.text = self:Text(row, nil, 10, -20, 12.5, "text")
    row.text:SetWordWrap(true)
    row.text:SetJustifyV("TOP")
    rows[index] = row

    return row
end

function Feedback:RefreshComments(entry)
    local body = self.comments.body
    local list = self:GetComments(entry.id)
    local width = max(1, body:GetWidth() - 20)
    local y = 0
    for index, comment in ipairs(list) do
        local row = self:GetCommentRow(index)
        row.cid = comment.id
        row:ClearAllPoints()
        row:SetPoint("TOPLEFT", body, "TOPLEFT", 0, -y)
        row:SetPoint("TOPRIGHT", body, "TOPRIGHT", 0, -y)
        row.head:SetText((Ambiguate and Ambiguate(comment.author or "", "guild") or comment.author or "") .. " · " .. self:FormatDate(comment.created))
        row.text:SetWidth(width)
        row.text:SetText(comment.text)
        row.remove:SetShown(self:IsOwnComment(comment))
        local height = 26 + row.text:GetStringHeight()
        row:SetHeight(height)
        row:Show()
        y = y + height
    end

    for index = #list + 1, #self.comments.rows do
        self.comments.rows[index]:Hide()
    end

    body:SetHeight(max(1, y))
    self.noComments:SetShown(#list == 0)
    if self.scrollComments then
        self.scrollComments = nil
        C_Timer.After(0, function()
            local scroll = self.comments.scroll
            scroll:SetVerticalScroll(scroll:GetVerticalScrollRange())
        end)
    end
end

function Feedback:Build(content)
    local Members, Window, Dashboard = GuildHelper.Members, GuildHelper.Window, GuildHelper.Dashboard
    self.content = content
    local title = Window:CreatePageTitle(content, "LID_FEEDBACK")
    self.pills = {}
    local previous = title
    for index, key in ipairs({"A", "I", "B"}) do
        local pill = Members:CreatePill(content, "")
        pill:SetPoint("LEFT", previous, "RIGHT", index == 1 and 24 or 8, 0)
        pill:SetScript("OnClick", function()
            self.filter = key
            self:Refresh()
        end)

        self.pills[key] = pill
        previous = pill
    end

    self.newButton = Members:CreateButton(content, "LID_FBNEW", true)
    self.newButton:SetPoint("TOPRIGHT", content, "TOPRIGHT", -Window.MARGIN - 42, -23)
    self.newButton:SetWidth(150)
    self.newButton:SetScript("OnClick", function() self:Compose() end)
    self.hint = self:Text(content, "LID_FBHINT", Window.PADDING, -62, 11)
    self.hint:SetPoint("RIGHT", content, "RIGHT", -Window.MARGIN, 0)
    self.side = Dashboard:CreateCard(content, "LID_FBDETAIL")
    self.side:SetPoint("TOPRIGHT", content, "TOPRIGHT", -Window.MARGIN, -84)
    self.side:SetPoint("BOTTOMRIGHT", content, "BOTTOMRIGHT", -Window.MARGIN, Members.BOTTOM)
    self.side:SetWidth(430)
    self.list = Dashboard:CreateList(Dashboard:CreateCard(content, "LID_FBLIST"))
    self.list:SetPoint("TOPLEFT", content, "TOPLEFT", Window.PADDING, -84)
    self.list:SetPoint("BOTTOMRIGHT", self.side, "BOTTOMLEFT", -12, 0)
    self:AddThumb(self.list.scroll)
    self.empty = self:Text(self.list, "LID_FBNONE", 16, -42)
    self.empty:SetPoint("RIGHT", self.list, "RIGHT", -16, 0)
    self.empty:SetWordWrap(true)
    self.rows = {}
    self:BuildForm(self.side)
    self:BuildDetail(self.side)
    content.OnPageShow = function()
        self:Request()
        self:Refresh()
    end

    content.OnPageHide = function()
        self:ClearFocus()
        self.confirm = nil
    end

    self:Refresh()
end

function Feedback:GetRow(index)
    local Theme = GuildHelper.Theme
    local row = self.rows[index]
    if row then return row end
    row = CreateFrame("Button", nil, self.list.body)
    row:SetPoint("TOPLEFT", self.list.body, "TOPLEFT", 0, -(index - 1) * self.ROW)
    row:SetPoint("TOPRIGHT", self.list.body, "TOPRIGHT", 0, -(index - 1) * self.ROW)
    row:SetHeight(self.ROW - 4)
    row.bg = Theme:Round(row, "navActive", 6)
    row.tag = self:Text(row, nil, 0, 0, 12, "accent")
    row.tag:ClearAllPoints()
    row.tag:SetPoint("TOPRIGHT", row, "TOPRIGHT", -10, -9)
    row.tag:SetJustifyH("RIGHT")
    row.title = self:Text(row, nil, 10, -8, 14, "text")
    row.title:SetPoint("RIGHT", row.tag, "LEFT", -10, 0)
    row.downCount = self:Text(row, nil, 0, 0, 12, "text")
    row.downCount:ClearAllPoints()
    row.downCount:SetPoint("BOTTOMRIGHT", row, "BOTTOMRIGHT", -10, 10)
    row.downIcon = Theme:Icon(row, "thumbdown", 13, "muted")
    row.downIcon:SetPoint("RIGHT", row.downCount, "LEFT", -4, 0)
    row.upCount = self:Text(row, nil, 0, 0, 12, "text")
    row.upCount:ClearAllPoints()
    row.upCount:SetPoint("RIGHT", row.downIcon, "LEFT", -12, 0)
    row.upIcon = Theme:Icon(row, "thumbup", 13, "muted")
    row.upIcon:SetPoint("RIGHT", row.upCount, "LEFT", -4, 0)
    row.info = self:Text(row, nil, 10, -32, 12)
    row.info:SetPoint("RIGHT", row.upIcon, "LEFT", -12, 0)
    row:SetScript("OnClick", function(sel)
        self.selected = sel.id
        self.composing = false
        self:StopEditing()
        self.confirm = nil
        self:ClearFocus()
        self:Refresh()
    end)

    self.rows[index] = row

    return row
end

function Feedback:FillRow(row, entry)
    local up, down = self:Count(entry.id)
    local bug = entry.kind == "B"
    row.id = entry.id
    row.title:SetText(entry.title)
    row.tag:SetText(GuildHelper:Trans(bug and "LID_FBBUG" or "LID_FBIDEA"))
    local info = {Ambiguate and Ambiguate(entry.author or "", "guild") or entry.author or "", "v" .. (entry.version or "?"), self:FormatDate(entry.created)}
    local comments = #self:GetComments(entry.id)
    if comments > 0 then tinsert(info, format(GuildHelper:Trans("LID_FBCOMMENTCOUNT"), comments)) end
    row.info:SetText(table.concat(info, " · "))
    row.upIcon:SetTexture(GuildHelper.Theme.MEDIA .. (bug and "bug" or "thumbup"))
    row.upCount:SetText(tostring(up))
    row.downIcon:SetShown(not bug)
    row.downCount:SetShown(not bug)
    row.downCount:SetText(bug and "" or tostring(down))
    row.bg:SetShown(not self.composing and entry.id == self.selected)
    row:Show()
end

function Feedback:RefreshList()
    local Members = GuildHelper.Members
    local all = self:GetList("A")
    local ideas, bugs = 0, 0
    for _, entry in ipairs(all) do
        if entry.kind == "B" then
            bugs = bugs + 1
        else
            ideas = ideas + 1
        end
    end

    for key, pill in pairs(self.pills) do
        local label = key == "I" and "LID_FBIDEAS" or (key == "B" and "LID_FBBUGS" or "LID_FBALL")
        local count = key == "I" and ideas or (key == "B" and bugs or #all)
        Members:SetPillText(pill, GuildHelper:Trans(label) .. " (" .. count .. ")")
        Members:SetPillActive(pill, self.filter == key)
    end

    local list = self:GetList(self.filter)
    local unread = self:GetUnread()
    if not self:Find(self.selected) then self.selected = list[1] and list[1].id end
    for index, entry in ipairs(list) do
        if unread then unread.entries[entry.id] = nil end
        self:FillRow(self:GetRow(index), entry)
    end

    for index = #list + 1, #self.rows do
        self.rows[index]:Hide()
    end

    self.list.body:SetHeight(max(1, #list * self.ROW))
    self.empty:SetShown(#list == 0)
end

function Feedback:RefreshForm()
    if not self.form or not self.form:IsShown() then return end
    local Members = GuildHelper.Members
    local draft = self:GetDraft()
    local entry = self.editing and self:Find(self.editing)
    Members:SetPillText(self.ideaPill, GuildHelper:Trans("LID_FBIDEA"))
    Members:SetPillText(self.bugPill, GuildHelper:Trans("LID_FBBUG"))
    Members:SetPillActive(self.ideaPill, draft.kind == "I")
    Members:SetPillActive(self.bugPill, draft.kind == "B")
    if self.titleBox:GetText() ~= draft.title then self.titleBox:SetText(draft.title) end
    if self.textBox:GetText() ~= draft.text then self.textBox:SetText(draft.text) end
    self.counter:SetText(format("%d / %d", self.textBox.GetNumLetters and self.textBox:GetNumLetters() or #draft.text, self.MAXLETTERS))
    self.version:SetText(format(GuildHelper:Trans("LID_FBVERSION"), (entry and entry.version) or GuildHelper:GetVersion() or "?"))
    GuildHelper.Theme:SetTrans(self.submit.text, self.editing and "LID_FBSAVE" or "LID_FBSUBMIT")
    self.submit:SetEnabled(IsInGuild() and self:CleanTitle(draft.title) ~= "")
end

function Feedback:RefreshDetail()
    local entry = self:Find(self.selected)
    local shown = entry ~= nil
    self.noSelection:SetShown(not shown)
    for _, region in ipairs({self.detailKind, self.detailDate, self.detailTitle, self.detailMeta, self.body, self.comments, self.commentBox, self.send, self.subscribe}) do
        region:SetShown(shown)
    end

    self.up:SetShown(shown and entry.kind ~= "B")
    self.down:SetShown(shown and entry.kind ~= "B")
    self.bug:SetShown(shown and entry.kind == "B")
    self.delete:SetShown(self:IsOwn(entry))
    self.edit:SetShown(self:IsOwn(entry))
    if not shown then return end
    GuildHelper.Theme:SetTrans(self.subscribe.text, self:IsSubscribed(entry) and "LID_FBSUBSCRIBED" or "LID_FBSUBSCRIBE")
    local up, down = self:Count(entry.id)
    local vote = self:GetVote(entry.id)
    self.detailKind:SetText(GuildHelper:Trans(entry.kind == "B" and "LID_FBBUG" or "LID_FBIDEA"))
    self.detailDate:SetText(self:FormatDate(entry.created))
    self.detailTitle:SetText(entry.title)
    local meta = format(GuildHelper:Trans("LID_FBBY"), entry.author or "?") .. " · " .. format(GuildHelper:Trans("LID_FBVERSION"), entry.version or "?")
    if entry.edited then meta = meta .. " · " .. format(GuildHelper:Trans("LID_FBEDITED"), self:FormatDate(entry.edited)) end
    self.detailMeta:SetText(meta)
    self.body.text:SetText(entry.text ~= "" and entry.text or "-")
    self.body:ResizeText()
    self:SetVote(self.up, up, vote > 0)
    self:SetVote(self.down, down, vote < 0)
    self:SetVote(self.bug, up, vote > 0)
    if self.confirm ~= entry.id then self.confirm = nil end
    GuildHelper.Theme:SetTrans(self.delete.text, self.confirm and "LID_FBCONFIRM" or "LID_FBDELETE")
    self.send:SetEnabled(IsInGuild() and GuildHelper.Groups:CleanText(self.commentBox:GetText(), 254) ~= "")
    self:RefreshComments(entry)
    local unread = self:GetUnread()
    if unread then unread.comments[entry.id] = nil end
end

function Feedback:Refresh()
    if not self.content or not self.content:IsVisible() or not self.list then
        GuildHelper.Window:UpdateNavCount("feedback", self:CountUnread())
        return
    end
    self:CheckGuild()
    if self.editing and not self:IsOwn(self:Find(self.editing)) then
        self:StopEditing()
        self.composing = false
    end

    self:RefreshList()
    self.form:SetShown(self.composing)
    self.detail:SetShown(not self.composing)
    GuildHelper.Theme:SetTrans(self.side.title, self.editing and "LID_FBEDITENTRY" or (self.composing and "LID_FBNEW" or "LID_FBDETAIL"), true)
    self.newButton:SetEnabled(not self.composing)
    if self.composing then
        self:RefreshForm()
    else
        self:RefreshDetail()
    end
    GuildHelper.Window:UpdateNavCount("feedback", self:CountUnread())
end

GuildHelper.Window:SetPageBuilder("feedback", function(content) Feedback:Build(content) end)
GuildHelper.Window:OnRebuild(function()
    Feedback.content = nil
    Feedback.titleBox = nil
    Feedback.commentBox = nil
    Feedback.commentWidth = nil
end)

GuildHelper.Theme:OnRefresh(function() Feedback:Refresh() end)
Feedback.events = CreateFrame("Frame")
Feedback.events:RegisterEvent("PLAYER_LOGIN")
Feedback.events:RegisterEvent("PLAYER_GUILD_UPDATE")
Feedback.events:RegisterEvent("CHAT_MSG_ADDON")
Feedback.events:SetScript("OnEvent", function(_, event, prefix, message, channel, sender)
    if event == "CHAT_MSG_ADDON" then
        if prefix == Feedback.PREFIX then Feedback:OnMessage(message, channel, sender) end

        return
    end

    if event == "PLAYER_LOGIN" then
        if C_ChatInfo and C_ChatInfo.RegisterAddonMessagePrefix then
            C_ChatInfo.RegisterAddonMessagePrefix(Feedback.PREFIX)
        elseif RegisterAddonMessagePrefix then
            RegisterAddonMessagePrefix(Feedback.PREFIX)
        end

        C_Timer.After(15, function() Feedback:Request() end)
    elseif Feedback.guild ~= GuildHelper.Sync:GetGuildKey() then
        C_Timer.After(5, function() Feedback:Request() end)
    end

    Feedback:CheckGuild()
    Feedback:Refresh()
end)

Feedback.events:SetScript("OnUpdate", function(_, elapsed) Feedback:Pump(elapsed) end)
