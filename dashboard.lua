local _, GuildHelper = ...
local Theme = GuildHelper.Theme
local Window = GuildHelper.Window
local Members = GuildHelper.Members
local Dashboard = {}
GuildHelper.Dashboard = Dashboard
Dashboard.LINE = 22
Dashboard.TOP = 70
Dashboard.MOTDTOP = 146
Dashboard.SCROLLTOP = 66
Dashboard.SCROLLPAD = 4
Dashboard.MINLOWER = 398
Dashboard.CHATLIMIT = 50
Dashboard.CHATMAX = 500
function Dashboard:CheckGuild()
    local guild = GuildHelper.Sync:GetGuildKey()
    if guild ~= self.guild then
        self.guild = guild
        self.chatMessages = {}
        self.chatClubID = nil
        self.chatStreamID = nil
        self:ResetChatHistory()
        self.cachedMOTD = nil
        self.lastRequest = nil
    end

    return guild ~= nil
end

function Dashboard:GetMOTD()
    if not self:CheckGuild() then return "" end
    local text = GetGuildRosterMOTD and GetGuildRosterMOTD()
    if not GuildHelper:CanAccessValues(text) then text = nil end
    if (not text or text == "") and C_Club and C_Club.GetGuildClubId and C_Club.GetClubInfo then
        local id = C_Club.GetGuildClubId()
        local info = id and C_Club.GetClubInfo(id)
        text = info and info.broadcast
    end

    if type(text) == "string" and GuildHelper:CanAccessValues(text) and text ~= "" then self.cachedMOTD = text end

    return self.cachedMOTD or ""
end

function Dashboard:RequestData()
    if not self:CheckGuild() then return end
    local now = GetTime()
    if self.lastRequest and now - self.lastRequest < 5 then return end
    self.lastRequest = now
    Members:RequestRoster()
    if self:HasNews() then
        if QueryGuildNews then QueryGuildNews() end
        if GuildNewsSort then GuildNewsSort(0) end
    end
end

Dashboard.NEWSFILTERS = {
    {id = 2, label = "LID_NEWSACHIEVEMENTS"},
    {id = 4, label = "LID_NEWSLOOTED"},
    {id = 6, label = "LID_NEWSCRAFTED"},
    {id = 5, label = "LID_NEWSPURCHASED"},
    {id = 9, label = "LID_NEWSLEGENDARY"}
}
function Dashboard:UpdateNewsFilters()
    if not self.newsFilters then return end
    local filters = GetGuildNewsFilters and {GetGuildNewsFilters()} or {}
    for index, option in ipairs(self.NEWSFILTERS) do
        self.newsFilters.rows[index]:SetChecked(filters[option.id] ~= false and filters[option.id] ~= 0)
    end
end

