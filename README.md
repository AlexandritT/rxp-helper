# RestedXP Helper

A standalone addon for WoW Forever. Quest tooltips show the installed RestedXP
guides that contain that quest, including the guide title, group, subgroup and
step numbers. Native quest tooltips, clicked chat quest links and Questie map
and tracker tooltips are supported. The original quest text stays intact.

Quests in ForeverDungeonJournal also get a small RestedXP logo. Hover the logo
to see the same guide information. Dungeon Journal is optional.

By default, guide information and DJ markers only appear for quests in your
current RXP guide grouping, such as Forever Dungeon Guide or Forever Speedrun
Guide. All matching chapters in that top-level grouping are included. Hold
**Alt** to show matches from every installed grouping. Open tooltips and DJ
markers update when you press or release Alt or switch guide groupings. If no
guide is selected, hold Alt to see guide information.

Main quests and expanded prerequisite rows are supported. Item-only steps and
quests hidden by Dungeon Journal's RPG mode have no marker. Existing quest
selection, quest symbols, completion ticks and chain controls stay in place.

## Install

Requires `RXPGuides`. `ForeverDungeonJournal` and `Questie` are optional.
From PowerShell in this repo:

```powershell
.\scripts\Install.ps1
```

The default destination is
`I:\World of Warcraft_2\_forever_\Interface\AddOns\RestedXPHelper`.
Pass `-WoWPath 'D:\World of Warcraft'` to use a different installation.
The installer backs up existing `RXPDJBridge` and `RestedXPHelper` directories
outside AddOns before copying the four addon files and checking their hashes.
Backups go to `%USERPROFILE%\.t3\backups\rxp-helper`. Override this with
`-BackupRoot 'D:\WoW Backups'`. The original and renamed builds must not run
together.

Enable **RestedXP Helper** in the character screen's AddOns list.
Restart the client if the new addon does not appear. Otherwise, `/reload` loads
changes to an addon the client has already discovered. Open `/dj`, pick a dungeon
and view its quests. Hover an RXP logo below a quest symbol or beside a chain step.
You can also hover quests in Questie or click a quest link in chat.

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

Commands, also available through the old `/rxpdj` alias:

- `/rxph` shows the indexed guide/quest counts and unavailable guide count.
- `/rxph rescan` rebuilds the index, useful after changing RXP route settings.
- `/rxph quest 167` lists matching guides for a quest ID.

Tooltip hooks use readable quest IDs, not quest-title matching. Tooltips without
a matching guide are unchanged. Restricted quest IDs and forbidden tooltips are
skipped. Native and Questie tooltips rebuild through their original rendering
methods when the active grouping or Alt state changes.

Built against the installed Forever client interface `16001`,
ForeverDungeonJournal `2.0.5` and RestedXP `v4.11.36`. The integration relies on
these addons' exposed Lua tables, including Dungeon Journal's
`MarkLostQuestRows` post-refresh helper. Future dependency changes may require
updating the helper.

## Original build and rollback

The original DJ-only build is committed and tagged `v1.0.0-dj-bridge`.
The rename and quest tooltip support are version `1.1.0`.
Current-group filtering and the Alt override are version `1.2.0`.

To return to the original build, close WoW, move `RestedXPHelper` out of the
AddOns directory, then restore the backed-up `RXPDJBridge` folder there. A ZIP
of the original installation is also in the backup directory. Restart WoW and
enable the old addon. RXP guide progress is not stored by either version.

You can inspect or recover the original source from the Git tag without
changing your current checkout:

```text
git archive --format=zip --output=rxp-dj-bridge-v1.0.0.zip v1.0.0-dj-bridge
```

## Development checks

Run from the repository root with Lua 5.1 or newer:

```text
lua tests/run.lua
```

The tests run the production files with mocked WoW frames and RXP data. They
check matching, multiple guides, included routes, lazy loading, reused rows,
native and Questie tooltips, imports/removals, optional Dungeon Journal and
combat deferral. They cannot verify rendering in
the game client. They also cover current-group filtering, live Alt expansion
and collapse, and switching guide groupings without rebuilding the index. In-game
checks should cover switching dungeons, expanding
prerequisite chains, changing RXP routes, hovering quest tooltips and clicking
chat quest links.
