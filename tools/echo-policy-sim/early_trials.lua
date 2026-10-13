local P=dofile('tests/prototype/policy_adapter.lua');P.Load('.')
local Sim=dofile('tools/echo-policy-sim/simulator.lua')
local C=dofile('tools/echo-policy-sim/candidates.lua')
local Early=dofile('tools/echo-policy-sim/early_banish.lua')
local corpus=dofile(arg[3]=='v3' and 'tools/echo-policy-sim/mechanics_corpus.lua' or 'tools/echo-policy-sim/corpus.lua').All()
local first,count=assert(tonumber(arg[1])),assert(tonumber(arg[2]))
assert(first>=1 and first==math.floor(first) and count>=1 and count<=10000 and count==math.floor(count))
local selected={Early.Build(C.Get('adaptive-0-settle')),C.Get('adaptive-0-settle'),C.Get('banish-family-safe-pair')}
print('profile,scenario,seed,policy,complete,missing,select,banish,reroll,freeze,draws,actions,stop,fingerprint')
local previous
for _,s in ipairs(corpus) do
    if previous~=s.profileID then io.stderr:write('Early test '..s.profileID..'\n');io.stderr:flush();previous=s.profileID end
    local prepared=Sim.Prepare(P,s)
    for seed=first,first+count-1 do
        s.seed=seed
        for _,candidate in ipairs(selected) do
            local r=Sim.Run(P,s,candidate,prepared)
            assert(r.stop=='COMPLETE' or r.stop=='PICKS_EXHAUSTED')
            print(table.concat({s.profileID,s.id,seed,candidate.id,r.complete and 1 or 0,r.missing,r.select,
                r.banish,r.reroll,r.freeze,r.draws,r.actions,r.stop,r.fingerprint},','))
        end
    end
end
