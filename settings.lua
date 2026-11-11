local _, GuildHelper = ...
local Theme = GuildHelper.Theme
local Window = GuildHelper.Window
local Members = GuildHelper.Members
local Settings = {}
GuildHelper.Settings = Settings
Settings.WIDTH = 480
Settings.PILLWIDTH = 180
function Settings:GetLanguageOptions()
    local options = {
        {
            value = "auto",
            label = GuildHelper:Trans("LID_LANGAUTO")
        }
    }

    for _, lang in ipairs(GuildHelper.LANGUAGES) do
        tinsert(options, {
            value = lang,
            label = GuildHelper:Trans("LID_LANG" .. strupper(lang))
        })
    end

    return options
end

function Settings:GetDesignOptions()
    local options = {}
    for _, key in ipairs(Theme.ORDER) do
        tinsert(options, {
            value = key,
            label = GuildHelper:Trans(Theme.DESIGNS[key].label)
        })
    end

    return options
end

function Settings:CreateRow(parent, y, label, desc)
    local pill = Members:CreatePill(parent, "")
    pill:SetPoint("TOPRIGHT", parent, "TOPRIGHT", -18, y - 4)
    local title = Theme:Text(parent, 14, "text")
    title:SetPoint("TOPLEFT", parent, "TOPLEFT", 18, y)
    title:SetPoint("RIGHT", pill, "LEFT", -12, 0)
    Theme:SetTrans(title, label)
    local sub = Theme:Text(parent, 12, "muted")
    sub:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -5)
    sub:SetPoint("RIGHT", pill, "LEFT", -12, 0)
    Theme:SetTrans(sub, desc)

    return pill
end

function Settings:SetPill(pill, label, minWidth)
    Members:SetPillText(pill, label)
    pill:SetWidth(max(minWidth or self.PILLWIDTH, pill:GetWidth()))
end

function Settings:CreateCheck(parent)
    if Theme:IsNative() then
        local native = CreateFrame("CheckButton", nil, parent, "UICheckButtonTemplate")
        native:SetSize(26, 26)

        return native
    end

    local check = CreateFrame("Button", nil, parent)
    check:SetSize(20, 20)
    check.fill, check.border = Theme:Panel(check, "control", "border", 5)
    check.mark = CreateFrame("Frame", nil, check)
    check.mark:SetPoint("TOPLEFT", check, "TOPLEFT", 5, -5)
    check.mark:SetPoint("BOTTOMRIGHT", check, "BOTTOMRIGHT", -5, 5)
    Theme:Round(check.mark, "accent", 3)
    check.SetChecked = function(sel, value)
        sel.checked = value == true
        sel.mark:SetShown(sel.checked)
        Theme:SetKey(sel.border, sel.checked and "accent" or "border")
    end

    check.GetChecked = function(sel) return sel.checked == true end

    return check
end

function Settings:CreateSpecRow(parent, y, slot)
    local Specs = GuildHelper.Specs
    local spec = Members:CreatePill(parent, "")
    spec:SetPoint("TOPRIGHT", parent, "TOPRIGHT", -18, y)
    local role = Members:CreatePill(parent, "")
    role:SetPoint("TOPRIGHT", spec, "TOPLEFT", -8, 0)
    local title = Theme:Text(parent, 14, "text")
    title:SetPoint("LEFT", parent, "TOPLEFT", 18, y - 14)
    title:SetPoint("RIGHT", role, "LEFT", -12, 0)
    Theme:SetTrans(title, Specs.SLOTS[slot])
    role:SetScript("OnClick", function(sel)
        Members:OpenMenu(sel, Specs:GetRoleOptions(), Specs:GetOwn()[slot].role, function(value)
            Specs:SetOwn(slot, "role", value)
            Settings:Update()
        end)
    end)

    spec:SetScript("OnClick", function(sel)
        Members:OpenMenu(sel, Specs:GetSpecOptions(), Specs:GetOwn()[slot].spec, function(value)
            Specs:SetOwnSpec(slot, value)
            Settings:Update()
        end)
    end)

    return {
        role = role,
        spec = spec
    }
end

