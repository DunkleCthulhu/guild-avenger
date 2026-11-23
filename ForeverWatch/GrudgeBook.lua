local addonName, addon = ...
local frame = CreateFrame("Frame")
local listID, entries
local plates, alerts, deaths, knownGUIDs = {}, {}, {}, {}
local cooldown = 30
local deathCooldown = 8
local nameLimit, noteLimit = 96, 104
local unavailable = "Зачекайте, поки WoW завантажить вашу гільдію."
local invalidEnemy = "Виберіть доступного для атаки гравця протилежної фракції поза вашою групою й гільдією."

addon.NameLimit, addon.NoteLimit = nameLimit, noteLimit

local function ordinary(value)
    return not issecretvalue or not issecretvalue(value)
end

local function isText(value)
    return ordinary(value) and type(value) == "string"
end

local function say(message)
    DEFAULT_CHAT_FRAME:AddMessage("|cffdf8278GrudgeBook|r " .. message)
end

local cyrillicLower = {}
do
    local upper = "АБВГҐДЕЄЁЖЗИІЇЙКЛМНОПРСТУФХЦЧШЩЪЫЬЭЮЯЎ"
    local lower = "абвгґдеєёжзиіїйклмнопрстуфхцчшщъыьэюяў"
    for index = 1, #upper, 2 do
        cyrillicLower[upper:sub(index, index + 1)] = lower:sub(index, index + 1)
    end
end

local function lowerName(value)
    if string.utf8lower then
        return string.utf8lower(value)
    end
    return (value:lower():gsub("[\208\209][\128-\191]", cyrillicLower))
end

local function clean(value, limit)
    if isText(value) and #value <= limit and not value:find("[%c|]") then
        return value:match("^%s*(.-)%s*$")
    end
end

local function playerName(value, fromWire)
    value = clean(value, fromWire and nameLimit + 64 or nameLimit)
    if not value then
        return
    end
    -- Forever sends a layer suffix on some roster and chat names.
    if fromWire then
        value = value:match("^([^%s%-]+ [^%s%-]+)%-%S+$")
            or value:match("^([^%s%-]+%-[^%s%-]+)%-%S+$") or value
    end
    if #value > nameLimit then
        return
    end
    local first, surname = value:match("^([^%s%-]+)[%s%-]+([^%s%-]+)$")
    if first and not (first .. surname):gsub("'", ""):find("[%d%p]") then
        local full = first .. " " .. surname
        return lowerName(full), full
    end
end

local function unitName(unit)
    local name, surname = UnitName(unit)
    local key, full = playerName(name)
    if key then
        return key, full
    end
    if isText(name) and isText(surname) and surname ~= "" then
        return playerName(name .. " " .. surname)
    end
end

local function guildName(value)
    local name = clean(value, nameLimit)
    if name and name ~= "" then
        name = name:gsub(" +", " ")
        return "guild:" .. lowerName(name), name
    end
end

local function entryName(value, kind)
    if kind == "G" then
        return guildName(value)
    end
    return playerName(value)
end

local function importLegacy(imported, legacy, kind)
    for _, record in pairs(type(legacy) == "table" and legacy or {}) do
        if type(record) == "table" and record.kind == kind and not record.removed then
            local key, name = entryName(record.name, kind)
            if key and not imported[key] then
                imported[key] = { name = name, note = clean(record.note, noteLimit) or "",
                    author = "", addedAt = 0, deaths = 0, kind = kind }
            end
        end
    end
end

local function indexGUIDs()
    knownGUIDs = {}
    for key, entry in pairs(entries) do
        if entry.guid then
            knownGUIDs[entry.guid] = key
        end
    end
end

local function updateScope()
    local id = "local"
    if IsInGuild() then
        local club = C_Club.GetGuildClubId()
        if not ordinary(club) or not club then
            return false
        end
        id = tostring(club)
    end
    if id == listID then
        return true
    end
    listID = id
    local legacy = ForeverWatchDB and ForeverWatchDB[id]
    if not GrudgeBookDB.lists[id] then
        GrudgeBookDB.lists[id] = {}
        importLegacy(GrudgeBookDB.lists[id], legacy, "P")
    end
    entries = GrudgeBookDB.lists[id]
    if not GrudgeBookDB.guildsImported[id] then
        importLegacy(entries, legacy, "G")
        GrudgeBookDB.guildsImported[id] = true
    end
    alerts, deaths = {}, {}
    for unit in pairs(plates) do
        plates[unit] = false
    end
    indexGUIDs()
    addon.RefreshUI()
    return true
end

