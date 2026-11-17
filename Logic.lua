-- Rules with no game API (tests/notebook.lua runs them in plain Lua 5.1): the folder tree, who sees what,
-- links, reading a typed task, done/daily state, the daily sweep and search.
--
-- Saved shape (account, EzNotebookDB):
--   folders[id] = { id, name, parent = folder id|nil, color = ns.COLORS key|nil, char = GUID|nil, charName,
--                   open, order }
--   pages[id]   = { id, kind = "note"|"list", title, folder, char, charName, order, t, edited,
--                   text (note), items (list), keep (done one-time tasks stay past the reset),
--                   each (every character ticks its own) }
--   item        = { id, text, link = { k = "quest"|"item"|"dungeon"|"level", ... }, goal, daily,
--                   done = time|nil, by = { [GUID] = time } (each pages) }
-- `char` set = only that character sees it (GUID: stable, unlike names); `charName` is for showing.
local _, ns = ...

local date = date or os.date

function ns.NewId(db)
    db.nextId = (db.nextId or 0) + 1
    return db.nextId
end

---------------------------------------------------------------------------
-- Text
---------------------------------------------------------------------------
function ns.Trim(s)
    return (s or ""):match("^%s*(.-)%s*$")
end

function ns.OneLine(s)
    return ns.Trim((s or ""):gsub("[\r\n]+", " "))
end

-- What a line reads as: colours, textures and link codes out, link labels kept ("[Linen Cloth]").
function ns.Plain(text)
    local s = text or ""
    s = s:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")
    s = s:gsub("|H.-|h(.-)|h", "%1")
    s = s:gsub("|T.-|t", ""):gsub("|A.-|a", "")
    s = s:gsub("||", "|")
    return s
end

---------------------------------------------------------------------------
-- Links. Blizzard's own (quest, item, spell…) stay as they are; ours are addon links only EzNotebook reads:
-- |Haddon:EzNotebook:<kind>:<args>|h[label]|h
---------------------------------------------------------------------------
local function Enc(s)
    return (tostring(s or ""):gsub("%%", "%%25"):gsub(":", "%%3A"):gsub("|", ""))
end

local function Dec(s)
    return (s:gsub("%%3A", ":"):gsub("%%25", "%%"))
end

local function Label(s)
    return (tostring(s or "?"):gsub("[%[%]|]", ""))
end

function ns.AddonLink(kind, args, label)
    return ("|cff%s|Haddon:EzNotebook:%s:%s|h[%s]|h|r"):format(ns.LINK_COLORS[kind] or "ffffff", kind, args,
        Label(label))
end

-- Era's quest log has no quest links: ours stands in.
function ns.QuestLink(id, name)
    return ns.AddonLink("quest", tostring(id), name)
end

function ns.DungeonLink(id, name, boss, bossName)
    local label = name
    if boss and bossName then label = name .. ": " .. bossName end
    return ns.AddonLink("dungeon", ("%d:%d"):format(id, boss or 0), label)
end

-- x, y as map fractions (0-1); kept to 0.1%.
function ns.PlaceLink(zone, sub, map, x, y)
    local label = (sub and sub ~= "" and sub ~= zone) and (sub .. ", " .. zone) or zone
    local args = ("%d:%d:%d:%s:%s"):format(map or 0, math.floor((x or 0) * 1000 + 0.5),
        math.floor((y or 0) * 1000 + 0.5), Enc(zone), Enc(sub ~= zone and sub or ""))
    return ns.AddonLink("place", args, label)
end

-- A hyperlink's target ("quest:123:20", "addon:EzNotebook:dungeon:36:0") → kind, fields.
function ns.ParseLink(link)
    if not link then return end
    local kind, rest = link:match("^addon:EzNotebook:(%a+):?(.*)$")
    if kind == "quest" then
        return "quest", { id = tonumber(rest:match("^(%d+)")) }
    elseif kind == "dungeon" then
        local id, boss = rest:match("^(%d+):(%d+)")
        boss = tonumber(boss)
        return "dungeon", { id = tonumber(id), boss = boss ~= 0 and boss or nil }
    elseif kind == "place" then
        local map, x, y, zone, sub = rest:match("^(%d+):(%d+):(%d+):([^:]*):?([^:]*)")
        if not map then return end
        return "place", { map = tonumber(map), x = tonumber(x) / 1000, y = tonumber(y) / 1000, zone = Dec(zone),
            sub = sub ~= "" and Dec(sub) or nil }
    elseif kind then
        return kind, {}
    end
    local t, id = link:match("^(%a+):(%d+)")
    return t or link:match("^(%a+)"), { id = tonumber(id) }
end

-- The label of the first link whose target starts with `prefix`, and the link's target.
local function Find(text, prefix)
    local s = text:find("|H" .. prefix, 1, true)
    if not s then return end
    local target, label = text:match("|H([^|]+)|h%[?(.-)%]?|h", s)
    return target, label
end

