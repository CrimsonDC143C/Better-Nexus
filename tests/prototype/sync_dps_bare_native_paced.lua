-- External synthetic production-event probe only; no native client proof.
-- First RequestSync and unchanged captured WLD2 packets, paced at +40/+65/+90.
-- No handler injection, source edits, saved-score edits, or fabricated authority.
local P=dofile('tests/prototype/sync_pair_support.lua')
local F=dofile('tests/prototype/format5_support.lua')
math.randomseed(1)
local checks=0
local function check(ok,reason) assert(ok,reason);checks=checks+1 end
P.Boot({'Origin','Recipient'},0,function(i,db)
 if i==2 then db.settingsVersion=5;db.accountCharacters={};db.settings.syncMode='manual' end
end,{realm='Rogue-Lite (Live)',realmApis={
 {game='Rogue-Lite (Live)',normalized='RogueLite(Live)'},
 {game='Rogue-Lite (Live)'},
}})
local source,receiver=P.A,P.B
for _,p in ipairs({source,receiver}) do
 p.name=p.e.UnitName('player')..'-rogue-lite(live)'
end
local N=source.e.Nexus
local echoes={{spellId=200001,count=3},{spellId=200002,count=1}}
local fixture={v=7,p='Origin',o='origin@rogue-lite(live)',r='rogue-lite(live)',
 k='MAGE',l=80,c='lk',d=47000,u=134.612,t=1700000900,e=echoes,
 f=N.DpsCapture.GetEchoKey(echoes),h=N.DpsCapture.GetEchoHash(echoes),
 lk={{spellId=200085,count=1}}}
