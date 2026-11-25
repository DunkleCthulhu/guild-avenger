"""Run from the repository checkout with Python and lupa installed."""

from collections import deque
from pathlib import Path
import unittest

from lupa.lua51 import LuaRuntime


ADDON = Path(__file__).resolve().parents[1] / "GuildAvenger"
SOURCES = {
    name: (ADDON / name).read_text(encoding="utf-8")
    for name in (ADDON / "GuildAvenger.toc").read_text(encoding="utf-8").splitlines()
    if name.endswith(".lua")
}
PREFIX = "GuildAvenger2"

WOW = r"""
local function noop() end
local function run(frame, event, ...)
    local script = frame.scripts[event]
    if script then script(frame, ...) end
    local hook = frame.hooks[event]
    if hook then hook(frame, ...) end
end
local methods = {}
local topLevel = 0
local function widget(kind, name, parent)
    local frame = setmetatable({
        kind=kind, scripts={}, hooks={}, shown=true, enabled=true, text="", value=0, children={}
    }, {__index=methods})
    if name then _G[name] = frame end
    if parent then table.insert(parent.children, frame) end
    return frame
end
function CreateFrame(kind, name, parent) return widget(kind, name, parent) end
function methods:SetScript(event, script) self.scripts[event] = script end
function methods:HookScript(event, script) self.hooks[event] = script end
function methods:CreateTexture(_, _, _, depth)
    local texture = widget("Texture", nil, self)
    texture.depth = depth
    return texture
end
function methods:SetColorTexture(_, _, _, alpha) self.alpha = alpha end
function methods:SetFrameStrata(strata) self.strata = strata end
function methods:SetMovable(movable) self.movable = movable end
function methods:SetToplevel(toplevel) self.toplevel = toplevel end
function methods:Raise()
    topLevel = topLevel + 1
    self.level = topLevel
end
function methods:RegisterForDrag(button) self.dragButton = button end
function methods:StartMoving()
    assert(self.movable)
    self.moving = true
end
function methods:StopMovingOrSizing() self.moving = false end
function methods:SetupMenu(generator) self.menuGenerator = generator end
function methods:GenerateMenu()
    self.menu = {}
    self.menuGenerator(self, {CreateRadio=function(_, text, _, select, value)
        self.menu[text] = function() select(value) end
    end})
end
function methods:CreateFontString() return widget("FontString", nil, self) end
function methods:GetFontString()
    if not self.font then self.font = self:CreateFontString() end
    return self.font
end
function methods:SetText(text)
    self.text = text
    if self.kind == "Button" then self:GetFontString():SetText(text) end
    if self.kind == "EditBox" then run(self, "OnTextChanged") end
end
function methods:GetText() return self.text end
function methods:IsShown() return self.shown end
function methods:SetShown(shown)
    if self.shown == shown then return end
    self.shown = shown
    run(self, shown and "OnShow" or "OnHide")
end
function methods:Show() self:SetShown(true) end
function methods:Hide() self:SetShown(false) end
function methods:SetEnabled(enabled) self.enabled = enabled end
function methods:SetChecked(checked) self.checked = checked end
function methods:GetChecked() return self.checked end
function methods:SetValue(value)
    if self.value == value then return end
    self.value = value
    run(self, "OnValueChanged", value)
end
function methods:GetValue() return self.value end
function methods:SetID(id) self.id = id end
function methods:GetID() return self.id end
for name in ([[
    SetPoint SetSize SetTextColor SetWidth SetHeight SetMaxLines SetJustifyH SetJustifyV
    SetWordWrap SetNonSpaceWrap SetAlpha SetFontObject SetAutoFocus SetMaxBytes SetTextInsets EnableMouse
    ClearFocus SetBackdrop SetClampedToScreen RegisterEvent SetFrameLevel SetMouseClickEnabled
    SetTexture SetTexCoord SetNormalTexture SetPressedTexture SetHighlightTexture SetAllPoints
    SetOrientation SetValueStep SetObeyStepOnDrag SetMinMaxValues SetThumbTexture EnableMouseWheel
    SetFocus HighlightText SetMultiLine SetScrollChild ClearAllPoints
]]):gmatch("%S+") do methods[name] = noop end
local function findButton(frame, text)
    if not frame:IsShown() then return end
    if frame.scripts.OnClick and frame.font and frame.font.text == text then return frame end
    for _, child in ipairs(frame.children) do
        local found = findButton(child, text)
        if found then return found end
    end
end
function clickButton(window, text)
    local button = assert(findButton(assert(_G[window]), text), text)
    assert(button.enabled, text .. " is disabled")
    return run(button, "OnClick")
end
function hasButton(window, text)
    return _G[window] and findButton(_G[window], text) ~= nil
end
UIParent = widget("Frame")
UISpecialFrames, SlashCmdList, PanelTemplates_SetNumTabs, PanelTemplates_SetTab = {}, {}, noop, noop
ScrollingEdit_OnLoad, ScrollingEdit_OnCursorChanged, ScrollingEdit_OnTextChanged = noop, noop, noop
tinsert, date = table.insert, os.date
local blank = function() return false end
GetTime = function() return mockTime end
GetServerTime = function() return 1700000000 + math.floor(mockTime) end
GetLocale = function() return language end
GetNormalizedRealmName = function() return "Forever" end
UnitName = function(unit) if unit == "player" then return own.name end end
UnitGUID = function(unit) if unit == "player" then return own.guid end end
UnitFactionGroup = function() return "Horde" end
UnitIsPlayer, UnitCanAttack, UnitIsInMyGuild, IsInRaid = blank, blank, blank, blank
GetNumGroupMembers = function() return 0 end
GetNumSubgroupMembers = GetNumGroupMembers
GetGuildInfo = function(unit) if unit == "player" and club then return "Test Guild" end end
IsInGuild = function() return club ~= nil end
GetNumGuildMembers = function() return rosterReady and #roster or 0 end
function GetGuildRosterInfo(index)
    local member = rosterReady and roster[index]
    if member then
        local online = rosterOnline and member.online
        return member.address,nil,index-1,nil,nil,nil,nil,nil,online,nil,nil,nil,nil,nil,nil,nil,member.guid
    end
end
C_AddOns = { GetAddOnMetadata=function() return version end }
C_Club = { GetGuildClubId=function() return club end }
C_GuildInfo = { GuildRoster=noop }
Enum = { SendAddonMessageResult={Success=0, AddOnMessageLockdown=1, AddonMessageThrottle=2, ChannelThrottle=3} }
C_ChatInfo = { RegisterAddonMessagePrefix=noop, SendAddonMessage=sendAddon, SendChatMessage=sendChat }
local callbacks = {}
EventRegistry = { RegisterCallback=function(_,name,callback) callbacks[name]=callback end }
function clickLink(link, button)
    local callback = callbacks["ChatFrame.OnHyperlinkClick"]
    if callback then callback({}, DEFAULT_CHAT_FRAME, link, "", button or "LeftButton") end
end
ChatFrameUtil = { AddMessageEventFilter=function(_,filter) guildFilter=filter end }
function receiveChat(message, sender)
    local skip, replacement = guildFilter(DEFAULT_CHAT_FRAME, "CHAT_MSG_GUILD", message, sender)
    if not skip then table.insert(chat, replacement or message) end
end
chat, notices, jobs = {}, {}, {}
DEFAULT_CHAT_FRAME = { AddMessage=function(_,text) table.insert(chat,text) end }
UIErrorsFrame = { AddMessage=function(_,text) table.insert(notices,text) end }
C_Timer = {
    After=function(delay, callback) table.insert(jobs, {due=mockTime+delay, callback=callback}) end,
    NewTicker=function(seconds, callback)
        -- Only run the transfer timer. Patrol and statistics timers are outside these tests.
        local ticker = {due=mockTime+seconds, interval=seconds, callback=callback, Cancel=function(self) self.cancelled=true end}
        if seconds == 0.25 then table.insert(jobs, ticker) end
        return ticker
    end
}
function tick()
    for index=#jobs,1,-1 do
        local job = jobs[index]
        if job.cancelled then
            table.remove(jobs, index)
        elseif mockTime >= job.due then
            if job.interval then job.due = mockTime + job.interval else table.remove(jobs, index) end
            job.callback()
        end
    end
end
local originalCreate = CreateFrame
function CreateFrame(...)
    local frame = originalCreate(...)
    if not eventFrame then eventFrame = frame end
    return frame
end
function fire(event, ...) return run(eventFrame, "OnEvent", event, ...) end
"""


