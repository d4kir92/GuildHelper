local _, GuildHelper = ...
local Share = {}
GuildHelper.FeedbackShare = Share
Share.PREFIX = "GHFeedShare"
Share.CHANNEL = "GuildHelperDev"
Share.PASSWORD = "ghfs7311"
Share.DEVELOPERS = {"Dakir Klaue", "Dakir Flitzhuf", "Xari Mondwächter"}
Share.COOLDOWN = 60
Share.STAY = 300
Share.ANSWERAGAIN = 600
Share.DETAILWINDOW = 1800
Share.DETAILAGAIN = 30
Share.MAXENTRIES = 60
Share.JOINAGAIN = 60
Share.claims = {}
Share.answered = {}
Share.detailSent = {}
Share.responders = {}
Share.chunks = {}
Share.asked = {}
function Share:IsDeveloperName(name)
    local key = GuildHelper.Groups:Name(name)
    if key == nil then return false end
    for _, developer in ipairs(self.DEVELOPERS) do
        if GuildHelper.Groups:Name(developer) == key then return true end
    end

    return false
end

function Share:IsDeveloper()
    for _, developer in ipairs(self.DEVELOPERS) do
        if GuildHelper.Groups:IsSelfName(developer) then return true end
    end

    return false
end

function Share:IsOfficer()
    if not IsInGuild() then return false end
    if GuildHelper.Bridge and GuildHelper.Bridge:CanEdit() then return true end
    if C_GuildInfo and C_GuildInfo.CanViewOfficerNote then return C_GuildInfo.CanViewOfficerNote() == true end

    return CanViewOfficerNote ~= nil and CanViewOfficerNote() == true
end

function Share:GetChannelID()
    return GuildHelper.Bridge:GetChannelID(self.CHANNEL)
end

function Share:UpdateMembership()
    local wanted = self:IsOfficer() or (self.stayUntil ~= nil and GetTime() < self.stayUntil)
    local id = self:GetChannelID()
    if wanted and id == 0 then
        if self.lastJoin and GetTime() - self.lastJoin < self.JOINAGAIN and not self.forceJoin then return end
        self.lastJoin = GetTime()
        self.forceJoin = nil
        GuildHelper.Bridge:JoinChannel(self.CHANNEL, self.PASSWORD)
        C_Timer.After(2, function() GuildHelper.Bridge:HideChannel(Share.CHANNEL) end)
    elseif not wanted and id > 0 then
        GuildHelper.Bridge:LeaveChannel(self.CHANNEL)
    end
end

function Share:GetRemoteStore(key)
    GHTAB = GHTAB or {}
    GHTAB.FEEDBACKREMOTE = GHTAB.FEEDBACKREMOTE or {}
    GHTAB.FEEDBACKREMOTE[key] = GHTAB.FEEDBACKREMOTE[key] or {}
    local store = GHTAB.FEEDBACKREMOTE[key]
    store.entries = store.entries or {}
    store.votes = store.votes or {}
    store.comments = store.comments or {}

    return store
end

function Share:GetViewOptions()
    local options = {
        {
            value = "",
            label = self:GetViewLabel(nil)
        }
    }

    local keys = {}
    for key in pairs(GHTAB and GHTAB.FEEDBACKREMOTE or {}) do
        tinsert(keys, key)
    end

    sort(keys)
    for _, key in ipairs(keys) do
        tinsert(options, {
            value = key,
            label = self:GetViewLabel(key)
        })
    end

    return options
end

function Share:GetViewLabel(key)
    if key == nil then return GetGuildInfo("player") or GuildHelper:Trans("LID_FBOWNGUILD") end
    local store = GHTAB and GHTAB.FEEDBACKREMOTE and GHTAB.FEEDBACKREMOTE[key]

    return store and store.name or key
end

function Share:Request()
    if not self:IsDeveloper() or not IsInGuild() then return end
    if self.lastRequest and GetTime() - self.lastRequest < self.COOLDOWN then
        self:OpenPage()

        return
    end

    self.lastRequest = GetTime()
    self.stayUntil = GetTime() + self.STAY
    self.forceJoin = true
    self.reqid = GuildHelper.Feedback:Base36(time()) .. GuildHelper.Feedback:Base36(random(0, 1295))
    self:UpdateMembership()
    self:SendRequest(self.reqid, 0)
    C_Timer.After(self.STAY + 1, function() Share:UpdateMembership() end)
    self:OpenPage()
end

function Share:SendRequest(reqid, elapsed)
    if reqid ~= self.reqid then return end
    local id = self:GetChannelID()
    if id > 0 then
        GuildHelper.Sync:Send("R~" .. reqid .. "~" .. (GetGuildInfo("player") or ""), "FSR", self.PREFIX, nil, id)
    elseif elapsed < 8 then
        C_Timer.After(0.5, function() Share:SendRequest(reqid, elapsed + 0.5) end)
    end
