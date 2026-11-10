local _, GuildHelper = ...
local Window, Theme, Members, Sync = GuildHelper.Window, GuildHelper.Theme, GuildHelper.Members, GuildHelper.Sync
local Groups, Recipes, Professions = GuildHelper.Groups, GuildHelper.Recipes, GuildHelper.Professions
local Orders = {pending = {}, heard = {}, answers = {}, queued = {}, states = {O = 1, C = 2, D = 3}}
GuildHelper.Orders = Orders

function Orders:GetStore()
    local guild = Sync:GetGuildKey()
    if guild ~= self.guild then
        self.guild = guild
        self.pending, self.heard, self.answers, self.queued = {}, {}, {}, {}
        self.draft, self.selected, self.lastRequest = nil, nil, nil
    end
    if not guild then return end
    GHTAB = GHTAB or {}
    GHTAB.ORDERS = GHTAB.ORDERS or {}
    GHTAB.ORDERS[guild] = GHTAB.ORDERS[guild] or {}
    return GHTAB.ORDERS[guild]
end

function Orders:Find(id)
    local store = self:GetStore()
    return store and store[id]
end

function Orders:IsIncoming(order)
    return Groups:IsSelfName(order.crafter)
end

function Orders:GetOpenIncoming(id)
    local order = self:Find(id)
    if order and order.status == "O" and self:IsIncoming(order) then return order end
end

function Orders:Count()
    local count = 0
    for _, order in pairs(self:GetStore() or {}) do
        if order.status == "O" and self:IsIncoming(order) then count = count + 1 end
    end
    return count
end

function Orders:ShortName(name)
    local short = strsplit("-", name)
    return short
end

function Orders:Encode(order)
    local materials = {}
    for _, row in ipairs(order.materials) do
        tinsert(materials, format("%d:%d:%s", row.quantity, row.owned, table.concat(row.options, ".")))
    end
    return table.concat({order.requester, order.crafter, order.recipe, order.delivery, order.status, table.concat(materials, ",")}, "~")
end

function Orders:Decode(id, payload)
    local requester, crafter, recipe, delivery, status, materials = payload:match("^([^~]+)~([^~]+)~(%d+)~([MT])~([OCD])~([%d:.,%-]*)$")
    recipe = tonumber(recipe)
    if not requester or Groups:Name(requester) ~= requester or not crafter or Groups:Name(crafter) ~= crafter or requester == crafter then return end
    if not recipe or recipe < 1 or recipe > 2147483647 or recipe ~= floor(recipe) then return end
    if (delivery ~= "M" and delivery ~= "T") or not self.states[status] or not materials then return end
    local rows = {}
    for record in materials:gmatch("[^,]+") do
        local quantity, owned, encoded = record:match("^(%d+):(%d+):([%d.%-]+)$")
        quantity, owned = tonumber(quantity), tonumber(owned)
        if not quantity or quantity < 1 or quantity > 999999 or owned > quantity or #rows >= 48 then return end
        local options = {}
        for value in encoded:gmatch("[^.]+") do
            local option = tonumber(value)
            if not option or option == 0 or abs(option) > 2147483647 or #options >= 24 then return end
            tinsert(options, option)
        end
        if #options == 0 then return end
        tinsert(rows, {quantity = quantity, owned = owned, options = options})
    end
    return {id = id, requester = requester, crafter = crafter, recipe = recipe, delivery = delivery, status = status, materials = rows}
end

