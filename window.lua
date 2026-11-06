local _, GuildHelper = ...
local Theme = GuildHelper.Theme
local Window = {}
GuildHelper.Window = Window
Window.WIDTH = 1040
Window.HEIGHT = 570
Window.SIDEBAR = 181
Window.PADDING = 18
Window.MARGIN = 24
Window.NAV = {
    {
        key = "members",
        label = "LID_MEMBERS"
    },
    {
        key = "professions",
        label = "LID_PROFESSIONS"
    },
    {
        key = "events",
        label = "LID_EVENTS"
    },
    {
        key = "groups",
        label = "LID_GROUPFINDER"
    },
    {
        key = "chars",
        label = "LID_MYCHARS"
    },
    {
        key = "log",
        label = "LID_GUILDLOG"
    },
    {
        key = "management",
        label = "LID_MANAGEMENT"
    },
}

Window.FLAVORS = {
    RETAIL = "Retail",
    CLASSIC = "Classic Era",
    TBC = "TBC Classic",
    WRATH = "Wrath Classic",
    CATA = "Cataclysm Classic",
    MISTS = "Mists of Pandaria Classic",
}

Window.builders = {}
Window.pageFrames = {}
Window.navButtons = {}
function Window:GetFlavorName()
    if GuildHelper:IsForever() then return "WoW Forever" end
    if GuildHelper:IsTitanReforged() then return "Titan Reforged" end

    return self.FLAVORS[GuildHelper:GetWoWBuild()] or ""
end

function Window:SetPageBuilder(key, builder)
    self.builders[key] = builder
end

function Window:CreatePageTitle(content, label)
    local title = Theme:Text(content, 20, "text")
    title:SetPoint("TOPLEFT", content, "TOPLEFT", self.PADDING, -29)
    title:SetText(GuildHelper:Trans(label))

    return title
end

function Window:BuildPlaceholder(content, entry)
    Window:CreatePageTitle(content, entry.label)
    local text = Theme:Text(content, 14, "muted")
    text:SetPoint("CENTER", content, "CENTER", 0, 0)
    text:SetText(GuildHelper:Trans("LID_COMINGSOON"))
end

function Window:UpdateNav()
    for _, button in ipairs(self.navButtons) do
        local active = button.entry.key == self.current
        local hovered = button:IsMouseOver()
        Theme:SetKey(button.bg, active and "navActive" or "hover")
        button.bg:SetShown(active or hovered)
        Theme:SetKey(button.dot, active and "accent" or "muted")
        Theme:SetKey(button.text, active and "accent" or "navText")
    end
end

function Window:CreateNavButton(index, entry)
    local frame = self.frame
    local button = CreateFrame("Button", nil, frame)
    button:SetSize(self.SIDEBAR - 30, 34)
    button:SetPoint("TOPLEFT", frame, "TOPLEFT", 18, -77 - (index - 1) * 38)
    button.entry = entry
    button.bg = Theme:Round(button, "navActive", 7)
    button.dot = Theme:Icon(button, "circle", 6, "muted")
    button.dot:SetPoint("LEFT", button, "LEFT", 11, 0)
    button.text = Theme:Text(button, 13.5, "navText")
    button.text:SetPoint("LEFT", button, "LEFT", 26, 0)
    button.text:SetText(GuildHelper:Trans(entry.label))
    button:SetScript("OnEnter", function() Window:UpdateNav() end)
    button:SetScript("OnLeave", function() Window:UpdateNav() end)
    button:SetScript("OnClick", function() Window:SelectPage(entry.key) end)
    tinsert(self.navButtons, button)
end

function Window:SelectPage(key)
    local entry = nil
    for _, nav in ipairs(self.NAV) do
        if nav.key == key then entry = nav end
    end

    entry = entry or self.NAV[1]
    self.current = entry.key
    GuildHelper:SetConfig("PAGE", entry.key)
    for pageKey, content in pairs(self.pageFrames) do
        content:SetShown(pageKey == entry.key)
    end

    local content = self.pageFrames[entry.key]
    if content == nil then
        content = CreateFrame("Frame", nil, self.frame)
        content:SetPoint("TOPLEFT", self.frame, "TOPLEFT", self.SIDEBAR + 1, 0)
        content:SetPoint("BOTTOMRIGHT", self.frame, "BOTTOMRIGHT", 0, 0)
        self.pageFrames[entry.key] = content
        local builder = self.builders[entry.key]
        if builder then
            builder(content, entry)
        else
            self:BuildPlaceholder(content, entry)
        end
    end

    content:Show()
    if content.OnPageShow then content:OnPageShow() end
    self:UpdateNav()
end

function Window:GetTabardInfo()
    if not IsInGuild() or C_GuildInfo == nil or C_GuildInfo.GetGuildTabardInfo == nil then return nil end
    local ok, info = pcall(C_GuildInfo.GetGuildTabardInfo, "player")
    if ok and type(info) == "table" and info.emblemFileID and info.backgroundColor and info.borderColor and info.emblemColor then return info end

    return nil
end

