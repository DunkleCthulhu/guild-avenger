local addonName, addon = ...
local frame = CreateFrame("Frame")
local listID, entries
local plates, alerts, deaths, knownGUIDs = {}, {}, {}, {}
local observedGuilds = {}
local cooldown = 30
local deathCooldown = 8
local guildObservationLifetime = 120
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
    alerts, deaths, observedGuilds = {}, {}, {}
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

local function matchGuild(unit, key, faction, guid)
    local guildKey = guildName((GetGuildInfo(unit)))
    local guild = guildKey and entries[guildKey]
    if guid and guildKey then
        observedGuilds[guid] = guild and { guild = guildKey, player = key, faction = faction, at = GetTime() } or nil
    end
    return guild
end

local function warn(key, entry, player, unit)
    local now = GetTime()
    if alerts[key] and now - alerts[key] < cooldown then
        return
    end
    alerts[key] = now
    local guild = entry.kind == "G" and "Гільдія «" .. entry.name .. "»" or ""
    local reason = entry.note ~= "" and " — " .. entry.note or ""
    local heading = entry.high and "Високий пріоритет: " or "Ворог поруч: "
    say(heading .. player .. (guild ~= "" and " — " .. guild or "") .. reason)
    addon.ShowAlert({ name = player, note = guild ~= "" and guild .. reason or entry.note,
        kind = entry.kind, high = entry.high, unit = unit })
end

local function scanUnit(unit, alreadySeen)
    if not entries or not next(entries) then
        return false
    end
    local key, name, faction, guid = enemyUnit(unit)
    if not key then
        return false
    end
    local personal = entries[key]
    local guild = matchGuild(unit, key, faction, guid)
    local entry = personal or guild
    if not entry then
        return false
    end
    if personal then
        remember(personal, key, faction, guid)
    end
    if key ~= alreadySeen then
        warn(key, entry, name, unit)
    end
    return key
end

local lastPrune = 0
local function scanPlates()
    local now = GetTime()
    if now - lastPrune >= 30 then
        lastPrune = now
        for guid, observation in pairs(observedGuilds) do
            if now - observation.at > guildObservationLifetime then observedGuilds[guid] = nil end
        end
        for guid, death in pairs(deaths) do
            if now - death.at >= deathCooldown then deaths[guid] = nil end
        end
    end
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
    local personal = key and entries[key]
    if UnitTokenFromGUID then
        local unit = UnitTokenFromGUID(guid)
        local candidate, _, faction, resolvedGUID = enemyUnit(unit, true)
        if candidate and resolvedGUID == guid then
            key, personal = candidate, entries[candidate]
            if personal then remember(personal, key, faction, guid) end
            matchGuild(unit, key, faction, guid)
        end
    end
    local now = GetTime()
    if personal and (personal.guid ~= guid or not isDifferentFaction(personal.faction) or isAllyName(key)) then
        personal = nil
    end
    local observation = observedGuilds[guid]
    local guild = observation and now - observation.at <= guildObservationLifetime
        and isDifferentFaction(observation.faction) and not isAllyName(observation.player) and entries[observation.guild]
    local death = deaths[guid]
    if not death or now - death.at >= deathCooldown then death = { at = now } end
    if not ((personal and not death.player) or (guild and not death.guild)) then
        return
    end
    if personal and not death.player then
        personal.deaths = math.min(personal.deaths + 1, 2147483647)
        death.player = true
    end
    if guild and not death.guild then
        guild.deaths = math.min(guild.deaths + 1, 2147483647)
        death.guild = true
    end
    deaths[guid] = death
    addon.RefreshUI()
end

