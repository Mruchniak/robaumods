local ADDON, ns = ...

-- LazyFisher: one key does everything.
--   not fishing   -> the key casts Fishing
--   line in water -> the same key becomes "Interact with target" and loots the bobber
-- A small toolbox has buttons to switch the mode on/off, apply a lure and hide itself.
-- Every action still needs YOUR key press or click (addons cannot do it for you).

local function say(msg) print("|cff33ddaaLazyFisher|r: " .. msg) end

local db
local defaults = {
    key = nil,            -- e.g. "F"
    on = false,
    autoLoot = true,
    loudSound = true,
    toolbox = true,       -- toolbox visible
    lure = "auto",        -- "auto" or an item name
    autoLure = false,     -- first key press applies a lure when none is active
    lureQuality = "best", -- "best" or "weakest" (used when lure is "auto")
    customLure = "",      -- typed item name, overrides the above
    stats = { casts = 0, catches = 0, lineTime = 0, items = {} },
    btnPoint = "CENTER", btnX = 0, btnY = -140,
    point = "CENTER", x = 0, y = -220,
    saved = {},           -- cvars to restore when switching off
}

-- Lures, best guess first. Only the ones you carry are used.
local LURES = { "Aquadynamic Fish Attractor", "Flesh Eating Worm", "Bright Baubles", "Nightcrawlers", "Shiny Bauble" }

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

local owner = CreateFrame("Frame")         -- owns the override bindings
local cast                                  -- secure button that casts Fishing
local toolbox                               -- toolbox frame
local fishingName = "Fishing"
local pendingBinding = false
local pendingLure = false
local lureLockUntil = 0
local lureMode = false   -- true: the cast key currently applies a lure instead of casting
local poleState = "ok"    -- "ok" | "equip" (pole in bags, not in hand) | "none" (no pole anywhere)
local poleInBags         -- { id =, name = } of a fishing pole found in the bags
local scanDirty = true

---------------------------------------------------------------------------
-- Game state helpers
---------------------------------------------------------------------------
local function isFishing()
    if not UnitChannelInfo then return false end
    local ok, name = pcall(UnitChannelInfo, "player")
    if not ok or not name then return false end
    if issecretvalue and issecretvalue(name) then return false end
    return name == fishingName
end

local function poleEquipped()
    local id = GetInventoryItemID("player", 16)
    if not id or not C_Item or not C_Item.GetItemInfoInstant then return false end
    local ok, _, _, _, _, _, classID, subClassID = pcall(C_Item.GetItemInfoInstant, id)
    return ok and classID == 2 and subClassID == 20
end

-- Returns active, secondsLeft for a lure/enchant on the main hand.
local function lureActive()
    if not GetWeaponEnchantInfo then return false, 0 end
    local ok, has, expiration = pcall(GetWeaponEnchantInfo)
    if not ok then return false, 0 end
    if issecretvalue and (issecretvalue(has) or issecretvalue(expiration)) then return false, 0 end
    if has then return true, (expiration or 0) / 1000 end
    return false, 0
end

local function scanPole()
    poleInBags = nil
    if not C_Container or not C_Container.GetContainerNumSlots or not C_Container.GetContainerItemInfo then return end
    for bag = 0, (NUM_BAG_SLOTS or 4) + 1 do
        local okN, n = pcall(C_Container.GetContainerNumSlots, bag)
        for slot = 1, (okN and n or 0) do
            local ok, info = pcall(C_Container.GetContainerItemInfo, bag, slot)
            if ok and type(info) == "table" and info.itemID and C_Item and C_Item.GetItemInfoInstant then
                local ok2, _, _, _, _, _, classID, subID = pcall(C_Item.GetItemInfoInstant, info.itemID)
                if ok2 and classID == 2 and subID == 20 then
                    local name = info.itemName
                    if not name and info.hyperlink then name = info.hyperlink:match("%[(.-)%]") end
                    if not name and C_Item.GetItemNameByID then
                        local okName, n2 = pcall(C_Item.GetItemNameByID, info.itemID)
                        if okName then name = n2 end
                    end
                    if name then
                        poleInBags = { id = info.itemID, name = name }
                        return
                    end
                end
            end
        end
    end
end

local function itemCount(name)
    if C_Item and C_Item.GetItemCount then
        local ok, n = pcall(C_Item.GetItemCount, name)
        if ok and n then return n end
    end
    if GetItemCount then
        local ok, n = pcall(GetItemCount, name)
        if ok and n then return n end
    end
    return 0
end

local function itemIcon(name)
    if C_Item and C_Item.GetItemInfoInstant then
        local ok, _, _, _, _, icon = pcall(C_Item.GetItemInfoInstant, name)
        if ok and icon then return icon end
    end
    return "Interface\\Icons\\INV_Misc_Note_01"
end

local function pickLure()
    local custom = (db.customLure or ""):gsub("^%s+", ""):gsub("%s+$", "")
    if custom ~= "" then return custom end
    if db.lure and db.lure ~= "auto" then return db.lure end
    -- LURES is ordered best first
    if db.lureQuality == "weakest" then
        for i = #LURES, 1, -1 do
            if itemCount(LURES[i]) > 0 then return LURES[i] end
        end
    else
        for _, name in ipairs(LURES) do
            if itemCount(name) > 0 then return name end
        end
    end
    return nil
end

---------------------------------------------------------------------------
-- Key bindings
---------------------------------------------------------------------------
local function setStatus(text, r, g, b)
    if not toolbox then return end
    toolbox.stext = { text, r or 1, g or 1, b or 1 }
    if not toolbox.channeling and toolbox.status then
        toolbox.status:SetText(text)
        toolbox.status:SetTextColor(r or 1, g or 1, b or 1)
    end
end

local fishBtn   -- fishing progress bar (secure, casts Fishing on click)

local function shortKey(k)
    k = k:gsub("SHIFT%-", "S-"):gsub("CTRL%-", "C-"):gsub("ALT%-", "A-")
    k = k:gsub("BUTTON", "M")
    k = k:gsub("SPACE", "Space")
    return k
end

local function refreshFishBtn()
    if fishBtn and fishBtn.setFishing then fishBtn.setFishing(isFishing()) end
end

local function refreshToolbox()
    refreshFishBtn()
    if not toolbox then return end
    toolbox.setPower(db.on)
    toolbox.keyText:SetText(db.key and shortKey(db.key) or "?")
    if not db.on then
        setStatus("Fishing mode off", 0.7, 0.7, 0.7)
    end
end

local function applyBinding()
    if not db or not db.on or not db.key or not cast then return end
    if InCombatLockdown() then pendingBinding = true return end
    pendingBinding = false
    ClearOverrideBindings(owner)
    if poleState == "none" then
        -- no fishing pole anywhere: give the key back to the game
        setStatus("No fishing pole: key released", 1, 0.35, 0.35)
        refreshFishBtn()
        return
    end
    if isFishing() then
        SetOverrideBinding(owner, true, db.key, "INTERACTTARGET")
        setStatus("Line in water: press " .. shortKey(db.key), 1, 0.85, 0.2)
    else
        SetOverrideBindingClick(owner, true, db.key, "LazyFisherCastButton")
        if poleState == "equip" then
            setStatus("Press " .. shortKey(db.key) .. ": equip fishing pole", 1, 0.7, 0.2)
        elseif lureMode then
            setStatus("Press " .. shortKey(db.key) .. ": apply lure", 1, 0.7, 0.2)
        else
            setStatus("Press " .. shortKey(db.key) .. " to cast", 0.3, 1, 0.7)
        end
    end
    refreshFishBtn()
