-- NX-01 scheduled Echo-catalog check work (stutter review, 2026-10-14). On the
-- delivered build test.2026101502-3d52b0ed7044 (and with the NX-03/NX-02
-- fixes, which do not touch this path) the keyed scheduler runs
-- GameAdapter.CheckCatalogSource every 30 s. Each run re-materializes the whole
-- Echo catalog from ProjectEbonhold.PerkDatabase (one GetSpellInfo per row) and
-- hashes the whole canonical text with one string.byte per byte, in ONE frame,
-- also when nothing changed. Historical figure: 90 lookups and 4418 byte calls
-- in one tick for the 90-row harness catalog.
--
-- Required: while the source is unchanged, the per-frame work of the scheduled
-- check does not grow with the source. For 600, 1200 and 2400 extra catalog
-- rows, no frame does more than 64 catalog-name lookups or reads more than
-- 8192 bytes of catalog text. The scheduled check still verifies the unchanged
-- source in every 45 s window.
--
-- SETUP and GUARD checks pass on the baseline. The BOUND check runs last; it is
-- EXPECTED RED until the NX-01 fix. Work units, both real boundaries:
--  * filler lookups: calls of the global GetSpellInfo with a filler spell ID
--    (610001..612400). Only PerkDatabase holds these IDs; no slot, board,
--    wishlist or window shows them.
--  * catalog text bytes: byte values string.byte returns for a string that
--    contains the filler-name marker 'Nx01Fill'. A chunked s:byte(i,j) is
--    charged per byte.
-- string.byte is wrapped before any module loads and GetSpellInfo before the
-- boot, so a module-level capture of either captures the wrapper. Both delegate
-- to the real functions. Frames are the harness clock: one H.Advance(step,step)
-- is one OnUpdate frame. The supported one-slice catalog pacing makes the
-- per-frame split deterministic. Lifecycle controls: stutter_catalog_lifecycle.lua.
local T=dofile('tests/prototype/startup_support.lua')
T.SingleSlicePacing()
local checks=0;local function check(v,m)assert(v,m);checks=checks+1 end

local MARK='Nx01Fill'
local work={on=false,lookups=0,bytes=0}
local rawByte,rawFind=string.byte,string.find
local marked={}
local function Tally(...) work.bytes=work.bytes+select('#',...);return ... end
string.byte=function(s,...)
 if work.on and type(s)=='string' then
  local m=marked[s]
  if m==nil then m=rawFind(s,MARK,1,true)~=nil;marked[s]=m end
  if m then return Tally(rawByte(s,...)) end
 end
 return rawByte(s,...)
end

local H=dofile('tests/prototype/harness.lua')
local FIRST,LAST=610001,612400
local rawInfo=GetSpellInfo
GetSpellInfo=function(id,...)
 if work.on then
  local n=tonumber(id)
  if n and n>=FIRST and n<=LAST then work.lookups=work.lookups+1 end
 end
 return rawInfo(id,...)
end

local filled=0
local function Fill(size)
 for i=filled+1,size do H.AddEcho(FIRST-1+i,'Nx01Filler Echo '..i,i%4,3) end
 filled=size
end
Fill(600)

-- SETUP: the instruments count a filler lookup and a marked byte only.
work.on=true
local n1,n2=GetSpellInfo(FIRST),GetSpellInfo(200001)
local b1,b2,b3,b4=('Nx01Filler'):byte(1,4)
local other=('Echo 1'):byte(1)
work.on=false
check(n1=='Nx01Filler Echo 1' and n2=='Echo 1' and b1==78 and b2==120 and b3==48 and b4==49 and other==69,
 'SETUP: the instruments return the real answers')
check(work.lookups==1 and work.bytes==4,
 'SETUP: one filler lookup and 4 marked bytes are counted, nothing else: lookups='..work.lookups..' bytes='..work.bytes)

H.Boot()
local A=Nexus.GameAdapter
for _=1,2000 do if A.CatalogStatus().scheduled==true then break end;H.Advance(.05,.05) end
check(A.CatalogStatus().scheduled==true,'SETUP: the catalog source check is scheduled')

