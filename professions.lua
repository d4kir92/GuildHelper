local _, GuildHelper = ...
local Window, Theme, Members, Sync = GuildHelper.Window, GuildHelper.Theme, GuildHelper.Members, GuildHelper.Sync
local Professions = {}
local Recipes = GuildHelper.Recipes

function Professions:CreateList(parent)
    local panel = CreateFrame("Frame", nil, parent)
    Theme:Panel(panel, "panel", "border", 7)
    local scroll = CreateFrame("ScrollFrame", nil, panel, "UIPanelScrollFrameTemplate")
    scroll:SetPoint("TOPLEFT", 8, -8)
    scroll:SetPoint("BOTTOMRIGHT", -28, 8)
    local body = CreateFrame("Frame", nil, scroll)
    body:SetSize(1, 1)
    scroll:SetScrollChild(body)
    scroll:HookScript("OnSizeChanged", function(_, width) body:SetWidth(max(1, width)) end)
    panel.scroll, panel.body, panel.rows = scroll, body, {}
    return panel
end

function Professions:ShowRows(panel, entries, onClick, selected)
    for index, entry in ipairs(entries) do
        local row = panel.rows[index]
        if not row then
            row = Members:CreateButton(panel.body, "LID_FBALL")
            row:SetHeight(28)
            row:SetPoint("TOPLEFT", 0, -(index - 1) * 30)
            row:SetPoint("TOPRIGHT", panel.body, "TOPRIGHT", 0, -(index - 1) * 30)
            row.text.ghTrans = nil
            row.text:ClearAllPoints()
            row.text:SetPoint("LEFT", 8, 0)
            row.text:SetPoint("RIGHT", -8, 0)
            row.text:SetJustifyH("LEFT")
            panel.rows[index] = row
        end
        row.text:SetText(entry.label)
        row:SetScript("OnClick", onClick and function() onClick(entry.key) end or nil)
        row:SetAlpha(onClick and selected and selected ~= entry.key and 0.75 or 1)
        row:EnableMouse(onClick ~= nil)
        row:Show()
    end
    for index = #entries + 1, #panel.rows do panel.rows[index]:Hide() end
    panel.body:SetHeight(max(1, #entries * 30))
    panel.scroll:SetVerticalScroll(min(panel.scroll:GetVerticalScroll(), panel.scroll:GetVerticalScrollRange()))
end

function Professions:Update()
    local page = self.page
    if not page or not page:IsVisible() then return end
    local counts, filters, results = {}, {}, {}
    local query = strlower(strtrim(page.search:GetText()))
    local byRecipe = page.byRecipe:GetChecked()
    local missing, captured = false, false
    for _, member in ipairs(Members.list) do
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
                counts[key] = {key = key, name = name, count = 0}
                tinsert(filters, counts[key])
            end
            if not seen[key] then counts[key].count = counts[key].count + 1 end
            seen[key] = format("%d/%d", skill[2] or 0, skill[3] or 0)
            tinsert(skills, {label = name .. "  " .. seen[key], key = key})
        end
        if #skills > 0 and (not page.online:GetChecked() or member.online) then
            local status = member.online and GuildHelper:Trans("LID_ONLINE") or (FRIENDS_LIST_OFFLINE or PLAYER_OFFLINE or "")
            local label = member.short .. "  |cffaaaaaa" .. status .. "|r"
            if byRecipe then
                for key in pairs(seen) do
                    if not page.filter or page.filter == key then
                        local known = data and data.recipes and data.recipes[tostring(key)]
                        if known then captured = true else missing = true end
                        if query ~= "" then
                            for id, materials in pairs(known or {}) do
                                local recipe = Recipes:Name(id)
                                if strlower(recipe):find(query, 1, true) then
                                    tinsert(results, {
                                        key = member.name .. ":" .. id,
                                        label = recipe .. "   " .. label,
                                        member = member,
                                        recipe = recipe,
                                        id = id,
                                        materials = materials
                                    })
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
    table.sort(results, function(a, b)
        if a.member.online ~= b.member.online then return a.member.online end
        if a.recipe ~= b.recipe then return a.recipe < b.recipe end
        return a.key < b.key
    end)
    local total = #results
    for index = total, 101, -1 do results[index] = nil end
    local selected
    for _, result in ipairs(results) do
        if result.key == page.selected then selected = result end
    end
    selected = selected or results[1]
    page.selected = selected and selected.key
    page.member = selected and selected.member
    page.empty:SetText(GuildHelper:Trans(byRecipe and (query == "" and "LID_RECIPESEARCH" or "LID_RECIPENOMATCH") or "LID_NODATA"))
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
        page.selected = key
        page.details.scroll:SetVerticalScroll(0)
        self:Update()
    end, page.selected)
    local details = selected and selected.skills or {}
    if selected and selected.id then
        details = Recipes:Materials(selected.id, selected.materials) or {{label = GuildHelper:Trans("LID_NODATA")}}
        tinsert(details, 1, {label = selected.recipe})
    end
    self:ShowRows(page.details, details)
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
    local label = Theme:Text(page, 13, "text")
    Theme:SetTrans(label, "LID_NAME")
    label:SetPoint("TOPLEFT", 2, -12)
    page.search = GuildHelper.Groups:CreateBox(page, 80)
    page.search:SetPoint("LEFT", label, "RIGHT", 10, 0)
    page.search:SetWidth(240)
    page.search:SetScript("OnTextChanged", function()
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
        Theme:SetTrans(label, button:GetChecked() and "LID_RECIPE" or "LID_NAME")
        page.selected = nil
        page.search:SetText("")
        page.results.scroll:SetVerticalScroll(0)
        page.details.scroll:SetVerticalScroll(0)
        if button:GetChecked() then Recipes:Request() end
        self:Update()
    end)

    page.filters = self:CreateList(page)
    page.filters:SetPoint("TOPLEFT", 0, -44)
    page.filters:SetPoint("BOTTOMLEFT", 0, 26)
    page.filters:SetWidth(214)
    page.details = self:CreateList(page)
    page.details:SetPoint("TOPRIGHT", 0, -44)
    page.details:SetPoint("BOTTOMRIGHT", 0, 40)
    page.details:SetWidth(244)
    page.results = self:CreateList(page)
    page.results:SetPoint("TOPLEFT", page.filters, "TOPRIGHT", 8, 0)
    page.results:SetPoint("BOTTOMRIGHT", page.details, "BOTTOMLEFT", -8, -14)

    page.empty = Theme:Text(page.results, 13, "muted")
    page.notice = Theme:Text(page, 12, "muted")
    page.notice:SetPoint("BOTTOMLEFT", 2, 5)
    page.notice:SetPoint("BOTTOMRIGHT", page.results, "BOTTOMRIGHT", 0, -16)
    page.notice:SetJustifyH("LEFT")
    page.empty:SetPoint("CENTER")
    page.whisper = Members:CreateButton(page, "LID_WHISPER", true)
    page.whisper:SetWidth(180)
    page.whisper:SetPoint("BOTTOMRIGHT")
    page.whisper:SetScript("OnClick", function() Members:Whisper(page.member) end)
    content.OnPageShow = function()
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
