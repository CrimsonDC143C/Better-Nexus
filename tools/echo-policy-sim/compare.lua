-- Run from repository root: lua5.1 tools/echo-policy-sim/compare.lua [seed-count]
local P=dofile('tests/prototype/policy_adapter.lua');P.Load()
local Sim=dofile('tools/echo-policy-sim/simulator.lua')
local F=dofile('tools/echo-policy-sim/scenarios.lua')
local count=arg and arg[1] and assert(tonumber(arg[1]),'seed count must be numeric') or 200
assert(not (arg and arg[2]),'only one seed-count argument is accepted')
assert(count==math.floor(count) and count>=1 and count<=10000,'seed count must be 1..10000')
local lines={}
print('nexus-search-order/v1 HYPOTHETICAL; exclusion, weights and draw behavior UNPROVEN')
print('Independent weighted draws with replacement; action-conditioned common random streams; no DPS scoring')
print('example|order|seed|exclusion|stop|missing|select|banish|reroll|freeze|draws|actions|trace')
for _,name in ipairs({'saves-reroll','wastes-banish','family-exclusion-cost'}) do
    for _,order in ipairs({'reroll-first','banish-first'}) do
        local line=name..'|'..Sim.Line(Sim.Run(P,F.Example(name),order))
        lines[#lines+1]=line;print(line)
    end
end
print('profile|budget|order|runs|complete|missing|select|banish|reroll|freeze|draws|actions')
for _,exclusion in ipairs({'none','spell','family'}) do
    for _,budget in ipairs({'scarce','base','ample'}) do
        for _,order in ipairs({'reroll-first','banish-first'}) do
            local totals={complete=0,missing=0,select=0,banish=0,reroll=0,freeze=0,draws=0,actions=0}
            for seed=1,count do
                local s=F.Base(seed,exclusion)
                if budget=='scarce' then s.resources={banish=1,reroll=1,freeze=0} end
                if budget=='ample' then s.resources={banish=6,reroll=4,freeze=2} end
                local r=Sim.Run(P,s,order)
                assert(r.stop~='ACTION_LIMIT' and r.stop~='POLICY_WAIT','incomplete experiment')
                for k in pairs(totals) do totals[k]=totals[k]+(k=='complete' and (r.complete and 1 or 0) or r[k]) end
                lines[#lines+1]=budget..'|'..Sim.Line(r)
            end
            print(table.concat({exclusion,budget,order,count,totals.complete,totals.missing,totals.select,
                totals.banish,totals.reroll,totals.freeze,totals.draws,totals.actions},'|'))
        end
    end
end
print('SEEDS 1..'..count..' RUNS '..(#lines)..' FINGERPRINT '..P.Fingerprint(lines))
