-- Warning choices, persistence and interruption; real UI owner, synthetic client.
local checks=0
local function check(v,m)assert(v,m);checks=checks+1 end
local function Fresh(db,mode)
 local H=dofile('tests/prototype/harness.lua');UIParent:SetSize(1280,720)
 NexusOverwriteWarning=nil
 Nexus={Store={StateWriteStatus=function()return {mode=mode or 'durable'}end},
  StartupStatus=function()return {coreReady=true}end}
 NexusDB=db
 return H,dofile('ui/OverwriteWarning.lua')
end
local function ReadWarning(H,W,checked)
 check(W.EnsureOnboarding()=='pending','first open asks again without suppression')
 local f=NexusOverwriteWarning
 local update=f:GetScript('OnUpdate');update(f,100)
 check(not f.yes:IsEnabled() and not f.no:IsEnabled(),'elapsed argument cannot bypass clock deadline')
 f:GetScript('OnKeyDown')(f,'ENTER')
 check(f:IsShown(),'Enter cannot acknowledge')
 H.Advance(5.01);f.suppress:SetChecked(checked==true);f.yes:Click()
 return f
end

-- Unchecked Yes is session-only. A reload offers it again; checked Yes saves
-- only this warning's versioned opt-out. The old welcome flag is irrelevant.
local db={hasSeenQuickStart=true}
local H,W=Fresh(db)
ReadWarning(H,W,false)
check(W.EnsureOnboarding()=='accepted' and db.overwriteWarnings==nil,'unchecked Yes creates no persistent opt-out')
H,W=Fresh(db);ReadWarning(H,W,true)
check(db.overwriteWarnings.onboarding.version==1 and db.overwriteWarnings.onboarding.suppressed,'checked Yes persists onboarding')
check(db.overwriteWarnings.auto==nil,'onboarding never suppresses Auto')
H,W=Fresh(db)
check(W.EnsureOnboarding()=='accepted' and NexusOverwriteWarning==nil,'reload honors matching saved opt-out without a timer')

local owner,calls={},0
local function Accept()calls=calls+1;return true end
W.RequestAuto(owner,Accept)
local f=NexusOverwriteWarning
check(f:IsShown() and f.yes:IsEnabled() and f.no:IsEnabled(),'Auto warning is immediately usable')
check(not f.suppress:GetChecked(),'Auto starts unchecked')
W.RequestAuto(owner,Accept);W.RequestAuto({},Accept)
check(calls==0 and f:IsShown(),'repeated requests keep one pending dialog')
f.suppress:SetChecked(true);f.no:Click()
check(calls==0 and db.overwriteWarnings.auto==nil,'No saves no suppression')
W.RequestAuto(owner,Accept);f:GetScript('OnKeyDown')(f,'ESCAPE')
check(calls==0 and not f:IsShown() and db.overwriteWarnings.auto==nil,'Escape is No')
W.RequestAuto(owner,Accept);f:Hide()
check(calls==0 and db.overwriteWarnings.auto==nil,'external close is No')
W.RequestAuto(owner,Accept);f.close:Click()
check(calls==0 and not f:IsShown(),'visible close is No')
W.RequestAuto(owner,Accept);f.yes:Click()
f.yes:GetScript('OnClick')(f.yes)
check(calls==1 and db.overwriteWarnings.auto==nil,'unchecked Yes runs once; stale handler cannot accept twice')
W.RequestAuto(owner,Accept)
check(f:IsShown(),'unchecked Yes does not suppress next enable')
check(W.CancelAuto(owner) and not W.CancelAuto(owner),'cancellation consumes only the matching request')
f.yes:GetScript('OnClick')(f.yes)
check(calls==1,'cancelled callback never resumes')
W.RequestAuto(owner,Accept);f.suppress:SetChecked(true);f.yes:Click()
check(calls==2 and db.overwriteWarnings.auto.suppressed,'affirmed checked Auto saves its own opt-out')
W.RequestAuto(owner,Accept)
check(calls==3 and not f:IsShown(),'saved Auto suppression still requires an explicit request')

-- Closing the delayed first warning works immediately, without consent.
H,W=Fresh({hasSeenQuickStart=true})
W.EnsureOnboarding();f=NexusOverwriteWarning;f.suppress:SetChecked(true);f.close:Click()
check(W.EnsureOnboarding()=='declined' and NexusDB.overwriteWarnings==nil,'close during delay writes no acknowledgment')
check(f:GetScript('OnUpdate')==nil,'close removes countdown work')

-- Durable-write boundary, malformed/future data and stale database identity.
for _,saved in ipairs({{}, {overwriteWarnings='preserve'},
 {overwriteWarnings={onboarding={version=2,suppressed=true}}}})do
 H,W=Fresh(saved,saved.overwriteWarnings==nil and 'read-only' or 'durable')
 local before=saved.overwriteWarnings
 ReadWarning(H,W,true)
 check(saved.overwriteWarnings==before,'read-only/malformed/future acknowledgment remains unchanged')
end
H,W=Fresh(nil);ReadWarning(H,W,true)
check(NexusDB==nil,'affirmation creates no absent database')
local unknown={marker='preserve'}
local prior={version=1,suppressed=false,extra=unknown}
H,W=Fresh({overwriteWarnings={onboarding=prior,other=unknown}})
ReadWarning(H,W,true)
check(NexusDB.overwriteWarnings.onboarding==prior and prior.extra==unknown
 and NexusDB.overwriteWarnings.other==unknown,'affirmation preserves unknown preference fields')
for _,version in ipairs({'1',-1,1.5,0/0,math.huge,false})do
 local entry={version=version,suppressed=false}
 H,W=Fresh({overwriteWarnings={onboarding=entry}})
 ReadWarning(H,W,true)
 check(NexusDB.overwriteWarnings.onboarding==entry and entry.suppressed==false,
  'malformed preference version is preserved')
end
local malformed={version=1,suppressed='preserve'}
H,W=Fresh({overwriteWarnings={onboarding=malformed}});ReadWarning(H,W,true)
check(malformed.suppressed=='preserve','malformed suppression value is preserved')
H,W=Fresh({overwriteWarnings={onboarding={version=1,suppressed=true}}})
local currentOwner='first@realm'
Nexus.Store.CurrentOwnerKey=function()return currentOwner end
W.RequestAuto(owner,Accept);f=NexusOverwriteWarning
currentOwner='second@realm';f.suppress:SetChecked(true);f.yes:Click()
check(calls==3 and NexusDB.overwriteWarnings.auto==nil,
 'same-root character change revokes pending approval and its persistence')
H,W=Fresh({overwriteWarnings={onboarding={version=1,suppressed=true}}})
W.EnsureOnboarding();W.RequestAuto(owner,Accept);f=NexusOverwriteWarning
local replacement={};NexusDB=replacement;f.suppress:SetChecked(true);f.yes:Click()
check(calls==3 and replacement.overwriteWarnings==nil,'stale dialog neither enables nor writes new database')
check(#H.actions==0,'warnings issue no game or save operation')
print('PASS overwrite warning lifetime, consent, reload, clock and owner guards checks='..checks)
