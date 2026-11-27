local _, GuildHelper = ...
local Notifications = {queue = {}, seen = {}, started = time()}
Notifications.ADDED = "2026-11-26"
Notifications.NEW_TYPES = {"NEWLIVE", "NEWPLANNED", "APPLICATION", "NEWIDEA", "NEWBUG"}
Notifications.GROUPS = {{label = "LID_GROUPFINDER", kinds = {"NEWLIVE", "NEWPLANNED", "APPLICATION"}}, {label = "LID_FEEDBACK", kinds = {"NEWIDEA", "NEWBUG"}}, {label = "LID_REQUESTS", kinds = {"REQUESTCOMMENT"}}}
Notifications.HOLDADDED = "2026-11-27"
Notifications.HOLDKINDS = {"PVP", "PARTY", "RAID"}
Notifications.HOLDTYPES = {pvp = "PVP", arena = "PVP", party = "PARTY", raid = "RAID"}
GuildHelper.Notifications = Notifications

function Notifications:GetDisplayTime()
    return (self.pauseStart or GetTime()) - (self.pauseDuration or 0)
end

function Notifications:IsHeld()
    if not IsInInstance then return false end
    local inInstance, kind = IsInInstance()
    local hold = inInstance and self.HOLDTYPES[kind]
    if not hold then return false end

    return self:IsEnabled("NOTIFYHOLD" .. hold)
end

function Notifications:UpdatePause()
    local paused = InCombatLockdown() or self:IsHeld()
    if paused and not self.pauseStart then
        self.pauseStart = GetTime()
    elseif not paused and self.pauseStart then
        self.pauseDuration = (self.pauseDuration or 0) + GetTime() - self.pauseStart
        self.pauseStart = nil
    end

    return paused
end

function Notifications:RestorePosition()
    local position = GuildHelper:GetConfig("NOTIFICATIONPOSITION", {})
    self.frame:ClearAllPoints()
    self.frame:SetPoint("CENTER", UIParent, "CENTER", tonumber(position.x) or 0, tonumber(position.y) or 200)
end

function Notifications:SavePosition()
    if not self.frame then return end
    self.frame:StopMovingOrSizing()
    local x, y = self.frame:GetCenter()
    local centerX, centerY = UIParent:GetCenter()
    if x and y and centerX and centerY then
        local scale = self.frame:GetEffectiveScale() / UIParent:GetEffectiveScale()
        GuildHelper:SetConfig("NOTIFICATIONPOSITION", {x = x * scale - centerX, y = y * scale - centerY})
    end
end

