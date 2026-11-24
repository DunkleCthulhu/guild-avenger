local addonName, addon = ...
local L = addon.Text
local prefix = "GuildAvenger2"
local version = C_AddOns.GetAddOnMetadata(addonName, "Version") or "0.0.0"
local downloadURL = "https://github.com/DunkleCthulhu/guild-avenger/releases/latest"
local maxEntries = 1000
local results = Enum.SendAddonMessageResult
local roster, rosterScope, rosterRequestedAt = {}, nil, nil
local sending, ticker, sequence = nil, nil, 0
local incoming = {}
local published, waiting = {}, {}
local requestedLists, guildRequests = {}, {}
local pullInbox, inboxScope = {}, nil
local lastListRequest
local requestLifetime = 300
local requestCooldown = 60
local makePackets, enqueue

local function transferID()
    sequence = sequence % 65535 + 1
    return ("%x.%x"):format(GetServerTime(), sequence)
end

local function versionRank(value)
    local major, minor, patch = value:match("^(%d%d?%d?)%.(%d%d?%d?)%.(%d%d?%d?)$")
    if major then
        return tonumber(major) * 1000000 + tonumber(minor) * 1000 + tonumber(patch)
    end
end

local installedRank = versionRank(version) or 0

local function installMessage(release, language)
    return addon.TextFor(language, "installMessage", release, downloadURL, addon.TextFor(language, "projectInfo"))
end

local function downloadLink()
    return ("|Haddon:GuildAvengerDownload|h[%s]|h"):format(L("downloadLinkLabel"))
end

function addon.OpenDownload()
    addon.PromptDownload(downloadURL, L("projectInfo"))
end

local function guildScope()
    local scope = addon.Scope()
    if scope and scope ~= "local" and IsInGuild() then
        return scope
    end
end

local function inbox()
    local scope = guildScope()
    if inboxScope ~= scope then
        pullInbox, inboxScope = {}, scope
    end
    return pullInbox
end

function addon.InboxCount()
    local count = 0
    for sender in pairs(inbox()) do
        if addon.IsGuildMember(sender) then count = count + 1 end
    end
    return count
end