function Settings:CreateCharacterPanel(content)
    local panel = CreateFrame("Frame", nil, content)
    panel:SetPoint("TOPLEFT", content, "TOPLEFT", Window.PADDING, -76)
    panel:SetSize(self.WIDTH, 236)
    Theme:Panel(panel, "panel", "border", 9)
    local header = Theme:Text(panel, 11, "muted")
    header:SetPoint("TOPLEFT", panel, "TOPLEFT", 18, -16)
    Theme:SetTrans(header, "LID_CHARACTER", true)
    self.mainCheck = self:CreateCheck(panel)
    self.mainCheck:SetPoint("TOPLEFT", panel, "TOPLEFT", 16, -42)
    self.mainCheck:SetScript("OnClick", function()
        GuildHelper.Specs:SetMain(not GuildHelper.Specs:IsMain())
        Settings:Update()
    end)

    local title = Theme:Text(panel, 14, "text")
    title:SetPoint("TOPLEFT", panel, "TOPLEFT", 48, -42)
    title:SetPoint("RIGHT", panel, "RIGHT", -18, 0)
    Theme:SetTrans(title, "LID_MAINCHAR")
    local sub = Theme:Text(panel, 12, "muted")
    sub:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -5)
    sub:SetPoint("RIGHT", panel, "RIGHT", -18, 0)
    Theme:SetTrans(sub, "LID_MAINCHARDESC")
    local line = Theme:Line(panel, "divider")
    line:SetHeight(1)
    line:SetPoint("TOPLEFT", panel, "TOPLEFT", 1, -92)
    line:SetPoint("TOPRIGHT", panel, "TOPRIGHT", -1, -92)
    self.specRows = {self:CreateSpecRow(panel, -108, 1), self:CreateSpecRow(panel, -148, 2)}
    self:CreateTwitchRow(panel, -188)

    return panel
end

function Settings:UpdateCharacter()
    if not self.mainCheck then return end
    local Specs = GuildHelper.Specs
    self.mainCheck:SetChecked(Specs:IsMain())
    local none = GuildHelper:Trans("LID_NONE")
    for slot, row in ipairs(self.specRows) do
        local entry = Specs:GetOwn()[slot]
        self:SetPill(row.role, Specs:Format({
            role = entry.role
        }) or none, 120)

        self:SetPill(row.spec, Specs:Format({
            spec = entry.spec,
            icon = entry.icon
        }) or none, 140)
    end

    if not self.twitchBox:HasFocus() then self.twitchBox:SetText(Specs:GetTwitch()) end
end

function Settings:CreateTwitchRow(parent, y)
    local box
    if Theme:IsNative() then
        box = Theme:FlatNative(CreateFrame("EditBox", nil, parent, "InputBoxTemplate"))
        box:SetSize(206, 24)
        box:SetPoint("TOPRIGHT", parent, "TOPRIGHT", -18, y - 2)
    else
        box = CreateFrame("EditBox", nil, parent)
        box:SetSize(212, 28)
        box:SetPoint("TOPRIGHT", parent, "TOPRIGHT", -18, y)
        box:SetTextInsets(10, 10, 0, 0)
        box.fill, box.border = Theme:Panel(box, "control", "border", 7)
        Theme:Track(box, "text", "text", 12.5)
    end

    box:SetAutoFocus(false)
    box:SetMaxLetters(25)
    box:SetScript("OnEnterPressed", function(sel) sel:ClearFocus() end)
    box:SetScript("OnEscapePressed", function(sel)
        sel:SetText(GuildHelper.Specs:GetTwitch())
        sel:ClearFocus()
    end)

    box:SetScript("OnEditFocusGained", function(sel) if sel.border then Theme:SetKey(sel.border, "accent") end end)
    box:SetScript("OnEditFocusLost", function(sel)
        if sel.border then Theme:SetKey(sel.border, "border") end
        if (sel:GetText() or "") ~= GuildHelper.Specs:GetTwitch() then GuildHelper.Specs:SetTwitch(sel:GetText()) end
        sel:SetText(GuildHelper.Specs:GetTwitch())
    end)

    local title = Theme:Text(parent, 14, "text")
    title:SetPoint("LEFT", parent, "TOPLEFT", 18, y - 14)
    title:SetPoint("RIGHT", box, "LEFT", -12, 0)
    Theme:SetTrans(title, "LID_TWITCHNAME")
    self.twitchBox = box
end

