-- Actual runtime/adapter on a synthetic client. No live reroll or resource use.
-- A crossed own reroll may resume only after a fresh same-run server spend,
-- changed offer, clear latch, and no competing reroll request.
local function Boot()
    Nexus=nil; NexusDB=nil; WishlistRealizerDB=nil; SlashCmdList=nil; NexusPanel=nil
    local H=dofile('tests/prototype/harness.lua')
    H.pendingRolls=2
    H.perks.serverActiveSlot=1
    H.perks.serverBuildSlots={[1]={name='Active saved build',verified=true,
        echoes={{spellId=200001,quality=1,stacks=2}}}}
    H.attempts=0
    local call=H.service.RequestReroll
    H.service.RequestReroll=function(...)
        H.attempts=H.attempts+1
        return call(...)
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
    H.decide='reroll'
    factory.New=function(options)
        options.policy.Decide=function()
            if H.decide=='wait' then return {type='wait',reason='fixture settled'} end
            return {type='reroll',reason='fixture own reroll'}
        end
        H.runtime=new(options)
        return H.runtime
    end
    H.Board({{spellId=200001,quality=1},{spellId=200089,quality=0},
        {spellId=200090,quality=1}})
    H.Fire('ADDON_LOADED','Nexus'); H.Fire('PLAYER_ENTERING_WORLD'); H.Advance(20,.05)
    H.AcknowledgeOverwriteWarnings()
    assert(Nexus.GameAdapter.SetLoadoutWishlistIdentity(1,'Assigned plan',
        {{spellId=200001,quality=1,stacks=2}}))
    SlashCmdList.NEXUS('auto'); H.Advance(1.2)
    assert(H.attempts==1 and H.perks.pendingReroll==true,
        'one own reroll must be submitted: '..H.attempts)
    return H
end

local function Enter(H)
    H.Fire('PLAYER_LEAVING_WORLD')
    H.Board({}); H.Notify(); H.Advance(2)
    H.Fire('PLAYER_ENTERING_WORLD'); H.Advance(4)
    local ok, why=H.runtime.AutoAllowed()
    assert(not ok and tostring(why):find('no confirmed result for reroll',1,true),
        'unresolved own request held after entry: '..tostring(why))
end

local function Answer(H, used, cards)
    H.decide='wait'
    H.perks.pendingReroll=nil
    H.Board(cards or {{spellId=200001,quality=1},{spellId=200091,quality=0},
        {spellId=200092,quality=1}})
    H.Notify()
    H.run=H.Clone(H.run)
    H.run.usedRerolls=used
    H.Advance(1)
end

-- The server's new run record and the client reply jointly settle the own
-- reroll. A second observation does not submit it again.
do
    local H=Boot(); Enter(H)
    assert(H.attempts==1,'no resend on world entry')
    Answer(H,1)
    local ok=H.runtime.AutoAllowed()
    assert(ok,'fresh same-run spend and offer resume Auto')
    local life=Nexus.RecomputeStats().lastActionLifecycle
    assert(life.state=='confirmed' and life.reason=='reroll_run_data_observed',
        'own reroll result recorded once: '..life.state..'/'..life.reason)
    H.Notify(); H.Advance(2)
    assert(H.attempts==1,'duplicate notifications do not replay request')
end

-- A moved board, cleared latch and optimistic local charge decrement do not
-- amount to a server result. An unrelated same-count push remains waiting.
do
    local H=Boot(); Enter(H)
    H.perks.pendingReroll=nil
    H.Board({{spellId=200001,quality=1},{spellId=200093,quality=0}})
    H.Notify(); H.Advance(2)
    H.run=H.Clone(H.run); H.Advance(1)
    local ok=H.runtime.AutoAllowed()
    assert(not ok and H.attempts==1,'unchanged raw used count keeps hold')
    -- Past the ten-second intent timeout, without a board notification: the
    -- adapter poll must wake the full step on the delayed server spend.
    H.decide='wait'; H.Advance(16)
    H.run=H.Clone(H.run); H.run.usedRerolls=1
    H.Advance(1)
    assert(H.runtime.AutoAllowed(),'delayed +1 settles without another action')
    assert(H.attempts==1,'delayed settlement did not resend')
end

-- An external reroll earlier in this run may have a delayed +1 push; without
-- request IDs that later count cannot be attributed to the own request.
do
    local H=Boot()
    -- An outside call after the own send, even a refused duplicate, is an
    -- attribution conflict. It may not clear the world hold.
    assert(H.service.RequestReroll()==false,'duplicate outside call refused')
    Enter(H); Answer(H,1)
    assert(not H.runtime.AutoAllowed(),'outside reroll epoch keeps hold')
    assert(H.attempts==2,'no retry after competing call')
end

do
    local H=Boot()
    Enter(H)
    H.decide='wait'; H.perks.pendingReroll=nil
    H.Board({{spellId=200001,quality=1},{spellId=200093,quality=0}})
    H.run=H.Clone(H.run); H.run.usedRerolls=2
    H.Notify(); H.Advance(1)
    assert(not H.runtime.AutoAllowed(),'more than one spend is ambiguous')
end

print('PASS own reroll recovery: fresh exact server spend, delayed push, ambiguous/missing/competing evidence, no resend')
