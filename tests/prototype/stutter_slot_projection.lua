-- NX-03 slot projection catalog work (stutter review, 2026-10-14). On the
-- delivered build test.2026101502-3d52b0ed7044, one GameAdapter.Slots()
-- projection acquires the Echo catalog once per projected Echo (FamilyOf), and
-- every acquisition reads the Project Ebonhold source version through
-- GetAddOnMetadata. Historical figure on a 15 x 79 synthetic mirror: 1185
-- acquisitions in one projection.
--
-- Required: one complete projection makes at most one successful catalog
-- acquisition and reads the catalog source at most once, but at least once
-- (each projection still sees the live source; no trust carries over to the
-- next projection). Slot IDs, copies, qualities and families are the same as
-- before. An Echo that is not in the catalog keeps its "s<spellId>" family.
--
-- SETUP, EXPECT and GUARD checks pass on the baseline. The BOUND checks run
-- last; they are EXPECTED RED until the NX-03 fix. Counts come from the public
-- GameAdapter.Catalog field and the WoW GetAddOnMetadata API; both delegate to
-- the real functions. Semantic controls: stutter_catalog_semantics.lua.
local H=dofile('tests/prototype/harness.lua')
local checks=0;local function check(v,m)assert(v,m);checks=checks+1 end

-- Catalog rows. Families worked by hand from the contract rule
-- (CONTRACTS.md: "g<groupId>" when more than one row shares groupId, else "s<spellId>").
H.AddEcho(330001,'Stutter Pair One',1,3,3300)
H.AddEcho(330002,'Stutter Pair Two',2,3,3300)
H.AddEcho(330003,'Stutter Lone Group',3,2,3301)
H.AddEcho(330004,'Stutter Ungrouped',0,4,0)
H.AddEcho(330005,'Stutter Trio One',1,2,3302)
H.AddEcho(330006,'Stutter Trio Two',2,2,3302)
H.AddEcho(330007,'Stutter Trio Three',3,2,3302)
local UNKNOWN=339999 -- not in PerkDatabase
local FAMILY={[330001]='g3300',[330002]='g3300',[330003]='s330003',[330004]='s330004',
 [330005]='g3302',[330006]='g3302',[330007]='g3302',[339999]='s339999'}

-- Small sparse mirror with literal expectations {spellId, stacks, quality, family}.
local function Small()
 return {
  [1]={name='Alpha',verified=true,echoes={
   {spellId=330001,quality=1,stacks=2},{spellId=330003,quality=3,stacks=1},
   {spellId=UNKNOWN,quality=0,stacks=1},{spellId=330005,quality=2,stacks=3}}},
  [2]={name='Beta',verified=true,echoes={
   {spellId=330002,quality=2,stacks=1},{spellId=330004,quality=0},
   {spellId=330006,quality=1,stacks=2},{spellId=330007,quality=3,stacks=1}}},
  [4]={name='Delta',verified=false,echoes={}},
 }
end
local SMALL={
 [1]={name='Alpha',echoes={{330001,2,1,'g3300'},{330003,1,3,'s330003'},{339999,1,0,'s339999'},{330005,3,2,'g3302'}}},
 [2]={name='Beta',echoes={{330002,1,2,'g3300'},{330004,1,0,'s330004'},{330006,2,1,'g3302'},{330007,1,3,'g3302'}}},
 [4]={name='Delta',echoes={}},
}