local encoded=N.Codec.Base64Encode(N.Codec.JSONEncode(fixture))
local total=math.ceil(#encoded/100)
for i=1,total do
 P.Channel(source,string.format('WLD2|Origin|fixture-lk:1700000900:47000|%d/%d|%s',
  i,total,encoded:sub((i-1)*100+1,i*100)),source.name)
end
local function advance(seconds)
 for _=1,math.floor(seconds/.05+.5) do
  source.H.Advance(.05,.05);receiver.H.Advance(.05,.05)
 end
end
advance(25)
local sourceRow=assert(N.DpsCapture.GetCharacterBest('lk','Origin',fixture.o))
local seedStart=#source.H.sent
check(N.Sync.BroadcastBuild(assert(N.BuildCatalog.Get(sourceRow.buildId)))==true,
 'synthetic public page seed admitted through production export')
advance(15)
local function wire(packet) return packet.text:gsub('||','|'):gsub('^P%d+:','') end
local seeded=0
for i=seedStart+1,#source.H.sent do
 local packet=source.H.sent[i]
 if wire(packet):match('^WLRB|') then
  P.Channel(receiver,packet.text,source.name);seeded=seeded+1
 end
end
advance(10)
check(seeded>0 and receiver.e.Nexus.BuildCatalog.Get(sourceRow.buildId),
 'receiver has captured real public page before measured request')
check(receiver.e.Nexus.DpsCapture.GetCharacterBest('lk','Origin',fixture.o)==nil,
 'receiver lacks measured synthetic LK row')
local savedSource=F.Serialize(source.e.NexusDB.authorityBundle.dpsCapture)
for _,p in ipairs({source,receiver}) do
 p.cursor=#p.H.sent
 check(p.e.Nexus.PeerDebug.Start()==true,'bounded diagnostic trace started')
end
local requestId,requestAt,transferId,bucket
local packets,deliveryAt={},{}
local expectedAt={40,65,90}
local function deliver(p,q,packet)
 check(packet.route=='chat' and packet.kind=='CHANNEL','measured route remains native CHANNEL')
 P.Channel(q,packet.text,p.e.UnitName('player'))
end
local function pump(p,q)
 while p.cursor<#p.H.sent do
  p.cursor=p.cursor+1
  local packet=p.H.sent[p.cursor]
  local text=wire(packet)
  if p==receiver and text:match('^WLRQ|') and not requestId then
   requestId=text:match('^WLRQ|[^|]+|[^|]+|[^|]+|([^|]+)')
   requestAt=receiver.H.now
  end
  local held=false
  if p==source and text:match('^WLD2|') then
   local transfer,index,n,requester,id,part=text:match(
    '^WLD2|[^|]+|([^|]+)|(%d+)/(%d+)|[^|]+|([^|]+)|([^|]+)|(%d+)$')
   if id==requestId then
    check(tonumber(n)==3,'actual production transfer contains exactly three chunks')
    check(requester==receiver.e.UnitName('player'),'captured requester is genuinely bare')
    transferId=transferId or transfer;bucket=bucket or tonumber(part)
    check(transfer==transferId and tonumber(part)==bucket,'one unchanged captured transfer/context')
    index=tonumber(index)
    if not packets[index] then packets[index]=packet end
    held=true
   end
  end
  if not held then
   if packet.route=='chat' then deliver(p,q,packet)
   elseif packet.route=='addon' and (packet.kind~='WHISPER'
      or packet.target==q.name or packet.target==q.e.UnitName('player')) then
    q.H.Fire('CHAT_MSG_ADDON',packet.prefix,packet.text,packet.kind,p.name)
   end
  end
 end
end
check(receiver.e.Nexus.Sync.RequestSync()==true,'first real manual RequestSync admitted')
local checked61,checked89=false,false
for _=1,2200 do -- 110 synthetic seconds, no actual sleep
 source.H.Advance(.05,.05);receiver.H.Advance(.05,.05)
 pump(receiver,source);pump(source,receiver)
 if requestAt then
  local age=receiver.H.now-requestAt
  for index=1,3 do
   if packets[index] and not deliveryAt[index] and age>=expectedAt[index] then
    deliveryAt[index]=age
    deliver(source,receiver,packets[index])
    local work=receiver.e.Nexus.Sync.Stats()
    print(string.format('PACED_CHUNK index=%d request=%s transfer=%s age=%.3f receiving=%s useful=%s',
     index,requestId,transferId,age,tostring(receiver.e.Nexus.Sync.IsReceiving()),tostring(work.useful)))
   end
  end
  if age>=61 and not checked61 then
   checked61=true
   check(deliveryAt[1]~=nil and deliveryAt[2]==nil,'one partial chunk received past original 60-second window')
   local work=receiver.e.Nexus.Sync.Stats()
   print('PACED_BOUNDARY age='..string.format('%.3f',age)..' request='..tostring(work.requestId)
    ..' receiving='..tostring(receiver.e.Nexus.Sync.IsReceiving()))
   check(work.requestId==requestId and receiver.e.Nexus.Sync.IsReceiving(),
    'native bare local requester preserves original request receive window past +60')
  end
  if age>=89 and not checked89 then
   checked89=true
   local work=receiver.e.Nexus.Sync.Stats()
   check(deliveryAt[2]~=nil and deliveryAt[3]==nil,'second partial chunk precedes final after original window')
   check(work.requestId==requestId and receiver.e.Nexus.Sync.IsReceiving(),
    'second native partial chunk preserves same request quiet window')
  end
  if deliveryAt[3] and age>=deliveryAt[3]+5 then break end
 end
end
check(type(requestId)=='string' and checked61 and checked89,'actual first request and both paced boundaries observed')
for index=1,3 do
 check(deliveryAt[index] and deliveryAt[index]>=expectedAt[index]
  and deliveryAt[index]<expectedAt[index]+.1,'scheduled chunk delivery retains exact production packet')
 if index>1 then check(deliveryAt[index]-deliveryAt[index-1]<30,'chunk gap stays under existing inflight grace') end
end
local RD=receiver.e.Nexus.DpsCapture
local exact=RD.GetCharacterBest('lk','Origin',fixture.o)
local named=RD.GetCharacterBest('lk','Origin')
local function matches(row)
 return row and row.dps==fixture.d and row.ts==fixture.t and row.duration==fixture.u
  and row.fingerprint==fixture.f and RD.VerifiedOwnerKey(row)==fixture.o
end
check(matches(exact) and matches(named),'actual delayed admission populates exact/named public getters')
local onBoard=false
for _,row in ipairs(RD.GetDpsBoard('lk') or {}) do if matches(row) then onBoard=true end end
check(onBoard,'actual public LK board contains exact synthetic verified score')
local stats=receiver.e.Nexus.Sync.Stats()
local work=receiver.e.Nexus.Sync.Stats()
check(stats.dpsDirectAccepted==1 and (stats.dpsRelayAccepted or 0)==0,
 'same delayed request remains direct owner admission')
check(work.requestId==requestId and work.useful==true and work.requestLastReason=='accepted',
 'exact original request records useful final progress')
local correlated=false
for _,event in ipairs(receiver.e.Nexus.PeerDebug.Events()) do
 local f=event.fields
 if event.kind=='dps_commit' and f.requestId==requestId and f.transferId==transferId
  and f.requester=='Recipient' and f.bucket==bucket and f.outcome=='accepted' and f.relay==false then
  correlated=true
 end
end
check(correlated,'retained diagnostic commit matches original captured transfer and requester')
check(F.Serialize(source.e.NexusDB.authorityBundle.dpsCapture)==savedSource,
 'source scores and provenance remain byte-identical')
check(#source.H.actions==0 and #receiver.H.actions==0,'zero harness gameplay actions')
print('PASS paced_bare_native_probe checks='..checks..' request='..requestId
 ..' transfer='..transferId..' final_age='..string.format('%.3f',deliveryAt[3])
 ..' directAccepted='..tostring(stats.dpsDirectAccepted)..' useful='..tostring(work.useful))
