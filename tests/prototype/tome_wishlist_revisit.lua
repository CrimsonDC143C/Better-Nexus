-- Level-one Wishlist changes reconcile conformant tome levers through the real
-- runtime and assignment facades. A disable -> enable -> disable in one visit
-- must not be suppressed by the first successful disable's visit marker.
-- Synthetic APIs only; no native client or private player data.
local checks, failures = 0, {}
local function check(value, message) assert(value, message); checks = checks + 1 end
local function expect(value, message)
    checks = checks + 1
    if not value then failures[#failures + 1] = message end
end
local function count(H)
    local n = 0
    for _, action in ipairs(H.actions) do if action[1] == 'toggle' then n = n + 1 end end
    return n
end
local ECHO, LEVER = 300001, 777001
local function fixture(route, enabled)
    Nexus, NexusDB, WishlistRealizerDB = nil, nil, nil
    local H = dofile('tests/prototype/harness.lua')
    H.names[LEVER] = 'Tome of Gated Echo'
    H.AddEcho(ECHO, 'Gated Echo', 1, 1, 0)
    H.db[ECHO].requiredSpell = LEVER
    H.discovered[ECHO] = true
    H.perks.discoveredEchoes = H.discovered
    H.disabled[ECHO] = not enabled
    H.playerLevel = 80
    local need = {{spellId=ECHO, quality=1, stacks=1}}
    local other = {{spellId=200001, quality=1, stacks=1}}
    if route == 'active_saved' then
        H.perks.serverActiveSlot = 1
        H.perks.serverBuildSlots[1] = {name='Active Saved Build', verified=true, echoes=other}
    end
    H.orbKnown = true
    ProjectEbonhold.OrbService = {
        IsStateKnown=function() return H.orbKnown end,
        IsOfferPending=function() return false end,
    }
    -- The shared harness records requests. This fixture supplies a successful
    -- server mirror, or holds it to exercise real pending-confirmation guards.
    local rawToggle = H.service.ToggleTomeEcho
    H.service.ToggleTomeEcho = function(id)
        local result = rawToggle(id)
        local desired = not H.disabled[id]
        if H.holdTomeMirror then H.heldTomeMirror = desired
        else H.disabled[id] = desired; H.Notify() end
        return result
    end
    H.Boot()
    local A = Nexus.GameAdapter
    local function assign(wanted)
        local name = wanted and 'Needs gated' or 'Excludes gated'
        local echoes = wanted and need or other
        local ok, why
        if route == 'active_saved' then ok, why = A.SetLoadoutWishlistIdentity(1, name, echoes, {})
        else ok, why = A.SetFirstLoadoutWishlistIdentity(name, echoes) end
        check(ok == true, route..' assignment: '..tostring(why))
        H.Notify()
    end
    local function autoOn()
        SlashCmdList.NEXUS('auto'); H.Advance(.4, .05)
        check(Nexus.Panel._lastModel.auto == true, route..' Auto ON')
    end
    local function reset()
        H.playerLevel = 1; H.Fire('PLAYER_LEVEL_UP', 1); H.Notify()
    end
    local function settle()
        H.Advance(4, .05)
        check(A.DiscoverySynced() == true, route..' discovery synced')
        check(A.TomeMutationPaused() == false, route..' no tome hold')
        check(A.OrdinaryBoardAllowed() == true, route..' ordinary gate open')
        check(Nexus.Store.Settings().autoDisable == true, route..' tome automation permission')
    end
    local function pending() return Nexus.Store.State().tomeTogglePending[LEVER] end
    local function trace(label)
        local p = pending()
        print(string.format('TRACE %s %s level=%d sends=%d disabled=%s pending=%s',
            route, label, H.playerLevel, count(H), tostring(H.disabled[ECHO]),
            p and tostring(p.want) or 'none'))
    end
    assign(false)
    return H, A, assign, autoOn, reset, settle, pending, trace
end

for _, route in ipairs({'first_run', 'active_saved'}) do
    -- Exact simple sequence, including an edit before the reset's first poll.
    local H, A, assign, autoOn, reset, settle, pending = fixture(route, false)
    autoOn(); reset(); assign(true); settle()
    check(H.playerLevel == 1 and H.disabled[ECHO] == false and count(H) == 1,
        route..' reset then changed Wishlist restores required tome at level1')
    check(pending() == nil, route..' required enable is confirmed')

    -- Auto OFF is a permission boundary even with a ready level-one assignment.
    H, A, assign, autoOn, reset, settle, pending = fixture(route, false)
    reset(); assign(true); settle()
    check(Nexus.Panel._lastModel.auto == false and count(H) == 0 and H.disabled[ECHO] == true,
        route..' Auto OFF sends no tome mutation')
    check(pending() == nil, route..' Auto OFF creates no pending toggle')

    -- Exact level-one eligibility is intentional; a later open gate cannot
    -- authorize a toggle after the character already advanced to level two.
    H, A, assign, autoOn, reset, settle = fixture(route, false)
    autoOn(); reset(); H.orbKnown = false; assign(true); H.Advance(1, .05)
    check(count(H) == 0 and H.disabled[ECHO] == true, route..' closed Orb gate sends nothing')
    H.playerLevel = 2; H.Fire('PLAYER_LEVEL_UP', 2); H.orbKnown = true; settle()
    check(count(H) == 0 and H.disabled[ECHO] == true, route..' level2 sends no tome mutation')
    local ok, why = A.ToggleLever(LEVER, false)
    check(ok == false and why == 'not level 1', route..' adapter enforces exact level1')

    -- End-to-end reset and two switches, with every mirror confirmed. The
    -- final Wishlist is current but the old visit marker used to skip its work.
    local trace
    H, A, assign, autoOn, reset, settle, pending, trace = fixture(route, true)
    autoOn(); reset(); settle()
    check(count(H) == 1 and H.disabled[ECHO] == true and pending() == nil,
        route..' first unwanted disable confirmed')
    assign(true); settle()
    check(count(H) == 2 and H.disabled[ECHO] == false and pending() == nil,
        route..' required re-enable confirmed')
    assign(false); settle(); trace('revisited')
    expect(count(H) == 3 and H.disabled[ECHO] == true and pending() == nil,
        route..': re-enabled unwanted tome must be disabled again during the same level1 visit')

    -- A successful enable may still await its mirror when the Wishlist changes
    -- back. Its pending record must block overlap; the final disable follows
    -- only after that enable confirms, without a duplicate accepted request.
    H, A, assign, autoOn, reset, settle, pending, trace = fixture(route, true)
    autoOn(); reset(); settle()
    check(count(H) == 1 and H.disabled[ECHO] == true, route..' pending fixture starts disabled')
    H.holdTomeMirror = true; assign(true); H.Advance(1, .05)
    check(count(H) == 2 and pending() and pending().want == false and H.disabled[ECHO] == true,
        route..' accepted enable awaits server mirror')
    assign(false); H.Advance(1, .05)
    check(count(H) == 2 and pending() and pending().want == false,
        route..' pending enable blocks overlapping toggle')
    H.holdTomeMirror = false; H.disabled[ECHO] = H.heldTomeMirror; H.Notify(); settle(); trace('pending-revisited')
    expect(count(H) == 3 and H.disabled[ECHO] == true and pending() == nil,
        route..': current unwanted disable must follow confirmation of the earlier accepted enable')
end
assert(#failures == 0, table.concat(failures, '\n'))
print('PASS level1 tome Wishlist revisit and permission guards checks='..checks)
