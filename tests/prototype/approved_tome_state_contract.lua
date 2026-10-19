local ARGV = rawget(_G, 'arg')
-- Approved tome/Wishlist coverage lane, stage 02: runtime/adapter contract
-- cases SC-1..SC-7 through public runtime, adapter, provider and HUD seams.
-- Every case boots its own real TOC fixture (approved_tome_coverage_support).
-- All data is synthetic harness data; offline results support no native
-- client, UI, performance or stutter claim.
-- Run from the source root: luajit tests/prototype/approved_tome_state_contract.lua [SC-1,SC-5]
local S = dofile('tests/prototype/approved_tome_coverage_support.lua')
local K = S.Checker('approved_tome_state_contract')
local function Auto() return Nexus.RecomputeStats().autoEnabled == true end
local function Steps() return Nexus.RecomputeStats().fullSteps or 0 end
local function Trace(id, H)
    local parts = {}
    for i, t in ipairs(H.trace or {}) do parts[i] = string.format('%d@%.2f', t.id, t.at - (H.resetAt or 0)) end
    print(string.format('TRACE %s level=%d sends=%d [%s]', id, H.playerLevel, #(H.trace or {}), table.concat(parts, ' ')))
end

-- SC-1 (D1): lock-design ("locked") target tomes versus undiscovered tomes.
local function SC1(c)
    local R, U = S.Lever(1, 'Wished Echo', true, true), S.Lever(2, 'Unseen Wished Echo', false, false)
    local K1, K2 = S.Lever(3, 'Locked Echo', true, true), S.Lever(4, 'Unseen Locked Echo', false, false)
    local X = S.Lever(5, 'Spare Echo', true, false)
    local H, A = S.Fixture({levers={R, U, K1, K2, X}})
    c(S.Assign(H, A, 'Locked plan', {R, U}, {[K1.echo]=true, [K2.echo]=true}),
        'SC-1 reached: the Wishlist with two locked targets is assigned')
    local data = S.CaptureProvider(H)()
    local k1, x = S.Entries(data, K1.tome)[1], S.Entries(data, X.tome)[1]
    c(k1 and tostring(k1.plan):find('keep enabled', 1, true) and x and tostring(x.plan):find('plan: disable', 1, true),
        'SC-1 reached: provider plan keeps the locked target tome')
    Nexus.RequestRecompute(); H.Advance(.5, .05); Nexus.Panel.Refresh()
    local m = Nexus.Panel._lastModel
    local pr = type(m) == 'table' and type(m.progress) == 'table' and m.progress or {}
    local list = type(pr.unknownTomes) == 'table' and pr.unknownTomes or {}
    local missing = {}
    for _, name in ipairs(list) do missing[name] = true end
    c(pr.wishlistName == 'Locked plan', 'SC-1 reached: the HUD model shows the assigned Wishlist')
    c(missing[U.tome] and missing[K2.tome],
        'SC-1 HUD Missing Tomes lists the undiscovered Wishlist and locked-target tomes')
    c(#list == 2 and not missing[R.tome] and not missing[K1.tome] and not missing[X.tome],
        'SC-1 disabled known tomes are not Missing Tomes')
    local autoOn = S.AutoOn(H)
    S.ResetToLevel1(H)
    c(autoOn and H.playerLevel == 1, 'SC-1 reached: Auto and tome permission ON at level 1')
    S.Within(H, 4, function() return #H.trace >= 3 end); H.Advance(2, .05)
    c(S.Toggles(H, R.echo) == 1 and H.disabled[R.echo] == false, 'SC-1 reached: the ordinary Wishlist tome was restored')
    c(S.Toggles(H, K1.echo) == 1 and H.disabled[K1.echo] == false, 'SC-1 locked target tome is restored at level 1')
    local firstPrune, lastRestore = nil, 0
    for i, t in ipairs(H.trace) do
        if t.id == X.echo and not firstPrune then firstPrune = i end
        if t.id == R.echo or t.id == K1.echo then lastRestore = i end
    end
    c(firstPrune ~= nil and lastRestore > 0 and lastRestore < firstPrune, 'SC-1 every restore precedes the first prune')
    c(S.Toggles(H, U.echo) == 0 and S.Toggles(H, K2.echo) == 0,
        'SC-1 undiscovered Wishlist and locked-target tomes are never toggled')
    c(#H.trace == 3 and next(S.Pending()) == nil and H.disabled[X.echo] == true,
        'SC-1 converged: three sends, no pending request')
    Trace('SC-1', H)
end

-- SC-2 (D1): stable repeat and a player re-enable against the once-per-visit mark.
local function SC2(c)
    local W = S.Lever(1, 'Kept Echo', true, false)
    local X1, X2 = S.Lever(2, 'First Spare Echo', true, false), S.Lever(3, 'Second Spare Echo', true, false)
    local H, A = S.Fixture({levers={W, X1, X2}})
    c(S.Assign(H, A, 'Kept plan', {W}), 'SC-2 reached: the Wishlist is assigned')
    c(S.AutoOn(H), 'SC-2 reached: Auto and tome permission ON')
    S.ResetToLevel1(H)
    S.Within(H, 4, function() return S.Toggles(H, X1.echo) >= 1 and S.Toggles(H, X2.echo) >= 1 end)
    H.Advance(1, .05)
    c(S.Toggles(H, X1.echo) == 1 and S.Toggles(H, X2.echo) == 1 and H.disabled[X1.echo] == true
        and H.disabled[X2.echo] == true, 'SC-2 reached: both off-Wishlist tomes pruned once')
    local sends, polls, steps = #H.trace, Nexus.RecomputeStats().polls or 0, Steps()
    H.Advance(20, .1); Nexus.RequestRecompute(); H.Advance(20, .1)
    c((Nexus.RecomputeStats().polls or 0) - polls >= 100 and Steps() > steps,
        'SC-2 reached: the runtime kept polling and stepped during the 40 s idle')
    c(#H.trace == sends, 'SC-2 a converged level-1 visit sends nothing more over 40 s')
    local generation = A.EchoReconcileStats().generations.discovery or 0
    steps = Steps()
    -- Synthetic player action: the client mirror shows X1 enabled again.
    H.disabled[X1.echo] = false; H.Notify(); H.Advance(6, .05)
    c((A.EchoReconcileStats().generations.discovery or 0) > generation and Steps() > steps,
        'SC-2 reached: the player re-enable changed the observed mirror generation and the runtime stepped')
    c(S.Toggles(H, X1.echo) == 1 and H.disabled[X1.echo] == false,
        'SC-2 a player re-enable of a pruned tome is not re-disabled within the same level-1 visit')
    -- The player keeps X1 enabled into the next visit (a no-op unless it was re-disabled).
    H.disabled[X1.echo] = false
    local before, boundary = S.Toggles(H, X1.echo), A.LevelBurstStats().runBoundaryGeneration or 0
    S.NewVisit(H)
    S.Within(H, 4, function() return S.Toggles(H, X1.echo) > before end); H.Advance(1, .05)
    c((A.LevelBurstStats().runBoundaryGeneration or 0) > boundary, 'SC-2 reached: a run boundary started a new level-1 visit')
    c(S.Toggles(H, X1.echo) - before == 1 and H.disabled[X1.echo] == true and S.Toggles(H, X2.echo) == 1,
        'SC-2 a new level-1 visit prunes the re-enabled tome again exactly once')
    c(S.Toggles(H, W.echo) == 0, 'SC-2 the kept Wishlist tome is never toggled')
    Trace('SC-2', H)
end

-- SC-3 (D2): stale and missing reads in the real JournalData provider.
local function SC3(c)
    local E, D = S.Lever(1, 'Open Echo', true, false), S.Lever(2, 'Closed Echo', true, true)
    local H, A = S.Fixture({levers={E, D}})
    local provider = S.CaptureProvider(H)
    local function Status(data, l) local e = S.Entries(data, l.tome)[1]; return e and e.status, e end
    local function Claims(data, l, word)
        for _, e in ipairs(S.Entries(data, l.tome)) do
            if tostring(e.status):find(word, 1, true) == 1 then return true end
        end
        return false
    end
    local fresh = provider()
    c(Status(fresh, E) == 'Enabled' and Status(fresh, D) == 'Disabled',
        'SC-3 control: a fresh mirror lists the enabled tome as Enabled and the disabled tome as Disabled')
    local owner = Nexus.MainInternals.StoreAuthorityOwner
    local writes, update = 0, owner.UpdateStateV1
    owner.UpdateStateV1 = function(...) writes = writes + 1; return update(...) end
    local actions, sent = #H.actions, #H.sent
    -- Synthetic: the client's discovery mirror is not synced (GameAdapter.lua:3543-3546).
    H.perks.discoveredEchoes = nil
    local synced = A.DiscoverySynced()
    local unsynced = provider()
    H.perks.discoveredEchoes = H.discovered
    local es, ee = Status(unsynced, E)
    local ds = Status(unsynced, D)
    c(synced == false and ee ~= nil and ds ~= nil, 'SC-3 reached: the provider read both tomes with discovery unsynced')
    c(ee ~= nil and not Claims(unsynced, E, 'Enabled'), 'SC-3 unsynced discovery never lists a mirror-enabled tome as Enabled')
    c(es == 'Unknown (stale)' and tostring(ee and ee.reason):find('discovery state unavailable', 1, true),
        'SC-3 unsynced discovery shows the enabled tome as Unknown (stale) with the discovery reason')
    c(ds == 'Disabled (stale)', 'SC-3 a stale disabled observation is marked (stale)')
    c(table.concat(S.Lines(unsynced), '\n'):find('discovery mirror is unsynced', 1, true),
        'SC-3 coverage names the unsynced discovery mirror')
    -- Synthetic refused member read (pattern of tome_state_observation.lua:39).
    local raw = H.service.IsTomeEchoDisabled
    H.service.IsTomeEchoDisabled = function(id) if id == D.echo then return nil end; return raw(id) end
    local refused = provider()
    H.service.IsTomeEchoDisabled = raw
    c(Status(refused, E) == 'Enabled', 'SC-3 reached: with one refused member read the other tome still reads Enabled')
    c(Status(refused, D) == 'Unknown' and not Claims(refused, D, 'Disabled'),
        'SC-3 a refused member read is Unknown, not Disabled')
    owner.UpdateStateV1 = update
    c(writes == 0 and #H.actions == actions and #H.sent == sent, 'SC-3 reading the provider wrote nothing and sent nothing')
end

-- SC-4 (D2): the overwrite warning on the level-1 tome path (composition guard).
local function SC4(c)
    local R = S.Lever(1, 'Guarded Echo', true, true)
    local H, A = S.Fixture({levers={R}, keepPrompts=true})
    local f = rawget(_G, 'NexusOverwriteWarning')
    if not (f and f:IsShown()) then SlashCmdList.NEXUS('auto'); f = rawget(_G, 'NexusOverwriteWarning') end
    H.Advance(5.01, .05)
    if f and f:IsShown() and f.yes:IsEnabled() then f.yes:Click() end
    local quick = rawget(_G, 'NexusQuickStart')
    if quick and quick:IsShown() then quick:Hide(); H.Advance(.2, .05) end
    c(Nexus.OverwriteWarning.EnsureOnboarding() ~= 'pending' and not Auto(),
        'SC-4 reached: the onboarding warning was answered and Auto stays OFF')
    c(S.Assign(H, A, 'Guarded plan', {R}), 'SC-4 reached: the Wishlist is assigned')
    S.ResetToLevel1(H); H.Advance(1, .05)
    SlashCmdList.NEXUS('auto'); f = rawget(_G, 'NexusOverwriteWarning')
    c(f and f:IsShown() and f.yes:IsEnabled() and not Auto() and H.playerLevel == 1 and #H.trace == 0,
        'SC-4 reached: the Auto warning is open and Auto is OFF at level 1')
    H.Advance(4, .05)
    c(#H.trace == 0 and next(S.Pending()) == nil and H.disabled[R.echo] == true,
        'SC-4 an unanswered Auto warning authorizes no tome restore or request')
    H.Fire('PLAYER_LEAVING_WORLD')
    local closed = f and not f:IsShown()
    local stale = f and f.yes:GetScript('OnClick')
    if stale then stale(f.yes) end -- a Yes handler left over from the cancelled request
    H.Advance(2, .05); H.Fire('PLAYER_ENTERING_WORLD'); H.Advance(4, .05)
    c(closed and not Auto() and #H.trace == 0 and H.disabled[R.echo] == true,
        'SC-4 a world interruption cancels the warning and still sends nothing')
    SlashCmdList.NEXUS('auto'); f = rawget(_G, 'NexusOverwriteWarning')
    if f and f:IsShown() and f.yes:IsEnabled() then f.yes:Click() end
    S.Within(H, 3, function() return #H.trace >= 1 end); H.Advance(1.5, .05)
    c(Auto(), 'SC-4 reached: Yes turned Auto ON')
    c(#H.trace == 1 and H.trace[1].id == R.echo and H.disabled[R.echo] == false,
        'SC-4 Yes authorizes exactly one required restore')
    Trace('SC-4', H)
end

-- SC-5 (D2, D3): a known-lever pending request across an offline module reload,
-- and a previous-boot record expiring in the restarted 3.5 s window.
local function SC5(c)
    local R, P = S.Lever(1, 'Requested Echo', true, true), S.Lever(2, 'Second Requested Echo', true, false)
    local levers = {R, P}
    local H, A = S.Fixture({levers=levers, holdMirror=true})
    c(S.Assign(H, A, 'Reload plan', levers), 'SC-5 reached: the Wishlist is assigned')
    c(S.AutoOn(H), 'SC-5 reached: Auto and tome permission ON')
    S.ResetToLevel1(H)
    S.Within(H, 2, function() return #H.trace >= 1 end); H.Advance(.5, .05)
    local p = S.Pending()[R.lever]
    c(#H.trace == 1 and H.trace[1].id == R.echo and type(p) == 'table' and p.want == false and H.disabled[R.echo] == true,
        'SC-5 reached: a level-1 enable request is pending before reload')
    Trace('SC-5', H)
    local H2, A2 = S.Reload({levers=levers, level=1, holdMirror=true})
    H2.Advance(1, .05)
    p = S.Pending()[R.lever]
    c(H2.playerLevel == 1 and H2.disabled[R.echo] == true, 'SC-5 reached: the reload booted at level 1 with the mirror still held')
    c(type(p) == 'table' and p.want == false, 'SC-5 the pending request survives the offline reload')
    c(not Auto() and #H2.trace == 0, 'SC-5 reload leaves Auto OFF and sends nothing')
    local rows = S.Entries(S.CaptureProvider(H2)(), R.tome)
    c(rows[1] and tostring(rows[1].plan):find('keep enabled', 1, true),
        'SC-5 reached: the reloaded Wishlist keeps the requested tome in the plan')
    c(#rows == 2 and tostring(rows[1].status):find('Disabled', 1, true) == 1 and rows[1].pending == 'enable',
        'SC-5 the reloaded provider lists the request apart from the Disabled observation')
    local steps = Steps()
    c(S.AutoOn(H2) and H2.playerLevel == 1, 'SC-5 reached: Auto is ON again at level 1 after the reload')
    -- CaptureProvider (+1 s) and AutoOn (+0.4 s) already consumed part of the
    -- 3.5 s pending window after Reload; keep this advance short.
    H2.Advance(.5, .05)
    p = S.Pending()[R.lever]
    c(Steps() > steps, 'SC-5 reached: the runtime stepped after Auto ON')
    c(#H2.trace == 0 and type(p) == 'table' and p.want == false,
        'SC-5 a reloaded pending request blocks a duplicate enable after Auto ON')
    local wasPending = type(p) == 'table'
    -- Synthetic server mirror: the held enable is now reflected.
    H2.holdMirror = false; H2.disabled[R.echo] = false; H2.Notify()
    local at = S.Within(H2, 2, function() return S.Pending()[R.lever] == nil end)
    H2.Advance(.5, .05)
    c(wasPending and at ~= nil and #H2.trace == 0 and H2.disabled[R.echo] == false,
        'SC-5 the reloaded request is cleared only by its mirror confirmation')
    SlashCmdList.NEXUS('auto'); H2.Advance(.2, .05)
    H2.holdMirror = true
    local okP = A2.ToggleLever(P.lever, true)
    p = S.Pending()[P.lever]
    c(not Auto() and okP == true and type(p) == 'table' and p.want == true,
        'SC-5 reached: Auto is OFF and a disable request is pending for the second tome')
    -- Synthetic: the saved request carries a timestamp from a previous boot whose
    -- clock ran far ahead (GameAdapter.lua:3780-3783). It is Nexus saved data
    -- written through the Store owner, not native client state.
    Nexus.MainInternals.StoreAuthorityOwner.UpdateStateV1(function(st)
        local q = type(st.tomeTogglePending) == 'table' and st.tomeTogglePending[P.lever]
        if type(q) == 'table' then q.t = GetTime() + 5000 end
    end)
    local H3, A3 = S.Reload({levers=levers, level=1, holdMirror=true, disabled={[R.echo]=false, [P.echo]=false}})
    p = S.Pending()[P.lever]
    -- harness.lua:2 starts every boot's clock at 1000, so the restarted window ends after 1003.5.
    c(type(p) == 'table' and p.want == true and not Auto() and H3.now < 1003.5,
        'SC-5 reached: a future-dated pending record from a previous boot survives reload')
    local cleared = S.Within(H3, 5, function() return S.Pending()[P.lever] == nil end)
    c(cleared ~= nil and H3.now > 1003.5, 'SC-5 a previous-boot request expires within the restarted 3.5 s window')
    local row
    for _, r in ipairs(A3.TomeStateObservation().rows) do if r.lever == P.lever then row = r end end
    c(row and row.observed == 'enabled' and A3.DisabledLevers()[P.lever] ~= 'confirmed' and #H3.trace == 0,
        'SC-5 the expired request left no confirmation claim and no resend')
    print(string.format('TRACE SC-5 reload clock=%.2f expiry after %.2f s', H3.now, cleared or -1))
end

-- SC-6 (D3, D1): loading screen and settle hold level-1 tome mutation; an
-- unclassified world entry revokes Auto (automation_world_transition.lua:110-124,143).
local function SC6(c)
    local R, X = S.Lever(1, 'Transit Echo', true, true), S.Lever(2, 'Transit Spare Echo', true, false)
    local H, A = S.Fixture({levers={R, X}})
    c(S.Assign(H, A, 'Transit plan', {R}), 'SC-6 reached: the Wishlist is assigned')
    S.ResetToLevel1(H); H.Advance(2, .05)
    c(H.playerLevel == 1 and not Auto() and #H.trace == 0, 'SC-6 reached: level 1 with Auto OFF sends nothing')
    H.Fire('PLAYER_LEAVING_WORLD')
    local steps = Steps()
    SlashCmdList.NEXUS('auto'); H.Advance(3, .05)
    c(Auto() and Steps() > steps, 'SC-6 reached: the runtime stepped at level 1 during the loading screen')
    c(#H.trace == 0, 'SC-6 the loading screen holds the level-1 tome restore')
    local entryAt, before = H.now, #H.trace
    H.Fire('PLAYER_ENTERING_WORLD'); H.Advance(2.5, .05)
    c(Auto(), 'SC-6 reached: the closing world entry keeps Auto ON')
    c(#H.trace - before == 0, 'SC-6 the settle window holds the level-1 tome restore')
    local at = S.Within(H, 2, function() return #H.trace > before end)
    local first = H.trace[1]
    c(at ~= nil and first ~= nil and first.id == R.echo and first.at >= entryAt + 3 - 1e-6 and S.Toggles(H, R.echo) == 1,
        'SC-6 after the settle the required tome is restored first, exactly once')
    local pruned = S.Toggles(H, X.echo)
    H.Fire('PLAYER_ENTERING_WORLD') -- an entry with no observed leave
    local revoked = not Auto()
    H.Advance(3, .05)
    c(revoked and pruned == 0 and S.Toggles(H, X.echo) == 0,
        'SC-6 an unclassified world entry revokes Auto before the next prune')
    SlashCmdList.NEXUS('auto')
    S.Within(H, 2, function() return S.Toggles(H, X.echo) >= 1 end); H.Advance(1, .05)
    c(S.Toggles(H, X.echo) == 1 and S.Toggles(H, R.echo) == 1 and H.disabled[X.echo] == true,
        'SC-6 control: Auto ON again resumes the prune')
    Trace('SC-6', H)
end

-- SC-7 (D3, D1): unassigning the Wishlist at level 1 (advisor mode) stops pruning.
local function SC7(c)
    local R = S.Lever(1, 'Anchor Echo', true, false)
    local X1, X2 = S.Lever(2, 'Spare Echo One', true, false), S.Lever(3, 'Spare Echo Two', true, false)
    local X3 = S.Lever(4, 'Spare Echo Three', true, false)
    local H, A = S.Fixture({levers={R, X1, X2, X3}})
    c(S.Assign(H, A, 'Anchor plan', {R}), 'SC-7 reached: the Wishlist is assigned')
    c(S.AutoOn(H), 'SC-7 reached: Auto and tome permission ON')
    S.ResetToLevel1(H)
    S.Within(H, 2, function() return #H.trace >= 1 end)
    c(#H.trace == 1 and H.trace[1].id == X1.echo, 'SC-7 reached: the first prune was sent with the Wishlist assigned')
    local ok = A.ClearFirstRunWishlist(); H.Notify()
    local sends, steps = #H.trace, Steps()
    H.Advance(4, .05)
    c(ok == true and A.Wishlist() == nil and Steps() > steps,
        'SC-7 reached: the Wishlist is unassigned and the runtime stepped')
    c(#H.trace == sends, 'SC-7 with no Wishlist, Auto prunes no tome')
    c(S.Assign(H, A, 'Anchor plan', {R}), 'SC-7 reached: the Wishlist is assigned again')
    H.Advance(4, .05)
    c(S.Toggles(H, X2.echo) == 1 and S.Toggles(H, X3.echo) == 1 and H.disabled[X1.echo] == true
        and H.disabled[X2.echo] == true and H.disabled[X3.echo] == true and H.disabled[R.echo] == false,
        'SC-7 control: re-assigning resumes pruning of off-Wishlist tomes only')
    Trace('SC-7', H)
end

K.Run({
    {id='SC-1', fn=SC1}, {id='SC-2', fn=SC2}, {id='SC-3', fn=SC3}, {id='SC-4', fn=SC4},
    {id='SC-5', fn=SC5}, {id='SC-6', fn=SC6}, {id='SC-7', fn=SC7},
}, ARGV)
