-- A prepared support file must distinguish the master Auto switch from the
-- effective tome-management permission at capture. No private player fixture.
local F=dofile('tests/prototype/select_followup_support.lua')
local H,A=F.R.Boot()
local builder=assert(Nexus.SupportReport)
local checks,failures=0,{}
local function check(v,m)
 checks=checks+1
 if not v then failures[#failures+1]=m;print('FAIL '..m) end
end
local prefix='Tome management at capture: permission='
local caveat='(autoDisable; effective session setting, not earlier switch history)'
local originalStore,originalSettings=Nexus.Store,Nexus.Store.Settings
local originalDB=H.Clone(NexusDB)
local actions=#H.actions
local function same(a,b,seen)
 if type(a)~=type(b) then return false end
 if type(a)~='table' then return a==b end
 seen=seen or {};if seen[a]==b then return true end;seen[a]=b
 for k,v in pairs(a) do if not same(v,b[k],seen) then return false end end
 for k in pairs(b) do if a[k]==nil then return false end end
 return true
end
local function prepare()
 local job=builder.NewPreparation({extended=true})
 local calls,reads,ok,result=F.Passive(A,function()
  for _=1,400 do
   local status=builder.Step(job)
   if status=='done' then return table.concat(job.chunks,'') end
   assert(status=='pending','report did not complete: '..tostring(status))
  end
  error('report step bound exhausted')
 end)
 assert(ok,result)
 check(#calls==0 and reads==0,'preparation reads no native service or adapter gate')
 check(#H.actions==actions,'preparation sends no action')
 return result
end
local function expectCase(label,getter,expected)
 local n=0
 Nexus.Store.Settings=function()n=n+1;return getter()end
 local text=prepare()
 check(text:find(prefix..expected,1,true)~=nil,label..' reports '..expected)
 check(text:find(caveat,1,true)~=nil,label..' states capture-only scope')
 check(n<=2,label..' keeps settings reads bounded including existing report readers')
 check(text:find('Auto: selected=no effective=off',1,true)~=nil,label..' keeps master Auto OFF separate')
 check(not text:find('PRIVATE_SENTINEL',1,true),label..' exposes no other settings')
 return text
end
local setting={autoDisable=true,private='PRIVATE_SENTINEL'}
local captured=expectCase('true',function()return setting end,'yes')
setting.autoDisable=false
check(captured:find(prefix..'yes',1,true)~=nil,'a prepared report is not rewritten by later settings')
expectCase('false',function()return setting end,'no')
expectCase('absent field',function()return {} end,'unknown')
expectCase('invalid truthy number',function()return {autoDisable=1} end,'unknown')
expectCase('invalid string',function()return {autoDisable='false'} end,'unknown')
expectCase('owner error',function()error('PRIVATE_SENTINEL')end,'unknown')
expectCase('non-table',function()return false end,'unknown')
local trap=0
expectCase('table metamethod',function()return setmetatable({},{__index=function()trap=trap+1;error('PRIVATE_SENTINEL')end})end,'unknown')
-- Existing report sections may query settings too; no global zero-metatable-
-- read claim is made. The new field must still remain unknown for this proxy.
Nexus.Store.Settings=nil
local missingGetter=prepare()
check(missingGetter:find(prefix..'unknown',1,true)~=nil,'missing settings accessor is unknown')
Nexus.Store=17
local missingOwner=prepare()
check(missingOwner:find(prefix..'unknown',1,true)~=nil,'non-table owner is unknown')
Nexus.Store=originalStore;Nexus.Store.Settings=originalSettings
check(same(originalDB,NexusDB),'preparation leaves all durable data unchanged')
check(Nexus.AutomationEffectiveState().selected==false,'preparation leaves Auto OFF')
print('SUMMARY support_tome_permission checks='..checks..' failures='..#failures)
assert(#failures==0,table.concat(failures,'\n'))
print('PASS support_tome_permission: bounded capture-only permission; false distinct from unknown; no actions, native reads or durable writes')
