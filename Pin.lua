-- A list pinned to the screen (its open tasks, tick them right there) and the launcher icon above the chat box.
-- Own flat frames; nothing protected.
local _, ns = ...

local PIN_W = 250
local PIN_ROWS = 8
local PIN_ROW_H = 18

local pin, pinRows = nil, {}
local icon

---------------------------------------------------------------------------
-- Pinned list
---------------------------------------------------------------------------
local function PinnedPage()
    local db = ns.db
    local p = db and db.pinned and db.pages[db.pinned]
    if p and p.kind == "list" and ns.PageShown(db, p, ns.me) then return p end
end

function ns.PlacePin()
    if not pin then return end
    pin:ClearAllPoints()
    local pos = ns.db.pinPos
    if pos then
        pin:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", pos[1], pos[2])
    else
        pin:SetPoint("TOPRIGHT", UIParent, "TOPRIGHT", -260, -220)
    end
end

local function PinRow(i)
    if pinRows[i] then return pinRows[i] end
    local r = CreateFrame("Frame", nil, pin)
    r:SetHeight(PIN_ROW_H)
    r:SetPoint("TOPLEFT", 4, -24 - (i - 1) * PIN_ROW_H)
    r:SetPoint("RIGHT", -6, 0)
    r.check = CreateFrame("CheckButton", nil, r, "UICheckButtonTemplate")
    r.check:SetSize(18, 18)
    r.check:SetPoint("LEFT")
    r.check:SetScript("OnClick", function(self)
        local p = PinnedPage()
        if p and r.item then
            ns.SetDone(p, r.item, ns.me, self:GetChecked() and true or false, time())
            ns.Refresh()
        end
    end)
    r.text = ns.Text(r)
    r.text:SetPoint("LEFT", r.check, "RIGHT", 2, 0)
    r.text:SetPoint("RIGHT")
    r.text:SetJustifyH("LEFT")
    r.text:SetWordWrap(false)
    r:EnableMouse(true)
    r:SetHyperlinksEnabled(true)
    r:SetScript("OnHyperlinkClick", function(_, link, text) ns.LinkClick(link, text) end)
    r:SetScript("OnHyperlinkEnter", function(self, link) ns.LinkEnter(self, link) end)
    r:SetScript("OnHyperlinkLeave", ns.LinkLeave)
    pinRows[i] = r
    return r
end

local function BuildPin()
    pin = CreateFrame("Frame", "EzNotebookPin", UIParent, "BackdropTemplate")
    pin:SetWidth(PIN_W)
    pin:SetFrameStrata("MEDIUM")
    pin:SetClampedToScreen(true)
    pin:SetMovable(true)
    pin:EnableMouse(true)
    pin:RegisterForDrag("LeftButton")
    pin:SetScript("OnDragStart", pin.StartMoving)
    pin:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        ns.db.pinPos = { self:GetLeft(), self:GetTop() }
    end)
    ns.Skin(pin, 0.6, 0.03)
    pin.title = ns.Text(pin, "GameFontNormalSmall")
    pin.title:SetPoint("TOPLEFT", 8, -7)
    pin.title:SetPoint("RIGHT", -8, 0)
    pin.title:SetJustifyH("LEFT")
    pin.title:SetWordWrap(false)
    pin.more = ns.Text(pin)
    pin.more:SetTextColor(0.6, 0.6, 0.6)
    pin:SetScript("OnMouseUp", function(_, button)
        if button ~= "RightButton" then return end
        local p = PinnedPage()
        ns.Menu({
            { text = p and p.title or "Pinned list", title = true },
            { text = "Open in the notebook", func = function() ns.Open(p and p.id) end },
            { text = "Unpin", func = function() ns.TogglePin(p) end },
        })
    end)
    ns.PlacePin()
end

