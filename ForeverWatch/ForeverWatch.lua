local addonName, addon = ...
local frame = CreateFrame("Frame")
local prefix = "ForeverWatch1"
local results = Enum.SendAddonMessageResult
local listID, entries
local pending = {}
local sendTicker
local plates, lastSeen = {}, {}
local maxRevision = 2147483647
local waitingForGuild = "Список доступний після підключення до гільдії."
local maxNoteBytes = 104

addon.MaxNoteBytes = maxNoteBytes

local function readable(value)
    return not issecretvalue or not issecretvalue(value)
end

local function textValue(value)
    return readable(value) and type(value) == "string"
end

local function say(message)
    DEFAULT_CHAT_FRAME:AddMessage("|cff56d6bfForever Watch|r " .. message)
end

local cyrillicLower = {}
do
    local upper = "АБВГҐДЕЄЁЖЗИІЇЙКЛМНОПРСТУФХЦЧШЩЪЫЬЭЮЯЎ"
    local lower = "абвгґдеєёжзиіїйклмнопрстуфхцчшщъыьэюяў"
    for index = 1, #upper, 2 do
        cyrillicLower[upper:sub(index, index + 1)] = lower:sub(index, index + 1)
    end
end

local function lowerText(value)
    if string.utf8lower then
        return string.utf8lower(value)
    end
    return (value:lower():gsub("[\208\209][\128-\191]", cyrillicLower))
end

local function watchName(kind, value)
    if not textValue(value) or #value > 96 or value:find("[%c|]") then
        return
    end
    local name = value:match("^%s*(.-)%s*$"):gsub(" +", " ")
    if name == "" then
        return
    end
    if kind == "P" then
        local first, last = name:match("^([^%s%-]+)[%s%-]+([^%s%-]+)$")
        if not first or (first .. last):gsub("'", ""):find("[%d%p]") then
            return
        end
        name = first .. " " .. last
    end
    return kind .. ":" .. lowerText(name), name
end

local function isPlayerUnit(unit)
    local isPlayer = UnitIsPlayer(unit)
    return readable(isPlayer) and isPlayer
end

local function characterName(unit)
    local name, surname = UnitName(unit)
    if not textValue(name) then
        return
    end
    -- Forever can give a full name or put the surname in the second return.
    local key, display = watchName("P", name)
    if key then
        return key, display
    end
    if textValue(surname) and surname ~= "" then
        return watchName("P", name .. " " .. surname)
    end
end

local function guildName(unit)
    return watchName("G", (GetGuildInfo(unit)))
end

local function matchedEntry(key)
    local entry = key and entries[key]
    return entry and not entry.removed and entry
end

local function scanPlate(unit)
    local previous = plates[unit]
    plates[unit] = false
    if unit == "player" or not entries or not next(entries) or not isPlayerUnit(unit) then
        return
    end
    local playerKey, playerName = characterName(unit)
    if playerKey and playerKey == characterName("player") then
        return
    end
    local key = playerKey
    local entry = matchedEntry(key)
    if not entry then
        key = guildName(unit)
        entry = matchedEntry(key)
    end
    if not entry then
        return
    end
    plates[unit] = key
    if previous == key then
        return
    end
    local sighting = playerKey or unit
    local now = GetTime()
    if lastSeen[sighting] and lastSeen[sighting] > now then
        return
    end
    lastSeen[sighting] = now + 15
    if entry.kind == "P" then
        say("Поруч персонаж зі списку PvP " .. entry.name)
    elseif playerName then
        say("Поруч " .. playerName .. " з гільдії «" .. entry.name .. "».")
    else
        say("Поруч гравець із гільдії «" .. entry.name .. "».")
    end
    addon.ShowAlert(entry, playerName)
end

local function scanPlates()
    local now = GetTime()
    for sighting, expiry in pairs(lastSeen) do
        if expiry <= now then
            lastSeen[sighting] = nil
        end
    end
    for unit in pairs(plates) do
        scanPlate(unit)
    end
end

local function updateGuild()
    local id = "local"
    if IsInGuild() then
        local club = C_Club.GetGuildClubId()
        if not readable(club) or not club then
            return false
        end
        id = tostring(club)
    end
    if id == listID then
        return true
    end
    listID = id
    ForeverWatchDB[id] = ForeverWatchDB[id] or {}
    entries = ForeverWatchDB[id]
    pending, lastSeen = {}, {}
    for unit in pairs(plates) do
        plates[unit] = false
    end
    scanPlates()
    addon.RefreshPanel()
    return true
