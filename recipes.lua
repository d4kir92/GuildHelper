local _, GuildHelper = ...
local Sync = GuildHelper.Sync
local Trade = C_TradeSkillUI
local Recipes = {pending = {}, sent = {}, names = {}, itemRequests = {}, serial = 0}
GuildHelper.Recipes = Recipes

function Recipes:Name(id)
    if self.names[id] then return self.names[id] end
    local name = C_Spell and C_Spell.GetSpellName and C_Spell.GetSpellName(id) or GetSpellInfo and GetSpellInfo(id)
    if not name and Trade and Trade.GetRecipeInfo then
        local info = Trade.GetRecipeInfo(id)
        name = info and info.name
    end
    self.names[id] = name
    return name or tostring(id)
end

function Recipes:Publish(key, recipes)
    local guild = Sync:GetGuildKey()
    if not guild then return end
    local records, packets = {}, {}
    for id, materials in pairs(recipes) do
        tinsert(records, tostring(id) .. (materials ~= true and ":" .. materials or ""))
    end
    table.sort(records)
    local payload = ""
    local limit = 205 - #key
    for _, record in ipairs(records) do
        if #record > limit then return end
        if #payload + #record + 1 > limit then
            tinsert(packets, payload)
            payload = ""
        end
        payload = payload == "" and record or payload .. "," .. record
    end
    tinsert(packets, payload)
    if #packets > 256 then return end
    self.serial = self.serial + 1
    local token = tostring(time()) .. "." .. tostring(self.serial)
    for index, packet in ipairs(packets) do
        Sync:Send(format("P~%s~%s~%d~%d~%s", key, token, index, #packets, packet), nil, nil, guild)
    end
end

function Recipes:Request()
    local guild = Sync:GetGuildKey()
    local now = GetTime()
    if not guild or (self.requestGuild == guild and now - self.requestTime < 300) then return end
    self.requestGuild, self.requestTime = guild, now
    Sync:Send("P?", nil, nil, guild)
end

function Recipes:Respond()
    local guild = Sync:GetGuildKey()
    if not guild or (self.responseGuild == guild and GetTime() - self.responseTime < 300) then return end
    self.responseGuild, self.responseTime = guild, GetTime()
    C_Timer.After(random(2, 12), function()
        if Sync:GetGuildKey() ~= guild then return end
        local name = Sync:GetOwnName()
        local data = name and Sync:GetData(name)
        local sent = self.sent[guild] or {}
        for key, recipes in pairs(data and data.recipes or {}) do
            if not sent[key] or GetTime() - sent[key] >= 300 then self:Publish(key, recipes) end
        end
    end)
end

function Recipes:OnMessage(message, sender)
    if message == "P?" then return self:Respond() end
    local key, token, part, total, payload = message:match("^P~([^~]+)~(%d+%.%d+)~(%d+)~(%d+)~([%d:.,%-]*)$")
    part, total = tonumber(part), tonumber(total)
    if not key or #key > 60 or not part or not total or total > 256 or part < 1 or part > total or #message > 255 then return end
    local guild = Sync:GetGuildKey()
    if not guild then return end
    if self.pendingGuild ~= guild then
        self.pendingGuild = guild
        wipe(self.pending)
    end
    local bucket = sender .. "~" .. key
    local pending = self.pending[bucket]
    if not pending or pending.token ~= token or GetTime() - pending.started > 600 then
        pending = {token = token, total = total, started = GetTime(), parts = {}, count = 0}
        self.pending[bucket] = pending
    end
    if pending.total ~= total or pending.parts[part] then return end
    pending.parts[part] = payload
    pending.count = pending.count + 1
    if pending.count ~= total then return end
    self.pending[bucket] = nil
    local recipes = {}
    for _, chunk in ipairs(pending.parts) do
        for record in chunk:gmatch("[^,]+") do
            local id, materials = record:match("^(%d+):(.*)$")
            id = tonumber(id or record:match("^%d+$"))
            if not id or id < 1 or id > 2147483647 then return end
            if materials and materials ~= "" and materials ~= "-" and not materials:match("^%d+%.%d+[:%d.]*$") then return end
            recipes[id] = materials or true
        end
    end
    local entry = Sync:GetEntry(sender)
    if not entry then return end
    entry.recipes = entry.recipes or {}
    entry.recipes[key] = recipes
    Sync:Notify()
end

function Recipes:CaptureModern()
    if (Trade.IsNPCCrafting and Trade.IsNPCCrafting()) or (Trade.IsTradeSkillLinked and Trade.IsTradeSkillLinked()) or (Trade.IsTradeSkillGuild and Trade.IsTradeSkillGuild()) then return end
    if Trade.IsTradeSkillReady and not Trade.IsTradeSkillReady() then return end
    local profession = Trade.GetBaseProfessionInfo()
    local key = profession and profession.professionID
    if not key or key <= 0 then return end
    local ids = Trade.GetAllRecipeIDs()
    if not ids or #ids == 0 then return end
    local recipes = {}
    for _, id in ipairs(ids) do
        local info = Trade.GetRecipeInfo(id)
        if not info then return end
        if info.learned then
            self.names[id] = info.name
            recipes[id] = true
        end
    end
    return tostring(key), recipes
end

function Recipes:CaptureClassic(craft)
    local getLine = craft and GetCraftDisplaySkillLine or GetTradeSkillLine
    local getCount = craft and GetNumCrafts or GetNumTradeSkills
    local getInfo = craft and GetCraftInfo or GetTradeSkillInfo
    local getLink = craft and GetCraftRecipeLink or GetTradeSkillRecipeLink
    local getReagentCount = craft and GetCraftNumReagents or GetTradeSkillNumReagents
    local getReagentInfo = craft and GetCraftReagentInfo or GetTradeSkillReagentInfo
    local getReagentLink = craft and GetCraftReagentItemLink or GetTradeSkillReagentItemLink
    if not getLine or not getCount or not getInfo or not getLink or not getReagentCount or not getReagentInfo or not getReagentLink then return end
    if not craft and ((IsTradeSkillLinked and IsTradeSkillLinked()) or (IsTradeSkillGuild and IsTradeSkillGuild())) then return end
    local line, rank = getLine()
    if not line or not rank or rank <= 0 then return end
    local key = tostring(Sync:GetProfessionID(line) or line)
    if #key > 60 or key:find("~", 1, true) then return end
    local recipes = {}
    for index = 1, getCount() do
        local name, kind, craftKind = getInfo(index)
        if craft then kind = craftKind end
        if name and kind and kind ~= "header" and kind ~= "subheader" and kind ~= "unlearned" and kind ~= "unavailable" then
            local link = getLink(index)
            local id = link and tonumber(link:match("|Henchant:(%d+)") or link:match("|Hspell:(%d+)") or link:match("|Htrade:(%d+)"))
            if id then
                self.names[id] = name
                local materials = {}
                for reagent = 1, getReagentCount(index) do
                    local _, _, quantity = getReagentInfo(index, reagent)
                    local reagentLink = getReagentLink(index, reagent)
                    local item = reagentLink and tonumber(reagentLink:match("|Hitem:(%d+)"))
                    if not item or not quantity then
                        materials = nil
                        break
                    end
                    tinsert(materials, format("%d.%d", item, quantity))
                end
                recipes[id] = materials and table.concat(materials, ":") or "-"
            end
        end
    end
    if not next(recipes) then return end
    return key, recipes
end

function Recipes:Capture(craft)
    local guild = Sync:GetGuildKey()
    local name = guild and Sync:GetOwnName()
    if not name then return end
    local modern = not craft and Trade and Trade.GetBaseProfessionInfo and Trade.GetAllRecipeIDs and Trade.GetRecipeInfo
    local key, recipes
    if modern then
        key, recipes = self:CaptureModern()
    else
        key, recipes = self:CaptureClassic(craft)
    end
    if not key then return end
    local entry = Sync:GetEntry(name)
    if not entry then return end
    entry.recipes = entry.recipes or {}
    local previous = entry.recipes[key] or {}
    local changed = entry.recipes[key] == nil
    if not modern then
        for id, materials in pairs(previous) do
            if recipes[id] == nil or recipes[id] == "-" then recipes[id] = materials end
        end
    end
    for id, materials in pairs(recipes) do
        if previous[id] ~= materials then changed = true end
    end
    for id in pairs(previous) do
        if recipes[id] == nil then changed = true end
    end
    entry.recipes[key] = recipes
    self.sent[guild] = self.sent[guild] or {}
    local sent = self.sent[guild]
    if changed or not sent[key] or GetTime() - sent[key] >= 300 then
        self:Publish(key, recipes)
        sent[key] = GetTime()
    end
    if changed then Sync:Notify() end
end

function Recipes:ItemName(id)
    local getInfo = C_Item and C_Item.GetItemInfo or GetItemInfo
    local name = getInfo and getInfo(id)
    if not name then self.itemRequests[id] = true end
    return name or ("#" .. id)
end

function Recipes:Materials(id, materials)
    local rows = {}
    wipe(self.itemRequests)
    if materials == true then
        if not Trade or not Trade.GetRecipeSchematic then return end
        local ok, schematic = pcall(Trade.GetRecipeSchematic, id, false)
        if not ok then return end
        if not schematic or not schematic.reagentSlotSchematics then return end
        for _, slot in ipairs(schematic.reagentSlotSchematics) do
            if slot.required and not slot.hiddenInCraftingForm then
                local options, seen = {}, {}
                for _, reagent in ipairs(slot.reagents) do
                    local name
                    if reagent.itemID then
                        name = self:ItemName(reagent.itemID)
                    elseif reagent.currencyID then
                        local currency = C_CurrencyInfo and C_CurrencyInfo.GetCurrencyInfo(reagent.currencyID)
                        name = currency and currency.name or ("#" .. reagent.currencyID)
                    end
                    if name and not seen[name] then
                        tinsert(options, name)
                        seen[name] = true
                    end
                end
                if #options == 0 then return end
                tinsert(rows, {label = format("%d x %s", slot.quantityRequired, options[1])})
                for index = 2, #options do
                    tinsert(rows, {label = "    / " .. options[index]})
                end
            end
        end
    elseif materials ~= "-" then
        for item, quantity in materials:gmatch("(%d+)%.(%d+)") do
            tinsert(rows, {label = quantity .. " x " .. self:ItemName(tonumber(item))})
        end
    else
        return
    end
    return rows
end

local events = CreateFrame("Frame")
local function Register(event)
    if not C_EventUtils or not C_EventUtils.IsEventValid or C_EventUtils.IsEventValid(event) then
        pcall(events.RegisterEvent, events, event)
    end
end

Register("TRADE_SKILL_SHOW")
Register("TRADE_SKILL_LIST_UPDATE")
Register("TRADE_SKILL_UPDATE")
Register("CRAFT_SHOW")
Register("CRAFT_UPDATE")
Register("TRADE_SKILL_CLOSE")
Register("CRAFT_CLOSE")
Register("GET_ITEM_INFO_RECEIVED")
events:SetScript("OnEvent", function(_, event, itemID, success)
    if event == "GET_ITEM_INFO_RECEIVED" then
        if Recipes.itemRequests[itemID] then
            Recipes.itemRequests[itemID] = nil
            if success and Recipes.onItemLoaded then Recipes.onItemLoaded() end
        end
        return
    end
    if event == "TRADE_SKILL_CLOSE" or event == "CRAFT_CLOSE" then
        Recipes.capture = nil
        return
    end
    local capture = event
    Recipes.capture = capture
    if Recipes.scanPending then return end
    Recipes.scanPending = true
    C_Timer.After(0.25, function()
        Recipes.scanPending = false
        local latest = Recipes.capture
        if latest then Recipes:Capture(latest:sub(1, 6) == "CRAFT_") end
    end)
end)
