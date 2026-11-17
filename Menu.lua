-- Flat look helpers, our own right-click menu and a one-line name prompt. Own frames only: Blizzard's menus
-- crash in combat on Forever, and nothing here is protected.
local _, ns = ...

local WHITE = "Interface\\Buttons\\WHITE8x8"
ns.FLAT = { bgFile = WHITE, edgeFile = WHITE, edgeSize = 1 }
ns.GOLD = { 1, 0.82, 0, 1 }

function ns.Skin(f, alpha, shade)
    f:SetBackdrop(ns.FLAT)
    shade = shade or 0.05
    f:SetBackdropColor(shade, shade, shade + 0.01, alpha or 0.94)
    f:SetBackdropBorderColor(1, 1, 1, 0.08)
end

function ns.Text(parent, font)
    return parent:CreateFontString(nil, "OVERLAY", font or "GameFontHighlightSmall")
end

function ns.Tip(frame, title, body)
    frame:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:AddLine(title, 1, 1, 1)
        if body then GameTooltip:AddLine(body, 0.85, 0.85, 0.85, true) end
        GameTooltip:Show()
    end)
    frame:SetScript("OnLeave", function() GameTooltip:Hide() end)
end

function ns.Button(parent, label, width, height)
    local b = CreateFrame("Button", nil, parent, "BackdropTemplate")
    b:SetSize(width, height or 20)
    ns.Skin(b, 0.7, 0.09)
    local hl = b:CreateTexture(nil, "HIGHLIGHT")
    hl:SetAllPoints()
    hl:SetColorTexture(1, 1, 1, 0.08)
    b.text = ns.Text(b)
    b.text:SetPoint("LEFT", 4, 0)
    b.text:SetPoint("RIGHT", -4, 0)
    b.text:SetWordWrap(false)
    b.text:SetJustifyH("CENTER")
    b.text:SetText(label)
    b:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    return b
end

-- A one-line edit box in our look.
function ns.Edit(parent, height)
    local e = CreateFrame("EditBox", nil, parent, "BackdropTemplate")
    e:SetHeight(height or 22)
    ns.Skin(e, 0.9, 0.02)
    e:SetFontObject("ChatFontNormal")
    e:SetTextInsets(6, 6, 0, 0)
    e:SetAutoFocus(false)
    e:SetScript("OnEscapePressed", e.ClearFocus)
    return e
end

---------------------------------------------------------------------------
-- Menu: ns.Menu(entries) at the cursor. entry = { text, func, checked = bool, disabled, title, color = hex,
-- tip }. Clicking outside, Escape or picking closes it.
---------------------------------------------------------------------------
local menu, catcher, rows = nil, nil, {}
local ROW_H, PAD = 18, 4

local function CloseMenu()
    if menu then menu:Hide() end
    if catcher then catcher:Hide() end
end
ns.CloseMenu = CloseMenu

local function Row(i)
    if rows[i] then return rows[i] end
    local r = CreateFrame("Button", nil, menu)
    r:SetHeight(ROW_H)
    local hl = r:CreateTexture(nil, "HIGHLIGHT")
    hl:SetAllPoints()
    hl:SetColorTexture(1, 0.82, 0, 0.15)
    r.check = r:CreateTexture(nil, "ARTWORK")
    r.check:SetSize(12, 12)
    r.check:SetPoint("LEFT", 4, 0)
    r.check:SetTexture("Interface\\Buttons\\UI-CheckBox-Check")
    r.text = ns.Text(r, "GameFontHighlightSmall")
    r.text:SetPoint("LEFT", 20, 0)
    r.text:SetJustifyH("LEFT")
    r:SetScript("OnClick", function(self)
        local e = self.entry
        if not e or e.disabled or e.title then return end
        CloseMenu()
        if e.func then e.func() end
    end)
    r:SetScript("OnEnter", function(self)
        local e = self.entry
        if e and e.tip then
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:AddLine(e.tip, 1, 1, 1, true)
            GameTooltip:Show()
        end
    end)
    r:SetScript("OnLeave", function() GameTooltip:Hide() end)
    rows[i] = r
    return r
end

