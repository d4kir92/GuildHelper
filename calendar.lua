local _, GuildHelper = ...
local Events, Groups, Theme, Window = GuildHelper.Events, GuildHelper.Groups, GuildHelper.Theme, GuildHelper.Window
local Calendar = {
    months = {"JANUARY", "FEBRUARY", "MARCH", "APRIL", "MAY", "JUNE", "JULY", "AUGUST", "SEPTEMBER", "OCTOBER", "NOVEMBER", "DECEMBER"},
    sources = {
        {key = "events", label = "LID_EVENTS", color = "accent"},
        {key = "wow", label = "LID_CALENDAR_WOW", color = "online"},
        {key = "groups", label = "LID_CALENDAR_GROUPS", color = "text"},
    },
}
GuildHelper.Calendar = Calendar

function Calendar:HasAPI()
    return C_Calendar ~= nil and C_Calendar.GetMonthInfo ~= nil and C_Calendar.GetNumDayEvents ~= nil and C_Calendar.GetDayEvent ~= nil
end

function Calendar:InitWoW()
    if self:HasAPI() and not self.wowOpened then
        self.wowOpened = not C_Calendar.OpenCalendar or pcall(C_Calendar.OpenCalendar)
    end
end

function Calendar:ReadWoWDay(day, base)
    local offset = (day.year - base.year) * 12 + day.month - base.month
    local items = {}
    local count = C_Calendar.GetNumDayEvents(offset, day.day)
    if not GuildHelper:CanAccessValues(count) or type(count) ~= "number" then return items end
    for index = 1, count do
        local info = C_Calendar.GetDayEvent(offset, day.day, index)
        if GuildHelper:CanAccessValues(info) and info and GuildHelper:CanAccessValues(info.title, info.startTime) then
            local start = info.startTime
            if start and GuildHelper:CanAccessValues(start.year, start.month, start.monthDay, start.hour, start.minute) and
                start.year and start.month and start.monthDay and start.hour and start.minute and info.title and info.title ~= "" then
                local when = format("%04d-%02d-%02d %02d:%02d", start.year, start.month, start.monthDay, start.hour, start.minute)
                local displayDay = format("%04d-%02d-%02d", day.year, day.month, day.day)
                tinsert(items, {source = "wow", title = info.title, when = when,
                    clock = when:sub(1, 10) == displayDay and when:sub(12) or nil})
            end
        end
    end
    return items
end

function Calendar:ReadWoW(days)
    if not self:HasAPI() then return false end
    local ok, base = pcall(C_Calendar.GetMonthInfo, 0)
    if not ok or not GuildHelper:CanAccessValues(base) or not base or
        not GuildHelper:CanAccessValues(base.year, base.month) or not base.year or not base.month then return false end
    local available = true
    for _, day in ipairs(days) do
        local read, items = pcall(self.ReadWoWDay, self, day.date, base)
        if read then
            for _, item in ipairs(items) do tinsert(day.items, item) end
        elseif day.stamp == self.focus then
            available = false
        end
    end
    return available
end

function Calendar:Period()
    local focus = date("*t", self.focus)
    local month = self.view == "month"
    local first = month and Events:Day(focus.year, focus.month, 1) or self.focus
    local firstDate = date("*t", first)
    local leading = (firstDate.wday + 5) % 7
    local rows = 1
    if month then
        local nextMonth = Events:Day(focus.year, focus.month + 1, 0)
        rows = math.ceil((leading + tonumber(date("%d", nextMonth))) / 7)
    end

    local days, byDate = {}, {}
    for index = 1, rows * 7 do
        local stamp = Events:Day(firstDate.year, firstDate.month, firstDate.day - leading + index - 1)
        local key = date("%Y-%m-%d", stamp)
        local day = {stamp = stamp, key = key, date = date("*t", stamp), items = {}}
        days[index], byDate[key] = day, day
    end
    return days, byDate, rows
end

function Calendar:IsEnabled(source)
    return GuildHelper:GetConfig("CALENDAR_" .. source, true)
end

