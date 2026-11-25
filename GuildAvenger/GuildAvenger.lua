local addonName, addon = ...
local L = addon.Text
local frame = CreateFrame("Frame")
local listID, entries
local plates, alerts, deaths, knownGUIDs = {}, {}, {}, {}
local pendingNames = {}
local observedGuilds = {}
local guildAlerts = {}
-- tokens: last alerted enemy per target, mouseover and focus.
local tokens = {}
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

local function searchLower(value)
    if string.utf8lower then return string.utf8lower(value) end
    -- Byte-wise lower() may alter UTF-8 in a non-C locale. Keep saved keys
    -- compatible and use an explicit case fold for search and pending names.
    local ascii = value:gsub("[A-Z]", function(letter) return string.char(letter:byte() + 32) end)
    return (ascii:gsub("[\208-\210][\128-\191]", cyrillicLower))
end

local function clean(value, limit)
    if isText(value) and #value <= limit and not value:find("[%z\001-\031\127|]") then
        return value:match("^ *(.-) *$")
    end
end

local function playerName(value, fromWire)
    value = clean(value, fromWire and nameLimit + 64 or nameLimit)
    if not value then
        return
    end
    -- Forever sends a layer suffix on some roster and chat names.
    local suffix
    if fromWire then
        local name
        name, suffix = value:match("^([^ %-]+[ %-][^ %-]+)%-([^ ]+)$")
        value = name or value
    end
    if #value > nameLimit then
        return
    end
    local first, surname = value:match("^([^ %-]+)[ %-]+([^ %-]+)$")
    -- Reject ASCII punctuation and digits except apostrophes. Lua's %p can
    -- also match UTF-8 bytes in some Windows locales.
    if first and not (first .. surname):find("[\032-\038\040-\064\091-\096\123-\127]") then
        local full = first .. " " .. surname
        return lowerName(full), full, suffix and lowerName(suffix)
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
    if entry.pending and entry.guid then return "pending:" .. entry.guid:upper() end
    return entryName(entry.name, entry.kind)
end

local function isPendingEntry(entry)
    return entry.pending == true or (entry.pendingName == true and entry.faction == nil)
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
    knownGUIDs, pendingNames = {}, {}
    for key, entry in pairs(entries) do
        if entry.guid then
            knownGUIDs[entry.guid] = key
        elseif entry.pendingName and isPendingEntry(entry) then
            pendingNames[searchLower(entry.name)] = key
        end
    end
end

local function guildClubID()
    local club = C_Club.GetGuildClubId()
    if ordinary(club) then return club end
end

local function guildClub()
    local club = guildClubID()
    if club then return tostring(club) end
end

local function guildWatchStatus(key, name)
    if not IsInGuild() then return end
    local ownKey, ownName = guildName((GetGuildInfo("player")))
    if not ownKey and C_Club.GetClubInfo then
        local club = guildClubID()
        local info = club and C_Club.GetClubInfo(club)
        if ordinary(info) and type(info) == "table" then
            ownKey, ownName = guildName(info.name)
        end
    end
    if not ownKey then return "guildPendingVerification" end
    if key == ownKey or searchLower(name) == searchLower(ownName) then return "ownGuild" end
end

function addon.GuildScope()
    local current = IsInGuild() and guildClub()
    if current and current == listID then return current end
end

local function updateScope()
    local id = "local"
    if IsInGuild() then
        id = guildClub()
        if not id then return false end
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
    alerts, deaths, observedGuilds, guildAlerts, tokens = {}, {}, {}, {}, {}
    for unit in pairs(plates) do
        plates[unit] = false
    end
    indexGUIDs()
    addon.RefreshUI()
    return true
end

local function isAllyName(key)
    if key == unitName("player") or addon.IsGuildAlly(key) then
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
    if not key or key == unitName("player") or addon.IsGuildAlly(key) then
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

local function visibleUnit(key, kind)
    local function matches(unit)
        if kind == "G" then return enemyEntry(unit, kind) == key end
        return unitName(unit) == key
    end
    for _, unit in ipairs({ "target", "mouseover", "focus" }) do
        if matches(unit) then
            return unit
        end
    end
    for unit in pairs(plates) do
        if matches(unit) then
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

