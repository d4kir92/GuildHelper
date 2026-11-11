local _, GuildHelper = ...
local Notifications = {queue = {}, seen = {}, started = time()}
Notifications.NEW_TYPES = {"NEWLIVE", "NEWPLANNED", "NEWIDEA", "NEWBUG"}
GuildHelper.Notifications = Notifications

function Notifications:GetDisplayTime()
    return (self.combatStart or GetTime()) - (self.combatDuration or 0)
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
        if notice.order and notice.guild == GuildHelper.Sync:GetGuildKey() then
            if GuildHelper.Orders:GetOpenIncoming(notice.id) then GuildHelper.Orders:Open(notice.id) end
        elseif (notice.applicant or notice.group) and notice.guild == GuildHelper.Sync:GetGuildKey() then
            local groups = GuildHelper.Groups
            local entry = groups:Find(notice.id)
            if entry and (notice.group or (entry.applicants and entry.applicants[notice.applicant])) then
                GuildHelper.Window:SelectPage("groups")
                GuildHelper.Window.frame:Show()
                groups:SetMode(entry.kind)
                groups:Select(entry)
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
    frame.openGroups = GuildHelper.Members:CreateButton(frame, "LID_GROUPFINDER")
    frame.openGroups:SetWidth(160)
    frame.openGroups:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -14, 10)
    frame.openGroups:SetScript("OnClick", frame:GetScript("OnClick"))
    frame.openGroups:Hide()
    self:RestorePosition()
    frame:Hide()
end

function Notifications:Dismiss()
    self.current = nil
    self.expires = nil
    if self.frame and not self.editing then self.frame:Hide() end
end

function Notifications:ShowGroupAction(shown)
    local frame = self.frame
    if frame.openGroups:IsShown() == shown then return end
    frame.openGroups:SetShown(shown)
    frame:SetHeight(shown and 142 or 100)
    frame.text:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -14, shown and 50 or 12)
end

function Notifications:SetEditing(active)
    self:Create()
    if self.editing and not active then self:SavePosition() end
    self.editing = active == true
    self.dragged = nil
    if self.editing then
        self:ShowGroupAction(false)
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

function Notifications:Application(id, applicant, author)
    local guild = GuildHelper.Sync:GetGuildKey()
    if not guild then return end
    self:Enqueue({id = id, guild = guild, applicant = applicant, author = author, queued = self:GetDisplayTime()})
end

function Notifications:NewEntry(id, owner, created, category, group)
    if not created or created < self.started or created > time() + 60 or GuildHelper.Groups:IsSelfName(owner) then return end
    local guild = GuildHelper.Sync:GetGuildKey()
    if not guild then return end
    local key = guild .. ":" .. category .. ":" .. id
    if self.seen[key] then return end
    self.seen[key] = true
    if GuildHelper:GetConfig(category, false) ~= true then return end
    self:Enqueue({id = id, guild = guild, category = category, group = group, queued = self:GetDisplayTime()})
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

function Notifications:Test()
    self:SetEditing(false)
    self.current = {test = true, guild = GuildHelper.Sync:GetGuildKey()}
    self.expires = self:GetDisplayTime() + 8
    self:Render()
end

function Notifications:Render()
    if self.editing then return end
    if not self.current or InCombatLockdown() then
        if self.frame then self.frame:Hide() end
        return
    end
    if self.current.test then
        self:Create()
        self:ShowGroupAction(false)
        self.frame.title:SetText(GuildHelper:Trans("LID_NOTIFICATIONS"))
        self.frame.text:SetText(GuildHelper:Trans("LID_NOTIFICATIONTEST"))
        self.frame:Show()
        return
    end
    if self.current.order then
        local order = GuildHelper.Orders:GetOpenIncoming(self.current.id)
        if not order then self:Dismiss() return end
        self:Create()
        self:ShowGroupAction(false)
        self.frame.title:SetText(GuildHelper:Trans("LID_ORDER_NOTIFICATION"))
        self.frame.text:SetText(GuildHelper.Recipes:Name(order.recipe) .. "\n" .. GuildHelper.Orders:ContactLabel(order.requester, nil, true))
        self.frame:Show()
        order.notified = true
        return
    end
    if self.current.category then
        local source = self.current.group and GuildHelper.Groups or GuildHelper.Feedback
        local entry = source:Find(self.current.id)
        if not entry or GuildHelper:GetConfig(self.current.category, false) ~= true then self:Dismiss() return end
        self:Create()
        self:ShowGroupAction(false)
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
        self:ShowGroupAction(true)
        self.frame.title:SetText(GuildHelper:Trans("LID_NOTIFICATIONAPPLICATION"))
        self.frame.text:SetText(self.current.author .. "\n" .. groups:GetActivityName(entry))
        self.frame:Show()
        return
    end
    local entry = GuildHelper.Feedback:Find(self.current.id)
    if not entry or not GuildHelper.Feedback:IsSubscribed(entry) then self:Dismiss() return end
    self:Create()
    self:ShowGroupAction(false)
    self.frame.title:SetText(GuildHelper:Trans("LID_NOTIFICATIONCOMMENT"))
    local author = GuildHelper.Feedback:AuthorLabel(self.current)
    self.frame.text:SetText(format(GuildHelper:Trans("LID_NOTIFICATIONCOMMENTTEXT"), author, entry.title))
    self.frame:Show()
end

function Notifications:Tick()
    if InCombatLockdown() then return end
    local guild = GuildHelper.Sync:GetGuildKey()
    if self.current and self.current.guild ~= guild then self:Dismiss() end
    if self.editing then return end
    if self.current then
        if self.frame and self.frame:IsMouseOver() then self.expires = self:GetDisplayTime() + 8 end
        if self:GetDisplayTime() >= (self.expires or 0) then self:Dismiss() end
    end
    if not self.current then
        while #self.queue > 0 do
            local notice = self.queue[1]
            if notice.guild ~= guild or (not notice.order and self:GetDisplayTime() - notice.queued > 180) then
                table.remove(self.queue, 1)
            elseif not notice.order and not notice.applicant and not notice.category and not GuildHelper.Feedback:Find(notice.id) then
                if self:GetDisplayTime() - notice.queued < 30 then return end
                table.remove(self.queue, 1)
            else
                self.current = table.remove(self.queue, 1)
                self.expires = self:GetDisplayTime() + 8
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
        Notifications.combatStart = GetTime()
        Notifications:Render()
        return
    end
    if event == "PLAYER_REGEN_ENABLED" then
        if Notifications.combatStart then
            local duration = GetTime() - Notifications.combatStart
            Notifications.combatDuration = (Notifications.combatDuration or 0) + duration
            Notifications.combatStart = nil
        end
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
GuildHelper.Theme:OnRefresh(function()
    if Notifications.editing then Notifications:SetEditing(true) else Notifications:Render() end
end)
GuildHelper.Window:OnRebuild(function()
    if Notifications.frame then Notifications.frame:Hide() end
    Notifications.frame = nil
    Notifications.editing = false
end)
