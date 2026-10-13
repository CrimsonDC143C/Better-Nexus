-- Real private Transport, Sync event wiring and immediate CTL callback ordering.
local H=dofile('tests/prototype/harness.lua')
ERR_CHAT_PLAYER_NOT_FOUND_S="No player named '%s' is currently playing."
local T;local load=loadfile
loadfile=function(path)
 local chunk,why=load(path)
 if chunk and path=='core/SyncTransport.lua' then return function(...)
  chunk(...);local factory=Nexus.SyncInternals.Transport;local new=factory.New
  factory.New=function(options)T=new(options);return T end
 end end
 return chunk,why
end
H.Boot();loadfile=load
local W,C,S=Nexus.SyncWire,Nexus.ChatThrottleLib,Nexus.Sync
local checks=0;local function check(v,m)assert(v,m);checks=checks+1 end
local function refill()C.bQueueing=false;C.avail=4000;C.LastAvailUpdate=H.now end
local function negotiate(peer)
 H.now=H.now+1.1;refill();W.ObservePeer(peer);W.PumpHandshake()
 check(H.sent[#H.sent].target==peer and H.sent[#H.sent].text=='HELLO1','actual HELLO '..peer)
 H.Fire('CHAT_MSG_ADDON',W.PREFIX,'ACK1','WHISPER',peer)
end
local function enqueue(peer,label)
 check(T.EnqueueControl('WLS|Tester|'..label,{requester=peer,requestId='same-id',queueClass='control'})==true,'actual mixed control admission '..peer)
end
T.Reset();negotiate('Offline');negotiate('Online');enqueue('Offline','first');enqueue('Online','second')
check(S.HandleIncoming('WLRQ|Offline|0|0|c1-7001-1001','Offline'),'actual producer admitted')
local send=C.SendAddonMessage;local fired=false
C.SendAddonMessage=function(self,priority,prefix,text,kind,target,queue,callback,arg)
 return send(self,priority,prefix,text,kind,target,queue,function(callbackArg,sent)
  callback(callbackArg,sent)
  if target=='Offline' and text:sub(1,3)=='P7:' then
   fired=true;H.Fire('UI_ERROR_MESSAGE',string.format(ERR_CHAT_PLAYER_NOT_FOUND_S,target))
  end
 end,arg)
end
H.now=H.now+5;refill();T.Pump(1.1);C.SendAddonMessage=send
check(fired,'native offline event fires inside actual immediate send callback')
check(T.RequestSnapshot('Offline','same-id').packets==0,'selected offline packet cancelled')
check(T.RequestSnapshot('Online','same-id').packets==1 and T.Snapshot().outbound==1,'unrelated Online survives callback compaction')
check(S.WorkState().pendingResponses==0,'actual producer cancelled synchronously')
check(not T.NoteTransportNotice('waiting to send') and T.ThrottleRemaining()==0,'cancelled selected packet cannot regain lastSent/retry eligibility')
H.now=H.now+1.1;refill();local start=#H.sent;T.Pump(1.1)
check(#H.sent==start+1 and H.sent[#H.sent].target=='Online' and T.Snapshot().outbound==0,'unrelated Online is sent exactly once after compaction')

-- The passive connectivity callback cancels queues before Pump selects them.
T.Reset();negotiate('Disconnect');enqueue('Disconnect','gone')
local channelList=GetChannelList;GetChannelList=function()return end
H.now=H.now+1.1;refill();start=#H.sent;local ok,why=pcall(T.Pump,1.1)
check(ok,'disconnect housekeeping cannot invalidate selected queue index: '..tostring(why))
check(T.Snapshot().outbound==0 and #H.sent==start,'disconnect cleans before selection and sends nothing')
GetChannelList=channelList;H.now=H.now+1.1;W.Housekeep()
check(not W.Receive(W.PREFIX,'ACK1','WHISPER','Disconnect'),'disconnected HELLO cannot regain negotiation')
check(#H.actions==0,'no gameplay actions')
print('PASS offline_peer_reentrancy checks='..checks)
