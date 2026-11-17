# EzNotebook

Notes and todo lists for World of Warcraft (WoW Forever and Classic Era), in folders, with quest, item and dungeon links and marked spots. Linked tasks tick themselves.

- `/nb` (`/notebook`) opens the notebook; `/todo <task>` adds to your Today list; `/nb help` lists the rest.
- Key bindings: *Open or close the notebook*, *Add a task to Today*.
- Launchers: a minimap button, the addon drawer (WoW Forever) and an icon above the chat. Click opens the notebook, right-click adds a task. Each can be hidden from the window's Options menu (`/nb minimap|drawer|icon off`).
- Right-click folders, pages and tasks for their options.
- **Mark spot** saves where you stand as a link (a bookmark): click it later for a pin on your map (Classic Era: its coordinates in chat). It never ticks a task.

| Task links to | Ticks when |
|---|---|
| a quest | you turn it in (or already have) |
| a dungeon | you leave it alive with a boss down |
| a dungeon boss | that boss dies |
| an item with a number (`20 [Linen Cloth]`) | your bags and bank hold that many |
| `Reach level 30` | you get there |

Development: `lua tests/notebook.lua` (rules + the whole addon on a stubbed API), `luacheck .`.
