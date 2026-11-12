local _, GuildHelper = ...
local Events, Groups, Theme = GuildHelper.Events, GuildHelper.Groups, GuildHelper.Theme
local PAGE_SIZE, COLUMNS = 36, 9

function Events:BuildIconCatalog()
    local entries, seen = {}, {}
    local function add(value, name)
        local icon = self:NormalizeIcon(value)
        if not icon then return end
        local entry = seen[icon]
        if not entry then
            local label = tostring(icon):match("[^\\]+$") or tostring(icon)
            entry = {icon = icon, label = label, search = strlower(label):gsub("_", " ")}
            seen[icon] = entry
            tinsert(entries, entry)
        end
        if name and name ~= "" then
            if not entry.named then entry.label, entry.named = name, true end
            entry.search = entry.search .. " " .. strlower(name)
        end
    end

    if C_SpellBook and C_SpellBook.GetNumSpellBookSkillLines and C_SpellBook.GetSpellBookSkillLineInfo and
        C_SpellBook.GetSpellBookItemInfo and Enum and Enum.SpellBookSpellBank then
        for index = 1, C_SpellBook.GetNumSpellBookSkillLines() do
            local line = C_SpellBook.GetSpellBookSkillLineInfo(index)
            if line then
                for slot = line.itemIndexOffset + 1, line.itemIndexOffset + line.numSpellBookItems do
                    local info = C_SpellBook.GetSpellBookItemInfo(slot, Enum.SpellBookSpellBank.Player)
                    if info then add(info.iconID, info.name) end
                end
            end
        end
    elseif GetNumSpellTabs and GetSpellTabInfo and GetSpellBookItemName and GetSpellBookItemTexture then
        local book = BOOKTYPE_SPELL or "spell"
        for index = 1, GetNumSpellTabs() do
            local _, _, offset, count = GetSpellTabInfo(index)
            for slot = (offset or 0) + 1, (offset or 0) + (count or 0) do
                add(GetSpellBookItemTexture(slot, book), GetSpellBookItemName(slot, book))
            end
        end
    end

    if C_MountJournal and C_MountJournal.GetMountIDs and C_MountJournal.GetMountInfoByID then
        for _, id in ipairs(C_MountJournal.GetMountIDs() or {}) do
            local name, _, icon = C_MountJournal.GetMountInfoByID(id)
            add(icon, name)
        end
    end
    for _, api in ipairs({"GetLooseMacroIcons", "GetLooseMacroItemIcons", "GetMacroIcons", "GetMacroItemIcons"}) do
        if _G[api] then
            local textures = {}
            _G[api](textures)
            for _, icon in ipairs(textures) do add(icon) end
        end
    end

    self.iconCatalog = entries
end

function Events:SearchIcons(query)
    if not self.iconCatalog then self:BuildIconCatalog() end
    local terms = {}
    for word in strlower(query):gsub("_", " "):gmatch("%S+") do tinsert(terms, word) end
    if #terms == 0 then return self.iconCatalog end
    local matches, seen = {}, {}
    for _, entry in ipairs(self.iconCatalog) do
        local matched = true
        for _, term in ipairs(terms) do
            if not entry.search:find(term, 1, true) then
                matched = false
                break
            end
        end
        if matched then
            seen[entry.icon] = true
            tinsert(matches, entry)
        end
    end
    local name, icon
    local input = query:match("^%s*(.-)%s*$")
    if not tonumber(input) then
        if C_Spell and C_Spell.GetSpellInfo then
            local ok, info = pcall(C_Spell.GetSpellInfo, input)
            if ok and info then name, icon = info.name, info.iconID end
        elseif GetSpellInfo then
            local ok, spellName, _, texture = pcall(GetSpellInfo, input)
            if ok then name, icon = spellName, texture end
        end
        if not icon then
            local itemInfo = C_Item and C_Item.GetItemInfoInstant or GetItemInfoInstant
            if itemInfo then
                local ok, _, _, _, _, texture = pcall(itemInfo, input)
                if ok then icon = texture end
            end
        end
    end
    icon = self:NormalizeIcon(icon)
    if icon and not seen[icon] then
        tinsert(matches, 1, {icon = icon, label = name or input})
    end
    return matches
end

function Events:RefreshIconPreview()
    local form = self.form
    if not form or not self.draft then return end
    local icon = self.draft.icon
    form.icon:SetTexture(icon)
    form.icon:SetShown(icon ~= nil)
    form.iconButton.text:ClearAllPoints()
    form.iconButton.text:SetPoint("CENTER", form.iconButton, "CENTER", icon and 10 or 0, 0)
end

function Events:ChooseIcon(icon)
    if self.draft then
        self.draft.icon = icon
        self:RefreshIconPreview()
    end
    self.iconPicker:Hide()
end

