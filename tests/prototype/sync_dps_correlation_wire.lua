-- Synthetic offline production transport only; no client/account/network data.
-- Match captured RequestSync/WLD2 wire IDs to detached diagnostic events.
local P=dofile('tests/prototype/sync_pair_support.lua')
local F=dofile('tests/prototype/format5_support.lua')
math.randomseed(1)
local checks=0
local function check(ok,why) assert(ok,why);checks=checks+1 end
local function run(enabled)
math.randomseed(1)
P.Boot({'Origin','Recipient'},0,function(i,db)
 if i==2 then db.settingsVersion=5;db.accountCharacters={};db.settings.syncMode='manual' end
end,{realm='Rogue-Lite (Live)'})
local source,receiver=P.A,P.B
for _,p in ipairs({source,receiver}) do
 p.name=p.e.UnitName('player')..'-rogue-lite(live)'
end
local N=source.e.Nexus
local echoes={{spellId=200001,count=3},{spellId=200002,count=1}}
local row={v=7,p='Origin',o='origin@rogue-lite(live)',r='rogue-lite(live)',
 k='MAGE',l=80,c='lk',d=47000,u=134.612,t=1700000900,e=echoes,
 f=N.DpsCapture.GetEchoKey(echoes),h=N.DpsCapture.GetEchoHash(echoes),
 lk={{spellId=200085,count=1}}}
local encoded=N.Codec.Base64Encode(N.Codec.JSONEncode(row))
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
local syntheticRow=assert(N.DpsCapture.GetCharacterBest('lk','Origin',row.o))
local seedStart=#source.H.sent
check(N.Sync.BroadcastBuild(assert(N.BuildCatalog.Get(syntheticRow.buildId)))==true,
 'public synthetic catalog seed accepted')
advance(15)
local seeded=0
local function wire(packet) return packet.text:gsub('||','|'):gsub('^P%d+:','') end
for i=seedStart+1,#source.H.sent do
 local packet=source.H.sent[i]
 if wire(packet):match('^WLRB|') then
  P.Channel(receiver,packet.text,source.name);seeded=seeded+1
 end
end
advance(10)
check(seeded>0 and receiver.e.Nexus.BuildCatalog.Get(syntheticRow.buildId)~=nil,
 'captured public build egress established receiver page')
check(receiver.e.Nexus.DpsCapture.GetCharacterBest('lk','Origin',row.o)==nil,
 'receiver has no synthetic LK record before measured request')
local saved=F.Serialize(source.e.NexusDB.authorityBundle.dpsCapture)
for _,p in ipairs({source,receiver}) do
 p.cursor=#p.H.sent
 if enabled then check(p.e.Nexus.PeerDebug.Start()==true,'bounded trace started')
 else p.e.Nexus.PeerDebug.Clear() end