class Client:
    def __init__(self, wire, name, index, language, version):
        self.wire = wire
        self.name = name
        self.address = name + "-Layer42"
        self.guid = f"Player-1-AA{index}"
        self.online = True
        self.lua = LuaRuntime(unpack_returned_tuples=True)
        self.g = self.lua.globals()
        self.g.own = self.member()
        self.g.sendAddon = self.send_addon
        self.g.sendChat = lambda msg, channel: wire.send(self, None, msg, channel, None)
        self.g.club, self.g.mockTime, self.g.version = 42, wire.time, version
        self.g.rosterReady, self.g.rosterOnline, self.g.language = True, True, language
        self.g.GuildAvengerDB = self.lua.table(language=language)
        self.lua.execute(WOW, name="WoW API harness")
        self.addon = self.lua.table()
        for name, source in SOURCES.items():
            self.lua.compile(source, name=name)("GuildAvenger", self.addon)

    def member(self):
        return self.lua.table(name=self.name, address=self.address, guid=self.guid, online=self.online)

    def refresh_roster(self):
        self.g.roster = self.lua.table_from([
            self.lua.table(address=player.address, guid=player.guid, online=player.online)
            for player in self.wire.players if player.g.club == self.g.club
        ])
        self.g.fire("GUILD_ROSTER_UPDATE")

    def send_addon(self, prefix, msg, channel, address=None):
        return self.wire.send(self, prefix, msg, channel, address)

    def add(self, name, note="", kind="G", deaths=0, high=False):
        key = self.addon.EntryName(name, kind)[0]
        notes = self.g.GuildAvengerDB.lists[str(self.g.club)]
        notes[key] = self.lua.table(
            name=name, note=note, kind=kind, deaths=deaths, author=self.name,
            faction="Alliance" if kind == "P" else None, high=high or None, addedAt=1700000000,
        )
        return key

    def read(self, key):
        return self.addon.WatchlistRecord(key)

    def text(self, key, *args):
        return self.addon.Text(key, *args)

    def click(self, window, key, *args):
        return self.g.clickButton(window, self.text(key, *args))

    def links(self, marker):
        return [
            text.split("|H", 1)[1].split("|h", 1)[0]
            for text in self.g.chat.values() if "|H" + marker in text
        ]


