"""Run the watchlist suite and the gameplay and UI audit against the checkout's Lua."""

import os
import re
import runpy
import unittest
import xml.etree.ElementTree as ET
from datetime import datetime, timezone
from pathlib import Path
from zipfile import ZipFile


sharing = runpy.run_path(str(Path(__file__).with_name("test-watchlist-sharing.py")))
SharingTests = sharing["SharingTests"]
Wire = sharing["Wire"]
ADDON = sharing["ADDON"]
VERSION = re.search(r"^## Version: (\S+)", (ADDON / "GuildAvenger.toc").read_text(), re.M)[1]


class GameplayTests(unittest.TestCase):
    def setUp(self):
        self.world = Wire([("Anna Wolf", "enUS", VERSION), ("Bohdan Fox", "ukUA", VERSION)])
        self.a, self.b = self.world.players
        self.api = self.a.addon
        self.a.g.loadWorldMap()
        self.a.lua.execute("""
            local original = UnitGUID
            UnitGUID = function(unit)
                if unit == 'target' then return 'Player-1-FF' end
                if unit == 'pet' then return 'Pet-1-AB' end
                return original(unit)
            end
            notifications = {}
            UnitIsDeadOrGhost = function() return false end
            COMBATLOG_HONORGAIN_NO_RANK = '%s grants %d honor.'
            COMBATLOG_HONORAWARD = 'Awarded %d honor.'
            COMBATLOG_HONORGAIN = '%3$d honor for %1$s (%2$s).'
            bit = {band=function(a,b) return a == b and a or 0 end}
        """)
        self.api.ShowAlert = self.a.lua.eval("function(entry) table.insert(notifications, entry) end")

    def watch_both(self):
        person = self.a.add("Enemy Player", kind="P")
        guild = self.a.add("Enemy Guild")
        self.a.g.selectEnemy()
        return self.a.read(person), self.a.read(guild)

    def honor(self, text, line):
        self.a.g.fire("CHAT_MSG_COMBAT_HONOR_GAIN", text, *([None] * 9), line)

    def test_detection_priority_cooldown_and_retarget(self):
        person, guild = self.watch_both()
        self.api.SetPriority(guild, True)
        self.a.g.fire("UNIT_COMBAT", "target")
        self.assertEqual(len(self.a.g.notifications), 1)
        self.world.advance(31)
        self.a.g.fire("UNIT_COMBAT", "target")
        self.assertEqual(len(self.a.g.notifications), 1)
        self.api.SetPriority(person, True)
        self.a.g.fire("PLAYER_TARGET_CHANGED")
        self.assertEqual(len(self.a.g.notifications), 2)
        self.assertTrue(self.a.g.notifications[2].high)

    def test_deaths_count_character_and_guild_but_credit_only_own_or_pet_blow(self):
        person, guild = self.watch_both()
        for killer in [self.b.guid, self.a.guid, "Pet-1-AB"]:
            self.a.g.fire("UNIT_DIED", "Player-1-FF")
            self.a.g.fire("PARTY_KILL", killer, "Player-1-FF")
            self.a.g.fire("UNIT_DIED", "Player-1-FF")
            self.world.advance(2)
            self.a.g.fire("UNIT_HEALTH", "target")
        self.assertEqual((person.deaths, guild.deaths, self.api.StatsRows(4)[1].count), (3, 3, 2))

    def test_healer_honor_repeated_kills_and_unnamed_award(self):
        self.watch_both()
        self.honor("Enemy Player grants 23 honor.", 1)
        self.honor("Enemy Player grants 23 honor.", 1)
        self.honor("23 honor for Enemy Player (Scout).", 2)
        self.honor("Awarded 45 honor.", 3)
        self.honor("Other Player grants 9 honor.", 4)
        self.assertEqual(self.api.StatsRows(2)[1].count, 46)
        self.assertEqual(len(self.api.StatsRows(4)), 0)
        self.assertEqual([e.reason for e in self.api.StatsRows(5).values()],
                         ["honorNotWatched", "honorNoTarget", "honorBoth", "honorBoth"])

    def test_pve_fall_self_and_pvp_journal(self):
        for guid in ["Creature-1-AB", None, self.a.guid, "Player-1-FF"]:
            self.a.g.testGuid = guid
            self.a.lua.execute("""local at = GetTime()
                C_DeathRecap = {GetRecapEvents=function() return {{timestamp=at,overkill=0,
                    sourceGUID=testGuid,sourceFlags=64,sourceName='Enemy Player'}} end}""")
            self.a.g.fire("PLAYER_DEAD")
            self.a.g.fire("PLAYER_DEAD")
            self.world.advance(3)
            self.a.g.fire("PLAYER_ALIVE")
        self.assertEqual(len(self.api.StatsRows(1)), 1)
        self.assertEqual(self.api.StatsRows(1)[1].killerGUID, "Player-1-FF")
        self.assertEqual(self.api.StatsRows(3)[1].count, 1)

    def test_week_rollover_and_all_time(self):
        monday = int(datetime(2026, 11, 30, tzinfo=timezone.utc).timestamp())
        self.a.g.GetServerTime = lambda: monday - 1
        self.api.RecordHonor(20)
        self.api.RecordRevenge()
        self.a.g.GetServerTime = lambda: monday
        self.assertEqual(len(self.api.StatsRows(2, True)), 0)
        self.assertEqual(len(self.api.StatsRows(4, True)), 0)
        self.api.RecordHonor(3)
        self.assertEqual(self.api.StatsRows(2, True)[1].count, 3)
        self.assertEqual(self.api.StatsRows(2, False)[1].count, 23)

    def test_season_leader_targets_and_peer_score(self):
        self.a.add("Enemy Player", kind="P")
        self.assertFalse(self.b.addon.StartSeason()[0])
        self.assertTrue(self.api.StartSeason()[0])
        self.world.advance(5)
        self.assertEqual(len(self.b.addon.SeasonTargets()), 1)
        self.assertFalse(self.api.StartSeason()[0])
        self.assertTrue(self.b.addon.RecordSeasonHonor("enemy player", None, 25))
        self.b.addon.SetStatsSharing(True)
        self.world.advance(20)
        self.api.RequestSeason()
        self.world.advance(5)
        self.assertEqual(self.api.SeasonRows()[1].count, 25)

    def test_pending_name_verifies_in_the_field_and_allies_are_rejected(self):
        self.assertFalse(self.api.Add("Anna Wolf", "")[0])
        self.assertFalse(self.api.Add("Bohdan Fox", "")[0])
        self.assertFalse(self.api.Add("Test Guild", "", None, "G")[0])
        self.assertTrue(self.api.Add("Enemy Player", "First")[0])
        entry = self.a.read("enemy player")
        self.assertFalse(self.api.EligibleRecord("enemy player", entry))
        self.a.g.selectEnemy()
        self.assertTrue(self.api.EligibleRecord("enemy player", entry))
        self.assertEqual(entry.note, "First")

    def test_search_case_filter_and_single_removal(self):
        self.a.add("Northern Guild", "ЗАСІДКА", high=True)
        self.a.add("Hidden Player", "Інше", "P")
        self.api.ToggleUI()
        panel = self.a.g.GuildAvengerPanel
        panel.search.SetText(panel.search, "засідка")
        self.assertEqual(len(panel.entries), 1)
        self.assertEqual(panel.entries[1].name, "Northern Guild")
        self.a.click("GuildAvengerPanel", "remove")
        self.a.click("GuildAvengerDialog", "cancel")
        self.assertIsNotNone(self.a.read("guild:northern guild"))
        self.a.click("GuildAvengerPanel", "remove")
        self.a.click("GuildAvengerDialog", "remove")
        self.assertEqual(len(panel.entries), 0)
        self.assertIsNotNone(self.a.read("hidden player"))

    def test_all_localized_keys_format_and_toc_assets(self):
        locale = (ADDON / "GuildAvengerLocale.lua").read_text(encoding="utf-8")
        blocks = re.findall(r"(?:enUS|ukUA) = \{\n(.*?)\n    \},", locale, re.S)
        keys = [dict(re.findall(r'^        (\w+) = "(.*)",$', block, re.M)) for block in blocks]
        self.assertEqual(len(keys), 2)
        self.assertEqual(keys[0].keys(), keys[1].keys())
        for key, en in keys[0].items():
            self.assertEqual(re.findall(r"%[ds]", en), re.findall(r"%[ds]", keys[1][key]), key)
        for name in (ADDON / "GuildAvenger.toc").read_text().splitlines():
            if name and not name.startswith("#"):
                self.assertTrue((ADDON / name).is_file(), name)
        ET.parse(ADDON / "GuildAvengerMap.xml")
        self.assertEqual((ADDON / "Sounds" / "HighPriority.ogg").read_bytes()[:4], b"OggS")

    def test_inbox_can_finish_review_with_every_row_skipped(self):
        self.b.add("New Guild")
        self.b.addon.SetAutoReply(True)
        self.api.RequestWatchlists()
        self.world.advance(8)
        self.api.OpenPullInbox()
        self.a.click("GuildAvengerReview", "clearAll")
        review = self.a.g.GuildAvengerReview
        self.assertTrue(review.confirm.enabled, "No action to finish a review with zero selected")
        review.confirm.scripts.OnClick(review.confirm)
        self.assertEqual(self.api.InboxCount(), 0)
        self.assertIsNone(self.a.read("guild:new guild"))

    def test_local_priority_is_preserved_when_peer_only_changed_death_count(self):
        key = self.a.add("Test Enemy")
        self.b.add("Test Enemy")
        self.api.SetAutoSyncWatchlists(True)
        self.b.addon.SetAutoSyncWatchlists(True)
        self.world.advance(10)
        self.api.SetPriority(self.a.read(key), True)
        self.b.read(key).deaths = 1
        self.world.advance(3600)
        rows = list(self.api.PreviewInbox().changes.values())
        self.assertFalse(any(r.changedPriority for r in rows), "Unchanged remote priority offered as a downgrade")
        self.assertTrue(any(r.moreDeaths for r in rows))

    def test_readding_guild_withdraws_published_removal(self):
        key = self.a.add("Returned Guild")
        self.b.add("Returned Guild")
        self.assertTrue(self.api.Delete("Returned Guild", "G")[0])
        self.assertTrue(self.api.Publish(None, True)[0])
        self.world.flush()
        link = self.b.links("addon:GuildAvenger:")[0]
        self.assertTrue(self.api.Add("Returned Guild", "", None, "G")[0])
        self.b.g.clickLink(link)
        self.world.advance(5)
        review = self.b.g.GuildAvengerReview
        offered = review and review.offer and list(review.offer.changes.values()) or []
        self.assertFalse(any(r.removed and r.key == key for r in offered), "Retracted removal is still offered")

    def test_direct_share_with_late_roster_is_delivered_or_failure_is_reported(self):
        self.a.add("Sent Guild")
        self.b.g.rosterReady = False
        self.b.refresh_roster()
        self.assertTrue(self.api.Share(self.b.name)[0])
        self.world.advance(22)
        self.b.g.rosterReady = True
        self.b.refresh_roster()
        self.world.advance(90)
        self.assertEqual(self.b.g.GuildAvengerReview.offer.changes[1].record.name, "Sent Guild")
        self.assertTrue(any(self.a.text("transferDone", self.b.name) in line for line in self.a.g.chat.values()))
        self.assertFalse(any(self.a.text("transferUnconfirmed", self.b.name) in line for line in self.a.g.chat.values()))

    def test_missing_receipt_is_reported_without_claiming_delivery(self):
        self.a.add("Sent Guild")
        self.world.error = lambda player, msg: 1 if msg.startswith("Y\t") else None
        self.api.Share(self.b.name)
        self.world.advance(80)
        self.assertEqual(self.b.g.GuildAvengerReview.offer.changes[1].record.name, "Sent Guild")
        self.assertTrue(any(self.a.text("transferUnconfirmed", self.b.name) in line for line in self.a.g.chat.values()))
        self.assertFalse(any(self.a.text("transferDone", self.b.name) in line for line in self.a.g.chat.values()))

    @unittest.skipUnless(os.environ.get("GUILD_AVENGER_PREVIOUS_ZIP"), "requires the 3.4.5 release ZIP")
    def test_released_345_exchanges_lists_both_directions(self):
        with ZipFile(os.environ["GUILD_AVENGER_PREVIOUS_ZIP"]) as archive:
            toc = archive.read("GuildAvenger/GuildAvenger.toc").decode("utf-8")
            self.assertIn("## Version: 3.4.5", toc)
            old = {name: archive.read("GuildAvenger/" + name).decode("utf-8")
                   for name in toc.splitlines() if name.endswith(".lua")}
        wire = Wire([("Anna Wolf", "enUS", VERSION), ("Bohdan Fox", "ukUA", "3.4.5")], {"3.4.5": old})
        new, previous = wire.players
        for sender, recipient, name in ((new, previous, "First Guild"), (previous, new, "Second Guild")):
            key = sender.add(name, "Shared note", deaths=4)
            sender.addon.Share(recipient.name)
            wire.advance(8)
            recipient.click("GuildAvengerReview", "accept")
            self.assertEqual((recipient.read(key).note, recipient.read(key).deaths), ("Shared note", 4))
        wire.advance(75)
        self.assertTrue(any(new.text("transferUnconfirmed", previous.name) in line for line in new.g.chat.values()))

    def test_full_direct_queue_reports_busy_and_allows_resending(self):
        self.a.add("Sent Guild")
        for _ in range(12):
            self.assertTrue(self.api.Share(self.b.name)[0])
            self.world.advance(4)
        self.assertTrue(any(self.a.text("recipientQueueFull", self.b.name) in line for line in self.a.g.chat.values()))
        self.b.click("GuildAvengerReview", "decline")
        self.world.advance(1)
        self.api.Share(self.b.name)
        self.world.advance(5)
        self.assertIn(self.a.text("transferDone", self.b.name), list(self.a.g.chat.values())[-1])

    def test_settings_cancel_discards_sighting_consent(self):
        self.api.PromptSettings()
        window = self.a.g.GuildAvengerSettings
        label = self.a.text("sightingSend")
        check = next(c for c in window.children.values() if c.kind == "CheckButton"
                     and any(child.text == label for child in c.children.values()))
        check.SetChecked(check, True)
        check.scripts.OnClick(check)
        self.a.click("GuildAvengerSettings", "cancel")
        self.assertFalse(self.api.SightingSetting("send"), "Cancel kept permission to transmit the player's location")

    def test_sightings_only_transmit_after_apply(self):
        self.a.add("Enemy Player", kind="P")
        self.api.PromptSettings()
        window = self.a.g.GuildAvengerSettings
        check = next(c for c in window.children.values() if c.kind == "CheckButton"
                     and any(child.text == self.a.text("sightingSend") for child in c.children.values()))
        check.SetChecked(check, True)
        check.scripts.OnClick(check)
        self.a.g.selectEnemy()
        self.assertFalse(self.world.packets)
        self.a.click("GuildAvengerSettings", "applySettings")
        self.world.advance(65)
        self.a.g.selectEnemy()
        self.assertTrue(any(packet[2] == "GUILD" for packet in self.world.packets))

    def test_fallback_ukrainian_name_key_agrees_with_search(self):
        self.assertEqual(self.api.SearchLower("Ґрім"), self.api.SearchLower("ґрім"))
        same_key = self.a.lua.eval("function(addon) return addon.EntryName('Ґрім','G') == addon.EntryName('ґрім','G') end")
        self.assertTrue(same_key(self.api), "Different saved keys for the same guild")

    def test_legacy_cyrillic_collision_migrates_once_without_losing_counts_or_notes(self):
        key = self.a.add("ґрім", "First")
        db = self.a.g.GuildAvengerDB
        old_key = "guild:Ґрім"
        db.lists["42"][old_key] = self.a.lua.table(name="Ґрім", kind="G", note="Second", deaths=7, high=True)
        db.normalizedLists["42"] = None
        for _ in range(2):
            fresh = self.reload_client()
            entry = fresh.WatchlistRecord(key)
            self.assertEqual((entry.note, entry.deaths, entry.high), ("First / Second", 7, True))
            self.assertIsNone(fresh.WatchlistRecord(old_key))
            self.assertEqual(db.nameMigrationBackup["42"][old_key].note, "Second")

    def test_unreviewed_inbox_survives_reload_and_stays_in_its_guild(self):
        key = self.b.add("Retained Guild")
        self.b.addon.SetAutoReply(True)
        self.api.RequestWatchlists()
        self.world.advance(8)
        fresh = self.reload_client()
        self.assertEqual(fresh.InboxCount(), 1)
        self.a.g.club = 99
        self.a.g.fire("PLAYER_GUILD_UPDATE")
        self.a.refresh_roster()
        self.assertEqual(fresh.InboxCount(), 0)
        self.a.g.club = 42
        self.a.g.fire("PLAYER_GUILD_UPDATE")
        self.a.refresh_roster()
        fresh.OpenPullInbox()
        self.a.click("GuildAvengerReview", "accept")
        self.assertIsNotNone(fresh.WatchlistRecord(key))
        self.assertEqual(self.reload_client().InboxCount(), 0)

    def test_newly_online_guildmate_can_refresh_rankings(self):
        wire = Wire([("Anna Wolf", "enUS", VERSION), ("Bohdan Fox", "ukUA", VERSION),
                     ("Clara Deer", "enUS", VERSION)])
        first, scorer, late = wire.players
        late.online = False
        scorer.addon.RecordRevenge()
        scorer.addon.SetStatsSharing(True)
        wire.advance(4)
        first.addon.RequestStats()
        wire.advance(6)
        self.assertEqual(first.addon.StatsRows(4)[1].count, 1)
        late.online = True
        late.refresh_roster()
        self.assertEqual(late.addon.RequestStats(), late.text("statsRequestSent"))
        wire.advance(50)
        self.assertEqual(len(late.addon.StatsRows(4)), 1, "Earlier guild request suppressed the new member's reply")

    def test_active_large_automatic_transfer_finishes(self):
        for n in range(650):
            self.b.add("G" * 92 + f"{n:04d}", "ї" * 52, high=True)
        self.api.SetAutoSyncWatchlists(True)
        self.b.addon.SetAutoSyncWatchlists(True)
        self.world.advance(550)
        packets = [p for p in self.world.packets if p[0] == self.b.name and p[1].startswith(("R\t", "M\t", "N\t"))]
        self.assertGreater(packets[-1][4] - packets[0][4], 300)
        inbox = self.api.PreviewInbox()
        self.assertIsNotNone(inbox, "Active transfer discarded when the five-minute request expired")
        self.assertEqual(inbox.added, 650)

    def test_alert_preview_normal_high_and_builtin_override(self):
        self.a.lua.execute("""
            SOUNDKIT = {RAID_WARNING=1, RAID_BOSS_EMOTE_WARNING=2, READY_CHECK=3}
            played = {}
            PlaySound = function(id, channel) assert(channel == 'Master'); table.insert(played,id) end
            PlaySoundFile = function(path, channel) assert(channel == 'Master'); table.insert(played,path); return true end
        """)
        self.api.PromptSounds()
        win = self.a.g.GuildAvengerSounds
        preview = [c for c in win.children.values() if c.font and c.font.text == self.a.text("previewSound")]
        self.assertEqual(len(preview), 2)
        for button in preview:
            button.scripts.OnClick(button)
        self.assertEqual(self.a.g.played[1], 1)
        self.assertTrue(self.a.g.played[2].endswith("HighPriority.ogg"))
        self.a.g.GuildAvengerDB.sound.highSound = "READY_CHECK"
        preview[1].scripts.OnClick(preview[1])
        self.assertEqual(self.a.g.played[3], 3)

    def test_guild_only_healer_honor_uses_recent_sighting(self):
        self.a.add("Enemy Guild")
        self.a.g.selectEnemy()
        self.a.g.UnitIsPlayer = self.a.lua.eval("function() return false end")
        self.honor("Enemy Player grants 14 honor.", 1)
        self.world.advance(125)
        self.honor("Enemy Player grants 14 honor.", 2)
        self.assertEqual(self.api.StatsRows(2)[1].count, 14)
        self.assertEqual(self.api.StatsRows(5)[1].reason, "honorNotWatched")

    def test_bug_report_generates_copyable_url_without_submitting(self):
        from urllib.parse import parse_qs, urlsplit
        self.api.PromptBugReport()
        report = self.a.g.GuildAvengerBugReport
        note = "Не працює & 50%?\nДругий рядок"
        report.field.SetText(report.field, note)
        self.a.click("GuildAvengerBugReport", "send")
        parsed = urlsplit(self.a.g.GuildAvengerDownload.field.text)
        self.assertEqual((parsed.netloc, parsed.path), ("github.com", "/DunkleCthulhu/guild-avenger/issues/new"))
        self.assertIn(note, parse_qs(parsed.query)["body"][0])
        self.assertFalse(self.world.messages)

    def reload_client(self):
        self.a.lua.execute("eventFrame=nil; jobs={}")
        fresh = self.a.lua.table()
        for name, source in sharing["SOURCES"].items():
            self.a.lua.compile(source, name=name)("GuildAvenger", fresh)
        self.a.g.fire("ADDON_LOADED", "GuildAvenger")
        self.a.g.fire("PLAYER_ENTERING_WORLD")
        self.a.refresh_roster()
        return fresh

    def test_reload_preserves_watchlist_honor_and_character_preferences(self):
        self.watch_both()
        self.api.EditNote("Enemy Player", "Keep my note", "P")
        self.honor("Enemy Player grants 12 honor.", 1)
        self.api.SetSightingSetting("receive", True)
        fresh = self.reload_client()
        self.assertEqual(fresh.WatchlistRecord("enemy player").note, "Keep my note")
        self.assertEqual(fresh.StatsRows(2)[1].count, 12)
        self.assertTrue(fresh.SightingSetting("receive"))
        self.a.g.club = 99
        self.a.g.fire("PLAYER_GUILD_UPDATE")
        self.a.refresh_roster()
        self.assertIsNone(fresh.WatchlistRecord("enemy player"))
        self.assertFalse(fresh.SightingSetting("receive"))
        self.assertEqual(len(fresh.StatsRows(2)), 0)

    def test_character_sighting_is_filtered_when_target_in_party_or_friendly(self):
        self.a.add("Enemy Player", kind="P")
        self.a.g.selectEnemy()
        self.assertEqual(len(self.a.g.notifications), 1)
        self.world.advance(31)
        self.a.g.UnitInParty = self.a.lua.eval("function(u) return u == 'target' end")
        self.a.g.fire("PLAYER_TARGET_CHANGED")
        self.assertEqual(len(self.a.g.notifications), 1)
        self.a.g.UnitInParty = self.a.lua.eval("function() return false end")
        self.a.g.UnitFactionGroup = self.a.lua.eval("function() return 'Horde' end")
        self.a.g.fire("PLAYER_TARGET_CHANGED")
        self.assertEqual(len(self.a.g.notifications), 1)

    def test_guildmate_receives_attacker_count_only_with_separate_consent(self):
        self.a.g.C_DeathRecap = self.a.lua.eval("""{GetRecapEvents=function() return {{timestamp=GetTime(),
            overkill=0,sourceGUID='Player-1-FF',sourceFlags=64,sourceName='Enemy Player'}} end}""")
        self.a.g.fire("PLAYER_DEAD")
        self.world.advance(3)
        self.api.SetStatsSharing(True)
        self.world.advance(5)
        self.assertEqual(len(self.b.addon.StatsRows(3)), 0)
        self.api.SetAttackerSharing(True)
        self.b.addon.RequestStats()
        self.world.advance(7)
        self.assertEqual(self.b.addon.StatsRows(3)[1].name, "Enemy Player")
        self.assertEqual(self.b.addon.StatsRows(3)[1].count, 1)

    def test_continuously_observed_enemy_keeps_its_local_map_marker(self):
        self.watch_both()
        world_map = self.a.g.WorldMapFrame
        world_map.Show(world_map)
        for _ in range(31):
            self.world.advance(30)
            self.a.g.fire("UNIT_COMBAT", "target")
        self.assertEqual(len(self.a.g.notifications), 1, "Repeated observations should stay quiet")
        self.assertEqual(self.a.read("enemy player").seen.at, self.a.g.GetServerTime())
        self.assertIsNotNone(world_map.pins["Enemy Player"], "A visible, repeatedly observed target lost its marker")

    def test_stationary_visible_target_refreshes_and_then_expires_out_of_sight(self):
        self.a.lua.execute("UnitIsVisible = function(unit) return unit == 'target' and visibleTarget end; visibleTarget = true")
        self.watch_both()
        world_map = self.a.g.WorldMapFrame
        world_map.Show(world_map)
        self.world.advance(940)
        self.assertIsNotNone(world_map.pins["Enemy Player"])
        self.assertEqual(len(self.a.g.notifications), 1)
        self.a.g.visibleTarget = False
        self.world.advance(940)
        self.api.RefreshSightingMap()
        self.assertIsNone(world_map.pins["Enemy Player"])


if __name__ == "__main__":
    unittest.main(verbosity=2)
