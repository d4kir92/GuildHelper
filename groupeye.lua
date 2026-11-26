local _, GuildHelper = ...
local Eye = {elapsed = 0, frame = 1, frameTime = 0}
GuildHelper.GroupEye = Eye
Eye.ATLAS = "groupfinder-eye-flipbook-searching"
Eye.LEGACY = {file = "Interface\\LFGFrame\\LFG-Eye", width = 512, height = 256, size = 64, frames = 29, delay = 0.1}

function Eye:GetOwnListings()
    local Groups = GuildHelper.Groups
    local list = {}
    if not Groups.live or not Groups:CheckGuild() then return list end
    for _, entry in pairs(Groups.live) do
        if Groups:IsOwn(entry) then tinsert(list, entry) end
    end

    table.sort(list, function(a, b) return a.key < b.key end)

    return list
end

function Eye:GetPrimary(list)
    for _, entry in ipairs(list) do
        for _, applicant in pairs(entry.applicants or {}) do
            if applicant.unread then return entry end
        end
    end

    return list[1]
end

function Eye:ShowTooltip(tooltip)
    local Groups = GuildHelper.Groups
    tooltip:AddLine(GuildHelper:Trans("LID_GROUPFINDER"), 1, 0.82, 0)
    for _, entry in ipairs(self:GetOwnListings()) do
        local names = {}
        for _, applicant in pairs(entry.applicants or {}) do
            tinsert(names, applicant)
        end

        table.sort(names, function(a, b) return (a.name or "") < (b.name or "") end)
        tooltip:AddLine(" ")
        tooltip:AddDoubleLine(Groups:GetActivityName(entry), GuildHelper:Trans("LID_GROUPAPPLICANTS") .. ": " .. #names, 1, 1, 1, 0.7, 0.7, 0.7)
        if #names == 0 then tooltip:AddLine(GuildHelper:Trans("LID_GROUPNOAPPLICANTS"), 0.6, 0.6, 0.6) end
        for _, applicant in ipairs(names) do
            local member = GuildHelper.Members:FindByName(applicant.name)
            local r, g, b = 1, 1, 1
            if member then r, g, b = GuildHelper.Members:GetClassColor(member) end
            local status = applicant.accepted and GuildHelper:Trans("LID_GROUPACCEPTED") or ""
            tooltip:AddDoubleLine(applicant.name or "?", status, r, g, b, 0.3, 0.9, 0.3)
        end
    end

    tooltip:AddLine(" ")
    tooltip:AddLine(GuildHelper:Trans("LID_GROUPEYECLICK"), 0.6, 0.6, 0.6)
end

function Eye:SetupAnimation(button)
    local icon = button.icon
    icon:ClearAllPoints()
    icon:SetPoint("CENTER", button, "CENTER", 0, 0)
    icon:SetSize(26, 26)
    local atlas = C_Texture and C_Texture.GetAtlasInfo and C_Texture.GetAtlasInfo(self.ATLAS)
    if atlas then
        icon:SetAtlas(self.ATLAS)
        local group = button:CreateAnimationGroup()
        local flip = group:CreateAnimation("FlipBook")
        if flip and flip.SetFlipBookRows then
            flip:SetTarget(icon)
            flip:SetFlipBookRows(8)
            flip:SetFlipBookColumns(11)
            flip:SetFlipBookFrames(80)
            flip:SetFlipBookFrameWidth(0)
            flip:SetFlipBookFrameHeight(0)
            flip:SetDuration(2)
            group:SetLooping("REPEAT")
            self.animation = group

            return
        end
    end

    icon:SetTexture(self.LEGACY.file)
    self:SetLegacyFrame(1)
end

function Eye:SetLegacyFrame(index)
    local info = self.LEGACY
    local columns = info.width / info.size
    local column = (index - 1) % columns
    local row = floor((index - 1) / columns)
    local w, h = info.size / info.width, info.size / info.height
    self.frame = index
    self.button.icon:SetTexCoord(column * w, (column + 1) * w, row * h, (row + 1) * h)
end

function Eye:Animate(elapsed)
    if self.animation then return end
    self.frameTime = self.frameTime + elapsed
    if self.frameTime < self.LEGACY.delay then return end
    self.frameTime = 0
    self:SetLegacyFrame(self.frame % self.LEGACY.frames + 1)
end

function Eye:Create()
    if self.button or not GuildHelper.CreateMinimapButton then return end
    GHTABPC = GHTABPC or {}
    GHTABPC.GROUPEYE = GHTABPC.GROUPEYE or {minimapPos = 200}
    local params = {
        name = "GuildHelperLFG",
        icon = self.LEGACY.file,
        dbtab = GHTABPC.GROUPEYE,
        dbkey = "",
        noalpha = true,
        addoncomp = false,
        funcL = function()
            local entry = Eye:GetPrimary(Eye:GetOwnListings())
            if entry then GuildHelper.Groups:OpenListing(entry) end
        end,
        vTTUpdate = function(_, tooltip) Eye:ShowTooltip(tooltip) end
    }
    self.button = GuildHelper:CreateMinimapButton(params)
    if not self.button then return end
    self:SetupAnimation(self.button)
    self.button:Hide()
end

function Eye:Update()
    if not self.button then return end
    local shown = #self:GetOwnListings() > 0
    if shown ~= self.button:IsShown() then
        self.button:SetShown(shown)
        if self.animation then
            if shown then self.animation:Play() else self.animation:Stop() end
        end
    end
end

Eye.events = CreateFrame("Frame")
Eye.events:RegisterEvent("PLAYER_LOGIN")
Eye.events:SetScript("OnEvent", function() Eye:Create() end)
Eye.events:SetScript("OnUpdate", function(_, elapsed)
    if Eye.button and Eye.button:IsShown() then Eye:Animate(elapsed) end
    Eye.elapsed = Eye.elapsed + elapsed
    if Eye.elapsed < 1 then return end
    Eye.elapsed = 0
    Eye:Update()
end)
