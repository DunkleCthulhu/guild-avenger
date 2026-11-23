# Guild Avenger 3.0.1

**English** · [Українська](README.uk.md)

Guild Avenger is a free, open-source PvP addon for **World of Warcraft: Forever 1.60.1**. Keep a watchlist of enemy characters and guilds, get alerts when you encounter them, and share entries and optional PvP statistics with guildmates. The in-game interface is in Ukrainian.

## Installation

Extract `GuildAvenger-3.0.1.zip` into `World of Warcraft/_forever_/Interface/AddOns/`. The addon appears in the addon menu as **Guild Avenger**. Type `/gavenger` or click the book icon beside the minimap. Drag the icon to move it around the minimap. [GitHub releases](https://github.com/DunkleCthulhu/guild-avenger/releases)

### Migrating from GrudgeBook or Forever Watch

Close WoW, install Guild Avenger, and run the migration script from this repository on Windows. Replace the example path with your `_forever_` folder.

```powershell
./scripts/Migrate-GuildAvenger.ps1 -ClientRoot 'C:/Program Files (x86)/World of Warcraft/_forever_'
```

The script migrates data from earlier versions of this project. It copies your lists, statistics, and settings into a separate `GuildAvenger.lua` SavedVariables file, then moves the old addon and its data files to `GuildAvengerMigrationBackup`. Add `-WhatIf` to preview the changes. Run the migration before you first launch Guild Avenger.

## Detection and death counts

- Guild Avenger alerts you about characters on your watchlist and members of listed guilds when you target them, mouse over them, see an available nameplate, or receive a readable `UNIT_COMBAT` event. The alert shows their portrait, name, note, and high-priority indicator. The name and note also appear in chat. Alerts for the same enemy have a 30-second cooldown.
- By default, normal-priority alerts use the raid warning sound and high-priority alerts play a distinct ascending four-note sound. Open `/gavenger` and click **Звуки…** to select and preview built-in WoW sounds for each priority. You can mute character or guild matches separately, or play sounds for high-priority matches only. When a character and their guild both match, the character entry controls the priority, note, and sound settings.
- The alert appears near the top of the screen in a semi-transparent WoW-style frame. High-priority alerts have a gold border. Drag the alert with the left mouse button to move it. Its position is saved between sessions. Use `/gavenger test` and `/gavenger test high` to preview the two styles.
- The **Target** (**У ціль**) and **Danger Ping** (**Пінг небезпеки**) buttons are available outside combat. The ping button appears when the enemy from the alert is your current target and WoW pings are enabled. Click it to send a built-in danger ping on that target.
- The death counter uses available `PARTY_KILL` and `UNIT_DIED` events and counts duplicate reports of the same death once. A listed guild member's death increases the guild total. If the character also has an individual entry, their counter increases too. WoW must provide a readable identifier, and the addon must recognize the character or guild. Forever reserves `COMBAT_LOG_EVENT_UNFILTERED` for the game client.

[Forever unit and combat log events](https://github.com/Gethe/wow-ui-source/tree/forever/Interface/AddOns/Blizzard_APIDocumentationGenerated) · [Forever's `/ping` command](https://github.com/Gethe/wow-ui-source/blob/forever/Interface/AddOns/Blizzard_ChatFrameBase/Mainline/SlashCommandsOverrides.lua)

## Using the watchlist

- Drag the `/gavenger` window by its title bar and press Esc to close it. The scrollable list includes names, notes, who added each entry and when, and death counts. Click an entry's priority button to switch between normal and high. High-priority entries appear first. Entries from old versions start with normal priority.
- The **All** (**Усі**) tab opens by default. Switch to **Characters** (**Персонажі**) or **Guilds** (**Гільдії**) to narrow the list. **High priority only** (**Лише високий пріоритет**) works in every tab.
- Search by part of a character name, guild name, or note alongside the other filters. Each row shows when and where your addon last saw the target. Hover over the row for the author and date added.
- **Remove selected** (**Вилучити позначені**) asks for confirmation before removing all selected rows, including selections hidden by a filter or another tab.
- Click **…** to read the full note in the watchlist, import window, or an alert with a note.
- **Add target** (**Додати ціль**) and **Guild from target** (**Гільдія з цілі**) save the character or guild of your current enemy target and use the note you entered. If you typed a name, the buttons use it. If the target is unavailable, the form prompts for manual entry. You can add a guild by name without targeting a member, except for your own guild. You can also right-click an enemy target or focus portrait to add the character or guild with a note.
- For manually entered characters, WoW must allow the addon to verify that the person belongs to the opposing faction, can be attacked, and is outside your group and guild. Use the full name and keep the character targeted, under your mouse, in focus, or visible through a nameplate.

| Command | Action |
| --- | --- |
| `/gavenger` or `/gavenger ui` | Open or close the watchlist. |
| `/gavenger list` | List characters and guilds with their priorities in chat. |
| `/gavenger add "Character Name" Note` | Add an enemy. With no arguments, use the current target. |
| `/gavenger del Character Name` | Remove a character. With no arguments, use the current target. |
| `/gavenger guild add` | Add the current enemy target's guild. Use `/gavenger guild add "Guild Name" Note` to enter a guild and note manually. |
| `/gavenger guild del Guild Name` | Remove a guild. |
| `/gavenger share Character Name` | Offer a list to a guildmate. With no arguments, use the current target. |
| `/gavenger share guild` | Post a link to the full watchlist in guild chat. |
| `/gavenger test` or `/gavenger test high` | Preview the normal- or high-priority alert and play its sound. |
| `/gavenger download` | Open a window with a copyable GitHub link. |
| `/gavenger help` | Show command help. |
| `/gavenger stats` | Open the personal death journal and guild rankings. |

## Sharing watchlists

Select the rows you want, or click **Select all** (**Позначити всі**) and clear individual entries. This selects the entire watchlist and keeps your selection when you change tabs or filters. If nothing is selected, the share dialog offers the full list. Choose an online guildmate from the suggestions with the mouse or Tab and click **Send** (**Надіслати**). To share with the guild, click **Post in guild chat** (**У чат гільдії**). The link works for 30 minutes while the sender stays online in the same session.

A guild chat post includes a GitHub link for installing or updating the addon. Guild Avenger hides the prompt for recipients with the same version or a newer one. If a list arrives from a newer version, the recipient gets a chat link that opens a window with the copyable GitHub URL. Compatible entries can be accepted right away.

Both sharing methods verify the sender and recipient against the guild roster and send packets 0.25 seconds apart. Recipients can review new entries, proposed note or priority changes, and proposed removals. They must select the proposed changes or removals before accepting them. When sharing the full list, enable **Suggest removed entries** (**Запропонувати вилучені записи**) to include entries you removed in the last 30 days. Merging keeps the higher death count. Both players need Guild Avenger 3.0.0 or later.

## Statistics

- **My Deaths** (**Мої смерті**) keeps up to 100 of your character's recent deaths, with time, zone, and coordinates when WoW provides them. The attacker appears if the death recap shows a confirmed killing blow.
- **Avengers** (**Месники**) ranks killing blows dealt by guildmates or their active pets to characters and guild members on their watchlists. A kill that matches both a character and a guild entry gives one point in the ranking.
- **Enemies** (**Вороги**) ranks the enemies with the most confirmed killing blows against guildmates who share their statistics. It groups reports by enemy character ID and keeps the highest reported total from each guildmate.
- In **Enemies**, click **Add to watchlist** (**До книги**) to add a ranked enemy. If WoW cannot identify the character yet, the entry waits for the next encounter to confirm the name and faction. A confirmed enemy's alert shows their known number of guildmate kills.
- **Avengers** has all-time and current-week views. Weekly tracking starts in version 2.4.0 and resets every Monday at 00:00 UTC. All-time totals carry over.
- Enable **Share summaries with the guild** (**Ділитися підсумками з гільдією**) to send your totals to guildmates. **Refresh rankings** (**Оновити рейтинг**) fetches summaries from online members who have sharing enabled. Your journal and the times and coordinates of individual deaths stay local. Ranking sync requires Guild Avenger 3.0.0 or later.

## Contributing

Fork the repository and open a pull request. To test locally, copy the `GuildAvenger` folder into your AddOns folder and type `/reload` in WoW. When reporting a bug, include your WoW version and the steps to reproduce it.

Guild Avenger is a free, open-source addon made for fun. The project is developed without monetization. The code is available under the [MIT License](LICENSE).