Settings.MAPWIDTH = 340
Settings.MAPROW = 40
Settings.MAPOPTIONS = {
    {
        key = "GUILDMEMBERPINS",
        default = true,
        label = "LID_GUILDMEMBERPINS",
        desc = "LID_GUILDMEMBERPINSDESC"
    },
    {
        key = "GUILDMEMBERLEVEL",
        default = false,
        label = "LID_GUILDMEMBERLEVEL",
        desc = "LID_GUILDMEMBERLEVELDESC",
        requires = "GUILDMEMBERPINS"
    },
    {
        key = "GUILDMEMBERNAME",
        default = false,
        label = "LID_GUILDMEMBERNAME",
        desc = "LID_GUILDMEMBERNAMEDESC",
        requires = "GUILDMEMBERPINS"
    },
    {
        key = "GUILDMEMBERZONES",
        default = true,
        label = "LID_GUILDMEMBERZONES",
        desc = "LID_GUILDMEMBERZONESDESC",
        requires = "GUILDMEMBERPINS"
    },
    {
        key = "GUILDMEMBERSHARE",
        default = true,
        label = "LID_GUILDMEMBERSHARE",
        desc = "LID_GUILDMEMBERSHAREDESC"
    }
}

Settings.INVITEOPTIONS = {
    {
        key = "GUILDINVITELINKS",
        default = true,
        label = "LID_GUILDINVITELINKS",
        desc = "LID_GUILDINVITELINKSDESC"
    },
    {
        key = "GUILDINVITEKEYWORD",
        default = false,
        label = "LID_GUILDINVITEKEYWORD",
        desc = "LID_GUILDINVITEKEYWORDDESC"
    }
}

Settings.DISPLAYOPTIONS = {
    {
        key = "MMBTN",
        default = true,
        label = "LID_SHOWMINIMAP",
        desc = "LID_SHOWMINIMAPDESC",
        display = true
    },
    {
        key = "SHOWILVL",
        default = false,
        label = "LID_SHOWILVL",
        desc = "LID_SHOWILVLDESC",
        display = true
    }
}

function Settings:GetMapOption(key)
    for _, list in ipairs({self.MAPOPTIONS, self.INVITEOPTIONS, self.DISPLAYOPTIONS, self.notificationOptions or {}}) do
        for _, option in ipairs(list) do
            if option.key == key then return GuildHelper:GetConfig(key, option.default) == true end
        end
    end

    return false
end

function Settings:IsMapOptionEnabled(option)
    return option.requires == nil or self:GetMapOption(option.requires)
end

function Settings:ToggleMapOption(option)
    if self:IsMapOptionEnabled(option) then
        GuildHelper:SetConfig(option.key, not self:GetMapOption(option.key))
        if option.key == "MMBTN" then GuildHelper:SetMinimapVisible(self:GetMapOption("MMBTN")) end
        if GuildHelper.GuildMap and not option.invite and not option.display then
            GuildHelper:SetSharedSetting(option.key, self:GetMapOption(option.key))
            GuildHelper.GuildMap.Refresh()
        end
    end

    self:Update()
end

function Settings:ShowMapTooltip(owner, option)
    GameTooltip:SetOwner(owner, "ANCHOR_RIGHT")
    GameTooltip:SetText(GuildHelper:Trans(option.label), 1, 1, 1)
    if option.desc then GameTooltip:AddLine(GuildHelper:Trans(option.desc), 0.8, 0.8, 0.8, true) end
    GameTooltip:Show()
end

function Settings:CreateMapRow(panel, index, option)
    local row = CreateFrame("Button", nil, panel)
    row:SetPoint("TOPLEFT", panel, "TOPLEFT", 10, -36 - (index - 1) * self.MAPROW)
    row:SetPoint("RIGHT", panel, "RIGHT", -10, 0)
    row:SetHeight(self.MAPROW)
    local check = self:CreateCheck(row)
    check:SetPoint("LEFT", row, "LEFT", 6, 0)
    local title = Theme:Text(row, 13, "text")
    title:SetPoint("LEFT", row, "LEFT", 38, 0)
    title:SetPoint("RIGHT", row, "RIGHT", -8, 0)
    Theme:SetTrans(title, option.label)
    for _, frame in ipairs({row, check}) do
        frame:SetScript("OnClick", function() Settings:ToggleMapOption(option) end)
        frame:SetScript("OnEnter", function() Settings:ShowMapTooltip(row, option) end)
        frame:SetScript("OnLeave", function() if GameTooltip:IsOwned(row) then GameTooltip:Hide() end end)
    end

    return {
        option = option,
        row = row,
        check = check
    }