function Dashboard:ToggleNewsFilters()
    if self.newsFilters then
        self.newsFilters:SetShown(not self.newsFilters:IsShown())
        self:UpdateNewsFilters()
        return
    end

    local panel = CreateFrame("Frame", nil, Window.frame)
    panel:SetFrameStrata("DIALOG")
    panel:SetClampedToScreen(true)
    panel:SetSize(300, 44 + #self.NEWSFILTERS * 30)
    panel:SetPoint("TOPLEFT", self.newsFilterButton, "BOTTOMLEFT", 0, -6)
    panel.ghNoInside = true
    Theme:Panel(panel, "card", "border", 8)
    local title = Theme:Text(panel, 13, "text")
    title:SetPoint("TOPLEFT", panel, "TOPLEFT", 12, -12)
    Theme:SetTrans(title, "LID_NEWSFILTERS")
    local close = Members:CreatePill(panel, "×")
    close:SetPoint("TOPRIGHT", panel, "TOPRIGHT", -6, -5)
    close:SetScript("OnClick", function() panel:Hide() end)
    panel.rows = {}
    for index, option in ipairs(self.NEWSFILTERS) do
        local check = GuildHelper.Settings:CreateCheck(panel)
        check:SetPoint("TOPLEFT", panel, "TOPLEFT", 12, -38 - (index - 1) * 30)
        local label = Theme:Text(panel, 12, "text")
        label:SetPoint("LEFT", check, "RIGHT", 8, 0)
        Theme:SetTrans(label, option.label)
        check:SetScript("OnClick", function()
            local filters = GetGuildNewsFilters and {GetGuildNewsFilters()} or {}
            local enabled = filters[option.id] == false or filters[option.id] == 0
            if SetGuildNewsFilter then SetGuildNewsFilter(option.id, enabled and 1 or 0) end
            self:UpdateNewsFilters()
            if self.news then self:UpdateNews() end
        end)
        panel.rows[index] = check
    end

    self.newsFilters = panel
    self:UpdateNewsFilters()
end

function Dashboard:CanEditMOTD()
    return CanEditMOTD ~= nil and CanEditMOTD() == true
end

function Dashboard:GetGuildInformation()
    if C_GuildInfo and C_GuildInfo.GetInfoText then return C_GuildInfo.GetInfoText() or "" end
    if GetGuildInfoText then return GetGuildInfoText() or "" end

    return ""
end

function Dashboard:HasNews()
    return GetNumGuildNews ~= nil and C_GuildInfo ~= nil and C_GuildInfo.GetGuildNewsInfo ~= nil
end

function Dashboard:FormatNews(info)
    if info.isHeader then return format("%02d.%02d.", (info.day or 0) + 1, (info.month or 0) + 1) end
    local who = info.whoText or UNKNOWN or "?"
    local what = info.whatText or UNKNOWN or "?"
    if info.newsType == 0 then who = what end
    if info.newsType == 6 then who = tonumber(info.data and info.data[1]) or tonumber(info.whatText) or 0 end
    local template = _G["GUILD_NEWS_FORMAT" .. tostring(info.newsType)]
    if template then
        local ok, text = pcall(format, template, who, what)
        if ok then return text end
    end

    return tostring(who) .. ": " .. what
end

function Dashboard:UpdateNews()
    if not self:HasNews() then
        self.news.text:SetText(GuildHelper:Trans("LID_NEWSUNAVAILABLE"))
    else
        local entries = {}
        local motd = self:GetMOTD()
        if motd ~= "" then tinsert(entries, GuildHelper:Trans("LID_MOTD") .. ": " .. motd) end
        for index = 1, GetNumGuildNews() do
            local info = C_GuildInfo.GetGuildNewsInfo(index)
            if info then tinsert(entries, self:FormatNews(info)) end
        end

        self.news.text:SetText(#entries > 0 and table.concat(entries, "\n\n") or GuildHelper:Trans("LID_NONEWS"))
    end

    self.news:ResizeText()
end

function Dashboard:CreateCard(parent, label)
    local card = CreateFrame("Frame", nil, parent)
    Theme:Panel(card, "panel", "border", 9)
    card.title = Theme:Text(card, 11, "muted")
    card.title:SetPoint("TOPLEFT", card, "TOPLEFT", 16, -14)
    if label then Theme:SetTrans(card.title, label, true) end

    return card
end

function Dashboard:CreateList(card)
    local scroll = CreateFrame("ScrollFrame", nil, card)
    scroll:SetPoint("TOPLEFT", card, "TOPLEFT", 6, -34)
    scroll:SetPoint("BOTTOMRIGHT", card, "BOTTOMRIGHT", -6, 8)
    local body = CreateFrame("Frame", nil, scroll)
    body:SetSize(1, 1)
    scroll:SetScrollChild(body)
    scroll:EnableMouseWheel(true)
    scroll:SetScript("OnMouseWheel", function(sel, delta)
        local current = sel:GetVerticalScroll()
        local target = min(max(current - delta * self.LINE * 2, 0), sel:GetVerticalScrollRange())
        if target == current then return (card.scrollPage or function(value) Dashboard:ScrollPage(value) end)(delta) end
        sel:SetVerticalScroll(target)
    end)
    scroll:SetScript("OnSizeChanged", function(sel, width) body:SetWidth(max(1, width or sel:GetWidth())) end)
    scroll:SetScript("OnScrollRangeChanged", function(sel) sel:SetVerticalScroll(min(sel:GetVerticalScroll(), sel:GetVerticalScrollRange())) end)
    card.scroll = scroll
    card.body = body
    card.lines = {}

    return card
end

function Dashboard:GetLine(card, index)
    local line = card.lines[index]
    if line then return line end
    line = CreateFrame("Button", nil, card.body)
    line:SetHeight(self.LINE)
    line:SetPoint("TOPLEFT", card.body, "TOPLEFT", 0, -(index - 1) * self.LINE)
    line:SetPoint("TOPRIGHT", card.body, "TOPRIGHT", 0, -(index - 1) * self.LINE)
    line.bg = Theme:Round(line, "rowHover", 5)
    line.bg:SetShown(false)
    line.dot = Theme:Icon(line, "circle", 6, "muted")
    line.dot:SetPoint("LEFT", line, "LEFT", 10, 0)
    line.left = Theme:Text(line, 12.5, "text")
    line.right = Theme:Text(line, 12, "muted")
    line.right:SetPoint("RIGHT", line, "RIGHT", -10, 0)
    line.right:SetJustifyH("RIGHT")
    line.left:SetPoint("RIGHT", line.right, "LEFT", -8, 0)
    line:SetScript("OnEnter", function(sel) sel.bg:SetShown(sel.member ~= nil) end)
    line:SetScript("OnLeave", function(sel) sel.bg:SetShown(false) end)
    line:SetScript("OnClick", function(sel) if sel.member then Members:Focus(sel.member) end end)
    card.lines[index] = line

    return line
end

function Dashboard:SetLine(card, index, left, right, member, header)
    local line = self:GetLine(card, index)
    line.member = member
    line.left:ClearAllPoints()
    line.left:SetPoint("LEFT", line, "LEFT", member and 24 or 10, 0)
    line.left:SetPoint("RIGHT", line.right, "LEFT", -8, 0)
    line.left:SetText(left)
    line.right:SetText(right or "")
    line.dot:SetShown(member ~= nil)
    if member then
        local r, g, b = Members:GetClassColor(member)
        line.dot:SetVertexColor(r, g, b)
        line.left:SetTextColor(r, g, b)
    else
        Theme:SetKey(line.left, header and "muted" or "text")
        line.left:SetTextColor(Theme:GetColor(header and "muted" or "text"))
    end

    line:Show()
end

function Dashboard:FinishList(card, count)
    for i = count + 1, #card.lines do
        card.lines[i].member = nil
        card.lines[i]:Hide()
    end

    card.body:SetHeight(max(1, count * self.LINE))
end

function Dashboard:ScrollPage(delta)
    local scroll = self.page
    if scroll == nil then return end
    scroll:SetVerticalScroll(min(max(scroll:GetVerticalScroll() - delta * 40, 0), scroll:GetVerticalScrollRange()))
    self:UpdatePageThumb()
end

function Dashboard:UpdatePageThumb()
    local scroll, thumb = self.page, self.pageThumb
    if scroll == nil or thumb == nil then return end
    local range = scroll:GetVerticalScrollRange()
    if range <= 0 then
        thumb:Hide()

        return
    end

    local track = scroll:GetHeight() - 12
    local height = max(24, track * scroll:GetHeight() / (scroll:GetHeight() + range))
    thumb:SetHeight(height)
    thumb:ClearAllPoints()
    thumb:SetPoint("TOPRIGHT", scroll, "TOPRIGHT", -9, -6 - (track - height) * scroll:GetVerticalScroll() / range)
    thumb:Show()
end

function Dashboard:CreatePage(content)
    local scroll = CreateFrame("ScrollFrame", nil, content)
    scroll:SetPoint("TOPLEFT", content, "TOPLEFT", 0, -self.SCROLLTOP)
    scroll:SetPoint("BOTTOMRIGHT", content, "BOTTOMRIGHT", 0, Members.BOTTOM - self.SCROLLPAD)
    local body = CreateFrame("Frame", nil, scroll)
    body:SetSize(1, 1)
    scroll:SetScrollChild(body)
    scroll:EnableMouseWheel(true)
    scroll:SetScript("OnMouseWheel", function(_, delta) Dashboard:ScrollPage(delta) end)
    scroll:SetScript("OnSizeChanged", function(sel, width, height)
        body:SetWidth(max(1, width or sel:GetWidth()))
        body:SetHeight(max(height or sel:GetHeight(), self.MOTDTOP - self.SCROLLTOP + self.MINLOWER + self.SCROLLPAD))
        Dashboard:UpdatePageThumb()
    end)

    scroll:SetScript("OnScrollRangeChanged", function(sel)
        sel:SetVerticalScroll(min(sel:GetVerticalScroll(), sel:GetVerticalScrollRange()))
        Dashboard:UpdatePageThumb()
    end)

    local thumb = CreateFrame("Frame", nil, content)
    thumb:SetWidth(4)
    thumb:SetFrameLevel(scroll:GetFrameLevel() + 20)
    Theme:Round(thumb, "thumb", 2)
    thumb:Hide()
    self.page = scroll
    self.pageThumb = thumb

    return body
end

function Dashboard:CreateMOTD(content)
    local card = self:CreateTextCard(content, "LID_MOTD")
    card:SetPoint("TOPLEFT", content, "TOPLEFT", Window.PADDING, -self.MOTDTOP + self.SCROLLTOP)
    card:SetHeight(102)
    card.hit = Members:CreateEditLink(card, card.title, card.title)

    self.motd = card
    self.information = self:CreateTextCard(content, "LID_GUILDINFORMATION")
    self.information:SetPoint("TOPLEFT", card, "TOPRIGHT", 12, 0)
    self.information:SetPoint("BOTTOMRIGHT", content, "TOPRIGHT", -Window.MARGIN, -self.MOTDTOP + self.SCROLLTOP - 102)
end

function Dashboard:CreateTextCard(parent, label)
    local card = self:CreateList(self:CreateCard(parent, label))
    card.text = Theme:Text(card.body, 13, "text")
    card.text:SetPoint("TOPLEFT", card.body, "TOPLEFT", 10, 0)
    card.text:SetWordWrap(true)
    card.text:SetJustifyV("TOP")
    card.ResizeText = function(sel)
        sel.text:SetWidth(max(1, sel.body:GetWidth() - 20))
        sel.body:SetHeight(max(1, sel.text:GetStringHeight() + 8))
    end

    card.body:SetScript("OnSizeChanged", function() card:ResizeText() end)

    return card
end

function Dashboard:CreateStats(content)
    local stats = CreateFrame("Frame", nil, content)
    stats:SetPoint("TOPLEFT", content, "TOPLEFT", Window.PADDING, -self.TOP + self.SCROLLTOP)
    stats:SetPoint("TOPRIGHT", content, "TOPRIGHT", -Window.MARGIN, -self.TOP + self.SCROLLTOP)
    stats:SetHeight(64)
    Theme:Panel(stats, "card", "border", 9)
    local fields = {
        {"online", "LID_ONLINENOW"},
        {"users", "LID_GUILDHELPERUSERS"},
        {"average", "LID_AVGILVLONLINE"},
        {"maxAverage", "LID_AVGILVLMAXLEVEL"},
    }
    for _, field in ipairs(fields) do
        local cell = CreateFrame("Frame", nil, stats)
        local label = Theme:Text(cell, 11, "muted")
        label:SetPoint("TOPLEFT", cell, "TOPLEFT", 14, -12)
        label:SetPoint("RIGHT", cell, "RIGHT", -8, 0)
        label:SetJustifyH("LEFT")
        label:SetWordWrap(false)
        Theme:SetTrans(label, field[2], true)
        local value = Theme:Text(cell, 22, "text")
        value:SetPoint("TOPLEFT", cell, "TOPLEFT", 14, -30)
        stats[field[1]] = cell
        cell.value = value
    end
    stats:SetScript("OnSizeChanged", function(_, width)
        local cellWidth = max(1, width / #fields)
        for index, field in ipairs(fields) do
            local cell = stats[field[1]]
            cell:ClearAllPoints()
            cell:SetPoint("TOPLEFT", stats, "TOPLEFT", (index - 1) * cellWidth, 0)
            cell:SetSize(cellWidth, 64)
        end
    end)
    stats:GetScript("OnSizeChanged")(stats, stats:GetWidth())
    self.stats = stats
end

function Dashboard:Build(content)
    self.content = content
    local title = Window:CreatePageTitle(content, "LID_DASHBOARD")
    self.guildName = Theme:Text(content, 13, "muted")
    self.guildName:SetPoint("BOTTOMLEFT", title, "BOTTOMRIGHT", 10, 1)
    local body = self:CreatePage(content)
    self:CreateMOTD(body)
    self:CreateStats(body)
    self.news = self:CreateTextCard(body, "LID_GUILDNEWS")
    self.newsFilterButton = Members:CreatePill(self.news, GuildHelper:Trans("LID_NEWSFILTERS"))
    self.newsFilterButton:SetPoint("TOPRIGHT", self.news, "TOPRIGHT", -10, -5)
    self.newsFilterButton:SetScript("OnClick", function() Dashboard:ToggleNewsFilters() end)
    self.newsFilterButton:SetEnabled(GetGuildNewsFilters ~= nil and SetGuildNewsFilter ~= nil)
    self.news.title:SetPoint("RIGHT", self.newsFilterButton, "LEFT", -8, 0)
    self.news:SetPoint("TOPLEFT", self.motd, "BOTTOMLEFT", 0, -12)
    self.news:SetPoint("RIGHT", self.motd, "RIGHT")
    self.news:SetHeight(110)
    self.professions = self:CreateList(self:CreateCard(body, "LID_GUILDPROFESSIONS"))
    self.professions:SetPoint("TOPLEFT", self.news, "TOPRIGHT", 12, 0)
    self.professions:SetPoint("RIGHT", self.stats, "RIGHT")
    self.professions:SetPoint("BOTTOM", self.news, "BOTTOM")
    self.chat = self:CreateChat(body)
    self.chat:SetPoint("TOPLEFT", self.news, "BOTTOMLEFT", 0, -12)
    self.chat:SetPoint("RIGHT", self.news, "RIGHT")
    self.chat:SetPoint("BOTTOM", body, "BOTTOM", 0, self.SCROLLPAD)
    self.zones = self:CreateList(self:CreateCard(body, "LID_WHOISWHERE"))
    self.zones:SetPoint("TOPLEFT", self.professions, "BOTTOMLEFT", 0, -12)
    self.zones:SetPoint("RIGHT", self.professions, "RIGHT")
    self.zones:SetPoint("BOTTOM", self.chat, "BOTTOM")
    content:SetScript("OnSizeChanged", function(_, width)
        local available = width - Window.PADDING - Window.MARGIN
        self.motd:SetWidth(max(1, (available - 12) / 2))
    end)

    content:GetScript("OnSizeChanged")(content, content:GetWidth())
    self.noGuild = Theme:Text(content, 14, "muted")
    self.noGuild:SetPoint("CENTER", content, "CENTER", 0, 0)
    Theme:SetTrans(self.noGuild, "LID_NOGUILD")
    content.OnPageShow = function()
        Dashboard:RequestData()
        Dashboard:Refresh()
    end
    content.OnPageHide = function()
        if Dashboard.newsFilters then Dashboard.newsFilters:Hide() end
    end
end

function Dashboard:Refresh()
    Members:Scan()
    self:Update()
end

function Dashboard:IsVisible()
    return self.content ~= nil and self.content:IsVisible()
end

function Dashboard:UpdateMOTD()
    local motd = self:GetMOTD()
    self.motd.text:SetText(motd ~= "" and motd or "–")
    Theme:SetKey(self.motd.text, motd ~= "" and "text" or "muted")
    self.motd.hit:Show()
    self.motd.hit.canEdit = self:CanEditMOTD()
    self.motd:ResizeText()
    local information = self:GetGuildInformation()
    self.information.text:SetText(information ~= "" and information or "–")
    Theme:SetKey(self.information.text, information ~= "" and "text" or "muted")
    self.information:ResizeText()
end

function Dashboard:UpdateStats()
    local total, online, users, onlineUsers, sum, count = #Members.list, 0, 0, 0, 0, 0
    local maxSum, maxCount = 0, 0
    local maxLevel = 60
    if not GuildHelper:IsForever() and GetMaxLevelForPlayerExpansion then
        maxLevel = GetMaxLevelForPlayerExpansion() or maxLevel
    end
    for _, member in ipairs(Members.list) do
        local data = Members:GetData(member)
        if data then users = users + 1 end
        if member.level == maxLevel and data and data.ilvl then
            maxSum = maxSum + data.ilvl
            maxCount = maxCount + 1
        end
        if member.online then
            online = online + 1
            if data then onlineUsers = onlineUsers + 1 end
            if data and data.ilvl then
                sum = sum + data.ilvl
                count = count + 1
            end
        end
    end

    local onlineColor = Theme:GetHex("online")
    self.stats.online.value:SetText(format("%s%d|r / %d", onlineColor, online, total))
    self.stats.users.value:SetText(format("%s%d|r / %d", onlineColor, onlineUsers, users))
    self.stats.average.value:SetText(count > 0 and format("%.1f", sum / count) or "–")
    self.stats.maxAverage.value:SetText(maxCount > 0 and format("%.1f", maxSum / maxCount) or "–")
end

function Dashboard:UpdateZones()
    local zones, order = {}, {}
    for _, member in ipairs(Members.list) do
        if member.online then
            local zone = member.zone ~= "" and member.zone or "?"
            if zones[zone] == nil then
                zones[zone] = {}
                tinsert(order, zone)
            end

            tinsert(zones[zone], member)
        end
    end

    table.sort(order, function(a, b)
        if #zones[a] ~= #zones[b] then return #zones[a] > #zones[b] end

        return a < b
    end)

    local index = 0
    for _, zone in ipairs(order) do
        index = index + 1
        self:SetLine(self.zones, index, strupper(zone), tostring(#zones[zone]), nil, true)
        table.sort(zones[zone], function(a, b) return a.key < b.key end)
        for _, member in ipairs(zones[zone]) do
            index = index + 1
            self:SetLine(self.zones, index, member.short, format("%d · %s", member.level, member.rank), member)
        end
    end

    self:FinishList(self.zones, index)
end

function Dashboard:UpdateProfessions()
    local counts, best, order, names = {}, {}, {}, {}
    local sync = GuildHelper.Sync
    for _, member in ipairs(Members.list) do
        local data = Members:GetData(member)
        local seen = {}
        for _, prof in ipairs(data and data.professions or {}) do
            local id = sync:GetProfessionID(prof[1], prof[4])
            local key = id or prof[1]
            if counts[key] == nil then
                counts[key] = 0
                best[key] = 0
                names[key] = sync:GetProfessionName(id, prof[1])
                tinsert(order, key)
            end

            if not seen[key] then
                seen[key] = true
                counts[key] = counts[key] + 1
            end

            best[key] = max(best[key], prof[2] or 0)
        end
    end

    table.sort(order, function(a, b)
        if counts[a] ~= counts[b] then return counts[a] > counts[b] end

        return names[a] < names[b]
    end)

    if #order == 0 then
        self:SetLine(self.professions, 1, GuildHelper:Trans("LID_NODATA"), nil, nil, true)
        self:FinishList(self.professions, 1)

        return
    end

    for i, key in ipairs(order) do
        self:SetLine(self.professions, i, format("%s |cff888888(%d)|r", names[key], best[key]), tostring(counts[key]))
    end

    self:FinishList(self.professions, #order)
end

function Dashboard:CreateChat(parent)
    local card = self:CreateCard(parent, "LID_CHAT")
    local messages = CreateFrame("ScrollingMessageFrame", nil, card)
    messages:SetPoint("TOPLEFT", card, "TOPLEFT", 16, -34)
    messages:SetPoint("BOTTOMRIGHT", card, "BOTTOMRIGHT", -16, 8)
    messages:SetMaxLines(self.CHATMAX)
    messages:SetFading(false)
    messages:SetJustifyH("LEFT")
    messages:SetHyperlinksEnabled(true)
    messages:SetScript("OnHyperlinkClick", function(_, link, text, button)
        SetItemRef(link, text, button, DEFAULT_CHAT_FRAME)
    end)
    Theme:Track(messages, "text", nil, 13)
    messages:EnableMouseWheel(true)
    messages:SetScript("OnMouseWheel", function(frame, delta)
        local atEdge = delta > 0 and frame:AtTop() or delta < 0 and frame:AtBottom()
        for _ = 1, 2 do
            if delta > 0 then frame:ScrollUp() else frame:ScrollDown() end
        end

        if delta > 0 and frame:AtTop() and self:RequestChatHistory() then return end
        if atEdge then self:ScrollPage(delta) end
    end)
    card.messages = messages

    return card
end

function Dashboard:ResetChatHistory()
    self.chatHistoryRequested = nil
    self.chatInitialRequested = nil
    self.chatHistoryLimit = self.CHATLIMIT
    self.chatOldest = nil
end

function Dashboard:RequestChatHistory()
    if not self.chatOldest or not self.chatClubID or not self.chatStreamID or not C_Club.RequestMoreMessagesBefore
        or self.chatHistoryLimit >= self.CHATMAX then return false end
    if C_ChatInfo and C_ChatInfo.InChatMessagingLockdown and C_ChatInfo.InChatMessagingLockdown() then return false end
    if C_Club.IsBeginningOfStream and C_Club.IsBeginningOfStream(self.chatClubID, self.chatStreamID, self.chatOldest) then return false end
    if self.chatHistoryRequested and GetTime() - self.chatHistoryRequested < 5 then return true end

    self.chatHistoryLimit = min(self.chatHistoryLimit + self.CHATLIMIT, self.CHATMAX)
    self.chatHistoryRequested = GetTime()
    if C_Club.RequestMoreMessagesBefore(self.chatClubID, self.chatStreamID, self.chatOldest, self.CHATLIMIT) then
        self.chatHistoryRequested = nil
    end

    self:UpdateChat()

    return true
end

function Dashboard:FormatChatLine(sender, text, classID, messageID)
    if not sender or sender == "" then return UNKNOWN .. ": " .. text end
    local name = sender:gsub("|", "||")
    local classInfo = classID and C_CreatureInfo and C_CreatureInfo.GetClassInfo and C_CreatureInfo.GetClassInfo(classID)
    local classFile = classInfo and classInfo.classFile
    if not classFile then
        for _, member in ipairs(Members.list) do
            if member.name == sender or member.short == sender then
                classFile = member.classFile
                break
            end
        end
    end

    local color = classFile and RAID_CLASS_COLORS and RAID_CLASS_COLORS[classFile]
    if color then name = format("|cff%02x%02x%02x%s|r", color.r * 255, color.g * 255, color.b * 255, name) end
    name = "[" .. name .. "]"
    if messageID and GetPlayerCommunityLink then
        name = GetPlayerCommunityLink(sender, name, self.chatClubID, self.chatStreamID, messageID.epoch, messageID.position)
    elseif GetPlayerLink then
        name = GetPlayerLink(sender, name)
    else
        name = format("|Hplayer:%s|h%s|h", sender, name)
    end

    return name .. ": " .. text
end

function Dashboard:GetChatHistory()
    if not C_Club or not C_Club.GetGuildClubId or not C_Club.GetStreams or not C_Club.GetMessageRanges
        or not C_Club.GetMessagesBefore or not Enum or not Enum.ClubStreamType then return end
    if C_ChatInfo and C_ChatInfo.InChatMessagingLockdown and C_ChatInfo.InChatMessagingLockdown() then return end

    local clubID = C_Club.GetGuildClubId()
    if not GuildHelper:CanAccessValues(clubID) or not clubID then return end
    local streams = C_Club.GetStreams(clubID)
    if not GuildHelper:CanAccessValues(streams) or not streams then return end

    local streamID
    for _, stream in ipairs(streams) do
        if stream.streamType == Enum.ClubStreamType.Guild then
            streamID = stream.streamId
            break
        end
    end

    if not streamID then return end
    if self.chatClubID ~= clubID or self.chatStreamID ~= streamID then
        self.chatClubID = clubID
        self.chatStreamID = streamID
        self:ResetChatHistory()
    end

    local ranges = C_Club.GetMessageRanges(clubID, streamID)
    if not GuildHelper:CanAccessValues(ranges) or not ranges then return end
    local range = ranges[#ranges]
    local messages, oldest
    if range then
        local first, last = range.oldestMessageId, range.newestMessageId
        if last.epoch > first.epoch or (last.epoch == first.epoch and last.position >= first.position) then
            messages = C_Club.GetMessagesBefore(clubID, streamID, last, self.chatHistoryLimit)
            if not GuildHelper:CanAccessValues(messages) then return end
            oldest = first
        end
    end

    if not self.chatInitialRequested and (not messages or #messages < self.CHATLIMIT) and C_Club.RequestMoreMessagesBefore then
        self.chatInitialRequested = true
        C_Club.RequestMoreMessagesBefore(clubID, streamID, oldest, self.CHATLIMIT)
    end

    if not messages then return end
    self.chatOldest = messages[1] and messages[1].messageId
    local lines = {}
    for _, message in ipairs(messages) do
        if not message.destroyed and message.content and message.author then
            local author = message.author
            if not author.name and author.memberId and C_Club.GetMemberInfo then
                author = C_Club.GetMemberInfo(clubID, author.memberId) or author
            end

            if GuildHelper:CanAccessValues(author.name, author.classID, message.content) then
                tinsert(lines, self:FormatChatLine(author.name, message.content, author.classID, message.messageId))
            end
        end
    end

    return lines
end

function Dashboard:UpdateChat()
    local card = self.chat
    local lines = self:GetChatHistory()
    if not lines then
        lines = {}
        for _, message in ipairs(self.chatMessages or {}) do
            tinsert(lines, self:FormatChatLine(message.sender, message.text))
        end
    end

    local text = table.concat(lines, "\n")
    local r, g, b = Theme:GetColor("text")
    local color = ChatTypeInfo and ChatTypeInfo.GUILD
    if color then r, g, b = color.r, color.g, color.b end
    if text == card.chatText and r == card.chatR and g == card.chatG and b == card.chatB then return end

    local frame = card.messages
    local offset = frame.GetScrollOffset and frame:GetScrollOffset() or 0
    frame:Clear()
    for _, line in ipairs(lines) do
        frame:AddMessage(line, r, g, b)
    end

    if offset > 0 and frame.SetScrollOffset then frame:SetScrollOffset(offset) end
    card.chatText, card.chatR, card.chatG, card.chatB = text, r, g, b
end

function Dashboard:Update()
    if not self:IsVisible() then return end
    local inGuild = IsInGuild()
    for _, region in ipairs({self.motd, self.information, self.news, self.stats, self.professions, self.zones, self.chat}) do
        region:SetShown(inGuild)
    end

    self.noGuild:SetShown(not inGuild)
    if self.newsFilterButton then Members:SetPillText(self.newsFilterButton, GuildHelper:Trans("LID_NEWSFILTERS")) end
    if not inGuild then
        self.guildName:SetText("")

        return
    end

    self.guildName:SetText(GetGuildInfo("player") or "")
    self:UpdateMOTD()
    self:UpdateNews()
    self:UpdateStats()
    self:UpdateZones()
    self:UpdateProfessions()
    self:UpdateChat()
end

function Dashboard:Reset()
    if self.newsFilters then self.newsFilters:Hide() end
    self.newsFilters = nil
    self.content = nil
    self.motd = nil
    self.information = nil
    self.news = nil
    self.chat = nil
    self.stats = nil
    self.zones = nil
    self.professions = nil
end

Window:OnRebuild(function() Dashboard:Reset() end)
Theme:OnRefresh(function() Dashboard:Update() end)
Dashboard.events = CreateFrame("Frame")
for _, event in ipairs({"PLAYER_LOGIN", "PLAYER_ENTERING_WORLD", "GUILD_ROSTER_UPDATE", "PLAYER_GUILD_UPDATE", "GUILD_MOTD", "CHAT_MSG_GUILD"}) do
    Dashboard.events:RegisterEvent(event)
end

if Dashboard:HasNews() then Dashboard.events:RegisterEvent("GUILD_NEWS_UPDATE") end
for _, event in ipairs({"CLUB_ADDED", "CLUB_UPDATED", "INITIAL_CLUBS_LOADED", "CLUB_STREAMS_LOADED",
    "CLUB_MESSAGE_ADDED", "CLUB_MESSAGE_UPDATED", "CLUB_MESSAGE_HISTORY_RECEIVED", "UPDATE_CHAT_COLOR"}) do
    if not C_EventUtils or not C_EventUtils.IsEventValid or C_EventUtils.IsEventValid(event) then Dashboard.events:RegisterEvent(event) end
end

Dashboard.events:SetScript("OnEvent", function(_, event, text, sender)
    if event == "CLUB_MESSAGE_ADDED" or event == "CLUB_MESSAGE_UPDATED" or event == "CLUB_MESSAGE_HISTORY_RECEIVED" then
        if GuildHelper:CanAccessValues(text, sender) and text == Dashboard.chatClubID and sender == Dashboard.chatStreamID then
            if event == "CLUB_MESSAGE_HISTORY_RECEIVED" then Dashboard.chatHistoryRequested = nil end
            if Dashboard:IsVisible() then Dashboard:UpdateChat() end
        end

        return
    end

    if event == "CHAT_MSG_GUILD" then
        if Dashboard:CheckGuild() and GuildHelper:CanAccessValues(text, sender) and text and sender then
            local messages = Dashboard.chatMessages
            if #messages >= Dashboard.CHATLIMIT then table.remove(messages, 1) end
            tinsert(messages, {sender = sender, text = text})
            if Dashboard:IsVisible() then Dashboard:UpdateChat() end
        end

        return
    end

    if event == "PLAYER_GUILD_UPDATE" and text and text ~= "player" then return end
    Dashboard:CheckGuild()
    if event == "GUILD_MOTD" and type(text) == "string" and GuildHelper:CanAccessValues(text) then Dashboard.cachedMOTD = text end
    if event == "PLAYER_LOGIN" or event == "PLAYER_ENTERING_WORLD" or event == "PLAYER_GUILD_UPDATE" or event == "INITIAL_CLUBS_LOADED" then
        Dashboard:RequestData()
        for _, delay in ipairs({5, 15, 30}) do
            C_Timer.After(delay, function()
                Dashboard:RequestData()
                Dashboard:Update()
            end)
        end
    end

    if not Dashboard:IsVisible() or Dashboard.updatePending then return end
    Dashboard.updatePending = true
    C_Timer.After(0.2, function()
        Dashboard.updatePending = nil
        Dashboard:Refresh()
        Dashboard:UpdateNewsFilters()
    end)
end)

Window:SetPageBuilder("dashboard", function(content) Dashboard:Build(content) end)
