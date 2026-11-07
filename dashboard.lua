local _, GuildHelper = ...
local Theme = GuildHelper.Theme
local Window = GuildHelper.Window
local Members = GuildHelper.Members
local Dashboard = {}
GuildHelper.Dashboard = Dashboard
Dashboard.SIDE = 260
Dashboard.LINE = 22
Dashboard.TOP = 70
Dashboard.STATSTOP = 186
Dashboard.LISTTOP = 266
Dashboard.SCROLLTOP = 66
Dashboard.SCROLLPAD = 4
Dashboard.MINLOWER = 278
function Dashboard:GetMOTD()
    if C_GuildInfo and C_GuildInfo.GetMOTD then return C_GuildInfo.GetMOTD() or "" end
    if GetGuildRosterMOTD then return GetGuildRosterMOTD() or "" end

    return ""
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
    Theme:SetTrans(card.title, label, true)

    return card
end

function Dashboard:CreateStat(parent, label)
    local stat = CreateFrame("Frame", nil, parent)
    stat:SetHeight(64)
    Theme:Panel(stat, "card", "border", 9)
    stat.label = Theme:Text(stat, 11, "muted")
    stat.label:SetPoint("TOPLEFT", stat, "TOPLEFT", 14, -12)
    Theme:SetTrans(stat.label, label, true)
    stat.value = Theme:Text(stat, 22, "text")
    stat.value:SetPoint("TOPLEFT", stat, "TOPLEFT", 14, -30)

    return stat
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
        if target == current then return Dashboard:ScrollPage(delta) end
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
        body:SetHeight(max(height or sel:GetHeight(), self.LISTTOP - self.SCROLLTOP + self.MINLOWER + self.SCROLLPAD))
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
    card:SetPoint("TOPLEFT", content, "TOPLEFT", Window.PADDING, -self.TOP + self.SCROLLTOP)
    card:SetHeight(102)
    card.hit = Members:CreateEditLink(card, card.title, card.title)

    self.motd = card
    self.information = self:CreateTextCard(content, "LID_GUILDINFORMATION")
    self.information:SetPoint("TOPLEFT", card, "TOPRIGHT", 12, 0)
    self.information:SetPoint("BOTTOMRIGHT", content, "TOPRIGHT", -Window.MARGIN, -self.TOP + self.SCROLLTOP - 102)
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
    stats:SetPoint("TOPLEFT", content, "TOPLEFT", Window.PADDING, -self.STATSTOP + self.SCROLLTOP)
    stats:SetPoint("TOPRIGHT", content, "TOPRIGHT", -Window.MARGIN, -self.STATSTOP + self.SCROLLTOP)
    stats:SetHeight(64)
    stats.items = {self:CreateStat(stats, "LID_ONLINENOW"), self:CreateStat(stats, "LID_GUILDHELPERUSERS"), self:CreateStat(stats, "LID_AVGILVLONLINE")}
    stats:SetScript("OnSizeChanged", function(sel, width)
        local size = ((width or sel:GetWidth()) - 24) / #sel.items
        for i, item in ipairs(sel.items) do
            item:ClearAllPoints()
            item:SetPoint("TOPLEFT", sel, "TOPLEFT", (i - 1) * (size + 12), 0)
            item:SetWidth(max(1, size))
        end
    end)

    stats:GetScript("OnSizeChanged")(stats, stats:GetWidth())
    self.stats = stats
end

