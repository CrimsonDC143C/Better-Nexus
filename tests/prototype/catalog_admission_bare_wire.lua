-- Real HELLO/ACK negotiation and bare CHAT_MSG_ADDON full-build delivery.
local P=dofile('tests/prototype/sync_pair_support.lua')
local checks=0;local function check(v,m)assert(v,m);checks=checks+1 end
P.Boot({'Receiver','Unused'},0,nil,{realm='Rogue-Lite (Live)'})
local p=P.A;local N,H=p.e.Nexus,p.H
P.NegotiateAddon(p,'Origin')
local payload={id='bare-legacy-full',t='Synthetic bare full',a='Origin',c='MAGE',m=1700000300,e={{200001,1,1}}}
local encoded=N.Codec.Base64Encode(N.Codec.JSONEncode(payload));local total=math.ceil(#encoded/90)
for i=1,total do
 local wire=string.format('WLRB|Origin|%s|%d|%d/%d|%s',payload.id,payload.m,i,total,encoded:sub((i-1)*90+1,i*90))
 H.Fire('CHAT_MSG_ADDON',N.SyncWire.PREFIX,'P7:'..wire,'WHISPER','Origin')
end
for i=1,400 do H.Advance(.05,.05) end
local row=N.BuildCatalog.Get(payload.id)
check(row~=nil,'previously supported actual bare ADDON route retains full-build availability')
check(row.ownerVerified~=true and row.ownerKey==nil,'bare ADDON route retains unverified content semantics')
check(p.e.NexusDB.authorityBundle.communityBuilds[payload.id].syncAdmissionOriginV1=='transport-bare:origin',
 'actual sender has quota bookkeeping without native realm context')
check(row.fingerprint=='200001x1','unchanged ordinary content determines fingerprint')
print('PASS catalog_admission_bare_wire checks='..checks..' chunks='..total)
