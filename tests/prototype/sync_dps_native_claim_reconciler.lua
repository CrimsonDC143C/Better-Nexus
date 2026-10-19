-- Contextual peer claims must not suppress a verified current-owner LK row.
-- Offline reconciler exercise only: it does not establish live delivery.
local P=dofile('tests/prototype/sync_pair_support.lua')
local F=dofile('tests/prototype/format5_support.lua')
local checks=0
local function check(ok,reason) assert(ok,reason); checks=checks+1 end

P.Boot({'Origin','Recipient'},0,nil,{realm='Rogue-Lite (Live)',realmApis={
    {game='Rogue-Lite (Live)',normalized='RogueLite(Live)'},
    {game='Rogue-Lite (Live)'},
}})
local source=P.A
local N=source.e.Nexus
local D=N.DpsCapture
local Reconciler=N.SyncInternals.Reconciler
local owner='origin@rogue-lite(live)'
local echoes={{spellId=200001,count=3},{spellId=200002,count=1}}
local row={v=7,p='Origin',o=owner,k='MAGE',l=80,c='lk',d=47000,
    u=134.612,t=source.e.time()-100,e=echoes,
    f=D.GetEchoKey(echoes),h=D.GetEchoHash(echoes),
    lk={{spellId=200085,count=1}}}
local bucket=D.SyncBucket('lk','Origin')
check(D.ReceiveRecord(row,'Origin-rogue-lite(live)')==true,
    'verified native owner row admitted')
for _=1,200 do source.H.Advance(.05,.05) end
local selected=D.GetCharacterBest('lk')
check(selected and selected.ownerKey==owner and selected.ownerVerified==true,
    'default lookup selects verified native row')
check(D.LocalOwnsDpsBucket(bucket)==true,
    'native row owns its exact response bucket')
local saved=F.Serialize(source.e.NexusDB)

local zero='0,0,0,0,0,0,0,0'
local localBuckets={'0','0','0','0','0','0','0','0'}
localBuckets[bucket]='native-owner-hash'
local localHash=table.concat(localBuckets,',')
local function splitHashes(hash)
    local parts={}
    for part in tostring(hash):gmatch('[^,]+') do
        parts[#parts+1]=part
    end
    return parts
end
local function reconciler()
    return Reconciler.New({
        bucketCount=8,maxPendingResponses=4,maxPendingLoadouts=4,
        pendingTtl=60,pendingMaxAge=120,claimDelayMin=0,
        claimDelayMax=1,bucketClaimMax=1,
        now=function() return source.e.time() end,
        myName=function() return 'Origin' end,
        stableDelay=function(key)
            return tostring(key):find('Alpha',1,true) and 0 or 1
        end,
        splitHashes=splitHashes,
        deltaBuildHash=function() return zero end,
        currentBuildHash=function() return zero end,
        currentDpsHash=function() return localHash end,
        catalogToken=function() return 'catalog' end,
        buildCandidateSnapshot=function() error('no build bucket expected') end,
        snapshotCurrent=function() return true end,
        bucketClaimable=function() return false end,
        backpressured=function() return false end,
        catalogGet=function() return nil end,
        prepareBuild=function() return nil end,
        admitBuild=function() return false end,
        sendNextBuild=function() error('no send expected') end,
        sendDpsBucket=function() error('no send expected') end,
        publishLoadoutClaim=function() return false end,
        publishBucketClaim=function() return false end,
        supportsRequestContext=function(id) return id=='c1-native-owner' end,
        localOwnsDpsBucket=function(b) return D.LocalOwnsDpsBucket(b) end,
        dpsBucketClaimInfo=function() return true,'unrelated@realm' end,
        isLocalPeer=function(peer) return peer=='Origin' end,
        isSelfRequest=function(peer) return peer=='Origin' end,
        transportOwnsOwner=function() return false end,
        noteSyncStat=function() end,
        log=function() end,
    })
end
local request={requester='Recipient',requestId='c1-native-owner',
    peerBuildHash=zero,peerDpsHash=zero}
local bucketClaim={responder='Alpha',requester='Recipient',
    requestId='c1-native-owner',kind='D',bucket=bucket,
    hash='native-owner-hash'}
local responseClaim={responder='Alpha',requester='Recipient',
    requestId='c1-native-owner',buildHash=zero,dpsHash=localHash}
local function prepared()
    local R=reconciler()
    check(R.ScheduleRequest(request)==true,'contextual request scheduled')
    R.Process(2) -- exactly one preparation turn; no bucket send
    check(R.Stats().entryPreparations==1 and R.Counts().responses==1,
        'one contextual DPS response prepared')
    return R
end

local bucketOwner=prepared()
check(bucketOwner.HandleBucketClaim(bucketClaim)==false,
    'equivalent WLBC cannot suppress verified native-owner bucket')
check(bucketOwner.Counts().responses==1,
    'owner response remains pending after WLBC')
local wholeOwner=prepared()
check(wholeOwner.HandleLegacyClaim(responseClaim)==true,
    'equivalent whole-response claim processed')
check(wholeOwner.Counts().responses==1,
    'owner response remains pending after whole-response claim')

source.e.GetRealmName=function() return 'AnotherRealm' end
check(D.LocalOwnsDpsBucket(bucket)==false,
    'different current realm cannot claim original row')
local bucketRelay=prepared()
check(bucketRelay.HandleBucketClaim(bucketClaim)==true,
    'non-owner relay accepts equivalent WLBC')
check(bucketRelay.Counts().responses==0,
    'non-owner response suppressed by equivalent WLBC')
local wholeRelay=prepared()
check(wholeRelay.HandleLegacyClaim(responseClaim)==true,
    'non-owner whole-response claim processed')
check(wholeRelay.Counts().responses==0,
    'non-owner response yields to equivalent higher-ranked claimant')
check(F.Serialize(source.e.NexusDB)==saved,
    'claims leave saved record byte-identical')
check(#source.H.actions==0 and #P.B.H.actions==0,
    'reconciler test performs no game actions')
print('PASS '..checks..' contextual native DPS claim checks')
