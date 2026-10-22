-- Diagnostic choice presence is separate from Orb execution and action latches.
-- Real TOC, adapter, runtime and report builder; synthetic services only.
local H=dofile('tests/prototype/orbs_support.lua')
local initial=assert(Nexus.SupportReport.Prepare({}))
assert(table.concat(initial.chunks,''):find('Echo choice: presence=unknown',1,true),
 'a never-observed choice is explicitly unknown in the report')
H.OrbPlan()
H.Board({{spellId=410001,quality=1},{spellId=410003,quality=0},{spellId=410004,quality=3}})
H.O.offer=false
H.perks.pendingSelectSpellId=nil
local status=H.M.Status()
assert(status.state=='IDLE' and status.running==false and status.pending==false,
 'fixture: an ordinary choice can exist while the Orb runner is idle')
local view=Nexus.GameAdapter.ChoicePresenceView()
assert(view.choicePresence=='present',
 'an open ordinary choice must be reported as present even with an idle runner')
assert(view.choiceCount==3,'the observation reports the three actual choices')
local report=assert(Nexus.SupportReport.Prepare({}))
assert(table.concat(report.chunks,''):find('Echo choice: presence=present',1,true),
 'the prepared support report exposes observed choice presence')
H.perks.currentChoice={}
H.M.Status()
view=Nexus.GameAdapter.ChoicePresenceView()
assert(view.choicePresence=='absent' and view.choiceCount==0,
 'an explicit valid empty choice table is observed absence')
local service=ProjectEbonhold.PerkService
local getter=service.GetCurrentChoice
H.perks.currentChoice=nil
H.M.Status()
view=Nexus.GameAdapter.ChoicePresenceView()
assert(view.choicePresence=='unknown' and view.choiceCount==nil,
 'a nil API result is not a confirmed empty choice table')
service.GetCurrentChoice=function()error('SYNTHETIC_PRIVATE_CHOICE_ERROR')end
H.M.Status()
view=Nexus.GameAdapter.ChoicePresenceView()
assert(view.choicePresence=='unknown' and view.choiceCount==nil and H.M.ReadinessView().stage=='choice',
 'a failed choice getter reports unknown and its refusal stage')
report=assert(Nexus.SupportReport.Prepare({}))
local text=table.concat(report.chunks,'')
assert(text:find('Echo choice: presence=unknown',1,true)
 and not text:find('SYNTHETIC_PRIVATE_CHOICE_ERROR',1,true),
 'the report retains unknown without leaking raw getter errors')
service.GetCurrentChoice=nil
H.M.Status()
view=Nexus.GameAdapter.ChoicePresenceView()
assert(view.choicePresence=='unknown' and view.choiceCount==nil and H.M.ReadinessView().stage=='capability',
 'an unavailable API cannot become observed absence')
service.GetCurrentChoice=getter
H.perks.currentChoice={unexpected={spellId=410001,quality=1}}
H.M.Status()
view=Nexus.GameAdapter.ChoicePresenceView()
assert(view.choicePresence=='unknown' and view.choiceCount==nil,
 'a non-array choice response is not confirmed empty just because ipairs skipped it')
H.perks.currentChoice={}
H.M.Status()
local sample=Nexus.GameAdapter.ChoicePresenceView()
H.now=H.now+2
view=Nexus.GameAdapter.ChoicePresenceView()
assert(view.choicePresence=='unknown' and view.lastChoicePresence=='absent'
 and view.choiceFreshness=='stale' and view.at==sample.at,
 'an aging frozen sample retains history but must not report current absence')
H.M.Status()
sample=Nexus.GameAdapter.ChoicePresenceView()
H.Fire('PLAYER_LEAVING_WORLD')
view=Nexus.GameAdapter.ChoicePresenceView()
assert(view.choicePresence=='unknown' and view.choiceFreshness=='transition'
 and view.at==sample.at and view.lastChoicePresence=='absent',
 'loading invalidates current absence even when no Orb run ever started')