function Notifications:Create()
    if self.frame then return end
    local Theme = GuildHelper.Theme
    local frame = CreateFrame("Button", nil, UIParent)
    self.frame = frame
    frame:SetSize(360, 100)
    frame:SetFrameStrata("DIALOG")
    frame:SetClampedToScreen(true)
    frame:SetMovable(true)
    frame:RegisterForDrag("LeftButton")
    frame:RegisterForClicks("LeftButtonUp")
    frame.ghNoInside = true
    Theme:Panel(frame, "card", "border", 9)
    frame.title = Theme:Text(frame, 14, "accent")
    frame.title:SetPoint("TOPLEFT", frame, "TOPLEFT", 14, -12)
    frame.title:SetPoint("RIGHT", frame, "RIGHT", -38, 0)
    frame.text = Theme:Text(frame, 13, "text")
    frame.text:SetPoint("TOPLEFT", frame, "TOPLEFT", 14, -35)
    frame.text:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -14, 12)
    frame.text:SetJustifyH("LEFT")
    frame.text:SetJustifyV("TOP")
    frame.text:SetWordWrap(true)
    frame.close = GuildHelper.Window:CreateCloseButton(frame)
    frame.close:ClearAllPoints()
    frame.close:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -5, -5)
    frame.close:SetScript("OnClick", function()
        if self.editing then self:SetEditing(false) else self:Dismiss() end
    end)
    frame:SetScript("OnDragStart", function(sel)
        if self.editing then
            self.dragged = true
            sel:StartMoving()
        end
    end)
    frame:SetScript("OnDragStop", function() self:SavePosition() end)
    frame:SetScript("OnClick", function()
        if self.dragged then self.dragged = nil return end
        if self.editing or not self.current then return end
        local notice = self.current
        local feedback = GuildHelper.Feedback
        if notice.debug then
            GuildHelper:MSG(notice.title .. (notice.setting and (" -> " .. notice.setting .. " = " .. tostring(self:IsEnabled(notice.setting))) or ""))
            if notice.page then
                GuildHelper.Window:SelectPage(notice.page)
                GuildHelper.Window.frame:Show()
            end
        elseif notice.repost then
            local entry = GuildHelper.Groups:Find(notice.repost)
            if entry then GuildHelper.Groups:OpenListing(entry) end
        elseif notice.log then
            GuildHelper.Window:SelectPage("log")
            GuildHelper.Window.frame:Show()
        elseif notice.request and notice.guild == GuildHelper.Sync:GetGuildKey() then
            GuildHelper.Requests:Open(notice.request)
        elseif notice.order and notice.guild == GuildHelper.Sync:GetGuildKey() then
            if GuildHelper.Orders:GetOpenIncoming(notice.id) then GuildHelper.Orders:Open(notice.id) end
        elseif (notice.applicant or notice.group) and notice.guild == GuildHelper.Sync:GetGuildKey() then
            local groups = GuildHelper.Groups
            local entry = groups:Find(notice.id)
            if entry and (notice.group or (entry.applicants and entry.applicants[notice.applicant])) then
                groups:OpenListing(entry)
            end
        elseif not notice.test and not notice.applicant and notice.guild == GuildHelper.Sync:GetGuildKey() and feedback:Find(notice.id) then
            feedback:StopEditing()
            feedback.composing = false
            feedback.filter = "A"
            feedback.selected = notice.id
            GuildHelper.Window:SelectPage("feedback")
            GuildHelper.Window.frame:Show()
            feedback:Refresh()
        end
        self:Dismiss()
    end)
    frame.open = GuildHelper.Members:CreateButton(frame, "LID_GROUPFINDER")
    frame.open:SetWidth(160)
    frame.open:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -14, 10)
    local openPage = frame:GetScript("OnClick")
    frame.open:SetScript("OnClick", function()
        local notice = not self.editing and self.current
        if notice and notice.repost then
            GuildHelper.Groups:PostNow(notice.repost)
            self:Dismiss()
        elseif notice and notice.debug and notice.action then
            GuildHelper:MSG(notice.title .. " -> " .. GuildHelper:Trans(notice.action))
            self:Dismiss()
        else
            openPage(frame)
        end
    end)
    frame.open:Hide()
    frame.mute = GuildHelper.Members:CreateButton(frame, "LID_NOTIFICATIONMUTE")
    frame.mute:SetWidth(150)
    frame.mute:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", 14, 10)
    frame.mute:SetScript("OnClick", function() self:MuteCurrent() end)
    frame.mute:Hide()
    self:RestorePosition()
    frame:Hide()
end

function Notifications:Dismiss()
    self.current = nil
    self.expires = nil
    if self.frame and not self.editing then self.frame:Hide() end
end

function Notifications:IsEnabled(setting)
    return GuildHelper:GetConfig(setting, true) == true
end

function Notifications:MuteCurrent()
    local setting = self.current and self.current.setting
    if not setting then return end
    if not StaticPopupDialogs or not StaticPopup_Show then
        self:ApplyMute(setting)
        return
    end
    StaticPopupDialogs.GUILDHELPER_NOTIFYMUTE = {
        text = GuildHelper:Trans("LID_NOTIFICATIONMUTECONFIRM"),
        button1 = YES,
        button2 = NO,
        OnAccept = function() Notifications:ApplyMute(setting) end,
        OnHide = function() Notifications.confirming = nil end,
        timeout = 0,
        whileDead = true,
        hideOnEscape = true,
        preferredIndex = 3,
    }
    self.confirming = true
    StaticPopup_Show("GUILDHELPER_NOTIFYMUTE", self.frame.title:GetText() or "")
end

