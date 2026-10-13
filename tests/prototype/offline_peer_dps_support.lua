-- Actual Sync owners and synthetic native APIs. Observe the established
-- constructor/queue seam without adding production hooks or changing calls.
local F={}
function F.Boot(seedDps)
 Nexus=nil;NexusDB=nil;WishlistRealizerDB=nil
 local H=dofile('tests/prototype/harness.lua')
 local T,R
 local originalLoad=loadfile
 loadfile=function(path)
  local chunk,why=originalLoad(path)
  if chunk and (path=='core/SyncTransport.lua' or path=='core/SyncReconciler.lua') then
   return function(...)
    chunk(...)
    local factory=path=='core/SyncTransport.lua' and Nexus.SyncInternals.Transport or Nexus.SyncInternals.Reconciler
    local new=factory.New
    factory.New=function(options)
     local owner=new(options)
     if path=='core/SyncTransport.lua' then T=owner else R=owner end
     return owner
    end
   end
  end
  return chunk,why
 end
 H.Boot();loadfile=originalLoad
 local S,D,W,C=Nexus.Sync,Nexus.DpsCapture,Nexus.SyncWire,Nexus.ChatThrottleLib
 assert(T and R,'fixture: actual owners captured')
 ERR_CHAT_PLAYER_NOT_FOUND_S="No player named '%s' is currently playing."
 local record
 if seedDps then
  local echoes={{spellId=200001,count=3},{spellId=200002,count=1}}
  local payload={v=7,p='PrototypeTester',o='prototypetester@ebonhold',r='Ebonhold',
   k='MAGE',l=40,c='dummy',d=47000,u=180,t=time()-100,e=echoes,
   f=D.GetEchoKey(echoes),h=D.GetEchoHash(echoes)}
  assert(D.ReceiveRecord(payload,'PrototypeTester-Ebonhold'),'fixture: real verified local DPS admission')
  H.Advance(15,.05)
  local row=assert(D.GetCharacterBest('dummy','PrototypeTester',payload.o),'fixture: durable synthetic row')
  record=D.MaterializeRecord(row);record.category='dummy'
 end
 T.Reset();R.Reset()
 local f={H=H,S=S,D=D,W=W,T=T,R=R,record=record,batches={},attempts={}}
 local enqueue=T.EnqueueBatch
 T.EnqueueBatch=function(messages,metadata)
  local admitted,why=enqueue(messages,metadata)
  local copy={};for i,text in ipairs(messages)do copy[i]=text end
  f.batches[#f.batches+1]={messages=copy,requester=metadata.requester,
   requestId=metadata.requestId,buildId=metadata.buildId,admitted=admitted,why=why}
  return admitted,why
 end
 local send=W.SendPacket
 W.SendPacket=function(payload,metadata,channel)
  local ok,why=send(payload,metadata,channel)
  if ok then f.attempts[#f.attempts+1]={payload=payload,requester=metadata.requester,
   requestId=metadata.requestId,route=why} end
  return ok,why
 end
 function f.Refill()C.bQueueing=false;C.avail=4000;C.LastAvailUpdate=H.now end
 function f.Negotiate(peer)
  for _=1,16 do
   H.now=H.now+1.01;f.Refill();W.ObservePeer(peer);W.PumpHandshake()
   if W.Receive(W.PREFIX,'ACK1','WHISPER',peer) then return end
  end
  error('fixture: no current actual HELLO/ACK for '..peer)
 end
 function f.Block(peer)
  H.Fire('UI_ERROR_MESSAGE',string.format(ERR_CHAT_PLAYER_NOT_FOUND_S,peer))
  assert(W.IsPeerBlocked(peer),'fixture: actual offline event attributed')
 end
 function f.PlanUntil(predicate)
  for _=1,1200 do
   H.now=H.now+.05;R.Process(.05)
   if predicate() then return end
  end
  error('fixture: response planning did not reach observable output')
 end
 function f.Pump(seconds)
  seconds=seconds or 1.2;H.now=H.now+seconds;f.Refill();T.Pump(seconds)
 end
 function f.DpsBatches()
  local out={}
  for _,batch in ipairs(f.batches)do
   if batch.messages[1]:match('^WLD2|') then out[#out+1]=batch end
  end
  return out
 end
 return f
end
return F
