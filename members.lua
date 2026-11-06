local _, GuildHelper = ...
local Theme = GuildHelper.Theme
local Window = GuildHelper.Window
local Members = {}
GuildHelper.Members = Members
Members.ROWHEIGHT = 35
Members.HEADERHEIGHT = 36
Members.TABLEWIDTH = 584
Members.TABLETOP = 108
Members.BOTTOM = 21
Members.COLUMNS = {
    {
        key = "name",
        label = "LID_NAME",
        x = 15
    },
    {
        key = "level",
        label = "LID_LVL",
        x = 155
    },
    {
        key = "rank",
        label = "LID_RANK",
        x = 199
    },
    {
        key = "ilvl",
        label = "LID_ILVL",
        x = 291
    },
    {
        key = "lastOnline",
        label = "LID_LASTSEEN",
        x = 340
    },
    {
        key = "note",
        label = "LID_NOTE",
        x = 430
    },
}

Members.list = {}
Members.view = {}
Members.rows = {}
Members.offset = 0
Members.sortKey = "name"
Members.sortAsc = true
Members.filter = {
    text = "",
    class = nil,
    rank = nil,
    onlineOnly = false,
    hideAlts = false,
}

function Members:RequestRoster()
    if not IsInGuild() then return end
    if C_GuildInfo and C_GuildInfo.GuildRoster then
        C_GuildInfo.GuildRoster()
    elseif GuildRoster then
        GuildRoster()
    end
end

function Members:ShortName(name)
    if name == nil then return "" end

    return (strsplit("-", name))
end

function Members:GetClassColor(member)
    local color = RAID_CLASS_COLORS and member and member.classFile and RAID_CLASS_COLORS[member.classFile]
    if color then return color.r, color.g, color.b end

    return Theme:GetColor("text")
end

function Members:GetLastOnlineHours(index, online)
    if online then return -1 end
    if GetGuildRosterLastOnline == nil then return nil end
    local years, months, days, hours = GetGuildRosterLastOnline(index)
    if years == nil then return nil end

    return (years or 0) * 8760 + (months or 0) * 730 + (days or 0) * 24 + (hours or 0)
end

function Members:FormatLastOnline(member)
    local hours = member.lastOnline
    if hours == nil then return "–" end
    if hours >= 8760 then return GuildHelper:Trans("LID_YEARSAGO", nil, floor(hours / 8760)) end
    if hours >= 730 then return GuildHelper:Trans("LID_MONTHSAGO", nil, floor(hours / 730)) end
    if hours >= 24 then return GuildHelper:Trans("LID_DAYSAGO", nil, floor(hours / 24)) end
    if hours >= 1 then return GuildHelper:Trans("LID_HOURSAGO", nil, hours) end

    return GuildHelper:Trans("LID_LESSTHANHOUR")
end

function Members:FindMainInNote(member, note, byName)
    if note == nil or note == "" then return nil end
    for word in string.gmatch(note, "[^%s%p%d]+") do
        local target = byName[strlower(word)]
        if target and target ~= member then return target end
    end

    return nil
end

function Members:LinkMains()
    local byName = {}
    for _, member in ipairs(self.list) do
        byName[member.key] = member
        member.main = nil
        member.alts = nil
    end

    for _, member in ipairs(self.list) do
        member.main = self:FindMainInNote(member, member.note, byName) or self:FindMainInNote(member, member.officerNote, byName)
    end

    for _, member in ipairs(self.list) do
        local main = member.main
        if main and main.main == member then
            member.main = nil
            main.main = nil
        end
    end

    for _, member in ipairs(self.list) do
        local main = member.main
        if main then
            main.alts = main.alts or {}
            tinsert(main.alts, member)
        end
    end

    for _, member in ipairs(self.list) do
        if member.alts then table.sort(member.alts, function(a, b) return a.key < b.key end) end
    end
end

function Members:Scan()
    wipe(self.list)
    self.numOnline = 0
    if not IsInGuild() then return end
    local total = GetNumGuildMembers() or 0
    for index = 1, total do
        local name, rankName, rankIndex, level, className, zone, note, officerNote, online, _, classFile = GetGuildRosterInfo(index)
        if name then
            local short = self:ShortName(name)
            local member = {
                name = name,
                short = short,
                key = strlower(short),
                rank = rankName or "",
                rankIndex = rankIndex or 0,
                level = level or 0,
                className = className or "",
                classFile = classFile,
                zone = zone or "",
                note = note or "",
                officerNote = officerNote or "",
                online = online and true or false,
            }

            member.lastOnline = self:GetLastOnlineHours(index, member.online)
            if member.online then self.numOnline = self.numOnline + 1 end
            tinsert(self.list, member)
        end
    end

    self:LinkMains()
    for _, member in ipairs(self.list) do
        local mainName = member.main and member.main.short or ""
        member.search = strlower(table.concat({member.short, member.note, member.officerNote, member.zone, member.rank, member.className, mainName}, "\n"))
    end
end