H.Fire('PLAYER_ENTERING_WORLD')
view=Nexus.GameAdapter.ChoicePresenceView()
assert(view.choicePresence=='unknown' and view.choiceFreshness=='transition',
 'world entry does not refresh the old captured choice observation')
H.M.Status()
view=Nexus.GameAdapter.ChoicePresenceView()
assert(view.choicePresence=='absent' and view.choiceFreshness=='recent'
 and view.choiceSampleEpoch==view.choiceCurrentEpoch,
 'a new ordinary read belongs to the new client epoch, without claiming server freshness')
local clock=H.now
for _,badClock in ipairs({1/0,0/0,clock-1}) do
 H.now=badClock
 view=Nexus.GameAdapter.ChoicePresenceView()
 assert(view.choicePresence=='unknown' and view.choiceFreshness=='unknown',
  'an unavailable or regressed client clock cannot assert recent absence or a known stale age')
end
H.now=clock
local getTime=GetTime
GetTime=nil
H.M.Status()
view=Nexus.GameAdapter.ChoicePresenceView()
assert(view.choicePresence=='unknown' and view.choiceFreshness=='unknown'
 and view.choiceObservedAt==nil,
 'an absent client clock is unavailable rather than an invented time zero')
GetTime=getTime
H.M.Status()
H.Board({{spellId=410001,quality=1},{spellId=410003,quality=0},{spellId=410004,quality=3}})
H.O.offer=false
H.M.Status()
local assignment=Nexus.GameAdapter.AssignedWishlist
Nexus.GameAdapter.AssignedWishlist=function()error('SYNTHETIC_PRE_OBSERVATION_ERROR')end
local success=pcall(H.M.Status)
Nexus.GameAdapter.AssignedWishlist=assignment
view=Nexus.GameAdapter.ChoicePresenceView()
assert(not success and view.choicePresence=='unknown' and view.lastChoicePresence=='present',
 'a failed ordinary read cannot leave a prior choice asserted as current')
H.M.Status()
H.M.Stop()
status=H.M.Status()
view=Nexus.GameAdapter.ChoicePresenceView()
assert(status.state=='STOPPED' and not status.running and view.choicePresence=='present',
 'a deliberate Orb Stop does not resolve an ordinary open choice')
assert(H.Count('orb-spend')==0 and H.Count('take')==0,
 'observing and preparing a report sends no Orb or choice')
-- A bounded summary must keep unresolved action/spend evidence ahead of the
-- additional passive choice context, even after a large incident history.
local budgetH=dofile('tests/prototype/orbs_support.lua')
budgetH.OrbPlan();budgetH.Approve(1,false);budgetH.M.Stop()
local budgetStatus=budgetH.M.Status()
assert(budgetStatus.pending and budgetStatus.state=='STOPPED' and budgetStatus.reserved==1,
 'budget fixture: a deliberate Stop retains one unresolved fake operation')
Nexus.SupportIncidents.Clear()
local readiness={}
for i=1,12 do readiness['source'..i]=string.rep('d',147)end
for i=1,20 do
 Nexus.SupportIncidents.Record('catalog-refusal',{
  reason=string.rep('r',96)..i,producer=string.rep('p',96),
  operation='budget fixture',counts={ordinary=80,locked=0,total=80},
  readiness=readiness,committed=false})
end
local summary=Nexus.SupportReport.Summary()
assert(#summary>7500 and #summary<=Nexus.SupportReport.SUMMARY_MAX_BYTES
 and (summary:find('context line(s) omitted',1,true)
  or summary:find('summary shortened to stay under',1,true)),
 'fixture reaches the summary budget and reports omitted context')
assert(summary:find('Orb action: unresolved in this session; state=STOPPED',1,true)
 and summary:find('client-observed spend=no; choice=none',1,true),
 'near-budget summary keeps the unresolved receipt and spend evidence before passive choice context')
assert(budgetH.Count('orb-spend')==1 and budgetH.Count('take')==0,
 'preparing the near-budget summary adds no action to the single fixture spend')

print('PASS orb_choice_observation')
