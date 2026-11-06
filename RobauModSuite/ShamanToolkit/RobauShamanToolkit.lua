local ADDON, ns = ...

local function say(msg) print("|cff0070ddRobau Shaman Toolkit|r: " .. msg) end

---------------------------------------------------------------------------
-- Spell lists. Only the ones the character actually knows get a button.
-- Edit freely, or add your own with /rst add <spell name> <earth|fire|water|air|imbue>
---------------------------------------------------------------------------
local ELEMENTS = { "earth", "fire", "water", "air" }
local COLORS = {
    earth = { 0.65, 0.5, 0.25 }, fire = { 0.95, 0.3, 0.1 },
    water = { 0.2, 0.55, 1 },    air = { 0.7, 0.85, 1 },
}
local TOTEM_SLOT = { fire = 1, earth = 2, water = 3, air = 4 }

local TOTEMS = {
    earth = { "Stoneskin Totem", "Stoneclaw Totem", "Strength of Earth Totem", "Earthbind Totem", "Tremor Totem", "Earth Elemental Totem" },
    fire  = { "Searing Totem", "Fire Nova Totem", "Magma Totem", "Flametongue Totem", "Frost Resistance Totem", "Totem of Wrath", "Fire Elemental Totem" },
    water = { "Healing Stream Totem", "Mana Spring Totem", "Poison Cleansing Totem", "Disease Cleansing Totem", "Fire Resistance Totem", "Mana Tide Totem", "Cleansing Totem" },
    air   = { "Grounding Totem", "Windfury Totem", "Grace of Air Totem", "Nature Resistance Totem", "Sentry Totem", "Windwall Totem", "Tranquil Air Totem", "Wrath of Air Totem" },
}
local EXTRA = { "Totemic Call", "Totemic Recall" }

-- Order = preference for the imbue alert button.
local IMBUES = { "Windfury Weapon", "Flametongue Weapon", "Rockbiter Weapon", "Frostbrand Weapon", "Earthliving Weapon" }

---------------------------------------------------------------------------
-- Helpers
---------------------------------------------------------------------------
local db

local defaults = {
    point = "CENTER", x = 0, y = -150, scale = 1, locked = false, shown = true,
    alertEnabled = true, alertOffhand = false,
    spacing = 8, showTimer = false, showBar = true, showNumbers = true, defaultImbue = "auto",
    alertPoint = "CENTER", alertX = 0, alertY = 180,
    custom = {},        -- { {name="...", kind="earth"} }
}

local function copyDefaults(src, dst)
    for k, v in pairs(src) do
        if type(v) == "table" then
            if type(dst[k]) ~= "table" then dst[k] = {} end
            copyDefaults(v, dst[k])
        elseif dst[k] == nil then
            dst[k] = v
        end
    end
end

local function spellInfo(name)
    if C_Spell and C_Spell.GetSpellInfo then
        local ok, info = pcall(C_Spell.GetSpellInfo, name)
        if ok and type(info) == "table" and info.spellID then return info.spellID, info.iconID or info.originalIconID, info.name end
    end
    if GetSpellInfo then
        local ok, n, _, icon, _, _, _, id = pcall(GetSpellInfo, name)
        if ok and id then return id, icon, n end
    end
    return nil
end

local function isKnown(id)
    if not id then return false end
    if IsPlayerSpell and IsPlayerSpell(id) then return true end
    if C_SpellBook and C_SpellBook.IsSpellKnown and C_SpellBook.IsSpellKnown(id) then return true end
    if IsSpellKnown and IsSpellKnown(id) then return true end
    return false
end

-- Returns { id=, icon=, name= } or nil if the spell is not known.
local function lookup(name)
    local id, icon, real = spellInfo(name)
    if id and isKnown(id) then return { id = id, icon = icon, name = real or name } end
    return nil
end

---------------------------------------------------------------------------
-- Totem toolbox
---------------------------------------------------------------------------
local BTN, PAD, TITLE_H = 34, 6, 24
local function GAP() return (db and db.spacing) or 8 end
local box
local buttons = {}
local pendingRebuild = false

local function savePosition()
    local point, _, _, x, y = box:GetPoint()
    db.point, db.x, db.y = point, x, y
