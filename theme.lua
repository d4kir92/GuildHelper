local _, GuildHelper = ...
local Theme = {}
GuildHelper.Theme = Theme
Theme.WHITE = "Interface\\Buttons\\WHITE8X8"
Theme.MEDIA = "Interface\\AddOns\\GuildHelper\\media\\"
Theme.DEFAULT = "modern"
Theme.WESTERN = {
    enUS = true,
    enGB = true,
    deDE = true,
    esES = true,
    esMX = true,
    frFR = true,
    itIT = true,
    ptBR = true,
}

Theme.DESIGNS = {
    modern = {
        label = "LID_DESIGNMODERN",
        font = "Fonts\\ARIALN.TTF",
        colors = {
            window = {0.071, 0.075, 0.086, 0.98},
            border = {0.16, 0.165, 0.19, 1},
            divider = {0.12, 0.125, 0.145, 1},
            panel = {0.086, 0.09, 0.102, 1},
            card = {0.114, 0.118, 0.137, 1},
            control = {0.098, 0.102, 0.118, 1},
            hover = {0.14, 0.145, 0.165, 1},
            navActive = {0.16, 0.13, 0.07, 1},
            pillActive = {0.17, 0.13, 0.06, 1},
            rowHover = {1, 1, 1, 0.035},
            rowSelected = {0.14, 0.115, 0.07, 1},
            accent = {0.95, 0.71, 0.29, 1},
            accentText = {0.1, 0.08, 0.04, 1},
            text = {0.92, 0.92, 0.94, 1},
            navText = {0.78, 0.79, 0.82, 1},
            muted = {0.55, 0.56, 0.6, 1},
            online = {0.32, 0.85, 0.45, 1},
            onlineBg = {0.08, 0.2, 0.12, 1},
            barBg = {0.16, 0.165, 0.19, 1},
            thumb = {0.25, 0.26, 0.29, 1},
        },
    },
}

Theme.CORNERS = {{"TOPLEFT", 0, 0.5, 0, 0.5, 1, -1}, {"TOPRIGHT", 0.5, 1, 0, 0.5, -1, -1}, {"BOTTOMLEFT", 0, 0.5, 0.5, 1, 1, 1}, {"BOTTOMRIGHT", 0.5, 1, 0.5, 1, -1, 1}}
Theme.elements = {}
Theme.callbacks = {}
local Shape = {}
Shape.__index = Shape
function Shape:SetColor(r, g, b, a)
    for _, part in ipairs(self.parts) do
        part:SetVertexColor(r, g, b, a or 1)
    end
end

function Shape:SetShown(shown)
    for _, part in ipairs(self.parts) do
        part:SetShown(shown)
    end
end

function GuildHelper:GetDesign()
    local value = GuildHelper:GetConfig("DESIGN", Theme.DEFAULT)
    if Theme.DESIGNS[value] == nil then return Theme.DEFAULT end

    return value
end

function GuildHelper:SetDesign(value)
    if Theme.DESIGNS[value] == nil then value = Theme.DEFAULT end
    GuildHelper:SetConfig("DESIGN", value)
    Theme:Refresh()
end

function Theme:GetDesignTable()
    return self.DESIGNS[GuildHelper:GetDesign()] or self.DESIGNS[self.DEFAULT]
end

function Theme:GetColor(key)
    local color = self:GetDesignTable().colors[key] or self.DESIGNS[self.DEFAULT].colors[key]
    if color == nil then return 1, 1, 1, 1 end

    return color[1], color[2], color[3], color[4]
end

function Theme:GetHex(key)
    local r, g, b = self:GetColor(key)

    return format("|cff%02x%02x%02x", r * 255, g * 255, b * 255)
end

function Theme:GetFont()
    local font = self:GetDesignTable().font
    if font and self.WESTERN[GetLocale()] then return font end

    return STANDARD_TEXT_FONT
end

