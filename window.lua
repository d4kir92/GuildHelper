local _, GuildHelper = ...
local Theme = GuildHelper.Theme
local Window = {}
GuildHelper.Window = Window
Window.WIDTH = 1200
Window.HEIGHT = 570
Window.MINWIDTH = 1060
Window.MINHEIGHT = 480
Window.MINSCALE = 0.5
Window.MAXSCALE = 2
Window.TEMPLATES = {"ButtonFrameTemplate", "PortraitFrameTemplate", "BasicFrameTemplateWithInset"}
Window.FLIPCORNERS = {
    {"TopLeftCorner", "UI-Frame-Metal-CornerBottomLeft", "TOPLEFT", -8, 3, "BottomLeftCorner"},
    {"TopRightCorner", "UI-Frame-Metal-CornerBottomRight", "TOPRIGHT", 4, 3, "BottomRightCorner"}
}

Window.FLIPEDGE = "_UI-Frame-Metal-EdgeBottom"
Window.FLIPSHADOW = 5
Window.BGINSET = 6
function Window:GetAtlas(name)
    local info = C_Texture and C_Texture.GetAtlasInfo and C_Texture.GetAtlasInfo(name)
    if info == nil or info.file == nil and info.filename == nil or not info.width or info.width <= 0 then return nil end

    return info
end

function Window:GetFlipCrop(info)
    return min(self.FLIPSHADOW, info.height - 1)
end

function Window:SetFlipped(texture, info, width)
    local crop = self:GetFlipCrop(info)
    local right = info.leftTexCoord + (info.rightTexCoord - info.leftTexCoord) * (width or info.width) / info.width
    local bottom = info.bottomTexCoord - (info.bottomTexCoord - info.topTexCoord) * crop / info.height
    texture:SetTexture(info.file or info.filename)
    texture:SetTexCoord(info.leftTexCoord, right, bottom, info.topTexCoord)
    texture:SetSize(width or info.width, info.height - crop)
end

function Window:FlipTopBorder(frame)
    local slice = frame.NineSlice
    if slice == nil or slice.TopEdge == nil or C_Texture == nil then return end
    local edge = self:GetAtlas(self.FLIPEDGE)
    if edge == nil then return end
    for _, entry in ipairs(self.FLIPCORNERS) do
        if slice[entry[1]] == nil or self:GetAtlas(entry[2]) == nil then return end
    end

    for _, entry in ipairs(self.FLIPCORNERS) do
        local corner = slice[entry[1]]
        local x, y = entry[4], entry[5]
        local source = slice[entry[6]]
        if source and source:GetNumPoints() > 0 then
            local _, _, _, sourceX, sourceY = source:GetPoint(1)
            if sourceX then x = sourceX end
            if sourceY then y = -sourceY end
        end

        local info = self:GetAtlas(entry[2])
        corner:ClearAllPoints()
        corner:SetPoint(entry[3], slice, entry[3], x, y - self:GetFlipCrop(info))
        self:SetFlipped(corner, info)
    end

    slice.TopEdge:Hide()
    slice.ghEdges = {}
    local function layout()
        local left, right = slice.TopLeftCorner:GetRight(), slice.TopRightCorner:GetLeft()
        if not left or not right then return end
        local scale = slice.TopLeftCorner:GetEffectiveScale() / slice:GetEffectiveScale()
        local total = max(0, (right - left) * scale)
        local count = ceil(total / edge.width)
        for index = 1, count do
            local piece = slice.ghEdges[index]
            if piece == nil then
                piece = slice:CreateTexture(nil, "OVERLAY")
                slice.ghEdges[index] = piece
            end

            local offset = (index - 1) * edge.width
            piece:ClearAllPoints()
            piece:SetPoint("TOPLEFT", slice.TopLeftCorner, "TOPRIGHT", offset, 0)
            self:SetFlipped(piece, edge, min(edge.width, total - offset))
            piece:Show()
        end

        for index = count + 1, #slice.ghEdges do
            slice.ghEdges[index]:Hide()
        end
    end

    frame:HookScript("OnSizeChanged", layout)
    frame:HookScript("OnShow", layout)
    C_Timer.After(0, layout)