function Notifications:ApplyMute(setting)
    GuildHelper:SetConfig(setting, false)
    if GuildHelper.Settings.notificationRows then GuildHelper.Settings:UpdateMap() end
    if self.current and self.current.setting == setting then self:Dismiss() end
end

function Notifications:GetPageLabel(page)
    for _, nav in ipairs(GuildHelper.Window.NAV) do
        if nav.key == page then return nav.label end
    end

    return nil
end

function Notifications:ShowActions(page, action)
    local frame = self.frame
    local muted = not self.editing and self.current ~= nil and self.current.setting ~= nil
    local label = not self.editing and (action or (page and self:GetPageLabel(page)))
    if label then
        GuildHelper.Theme:SetTrans(frame.open.text, label)
        frame.open:SetWidth(min(170, max(120, ceil(frame.open.text:GetStringWidth()) + 32)))
    end
    frame.open:SetShown(label and true or false)
    frame.mute:SetShown(muted)
    local row = frame.open:IsShown() or muted
    frame:SetHeight(row and 142 or 100)
    frame.text:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -14, row and 50 or 12)
end

function Notifications:SetEditing(active)
    self:Create()
    if self.editing and not active then self:SavePosition() end
    self.editing = active == true
    self.dragged = nil
    if self.editing then
        self:ShowActions(nil)
        self.frame.title:SetText(GuildHelper:Trans("LID_NOTIFICATIONS"))
        self.frame.text:SetText(GuildHelper:Trans("LID_NOTIFICATIONMOVE"))
        self.frame:Show()
    else
        self.expires = self:GetDisplayTime() + 8
        self:Render()
    end
end

function Notifications:Suppress()
    for index = #self.queue, 1, -1 do
        if not self.queue[index].order then table.remove(self.queue, index) end
    end
    if self.current and not self.current.test and not self.current.order then self:Dismiss() end
end

function Notifications:Enqueue(notice)
    local window = GuildHelper.Window.frame
    if not notice.order then
        if window and window:IsShown() then return end
        if #self.queue >= 20 then
            local removed
            for index, queued in ipairs(self.queue) do
                if not queued.order then
                    table.remove(self.queue, index)
                    removed = true
                    break
                end
            end
            if not removed then return end
        end
    end
    tinsert(self.queue, notice)
end

function Notifications:Repost(key)
    local guild = GuildHelper.Sync:GetGuildKey()
    if not guild or (self.current and self.current.repost == key) then return end
    for _, queued in ipairs(self.queue) do
        if queued.repost == key then return end
    end
    self:Enqueue({repost = key, guild = guild, queued = self:GetDisplayTime()})
end

function Notifications:Application(id, applicant, author)
    local guild = GuildHelper.Sync:GetGuildKey()
    if not guild then return end
    if not self:IsEnabled("NOTIFYAPPLICATION") then return end
    self:Enqueue({id = id, guild = guild, applicant = applicant, author = author, setting = "NOTIFYAPPLICATION", queued = self:GetDisplayTime()})
end

function Notifications:NewEntry(id, owner, created, category, group)
    if not created or created < self.started or created > time() + 60 or GuildHelper.Groups:IsSelfName(owner) then return end
    local guild = GuildHelper.Sync:GetGuildKey()
    if not guild then return end
    local key = guild .. ":" .. category .. ":" .. id
    if self.seen[key] then return end
    self.seen[key] = true
    if not self:IsEnabled("NOTIFY" .. category) then return end
    self:Enqueue({id = id, guild = guild, category = category, setting = "NOTIFY" .. category, group = group, queued = self:GetDisplayTime()})
end

function Notifications:Comment(id, comment)
    if not comment or comment.created < self.started or comment.created > time() + 60 or GuildHelper.Groups:IsSelfName(comment.owner) then return end
    local guild = GuildHelper.Sync:GetGuildKey()
    if not guild then return end
    local key = guild .. ":" .. id .. ":" .. comment.id
    if self.seen[key] then return end
    self.seen[key] = true
    local entry = GuildHelper.Feedback:Find(id)
    if entry and not GuildHelper.Feedback:IsSubscribed(entry) then return end
    self:Enqueue({id = id, guild = guild, author = comment.author or comment.owner, owner = comment.owner, queued = self:GetDisplayTime()})
