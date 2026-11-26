local _, GuildHelper = ...
local Theme, Members, Groups = GuildHelper.Theme, GuildHelper.Members, GuildHelper.Groups
local Orders, Recipes, Professions = GuildHelper.Orders, GuildHelper.Recipes, GuildHelper.Professions
local Mail = {watched = {}}
GuildHelper.Mail = Mail

function Mail:BagCount()
    return NUM_TOTAL_EQUIPPED_BAG_SLOTS or NUM_BAG_SLOTS or 4
end

function Mail:SlotCount(bag)
    local getSlots = C_Container and C_Container.GetContainerNumSlots or GetContainerNumSlots
    return getSlots and getSlots(bag) or 0
end

function Mail:SlotInfo(bag, slot)
    if C_Container and C_Container.GetContainerItemInfo then
        local info = C_Container.GetContainerItemInfo(bag, slot)
        if info then return info.itemID, info.stackCount or 1, info.isLocked, info.isBound end

        return nil
    end

    if GetContainerItemInfo then
        local _, count, locked, _, _, _, _, _, _, id = GetContainerItemInfo(bag, slot)

        return id, count or 1, locked, false
    end
end

function Mail:Recipient(name)
    local member = Members:FindByName(name)
    local full = member and member.name or name
    local short, realm = strsplit("-", full)
    local own = (GetRealmName() or ""):gsub("%s", "")
    if not realm or strlower(realm) == strlower(own) then full = short end
    if full == strlower(full) then full = (full:gsub("^%l", strupper)) end

    return full
end

function Mail:OrderItems(order, incoming)
    local items = {}
    if incoming and not Recipes:GetServiceSkill(order.recipe) then
        local output = Recipes:Output(order.recipe)
        if output and output > 0 then
            tinsert(items, {options = {output}, quantity = order.amount or 1})
        end

        return items
    end

    for _, material in ipairs(order.materials) do
        if material.owned > 0 then
            tinsert(items, {options = material.options, quantity = material.owned})
        end
    end

    return items
end

function Mail:OrderEntries(list)
    for _, order in pairs(Orders:GetStore() or {}) do
        if order and order.status == "O" and order.delivery == "M" then
            local incoming = Orders:IsIncoming(order)
            local outgoing = not incoming and Groups:IsSelfName(order.requester)
            local items = (incoming or outgoing) and self:OrderItems(order, incoming) or {}
            local money = outgoing and order.tip or 0
            if #items > 0 or money > 0 then
                local name, icon = Recipes:OutputDisplay(order.recipe)
                local contact = incoming and order.requester or order.crafter
                local recipient = self:Recipient(contact)
                local first = items[1] and items[1].options[1]
                tinsert(list, {
                    key = "O" .. order.id,
                    incoming = incoming,
                    tip = money > 0,
                    label = money > 0 and (name .. "  ·  " .. GuildHelper:Trans("LID_ORDER_TIP") .. " " .. Orders:FormatTip(money)) or name,
                    icon = icon,
                    material = first and first > 0 and first or nil,
                    prefix = format("%dx", order.amount or 1),
                    value = strsplit("-", recipient),
                    recipient = recipient,
                    subject = name,
                    money = money,
                    items = items
                })
            end
        end
    end
end

function Mail:Collect()
    local list = {}
    self:OrderEntries(list)
    if GuildHelper.Requests then GuildHelper.Requests:MailEntries(list) end
    table.sort(list, function(a, b)
        if a.incoming ~= b.incoming then return a.incoming end

        return a.key > b.key
    end)

    return list
end

function Mail:FreeSlot(used)
    for index = 1, ATTACHMENTS_MAX_SEND or 12 do
        if not used[index] and not HasSendMailItem(index) then return index end
    end
end

function Mail:Matches(item, id)
    if type(id) ~= "number" then return false end
    for _, option in ipairs(item.options) do
        if option == id then return true end
    end

    return false
end

function Mail:KeepAttached(items, used)
    for index = 1, ATTACHMENTS_MAX_SEND or 12 do
        if HasSendMailItem(index) then
            local _, id, _, count = GetSendMailItem(index)
            local kept
            for _, item in ipairs(items) do
                if not kept and item.remaining > 0 and self:Matches(item, id) then
                    item.remaining = item.remaining - (count or 1)
                    kept = true
                end
            end

            if not kept then ClickSendMailItemButton(index, true) end
            used[index] = true
        end
    end
end

function Mail:AttachSlot(item, bag, slot, used)
    local _, count, locked, bound = self:SlotInfo(bag, slot)
    if locked or bound then return true end
    local index = self:FreeSlot(used)
    if not index then return false, "full" end
    local container = C_Container or {}
    if count > item.remaining then
        local split = container.SplitContainerItem or SplitContainerItem
        split(bag, slot, item.remaining)
    else
        local pickup = container.PickupContainerItem or PickupContainerItem
        pickup(bag, slot)
    end

    if not CursorHasItem() then return true end
    ClickSendMailItemButton(index)
    if CursorHasItem() then
        ClearCursor()

        return false, "failed"
    end

    used[index] = true
    item.remaining = item.remaining - min(count, item.remaining)

    return true