end

local function applyEntry(key, kind, name, revision, removed, note)
    local previous = entries[key]
    if previous then
        if previous.revision > revision then
            return
        end
        if previous.revision == revision then
            if previous.removed and not removed then
                return
            end
            if previous.removed == removed then
                if previous.name < name then
                    return
                end
                if previous.name == name and (note == nil or (previous.note and previous.note <= note)) then
                    return
                end
            end
        end
    end
    entries[key] = { kind = kind, name = name, revision = revision, removed = removed, note = note }
    scanPlates()
    addon.RefreshPanel()
end

local function sendNext()
    if not updateGuild() then
        return
    end
    local key = next(pending)
    if not key then
        sendTicker:Cancel()
        sendTicker = nil
        return
    end
    local entry = entries[key]
    local operation = entry.removed and "D" or "A"
    local message = ("%s\t%s\t%s\t%d\t%s"):format(listID, operation, entry.kind, entry.revision, entry.name)
    -- Send the original format first so earlier versions still receive list changes.
    local includesNote = pending[key] == entry and entry.note ~= nil
    if includesNote then
        message = message .. "\t" .. entry.note
    end
    local result = C_ChatInfo.SendAddonMessage(prefix, message, "GUILD")
    if result == results.AddonMessageThrottle or result == results.ChannelThrottle
        or result == results.AddOnMessageLockdown then
        return
    end
    if result ~= results.Success then
        sendTicker:Cancel()
        sendTicker = nil
        say("Гільдійна синхронізація призупинена. Для повтору введіть /fw share.")
        return
    end
    pending[key] = not includesNote and entry.note ~= nil and entry or nil
end

local function startSending()
    if next(pending) and not sendTicker then
        sendTicker = C_Timer.NewTicker(0.35, sendNext)
    end
end

local function normalizedNote(note)
    if textValue(note) and #note <= maxNoteBytes and not note:find("[%c|]") then
        return note:match("^%s*(.-)%s*$")
    end
end

local function onGuildMessage(messagePrefix, message, channel)
    if not textValue(messagePrefix) or messagePrefix ~= prefix
        or not textValue(channel) or channel ~= "GUILD"
        or not textValue(message) or #message > 240 then
        return
    end
    if not updateGuild() then
        return
    end
    local id, operation, kind, revisionText, name, suffix =
        message:match("^([^\t]+)\t([AD])\t([PG])\t(%d+)\t([^\t]+)(.*)$")
    if not entries or listID == "local" or id ~= listID then
        return
    end
    local key, display = watchName(kind, name)
    local revision = tonumber(revisionText)
    local note
    if suffix ~= "" then
        note = suffix:sub(1, 1) == "\t" and operation == "A" and normalizedNote(suffix:sub(2))
        if not note then
            return
        end
    end
    if key and revision and revision >= 1 and revision <= maxRevision then
        applyEntry(key, kind, display, revision, operation == "D", note)
    end
end

local function targetName(kind)
    if not isPlayerUnit("target") then
        return
    end
    if kind == "G" then
        return guildName("target")
    end
    return characterName("target")
end

local function editEntry(kind, input, operation, note)
    if not updateGuild() then
        return false, waitingForGuild
    end
    local key, name
    if input ~= "" then
        key, name = watchName(kind, input)
    else
        key, name = targetName(kind)
    end
    if not key then
        return false, kind == "G" and "Введіть назву гільдії або виберіть її учасника."
            or "Виберіть персонажа або введіть його ім’я та прізвище."
    end
    local previous = entries[key]
    local active = previous and not previous.removed
    local removed = operation == "remove"
    if operation == "add" and active then
        return false, "Цей запис уже є у списку."
    end
    if operation ~= "add" and not active then
        return false, "Цього запису немає у списку."
    end
    if note ~= nil then
        note = normalizedNote(note)
        if note == nil then
            return false, "Причина містить недопустимі символи або надто довга."
        end
    end
    if operation == "note" then
        if (previous.note or "") == note then
            return true, "Причина збережена.", previous.name
        end
        name = previous.name
    elseif note == "" then
        note = nil
    end
    local revision = previous and previous.revision + 1 or 1
    if revision > maxRevision then
        return false, "Досягнуто максимальної ревізії запису."
    end
    applyEntry(key, kind, name, revision, removed, note)
    if listID ~= "local" then
        pending[key] = true
        startSending()
    end
    local message = operation == "note" and "Причина збережена." or (removed and "Вилучено " or "Додано ") .. name
    return true, message, name