end

function Notifications:RequestComment(comment)
    local guild = GuildHelper.Sync:GetGuildKey()
    if not guild or not self:IsEnabled("NOTIFYREQUESTCOMMENT") then return end
    local key = guild .. ":request:" .. comment.cid
    if self.seen[key] then return end
    self.seen[key] = true
    self:Enqueue({request = comment.id, cid = comment.cid, author = comment.name, guild = guild, setting = "NOTIFYREQUESTCOMMENT", queued = self:GetDisplayTime()})
end

function Notifications:LogEntry(text, setting)
    local guild = GuildHelper.Sync:GetGuildKey()
    if not guild or type(text) ~= "string" or text == "" then return end
    self:Enqueue({log = text:gsub("|H.-|h(.-)|h", "%1"), guild = guild, setting = setting, queued = self:GetDisplayTime()})
end

function Notifications:GetDebugSamples()
    local sample = {author = UnitName("player") or "?", activity = GetZoneText and GetZoneText() or "?", title = GuildHelper:Trans("LID_NOTIFYSAMPLETITLE")}
    for _, member in ipairs(GuildHelper.Members.list or {}) do
        if member.online and member.short and not GuildHelper.Members:IsSelf(member) then
            sample.author = member.short
            break
        end
    end

    local activities = GuildHelper.Groups:GetModeActivities("L")
    for _, option in ipairs(activities or {}) do
        if not option.header and option.label then
            sample.activity = option.label
            break
        end
    end

    local newest
    local store = GuildHelper.Feedback:GetStore()
    for _, entry in pairs(store and store.entries or {}) do
        if not entry.deleted and entry.title and (not newest or (entry.created or 0) > (newest.created or 0)) then newest = entry end
    end
    if newest then sample.title = newest.title end

    local Log = GuildHelper.Log
    local logStore = Log and Log:GetStore()
    local logEntry
    for _, entry in pairs(logStore and logStore.entries or {}) do
        if Log.types[entry.kind] and (not logEntry or (entry.time or 0) > (logEntry.time or 0)) then logEntry = entry end
    end
    if logEntry then
        local definition = Log.types[logEntry.kind]
        sample.log = Log:FormatEntry(logEntry):gsub("|H.-|h(.-)|h", "%1")
        sample.logSetting = "NOTIFYLOG" .. strupper(definition.filter or logEntry.kind)
    else
        sample.log = format(GuildHelper:Trans("LID_LOGLEVEL"), sample.author, UnitLevel("player") or 1)
        sample.logSetting = "NOTIFYLOGLEVEL"
    end

    return sample
end

Notifications.DEBUGTYPES = {"NEWLIVE", "NEWPLANNED", "NEWIDEA", "NEWBUG", "LOG", "APPLICATION", "COMMENT", "REPOST"}
function Notifications:Debug(kind)
    kind = strupper(kind or "")
    local list = {}
    for _, value in ipairs(self.DEBUGTYPES) do
        if kind == "" or kind == "ALL" or kind == value then tinsert(list, value) end
    end
    if #list == 0 then
        GuildHelper:MSG("/ghnotifytest all | " .. strlower(table.concat(self.DEBUGTYPES, " | ")))
        return
    end

    local guild = GuildHelper.Sync:GetGuildKey()
    local sample = self:GetDebugSamples()
    for _, value in ipairs(list) do
        local notice = {debug = true, guild = guild, queued = self:GetDisplayTime()}
        if value == "LOG" then
            notice.title, notice.text, notice.setting, notice.page = GuildHelper:Trans("LID_GUILDLOG"), sample.log, sample.logSetting, "log"
        elseif value == "APPLICATION" then
            notice.title, notice.page, notice.setting = GuildHelper:Trans("LID_NOTIFICATIONAPPLICATION"), "groups", "NOTIFYAPPLICATION"
            notice.text = sample.author .. "\n" .. sample.activity
        elseif value == "REPOST" then
            notice.title, notice.text, notice.action = GuildHelper:Trans("LID_GROUPREPOSTTITLE"), sample.activity, "LID_GROUPREPOSTNOW"
        elseif value == "COMMENT" then
            notice.title, notice.page = GuildHelper:Trans("LID_NOTIFICATIONCOMMENT"), "feedback"
            notice.text = format(GuildHelper:Trans("LID_NOTIFICATIONCOMMENTTEXT"), sample.author, sample.title)
        else
            notice.title, notice.setting = GuildHelper:Trans("LID_NOTIFICATION" .. value), "NOTIFY" .. value
            notice.page = (value == "NEWLIVE" or value == "NEWPLANNED") and "groups" or "feedback"
            notice.text = (value == "NEWLIVE" or value == "NEWPLANNED") and sample.activity or sample.title
        end
        tinsert(self.queue, notice)
    end
    if self.current and self.current.debug then self:Dismiss() end
