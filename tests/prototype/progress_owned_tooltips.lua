-- Run from the candidate source root with the pinned LuaJIT.
-- Read-only renderer probe: no production file is changed.
-- Counting provider is intentional; real JournalTab, row hover handlers,
-- tooltip owners, pooled renderer and existing scanner are exercised.
-- Candidate 1 expectation: three display misses (Missing, Off Wishlist,
-- counts tooltip) and zero guard misses. Do not execute concurrently with CI.
Nexus, NexusDB, WishlistRealizerDB = nil, nil, nil
local H = dofile('tests/prototype/harness.lua')
H.playerLevel = 80
local journal = CreateFrame('Frame', 'ProjectEbonholdEchoJournal', UIParent)
journal:SetSize(570, 450)
CreateFrame('ScrollFrame', 'ProjectEbonholdEchoJournalScroll', journal)
CreateFrame('Button', 'ProjectEbonholdEchoJournalTab1', journal)
H.Boot()
local J = assert(Nexus.JournalTab)
assert(type(J.Invalidate) == 'function', 'SETUP: candidate invalidation API')

local function snapshot(letter, off)
    local offCount = off and 1 or 0
    return {sections={
        {title='Target', lines={string.format(
            "Wishlist 'Tooltip Plan %s': 1 Echo families -- 0 represented, 1 missing, %d off-Wishlist families in the saved build",
            letter, offCount)}},
        {title='Pending (1)', lines={'Missing ' .. letter}},
        {title='Extra copies compared with the plan', lines=off and {
            'Off ' .. letter .. '  (not on the target plan; compare after the next run)',
        } or {}},
        {title='Tome state coverage', lines={'Counting-provider tooltip fixture only.'}},
    }}
end
local data, calls = snapshot('A', true), 0
local function countingProvider()
    calls = calls + 1
    return data
end
assert(J.TryInstall(countingProvider), 'SETUP: actual Journal renderer installed')

-- Record text emitted by the source-installed hover handlers; do not replace
-- those handlers or the renderer. This matches the existing tooltip fixture.
function GameTooltip:SetOwner(owner)
    self._testOwner, self._testLines = owner, {}
