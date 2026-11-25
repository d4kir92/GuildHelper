local _, GuildHelper = ...
local Bridge = {}
GuildHelper.Bridge = Bridge
local Theme = GuildHelper.Theme
local Window = GuildHelper.Window
Bridge.PREFIX = "GHBridge"
Bridge.TIMEOUT = 6
Bridge.HELLO = 300
Bridge.KEEP = 30 * 86400
Bridge.status = "none"
Bridge.guilds = {}
Bridge.handlers = {}
function Bridge:GetStore()
    local key = GuildHelper.Sync:GetGuildKey()
    if key == nil then return nil end
    GHTAB = GHTAB or {}
    GHTAB.BRIDGE = GHTAB.BRIDGE or {}
    GHTAB.BRIDGE[key] = GHTAB.BRIDGE[key] or {}

    return GHTAB.BRIDGE[key]
end

function Bridge:GetGuildName()
    if not IsInGuild() then return nil end
    local guild = GetGuildInfo("player")
    if not GuildHelper:CanAccessValues(guild) or type(guild) ~= "string" or guild == "" then return nil end

    return guild
end

function Bridge:GetLeader()
    return GuildHelper.Events and GuildHelper.Events:GetLeader()
end

function Bridge:CanEdit()
    if not IsInGuild() then return false end
    if GuildHelper.testLeader then return true end
    if IsGuildLeader then return IsGuildLeader() == true end
    local leader = self:GetLeader()

    return leader ~= nil and GuildHelper.Groups:IsSelfName(leader)
end

function Bridge:IsLeaderName(sender)
    local leader = self:GetLeader()

    return leader ~= nil and GuildHelper.Groups:Name(sender) == leader
end

function Bridge:Validate(name, password)
    name = strtrim(name or "")
    password = strtrim(password or "")
    if #name < 2 or #name > 24 or not name:match("^%a%w+$") then return nil end
    if password == "" or #password > 24 or password:find("[%s~]") then return nil end

    return name, password
end

function Bridge:IsChannel(name, other)
    return type(name) == "string" and type(other) == "string" and strlower(name) == strlower(other)
end

function Bridge:GetChannelID(name)
    name = name or self.joined
    if name == nil or GetChannelName == nil then return 0 end
    local id = GetChannelName(name)
    if GuildHelper:CanAccessValues(id) and type(id) == "number" then return id end

    return 0
end

function Bridge:JoinChannel(name, password)
    local join = JoinTemporaryChannel or JoinChannelByName
    if join == nil then return false end

    return pcall(join, name, password)
end

function Bridge:LeaveChannel(name)
    if name and LeaveChannelByName and self:GetChannelID(name) > 0 then
        pcall(LeaveChannelByName, name)
    end
end

function Bridge:HideChannel(name)
    local remove = ChatFrame_RemoveChannel or (ChatFrameUtil and ChatFrameUtil.RemoveChannel)
    if remove == nil then return end
    for index = 1, NUM_CHAT_WINDOWS or 10 do
        local frame = _G["ChatFrame" .. index]
        if frame then pcall(remove, frame, name) end
    end
end

function Bridge:SetStatus(status)
    self.status = status
    self:Update()
end

function Bridge:Attempt(name, password, manual)
    if self.pending then return end
    if self.joined and self:IsChannel(self.joined, name) and self:GetChannelID(name) > 0 then
        self.pending = {
            name = name,
            password = password,
            manual = manual
        }

        self:Finish(true)

        return
    end

    local pending = {
        name = name,
        password = password,
        previous = self.joined,
        manual = manual
    }

    self.pending = pending
    self:SetStatus("joining")
    if not self:JoinChannel(name, password) then
        self:Finish(false, "failed")

        return
    end

    self:Check(pending, 0)
end

function Bridge:Check(pending, elapsed)
    if self.pending ~= pending then return end
    if self:GetChannelID(pending.name) > 0 then
        self:Finish(true)
    elseif elapsed >= self.TIMEOUT then
        self:Finish(false, "failed")
    else
        C_Timer.After(0.5, function() Bridge:Check(pending, elapsed + 0.5) end)
    end
