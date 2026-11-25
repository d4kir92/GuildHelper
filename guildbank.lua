local _, GuildHelper = ...
local Bank = {}
GuildHelper.Bank = Bank
Bank.pending = {}
Bank.outgoing = {}
Bank.lastRequest = 0
Bank.serial = 0
Bank.peers = {}
Bank.claims = {}
Bank.queried = {}
Bank.SLOTS = 98
Bank.MAXTABS = 8

function Bank:Identity()
    local guild = GuildHelper.Sync:GetGuildKey()
    local _, _, rank = GetGuildInfo("player")
    if not guild or type(rank) ~= "number" then return nil end
    return guild, rank
end

function Bank:Store()
    local guild, rank = self:Identity()
    if not guild then return nil end
    if self.guild ~= guild or self.rank ~= rank then
        self:Debug("Bank-Schlüssel:", self.guild and (self.guild .. "#" .. tostring(self.rank)) or "-", "->", guild .. "#" .. rank, self.guild and "(alter Speicher gelöscht)" or "")
        if self.guild and self.rank and GHTABPC and GHTABPC.BANK then
            GHTABPC.BANK[self.guild .. "#" .. self.rank] = nil
        end
        self.guild, self.rank = guild, rank
        self.pending, self.outgoing, self.sent, self.peers, self.claims = {}, {}, {}, {}, {}
        self.selected = 1
    end
    GHTABPC = GHTABPC or {}
    GHTABPC.BANK = GHTABPC.BANK or {}
    local key = guild .. "#" .. rank
    GHTABPC.BANK[key] = GHTABPC.BANK[key] or {tabs = {}, public = {}}
    GHTABPC.BANK[key].icons = GHTABPC.BANK[key].icons or {}
    return GHTABPC.BANK[key]
end

function Bank:Member(name)
    local key = GuildHelper.Groups:Name(name)
    if not key then return nil end
    for index = 1, GetNumGuildMembers() do
        local member, _, rank, _, _, _, _, _, online = GetGuildRosterInfo(index)
        if member and GuildHelper:CanAccessValues(member, rank) and GuildHelper.Groups:Name(member) == key then
            return rank, member, online
        end
    end
end

function Bank:IsLeader()
    if GuildHelper.testLeader then return true end
    local _, rank = self:Identity()
    return rank == 0
end

function Bank:Allowed(tab)
    local store = self:Store()
    if not store then return false end
    if self:IsLeader() then return true end
    if GetGuildBankTabInfo then
        local name, _, view = GetGuildBankTabInfo(tab)
        if name and name ~= "" and not view then return false end
    end
    local record = store.tabs[tab]
    if not record then return false end
    if store.public[tab] and record.public then return true end
    return record.rank == self.rank and record.authorized == true
end

function Bank:CanTransmit(message, target, rank)
    local store = self:Store()
    if not store or rank ~= self.rank then return false end
    local command, tab = message:match("^BK~([A-Z])~?(%d*)")
    if command == "Q" then return true end
    if command == "P" then return self:IsLeader() end
    if command == "N" then return self.open == true end
    if command == "C" then return true end
    tab = tonumber(tab)
    if not tab or not self:Allowed(tab) then return false end
    if not target then return store.public[tab] == true end
    local recipientRank = self:Member(target)
    return recipientRank ~= nil and (store.public[tab] == true or recipientRank == self.rank)
end

function Bank:Send(message, key, target)
    if #message > 240 then return end
    GuildHelper.Sync:Send(message, "bank:" .. key, nil, self.guild, target)
end

function Bank:Policy(tab, enabled)
    if not self:IsLeader() then return end
    local store = self:Store()
    if not store then return end
    self.serial = self.serial + 1
    local stamp = time() * 100 + self.serial % 100
    store.policyStamp = stamp
    store.public[tab] = enabled or nil
    self:Send("BK~P~" .. tab .. "~" .. (enabled and "1" or "0") .. "~" .. stamp, "policy:" .. tab)
    if enabled and store.tabs[tab] then self:QueueTab(tab) end
    self:Refresh()
