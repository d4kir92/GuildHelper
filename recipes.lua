local _, GuildHelper = ...
local Sync = GuildHelper.Sync
local Trade = C_TradeSkillUI
local Recipes = {pending = {}, sent = {}, names = {}, itemRequests = {}, bindingRequests = {}, icons = {}, outputs = {}, materialSearch = {}, verifiedTokenPrefix = "0"}
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

function Recipes:Output(id)
    local outputs = GHTAB and GHTAB.RECIPEOUTPUTS
    if outputs and outputs[id] ~= nil then return outputs[id] end
    if self.outputs[id] ~= nil then return self.outputs[id] end
    if Trade and Trade.GetRecipeSchematic then
        local ok, schematic = pcall(Trade.GetRecipeSchematic, id, false)
        if ok and schematic then
            local output = schematic.outputItemID
            if output == 0 then output = nil end
            local itemType = Enum and Enum.TradeskillRecipeType and Enum.TradeskillRecipeType.Item or 1
            if not output and schematic.recipeType ~= itemType then output = 0 end
            self.outputs[id] = output
            return output
        end
    end
end

function Recipes:CanShare(id, key)
    local item = self:Output(id)
    if item == 0 then return true end
    if not item then return end
    local getInfo = C_Item and C_Item.GetItemInfo or GetItemInfo
    if not getInfo then return end
    local binding = select(14, getInfo(item))
    if binding == nil then
        self.bindingRequests[item] = self.bindingRequests[item] or {}
        if key then self.bindingRequests[item][key] = true end
        return
    end
    local onAcquire = Enum and Enum.ItemBind and Enum.ItemBind.OnAcquire or 1
    return binding ~= onAcquire
end

function Recipes:CanSee(data, key, id)
    local shareable = self:CanShare(id)
    if shareable ~= nil then return shareable end
    return data.recipeVerified and data.recipeVerified[key]
end

function Recipes:CanOrder(data, id)
    for key, recipes in pairs(data and data.recipes or {}) do
        if recipes[id] ~= nil and self:CanSee(data, key, id) then return true end
    end
    return false
end

function Recipes:Icon(id)
    if self.icons[id] then return self.icons[id] end
    local item = self:Output(id)
    local getIcon = C_Item and C_Item.GetItemIconByID or GetItemIcon
    local icon = item and item > 0 and getIcon and getIcon(item)
    if not icon then
        local getSpellIcon = C_Spell and C_Spell.GetSpellTexture or GetSpellTexture
        if getSpellIcon then icon = getSpellIcon(id) end
    end
    self.icons[id] = icon
    return icon or 134400
end

function Recipes:IsNewer(token, previous)
    if not previous then return true end
    local stamp, serial = token:match("^(%d+)%.(%d+)$")
    local oldStamp, oldSerial = previous:match("^(%d+)%.(%d+)$")
    stamp, oldStamp = tonumber(stamp), tonumber(oldStamp)
    return stamp > oldStamp or (stamp == oldStamp and tonumber(serial) > tonumber(oldSerial))
end

function Recipes:NextToken(entry)
    local stamp, serial = time(), 1
    if entry.recipeClock then
        local oldStamp, oldSerial = entry.recipeClock:match("^(%d+)%.(%d+)$")
        oldStamp = tonumber(oldStamp)
        if oldStamp >= stamp then stamp, serial = oldStamp, tonumber(oldSerial) + 1 end
    end
    entry.recipeClock = format("%d.%d", stamp, serial)
    return entry.recipeClock
end

function Recipes:Prune(entry, professions, own)
    if not entry or not entry.recipes then return end
    local active = {}
    for _, profession in ipairs(professions) do
        active[tostring(Sync:GetProfessionID(profession[1], profession[4]) or profession[1])] = true
    end
    local changed = false
    for key in pairs(entry.recipes) do
        if not active[key] then
            entry.recipes[key] = nil
            if entry.recipeVerified then entry.recipeVerified[key] = nil end
            changed = true
            if own then
                entry.recipeRemovals = entry.recipeRemovals or {}
                local token = self:NextToken(entry)
                entry.recipeRemovals[key] = token
                self:SendRemoval(key, token)
            end
        end
    end
    return changed