end

function Bridge:Finish(success, reason)
    local pending = self.pending
    self.pending = nil
    if pending == nil then return end
    if not success then
        self:SetStatus(reason)

        return
    end

    if pending.previous and not self:IsChannel(pending.previous, pending.name) then self:LeaveChannel(pending.previous) end
    self.joined = pending.name
    self:HideChannel(pending.name)
    if pending.manual then
        if SetChannelPassword then pcall(SetChannelPassword, pending.name, pending.password) end
        self:SaveConfig(pending.name, pending.password)
        self:Broadcast()
    end

    self:ResetRemote(pending.name)
    self:SetStatus("joined")
    self:SendAddon("Q~" .. (self:GetGuildName() or ""), "Q")
    self:SendHello()
end

function Bridge:SaveConfig(name, password)
    local store = self:GetStore()
    if store == nil then return end
    store.name = name
    store.password = password
    store.rev = max(time(), (store.rev or 0) + 1)
end

function Bridge:Broadcast()
    local store = self:GetStore()
    if store == nil or store.rev == nil then return end
    GuildHelper.Sync:Send(format("BR~%d~%s~%s", store.rev, store.name or "", store.password or ""), "BR")
end

function Bridge:IsLiveRepeatEnabled()
    local store = self:GetStore()
    return store ~= nil and store.liveRepeatEnabled == true
end

function Bridge:BroadcastLiveRepeat()
    if not self:CanEdit() then return end
    local sync = GuildHelper.Sync
    local guild = sync:GetGuildKey()
    local store = self:GetStore()
    if not store or not store.liveRepeatRevision then return end
    sync:Send(format("GR~%d~%d", store.liveRepeatRevision, store.liveRepeatEnabled and 1 or 0), "GR", nil, guild)
end

function Bridge:ToggleLiveRepeat()
    if not self:CanEdit() then return end
    local store = self:GetStore()
    if not store then return end
    store.liveRepeatEnabled = not store.liveRepeatEnabled
    store.liveRepeatRevision = max(time(), (store.liveRepeatRevision or 0) + 1)
    self:BroadcastLiveRepeat()
    self:UpdateVisible()
    GuildHelper.Groups:Refresh()
end

function Bridge:OnLiveRepeatMessage(message, sender)
    if message == "GR~Q" then
        self:BroadcastLiveRepeat()

        return
    end
    local revision, enabled = message:match("^GR~(%d+)~([01])$")
    revision = tonumber(revision)
    if not revision or not self:IsLeaderName(sender) then return end
    local store = self:GetStore()
    if not store or revision <= (store.liveRepeatRevision or 0) then return end
    store.liveRepeatRevision = revision
    store.liveRepeatEnabled = enabled == "1"
    self:UpdateVisible()
    GuildHelper.Groups:Refresh()
end

function Bridge:OnQuery()
    local store = self:GetStore()
    if store and (store.rev or store.liveRepeatRevision) and self:CanEdit() then
        C_Timer.After(random(3, 15), function()
            Bridge:Broadcast()
            Bridge:BroadcastLiveRepeat()
        end)
    end
end

function Bridge:OnGuildMessage(message, sender)
    local rev, name, password = message:match("^BR~(%d+)~([^~]*)~([^~]*)$")
    rev = tonumber(rev)
    local store = self:GetStore()
    if rev == nil or store == nil or not self:IsLeaderName(sender) then return end
    if store.rev and store.rev >= rev then
        if store.rev > rev and self:CanEdit() then self:Broadcast() end

        return
    end

    store.rev = rev
    store.name = name ~= "" and name or nil
    store.password = password ~= "" and password or nil
    self:ApplyConfig()
end

function Bridge:ApplyConfig()
    local store = self:GetStore()
    local name = store and store.name
    if name == nil then
        if self.joined then self:LeaveChannel(self.joined) end
        self.joined = nil
        wipe(self.guilds)
        self:ResetRemote(nil)
        self:SetStatus("none")

        return
    end

    self:Attempt(name, store.password, false)
end

