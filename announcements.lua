local _, GuildHelper = ...
local Groups = GuildHelper.Groups
Groups.announcements = {}
Groups.LIVECHATCOOLDOWN = 15
Groups.DEFAULTCHATREPEATMINUTES = 2

function Groups:GetChatCooldown()
    local elapsed
    if self.lastChatSend then
        elapsed = GetTime() - self.lastChatSend
    else
        local last = GuildHelper:GetConfig("GROUPCHATLAST", 0)
        elapsed = max(0, time() - last - 1)
    end
    return max(0, self.LIVECHATCOOLDOWN - elapsed)
end

function Groups:GetLiveChatState(entry, text)
    return table.concat({text, entry.activity, entry.note or "", entry.chatLanguage or "", entry.soloRole or "", entry.rosterSignature or ""}, "\n")
end

function Groups:GetLiveAnnouncementDelay(entry, state, clock, now)
    if state ~= entry.lastChatState then return 0 end
    if not GuildHelper.Bridge:IsLiveRepeatEnabled() then return math.huge end
    local elapsed = entry.lastChatSend and (clock - entry.lastChatSend) or (now - (entry.lastChatAt or 0))
    return max(0, (entry.chatRepeatMinutes or self.DEFAULTCHATREPEATMINUTES) * 60 - elapsed)
end

