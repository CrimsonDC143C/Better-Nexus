-- Real report/Performance owners; synthetic clocks and game. No user data.
local T=dofile('tests/prototype/startup_support.lua')
Nexus=nil;NexusDB=nil;WishlistRealizerDB=nil;SlashCmdList=nil
local H=dofile('tests/prototype/harness.lua')
NexusDB=T.Profile(0,0);T.Load();H.Fire('ADDON_LOADED','Nexus');H.Fire('PLAYER_ENTERING_WORLD')
T.Until(H,function()return Nexus.StartupStatus().state=='ready'end)
local P=Nexus.Performance;local M=Nexus.SupportReport
local checks=0;local function check(v,m)assert(v,m);checks=checks+1 end
local function lines(short) return table.concat(M.TargetedDiagnosticLines(short),'\n') end
local cold=lines(true)
check(cold:find('Targeted stutter diagnostics: configured=no',1,true),'actual default OFF is exported, not unknown')
check(cold:find('Assignment detail: configured=no',1,true),'assignment detail flag is separately exported')
local clocks,memories=0,0;local ms,heap=0,1000
P.SetClock(function()clocks=clocks+1;ms=ms+1;return ms end)
P.SetDiagnosticSessionClock(function()return H.now end)
P.SetDiagnosticMemoryReader(function()memories=memories+1;heap=heap+1;return heap end)
assert(P.SetDiagnosticEnabled(true));P.ResetDiagnostics()
local a,b,c=P.MeasureDiagnostic('orb.status',function()
 return P.MeasureDiagnostic('echo.reconcile',function()return 'safe',nil,false end)
end)
check(a=='safe' and b==nil and c==false,'diagnostic return arity/nil/false unchanged')
local beforeClock,beforeMemory=clocks,memories
local before=Nexus.Codec.JSONEncode(NexusDB)
local full=lines(false)
check(clocks==beforeClock and memories==beforeMemory,'export samples no clock/heap and advances no work')
check(before==Nexus.Codec.JSONEncode(NexusDB),'formatting does not mutate saved data')
check(full:find('global',1,true)~=nil or full:find('GLOBAL',1,true)~=nil,'net global heap meaning is explicit')
check(full:find('not bytes allocated or GC duration',1,true),'does not call net heap allocated bytes or GC time')
check(full:find('not exclusive addon CPU',1,true),'inclusive/residual elapsed truth is explicit')
check(full:find('Diagnostic span',1,true),'bounded geometry retained in report')
check(full:find('session_available=no',1,true),'frozen same-frame session bounds remain unavailable')
check(full:find('frozen_or_zero_window',1,true),'frozen session window reason retained')
check(full==lines(false),'detached snapshot formatting has no new sample or state changes')
local oldBoundary=Nexus.OrbRuntime.BoundaryDiagnostics
Nexus.OrbRuntime.BoundaryDiagnostics=function()
 return {observed=true,receiptPresent=true,mode='session_only',reason='restored_receipt',retained=1,dropped=0,captureFailures=0,unsaved=false,
  snapshot={chargesBefore=100,chargesNow=95,chargeRelation='lower',ownedRelation='neither',offerPresent=false,pickInFlight=false,hostPending=false,epoch=3,phase='w'},
  receiptJournal={},sessionJournal={{event='leave',epoch=2,phase='l',charge=95,relation='lower',owned='neither',offer=false,pick=false,host=false,player='SECRETPLAYER',payload='SECRETPACKET'}}}
end
local boundary=lines(false)
check(boundary:find('before=100; now=95; charge_relation=lower; owned_relation=neither',1,true),'missing recovery comparisons are explicitly exported')
check(boundary:find('offer=no; pick=no; host=no',1,true),'false comparisons are not changed to unknown')
check(boundary:find('sessionJournal 1',1,true),'bounded journal is included')
check(not boundary:find('SECRET',1,true),'extra arbitrary/private journal fields never exported')
check(boundary:find('not a server transaction token',1,true),'local journal IDs never claimed as server correlation')
Nexus.OrbRuntime.BoundaryDiagnostics=oldBoundary
local rawSnapshot=P.SnapshotDiagnostics
P.SnapshotDiagnostics=function()error('PRIVATEFAILURE')end
local failed=lines(false)
check(failed:find('Targeted stutter diagnostics: configured=unknown',1,true),'unavailable owner is unknown, not disabled/zero')
check(not failed:find('PRIVATEFAILURE',1,true),'owner exception text is not exported')
check(failed:find('Assignment detail:',1,true),'a failed diagnostic owner does not omit the independent assignment owner')
P.SnapshotDiagnostics=rawSnapshot
P.SnapshotDiagnostics=function()return {enabled=false,clockState='SECRETPLAYER',memoryState='SECRETPACKET',spans={},rows={}}end
check(not lines(false):find('SECRET',1,true),'only fixed enumerated diagnostics codes are exported')
P.SnapshotDiagnostics=rawSnapshot
local rootPerformance,rootOrb,oldMeta=Nexus.Performance,Nexus.OrbRuntime,getmetatable(Nexus)
Nexus.Performance=nil;Nexus.OrbRuntime=nil
setmetatable(Nexus,{__index=function()error('ROOTOWNERFAILURE')end})
local noOwners=lines(false)
check(noOwners:find('configured=unknown',1,true)~=nil and not noOwners:find('ROOTOWNERFAILURE',1,true),'root owner lookups do not invoke a poisoned metatable')
setmetatable(Nexus,oldMeta);Nexus.Performance=rootPerformance;Nexus.OrbRuntime=rootOrb
local summary=assert(M.Summary())
check(#summary<=M.SUMMARY_MAX_BYTES,'compact summary byte budget preserved')
check(summary:find('Targeted stutter diagnostics:',1,true),'normal Copy summary includes actual diagnostic flags')
check(summary:find('Orb comparisons:',1,true),'normal Copy summary includes recovery comparison classification')
local completed=assert(M.Prepare({extended=false}))
local prepared=table.concat(completed.chunks)
check(prepared:find('-- targeted diagnostics',1,true),'normal Prepare file exports the new bounded section')
check(prepared:find('Diagnostic span',1,true),'normal Prepare file carries available geometry')
check(completed.meta.checksum==M.Checksum(completed.chunks),'full report chunk checksum contract preserved')
P.SetDiagnosticMemoryReader(function()return nil end);P.ResetDiagnostics()
P.MeasureDiagnostic('orb.read',function()return 'unchanged'end)
local unavailable=lines(false)
check(unavailable:find('heap_net_KB=unknown; heap_count=0; heap_available=no',1,true),'unavailable heap observations are not exported as measured zero')
check(unavailable:find('residual_ms=unknown; residual_count=0; residual_available=no',1,true),'unused path residual is not exported as measured zero')
P.SetDiagnosticEnabled(false)
check(lines(true):find('configured=no',1,true),'actual explicit OFF returns without conflating prior samples')
print('PASS support_targeted_diagnostics checks='..checks)