function Bridge:Submit()
    if not self:CanEdit() or self.ui == nil then return end
    local name, password = self:Validate(self.ui.name:GetText(), self.ui.password:GetText())
    if name == nil then
        self:SetStatus("invalid")

        return
    end

    self.ui.name:ClearFocus()
    self.ui.password:ClearFocus()
    self:Attempt(name, password, true)
end

function Bridge:Clear()
    if not self:CanEdit() then return end
    local store = self:GetStore()
    if store == nil or store.name == nil then return end
    self:SaveConfig(nil, nil)
    self:Broadcast()
    self:ApplyConfig()
end

function Bridge:IsChatInput()
    local active = (ChatEdit_GetActiveWindow and ChatEdit_GetActiveWindow()) or (ChatFrameUtil and ChatFrameUtil.GetActiveWindow and ChatFrameUtil.GetActiveWindow())
    if ChatEdit_GetActiveWindow == nil and (ChatFrameUtil == nil or ChatFrameUtil.GetActiveWindow == nil) then return true end

    return active ~= nil
end

function Bridge:Trim(text, limit)
    if #text <= limit then return text end
    local cut = limit
    while cut > 0 do
        local byte = strbyte(text, cut + 1)
        if byte == nil or byte < 128 or byte >= 192 then break end
        cut = cut - 1
    end

    return strsub(text, 1, cut)
end

function Bridge:OnSendChat(message, chatType)
    if self.relaying or chatType ~= "GUILD" or not GuildHelper:CanAccessValues(message) or type(message) ~= "string" or message == "" then return end
    local id = self:GetChannelID()
    local guild = self:GetGuildName()
    if id <= 0 or guild == nil or not self:IsChatInput() then return end
    local now = GetTime()
    if self.lastMessage == message and self.lastTime == now then return end
    self.lastMessage = message
    self.lastTime = now
    local text = self:Trim(format("<%s> %s", guild, message), 255)
    local send = (C_ChatInfo and C_ChatInfo.SendChatMessage) or SendChatMessage
    self.relaying = true
    pcall(send, text, "CHANNEL", nil, id)
    self.relaying = false
end

function Bridge:SeeGuild(guild)
    if guild == nil or guild == "" or guild == self:GetGuildName() then return end
    self.guilds[guild] = GetTime()
    self:Update()
end

function Bridge:ShowRelay(text, sender, guid)
    local guild = text:match("^<([^>]+)> .+$")
    if guild == nil or guild == self:GetGuildName() then return end
    self:SeeGuild(guild)
    if self:DispatchGuild(text, sender, guid) then return end
    local info = ChatTypeInfo and ChatTypeInfo.GUILD
    local frame = DEFAULT_CHAT_FRAME or ChatFrame1
    if frame then frame:AddMessage(self:FormatFallback(text, sender),info and info.r or 0.25, info and info.g or 1, info and info.b or 0.25) end
end

function Bridge:FormatFallback(message, sender)
    local name = Ambiguate and Ambiguate(sender, "none") or sender
    local link = format("|Hplayer:%s|h[%s]|h", sender, name)

    return format(CHAT_GUILD_GET or "[%s]: ", link) .. message
end

function Bridge:HasGuildChat(frame)
    if frame == nil or type(frame.messageTypeList) ~= "table" then return false end
    for _, group in ipairs(frame.messageTypeList) do
        if group == "GUILD" then return true end
    end

    return false
end

function Bridge:DispatchGuild(message, sender, guid)
    local shown = false
    for index = 1, NUM_CHAT_WINDOWS or 10 do
        local frame = _G["ChatFrame" .. index]
        local handler = frame and frame.GetScript and frame:GetScript("OnEvent")
        if handler and self:HasGuildChat(frame) then
            local ok = pcall(handler, frame, "CHAT_MSG_GUILD", message, sender, "", "", "", "", 0, 0, "", 0, 0, guid)
            shown = shown or ok
        end
    end

    return shown
end


function Bridge:OnChannelChat(text, sender, baseName, guid)
    if not GuildHelper:CanAccessValues(text, sender, baseName, guid) or type(text) ~= "string" or type(sender) ~= "string" then return end
    if not self:IsChannel(baseName, self.joined) then return end
    self:ShowRelay(text, sender, type(guid) == "string" and guid ~= "" and guid or nil)