function Dashboard:CreateMyCard(side)
    local card = self:CreateCard(side, "LID_MYGUILDCARD")
    card:SetPoint("TOPLEFT", side, "TOPLEFT", 0, 0)
    card:SetPoint("TOPRIGHT", side, "TOPRIGHT", 0, 0)
    card:SetHeight(176)
    card.rank = Theme:Text(card, 13, "text")
    card.rank:SetPoint("TOPLEFT", card, "TOPLEFT", 16, -34)
    card.rank:SetPoint("RIGHT", card, "RIGHT", -16, 0)
    card.noteHeader = Theme:Text(card, 11, "muted")
    card.noteHeader:SetPoint("TOPLEFT", card, "TOPLEFT", 16, -62)
    Theme:SetTrans(card.noteHeader, "LID_NOTE", true)
    card.noteText = Theme:Text(card, 12.5, "text")
    card.noteText:SetPoint("TOPLEFT", card.noteHeader, "BOTTOMLEFT", 0, -6)
    card.noteText:SetPoint("RIGHT", card, "RIGHT", -16, 0)
    card.officerHeader = Theme:Text(card, 11, "muted")
    card.officerHeader:SetPoint("TOPLEFT", card, "TOPLEFT", 16, -112)
    Theme:SetTrans(card.officerHeader, "LID_OFFICERNOTE", true)
    card.officerText = Theme:Text(card, 12.5, "text")
    card.officerText:SetPoint("TOPLEFT", card.officerHeader, "BOTTOMLEFT", 0, -6)
    card.officerText:SetPoint("RIGHT", card, "RIGHT", -16, 0)
    card.noteHit = Members:CreateEditLink(card, card.noteHeader, card.noteText)
    card.officerHit = Members:CreateEditLink(card, card.officerHeader, card.officerText)
    self.myCard = card
end