end

local function getLists()
    local players, guilds = {}, {}
    if entries then
        for _, entry in pairs(entries) do
            if not entry.removed then
                local names = entry.kind == "G" and guilds or players
                names[#names + 1] = entry
            end
        end
    end
    local function byName(left, right) return left.name < right.name end
    table.sort(players, byName)
    table.sort(guilds, byName)
    return players, guilds, listID
end

local function showList()
    if not updateGuild() then
        say(waitingForGuild)
        return
    end
    local players, guilds = getLists()
    say(("Персонажів %d, гільдій %d"):format(#players, #guilds))
    for _, entry in ipairs(players) do
        say("Персонаж " .. entry.name .. (entry.note and entry.note ~= "" and " — " .. entry.note or ""))
    end
    for _, entry in ipairs(guilds) do
        say("Гільдія " .. entry.name .. (entry.note and entry.note ~= "" and " — " .. entry.note or ""))
    end
end

local function shareList()
    if not updateGuild() then
        return false, waitingForGuild
    end
    if listID == "local" then
        return false, "Для поширення списку потрібно бути в гільдії."
    end
    for key in pairs(entries) do
        pending[key] = true
    end
    if not next(pending) then
        return false, "Список порожній."
    end
    startSending()
    return true, "Список поставлено в чергу для гільдії."
end

addon.GetLists = getLists
addon.EditEntry = editEntry
addon.ShareList = shareList
addon.GetTargetName = targetName
addon.GetPlayerName = function() return characterName("player") end

local function commands(input)
    local command, rest = input:match("^%s*(%S*)%s*(.-)%s*$")
    command = command:lower()
    if command == "" then
        updateGuild()
        addon.TogglePanel()
        return
    end
    local kind = "P"
    if command == "guild" then
        kind = "G"
        command, rest = rest:match("^(%S*)%s*(.-)%s*$")
        command = command:lower()
    end
    if command == "add" or command == "remove" then
        local _, message = editEntry(kind, rest, command)
        say(message)
    elseif kind == "P" and command == "list" then
        showList()
    elseif kind == "P" and command == "share" then
        local _, message = shareList()
        say(message)
    elseif kind == "P" and command == "test" then
        addon.PreviewAlert()
    else
        say("/fw — відкрити список")
        say("/fw add або /fw remove [Ім’я Прізвище]")
        say("/fw guild add або /fw guild remove [Назва гільдії]")
        say("/fw list, /fw share, /fw test")
    end
end

local function onEvent(_, event, ...)
    if event == "ADDON_LOADED" then
        if (...) == addonName then
            ForeverWatchDB = ForeverWatchDB or {}
            frame:UnregisterEvent(event)
            C_ChatInfo.RegisterAddonMessagePrefix(prefix)
            C_Timer.NewTicker(1, scanPlates)
            SLASH_FOREVERWATCH1 = "/fw"
            SlashCmdList.FOREVERWATCH = commands
        end
    elseif event == "PLAYER_ENTERING_WORLD" or event == "PLAYER_GUILD_UPDATE" or event == "INITIAL_CLUBS_LOADED" then
        updateGuild()
    elseif event == "PLAYER_LEAVING_WORLD" then
        plates = {}
        addon.CloseAlert()
    elseif event == "CHAT_MSG_ADDON" then
        onGuildMessage(...)
    else
        local unit = ...
        if not textValue(unit) then
            return
        end
        if event == "NAME_PLATE_UNIT_REMOVED" then
            plates[unit] = nil
        elseif event == "NAME_PLATE_UNIT_ADDED" then
            scanPlate(unit)
        end
    end
end

frame:SetScript("OnEvent", onEvent)
for _, event in ipairs({
    "ADDON_LOADED", "PLAYER_ENTERING_WORLD", "PLAYER_LEAVING_WORLD", "PLAYER_GUILD_UPDATE",
    "INITIAL_CLUBS_LOADED", "CHAT_MSG_ADDON", "NAME_PLATE_UNIT_ADDED", "NAME_PLATE_UNIT_REMOVED",
}) do
    frame:RegisterEvent(event)
end