function Window:UpdateLogo()
    local logo = self.logo
    if logo == nil then return end
    local info = self:GetTabardInfo()
    if info == nil then
        logo.border:SetColor(Theme:GetColor("accent"))
        logo.fill:SetShown(false)
        logo.emblem:Hide()
        logo.shield:Show()

        return
    end

    logo.border:SetColor(info.borderColor:GetRGB())
    logo.fill:SetColor(info.backgroundColor:GetRGB())
    logo.fill:SetShown(true)
    if info.emblemStyle then
        local cell = 64 / 1024
        local x = mod(info.emblemStyle, 16) * cell
        local y = floor(info.emblemStyle / 16) * cell
        logo.emblem:SetTexture("Interface\\GuildFrame\\GuildEmblemsLG_01")
        logo.emblem:SetTexCoord(x, x + cell, y, y + cell)
    else
        logo.emblem:SetTexture(info.emblemFileID)
        logo.emblem:SetTexCoord(0, 1, 0, 1)
    end

    logo.emblem:SetVertexColor(info.emblemColor:GetRGB())
    logo.emblem:SetSize(22 * 7 / 8, 22)
    logo.emblem:Show()
    logo.shield:Hide()
end

function Window:CreateSidebar()
    local frame = self.frame
    local divider = Theme:Line(frame, "divider")
    divider:SetWidth(1)
    divider:SetPoint("TOPLEFT", frame, "TOPLEFT", self.SIDEBAR, -1)
    divider:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", self.SIDEBAR, 1)
    local logo = CreateFrame("Frame", nil, frame)
    logo:SetSize(30, 30)
    logo:SetPoint("TOPLEFT", frame, "TOPLEFT", 24, -25)
    logo.border = Theme:CreateShape(logo, 7, "BACKGROUND", 0)
    logo.fill = Theme:CreateShape(logo, 5, "BACKGROUND", 1, 2)
    logo.shield = Theme:Icon(logo, "shield", 18, "accentText")
    logo.shield:SetPoint("CENTER", logo, "CENTER", 0, 0)
    logo.emblem = logo:CreateTexture(nil, "ARTWORK")
    logo.emblem:SetPoint("CENTER", logo, "CENTER", 0, 0)
    self.logo = logo
    self:UpdateLogo()
    local title = Theme:Text(frame, 15, "text")
    title:SetPoint("TOPLEFT", logo, "TOPRIGHT", 10, -1)
    title:SetText(GuildHelper:Trans("LID_ADDONTITLE"))
    local flavor = Theme:Text(frame, 11, "muted")
    flavor:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -3)
    flavor:SetText(self:GetFlavorName())
    for index, entry in ipairs(self.NAV) do
        self:CreateNavButton(index, entry)
    end

    local footer = Theme:Text(frame, 10.5, "muted")
    footer:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", 26, 24)
    footer:SetWidth(self.SIDEBAR - 40)
    footer:SetWordWrap(true)
    footer:SetText(format("v%s", GuildHelper:GetVersion() or ""))
end

function Window:CreateCloseButton()
    local frame = self.frame
    local close = CreateFrame("Button", nil, frame)
    close:SetSize(31, 31)
    close:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -self.MARGIN, -24)
    close:SetFrameLevel(frame:GetFrameLevel() + 10)
    close.bg = Theme:Panel(close, "control", "border", 7)
    close.icon = Theme:Icon(close, "close", 10, "muted")
    close.icon:SetPoint("CENTER", close, "CENTER", 0, 0)
    close:SetScript("OnEnter", function(sel)
        Theme:SetKey(sel.bg, "hover")
        Theme:SetKey(sel.icon, "text")
    end)

    close:SetScript("OnLeave", function(sel)
        Theme:SetKey(sel.bg, "control")
        Theme:SetKey(sel.icon, "muted")
    end)

    close:SetScript("OnClick", function() frame:Hide() end)
end

function Window:Create()
    local frame = CreateFrame("Frame", "GuildHelperFrame", UIParent)
    frame:SetSize(self.WIDTH, self.HEIGHT)
    frame:SetPoint("CENTER")
    frame:SetFrameStrata("HIGH")
    frame:SetToplevel(true)
    frame:SetClampedToScreen(true)
    frame:SetMovable(true)
    frame:EnableMouse(true)
    frame:RegisterForDrag("LeftButton")
    frame:SetScript("OnDragStart", frame.StartMoving)
    frame:SetScript("OnDragStop", frame.StopMovingOrSizing)
    frame:Hide()
    tinsert(UISpecialFrames, "GuildHelperFrame")
    self.frame = frame
    Theme:Panel(frame, "window", "border", 10)
    self:CreateSidebar()
    self:CreateCloseButton()
    frame:SetScript("OnShow", function()
        Window:UpdateLogo()
        Window:SelectPage(Window.current or GuildHelper:GetConfig("PAGE", "members"))
    end)

    Theme:OnRefresh(function() Window:UpdateLogo() end)
    local events = CreateFrame("Frame")
    for _, event in ipairs({"PLAYER_GUILD_UPDATE", "GUILDTABARD_UPDATE"}) do
        pcall(events.RegisterEvent, events, event)
    end

    events:SetScript("OnEvent", function() Window:UpdateLogo() end)

    frame:SetScript("OnHide", function()
        for _, content in pairs(Window.pageFrames) do
            if content.OnPageHide then content:OnPageHide() end
        end
    end)
end

function Window:Toggle()
    if self.frame == nil then return end
    self.frame:SetShown(not self.frame:IsShown())
end
