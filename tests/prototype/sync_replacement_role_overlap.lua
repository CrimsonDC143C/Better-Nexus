-- Independent review controls. Production SyncSession, synthetic clock/transport.
Nexus=nil
dofile('core/SyncSession.lua')
local Factory=Nexus.SyncInternals.Session
local results,checks={},0
local function check(ok,label)
  checks=checks+1
  results[#results+1]={ok=not not ok,label=label}
  print((ok and 'PASS ' or 'FAIL ')..label)
end
local function Boot(cap)
  local S={time=100,mode='automatic',inbound=false,bulk=0,calls={},overflow=0,ok=true,why=nil,complete=true}
  local M=Factory.New({
    now=function()return S.time end,myName=function()return 'Review-Realm' end,
    normalizePeerName=function(x)return tostring(x or ''):lower()end,
    receiveWindow=5,inflightGrace=3,maxReceiveAge=10,maxConvergenceAge=40,
    maxRecoveryQueue=cap or 2,maxKnownPeers=32,requestCooldown=0,
    autoSyncMinPass=0,autoSyncQuiet=0,maxPasses=1,
    syncMode=function()return S.mode end,
    validIdentifier=function(x)return type(x)=='string' and x~=''end,
    catalogGet=function()return S.complete and {echoes={{spellId=1}}} or nil end,
    transportSnapshot=function()return {bulk=S.bulk}end,
    inboundHasPending=function()return S.inbound end,
    transportHasPending=function()return false end,
    currentBuildHash=function()return 'a' end,currentDpsHash=function()return 'b'end,
    isConnected=function()return true end,ensureChannel=function()return true end,
    loadoutRequestCode='WLRL',requestCode='WLRQ',chatLimit=255,
    announceVersion=function()return '1.0.0'end,
    enqueueControl=function(wire,meta)
      S.calls[#S.calls+1]={wire=wire,meta=meta};return S.ok,S.why
    end,
    rejectRecoveryOverflow=function()S.overflow=S.overflow+1;return false end,
  })
  return M,S
end
local function Q(M,id,stamp)
  return M.QueueReplacement(id,{buildId=id,lastModified=stamp or 2,fingerprintHash='a'},'c1-review')
end
local function Count(M)return M.WorkSnapshot().pendingReplacements end

-- New owner must survive stale queued table removal; no duplicate enqueue.
do
  local M,S=Boot();check(Q(M,'a'),'stale: first queued')
  check(M.ClearRequestedLoadout('a',2),'stale: clear before pump')
  check(Q(M,'a',3),'stale: new exact owner queued')
  M.PumpRecovery(1.5)
  check(#S.calls==0 and Count(M)==1,'stale: old queued table skipped without releasing current')
  M.PumpRecovery(1.5);M.PumpRecovery(1.5)
  check(#S.calls==1 and S.calls[1].wire=='WLRL|Review-Realm|a|c1-review','stale: only current wire sent once')
  S.time=113;M.PumpRecovery(1.5)
  check(Count(M)==1,'expiry: inclusive age plus grace boundary retained')
  S.time=113.01;S.bulk=20;M.PumpRecovery(1.5)
  check(Count(M)==0,'expiry: even bulk pressure does not retain ended owner')
end

-- Newer summary while queued updates the same queue slot and shallow copy.
do
  local M,S=Boot();check(Q(M,'a',2),'winner: queued')
  check(Q(M,'a',3),'winner: queued newer summary')
  check(Count(M)==1 and M.WorkSnapshot().recovery==1,'winner: queued owner not double counted')
  local view=M.PendingReplacement('a');view.lastModified=500
  check(M.PendingReplacement('a').lastModified==3,'winner: returned scalar copy cannot change owner')
  check(not M.ClearRequestedLoadout('a',2),'winner: stale clear blocked')
  M.PumpRecovery(1.5);M.PumpRecovery(1.5)
  check(#S.calls==1,'winner: exactly one transport admission')
end

-- Global in-flight receive protection and terminal no-send cleanup remain separate.
do
  local M,S=Boot();check(Q(M,'a'),'inbound: queued');M.PumpRecovery(1.5)
  S.time=200;S.inbound=true;M.PumpRecovery(1.5)
  check(Count(M)==1,'inbound: active inbound protects late exact identity')
  S.inbound=false;M.PumpRecovery(1.5)
  check(Count(M)==0,'inbound: release once owner completed')
  S.mode='off';check(Q(M,'b'),'off: replacement queued');M.PumpRecovery(1.5)
  check(Count(M)==0 and #S.calls==1,'off: release without another transport call')
end

-- Real legacy depth still invokes existing overflow callback; replacement cap does not.
do
  local M,S=Boot();S.complete=false
  check(M.QueueLegacyRecovery('a'),'legacy: first queue')
  check(M.QueueLegacyRecovery('b'),'legacy: second queue')
  check(not M.QueueLegacyRecovery('c') and S.overflow==1,'legacy: queue depth preserves overflow callback')
  M.Reset();S.complete=true
  check(Q(M,'a') and Q(M,'b'),'counter: fill replacement budget')
  local ok,why=Q(M,'c')
  check(not ok and why=='replacement budget exhausted' and S.overflow==1,'counter: exhaustion has separate reason/callback semantics')
  check(M.StatusSnapshot().replacementBudgetRejected==1,'counter: new rejection counter visible')
  M.Reset();check(Count(M)==0 and M.StatusSnapshot().replacementBudgetRejected==0,'counter: reset clears both counters')
end

-- The public roles-completion path must not replace a live summary owner.
do
  local M,S=Boot();check(Q(M,'a'),'roles: replacement queued');M.PumpRecovery(1.5)
  check(M.PendingReplacement('a')~=nil and Count(M)==1,'roles: sent owner retained')
  local accepted=M.QueueRolesRequest('a')
  print('OBSERVE roles accepted='..tostring(accepted)..' pending='..tostring(M.PendingReplacement('a')~=nil)..' count='..Count(M))
  check(M.PendingReplacement('a')~=nil,'roles: must preserve sent replacement identity')
  S.time=200;M.PumpRecovery(1.5);S.time=300;M.PumpRecovery(1.5)
  M.ClearRequestedLoadout('a',2)
  check(Count(M)==0,'roles: expiry or promotion must release all retained budget')
  check(Q(M,'b'),'roles: remaining first capacity reusable')
  local ok,why=Q(M,'c')
  check(ok,'roles: second capacity reusable without phantom ownership')
  print('OBSERVE roles final count='..Count(M)..' secondAdmission='..tostring(ok)..' reason='..tostring(why))
end

local failed=0
for _,r in ipairs(results)do if not r.ok then failed=failed+1 end end
print(string.format('REVIEW_RESULT checks=%d passed=%d failed=%d',checks,checks-failed,failed))
assert(failed==0,'independent adversarial review failed')