end

---------------------------------------------------------------------------
-- CVars: auto loot, louder effects, soft-target interact (lets a key click the bobber)
---------------------------------------------------------------------------
local function setCVar(name, value)
    if not C_CVar or not C_CVar.GetCVar then return end
    local ok, current = pcall(C_CVar.GetCVar, name)
    if not ok or current == nil then return end
    if db.saved[name] == nil then db.saved[name] = current end
    pcall(C_CVar.SetCVar, name, value)
end

local function restoreCVars()
    for name, value in pairs(db.saved) do
        pcall(C_CVar.SetCVar, name, value)
    end
    wipe(db.saved)
end

local function switchOn()
    if not db.key then
        say("pick a key first (Robau Mod Suite - LazyFisher).")
        refreshToolbox()
        return false
    end
    db.on = true
    setCVar("softTargetInteract", "3")
    if db.autoLoot then setCVar("autoLootDefault", "1") end
    if db.loudSound then
        setCVar("Sound_MasterVolume", "1")
        setCVar("Sound_SFXVolume", "1")
        setCVar("Sound_MusicVolume", "0")
        setCVar("Sound_AmbienceVolume", "0.2")
    end
    refreshToolbox()
    applyBinding()
    return true
end

local function switchOff()
    db.on = false
    if not InCombatLockdown() then ClearOverrideBindings(owner) end
    restoreCVars()
    refreshToolbox()
end

local function toggleMode()
    if db.on then switchOff() else switchOn() end
end

---------------------------------------------------------------------------
-- Lure button: secure, enabled only when it is safe to apply a lure
---------------------------------------------------------------------------
-- Nicer bars: vertical gradient, a soft gloss on the top half and a bright edge ("spark").
local function paintGradient(tex, r, g, b)
    local lo = CreateColor(r * 0.50, g * 0.50, b * 0.50, 1)
    local hi = CreateColor(math.min(1, r * 1.15 + 0.10), math.min(1, g * 1.15 + 0.10), math.min(1, b * 1.15 + 0.10), 1)
    local ok = pcall(function()
        tex:SetColorTexture(1, 1, 1, 1)
        tex:SetGradient("VERTICAL", lo, hi)
    end)
    if not ok then tex:SetColorTexture(r, g, b, 1) end
end

local function makeFill(parent)
    local fx = {}
    local fill = parent:CreateTexture(nil, "ARTWORK")
    fill:SetPoint("TOPLEFT", 1, -1)
    fill:SetPoint("BOTTOMLEFT", 1, 1)
    fill:SetWidth(1)
    local gloss = parent:CreateTexture(nil, "OVERLAY")
    gloss:SetPoint("TOPLEFT", fill, "TOPLEFT")
    gloss:SetPoint("TOPRIGHT", fill, "TOPRIGHT")
    gloss:SetHeight(math.max(3, math.floor(((parent:GetHeight() or 14) - 2) / 2)))
    gloss:SetColorTexture(1, 1, 1, 0.16)
    local spark = parent:CreateTexture(nil, "OVERLAY")
    spark:SetPoint("TOPRIGHT", fill, "TOPRIGHT")
    spark:SetPoint("BOTTOMRIGHT", fill, "BOTTOMRIGHT")
    spark:SetWidth(2)
    spark:SetColorTexture(1, 1, 1, 0.7)
    function fx.paint(r, g, b) paintGradient(fill, r, g, b) end
    function fx.setWidth(w) fill:SetWidth(w) end
    function fx.show() fill:Show() gloss:Show() spark:Show() end
    function fx.hide() fill:Hide() gloss:Hide() spark:Hide() end
    fx.hide()
    return fx
end

local function darkBackground(tex)
    local ok = pcall(function()
        tex:SetColorTexture(1, 1, 1, 1)
        tex:SetGradient("VERTICAL", CreateColor(0.01, 0.03, 0.04, 1), CreateColor(0.05, 0.10, 0.12, 1))
    end)
    if not ok then tex:SetColorTexture(0.02, 0.05, 0.06, 1) end
end

local function updateWarning()
    if not toolbox or not toolbox.warn then return end
    local w = toolbox.warn
    if db.on and poleState ~= "ok" then
        local key = db.key and shortKey(db.key) or "your key"
        if poleState == "equip" then
            w.text:SetText("No fishing pole in your hand. Press " .. key .. " (or click the bar) to equip |cffffd100"
                .. (poleInBags and poleInBags.name or "a pole") .. "|r, or switch LazyFisher off.")
        else
            w.text:SetText("You have no fishing pole. Your key works normally again. Switch LazyFisher off, or get a pole.")
        end
        w:Show()
    else
        w:Hide()
    end
end

local lureMaxSeen = 0

-- Mode chip: which lure is selected and whether it is applied automatically.
local function refreshMode()
    if not toolbox or not toolbox.modeSel then return end
    local sel
    if (db.customLure or "") ~= "" then
        sel = "Custom"
    elseif (db.lure or "auto") == "auto" then
        sel = (db.lureQuality == "weakest") and "Auto: weak" or "Auto: strong"
    else
        sel = db.lure
    end
    toolbox.modeSel:SetText(sel)
    if db.autoLure then
        toolbox.modeAuto:SetText("AUTO-APPLY ON")
        toolbox.modeAuto:SetTextColor(0.35, 1, 0.65)
        toolbox.modeDot:SetColorTexture(0.35, 1, 0.65, 1)
    else
        toolbox.modeAuto:SetText("AUTO-APPLY OFF")
        toolbox.modeAuto:SetTextColor(0.6, 0.6, 0.6)
        toolbox.modeDot:SetColorTexture(0.5, 0.5, 0.5, 1)
    end
end
local function setLureBar(active, left)
    if not toolbox or not toolbox.bar then return end
    local bar = toolbox.bar
    local width = bar:GetWidth()
    if not width or width < 20 then width = 224 end
    if active then
        if left > lureMaxSeen then lureMaxSeen = left end
        local total = math.max(lureMaxSeen, 600)
        local frac = math.min(1, math.max(0, left / total))
        local r, g, b = 0.20, 0.78, 0.58
        if left < 30 then r, g, b = 0.85, 0.25, 0.25
        elseif left < 120 then r, g, b = 1, 0.82, 0.10 end
        bar.fx.paint(r, g, b)
        bar.fx.setWidth(math.max(1, (width - 2) * frac))
        bar.fx.show()
        bar.text:SetText(string.format("Lure  %d:%02d", math.floor(left / 60), math.floor(left % 60)))
        bar.text:SetTextColor(1, 1, 1)
    else
        lureMaxSeen = 0
        bar.fx.hide()
        bar.text:SetText("No lure active")
        bar.text:SetTextColor(0.55, 0.65, 0.65)
    end
