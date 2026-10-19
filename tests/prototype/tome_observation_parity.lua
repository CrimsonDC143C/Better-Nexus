-- Same raw call/Store transcript is compared externally on base and successor.
local F=dofile(os.getenv('NEXUS_TOME_TEST_SUPPORT') or 'tests/prototype/tome_observation_support.lua')
local U=dofile('tests/prototype/format5_support.lua')
local function hash(text)local h=5381;for i=1,#text do h=(h*33+text:byte(i))%2147483647 end;return h end
local function pack(...)return {n=select('#',...),...}end
for _,mode in ipairs({'known','missing'})do
 local W=F.Boot(mode);local trace={}
 local function wrap(name,fn)
  return function(...)
   local args=pack(...);local output=pack(fn(...));local pieces={name}
   for i=1,args.n do local v=args[i];pieces[#pieces+1]=(type(v)=='number' or type(v)=='boolean')and tostring(v) or type(v)end
   pieces[#pieces+1]='returns:'..output.n
   for i=1,output.n do pieces[#pieces+1]=type(output[i])end
   trace[#trace+1]=table.concat(pieces,':')
   return unpack(output,1,output.n)
  end
 end
 for name,fn in pairs(W.H.service)do if type(fn)=='function' then W.H.service[name]=wrap(name,fn)end end
 for step,key in ipairs({'A','B','A'})do
  F.Pick(W,key);W.H.Advance(12,.05)
  local count=#trace;local db=U.Serialize(NexusDB)
  F.Report(W)
  assert(#trace==count,'report adds no native service calls')
  assert(U.Serialize(NexusDB)==db,'report adds no durable writes')
  local v=F.Vector(W)
  print('PARITY',mode,step,key,tostring(v[1]),tostring(v[2]),#W.O.calls,#W.O.replies,#trace,hash(table.concat(trace,'\n')),hash(db))
  print('FULL_CALL_TRACE',mode,step,U.Serialize(trace))
  print('FULL_STORE_TRACE',mode,step,db)
 end
end
print('PASS tome_observation_parity: complete call/Store transcript retained for matched comparison')
