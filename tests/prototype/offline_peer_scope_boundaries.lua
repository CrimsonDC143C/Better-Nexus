-- Actual Sync connectivity options; no joins/sends from passive scope checks.
local H=dofile('tests/prototype/harness.lua')
ERR_CHAT_PLAYER_NOT_FOUND_S="No player named '%s' is currently playing."
local T;local received=0;local load=loadfile
loadfile=function(path)
 local chunk,why=load(path)
 if chunk and path=='core/SyncTransport.lua' then return function(...)
  chunk(...);local factory=Nexus.SyncInternals.Transport;local new=factory.New
  factory.New=function(options)T=new(options);return T end
 end end
 if chunk and path=='core/SyncWire.lua' then return function(...)
  chunk(...);local init=Nexus.SyncWire.Init
  Nexus.SyncWire.Init=function(fn,options)
   return init(function(...)received=received+1;return fn(...)end,options)
  end
 end end
 return chunk,why
end
H.Boot();loadfile=load
local W,C,S=Nexus.SyncWire,Nexus.ChatThrottleLib,Nexus.Sync
local checks=0;local function check(v,m)assert(v,m);checks=checks+1 end
local channels=GetChannelList
local function refill()C.bQueueing=false;C.avail=4000;C.LastAvailUpdate=H.now end
local function restore()GetChannelList=channels;H.now=H.now+1.1;refill()end
local function negotiate(peer)
 restore();W.ObservePeer(peer);W.PumpHandshake()
 check(H.sent[#H.sent].target==peer and H.sent[#H.sent].text=='HELLO1','actual current HELLO')
 check(W.Receive(W.PREFIX,'ACK1','WHISPER',peer),'actual current ACK')
end
T.Reset();W.ObservePeer('DispatchPeer')
check(S.HandleIncoming('WLRQ|DispatchPeer|0|0|c1-7001-1001','DispatchPeer'),'actual response producer')
check(T.EnqueueBatch({'WLS|Tester|one','WLS|Tester|two'},{requester='DispatchPeer',requestId='c1-7001-1001'}),'actual directed consumer backlog')
W.Housekeep(true);local before=#H.sent;GetChannelList=function()return end;H.now=H.now+.1;refill();W.PumpHandshake()
check(#H.sent==before,'sub-second disconnect prevents queued HELLO dispatch')
check(S.WorkState().pendingResponses==0 and T.Snapshot().outbound==0 and W.Stats().pendingHandshakes==0,'sub-second disconnect cancels actual owners before dispatch')

restore();W.ObservePeer('AckPeer');W.PumpHandshake();W.Housekeep(true)
GetChannelList=function()return end;H.now=H.now+.1
check(not W.Receive(W.PREFIX,'ACK1','WHISPER','AckPeer'),'sub-second disconnect refuses stale ACK generation')
check(not W.Receive(W.PREFIX,'HELLO1','WHISPER','NewPeer'),'disconnected incoming HELLO cannot renew negotiation')
check(W.Stats().pendingHandshakes==0,'incoming HELLO admitted no disconnected reply')

negotiate('PayloadPeer');W.Housekeep(true);GetChannelList=function()return end;H.now=H.now+.1
local receivedBefore=received
check(not W.Receive(W.PREFIX,'P7:WLNP||PayloadPeer||1.19.5','WHISPER','PayloadPeer'),'sub-second disconnect refuses old negotiated payload')
check(received==receivedBefore,'disconnected payload never reaches semantic owner')

negotiate('NoticePeer');refill();check(W.SendPacket('X',{requester='NoticePeer'},1),'actual current directed whisper')
W.Housekeep(true);local cancelled=W.Stats().offlineCancelled or 0
GetChannelList=function()return end;H.now=H.now+.1
check(not W.NoteOfflineNotice(string.format(ERR_CHAT_PLAYER_NOT_FOUND_S,'NoticePeer')),'offline attribution cannot renew stale connection scope')
check((W.Stats().offlineCancelled or 0)==cancelled,'connection cleanup does not invent offline attribution')

negotiate('PacketPeer');W.Housekeep(true);GetChannelList=function()return end;H.now=H.now+.1;refill();before=#H.sent
check(not W.SendPacket('X',{requester='PacketPeer'},1) and #H.sent==before,'direct packet submission also reads actual sub-second membership')

restore();local reads=0;GetChannelList=function()reads=reads+1;return channels()end
W.Housekeep(true);local swept=W.Stats().housekeepingSweeps;local readBefore=reads
for i=1,10000 do W.Housekeep();W.IsPeerBlocked('Idle');W.Blocked() end
check(W.Stats().housekeepingSweeps==swept and reads==readBefore,'ten thousand passive same-time checks perform no new native membership read or map sweep')
GetChannelList=channels
check(#H.actions==0,'no gameplay actions')
print('PASS offline_peer_scope_boundaries checks='..checks)
