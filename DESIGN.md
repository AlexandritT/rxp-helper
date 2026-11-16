# RestedXP Helper

The orphan quest browser follows the user's installed EllesmereUI or ElvUI.
Prefer EllesmereUI's GetAccentColor, DARK_BG and GetFontPath; otherwise use
ElvUI's configured value color and normal font. A standalone dark palette is
available when neither suite is loaded. No Blizzard ornamental window chrome.

Use flat surfaces, one-pixel edges, readable text and a single selection accent.
The 1040 by 660 window fits inside the available UI dimensions. The left column
is a zone-grouped quest navigator; the right column is the selected quest's
description, objectives and confirmed Abandon action. Both columns scroll
independently. Keep the selected quest stable across updates when it remains
visible. Dungeon exclusion is a persistent, reversible display filter.

Base colors: background #0e1011, sidebar #0b0c0e, foreground #e8edf0,
secondary #9ea8b0, standalone accent #40c2ba. Host-suite tokens override the
background, accent and font. Text sizes: 24 title, 22 quest heading, 14 content,
12 metadata and zone headings, 11 secondary controls. List rows are at least
58 units high, with room for wrapped quest titles. Selection uses a faint accent
fill and a one-pixel edge; hover uses a faint neutral fill.

Do not send input to the running game for inspection or testing. Verify Lua and
behavior through local tests; the user handles in-game visual checks.
