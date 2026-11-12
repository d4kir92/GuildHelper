local _, GuildHelper = ...
local Events, Window, Theme = GuildHelper.Events, GuildHelper.Window, GuildHelper.Theme
local Groups, Members, Feedback = GuildHelper.Groups, GuildHelper.Members, GuildHelper.Feedback
local Dashboard = GuildHelper.Dashboard

function Events:Button(parent, label, width, action, primary)
    local button = Members:CreateButton(parent, label, primary)
    button:SetWidth(width)
    button:SetScript("OnClick", action)
    return button
end

function Events:List(parent, label)
    local card = Dashboard:CreateList(Dashboard:CreateCard(parent, label))
    card.scrollPage = function() end
    Feedback:AddThumb(card.scroll)
    return card
end

function Events:AuthorLabel(row, avatar)
    return Feedback:AuthorLabel({author = row.name, owner = row.author}, avatar)
end

function Events:RenderList(card, items)
    card.items = items
    local y = 0
    for index, item in ipairs(items) do
        local row = card.lines[index]
        if not row then
            row = CreateFrame("Button", nil, card.body)
            row.fill = Theme:Round(row, "rowHover", 5)
            row.text = Theme:Text(row, 12, "text")

            row.text:SetJustifyH("LEFT")
            row.text:SetWordWrap(true)
            row:SetScript("OnClick", function(button)
                if button.item.action then button.item.action() end
            end)
            row:SetScript("OnEnter", function(button)
                button.fill:SetShown(button.item.action ~= nil or button.item.selected == true)
                if button.item.tooltip then
                    GameTooltip:SetOwner(button, "ANCHOR_RIGHT")
                    GameTooltip:SetText(button.item.tooltip)
                    GameTooltip:Show()
                end
            end)
            row:SetScript("OnLeave", function(button)
                button.fill:SetShown(button.item.selected == true)
                if GameTooltip:IsOwned(button) then GameTooltip:Hide() end
            end)
            card.lines[index] = row
        end

        row.item = item
        row:ClearAllPoints()
        row:SetPoint("TOPLEFT", card.body, "TOPLEFT", 0, -y)
        row:SetPoint("TOPRIGHT", card.body, "TOPRIGHT", 0, -y)
        row.text:ClearAllPoints()
        local textTop = -5
        local authorHeight = 0
        if item.author then
            if not row.avatar then
                row.avatar = Members:CreateAvatar(row, 16, 9)
                row.avatar:SetPoint("TOPLEFT", 8, -4)
                row.author = Theme:Text(row, 12, "text")
                row.author:SetPoint("TOPLEFT", 29, -5)
                row.author:SetPoint("TOPRIGHT", -8, -5)
                row.author:SetJustifyH("LEFT")
                row.author:SetWordWrap(true)
            end
            row.avatar:Show()
            row.author:Show()
            row.author:SetText(self:AuthorLabel(item.author, row.avatar) .. (item.meta or ""))
            authorHeight = max(17, row.author:GetStringHeight() + 2)
            textTop = textTop - authorHeight
        elseif row.avatar then
            row.avatar:Hide()
            row.author:Hide()
        end
        row.text:SetPoint("TOPLEFT", item.author and 29 or 8, textTop)
        row.text:SetPoint("TOPRIGHT", -8, textTop)
        row.text:SetText(item.text)
        row.text:SetShown(item.text ~= "")
        Theme:SetKey(row.text, item.color or "text")
        row.fill:SetShown(item.selected == true)
        row:Show()
        local height = max(24, authorHeight + (item.text == "" and 0 or row.text:GetStringHeight()) + 10)
        row:SetHeight(height)
        y = y + height
    end
    for index = #items + 1, #card.lines do card.lines[index]:Hide() end
    card.body:SetHeight(max(1, y))
    Feedback:UpdateThumb(card.scroll)
end

function Events:BindListSize(card)
    card.body:SetScript("OnSizeChanged", function(_, width)
        if width == card.lastWidth then return end
        card.lastWidth = width
        if card.items then self:RenderList(card, card.items) end
    end)
end