function Calendar:Collect(days, byDate)
    if not self.picking and self:IsEnabled("events") then
        for _, event in ipairs(Events:GetList()) do
            local day = byDate[event.when:sub(1, 10)]
            if day then
                tinsert(day.items, {source = "events", title = event.title, when = event.when, clock = event.when:sub(12), id = event.id, icon = Events:GetIcon(event.id)})
            end
        end
    end
    if not self.picking and self:IsEnabled("groups") then
        Groups:CheckGuild()
        for _, entry in ipairs(Groups:GetList("P")) do
            local when = Events:PlannedClock(entry.when)
            local day = byDate[when:sub(1, 10)]
            if day then
                tinsert(day.items, {source = "groups", title = Groups:GetActivityName(entry), when = when, clock = when:sub(12), entry = entry})
            end
        end
    end
    local wowAvailable = true
    if self.picking or self:IsEnabled("wow") then wowAvailable = self:ReadWoW(days) end
    for _, day in ipairs(days) do
        table.sort(day.items, function(a, b)
            if (a.clock or "") ~= (b.clock or "") then return (a.clock or "") < (b.clock or "") end
            if a.source ~= b.source then return a.source < b.source end
            return a.title < b.title
        end)
    end
    return wowAvailable
end

function Calendar:Activate(item)
    if item.source == "events" then
        Window:SelectPage("events")
        Events:Select(item.id)
    elseif item.source == "groups" then
        Window:SelectPage("groups")
        Groups:SetMode("P")
        Groups:Select(item.entry)
    elseif self.picking then
        self.picking = false
        Events:Import(item)
    end
end

function Calendar:Move(direction)
    local current = date("*t", self.focus)
    if self.view == "month" then
        self.focus = Events:Day(current.year, current.month + direction, 1)
    else
        self.focus = Events:Day(current.year, current.month, current.day + direction * 7)
    end
    self.agenda.scroll:SetVerticalScroll(0)
    self:Refresh()
end

function Calendar:Pick(day)
    self.picking = true
    local year, month, dayNumber = day:match("^(%d%d%d%d)%-(%d%d)%-(%d%d)$")
    self.focus = Events:ParseDate(day, "00:00") and Events:Day(tonumber(year), tonumber(month), tonumber(dayNumber)) or Events:Today()
    Window:SelectPage("calendar")
end

function Calendar:SetView(view)
    self.view = view
    GuildHelper:SetConfig("CALENDAR_VIEW", view)
    self:Refresh()
end

function Calendar:CreateCell(grid, index)
    local cell = CreateFrame("Button", nil, grid)
    cell.ghNoInside = true
    cell.fill = Theme:Panel(cell, "control", "border", 4)
    cell.day = Theme:Text(cell, 11, "muted")
    cell.day:SetPoint("TOPLEFT", 6, -4)
    cell.count = Theme:Text(cell, 10, "muted")
    cell.count:SetPoint("TOPRIGHT", -5, -5)
    cell.lines = {}
    cell:SetScript("OnClick", function(button)
        self.focus = button.data.stamp
        self.agenda.scroll:SetVerticalScroll(0)
        self:Refresh()
    end)
    self.cells[index] = cell
    return cell
end

