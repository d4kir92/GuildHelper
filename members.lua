local _, GuildHelper = ...
local Theme = GuildHelper.Theme
local Window = GuildHelper.Window
local Members = {}
GuildHelper.Members = Members
Members.ROWHEIGHT = 35
Members.HEADERHEIGHT = 36
Members.DETAILWIDTH = 220
Members.COLUMNMENUROW = 28
Members.TABLETOP = 108
Members.BOTTOM = 21
Members.MENUROWS = 16
Members.NAMEX = 15
Members.MINNAME = 140
Members.NOTEWIDTH = 170
Members.MINNOTE = 70
Members.COLUMNS = {
    {
        key = "level",
        label = "LID_LVL",
        width = 40
    },
    {
        key = "name",
        label = "LID_NAME"
    },
    {
        key = "ilvl",
        label = "LID_ILVL",
        width = 48
    },
    {
        key = "zone",
        label = "LID_ZONE",
        width = 122
    },
    {
        key = "isMain",
        label = "LID_MAINQ",
        width = 50
    },
    {
        key = "mainSpec",
        label = "LID_MAINSPECSHORT",
        width = 72
    },
    {
        key = "secondSpec",
        label = "LID_SECONDSPECSHORT",
        width = 72
    },
    {
        key = "rank",
        label = "LID_RANK",
        width = 92
    },
    {
        key = "note",
        label = "LID_NOTE",
        note = true
    },
    {
        key = "officerNote",
        label = "LID_OFFICERNOTE",
        note = true
    },
    {
        key = "twitch",
        label = "LID_TWITCH",
        width = 120
    },
    {
        key = "lastOnline",
        label = "LID_LASTSEEN",
        width = 90
    },
}

Members.COLUMNX = {}
Members.COLUMNW = {}
Members.COLUMNSHOWN = {}
Members.nameWidth = Members.MINNAME


