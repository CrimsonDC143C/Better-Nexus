-- Real Session late-role lifecycle; synthetic clock/catalog/transport only.
Nexus=nil
dofile('core/SyncSession.lua')
local F=Nexus.SyncInternals.Session
local checks=0
local function check(ok,message) checks=checks+1;assert(ok,message) end
local function Boot()
    local state={now=100,mode='automatic',calls={},caps={}}
    local M=F.New({
        now=function() return state.now end,
        myName=function() return 'Receiver-Realm' end,
        normalizePeerName=function(x) return tostring(x or ''):lower() end,
        syncMode=function() return state.mode end,
        maxRecoveryQueue=8,maxKnownPeers=32,maxReceiveAge=10,inflightGrace=3,
        receiveWindow=5,validIdentifier=function(x) return type(x)=='string' and x~='' end,
        transportSnapshot=function() return {bulk=0} end,
        inboundHasPending=function() return false end,
        catalogGet=function() return {echoes={{spellId=1}}} end,
        isConnected=function() return true end,
        loadoutRequestCode='WLLQ',
        advertiseCapability=function(metadata,force)
            state.caps[#state.caps+1]=force
            return true,true
        end,
        enqueueControl=function(wire,metadata)
            state.calls[#state.calls+1]={wire=wire,metadata=metadata}
            return true
        end,
    })
    return M,state
end
local function Queue(M)
    return M.QueueReplacement('a',{buildId='a',lastModified=2,
        fingerprintHash='aa'},'c1-lifecycle')
end

-- Both queued and sent replacement owners refuse the weaker roles-only
-- transition. No extra queue slot or transport call is created.
do
    local M,S=Boot()
    check(Queue(M),'queued: replacement admitted')
    check(not M.QueueRolesRequest('a'),'queued: weaker roles request declined')
    check(M.WorkSnapshot().recovery==1,'queued: one queue slot only')
    M.PumpRecovery(1.5)
    check(#S.calls==1 and M.PendingReplacement('a')~=nil,'sent: exact replacement sent once')
    check(not M.QueueRolesRequest('a'),'sent: weaker roles request declined')
    check(M.RolesRequestState('a')==nil,'sent: no false roles request state')
    check(M.PendingReplacement('a').lastModified==2,'sent: exact winner preserved')
    check(not M.ClearRequestedLoadout('a',1),'sent: stale answer cannot clear winner')
    check(M.WorkSnapshot().pendingReplacements==1,'sent: exact budget owner remains counted')
    S.now=114;M.PumpRecovery(1.5)
    check(M.PendingReplacement('a')==nil,'expired: ended owner released')
    check(M.WorkSnapshot().pendingReplacements==0,'expired: no phantom budget')
    check(M.QueueRolesRequest('a'),'expired: new deliberate roles request allowed')
    check(M.RolesRequestState('a')=='queued','expired: genuine queued roles status')
    M.PumpRecovery(1.5)
    local status,at=M.RolesRequestState('a')
    check(status=='sent' and at==114,'expired: late roles request actually sent')
    check(#S.calls==2 and S.calls[2].wire=='WLLQ|Receiver-Realm|a','expired: one unchanged late roles wire')
    check(S.caps[#S.caps]==true,'expired: late role request forces existing capability path')
    check(M.WorkSnapshot().pendingReplacements==0,'expired: roles-only send has no replacement count')
end

-- A valid promotion can end the replacement before timeout; a later roles
-- request still uses the original mode/wire state and can be refused by mode.
do
    local M,S=Boot()
    check(Queue(M),'promotion: replacement admitted');M.PumpRecovery(1.5)
    check(M.ClearRequestedLoadout('a',2),'promotion: exact winner cleared')
    check(M.WorkSnapshot().pendingReplacements==0,'promotion: capacity released once')
    check(M.QueueRolesRequest('a'),'promotion: roles request allowed after completion')
    S.mode='off';M.PumpRecovery(1.5)
    local status,why=M.RolesRequestState('a')
    check(status=='unsent' and why=='mode','promotion: existing roles no-send state retained')
    check(#S.calls==1,'promotion: mode refusal adds no transport call')
    check(M.WorkSnapshot().pendingReplacements==0,'promotion: no phantom replacement after roles refusal')
end
print(string.format('PASS sync_replacement_roles_lifecycle: %d checks',checks))