local function trackedPlayer(key, name, faction, guid)
    local entry = entries[key]
    local normalizedName = searchLower(name)
    local pendingKey = pendingNames[normalizedName]
    if pendingKey then
        pendingNames[normalizedName] = nil
        if pendingKey ~= key then
            local pending = entries[pendingKey]
            entries[pendingKey] = nil
            if not entry then
                entries[key], entry = pending, pending
            end
        end
    end
    local ranked = guid and entries["pending:" .. guid:upper()]
    if ranked then
        entries[recordKey(ranked)] = nil
        if not entry then
            entries[key], entry = ranked, ranked
        else
            knownGUIDs[guid] = nil
        end
        if entry.guid == guid then knownGUIDs[guid] = key end
    end
    if not entry then return end
    local wasPending = isPendingEntry(entry)
    if wasPending then entry.name = name end
    entry.pending, entry.pendingName = nil, nil
    remember(entry, key, faction, guid)
    if wasPending or ranked or pendingKey then
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

local function watchedGuild(key)
    local guild = entries and key and entries[key]
    if guild and not guildWatchStatus(key, guild.name) then return guild end
end

local function matchGuild(unit, key, faction, guid)
    local guildKey, name = guildName((GetGuildInfo(unit)))
    if guid and guildKey then
        observedGuilds[guid] = { guild = guildKey, player = key, faction = faction, at = GetTime() }
    end
    return watchedGuild(guildKey), guildKey, name
end

function addon.HonorTarget(victim)
    local key = playerName(victim, true)
    if not key or not entries or isAllyName(key) then return end
    local personal = entries[key]
    local function result(guild, verified)
        local byName = personal and not isPendingEntry(personal) and (verified or isDifferentFaction(personal.faction))
        local byGuild = watchedGuild(guild) ~= nil
        local reason = byName and (byGuild and "honorBoth" or "honorCharacter") or (byGuild and "honorGuild")
        return key, guild, reason or nil
    end

    local function guildAt(unit)
        local observed, name, faction, guid = enemyUnit(unit, true)
        if observed == key then
            if (personal and isPendingEntry(personal)) or pendingNames[searchLower(name)] then
                personal = trackedPlayer(key, name, faction, guid)
            end
            local _, guild = matchGuild(unit, key, faction, guid)
            return guild or false
        end
    end
    for _, unit in ipairs({ "target", "mouseover", "focus" }) do
        local guild = guildAt(unit)
        if guild ~= nil then return result(guild or nil, true) end
    end
    for unit in pairs(plates) do
        local guild = guildAt(unit)
        if guild ~= nil then return result(guild or nil, true) end
    end
    local now = GetTime()
    local latest
    for _, observation in pairs(observedGuilds) do
        if observation.player == key and now - observation.at <= guildObservationLifetime
            and isDifferentFaction(observation.faction) and (not latest or observation.at > latest.at) then
            latest = observation
        end
    end
    return result(latest and latest.guild, latest ~= nil)
end

local function startAlert(key)
    local now = GetTime()
    if alerts[key] and now - alerts[key] < cooldown then
        return false
    end
    alerts[key] = now
    return true
end

local function warn(entry, player, unit, guid)
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
    -- The player's own history with this enemy goes first, where the two-line alert always shows it.
    local killed, last = addon.KillerHistory(guid, player)
    if killed > 0 then
        local history = L("killedYou", killed, date("%d.%m %H:%M", last))
        note = note ~= "" and (history .. " · " .. note) or history
    end
    addon.ShowAlert({ name = player, note = note, guild = entry.kind == "G" and entry.name or nil,
        kind = entry.kind, high = entry.high, unit = unit })
end

-- The player's own entry for an enemy that a guildmate reported: the character, or the named guild.
function addon.ListedEntry(key, guild)
    if not entries or not key or isAllyName(key) then return end
    local personal = entries[key]
    if personal and not isPendingEntry(personal) and isDifferentFaction(personal.faction) then return personal end
    local guildKey = guild and guildName(guild)
    return watchedGuild(guildKey)
end

