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
local receipts = {}
local published, waiting = {}, {}
local requestedLists, guildRequests = {}, {}
local pendingGuildRequests = {}
local pendingWhispers = {}
local pullInbox, inboxScope, inboxCharacter = {}, nil, nil
local lastListRequest
local hourlyInterval, loginSyncPending = 3600, true
local automaticReplies, automaticReplyScope = {}, nil
local requestLifetime = 300
local requestCooldown = 60
local rosterWait, maxPendingRequests = 15, 32
local maxPendingWhispers = 128
local whisperWait = 60
local autoReplyRevision = 0
local autoSyncRevision = 0
local packetLimit = 240
local capabilities = "M"
local capable, announced, probing = {}, {}, {}
local makePackets, enqueue, currentMember, drainGuildRequests
local autoSyncSettings

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

local function installMessage(release, language, short)
    if short then
        return addon.TextFor(language, "installMessageShort", release, downloadURL)
    end
    return addon.TextFor(language, "installMessage", release, downloadURL, addon.TextFor(language, "projectInfo"))
end

-- A chat message holds 255 bytes, and the Ukrainian text is close to that.
local function fittingInstallMessage(release, language)
    local message = installMessage(release, language)
    return #message <= 255 and message or installMessage(release, language, true)
end

local function isInstallMessage(message, release)
    for _, language in ipairs({ "ukUA", "enUS" }) do
        if message == installMessage(release, language) or message == installMessage(release, language, true) then
            return true
        end
    end
    return false
end

local function downloadLink()
    return ("|Haddon:GuildAvengerDownload|h[%s]|h"):format(L("downloadLinkLabel"))
end

function addon.OpenDownload()
    addon.PromptDownload(downloadURL, L("projectInfo"))
end

local guildScope = addon.GuildScope

local function inbox()
    local scope = guildScope()
    local guid = UnitGUID("player")
    local character = addon.IsText(guid) and guid:match("^Player%-%d+%-%x+$") or nil
    if inboxScope ~= scope or inboxCharacter ~= character then
        inboxScope, inboxCharacter, pullInbox = scope, character, {}
        if scope and character then
            local saved = GuildAvengerDB.watchlistInbox
            saved[character] = saved[character] or {}
            saved[character][scope] = saved[character][scope] or {}
            pullInbox = saved[character][scope]
            -- Request ordering uses session time. Every new request follows the restored replies.
            for _, reply in pairs(pullInbox) do reply.at = 0 end
        end
    end
    return pullInbox
end