-- What a typed task links to: quest > dungeon > item (with a count) > "reach level N". A marked spot (place
-- link) is only a bookmark: it never makes a task tick, so it isn't read here.
-- Returns the link table or nil, and the item goal if any.
function ns.ParseTask(text)
    text = text or ""
    local target, label = Find(text, "quest:")
    if not target then target, label = Find(text, "addon:EzNotebook:quest:") end
    if target then
        local _, f = ns.ParseLink(target)
        if f and f.id then return { k = "quest", id = f.id, name = label } end
    end
    target, label = Find(text, "addon:EzNotebook:dungeon:")
    if target then
        local _, f = ns.ParseLink(target)
        if f and f.id then
            local name, bossName = label:match("^(.-): (.+)$")
            return { k = "dungeon", id = f.id, boss = f.boss, name = f.boss and name or label,
                bossName = f.boss and bossName or nil }
        end
    end
    -- Words around the links, for a count or a level.
    local rest = text:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""):gsub("|H.-|h.-|h", " ")
    target, label = Find(text, "item:")
    if target then
        local id = tonumber(target:match("^item:(%d+)"))
        if id then
            local n = tonumber(rest:match("(%d+)"))
            local goal = n and n >= 1 and math.min(n, ns.MAX_GOAL) or nil
            return { k = "item", id = id, name = label }, goal
        end
    end
    local lower = ns.Trim(rest:lower())
    local lv = lower:match("^reach level (%d+)") or lower:match("^get to level (%d+)") or lower:match("^level (%d+)")
        or lower:match("^ding (%d+)")
    lv = tonumber(lv)
    if lv and lv >= 2 and lv <= 100 then return { k = "level", lv = lv } end
end

---------------------------------------------------------------------------
-- Done and daily
---------------------------------------------------------------------------
-- The latest daily reset at or before `now`. untilNext = seconds to the next one from the game, else local
-- midnight.
function ns.LastReset(now, untilNext)
    if untilNext and untilNext > 0 and untilNext <= 86400 then
        return now + untilNext - 86400
    end
    local t = date("*t", now)
    return now - (t.hour * 3600 + t.min * 60 + t.sec)
end

function ns.Stamp(page, item, me)
    if page.each then return item.by and item.by[me] end
    return item.done
end

function ns.IsDone(page, item, me, reset)
    local t = ns.Stamp(page, item, me)
    if not t then return false end
    if item.daily then return t >= reset end
    return true
end

function ns.SetDone(page, item, me, on, now)
    if page.each then
        item.by = item.by or {}
        item.by[me] = on and now or nil
        if not next(item.by) then item.by = nil end
    else
        item.done = on and now or nil
    end
end

function ns.CountOpen(page, me, reset)
    local open, total = 0, 0
    for _, item in ipairs(page.items or {}) do
        total = total + 1
        if not ns.IsDone(page, item, me, reset) then open = open + 1 end
    end
    return open, total
end