local function groupGuildAlert(guildKey, entry, player, unit, guid)
    local burst = guildAlerts[guildKey]
    if burst and burst.entry == entry then
        burst.count = burst.count + 1
        return
    end
    burst = { entry = entry, count = 1 }
    guildAlerts[guildKey] = burst
    C_Timer.After(1.25, function()
        if guildAlerts[guildKey] ~= burst then return end
        guildAlerts[guildKey] = nil
        if watchedGuild(guildKey) ~= entry then return end
        if burst.count == 1 then
            warn(entry, player, unit, guid)
        else
            local headline = L("guildAlertCount", burst.count)
            local note = entry.note ~= "" and headline .. " · " .. entry.note or headline
            say(L("guildNameQuoted", entry.name) .. " — " .. note)
            addon.ShowAlert({name = entry.name, note = note, kind = "G", grouped = true})
        end
    end)
end

local function scanUnit(unit, alreadySeen)
    if not entries or (not next(entries) and not addon.ActiveSeason()) then
        return false
    end
    local key, name, faction, guid = enemyUnit(unit)
    if not key then
        return false
    end
    local personal = trackedPlayer(key, name, faction, guid)
    local guild, guildKey, enemyGuild = matchGuild(unit, key, faction, guid)
    local entry = personal or guild
    if not entry then
        return false
    end
    local now = GetServerTime()
    local zone = clean(GetRealZoneText(), 140)
    local personalSeen = sighting(personal, now, zone)
    local guildSeen = sighting(guild, now, zone)
    if personalSeen or guildSeen then addon.RefreshUI() end
    if key ~= alreadySeen and startAlert(key) then
        addon.RecordLocalMapSighting(key, name, enemyGuild)
        -- Every new alert may be reported to the guild, whether it is shown alone or in a group.
        -- The enemy's guild lets guildmates who list only that guild see the report.
        addon.ReportSighting(key, entry, name, enemyGuild)
        if not personal and not entry.high then
            groupGuildAlert(guildKey, entry, name, unit, guid)
        else
            warn(entry, name, unit, guid)
        end
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
    if not entries or (not next(entries) and not addon.ActiveSeason()) then
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
            key, personal = candidate, trackedPlayer(candidate, name, faction, guid)
            matchGuild(unit, key, faction, guid)
        end
    end
    local now = GetTime()
    if personal and (isPendingEntry(personal) or personal.guid ~= guid or not isDifferentFaction(personal.faction) or isAllyName(key)) then
        personal = nil
    end
    local observation = observedGuilds[guid]
    local guild = observation and now - observation.at <= guildObservationLifetime
        and isDifferentFaction(observation.faction) and not isAllyName(observation.player) and watchedGuild(observation.guild)
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
            unit = visibleUnit(wanted, kind)
        end
    end
    local key, name, faction, guid = enemyEntry(unit, kind)
    local seenNow = key ~= nil
    local pending = kind ~= "G" and wanted and not fromUnit and not unit
    if pending then key, name = wanted, writtenName end
    if kind == "G" and wanted and not fromUnit and not key then
        key, name = wanted, writtenName
    end
    if not key then
        return false, kind == "G" and L("guildNotVisible") or L("invalidEnemy")
    end
    local guildStatus = kind == "G" and guildWatchStatus(key, name)
    if guildStatus == "ownGuild" then return false, L(guildStatus) end
    local pendingName = kind ~= "G" and searchLower(name)
    if entries[key] or (pendingName and pendingNames[pendingName]) then
        return false, L("alreadyListed")
    end
    local note = clean(reason, noteLimit)
    if not note then
        return false, L("invalidNote")
    end
    local _, author = unitName("player")
    local entry = { name = name, note = note, author = author or "", addedAt = GetServerTime(),
        deaths = 0, kind = kind or "P", pendingName = pending and true or nil }
    if seenNow then sighting(entry, entry.addedAt, clean(GetRealZoneText(), 140)) end
    entries[key] = entry
    if pending then pendingNames[pendingName] = key end
    removalLog()[key] = nil
    if kind == "G" then
        local player, _, observedFaction, observedGUID = enemyUnit(unit)
        if player then matchGuild(unit, player, observedFaction, observedGUID) end
    elseif not pending then
        remember(entry, key, faction, guid)
    end
    addon.RefreshUI()
    local message = pending and "entryAddedPending" or (guildStatus and "guildAddedPending" or "entryAdded")
    return true, L(message, name)
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
    if entry.pendingName then pendingNames[searchLower(entry.name)] = nil end
    if rememberRemoval and not isPendingEntry(entry) then
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
        local name
        key, name = entryName(input, kind)
        if kind ~= "G" and name and not entries[key] then key = pendingNames[searchLower(name)] end
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
    if isPendingEntry(entry) then return false end
    if entry.kind == "G" then
        return not guildWatchStatus(key, entry.name)
    end
    return isDifferentFaction(entry.faction) and not isAllyName(key)
