local _, addon = ...
local L = addon.Text
local template = "GuildAvengerSightingPinTemplate"
local lifetime, recordInterval = 15 * 60, 30
local localSightings, guildSightings = {}, {}
local provider

local function validNumber(value)
    return addon.Ordinary(value) and type(value) == "number"
end

local function normalized(value)
    return validNumber(value) and value >= 0 and value <= 1
end

local function mapInfo(id)
    if not validNumber(id) or id <= 0 or id > 2147483647 or id % 1 ~= 0 then return end
    local info = C_Map.GetMapInfo(id)
    if addon.Ordinary(info) and type(info) == "table" then return info end
end

local function project(place, mapID)
    local id, x, y = place.mapID, place.x, place.y
    -- Walk through parent maps so each position stays inside its own zone or continent.
    for _ = 1, 8 do
        if id == mapID then
            if normalized(x) and normalized(y) then return x, y end
            return
        end
        local parent = (mapInfo(id) or {}).parentMapID
        if not validNumber(parent) or parent <= 0 or parent == id then return end
        local left, right, top, bottom = C_Map.GetMapRectOnMap(id, parent)
        if not validNumber(left) or not validNumber(right) or not validNumber(top) or not validNumber(bottom)
            or right <= left or bottom <= top then return end
        x, y = left + (right - left) * x, top + (bottom - top) * y
        id = parent
    end
end

local function store(sightings, key, place)
    if not normalized(place.x) or not normalized(place.y) or not mapInfo(place.mapID)
        or (place.x == 0 and place.y == 0) then return end
    local now, oldest, count = GetTime(), nil, 0
    for previousKey, previous in pairs(sightings) do
        if previous.scope ~= place.scope or now - previous.at >= lifetime then
            sightings[previousKey] = nil
        elseif previousKey ~= key then
            count = count + 1
            if not oldest or previous.at < sightings[oldest].at then oldest = previousKey end
        end
    end
    if count >= 200 then sightings[oldest] = nil end
    place.at = now
    sightings[key] = place
    addon.RefreshSightingMap()
end

function addon.RecordLocalMapSighting(key, name, guild)
    if not C_Map or not C_Map.GetMapInfo then return end
    local inside = IsInInstance()
    if not addon.Ordinary(inside) or inside == true or inside == 1 then return end
    local place = { name = name, guild = guild, scope = addon.Scope() }
    place.mapID = addon.Location(place)
    store(localSightings, key, place)
end

function addon.RecordGuildMapSighting(key, name, guild, reporter, mapID, x, y)
    if not C_Map or not C_Map.GetMapInfo then return end
    local scope = addon.GuildScope()
    local previous = guildSightings[key]
    if previous and previous.scope == scope and GetTime() - previous.at < recordInterval then return end
    if scope then
        store(guildSightings, key, { name = name, guild = guild, scope = scope, reporter = reporter,
            mapID = mapID, x = x, y = y })
    end
end

GuildAvengerSightingPinMixin = {}

function GuildAvengerSightingPinMixin:OnLoad()
    self:UseFrameLevelType("PIN_FRAME_LEVEL_AREA_POI")
end

function GuildAvengerSightingPinMixin:OnAcquired(place, priority, x, y)
    self.place, self.priority = place, priority
    self.Icon:SetVertexColor(1, priority and 0.72 or 0.38, priority and 0.25 or 0.32)
    self:SetPosition(x, y)
end

function GuildAvengerSightingPinMixin:OnMouseEnter()
    local place = self.place
    if not place then return end
    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
    GameTooltip:SetText(L("mapSeenHere", place.name), 1, 0.82, 0)
    if place.guild then GameTooltip:AddLine(L("guildNameQuoted", place.guild), 1, 0.84, 0.69) end
    local zone = (mapInfo(place.mapID) or {}).name
    if addon.IsText(zone) then GameTooltip:AddLine(zone, 0.9, 0.9, 0.9) end
    local minutes = math.floor((GetTime() - place.at) / 60)
    local age = minutes > 0 and L("mapSeenMinutes", minutes) or L("mapSeenJustNow")
    GameTooltip:AddLine(place.reporter and L("mapSeenByGuildmate", place.reporter, age) or L("mapSeenByYou", age))
    GameTooltip:AddLine(L("mapSeenApproximate"), 0.8, 0.8, 0.8)
    GameTooltip:Show()
end

function GuildAvengerSightingPinMixin:OnMouseLeave()
    if GameTooltip:IsOwned(self) then GameTooltip:Hide() end
end

function GuildAvengerSightingPinMixin:OnReleased()
    self:OnMouseLeave()
    self.place = nil
    MapCanvasPinMixin.OnReleased(self)
end

local function collect(sightings, visible, scope, now, enabled)
    for key, place in pairs(sightings) do
        if place.scope ~= scope or now - place.at >= lifetime then
            sightings[key] = nil
        elseif enabled and (not visible[key] or visible[key].at < place.at) then
            visible[key] = place
        end
    end
end

local function refresh(self)
    local map = self:GetMap()
    local mapID = map:GetMapID()
    local visible, now = {}, GetTime()
    collect(localSightings, visible, addon.Scope(), now, true)
    collect(guildSightings, visible, addon.GuildScope(), now, addon.SightingSetting("receive"))
    for key, place in pairs(visible) do
        local entry = addon.ListedEntry(key, place.guild)
        local x, y
        if entry and validNumber(mapID) then x, y = project(place, mapID) end
        if x then
            local pin = self.pins[key]
            if not pin or pin.place ~= place or pin.priority ~= entry.high then
                if pin then map:RemovePin(pin) end
                self.pins[key] = map:AcquirePin(template, place, entry.high, x, y)
            end
        else
            visible[key] = nil
        end
    end
    for key, pin in pairs(self.pins) do
        if not visible[key] then
            map:RemovePin(pin)
            self.pins[key] = nil
        end
    end
end

function addon.RefreshSightingMap()
    if provider and provider:GetMap():IsShown() then refresh(provider) end
end

function addon.InitSightingMap()
    if provider or not WorldMapFrame or not WorldMapFrame.AddDataProvider or not MapCanvasDataProviderMixin or not MapCanvasPinMixin
        or not C_Map or not C_Map.GetMapInfo or not C_Map.GetMapRectOnMap then return end
    for name, method in pairs(MapCanvasPinMixin) do
        if GuildAvengerSightingPinMixin[name] == nil then GuildAvengerSightingPinMixin[name] = method end
    end
    provider = CreateFromMixins(MapCanvasDataProviderMixin)
    provider.pins = {}
    function provider:RemoveAllData()
        self:GetMap():RemoveAllPinsByTemplate(template)
        self.pins = {}
    end
    function provider:RefreshAllData()
        self:RemoveAllData()
        refresh(self)
    end
    function provider:OnShow()
        self.timer = self.timer or C_Timer.NewTicker(5, addon.RefreshSightingMap)
    end
    function provider:OnHide()
        if self.timer then self.timer:Cancel() end
        self.timer = nil
    end
    WorldMapFrame:AddDataProvider(provider)
    if WorldMapFrame:IsShown() then
        provider:OnShow()
        provider:RefreshAllData()
    end
end