end

function Recipes:SendRemoval(key, token)
    local guild = Sync:GetGuildKey()
    if guild then Sync:Send(format("P!~%s~%s", key, token), nil, nil, guild) end
end

function Recipes:ReplayRemovals(entry)
    for key, token in pairs(entry and entry.recipeRemovals or {}) do
        self:SendRemoval(key, token)
    end
end

function Recipes:Publish(key, recipes, response)
    local guild = Sync:GetGuildKey()
    if not guild then return end
    local records, packets = {}, {}
    for id, materials in pairs(recipes) do
        if self:CanShare(id, key) then
            tinsert(records, tostring(id) .. (materials ~= true and ":" .. materials or ""))
        end
    end
    table.sort(records)
    local payload = ""
    local limit = (response and 175 or 205) - #key
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
    local name = Sync:GetOwnName()
    local entry = name and Sync:GetEntry(name)
    if not entry then return end
    local token = self.verifiedTokenPrefix .. self:NextToken(entry)
    for index, packet in ipairs(packets) do
        local message = format("P~%s~%s~%d~%d~%s", key, token, index, #packets, packet)
        if response then
            tinsert(response, message)
        else
            Sync:Send(message, nil, nil, guild)
        end
    end
    return #records
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
        self:ReplayRemovals(data)
        local sent = self.sent[guild] or {}
        for key, recipes in pairs(data and data.recipes or {}) do
            if not sent[key] or GetTime() - sent[key] >= 300 then self:Publish(key, recipes) end
        end
    end)
end

function Recipes:PlayerRequestKey(name)
    local guild = Sync:GetGuildKey()
    return guild and (guild .. "~" .. Sync:GetKey(name))
end

function Recipes:RequestPlayer(member)
    if not member or not member.online or GuildHelper.Members:IsSelf(member) then return end
    local key = self:PlayerRequestKey(member.short)
    if not key then return end
    local cooldowns = GuildHelper:GetConfig("RECIPE_REQUEST_TIMES", {})
    local now = time()
    if cooldowns[key] and now - cooldowns[key] < 3600 then return end
    for target, stamp in pairs(cooldowns) do
        if now - stamp >= 3600 then cooldowns[target] = nil end
    end
    cooldowns[key] = now
    self.playerRequests = self.playerRequests or {}
    local request = {id = format("%d.%09d", now, random(1, 999999999)), received = 0, deadline = GetTime() + 120, status = "waiting", seen = {}}
    self.playerRequests[key] = request
    local function expire()
        if self.playerRequests[key] ~= request or (request.status ~= "waiting" and request.status ~= "receiving") then return end
        local remaining = request.deadline - GetTime()
        if remaining > 0 then
            C_Timer.After(remaining, expire)
        else
            request.status = request.total and "incomplete" or "timeout"
            request.seen = nil
            if self.onProgress then self.onProgress() end
        end
    end
    C_Timer.After(120, expire)
    Sync:Send(format("P?~%s~%s", Sync:GetKey(member.short), request.id), nil, nil, Sync:GetGuildKey())
    if self.onProgress then self.onProgress() end
end

