local ADDON, ns = ...

-- Robau Mod Suite hub: one window with a module list on the left, one settings panel
-- per module on the right, and a single minimap icon that opens it.
-- Visual language shared by every module: deep teal panel, thin aqua border,
-- gradient header strip, flat buttons, gold only for "something is happening".

ns.UI = {}
ns.Hub = { modules = {}, order = {} }
local UI, Hub = ns.UI, ns.Hub

UI.PAL = {
    panel  = { 0.04, 0.09, 0.11, 0.96 },
    panel2 = { 0.03, 0.07, 0.09, 1 },
    button = { 0.10, 0.22, 0.24, 1 },
    edge   = { 0.16, 0.55, 0.55, 1 },
    aqua   = { 0.30, 0.90, 0.80 },
    dim    = { 0.55, 0.65, 0.65 },
    gold   = { 1, 0.82, 0.10 },
    warn   = { 0.85, 0.25, 0.25 },
}
local PAL = UI.PAL

---------------------------------------------------------------------------
-- Look helpers (used by every module)
---------------------------------------------------------------------------
function UI.Border(frame, r, g, b, a, size, layer)
    size = size or 1
    local out = {}
    local defs = {
        { "TOPLEFT", "TOPRIGHT", nil, size }, { "BOTTOMLEFT", "BOTTOMRIGHT", nil, size },
        { "TOPLEFT", "BOTTOMLEFT", size, nil }, { "TOPRIGHT", "BOTTOMRIGHT", size, nil },
    }
    for i, d in ipairs(defs) do
        local t = frame:CreateTexture(nil, layer or "OVERLAY")
        t:SetColorTexture(r, g, b, a or 1)
        t:SetPoint(d[1])
        t:SetPoint(d[2])
        if d[3] then t:SetWidth(d[3]) end
        if d[4] then t:SetHeight(d[4]) end
        out[i] = t
    end
    return out
end

function UI.Panel(frame, color, edge)
    color = color or PAL.panel
    edge = edge or PAL.edge
    local bg = frame:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    bg:SetColorTexture(color[1], color[2], color[3], color[4] or 1)
    UI.Border(frame, edge[1], edge[2], edge[3], edge[4] or 1, 1, "BORDER")
    return bg
end

-- Header bar with gradient, icon and title. Returns the bar (a frame: usable as a drag handle).
function UI.HeaderStrip(frame, iconPath, title, height, tint)
    height = height or 22
    tint = tint or { 0.10, 0.38, 0.40 }
    local bar = CreateFrame("Frame", nil, frame)
    bar:SetPoint("TOPLEFT", 1, -1)
    bar:SetPoint("TOPRIGHT", -1, -1)
    bar:SetHeight(height)
    bar:EnableMouse(true)
    local tex = bar:CreateTexture(nil, "ARTWORK")
    tex:SetAllPoints()
    local ok = pcall(function()
        tex:SetColorTexture(1, 1, 1, 1)
        tex:SetGradient("HORIZONTAL", CreateColor(tint[1], tint[2], tint[3], 1), CreateColor(0.05, 0.12, 0.15, 1))
    end)
    if not ok then tex:SetColorTexture(tint[1] * 0.8, tint[2] * 0.8, tint[3] * 0.8, 1) end
    local x = 6
    if iconPath then
        local icon = bar:CreateTexture(nil, "OVERLAY")
        icon:SetSize(height - 6, height - 6)
        icon:SetPoint("LEFT", 6, 0)
        icon:SetTexture(iconPath)
        icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
        x = height + 2
    end
    local fs = bar:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    fs:SetPoint("LEFT", x, 0)
    fs:SetText(title or "")
    fs:SetTextColor(PAL.aqua[1], PAL.aqua[2], PAL.aqua[3])
    bar.title = fs
    return bar
end

-- Small "x" button for a header bar.
function UI.CloseX(bar, onclick)
    local b = CreateFrame("Button", nil, bar)
    b:SetSize(18, 18)
    b:SetPoint("RIGHT", -3, 0)
    local fs = b:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    fs:SetPoint("CENTER", 0, 1)
    fs:SetText("x")
    fs:SetTextColor(0.8, 0.85, 0.85)
    local hl = b:CreateTexture(nil, "HIGHLIGHT")
    hl:SetAllPoints()
    hl:SetColorTexture(1, 1, 1, 0.15)
    b:SetScript("OnClick", onclick)
    return b