end

-- Adds an enemy known by character ID. If WoW cannot see them now, the entry waits for the next encounter.
local function addByGUID(guid, enemyName, note)
    local pendingKey = "pending:" .. guid:upper()
    local nameKey = enemyName:find(" ", 1, true) and playerName(enemyName)
    if nameKey and isAllyName(nameKey) then return false, L("invalidEnemy") end
    if entries[pendingKey] or knownGUIDs[guid] or (nameKey and entries[nameKey]) then
        return false, L("enemyAlreadyListed")
    end
    local unit = UnitTokenFromGUID and UnitTokenFromGUID(guid)
    local key, name = enemyUnit(unit)
    if key then return addEnemy(name, note, unit) end
    local _, author = unitName("player")
    entries[pendingKey] = { name = enemyName, note = note, author = author or "", addedAt = GetServerTime(),
        kind = "P", deaths = 0, guid = guid, pending = true }
    if nameKey then removalLog()[nameKey] = nil end
    addon.RefreshUI()
    return true, L("rankedEnemyAdded", enemyName)
end

function addon.AddRankedEnemy(guid)
    if not updateScope() then return false, L("guildLoading") end
    local enemy = addon.RankedEnemy(guid)
    if not enemy then return false, L("rankedEntryMissing") end
    return addByGUID(guid, enemy.name, L("rankedEnemyNote"))
end

