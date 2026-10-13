-- Independent review probes for the own-reroll world reconciliation.
-- Synthetic runtime and client only; no live resource action.
local FIRST={{spellId=200001,quality=1},{spellId=200089,quality=0},
    {spellId=200090,quality=1}}
local SECOND={{spellId=200001,quality=1},{spellId=200091,quality=0},
    {spellId=200092,quality=1}}
local THIRD={{spellId=200001,quality=1},{spellId=200093,quality=0},
    {spellId=200094,quality=1}}

local function Boot()
    Nexus=nil; NexusDB=nil; WishlistRealizerDB=nil; SlashCmdList=nil; NexusPanel=nil
    local H=dofile('tests/prototype/harness.lua')
    H.pendingRolls=2
    H.perks.serverActiveSlot=1
    H.perks.serverBuildSlots={[1]={name='Active saved build',verified=true,
        echoes={{spellId=200001,quality=1,stacks=2}}}}
    H.attempts=0
    local reroll=H.service.RequestReroll
    H.service.RequestReroll=function(...)
        H.attempts=H.attempts+1
        return reroll(...)
    end
    for line in io.lines('Nexus.toc') do
        line=line:gsub('\r','')
        if line~='' and not line:match('^#') then
            local chunk,err=loadfile((line:gsub('\\','/')))
            assert(chunk,err); chunk('Nexus',{})
        end
    end
    local factory=Nexus.MainInternals.AutomationRuntime
    local new=factory.New
    H.decide='wait'
    factory.New=function(options)
        options.policy.Decide=function()
            if H.decide=='reroll' then
                return {type='reroll',reason='review fixture reroll'}
            end
            return {type='wait',reason='review fixture wait'}
        end
        H.runtime=new(options)
        return H.runtime
    end
    H.Board(FIRST)
    H.Fire('ADDON_LOADED','Nexus'); H.Fire('PLAYER_ENTERING_WORLD')
    H.Advance(20,.05)
    H.AcknowledgeOverwriteWarnings()
    assert(Nexus.GameAdapter.SetLoadoutWishlistIdentity(1,'Assigned plan',
        {{spellId=200001,quality=1,stacks=2}}))
    return H
end