end
Window.SIDEBAR = 181
Window.PADDING = 18
Window.MARGIN = 24
Window.NAV = {
    {
        key = "dashboard",
        label = "LID_DASHBOARD"
    },
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
    {
        key = "settings",
        label = "LID_SETTINGS"
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
    Theme:SetTrans(title, label)

    return title
end

function Window:BuildPlaceholder(content, entry)
    Window:CreatePageTitle(content, entry.label)
    local text = Theme:Text(content, 14, "muted")
    text:SetPoint("TOPLEFT", content, "TOPLEFT", self.PADDING, -76)
    Theme:SetTrans(text, "LID_COMINGSOON")
    local description = Theme:Text(content, 14, "text")
    description:SetPoint("TOPLEFT", text, "BOTTOMLEFT", 0, -18)
    description:SetPoint("RIGHT", content, "RIGHT", -self.PADDING, 0)
    description:SetJustifyH("LEFT")
    description:SetWordWrap(true)
    Theme:SetTrans(description, "LID_PLANNED_" .. string.upper(entry.key))
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
    Theme:SetTrans(button.text, entry.label)
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

    self.inGuild = IsInGuild() and true or false
    local blocked = not self.inGuild and not self.GUILDFREE[entry.key]
    content:SetShown(not blocked)
    if blocked and self.noGuild == nil then self:CreateNoGuild() end
    if self.noGuild then
        self.noGuild:SetShown(blocked)
        Theme:SetTrans(self.noGuild.title, entry.label)
    end

    if not blocked and content.OnPageShow then content:OnPageShow() end
    self:UpdateNav()
end

Window.GUILDFREE = {
    settings = true
}

function Window:CreateNoGuild()
    local view = CreateFrame("Frame", nil, self.frame)
    view:SetPoint("TOPLEFT", self.frame, "TOPLEFT", self.SIDEBAR + 1, 0)
    view:SetPoint("BOTTOMRIGHT", self.frame, "BOTTOMRIGHT", 0, 0)
    view.title = self:CreatePageTitle(view, "LID_DASHBOARD")
    local box = CreateFrame("Frame", nil, view)
    box:SetSize(440, 230)
    box:SetPoint("CENTER", view, "CENTER", 0, 10)
    local icon = Theme:Icon(box, "shield", 40, "accent")
    icon:SetPoint("TOP", box, "TOP", 0, 0)
    local heading = Theme:Text(box, 18, "text")
    heading:SetPoint("TOP", icon, "BOTTOM", 0, -14)
    Theme:SetTrans(heading, "LID_NOGUILD")
    local hint = Theme:Text(box, 13.5, "muted")
    hint:SetPoint("TOP", heading, "BOTTOM", 0, -10)
    hint:SetWidth(440)
    hint:SetJustifyH("CENTER")
    hint:SetWordWrap(true)
    Theme:SetTrans(hint, "LID_NOGUILDHINT")
    local find = GuildHelper.Members:CreateButton(box, "LID_FINDGUILD", true)
    find:SetWidth(170)
    find:SetPoint("TOP", hint, "BOTTOM", 0, -20)
    find:SetScript("OnEnter", function(sel) Window:ShowGuildOverlay(sel, "LID_FINDGUILDTIP") end)
    find:SetScript("OnClick", function()
        if InCombatLockdown() and UIErrorsFrame and ERR_NOT_IN_COMBAT then UIErrorsFrame:AddMessage(ERR_NOT_IN_COMBAT, 1, 0.1, 0.1) end
    end)

    find:SetShown(self:GetGuildButton() ~= nil)
    view:Hide()
    self.noGuild = view
end

function Window:UpdateGuildState()
    local inGuild = IsInGuild() and true or false
    if inGuild == self.inGuild then return end
    self.inGuild = inGuild
    if self.frame and self.frame:IsShown() and self.current then self:SelectPage(self.current) end
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
    title:SetWidth(self.SIDEBAR - 76)
    self.guildTitle = title
    local flavor = Theme:Text(frame, 11, "muted")
    flavor:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -3)
    self.statusLine = flavor
    self:UpdateGuildName()
    for index, entry in ipairs(self.NAV) do
        self:CreateNavButton(index, entry)
    end

    local footer = Theme:Text(frame, 10.5, "muted")
    footer:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", 26, 24)
    footer:SetWidth(self.SIDEBAR - 40)
    footer:SetWordWrap(true)
    footer:SetText(format("GuildHelper v%s", GuildHelper:GetVersion() or ""))
end

function Window:CreateCloseButton()
    local frame = self.frame
    if frame.CloseButton then
        frame.CloseButton:SetScript("OnClick", function() frame:Hide() end)

        return
    end

    if Theme:IsNative() then
        local native = CreateFrame("Button", nil, frame, "UIPanelCloseButton")
        native:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -4, -4)
        native:SetFrameLevel(frame:GetFrameLevel() + 10)
        native:SetScript("OnClick", function() frame:Hide() end)

        return
    end

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

