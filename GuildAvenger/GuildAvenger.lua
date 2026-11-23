local addonName, addon = ...
local L = addon.Text
local frame = CreateFrame("Frame")
local listID, entries
local plates, alerts, deaths, knownGUIDs = {}, {}, {}, {}
local observedGuilds = {}
local cooldown = 30
local deathCooldown = 8
local guildObservationLifetime = 120
local nameLimit, noteLimit = 96, 104

addon.NameLimit, addon.NoteLimit = nameLimit, noteLimit

local function ordinary(value)
    return not issecretvalue or not issecretvalue(value)
end

local function isText(value)
    return ordinary(value) and type(value) == "string"
end

local function say(message)
    DEFAULT_CHAT_FRAME:AddMessage("|cffdf8278Guild Avenger|r " .. message)
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

local function recordKey(entry)
    if entry.pending then return "pending:" .. entry.guid:upper() end
    return entryName(entry.name, entry.kind)
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
    local legacy = GuildAvengerLegacyDB and GuildAvengerLegacyDB[id]
    if not GuildAvengerDB.lists[id] then
        GuildAvengerDB.lists[id] = {}
        importLegacy(GuildAvengerDB.lists[id], legacy, "P")
    end
    entries = GuildAvengerDB.lists[id]
    if not GuildAvengerDB.guildsImported[id] then
        importLegacy(entries, legacy, "G")
        GuildAvengerDB.guildsImported[id] = true
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

local function trackedPlayer(key, name, guid)
    local entry = entries[key]
    local pending = guid and entries["pending:" .. guid:upper()]
    if pending then
        entries[recordKey(pending)] = nil
        if not entry then
            pending.name, pending.pending = name, nil
            entries[key], entry = pending, pending
        else
            knownGUIDs[guid] = nil
        end
        if entry.guid == guid then knownGUIDs[guid] = key end
        addon.RefreshUI()
    end
    return entry
end

local function sighting(entry, now, zone)
    if not entry then return false end
    local previous = entry.seen
    if previous and previous.zone == zone and now - previous.at < 30 then return false end
    entry.seen = { at = now, zone = zone }
    return true
end

local function matchGuild(unit, key, faction, guid)
    local guildKey = guildName((GetGuildInfo(unit)))
    local guild = guildKey and entries[guildKey]
    if guid and guildKey then
        observedGuilds[guid] = guild and { guild = guildKey, player = key, faction = faction, at = GetTime() } or nil
    end
    return guild
end

function addon.IsHonorTarget(victim)
    local key = playerName(victim, true)
    if not key or not entries or isAllyName(key) then return false end

    local personal = entries[key]
    if personal and not personal.pending and isDifferentFaction(personal.faction) then return true end

    local function matches(unit)
        local observed, _, faction, guid = enemyUnit(unit, true)
        if observed == key then
            return personal ~= nil or matchGuild(unit, key, faction, guid) ~= nil
        end
    end
    for _, unit in ipairs({ "target", "mouseover", "focus" }) do
        local match = matches(unit)
        if match ~= nil then return match end
    end
    for unit in pairs(plates) do
        local match = matches(unit)
        if match ~= nil then return match end
    end
    local now = GetTime()
    for _, observation in pairs(observedGuilds) do
        if observation.player == key and now - observation.at <= guildObservationLifetime
            and entries[observation.guild] and isDifferentFaction(observation.faction) then
            return true
        end
    end
    return false
end

