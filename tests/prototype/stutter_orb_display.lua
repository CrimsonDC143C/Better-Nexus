-- NX-02 Orb display reconciliation work (stutter review, 2026-10-14). On the
-- delivered build test.2026101502-3d52b0ed7044, every Orb window refresh
-- (OrbRuntime.Status, every 0.25 s) reads through OrbAdapter.Read, whose context
-- runs a full Echo-state reconciliation in each new frame
-- (GameAdapter.EchoActiveSlotGeneration). Historical figure: 4 full scans for
-- 4 idle refreshes. The display uses none of that scan's results; every shown
-- value is read fresh by OrbAdapter.Read itself.
--
-- Required: 4 idle display refreshes over 1.0 s, with no notification and no
-- change, run at most one full reconciliation (FINAL_AUDIT P3a: display reuse
-- only within a documented <=1 s bound, only while no notification is pending).
-- The display shows the same literal state on every refresh.
--
-- SETUP and GUARD checks pass on the baseline. The BOUND check runs last; it is
-- EXPECTED RED until the NX-02 fix. Work unit: reads of the game's
-- PerkService.GetServerActiveSlot made outside a GameAdapter.Slots projection.
-- Its only other production caller is the full reconciliation
-- (CaptureEchoSnapshot), so each such read is one full scan. Both instruments
-- delegate to the real functions. Semantic controls: stutter_orb_authority.lua.
local H=dofile('tests/prototype/orbs_support.lua')
local A,M=H.A,H.M
local checks=0;local function check(v,m)assert(v,m);checks=checks+1 end

H.OrbPlan() -- the assigned plan: one copy of 410002 (quality 2)

-- Instruments: the foreign active-slot read and the public slot projection.
local S=H.service
local work={outside=0,inside=0,projections=0}
local depth=0
local rawActive=S.GetServerActiveSlot
S.GetServerActiveSlot=function(...)
 if depth>0 then work.inside=work.inside+1 else work.outside=work.outside+1 end
 return rawActive(...)
end
local rawSlots=A.Slots
local function Leave(ok,...)
 depth=depth-1
 if not ok then error((...),0) end
 return ...
end
A.Slots=function(...)
 work.projections=work.projections+1;depth=depth+1
 return Leave(pcall(rawSlots,...))
end
local function Reset() for k in pairs(work) do work[k]=0 end end
local function Scans() return A.EchoReconcileStats().scans end
local function Later() H.now=H.now+.25 end

-- SETUP: the instruments count one full reconciliation as one outside read,
-- and one slot projection as one inside read.
Later();Reset();local s0=Scans()
A.EchoActiveSlotGeneration()
check(work.outside==1 and work.inside==0 and work.projections==0 and Scans()-s0==1,
 'SETUP: one reconciliation in a new frame reads the active slot once, outside any projection: outside='
 ..work.outside..' inside='..work.inside..' projections='..work.projections..' scans='..(Scans()-s0))
Reset();A.EchoActiveSlotGeneration()
check(work.outside==0,'SETUP: a second reconciliation in the same frame reuses the scan: outside='..work.outside)
Later();Reset();A.Slots()
check(work.outside==0 and work.inside==1 and work.projections==1,
 'SETUP: one slot projection reads the active slot once, inside the projection: outside='
 ..work.outside..' inside='..work.inside..' projections='..work.projections)

-- The display state every refresh must show (literal).
local function Shown(label,r)
 check(type(r)=='table' and r.error==nil and type(r.assignment)=='table' and r.assignment.state=='ready'
  and type(r.progress)=='table' and r.progress.rolledMissing==1 and r.canStart==true,
  label..': the display shows the assigned plan, one missing copy and Start available: error='
  ..tostring(r and r.error)..' reason='..tostring(r and r.startReason)..' assignment='
  ..tostring(r and r.assignment and r.assignment.state)..' missing='..tostring(r and r.progress and r.progress.rolledMissing))
end

-- SETUP: two warm-up refreshes, then one direct (action-path) read that runs
-- its own full reconciliation (orb_read_signature_cost contract).
Later();Shown('SETUP warm-up 1',M.Status(false))
Later();Shown('SETUP warm-up 2',M.Status(false))
Later();Reset()
local fresh=A.Orbs.Read()
check(type(fresh)=='table' and work.outside==1,'SETUP: a direct Orb read in a new frame runs one full reconciliation: outside='..work.outside)

-- Measure: 4 idle display refreshes over 1.0 s, no notification, no change.
Reset();local s1=Scans()
for i=1,4 do Later();Shown('GUARD refresh '..i,M.Status(false)) end
local reconciliations,projections,scans=work.outside,work.projections,Scans()-s1
print(string.format('NX02_MEASURE orb_display_refreshes=4 seconds=1.00 notifications=0 reconciliation_reads=%d slot_projections=%d reconcile_scans_stat=%d',
 reconciliations,projections,scans))

S.GetServerActiveSlot,A.Slots=rawActive,rawSlots
if reconciliations>1 then
 error('BOUND (expected RED until the NX-02 fix): 4 idle Orb display refreshes over 1.0 s with no notification ran '
  ..reconciliations..' full Echo reconciliations (bound 1) ('..checks..' SETUP/GUARD checks passed)',0)
end
print('PASS idle Orb display: at most one full Echo reconciliation per 4 refreshes over 1.0 s, display unchanged; '..checks..' checks')