function ns.RedrawPin()
    local p = PinnedPage()
    if not p then
        if pin then pin:Hide() end
        return
    end
    if not pin then BuildPin() end
    local reset = ns.Reset()
    local open = {}
    for _, item in ipairs(p.items or {}) do
        if not ns.IsDone(p, item, ns.me, reset) then open[#open + 1] = item end
    end
    pin.title:SetText(("%s |cff999999%d left|r"):format(p.title, #open))
    local shown = math.min(#open, PIN_ROWS)
    for i = 1, math.max(shown, #pinRows) do
        local item = open[i]
        local r = (i <= shown and item) and PinRow(i) or pinRows[i]
        if r then
            r:SetShown(i <= shown)
            if i <= shown then
                r.item = item
                r.check:SetChecked(false)
                local prog = ns.Progress(item)
                r.text:SetText(item.text .. (prog and (" |cff999999" .. prog .. "|r") or ""))
            end
        end
    end
    local h = 26 + shown * PIN_ROW_H
    pin.more:ClearAllPoints()
    pin.more:SetPoint("TOPLEFT", 10, -24 - shown * PIN_ROW_H)
    if #open == 0 then
        pin.more:SetText("|cff66dd66All done.|r")
        h = h + 14
    elseif #open > shown then
        pin.more:SetText(("+%d more"):format(#open - shown))
        h = h + 14
    else
        pin.more:SetText("")
    end
    pin:SetHeight(h + 4)
    pin:Show()
end

-- Pin a list (the open one if it's a list, else Today), or unpin it when it's the pinned one.
function ns.TogglePin(p)
    local db = ns.db
    p = p or (ns.char.sel and db.pages[ns.char.sel])
    if not p or p.kind ~= "list" then p = ns.Inbox() end
    if db.pinned == p.id then
        db.pinned = nil
        ns.Print(("Unpinned %s."):format(p.title))
    else
        db.pinned = p.id
        ns.Print(("Pinned %s to the screen. Drag it to move it, right-click it for options."):format(p.title))
    end
    ns.Refresh()
end

---------------------------------------------------------------------------
-- Launcher icon: in the row of our icons above the chat box, left of EzRecruit's.
---------------------------------------------------------------------------
local function PlaceIcon()
    icon:ClearAllPoints()
    local p = ns.db.iconPos
    if p then
        icon:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", p[1], p[2])
    else
        icon:SetPoint("BOTTOMRIGHT", ChatFrame1, "TOPRIGHT", -196, 28)
    end
end

local function BuildIcon()
    icon = CreateFrame("Button", "EzNotebookIcon", UIParent, "BackdropTemplate")
    icon:SetSize(24, 24)
    icon:SetFrameStrata("MEDIUM")
    icon:SetClampedToScreen(true)
    icon:SetMovable(true)
    icon:RegisterForDrag("LeftButton")
    icon:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    ns.Skin(icon, 0.6)
    icon:SetBackdropBorderColor(0, 0, 0, 1)
    icon:SetAlpha(0.7)
    local tex = icon:CreateTexture(nil, "ARTWORK")
    tex:SetPoint("TOPLEFT", 1, -1)
    tex:SetPoint("BOTTOMRIGHT", -1, 1)
    tex:SetTexture(ns.ICON)
    tex:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    icon:SetScript("OnDragStart", icon.StartMoving)
    icon:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        ns.db.iconPos = { self:GetLeft(), self:GetTop() }
    end)
    icon:SetScript("OnClick", function(_, button) ns.Launch(button) end)
    icon:SetScript("OnEnter", function(self)
        self:SetAlpha(1)
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        ns.LauncherTooltip(GameTooltip)
        GameTooltip:AddLine("Drag: move", 0.8, 0.8, 0.8)
        GameTooltip:Show()
    end)
    icon:SetScript("OnLeave", function(self)
        self:SetAlpha(0.7)
        GameTooltip:Hide()
    end)
end

function ns.UpdateIcon()
    if not icon then BuildIcon() end
    PlaceIcon()
    icon:SetShown(ns.db.icon ~= false)
end

-- At login (Core), once the saved variables exist.
function ns.Login()
    ns.UpdateIcon()
    ns.UpdateMinimap()
    ns.UpdateDrawer()
    ns.RedrawPin()
end
