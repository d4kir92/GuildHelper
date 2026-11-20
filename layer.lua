local _, GuildHelper = ...
local Layer = {}
GuildHelper.Layer = Layer
Layer.FRESH = 600
Layer.HEARTBEAT = 300
Layer.CONFIRM = 2
Layer.peers = {}

function Layer:IsSupported()
    return WOW_PROJECT_ID ~= WOW_PROJECT_MAINLINE
end

function Layer:GetContinent()
    local _, instanceType, _, _, _, _, _, instanceID = GetInstanceInfo()
    if instanceType ~= "none" or type(instanceID) ~= "number" then return nil end

    return instanceID
end

function Layer:GetOwn()
    local own = self.own
    if own and GetTime() - own.time < self.FRESH and own.continent == self:GetContinent() then return own end
end

function Layer:ReadUnit(unit)
    if not unit or not UnitExists(unit) then return end
    local guid = UnitGUID(unit)
    if not GuildHelper:CanAccessValue(guid) or type(guid) ~= "string" then return end
    local unitType, _, _, _, zoneUID = strsplit("-", guid)
    if unitType ~= "Creature" then return end
    local id = tonumber(zoneUID)
    local continent = self:GetContinent()
    if not id or id == 0 or not continent then return end
    self:Observe(id, continent)
end

function Layer:Observe(id, continent)
    local now = GetTime()
    local own = self.own
    if own and own.id == id and own.continent == continent then
        local stale = now - own.time >= self.FRESH
        own.time = now
        self.candidate = nil
        if stale then self:Send(true) end

        return
    end

    local candidate = self.candidate
    if candidate and candidate.id == id and candidate.continent == continent then
        candidate.count = candidate.count + 1
    else
        candidate = {
            id = id,
            continent = continent,
            count = 1
        }

        self.candidate = candidate
    end

    if own and own.continent == continent and candidate.count < self.CONFIRM then return end
    self.own = {
        id = id,
        continent = continent,
        time = now
    }

    self.candidate = nil
    self:Send(true)
    self:Changed()
end

function Layer:Send(force)
    if not self:IsSupported() or not IsInGuild() then return end
    local own = self:GetOwn()
    if not own then return end
    local now = GetTime()
    if not force and self.lastSend and now - self.lastSend < self.HEARTBEAT - 5 then return end
    self.lastSend = now
    self.shared = true
    GuildHelper.Sync:Send(format("L~%d~%d", own.id, own.continent), "L")
end

function Layer:Withdraw()
    self.own = nil
    self.candidate = nil
    if self.shared and IsInGuild() then GuildHelper.Sync:Send("L", "L") end
    self.shared = false
    self:Changed()
end

function Layer:OnMessage(shortName, message)
    local key = GuildHelper.Sync:GetKey(shortName)
    if message == "L" then
        if self.peers[key] then
            self.peers[key] = nil
            self:Changed()
        end

        return
    end

    local id, continent = message:match("^L~(%d+)~(%d+)$")
    id, continent = tonumber(id), tonumber(continent)
    if not id or not continent then return end
    local old = self.peers[key]
    self.peers[key] = {
        id = id,
        continent = continent,
        time = GetTime()
    }

    if not old or old.id ~= id or old.continent ~= continent then self:Changed() end
end

function Layer:GetEntry(member)
    if member == nil or member.remote or not member.online then return nil end
    if GuildHelper.Members:IsSelf(member) then return self:GetOwn() end
    local entry = self.peers[GuildHelper.Sync:GetKey(member.short)]
    if entry and GetTime() - entry.time < self.FRESH then return entry end
end

function Layer:GetRelation(member)
    local entry = self:GetEntry(member)
    if entry == nil then return nil end
    if GuildHelper.Members:IsSelf(member) then return "self", entry end
    local own = self:GetOwn()
    if own == nil or own.continent ~= entry.continent then return "unknown", entry end

    return own.id == entry.id and "same" or "other", entry
end

Layer.ORDER = {
    self = 0,
    same = 1,
    other = 2,
    unknown = 3
}

Layer.COLORS = {
    self = "accent",
    same = "online",
    other = "text",
    unknown = "muted"
}

function Layer:GetSortValue(member)
    local relation, entry = self:GetRelation(member)
    if relation == nil then return 4e9 end

    return self.ORDER[relation] * 1e9 + entry.id
end

function Layer:GetDisplay(member)
    local relation, entry = self:GetRelation(member)
    if relation == nil then return "–", "muted" end

    return tostring(entry.id), self.COLORS[relation], relation
end

function Layer:GetTooltipLine(member)
    local relation, entry = self:GetRelation(member)
    if relation == nil then return nil end
    local text = tostring(entry.id)
    if relation == "same" then
        text = text .. " (" .. GuildHelper:Trans("LID_LAYERSAME") .. ")"
    elseif relation == "other" then
        text = text .. " (" .. GuildHelper:Trans("LID_LAYEROTHER") .. ")"
    end

    return text
end

function Layer:Changed()
    if self.refreshPending then return end
    self.refreshPending = true
    C_Timer.After(0.5, function()
        Layer.refreshPending = false
        local members = GuildHelper.Members
        if members.content and members.content:IsVisible() then members:ApplyFilter() end
    end)
end

function Layer:Init()
    if not self:IsSupported() then return end
    local events = CreateFrame("Frame")
    events:RegisterEvent("PLAYER_TARGET_CHANGED")
    events:RegisterEvent("UPDATE_MOUSEOVER_UNIT")
    events:RegisterEvent("NAME_PLATE_UNIT_ADDED")
    events:RegisterEvent("PLAYER_ENTERING_WORLD")
    events:SetScript("OnEvent", function(_, event, unit)
        if event == "PLAYER_TARGET_CHANGED" then
            Layer:ReadUnit("target")
        elseif event == "UPDATE_MOUSEOVER_UNIT" then
            Layer:ReadUnit("mouseover")
        elseif event == "NAME_PLATE_UNIT_ADDED" then
            Layer:ReadUnit(unit)
        elseif Layer.own and Layer.own.continent ~= Layer:GetContinent() then
            Layer:Withdraw()
        end
    end)

    C_Timer.NewTicker(self.HEARTBEAT, function() Layer:Send(false) end)
end