class Wire:
    def __init__(self, members):
        self.time = 100
        self.packets, self.pending, self.messages = [], deque(), []
        self.error = None
        self.bare_guild_sender = False
        self.players = [Client(self, name, index, language, version)
                        for index, (name, language, version) in enumerate(members)]
        for player in self.players:
            player.g.fire("ADDON_LOADED", "GuildAvenger")
            player.g.fire("PLAYER_ENTERING_WORLD")
            player.refresh_roster()

    def send(self, sender, prefix, msg, channel, address):
        if prefix and self.error:
            err = self.error(sender, msg)
            if err:
                return err
        if prefix == PREFIX:
            assert len(msg.encode()) <= 240
            self.packets.append((sender.name, msg, channel, address, self.time))
        if prefix is None:
            assert len(msg.encode()) <= 255
            self.messages.append(msg)
        self.pending.append((sender, prefix, msg, channel, address))
        return 0

    def flush(self):
        while self.pending:
            sender, prefix, msg, channel, address = self.pending.popleft()
            for receiver in self.players:
                if not receiver.online:
                    continue
                addressed = (channel == "GUILD" and receiver.g.club == sender.g.club
                             or channel == "WHISPER" and receiver.address == address)
                if addressed:
                    display = sender.name if self.bare_guild_sender and channel == "GUILD" else sender.address
                    if prefix is None:
                        receiver.g.receiveChat(msg, display)
                    else:
                        receiver.g.fire("CHAT_MSG_ADDON", prefix, msg, channel, display)

    def advance(self, seconds):
        self.flush()
        for _ in range(round(seconds * 4)):
            self.time += 0.25
            for player in self.players:
                player.g.mockTime = self.time
                player.g.tick()
            self.flush()


