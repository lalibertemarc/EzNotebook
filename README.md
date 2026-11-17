# EzNotebook

Notes and todo lists for World of Warcraft (WoW Forever and Classic Era), in folders, with quest, item, dungeon and place links. Linked tasks tick themselves.

- `/nb` (`/notebook`) opens the notebook; `/todo <task>` adds to your Today list; `/nb help` lists the rest.
- Key bindings: *Open or close the notebook*, *Add a task to Today*.
- Right-click folders, pages and tasks for their options.

| Task links to | Ticks when |
|---|---|
| a quest | you turn it in (or already have) |
| a dungeon | you leave it alive with a boss down |
| a dungeon boss | that boss dies |
| an item with a number (`20 [Linen Cloth]`) | your bags and bank hold that many |
| `Reach level 30` | you get there |
| a place (Here button) | you walk into it |

Development: `lua tests/notebook.lua` (rules + the whole addon on a stubbed API), `luacheck .`.