function Members:GetItemLevel(member)
    local data = GuildHelper.Sync:GetData(member.short)

    return data and data.ilvl
end

function Members:Matches(member)
    local filter = self.filter
    if filter.onlineOnly and not member.online then return false end
    if filter.hideAlts and member.main then return false end
    if filter.class and member.classFile ~= filter.class then return false end
    if filter.rank and member.rankIndex ~= filter.rank then return false end
    if filter.text ~= "" and not strfind(member.search, filter.text, 1, true) then return false end

    return true
end

function Members:GetSortValue(member, key)
    if key == "level" then return member.level end
    if key == "rank" then return member.rankIndex end
    if key == "ilvl" then return self:GetItemLevel(member) or -1 end
    if key == "lastOnline" then return member.lastOnline or 999999 end
    if key == "note" then return member.note == "" and "\255" or strlower(member.note) end

    return member.key
end

function Members:ApplyFilter()
    wipe(self.view)
    for _, member in ipairs(self.list) do
        if self:Matches(member) then tinsert(self.view, member) end
    end

    local key = self.sortKey
    local asc = self.sortAsc
    table.sort(self.view, function(a, b)
        local va = self:GetSortValue(a, key)
        local vb = self:GetSortValue(b, key)
        if va == vb then return a.key < b.key end
        if asc then return va < vb end

        return va > vb
    end)

    self:Update()
end

function Members:Refresh()
    self:Scan()
    self:ApplyFilter()
end

function Members:GetSelected()
    if self.selectedKey == nil then return nil end
    for _, member in ipairs(self.list) do
        if member.key == self.selectedKey then return member end
    end

    return nil
end

function Members:Select(member)
    self.selectedKey = member and member.key or nil
    self:Update()
end

function Members:CreatePill(parent, label)
    local pill = CreateFrame("Button", nil, parent)
    pill:SetHeight(28)
    pill.fill, pill.border = Theme:Panel(pill, "control", "border", 14)
    pill.text = Theme:Text(pill, 12.5, "text")
    pill.text:SetPoint("CENTER", pill, "CENTER", 0, 0)
    pill:SetScript("OnEnter", function(sel) Members:StylePill(sel) end)
    pill:SetScript("OnLeave", function(sel) Members:StylePill(sel) end)
    self:SetPillText(pill, label)

    return pill
end

function Members:SetPillText(pill, label)
    pill.text:SetText(label or "")
    pill:SetWidth(floor(pill.text:GetStringWidth() + 32))
end

function Members:StylePill(pill)
    local active = pill.active
    Theme:SetKey(pill.fill, active and "pillActive" or (pill:IsMouseOver() and "hover" or "control"))
    Theme:SetKey(pill.border, active and "accent" or "border")
    Theme:SetKey(pill.text, active and "accent" or "text")
end

function Members:SetPillActive(pill, active)
    pill.active = active
    self:StylePill(pill)
end

function Members:GetMenu()
    if self.menu then return self.menu end
    local menu = CreateFrame("Frame", nil, Window.frame)
    menu:SetFrameStrata("DIALOG")
    menu:SetClampedToScreen(true)
    menu:EnableMouse(true)
    menu:Hide()
    Theme:Panel(menu, "card", "border", 7)
    menu.buttons = {}
    self.menu = menu

    return menu
end

