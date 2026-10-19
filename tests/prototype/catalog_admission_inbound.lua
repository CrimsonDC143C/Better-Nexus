-- Actual legacy-summary decoder/caller integration; no network or game client.
local S=dofile('tests/prototype/catalog_admission_policy_support.lua')
local checks=0;local function check(v,m)assert(v,m);checks=checks+1 end
local H,C=S.Boot(1791)
local function Receive(id,name,forged)
 local sender=name..'-Ebonhold'
 local data={id=id,t='Synthetic '..id,a=sender,o=Nexus.Identity.OwnerKey(name,'Ebonhold'),
  c='MAGE',m=time(),h='a1',n=1}
 if forged then data.syncAdmissionOriginV1='forged@foreign' end
 local text='WLBI|'..sender..'|'..Nexus.Codec.Base64Encode(Nexus.Codec.JSONEncode(data))
 return Nexus.Sync.HandleIncoming(text,sender)
end
local untouched=S.Saved()
local forged=Receive('forged-wire-marker','ActualPeer',true)
check(not forged and C.Get('forged-wire-marker')==nil,'existing wire schema rejects foreign local metadata')
check(S.Saved()==untouched,'foreign wire metadata rejection changes no row')
Receive('allowed-last','ActualPeer')
S.T.Until(H,function()return C.Get('allowed-last')~=nil and C.ManualPreparationStatus().ready end)
check(S.Raw('allowed-last').syncAdmissionOriginV1=='actualpeer@ebonhold',
 'actual inbound caller retains transport origin from the validated sender')
check(C.Get('allowed-last').ownerVerified==true,'existing summary ownership checks still prove the actual owner')
local before=S.Saved()
Receive('refused-overflow','AnotherPeer')
H.Advance(5,.05)
S.T.Until(H,function()return C.ManualPreparationStatus().ready end)
check(C.Get('refused-overflow')==nil and C.Status().buildIdentityCount==1792,
 'actual inbound caller cannot consume local reserved headroom')
check(S.Saved()==before,'inbound refusal preserves all durable rows')
check(Nexus.StartupStatus().state=='ready','policy refusal does not make the catalog unreadable')
print('PASS catalog_admission_inbound checks='..checks)