end

function Notifications:Test()
    self:SetEditing(false)
    self.current = {test = true, guild = GuildHelper.Sync:GetGuildKey()}
    self.expires = self:GetDisplayTime() + 8
    self:Render()
end

function Notifications:Render()
    if self.editing then return end
    if not self.current or InCombatLockdown() or (not self.current.test and self:IsHeld()) then
        if self.frame then self.frame:Hide() end
        return
    end
    if self.current.test then
        self:Create()
        self:ShowActions(nil)
        self.frame.title:SetText(GuildHelper:Trans("LID_NOTIFICATIONS"))
        self.frame.text:SetText(GuildHelper:Trans("LID_NOTIFICATIONTEST"))
        self.frame:Show()
        return
    end
    if self.current.debug then
        self:Create()
        self:ShowActions(self.current.page, self.current.action)
        self.frame.title:SetText(self.current.title)
        self.frame.text:SetText(self.current.text)
        self.frame:Show()
        return
    end
    if self.current.repost then
        local groups = GuildHelper.Groups
        local entry = groups:Find(self.current.repost)
        if not entry or not groups:IsOwn(entry) then self:Dismiss() return end
        self:Create()
        self:ShowActions(nil, "LID_GROUPREPOSTNOW")
        self.frame.title:SetText(GuildHelper:Trans("LID_GROUPREPOSTTITLE"))
        self.frame.text:SetText(groups:GetActivityName(entry))
        self.frame:Show()
        return
    end
    if self.current.log then
        self:Create()
        self:ShowActions("log")
        self.frame.title:SetText(GuildHelper:Trans("LID_GUILDLOG"))
        self.frame.text:SetText(self.current.log)
        self.frame:Show()
        return
    end
    if self.current.request then
        local requests = GuildHelper.Requests
        local row = requests:Get(self.current.request)
        if not row or row.status == "X" then self:Dismiss() return end
        self:Create()
        self:ShowActions("requests")
        self.frame.title:SetText(GuildHelper:Trans("LID_NOTIFICATIONCOMMENT"))
        local author = GuildHelper.Orders:ContactLabel(self.current.author)
        self.frame.text:SetText(format(GuildHelper:Trans("LID_NOTIFICATIONCOMMENTTEXT"), author, requests:Display(row)))
        self.frame:Show()
        return
    end
    if self.current.order then
        local order = GuildHelper.Orders:GetOpenIncoming(self.current.id)
        if not order then self:Dismiss() return end
        self:Create()
        self:ShowActions("orders")
        self.frame.title:SetText(GuildHelper:Trans("LID_ORDER_NOTIFICATION"))
        self.frame.text:SetText(GuildHelper.Recipes:Name(order.recipe) .. "\n" .. GuildHelper.Orders:ContactLabel(order.requester, nil, true))
        self.frame:Show()
        order.notified = true
        return
    end
    if self.current.category then
        local source = self.current.group and GuildHelper.Groups or GuildHelper.Feedback
        local entry = source:Find(self.current.id)
        if not entry then self:Dismiss() return end
        self:Create()
        self:ShowActions(self.current.group and source:GetPageForMode(source:GetListingMode(entry)) or "feedback")
        self.frame.title:SetText(GuildHelper:Trans("LID_NOTIFICATION" .. self.current.category))
        self.frame.text:SetText(self.current.group and source:GetActivityName(entry) or entry.title)
        self.frame:Show()
        return
    end
    if self.current.applicant then
        local groups = GuildHelper.Groups
        local entry = groups:Find(self.current.id)
        if not entry or not entry.applicants or not entry.applicants[self.current.applicant] then
            self:Dismiss()
            return
        end
        self:Create()
        self:ShowActions(groups:GetPageForMode(groups:GetListingMode(entry)))
        self.frame.title:SetText(GuildHelper:Trans("LID_NOTIFICATIONAPPLICATION"))
        self.frame.text:SetText(self.current.author .. "\n" .. groups:GetActivityName(entry))
        self.frame:Show()
        return
    end
    local entry = GuildHelper.Feedback:Find(self.current.id)
    if not entry or not GuildHelper.Feedback:IsSubscribed(entry) then self:Dismiss() return end
    self:Create()
    self:ShowActions("feedback")
    self.frame.title:SetText(GuildHelper:Trans("LID_NOTIFICATIONCOMMENT"))
    local author = GuildHelper.Feedback:AuthorLabel(self.current)
    self.frame.text:SetText(format(GuildHelper:Trans("LID_NOTIFICATIONCOMMENTTEXT"), author, entry.title))
    self.frame:Show()
