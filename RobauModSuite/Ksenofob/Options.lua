local ADDON, ns = ...
local UI, Hub = ns.UI, ns.Hub

-- Ksenofob settings panel (lives inside the Robau Mod Suite window).
function ns.RefreshOptions()
    if ns.ksenPanel and ns.ksenPanel.RefreshAll then ns.ksenPanel.RefreshAll() end
end

function ns.OpenOptions()
    Hub.Open("ksenofob")
end

function ns.OnCountWindow()
    if ns.ksenPanel and ns.ksenPanel:IsVisible() then ns.ksenPanel.RefreshAll() end
end

local function build(p)
    local db = ns.db
    ns.ksenPanel = p
    local L, R = 12, 280

    -- left column
    UI.Check(p, "Enable Ksenofob", nil, L, -66,
        function() return db.enabled end, function(v) db.enabled = v end)

    UI.Header(p, "Block messages written in:", L, -100)
    local langs = { { "de", "German" }, { "fr", "French" }, { "ru", "Russian" } }
    local y = -122
    for _, l in ipairs(langs) do
        UI.Check(p, l[2], "Messages containing common " .. l[2] .. " words are hidden.", L, y,
            function() return db.langs[l[1]] end, function(v) db.langs[l[1]] = v end)
        y = y - 26
    end
    UI.Check(p, "Any Cyrillic text counts as Russian",
        "Hides every message containing Cyrillic letters (if Russian is blocked).", L, y,
        function() return db.blockCyrillicText end, function(v) db.blockCyrillicText = v end)

    y = y - 40
    UI.Header(p, "Player names:", L, y)
    y = y - 22
    UI.Check(p, "Hide Cyrillic nicknames",
        "Any message from a player whose name contains Cyrillic letters is hidden.", L, y,
        function() return db.blockCyrillicNames end, function(v) db.blockCyrillicNames = v end)
    y = y - 26
    UI.Check(p, "Hide other non-Latin nicknames",
        "Chinese, Japanese, Korean, Arabic, Hebrew and Greek names.", L, y,
        function() return db.blockOtherScriptNames end, function(v) db.blockOtherScriptNames = v end)

    -- right column
    UI.Header(p, "Where to filter:", R, -100)
    local where = {
        { "filterPublic", "Say, yell, emotes, channels" },
        { "filterWhispers", "Whispers" },
        { "filterGroup", "Party, raid, instance" },
        { "filterGuild", "Guild and officer" },
    }
    local ry = -122
    for _, w in ipairs(where) do
        UI.Check(p, w[2], nil, R, ry,
            function() return db[w[1]] end, function(v) db[w[1]] = v end)
        ry = ry - 26
    end

    ry = ry - 14
    UI.Header(p, "Sensitivity:", R, ry)
    ry = ry - 22
    UI.Stepper(p, function(v) return "Word matches needed: " .. v end, R, ry,
        function() return db.sensitivity end, function(v) db.sensitivity = v end, 1, 4, 1)
    UI.Note(p, "1 = aggressive (more false hits), 4 = careful.", R, ry - 30, 220)

    -- counter
    local counter = p:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
    counter:SetPoint("TOPRIGHT", -16, -14)
    counter:SetJustifyH("RIGHT")
    p.widgets[#p.widgets + 1] = { refresh = function()
        counter:SetText("Blocked: |cffffd100" .. ns.session .. "|r this session\n|cffffd100" .. db.blocked .. "|r in total")
    end }
    UI.Button(p, "Reset counter", 110, 380, -380, function()
        db.blocked = 0
        ns.session = 0
        p.RefreshAll()
    end)
end

Hub.Register("ksenofob", "Ksenofob", "Interface\\Icons\\Ability_Warrior_Rampage",
    "Hides chat written in German, French or Russian and messages from players with Cyrillic nicknames.",
    build,
    function() return (ns.session or 0) .. " blocked" end)