function Events:FormField(parent, key, limit, x, y, width, field)
    local label = Groups:Text(parent, key, x, y)
    local box = Groups:CreateBox(parent, limit)
    box:SetPoint("TOPLEFT", label, "BOTTOMLEFT", 0, -5)
    if width then
        box:SetWidth(width)
    else
        box:SetPoint("RIGHT", parent, "RIGHT", -18, 0)
    end
    box:SetScript("OnTextChanged", function(edit)
        if self.draft then self.draft[field] = edit:GetText() end
        self:ValidateForm()
    end)
    return box
end

function Events:ValidateForm()
    if not self.form or not self.form.submit or not self.draft then return end
    local draft = self.draft
    local valid = self:ParseDate(draft.day, draft.clock)
    self.form.submit:SetEnabled(valid ~= nil and Groups:CleanText(draft.title, 120) ~= "")
    self.form.invalid:SetShown(not valid)
end

function Events:BuildForm(panel)
    local form = CreateFrame("Frame", nil, panel)
    form:SetAllPoints()
    self.form = form
    form.iconButton = self:Button(form, "LID_EVENT_ICON", 157, function() self:OpenIconPicker() end)
    form.iconButton:SetPoint("TOPLEFT", 18, -15)
    form.icon = form.iconButton:CreateTexture(nil, "ARTWORK")
    form.icon:SetSize(19, 19)
    form.icon:SetPoint("LEFT", 9, 0)
    form.icon:Hide()
    form.title = self:FormField(form, "LID_FBTITLE", 120, 18, -56, nil, "title")
    form.day = self:FormField(form, "LID_GROUPDATE", 10, 18, -112, 136, "day")
    form.clock = self:FormField(form, "LID_EVENT_TIME", 5, 169, -112, 100, "clock")
    form.import = self:Button(form, "LID_EVENT_IMPORT", 240, function()
        GuildHelper.Calendar:Pick(self.draft.day)
    end)
    form.import:SetPoint("TOPLEFT", form, "TOPLEFT", 18, -169)
    form.invalid = Groups:Text(form, "LID_EVENT_INVALID_DATE", 18, -208, 12, "accent")
    form.invalid:SetPoint("RIGHT", form, "RIGHT", -18, 0)
    Groups:Text(form, "LID_EVENT_INFO", 18, -239)
    local area = CreateFrame("Frame", nil, form)
    area:SetPoint("TOPLEFT", 18, -258)
    area:SetPoint("BOTTOMRIGHT", -18, 62)
    area.ghNoInside = true
    Theme:Panel(area, "control", "border", 6)
    local scroll = CreateFrame("ScrollFrame", nil, area)
    scroll:SetPoint("TOPLEFT", 8, -5)
    scroll:SetPoint("BOTTOMRIGHT", -13, 5)
    local box = CreateFrame("EditBox", nil, scroll)
    form.info = box
    box:SetSize(200, 22)
    box:SetAutoFocus(false)
    box:SetMultiLine(true)
    box:SetMaxLetters(500)
    box:SetTextInsets(0, 0, 2, 2)
    Theme:Track(box, "text", "text", 13)
    scroll:SetScrollChild(box)
    scroll:SetScript("OnSizeChanged", function(_, width) box:SetWidth(max(1, width)) end)
    scroll:EnableMouseWheel(true)
    scroll:SetScript("OnMouseWheel", function(sel, delta)
        sel:SetVerticalScroll(min(max(sel:GetVerticalScroll() - delta * 26, 0), sel:GetVerticalScrollRange()))
    end)
    Feedback:AddThumb(scroll, 3)
    box:SetScript("OnCursorChanged", function(_, _, y, _, height)
        local top, view = -y, scroll:GetVerticalScroll()
        if top < view then
            scroll:SetVerticalScroll(top)
        elseif top + height > view + scroll:GetHeight() then
            scroll:SetVerticalScroll(top + height - scroll:GetHeight())
        end
    end)
    box:SetScript("OnEscapePressed", function(edit) edit:ClearFocus() end)
    box:SetScript("OnTextChanged", function(edit)
        if self.draft then self.draft.info = edit:GetText() end
    end)
    area:EnableMouse(true)
    area:SetScript("OnMouseDown", function() box:SetFocus() end)
    form.submit = self:Button(form, "LID_EVENT_CREATE", 155, function()
        local draft = self.draft
        if not draft then return end
        local when = self:ParseDate(draft.day, draft.clock)
        local title = Groups:CleanText(draft.title, 120)
        if not when or title == "" then return end
        local id
        if draft.event then
            id = self:UpdateEvent(draft.event, when, title, draft.info, draft.icon)
        else
            id = self:Publish(when, title, draft.info, draft.icon)
        end
        if id then self:Select(id) end
    end, true)
    form.submit:SetPoint("BOTTOMRIGHT", -18, 14)
    local cancel = self:Button(form, "LID_FBCANCEL", 120, function() self:Select(self.selected) end)
    cancel:SetPoint("RIGHT", form.submit, "LEFT", -8, 0)
    form:Hide()
