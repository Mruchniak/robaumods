local ADDON, ns = ...

-- LFGMsg: a saved message box under the Looking For Group window, plus a
-- [Send PM] button on every group listing that whispers that message to the leader.
-- Frames (found with /lfgmsg frame): LFGParentFrame > LFGBrowseFrame > LFGBrowseFrameScrollBox

local function say(msg) print("|cff55ccffLFGMsg|r: " .. msg) end
local issecret = issecretvalue or function() return false end

local box          -- container frame under the LFG window
local edit         -- the edit box
local rowButtons = setmetatable({}, { __mode = "k" })

---------------------------------------------------------------------------
-- Listing helpers
---------------------------------------------------------------------------
local function resultIDOf(row)
    if row.resultID then return row.resultID end
    if row.GetElementData then
        local ok, data = pcall(row.GetElementData, row)
        if ok and data then
            if type(data) == "table" then
                return data.resultID or data.searchResultID or data.id
            end
            return data
        end
    end
    return nil
end

local function leaderOf(resultID)
    if not resultID or not C_LFGList or not C_LFGList.GetSearchResultInfo then return nil end
    local ok, info = pcall(C_LFGList.GetSearchResultInfo, resultID)
    if ok and type(info) == "table" then return info.leaderName end
    return nil
end

-- Who we whispered and when (this session only), so the list can show "Sent 23s".
local sent = {}

local function sentAgo(name)
    if not name or issecret(name) then return nil end
    local t = sent[name]
    if not t then return nil end
    local window = (LFGMsgDB and LFGMsgDB.sentWindow or 1) * 60
    local ago = GetTime() - t
    if ago > window then
        sent[name] = nil
        return nil
    end
    return ago
end

local function fmtAgo(sec)
    if sec < 60 then return string.format("%ds", math.floor(sec)) end
    return string.format("%dm", math.floor(sec / 60))
end

local function sendTo(name)
    if not name or name == "" then
        say("this listing has no leader name I can read.")
        return
    end
    if issecret(name) then
        say("the game hides this leader's name right now, can't whisper.")
        return
    end
    local text = (edit and edit:GetText() or ""):gsub("[\r\n]+", " ")
    text = text:gsub("^%s+", ""):gsub("%s+$", "")
    if text == "" then
        say("type a message in the box under the window first.")
        return
    end
    local ok, err = pcall(SendChatMessage, text, "WHISPER", nil, name)
    if ok then
        sent[name] = GetTime()
        say("sent to " .. name)
    else
        say("could not send: " .. tostring(err))
    end
end

---------------------------------------------------------------------------
-- Per-listing button
---------------------------------------------------------------------------
local function attachButton(row)
    local b = rowButtons[row]
    if not b then
        b = ns.UI.RawButton(row, 72, 18, "Send PM")
        b:SetPoint("BOTTOMRIGHT", row, "BOTTOMRIGHT", -8, 6)
        b:SetFrameLevel(row:GetFrameLevel() + 5)
        b:SetScript("OnClick", function(self)
            local name = leaderOf(resultIDOf(self:GetParent()))
            local ago = sentAgo(name)
            if ago and not IsShiftKeyDown() then
                say("you already messaged " .. name .. " " .. fmtAgo(ago) .. " ago. Shift-click to send again.")
                return
            end
            sendTo(name)
        end)
        b:SetScript("OnEnter", function(self)
            local name = leaderOf(resultIDOf(self:GetParent()))
            local ago = sentAgo(name)
            if ago then
                GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
                GameTooltip:SetText("Already messaged " .. name .. " " .. fmtAgo(ago) .. " ago", 1, 0.82, 0.1)
                GameTooltip:AddLine("Shift-click to send again.", 0.8, 0.8, 0.8)
                GameTooltip:Show()
            end
        end)
        b:SetScript("OnLeave", function() GameTooltip:Hide() end)
        rowButtons[row] = b
    end
    local id = resultIDOf(row)
    b:SetShown(LFGMsgDB.showButtons ~= false and id ~= nil)
    if id ~= nil then
        local ago = sentAgo(leaderOf(id))
        if ago then
            b:SetText("Sent " .. fmtAgo(ago))
            b.label:SetTextColor(1, 0.82, 0.1)
        else
            b:SetText("Send PM")
            b.label:SetTextColor(1, 1, 1)
        end
    end
