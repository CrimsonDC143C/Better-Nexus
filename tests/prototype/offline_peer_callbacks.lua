-- Actual private Transport/CTL with malformed callback orders; synthetic APIs.
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
local W,C=Nexus.SyncWire,Nexus.ChatThrottleLib
local checks=0;local function check(v,m)assert(v,m);checks=checks+1 end
local send=C.SendAddonMessage
local function refill()C.bQueueing=false;C.avail=4000;C.LastAvailUpdate=H.now end
local function reset()C.SendAddonMessage=send;T.Reset();W.Init(function()return true end);H.now=H.now+1.1;refill()end
local function negotiate(peer)
 W.ObservePeer(peer);W.PumpHandshake()
 check(H.sent[#H.sent].target==peer and H.sent[#H.sent].text=='HELLO1','actual current HELLO')
 check(W.Receive(W.PREFIX,'ACK1','WHISPER',peer),'current ACK')
 H.now=H.now+5;refill()
end
for _,kind in ipairs({'packet','handshake'}) do
 reset();local peer='Deferred'..kind;local callback,arg
 if kind=='packet' then negotiate(peer) else W.ObservePeer(peer) end
 C.SendAddonMessage=function(_,_,_,_,_,_,_,fn,value)callback,arg=fn,value end
 local before=#H.sent
 if kind=='packet' then
  check(T.EnqueueControl('WLS|Tester|late',{requester=peer,queueClass='control'}),'actual packet admitted')
  T.Pump(1.1);check(T.Snapshot().outbound==0,'unresolved packet consumed')
 else W.PumpHandshake();check(W.Stats().pendingHandshakes==0,'unresolved handshake consumed') end
 check(callback and W.suspended,'unresolved callback quarantines backend')
 callback(arg,true);callback(arg,false)
 check(not W.NoteOfflineNotice(string.format(ERR_CHAT_PLAYER_NOT_FOUND_S,peer)),'late '..kind..' callback cannot grant attribution')
 check(not W.Receive(W.PREFIX,'ACK1','WHISPER',peer),'late '..kind..' callback cannot grant ACK window')
 H.now=H.now+10;refill();T.Pump(10);W.PumpHandshake()
 check(#H.sent==before,'deferred backend cannot submit replay')
end
for _,kind in ipairs({'packet','handshake'}) do
 for _,order in ipairs({{true,false},{false,true}}) do
  reset();local peer='Duplicate'..kind
  if kind=='packet' then negotiate(peer) else W.ObservePeer(peer) end
  C.SendAddonMessage=function(self,priority,prefix,text,distribution,target,queue,fn,arg)
   return send(self,priority,prefix,text,distribution,target,queue,function(value)
    fn(value,order[1]);fn(value,order[2])
   end,arg)
  end
  local before=#H.sent
  if kind=='packet' then
   check(T.EnqueueControl('WLS|Tester|duplicate',{requester=peer,queueClass='control'}),'actual duplicate control admitted')
   T.Pump(1.1);check(T.Snapshot().outbound==0,'any immediate success consumes selected packet')
  else
   W.PumpHandshake();check(W.Receive(W.PREFIX,'ACK1','WHISPER',peer),'any immediate HELLO success retains current ACK witness')
  end
  check(#H.sent==before+1 and W.suspended,'one actual '..kind..' submission; duplicate callback quarantined')
  T.NoteTransportNotice('waiting to send');H.now=H.now+10;refill();T.Pump(10);W.PumpHandshake()
  check(#H.sent==before+1,'both duplicate orders prevent actual API replay')
 end
end
for _,kind in ipairs({'packet','handshake'}) do
 reset();local peer='Exception'..kind
 if kind=='packet' then negotiate(peer) else W.ObservePeer(peer) end
 C.SendAddonMessage=function(self,priority,prefix,text,distribution,target,queue,fn,arg)
  send(self,priority,prefix,text,distribution,target,queue,fn,arg);error('after successful immediate callback')
 end
 local before=#H.sent
 if kind=='packet' then
  check(T.EnqueueControl('WLS|Tester|exception',{requester=peer,queueClass='control'}),'actual exception control admitted')
  T.Pump(1.1);check(T.Snapshot().outbound==0,'post-success exception consumes actual packet')
 else W.PumpHandshake();check(W.Receive(W.PREFIX,'ACK1','WHISPER',peer),'post-success handshake exception retains witness') end
 check(W.suspended and #H.sent==before+1,'post-success exception quarantined after one API submission')
 H.now=H.now+10;refill();T.Pump(10);W.PumpHandshake();check(#H.sent==before+1,'post-success exception cannot replay')
end
reset();negotiate('FalseOnly');local callbacks=0;local before=#H.sent
C.SendAddonMessage=function(_,_,_,_,_,_,_,fn,arg)callbacks=callbacks+1;fn(arg,false)end
check(T.EnqueueControl('WLS|Tester|false',{requester='FalseOnly',queueClass='control'}),'false-only control admitted')
for i=1,3 do T.Pump(2.1);H.now=H.now+2.1;refill() end
check(callbacks==3 and T.Snapshot().outbound==0,'false-only refusal retains existing bounded attempts')
check(#H.sent==before and not W.suspended,'false-only path submitted no native bytes and did not quarantine valid refusal')
check(not W.NoteOfflineNotice(string.format(ERR_CHAT_PLAYER_NOT_FOUND_S,'FalseOnly')),'false-only callbacks create no new attribution')
reset();W.ObservePeer('FalseHandshake');C.SendAddonMessage=function(_,_,_,_,_,_,_,fn,arg)fn(arg,false)end
W.PumpHandshake();check(not W.Receive(W.PREFIX,'ACK1','WHISPER','FalseHandshake'),'false-only handshake creates no ACK authority')
C.SendAddonMessage=send
check(#H.actions==0,'no gameplay actions')
print('PASS offline_peer_callbacks checks='..checks)