local function Rows(c) local n=0;for _ in pairs(c.rows) do n=n+1 end;return n end
local c=A.Catalog()
check(type(c)=='table' and type(c.rows[FIRST])=='table' and c.rows[FIRST].name=='Nx01Filler Echo 1'
 and c.familyOf[FIRST]=='s610001','SETUP: the boot catalog has the filler rows')

local STEP=.05
local function Frames(seconds,measure)
 local peakL,peakB,sumL,sumB=0,0,0,0
 for _=1,math.floor(seconds/STEP+.5) do
  work.lookups,work.bytes=0,0;work.on=measure
  H.Advance(STEP,STEP)
  work.on=false
  if work.lookups>peakL then peakL=work.lookups end
  if work.bytes>peakB then peakB=work.bytes end
  sumL,sumB=sumL+work.lookups,sumB+work.bytes
 end
 return peakL,peakB,sumL,sumB
end

local SIZES={600,1200,2400}
local LOOKUP_BOUND,BYTE_BOUND=64,8192
local SETTLE,WINDOW=35,45
local results={}
for _,size in ipairs(SIZES) do
 local label='size '..size
 if size>filled then
  -- In-place growth, published by an explicit check outside the measured frames.
  Fill(size)
  local ok,result,changed=A.CheckCatalogSource()
  check(ok==true and result=='rebuilt' and changed==true,
   label..' SETUP: the explicit check publishes the grown source: '..tostring(ok)..' '..tostring(result)..' '..tostring(changed))
 end
 local last=FIRST-1+size
 c=A.Catalog()
 check(type(c)=='table' and Rows(c)==90+size and type(c.rows[last])=='table'
  and c.rows[last].name=='Nx01Filler Echo '..size and c.familyOf[last]=='s'..last,
  label..' SETUP: the published catalog has '..(90+size)..' rows: '..tostring(type(c)=='table' and Rows(c)))
 Frames(SETTLE,false)
 local s0,c0=A.CatalogStatus(),A.Catalog()
 local peakL,peakB,sumL,sumB=Frames(WINDOW,true)
 local s1=A.CatalogStatus()
 local verified=s1.equivalent-s0.equivalent
 check(verified>=1 and s1.rebuilds==s0.rebuilds and s1.failures==s0.failures and s1.lastResult=='unchanged'
  and s1.lastError==nil and A.Catalog()==c0 and s1.publishedHash==s0.publishedHash,
  label..' GUARD: the scheduled check verified the unchanged source in the '..WINDOW..' s window: unchanged checks='
  ..verified..' rebuilds '..s0.rebuilds..' -> '..s1.rebuilds..' last='..tostring(s1.lastResult)
  ..' same catalog='..tostring(A.Catalog()==c0))
 print(string.format('NX01_MEASURE filler_rows=%d catalog_rows=%d window_seconds=%d frames=%d unchanged_checks=%d '
  ..'peak_frame_filler_lookups=%d peak_frame_catalog_text_bytes=%d window_filler_lookups=%d window_catalog_text_bytes=%d',
  size,90+size,WINDOW,math.floor(WINDOW/STEP+.5),verified,peakL,peakB,sumL,sumB))
 results[#results+1]={size=size,lookups=peakL,bytes=peakB}
end

GetSpellInfo,string.byte=rawInfo,rawByte
local over={}
for _,r in ipairs(results) do
 if r.lookups>LOOKUP_BOUND or r.bytes>BYTE_BOUND then
  over[#over+1]=r.size..' filler rows: '..r.lookups..' lookups and '..r.bytes..' bytes in one frame'
 end
end
if #over>0 then
 error('BOUND (expected RED until the NX-01 fix): the scheduled check of an unchanged Echo catalog did per-frame work '
  ..'that grows with the source (bound '..LOOKUP_BOUND..' filler-name lookups and '..BYTE_BOUND..' catalog-text bytes per frame): '
  ..table.concat(over,'; ')..' ('..checks..' SETUP/GUARD checks passed)',0)
end
print('PASS scheduled unchanged Echo catalog check: per-frame work flat for 600/1200/2400 extra rows, unchanged source verified; '..checks..' checks')