end

local function flatButton(b, w, h)
    b:SetSize(w, h)
    local bg = b:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    bg:SetColorTexture(PAL.button[1], PAL.button[2], PAL.button[3], 1)
    UI.Border(b, PAL.edge[1], PAL.edge[2], PAL.edge[3], 1, 1, "BORDER")
    local hl = b:CreateTexture(nil, "HIGHLIGHT")
    hl:SetAllPoints()
    hl:SetColorTexture(1, 1, 1, 0.10)
    local fs = b:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    fs:SetPoint("CENTER")
    b.label = fs
    b.SetText = function(_, t) fs:SetText(t) end
    b.GetText = function() return fs:GetText() end
end

function UI.RawButton(parent, w, h, text)
    local b = CreateFrame("Button", nil, parent)
    flatButton(b, w, h)
    b:SetText(text or "")
    return b
end

---------------------------------------------------------------------------
-- Widgets used by module panels. Every widget gets a .refresh() and is stored in panel.widgets.
---------------------------------------------------------------------------
local function addWidget(panel, w)
    panel.widgets[#panel.widgets + 1] = w
end

function UI.Header(panel, text, x, y)
    local fs = panel:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    fs:SetPoint("TOPLEFT", x, y)
    fs:SetText(text)
    fs:SetTextColor(PAL.aqua[1], PAL.aqua[2], PAL.aqua[3])
    return fs
end

function UI.Note(panel, text, x, y, width)
    local fs = panel:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    fs:SetPoint("TOPLEFT", x, y)
    fs:SetWidth(width or 240)
    fs:SetJustifyH("LEFT")
    fs:SetTextColor(PAL.dim[1] + 0.2, PAL.dim[2] + 0.2, PAL.dim[3] + 0.2)
    fs:SetText(text)
    return fs
end

function UI.Check(panel, label, tip, x, y, get, set)
    local cb = CreateFrame("Button", nil, panel)
    cb:SetSize(250, 20)
    cb:SetPoint("TOPLEFT", x, y)

    local boxf = CreateFrame("Frame", nil, cb)
    boxf:SetSize(16, 16)
    boxf:SetPoint("LEFT", 0, 0)
    local bg = boxf:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    bg:SetColorTexture(0.02, 0.05, 0.06, 1)
    UI.Border(boxf, PAL.edge[1], PAL.edge[2], PAL.edge[3], 1, 1, "BORDER")
    local mark = boxf:CreateTexture(nil, "ARTWORK")
    mark:SetPoint("TOPLEFT", 3, -3)
    mark:SetPoint("BOTTOMRIGHT", -3, 3)
    mark:SetColorTexture(PAL.aqua[1], PAL.aqua[2], PAL.aqua[3], 1)

    local fs = cb:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    fs:SetPoint("LEFT", boxf, "RIGHT", 8, 0)
    fs:SetText(label)

    local hl = cb:CreateTexture(nil, "HIGHLIGHT")
    hl:SetAllPoints(boxf)
    hl:SetColorTexture(1, 1, 1, 0.12)

    local value = false
    cb.refresh = function()
        value = get() and true or false
        mark:SetShown(value)
    end
    cb:SetScript("OnClick", function()
        value = not value
        mark:SetShown(value)
        set(value)
        if panel.RefreshAll then panel.RefreshAll() end
    end)
    if tip then
        cb:SetScript("OnEnter", function(self)
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:SetText(tip, 1, 1, 1, 1, true)
        end)
        cb:SetScript("OnLeave", function() GameTooltip:Hide() end)
    end
    addWidget(panel, cb)
    return cb
end

function UI.Button(panel, text, width, x, y, onclick)
    local b = UI.RawButton(panel, width, 22, text)
    b:SetPoint("TOPLEFT", x, y)
    b:SetScript("OnClick", function(self) onclick(self) end)
    return b
end

function UI.EditBox(panel, width, x, y)
    local e = CreateFrame("EditBox", nil, panel)
    e:SetSize(width, 22)
    e:SetPoint("TOPLEFT", x, y)
    e:SetAutoFocus(false)
    e:SetFontObject(GameFontHighlight)
    e:SetTextInsets(6, 6, 0, 0)
    local bg = e:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    bg:SetColorTexture(0.02, 0.05, 0.06, 1)
    UI.Border(e, PAL.edge[1], PAL.edge[2], PAL.edge[3], 1, 1, "BORDER")
    e:SetScript("OnEscapePressed", e.ClearFocus)
    return e
end

-- "Label: value   [-] [+]"
function UI.Stepper(panel, labelFn, x, y, get, set, min, max, step)
    local fs = panel:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
    fs:SetPoint("TOPLEFT", x, y - 4)
    local function show() fs:SetText(labelFn(get())) end
    local function change(delta)
        local v = get() + delta
        if v < min then v = min end
        if v > max then v = max end
        v = math.floor(v / step + 0.5) * step
        set(v)
        show()
    end
    UI.Button(panel, "-", 24, x + 190, y, function() change(-step) end)
    UI.Button(panel, "+", 24, x + 218, y, function() change(step) end)
    local w = { refresh = show }
    addWidget(panel, w)
    return w
end

---------------------------------------------------------------------------
-- Hub registry and window
---------------------------------------------------------------------------
-- id, title, icon path, one-line description, build(panel), optional status() -> string
function Hub.Register(id, title, icon, desc, build, status)
    Hub.modules[id] = { id = id, title = title, icon = icon, desc = desc, build = build, status = status }
    Hub.order[#Hub.order + 1] = id
end

local win, content, sidebarButtons
local panels = {}
local current

local function select(id)
    local def = Hub.modules[id]
    if not def then return end
    current = id
    for _, p in pairs(panels) do p:Hide() end
    for bid, b in pairs(sidebarButtons) do b.sel:SetShown(bid == id) end

    local p = panels[id]
    if not p then
        p = CreateFrame("Frame", nil, content)
        p:SetAllPoints()
        p.widgets = {}
        p.RefreshAll = function()
            for _, w in ipairs(p.widgets) do pcall(w.refresh) end
        end
        local title = p:CreateFontString(nil, "ARTWORK", "GameFontNormalHuge")
        title:SetPoint("TOPLEFT", 14, -12)
        title:SetText(def.title)
        title:SetTextColor(PAL.aqua[1], PAL.aqua[2], PAL.aqua[3])
        local desc = p:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
        desc:SetPoint("TOPLEFT", 14, -38)
        desc:SetWidth(480)
        desc:SetJustifyH("LEFT")
        desc:SetTextColor(PAL.dim[1] + 0.2, PAL.dim[2] + 0.2, PAL.dim[3] + 0.2)
        desc:SetText(def.desc or "")
        local line = p:CreateTexture(nil, "ARTWORK")
        line:SetPoint("TOPLEFT", 12, -56)
        line:SetPoint("TOPRIGHT", -12, -56)
        line:SetHeight(1)
        line:SetColorTexture(PAL.edge[1], PAL.edge[2], PAL.edge[3], 0.6)
        local ok, err = pcall(def.build, p)
        if not ok then
            local e = p:CreateFontString(nil, "ARTWORK", "GameFontRed")
            e:SetPoint("TOPLEFT", 12, -80)
            e:SetWidth(480)
            e:SetText("Could not build this panel: " .. tostring(err))
        end
        panels[id] = p
    end
    p:Show()
    p.RefreshAll()
end

local function build()
    win = CreateFrame("Frame", "RobauModSuiteHub", UIParent)
    win:SetSize(780, 500)
    win:SetPoint("CENTER")
    win:SetFrameStrata("DIALOG")
    win:SetMovable(true)
    win:EnableMouse(true)
    win:SetClampedToScreen(true)
    UI.Panel(win)
    tinsert(UISpecialFrames, "RobauModSuiteHub")

    local bar = UI.HeaderStrip(win, "Interface\\Icons\\INV_Misc_Gear_01", "Robau Mod Suite", 28)
    bar.title:SetFontObject(GameFontNormal)
    bar:RegisterForDrag("LeftButton")
    bar:SetScript("OnDragStart", function() win:StartMoving() end)
    bar:SetScript("OnDragStop", function() win:StopMovingOrSizing() end)
    UI.CloseX(bar, function() win:Hide() end)

    local side = CreateFrame("Frame", nil, win)
    side:SetPoint("TOPLEFT", 8, -36)
    side:SetPoint("BOTTOMLEFT", 8, 8)
    side:SetWidth(172)
    local sbg = side:CreateTexture(nil, "BACKGROUND")
    sbg:SetAllPoints()
    sbg:SetColorTexture(PAL.panel2[1], PAL.panel2[2], PAL.panel2[3], 1)
    UI.Border(side, PAL.edge[1], PAL.edge[2], PAL.edge[3], 0.5, 1, "BORDER")

    content = CreateFrame("Frame", nil, win)
    content:SetPoint("TOPLEFT", side, "TOPRIGHT", 8, 0)
    content:SetPoint("BOTTOMRIGHT", -8, 8)
    local cbg = content:CreateTexture(nil, "BACKGROUND")
    cbg:SetAllPoints()
    cbg:SetColorTexture(PAL.panel2[1], PAL.panel2[2], PAL.panel2[3], 1)
    UI.Border(content, PAL.edge[1], PAL.edge[2], PAL.edge[3], 0.5, 1, "BORDER")

    sidebarButtons = {}
    local y = -6
    for _, id in ipairs(Hub.order) do
        local def = Hub.modules[id]
        local b = CreateFrame("Button", nil, side)
        b:SetSize(160, 36)
        b:SetPoint("TOPLEFT", 6, y)
        b.sel = CreateFrame("Frame", nil, b)
        b.sel:SetAllPoints()
        local selbg = b.sel:CreateTexture(nil, "BACKGROUND")
        selbg:SetAllPoints()
        selbg:SetColorTexture(PAL.edge[1], PAL.edge[2], PAL.edge[3], 0.22)
        local accent = b.sel:CreateTexture(nil, "ARTWORK")
        accent:SetPoint("TOPLEFT")
        accent:SetPoint("BOTTOMLEFT")
        accent:SetWidth(3)
        accent:SetColorTexture(PAL.aqua[1], PAL.aqua[2], PAL.aqua[3], 1)
        b.sel:Hide()
        local hl = b:CreateTexture(nil, "HIGHLIGHT")
        hl:SetAllPoints()
        hl:SetColorTexture(1, 1, 1, 0.08)
        local icon = b:CreateTexture(nil, "ARTWORK")
        icon:SetSize(24, 24)
        icon:SetPoint("LEFT", 10, 0)
        icon:SetTexture(def.icon)
        icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
        local t = b:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
        t:SetPoint("LEFT", icon, "RIGHT", 8, 0)
        t:SetPoint("RIGHT", -4, 0)
        t:SetJustifyH("LEFT")
        t:SetText(def.title)
        b:SetScript("OnClick", function() select(id) end)
        sidebarButtons[id] = b
        y = y - 40
    end
end

function Hub.Open(id)
    if not win then
        local ok, err = pcall(build)
        if not ok then
            print("|cffffd100Robau Mod Suite|r: could not build the window: " .. tostring(err))
            win = nil
            return
        end
    end
    win:Show()
    select(id or current or Hub.order[1])
end

function Hub.Toggle()
    if win and win:IsShown() then win:Hide() else Hub.Open() end
end

---------------------------------------------------------------------------
-- Overview panel (first entry): short catalog and the minimap icon switch
---------------------------------------------------------------------------
local function buildOverview(p)
    UI.Header(p, "Modules", 14, -72)
    local y = -96
    for _, id in ipairs(Hub.order) do
        local def = Hub.modules[id]
        if id ~= "overview" then
            UI.Button(p, def.title, 150, 14, y, function() Hub.Open(id) end)
            UI.Note(p, def.desc or "", 176, y - 3, 320)
            y = y - 40
        end
    end
    UI.Header(p, "Minimap icon", 14, y - 8)
    UI.Check(p, "Show the Robau Mod Suite icon at the minimap",
        "One icon for all modules. Left click opens this window. Drag to move.", 14, y - 32,
        function() return not (ns.suiteDB and ns.suiteDB.minimap.hide) end,
        function(v)
            ns.suiteDB.minimap.hide = not v
            if ns.UpdateSuiteMinimap then ns.UpdateSuiteMinimap() end
        end)
    UI.Note(p, "Chat shortcuts still exist if you want them: /robau, /xeno, /lfgmsg, /rst, /lazyfish.",
        14, y - 68, 480)
end

Hub.Register("overview", "Overview", "Interface\\Icons\\INV_Misc_Gear_01",
    "Everything in one place. Pick a module on the left to change its settings.", buildOverview)

---------------------------------------------------------------------------
-- Minimap icon (single, for the whole suite)
---------------------------------------------------------------------------
local btn

local function place()
    local angle = math.rad(ns.suiteDB.minimap.angle or 215)
    local w = Minimap:GetWidth()
    if not w or w < 50 then w = 140 end
    local radius = (w / 2) + 5
    btn:ClearAllPoints()
    btn:SetPoint("CENTER", Minimap, "CENTER", math.cos(angle) * radius, math.sin(angle) * radius)
end

local function tooltip(self)
    GameTooltip:SetOwner(self, "ANCHOR_LEFT")
    GameTooltip:AddLine("Robau Mod Suite")
    for _, id in ipairs(Hub.order) do
        local def = Hub.modules[id]
        if def.status then
            local ok, s = pcall(def.status)
            if ok and s then GameTooltip:AddDoubleLine(def.title, s, 1, 1, 1, PAL.aqua[1], PAL.aqua[2], PAL.aqua[3]) end
        end
    end
    GameTooltip:AddLine(" ")
    GameTooltip:AddLine("Left click: settings", 0.7, 0.7, 0.7)
    GameTooltip:AddLine("Drag: move icon", 0.7, 0.7, 0.7)
    GameTooltip:Show()
end

local function createMinimapButton()
    btn = CreateFrame("Button", "RobauModSuiteMinimapButton", Minimap)
    btn:SetSize(31, 31)
    btn:SetFrameStrata("HIGH")
    btn:SetFrameLevel(50)
    btn:RegisterForClicks("LeftButtonUp")
    btn:RegisterForDrag("LeftButton")
    btn:SetHighlightTexture("Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight")

    local bg = btn:CreateTexture(nil, "BACKGROUND")
    bg:SetSize(20, 20)
    bg:SetPoint("CENTER")
    bg:SetColorTexture(PAL.panel[1], PAL.panel[2], PAL.panel[3], 1)

    local icon = btn:CreateTexture(nil, "ARTWORK")
    icon:SetSize(17, 17)
    icon:SetPoint("CENTER")
    icon:SetTexture("Interface\\Icons\\INV_Misc_Gear_01")
    icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)

    local border = btn:CreateTexture(nil, "OVERLAY")
    border:SetSize(53, 53)
    border:SetPoint("TOPLEFT")
    border:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")

    btn:SetScript("OnClick", function() Hub.Toggle() end)
    btn:SetScript("OnEnter", tooltip)
    btn:SetScript("OnLeave", function() GameTooltip:Hide() end)
    btn:SetScript("OnDragStart", function(self)
        self:SetScript("OnUpdate", function()
            local mx, my = Minimap:GetCenter()
            local scale = Minimap:GetEffectiveScale()
            local cx, cy = GetCursorPosition()
            ns.suiteDB.minimap.angle = math.deg(math.atan2(cy / scale - my, cx / scale - mx))
            place()
        end)
    end)
    btn:SetScript("OnDragStop", function(self) self:SetScript("OnUpdate", nil) end)
end

function ns.UpdateSuiteMinimap()
    if not ns.suiteDB or not Minimap then return end
    if not btn then
        local ok, err = pcall(createMinimapButton)
        if not ok then
            print("|cffffd100Robau Mod Suite|r: minimap icon failed: " .. tostring(err))
            return
        end
    end
    place()
    if ns.suiteDB.minimap.hide then btn:Hide() else btn:Show() end
end

---------------------------------------------------------------------------
-- Boot and slash command
---------------------------------------------------------------------------
local ev = CreateFrame("Frame")
ev:RegisterEvent("ADDON_LOADED")
ev:RegisterEvent("PLAYER_LOGIN")
ev:SetScript("OnEvent", function(self, event, name)
    if event == "ADDON_LOADED" and name == ADDON then
        RobauModSuiteDB = RobauModSuiteDB or {}
        local d = RobauModSuiteDB
        if type(d.minimap) ~= "table" then d.minimap = { hide = false, angle = 215 } end
        if d.minimap.hide == nil then d.minimap.hide = false end
        if d.minimap.angle == nil then d.minimap.angle = 215 end
        ns.suiteDB = d
    elseif event == "PLAYER_LOGIN" then
        ns.UpdateSuiteMinimap()
    end
end)

SLASH_ROBAUMODSUITE1 = "/robau"
SlashCmdList.ROBAUMODSUITE = function(input)
    local cmd = (input or ""):match("^(%S*)"):lower()
    if cmd == "minimap" and ns.suiteDB then
        ns.suiteDB.minimap.hide = not ns.suiteDB.minimap.hide
        ns.UpdateSuiteMinimap()
    else
        Hub.Toggle()
    end
end
