-- Synthetic native-realm source row and exact response-claim ownership guard.
-- This does not reproduce or attribute the retained live request outcome.
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
local echoes={{spellId=200001,count=3},{spellId=200002,count=1}}
local owner='origin@rogue-lite(live)'
local row={v=7,p='Origin',o=owner,k='MAGE',l=80,c='lk',d=47000,
    u=134.612,t=source.e.time()-100,e=echoes,
    f=D.GetEchoKey(echoes),h=D.GetEchoHash(echoes),
    lk={{spellId=200085,count=1}}}
local bucket=D.SyncBucket('lk','Origin')
check(D.LocalOwnsDpsBucket(bucket)==false,'empty bucket has no local owner')
check(D.ReceiveRecord(row,'Origin-rogue-lite(live)')==true,
    'exact native-channel row admitted as verified owner')
for _=1,200 do source.H.Advance(.05,.05) end
local selected=D.GetCharacterBest('lk')
check(selected and selected.ownerKey==owner and selected.ownerVerified==true,
    'default native fallback finds exact current-owner LK row')
local before=F.Serialize(source.e.NexusDB)
check(D.LocalOwnsDpsBucket(bucket)==true,
    'verified native-owned row prevents equivalent peer claim suppression')
check(F.Serialize(source.e.NexusDB)==before,
    'claim guard leaves saved row byte-identical')
check(D.LocalOwnsDpsBucket(bucket==1 and 2 or 1)==false,
    'unrelated bucket is not claimed under the native realm')
source.e.GetRealmName=function() return 'AnotherRealm' end
check(D.LocalOwnsDpsBucket(bucket)==false,
    'changed native realm cannot borrow prior ownership')
check(#source.H.actions==0 and #P.B.H.actions==0,
    'read-only claim checks perform no game actions')
print('PASS '..checks..' native DPS bucket-claim ownership checks')
