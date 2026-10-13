-- Real TOC/catalog/hash/DPS owners, synthetic profiles only. Counts description
-- calls avoided by ready consumers; does not measure native CPU, FPS or memory.
local T=dofile('tests/prototype/startup_support.lua')
local H=dofile('tests/prototype/harness.lua')
local checks=0
local function check(v,m) assert(v,m);checks=checks+1 end
NexusDB=T.Profile(40,60);T.Load()
H.Fire('ADDON_LOADED','Nexus');H.Fire('PLAYER_ENTERING_WORLD')
T.Until(H,function() return Nexus.StartupStatus().state=='ready' end,200000)
for _=1,100 do H.Advance(.05) end
local C,B,D=Nexus.BuildCatalog,Nexus.BuildHashCache,Nexus.DpsCapture
local originalDb=NexusDB
local legacy,delta,dps=B.Legacy(),B.Delta(),D.GetSyncHash()
check(type(legacy)=='string' and type(delta)=='string' and type(dps)=='string','ready fixture has complete digests')
local rawManual,rawStatus=C.ManualPreparationStatus,C.Status
local buildPumping,dpsPumping=false,false
local descriptions,policies=0,0
C.ManualPreparationStatus=function(...)
 if buildPumping then descriptions=descriptions+1 end
 return rawManual(...)
end
C.Status=function(...)
 if dpsPumping then policies=policies+1 end
 return rawStatus(...)
end
local before=C.DebugStats()
for _=1,40 do
 buildPumping=true;local ready=B.Pump();buildPumping=false
 check(ready==true,'ready build pump still serves')
 dpsPumping=true;local dpsReady=D.PumpSyncHash();dpsPumping=false
 check(dpsReady==true,'ready DPS pump still serves')
end
print('CATALOG_DESCRIPTION_CALLS build='..descriptions..' dps='..policies..' pumps=40 each')
check(descriptions==0,'ready build consumers do not allocate preparation descriptions: '..descriptions)
check(policies==0,'ready DPS consumers do not allocate status descriptions: '..policies)
C.ManualPreparationStatus=rawManual;C.Status=rawStatus
local after=C.DebugStats()
for _,k in ipairs({'rootAdmissions','rootPumps','rowWalks','commits','driftInvalidations'}) do
 check(after[k]==before[k],'ready scalar queries start no catalog work: '..k)
end
check(B.Legacy()==legacy and B.Delta()==delta and D.GetSyncHash()==dps,'digests remain exact')

local function Equivalent(label)
 local m=C.ManualPreparationStatus()
 local agrees,binding,reason=C.SourceBinding()
 check(agrees==m.ownerAgrees,label..': source agreement matches full description')
 check(binding==m.binding,label..': binding matches full description')
 if not agrees then check(reason==m.reason,label..': exact refusal reason') end
 local readOnly,state=C.ServingPolicy()
 local s=C.Status()
 check(readOnly==s.readOnly and state==s.state,label..': storage policy matches full fresh gate')
end
Equivalent('ready')

-- Existing capability-less hosts retain their truthful, fresh old-reader path.
local sourceBinding,servingPolicy=C.SourceBinding,C.ServingPolicy
C.SourceBinding=nil;C.ServingPolicy=nil
descriptions,policies=0,0
C.ManualPreparationStatus=function(...) descriptions=descriptions+1;return rawManual(...) end
C.Status=function(...) policies=policies+1;return rawStatus(...) end
check(B.Pump()==true and descriptions==1,'legacy host performs one fresh preparation query')
check(D.PumpSyncHash()==true and policies>=1,'legacy host still performs fresh policy query')
C.ManualPreparationStatus=rawManual;C.Status=rawStatus
C.SourceBinding=sourceBinding;C.ServingPolicy=servingPolicy
check(B.Legacy()==legacy and D.GetSyncHash()==dps,'fallback preserves current digests')

local stored=assert(C.Get('synthetic-startup-7'))
local donor=H.Clone(stored)
donor.id='dependency-pending';donor.title='Dependency pending';donor.author='Remote-Realm'
local ok,why,ticket=C.Put(donor)
check(ok==nil and why=='ROOT_MUTATION_PENDING' and type(ticket)=='table','real same-source pending mutation')
Equivalent('same-source pending')
check(C.ManualPreparationStatus().ownerAgrees==true and B.Pump()==true,'pending preserves serving authority')
T.Until(H,function() return ticket.state=='committed' and B.Stats().phase=='ready' end,200000)
Equivalent('published')
check(B.Legacy()~=legacy,'published mutation rebuilds digest')

-- Every new call re-proves current ownership/database identities. No frame cache.
local unitName=UnitName
UnitName=function() return 'OtherOwner','Ebonhold' end
Equivalent('owner changed')
check(B.Pump()==false and B.Legacy()==nil,'owner mismatch immediately refuses old digest')
UnitName=unitName
C.RequestAuthorityRebindV1('OWNER_REBIND_REQUIRED')
T.Until(H,function() return C.ManualPreparationStatus().ownerAgrees and B.Stats().phase=='ready' end,200000)
NexusDB={settings={autoPick=false},chars={},communityBuilds={}}
Equivalent('database replaced')
check(B.Pump()==false and B.Legacy()==nil,'replacement root immediately refuses old digest')
NexusDB=originalDb
C.RequestAuthorityRebindV1('SOURCE_REBIND_REQUIRED')
T.Until(H,function() return C.ManualPreparationStatus().ownerAgrees and B.Stats().phase=='ready' end,200000)
Equivalent('restored')

-- Read-only and refused saved roots keep the full-reader policy, visible
-- supported rows, receive refusal and byte-preservation contract. Those real
-- board/receive paths are exercised by readonly_saved_dps_visibility separately.
local F=dofile('tests/prototype/format5_support.lua')
for _,case in ipairs({
 {'future saved format',function(db) db.settingsVersion=6 end},
 {'unknown catalog schema',function(db) db.settingsVersion=6;db.buildCatalog={schemaVersion=2} end},
}) do
 local db=F.Database({version=2});case[2](db)
 local input=F.Serialize(db)
 local h=F.Boot(db)
 for _=1,240 do h.Advance(.5,.5) end
 C=Nexus.BuildCatalog
 Equivalent(case[1])
 check(C.ServingPolicy()==true,case[1]..': scalar policy stays read-only')
 Nexus.DpsCapture.PumpSyncHash()
 h.Fire('PLAYER_LOGOUT')
 check(F.Serialize(NexusDB)==input,case[1]..': reads and digest write no saved data')
end
print('PASS fresh scalar dependency policies; idle description avoidance, legacy fallback, pending publication, owner/root drift and read-only preservation; '..checks..' checks')
