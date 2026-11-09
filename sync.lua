local _, GuildHelper = ...
local Sync = {}
GuildHelper.Sync = Sync
Sync.PREFIX = "GuildHelper"
Sync.SEND_THROTTLE = 15
Sync.ANSWER_THROTTLE = 120
Sync.lastSend = 0
Sync.listeners = {}
Sync.BURST = 1
Sync.MAXTRIES = 20
Sync.tokens = Sync.BURST
Sync.queue = {}
Sync.pump = CreateFrame("Frame")
Sync.pump:SetScript("OnUpdate", function(_, elapsed) Sync:Pump(elapsed) end)
function Sync:GetGuildKey()
    if not IsInGuild() then return nil end
    local guild = GetGuildInfo("player")
    if guild == nil then return nil end

    return guild .. "-" .. (GetRealmName() or "")
end

function Sync:GetStore()
    local key = self:GetGuildKey()
    if key == nil then return nil end
    GHTAB = GHTAB or {}
    GHTAB.MEMBERDATA = GHTAB.MEMBERDATA or {}
    GHTAB.MEMBERDATA[key] = GHTAB.MEMBERDATA[key] or {}

    return GHTAB.MEMBERDATA[key]
end

function Sync:GetData(shortName)
    local store = self:GetStore()
    if store == nil or shortName == nil then return nil end

    return store[self:GetKey(shortName)] or store[strlower(strsplit("-", shortName))]
end

function Sync:GetKey(name)
    local shortName = strsplit("-", name)
    if GuildHelper:IsForever() then shortName = shortName:match("^%S+") or shortName end

    return strlower(shortName)
end

function Sync:OnUpdate(callback)
    tinsert(self.listeners, callback)
end

function Sync:Notify()
    for _, callback in ipairs(self.listeners) do
        callback()
    end
end

function Sync:GetOwnItemLevel()
    if GetAverageItemLevel then
        local _, equipped = GetAverageItemLevel()
        if equipped and equipped > 0 then return floor(equipped) end
    end

    local value = GuildHelper:GetInspectILvl("player")
    if value and value > 0 then return floor(value) end

    return nil
end

Sync.professionIDs = {
    [129] = "First Aid", [164] = "Blacksmithing", [165] = "Leatherworking",
    [171] = "Alchemy", [182] = "Herbalism", [185] = "Cooking", [186] = "Mining",
    [197] = "Tailoring", [202] = "Engineering", [333] = "Enchanting", [356] = "Fishing",
    [393] = "Skinning", [755] = "Jewelcrafting", [773] = "Inscription", [794] = "Archaeology",
}

function Sync:GetProfessionName(id, fallback)
    if id and C_TradeSkillUI then
        local name
        if C_TradeSkillUI.GetTradeSkillDisplayName then
            name = C_TradeSkillUI.GetTradeSkillDisplayName(id)
        elseif C_TradeSkillUI.GetProfessionInfoBySkillLineID then
            local info = C_TradeSkillUI.GetProfessionInfoBySkillLineID(id)
            name = info and info.professionName
        end

        if name and name ~= "" then return name end
    end

    return fallback
end

function Sync:GetProfessionID(name)
    for id, englishName in pairs(self.professionIDs) do
        if name == englishName or name == self:GetProfessionName(id) then return id end
    end
end

function Sync:GetOwnProfessions()
    local list = {}
    if GetProfessions and GetProfessionInfo then
        local indices = {GetProfessions()}
        for i = 1, 5 do
            local index = indices[i]
            if index then
                local name, _, rank, maxRank, _, _, skillLineID = GetProfessionInfo(index)
                if name then
                    tinsert(list, {name, rank or 0, maxRank or 0, skillLineID or self:GetProfessionID(name)})
                end
            end
        end

        return list
    end

    if GetNumSkillLines == nil then return list end
    local header = nil
    for i = 1, GetNumSkillLines() do
        local name, isHeader, _, rank, _, _, maxRank = GetSkillLineInfo(i)
        if isHeader then
            header = name
        elseif name and (header == TRADE_SKILLS or (SECONDARY_SKILLS and header == SECONDARY_SKILLS)) then
            tinsert(list, {name, rank or 0, maxRank or 0, self:GetProfessionID(name)})
        end
    end

    return list
end

function Sync:BuildInfo()
    local parts = {"I", tostring(self:GetOwnItemLevel() or 0)}
    for _, prof in ipairs(self:GetOwnProfessions()) do
        tinsert(parts, format("%s;%d;%d;%s", prof[1], prof[2], prof[3], tostring(prof[4] or "")))
    end

    return table.concat(parts, "~")
end

