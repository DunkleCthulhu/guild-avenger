local _, addon = ...
local L = addon.Text
-- A prefix of its own: versions without sightings never register it, so they never see these messages.
local prefix = "GuildAvSeen1"
local messageLimit = 240
local enemyInterval, sendInterval, postInterval = 60, 5, 10
-- Times by enemy key: reported by this client, reported by a guildmate, shown to the player.
local sent, heard, shown = {}, {}, {}
local lastSent, lastPost

function addon.InitSightings()
    -- Sending reveals where the player is, so everything here starts switched off.
    GuildAvengerDB.sightings = GuildAvengerDB.sightings or {}
    C_ChatInfo.RegisterAddonMessagePrefix(prefix)
end

function addon.SightingSetting(name)
    return GuildAvengerDB.sightings[name] == true
end

function addon.SetSightingSetting(name, value)
    GuildAvengerDB.sightings[name] = value and true or nil
end

local function inGuild()
    local scope, key = addon.Scope(), addon.UnitName("player")
    return scope ~= nil and scope ~= "local" and IsInGuild() and key ~= nil and addon.IsGuildMember(key)
end

local function inInstance()
    local inside = IsInInstance()
    return not addon.Ordinary(inside) or inside == true or inside == 1
end

local function recently(times, key, now)
    for other, at in pairs(times) do
        if now - at >= enemyInterval then times[other] = nil end
    end
    return times[key] ~= nil
end

-- The player's zone, subzone and map position in whole percent.
local function ownPlace()
    local place = {}
    addon.Location(place)
    local x = place.x and math.floor(place.x * 100 + 0.5)
    local y = place.y and math.floor(place.y * 100 + 0.5)
    return place.zone or "", place.area or "", x, y
end

local function placeText(zone, area, x, y)
    local text = zone ~= "" and zone or L("unknownLocation")
    if area ~= "" and area ~= zone then text = text .. " · " .. area end
    if x and y then text = text .. (" (%d, %d)"):format(x, y) end
    return text
end

-- Called for every new alert. Sends one addon message to the guild when the player allowed it.
function addon.ReportSighting(key, entry, name, guild)
    if not addon.SightingSetting("send") or not inGuild() or inInstance() then return end
    local now = GetTime()
    if recently(sent, key, now) or recently(heard, key, now) or (lastSent and now - lastSent < sendInterval) then
        return
    end
    local zone, area, x, y = ownPlace()
    local kind = entry.kind == "G" and "G" or "P"
    local function compose(subzone)
        return ("S\t%s\t%s\t%s\t%s\t%s\t%s\t%s"):format(kind, name, guild or "",
            x and y and tostring(x) or "", x and y and tostring(y) or "", zone, subzone)
    end
    local message = compose(area)
    if #message > messageLimit then message = compose("") end
    if #message > messageLimit then return end
    if C_ChatInfo.SendAddonMessage(prefix, message, "GUILD") == Enum.SendAddonMessageResult.Success then
        sent[key], lastSent = now, now
    end
end

function addon.ReceiveSighting(receivedPrefix, message, channel, sender)
    if not addon.IsText(receivedPrefix) or receivedPrefix ~= prefix or not addon.IsText(channel) or channel ~= "GUILD"
        or not addon.IsText(message) or #message > messageLimit then return end
    local reporterKey, reporter = addon.PlayerName(sender, true)
    if not reporterKey or reporterKey == addon.UnitName("player") or not addon.IsGuildMember(reporterKey) then return end
    local kind, name, guild, x, y, zone, area =
        message:match("^S\t([PG])\t([^\t]+)\t([^\t]*)\t(%d*)\t(%d*)\t([^\t]*)\t([^\t]*)$")
    if not kind or #x > 3 or #y > 3 then return end
    local key, full = addon.PlayerName(name)
    zone, area = addon.Clean(zone, 140), addon.Clean(area, 140)
    x, y = tonumber(x), tonumber(y)
    if not key or not zone or not area or (x == nil) ~= (y == nil) or (x and (x > 100 or y > 100)) then return end
    local now = GetTime()
    -- A guildmate already reported this enemy, so this client stays quiet about them for a while.
    recently(heard, key, now)
    heard[key] = now
    if not addon.SightingSetting("receive") then return end
    -- Only enemies on the player's own watchlist are shown, with the player's own note and priority.
    -- A character report names their guild too, so a player who lists only the guild sees it.
    local entry = addon.ListedEntry(key, guild ~= "" and guild or nil)
    if not entry or recently(shown, key, now) then return end
    shown[key] = now
    local place = placeText(zone, area, x, y)
    local line = L(entry.high and "sightingHigh" or "sighting", full, place, reporter)
    if entry.kind == "G" then line = line .. " — " .. L("guildNameQuoted", entry.name) end
    if entry.note ~= "" then line = line .. " — " .. entry.note end
    addon.Say(line)
    if addon.SightingSetting("popup") then
        local note = L("sightingAlert", place, reporter)
        if entry.note ~= "" then note = note .. " · " .. entry.note end
        addon.ShowAlert({ name = full, note = note, kind = entry.kind, high = entry.high, remote = true })
    end
end

-- The alert's guild chat button: one visible line in guild chat, sent only on a click.
function addon.PostSighting(name, guild)
    if not inGuild() then return false, L("sharingRequiresGuild") end
    if C_ChatInfo.InChatMessagingLockdown and C_ChatInfo.InChatMessagingLockdown() then
        return false, L("chatLockdown")
    end
    local now = GetTime()
    if lastPost and now - lastPost < postInterval then return false end
    local zone, area, x, y = ownPlace()
    local subject = guild and (name .. " — " .. L("guildNameQuoted", guild)) or name
    local text = L("sightingPost", subject, placeText(zone, area, x, y))
    if #text > 255 then text = L("sightingPost", subject, placeText(zone, "", x, y)) end
    if #text > 255 then text = L("sightingPostShort", name) end
    lastPost = now
    C_ChatInfo.SendChatMessage(text, "GUILD")
    return true
end
