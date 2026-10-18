-- NX-02 display reuse expiry (review B1, 2026-10-15). PROPOSED new appended
-- test; not registered and not run. The controls in stutter_orb_authority.lua
-- anchor every expiry check on a direct or default reconciliation, which clears
-- the display reuse record, so the first display read after them always scans
-- whatever the window. Here a reuse record is seeded by a display read right
-- after a direct read, and only display reads follow it.
--
-- Required:
--  E. Expiry is bounded and does not slide: after an unnotified in-place
--     active-slot change made right after the seeding display read at t0,
--     display-only reads every 0.25 s (no other reconciling reader) show the
--     change in the active-slot generation and in the returned context.active
--     by t0+1.25 s.
--  B. A clock that moves backward never extends reuse: a display read 5 s
--     before the seeding scan reconciles the change.
--  O. Only the exact opt-ins reuse: inside a live reuse window every other
--     argument to A.EchoActiveSlotGeneration and A.Orbs.Read reconciles.
-- GUARD checks prove each case runs inside a live reuse window (a display read
-- 0.25 s after the seeding scan still returns the seeded generation), so no
-- expectation is vacuous. Public seams, the harness clock and the synthetic
-- PerkService mirror only; no debug hooks, no private state.
local H=dofile('tests/prototype/orbs_support.lua')
local A=H.A
local checks=0;local function check(v,m)assert(v,m);checks=checks+1 end

H.OrbPlan() -- the assigned plan: one copy of 410002 (quality 2)

local function Active() return (select(2,A.PresentationRevisions())) end
local function Scans() return A.EchoReconcileStats().scans end
local function C(r,k) if type(r)=='table' and type(r.context)=='table' then return r.context[k] end end
local function Display() return A.Orbs.Read('display') end
local function Later() H.now=H.now+.25 end
-- A fresh reuse record: a direct read clears any record, then one display read
-- 0.25 s later scans once and records itself. Returns the seeded generation.
local function Seed(label)
 Later();local direct,why=A.Orbs.Read()
 check(type(direct)=='table',label..' SETUP: the direct read succeeds: '..tostring(why))
 Later();local s0=Scans();local d;d,why=Display();local g=Active()
 check(type(d)=='table' and Scans()-s0==1 and type(g)=='number' and C(d,'active')==g,
  label..' SETUP: the seeding display read scans once and carries the active generation: scans '..(Scans()-s0)
  ..' context '..tostring(C(d,'active'))..' generation '..tostring(g)..' '..tostring(why))
 return g
end
-- Unnotified in-place active-slot change: the synthetic slot alternates 0/1.
local slot=0
local function Toggle() slot=slot==0 and 1 or 0;H.perks.serverActiveSlot=slot end

check(H.perks.serverActiveSlot==0,'SETUP: the synthetic active slot starts at 0: '..tostring(H.perks.serverActiveSlot))

-- E. Bounded, non-sliding expiry with display-only reads.
H.now=math.floor(H.now)+1 -- whole seconds: every 0.25 s step below is exact
local g0=Seed('E')
Toggle()
local seen,last,lastWhy
for k=1,5 do
 Later();last,lastWhy=Display()
 local g=Active()
 check(type(last)=='table','E SETUP: the display read at t0+'..(k*.25)..' s succeeds: '..tostring(lastWhy))
 if k==1 then
  check(g==g0 and C(last,'active')==g0,
   'E GUARD: 0.25 s after the seeding scan the display read reuses it: generation '..g
   ..' context '..tostring(C(last,'active'))..' after '..g0)
 end
 if seen==nil and g==g0+1 then seen=k*.25 end
end
print('EXPIRY first_seen=+'..tostring(seen)..' s (characterization, not asserted)')
check(Active()==g0+1 and C(last,'active')==g0+1,
 'E display-only reads show the unnotified active-slot change by t0+1.25 s: generation '..Active()
 ..' context '..tostring(C(last,'active'))..' after '..g0)

-- B. A backward clock never extends reuse.
local g1=Seed('B');local t1=H.now
Toggle()
Later();local d,why=Display()
check(type(d)=='table' and Active()==g1 and C(d,'active')==g1,
 'B GUARD: 0.25 s after the seeding scan the display read still reuses it: generation '..Active()
 ..' context '..tostring(C(d,'active'))..' after '..g1..' '..tostring(why))
H.now=t1-5
d,why=Display()
check(type(d)=='table','B SETUP: the display read 5 s before the seeding scan succeeds: '..tostring(why))
check(Active()==g1+1 and C(d,'active')==g1+1,
 'B a display read 5 s before the seeding scan reconciles the unnotified slot change: generation '..Active()
 ..' context '..tostring(C(d,'active'))..' after '..g1)
H.now=t1+.5

-- O. Inside a live reuse window only the exact opt-ins reuse.
local calls={
 {'A.EchoActiveSlotGeneration(3600)',function() return A.EchoActiveSlotGeneration(3600) end},
 {'A.EchoActiveSlotGeneration("display")',function() return A.EchoActiveSlotGeneration('display') end},
 {'A.EchoActiveSlotGeneration(math.huge)',function() return A.EchoActiveSlotGeneration(math.huge) end},
 {'A.EchoActiveSlotGeneration(1)',function() return A.EchoActiveSlotGeneration(1) end},
 {'A.EchoActiveSlotGeneration(0)',function() return A.EchoActiveSlotGeneration(0) end},
 {'A.EchoActiveSlotGeneration(-1)',function() return A.EchoActiveSlotGeneration(-1) end},
 {'A.EchoActiveSlotGeneration(0/0)',function() return A.EchoActiveSlotGeneration(0/0) end},
 {'A.EchoActiveSlotGeneration({})',function() return A.EchoActiveSlotGeneration({}) end},
 {'A.EchoActiveSlotGeneration(false)',function() return A.EchoActiveSlotGeneration(false) end},
 {'A.Orbs.Read(3600)',function() return C(A.Orbs.Read(3600),'active') end},
 {'A.Orbs.Read(true)',function() return C(A.Orbs.Read(true),'active') end},
}
for _,c in ipairs(calls) do
 local g=Seed('O '..c[1])
 Toggle()
 Later()
 local reused=A.EchoActiveSlotGeneration(true)
 check(reused==g,'O GUARD '..c[1]..': the display opt-in still reuses the seeded scan: '..tostring(reused)..' after '..g)
 local ok,got=pcall(c[2])
 check(ok and got==g+1 and Active()==g+1,
  'O '..c[1]..' inside the reuse window reconciles the unnotified slot change: '..tostring(got)
  ..' generation '..Active()..' after '..g)
end

print('PASS Orb display reuse expiry: bounded and non-sliding with display-only reads, backward clock, exact opt-ins; '..checks..' checks')