-- The killer from a My Deaths journal row.
function addon.AddKiller(guid, name)
    if not updateScope() then return false, L("guildLoading") end
    if not isText(guid) or not guid:match("^Player%-%d+%-%x+$") or not isText(name) or name == "" then
        return false, L("rankedEntryMissing")
    end
    return addByGUID(guid, name, L("killerNote"))
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
    local touched = {}
    for key, record in pairs(incoming) do
        local plan = planned and planned[key]
        -- A count row is reviewed apart from the note or priority row of the same entry.
        local countOnly = plan and plan.countOnly
        if countOnly then key = plan.entry end
        local previous = entries[key]
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
                local moreDeaths = record.deaths > previous.deaths and not (plan and plan.split)
                local higherPriority = record.high == true and not previous.high
                local changedNote = explicit and same and not countOnly and record.note ~= previous.note
                local changedPriority = explicit and same and not countOnly
                    and (record.high == true) ~= (previous.high == true)
                if moreDeaths or (not explicit and higherPriority) or changedNote or changedPriority then
                    if not touched[key] then
                        touched[key] = true
                        updated = updated + 1
                    end
                    if preview then
                        local split = moreDeaths and (changedNote or changedPriority)
                        if split then
                            -- A tab cannot appear in a name, so this key never collides with an entry.
                            changes[#changes + 1] = { key = key .. "\tdeaths", entry = key, record = record,
                                moreDeaths = true, countOnly = true, previous = previous,
                                oldNote = previous.note, oldHigh = previous.high == true }
                        end
                        changes[#changes + 1] = { key = key, record = record, moreDeaths = moreDeaths and not split,
                            split = split or nil,
                            higherPriority = higherPriority, changedNote = changedNote, changedPriority = changedPriority,
                            previous = previous, oldNote = previous.note, oldHigh = previous.high == true }
                    else
                        if moreDeaths then previous.deaths = record.deaths end
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
addon.SearchLower = searchLower
addon.PlayerName = playerName
addon.EntryName = entryName
addon.RecordKey = recordKey
addon.IsPendingEntry = isPendingEntry
addon.GuildWatchStatus = guildWatchStatus
addon.UnitName = unitName
addon.EnemyUnit = enemyUnit
addon.EnemyEntry = enemyEntry
addon.UpdateScope = updateScope
addon.Scope = function() return listID end
addon.Entries = sortedEntries
addon.WatchlistRecord = function(key) return entries and entries[key] end
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
    say(L("helpRevokeLinks"))
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
    elseif command == "addtarget" then
        -- "add" reads any text as a name, so the target takes a note through its own command.
        _, message = addEnemy("", rest)
    elseif command == "guild" then
        local operation, guild = rest:match("^(%S+)%s*(.*)$")
        if operation == "add" then
            local name, note = guild:match('^"([^"]+)"%s*(.*)$')
            _, message = addEnemy(name or guild, note or "", nil, "G")
        elseif operation == "addtarget" then
            _, message = addEnemy("", guild, nil, "G")
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
    elseif command == "revoke" then
        _, message = addon.RevokeWatchlistLinks()
    elseif command == "test" then
        addon.ShowAlert({ name = "Guild Avenger", note = L("testAlert"), unit = "player",
            high = rest:lower() == "high" }, true)
    elseif command == "download" then
        addon.OpenDownload()
    elseif command == "stats" then
        addon.OpenStats()
    elseif command == "settings" then
        addon.PromptSettings()
    elseif command == "minimap" then
        message = addon.ToggleMinimap()
    elseif command == "reload" then
        -- WoW refuses a reload from an addon button but allows it from a typed command.
        if InCombatLockdown() then
            message = L("reloadAfterCombat")
        else
            C_UI.Reload()
        end
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
        addon.InitSeason()
        addon.InitSightings()
        addon.InitSightingMap()
        addon.InitMenus()
        SLASH_GUILDAVENGER1 = "/gavenger"
        SlashCmdList.GUILDAVENGER = slash
        C_Timer.NewTicker(1, scanPlates)
    elseif event == "PLAYER_ENTERING_WORLD" or event == "PLAYER_GUILD_UPDATE" or event == "INITIAL_CLUBS_LOADED" then
        updateScope()
        addon.RefreshRoster()
        addon.InitMenus()
        addon.RefreshUI()
        addon.RefreshSettingsGuild()
        if event == "PLAYER_ENTERING_WORLD" then addon.InitMinimap() end
        addon.RefreshSightingMap()
    elseif event == "GUILD_ROSTER_UPDATE" then
        addon.ReadRoster()
        addon.SeasonRosterReady()
        addon.RefreshStats()
        addon.RefreshUI()
        addon.RefreshSettingsGuild()
    elseif event == "PLAYER_LEAVING_WORLD" then
        plates, observedGuilds, deaths, guildAlerts, tokens = {}, {}, {}, {}, {}
        addon.CloseAlert()
    elseif event == "PLAYER_TARGET_CHANGED" or event == "UPDATE_MOUSEOVER_UNIT" or event == "PLAYER_FOCUS_CHANGED" then
        local unit = event == "PLAYER_TARGET_CHANGED" and "target"
            or event == "PLAYER_FOCUS_CHANGED" and "focus" or "mouseover"
        tokens[unit] = scanUnit(unit)
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
        -- Combat events repeat through a fight, so an enemy already announced on this unit stays quiet.
        if isText(unit) then
            if plates[unit] ~= nil then
                plates[unit] = scanUnit(unit, plates[unit])
            elseif unit == "target" or unit == "mouseover" or unit == "focus" then
                tokens[unit] = scanUnit(unit, tokens[unit])
            end
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
        addon.ReceiveSeason(...)
        addon.ReceiveSighting(...)
    elseif event == "ADDON_LOADED" then
        addon.InitMenus()
        if (...) == "Blizzard_WorldMap" then addon.InitSightingMap() end
    end
end)

for _, event in ipairs({
    "ADDON_LOADED", "PLAYER_ENTERING_WORLD", "PLAYER_LEAVING_WORLD", "PLAYER_GUILD_UPDATE",
    "INITIAL_CLUBS_LOADED", "GUILD_ROSTER_UPDATE", "PLAYER_TARGET_CHANGED", "UPDATE_MOUSEOVER_UNIT",
    "NAME_PLATE_UNIT_ADDED", "NAME_PLATE_UNIT_REMOVED", "UNIT_COMBAT", "UNIT_DIED", "PARTY_KILL",
    "UNIT_HEALTH", "CHAT_MSG_ADDON", "CHAT_MSG_COMBAT_HONOR_GAIN", "PLAYER_DEAD", "PLAYER_ALIVE", "PLAYER_UNGHOST",
    "PLAYER_FOCUS_CHANGED",
}) do
    frame:RegisterEvent(event)
end