end

function Share:OpenPage()
    local Window = GuildHelper.Window
    if Window.frame == nil then return end
    Window.frame:Show()
    Window:SelectPage("feedback")
end

function Share:OnRequest(reqid, sender)
    if not self:IsOfficer() or not self:IsDeveloperName(sender) or GuildHelper.Groups:IsSelfName(sender) then return end
    if type(reqid) ~= "string" or #reqid > 16 or reqid:find("[^%w]") or self.claims[reqid] then return end
    local developer = GuildHelper.Groups:Name(sender)
    if self.answered[developer] and time() - self.answered[developer] < self.ANSWERAGAIN then return end
    C_Timer.After(random(1, 6), function()
        if Share.claims[reqid] or not Share:IsOfficer() then return end
        Share.claims[reqid] = true
        GuildHelper.Sync:Send("C~" .. reqid .. "~" .. developer, nil, Share.PREFIX)
        Share:Answer(reqid, sender, developer)
    end)
end

function Share:Answer(reqid, target, developer)
    local Feedback = GuildHelper.Feedback
    local guild = GetGuildInfo("player")
    if not Feedback:CheckGuild() or not guild then return end
    self.answered[developer] = time()
    local list = Feedback:GetList("A")
    local count = min(#list, self.MAXENTRIES)
    Feedback:Queue(format("H~%s~%d~%s", reqid, count, guild), target)
    for index = 1, count do
        local id = list[index].id
        Feedback:SendEntry(id, target, true)
        Feedback:SendVotes(id, target)
    end
end

function Share:OnDetail(id, sender)
    local Feedback = GuildHelper.Feedback
    local developer = GuildHelper.Groups:Name(sender)
    if not self:IsDeveloperName(sender) or not Feedback:ValidId(id) or not Feedback:CheckGuild() then return end
    if not self.answered[developer] or time() - self.answered[developer] > self.DETAILWINDOW then return end
    local key = developer .. ":" .. id
    if self.detailSent[key] and time() - self.detailSent[key] < self.DETAILAGAIN then return end
    if not Feedback:Find(id) then return end
    self.detailSent[key] = time()
    Feedback:SendBody(id, sender)
    Feedback:SendComments(id, sender)
end

function Share:RequestDetail(key, entry)
    local store = self:GetRemoteStore(key)
    local asked = key .. ":" .. entry.id
    if not store.target or (self.asked[asked] and GetTime() - self.asked[asked] < self.DETAILAGAIN) then return end
    self.asked[asked] = GetTime()
    GuildHelper.Sync:Send("G~" .. entry.id, nil, self.PREFIX, nil, store.target)
end

function Share:GetRemoteKey(guild, sender)
    local realm = sender:match("%-(.+)$") or GetRealmName() or ""

    return guild .. "-" .. realm
end

function Share:OnHead(parts, sender, senderKey)
    local reqid, guild = parts[2], GuildHelper.Groups:CleanText(table.concat(parts, "~", 4), 48)
    if reqid ~= self.reqid or guild == "" or guild == GetGuildInfo("player") then return end
    local key = self:GetRemoteKey(guild, sender)
    GHTAB.FEEDBACKREMOTE = GHTAB.FEEDBACKREMOTE or {}
    GHTAB.FEEDBACKREMOTE[key] = nil
    local store = self:GetRemoteStore(key)
    store.name = guild
    store.target = sender
    store.updated = time()
    self.responders[senderKey] = key
end

function Share:ReadHeader(store, parts, edit)
    local Feedback, Groups = GuildHelper.Feedback, GuildHelper.Groups
    local id, kind, created, count = parts[2], parts[3], tonumber(parts[4]), tonumber(parts[5])
    if not Feedback:ValidId(id) or (kind ~= "I" and kind ~= "B") or not created or not count or count > 40 then return end
    local edited = edit and tonumber(parts[9])
    if edit and not edited then return end
    local owner = Groups:Name(parts[6])
    local title = Feedback:CleanTitle(table.concat(parts, "~", edit and 10 or 9))
    if not owner or title == "" then return end
    store.entries[id] = {
        id = id,
        kind = kind,
        created = created,
        owner = owner,
        version = Groups:CleanText(parts[7], 20),
        author = Groups:CleanText(parts[8], 48),
        title = title,
        edited = edited and floor(edited) or nil,
        chunks = count,
        text = count == 0 and "" or nil
    }
end

function Share:ReadChunk(key, store, message)
    local Feedback = GuildHelper.Feedback
    local id, index, text = message:match("^T~(%w+)~(%d+)~(.*)$")
    local entry = id and store.entries[id]
    index = tonumber(index)
    if not entry or not index or index > (entry.chunks or 0) then return end
    local pending = self.chunks[key .. ":" .. id] or {
        count = 0,
        parts = {}
    }

    self.chunks[key .. ":" .. id] = pending
    if pending.parts[index] then return end
    pending.parts[index] = Feedback:Decode(text)
    pending.count = pending.count + 1
    if pending.count < entry.chunks then return end
    self.chunks[key .. ":" .. id] = nil
    entry.text = Feedback:CleanBody(table.concat(pending.parts))
end

function Share:ReadVotes(store, id, list)
    if not store.entries[id] or type(list) ~= "string" then return end
    for item in string.gmatch(list, "[^;]+") do
        local voter, value, stamp = strsplit(",", item)
        voter = GuildHelper.Groups:Name(voter)
        value = tonumber(value)
        stamp = tonumber(stamp)
        if voter and value and stamp and value >= -1 and value <= 1 then
            store.votes[id] = store.votes[id] or {}
            store.votes[id][voter] = {floor(value), floor(stamp)}
        end
    end
end

function Share:ReadComment(store, parts)
    local Feedback, Groups = GuildHelper.Feedback, GuildHelper.Groups
    local id, cid, created = parts[2], parts[3], tonumber(parts[4])
    if not store.entries[id] or not Feedback:ValidId(cid) or not created then return end
    local owner = Groups:Name(parts[5])
    local text = Groups:CleanText(table.concat(parts, "~", 7), 254)
    if not owner or text == "" then return end
    store.comments[id] = store.comments[id] or {}
    store.comments[id][cid] = {
        id = cid,
        created = created,
        owner = owner,
        author = Groups:CleanText(parts[6], 48),
        text = text
    }
end

function Share:OnData(message, sender)
    if not self:IsDeveloper() then return end
    local senderKey = GuildHelper.Groups:Name(sender)
    if senderKey == nil then return end
    local parts = {strsplit("~", message)}
    local kind = parts[1]
    if kind == "H" then
        self:OnHead(parts, sender, senderKey)
    else
        local key = self.responders[senderKey]
        if key == nil then
            for remoteKey, store in pairs(GHTAB and GHTAB.FEEDBACKREMOTE or {}) do
                if store.target and GuildHelper.Groups:Name(store.target) == senderKey then key = remoteKey end
            end
        end

        if key == nil then return end
        local store = self:GetRemoteStore(key)
        if kind == "E" or kind == "U" then
            self:ReadHeader(store, parts, kind == "U")
        elseif kind == "T" then
            self:ReadChunk(key, store, message)
        elseif kind == "V" then
            self:ReadVotes(store, parts[2], parts[3])
        elseif kind == "C" then
            self:ReadComment(store, parts)
        else
            return
        end
    end

    self:ScheduleRefresh()
end

function Share:ScheduleRefresh()
    if self.refreshing then return end
    self.refreshing = true
    C_Timer.After(0.3, function()
        Share.refreshing = nil
        GuildHelper.Feedback:Refresh()
    end)
end

function Share:OnMessage(message, channel, sender)
    if type(message) ~= "string" or type(sender) ~= "string" or not GuildHelper:CanAccessValues(message, sender) then return end
    if channel == "CHANNEL" then
        local reqid, guild = message:match("^R~(%w+)~(.*)$")
        if reqid and guild ~= GetGuildInfo("player") then self:OnRequest(reqid, sender) end
    elseif channel == "GUILD" then
        local reqid, developer = message:match("^C~(%w+)~(.+)$")
        if reqid then
            self.claims[reqid] = true
            if self:IsDeveloperName(developer) then self.answered[GuildHelper.Groups:Name(developer)] = time() end
        end
    elseif channel == "WHISPER" then
        local id = message:match("^G~(%w+)$")
        if id then
            self:OnDetail(id, sender)
        else
            self:OnData(message, sender)
        end
    end
end

Share.events = CreateFrame("Frame")
Share.events:RegisterEvent("PLAYER_LOGIN")
Share.events:RegisterEvent("PLAYER_GUILD_UPDATE")
Share.events:RegisterEvent("GUILD_ROSTER_UPDATE")
Share.events:RegisterEvent("CHAT_MSG_ADDON")
Share.events:SetScript("OnEvent", function(_, event, prefix, message, channel, sender)
    if event == "CHAT_MSG_ADDON" then
        if prefix == Share.PREFIX then Share:OnMessage(message, channel, sender) end
    elseif event == "PLAYER_LOGIN" then
        if C_ChatInfo and C_ChatInfo.RegisterAddonMessagePrefix then
            C_ChatInfo.RegisterAddonMessagePrefix(Share.PREFIX)
        elseif RegisterAddonMessagePrefix then
            RegisterAddonMessagePrefix(Share.PREFIX)
        end

        GuildHelper:AddSlash("ghdevfb", function() Share:Request() end)
        C_Timer.After(15, function()
            Share.ready = true
            Share:UpdateMembership()
        end)
    elseif Share.ready then
        Share:UpdateMembership()
    end
end)
