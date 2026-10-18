-- Synthetic-only host for tome observation regressions. Real TOC and Journal.
local S=dofile('tests/prototype/saved_build_wishlist_transition_support.lua')
local F={ECHO={300701,300702},LEVER={777701,777702}}
local rawDofile=dofile
function F.Up(fn,wanted)
 for i=1,255 do local n,v=debug.getupvalue(fn,i);if not n then break end;if n==wanted then return v,i end end
end
function F.Runtime()
 local owner=F.Up(Nexus.RecomputeStats,'Automation')
 local ensure=owner and F.Up(owner,'EnsureAutomationRuntime')
 return ensure and F.Up(ensure,'AutomationRuntime')
end
function F.Boot(mode,permission,auto,route)
 local O={boots=0,calls={},replies={},queue={},reads=0,mode=mode}
 dofile=function(path)
  local result=rawDofile(path)
  if path=='tests/prototype/harness.lua' then
   local H,boot=result,result.Boot
   H.Boot=function()
    O.boots=O.boots+1;wipe(H.db)
    H.AddEcho(200001,'Observation Common Echo',1,1,0)
    for i,id in ipairs(F.ECHO)do
     H.AddEcho(id,'Observation Echo '..i,1,1,0)
     H.db[id].requiredSpell=F.LEVER[i];H.names[F.LEVER[i]]='Tome of Observation Echo '..i
     H.disabled[id]=false
     if mode~='missing' then H.discovered[id]=true end
    end
    H.perks.discoveredEchoes=H.discovered;H.perks.serverActiveSlot=route=='first' and 0 or 1
    H.perks.serverBuildSlots={
     [1]=route=='first' and nil or {name='Observation Saved Build',verified=true,echoes={{spellId=200001,quality=1,stacks=1}}},
     [101]={name='Observation A',verified=false,echoes={{spellId=F.ECHO[1],quality=1,stacks=1,locked=false}}},
     [102]={name='Observation B',verified=false,echoes={{spellId=F.ECHO[2],quality=1,stacks=1,locked=false}}},
    }
    local read=H.service.GetDiscoveredEchoes
    H.service.GetDiscoveredEchoes=function(...)
     O.reads=O.reads+1;if mode=='missing' then return nil end;return read(...)
    end
    local toggle=H.service.ToggleTomeEcho
    H.service.ToggleTomeEcho=function(id)
     if O.refuse then O.calls[#O.calls+1]={id=id,ok=false};return false end
     local accepted=toggle(id);O.calls[#O.calls+1]={id=id,ok=accepted}
     if accepted then O.queue[#O.queue+1]={id=id,want=not(H.disabled[id]==true),due=H.now+.9}end
     return accepted
    end
    local frame=CreateFrame('Frame',nil,UIParent)
    frame:SetScript('OnUpdate',function()
     if O.hold then return end
     for i=#O.queue,1,-1 do local q=O.queue[i];if H.now>=q.due then
      H.disabled[q.id]=q.want;O.replies[#O.replies+1]=q;table.remove(O.queue,i);H.Notify()
     end end
    end)
    return boot()
   end
  end
  return result
 end
 local ok,W=pcall(S.World,{level=1});dofile=rawDofile
 assert(ok,W)
 W.O=O;W.runtime=assert(F.Runtime(),'runtime exists')
 for _,lever in ipairs(F.LEVER)do assert(W.A.Catalog().levers[lever].conformant==true,'SETUP: conformant synthetic tome')end
 assert(O.boots==1 and W.H.playerLevel==1,'one level-one boot')
 Nexus.MainInternals.StoreAuthorityOwner.UpdateSettingsV1('autoDisable',permission~=false)
 if auto~=false then SlashCmdList.NEXUS('auto')end
 return W
end
-- The synthetic player picks a Wishlist in the real Journal chooser. Since M3
-- (UX-05) a pick for a numbered Saved Build with Echoes while Auto is selected
-- asks first with the real confirmation, which this player answers with
-- Assign (the dialog's own OnAccept, as the client runs it). Whether it must
-- ask is predicted from production-visible state, not from the dialog: an
-- expected confirmation that is missing or different, or any dialog where
-- none is expected, fails the fixture. Every other pick assigns at once.
local CONSENT='NEXUS_ASSIGN_WISHLIST_AUTO_ON'
function F.Pick(W,key)
 local picker=assert(S.OpenPicker(),'real Journal selector opens')
 local row=assert(S.PickerRow('Observation '..key),'real Journal row exists')
 local H=W.H
 local active=tonumber(H.perks.serverActiveSlot) or 0
 local target=type(H.perks.serverBuildSlots)=='table' and H.perks.serverBuildSlots[active] or nil
 local auto=Nexus.RecomputeStats().autoEnabled==true
 local asks=auto and active>=1 and type(target)=='table' and #(target.echoes or {})>0
 local before=F.Facts(W)
 local sequence=before and before.assignment and before.assignment.sequence
 H.popup=nil
 row.nameButton:Click()
 local p=H.popup
 if asks then
  assert(p~=nil and p.which==CONSENT,'Auto-ON pick asks with the real assignment confirmation: '..tostring(p and p.which))
  local d=assert(StaticPopupDialogs[CONSENT],'confirmation dialog is defined')
  local wishlist,where='Observation '..key,"Saved Build '"..tostring(target.name).."'"
  local ok,asked=pcall(string.format,tostring(d.text),p.arg1,p.arg2)
  assert(d.button1=='Assign' and d.button2=='Cancel','confirmation buttons are Assign and Cancel')
  assert(p.arg1==wishlist and p.arg2==where,'confirmation names the picked Wishlist and the captured Saved Build: '
   ..tostring(p.arg1)..' / '..tostring(p.arg2))
  assert(ok and asked:find("Assign '"..wishlist.."' to "..where.."?",1,true)==1
   and asked:find('Auto is ON',1,true)~=nil and asked:find('Cancel changes nothing',1,true)~=nil,
   'confirmation title and Auto consequence: '..tostring(asked))
  local asking=F.Facts(W)
  assert(picker:IsShown() and (sequence==nil or (asking and asking.assignment
   and asking.assignment.sequence==sequence)),'nothing is assigned before the answer')
  H.popup=nil
  d.OnAccept(p.frame,p.data)
 else
  assert(p==nil,'no dialog for this pick: '..tostring(p and p.which))
 end
 assert(not picker:IsShown(),'name callback closes picker')
 assert((Nexus.RecomputeStats().autoEnabled==true)==auto,'picking changes no Auto state')
 ProjectEbonholdEchoJournal:Hide()
end
function F.Vector(W)return {W.H.disabled[F.ECHO[1]]==true,W.H.disabled[F.ECHO[2]]==true}end
function F.Same(a,b)return a[1]==b[1] and a[2]==b[2]end
function F.Facts(W)
 local get=W.A.TomeObservationFacts
 return type(get)=='function' and get() or nil
end
function F.Report(W)
 local before={calls=#W.O.calls,reads=W.O.reads,replies=#W.O.replies,now=W.H.now,vector=F.Vector(W)}
 local job=Nexus.SupportReport.NewPreparation({extended=true})
 for _=1,400 do local s=Nexus.SupportReport.Step(job);if s=='done' then
  assert(before.calls==#W.O.calls and before.reads==W.O.reads and before.replies==#W.O.replies and before.now==W.H.now and F.Same(before.vector,F.Vector(W)),'report is passive')
  return table.concat(job.chunks,'')
 end;assert(s=='pending','report progress')end
 error('report step bound')
end
function F.Arm(W,plan,disabled)
 local run=F.Up(W.runtime.RunFullStep,'RunFullStep')
 local step=assert(F.Up(run,'Step'))
 local dispatch=assert(F.Up(step,'DispatchLevelStep'))
 local arm=assert(F.Up(dispatch,'StepArm'))
 local render,index=F.Up(arm,'RenderIdlePanel')
 assert(render and index,'arm render seam')
 debug.setupvalue(arm,index,function()end)
 local ok,err=pcall(arm,1,plan,{},nil,disabled or{},{catalog={}},nil)
 debug.setupvalue(arm,index,render)
 assert(ok,err)
end
function F.Plan()return {advisorOnly=false,leverPlan={keep={},disable={F.LEVER[1]}}}end
return F
