-- The optional field name used to be unknown: old bounded values stay unknown.
local S=dofile('tests/prototype/catalog_admission_policy_support.lua')
local F=S.F
local checks=0;local function check(v,m)assert(v,m);checks=checks+1 end
local values={false,{keep=true,nested={origin='not-authenticated'}},string.rep('x',178),
 'not-a-canonical-origin',42}
local H,C=S.Boot(0,function(db)
 for i,v in ipairs(values) do
  db.communityBuilds['legacy-'..i]=S.Record('legacy-'..i,{syncAdmissionOriginV1=v,
   otherUnknown={keep=i}})
 end
end)
for i,v in ipairs(values) do
 local id='legacy-'..i
 check(C.Get(id)~=nil,'historically valid row stays readable with old unknown marker shape '..i)
 check(F.Serialize(S.Raw(id).syncAdmissionOriginV1)==F.Serialize(v),'old marker value is kept exact '..i)
 check(S.Remote(S.Record(id,{lastModified=3,syncAdmissionOriginV1='forged@foreign'}),'Owner-Ebonhold'),
  'ordinary safe update remains possible for old marker shape '..i)
 check(F.Serialize(S.Raw(id).syncAdmissionOriginV1)==F.Serialize(v),
  'update preserves old unknown marker value exactly '..i)
 check(S.Raw(id).otherUnknown.keep==i,'unrelated unknown evidence is kept '..i)
end
local saved=S.Saved()
H=F.Reload();S.H=H;S.C=Nexus.BuildCatalog;C=S.C
check(S.Saved()==saved,'literal reload does not migrate/rewrite any old unknown marker')
for i=1,#values do check(C.Get('legacy-'..i)~=nil,'old row remains readable after reload '..i) end
print('PASS catalog_admission_legacy_field checks='..checks)