local function OwnReroll(H)
    H.decide='reroll'
    if not Nexus.RecomputeStats().autoEnabled then SlashCmdList.NEXUS('auto') end
    local before=H.attempts
    H.Advance(4.5)
    local allowed,why=H.runtime.AutoAllowed()
    assert(H.attempts==before+1 and H.perks.pendingReroll==true,
        'one own reroll submitted, attempts='..H.attempts
            ..' allowed='..tostring(allowed)..' why='..tostring(why)
            ..' lifecycle='..tostring(Nexus.RecomputeStats().lastActionLifecycle.state)
            ..'/'..tostring(Nexus.RecomputeStats().lastActionLifecycle.reason)
            ..' pending='..tostring(H.perks.pendingReroll)
            ..' inFlight='..tostring(Nexus.GameAdapter.InFlight())
            ..' pendingN='..tostring(#Nexus.GameAdapter.PendingActions())
            ..' status='..tostring(Nexus.RecomputeStats().lastStepContext and Nexus.RecomputeStats().lastStepContext.outcome))
end

local function Port(H)
    H.Fire('PLAYER_LEAVING_WORLD')
    H.Board({}); H.Notify(); H.Advance(2)
    H.Fire('PLAYER_ENTERING_WORLD')
end

local function Answer(H, cards, used)
    H.perks.pendingReroll=nil
    H.Board(cards); H.Notify()
    H.run=H.Clone(H.run)
    H.run.usedRerolls=used
end

-- The first count rise after our request can belong to a player reroll that
-- advanced its board before its run-data push. Its pending latch is gone, so
-- the own request is admissible, but the raw baseline has not caught up.
do
    local H=Boot()
    assert(H.service.RequestReroll()==true,'player reroll accepted first')
    H.perks.pendingReroll=nil
    H.Board(SECOND); H.Notify(); H.Advance(4)
    assert(H.run.usedRerolls==0,'earlier player spend has not reached run data')
    OwnReroll(H)
    Port(H); H.Advance(4)
    H.decide='wait'; Answer(H,THIRD,1); H.Advance(1)
    local ok,why=H.runtime.AutoAllowed()
    assert(not ok and tostring(why):find('no confirmed result for reroll',1,true),
        'late player +1 cannot prove the own reroll: '..tostring(why))
    assert(H.attempts==2 and Nexus.RecomputeStats().actionLifecycle.confirmed==0,
        'no duplicate or false confirmation after an earlier outside request')
end

-- The old run's local record cannot poison attribution in the next run.
do
    local H=Boot(); OwnReroll(H)
    H.playerLevel=80; H.Advance(.5)
    H.Fire('PLAYER_LEAVING_WORLD'); H.Board({}); H.Notify(); H.Advance(2)
    H.perks.pendingReroll=nil
    H.playerLevel=1
    H.Fire('PLAYER_ENTERING_WORLD'); H.Advance(4)
    local life=Nexus.RecomputeStats().lastActionLifecycle
    assert(life.state=='superseded' and life.reason=='run_boundary',
        'old reroll voided by new run: '..life.state..'/'..life.reason)
    H.run=H.Clone(H.run); H.run.usedRerolls=0
    H.decide='reroll'
    H.playerLevel=40; H.Board(SECOND); H.Notify()
    OwnReroll(H)
    Port(H); H.Advance(4)
    H.decide='wait'; Answer(H,THIRD,1); H.Advance(1)
    life=Nexus.RecomputeStats().lastActionLifecycle
    assert(life.state=='confirmed' and life.reason=='reroll_run_data_observed',
        'next-run own reroll still attributable: '..life.state..'/'..life.reason)
    assert(H.attempts==2,'one request in each run, no replay')
end

-- Proof at the first eligible post-entry poll ends the old hold before any
-- new mutation. A fresh policy decision still observes the normal intent beat.
do
    local H=Boot(); OwnReroll(H); Port(H)
    H.Advance(2.9)
    Answer(H,SECOND,1)
    H.Advance(.2,.2)
    assert(H.runtime.AutoAllowed(),'same-poll proof releases the hold')
    assert(H.attempts==1,'no mutation in the proof poll')
    local life=Nexus.RecomputeStats().lastActionLifecycle
    assert(life.state=='prepared' and life.actionType=='reroll',
        'fresh decision is only prepared in the proof poll: '
            ..life.state..'/'..life.actionType)
    H.Advance(.8)
    assert(H.attempts==2,'fresh decision sends after its ordinary beat')
end

-- Duplicate leave/entry pairs preserve the same unresolved request. One
-- authoritative answer confirms once; later polls and notifications do not
-- confirm again or resend it.
do
    local H=Boot(); OwnReroll(H)
    H.decide='wait'
    H.Fire('PLAYER_LEAVING_WORLD'); H.Fire('PLAYER_LEAVING_WORLD')
    H.Board({}); H.Notify(); H.Advance(2)
    H.Fire('PLAYER_ENTERING_WORLD'); H.Advance(4)
    Port(H); H.Advance(4)
    Answer(H,SECOND,1); H.Advance(1)
    local n=Nexus.RecomputeStats().actionLifecycle.confirmed
    assert(n==1 and H.attempts==1,'one confirmed result across duplicate events')
    for _=1,4 do H.Notify(); H.Advance(2) end
    assert(Nexus.RecomputeStats().actionLifecycle.confirmed==n and H.attempts==1,
        'repeated polls and notifications stay idempotent')
end

print('PASS independent Auto-port edges: earlier external spend, next run, same-poll beat, duplicate events and polls')
