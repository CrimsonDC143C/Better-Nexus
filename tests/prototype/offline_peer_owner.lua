-- Tests-only diagnostic outside production. Actual Sync owners and callbacks;
-- synthetic APIs, no future APIs. Capture existing constructor without changing it.
local H=dofile('tests/prototype/harness.lua')
local filters={}
ChatFrame_AddMessageEventFilter=function(event,fn)
  filters[event]=filters[event] or {};filters[event][#filters[event]+1]=fn
end
ERR_CHAT_PLAYER_NOT_FOUND_S="No player named '%s' is currently playing."
local transport,construction,reconciler
local realLoadfile=loadfile
loadfile=function(path)
  local chunk,why=realLoadfile(path)
  if chunk and (path=='core/SyncTransport.lua' or path=='core/SyncReconciler.lua') then
    return function(...)
      chunk(...)
      local factory=path=='core/SyncTransport.lua' and Nexus.SyncInternals.Transport or Nexus.SyncInternals.Reconciler
      local realNew=factory.New
      factory.New=function(options)
        local instance=realNew(options)
        if path=='core/SyncTransport.lua' then transport,construction=instance,options else reconciler=instance end
        return instance
      end
    end
  end
  return chunk,why
end
H.Boot();loadfile=realLoadfile
local S,W,C=Nexus.Sync,Nexus.SyncWire,Nexus.ChatThrottleLib
assert(transport and construction.listenEvent and construction.sendPacket,
  'fixture: actual Sync constructor and callbacks retained')
transport.Reset()
local function refill() C.bQueueing=false;C.avail=4000;C.LastAvailUpdate=H.now end
local hellos={}
local function negotiate(peer)
  local start=#H.sent
  H.Fire('CHAT_MSG_CHANNEL','WLNP|'..peer..'|1.19.5',peer,'',
    '1. wrbuildssync','','',0,1,'wrbuildssync')
  refill();W.PumpHandshake()
  local hello
  for i=start+1,#H.sent do
    local p=H.sent[i]
    if p.route=='addon' and p.kind=='WHISPER' and p.target==peer and p.text=='HELLO1' then hello=p end
  end
  assert(hello,'fixture: actual current HELLO1 submitted for '..peer)
  hellos[#hellos+1]={peer=peer,at=H.now}
  H.Fire('CHAT_MSG_ADDON',W.PREFIX,'ACK1','WHISPER',peer)
  H.now=H.now+1.01;refill()
end
negotiate('Tryveer');negotiate('Online')
local requestId='c1-7001-1001'
assert(S.HandleIncoming('WLRQ|Tryveer|0|0|'..requestId,'Tryveer'),'fixture: actual Tryveer request accepted')
assert(S.HandleIncoming('WLRQ|Online|0|0|'..requestId,'Online'),'fixture: actual Online request accepted')
assert(S.WorkState().pendingResponses==2,'fixture: same request ID owns two distinct producers')
assert(reconciler.ScheduleLoadout({requester='Tryveer',buildId='offline-test-build',requestId=requestId}),'offline loadout producer admitted')
assert(reconciler.ScheduleLoadout({requester='Online',buildId='offline-test-build',requestId=requestId}),'online loadout producer admitted')
assert(S.WorkState().pendingLoadouts==2,'two exact loadout producers')
local function enqueue(peer)
  local messages={};for i=1,4 do messages[i]='WLS|Tester|synthetic-directed-'..i end
  assert(transport.EnqueueBatch(messages,{requester=peer,requestId=requestId,
    transferId='transfer-'..peer,expiresAt=H.now+120})==true,'fixture: four chunks admitted for '..peer)
end
enqueue('Tryveer');enqueue('Online')
assert(transport.EnqueueControl('WLS|Tester|offline-control',{requester='Tryveer',requestId=requestId,queueClass='control'}),'offline control consumer admitted')
assert(transport.EnqueueControl('WLS|Tester|online-control',{requester='Online',requestId=requestId,queueClass='control'}),'online control consumer admitted')
-- Passive spy on the actual SendPacket method; arguments and returns preserved.
local attempts={}
local realSend=W.SendPacket
W.SendPacket=function(payload,metadata,channel)
  local ok,route=realSend(payload,metadata,channel)
  if ok then attempts[#attempts+1]={at=H.now,route=route,requester=metadata.requester,
    requestId=metadata.requestId,payload=payload} end
  return ok,route
end
H.now=H.now+1.2;refill();transport.Pump(1.2)
assert(#attempts==1 and attempts[1].requester=='Tryveer' and attempts[1].route=='addon',
  'fixture: first chunk was an actual immediate negotiated addon whisper')
local beforeNotice=S.WorkState()
local text=string.format(ERR_CHAT_PLAYER_NOT_FOUND_S,'Tryveer')
H.Fire('UI_ERROR_MESSAGE',text)
local visible=true
for _,fn in ipairs(filters.CHAT_MSG_SYSTEM or {}) do
  if fn(nil,'CHAT_MSG_SYSTEM',text)==true then visible=false end
end
local afterNotice=S.WorkState()
assert(transport.RequestSnapshot('Tryveer',requestId).packets==0,'exact offline queue removed immediately')
assert(transport.RequestSnapshot('Online',requestId).packets==5,'same-ID online queue unchanged')
assert(afterNotice.pendingLoadouts==1,'offline cancellation removes only exact loadout producer')
assert(not transport.NoteTransportNotice('waiting to send'),'cancelled latest attempt cannot replay on a throttle notice')
assert(transport.ThrottleRemaining()==0,'cancelled attempt cannot impose a new global throttle pause')
-- Below the 60-second cooldown: real lifecycle runs retained producers,
-- consumers and latest-attempt/throttle settlement after cancellation.
for _=1,900 do refill();H.Advance(.05,.05) end
local directed,online=0,0
for _,a in ipairs(attempts) do
  if a.requester=='Tryveer' then directed=directed+1 end
  if a.requester=='Online' then online=online+1 end
end
assert(transport.RequestSnapshot('Tryveer',requestId).packets==0,
  'cancelled peer has no retained request packets after later lifecycle turns')
assert(transport.Enqueue('WLS|Tester|late',{requester='Tryveer',requestId=requestId})==false,
  'cooldown rejects consumer recreation')
assert(S.HandleIncoming('WLRQ|Tryveer|0|0|'..requestId,'Tryveer'),
  'delayed duplicate request remains semantically handled')
assert(S.WorkState().pendingResponses==0,'cooldown rejects producer recreation')
assert(online>=4,'control: unrelated Online with the same request ID continues')
assert(visible,'control: native offline message remains visible')
assert(#H.actions==0,'control: no gameplay mutation')
print('RESULT '..Nexus.Codec.JSONEncode({case='legitimate_directed_actual_sync',
  runtime={lua=_VERSION,jit=jit and jit.version},requestId=requestId,
  actualHellos=hellos,tryveerAttempts=directed,onlineAttempts=online,
  beforeNotice=beforeNotice,afterNotice=afterNotice,finalWork=S.WorkState(),
  wire=W.Stats(),offlineMessageVisible=visible,attempts=attempts,
  newCallbackApiFabricated=false,constructorOptionsPreserved=true,
  productionHooks='actual Sync UI_ERROR_MESSAGE and CHAT_MSG_SYSTEM callbacks'}))
if ORACLE~=false then
  assert(directed==1,'REGRESSION: legitimate peer retains directed backlog or response producer after attributable offline notice')
  assert(afterNotice.pendingResponses==1,
    'REGRESSION: offline cancellation did not terminate only the exact Tryveer producer')
end

print('PASS offline_peer_owner: legitimate negotiation, actual owners/events, exact requester isolation and later-turn prevention')