end

local function refreshRows()
    local sb = LFGBrowseFrameScrollBox or (LFGBrowseFrame and LFGBrowseFrame.ScrollBox)
    if not sb then return end
    if sb.ForEachFrame then
        sb:ForEachFrame(attachButton)
    elseif sb.ScrollTarget then
        for _, row in ipairs({ sb.ScrollTarget:GetChildren() }) do attachButton(row) end
    end
end

---------------------------------------------------------------------------
-- Message box under the window
---------------------------------------------------------------------------
local function build()
    local anchor = LFGParentFrame
    box = CreateFrame("Frame", "LFGMsgBox", anchor)
    box:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", 6, -2)
    box:SetPoint("TOPRIGHT", anchor, "BOTTOMRIGHT", -6, -2)
    box:SetHeight(96)

    ns.UI.Panel(box)

    local title = box:CreateFontString(nil, "ARTWORK", "GameFontNormalSmall")
    title:SetPoint("TOPLEFT", 8, -6)
    title:SetText("Message for Send PM")
    title:SetTextColor(ns.UI.PAL.aqua[1], ns.UI.PAL.aqua[2], ns.UI.PAL.aqua[3])

    local count = box:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
    count:SetPoint("TOPRIGHT", -8, -6)

    edit = CreateFrame("EditBox", "LFGMsgEdit", box)
    edit:SetMultiLine(true)
    edit:SetAutoFocus(false)
    edit:SetMaxLetters(255)
    edit:SetFontObject(ChatFontNormal or GameFontHighlight)
    edit:SetPoint("TOPLEFT", 8, -22)
    edit:SetPoint("BOTTOMRIGHT", -8, 6)
    edit:SetTextInsets(2, 2, 2, 2)
    edit:SetText(LFGMsgDB.text or "")
    edit:SetScript("OnEscapePressed", edit.ClearFocus)
    edit:SetScript("OnTextChanged", function(self, userInput)
        LFGMsgDB.text = self:GetText()
        count:SetText(#self:GetText() .. "/255")
    end)
    count:SetText(#edit:GetText() .. "/255")

    -- click anywhere in the box to start typing
    box:EnableMouse(true)
    box:SetScript("OnMouseDown", function() edit:SetFocus() end)

    box:SetShown(LFGMsgDB.showBox ~= false)

    -- keep the Send PM buttons in sync with the scrolling list (runs while the LFG window is open)
    local ticker = CreateFrame("Frame", nil, anchor)
    local acc = 0
    ticker:SetScript("OnUpdate", function(_, dt)
        acc = acc + dt
        if acc > 0.25 then acc = 0 refreshRows() end
    end)
end

local function tryBuild()
    if box then return true end
    if not LFGParentFrame or not LFGBrowseFrame then return false end
    local ok, err = pcall(build)
    if not ok then
        say("could not build the message box: " .. tostring(err))
        box = nil
        return true  -- do not retry forever
    end
    return true
end

---------------------------------------------------------------------------
-- Discovery tool (kept for debugging)
---------------------------------------------------------------------------
local function dumpFrame()
    local foci
    if GetMouseFoci then foci = GetMouseFoci() elseif GetMouseFocus then foci = { GetMouseFocus() } end
    local f = foci and foci[1]
    if not f then say("no frame under the mouse") return end
    for i = 1, 6 do
        if not f then break end
        local n = {}
        pcall(function()
            for k, v in pairs(f) do
                if type(k) == "string" and (type(v) ~= "table" and type(v) ~= "userdata") then
                    n[#n + 1] = k .. "=" .. tostring(v)
                end
            end
        end)
        local okName, name = pcall(f.GetName, f)
        print(string.rep(">", i - 1) .. " " .. tostring(okName and name) .. " { " .. table.concat(n, ", ") .. " }")
        local ok, p = pcall(f.GetParent, f)
        f = ok and p or nil
    end
end

---------------------------------------------------------------------------
-- Boot
---------------------------------------------------------------------------
local ev = CreateFrame("Frame")
ev:RegisterEvent("ADDON_LOADED")
ev:RegisterEvent("PLAYER_LOGIN")
ev:SetScript("OnEvent", function(self, event, name)
    if event == "ADDON_LOADED" and name == ADDON then
        LFGMsgDB = LFGMsgDB or {}
        if LFGMsgDB.showBox == nil then LFGMsgDB.showBox = true end
        if LFGMsgDB.showButtons == nil then LFGMsgDB.showButtons = true end
        if LFGMsgDB.sentWindow == nil then LFGMsgDB.sentWindow = 1 end
    end
    if event == "PLAYER_LOGIN" or event == "ADDON_LOADED" then
        if LFGMsgDB and tryBuild() then self:UnregisterEvent("ADDON_LOADED") end
    end
end)

-- The LFG frames may load later; retry for a while.
C_Timer.NewTicker(1, function(t)
    if LFGMsgDB and tryBuild() then t:Cancel() end
end, 60)

SLASH_LFGMSG1 = "/lfgmsg"
SlashCmdList.LFGMSG = function(input)
    local cmd = (input or ""):match("^(%S*)"):lower()
    if cmd == "frame" then
        say("hover over a frame now, dumping in 4 seconds...")
        C_Timer.After(4, dumpFrame)
    elseif cmd == "status" then
        say("box: " .. tostring(box ~= nil) .. ", LFGParentFrame: " .. tostring(LFGParentFrame ~= nil)
            .. ", LFGBrowseFrame: " .. tostring(LFGBrowseFrame ~= nil))
    else
        say("/lfgmsg status | frame (hover over a frame, wait 4 s)")
    end
end

---------------------------------------------------------------------------
-- Settings panel (Robau Mod Suite window)
---------------------------------------------------------------------------
local UI, Hub = ns.UI, ns.Hub
Hub.Register("lfgmsg", "LFG Message", "Interface\\Icons\\INV_Misc_GroupLooking",
    "A saved message under the Looking For Group window and a Send PM button on every group.",
    function(p)
        UI.Check(p, "Show the message box under the LFG window",
            "The box where you type the message that Send PM whispers.", 12, -70,
            function() return LFGMsgDB.showBox ~= false end,
            function(v)
                LFGMsgDB.showBox = v
                if box then box:SetShown(v) end
            end)
        UI.Check(p, "Show Send PM buttons on the group list",
            "One button per group, whispering your message to the group leader.", 12, -98,
            function() return LFGMsgDB.showButtons ~= false end,
            function(v)
                LFGMsgDB.showButtons = v
                refreshRows()
                if not v then
                    for _, b in pairs(rowButtons) do b:Hide() end
                end
            end)
        UI.Stepper(p, function(v) return "Show 'Sent' for: " .. v .. (v == 1 and " minute" or " minutes") end, 12, -130,
            function() return LFGMsgDB.sentWindow or 1 end,
            function(v) LFGMsgDB.sentWindow = v end, 1, 60, 1)
        UI.Note(p, "After you whisper a leader, their button says Sent for this long. Clicking it again does nothing unless you hold Shift.", 12, -160, 480)
        UI.Header(p, "Your message", 12, -204)
        UI.Note(p, "Open the Looking For Group window. The editable box sits right under it and the text is saved between sessions.", 12, -226, 480)
        UI.Button(p, "Clear saved message", 160, 12, -274, function()
            LFGMsgDB.text = ""
            if edit then edit:SetText("") end
        end)
        UI.Note(p, "Whispers are sent only when you click. The game hides some leader names, and addons cannot whisper inside instances.", 12, -314, 480)
    end,
    function() return (LFGMsgDB and LFGMsgDB.showButtons ~= false) and "buttons on" or "buttons off" end)
