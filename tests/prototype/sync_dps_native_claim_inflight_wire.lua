-- Synthetic offline regression ONLY: no native client/account/network proof.
-- Real RequestSync -> channel fallback -> equivalent peer claim -> DPS wire
-- egress -> receiver getter/board -> serialized fresh-runtime persistence.
-- The optional normalized-realm owner must survive another responder's claim.
local P=dofile('tests/prototype/sync_pair_support.lua')
local Q=dofile('tests/prototype/sync_pair_support.lua')
local F=dofile('tests/prototype/format5_support.lua')
math.randomseed(812733)
P.Boot({'Origin','Recipient'},0,function(i,db)
 if i==2 then
  db.settingsVersion=5;db.accountCharacters={};db.settings.syncMode='manual'
 end
end,{realm='Rogue-Lite (Live)',realmApis={
 {game='Rogue-Lite (Live)',normalized='RogueLite(Live)'},
 {game='Rogue-Lite (Live)'},
}})
Q.Boot({'Alpha','Unused'},0,nil,{realm='Rogue-Lite (Live)'})
local owner,receiver,relay=P.A,P.B,Q.A
local peers={owner,receiver,relay}
-- pair_support's transport labels hardcode -Ebonhold. Use the actual native
-- same-realm sender metadata for each synthetic peer, including requester.
for _,p in ipairs(peers) do
 p.name=assert(p.e.Nexus.Identity.NativeChannelSender(p.e.UnitName('player')))
end
local checks=0
local function check(value,reason) assert(value,reason);checks=checks+1 end
local function advance(seconds)
 for _=1,math.floor(seconds/.05+.5) do
  for _,p in ipairs(peers) do p.H.Advance(.05,.05) end
 end
end
local N=owner.e.Nexus
local echoes={{spellId=200001,count=3},{spellId=200002,count=1}}
-- Only initial fixture data is synthetic. ReceiveRecord performs the existing
-- native-qualified owner admission; no saved score/authority flag is edited.
local payload={v=7,p='Origin',o='origin@rogue-lite(live)',r='rogue-lite(live)',
 k='MAGE',l=80,c='lk',d=47000,u=134.612,t=1700000900,e=echoes,
 f=N.DpsCapture.GetEchoKey(echoes),h=N.DpsCapture.GetEchoHash(echoes),
 lk={{spellId=200085,count=1}}}
for _,p in ipairs({owner,relay}) do
 check(p.e.Nexus.DpsCapture.ReceiveRecord(payload,owner.name)==true,
  'synthetic native-owned seed admitted')
end
advance(25)
-- Supported no-profile-clock catalog pacing and 300ms ordered peer latency
-- expose a claim arriving after DPS queue admission while a build prepares.
-- Nothing is lost/reordered; no product hash, claim or delay is overridden.
owner.T.SingleSlicePacing()
local sourceRow=assert(N.DpsCapture.GetCharacterBest('lk','Origin',payload.o))
local page=assert(N.BuildCatalog.Get(sourceRow.buildId))
check(receiver.e.Nexus.BuildCatalog.Get(page.id)==nil,
 'receiver initially lacks the generated build page too')
check(receiver.e.Nexus.DpsCapture.GetCharacterBest('lk','Origin')==nil,
 'receiver initially lacks synthetic LK score')
check(receiver.e.Nexus.SyncModePolicy.Mode()=='manual',
 'supported saved Manual setting forces native reply/claim fallback')
local sourceBuild,sourceDps=N.Sync.GetCompatibilityHashes()
local relayBuild,relayDps=relay.e.Nexus.Sync.GetCompatibilityHashes()
local receiverBuild,receiverDps=receiver.e.Nexus.Sync.GetCompatibilityHashes()
check(sourceBuild==relayBuild and sourceBuild~=receiverBuild,
 'real catalog digests expose missing receiver page')
check(sourceDps==relayDps and sourceDps~=receiverDps,
 'real DPS digests expose only missing receiver evidence')
local bucket=N.DpsCapture.SyncBucket('lk','Origin')
local ownSafe,ownAuthority=N.DpsCapture.ResponseBucketClaimInfo(bucket)
local relaySafe,relayAuthority=relay.e.Nexus.DpsCapture.ResponseBucketClaimInfo(bucket)
check(ownSafe and relaySafe and ownAuthority==payload.o and relayAuthority==payload.o,
 'actual digest claims carry matching native row authority')