end

function Bridge:FilterChannel(_, _, _, _, _, _, _, _, _, _, baseName)
    return GuildHelper:CanAccessValues(baseName) and self:IsChannel(baseName, self.joined)
end

function Bridge:OnNotice(text, baseName, channelName)
    local pending = self.pending
    if pending == nil or not GuildHelper:CanAccessValues(text, baseName, channelName) then return end
    if not self:IsChannel(baseName, pending.name) and not (type(channelName) == "string" and strlower(channelName):find(strlower(pending.name), 1, true)) then return end
    if text == "WRONG_PASSWORD" then
        self:Finish(false, "wrongpassword")
    elseif text == "BANNED" or text == "INVALID_NAME" then
        self:Finish(false, "failed")
    end
end

function Bridge:SendAddon(message, key)
    local id = self:GetChannelID()
    if id <= 0 then return false end
    GuildHelper.Sync:Send(message, key and ("BRIDGE-" .. key) or nil, self.PREFIX, nil, id)

    return true
end

function Bridge:SendHello()
    local guild = self:GetGuildName()
    if guild == nil then return end
    self:SendAddon("H~" .. guild, "H")
    self:SendMember()
end

function Bridge:RegisterHandler(kind, callback)
    self.handlers[kind] = callback
end

function Bridge:OnAddon(message, sender)
    if not GuildHelper:CanAccessValues(message, sender) or type(message) ~= "string" or type(sender) ~= "string" then return end
    local kind, guild, payload = message:match("^(%a+)~([^~]*)~?(.*)$")
    if kind == nil or guild == nil or guild == self:GetGuildName() then return end
    self:SeeGuild(guild)
    if kind == "Q" then
        C_Timer.After(random(2, 10), function() Bridge:SendHello() end)
    elseif self.handlers[kind] then
        self.handlers[kind](payload, guild, sender)
    end
end

function Bridge:GetGuildList()
    local list = {}
    local now = GetTime()
    for guild, seen in pairs(self.guilds) do
        if now - seen <= self.HELLO * 2 + 60 then tinsert(list, guild) end
    end

    sort(list)

    return list
end

function Bridge:GetRemoteStore()
    local key = GuildHelper.Sync:GetGuildKey()
    if key == nil then return nil end
    GHTAB = GHTAB or {}
    GHTAB.BRIDGEDATA = GHTAB.BRIDGEDATA or {}
    GHTAB.BRIDGEDATA[key] = GHTAB.BRIDGEDATA[key] or {guilds = {}}
    local store = GHTAB.BRIDGEDATA[key]
    store.guilds = store.guilds or {}

    return store
end

function Bridge:ResetRemote(channel)
    local store = self:GetRemoteStore()
    if store == nil then return end
    if channel and store.channel and self:IsChannel(store.channel, channel) then return end
    store.channel = channel
    wipe(store.guilds)
    GuildHelper.Sync:Notify()
end

function Bridge:GetRemoteEntry(guild, sender)
    local store = self:GetRemoteStore()
    if store == nil or guild == "" or sender == "" then return nil end
    store.guilds[guild] = store.guilds[guild] or {}
    local key = GuildHelper.Sync:GetKey(sender)
    local entry = store.guilds[guild][key] or {}
    store.guilds[guild][key] = entry
    entry.name = sender
    entry.seen = time()

    return entry
end

function Bridge:IsRemoteOnline(entry)
    return entry.seen ~= nil and time() - entry.seen <= self.HELLO * 2 + 60
end