local function sourceLabel(names)
    if #names <= 4 then return table.concat(names, ", ") end
    return table.concat(names, ", ", 1, 4) .. " +" .. (#names - 4)
end

function addon.PreviewInbox()
    local scope = guildScope()
    local replies, senders, combined, notes, sources, existing = {}, {}, {}, {}, {}, {}
    for key, reply in pairs(inbox()) do
        if addon.IsGuildMember(key) then
            replies[key] = reply
            senders[#senders + 1] = key
        end
    end
    if #senders == 0 then return end
    table.sort(senders)
    for _, entry in ipairs(addon.Entries()) do existing[addon.RecordKey(entry)] = entry end
    for _, sender in ipairs(senders) do
        local reply = replies[sender]
        for key, record in pairs(reply.entries) do
            if not combined[key] then
                local copy = {}
                for field, value in pairs(record) do copy[field] = value end
                combined[key], sources[key], notes[key] = copy, {}, {}
            end
            local item = combined[key]
            item.deaths = math.max(item.deaths, record.deaths)
            item.high = item.high or record.high
            sources[key][#sources[key] + 1] = reply.sender
            local noteSources = notes[key][record.note] or {}
            noteSources[#noteSources + 1] = reply.sender
            notes[key][record.note] = noteSources
        end
    end
    for key, item in pairs(combined) do
        if existing[key] and item.note == existing[key].note then
            local alternatives = {}
            for note in pairs(notes[key]) do
                if note ~= item.note then alternatives[#alternatives + 1] = note end
            end
            table.sort(alternatives)
            item.note = alternatives[1] or item.note
        end
    end
    local added, updated, changes = addon.Merge(combined, true, true)
    local planned = {}
    for _, change in ipairs(changes) do
        local key = change.key
        local variants = {}
        for note, authors in pairs(notes[key]) do
            variants[#variants + 1] = {note = note, authors = sourceLabel(authors)}
        end
        if change.previous and not notes[key][change.oldNote] then
            variants[#variants + 1] = {note = change.oldNote, authors = L("currentNote")}
        end
        table.sort(variants, function(left, right) return left.note < right.note end)
        change.sources = sourceLabel(sources[key])
        change.variants = variants
        planned[key] = change
    end
    local function accept(selection)
        if not addon.UpdateScope() or guildScope() ~= scope then
            addon.Say(L("importSenderLeft"))
            return
        end
        for key in pairs(replies) do
            if not addon.IsGuildMember(key) then
                addon.RefreshUI()
                addon.Say(L("importSenderLeft"))
                return
            end
        end
        local current = inbox()
        for key, reply in pairs(replies) do
            if current[key] == reply then current[key] = nil end
        end
        local newEntries, updatedEntries, _, removedEntries = addon.Merge(selection, false, true, planned)
        addon.Say(L("importFinished", newEntries, updatedEntries, removedEntries or 0))
    end
    return {added = added, updated = updated, changes = changes, removed = 0, accept = accept, replyCount = #senders}
end

function addon.ReadRoster()
    local scope = guildScope()
    if not scope or not GetGuildRosterInfo or not GetNumGuildMembers then
        roster, rosterScope = {}, nil
        return
    end
    local count = GetNumGuildMembers()
    if not addon.Ordinary(count) or type(count) ~= "number" then
        roster, rosterScope = {}, nil
        return
    end
    local updated = {}
    for index = 1, count do
        local name, _, rank, _, _, _, _, _, online = GetGuildRosterInfo(index)
        local key, full = addon.PlayerName(name, true)
        if key then
            updated[key] = { name = full, online = addon.Ordinary(online) and online == true,
                leader = addon.Ordinary(rank) and rank == 0 }
        end
    end
    local own = addon.UnitName("player")
    if own and updated[own] then
        roster, rosterScope = updated, scope
    else
        roster, rosterScope = {}, nil
    end
    addon.RefreshSuggestions()
end

function addon.RefreshRoster()
    local scope = guildScope()
    if scope ~= rosterScope then
        roster, rosterScope, incoming = {}, nil, {}
        rosterRequestedAt = nil
    end
    if scope and (not rosterRequestedAt or GetTime() - rosterRequestedAt >= 5) then
        rosterRequestedAt = GetTime()
        C_GuildInfo.GuildRoster()
    end
end

function addon.IsGuildMember(key)
    return rosterScope ~= nil and rosterScope == guildScope() and roster[key] ~= nil
end

function addon.IsGuildLeaderKey(key)
    return addon.IsGuildMember(key) and roster[key].leader == true
end

function addon.SuggestRecipients(value)
    local matching = {}
    if not rosterScope or rosterScope ~= guildScope() then
        return matching
    end
    local normalized = addon.LowerName(value):gsub("%-", " "):gsub("^%s+", "")
    local own = addon.UnitName("player")
    for key, member in pairs(roster) do
        if member.online and key ~= own and key:find(normalized, 1, true) then
            matching[#matching + 1] = member.name
        end
    end
    table.sort(matching, function(left, right) return addon.LowerName(left) < addon.LowerName(right) end)
    return matching
end

local function stopSending(message)
    if not sending.quiet then
        addon.Say(message)
    end
    sending = table.remove(waiting, 1)
    if sending then
        sending.progressAt = GetTime()
    else
        ticker:Cancel()
        ticker = nil
    end
end

local function sendNext()
    if not addon.UpdateScope() or sending.scope ~= guildScope() or not addon.IsGuildMember(sending.key) then
        stopSending(L("recipientLeftRoster"))
        return
    end
    local member = roster[sending.key]
    local result = C_ChatInfo.SendAddonMessage(prefix, sending.packets[sending.position], "WHISPER", member.name)
    if result == results.AddonMessageThrottle or result == results.ChannelThrottle
        or result == results.AddOnMessageLockdown then
        if GetTime() - sending.progressAt > 45 then
            stopSending(L("transferBlocked"))
        end
        return
    end
    if result ~= results.Success then
        stopSending(L("transferFailed", member.name))
        return
    end
    sending.position = sending.position + 1
    sending.progressAt = GetTime()
    if sending.position > #sending.packets then
        stopSending(L("transferDone", member.name))
    end
end

local function recipient(input)
    if input == "" then
        local key = addon.UnitName("target")
        return key
    end
    local key = addon.PlayerName(input, true)
    if key or not input:match("^%S+$") then
        return key
    end
    local typed = addon.PlayerName(input .. " Placeholder")
    if not typed then
        return
    end
    typed = typed:match("^(%S+)")
    local exact
    for rosterKey in pairs(roster) do
        local first = rosterKey:match("^(%S+)")
        if first == typed then
            if exact then
                return nil, L("ambiguousRecipient")
            end
            exact = rosterKey
        end
    end
    return exact
end

function addon.Share(input, selection, includeRemovals)
    if sending then
        return false, L("transferInProgress")
    end
    if not addon.UpdateScope() or not guildScope() then
        return false, L("sharingRequiresGuild")
    end
    addon.RefreshRoster()
    if rosterScope ~= guildScope() then
        return false, L("rosterLoading")
    end
    local key, message = recipient(input)
    if not key or key == addon.UnitName("player") or not addon.IsGuildMember(key) then
        return false, message or L("enterRecipient")
    end
    local member = roster[key]
    if not member.online then
        return false, L("recipientOffline", member.name)
    end
    local packets, message = makePackets(selection, includeRemovals)
    if not packets then
        return false, message
    end
    enqueue(key, packets)
    return true, L("transferStarted", member.name)
end

makePackets = function(selection, includeRemovals, pullID)
    local entries = {}
    local removals = includeRemovals and not selection and addon.RemovalProposals() or {}
    for _, entry in ipairs(addon.Entries()) do
        local entryKey = addon.RecordKey(entry)
        if (not selection or selection[entryKey]) and addon.EligibleRecord(entryKey, entry) then
            entries[#entries + 1] = entry
        end
    end
    if #entries + #removals == 0 then
        return nil, L("nothingToShare")
    end
    if #entries + #removals > maxEntries then
        return nil, L("tooManyEntries")
    end

    local id = transferID()
    local start = ("B\t%s\t%d"):format(id, #entries)
    if pullID then start = start .. "\t" .. pullID end
    local packets = { start, ("V\t%s\t%s"):format(id, version) }
    if #removals > 0 then
        packets[#packets + 1] = ("D\t%s\t%d"):format(id, #removals)
        for _, entry in ipairs(removals) do
            packets[#packets + 1] = ("X\t%s\t%s\t%s"):format(id, entry.kind, entry.name)
        end
    end
    for index, entry in ipairs(entries) do
        local faction = entry.kind == "G" and "G" or (entry.faction == "Alliance" and "A" or "H")
        packets[#packets + 1] = ("R\t%s\t%d\t%s\t%d\t%d\t%s"):format(id, index, faction,
            entry.addedAt, entry.deaths, entry.name)
        -- Existing 2.0 clients ignore the optional priority packet.
        if entry.high then
            packets[#packets + 1] = ("H\t%s\t%d\t1"):format(id, index)
        end
        packets[#packets + 1] = ("N\t%s\t%d\t%s\t%s"):format(id, index, entry.author, entry.note)
    end
    return packets, id
end

enqueue = function(key, packets, quiet)
    local job = { scope = guildScope(), key = key, position = 1, packets = packets,
        progressAt = GetTime(), quiet = quiet }
    if sending then
        if #waiting >= 20 then return false end
        waiting[#waiting + 1] = job
    else
        sending = job
        ticker = C_Timer.NewTicker(0.25, sendNext)
    end
    return true
end

function addon.RequestWatchlists()
    if not addon.UpdateScope() or not guildScope() then return false, L("sharingRequiresGuild") end
    addon.RefreshRoster()
    local scope, own, now = guildScope(), addon.UnitName("player"), GetTime()
    if not addon.IsGuildMember(own) then return false, L("rosterLoading") end
    if lastListRequest and lastListRequest.scope == scope and now - lastListRequest.at < requestCooldown then
        return false, L("listRequestCooldown")
    end
    local id = transferID()
    if C_ChatInfo.SendAddonMessage(prefix, "P\t" .. id, "GUILD") ~= results.Success then
        return false, L("shareRequestFailed")
    end
    for key, request in pairs(requestedLists) do
        if request.scope ~= scope or now - request.at >= requestLifetime then requestedLists[key] = nil end
    end
    lastListRequest = { scope = scope, at = now, received = {} }
    requestedLists[id] = lastListRequest
    return true, L("listRequestSent")
end

local function replyToListRequest(sender, id)
    local request = guildRequests[sender]
    local member = addon.IsGuildMember(sender) and roster[sender]
    if not request or request.id ~= id or not member or not member.online or request.scope ~= guildScope()
        or GetTime() - request.at >= requestLifetime then
        return false, L("listRequestExpired")
    end
    if request.sent then return false, L("listRequestAlreadySent") end
    local packets, errorMessage = makePackets(nil, false, id)
    if not packets then return false, errorMessage end
    if not enqueue(sender, packets) then return false, L("transferInProgress") end
    request.sent = true
    return true, L("transferStarted", member.name)
end

local function receiveListRequest(sender, id)
    local member, scope, now = roster[sender], guildScope(), GetTime()
    local request = guildRequests[sender]
    if not member.online or (request and request.scope == scope
        and (request.id == id or now - request.at < requestCooldown)) then return end

    for key, previous in pairs(guildRequests) do
        if now - previous.at >= requestLifetime or previous.scope ~= scope then guildRequests[key] = nil end
    end
    request = { id = id, scope = scope, at = now }
    guildRequests[sender] = request
    local function offerReply()
        local link = ("|Haddon:GuildAvengerPull:%s:%s|h[%s]|h"):format(id, sender, L("replyToListRequest"))
        addon.Say(L("guildmateRequestedList", member.name, link))
    end
    if GuildAvengerDB.replyToListRequests then
        C_Timer.After(math.random(5, 30) / 10, function()
            if guildScope() ~= scope or guildRequests[sender] ~= request or request.sent
                or not addon.IsGuildMember(sender) then return end
            if GuildAvengerDB.replyToListRequests and replyToListRequest(sender, id) then return end
            offerReply()
        end)
    else
        offerReply()
    end
end

function addon.Publish(selection, includeRemovals)
    if not addon.UpdateScope() or not guildScope() then
        return false, L("publishingRequiresGuild")
    end
    if C_ChatInfo.InChatMessagingLockdown and C_ChatInfo.InChatMessagingLockdown() then
        return false, L("chatLockdown")
    end
    local packets, id = makePackets(selection, includeRemovals)
    if not packets then
        return false, id
    end
    local now = GetTime()
    for key, offer in pairs(published) do
        if now - offer.at >= 1800 or offer.scope ~= guildScope() then
            published[key] = nil
        end
    end
    published[id] = { packets = packets, at = now, scope = guildScope(), requested = {} }
    C_ChatInfo.SendChatMessage("[Guild Avenger " .. id .. "]", "GUILD")
    C_ChatInfo.SendChatMessage(installMessage(version, addon.Language()), "GUILD")
    return true, L("listPublished")
end

local function chatFilter(_, _, message, sender, ...)
    if not addon.IsText(message) then
        return false
    end
    local release = message:match("^Guild Avenger v([%d.]+)%. ")
    local availableRank = release and versionRank(release)
    -- Plain guild chat uses the sender's language. Addon links use the reader's language.
    if availableRank and (message == installMessage(release, "ukUA") or message == installMessage(release, "enUS")) then
        if availableRank <= installedRank then
            return true
        end
        return false, ("Guild Avenger %s · %s · %s"):format(release, downloadLink(), L("projectInfo")), sender, ...
    end
    local id = message:match("^%[Guild Avenger ([%da-f]+%.[%da-f]+)%]$")
    local key = id and #id <= 16 and addon.PlayerName(sender, true)
    if not key then
        return false
    end
    local link = ("|Haddon:GuildAvenger:%s:%s|h[%s]|h"):format(id, key, L("shareLinkLabel"))
    return false, link, sender, ...
end

local function requestLink(_, link, _, mouseButton)
    if not addon.IsText(link) or mouseButton ~= "LeftButton" then
        return
    end
    if link == "addon:GuildAvengerDownload" then
        addon.OpenDownload()
        return
    end
    local pullID, requester = link:match("^addon:GuildAvengerPull:([%da-f]+%.[%da-f]+):([^:]+)$")
    if pullID then
        if addon.UpdateScope() then
            local _, message = replyToListRequest(requester, pullID)
            addon.Say(message)
        end
        return
    end
    local id, sender = link:match("^addon:GuildAvenger:([%da-f]+%.[%da-f]+):([^:]+)$")
    if not id or #id > 16 or not addon.UpdateScope() or not guildScope() then
        return
    end
    if sender == addon.UnitName("player") then
        addon.Say(L("ownShareLink"))
        return
    end
    addon.RefreshRoster()
    local member = addon.IsGuildMember(sender) and roster[sender]
    if not member or not member.online then
        addon.Say(L("shareAuthorOffline"))
        return
    end
    local result = C_ChatInfo.SendAddonMessage(prefix, "Q\t" .. id, "WHISPER", member.name)
    if result == results.Success then
        addon.Say(L("shareRequestSent"))
    else
        addon.Say(L("shareRequestFailed"))
    end
end

local function finish(sender, batch)
    incoming[sender] = nil
    local entries = {}
    for _, part in pairs(batch.records) do
        if entries[part.key] then
            return
        end
        entries[part.key] = { name = part.name, kind = part.kind, faction = part.faction, addedAt = part.addedAt,
            deaths = part.deaths, author = part.author, note = part.note, high = part.high }
    end
    for key, record in pairs(batch.removals) do
        if entries[key] then return end
        entries[key] = record
    end
    local owner = batch.pull
    if owner then
        if owner.received[sender] then return end
        owner.received[sender] = true
        local current = inbox()
        if not current[sender] or owner.at >= current[sender].at then
            current[sender] = {sender = roster[sender].name, entries = entries, at = owner.at}
            addon.RefreshUI()
        end
        return
    end
    local function canImport()
        return addon.UpdateScope() and guildScope() == batch.scope and addon.IsGuildMember(sender)
    end
    addon.OfferImport(roster[sender].name, function()
        if not canImport() then return end
        local added, updated, changes, removed = addon.Merge(entries, true, batch.explicit)
        local planned = {}
        for _, change in ipairs(changes or {}) do planned[change.key] = change end
        local function accept(selection)
            if not canImport() then
                addon.Say(L("importSenderLeft"))
                return
            end
            local newEntries, updatedEntries, _, removedEntries = addon.Merge(selection, false, batch.explicit, planned)
            addon.Say(L("importFinished", newEntries, updatedEntries, removedEntries or 0))
        end
        return { added = added, updated = updated, changes = changes or {}, accept = accept, removed = removed }
    end)
end

function addon.Receive(receivedPrefix, message, channel, senderName)
    if not addon.IsText(receivedPrefix) or receivedPrefix ~= prefix or not addon.IsText(channel)
        or (channel ~= "WHISPER" and channel ~= "GUILD")
        or not addon.IsText(message) or #message > 240 or not addon.UpdateScope() then
        return
    end
    local sender = addon.PlayerName(senderName, true)
    if not sender or sender == addon.UnitName("player") or not addon.IsGuildMember(sender) then
        return
    end
    if channel == "GUILD" then
        local id = message:match("^P\t([%da-f]+%.[%da-f]+)$")
        if id and #id <= 16 then receiveListRequest(sender, id) end
        return
    end
    local requestID = message:match("^Q\t([%da-f]+%.[%da-f]+)$")
    if requestID then
        local offer, now = published[requestID], GetTime()
        if offer and offer.scope == guildScope() and now - offer.at < 1800
            and (not offer.requested[sender] or now - offer.requested[sender] >= 10) then
            offer.requested[sender] = now
            enqueue(sender, offer.packets, true)
        end
        return
    end
    local operation, id, data = message:match("^([BRNHVDX])\t([%da-f]+%.[%da-f]+)\t(.*)$")
    if not operation or #id > 16 then
        return
    end
    local now = GetTime()
    if operation == "B" then
        local number, pullID = data:match("^(%d+)\t([%da-f]+%.[%da-f]+)$")
        local owner = pullID and requestedLists[pullID]
        if pullID and (not owner or owner.scope ~= guildScope()
            or now - owner.at >= requestLifetime or owner.received[sender] or not roster[sender].online) then
            return
        end
        local count = tonumber(number or data:match("^%d+$"))
        if not count or count > maxEntries then
            return
        end
        for key, old in pairs(incoming) do
            if now - old.progressAt > 75 or not addon.IsGuildMember(key) then
                incoming[key] = nil
            end
        end
        incoming[sender] = { id = id, count = count, ready = 0, records = {}, progressAt = now, scope = guildScope(),
            removals = {}, removalCount = 0, pull = owner }
        return
    end
    local batch = incoming[sender]
    if not batch or batch.id ~= id or batch.scope ~= guildScope() or now - batch.progressAt > 75 then
        return
    end
    if operation == "V" then
        local senderRank = not batch.version and versionRank(data)
        if senderRank then
            batch.version = data
            batch.explicit = senderRank >= 2004000
            if senderRank > installedRank then
                addon.Say(L("shareNewerVersion", data, downloadLink()))
            end
        end
        return
    end
    if operation == "D" then
        local count = data:match("^%d+$") and tonumber(data)
        if not batch.pull and batch.explicit and not batch.expectedRemovals and not next(batch.records)
            and count and count > 0 and batch.count + count <= maxEntries then
            batch.expectedRemovals, batch.progressAt = count, now
        end
        return
    elseif operation == "X" then
        if not batch.expectedRemovals or batch.removalCount >= batch.expectedRemovals then return end
        local kind, name = data:match("^([PG])\t([^\t]+)$")
        local key, full = addon.EntryName(name, kind)
        if not key or batch.removals[key] then return end
        batch.removals[key] = { name = full, kind = kind, removed = true }
        batch.removalCount = batch.removalCount + 1
        batch.progressAt = now
        if batch.ready == batch.count and batch.removalCount == batch.expectedRemovals then finish(sender, batch) end
        return
    end
    local indexText, fields = data:match("^(%d+)\t(.*)$")
    local index = tonumber(indexText)
    if not index or index < 1 or index > batch.count then
        return
    end
    local record = batch.records[index] or {}
    if operation == "R" and not record.key then
        local faction, addedAt, deaths, name = fields:match("^([AHG])\t(%d+)\t(%d+)\t([^\t]+)$")
        local kind = faction == "G" and "G" or "P"
        local key, full = addon.EntryName(name, kind)
        addedAt, deaths = tonumber(addedAt), tonumber(deaths)
        if not key or not addedAt or addedAt > 4294967295 or not deaths or deaths > 2147483647 then
            return
        end
        record.key, record.name, record.kind = key, full, kind
        record.faction = kind == "P" and (faction == "A" and "Alliance" or "Horde") or nil
        record.addedAt, record.deaths = addedAt, deaths
    elseif operation == "H" and record.key and record.note == nil and fields == "1" then
        record.high = true
    elseif operation == "N" and record.note == nil then
        local author, note = fields:match("^([^\t]*)\t([^\t]*)$")
        note = addon.Clean(note, addon.NoteLimit)
        local full
        if author ~= "" then
            local _
            _, full = addon.PlayerName(author)
        end
        if note == nil or (author ~= "" and not full) then
            return
        end
        record.author, record.note = full or "", note
    else
        return
    end
    batch.records[index], batch.progressAt = record, now
    if record.key and record.note ~= nil then
        batch.ready = batch.ready + 1
        if batch.ready == batch.count and batch.removalCount == (batch.expectedRemovals or 0) then
            finish(sender, batch)
        end
    end
end

function addon.InitSync()
    C_ChatInfo.RegisterAddonMessagePrefix(prefix)
    local addFilter = ChatFrameUtil and ChatFrameUtil.AddMessageEventFilter or ChatFrame_AddMessageEventFilter
    if addFilter and EventRegistry then
        addFilter("CHAT_MSG_GUILD", chatFilter)
        EventRegistry:RegisterCallback("SetItemRef", requestLink)
    end
end
