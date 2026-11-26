local _, GuildHelper = ...
local Window, Theme, Members, Groups = GuildHelper.Window, GuildHelper.Theme, GuildHelper.Members, GuildHelper.Groups
local Professions, Recipes, Orders, Feedback = GuildHelper.Professions, GuildHelper.Recipes, GuildHelper.Orders, GuildHelper.Feedback
local Requests = GuildHelper.Requests
Requests.FILTERS = {"all", "M", "G", "A", "W", "X", "mine"}
Requests.FILTERLABELS = {all = "LID_FBALL", mine = "LID_REQ_MINE"}

function Requests:CategoryLabel(category)
    return "LID_REQ_CAT_" .. category
end

function Requests:FlowPills(pills, x, y, width)
    local left, top = x, y
    for _, pill in ipairs(pills) do
        local size = pill:GetWidth()
        if left > x and left + size > x + width then
            left, top = x, top - 34
        end

        pill:ClearAllPoints()
        pill:SetPoint("TOPLEFT", left, top)
        left = left + size + 6
    end
end

function Requests:CreatePills(parent, keys, labels, onClick)
    local pills = {}
    for _, key in ipairs(keys) do
        local pill = Members:CreatePill(parent, GuildHelper:Trans(labels(key)))
        pill.key = key
        pill:SetScript("OnClick", function() onClick(key) end)
        tinsert(pills, pill)
    end

    return pills
end

function Requests:Matches(row)
    if not row or row.status == "X" then return false end
    local own = self:IsOwn(row)
    if self.filter == "mine" then
        if not own then return false end
    elseif row.status ~= "O" or (self.filter ~= "all" and row.category ~= self.filter) then
        return false
    end

    if self.query == "" then return true end
    local title = self:Display(row)
    local haystack = strlower(table.concat({title or "", row.text, row.name}, " "))

    return haystack:find(self.query, 1, true) ~= nil
end

function Requests:ItemFromText(text)
    local getInstant = C_Item and C_Item.GetItemInfoInstant or GetItemInfoInstant
    if not getInstant or text == "" then return end
    local id = getInstant(text)

    return id
end

function Requests:SetDraftItem(id)
    local draft, page = self.draft, self.page
    if not draft or not page or type(id) ~= "number" then return end
    draft.item = id
    page.itemBox:SetText(Recipes:ItemName(id))
    page.itemBox:ClearFocus()
    local getInstant = C_Item and C_Item.GetItemInfoInstant or GetItemInfoInstant
    local classID = getInstant and select(6, getInstant(id))
    local category = classID and self.ITEMCLASSES[classID]
    if category then draft.category = category end
    self:RenderForm()
end

function Requests:TakeCursorItem()
    local kind, id = GetCursorInfo()
    if kind ~= "item" or not id then return false end
    ClearCursor()
    self:SetDraftItem(id)

    return true
end

function Requests:InsertLink(link)
    local page = self.page
    if not self.draft or not page or not page.itemBox:HasFocus() or type(link) ~= "string" then return end
    local id = tonumber(link:match("|Hitem:(%d+)") or link:match("^item:(%d+)"))
    if id then self:SetDraftItem(id) end
end

function Requests:NewDraft()
    self.draft = {category = "M", item = 0}
    self.selected = nil
    local page = self.page
    page.error:SetText("")
    page.itemBox:SetText("")
    page.quantity:SetText("1")
    page.gold:SetText("")
    page.silver:SetText("")
    page.copper:SetText("")
    page.text:SetText("")
    self:Refresh()
end

