-- The minimap button (drag it around the rim) and the entry in Forever's addon drawer, each with its own
-- show/hide option (db.minimap, db.drawer). Both, like the launcher icon above the chat, go through ns.Launch and
-- ns.LauncherTooltip. The drawer entry is registered at run time (AddonCompartmentFrame:RegisterAddon, which
-- Blizzard's source documents for addons) instead of in the TOC, so it can be taken out again; Era has no drawer.
local _, ns = ...

local DEFAULT_ANGLE = 200 -- degrees, counterclockwise from the right: left side, a bit low
local RIM = 5             -- how far past the minimap's edge the button's center sits

-- Left: open or close the notebook. Right: add a task to the /todo list.
function ns.Launch(which)
    if which == "RightButton" then
        ns.Open(ns.Inbox().id, nil, true)
    else
        ns.Toggle()
    end
end

function ns.LauncherTooltip(tip)
    tip:AddLine("EzNotebook")
    local inbox = ns.Inbox()
    local open = ns.CountOpen(inbox, ns.me, ns.Reset())
    tip:AddLine(("%s: %d left"):format(inbox.title, open), 1, 0.82, 0)
    tip:AddLine("Click: open the notebook", 0.8, 0.8, 0.8)
    tip:AddLine(("Right-click: add to %s"):format(inbox.title), 0.8, 0.8, 0.8)
    tip:Show()
end

---------------------------------------------------------------------------
-- Minimap button
---------------------------------------------------------------------------
local button, tex

local function Clamp(v) return math.max(-1, math.min(1, v)) end

-- On the minimap's rim at the saved angle (the corners of a square minimap, when an addon made it one and
-- says so through GetMinimapShape).
function ns.PlaceMinimap()
    if not button then return end
    local a = math.rad(ns.db.minimapAngle or DEFAULT_ANGLE)
    local x, y = math.cos(a), math.sin(a)
    if GetMinimapShape and GetMinimapShape() == "SQUARE" then
        x, y = Clamp(x * 1.4142), Clamp(y * 1.4142)
    end
    button:ClearAllPoints()
    button:SetPoint("CENTER", Minimap, "CENTER", x * (Minimap:GetWidth() / 2 + RIM),
        y * (Minimap:GetHeight() / 2 + RIM))
end

local function Drag()
    local mx, my = Minimap:GetCenter()
    local cx, cy = GetCursorPosition()
    local scale = Minimap:GetEffectiveScale()
    ns.db.minimapAngle = math.deg(math.atan2(cy / scale - my, cx / scale - mx)) % 360
    ns.PlaceMinimap()
end

local function BuildMinimap()
    button = CreateFrame("Button", "EzNotebookMinimapButton", Minimap)
    button:SetSize(31, 31)
    button:SetFrameStrata("MEDIUM")
    button:SetFrameLevel(Minimap:GetFrameLevel() + 8)
    button:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    button:RegisterForDrag("LeftButton")
    button:SetHighlightTexture("Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight")
    local border = button:CreateTexture(nil, "OVERLAY")
    border:SetSize(53, 53)
    border:SetPoint("TOPLEFT")
    border:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")
    local back = button:CreateTexture(nil, "BACKGROUND")
    back:SetSize(20, 20)
    back:SetPoint("TOPLEFT", 7, -5)
    back:SetTexture("Interface\\Minimap\\UI-Minimap-Background")
    tex = button:CreateTexture(nil, "ARTWORK")
    tex:SetSize(17, 17)
    tex:SetPoint("TOPLEFT", 7, -6)
    tex:SetTexture(ns.ICON)
    tex:SetTexCoord(0.05, 0.95, 0.05, 0.95)

    button:SetScript("OnClick", function(_, which) ns.Launch(which) end)
    button:SetScript("OnMouseDown", function() tex:SetPoint("TOPLEFT", 8, -7) end)
    button:SetScript("OnMouseUp", function() tex:SetPoint("TOPLEFT", 7, -6) end)
    button:SetScript("OnDragStart", function(self)
        GameTooltip:Hide()
        self:LockHighlight()
        self:SetScript("OnUpdate", Drag)
    end)
    button:SetScript("OnDragStop", function(self)
        self:SetScript("OnUpdate", nil)
        self:UnlockHighlight()
        tex:SetPoint("TOPLEFT", 7, -6)
    end)
    button:SetScript("OnEnter", function(self)
        if self:GetScript("OnUpdate") then return end -- dragging
        GameTooltip:SetOwner(self, "ANCHOR_LEFT")
        ns.LauncherTooltip(GameTooltip)
        GameTooltip:AddLine("Drag: move it around the map", 0.8, 0.8, 0.8)
        GameTooltip:Show()
    end)
    button:SetScript("OnLeave", function() GameTooltip:Hide() end)
end

function ns.UpdateMinimap()
    if not Minimap then return end
    if not button then BuildMinimap() end
    button:SetShown(ns.db.minimap ~= false)
    ns.PlaceMinimap()
end

---------------------------------------------------------------------------
-- Addon drawer (Forever)
---------------------------------------------------------------------------
local drawerData

function ns.HasDrawer()
    return AddonCompartmentFrame ~= nil and AddonCompartmentFrame.RegisterAddon ~= nil
end

function ns.UpdateDrawer()
    if not ns.HasDrawer() then return end
    local frame = AddonCompartmentFrame
    local want = ns.db.drawer ~= false
    if want and not drawerData then
        drawerData = {
            text = "EzNotebook",
            icon = ns.ICON,
            notCheckable = true,
            func = function(_, input) ns.Launch(input and input.buttonName) end,
            funcOnEnter = function(btn)
                GameTooltip:SetOwner(btn, "ANCHOR_LEFT")
                ns.LauncherTooltip(GameTooltip)
            end,
            funcOnLeave = function() GameTooltip:Hide() end,
        }
        frame:RegisterAddon(drawerData)
    elseif not want and drawerData then
        for i, d in ipairs(frame.registeredAddons or {}) do
            if d == drawerData then
                table.remove(frame.registeredAddons, i)
                break
            end
        end
        drawerData = nil
        if frame.UpdateDisplay then frame:UpdateDisplay() end
    end
end