function Bridge:GetRemoteMembers()
    local list = {}
    local store = IsInGuild() and self:GetRemoteStore()
    if not store then return list end
    local now = time()
    local Members = GuildHelper.Members
    for guild, entries in pairs(store.guilds) do
        for key, entry in pairs(entries) do
            if entry.seen == nil or now - entry.seen > self.KEEP then
                entries[key] = nil
            elseif entry.name then
                local short = Members:ShortName(entry.name)
                local online = self:IsRemoteOnline(entry)
                local className = entry.classFile and ((LOCALIZED_CLASS_NAMES_MALE and LOCALIZED_CLASS_NAMES_MALE[entry.classFile]) or entry.classFile) or ""
                local member = {
                    name = entry.name,
                    short = format("%s <%s>", short, guild),
                    key = strlower(guild) .. ">" .. key,
                    remote = true,
                    guild = guild,
                    data = entry,
                    rank = "",
                    rankIndex = 99,
                    isGuildLeader = false,
                    level = entry.level or 0,
                    className = className,
                    classFile = entry.classFile,
                    zone = "",
                    note = "",
                    officerNote = "",
                    online = online,
                    lastOnline = online and -1 or floor((now - entry.seen) / 3600),
                    declaredMain = entry.main ~= nil and entry.main ~= "" and GuildHelper.Sync:GetKey(entry.main) == key,
                }

                member.search = strlower(table.concat({short, guild, className}, "\n"))
                tinsert(list, member)
            end
        end

        if next(entries) == nil then store.guilds[guild] = nil end
    end

    return list
end

function Bridge:FitParts(parts)
    local message = table.concat(parts, "~")
    while #message > 255 and #parts > 3 do
        tremove(parts)
        message = table.concat(parts, "~")
    end

    return #message <= 255 and message or nil
end

function Bridge:SendMember()
    local guild = self:GetGuildName()
    if guild == nil or self:GetChannelID() <= 0 then return end
    local sync = GuildHelper.Sync
    local _, classFile = UnitClass("player")
    local _, race = UnitRace("player")
    local sex = UnitSex("player")
    if not GuildHelper:CanAccessValues(classFile, race, sex) then return end
    race = type(race) == "string" and race:match("^[A-Za-z]+$") and race:lower() or ""
    self:SendAddon(format("MC~%s~%s;%d;%s;%s", guild, classFile or "", UnitLevel("player") or 0, race, tostring(sex or "")), "MC")
    local info = {strsplit("~", sync:BuildInfo())}
    info[1] = guild
    tinsert(info, 1, "MI")
    local message = self:FitParts(info)
    if message then self:SendAddon(message, "MI") end
    local specs = {strsplit("~", sync:BuildSpecs())}
    specs[1] = guild
    tinsert(specs, 1, "MS")
    tinsert(specs, GuildHelper.Specs:GetTwitch() or "")
    message = table.concat(specs, "~")
    if #message <= 255 then self:SendAddon(message, "MS") end
end

function Bridge:OnMemberClass(payload, guild, sender)
    local classFile, level, race, sex = strsplit(";", payload)
    local entry = self:GetRemoteEntry(guild, sender)
    if entry == nil then return end
    entry.classFile = classFile and classFile:match("^%u+$") or entry.classFile
    entry.level = tonumber(level) or entry.level
    if race and race:match("^[a-z]+$") then entry.portraitRace = race end
    if sex == "2" or sex == "3" then entry.portraitGender = sex == "2" and "male" or "female" end
    GuildHelper.Sync:Notify()
end

function Bridge:OnMemberInfo(payload, guild, sender)
    local entry = self:GetRemoteEntry(guild, sender)
    if entry == nil then return end
    local parts = {strsplit("~", payload)}
    local professions = {}
    for index = 2, #parts do
        local name, rank, maxRank, skillLineID = strsplit(";", parts[index])
        if name and name ~= "" then tinsert(professions, {name, tonumber(rank) or 0, tonumber(maxRank) or 0, tonumber(skillLineID)}) end
    end

    local ilvl = tonumber(parts[1])
    entry.ilvl = ilvl and ilvl > 0 and ilvl or nil
    entry.professions = professions
    GuildHelper.Sync:Notify()
end

