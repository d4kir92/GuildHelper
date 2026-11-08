local _, GuildHelper = ...
local Groups = GuildHelper.Groups
Groups.announcements = {}
function Groups:GetChatInterval(entry)
    return min(60, max(10, floor((tonumber(entry.chatInterval) or 15) / 5) * 5)) * 60
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
    if not self:IsOwn(entry) then return end
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
    if not self.guild then return end
    local now = time()
    local last = 0 or GuildHelper:GetConfig("GROUPCHATLAST", 0)
    if now - last < 120 then return end
    if C_GuildInfo and C_GuildInfo.CanSpeakInGuildChat and not C_GuildInfo.CanSpeakInGuildChat() then return end
    local live = self:GetOwnLive()
    if live and live.lastChatAt and now - live.lastChatAt >= self:GetChatInterval(live) then
        self.announcements[live.key] = self.announcements[live.key] or {queued = GetTime()}
    end

    for _, entry in pairs(self:GetPlanned() or {}) do
        if self:IsOwn(entry) and entry.chatPending then
            self.announcements[entry.key] = self.announcements[entry.key] or {queued = GetTime()}
        end
    end

    local selected, oldest
    for key, pending in pairs(self.announcements) do
        local entry = self:Find(key)
        if not entry or not self:IsOwn(entry) or (entry.kind == "P" and entry.when <= now) then
            self.announcements[key] = nil
        elseif not oldest or pending.queued < oldest then
            selected, oldest = entry, pending.queued
        end
    end
    if not selected then return end
    local send = C_ChatInfo and C_ChatInfo.SendChatMessage or SendChatMessage
    if not send then return end
    local text = self:AnnouncementText(selected)
    if #text > 255 then return end
    send(text, "GUILD")
    GuildHelper:SetConfig("GROUPCHATLAST", now)
    selected.chatPending = nil
    selected.lastChatAt = now
    selected.lastChatText = text
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
    self.chatRepeatLabel = self:Text(form, "LID_GROUPCHATREPEAT", 360, -119)
    self.chatRepeat = Members:CreatePill(form, "")
    self.chatRepeat:SetScript("OnClick", function(button)
        local options = {}
        for minutes = 10, 60, 5 do
            tinsert(options, {value = minutes, label = format(GuildHelper:Trans("LID_GROUPCHATMINUTES"), minutes)})
        end
        Members:OpenMenu(button, options, self.draft.L.chatInterval or 15, function(value)
            self.draft.L.chatInterval = value
            local current = self:GetOwnLive()
            if current then current.chatInterval = value end
            self:Refresh()
        end)
    end)
end

function Groups:RefreshAnnouncementOptions(planned)
    local draft = self.draft[self.mode]
    local y = planned and -153 or -119
    self.chatLabel:ClearAllPoints()
    self.chatLabel:SetPoint("TOPLEFT", self.form, "TOPLEFT", 14, y)
    self.chatLanguage:ClearAllPoints()
    self.chatLanguage:SetPoint("TOPLEFT", self.form, "TOPLEFT", 150, y + 7)
    GuildHelper.Members:SetPillText(self.chatLanguage, GuildHelper:Trans("LID_LANG" .. strupper(draft.chatLanguage or GuildHelper:GetLanguage())))
    self.chatRepeatLabel:SetShown(not planned)
    self.chatRepeat:SetShown(not planned)
    self.chatRepeat:SetPoint("TOPLEFT", self.form, "TOPLEFT", 540, -112)
    GuildHelper.Members:SetPillText(self.chatRepeat, format(GuildHelper:Trans("LID_GROUPCHATMINUTES"), draft.chatInterval or 15))
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

function Groups:InstallChatRoleDisplay()
    self.chatDisplayHooks = self.chatDisplayHooks or {}
    for index = 1, NUM_CHAT_WINDOWS or 10 do
        local frame = _G["ChatFrame" .. index]
        if frame and index ~= 2 and type(frame.AddMessage) == "function" then
            local hooks = self.chatDisplayHooks[frame]
            if not hooks then
                hooks = {wrappers = {}, originals = {}}
                self.chatDisplayHooks[frame] = hooks
            end
            local original = frame.AddMessage
            if not hooks.wrappers[original] then
                local wrapper = hooks.originals[original]
                if not wrapper then
                    wrapper = function(chatFrame, message, ...)
                        return original(chatFrame, Groups:FormatChatRoles(message), ...)
                    end
                    hooks.originals[original] = wrapper
                    hooks.wrappers[wrapper] = true
                end
                frame.AddMessage = wrapper
            end
        end
    end
end

function Groups:RegisterChatRoleIcons()
    if self.chatRoleFilterRegistered then return end
    local register = (ChatFrameUtil and ChatFrameUtil.AddMessageEventFilter) or ChatFrame_AddMessageEventFilter
    if not register then return end
    register("CHAT_MSG_GUILD", function(...) return Groups:ChatRoleIcons(...) end)
    self.chatRoleFilterRegistered = true
end

Groups:RegisterChatRoleIcons()