local function warn(key, entry, player, unit, guid)
    local now = GetTime()
    if alerts[key] and now - alerts[key] < cooldown then
        return
    end
    alerts[key] = now
    local guild = entry.kind == "G" and L("guildNameQuoted", entry.name) or ""
    local reason = entry.note ~= "" and " — " .. entry.note or ""
    local heading = L(entry.high and "highAlert" or "nearbyAlert", player)
    say(heading .. (guild ~= "" and " — " .. guild or "") .. reason)
    local count = addon.EnemyScore(guid)
    local note = guild ~= "" and guild .. reason or entry.note
    if count > 0 then
        local score = L("guildmateKills", count)
        note = note ~= "" and (score .. " · " .. note) or score
    end
    addon.ShowAlert({ name = player, note = note,
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
    local personal = trackedPlayer(key, name, guid)
    local guild = matchGuild(unit, key, faction, guid)
    local entry = personal or guild
    if not entry then
        return false
    end
    if personal then
        remember(personal, key, faction, guid)
    end
    local now = GetServerTime()
    local zone = clean(GetRealZoneText(), 140)
    local personalSeen = sighting(personal, now, zone)
    local guildSeen = sighting(guild, now, zone)
    if personalSeen or guildSeen then addon.RefreshUI() end
    if key ~= alreadySeen then
        warn(key, entry, name, unit, guid)
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

local function recordDeath(guid, killer)
    if not isText(guid) or not entries then
        return
    end
    local key = knownGUIDs[guid]
    local personal = key and entries[key]
    if UnitTokenFromGUID then
        local unit = UnitTokenFromGUID(guid)
        local candidate, name, faction, resolvedGUID = enemyUnit(unit, true)
        if candidate and resolvedGUID == guid then
            key, personal = candidate, trackedPlayer(candidate, name, guid)
            if personal then remember(personal, key, faction, guid) end
            matchGuild(unit, key, faction, guid)
        end
    end
    local now = GetTime()
    if personal and (personal.pending or personal.guid ~= guid or not isDifferentFaction(personal.faction) or isAllyName(key)) then
        personal = nil
    end
    local observation = observedGuilds[guid]
    local guild = observation and now - observation.at <= guildObservationLifetime
        and isDifferentFaction(observation.faction) and not isAllyName(observation.player) and entries[observation.guild]
    if not personal and not guild then return end
    local death = deaths[guid]
    if not death or now - death.at >= deathCooldown then death = { at = now } end
    if not death.revenge and addon.IsOwnKillingBlow(killer) then
        death.revenge = true
        addon.RecordRevenge()
    end
    deaths[guid] = death
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
    local key = recordKey(entry)
    if updateScope() and entries[key] == entry then
        entry.high = high and true or nil
        addon.RefreshUI()
    end
end

local function removalLog()
    local logs = GuildAvengerDB.removals
    if not logs[listID] then logs[listID] = {} end
    return logs[listID]
end

local function addEnemy(input, reason, fromUnit, kind)
    if not updateScope() then
        return false, L("guildLoading")
    end
    local unit = fromUnit or "target"
    local wanted, writtenName
    if input ~= "" then
        wanted, writtenName = entryName(input, kind)
        if not wanted then
            return false, kind == "G" and L("enterGuildName") or L("enterCharacterName")
        end
        if kind ~= "G" and isAllyName(wanted) then
            return false, L("invalidEnemy")
        end
        if not fromUnit or wanted ~= enemyEntry(fromUnit, kind) then
            unit = visibleEnemy(wanted, kind)
        end
    end
    local key, name, faction, guid = enemyEntry(unit, kind)
    local seenNow = key ~= nil
    if kind == "G" and wanted and not fromUnit and not key then
        local ownGuild = guildName((GetGuildInfo("player")))
        if IsInGuild() and not ownGuild then
            return false, L("guildLoading")
        end
        if wanted == ownGuild then
            return false, L("ownGuild")
        end
        key, name = wanted, writtenName
    end
    if not key then
        if wanted and kind ~= "G" then
            return false, L("characterNotVisible")
        end
        return false, kind == "G" and L("guildNotVisible") or L("invalidEnemy")
    end
    if entries[key] then
        return false, L("alreadyListed")
    end
    local note = clean(reason, noteLimit)
    if not note then
        return false, L("invalidNote")
    end
    local _, author = unitName("player")
    local entry = { name = name, note = note, author = author or "", addedAt = GetServerTime(),
        deaths = 0, kind = kind or "P" }
    if seenNow then sighting(entry, entry.addedAt, clean(GetRealZoneText(), 140)) end
    entries[key] = entry
    removalLog()[key] = nil
    if kind == "G" then
        local player, _, observedFaction, observedGUID = enemyUnit(unit)
        if player then matchGuild(unit, player, observedFaction, observedGUID) end
    else
        remember(entry, key, faction, guid)
    end
    addon.RefreshUI()
    return true, L("entryAdded", name)
end

local function changeNote(input, reason, kind, selected)
    if not updateScope() then
        return false, L("guildLoading")
    end
    local key = selected and recordKey(selected) or entryName(input, kind)
    if not key or not entries[key] then
        return false, L("entryMissing")
    end
    local note = clean(reason, noteLimit)
    if not note then
        return false, L("invalidNote")
    end
    entries[key].note = note
    addon.RefreshUI()
    return true, L("noteSaved")
end

local function removeEntry(key, entry, rememberRemoval)
    if entry.guid then knownGUIDs[entry.guid] = nil end
    if rememberRemoval and not entry.pending then
        removalLog()[key] = { name = entry.name, kind = entry.kind, at = GetServerTime() }
    end
    entries[key], alerts[key] = nil, nil
end

local function deleteEnemy(input, kind, selected)
    if not updateScope() then
        return false, L("guildLoading")
    end
    local key
    if selected then
        key = recordKey(selected)
    elseif input == "" and kind == "G" then
        key = guildName((GetGuildInfo("target")))
    elseif input == "" then
        key = unitName("target")
    else
        key = entryName(input, kind)
    end
    local entry = key and entries[key]
    if not entry then
        return false, L("entryMissing")
    end
    removeEntry(key, entry, true)
    addon.RefreshUI()
    return true, L("entryRemoved", entry.name)
end

function addon.DeleteSelection(selection, scope)
    if not updateScope() or listID ~= scope then return 0 end
    local count = 0
    for key, entry in pairs(selection) do
        if entries[key] == entry then
            removeEntry(key, entry, true)
            count = count + 1
        end
    end
    addon.RefreshUI()
    return count
end

local function eligibleRecord(key, entry)
    if entry.pending then return false end
    if entry.kind == "G" then
        return key ~= guildName((GetGuildInfo("player")))
    end
    return isDifferentFaction(entry.faction) and not isAllyName(key)
end

function addon.AddRankedEnemy(guid)
    if not updateScope() then return false, L("guildLoading") end
    local enemy = addon.RankedEnemy(guid)
    if not enemy then return false, L("rankedEntryMissing") end
    local pendingKey = "pending:" .. guid:upper()
    local nameKey = enemy.name:find(" ", 1, true) and playerName(enemy.name)
    if nameKey and isAllyName(nameKey) then return false, L("invalidEnemy") end
    if entries[pendingKey] or knownGUIDs[guid] or (nameKey and entries[nameKey]) then
        return false, L("enemyAlreadyListed")
    end
    local note = L("rankedEnemyNote")
    local unit = UnitTokenFromGUID and UnitTokenFromGUID(guid)
    local key, name = enemyUnit(unit)
    if key then return addEnemy(name, note, unit) end
    local _, author = unitName("player")
    entries[pendingKey] = { name = enemy.name, note = note, author = author or "", addedAt = GetServerTime(),
        kind = "P", deaths = 0, guid = guid, pending = true }
    if nameKey then removalLog()[nameKey] = nil end
    addon.RefreshUI()
    return true, L("rankedEnemyAdded", enemy.name)
end

function addon.RemovalProposals()
    local proposals, now = {}, GetServerTime()
    for key, record in pairs(removalLog()) do
        if now - record.at > 30 * 86400 or entries[key] then
            removalLog()[key] = nil
        else
            proposals[#proposals + 1] = record
        end
    end
    return proposals
end

local function mergeEntries(incoming, preview, explicit, planned)
    if not updateScope() then
        return 0, 0
    end
    local added, updated, changes, removed = 0, 0, {}, 0
    for key, record in pairs(incoming) do
        local previous = entries[key]
        local plan = planned and planned[key]
        local same = not plan or (plan.previous == previous and (not previous or
            (previous.note == plan.oldNote and (previous.high == true) == plan.oldHigh)))
        if record.removed and explicit and previous and same then
            removed = removed + 1
            if preview then
                changes[#changes + 1] = { key = key, record = previous, proposal = record, removed = true,
                    previous = previous, oldNote = previous.note, oldHigh = previous.high == true }
            else
                removeEntry(key, previous, false)
            end
        elseif not record.removed and eligibleRecord(key, record) then
            if not previous and same then
                added = added + 1
                if preview then
                    changes[#changes + 1] = { key = key, record = record, new = true }
                else
                    entries[key] = record
                    removalLog()[key] = nil
                end
            elseif previous then
                local moreDeaths = record.deaths > previous.deaths
                local higherPriority = record.high == true and not previous.high
                local changedNote = explicit and same and record.note ~= previous.note
                local changedPriority = explicit and same and (record.high == true) ~= (previous.high == true)
                if moreDeaths or (not explicit and higherPriority) or changedNote or changedPriority then
                    updated = updated + 1
                    if preview then
                        changes[#changes + 1] = { key = key, record = record, moreDeaths = moreDeaths,
                            higherPriority = higherPriority, changedNote = changedNote, changedPriority = changedPriority,
                            previous = previous, oldNote = previous.note, oldHigh = previous.high == true }
                    else
                        previous.deaths = math.max(previous.deaths, record.deaths)
                        if changedNote then previous.note = record.note end
                        if changedPriority then previous.high = record.high == true and true or nil end
                        if not explicit and higherPriority then previous.high = true end
                    end
                end
            end
        end
    end
    if not preview then
        addon.RefreshUI()
    end
    return added, updated, changes, removed
end

addon.Ordinary = ordinary
addon.IsText = isText
addon.Say = say
addon.Clean = clean
addon.LowerName = lowerName
addon.PlayerName = playerName
addon.EntryName = entryName
addon.RecordKey = recordKey
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
    say(L("helpOverview"))
    say(L("helpCharacters"))
    say(L("helpGuilds"))
    say(L("helpSharing"))
    say(L("helpRequestLists"))
    say(L("helpAlerts"))
    say(L("helpStats"))
    say(L("helpSettings"))
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
            message = L("guildCommandUsage")
        end
    elseif command == "del" or command == "remove" then
        _, message = deleteEnemy(rest)
    elseif command == "share" then
        if rest:lower() == "guild" then
            _, message = addon.Publish()
        else
            _, message = addon.Share(rest)
        end
    elseif command == "request" then
        _, message = addon.RequestWatchlists()
    elseif command == "test" then
        addon.ShowAlert({ name = "Guild Avenger", note = L("testAlert"), unit = "player",
            high = rest:lower() == "high" }, true)
    elseif command == "download" then
        addon.OpenDownload()
    elseif command == "stats" then
        addon.OpenStats()
    elseif command == "settings" then
        addon.PromptSettings()
    elseif command == "list" then
        local list = sortedEntries()
        say(#list == 0 and L("emptyListChat") or L("entryCountChat", #list))
        for _, entry in ipairs(list) do
            local name = entry.kind == "G" and L("guildNameQuoted", entry.name) or entry.name
            say((entry.high and L("chatHigh") or L("chatNormal")) .. L("chatEntryDeaths", name, entry.deaths))
        end
    else
        message = L("unknownCommand")
    end
    if message then
        say(message)
    end
end

frame:SetScript("OnEvent", function(_, event, ...)
    if event == "ADDON_LOADED" and (...) == addonName then
        local hadSettings = GuildAvengerDB ~= nil or GuildAvengerLegacyDB ~= nil
        GuildAvengerDB = GuildAvengerDB or {}
        addon.InitLanguage(hadSettings)
        GuildAvengerDB.lists = GuildAvengerDB.lists or {}
        GuildAvengerDB.guildsImported = GuildAvengerDB.guildsImported or {}
        GuildAvengerDB.sound = GuildAvengerDB.sound or {}
        GuildAvengerDB.removals = GuildAvengerDB.removals or {}
        addon.InitSync()
        addon.InitStats()
        addon.InitMenus()
        SLASH_GUILDAVENGER1 = "/gavenger"
        SlashCmdList.GUILDAVENGER = slash
        C_Timer.NewTicker(1, scanPlates)
    elseif event == "PLAYER_ENTERING_WORLD" or event == "PLAYER_GUILD_UPDATE" or event == "INITIAL_CLUBS_LOADED" then
        updateScope()
        addon.RefreshRoster()
        addon.InitMenus()
        if event == "PLAYER_ENTERING_WORLD" then addon.InitMinimap() end
    elseif event == "GUILD_ROSTER_UPDATE" then
        addon.ReadRoster()
        addon.RefreshStats()
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
        local killer, victim = ...
        recordDeath(victim, killer)
    elseif event == "CHAT_MSG_COMBAT_HONOR_GAIN" then
        local message = ...
        addon.OnHonorGain(message, select(11, ...))
    elseif event == "PLAYER_DEAD" then
        addon.RecordOwnDeath()
    elseif event == "PLAYER_ALIVE" or event == "PLAYER_UNGHOST" then
        addon.ResetOwnDeath()
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
        addon.ReceiveStats(...)
    elseif event == "ADDON_LOADED" then
        addon.InitMenus()
    end
end)

for _, event in ipairs({
    "ADDON_LOADED", "PLAYER_ENTERING_WORLD", "PLAYER_LEAVING_WORLD", "PLAYER_GUILD_UPDATE",
    "INITIAL_CLUBS_LOADED", "GUILD_ROSTER_UPDATE", "PLAYER_TARGET_CHANGED", "UPDATE_MOUSEOVER_UNIT",
    "NAME_PLATE_UNIT_ADDED", "NAME_PLATE_UNIT_REMOVED", "UNIT_COMBAT", "UNIT_DIED", "PARTY_KILL",
    "UNIT_HEALTH", "CHAT_MSG_ADDON", "CHAT_MSG_COMBAT_HONOR_GAIN", "PLAYER_DEAD", "PLAYER_ALIVE", "PLAYER_UNGHOST",
}) do
    frame:RegisterEvent(event)
end
