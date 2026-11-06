local ADDON, ns = ...

local issecret = issecretvalue or function() return false end

local defaults = {
    enabled = true,
    langs = { de = true, fr = true, ru = true },
    blockCyrillicNames = true,
    blockOtherScriptNames = false,   -- CJK, Korean, Arabic, Hebrew, Greek
    blockCyrillicText = true,        -- any Cyrillic message counts as Russian
    sensitivity = 2,                 -- word hits needed to flag a message
    filterPublic = true,             -- say, yell, emote, channels
    filterWhispers = false,
    filterGroup = false,             -- party, raid, instance
    filterGuild = false,
    blocked = 0,
}

local EVENTS = {
    filterPublic = { "CHAT_MSG_SAY", "CHAT_MSG_YELL", "CHAT_MSG_EMOTE", "CHAT_MSG_CHANNEL" },
    filterWhispers = { "CHAT_MSG_WHISPER" },
    filterGroup = { "CHAT_MSG_PARTY", "CHAT_MSG_PARTY_LEADER", "CHAT_MSG_RAID", "CHAT_MSG_RAID_LEADER",
                    "CHAT_MSG_RAID_WARNING", "CHAT_MSG_INSTANCE_CHAT", "CHAT_MSG_INSTANCE_CHAT_LEADER" },
    filterGuild = { "CHAT_MSG_GUILD", "CHAT_MSG_OFFICER" },
}
local eventOpt = {}
for opt, list in pairs(EVENTS) do
    for _, e in ipairs(list) do eventOpt[e] = opt end
end

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

local db

-- UTF-8 script detection by lead byte.
local CYR = "[\208-\211][\128-\191]"        -- U+0400..U+04FF
local OTHER = {
    "[\206\207][\128-\191]",                -- Greek
    "\215[\128-\191]",                      -- Hebrew
    "[\216-\219][\128-\191]",               -- Arabic
    "[\227-\237][\128-\191][\128-\191]",    -- CJK, Hiragana/Katakana, Hangul
}

local function hasCyrillic(s) return s:find(CYR) ~= nil end
local function hasOtherScript(s)
    for _, p in ipairs(OTHER) do
        if s:find(p) then return true end
    end
    return false
end

local function clean(msg)
    msg = msg:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")
    msg = msg:gsub("|H.-|h.-|h", " ")
    msg = msg:gsub("|T.-|t", " ")
    msg = msg:gsub("{[%a%d]-}", " ")
    msg = msg:gsub("’", " "):gsub("'", " ")
    return msg
end

-- Returns the language code the message is written in (only enabled languages), or nil.
local function detect(msg)
    msg = clean(msg)
    if db.langs.ru and db.blockCyrillicText and hasCyrillic(msg) then return "ru" end

    local lower = msg:lower()
    local hits = { de = 0, fr = 0, ru = 0 }
    local seen = {}
    for w in lower:gmatch("[%w\128-\255]+") do
        if not seen[w] then
            seen[w] = true
            for lang, words in pairs(ns.WORDS) do
                if words[w] then hits[lang] = hits[lang] + 1 end
            end
        end
    end
    for lang, marks in pairs(ns.MARKERS) do
        for _, m in ipairs(marks) do
            if msg:find(m, 1, true) then hits[lang] = hits[lang] + 1 break end
        end
    end

    for _, lang in ipairs({ "de", "fr", "ru" }) do
        if db.langs[lang] then
            local n = hits[lang]
            -- transliterated Russian words are distinctive: one hit is enough
            if lang == "ru" and n >= 1 then return "ru" end
            if n >= db.sensitivity then return lang end
        end
    end
    return nil
end

local function badName(author)
    if db.blockCyrillicNames and hasCyrillic(author) then return true end
    if db.blockOtherScriptNames and hasOtherScript(author) then return true end
    return false
end

ns.session = 0
function ns.Count()
    db.blocked = db.blocked + 1
    ns.session = ns.session + 1
    if ns.OnCountWindow then ns.OnCountWindow() end
end

local playerName
local function filter(_, event, msg, author)
    if not db or not db.enabled then return false end
    if not db[eventOpt[event] or "filterPublic"] then return false end
    -- Midnight "secret values": cannot be inspected, so let them through.
    if issecret(msg) or issecret(author) then return false end
    if type(msg) ~= "string" or type(author) ~= "string" then return false end
    if author ~= "" then
        local short = author:match("^[^-]+") or author
        if short == playerName then return false end
        if badName(author) then
            ns.Count()
            return true
        end
    end
    if detect(msg) then
        ns.Count()
        return true
    end
    return false
end

local registered = false
local function registerFilters()
    if registered then return end
    registered = true
    for e in pairs(eventOpt) do
        ChatFrame_AddMessageEventFilter(e, filter)
    end
end

function ns.Test(text)
    return detect(text)
end

local f = CreateFrame("Frame")
f:RegisterEvent("ADDON_LOADED")
f:RegisterEvent("PLAYER_LOGIN")
f:SetScript("OnEvent", function(_, event, name)
    if event == "ADDON_LOADED" and name == ADDON then
        KsenofobDB = KsenofobDB or {}
        copyDefaults(defaults, KsenofobDB)
        db = KsenofobDB
        ns.db = db
        registerFilters()
    elseif event == "PLAYER_LOGIN" then
        playerName = UnitName("player")
    end
end)

local function say(msg) print("|cffff5555Ksenofob|r: " .. msg) end

SLASH_KSENOFOB1 = "/xeno"
SLASH_KSENOFOB2 = "/ksen"
SLASH_KSENOFOB3 = "/ksenofob"
SlashCmdList.KSENOFOB = function(input)
    if not db then return end
    local cmd, arg = (input or ""):match("^(%S*)%s*(.-)$")
    cmd = cmd:lower()
    if cmd == "toggle" then
        db.enabled = not db.enabled
        say(db.enabled and "enabled" or "disabled")
    elseif cmd == "stats" then
        say(ns.session .. " blocked this session, " .. db.blocked .. " in total")
    elseif cmd == "test" then
        say("detected: " .. tostring(ns.Test(arg)))
    elseif cmd == "de" or cmd == "fr" or cmd == "ru" then
        db.langs[cmd] = not db.langs[cmd]
        say(cmd .. (db.langs[cmd] and " blocked" or " allowed"))
        if ns.RefreshOptions then ns.RefreshOptions() end
    elseif cmd == "help" then
        say("/xeno - open options | toggle | stats | de | fr | ru (toggle language) | test <text>")
    else
        if ns.OpenOptions then ns.OpenOptions() end
    end
end
