# RestedXP - Dungeon Journal Bridge

A standalone addon for WoW Forever. Quests in ForeverDungeonJournal get a small
RestedXP logo when they appear in an installed RXP guide. Hover the logo to see
every matching guide's title, group, subgroup and step numbers.

Main quests and expanded prerequisite rows are supported. Item-only steps and
quests hidden by Dungeon Journal's RPG mode have no marker. Existing quest
selection, quest symbols, completion ticks and chain controls stay in place.

## Install

Requires `RXPGuides` and `ForeverDungeonJournal`. From PowerShell in this repo:

```powershell
.\scripts\Install.ps1
```

The default destination is
`I:\World of Warcraft_2\_forever_\Interface\AddOns\RXPDJBridge`.
Pass `-WoWPath 'D:\World of Warcraft'` to use a different installation.
The installer copies only the addon's three files and checks their hashes.

Enable **RestedXP - Dungeon Journal Bridge** in the character screen's AddOns list.
Restart the client if the new addon does not appear. Otherwise, `/reload` loads
changes to an addon the client has already discovered. Open `/dj`, pick a dungeon
and view its quests. Hover an RXP logo below a quest symbol or beside a chain step.

## Guide matching

The bridge uses the installed RXP build's `RXP.guides`, `FetchGuide` and
`ProcessGuideTable` functions. This includes imported and inactive guides
registered for the current character. RXP handles class/faction/race conditions,
Forever quest IDs, included guides and route settings. The tooltip names the
parent route after RXP expands its includes, and uses that route's step numbers.
Disabled and internal helper guides are excluded.

The bridge processes one guide per timer callback and defers scans during combat.
RXP may expand several included guides when processing a route. The first scan
can take a few seconds for a large guide library. It uses RXP's normal lazy guide
loader without selecting another guide or changing saved progress. Nothing is
downloaded, and neither dependency is patched. The index lives in memory and is
rebuilt on login, guide imports/removals, route reloads and registry changes.

Commands:

- `/rxpdj` shows the indexed guide/quest counts and unavailable guide count.
- `/rxpdj rescan` rebuilds the index, useful after changing RXP route settings.
- `/rxpdj quest 167` lists matching guides for a quest ID.

Built against the installed Forever client interface `16001`,
ForeverDungeonJournal `2.0.5` and RestedXP `v4.11.36`. The integration relies on
these addons' exposed Lua tables, including Dungeon Journal's
`MarkLostQuestRows` post-refresh helper. Future dependency changes may require
updating the bridge.

## Development checks

Run from the repository root with Lua 5.1 or newer:

```text
lua tests/run.lua
```

The tests run the production files with mocked WoW frames and RXP data. They
check matching, multiple guides, included routes, lazy loading, reused rows,
tooltips, imports/removals and combat deferral. They cannot verify rendering in
the game client. In-game checks should cover switching dungeons, expanding
prerequisite chains, changing RXP routes and hovering the markers.