end

function Notifications:Tick()
    if self:UpdatePause() then
        if self.current and not self.editing then self:Render() end
        return
    end
    local guild = GuildHelper.Sync:GetGuildKey()
    if self.current and self.current.guild ~= guild then self:Dismiss() end
    if self.editing then return end
    if self.current then
        if self.confirming or (self.frame and self.frame:IsMouseOver()) then self.expires = self:GetDisplayTime() + 8 end
        if self:GetDisplayTime() >= (self.expires or 0) then self:Dismiss() end
    end
    if not self.current then
        while #self.queue > 0 do
            local notice = self.queue[1]
            if notice.guild ~= guild or (not notice.order and self:GetDisplayTime() - notice.queued > 180) or (notice.setting and not notice.debug and not self:IsEnabled(notice.setting)) then
                table.remove(self.queue, 1)
            elseif notice.debug then
                self.current = table.remove(self.queue, 1)
                self.expires = self:GetDisplayTime() + 8
                break
            elseif not notice.order and not notice.applicant and not notice.category and not notice.log and not notice.repost and not GuildHelper.Feedback:Find(notice.id) then
                if self:GetDisplayTime() - notice.queued < 30 then return end
                table.remove(self.queue, 1)
            else
                self.current = table.remove(self.queue, 1)
                self.expires = self:GetDisplayTime() + (self.current.repost and 30 or 8)
                break
            end
        end
    end
    self:Render()
end

Notifications.events = CreateFrame("Frame")
Notifications.events:RegisterEvent("PLAYER_LOGIN")
Notifications.events:RegisterEvent("PLAYER_REGEN_DISABLED")
Notifications.events:RegisterEvent("PLAYER_REGEN_ENABLED")
Notifications.events:SetScript("OnEvent", function(_, event)
    if event == "PLAYER_REGEN_DISABLED" then
        Notifications:UpdatePause()
        Notifications:Render()
        return
    end
    if event == "PLAYER_REGEN_ENABLED" then
        Notifications:Tick()
        return
    end
    Notifications.started = time()
    if EventRegistry then
        EventRegistry:RegisterCallback("EditMode.Enter", function() Notifications:SetEditing(true) end, Notifications)
        EventRegistry:RegisterCallback("EditMode.Exit", function() Notifications:SetEditing(false) end, Notifications)
    end
end)
Notifications.events:SetScript("OnUpdate", function(_, elapsed)
    Notifications.elapsed = (Notifications.elapsed or 0) + elapsed
    if Notifications.elapsed < 0.2 then return end
    Notifications.elapsed = 0
    Notifications:Tick()
end)
GuildHelper:AddSlash("ghnotifytest", function(args) Notifications:Debug(args) end)
GuildHelper.Theme:OnRefresh(function()
    if Notifications.editing then Notifications:SetEditing(true) else Notifications:Render() end
end)
GuildHelper.Window:OnRebuild(function()
    if Notifications.frame then Notifications.frame:Hide() end
    Notifications.frame = nil
    Notifications.editing = false
end)
