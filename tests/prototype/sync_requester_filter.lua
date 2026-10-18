-- Requester correlation only extends diagnostic selection, never authority.
local H=dofile('tests/prototype/harness.lua');H.Boot()
local F=dofile('tests/prototype/format5_support.lua')
local D=Nexus.PeerDebug
local checks=0
local function check(ok,why) assert(ok,why);checks=checks+1 end
local saved=F.Serialize(NexusDB)
local sends=#H.sent
local realmCalls=0
GetRealmName=function() realmCalls=realmCalls+1;return 'Rogue-Lite (Live)' end
check(D.Start('Nexustest')==true,'short intended requester selected')
local pinnedCalls=realmCalls
local function record(peer,requester,id,kind)
 return D.Record(kind or 'response_claim',{peer=peer,requester=requester,
  requestId=id,outcome='retained',transferId='transfer:1',dataKind='D',bucket=1})
end
check(record('Alpha','Nexustest','c1-filter')==true,
 'third-party claim about intended requester retained')
local event=D.Events()[2].fields
check(event.peer=='Alpha' and event.requester=='Nexustest'
 and event.requestId=='c1-filter','actual responder and exact request tuple retained')
check(record('Alpha','Nexustest-rogue-lite(live)','c1-filter')==true,
 'exact pinned native qualified requester retained')
check(record(nil,'Nexustest','c1-filter','send_attempted')==true,
 'metadata-only intended request retained')
check(record(nil,'Unrelated','c1-filter','send_attempted')==false,
 'metadata-only unrelated valid request cannot bypass selection')
check(record('Alpha','Unrelated','c1-filter')==false,'unrelated requester refused')
check(record('Alpha','Nexustest-foreignrealm','c1-filter')==false,
 'same short name in foreign requester realm refused')
check(record('Alpha','Nexustester','c1-filter')==false,'prefix lookalike refused')
check(record(42,'Nexustest','c1-filter')==false,
 'malformed supplied peer cannot borrow requester exception')
for _,id in ipairs({'',string.rep('x',97),'bad|id','bad\nid','bad id','bad\255'}) do
 check(record('Alpha','Nexustest',id)==false,'malformed ID cannot grant requester exception')
end
for _,id in ipairs({false,42,{value='c1-filter'}}) do
 check(record('Alpha','Nexustest',id)==false,'non-string ID cannot grant exception')
end
for _,requester in ipairs({'bad|name','Nexustest\255',42,{name='Nexustest'}}) do
 check(record('Alpha',requester,'c1-filter')==false,'invalid requester cannot grant exception')
end
check(record('Alpha','Nexustest',nil)==false,'requester alone cannot grant exception')
check(record('Alpha',nil,'c1-filter')==false,'ID/transfer alone cannot grant exception')
check(record('Nexustest','Unrelated','c1-filter')==true,
 'existing matching peer still retained with different requester')
check(record('Nexustest','Nexustest',42)==true,
 'existing peer match survives malformed diagnostic correlation')
check(record('Alpha',nil,nil)==false,'old noncorrelated unrelated peer filter unchanged')
check(D.Record('global',{outcome='observed'})==true,'old peerless global events included')
check(D.Record('global',{requester='Nexustest',requestId=42})==true,
 'malformed peerless input remains global and grants no correlation route')
check(D.Events()[#D.Events()].fields.requestId==nil,'invalid global ID not retained as proof')
check(record('Alpha','Nexustest','c1-filter','owner_boundary')==false,
 'identifier-free owner boundary cannot use hidden requester exception')
check(D.Record('owner_boundary',{directOwner=true})==true,'global owner boundary privacy unchanged')
check(realmCalls==pinnedCalls,'request filtering never polls native realm')
GetRealmName=function() return 'AnotherRealm' end
check(record('Alpha','Nexustest-rogue-lite(live)','c1-filter')==true,
 'native requester identity remains pinned until explicit selection changes')
check(record('Alpha','Nexustest-anotherrealm','c1-filter')==false,
 'later realm cannot silently change request selection')
check(D.SetPeer('Nexustest')=='Nexustest','explicit SetPeer updates selection')
check(record('Alpha','Nexustest-anotherrealm','c1-filter')==true,
 'explicit selection pins fresh native requester identity')
check(D.Start('Nexustest-rogue-lite(live)')==true,'explicit qualified requester selected')
check(record('Alpha','NEXUSTEST-ROGUE-LITE(LIVE)','c1-filter')==true,
 'qualified identity uses existing exact case-insensitive player key')
check(record('Alpha','Nexustest','c1-filter')==false,'bare requester cannot borrow explicit realm')
check(record('Alpha','Nexustest-foreignrealm','c1-filter')==false,
 'explicit qualified target rejects foreign requester')
check(record('Nexustest-foreignrealm',nil,nil)==true,
 'legacy matching-peer short-name semantics preserved')
check(D.Start('Valentiné')==true,'true U+00E9 requester selected')
check(record('Alpha','Valentiné','c1-filter')==true,'true UTF-8 requester preserved')
check(record('Alpha','Valentine','c1-filter')==false,'different accent identity refused')
check(record('Alpha','Valentiné','legacy-Valentiné-123')==true,
 'exact generated legacy requester clock scope recognized')
check(record('Alpha','Valentiné','legacy-Valentiné-bad')==false,
 'malformed legacy clock cannot grant exception')
GetRealmName=function() error('synthetic realm failure') end
check(D.Start('Nexustest')==true,'failed native lookup preserves short selection')
check(record('Alpha','Nexustest','c1-filter')==true,'short exact requester still matches')
check(record('Alpha','Nexustest-anotherrealm','c1-filter')==false,
 'failed native lookup grants no stale qualified requester')
GetRealmName=nil
check(D.Start('Nexustest')==true,'missing realm preserves short selection')
check(record('Alpha','Nexustest-unknown','c1-filter')==false,'unknown realm cannot match')
check(D.Start()==true and record('Alpha','Unrelated','c1-filter')==true,
 'unfiltered session remains unfiltered')
check(F.Serialize(NexusDB)==saved,'diagnostic selection changes no saved bytes')
check(#H.sent==sends and #H.actions==0,'selection takes no sends or gameplay actions')
print('PASS sync_requester_filter checks='..checks)

-- Route every real reconciler decision from the existing production fixture
-- into the real filtered PeerDebug seam; no product callback is replaced.
local file=assert(io.open('tests/prototype/sync_claim_correlation.lua','rb'))
local fixture=file:read('*a');file:close()
local count
fixture,count=fixture:gsub('local observations={}',
 "local observations={}\nassert(N.PeerDebug.Start('Recipient'))")
check(count==1,'actual reconciler fixture start bound')
fixture,count=fixture:gsub('observations%[#observations%+1%]={kind=kind,fields=fields}',
 "observations[#observations+1]={kind=kind,fields=fields}\ncheck(N.PeerDebug.Record(kind,fields)==true,'actual filtered reconcile event retained')")
check(count==1,'actual reconciler observer bound')
-- sync_pair_support expects an unloaded outer addon namespace so each peer
-- gets its own namespace rather than inheriting this first harness's table.
local outerNexus=Nexus;Nexus=nil
assert(loadstring(fixture,'filtered-actual-reconciler'))()
Nexus=outerNexus
