-- Sequential level-one Wishlist selections through the real Journal picker.
-- At level 1, choosing a Wishlist with tome-gated Echoes must bring the
-- server's tome state to exactly that Wishlist's set: every tome it needs
-- enabled AND every tome it no longer needs disabled. This must hold after
-- EACH selection of A -> B -> C -> A -> ... within one running session (no
-- reload, no rebuilt runtime), not only after the first one.
--
-- Real TOC boot, runtime, adapter and Journal controls: the selector, then a
-- picker row click (ui/JournalTab.lua AssociateWishlistOnly, which calls
-- SetFirstRunWishlist or SetLoadoutWishlist with the row's own candidate).
-- A click is not followed by H.Notify: a Nexus association has no server
-- event. The one modelled boundary is the synthetic server. The harness
-- records ToggleTomeEcho; only an accepted call queues a reply, and a
-- delivered reply flips that Echo's disabled flag and notifies after a short
-- latency, or is held to keep the control pending. An accepted request is
-- never counted as a changed state: every tome verdict reads the server
-- mirror (H.disabled), and a step is settled only with no pending toggle and
-- no undelivered reply.
--
--   SEQ     Auto ON and tome automation permission (autoDisable) ON. After
--           each selection: the exact enabled and disabled set, exactly one
--           accepted request per tome that had to change and none otherwise,
--           nothing left pending. First-run and populated Saved Build
--           destinations, entered by an in-session reset from level 80 or by
--           a level-1 login. Also: a Wishlist with the same tome set, a held
--           server reply, reopening without a choice, re-selecting after
--           Unassign, an idle period, and level 2.
--   GUARD   Auto OFF and/or tome permission OFF: every selection changes the
--           assignment, no tome request is sent, the server is unchanged.
--           Control: grant what was withheld; the same route then mutates.
--   NATIVE  Native Wishlist activation is not a Nexus association. With a
--           populated Saved Build the Nexus target stays that Saved Build's
--           association (saved_build_wishlist_transition.lua; GameAdapter
--           keptSavedBuild). First-run native activation is not covered.
--
-- Every case boots fresh and runs to its end; each step is reported on its
-- own, so a good first selection stays visible beside a failed later one.
-- Run from the repository root. Synthetic ids and names only.
local realPrint = print
local results = {}
local function record(group, case, step, label, check, ok, detail)
    results[#results + 1] = {group=group, case=case, step=step, label=label,
        check=check, ok=ok == true}
    realPrint(string.format('%s %s %s #%s %s (%s): %s', ok == true and 'OK  ' or 'MISS',
        group, case, tostring(step), check, label, tostring(detail)))
end

local TICK, REPLY_DELAY = 0.05, 0.3
-- A step is settled once its wanted state holds with nothing pending and no
-- new request for SETTLE_QUIET seconds. SETTLE_MAX bounds a step that never
-- gets there; it exceeds the runtime's 5 s fallback plus four paced sends.
local SETTLE_MAX, SETTLE_QUIET, HOLD_SECONDS, IDLE_SECONDS = 10, 1.5, 2.5, 6
local LETTERS = {'Amber', 'Birch', 'Cedar', 'Dune', 'Ember'}
local GATED, LEVER, TOME, INDEX_OF_ECHO, TOME_OF_LEVER = {}, {}, {}, {}, {}
for i = 1, #LETTERS do
    GATED[i], LEVER[i], TOME[i] = 300100 + i, 777100 + i, 'T' .. i
    INDEX_OF_ECHO[GATED[i]], TOME_OF_LEVER[LEVER[i]] = i, 'T' .. i
end
-- Common ordinary content is held constant: the Wishlists differ only in
-- their tome-gated Echoes. Overlapping tome sets. T5 is in no Wishlist and must stay disabled. D has
-- the tome set of A in another Wishlist: choosing it after A changes no tome.
local WISHLISTS = {
    A = {slot=101, name='Seq Wishlist A', tomes={1, 2}, ordinary=200011},
    B = {slot=102, name='Seq Wishlist B', tomes={2, 3}, ordinary=200011},
    C = {slot=103, name='Seq Wishlist C', tomes={3, 4}, ordinary=200011},
    D = {slot=104, name='Seq Wishlist D', tomes={1, 2}, ordinary=200011},
}
local SAVED_BUILD = 'Saved Build One'

-- The synthetic server. W.hold keeps every reply queued (control pending).
-- ToggleTomeEcho is a toggle, so a delivered reply flips the Echo's flag.
local function Deliver(W)
    if W.hold or #W.queue == 0 then return end
    local H, kept, delivered = W.H, {}, false
    for _, reply in ipairs(W.queue) do
        if H.now >= reply.due - 1e-9 then
            H.disabled[reply.id] = not (H.disabled[reply.id] == true)
            delivered = true
        else
            kept[#kept + 1] = reply
        end
    end
    W.queue = kept
    if delivered then H.Notify() end
end

local function Run(W, seconds)
    local H = W.H
    local stop = H.now + seconds
    while H.now < stop - 1e-8 do
        H.Advance(TICK, TICK)
        Deliver(W)
    end
end

-- Server truth per tome: true when enabled (no member disabled).
local function Server(W)
    local out = {}
    for i = 1, #GATED do out[i] = W.H.disabled[GATED[i]] ~= true end
    return out
end
local function Vector(tomes)
    local out = {}
    for i = 1, #GATED do out[i] = false end
    for _, i in ipairs(tomes) do out[i] = true end
    return out
end
local function Same(a, b)
    for i = 1, #GATED do if a[i] ~= b[i] then return false end end
    return true
end
local function Show(vector)
    local on, off = {}, {}
    for i = 1, #GATED do
        if vector[i] then on[#on + 1] = TOME[i] else off[#off + 1] = TOME[i] end
    end
    return 'on={' .. table.concat(on, ',') .. '} off={' .. table.concat(off, ',') .. '}'
end
local function Pending()
    local state = Nexus.Store.State()
    local map = type(state) == 'table' and state.tomeTogglePending
    return type(map) == 'table' and map or {}
end
local function Quiet(W) return #W.queue == 0 and next(Pending()) == nil end
local function PendingText()
    local out = {}
    for lever, entry in pairs(Pending()) do
        local direction = type(entry) == 'table' and (entry.want == true and 'disable'
            or entry.want == false and 'enable' or 'unknown') or 'legacy'
        out[#out + 1] = (TOME_OF_LEVER[lever] or tostring(lever)) .. '=' .. direction
    end
    table.sort(out)
    return #out > 0 and table.concat(out, ',') or 'none'
end

-- Accepted requests of one step against the minimal change from the server
-- state before it: one request per tome that must change, none otherwise.
local function Sends(W, step, before, want)
    local count, wrong = {}, {}
    for _, request in ipairs(W.requests) do
        if request.step == step then
            local i = INDEX_OF_ECHO[request.id]
            if i then count[i] = (count[i] or 0) + 1
            else wrong[#wrong + 1] = 'unrelated Echo ' .. tostring(request.id) end
        end
    end
    local sent = {}
    for i = 1, #GATED do
        local n, expected = count[i] or 0, before[i] ~= want[i] and 1 or 0
        if n > 0 then sent[#sent + 1] = TOME[i] .. 'x' .. n end
        if n ~= expected then wrong[#wrong + 1] = TOME[i] .. ' sent ' .. n .. ', want ' .. expected end
    end
    return #wrong == 0, #sent > 0 and table.concat(sent, ',') or 'none', table.concat(wrong, '; ')
end

-- Diagnostics only: the assignment's tomes and the runtime's lever view.
local function AssignedText(W)
    local a = W.A.AssignedWishlist() or {}
    local tomes = {}
    for _, entry in ipairs(a.entries or {}) do
        local i = INDEX_OF_ECHO[tonumber(entry.spellId)]
        if i then tomes[#tomes + 1] = TOME[i] end
    end
    table.sort(tomes)
    return tostring(a.state) .. '/' .. tostring(a.name) .. ' tomes={' .. table.concat(tomes, ',') .. '}'
end
local function LeverView(W)
    local ok, view = pcall(W.A.DisabledLevers)
    if not ok or type(view) ~= 'table' then return 'unreadable' end
    local out = {}
    for i = 1, #GATED do
        local value = view[LEVER[i]]
        out[#out + 1] = TOME[i] .. '=' .. (value == 'confirmed' and 'off'
            or value == 'pending' and 'pending-off' or 'on')
    end
    return table.concat(out, ',')
end

local function World(o)
    Nexus, NexusDB, WishlistRealizerDB = nil, nil, nil
    ProjectEbonholdEchoJournal, NexusWishlistOnlyPicker = nil, nil
    NexusLoadoutAssociationPanel, NexusActiveWishlistSelector = nil, nil
    local H = dofile('tests/prototype/harness.lua')
    for i = 1, #GATED do
        local name = 'Gated Echo ' .. LETTERS[i]
        H.AddEcho(GATED[i], name, 1, 1, 0)
        H.db[GATED[i]].requiredSpell = LEVER[i]
        H.names[LEVER[i]] = 'Tome of ' .. name
        H.discovered[GATED[i]] = true
        H.disabled[GATED[i]] = true
    end
    H.perks.discoveredEchoes = H.discovered
    local function Entry(id) return {spellId=id, quality=H.db[id].quality, stacks=1} end
    for _, w in pairs(WISHLISTS) do
        local echoes = {Entry(w.ordinary)}
        for _, i in ipairs(w.tomes) do echoes[#echoes + 1] = Entry(GATED[i]) end
        H.perks.serverBuildSlots[w.slot] = {name=w.name, verified=false, echoes=echoes}
    end
    if o.destination == 'saved_build' then
        H.perks.serverActiveSlot = 1
        H.perks.serverBuildSlots[1] = {name=SAVED_BUILD, verified=true, echoes={Entry(200050)}}
    end
    H.playerLevel = o.entry == 'login1' and 1 or 80
    H.orbKnown = true
    ProjectEbonhold.OrbService = {
        IsStateKnown=function() return H.orbKnown end,
        IsOfferPending=function() return false end,
    }
    local W = {H=H, o=o, group=o.group, case=o.case, requests={}, queue={}, hold=false, step=0}
    local rawToggle = H.service.ToggleTomeEcho
    H.service.ToggleTomeEcho = function(id)
        local accepted = rawToggle(id)
        if accepted then
            W.requests[#W.requests + 1] = {id=id, step=W.step, at=H.now}
            W.queue[#W.queue + 1] = {id=id, due=H.now + REPLY_DELAY}
        end
        return accepted
    end
    H.Boot()
    W.A = Nexus.GameAdapter
    return W
end

local function Plain(text)
    return (tostring(text or ''):gsub('|c%x%x%x%x%x%x%x%x', ''):gsub('|r', ''))
end
-- RefreshAssociations is pcall-guarded, so the panel it draws is required.
local function Journal()
    if not ProjectEbonholdEchoJournal then
        CreateFrame('Frame', 'ProjectEbonholdEchoJournal', UIParent)
    end
    ProjectEbonholdEchoJournal:Show()
    Nexus.JournalTab.RefreshAssociations()
    assert(NexusLoadoutAssociationPanel and NexusLoadoutAssociationPanel:IsShown()
        and NexusActiveWishlistSelector, 'SETUP: the Journal association panel and selector are shown')
end
local function ClosePicker()
    if NexusWishlistOnlyPicker and NexusWishlistOnlyPicker:IsShown() then
        NexusActiveWishlistSelector:Click()
    end
end
local function OpenPicker()
    Journal()
    ClosePicker()
    NexusActiveWishlistSelector:Click()
    local picker = NexusWishlistOnlyPicker
    return (picker and picker:IsShown()) and picker or nil
end
local function Stored(W)
    local state = Nexus.Store.State() or {}
    if W.o.destination == 'saved_build' then
        return type(state.loadoutWishlists) == 'table' and state.loadoutWishlists[1] or nil
    end
    return state.firstRunWishlist
end

-- One real selection: the selector opens the picker, the named row is clicked.
local function Pick(W, key)
    local w = WISHLISTS[key]
    local picker = OpenPicker()
    if not picker then return false, 'the real selector opened no picker' end
    local row, names = nil, {}
    for _, candidate in ipairs(picker.children) do
        if candidate.nameButton and candidate:IsVisible() then
            local label = Plain(candidate.nameButton.text:GetText()):gsub('^%[Selected%] ', '')
            names[#names + 1] = label
            if label == w.name or label:sub(1, #w.name + 2) == w.name .. '  ' then row = candidate end
        end
    end
    if not row then
        ClosePicker()
        return false, 'no picker row for ' .. w.name .. '; selector "'
            .. Plain(NexusActiveWishlistSelector.text:GetText()) .. '" rows ['
            .. table.concat(names, ' | ') .. ']'
    end
    local heard = {}
    print = function(...)
        local parts = {}
        for i = 1, select('#', ...) do parts[#parts + 1] = tostring((select(i, ...))) end
        heard[#heard + 1] = Plain(table.concat(parts, ' '))
    end
    local ok, err = pcall(row.nameButton.Click, row.nameButton)
    print = realPrint
    if not ok then return false, 'the row click raised: ' .. tostring(err) end
    local closed = not NexusWishlistOnlyPicker:IsShown()
    ClosePicker()
    local a, stored = W.A.AssignedWishlist() or {}, Stored(W)
    local storedSlot = type(stored) == 'table' and tonumber(stored.slot) or nil
    local storedName = type(stored) == 'table' and stored.name or nil
    return closed and a.state == 'ready' and a.name == w.name
            and storedSlot == w.slot and storedName == w.name,
        string.format('clicked %s (server slot %d): picker closed=%s assigned=%s/%s stored=%s/%s%s',
            w.name, w.slot, tostring(closed), tostring(a.state), tostring(a.name),
            tostring(storedSlot), tostring(storedName),
            #heard > 0 and (' heard: ' .. table.concat(heard, ' / ')) or '')
end

-- `want` nil: settle on quiet only (an observed step).
local function Settle(W, want)
    local H = W.H
    local start, reached, seen = H.now, nil, #W.requests
    while H.now - start < SETTLE_MAX - 1e-8 do
        Run(W, TICK)
        if #W.requests ~= seen then seen, reached = #W.requests, nil end
        if reached then
            if H.now - reached >= SETTLE_QUIET - 1e-8 then break end
        elseif Quiet(W) and (want == nil or Same(Server(W), want)) then
            reached = H.now
        end
    end
    return H.now - start
end

-- One user action and its verdict. `action`: a Wishlist key (a real picker
-- click), a function returning ok, detail, or nil. `tomes`: the exact
-- enabled set expected afterwards; nil expects the server state unchanged.
local function Step(W, label, action, tomes, opts)
    opts = opts or {}
    W.step = W.step + 1
    local n = W.step
    local before = Server(W)
    local want = tomes and Vector(tomes) or before
    if opts.hold then W.hold = true end
    if type(action) == 'string' then
        record(W.group, W.case, n, label, 'PICK', Pick(W, action))
    elseif type(action) == 'function' then
        record(W.group, W.case, n, label, 'ACTION', action(W))
    end
    if opts.hold then
        Run(W, HOLD_SECONDS)
        local held, pending, unmatched = Server(W), Pending(), {}
        for i = 1, #GATED do
            local entry = pending[LEVER[i]]
            if before[i] ~= want[i] and not (type(entry) == 'table'
                and entry.want == (not want[i])) then
                unmatched[#unmatched + 1] = TOME[i]
            end
        end
        local each, sent, wrong = Sends(W, n, before, want)
        record(W.group, W.case, n, label, 'HELD-NOT-CHANGED', Same(held, before),
            'server mirror while every reply is held ' .. Show(held) .. '; before ' .. Show(before))
        record(W.group, W.case, n, label, 'HELD-ONE-REQUEST', each,
            'accepted requests while held ' .. sent .. (wrong ~= '' and ('; ' .. wrong) or ''))
        record(W.group, W.case, n, label, 'HELD-PENDING', #unmatched == 0,
            'pending ' .. PendingText() .. (#unmatched > 0
                and ('; no pending entry in the wanted direction for ' .. table.concat(unmatched, ',')) or ''))
        W.hold = false
    end
    local waited = Settle(W, not opts.observeOnly and want or nil)
    local after = Server(W)
    local exact, sent, wrong = Sends(W, n, before, want)
    if opts.observeOnly then
        realPrint('OBSERVE ' .. W.group .. ' ' .. W.case .. ' #' .. n .. ' ' .. label .. ': server '
            .. Show(after) .. ' (before ' .. Show(before) .. '); accepted requests ' .. sent
            .. '; pending ' .. PendingText())
    else
        local stale, missing = {}, {}
        for i = 1, #GATED do
            if after[i] and not want[i] then stale[#stale + 1] = TOME[i] end
            if want[i] and not after[i] then missing[#missing + 1] = TOME[i] end
        end
        record(W.group, W.case, n, label, 'TOMES', Same(after, want), 'server ' .. Show(after)
            .. '; want ' .. Show(want)
            .. (#stale > 0 and ('; still enabled ' .. table.concat(stale, ',')) or '')
            .. (#missing > 0 and ('; not enabled ' .. table.concat(missing, ',')) or ''))
        record(W.group, W.case, n, label, 'REQUESTS', exact,
            'accepted requests ' .. sent .. (wrong ~= '' and ('; ' .. wrong) or ''))
        record(W.group, W.case, n, label, 'CONFIRMED', Quiet(W),
            'pending ' .. PendingText() .. '; undelivered replies ' .. #W.queue)
    end
    realPrint(string.format('TRACE %s %s #%d %s: level=%s auto=%s tomePermission=%s assigned=%s server %s runtime %s requests %s pending %s settled=%.2fs',
        W.group, W.case, n, label, tostring(W.H.playerLevel),
        tostring(Nexus.RecomputeStats().autoEnabled), tostring(Nexus.Store.Settings().autoDisable),
        AssignedText(W), Show(after), LeverView(W), sent, PendingText(), waited))
end

local function Idle(W, label, seconds)
    W.step = W.step + 1
    local n, before = W.step, Server(W)
    Run(W, seconds)
    local none, sent = Sends(W, n, before, before)
    local after = Server(W)
    record(W.group, W.case, n, label, 'IDLE', none and Same(after, before) and Quiet(W),
        string.format('over %ss: accepted requests %s; server %s; pending %s',
            tostring(seconds), sent, Show(after), PendingText()))
end

local function Reopen(W)
    local before = AssignedText(W)
    local opened = OpenPicker() ~= nil
    ClosePicker()
    local after = AssignedText(W)
    return opened and before == after
            and not (NexusWishlistOnlyPicker and NexusWishlistOnlyPicker:IsShown()),
        'picker opened=' .. tostring(opened) .. '; assignment ' .. after .. ' (before ' .. before .. ')'
end

local function Unassign(W)
    local picker = OpenPicker()
    local clear = picker and picker.clearRow
    if not (clear and clear:IsVisible()) then
        ClosePicker()
        return false, 'the picker offers no Unassign row'
    end
    clear:Click()
    ClosePicker()
    return (W.A.AssignedWishlist() or {}).state == 'unassigned', 'after Unassign ' .. AssignedText(W)
end

local function SetPermission(value)
    local result, why = Nexus.MainInternals.StoreAuthorityOwner.UpdateSettingsV1('autoDisable', value)
    assert(result ~= nil and Nexus.Store.Settings().autoDisable == value,
        'SETUP: tome automation permission ' .. tostring(value) .. ' through the settings owner: ' .. tostring(why))
end
local function AutoOn(W)
    SlashCmdList.NEXUS('auto'); Run(W, .4)
    assert(Nexus.RecomputeStats().autoEnabled == true, 'SETUP: /nexus auto turns Auto ON')
end

local function Enter(W)
    local o, H, A = W.o, W.H, W.A
    if o.tomePermission == false then SetPermission(false) end
    if o.auto then AutoOn(W) end
    if o.entry == 'reset' then
        H.playerLevel = 1; H.Fire('PLAYER_LEVEL_UP', 1); H.Notify()
    end
    Run(W, 2)
    assert(H.playerLevel == 1, 'SETUP: level 1')
    assert(A.DiscoverySynced() == true, 'SETUP: discovery mirror synced')
    assert(A.TomeMutationPaused() == false, 'SETUP: no Tome of Echo mutation hold')
    assert(A.OrdinaryBoardAllowed() == true, 'SETUP: ordinary gate open')
    assert(Nexus.RecomputeStats().autoEnabled == (o.auto == true), 'SETUP: Auto is ' .. tostring(o.auto == true))
    assert(Nexus.Store.Settings().autoDisable == (o.tomePermission ~= false),
        'SETUP: tome automation permission is ' .. tostring(o.tomePermission ~= false))
    local catalog = A.Catalog()
    for i = 1, #GATED do
        local lever = catalog and catalog.levers and catalog.levers[LEVER[i]]
        assert(lever and lever.conformant == true and A.LeverHasKnownMember(LEVER[i]) == true,
            'SETUP: ' .. TOME[i] .. ' is a conformant, discovered tome lever')
    end
    assert((A.AssignedWishlist() or {}).state == 'unassigned',
        'SETUP: no Wishlist is assigned before the first selection: ' .. AssignedText(W))
    local server = Server(W)
    record(W.group, W.case, 0, 'before any selection', 'PRE', #W.requests == 0 and Same(server, Vector({})),
        'no tome request without a Wishlist; server ' .. Show(server) .. '; requests ' .. #W.requests)
end

local function NoBuildWrites(W)
    W.step = W.step + 1
    local n = 0
    for _, action in ipairs(W.H.actions) do
        if action[1] == 'upload' or action[1] == 'save' or action[1] == 'activate' then n = n + 1 end
    end
    record(W.group, W.case, W.step, 'whole case', 'NO-BUILD-WRITES', n == 0,
        'selections upload, save or activate no build: ' .. n)
end

local function Sequence(W)
    Enter(W)
    Step(W, 'first selection A', 'A', WISHLISTS.A.tomes)
    Step(W, 'second selection B', 'B', WISHLISTS.B.tomes)
    Step(W, 'third selection C', 'C', WISHLISTS.C.tomes)
    Step(W, 'back to A', 'A', WISHLISTS.A.tomes)
    Step(W, 'D: the tome set of A in another Wishlist', 'D', WISHLISTS.D.tomes)
    Step(W, 'B again', 'B', WISHLISTS.B.tomes)
    Step(W, 'C again, server replies held then released', 'C', WISHLISTS.C.tomes, {hold=true})
    Step(W, 'A again', 'A', WISHLISTS.A.tomes)
    Step(W, 'reopen the picker and choose nothing', Reopen, nil)
    Step(W, 'Unassign', Unassign, nil, {observeOnly=true})
    Step(W, 'select A again after Unassign', 'A', WISHLISTS.A.tomes)
    Idle(W, 'idle after the sequence', IDLE_SECONDS)
    -- Exact level-one eligibility: at level 2 a selection still changes the
    -- assignment, and no tome request follows.
    Step(W, 'advance to level 2', function(W)
        W.H.playerLevel = 2; W.H.Fire('PLAYER_LEVEL_UP', 2)
        return true, 'level ' .. tostring(W.H.playerLevel)
    end, nil)
    Step(W, 'level 2: select B', 'B', nil)
    W.step = W.step + 1
    local requests = #W.requests
    local ok, why = W.A.ToggleLever(LEVER[3], false)
    record(W.group, W.case, W.step, 'adapter at level 2', 'LEVEL2-ADAPTER',
        ok == false and why == 'not level 1' and #W.requests == requests,
        'ToggleLever(' .. TOME[3] .. ', enable) at level 2: ' .. tostring(ok) .. ', ' .. tostring(why))
end

local function Guarded(W)
    Enter(W)
    Step(W, 'first selection A', 'A', nil)
    Step(W, 'second selection B', 'B', nil)
    Step(W, 'third selection C', 'C', nil)
    Step(W, 'back to A', 'A', nil)
    Idle(W, 'idle with the permission withheld', IDLE_SECONDS)
    -- Control: grant only what this case withheld; the same Journal route
    -- then mutates, so the silence above was the permission, not the fixture.
    Step(W, 'grant the withheld permission', function(W)
        if W.o.tomePermission == false then SetPermission(true) end
        if not W.o.auto then AutoOn(W) end
        local auto, tome = Nexus.RecomputeStats().autoEnabled, Nexus.Store.Settings().autoDisable
        return auto == true and tome == true, 'Auto=' .. tostring(auto) .. ' tomePermission=' .. tostring(tome)
    end, nil, {observeOnly=true})
    Step(W, 'control: select B with the permission granted', 'B', WISHLISTS.B.tomes)
end

local function Target(W, label, key)
    local w = WISHLISTS[key]
    local a = W.A.AssignedWishlist() or {}
    Journal()
    local journalLabel = Plain(NexusLoadoutAssociationPanel.label:GetText())
    record(W.group, W.case, W.step, label, 'NATIVE-TARGET',
        a.state == 'ready' and a.name == w.name and journalLabel:find(SAVED_BUILD, 1, true) ~= nil,
        'Nexus target ' .. AssignedText(W) .. ', Journal "' .. journalLabel .. '"; contract: '
            .. w.name .. ', the association of ' .. SAVED_BUILD)
end

local function Native(W)
    Enter(W)
    Step(W, 'Journal selection A', 'A', WISHLISTS.A.tomes)
    Step(W, 'native activation of the Wishlist B mirror', function(W)
        W.H.perks.serverActiveSlot = WISHLISTS.B.slot; W.H.Notify()
        return true, 'native active slot ' .. tostring(W.A.Slots().activeSlot)
    end, nil)
    Target(W, 'native Wishlist active', 'A')
    Step(W, 'Journal selection C while a Wishlist is natively active', 'C', WISHLISTS.C.tomes)
    Step(W, 'native activation back to the Saved Build', function(W)
        W.H.perks.serverActiveSlot = 1; W.H.Notify()
        return true, 'native active slot ' .. tostring(W.A.Slots().activeSlot)
    end, nil)
    Target(W, 'Saved Build natively active again', 'C')
end

local function Case(group, case, o, body)
    o.group, o.case = group, case
    realPrint('CASE ' .. group .. ' ' .. case)
    local ok, err = pcall(function()
        local W = World(o)
        body(W)
        NoBuildWrites(W)
    end)
    print = realPrint
    if not ok then record(group, case, 0, 'case', 'STAGE', false, 'did not complete: ' .. tostring(err)) end
end

for _, destination in ipairs({'first_run', 'saved_build'}) do
    for _, entry in ipairs({'reset', 'login1'}) do
        Case('SEQ', destination .. '/' .. entry,
            {destination=destination, entry=entry, auto=true, tomePermission=true}, Sequence)
    end
end
for _, destination in ipairs({'first_run', 'saved_build'}) do
    for _, g in ipairs({{false, true}, {true, false}, {false, false}}) do
        Case('GUARD', destination .. '/auto-' .. (g[1] and 'on' or 'off') .. '/tome-' .. (g[2] and 'on' or 'off'),
            {destination=destination, entry='reset', auto=g[1], tomePermission=g[2]}, Guarded)
    end
end
Case('NATIVE', 'saved_build/reset',
    {destination='saved_build', entry='reset', auto=true, tomePermission=true}, Native)

-- Per case, each step's verdict in order: a first selection that succeeded
-- stays visible beside a later one that did not.
local order, cases, missed = {}, {}, {}
for _, r in ipairs(results) do
    local key = r.group .. ' ' .. r.case
    local c = cases[key]
    if not c then
        c = {ok=0, miss=0, steps={}, stepOrder={}}
        cases[key] = c; order[#order + 1] = key
    end
    local s = c.steps[r.step]
    if not s then
        s = {misses={}}; c.steps[r.step] = s; c.stepOrder[#c.stepOrder + 1] = r.step
    end
    if r.ok then c.ok = c.ok + 1
    else
        c.miss = c.miss + 1; s.misses[#s.misses + 1] = r.check
        missed[#missed + 1] = key .. ' #' .. tostring(r.step) .. ' ' .. r.check .. ' (' .. r.label .. ')'
    end
end
for _, key in ipairs(order) do
    local c, parts = cases[key], {}
    for _, step in ipairs(c.stepOrder) do
        local s = c.steps[step]
        parts[#parts + 1] = tostring(step) .. '=' .. (#s.misses == 0 and 'ok'
            or ('MISS:' .. table.concat(s.misses, '+')))
    end
    realPrint('SUMMARY ' .. key .. ' ok=' .. c.ok .. ' miss=' .. c.miss .. ' steps ' .. table.concat(parts, ' '))
end
if #missed > 0 then
    error('FAIL native_wishlist_tome_sequence: ' .. #missed .. ' expectation(s) not met:\n'
        .. table.concat(missed, '\n'), 0)
end
realPrint('PASS native_wishlist_tome_sequence: each level-1 Journal selection (A -> B -> C -> A ...) '
    .. 'leaves exactly its tomes enabled and the rest disabled on the synthetic server, one confirmed '
    .. 'request per changed tome; Auto OFF, tome permission OFF and level 2 send none; native Wishlist '
    .. 'activation keeps the Saved Build association; checks=' .. #results)