local function sourceLabel(names)
    if #names <= 4 then return table.concat(names, ", ") end
    return table.concat(names, ", ", 1, 4) .. " +" .. (#names - 4)
end

local function recordRevision(record)
    local first, second = 0, 0
    for index = 1, #record.note do
        local byte = record.note:byte(index)
        first = (first * 131 + byte) % 2147483647
        second = (second * 137 + byte) % 2147483629
    end
    return ("%d:%d:%d:%d:%d"):format(record.deaths, record.high and 1 or 0, #record.note, first, second)
end

local function reviewNote(record, own)
    if record.keepLocalNote and own then return own.note end
    return record.note
end

local function changesRecord(record, own)
    return not own or reviewNote(record, own) ~= own.note or record.deaths > own.deaths
        or (not record.keepLocalPriority and (record.high == true) ~= (own.high == true))
end

local function hasReviewableChange(key, record)
    return not record.removed and addon.EligibleRecord(key, record) and changesRecord(record, addon.WatchlistRecord(key))
end

local function acknowledgeReply(reply, settings)
    if not settings or not reply.revisions then return end
    local reviewed = settings.reviewed[reply.identity] or {}
    settings.reviewed[reply.identity] = reviewed
    for key, revision in pairs(reply.revisions) do reviewed[key] = revision end
end

local function reviewableReplies()
    local current, replies = inbox(), {}
    local count = 0
    for sender, reply in pairs(current) do
        if currentMember(sender, reply.identity) then
            for key, record in pairs(reply.entries) do
                if hasReviewableChange(key, record) then
                    replies[sender], count = reply, count + 1
                    break
                end
            end
            if not replies[sender] then
                acknowledgeReply(reply, autoSyncSettings())
                current[sender] = nil
            end
        end
    end
    return replies, count
end

function addon.InboxCount()
    local _, count = reviewableReplies()
    return count
end

function addon.PreviewInbox()
    local scope = guildScope()
    local replies = reviewableReplies()
    local senders, combined, notes, sources, existing = {}, {}, {}, {}, {}
    local proposedPriority = {}
    for key in pairs(replies) do senders[#senders + 1] = key end
    if #senders == 0 then return end
    table.sort(senders)
    for _, entry in ipairs(addon.Entries()) do existing[addon.RecordKey(entry)] = entry end
    for _, sender in ipairs(senders) do
        local reply = replies[sender]
        for key, record in pairs(reply.entries) do
            local note = reviewNote(record, existing[key])
            if not combined[key] then
                local copy = {}
                for field, value in pairs(record) do copy[field] = value end
                copy.note, copy.keepLocalNote, copy.keepLocalPriority = note, nil, nil
                combined[key], sources[key], notes[key] = copy, {}, {}
            end
            local item = combined[key]
            item.deaths = math.max(item.deaths, record.deaths)
            if not existing[key] or not record.keepLocalPriority then
                proposedPriority[key] = proposedPriority[key] or record.high == true
            end
            sources[key][#sources[key] + 1] = reply.sender
            local noteSources = notes[key][note] or {}
            noteSources[#noteSources + 1] = reply.sender
            notes[key][note] = noteSources
        end
    end
    for key, item in pairs(combined) do
        if proposedPriority[key] == nil and existing[key] then
            item.high = existing[key].high
        else
            item.high = proposedPriority[key] or nil
        end
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
        -- A death count row has its own key and names its entry. It offers no note to choose.
        local key = change.entry or change.key
        if not change.countOnly then
            local variants = {}
            for note, authors in pairs(notes[key]) do
                variants[#variants + 1] = {note = note, authors = sourceLabel(authors)}
            end
            if change.previous and not notes[key][change.oldNote] then
                variants[#variants + 1] = {note = change.oldNote, authors = L("currentNote")}
            end
            table.sort(variants, function(left, right) return left.note < right.note end)
            change.variants = variants
        end
        change.sources = sourceLabel(sources[key])
        planned[change.key] = change
    end
    local function accept(selection)
        if not addon.UpdateScope() or guildScope() ~= scope then
            addon.Say(L("importSenderLeft"))
            return
        end
        for key, reply in pairs(replies) do
            if not currentMember(key, reply.identity) then
                addon.RefreshUI()
                addon.Say(L("importSenderLeft"))
                return
            end
        end
        local current = inbox()
        local settings = autoSyncSettings()
        for key, reply in pairs(replies) do
            if current[key] == reply then
                current[key] = nil
                acknowledgeReply(reply, settings)
            end
        end
        local newEntries, updatedEntries, _, removedEntries = addon.Merge(selection, false, true, planned)
        addon.Say(L("importFinished", newEntries, updatedEntries, removedEntries or 0))
    end
    return {added = added, updated = updated, changes = changes, removed = 0, accept = accept, replyCount = #senders}
end

local function rosterName(value)
    local key, name, suffix = addon.PlayerName(value, true)
    if not key then return end
    local qualified = suffix ~= nil
    local realm = GetNormalizedRealmName and GetNormalizedRealmName()
    if suffix and addon.IsText(realm) and suffix == addon.LowerName(realm) then suffix = nil end
    return key, name, suffix, qualified
end

local function readMember(index)
    local raw, _, rank, _, _, _, _, _, online, _, _, _, _, _, _, _, guid = GetGuildRosterInfo(index)
    local key, name, suffix = rosterName(raw)
    if not key then return end
    local address = addon.Clean(raw, addon.NameLimit + 64)
    -- Keep existing per-character consent and review history keyed to the same roster identity.
    local oldSuffix = suffix and addon.LegacyLowerName(raw:match("%-([^ %-]+)$") or suffix) or ""
    local identity = addon.LegacyLowerName(name) .. "\t" .. oldSuffix .. "\t" .. (addon.IsText(guid) and guid or "")
    return key, {name = name, address = address, suffix = suffix, identity = identity, index = index,
        online = addon.Ordinary(online) and online == true, leader = addon.Ordinary(rank) and rank == 0}
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
        local key, member = readMember(index)
        if key then
            updated[key] = updated[key] and {ambiguous = true} or member
        end
    end
    local own = addon.UnitName("player")
    if own and updated[own] then
        roster, rosterScope = updated, scope
    else
        roster, rosterScope = {}, nil
    end
    addon.RefreshSuggestions()
    if rosterScope then
        local queued, now = pendingWhispers, GetTime()
        pendingWhispers = {}
        for _, packet in ipairs(queued) do
            if packet.scope == scope and now - packet.at < whisperWait then
                addon.Receive(prefix, packet.message, "WHISPER", packet.sender)
            end
        end
        drainGuildRequests()
    end
end

function addon.RefreshRoster()
    local scope = guildScope()
    if scope ~= rosterScope then
        roster, rosterScope, incoming = {}, nil, {}
        capable, announced, probing = {}, {}, {}
        rosterRequestedAt = nil
    end
    if scope and (not rosterRequestedAt or GetTime() - rosterRequestedAt >= 5) then
        rosterRequestedAt = GetTime()
        C_GuildInfo.GuildRoster()
    end
end

function addon.IsGuildAlly(key)
    return rosterScope ~= nil and rosterScope == guildScope() and roster[key] ~= nil
end

local function guildMember(key)
    if addon.IsGuildAlly(key) and not roster[key].ambiguous then return roster[key] end
end

function addon.IsGuildMember(key)
    return guildMember(key) ~= nil
end

currentMember = function(key, identity)
    local member = guildMember(key)
    if not member or member.identity ~= identity then return end
    local found, current = readMember(member.index)
    if found == key and current.identity == identity then return current end
    -- The guild roster can be reordered or change between queued packets.
    addon.ReadRoster()
    member = guildMember(key)
    if member and member.identity == identity then return member end
end

function addon.GuildSender(raw, guildBroadcast)
    local key, _, suffix, qualified = rosterName(raw)
    local member = guildMember(key)
    if guildBroadcast and key and not member and guildScope() and rosterScope ~= guildScope() then
        addon.ReadRoster()
        member = guildMember(key)
    end
    if member and (member.suffix == suffix or (guildBroadcast and not qualified)) and currentMember(key, member.identity) then
        return key, member.name, member.identity
    end
end

function addon.IsGuildLeaderKey(key)
    local member = guildMember(key)
    local current = member and currentMember(key, member.identity)
    return current ~= nil and current.leader == true
end

function addon.GuildPrivacyIdentity()
    local key = addon.UnitName("player")
    local member = guildMember(key)
    if member and currentMember(key, member.identity) then return guildScope(), member.identity end
end

function addon.AutoReplyEnabled()
    local scope, identity = addon.GuildPrivacyIdentity()
    local settings = scope and GuildAvengerDB.autoReplyGuilds[scope]
    return settings ~= nil and settings[identity] == true
end

function addon.SetAutoReply(enabled)
    local scope, identity = addon.GuildPrivacyIdentity()
    if not scope then return end
    local settings = GuildAvengerDB.autoReplyGuilds
    settings[scope] = settings[scope] or {}
    settings[scope][identity] = enabled and true or nil
    autoReplyRevision = autoReplyRevision + 1
end

autoSyncSettings = function()
    local scope, identity = addon.GuildPrivacyIdentity()
    local settings = scope and GuildAvengerDB.autoSyncGuilds[scope]
    local current = settings and settings[identity]
    if current and current.enabled then return current end
end

function addon.AutoSyncWatchlistsEnabled()
    return autoSyncSettings() ~= nil
end

function addon.SetAutoSyncWatchlists(enabled)
    local scope, identity = addon.GuildPrivacyIdentity()
    if not scope then return end
    local settings = GuildAvengerDB.autoSyncGuilds
    settings[scope] = settings[scope] or {}
    local current = settings[scope][identity]
    if (current and current.enabled or false) == enabled then return end
    autoSyncRevision = autoSyncRevision + 1
    if enabled then
        current = current or { reviewed = {} }
        current.enabled = true
        settings[scope][identity] = current
        loginSyncPending = true
        addon.CheckWatchlistSync()
    else
        current.enabled = false
    end
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
            matching[#matching + 1] = member.address
        end
    end
    table.sort(matching, function(left, right) return addon.LowerName(left) < addon.LowerName(right) end)
    return matching
end

local function snapshotCurrent(transfer)
    for key, removal in pairs(transfer.removals) do
        if addon.RemovalRecord(key) ~= removal or addon.WatchlistRecord(key) then return false end
    end
    for key, guard in pairs(transfer.records) do
        local record = addon.WatchlistRecord(key)
        if record ~= guard.record or record.note ~= guard.note or record.author ~= guard.author then return false end
    end
    return true
end

local function activeOffer(offer)
    return offer and published[offer.id] == offer and offer.scope == guildScope()
        and GetTime() - offer.at < 1800 and snapshotCurrent(offer.transfer)
end

function addon.HasWatchlistLinks()
    local active = false
    for id, offer in pairs(published) do
        if activeOffer(offer) then active = true else published[id] = nil end
    end
    return active
end

function addon.RevokeWatchlistLinks()
    published = {}
    return true, L("watchlistLinksRevoked")
end

local function finishReply(request, success)
    if request then
        request.sending, request.sent = nil, success or nil
        addon.RefreshUI()
    end
end

local function stopSending(message, success)
    local completed = sending
    sending = table.remove(waiting, 1)
    if sending then
        sending.progressAt = GetTime()
    else
        ticker:Cancel()
        ticker = nil
    end
    finishReply(completed.transfer.request, success)
    if completed.transfer.request then addon.WatchlistReplyStatus(success, message) end
    if message and not completed.quiet then addon.Say(message) end
end

local function sendNext()
    local transfer, offer = sending.transfer, sending.offer
    local member
    if addon.UpdateScope() and sending.scope == guildScope() then
        member = currentMember(sending.key, sending.identity)
    end
    if not member or (not member.online and not transfer.pullID) then
        stopSending(L("recipientLeftRoster"))
        return
    end
    if sending.autoRevision and (sending.autoRevision ~= autoReplyRevision or not addon.AutoReplyEnabled()) then
        stopSending(L("autoReplyStopped"))
        return
    end
    if transfer.automatic and (transfer.syncRevision ~= autoSyncRevision or not addon.AutoSyncWatchlistsEnabled()) then
        stopSending()
        return
    end
    if (offer and not activeOffer(offer)) or (not offer and not snapshotCurrent(transfer)) then
        stopSending(L("watchlistTransferRevoked"))
        return
    end
    local result = C_ChatInfo.SendAddonMessage(prefix, sending.packets[sending.position], "WHISPER", member.address)
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
        if transfer.pullID or offer then
            stopSending(L("transferDispatched", member.name), true)
        else
            local id = transfer.id
            local receipt = {scope = sending.scope, key = sending.key, identity = sending.identity}
            receipts[id] = receipt
            C_Timer.After(whisperWait + 5, function()
                if receipts[id] ~= receipt then return end
                receipts[id] = nil
                if receipt.scope == guildScope() then addon.Say(L("transferUnconfirmed", member.name)) end
            end)
            stopSending(nil, true)
        end
    end
end

local function targetMember()
    local key = addon.UnitName("target")
    local member = guildMember(key)
    if not member then return end
    local ally = UnitIsInMyGuild("target")
    if addon.Ordinary(ally) and ally == true then return key, member.address end
end

function addon.ShareTargetName()
    local _, address = targetMember()
    return address
end

local function recipient(input)
    if input == "" then return (targetMember()) end
    local key, _, suffix, qualified = rosterName(input)
    if qualified then
        local member = guildMember(key)
        if not member or member.suffix ~= suffix then return nil, L("guildIdentityMismatch") end
    end
    if key or not input:match("^%S+$") then
        return key
    end
    local typed = addon.PlayerName(input .. " Placeholder")
    if not typed then
        return
    end
    typed = typed:match("^(%S+)")
    local exact
    for rosterKey, member in pairs(roster) do
        local first = rosterKey:match("^(%S+)")
        if first == typed and not member.ambiguous then
            if exact then
                return nil, L("ambiguousRecipient")
            end
            exact = rosterKey
        end
    end
    return exact
end

local function finishProbe(id, probe, packed)
    if probing[id] ~= probe then return end
    probing[id] = nil
    if probe.transfer.automatic and (not packed or probe.transfer.syncRevision ~= autoSyncRevision
        or not addon.AutoSyncWatchlistsEnabled()) then return end
    if probe.scope == guildScope() and currentMember(probe.key, probe.identity)
        and enqueue(probe.key, probe.transfer, nil, probe.revision, packed) then return end
    if probe.transfer.automatic then return end
    finishReply(probe.transfer.request, false)
    local message = L("transferCouldNotStart")
    if probe.transfer.request then addon.WatchlistReplyStatus(false, message) end
    addon.Say(message)
end

local function startTransfer(key, transfer, revision)
    local scope, member = guildScope(), guildMember(key)
    local current = scope and member and currentMember(key, member.identity)
    if not current or (not current.online and not transfer.pullID) or (sending and #waiting >= 20) then return false end
    local id = transfer.id
    local probe = { key = key, scope = scope, identity = current.identity, transfer = transfer, revision = revision }
    probing[id] = probe
    local message = "A\t" .. id
    if transfer.automatic then
        message = ("%s\t%s\t%s"):format(transfer.reciprocal and "K" or "J", id, transfer.pullID)
    end
    local result = C_ChatInfo.SendAddonMessage(prefix, message, "WHISPER", current.address)
    if transfer.automatic and result ~= results.Success then
        probing[id] = nil
        return false
    end
    C_Timer.After(transfer.automatic and 5 or 2, function() finishProbe(id, probe, false) end)
    return true
end

function addon.Share(input, selection, includeRemovals)
    if sending or next(probing) then
        return false, L("transferInProgress")
    end
    if not addon.UpdateScope() or not guildScope() then
        return false, L("sharingRequiresGuild")
    end
    addon.RefreshRoster()
    if rosterScope ~= guildScope() then addon.ReadRoster() end
    if rosterScope ~= guildScope() then return false, L("rosterLoading") end
    local key, message = recipient(input)
    if not key or key == addon.UnitName("player") or not addon.IsGuildMember(key) then
        return false, message or L("enterRecipient")
    end
    local member = roster[key]
    member = currentMember(key, member.identity)
    if not member then return false, L("recipientLeftRoster") end
    if not member.online then
        return false, L("recipientOffline", member.name)
    end
    local transfer, message = makePackets(selection, includeRemovals)
    if not transfer then
        return false, message
    end
    if not startTransfer(key, transfer) then return false, L("recipientLeftRoster") end
    return true, L("transferStarted", member.name)
end

makePackets = function(selection, includeRemovals, pullID)
    local entries, guards, removalGuards = {}, {}, {}
    local removals = includeRemovals and not selection and addon.RemovalProposals() or {}
    for _, entry in ipairs(addon.Entries()) do
        local entryKey = addon.RecordKey(entry)
        if (not selection or selection[entryKey]) and addon.EligibleRecord(entryKey, entry) then
            entries[#entries + 1] = entry
            guards[entryKey] = {record = entry, note = entry.note, author = entry.author}
        end
    end
    if #entries + #removals == 0 and not pullID then
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
            removalGuards[addon.RecordKey(entry)] = entry
            packets[#packets + 1] = ("X\t%s\t%s\t%s"):format(id, entry.kind, entry.name)
        end
    end
    -- The packed form puts several records, seven fields each, into one M message.
    local packed = {}
    for index, packet in ipairs(packets) do packed[index] = packet end
    local header = ("M\t%s"):format(id)
    local current = header
    local function flush()
        if current ~= header then
            packed[#packed + 1] = current
            current = header
        end
    end
    for index, entry in ipairs(entries) do
        local faction = entry.kind == "G" and "G" or (entry.faction == "Alliance" and "A" or "H")
        local base = { ("R\t%s\t%d\t%s\t%d\t%d\t%s"):format(id, index, faction,
            entry.addedAt, entry.deaths, entry.name) }
        -- Existing 2.0 clients ignore the optional priority packet.
        if entry.high then
            base[#base + 1] = ("H\t%s\t%d\t1"):format(id, index)
        end
        base[#base + 1] = ("N\t%s\t%d\t%s\t%s"):format(id, index, entry.author, entry.note)
        for _, packet in ipairs(base) do packets[#packets + 1] = packet end
        local record = ("\t%d\t%s%d\t%d\t%d\t%s\t%s\t%s"):format(index, faction, entry.high and 1 or 0,
            entry.addedAt, entry.deaths, entry.name, entry.author, entry.note)
        if #header + #record > packetLimit then
            -- A record too long for one message travels in the base format.
            flush()
            for _, packet in ipairs(base) do packed[#packed + 1] = packet end
        else
            if #current + #record > packetLimit then flush() end
            current = current .. record
        end
    end
    flush()
    return {packets = packets, packed = packed, id = id, records = guards, removals = removalGuards, pullID = pullID}
end

enqueue = function(key, transfer, offer, revision, packed)
    local member = guildMember(key)
    if not member or not currentMember(key, member.identity) then return false end
    local job = {scope = guildScope(), key = key, identity = member.identity, position = 1, transfer = transfer,
        packets = packed and transfer.packed or transfer.packets,
        progressAt = GetTime(), quiet = offer ~= nil or transfer.automatic == true, offer = offer, autoRevision = revision}
    if sending then
        if #waiting >= 20 then return false end
        waiting[#waiting + 1] = job
    else
        sending = job
        ticker = C_Timer.NewTicker(0.25, sendNext)
    end
    return true
end

local function requestWatchlists(automatic)
    if not addon.UpdateScope() or not guildScope() then return false, L("sharingRequiresGuild") end
    addon.RefreshRoster()
    local scope, own, now = guildScope(), addon.UnitName("player"), GetTime()
    if not addon.IsGuildMember(own) then addon.ReadRoster() end
    if not addon.IsGuildMember(own) then return false, L("rosterLoading") end
    if not automatic and lastListRequest and lastListRequest.scope == scope and now - lastListRequest.at < requestCooldown then
        return false, L("listRequestCooldown")
    end
    local id = transferID()
    local result = C_ChatInfo.SendAddonMessage(prefix, (automatic and "U\t" or "P\t") .. id, "GUILD")
    if result ~= results.Success then
        return false, L(result == results.AddOnMessageLockdown and "chatLockdown" or "shareRequestFailed")
    end
    for key, request in pairs(requestedLists) do
        if request.scope ~= scope or now - request.at >= requestLifetime then requestedLists[key] = nil end
    end
    local request = { scope = scope, at = now, received = {}, automatic = automatic, syncRevision = autoSyncRevision,
        verified = automatic and {} or nil }
    requestedLists[id] = request
    if not automatic then lastListRequest = request end
    return true, L("listRequestSent")
end

function addon.RequestWatchlists()
    return requestWatchlists(false)
end

function addon.CheckWatchlistSync()
    local settings = autoSyncSettings()
    if not settings then return end
    local now = GetServerTime()
    local elapsed = settings.lastAt and now - settings.lastAt
    if elapsed and elapsed < (loginSyncPending and requestCooldown or hourlyInterval) then return end
    if requestWatchlists(true) then
        loginSyncPending = false
        settings.lastAt = now
    end
end

local function activeRequest(sender, request)
    if not request or request.scope ~= guildScope() or GetTime() - request.at >= requestLifetime then return end
    return currentMember(sender, request.identity)
end

function addon.WatchlistRequests()
    local requests = {}
    for sender, request in pairs(guildRequests) do
        local member = not request.sent and not request.dismissed and activeRequest(sender, request)
        if member then
            requests[#requests + 1] = {sender = sender, name = member.name, id = request.id, sending = request.sending}
        end
    end
    table.sort(requests, function(left, right) return left.sender < right.sender end)
    return requests
end

local function replyToListRequest(sender, id, revision)
    local request = guildRequests[sender]
    local member = activeRequest(sender, request)
    if not member or request.id ~= id or request.dismissed then return false, L("listRequestExpired") end
    if request.sent then return false, L("listRequestAlreadySent") end
    if request.sending then return false, L("transferInProgress") end
    local transfer, errorMessage = makePackets(nil, false, id)
    if not transfer then return false, errorMessage end
    transfer.request = request
    if not startTransfer(sender, transfer, revision) then return false, L("transferCouldNotStart") end
    request.sending = true
    addon.RefreshUI()
    return true, L("transferStarted", member.name)
end

function addon.ReplyToWatchlistRequest(sender, id)
    if not addon.UpdateScope() then return false, L("listRequestExpired") end
    return replyToListRequest(sender, id)
end

function addon.DismissWatchlistRequest(sender, id)
    local request = guildRequests[sender]
    if not addon.UpdateScope() or not activeRequest(sender, request) or request.id ~= id or request.sending then
        return false, L("listRequestExpired")
    end
    request.dismissed = true
    addon.RefreshUI()
    return true, L("listRequestDismissed")
end

local function receiveListRequest(sender, member, id, qualified)
    local scope, now = guildScope(), GetTime()
    local request = guildRequests[sender]
    if request and request.scope == scope
        and (request.id == id or now - request.at < requestCooldown) then return end

    for key, previous in pairs(guildRequests) do
        if now - previous.at >= requestLifetime or previous.scope ~= scope then guildRequests[key] = nil end
    end
    request = {id = id, scope = scope, at = now, identity = member.identity}
    guildRequests[sender] = request
    C_Timer.After(requestLifetime, function()
        if guildRequests[sender] ~= request then return end
        guildRequests[sender] = nil
        addon.RefreshUI()
    end)
    local function offerReply()
        local link = ("|Haddon:GuildAvengerPull:%s:%s|h[%s]|h"):format(id, sender, L("replyToListRequest"))
        addon.Say(L("guildmateRequestedList", member.name, link))
        addon.NotifyWatchlistRequest(member.name)
        addon.RefreshUI()
    end
    if qualified and addon.AutoReplyEnabled() then
        local revision = autoReplyRevision
        C_Timer.After(math.random(5, 30) / 10, function()
            if guildScope() ~= scope or guildRequests[sender] ~= request or request.sent or request.sending or request.dismissed
                or not currentMember(sender, request.identity) then return end
            if revision == autoReplyRevision and addon.AutoReplyEnabled() and replyToListRequest(sender, id, revision) then return end
            offerReply()
        end)
    else
        offerReply()
    end
end

local function receiveAutomaticRequest(sender, member, id)
    if not addon.AutoSyncWatchlistsEnabled() then return end
    local scope, now = guildScope(), GetTime()
    if automaticReplyScope ~= scope then automaticReplies, automaticReplyScope = {}, scope end
    local previous = automaticReplies[sender]
    if previous and (previous.id == id or now - previous.at < requestCooldown) then return end
    local request = { id = id, at = now, scope = scope, automatic = true, syncRevision = autoSyncRevision,
        received = {}, verified = {} }
    automaticReplies[sender] = request
    C_Timer.After(math.random(5, 30) / 10, function()
        if guildScope() ~= scope or automaticReplies[sender] ~= request or request.syncRevision ~= autoSyncRevision
            or not addon.AutoSyncWatchlistsEnabled() or not currentMember(sender, member.identity) then return end
        local transfer = makePackets(nil, false, id)
        if not transfer then return end
        transfer.automatic, transfer.syncRevision = true, request.syncRevision
        request.sentProbe = startTransfer(sender, transfer)
    end)
end

local function handleGuildRequest(raw, id, automatic)
    local key, _, suffix, qualified = rosterName(raw)
    if not key or key == addon.UnitName("player") then return true end
    local member = guildMember(key)
    if not member then return false end
    if qualified and member.suffix ~= suffix then return true end
    member = currentMember(key, member.identity)
    if not member then return false end
    -- Guild broadcasts can show a bare name. A unique roster match can show a
    -- prompt, while an address mismatch must never trigger an automatic reply.
    if automatic then
        receiveAutomaticRequest(key, member, id)
    else
        receiveListRequest(key, member, id, member.suffix == suffix)
    end
    return true
end

drainGuildRequests = function()
    if not next(pendingGuildRequests) then return end
    local waiting = pendingGuildRequests
    pendingGuildRequests = {}
    local scope, now = guildScope(), GetTime()
    for key, request in pairs(waiting) do
        if request.scope == scope and now - request.at < rosterWait
            and not handleGuildRequest(request.raw, request.id, request.automatic) then
            pendingGuildRequests[key] = request
        end
    end
end

local function queueGuildRequest(raw, id, automatic)
    if handleGuildRequest(raw, id, automatic) then return end
    local scope, now = guildScope(), GetTime()
    if not scope then return end
    local count = 0
    for name, request in pairs(pendingGuildRequests) do
        if request.scope ~= scope or now - request.at >= rosterWait then
            pendingGuildRequests[name] = nil
        else
            count = count + 1
        end
    end
    local key = (automatic and "U" or "P") .. raw
    if pendingGuildRequests[key] or count >= maxPendingRequests then return end
    pendingGuildRequests[key] = {raw = raw, id = id, scope = scope, at = now, automatic = automatic}
    addon.ReadRoster()
    if next(pendingGuildRequests) then addon.RefreshRoster() end
end

function addon.Publish(selection, includeRemovals)
    if not addon.UpdateScope() or not guildScope() then
        return false, L("publishingRequiresGuild")
    end
    if C_ChatInfo.InChatMessagingLockdown and C_ChatInfo.InChatMessagingLockdown() then
        return false, L("chatLockdown")
    end
    local transfer, errorMessage = makePackets(selection, includeRemovals)
    if not transfer then
        return false, errorMessage
    end
    addon.HasWatchlistLinks()
    local id = transfer.id
    published[id] = {id = id, transfer = transfer, at = GetTime(), scope = guildScope(), requested = {}}
    C_ChatInfo.SendChatMessage("[Guild Avenger " .. id .. "]", "GUILD")
    C_ChatInfo.SendChatMessage(fittingInstallMessage(version, addon.Language()), "GUILD")
    return true, L("listPublished")
end

local function chatFilter(_, _, message, sender, ...)
    if not addon.IsText(message) then
        return false
    end
    local release = message:match("^Guild Avenger v([%d.]+)%. ")
    local availableRank = release and versionRank(release)
    -- Plain guild chat uses the sender's language. Addon links use the reader's language.
    if availableRank and isInstallMessage(message, release) then
        if availableRank <= installedRank then
            return true
        end
        return false, ("Guild Avenger %s · %s · %s"):format(release, downloadLink(), L("projectInfo")), sender, ...
    end
    local id = message:match("^%[Guild Avenger ([%da-f]+%.[%da-f]+)%]$")
    if not id or #id > 16 then return false end
    local key, _, suffix, qualified = rosterName(sender)
    local member = guildMember(key)
    if key and not member then
        addon.ReadRoster()
        member = guildMember(key)
    end
    if not member or (qualified and suffix ~= member.suffix) or not currentMember(key, member.identity) then return false end
    local link = ("|Haddon:GuildAvenger:%s:%s|h[%s]|h"):format(id, member.address, L("shareLinkLabel"))
    return false, link, sender, ...
end

local function requestLink(_, _, link, _, mouseButton)
    if not addon.IsText(link) or mouseButton ~= "LeftButton" then
        return
    end
    if link == "addon:GuildAvengerDownload" then
        addon.OpenDownload()
        return
    end
    local pullID, requester = link:match("^addon:GuildAvengerPull:([%da-f]+%.[%da-f]+):([^:]+)$")
    if pullID then
        local request = guildRequests[requester]
        if addon.UpdateScope() and activeRequest(requester, request) and request.id == pullID then
            addon.OpenWatchlistRequests()
        else
            addon.Say(L("listRequestExpired"))
        end
        return
    end
    local id, address = link:match("^addon:GuildAvenger:([%da-f]+%.[%da-f]+):([^:]+)$")
    if not id or #id > 16 or not addon.UpdateScope() or not guildScope() then
        return
    end
    local sender = addon.GuildSender(address)
    if sender == addon.UnitName("player") then
        addon.Say(L("ownShareLink"))
        return
    end
    addon.RefreshRoster()
    local member = guildMember(sender)
    if not member or not member.online then
        addon.Say(L("shareAuthorOffline"))
        return
    end
    C_ChatInfo.SendAddonMessage(prefix, ("C\t%s\t%s"):format(id, capabilities), "WHISPER", member.address)
    local result = C_ChatInfo.SendAddonMessage(prefix, "Q\t" .. id, "WHISPER", member.address)
    if result == results.Success then
        addon.Say(L("shareRequestSent"))
    else
        addon.Say(L("shareRequestFailed"))
    end
end

local function permittedAutomaticRequest(owner)
    return owner and owner.automatic and owner.scope == guildScope() and owner.syncRevision == autoSyncRevision
        and autoSyncSettings()
end

local function noteRevision(revision)
    return revision:match("^%d+:%d+:(.+)$")
end

local function reviewableRecords(entries, reviewed)
    local result, revisions = {}, {}
    if reviewed then
        for key in pairs(reviewed) do
            if not entries[key] then reviewed[key] = nil end
        end
    end
    for key, record in pairs(entries) do
        if not reviewed then
            if hasReviewableChange(key, record) then result[key] = record end
        else
            local revision = recordRevision(record)
            local previous = reviewed[key]
            if previous ~= revision and addon.EligibleRecord(key, record) then
                local own = addon.WatchlistRecord(key)
                -- A peer's initial or unchanged note is not a change to our local comment.
                if own and (not previous or noteRevision(previous) == noteRevision(revision)) then
                    record.keepLocalNote = true
                end
                if own and previous and previous:match("^%d+:([01]):") == (record.high and "1" or "0") then
                    record.keepLocalPriority = true
                end
                if changesRecord(record, own) then
                    result[key], revisions[key] = record, revision
                else
                    reviewed[key] = revision
                end
            end
        end
    end
    return result, reviewed and revisions or nil
end

local function sameAutomaticReply(previous, entries, identity)
    if not previous or not previous.automatic or previous.identity ~= identity then return false end
    for key, record in pairs(entries) do
        local old = previous.entries[key]
        if not old or old.note ~= record.note or old.high ~= record.high or old.deaths ~= record.deaths
            or old.keepLocalNote ~= record.keepLocalNote or old.keepLocalPriority ~= record.keepLocalPriority then return false end
    end
    for key in pairs(previous.entries) do
        if not entries[key] then return false end
    end
    return true
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
        local previous = current[sender]
        if previous and owner.at < previous.at then return end
        local reviewed
        if owner.automatic then
            local settings = permittedAutomaticRequest(owner)
            if not settings then return end
            reviewed = settings.reviewed[batch.identity] or {}
            settings.reviewed[batch.identity] = reviewed
        end
        local changes, revisions = reviewableRecords(entries, reviewed)
        if not next(changes) then
            if previous and (not owner.automatic or previous.automatic) then
                current[sender] = nil
                addon.RefreshUI()
            end
            return
        end
        if owner.automatic and sameAutomaticReply(previous, changes, batch.identity) then
            previous.at, previous.revisions = owner.at, revisions
            return
        end
        current[sender] = {sender = roster[sender].name, entries = changes, at = owner.at, identity = batch.identity,
            automatic = owner.automatic, revisions = revisions}
        if not owner.automatic and not owner.notified then
            owner.notified = true
            addon.Say(L("watchlistReplyArrived"))
        end
        addon.RefreshUI()
        return
    end
    local function canImport()
        return addon.UpdateScope() and guildScope() == batch.scope and currentMember(sender, batch.identity) ~= nil
    end
    local queued = addon.OfferImport(roster[sender].name, function()
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
    if not queued then addon.Say(L("reviewQueueFull", roster[sender].name)) end
    if batch.version and versionRank(batch.version) >= 3004008 then
        C_ChatInfo.SendAddonMessage(prefix, (queued and "Y\t" or "F\t") .. batch.id, "WHISPER", roster[sender].address)
    end
end

local function readRecord(record, faction, addedAt, deaths, name)
    local kind = faction == "G" and "G" or "P"
    local key, full = addon.EntryName(name, kind)
    addedAt, deaths = tonumber(addedAt), tonumber(deaths)
    if not key or not addedAt or addedAt > 4294967295 or not deaths or deaths > 2147483647 then
        return false
    end
    record.key, record.name, record.kind = key, full, kind
    record.faction = kind == "P" and (faction == "A" and "Alliance" or "Horde") or nil
    record.addedAt, record.deaths = addedAt, deaths
    return true
end

local function readNote(record, author, note)
    note = addon.Clean(note, addon.NoteLimit)
    local full
    if author and author ~= "" then
        local _
        _, full = addon.PlayerName(author)
    end
    if note == nil or (author ~= "" and not full) then
        return false
    end
    record.author, record.note = full or "", note
    return true
end

function addon.Receive(receivedPrefix, message, channel, senderName)
    if not addon.IsText(receivedPrefix) or receivedPrefix ~= prefix or not addon.IsText(channel)
        or (channel ~= "WHISPER" and channel ~= "GUILD")
        or not addon.IsText(message) or #message > 240 or not addon.UpdateScope() then
        return
    end
    if channel == "GUILD" then
        local mode, id = message:match("^([PU])\t([%da-f]+%.[%da-f]+)$")
        if id and #id <= 16 then queueGuildRequest(senderName, id, mode == "U") end
        return
    end
    local scope = guildScope()
    if scope and rosterScope ~= scope and rosterName(senderName) then
        local queued, now = {}, GetTime()
        for _, packet in ipairs(pendingWhispers) do
            if packet.scope == scope and now - packet.at < whisperWait then queued[#queued + 1] = packet end
        end
        if #queued < maxPendingWhispers then
            queued[#queued + 1] = {scope = scope, at = now, message = message, sender = senderName}
        end
        pendingWhispers = queued
        addon.ReadRoster()
        if rosterScope ~= scope then addon.RefreshRoster() end
        return
    end
    local sender, _, identity = addon.GuildSender(senderName)
    if not sender or sender == addon.UnitName("player") then return end
    local receiptType, receiptID = message:match("^([YF])\t([%da-f]+%.[%da-f]+)$")
    if receiptID then
        local receipt = receipts[receiptID]
        if receipt and receipt.key == sender and receipt.identity == identity and receipt.scope == scope then
            receipts[receiptID] = nil
            addon.Say(L(receiptType == "Y" and "transferDone" or "recipientQueueFull", roster[sender].name))
        end
        return
    end
    -- J proposes a reply to U; K proposes the return transfer to the same peer.
    -- Either transfer needs a private C response before any records are sent.
    local direction, autoProbe, autoID = message:match("^([JK])\t([%da-f]+%.[%da-f]+)\t([%da-f]+%.[%da-f]+)$")
    if autoProbe then
        local owner
        if direction == "J" then
            owner = requestedLists[autoID]
        else
            owner = automaticReplies[sender]
            if not owner or owner.id ~= autoID or not owner.sentProbe then return end
        end
        if #autoProbe <= 16 and permittedAutomaticRequest(owner) and GetTime() - owner.at < requestLifetime
            and not owner.verified[sender] then
            local reply = ("C\t%s\t%s"):format(autoProbe, capabilities)
            if C_ChatInfo.SendAddonMessage(prefix, reply, "WHISPER", roster[sender].address) == results.Success then
                owner.verified[sender] = { id = autoProbe, identity = identity }
                if direction == "J" then
                    local transfer = makePackets(nil, false, autoID)
                    if transfer then
                        transfer.automatic, transfer.reciprocal, transfer.syncRevision = true, true, owner.syncRevision
                        startTransfer(sender, transfer)
                    end
                end
            end
        end
        return
    end
    local requestID = message:match("^Q\t([%da-f]+%.[%da-f]+)$")
    if requestID then
        local offer, now = published[requestID], GetTime()
        if activeOffer(offer)
            and (not offer.requested[sender] or now - offer.requested[sender] >= 10) then
            local peer = capable[sender]
            local packed = peer and peer.id == requestID and peer.identity == identity
                and peer.scope == offer.scope and now - peer.at < 30
            if enqueue(sender, offer.transfer, offer, nil, packed) then offer.requested[sender] = now end
        end
        return
    end
    -- Guild messages returned above, so the question A and the answer C count only as whispers.
    local probeID = message:match("^A\t([%da-f]+%.[%da-f]+)$")
    if probeID then
        -- A sender asks what this client reads before it starts a transfer.
        local now = GetTime()
        if #probeID <= 16 and (not announced[sender] or now - announced[sender] >= 2) then
            announced[sender] = now
            C_ChatInfo.SendAddonMessage(prefix, ("C\t%s\t%s"):format(probeID, capabilities), "WHISPER",
                roster[sender].address)
        end
        return
    end
    local capableID, flags = message:match("^C\t([%da-f]+%.[%da-f]+)\t(%a+)$")
    if capableID then
        if #capableID <= 16 and flags:find("M", 1, true) then
            local probe = probing[capableID]
            if probe and probe.key == sender and probe.identity == identity then
                finishProbe(capableID, probe, true)
            elseif activeOffer(published[capableID]) then
                capable[sender] = {id = capableID, identity = identity, scope = guildScope(), at = GetTime()}
            end
        end
        return
    end
    -- P is the guild-wide watchlist request above, so packed records travel as M.
    local operation, id, data = message:match("^([BRNHVDXM])\t([%da-f]+%.[%da-f]+)\t(.*)$")
    if not operation or #id > 16 then
        return
    end
    local now = GetTime()
    if operation == "B" then
        local number, pullID = data:match("^(%d+)\t([%da-f]+%.[%da-f]+)$")
        local owner = pullID and requestedLists[pullID]
        local verified = owner and owner.verified and owner.verified[sender]
        local reciprocal = pullID and automaticReplies[sender]
        if reciprocal and reciprocal.id == pullID then
            local peer = reciprocal.verified[sender]
            if peer and peer.id == id then owner, verified = reciprocal, peer end
        end
        if pullID and (not owner or owner.scope ~= guildScope()
            or now - owner.at >= requestLifetime or owner.received[sender]
            or (owner.automatic and (not verified or verified.id ~= id or verified.identity ~= identity
                or not permittedAutomaticRequest(owner)))) then
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
            removals = {}, removalCount = 0, pull = owner, identity = identity }
        return
    end
    local batch = incoming[sender]
    if not batch or batch.id ~= id or batch.scope ~= guildScope() or batch.identity ~= identity or now - batch.progressAt > 75 then
        return
    end
    if operation == "V" then
        local senderRank = not batch.version and versionRank(data)
        if senderRank then
            batch.version = data
            batch.explicit = senderRank >= 2004000
            if senderRank > installedRank and not (batch.pull and batch.pull.automatic) then
                addon.Say(L("shareNewerVersion", data, downloadLink()))
            end
            if batch.pull and batch.count == 0 then finish(sender, batch) end
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
    elseif operation == "M" then
        -- Several whole records in one message, seven fields each.
        -- Every field counts, including an empty note at the very end of the message.
        local fields = {}
        for field in (data .. "\t"):gmatch("([^\t]*)\t") do fields[#fields + 1] = field end
        if #fields % 7 ~= 0 then return end
        for offset = 1, #fields, 7 do
            local index = fields[offset]:match("^%d+$") and tonumber(fields[offset])
            local faction, high = fields[offset + 1]:match("^([AHG])([01])$")
            local record = {}
            if index and index >= 1 and index <= batch.count and not batch.records[index] and faction
                and fields[offset + 2]:match("^%d+$") and fields[offset + 3]:match("^%d+$")
                and readRecord(record, faction, fields[offset + 2], fields[offset + 3], fields[offset + 4])
                and readNote(record, fields[offset + 5], fields[offset + 6]) then
                record.high = high == "1" or nil
                batch.records[index], batch.progressAt = record, now
                batch.ready = batch.ready + 1
            end
        end
        if batch.ready == batch.count and batch.removalCount == (batch.expectedRemovals or 0) then
            finish(sender, batch)
        end
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
        if not readRecord(record, faction, addedAt, deaths, name) then
            return
        end
    elseif operation == "H" and record.key and record.note == nil and fields == "1" then
        record.high = true
    elseif operation == "N" and record.note == nil then
        local author, note = fields:match("^([^\t]*)\t([^\t]*)$")
        if not readNote(record, author, note) then
            return
        end
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
    GuildAvengerDB.watchlistInbox = GuildAvengerDB.watchlistInbox or {}
    GuildAvengerDB.autoReplyGuilds = GuildAvengerDB.autoReplyGuilds or {}
    GuildAvengerDB.autoSyncGuilds = GuildAvengerDB.autoSyncGuilds or {}
    GuildAvengerDB.replyToListRequests = nil
    C_Timer.NewTicker(30, addon.CheckWatchlistSync)
    C_ChatInfo.RegisterAddonMessagePrefix(prefix)
    local addFilter = ChatFrameUtil and ChatFrameUtil.AddMessageEventFilter or ChatFrame_AddMessageEventFilter
    if addFilter then addFilter("CHAT_MSG_GUILD", chatFilter) end
    if EventRegistry then EventRegistry:RegisterCallback("ChatFrame.OnHyperlinkClick", requestLink) end
end
