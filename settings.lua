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

function Settings:CreateCharacterPanel(content, anchor)
    local panel = CreateFrame("Frame", nil, content)
    panel:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", 0, -16)
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
end

function Settings:UpdateCharacter()
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
        box = CreateFrame("EditBox", nil, parent, "InputBoxTemplate")
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
        key = "GUILDMEMBERSHARE",
        default = true,
        label = "LID_GUILDMEMBERSHARE",
        desc = "LID_GUILDMEMBERSHAREDESC"
    }
}

function Settings:GetMapOption(key)
    for _, option in ipairs(self.MAPOPTIONS) do
        if option.key == key then return GuildHelper:GetConfig(key, option.default) == true end
    end

    return false
end

function Settings:IsMapOptionEnabled(option)
    return option.requires == nil or self:GetMapOption(option.requires)
end

function Settings:ToggleMapOption(option)
    if self:IsMapOptionEnabled(option) then
        GuildHelper:SetConfig(option.key, not self:GetMapOption(option.key))
        GuildHelper.GuildMap.Refresh()
    end

    self:Update()
end

function Settings:ShowMapTooltip(owner, option)
    GameTooltip:SetOwner(owner, "ANCHOR_RIGHT")
    GameTooltip:SetText(GuildHelper:Trans(option.label), 1, 1, 1)
    GameTooltip:AddLine(GuildHelper:Trans(option.desc), 0.8, 0.8, 0.8, true)
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
    self.mapRows = {}
    for index, option in ipairs(self.MAPOPTIONS) do
        self.mapRows[index] = self:CreateMapRow(panel, index, option)
    end
end

function Settings:UpdateMap()
    if self.mapRows == nil then return end
    for _, entry in ipairs(self.mapRows) do
        entry.check:SetChecked(self:GetMapOption(entry.option.key))
        entry.row:SetAlpha(self:IsMapOptionEnabled(entry.option) and 1 or 0.45)
    end
end

function Settings:Update()
    if self.langPill == nil then return end
    self:SetPill(self.langPill, Members:GetOptionLabel(self:GetLanguageOptions(), GuildHelper:GetConfig("LANGUAGE", "auto")))
    self:SetPill(self.designPill, Members:GetOptionLabel(self:GetDesignOptions(), GuildHelper:GetDesign()))
    self:UpdateCharacter()
    self:UpdateMap()
end

function Settings:Build(content)
    Window:CreatePageTitle(content, "LID_SETTINGS")
    local panel = CreateFrame("Frame", nil, content)
    panel:SetPoint("TOPLEFT", content, "TOPLEFT", Window.PADDING, -80)
    panel:SetSize(self.WIDTH, 132)
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

    self:CreateCharacterPanel(content, panel)
    self:CreateMapPanel(content, panel)
    if not self.hooked then
        self.hooked = true
        Theme:OnRefresh(function() Settings:Update() end)
    end

    content.OnPageShow = function() Settings:Update() end
    content.OnPageHide = function()
        if Members.menu then Members.menu:Hide() end
    end
end

Window:SetPageBuilder("settings", function(content) Settings:Build(content) end)