end

function Settings:CreateMapPanel(content, anchor)
    if GuildHelper.GuildMap == nil then return end
    local panel = CreateFrame("Frame", nil, content)
    panel:SetPoint("TOPLEFT", anchor, "TOPRIGHT", 16, 0)
    panel:SetSize(self.MAPWIDTH, 48 + #self.MAPOPTIONS * self.MAPROW)
    Theme:Panel(panel, "panel", "border", 9)
    local header = Theme:Text(panel, 11, "muted")
    header:SetPoint("TOPLEFT", panel, "TOPLEFT", 18, -16)
    Theme:SetTrans(header, "LID_WORLDMAP", true)
    self.mapPanel = panel
    self.mapRows = {}
    for index, option in ipairs(self.MAPOPTIONS) do
        self.mapRows[index] = self:CreateMapRow(panel, index, option)
    end
end

function Settings:CreateInvitePanel(content, anchor)
    if GuildHelper.GuildInvite == nil then return end
    local panel = CreateFrame("Frame", nil, content)
    if self.mapPanel then
        panel:SetPoint("TOPLEFT", self.mapPanel, "BOTTOMLEFT", 0, -16)
    else
        panel:SetPoint("TOPLEFT", anchor, "TOPRIGHT", 16, 0)
    end

    panel:SetSize(self.MAPWIDTH, 48 + (#self.INVITEOPTIONS + 1) * self.MAPROW)
    Theme:Panel(panel, "panel", "border", 9)
    local header = Theme:Text(panel, 11, "muted")
    header:SetPoint("TOPLEFT", panel, "TOPLEFT", 18, -16)
    Theme:SetTrans(header, "LID_GUILDINVITES", true)
    self.inviteRows = {}
    for index, option in ipairs(self.INVITEOPTIONS) do
        option.invite = true
        self.inviteRows[index] = self:CreateMapRow(panel, index, option)
    end

    local y = -36 - #self.INVITEOPTIONS * self.MAPROW
    local box = CreateFrame("EditBox", nil, panel, Theme:IsNative() and "InputBoxTemplate" or nil)
    box:SetSize(130, 26)
    box:SetPoint("TOPRIGHT", panel, "TOPRIGHT", -18, y - 7)
    if not Theme:IsNative() then
        box:SetTextInsets(10, 10, 0, 0)
        box.fill, box.border = Theme:Panel(box, "control", "border", 7)
        Theme:Track(box, "text", "text", 12.5)
    end

    box:SetAutoFocus(false)
    box:SetMaxLetters(30)
    box:SetScript("OnEnterPressed", function(sel) sel:ClearFocus() end)
    box:SetScript("OnEscapePressed", function(sel)
        sel:SetText(GuildHelper:GetConfig("GUILDINVITEWORD", ""))
        sel:ClearFocus()
    end)

    box:SetScript("OnEditFocusLost", function(sel) GuildHelper:SetConfig("GUILDINVITEWORD", strtrim(sel:GetText() or "")) end)
    local title = Theme:Text(panel, 13, "text")
    title:SetPoint("LEFT", panel, "TOPLEFT", 54, y - 20)
    title:SetPoint("RIGHT", box, "LEFT", -10, 0)
    Theme:SetTrans(title, "LID_GUILDINVITEWORD")
    self.inviteWord = box
end

function Settings:UpdateMap()
    for _, rows in ipairs({self.mapRows or {}, self.inviteRows or {}, self.displayRows or {}, self.notificationRows or {}}) do
        for _, entry in ipairs(rows) do
            entry.check:SetChecked(self:GetMapOption(entry.option.key))
            entry.row:SetAlpha(self:IsMapOptionEnabled(entry.option) and 1 or 0.45)
        end
    end

    if self.inviteWord and not self.inviteWord:HasFocus() then
        self.inviteWord:SetText(GuildHelper:GetConfig("GUILDINVITEWORD", ""))
        self.inviteWord:SetAlpha(self:GetMapOption("GUILDINVITEKEYWORD") and 1 or 0.45)
    end
end

function Settings:UpdateWindowKey()
    if not self.keyPill then return end
    local key = GuildHelper:GetConfig("WINDOWKEY", "SHIFT-J")
    self:SetPill(self.keyPill, self.capturingKey and GuildHelper:Trans("LID_PRESSKEY") or (key == "" and NOT_BOUND or GetBindingText(key, "KEY_")))
end

function Settings:StopKeyCapture()
    self.capturingKey = false
    if self.keyPill then self.keyPill:EnableKeyboard(false) end
    self:UpdateWindowKey()
end

function Settings:CreateWindowKey(panel)
    self.keyPill = self:CreateRow(panel, -218, "LID_WINDOWKEY", "LID_WINDOWKEYDESC")
    self.keyPill:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    self.keyPill:SetScript("OnClick", function(sel, button)
        if button == "RightButton" then
            GuildHelper:SetConfig("WINDOWKEY", "")
            GuildHelper:ApplyWindowKey()
            Settings:StopKeyCapture()
            return
        end

        Settings.capturingKey = true
        sel:EnableKeyboard(true)
        sel:SetPropagateKeyboardInput(false)
        Settings:UpdateWindowKey()
    end)

    self.keyPill:SetScript("OnKeyDown", function(_, key)
        if key == "ESCAPE" then
            Settings:StopKeyCapture()
            return
        end

        if key == "LSHIFT" or key == "RSHIFT" or key == "LCTRL" or key == "RCTRL" or key == "LALT" or key == "RALT" then return end
        if IsShiftKeyDown() then key = "SHIFT-" .. key end
        if IsControlKeyDown() then key = "CTRL-" .. key end
        if IsAltKeyDown() then key = "ALT-" .. key end
        GuildHelper:SetConfig("WINDOWKEY", key)
        GuildHelper:ApplyWindowKey()
        Settings:StopKeyCapture()
    end)

    self.keyPill:SetScript("OnHide", function() Settings:StopKeyCapture() end)
    self.keyPill:EnableKeyboard(false)
end

function Settings:Update()
    self:UpdateCharacter()
    if self.langPill == nil then return end
    self:SetPill(self.langPill, Members:GetOptionLabel(self:GetLanguageOptions(), GuildHelper:GetConfig("LANGUAGE", "auto")))
    self:SetPill(self.designPill, Members:GetOptionLabel(self:GetDesignOptions(), GuildHelper:GetDesign()))
    self:UpdateWindowKey()
    self:UpdateMap()
end

function Settings:CreateNotificationPanel(content, anchor)
    local panel = CreateFrame("Frame", nil, content)
    panel:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", 0, -16)
    panel:SetSize(self.WIDTH, 282)
    Theme:Panel(panel, "panel", "border", 9)
    local header = Theme:Text(panel, 11, "muted")
    header:SetPoint("TOPLEFT", panel, "TOPLEFT", 18, -16)
    Theme:SetTrans(header, "LID_NOTIFICATIONS", true)
    self.notificationOptions = {}
    self.notificationRows = {}
    for index, key in ipairs(GuildHelper.Notifications.NEW_TYPES) do
        local option = {key = key, default = false, label = "LID_NOTIFICATION" .. key, display = true}
        self.notificationOptions[index] = option
        self.notificationRows[index] = self:CreateMapRow(panel, index, option)
    end

    local position = Members:CreateButton(panel, "LID_NOTIFICATIONPOSITION")
    position:SetPoint("TOPLEFT", panel, "TOPLEFT", 18, -202)
    position:SetWidth(self.WIDTH - 36)
    position:SetScript("OnClick", function()
        GuildHelper.Notifications:SetEditing(not GuildHelper.Notifications.editing)
    end)

    local test = Members:CreateButton(panel, "LID_NOTIFICATIONTEST")
    test:SetPoint("TOPLEFT", position, "BOTTOMLEFT", 0, -4)
    test:SetWidth(self.WIDTH - 36)
    test:SetScript("OnClick", function() GuildHelper.Notifications:Test() end)
end

function Settings:Build(content)
    Window:CreatePageTitle(content, "LID_SETTINGS")
    local scroll = CreateFrame("ScrollFrame", nil, content)
    scroll:SetPoint("TOPLEFT", content, "TOPLEFT", Window.PADDING, -80)
    scroll:SetPoint("BOTTOMRIGHT", content, "BOTTOMRIGHT", -Window.PADDING, Window.PADDING)
    local body = CreateFrame("Frame", nil, scroll)
    body:SetSize(self.WIDTH + 16 + self.MAPWIDTH, 594)
    scroll:SetScrollChild(body)
    scroll:EnableMouseWheel(true)
    scroll:SetScript("OnMouseWheel", function(sel, delta)
        sel:SetVerticalScroll(min(max(sel:GetVerticalScroll() - delta * 40, 0), sel:GetVerticalScrollRange()))
    end)

    scroll:SetScript("OnScrollRangeChanged", function(sel)
        sel:SetVerticalScroll(min(sel:GetVerticalScroll(), sel:GetVerticalScrollRange()))
    end)

    local panel = CreateFrame("Frame", nil, body)
    panel:SetPoint("TOPLEFT", body, "TOPLEFT", 0, 0)
    panel:SetSize(self.WIDTH, 294)
    Theme:Panel(panel, "panel", "border", 9)
    self.langPill = self:CreateRow(panel, -20, "LID_LANGUAGE", "LID_LANGUAGEDESC")
    self.langPill:SetScript("OnClick", function(sel)
        Members:OpenMenu(sel, Settings:GetLanguageOptions(), GuildHelper:GetConfig("LANGUAGE", "auto"), function(value) GuildHelper:SetLanguage(value) end)
    end)

    local line = Theme:Line(panel, "divider")
    line:SetHeight(1)
    line:SetPoint("TOPLEFT", panel, "TOPLEFT", 1, -66)
    line:SetPoint("TOPRIGHT", panel, "TOPRIGHT", -1, -66)
    self.designPill = self:CreateRow(panel, -86, "LID_DESIGN", "LID_DESIGNDESC")
    self.designPill:SetScript("OnClick", function(sel)
        Members:OpenMenu(sel, Settings:GetDesignOptions(), GuildHelper:GetDesign(), function(value) GuildHelper:SetDesign(value) end)
    end)

    local displayLine = Theme:Line(panel, "divider")
    displayLine:SetHeight(1)
    displayLine:SetPoint("TOPLEFT", panel, "TOPLEFT", 1, -132)
    displayLine:SetPoint("TOPRIGHT", panel, "TOPRIGHT", -1, -132)
    self.displayRows = {}
    for index, option in ipairs(self.DISPLAYOPTIONS) do
        local entry = self:CreateMapRow(panel, index, option)
        entry.row:ClearAllPoints()
        entry.row:SetPoint("TOPLEFT", panel, "TOPLEFT", 10, -132 - (index - 1) * 36)
        entry.row:SetPoint("RIGHT", panel, "RIGHT", -10, 0)
        entry.row:SetHeight(36)
        self.displayRows[index] = entry
    end

    self:CreateWindowKey(panel)
    self:CreateMapPanel(body, panel)
    self:CreateInvitePanel(body, panel)
    self:CreateNotificationPanel(body, panel)
    if not self.hooked then
        self.hooked = true
        Theme:OnRefresh(function() Settings:Update() end)
    end

    content.OnPageShow = function() Settings:Update() end
    content.OnPageHide = function()
        Settings:StopKeyCapture()
        if Members.menu then Members.menu:Hide() end
    end
end

Settings.SETUPWIDTH = 520
Settings.SETUPHEIGHT = 290
function Settings:CreateSetup()
    local frame = Window.frame
    local popup = CreateFrame("Frame", nil, frame)
    popup:SetAllPoints(frame)
    popup:SetFrameLevel(frame:GetFrameLevel() + 50)
    popup:EnableMouse(true)
    local dim = popup:CreateTexture(nil, "BACKGROUND")
    dim:SetAllPoints(popup)
    dim:SetColorTexture(0, 0, 0, 0.55)
    local box = Window:CreateStyledFrame(nil, popup)
    box:SetSize(self.SETUPWIDTH, self.SETUPHEIGHT)
    box:SetPoint("CENTER", popup, "CENTER", 0, 0)
    box:SetFrameLevel(popup:GetFrameLevel() + 1)
    box:EnableMouse(true)
    box:SetMovable(true)
    box:SetClampedToScreen(true)
    box:RegisterForDrag("LeftButton")
    box:SetScript("OnDragStart", box.StartMoving)
    box:SetScript("OnDragStop", box.StopMovingOrSizing)
    Window:SetupMainFrame(box)
    if box.CloseButton then box.CloseButton:Hide() end
    local title = Theme:Text(box, 18, "text")
    title:SetPoint("TOPLEFT", box, "TOPLEFT", 24, -24)
    title:SetPoint("RIGHT", box, "RIGHT", -24, 0)
    title:SetJustifyH("LEFT")
    Theme:SetTrans(title, "LID_SETUPTITLE")
    local desc = Theme:Text(box, 12.5, "muted")
    desc:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -8)
    desc:SetPoint("RIGHT", box, "RIGHT", -24, 0)
    desc:SetJustifyH("LEFT")
    desc:SetWordWrap(true)
    Theme:SetTrans(desc, "LID_SETUPDESC")
    local panel = CreateFrame("Frame", nil, box)
    panel:SetPoint("TOPLEFT", box, "TOPLEFT", 16, -94)
    panel:SetPoint("TOPRIGHT", box, "TOPRIGHT", -16, -94)
    panel:SetHeight(132)
    Theme:Panel(panel, "panel", "border", 9)
    popup.langPill = self:CreateRow(panel, -20, "LID_LANGUAGE", "LID_LANGUAGEDESC")
    popup.langPill:SetScript("OnClick", function(sel)
        Members:OpenMenu(sel, Settings:GetLanguageOptions(), GuildHelper:GetConfig("LANGUAGE", "auto"), function(value) GuildHelper:SetLanguage(value) end)
    end)

    local line = Theme:Line(panel, "divider")
    line:SetHeight(1)
    line:SetPoint("TOPLEFT", panel, "TOPLEFT", 1, -66)
    line:SetPoint("TOPRIGHT", panel, "TOPRIGHT", -1, -66)
    popup.designPill = self:CreateRow(panel, -86, "LID_DESIGN", "LID_DESIGNDESC")
    popup.designPill:SetScript("OnClick", function(sel)
        Members:OpenMenu(sel, Settings:GetDesignOptions(), GuildHelper:GetDesign(), function(value) GuildHelper:SetDesign(value) end)
    end)

    local done = Members:CreateButton(box, "LID_SETUPDONE", true)
    done:SetWidth(150)
    done:SetPoint("BOTTOMRIGHT", box, "BOTTOMRIGHT", -16, 16)
    done:SetScript("OnClick", function() Settings:FinishSetup() end)
    popup:Hide()
    self.setup = popup

    return popup
end

function Settings:UpdateSetup()
    local popup = self.setup
    if popup == nil then return end
    self:SetPill(popup.langPill, Members:GetOptionLabel(self:GetLanguageOptions(), GuildHelper:GetConfig("LANGUAGE", "auto")))
    self:SetPill(popup.designPill, Members:GetOptionLabel(self:GetDesignOptions(), GuildHelper:GetDesign()))
end

function Settings:ShowSetup()
    if GuildHelper:GetConfig("SETUPDONE", false) or Window.frame == nil then return end
    if not self.setupHooked then
        self.setupHooked = true
        Theme:OnRefresh(function() Settings:UpdateSetup() end)
    end

    local popup = self.setup or self:CreateSetup()
    popup:Show()
    self:UpdateSetup()
end

function Settings:FinishSetup()
    GuildHelper:SetConfig("SETUPDONE", true)
    if Members.menu then Members.menu:Hide() end
    if self.setup then self.setup:Hide() end
end

Window:OnRebuild(function()
    Settings.setup = nil
    Settings.mainCheck = nil
    Settings.langPill = nil
    Settings.mapPanel = nil
end)

Window:SetPageBuilder("chars", function(content, entry)
    Window:CreatePageTitle(content, entry.label)
    local panel = Settings:CreateCharacterPanel(content)
    Window:BuildPlaceholder(content, entry, panel)
    content.OnPageShow = function() Settings:UpdateCharacter() end
end)
Window:SetPageBuilder("settings", function(content) Settings:Build(content) end)
