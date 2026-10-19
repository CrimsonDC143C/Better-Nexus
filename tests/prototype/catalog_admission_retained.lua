-- Origin quota follows retained overlay identity, not display/readability.
local S=dofile('tests/prototype/catalog_admission_policy_support.lua')
local F,T=S.F,S.T
local checks=0;local function check(v,m)assert(v,m);checks=checks+1 end
local function Seed(db)
 for _,r in pairs(db.communityBuilds)do r.syncAdmissionOriginV1='relay@ebonhold' end
end
local function Refused(label)
 local saved=S.Saved();local ok,why=S.Remote(S.Record('new-'..label),'Relay-Ebonhold')
 check(ok==false and why=='REMOTE_ORIGIN_LIMIT',label..' retains its origin charge: ok='..tostring(ok)..' why='..tostring(why)..' admitted='..tostring(S.Raw('new-'..label)~=nil))
 check(S.Saved()==saved,label..' refusal keeps exact retained rows')
end
for _,case in ipairs({'invalid','tombstone','retention'})do
 local H,C=S.Boot(256,function(db)
  Seed(db)
  if case=='invalid' then db.communityBuilds['seed-1'].title=false
  elseif case=='tombstone' then db.syncTombstones={['seed-1']={stamp=2,author='Owner-Ebonhold'}}
  else db.communityRetentionEvictions={['seed-1']=1700000000} end
 end)
 check(type(S.Raw('seed-1'))=='table' and S.Raw('seed-1').syncAdmissionOriginV1=='relay@ebonhold',case..' raw overlay identity/witness retained')
 if case~='retention' then check(C.Get('seed-1')==nil,case..' has no readable snapshot') end
 Refused(case)
 H=F.Reload();S.H=H;S.C=Nexus.BuildCatalog
 T.Until(H,function()return S.C.ManualPreparationStatus().ready end)
 Refused(case..'-reload')
end

-- A real remote tombstone retains raw source and must not release Q.
local H,C=S.Boot(256,Seed)
check(S.Settle(C.SetTombstone('seed-1',{stamp=3,author='Owner-Ebonhold'},
 {source='remote',sender='Owner-Ebonhold'})),'actual remote owner tombstone commits')
check(C.Get('seed-1')==nil and S.Raw('seed-1')~=nil,'actual tombstone hides but retains the overlay')
Refused('actual-remote-tombstone')

-- Cancellation publishes neither row removal nor a quota decrement.
H,C=S.Boot(256,Seed)
local saved=S.Saved();local restore=T.SingleSlicePacing()
local ok,why,ticket=C.RemoveOverlay('seed-1')
check(ok==nil and type(ticket)=='table','removal starts a bounded candidate')
C.CancelRootAdmission();restore()
check(S.Saved()==saved and ticket.committed==false,'cancelled removal retains raw identity and witness')
-- A cancelled admission root is deliberately not resumed implicitly.
-- Literal reload rebuilds the serving root from its unchanged durable bytes.
H=F.Reload();S.H=H;S.C=Nexus.BuildCatalog;C=S.C
T.Until(H,function()return C.ManualPreparationStatus().ready end)
Refused('cancelled-removal')

-- Actual removal releases one occupied identity; actual re-admission charges it.
T.Until(H,function()return C.ManualPreparationStatus().ready end)
check(S.Settle(C.RemoveOverlay('seed-1')),'actual overlay removal commits')
check(S.Raw('seed-1')==nil and C.Status().buildIdentityCount==255,'removed identity is no longer charged as occupied')
check(S.Remote(S.Record('seed-1'),'Relay-Ebonhold'),'actual re-admission can use the one released slot')
check(S.Raw('seed-1').syncAdmissionOriginV1=='relay@ebonhold','re-admission records actual origin')
Refused('readmitted')
H=F.Reload();S.H=H;S.C=Nexus.BuildCatalog
T.Until(H,function()return S.C.ManualPreparationStatus().ready end)
Refused('readmitted-reload')
print('PASS catalog_admission_retained checks='..checks)
