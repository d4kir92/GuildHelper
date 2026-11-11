local _, GuildHelper = ...
local Window, Theme, Members, Sync = GuildHelper.Window, GuildHelper.Theme, GuildHelper.Members, GuildHelper.Sync
local Groups, Recipes, Professions = GuildHelper.Groups, GuildHelper.Recipes, GuildHelper.Professions
local Orders = {pending = {}, heard = {}, answers = {}, queued = {}, states = {O = 1, C = 2, D = 3}}
Orders.retention = 7 * 86400
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
    return store and store[id] or nil
end

function Orders:Prune(store)
    local now = time()
    local changed
    for id, order in pairs(store or {}) do
        if order and order.status ~= "O" then
            order.archivedAt = order.archivedAt or now
            if now - (order.closedAt or order.archivedAt) >= self.retention then
                store[id] = false
                changed = true
            end
        end
    end
    return changed
end

function Orders:Delete(order)
    local store = self:GetStore()
    if not store or store[order.id] ~= order or order.status == "O" then return end
    if not (self:IsIncoming(order) or Groups:IsSelfName(order.requester)) then return end
    store[order.id] = false
    self:Refresh()
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
        if order and order.status == "O" and self:IsIncoming(order) then count = count + 1 end
    end
    return count
end

function Orders:ShortName(name)
    local short = strsplit("-", name)
    return short
end

function Orders:CleanText(value, limit)
    local text = (value or ""):gsub("[|%c]", " "):match("^%s*(.-)%s*$")
    return GuildHelper.Feedback:Cut(text, limit)
end

function Orders:Encode(order)
    local materials = {}
    for _, row in ipairs(order.materials) do
        tinsert(materials, format("%d:%d:%s", row.quantity, row.owned, table.concat(row.options, ".")))
    end
    local payload = table.concat({order.requester, order.crafter, order.recipe, order.delivery, order.status, table.concat(materials, ",")}, "~")
    if (order.amount or 1) > 1 then payload = payload .. "~" .. order.amount end
    if order.note and order.note ~= "" then payload = payload .. "~N~" .. order.note end
    return payload
end

function Orders:Decode(id, payload)
    local body, note = payload:match("^(.-)~N~(.*)$")
    if body then
        if note == "" or self:CleanText(note, 240) ~= note then return end
        payload = body
    end
    local base, amount = payload:match("^(.*)~(%d+)$")
    amount = base and tonumber(amount) or 1
    if amount < 1 or amount > 999 then return end
    local requester, crafter, recipe, delivery, status, materials = (base or payload):match("^([^~]+)~([^~]+)~(%d+)~([MT])~([OCD])~([%d:.,%-]*)$")
    recipe = tonumber(recipe)
    if not requester or Groups:Name(requester) ~= requester or not crafter or Groups:Name(crafter) ~= crafter or requester == crafter then return end
    if not recipe or recipe < 1 or recipe > 2147483647 or recipe ~= floor(recipe) then return end
    if (delivery ~= "M" and delivery ~= "T") or not self.states[status] or not materials then return end
    local rows = {}
    for record in materials:gmatch("[^,]+") do
        local quantity, owned, encoded = record:match("^(%d+):(%d+):([%d.%-]+)$")
        quantity, owned = tonumber(quantity), tonumber(owned)
        if not quantity or not owned or quantity < 1 or quantity > 999999 or quantity % amount ~= 0 or owned > quantity or #rows >= 48 then return end
        local options = {}
        for value in encoded:gmatch("[^.]+") do
            local option = tonumber(value)
            if not option or option == 0 or abs(option) > 2147483647 or #options >= 24 then return end
            tinsert(options, option)
        end
        if #options == 0 then return end
        tinsert(rows, {quantity = quantity, owned = owned, options = options})
    end
    return {id = id, requester = requester, crafter = crafter, recipe = recipe, delivery = delivery, status = status, materials = rows, amount = amount, note = note}
end