function Members:OpenMenu(anchor, options, current, onSelect)
    local menu = self:GetMenu()
    if menu:IsShown() and menu.anchor == anchor then
        menu:Hide()

        return
    end

    menu.anchor = anchor
    local width = 140
    for i, option in ipairs(options) do
        local button = menu.buttons[i]
        if button == nil then
            button = CreateFrame("Button", nil, menu)
            button:SetHeight(24)
            button.bg = Theme:Round(button, "hover", 5)
            button.text = Theme:Text(button, 12.5)
            button.text:SetPoint("LEFT", button, "LEFT", 10, 0)
            button:SetScript("OnEnter", function(sel) sel.bg:SetShown(true) end)
            button:SetScript("OnLeave", function(sel) sel.bg:SetShown(sel.selected == true) end)
            menu.buttons[i] = button
        end

        button:ClearAllPoints()
        button:SetPoint("TOPLEFT", menu, "TOPLEFT", 5, -5 - (i - 1) * 24)
        button:SetPoint("TOPRIGHT", menu, "TOPRIGHT", -5, -5 - (i - 1) * 24)
        button.text:SetText(option.label)
        if option.color then
            button.text:SetTextColor(option.color.r, option.color.g, option.color.b)
        else
            button.text:SetTextColor(Theme:GetColor("text"))
        end

        button.selected = option.value == current
        Theme:SetKey(button.bg, button.selected and "pillActive" or "hover")
        button.bg:SetShown(button.selected)
        button:SetScript("OnClick", function()
            menu:Hide()
            onSelect(option.value)
        end)

        button:Show()
        width = max(width, button.text:GetStringWidth() + 30)
    end

    for i = #options + 1, #menu.buttons do
        menu.buttons[i]:Hide()
    end

    menu:SetSize(width, #options * 24 + 10)
    menu:ClearAllPoints()
    menu:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", 0, -4)
    menu:Show()
end

function Members:GetClassOptions()
    local options = {
        {
            label = GuildHelper:Trans("LID_ALLCLASSES")
        }
    }

    local seen = {}
    local classes = {}
    for _, member in ipairs(self.list) do
        if member.classFile and not seen[member.classFile] then
            seen[member.classFile] = true
            tinsert(classes, member)
        end
    end

    table.sort(classes, function(a, b) return a.className < b.className end)
    for _, member in ipairs(classes) do
        tinsert(options, {
            label = member.className,
            value = member.classFile,
            color = RAID_CLASS_COLORS and RAID_CLASS_COLORS[member.classFile]
        })
    end

    return options
end

function Members:GetRankOptions()
    local options = {
        {
            label = GuildHelper:Trans("LID_ALLRANKS")
        }
    }

    local ranks = {}
    local indices = {}
    for _, member in ipairs(self.list) do
        if ranks[member.rankIndex] == nil then
            ranks[member.rankIndex] = member.rank
            tinsert(indices, member.rankIndex)
        end
    end

    table.sort(indices)
    for _, index in ipairs(indices) do
        tinsert(options, {
            label = ranks[index],
            value = index
        })
    end

    return options
end

function Members:GetOptionLabel(options, value)
    for _, option in ipairs(options) do
        if option.value == value then return option.label end
    end

    return options[1].label
end

function Members:CreateHeaderArea(content)
    local title = Window:CreatePageTitle(content, "LID_MEMBERS")
    self.count = Theme:Text(content, 13, "muted")
    self.count:SetPoint("BOTTOMLEFT", title, "BOTTOMRIGHT", 10, 1)
    local box = CreateFrame("Frame", nil, content)
    box:SetSize(200, 31)
    box:SetPoint("TOPRIGHT", content, "TOPRIGHT", -Window.MARGIN - 42, -24)
    box.fill, box.border = Theme:Panel(box, "control", "border", 7)
    local icon = Theme:Icon(box, "search", 12, "muted")
    icon:SetPoint("LEFT", box, "LEFT", 12, 0)
    local search = CreateFrame("EditBox", nil, box)
    search:SetPoint("TOPLEFT", box, "TOPLEFT", 32, 0)
    search:SetPoint("BOTTOMRIGHT", box, "BOTTOMRIGHT", -8, 0)
    search:SetAutoFocus(false)
    search:SetMaxLetters(60)
    Theme:Track(search, "text", "text", 12.5)
    search.placeholder = Theme:Text(box, 12.5, "muted")
    search.placeholder:SetPoint("LEFT", box, "LEFT", 32, 0)
    search.placeholder:SetPoint("RIGHT", box, "RIGHT", -8, 0)
    search.placeholder:SetText(GuildHelper:Trans("LID_SEARCH"))
    search:SetScript("OnEscapePressed", search.ClearFocus)
    search:SetScript("OnEnterPressed", search.ClearFocus)
    search:SetScript("OnEditFocusGained", function() Theme:SetKey(box.border, "accent") end)
    search:SetScript("OnEditFocusLost", function() Theme:SetKey(box.border, "border") end)
    search:SetScript("OnTextChanged", function(sel)
        local text = sel:GetText() or ""
        sel.placeholder:SetShown(text == "")
        Members.filter.text = strlower(strtrim(text))
        Members.offset = 0
        Members:ApplyFilter()
    end)

    self.searchBox = box
end

function Members:CreateFilters(content)
    local filters = CreateFrame("Frame", nil, content)
    filters:SetPoint("TOPLEFT", content, "TOPLEFT", Window.PADDING, -68)
    filters:SetSize(600, 28)
    self.filters = filters
    self.classPill = self:CreatePill(filters)
    self.classPill:SetPoint("LEFT", filters, "LEFT", 0, 0)
    self.classPill:SetScript("OnClick", function(sel)
        Members:OpenMenu(sel, Members:GetClassOptions(), Members.filter.class, function(value)
            Members.filter.class = value
            Members.offset = 0
            Members:ApplyFilter()
        end)
    end)

    self.rankPill = self:CreatePill(filters)
    self.rankPill:SetPoint("LEFT", self.classPill, "RIGHT", 8, 0)
    self.rankPill:SetScript("OnClick", function(sel)
        Members:OpenMenu(sel, Members:GetRankOptions(), Members.filter.rank, function(value)
            Members.filter.rank = value
            Members.offset = 0
            Members:ApplyFilter()
        end)
    end)

    self.onlinePill = self:CreatePill(filters, GuildHelper:Trans("LID_ONLINEONLY"))
    self.onlinePill:SetPoint("LEFT", self.rankPill, "RIGHT", 8, 0)
    self.onlinePill:SetScript("OnClick", function()
        Members.filter.onlineOnly = not Members.filter.onlineOnly
        Members.offset = 0
        Members:ApplyFilter()
    end)

    self.altsPill = self:CreatePill(filters, GuildHelper:Trans("LID_HIDEALTS"))
    self.altsPill:SetPoint("LEFT", self.onlinePill, "RIGHT", 8, 0)
    self.altsPill:SetScript("OnClick", function()
        Members.filter.hideAlts = not Members.filter.hideAlts
        Members.offset = 0
        Members:ApplyFilter()
    end)
end

function Members:UpdateFilters()
    self:SetPillText(self.classPill, self:GetOptionLabel(self:GetClassOptions(), self.filter.class))
    self:SetPillText(self.rankPill, self:GetOptionLabel(self:GetRankOptions(), self.filter.rank))
    self:SetPillActive(self.classPill, self.filter.class ~= nil)
    self:SetPillActive(self.rankPill, self.filter.rank ~= nil)
    self:SetPillActive(self.onlinePill, self.filter.onlineOnly)
    self:SetPillActive(self.altsPill, self.filter.hideAlts)
    for _, header in ipairs(self.headers) do
        local active = header.column.key == self.sortKey
        Theme:SetKey(header.text, active and "accent" or "muted")
        header.text:SetText(strupper(GuildHelper:Trans(header.column.label)))
    end
end

function Members:UpdateRowBackground(row)
    local member = row.member
    if member and member.key == self.selectedKey then
        Theme:SetKey(row.bg, "rowSelected")
        row.bg:Show()
    elseif member and row:IsMouseOver() then
        Theme:SetKey(row.bg, "rowHover")
        row.bg:Show()
    else
        row.bg:Hide()
    end
end

function Members:ShowTooltip(row)
    local member = row.member
    if member == nil or (member.note == "" and member.officerNote == "") then return end
    GameTooltip:SetOwner(row, "ANCHOR_RIGHT")
    GameTooltip:AddLine(member.short, self:GetClassColor(member))
    if member.note ~= "" then GameTooltip:AddDoubleLine(GuildHelper:Trans("LID_NOTE"), member.note, 0.7, 0.7, 0.7, 1, 1, 1) end
    if member.officerNote ~= "" then GameTooltip:AddDoubleLine(GuildHelper:Trans("LID_OFFICERNOTE"), member.officerNote, 0.7, 0.7, 0.7, 1, 1, 1) end
    GameTooltip:Show()
end

function Members:CreateRow(parent, index)
    local row = CreateFrame("Button", nil, parent)
    row:SetHeight(self.ROWHEIGHT)
    row:SetPoint("TOPLEFT", parent, "TOPLEFT", 1, -self.HEADERHEIGHT - 1 - (index - 1) * self.ROWHEIGHT)
    row:SetPoint("TOPRIGHT", parent, "TOPRIGHT", -1, -self.HEADERHEIGHT - 1 - (index - 1) * self.ROWHEIGHT)
    row.bg = Theme:Background(row, "rowHover")
    row.bg:Hide()
    row.line = Theme:Line(row, "divider")
    row.line:SetHeight(1)
    row.line:SetPoint("BOTTOMLEFT", row, "BOTTOMLEFT", 0, 0)
    row.line:SetPoint("BOTTOMRIGHT", row, "BOTTOMRIGHT", 0, 0)
    row.dot = row:CreateTexture(nil, "ARTWORK")
    row.dot:SetTexture(Theme.MEDIA .. "circle")
    row.dot:SetSize(7, 7)
    row.dot:SetPoint("LEFT", row, "LEFT", self.COLUMNS[1].x, 0)
    row.name = Theme:Text(row, 13.5)
    row.name:SetPoint("LEFT", row, "LEFT", self.COLUMNS[1].x + 15, 0)
    row.tag = Theme:Text(row, 10.5, "muted")
    row.tag:SetPoint("LEFT", row.name, "RIGHT", 6, 0)
    row.level = Theme:Text(row, 13, "text")
    row.level:SetPoint("LEFT", row, "LEFT", self.COLUMNS[2].x, 0)
    row.rank = Theme:Text(row, 13, "text")
    row.rank:SetPoint("LEFT", row, "LEFT", self.COLUMNS[3].x, 0)
    row.rank:SetWidth(self.COLUMNS[4].x - self.COLUMNS[3].x - 8)
    row.ilvl = Theme:Text(row, 13, "text")
    row.ilvl:SetPoint("LEFT", row, "LEFT", self.COLUMNS[4].x, 0)
    row.seen = Theme:Text(row, 12, "muted")
    row.seen:SetPoint("LEFT", row, "LEFT", self.COLUMNS[5].x, 0)
    row.note = Theme:Text(row, 12, "navText")
    row.note:SetPoint("LEFT", row, "LEFT", self.COLUMNS[6].x, 0)
    row.note:SetWidth(self.TABLEWIDTH - self.COLUMNS[6].x - 14)
    row.badge = CreateFrame("Frame", nil, row)
    row.badge:SetHeight(18)
    row.badge:SetPoint("LEFT", row, "LEFT", self.COLUMNS[5].x - 2, 0)
    Theme:Round(row.badge, "onlineBg", 9)
    row.badge.text = Theme:Text(row.badge, 11, "online")
    row.badge.text:SetPoint("CENTER", row.badge, "CENTER", 0, 0)
    row:RegisterForClicks("AnyUp")
    row:SetScript("OnClick", function(sel) if sel.member then Members:Select(sel.member) end end)
    row:SetScript("OnEnter", function(sel)
        Members:UpdateRowBackground(sel)
        Members:ShowTooltip(sel)
    end)

    row:SetScript("OnLeave", function(sel)
        GameTooltip:Hide()
        Members:UpdateRowBackground(sel)
    end)

    return row
end

function Members:FillRow(row, member)
    row.member = member
    local r, g, b = self:GetClassColor(member)
    row.dot:SetVertexColor(r, g, b)
    row.name:SetText(member.short)
    row.name:SetTextColor(r, g, b)
    if member.alts then
        row.tag:SetText(GuildHelper:Trans("LID_MAINTAG", nil, #member.alts))
    elseif member.main then
        row.tag:SetText(GuildHelper:Trans("LID_ALTTAG"))
    else
        row.tag:SetText("")
    end

    row.level:SetText(member.level)
    row.rank:SetText(member.rank)
    row.ilvl:SetText(self:GetItemLevel(member) or "–")
    row.note:SetText(member.note)
    row.badge:SetShown(member.online)
    row.seen:SetShown(not member.online)
    if member.online then
        row.badge.text:SetText(GuildHelper:Trans("LID_ONLINE"))
        row.badge:SetWidth(floor(row.badge.text:GetStringWidth() + 16))
    else
        row.seen:SetText(self:FormatLastOnline(member))
    end

    self:UpdateRowBackground(row)
end

function Members:CreateTable(content)
    local panel = CreateFrame("Frame", nil, content)
    panel:SetPoint("TOPLEFT", content, "TOPLEFT", Window.PADDING, -self.TABLETOP)
    panel:SetPoint("BOTTOMLEFT", content, "BOTTOMLEFT", Window.PADDING, self.BOTTOM)
    panel:SetWidth(self.TABLEWIDTH)
    Theme:Panel(panel, "panel", "border", 9)
    panel:EnableMouseWheel(true)
    panel:SetScript("OnMouseWheel", function(_, delta)
        Members.offset = Members.offset - delta * 3
        Members:Update()
    end)

    self.panel = panel
    self.headers = {}
    for i, column in ipairs(self.COLUMNS) do
        local nextColumn = self.COLUMNS[i + 1]
        local header = CreateFrame("Button", nil, panel)
        header:SetPoint("TOPLEFT", panel, "TOPLEFT", column.x, 0)
        header:SetSize((nextColumn and nextColumn.x or self.TABLEWIDTH - 10) - column.x, self.HEADERHEIGHT)
        header.column = column
        header.text = Theme:Text(header, 11, "muted")
        header.text:SetPoint("LEFT", header, "LEFT", 0, 0)
        header:SetScript("OnClick", function()
            if Members.sortKey == column.key then
                Members.sortAsc = not Members.sortAsc
            else
                Members.sortKey = column.key
                Members.sortAsc = true
            end

            Members:ApplyFilter()
        end)

        tinsert(self.headers, header)
    end

    local line = Theme:Line(panel, "border")
    line:SetHeight(1)
    line:SetPoint("TOPLEFT", panel, "TOPLEFT", 1, -self.HEADERHEIGHT)
    line:SetPoint("TOPRIGHT", panel, "TOPRIGHT", -1, -self.HEADERHEIGHT)
    local height = Window.HEIGHT - self.TABLETOP - self.BOTTOM
    local visible = floor((height - self.HEADERHEIGHT - 2) / self.ROWHEIGHT)
    for i = 1, visible do
        self.rows[i] = self:CreateRow(panel, i)
    end

    local thumb = CreateFrame("Button", nil, panel)
    thumb:SetWidth(4)
    thumb:SetFrameLevel(panel:GetFrameLevel() + 5)
    Theme:Round(thumb, "thumb", 2)
    thumb:SetScript("OnMouseDown", function(sel)
        sel.startY = select(2, GetCursorPosition()) / sel:GetEffectiveScale()
        sel.startOffset = Members.offset
        sel:SetScript("OnUpdate", function()
            local y = select(2, GetCursorPosition()) / sel:GetEffectiveScale()
            local range = Members:GetTrackHeight() - sel:GetHeight()
            local maxOffset = max(0, #Members.view - #Members.rows)
            if range <= 0 or maxOffset == 0 then return end
            local offset = floor(sel.startOffset + (sel.startY - y) / range * maxOffset + 0.5)
            if offset ~= Members.offset then
                Members.offset = offset
                Members:Update()
            end
        end)
    end)

    thumb:SetScript("OnMouseUp", function(sel) sel:SetScript("OnUpdate", nil) end)
    thumb:SetScript("OnHide", function(sel) sel:SetScript("OnUpdate", nil) end)
    self.thumb = thumb
end

function Members:GetTrackHeight()
    return self.panel:GetHeight() - self.HEADERHEIGHT - 12
end

function Members:UpdateScrollBar()
    local thumb = self.thumb
    local total = #self.view
    local visible = #self.rows
    local maxOffset = max(0, total - visible)
    if maxOffset == 0 then
        thumb:Hide()

        return
    end

    local track = self:GetTrackHeight()
    local height = max(24, track * visible / total)
    thumb:SetHeight(height)
    thumb:ClearAllPoints()
    thumb:SetPoint("TOPRIGHT", self.panel, "TOPRIGHT", -4, -self.HEADERHEIGHT - 6 - (track - height) * self.offset / maxOffset)
    thumb:Show()
end

function Members:CreateStatCard(parent, label)
    local card = CreateFrame("Frame", nil, parent)
    card:SetSize(90, 52)
    Theme:Round(card, "card", 7)
    card.label = Theme:Text(card, 10.5, "muted")
    card.label:SetPoint("TOPLEFT", card, "TOPLEFT", 10, -9)
    card.label:SetText(GuildHelper:Trans(label))
    card.value = Theme:Text(card, 16, "text")
    card.value:SetPoint("TOPLEFT", card, "TOPLEFT", 10, -25)
    card.value:SetPoint("RIGHT", card, "RIGHT", -8, 0)

    return card
end

function Members:CreateButton(parent, label, primary)
    local button = CreateFrame("Button", nil, parent)
    button:SetSize(90, 32)
    if primary then
        button.fill = Theme:Round(button, "accent", 7)
    else
        button.fill = Theme:Panel(button, "control", "border", 7)
    end

    button.text = Theme:Text(button, 13, primary and "accentText" or "text")
    button.text:SetPoint("CENTER", button, "CENTER", 0, 0)
    button.text:SetText(GuildHelper:Trans(label))
    if not primary then
        button:SetScript("OnEnter", function(sel) Theme:SetKey(sel.fill, "hover") end)
        button:SetScript("OnLeave", function(sel) Theme:SetKey(sel.fill, "control") end)
    end

    return button
end

function Members:GetProfessionRow(index)
    local detail = self.detail
    local row = detail.professions[index]
    if row then return row end
    row = CreateFrame("Frame", nil, detail)
    row:SetSize(188, 26)
    row.name = Theme:Text(row, 12.5, "text")
    row.name:SetPoint("TOPLEFT", row, "TOPLEFT", 0, 0)
    row.value = Theme:Text(row, 12, "muted")
    row.value:SetPoint("TOPRIGHT", row, "TOPRIGHT", 0, 0)
    row.value:SetJustifyH("RIGHT")
    row.bar = CreateFrame("Frame", nil, row)
    row.bar:SetSize(188, 4)
    row.bar:SetPoint("TOPLEFT", row, "TOPLEFT", 0, -19)
    Theme:Round(row.bar, "barBg", 2)
    row.fill = CreateFrame("Frame", nil, row.bar)
    row.fill:SetHeight(4)
    row.fill:SetPoint("TOPLEFT", row.bar, "TOPLEFT", 0, 0)
    Theme:Round(row.fill, "accent", 2)
    detail.professions[index] = row

    return row
end

function Members:CreateDetail(content)
    local detail = CreateFrame("Frame", nil, content)
    detail:SetPoint("TOPLEFT", content, "TOPLEFT", Window.PADDING + self.TABLEWIDTH + 12, -self.TABLETOP)
    detail:SetPoint("BOTTOMRIGHT", content, "BOTTOMRIGHT", -Window.MARGIN, self.BOTTOM)
    Theme:Panel(detail, "panel", "border", 9)
    detail.professions = {}
    self.detail = detail
    local avatar = CreateFrame("Frame", nil, detail)
    avatar:SetSize(40, 40)
    avatar:SetPoint("TOPLEFT", detail, "TOPLEFT", 16, -16)
    avatar.border = Theme:CreateShape(avatar, 8, "BACKGROUND", 0)
    avatar.fill = Theme:CreateShape(avatar, 7, "BACKGROUND", 1, 1)
    avatar.letter = Theme:Text(avatar, 17)
    avatar.letter:SetPoint("CENTER", avatar, "CENTER", 0, 0)
    detail.avatar = avatar
    detail.name = Theme:Text(detail, 18)
    detail.name:SetPoint("TOPLEFT", avatar, "TOPRIGHT", 12, -2)
    detail.name:SetPoint("RIGHT", detail, "RIGHT", -12, 0)
    detail.sub = Theme:Text(detail, 12, "muted")
    detail.sub:SetPoint("TOPLEFT", detail.name, "BOTTOMLEFT", 0, -4)
    detail.sub:SetPoint("RIGHT", detail, "RIGHT", -12, 0)
    detail.ilvl = self:CreateStatCard(detail, "LID_ILVL")
    detail.ilvl:SetPoint("TOPLEFT", detail, "TOPLEFT", 16, -68)
    detail.rank = self:CreateStatCard(detail, "LID_RANK")
    detail.rank:SetPoint("TOPLEFT", detail.ilvl, "TOPRIGHT", 8, 0)
    detail.noteHeader = Theme:Text(detail, 11, "muted")
    detail.noteHeader:SetText(strupper(GuildHelper:Trans("LID_NOTE")))
    detail.noteText = Theme:Text(detail, 12.5, "text")
    detail.noteText:SetWidth(188)
    detail.noteText:SetWordWrap(true)
    detail.officerHeader = Theme:Text(detail, 11, "muted")
    detail.officerHeader:SetText(strupper(GuildHelper:Trans("LID_OFFICERNOTE")))
    detail.officerText = Theme:Text(detail, 12.5, "text")
    detail.officerText:SetWidth(188)
    detail.officerText:SetWordWrap(true)
    detail.profHeader = Theme:Text(detail, 11, "muted")
    detail.profHeader:SetText(strupper(GuildHelper:Trans("LID_PROFESSIONS")))
    detail.profEmpty = Theme:Text(detail, 12, "muted")
    detail.altHeader = Theme:Text(detail, 11, "muted")
    detail.altText = Theme:Text(detail, 12.5, "text")
    detail.altText:SetWidth(188)
    detail.altText:SetWordWrap(true)
    detail.whisper = self:CreateButton(detail, "LID_WHISPER", true)
    detail.whisper:SetPoint("BOTTOMLEFT", detail, "BOTTOMLEFT", 16, 16)
    detail.whisper:SetScript("OnClick", function() Members:Whisper(Members:GetSelected()) end)
    detail.invite = self:CreateButton(detail, "LID_INVITE", false)
    detail.invite:SetPoint("BOTTOMRIGHT", detail, "BOTTOMRIGHT", -16, 16)
    detail.invite:SetScript("OnClick", function() Members:Invite(Members:GetSelected()) end)
    detail.empty = Theme:Text(detail, 13, "muted")
    detail.empty:SetPoint("CENTER", detail, "CENTER", 0, 0)
    detail.content = {avatar, detail.name, detail.sub, detail.ilvl, detail.rank, detail.noteHeader, detail.noteText, detail.officerHeader, detail.officerText, detail.profHeader, detail.profEmpty, detail.altHeader, detail.altText, detail.whisper, detail.invite}
end

function Members:PlaceSection(header, text, y, value, empty)
    header:ClearAllPoints()
    header:SetPoint("TOPLEFT", self.detail, "TOPLEFT", 16, y)
    text:ClearAllPoints()
    text:SetPoint("TOPLEFT", header, "BOTTOMLEFT", 0, -6)
    text:SetText(value ~= "" and value or empty)
    Theme:SetKey(text, value ~= "" and "text" or "muted")

    return y - 20 - max(14, text:GetStringHeight()) - 12
end

function Members:IsSelf(member)
    return member and member.short == UnitName("player")
end

function Members:Whisper(member)
    if member == nil or self:IsSelf(member) then return end
    if ChatFrame_SendTell then
        ChatFrame_SendTell(member.name)
    elseif ChatFrameUtil and ChatFrameUtil.SendTell then
        ChatFrameUtil.SendTell(member.name)
    end
end

function Members:Invite(member)
    if member == nil or self:IsSelf(member) or not member.online then return end
    if C_PartyInfo and C_PartyInfo.InviteUnit then
        C_PartyInfo.InviteUnit(member.name)
    elseif InviteUnit then
        InviteUnit(member.name)
    end
end

function Members:ColoredName(member)
    local r, g, b = self:GetClassColor(member)

    return format("|cff%02x%02x%02x%s|r", r * 255, g * 255, b * 255, member.short)
end

function Members:UpdateDetail()
    local detail = self.detail
    local member = self:GetSelected()
    for _, region in ipairs(detail.content) do
        region:SetShown(member ~= nil)
    end

    detail.empty:SetShown(member == nil)
    for _, row in ipairs(detail.professions) do
        row:Hide()
    end

    if member == nil then return end
    local r, g, b = self:GetClassColor(member)
    detail.avatar.border:SetColor(r, g, b, 1)
    detail.avatar.fill:SetColor(r * 0.28, g * 0.28, b * 0.28, 1)
    detail.avatar.letter:SetText(member.short:match("^[%z\1-\127\194-\244][\128-\191]*") or "?")
    detail.avatar.letter:SetTextColor(r, g, b)
    detail.name:SetText(member.short)
    detail.name:SetTextColor(r, g, b)
    detail.sub:SetText(GuildHelper:Trans("LID_CLASSLEVEL", nil, member.className, member.level))
    detail.ilvl.value:SetText(self:GetItemLevel(member) or "–")
    detail.rank.value:SetText(member.rank)
    local data = GuildHelper.Sync:GetData(member.short)
    local professions = data and data.professions or {}
    local y = self:PlaceSection(detail.noteHeader, detail.noteText, -136, member.note, "–")
    local hasOfficer = member.officerNote ~= ""
    detail.officerHeader:SetShown(hasOfficer)
    detail.officerText:SetShown(hasOfficer)
    if hasOfficer then y = self:PlaceSection(detail.officerHeader, detail.officerText, y, member.officerNote, "–") end
    detail.profHeader:ClearAllPoints()
    detail.profHeader:SetPoint("TOPLEFT", detail, "TOPLEFT", 16, y)
    y = y - 20
    local step = #professions > 3 and 26 or 31
    local limit = -(detail:GetHeight() - 64)
    for i, prof in ipairs(professions) do
        if y - step < limit then break end
        local row = self:GetProfessionRow(i)
        row:ClearAllPoints()
        row:SetPoint("TOPLEFT", detail, "TOPLEFT", 16, y)
        row.name:SetText(prof[1])
        row.value:SetText(format("%d/%d", prof[2], prof[3]))
        local progress = prof[3] > 0 and min(1, prof[2] / prof[3]) or 0
        row.fill:SetWidth(max(1, 188 * progress))
        row.fill:SetShown(progress > 0)
        row:Show()
        y = y - step
    end

    detail.profEmpty:SetShown(#professions == 0)
    if #professions == 0 then
        detail.profEmpty:ClearAllPoints()
        detail.profEmpty:SetPoint("TOPLEFT", detail, "TOPLEFT", 16, y)
        detail.profEmpty:SetText(GuildHelper:Trans("LID_NODATA"))
        y = y - 22
    end

    local names = {}
    if member.alts then
        detail.altHeader:SetText(strupper(GuildHelper:Trans("LID_ALTS")))
        for _, alt in ipairs(member.alts) do
            tinsert(names, self:ColoredName(alt))
        end
    elseif member.main then
        detail.altHeader:SetText(strupper(GuildHelper:Trans("LID_MAIN")))
        tinsert(names, self:ColoredName(member.main))
    end

    detail.altHeader:SetShown(#names > 0)
    detail.altText:SetShown(#names > 0)
    detail.altHeader:ClearAllPoints()
    detail.altHeader:SetPoint("TOPLEFT", detail, "TOPLEFT", 16, y - 10)
    detail.altText:ClearAllPoints()
    detail.altText:SetPoint("TOPLEFT", detail.altHeader, "BOTTOMLEFT", 0, -8)
    detail.altText:SetText(table.concat(names, ", "))
    local isSelf = self:IsSelf(member)
    detail.whisper:SetAlpha(isSelf and 0.4 or 1)
    detail.whisper:SetEnabled(not isSelf)
    detail.invite:SetAlpha((isSelf or not member.online) and 0.4 or 1)
    detail.invite:SetEnabled(not isSelf and member.online)
end

function Members:Update()
    if self.content == nil or not self.content:IsVisible() then return end
    local inGuild = IsInGuild()
    self.panel:SetShown(inGuild)
    self.detail:SetShown(inGuild)
    self.filters:SetShown(inGuild)
    self.searchBox:SetShown(inGuild)
    self.noGuild:SetShown(not inGuild)
    if not inGuild then
        self.count:SetText("")

        return
    end

    if self:GetSelected() == nil then self.selectedKey = self.view[1] and self.view[1].key or nil end
    local maxOffset = max(0, #self.view - #self.rows)
    self.offset = min(max(self.offset, 0), maxOffset)
    for i, row in ipairs(self.rows) do
        local member = self.view[self.offset + i]
        if member then
            self:FillRow(row, member)
            row:Show()
        else
            row.member = nil
            row:Hide()
        end
    end

    self.count:SetText(GuildHelper:Trans("LID_ONLINECOUNT", nil, Theme:GetHex("online") .. (self.numOnline or 0) .. "|r", #self.list))
    self:UpdateFilters()
    self:UpdateScrollBar()
    self:UpdateDetail()
end

function Members:Build(content)
    self.content = content
    self:CreateHeaderArea(content)
    self:CreateFilters(content)
    self:CreateTable(content)
    self:CreateDetail(content)
    self.noGuild = Theme:Text(content, 14, "muted")
    self.noGuild:SetPoint("CENTER", content, "CENTER", 0, 0)
    self.noGuild:SetText(GuildHelper:Trans("LID_NOGUILD"))
    content.OnPageShow = function()
        Members:RequestRoster()
        Members:Refresh()
    end

    content.OnPageHide = function()
        if Members.menu then Members.menu:Hide() end
    end
end

function Members:Init()
    Theme:OnRefresh(function() Members:Update() end)
    GuildHelper.Sync:OnUpdate(function() Members:Update() end)
    local events = CreateFrame("Frame")
    events:RegisterEvent("GUILD_ROSTER_UPDATE")
    events:RegisterEvent("PLAYER_GUILD_UPDATE")
    events:SetScript("OnEvent", function(_, event)
        if Members.content == nil or not Members.content:IsVisible() then return end
        if event == "PLAYER_GUILD_UPDATE" then Members:RequestRoster() end
        Members:Refresh()
    end)
end

Window:SetPageBuilder("members", function(content) Members:Build(content) end)
