-- Desired policy Q=256/R=256 are explicit private guardrails, not measured limits.
local S=dofile('tests/prototype/catalog_admission_policy_support.lua')
local F=S.F
local checks=0;local function check(v,m)assert(v,m);checks=checks+1 end
local H,C=S.Boot(255,function(db)
 for _,r in pairs(db.communityBuilds) do r.syncAdmissionOriginV1='relay@ebonhold' end
end)
local function Request(id,sender,extra)
 return {record=S.Record(id,extra),options={source='remote',sender=sender or 'Relay-Ebonhold'}}
end
local tickets=S.Batch({Request('last-for-relay'),Request('one-too-many'),Request('other-origin','Other-Ebonhold')})
check(tickets[1].committed==true,'256th same-origin identity fits')
check(tickets[2].committed==false and tickets[2].reason=='REMOTE_ORIGIN_LIMIT',
 'later batch member observes earlier per-origin reservation')
check(tickets[3].committed==true,'another authenticated origin keeps its own allowance')
check(C.Status().buildIdentityCount==257,'only admitted members occupy identities')
check(S.Remote(S.Record('seed-1',{lastModified=3}),'Owner-Ebonhold'),'existing-ID update bypasses new-growth ceiling')
check(S.Raw('seed-1').syncAdmissionOriginV1=='relay@ebonhold','existing update cannot move quota attribution')
local saved=S.Saved();local ok,why=S.Remote(S.Record('author-spoof',{author='NewAuthor-Ebonhold',ownerKey='newauthor@ebonhold'}),'Relay-Ebonhold')
check(ok==false and why=='REMOTE_ORIGIN_LIMIT','author/claimed-owner change cannot obtain a fresh origin bucket')
check(S.Saved()==saved,'origin refusal changes no stored row')
ok,why=S.Remote(S.Record('case-only-bucket'),'RELAY-EbOnHoLd')
check(ok==false and why=='REMOTE_ORIGIN_LIMIT','ASCII sender case changes do not create another origin bucket')

H,C=S.Boot(1791)
tickets=S.Batch({Request('remote-last','First-Ebonhold'),Request('remote-overflow','Second-Ebonhold'),
 {record=S.Record('local-reserved',{author='PrototypeTester-Ebonhold',ownerKey='prototypetester@ebonhold'}),options={source='local'}}})
check(tickets[1].committed==true,'new remote identity can fill the 1792nd total slot')
check(tickets[2].committed==false and tickets[2].reason=='REMOTE_HEADROOM_LIMIT',
 'later remote member observes aggregate reservation and local headroom')
check(tickets[3].committed==true,'explicit local save can use reserved headroom')
check(C.Status().buildIdentityCount==1793,'remote reservation and local identity count once each')
saved=S.Saved();ok,why=S.Remote(S.Record('remote-after-local'),'Third-Ebonhold')
check(ok==false and why=='REMOTE_HEADROOM_LIMIT','local headroom use does not reopen remote growth')
check(S.Saved()==saved,'aggregate refusal changes no stored row')

H,C=S.Boot(1800,function(db)
 for _,r in pairs(db.communityBuilds) do r.syncAdmissionOriginV1='legacy@ebonhold';r.unknownKeep={yes=true} end
end)
local rawBefore=S.Saved()
check(C.Status().buildIdentityCount==1800,'over-threshold legacy profile remains readable')
check(S.Saved()==rawBefore,'opening a legacy profile performs no quota migration/eviction')
check(S.Remote(S.Record('seed-1',{lastModified=4}),'Owner-Ebonhold'),'safe update in over-threshold profile remains possible')
check(S.Raw('seed-1').syncAdmissionOriginV1=='legacy@ebonhold' and S.Raw('seed-1').unknownKeep.yes,
 'safe update preserves original origin and unrelated unknown data')
local count=C.Status().buildIdentityCount
F.Reload();S.C=Nexus.BuildCatalog;C=S.C
check(C.Status().buildIdentityCount==count,'reload preserves all over-threshold identities')

F.fileHooks={[ [[data\BundledBuilds.lua]] ]=function()
 Nexus.BundledBuilds.builds={['shipped-only']=S.Record('shipped-only')}
end}
H,C=S.Boot(1791);F.fileHooks=nil
check(C.Status().buildIdentityCount==1792,'fixture: shipped and saved identities share the hard count')
check(S.Remote(S.Record('shipped-only',{lastModified=4,title='Updated shipped identity'}),'Owner-Ebonhold'),
 'an existing shipped-only identity remains an update at the remote threshold')
check(S.Raw('shipped-only').syncAdmissionOriginV1==nil,'shipped-only update is not charged as a new remote admission')
H,C=S.Boot(2048)
ok,why=S.Put(S.Record('beyond-hard-limit'),{source='local'})
check(ok==false and why=='ROOT_SLOT_LIMIT','the original hard cap still applies to new local identities')
print('PASS catalog_admission_limits checks='..checks)
