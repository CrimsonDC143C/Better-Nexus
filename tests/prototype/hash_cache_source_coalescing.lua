-- One passive source snapshot per build-cache operation; never reused across
-- calls or frames. Real TOC boot/catalog/lifecycle, synthetic data only.
local T=dofile('tests/prototype/startup_support.lua')
local H=dofile('tests/prototype/harness.lua')
local checks=0
local function check(value,message) assert(value,message);checks=checks+1 end
NexusDB=T.Profile(40,60);T.Load()
H.Fire('ADDON_LOADED','Nexus');H.Fire('PLAYER_ENTERING_WORLD')
T.Until(H,function() return Nexus.StartupStatus().state=='ready' end,200000)
for _=1,100 do H.Advance(.05) end
local C,Cache=Nexus.BuildCatalog,Nexus.BuildHashCache
local rawPump,rawStatus,rawBinding=Cache.Pump,C.ManualPreparationStatus,C.SourceBinding
local function find(fn,name,seen)
 if type(fn)~='function' or seen[fn] then return end;seen[fn]=true
 for i=1,255 do
  local n,v=debug.getupvalue(fn,i);if not n then break end
  if n==name then return v end
  if n~='_ENV' and type(v)=='function' then local got=find(v,name,seen);if got then return got end end
 end
end
local sourceOf=assert(find(rawPump,'SourceOf',{}),'real source query')
local pumping=false;local pumpCalls,statusCalls=0,0
Cache.Pump=function(...)
 pumpCalls=pumpCalls+1;pumping=true
 local ready,progressed=rawPump(...)
 pumping=false
 return ready,progressed
end
local function CountSourceRead()
 if pumping then
  for depth=2,6 do
   local caller=debug.getinfo(depth,'f')
   if caller and caller.func==sourceOf then statusCalls=statusCalls+1;break end
  end
 end
end
C.ManualPreparationStatus=function(...)
 CountSourceRead();return rawStatus(...)
end
if rawBinding then
 C.SourceBinding=function(...)
  CountSourceRead();return rawBinding(...)
 end
end
local originalRoot=NexusDB
local originalLegacy,originalDelta=Cache.Legacy(),Cache.Delta()
check(type(originalLegacy)=='string' and type(originalDelta)=='string','warm fixture serves both digests')
local before=C.DebugStats()
for _=1,40 do H.Advance(.0025) end
local after=C.DebugStats()
check(pumpCalls==40,'real lifecycle retains one hash pump per frame')
check(statusCalls==40,'one source query per ready hash pump, no nested duplicate: '..statusCalls..' for '..pumpCalls)
for _,key in ipairs({'rootAdmissions','rootPumps','rowWalks','commits','driftInvalidations'}) do
 check(after[key]==before[key],'idle remains work-free: '..key)
end
check(Cache.Legacy()==originalLegacy and Cache.Delta()==originalDelta,'idle coalescing preserves exact digests')
Cache.Pump=rawPump;C.ManualPreparationStatus=rawStatus;C.SourceBinding=rawBinding

-- A source refusal arriving between two public operations is observed in the
-- very next operation: no frame-scoped or retained source result exists.
NexusDB={settings={autoPick=false},chars={},communityBuilds={}}
check(Cache.Pump()==false,'next operation refuses a replaced saved root')
check(Cache.Legacy()==nil and Cache.Delta()==nil,'no old digest after saved-root replacement')
check(Cache.BucketHasTombstone(1)==nil,'no marker authority from refused source')
NexusDB=originalRoot
C.RequestAuthorityRebindV1('SOURCE_REBIND_REQUIRED')
T.Until(H,function() return C.ManualPreparationStatus().ownerAgrees and Cache.Stats().phase=='ready' end,200000)
check(Cache.Legacy()==originalLegacy and Cache.Delta()==originalDelta,'restored root recovers exact digests')

-- A same-source pending transaction still serves its original root. It is
-- source agreement, not the ready flag, that decides hash authority.
local stored=assert(C.Get('synthetic-startup-7'))
local donor=H.Clone(stored)
donor.id='coalescing-pending-1';donor.title='Coalescing pending';donor.author='Remote-Realm'
local ok,why,ticket=C.Put(donor)
check(ok==nil and why=='ROOT_MUTATION_PENDING' and type(ticket)=='table','real mutation is pending')
local status=C.ManualPreparationStatus()
check(status.ownerAgrees==true and status.ready==false,'pending retains the owner-agreeing serving source')
check(Cache.Pump()==true and Cache.Legacy()==originalLegacy,'pending does not invalidate same-source digest')
T.Until(H,function() return ticket.state=='committed' and Cache.Stats().phase=='ready' end,200000)
check(C.Get(donor.id)~=nil and Cache.Legacy()~=originalLegacy,'published change invalidates and rebuilds digest')
check(Cache.Delta()~=originalDelta,'published change updates delta digest too')
print('PASS coalesced build source query; real idle lifecycle, immediate refusal and pending/publication; '..checks..' checks')