local function isAllyName(key)
    if key == unitName("player") or addon.IsGuildMember(key) then
        return true
    end
    local raid = IsInRaid()
    local count = raid and GetNumGroupMembers() or GetNumSubgroupMembers()
    for index = 1, count do
        local unit = (raid and "raid" or "party") .. index
        if key == unitName(unit) then
            return true
        end
    end
    return false
end

local function isDifferentFaction(faction)
    local own = UnitFactionGroup("player")
    return ordinary(own) and (own == "Alliance" or own == "Horde")
        and (faction == "Alliance" or faction == "Horde") and own ~= faction
end

local function enemyUnit(unit, allowDead)
    if not isText(unit) or unit == "player" then
        return
    end
    local player, attackable = UnitIsPlayer(unit), UnitCanAttack("player", unit)
    if not ordinary(player) or not player or not ordinary(attackable) then
        return
    end
    if not attackable then
        local dead = allowDead and UnitIsDead(unit)
        if not ordinary(dead) or not dead then
            return
        end
    end
    local faction, myGuild = UnitFactionGroup(unit), UnitIsInMyGuild(unit)
    local party, raid = UnitInParty(unit), UnitInRaid(unit)
    if not ordinary(faction) or not isDifferentFaction(faction) or not ordinary(myGuild) or myGuild
        or not ordinary(party) or party or not ordinary(raid) or (raid and raid ~= 0) then
        return
    end
    local key, name = unitName(unit)
    if not key or key == unitName("player") or addon.IsGuildMember(key) then
        return
    end
    local guid = UnitGUID(unit)
    return key, name, faction, isText(guid) and guid or nil
end

local function enemyEntry(unit, kind)
    local key, name, faction, guid = enemyUnit(unit)
    if key and kind == "G" then
        return guildName((GetGuildInfo(unit)))
    end
    return key, name, faction, guid
end

local function visibleEnemy(key, kind)
    for _, unit in ipairs({ "target", "mouseover", "focus" }) do
        if key == enemyEntry(unit, kind) then
            return unit
        end
    end
    for unit in pairs(plates) do
        if key == enemyEntry(unit, kind) then
            return unit
        end
    end
end

local function remember(entry, key, faction, guid)
    entry.faction = faction
    if guid and guid ~= entry.guid then
        if entry.guid then
            knownGUIDs[entry.guid] = nil
        end
        entry.guid = guid
        knownGUIDs[guid] = key
    end
end

local function warn(key, entry, player)
    local now = GetTime()
    if alerts[key] and now - alerts[key] < cooldown then
        return
    end
    alerts[key] = now
    local guild = entry.kind == "G" and "Гільдія «" .. entry.name .. "»" or ""
    local reason = entry.note ~= "" and " — " .. entry.note or ""
    say("Ворог поруч: " .. player .. (guild ~= "" and " — " .. guild or "") .. reason)
    addon.ShowAlert({ name = player, note = guild ~= "" and guild .. reason or entry.note })
end

local function scanUnit(unit, alreadySeen)
    if not entries or not next(entries) then
        return false
    end
    local key, name, faction, guid = enemyUnit(unit)
    local entry = key and entries[key]
    if not entry and key then
        local guild = guildName((GetGuildInfo(unit)))
        entry = guild and entries[guild]
    end
    if not entry then
        return false
    end
    if entry.kind ~= "G" then
        remember(entry, key, faction, guid)
    end
    if key ~= alreadySeen then
        warn(key, entry, name)
    end
    return key
end

local function scanPlates()
    if not entries or not next(entries) then
        return
    end
    for unit, key in pairs(plates) do
        plates[unit] = scanUnit(unit, key)
    end
end

local function recordDeath(guid)
    if not isText(guid) or not entries then
        return
    end
    local key = knownGUIDs[guid]
    local entry = key and entries[key]
    if not entry and UnitTokenFromGUID then
        local candidate, _, faction, resolvedGUID = enemyUnit(UnitTokenFromGUID(guid), true)
        if candidate and resolvedGUID == guid and entries[candidate] then
            key, entry = candidate, entries[candidate]
            remember(entry, key, faction, guid)
        end
    end
    if not entry or entry.guid ~= guid or not isDifferentFaction(entry.faction) or isAllyName(key) then
        return
    end
    local now = GetTime()
    if deaths[key] and now - deaths[key] < deathCooldown then
        return
    end
    deaths[key] = now
    entry.deaths = math.min(entry.deaths + 1, 2147483647)
    addon.RefreshUI()
end

