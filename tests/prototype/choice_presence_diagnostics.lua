-- Public seams, synthetic services. No native execution or private fixtures.
local H=dofile('tests/prototype/orbs_support.lua')
local A=Nexus.GameAdapter
local function text()return table.concat(assert(Nexus.SupportReport.Prepare({})).chunks,'')end
assert(type(A.ChoicePresenceView)=='function','ordinary choice observations have a passive view')
local view=A.ChoicePresenceView()
-- The normal harness startup already reads the board; a fresh owner is checked below.
assert(loadfile('core/OrbRuntime.lua'))('Nexus',{})
local runner=Nexus.OrbRuntime.RunnerView()
assert(runner.initialized==false and runner.pending==nil,'an uninitialized runner is not a measured no-receipt')
H.Board({{spellId=410001,quality=1},{spellId=410003,quality=0},{spellId=410004,quality=3}})
H.O.offer=false
local getter=ProjectEbonhold.PerkService.GetCurrentChoice
local reads=0
ProjectEbonhold.PerkService.GetCurrentChoice=function(...)reads=reads+1;return getter(...)end
local board=A.Board()
assert(board and #board.cards==3 and reads==1,'the ordinary board preserves one existing native read')
view=A.ChoicePresenceView()
assert(view.choicePresence=='present' and view.choiceCount==3,'ordinary choice is observed without an Orb plan')
local capability,status=A.Orbs.ServiceState()
assert(capability=='STATE_AWARE' and status=='IDLE','fixture: Orb offer is idle')
local service=A.Orbs.ServiceStateView()
assert(service.offer=='absent' and service.status=='IDLE','service sample is distinct from the ordinary board')
local report=text()
assert(report:find('Echo choice: presence=present',1,true)
 and report:find('Orb service: offer=absent',1,true)
 and report:find('Orb runner: initialized=no',1,true),'report keeps the three sources separate')
assert(report:find('Orb action: unknown',1,true)
 and not report:find('Orb action: none unresolved',1,true),'uninitialized state is not confirmed absence')
assert(Nexus.OrbRuntime.RunnerView().initialized==false and reads==1,'report collection initializes and reads nothing')
local svc=ProjectEbonhold.PerkService
local ordinaryGetter=svc.GetCurrentChoice
svc.GetCurrentChoice=function()error({{spellId=410001,quality=1}},0)end
assert(A.Board()==nil,'a table-valued API error must never become a gameplay board')
assert(A.ChoicePresenceView().choicePresence=='unknown','table-valued errors remain diagnostic unknown')
svc.GetCurrentChoice=ordinaryGetter
A.Board()
ProjectEbonhold.PerkService=setmetatable({},{__index=function()error('SYNTHETIC_MEMBER_ERROR')end})
local lookupOk=pcall(A.Board)
ProjectEbonhold.PerkService=svc
view=A.ChoicePresenceView()
assert(not lookupOk and view.choicePresence=='unknown' and view.lastChoicePresence=='present',
 'an interrupted service/member lookup invalidates currentness while retaining the preceding observation')
A.Board()
-- Failure class is historical evidence even after the sample stops being current.
-- Exercise the existing Board and full report seams; collection must not retry.
local failedCases={
 {'read_failed',function()error('SYNTHETIC_PRIVATE_CHOICE_FAILURE')end},
 {'nil_response',function()return nil end},
 {'malformed',function()return {unexpected={spellId=410001}}end},
 {'no_getter'}, {'no_service'},
}
local failures={}
local function expectFailureFact(ok,message)
 if not ok then failures[#failures+1]=message;print('FAIL '..message)end
end
for _,case in ipairs(failedCases)do
 local reason,calls=case[1],0
 ProjectEbonhold.PerkService=svc
 if reason=='no_service'then ProjectEbonhold.PerkService=nil
 elseif reason=='no_getter'then svc.GetCurrentChoice=nil
 else svc.GetCurrentChoice=function(...)calls=calls+1;return case[2](...)end end
 assert(A.Board()==nil,'failed fixture is not a gameplay board: '..reason)
 local sample=A.ChoicePresenceView()
 assert(sample.choicePresence=='unknown' and sample.choiceReason==reason,
  'the normal read classifies the fixture: '..reason)
 H.now=H.now+2
 local aged=A.ChoicePresenceView()
 expectFailureFact(aged.choicePresence=='unknown' and aged.choiceCount==nil
  and aged.choiceFreshness=='stale' and aged.choiceReason=='stale',
  reason..': aged failure does not assert current choice presence or absence')
 expectFailureFact(aged.lastChoiceReason==reason,
  reason..': stale view retains the original failure reason')
 local beforeCalls,beforeSerial,beforeAt=calls,aged.serial,aged.at
 local summary=Nexus.SupportReport.Summary()
 local prepared=text()
 for _,entry in ipairs({{'summary',summary},{'prepared',prepared}})do
  expectFailureFact(entry[2]:find('lastReason='..reason,1,true)~=nil,
   reason..': '..entry[1]..' retains the original failure reason')
  expectFailureFact(entry[2]:find('Echo choice: presence=unknown',1,true)~=nil
   and not entry[2]:find('SYNTHETIC_PRIVATE_CHOICE_FAILURE',1,true),
   reason..': '..entry[1]..' is unknown without the raw error')
 end
 local after=A.ChoicePresenceView()
 expectFailureFact(calls==beforeCalls and after.serial==beforeSerial and after.at==beforeAt
  and after.choicePresence=='unknown',
  reason..': summary and preparation do not resample the failure')
end
ProjectEbonhold.PerkService=svc;svc.GetCurrentChoice=ordinaryGetter
assert(#failures==0,'historical choice failures: '..table.concat(failures,'; '))
A.Board()

for _,case in ipairs({
 {'UNKNOWN',function()return false end,function()error('pending should not be read')end},
 {'INVALID',function()error('SYNTHETIC_SERVICE_ERROR')end,function()return false end},
 {'UNAVAILABLE',nil,function()return false end},
}) do
 ProjectEbonhold.OrbService.IsStateKnown=case[2];ProjectEbonhold.OrbService.IsOfferPending=case[3]
 local _,st=A.Orbs.ServiceState();service=A.Orbs.ServiceStateView()
 assert(st==case[1] and service.offer=='unknown','unavailable service state never becomes offer absence')
end
assert(H.Count('orb-spend')==0 and H.Count('take')==0,'diagnostics send no gameplay action')
-- Reload only the observer owner, with no startup calls, to check absence of
-- an observation independently of the harness's normal startup reads.
assert(loadfile('core/GameAdapter.lua'))('Nexus',{})
assert(Nexus.GameAdapter.ChoicePresenceView().observed==false,'no sample is invented on owner load')
print('PASS choice_presence_diagnostics')
