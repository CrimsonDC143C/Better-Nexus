local P=dofile('tests/prototype/policy_adapter.lua');P.Load('.')
local Fast=dofile('tools/echo-policy-sim/rollout_adapter.lua').Wrap(P)
local Sim=dofile('tools/echo-policy-sim/simulator.lua')
local C=dofile('tools/echo-policy-sim/candidates.lua')
local Corpus=dofile('tools/echo-policy-sim/corpus.lua')
local checks=0
for _,s in ipairs(Corpus.All()) do
    local prepared=Sim.Prepare(P,s)
    for _,id in ipairs({'released','banish-family-safe-pair'}) do
        local candidate=C.Get(id)
        for seed=31,33 do
            s.seed=seed
            local a=Sim.Run(P,s,candidate,prepared)
            local b=Sim.Run(Fast,s,candidate,prepared)
            assert(Sim.Line(a)==Sim.Line(b),'fast projection changed production behavior')
            checks=checks+1
        end
    end
end
local s=Corpus.All()[11] -- one-pick case: bounded repeat/safety test
local planner=C.Get('plan-16')
local a=Sim.Run(P,s,planner)
local b=Sim.Run(P,s,planner)
assert(Sim.Line(a)==Sim.Line(b),'planning is not deterministic')
assert(a.stop=='COMPLETE' or a.stop=='PICKS_EXHAUSTED')
print('PASS planning: '..checks..' complete fast/production parity runs and deterministic planner')