local function sortedEntries()
    local list = {}
    for _, entry in pairs(entries or {}) do
        list[#list + 1] = entry
    end
    table.sort(list, function(left, right)
        local leftHigh, rightHigh = left.high == true, right.high == true
        if leftHigh ~= rightHigh then
            return leftHigh
        end
        if strcmputf8i then
            return strcmputf8i(left.name, right.name) < 0
        end
        return lowerName(left.name) < lowerName(right.name)
    end)
    return list
end

local function setPriority(entry, high)
    local key = entryName(entry.name, entry.kind)
    if updateScope() and entries[key] == entry then
        entry.high = high and true or nil
        addon.RefreshUI()
    end
end

local function addEnemy(input, reason, fromUnit, kind)
    if not updateScope() then
        return false, unavailable
    end
    local unit = fromUnit or "target"
    local wanted, writtenName
    if input ~= "" then
        wanted, writtenName = entryName(input, kind)
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
    if kind == "G" and wanted and not fromUnit and not key then
        local ownGuild = guildName((GetGuildInfo("player")))
        if IsInGuild() and not ownGuild then
            return false, unavailable
        end
        if wanted == ownGuild then
            return false, "Власну гільдію додати не можна."
        end
        key, name = wanted, writtenName
    end
    if not key then
        if wanted and kind ~= "G" then
            return false, "WoW має бачити цього персонажа, щоб перевірити, що він ворог."
        end
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
    if kind == "G" then
        local player, _, observedFaction, observedGUID = enemyUnit(unit)
        if player then matchGuild(unit, player, observedFaction, observedGUID) end
    else
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
    entries[key], alerts[key] = nil, nil
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
            else
                local moreDeaths = record.deaths > previous.deaths
                local higherPriority = record.high == true and not previous.high
                if moreDeaths or higherPriority then
                    updated = updated + 1
                    if preview then
                        changes[#changes + 1] = { key = key, record = record, moreDeaths = moreDeaths,
                            higherPriority = higherPriority }
                    else
                        previous.deaths = math.max(previous.deaths, record.deaths)
                        if higherPriority then previous.high = true end
                    end
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
addon.SetPriority = setPriority

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

local function showHelp()
    say("/gb або /gb ui — відкрити книгу · /gb list — показати записи в чаті")
    say("/gb add [Ім’я Прізвище] [Коментар] · /gb del [Ім’я Прізвище]")
    say('/gb guild add ["Назва гільдії"] [Коментар] · /gb guild del [Назва гільдії]')
    say("/gb share [Ім’я Прізвище] — гільдійцю · /gb share guild — у чат гільдії")
    say("/gb test [high] — перевірити сповіщення · /gb download — посилання на GitHub")
end

local function slash(input)
    local command, rest = input:match("^%s*(%S*)%s*(.-)%s*$")
    command = command:lower()
    local _, message
    if command == "" or command == "ui" then
        addon.ToggleUI()
    elseif command == "help" or command == "?" then
        showHelp()
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
        if rest:lower() == "guild" then
            _, message = addon.Publish()
        else
            _, message = addon.Share(rest)
        end
    elseif command == "test" then
        addon.ShowAlert({ name = "GrudgeBook", note = "Тест сповіщення.", unit = "player",
            high = rest:lower() == "high" }, true)
    elseif command == "download" then
        addon.OpenDownload()
    elseif command == "list" then
        local list = sortedEntries()
        say(#list == 0 and "Книга порожня." or ("Записів у Книзі Образ: %d"):format(#list))
        for _, entry in ipairs(list) do
            local name = entry.kind == "G" and ("Гільдія «%s»"):format(entry.name) or entry.name
            say((entry.high and "[Високий] " or "[Звичайний] ") .. ("%s · смертей: %d"):format(name, entry.deaths))
        end
    else
        message = "Невідома команда. Введіть /gb help."
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
        GrudgeBookDB.sound = GrudgeBookDB.sound or {}
        addon.InitSync()
        addon.InitMenus()
        SLASH_GRUDGEBOOK1, SLASH_GRUDGEBOOK2 = "/gb", "/fw"
        SlashCmdList.GRUDGEBOOK = slash
        C_Timer.NewTicker(1, scanPlates)
    elseif event == "PLAYER_ENTERING_WORLD" or event == "PLAYER_GUILD_UPDATE" or event == "INITIAL_CLUBS_LOADED" then
        updateScope()
        addon.RefreshRoster()
        addon.InitMenus()
        if event == "PLAYER_ENTERING_WORLD" then addon.InitMinimap() end
    elseif event == "GUILD_ROSTER_UPDATE" then
        addon.ReadRoster()
    elseif event == "PLAYER_LEAVING_WORLD" then
        plates, observedGuilds, deaths = {}, {}, {}
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
        if isText(unit) and (unit == "target" or unit == "mouseover" or unit == "focus" or plates[unit] ~= nil) then
            local guid = UnitGUID(unit)
            local death = isText(guid) and deaths[guid]
            if death and GetTime() - death.at >= 1 then
                local dead = UnitIsDeadOrGhost(unit)
                if ordinary(dead) and dead == false then
                    deaths[guid] = nil
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