function Events:RefreshIconPicker(reset)
    local picker = self.iconPicker
    if reset or not picker.matches then
        picker.matches = self:SearchIcons(picker.search:GetText())
        picker.page = 1
    end
    local lastPage = max(1, math.ceil(#picker.matches / PAGE_SIZE))
    picker.page = min(max(picker.page, 1), lastPage)
    picker.pageText:SetText(format("%d / %d", picker.page, lastPage))
    picker.previous:SetEnabled(picker.page > 1)
    picker.next:SetEnabled(picker.page < lastPage)
    picker.empty:SetShown(#picker.matches == 0)
    for index, button in ipairs(picker.icons) do
        local entry = picker.matches[(picker.page - 1) * PAGE_SIZE + index]
        button.entry = entry
        button:SetShown(entry ~= nil)
        if entry then
            button.icon:SetTexture(entry.icon)
            Theme:SetKey(button.fill, self.draft and self.draft.icon == entry.icon and "accent" or "control")
        end
    end
end

function Events:BuildIconPicker()
    local picker = CreateFrame("Frame", nil, self.content)
    picker:SetSize(426, 326)
    picker:SetPoint("CENTER")
    picker:SetFrameLevel(self.content:GetFrameLevel() + 30)
    picker:EnableMouse(true)
    Theme:Panel(picker, "window", "border", 8)
    local label = Groups:Text(picker, "LID_EVENT_ICON_SEARCH", 17, -15)
    picker.search = Groups:CreateBox(picker, 72)
    picker.search:SetPoint("TOPLEFT", label, "BOTTOMLEFT", 0, -5)
    picker.search:SetPoint("TOPRIGHT", -17, -35)
    picker.empty = Groups:Text(picker, "LID_EVENT_ICON_EMPTY", 17, -82)
    picker.icons = {}

    for index = 1, PAGE_SIZE do
        local button = CreateFrame("Button", nil, picker)
        button:SetSize(38, 38)
        button:SetPoint("TOPLEFT", 18 + (index - 1) % COLUMNS * 44, -79 - floor((index - 1) / COLUMNS) * 44)
        button.ghNoInside = true
        button.fill = Theme:Panel(button, "control", "border", 4)
        button.icon = button:CreateTexture(nil, "ARTWORK")
        button.icon:SetPoint("TOPLEFT", 3, -3)
        button.icon:SetPoint("BOTTOMRIGHT", -3, 3)
        button:SetScript("OnClick", function(sel) self:ChooseIcon(sel.entry.icon) end)
        button:SetScript("OnEnter", function(sel)
            if not sel.entry then return end
            GameTooltip:SetOwner(sel, "ANCHOR_RIGHT")
            GameTooltip:SetText(sel.entry.label)
            if type(sel.entry.icon) == "number" and sel.entry.label ~= tostring(sel.entry.icon) then
                GameTooltip:AddLine(tostring(sel.entry.icon))
            end
            GameTooltip:Show()
        end)
        button:SetScript("OnLeave", function(sel)
            if GameTooltip:IsOwned(sel) then GameTooltip:Hide() end
        end)
        tinsert(picker.icons, button)
    end

    local function move(delta)
        picker.page = picker.page + delta
        self:RefreshIconPicker()
    end
    picker.previous = self:Button(picker, nil, 30, function() move(-1) end)
    picker.previous.text:SetText("‹")
    picker.previous:SetPoint("BOTTOMLEFT", 17, 16)
    picker.next = self:Button(picker, nil, 30, function() move(1) end)
    picker.next.text:SetText("›")
    picker.next:SetPoint("BOTTOMLEFT", 111, 16)
    picker.pageText = Theme:Text(picker, 12, "muted")
    picker.pageText:SetPoint("CENTER", picker.previous, "CENTER", 47, 0)
    local cancel = self:Button(picker, "LID_FBCANCEL", 115, function() picker:Hide() end)
    cancel:SetPoint("BOTTOMRIGHT", -17, 16)
    local clear = self:Button(picker, "LID_EVENT_ICON_NONE", 122, function() self:ChooseIcon(nil) end)
    clear:SetPoint("RIGHT", cancel, "LEFT", -6, 0)
    picker:EnableMouseWheel(true)
    picker:SetScript("OnMouseWheel", function(_, delta) move(-delta) end)
    picker:SetScript("OnHide", function()
        picker.search:ClearFocus()
        local owner = GameTooltip:GetOwner()
        if owner and owner:GetParent() == picker then GameTooltip:Hide() end
    end)
    picker.search:SetScript("OnEscapePressed", function() picker:Hide() end)
    picker.search:SetScript("OnTextChanged", function()
        if picker:IsShown() then self:RefreshIconPicker(true) end
    end)
    picker:Hide()
    self.iconPicker = picker
end

function Events:OpenIconPicker()
    if not self.draft then return end
    if not self.iconPicker then self:BuildIconPicker() end
    self:BuildIconCatalog()
    local picker = self.iconPicker
    picker.search:SetText("")
    picker:Show()
    self:RefreshIconPicker(true)
    picker.search:SetFocus()
end
