local _, GuildHelper = ...
local Specs = {}
GuildHelper.Specs = Specs
Specs.ROLEICONS = "Interface\\LFGFrame\\UI-LFG-ICON-PORTRAITROLES"
Specs.ROLES = {
    {
        value = "TANK",
        label = "LID_ROLETANK",
        coords = {0, 19 / 64, 22 / 64, 41 / 64}
    },
    {
        value = "HEALER",
        label = "LID_ROLEHEALER",
        coords = {20 / 64, 39 / 64, 1 / 64, 20 / 64}
    },
    {
        value = "DAMAGER",
        label = "LID_ROLEDAMAGER",
        coords = {20 / 64, 39 / 64, 22 / 64, 41 / 64}
    },
}

Specs.SLOTS = {"LID_MAINSPEC", "LID_SECONDSPEC"}
function Specs:GetOwnSpecs()
    local list = {}
    if GetNumTalentTabs and GetTalentTabInfo then
        for index = 1, GetNumTalentTabs() or 0 do
            local first, second, _, fourth = GetTalentTabInfo(index)
            local classic = type(first) == "string"
            local name = classic and first or second
            if type(name) == "string" and name ~= "" then
                tinsert(list, {
                    name = name,
                    icon = classic and second or fourth
                })
            end
        end
    end

    if #list == 0 and GetNumSpecializations and GetSpecializationInfo then
        for index = 1, GetNumSpecializations() or 0 do
            local _, name, _, icon = GetSpecializationInfo(index)
            if name and name ~= "" then
                tinsert(list, {
                    name = name,
                    icon = icon
                })
            end
        end
    end

    return list
end

function Specs:GetRole(role)
    for _, entry in ipairs(self.ROLES) do
        if entry.value == role then return entry end
    end

    return nil
end

function Specs:GetRoleOptions()
    local options = {
        {
            value = "",
            label = GuildHelper:Trans("LID_NONE")
        }
    }

    for _, role in ipairs(self.ROLES) do
        tinsert(options, {
            value = role.value,
            label = self:Format({
                role = role.value
            })
        })
    end

    return options
end

function Specs:GetSpecOptions()
    local options = {
        {
            value = "",
            label = GuildHelper:Trans("LID_NONE")
        }
    }

    for _, spec in ipairs(self:GetOwnSpecs()) do
        tinsert(options, {
            value = spec.name,
            label = self:GetIconString(spec.icon) .. spec.name
        })
    end

    return options
end

function Specs:SetOwnSpec(slot, name)
    local entry = self:GetOwn()[slot]
    entry.spec = name or ""
    entry.icon = nil
    for _, spec in ipairs(self:GetOwnSpecs()) do
        if spec.name == name then entry.icon = spec.icon end
    end

    GuildHelper.Sync:SendSpecs()
end

function Specs:GetIconString(icon, coords, size)
    if icon == nil or icon == "" then return "" end
    size = size or 14
    if coords then return format("|T%s:%d:%d:0:0:64:64:%d:%d:%d:%d|t ", icon, size, size, coords[1] * 64, coords[2] * 64, coords[3] * 64, coords[4] * 64) end

    return format("|T%s:%d:%d:0:0:64:64:4:60:4:60|t ", icon, size, size)
end

function Specs:Format(entry, short)
    if entry == nil then return nil end
    local role = self:GetRole(entry.role)
    local parts = {}
    if role then tinsert(parts, self:GetIconString(self.ROLEICONS, role.coords) .. (short and "" or GuildHelper:Trans(role.label))) end
    if entry.spec and entry.spec ~= "" then tinsert(parts, self:GetIconString(entry.icon) .. entry.spec) end
    if #parts == 0 then return nil end

    return table.concat(parts, short and "" or "  ")
end

function Specs:GetOwn()
    local specs = GuildHelper:GetConfig("SPECS", {})
    for slot = 1, #self.SLOTS do
        specs[slot] = specs[slot] or {
            role = "",
            spec = ""
        }
    end

    return specs
end

function Specs:SetOwn(slot, key, value)
    self:GetOwn()[slot][key] = value or ""
    GuildHelper.Sync:SendSpecs()
end

function Specs:GetTwitch()
    GHTAB = GHTAB or {}

    return GHTAB.TWITCH or ""
end

function Specs:SetTwitch(value)
    value = gsub(strtrim(value or ""), "[^%w_]", "")
    GHTAB = GHTAB or {}
    GHTAB.TWITCH = strsub(value, 1, 25)
    GuildHelper.Sync:SendSpecs()
end

function Specs:GetMains()
    GHTAB = GHTAB or {}
    GHTAB.MAINS = GHTAB.MAINS or {}

    return GHTAB.MAINS
end

function Specs:GetMainName()
    local key = GuildHelper.Sync:GetGuildKey()

    return key and self:GetMains()[key] or nil
end

function Specs:IsMain()
    local main = self:GetMainName()

    return main ~= nil and strlower(main) == strlower(UnitName("player") or "")
end

function Specs:SetMain(value)
    local key = GuildHelper.Sync:GetGuildKey()
    if key == nil then return end
    if value then
        self:GetMains()[key] = UnitName("player")
    elseif self:IsMain() then
        self:GetMains()[key] = nil
    end

    GuildHelper.Sync:SendSpecs()
end

function Specs:GetRoleLabel(role)
    local entry = self:GetRole(role)

    return entry and GuildHelper:Trans(entry.label) or nil
end

function Specs:Describe(specs)
    if specs == nil then return "" end
    local lines = {}
    for slot, label in ipairs(self.SLOTS) do
        tinsert(lines, format("%s: %s", GuildHelper:Trans(label), self:Format(specs[slot]) or GuildHelper:Trans("LID_NONE")))
    end

    return table.concat(lines, "\n")
end
