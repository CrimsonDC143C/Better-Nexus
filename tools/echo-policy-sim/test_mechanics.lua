local P=dofile('tests/prototype/policy_adapter.lua');P.Load('.')
local Sim=dofile('tools/echo-policy-sim/simulator.lua')
local function Scenario()
    local s={seed=1,picks=2,profile={version=3,banishExclusion='spell',rerollExcludeCurrent=true,
        selectFamilyBoost=2,rerollFamilyPenalty=0.5,rerollPenaltyLifetime='board'},
        resources={reroll=1},families={a={[0]=1001},b={[0]=1002},c={[0]=1003},d={[0]=1004},e={[0]=1005},f={[0]=1006}},
        targets={{spellId=1006,stacks=2}},pool={},board={{spellId=1001},{spellId=1002},{spellId=1003}}}
    for i=1,6 do s.pool[i]={spellId=1000+i,weight=1} end
    return s
end
local function Scripted(actions,inspect)
    local at=0
    return {id='mechanics-test',decide=function(_,input)
        at=at+1;if inspect then inspect(input,at) end
        local kind,index=unpack(actions[at] or {'take',1})
        return {type=kind,index=index,spellId=index and input.cards[index].spellId}
    end}
end
local checks=0
for seed=1,100 do
    local s=Scenario();s.seed=seed
    Sim.Run(P,s,Scripted({{'reroll'},{'take',1},{'take',1}},function(input,at)
        if at==2 then for _,c in ipairs(input.cards) do assert(c.spellId>1003,'Reroll repeated an old offer');checks=checks+1 end end
    end))
end
local s=Scenario();s.draws={reroll={{1004,1005,1006}},select={{1001,1002,1003}}}
Sim.Run(P,s,Scripted({{'reroll'},{'take',1},{'take',1}})) -- next selection can draw old IDs
s=Scenario();s.draws={reroll={{1001,1005,1006}}}
assert(not pcall(Sim.Run,P,s,Scripted({{'reroll'}})),'scripted forbidden draw accepted')
s=Scenario();s.profile.selectFamilyBoost=nil
assert(not pcall(Sim.Run,P,s,Scripted({{'take',1}})),'implicit mechanics accepted')
s=Scenario();s.profile.version=2
assert(not pcall(Sim.Run,P,s,Scripted({{'take',1}})),'v3 flags silently ignored')
s=Scenario();s.board[1].isFrozen=true;s.board[2].isFrozen=true
assert(not pcall(Sim.Run,P,s,Scripted({{'reroll'}})),'two-held Reroll accepted')
-- Analytic initial draw: one owned family has weight 4, five others weight 1.
-- Compare first-slot frequency to 4/9 with independent fixed sample seeds.
local hits=0
for seed=1,6000 do
    s=Scenario();s.seed=seed;s.board=nil;s.owned={[1001]=1};s.profile.selectFamilyBoost=4
    Sim.Run(P,s,Scripted({{'take',1},{'take',1}},function(input,at)
        if at==1 and input.cards[1].spellId==1001 then hits=hits+1 end
    end))
end
assert(math.abs(hits/6000-4/9)<0.025,'selection boost calibration failed')
for _,lifetime in ipairs({'board','run'}) do
    local afterReroll,afterSelect=0,0
    for seed=1,6000 do
        s=Scenario();s.seed=seed;s.profile.selectFamilyBoost=1
        s.profile.rerollFamilyPenalty=0.25;s.profile.rerollPenaltyLifetime=lifetime
        s.families.a[1]=1004;s.families.d=nil
        Sim.Run(P,s,Scripted({{'reroll'},{'take',1},{'take',1}},function(input,at)
            if at==2 and input.cards[1].spellId==1004 then afterReroll=afterReroll+1 end
        end))
        s.draws={reroll={{1005,1005,1005}}}
        Sim.Run(P,s,Scripted({{'reroll'},{'take',1},{'take',1}},function(input,at)
            if at==3 and input.cards[1].spellId==1004 then afterSelect=afterSelect+1 end
        end))
    end
    assert(math.abs(afterReroll/6000-1/9)<0.02,'family penalty calibration failed')
    assert(math.abs(afterSelect/6000-(lifetime=='board' and 1/6 or 1/12))<0.02,'penalty lifetime failed')
end
assert(#dofile('tools/echo-policy-sim/mechanics_corpus.lua').All()==864)
print('PASS v3 mechanics: exclusion, expiry, guards, explicit profiles; boost '..hits..'/6000; '..checks..' checked offers')
