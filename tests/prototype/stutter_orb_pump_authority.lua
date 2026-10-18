-- CX-04 semantic controls (stutter review, 2026-10-15). They pass on the
-- current source (3d52b0ed7044 plus NX-03, NX-02, NX-01) and must keep passing
-- after any change that lets one Orb pump reuse its own assignment read
-- (stutter_orb_pump.lua).
--
-- Required:
--  1. Spend precondition: a change made inside the Spend call, after every
--     pump read and before the adapter's own checks, is refused. Nothing is
--     spent. Design, loading and source drift reach the Spend callback, which
--     reads the assignment fresh.
--  2. Select precondition: the same for the Select call. Nothing is selected.
--     A paused pump selects nothing; Resume selects after its own fresh read.
--  3. A change between two pumps is seen by the next pump's single read, in
--     the pending and in the nonpending branch.
--  4. Reentrant write: the first-run hand-off written by the pump's own read
--     does not let the pump act; the pump reads the assignment once.
-- Instruments as in stutter_orb_pump.lua: public OrbRuntime.Pump,
-- GameAdapter.AssignedWishlist, Orbs.Spend and Orbs.Select, each delegating.
local H=dofile('tests/prototype/orbs_support.lua')
local A,M,O=H.A,H.M,H.O
local checks=0;local function check(v,m)assert(v,m);checks=checks+1 end

H.OrbPlan() -- the assigned plan: one copy of 410002 (quality 2)
local BASE=H.Clone(H.granted)

-- Instruments.
local work={pumps=0,outside=0,inside=0}
local pumpDepth,guardDepth=0,0
local rawPump=M.Pump
local function LeavePump(ok,...) pumpDepth=pumpDepth-1;if not ok then error((...),0) end return ... end
M.Pump=function(...) work.pumps=work.pumps+1;pumpDepth=pumpDepth+1;return LeavePump(pcall(rawPump,...)) end
local rawAssigned=A.AssignedWishlist
A.AssignedWishlist=function(...)
 if pumpDepth>0 then
  if guardDepth>0 then work.inside=work.inside+1 else work.outside=work.outside+1 end
 end
 return rawAssigned(...)
end
local rawSpend,rawSelect=A.Orbs.Spend,A.Orbs.Select
local function LeaveGuard(ok,...) guardDepth=guardDepth-1;if not ok then error((...),0) end return ... end
local function Counted(guard)
 if type(guard)~='function' then return guard end
 return function(...) guardDepth=guardDepth+1;return LeaveGuard(pcall(guard,...)) end
end
-- One-shot changes made inside the action call, before the real adapter runs.
local spendChange,selectChange
A.Orbs.Spend=function(token,key,expected,guard)
 local change=spendChange;spendChange=nil
 if change then change(key) end
 return rawSpend(token,key,expected,Counted(guard))
end
A.Orbs.Select=function(token,index,board,id,guard)
 local change=selectChange;selectChange=nil
 if change then change(id) end
 return rawSelect(token,index,board,id,Counted(guard))
end
local function Measure(fn,...)
 for k in pairs(work) do work[k]=0 end
 fn(...)
 local w={};for k,v in pairs(work) do w[k]=v end
 return w
end
local function Later() H.now=H.now+.2 end
local function State() return M.CompactStatus() or {} end
local function OneOf(v,list) for _,x in ipairs(list) do if v==x then return true end end return false end

-- Literal refusal texts (core/OrbAdapter.lua, core/OrbRuntime.lua).
local SPEND_GUARD='Assignment or source protection changed before submission. Resume only after reviewing the current assignment.'
local SELECT_GUARD='The assigned target changed before selection. The original pending operation must be resolved.'
local CONTEXT='The character, loadout, or game service changed. Orb mode is paused.'
local BALANCE_LOADING="Waiting for the server's Orb balance. Use Recheck once it is available."
local SOURCE_CHANGED='The approved source or balance changed before spending.'
local TRUST_WAIT='Waiting for current rolled and locked Echo data from the server.'
local OFFER_CHANGED='The Orb offer changed or another action is pending.'
local TARGET_CHANGED='The active loadout or assigned Wishlist changed. The original operation stays pending; Resume requires settlement and a resolved assignment.'
local LOADOUT='The original loadout cannot be verified after a loadout change or an incomplete older receipt. Ownership responses do not identify the original loadout. Pending exposure is retained; no retry is allowed.'

-- Changes and their restores.
local rawGUID=UnitGUID
local drift
local function Design(stacks)
 return function() assert(A.SetFirstLoadoutWishlistIdentity('Orb test',{{spellId=410002,quality=2,stacks=stacks or 2}})) end
