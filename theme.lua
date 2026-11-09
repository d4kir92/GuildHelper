local _, GuildHelper = ...
local Theme = {}
GuildHelper.Theme = Theme
Theme.WHITE = "Interface\\Buttons\\WHITE8X8"
Theme.MEDIA = "Interface\\AddOns\\GuildHelper\\media\\"
Theme.DEFAULT = "materialdark"
Theme.ORDER = {"materialdark", "materiallight", "obsidian", "forever"}
Theme.LANGFONTS = {
    koKR = "Fonts\\2002.TTF",
    zhCN = "Fonts\\ARKai_T.ttf",
    zhTW = "Fonts\\blei00d.TTF",
    ruRU = "Fonts\\FRIZQT___CYR.TTF",
}

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

local function Hex(value, alpha)
    return {tonumber(strsub(value, 1, 2), 16) / 255, tonumber(strsub(value, 3, 4), 16) / 255, tonumber(strsub(value, 5, 6), 16) / 255, alpha or 1}
end

Theme.DESIGNS = {
    materialdark = {
        label = "LID_DESIGNMATERIALDARK",
        font = "Fonts\\ARIALN.TTF",
        colors = {
            window = Hex("141218"),
            border = Hex("49454f"),
            divider = Hex("2b2930"),
            panel = Hex("1d1b20"),
            card = Hex("2b2930"),
            control = Hex("211f26"),
            hover = Hex("36343b"),
            navActive = Hex("4a4458"),
            pillActive = Hex("4a4458"),
            rowHover = Hex("e6e0e9", 0.08),
            rowSelected = Hex("4f378b"),
            accent = Hex("d0bcff"),
            accentText = Hex("381e72"),
            text = Hex("e6e0e9"),
            navText = Hex("cac4d0"),
            muted = Hex("938f99"),
            online = Hex("7dd68c"),
            onlineBg = Hex("1f3a26"),
            barBg = Hex("36343b"),
            thumb = Hex("938f99"),
        },
    },
    materiallight = {
        label = "LID_DESIGNMATERIALLIGHT",
        font = "Fonts\\ARIALN.TTF",
        colors = {
            window = Hex("fef7ff"),
            border = Hex("cac4d0"),
            divider = Hex("ece6f0"),
            panel = Hex("f7f2fa"),
            card = Hex("ece6f0"),
            control = Hex("f3edf7"),
            hover = Hex("e6e0e9"),
            navActive = Hex("e8def8"),
            pillActive = Hex("e8def8"),
            rowHover = Hex("1d1b20", 0.08),
            rowSelected = Hex("eaddff"),
            accent = Hex("6750a4"),
            accentText = Hex("ffffff"),
            text = Hex("1d1b20"),
            navText = Hex("49454f"),
            muted = Hex("79747e"),
            online = Hex("1e7a3a"),
            onlineBg = Hex("d4f0da"),
            barBg = Hex("e6e0e9"),
            thumb = Hex("79747e"),
        },
    },
    obsidian = {
        label = "LID_DESIGNOBSIDIAN",
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
    forever = {
        label = "LID_DESIGNFOREVER",
        native = true,
        colors = {
            window = {1, 1, 1, 1},
            border = {0.75, 0.75, 0.75, 1},
            divider = {0.4, 0.4, 0.4, 0.6},
            panel = {0, 0, 0, 0.8},
            card = {0.08, 0.08, 0.08, 0.9},
            control = {0.08, 0.08, 0.08, 0.9},
            hover = {0.3, 0.3, 0.3, 0.6},
            navActive = {1, 0.82, 0, 0.18},
            pillActive = {1, 0.82, 0, 0.18},
            rowHover = {1, 1, 1, 0.08},
            rowSelected = {1, 0.82, 0, 0.16},
            accent = {1, 0.82, 0, 1},
            accentText = {0, 0, 0, 1},
            text = {1, 1, 1, 1},
            navText = {1, 0.82, 0, 1},
            muted = {0.62, 0.62, 0.62, 1},
            online = {0.25, 1, 0.25, 1},
            onlineBg = {0.05, 0.22, 0.05, 0.9},
            barBg = {0.2, 0.2, 0.2, 1},
            thumb = {0.55, 0.55, 0.55, 1},
        },
    },
}

Theme.DIALOG = {
    bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background",
    edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
    tile = true,
    tileSize = 32,
    edgeSize = 32,
    insets = {
        left = 11,
        right = 12,
        top = 12,
        bottom = 11
    },
}

Theme.TOOLTIP = {
    bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
    edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
    tile = true,
    tileSize = 16,
    edgeSize = 16,
    insets = {
        left = 4,
        right = 4,
        top = 4,
        bottom = 4
    },
}

Theme.CORNERS = {{"TOPLEFT", 0, 0.5, 0, 0.5, 1, -1}, {"TOPRIGHT", 0.5, 1, 0, 0.5, -1, -1}, {"BOTTOMLEFT", 0, 0.5, 0.5, 1, 1, 1}, {"BOTTOMRIGHT", 0.5, 1, 0.5, 1, -1, 1}}
Theme.elements = {}
Theme.texts = {}
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

local Backdrop = {}
Backdrop.__index = Backdrop
function Backdrop:SetColor(r, g, b, a)
    if self.isBorder then
        self.frame:SetBackdropBorderColor(r, g, b, a or 1)
    else
        self.frame:SetBackdropColor(r, g, b, a or 1)
    end
end

function Backdrop:SetShown()
end

function GuildHelper:GetDesign()
    local value = GuildHelper:GetConfig("DESIGN", Theme.DEFAULT)
    if Theme.DESIGNS[value] == nil then return Theme.DEFAULT end

    return value
end

function GuildHelper:SetDesign(value)
    if Theme.DESIGNS[value] == nil then value = Theme.DEFAULT end
    local wasNative = Theme:IsNative()
    GuildHelper:SetConfig("DESIGN", value)
    if wasNative ~= Theme:IsNative() and GuildHelper.Window.frame then
        GuildHelper.Window:Rebuild()
    else
        Theme:Refresh()
    end
end

function Theme:IsNative()
    return self:GetDesignTable().native == true
end

function Theme:Reset()
    wipe(self.elements)
    wipe(self.texts)
end

function Theme:HasAtlas(atlas)
    if C_Texture and C_Texture.GetAtlasInfo then return C_Texture.GetAtlasInfo(atlas) ~= nil end
    if GetAtlasInfo then return GetAtlasInfo(atlas) ~= nil end

    return false
end

function Theme:InsideFrame(frame)
    local border = frame:CreateTexture(nil, "BORDER", nil, -7)
    if self:HasAtlas("common-insideframe") then
        border:SetAtlas("common-insideframe")
    elseif border.SetTextureSliceMargins then
        border:SetTexture(self.MEDIA .. "insideframe")
        border:SetTexCoord(1 / 128, 108 / 128, 1 / 128, 108 / 128)
        border:SetTextureSliceMargins(53, 53, 53, 53)
        if border.SetTextureSliceMode then border:SetTextureSliceMode(0) end
    else
        border:Hide()

        return false
    end

    border:SetPoint("TOPLEFT", frame, "TOPLEFT", -4, 4)
    border:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", 4, -4)
    local background = frame:CreateTexture(nil, "BACKGROUND", nil, -8)
    background:SetAllPoints(frame)
    if self:HasAtlas("collections-background-tile") then
        background:SetAtlas("collections-background-tile")
        background:SetHorizTile(true)
        background:SetVertTile(true)
    else
        background:SetColorTexture(0.05, 0.04, 0.03, 0.92)
    end

    return true
end

function Theme:NativePanel(frame, fillKey, borderKey)
    if (fillKey == "panel" or (fillKey == "card" and not frame.ghNoInside)) and self:InsideFrame(frame) then
        local static = {
            SetColor = function() end,
            SetShown = function() end
        }

        return static, static
    end

    if frame.SetBackdrop == nil and BackdropTemplateMixin then
        Mixin(frame, BackdropTemplateMixin)
        frame:HookScript("OnSizeChanged", frame.OnBackdropSizeChanged)
    end

    frame:SetBackdrop(fillKey == "window" and self.DIALOG or self.TOOLTIP)
    local fill = self:Track(setmetatable({
        frame = frame
    }, Backdrop), "shape", fillKey)

    local border = self:Track(setmetatable({
        frame = frame,
        isBorder = true
    }, Backdrop), "shape", borderKey or "border")

    return fill, border
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
    local lang = GuildHelper:GetLanguage()
    local font = self:GetDesignTable().font
    if font and self.WESTERN[lang] and self.WESTERN[GetLocale()] then return font end
    if lang ~= GetLocale() and self.LANGFONTS[lang] then return self.LANGFONTS[lang] end

    return STANDARD_TEXT_FONT
end

function Theme:NoShadow(obj)
    if obj and obj.SetShadowOffset then
        obj:SetShadowOffset(0, 0)
        obj:SetShadowColor(0, 0, 0, 0)
    end

    return obj
end

function Theme:FlatFont(base)
    local name = base and base.GetName and base:GetName()
    if not name then return base end
    self.flatFonts = self.flatFonts or {}
    if not self.flatFonts[name] then
        local font = CreateFont("GuildHelperFlat" .. name)
        font:CopyFontObject(base)
        self.flatFonts[name] = self:NoShadow(font)
    end

    return self.flatFonts[name]
end

function Theme:FlatNative(widget)
    if widget.GetNormalFontObject then
        for _, state in ipairs({"Normal", "Highlight", "Disabled"}) do
            local base = widget["Get" .. state .. "FontObject"](widget)
            if base then widget["Set" .. state .. "FontObject"](widget, self:FlatFont(base)) end
        end
    end

    if widget:GetObjectType() == "EditBox" then self:NoShadow(widget) end

    self:NoShadow(widget.GetFontString and widget:GetFontString() or nil)

    return widget
end

function Theme:Apply(element)
    local obj = element.obj
    if element.kind == "text" then
        self:NoShadow(obj)
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

function Theme:SetTrans(text, key, upper)
    if not text.ghTransTracked then
        text.ghTransTracked = true
        tinsert(self.texts, text)
    end

    text.ghTrans = key
    text.ghUpper = upper
    self:ApplyTrans(text)
end

function Theme:ApplyTrans(text)
    if text.ghTrans == nil then return end
    local value = GuildHelper:Trans(text.ghTrans)
    text:SetText(text.ghUpper and strupper(value) or value)
end

function Theme:RefreshTexts()
    for _, text in ipairs(self.texts) do
        self:ApplyTrans(text)
    end
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
    if self:IsNative() then return self:NativePanel(frame, fillKey, borderKey) end
    local border = borderKey and self:Round(frame, borderKey, radius, layer, 0)
    local fill = self:Round(frame, fillKey, borderKey and radius - 1 or radius, layer, 1, borderKey and 1 or 0)

    return fill, border
end

function Theme:Line(parent, key, layer)
    local texture = parent:CreateTexture(nil, layer or "BORDER")

    return self:Fill(texture, key)
end

function Theme:BindScrollDrag(thumb, getScroll, setScroll)
    local function stop(frame)
        frame:SetScript("OnUpdate", nil)
    end

    thumb:SetHitRectInsets(-4, -4, 0, 0)
    thumb:SetScript("OnMouseDown", function(frame, button)
        if button ~= "LeftButton" then return end
        local scale = frame:GetEffectiveScale()
        local startY = select(2, GetCursorPosition()) / scale
        local startOffset, range, travel = getScroll()
        if range <= 0 or travel <= 0 then return end
        frame:SetScript("OnUpdate", function()
            if not IsMouseButtonDown("LeftButton") then return stop(frame) end
            local y = select(2, GetCursorPosition()) / scale
            setScroll(min(range, max(0, startOffset + (startY - y) / travel * range)))
        end)
    end)
    thumb:SetScript("OnMouseUp", function(frame, button)
        if button == "LeftButton" then stop(frame) end
    end)
    thumb:SetScript("OnHide", stop)
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