class SharingTests(unittest.TestCase):
    def setUp(self):
        self.wire = Wire([("Anna Wolf", "enUS", "3.4.2"), ("Bohdan Fox", "ukUA", "3.4.2"),
                          ("Clara Deer", "enUS", "3.4.2")])
        self.anna, self.bohdan, self.clara = self.wire.players

    def check_draggable_window(self, window, strata="FULLSCREEN_DIALOG", hide_while_dragging=False):
        self.assertTrue(window.IsShown(window))
        self.assertEqual(window.strata, strata)
        self.assertTrue(window.toplevel)
        self.assertTrue(any(child.depth == -8 and child.alpha == 1 for child in window.children.values()))
        (header,) = (child for child in window.children.values() if child.scripts.OnDragStart)
        self.assertEqual(header.dragButton, "LeftButton")
        header.scripts.OnDragStart(header)
        self.assertTrue(window.moving)
        if hide_while_dragging:
            window.Hide(window)
        else:
            header.scripts.OnDragStop(header)
        self.assertFalse(window.moving)

    def test_windows_drag_and_layer_above_the_window_that_opened_them(self):
        addon, frames = self.anna.addon, self.anna.g
        addon.ToggleUI()
        panel = frames.GuildAvengerPanel
        self.check_draggable_window(panel, "DIALOG")
        self.anna.click("GuildAvengerPanel", "watchlistRequestsButton", 0)
        requests = frames.GuildAvengerRequests
        self.check_draggable_window(requests)
        self.anna.click("GuildAvengerPanel", "statistics")
        self.check_draggable_window(frames.GuildAvengerStats)
        self.assertGreater(frames.GuildAvengerStats.level, requests.level)
        addon.OpenWatchlistRequests()
        self.assertGreater(requests.level, frames.GuildAvengerStats.level)
        self.check_draggable_window(requests, hide_while_dragging=True)
        self.anna.click("GuildAvengerPanel", "sounds")
        self.check_draggable_window(frames.GuildAvengerSounds)
        self.anna.click("GuildAvengerPanel", "shareWatchlist")
        self.check_draggable_window(frames.GuildAvengerDialog, hide_while_dragging=True)

    def test_nested_settings_and_report_windows_open_in_front(self):
        addon, frames = self.anna.addon, self.anna.g
        addon.PromptSettings()
        settings = frames.GuildAvengerSettings
        self.check_draggable_window(settings)
        language = next(child for child in settings.children.values()
                        if child.kind == "DropdownButton" and child.menu[self.anna.text("languageUkrainian")])
        language.menu[self.anna.text("languageUkrainian")]()
        self.anna.click("GuildAvengerSettings", "applySettings")
        comment = frames.GuildAvengerComment
        self.assertGreater(comment.level, settings.level)
        self.check_draggable_window(comment, hide_while_dragging=True)
        self.anna.click("GuildAvengerSettings", "reportBug")
        report = frames.GuildAvengerBugReport
        self.assertGreater(report.level, settings.level)
        self.check_draggable_window(report)
        report.field.SetText(report.field, "Test")
        self.anna.click("GuildAvengerBugReport", "send")
        link = frames.GuildAvengerDownload
        self.assertGreater(link.level, report.level)
        self.check_draggable_window(link)

    def test_requests_badge_chat_click_and_selective_import(self):
        self.wire.bare_guild_sender = True
        self.bohdan.g.rosterOnline = False
        self.bohdan.g.rosterReady = False
        self.bohdan.refresh_roster()
        hero = self.bohdan.add("Enemy Player", "Кемпер", "P", 5, True)
        guild = self.bohdan.add("Enemy Guild", "Пріоритет")
        self.anna.addon.ToggleUI()
        self.anna.click("GuildAvengerPanel", "watchlistRequestsButton", 0)
        self.anna.click("GuildAvengerRequests", "requestWatchlists")
        self.wire.flush()
        self.assertEqual(len(self.bohdan.g.notices), 0)
        self.bohdan.g.rosterReady = True
        self.bohdan.refresh_roster()
        self.assertIn("Anna Wolf", self.bohdan.g.notices[1])
        self.assertIn("Запити", self.bohdan.g.notices[1])
        self.bohdan.addon.ToggleUI()
        self.assertTrue(self.bohdan.g.hasButton("GuildAvengerPanel", "Запити (1)"))
        link = self.bohdan.links("addon:GuildAvengerPull:")[0]
        self.bohdan.g.clickLink(link, "RightButton")
        self.assertIsNone(self.bohdan.g.GuildAvengerRequests)
        self.bohdan.g.clickLink(link)
        self.assertTrue(self.bohdan.g.hasButton("GuildAvengerRequests", "Надіслати список"))
        self.assertEqual(len(self.wire.packets), 1, "Opening the request must not send the list")
        self.bohdan.click("GuildAvengerRequests", "sendMyWatchlist")
        self.assertTrue(self.bohdan.g.hasButton("GuildAvengerRequests", "Надсилання…"))
        self.wire.advance(5)
        self.assertEqual(self.anna.addon.InboxCount(), 1)
        self.assertEqual(self.clara.addon.InboxCount(), 0)
        self.assertIsNone(self.anna.read(hero))
        self.anna.click("GuildAvengerRequests", "inboxButton", 1)
        review = self.anna.g.GuildAvengerReview
        self.check_draggable_window(review)
        self.assertGreater(review.level, self.anna.g.GuildAvengerRequests.level)
        for row in review.rows.values():
            if row.change and row.change.key == guild:
                row.check.SetChecked(row.check, False)
                row.check.scripts.OnClick(row.check)
        self.anna.click("GuildAvengerReview", "accept")
        self.assertEqual(self.anna.read(hero).note, "Кемпер")
        self.assertEqual(self.anna.read(hero).deaths, 5)
        self.assertTrue(self.anna.read(hero).high)
        self.assertIsNone(self.anna.read(guild))
        self.assertEqual(self.anna.addon.InboxCount(), 0)

    def test_multiple_replies_merge_and_later_reply_stays_in_inbox(self):
        key = self.bohdan.add("Enemy Guild", "First note", deaths=2)
        self.clara.add("Enemy Guild", "Second note", deaths=7, high=True)
        self.assertTrue(self.anna.addon.RequestWatchlists()[0])
        self.wire.flush()
        reply = self.bohdan.addon.WatchlistRequests()[1]
        self.bohdan.addon.ReplyToWatchlistRequest(reply.sender, reply.id)
        self.wire.advance(4)
        older = self.anna.addon.PreviewInbox()
        reply = self.clara.addon.WatchlistRequests()[1]
        self.clara.addon.ReplyToWatchlistRequest(reply.sender, reply.id)
        self.wire.advance(4)
        merged = self.anna.addon.PreviewInbox()
        self.assertEqual(merged.replyCount, 2)
        self.assertEqual(len(merged.changes), 1)
        self.assertEqual(merged.changes[1].record.deaths, 7)
        self.assertEqual(len(merged.changes[1].variants), 2)
        older.accept(self.anna.lua.table_from({key: older.changes[1].record}))
        self.assertEqual(self.anna.read(key).deaths, 2)
        self.assertEqual(self.anna.addon.InboxCount(), 1)

    def test_throttle_retry_and_empty_reply(self):
        self.anna.addon.RequestWatchlists()
        self.assertFalse(self.anna.addon.RequestWatchlists()[0])
        self.wire.flush()
        reply = self.bohdan.addon.WatchlistRequests()[1]
        self.wire.error = lambda sender, msg: 2 if msg.startswith("B\t") else None
        self.bohdan.addon.ReplyToWatchlistRequest(reply.sender, reply.id)
        self.wire.advance(49)
        self.assertEqual(self.anna.addon.InboxCount(), 0)
        self.assertFalse(self.bohdan.addon.WatchlistRequests()[1].sending)
        self.wire.error = None
        self.assertTrue(self.bohdan.addon.ReplyToWatchlistRequest(reply.sender, reply.id)[0])
        self.wire.advance(4)
        preview = self.anna.addon.PreviewInbox()
        self.assertEqual(preview.replyCount, 1)
        self.assertEqual(len(preview.changes), 0)
        self.anna.addon.OpenPullInbox()
        self.anna.click("GuildAvengerReview", "done")
        self.assertEqual(self.anna.addon.InboxCount(), 0)

    def test_dismiss_expiry_and_opt_in(self):
        self.bohdan.add("Enemy Guild")
        self.bohdan.addon.SetAutoReply(True)
        self.anna.addon.RequestWatchlists()
        self.wire.flush()
        self.bohdan.addon.SetAutoReply(False)
        self.wire.advance(4)
        reply = self.bohdan.addon.WatchlistRequests()[1]
        self.assertTrue(self.bohdan.addon.DismissWatchlistRequest(reply.sender, reply.id)[0])
        self.assertFalse(self.bohdan.addon.ReplyToWatchlistRequest(reply.sender, reply.id)[0])
        self.assertEqual(len(self.bohdan.addon.WatchlistRequests()), 0)
        self.bohdan.addon.SetAutoReply(True)
        self.wire.advance(61)
        self.anna.addon.RequestWatchlists()
        self.wire.advance(8)
        self.assertEqual(self.anna.addon.InboxCount(), 1)
        self.assertEqual(len(self.bohdan.g.notices), 1, "Only the manual prompt needed a notification")
        self.wire.advance(301)
        self.assertEqual(len(self.clara.addon.WatchlistRequests()), 0)

    def test_guild_chat_share_and_direct_share(self):
        key = self.anna.add("Enemy Guild")
        self.wire.bare_guild_sender = True
        self.assertTrue(self.anna.addon.Publish(None, False)[0])
        self.wire.flush()
        self.assertIn("[Guild Avenger ", self.wire.messages[0])
        link = self.bohdan.links("addon:GuildAvenger:")[0]
        self.bohdan.g.clickLink(link)
        self.wire.advance(5)
        self.assertTrue(self.bohdan.g.hasButton("GuildAvengerReview", self.bohdan.text("accept")))
        self.bohdan.click("GuildAvengerReview", "decline")
        self.assertIsNone(self.bohdan.read(key))
        self.assertTrue(self.anna.addon.Share("Clara Deer", None, False)[0])
        self.wire.advance(5)
        self.clara.click("GuildAvengerReview", "accept")
        self.assertIsNotNone(self.clara.read(key))
        self.assertIsNone(self.bohdan.read(key))
        for sender, message, channel, address, _ in self.wire.packets:
            self.assertEqual(channel, "WHISPER")
            self.assertIn(address, [player.address for player in self.wire.players])

    def test_invalid_packets_and_guild_membership_change(self):
        self.anna.addon.RequestWatchlists()
        self.wire.flush()
        for name, channel in [("Outsider Name-Layer42", "GUILD"), ("Bohdan Fox-WrongLayer", "GUILD"),
                              (self.bohdan.address, "WHISPER")]:
            self.anna.g.fire("CHAT_MSG_ADDON", PREFIX, "P\tabc.1", channel, name)
        self.assertEqual(len(self.anna.addon.WatchlistRequests()), 0)
        reply = self.bohdan.addon.WatchlistRequests()[1]
        self.anna.g.club = 99
        self.bohdan.refresh_roster()
        self.assertFalse(self.bohdan.addon.ReplyToWatchlistRequest(reply.sender, reply.id)[0])
        self.assertEqual(self.anna.addon.InboxCount(), 0)

    def test_large_list_resumes_after_short_throttle(self):
        self.bohdan.add("Long" * 24, "ї" * 52, deaths=9, high=True)
        for index in range(75):
            self.bohdan.add(f"Enemy Guild {index}")
        self.anna.addon.RequestWatchlists()
        self.wire.flush()
        reply = self.bohdan.addon.WatchlistRequests()[1]
        self.bohdan.addon.ReplyToWatchlistRequest(reply.sender, reply.id)
        self.wire.error = lambda sender, msg: 3 if msg.startswith("M\t") else None
        self.wire.advance(5)
        self.assertEqual(self.anna.addon.InboxCount(), 0)
        self.wire.error = None
        self.wire.advance(40)
        self.assertEqual(self.anna.addon.PreviewInbox().added, 76)
        sent = [(msg, at) for sender, msg, _, _, at in self.wire.packets
                if sender == self.bohdan.name and msg[:2] in ("B\t", "V\t", "M\t", "R\t", "N\t", "H\t")]
        self.assertTrue(any(msg.startswith("M\t") for msg, _ in sent))
        self.assertTrue(any(msg.startswith("R\t") for msg, _ in sent))
        self.assertTrue(all(next_at - at >= 0.25 for (_, at), (_, next_at) in zip(sent, sent[1:])))

    def test_legacy_transfer_without_capability_response(self):
        key = self.bohdan.add("Enemy Player", "Legacy format", "P", 3, True)
        self.anna.addon.RequestWatchlists()
        self.wire.flush()
        reply = self.bohdan.addon.WatchlistRequests()[1]
        self.wire.error = lambda sender, msg: 1 if msg.startswith("C\t") else None
        self.bohdan.addon.ReplyToWatchlistRequest(reply.sender, reply.id)
        self.wire.advance(8)
        preview = self.anna.addon.PreviewInbox()
        self.assertIsNotNone(preview)
        self.assertEqual(preview.changes[1].record.note, "Legacy format")
        self.assertTrue(preview.changes[1].record.high)
        self.assertFalse(any(msg.startswith("M\t") for _, msg, _, _, _ in self.wire.packets))
        preview.accept(self.anna.lua.table_from({key: preview.changes[1].record}))
        self.assertEqual(self.anna.read(key).deaths, 3)


if __name__ == "__main__":
    unittest.main(verbosity=2)