end

local function updateLure()
    if not toolbox or not db then return end
    local b = toolbox.lure
    local name = pickLure()
    local active, left = lureActive()
    local pole = poleEquipped()
    setLureBar(active, left)
    refreshMode()

    local reason
    if InCombatLockdown() then
        pendingLure = true
        return
    end
    pendingLure = false

    local usable = false
    if active then
        reason = string.format("Lure active (%d min left)", math.ceil(left / 60))
    elseif not pole then
        reason = "Equip a fishing pole"
    elseif not name then
        reason = "No lure in your bags"
    elseif itemCount(name) < 1 then
        reason = "You have no " .. name
    elseif GetTime() < lureLockUntil then
        reason = "Applying..."
    else
        usable = true
        reason = "Click to apply " .. name
    end

    if name then b.icon:SetTexture(itemIcon(name)) else b.icon:SetTexture("Interface\\Icons\\INV_Misc_Note_01") end
    -- only grey the icon when there is nothing usable to apply (no pole, no lure in bags)
    b.icon:SetDesaturated(not usable and not active and (not pole or not name or itemCount(name) < 1))
    if active then b.icon:SetVertexColor(0.7, 1, 0.9) else b.icon:SetVertexColor(1, 1, 1) end
    b.count:SetText(name and itemCount(name) or "")
    b.reason = reason
    b.lureName = name
    b.timer:SetText("")

    if usable then
        b:SetAttribute("type", "macro")
        b:SetAttribute("macrotext", "/use " .. name .. "\n/use 16")
    else
        b:SetAttribute("type", nil)
        b:SetAttribute("macrotext", nil)
    end

    -- automatic lure: the cast key applies a lure first (still one key press per action)
    if scanDirty then
        scanPole()
        scanDirty = false
    end
    local newState = "ok"
    if db.on and not pole then newState = poleInBags and "equip" or "none" end
    local wantMacro = usable and db.autoLure and db.on and true or false
    for _, btn in ipairs({ cast, fishBtn }) do
        if btn then
            if newState == "equip" then
                btn:SetAttribute("type", "macro")
                btn:SetAttribute("macrotext", "/equip " .. poleInBags.name)
            elseif wantMacro then
                btn:SetAttribute("type", "macro")
                btn:SetAttribute("macrotext", "/use " .. name .. "\n/use 16")
            else
                btn:SetAttribute("type", "spell")
                btn:SetAttribute("macrotext", nil)
                btn:SetAttribute("spell", fishingName)
            end
        end
    end
    if wantMacro ~= lureMode then
        lureMode = wantMacro
        if db.on then applyBinding() end
    end
    if newState ~= poleState then
        poleState = newState
        if db.on then applyBinding() end
    end
    updateWarning()
end

---------------------------------------------------------------------------
-- Toolbox
---------------------------------------------------------------------------
---------------------------------------------------------------------------
-- Two pop-up lists:
--   arrow above the lure icon  -> only the lures you carry
--   the mode chip (right side)  -> auto options: apply on expiry, strong / weak
---------------------------------------------------------------------------
local function qualityLure(q)
    if q == "weakest" then
        for i = #LURES, 1, -1 do
            if itemCount(LURES[i]) > 0 then return LURES[i] end
        end
    else
        for _, name in ipairs(LURES) do
            if itemCount(name) > 0 then return name end
        end
    end
    return nil
end

