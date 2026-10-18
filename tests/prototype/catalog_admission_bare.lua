-- Bare transport keys are availability-preserving quota labels, never realm proof.
local S=dofile('tests/prototype/catalog_admission_policy_support.lua')
local F=S.F
local checks=0;local function check(v,m)assert(v,m);checks=checks+1 end
local H,C=S.Boot(255,function(db)
 for _,r in pairs(db.communityBuilds) do r.syncAdmissionOriginV1='transport-bare:origin' end
end)
local tickets=S.Batch({
 {record=S.Record('bare-last',{syncAdmissionOriginV1='transport-bare:other'}),options={source='remote',sender='Origin'}},
 {record=S.Record('bare-over'),options={source='remote',sender='ORIGIN'}},
 {record=S.Record('qualified-distinct'),options={source='remote',sender='Origin-Ebonhold'}},
})
check(tickets[1].committed==true,'256th bare transport identity fits')
check(S.Raw('bare-last').syncAdmissionOriginV1=='transport-bare:origin','forged marker cannot move actual bare quota')
check(tickets[2].committed==false and tickets[2].reason=='REMOTE_ORIGIN_LIMIT',
 'batch reservations and ASCII normalization cap bare transport')
check(tickets[3].committed==true and S.Raw('qualified-distinct').syncAdmissionOriginV1=='origin@ebonhold',
 'qualified and bare namespaces are explicitly disjoint, not assumed same person')
check(C.Get('bare-last').ownerVerified==false,'bare bookkeeping cannot prove content owner')
H=F.Reload();S.H=H;S.C=Nexus.BuildCatalog;C=S.C
local ok,why=S.Remote(S.Record('bare-after-reload'),'Origin')
check(ok==false and why=='REMOTE_ORIGIN_LIMIT','bare origin count survives literal reload')
ok,why=S.Put(S.Record('missing-actual-sender'),{source='remote'})
check(ok==false and why=='REMOTE_ORIGIN_UNAVAILABLE','missing actual sender still refuses new remote growth')
H,C=S.Boot(1791)
check(S.Remote(S.Record('bare-headroom-last'),'Origin'),'bare admission can fill the 1792nd total slot')
ok,why=S.Remote(S.Record('bare-headroom-overflow'),'Another')
check(ok==false and why=='REMOTE_HEADROOM_LIMIT','global local headroom applies across bare identities')
print('PASS catalog_admission_bare checks='..checks)