function Recipes:RespondToPlayer(sender, target, id)
    local own = Sync:GetOwnName()
    if not own or Sync:GetKey(own) ~= target then return end
    local key = self:PlayerRequestKey(sender)
    if not key then return end
    self.playerAnswers = self.playerAnswers or {}
    local now = GetTime()
    if self.playerAnswers[key] and now - self.playerAnswers[key] < 3600 then return end
    self.playerAnswers[key] = now
    local guild = Sync:GetGuildKey()
    local data = Sync:GetData(own)
    local packets = {}
    for skill, token in pairs(data and data.recipeRemovals or {}) do
        tinsert(packets, format("P!~%s~%s", skill, token))
    end
    local shared = 0
    for skill, recipes in pairs(data and data.recipes or {}) do
        if (self:Publish(skill, recipes, packets) or 0) > 0 then shared = shared + 1 end
    end
    Sync:Send(format("PA~%s~%d~%d", id, #packets, shared), nil, nil, guild)
    for _, packet in ipairs(packets) do
        Sync:Send(format("PX~%s~%s", id, packet), nil, nil, guild)
    end
end

function Recipes:ReceivePlayerResponse(sender, id, total, shared, packet)
    local key = self:PlayerRequestKey(sender)
    local request = self.playerRequests and self.playerRequests[key]
    if not request or request.id ~= id then return end
    if total then
        if request.status ~= "waiting" or total > 4096 or shared > total then return end
        request.total, request.shared = total, shared
        request.status = total > 0 and "receiving" or "empty"
    else
        if request.status ~= "receiving" or request.seen[packet] then return end
        if not packet:match("^P[!~]") or not self:OnMessage(packet, sender, true) then return end
        request.seen[packet] = true
        request.received = request.received + 1
        if request.received == request.total then request.status = request.shared > 0 and "complete" or "empty" end
    end
    request.deadline = GetTime() + 120
    if request.status ~= "receiving" then request.seen = nil end
    if self.onProgress then self.onProgress() end
end

function Recipes:StoreSnapshot(sender, key, token, recipes)
    local entry = Sync:GetEntry(sender)
    if not entry then return end
    entry.recipeVersions = entry.recipeVersions or {}
    entry.recipeVersions[key] = token
    entry.recipeVerified = entry.recipeVerified or {}
    entry.recipeVerified[key] = recipes ~= nil and token:sub(1, 1) == self.verifiedTokenPrefix or nil
    entry.recipes = entry.recipes or {}
    local previous = entry.recipes[key]
    entry.recipes[key] = recipes
    if previous or recipes then Sync:Notify() end
end

function Recipes:OnMessage(message, sender, response)
    if #message > 255 then return end
    if not response then
        if message == "P?" then return self:Respond() end
        local target, id = message:match("^P%?~([^~]+)~(%d+%.%d+)$")
        if target and #id <= 23 then return self:RespondToPlayer(sender, target, id) end
        local ack, total, shared = message:match("^PA~(%d+%.%d+)~(%d+)~(%d+)$")
        if ack then return self:ReceivePlayerResponse(sender, ack, tonumber(total), tonumber(shared)) end
        local transfer, packet = message:match("^PX~(%d+%.%d+)~(.+)$")
        if transfer then return self:ReceivePlayerResponse(sender, transfer, nil, nil, packet) end
    end
    local removedKey, removedToken = message:match("^P!~([^~]+)~(%d+%.%d+)$")
    if removedKey then
        local entry = Sync:GetData(sender)
        local applied = entry and entry.recipeVersions and entry.recipeVersions[removedKey]
        if #removedKey <= 60 and #message <= 255 and self:IsNewer(removedToken, applied) then
            self:StoreSnapshot(sender, removedKey, removedToken, nil)
        end
        return #removedKey <= 60
    end
    local key, token, part, total, payload = message:match("^P~([^~]+)~(%d+%.%d+)~(%d+)~(%d+)~([%d:.,%-]*)$")
    part, total = tonumber(part), tonumber(total)
    if not key or #key > 60 or not part or not total or total > 256 or part < 1 or part > total or #message > 255 then return end
    local guild = Sync:GetGuildKey()
    if not guild then return end
    if self.pendingGuild ~= guild then
        self.pendingGuild = guild
        wipe(self.pending)
    end
    local entry = Sync:GetData(sender)
    local applied = entry and entry.recipeVersions and entry.recipeVersions[key]
    if not self:IsNewer(token, applied) then return true end
    local bucket = Sync:GetKey(sender) .. "~" .. key
    local pending = self.pending[bucket]
    if pending and pending.token ~= token and not self:IsNewer(token, pending.token) then return true end
    if not pending or pending.token ~= token or GetTime() - pending.started > 600 then
        pending = {token = token, total = total, started = GetTime(), parts = {}, count = 0}
        self.pending[bucket] = pending
    end
    if pending.total ~= total or pending.parts[part] then return end
    pending.parts[part] = payload
    pending.count = pending.count + 1
    if pending.count ~= total then return true end
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
    self:StoreSnapshot(sender, key, token, recipes)
    return true
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
                local getItem = craft and GetCraftItemLink or GetTradeSkillItemLink
                local itemLink = getItem and getItem(index)
                local output = itemLink and tonumber(itemLink:match("|Hitem:(%d+)"))
                local getIcon = C_Item and C_Item.GetItemIconByID or GetItemIcon
                if output or (craft and getItem) then
                    GHTAB = GHTAB or {}
                    GHTAB.RECIPEOUTPUTS = GHTAB.RECIPEOUTPUTS or {}
                    GHTAB.RECIPEOUTPUTS[id] = output or 0
                end
                if output and getIcon then self.icons[id] = getIcon(output) or self.icons[id] end
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

function Recipes:QueueItemRefresh(keys)
    self.bindingKeys = self.bindingKeys or {}
    for key in pairs(keys or {}) do self.bindingKeys[key] = true end
    if self.bindingPending then return end
    self.bindingPending = true
    local guild = Sync:GetGuildKey()
    C_Timer.After(0.5, function()
        local updates = self.bindingKeys
        self.bindingKeys, self.bindingPending = nil, nil
        if not guild or guild ~= Sync:GetGuildKey() then return end
        local name = Sync:GetOwnName()
        local data = name and Sync:GetData(name)
        for key in pairs(updates) do
            local recipes = data and data.recipes and data.recipes[key]
            if recipes then self:Publish(key, recipes) end
        end
        if self.onItemLoaded then self.onItemLoaded() end
    end)
end

function Recipes:ItemName(id)
    local getInfo = C_Item and C_Item.GetItemInfo or GetItemInfo
    local name = getInfo and getInfo(id)
    if not name then self.itemRequests[id] = true end
    return name or ("#" .. id), name ~= nil
end

function Recipes:OutputDisplay(id)
    local item = self:Output(id)
    if item and item > 0 then
        local name, loaded = self:ItemName(item)
        return loaded and name or self:Name(id), self:MaterialIcon(item)
    end
    return self:Name(id), self:Icon(id)
end

function Recipes:OutputLink(id)
    local item = self:Output(id)
    local link
    if Trade and Trade.GetRecipeOutputItemData then
        local ok, output = pcall(Trade.GetRecipeOutputItemData, id)
        local hyperlink = ok and output and output.hyperlink
        if hyperlink and hyperlink:find("|Hitem:", 1, true) then link = hyperlink end
    end
    return link or (item and item > 0 and ("item:" .. item))
end

function Recipes.ShowTooltip(owner)
    local material, recipe = owner.ghTooltipMaterial, owner.ghTooltipRecipe
    local link = recipe and Recipes:OutputLink(recipe)
    local currency = material and material < 0 and GameTooltip.SetCurrencyByID and -material
    if material and material > 0 then link = "item:" .. material end
    if not link and not currency then return end
    if not GameTooltip:IsOwned(owner) then GameTooltip:SetOwner(owner, "ANCHOR_RIGHT") end
    if currency then
        GameTooltip:SetCurrencyByID(currency)
    else
        GameTooltip:SetHyperlink(link)
    end
    GameTooltip:Show()
end

function Recipes:SetTooltip(owner, recipe, material)
    if owner.ghTooltipRecipe == recipe and owner.ghTooltipMaterial == material then return end
    owner.ghTooltipRecipe, owner.ghTooltipMaterial = recipe, material
    if (recipe or material) and not owner.ghTooltipBound then
        owner.ghTooltipBound = true
        owner:HookScript("OnEnter", Recipes.ShowTooltip)
        local function hideTooltip(frame)
            if GameTooltip:IsOwned(frame) then GameTooltip:Hide() end
        end
        owner:HookScript("OnLeave", hideTooltip)
        owner:HookScript("OnHide", hideTooltip)
        if not GameTooltip.supportsItemComparison then owner.UpdateTooltip = Recipes.ShowTooltip end
    end
    if GameTooltip:IsOwned(owner) then
        GameTooltip:Hide()
        Recipes.ShowTooltip(owner)
    end
end

function Recipes:Requirements(id, materials)
    local requirements = {}
    if materials == true then
        if not Trade or not Trade.GetRecipeSchematic then return end
        local ok, schematic = pcall(Trade.GetRecipeSchematic, id, false)
        if not ok then return end
        if not schematic or not schematic.reagentSlotSchematics then return end
        for _, slot in ipairs(schematic.reagentSlotSchematics) do
            if slot.required and not slot.hiddenInCraftingForm then
                local options = {}
                for _, reagent in ipairs(slot.reagents) do
                    if reagent.itemID then
                        tinsert(options, reagent.itemID)
                    elseif reagent.currencyID then
                        tinsert(options, -reagent.currencyID)
                    end
                end
                if #options == 0 then return end
                tinsert(requirements, {quantity = slot.quantityRequired, options = options})
            end
        end
    elseif type(materials) == "string" and materials ~= "-" then
        for item, quantity in materials:gmatch("(%d+)%.(%d+)") do
            tinsert(requirements, {quantity = tonumber(quantity), options = {tonumber(item)}})
        end
    else
        return
    end
    return requirements
end

function Recipes:MaterialIcon(id)
    if id > 0 then
        local getIcon = C_Item and C_Item.GetItemIconByID or GetItemIcon
        if getIcon then return getIcon(id) or 134400 end
    else
        local currency = C_CurrencyInfo and C_CurrencyInfo.GetCurrencyInfo(-id)
        if currency then return currency.iconFileID or 134400 end
    end
    return 134400
end

function Recipes:MaterialNames(requirement)
    local names, seen, ids, complete = {}, {}, {}, true
    for _, id in ipairs(requirement.options) do
        local name
        if id > 0 then
            local loaded
            name, loaded = self:ItemName(id)
            if not loaded then complete = false end
        else
            local currency = C_CurrencyInfo and C_CurrencyInfo.GetCurrencyInfo(-id)
            name = currency and currency.name or ("#" .. -id)
            if not currency or not currency.name then complete = false end
        end
        if not seen[id] then
            seen[id] = true
            tinsert(names, name)
            tinsert(ids, id)
        end
    end
    return names, ids, complete
end

function Recipes:MatchesMaterials(id, materials, query)
    local cached = self.materialSearch[id]
    if cached and cached.materials == materials then return cached.text:find(query, 1, true) ~= nil end
    local requirements = self:Requirements(id, materials)
    if not requirements then return false end
    local terms, complete = {}, true
    for _, requirement in ipairs(requirements) do
        local names, _, loaded = self:MaterialNames(requirement)
        if not loaded then complete = false end
        tinsert(terms, table.concat(names, "\n"))
    end
    local text = strlower(table.concat(terms, "\n"))
    if complete then self.materialSearch[id] = {materials = materials, text = text} end
    return text:find(query, 1, true) ~= nil
end

function Recipes:Materials(id, materials)
    local requirements = self:Requirements(id, materials)
    if not requirements then return end
    local rows = {}
    for _, requirement in ipairs(requirements) do
        local names, ids = self:MaterialNames(requirement)
        tinsert(rows, {label = names[1], prefix = format("%dx", requirement.quantity), material = ids[1]})
        for index = 2, #names do
            tinsert(rows, {label = names[index], prefix = "/", material = ids[index]})
        end
    end
    return rows, requirements
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
        local keys = Recipes.bindingRequests[itemID]
        local requested = Recipes.itemRequests[itemID]
        Recipes.bindingRequests[itemID], Recipes.itemRequests[itemID] = nil, nil
        if success and (keys or requested) then Recipes:QueueItemRefresh(keys) end
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