local function lureChoices()
    local list = {}
    local seen = {}
    local function add(name)
        if name and name ~= "" and not seen[name] and itemCount(name) > 0 then
            seen[name] = true
            list[#list + 1] = { kind = "lure", name = name }
        end
    end
    for _, name in ipairs(LURES) do add(name) end
    add(db.customLure)
    if db.lure and db.lure ~= "auto" then add(db.lure) end
    if #list == 0 then list[1] = { kind = "none" } end
    return list
end

local function autoChoices()
    return {
        { kind = "toggle" },
        { kind = "auto", quality = "best", text = "Auto: strong lure" },
        { kind = "auto", quality = "weakest", text = "Auto: weak lure" },
    }
end

local function isChosen(item)
    local custom = (db.customLure or "") ~= ""
    if item.kind == "auto" then
        return not custom and db.lure == "auto" and (db.lureQuality or "best") == item.quality
    elseif item.kind == "lure" then
        return (custom and db.customLure == item.name) or (not custom and db.lure == item.name)
    end
    return false
end

local function createMenu(frameName, choicesFn)
    local menu = { rows = {} }
    local m = CreateFrame("Frame", frameName, UIParent)
    m:SetFrameStrata("FULLSCREEN_DIALOG")
    m:SetClampedToScreen(true)
    ns.UI.Panel(m)
    menu.frame = m
    m.rows = menu.rows
    local catcher = CreateFrame("Button", nil, UIParent)
    catcher:SetAllPoints(UIParent)
    catcher:SetFrameStrata("FULLSCREEN")
    catcher:Hide()
    catcher:SetScript("OnClick", function() m:Hide() end)
    m:SetScript("OnShow", function() catcher:Show() end)
    m:SetScript("OnHide", function() catcher:Hide() end)
    m:Hide()

    function menu.refresh()
        local PAL = ns.UI.PAL
        local list = choicesFn()
        for i, item in ipairs(list) do
            local r = menu.rows[i]
            if not r then
                r = CreateFrame("Button", nil, m)
                r:SetSize(214, 22)
                r.icon = r:CreateTexture(nil, "ARTWORK")
                r.icon:SetSize(18, 18)
                r.icon:SetPoint("LEFT", 8, 0)
                r.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
                r.text = r:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
                r.text:SetJustifyH("LEFT")
                r.count = r:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
                r.count:SetPoint("RIGHT", -8, 0)
                r.sel = r:CreateTexture(nil, "BACKGROUND")
                r.sel:SetAllPoints()
                r.sel:SetColorTexture(PAL.edge[1], PAL.edge[2], PAL.edge[3], 0.3)
                local hl = r:CreateTexture(nil, "HIGHLIGHT")
                hl:SetAllPoints()
                hl:SetColorTexture(1, 1, 1, 0.10)
                r:SetScript("OnClick", function(self)
                    local it = self.item
                    if it.kind == "toggle" then
                        db.autoLure = not db.autoLure
                        updateLure()
                        menu.refresh()
                        return
                    elseif it.kind == "auto" then
                        db.lure = "auto"
                        db.lureQuality = it.quality
                    elseif it.kind == "lure" then
                        db.lure = it.name
                    else
                        return
                    end
                    db.customLure = ""
                    m:Hide()
                    updateLure()
                end)
                menu.rows[i] = r
            end
            r.item = item
            r:ClearAllPoints()
            r:SetPoint("TOPLEFT", 4, -4 - (i - 1) * 22)
            r:Show()
            r.text:ClearAllPoints()
            if item.kind == "toggle" then
                r.icon:SetTexture(nil)
                r.text:SetPoint("LEFT", r, "LEFT", 8, 0)
                r.text:SetText("Apply when it expires: " .. (db.autoLure and "ON" or "OFF"))
                if db.autoLure then r.text:SetTextColor(PAL.aqua[1], PAL.aqua[2], PAL.aqua[3])
                else r.text:SetTextColor(0.7, 0.7, 0.7) end
                r.count:SetText("")
                r.sel:Hide()
            elseif item.kind == "auto" then
                local pick = qualityLure(item.quality)
                r.icon:SetTexture(pick and itemIcon(pick) or "Interface\\Icons\\INV_Misc_Note_01")
                r.text:SetPoint("LEFT", r.icon, "RIGHT", 6, 0)
                r.text:SetText(item.text)
                r.text:SetTextColor(1, 1, 1)
                r.count:SetText("")
                r.sel:SetShown(isChosen(item))
            elseif item.kind == "lure" then
                r.icon:SetTexture(itemIcon(item.name))
                r.text:SetPoint("LEFT", r.icon, "RIGHT", 6, 0)
                r.text:SetText(item.name)
                r.text:SetTextColor(1, 1, 1)
                r.count:SetText(itemCount(item.name))
                r.sel:SetShown(isChosen(item))
            else
                r.icon:SetTexture(nil)
                r.text:SetPoint("LEFT", r, "LEFT", 8, 0)
                r.text:SetText("No lures in your bags")
                r.text:SetTextColor(0.6, 0.6, 0.6)
                r.count:SetText("")
                r.sel:Hide()
            end
        end
        for i = #list + 1, #menu.rows do menu.rows[i]:Hide() end
        m:SetSize(222, 8 + #list * 22)
    end

    function menu.toggle(anchor)
        if m:IsShown() then
            m:Hide()
            return
        end
        m:ClearAllPoints()
        m:SetPoint("BOTTOMLEFT", anchor, "TOPLEFT", -4, 4)
        menu.refresh()
        m:Show()
    end
    return menu
end

local lureMenu, autoMenu
local function toggleLureMenu(anchor)
    lureMenu = lureMenu or createMenu("LazyFisherLureMenu", lureChoices)
    if autoMenu then autoMenu.frame:Hide() end
    lureMenu.toggle(anchor)
end
local function toggleAutoMenu(anchor)
    autoMenu = autoMenu or createMenu("LazyFisherAutoMenu", autoChoices)
    if lureMenu then lureMenu.frame:Hide() end
    autoMenu.toggle(anchor)
end

local function iconButton(parent, template, size)
    local b = CreateFrame("Button", nil, parent, template)
    b:SetSize(size, size)
    local icon = b:CreateTexture(nil, "ARTWORK")
    icon:SetAllPoints()
    icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
    b.icon = icon
    local hl = b:CreateTexture(nil, "HIGHLIGHT")
    hl:SetAllPoints()
    hl:SetColorTexture(1, 1, 1, 0.25)
    return b
end

local function showTip(self, title, body)
    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
    GameTooltip:AddLine(title)
    if body then GameTooltip:AddLine(body, 0.8, 0.8, 0.8, true) end
    GameTooltip:Show()
end

local function applyToolboxVisibility()
    if not toolbox or InCombatLockdown() then return end
    toolbox:SetShown(db.toolbox and true or false)
end

local function build()
    local spellName
    if C_Spell and C_Spell.GetSpellInfo then
        local ok, info = pcall(C_Spell.GetSpellInfo, "Fishing")
        if ok and type(info) == "table" and info.name then spellName = info.name end
    end
    fishingName = spellName or "Fishing"

    cast = CreateFrame("Button", "LazyFisherCastButton", UIParent, "SecureActionButtonTemplate")
    cast:SetSize(1, 1)
    cast:SetPoint("CENTER")
    cast:RegisterForClicks("AnyUp", "AnyDown")
    cast:SetAttribute("type", "spell")
    cast:SetAttribute("spell", fishingName)
    cast:SetScript("PostClick", function()
        if lureMode then
            lureLockUntil = GetTime() + 8
            if not InCombatLockdown() then updateLure() end
        end
    end)

    -- Palette: deep teal panel, aqua accent, gold for the fishing glow.
    local PANEL = { 0.04, 0.09, 0.11, 0.94 }
    local EDGE = { 0.16, 0.55, 0.55, 1 }
    local AQUA = { 0.30, 0.90, 0.80 }

    local function border(frame, r, g, bl, a)
        local t = {}
        for i, pts in ipairs({
            { "TOPLEFT", "TOPRIGHT", nil, 1 }, { "BOTTOMLEFT", "BOTTOMRIGHT", nil, 1 },
            { "TOPLEFT", "BOTTOMLEFT", 1, nil }, { "TOPRIGHT", "BOTTOMRIGHT", 1, nil } }) do
            local tex = frame:CreateTexture(nil, "BORDER")
            tex:SetColorTexture(r, g, bl, a)
            tex:SetPoint(pts[1])
            tex:SetPoint(pts[2])
            if pts[3] then tex:SetWidth(pts[3]) end
            if pts[4] then tex:SetHeight(pts[4]) end
            t[i] = tex
        end
        return t
    end

    toolbox = CreateFrame("Frame", "LazyFisherToolbox", UIParent)
    toolbox:SetSize(270, 138)
    toolbox:SetPoint(db.point, UIParent, db.point, db.x, db.y)
    toolbox:SetMovable(true)
    toolbox:SetClampedToScreen(true)
    toolbox:EnableMouse(true)
    toolbox:RegisterForDrag("LeftButton")
    local bg = toolbox:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    bg:SetColorTexture(PANEL[1], PANEL[2], PANEL[3], PANEL[4])
    border(toolbox, EDGE[1], EDGE[2], EDGE[3], EDGE[4])
    toolbox:SetScript("OnDragStart", function(self)
        if not InCombatLockdown() then self:StartMoving() end
    end)
    toolbox:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        local point, _, _, x, y = self:GetPoint()
        db.point, db.x, db.y = point, x, y
    end)

    -- header strip
    local head = toolbox:CreateTexture(nil, "ARTWORK")
    head:SetPoint("TOPLEFT", 1, -1)
    head:SetPoint("TOPRIGHT", -1, -1)
    head:SetHeight(22)
    local okG = pcall(function()
        head:SetColorTexture(1, 1, 1, 1)
        head:SetGradient("HORIZONTAL", CreateColor(0.10, 0.38, 0.40, 1), CreateColor(0.05, 0.12, 0.15, 1))
    end)
    if not okG then head:SetColorTexture(0.10, 0.30, 0.32, 1) end
    local hicon = toolbox:CreateTexture(nil, "OVERLAY")
    hicon:SetSize(16, 16)
    hicon:SetPoint("LEFT", head, "LEFT", 6, 0)
    hicon:SetTexture("Interface\\Icons\\Trade_Fishing")
    hicon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
    local htitle = toolbox:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    htitle:SetPoint("LEFT", hicon, "RIGHT", 6, 0)
    htitle:SetText("LazyFisher")
    htitle:SetTextColor(AQUA[1], AQUA[2], AQUA[3])

    -- hide (X)
    local hide = CreateFrame("Button", nil, toolbox)
    hide:SetSize(18, 18)
    hide:SetPoint("RIGHT", head, "RIGHT", -3, 0)
    local hx = hide:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    hx:SetPoint("CENTER", 0, 1)
    hx:SetText("x")
    hx:SetTextColor(0.8, 0.85, 0.85)
    local hhl = hide:CreateTexture(nil, "HIGHLIGHT")
    hhl:SetAllPoints()
    hhl:SetColorTexture(1, 1, 1, 0.15)
    hide:SetScript("OnClick", function()
        db.toolbox = false
        applyToolboxVisibility()
    end)
    hide:SetScript("OnEnter", function(self) showTip(self, "Hide toolbox", "Bring it back in Robau Mod Suite - LazyFisher.") end)
    hide:SetScript("OnLeave", function() GameTooltip:Hide() end)

    -- on / off switch (pill)
    local power = CreateFrame("Button", nil, toolbox)
    power:SetSize(64, 38)
    power:SetPoint("TOPLEFT", 8, -44)
    local pbg = power:CreateTexture(nil, "BACKGROUND")
    pbg:SetAllPoints()
    border(power, 0.35, 0.40, 0.40, 1)
    local pdot = power:CreateTexture(nil, "ARTWORK")
    pdot:SetSize(8, 8)
    pdot:SetPoint("LEFT", 8, 0)
    local ptext = power:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    ptext:SetPoint("LEFT", pdot, "RIGHT", 6, 0)
    local phl = power:CreateTexture(nil, "HIGHLIGHT")
    phl:SetAllPoints()
    phl:SetColorTexture(1, 1, 1, 0.12)
    toolbox.setPower = function(on)
        if on then
            pbg:SetColorTexture(0.08, 0.32, 0.26, 1)
            pdot:SetColorTexture(0.35, 1, 0.65, 1)
            ptext:SetText("ON")
            ptext:SetTextColor(0.55, 1, 0.8)
        else
            pbg:SetColorTexture(0.12, 0.14, 0.15, 1)
            pdot:SetColorTexture(0.5, 0.5, 0.5, 1)
            ptext:SetText("OFF")
            ptext:SetTextColor(0.65, 0.65, 0.65)
        end
    end
    power:SetScript("OnClick", toggleMode)
    power:SetScript("OnEnter", function(self)
        showTip(self, db.on and "Fishing mode: ON" or "Fishing mode: OFF", "Click to switch " .. (db.on and "off" or "on") .. ".")
    end)
    power:SetScript("OnLeave", function() GameTooltip:Hide() end)
    toolbox.power = power

    -- lure button (secure)
    local lure = CreateFrame("Button", nil, toolbox, "SecureActionButtonTemplate")
    lure:SetSize(38, 38)
    lure:SetPoint("LEFT", power, "RIGHT", 8, 0)
    lure:RegisterForClicks("AnyUp", "AnyDown")
    local licon = lure:CreateTexture(nil, "ARTWORK")
    licon:SetPoint("TOPLEFT", 1, -1)
    licon:SetPoint("BOTTOMRIGHT", -1, 1)
    licon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
    lure.icon = licon
    border(lure, 0.35, 0.40, 0.40, 1)
    local lhl = lure:CreateTexture(nil, "HIGHLIGHT")
    lhl:SetAllPoints()
    lhl:SetColorTexture(1, 1, 1, 0.2)
    lure.count = lure:CreateFontString(nil, "OVERLAY", "NumberFontNormalSmall")
    lure.count:SetPoint("BOTTOMRIGHT", -1, 1)
    lure.timer = lure:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    lure.timer:SetPoint("TOP", 0, -2)
    lure.timer:SetTextColor(AQUA[1], AQUA[2], AQUA[3])
    lure:SetScript("PostClick", function()
        -- block a second use right away; the real state is re-read after a few seconds
        lureLockUntil = GetTime() + 8
        if not InCombatLockdown() then updateLure() end
    end)
    lure:SetScript("OnEnter", function(self) showTip(self, "Fishing lure", self.reason or "") end)
    lure:SetScript("OnLeave", function() GameTooltip:Hide() end)
    toolbox.lure = lure

    -- arrow above the lure icon: opens the lure list
    local arrow = CreateFrame("Button", nil, toolbox)
    arrow:SetSize(38, 12)
    arrow:SetPoint("BOTTOM", lure, "TOP", 0, 1)
    local abg = arrow:CreateTexture(nil, "BACKGROUND")
    abg:SetAllPoints()
    abg:SetColorTexture(0.10, 0.22, 0.24, 1)
    local ahl = arrow:CreateTexture(nil, "HIGHLIGHT")
    ahl:SetAllPoints()
    ahl:SetColorTexture(1, 1, 1, 0.15)
    local atext = arrow:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    atext:SetPoint("CENTER", 0, -2)
    atext:SetText("^")
    atext:SetTextColor(AQUA[1], AQUA[2], AQUA[3])
    arrow:SetScript("OnClick", function(self) toggleLureMenu(self) end)
    arrow:SetScript("OnEnter", function(self) showTip(self, "Choose lure", "Pick which lure to use, or switch auto-apply.") end)
    arrow:SetScript("OnLeave", function() GameTooltip:Hide() end)
    toolbox.arrow = arrow

    -- key chip: shows the bound key, click to open the settings
    local chip = CreateFrame("Button", nil, toolbox)
    chip:SetSize(44, 38)
    chip:SetPoint("LEFT", lure, "RIGHT", 6, 0)
    local cbg = chip:CreateTexture(nil, "BACKGROUND")
    cbg:SetAllPoints()
    cbg:SetColorTexture(0.10, 0.13, 0.15, 1)
    border(chip, 0.35, 0.40, 0.40, 1)
    local clabel = chip:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    clabel:SetPoint("TOP", 0, -3)
    clabel:SetText("KEY")
    clabel:SetTextColor(0.55, 0.65, 0.65)
    toolbox.keyText = chip:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    toolbox.keyText:SetPoint("BOTTOM", 0, 4)
    local chl = chip:CreateTexture(nil, "HIGHLIGHT")
    chl:SetAllPoints()
    chl:SetColorTexture(1, 1, 1, 0.12)
    chip:SetScript("OnClick", function() ns.Hub.Open("lazyfish") end)
    chip:SetScript("OnEnter", function(self) showTip(self, "Fishing key", "Click to change it in the settings.") end)
    chip:SetScript("OnLeave", function() GameTooltip:Hide() end)

    -- mode chip: selected lure + auto-apply state, click toggles auto-apply
    local mode = CreateFrame("Button", nil, toolbox)
    mode:SetSize(88, 38)
    mode:SetPoint("LEFT", chip, "RIGHT", 6, 0)
    local mbg = mode:CreateTexture(nil, "BACKGROUND")
    mbg:SetAllPoints()
    mbg:SetColorTexture(0.10, 0.13, 0.15, 1)
    border(mode, 0.35, 0.40, 0.40, 1)
    toolbox.modeSel = mode:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    toolbox.modeSel:SetPoint("TOPLEFT", 6, -7)
    toolbox.modeSel:SetPoint("TOPRIGHT", -6, -7)
    toolbox.modeSel:SetJustifyH("LEFT")
    toolbox.modeSel:SetWordWrap(false)
    toolbox.modeDot = mode:CreateTexture(nil, "OVERLAY")
    toolbox.modeDot:SetSize(5, 5)
    toolbox.modeDot:SetPoint("BOTTOMLEFT", 6, 8)
    toolbox.modeAuto = mode:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    toolbox.modeAuto:SetPoint("LEFT", toolbox.modeDot, "RIGHT", 3, 0)
    toolbox.modeAuto:SetFont(toolbox.modeAuto:GetFont(), 8)
    toolbox.modeAuto:SetWordWrap(false)
    local mhl = mode:CreateTexture(nil, "HIGHLIGHT")
    mhl:SetAllPoints()
    mhl:SetColorTexture(1, 1, 1, 0.12)
    mode:SetScript("OnClick", function(self) toggleAutoMenu(self) end)
    mode:SetScript("OnEnter", function(self)
        showTip(self, "Lure mode", "Top: which lure is chosen (change it with the arrow). Bottom: whether your key applies a new lure when the old one expires. Click for the auto options: apply on expiry, strong or weak lure.")
    end)
    mode:SetScript("OnLeave", function() GameTooltip:Hide() end)
    toolbox.mode = mode

    -- lure time bar
    local bar = CreateFrame("Frame", nil, toolbox)
    bar:SetPoint("TOPLEFT", 8, -92)
    bar:SetPoint("TOPRIGHT", -8, -92)
    bar:SetHeight(14)
    local barbg = bar:CreateTexture(nil, "BACKGROUND")
    barbg:SetAllPoints()
    darkBackground(barbg)
    border(bar, 0.35, 0.40, 0.40, 1)
    bar.fx = makeFill(bar)
    bar.text = bar:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    bar.text:SetPoint("CENTER", 0, 0)
    toolbox.bar = bar


    -- fishing progress bar, built into the toolbox. It is a secure button, so a click casts
    -- like the key does. It drains while the line is in the water and shows the status text otherwise.
    fishBtn = CreateFrame("Button", "LazyFisherButton", toolbox, "SecureActionButtonTemplate")
    fishBtn:SetPoint("BOTTOMLEFT", 8, 8)
    fishBtn:SetPoint("BOTTOMRIGHT", -8, 8)
    fishBtn:SetHeight(20)
    fishBtn:RegisterForClicks("AnyUp", "AnyDown")
    fishBtn:SetAttribute("type", "spell")
    fishBtn:SetAttribute("spell", fishingName)
    fishBtn:SetScript("PostClick", function()
        if lureMode then
            lureLockUntil = GetTime() + 8
            if not InCombatLockdown() then updateLure() end
        end
    end)
    local fbg = fishBtn:CreateTexture(nil, "BACKGROUND")
    fbg:SetAllPoints()
    darkBackground(fbg)
    local frameTex = border(fishBtn, 0.35, 0.40, 0.40, 1)
    local fx = makeFill(fishBtn)
    local label = fishBtn:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    label:SetPoint("CENTER", 0, 0)
    toolbox.status = label
    local fhl = fishBtn:CreateTexture(nil, "HIGHLIGHT")
    fhl:SetAllPoints()
    fhl:SetColorTexture(1, 1, 1, 0.08)

    fishBtn.setFishing = function(fishing)
        local r, g, b = 0.35, 0.40, 0.40
        if fishing then r, g, b = 0.35, 0.80, 1 end
        for _, t in ipairs(frameTex) do t:SetColorTexture(r, g, b, 1) end
        fx.paint(0.14, 0.52, 0.95)
    end
    fishBtn.setFishing(false)

    local acc = 0
    fishBtn:SetScript("OnUpdate", function(_, dt)
        acc = acc + dt
        if acc < 0.05 then return end
        acc = 0
        local frac, left
        if UnitChannelInfo then
            local ok, name, _, _, startMS, endMS = pcall(UnitChannelInfo, "player")
            if ok and name and name == fishingName and startMS and endMS
                and not (issecretvalue and (issecretvalue(startMS) or issecretvalue(endMS))) then
                local total = endMS - startMS
                left = endMS - GetTime() * 1000
                if total > 0 then frac = math.max(0, math.min(1, left / total)) end
            end
        end
        if frac then
            toolbox.channeling = true
            fx.setWidth(math.max(1, (fishBtn:GetWidth() - 2) * frac))
            fx.show()
            label:SetText(string.format("Line in water   %.1fs", math.max(0, left) / 1000))
            label:SetTextColor(1, 1, 1)
        elseif toolbox.channeling then
            toolbox.channeling = false
            fx.hide()
            local st = toolbox.stext
            if st then label:SetText(st[1]) label:SetTextColor(st[2], st[3], st[4]) end
        end
    end)
    fishBtn:SetScript("OnEnter", function(self)
        showTip(self, "Fishing line", db.key and ("Press " .. db.key .. " to cast, and again on the splash. You can also click here to cast.") or "Set a key in the settings.")
    end)
    fishBtn:SetScript("OnLeave", function() GameTooltip:Hide() end)

    -- warning shown while fishing mode is on but no pole is in hand
    local warn = CreateFrame("Frame", "LazyFisherWarning", UIParent)
    warn:SetSize(270, 66)
    warn:SetPoint("BOTTOM", toolbox, "TOP", 0, 6)
    warn:SetFrameStrata("HIGH")
    ns.UI.Panel(warn, { 0.17, 0.04, 0.05, 0.96 }, ns.UI.PAL.warn)
    warn.text = warn:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    warn.text:SetPoint("TOPLEFT", 8, -7)
    warn.text:SetWidth(254)
    warn.text:SetJustifyH("LEFT")
    local off = ns.UI.RawButton(warn, 150, 18, "Switch LazyFisher off")
    off:SetPoint("BOTTOMRIGHT", -8, 6)
    off:SetScript("OnClick", function() switchOff() end)
    warn:Hide()
    toolbox.warn = warn

    applyToolboxVisibility()
    refreshToolbox()
    updateLure()
end

---------------------------------------------------------------------------
-- Events
---------------------------------------------------------------------------
---------------------------------------------------------------------------
-- Fishing statistics
---------------------------------------------------------------------------
local session = { casts = 0, catches = 0, lineTime = 0, items = {}, first = nil, last = nil }
local channelStart
local lastLoot = 0

local function bumpItem(tbl, name, qty, quality, icon)
    local e = tbl[name]
    if not e then
        e = { count = 0 }
        tbl[name] = e
    end
    e.count = e.count + qty
    e.quality = quality or e.quality
    e.icon = icon or e.icon
end

local function recordCast()
    session.casts = session.casts + 1
    db.stats.casts = db.stats.casts + 1
    session.first = session.first or GetTime()
    session.last = GetTime()
    channelStart = GetTime()
end

local function recordLineEnd()
    if not channelStart then return end
    local dt = GetTime() - channelStart
    channelStart = nil
    if dt > 0 and dt < 60 then
        session.lineTime = session.lineTime + dt
        db.stats.lineTime = (db.stats.lineTime or 0) + dt
    end
end

local function recordLoot()
    if not IsFishingLoot or not IsFishingLoot() then return end
    if GetTime() - lastLoot < 0.5 then return end   -- LOOT_READY and LOOT_OPENED both fire
    lastLoot = GetTime()
    session.catches = session.catches + 1
    db.stats.catches = db.stats.catches + 1
    session.first = session.first or GetTime()
    session.last = GetTime()
    local n = GetNumLootItems and GetNumLootItems() or 0
    for i = 1, n do
        local ok, icon, name, qty, a, b = pcall(GetLootSlotInfo, i)
        if ok and name and not (issecretvalue and issecretvalue(name)) then
            qty = tonumber(qty) or 1
            local quality = b or a
            if type(quality) ~= "number" then quality = nil end
            bumpItem(session.items, name, qty, quality, icon)
            bumpItem(db.stats.items, name, qty, quality, icon)
        end
    end
end

local function onChannelChange()
    if isFishing() then
        if not channelStart then recordCast() end
    else
        recordLineEnd()
    end
    applyBinding()
end

local ev = CreateFrame("Frame")
ev:RegisterEvent("ADDON_LOADED")
ev:SetScript("OnEvent", function(self, event, arg1)
    if event == "ADDON_LOADED" then
        if arg1 ~= ADDON then return end
        LazyFisherDB = LazyFisherDB or {}
        db = LazyFisherDB
        copyDefaults(defaults, db)
        self:UnregisterEvent("ADDON_LOADED")
        self:RegisterEvent("PLAYER_LOGIN")
        self:RegisterEvent("UNIT_SPELLCAST_CHANNEL_START")
        self:RegisterEvent("UNIT_SPELLCAST_CHANNEL_STOP")
        self:RegisterEvent("PLAYER_REGEN_ENABLED")
        self:RegisterEvent("BAG_UPDATE_DELAYED")
        self:RegisterEvent("PLAYER_EQUIPMENT_CHANGED")
        self:RegisterEvent("LOOT_OPENED")
        self:RegisterEvent("LOOT_READY")
    elseif event == "PLAYER_LOGIN" then
        build()
        if db.on and db.key then
            db.on = false
            switchOn()
        else
            db.on = false
            refreshToolbox()
        end
        C_Timer.NewTicker(1, function() updateLure() end)
    elseif event == "UNIT_SPELLCAST_CHANNEL_START" or event == "UNIT_SPELLCAST_CHANNEL_STOP" then
        if arg1 == "player" then
            -- the channel state is updated just after the event, so check one frame later
            C_Timer.After(0.05, onChannelChange)
        end
    elseif event == "LOOT_OPENED" or event == "LOOT_READY" then
        pcall(recordLoot)
    elseif event == "PLAYER_REGEN_ENABLED" then
        if pendingBinding then applyBinding() end
        applyToolboxVisibility()
        refreshFishBtn()
        updateLure()
    else
        scanDirty = true
        updateLure()
    end
end)

---------------------------------------------------------------------------
-- Settings panel (Robau Mod Suite window) and optional slash command
---------------------------------------------------------------------------
local UI, Hub = ns.UI, ns.Hub

local MODIFIERS = { LSHIFT = 1, RSHIFT = 1, LCTRL = 1, RCTRL = 1, LALT = 1, RALT = 1, LMETA = 1, RMETA = 1 }

Hub.Register("lazyfish", "LazyFisher", "Interface\\Icons\\Trade_Fishing",
    "One key casts the line and pulls in the fish. A toolbox adds fishing mode on/off, a safe lure button and hide.",
    function(p)
        local L, R = 12, 290
        UI.Header(p, "Fishing mode", L, -66)
        UI.Check(p, "Fishing mode on", "Casts with your key, loots the bobber with the same key.", L, -88,
            function() return db.on end,
            function(v) if v then switchOn() else switchOff() end end)

        UI.Header(p, "Key", L, -128)
        local capturing = false
        local keyBtn
        keyBtn = UI.Button(p, "-", 150, L, -150, function(self)
            capturing = true
            self:SetText("Press a key... (Esc cancels)")
            self:EnableKeyboard(true)
            self:SetPropagateKeyboardInput(false)
        end)
        keyBtn:SetScript("OnKeyDown", function(self, key)
            if not capturing then
                self:SetPropagateKeyboardInput(true)
                return
            end
            self:SetPropagateKeyboardInput(false)
            if MODIFIERS[key] then return end
            capturing = false
            self:EnableKeyboard(false)
            if key ~= "ESCAPE" then
                local combo = (IsAltKeyDown() and "ALT-" or "") .. (IsControlKeyDown() and "CTRL-" or "")
                    .. (IsShiftKeyDown() and "SHIFT-" or "") .. key
                db.key = combo
                if db.on then applyBinding() else refreshFishBtn() end
            end
            p.RefreshAll()
        end)
        p.widgets[#p.widgets + 1] = { refresh = function()
            if not capturing then keyBtn:SetText(db.key or "Click to set a key") end
        end }

        UI.Header(p, "While fishing", L, -190)
        UI.Check(p, "Loot automatically", "Takes effect next time you switch fishing mode on.", L, -212,
            function() return db.autoLoot end, function(v) db.autoLoot = v end)
        UI.Check(p, "Louder effects, quiet music", "Easier to hear the splash. Your settings come back when you switch off.", L, -238,
            function() return db.loudSound end, function(v) db.loudSound = v end)
        UI.Check(p, "Show the toolbox", "The small box with on/off, lure and hide buttons.", L, -264,
            function() return db.toolbox end,
            function(v) db.toolbox = v applyToolboxVisibility() end)

        UI.Header(p, "Lure", R, -66)
        UI.Note(p, "The lure button never applies a new lure while one is still active on your pole, and it needs a fishing pole in your main hand.", R, -88, 240)
        UI.Check(p, "Apply a lure automatically", "When no lure is active, your key press applies one first, then the next press casts. Never while a lure is still active.", R, -138,
            function() return db.autoLure end,
            function(v) db.autoLure = v updateLure() end)
        local q
        q = UI.Button(p, "Strong", 140, R + 6, -166, function(self)
            db.lureQuality = (db.lureQuality == "weakest") and "best" or "weakest"
            p.RefreshAll()
            updateLure()
        end)
        p.widgets[#p.widgets + 1] = { refresh = function()
            q:SetText(db.lureQuality == "weakest" and "Lure quality: Weak" or "Lure quality: Strong")
        end }
        UI.Header(p, "Which lure to use:", R, -204)
        local cycle
        cycle = UI.Button(p, "Auto", 230, R, -226, function(self)
            local list = { "auto" }
            for _, n in ipairs(LURES) do if itemCount(n) > 0 then list[#list + 1] = n end end
            local idx = 1
            for i, n in ipairs(list) do if n == db.lure then idx = i end end
            idx = idx % #list + 1
            db.lure = list[idx]
            p.RefreshAll()
            updateLure()
        end)
        p.widgets[#p.widgets + 1] = { refresh = function()
            cycle:SetText((db.lure or "auto") == "auto" and "Auto (by quality above)" or db.lure)
        end }
        UI.Note(p, "Click to cycle through the lures you carry.", R, -252, 240)

        UI.Header(p, "Or type an item name:", R, -282)
        local edit = UI.EditBox(p, 230, R, -310)
        edit:SetScript("OnEnterPressed", function(self)
            db.customLure = self:GetText()
            self:ClearFocus()
            updateLure()
        end)
        edit:SetScript("OnEditFocusLost", function(self)
            db.customLure = self:GetText()
            updateLure()
        end)
        p.widgets[#p.widgets + 1] = { refresh = function() edit:SetText(db.customLure or "") end }
        UI.Note(p, "Leave empty to use the list above. A typed name wins over it.", R, -338, 240)
    end,
    function() return db and (db.on and "on" or "off") end)

SLASH_LAZYFISHER1 = "/lazyfish"
SLASH_LAZYFISHER2 = "/lf"
SlashCmdList.LAZYFISHER = function(input)
    if not db then return end
    local cmd = (input or ""):match("^(%S*)"):lower()
    if cmd == "on" then
        if not db.on then switchOn() end
    elseif cmd == "off" then
        if db.on then switchOff() end
    elseif cmd == "toggle" then
        toggleMode()
    elseif cmd == "show" then
        db.toolbox = true
        applyToolboxVisibility()
    else
        Hub.Open("lazyfish")
    end
end

---------------------------------------------------------------------------
-- Fishing Stats panel
---------------------------------------------------------------------------
local QUALITY = {
    [0] = { 0.62, 0.62, 0.62 }, [1] = { 1, 1, 1 }, [2] = { 0.12, 1, 0 },
    [3] = { 0, 0.44, 0.87 }, [4] = { 0.64, 0.21, 0.93 }, [5] = { 1, 0.5, 0 },
}

local function fmtTime(sec)
    sec = math.floor(sec or 0)
    local h, m = math.floor(sec / 3600), math.floor((sec % 3600) / 60)
    if h > 0 then return string.format("%dh %02dm", h, m) end
    return string.format("%dm %02ds", m, sec % 60)
end

local function pct(a, b)
    if not b or b == 0 then return "-" end
    return string.format("%d%%", math.floor(100 * a / b + 0.5))
end

Hub.Register("fishstats", "Fishing Stats", "Interface\\Icons\\INV_Misc_Fish_02",
    "What you caught this session and in total. Counted from the loot window, so only real catches.",
    function(p)
        local PAL = UI.PAL
        local function line(label, x, y)
            local l = p:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
            l:SetPoint("TOPLEFT", x, y)
            l:SetText(label)
            l:SetTextColor(PAL.dim[1] + 0.2, PAL.dim[2] + 0.2, PAL.dim[3] + 0.2)
            local v = p:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
            v:SetPoint("TOPLEFT", x + 120, y)
            return v
        end
        UI.Header(p, "This session", 14, -72)
        local sCasts = line("Casts", 14, -96)
        local sCatches = line("Catches", 14, -116)
        local sRate = line("Success", 14, -136)
        local sHour = line("Fish per hour", 14, -156)
        local sTime = line("Line in water", 14, -176)
        UI.Header(p, "All time", 290, -72)
        local aCasts = line("Casts", 290, -96)
        local aCatches = line("Catches", 290, -116)
        local aRate = line("Success", 290, -136)
        local aTime = line("Line in water", 290, -156)

        UI.Header(p, "Catches", 14, -208)
        UI.Button(p, "Reset session", 100, 340, -204, function()
            session = { casts = 0, catches = 0, lineTime = 0, items = {}, first = nil, last = nil }
            p.RefreshAll()
        end)
        UI.Button(p, "Reset all time", 100, 446, -204, function()
            db.stats = { casts = 0, catches = 0, lineTime = 0, items = {} }
            p.RefreshAll()
        end)
        UI.Note(p, "Success is catches per cast. A cast that you cancel or let run out counts as a miss.", 14, -230, 470)

        local rows = {}
        for i = 1, 9 do
            local y = -258 - (i - 1) * 22
            local icon = p:CreateTexture(nil, "ARTWORK")
            icon:SetSize(18, 18)
            icon:SetPoint("TOPLEFT", 14, y)
            icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
            local name = p:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
            name:SetPoint("LEFT", icon, "RIGHT", 8, 0)
            local total = p:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
            total:SetPoint("TOPLEFT", 340, y - 2)
            local sess = p:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
            sess:SetPoint("TOPLEFT", 420, y - 3)
            rows[i] = { icon = icon, name = name, total = total, sess = sess }
        end
        local colA = p:CreateFontString(nil, "ARTWORK", "GameFontNormalSmall")
        colA:SetPoint("TOPLEFT", 340, -244)
        colA:SetText("ALL TIME")
        local colB = p:CreateFontString(nil, "ARTWORK", "GameFontNormalSmall")
        colB:SetPoint("TOPLEFT", 420, -244)
        colB:SetText("SESSION")

        local function render()
            sCasts:SetText(session.casts)
            sCatches:SetText(session.catches)
            sRate:SetText(pct(session.catches, session.casts))
            local rate = "-"
            if session.first and session.last and session.last - session.first >= 60 then
                rate = string.format("%.1f", session.catches / ((session.last - session.first) / 3600))
            end
            sHour:SetText(rate)
            sTime:SetText(fmtTime(session.lineTime))
            aCasts:SetText(db.stats.casts)
            aCatches:SetText(db.stats.catches)
            aRate:SetText(pct(db.stats.catches, db.stats.casts))
            aTime:SetText(fmtTime(db.stats.lineTime))

            local list = {}
            for name, e in pairs(db.stats.items) do list[#list + 1] = { name = name, e = e } end
            table.sort(list, function(x, y)
                if x.e.count ~= y.e.count then return x.e.count > y.e.count end
                return x.name < y.name
            end)
            for i, r in ipairs(rows) do
                local it = list[i]
                if it then
                    local q = QUALITY[it.e.quality or 1] or QUALITY[1]
                    r.icon:SetTexture(it.e.icon)
                    r.icon:Show()
                    r.name:SetText(it.name)
                    r.name:SetTextColor(q[1], q[2], q[3])
                    r.total:SetText(it.e.count)
                    local sc = session.items[it.name]
                    r.sess:SetText(sc and ("+" .. sc.count) or "")
                    r.sess:SetTextColor(PAL.aqua[1], PAL.aqua[2], PAL.aqua[3])
                else
                    r.icon:Hide()
                    r.name:SetText("")
                    r.total:SetText("")
                    r.sess:SetText("")
                end
            end
            if #list == 0 then
                rows[1].name:SetText("Nothing caught yet. Go fish.")
                rows[1].name:SetTextColor(0.6, 0.7, 0.7)
            end
        end
        p.widgets[#p.widgets + 1] = { refresh = render }
        local acc = 0
        p:SetScript("OnUpdate", function(_, dt)
            acc = acc + dt
            if acc > 1 then acc = 0 render() end
        end)
    end,
    function() return session.catches .. " caught" end)