local savedSource=F.Serialize(owner.e.NexusDB.authorityBundle.dpsCapture)
for _,p in ipairs(peers) do p.cursor=#p.H.sent end
local requestId
local delayed={}
local ownerChunks,ownerTotal={},nil
local relayClaimSeen,requestSeen=false,false
local ownerClaimSeen,relayDpsChunks=0,0
local function deliver(p,q,packet)
 local text=packet.text:gsub('||','|'):gsub('^P%d+:','')
 local code=text:match('^([^|]+)')
 if p==receiver and code=='WLRQ' then
  local id=text:match('^WLRQ|[^|]+|[^|]+|[^|]+|([^|]+)')
  requestId=requestId or id;requestSeen=true
 end
 if requestId and text:find(requestId,1,true) then
  if p==relay and q==owner and code=='WLRC' then
   check(packet.route=='chat' and packet.kind=='CHANNEL',
    'equivalent real peer claim reaches source on native channel')
   relayClaimSeen=true
  elseif p==owner and q==receiver and code=='WLBC' then
   ownerClaimSeen=ownerClaimSeen+1
  end
  if q==receiver and code=='WLD2' then
   local index,total,data,requester,id,part=text:match(
    '^WLD2|[^|]+|[^|]+|(%d+)/(%d+)|([^|]+)|([^|]+)|([^|]+)|([^|]+)$')
   if id==requestId and p==owner then
    check(requester==receiver.name and tonumber(part)==bucket,
     'real owner DPS chunks preserve exact requester/ID/bucket')
    check(packet.route=='chat' and packet.kind=='CHANNEL','owner uses real native fallback')
    ownerChunks[tonumber(index)]=data;ownerTotal=tonumber(total)
   elseif id==requestId and p==relay then relayDpsChunks=relayDpsChunks+1 end
  end
 end
 if packet.route=='chat' and packet.kind=='CHANNEL' then P.Channel(q,packet.text,p.name)
 elseif packet.route=='addon' then
  q.H.Fire('CHAT_MSG_ADDON',packet.prefix,packet.text,packet.kind,p.name)
 else error('unmodelled captured route '..tostring(packet.route)..'/'..tostring(packet.kind)) end
end
local function pump(p)
 while p.cursor<#p.H.sent do
  p.cursor=p.cursor+1
  local packet=p.H.sent[p.cursor]
  for _,q in ipairs(peers) do
   if q~=p and (packet.route=='chat' or packet.kind~='WHISPER'
      or packet.target==q.name or packet.target==q.e.UnitName('player')) then
    if p==relay and q==owner then
     delayed[#delayed+1]={from=p,to=q,packet=packet,due=owner.H.now+.30}
    else deliver(p,q,packet) end
   end
  end
 end
end
check(receiver.e.Nexus.Sync.RequestSync()==true,'real Manual RequestSync admitted')
for _=1,800 do -- existing .05 step, no latency/loss/reordering, 40s hard bound
 for _,p in ipairs(peers) do p.H.Advance(.05,.05) end
 while delayed[1] and owner.H.now>=delayed[1].due do
  local item=table.remove(delayed,1);deliver(item.from,item.to,item.packet)
 end
 for _,p in ipairs(peers) do pump(p) end
end
check(requestSeen and requestId~=nil,'production request ID captured')
check(relayClaimSeen,'actual equivalent peer WLRC reached source')
local count=0;for _ in pairs(ownerChunks) do count=count+1 end
print('OBSERVED synthetic native LK request='..tostring(requestId)
 ..' ownerChunks='..count..'/'..tostring(ownerTotal)
 ..' relayChunks='..relayDpsChunks..' ownerBucketClaims='..ownerClaimSeen)
-- This is intentionally the first baseline-sensitive assertion. It fails
-- after actual request/claim routing, never at a preliminary owner getter.
check(ownerTotal~=nil and count==ownerTotal,
 'equivalent real peer claim must preserve complete direct-owner DPS egress')
local wire=N.Codec.JSONDecode(N.Codec.Base64Decode(table.concat(ownerChunks)))
check(wire and wire.c==payload.c and wire.o==payload.o and wire.d==payload.d
 and wire.t==payload.t and wire.u==payload.u and wire.f==payload.f,
 'captured production transfer preserves exact synthetic evidence')
local D=receiver.e.Nexus.DpsCapture
local exact=D.GetCharacterBest('lk','Origin',payload.o)
local named=D.GetCharacterBest('lk','Origin')
local function matches(row,reader)
 return row and row.dps==payload.d and row.ts==payload.t and row.duration==payload.u
  and row.fingerprint==payload.f and reader.VerifiedOwnerKey(row)==payload.o
end
check(matches(exact,D) and matches(named,D),'exact/named public getters retain verified owner evidence')
local boardMatch=false
for _,row in ipairs(D.GetDpsBoard('lk') or {}) do
 if matches(row,D) then boardMatch=true end
end
check(boardMatch,'public LK board projection includes exact verified synthetic score')
check(receiver.e.Nexus.BuildCatalog.Get(page.id)~=nil,
 'same initial request also retains the formerly missing build page')
check(F.Serialize(owner.e.NexusDB.authorityBundle.dpsCapture)==savedSource,
 'source saved DPS evidence remains byte-identical')
receiver.e.NexusDB=assert(loadstring('return '..F.Serialize(receiver.e.NexusDB)))()
local reloaded=P.Rejoin(2)
for _=1,200 do reloaded.H.Advance(.05,.05) end
local RD=reloaded.e.Nexus.DpsCapture
check(matches(RD.GetCharacterBest('lk','Origin',payload.o),RD)
 and matches(RD.GetCharacterBest('lk','Origin'),RD),
 'serialized fresh-runtime reload preserves exact/named record and verified authority')
local reloadBoard=false
for _,row in ipairs(RD.GetDpsBoard('lk') or {}) do
 if matches(row,RD) then reloadBoard=true end
end
check(reloadBoard,'fresh runtime public LK board preserves same synthetic evidence')
check(#owner.H.actions==0 and #relay.H.actions==0 and #receiver.H.actions==0
 and #reloaded.H.actions==0,'no gameplay action')
print('PASS '..checks..' synthetic offline real-wire native LK owner-claim checks')
