-- Metamorphic public digest/full-payload checks: only local bookkeeping differs.
local S=dofile('tests/prototype/catalog_admission_policy_support.lua')
local F=S.F
local checks=0;local function check(v,m)assert(v,m);checks=checks+1 end
local function unused()error('CompactEncode unexpectedly called validation callback')end
local function Observe(witness)
 S.Boot(0,function(db)db.communityBuilds.semantic=S.Record('semantic',{syncAdmissionOriginV1=witness,ownerVerified=true})end)
 local row=S.C.Get('semantic')
 local protocol=Nexus.SyncInternals.Protocol.New({parseVersion=unused,ownerKeyMatchesAuthor=unused,isSafeTree=unused})
 local delta,all=Nexus.Sync.GetCanonicalBuildHashes()
 check(type(delta)=='string' and type(all)=='string','canonical digest is available')
 check(all~='0,0,0,0,0,0,0,0','fixture exercises a nonempty real catalog digest')
 local advertised=Nexus.Sync.GetCompatibilityHashes()
 check(advertised==delta,'actual advertised digest agrees with canonical digest')
 return {fingerprint=row.fingerprint,fingerprintHash=row.fingerprintHash,
  payload=Nexus.Codec.JSONEncode(protocol.CompactEncode(row)),delta=delta,all=all,
  legacy=Nexus.Sync.GetLegacyBuildHash()}
end
local baseline=F.Serialize(Observe(nil))
check(F.Serialize(Observe('relay@ebonhold'))==baseline,'qualified local admission metadata changes no content/digest/wire semantics')
check(F.Serialize(Observe('transport-bare:origin'))==baseline,'bare local admission metadata changes no content/digest/wire semantics')
print('PASS catalog_admission_semantics checks='..checks)
