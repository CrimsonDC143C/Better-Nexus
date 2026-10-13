-- Synthetic native APIs, actual wire/CTL; no external or game actions.
local H=dofile('tests/prototype/harness.lua');H.Boot()
local W,C=Nexus.SyncWire,Nexus.ChatThrottleLib
local checks=0;local function check(v,m)assert(v,m);checks=checks+1 end
local removed,online={},true
local function refill() C.bQueueing=false;C.avail=4000;C.LastAvailUpdate=H.now end
local function init()
 W.Init(function() return true end,{connected=function()return online end,
  onPeerRemoved=function(name,why)removed[#removed+1]={name,why}end})
 refill()
end
local function negotiate(name)
 H.now=H.now+1.1;refill();W.ObservePeer(name);local start=#H.sent;W.PumpHandshake()
 check(#H.sent==start+1 and H.sent[#H.sent].text=='HELLO1' and H.sent[#H.sent].target==name,'actual HELLO submitted '..name)
 check(W.Receive(W.PREFIX,'ACK1','WHISPER',name),'current ACK accepted '..name)
end
init();H.combat=true;W.ObservePeer('Stale');local start=#H.sent
H.now=H.now+7201;W.PumpHandshake();H.combat=false;refill();W.PumpHandshake()
check(#H.sent==start and W.Stats().pendingHandshakes==0,'stale HELLO expires behind combat gate')
check(not W.Receive(W.PREFIX,'ACK1','WHISPER','Stale'),'unsolicited stale ACK refused')
init();W.ObservePeer('Deadline');W.Housekeep();H.now=H.now+29.9;W.Housekeep()
H.now=H.now+.1;start=#H.sent;W.PumpHandshake();check(W.Stats().pendingHandshakes==0 and #H.sent==start,'exact pending deadline despite cached sweep')
init();W.ObservePeer('LateAck');W.PumpHandshake();H.now=H.now+30
check(not W.Receive(W.PREFIX,'ACK1','WHISPER','LateAck'),'sent HELLO reply window expires at deadline')
init();W.Receive(W.PREFIX,'HELLO1','WHISPER','AckQueued');H.combat=true;H.now=H.now+31;start=#H.sent
W.PumpHandshake();H.combat=false;refill();W.PumpHandshake();check(#H.sent==start,'stale queued ACK expires')
init();negotiate('Reconnect');online=false;H.now=H.now+1;W.Housekeep()
check(removed[#removed][1]=='Reconnect','disconnect cleans exact owner')
online=true;H.now=H.now+1;W.Housekeep()
check(not W.Receive(W.PREFIX,'ACK1','WHISPER','Reconnect'),'old ACK cannot cross connection generation')
negotiate('Reconnect');check(W.SendPacket('X',{requester='Reconnect'},1)==true,'fresh reconnect recovers')
init();negotiate('Mode');NexusDB.settingsVersion=5;NexusDB.settings.syncMode='off';H.now=H.now+1;W.Housekeep()
check(W.Stats().pendingHandshakes==0 and not W.Receive(W.PREFIX,'ACK1','WHISPER','Mode'),'mode change cleans negotiation')
NexusDB.settings.syncMode='automatic';H.now=H.now+1;W.Housekeep()
local _,route=W.SendPacket('X',{requester='Mode'},1);check(route=='legacy','mode return does not resurrect negotiation')
init();W.ObservePeer('QuickMode');W.PumpHandshake()
NexusDB.settings.syncMode='off';W.PumpHandshake();NexusDB.settings.syncMode='automatic'
check(not W.Receive(W.PREFIX,'ACK1','WHISPER','QuickMode'),'observed mode refusal clears outstanding ACK window even within one sweep interval')
init();local called=0;W.Housekeep();local sweeps=W.Stats().housekeepingSweeps
for i=1,10000 do W.Housekeep();called=called+1 end
check(W.Stats().housekeepingSweeps==sweeps,'ten thousand unchanged-time passive calls do not scan again')
init();local send=C.SendAddonMessage
C.SendAddonMessage=function(_,_,_,_,_,_,_,callback,arg)callback(arg,false)end
W.ObservePeer('Refused');W.PumpHandshake();check(not W.Receive(W.PREFIX,'ACK1','WHISPER','Refused'),'false immediate callback creates no ACK authority')
C.SendAddonMessage=function()end
H.now=H.now+1;W.ObservePeer('Unresolved');W.PumpHandshake()
check(W.suspended and not W.Receive(W.PREFIX,'ACK1','WHISPER','Unresolved'),'unresolved CTL cannot create negotiation')
C.SendAddonMessage=send;init();negotiate('PacketCtl')
local attempts=0;ERR_CHAT_PLAYER_NOT_FOUND_S="No player named '%s' is currently playing."
H.now=H.now+4.01;refill()
C.SendAddonMessage=function(_,_,_,_,_,_,_,callback,arg)attempts=attempts+1;callback(arg,false)end
check(W.SendPacket('X',{requester='PacketCtl'},1)==false,'false packet callback reports refusal')
check(not W.NoteOfflineNotice("No player named 'PacketCtl' is currently playing."),'refused packet creates no recent submission attribution')
C.SendAddonMessage=function()attempts=attempts+1 end
local admitted,status=W.SendPacket('X',{requester='PacketCtl'},1)
check(admitted and W.suspended and status=='submitted to CTL; dispatch unresolved','unresolved packet is consumed without replay')
check(not W.SendPacket('X',{requester='PacketCtl'},1) and attempts==2,'suspended unresolved packet cannot replay')
C.SendAddonMessage=send;init();negotiate('PostCallbackError')
local dispatched=0
C.SendAddonMessage=function(_,_,_,_,_,_,_,callback,arg)dispatched=dispatched+1;callback(arg,true);error('after dispatch')end
local accepted,detail=W.SendPacket('X',{requester='PostCallbackError'},1)
check(accepted and W.suspended,'successful immediate callback followed by CTL exception is consumed')
check(not W.SendPacket('X',{requester='PostCallbackError'},1) and dispatched==1,'post-dispatch exception cannot replay')
C.SendAddonMessage=send;init()
local before=#H.sent;W.ObservePeer('Reset');W.Init(function()return true end);refill();W.PumpHandshake()
check(#H.sent==before and W.Stats().pendingHandshakes==0,'explicit reset removes pending handshake')
check(#H.actions==0,'no gameplay actions')
print('PASS offline_peer_lifecycle checks='..checks)