function Requests:Submit()
    local draft, page = self.draft, self.page
    if not draft then return end
    local itemText = Groups:CleanText(page.itemBox:GetText(), 120)
    local text = Groups:CleanText(page.text:GetText(), 120)
    local quantity = min(self.MAXQUANTITY, max(1, floor(tonumber(page.quantity:GetText()) or 1)))
    local function coins(box, limit) return min(limit, max(0, floor(tonumber(box:GetText()) or 0))) end
    local gold = min(self.MAXMONEY, coins(page.gold, 999999) * 10000 + coins(page.silver, 99) * 100 + coins(page.copper, 99))
    local item = draft.item
    if item == 0 and itemText ~= "" then
        item = self:ItemFromText(itemText) or 0
        if item == 0 then text = Groups:CleanText(text ~= "" and (itemText .. " - " .. text) or itemText, 120) end
    end

    if draft.category == "G" then
        item, quantity = 0, 1
        if gold < 1 then return page.error:SetText(GuildHelper:Trans("LID_REQ_ERROR_GOLD")) end
    elseif item == 0 and text == "" then
        return page.error:SetText(GuildHelper:Trans("LID_REQ_ERROR_EMPTY"))
    end

    if self:CountOwnOpen() >= self.MAXOPEN then
        return page.error:SetText(format(GuildHelper:Trans("LID_REQ_ERROR_LIMIT"), self.MAXOPEN))
    end

    local id = self:Publish(draft.category, item, quantity, gold, text)
    if not id then return page.error:SetText(GuildHelper:Trans("LID_ORDER_ERROR")) end
    self.draft, self.selected = nil, id
    self:Refresh()
end

function Requests:RenderForm()
    local page, draft = self.page, self.draft
    if not page or not draft then return end
    for _, pill in ipairs(page.categoryPills) do Members:SetPillActive(pill, pill.key == draft.category) end
    self:FlowPills(page.categoryPills, 12, -66, max(200, page.side:GetWidth() - 24))
    local gold = draft.category == "G"
    page.itemBox:SetEnabled(not gold)
    page.itemBox:SetAlpha(gold and 0.5 or 1)
    page.quantity:SetEnabled(not gold)
    page.quantity:SetAlpha(gold and 0.5 or 1)
end

function Requests:HelperNames(bucket)
    local names = {}
    for _, helper in ipairs(self:Helpers(bucket)) do
        tinsert(names, Orders:ContactLabel(helper.name, nil, true))
    end

    return names
end