function Bridge:OnMemberSpecs(payload, guild, sender)
    local entry = self:GetRemoteEntry(guild, sender)
    if entry == nil then return end
    local parts = {strsplit("~", payload)}
    local slots = #GuildHelper.Specs.SLOTS
    local specs = {}
    for slot = 1, slots do
        local role, spec, icon = strsplit(";", parts[slot + 1] or "")
        specs[slot] = {role = role or "", spec = spec or "", icon = tonumber(icon) or (icon ~= nil and icon ~= "" and icon or nil)}
    end

    entry.main = parts[1] or ""
    entry.specs = specs
    entry.twitch = parts[slots + 2] or entry.twitch
    GuildHelper.Sync:Notify()
end

function Bridge:CreateBox(parent, width, password)
    local box = CreateFrame("EditBox", nil, parent, Theme:IsNative() and "InputBoxTemplate" or nil)
    box:SetSize(width, 26)
    if Theme:IsNative() then
        Theme:FlatNative(box)
    else
        box:SetTextInsets(10, 10, 0, 0)
        box.fill, box.border = Theme:Panel(box, "control", "border", 7)
        Theme:Track(box, "text", "text", 12.5)
    end

    box:SetAutoFocus(false)
    box:SetMaxLetters(24)
    if password then box:SetPassword(true) end
    box:SetScript("OnEnterPressed", function(sel) sel:ClearFocus() end)
    box:SetScript("OnEscapePressed", function(sel) sel:ClearFocus() end)
    box:SetScript("OnEditFocusGained", function(sel) if sel.border then Theme:SetKey(sel.border, "accent") end end)
    box:SetScript("OnEditFocusLost", function(sel) if sel.border then Theme:SetKey(sel.border, "border") end end)

    return box
end

function Bridge:CreateLabeledBox(parent, y, label, password)
    local box = self:CreateBox(parent, 220, password)
    box:SetPoint("TOPRIGHT", parent, "TOPRIGHT", -18, y)
    local title = Theme:Text(parent, 13, "text")
    title:SetPoint("LEFT", parent, "TOPLEFT", 18, y - 13)
    title:SetPoint("RIGHT", box, "LEFT", -10, 0)
    Theme:SetTrans(title, label)

    return box
end

function Bridge:CreateButton(parent, label, width, action, primary)
    local button = GuildHelper.Members:CreateButton(parent, label, primary)
    button:SetWidth(width)
    button:SetScript("OnClick", action)

    return button
end

