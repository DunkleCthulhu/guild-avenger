local _, addon = ...
local prefix = "GrudgeBook2"
local maxEntries = 1000
local results = Enum.SendAddonMessageResult
local roster, rosterScope, rosterRequestedAt = {}, nil, nil
local sending, ticker, sequence = nil, nil, 0
local incoming = {}
local published, waiting = {}, {}
local makePackets, enqueue

local function guildScope()
    local scope = addon.Scope()
    if scope and scope ~= "local" and IsInGuild() then
        return scope
    end
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
        local name, _, _, _, _, _, _, _, online = GetGuildRosterInfo(index)
        local key, full = addon.PlayerName(name, true)
        if key then
            updated[key] = { name = full, online = addon.Ordinary(online) and online == true }
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
        stopSending("Передавання зупинено: одержувач більше не підтверджений у ростері.")
        return
    end
    local member = roster[sending.key]
    local result = C_ChatInfo.SendAddonMessage(prefix, sending.packets[sending.position], "WHISPER", member.name)
    if result == results.AddonMessageThrottle or result == results.ChannelThrottle
        or result == results.AddOnMessageLockdown then
        if GetTime() - sending.progressAt > 45 then
            stopSending("WoW тимчасово заблокував передавання. Спробуйте знову поза боєм.")
        end
        return
    end
    if result ~= results.Success then
        stopSending("Не вдалося надіслати список " .. member.name .. ".")
        return
    end
    sending.position = sending.position + 1
    sending.progressAt = GetTime()
    if sending.position > #sending.packets then
        stopSending("Список надіслано " .. member.name .. " для підтвердження.")
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
                return nil, "Кілька гільдійців мають це ім’я. Введіть також прізвище."
            end
            exact = rosterKey
        end
    end
    return exact
end

function addon.Share(input)
    if sending then
        return false, "Дочекайтеся завершення поточного передавання."
    end
    if not addon.UpdateScope() or not guildScope() then
        return false, "Передавання доступне лише учасникам гільдії."
    end
    addon.RefreshRoster()
    if rosterScope ~= guildScope() then
        return false, "WoW ще завантажує ростер гільдії. Спробуйте за мить."
    end
    local key, message = recipient(input)
    if not key or key == addon.UnitName("player") or not addon.IsGuildMember(key) then
        return false, message or "Введіть ім’я гільдійця або виберіть його ціллю."
    end
    local member = roster[key]
    if not member.online then
        return false, member.name .. " зараз не в мережі."
    end
    local packets, message = makePackets()
    if not packets then
        return false, message
    end
    enqueue(key, packets)
    return true, "Починаю передавання " .. member.name .. "."
end