-- Large mirror: the historical 15 rows x 79 Echoes.
local ROWS,PER=15,79
local IDS={330001,330002,330003,330004,330005,330006,330007,UNKNOWN}
local function LargeEcho(r,j) return IDS[((r+j)%#IDS)+1],(j%3)+1,j%4 end
local function Large()
 local mirror={}
 for r=1,ROWS do
  local echoes={}
  for j=1,PER do local id,stacks,quality=LargeEcho(r,j);echoes[j]={spellId=id,quality=quality,stacks=stacks} end
  mirror[r]={name='Synthetic '..r,verified=r<=5,echoes=echoes}
 end
 return mirror
end

local P=H.perks
P.serverBuildSlots=Small()
H.Boot()
local A=Nexus.GameAdapter
check(type(A.Catalog())=='table' and A.CatalogStatus().rebuilds>=1,'SETUP: the Echo catalog is built at boot')

-- Instruments: public catalog lookup and the foreign source read. Both delegate.
local work={acquired=0,empty=0,source=0}
local rawCatalog=A.Catalog
A.Catalog=function(...)
 local cat=rawCatalog(...)
 if cat~=nil then work.acquired=work.acquired+1 else work.empty=work.empty+1 end
 return cat
end
local rawMeta=GetAddOnMetadata
GetAddOnMetadata=function(addon,field,...)
 if addon=='ProjectEbonhold' and field=='Version' then work.source=work.source+1 end
 return rawMeta(addon,field,...)
end
local function Reset() for k in pairs(work) do work[k]=0 end end
Reset();A.Catalog()
check(work.acquired==1 and work.empty==0 and work.source==1,
 'SETUP: the instruments count one direct catalog lookup: acquired='..work.acquired..' source='..work.source)

-- One complete projection and the work it did.
local function Project()
 Reset()
 local slots=A.Slots()
 return slots,{acquired=work.acquired,empty=work.empty,source=work.source}
end
local over={}
local function Bound(label,w,echoes)
 print(string.format('NX03_MEASURE %s projected_echoes=%d catalog_acquisitions=%d empty_acquisitions=%d source_reads=%d',
  label,echoes,w.acquired,w.empty,w.source))
 check(w.empty==0,label..': GUARD every catalog acquisition returns the built catalog: '..w.empty)
 check(w.source>=1,label..': GUARD the projection reads the live catalog source: '..w.source)
 if w.acquired>1 then over[#over+1]=label..' catalog_acquisitions='..w.acquired..' (bound 1) for '..echoes..' Echoes' end
 if w.source>1 then over[#over+1]=label..' source_reads='..w.source..' (bound 1)' end
end
local function Echo(label,e,id,stacks,quality,family)
 check(type(e)=='table' and e.spellId==id and e.stacks==stacks and e.quality==quality and e.family==family,
  label..': EXPECT {'..id..','..stacks..','..quality..','..family..'} got {'
  ..tostring(e and e.spellId)..','..tostring(e and e.stacks)..','..tostring(e and e.quality)..','..tostring(e and e.family)..'}')
end

-- 1. Small mirror: literal slots, copies, qualities and families.
local slots,w=Project()
check(type(slots)=='table' and type(slots.bySlot)=='table','SETUP: the small mirror is projected')
local keys=0
for slot in pairs(slots.bySlot) do keys=keys+1;check(SMALL[slot]~=nil,'EXPECT no unexpected slot: '..tostring(slot)) end
check(keys==3,'EXPECT sparse slots 1, 2 and 4: '..keys)
for slot,want in pairs(SMALL) do
 local row=slots.bySlot[slot]
 check(row and row.slot==slot and row.name==want.name and #row.echoes==#want.echoes,'EXPECT slot '..slot..' row')
 for i,e in ipairs(want.echoes) do Echo('small slot '..slot..' Echo '..i,row.echoes[i],e[1],e[2],e[3],e[4]) end
end
check(slots.activeSlot==0 and slots.activeKnown==true and slots.maxSlots==5,'EXPECT no active slot, 5 slots')
Bound('small',w,8)

-- 2. Large mirror, two projections: the bound holds for each one.
P.serverBuildSlots=Large()
for pass=1,2 do
 local label='large pass '..pass
 slots,w=Project()
 check(type(slots)=='table' and type(slots.bySlot)=='table','SETUP: '..label..' is projected')
 local rows,total=0,0
 for r=1,ROWS do
  local row=slots.bySlot[r]
  check(row and row.name=='Synthetic '..r and #row.echoes==PER,'EXPECT '..label..' row '..r..' has '..PER..' Echoes')
  rows=rows+1
  for j=1,PER do
   local id,stacks,quality=LargeEcho(r,j)
   local e=row.echoes[j]
   if not (e and e.spellId==id and e.stacks==stacks and e.quality==quality and e.family==FAMILY[id]) then
    Echo(label..' row '..r..' Echo '..j,e,id,stacks,quality,FAMILY[id])
   end
   total=total+1
  end
 end
 check(rows==ROWS and total==ROWS*PER,'EXPECT '..label..': '..ROWS..' rows, '..(ROWS*PER)..' Echoes: '..total)
 Bound(label,w,ROWS*PER)
end

A.Catalog,GetAddOnMetadata=rawCatalog,rawMeta
if #over>0 then
 error('BOUND (expected RED until the NX-03 fix): one slot projection made more than one catalog acquisition or source read: '
  ..table.concat(over,'; ')..' ('..checks..' SETUP/EXPECT/GUARD checks passed)',0)
end
print('PASS one slot projection: at most one catalog acquisition and one source read, families unchanged; '..checks..' checks')