function Window:CreateStyledFrame(name, parent)
    if Theme:IsNative() and DoesTemplateExist then
        for _, template in ipairs(self.TEMPLATES) do
            if DoesTemplateExist(template) then
                local frame = CreateFrame("Frame", name, parent, template)
                frame.ghTemplate = template

                return frame
            end
        end
    end

    return CreateFrame("Frame", name, parent)
end

function Window:CreateMainFrame()
    return self:CreateStyledFrame("GuildHelperFrame", UIParent)
end

function Window:SetupMainFrame(frame)
    if frame.ghTemplate == nil then
        Theme:Panel(frame, "window", "border", 10)

        return
    end

    if frame.ghTemplate == "ButtonFrameTemplate" and ButtonFrameTemplate_HidePortrait then ButtonFrameTemplate_HidePortrait(frame) end
    for _, key in ipairs({"Inset", "InsetBg", "PortraitContainer", "portrait", "TitleBg", "TitleContainer", "TitleText", "TopTileStreaks"}) do
        if frame[key] and frame[key].Hide then frame[key]:Hide() end
    end

    self:FlipTopBorder(frame)

    if frame.CloseButton then
        frame.CloseButton:ClearAllPoints()
        local slice = frame.NineSlice
        if slice and slice.ghEdges and slice.TopRightCorner then
            frame.CloseButton:SetPoint("TOPRIGHT", slice.TopRightCorner, "TOPRIGHT", -7, self.FLIPSHADOW - 11)
        else
            frame.CloseButton:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -3, -8)
        end
        frame.CloseButton:SetFrameLevel(max(frame:GetFrameLevel(), frame.NineSlice and frame.NineSlice:GetFrameLevel() or 0) + 10)
    end

    if frame.Bg then
        frame.Bg:ClearAllPoints()
        frame.Bg:SetPoint("TOPLEFT", frame, "TOPLEFT", self.BGINSET, -3)
        frame.Bg:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -2, 2)
    end
end

Window.GUILDBUTTONS = {"GuildMicroButton", "SocialsMicroButton", "FriendsMicroButton"}
function Window:GetGuildButton()
    for _, name in ipairs(self.GUILDBUTTONS) do
        if _G[name] then return _G[name] end
    end

    return nil
end

function Window:HideGuildOverlay()
    local overlay = self.guildOverlay
    if overlay == nil or InCombatLockdown() then return end
    overlay:Hide()
    GameTooltip:Hide()
end

function Window:GetGuildOverlay()
    if self.guildOverlay then return self.guildOverlay end
    local target = self:GetGuildButton()
    if target == nil or InCombatLockdown() then return nil end
    local overlay = CreateFrame("Button", "GuildHelperGuildOverlay", UIParent, "SecureActionButtonTemplate")
    overlay:SetFrameStrata("DIALOG")
    overlay:RegisterForClicks("AnyUp", "AnyDown")
    overlay:SetAttribute("type", "click")
    overlay:SetAttribute("clickbutton", target)
    overlay.bg = overlay:CreateTexture(nil, "BACKGROUND")
    overlay.bg:SetAllPoints(overlay)
    overlay.bg:SetColorTexture(1, 1, 1, 0.06)
    overlay:SetScript("OnLeave", function() Window:HideGuildOverlay() end)
    overlay:SetScript("PostClick", function(_, _, down)
        if down then return end
        Window:HideGuildOverlay()
        if Window.frame then Window.frame:Hide() end
    end)

    overlay:Hide()
    self.overlayEvents = CreateFrame("Frame")
    self.overlayEvents:RegisterEvent("PLAYER_REGEN_DISABLED")
    self.overlayEvents:SetScript("OnEvent", function() overlay:Hide() end)
    self.guildOverlay = overlay

    return overlay
end

function Window:ShowGuildOverlay(region, tooltip)
    if InCombatLockdown() then return false end
    local overlay = self:GetGuildOverlay()
    local left, top = region:GetLeft(), region:GetTop()
    if overlay == nil or left == nil or top == nil then return false end
    local scale = region:GetEffectiveScale() / UIParent:GetEffectiveScale()
    overlay:ClearAllPoints()
    overlay:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", left * scale, top * scale)
    overlay:SetSize(region:GetWidth() * scale, region:GetHeight() * scale)
    overlay:Show()
    GameTooltip:SetOwner(overlay, "ANCHOR_RIGHT")
    GameTooltip:AddLine(GuildHelper:Trans(tooltip or "LID_EDITINBLIZZARD"), 1, 1, 1, true)
    GameTooltip:Show()

    return true
end

