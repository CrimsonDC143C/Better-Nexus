-- Legacy request encoding must not erase local response/cancellation ownership.
-- Actual ingress, Reconciler, DPS, Transport and CTL; no game/network access.
local F=dofile('tests/prototype/offline_peer_dps_support.lua')
local checks,failed=0,{}
local function check(value,message)
 checks=checks+1;print((value and 'PASS ' or 'FAIL ')..message)
 if not value then failed[#failed+1]=message end
end
local function Fields(text)local n=1;for _ in text:gmatch('|')do n=n+1 end;return n end
local function DpsAttempts(f,start)
 local out={};for i=(start or 0)+1,#f.attempts do
  if f.attempts[i].payload:match('^WLD2|')then out[#out+1]=f.attempts[i]end
 end;return out
end

-- Both supported legacy request forms, plus a real c1 control. Inspect the
-- actual DPS response queue then cancel before its first data submission.
for _,case in ipairs({{name='old ID',suffix='|old-request',fields=5},
 {name='missing ID',suffix='',fields=5},{name='c1 control',suffix='|c1-7001-1001',fields=8},
 {name='missing ID UTF-8',peer=string.char(195,137)..'lodie',suffix='',fields=5},
 {name='missing ID realm apostrophe',peer="Legacy-Quel'Thalas",suffix='',fields=5},
 {name='missing ID realm parentheses',peer='Legacy-Rogue-Lite(Live)',suffix='',fields=5}})do
 local f=F.Boot(true)
 local peer=case.peer or 'Legacy'
 assert(f.S.HandleNativeChannelIncoming('WLRQ|'..peer..'|0|0'..case.suffix,peer),'fixture: accepted '..case.name)
 f.PlanUntil(function()return #f.DpsBatches()>0 end)
 local batch=f.DpsBatches()[1]
 check(batch.requester==peer and type(batch.requestId)=='string' and batch.requestId~='',case.name..': exact local DPS scope retained')
 check(Fields(batch.messages[1])==case.fields,case.name..': existing wire field count preserved')
 f.Negotiate(peer);f.Block(peer)
 check(f.T.Snapshot().bulk==0 and f.T.Snapshot().control==0,case.name..': all queued build, claim and DPS chunks canceled')
 check(f.R.Counts().total==0,case.name..': response producers terminated')
 local cursor=#f.attempts
 for _=1,12 do f.Pump()end
 check(#DpsAttempts(f,cursor)==0,case.name..': no post-offline channel or addon DPS emission')
 check(f.W.IsPeerBlocked(peer),case.name..': cooldown still held')
 check(#f.H.actions==0,case.name..': no gameplay action')
end

-- Latest-attempt cancellation must also defeat a later native throttle notice.
do
 local f=F.Boot(true);f.Negotiate('Legacy')
 local context={requester='Legacy',requestId='old-throttle',bucket=1}
 assert(f.S.BroadcastDpsRecord(f.record,nil,true,context),'fixture: initial legacy DPS response')
 f.Pump()
 assert(#DpsAttempts(f)==1,'fixture: actual first response chunk submitted')
 -- Keep current addon attribution separate from the Transport latest attempt.
 f.Refill();assert(f.W.SendPacket('WLNP|PrototypeTester|1.19.5',{requester='Legacy'},1),'fixture: recent actual addon whisper')
 f.Block('Legacy')
 check(f.T.Snapshot().bulk==0,'latest attempt: remaining legacy DPS canceled')
 check(not f.T.NoteTransportNotice('waiting to send'),'latest attempt: offline response cannot throttle-requeue')
 check(f.T.ThrottleRemaining()==0,'latest attempt: canceled scope cannot impose a throttle pause')
 local cursor=#f.attempts;f.Pump(10)
 check(#DpsAttempts(f,cursor)==0,'latest attempt: no delayed replay')
end

-- A wire-budget deferral returns an authentic private cache. Its eventual
-- admission must keep legacy scope, refuse offline peers, and bind all scope
-- fields without adding a c1 envelope to legacy bytes.
do
 local f=F.Boot(true);f.Negotiate('Legacy')
 local context={requester='Legacy',requestId='old-cache',bucket=1}
 local ok,why,prepared=f.S.BroadcastDpsRecord(f.record,nil,true,context,{chunks=0,bytes=0,seconds=0,transfers=0})
 assert(not ok and why=='response wire budget' and prepared,'fixture: authentic deferred cache')
 f.Block('Legacy')
 local admitted,refusal=f.S.BroadcastDpsRecord(f.record,prepared,true,context)
 check(admitted==false and refusal=='peer offline','cached response: blocked peer refused at retry admission')
 check(f.T.Snapshot().bulk==0,'cached response: offline retry adds no chunks')
 local cursor=#f.attempts;f.Pump()
 check(#DpsAttempts(f,cursor)==0,'cached response: no channel fallback after refusal')
 -- The existing recovery boundary needs a fresh accepted observation and ACK.
 f.H.now=f.H.now+60;f.W.Housekeep(true)
 check(f.W.IsPeerBlocked('Legacy'),'recovery: deadline alone cannot authorize replay')
 assert(f.S.HandleNativeChannelIncoming('WLNP|Legacy|1.19.5','Legacy'),'fixture: new accepted observation')
 f.Negotiate('Legacy')
 check(not f.W.IsPeerBlocked('Legacy'),'recovery: fresh negotiation opens current work')
 local fresh=f.S.BroadcastDpsRecord(f.record,nil,true,{requester='Legacy',requestId='new-cache',bucket=1})
 check(fresh==true,'recovery: fresh legacy DPS work admitted')
 f.Pump();check(#DpsAttempts(f,cursor)==1,'recovery: new response sends once')
end

-- A successful cached admission also needs ownership, so cancellation works
-- after admission and before submission rather than only refusing a retry.
for _,peer in ipairs({'Legacy',string.char(195,137)..'lodie'})do
 local f=F.Boot(true);f.Negotiate(peer)
 local requestId=peer=='Legacy' and 'old-admitted-cache' or 'legacy-'..peer..'-1000'
 local context={requester=peer,requestId=requestId,bucket=1}
 local ok,why,prepared=f.S.BroadcastDpsRecord(f.record,nil,true,context,{chunks=0,bytes=0,seconds=0,transfers=0})
 assert(not ok and why=='response wire budget' and prepared,'fixture: deferred online cache')
 check(f.S.BroadcastDpsRecord(f.record,prepared,true,context)==true,'cached online response: normal retry admitted')
 local batch=f.DpsBatches()[1]
 check(batch and batch.requester==peer and batch.requestId==context.requestId,'cached online response: exact queue scope retained')
 check(batch and Fields(batch.messages[1])==5,'cached online response: legacy wire field count preserved')
 f.Block(peer)
 check(f.T.Snapshot().bulk==0,'cached online response: all admitted chunks cancel')
 local cursor=#f.attempts;f.Pump()
 check(#DpsAttempts(f,cursor)==0,'cached online response: no post-cancellation emission')
end

for _,suffix in ipairs({'-not-a-clock','-1000\n','-100000000000000000000000000'})do
 local f=F.Boot(true);local peer=string.char(195,137)..'lodie'
 local accepted,why=f.S.BroadcastDpsRecord(f.record,nil,true,{requester=peer,requestId='legacy-'..peer..suffix,bucket=1})
 check(accepted==false and why=='outside_request','generated legacy scope: malformed clock rejected')
 check(f.T.Snapshot().bulk==0,'generated legacy scope: rejected clock adds no chunks')
end

-- An unrelated blocked peer must not suppress an intended local broadcast.
do
 local f=F.Boot(true);f.Negotiate('Legacy');f.Block('Legacy')
 check(f.S.BroadcastDpsRecord(f.record)==true,'community broadcast: admitted while unrelated peer offline')
 local batch=f.DpsBatches()[1]
 check(batch and batch.requester==nil and batch.requestId==nil,'community broadcast: remains intentionally unscoped')
 local cursor=#f.attempts
 for _=1,5 do f.Pump()end
 local sent=DpsAttempts(f,cursor)
 check(#sent==3,'community broadcast: all local DPS chunks progress')
 check(f.W.IsPeerBlocked('Legacy'),'community broadcast: does not recover offline peer')
end

for _,change in ipairs({'peer','request','bucket','broadcast','tampered cache'})do
 local f=F.Boot(true)
 local context={requester='Legacy',requestId='old-proof',bucket=1}
 local ok,why,prepared=f.S.BroadcastDpsRecord(f.record,nil,true,context,{chunks=0,bytes=0,seconds=0,transfers=0})
 assert(not ok and why=='response wire budget' and prepared,'fixture: authentic proof cache')
 local nextContext={requester='Legacy',requestId='old-proof',bucket=1}
 if change=='peer'then nextContext.requester='Online'
 elseif change=='request'then nextContext.requestId='other-request'
 elseif change=='bucket'then nextContext.bucket=2
 elseif change=='broadcast'then nextContext=nil
 else prepared.responseScope={requester='Online',requestId='old-proof',bucket=1}end
 local admitted,refusal=f.S.BroadcastDpsRecord(f.record,prepared,true,nextContext)
 check(admitted==false and refusal=='relay_authorization','prepared legacy identity: rejects '..change)
 check(f.T.Snapshot().bulk==0,'prepared legacy identity: '..change..' emits no chunks')
end

-- Same request ID belongs to distinct peers. Cancellation must preserve the
-- other peer's actual DPS response, not merely a manually enqueued packet.
do
 local f=F.Boot(true)
 for _,peer in ipairs({'Legacy','Online'})do
  assert(f.S.HandleNativeChannelIncoming('WLRQ|'..peer..'|0|0|same-legacy',peer),'fixture: actual request '..peer)
 end
 f.PlanUntil(function()return #f.DpsBatches()==2 end)
 f.Negotiate('Legacy');f.Negotiate('Online')
 local onlineBefore=f.T.RequestSnapshot('Online','same-legacy').packets
 f.Refill();assert(f.W.SendPacket('WLNP|PrototypeTester|1.19.5',{requester='Legacy'},1),'fixture: exact recent target')
 f.Block('Legacy')
 check(f.T.RequestSnapshot('Legacy','same-legacy').packets==0,'mixed peers: exact offline request removed')
 check(onlineBefore>0 and f.T.RequestSnapshot('Online','same-legacy').packets==onlineBefore,'mixed peers: same-ID online queue preserved')
 local cursor=#f.attempts
 for _=1,20 do f.Pump()end
 local sent=DpsAttempts(f,cursor);local online,unscoped=0,0
 for _,packet in ipairs(sent)do
  if packet.requester=='Online'then online=online+1 end
  if packet.requester~='Online'then unscoped=unscoped+1 end
 end
 check(online==3 and unscoped==0,'mixed peers: every online DPS chunk progresses; no offline/unscoped response')
end

-- A legacy exact-loadout response already retains local ownership. Keep that
-- control intact while the DPS owner is repaired.
do
 local f=F.Boot(true)
 assert(type(f.record.buildId)=='string','fixture: related local build')
 assert(f.S.HandleNativeChannelIncoming('WLLQ|Legacy|'..f.record.buildId,'Legacy'),'fixture: legacy loadout request')
 f.PlanUntil(function()
  for _,batch in ipairs(f.batches)do if batch.messages[1]:match('^WLRB|')then return true end end
 end)
 for _,batch in ipairs(f.batches)do
  if batch.messages[1]:match('^WLRB|')then check(batch.requester=='Legacy','legacy loadout: existing local scope retained')end
 end
 f.Negotiate('Legacy');f.Block('Legacy')
 check(f.T.Snapshot().outbound==0 and f.R.Counts().total==0,'legacy loadout: producer and chunks cancel')
end

assert(#failed==0,table.concat(failed,'; '))
print('PASS offline_peer_legacy_dps checks='..checks)
