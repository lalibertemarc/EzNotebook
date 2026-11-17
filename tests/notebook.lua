-- lua tests/notebook.lua (inside the addon folder). Part 1: the rules in Logic.lua. Part 2: the whole addon on a
-- stubbed game API: login, /todo, tasks ticking themselves, the window, note editing, link insertion, menus, pin.
-- Catches nil calls and wrong state, not looks.
local checks, failed = 0, 0
local function check(ok, what)
    checks = checks + 1
    if not ok then
        failed = failed + 1
        print("FAIL: " .. what)
    end
end

---------------------------------------------------------------------------
-- Stubs (enough for Data/Logic to load on their own too)
---------------------------------------------------------------------------
local now = 1800000000
local state = {
    level = 10, zone = "Elwynn Forest", sub = "Goldshire", map = 1429, inside = false, instance = nil,
    counts = {}, done = {}, onQuest = {}, untilReset = 6 * 3600, dead = false, cursor = nil,
}
local printed = {}
_G.time = function() return now end
_G.GetTime = function() return now end
_G.GetBuildInfo = function() return "1.60.1", "0", "", 16001 end
_G.issecretvalue = function() return false end

local timers = {}
_G.C_Timer = { After = function(s, fn) timers[#timers + 1] = { s = s, fn = fn } end }
local function runTimers(maxDelay)
    local due, keep = {}, {}
    for _, t in ipairs(timers) do
        if t.s <= (maxDelay or 5) then due[#due + 1] = t else keep[#keep + 1] = t end
    end
    timers = keep
    for _, t in ipairs(due) do t.fn() end
end

local Widget
local function Methods()
    return {
        SetScript = function(self, name, fn) self.scripts[name] = fn end,
        GetScript = function(self, name) return self.scripts[name] end,
        HookScript = function(self, name, fn) self.scripts[name] = fn end,
        SetText = function(self, t) self.text = t or "" end,
        GetText = function(self) return self.text end,
        Insert = function(self, t)
            self.text = self.text .. t
            if self.scripts.OnTextChanged then self.scripts.OnTextChanged(self, false) end
        end,
        Show = function(self)
            local was = self.shown
            self.shown = true
            if not was and self.scripts.OnShow then self.scripts.OnShow(self) end
        end,
        Hide = function(self)
            local was = self.shown
            self.shown = false
            if was and self.scripts.OnHide then self.scripts.OnHide(self) end
        end,
        SetShown = function(self, on) if on then self:Show() else self:Hide() end end,
        IsShown = function(self) return self.shown end,
        IsVisible = function(self) return self.shown end,
        SetFocus = function(self)
            if self.focus then return end
            self.focus = true
            if self.scripts.OnEditFocusGained then self.scripts.OnEditFocusGained(self) end
        end,
        ClearFocus = function(self)
            if not self.focus then return end
            self.focus = false
            if self.scripts.OnEditFocusLost then self.scripts.OnEditFocusLost(self) end
        end,
        HasFocus = function(self) return self.focus end,
        SetChecked = function(self, on) self.checked = on and true or false end,
        GetChecked = function(self) return self.checked end,
        Click = function(self)
            if self.kind == "CheckButton" then self.checked = not self.checked end
            if self.scripts.OnClick then self.scripts.OnClick(self, "LeftButton") end
        end,
        CreateFontString = function() return Widget("FontString") end,
        CreateTexture = function() return Widget("Texture") end,
        GetStringWidth = function() return 60 end,
        GetStringHeight = function() return 40 end,
        GetWidth = function() return 300 end,
        GetHeight = function(self) return self.height or 300 end,
        SetHeight = function(self, h) self.height = h end,
        GetLeft = function() return 10 end,
        GetTop = function() return 500 end,
        GetVerticalScroll = function() return 0 end,
        GetVerticalScrollRange = function() return 0 end,
        GetCursorPosition = function(self) return #self.text end,
        GetFrameLevel = function() return 1 end,
        GetEffectiveScale = function() return 1 end,
        GetDebugName = function() return "stub" end,
    }
end
local methods = Methods()
function Widget(kind)
    local w = { kind = kind, scripts = {}, text = "", shown = true, checked = false }
    -- Capitalized names are methods (unknown ones do nothing); anything else is a plain field.
    return setmetatable(w, { __index = function(_, k)
        if methods[k] then return methods[k] end
        if type(k) == "string" and k:match("^%u") then return function() end end
    end })
end

local events, created = {}, {}
_G.CreateFrame = function(kind, name, _, template)
    local f = Widget(template == "UICheckButtonTemplate" and "CheckButton" or kind)
    created[#created + 1] = f
    f.RegisterEvent = function(self, e) events[e] = self end
    if name then _G[name] = f end
    return f
end
_G.UIParent = Widget("Frame")
_G.GameTooltip = Widget("GameTooltip")
_G.ItemRefTooltip = Widget("GameTooltip")
_G.ChatFrame1 = Widget("Frame")
_G.DEFAULT_CHAT_FRAME = { AddMessage = function(_, msg) printed[#printed + 1] = msg end }
_G.UISpecialFrames = {}
_G.tinsert = table.insert
_G.SlashCmdList = {}
_G.hooksecurefunc = function(a, b, c)
    if type(a) == "table" then
        local old = a[b]
        a[b] = function(...)
            local r = old(...)
            c(...)
            return r
        end
    else
        local old = _G[a]
        _G[a] = function(...)
            local r = old(...)
            b(...)
            return r
        end
    end
end
_G.ChatFrameUtil = { InsertLink = function() return false end }
_G.ChatEdit_InsertLink = _G.ChatFrameUtil.InsertLink -- Forever's alias
_G.IsModifiedClick = function() return false end
_G.GetCursorPosition = function() return 0, 0 end
_G.GetCursorInfo = function()
    if state.cursor then return "item", state.cursor.id, state.cursor.link end
end
_G.ClearCursor = function() state.cursor = nil end
_G.C_DateAndTime = { GetSecondsUntilDailyReset = function() return state.untilReset end }
_G.C_QuestLog = {
    IsQuestFlaggedCompleted = function(id) return state.done[id] == true end,
    IsOnQuest = function(id) return state.onQuest[id] == true end,
    GetNumQuestLogEntries = function() return 2 end,
    GetInfo = function(i)
        if i == 1 then return { isHeader = true, title = "Elwynn Forest" } end
        return { title = "The Fargodeep Mine", questID = 62, level = 7 }
    end,
}
_G.GetQuestLink = function(id) return ("|cffffff00|Hquest:%d:7|h[The Fargodeep Mine]|h|r"):format(id) end
_G.C_Item = { GetItemCount = function(id) return state.counts[id] or 0 end }
_G.UnitLevel = function() return state.level end
_G.UnitGUID = function() return "Player-1-0000AAAA" end
_G.UnitName = function() return "Olizzy", "Duskmantle" end
_G.UnitIsDeadOrGhost = function() return state.dead end
_G.GetRealZoneText = function() return state.zone end
_G.GetZoneText = function() return state.zone end
_G.GetSubZoneText = function() return state.sub end
_G.C_Map = {
    GetBestMapForUnit = function() return state.map end,
    GetPlayerMapPosition = function() return { GetXY = function() return 0.4231, 0.6512 end } end,
}
_G.IsInInstance = function() return state.inside, state.inside and "party" or "none" end
_G.GetInstanceInfo = function()
    if state.instance then return state.instance.name, "party", 1, "Normal", 5, 0, false, state.instance.id end
    return state.zone, "none", 0, "", 0, 0, false, 0
end

---------------------------------------------------------------------------
-- Load
---------------------------------------------------------------------------
local ns = {}
local toc = io.open("EzNotebook.toc"):read("*a")
for file in toc:gmatch("\n([%w_]+%.lua)") do
    assert(loadfile(file))("EzNotebook", ns)
end

---------------------------------------------------------------------------
-- Part 1: rules
---------------------------------------------------------------------------
local ITEM = "|cffffffff|Hitem:2589::::::::10:::::::|h[Linen Cloth]|h|r"
local QUEST = "|cffffff00|Hquest:123:10|h[Kobold Camp Cleanup]|h|r"

do
    local link, goal = ns.ParseTask("Gather 20 " .. ITEM)
    check(link and link.k == "item" and link.id == 2589 and goal == 20, "item with a count")
    check(link.name == "Linen Cloth", "item label read")
    link, goal = ns.ParseTask(ITEM .. " x35")
    check(link.k == "item" and goal == 35, "item with x35 after")
    link, goal = ns.ParseTask("Sell " .. ITEM)
    check(link.k == "item" and goal == nil, "item without a count has no goal")
    link = ns.ParseTask("Turn in " .. QUEST)
    check(link and link.k == "quest" and link.id == 123 and link.name == "Kobold Camp Cleanup", "quest link")
    link = ns.ParseTask(QUEST .. " then 20 " .. ITEM)
    check(link.k == "quest", "quest wins over item")
    link = ns.ParseTask("Do " .. ns.QuestLink(456, "Era Quest [x]"))
    check(link.k == "quest" and link.id == 456 and link.name == "Era Quest x", "our quest link, brackets dropped")
    link = ns.ParseTask("Run " .. ns.DungeonLink(36, "The Deadmines"))
    check(link.k == "dungeon" and link.id == 36 and link.boss == nil and link.name == "The Deadmines", "dungeon run")
    link = ns.ParseTask(ns.DungeonLink(36, "The Deadmines", 1002, "Sneed: Shredder"))
    check(link.boss == 1002 and link.name == "The Deadmines" and link.bossName == "Sneed: Shredder",
        "dungeon boss, colon in the boss name")
    local place = ns.PlaceLink("Zul:Aman", "Hall 100%", 1429, 0.4231, 0.6512)
    link = ns.ParseTask("Visit " .. place)
    check(link.k == "place" and link.zone == "Zul:Aman" and link.sub == "Hall 100%", "place zone/sub survive")
    check(math.abs(link.x - 0.423) < 0.0001 and link.map == 1429, "place spot")
    link = ns.ParseTask(ns.PlaceLink("Elwynn Forest", "", 1429, 0, 0))
    check(link.sub == nil and link.zone == "Elwynn Forest", "place without a subzone")
    check(ns.ParseTask("Reach level 30").lv == 30, "reach level")
    check(ns.ParseTask("ding 42").lv == 42, "ding")
    check(ns.ParseTask("Level 20 then hearth").lv == 20, "level at the start")
    check(ns.ParseTask("Buy 20 bread") == nil, "plain task has no link")
    check(ns.ParseTask("I hit level 3 yesterday") == nil, "level mid-sentence isn't a goal")
    check(ns.Plain("Get " .. ITEM .. " ||") == "Get [Linen Cloth] |", "plain text")
end

do
    check(ns.LastReset(1000000, 3600) == 1000000 + 3600 - 86400, "last reset from the game")
    local r = ns.LastReset(now, nil)
    local t = os.date("*t", r)
    check(t.hour == 0 and t.min == 0 and r <= now and now - r < 86400, "fallback reset is local midnight")
    local page, item = { kind = "list" }, { text = "x" }
    check(not ns.IsDone(page, item, "A", 100), "not done")
    ns.SetDone(page, item, "A", true, 150)
    check(ns.IsDone(page, item, "A", 100) and ns.IsDone(page, item, "B", 100), "shared done")
    item.daily = true
    check(not ns.IsDone(page, item, "A", 200), "daily done before the reset is open again")
    page.each = true
    item.done = nil
    ns.SetDone(page, item, "A", true, 250)
    check(ns.IsDone(page, item, "A", 200) and not ns.IsDone(page, item, "B", 200), "each character ticks its own")
    ns.SetDone(page, item, "A", false, 260)
    check(item.by == nil, "empty per-character table dropped")
end

do
    local db = { pages = {
        [1] = { id = 1, kind = "list", items = {
            { text = "once old", done = 50 }, { text = "once new", done = 150 }, { text = "daily", daily = true, done = 50 },
            { text = "open" } } },
        [2] = { id = 2, kind = "list", keep = true, items = { { text = "kept", done = 50 } } },
        [3] = { id = 3, kind = "list", each = true, items = { { text = "each", by = { A = 50 } } } },
    } }
    check(ns.Sweep(db, 100) == 1, "sweep removes one")
    check(#db.pages[1].items == 3 and db.pages[1].items[1].text == "once new", "sweep keeps new, daily and open")
    check(#db.pages[2].items == 1 and #db.pages[3].items == 1, "keep and each lists untouched")
end

do
    local me, other = "A", "B"
    local db = { folders = {}, pages = {} }
    db.folders[1] = { id = 1, name = "Quests", open = true }
    db.folders[2] = { id = 2, name = "Elwynn", parent = 1, open = false }
    db.folders[3] = { id = 3, name = "Alt stuff", char = other }
    db.pages[4] = { id = 4, kind = "list", title = "Today" }
    db.pages[5] = { id = 5, kind = "note", title = "Kobolds", folder = 2, text = "Bring " .. ITEM }
    db.pages[6] = { id = 6, kind = "note", title = "Secret", folder = 3, text = "" }
    db.pages[7] = { id = 7, kind = "note", title = "Wq", folder = 1, text = "" }
    local rows = ns.Tree(db, me)
    local names = {}
    for _, r in ipairs(rows) do names[#names + 1] = (r.page and r.page.title or r.folder.name) .. r.depth end
    check(table.concat(names, ",") == "Today0,Quests0,Wq1,Elwynn1", "tree order, closed folder, hidden folder: "
        .. table.concat(names, ","))
    check(#ns.Tree(db, me, { all = true }) == 5, "every character's things with all (their folder closed)")
    local found = ns.Search(db, "linen bring", function(p) return ns.PageShown(db, p, me) end)
    check(found[5] and not found[4], "search reads link labels")
    rows = ns.Tree(db, me, { match = found })
    check(#rows == 3 and rows[3].page and rows[3].page.id == 5, "search opens the way to a hit")
    check(not ns.PageShown(db, db.pages[6], me) and ns.PageShown(db, db.pages[6], other), "hidden by its folder")
    check(ns.Path(db, 2) == "Quests / Elwynn", "path")
    check(not ns.CanMoveFolder(db, 1, 2) and ns.CanMoveFolder(db, 2, nil) and ns.CanMoveFolder(db, 2, 3),
        "no folder inside itself")
    check(ns.MoveAmong(db, db.pages[7], false, -1) == false, "first can't go up")
    db.pages[8] = { id = 8, kind = "note", title = "Second", folder = 1, text = "" }
    check(ns.MoveAmong(db, db.pages[8], false, -1) and db.pages[8].order < db.pages[7].order, "move up")
    check(ns.DeleteFolder(db, 1) == 3 and db.folders[2].parent == nil and db.pages[7].folder == nil,
        "deleting a folder moves its things up")
end

---------------------------------------------------------------------------
-- Part 2: the whole addon
---------------------------------------------------------------------------
events.PLAYER_LOGIN.scripts.OnEvent(events.PLAYER_LOGIN, "PLAYER_LOGIN")
local db = EzNotebookDB
local function fire(e, ...) events[e].scripts.OnEvent(events[e], e, ...) end
local function lastPrint() return printed[#printed] or "" end

check(db.seeded and db.pages[db.inbox] and db.pages[db.inbox].title == "Today", "seeded Today list")
local today = db.pages[db.inbox]
local welcome
for _, p in pairs(db.pages) do if p.kind == "note" then welcome = p end end
check(welcome and welcome.text:find("Shift%-click") and db.folders[welcome.folder].name == "Notes", "welcome note")
check(_G.EzNotebookIcon and _G.EzNotebookIcon:IsShown(), "launcher icon")

-- /todo and tasks ticking themselves
local function task(text)
    for _, item in ipairs(today.items) do if item.text:find(text, 1, true) then return item end end
end
local function done(text) return ns.IsDone(today, task(text), ns.me, ns.Reset()) end

SlashCmdList.EZNOTEBOOKTODO("Gather 20 " .. ITEM)
check(lastPrint():find("Added to Today"), "/todo confirms")
state.counts[2589] = 5
fire("BAG_UPDATE_DELAYED")
runTimers()
check(not done("Gather 20"), "5 of 20 isn't done")
check(ns.Progress(task("Gather 20")) == "5/20", "progress 5/20")
state.counts[2589] = 21
fire("BAG_UPDATE_DELAYED")
fire("BAG_UPDATE_DELAYED")
runTimers()
check(done("Gather 20") and lastPrint():find("Done:"), "21 of 20 ticks, with a chat line")

SlashCmdList.EZNOTEBOOKTODO("Turn in " .. QUEST)
check(not done("Turn in"), "quest open")
fire("QUEST_TURNED_IN", 999)
check(not done("Turn in"), "other quest doesn't tick it")
fire("QUEST_TURNED_IN", 123)
check(done("Turn in"), "quest turned in ticks")
state.done[77] = true
SlashCmdList.EZNOTEBOOKTODO("Old " .. ns.QuestLink(77, "Done Before"))
check(done("Old"), "a quest done before ticks as it's added")

SlashCmdList.EZNOTEBOOKTODO("Reach level 12")
check(not done("Reach level 12"), "level 10 isn't 12")
fire("PLAYER_LEVEL_UP", 12)
check(done("Reach level 12"), "level up ticks")

-- Dungeons
SlashCmdList.EZNOTEBOOKTODO("Run " .. ns.DungeonLink(36, "The Deadmines"))
SlashCmdList.EZNOTEBOOKTODO("Kill " .. ns.DungeonLink(36, "The Deadmines", 1002, "Sneed"))
state.inside, state.instance = true, { id = 36, name = "The Deadmines" }
fire("PLAYER_ENTERING_WORLD")
check(ns.char.run and ns.char.run.id == 36 and db.instances[36] == "The Deadmines", "run started, name learned")
fire("ENCOUNTER_END", 1001, "Rhahk'Zor", 1, 5, 0)
check(ns.char.run.kills == 0, "a wipe isn't a kill")
fire("ENCOUNTER_END", 1001, "Rhahk'Zor", 1, 5, 1)
check(ns.char.run.kills == 1 and db.bosses[36][1001] == "Rhahk'Zor", "boss kill counted and learned")
check(not done("Run ") and not done("Kill "), "nothing ticks inside yet")
fire("ENCOUNTER_END", 1002, "Sneed", 1, 5, 1)
check(done("Kill ") and not done("Run "), "picked boss ticks at once")
state.inside, state.instance, state.dead = false, nil, true
fire("PLAYER_ENTERING_WORLD")
check(not done("Run ") and ns.char.run, "released as a ghost: run waits")
state.dead = false
fire("ZONE_CHANGED_NEW_AREA")
check(done("Run ") and ns.char.run == nil, "out alive with a boss down: run ticks")

-- Places: never on the spot it was made, only on walking in
SlashCmdList.EZNOTEBOOKTODO("Visit " .. ns.HereLink())
runTimers()
check(not done("Visit"), "made here, not ticked")
state.sub = "Northshire"
fire("ZONE_CHANGED")
state.sub = "Goldshire"
fire("ZONE_CHANGED")
check(done("Visit"), "walking back in ticks")

-- Daily tasks and the reset
local daily = ns.AddTask(today, "Cook fish", true)
ns.SetDone(today, daily, ns.me, true, now)
check(ns.IsDone(today, daily, ns.me, ns.Reset()), "daily done today")
local before = #today.items
now = now + 7 * 3600 -- past the reset (6 h away)
state.untilReset = 23 * 3600
check(not ns.IsDone(today, daily, ns.me, ns.Reset()), "daily open again after the reset")
runTimers(86400) -- the reset timer (and anything else waiting)
check(#today.items < before and task("Cook fish"), "reset swept done one-time tasks, kept the daily")

-- Someone else's page never ticks for us
local alt = ns.NewPage("list", "Alt list")
alt.char = "Player-1-0000BBBB"
ns.AddTask(alt, "Turn in " .. QUEST:gsub("123", "321"))
fire("QUEST_TURNED_IN", 321)
check(not alt.items[1].done, "hidden page doesn't tick")

---------------------------------------------------------------------------
-- The window
---------------------------------------------------------------------------
local menus, asks = {}, {}
local realMenu = ns.Menu
ns.Menu = function(entries)
    menus[#menus + 1] = entries
    return realMenu(entries)
end
ns.Ask = function(title, default, onOk)
    asks[#asks + 1] = { title = title, default = default, onOk = onOk }
end
local function pick(entries, text)
    for _, e in ipairs(entries) do
        if e.text and e.text:find(text, 1, true) and e.func then return e.func() end
    end
    check(false, "menu entry " .. text)
end

ns.Open(today.id)
local win = _G.EzNotebookFrame
check(win and win:IsShown(), "window opens")
runTimers()

-- Find our widgets by what they are.
local addBox, noteEdit
for _, f in ipairs(created) do
    if f.kind == "EditBox" and f.scripts.OnEnterPressed and f.scripts.OnReceiveDrag then addBox = f end
    if f.kind == "EditBox" and f.ezAfterInsert then noteEdit = f end
end
check(addBox and noteEdit, "found the add box and the note editor")

local n = #today.items
addBox:SetFocus()
addBox:SetText("Buy bread")
addBox.scripts.OnEnterPressed(addBox)
check(#today.items == n + 1 and today.items[#today.items].text == "Buy bread" and addBox:GetText() == "",
    "add box adds a task")

-- Shift-click while the add box has focus puts the link in it.
_G.ChatFrameUtil.InsertLink(QUEST)
_G.ChatEdit_InsertLink(QUEST) -- same click through the alias: only once
check(addBox:GetText() == QUEST, "shift-click inserts once: " .. addBox:GetText())
addBox:SetText("")
state.cursor = { id = 2589, link = ITEM }
addBox.scripts.OnReceiveDrag(addBox)
check(addBox:GetText() == ITEM and state.cursor == nil, "dropped item goes in")
addBox:SetText("")
addBox:ClearFocus()

-- Notes: open the welcome note, click to edit, type, insert a link, Done.
ns.SelectPage(welcome.id)
local noteChild
for _, f in ipairs(created) do
    if f.kind == "Frame" and f.scripts.OnHyperlinkClick and f.scripts.OnMouseUp and f.index == nil and f.check == nil then
        noteChild = f
    end
end
check(noteChild ~= nil, "note view found")
noteChild.scripts.OnHyperlinkClick(noteChild, "item:2589", "[Linen Cloth]", "LeftButton")
noteChild.scripts.OnMouseUp(noteChild, "LeftButton")
runTimers()
check(not noteEdit:HasFocus(), "clicking a link doesn't start editing")
now = now + 1
noteChild.scripts.OnMouseUp(noteChild, "LeftButton")
runTimers()
check(noteEdit:HasFocus() and noteEdit:GetText() == welcome.text, "click on the note edits it")
noteEdit:SetText(welcome.text .. "\nMy line")
noteEdit.scripts.OnTextChanged(noteEdit, true)
check(welcome.text:find("My line$"), "typing saves")
_G.ChatFrameUtil.InsertLink(ITEM)
check(welcome.text:find("Linen Cloth", 1, true), "shift-click into the note saves")
noteEdit.scripts.OnEscapePressed(noteEdit)
check(not noteEdit:HasFocus(), "escape leaves editing")

-- Tree menus: delete a folder (its note moves up), page options.
local treeRow
for _, f in ipairs(created) do
    if f.kind == "Button" and f.folder then treeRow = f end
end
check(treeRow and treeRow.folder.name == "Notes", "folder row drawn")
treeRow.scripts.OnClick(treeRow, "RightButton")
pick(menus[#menus], "Delete folder")
pick(menus[#menus], "Yes")
check(not next(db.folders) and welcome.folder == nil, "folder deleted, note kept at the top")

local pageRow
for _, f in ipairs(created) do
    if f.kind == "Button" and f.page == today and f.shown then pageRow = f end
end
check(pageRow ~= nil, "Today row drawn")
pageRow.scripts.OnClick(pageRow, "RightButton")
pick(menus[#menus], "Only Olizzy")
check(today.char == ns.me and today.charName == "Olizzy", "only this character")
pageRow.scripts.OnClick(pageRow, "RightButton")
pick(menus[#menus], "Pin to the screen")
check(_G.EzNotebookPin and _G.EzNotebookPin:IsShown() and db.pinned == today.id, "pinned")

-- New list from the button, via the name prompt.
for _, f in ipairs(created) do
    if f.kind == "Button" and f.text and f.text.text == "+ List" then f.scripts.OnClick(f, "LeftButton") end
end
check(#asks > 0, "name asked")
asks[#asks].onOk("Dungeon goals")
local sel = db.pages[ns.char.sel]
check(sel and sel.kind == "list" and sel.title == "Dungeon goals", "new list made and opened")

-- Task row: right-click > Daily
ns.AddTask(sel, "Heroic stuff")
ns.RedrawWindow()
local taskRow
for _, f in ipairs(created) do
    if f.item and f.item.text == "Heroic stuff" then taskRow = f end
end
check(taskRow ~= nil, "task row drawn")
taskRow.scripts.OnMouseUp(taskRow, "RightButton")
runTimers()
pick(menus[#menus], "Daily")
check(sel.items[1].daily == true, "task made daily")
taskRow.scripts.OnMouseUp(taskRow, "LeftButton")
runTimers()
check(ns.IsDone(sel, sel.items[1], ns.me, ns.Reset()), "clicking a task ticks it")

-- Search and slash
SlashCmdList.EZNOTEBOOK("find kobold")
check(win:IsShown(), "search opens the window")
SlashCmdList.EZNOTEBOOK("notify off")
check(db.notify == false, "notify off")
SlashCmdList.EZNOTEBOOK("new folder Raids")
local raids
for _, f in pairs(db.folders) do if f.name == "Raids" then raids = f end end
check(raids ~= nil, "/nb new folder")
SlashCmdList.EZNOTEBOOK("pin")
check(db.pinned ~= today.id, "/nb pin moves or clears the pin")
_G.EzNotebook_AddTask("down")
_G.EzNotebook_AddTask("up")
check(addBox:HasFocus(), "add-task key focuses the add box on release")
SlashCmdList.EZNOTEBOOK("help")
SlashCmdList.EZNOTEBOOK("reset")

print(("%d checks, %d failed"):format(checks, failed))
if failed > 0 then os.exit(1) end