function Groups:AnnouncementText(entry)
    local lang = entry.chatLanguage or GuildHelper:GetLanguage()
    local needs = {}
    for _, role in ipairs(GuildHelper.Specs.ROLES) do
        local count = entry[role.value] or 0
        if count > 0 then tinsert(needs, count .. " [" .. GuildHelper:Trans(role.label, lang) .. "]") end
    end

    local function compose(activity)
        if entry.kind == "P" then
            return "[GuildHelper] " .. format(GuildHelper:Trans("LID_GROUPCHATPLANNED", lang), date("%Y-%m-%d %H:%M", entry.when), table.concat(needs, " "), activity)
        end
        return "[GuildHelper] " .. format(GuildHelper:Trans("LID_GROUPCHATLIVE", lang), table.concat(needs, " "), activity)
    end
    local activity = self:CleanText(self:GetActivityName(entry), min(100, max(0, 255 - #compose(""))))
    local text = compose(activity)
    local note = self:CleanText(entry.note, max(0, 255 - #text - 2))
    if note ~= "" then text = text .. ": " .. note end

    return text
end

function Groups:QueueAnnouncement(entry)
    if entry.kind ~= "P" or not self:IsOwn(entry) then return end
    local text = self:AnnouncementText(entry)
    local pending = self.announcements[entry.key]
    entry.chatPending = text ~= entry.lastChatText or nil
    if entry.chatPending then
        self.announcements[entry.key] = pending or {queued = GetTime()}
    else
        self.announcements[entry.key] = nil
    end
end

function Groups:TickAnnouncements()
    if not self.guild or self:GetChatCooldown() > 0 then return end
    if C_GuildInfo and C_GuildInfo.CanSpeakInGuildChat and not C_GuildInfo.CanSpeakInGuildChat() then return end
    local now, clock = time(), GetTime()
    local selected, oldest, text, liveState

    local last = GuildHelper:GetConfig("GROUPCHATLAST", 0)
    if now - last >= 120 then
        for _, entry in pairs(self:GetPlanned() or {}) do
            if self:IsOwn(entry) and entry.chatPending then
                self.announcements[entry.key] = self.announcements[entry.key] or {queued = clock}
            end
        end

        for key, pending in pairs(self.announcements) do
            local entry = self:Find(key)
            if not entry or not self:IsOwn(entry) or entry.when <= now then
                self.announcements[key] = nil
            elseif not oldest or pending.queued < oldest then
                selected, oldest = entry, pending.queued
            end
        end
    end

    if not selected and (not self.rosterReadyAt or clock >= self.rosterReadyAt) then
        local live = self:GetOwnLive()
        if live then
            text = self:AnnouncementText(live)
            liveState = self:GetLiveChatState(live, text)
            if self:GetLiveAnnouncementDelay(live, liveState, clock, now) == 0 then selected = live end
        end
    end

    if not selected then return end
    local send = C_ChatInfo and C_ChatInfo.SendChatMessage or SendChatMessage
    if not send then return end
    text = text or self:AnnouncementText(selected)
    if #text > 255 then return end
    send(text, "GUILD")
    GuildHelper:SetConfig("GROUPCHATLAST", now)
    self.lastChatSend = clock
    selected.chatPending = nil
    selected.lastChatAt = now
    selected.lastChatSend = clock
    selected.lastChatText = text
    selected.lastChatState = liveState
    self.announcements[selected.key] = nil
end

function Groups:GetChatLanguages()
    local options = {}
    for _, lang in ipairs(GuildHelper.LANGUAGES) do
        tinsert(options, {value = lang, label = GuildHelper:Trans("LID_LANG" .. strupper(lang))})
    end
    return options
end

function Groups:BuildAnnouncementOptions(form)
    local Members = GuildHelper.Members
    self.chatLabel = self:Text(form, "LID_GROUPCHATLANG", 14, -119)
    self.chatLanguage = Members:CreatePill(form, "")
    self.chatLanguage:SetScript("OnClick", function(button)
        local draft = self.draft[self.mode]
        Members:OpenMenu(button, self:GetChatLanguages(), draft.chatLanguage or GuildHelper:GetLanguage(), function(value)
            draft.chatLanguage = value
            self:Refresh()
        end)
    end)
    self.chatRepeatLabel = self:Text(form, "LID_GROUPCHATREPEAT", 14, -153)
    self.chatRepeat = Members:CreatePill(form, "")
    self.chatRepeat:SetPoint("TOPLEFT", form, "TOPLEFT", 150, -146)
    self.chatCountdown = self:Text(form, nil, 0, 0)
    self.chatCountdown:ClearAllPoints()
    self.chatCountdown:SetPoint("LEFT", self.chatRepeat, "RIGHT", 12, 0)
    self.chatRepeat:SetScript("OnClick", function(button)
        local draft = self.draft.L
        local options = {}
        local label = GuildHelper:Trans("LID_GROUPCHATMINUTES")
        for minutes = self.DEFAULTCHATREPEATMINUTES, 20 do
            tinsert(options, {value = minutes, label = format(label, minutes)})
        end
        Members:OpenMenu(button, options, draft.chatRepeatMinutes or self.DEFAULTCHATREPEATMINUTES, function(value)
            draft.chatRepeatMinutes = value
            local live = self:GetOwnLive()
            if live then live.chatRepeatMinutes = value end
            self:Refresh()
        end)
    end)
end

function Groups:RefreshAnnouncementOptions(planned)
    local draft = self.draft[self.mode]
    local y = planned and -177 or -119
    self.chatLabel:ClearAllPoints()
    self.chatLabel:SetPoint("TOPLEFT", self.form, "TOPLEFT", 14, y)
    self.chatLanguage:ClearAllPoints()
    self.chatLanguage:SetPoint("TOPLEFT", self.form, "TOPLEFT", 150, y + 7)
    GuildHelper.Members:SetPillText(self.chatLanguage, GuildHelper:Trans("LID_LANG" .. strupper(draft.chatLanguage or GuildHelper:GetLanguage())))
    local repeatEnabled = not planned and GuildHelper.Bridge:IsLiveRepeatEnabled()
    self.chatRepeatLabel:SetShown(repeatEnabled)
    self.chatRepeat:SetShown(repeatEnabled)
    local live = repeatEnabled and self:GetOwnLive()
    self.chatCountdown:SetShown(live and true or false)
    if live then
        local clock = GetTime()
        local state = self:GetLiveChatState(live, self:AnnouncementText(live))
        local delay = self:GetLiveAnnouncementDelay(live, state, clock, time())
        local remaining = math.ceil(max(delay, self:GetChatCooldown(), (self.rosterReadyAt or clock) - clock))
        local countdown = format("%d:%02d", floor(remaining / 60), remaining % 60)
        self.chatCountdown:SetText(format(GuildHelper:Trans("LID_GROUPCHATNEXT"), countdown))
    end
    if repeatEnabled then
        GuildHelper.Members:SetPillText(self.chatRepeat, format(GuildHelper:Trans("LID_GROUPCHATMINUTES"), draft.chatRepeatMinutes or self.DEFAULTCHATREPEATMINUTES))
    end
end

function Groups:FormatChatRoles(message)
    if not GuildHelper:CanAccessValues(message) or type(message) ~= "string" or not message:find("[GuildHelper]", 1, true) then return message end
    local icons = {}
    for _, lang in ipairs(GuildHelper.LANGUAGES) do
        for _, role in ipairs(GuildHelper.Specs.ROLES) do
            icons[GuildHelper:Trans(role.label, lang)] = GuildHelper.Specs:GetIconString(GuildHelper.Specs.ROLEICONS, role.coords)
        end
    end
    message = message:gsub("%[([^%]]+)%]", function(label) return icons[label] or "[" .. label .. "]" end)
    return message
end

function Groups:ChatRoleIcons(_, _, message, ...)
    local formatted = self:FormatChatRoles(message)
    if not GuildHelper:CanAccessValues(message) or formatted == message then return false end

    return false, formatted, ...
end

function Groups:RegisterChatRoleIcons()
    if self.chatRoleFilterRegistered then return end
    local register = (ChatFrameUtil and ChatFrameUtil.AddMessageEventFilter) or ChatFrame_AddMessageEventFilter
    if not register then return end
    register("CHAT_MSG_GUILD", function(...) return Groups:ChatRoleIcons(...) end)
    self.chatRoleFilterRegistered = true
end

Groups:RegisterChatRoleIcons()
