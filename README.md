# Guild Avenger

**English** · [Українська](README.uk.md)

Guild Avenger is a free, open-source PvP addon by the **False Memory** guild for **World of Warcraft: Forever 1.60.1**. Keep a watchlist of enemy characters and guilds, get alerts when you encounter them, and share entries and optional PvP statistics with guildmates.

**Authors** · `Dunkle_Cthulhu`, `ne_multik`, `marakesz`.

## Reporting a bug

Open **Settings → Report a bug**, describe what happened, and click **Send**. Copy the link into your browser to review and submit the public report on GitHub. The draft contains your comment and the addon version. [Guild Avenger Issues](https://github.com/DunkleCthulhu/guild-avenger/issues)

## Installation

Extract the Guild Avenger release ZIP into `World of Warcraft/_forever_/Interface/AddOns/`. The addon appears in the addon menu as **Guild Avenger**. Type `/gavenger` or click the book icon beside the minimap. Drag the icon to move it around the minimap. [GitHub releases](https://github.com/DunkleCthulhu/guild-avenger/releases)

Drag an addon window by its title bar. Requests, settings, and other dialogs open in front of the main watchlist.

### Interface language

Open **Settings** (**Налаштування**) in the watchlist or type `/gavenger settings`. Choose English or Ukrainian, click **Apply** (**Застосувати**), then type `/reload` in the WoW chat to update all addon windows. Your choice is saved between sessions.

### Migrating from GrudgeBook or Forever Watch

Close WoW, install Guild Avenger, and run the migration script from this repository on Windows. Replace the example path with your `_forever_` folder.

```powershell
./scripts/Migrate-GuildAvenger.ps1 -ClientRoot 'C:/Program Files (x86)/World of Warcraft/_forever_'
```

The script migrates data from earlier versions of this project. It copies your lists, statistics, and settings into a separate `GuildAvenger.lua` SavedVariables file, then moves the old addon and its data files to `GuildAvengerMigrationBackup`. Add `-WhatIf` to preview the changes. Run the migration before you first launch Guild Avenger.

## Detection and death counts

- Guild Avenger alerts you about characters on your watchlist and members of listed guilds when you target them, mouse over them, see an available nameplate, or receive a readable `UNIT_COMBAT` event. Combat events from an enemy you already see as your target, mouseover, focus, or nameplate do not repeat the alert. Targeting the enemy again does. The alert shows their portrait, name, note, and high-priority indicator. If this enemy is in your death journal, the alert starts with how many times they killed you and when they last did. The name and note also appear in chat. Alerts for the same enemy have a 30-second cooldown.
- By default, normal-priority alerts use the raid warning sound and high-priority alerts play a distinct ascending four-note sound. Open `/gavenger` and click **Звуки…** to select and preview built-in WoW sounds for each priority. You can mute character or guild matches separately, or play sounds for high-priority matches only. When a character and their guild both match, the character entry controls the priority, note, and sound settings.
- The alert appears near the top of the screen in a semi-transparent WoW-style frame. High-priority alerts have a gold border. Drag the alert with the left mouse button to move it. Its position is saved between sessions. The alert stays for 12 seconds by default. Choose 6, 12, 20, or 30 seconds in **Settings** (**Налаштування**), where you can also hide the minimap button. Use `/gavenger test` and `/gavenger test high` to preview the two styles.
- When several enemies from the same guild are spotted together and match only a normal-priority guild entry, they share one alert. A high-priority alert keeps its own portrait and target controls.
- The **Target** (**У ціль**) and **Danger Ping** (**Пінг небезпеки**) buttons are available outside combat. The ping button appears when the enemy from the alert is your current target and WoW pings are enabled. Click it to send a built-in danger ping on that target.
- The death counter uses available `PARTY_KILL` and `UNIT_DIED` events and counts duplicate reports of the same death once. A listed guild member's death increases the guild total. If the character also has an individual entry, their counter increases too. WoW must provide a readable identifier, and the addon must recognize the character or guild. Forever reserves `COMBAT_LOG_EVENT_UNFILTERED` for the game client.

[Forever unit and combat log events](https://github.com/Gethe/wow-ui-source/tree/forever/Interface/AddOns/Blizzard_APIDocumentationGenerated) · [Forever's `/ping` command](https://github.com/Gethe/wow-ui-source/blob/forever/Interface/AddOns/Blizzard_ChatFrameBase/Mainline/SlashCommandsOverrides.lua)

## Using the watchlist

- Drag the `/gavenger` window by its title bar and press Esc to close it. The scrollable list includes names, notes, who added each entry and when, and death counts. Click an entry's priority button to switch between normal and high. High-priority entries appear first. Entries from old versions start with normal priority.
- The **All** (**Усі**) tab opens by default. Switch to **Characters** (**Персонажі**) or **Guilds** (**Гільдії**) to narrow the list. **High priority only** (**Лише високий пріоритет**) works in every tab.
- Search by part of a character name, guild name, or note alongside the other filters. Search ignores letter case, and you can clear it with **×**. Each row shows when and where your addon last saw the target. Hover over the row for the author and date added.
- **Remove selected** (**Вилучити позначені**) asks for confirmation before removing all selected rows, including selections hidden by a filter or another tab.
- **Remove** (**Вилучити**) on a single row asks for confirmation too.
- Click **…** in the watchlist to read the full note, author, and last sighting. Import rows and alerts also offer full notes.
- **Add target** (**Додати ціль**) and **Guild from target** (**Гільдія з цілі**) save the character or guild of your current enemy target and use the note you entered. If you typed a name, the buttons use it. If the target is unavailable, the form prompts for manual entry. You can add a guild by name without targeting a member, except for your own guild. You can also right-click an enemy target or focus portrait to add the character or guild with a note.
- Starting with 3.3.2, you can type a character's first and last name to add them without a target. If WoW cannot see the character yet, the entry stays pending until the addon can verify an attackable enemy from the opposing faction outside your group and guild. Tracking and sharing start after verification.
- To add a guild without a target, type its name in the name field and click **Add guild**. If WoW is still loading your own guild name, the entry is saved and becomes available for tracking and sharing once the addon can verify it belongs to a different guild.

| Command | Action |
| --- | --- |
| `/gavenger` or `/gavenger ui` | Open or close the watchlist. |
| `/gavenger list` | List characters and guilds with their priorities in chat. |
| `/gavenger add "Character Name" Note` | Add an enemy. With no arguments, use the current target. |
| `/gavenger addtarget Note` | Add the current target with a note. |
| `/gavenger del Character Name` | Remove a character. With no arguments, use the current target. |
| `/gavenger guild add` | Add the current enemy target's guild. Use `/gavenger guild add "Guild Name" Note` to enter a guild and note manually. |
| `/gavenger guild addtarget Note` | Add the current enemy target's guild with a note. |
| `/gavenger guild del Guild Name` | Remove a guild. |
| `/gavenger share Character Name` | Offer a list to a guildmate. With no arguments, use the current target. |
| `/gavenger share guild` | Post a link to the full watchlist in guild chat. |
| `/gavenger request` | Ask online guildmates for their watchlists. |
| `/gavenger revoke` | Revoke outgoing watchlist links for this session. |
| `/gavenger test` or `/gavenger test high` | Preview the normal- or high-priority alert and play its sound. |
| `/gavenger download` | Open a window with a copyable GitHub link. |
| `/gavenger help` | Show command help. |
| `/gavenger stats` | Open the personal death journal and guild rankings. |
| `/gavenger settings` | Open the settings: language, alert duration, minimap button. |
| `/gavenger minimap` | Hide or show the minimap button. |
| `/gavenger reload` | Reload the UI, like `/reload`. |

## Sharing watchlists

Select the rows you want, or click **Select all** (**Позначити всі**) and clear individual entries. This selects the entire watchlist and keeps your selection when you change tabs or filters. If nothing is selected, the share dialog offers the full list. Choose an online guildmate from the suggestions with the mouse or Tab and click **Send** (**Надіслати**). To share with the guild, click **Post in guild chat** (**У чат гільдії**). Links last up to 30 minutes in the current session. In 3.3.1, editing a shared note or removing a shared entry invalidates the link. **Revoke watchlist links** stops future downloads and ongoing transfers from those links. Guildmates keep copies they already received.

A guild chat post includes a GitHub link for installing or updating the addon. Guild Avenger hides the prompt for recipients with the same version or a newer one. If a list arrives from a newer version, the recipient gets a chat link that opens a window with the copyable GitHub URL. Compatible entries can be accepted right away.

Both sharing methods verify the sender and recipient against the guild roster and send packets 0.25 seconds apart. Version 3.3.1 keeps the roster’s full address and stops the exchange when a recipient cannot be verified unambiguously. Recipients can select which entries, changes, and removals to accept. When sharing the full list, **Suggest removed entries** (**Запропонувати вилучені записи**) includes entries removed in the last 30 days. Merging keeps the higher death count. Both players need Guild Avenger 3.0.0 or later.

When the recipient supports it, Guild Avenger packs several entries into one message. When an entry has a higher death count and a proposed note or priority change, the count appears on a separate, preselected row.

**Request guild watchlists** asks online guildmates running 3.2.0 or later for their lists. They can send their list from the chat link or opt in to automatic replies in **Settings**. Replies include current characters, guilds, notes, priorities, and death counts. In 3.3.0, open **Inbox** to review replies together. The same enemy occupies one row with its sources listed. Use **Notes** to choose from differing comments and **Select all new** to mark new entries. Replies that arrive while you are reviewing remain in the inbox.

In 3.3.1, automatic replies are off until you apply permission for the current character and guild. The previous account-wide permission is reset on upgrade. **Cancel** discards settings changes. Applying a change that turns automatic replies off also stops queued replies. Shared records include notes, authors, dates added, and death counts.

In 3.4.2, open **Requests → Request guild watchlists** to ask the guild. If a guildmate needs to reply manually, they see an on-screen notice and an **Open requests** link in chat. In **Requests**, they can send their current list or dismiss the request. Requests stay available for five minutes. **Inbox** shows replies for review before any entries are added.

In 3.4.5, enable **Settings → Automatically exchange watchlists** for a two-way sync with online guildmates who enabled the same option. It starts when your guild roster is ready after login and checks again hourly. **Inbox** shows new or changed entries for approval. Entries reviewed and skipped stay out of automatic results until their contents change. Automatic checks stay quiet in chat and use the current character and guild's setting.

From 3.4.6, the Inbox badge counts only replies with changes left to review. Automatic exchange keeps your comment when a guildmate first shares an existing entry or repeats the same comment. A later edit by that guildmate can appear for review. Manual sharing can still show different comments.

## Guild sightings

Guild Avenger can tell guildmates where you met a listed enemy. The three options in **Settings** (**Налаштування**) start off and apply to your current character and guild.

- **Report enemies I meet to the guild** sends a hidden addon message to the guild when you get a new alert. It contains the enemy's name, their guild name when the addon can see it, your zone and subzone, and your map coordinates rounded to whole percent. Nothing is sent from dungeons, battlegrounds, or arenas. You report the same enemy at most once a minute, at most one enemy every 5 seconds, and not at all for a minute after a guildmate reported that enemy.
- **Show guild sightings in chat and on the map** shows sightings for targets on your watchlist or members of guilds on it. Chat uses your own note and priority and displays at most one message per minute per enemy. Reports are accepted only from members of your guild roster.
- **Also show a popup with sound** shows the alert window for these sightings too.
- **Share sighting** (**Поділитися зустріччю**) on a local alert posts the enemy and your current location in guild chat when clicked outside an instance.

Guildmates on versions before 3.4.0 neither send nor receive sightings.

Starting in 3.4.4, the world map shows **Seen here** markers for the last 15 minutes of your own encounters, plus reports from guildmates on 3.4.4 or later if you enabled receiving them. Hover over a marker for the character, guild, age and observer. The marker uses the observer's location at the time of the encounter.

## Statistics

- **My Deaths** (**Мої смерті**) shows up to 100 deaths with a confirmed player killing blow, with time, zone, and coordinates when WoW provides them. If an older entry lacks a verified player ID, it stays in saved data and is omitted from this view. A row whose killer was recorded as an enemy player has an **Add to list** (**До книги**) button that adds the killer to the watchlist. Deaths recorded before 3.4.0 have no button.
- **Avengers** (**Месники**) ranks Honor awarded for kills against each guildmate’s watchlist. Healers and other party members get credit when WoW awards them Honor for the same kill. An enemy on both the character and guild lists counts once. An award has to name a recognizable enemy. For guild-only matches, the addon needs to have seen that enemy’s guild.
- **Killing blows** (**Останні удари**) keeps the earlier ranking and counts final hits by guildmates or their active pets against watchlist entries. An enemy that matches both a character and a guild entry gives one killing blow in the ranking.
- **Enemies** (**Вороги**) ranks the enemies with the most confirmed killing blows against guildmates who share their statistics. It groups reports by enemy character ID and keeps the highest reported total from each guildmate.
- In **Enemies**, click **Add to watchlist** (**До книги**) to add a ranked enemy. If WoW cannot identify the character yet, the entry waits for the next encounter to confirm the name and faction. A confirmed enemy's alert shows their known number of guildmate kills.
- **Avengers** and **Killing blows** both have all-time and current-week views. Honor tracking starts in 3.2.0. Earlier killing blow totals carry over. Weekly totals reset every Monday at 00:00 UTC.
- **Honor journal** shows the latest 100 recognizable Honor awards for your character, with the target when known and the reason the award counted or was left out. It also shows when an award counted towards the guild race.
- Enable **Share summaries with the guild** (**Ділитися підсумками з гільдією**) to send your ranking totals to guildmates. In 3.3.1, sending attackers’ names, game GUIDs, and each attacker’s kill count requires the separate **Share attacker details with the guild** permission in **Settings**. **Refresh rankings** fetches summaries from online members who have sharing enabled. Journals, times, and coordinates stay local. Honor sync requires Guild Avenger 3.2.0 or later. Killing blow and enemy totals can still sync with versions 3.0.0 and later.

### Weekly guild race

In **Statistics → Guild race** the guild leader can lock the selected entries from their watchlist, or the entire list if nothing is checked. **Race targets** shows the shared list. Once you have received it, your Honor awards can count toward the race until Monday at 00:00 UTC. **Sync guild race** requests the target list from the online leader and updates results from online members who opted into statistics sharing. The race requires 3.3.0 or later.

## Contributing

Fork the repository and open a pull request. To test locally, copy the `GuildAvenger` folder into your AddOns folder and type `/reload` in WoW. When reporting a bug, include your WoW version and the steps to reproduce it.

Run `python scripts/test-watchlist-sharing.py` with the Python package `lupa` installed to exercise sharing with simulated WoW clients. For an in-game check, use two online guildmates on the same addon version. Send a watchlist request, answer it manually, and check that only selected entries are added from the inbox. Also try a direct share and a guild chat link.

Guild Avenger is a free, open-source addon made for fun. The project is developed without monetization. The code is available under the [MIT License](LICENSE).