end
local requestId
local transfers,responsePackets={},{}
local captured,traffic,rawTraffic=0,{},{}
local function pump(p,q)
 while p.cursor<#p.H.sent do
  p.cursor=p.cursor+1
  local packet=p.H.sent[p.cursor]
  local rawEvent={peer=p.name,text=packet.text,route=packet.route,
   kind=packet.kind,target=packet.target,prefix=packet.prefix}
  rawTraffic[#rawTraffic+1]=rawEvent
  local comparisonText=packet.text
  -- The unrelated WLCP session token varies between fresh runtimes. Keep
  -- raw bytes above; compare only that opaque final token canonically. All
  -- request, claim and DPS packet bytes/IDs remain untouched in this check.
  if wire(packet):match('^WLCP|') then
   comparisonText=wire(packet):gsub('^(WLCP|[^|]+|[^|]+|)[^|]+$','%1<opaque-session-token>')
  end
  traffic[#traffic+1]={peer=p.name,text=comparisonText,route=packet.route,
   kind=packet.kind,target=packet.target,prefix=packet.prefix}
  local text=wire(packet)
  if p==receiver and text:match('^WLRQ|') and not requestId then
   requestId=text:match('^WLRQ|[^|]+|[^|]+|[^|]+|([^|]+)')
  end
  if p==source and text:match('^WLD2|') then
   local transfer,requester,id,bucket=text:match(
    '^WLD2|[^|]+|([^|]+)|[^|]+|[^|]+|([^|]+)|([^|]+)|(%d+)$')
   if transfer then
    transfers[transfer]={requester=requester,requestId=id,bucket=tonumber(bucket)}
    responsePackets[#responsePackets+1]={packet=packet,requestId=id}
    captured=captured+1
   end
  end
  if packet.route=='chat' then P.Channel(q,packet.text,p.name)
  elseif packet.route=='addon' and (packet.kind~='WHISPER'
   or packet.target==q.name or packet.target==q.e.UnitName('player')) then
   q.H.Fire('CHAT_MSG_ADDON',packet.prefix,packet.text,packet.kind,p.name)
  end
 end
end
check(receiver.e.Nexus.Sync.RequestSync()==true,'real manual RequestSync accepted')
for _=1,800 do
 source.H.Advance(.05,.05);receiver.H.Advance(.05,.05)
 pump(receiver,source);pump(source,receiver)
end
check(type(requestId)=='string' and requestId:match('^c1%-'),
 'actual request ID retained from captured production wire')
check(captured>0,'actual contextual DPS egress captured')
local sourceEvents=N.PeerDebug.Events()
local receiverEvents=receiver.e.Nexus.PeerDebug.Events()
local function found(events,kind,id,transfer,outcome)
 for _,event in ipairs(events) do local f=event.fields
  if event.kind==kind and f.requestId==id
   and (not transfer or f.transferId==transfer)
   and (not outcome or f.outcome==outcome) then return f end
 end
end
local function outcomeCounters(sync)
 local stats=sync.Stats()
 local projected={}
 -- Outcome/egress counters, not nondeterministic maintenance scan work.
 for _,key in ipairs({'dpsRequestsReceived','dpsRelayOffered','dpsDirectAccepted',
  'dpsDirectRejected','dpsRelayAccepted','dpsRelayRejected','admittedPackets',
  'admittedBytes','attempted','sent','received','storageRejected',
  'requestNew','requestUpdated','requestRejected','requestDuplicates'}) do
  projected[key]=stats[key]
 end
 return F.Serialize(projected)
end
local result={traffic=F.Serialize(traffic),rawTraffic=F.Serialize(rawTraffic),
 source=F.Serialize(source.e.NexusDB.authorityBundle.dpsCapture),
 receiver=F.Serialize(receiver.e.NexusDB.authorityBundle.dpsCapture),
 sourceStats=outcomeCounters(N.Sync),
 receiverStats=outcomeCounters(receiver.e.Nexus.Sync)}
if not enabled then
 check(#sourceEvents==0 and #receiverEvents==0,'disabled trace collects no events')
 check(#source.H.actions==0 and #receiver.H.actions==0,'disabled case has zero game actions')
 return result
end
check(found(sourceEvents,'request_scheduled',requestId)~=nil,'actual scheduled request exact ID observed')
check(found(receiverEvents,'send_attempted',requestId)~=nil,'request send exact ID observed')
local accepted=0
for transfer,context in pairs(transfers) do
 if context.requestId==requestId then
  local offered=found(sourceEvents,'dps_offer',requestId,transfer,'admitted')
  local sent=found(sourceEvents,'send_attempted',requestId,transfer)
  local assembled=found(receiverEvents,'dps_transfer_complete',requestId,transfer,'complete')
  local committed=found(receiverEvents,'dps_commit',requestId,transfer,'accepted')
  for _,fields in ipairs({assert(offered),assert(sent),assert(assembled),assert(committed)}) do
   check(fields.requester==context.requester and fields.bucket==context.bucket
    and fields.dataKind=='D','exact wire context propagated through real observation seam')
  end
  check(committed.relay==false,'accepted diagnostic retains direct/relay boolean')
  accepted=accepted+1
 end
end
check(accepted>0,'original manual request has actual accepted contextual transfer')
local received=receiver.e.Nexus.DpsCapture.GetCharacterBest('lk','Origin',row.o)
check(received and received.dps==row.d and received.ownerVerified==true,
 'real durable synthetic admission agrees with diagnostic commit')
check(F.Serialize(source.e.NexusDB.authorityBundle.dpsCapture)==saved,
 'diagnostic request left source scores and record metadata unchanged')
-- Explicit offline fault injection: change only the captured envelope bucket
-- to a different valid bucket. Existing request authorization must refuse;
-- diagnostics must keep the actual supplied envelope IDs, not a current ID.
advance(100)
receiver.e.Nexus.PeerDebug.Start()
local replayed
for _,capturedResponse in ipairs(responsePackets) do
 if capturedResponse.requestId==requestId then
  local corrupted=wire(capturedResponse.packet):gsub('|(%d+)$',function(bucket)
   return '|'..tostring(tonumber(bucket)%8+1)
  end)
  P.Channel(receiver,corrupted,source.name);replayed=true
 end
end
check(replayed,'captured response replay available')
local rejected=found(receiver.e.Nexus.PeerDebug.Events(),'dps_commit',requestId,nil,'rejected')
check(rejected and rejected.reason=='outside requested response'
 and transfers[rejected.transferId]~=nil,'request authorization refusal keeps exact captured ID and transfer')
check(#source.H.actions==0 and #receiver.H.actions==0,'zero harness gameplay actions')
print('PASS sync_dps_correlation_wire checks='..checks..'; contextual chunks='..captured)
return result
end
local off=run(false)
local on=run(true)
for _,field in ipairs({'traffic','source','receiver','sourceStats','receiverStats'}) do
 if off[field]~=on[field] then
  local at=1
  while at<=#off[field] and off[field]:sub(at,at)==on[field]:sub(at,at) do at=at+1 end
  print('OFFLINE MISMATCH '..field..' byte='..at..' off='..off[field]:sub(math.max(1,at-140),at+60)..' on='..on[field]:sub(math.max(1,at-140),at+60))
 end
 check(off[field]==on[field],'matched diagnostics off/on identical '..field)
end
print('PASS matched diagnostics on/off checks='..checks)
print('MATCHED WIRE: only unrelated WLCP opaque final token canonicalized; raw_equal='..tostring(off.rawTraffic==on.rawTraffic))
