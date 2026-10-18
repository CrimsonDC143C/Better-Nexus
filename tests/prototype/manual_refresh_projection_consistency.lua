-- Projection consistency after Echo mirror changes that only a static rebuild
-- reconciles (manual refresh F1). A step whose static context is rebuilt
-- (a forced recompute, an in-session world entry) captures the fallback
-- signature, and that capture reconciles the Echo mirrors after ConsumeDirty
-- keyed the poll's projections. The projections the step then renders, and
-- that Main caches under the now-current revisions, must not predate that
-- reconciliation (core/AutomationRuntime.lua StaticContext).
--
-- Categories (tests/prototype/view_regression_support.lua): SETUP is the
-- fixture or an attribution fact; EXPECT is the corrected behaviour, read from
-- source as not holding on the uncorrected tree; GUARD holds before and after
-- the correction and must keep holding (warm reuse, local revision
-- invalidation, fallback cadence, steady state, adapters without the revision
-- contract or the fallback signature, one ConsumeDirty per poll, no Nexus
-- host action). The run decides; nothing here is a native result.
--
-- Real TOC boot (progress_refresh_support/format5_support), real GameAdapter,
-- AutomationRuntime, Main and Panel; synthetic host. A manual game action is
-- the native call the game UI makes plus the server reply as a replaced client
-- mirror, with no client callback ("silent"). Level 80, Auto OFF, Sync manual,
-- an OrbService present; synthetic Echo ids only.
local S=dofile('tests/prototype/progress_refresh_support.lua')
local V=dofile('tests/prototype/view_regression_support.lua')
local F=S.F
local C=V.Checker('manual_refresh_projection_consistency')