function Orders:Send(order, relay)
    local guild = Sync:GetGuildKey()
    if not guild then return end
    local payload = self:Encode(order)
    local size = 200
    local total = ceil(#payload / size)
    if total > 16 then return end
    for part = 1, total do
        local message = format("O~%s~%s~%d~%d~%s", order.id, relay and "R" or "S", part, total, payload:sub((part - 1) * size + 1, part * size))
        Sync:Send(message, nil, nil, guild)
    end
    return true
end

function Orders:SelfName()
    local member = Members:GetSelf()
    return member and Groups:Name(member.name) or Groups:Self()
end

function Orders:Digest(store, participant)
    local states = {}
    for id, order in pairs(store) do
        if order.requester == participant or order.crafter == participant then
            tinsert(states, id .. order.status)
        end
    end
    table.sort(states)
    return tostring(GuildHelper.Feedback:Hash(table.concat(states, ",")))
end

function Orders:Request()
    local store = self:GetStore()
    if not store or (self.lastRequest and GetTime() - self.lastRequest < 45) then return end
    self.lastRequest = GetTime()
    Sync:Send("O?~" .. self:Digest(store, self:SelfName()), nil, nil, self.guild)
end

function Orders:OnRequest(sender, digest)
    if self.answers[sender] and GetTime() - self.answers[sender] < 45 then return end
    local guild, requested = self.guild, GetTime()
    self.answers[sender] = requested
    C_Timer.After(random(2, 15), function()
        local store = self:GetStore()
        if not store or self.guild ~= guild or digest == self:Digest(store, sender) then return end
        for id, order in pairs(store) do
            if order.requester == sender or order.crafter == sender then
                local heard = self.heard[id]
                if not heard or heard.at < requested or heard.status ~= order.status then self:Send(order, true) end
            end
        end
    end)
end

function Orders:OnMessage(message, sender)
    local store = self:GetStore()
    sender = Groups:Name(sender)
    if not store or not sender or Groups:IsSelfName(sender) then return end
    local digest = message:match("^O%?~(%d+)$")
    if digest and #digest <= 10 then return self:OnRequest(sender, digest) end
    if #message > 255 then return end
    local id, mode, part, total, chunk = message:match("^O~(%d+%.%d+)~([SR])~(%d+)~(%d+)~(.*)$")
    part, total = tonumber(part), tonumber(total)
    if not id or #id > 23 or not part or not total or part < 1 or part > total or total > 16 or #chunk > 200 then return end
    local key = sender .. "~" .. id .. "~" .. mode
    local state = self.pending[key]
    if not state or state.total ~= total or GetTime() - state.at > 120 or (part == 1 and state.parts[1] and state.parts[1] ~= chunk) then
        state = {parts = {}, total = total, count = 0, at = GetTime()}
        self.pending[key] = state
    end
    if state.parts[part] then return end
    state.parts[part] = chunk
    state.count = state.count + 1
    if state.count ~= total then return end
    self.pending[key] = nil
    local order = self:Decode(id, table.concat(state.parts))
    if not order then return end
    if mode == "S" and sender ~= (order.status == "D" and order.crafter or order.requester) then return end
    local previous = store[id]
    if previous and (previous.requester ~= order.requester or previous.crafter ~= order.crafter or previous.recipe ~= order.recipe or previous.delivery ~= order.delivery) then return end
    self.heard[id] = {status = order.status, at = GetTime()}
    if previous and self.states[previous.status] >= self.states[order.status] then return end
    if previous then
        previous.status = order.status
    else
        store[id] = order
    end
    self:Refresh()
end

function Orders:Notify()
    local notifications = GuildHelper.Notifications
    for id, order in pairs(self:GetStore() or {}) do
        if order.status == "O" and self:IsIncoming(order) and not order.notified and not self.queued[id] then
            self.queued[id] = true
            notifications:Enqueue({id = id, order = true, guild = self.guild, queued = notifications:GetDisplayTime()})
        end
    end
end

function Orders:SetStatus(order, status)
    if order.status ~= "O" then return end
    if status == "D" and not self:IsIncoming(order) then return end
    if status == "C" and not Groups:IsSelfName(order.requester) then return end
    order.status = status
    self:Send(order)
    self:Refresh()
end

function Orders:MaterialText(row)
    return table.concat(Recipes:MaterialNames(row), " / ")
end

function Orders:ShowContact(page, name)
    local member
    for _, candidate in ipairs(Members.list) do
        if Groups:Name(candidate.name) == name then
            member = candidate
            break
        end
    end
    page.avatar:SetShown(member ~= nil)
    page.subtitle:SetPoint("TOPLEFT", member and 38 or 14, -36)
    page.subtitle:SetText(member and member.short or self:ShortName(name))
    if member then
        local r, g, b = Members:GetClassColor(member)
        Members:FillAvatar(page.avatar, member, Members:GetData(member), r, g, b)
    end
end

function Orders:DeliveryLabel(delivery)
    return delivery == "M" and "LID_ORDER_MAIL" or "LID_ORDER_TRADE"
end

function Orders:Compose(member, recipe, requirements)
    local store = self:GetStore()
    local requester = self:SelfName()
    local crafter = Groups:Name(member.name)
    if not requirements or not store or not requester or not crafter or Groups:IsSelfName(crafter) then return end
    if not Recipes:CanOrder(Members:GetData(member), recipe) then return end
    self.draft = {requester = requester, crafter = crafter, crafterName = member.short, recipe = recipe, delivery = "M", status = "O", materials = requirements}
    for _, row in ipairs(requirements) do row.owned = 0 end
    self.mode = "outgoing"
    Window:SelectPage("orders")
end

function Orders:Submit()
    local draft, store = self.draft, self:GetStore()
    if not draft or not store or draft ~= self.draft then return end
    draft.id = format("%d.%09d", time(), random(1, 999999999))
    if not Recipes:CanOrder(Sync:GetData(draft.crafterName), draft.recipe) or store[draft.id] or not self:Decode(draft.id, self:Encode(draft)) or not self:Send(draft) then
        self.page.error:SetText(GuildHelper:Trans("LID_ORDER_ERROR"))
        return
    end
    store[draft.id] = draft
    self.draft, self.selected = nil, draft.id
    self:Refresh()
end

function Orders:Open(id)
    self.draft, self.selected, self.mode = nil, id, "incoming"
    Window.frame:Show()
    Window:SelectPage("orders")
end

function Orders:RenderDraft(page, draft)
    if page.renderedDraft == draft then return end
    page.renderedDraft = draft
    for _, row in ipairs(page.inputs) do
        row.box:ClearFocus()
        row:Hide()
    end
    page.error:SetText("")
    if not draft then return end
    page.form.scroll:SetVerticalScroll(0)
    page.title:SetText(Recipes:Name(draft.recipe))
    page.icon:SetTexture(Recipes:Icon(draft.recipe))
    self:ShowContact(page, draft.crafter)
    page.mail:SetAlpha(draft.delivery == "M" and 1 or 0.65)
    page.trade:SetAlpha(draft.delivery == "T" and 1 or 0.65)
    for index, material in ipairs(draft.materials) do
        local row = page.inputs[index]
        if not row then
            row = CreateFrame("Frame", nil, page.form.body)
            row:SetPoint("TOPLEFT", 0, -(index - 1) * 40)
            row:SetPoint("TOPRIGHT", 0, -(index - 1) * 40)
            row:SetHeight(38)
            row.box = Groups:CreateBox(row, 6, true)
            row.box:SetPoint("RIGHT", -8, 0)
            row.box:SetWidth(65)
            row.icon = row:CreateTexture(nil, "ARTWORK")
            row.icon:SetSize(20, 20)
            row.icon:SetPoint("LEFT", 43, 0)
            row.quantity = Theme:Text(row, 13, "text")
            row.quantity:SetPoint("LEFT", 8, 0)
            row.quantity:SetWidth(30)
            row.quantity:SetJustifyH("RIGHT")
            row.label = Theme:Text(row, 13, "text")
            row.label:SetPoint("LEFT", 70, 0)
            row.label:SetPoint("RIGHT", row.box, "LEFT", -8, 0)
            row.label:SetHeight(36)
            row.label:SetJustifyH("LEFT")
            row.label:SetWordWrap(true)
            page.inputs[index] = row
        end
        row.icon:SetTexture(Recipes:MaterialIcon(material.options[1]))
        row.quantity:SetText(format("%dx", material.quantity))
        row.label:SetText(self:MaterialText(material))
        row.box:SetScript("OnTextChanged", nil)
        row.box:SetText(tostring(material.owned))
        row.box:SetScript("OnTextChanged", function(box)
            local entered = tonumber(box:GetText()) or 0
            local value = min(material.quantity, max(0, floor(entered)))
            material.owned = value
            if entered ~= value then box:SetText(tostring(value)) end
        end)
        row:Show()
    end
    page.form.body:SetHeight(max(1, #draft.materials * 40))
end

function Orders:Refresh()
    local store = self:GetStore()
    Window:UpdateNavCount("orders", self:Count())
    self:Notify()
    local page = self.page
    if not page or not page:IsVisible() then return end
    local entries, selected = {}, nil
    local incoming = self.mode ~= "outgoing"
    for _, order in pairs(store or {}) do
        if (incoming and self:IsIncoming(order)) or (not incoming and Groups:IsSelfName(order.requester)) then
            local contact = incoming and order.requester or order.crafter
            local label = format("%s  |cffaaaaaa%s|r", Recipes:Name(order.recipe), self:ShortName(contact))
            tinsert(entries, {key = order.id, label = label, id = order.recipe, order = order})
            if order.id == self.selected then selected = order end
        end
    end
    table.sort(entries, function(a, b)
        local aa, bb = a.order.status == "O", b.order.status == "O"
        if aa ~= bb then return aa end
        return a.key > b.key
    end)
    selected = selected or (entries[1] and entries[1].order)
    self.selected = selected and selected.id
    page.incoming:SetAlpha(incoming and 1 or 0.65)
    page.outgoing:SetAlpha(incoming and 0.65 or 1)
    Professions:ShowRows(page.list, entries, function(id)
        self.draft, self.selected = nil, id
        page.detail.scroll:SetVerticalScroll(0)
        self:Refresh()
    end, self.selected)
    page.empty:SetShown(#entries == 0)
    local draft = self.draft
    page.form:SetShown(draft ~= nil)
    page.mail:SetShown(draft ~= nil)
    page.trade:SetShown(draft ~= nil)
    page.submit:SetShown(draft ~= nil)
    page.abort:SetShown(draft ~= nil)
    page.have:SetShown(draft ~= nil)
    page.error:SetShown(draft ~= nil)
    page.detail:SetShown(draft == nil and selected ~= nil)
    page.action:SetShown(draft == nil and selected ~= nil and selected.status == "O")
    page.whisper:SetShown(draft == nil and selected ~= nil)
    page.title:SetShown(draft ~= nil or selected ~= nil)
    page.icon:SetShown(draft ~= nil or selected ~= nil)
    page.subtitle:SetShown(draft ~= nil or selected ~= nil)
    if not draft and not selected then page.avatar:Hide() end
    self:RenderDraft(page, draft)
    if draft then
        for index, material in ipairs(draft.materials) do
            page.inputs[index].label:SetText(self:MaterialText(material))
        end
    elseif selected then
        local contact = incoming and selected.requester or selected.crafter
        page.title:SetText(Recipes:Name(selected.recipe))
        page.icon:SetTexture(Recipes:Icon(selected.recipe))
        self:ShowContact(page, contact)
        local rows = {
            {label = GuildHelper:Trans(self:DeliveryLabel(selected.delivery))},
            {label = GuildHelper:Trans("LID_ORDER_STATUS_" .. selected.status)},
            {label = GuildHelper:Trans("LID_ORDER_OWNED") .. " / " .. GuildHelper:Trans("LID_RECIPE_MATERIALS")}
        }
        for _, material in ipairs(selected.materials) do
            tinsert(rows, {label = format("%s  (%d/%d)", self:MaterialText(material), material.owned, material.quantity), prefix = format("%dx", material.quantity), icon = Recipes:MaterialIcon(material.options[1])})
        end
        Professions:ShowRows(page.detail, rows)
        Theme:SetTrans(page.action.text, incoming and "LID_ORDER_COMPLETE" or "LID_FBCANCEL")
        page.action:SetScript("OnClick", function() self:SetStatus(selected, incoming and "D" or "C") end)
        page.whisper:SetScript("OnClick", function()
            local target = contact
            for _, member in ipairs(Members.list) do
                if Groups:Name(member.name) == contact then target = member.name break end
            end
            Members:Whisper({name = target})
        end)
    end
end

function Orders:Build(content)
    local title = Window:CreatePageTitle(content, "LID_ORDER_TITLE")
    local page = CreateFrame("Frame", nil, content)
    self.page = page
    page.inputs = {}
    page:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -12)
    page:SetPoint("BOTTOMRIGHT", -Window.PADDING, Window.PADDING)

    page.incoming = Members:CreateButton(page, "LID_ORDER_INCOMING")
    page.incoming:SetPoint("TOPLEFT")
    page.incoming:SetWidth(145)
    page.outgoing = Members:CreateButton(page, "LID_ORDER_OUTGOING")
    page.outgoing:SetPoint("LEFT", page.incoming, "RIGHT", 8, 0)
    page.outgoing:SetWidth(145)
    for mode, button in pairs({incoming = page.incoming, outgoing = page.outgoing}) do
        button:SetScript("OnClick", function()
            self.mode, self.draft, self.selected = mode, nil, nil
            page.list.scroll:SetVerticalScroll(0)
            page.detail.scroll:SetVerticalScroll(0)
            self:Refresh()
        end)
    end
    page.list = Professions:CreateList(page)
    page.list:SetPoint("TOPLEFT", 0, -42)
    page.list:SetPoint("BOTTOMLEFT")
    page.list:SetWidth(300)
    page.empty = Theme:Text(page.list, 13, "muted")
    Theme:SetTrans(page.empty, "LID_NODATA")
    page.empty:SetPoint("CENTER")
    local side = CreateFrame("Frame", nil, page)
    side:SetPoint("TOPLEFT", page.list, "TOPRIGHT", 12, 0)
    side:SetPoint("BOTTOMRIGHT")
    Theme:Panel(side, "panel", "border", 7)

    page.title = Theme:Text(side, 17, "text")
    page.icon = side:CreateTexture(nil, "ARTWORK")
    page.icon:SetSize(22, 22)
    page.icon:SetPoint("TOPLEFT", 14, -9)
    page.title:SetPoint("TOPLEFT", 44, -10)
    page.title:SetPoint("TOPRIGHT", -14, -10)
    page.title:SetJustifyH("LEFT")
    page.subtitle = Theme:Text(side, 13, "muted")
    page.subtitle:SetPoint("TOPLEFT", 14, -36)
    page.avatar = Members:CreateAvatar(side, 18, 10)
    page.avatar:SetPoint("TOPLEFT", 14, -33)
    page.avatar:Hide()
    page.detail = Professions:CreateList(side, true)
    page.detail:SetPoint("TOPLEFT", 10, -59)
    page.detail:SetPoint("BOTTOMRIGHT", -10, 50)
    page.form = Professions:CreateList(side)
    page.form:SetPoint("TOPLEFT", 10, -116)
    page.form:SetPoint("BOTTOMRIGHT", -10, 50)
    page.have = Theme:Text(side, 12, "muted")
    Theme:SetTrans(page.have, "LID_ORDER_OWNED")
    page.have:SetPoint("BOTTOMRIGHT", page.form, "TOPRIGHT", -24, 4)
    page.error = Theme:Text(side, 12, "muted")
    page.error:SetPoint("BOTTOMLEFT", 12, 12)
    page.error:SetPoint("BOTTOMRIGHT", -278, 12)
    page.error:SetJustifyH("LEFT")

    page.mail = Members:CreateButton(side, "LID_ORDER_MAIL")
    page.mail:SetPoint("TOPLEFT", 12, -57)
    page.mail:SetWidth(130)
    page.trade = Members:CreateButton(side, "LID_ORDER_TRADE")
    page.trade:SetPoint("LEFT", page.mail, "RIGHT", 6, 0)
    page.trade:SetWidth(130)
    page.mail:SetScript("OnClick", function()
        if self.draft then
            self.draft.delivery = "M"
            page.mail:SetAlpha(1)
            page.trade:SetAlpha(0.65)
        end
    end)
    page.trade:SetScript("OnClick", function()
        if self.draft then
            self.draft.delivery = "T"
            page.trade:SetAlpha(1)
            page.mail:SetAlpha(0.65)
        end
    end)
    page.submit = Members:CreateButton(side, "LID_FBSEND", true)
    page.submit:SetPoint("BOTTOMRIGHT", -10, 9)
    page.submit:SetWidth(130)
    page.submit:SetScript("OnClick", function() self:Submit() end)
    page.abort = Members:CreateButton(side, "LID_FBCANCEL")
    page.abort:SetPoint("RIGHT", page.submit, "LEFT", -6, 0)
    page.abort:SetWidth(130)
    page.abort:SetScript("OnClick", function() self.draft = nil self:Refresh() end)
    page.action = Members:CreateButton(side, "LID_ORDER_COMPLETE", true)
    page.action:SetPoint("BOTTOMRIGHT", -10, 9)
    page.action:SetWidth(205)
    page.whisper = Members:CreateButton(side, "LID_WHISPER")
    page.whisper:SetPoint("RIGHT", page.action, "LEFT", -6, 0)
    page.whisper:SetWidth(125)
    content.OnPageShow = function()
        Members:Scan()
        self:Request()
        self:Refresh()
    end
    content.OnPageHide = function()
        for _, row in ipairs(page.inputs) do row.box:ClearFocus() end
    end
end

Window:SetPageBuilder("orders", function(page) Orders:Build(page) end)
Window:OnRebuild(function() Orders.page = nil end)
Theme:OnRefresh(function() Orders:Refresh() end)
local events = CreateFrame("Frame")
events:RegisterEvent("PLAYER_LOGIN")
events:RegisterEvent("PLAYER_GUILD_UPDATE")
events:SetScript("OnEvent", function()
    C_Timer.After(4, function()
        Orders:Request()
        Orders:Refresh()
    end)
end)
C_Timer.NewTicker(180, function()
    Orders:Request()
    for key, packet in pairs(Orders.pending) do
        if GetTime() - packet.at > 120 then Orders.pending[key] = nil end
    end
end)
