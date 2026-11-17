-- Static tables: dungeons for the picker, folder colours, limits, first-run pages.
local _, ns = ...

ns.ERA = select(4, GetBuildInfo()) < 16000
ns.ICON = "Interface\\Icons\\INV_Misc_Book_09"
ns.PREFIX = "|cffe8c87aEzNotebook|r: "

-- Limits (letters / bytes as typed).
ns.MAX_TITLE = 60
ns.MAX_NOTE = 20000
ns.MAX_TASK = 250
ns.MAX_GOAL = 9999
ns.SEARCH_MIN = 2 -- letters before the search filters

-- Dungeons and raids for the Dungeon picker. id = GetInstanceInfo()'s 8th return (Map.db2 ID), as
-- DeadButDelicious' ns.VENUES. Names are only shown until you enter the place: then the client's own name
-- (EzNotebookDB.instances) wins. `forever` = only in WoW Forever.
ns.DUNGEONS = {
    { id = 389, name = "Ragefire Chasm" },
    { id = 36, name = "The Deadmines" },
    { id = 43, name = "Wailing Caverns" },
    { id = 33, name = "Shadowfang Keep" },
    { id = 34, name = "The Stockade" },
    { id = 48, name = "Blackfathom Deeps" },
    { id = 90, name = "Gnomeregan" },
    { id = 47, name = "Razorfen Kraul" },
    { id = 189, name = "Scarlet Monastery" },
    { id = 129, name = "Razorfen Downs" },
    { id = 70, name = "Uldaman" },
    { id = 209, name = "Zul'Farrak" },
    { id = 349, name = "Maraudon" },
    { id = 109, name = "The Temple of Atal'Hakkar" },
    { id = 230, name = "Blackrock Depths" },
    { id = 229, name = "Blackrock Spire" },
    { id = 429, name = "Dire Maul" },
    { id = 289, name = "Scholomance" },
    { id = 329, name = "Stratholme" },
    { id = 3109, name = "Manor Mistmantle", forever = true },
    { id = 2994, name = "Alcaz Prison", forever = true },
    { id = 2970, name = "The Drowned City", forever = true },
    { id = 2974, name = "Blackmaw Hold", forever = true },
    { id = 2998, name = "Excavation Site", forever = true },
    { id = 3039, name = "Krol'dok Stronghold", forever = true },
    { id = 3065, name = "The Hall of Thanes", forever = true },
    { id = 2999, name = "Ruins of Lordaeron", forever = true },
    { id = 2959, name = "Dalaran", forever = true },
    { id = 3001, name = "The Shaper's Terrace", forever = true },
    { id = 409, name = "Molten Core", raid = true },
    { id = 249, name = "Onyxia's Lair", raid = true },
    { id = 469, name = "Blackwing Lair", raid = true },
    { id = 309, name = "Zul'Gurub", raid = true },
    { id = 509, name = "Ruins of Ahn'Qiraj", raid = true },
    { id = 531, name = "Temple of Ahn'Qiraj", raid = true },
    { id = 533, name = "Naxxramas", raid = true },
}

-- Folder colours (right-click a folder > Colour). Hex without the alpha.
ns.COLORS = {
    { key = "gold", name = "Gold", hex = "e8c87a" },
    { key = "red", name = "Red", hex = "e06c5f" },
    { key = "orange", name = "Orange", hex = "f0a050" },
    { key = "green", name = "Green", hex = "7fcf6f" },
    { key = "teal", name = "Teal", hex = "5fc8c0" },
    { key = "blue", name = "Blue", hex = "6fa8ef" },
    { key = "purple", name = "Purple", hex = "b98af0" },
    { key = "grey", name = "Grey", hex = "a0a0a0" },
}

-- Colours of our own links (addon links: only EzNotebook reads them).
ns.LINK_COLORS = {
    quest = "ffff00", -- Era has no quest links; ours look like Blizzard's
    dungeon = "ff9d5c",
    place = "7fd0ff",
}

-- First run: a daily list and a short how-to note.
ns.WELCOME_TITLE = "How this works"
ns.WELCOME = table.concat({
    "Folders on the left hold notes and todo lists. Right-click anything for its options.",
    "",
    "Notes: click the page to write, click outside or press Escape when done. Links you add stay clickable.",
    "",
    "Links: while you type, Shift-click a quest, item or spell to put its link in, or drag an item onto the box. "
        .. "The Quest, Dungeon and Here buttons add one from your quest log, a dungeon list or where you stand.",
    "",
    "Todo lists: type a task and press Enter. A task with a link ticks itself:",
    "- a quest: when you turn it in",
    "- a dungeon: when you leave it with a boss down, or when you kill the boss you picked",
    "- an item with a number (\"20 [Linen Cloth]\"): when your bags and bank hold that many",
    "- \"Reach level 30\": when you get there",
    "- a place (Here button): when you walk into it",
    "",
    "Right-click a task to make it daily: it unchecks itself at the daily reset. Done one-time tasks clear "
        .. "away at the reset unless the list keeps them.",
    "",
    "/todo <task> adds a task to your Today list. /nb opens this book.",
}, "\n")
