local _, GuildHelper = ...
local Window, Theme, Members, Sync = GuildHelper.Window, GuildHelper.Theme, GuildHelper.Members, GuildHelper.Sync
local Professions = {}
GuildHelper.Professions = Professions
local Recipes = GuildHelper.Recipes
Professions.skillSpells = {[129] = 3273, [164] = 2018, [165] = 2108, [171] = 2259, [182] = 2366, [185] = 2550, [186] = 2575, [197] = 3908, [202] = 4036, [333] = 7411, [356] = 7620, [393] = 8613, [755] = 25229, [773] = 45357, [794] = 78670}

function Professions:CreateList(parent, readOnly)
    local panel = CreateFrame("Frame", nil, parent)
    Theme:Panel(panel, "panel", "border", 7)
    local scroll = CreateFrame("ScrollFrame", nil, panel)
    scroll:SetPoint("TOPLEFT", 8, -8)
    scroll:SetPoint("BOTTOMRIGHT", -16, 8)
    local body = CreateFrame("Frame", nil, scroll)
    body:SetSize(1, 1)
    scroll:SetScrollChild(body)
    local thumb = CreateFrame("Button", nil, panel)
    thumb:SetWidth(4)
    thumb:SetFrameLevel(scroll:GetFrameLevel() + 2)
    Theme:Round(thumb, "thumb", 2)
    thumb:Hide()
    local function updateThumb()
        GuildHelper.Dashboard:UpdateScrollThumb(scroll, thumb, scroll:GetVerticalScrollRange(), scroll:GetVerticalScroll(), 8)
    end
    local function setOffset(offset)
        scroll:SetVerticalScroll(min(max(0, offset), scroll:GetVerticalScrollRange()))
        updateThumb()
    end
    scroll:EnableMouseWheel(true)
    scroll:SetScript("OnMouseWheel", function(_, delta) setOffset(scroll:GetVerticalScroll() - delta * 36) end)
    scroll:SetScript("OnVerticalScroll", updateThumb)
    scroll:SetScript("OnScrollRangeChanged", function() setOffset(scroll:GetVerticalScroll()) end)
    scroll:SetScript("OnSizeChanged", function(_, width)
        body:SetWidth(max(1, width))
        updateThumb()
    end)
    Theme:BindScrollDrag(thumb, function()
        return scroll:GetVerticalScroll(), scroll:GetVerticalScrollRange(), scroll:GetHeight() - 12 - thumb:GetHeight()
    end, setOffset)
    panel.scroll, panel.body, panel.rows = scroll, body, {}
    panel.readOnly = readOnly
    return panel
end