end

function Mail:AttachItem(item, used)
    for _, id in ipairs(item.options) do
        if id > 0 then
            for bag = 0, self:BagCount() do
                for slot = 1, self:SlotCount(bag) do
                    if item.remaining <= 0 then return true end
                    if self:SlotInfo(bag, slot) == id then
                        local ok, reason = self:AttachSlot(item, bag, slot, used)
                        if not ok then return false, reason end
                    end
                end
            end
        end
    end

    return true
end

function Mail:Attach(entry)
    local items, used, missing = {}, {}, {}
    for _, item in ipairs(entry.items) do
        tinsert(items, {options = item.options, quantity = item.quantity, remaining = item.quantity})
    end

    ClearCursor()
    self:KeepAttached(items, used)
    local problem
    for _, item in ipairs(items) do
        if not problem then
            local ok, reason = self:AttachItem(item, used)
            if not ok then problem = reason end
        end

        if item.remaining > 0 then
            tinsert(missing, format("%dx %s", item.remaining, Recipes:ItemName(item.options[1])))
        end
    end

    return missing, problem
end

function Mail:OpenSendTab()
    if SendMailFrame and SendMailFrame:IsShown() then return true end
    if not MailFrameTab_OnClick then return false end
    MailFrameTab_OnClick(nil, 2)

    return SendMailFrame ~= nil and SendMailFrame:IsShown()
end

function Mail:Daylight()
    local window = _G.DaylightUIMail
    if type(window) == "table" and window.IsVisible and window:IsVisible() and type(window.pages) == "table" then return window end
end

function Mail:Host()
    local daylight = self:Daylight()
    if daylight then return daylight end
    if MailFrame and MailFrame:IsVisible() then return MailFrame end
end

function Mail:FillDaylight(window, entry)
    if window.current ~= "send" then
        for _, tab in ipairs(window.tabs or {}) do
            if tab.id == "send" then tab:Click() end
        end
    end

    local page = window.pages.send
    if not page or not page.to or not page.subject or not page.gold then return false end
    page.to:SetText(entry.recipient)
    page.to:ClearFocus()
    local missing, problem = self:Attach(entry)
    page.subject:SetText(entry.subject)
    local money = entry.money or 0
    if money > 0 and page.cod and page.cod.on then page.cod:Click() end
    page.gold:SetText(money >= 10000 and tostring(floor(money / 10000)) or "")
    page.silver:SetText(floor(money / 100) % 100 > 0 and tostring(floor(money / 100) % 100) or "")
    page.copper:SetText(money % 100 > 0 and tostring(money % 100) or "")

    return true, missing, problem
end

function Mail:FillGame(entry)
    if not self:OpenSendTab() or not SendMailNameEditBox then return false end
    SendMailNameEditBox:SetText(entry.recipient)
    SendMailNameEditBox:ClearFocus()
    local missing, problem = self:Attach(entry)
    SendMailSubjectEditBox:SetText(entry.subject)
    if SendMailMoney and MoneyInputFrame_SetCopper then
        if SendMailRadioButton_OnClick then SendMailRadioButton_OnClick(1) end
        MoneyInputFrame_SetCopper(SendMailMoney, entry.money or 0)
    end

    if SendMailFrame_Update then SendMailFrame_Update() end

    return true, missing, problem
end

function Mail:Fill(entry)
    if InCombatLockdown() then return end
    local daylight = self:Daylight()
    local ok, missing, problem
    if daylight then
        ok, missing, problem = self:FillDaylight(daylight, entry)
    else
        ok, missing, problem = self:FillGame(entry)
    end

    if not ok then return end
    local lines = {}
    if problem == "full" then tinsert(lines, GuildHelper:Trans("LID_MAIL_FULL")) end
    if problem == "failed" then tinsert(lines, GuildHelper:Trans("LID_MAIL_FAILED")) end
    if #missing > 0 then tinsert(lines, format(GuildHelper:Trans("LID_MAIL_MISSING"), table.concat(missing, ", "))) end
    if #lines == 0 then tinsert(lines, GuildHelper:Trans("LID_MAIL_READY")) end
    if (entry.money or 0) > 0 then
        tinsert(lines, format(GuildHelper:Trans(entry.tip and "LID_MAIL_TIP" or "LID_MAIL_GOLD"), Orders:FormatTip(entry.money)))
    end
    self.selected = entry.key
    self.frame.status:SetText(table.concat(lines, "\n"))
    self:Refresh()
end

