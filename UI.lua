-- The notebook window: folder tree on the left (search on top, + Folder / + Note / + List under it), the open
-- page on the right. Notes read with clickable links and turn into an edit box when clicked; lists are rows of
-- tasks with an add box under them. Own flat frames only, nothing protected, usable in combat.
local _, ns = ...

local PAD = 8
local TREE_W = 210
local ROW_H = 20
local TASK_H = 22
local MIN_W, MIN_H = 660, 340 -- the list bar needs room for its add box next to its buttons

local window, search, searchHint
local treePane, treeRows, treeOffset = nil, {}, 0
local right, header, sub, empty
local noteView, noteScroll, noteChild, noteText, editScroll, edit, noteBar
local listPane, taskRows, taskOffset, addBox, addDaily, listBar, footer = nil, {}, 0, nil, nil, nil, nil
local editing = false
local query

local function Db() return ns.db end
local function Selected()
    local p = ns.char.sel and Db().pages[ns.char.sel]
    if p and (Db().showAll or ns.PageShown(Db(), p, ns.me)) then return p end
end

local function Ago(t)
    local s = time() - (t or 0)
    if s < 90 then return "just now" end
    if s < 3600 then return ("%d min ago"):format(s / 60) end
    if s < 86400 then return ("%d h ago"):format(s / 3600) end
    return ("%d days ago"):format(s / 86400)
end

local function Duration(s)
    if s >= 3600 then return ("%d h %d min"):format(s / 3600, (s % 3600) / 60) end
    return ("%d min"):format(math.max(1, s / 60))
end

local function ColorHex(key)
    for _, c in ipairs(ns.COLORS) do
        if c.key == key then return c.hex end
    end
end

---------------------------------------------------------------------------
-- Saving a note as you type
---------------------------------------------------------------------------
local function SaveNote()
    local p = Selected()
    if p and p.kind == "note" and editing then
        local text = edit:GetText()
        if text ~= p.text then
            p.text = text
            p.edited = time()
        end
    end
end

local function StopEdit()
    if not editing then return end
    SaveNote()
    editing = false
    edit:ClearFocus()
    if ns.focus == edit then ns.focus = nil end
end

---------------------------------------------------------------------------
-- Moving things, renaming, deleting (menus)
---------------------------------------------------------------------------
local function MoveTargets(exclude)
    local db = Db()
    local out = { { text = "Move to", title = true }, { text = "Top level", value = false } }
    -- Every folder, open or not: walk with everything open.
    local opened = {}
    for _, f in pairs(db.folders) do
        opened[f] = f.open
        f.open = true
    end
    local rows = ns.Tree(db, ns.me, { all = db.showAll })
    for f, was in pairs(opened) do f.open = was end
    for _, r in ipairs(rows) do
        if r.folder and not (exclude and ns.Inside(db, r.folder.id, exclude)) then
            out[#out + 1] = { text = string.rep("   ", r.depth + 1) .. r.folder.name, value = r.folder.id,
                color = ColorHex(r.folder.color) }
        end
    end
    return out
end

local function MoveMenu(apply, exclude)
    local entries = MoveTargets(exclude)
    for _, e in ipairs(entries) do
        if e.value ~= nil then
            local v = e.value
            e.func = function()
                apply(v or nil)
                ns.Refresh()
            end
        end
    end
    ns.Menu(entries)
end

local function OnlyMeEntry(obj)
    local db = Db()
    if obj.char and obj.char ~= ns.me then
        return { text = ("Only %s sees this: share it"):format(obj.charName or "another character"),
            func = function()
                obj.char, obj.charName = nil, nil
                ns.Refresh()
            end }
    end
    return { text = ("Only %s"):format(ns.myName or "this character"), checked = obj.char == ns.me,
        tip = "Other characters won't see it (unless they show every character's pages).",
        func = function()
            if obj.char then
                obj.char, obj.charName = nil, nil
            else
                obj.char, obj.charName = ns.me, ns.myName
            end
            if not db.showAll then
                local p = Selected()
                if not p then ns.char.sel = nil end
            end
            ns.Refresh()
        end }
end

function ns.SelectPage(id)
    StopEdit()
    ns.char.sel = id
    taskOffset = 0
    ns.Refresh()
end

local function NewPageIn(kind, folder)
    local label = kind == "note" and "New note" or "New list"
    ns.Ask(label .. ": name", "", function(text)
        text = ns.OneLine(text)
        if text == "" then return "Give it a name." end
        local p = ns.NewPage(kind, text, folder)
        ns.SelectPage(p.id)
    end)
end

local function NewFolderIn(parent)
    ns.Ask("New folder: name", "", function(text)
        text = ns.OneLine(text)
        if text == "" then return "Give it a name." end
        ns.NewFolder(text, parent)
        if parent and Db().folders[parent] then Db().folders[parent].open = true end
        ns.Refresh()
    end)
end

