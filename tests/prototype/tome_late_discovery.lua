-- A present discovery mirror need not contain every tome yet. An off-plan
-- control skipped as unknown must become eligible when a later ordinary
-- evaluation can read a known member, without a run boundary or runtime reload.
-- Real TOC, runtime, adapter and Journal name callbacks; synthetic host only.
local S=dofile('tests/prototype/saved_build_wishlist_transition_support.lua')
local rawDofile=dofile
local ECHO={300501,300502}
local LEVER={777501,777502}
local WAIT,TICK,DELAY=12,.05,.9
local checks,failures=0,{}
local function setup(value,message)assert(value,'SETUP: '..message)end
local function expect(value,message)
 checks=checks+1
 if not value then failures[#failures+1]=message;print('MISS '..message)end
end
local function up(fn,wanted)
 for i=1,255 do
  local name,value=debug.getupvalue(fn,i)
  if not name then break end
  if name==wanted then return value end
 end
end
local function runtime()
 local owner=up(Nexus.RecomputeStats,'Automation')
 local ensure=owner and up(owner,'EnsureAutomationRuntime')
 return ensure and up(ensure,'AutomationRuntime')
end
local function vector(H)return {H.disabled[ECHO[1]]==true,H.disabled[ECHO[2]]==true}end
local function show(v)return tostring(v[1])..','..tostring(v[2])end
local function World(kind)
 local F={kind=kind,boots=0,calls={},replies={},queue={},phase=0,readUnavailable=false,discoveryReads=0}
 dofile=function(path)
  local result=rawDofile(path)
  if path=='tests/prototype/harness.lua'then
   local H=result
   local boot=H.Boot
   H.Boot=function()
    F.boots=F.boots+1
    wipe(H.db)
    H.AddEcho(200001,'Late Discovery Common Echo',1,1,0)
    for i,id in ipairs(ECHO)do
     H.AddEcho(id,'Late Discovery Echo '..i,1,1,0)
     H.db[id].requiredSpell=LEVER[i]
     H.names[LEVER[i]]='Tome of Late Discovery Echo '..i
     H.disabled[id]=false
     if kind=='unavailable_read'then H.discovered[id]=true end
    end
    H.perks.discoveredEchoes=H.discovered
    H.perks.serverActiveSlot=1
    H.perks.serverBuildSlots={
     [1]={name='Late Discovery Saved Build',verified=true,echoes={{spellId=200001,quality=1,stacks=1}}},
     [101]={name='Late Discovery A',verified=false,echoes={{spellId=ECHO[1],quality=1,stacks=1,locked=false}}},
     [102]={name='Late Discovery B',verified=false,echoes={{spellId=ECHO[2],quality=1,stacks=1,locked=false}}},
    }
    local read=H.service.GetDiscoveredEchoes
    setup(type(read)=='function','host discovery getter exists')
    H.service.GetDiscoveredEchoes=function(...)
     F.discoveryReads=F.discoveryReads+1
     if F.readUnavailable then return nil end
     return read(...)
    end
    local toggle=H.service.ToggleTomeEcho
    H.service.ToggleTomeEcho=function(id)
     local accepted=toggle(id)
     if accepted then
      local request={id=id,want=not(H.disabled[id]==true),at=H.now,phase=F.phase}
      F.calls[#F.calls+1]=request
      F.queue[#F.queue+1]={id=id,want=request.want,due=H.now+DELAY,phase=F.phase}
     end
     return accepted
    end
    local mirror=CreateFrame('Frame',nil,UIParent)
    mirror:SetScript('OnUpdate',function()
     for i=#F.queue,1,-1 do
      local reply=F.queue[i]
      if H.now>=reply.due then
       H.disabled[reply.id]=reply.want
       F.replies[#F.replies+1]={id=reply.id,want=reply.want,at=H.now,phase=reply.phase}
       table.remove(F.queue,i)
       H.Notify() -- a successful host mirror change, not an assignment event
      end
     end
    end)
    return boot()
   end
  end
  return result
 end
 local good,W=pcall(S.World,{level=1})
 dofile=rawDofile
 setup(good,'real TOC world: '..tostring(W))
 local H,A=W.H,W.A
 W.F=F
 setup(H.playerLevel==1 and F.boots==1,'one level-one boot')
 setup(type(H.perks.discoveredEchoes)=='table','discovery mirror is present')
 setup(A.DiscoverySynced()==true,'present discovery mirror passes the global sync gate')
 setup(A.OrdinaryBoardAllowed()==true and A.TomeMutationPaused()==false,'other action gates open')
 setup(H.disabled[ECHO[1]]==false and H.disabled[ECHO[2]]==false,'both actual tome mirrors start enabled')
 if kind=='empty_mirror'then
  setup(next(H.perks.discoveredEchoes)==nil,'initial mirror is empty')
 else
  setup(H.discovered[ECHO[1]]==true and H.discovered[ECHO[2]]==true,'underlying mirror already knows both controls')
  F.readUnavailable=true -- transient host getter failure, no discovery revision promised
 end
 for _,lever in ipairs(LEVER)do setup(A.LeverHasKnownMember(lever)==false,'initial member read is unknown')end
 local changed,why=Nexus.MainInternals.StoreAuthorityOwner.UpdateSettingsV1('autoDisable',true)
 setup(changed~=nil and Nexus.Store.Settings().autoDisable==true,'explicit tome permission: '..tostring(why))
 setup(Nexus.RecomputeStats().autoEnabled==false,'Auto starts OFF')
 W.runtime=runtime()
 setup(type(W.runtime)=='table','cached runtime exists')
 SlashCmdList.NEXUS('auto')
 setup(W.runtime.AutoEnabled()==true and #F.calls==0,'explicit Auto ON before first action tick')
 return W
end
-- Since M3 (UX-05) a pick for a numbered Saved Build with Echoes while Auto is
-- selected asks first with the real confirmation; this synthetic player checks
-- it and answers Assign (the dialog's own OnAccept, as the client runs it).
-- The expectation comes from the scenario (Auto state, Saved Build 1 with
-- Echoes), never from the dialog: a missing or different confirmation, or a
-- dialog where none is expected, fails the fixture. Only the raw Store
-- association is read between the click and the answer (no assignment,
-- slot, Progress or display observer).
local CONSENT='NEXUS_ASSIGN_WISHLIST_AUTO_ON'
local function Association()
 local links=Nexus.Store.State().loadoutWishlists
 local record=type(links)=='table' and links[1] or nil
 if type(record)~='table' then return tostring(record) end
 return tostring(record.slot)..'/'..tostring(record.name)..'/'..tostring(record.assignmentId)
end
local function Pick(W,key)
 local picker=assert(S.OpenPicker(),'SETUP: real Journal selector opens')
 local row=assert(S.PickerRow('Late Discovery '..key),'SETUP: real Journal offers '..key)
 local H=W.H
 local target=type(H.perks.serverBuildSlots)=='table' and H.perks.serverBuildSlots[1] or nil
 local auto=W.runtime.AutoEnabled()==true
 local asks=auto and tonumber(H.perks.serverActiveSlot)==1 and type(target)=='table' and #(target.echoes or {})>0
 local prior=Association()
 H.popup=nil
 row.nameButton:Click()
 local p=H.popup
 if asks then
  setup(p~=nil and p.which==CONSENT,'Auto-ON pick asks with the real assignment confirmation: '..tostring(p and p.which))
  local d=StaticPopupDialogs[CONSENT]
  setup(type(d)=='table','the confirmation dialog is defined')
  local wishlist,where='Late Discovery '..key,"Saved Build '"..tostring(target.name).."'"
  local ok,asked=pcall(string.format,tostring(d.text),p.arg1,p.arg2)
  setup(d.button1=='Assign' and d.button2=='Cancel','confirmation buttons are Assign and Cancel')
  setup(p.arg1==wishlist and p.arg2==where,'confirmation names the picked Wishlist and the captured Saved Build: '
   ..tostring(p.arg1)..' / '..tostring(p.arg2))
  setup(ok and asked:find("Assign '"..wishlist.."' to "..where.."?",1,true)==1
   and asked:find('Auto is ON',1,true)~=nil and asked:find('Cancel changes nothing',1,true)~=nil,
   'confirmation title and Auto consequence: '..tostring(asked))
  setup(picker:IsShown() and Association()==prior,'nothing is assigned before the answer')
  H.popup=nil
  d.OnAccept(p.frame,p.data)
 else
  setup(p==nil,'no dialog for this pick: '..tostring(p and p.which))
 end
 setup(not picker:IsShown(),'real name callback closes its picker')
 setup((W.runtime.AutoEnabled()==true)==auto,'picking changes no Auto state')
 ProjectEbonholdEchoJournal:Hide()
end
local function Pending()
 local map=Nexus.Store.State().tomeTogglePending or{}
 return map,next(map)==nil
end
local function Phase(W,label,action,key,want)
 local H,F=W.H,W.F
 F.phase=F.phase+1
 local before,start,replyStart=vector(H),#F.calls,#F.replies
 if action then action()end
 H.Advance(WAIT,TICK)
 -- Raw host evidence first. No assignment, slot, Progress or display read
 -- is used to make these state/request assertions succeed.
 local after=vector(H)
 local pending,empty=Pending()
 print('TRACE '..F.kind..' '..label..' disabled={'..show(after)..'} want={'..show(want)..'}'
  ..' accepted='..(#F.calls-start)..' replies='..(#F.replies-replyStart)
  ..' pendingEmpty='..tostring(empty)..' discoveryReads='..F.discoveryReads)
 for i,id in ipairs(ECHO)do
  expect(after[i]==want[i],F.kind..' '..label..' actual disabled state '..id)
  local count=0
  for n=start+1,#F.calls do
   local request=F.calls[n]
   if request.id==id then
    count=count+1
    expect(request.want==want[i],F.kind..' '..label..' request direction '..id)
   end
  end
  local expected=before[i]~=want[i]and 1 or 0
  expect(count==expected,F.kind..' '..label..' exact necessary request count '..id..' got '..count..' want '..expected)
 end
 expect(empty and #F.queue==0,F.kind..' '..label..' requests await actual replies before settling')
 expect(F.boots==1 and runtime()==W.runtime and H.playerLevel==1,F.kind..' '..label..' original boot/runtime/level retained')
 -- This observer runs after the raw verdict, never between a click and wait.
 local assigned=W.A.AssignedWishlist()or{}
 expect(assigned.state=='ready'and assigned.name=='Late Discovery '..key,F.kind..' '..label..' exact assigned target')
 local stored=Nexus.Store.State().loadoutWishlists[1]
 expect(type(stored)=='table'and stored.slot==(key=='A'and 101 or 102),F.kind..' '..label..' SavedBuild1 association')
end
for _,kind in ipairs({'empty_mirror','unavailable_read'})do
 local W=World(kind)
 local H,F=W.H,W.F
 Phase(W,'unknown initial B',function()Pick(W,'B')end,'B',{false,false})
 -- Unknown controls send nothing and create no new half-second retry loop.
 local before=W.runtime.RecomputeStats()
 local reads,start=F.discoveryReads,#F.calls
 H.Advance(6,TICK)
 local after=W.runtime.RecomputeStats()
 expect(#F.calls==start and next(Nexus.Store.State().tomeTogglePending)==nil,kind..' stable unknown stays action-free')
 expect(after.fullSteps-before.fullSteps<=2,kind..' stable unknown does not add hot full-step retries')
 print('IDLE '..kind..' seconds=6 fullSteps='..(after.fullSteps-before.fullSteps)..' discoveryReads='..(F.discoveryReads-reads))
 if kind=='empty_mirror'then
  Phase(W,'discovery arrives without a boundary',function()
   H.discovered[ECHO[1]],H.discovered[ECHO[2]]=true,true
   H.Notify()
  end,'B',{true,false})
 else
  -- Recovery of the SAME underlying table is not a discovery event and
  -- promises no new generation. The following real assignments must retry
  -- eligibility normally, rather than inherit a durable "unknown" latch.
  F.readUnavailable=false
 end
 Phase(W,'Journal A',function()Pick(W,'A')end,'A',{false,true})
 Phase(W,'Journal B',function()Pick(W,'B')end,'B',{true,false})
 Phase(W,'Journal A again',function()Pick(W,'A')end,'A',{false,true})
 expect(W.runtime.AutoEnabled()==true and Nexus.Store.Settings().autoDisable==true,kind..' explicit permissions retained')
 expect(S.Writes(W)==0,kind..' no upload/save/activation')
 for i=2,#F.calls do expect(F.calls[i].at-F.calls[i-1].at>=.5-1e-6,kind..' accepted send spacing '..i)end
end
print('RESULT tome_late_discovery checks='..checks..' failures='..#failures)
assert(#failures==0,table.concat(failures,'\n'))
print('PASS late discovery and recovered discovery reads permit later real Journal tome reconciliation; accepted action pacing and stable unknown idle remain bounded')