local TOME=777019
local function E(i) return 200000+i end
local function Range(a,b) local t={} for i=a,b do t[#t+1]=i end return t end
local EXTRAS=Range(51,60)
local function Counts(...)
 local c={}
 for _,list in ipairs({...}) do
  for _,i in ipairs(list) do c[E(i)]=(c[E(i)] or 0)+1 end
 end
 return c
end
local W
do
 local spec={}
 for i=11,19 do spec[#spec+1]={E(i),1,false} end
 W=S.Rows(spec) -- Echo 11-19, one ordinary copy each; Echo 19 needs a tome
end
local function Boot(counts)
 return S.Boot({granted=counts,locked={},active=2,
  slots={[2]={name='Build Two',verified=true,echoes=S.SlotRows(counts)},
   [101]={name='Synthetic W',verified=false,echoes=S.Copy(W)}},
  associations={[2]=S.Association(101,'Synthetic W',W)},
  before=function(h)
   h.db[E(19)].requiredSpell=TOME
   h.names[TOME]='Tome of Echo 19'
   h.perks.discoveredEchoes=h.discovered
   F.OrbService(h)
  end})
end

local function Progress()
 local m=Nexus.Panel and Nexus.Panel._lastModel
 return type(m)=='table' and type(m.progress)=='table' and m.progress or {}
end
local function Needed()
 local out={}
 for _,label in ipairs(type(Progress().missing)=='table' and Progress().missing or {}) do
  out[#out+1]=tonumber(tostring(label):match('^Echo (%d+)')) or -1
 end
 table.sort(out)
 return out
end
local function Same(a,b)
 if #a~=#b then return false end
 for i=1,#a do if a[i]~=b[i] then return false end end
 return true
end
local function Show(a) local t={} for i,v in ipairs(a) do t[i]=tostring(v) end return '{'..table.concat(t,',')..'}' end
local function Has(list,name)
 for _,v in ipairs(type(list)=='table' and list or {}) do if v==name then return true end end
 return false
end
-- Runtime counters: phaseCounts.owned/locked/slots/levers move only when
-- ReadProjection really calls its getter (a cache miss or no revision contract).
local function Stats()
 local r=Nexus.RecomputeStats() or {}
 local e=Nexus.GameAdapter.EchoReconcileStats()
 local g,pc,m,c=e.generations or {},r.phaseCounts or {},r.fallbackMismatchFields or {},r.lastStepContext or {}
 return {steps=r.fullSteps or 0,polls=r.polls or 0,pollFailures=r.pollFailures or 0,
  stepFailures=r.stepFailures or 0,repairs=r.fallbackRepairs or 0,staticProbes=r.staticProbes or 0,
  grantedMismatch=m.granted or 0,trigger=tostring(c.trigger),staticProbe=c.staticProbe==true,
  notes=e.notifications or 0,granted=g.granted or 0,locked=g.locked or 0,slots=g.slots or 0,
  discovery=g.discovery or 0,readOwned=pc.owned or 0,readLocked=pc.locked or 0,
  readSlots=pc.slots or 0,readLevers=pc.levers or 0}
end
local function Moves(a,b)
 return 'granted '..a.granted..'->'..b.granted..' slots '..a.slots..'->'..b.slots..' discovery '..a.discovery..'->'..b.discovery
  ..' | reads owned '..a.readOwned..'->'..b.readOwned..' locked '..a.readLocked..'->'..b.readLocked
  ..' slots '..a.readSlots..'->'..b.readSlots..' levers '..a.readLevers..'->'..b.readLevers
  ..' | step '..b.trigger..(b.staticProbe and '+static' or '')..' callbacks '..a.notes..'->'..b.notes
end
local function OwnedRevision() local _,_,_,r=Nexus.GameAdapter.PresentationRevisions();return r end
local function GetterOwns(i,n)
 local o=Nexus.GameAdapter.Owned()
 return o.synced==true and (o.bySpell[E(i)] or 0)==n
end
local function Diag(label)
 local p=Progress()
 print('DIAG '..label..': needed='..Show(Needed())..' owned='..tostring(p.owned)..'/'..tostring(p.total)
  ..' savedBuildLocked='..table.concat(type(p.locked)=='table' and p.locked or {},',')
  ..' unknownTomes='..tostring(type(p.unknownTomes)=='table' and #p.unknownTomes or nil))
end
local function AfterFallbackCheck(H)
 local at=Nexus.RecomputeStats().lastFallbackCheckAt
 for _=1,160 do
  H.Advance(.05,.05)
  if Nexus.RecomputeStats().lastFallbackCheckAt~=at then return true end
 end
 return false
end
local function FirstStep(H,limit)
 local n,start=Stats().steps,H.now
 while H.now-start<limit-1e-9 do
  H.Advance(.05,.05)
  if Stats().steps>n then return H.now-start end
 end
 return nil
end
local function Leave(H) H.Fire('PLAYER_LEAVING_WORLD');H.Advance(.5,.05) end
local function Enter(H) H.Fire('PLAYER_ENTERING_WORLD') end
local function Player(H)
 local p={actions=#H.actions,sent=#H.sent,own=0}
 function p.native(label,writes,fn)
  local before=#H.actions
  local ok,err=pcall(fn)
  C.setup(ok and #H.actions-before==writes,'the player\'s native '..label..' reached the host',ok and (#H.actions-before) or err)
  p.own=p.own+writes
 end
 function p.quiet(label)
  local kinds={}
  for i=p.actions+1,#H.actions do kinds[#kinds+1]=tostring(H.actions[i][1]) end
  C.guard(#H.actions-p.actions==p.own,label..': Nexus made no host write of its own; host writes are the player\'s '..p.own,table.concat(kinds,','))
  C.guard(#H.sent==p.sent,label..': Nexus sent no chat or addon message',#H.sent-p.sent)
 end
 return p
end

C.scenario('warm reuse, local revision, forced recompute and world entry',function()
 local H=Boot(Counts({11,12,13},EXTRAS))
 C.setup(Same(Needed(),Range(14,19)) and Progress().owned==3 and Progress().total==9,'fixture: 3/9, Echo 14-19 still needed',Show(Needed()))
 C.setup(type(Progress().locked)=='table' and #Progress().locked==0,'fixture: the active Saved Build holds no locked Echo')
 local A=Nexus.GameAdapter
 local realConsume,consumed=A.ConsumeDirty,0
 A.ConsumeDirty=function(...) consumed=consumed+1;return realConsume(...) end
 local s00=Stats()
 local p=Player(H)

 -- No change: a world entry rebuilds the static context and reuses every projection.
 C.setup(AfterFallbackCheck(H),'synchronised after a fallback check')
 local s0=Stats()
 Leave(H);Enter(H)
 local dt=FirstStep(H,1)
 local s1=Stats()
 C.setup(dt~=nil and s1.staticProbe,'no-change world entry: its first step rebuilt the static context',Moves(s0,s1))
 C.guard(s1.granted==s0.granted and s1.locked==s0.locked and s1.slots==s0.slots and s1.discovery==s0.discovery
  and s1.readOwned==s0.readOwned and s1.readLocked==s0.readLocked and s1.readSlots==s0.readSlots
  and s1.readLevers==s0.readLevers,'no-change world entry: no generation moved and every projection was reused warm',Moves(s0,s1))
 C.guard(Same(Needed(),Range(14,19)),'no-change world entry: STILL NEEDED unchanged',Show(Needed()))

 -- Local revision: the player's pick in the game's Orb offer (hooked
 -- SelectPerk) re-reads the owned projection with no generation change.
 p.native('OrbService.ConfirmSpend(Echo 51)',1,function() return ProjectEbonhold.OrbService.ConfirmSpend(E(51),1) end)
 H.orbs.offer=true;H.orbs.charges=H.orbs.charges-1
 H.Board({{spellId=E(14),quality=S.Q(E(14))},{spellId=E(61),quality=S.Q(E(61))},{spellId=E(62),quality=S.Q(E(62))}})
 H.Advance(.3)
 s0=Stats();local r0=OwnedRevision()
 p.native('PerkService.SelectPerk(Echo 14)',1,function() return ProjectEbonhold.PerkService.SelectPerk(E(14)) end)
 C.setup(OwnedRevision()==r0+1,'manual pick: Nexus\'s SelectPerk hook raised the local owned revision',tostring(r0)..'->'..tostring(OwnedRevision()))
 dt=FirstStep(H,1)
 s1=Stats()
 C.guard(dt~=nil and s1.granted==s0.granted and s1.readOwned==s0.readOwned+1,
  'local revision: the next step read the owned projection again although no generation moved',Moves(s0,s1))

 -- The server settles the pick silently; a forced recompute (the Wishlist
 -- editor's and AutoLock retry's entry) is the next step.
 C.setup(AfterFallbackCheck(H),'synchronised after a fallback check')
 s0=Stats();r0=OwnedRevision()
 H.perks.pendingSelectSpellId=nil;H.perks.currentChoice=nil;H.orbs.offer=false
 H.granted=S.Granted(Counts({11,12,13,14},Range(52,60)))
 Nexus.RequestRecompute()
 dt=FirstStep(H,1)
 s1=Stats()
 C.setup(dt~=nil and s1.trigger=='forced' and s1.staticProbe and s1.granted==s0.granted+1
  and s1.notes==s0.notes and OwnedRevision()==r0,
  'forced recompute: its static rebuild reconciled the silent settlement itself (granted +1, no callback, no confirmation)',Moves(s0,s1))
 C.setup(GetterOwns(14,1) and GetterOwns(51,0),'forced recompute: Nexus\'s own getter reads Echo 14 owned and Echo 51 spent')
 Diag('forced recompute, first step')
 C.expect(Same(Needed(),Range(15,19)),'forced recompute after a silent manual Orb pick: the step renders what the getter reads (Echo 15-19)',Show(Needed()))
 C.expect(s1.readOwned==s0.readOwned+1,'forced recompute: the owned projection was read again in that step',Moves(s0,s1))
 H.Advance(6)
 C.expect(Same(Needed(),Range(15,19)),'forced recompute: STILL NEEDED keeps it through the next fallback period',Show(Needed()))

 -- World entry after a silent Saved Build save of the run (Echo 11 kept
 -- locked in that build), a silent grant and a silent tome discovery.
 C.setup(AfterFallbackCheck(H),'synchronised after a fallback check')
 s0=Stats();r0=OwnedRevision()
 local saved=Counts({11,12,13,14,15},Range(52,60))
 p.native('PerkService.SaveServerBuildSlot(2)',1,function() return ProjectEbonhold.PerkService.SaveServerBuildSlot(2,'Build Two') end)
 local rows=S.SlotRows(saved)
 for _,e in ipairs(rows) do if e.spellId==E(11) then e.locked=true end end
 H.perks.serverBuildSlots[2]={name='Build Two',verified=true,echoes=rows}
 H.granted=S.Granted(saved)
 H.discovered[E(19)]=true
 Leave(H)
 local sl=Stats()
 C.setup(sl.granted==s0.granted and sl.slots==s0.slots and sl.discovery==s0.discovery and OwnedRevision()==r0,
  'world entry: nothing reconciled the silent changes before it',Moves(s0,sl))
 Enter(H)
 dt=FirstStep(H,1)
 s1=Stats()
 C.setup(dt~=nil and s1.staticProbe and s1.granted==s0.granted+1 and s1.slots==s0.slots+1
  and s1.discovery==s0.discovery+1 and s1.notes==s0.notes,
  'world entry: its static rebuild reconciled the granted, slot and discovery changes itself',Moves(s0,s1))
 C.setup(Progress().wishlistName=='Synthetic W' and Progress().total==9,'world entry: the assignment is unchanged',S.Text(S.Hud()))
 Diag('world entry, first step')
 C.expect(Same(Needed(),Range(16,19)),'world entry: STILL NEEDED renders the silent grant (Echo 16-19)',Show(Needed()))
 C.expect(Has(Progress().locked,'Echo 11'),'world entry: the Saved Build row is read in that step (Echo 11 kept locked there)',
  table.concat(type(Progress().locked)=='table' and Progress().locked or {},','))
 C.expect(s1.readLevers==s0.readLevers+1,'world entry: the disabled-lever projection was read again after its discovery generation moved',Moves(s0,s1))
 C.guard(type(Progress().unknownTomes)=='table' and #Progress().unknownTomes==0,'world entry: MISSING TOMES clears (a live read in the progress model)')

 -- Fallback only: a silent grant with no static rebuild is still repaired on its cadence.
 C.setup(AfterFallbackCheck(H),'synchronised after a fallback check')
 s0=Stats()
 H.granted=S.Granted(Counts({11,12,13,14,15,16},Range(52,60)))
 local t=S.Within(H,5.5,function() return Same(Needed(),Range(17,19)) end)
 s1=Stats()
 C.guard(t~=nil and s1.notes==s0.notes and s1.repairs>s0.repairs and s1.grantedMismatch>s0.grantedMismatch,
  'fallback cadence: a silent grant alone is repaired by the five-second fallback',tostring(t)..' s; '..Moves(s0,s1))

 -- Steady state: nothing changes, nothing is redone.
 H.Advance(6)
 s0=Stats()
 H.Advance(30)
 s1=Stats()
 C.guard(s1.repairs==s0.repairs and s1.staticProbes==s0.staticProbes and s1.steps==s0.steps
  and s1.readOwned==s0.readOwned and s1.readLocked==s0.readLocked and s1.readSlots==s0.readSlots
  and s1.readLevers==s0.readLevers,'steady state for 30 s: no repair, static rebuild, step or projection read',Moves(s0,s1))

 local sEnd=Stats()
 C.guard(consumed==sEnd.polls-s00.polls and sEnd.pollFailures==s00.pollFailures,
  'one ConsumeDirty per poll (never a second call)',consumed..' calls, '..(sEnd.polls-s00.polls)..' polls')
 A.ConsumeDirty=realConsume
 p.quiet('consistency')
end)

C.scenario('adapters without the revision contract or the fallback signature',function()
 local H=Boot(Counts({11,12,13},EXTRAS))
 C.setup(Same(Needed(),Range(14,19)),'fixture: STILL NEEDED lists Echo 14-19',Show(Needed()))
 local A=Nexus.GameAdapter
 local p=Player(H)

 -- An adapter whose ConsumeDirty returns only the three dirty bits: the
 -- runtime caches no projection, so the correction has nothing to drop.
 local realConsume,consumed=A.ConsumeDirty,0
 A.ConsumeDirty=function() consumed=consumed+1;local b,s,d=realConsume();return b,s,d end
 local s00=Stats()
 C.setup(AfterFallbackCheck(H),'synchronised after a fallback check')
 H.granted=S.Granted(Counts({11,12,13,14},EXTRAS))
 Leave(H);Enter(H)
 local dt=FirstStep(H,1)
 local s1=Stats()
 C.guard(dt~=nil and Same(Needed(),Range(15,19)),'no revision contract: uncached projections show the silent change at the first step after world entry',Show(Needed()))
 C.guard(s1.stepFailures==s00.stepFailures and s1.pollFailures==s00.pollFailures,'no revision contract: no step or poll failure')
 C.guard(consumed==s1.polls-s00.polls,'no revision contract: one ConsumeDirty per poll',consumed..' calls, '..(s1.polls-s00.polls)..' polls')
 A.ConsumeDirty=realConsume
 H.Advance(.5)

 -- An adapter without AutomationSignature: no capture, so the correction is
 -- inert, and the fallback repairs on its cadence as it always did.
 local realSignature=A.AutomationSignature
 A.AutomationSignature=nil
 local s0=Stats()
 H.Advance(6)
 s1=Stats()
 C.guard(s1.stepFailures==s0.stepFailures and s1.pollFailures==s0.pollFailures,'no fallback signature: steps and polls run without failure')
 C.guard(s1.repairs>s0.repairs,'no fallback signature: the fallback still runs on its cadence',s0.repairs..'->'..s1.repairs)
 A.AutomationSignature=realSignature
 H.Advance(6)
 C.guard(Same(Needed(),Range(15,19)),'signature restored: STILL NEEDED still reads the getter state',Show(Needed()))
 p.quiet('minimal adapters')
end)

C.finish('warm reuse, local revision, forced recompute, world entry, fallback cadence, steady state and minimal adapters')