function Orders:Send(order, relay)
    local guild = Sync:GetGuildKey()
    if not guild then return end
    local payload = self:Encode(order)
    local size = 200
    local total = ceil(#payload / size)
    if total > 16 then return end
    local mode = relay and "R" or "S"
    for part = 1, total do
        local message = format("O~%s~%s~%d~%d~%s", order.id, mode, part, total, payload:sub((part - 1) * size + 1, part * size))
        Sync:Send(message, nil, nil, guild)
    end
    if order.closedAt then
        Sync:Send(format("OT~%s~%s~%s~%d", order.id, mode, order.status, order.closedAt), nil, nil, guild)
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
        if order and (order.requester == participant or order.crafter == participant) then
            tinsert(states, id .. order.status)
            for key in pairs(order.comments or {}) do tinsert(states, id .. "~" .. key) end
        end
    end
    table.sort(states)
    return tostring(GuildHelper.Feedback:Hash(table.concat(states, ",")))
end

function Orders:Request()
    local store = self:GetStore()
    if not store or (self.lastRequest and GetTime() - self.lastRequest < 45) then return end
    if self:Prune(store) then self:Refresh() end
    self.lastRequest = GetTime()
    Sync:Send("O?~" .. self:Digest(store, self:SelfName()), nil, nil, self.guild)
end

function Orders:OnRequest(sender, digest)
    if self.answers[sender] and GetTime() - self.answers[sender] < 45 then return end
    local guild, requested = self.guild, GetTime()
    self.answers[sender] = requested
    C_Timer.After(random(2, 15), function()
        local store = self:GetStore()
        if not store or self.guild ~= guild then return end
        if self:Prune(store) then self:Refresh() end
        if digest == self:Digest(store, sender) then return end
        for id, order in pairs(store) do
            if order and (order.requester == sender or order.crafter == sender) then
                local heard = self.heard[id]
                if not heard or heard.at < requested or heard.status ~= order.status then self:Send(order, true) end
                self:SendComments(order)
            end
        end
    end)
end

function Orders:GetComments(order)
    local list = {}
    for _, comment in pairs(order.comments or {}) do tinsert(list, comment) end
    table.sort(list, function(a, b)
        if a.created ~= b.created then return a.created < b.created end
        if a.id ~= b.id then return a.id < b.id end
        return a.author < b.author
    end)
    return list
end

function Orders:StoreComment(order, id, author, text)
    local created = tonumber(id:match("^%d+"))
    if not created or created < 1 or created > time() + 86400 then return end
    order.comments = order.comments or {}
    local key = author .. "~" .. id
    if order.comments[key] then return end
    order.comments[key] = {id = id, author = author, text = text, created = created}
    local comments = self:GetComments(order)
    for index = 1, #comments - 50 do
        local comment = comments[index]
        order.comments[comment.author .. "~" .. comment.id] = nil
    end
    return true
end

function Orders:SendComment(order, comment)
    Sync:Send(format("OC~%s~%s~%s", order.id, comment.id, comment.text), nil, nil, self.guild)
end

function Orders:SendComments(order)
    for _, comment in ipairs(self:GetComments(order)) do
        if Groups:IsSelfName(comment.author) then self:SendComment(order, comment) end
    end
end

function Orders:AddComment(id, value)
    local order = self:Find(id)
    local author = self:SelfName()
    local text = self:CleanText(value, 160)
    if not order or (author ~= order.requester and author ~= order.crafter) or text == "" then return end
    local comment = {id = format("%d.%09d", time(), random(1, 999999999)), author = author, text = text}
    if not self:StoreComment(order, comment.id, author, text) then return end
    self:SendComment(order, comment)
    return true
end

function Orders:OnMessage(message, sender)
    local store = self:GetStore()
    sender = Groups:Name(sender)
    if not store or not sender or Groups:IsSelfName(sender) then return end
    local digest = message:match("^O%?~(%d+)$")
    if digest and #digest <= 10 then return self:OnRequest(sender, digest) end
    if #message > 255 then return end
    local closedID, closedMode, closedStatus, stamp = message:match("^OT~(%d+%.%d+)~([SR])~([CD])~(%d+)$")
    if closedID then
        local order = store[closedID]
        if not order or order.status ~= closedStatus then return end
        if closedMode == "S" and sender ~= (closedStatus == "D" and order.crafter or order.requester) then return end
        local closedAt = tonumber(stamp)
        if closedAt < tonumber(closedID:match("^%d+")) or closedAt > time() + 86400 then return end
        if order.closedAt and (closedMode == "R" or order.closedAt == closedAt) then return end
        order.closedAt = closedAt
        self:Refresh()
        return
    end
    local orderID, commentID, text = message:match("^OC~(%d+%.%d+)~(%d+%.%d+)~(.+)$")
    if orderID then
        local order = store[orderID]
        if order and #commentID <= 23 and (sender == order.requester or sender == order.crafter)
            and self:CleanText(text, 160) == text and self:StoreComment(order, commentID, sender, text) then
            self:Refresh()
        end
        return
    end
    local id, mode, part, total, chunk = message:match("^O~(%d+%.%d+)~([SR])~(%d+)~(%d+)~(.*)$")
    part, total = tonumber(part), tonumber(total)
    if not id or #id > 23 or not part or not total or part < 1 or part > total or total > 16 or #chunk > 200 or store[id] == false then return end
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
        previous.closedAt, previous.archivedAt = nil, nil
        previous.note = previous.note or order.note
    else
        store[id] = order
    end
    self:Refresh()
end

function Orders:Notify()
    local notifications = GuildHelper.Notifications
    for id, order in pairs(self:GetStore() or {}) do
        if order and order.status == "O" and self:IsIncoming(order) and not order.notified and not self.queued[id] then
            self.queued[id] = true
            notifications:Enqueue({id = id, order = true, guild = self.guild, queued = notifications:GetDisplayTime()})
        end
    end
end

function Orders:SetStatus(order, status)
    if order.status ~= "O" or (status ~= "C" and status ~= "D") then return end
    if status == "D" and not self:IsIncoming(order) then return end
    if status == "C" and not Groups:IsSelfName(order.requester) then return end
    order.status = status
    order.closedAt = time()
    self:Send(order)
    self:Refresh()
end

function Orders:MaterialText(row)
    return table.concat(Recipes:MaterialNames(row), " / ")
end

function Orders:ContactLabel(name, member, withIcon)
    member = member or Members:FindByName(name)
    local label = Members:NameWithTwitch(member, self:ShortName(name))
    return withIcon and (Members:RaceIconMarkup(member, 15) .. label) or label
end

function Orders:ShowContact(page, name)
    local member = Members:FindByName(name)
    page.avatar:SetShown(member ~= nil)
    page.subtitle:SetPoint("TOPLEFT", member and 38 or 14, -36)
    page.subtitle:SetText(self:ContactLabel(name, member))
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
    local materials, limit = {}, 999
    for index, row in ipairs(requirements) do
        if row.quantity < 1 or row.quantity > 999999 then return end
        limit = min(limit, floor(999999 / row.quantity))
        materials[index] = {quantity = row.quantity, perCraft = row.quantity, owned = 0, options = row.options}
    end
    self.draft = {requester = requester, crafter = crafter, crafterName = member.short, recipe = recipe, delivery = "M",
        status = "O", materials = materials, amount = 1, limit = limit}
    self.mode = "outgoing"
    Window:SelectPage("orders")
end

function Orders:Submit()
    local draft, store = self.draft, self:GetStore()
    if not draft or not store then return end
    self:UpdateAmount(self.page, draft)
    draft.note = self:CleanText(self.page.note:GetText(), 240)
    draft.id = format("%d.%09d", time(), random(1, 999999999))
    if not Recipes:CanOrder(Sync:GetData(draft.crafterName), draft.recipe) or store[draft.id] ~= nil or not self:Decode(draft.id, self:Encode(draft)) or not self:Send(draft) then
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

function Orders:UpdateAmount(page, draft)
    if not draft then return end
    local amount = min(draft.limit, max(1, tonumber(page.amount:GetText()) or 1))
    draft.amount = amount
    for index, material in ipairs(draft.materials) do
        local row = page.inputs[index]
        material.quantity = material.perCraft * amount
        row.quantity:SetText(format("%dx", material.quantity))
        if material.owned > material.quantity then row.box:SetText(tostring(material.quantity)) end
    end
end

function Orders:Inventory(material, available)
    local bags, bank, remaining, seen = 0, 0, material.quantity - material.owned, {}
    local getCount = C_Item and C_Item.GetItemCount or GetItemCount
    for _, id in ipairs(material.options) do
        if not seen[id] then
            seen[id] = true
            local inBags, inBank = 0, 0
            if id > 0 and getCount then
                inBags = getCount(id, false) or 0
                inBank = max(0, (getCount(id, true, false, true) or 0) - inBags)
            elseif id < 0 then
                local currency = C_CurrencyInfo and C_CurrencyInfo.GetCurrencyInfo(-id)
                inBags = currency and currency.quantity or 0
            end
            bags, bank = bags + inBags, bank + inBank
            local count = available[id]
            if count == nil then count = inBags + inBank end
            local used = min(count, remaining)
            available[id], remaining = count - used, remaining - used
        end
    end
    return bags, bank, remaining
end

function Orders:RenderDraft(page, draft)
    if page.renderedDraft == draft then return end
    page.renderedDraft = draft
    for _, row in ipairs(page.inputs) do
        row.box:ClearFocus()
        row:Hide()
    end
    page.error:SetText("")
    page.note:ClearFocus()
    if not draft then return end
    page.note:SetText(draft.note or "")
    page.amount:ClearFocus()
    page.amount:SetText(tostring(draft.amount))
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
            row.icon:SetPoint("LEFT", 69, 0)
            row.quantity = Theme:Text(row, 13, "text")
            row.quantity:SetPoint("LEFT", 8, 0)
            row.quantity:SetWidth(56)
            row.quantity:SetJustifyH("RIGHT")
            row.label = Theme:Text(row, 13, "text")
            row.label:SetPoint("LEFT", 96, 0)
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
    self:Prune(store)
    Window:UpdateNavCount("orders", self:Count())
    self:Notify()
    local page = self.page
    if not page or not page:IsVisible() then return end
    local entries, archived, selected = {}, {}, nil
    local incoming = self.mode ~= "outgoing"
    for _, order in pairs(store or {}) do
        if order and ((incoming and self:IsIncoming(order)) or (not incoming and Groups:IsSelfName(order.requester))) then
            local item = Recipes:Output(order.recipe)
            local name, loaded
            local hasItem = item and item > 0
            if hasItem then name, loaded = Recipes:ItemName(item) end
            local list = order.status == "O" and entries or archived
            tinsert(list, {key = order.id, label = loaded and name or Recipes:Name(order.recipe),
                icon = hasItem and Recipes:MaterialIcon(item) or Recipes:Icon(order.recipe),
                order = order, prefix = format("%dx", order.amount or 1)})
            if order.id == self.selected then selected = order end
        end
    end
    table.sort(entries, function(a, b) return a.key > b.key end)
    table.sort(archived, function(a, b)
        local aTime = a.order.closedAt or a.order.archivedAt
        local bTime = b.order.closedAt or b.order.archivedAt
        if aTime ~= bTime then return aTime > bTime end
        return a.key > b.key
    end)
    local first = entries[1] or archived[1]
    selected = selected or (first and first.order)
    self.selected = selected and selected.id
    if page.commentOrder ~= self.selected or self.draft then
        page.commentOrder = self.selected
        page.commentBox:ClearFocus()
        page.commentBox:SetText("")
    end
    page.incoming:SetAlpha(incoming and 1 or 0.65)
    page.outgoing:SetAlpha(incoming and 0.65 or 1)
    local function selectOrder(id)
        self.draft, self.selected = nil, id
        page.detail.scroll:SetVerticalScroll(0)
        self:Refresh()
    end
    local showArchive = #archived > 0
    page.list:SetPoint("BOTTOMLEFT", page, showArchive and "LEFT" or "BOTTOMLEFT", 0, 0)
    page.archive:SetShown(showArchive)
    Professions:ShowRows(page.list, entries, selectOrder, self.selected)
    Professions:ShowRows(page.archive, archived, selectOrder, self.selected)
    page.empty:SetShown(#entries == 0)
    local draft = self.draft
    page.form:SetShown(draft ~= nil)
    page.mail:SetShown(draft ~= nil)
    page.trade:SetShown(draft ~= nil)
    page.submit:SetShown(draft ~= nil)
    page.abort:SetShown(draft ~= nil)
    page.have:SetShown(draft ~= nil)
    page.amount:SetShown(draft ~= nil)
    page.amountLabel:SetShown(draft ~= nil)
    page.note:SetShown(draft ~= nil)
    page.noteLabel:SetShown(draft ~= nil)
    page.commentBox:SetShown(draft == nil and selected ~= nil)
    page.commentSend:SetShown(draft == nil and selected ~= nil)
    page.openRecipe:Hide()
    page.track:Hide()
    page.ready:Hide()
    page.error:SetShown(draft ~= nil)
    page.detail:SetShown(draft == nil and selected ~= nil)
    page.action:SetShown(draft == nil and selected ~= nil)
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
            {label = GuildHelper:Trans(self:DeliveryLabel(selected.delivery)) .. "  ·  " .. GuildHelper:Trans("LID_ORDER_STATUS_" .. selected.status)},
            {label = GuildHelper:Trans("LID_ORDER_AMOUNT") .. "  " .. (selected.amount or 1)}
        }
        local available, ready = {}, true
        for _, material in ipairs(selected.materials) do
            local label = self:MaterialText(material) .. "\n" .. format(GuildHelper:Trans("LID_ORDER_PROVIDED"), material.owned, material.quantity)
            if incoming then
                local bags, bank, missing = self:Inventory(material, available)
                label = label .. "\n" .. format(GuildHelper:Trans("LID_ORDER_INVENTORY"), bags, bank, missing)
                ready = ready and missing == 0
            end
            tinsert(rows, {label = label, icon = Recipes:MaterialIcon(material.options[1])})
        end
        if selected.note and selected.note ~= "" then
            tinsert(rows, {label = GuildHelper:Trans("LID_NOTE") .. "\n" .. selected.note, gap = 8})
        end
        local comments = self:GetComments(selected)
        tinsert(rows, {label = GuildHelper:Trans("LID_FBCOMMENTS"), gap = 8})
        if #comments == 0 then
            tinsert(rows, {label = GuildHelper:Trans("LID_FBNOCOMMENTS")})
        end
        for _, comment in ipairs(comments) do
            local name = self:ContactLabel(comment.author, nil, true)
            tinsert(rows, {label = name .. " · " .. GuildHelper.Feedback:FormatDate(comment.created) .. "\n" .. comment.text})
        end
        local active = incoming and selected.status == "O"
        local commentY = active and 118 or 50
        page.commentSend:SetPoint("BOTTOMRIGHT", -10, commentY)
        page.commentBox:SetPoint("BOTTOMLEFT", 12, commentY)
        page.detail:SetPoint("BOTTOMRIGHT", -10, active and 155 or 87)
        page.ready:SetShown(active)
        Theme:SetTrans(page.ready, ready and "LID_ORDER_READY" or "LID_ORDER_MATERIALS_MISSING")
        local trade = C_TradeSkillUI
        page.openRecipe:SetShown(active and trade ~= nil and trade.OpenRecipe ~= nil)
        page.openRecipe:SetScript("OnClick", function()
            trade.OpenRecipe(selected.recipe)
        end)
        page.track:SetShown(active and trade ~= nil and trade.SetRecipeTracked ~= nil and trade.IsRecipeTracked ~= nil)
        if page.track:IsShown() then
            page.track:SetChecked(trade.IsRecipeTracked(selected.recipe, false))
            page.track:SetScript("OnClick", function(button)
                trade.SetRecipeTracked(selected.recipe, button:GetChecked(), false)
                button:SetChecked(trade.IsRecipeTracked(selected.recipe, false))
            end)
        end
        Professions:ShowRows(page.detail, rows)
        if selected.status == "O" then
            Theme:SetTrans(page.action.text, incoming and "LID_ORDER_COMPLETE" or "LID_FBCANCEL")
            page.action:SetScript("OnClick", function() self:SetStatus(selected, incoming and "D" or "C") end)
        else
            Theme:SetTrans(page.action.text, "LID_FBDELETE")
            page.action:SetScript("OnClick", function() self:Delete(selected) end)
        end
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
            page.archive.scroll:SetVerticalScroll(0)
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
    page.archive = Professions:CreateList(page)
    page.archive:SetPoint("TOPLEFT", page, "LEFT", 0, -10)
    page.archive:SetPoint("BOTTOMLEFT", page, "BOTTOMLEFT", 0, 0)
    page.archive:SetWidth(300)
    page.archive.scroll:SetPoint("TOPLEFT", 8, -31)
    local archiveTitle = Theme:Text(page.archive, 12, "muted")
    archiveTitle:SetPoint("TOPLEFT", 12, -9)
    Theme:SetTrans(archiveTitle, "LID_ORDER_CLOSED")
    page.archive:Hide()
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
    page.detail.fitText = true
    page.detail:SetPoint("TOPLEFT", 10, -59)
    page.detail:SetPoint("BOTTOMRIGHT", -10, 118)
    page.ready = Theme:Text(side, 13, "text")
    page.ready:SetPoint("BOTTOMLEFT", 14, 96)
    page.ready:SetPoint("BOTTOMRIGHT", -14, 96)
    page.ready:SetJustifyH("LEFT")
    page.openRecipe = Members:CreateButton(side, "LID_ORDER_OPEN_RECIPE")
    page.openRecipe:SetPoint("BOTTOMLEFT", 12, 50)
    page.openRecipe:SetWidth(164)
    page.track = CreateFrame("CheckButton", nil, side, "UICheckButtonTemplate")
    page.track:SetPoint("LEFT", page.openRecipe, "RIGHT", 6, 0)
    local trackLabel = Theme:Text(page.track, 12, "text")
    trackLabel:SetPoint("LEFT", page.track, "RIGHT", 2, 0)
    Theme:SetTrans(trackLabel, "LID_ORDER_TRACK_RECIPE")
    page.form = Professions:CreateList(side)
    page.form:SetPoint("TOPLEFT", 10, -145)
    page.amountLabel = Theme:Text(side, 13, "text")
    page.amountLabel:SetPoint("TOPLEFT", 12, -105)
    Theme:SetTrans(page.amountLabel, "LID_ORDER_AMOUNT")
    page.amount = Groups:CreateBox(side, 3, true)
    page.amount:SetPoint("LEFT", page.amountLabel, "RIGHT", 8, 0)
    page.amount:SetWidth(55)
    page.amount:SetScript("OnTextChanged", function(_, userInput)
        if userInput and page.amount:GetText() ~= "" then self:UpdateAmount(page, self.draft) end
    end)
    page.amount:SetScript("OnEditFocusLost", function(box)
        if self.draft then box:SetText(tostring(self.draft.amount)) end
    end)
    page.form:SetPoint("BOTTOMRIGHT", -10, 87)
    page.note = Groups:CreateBox(side, 240)
    page.note:SetPoint("BOTTOMLEFT", 12, 50)
    page.note:SetPoint("BOTTOMRIGHT", -12, 50)
    page.noteLabel = Theme:Text(page.note, 12, "muted")
    page.noteLabel:SetPoint("LEFT", max(5, page.note:GetTextInsets()), 0)
    Theme:SetTrans(page.noteLabel, "LID_NOTE")
    page.note:SetScript("OnTextChanged", function(box)
        local text = box:GetText()
        local limited = GuildHelper.Feedback:Cut(text, 240)
        if text ~= limited then box:SetText(limited) end
        page.noteLabel:SetShown(limited == "")
        if self.draft then self.draft.note = limited end
    end)

    page.commentSend = Members:CreateButton(side, "LID_FBSEND")
    page.commentSend:SetPoint("BOTTOMRIGHT", -10, 50)
    page.commentSend:SetWidth(110)
    page.commentBox = Groups:CreateBox(side, 160)
    page.commentBox:SetPoint("BOTTOMLEFT", 12, 50)
    page.commentBox:SetPoint("BOTTOMRIGHT", page.commentSend, "BOTTOMLEFT", -6, 0)
    local commentHint = Theme:Text(page.commentBox, 12, "muted")
    commentHint:SetPoint("LEFT", max(5, page.commentBox:GetTextInsets()), 0)
    Theme:SetTrans(commentHint, "LID_FBCOMMENTS")
    page.commentBox:SetScript("OnTextChanged", function(box)
        local text = box:GetText()
        local limited = GuildHelper.Feedback:Cut(text, 160)
        if limited ~= text then box:SetText(limited) end
        commentHint:SetShown(limited == "")
        page.commentSend:SetEnabled(self:CleanText(limited, 160) ~= "")
    end)
    local function postComment()
        local id = self.selected
        if not self:AddComment(id, page.commentBox:GetText()) then return end
        page.commentBox:SetText("")
        page.commentBox:ClearFocus()
        self:Refresh()
        C_Timer.After(0, function()
            if self.page == page and self.selected == id and not self.draft then
                page.detail.scroll:SetVerticalScroll(page.detail.scroll:GetVerticalScrollRange())
            end
        end)
    end
    page.commentBox:SetScript("OnEnterPressed", postComment)
    page.commentSend:SetScript("OnClick", postComment)
    page.commentSend:SetEnabled(false)
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
    page.detail.scroll:HookScript("OnSizeChanged", function(_, width)
        if page.detailWidth == width then return end
        page.detailWidth = width
        if page.detailResizePending then return end
        page.detailResizePending = true
        C_Timer.After(0, function()
            page.detailResizePending = nil
            if self.page == page and page.detail:IsVisible() then self:Refresh() end
        end)
    end)
    content.OnPageShow = function()
        Members:Scan()
        self:Request()
        self:Refresh()
    end
    content.OnPageHide = function()
        page.amount:ClearFocus()
        page.note:ClearFocus()
        page.commentBox:ClearFocus()
        for _, row in ipairs(page.inputs) do row.box:ClearFocus() end
    end
end

Window:SetPageBuilder("orders", function(page) Orders:Build(page) end)
Window:OnRebuild(function() Orders.page = nil end)
Theme:OnRefresh(function() Orders:Refresh() end)
Sync:OnUpdate(function()
    if Orders.page and Orders.page:IsVisible() then Orders:Refresh() end
end)
local events = CreateFrame("Frame")
events:RegisterEvent("PLAYER_LOGIN")
events:RegisterEvent("PLAYER_GUILD_UPDATE")
for _, event in ipairs({"BAG_UPDATE_DELAYED", "PLAYERBANKSLOTS_CHANGED", "BANKFRAME_OPENED", "BANKFRAME_CLOSED", "CURRENCY_DISPLAY_UPDATE"}) do
    pcall(events.RegisterEvent, events, event)
end
events:SetScript("OnEvent", function(_, event)
    if event ~= "PLAYER_LOGIN" and event ~= "PLAYER_GUILD_UPDATE" then
        if Orders.page and Orders.page:IsVisible() then Orders:Refresh() end
        return
    end
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