function Professions:ShowRows(panel, entries, onClick, selected)
    local step = panel.readOnly and 36 or 30
    for index, entry in ipairs(entries) do
        local row = panel.rows[index]
        if not row then
            if panel.readOnly then
                row = CreateFrame("Frame", nil, panel.body)
                row.text = Theme:Text(row, 13, "text")
                row.text:SetWordWrap(true)
                row.text:SetHeight(step - 2)
            else
                row = Members:CreateButton(panel.body, "LID_FBALL")
                row.text.ghTrans = nil
                row.text:ClearAllPoints()
                row.selection = Theme:Fill(row:CreateTexture(nil, "ARTWORK"), "accent")
                row.selection:SetPoint("TOPLEFT", 1, -5)
                row.selection:SetPoint("BOTTOMLEFT", 1, 5)
                row.selection:SetWidth(3)
                if not row.native then
                    row:SetScript("OnEnter", function(button) Theme:SetKey(button.fill, button.selected and "rowSelected" or "hover") end)
                    row:SetScript("OnLeave", function(button) Theme:SetKey(button.fill, button.selected and "rowSelected" or "control") end)
                end
            end
            row:SetHeight(step - 2)
            row:SetPoint("TOPLEFT", 0, -(index - 1) * step)
            row:SetPoint("TOPRIGHT", panel.body, "TOPRIGHT", 0, -(index - 1) * step)
            row.text:SetPoint("LEFT", 8, 0)
            row.text:SetPoint("RIGHT", -8, 0)
            row.text:SetJustifyH("LEFT")
            panel.rows[index] = row
        end
        row.text:SetText(entry.label)
        local texture = entry.icon or (entry.id and Recipes:Icon(entry.id))
        if entry.prefix then
            if not row.prefix then
                row.prefix = Theme:Text(row, 13, "text")
                row.prefix:SetPoint("LEFT", 8, 0)
                row.prefix:SetWidth(30)
                row.prefix:SetJustifyH("RIGHT")
            end
            row.prefix:SetText(entry.prefix)
        end
        if row.prefix then row.prefix:SetShown(entry.prefix ~= nil) end
        if texture then
            if not row.icon then
                row.icon = row:CreateTexture(nil, "ARTWORK")
                row.icon:SetSize(20, 20)
            end
            row.icon:SetPoint("LEFT", entry.prefix and 43 or 7, 0)
            row.icon:SetTexture(texture)
        end
        if row.icon then row.icon:SetShown(texture ~= nil) end
        row.text:SetPoint("LEFT", entry.prefix and 70 or ((texture or entry.member) and 35 or 8), 0)
        if not panel.readOnly then
            if entry.member then
                if not row.avatar then
                    row.avatar = Members:CreateAvatar(row, 22, 11)
                    row.avatar:SetPoint("LEFT", 7, 0)
                end
                local r, g, b = Members:GetClassColor(entry.member)
                Members:FillAvatar(row.avatar, entry.member, Members:GetData(entry.member), r, g, b)
            end
            if row.avatar then row.avatar:SetShown(entry.member ~= nil) end
            row:SetScript("OnClick", function() onClick(entry.key) end)
            row.selected = selected == entry.key
            row.selection:SetShown(row.selected)
            if not row.native then
                Theme:SetKey(row.fill, row.selected and "rowSelected" or (row:IsMouseOver() and "hover" or "control"))
            end
        end
        row:Show()
    end
    for index = #entries + 1, #panel.rows do panel.rows[index]:Hide() end
    panel.body:SetHeight(max(1, #entries * step))
    panel.scroll:SetVerticalScroll(min(panel.scroll:GetVerticalScroll(), panel.scroll:GetVerticalScrollRange()))
end

function Professions:Update()
    local page = self.page
    if not page or not page:IsVisible() then return end
    local counts, filters, results, recipes = {}, {}, {}, {}
    local query = strlower(strtrim(page.search:GetText()))
    local byRecipe = page.byRecipe:GetChecked()
    local byMaterial = byRecipe and page.byMaterial:GetChecked()
    local missing, captured = false, false
    local roster = Members.list
    if page.focusName then
        roster = {}
        for _, member in ipairs(Members.list) do
            if member.name == page.focusName then
                roster[1] = member
                break
            end
        end
    end
    for _, member in ipairs(roster) do
        local data = Members:GetData(member)
        local skills, seen = {}, {}
        local own = Members:IsSelf(member)
        local professions = data and data.professions
        if own then professions = Sync:GetOwnProfessions() end
        for _, skill in ipairs(professions or {}) do
            local id = Sync:GetProfessionID(skill[1], skill[4])
            local key = id or skill[1]
            local name = Sync:GetProfessionName(id, skill[1])
            if not counts[key] then
                local spell = self.skillSpells[id]
                local getTexture = C_Spell and C_Spell.GetSpellTexture or GetSpellTexture
                local icon = spell and getTexture and getTexture(spell)
                counts[key] = {key = key, name = name, count = 0, icon = icon or "Interface\\Icons\\Trade_BlackSmithing"}
                tinsert(filters, counts[key])
            end
            if not seen[key] then counts[key].count = counts[key].count + 1 end
            seen[key] = format("%d/%d", skill[2] or 0, skill[3] or 0)
            tinsert(skills, {label = name .. "  " .. seen[key], key = key, icon = counts[key].icon})
        end
        if #skills > 0 and (not page.online:GetChecked() or member.online) then
            local status = member.online and GuildHelper:Trans("LID_ONLINE") or (FRIENDS_LIST_OFFLINE or PLAYER_OFFLINE or "")
            local label = member.short .. "  |cffaaaaaa" .. status .. "|r"
            if byRecipe then
                for key in pairs(seen) do
                    if not page.filter or page.filter == key then
                        local known = data and data.recipes and data.recipes[tostring(key)]
                        if known then captured = true else missing = true end
                        if query ~= "" or page.focusName then
                            for id, materials in pairs(known or {}) do
                                local recipe = Recipes:Name(id)
                                local nameMatches = strlower(recipe):find(query, 1, true) ~= nil
                                if (byMaterial or nameMatches) and (own or Recipes:CanSee(data, tostring(key), id)) then
                                    local result = recipes[id]
                                    if not result then
                                        result = {key = id, recipe = recipe, id = id, crafters = {}, members = {}}
                                        recipes[id] = result
                                    end
                                    if not result.matched and (nameMatches or Recipes:MatchesMaterials(id, materials, query)) then
                                        result.matched = true
                                        tinsert(results, result)
                                    end
                                    if materials ~= "-" then result.materials = materials end
                                    if not result.members[member.name] then
                                        local crafter = {key = member.name, label = label, member = member}
                                        result.members[member.name] = crafter
                                        tinsert(result.crafters, crafter)
                                    end
                                end
                            end
                        end
                    end
                end
            elseif strlower(member.name):find(query, 1, true) then
                tinsert(results, {key = member.name, label = label, member = member, skills = skills, seen = seen})
            end
        end
    end
    table.sort(filters, function(a, b) return a.name < b.name end)
    for _, filter in ipairs(filters) do filter.label = format("%s  (%d)", filter.name, filter.count) end
    tinsert(filters, 1, {key = false, label = GuildHelper:Trans("LID_FBALL")})
    if page.filter and not counts[page.filter] then page.filter = false end
    for index = #results, 1, -1 do
        local result = results[index]
        if page.filter and not byRecipe then
            local rank = result.seen[page.filter]
            if rank then
                result.label = result.label .. "    " .. rank
            else
                table.remove(results, index)
            end
        end
    end
    local function byMember(a, b)
        if a.member.online ~= b.member.online then return a.member.online end
        return a.key < b.key
    end
    if byRecipe then
        for _, result in ipairs(results) do
            result.label = format("%s  (%d)", result.recipe, #result.crafters)
        end
        table.sort(results, function(a, b)
            if a.recipe ~= b.recipe then return a.recipe < b.recipe end
            return a.key < b.key
        end)
    else
        table.sort(results, byMember)
    end
    local total = #results
    for index = total, 101, -1 do results[index] = nil end
    local selected
    for _, result in ipairs(results) do
        if result.key == page.selected then selected = result end
    end
    if not byRecipe then selected = selected or results[1] end
    page.selected = selected and selected.key
    local crafter = selected and selected.members and selected.members[page.selectedCrafter]
    page.selectedCrafter = crafter and crafter.key
    page.member = crafter and crafter.member or selected and selected.member
    page.empty:SetText(GuildHelper:Trans(byRecipe and (query == "" and not page.focusName and "LID_RECIPESEARCH" or "LID_RECIPENOMATCH") or "LID_NODATA"))
    page.empty:SetShown(#results == 0)
    local notice = byRecipe and (missing or not captured) and GuildHelper:Trans("LID_RECIPEDATAMISSING") or ""
    if total > #results then
        local count = format("%d / %d", #results, total)
        notice = notice ~= "" and notice .. "  (" .. count .. ")" or count
    end
    page.notice:SetText(notice)
    page.whisper:SetEnabled(page.member ~= nil and not Members:IsSelf(page.member))
    self:ShowRows(page.filters, filters, function(key)
        page.filter = key
        if page.results then page.results.scroll:SetVerticalScroll(0) end
        self:Update()
    end, page.filter)
    self:ShowRows(page.results, results, function(key)
        if page.selected ~= key then
            page.selectedCrafter = nil
            page.crafters.scroll:SetVerticalScroll(0)
        end
        page.selected = key
        page.details.scroll:SetVerticalScroll(0)
        self:Update()
    end, page.selected)
    local details = selected and selected.skills or {}
    local recipe = selected and selected.id
    local panel = page.details
    panel.recipeHeader:SetShown(recipe ~= nil)
    page.crafters:SetShown(recipe ~= nil)
    panel.scroll:SetPoint("TOPLEFT", 8, recipe and -196 or -8)
    page.order:SetShown(byRecipe and true or false)
    page.byMaterial:SetShown(byRecipe and true or false)
    panel:SetPoint("BOTTOMRIGHT", byRecipe and page.order or page.whisper, "TOPRIGHT", 0, 8)
    page.orderRecipe, page.orderRequirements = recipe, nil
    if recipe then
        panel.recipeTitle:SetText(selected.recipe)
        panel.recipeIcon:SetTexture(Recipes:Icon(recipe))
        table.sort(selected.crafters, byMember)
        self:ShowRows(page.crafters, selected.crafters, function(key)
            page.selectedCrafter = key
            self:Update()
        end, page.selectedCrafter)
        details, page.orderRequirements = Recipes:Materials(recipe, selected.materials)
        if not details then
            details = {{label = GuildHelper:Trans("LID_NODATA")}}
        elseif #details == 0 then
            details = {{label = GuildHelper:Trans("LID_RECIPE_NOMATERIALS")}}
        end
    end
    local canOrder = crafter ~= nil and not Members:IsSelf(crafter.member) and page.orderRequirements ~= nil
    page.order:SetEnabled(canOrder)
    if page.order.native then
        page.order:SetAlpha(canOrder and 1 or 0.55)
    else
        Theme:SetKey(page.order.fill, canOrder and "accent" or "control")
        Theme:SetKey(page.order.text, canOrder and "accentText" or "muted")
    end
    self:ShowRows(page.details, details)
end

function Professions:Focus(member)
    self.focus = member
    Window:SelectPage("professions")
end

function Professions:Refresh()
    if not self.page or not self.page:IsVisible() then return end
    Members:Scan()
    self:Update()
end

function Professions:Build(content)
    local title = Window:CreatePageTitle(content, "LID_PROFESSIONS")
    local page = CreateFrame("Frame", nil, content)
    page:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -8)
    page:SetPoint("BOTTOMRIGHT", -Window.PADDING, Window.PADDING)
    self.page = page
    page.filter = false
    page.scope = Members:CreatePill(content)
    page.scope:SetPoint("LEFT", title, "RIGHT", 12, 0)
    page.scope:SetScript("OnClick", function()
        page.focusName, page.selected, page.selectedCrafter = nil, nil, nil
        page.filter = false
        page.scope:Hide()
        page.filters.scroll:SetVerticalScroll(0)
        page.results.scroll:SetVerticalScroll(0)
        page.details.scroll:SetVerticalScroll(0)
        self:Update()
    end)
    page.scope:Hide()
    page.search = GuildHelper.Groups:CreateBox(page, 80)
    page.search:SetPoint("TOPLEFT", 0, -5)
    page.search:SetWidth(240)
    local placeholder = Theme:Text(page.search, 13, "muted")
    local inset = page.search:GetTextInsets()
    placeholder:SetPoint("LEFT", max(5, inset), 0)
    Theme:SetTrans(placeholder, "LID_SEARCHPLACEHOLDER")
    page.search:SetScript("OnTextChanged", function(box)
        placeholder:SetShown(box:GetText() == "")
        if page.results then page.results.scroll:SetVerticalScroll(0) end
        self:Update()
    end)
    page.online = CreateFrame("CheckButton", nil, page, "UICheckButtonTemplate")
    page.online:SetPoint("LEFT", page.search, "RIGHT", 14, 0)
    local onlineLabel = Theme:Text(page.online, 13, "text")
    Theme:SetTrans(onlineLabel, "LID_ONLINEONLY")
    onlineLabel:SetPoint("LEFT", page.online, "RIGHT", 3, 0)
    page.online:SetScript("OnClick", function()
        if page.results then page.results.scroll:SetVerticalScroll(0) end
        self:Update()
    end)

    page.byRecipe = CreateFrame("CheckButton", nil, page, "UICheckButtonTemplate")
    page.byRecipe:SetPoint("LEFT", onlineLabel, "RIGHT", 14, 0)
    local recipeLabel = Theme:Text(page.byRecipe, 13, "text")
    Theme:SetTrans(recipeLabel, "LID_RECIPESEARCH")
    recipeLabel:SetPoint("LEFT", page.byRecipe, "RIGHT", 3, 0)
    page.byRecipe:SetScript("OnClick", function(button)
        page.selected, page.selectedCrafter = nil, nil
        page.search:SetText("")
        page.results.scroll:SetVerticalScroll(0)
        page.details.scroll:SetVerticalScroll(0)
        if button:GetChecked() then Recipes:Request() end
        self:Update()
    end)

    page.byMaterial = CreateFrame("CheckButton", nil, page, "UICheckButtonTemplate")
    page.byMaterial:SetPoint("LEFT", recipeLabel, "RIGHT", 14, 0)
    local materialLabel = Theme:Text(page.byMaterial, 13, "text")
    Theme:SetTrans(materialLabel, "LID_RECIPESEARCHMATERIALS")
    materialLabel:SetPoint("LEFT", page.byMaterial, "RIGHT", 3, 0)
    page.byMaterial:SetScript("OnClick", function()
        page.results.scroll:SetVerticalScroll(0)
        self:Update()
    end)
    page.byMaterial:Hide()

    page.filters = self:CreateList(page)
    page.filters:SetPoint("TOPLEFT", 0, -44)
    page.filters:SetPoint("BOTTOMLEFT", 0, 26)
    page.filters:SetWidth(214)
    page.details = self:CreateList(page, true)
    page.details:SetPoint("TOPRIGHT", 0, -44)
    page.details:SetWidth(244)
    local header = CreateFrame("Frame", nil, page.details)
    header:SetPoint("TOPLEFT", 16, -10)
    header:SetPoint("TOPRIGHT", -16, -10)
    header:SetHeight(184)
    header:Hide()
    page.details.recipeHeader = header
    local kind = Theme:Text(header, 11, "muted")
    kind:SetPoint("TOPLEFT")
    Theme:SetTrans(kind, "LID_RECIPE", true)
    local recipeIcon = header:CreateTexture(nil, "ARTWORK")
    recipeIcon:SetSize(24, 24)
    recipeIcon:SetPoint("TOPLEFT", 0, -15)
    page.details.recipeIcon = recipeIcon
    local recipeTitle = Theme:Text(header, 16, "text")
    recipeTitle:SetPoint("TOPLEFT", 31, -14)
    recipeTitle:SetPoint("TOPRIGHT", 0, -14)
    recipeTitle:SetHeight(36)
    recipeTitle:SetJustifyH("LEFT")
    recipeTitle:SetJustifyV("TOP")
    recipeTitle:SetWordWrap(true)
    page.details.recipeTitle = recipeTitle
    local crafter = Theme:Text(header, 12, "muted")
    crafter:SetPoint("TOPLEFT", 0, -52)
    Theme:SetTrans(crafter, "LID_ORDER_CRAFTERS")
    page.crafters = self:CreateList(page.details)
    page.crafters:SetPoint("TOPLEFT", 8, -78)
    page.crafters:SetPoint("TOPRIGHT", -8, -78)
    page.crafters:SetHeight(88)
    page.crafters:Hide()
    local divider = Theme:Line(header, "divider")
    divider:SetPoint("TOPLEFT", 0, -161)
    divider:SetPoint("TOPRIGHT", 0, -161)
    divider:SetHeight(1)
    local materials = Theme:Text(header, 12, "muted")
    materials:SetPoint("TOPLEFT", 0, -169)
    Theme:SetTrans(materials, "LID_RECIPE_MATERIALS")
    page.results = self:CreateList(page)
    page.results:SetPoint("TOPLEFT", page.filters, "TOPRIGHT", 8, 0)
    page.results:SetPoint("TOPRIGHT", page.details, "TOPLEFT", -8, 0)
    page.results:SetPoint("BOTTOMLEFT", page.filters, "BOTTOMRIGHT", 8, 0)

    page.empty = Theme:Text(page.results, 13, "muted")
    page.notice = Theme:Text(page, 12, "muted")
    page.notice:SetPoint("BOTTOMLEFT", 2, 5)
    page.notice:SetPoint("BOTTOMRIGHT", page.results, "BOTTOMRIGHT", 0, -16)
    page.notice:SetJustifyH("LEFT")
    page.empty:SetPoint("CENTER")
    page.whisper = Members:CreateButton(page, "LID_WHISPER", true)
    page.whisper:SetWidth(page.details:GetWidth())
    page.whisper:SetPoint("BOTTOMRIGHT")
    page.whisper:SetScript("OnClick", function() Members:Whisper(page.member) end)
    page.order = Members:CreateButton(page, "LID_ORDER_NEW", true)
    page.order:SetWidth(page.details:GetWidth())
    page.order:SetPoint("BOTTOMRIGHT", page.whisper, "TOPRIGHT", 0, 4)
    page.order:SetScript("OnClick", function()
        if page.member and page.orderRecipe then
            GuildHelper.Orders:Compose(page.member, page.orderRecipe, page.orderRequirements)
        end
    end)
    page.order:Hide()
    content.OnPageShow = function()
        local focus = self.focus
        if focus then
            self.focus = nil
            page.focusName = focus.name
            page.selected, page.selectedCrafter, page.filter = focus.name, nil, false
            Members:SetPillText(page.scope, focus.short .. "  ×")
            page.scope:Show()
            page.byRecipe:SetChecked(false)
            page.online:SetChecked(false)
            page.search:SetText("")
            page.filters.scroll:SetVerticalScroll(0)
            page.results.scroll:SetVerticalScroll(0)
            page.details.scroll:SetVerticalScroll(0)
        end
        Members:RequestRoster()
        if page.byRecipe:GetChecked() then Recipes:Request() end
        self:Refresh()
    end
    content.OnPageHide = function() page.search:ClearFocus() end
end

Window:SetPageBuilder("professions", function(page) Professions:Build(page) end)
Window:OnRebuild(function() Professions.page = nil end)
Sync:OnUpdate(function() Professions:Update() end)
Recipes.onItemLoaded = function()
    if Professions.page and Professions.page.byRecipe:GetChecked() then Professions:Update() end
end
local events = CreateFrame("Frame")
events:RegisterEvent("GUILD_ROSTER_UPDATE")
events:RegisterEvent("PLAYER_GUILD_UPDATE")
events:SetScript("OnEvent", function() Professions:Refresh() end)