-- At the reset: one-time tasks done before it go away, unless the list keeps them. "Each character" lists keep
-- theirs (one character's done isn't another's). Returns how many went.
function ns.Sweep(db, reset)
    local gone = 0
    for _, page in pairs(db.pages) do
        if page.kind == "list" and not page.keep and not page.each and page.items then
            for i = #page.items, 1, -1 do
                local item = page.items[i]
                if not item.daily and item.done and item.done < reset then
                    table.remove(page.items, i)
                    gone = gone + 1
                end
            end
        end
    end
    return gone
end

function ns.MoveItem(page, index, delta)
    local items = page.items
    local j = index + delta
    if not items[index] or not items[j] then return false end
    items[index], items[j] = items[j], items[index]
    return true
end

---------------------------------------------------------------------------
-- Who sees what
---------------------------------------------------------------------------
function ns.Mine(obj, me)
    return not obj.char or obj.char == me
end

-- A folder shows when it and every folder above it are yours (or shared).
function ns.FolderShown(db, id, me)
    local guard = 0
    while id and guard < 64 do
        local f = db.folders[id]
        if not f then return true end -- lost parent: treat as the top
        if not ns.Mine(f, me) then return false end
        id = f.parent
        guard = guard + 1
    end
    return true
end

function ns.PageShown(db, page, me)
    return ns.Mine(page, me) and (not page.folder or ns.FolderShown(db, page.folder, me))
end

function ns.Path(db, id)
    local parts, guard = {}, 0
    while id and db.folders[id] and guard < 64 do
        table.insert(parts, 1, db.folders[id].name)
        id = db.folders[id].parent
        guard = guard + 1
    end
    return table.concat(parts, " / ")
end

-- True when `id` is `ancestor` or sits somewhere inside it.
function ns.Inside(db, id, ancestor)
    local guard = 0
    while id and guard < 64 do
        if id == ancestor then return true end
        id = db.folders[id] and db.folders[id].parent
        guard = guard + 1
    end
    return false
end

function ns.CanMoveFolder(db, id, parent)
    return not parent or not ns.Inside(db, parent, id)
end

-- Deleting a folder keeps what's in it: its pages and folders move up a level.
function ns.DeleteFolder(db, id)
    local f = db.folders[id]
    if not f then return 0 end
    local moved = 0
    for _, g in pairs(db.folders) do
        if g.parent == id then
            g.parent = f.parent
            moved = moved + 1
        end
    end
    for _, p in pairs(db.pages) do
        if p.folder == id then
            p.folder = f.parent
            moved = moved + 1
        end
    end
    db.folders[id] = nil
    return moved
end

local function Before(a, b)
    local oa, ob = a.order or a.id, b.order or b.id
    if oa ~= ob then return oa < ob end
    return a.id < b.id
end

-- Siblings of a folder (folders = true) or page, in order.
function ns.Siblings(db, obj, folders)
    local out = {}
    if folders then
        for _, f in pairs(db.folders) do
            if f.parent == obj.parent then out[#out + 1] = f end
        end
    else
        for _, p in pairs(db.pages) do
            if p.folder == obj.folder then out[#out + 1] = p end
        end
    end
    table.sort(out, Before)
    return out
end

-- Swap places with the previous (-1) or next (+1) sibling; fixes the order numbers as it goes.
function ns.MoveAmong(db, obj, folders, delta)
    local list = ns.Siblings(db, obj, folders)
    for i, o in ipairs(list) do o.order = i end
    for i, o in ipairs(list) do
        if o == obj then
            local other = list[i + delta]
            if not other then return false end
            obj.order, other.order = other.order, obj.order
            return true
        end
    end
    return false
end

---------------------------------------------------------------------------
-- Search
---------------------------------------------------------------------------
local function Haystack(db, page)
    local parts = { page.title or "", ns.Plain(page.text), ns.Path(db, page.folder) }
    for _, item in ipairs(page.items or {}) do parts[#parts + 1] = ns.Plain(item.text) end
    return table.concat(parts, "\n"):lower()
end

-- Pages where every word of the query shows up (title, text, tasks or folder names), as a set of ids.
function ns.Search(db, query, show)
    local words = {}
    for w in (query or ""):lower():gmatch("%S+") do words[#words + 1] = w end
    local found = {}
    for id, page in pairs(db.pages) do
        if show(page) then
            local hay = Haystack(db, page)
            local all = true
            for _, w in ipairs(words) do
                if not hay:find(w, 1, true) then
                    all = false
                    break
                end
            end
            if all then found[id] = true end
        end
    end
    return found
end

---------------------------------------------------------------------------
-- The tree as rows: { folder = f | page = p, depth }. Pages before folders at each level.
-- opts.all = show other characters' things too; opts.match = set of page ids (search) → only those, with every
-- folder on their way open.
---------------------------------------------------------------------------
function ns.Tree(db, me, opts)
    opts = opts or {}
    local kids, pages = {}, {}
    for _, f in pairs(db.folders) do
        local parent = f.parent and db.folders[f.parent] and f.parent or 0
        kids[parent] = kids[parent] or {}
        table.insert(kids[parent], f)
    end
    for _, p in pairs(db.pages) do
        local parent = p.folder and db.folders[p.folder] and p.folder or 0
        pages[parent] = pages[parent] or {}
        table.insert(pages[parent], p)
    end
    for _, list in pairs(kids) do table.sort(list, Before) end
    for _, list in pairs(pages) do table.sort(list, Before) end

    local function visible(o) return opts.all or ns.Mine(o, me) end
    local hits = {}
    local function hasHit(id)
        if hits[id] ~= nil then return hits[id] end
        local yes = false
        for _, p in ipairs(pages[id] or {}) do
            if visible(p) and opts.match[p.id] then yes = true end
        end
        for _, f in ipairs(kids[id] or {}) do
            if visible(f) and hasHit(f.id) then yes = true end
        end
        hits[id] = yes
        return yes
    end

    local rows = {}
    local function walk(id, depth)
        for _, p in ipairs(pages[id] or {}) do
            if visible(p) and (not opts.match or opts.match[p.id]) then
                rows[#rows + 1] = { page = p, depth = depth }
            end
        end
        for _, f in ipairs(kids[id] or {}) do
            if visible(f) and (not opts.match or hasHit(f.id)) then
                rows[#rows + 1] = { folder = f, depth = depth }
                if f.open or opts.match then walk(f.id, depth + 1) end
            end
        end
    end
    walk(0, 0)
    return rows
end

-- Tasks not done yet on pages this character sees whose link passes `test(link, item)`, as { page, item } pairs.
function ns.Tickable(db, me, reset, test)
    local out = {}
    for _, page in pairs(db.pages) do
        if page.kind == "list" and ns.PageShown(db, page, me) then
            for _, item in ipairs(page.items or {}) do
                if item.link and not ns.IsDone(page, item, me, reset) and test(item.link, item) then
                    out[#out + 1] = { page = page, item = item }
                end
            end
        end
    end
    return out
end