makePackets = function()
    local entries = {}
    for _, entry in ipairs(addon.Entries()) do
        local entryKey = addon.EntryName(entry.name, entry.kind)
        if addon.EligibleRecord(entryKey, entry) then
            entries[#entries + 1] = entry
        end
    end
    if #entries == 0 then
        return nil, "Немає записів для передавання."
    end
    if #entries > maxEntries then
        return nil, "За одне передавання можна надіслати до 1000 записів."
    end

    sequence = sequence % 65535 + 1
    local id = ("%x.%x"):format(GetServerTime(), sequence)
    local packets = { ("B\t%s\t%d"):format(id, #entries) }
    for index, entry in ipairs(entries) do
        local faction = entry.kind == "G" and "G" or (entry.faction == "Alliance" and "A" or "H")
        packets[#packets + 1] = ("R\t%s\t%d\t%s\t%d\t%d\t%s"):format(id, index, faction,
            entry.addedAt, entry.deaths, entry.name)
        packets[#packets + 1] = ("N\t%s\t%d\t%s\t%s"):format(id, index, entry.author, entry.note)
    end
    return packets, id
end

enqueue = function(key, packets, quiet)
    local job = { scope = guildScope(), key = key, position = 1, packets = packets,
        progressAt = GetTime(), quiet = quiet }
    if sending then
        if #waiting < 20 then
            waiting[#waiting + 1] = job
        end
    else
        sending = job
        ticker = C_Timer.NewTicker(0.25, sendNext)
    end
end

function addon.Publish()
    if not addon.UpdateScope() or not guildScope() then
        return false, "Публікація доступна учасникам гільдії."
    end
    if C_ChatInfo.InChatMessagingLockdown and C_ChatInfo.InChatMessagingLockdown() then
        return false, "WoW тимчасово обмежив повідомлення в чаті."
    end
    local packets, id = makePackets()
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
    C_ChatInfo.SendChatMessage("[GrudgeBook " .. id .. "]", "GUILD")
    return true, "Посилання на список опубліковано в чаті гільдії."
end

local function chatFilter(_, _, message, sender, ...)
    if not addon.IsText(message) then
        return false
    end
    local id = message:match("^%[GrudgeBook ([%da-f]+%.[%da-f]+)%]$")
    local key = id and #id <= 16 and addon.PlayerName(sender, true)
    if not key then
        return false
    end
    local link = ("|Haddon:GrudgeBook:%s:%s|h[Перелік GrudgeBook]|h"):format(id, key)
    return false, link, sender, ...
end

local function requestLink(_, link, _, mouseButton)
    if not addon.IsText(link) or mouseButton ~= "LeftButton" then
        return
    end
    local id, sender = link:match("^addon:GrudgeBook:([%da-f]+%.[%da-f]+):([^:]+)$")
    if not id or #id > 16 or not addon.UpdateScope() or not guildScope() then
        return
    end
    if sender == addon.UnitName("player") then
        addon.Say("Ти опублікував цей список. Гільдійці з аддоном можуть відкрити його за посиланням.")
        return
    end
    addon.RefreshRoster()
    local member = addon.IsGuildMember(sender) and roster[sender]
    if not member or not member.online then
        addon.Say("Автор посилання має бути онлайн у вашій гільдії.")
        return
    end
    local result = C_ChatInfo.SendAddonMessage(prefix, "Q\t" .. id, "WHISPER", member.name)
    if result == results.Success then
        addon.Say("Запит надіслано. Список з’явиться після отримання всіх записів.")
    else
        addon.Say("WoW не прийняв запит. Спробуйте ще раз.")
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
            deaths = part.deaths, author = part.author, note = part.note }
    end
    local added, updated, changes = addon.Merge(entries, true)
    addon.OfferImport(roster[sender].name, added, updated, changes or {}, function(selection)
        if not addon.UpdateScope() or guildScope() ~= batch.scope or not addon.IsGuildMember(sender) then
            addon.Say("Імпорт скасовано: відправник більше не підтверджений у ростері.")
            return
        end
        local newEntries, newerCounts = addon.Merge(selection, false)
        addon.Say(("Імпорт завершено. Додано %d, оновлено лічильників %d."):format(newEntries, newerCounts))
    end)
end

function addon.Receive(receivedPrefix, message, channel, senderName)
    if not addon.IsText(receivedPrefix) or receivedPrefix ~= prefix or not addon.IsText(channel) or channel ~= "WHISPER"
        or not addon.IsText(message) or #message > 240 or not addon.UpdateScope() then
        return
    end
    local sender = addon.PlayerName(senderName, true)
    if not sender or sender == addon.UnitName("player") or not addon.IsGuildMember(sender) then
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
    local operation, id, data = message:match("^([BRN])\t([%da-f]+%.[%da-f]+)\t(.*)$")
    if not operation or #id > 16 then
        return
    end
    local now = GetTime()
    if operation == "B" then
        local count = data:match("^%d+$") and tonumber(data)
        if not count or count < 1 or count > maxEntries then
            return
        end
        for key, old in pairs(incoming) do
            if now - old.progressAt > 75 or not addon.IsGuildMember(key) then
                incoming[key] = nil
            end
        end
        incoming[sender] = { id = id, count = count, ready = 0, records = {}, progressAt = now, scope = guildScope() }
        return
    end
    local batch = incoming[sender]
    if not batch or batch.id ~= id or batch.scope ~= guildScope() or now - batch.progressAt > 75 then
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
        record.addedAt, record.deaths = addedAt, kind == "P" and deaths or 0
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
        if batch.ready == batch.count then
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