end

function Events:NewDraft()
    self:GetStore()
    self.draft = {day = date("%Y-%m-%d", self:Today()), clock = "20:00", title = "", info = ""}
    self:LoadDraft()
    self:Refresh()
    if self.form then self.form.title:SetFocus() end
end

function Events:Edit(id)
    local bucket = self:Get(id)
    local event = bucket and bucket.event
    if not self:IsOwn(event) then return end
    local day, clock = event.when:match("^(%S+) (%S+)$")
    self.draft = {event = id, day = day, clock = clock, title = event.title, info = event.info, icon = self:GetIcon(id)}
    self:LoadDraft()
    self:Refresh()
end

function Events:LoadDraft()
    local draft = self.draft
    if not self.form or not draft then return end
    local values = {day = draft.day, clock = draft.clock, title = draft.title, info = draft.info}
    for field, value in pairs(values) do self.form[field]:SetText(value) end
    self:RefreshIconPreview()
    Theme:SetTrans(self.form.submit.text, draft.event and "LID_FBSAVE" or "LID_EVENT_CREATE")
    self:ValidateForm()
end

function Events:Import(item)
    if not self.draft then return end
    self.draft.title = Groups:CleanText(item.title, 120)
    self.draft.day, self.draft.clock = item.when:match("^(%S+) (%S+)$")
    self:LoadDraft()
    Window:SelectPage("events")
end

function Events:BuildDetail(panel)
    local detail = CreateFrame("Frame", nil, panel)
    detail:SetAllPoints()
    self.detail = detail
    detail.roles, detail.statuses = {}, {}
    detail.heading = Groups:Text(detail, nil, 16, -15, 16, "text")
    detail.heading:SetWordWrap(false)
    detail.delete = self:Button(detail, "LID_FBDELETE", 136, function()
        local id = self.selected
        if detail.confirmDelete == id then
            detail.confirmDelete = nil
            self:Delete(id)
        else
            detail.confirmDelete = id
            self:RefreshDetail()
        end
    end)
    detail.delete:SetPoint("TOPRIGHT", -16, -10)
    detail.edit = self:Button(detail, "LID_EVENT_EDIT", 136, function() self:Edit(self.selected) end)
    detail.edit:SetPoint("RIGHT", detail.delete, "LEFT", -6, 0)
    detail.avatar = Members:CreateAvatar(detail, 16, 9)
    detail.avatar:SetPoint("TOPLEFT", 16, -42)
    detail.meta = Groups:Text(detail, nil, 37, -45)
    detail.meta:SetPoint("RIGHT", detail, "RIGHT", -16, 0)
    detail.meta:SetWordWrap(false)
    Groups:Text(detail, "LID_EVENT_ROLE", 16, -63)
    for index, role in ipairs({"TANK", "HEALER", "DAMAGER"}) do
        local button = self:Button(detail, self.roles[role], 119, function()
            detail.role = role
            self:RefreshDetail()
        end)
        button:SetPoint("TOPLEFT", 16 + (index - 1) * 125, -79)
        detail.roles[role] = button
    end
    Groups:Text(detail, "LID_EVENT_RSVP_NOTE", 16, -115)
    detail.note = Groups:CreateBox(detail, 240)
    detail.note:SetPoint("TOPLEFT", 16, -132)
    detail.note:SetPoint("TOPRIGHT", -16, -132)
    for index, status in ipairs({"A", "T", "D"}) do
        local button = self:Button(detail, self.statuses[status], 119, function()
            self:Respond(self.selected, detail.role, status, detail.note:GetText())
            detail.note:ClearFocus()
        end)
        button:SetPoint("TOPLEFT", 16 + (index - 1) * 125, -168)
        detail.statuses[status] = button
    end
    detail.list = self:List(detail, "LID_FBDETAIL")
    detail.list:SetPoint("TOPLEFT", 8, -208)
    detail.list:SetPoint("BOTTOMRIGHT", -8, 54)
    self:BindListSize(detail.list)
    local function post()
        if self:Comment(self.selected, detail.comment:GetText()) then
            detail.comment:SetText("")
            detail.comment:ClearFocus()
        end
    end
    local send = self:Button(detail, "LID_FBSEND", 96, post)
    send:SetPoint("BOTTOMRIGHT", -16, 12)
    detail.comment = Groups:CreateBox(detail, 240)
    detail.comment:SetPoint("LEFT", detail, "LEFT", 16, 0)
    detail.comment:SetPoint("RIGHT", send, "LEFT", -8, 0)
    detail.comment:SetPoint("TOP", send, "TOP", 0, -2)
    detail.comment:SetScript("OnEnterPressed", post)
    detail.comment:SetScript("OnTextChanged", function(edit)
        send:SetEnabled(Groups:CleanText(edit:GetText(), 240) ~= "")
    end)
    send:SetEnabled(false)
    detail:Hide()
