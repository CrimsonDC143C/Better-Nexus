-- Pure Project Ebonhold Echo-catalog materialization.
--
-- This module never reads Project Ebonhold globals. GameAdapter captures the
-- source table and spell-name resolver, then publishes only a complete result.

Nexus = Nexus or {}

local Source = {}
Nexus.EchoCatalogSource = Source

local function SafeText(value)
    local ok, text = pcall(tostring, value)
    return ok and tostring(text or "") or "unprintable catalog error"
end
local function Number(value, fallback)
    local number = tonumber(value)
    if not number or number ~= number or number == math.huge
        or number == -math.huge then return fallback end
    return number
end

local function Encode(value)
    local kind = type(value)
    local text
    if kind == "string" then text = value
    elseif kind == "number" then text = tostring(value)
    elseif kind == "boolean" then text = value and "1" or "0"
    elseif kind == "nil" then text = ""
    else error("non-scalar normalized catalog value") end
    return kind:sub(1, 1) .. tostring(#text) .. ":" .. text
end

local function HashText(text)
    local hash = 5381
    for index = 1, #text do
        hash = ((hash * 33) + text:byte(index)) % 2147483648
    end
    return string.format("%08x", hash)
end

local function ResolveName(resolveSpell, spellId)
    if type(resolveSpell) ~= "function" then return nil end
    local value = resolveSpell(spellId)
    if value ~= nil and type(value) ~= "string" then
        error("spell-name resolver returned a non-string value")
    end
    return value
end

local function EchoName(row, spellId, resolveSpell)
    local name = ResolveName(resolveSpell, spellId)
    if name ~= nil then return name end
    local comment = tostring(row.comment or "")
    return (comment:gsub(" %- %a+$", ""))
end

local function MaterializeUnsafe(database, resolveSpell)
    if type(database) ~= "table" then error("PerkDatabase must be a table") end

    local spellIds = {}
    for spellId, row in pairs(database) do
        if type(spellId) == "number" and Number(spellId) ~= nil
            and type(row) == "table" and row.maxStack then
            spellIds[#spellIds + 1] = spellId
        end
    end
    table.sort(spellIds)

    local rows, groupCount = {}, {}
    for _, spellId in ipairs(spellIds) do
        local row = database[spellId]
        local normalized = {
            spellId=spellId,
            name=EchoName(row, spellId, resolveSpell),
            maxStack=Number(row.maxStack, 1),
            classMask=Number(row.classMask, 0),
            minLevel=Number(row.minLevel, 1),
            quality=Number(row.quality, 0),
            groupId=Number(row.groupId, 0),
            requiredSpell=Number(row.requiredSpell, 0),
        }
        rows[spellId] = normalized
        if normalized.groupId > 0 then
            groupCount[normalized.groupId] = (groupCount[normalized.groupId] or 0) + 1
        end
    end

    local familyOf, familyMembers, familyName = {}, {}, {}
    for _, spellId in ipairs(spellIds) do
        local row = rows[spellId]
        local family = row.groupId > 0 and (groupCount[row.groupId] or 0) > 1
            and ("g" .. tostring(row.groupId)) or ("s" .. tostring(spellId))
        familyOf[spellId] = family
        local members = familyMembers[family]
        if not members then members = {}; familyMembers[family] = members end
        members[#members + 1] = spellId
        if familyName[family] == nil then familyName[family] = row.name end
    end

    local levers = {}
    for _, spellId in ipairs(spellIds) do
        local row = rows[spellId]
        if row.requiredSpell ~= 0 then
            local lever = levers[row.requiredSpell]
            if not lever then
                lever = {
                    lever=row.requiredSpell,
                    members={},
                    conformant=true,
                    tomeName=ResolveName(resolveSpell, row.requiredSpell),
                }
                levers[row.requiredSpell] = lever
            end
            lever.members[#lever.members + 1] = spellId
            if lever.tomeName ~= ("Tome of " .. row.name) then
                lever.conformant = false
            end
        end
    end

    local canonical = {"catalog-source-v1"}
    for _, spellId in ipairs(spellIds) do
        local row = rows[spellId]
        canonical[#canonical + 1] = table.concat({
            Encode(row.spellId), Encode(row.name), Encode(row.maxStack),
            Encode(row.classMask), Encode(row.minLevel), Encode(row.quality),
            Encode(row.groupId), Encode(row.requiredSpell),
            Encode(row.requiredSpell ~= 0 and levers[row.requiredSpell].tomeName or nil),
        })
    end
    canonical = table.concat(canonical)

    return {
        rows=rows,
        familyOf=familyOf,
        familyMembers=familyMembers,
        familyName=familyName,
        levers=levers,
        rowCount=#spellIds,
    }, canonical, HashText(canonical)
end

function Source.Materialize(database, resolveSpell)
    local ok, candidate, canonical, hash = pcall(
        MaterializeUnsafe, database, resolveSpell)
    if not ok then return nil, SafeText(candidate) end
    return candidate, canonical, hash
end

-- Number equality as the canonical text sees it: Encode writes tostring, so
-- 0 and -0 differ there although they compare equal.
local function SameNumber(left, right)
    if left ~= right then return false end
    return left ~= 0 or 1 / left == 1 / right
end

-- "skip" for a source entry that Materialize does not take, true when the row
-- normalizes to the published row (name and lever tome name resolved again),
-- false when it differs. Reads one row, at most two names. Never publishes.
local function VerifyRowUnsafe(catalog, spellId, row, resolveSpell)
    if not (type(spellId) == "number" and Number(spellId) ~= nil
        and type(row) == "table" and row.maxStack) then return "skip" end
    local published = catalog.rows[spellId]
    if type(published) ~= "table" then return false end
    if EchoName(row, spellId, resolveSpell) ~= published.name then return false end
    local requiredSpell = Number(row.requiredSpell, 0)
    if not (SameNumber(Number(row.maxStack, 1), published.maxStack)
        and SameNumber(Number(row.classMask, 0), published.classMask)
        and SameNumber(Number(row.minLevel, 1), published.minLevel)
        and SameNumber(Number(row.quality, 0), published.quality)
        and SameNumber(Number(row.groupId, 0), published.groupId)
        and SameNumber(requiredSpell, published.requiredSpell)) then
        return false
    end
    if requiredSpell ~= 0 then
        local lever = catalog.levers[requiredSpell]
        if type(lever) ~= "table" then return false end
        if ResolveName(resolveSpell, requiredSpell) ~= lever.tomeName then return false end
    end
    return true
end

function Source.VerifyRow(catalog, spellId, row, resolveSpell)
    local ok, result = pcall(VerifyRowUnsafe, catalog, spellId, row, resolveSpell)
    if not ok then return nil, SafeText(result) end
    return result
end

function Source.FamilyDrift(previous, candidate)
    local oldFamilies = type(previous) == "table" and previous.familyOf or nil
    local newFamilies = type(candidate) == "table" and candidate.familyOf or nil
    if type(oldFamilies) ~= "table" or type(newFamilies) ~= "table" then
        return nil
    end
    local spellIds = {}
    for spellId in pairs(oldFamilies) do
        if type(spellId) == "number" and newFamilies[spellId] ~= nil then
            spellIds[#spellIds + 1] = spellId
        end
    end
    table.sort(spellIds)
    for _, spellId in ipairs(spellIds) do
        if oldFamilies[spellId] ~= newFamilies[spellId] then
            return {
                spellId=spellId,
                before=oldFamilies[spellId],
                after=newFamilies[spellId],
            }
        end
    end
    return nil
end