function Requests:RenderDetail(row, bucket)
    local page = self.page
    local title, icon = self:Display(row)
    page.title:SetText(title)
    page.icon:SetTexture(icon)
    Recipes:SetTooltip(page.header, nil, row.item > 0 and row.item or nil)
    page.subtitle:SetText(Orders:ContactLabel(row.name, nil, true) .. "  ·  " .. Feedback:FormatDate(self:Created(row.id)))
    local rows = {{label = GuildHelper:Trans(self:CategoryLabel(row.category))}}
    if row.item > 0 then
        local count = C_Item and C_Item.GetItemCount and C_Item.GetItemCount(row.item, true) or GetItemCount and GetItemCount(row.item, true) or 0
        tinsert(rows, {label = GuildHelper:Trans("LID_REQ_QUANTITY") .. "  " .. row.quantity, material = row.item})
        if not self:IsOwn(row) then tinsert(rows, {label = format(GuildHelper:Trans("LID_REQ_HAVE"), count)}) end
    end

    if row.gold > 0 then tinsert(rows, {label = GuildHelper:Trans("LID_REQ_GOLD") .. "  " .. Orders:FormatTip(row.gold)}) end
    if row.item > 0 and row.text ~= "" then tinsert(rows, {label = GuildHelper:Trans("LID_REQ_TEXT") .. "\n" .. row.text, gap = 8}) end
    if row.status == "D" then tinsert(rows, {label = GuildHelper:Trans("LID_REQ_DONE"), gap = 8}) end
    tinsert(rows, {label = GuildHelper:Trans("LID_REQ_HELPERS"), gap = 8})
    local names = self:HelperNames(bucket)
    tinsert(rows, {label = #names > 0 and table.concat(names, "\n") or GuildHelper:Trans("LID_REQ_NOHELPERS")})
    local helping = self:IsHelping(bucket)
    if helping and (row.item > 0 or row.gold > 0) then tinsert(rows, {label = GuildHelper:Trans("LID_REQ_MAILNOTE"), gap = 8}) end
    Professions:ShowRows(page.detail, rows)
    local own, open = self:IsOwn(row), row.status == "O"
    page.primary:SetShown(open)
    page.secondary:SetShown(own or open)
    if own then
        Theme:SetTrans(page.primary.text, "LID_REQ_MARKDONE")
        page.primary:SetScript("OnClick", function() self:SetStatus(row.id, "D") end)
        Theme:SetTrans(page.secondary.text, "LID_FBDELETE")
        page.secondary:SetScript("OnClick", function()
            self.selected = nil
            self:SetStatus(row.id, "X")
        end)
    else
        Theme:SetTrans(page.primary.text, helping and "LID_REQ_UNHELP" or "LID_REQ_HELP")
        page.primary:SetScript("OnClick", function() self:Help(row.id, not helping) end)
        Theme:SetTrans(page.secondary.text, "LID_WHISPER")
        page.secondary:SetScript("OnClick", function()
            local target = Members:FindByName(row.name)
            if not target and not GuildHelper:IsForever() then target = {name = row.name} end
            if target then Members:Whisper(target) end
        end)
    end
end

function Requests:Refresh()
    local page = self.page
    if not page or not page:IsVisible() then return end
    local store = self:GetStore() or {}
    local entries, seen = {}, self:GetSeen()
    for id, bucket in pairs(store) do
        local row = bucket.request
        if self:Matches(row) then
            local title, icon = self:Display(row)
            local value = row.item > 0 and format("%dx", row.quantity) or (row.gold > 0 and Orders:FormatTip(row.gold)) or nil
            tinsert(entries, {key = id, label = title, icon = icon, value = value, material = row.item > 0 and row.item or nil, created = self:Created(id),
                done = row.status ~= "O"})
            seen[id] = true
        end
    end

    table.sort(entries, function(a, b)
        if a.done ~= b.done then return b.done end

        return a.key > b.key
    end)
    for _, pill in ipairs(page.filterPills) do Members:SetPillActive(pill, pill.key == self.filter) end
    local selected, bucket
    if self.selected then selected, bucket = self:Get(self.selected) end
    if selected and not self:Matches(selected) then selected = nil end
    if not selected and not self.draft and entries[1] then
        self.selected = entries[1].key
        selected, bucket = self:Get(self.selected)
    end

    Professions:ShowRows(page.list, entries, function(key)
        self.draft, self.selected = nil, key
        page.detail.scroll:SetVerticalScroll(0)
        self:Refresh()
    end, not self.draft and self.selected or nil)
    page.empty:SetShown(#entries == 0)
    local draft = self.draft
    page.form:SetShown(draft ~= nil)
    page.view:SetShown(draft == nil and selected ~= nil)
    page.hint:SetShown(draft == nil and selected == nil)
    if draft then
        self:RenderForm()
    elseif selected then
        self:RenderDetail(selected, bucket)
    end

    self:UpdateCount()
end

function Requests:BuildForm(side)
    local page = self.page
    local form = CreateFrame("Frame", nil, side)
    form:SetAllPoints()
    page.form = form
    local heading = Theme:Text(form, 17, "text")
    heading:SetPoint("TOPLEFT", 14, -12)
    Theme:SetTrans(heading, "LID_REQ_NEW")
    local categoryLabel = Theme:Text(form, 13, "muted")
    categoryLabel:SetPoint("TOPLEFT", 14, -44)
    Theme:SetTrans(categoryLabel, "LID_REQ_CATEGORY")
    page.categoryPills = self:CreatePills(form, self.CATEGORIES, function(key) return self:CategoryLabel(key) end, function(key)
        if self.draft then self.draft.category = key end
        self:RenderForm()
    end)
    local function label(key, y)
        local text = Theme:Text(form, 13, "text")
        text:SetPoint("TOPLEFT", 14, y)
        text:SetWidth(110)
        text:SetJustifyH("LEFT")
        Theme:SetTrans(text, key)

        return text
    end

    label("LID_REQ_ITEM", -146)
    page.itemBox = Groups:CreateBox(form, 120)
    page.itemBox:SetPoint("TOPLEFT", 130, -139)
    page.itemBox:SetPoint("RIGHT", -12, 0)
    page.itemBox:SetScript("OnTextChanged", function(_, user)
        if user and self.draft then self.draft.item = 0 end
    end)
    page.itemBox:SetScript("OnReceiveDrag", function() self:TakeCursorItem() end)
    page.itemBox:HookScript("OnMouseDown", function() self:TakeCursorItem() end)
    local hint = Theme:Text(form, 11, "muted")
    hint:SetPoint("TOPLEFT", 130, -170)
    hint:SetPoint("RIGHT", -12, 0)
    hint:SetJustifyH("LEFT")
    hint:SetWordWrap(true)
    Theme:SetTrans(hint, "LID_REQ_ITEMHINT")
    label("LID_REQ_QUANTITY", -207)
    page.quantity = Groups:CreateBox(form, 4, true)
    page.quantity:SetPoint("TOPLEFT", 130, -200)
    page.quantity:SetWidth(70)
    label("LID_REQ_GOLD", -247)
    local anchor
    for _, coin in ipairs({{"gold", 6, "Interface\\MoneyFrame\\UI-GoldIcon"}, {"silver", 2, "Interface\\MoneyFrame\\UI-SilverIcon"}, {"copper", 2, "Interface\\MoneyFrame\\UI-CopperIcon"}}) do
        local box = Groups:CreateBox(form, coin[2], true)
        if anchor then
            box:SetPoint("LEFT", anchor, "RIGHT", 8, 0)
        else
            box:SetPoint("TOPLEFT", 130, -240)
        end

        box:SetWidth(coin[2] == 6 and 70 or 36)
        local icon = form:CreateTexture(nil, "ARTWORK")
        icon:SetSize(13, 13)
        icon:SetPoint("LEFT", box, "RIGHT", 3, 0)
        icon:SetTexture(coin[3])
        page[coin[1]] = box
        anchor = icon
    end

    label("LID_REQ_TEXT", -287)
    page.text = Groups:CreateBox(form, 120)
    page.text:SetPoint("TOPLEFT", 130, -280)
    page.text:SetPoint("RIGHT", -12, 0)
    page.error = Theme:Text(form, 12, "muted")
    page.error:SetPoint("TOPLEFT", 14, -324)
    page.error:SetPoint("RIGHT", -14, 0)
    page.error:SetJustifyH("LEFT")
    page.error:SetWordWrap(true)
    local submit = Members:CreateButton(form, "LID_REQ_SUBMIT", true)
    submit:SetPoint("BOTTOMLEFT", 12, 12)
    submit:SetWidth(170)
    submit:SetScript("OnClick", function() self:Submit() end)
    local cancel = Members:CreateButton(form, "LID_FBCANCEL")
    cancel:SetPoint("LEFT", submit, "RIGHT", 8, 0)
    cancel:SetWidth(120)
    cancel:SetScript("OnClick", function()
        self.draft = nil
        self:Refresh()
    end)
end

function Requests:BuildView(side)
    local page = self.page
    local view = CreateFrame("Frame", nil, side)
    view:SetAllPoints()
    page.view = view
    page.header = CreateFrame("Frame", nil, view)
    page.header:SetPoint("TOPLEFT")
    page.header:SetPoint("TOPRIGHT")
    page.header:SetHeight(32)
    page.header:EnableMouse(true)
    page.icon = page.header:CreateTexture(nil, "ARTWORK")
    page.icon:SetSize(22, 22)
    page.icon:SetPoint("TOPLEFT", 14, -9)
    page.title = Theme:Text(page.header, 17, "text")
    page.title:SetPoint("TOPLEFT", 44, -10)
    page.title:SetPoint("TOPRIGHT", -14, -10)
    page.title:SetJustifyH("LEFT")
    page.title:SetWordWrap(false)
    page.subtitle = Theme:Text(view, 13, "muted")
    page.subtitle:SetPoint("TOPLEFT", 14, -36)
    page.subtitle:SetPoint("TOPRIGHT", -14, -36)
    page.subtitle:SetJustifyH("LEFT")
    page.detail = Professions:CreateList(view, true)
    page.detail.fitText = true
    page.detail:SetPoint("TOPLEFT", 10, -59)
    page.detail:SetPoint("BOTTOMRIGHT", -10, 56)
    page.primary = Members:CreateButton(view, "LID_REQ_HELP", true)
    page.primary:SetPoint("BOTTOMLEFT", 12, 12)
    page.primary:SetWidth(180)
    page.secondary = Members:CreateButton(view, "LID_WHISPER")
    page.secondary:SetPoint("LEFT", page.primary, "RIGHT", 8, 0)
    page.secondary:SetWidth(130)
end

function Requests:Build(content)
    local title = Window:CreatePageTitle(content, "LID_REQUESTS")
    local page = CreateFrame("Frame", nil, content)
    self.page = page
    page:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -12)
    page:SetPoint("BOTTOMRIGHT", -Window.PADDING, Window.PADDING)
    page.search = Groups:CreateBox(page, 60)
    page.search:SetPoint("TOPLEFT")
    page.search:SetWidth(250)
    local placeholder = Theme:Text(page.search, 12.5, "muted")
    placeholder:SetPoint("LEFT", 10, 0)
    Theme:SetTrans(placeholder, "LID_SEARCH")
    page.search:SetScript("OnTextChanged", function(box)
        local text = box:GetText() or ""
        placeholder:SetShown(text == "")
        self.query = strlower(strtrim(text))
        self:Refresh()
    end)
    local new = Members:CreateButton(page, "LID_REQ_NEW", true)
    new:SetPoint("LEFT", page.search, "RIGHT", 8, 0)
    new:SetWidth(150)
    new:SetScript("OnClick", function() self:NewDraft() end)
    page.filterPills = self:CreatePills(page, self.FILTERS, function(key) return self.FILTERLABELS[key] or self:CategoryLabel(key) end, function(key)
        self.filter = key
        page.list.scroll:SetVerticalScroll(0)
        self:Refresh()
    end)
    self:FlowPills(page.filterPills, 0, -38, 2000)
    page.list = Professions:CreateList(page)
    page.list:SetPoint("TOPLEFT", 0, -76)
    page.list:SetPoint("BOTTOMLEFT")
    page.list:SetWidth(360)
    page.empty = Theme:Text(page.list, 13, "muted")
    page.empty:SetPoint("CENTER")
    Theme:SetTrans(page.empty, "LID_NODATA")
    local side = CreateFrame("Frame", nil, page)
    side:SetPoint("TOPLEFT", page.list, "TOPRIGHT", 12, 0)
    side:SetPoint("BOTTOMRIGHT")
    Theme:Panel(side, "panel", "border", 7)
    page.side = side
    page.hint = Theme:Text(side, 13, "muted")
    page.hint:SetPoint("LEFT", 20, 0)
    page.hint:SetPoint("RIGHT", -20, 0)
    page.hint:SetWordWrap(true)
    Theme:SetTrans(page.hint, "LID_REQ_SELECT")
    self:BuildView(side)
    self:BuildForm(side)
    side:SetScript("OnSizeChanged", function()
        if self.draft then self:RenderForm() end
    end)
    content.OnPageShow = function()
        self:Request()
        self:Refresh()
    end
    content.OnPageHide = function()
        for _, box in ipairs({page.search, page.itemBox, page.quantity, page.gold, page.silver, page.copper, page.text}) do box:ClearFocus() end
    end
end

function Requests:HookLinks()
    local function insert(link) Requests:InsertLink(link) end
    if ChatEdit_InsertLink then
        hooksecurefunc("ChatEdit_InsertLink", insert)
    elseif ChatFrameUtil and ChatFrameUtil.InsertLink then
        hooksecurefunc(ChatFrameUtil, "InsertLink", insert)
    end
end

Requests:HookLinks()
Window:SetPageBuilder("requests", function(content) Requests:Build(content) end)