function Sync:GetEntry(shortName)
    local store = self:GetStore()
    if store == nil then return nil end
    local key = self:GetKey(shortName)
    store[key] = store[key] or {}
    store[key].time = time()

    return store[key]
end

function Sync:Store(shortName, ilvl, professions)
    local entry = self:GetEntry(shortName)
    if entry == nil then return end
    entry.ilvl = ilvl and ilvl > 0 and ilvl or nil
    entry.professions = professions
    self:Notify()
end

function Sync:Trace(...)
    if self.debug then print("[GuildHelper Sync]", ...) end
end

function Sync:BuildSpecs()
    local parts = {"S", GuildHelper.Specs:GetMainName() or ""}
    for _, entry in ipairs(GuildHelper.Specs:GetOwn()) do
        tinsert(parts, format("%s;%s;%s", entry.role or "", entry.spec or "", tostring(entry.icon or "")))
    end

    return table.concat(parts, "~")
end

function Sync:ParseSpecs(shortName, message)
    local entry = self:GetEntry(shortName)
    if entry == nil then return end
    local parts = {strsplit("~", message)}
    local specs = {}
    for slot = 1, #GuildHelper.Specs.SLOTS do
        local role, spec, icon = strsplit(";", parts[slot + 2] or "")
        specs[slot] = {
            role = role or "",
            spec = spec or "",
            icon = tonumber(icon) or (icon ~= "" and icon or nil)
        }
    end

    entry.main = parts[2] or ""
    self:Trace("S", shortName, "Main:", entry.main ~= "" and entry.main or "(leer)")
    entry.specs = specs
    if parts[#GuildHelper.Specs.SLOTS + 3] ~= nil then entry.twitch = parts[#GuildHelper.Specs.SLOTS + 3] end
    self:Notify()
end

function Sync:SendSpecs()
    local message = self:BuildSpecs()
    self:ParseSpecs(UnitName("player"), message)
    local entry = self:GetEntry(UnitName("player"))
    if entry then entry.twitch = GuildHelper.Specs:GetTwitch() end
    self:Notify()
    self:Send(message, "S")
    self:Send("T~" .. GuildHelper.Specs:GetTwitch(), "T")
    local main = GuildHelper.Specs:GetMainName()
    self:Trace("Gespeicherter Main:", main or "(leer)", "Gilde:", self:GetGuildKey() or "(keine)")
    self:Send("M~" .. (main or ""), "M")
end

function Sync:Parse(shortName, message)
    local parts = {strsplit("~", message)}
    local professions = {}
    for i = 3, #parts do
        local name, rank, maxRank, skillLineID = strsplit(";", parts[i])
        if name and name ~= "" then
            tinsert(professions, {name, tonumber(rank) or 0, tonumber(maxRank) or 0, tonumber(skillLineID)})
        end
    end

    self:Store(shortName, tonumber(parts[2]), professions)
end

function Sync:Send(message, key, prefix)
    if not IsInGuild() or type(message) ~= "string" or #message > 255 then return end
    for _, item in ipairs(self.queue) do
        if item.prefix == (prefix or self.PREFIX) and ((key and item.key == key) or item.message == message) then
            item.message = message
            item.tries = 0

            return
        end
    end

    tinsert(self.queue, {
        message = message,
        prefix = prefix or self.PREFIX,
        key = key,
        tries = 0
    })

    self:Pump(0)
end

function Sync:Transmit(message, prefix)
    local ok, result = false, nil
    if C_ChatInfo and C_ChatInfo.SendAddonMessage then
        ok, result = pcall(C_ChatInfo.SendAddonMessage, prefix or self.PREFIX, message, "GUILD")
    elseif SendAddonMessage then
        ok, result = pcall(SendAddonMessage, prefix or self.PREFIX, message, "GUILD")
    end

    if (prefix or self.PREFIX) == self.PREFIX and strsub(message, 1, 2) == "M~" then
        self:Trace("Versand:", message, ok and "API-Ergebnis:" or "API-Fehler:", tostring(result))
    end
    if not ok or result == false then return false end
    local codes = Enum and Enum.SendAddonMessageResult
    if type(result) == "number" and codes then return result == codes.Success end

    return true
end

function Sync:Pump(elapsed)
    self.tokens = min(self.BURST, self.tokens + elapsed)
    if #self.queue == 0 then return end
    if not IsInGuild() then
        self.queue = {}

        return
    end

    while self.tokens >= 1 and #self.queue > 0 do
        local item = self.queue[1]
        if not self:Transmit(item.message, item.prefix) then
            item.tries = item.tries + 1
            if item.tries >= self.MAXTRIES then tremove(self.queue, 1) end
            self.tokens = 0

            return
        end

        tremove(self.queue, 1)
        self.tokens = self.tokens - 1
    end
end

function Sync:GetOwnPortraitDisplayID()
    if not SetPortraitTextureFromCreatureDisplayID then return nil end
    if not self.portraitModel then
        self.portraitModel = CreateFrame("PlayerModel", nil, UIParent)
        self.portraitModel:SetSize(1, 1)
        self.portraitModel:SetPoint("CENTER")
        self.portraitModel:SetAlpha(0)
    end

    local model = self.portraitModel
    if not model.GetDisplayInfo then return nil end
    local ok, applied = pcall(model.SetUnit, model, "player")
    if not ok or applied == false then return nil end
    local read, id = pcall(model.GetDisplayInfo, model)
    if read and GuildHelper:CanAccessValues(id) and type(id) == "number" and id > 0 then return id end

    return nil
end

function Sync:SendInfo(force)
    if not IsInGuild() then return end
    local now = GetTime()
    if not force and now - self.lastSend < self.SEND_THROTTLE then
        self:ScheduleInfo(self.SEND_THROTTLE - (now - self.lastSend) + 1)

        return
    end

    self.lastSend = now
    local message = self:BuildInfo()
    self:Parse(UnitName("player"), message)
    self:Send(message, "I")
    self:SendSpecs()
    self:Send(format("A~%d", self:GetOwnPortraitDisplayID() or 0), "A")
end

function Sync:ScheduleInfo(delay)
    if self.pending then return end
    self.pending = true
    C_Timer.After(delay, function()
        Sync.pending = false
        Sync:SendInfo()
    end)
end

function Sync:OnMessage(message, channel, sender)
    if channel ~= "GUILD" or type(message) ~= "string" or type(sender) ~= "string" then return end
    if not GuildHelper:CanAccessValues(message, sender) then
        self:Trace("Gildennachricht vom Client gesperrt")

        return
    end
    if strsub(message, 1, 2) == "F~" and GuildHelper.Groups then
        GuildHelper.Groups:OnMessage(message, sender)

        return
    end
    local shortName = strsplit("-", sender)
    if self:GetKey(shortName) == self:GetKey(UnitName("player") or "") then return end
    local kind = strsub(message, 1, 1)
    if kind == "I" then
        self:Parse(shortName, message)
    elseif kind == "S" then
        self:ParseSpecs(shortName, message)
    elseif kind == "T" then
        local entry = self:GetEntry(shortName)
        if entry then
            entry.twitch = strsub(message, 3)
            self:Notify()
        end
    elseif kind == "M" then
        local entry = self:GetEntry(shortName)
        if entry then
            entry.main = strsub(message, 3)
            self:Trace("M empfangen:", shortName, "Main:", entry.main ~= "" and entry.main or "(leer)")
            self:Notify()
        end
    elseif kind == "A" then
        local rawID = message:match("^A~(%d+)$")
        local id = rawID and #rawID <= 10 and tonumber(rawID)
        if not id or id > 2147483647 then return end
        local entry = self:GetEntry(shortName)
        local displayID = id > 0 and id or nil
        if entry and entry.portraitDisplayID ~= displayID then
            entry.portraitDisplayID = displayID
            self:Notify()
        end
    elseif kind == "Q" then
        self:ScheduleInfo(max(0, self.ANSWER_THROTTLE - (GetTime() - self.lastSend)) + random(2, 12))
    end
end

function Sync:Init()
    GuildHelper:AddSlash("ghsyncdebug", function()
        Sync.debug = not Sync.debug
        print("[GuildHelper Sync]", Sync.debug and "Debug an" or "Debug aus")
        if Sync.debug then
            Sync:SendSpecs()
            Sync:Send("Q")
        end
    end)

    if C_ChatInfo and C_ChatInfo.RegisterAddonMessagePrefix then
        C_ChatInfo.RegisterAddonMessagePrefix(self.PREFIX)
    elseif RegisterAddonMessagePrefix then
        RegisterAddonMessagePrefix(self.PREFIX)
    end

    local events = CreateFrame("Frame")
    events:RegisterEvent("CHAT_MSG_ADDON")
    events:RegisterEvent("PLAYER_EQUIPMENT_CHANGED")
    events:RegisterEvent("SKILL_LINES_CHANGED")
    events:RegisterEvent("PLAYER_GUILD_UPDATE")
    events:SetScript("OnEvent", function(_, event, prefix, message, channel, sender)
        if event == "CHAT_MSG_ADDON" then
            if prefix == Sync.PREFIX then Sync:OnMessage(message, channel, sender) end
        else
            Sync:ScheduleInfo(5)
        end
    end)

    C_Timer.After(8, function()
        Sync:SendInfo(true)
        Sync:Send("Q")
    end)
end