local function FolderMenu(f)
    local db = Db()
    local colors = {}
    ns.Menu({
        { text = f.name, title = true, color = ColorHex(f.color) },
        { text = "New note here", func = function() NewPageIn("note", f.id) end },
        { text = "New list here", func = function() NewPageIn("list", f.id) end },
        { text = "New folder here", func = function() NewFolderIn(f.id) end },
        { text = "Rename...", func = function()
            ns.Ask("Rename folder", f.name, function(text)
                text = ns.OneLine(text)
                if text == "" then return "Give it a name." end
                f.name = text
                ns.Refresh()
            end)
        end },
        { text = "Colour...", func = function()
            colors[1] = { text = "Colour", title = true }
            for _, c in ipairs(ns.COLORS) do
                colors[#colors + 1] = { text = c.name, color = c.hex, checked = f.color == c.key, func = function()
                    f.color = c.key
                    ns.Refresh()
                end }
            end
            colors[#colors + 1] = { text = "No colour", checked = f.color == nil, func = function()
                f.color = nil
                ns.Refresh()
            end }
            ns.Menu(colors)
        end },
        OnlyMeEntry(f),
        { text = "Move up", func = function() ns.MoveAmong(db, f, true, -1) ns.Refresh() end },
        { text = "Move down", func = function() ns.MoveAmong(db, f, true, 1) ns.Refresh() end },
        { text = "Move to...", func = function()
            MoveMenu(function(parent)
                if ns.CanMoveFolder(db, f.id, parent) then f.parent = parent end
            end, f.id)
        end },
        { text = "Delete folder (keeps what's in it)", func = function()
            ns.Confirm(("Delete \"%s\"? Its pages and folders move up a level."):format(f.name), function()
                ns.DeleteFolder(db, f.id)
                ns.Refresh()
            end)
        end },
    })
end

local function PageMenu(p)
    local db = Db()
    local entries = {
        { text = p.title, title = true },
        { text = "Rename...", func = function()
            ns.Ask("Rename", p.title, function(text)
                text = ns.OneLine(text)
                if text == "" then return "Give it a name." end
                p.title = text
                ns.Refresh()
            end)
        end },
        { text = "Move to...", func = function() MoveMenu(function(folder) p.folder = folder end) end },
        { text = "Move up", func = function() ns.MoveAmong(db, p, false, -1) ns.Refresh() end },
        { text = "Move down", func = function() ns.MoveAmong(db, p, false, 1) ns.Refresh() end },
        OnlyMeEntry(p),
    }
    if p.kind == "list" then
        entries[#entries + 1] = { text = "Keep done tasks", checked = p.keep == true,
            tip = "Off: one-time tasks that are done go away at the daily reset.",
            func = function()
                p.keep = not p.keep or nil
                ns.Refresh()
            end }
        entries[#entries + 1] = { text = "Each character ticks its own", checked = p.each == true,
            tip = "For a list every character works through: a tick only counts for the character who made it.",
            func = function()
                p.each = not p.each or nil
                ns.Refresh()
            end }
        entries[#entries + 1] = { text = "Pin to the screen", checked = db.pinned == p.id,
            func = function() ns.TogglePin(p) end }
        entries[#entries + 1] = { text = "/todo adds here", checked = db.inbox == p.id,
            func = function()
                db.inbox = p.id
                ns.Refresh()
            end }
    end
    entries[#entries + 1] = { text = "Delete...", func = function()
        ns.Confirm(("Delete \"%s\"? This can't be undone."):format(p.title), function()
            db.pages[p.id] = nil
            if ns.char.sel == p.id then ns.char.sel = nil end
            if db.pinned == p.id then db.pinned = nil end
            if db.inbox == p.id then db.inbox = nil end
            StopEdit()
            ns.Refresh()
        end)
    end }
    ns.Menu(entries)
end

local function OptionsMenu()
    local db = Db()
    ns.Menu({
        { text = "EzNotebook", title = true },
        { text = "Chat line when a task ticks itself", checked = db.notify == true, func = function()
            db.notify = not db.notify
        end },
        { text = "Launcher icon above the chat", checked = db.icon == true, func = function()
            db.icon = not db.icon
            if ns.UpdateIcon then ns.UpdateIcon() end
        end },
        { text = "Minimap button", checked = db.minimap ~= false, func = function()
            db.minimap = db.minimap == false
            ns.UpdateMinimap()
        end },
        { text = ns.HasDrawer() and "Entry in the addon drawer" or "Entry in the addon drawer (WoW Forever only)",
            checked = ns.HasDrawer() and db.drawer ~= false, disabled = not ns.HasDrawer(), func = function()
                db.drawer = db.drawer == false
                ns.UpdateDrawer()
            end },
        { text = "Show other characters' pages", checked = db.showAll == true,
            tip = "Pages and folders marked for one character show for every character, dimmed.",
            func = function()
                db.showAll = not db.showAll or nil
                ns.Refresh()
            end },
        { text = "Commands in chat (/nb help)", func = function() SlashCmdList.EZNOTEBOOK("help") end },
    })
end