function Dashboard:Build(content)
    self.content = content
    local title = Window:CreatePageTitle(content, "LID_DASHBOARD")
    self.guildName = Theme:Text(content, 13, "muted")
    self.guildName:SetPoint("BOTTOMLEFT", title, "BOTTOMRIGHT", 10, 1)
    local body = self:CreatePage(content)
    local top = -self.LISTTOP + self.SCROLLTOP
    self:CreateMOTD(body)
    self:CreateStats(body)
    local side = CreateFrame("Frame", nil, body)
    side:SetPoint("TOPRIGHT", body, "TOPRIGHT", -Window.MARGIN, top)
    side:SetPoint("BOTTOMRIGHT", body, "BOTTOMRIGHT", -Window.MARGIN, self.SCROLLPAD)
    side:SetWidth(self.SIDE)
    self.side = side
    self:CreateMyCard(side)
    self.professions = self:CreateList(self:CreateCard(side, "LID_GUILDPROFESSIONS"))
    self.professions:SetPoint("TOPLEFT", self.myCard, "BOTTOMLEFT", 0, -12)
    self.professions:SetPoint("BOTTOMRIGHT", side, "BOTTOMRIGHT", 0, 0)
    self.zones = self:CreateList(self:CreateCard(body, "LID_WHOISWHERE"))
    self.news = self:CreateTextCard(body, "LID_GUILDNEWS")
    self.news:SetPoint("TOPLEFT", body, "TOPLEFT", Window.PADDING, top)
    self.news:SetPoint("BOTTOMLEFT", body, "BOTTOMLEFT", Window.PADDING, self.SCROLLPAD)
    self.zones:SetPoint("TOPLEFT", self.news, "TOPRIGHT", 12, 0)
    self.zones:SetPoint("BOTTOMRIGHT", side, "BOTTOMLEFT", -12, 0)
    content:SetScript("OnSizeChanged", function(_, width)
        local available = width - Window.PADDING - Window.MARGIN
        self.motd:SetWidth(max(1, (available - 12) / 2))
        self.news:SetWidth(max(1, (available - self.SIDE - 24) * 0.6))
    end)

    content:GetScript("OnSizeChanged")(content, content:GetWidth())
    self.noGuild = Theme:Text(content, 14, "muted")
    self.noGuild:SetPoint("CENTER", content, "CENTER", 0, 0)
    Theme:SetTrans(self.noGuild, "LID_NOGUILD")
    content.OnPageShow = function()
        Members:RequestRoster()
        Dashboard:Refresh()
        if IsInGuild() and Dashboard:HasNews() and QueryGuildNews then QueryGuildNews() end
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
    local total, online, users, sum, count = #Members.list, 0, 0, 0, 0
    for _, member in ipairs(Members.list) do
        local data = Members:GetData(member)
        if data then users = users + 1 end
        if member.online then
            online = online + 1
            if data and data.ilvl then
                sum = sum + data.ilvl
                count = count + 1
            end
        end
    end

    local items = self.stats.items
    items[1].value:SetText(format("%s%d|r / %d", Theme:GetHex("online"), online, total))
    items[2].value:SetText(format("%d / %d", users, total))
    items[3].value:SetText(count > 0 and format("%.1f", sum / count) or "–")
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
    local counts, best, order = {}, {}, {}
    for _, member in ipairs(Members.list) do
        local data = Members:GetData(member)
        for _, prof in ipairs(data and data.professions or {}) do
            local name = prof[1]
            if counts[name] == nil then
                counts[name] = 0
                best[name] = 0
                tinsert(order, name)
            end

            counts[name] = counts[name] + 1
            best[name] = max(best[name], prof[2] or 0)
        end
    end

    table.sort(order, function(a, b)
        if counts[a] ~= counts[b] then return counts[a] > counts[b] end

        return a < b
    end)

    if #order == 0 then
        self:SetLine(self.professions, 1, GuildHelper:Trans("LID_NODATA"), nil, nil, true)
        self:FinishList(self.professions, 1)

        return
    end

    for i, name in ipairs(order) do
        self:SetLine(self.professions, i, format("%s |cff888888(%d)|r", name, best[name]), tostring(counts[name]))
    end

    self:FinishList(self.professions, #order)
end

function Dashboard:UpdateMyCard()
    local card = self.myCard
    local member = Members:GetSelf()
    local viewOfficer = Members:CanViewOfficerNote()
    card.rank:SetText(member and format("%s: %s", GuildHelper:Trans("LID_RANK"), member.rank) or "")
    card.noteText:SetText(member and member.note ~= "" and member.note or "–")
    Theme:SetKey(card.noteText, member and member.note ~= "" and "text" or "muted")
    card.officerHeader:SetShown(viewOfficer)
    card.officerText:SetShown(viewOfficer)
    card.officerText:SetText(member and member.officerNote ~= "" and member.officerNote or "–")
    Theme:SetKey(card.officerText, member and member.officerNote ~= "" and "text" or "muted")
    Members:UpdateNoteEditor(card.noteHit, member, Members:CanEditPublicNote(member))
    Members:UpdateNoteEditor(card.officerHit, viewOfficer and member or nil, Members:CanEditOfficerNote())
end

function Dashboard:Update()
    if not self:IsVisible() then return end
    local inGuild = IsInGuild()
    for _, region in ipairs({self.motd, self.information, self.news, self.stats, self.side, self.zones}) do
        region:SetShown(inGuild)
    end

    self.noGuild:SetShown(not inGuild)
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
    self:UpdateMyCard()
end

function Dashboard:Reset()
    self.content = nil
    self.motd = nil
    self.information = nil
    self.news = nil
    self.stats = nil
    self.side = nil
    self.zones = nil
    self.professions = nil
    self.myCard = nil
end

Window:OnRebuild(function() Dashboard:Reset() end)
Theme:OnRefresh(function() Dashboard:Update() end)
Dashboard.events = CreateFrame("Frame")
for _, event in ipairs({"GUILD_ROSTER_UPDATE", "PLAYER_GUILD_UPDATE", "GUILD_MOTD"}) do
    Dashboard.events:RegisterEvent(event)
end

if Dashboard:HasNews() then Dashboard.events:RegisterEvent("GUILD_NEWS_UPDATE") end
Dashboard.events:SetScript("OnEvent", function(_, event)
    if not Dashboard:IsVisible() then return end
    if event == "GUILD_NEWS_UPDATE" then
        Dashboard:UpdateNews()
    elseif event == "GUILD_MOTD" then
        Dashboard:Update()
    else
        Dashboard:Refresh()
    end
end)

Window:SetPageBuilder("dashboard", function(content) Dashboard:Build(content) end)