Members.list = {}
Members.view = {}
Members.rows = {}
Members.offset = 0
Members.numVisible = 0
Members.sortKey = "name"
Members.sortAsc = true
Members.filter = {
    text = "",
    class = nil,
    rank = nil,
    onlineOnly = true,
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

function Members:GetData(member)
    if member == nil then return nil end
    if self:IsSelf(member) then return GuildHelper.Sync:GetData(UnitName("player")) or GuildHelper.Sync:GetData(member.short) end

    return GuildHelper.Sync:GetData(member.short)
end

function Members:GetDeclaredMain(member, byName)
    if self:IsSelf(member) and GuildHelper.Specs:IsMain() then return member end
    local data = self:GetData(member)
    local main = data and data.main
    if main == nil or main == "" then return nil end
    local key = GuildHelper.Sync:GetKey(main)
    if key == member.key then return member end

    return byName[key]
end

function Members:LinkMains()
    local byName = {}
    for _, member in ipairs(self.list) do
        byName[member.key] = member
        member.main = nil
        member.alts = nil
        member.declaredMain = false
    end

    for _, member in ipairs(self.list) do
        local declared = self:GetDeclaredMain(member, byName)
        if declared then
            declared.declaredMain = true
            member.main = declared ~= member and declared or nil
        else
            member.main = self:FindMainInNote(member, member.note, byName) or self:FindMainInNote(member, member.officerNote, byName)
        end
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
                key = GuildHelper.Sync:GetKey(short),
                rank = rankName or "",
                rankIndex = rankIndex or 0,
                isGuildLeader = rankIndex == 0,
                level = level or 0,
                className = className or "",
                classFile = classFile,
                zone = zone or "",
                note = note or "",
                officerNote = officerNote or "",
                online = online and true or false,
                guid = select(17, GetGuildRosterInfo(index)),
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
    local data = self:GetData(member)

    return data and data.ilvl
end

function Members:Matches(member)
    local filter = self.filter
    if filter.onlineOnly and not member.online then return false end
    if filter.hideAlts and not member.declaredMain and member.alts == nil then return false end
    if filter.class and member.classFile ~= filter.class then return false end
    if filter.rank and member.rankIndex ~= filter.rank then return false end
    if filter.text ~= "" and not strfind(member.search, filter.text, 1, true) then return false end

    return true
end

function Members:GetTwitchName(member)
    if self:IsSelf(member) then return GuildHelper.Specs:GetTwitch() end
    local data = self:GetData(member)

    return data and type(data.twitch) == "string" and data.twitch or ""
end

function Members:GetSortValue(member, key)
    if key == "twitch" then
        local name = self:GetTwitchName(member)
        return name ~= "" and strlower(name) or "\255"
    end
    if key == "level" then return member.level end
    if key == "rank" then return member.rankIndex end
    if key == "zone" then return member.zone == "" and "\255" or strlower(member.zone) end
    if key == "isMain" then return member.declaredMain and 0 or (member.main and 1 or 2) end
    if key == "mainSpec" then return self:GetSpecSortValue(member, 1) end
    if key == "secondSpec" then return self:GetSpecSortValue(member, 2) end
    if key == "ilvl" then return self:GetItemLevel(member) or -1 end
    if key == "lastOnline" then return member.lastOnline or 999999 end
    if key == "note" then return member.note == "" and "\255" or strlower(member.note) end
    if key == "officerNote" then return member.officerNote == "" and "\255" or strlower(member.officerNote) end

    return member.key
end

function Members:LoadFilter()
    local saved = GuildHelper:GetConfig("MEMBERFILTER", {})
    self.filter.class = saved.class
    self.filter.rank = saved.rank
    self.filter.onlineOnly = saved.onlineOnly ~= false
    self.filter.hideAlts = saved.hideAlts == true
end

function Members:SaveFilter()
    GuildHelper:SetConfig("MEMBERFILTER", {
        class = self.filter.class,
        rank = self.filter.rank,
        onlineOnly = self.filter.onlineOnly,
        hideAlts = self.filter.hideAlts,
    })
end

function Members:ApplyFilter()
    self:SaveFilter()
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

function Members:CreateNativeButton(parent, height)
    local button = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
    button:SetHeight(height)
    button:SetText(" ")
    Theme:FlatNative(button)
    button.text = button:GetFontString()
    button.native = true

    return button
end

function Members:CreatePill(parent, label)
    if Theme:IsNative() then
        local native = self:CreateNativeButton(parent, 24)
        self:SetPillText(native, label)

        return native
    end

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
    if pill.native then
        if active then
            pill:LockHighlight()
        else
            pill:UnlockHighlight()
        end

        return
    end

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
    menu.ghNoInside = true
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
    menu.options = options
    menu.current = current
    menu.onSelect = onSelect
    menu.visible = min(#options, self.MENUROWS)
    menu.offset = 0
    for i, option in ipairs(options) do
        if not option.header and option.value == current then menu.offset = max(0, min(i - floor(menu.visible / 2), #options - menu.visible)) end
    end

    if not menu.measure then
        menu.measure = Theme:Text(menu, 12.5)
        menu.measure:Hide()
        menu.thumb = menu:CreateTexture(nil, "OVERLAY")
        menu.thumb:SetWidth(3)
        menu:EnableMouseWheel(true)
        menu:SetScript("OnMouseWheel", function(sel, delta)
            local offset = max(0, min(sel.offset - delta * 3, #sel.options - sel.visible))
            if offset ~= sel.offset then
                sel.offset = offset
                Members:RenderMenu()
            end
        end)
    end

    local width = 140
    for _, option in ipairs(options) do
        menu.measure:SetText(option.label)
        width = max(width, menu.measure:GetStringWidth() + 36)
    end

    menu:SetSize(min(width, 420), menu.visible * 24 + 10)
    menu:ClearAllPoints()
    menu:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", 0, -4)
    self:RenderMenu()
    menu:Show()
end

function Members:RenderMenu()
    local menu = self.menu
    for i = 1, menu.visible do
        local option = menu.options[menu.offset + i]
        local button = menu.buttons[i]
        if button == nil then
            button = CreateFrame("Button", nil, menu)
            button:SetHeight(24)
            button:SetPoint("TOPLEFT", menu, "TOPLEFT", 5, -5 - (i - 1) * 24)
            button:SetPoint("TOPRIGHT", menu, "TOPRIGHT", -9, -5 - (i - 1) * 24)
            button.bg = Theme:Round(button, "hover", 5)
            button.text = Theme:Text(button, 12.5)
            button.text:SetPoint("LEFT", button, "LEFT", 10, 0)
            button.text:SetPoint("RIGHT", button, "RIGHT", -4, 0)
            button.text:SetJustifyH("LEFT")
            button.text:SetWordWrap(false)
            button:SetScript("OnEnter", function(sel) sel.bg:SetShown(not sel.header) end)
            button:SetScript("OnLeave", function(sel) sel.bg:SetShown(sel.selected == true) end)
            button:SetScript("OnClick", function(sel)
                if sel.header then return end
                menu:Hide()
                menu.onSelect(sel.value)
            end)

            menu.buttons[i] = button
        end

        button.header = option.header == true
        button.value = option.value
        button.text:SetText(option.label)
        if option.color then
            button.text:SetTextColor(option.color.r, option.color.g, option.color.b)
        else
            button.text:SetTextColor(Theme:GetColor(button.header and "muted" or "text"))
        end

        button.selected = not button.header and option.value == menu.current
        Theme:SetKey(button.bg, button.selected and "pillActive" or "hover")
        button.bg:SetShown(button.selected)
        button:Show()
    end

    for i = menu.visible + 1, #menu.buttons do
        menu.buttons[i]:Hide()
    end

    local total = #menu.options
    menu.thumb:SetShown(total > menu.visible)
    if total > menu.visible then
        local track = menu.visible * 24
        local size = max(16, track * menu.visible / total)
        menu.thumb:SetColorTexture(Theme:GetColor("muted"))
        menu.thumb:SetHeight(size)
        menu.thumb:ClearAllPoints()
        menu.thumb:SetPoint("TOPRIGHT", menu, "TOPRIGHT", -4, -5 - (track - size) * menu.offset / (total - menu.visible))
    end
end

function Members:GetColumnConfig()
    local config = GuildHelper:GetConfig("MEMBERCOLUMNS", {})
    if type(config.order) ~= "table" then config.order = {} end
    if type(config.hidden) ~= "table" then config.hidden = {} end

    return config
end

function Members:GetOrderedColumns()
    local byKey, list, seen = {}, {}, {}
    for _, column in ipairs(self.COLUMNS) do
        byKey[column.key] = column
    end

    for _, key in ipairs(self:GetColumnConfig().order) do
        if byKey[key] and not seen[key] then
            seen[key] = true
            tinsert(list, byKey[key])
        end
    end

    if #list > 0 and not seen.name then
        seen.name = true
        tinsert(list, 1, byKey.name)
    end

    for _, column in ipairs(self.COLUMNS) do
        if not seen[column.key] then
            seen[column.key] = true
            tinsert(list, column)
        end
    end

    local ordered, specsAdded = {}, false
    for _, column in ipairs(list) do
        if column.key == "mainSpec" or column.key == "secondSpec" then
            if not specsAdded then
                tinsert(ordered, byKey.mainSpec)
                tinsert(ordered, byKey.secondSpec)
                specsAdded = true
            end
        else
            tinsert(ordered, column)
        end
    end

    return ordered
end

function Members:GetColumnGroups()
    local groups = {}
    for _, column in ipairs(self:GetOrderedColumns()) do
        if column.key ~= "secondSpec" then tinsert(groups, column) end
    end

    return groups
end

function Members:IsColumnEnabled(key)
    if key == "name" then return true end
    if key == "ilvl" then return self:ShowItemLevel() end

    local hidden = self:GetColumnConfig().hidden
    if key == "mainSpec" or key == "secondSpec" then return not (hidden.mainSpec and hidden.secondSpec) end

    return not hidden[key]
end

function Members:ToggleColumn(key)
    if key == "name" then return end
    if key == "ilvl" then
        GuildHelper:SetConfig("SHOWILVL", not self:ShowItemLevel())
    else
        local config = self:GetColumnConfig()
        if key == "mainSpec" or key == "secondSpec" then
            local hidden = self:IsColumnEnabled(key) or nil
            config.hidden.mainSpec = hidden
            config.hidden.secondSpec = hidden
        else
            config.hidden[key] = not config.hidden[key] or nil
        end
    end

    self:ColumnsChanged()
end

function Members:MoveColumn(key, direction)
    if key == "secondSpec" then key = "mainSpec" end
    local order = {}
    for _, column in ipairs(self:GetColumnGroups()) do
        tinsert(order, column.key)
    end

    for index, other in ipairs(order) do
        local target = index + direction
        if other == key and order[target] then
            order[index], order[target] = order[target], order[index]
            break
        end
    end

    local expanded = {}
    for _, columnKey in ipairs(order) do
        tinsert(expanded, columnKey)
        if columnKey == "mainSpec" then tinsert(expanded, "secondSpec") end
    end

    self:GetColumnConfig().order = expanded
    self:ColumnsChanged()
end

function Members:ColumnsChanged()
    self:RenderColumnMenu()
    self:Update()
end

function Members:CreateArrowButton(parent, icon, onClick)
    local button = CreateFrame("Button", nil, parent)
    button:SetSize(22, 22)
    button.icon = Theme:Icon(button, icon, 12, "muted")
    button.icon:SetPoint("CENTER", button, "CENTER", 0, 0)
    button:SetScript("OnEnter", function(sel) if sel:IsEnabled() then Theme:SetKey(sel.icon, "text") end end)
    button:SetScript("OnLeave", function(sel) Theme:SetKey(sel.icon, "muted") end)
    button:SetScript("OnClick", onClick)

    return button
end

function Members:CreateColumnRow(menu, index)
    local row = CreateFrame("Button", nil, menu)
    row:SetHeight(self.COLUMNMENUROW)
    row:SetPoint("TOPLEFT", menu, "TOPLEFT", 5, -5 - (index - 1) * self.COLUMNMENUROW)
    row:SetPoint("TOPRIGHT", menu, "TOPRIGHT", -5, -5 - (index - 1) * self.COLUMNMENUROW)
    row.bg = Theme:Round(row, "hover", 5)
    row.bg:SetShown(false)
    row.check = GuildHelper.Settings:CreateCheck(row)
    row.check:SetPoint("LEFT", row, "LEFT", 6, 0)
    row.down = self:CreateArrowButton(row, "arrowdown", function() Members:MoveColumn(row.key, 1) end)
    row.down:SetPoint("RIGHT", row, "RIGHT", -2, 0)
    row.up = self:CreateArrowButton(row, "arrowup", function() Members:MoveColumn(row.key, -1) end)
    row.up:SetPoint("RIGHT", row.down, "LEFT", -2, 0)
    row.text = Theme:Text(row, 12.5, "text")
    row.text:SetPoint("LEFT", row, "LEFT", 36, 0)
    row.text:SetPoint("RIGHT", row.up, "LEFT", -6, 0)
    for _, frame in ipairs({row, row.check}) do
        frame:SetScript("OnClick", function() Members:ToggleColumn(row.key) end)
    end

    row:SetScript("OnEnter", function(sel) sel.bg:SetShown(sel.key ~= "name") end)
    row:SetScript("OnLeave", function(sel) sel.bg:SetShown(false) end)

    return row
end

function Members:RenderColumnMenu()
    local menu = self.columnMenu
    if not menu or not menu:IsShown() then return end
    local columns = self:GetColumnGroups()
    for index, column in ipairs(columns) do
        local row = menu.rows[index] or self:CreateColumnRow(menu, index)
        menu.rows[index] = row
        local locked = column.key == "name"
        row.key = column.key
        local label = GuildHelper:Trans(column.label)
        if column.key == "mainSpec" then label = label .. " + " .. GuildHelper:Trans("LID_SECONDSPECSHORT") end
        row.text:SetText(label)
        row.check:SetChecked(self:IsColumnEnabled(column.key))
        row.check:SetEnabled(not locked)
        row.check:SetAlpha(locked and 0.45 or 1)
        row.up:SetEnabled(index > 1)
        row.down:SetEnabled(index < #columns)
        row.up:SetAlpha(index > 1 and 1 or 0.3)
        row.down:SetAlpha(index < #columns and 1 or 0.3)
        row:Show()
    end

    for index = #columns + 1, #menu.rows do
        menu.rows[index]:Hide()
    end

    menu:SetHeight(#columns * self.COLUMNMENUROW + 10)
end

function Members:ToggleColumnMenu(anchor)
    if self.menu then self.menu:Hide() end
    local menu = self.columnMenu
    if not menu then
        menu = CreateFrame("Frame", nil, Window.frame)
        menu:SetFrameStrata("DIALOG")
        menu:SetClampedToScreen(true)
        menu:EnableMouse(true)
        menu:SetWidth(230)
        menu:Hide()
        menu.ghNoInside = true
        menu.rows = {}
        Theme:Panel(menu, "card", "border", 7)
        self.columnMenu = menu
    end

    if menu:IsShown() then
        menu:Hide()
        self:SetPillActive(anchor, false)

        return
    end

    menu:ClearAllPoints()
    menu:SetPoint("TOPRIGHT", anchor, "BOTTOMRIGHT", 0, -4)
    menu:SetScript("OnHide", function() if Members.columnsPill then Members:SetPillActive(Members.columnsPill, false) end end)
    menu:Show()
    self:SetPillActive(anchor, true)
    self:RenderColumnMenu()
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
    local box, search
    local inset = 32
    if Theme:IsNative() then
        search = Theme:FlatNative(CreateFrame("EditBox", nil, content, "InputBoxTemplate"))
        search:SetSize(190, 24)
        search:SetPoint("TOPRIGHT", content, "TOPRIGHT", -Window.MARGIN - 42, -27)
        box = search
        inset = 2
    else
        box = CreateFrame("Frame", nil, content)
        box:SetSize(200, 31)
        box:SetPoint("TOPRIGHT", content, "TOPRIGHT", -Window.MARGIN - 42, -24)
        box.fill, box.border = Theme:Panel(box, "control", "border", 7)
        local icon = Theme:Icon(box, "search", 12, "muted")
        icon:SetPoint("LEFT", box, "LEFT", 12, 0)
        search = CreateFrame("EditBox", nil, box)
        search:SetPoint("TOPLEFT", box, "TOPLEFT", 32, 0)
        search:SetPoint("BOTTOMRIGHT", box, "BOTTOMRIGHT", -8, 0)
        Theme:Track(search, "text", "text", 12.5)
    end

    search:SetAutoFocus(false)
    search:SetMaxLetters(60)
    search.placeholder = Theme:Text(box, 12.5, "muted")
    search.placeholder:SetPoint("LEFT", box, "LEFT", inset, 0)
    search.placeholder:SetPoint("RIGHT", box, "RIGHT", -8, 0)
    Theme:SetTrans(search.placeholder, "LID_SEARCH")
    search:SetScript("OnEscapePressed", search.ClearFocus)
    search:SetScript("OnEnterPressed", search.ClearFocus)
    search:SetScript("OnEditFocusGained", function() if box.border then Theme:SetKey(box.border, "accent") end end)
    search:SetScript("OnEditFocusLost", function() if box.border then Theme:SetKey(box.border, "border") end end)
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

    self.onlinePill = self:CreatePill(filters)
    self.onlinePill:SetPoint("LEFT", self.rankPill, "RIGHT", 8, 0)
    self.onlinePill:SetScript("OnClick", function()
        Members.filter.onlineOnly = not Members.filter.onlineOnly
        Members.offset = 0
        Members:ApplyFilter()
    end)

    self.altsPill = self:CreatePill(filters)
    self.altsPill:SetPoint("LEFT", self.onlinePill, "RIGHT", 8, 0)
    self.altsPill:SetScript("OnClick", function()
        Members.filter.hideAlts = not Members.filter.hideAlts
        Members.offset = 0
        Members:ApplyFilter()
    end)

    self.columnsPill = self:CreatePill(content)
    self.columnsPill:SetPoint("RIGHT", content, "TOPRIGHT", -Window.MARGIN - self.DETAILWIDTH - 12, -82)
    self.columnsPill:SetScript("OnClick", function(sel) Members:ToggleColumnMenu(sel) end)
end

function Members:UpdateFilters()
    self:SetPillText(self.classPill, self:GetOptionLabel(self:GetClassOptions(), self.filter.class))
    self:SetPillText(self.rankPill, self:GetOptionLabel(self:GetRankOptions(), self.filter.rank))
    self:SetPillText(self.onlinePill, GuildHelper:Trans("LID_ONLINEONLY"))
    self:SetPillText(self.altsPill, GuildHelper:Trans("LID_HIDEALTS"))
    self:SetPillActive(self.classPill, self.filter.class ~= nil)
    self:SetPillActive(self.rankPill, self.filter.rank ~= nil)
    self:SetPillActive(self.onlinePill, self.filter.onlineOnly)
    self:SetPillActive(self.altsPill, self.filter.hideAlts)
    self:SetPillText(self.columnsPill, GuildHelper:Trans("LID_COLUMNS"))
    self:SetPillActive(self.columnsPill, self.columnMenu ~= nil and self.columnMenu:IsShown())
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
    row.avatar = self:CreateAvatar(row, 22, 11)
    row.name = Theme:Text(row, 13.5)
    row.name:SetPoint("LEFT", row, "LEFT", self.NAMEX + 28, 0)
    row.tag = Theme:Text(row, 10.5, "muted")
    row.tag:SetPoint("LEFT", row.name, "RIGHT", 6, 0)
    row.level = Theme:Text(row, 13, "text")
    row.isMain = Theme:Text(row, 12.5, "text")
    row.mainSpec = Theme:Text(row, 12, "navText")
    row.secondSpec = Theme:Text(row, 12, "navText")
    row.twitch = Theme:Text(row, 12.5, "text")
    row.zone = Theme:Text(row, 12.5, "navText")
    row.rank = Theme:Text(row, 13, "text")
    row.ilvl = Theme:Text(row, 13, "text")
    row.seen = Theme:Text(row, 12, "muted")
    row.note = Theme:Text(row, 12, "navText")
    row.officer = Theme:Text(row, 12, "navText")
    row.badge = CreateFrame("Frame", nil, row)
    row.badge:SetHeight(18)
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

function Members:GetMainLabel(member)
    if member.declaredMain then return GuildHelper:Trans("LID_YES") end
    if member.main then return GuildHelper:Trans("LID_NO") end

    return "–"
end

function Members:GetSpecSortValue(member, slot)
    local data = self:GetData(member)
    local entry = data and data.specs and data.specs[slot]
    if entry == nil or (entry.spec == "" and entry.role == "") then return "\255" end

    return strlower((entry.role or "") .. (entry.spec or ""))
end

function Members:CreateAvatar(parent, size, fontSize)
    local avatar = CreateFrame("Frame", nil, parent)
    avatar:SetSize(size, size)
    local fallback = CreateFrame("Frame", nil, avatar)
    fallback:SetAllPoints()
    fallback:SetFrameLevel(avatar:GetFrameLevel())
    fallback.border = fallback:CreateTexture(nil, "BACKGROUND")
    fallback.border:SetTexture(Theme.MEDIA .. "circle")
    fallback.border:SetAllPoints()
    fallback.fill = fallback:CreateTexture(nil, "BORDER")
    fallback.fill:SetTexture(Theme.MEDIA .. "circle")
    fallback.fill:SetPoint("TOPLEFT", 1, -1)
    fallback.fill:SetPoint("BOTTOMRIGHT", -1, 1)
    fallback.letter = Theme:Text(fallback, fontSize)
    fallback.letter:SetPoint("CENTER")
    avatar.fallback = fallback
    avatar.portrait = avatar:CreateTexture(nil, "ARTWORK")
    avatar.portrait:SetAllPoints()
    local crownSize = size == 22 and 12 or 16
    local crownAtlas = "UI-HUD-UnitFrame-Player-Group-LeaderIcon"
    avatar.crown = avatar:CreateTexture(nil, "OVERLAY")
    avatar.crown:SetSize(crownSize, crownSize)
    avatar.crown:SetPoint("BOTTOM", avatar, "TOP", 0, size == 22 and -4 or -6)
    if avatar.crown.SetAtlas and C_Texture and C_Texture.GetAtlasInfo and C_Texture.GetAtlasInfo(crownAtlas) then
        avatar.crown:SetAtlas(crownAtlas)
    else
        avatar.crown:SetTexture("Interface\\GroupFrame\\UI-Group-LeaderIcon")
    end
    avatar.crown:Hide()

    return avatar
end

function Members:FillAvatar(avatar, member, data, r, g, b)
    local portrait = avatar.portrait
    local displayed = false
    portrait:SetTexture(nil)
    if self:IsSelf(member) and SetPortraitTexture then
        displayed = pcall(SetPortraitTexture, portrait, "player")
    elseif data and data.portraitDisplayID and SetPortraitTextureFromCreatureDisplayID then
        displayed = pcall(SetPortraitTextureFromCreatureDisplayID, portrait, data.portraitDisplayID)
    end

    avatar.crown:SetShown(member.isGuildLeader)
    portrait:SetShown(displayed)
    local fallback = avatar.fallback
    fallback:SetShown(not displayed)
    if displayed then return end
    fallback.border:SetVertexColor(r, g, b, 1)
    fallback.fill:SetVertexColor(r * 0.28, g * 0.28, b * 0.28, 1)
    fallback.letter:SetText(member.short:match("^[%z\1-\127\194-\244][\128-\191]*") or "?")
    fallback.letter:SetTextColor(r, g, b)
end

function Members:FillRow(row, member)
    row.member = member
    local r, g, b = self:GetClassColor(member)
    local data = self:GetData(member)
    self:FillAvatar(row.avatar, member, data, r, g, b)
    row.name:SetText(member.short)
    row.name:SetTextColor(r, g, b)
    row.tag:SetText(member.main and not member.alts and GuildHelper:Trans("LID_ALTTAG") or "")

    self:FitName(row)
    row.level:SetText(member.level)
    local specs = data and data.specs or {}
    row.isMain:SetText(self:GetMainLabel(member))
    Theme:SetKey(row.isMain, member.declaredMain and "accent" or "muted")
    row.mainSpec:SetText(GuildHelper.Specs:FormatIcons(specs[1]) or "–")
    row.secondSpec:SetText(GuildHelper.Specs:FormatIcons(specs[2]) or "–")
    local twitch = self:GetTwitchName(member)
    row.twitch:SetText(twitch ~= "" and twitch or "–")
    row.zone:SetText(member.zone)
    row.rank:SetText(member.rank)
    row.ilvl:SetText(self:GetItemLevel(member) or "–")
    row.note:SetText(member.note)
    row.officer:SetText(member.officerNote)
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
    panel:SetPoint("BOTTOMRIGHT", content, "BOTTOMRIGHT", -Window.MARGIN - self.DETAILWIDTH - 12, self.BOTTOM)
    Theme:Panel(panel, "panel", "border", 9)
    panel:EnableMouseWheel(true)
    panel:SetScript("OnMouseWheel", function(_, delta)
        Members.offset = Members.offset - delta * 3
        Members:Update()
    end)

    self.panel = panel
    self.headers = {}
    self.headerByKey = {}
    for _, column in ipairs(self.COLUMNS) do
        local header = CreateFrame("Button", nil, panel)
        header:SetHeight(self.HEADERHEIGHT)
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
        self.headerByKey[column.key] = header
    end

    local line = Theme:Line(panel, "border")
    line:SetHeight(1)
    line:SetPoint("TOPLEFT", panel, "TOPLEFT", 1, -self.HEADERHEIGHT)
    line:SetPoint("TOPRIGHT", panel, "TOPRIGHT", -1, -self.HEADERHEIGHT)
    panel:SetScript("OnSizeChanged", function()
        Members:LayoutRows()
        Members:Update()
    end)

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
            local maxOffset = max(0, #Members.view - Members.numVisible)
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
    self:LayoutRows()
end

function Members:ShowItemLevel()
    return GuildHelper:GetConfig("SHOWILVL", false) == true
end

function Members:IsColumnShown(column)
    if not self:IsColumnEnabled(column.key) then return false end

    return column.key ~= "officerNote" or self:CanViewOfficerNote()
end

function Members:LayoutColumns()
    local panel = self.panel
    local fixed, notes = 0, 0
    for _, column in ipairs(self.COLUMNS) do
        if column.note and self:IsColumnShown(column) then
            notes = notes + 1
        elseif column.width and self:IsColumnShown(column) then
            fixed = fixed + column.width
        end
    end

    local free = panel:GetWidth() - self.NAMEX - 14 - fixed
    local noteWidth = max(self.MINNOTE, min(self.NOTEWIDTH, (free - self.MINNAME) / max(1, notes)))
    local nameWidth = max(self.MINNAME, free - noteWidth * notes)
    local x = self.NAMEX
    local limit = panel:GetWidth() - 6
    for _, column in ipairs(self:GetOrderedColumns()) do
        local width = column.width or (column.note and noteWidth) or nameWidth
        local shown = self:IsColumnShown(column) and (column.key == "name" or x + width <= limit)
        if column.key == "mainSpec" then shown = shown and x + width * 2 <= limit end
        if column.key == "secondSpec" then shown = shown and self.COLUMNSHOWN.mainSpec end
        local header = self.headerByKey[column.key]
        self.COLUMNX[column.key] = x
        self.COLUMNW[column.key] = width
        self.COLUMNSHOWN[column.key] = shown
        header:ClearAllPoints()
        header:SetPoint("TOPLEFT", panel, "TOPLEFT", x, 0)
        header:SetSize(max(1, width - 6), self.HEADERHEIGHT)
        header:SetShown(shown)
        if shown then x = x + width end
    end

    self.nameWidth = nameWidth
    for _, row in ipairs(self.rows) do
        self:LayoutRow(row)
    end
end

function Members:LayoutRow(row)
    local pos, width, shown = self.COLUMNX, self.COLUMNW, self.COLUMNSHOWN
    local function Place(region, key, offset, size)
        region:ClearAllPoints()
        region:SetPoint("LEFT", row, "LEFT", pos[key] + (offset or 0), 0)
        if size then region:SetWidth(max(1, width[key] - size)) end
        region:SetAlpha(shown[key] and 1 or 0)
    end

    Place(row.avatar, "name")
    Place(row.name, "name", 28)
    Place(row.level, "level")
    Place(row.isMain, "isMain")
    Place(row.mainSpec, "mainSpec", 0, 8)
    Place(row.secondSpec, "secondSpec", 0, 8)
    Place(row.twitch, "twitch", 0, 8)
    Place(row.zone, "zone", 0, 8)
    Place(row.rank, "rank", 0, 8)
    Place(row.ilvl, "ilvl")
    Place(row.seen, "lastOnline")
    Place(row.badge, "lastOnline", -2)
    Place(row.note, "note", 0, 10)
    Place(row.officer, "officerNote", 0, 10)
end

function Members:FitName(row)
    row.name:SetWidth(0)
    local tag = row.tag:GetText() or ""
    local limit = self.nameWidth - 36 - (tag ~= "" and row.tag:GetStringWidth() + 6 or 0)
    if row.name:GetStringWidth() > limit then row.name:SetWidth(max(20, limit)) end
end

function Members:LayoutRows()
    local height = self.panel:GetHeight() or 0
    self.numVisible = max(0, floor((height - self.HEADERHEIGHT - 2) / self.ROWHEIGHT))
    for i = #self.rows + 1, self.numVisible do
        self.rows[i] = self:CreateRow(self.panel, i)
    end

    for i = self.numVisible + 1, #self.rows do
        self.rows[i].member = nil
        self.rows[i]:Hide()
    end
end

function Members:GetTrackHeight()
    return self.panel:GetHeight() - self.HEADERHEIGHT - 12
end

function Members:UpdateScrollBar()
    local thumb = self.thumb
    local total = #self.view
    local visible = self.numVisible
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
    Theme:SetTrans(card.label, label)
    card.value = Theme:Text(card, 16, "text")
    card.value:SetPoint("TOPLEFT", card, "TOPLEFT", 10, -25)
    card.value:SetPoint("RIGHT", card, "RIGHT", -8, 0)

    return card
end

function Members:CreateButton(parent, label, primary)
    if Theme:IsNative() then
        local native = self:CreateNativeButton(parent, 26)
        native:SetWidth(90)
        Theme:SetTrans(native.text, label)

        return native
    end

    local button = CreateFrame("Button", nil, parent)
    button:SetSize(90, 32)
    if primary then
        button.fill = Theme:Round(button, "accent", 7)
    else
        button.fill = Theme:Panel(button, "control", "border", 7)
    end

    button.text = Theme:Text(button, 13, primary and "accentText" or "text")
    button.text:SetPoint("CENTER", button, "CENTER", 0, 0)
    Theme:SetTrans(button.text, label)
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
    row = CreateFrame("Frame", nil, detail.body)
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
    detail:SetPoint("TOPRIGHT", content, "TOPRIGHT", -Window.MARGIN, -self.TABLETOP)
    detail:SetPoint("BOTTOMRIGHT", content, "BOTTOMRIGHT", -Window.MARGIN, self.BOTTOM)
    detail:SetWidth(self.DETAILWIDTH)
    Theme:Panel(detail, "panel", "border", 9)
    detail.professions = {}
    self.detail = detail
    local scroll = CreateFrame("ScrollFrame", nil, detail)
    scroll:SetPoint("TOPLEFT", detail, "TOPLEFT", 0, -1)
    scroll:SetPoint("BOTTOMRIGHT", detail, "BOTTOMRIGHT", 0, 58)
    local body = CreateFrame("Frame", nil, scroll)
    body:SetSize(self.DETAILWIDTH, 1)
    scroll:SetScrollChild(body)
    scroll:EnableMouseWheel(true)
    scroll:SetScript("OnMouseWheel", function(sel, delta)
        sel:SetVerticalScroll(min(max(sel:GetVerticalScroll() - delta * 30, 0), sel:GetVerticalScrollRange()))
        Members:UpdateDetailThumb()
    end)

    scroll:SetScript("OnScrollRangeChanged", function(sel)
        sel:SetVerticalScroll(min(sel:GetVerticalScroll(), sel:GetVerticalScrollRange()))
        Members:UpdateDetailThumb()
    end)

    detail.scroll = scroll
    detail.body = body
    detail.thumb = CreateFrame("Frame", nil, detail)
    detail.thumb:SetWidth(4)
    detail.thumb:SetFrameLevel(scroll:GetFrameLevel() + 5)
    Theme:Round(detail.thumb, "thumb", 2)
    detail.thumb:Hide()
    local avatar = self:CreateAvatar(body, 40, 17)
    avatar:SetPoint("TOPLEFT", body, "TOPLEFT", 16, -16)
    detail.avatar = avatar
    detail.name = Theme:Text(body, 18)
    detail.name:SetPoint("TOPLEFT", avatar, "TOPRIGHT", 12, -2)
    detail.name:SetPoint("RIGHT", body, "RIGHT", -12, 0)
    detail.sub = Theme:Text(body, 12, "muted")
    detail.sub:SetPoint("TOPLEFT", detail.name, "BOTTOMLEFT", 0, -4)
    detail.sub:SetPoint("RIGHT", body, "RIGHT", -12, 0)
    detail.ilvl = self:CreateStatCard(body, "LID_ILVL")
    detail.ilvl:SetPoint("TOPLEFT", body, "TOPLEFT", 16, -68)
    detail.rank = self:CreateStatCard(body, "LID_RANK")
    detail.rank:SetPoint("TOPLEFT", detail.ilvl, "TOPRIGHT", 8, 0)
    detail.specHeader = Theme:Text(body, 11, "muted")
    Theme:SetTrans(detail.specHeader, "LID_SPECS", true)
    detail.specText = Theme:Text(body, 12.5, "text")
    detail.specText:SetWidth(188)
    detail.specText:SetWordWrap(true)
    detail.twitchHeader = Theme:Text(body, 11, "muted")
    Theme:SetTrans(detail.twitchHeader, "LID_TWITCH", true)
    detail.twitchText = Theme:Text(body, 12.5, "text")
    detail.twitchText:SetWidth(188)
    detail.noteHeader = Theme:Text(body, 11, "muted")
    Theme:SetTrans(detail.noteHeader, "LID_NOTE", true)
    detail.noteText = Theme:Text(body, 12.5, "text")
    detail.noteText:SetWidth(188)
    detail.noteText:SetWordWrap(true)
    detail.officerHeader = Theme:Text(body, 11, "muted")
    Theme:SetTrans(detail.officerHeader, "LID_OFFICERNOTE", true)
    detail.officerText = Theme:Text(body, 12.5, "text")
    detail.officerText:SetWidth(188)
    detail.officerText:SetWordWrap(true)
    detail.profHeader = Theme:Text(body, 11, "muted")
    Theme:SetTrans(detail.profHeader, "LID_PROFESSIONS", true)
    detail.profEmpty = Theme:Text(body, 12, "muted")
    detail.altHeader = Theme:Text(body, 11, "muted")
    detail.altText = Theme:Text(body, 12.5, "text")
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
    detail.noteHit = self:CreateEditLink(body, detail.noteHeader, detail.noteText)
    detail.officerHit = self:CreateEditLink(body, detail.officerHeader, detail.officerText)
    detail.content = {avatar, detail.name, detail.sub, detail.ilvl, detail.rank, detail.specHeader, detail.specText, detail.twitchHeader, detail.twitchText, detail.noteHeader, detail.noteText, detail.officerHeader, detail.officerText, detail.profHeader, detail.profEmpty, detail.altHeader, detail.altText, detail.whisper, detail.invite}
end

function Members:PlaceSection(header, text, y, value, empty)
    header:ClearAllPoints()
    header:SetPoint("TOPLEFT", self.detail.body, "TOPLEFT", 16, y)
    text:ClearAllPoints()
    text:SetPoint("TOPLEFT", header, "BOTTOMLEFT", 0, -6)
    text:SetText(value ~= "" and value or empty)
    Theme:SetKey(text, value ~= "" and "text" or "muted")

    return y - 20 - max(14, text:GetStringHeight()) - 12
end

function Members:IsSelf(member)
    if member == nil then return false end
    local guid = UnitGUID and UnitGUID("player")
    if guid and member.guid then return member.guid == guid end
    local name = UnitName("player") or ""

    return member.key == GuildHelper.Sync:GetKey(name)
end

function Members:CanViewOfficerNote()
    if C_GuildInfo and C_GuildInfo.CanViewOfficerNote then return C_GuildInfo.CanViewOfficerNote() == true end
    if CanViewOfficerNote then return CanViewOfficerNote() == true end

    return false
end

function Members:CanEditOfficerNote()
    if C_GuildInfo and C_GuildInfo.CanEditOfficerNote then return C_GuildInfo.CanEditOfficerNote() == true end
    if CanEditOfficerNote then return CanEditOfficerNote() == true end

    return false
end

function Members:CanEditPublicNote(member)
    if self:IsSelf(member) then return true end
    if CanEditPublicNote then return CanEditPublicNote() == true end
    if C_GuildInfo and C_GuildInfo.CanEditPublicNote then return C_GuildInfo.CanEditPublicNote() == true end

    return false
end

function Members:GetEditMessage(hit)
    if hit.canEdit == false then return "LID_NOEDITRIGHT" end
    if InCombatLockdown() then return "LID_NOTINCOMBAT" end

    return "LID_OPENGUILDHINT"
end

function Members:CreateEditLink(parent, header, text)
    local hit = CreateFrame("Button", nil, parent)
    hit:SetPoint("TOPLEFT", header, "TOPLEFT", -6, 5)
    hit:SetPoint("BOTTOMRIGHT", text, "BOTTOMRIGHT", 6, -5)
    hit.bg = Theme:Round(hit, "rowHover", 6)
    hit.bg:SetShown(false)
    hit:SetFrameLevel(parent:GetFrameLevel() + 3)
    hit:SetScript("OnEnter", function(sel)
        if sel.canEdit ~= false and Window:ShowGuildOverlay(sel) then return end
        sel.bg:SetShown(true)
        GameTooltip:SetOwner(sel, "ANCHOR_RIGHT")
        GameTooltip:AddLine(GuildHelper:Trans(Members:GetEditMessage(sel)), 1, sel.canEdit == false and 0.3 or 1, sel.canEdit == false and 0.3 or 1, true)
        GameTooltip:Show()
    end)

    hit:SetScript("OnLeave", function(sel)
        sel.bg:SetShown(false)
        GameTooltip:Hide()
    end)

    hit:SetScript("OnClick", function(sel)
        GameTooltip:Hide()
        if UIErrorsFrame then UIErrorsFrame:AddMessage(GuildHelper:Trans(Members:GetEditMessage(sel)), 1, 0.1, 0.1) end
    end)

    return hit
end

function Members:UpdateNoteEditor(hit, member, canEdit)
    hit:SetShown(member ~= nil)
    hit.canEdit = canEdit == true
end

function Members:FindByKey(key)
    for _, member in ipairs(self.list) do
        if member.key == key then return member end
    end

    return nil
end

function Members:GetSelf()
    for _, member in ipairs(self.list) do
        if self:IsSelf(member) then return member end
    end

    return nil
end

function Members:Focus(member)
    self.focusKey = member and member.key
    Window:SelectPage("members")
end

function Members:ApplyFocus()
    local key = self.focusKey
    if key == nil then return end
    self.focusKey = nil
    self.selectedKey = key
    for index, member in ipairs(self.view) do
        if member.key == key then
            if index <= self.offset or index > self.offset + self.numVisible then self.offset = max(0, index - 1) end
            break
        end
    end

    self:Update()
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

function Members:UpdateDetailThumb()
    local detail = self.detail
    local scroll = detail.scroll
    local range = scroll:GetVerticalScrollRange()
    if range <= 0 or not detail.body:IsShown() then
        detail.thumb:Hide()

        return
    end

    local track = scroll:GetHeight() - 12
    local height = max(24, track * scroll:GetHeight() / (scroll:GetHeight() + range))
    detail.thumb:SetHeight(height)
    detail.thumb:ClearAllPoints()
    detail.thumb:SetPoint("TOPRIGHT", scroll, "TOPRIGHT", -4, -6 - (track - height) * scroll:GetVerticalScroll() / range)
    detail.thumb:Show()
end

function Members:UpdateDetail()
    local detail = self.detail
    local member = self:GetSelected()
    if member == nil or member.key ~= detail.shownKey then detail.scroll:SetVerticalScroll(0) end
    detail.shownKey = member and member.key
    for _, region in ipairs(detail.content) do
        region:SetShown(member ~= nil)
    end

    detail.empty:SetShown(member == nil)
    for _, row in ipairs(detail.professions) do
        row:Hide()
    end

    local viewOfficer = self:CanViewOfficerNote()
    self:UpdateNoteEditor(detail.noteHit, member, self:CanEditPublicNote(member))
    self:UpdateNoteEditor(detail.officerHit, viewOfficer and member or nil, self:CanEditOfficerNote())
    if member == nil then
        detail.body:SetHeight(1)
        self:UpdateDetailThumb()

        return
    end
    local r, g, b = self:GetClassColor(member)
    local data = self:GetData(member)
    self:FillAvatar(detail.avatar, member, data, r, g, b)
    detail.name:SetText(member.short)
    detail.name:SetTextColor(r, g, b)
    detail.sub:SetText(GuildHelper:Trans("LID_CLASSLEVEL", nil, member.className, member.level))
    local showIlvl = self:ShowItemLevel()
    detail.ilvl:SetShown(showIlvl)
    detail.ilvl.value:SetText(self:GetItemLevel(member) or "–")
    detail.rank:ClearAllPoints()
    if showIlvl then
        detail.rank:SetPoint("TOPLEFT", detail.ilvl, "TOPRIGHT", 8, 0)
    else
        detail.rank:SetPoint("TOPLEFT", detail.ilvl, "TOPLEFT", 0, 0)
    end

    detail.rank.value:SetText(member.rank)
    local professions = data and data.professions or {}
    local y = -136
    local hasSpecs = data ~= nil and data.specs ~= nil
    detail.specHeader:SetShown(hasSpecs)
    detail.specText:SetShown(hasSpecs)
    if hasSpecs then y = self:PlaceSection(detail.specHeader, detail.specText, y, GuildHelper.Specs:Describe(data.specs), "–") end
    local hasTwitch = data ~= nil and type(data.twitch) == "string" and data.twitch ~= ""
    detail.twitchHeader:SetShown(hasTwitch)
    detail.twitchText:SetShown(hasTwitch)
    if hasTwitch then y = self:PlaceSection(detail.twitchHeader, detail.twitchText, y, data.twitch, "–") end
    y = self:PlaceSection(detail.noteHeader, detail.noteText, y, member.note, "–")
    local hasOfficer = viewOfficer or member.officerNote ~= ""
    detail.officerHeader:SetShown(hasOfficer)
    detail.officerText:SetShown(hasOfficer)
    if hasOfficer then y = self:PlaceSection(detail.officerHeader, detail.officerText, y, member.officerNote, "–") end
    detail.profHeader:ClearAllPoints()
    detail.profHeader:SetPoint("TOPLEFT", detail.body, "TOPLEFT", 16, y)
    y = y - 20
    local step = #professions > 3 and 26 or 31
    for i, prof in ipairs(professions) do
        local row = self:GetProfessionRow(i)
        row:ClearAllPoints()
        row:SetPoint("TOPLEFT", detail.body, "TOPLEFT", 16, y)
        local sync = GuildHelper.Sync
        row.name:SetText(sync:GetProfessionName(sync:GetProfessionID(prof[1], prof[4]), prof[1]))
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
        detail.profEmpty:SetPoint("TOPLEFT", detail.body, "TOPLEFT", 16, y)
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
    detail.altHeader:SetPoint("TOPLEFT", detail.body, "TOPLEFT", 16, y - 10)
    detail.altText:ClearAllPoints()
    detail.altText:SetPoint("TOPLEFT", detail.altHeader, "BOTTOMLEFT", 0, -8)
    detail.altText:SetText(table.concat(names, ", "))
    if #names > 0 then y = y - 10 - 14 - 8 - detail.altText:GetStringHeight() end
    detail.body:SetHeight(max(1, -y + 12))
    self:UpdateDetailThumb()
    local isSelf = self:IsSelf(member)
    detail.whisper:SetAlpha(isSelf and 0.4 or 1)
    detail.whisper:SetEnabled(not isSelf)
    detail.invite:SetAlpha((isSelf or not member.online) and 0.4 or 1)
    detail.invite:SetEnabled(not isSelf and member.online)
end

function Members:Update()
    if self.content == nil or self.detail == nil or not self.content:IsVisible() then return end
    local inGuild = IsInGuild()
    self.panel:SetShown(inGuild)
    self.detail:SetShown(inGuild)
    self.filters:SetShown(inGuild)
    self.columnsPill:SetShown(inGuild)
    self.searchBox:SetShown(inGuild)
    self.noGuild:SetShown(not inGuild)
    if not inGuild then
        self.count:SetText("")

        return
    end

    if self:GetSelected() == nil then self.selectedKey = self.view[1] and self.view[1].key or nil end
    self:LayoutColumns()
    local maxOffset = max(0, #self.view - self.numVisible)
    self.offset = min(max(self.offset, 0), maxOffset)
    for i, row in ipairs(self.rows) do
        local member = i <= self.numVisible and self.view[self.offset + i]
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
    Theme:SetTrans(self.noGuild, "LID_NOGUILD")
    content.OnPageShow = function()
        Members:RequestRoster()
        Members:Refresh()
        Members:ApplyFocus()
    end

    content.OnPageHide = function()
        if Members.menu then Members.menu:Hide() end
        if Members.columnMenu then Members.columnMenu:Hide() end
    end
end

function Members:Reset()
    self.content = nil
    self.panel = nil
    self.detail = nil
    self.headers = nil
    self.headerByKey = nil
    self.thumb = nil
    self.menu = nil
    self.columnMenu = nil
    self.columnsPill = nil
    self.searchBox = nil
    self.filters = nil
    self.rows = {}
    self.numVisible = 0
    self.filter.text = ""
end

function Members:Init()
    Window:OnRebuild(function() Members:Reset() end)
    self:LoadFilter()
    Theme:OnRefresh(function() Members:Update() end)
    GuildHelper.Sync:OnUpdate(function()
        if Members.content == nil or not Members.content:IsVisible() then return end
        Members:LinkMains()
        Members:ApplyFilter()
    end)
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
