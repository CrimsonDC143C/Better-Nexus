-- Synthetic production peers reproduce a present current-native LK row missed
-- by the optional normalized realm lookup. No native/account/network evidence.
local P=dofile('tests/prototype/sync_pair_support.lua')
local checks,failures=0,{}
local function check(value,message)
 checks=checks+1;print((value and 'PASS ' or 'FAIL ')..message)
 if not value then failures[#failures+1]=message end
end
local function Settle(peer)for _=1,200 do peer.H.Advance(.05,.05)end end
local function Boot()
 P.Boot({'Origin','Recipient'},0,nil,{realm='Rogue-Lite (Live)',realmApis={
  {game='Rogue-Lite (Live)',normalized='RogueLite(Live)'},
  {game='Rogue-Lite (Live)'},
 }})
 return P.A.e.Nexus,P.A,P.B
end
local function Seed(N,peer,category,owner,score,transportOwner)
 local echoes={{spellId=200001,count=3},{spellId=200002,count=1}}
 local player=owner:match('^([^@]+)@')
 player=player=='origin' and 'Origin' or 'Other'
 local r={v=7,p=player,o=owner,k='MAGE',l=80,c=category,d=score or 47000,
  u=134.612,t=peer.e.time()-100,e=echoes,f=N.DpsCapture.GetEchoKey(echoes),
  h=N.DpsCapture.GetEchoHash(echoes),lk={{spellId=200085,count=1}}}
 check(N.DpsCapture.ReceiveRecord(r,player..'-'..(transportOwner or owner):match('@(.+)$'))==true,
  'fixture genuine shaped verified '..category..' row admitted')
 Settle(peer)
 return r,N.DpsCapture.GetCharacterBest(category,player,owner)
end
local function Saved(peer)
 local F=peer.e.dofile('tests/prototype/format5_support.lua')
 return F.Serialize(peer.e.NexusDB)
end
do
 local N,source,recipient=Boot()
 local r,row=Seed(N,source,'lk','origin@rogue-lite(live)',47000)
 check(row and row.ownerVerified==true and row.buildId~=nil,'native row has verified owner and real generated build')
 local before=Saved(source)
 local default=N.DpsCapture.GetCharacterBest('lk')
 check(default and default.ownerKey==r.o and default.dps==r.d,
  'default current-character lookup finds present exact native LK row')
 check(default and default.duration==r.u and default.ts==r.t
  and default.fingerprint==r.f,'native fallback preserves exact score/time/loadout')
 check(Saved(source)==before,'fallback read preserves every saved byte without rekeying')
 check(N.Identity.CanonicalOwnerKey(r.o)~='origin@roguelite(live)',
  'global canonical identities remain distinct')
 check(N.DpsCapture.GetCharacterBest('lk','Origin',r.o).ownerKey==r.o,
  'explicit native-owner lookup retains exact contract')
 local start=#source.H.sent
 local admitted=row and N.DpsCapture.BroadcastBestForBuild(row.buildId)
 check(admitted==true,'public build-best path exports current native owner with category')
 Settle(source)
 local chunks,total={},nil
 for i=start+1,#source.H.sent do
  local packet=source.H.sent[i]
  local text=packet.text:gsub('||','|')
  local index,count,data=text:match('^WLD2|[^|]+|[^|]+|(%d+)/(%d+)|([^|]+)$')
  if data then
   check(packet.route=='chat' and packet.kind=='CHANNEL','export uses the existing native channel')
   chunks[tonumber(index)]=data;total=tonumber(count)
   P.Channel(recipient,packet.text,'Origin')
  end
 end
 check(total and #chunks==total,'all production DPS chunks captured and delivered')
 if total and #chunks==total then
  local payload=N.Codec.JSONDecode(N.Codec.Base64Decode(table.concat(chunks)))
  check(payload.c=='lk' and payload.o==r.o and payload.d==r.d
   and payload.t==r.t and payload.f==r.f,'wire keeps category and exact original owner/evidence')
 end
 Settle(recipient)
 local received=recipient.e.Nexus.DpsCapture.GetCharacterBest('lk','Origin',r.o)
 check(received and received.ownerVerified==true and received.dps==r.d
  and received.fingerprint==r.f,'real recipient ingress retains authenticated native row')
 check(recipient.e.Nexus.DpsCapture.GetCharacterBest('lk')==nil,
  'recipient does not acquire sender local ownership from presence')
 local F=source.e.dofile('tests/prototype/format5_support.lua')
 source.e.NexusDB=assert(loadstring('return '..F.Serialize(source.e.NexusDB)))()
 source=P.Rejoin(1);N=source.e.Nexus;Settle(source)
 local reloaded=N.DpsCapture.GetCharacterBest('lk')
 check(reloaded and reloaded.ownerKey==r.o and reloaded.dps==r.d
  and reloaded.ts==r.t,'fresh-runtime serialized reload preserves lookup and original owner')
 check(#source.H.actions==0 and #recipient.H.actions==0,'offline case takes no gameplay action')
end
do
 local N,source=Boot()
 Seed(N,source,'lk','origin@roguelite(live)',47000,'origin@rogue-lite(live)')
 local row=N.DpsCapture.GetCharacterBest('lk','Origin')
 local bucket=source.e.NexusDB.authorityBundle.dpsCapture.characterBest.lk
 check(bucket['origin@rogue-lite(live)'] and row and row.ownerKey==nil
  and row.ownerVerified==false,
  'unknown-route mismatch remains an unverified native slot')
 local before=Saved(source)
 check(N.DpsCapture.GetCharacterBest('lk')==nil,
  'unverified native slot cannot fill missing current-owner lookup')
 check(row and not N.DpsCapture.BroadcastBestForBuild(row.buildId),
  'unverified native slot cannot acquire direct egress')
 check(Saved(source)==before,'unverified refusal never promotes or rewrites the row')
end
do
 local N,source=Boot()
 local _,native=Seed(N,source,'dummy','origin@rogue-lite(live)',47000)
 local _,normalized=Seed(N,source,'dummy','origin@roguelite(live)',48000)
 local before=Saved(source)
 local selected=N.DpsCapture.GetCharacterBest('dummy')
 check(selected and selected.ownerKey==normalized.ownerKey and selected.dps==48000,
  'existing normalized primary selection retains precedence')
 check(native and N.DpsCapture.GetCharacterBest('dummy','Origin',native.ownerKey).dps==47000,
  'both globally distinct verified rows remain explicitly readable')
 check(Saved(source)==before,'primary and native rows are not merged or rewritten')
end
for _,mode in ipairs({'missing-native','invalid-native','changed-native','foreign-player'})do
 local N,source=Boot()
 local owner=mode=='foreign-player' and 'other@rogue-lite(live)' or 'origin@rogue-lite(live)'
 local _,row=Seed(N,source,'lk',owner,47000)
 if mode=='missing-native' then source.e.GetRealmName=nil end
 if mode=='invalid-native' then source.e.GetRealmName=function()return 'bad@realm'end end
 if mode=='changed-native' then source.e.GetRealmName=function()return 'AnotherRealm'end end
 local before=Saved(source)
 check(N.DpsCapture.GetCharacterBest('lk')==nil,mode..' cannot borrow native lookup')
 check(not N.DpsCapture.BroadcastBestForBuild(row.buildId),mode..' cannot borrow direct egress')
 check(Saved(source)==before,mode..' refusal preserves saved records')
end
do
 local N,source=Boot()
 local _,row=Seed(N,source,'lk','origin@rogue-lite(live)',47000)
 local outgoing=N.DpsCapture.MaterializeRecord(row);outgoing.category='lk'
 local admitted,why,prepared=N.Sync.BroadcastDpsRecord(outgoing,nil,false,nil,
  {maxChunks=0,maxBytes=0,maxTransfers=0})
 check(admitted==false and type(prepared)=='table','bounded budget retains a real prepared native payload')
 source.e.GetRealmName=function()return 'AnotherRealm'end
 local before=Saved(source)
 check(prepared and N.Sync.BroadcastDpsRecord(outgoing,prepared)==false,
  'prepared egress freshly refuses changed native authority')
 check(Saved(source)==before,'fresh prepared refusal preserves saved records')
end
print(string.format('CHECKS %d FAILURES %d',checks,#failures))
assert(#failures==0,table.concat(failures,'; '))
