-- Desired policy: cancelled complete candidates consume no durable origin quota.
local S=dofile('tests/prototype/catalog_admission_policy_support.lua')
local F,T=S.F,S.T
local checks=0;local function check(v,m)assert(v,m);checks=checks+1 end
for _,case in ipairs({{sender='Relay-Ebonhold',origin='relay@ebonhold'},
 {sender='Relay',origin='transport-bare:relay'}}) do
local H,C=S.Boot(255,function(db)
 for _,r in pairs(db.communityBuilds) do r.syncAdmissionOriginV1=case.origin end
end)
local restore=T.SingleSlicePacing()
local saved=S.Saved()
local ok,why,tickets=C.PutBatch({
 {record=S.Record('cancelled-final-slot'),options={source='remote',sender=case.sender}},
 {record=S.Record('cancelled-over-limit'),options={source='remote',sender=case.sender}},
})
check(ok==nil and type(tickets)=='table','candidate starts with bounded frozen members')
T.Until(H,function()return C.ManualPreparationStatus().phase=='collect' end)
check(C.RootState().candidate~=nil,'candidate reached construction after preparing complete member reservations')
C.CancelRootAdmission()
check(S.Saved()==saved,'cancellation leaves every original stored row and witness exact')
check(tickets[1].committed==false and tickets[2].committed==false,'no cancelled member commits')
restore()
H=F.Reload();S.H=H;S.C=Nexus.BuildCatalog;C=S.C
T.Until(H,function()return C.ManualPreparationStatus().ready end)
check(C.Status().buildIdentityCount==255,'reload retains only original identities')
check(S.Remote(S.Record('retry-after-cancel'),case.sender),
 'cancelled admission did not consume the remaining origin slot')
local refused,reason=S.Remote(S.Record('after-real-commit'),case.sender)
check(refused==false and reason=='REMOTE_ORIGIN_LIMIT','only the later actual commit consumes the final slot')
check(C.Get('cancelled-final-slot')==nil and C.Get('cancelled-over-limit')==nil,
 'cancellation never replayed the old records')
end
print('PASS catalog_admission_rollback checks='..checks)