local function sortedEntries()
    local list = {}
    for _, entry in pairs(entries or {}) do
        list[#list + 1] = entry
    end
    table.sort(list, function(left, right)
        if strcmputf8i then
            return strcmputf8i(left.name, right.name) < 0
        end
        return lowerName(left.name) < lowerName(right.name)
    end)
    return list
end

local function addEnemy(input, reason, fromUnit, kind)
    if not updateScope() then
        return false, unavailable
    end
    local unit = fromUnit or "target"
    if input ~= "" then
        local wanted = entryName(input, kind)
        if not wanted then
            return false, kind == "G" and "Введіть назву гільдії." or "Введіть повне ім’я персонажа."
        end
        if kind ~= "G" and isAllyName(wanted) then
            return false, invalidEnemy
        end
        if not fromUnit or wanted ~= enemyEntry(fromUnit, kind) then
            unit = visibleEnemy(wanted, kind)
        end
    end
    local key, name, faction, guid = enemyEntry(unit, kind)
    if not key then
        return false, kind == "G" and "Виберіть доступного ворога, чию гільдію видно." or invalidEnemy
    end
    if entries[key] then
        return false, "Цей запис уже в Книзі Образ."
    end
    local note = clean(reason, noteLimit)
    if not note then
        return false, "Коментар надто довгий або містить недопустимі символи."
    end
    local _, author = unitName("player")
    local entry = { name = name, note = note, author = author or "", addedAt = GetServerTime(),
        deaths = 0, kind = kind or "P" }
    entries[key] = entry
    if kind ~= "G" then
        remember(entry, key, faction, guid)
    end
    addon.RefreshUI()
    return true, "Додано " .. name .. "."
end

local function changeNote(input, reason, kind)
    if not updateScope() then
        return false, unavailable
    end
    local key = entryName(input, kind)
    if not key or not entries[key] then
        return false, "Запису немає в Книзі Образ."
    end
    local note = clean(reason, noteLimit)
    if not note then
        return false, "Коментар надто довгий або містить недопустимі символи."
    end
    entries[key].note = note
    addon.RefreshUI()
    return true, "Коментар збережено."
end

local function deleteEnemy(input, kind)
    if not updateScope() then
        return false, unavailable
    end
    local key
    if input == "" and kind == "G" then
        key = guildName((GetGuildInfo("target")))
    elseif input == "" then
        key = unitName("target")
    else
        key = entryName(input, kind)
    end
    local entry = key and entries[key]
    if not entry then
        return false, "Запису немає в Книзі Образ."
    end
    if entry.guid then
        knownGUIDs[entry.guid] = nil
    end
    entries[key], alerts[key], deaths[key] = nil, nil, nil
    addon.RefreshUI()
    return true, "Вилучено " .. entry.name .. "."
end

local function eligibleRecord(key, entry)
    if entry.kind == "G" then
        return key ~= guildName((GetGuildInfo("player")))
    end
    return isDifferentFaction(entry.faction) and not isAllyName(key)
end

local function mergeEntries(incoming, preview)
    if not updateScope() then
        return 0, 0
    end
    local added, updated, changes = 0, 0, {}
    for key, record in pairs(incoming) do
        if eligibleRecord(key, record) then
            local previous = entries[key]
            if not previous then
                added = added + 1
                if preview then
                    changes[#changes + 1] = { key = key, record = record, new = true }
                else
                    entries[key] = record
                end
            elseif record.kind ~= "G" and record.deaths > previous.deaths then
                updated = updated + 1
                if preview then
                    changes[#changes + 1] = { key = key, record = record, new = false }
                else
                    previous.deaths = math.max(previous.deaths, record.deaths)
                end
            end
        end
    end
    if not preview then
        addon.RefreshUI()
    end
    return added, updated, changes
end

addon.Ordinary = ordinary
addon.IsText = isText
addon.Say = say
addon.Clean = clean
addon.LowerName = lowerName
addon.PlayerName = playerName
addon.EntryName = entryName
addon.UnitName = unitName
addon.EnemyUnit = enemyUnit
addon.EnemyEntry = enemyEntry
addon.UpdateScope = updateScope
addon.Scope = function() return listID end
addon.Entries = sortedEntries
addon.EligibleRecord = eligibleRecord
addon.Merge = mergeEntries
addon.Add = addEnemy
addon.EditNote = changeNote
addon.Delete = deleteEnemy

local function splitAdd(input)
    if input == "" then
        return "", ""
    end
    local name, reason = input:match('^"([^"]+)"%s*(.*)$')
    if not name then
        name, reason = input:match("^(%S+%-%S+)%s*(.*)$")
    end
    if not name then
        name, reason = input:match("^(%S+%s+%S+)%s*(.*)$")
    end
    return name or input, reason or ""
end

local function slash(input)
    local command, rest = input:match("^%s*(%S*)%s*(.-)%s*$")
    command = command:lower()
    local _, message
    if command == "" or command == "ui" then
        addon.ToggleUI()
    elseif command == "add" then
        _, message = addEnemy(splitAdd(rest))
    elseif command == "guild" then
        local operation, guild = rest:match("^(%S+)%s*(.*)$")
        if operation == "add" then
            local name, note = guild:match('^"([^"]+)"%s*(.*)$')
            _, message = addEnemy(name or guild, note or "", nil, "G")
        elseif operation == "del" or operation == "remove" then
            _, message = deleteEnemy(guild, "G")
        else
            message = "/gb guild add [Назва], /gb guild del [Назва]"
        end
    elseif command == "del" or command == "remove" then
        _, message = deleteEnemy(rest)
    elseif command == "share" then
        _, message = addon.Share(rest)
    elseif command == "test" then
        addon.ShowAlert({ name = "GrudgeBook", note = "Тест рейд-тривоги." }, true)
    elseif command == "list" then
        for _, entry in ipairs(sortedEntries()) do
            say(entry.kind == "G" and ("Гільдія «%s»"):format(entry.name)
                or ("%s — смертей: %d"):format(entry.name, entry.deaths))
        end
    else
        message = "/gb ui, /gb add [Ім’я Прізвище] [Коментар], /gb del [Ім’я Прізвище], /gb share [Ім’я Прізвище]"
    end
    if message then
        say(message)
    end
end

frame:SetScript("OnEvent", function(_, event, ...)
    if event == "ADDON_LOADED" and (...) == addonName then
        GrudgeBookDB = GrudgeBookDB or {}
        GrudgeBookDB.lists = GrudgeBookDB.lists or {}
        GrudgeBookDB.guildsImported = GrudgeBookDB.guildsImported or {}
        addon.InitSync()
        addon.InitMenus()
        SLASH_GRUDGEBOOK1, SLASH_GRUDGEBOOK2 = "/gb", "/fw"
        SlashCmdList.GRUDGEBOOK = slash
        C_Timer.NewTicker(1, scanPlates)
    elseif event == "PLAYER_ENTERING_WORLD" or event == "PLAYER_GUILD_UPDATE" or event == "INITIAL_CLUBS_LOADED" then
        updateScope()
        addon.RefreshRoster()
        addon.InitMenus()
    elseif event == "GUILD_ROSTER_UPDATE" then
        addon.ReadRoster()
    elseif event == "PLAYER_LEAVING_WORLD" then
        plates = {}
        addon.CloseAlert()
    elseif event == "PLAYER_TARGET_CHANGED" or event == "UPDATE_MOUSEOVER_UNIT" then
        scanUnit(event == "PLAYER_TARGET_CHANGED" and "target" or "mouseover")
    elseif event == "NAME_PLATE_UNIT_ADDED" or event == "NAME_PLATE_UNIT_REMOVED" then
        local unit = ...
        if isText(unit) then
            if event == "NAME_PLATE_UNIT_ADDED" then
                plates[unit] = scanUnit(unit)
            else
                plates[unit] = nil
            end
        end
    elseif event == "UNIT_DIED" then
        recordDeath(...)
    elseif event == "PARTY_KILL" then
        local _, victim = ...
        recordDeath(victim)
    elseif event == "UNIT_COMBAT" then
        local unit = ...
        if isText(unit) and (unit == "target" or unit == "mouseover" or unit == "focus" or plates[unit] ~= nil) then
            scanUnit(unit)
        end
    elseif event == "UNIT_HEALTH" then
        local unit = ...
        if isText(unit) and (unit == "target" or unit == "mouseover" or plates[unit]) then
            local guid = UnitGUID(unit)
            local key = isText(guid) and knownGUIDs[guid]
            if key and deaths[key] and GetTime() - deaths[key] >= 1 then
                local dead = UnitIsDeadOrGhost(unit)
                if ordinary(dead) and dead == false then
                    deaths[key] = nil
                end
            end
        end
    elseif event == "CHAT_MSG_ADDON" then
        addon.Receive(...)
    elseif event == "ADDON_LOADED" then
        addon.InitMenus()
    end
end)

for _, event in ipairs({
    "ADDON_LOADED", "PLAYER_ENTERING_WORLD", "PLAYER_LEAVING_WORLD", "PLAYER_GUILD_UPDATE",
    "INITIAL_CLUBS_LOADED", "GUILD_ROSTER_UPDATE", "PLAYER_TARGET_CHANGED", "UPDATE_MOUSEOVER_UNIT",
    "NAME_PLATE_UNIT_ADDED", "NAME_PLATE_UNIT_REMOVED", "UNIT_COMBAT", "UNIT_DIED", "PARTY_KILL",
    "UNIT_HEALTH", "CHAT_MSG_ADDON",
}) do
    frame:RegisterEvent(event)
end