end

function Bank:ValidIcon(icon)
    if type(icon) == "string" and tonumber(icon) then icon = tonumber(icon) end
    if type(icon) == "number" then
        if icon >= 1 and icon <= 2147483647 and icon == floor(icon) then return icon end
        return nil
    end
    if type(icon) == "string" and #icon <= 120 and icon:match("^[%w_%.%-\\/]+$") then return icon end
end

function Bank:TabIcon(tab)
    if self.open and GetGuildBankTabInfo then
        local _, icon = GetGuildBankTabInfo(tab)
        icon = self:ValidIcon(icon)
        if icon then return icon end
    end
    local store = self:Store()
    return store and store.icons[tab]
end

function Bank:Encode(record)
    local parts = {}
    for slot = 1, self.SLOTS do
        local item = record.items[slot]
        if item then parts[#parts + 1] = slot .. ":" .. item.id .. ":" .. item.count end
    end
    return table.concat(parts, ";")
end

function Bank:Decode(payload)
    local items = {}
    if payload == "" then return items end
    for part in (payload .. ";"):gmatch("(.-);") do
        local slot, id, count = part:match("^(%d+):(%d+):(%d+)$")
        slot, id, count = tonumber(slot), tonumber(id), tonumber(count)
        if not slot or slot < 1 or slot > self.SLOTS or not id or id < 1 or id > 100000000
            or not count or count < 1 or count > 1000000 or items[slot] then return nil end
        items[slot] = {id = id, count = count}
    end
    return items
end

function Bank:QueueTab(tab, target)
    local store = self:Store()
    local record = store and store.tabs[tab]
    if not record or not self:Allowed(tab) then return end
    local public = store.public[tab] == true
    if public then target = nil end
    if not public and not target then
        for name in pairs(self.peers) do
            local rank, member, online = self:Member(name)
            if online and rank == self.rank then self:QueueTab(tab, member) end
        end
        return
    end
    if target then
        local rank = self:Member(target)
        if rank == nil or (not public and rank ~= self.rank) then return end
    end
    local key = tab .. ":" .. (target or "GUILD")
    local signature = record.stamp .. ":" .. tostring(public)
    self.sent = self.sent or {}
    if self.sent[key] and self.sent[key].signature == signature and GetTime() - self.sent[key].at < 60 then return end
    self.outgoing[key] = {tab = tab, target = target, guild = self.guild, rank = self.rank, stamp = record.stamp, public = public}
end

function Bank:Pump()
    local store = self:Store()
    if not store then return end
    for key, transfer in pairs(self.outgoing) do
        local record = store.tabs[transfer.tab]
        local valid = record and transfer.guild == self.guild and transfer.rank == self.rank and self:Allowed(transfer.tab)
            and (store.public[transfer.tab] == true) == transfer.public
        if transfer.target then
            local rank = self:Member(transfer.target)
            valid = valid and rank ~= nil and (transfer.public or rank == self.rank)
            local claim = self.claims[transfer.target .. ":" .. transfer.tab]
            local own = GuildHelper.Groups:Name(UnitName("player") .. "-" .. GetRealmName())
            if claim and claim.expires > GetTime() and claim.sender < own then valid = false end
        end
        if not valid or record.stamp ~= transfer.stamp then
            self.outgoing[key] = nil
        else
            if not transfer.parts then
                local payload = self:Encode(record)
                transfer.parts = {}
                for offset = 1, max(1, #payload), 160 do transfer.parts[#transfer.parts + 1] = payload:sub(offset, offset + 159) end
                transfer.index = 0
                self:Send(table.concat({"BK", "H", transfer.tab, record.stamp, #transfer.parts, transfer.public and "1" or "0", record.name}, "~"), "head:" .. key, transfer.target)
                local icon = store.icons[transfer.tab]
                if icon then self:Send(table.concat({"BK", "I", transfer.tab, record.stamp, icon}, "~"), "icon:" .. key, transfer.target) end
            else
                transfer.index = transfer.index + 1
                self:Send(table.concat({"BK", "D", transfer.tab, record.stamp, transfer.index, transfer.parts[transfer.index]}, "~"), "part:" .. key .. ":" .. transfer.index, transfer.target)
                if transfer.index == #transfer.parts then
                    self.sent[key] = {signature = record.stamp .. ":" .. tostring(transfer.public), at = GetTime()}
                    self.outgoing[key] = nil
                end
            end
            return
        end
    end
end

function Bank:Request()
    if not self:Store() or GetTime() - self.lastRequest < 60 then return end
    self.lastRequest = GetTime()
    self:Send("BK~Q", "request")
end

function Bank:OnMessage(message, channel, sender)
    local store = self:Store()
    if not store or #message > 240 or GuildHelper.Groups:IsSelfName(sender) then return end
    local rank, name = self:Member(sender)
    if rank == nil then return end
    self.peers[name] = true
    local parts = {strsplit("~", message)}
    local command, tab = parts[2], tonumber(parts[3])
    if command == "N" and #parts == 3 and channel == "GUILD" and tab and tab >= 1 and tab <= self.MAXTABS and tab == floor(tab) then
        store.count = tab
        self:Refresh()
        return
    end
    if command == "Q" and #parts == 2 and channel == "GUILD" then
        self.requests = self.requests or {}
        if self.requests[name] and GetTime() - self.requests[name] < 60 then return end
        self.requests[name] = GetTime()
        C_Timer.After(random(2, 6), function()
            if not self:Store() then return end
            for index in pairs(store.tabs) do
                local key = name .. ":" .. index
                local claim = self.claims[key]
                if self:Allowed(index) and (store.public[index] or rank == self.rank) and (not claim or claim.expires <= GetTime()) then
                    self.claims[key] = {sender = GuildHelper.Groups:Name(UnitName("player") .. "-" .. GetRealmName()), expires = GetTime() + 60}
                    self:Send("BK~C~" .. index .. "~" .. name, "claim:" .. key)
                    self:QueueTab(index, name)
                end
            end
            if self:IsLeader() then
                self:Debug("Sende Freigaben an Gilde wegen Anfrage von", name, "Zeitstempel", store.policyStamp or "FEHLT (aktuelle Zeit)")
                for index = 1, self.MAXTABS do
                    self:Send("BK~P~" .. index .. "~" .. (store.public[index] and "1" or "0") .. "~" .. (store.policyStamp or time() * 100), "policy:" .. index)
                end
            end
        end)
        return
    end
    if not tab or tab < 1 or tab > self.MAXTABS or tab ~= floor(tab) then return end
    if command == "C" and #parts == 4 and channel == "GUILD" then
        local targetRank, target = self:Member(parts[4])
        if target and (store.public[tab] or targetRank == rank) then
            local key = target .. ":" .. tab
            local previous = self.claims[key]
            local source = GuildHelper.Groups:Name(name)
            if not previous or previous.expires <= GetTime() or source < previous.sender then
                self.claims[key] = {sender = source, expires = GetTime() + 60}
            end
        end
        return
    end
    if command == "P" and #parts == 5 and rank ~= 0 then
        self:Debug("Freigabe von", name, "ignoriert: Rang", rank, "ist nicht Gildenleiter")
        return
    end
    if command == "P" and #parts == 5 and channel == "GUILD" then
        local stamp = tonumber(parts[5])
        if not stamp or stamp < (store.policyStamp or 0) then
            self:Debug("Freigabe Tab", tab, "von", name, "ignoriert: älter", parts[5], "<", store.policyStamp or 0)
            return
        end
        store.policyStamp = stamp
        local was = store.public[tab] == true
        store.public[tab] = parts[4] == "1" or nil
        if was ~= (store.public[tab] == true) then
            self:Debug("Freigabe Tab", tab, "von", name, was and "öffentlich -> privat" or "privat -> öffentlich", "Zeitstempel", stamp)
        end
        if not store.public[tab] and store.tabs[tab] and store.tabs[tab].public then
            self:Debug("Tab", tab, "gelöscht: Gildenleiter", name, "hat ihn auf privat gesetzt")
            store.tabs[tab] = nil
        end
        self:Refresh()
        return
    end
    local stamp = tonumber(parts[4])
    if not stamp or stamp < 1 or stamp > time() + 300 then return end
    local key = name .. ":" .. tab
    if command == "I" and #parts == 5 then
        if channel == "WHISPER" and rank ~= self.rank and not store.public[tab] then return end
        if channel ~= "WHISPER" and not store.public[tab] then return end
        local icon = self:ValidIcon(parts[5])
        if icon then
            store.icons[tab] = icon
            self:Refresh()
        end
        return
    end
    if command == "H" and #parts == 7 then
        local count, public = tonumber(parts[5]), parts[6] == "1"
        if not count or count < 1 or count > 20 or count ~= floor(count) or #parts[7] > 90 then return end
        if public then
            if not store.public[tab] then
                self:Debug("Tab", tab, "von", name, "ignoriert: hier nicht als öffentlich markiert")
                return
            end
        elseif channel ~= "WHISPER" or rank ~= self.rank then
            self:Debug("Tab", tab, "von", name, "ignoriert: privat, Rang", rank, "~= eigener Rang", self.rank)
            return
        end
        if store.tabs[tab] and store.tabs[tab].stamp > stamp then
            self:Debug("Tab", tab, "von", name, "ignoriert: älter als gespeicherter Stand")
            return
        end
        local pendingCount = 0
        for pendingKey, pending in pairs(self.pending) do
            if pending.expires < GetTime() then self.pending[pendingKey] = nil else pendingCount = pendingCount + 1 end
        end
        if pendingCount >= 16 and not self.pending[key] then return end
        self.pending[key] = {stamp = stamp, count = count, public = public, name = parts[7], parts = {}, expires = GetTime() + 120, rank = rank}
    elseif command == "D" and #parts == 6 then
        local pending = self.pending[key]
        local index = tonumber(parts[5])
        if not pending or pending.stamp ~= stamp or pending.expires < GetTime() or not index
            or index < 1 or index > pending.count or index ~= floor(index) then return end
        if pending.public then
            if not store.public[tab] then self.pending[key] = nil return end
        elseif channel ~= "WHISPER" or rank ~= self.rank then
            self.pending[key] = nil
            return
        end
        pending.parts[index] = parts[6]
        for i = 1, pending.count do if pending.parts[i] == nil then return end end
        local items = self:Decode(table.concat(pending.parts))
        self.pending[key] = nil
        if not items or (store.tabs[tab] and store.tabs[tab].stamp > stamp) then return end
        store.tabs[tab] = {items = items, name = pending.name, stamp = stamp, public = pending.public, rank = rank, authorized = true}
        self:Debug("Tab", tab, "von", name, "gespeichert:", pending.public and "öffentlich" or "privat", "Rang", rank, "Zeitstempel", stamp)
        self:Refresh()
    end
end

function Bank:Capture(tab)
    if not self.open or not self:Store() or not GetGuildBankTabInfo then return end
    local name, icon, view = GetGuildBankTabInfo(tab)
    if not name then return end
    icon = self:ValidIcon(icon)
    if icon then self:Store().icons[tab] = icon end
    if not view then
        local store = self:Store()
        if store.tabs[tab] then self:Debug("Tab", tab, "gelöscht: eigene Bank zeigt ihn als nicht einsehbar") end
        store.tabs[tab] = nil
        self:Refresh()
        return
    end
    local items = {}
    for slot = 1, self.SLOTS do
        local texture, count, locked = GetGuildBankItemInfo(tab, slot)
        if locked then return end
        if texture then
            local link = GetGuildBankItemLink(tab, slot)
            local id = link and tonumber(link:match("item:(%d+)"))
            if not id or not count or count < 1 then return end
            items[slot] = {id = id, count = count}
        end
    end
    local store = self:Store()
    local record = {items = items, name = GuildHelper.Groups:CleanText(name, 90), stamp = time(), rank = self.rank, authorized = true}
    local previous = store.tabs[tab]
    local encoded = self:Encode(record)
    self.emptySeen = self.emptySeen or {}
    if encoded == "" and previous and next(previous.items) and not self.emptySeen[tab] then
        self.emptySeen[tab] = true
        self:Debug("Tab", tab, "leer gelesen, gespeicherter Stand hat Gegenstände: warte auf Bestätigung")
        return
    end
    if encoded ~= "" then self.emptySeen[tab] = nil end
    if previous and previous.name == record.name and self:Encode(previous) == encoded then return end
    local count = 0
    for _ in pairs(items) do count = count + 1 end
    self:Debug("Tab", tab, "aus eigener Bank erfasst:", count, "Gegenstände")
    if previous then record.stamp = max(record.stamp, previous.stamp + 1) end
    store.tabs[tab] = record
    self:QueueTab(tab)
    self:Refresh()
end

function Bank:TabCount()
    if not self.open or not GetNumGuildBankTabs then return end
    local store = self:Store()
    local count = GetNumGuildBankTabs()
    if store and count > 0 and count <= self.MAXTABS and store.count ~= count then
        store.count = count
        self:Send("BK~N~" .. count, "tabcount")
    end
end

function Bank:Debug(...)
    if not self.debug then return end
    local parts = {}
    for index = 1, select("#", ...) do
        local value = select(index, ...)
        parts[index] = GuildHelper:CanAccessValue(value) and tostring(value) or "<geheim>"
    end
    print("|cff33ff99[GuildHelper Bank]|r " .. table.concat(parts, " "))
end

function Bank:DebugTab(tab, record, allowed, store)
    local state = "leer"
    if record then
        state = allowed and "sichtbar" or "versteckt"
        if not allowed then
            local name, _, view
            if GetGuildBankTabInfo then name, _, view = GetGuildBankTabInfo(tab) end
            if name and name ~= "" and not view then
                state = state .. " (eigene Bankrechte: nicht einsehbar)"
            elseif record.public and not store.public[tab] then
                state = state .. " (öffentlicher Tab, hier aber nicht freigegeben)"
            elseif record.rank ~= self.rank then
                state = state .. " (privat von Rang " .. tostring(record.rank) .. ", eigener Rang " .. tostring(self.rank) .. ")"
            end
        end
    end
    self.debugState = self.debugState or {}
    if self.debugState[tab] ~= state then
        if self.debugState[tab] then self:Debug("Anzeige Tab", tab, ":", self.debugState[tab], "->", state) end
        self.debugState[tab] = state
    end
end

function Bank:SetDebug(enabled)
    self.debug = enabled and true or nil
    self.debugState = nil
    GuildHelper:SetConfig("BANKDEBUG", self.debug == true)
    print("|cff33ff99[GuildHelper Bank]|r Debug " .. (self.debug and "an" or "aus"))
    if not self.debug then return end
    local store = self:Store()
    if not store then
        self:Debug("Kein Bank-Speicher: nicht in Gilde oder Rang unbekannt")
        return
    end
    self:Debug("Schlüssel", self.guild .. "#" .. self.rank, "Gildenleiter:", self:IsLeader() and "ja" or "nein", "Freigabe-Zeitstempel", store.policyStamp or "-")
    for tab = 1, self.MAXTABS do
        local record = store.tabs[tab]
        if record or store.public[tab] then
            self:Debug("Tab", tab, record and "Daten" or "keine Daten", store.public[tab] and "öffentlich" or "privat", "sichtbar:", self:Allowed(tab) and "ja" or "nein")
        end
    end
end

GuildHelper:AddSlash("ghbankdebug", function() Bank:SetDebug(not Bank.debug) end)

function Bank:Matches(item, search)
    if search == "" then return true end
    if tostring(item.id):find(search, 1, true) then return true end
    local getter = C_Item and C_Item.GetItemInfo or GetItemInfo
    local name = getter and getter(item.id)
    return name and strlower(name):find(search, 1, true) ~= nil or false
end

function Bank:Refresh()
    if not self.content or not self.content:IsVisible() then return end
    local store = self:Store()
    if not store then return end
    if store.count and self.selected > store.count then self.selected = 1 end
    local search = strlower(self.search:GetText() or "")
    for tab = 1, self.MAXTABS do
        local record = store.tabs[tab]
        local allowed = self:Allowed(tab)
        if self.debug then self:DebugTab(tab, record, allowed, store) end
        local count = 0
        if record and allowed then
            for _, item in pairs(record.items) do if self:Matches(item, search) then count = count + 1 end end
        end
        self.tabs[tab]:SetShown(tab <= (store.count or self.MAXTABS))
        local label = record and record.name or format(GuildHelper:Trans("LID_BANKTAB"), tab)
        if search ~= "" then label = label .. " (" .. count .. ")" end
        local button = self.tabs[tab]
        local icon = self:TabIcon(tab)
        GuildHelper.Members:SetPillText(button, label)
        button.tabIcon:SetTexture(icon)
        button.tabIcon:SetShown(icon ~= nil)
        button.text:ClearAllPoints()
        if icon then
            button:SetWidth(button:GetWidth() + 24)
            button.text:SetPoint("LEFT", button.tabIcon, "RIGHT", 6, 0)
        else
            button.text:SetPoint("CENTER", button, "CENTER", 0, 0)
        end
        GuildHelper.Members:SetPillActive(button, tab == self.selected)
    end
    local record = store.tabs[self.selected]
    local allowed = self:Allowed(self.selected)
    local status = self:IsLeader() and "LID_BANKNODATA" or "LID_BANKRELEASE"
    self.status:SetText(record and allowed and format(GuildHelper:Trans("LID_BANKUPDATED"), date("%Y-%m-%d %H:%M", record.stamp))
        or GuildHelper:Trans(status))
    self.release:SetShown(self:IsLeader())
    GuildHelper.Theme:SetTrans(self.release.text, store.public[self.selected] and "LID_BANKPRIVATE" or "LID_BANKPUBLIC")
    self.release:SetSize(max(200, self.release.text:GetStringWidth() + 40), 34)
    for slot, button in ipairs(self.slots) do
        local item = record and allowed and record.items[slot]
        local texture
        if item then
            local getter = C_Item and C_Item.GetItemIconByID or GetItemIcon
            texture = getter and getter(item.id)
        end
        button.item = item
        button.icon:SetTexture(texture or (item and "Interface\\Icons\\INV_Misc_QuestionMark"))
        button.count:SetText(item and item.count > 1 and item.count or "")
        button:SetAlpha(item and not self:Matches(item, search) and 0.18 or 1)
    end
end

function Bank:Layout()
    if not self.grid then return end
    local size = max(16, min(40, (self.grid:GetWidth() - 30) / 14 - 3, (self.grid:GetHeight() - 16) / 7 - 3))
    for slot, button in ipairs(self.slots) do
        local group = floor((slot - 1) / 14)
        local column = group * 2 + floor(((slot - 1) % 14) / 7)
        local row = (slot - 1) % 7
        button:ClearAllPoints()
        button:SetPoint("TOPLEFT", self.grid, "TOPLEFT", 8 + column * (size + 3) + group * 4, -8 - row * (size + 3))
        button:SetSize(size, size)
    end
end

function Bank:Build(content)
    local Theme, Members = GuildHelper.Theme, GuildHelper.Members
    self.content, self.tabs, self.slots = content, {}, {}
    GuildHelper.Window:CreatePageTitle(content, "LID_GUILDBANK")
    self.search = Theme:FlatNative(CreateFrame("EditBox", nil, content, "InputBoxTemplate"))
    self.search:SetSize(210, 26)
    self.search:SetPoint("TOPRIGHT", content, "TOPRIGHT", -GuildHelper.Window.MARGIN - 48, -28)
    self.search:SetAutoFocus(false)
    self.search:SetMaxLetters(60)
    self.search:SetScript("OnTextChanged", function() self:Refresh() end)
    self.search:SetScript("OnEscapePressed", function(box) box:SetText("") box:ClearFocus() end)
    self.searchHint = Theme:Text(content, 12, "muted")
    Theme:SetTrans(self.searchHint, "LID_BANKSEARCH")
    self.searchHint:SetPoint("TOPRIGHT", self.search, "BOTTOMRIGHT", 0, -4)
    self.grid = CreateFrame("Frame", nil, content)
    self.grid:SetPoint("TOPLEFT", content, "TOPLEFT", 18, -92)
    self.grid:SetPoint("BOTTOMRIGHT", content, "BOTTOMRIGHT", -190, 70)
    Theme:Panel(self.grid, "panel", "border", 8)
    for tab = 1, self.MAXTABS do
        local index = tab
        local button = Members:CreatePill(content, "")
        button:SetPoint("TOPLEFT", self.grid, "TOPRIGHT", 12, -(tab - 1) * 36)
        button:SetWidth(154)
        button:SetScript("OnClick", function() self.selected = index self:Refresh() end)
        button.tabIcon = button:CreateTexture(nil, "OVERLAY")
        button.tabIcon:SetSize(18, 18)
        button.tabIcon:SetPoint("LEFT", button, "LEFT", 8, 0)
        button.tabIcon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
        self.tabs[tab] = button
    end
    for slot = 1, self.SLOTS do
        local button = CreateFrame("Button", nil, self.grid)
        Theme:Panel(button, "control", "border", 2)
        button.icon = button:CreateTexture(nil, "ARTWORK")
        button.icon:SetPoint("TOPLEFT", 2, -2)
        button.icon:SetPoint("BOTTOMRIGHT", -2, 2)
        button.icon:SetTexCoord(0.06, 0.94, 0.06, 0.94)
        button.count = Theme:Text(button, 11, "text")
        button.count:SetPoint("BOTTOMRIGHT", -2, 2)
        button:SetScript("OnEnter", function(owner)
            if not owner.item then return end
            GameTooltip:SetOwner(owner, "ANCHOR_RIGHT")
            GameTooltip:SetHyperlink("item:" .. owner.item.id)
            GameTooltip:Show()
        end)
        button:SetScript("OnLeave", function() GameTooltip:Hide() end)
        self.slots[slot] = button
    end
    self.status = Theme:Text(content, 12, "muted")
    self.status:SetPoint("TOPLEFT", self.grid, "BOTTOMLEFT", 0, -12)
    self.status:SetPoint("RIGHT", content, "RIGHT", -24, 0)
    self.status:SetWordWrap(true)
    self.release = Members:CreateButton(content, "LID_BANKPUBLIC")
    self.release:SetPoint("BOTTOMLEFT", content, "BOTTOMLEFT", 18, 14)
    self.release:SetScript("OnClick", function()
        local store = self:Store()
        if store then self:Policy(self.selected, not store.public[self.selected]) end
    end)
    self.grid:SetScript("OnSizeChanged", function() self:Layout() end)
    content.OnPageShow = function() self:Store() self:Layout() self:Request() self:Refresh() end
    content.OnPageHide = function() self.search:ClearFocus() end
end

Bank.events = CreateFrame("Frame")
for _, event in ipairs({"PLAYER_LOGIN", "PLAYER_GUILD_UPDATE", "GUILD_ROSTER_UPDATE", "GUILDBANKFRAME_OPENED",
    "GUILDBANKFRAME_CLOSED", "GUILDBANKBAGSLOTS_CHANGED", "GUILDBANK_UPDATE_TABS", "GET_ITEM_INFO_RECEIVED",
    "PLAYER_INTERACTION_MANAGER_FRAME_SHOW", "PLAYER_INTERACTION_MANAGER_FRAME_HIDE"}) do
    if not C_EventUtils or not C_EventUtils.IsEventValid or C_EventUtils.IsEventValid(event) then Bank.events:RegisterEvent(event) end
end
Bank.events:SetScript("OnEvent", function(_, event, kind)
    if event == "PLAYER_INTERACTION_MANAGER_FRAME_SHOW" or event == "PLAYER_INTERACTION_MANAGER_FRAME_HIDE" then
        local banker = Enum and Enum.PlayerInteractionType and Enum.PlayerInteractionType.GuildBanker
        if not banker or kind ~= banker then return end
        event = event == "PLAYER_INTERACTION_MANAGER_FRAME_SHOW" and "GUILDBANKFRAME_OPENED" or "GUILDBANKFRAME_CLOSED"
        if event == "GUILDBANKFRAME_OPENED" and Bank.open then return end
    end
    if event == "GUILDBANKBAGSLOTS_CHANGED" and not Bank.open then
        Bank.events:GetScript("OnEvent")(Bank.events, "GUILDBANKFRAME_OPENED")
    end
    if event == "GUILDBANKFRAME_OPENED" then
        Bank.open = true
        Bank:Store()
        Bank.queryNext = 1
        Bank.queryAt = GetTime() + 1
        Bank:TabCount()
    elseif event == "GUILDBANKFRAME_CLOSED" then
        Bank.open = false
        Bank.scanAt = nil
        Bank.queryTab, Bank.queryNext = nil, nil
        Bank.queried, Bank.emptySeen = {}, {}
    elseif event == "GUILDBANKBAGSLOTS_CHANGED" and Bank.open then
        Bank.scanAt = GetTime() + 1
    elseif event == "GUILDBANK_UPDATE_TABS" and Bank.open then
        Bank:TabCount()
        Bank.queryNext = Bank.queryNext or 1
        Bank.queryAt = GetTime() + 1
    elseif event == "PLAYER_LOGIN" then
        if GuildHelper:GetConfig("BANKDEBUG", false) == true then C_Timer.After(5, function() Bank:SetDebug(true) end) end
        C_Timer.After(random(12, 20), function() Bank:Request() end)
    end
    Bank:Refresh()
end)
Bank.elapsed = 0
Bank.events:SetScript("OnUpdate", function(_, elapsed)
    Bank.elapsed = Bank.elapsed + elapsed
    if Bank.elapsed < 1 then return end
    Bank.elapsed = 0
    if Bank.scanAt and GetTime() >= Bank.scanAt then
        Bank.scanAt = nil
        local tab = Bank.queryTab or (GetCurrentGuildBankTab and GetCurrentGuildBankTab())
        if tab then Bank.queried[tab] = true end
        for index in pairs(Bank.queried) do Bank:Capture(index) end
        Bank.queryTab = nil
    end
    if Bank.queryTab and GetTime() > (Bank.queryDeadline or 0) then
        Bank.queryTab = nil
    end
    if Bank.open and Bank.queryNext and GetTime() >= (Bank.queryAt or 0) and not Bank.queryTab then
        local count = GetNumGuildBankTabs and GetNumGuildBankTabs() or 0
        local tab = Bank.queryNext
        if tab > min(count, Bank.MAXTABS) then
            Bank.queryNext = nil
        else
            Bank.queryNext = tab + 1
            Bank.queryAt = GetTime() + 4
            local _, _, view = GetGuildBankTabInfo(tab)
            if view and QueryGuildBankTab then
                Bank.queryTab = tab
                Bank.queryDeadline = GetTime() + 6
                QueryGuildBankTab(tab)
            end
        end
    end
    Bank:Pump()
end)
GuildHelper.Window:SetPageBuilder("guildbank", function(content) Bank:Build(content) end)
GuildHelper.Window:OnRebuild(function() Bank.content = nil end)
GuildHelper.Theme:OnRefresh(function() Bank:Refresh() end)