function Calendar:LayoutGrid()
    if not self.days then return end
    local width = max(1, (self.grid:GetWidth() - 18) / 7)
    local height = max(1, (self.grid:GetHeight() - (self.rows - 1) * 3) / self.rows)
    local lineCount = max(0, floor((height - 21) / 15))
    for index, day in ipairs(self.days) do
        local cell = self.cells[index] or self:CreateCell(self.grid, index)
        cell.data = day
        cell:SetSize(width, height)
        cell:SetPoint("TOPLEFT", self.grid, "TOPLEFT", (index - 1) % 7 * (width + 3), -floor((index - 1) / 7) * (height + 3))
        cell:Show()
        Theme:SetKey(cell.fill, self.focus == day.stamp and "rowHover" or "control")
        local otherMonth = self.view == "month" and day.date.month ~= self.focusMonth
        Theme:SetKey(cell.day, day.stamp == self.today and "accent" or otherMonth and "muted" or "text")
        cell.day:SetText(day.date.day)
        local more = #day.items - lineCount
        cell.count:SetText(more > 0 and "+" .. more or "")
        for lineIndex = 1, min(#day.items, lineCount) do
            local item = day.items[lineIndex]
            local line = cell.lines[lineIndex]
            if not line then
                line = Theme:Text(cell, 10.5, "text")
                line:SetPoint("TOPLEFT", 6, -19 - (lineIndex - 1) * 15)
                line:SetPoint("RIGHT", -5, 0)
                line:SetJustifyH("LEFT")
                line:SetWordWrap(false)
                cell.lines[lineIndex] = line
            end
            Theme:SetKey(line, self.sourceByKey[item.source].color)
            line:SetText(Events:IconMarkup(item.icon, 11) .. (item.clock and item.clock .. " " .. item.title or item.title))
            line:Show()
        end
        for lineIndex = min(#day.items, lineCount) + 1, #cell.lines do cell.lines[lineIndex]:Hide() end
    end
    for index = #self.days + 1, #self.cells do self.cells[index]:Hide() end
    for index, label in ipairs(self.weekdays) do
        label:SetWidth(width)
        label:SetPoint("BOTTOMLEFT", self.grid, "TOPLEFT", (index - 1) * (width + 3), 4)
    end
end

function Calendar:Refresh()
    if not self.content or not self.content:IsVisible() then return end
    self.today = Events:Today()
    self.focus = self.focus or self.today
    self.focusMonth = tonumber(date("%m", self.focus))
    local days, byDate, rows = self:Period()
    self.days, self.rows = days, rows
    local wowAvailable = self:Collect(days, byDate)
    local day = byDate[date("%Y-%m-%d", self.focus)]
    local items = {}
    for _, item in ipairs(day.items) do
        local source = self.sourceByKey[item.source]
        local label = Events:IconMarkup(item.icon, 14) .. (item.clock or item.when) .. "  ·  " .. item.title .. "  ·  " .. GuildHelper:Trans(source.label)
        tinsert(items, {text = label, color = source.color, action = (self.picking or item.source ~= "wow") and function() self:Activate(item) end or nil})
    end
    if not wowAvailable then
        tinsert(items, {text = GuildHelper:Trans("LID_CALENDAR_WOW_UNAVAILABLE"), color = "muted"})
    elseif #items == 0 then
        tinsert(items, {text = GuildHelper:Trans("LID_CALENDAR_EMPTY_DAY"), color = "muted"})
    end
    self.agenda.title:SetText(day.key)
    Events:RenderList(self.agenda, items)
    local localizedMonth = _G["MONTH_" .. self.months[self.focusMonth]]
    self.period:SetText(self.view == "month" and ((localizedMonth or date("%B", self.focus)) .. " " .. day.date.year) or
        days[1].key .. " – " .. days[#days].key)
    self.period:SetWidth(self.view == "month" and 125 or 165)
    self.cancel:SetShown(self.picking == true)
    self.filters:SetShown(not self.picking)
    Theme:SetTrans(self.title, self.picking and "LID_EVENT_IMPORT" or "LID_CALENDAR")
    for view, button in pairs(self.viewButtons) do Theme:SetKey(button.text, self.view == view and "accent" or "text") end
    for key, button in pairs(self.filterButtons) do button:SetChecked(self:IsEnabled(key)) end
    for index, label in ipairs(self.weekdays) do
        local weekday = Groups.WEEKDAYS[index % 7 + 1]
        label:SetText(_G[weekday] or date("%a", days[index].stamp))
    end
    self:LayoutGrid()
end

function Calendar:QueueRefresh()
    if self.refreshQueued or not self.content or not self.content:IsVisible() then return end
    self.refreshQueued = true
    C_Timer.After(0, function()
        self.refreshQueued = false
        self:Refresh()
    end)
end

function Calendar:Build(content)
    self.content = content
    self.cells, self.weekdays, self.viewButtons, self.filterButtons, self.sourceByKey = {}, {}, {}, {}, {}
    self.view = GuildHelper:GetConfig("CALENDAR_VIEW", "month") == "week" and "week" or "month"
    self.title = Window:CreatePageTitle(content, "LID_CALENDAR")
    local week = Events:Button(content, "LID_CALENDAR_WEEK", 100, function() self:SetView("week") end)
    week:SetPoint("TOPRIGHT", -76, -23)
    local month = Events:Button(content, "LID_CALENDAR_MONTH", 100, function() self:SetView("month") end)
    month:SetPoint("RIGHT", week, "LEFT", -6, 0)
    self.viewButtons.month, self.viewButtons.week = month, week
    local prev = Events:Button(content, nil, 27, function() self:Move(-1) end)
    prev.text:SetText("‹")
    prev:SetPoint("TOPLEFT", 20, -65)
    self.period = Theme:Text(content, 13, "text")
    self.period:SetPoint("LEFT", prev, "RIGHT", 3, 0)
    self.period:SetJustifyH("CENTER")
    local nextButton = Events:Button(content, nil, 27, function() self:Move(1) end)
    nextButton.text:SetText("›")
    nextButton:SetPoint("LEFT", self.period, "RIGHT", 3, 0)
    local today = Events:Button(content, "LID_TODAY", 88, function()
        self.focus = Events:Today()
        self.agenda.scroll:SetVerticalScroll(0)
        self:Refresh()
    end)
    today:SetPoint("LEFT", nextButton, "RIGHT", 8, 0)
    self.cancel = Events:Button(content, "LID_FBCANCEL", 120, function()
        self.picking = false
        Window:SelectPage("events")
    end)
    self.cancel:SetPoint("TOPRIGHT", -20, -65)
    self.filters = CreateFrame("Frame", nil, content)
    self.filters:SetPoint("TOPLEFT", content, "TOPLEFT", 358, -65)
    self.filters:SetPoint("BOTTOMRIGHT", content, "TOPRIGHT", -20, -97)
    local anchor = self.filters
    for index, source in ipairs(self.sources) do
        local check = GuildHelper.Settings:CreateCheck(self.filters)
        check:SetPoint("LEFT", anchor, index == 1 and "LEFT" or "RIGHT", index == 1 and 0 or 12, 0)
        local label = Theme:Text(self.filters, 12, source.color)
        label:SetPoint("LEFT", check, "RIGHT", 4, 0)
        Theme:SetTrans(label, source.label)
        check:SetScript("OnClick", function()
            GuildHelper:SetConfig("CALENDAR_" .. source.key, not self:IsEnabled(source.key))
            self:Refresh()
        end)
        self.filterButtons[source.key] = check
        self.sourceByKey[source.key] = source
        anchor = label
    end
    self.grid = CreateFrame("Frame", nil, content)
    self.grid:SetPoint("TOPLEFT", 20, -116)
    self.grid:SetPoint("BOTTOMRIGHT", -20, 158)
    for index = 1, 7 do
        local label = Theme:Text(content, 11, "muted")
        label:SetWordWrap(false)
        self.weekdays[index] = label
    end
    self.grid:SetScript("OnSizeChanged", function() self:LayoutGrid() end)
    self.agenda = Events:List(content, nil)
    self.agenda:SetPoint("TOPLEFT", self.grid, "BOTTOMLEFT", 0, -8)
    self.agenda:SetPoint("BOTTOMRIGHT", content, "BOTTOMRIGHT", -20, 20)
    Events:BindListSize(self.agenda)
    content.OnPageShow = function()
        self:InitWoW()
        self:Refresh()
    end
    content.OnPageHide = function() self.picking = false end
end

Window:SetPageBuilder("calendar", function(content) Calendar:Build(content) end)
Window:OnRebuild(function() Calendar.content, Calendar.days = nil, nil end)
Theme:OnRefresh(function() Calendar:Refresh() end)
local frame = CreateFrame("Frame")
for _, event in ipairs({"CALENDAR_UPDATE_EVENT_LIST", "CALENDAR_UPDATE_GUILD_EVENTS", "CALENDAR_UPDATE_EVENT", "PLAYER_REGEN_ENABLED"}) do
    if not C_EventUtils or not C_EventUtils.IsEventValid or C_EventUtils.IsEventValid(event) then
        frame:RegisterEvent(event)
    end
end
frame:SetScript("OnEvent", function() Calendar:QueueRefresh() end)