function ns.Menu(entries)
    if not menu then
        catcher = CreateFrame("Button", nil, UIParent)
        catcher:SetAllPoints(UIParent)
        catcher:SetFrameStrata("FULLSCREEN_DIALOG")
        catcher:RegisterForClicks("AnyUp")
        catcher:SetScript("OnClick", CloseMenu)
        menu = CreateFrame("Frame", "EzNotebookMenu", UIParent, "BackdropTemplate")
        menu:SetFrameStrata("FULLSCREEN_DIALOG")
        menu:SetFrameLevel(catcher:GetFrameLevel() + 10)
        menu:SetClampedToScreen(true)
        menu:EnableMouse(true)
        ns.Skin(menu, 0.97, 0.07)
        menu:SetScript("OnHide", function() if catcher then catcher:Hide() end end)
        tinsert(UISpecialFrames, "EzNotebookMenu")
    end
    local width = 120
    for i, e in ipairs(entries) do
        local r = Row(i)
        r.entry = e
        local label = e.text
        if e.color then label = "|cff" .. e.color .. label .. "|r" end
        r.text:SetText(label)
        if e.title then
            r.text:SetTextColor(1, 0.82, 0)
            r.text:SetPoint("LEFT", 6, 0)
        else
            r.text:SetPoint("LEFT", 20, 0)
            if e.disabled then r.text:SetTextColor(0.5, 0.5, 0.5) else r.text:SetTextColor(1, 1, 1) end
        end
        r.check:SetShown(e.checked == true)
        r:ClearAllPoints()
        r:SetPoint("TOPLEFT", PAD, -PAD - (i - 1) * ROW_H)
        r:SetPoint("RIGHT", -PAD, 0)
        r:Show()
        width = math.max(width, r.text:GetStringWidth() + 32)
    end
    for i = #entries + 1, #rows do rows[i]:Hide() end
    menu:SetSize(math.min(width, 360) + 2 * PAD, #entries * ROW_H + 2 * PAD)
    local scale = UIParent:GetEffectiveScale()
    local x, y = GetCursorPosition()
    menu:ClearAllPoints()
    menu:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", x / scale - 4, y / scale + 4)
    catcher:Show()
    menu:Show()
    return menu
end

---------------------------------------------------------------------------
-- Ask: a small prompt with one line to fill (names, counts). onOk(text) returns an error text to stay open.
---------------------------------------------------------------------------
local ask

function ns.Ask(title, default, onOk, maxLetters, numeric)
    if not ask then
        ask = CreateFrame("Frame", "EzNotebookAsk", UIParent, "BackdropTemplate")
        ask:SetSize(300, 96)
        ask:SetFrameStrata("FULLSCREEN_DIALOG")
        ask:SetPoint("CENTER", 0, 120)
        ask:EnableMouse(true)
        ns.Skin(ask, 0.97, 0.07)
        ask:SetBackdropBorderColor(1, 0.82, 0, 0.5)
        ask.title = ns.Text(ask, "GameFontNormal")
        ask.title:SetPoint("TOPLEFT", 10, -10)
        ask.title:SetPoint("RIGHT", -10, 0)
        ask.title:SetJustifyH("LEFT")
        ask.edit = ns.Edit(ask)
        ask.edit:SetPoint("TOPLEFT", 10, -32)
        ask.edit:SetPoint("RIGHT", -10, 0)
        ask.err = ns.Text(ask)
        ask.err:SetPoint("BOTTOMLEFT", 10, 12)
        ask.err:SetTextColor(1, 0.4, 0.4)
        ask.ok = ns.Button(ask, "OK", 60)
        ask.ok:SetPoint("BOTTOMRIGHT", -76, 8)
        ask.cancel = ns.Button(ask, "Cancel", 60)
        ask.cancel:SetPoint("BOTTOMRIGHT", -10, 8)
        local function Ok()
            local err = ask.onOk and ask.onOk(ask.edit:GetText())
            if err then return ask.err:SetText(err) end
            ask:Hide()
        end
        ask.ok:SetScript("OnClick", Ok)
        ask.edit:SetScript("OnEnterPressed", Ok)
        ask.cancel:SetScript("OnClick", function() ask:Hide() end)
        ask.edit:SetScript("OnEscapePressed", function() ask:Hide() end)
        ask:SetScript("OnHide", function() ask.edit:ClearFocus() end)
        tinsert(UISpecialFrames, "EzNotebookAsk")
    end
    ask.title:SetText(title)
    ask.err:SetText("")
    ask.onOk = onOk
    ask.edit:SetMaxLetters(maxLetters or ns.MAX_TITLE)
    ask.edit:SetNumeric(numeric and true or false)
    ask.edit:SetText(default or "")
    ask:Show()
    ask.edit:SetFocus()
    ask.edit:HighlightText()
end

-- Yes/no for things that can't be undone.
function ns.Confirm(text, onYes)
    ns.Menu({
        { text = text, title = true },
        { text = "Yes", func = onYes },
        { text = "No" },
    })
end