end

function Events:Select(id)
    self:GetStore()
    self.selected, self.draft = id, nil
    if self.detail then self.detail.confirmDelete = nil end
    self:Refresh()
end

function Events:RefreshDetail()
    local detail = self.detail
    local bucket = self:Get(self.selected)
    local event = bucket and bucket.event
    detail:SetShown(event ~= nil and self.draft == nil)
    self.empty:SetShown(not event and not self.draft)
    if not event or self.draft then return end

    local response = self:GetResponse(bucket)
    if detail.event ~= event.id then
        detail.event = event.id
        detail.confirmComment = nil
        detail.role = response and response.role or nil
        detail.note:SetText(response and response.text or "")
        detail.comment:SetText("")
        detail.list.scroll:SetVerticalScroll(0)
    end

    for role, button in pairs(detail.roles) do
        Theme:SetKey(button.text, detail.role == role and "accent" or "text")
    end
    for status, button in pairs(detail.statuses) do
        button:SetEnabled(detail.role ~= nil)
        Theme:SetKey(button.text, response and response.status == status and "accent" or "text")
    end

    local own = self:IsOwn(event)
    local canDelete = self:CanDelete(event)
    detail.edit:SetShown(own)
    detail.delete:SetShown(canDelete)
    Theme:SetTrans(detail.delete.text, detail.confirmDelete == event.id and "LID_FBCONFIRM" or "LID_FBDELETE")
    detail.heading:SetPoint("RIGHT", detail, "RIGHT", own and -306 or canDelete and -164 or -16, 0)
    detail.heading:SetText(self:IconMarkup(self:GetIcon(event.id), 17) .. event.title)
    detail.meta:SetText(self:AuthorLabel(event, detail.avatar) .. "  ·  " .. event.when)
    local items = {}
    if event.info ~= "" then tinsert(items, {text = event.info}) end
    tinsert(items, {text = GuildHelper:Trans("LID_EVENT_RESPONSES"), color = "accent"})
    local responses, comments = {}, {}
    for _, row in pairs(bucket.responses) do tinsert(responses, row) end
    for _, row in pairs(bucket.comments) do
        if row.text ~= "" then tinsert(comments, row) end
    end
    table.sort(responses, function(a, b) return a.author < b.author end)
    table.sort(comments, function(a, b)
        if a.revision ~= b.revision then return a.revision < b.revision end
        return a.comment < b.comment
    end)
    for _, row in ipairs(responses) do
        local meta = "  ·  " .. GuildHelper:Trans(self.roles[row.role]) .. "  ·  " .. GuildHelper:Trans(self.statuses[row.status])
        tinsert(items, {author = row, meta = meta, text = row.text})
    end
    tinsert(items, {text = GuildHelper:Trans("LID_FBCOMMENTS"), color = "accent"})
    if #comments == 0 then tinsert(items, {text = GuildHelper:Trans("LID_FBNOCOMMENTS"), color = "muted"}) end
    for _, row in ipairs(comments) do
        local item = {author = row, meta = "  ·  " .. Feedback:FormatDate(row.revision), text = row.text}
        if self:IsOwn(row) then
            item.tooltip = GuildHelper:Trans("LID_FBDELETECOMMENT")
            item.action = function()
                if detail.confirmComment == row.comment then
                    detail.confirmComment = nil
                    self:Comment(event.id, "", row.comment)
                else
                    detail.confirmComment = row.comment
                    self:RefreshDetail()
                end
            end
            if detail.confirmComment == row.comment then
                item.text = item.text .. "\n" .. GuildHelper:Trans("LID_FBCONFIRM")
                item.selected = true
            end
        end
        tinsert(items, item)
    end
    self:RenderList(detail.list, items)