end
local function Drift(id) id=tonumber(tostring(id):match('^(%d+)'));drift={id,H.db[id].groupId};H.db[id].groupId=4199 end
local function Undrift() if drift then H.db[drift[1]].groupId=drift[2];drift=nil end end
local function Nothing() end
local C={
 design={name='design change',change=Design(2),restore=Nothing,replan=true},
 loading={name='build-slot mirror unavailable (loading)',change=function() H.perks.serverBuildSlots=nil end,
  restore=function() H.perks.serverBuildSlots={} end},
 drift={name='catalog family drift of the',change=Drift,restore=Undrift},
 slot={name='active slot change',change=function() H.perks.serverActiveSlot=1 end,restore=function() H.perks.serverActiveSlot=0 end},
 owner={name='character change',change=function() UnitGUID=function() return '0x0000000000000002' end end,
  restore=function() UnitGUID=rawGUID end},
 mirror={name='ownership mirror in-place change',change=function() H.granted['Excess high']={{spellId=410006,quality=3}} end,
  restore=function() H.granted['Excess high']=nil end},
 stale={name='Orb balance not known (stale)',change=function() O.known=false end,restore=function() O.known=true end},
}

-- Back to the base ownership and balance, with no run and no offer.
local function Reset()
 H.granted=H.Clone(BASE);O.charges=10;O.offer=false
 H.perks.currentChoice=nil;H.perks.pendingSelectSpellId=nil
 H.Notify();A.Poll();Later()
end
-- Stop, resolve the native offer by hand and settle the receipt passively.
local function Settle(label,replan)
 check(M.Stop(),label..': cleanup Stop')
 H.service.SelectPerk(410002);H.Result(410002,2)
 local c=State()
 check(c.pending==false and c.running==false,label..': cleanup the receipt settles: state='..tostring(c.state))
 Reset()
 if replan then H.OrbPlan() end
end
local function Spend(label)
 local spends=H.Count('orb-spend')
 local w=Measure(H.Approve,1,false,true)
 local c=State()
 check(w.pumps==1 and H.Count('orb-spend')==spends+1 and c.state=='WAIT_OFFER' and c.pending==true,
  label..' SETUP: one approved Orb spend: spends='..(H.Count('orb-spend')-spends)..' state='..tostring(c.state))
 check(w.inside==1,label..' SETUP: the Spend precondition read the assignment fresh: '..w.inside)
end

-- 1. Spend precondition freshness.
local SPEND={
 {C.design,{SPEND_GUARD},1},
 {C.loading,{SPEND_GUARD},1},
 {C.drift,{SPEND_GUARD},1,' source'},
 {C.slot,{CONTEXT},0},
 {C.owner,{CONTEXT},0},
 {C.mirror,{CONTEXT,SOURCE_CHANGED,TRUST_WAIT},0},
 {C.stale,{BALANCE_LOADING},0},
}
for _,row in ipairs(SPEND) do
 local case,reasons,guard=row[1],row[2],row[3]
 local label='1 Spend '..case.name..(row[4] or '')
 Later()
 local spends=H.Count('orb-spend')
 spendChange=case.change
 local w=Measure(H.Approve,1,false,true)
 case.restore()
 local c=State()
 check(spendChange==nil and w.pumps==1,label..' SETUP: the change was made inside the one Spend call: pumps='..w.pumps)
 check(H.Count('orb-spend')==spends and c.state=='PAUSED' and c.pending==false and OneOf(c.reason,reasons),
  label..': refused, nothing spent: spends='..(H.Count('orb-spend')-spends)..' state='..tostring(c.state)..' reason='..tostring(c.reason))
 check(w.inside==guard,label..': precondition callback assignment reads '..w.inside..' (expected '..guard..')')
 check(M.Stop(),label..': cleanup Stop')
 Later()
 if case.replan then H.OrbPlan() end
end

-- 2. Select precondition freshness.
-- 2a. Unchanged: a paused pump selects nothing; Resume selects after its own
-- fresh read.
Spend('2a')
check(M.Pause(),'2a SETUP: pause before the offer')
Later();local takes=H.Count('take')
local w=Measure(H.Offer)
check(w.pumps==1 and H.Count('take')==takes and w.outside==1 and w.inside==0,
 '2a a paused pump selects nothing and reads the assignment once: takes='..(H.Count('take')-takes)..' reads='..w.outside)