function Mail:Build()
    local kind = Theme:GetBuildKind()
    if self.frame and self.kind == kind then return self.frame end
    if self.frame then self.frame:Hide() end
    self.kind = kind
    local frame = CreateFrame("Frame", nil, UIParent)
    frame:SetWidth(300)
    frame:Hide()
    frame:EnableMouse(true)
    Theme:Panel(frame, "window", "border", 10)
    frame.badge = CreateFrame("Frame", nil, frame)
    frame.badge:SetSize(20, 20)
    frame.badge:SetPoint("TOPLEFT", 14, -11)
    frame.badge:EnableMouse(true)
    frame.badge.icon = frame.badge:CreateTexture(nil, "ARTWORK")
    frame.badge.icon:SetAllPoints()
    frame.badge.icon:SetTexture(135026)
    frame.badge:SetScript("OnEnter", function(badge)
        GameTooltip:SetOwner(badge, "ANCHOR_RIGHT")
        GameTooltip:SetText("GuildHelper")
        GameTooltip:AddLine(GuildHelper:Trans("LID_MAIL_ICONTIP"), 1, 1, 1, true)
        GameTooltip:Show()
    end)
    frame.badge:SetScript("OnLeave", function() GameTooltip:Hide() end)
    frame.title = Theme:Text(frame, 15, "text")
    frame.title:SetPoint("LEFT", frame.badge, "RIGHT", 8, 0)
    frame.title:SetPoint("RIGHT", frame, "RIGHT", -14, 0)
    frame.title:SetJustifyH("LEFT")
    Theme:SetTrans(frame.title, "LID_MAIL_TITLE")
    frame.hint = Theme:Text(frame, 12, "muted")
    frame.hint:SetPoint("TOPLEFT", 14, -36)
    frame.hint:SetPoint("TOPRIGHT", -14, -36)
    frame.hint:SetJustifyH("LEFT")
    frame.hint:SetWordWrap(true)
    Theme:SetTrans(frame.hint, "LID_MAIL_HINT")
    frame.list = Professions:CreateList(frame)
    frame.list:SetPoint("TOPLEFT", 10, -70)
    frame.list:SetPoint("BOTTOMRIGHT", -10, 64)
    frame.empty = Theme:Text(frame.list, 13, "muted")
    frame.empty:SetPoint("LEFT", 12, 0)
    frame.empty:SetPoint("RIGHT", -12, 0)
    frame.empty:SetWordWrap(true)
    Theme:SetTrans(frame.empty, "LID_MAIL_EMPTY")
    frame.status = Theme:Text(frame, 12, "text")
    frame.status:SetPoint("BOTTOMLEFT", 14, 12)
    frame.status:SetPoint("BOTTOMRIGHT", -14, 12)
    frame.status:SetHeight(46)
    frame.status:SetJustifyH("LEFT")
    frame.status:SetJustifyV("BOTTOM")
    frame.status:SetWordWrap(true)
    self.frame = frame

    return frame
end

function Mail:Refresh()
    local frame = self.frame
    if not frame or not frame:IsShown() then return end
    local entries = self:Collect()
    local byKey, splits = {}, nil
    for index, entry in ipairs(entries) do
        byKey[entry.key] = entry
        if not splits and index > 1 and not entry.incoming and entries[index - 1].incoming then splits = {index} end
    end

    if self.selected and not byKey[self.selected] then self.selected = nil end
    Professions:ShowRows(frame.list, entries, function(key)
        if byKey[key] then self:Fill(byKey[key]) end
    end, self.selected, splits)
    frame.empty:SetShown(#entries == 0)
end

function Mail:Place()
    local frame = self.frame
    if not frame then return end
    local host = self.open and self:Host()
    if not host then
        frame:Hide()

        return
    end

    frame:ClearAllPoints()
    frame:SetPoint("TOPLEFT", host, "TOPRIGHT", 4, 0)
    frame:SetPoint("BOTTOMLEFT", host, "BOTTOMRIGHT", 4, 0)
    frame:SetFrameStrata(host:GetFrameStrata())
    frame:SetFrameLevel(host:GetFrameLevel() + 10)
    frame:Show()
    self:Refresh()
end

function Mail:Watch(host)
    if type(host) ~= "table" or not host.HookScript or self.watched[host] then return end
    self.watched[host] = true
    local function place()
        C_Timer.After(0, function() Mail:Place() end)
    end

    host:HookScript("OnShow", place)
    host:HookScript("OnHide", place)
end

function Mail:Open()
    local frame = self:Build()
    frame.status:SetText("")
    self.selected = nil
    self.open = true
    self:Watch(MailFrame)
    self:Watch(_G.DaylightUIMail)
    self:Place()
    C_Timer.After(0.2, function()
        Mail:Watch(_G.DaylightUIMail)
        Mail:Place()
    end)
end

function Mail:OnEvent(event)
    if event == "MAIL_SHOW" then
        self:Open()
    elseif event == "MAIL_SEND_SUCCESS" and self.frame then
        self.selected = nil
        self.frame.status:SetText(GuildHelper:Trans("LID_MAIL_SENT"))
        self:Refresh()
    elseif event == "MAIL_CLOSED" and self.frame then
        self.open = false
        self.frame:Hide()
    end
end

Mail.events = CreateFrame("Frame")
Mail.events:RegisterEvent("MAIL_SHOW")
Mail.events:RegisterEvent("MAIL_CLOSED")
Mail.events:RegisterEvent("MAIL_SEND_SUCCESS")
Mail.events:SetScript("OnEvent", function(_, event) Mail:OnEvent(event) end)
hooksecurefunc(Orders, "Refresh", function() Mail:Refresh() end)
