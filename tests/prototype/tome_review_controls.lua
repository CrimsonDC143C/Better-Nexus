-- Review controls for PR #119: visit-latched non-idempotent toggles, fair
-- keep/disable progress, typed progress, and bound Auto-prompt consent.
-- Real TOC/runtime/adapter; synthetic host only. No native client claim.
local S = dofile('tests/prototype/approved_tome_coverage_support.lua')
local K = S.Checker('tome_review_controls')
local function Auto() return Nexus.RecomputeStats().autoEnabled == true end
local function DialogText()
    local info = StaticPopupDialogs and StaticPopupDialogs.NEXUS_LEVEL1_AUTO_TOMES
    return info and tostring(info.text or '') or ''
end
local function EchoFor(A, lever)
    local lv = A.Catalog() and A.Catalog().levers and A.Catalog().levers[lever]
    return lv and lv.members and lv.members[1]
end
local function WrapCalls(H, refuseId)
    local calls, inner = {}, H.service.ToggleTomeEcho
    H.service.ToggleTomeEcho = function(id)
        calls[#calls + 1] = {id = id, at = H.now}
        if refuseId and id == refuseId then return false end
        return inner(id)
    end
    return calls
end
local function Count(calls, id)
    local n = 0
    for i = 1, #calls do if calls[i].id == id then n = n + 1 end end
    return n
end

K.Run({
    {id = 'keep_fair', fn = function(c)
        local A1, B1 = S.Lever(1, 'Keep Alpha', true, true), S.Lever(2, 'Keep Beta', true, true)
        local H, A = S.Fixture({levers = {A1, B1}})
        c(S.Assign(H, A, 'Keep pair', {A1, B1}), 'keep_fair reached: both Wishlist tomes assigned')
        c(S.AutoOn(H), 'keep_fair reached: Auto ON')
        local plan = Nexus.Strategy.Compile(A.Catalog(), A.Wishlist(), Nexus.Store.Settings())
        local firstLever, secondLever = plan.leverPlan.keep[1], plan.leverPlan.keep[2]
        local firstEcho, secondEcho = EchoFor(A, firstLever), EchoFor(A, secondLever)
        c(firstEcho and secondEcho and firstEcho ~= secondEcho, 'keep_fair reached: two keep candidates')
        local calls = WrapCalls(H, firstEcho)
        S.ResetToLevel1(H)
        H.Advance(.3, .05)
        c(#calls >= 1 and calls[1].id == firstEcho, 'keep_fair reached: first keep candidate is attempted')
        H.Advance(.7, .05)
        c(Count(calls, firstEcho) >= 1 and Count(calls, secondEcho) == 1,
            'keep_fair a persistently refused keep A does not starve keep B')
        c(H.disabled[secondEcho] == false, 'keep_fair keep B is accepted and confirmed')
    end},
    {id = 'disable_fair', fn = function(c)
        local R = S.Lever(1, 'Disable Anchor', true, false)
        local X1, X2 = S.Lever(2, 'Disable Spare One', true, false), S.Lever(3, 'Disable Spare Two', true, false)
        local H, A = S.Fixture({levers = {R, X1, X2}})
        c(S.Assign(H, A, 'Disable pair', {R}), 'disable_fair reached: Wishlist assigned')
        c(S.AutoOn(H), 'disable_fair reached: Auto ON')
        local plan = Nexus.Strategy.Compile(A.Catalog(), A.Wishlist(), Nexus.Store.Settings())
        local firstLever, secondLever = plan.leverPlan.disable[1], plan.leverPlan.disable[2]
        local firstEcho, secondEcho = EchoFor(A, firstLever), EchoFor(A, secondLever)
        c(firstEcho and secondEcho and firstEcho ~= secondEcho, 'disable_fair reached: two disable candidates')
        local calls = WrapCalls(H, firstEcho)
        S.ResetToLevel1(H)
        H.Advance(.3, .05)
        c(#calls >= 1 and calls[1].id == firstEcho, 'disable_fair reached: first disable candidate is attempted')
        H.Advance(.7, .05)
        c(Count(calls, firstEcho) >= 1 and Count(calls, secondEcho) == 1,
            'disable_fair a persistently refused disable A does not starve disable B')
        c(H.disabled[secondEcho] == true, 'disable_fair disable B is accepted and confirmed')
    end},
    {id = 'unread_keep', fn = function(c)
        local R, X = S.Lever(1, 'Unread Keep', true, false), S.Lever(2, 'Unread Spare', true, false)
        local H, A = S.Fixture({levers = {R, X}})
        c(S.Assign(H, A, 'Unread plan', {R}), 'unread_keep reached: Wishlist assigned')
        local raw = H.service.IsTomeEchoDisabled
        H.service.IsTomeEchoDisabled = function(id)
            if id == R.echo then return nil end
            return raw(id)
        end
        c(A.LeverMirrorKind(R.lever) == 'unknown' and A.DisabledLevers()[R.lever] == nil,
            'unread_keep reached: unreadable keep is omitted from DisabledLevers')
        c(S.AutoOn(H), 'unread_keep reached: Auto ON')
        S.ResetToLevel1(H)
        H.Advance(1.2, .05)
        local text = DialogText()
        c(text:find('will not send another automatic change', 1, true) ~= nil,
            'unread_keep unknown keep is not reported as configured')
        c(not text:find('Please wait', 1, true) and not text:find('You may now level up', 1, true),
            'unread_keep unknown keep neither waits nor claims success')
        c(#H.trace == 1 and H.trace[1].id == X.echo, 'unread_keep still disables the readable spare')
    end},
    {id = 'unconfirmed_disable', fn = function(c)
        local R, X = S.Lever(1, 'Held Anchor', true, false), S.Lever(2, 'Held Spare', true, false)
        local H, A = S.Fixture({levers = {R, X}, holdMirror = true})
        c(S.Assign(H, A, 'Held disable', {R}), 'unconfirmed_disable reached: Wishlist assigned')
        c(S.AutoOn(H), 'unconfirmed_disable reached: Auto ON')
        S.ResetToLevel1(H)
        S.Within(H, 2, function() return #H.trace >= 1 end)
        c(#H.trace == 1 and H.trace[1].id == X.echo and H.disabled[X.echo] == false,
            'unconfirmed_disable reached: disable is accepted with a held mirror')
        H.Advance(31, .05)
        c(#H.trace == 1, 'unconfirmed_disable expiry does not send a second disable')
        local text = DialogText()
        c(text:find('will not send another automatic change', 1, true) ~= nil,
            'unconfirmed_disable remaining work is unconfirmed, not in-progress')
        c(not text:find('Please wait', 1, true) and not text:find('You may now level up', 1, true),
            'unconfirmed_disable neither waits nor claims success')
        H.holdMirror = false; H.disabled[X.echo] = true; H.Notify(); H.Advance(1, .05)
        c(#H.trace == 1 and H.disabled[X.echo] == true,
            'unconfirmed_disable late confirmation does not authorize another request')
    end},
    {id = 'late_enable', fn = function(c)
        local R, X = S.Lever(1, 'Late Enable', true, true), S.Lever(2, 'Late Spare', true, false)
        local H, A = S.Fixture({levers = {R, X}, holdMirror = true})
        c(S.Assign(H, A, 'Late enable', {R}), 'late_enable reached: Wishlist assigned')
        c(S.AutoOn(H), 'late_enable reached: Auto ON')
        S.ResetToLevel1(H)
        S.Within(H, 2, function() return #H.trace >= 1 end)
        c(#H.trace == 1 and H.trace[1].id == R.echo and H.disabled[R.echo] == true,
            'late_enable reached: enable is pending without its mirror')
        H.Advance(31, .05)
        c(S.Toggles(H, R.echo) == 1, 'late_enable expiry does not resubmit the enable')
        H.holdMirror = false; H.disabled[R.echo] = false; H.Notify(); H.Advance(1, .05)
        c(S.Toggles(H, R.echo) == 1 and H.disabled[R.echo] == false,
            'late_enable late confirmation settles without a second toggle')
    end},
    {id = 'prompt_retire', fn = function(c)
        local R = S.Lever(1, 'Prompt Echo', true, true)
        local H, A = S.Fixture({levers = {R}})
        c(S.Assign(H, A, 'Prompt plan', {R}), 'prompt_retire reached: Wishlist assigned')
        S.ResetToLevel1(H); H.Advance(1, .05)
        c(not Auto() and H.popup and H.popup.which == 'NEXUS_LEVEL1_AUTO_TOMES',
            'prompt_retire reached: Auto-OFF mismatch shows the Enable Auto prompt')
        H.disabled[R.echo] = false; H.Notify(); H.Advance(1, .05)
        c(H.popup == nil, 'prompt_retire resolving the mismatch retires the Auto-OFF prompt')
        c(not Auto() and #H.trace == 0, 'prompt_retire retiring the prompt does not enable Auto or send')
    end},
    {id = 'prompt_revalidate', fn = function(c)
        local R = S.Lever(1, 'Bound Echo', true, true)
        local H, A = S.Fixture({levers = {R}})
        c(S.Assign(H, A, 'Bound plan', {R}), 'prompt_revalidate reached: Wishlist assigned')
        S.ResetToLevel1(H); H.Advance(1, .05)
        c(H.popup and H.popup.which == 'NEXUS_LEVEL1_AUTO_TOMES', 'prompt_revalidate reached: prompt is open')
        Nexus.MainInternals.StoreAuthorityOwner.UpdateSettingsV1('autoDisable', false)
        local accepted = H.AcceptPopup()
        c(accepted ~= true and not Auto(),
            'prompt_revalidate Yes is refused after tome permission is cleared')
    end},
    {id = 'prompt_overwrite', fn = function(c)
        local R = S.Lever(1, 'Overwrite Echo', true, true)
        local H, A = S.Fixture({levers = {R}, keepPrompts = true})
        local f = rawget(_G, 'NexusOverwriteWarning')
        if not (f and f:IsShown()) then SlashCmdList.NEXUS('auto'); f = rawget(_G, 'NexusOverwriteWarning') end
        H.Advance(5.01, .05)
        if f and f:IsShown() and f.yes:IsEnabled() then f.yes:Click() end
        local quick = rawget(_G, 'NexusQuickStart')
        if quick and quick:IsShown() then quick:Hide(); H.Advance(.2, .05) end
        c(Nexus.OverwriteWarning.EnsureOnboarding() ~= 'pending' and not Auto(),
            'prompt_overwrite reached: onboarding answered, Auto still OFF')
        c(S.Assign(H, A, 'Overwrite plan', {R}), 'prompt_overwrite reached: Wishlist assigned')
        S.ResetToLevel1(H); H.Advance(1, .05)
        c(H.popup and H.popup.which == 'NEXUS_LEVEL1_AUTO_TOMES',
            'prompt_overwrite reached: the bound Auto prompt is open')
        H.AcceptPopup()
        f = rawget(_G, 'NexusOverwriteWarning')
        c(f and f:IsShown() and not Auto() and #H.trace == 0,
            'prompt_overwrite reached: prompt Yes opens the overwrite warning')
        H.disabled[R.echo] = false; H.Notify(); H.Advance(1, .05)
        if f and f:IsShown() and f.yes:IsEnabled() then f.yes:Click() end
        c(not Auto() and #H.trace == 0,
            'prompt_overwrite a deferred Yes is refused after the bound mismatch resolves')
    end},
}, rawget(_G, 'arg'))