Later()
w=Measure(function() check(M.Resume(),'2a Resume accepts the known waiting offer') end)
local last=H.actions[#H.actions]
check(H.Count('take')==takes+1 and last and last[1]=='take' and last[2]==410002 and State().state=='WAIT_RESULT',
 '2a Resume selects 410002 once: takes='..(H.Count('take')-takes)..' state='..tostring(State().state))
check(w.inside==1,'2a the Select precondition read the assignment fresh: '..w.inside)
Later();H.Result(410002,2)
check(State().state=='COMPLETE' and State().pending==false,'2a the result completes the plan: '..tostring(State().state))
Reset()

local SELECT={
 {C.design,{SELECT_GUARD},1},
 {C.loading,{SELECT_GUARD},1},
 {C.drift,{OFFER_CHANGED},0,' target'},
 {C.slot,{CONTEXT},0},
 {C.owner,{CONTEXT},0},
 {C.stale,{BALANCE_LOADING},0},
}
for _,row in ipairs(SELECT) do
 local case,reasons,guard=row[1],row[2],row[3]
 local label='2 Select '..case.name..(row[4] or '')
 Later();Spend(label)
 Later();takes=H.Count('take')
 selectChange=case.change
 w=Measure(H.Offer)
 case.restore()
 local c=State()
 check(selectChange==nil and w.pumps==1,label..' SETUP: the change was made inside the one Select call: pumps='..w.pumps)
 check(H.Count('take')==takes and c.state=='PAUSED' and c.pending==true and OneOf(c.reason,reasons),
  label..': refused, nothing selected: takes='..(H.Count('take')-takes)..' state='..tostring(c.state)..' reason='..tostring(c.reason))
 check(w.inside==guard,label..': precondition callback assignment reads '..w.inside..' (expected '..guard..')')
 Settle(label,case.replan)
end

-- 3. Changes between pumps reach the next pump's single read.
-- 3a. Pending branch: the design changes before the offer pump.
Later();Spend('3a')
Design(2)()
Later();takes=H.Count('take')
w=Measure(H.Offer)
local c=State()
check(w.pumps==1 and w.outside==1 and w.inside==0,'3a the pending pump reads the assignment once: '..w.outside..' '..w.inside)
check(H.Count('take')==takes and c.state=='PAUSED' and c.pending==true and c.reason==TARGET_CHANGED,
 '3a the pending pump pauses on the changed design and selects nothing: state='..tostring(c.state)..' reason='..tostring(c.reason))
Settle('3a',true)

-- 3b. Nonpending branch: a settled result leaves the run READY; the design
-- changes before the next pump.
H.OrbPlan({{spellId=410002,quality=2,stacks=2}})
Later();H.Approve(2,false,false)
check(H.Count('orb-spend')>0 and State().state=='WAIT_OFFER','3b SETUP: the first approved Orb is spent')
Later();takes=H.Count('take');H.Offer()
check(H.Count('take')==takes+1 and State().state=='WAIT_RESULT','3b SETUP: the target is selected')
Later();H.Result(410002,2)
c=State()
check(c.state=='READY' and c.running==true and c.pending==false,'3b SETUP: one copy confirmed, the run continues: '..tostring(c.state))
Design(3)()
Later();local spends=H.Count('orb-spend')
w=Measure(M.Pump)
c=State()
check(w.pumps==1 and w.outside==1 and w.inside==0,'3b the nonpending pump reads the assignment once: '..w.outside..' '..w.inside)
check(H.Count('orb-spend')==spends and c.state=='PAUSED' and c.pending==false and c.reason==TARGET_CHANGED,
 '3b the nonpending pump pauses on the changed design and spends nothing: state='..tostring(c.state)..' reason='..tostring(c.reason))
check(M.Stop(),'3b cleanup Stop')
Reset();H.OrbPlan()

-- 4. Reentrant write: while an Orb is pending, the active loadout moves to a
-- populated Saved Build with no association. The pump's own assignment read
-- writes the first-run hand-off for that loadout.
Later();Spend('4')
local before=Nexus.Store.State()
local firstId=type(before.firstRunWishlist)=='table' and before.firstRunWishlist.assignmentId
check(type(firstId)=='string' and (before.loadoutWishlists or {})[2]==nil,'4 SETUP: a first-run plan and no association for Saved Build 2')
H.perks.serverBuildSlots={[2]={name='Loadout two',verified=true,echoes={{spellId=200001,quality=1,stacks=1}}}}
H.perks.serverActiveSlot=2
Later();takes=H.Count('take');spends=H.Count('orb-spend')
w=Measure(M.Pump)
c=State()
local after=Nexus.Store.State()
local handoff=(after.loadoutWishlists or {})[2]
check(type(handoff)=='table' and handoff.assignmentId==firstId,
 '4 REENTRANT: the pump read wrote the hand-off with the same assignment identity: '..tostring(handoff and handoff.assignmentId)..' / '..tostring(firstId))
check(w.pumps==1 and w.outside==1 and w.inside==0,'4 the pump reads the assignment once: '..w.outside..' '..w.inside)
check(H.Count('take')==takes and H.Count('orb-spend')==spends and c.state=='PAUSED' and c.pending==true and c.reason==LOADOUT,
 '4 the pump pauses on the changed loadout and sends nothing: state='..tostring(c.state)..' reason='..tostring(c.reason))

M.Pump,A.AssignedWishlist,A.Orbs.Spend,A.Orbs.Select=rawPump,rawAssigned,rawSpend,rawSelect
UnitGUID=rawGUID
print('PASS Orb pump authority: fresh Spend/Select preconditions, paused and resumed selection, between-pump changes and the reentrant hand-off; '..checks..' checks')
