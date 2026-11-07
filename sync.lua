local _, GuildHelper = ...
local Sync = {}
GuildHelper.Sync = Sync
Sync.PREFIX = "GuildHelper"
Sync.SEND_THROTTLE = 15
Sync.ANSWER_THROTTLE = 120
Sync.lastSend = 0
Sync.listeners = {}
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

    return store[self:GetKey(shortName)]
end

function Sync:GetKey(name)
    return strlower(strsplit("-", name))
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

function Sync:GetOwnProfessions()
    local list = {}
    if GetProfessions and GetProfessionInfo then
        local indices = {GetProfessions()}
        for i = 1, 5 do
            local index = indices[i]
            if index then
                local name, _, rank, maxRank = GetProfessionInfo(index)
                if name then
                    tinsert(list, {name, rank or 0, maxRank or 0})
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
            tinsert(list, {name, rank or 0, maxRank or 0})
        end
    end

    return list
end

function Sync:BuildInfo()
    local parts = {"I", tostring(self:GetOwnItemLevel() or 0)}
    for _, prof in ipairs(self:GetOwnProfessions()) do
        tinsert(parts, format("%s;%d;%d", prof[1], prof[2], prof[3]))
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

function Sync:BuildSpecs()
    local parts = {"S", GuildHelper.Specs:GetMainName() or ""}
    for _, entry in ipairs(GuildHelper.Specs:GetOwn()) do
        tinsert(parts, format("%s;%s;%s", entry.role or "", entry.spec or "", tostring(entry.icon or "")))
    end

    tinsert(parts, GuildHelper.Specs:GetTwitch())

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
    entry.specs = specs
    entry.twitch = parts[#GuildHelper.Specs.SLOTS + 3] or ""
    self:Notify()
end

function Sync:SendSpecs()
    local message = self:BuildSpecs()
    self:ParseSpecs(UnitName("player"), message)
    self:Send(message)
end

function Sync:Parse(shortName, message)
    local parts = {strsplit("~", message)}
    local professions = {}
    for i = 3, #parts do
        local name, rank, maxRank = strsplit(";", parts[i])
        if name and name ~= "" then
            tinsert(professions, {name, tonumber(rank) or 0, tonumber(maxRank) or 0})
        end
    end

    self:Store(shortName, tonumber(parts[2]), professions)
end

function Sync:Send(message)
    if not IsInGuild() then return end
    if C_ChatInfo and C_ChatInfo.SendAddonMessage then
        pcall(C_ChatInfo.SendAddonMessage, self.PREFIX, message, "GUILD")
    elseif SendAddonMessage then
        pcall(SendAddonMessage, self.PREFIX, message, "GUILD")
    end
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
    self:Send(message)
    self:SendSpecs()
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
    if not GuildHelper:CanAccessValues(message, sender) then return end
    local shortName = strsplit("-", sender)
    if shortName == UnitName("player") then return end
    local kind = strsub(message, 1, 1)
    if kind == "I" then
        self:Parse(shortName, message)
    elseif kind == "S" then
        self:ParseSpecs(shortName, message)
    elseif kind == "Q" and GetTime() - self.lastSend > self.ANSWER_THROTTLE then
        self:ScheduleInfo(random(2, 12))
    end
end

function Sync:Init()
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