end

local updateNumbers, updateActive, snap   -- defined below, used by the box OnUpdate

local function makeBox()
    box = CreateFrame("Frame", "RobauShamanToolkitFrame", UIParent)
    box:SetFrameStrata("MEDIUM")
    box:SetClampedToScreen(true)
    box:SetMovable(true)
    box:SetPoint(db.point, UIParent, db.point, db.x, db.y)
    box:SetScale(db.scale)

    ns.UI.Panel(box)

    local handle = ns.UI.HeaderStrip(box, "Interface\\Icons\\Spell_Nature_StoneSkinTotem", "Robau Totems", 22)
    handle:RegisterForDrag("LeftButton")
    handle:SetScript("OnDragStart", function()
        if not db.locked and not InCombatLockdown() then box:StartMoving() end
    end)
    handle:SetScript("OnDragStop", function()
        box:StopMovingOrSizing()
        savePosition()
    end)
    ns.UI.CloseX(handle, function()
        db.shown = false
        box:Hide()
    end)
    box.handle = handle

    local acc, poll = 0, 0
    box:SetScript("OnUpdate", function(_, dt)
        acc = acc + dt
        poll = poll + dt
        if poll > 0.4 then
            poll = 0
            updateActive()
        end
        if acc > 0.2 then
            acc = 0
            updateNumbers()
        end
    end)
end

local function makeButton(spell, element)
    box.cache = box.cache or {}
    local existing = box.cache[spell.name]
    if existing then
        existing.element = element
        existing:Show()
        return existing
    end
    local b = CreateFrame("Button", nil, box, "SecureActionButtonTemplate")
    b:SetSize(BTN, BTN)
    b:RegisterForClicks("AnyUp", "AnyDown")
    b:SetAttribute("type", "spell")
    b:SetAttribute("spell", spell.name)

    local icon = b:CreateTexture(nil, "ARTWORK")
    icon:SetAllPoints()
    icon:SetTexture(spell.icon)
    icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
    b.icon = icon


    local hl = b:CreateTexture(nil, "HIGHLIGHT")
    hl:SetAllPoints()
    hl:SetColorTexture(1, 1, 1, 0.25)
    ns.UI.Border(b, 0.16, 0.55, 0.55, 1, 1, "OVERLAY")

    local cd = CreateFrame("Cooldown", nil, b, "CooldownFrameTemplate")
    cd:SetAllPoints()
    cd:SetHideCountdownNumbers(true)
    pcall(cd.SetReverse, cd, true)   -- lit part = time left, like a buff, not a cooldown
    b.cd = cd
    local tf = CreateFrame("Frame", nil, b)
    tf:SetAllPoints()
    tf:SetFrameLevel(cd:GetFrameLevel() + 3)
    b.time = tf:CreateFontString(nil, "OVERLAY", "NumberFontNormalLarge")
    b.time:SetPoint("CENTER", 0, 0)
    -- duration bar along the bottom edge: drains while the totem stands
    b.barBg = tf:CreateTexture(nil, "OVERLAY")
    b.barBg:SetPoint("BOTTOMLEFT", 1, 1)
    b.barBg:SetPoint("BOTTOMRIGHT", -1, 1)
    b.barBg:SetHeight(6)
    b.barBg:SetColorTexture(0, 0, 0, 0.8)
    b.bar = tf:CreateTexture(nil, "OVERLAY")
    b.bar:SetPoint("BOTTOMLEFT", 2, 2)
    b.bar:SetHeight(4)
    b.bar:SetWidth(1)
    b.barBg:Hide()
    b.bar:Hide()

    b.spellName = spell.name
    b.element = element
    b:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        local ok = pcall(GameTooltip.SetSpellByID, GameTooltip, spell.id)
        if not ok then GameTooltip:SetText(spell.name) end
        GameTooltip:AddLine(" ")
        GameTooltip:AddLine("Casts the highest rank you know.", 0.55, 1, 0.85)
        GameTooltip:Show()
    end)
    b:SetScript("OnLeave", function() GameTooltip:Hide() end)
    b:SetScript("PostClick", function(self)
        self.lastCast = GetTime()
        local name = self.spellName
        C_Timer.After(0.3, function() updateActive() snap("click+0.3s " .. tostring(name)) end)
        C_Timer.After(1.0, function() updateActive() snap("click+1.0s " .. tostring(name)) end)
    end)
    box.cache[spell.name] = b
    return b
