-- Real SyncSession, synthetic catalog/clock/transport. Replacement retention is
-- bounded by the receive lifetime, not the lifetime of the client session.
-- No network, saved records, wire/auth changes or WoW runtime is exercised.
Nexus = nil
dofile('core/SyncSession.lua')
local Factory = Nexus.SyncInternals.Session
local checks, failures = 0, {}
local function check(ok, label)
    checks = checks + 1
    if not ok then failures[#failures + 1] = label end
end
local function Boot(mode)
    local S = {clock=100,mode=mode or 'automatic',bulk=0,inbound=false,
        calls={},logs={},overflow=0,queueOK=true,queueWhy=nil}
    local M = Factory.New({
        now=function() return S.clock end,
        myName=function() return 'Receiver-Realm' end,
        normalizePeerName=function(name) return tostring(name or ''):lower() end,
        receiveWindow=5,inflightGrace=3,maxReceiveAge=10,
        maxConvergenceAge=40,maxRecoveryQueue=8,maxKnownPeers=32,
        requestCooldown=0,autoSyncMinPass=0,autoSyncQuiet=0,maxPasses=1,
        syncMode=function() return S.mode end,
        validIdentifier=function(id) return type(id)=='string' and id~='' end,
        catalogGet=function() return {echoes={{spellId=1}}} end,
        transportSnapshot=function() return {bulk=S.bulk} end,
        inboundHasPending=function() return S.inbound end,
        transportHasPending=function() return false end,
        currentBuildHash=function() return 'abc' end,
        currentDpsHash=function() return 'def' end,
        isConnected=function() return true end,
        ensureChannel=function() return true end,
        loadoutRequestCode='WLRL',requestCode='WLRQ',chatLimit=255,
        announceVersion=function() return '1.0.0' end,
        newRequestId=function() return 'c1-budget-request' end,
        enqueueControl=function(wire, metadata)
            S.calls[#S.calls+1]={wire=wire,metadata=metadata}
            return S.queueOK,S.queueWhy
        end,
        rejectRecoveryOverflow=function()
            S.overflow=S.overflow+1
            return false
        end,
        log=function(kind, fmt, ...)
            S.logs[#S.logs+1]=kind..' '..string.format(fmt,...)
        end,
    })
    return M,S
end
local function Replacement(id, stamp)
    return {buildId=id,title='Build '..id,author='Owner-Realm',
        ownerKey='owner@realm',class='MAGE',lastModified=stamp or 1,
        fingerprintHash='abc',echoCount=1}
end
local function Queue(M,id,stamp)
    return M.QueueReplacement(id,Replacement(id,stamp),'c1-budget')
end
local function Fill(M)
    for i=1,8 do check(Queue(M,'build'..i),'admit '..i) end
end
local function PumpAll(M)
    for _=1,8 do M.PumpRecovery(1.5) end
end
local function Count(M) return M.WorkSnapshot().pendingReplacements end

-- Saved-mode refusal is a terminal no-send, not eight permanent owners.
for _,mode in ipairs({'off','manual'}) do
    local M,S=Boot(mode)
    Fill(M);check(Count(M)==8,mode..': bounded eight before pump')
    PumpAll(M)
    check(#S.calls==0,mode..': no transport admission')
    check(Count(M)==0,mode..': terminal no-send releases all eight')
    check(M.PendingReplacement('build1')==nil,mode..': stale identity released')
    check(Queue(M,'after-mode'),mode..': ninth distinct replacement admitted')
end

-- Sent but unanswered: retain through both exact bounds, release only after.
do
    local M,S=Boot();Fill(M);PumpAll(M)
    check(#S.calls==8,'sent: eight admissions')
    check(Count(M)==8,'sent: owners retained after admission')
    S.clock=110;M.PumpRecovery(1.5)
    check(Count(M)==8,'sent: maxReceiveAge boundary retains identity')
    S.clock=113;M.PumpRecovery(1.5)
    check(Count(M)==8,'sent: maxReceiveAge + inflightGrace boundary retained')
    S.clock=113.001;M.PumpRecovery(1.5)
    check(Count(M)==0,'sent: terminal expiry releases unanswered owners')
    check(M.PendingReplacement('build1')==nil,'sent: expired identity released')
    check(Queue(M,'after-expiry'),'sent: capacity reusable without Reset')
end

-- A genuine full budget is explicit; it is not transmit queue pressure.
do
    local M,S=Boot();Fill(M)
    local ok,why=Queue(M,'ninth')
    check(ok==false,'full: ninth refused')
    check(why=='replacement budget exhausted','full: distinct refusal reason')
    check(S.overflow==0,'full: not attributed to transmit queue overflow')
    check(M.WorkSnapshot().replacementBudgetRejected==1,'full: distinct counter')
    check(M.StatusSnapshot().replacementBudgetRejected==1,'full: status counter')
    local found=false
    for _,line in ipairs(S.logs) do
        if line:find('replacement budget exhausted',1,true) then found=true end
    end
    check(found,'full: explicit bounded exhaustion log')
end

-- A deterministic invalid wire has no answer to await. Transient queue full
-- remains queued and owns its capacity rather than being retried unboundedly.
do
    local M,S=Boot();S.queueOK=false;S.queueWhy='invalid packet'
    Fill(M);PumpAll(M)
    check(Count(M)==0,'wire: terminal invalid packet releases budget')
    check(Queue(M,'after-wire'),'wire: capacity reusable')
    M,S=Boot();S.queueOK=false;S.queueWhy='sync queue full'
    Fill(M);M.PumpRecovery(1.5)
    S.clock=1000;M.PumpRecovery(1.5)
    check(Count(M)==8,'pressure: unsent queued work retains all eight owners')
    check(M.WorkSnapshot().recovery==8,'pressure: queue entry not consumed')
    S.queueOK=true;S.queueWhy=nil;PumpAll(M)
    check(#S.calls==10 and Count(M)==8,'pressure: retry then eight admissions')
    check(M.PendingReplacement('build8')~=nil,'pressure: last identity retained')
end

-- Inbound work can begin late. A response already in flight must retain the
-- exact replacement even past the age bound, until the existing owner clears.
do
    local M,S=Boot();Fill(M);PumpAll(M)
    S.clock=109.9;S.inbound=true;M.PumpRecovery(1.5)
    S.clock=114;M.PumpRecovery(1.5)
    check(Count(M)==8,'inflight: late begun response retains budget')
    check(M.PendingReplacement('build1')~=nil,'inflight: exact identity retained')
    check(M.ClearRequestedLoadout('build1',1),'inflight: valid response commits')
    check(Count(M)==7,'inflight: only committed owner released')
    check(Queue(M,'inflight-new'),'inflight: one released slot reused')
    check(Count(M)==8,'inflight: reused capacity bounded')
    S.inbound=false;M.PumpRecovery(1.5)
    check(Count(M)==1,'inflight: terminal unanswered owners now released')
    check(M.PendingReplacement('inflight-new')~=nil,'inflight: unsent new owner kept')
end

-- Other live receive work is also protected; the grace is refreshed by the
-- existing recovery request, not by the expiry scan itself.
do
    local M,S=Boot();Fill(M);PumpAll(M)
    S.clock=112;check(M.QueueRolesRequest('roles'),'receiving: roles queued')
    M.PumpRecovery(1.5)
    S.clock=114;M.PumpRecovery(1.5)
    check(M.IsReceiving(),'receiving: real receive window is still open')
    check(Count(M)==8,'receiving: open receive window retains replacements')
    S.clock=115.001;M.PumpRecovery(1.5)
    check(Count(M)==0,'receiving: expired owners released once window closes')
    local state,at=M.RolesRequestState('roles')
    check(state=='sent' and at==112,'receiving: role state not removed by expiry')
end

-- Same build winner updates, stale promotion rejection, and late peers do
-- not reset or release a different owner's budget.
do
    local M,S=Boot();Fill(M);PumpAll(M)
    S.clock=108;check(Queue(M,'build1',2),'newer: same build requeued')
    check(Count(M)==8,'newer: no double count')
    check(not Queue(M,'build1',2),'newer: equal revision ignored')
    check(not M.ClearRequestedLoadout('build1',1),'newer: stale answer cannot release')
    M.PumpRecovery(1.5)
    S.clock=114;M.MarkPeer('Late-Realm','1.0.0');M.PumpRecovery(1.5)
    check(Count(M)==1,'newer: only older terminal owners expire')
    check(M.PendingReplacement('build1').lastModified==2,'newer: exact winner retained')
    check(M.IsKnownPeer('Late-Realm'),'late peer: recognition unchanged')
    check(M.ClearRequestedLoadout('build1',2),'newer: valid response clears once')
    check(M.ClearRequestedLoadout('build1',2),'newer: repeated cleanup is harmless')
    check(Count(M)==0,'newer: no count underflow')
    M.Reset();check(Count(M)==0,'reset: no retained budget')
    check(M.WorkSnapshot().replacementBudgetRejected==0,'reset: rejection counter resets')
end

for _,message in ipairs(failures) do print('FAIL '..message) end
assert(#failures==0,string.format('%d/%d replacement-budget checks failed',#failures,checks))
print(string.format('PASS sync_replacement_budget: %d checks',checks))