function Window:GetOnlineCount()
    local total, online = GetNumGuildMembers()
    total = total or 0
    if online == nil then
        online = 0
        for index = 1, total do
            if select(9, GetGuildRosterInfo(index)) then online = online + 1 end
        end
    end

    return online, total
end

function Window:UpdateGuildName()
    if self.guildTitle == nil or self.statusLine == nil then return end
    local name = IsInGuild() and GetGuildInfo("player")
    if name and name ~= "" then
        self.guildTitle.ghTrans = nil
        self.guildTitle:SetText(name)
        local online, total = self:GetOnlineCount()
        self.statusLine:SetText(GuildHelper:Trans("LID_ONLINECOUNT", nil, Theme:GetHex("online") .. online .. "|r", total))
    else
        Theme:SetTrans(self.guildTitle, "LID_ADDONTITLE")
        self.statusLine:SetText(self:GetFlavorName())
    end
end

function Window:AnchorTopLeft()
    local frame = self.frame
    local left, top = frame:GetLeft(), frame:GetTop()
    if left == nil or top == nil then return end
    frame:ClearAllPoints()
    frame:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", left, top)
end

function Window:SetScaleKeepPosition(scale)
    local frame = self.frame
    local effective = frame:GetEffectiveScale()
    local left, top = frame:GetLeft(), frame:GetTop()
    frame:SetScale(min(max(scale, self.MINSCALE), self.MAXSCALE))
    if left == nil or top == nil then return end
    effective = effective / frame:GetEffectiveScale()
    frame:ClearAllPoints()
    frame:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", left * effective, top * effective)
end

function Window:ApplySize()
    local frame = self.frame
    frame:SetSize(max(self.MINWIDTH, GuildHelper:GetConfig("WIDTH", self.WIDTH)), max(self.MINHEIGHT, GuildHelper:GetConfig("HEIGHT", self.HEIGHT)))
    self:SetScaleKeepPosition(GuildHelper:GetConfig("SCALE", 1))
end

function Window:ResetSize()
    GuildHelper:SetConfig("WIDTH", self.WIDTH)
    GuildHelper:SetConfig("HEIGHT", self.HEIGHT)
    GuildHelper:SetConfig("SCALE", 1)
    self:ApplySize()
end

function Window:StartScaling(grip)
    local frame = self.frame
    local startScale = frame:GetScale()
    local startX = GetCursorPosition()
    local width = frame:GetWidth() * frame:GetEffectiveScale()
    grip.mode = "scale"
    grip:SetScript("OnUpdate", function(sel)
        if IsMouseButtonDown and not IsMouseButtonDown("LeftButton") then return Window:StopResize(sel) end
        local x = GetCursorPosition()
        Window:SetScaleKeepPosition(startScale * (width + x - startX) / width)
    end)
end

function Window:StartResizing(grip)
    local frame = self.frame
    local scale = frame:GetEffectiveScale()
    local startX, startY = GetCursorPosition()
    local startWidth, startHeight = frame:GetWidth(), frame:GetHeight()
    local maxWidth = max(self.MINWIDTH, (UIParent:GetRight() or 0) * UIParent:GetEffectiveScale() / scale - (frame:GetLeft() or 0))
    local maxHeight = max(self.MINHEIGHT, frame:GetTop() or 0)
    grip.mode = "size"
    grip:SetScript("OnUpdate", function(sel)
        if IsMouseButtonDown and not IsMouseButtonDown("LeftButton") then return Window:StopResize(sel) end
        local x, y = GetCursorPosition()
        local width = min(max(startWidth + (x - startX) / scale, Window.MINWIDTH), maxWidth)
        local height = min(max(startHeight + (startY - y) / scale, Window.MINHEIGHT), maxHeight)
        frame:SetSize(width, height)
    end)
end

function Window:StopResize(grip)
    local frame = self.frame
    if grip.mode == nil then return end
    grip:SetScript("OnUpdate", nil)
    if grip.mode == "size" then
        GuildHelper:SetConfig("WIDTH", floor(frame:GetWidth() + 0.5))
        GuildHelper:SetConfig("HEIGHT", floor(frame:GetHeight() + 0.5))
    else
        GuildHelper:SetConfig("SCALE", floor(frame:GetScale() * 100 + 0.5) / 100)
    end

    grip.mode = nil
end