end

local function collect()
    local rows = {}
    for _, el in ipairs(ELEMENTS) do
        rows[el] = {}
        for _, name in ipairs(TOTEMS[el]) do
            local s = lookup(name)
            if s then rows[el][#rows[el] + 1] = s end
        end
    end
    local extras = {}
    for _, name in ipairs(EXTRA) do
        local s = lookup(name)
        if s then extras[#extras + 1] = s end
    end
    for _, c in ipairs(db.custom) do
        local s = lookup(c.name)
        if s and c.kind ~= "imbue" then
            if rows[c.kind] then rows[c.kind][#rows[c.kind] + 1] = s else extras[#extras + 1] = s end
        end
    end
    return rows, extras
end

local function rebuild()
    if InCombatLockdown() then pendingRebuild = true return end
    pendingRebuild = false
    if not box then makeBox() end
    for _, b in ipairs(buttons) do b:Hide() b:ClearAllPoints() end
    wipe(buttons)

    local rows, extras = collect()
    local y = -(TITLE_H + PAD)
    local maxCols = 3
    local any = false
    for _, el in ipairs(ELEMENTS) do
        local list = rows[el]
        if #list > 0 then
            any = true
            for i, s in ipairs(list) do
                local b = makeButton(s, el)
                b:SetPoint("TOPLEFT", box, "TOPLEFT", PAD + 6 + (i - 1) * (BTN + GAP()), y)
                buttons[#buttons + 1] = b
                if i > maxCols then maxCols = i end
            end
            local tag = box:CreateTexture(nil, "ARTWORK")
            tag:SetColorTexture(COLORS[el][1], COLORS[el][2], COLORS[el][3], 1)
            tag:SetSize(3, BTN)
            tag:SetPoint("TOPLEFT", box, "TOPLEFT", PAD, y)
            box.tags = box.tags or {}
            box.tags[#box.tags + 1] = tag
            y = y - (BTN + GAP())
        end
    end
    if #extras > 0 then
        any = true
        for i, s in ipairs(extras) do
            local b = makeButton(s, "extra")
            b:SetPoint("TOPLEFT", box, "TOPLEFT", PAD + 6 + (i - 1) * (BTN + GAP()), y)
            buttons[#buttons + 1] = b
            if i > maxCols then maxCols = i end
        end
        y = y - (BTN + GAP())
    end
    if not any then
        say("no totem spells found in your spellbook. Use /rst dump, or /rst add <spell name> <earth|fire|water|air>.")
    end
    box:SetSize(PAD * 2 + 6 + maxCols * (BTN + GAP()) - GAP(), -y + PAD - GAP())
    box:SetShown(db.shown and any)
end

-- Hide stale element tags when rebuilding.
local oldRebuild = rebuild
rebuild = function()
    if box and box.tags then
        for _, t in ipairs(box.tags) do t:Hide() end
        wipe(box.tags)
    end
    oldRebuild()
end

local function formatLeft(left)
    if left >= 60 then return string.format("%dm", math.ceil(left / 60)) end
    return string.format("%d", math.ceil(left))
end

function updateNumbers()
    local now = GetTime()
    for _, b in ipairs(buttons) do
        local text = ""
        local frac, r, g, bl
        if b.endTime then
            local left = b.endTime - now
            if left > 0 then
                if left <= 5 then r, g, bl = 1, 0.3, 0.3
                elseif left <= 15 then r, g, bl = 1, 0.82, 0.1
                else r, g, bl = 0.30, 0.90, 0.80 end
                if db.showNumbers then
                    text = formatLeft(left)
                    b.time:SetTextColor(r == 0.30 and 1 or r, r == 0.30 and 1 or g, r == 0.30 and 1 or bl)
                end
                if b.totalDur and b.totalDur > 0 then frac = math.min(1, left / b.totalDur) end
            else
                b.endTime = nil
                b.isActive = false
            end
        end
        if b.isActive and not b.endTime then
            r, g, bl = 0.45, 0.60, 0.65   -- active, duration not known yet
            frac = 1
        end
        b.time:SetText(text)
        if db.showBar and frac then
            local w = math.max(1, (BTN - 4) * frac)
            b.bar:SetWidth(w)
            b.bar:SetColorTexture(r, g, bl, 1)
            b.barBg:Show()
            b.bar:Show()
        else
            b.barBg:Hide()
            b.bar:Hide()
        end
    end
end

local function isSecret(x) return issecretvalue and issecretvalue(x) end

-- Totem timers.
-- Out of combat the game tells us everything (name, start, duration). In combat it hides ALL of it
-- ("secret values"), even whether a totem exists. So the addon tracks totems itself:
--   * when you cast a totem spell (the name is readable), it starts a timer from the known duration,
--   * when the game does give readable data, it takes over and also LEARNS the duration for next time,
--   * a totem update long after the cast, with hidden data, means the totem ended or was killed.
local SLOT_ELEMENT = { [1] = "fire", [2] = "earth", [3] = "water", [4] = "air" }
local DEFAULT_DUR = { ["Searing Totem"] = 30, ["Earthbind Totem"] = 45, ["Tremor Totem"] = 300 }
local active = {}   -- element -> { btn =, castAt =, endTime =, total = }

local function buttonByName(name)
    for _, b in ipairs(buttons) do
        if b.spellName == name then return b end
    end
    for _, b in ipairs(buttons) do
        if name:find(b.spellName, 1, true) then return b end
    end
    return nil
end

local function knownDuration(name)
    return (db.durations and db.durations[name]) or DEFAULT_DUR[name]
end

local function learnDuration(name, dur)
    if dur and dur > 0 then
        db.durations = db.durations or {}
        db.durations[name] = dur
    end
end

-- Reads one totem slot. Returns nil while the game hides the values.
local function readSlot(slot)
    if not GetTotemInfo then return nil end
    local ok, have, name, start, dur = pcall(GetTotemInfo, slot)
    if not ok or isSecret(have) or isSecret(name) or isSecret(start) or isSecret(dur) then return nil end
    if type(name) ~= "string" then name = "" end
    return { name = name, start = tonumber(start) or 0, dur = tonumber(dur) or 0 }
end

local function applyActive()
    local now = GetTime()
    for el, a in pairs(active) do
        if a.endTime and now > a.endTime + 0.5 then active[el] = nil end
    end
    for _, b in ipairs(buttons) do
        local a = active[b.element]
        if a and a.btn == b then
            b.isActive = true
            b.endTime = a.endTime
            b.totalDur = a.total
            if db.showTimer and a.endTime and a.total then
                pcall(b.cd.SetCooldown, b.cd, a.endTime - a.total, a.total)
                pcall(b.cd.SetDrawSwipe, b.cd, true)
                pcall(b.cd.SetHideCountdownNumbers, b.cd, true)
            else
                b.cd:Clear()
            end
        else
            b.isActive = false
            b.endTime = nil
            b.totalDur = nil
            b.cd:Clear()
        end
    end
end

function updateActive()
    if not box then return end
    local now = GetTime()
    for slot = 1, 4 do
        local el = SLOT_ELEMENT[slot]
        local info = readSlot(slot)
        if info then
            local a = active[el]
            if info.name ~= "" and info.start > 0 then
                local b = buttonByName(info.name)
                if b then
                    learnDuration(b.spellName, info.dur)
                    active[el] = {
                        btn = b, castAt = info.start,
                        endTime = (info.dur > 0) and (info.start + info.dur) or nil,
                        total = (info.dur > 0) and info.dur or nil,
                    }
                end
            elseif not (a and now - a.castAt < 1.2) then
                active[el] = nil   -- readable and empty: no totem (ignoring the moment right after a cast)
            end
        end
    end
    applyActive()
end

-- Called when the player has just cast a totem spell.
local function onTotemCast(name)
    local b = buttonByName(name)
    if not b or not TOTEM_SLOT[b.element] then return end
    local dur = knownDuration(b.spellName)
    local now = GetTime()
    active[b.element] = { btn = b, castAt = now, endTime = dur and (now + dur) or nil, total = dur }
    applyActive()
    C_Timer.After(0.4, updateActive)   -- sync with the real data when it is readable (also learns the duration)
end

-- Called when the game reports a change in a totem slot.
local function onTotemSlotUpdate(slot)
    local el = SLOT_ELEMENT[slot]
    local a = el and active[el]
    if a and not readSlot(slot) and GetTime() - a.castAt > 1.5 then
        active[el] = nil   -- hidden data and no recent cast: the totem ended or was killed
    end
    updateActive()
end

-- Debug recorder: writes what the game returns for the four totem slots into the saved variables
-- (db.debugLog), so the real behaviour can be inspected after /reload or logout.
snap = function(tag)
    if not db then return end
    db.debugLog = db.debugLog or {}
    local parts = { string.format("%.1f", GetTime()), tostring(tag) }
    for slot = 1, 4 do
        local res = { pcall(GetTotemInfo, slot) }
        local f = {}
        for i = 2, 8 do
            local v = res[i]
            if isSecret(v) then f[#f + 1] = "<secret " .. type(v) .. ">" else f[#f + 1] = tostring(v) end
        end
        parts[#parts + 1] = "s" .. slot .. "=" .. table.concat(f, "/")
    end
    local log = db.debugLog
    log[#log + 1] = table.concat(parts, " | ")
    while #log > 80 do table.remove(log, 1) end
end

---------------------------------------------------------------------------
-- Weapon imbue alert
---------------------------------------------------------------------------
local alert
local imbueSpell    -- the spell the alert button casts

local function pickImbue()
    if db.defaultImbue and db.defaultImbue ~= "auto" then
        local s = lookup(db.defaultImbue)
        if s then return s end
    end
    for _, name in ipairs(IMBUES) do
        local s = lookup(name)
        if s then return s end
    end
    for _, c in ipairs(db.custom) do
        if c.kind == "imbue" then
            local s = lookup(c.name)
            if s then return s end
        end
    end
    return nil
end

local function makeAlert()
    alert = CreateFrame("Button", "RobauShamanToolkitAlert", UIParent, "SecureActionButtonTemplate")
    alert:SetSize(260, 56)
    alert:SetFrameStrata("HIGH")
    alert:SetClampedToScreen(true)
    alert:SetMovable(true)
    alert:SetPoint(db.alertPoint, UIParent, db.alertPoint, db.alertX, db.alertY)
    alert:RegisterForClicks("AnyUp", "AnyDown")
    alert:RegisterForDrag("LeftButton")
    alert:SetAttribute("type", "spell")

    local bg = alert:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    bg:SetColorTexture(0.17, 0.04, 0.05, 0.95)
    ns.UI.Border(alert, 0.85, 0.25, 0.25, 1, 1, "BORDER")

    local icon = alert:CreateTexture(nil, "ARTWORK")
    icon:SetSize(44, 44)
    icon:SetPoint("LEFT", 6, 0)
    icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
    alert.icon = icon

    local text = alert:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    text:SetPoint("LEFT", icon, "RIGHT", 8, 6)
    text:SetText("NO WEAPON IMBUE!")
    text:SetTextColor(1, 0.2, 0.2)

    local sub = alert:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    sub:SetPoint("TOPLEFT", text, "BOTTOMLEFT", 0, -2)
    alert.sub = sub

    local ag = alert:CreateAnimationGroup()
    ag:SetLooping("BOUNCE")
    local a = ag:CreateAnimation("Alpha")
    a:SetFromAlpha(1)
    a:SetToAlpha(0.25)
    a:SetDuration(0.6)
    alert.pulse = ag

    alert:SetScript("OnDragStart", function(self)
        if not db.locked and not InCombatLockdown() then self:StartMoving() end
    end)
    alert:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        local point, _, _, x, y = self:GetPoint()
        db.alertPoint, db.alertX, db.alertY = point, x, y
    end)
    alert:Hide()
end

local function needsImbue()
    if not GetWeaponEnchantInfo then return false end
    local ok, hasMain, _, _, _, hasOff = pcall(GetWeaponEnchantInfo)
    if not ok then return false end
    if issecretvalue and (issecretvalue(hasMain) or issecretvalue(hasOff)) then return false end
    local mainWeapon = GetInventoryItemID("player", 16)
    if not mainWeapon then return false end
    -- a fishing pole in hand (weapon class 2, subclass 20): no imbue needed, no alert
    if C_Item and C_Item.GetItemInfoInstant then
        local okI, _, _, _, _, _, classID, subClassID = pcall(C_Item.GetItemInfoInstant, mainWeapon)
        if okI and classID == 2 and subClassID == 20 then return false end
    end
    if hasMain then
        if not db.alertOffhand then return false end
        local off = GetInventoryItemID("player", 17)
        local offIsWeapon = off and C_Item and C_Item.GetItemInfoInstant and select(6, C_Item.GetItemInfoInstant(off)) == 2
        if offIsWeapon and not hasOff then return true end
        return false
    end
    -- nothing on main hand: only "none at all" if the off hand has none as well
    if hasOff then return false end
    return true
end

local pendingAlert = false
local function updateAlert()
    if not db.alertEnabled then
        if alert then alert:Hide() end
        return
    end
    if not alert then makeAlert() end
    local show = needsImbue() and not UnitIsDeadOrGhost("player") and not IsMounted()
    local spell = pickImbue()
    if show and spell then
        if not InCombatLockdown() then
            alert:SetAttribute("spell", spell.name)
            pendingAlert = false
        end
        alert.icon:SetTexture(spell.icon)
        alert.sub:SetText("Click to cast " .. spell.name)
    elseif show then
        alert.icon:SetTexture(nil)
        alert.sub:SetText("")
    end
    if show then
        if not alert:IsShown() and not InCombatLockdown() then alert:Show() end
        if not alert.pulse:IsPlaying() then alert.pulse:Play() end
    else
        alert.pulse:Stop()
        if alert:IsShown() and not InCombatLockdown() then alert:Hide() end
    end
end

---------------------------------------------------------------------------
-- Boot and events
---------------------------------------------------------------------------
local ev = CreateFrame("Frame")
ev:RegisterEvent("ADDON_LOADED")
ev:SetScript("OnEvent", function(self, event, arg1, arg2, arg3)
    if event == "ADDON_LOADED" then
        if arg1 ~= ADDON then return end
        RobauShamanToolkitDB = RobauShamanToolkitDB or {}
        db = RobauShamanToolkitDB
        copyDefaults(defaults, db)
        if not db.timerStyleV2 then
            -- the old clock sweep looked like a cooldown; the duration bar replaces it
            db.showTimer = false
            db.timerStyleV2 = true
        end
        self:UnregisterEvent("ADDON_LOADED")
        local _, class = UnitClass("player")
        if class ~= "SHAMAN" then return end
        self:RegisterEvent("PLAYER_ENTERING_WORLD")
        self:RegisterEvent("SPELLS_CHANGED")
        self:RegisterEvent("PLAYER_TOTEM_UPDATE")
        self:RegisterUnitEvent("UNIT_SPELLCAST_SUCCEEDED", "player")
        self:RegisterEvent("PLAYER_REGEN_ENABLED")
        self:RegisterEvent("UNIT_INVENTORY_CHANGED")
        self:RegisterEvent("PLAYER_EQUIPMENT_CHANGED")
        self:RegisterEvent("PLAYER_DEAD")
        self:RegisterEvent("PLAYER_ALIVE")
        self:RegisterEvent("PLAYER_UNGHOST")
        C_Timer.NewTicker(1, function() updateAlert() end)
    elseif event == "PLAYER_ENTERING_WORLD" or event == "SPELLS_CHANGED" then
        rebuild()
        updateActive()
        updateAlert()
    elseif event == "PLAYER_REGEN_ENABLED" then
        if pendingRebuild then rebuild() end
        updateAlert()
    elseif event == "PLAYER_TOTEM_UPDATE" then
        onTotemSlotUpdate(arg1)
        snap("PLAYER_TOTEM_UPDATE slot=" .. tostring(arg1))
    elseif event == "UNIT_SPELLCAST_SUCCEEDED" then
        local name
        if C_Spell and C_Spell.GetSpellInfo and arg3 and not isSecret(arg3) then
            local ok, info = pcall(C_Spell.GetSpellInfo, arg3)
            if ok and type(info) == "table" then name = info.name end
        end
        if name and name:find("Totem") then
            onTotemCast(name)
            snap("cast " .. name)
        end
    else
        updateAlert()
    end
end)

---------------------------------------------------------------------------
-- Slash commands
---------------------------------------------------------------------------
SLASH_ROBAUSHAMAN1 = "/rst"
SlashCmdList.ROBAUSHAMAN = function(input)
    if not db then return end
    local cmd, rest = (input or ""):match("^(%S*)%s*(.-)$")
    cmd = cmd:lower()
    if cmd == "lock" then
        db.locked = true say("locked")
    elseif cmd == "unlock" then
        db.locked = false say("unlocked: drag the blue title bar (and the red alert) to move them")
    elseif cmd == "show" or cmd == "hide" or cmd == "toggle" then
        if cmd == "toggle" then db.shown = not db.shown else db.shown = (cmd == "show") end
        if box then box:SetShown(db.shown and #buttons > 0) end
    elseif cmd == "scale" then
        local n = tonumber(rest)
        if n and n >= 0.5 and n <= 2.5 then
            db.scale = n
            if box then box:SetScale(n) end
        else
            say("usage: /rst scale 0.5 - 2.5")
        end
    elseif cmd == "alert" then
        db.alertEnabled = not db.alertEnabled
        say("imbue alert " .. (db.alertEnabled and "on" or "off"))
        updateAlert()
    elseif cmd == "offhand" then
        db.alertOffhand = not db.alertOffhand
        say("also warn about a missing off hand imbue: " .. tostring(db.alertOffhand))
    elseif cmd == "reset" then
        db.point, db.x, db.y = defaults.point, defaults.x, defaults.y
        db.alertPoint, db.alertX, db.alertY = defaults.alertPoint, defaults.alertX, defaults.alertY
        if box then box:ClearAllPoints() box:SetPoint(db.point, UIParent, db.point, db.x, db.y) end
        if alert then alert:ClearAllPoints() alert:SetPoint(db.alertPoint, UIParent, db.alertPoint, db.alertX, db.alertY) end
        say("positions reset")
    elseif cmd == "add" then
        local name, kind = rest:match("^(.-)%s+(%a+)$")
        kind = kind and kind:lower()
        if name and name ~= "" and (kind == "imbue" or TOTEMS[kind]) then
            db.custom[#db.custom + 1] = { name = name, kind = kind }
            say("added " .. name .. " (" .. kind .. ")")
            rebuild()
        else
            say("usage: /rst add <spell name> <earth|fire|water|air|imbue>")
        end
    elseif cmd == "totems" then
        local function d(x)
            if isSecret(x) then return "<secret " .. type(x) .. ">" end
            return tostring(x)
        end
        for slot = 1, 4 do
            local ok, have, name, start, dur = pcall(GetTotemInfo, slot)
            say("slot " .. slot .. ": ok=" .. tostring(ok) .. " have=" .. d(have) .. " name=" .. d(name)
                .. " start=" .. d(start) .. " dur=" .. d(dur))
        end
    elseif cmd == "dump" then
        for _, el in ipairs(ELEMENTS) do
            local found = {}
            for _, n in ipairs(TOTEMS[el]) do if lookup(n) then found[#found + 1] = n end end
            say(el .. ": " .. (#found > 0 and table.concat(found, ", ") or "none known"))
        end
        local imb = {}
        for _, n in ipairs(IMBUES) do if lookup(n) then imb[#imb + 1] = n end end
        say("imbues: " .. (#imb > 0 and table.concat(imb, ", ") or "none known"))
    else
        say("/rst lock | unlock | show | hide | toggle | scale <n> | alert | offhand | reset | add <spell> <element> | dump")
    end
end

---------------------------------------------------------------------------
-- Settings panel (Robau Mod Suite window)
---------------------------------------------------------------------------
local UI, Hub = ns.UI, ns.Hub

local function knownImbues()
    local list = { "auto" }
    for _, n in ipairs(IMBUES) do if lookup(n) then list[#list + 1] = n end end
    for _, c in ipairs(db.custom) do
        if c.kind == "imbue" and lookup(c.name) then list[#list + 1] = c.name end
    end
    return list
end

Hub.Register("shaman", "Shaman Toolkit", "Interface\\Icons\\Spell_Nature_StoneSkinTotem",
    "A draggable totem toolbox (click to drop a totem) and a pulsing alert when your weapon has no imbue.",
    function(p)
        local L, R = 12, 290
        UI.Header(p, "Totem toolbox", L, -66)
        UI.Check(p, "Show the toolbox", nil, L, -88,
            function() return db.shown end,
            function(v) db.shown = v if box then box:SetShown(v and #buttons > 0) end end)
        UI.Check(p, "Lock position", "Off: drag the blue title bar to move it.", L, -114,
            function() return db.locked end, function(v) db.locked = v end)
        UI.Check(p, "Show clock sweep on active totems", "Fills like a buff timer (the lit part is the time left). Off by default, the bar and number are clearer.", L, -140,
            function() return db.showTimer end,
            function(v) db.showTimer = v updateActive() end)
        UI.Check(p, "Show seconds left as a number", "A big number on the icon: seconds, or minutes for long totems.", L, -166,
            function() return db.showNumbers end,
            function(v) db.showNumbers = v updateNumbers() end)
        UI.Check(p, "Show a duration bar under active totems", "A thin bar along the bottom of the icon that shrinks while the totem stands.", L, -192,
            function() return db.showBar end,
            function(v) db.showBar = v updateNumbers() end)
        UI.Stepper(p, function(v) return string.format("Size: %.1f", v) end, L, -228,
            function() return db.scale end,
            function(v) db.scale = v if box then box:SetScale(v) end end, 0.5, 2.5, 0.1)
        UI.Stepper(p, function(v) return "Spacing: " .. v end, L, -260,
            function() return db.spacing end,
            function(v) db.spacing = v rebuild() end, 0, 24, 2)
        UI.Button(p, "Reset positions", 140, L, -302, function()
            db.point, db.x, db.y = defaults.point, defaults.x, defaults.y
            db.alertPoint, db.alertX, db.alertY = defaults.alertPoint, defaults.alertX, defaults.alertY
            if box then box:ClearAllPoints() box:SetPoint(db.point, UIParent, db.point, db.x, db.y) end
            if alert then alert:ClearAllPoints() alert:SetPoint(db.alertPoint, UIParent, db.alertPoint, db.alertX, db.alertY) end
        end)
        UI.Note(p, "Totems you do not know yet do not appear. Missing one? The spell may have another name on this client.", L, -336, 250)

        UI.Header(p, "Weapon imbue alert", R, -66)
        UI.Check(p, "Warn when my weapon has no imbue", nil, R, -88,
            function() return db.alertEnabled end,
            function(v) db.alertEnabled = v updateAlert() end)
        UI.Check(p, "Also warn about the off hand", "Only if you hold a weapon in the off hand.", R, -114,
            function() return db.alertOffhand end, function(v) db.alertOffhand = v end)
        UI.Header(p, "Imbue to cast when I click the alert:", R, -152)
        local cycle
        cycle = UI.Button(p, "Auto", 220, R, -176, function(self)
            local list = knownImbues()
            local idx = 1
            for i, n in ipairs(list) do if n == db.defaultImbue then idx = i end end
            idx = idx % #list + 1
            db.defaultImbue = list[idx]
            self:SetText(db.defaultImbue == "auto" and "Auto (best known)" or db.defaultImbue)
            updateAlert()
        end)
        p.widgets[#p.widgets + 1] = { refresh = function()
            cycle:SetText((db.defaultImbue or "auto") == "auto" and "Auto (best known)" or db.defaultImbue)
        end }
        UI.Note(p, "Click the button to cycle through the imbues you know. The alert is hidden while a fishing pole is equipped.", R, -208, 250)
    end,
    function() return db and (db.shown and "toolbox on" or "toolbox off") end)