end
function GameTooltip:GetOwner() return self._testOwner end
function GameTooltip:IsOwned(owner) return self._testOwner == owner end
function GameTooltip:AddLine(line)
    self._testLines[#self._testLines + 1] = tostring(line)
end
local function tooltipText() return table.concat(GameTooltip._testLines or {}, '\n') end
local function button(text)
    for _, frame in ipairs(H.frames) do
        if frame.kind == 'Button' and frame:IsVisible() and frame:GetText() == text then
            return frame
        end
    end
end
local checks, misses, guardMisses = 0, {}, {}
local function check(value, message, guard)
    checks = checks + 1
    if value then print('OK ' .. message); return end
    local list = guard and guardMisses or misses
    list[#list + 1] = message
    print((guard and 'GUARD_MISS ' or 'DISPLAY_MISS ') .. message)
end
local actionsBefore, sentBefore = #H.actions, #H.sent
journal:Show()
assert(NexusJournalTab):Click()
assert(button('Show details'), 'SETUP: real Show details button'):Click()
assert(NexusJournalPanel:IsVisible(), 'SETUP: visible expanded Progress')
local child = assert(NexusJournalScroll.scrollChild)

local function findRow(name)
    for _, row in ipairs(H.frames) do
        if row.parent == child and row.label and row.status and row.tipName
                and row:IsVisible() and row.label:GetText() == name then
            return row
        end
    end
    error('SETUP: no actual family row named ' .. name)
end
local function countsOwner()
    for _, frame in ipairs(H.frames) do
        if frame.parent == child and frame.offTip and frame:IsVisible() then return frame end
    end
    error('SETUP: no real counts hover owner')
end
local function hover(owner, firstLine)
    assert(owner:IsVisible(), 'SETUP: hover owner is visible')
    assert(owner:GetScript('OnEnter'), 'SETUP: source-installed hover handler')(owner)
    assert(GameTooltip:IsShown() and GameTooltip:GetOwner() == owner,
        'SETUP: source hover owns a visible tooltip')
    assert(GameTooltip._testLines[1] == firstLine,
        'SETUP: hover text is the expected old entry: ' .. tooltipText())
end
local function automaticChange(letter, off, label)
    local before = calls
    data = snapshot(letter, off)
    J.Invalidate()
    check(calls == before, label .. ': invalidation performs no synchronous provider read', true)
    H.Advance(.85, .05)
    check(calls == before + 1, label .. ': exactly one scanner render', true)
end
local function restoreA()
    data = snapshot('A', true)
    J.Refresh()
    assert(findRow('Missing A') and findRow('Off A'), 'SETUP: initial family rows')
end

-- Equal row counts/layout preserve each frame under a stationary pointer.
-- The actual new label and frame identity are separate from tooltip verdicts.
restoreA()
local missing = findRow('Missing A')
hover(missing, 'Missing A')
automaticChange('B', true, 'Missing family rebind')
check(findRow('Missing B') == missing and missing.tipName == 'Missing B',
    'Missing family: same pooled owner now displays B', true)
check(not GameTooltip:IsShown(), 'Missing family: old owned tooltip dismissed before rebind', false)

restoreA()
local off = findRow('Off A')
hover(off, 'Off A')
automaticChange('B', true, 'Off-Wishlist family rebind')
check(findRow('Off B') == off and off.tipName == 'Off B',
    'Off-Wishlist family: same pooled owner now displays B', true)
check(not GameTooltip:IsShown(), 'Off-Wishlist family: old owned tooltip dismissed before rebind', false)

restoreA()
local counts = countsOwner()
hover(counts, 'Wishlist family counts')
local oldOffTip = counts.offTip
automaticChange('B', false, 'counts classification change')
check(countsOwner() == counts and counts.offTip ~= oldOffTip,
    'counts: visible same owner now explains none-listed instead of listed', true)
check(not GameTooltip:IsShown(), 'counts: old owned tooltip dismissed before classification change', false)

-- A static intro tooltip has no target-dependent text and should survive.
-- Identify the actual hover owner by invoking its real handler, not by
-- constructing another frame or replacing a source callback.
restoreA()
local intro
for _, frame in ipairs(H.frames) do
    if frame.parent == child and frame.kind == 'Frame' and frame:IsVisible()
            and frame:GetScript('OnEnter') then
        frame:GetScript('OnEnter')(frame)
        if GameTooltip:GetOwner() == frame and GameTooltip._testLines[1] == 'Build Progress' then
            intro = frame
            break
        end
    end
end
assert(intro, 'SETUP: actual static intro hover owner')
hover(intro, 'Build Progress')
local introText = tooltipText()
automaticChange('B', true, 'static intro preservation')
check(GameTooltip:IsShown() and GameTooltip:GetOwner() == intro and tooltipText() == introText,
    'static intro: tooltip survives unchanged', true)

local unrelated = CreateFrame('Button', nil, journal)
GameTooltip:SetOwner(unrelated, 'ANCHOR_RIGHT')
GameTooltip:AddLine('Unrelated tooltip')
GameTooltip:Show()
local unrelatedText = tooltipText()
automaticChange('C', true, 'unrelated tooltip preservation')
check(GameTooltip:IsShown() and GameTooltip:GetOwner() == unrelated and tooltipText() == unrelatedText,
    'unrelated owner: tooltip survives unchanged', true)
check(#H.actions == actionsBefore and #H.sent == sentBefore,
    'all tooltip/renderer controls send no gameplay or network action', true)

print('RESULT checks=' .. checks .. ' displayMisses=' .. #misses
    .. ' guardMisses=' .. #guardMisses .. ' providerCalls=' .. calls)
assert(#guardMisses == 0, 'GUARD FAILURES:\n' .. table.concat(guardMisses, '\n'))
assert(#misses == 0, 'OWNED TOOLTIP REBIND FAILURES:\n' .. table.concat(misses, '\n'))
print('PASS automatic Progress refresh dismisses dynamic owned tooltips and preserves static/unrelated owners')
