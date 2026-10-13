local P=dofile('tests/prototype/policy_adapter.lua');P.Load('.')
local Fast=dofile('tools/echo-policy-sim/rollout_adapter.lua').Wrap(P)
local Sim=dofile('tools/echo-policy-sim/simulator.lua')
local C=dofile('tools/echo-policy-sim/candidates.lua')
local data=dofile(assert(arg[4],'local generated catalog path required'))
local corpus=dofile('tools/echo-policy-sim/catalog_corpus.lua').All(data)
local first,count=tonumber(arg[1]),tonumber(arg[2])
assert(first and first>=1 and first==math.floor(first) and count and count>=1 and count<=10000 and count==math.floor(count),'valid seed range required')
assert(first+count<2147483647,'seed range too large')
local policies={}
for id in tostring(arg[3]):gmatch('[^,]+') do
    assert(id=='released' or id=='banish-family-safe-pair' or id=='adaptive-0-settle' or id=='reroll-pair','candidate not validated for catalog model')
    policies[#policies+1]=C.Get(id)
end
print('profile,scenario,seed,policy,complete,missing,select,banish,reroll,freeze,draws,actions,stop,fingerprint')
local last
for _,s in ipairs(corpus) do
    if last~=s.profileID then io.stderr:write('Catalog '..s.profileID..' seeds '..first..'..'..(first+count-1)..'\n');last=s.profileID end
    local prepared=Sim.Prepare(P,s)
    for seed=first,first+count-1 do
        s.seed=seed
        for _,policy in ipairs(policies) do
            local r=Sim.Run(Fast,s,policy,prepared)
            assert(r.stop=='COMPLETE' or r.stop=='PICKS_EXHAUSTED','unsettled catalog run: '..r.stop)
            print(table.concat({s.profileID,s.id,seed,policy.id,r.complete and 1 or 0,r.missing,r.select,
                r.banish,r.reroll,r.freeze,r.draws,r.actions,r.stop,r.fingerprint},','))
        end
    end
end