function Bridge:Build(content, entry)
    Window:CreatePageTitle(content, entry.label)
    local body = CreateFrame("Frame", nil, content)
    body:SetAllPoints(content)
    local locked = Theme:Text(content, 14, "muted")
    locked:SetPoint("TOPLEFT", content, "TOPLEFT", Window.PADDING, -80)
    locked:SetPoint("RIGHT", content, "RIGHT", -Window.PADDING, 0)
    locked:SetJustifyH("LEFT")
    locked:SetWordWrap(true)
    Theme:SetTrans(locked, "LID_BRIDGENOPERMISSION")
    local panel = CreateFrame("Frame", nil, body)
    panel:SetPoint("TOPLEFT", body, "TOPLEFT", Window.PADDING, -80)
    panel:SetSize(520, 300)
    Theme:Panel(panel, "panel", "border", 9)
    local header = Theme:Text(panel, 11, "muted")
    header:SetPoint("TOPLEFT", panel, "TOPLEFT", 18, -16)
    Theme:SetTrans(header, "LID_BRIDGE", true)
    local desc = Theme:Text(panel, 12, "muted")
    desc:SetPoint("TOPLEFT", panel, "TOPLEFT", 18, -36)
    desc:SetPoint("RIGHT", panel, "RIGHT", -18, 0)
    desc:SetJustifyH("LEFT")
    desc:SetWordWrap(true)
    Theme:SetTrans(desc, "LID_BRIDGEDESC")
    local ui = {}
    ui.name = self:CreateLabeledBox(panel, -88, "LID_BRIDGENAME")
    ui.password = self:CreateLabeledBox(panel, -124, "LID_BRIDGEPASSWORD", true)
    ui.name:SetScript("OnTabPressed", function() ui.password:SetFocus() end)
    ui.password:SetScript("OnTabPressed", function() ui.name:SetFocus() end)
    ui.password:SetScript("OnEnterPressed", function() Bridge:Submit() end)
    ui.create = self:CreateButton(panel, "LID_BRIDGECREATE", 120, function() Bridge:Submit() end, true)
    ui.create:SetPoint("TOPRIGHT", panel, "TOPRIGHT", -18, -164)
    ui.leave = self:CreateButton(panel, "LID_BRIDGELEAVE", 100, function() Bridge:Clear() end)
    ui.leave:SetPoint("RIGHT", ui.create, "LEFT", -8, 0)
    ui.status = Theme:Text(panel, 13, "text")
    ui.status:SetPoint("TOPLEFT", panel, "TOPLEFT", 18, -212)
    ui.status:SetPoint("RIGHT", panel, "RIGHT", -18, 0)
    ui.status:SetJustifyH("LEFT")
    ui.status:SetWordWrap(true)
    ui.guilds = Theme:Text(panel, 12, "muted")
    ui.guilds:SetPoint("TOPLEFT", ui.status, "BOTTOMLEFT", 0, -8)
    ui.guilds:SetPoint("RIGHT", panel, "RIGHT", -18, 0)
    ui.guilds:SetJustifyH("LEFT")
    ui.guilds:SetWordWrap(true)
    local recruitment = CreateFrame("Frame", nil, body)
    recruitment:SetPoint("TOPLEFT", panel, "BOTTOMLEFT", 0, -12)
    recruitment:SetSize(520, 48)
    Theme:Panel(recruitment, "panel", "border", 9)
    ui.liveRepeat = GuildHelper.Settings:CreateCheck(recruitment)
    ui.liveRepeat:SetPoint("LEFT", recruitment, "LEFT", 18, 0)
    ui.liveRepeat:SetScript("OnClick", function() Bridge:ToggleLiveRepeat() end)
    local repeatLabel = Theme:Text(recruitment, 13, "text")
    repeatLabel:SetPoint("LEFT", ui.liveRepeat, "RIGHT", 10, 0)
    repeatLabel:SetPoint("RIGHT", recruitment, "RIGHT", -18, 0)
    repeatLabel:SetJustifyH("LEFT")
    repeatLabel:SetWordWrap(true)
    Theme:SetTrans(repeatLabel, "LID_GROUPCHATREPEATENABLED")
    ui.body = body
    ui.locked = locked
    ui.content = content
    self.ui = ui
    Window:BuildPlaceholder(body, entry, recruitment)
    if not self.hooked then
        self.hooked = true
        Theme:OnRefresh(function() Bridge:Update() end)
    end

    content.OnPageShow = function() Bridge:Update() end
    self:Update()
end

function Bridge:SetButtonEnabled(button, enabled)
    button:SetEnabled(enabled)
    button:SetAlpha(enabled and 1 or 0.45)
end