---------------------------------------------------------------------------
-- Link pickers: quest log, dungeons (then a boss you've killed there), where you stand
---------------------------------------------------------------------------
local function QuestPicker(put)
    local quests = ns.QuestLog()
    if #quests == 0 then return ns.Print("No quests in your log (Era: open its zone headers).") end
    local entries = { { text = "Quest from your log", title = true } }
    for _, q in ipairs(quests) do
        entries[#entries + 1] = { text = q.level and ("[%d] %s"):format(q.level, q.title) or q.title,
            func = function() put(ns.MakeQuestLink(q.id, q.title)) end }
    end
    ns.Menu(entries)
end

local function BossPicker(d, put)
    local bosses = ns.Bosses(d.id)
    if #bosses == 0 then return put(ns.DungeonLink(d.id, d.name)) end
    local entries = { { text = d.name, title = true },
        { text = "The whole run (ticks when you leave with a boss down)", func = function()
            put(ns.DungeonLink(d.id, d.name))
        end } }
    for _, b in ipairs(bosses) do
        entries[#entries + 1] = { text = b.name, func = function() put(ns.DungeonLink(d.id, d.name, b.id, b.name)) end }
    end
    ns.Menu(entries)
end

local function DungeonPicker(put)
    local list = ns.DungeonList()
    local entries = { { text = "Dungeon or raid", title = true } }
    for _, d in ipairs(list) do
        local label = d.name .. (d.raid and " |cff999999(raid)|r" or "")
        if #ns.Bosses(d.id) > 0 then label = label .. " |cff999999...|r" end
        entries[#entries + 1] = { text = label, func = function() BossPicker(d, put) end }
    end
    ns.Menu(entries)
end

-- Mark spot: a bookmark of where you stand (zone, subzone, map spot). Clicking it later puts a pin on the map.
local function Here(put)
    local link = ns.HereLink()
    if not link then return ns.Print("Can't tell where you are right now.") end
    put(link)
end

---------------------------------------------------------------------------
-- Tree
---------------------------------------------------------------------------
local function TreeRow(i)
    if treeRows[i] then return treeRows[i] end
    local r = CreateFrame("Button", nil, treePane)
    r:SetHeight(ROW_H)
    r:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    r.sel = r:CreateTexture(nil, "BACKGROUND")
    r.sel:SetAllPoints()
    r.sel:SetColorTexture(1, 0.82, 0, 0.16)
    local hl = r:CreateTexture(nil, "HIGHLIGHT")
    hl:SetAllPoints()
    hl:SetColorTexture(1, 1, 1, 0.07)
    r.icon = r:CreateTexture(nil, "ARTWORK")
    r.icon:SetSize(14, 14)
    r.name = ns.Text(r, "GameFontHighlightSmall")
    r.name:SetJustifyH("LEFT")
    r.name:SetWordWrap(false)
    r.count = ns.Text(r, "GameFontHighlightSmall")
    r.count:SetPoint("RIGHT", -4, 0)
    r.count:SetTextColor(0.7, 0.7, 0.7)
    r.name:SetPoint("RIGHT", r.count, "LEFT", -4, 0)
    r:SetScript("OnClick", function(self, button)
        local f, p = self.folder, self.page
        if button == "RightButton" then
            if f then FolderMenu(f) else PageMenu(p) end
        elseif f then
            f.open = not f.open
            ns.Refresh()
        else
            ns.SelectPage(p.id)
        end
    end)
    r:SetScript("OnEnter", function(self)
        local o = self.folder or self.page
        if not o or not o.char then return end
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:AddLine(("Only %s sees this"):format(o.charName or "one character"), 1, 1, 1)
        GameTooltip:Show()
    end)
    r:SetScript("OnLeave", function() GameTooltip:Hide() end)
    r:EnableMouseWheel(true)
    r:SetScript("OnMouseWheel", function(_, delta) treePane:GetScript("OnMouseWheel")(treePane, delta) end)
    treeRows[i] = r
    return r
end

local function DrawTree()
    local db = Db()
    local match
    if query and #query >= ns.SEARCH_MIN then
        match = ns.Search(db, query, function(p) return db.showAll or ns.PageShown(db, p, ns.me) end)
    end
    local rows = ns.Tree(db, ns.me, { all = db.showAll, match = match })
    local fit = math.max(1, math.floor((treePane:GetHeight() - 4) / ROW_H))
    treeOffset = math.max(0, math.min(treeOffset, #rows - fit))
    local reset = ns.Reset()
    local sel = ns.char.sel
    for i = 1, math.max(fit, #treeRows) do
        local data = i <= fit and rows[i + treeOffset]
        local r = (data or treeRows[i]) and TreeRow(i)
        if r then
            r:SetShown(data ~= nil and data ~= false)
            if data then
                r:ClearAllPoints()
                r:SetPoint("TOPLEFT", 2, -2 - (i - 1) * ROW_H)
                r:SetPoint("RIGHT", -2, 0)
                local indent = 4 + data.depth * 12
                r.icon:ClearAllPoints()
                r.icon:SetPoint("LEFT", indent, 0)
                r.name:SetPoint("LEFT", indent + 18, 0)
                r.folder, r.page = data.folder, data.page
                local o = data.folder or data.page
                local other = o.char and o.char ~= ns.me
                if data.folder then
                    local f = data.folder
                    r.icon:SetTexture(f.open and "Interface\\Buttons\\UI-MinusButton-Up" or "Interface\\Buttons\\UI-PlusButton-Up")
                    r.icon:SetTexCoord(0, 1, 0, 1)
                    local hex = ColorHex(f.color) or "e8c87a"
                    r.name:SetText("|cff" .. hex .. f.name .. "|r")
                    r.count:SetText("")
                    r.sel:Hide()
                else
                    local p = data.page
                    r.icon:SetTexture(p.kind == "list" and "Interface\\Icons\\INV_Misc_Note_06"
                        or "Interface\\Icons\\INV_Misc_Note_01")
                    r.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
                    r.name:SetText(p.title)
                    if p.kind == "list" then
                        local open, total = ns.CountOpen(p, ns.me, reset)
                        r.count:SetText(total > 0 and (open == 0 and "|cff66dd66done|r" or tostring(open)) or "")
                    else
                        r.count:SetText("")
                    end
                    r.sel:SetShown(p.id == sel)
                end
                r:SetAlpha(other and 0.5 or 1)
            end
        end
    end
    if #rows == 0 then
        empty.tree:SetText(match and "Nothing matches." or "Empty. Make a page below.")
        empty.tree:Show()
    else
        empty.tree:Hide()
    end
end

---------------------------------------------------------------------------
-- Note page
---------------------------------------------------------------------------
local function LayoutNote()
    local w = math.max(noteScroll:GetWidth(), 100) -- 0 before the first frame
    noteChild:SetWidth(w)
    noteText:SetWidth(w - 12)
    noteChild:SetHeight(math.max(noteText:GetStringHeight() + 16, noteScroll:GetHeight()))
    edit:SetWidth(math.max(editScroll:GetWidth(), 100) - 4)
end

local function DrawNote(p)
    noteView:Show()
    listPane:Hide()
    noteBar.done:SetText(editing and "Done" or "Edit")
    if editing then
        noteScroll:Hide()
        editScroll:Show()
        if edit.pageId ~= p.id then
            edit.pageId = p.id
            edit.cursor = nil
            edit:SetText(p.text or "")
            edit:SetCursorPosition(#(p.text or ""))
        end
    else
        editScroll:Hide()
        noteScroll:Show()
        local text = p.text or ""
        if ns.Trim(text) == "" then
            noteText:SetText("|cff808080Click here to write.|r")
        else
            noteText:SetText(text)
        end
        LayoutNote()
    end
end

local function StartEdit(atEnd)
    local p = Selected()
    if not p or p.kind ~= "note" then return end
    editing = true
    edit.pageId = nil
    DrawNote(p)
    LayoutNote()
    edit:SetFocus()
    if atEnd then edit:SetCursorPosition(#(p.text or "")) end
end

local function PutInNote(link)
    if editing then
        edit:SetFocus()
        if edit.cursor then edit:SetCursorPosition(edit.cursor) end
    else
        StartEdit(true)
    end
    edit:Insert(link)
    SaveNote()
end

-- A click on a frame with links fires both OnHyperlinkClick and OnMouseUp, in an order we can't count on:
-- the plain click waits a frame and stands down if a link was clicked in the same one.
local function AfterClick(frame, fn)
    local at = GetTime()
    C_Timer.After(0, function()
        if frame.linkAt ~= at then fn() end
    end)
end

---------------------------------------------------------------------------
-- List page
---------------------------------------------------------------------------
local function TaskMenu(p, index)
    local item = p.items[index]
    if not item then return end
    local entries = {
        { text = ns.Plain(item.text):sub(1, 50), title = true },
        { text = "Edit...", func = function()
            ns.Ask("Edit task", item.text, function(text)
                text = ns.OneLine(text)
                if text == "" then return "Type something, or use Remove." end
                item.text = text
                item.link, item.goal = ns.ParseTask(text)
                ns.Refresh()
            end, ns.MAX_TASK)
        end },
        { text = "Daily (unchecks at the reset)", checked = item.daily == true, func = function()
            item.daily = not item.daily or nil
            ns.Refresh()
        end },
    }
    if item.link and item.link.k == "item" then
        entries[#entries + 1] = { text = item.goal and ("Count: %d..."):format(item.goal) or "Set a count...",
            tip = "Ticks when your bags and bank hold that many.", func = function()
                ns.Ask("How many?", item.goal and tostring(item.goal) or "", function(text)
                    local n = tonumber(text)
                    if not n or n < 1 then
                        item.goal = nil
                    else
                        item.goal = math.min(math.floor(n), ns.MAX_GOAL)
                        if ns.Met(item.link, item) then ns.SetDone(p, item, ns.me, true, time()) end
                    end
                    ns.Refresh()
                end, 5, true)
            end }
    end
    entries[#entries + 1] = { text = "Move up", func = function() ns.MoveItem(p, index, -1) ns.Refresh() end }
    entries[#entries + 1] = { text = "Move down", func = function() ns.MoveItem(p, index, 1) ns.Refresh() end }
    entries[#entries + 1] = { text = "Remove", func = function()
        table.remove(p.items, index)
        ns.Refresh()
    end }
    ns.Menu(entries)
end

local function TaskRow(i)
    if taskRows[i] then return taskRows[i] end
    local r = CreateFrame("Frame", nil, listPane)
    r:SetHeight(TASK_H)
    local hl = r:CreateTexture(nil, "BACKGROUND")
    hl:SetAllPoints()
    hl:SetColorTexture(1, 1, 1, 0.04)
    hl:Hide()
    r.hl = hl
    r.check = CreateFrame("CheckButton", nil, r, "UICheckButtonTemplate")
    r.check:SetSize(22, 22)
    r.check:SetPoint("LEFT", 0, 0)
    r.check:SetScript("OnClick", function(self)
        local p, item = Selected(), r.item
        if not (p and item) then return end
        ns.SetDone(p, item, ns.me, self:GetChecked() and true or false, time())
        ns.Refresh()
    end)
    r.extra = ns.Text(r)
    r.extra:SetPoint("RIGHT", -6, 0)
    r.extra:SetTextColor(0.75, 0.75, 0.75)
    r.text = ns.Text(r, "GameFontHighlight")
    r.text:SetPoint("LEFT", r.check, "RIGHT", 2, 0)
    r.text:SetPoint("RIGHT", r.extra, "LEFT", -8, 0)
    r.text:SetJustifyH("LEFT")
    r.text:SetWordWrap(false)
    r:EnableMouse(true)
    r:SetHyperlinksEnabled(true)
    local function Menu()
        local p = Selected()
        if p and r.index then TaskMenu(p, r.index) end
    end
    r:SetScript("OnHyperlinkClick", function(_, link, text, button)
        r.linkAt = GetTime()
        if button == "RightButton" then return Menu() end
        ns.LinkClick(link, text)
    end)
    r:SetScript("OnHyperlinkEnter", function(self, link) ns.LinkEnter(self, link) end)
    r:SetScript("OnHyperlinkLeave", ns.LinkLeave)
    r:SetScript("OnMouseUp", function(_, button)
        AfterClick(r, function()
            if button == "RightButton" then
                Menu()
            elseif button == "LeftButton" then
                r.check:Click()
            end
        end)
    end)
    r:SetScript("OnEnter", function() hl:Show() end)
    r:SetScript("OnLeave", function() hl:Hide() end)
    r:EnableMouseWheel(true)
    r:SetScript("OnMouseWheel", function(_, delta) listPane:GetScript("OnMouseWheel")(listPane, delta) end)
    taskRows[i] = r
    return r
end

local function DrawList(p)
    noteView:Hide()
    listPane:Show()
    local reset = ns.Reset()
    local items = p.items or {}
    local fit = math.max(1, math.floor((listPane:GetHeight() - 60) / TASK_H))
    taskOffset = math.max(0, math.min(taskOffset, #items - fit))
    for i = 1, math.max(fit, #taskRows) do
        local index = i + taskOffset
        local item = i <= fit and items[index]
        local r = (item or taskRows[i]) and TaskRow(i)
        if r then
            r:SetShown(item ~= nil and item ~= false)
            if item then
                r:ClearAllPoints()
                r:SetPoint("TOPLEFT", listBar, "BOTTOMLEFT", 0, -4 - (i - 1) * TASK_H)
                r:SetPoint("RIGHT", listPane, "RIGHT", 0, 0)
                r.item, r.index = item, index
                local done = ns.IsDone(p, item, ns.me, reset)
                r.check:SetChecked(done)
                r.text:SetText(done and ("|cff808080" .. ns.Plain(item.text) .. "|r") or item.text)
                local extra = {}
                local prog = not done and ns.Progress(item)
                if prog then extra[#extra + 1] = prog end
                if item.daily then extra[#extra + 1] = "|cff7fd0ffdaily|r" end
                r.extra:SetText(table.concat(extra, "  "))
            end
        end
    end
    local open, total = ns.CountOpen(p, ns.me, reset)
    local parts = {}
    if total == 0 then
        parts[1] = "No tasks yet: type one below and press Enter."
    else
        parts[1] = open == 0 and "|cff66dd66All done.|r" or ("%d of %d left"):format(open, total)
        if #items > fit then parts[#parts + 1] = "scroll for more" end
    end
    local untilReset = ns.UntilReset()
    if untilReset then parts[#parts + 1] = "daily reset in " .. Duration(untilReset) end
    if p.each then parts[#parts + 1] = "each character ticks its own" end
    footer:SetText(table.concat(parts, "  ·  "))
    addDaily:SetChecked(ns.char.addDaily == true)
end

---------------------------------------------------------------------------
-- Right side
---------------------------------------------------------------------------
local function DrawPage()
    local p = Selected()
    if not p then
        header:SetText("")
        sub:SetText("")
        noteView:Hide()
        listPane:Hide()
        empty.page:Show()
        return
    end
    empty.page:Hide()
    header:SetText(p.title)
    local parts = {}
    local path = ns.Path(Db(), p.folder)
    parts[#parts + 1] = path ~= "" and path or "Top level"
    if p.char then parts[#parts + 1] = "only " .. (p.charName or "one character") end
    if Db().pinned == p.id then parts[#parts + 1] = "pinned" end
    if Db().inbox == p.id then parts[#parts + 1] = "/todo adds here" end
    parts[#parts + 1] = "edited " .. Ago(p.edited)
    sub:SetText(table.concat(parts, "  ·  "))
    if p.kind == "note" then DrawNote(p) else DrawList(p) end
end

function ns.RedrawWindow()
    if not window or not window:IsShown() then return end
    DrawTree()
    DrawPage()
end

---------------------------------------------------------------------------
-- Building the window
---------------------------------------------------------------------------
function ns.PlaceWindow()
    if not window then return end
    window:ClearAllPoints()
    local p = Db().win
    if p then
        window:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", p[1], p[2])
        window:SetSize(p[3] or 720, p[4] or 460)
    else
        window:SetPoint("CENTER", 0, 40)
        window:SetSize(720, 460)
    end
end

local function SavePlace()
    Db().win = { window:GetLeft(), window:GetTop(), window:GetWidth(), window:GetHeight() }
end

local function Scroller(frame, step, get, set)
    frame:EnableMouseWheel(true)
    frame:SetScript("OnMouseWheel", function(_, delta)
        set(math.max(0, get() - delta * step))
        ns.RedrawWindow()
    end)
end

local function BuildNote()
    noteView = CreateFrame("Frame", nil, right)
    noteView:SetPoint("TOPLEFT", 0, -50)
    noteView:SetPoint("BOTTOMRIGHT", 0, 0)

    noteBar = CreateFrame("Frame", nil, noteView)
    noteBar:SetPoint("TOPLEFT")
    noteBar:SetPoint("RIGHT")
    noteBar:SetHeight(22)
    noteBar.done = ns.Button(noteBar, "Edit", 56)
    noteBar.done:SetPoint("LEFT")
    noteBar.done:SetScript("OnClick", function()
        if editing then
            StopEdit()
            ns.Refresh()
        else
            StartEdit(true)
        end
    end)
    local function Put(link) PutInNote(link) end
    local quest = ns.Button(noteBar, "Quest", 56)
    quest:SetPoint("LEFT", noteBar.done, "RIGHT", 12, 0)
    quest:SetScript("OnClick", function() QuestPicker(Put) end)
    ns.Tip(quest, "Link a quest from your log", "Or Shift-click a quest while typing.")
    local dungeon = ns.Button(noteBar, "Dungeon", 64)
    dungeon:SetPoint("LEFT", quest, "RIGHT", 4, 0)
    dungeon:SetScript("OnClick", function() DungeonPicker(Put) end)
    local here = ns.Button(noteBar, "Mark spot", 70)
    here:SetPoint("LEFT", dungeon, "RIGHT", 4, 0)
    here:SetScript("OnClick", function() Here(Put) end)
    ns.Tip(here, "Mark this spot",
        "Saves where you stand as a link. Click the link later to put a pin on your map and find your way back "
        .. "(Classic Era: its coordinates in chat).")
    local hint = ns.Text(noteBar)
    hint:SetPoint("LEFT", here, "RIGHT", 10, 0)
    hint:SetPoint("RIGHT")
    hint:SetJustifyH("LEFT")
    hint:SetWordWrap(false)
    hint:SetTextColor(0.6, 0.6, 0.6)
    hint:SetText("Shift-click or drop items and quests in.")

    -- Reading: a font string in a frame that takes link clicks.
    noteScroll = CreateFrame("ScrollFrame", nil, noteView, "BackdropTemplate")
    noteScroll:SetPoint("TOPLEFT", 0, -28)
    noteScroll:SetPoint("BOTTOMRIGHT", 0, 0)
    ns.Skin(noteScroll, 0.5, 0.02)
    noteChild = CreateFrame("Frame", nil, noteScroll)
    noteChild:SetSize(400, 200)
    noteScroll:SetScrollChild(noteChild)
    noteText = ns.Text(noteChild, "ChatFontNormal")
    noteText:SetPoint("TOPLEFT", 6, -6)
    noteText:SetJustifyH("LEFT")
    noteText:SetJustifyV("TOP")
    noteText:SetSpacing(2)
    noteChild:EnableMouse(true)
    noteChild:SetHyperlinksEnabled(true)
    noteChild:SetScript("OnHyperlinkClick", function(self, link, text)
        self.linkAt = GetTime()
        ns.LinkClick(link, text)
    end)
    noteChild:SetScript("OnHyperlinkEnter", function(self, link) ns.LinkEnter(self, link) end)
    noteChild:SetScript("OnHyperlinkLeave", ns.LinkLeave)
    noteChild:SetScript("OnMouseUp", function(self, button)
        if button ~= "LeftButton" then return end
        AfterClick(self, function() StartEdit(true) end)
    end)
    noteScroll:EnableMouseWheel(true)
    noteScroll:SetScript("OnMouseWheel", function(self, delta)
        local v = self:GetVerticalScroll() - delta * 40
        self:SetVerticalScroll(math.max(0, math.min(v, self:GetVerticalScrollRange())))
    end)
    noteScroll:SetScript("OnSizeChanged", function() if noteScroll:IsShown() then LayoutNote() end end)

    -- Writing: a multi-line edit box; saved on every typed change.
    editScroll = CreateFrame("ScrollFrame", nil, noteView, "BackdropTemplate")
    editScroll:SetPoint("TOPLEFT", 0, -28)
    editScroll:SetPoint("BOTTOMRIGHT", 0, 0)
    ns.Skin(editScroll, 0.8, 0.0)
    editScroll:SetBackdropBorderColor(1, 0.82, 0, 0.35)
    edit = CreateFrame("EditBox", nil, editScroll)
    edit:SetMultiLine(true)
    edit:SetAutoFocus(false)
    edit:SetFontObject("ChatFontNormal")
    edit:SetTextInsets(6, 6, 6, 6)
    edit:SetMaxLetters(ns.MAX_NOTE)
    edit:SetWidth(400)
    edit:SetHeight(200)
    editScroll:SetScrollChild(edit)
    edit.ezAfterInsert = SaveNote
    edit:SetScript("OnTextChanged", function(_, userInput)
        if userInput then SaveNote() end
    end)
    edit:SetScript("OnEditFocusGained", function(self) ns.focus = self end)
    edit:SetScript("OnEditFocusLost", function(self)
        self.cursor = self:GetCursorPosition()
        SaveNote()
    end)
    edit:SetScript("OnEscapePressed", function()
        StopEdit()
        ns.Refresh()
    end)
    edit:SetScript("OnCursorChanged", function(_, _, y, _, h)
        local top, height = editScroll:GetVerticalScroll(), editScroll:GetHeight()
        y = -y
        if y < top then
            editScroll:SetVerticalScroll(y)
        elseif y + h > top + height then
            editScroll:SetVerticalScroll(y + h - height + 8)
        end
    end)
    edit:SetScript("OnReceiveDrag", function(self) ns.Drop(self) end)
    edit:SetScript("OnMouseUp", function(self)
        if GetCursorInfo() then ns.Drop(self) end
    end)
    editScroll:EnableMouse(true)
    editScroll:SetScript("OnMouseDown", function() edit:SetFocus() end)
    editScroll:SetScript("OnReceiveDrag", function() ns.Drop(edit) end)
    editScroll:EnableMouseWheel(true)
    editScroll:SetScript("OnMouseWheel", function(self, delta)
        local v = self:GetVerticalScroll() - delta * 40
        self:SetVerticalScroll(math.max(0, math.min(v, self:GetVerticalScrollRange())))
    end)
    editScroll:SetScript("OnSizeChanged", function() edit:SetWidth(editScroll:GetWidth() - 4) end)
    editScroll:Hide()
end

local function BuildList()
    listPane = CreateFrame("Frame", nil, right)
    listPane:SetPoint("TOPLEFT", 0, -50)
    listPane:SetPoint("BOTTOMRIGHT", 0, 0)
    Scroller(listPane, 3, function() return taskOffset end, function(v) taskOffset = v end)

    listBar = CreateFrame("Frame", nil, listPane)
    listBar:SetPoint("TOPLEFT")
    listBar:SetPoint("RIGHT")
    listBar:SetHeight(1)

    -- Add box at the bottom.
    addBox = ns.Edit(listPane, 24)
    addBox:SetPoint("BOTTOMLEFT", 0, 22)
    addBox:SetMaxBytes(ns.MAX_TASK)
    local hint = ns.Text(addBox)
    -- Both sides anchored and one line: a long hint would run out of the box over the Daily check.
    hint:SetPoint("LEFT", 8, 0)
    hint:SetPoint("RIGHT", -6, 0)
    hint:SetJustifyH("LEFT")
    hint:SetWordWrap(false)
    hint:SetTextColor(0.5, 0.5, 0.5)
    hint:SetText("Add a task, Enter (Shift-click links in)")
    local function Hint() hint:SetShown(addBox:GetText() == "" and not addBox:HasFocus()) end
    addBox:SetScript("OnEditFocusGained", function(self)
        ns.focus = self
        Hint()
    end)
    addBox:SetScript("OnEditFocusLost", Hint)
    addBox:SetScript("OnTextChanged", Hint)
    addBox:SetScript("OnEnterPressed", function(self)
        local p = Selected()
        local text = self:GetText()
        if p and p.kind == "list" and ns.Trim(text) ~= "" then
            ns.AddTask(p, text, ns.char.addDaily)
            self:SetText("")
            -- Scroll to the new task.
            taskOffset = #p.items
            ns.Refresh()
        else
            self:ClearFocus()
        end
    end)
    addBox:SetScript("OnReceiveDrag", function(self) ns.Drop(self) end)
    addBox:SetScript("OnMouseUp", function(self)
        if GetCursorInfo() then ns.Drop(self) end
    end)
    local function Put(link)
        addBox:SetFocus()
        addBox:Insert(link)
    end
    local here = ns.Button(listPane, "Mark spot", 70)
    here:SetPoint("BOTTOMRIGHT", 0, 24)
    here:SetScript("OnClick", function() Here(Put) end)
    ns.Tip(here, "Mark this spot",
        "Saves where you stand as a link, a reminder of where the task is. Click it later to put a pin on your "
        .. "map (Classic Era: its coordinates in chat). It doesn't tick the task.")
    local dungeon = ns.Button(listPane, "Dungeon", 60)
    dungeon:SetPoint("RIGHT", here, "LEFT", -4, 0)
    dungeon:SetScript("OnClick", function() DungeonPicker(Put) end)
    ns.Tip(dungeon, "Link a dungeon", "Ticks when you leave it with a boss down, or when the boss you pick dies.")
    local quest = ns.Button(listPane, "Quest", 50)
    quest:SetPoint("RIGHT", dungeon, "LEFT", -4, 0)
    quest:SetScript("OnClick", function() QuestPicker(Put) end)
    ns.Tip(quest, "Link a quest from your log", "Ticks when you turn it in.")
    addDaily = CreateFrame("CheckButton", nil, listPane, "UICheckButtonTemplate")
    addDaily:SetSize(22, 22)
    addDaily:SetPoint("RIGHT", quest, "LEFT", -48, 0)
    local dl = ns.Text(addDaily)
    dl:SetPoint("LEFT", addDaily, "RIGHT", 0, 1)
    dl:SetText("Daily")
    addDaily:SetHitRectInsets(0, -36, 0, 0)
    addDaily:SetScript("OnClick", function(self) ns.char.addDaily = self:GetChecked() and true or nil end)
    ns.Tip(addDaily, "New tasks are daily", "Daily tasks uncheck themselves at the daily reset.")
    addBox:SetPoint("RIGHT", addDaily, "LEFT", -6, 0)

    footer = ns.Text(listPane)
    footer:SetPoint("BOTTOMLEFT", 2, 4)
    footer:SetPoint("RIGHT")
    footer:SetJustifyH("LEFT")
    footer:SetTextColor(0.65, 0.65, 0.65)
end

local function Build()
    window = CreateFrame("Frame", "EzNotebookFrame", UIParent, "BackdropTemplate")
    window:SetFrameStrata("HIGH")
    window:SetToplevel(true)
    window:EnableMouse(true)
    window:SetMovable(true)
    window:SetResizable(true)
    if window.SetResizeBounds then window:SetResizeBounds(MIN_W, MIN_H, 1400, 1000) end
    window:SetClampedToScreen(true)
    window:RegisterForDrag("LeftButton")
    window:SetScript("OnDragStart", window.StartMoving)
    window:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        SavePlace()
    end)
    ns.Skin(window)
    window:Hide()
    tinsert(UISpecialFrames, "EzNotebookFrame")
    ns.PlaceWindow()

    local title = ns.Text(window, "GameFontNormal")
    title:SetPoint("TOPLEFT", PAD + 2, -PAD - 4)
    title:SetText("Notebook")
    local close = ns.Button(window, "x", 22)
    close:SetPoint("TOPRIGHT", -PAD, -PAD)
    close:SetScript("OnClick", function() window:Hide() end)
    local opts = ns.Button(window, "Options", 60)
    opts:SetPoint("RIGHT", close, "LEFT", -4, 0)
    opts:SetScript("OnClick", OptionsMenu)

    -- Resize grip.
    local grip = CreateFrame("Button", nil, window)
    grip:SetSize(16, 16)
    grip:SetPoint("BOTTOMRIGHT", -2, 2)
    grip:SetNormalTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Up")
    grip:SetHighlightTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Highlight")
    grip:SetScript("OnMouseDown", function() window:StartSizing("BOTTOMRIGHT") end)
    grip:SetScript("OnMouseUp", function()
        window:StopMovingOrSizing()
        SavePlace()
        ns.RedrawWindow()
    end)
    window:SetScript("OnSizeChanged", function()
        if window:IsShown() then ns.RedrawWindow() end
    end)

    -- Search.
    search = ns.Edit(window, 22)
    search:SetPoint("TOPLEFT", PAD, -36)
    search:SetWidth(TREE_W)
    searchHint = ns.Text(search)
    searchHint:SetPoint("LEFT", 8, 0)
    searchHint:SetPoint("RIGHT", -6, 0)
    searchHint:SetJustifyH("LEFT")
    searchHint:SetWordWrap(false)
    searchHint:SetTextColor(0.5, 0.5, 0.5)
    searchHint:SetText("Search every page")
    search:SetScript("OnTextChanged", function(self, userInput)
        searchHint:SetShown(self:GetText() == "")
        if not userInput then return end
        query = ns.Trim(self:GetText())
        treeOffset = 0
        DrawTree()
    end)
    search:SetScript("OnEnterPressed", search.ClearFocus)
    search:SetScript("OnEscapePressed", function(self)
        self:SetText("")
        query = nil
        self:ClearFocus()
        DrawTree()
    end)

    treePane = CreateFrame("Frame", nil, window, "BackdropTemplate")
    treePane:SetPoint("TOPLEFT", search, "BOTTOMLEFT", 0, -6)
    treePane:SetPoint("BOTTOMLEFT", PAD, PAD + 28)
    treePane:SetWidth(TREE_W)
    ns.Skin(treePane, 0.5, 0.02)
    Scroller(treePane, 3, function() return treeOffset end, function(v) treeOffset = v end)
    empty = {}
    empty.tree = ns.Text(treePane)
    empty.tree:SetPoint("TOP", 0, -12)
    empty.tree:SetTextColor(0.6, 0.6, 0.6)

    local function Selection()
        local p = Selected()
        if p then return p.folder end
    end
    local bw = math.floor((TREE_W - 8) / 3)
    local nf = ns.Button(window, "+ Folder", bw)
    nf:SetPoint("BOTTOMLEFT", PAD, PAD)
    nf:SetScript("OnClick", function() NewFolderIn(Selection()) end)
    ns.Tip(nf, "New folder", "Made next to the open page. Right-click a folder to make one inside it.")
    local nn = ns.Button(window, "+ Note", bw)
    nn:SetPoint("LEFT", nf, "RIGHT", 4, 0)
    nn:SetScript("OnClick", function() NewPageIn("note", Selection()) end)
    local nl = ns.Button(window, "+ List", bw)
    nl:SetPoint("LEFT", nn, "RIGHT", 4, 0)
    nl:SetScript("OnClick", function() NewPageIn("list", Selection()) end)

    right = CreateFrame("Frame", nil, window)
    right:SetPoint("TOPLEFT", treePane, "TOPRIGHT", PAD + 2, 30)
    right:SetPoint("BOTTOMRIGHT", -PAD - 10, PAD)
    header = right:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    header:SetPoint("TOPLEFT", 0, 0)
    header:SetPoint("RIGHT", 0, 0)
    header:SetJustifyH("LEFT")
    header:SetWordWrap(false)
    sub = ns.Text(right)
    sub:SetPoint("TOPLEFT", header, "BOTTOMLEFT", 0, -6)
    sub:SetPoint("RIGHT", 0, 0)
    sub:SetJustifyH("LEFT")
    sub:SetTextColor(0.65, 0.65, 0.65)
    local pageMenu = CreateFrame("Button", nil, right)
    pageMenu:SetAllPoints(header)
    pageMenu:RegisterForClicks("RightButtonUp", "LeftButtonUp")
    pageMenu:SetScript("OnClick", function(_, button)
        local p = Selected()
        if not p then return end
        if button == "RightButton" then return PageMenu(p) end
        ns.Ask("Rename", p.title, function(text)
            text = ns.OneLine(text)
            if text == "" then return "Give it a name." end
            p.title = text
            ns.Refresh()
        end)
    end)
    ns.Tip(pageMenu, "Click to rename", "Right-click for this page's options.")
    empty.page = ns.Text(right, "GameFontHighlight")
    empty.page:SetPoint("CENTER", 0, 20)
    empty.page:SetTextColor(0.6, 0.6, 0.6)
    empty.page:SetText("Pick a page on the left, or make one with + Note or + List.")

    BuildNote()
    BuildList()

    window:SetScript("OnShow", function()
        ns.RedrawWindow()
        C_Timer.After(0, ns.RedrawWindow) -- sizes are known after the first frame
    end)
    window:SetScript("OnHide", function()
        StopEdit()
        ns.CloseMenu()
    end)
end

-- Open on a page (or the last one), optionally searching, optionally with the add box focused.
function ns.Open(pageId, find, focusAdd)
    if not window then Build() end
    if pageId then
        StopEdit()
        ns.char.sel = pageId
        local p = Db().pages[pageId]
        local f = p and p.folder and Db().folders[p.folder]
        while f do
            f.open = true
            f = f.parent and Db().folders[f.parent]
        end
    end
    if find then
        search:SetText(find)
        query = ns.Trim(find)
        searchHint:SetShown(find == "")
    end
    if window:IsShown() then ns.RedrawWindow() else window:Show() end
    if focusAdd then
        local p = Selected()
        if p and p.kind == "list" then addBox:SetFocus() end
    end
end

function ns.Toggle()
    if window and window:IsShown() then
        window:Hide()
    else
        ns.Open()
    end
end
