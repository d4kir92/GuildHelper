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

function Settings:SetPill(pill, label)
    Members:SetPillText(pill, label)
    pill:SetWidth(max(self.PILLWIDTH, pill:GetWidth()))
end

function Settings:Update()
    if self.langPill == nil then return end
    self:SetPill(self.langPill, Members:GetOptionLabel(self:GetLanguageOptions(), GuildHelper:GetConfig("LANGUAGE", "auto")))
    self:SetPill(self.designPill, Members:GetOptionLabel(self:GetDesignOptions(), GuildHelper:GetDesign()))
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
