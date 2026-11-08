local _, GuildHelper = ...
local Notifications = {queue = {}, seen = {}, started = time()}
GuildHelper.Notifications = Notifications
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
    frame.close = GuildHelper.Members:CreatePill(frame, "×")
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
        if notice.guild == GuildHelper.Sync:GetGuildKey() and feedback:Find(notice.id) then
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
    self:RestorePosition()
    frame:Hide()
end

function Notifications:Dismiss()
    self.current = nil
    self.expires = nil
    if self.frame and not self.editing then self.frame:Hide() end
end

function Notifications:SetEditing(active)
    self:Create()
    if self.editing and not active then self:SavePosition() end
    self.editing = active == true
    self.dragged = nil
    if self.editing then
        self.frame.title:SetText(GuildHelper:Trans("LID_NOTIFICATIONS"))
        self.frame.text:SetText(GuildHelper:Trans("LID_NOTIFICATIONMOVE"))
        self.frame:Show()
    else
        self.expires = GetTime() + 8
        self:Render()
    end
end

function Notifications:Comment(id, comment)
    if not comment or comment.created < self.started or comment.created > time() + 60 or GuildHelper.Groups:IsSelfName(comment.owner) then return end
    local guild = GuildHelper.Sync:GetGuildKey()
    if not guild then return end
    local key = guild .. ":" .. id .. ":" .. comment.id
    if self.seen[key] then return end
    self.seen[key] = true
    if #self.queue >= 20 then table.remove(self.queue, 1) end
    tinsert(self.queue, {id = id, guild = guild, author = comment.author or comment.owner, queued = GetTime()})
end

function Notifications:Render()
    if self.editing then return end
    if not self.current then
        if self.frame then self.frame:Hide() end
        return
    end
    local entry = GuildHelper.Feedback:Find(self.current.id)
    if not entry then self:Dismiss() return end
    self:Create()
    self.frame.title:SetText(GuildHelper:Trans("LID_NOTIFICATIONCOMMENT"))
    self.frame.text:SetText(format(GuildHelper:Trans("LID_NOTIFICATIONCOMMENTTEXT"), self.current.author, entry.title))
    self.frame:Show()
end

function Notifications:Tick()
    local guild = GuildHelper.Sync:GetGuildKey()
    if self.current and self.current.guild ~= guild then self:Dismiss() end
    if self.editing then return end
    if self.current then
        if self.frame and self.frame:IsMouseOver() then self.expires = GetTime() + 8 end
        if GetTime() >= (self.expires or 0) then self:Dismiss() end
    end
    if not self.current then
        while #self.queue > 0 do
            local notice = self.queue[1]
            if notice.guild ~= guild or GetTime() - notice.queued > 180 then
                table.remove(self.queue, 1)
            elseif not GuildHelper.Feedback:Find(notice.id) then
                if GetTime() - notice.queued < 30 then return end
                table.remove(self.queue, 1)
            else
                self.current = table.remove(self.queue, 1)
                self.expires = GetTime() + 8
                break
            end
        end
    end
    self:Render()
end

Notifications.events = CreateFrame("Frame")
Notifications.events:RegisterEvent("PLAYER_LOGIN")
Notifications.events:SetScript("OnEvent", function()
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
