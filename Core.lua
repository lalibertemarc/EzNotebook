-- Saved data, events and the tasks that tick themselves; link insertion while typing in our boxes; link clicks;
-- slash commands and key bindings. Never sends chat.
local addonName, ns = ...

local db, char

function ns.Print(msg)
    DEFAULT_CHAT_FRAME:AddMessage(ns.PREFIX .. msg)
end

local function IsSecret(v)
    return issecretvalue and issecretvalue(v) or false
end

---------------------------------------------------------------------------
-- Time
---------------------------------------------------------------------------
function ns.UntilReset()
    if C_DateAndTime and C_DateAndTime.GetSecondsUntilDailyReset then
        local ok, s = pcall(C_DateAndTime.GetSecondsUntilDailyReset)
        if ok and type(s) == "number" and s > 0 then return s end
    end
    if GetQuestResetTime then
        local s = GetQuestResetTime()
        if type(s) == "number" and s > 0 then return s end
    end
end

function ns.Reset()
    return ns.LastReset(time(), ns.UntilReset())
end

---------------------------------------------------------------------------
-- Game reads (each guarded: Forever is Mainline's API, Era the old one)
---------------------------------------------------------------------------
function ns.QuestDone(id)
    if C_QuestLog and C_QuestLog.IsQuestFlaggedCompleted then return C_QuestLog.IsQuestFlaggedCompleted(id) end
    if IsQuestFlaggedCompleted then return IsQuestFlaggedCompleted(id) end
    return false
end

function ns.OnQuest(id)
    if C_QuestLog and C_QuestLog.IsOnQuest then return C_QuestLog.IsOnQuest(id) end
    if GetQuestLogIndexByID then return (GetQuestLogIndexByID(id) or 0) > 0 end
    return false
end

function ns.ItemCount(id)
    local count = (C_Item and C_Item.GetItemCount) or GetItemCount
    return count and count(id, true) or 0
end

function ns.Level()
    return UnitLevel("player") or 1
end

-- Quests in your log (open headers only in Era): { id, title, level }.
function ns.QuestLog()
    local out = {}
    if C_QuestLog and C_QuestLog.GetInfo and C_QuestLog.GetNumQuestLogEntries then
        for i = 1, C_QuestLog.GetNumQuestLogEntries() do
            local info = C_QuestLog.GetInfo(i)
            if info and not info.isHeader and not info.isHidden and info.questID and info.title then
                out[#out + 1] = { id = info.questID, title = info.title, level = info.level }
            end
        end
    elseif GetNumQuestLogEntries and GetQuestLogTitle then
        for i = 1, GetNumQuestLogEntries() do
            local title, level, _, isHeader, _, _, _, id = GetQuestLogTitle(i)
            if title and not isHeader and id then out[#out + 1] = { id = id, title = title, level = level } end
        end
    end
    return out
end

-- A quest's link: Blizzard's where it makes one (Forever), else ours.
function ns.MakeQuestLink(id, title)
    if GetQuestLink then
        local ok, link = pcall(GetQuestLink, id)
        if ok and type(link) == "string" and link ~= "" then return link end
    end
    return ns.QuestLink(id, title)
end

function ns.Here()
    local zone = GetRealZoneText and GetRealZoneText() or GetZoneText()
    local sub = GetSubZoneText and GetSubZoneText() or ""
    local map = C_Map and C_Map.GetBestMapForUnit and C_Map.GetBestMapForUnit("player")
    local x, y
    if map and C_Map.GetPlayerMapPosition then
        local pos = C_Map.GetPlayerMapPosition(map, "player")
        if pos then x, y = pos:GetXY() end
    end
    return zone, sub, map, x, y
end

function ns.HereLink()
    local zone, sub, map, x, y = ns.Here()
    if not zone or zone == "" then return end
    return ns.PlaceLink(zone, sub, map, x, y)
end

-- Dungeons for the picker: ours (minus Forever's in Era) + any instance you entered that we don't list.
function ns.DungeonList()
    local out, seen = {}, {}
    for _, d in ipairs(ns.DUNGEONS) do
        if not (ns.ERA and d.forever) then
            out[#out + 1] = { id = d.id, name = db.instances[d.id] or d.name, raid = d.raid }
            seen[d.id] = true
        end
    end
    for id, name in pairs(db.instances) do
        if not seen[id] then out[#out + 1] = { id = id, name = name, learned = true } end
    end
    return out
end

-- Bosses you've killed there: { id, name }, by name.
function ns.Bosses(id)
    local out = {}
    for enc, name in pairs(db.bosses[id] or {}) do out[#out + 1] = { id = enc, name = name } end
    table.sort(out, function(a, b) return a.name < b.name end)
    return out
end

function ns.DungeonName(id)
    if db.instances[id] then return db.instances[id] end
    for _, d in ipairs(ns.DUNGEONS) do
        if d.id == id then return d.name end
    end
    return "Dungeon " .. id
end

-- A task's live state for its row: "12/20", "lv 23/30", "in your log".
function ns.Progress(item)
    local link = item.link
    if not link then return end
    if link.k == "item" and item.goal then
        return ("%d/%d"):format(math.min(ns.ItemCount(link.id), ns.MAX_GOAL), item.goal)
    elseif link.k == "level" then
        return ("lv %d/%d"):format(ns.Level(), link.lv)
    elseif link.k == "quest" and ns.OnQuest(link.id) then
        return "in your log"
    end
end

---------------------------------------------------------------------------
-- Pages, folders, tasks
---------------------------------------------------------------------------
function ns.NewFolder(name, parent)
    local id = ns.NewId(db)
    local f = { id = id, name = ns.OneLine(name), parent = parent, open = true, order = id }
    db.folders[id] = f
    return f
end

function ns.NewPage(kind, title, folder)
    local id = ns.NewId(db)
    local p = { id = id, kind = kind, title = ns.OneLine(title), folder = folder, order = id, t = time(),
        edited = time() }
    if kind == "list" then p.items = {} else p.text = "" end
    db.pages[id] = p
    if folder and db.folders[folder] then db.folders[folder].open = true end
    return p
end

-- Is it already done? (A quest turned in before, enough of the item, the level reached.) Places only tick
-- when you walk in and dungeons when you clear them.
function ns.Met(link, item)
    if link.k == "quest" then return ns.QuestDone(link.id) end
    if link.k == "item" then return item.goal ~= nil and ns.ItemCount(link.id) >= item.goal end
    if link.k == "level" then return ns.Level() >= link.lv end
    return false
end

function ns.AddTask(page, text, daily)
    text = ns.OneLine(text)
    if text == "" then return end
    local link, goal = ns.ParseTask(text)
    local item = { id = ns.NewId(db), text = text, link = link, goal = goal, daily = daily or nil }
    page.items = page.items or {}
    page.items[#page.items + 1] = item
    page.edited = time()
    if link and ns.Met(link, item) then ns.SetDone(page, item, ns.me, true, time()) end
    return item
end

-- The list /todo adds to: the one you set, else the first list called Today, else a new one.
function ns.Inbox()
    local p = db.inbox and db.pages[db.inbox]
    if p and p.kind == "list" and ns.PageShown(db, p, ns.me) then return p end
    for _, page in pairs(db.pages) do
        if page.kind == "list" and page.title == "Today" and ns.PageShown(db, page, ns.me) then
            db.inbox = page.id
            return page
        end
    end
    p = ns.NewPage("list", "Today")
    db.inbox = p.id
    return p
end

local function Seed()
    local today = ns.NewPage("list", "Today")
    db.inbox = today.id
    local notes = ns.NewFolder("Notes")
    local welcome = ns.NewPage("note", ns.WELCOME_TITLE, notes.id)
    welcome.text = ns.WELCOME
    db.seeded = true
    char.sel = today.id
end

function ns.Refresh()
    if ns.RedrawWindow then ns.RedrawWindow() end
    if ns.RedrawPin then ns.RedrawPin() end
end

---------------------------------------------------------------------------
-- Ticking by itself
---------------------------------------------------------------------------
function ns.Tick(test)
    if not db then return 0 end
    local list = ns.Tickable(db, ns.me, ns.Reset(), test)
    local now = time()
    for _, e in ipairs(list) do
        ns.SetDone(e.page, e.item, ns.me, true, now)
        if db.notify then
            ns.Print(("|cff66dd66Done:|r %s |cff999999(%s)|r"):format(e.item.text, e.page.title))
        end
    end
    if #list > 0 then ns.Refresh() end
    return #list
end

function ns.CheckAll()
    return ns.Tick(function(link, item) return ns.Met(link, item) end)
end

local lastZone, lastSub
local function CheckPlace()
    local zone = GetRealZoneText and GetRealZoneText() or GetZoneText()
    local sub = GetSubZoneText and GetSubZoneText() or ""
    if IsSecret(zone) or IsSecret(sub) then return end
    if zone == lastZone and sub == lastSub then return end
    local first = lastZone == nil
    lastZone, lastSub = zone, sub
    if first then return end -- logging in where a place task points isn't walking in
    ns.Tick(function(link) return link.k == "place" and ns.PlaceMatch(link, zone, sub) end)
end

-- Dungeon runs: char.run = { id, name, kills, t } survives a /reload inside.
local RUN_KEEP = 3 * 3600

local function FinishRun(run)
    if run.kills > 0 then
        ns.Tick(function(link) return link.k == "dungeon" and link.id == run.id and not link.boss end)
    end
end

local function CheckInstance()
    local run = char.run
    if run and time() - (run.t or 0) > RUN_KEEP then
        char.run, run = nil, nil
    end
    local inside, kind = IsInInstance()
    local id, name
    if inside and (kind == "party" or kind == "raid") then
        local n, _, _, _, _, _, _, i = GetInstanceInfo()
        if not IsSecret(i) then id = i end
        if not IsSecret(n) then name = n end
    end
    if id then
        if name then db.instances[id] = name end
        if run and run.id ~= id then
            FinishRun(run)
            run = nil
        end
        if not run then char.run = { id = id, name = name, kills = 0, t = time() } end
        char.run.t = time()
    elseif run and not UnitIsDeadOrGhost("player") then
        -- Out and alive: the run is over. (Released as a ghost: wait, you're likely running back in.)
        FinishRun(run)
        char.run = nil
    end
end

local function OnEncounter(encounterID, encounterName, success)
    if not (success == 1 or success == true) then return end
    local run = char.run
    if not run then return end
    run.kills = run.kills + 1
    run.t = time()
    if IsSecret(encounterID) then return end
    if encounterName and not IsSecret(encounterName) then
        db.bosses[run.id] = db.bosses[run.id] or {}
        db.bosses[run.id][encounterID] = encounterName
    end
    ns.Tick(function(link) return link.k == "dungeon" and link.id == run.id and link.boss == encounterID end)
end

-- The daily reset while you play: sweep, redraw, wait for the next one.
local resetToken = 0
local function ScheduleReset()
    resetToken = resetToken + 1
    local token = resetToken
    local s = ns.UntilReset() or 3600
    C_Timer.After(math.min(s + 3, 86400), function()
        if token ~= resetToken then return end
        ns.Sweep(db, ns.Reset())
        ns.Refresh()
        ScheduleReset()
    end)
end

---------------------------------------------------------------------------
-- Links while typing in our boxes: Shift-click (Blizzard's InsertLink, hooked after it runs) or drop an item
---------------------------------------------------------------------------
local lastLink, lastAt
local function Insert(text)
    local box = ns.focus
    if type(text) ~= "string" or text == "" or not box or not box:HasFocus() or not box:IsVisible() then return end
    local at = GetTime()
    if text == lastLink and at == lastAt then return end -- hooked twice (Era's alias)
    lastLink, lastAt = text, at
    box:Insert(text)
    if box.ezAfterInsert then box.ezAfterInsert(box) end
end

local function HookInsert()
    local util = ChatFrameUtil and ChatFrameUtil.InsertLink
    local alias = ChatEdit_InsertLink
    if util then hooksecurefunc(ChatFrameUtil, "InsertLink", Insert) end
    if alias and alias ~= util then hooksecurefunc("ChatEdit_InsertLink", Insert) end
end

-- An item (or spell) let go over one of our boxes: its link goes in at the cursor.
function ns.Drop(box)
    local kind, a, b, c = GetCursorInfo()
    local link
    if kind == "item" then
        link = b
    elseif kind == "spell" then
        local id = c or a
        local get = (C_Spell and C_Spell.GetSpellLink) or GetSpellLink
        if get and type(id) == "number" then link = get(id) end
    end
    if not link then return false end
    ClearCursor()
    box:SetFocus()
    box:Insert(link)
    if box.ezAfterInsert then box.ezAfterInsert(box) end
    return true
end

---------------------------------------------------------------------------
-- Clicking and hovering links in our pages
---------------------------------------------------------------------------
local function OwnTooltip(tip, link)
    local kind, f = ns.ParseLink(link)
    if kind == "quest" and link:find("^addon:") then
        tip:AddLine(f.id and ("Quest %d"):format(f.id) or "Quest", 1, 0.82, 0)
        if f.id and ns.QuestDone(f.id) then
            tip:AddLine("Turned in on this character", 0.4, 0.87, 0.4)
        elseif f.id and ns.OnQuest(f.id) then
            tip:AddLine("In your quest log", 1, 1, 1)
        end
        return true
    elseif kind == "dungeon" then
        tip:AddLine(ns.DungeonName(f.id), 1, 0.62, 0.36)
        local bosses = ns.Bosses(f.id)
        if f.boss then
            tip:AddLine("Ticks when this boss dies", 1, 1, 1)
        else
            tip:AddLine("Ticks when you leave it with a boss down", 1, 1, 1)
        end
        if #bosses > 0 then
            local names = {}
            for _, b in ipairs(bosses) do names[#names + 1] = b.name end
            tip:AddLine("Bosses you've killed here: " .. table.concat(names, ", "), 0.7, 0.7, 0.7, true)
        end
        return true
    elseif kind == "place" then
        tip:AddLine(f.sub and (f.sub .. ", " .. f.zone) or f.zone, 0.5, 0.82, 1)
        if f.x and f.x > 0 then tip:AddLine(("%.1f, %.1f"):format(f.x * 100, f.y * 100), 1, 1, 1) end
        tip:AddLine(ns.CanWaypoint(f) and "Click: map pin" or "Ticks when you walk in", 0.7, 0.7, 0.7)
        return true
    end
end

function ns.CanWaypoint(f)
    return f.map and f.map > 0 and f.x and f.x > 0 and C_Map and C_Map.SetUserWaypoint and UiMapPoint
        and C_Map.CanSetUserWaypointOnMap and C_Map.CanSetUserWaypointOnMap(f.map)
end

function ns.LinkEnter(owner, link)
    GameTooltip:SetOwner(owner, "ANCHOR_CURSOR")
    if not OwnTooltip(GameTooltip, link) then
        if not pcall(GameTooltip.SetHyperlink, GameTooltip, link) then return GameTooltip:Hide() end
    end
    GameTooltip:Show()
end

function ns.LinkLeave()
    GameTooltip:Hide()
end

-- Blizzard links open in ItemRefTooltip as its own SetItemRef does (the same link again closes it); Shift-click
-- while typing in chat passes the link on. Ours: a map pin for places, a tooltip for the rest.
local refShown
function ns.LinkClick(link, text)
    if IsModifiedClick and IsModifiedClick("CHATLINK") then
        local put = (ChatFrameUtil and ChatFrameUtil.InsertLink) or ChatEdit_InsertLink
        if put and text and put(text) then return end
    end
    local kind, f = ns.ParseLink(link)
    if kind == "place" and ns.CanWaypoint(f) then
        C_Map.SetUserWaypoint(UiMapPoint.CreateFromCoordinates(f.map, f.x, f.y))
        if C_SuperTrack and C_SuperTrack.SetSuperTrackedUserWaypoint then
            C_SuperTrack.SetSuperTrackedUserWaypoint(true)
        end
        return ns.Print(("Map pin set: %s."):format(f.sub or f.zone))
    end
    local tip = ItemRefTooltip
    if not tip then return end
    if tip:IsShown() and refShown == link then
        tip:Hide()
        return
    end
    tip:SetOwner(UIParent, "ANCHOR_PRESERVE") -- also forgets the shown link
    if not OwnTooltip(tip, link) then
        local set = tip.ItemRefSetHyperlink or tip.SetHyperlink
        if not pcall(set, tip, link) then return end
    end
    tip:Show()
    refShown = link
end

---------------------------------------------------------------------------
-- Slash commands
---------------------------------------------------------------------------
local function OnOff(arg, current)
    if arg == "on" then return true elseif arg == "off" then return false end
    return not current
end

local HELP = {
    "/nb - open or close the notebook (also /notebook)",
    "/todo <task> - add a task to your Today list; /todo alone opens it",
    "/nb new note|list|folder <name> - make one",
    "/nb find <words> - search every page",
    "/nb pin - pin the open list to the screen (again: unpin)",
    "/nb notify [on|off] - a chat line when a task ticks itself",
    "/nb icon [on|off] - the launcher icon above the chat",
    "/nb reset - put the window, icon and pin back in place",
}

local function Slash(msg)
    msg = ns.Trim(msg)
    local cmd, rest = msg:match("^(%S*)%s*(.-)$")
    cmd = cmd:lower()
    if cmd == "" then
        return ns.Toggle()
    elseif cmd == "help" or cmd == "?" then
        for _, line in ipairs(HELP) do ns.Print(line) end
    elseif cmd == "todo" or cmd == "add" then
        return ns.TodoSlash(rest)
    elseif cmd == "new" then
        local kind, name = rest:match("^(%S*)%s*(.-)$")
        kind = kind:lower()
        if kind ~= "note" and kind ~= "list" and kind ~= "folder" then
            return ns.Print("/nb new note|list|folder <name>")
        end
        if name == "" then name = kind == "folder" and "New folder" or (kind == "note" and "New note" or "New list") end
        if kind == "folder" then
            ns.NewFolder(name)
            ns.Open()
        else
            ns.Open(ns.NewPage(kind, name).id)
        end
    elseif cmd == "find" or cmd == "search" then
        ns.Open(nil, rest)
    elseif cmd == "pin" then
        ns.TogglePin()
    elseif cmd == "notify" then
        db.notify = OnOff(rest:lower(), db.notify)
        ns.Print("Chat line when a task ticks itself: " .. (db.notify and "on" or "off"))
    elseif cmd == "icon" then
        db.icon = OnOff(rest:lower(), db.icon)
        if ns.UpdateIcon then ns.UpdateIcon() end
        ns.Print("Launcher icon: " .. (db.icon and "shown" or "hidden"))
    elseif cmd == "reset" then
        db.win, db.iconPos, db.pinPos = nil, nil, nil
        if ns.PlaceWindow then ns.PlaceWindow() end
        if ns.UpdateIcon then ns.UpdateIcon() end
        if ns.PlacePin then ns.PlacePin() end
        ns.Print("Window, icon and pin are back in place.")
    else
        ns.Open(nil, msg) -- anything else: search for it
    end
end

function ns.TodoSlash(text)
    local page = ns.Inbox()
    if ns.Trim(text) == "" then return ns.Open(page.id) end
    local item = ns.AddTask(page, text)
    ns.Print(("Added to %s: %s"):format(page.title, item.text))
    ns.Refresh()
end

---------------------------------------------------------------------------
-- Globals for bindings and the addon drawer
---------------------------------------------------------------------------
BINDING_HEADER_EZNOTEBOOK = "EzNotebook"
BINDING_NAME_EZNOTEBOOK_TOGGLE = "Open or close the notebook"
BINDING_NAME_EZNOTEBOOK_ADD = "Add a task to Today"

function EzNotebook_Toggle()
    ns.Toggle()
end

-- runOnUp: opens on the key's release, so its letter doesn't land in the task box.
function EzNotebook_AddTask(keystate)
    if keystate ~= "up" then return end
    ns.Open(ns.Inbox().id, nil, true)
end

function EzNotebook_OnAddonCompartmentClick()
    ns.Toggle()
end

---------------------------------------------------------------------------
-- Events
---------------------------------------------------------------------------
local bagPending = false
local events = CreateFrame("Frame")
events:RegisterEvent("PLAYER_LOGIN")
events:SetScript("OnEvent", function(_, event, a, b, _, _, e)
    if event == "PLAYER_LOGIN" then
        EzNotebookDB = EzNotebookDB or {}
        EzNotebookCharDB = EzNotebookCharDB or {}
        db, char = EzNotebookDB, EzNotebookCharDB
        ns.db, ns.char = db, char
        db.folders = db.folders or {}
        db.pages = db.pages or {}
        db.instances = db.instances or {}
        db.bosses = db.bosses or {}
        if db.notify == nil then db.notify = true end
        if db.icon == nil then db.icon = true end
        ns.me = UnitGUID("player") or UnitName("player")
        ns.myName = UnitName("player")
        if not db.seeded then Seed() end
        ns.Sweep(db, ns.Reset())
        HookInsert()
        ScheduleReset()
        SLASH_EZNOTEBOOK1, SLASH_EZNOTEBOOK2 = "/nb", "/notebook"
        SlashCmdList.EZNOTEBOOK = Slash
        SLASH_EZNOTEBOOKTODO1 = "/todo"
        SlashCmdList.EZNOTEBOOKTODO = ns.TodoSlash
        if ns.Login then ns.Login() end
        for _, ev in ipairs({ "PLAYER_ENTERING_WORLD", "QUEST_TURNED_IN", "ENCOUNTER_END", "BAG_UPDATE_DELAYED",
            "PLAYER_LEVEL_UP", "ZONE_CHANGED", "ZONE_CHANGED_INDOORS", "ZONE_CHANGED_NEW_AREA" }) do
            events:RegisterEvent(ev)
        end
    elseif event == "PLAYER_ENTERING_WORLD" then
        CheckInstance()
        CheckPlace()
        C_Timer.After(3, ns.CheckAll) -- quest completion data settles after the loading screen
    elseif event == "QUEST_TURNED_IN" then
        local id = a
        if IsSecret(id) then return end
        ns.Tick(function(link) return link.k == "quest" and link.id == id end)
    elseif event == "ENCOUNTER_END" then
        OnEncounter(a, b, e)
    elseif event == "BAG_UPDATE_DELAYED" then
        if bagPending then return end
        bagPending = true
        C_Timer.After(1, function()
            bagPending = false
            ns.Tick(function(link, item)
                return link.k == "item" and item.goal ~= nil and ns.ItemCount(link.id) >= item.goal
            end)
            ns.Refresh() -- counts on rows
        end)
    elseif event == "PLAYER_LEVEL_UP" then
        local level = tonumber(a) or ns.Level()
        ns.Tick(function(link) return link.k == "level" and link.lv <= level end)
    else -- zone changes
        CheckPlace()
        if event == "ZONE_CHANGED_NEW_AREA" then CheckInstance() end
    end
end)

ns.addonName = addonName
