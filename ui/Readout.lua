-- Nexus: ui/Readout.lua
-- Pure string builders for the panel and journal tab. No frames, no IO,
-- no WoW API: loadable under bare LuaJIT for the offline suite. Names
-- arrive pre-bridged (spellId -> name) by the caller; a missing name
-- falls back to the spellId so a line is never blank.

Nexus = Nexus or {}
local M = {}
Nexus.Readout = M

local QUALITY_NAMES = {
    [0] = "Common", [1] = "Uncommon", [2] = "Rare",
    [3] = "Epic", [4] = "Legendary",
}

-- %d on a raw float truncates silently on this toolchain; round first.
local function Round(x)
    return math.floor(x + 0.5)
end

local function NameOf(t)
    if type(t) ~= "table" then return "?" end
    if t.name ~= nil then return tostring(t.name) end
    if t.spellId ~= nil then return "spell " .. tostring(t.spellId) end
    return "?"
end

-- One honest sentence. model = { text=s|nil (verbatim main clause),
-- level=n|nil, advisorOnly=b, synced=b|nil, charges=charges|nil }.
-- Derived fallbacks cover the states Main may not phrase itself;
-- charges append as "B:n R:n F:n", "(approx)" when not trustworthy.
function M.Status(model)
    if type(model) ~= "table" then return "" end
    local main
    if model.text ~= nil then
        main = Nexus.UserText and Nexus.UserText.Message(model.text) or tostring(model.text)
    elseif model.advisorOnly then
        main = "No Wishlist assigned - recommendations only"
    elseif model.synced == false then
        main = "Waiting for current Echo data - automatic choices paused"
    else
        main = "idle"
    end
    if type(model.level) == "number" then
        main = string.format("Lv %d - %s", Round(model.level), main)
    end
    local c = model.charges
    if type(c) == "table" then
        local s = string.format("Banish:%d Reroll:%d Freeze:%d",
            Round(tonumber(c.banish) or 0),
            Round(tonumber(c.reroll) or 0),
            Round(tonumber(c.freeze) or 0))
        if c.trustworthy == false then s = s .. " (estimated)" end
        main = main .. " | " .. s
    end
    return main
end

-- "[G] Name (Epic) +100 wanted". card = board card (+ bridged .name),
-- annotation = Policy annotation word or nil, delta = number or nil.
function M.CardLine(card, annotation, delta)
    if type(card) ~= "table" then return "" end
    local parts = {}
    if card.isGuaranteed then parts[#parts + 1] = "[Guaranteed offer]" end
    parts[#parts + 1] = NameOf(card)
    local q = QUALITY_NAMES[card.quality]
    if q then parts[#parts + 1] = "(" .. q .. ")" end
    -- Scores remain available in diagnostics; they are priorities, not DPS.
    -- The "[Guaranteed offer]" prefix already states EchoWeaver's
    -- "guaranteed" annotation.
    if annotation ~= nil and annotation ~= ""
        and not (annotation == "guaranteed" and card.isGuaranteed) then
        parts[#parts + 1] = Nexus.UserText and Nexus.UserText.Annotation(annotation) or tostring(annotation)
    end
    return table.concat(parts, " ")
end

-- The card the current recommendation takes: exactly one card that the
-- runtime marked as the Take target (card.highlight). None, or several (the
-- same Echo offered twice), gives nil, so no card is guessed.
function M.MarkedCard(cards)
    if type(cards) ~= "table" then return nil end
    local found
    for i = 1, math.min(#cards, 3) do
        local c = cards[i]
        if type(c) == "table" and c.highlight == true then
            if found then return nil end
            found = i
        end
    end
    return found
end

-- "Name (Quality)" from a CardLine text; nil when the line carries no known
-- quality, since the name then cannot be told from its annotation.
function M.CardTarget(text)
    text = tostring(text or ""):gsub("^%[Guaranteed offer%] ", "")
    local first, last
    for _, q in pairs(QUALITY_NAMES) do
        local s, e = text:find(" (" .. q .. ")", 1, true)
        if s and (not first or s < first) then first, last = s, e end
    end
    if not first or first <= 1 then return nil end
    return text:sub(1, last)
end

-- An unstepped recommendation with its definite target named:
-- "<reason>: <Name (Quality)>". A stepped plan (numbered lines) already
-- names each step and is returned unchanged, as is a line with no target.
function M.RecommendationWithTarget(recommendation, cardText)
    local text = tostring(recommendation or "")
    if text:find("^%d+%. ") or text:find("\n%d+%. ") then return text end
    local target = M.CardTarget(cardText)
    if not target then return text end
    if text == "" then return "Take: " .. target end
    return text .. ": " .. target
end

-- Compact charges for the roll heading, "B:2 R:1 F:0". A count the game has
-- not reported (charges.arrived == false, or no number) is "?", never 0;
-- counts the adapter does not trust are marked "~" (estimated). Without a
-- charges table there is nothing to show (""). Formatting only: it reads no
-- service and changes no count.
function M.ChargesLine(charges)
    if type(charges) ~= "table" then return "" end
    local arrived = charges.arrived ~= false
    local function Count(value)
        value = tonumber(value)
        if not arrived or value == nil or value ~= value or value < 0
            or value >= math.huge then return "?" end
        return tostring(Round(value))
    end
    local line = "B:" .. Count(charges.banish) .. " R:" .. Count(charges.reroll)
        .. " F:" .. Count(charges.freeze)
    if arrived and charges.trustworthy == false then line = line .. " ~" end
    return line
end

-- Next n predicted guaranteed arrivals, "(predicted)" suffixed --
-- injection order is measured but not version-stable, never state it
-- as fact. queue = Ratchet.PredictQueue output (entries pre-bridged).
function M.QueueLines(queue, n)
    local out = {}
    if type(queue) ~= "table" then return out end
    local entries = queue.entries
    if type(entries) ~= "table" then return out end
    local limit = tonumber(n) or 3
    for i = 1, math.min(#entries, limit) do
        local e = entries[i]
        if type(e) == "table" then
            out[#out + 1] = string.format("%d. %s%s (predicted)",
                i, NameOf(e), e.wanted and " [wanted]" or "")
        end
    end
    return out
end