function Window:ShowGripTooltip(grip)
    local normal, highlight = NORMAL_FONT_COLOR, HIGHLIGHT_FONT_COLOR
    GameTooltip:SetOwner(grip, "ANCHOR_RIGHT")
    GameTooltip:AddDoubleLine(GuildHelper:Trans("LID_LEFTCLICK"), GuildHelper:Trans("LID_RESIZEWINDOW"), normal.r, normal.g, normal.b, highlight.r, highlight.g, highlight.b)
    GameTooltip:AddDoubleLine(GuildHelper:Trans("LID_SHIFTLEFTCLICK"), GuildHelper:Trans("LID_SCALE"), normal.r, normal.g, normal.b, highlight.r, highlight.g, highlight.b)
    GameTooltip:AddDoubleLine(GuildHelper:Trans("LID_RIGHTCLICK"), GuildHelper:Trans("LID_RESETSIZESCALE"), normal.r, normal.g, normal.b, highlight.r, highlight.g, highlight.b)
    GameTooltip:Show()
end

function Window:CreateResizeGrip()
    local frame = self.frame
    local grip = CreateFrame("Button", nil, frame)
    grip:SetSize(16, 16)
    grip:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -5, 5)
    grip:SetFrameLevel(frame:GetFrameLevel() + 20)
    grip:SetNormalTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Up")
    grip:SetHighlightTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Highlight")
    grip:SetPushedTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Down")
    grip:RegisterForClicks("RightButtonUp")
    grip:RegisterForDrag("LeftButton")
    grip:SetScript("OnDragStart", function() end)
    grip:SetScript("OnDragStop", function(sel) Window:StopResize(sel) end)
    grip:SetScript("OnMouseDown", function(sel, button)
        if button ~= "LeftButton" then return end
        GameTooltip:Hide()
        Window:AnchorTopLeft()
        if IsShiftKeyDown() then
            Window:StartScaling(sel)
        else
            Window:StartResizing(sel)
        end
    end)

    grip:SetScript("OnMouseUp", function(sel, button) if button == "LeftButton" then Window:StopResize(sel) end end)
    grip:SetScript("OnHide", function(sel) Window:StopResize(sel) end)
    grip:SetScript("OnClick", function() Window:ResetSize() end)
    grip:SetScript("OnEnter", function(sel) Window:ShowGripTooltip(sel) end)
    grip:SetScript("OnLeave", function() GameTooltip:Hide() end)
    self.grip = grip
end

function Window:Create()
    local frame = self:CreateMainFrame()
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
    if self.events == nil then tinsert(UISpecialFrames, "GuildHelperFrame") end
    self.frame = frame
    self:SetupMainFrame(frame)
    self:CreateSidebar()
    self:CreateCloseButton()
    self:CreateResizeGrip()
    self:ApplySize()
    frame:SetScript("OnShow", function()
        Window:UpdateLogo()
        Window:UpdateGuildName()
        Window:SelectPage(Window.current or GuildHelper:GetConfig("PAGE", "dashboard"))
        if GuildHelper.Settings then GuildHelper.Settings:ShowSetup() end
    end)

    frame:SetScript("OnHide", function()
        Window:HideGuildOverlay()
        for _, content in pairs(Window.pageFrames) do
            if content.OnPageHide then content:OnPageHide() end
        end
    end)

    if self.events then return end
    Theme:OnRefresh(function()
        Window:UpdateLogo()
        Window:UpdateGuildName()
    end)

    self.events = CreateFrame("Frame")
    for _, event in ipairs({"PLAYER_GUILD_UPDATE", "GUILDTABARD_UPDATE", "GUILD_ROSTER_UPDATE"}) do
        pcall(self.events.RegisterEvent, self.events, event)
    end

    self.events:SetScript("OnEvent", function(_, event)
        if event ~= "GUILD_ROSTER_UPDATE" then Window:UpdateLogo() end
        Window:UpdateGuildName()
        Window:UpdateGuildState()
    end)
end

Window.rebuildCallbacks = {}
function Window:OnRebuild(callback)
    tinsert(self.rebuildCallbacks, callback)
end

function Window:Rebuild()
    local old = self.frame
    local shown = old:IsShown()
    local scale = old:GetEffectiveScale()
    local left, top = old:GetLeft(), old:GetTop()
    old:Hide()
    old:SetScript("OnShow", nil)
    old:SetScript("OnHide", nil)
    wipe(self.pageFrames)
    wipe(self.navButtons)
    self.noGuild = nil
    for _, callback in ipairs(self.rebuildCallbacks) do
        callback()
    end

    Theme:Reset()
    self:Create()
    if left and top then
        local frame = self.frame
        scale = scale / frame:GetEffectiveScale()
        frame:ClearAllPoints()
        frame:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", left * scale, top * scale)
    end

    if shown then self.frame:Show() end
end

function Window:Toggle()
    if self.frame == nil then return end
    self.frame:SetShown(not self.frame:IsShown())
end