function Bridge:Update()
    local ui = self.ui
    if ui == nil then return end
    local store = self:GetStore()
    local canEdit = self:CanEdit()
    ui.body:SetShown(canEdit)
    ui.locked:SetShown(not canEdit)
    if not canEdit then
        ui.name:ClearFocus()
        ui.password:ClearFocus()

        return
    end

    ui.liveRepeat:SetChecked(store and store.liveRepeatEnabled == true or false)
    if not ui.name:HasFocus() then ui.name:SetText(store and store.name or "") end
    if not ui.password:HasFocus() then ui.password:SetText(store and store.password or "") end
    ui.name:SetEnabled(canEdit)
    ui.password:SetEnabled(canEdit)
    ui.create.text:SetText(GuildHelper:Trans(self.joined and "LID_BRIDGEUPDATE" or "LID_BRIDGECREATE"))
    self:SetButtonEnabled(ui.create, canEdit and self.pending == nil)
    self:SetButtonEnabled(ui.leave, canEdit and self.pending == nil and store ~= nil and store.name ~= nil)
    local channel = (self.pending and self.pending.name) or self.joined or (store and store.name) or ""
    ui.status:SetText(format(GuildHelper:Trans("LID_BRIDGESTATUS" .. strupper(self.status)), channel))
    local guilds = self:GetGuildList()
    ui.guilds:SetText(format(GuildHelper:Trans("LID_BRIDGEGUILDS"), #guilds > 0 and table.concat(guilds, ", ") or GuildHelper:Trans("LID_NONE")))
end

function Bridge:UpdateVisible()
    if self.ui and self.ui.content:IsVisible() then self:Update() end
end

function Bridge:HookChat()
    if C_ChatInfo and C_ChatInfo.SendChatMessage then hooksecurefunc(C_ChatInfo, "SendChatMessage", function(message, chatType) Bridge:OnSendChat(message, chatType) end) end
    if SendChatMessage then hooksecurefunc("SendChatMessage", function(message, chatType) Bridge:OnSendChat(message, chatType) end) end
    local register = (ChatFrameUtil and ChatFrameUtil.AddMessageEventFilter) or ChatFrame_AddMessageEventFilter
    if register then register("CHAT_MSG_CHANNEL", function(...) return Bridge:FilterChannel(...) end) end
end

function Bridge:Init()
    self.repeatGuild = GuildHelper.Sync:GetGuildKey()
    if C_ChatInfo and C_ChatInfo.RegisterAddonMessagePrefix then
        C_ChatInfo.RegisterAddonMessagePrefix(self.PREFIX)
    elseif RegisterAddonMessagePrefix then
        RegisterAddonMessagePrefix(self.PREFIX)
    end

    self:HookChat()
    self:RegisterHandler("MC", function(payload, guild, sender) Bridge:OnMemberClass(payload, guild, sender) end)
    self:RegisterHandler("MI", function(payload, guild, sender) Bridge:OnMemberInfo(payload, guild, sender) end)
    self:RegisterHandler("MS", function(payload, guild, sender) Bridge:OnMemberSpecs(payload, guild, sender) end)
    self:RegisterHandler("H", function(_, guild, sender) Bridge:GetRemoteEntry(guild, sender) end)
    C_Timer.After(10, function() Bridge:ApplyConfig() end)
    C_Timer.NewTicker(self.HELLO, function() Bridge:SendHello() end)
end

Bridge.events = CreateFrame("Frame")
Bridge.events:RegisterEvent("PLAYER_LOGIN")
Bridge.events:RegisterEvent("PLAYER_GUILD_UPDATE")
Bridge.events:RegisterEvent("GUILD_ROSTER_UPDATE")
Bridge.events:RegisterEvent("CHAT_MSG_CHANNEL")
Bridge.events:RegisterEvent("CHAT_MSG_CHANNEL_NOTICE_USER")
Bridge.events:RegisterEvent("CHAT_MSG_ADDON")
Bridge.events:SetScript("OnEvent", function(_, event, ...)
    if event == "PLAYER_LOGIN" then
        Bridge:Init()
    elseif event == "PLAYER_GUILD_UPDATE" then
        local sync = GuildHelper.Sync
        local guild = sync:GetGuildKey()
        if guild ~= Bridge.repeatGuild then
            Bridge.repeatGuild = guild
            if guild then sync:Send("GR~Q", "GR~Q", nil, guild) end
        end
        if not IsInGuild() and Bridge.joined then
            Bridge:LeaveChannel(Bridge.joined)
            Bridge.joined = nil
            Bridge:SetStatus("none")
        end
        Bridge:UpdateVisible()
    elseif event == "GUILD_ROSTER_UPDATE" then
        Bridge:UpdateVisible()
    elseif event == "CHAT_MSG_CHANNEL" then
        local text, sender, _, _, _, _, _, _, baseName, _, _, guid = ...
        Bridge:OnChannelChat(text, sender, baseName, guid)
    elseif event == "CHAT_MSG_CHANNEL_NOTICE_USER" then
        local text, _, _, channelName, _, _, _, _, baseName = ...
        Bridge:OnNotice(text, baseName, channelName)
    elseif event == "CHAT_MSG_ADDON" then
        local prefix, message, channel, sender = ...
        if prefix == Bridge.PREFIX and channel == "CHANNEL" then Bridge:OnAddon(message, sender) end
    end
end)

Window:SetPageBuilder("management", function(content, entry) Bridge:Build(content, entry) end)