function Theme:Apply(element)
    local obj = element.obj
    if element.kind == "text" then
        if element.size then obj:SetFont(self:GetFont(), element.size, element.flags or "") end
        if element.key then obj:SetTextColor(self:GetColor(element.key)) end
    elseif element.kind == "shape" then
        obj:SetColor(self:GetColor(element.key))
    else
        obj:SetVertexColor(self:GetColor(element.key))
    end
end

function Theme:Track(obj, kind, key, size, flags)
    local element = {
        obj = obj,
        kind = kind,
        key = key,
        size = size,
        flags = flags,
    }

    obj.ghTheme = element
    tinsert(self.elements, element)
    self:Apply(element)

    return obj
end

function Theme:SetKey(obj, key)
    local element = obj and obj.ghTheme
    if element == nil or element.key == key then return end
    element.key = key
    self:Apply(element)
end

function Theme:Fill(texture, key)
    texture:SetTexture(self.WHITE)

    return self:Track(texture, "texture", key)
end

function Theme:Icon(parent, name, size, key, layer)
    local texture = parent:CreateTexture(nil, layer or "ARTWORK")
    texture:SetTexture(self.MEDIA .. name)
    texture:SetSize(size, size)

    return self:Track(texture, "texture", key)
end

function Theme:Text(parent, size, key, flags)
    local text = parent:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    text:SetWordWrap(false)
    text:SetJustifyH("LEFT")

    return self:Track(text, "text", key, size, flags)
end

function Theme:Background(frame, key, layer)
    local texture = frame:CreateTexture(nil, layer or "BACKGROUND")
    texture:SetAllPoints(frame)

    return self:Fill(texture, key)
end

function Theme:CreateShape(frame, radius, layer, sublevel, inset)
    inset = inset or 0
    local shape = setmetatable({
        parts = {}
    }, Shape)

    local function Part(file)
        local texture = frame:CreateTexture(nil, layer or "BACKGROUND", nil, sublevel or 0)
        texture:SetTexture(file)
        tinsert(shape.parts, texture)

        return texture
    end

    for _, corner in ipairs(self.CORNERS) do
        local texture = Part(self.MEDIA .. "circle")
        texture:SetSize(radius, radius)
        texture:SetTexCoord(corner[2], corner[3], corner[4], corner[5])
        texture:SetPoint(corner[1], frame, corner[1], corner[6] * inset, corner[7] * inset)
    end

    local center = Part(self.WHITE)
    center:SetPoint("TOPLEFT", frame, "TOPLEFT", inset + radius, -inset)
    center:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -inset - radius, inset)
    local left = Part(self.WHITE)
    left:SetPoint("TOPLEFT", frame, "TOPLEFT", inset, -inset - radius)
    left:SetPoint("BOTTOMRIGHT", frame, "BOTTOMLEFT", inset + radius, inset + radius)
    local right = Part(self.WHITE)
    right:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -inset, -inset - radius)
    right:SetPoint("BOTTOMLEFT", frame, "BOTTOMRIGHT", -inset - radius, inset + radius)

    return shape
end

function Theme:Round(frame, key, radius, layer, sublevel, inset)
    return self:Track(self:CreateShape(frame, radius, layer, sublevel, inset), "shape", key)
end

function Theme:Panel(frame, fillKey, borderKey, radius, layer)
    local border = borderKey and self:Round(frame, borderKey, radius, layer, 0)
    local fill = self:Round(frame, fillKey, borderKey and radius - 1 or radius, layer, 1, borderKey and 1 or 0)

    return fill, border
end

function Theme:Line(parent, key, layer)
    local texture = parent:CreateTexture(nil, layer or "BORDER")

    return self:Fill(texture, key)
end

function Theme:OnRefresh(callback)
    tinsert(self.callbacks, callback)
end

function Theme:Refresh()
    for _, element in ipairs(self.elements) do
        self:Apply(element)
    end

    for _, callback in ipairs(self.callbacks) do
        callback()
    end
end
