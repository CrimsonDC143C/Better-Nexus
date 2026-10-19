-- Synthetic natural handshake regression. No native/account/network proof.
local P=dofile('tests/prototype/sync_pair_support.lua')
local Q=dofile('tests/prototype/sync_pair_support.lua')
local F=dofile('tests/prototype/format5_support.lua')
local checks=0
local function check(ok,why)assert(ok,why);checks=checks+1 end
local function natural(bare)
 math.randomseed(1)
 P.Boot({'Origin','Recipient'},0,nil,{realm='Rogue-Lite (Live)',realmApis={
  {game='Rogue-Lite (Live)',normalized='RogueLite(Live)'},{game='Rogue-Lite (Live)'}}})
 Q.Boot({'Alpha','Unused'},0,nil,{realm='Rogue-Lite (Live)'})
 local owner,recipient,relay=P.A,P.B,Q.A
 local peers={owner,recipient,relay}
 for _,p in ipairs(peers)do
  check(not p.e.UnitName('player'):find('-',1,true),'literal UnitName is bare')
  p.name=assert(p.e.Nexus.Identity.NativeChannelSender(p.e.UnitName('player')))
 end
 local N=owner.e.Nexus
 local echoes={{spellId=200001,count=3},{spellId=200002,count=1}}
 local payload={v=7,p='Origin',o='origin@rogue-lite(live)',r='rogue-lite(live)',
  k='MAGE',l=80,c='lk',d=47000,u=134.612,t=1700000900,e=echoes,
  f=N.DpsCapture.GetEchoKey(echoes),h=N.DpsCapture.GetEchoHash(echoes),
  lk={{spellId=200085,count=1}}}
 local encoded=N.Codec.Base64Encode(N.Codec.JSONEncode(payload))
 local total=math.ceil(#encoded/100)
 for _,p in ipairs({owner,relay})do
  for i=1,total do P.Channel(p,string.format('WLD2|Origin|fixture-lk:1700000900:47000|%d/%d|%s',
   i,total,encoded:sub((i-1)*100+1,i*100)),owner.name)end
 end
 for _=1,500 do for _,p in ipairs(peers)do p.H.Advance(.05,.05)end end
 check(N.DpsCapture.GetCharacterBest('lk','Origin',payload.o)~=nil,'synthetic source seeded by native ingress')
 check(relay.e.Nexus.DpsCapture.GetCharacterBest('lk','Origin',payload.o)~=nil,'equivalent relay seeded')
 check(recipient.e.Nexus.DpsCapture.GetCharacterBest('lk','Origin')==nil,'empty receiver before request')
 local saved=F.Serialize(owner.e.NexusDB.authorityBundle.dpsCapture)
 for _,p in ipairs(peers)do p.cursor=#p.H.sent;p.e.Nexus.PeerDebug.Start()end
 local firstId,ownerParts,handshakes,addonDps,wireDrops=nil,{},0,0,0
 local directCommit=false
 local function pump(p)
  while p.cursor<#p.H.sent do
   p.cursor=p.cursor+1;local packet=p.H.sent[p.cursor]
   local text=packet.text:gsub('||','|'):gsub('^P%d+:','')
   local code=text:match('^([^|]+)')
   if p==recipient and code=='WLRQ' and not firstId then
    firstId=text:match('^WLRQ|[^|]+|[^|]+|[^|]+|([^|]+)')
   end
   for _,q in ipairs(peers)do
    if q~=p and (packet.route=='chat' or packet.kind~='WHISPER'
     or packet.target==q.name or packet.target==q.e.UnitName('player'))then
     local actual=bare and p.e.UnitName('player') or p.name
     local before=q.e.Nexus.SyncWire.Stats().rejected or 0
     if packet.route=='addon'then
      q.H.Fire('CHAT_MSG_ADDON',packet.prefix,packet.text,packet.kind,actual)
      if code=='HELLO1' or code=='ACK1' then handshakes=handshakes+1 end
     else check(packet.kind=='CHANNEL','real native route');P.Channel(q,packet.text,actual)end
     if code=='WLD2' and firstId and text:find(firstId,1,true) and q==recipient then
      wireDrops=wireDrops+(q.e.Nexus.SyncWire.Stats().rejected or 0)-before
      if packet.route=='addon'then addonDps=addonDps+1 end
      if p==owner then
       local transfer,index,count,data,requester,id,bucket=text:match(
        '^WLD2|[^|]+|([^|]+)|(%d+)/(%d+)|([^|]+)|([^|]+)|([^|]+)|(%d+)$')
       check(id==firstId,'direct egress preserves first request ID')
       check(requester==(bare and 'Recipient' or recipient.name),'exact actual requester context')
       if bare then check(packet.route=='chat','every bare-context owner chunk stays native')end
       ownerParts[tonumber(index)]={text=data,total=tonumber(count),transfer=transfer,bucket=bucket}
      end
     end
    end
   end
  end
 end
 check(recipient.e.Nexus.Sync.RequestSync()==true,'actual RequestSync admitted')
 for _=1,1800 do
  for _,p in ipairs(peers)do p.H.Advance(.05,.05)end
  for _,p in ipairs(peers)do pump(p)end
  for _,event in ipairs(recipient.e.Nexus.PeerDebug.Events())do
   local f=event.fields
   if not directCommit and event.kind=='dps_commit' and f.requestId==firstId and f.peer=='Origin'
    and f.relay==false and f.outcome=='accepted'then
    check(f.nativeOwnerContext==bare,'commit retains expected native provenance')
    check(f.senderForm==(bare and 'bare' or 'qualified'),'commit records literal sender form')
    directCommit=true
   end
  end
 end
 check(firstId~=nil and handshakes>0,'real request plus actual addon handshakes delivered')
 check(wireDrops==0,'matched first-request DPS passed wire gate')
 check(directCommit,'first request has direct owner commit, independent of final getter')
 if bare then check(addonDps==0,'bare contextual transfer has no addon final chunk')
 else check(addonDps>0,'qualified contextual transfer retains negotiated addon route')end
 local chunks={};local count=0
 for i,row in pairs(ownerParts)do chunks[i]=row.text;count=count+1 end
 check(count>0 and count==ownerParts[1].total,'all actual owner first-ID chunks captured')
 local decoded=assert(N.Codec.JSONDecode(N.Codec.Base64Decode(table.concat(chunks))))
 check(decoded.d==payload.d and decoded.t==payload.t and decoded.o==payload.o
  and decoded.x==nil,'direct owner payload keeps score/owner without relay context')
 local D=recipient.e.Nexus.DpsCapture
 local function exact(row,dps)
  return row and row.dps==payload.d and row.ts==payload.t and row.duration==payload.u
   and row.fingerprint==payload.f and dps.VerifiedOwnerKey(row)==payload.o
 end
 check(exact(D.GetCharacterBest('lk','Origin',payload.o),D),'exact verified owner getter')
 check(exact(D.GetCharacterBest('lk','Origin'),D),'named getter displays owner result')
 local displayed=false
 for _,row in ipairs(D.GetDpsBoard('lk'))do if exact(row,D)then displayed=true end end
 check(displayed,'public board displays verified result')
 recipient.e.NexusDB=assert(loadstring('return '..F.Serialize(recipient.e.NexusDB)))()
 local reload=P.Rejoin(2);for _=1,200 do reload.H.Advance(.05,.05)end
 check(exact(reload.e.Nexus.DpsCapture.GetCharacterBest('lk','Origin',payload.o),reload.e.Nexus.DpsCapture),
  'synthetic fresh-runtime persistence retains exact verified row')
 check(F.Serialize(owner.e.NexusDB.authorityBundle.dpsCapture)==saved,'source records unchanged')
 check(#owner.H.actions==0 and #relay.H.actions==0 and #recipient.H.actions==0
  and #reload.H.actions==0,'no gameplay actions')
end
natural(true);natural(false)
-- Route-only controls use real HELLO submission followed by a bounded ACK;
-- the natural end-to-end cases above do not synthesize ACK or confirmation.
local O=dofile('tests/prototype/offline_peer_dps_support.lua').Boot(false)
local W=O.W
O.Negotiate('Recipient');O.Negotiate('Recipient-OtherRealm');O.Negotiate('Origin')
local original='WLD2|Origin|route-t|1/1|YQ==|Recipient|c1-route|1'
local function metadata(changes)
 local m={dataKind='D',requester='Recipient',requestId='c1-route',bucket=1,transferId='route-t'}
 for k,v in pairs(changes or {})do m[k]=v end;return m
end
local function route(text,m,wanted,why)
 O.Refill();local before=#O.H.sent
 local ok,selected=W.SendPacket(text,m,1)
 check(ok and selected==wanted and #O.H.sent==before+1,why)
 local sent=O.H.sent[#O.H.sent]
 check(sent.text:gsub('||','|'):gsub('^P7:','')==text,'route changes no payload bytes')
 return sent
end
route(original,metadata(),'legacy','bounded exact bare-context preference')
route('WLD2|Origin|route-t|1/1|YQ==',metadata(),'addon','unsuffixed legacy DPS retains addon')
route(original..'|extra',metadata(),'addon','extra wire field cannot select preference')
route('WLBC|Origin|Recipient|c1-route|D|1|hash',metadata(),'addon','D-kind claim stays addon')
route(original,metadata({dataKind='B'}),'addon','non-D metadata stays addon')
route(original:gsub('|Recipient|','|Recipient-OtherRealm|'),metadata({requester='Recipient-OtherRealm'}),
 'addon','qualified requester stays addon')
route(original:gsub('|Recipient|','|Other|'),metadata(),'addon','mismatched requester stays addon')
route(original,metadata({requestId='c1-other'}),'addon','mismatched request ID stays addon')
route(original:gsub('c1-route','legacy-route'),metadata({requestId='legacy-route'}),
 'addon','non-contextual ID stays addon')
route(original,metadata({bucket=2}),'addon','mismatched bucket stays addon')
route(original,metadata({bucket=1.5}),'addon','fractional scalar bucket stays addon')
route(original,metadata({bucket=9}),'addon','out-of-range scalar bucket stays addon')
route(original,metadata({transferId='other'}),'addon','mismatched transfer stays addon')
for _,id in ipairs({'bad transfer','bad\127id',string.rep('x',161)})do
 local text=original:gsub('route%-t',id)
 -- The long malformed transfer independently exceeds the addon envelope.
 if #text*2<210 then route(text,metadata({transferId=id}),'addon','malformed transfer cannot select preference')
 else
  local short=original:gsub('route%-t','x')
  route(short,metadata({transferId=id}),'addon','oversized scalar transfer cannot select preference')
 end
end
local policy=Nexus.MainInternals.SavedSyncModeV1
Nexus.MainInternals.SavedSyncModeV1=function()return 'manual'end
local before=#O.H.sent
O.Refill();check(not W.SendPacket(original,metadata(),1) and #O.H.sent==before,'manual refusal retains packets')
Nexus.SyncModePolicy.Bind(function()return 'fixture-grant'end,function()return 'PrototypeTester'end)
route(original,metadata({manualGrant='fixture-grant'}),'legacy','explicit manual grant still uses native response')
Nexus.MainInternals.SavedSyncModeV1=function()return 'off'end
O.Refill();before=#O.H.sent
check(not W.SendPacket(original,metadata({manualGrant='fixture-grant'}),1) and #O.H.sent==before,
 'Off refuses even granted response')
Nexus.MainInternals.SavedSyncModeV1=policy
O.H.combat=true;O.Refill();before=#O.H.sent
check(not W.SendPacket(original,metadata(),1) and #O.H.sent==before,'combat guard stays active')
O.H.combat=false;Nexus.ChatThrottleLib.bQueueing=true
check(not W.SendPacket(original,metadata(),1) and #O.H.sent==before,'CTL queue guard stays active')
Nexus.ChatThrottleLib.bQueueing=false
-- Complete old five-field DPS through actual bare addon reception. It can
-- retain the historical score, but route preference grants it no authority.
local D=Nexus.DpsCapture
local echoes={{spellId=200001,count=1}}
local row={v=7,p='Origin',o='origin@ebonhold',r='Ebonhold',k='MAGE',l=40,
 c='dummy',d=47000,u=180,t=time()-100,e=echoes,
 f=D.GetEchoKey(echoes),h=D.GetEchoHash(echoes)}
local encoded=Nexus.Codec.Base64Encode(Nexus.Codec.JSONEncode(row))
local count=math.ceil(#encoded/65)
for i=1,count do
 local text=string.format('WLD2|Origin|legacy-t|%d/%d|%s',i,count,encoded:sub((i-1)*65+1,i*65))
 local packet=route(text,metadata({transferId='legacy-t'}),'addon','old unsuffixed chunk stays addon')
 W.Receive(packet.prefix,packet.text,packet.kind,'Origin')
end
O.H.Advance(15,.05)
local legacy=D.GetCharacterBest('dummy','Origin')
check(legacy and legacy.dps==row.d and D.VerifiedOwnerKey(legacy)==nil,
 'bare unsuffixed addon historical score remains unverified')
-- The cooldown must still retain requester identity for directed cancellation.
route('X',metadata(),'addon','actual whisper establishes recipient notice window')
O.Block('Recipient');O.Refill();before=#O.H.sent
check(not W.CanDispatch(original,metadata()) and not W.SendPacket(original,metadata(),1)
 and #O.H.sent==before,'offline requester refuses native preference without stripping metadata')
print('PASS bare requester route/natural wire/legacy authority controls checks='..checks)
