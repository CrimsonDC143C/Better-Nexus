-- DPS sync digest across a catalog publication inside the measured window.
-- Real TOC boot, real owners (DpsCapture, BuildCatalog, CommunityBuilds,
-- DataRetention, MainLifecycle hash slot, Sync), public inputs only: no
-- product function is wrapped or replaced and no private upvalue is read.
-- Synthetic data.
--
-- dps_sync_digest_bounded sections 8 and 10 first let background catalog
-- work settle, and fail on any publication inside their windows. This test
-- covers that case on purpose. During 600 frames of existing-player traffic
-- (one record every 10 frames) a public record for a new player with a new
-- loadout arrives at frame 100. Its build page is a catalog commit, and the
-- commit replaces the saved DPS store, so the digest is prepared again.
-- Across that replacement:
--  * GetSyncHash returns nothing while the digest owner is not initialized,
--    and any digest it returns is the canonical digest of the current store
--    (GetSyncHashUncached), never an older one;
--  * the Sync gate is open only while the digest is readable;
--  * the DPS field of every WLRQ on the wire is the canonical digest;
--  * a manual Sync Now made while the digest is not ready waits ("preparing
--    sync data") and is sent once the digest is ready.
-- "Canonical" is the digest of the current store. That does not show that
-- no record is lost across the replacement; row counts are reported, not
-- asserted. Assertions count frames; no wall-clock threshold. The frame of
-- the publication and the not-ready counts are measured and printed, never
-- pinned.
local F=dofile('tests/prototype/format5_support.lua')
local L=dofile('tests/prototype/leaderboard_fixture_support.lua')
local N=240
local WINDOW,PERIOD,INJECT_FRAME=600,10,100
local checks=0
local function check(v,m) if not v then error(m,2) end;checks=checks+1 end

local players={{name='PrototypeTester',class='MAGE',dps={lk=39000,dummy=38000},isLocal=true,variant=30,ordinary=60},
 {name='Alpha',class='MAGE',dps={lk=52000,dummy=48000},variant=10,ordinary=60}}
for i=1,N do players[#players+1]={name='Filler'..i,class='PRIEST',variant=100+i,dps={lk=20000+i,dummy=19000+i}} end
local fx=L.New({players=players})
local H=F.Boot(fx:Install(F.Database({version=2})),function(h) h.playerLevel=60 end)
local D=Nexus.DpsCapture
local function Stats() return D.HashCacheStats() end
local function Phase() local s=Stats();return s.phase or (s.initialized and 'ready' or 'cold') end
local function Gate() return Nexus.StartupStatus().syncGate end
local function SavedStore() return rawget(rawget(NexusDB,'authorityBundle'),'dpsCapture') end
local function RetentionDue()
 local meta=rawget(rawget(NexusDB,'authorityBundle'),'dataRetention')
 return type(meta)=='table' and tonumber(rawget(meta,'nextMaintenanceAt')) or nil
end

-- Setup: let background catalog work (the evidence compaction walk,
-- scheduled retention runs) finish through its own owners, then make sure
-- no retention commit falls due during the test, so the publication in the
-- window is the injected record's. Same passive reads and bounds as
-- dps_sync_digest_bounded sections 8 and 10. Retention is requested through
-- its public entry only when its saved schedule is due sooner (or, before its
-- first run, absent). Nothing is cancelled, forced or skipped, and no clock
-- is changed. The "DSDP settle" line reports the frames, schedule and
-- headroom.
local function Settle()
 local quiet=0
 for i=1,24000 do
  local calm=Gate()=='open' and Phase()=='ready'
   and Nexus.BuildCatalog.ManualPreparationStatus().ready==true
   and not Nexus.Scheduler.Pending('data-compaction')
   and not Nexus.Scheduler.Pending('data-retention.enforce')
  quiet=calm and quiet+1 or 0
  if quiet>=40 then return i-1 end
  H.Advance(.05,.05)
 end
 check(false,'setup: background catalog work settles: gate '..tostring(Gate())
  ..' phase '..tostring(Phase())..' catalog ready '..tostring(Nexus.BuildCatalog.ManualPreparationStatus().ready)
  ..' compaction pending '..tostring(Nexus.Scheduler.Pending('data-compaction')~=nil)
  ..' retention pending '..tostring(Nexus.Scheduler.Pending('data-retention.enforce')~=nil))
end
local function SettleCatalog(seconds)
 local clock0=os.clock()
 check(Nexus.DataRetention.Limits().enabled~=true,'setup: retention runs in its unlimited mode')
 local settled=Settle()
 local due=RetentionDue()
 local dueIn,waited,resettled=due and due-time(),0,0
 if due==nil or due-time()<seconds then
  for _=1,6200 do if due==nil or time()>=due then break end;waited=waited+1;H.Advance(.05,.05) end
  check(Nexus.DataRetention.Request('test: retention before the publication window')==true,'setup: a retention run is requested')
  resettled=Settle()
 end
 print('DSDP settle','settleFrames',settled,'dueIn',tostring(dueIn),'waitFrames',waited,'resettleFrames',resettled,
  'headroom',(RetentionDue() or 0)-time(),'needed',seconds,'profileElapsedSeconds',string.format('%.2f',os.clock()-clock0))
 check(RetentionDue()~=nil,'setup: the retention schedule is saved')
 check(RetentionDue()-time()>=seconds,'setup: no retention commit falls due in the test: '..tostring(RetentionDue()-time()))
end

-- The state request on the wire (core/SyncSession.lua RequestSyncOnce):
-- WLRQ|<sender>|<build hash>|<DPS digest>|<request ID>|<version>. A packet is
-- read as the Sync tests read it (sync_request_readiness, sync_request_size):
-- '||' unescaped, a 'P<n>:' part prefix removed, split on '|'. The DPS field
-- is compared exactly; the digest appearing elsewhere in the text is not
-- enough.
local function Fields(text) local f={};for part in (text..'|'):gmatch('([^|]*)|') do f[#f+1]=part end;return f end
local function RequestFields(packet)
 local text=tostring(packet and packet.text):gsub('||','|'):gsub('^P%d+:','')
 if text:find('^WLRQ|') then return Fields(text) end
end

-- Per-frame observation, after each update. Only public reads: the owner's
-- passive stats, the Sync gate, the cached and the uncached digest, the
-- harness wire log.
local BuildHashes=Nexus.BuildHashCache
local function BuildHashesReady()
 return type(BuildHashes)=='table' and type(BuildHashes.Stats)=='function' and BuildHashes.Stats().phase=='ready'
end
local o={frames=0,stale=0,served=0,gateOpenNoDigest=0,requests=0,badRequests=0,
 notInitialized=0,noDigest=0,hashesNotReady=0,catalogNotReady=0,dpsOnly=0}
local seen,manualIndex=#H.sent,nil
local function ScanSent(canonical,label)
 for i=seen+1,#H.sent do
  local f=RequestFields(H.sent[i])
  if f then
   o.requests=o.requests+1
   local ok=#f==6 and f[4]==canonical
   if not ok then
    o.badRequests=o.badRequests+1
    o.badRequest=o.badRequest or ('frame '..tostring(label)..' fields '..#f..' DPS '..tostring(f[4])..' canonical '..tostring(canonical))
   end
   if manualIndex and i>manualIndex and not o.manualSentAt then o.manualSentAt,o.manualCanonical=label,ok end
  end
 end
 seen=#H.sent
end
local function Observe(label)
 -- The owner's state is read before GetSyncHash, which can itself start a
 -- rebuild after a store replacement.
 local initialized=Stats().initialized==true
 local gate=Gate()
 local digest=D.GetSyncHash()
 local canonical=D.GetSyncHashUncached()
 o.frames=o.frames+1
 if digest~=nil and digest~=canonical then o.stale=o.stale+1 end
 if not initialized and digest~=nil then o.served=o.served+1 end
 if gate=='open' and digest==nil then o.gateOpenNoDigest=o.gateOpenNoDigest+1 end
 if not initialized then o.notInitialized=o.notInitialized+1 end
 if digest==nil then o.noDigest=o.noDigest+1 end
 if gate=='hashes-not-ready' then o.hashesNotReady=o.hashesNotReady+1 end
 if gate=='catalog-not-ready' then o.catalogNotReady=o.catalogNotReady+1 end
 -- Frames where only the DPS digest can hold the gate (reported).
 if not initialized and gate~='catalog-not-ready' and BuildHashesReady() then o.dpsOnly=o.dpsOnly+1 end
 ScanSent(canonical,label)
 return initialized,digest
end

local function RowCounts()
 local best=type(SavedStore())=='table' and rawget(SavedStore(),'characterBest') or nil
 local out={}
 for _,category in ipairs({'lk','dummy'}) do
  local bucket=type(best)=='table' and rawget(best,category) or nil
  local count=0
  if type(bucket)=='table' then for _ in pairs(bucket) do count=count+1 end end
  out[category]=count
 end
 return out
end

-- The injected record: the section-4b wire shape, from its own sender, for a
-- player the fixture does not have and a loadout no fixture player has
-- (generator variant 1000, built as L.New builds the fixture players). A new
-- owner's record reaches CommunityBuilds.EnsureDpsBuildForEchoes and a
-- BuildCatalog.Put of its build page; that commit replaces the saved store.
local NAME,VARIANT='Windowcomer',1000
local REALM=fx.realm
local OWNER=NAME:lower()..'@'..REALM:lower()
local function HasNamedRow()
 local best=type(SavedStore())=='table' and rawget(SavedStore(),'characterBest') or nil
 local bucket=type(best)=='table' and rawget(best,'lk') or nil
 if type(bucket)~='table' then return false end
 for _,row in pairs(bucket) do if type(row)=='table' and rawget(row,'player')==NAME then return true end end
 return false
end
local function Inject()
 local ord,locked=L.OrdinaryRows(VARIANT),L.LockedRows(VARIANT)
 local fp=L.Fingerprint(ord)
 local new=true
 for _,p in ipairs(fx.players) do if p.name==NAME or p.fingerprint==fp then new=false end end
 check(new,'setup: the injected player and loadout are new to the fixture')
 check(not HasNamedRow(),'setup: the injected player has no row before its record')
 local wire={v=7,c='lk',d=44444,u=120,t=time()-4,p=NAME,l=80,k='MAGE',o=OWNER,r=REALM,
  e=L.DpsRows(ord),f=fp,lk=L.DpsRows(locked)}
 check(D.ReceiveRecord(wire,NAME..'-'..REALM)==true,'setup: the new player record is accepted at frame '..INJECT_FRAME)
end

-- Start-up and setup.
for _=1,40000 do if Phase()=='ready' then break end;H.Advance(.05,.05) end
check(Phase()=='ready','setup: the start-up digest becomes ready: '..tostring(Phase()))
check(D.GetSyncHash()==D.GetSyncHashUncached(),'setup: the start-up digest is canonical')
SettleCatalog(100)
for _=1,400 do if Gate()=='open' then break end;H.Advance(.05,.05) end
check(Gate()=='open','setup: the Sync gate is open: '..tostring(Gate()))

-- The window. Requests sent during the setup are not part of it.
seen=#H.sent
local store0,rows0=SavedStore(),RowCounts()
local lastStore,replacedAt,replacements=store0,nil,0
local accepted,n,preInject,afterReplacement=0,0,0,0
local manualAt,preparing
local clock0=os.clock()
for i=1,WINDOW do
 if i%PERIOD==0 then
  n=n+1
  if fx:Receive('Filler'..(1+n%N),'dummy',{dps=90000+n,ts=time()-1}) then accepted=accepted+1 end
 end
 if i==INJECT_FRAME then Inject() end
 H.Advance(.05,.05)
 local initialized,digest=Observe(i)
 local store=SavedStore()
 if store~=lastStore then replacements=replacements+1;replacedAt=replacedAt or i;lastStore=store end
 local notReady=not initialized or digest==nil
 if i<INJECT_FRAME then
  if notReady or store~=store0 then preInject=preInject+1 end
 elseif notReady then
  if replacedAt then afterReplacement=afterReplacement+1 end
  if not manualAt then
   -- First not-ready observation: a manual Sync Now, as a user would.
   manualAt,manualIndex=i,#H.sent
   local chat0=#H.chat
   SlashCmdList.NEXUS('sync')
   for k=chat0+1,#H.chat do if tostring(H.chat[k]):find('preparing sync data',1,true) then preparing=true end end
   ScanSent(D.GetSyncHashUncached(),i)
  end
 end
end
print('DSDP window','frames',WINDOW,'accepted',accepted,'replacedAtFrame',tostring(replacedAt),'replacements',replacements,
 'manualAtFrame',tostring(manualAt),'notInitializedFrames',o.notInitialized,'noDigestFrames',o.noDigest,
 'hashes-not-ready',o.hashesNotReady,'catalog-not-ready',o.catalogNotReady,'dpsOnlyRebuildFrames',o.dpsOnly,
 'requests',o.requests,'profileElapsedSeconds',string.format('%.2f',os.clock()-clock0))
check(accepted>=WINDOW/PERIOD-1,'fixture: records accepted: '..accepted)
check(preInject==0,'setup: before the new record the digest is ready and the store is not replaced: '..preInject..' frame(s)')
check(replacedAt~=nil and replacedAt>=INJECT_FRAME,'setup: the new record\'s build page replaced the saved DPS store inside the window: '
 ..tostring(replacedAt))
check(afterReplacement>=1,'setup: the replacement made the digest not ready: '..afterReplacement..' frame(s)')
check(manualAt~=nil,'setup: a manual Sync Now was made while the digest was not ready')
check(o.stale==0,'no stale digest across the publication: '..o.stale..' frame(s)')
check(o.served==0,'no digest returned while the digest owner is not initialized: '..o.served..' frame(s)')
check(o.gateOpenNoDigest==0,'the Sync gate is open only with a readable digest: '..o.gateOpenNoDigest..' frame(s)')
check(o.badRequests==0,'every WLRQ carries the canonical DPS digest: '..o.badRequests..' of '..o.requests..': '..tostring(o.badRequest))
check(preparing==true,'a manual Sync Now waits ("preparing sync data") while the digest is prepared')

-- Recovery after the traffic: ready, gate open, canonical, the manual
-- request sent with the canonical digest. Every frame is still observed.
local readyAt,openAt
for i=1,20000 do if Phase()=='ready' then readyAt=i;break end;H.Advance(.05,.05);Observe('recovery') end
check(readyAt~=nil,'the digest becomes ready after the traffic: '..tostring(Phase()))
for i=1,400 do if Gate()=='open' then openAt=i;break end;H.Advance(.05,.05);Observe('recovery') end
check(openAt~=nil,'the Sync gate opens after the traffic: '..tostring(Gate()))
check(D.GetSyncHash()==D.GetSyncHashUncached(),'the recovered digest is canonical')
for _=1,400 do if o.manualSentAt then break end;H.Advance(.05,.05);Observe('recovery') end
local rows1=RowCounts()
print('DSDP recovery','readyAfter',tostring(readyAt),'openAfter',tostring(openAt),'manualSentAt',tostring(o.manualSentAt),
 'requests',o.requests,'rows lk',rows0.lk..'->'..rows1.lk,'rows dummy',rows0.dummy..'->'..rows1.dummy,
 'injectedRowPresent',tostring(HasNamedRow()))
check(o.manualSentAt~=nil,'the manual request is sent once the digest is ready')
check(o.manualCanonical==true,'the manual request carries the canonical DPS digest')
check(o.stale==0 and o.served==0 and o.gateOpenNoDigest==0,'recovery: no stale, early or ungated digest: '
 ..o.stale..'/'..o.served..'/'..o.gateOpenNoDigest)
check(o.badRequests==0,'recovery: every WLRQ carries the canonical DPS digest: '..o.badRequests..' of '..o.requests..': '..tostring(o.badRequest))
check(#H.actions==0,'zero gameplay mutation')

print('PASS dps_sync_digest_publication: the digest stays canonical and Sync waits across an in-window catalog publication checks='..checks)