end

function Events:Refresh()
    if not self.content or not self.content:IsVisible() or not IsInGuild() then return end
    local items = {}
    for _, event in ipairs(self:GetList()) do
        tinsert(items, {text = self:IconMarkup(self:GetIcon(event.id), 14) .. event.title .. "\n" .. event.when, selected = event.id == self.selected and not self.draft,
            action = function() self:Select(event.id) end})
    end
    if #items == 0 then tinsert(items, {text = GuildHelper:Trans("LID_EVENT_EMPTY"), color = "muted"}) end
    self:RenderList(self.list, items)
    self.form:SetShown(self.draft ~= nil)
    if not self.draft and self.iconPicker then self.iconPicker:Hide() end
    self.form.import:SetEnabled(GuildHelper.Calendar:HasAPI())
    self:RefreshDetail()
end

function Events:OnChanged()
    self:Refresh()
    if GuildHelper.Calendar then GuildHelper.Calendar:QueueRefresh() end
end

function Events:Build(content)
    self.content = content
    Window:CreatePageTitle(content, "LID_EVENTS")
    local create = self:Button(content, "LID_EVENT_CREATE", 155, function() self:NewDraft() end, true)
    create:SetPoint("TOPRIGHT", -76, -22)
    self.list = self:List(content, "LID_EVENTS")
    self.list:SetPoint("TOPLEFT", 20, -70)
    self.list:SetPoint("BOTTOMLEFT", 20, 20)
    self.list:SetWidth(276)
    self:BindListSize(self.list)
    local panel = CreateFrame("Frame", nil, content)
    panel:SetPoint("TOPLEFT", self.list, "TOPRIGHT", 12, 0)
    panel:SetPoint("BOTTOMRIGHT", -22, 20)
    Theme:Panel(panel, "panel", "border", 7)
    self.empty = Groups:Text(panel, "LID_EVENT_SELECT", 18, -18, 13)
    self:BuildForm(panel)
    self:BuildDetail(panel)
    self:LoadDraft()
    content.OnPageShow = function()
        Members:Scan()
        self:Refresh()
        self:Request()
    end
    content.OnPageHide = function()
        self.detail.confirmDelete = nil
        if self.iconPicker then self.iconPicker:Hide() end
    end
end

Window:SetPageBuilder("events", function(content) Events:Build(content) end)
Window:OnRebuild(function() Events.content, Events.form, Events.detail, Events.iconPicker = nil, nil, nil, nil end)
Theme:OnRefresh(function() Events:Refresh() end)
GuildHelper.Sync:OnUpdate(function() Events:Refresh() end)
local roster = CreateFrame("Frame")
for _, event in ipairs({"GUILD_ROSTER_UPDATE", "INITIAL_CLUBS_LOADED", "CLUB_MEMBERS_UPDATED", "CLUB_MEMBER_UPDATED"}) do
    if not C_EventUtils or not C_EventUtils.IsEventValid or C_EventUtils.IsEventValid(event) then
        pcall(roster.RegisterEvent, roster, event)
    end
end
roster:SetScript("OnEvent", function()
    if Events.content and Events.content:IsVisible() and IsInGuild() then
        Members:Scan()
        Events:Refresh()
    end
end)
