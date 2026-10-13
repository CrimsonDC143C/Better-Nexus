-- Machine-readable complete-run trials. evaluate.py owns train/test separation.
local P=dofile('tests/prototype/policy_adapter.lua');P.Load('.')
local Sim=dofile('tools/echo-policy-sim/simulator.lua')
local Candidates=dofile('tools/echo-policy-sim/candidates.lua')
local Corpus=dofile(arg[4]=='client-v3' and 'tools/echo-policy-sim/mechanics_corpus.lua' or 'tools/echo-policy-sim/corpus.lua')
if arg[1]=='--list' then
    print('id,order,freeze,reserve,family_safe,one_banish')
    for _,c in ipairs(Candidates.all) do
        local v=c.spec
        print(table.concat({v.id,v.order,v.freeze,v.reserve,tostring(v.familySafe),tostring(v.oneBanish)},','))
    end
    return
end
local first,count=tonumber(arg[1]),tonumber(arg[2])
assert(first and first>=1 and first==math.floor(first),'positive start seed required')
assert(count and count>=1 and count<=10000 and count==math.floor(count),'count must be 1..10000')
assert(first+count<2147483647,'seed range too large')
local selected={}
for id in tostring(arg[3] or 'released'):gmatch('[^,]+') do selected[#selected+1]=Candidates.Get(id) end
print('profile,scenario,seed,policy,complete,missing,select,banish,reroll,freeze,draws,actions,stop,fingerprint')
local lastProfile
for _,s in ipairs(Corpus.All()) do
    if s.profileID~=lastProfile then
        io.stderr:write('Trials '..s.profileID..' seeds '..first..'..'..(first+count-1)..' policies '..#selected..'\n')
        io.stderr:flush();lastProfile=s.profileID
    end
    local prepared=Sim.Prepare(P,s)
    for seed=first,first+count-1 do
        s.seed=seed
        for _,candidate in ipairs(selected) do
            local r=Sim.Run(P,s,candidate,prepared)
            assert(r.stop=='COMPLETE' or r.stop=='PICKS_EXHAUSTED','trial did not settle: '..r.stop)
            print(table.concat({s.profileID,s.id,seed,candidate.id,r.complete and 1 or 0,r.missing,
                r.select,r.banish,r.reroll,r.freeze,r.draws,r.actions,r.stop,r.fingerprint},','))
        end
    end
end
