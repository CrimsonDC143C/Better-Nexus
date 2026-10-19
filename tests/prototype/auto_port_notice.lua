-- Actual runtime + adapter event path on a synthetic game surface. No live roll.
-- A reroll still awaiting its result at a loading screen keeps Auto selected
-- but pauses further action; the player must see one post-entry chat notice.
local function Boot()
    Nexus=nil; NexusDB=nil; WishlistRealizerDB=nil; SlashCmdList=nil; NexusPanel=nil
    local H=dofile('tests/prototype/harness.lua')
    H.pendingRolls=2
    H.perks.serverActiveSlot=1
    H.perks.serverBuildSlots={[1]={name='Active saved build',verified=true,
        echoes={{spellId=200001,quality=1,stacks=2}}}}
    H.attempts=0
    for _,name in ipairs({'SelectPerk','BanishPerk','FreezePerk','RequestReroll'}) do
        local call=H.service[name]
        H.service[name]=function(...) H.attempts=H.attempts+1; return call(...) end
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
    factory.New=function(...) H.runtime=new(...); return H.runtime end
    H.Fire('ADDON_LOADED','Nexus'); H.Fire('PLAYER_ENTERING_WORLD'); H.Advance(20,.05)
    H.AcknowledgeOverwriteWarnings()
    assert(H.runtime,'real runtime loaded')
    assert(Nexus.GameAdapter.SetLoadoutWishlistIdentity(1,'Assigned plan',{{spellId=200001,quality=1,stacks=2}}))
    return H
end

local function CountNotice(H, kind)
    kind=kind or 'reroll'
    local n=0
    for _,line in ipairs(H.chat) do
        if line:find('Auto is ON but paused',1,true)
            and line:find(kind,1,true)
            and line:find('off and on',1,true) then n=n+1 end
    end
    return n
end

local function HasDoublePrefix(H)
    for _,line in ipairs(H.chat) do
        local plain=line:gsub('|c%x%x%x%x%x%x%x%x',''):gsub('|r','')
        if plain:find('Nexus: Nexus: Auto is ON but paused',1,true) then return true end
    end
    return false
end

-- This request is the harness's real client-service reroll latch, not a fake
-- grant or a live resource action. No board result is supplied across entry.
local H=Boot()
SlashCmdList.NEXUS('auto'); H.Advance(.5)
assert(Nexus.RecomputeStats().autoEnabled,'Auto selected before port')
assert(H.service.RequestReroll()==true and H.perks.pendingReroll==true,'reroll accepted and pending')
assert(H.attempts==1,'one request only')
H.Fire('PLAYER_LEAVING_WORLD'); H.Board({}); H.Notify(); H.Advance(2)
assert(CountNotice(H)==0,'notice must be shown after the world returns, not hidden during loading')
H.Fire('PLAYER_ENTERING_WORLD'); H.Advance(4)
local state=Nexus.AutomationEffectiveState()
assert(state.selected==true and state.state=='paused'
    and tostring(state.reason):find('no confirmed result for reroll sent before the loading screen',1,true),
    'the actual selected-ON/effectively-paused reroll hold is reached: '..tostring(state.state)..' '..tostring(state.reason))
assert(H.attempts==1,'loading screen must not resend the reroll')
assert(CountNotice(H)==1,'one post-entry chat notice names Auto ON, the reroll pause, and off/on recovery; got '..CountNotice(H))
assert(not HasDoublePrefix(H),'the pause notice has one Nexus prefix')
H.Advance(12)
assert(CountNotice(H)==1 and H.attempts==1,'no repeated notice or action while paused')

-- A loading screen with no outstanding action resumes normally and gives no
-- warning. Repeated UI/state reads also do not create a chat event.
local J=Boot()
SlashCmdList.NEXUS('auto'); J.Advance(.5)
J.Fire('PLAYER_LEAVING_WORLD'); J.Advance(2); J.Fire('PLAYER_ENTERING_WORLD'); J.Advance(4)
local normal=Nexus.AutomationEffectiveState()
assert(normal.selected==true and normal.state~='paused','no stale transition pause without a request')
assert(CountNotice(J)==0,'no warning for an ordinary loading screen')

-- A grant visible at the first eligible post-entry poll is settled by that
-- poll's full step. Do not warn about a hold that the step just ended.
local K=Boot()
K.run={remainingBanishes=0,totalRerolls=0,usedRerolls=0,
    totalFreezes=0,usedFreezes=0}
K.Board({{spellId=200001,quality=1},{spellId=200089,quality=0},
    {spellId=200090,quality=1}}); K.Notify()
SlashCmdList.NEXUS('auto'); K.Advance(1.2)
assert(K.attempts==1 and Nexus.RecomputeStats().lastActionLifecycle.actionType=='take',
    'one automatic Take is pending before the port')
K.Fire('PLAYER_LEAVING_WORLD'); K.Board({}); K.Notify(); K.Advance(2)
K.Fire('PLAYER_ENTERING_WORLD')
K.Advance(2.9)
K.perks.pendingSelectSpellId=nil
K.granted={['Echo 1']={{spellId=200001}}}; K.Notify()
K.Advance(.2,.2)
assert(Nexus.RecomputeStats().lastActionLifecycle.state=='confirmed',
    'the same post-entry step confirms the exact Take grant')
assert(K.attempts==1,'the exact grant does not resend the Take')
assert(CountNotice(K,'take')==0,'no pause warning after the exact grant ended the hold')

-- A new run observed by the first eligible poll supersedes the old reroll.
-- The pending notice belongs to the old run and must be dropped with it.
local M=Boot()
SlashCmdList.NEXUS('auto'); M.Advance(.5)
assert(M.service.RequestReroll()==true,'run-boundary case has a pending reroll')
M.playerLevel=80; M.Advance(1)
M.Fire('PLAYER_LEAVING_WORLD'); M.Board({}); M.Notify(); M.Advance(2)
M.Fire('PLAYER_ENTERING_WORLD'); M.Advance(2.9)
M.playerLevel=1; M.Advance(.2,.2)
local _,boundaryReason=M.runtime.AutoAllowed()
assert(not tostring(boundaryReason):find('no confirmed result',1,true),
    'the new run ends the old-run world hold: '..tostring(boundaryReason))
assert(M.attempts==1,'the run boundary does not resend the reroll')
assert(CountNotice(M)==0,'no old-run pause warning after the run boundary')

-- Readiness can return after the scheduled settle step has already run.
-- The next ordinary poll still gives the pending-action notice promptly.
local L=Boot()
SlashCmdList.NEXUS('auto'); L.Advance(.5)
assert(L.service.RequestReroll()==true,'readiness case has a pending reroll')
L.Fire('PLAYER_LEAVING_WORLD'); L.Board({}); L.Notify(); L.Advance(2)
local name=UnitName
UnitName=function() return 'Unknown' end
L.Fire('PLAYER_ENTERING_WORLD'); L.Advance(4)
assert(CountNotice(L)==0,'not ready: no notice yet')
UnitName=name; L.Advance(.3)
assert(CountNotice(L)==1,'ready: one prompt notice without new board data')
L.Advance(1)
assert(CountNotice(L)==1,'readiness recovery does not duplicate the notice')

print('PASS one post-entry Auto pause notice for an unresolved reroll; no resend or duplicate; same-poll grant and run boundary do not warn; delayed readiness still warns')
