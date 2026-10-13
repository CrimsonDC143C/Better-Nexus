local P=dofile('tests/prototype/policy_adapter.lua');P.Load()
local Sim=dofile('tools/echo-policy-sim/simulator.lua')
local C=dofile('tools/echo-policy-sim/candidates.lua')
local Corpus=dofile('tools/echo-policy-sim/corpus.lua')
local Random=dofile('tools/echo-policy-sim/random.lua')
local checks=0
local function Check(ok,why) assert(ok,why);checks=checks+1 end
local s={seed=1,profile={version=2,banishExclusion='none'},picks=1,
    families={a={[0]=1},b={[0]=2},c={[0]=3},d={[0]=4}},targets={{spellId=1,stacks=1}},
    pool={{spellId=1,weight=1},{spellId=2,weight=1},{spellId=3,weight=1},{spellId=4,weight=1}},resources={}}
local prepared=Sim.Prepare(P,s)
local successes=0
for seed=1,5000 do
    s.seed=seed
    local r=Sim.Run(P,s,C.Get('released'),prepared)
    successes=successes+(r.complete and 1 or 0)
end
Check(math.abs(successes/5000-(1-0.75^3))<0.025,'initial three-draw probability calibration')
s.profile.uniqueOffers=true
successes=0
for seed=1,5000 do
    s.seed=seed;local r=Sim.Run(P,s,C.Get('released'),prepared)
    successes=successes+(r.complete and 1 or 0)
end
Check(math.abs(successes/5000-0.75)<0.025,'weighted-without-replacement calibration')
local seenSeeds={}
for _,scenario in ipairs(Corpus.All()) do
    local cache=Sim.Prepare(P,scenario)
    for _,candidate in ipairs(C.all) do
        local a=Sim.Run(P,scenario,candidate,cache)
        local b=Sim.Run(P,scenario,candidate,cache)
        Check(Sim.Line(a)==Sim.Line(b),'repeatability '..scenario.id..candidate.id)
        Check(a.actions==a.select+a.banish+a.reroll+a.freeze,'action accounting')
        Check(a.stop=='COMPLETE' or a.stop=='PICKS_EXHAUSTED','settlement')
        for _,resource in ipairs({'banish','reroll','freeze'}) do
            Check(a[resource]+a.remaining[resource]==scenario.resources[resource],'resource conservation')
        end
    end
    local control=Sim.Run(P,scenario,'reroll-first',cache)
    Check(Sim.Line(control):gsub('reroll%-first','released')==Sim.Line(Sim.Run(P,scenario,C.Get('released'),cache)),
        'released control is the production planner')
end
local defaults=Nexus.EchoWeaver.NEXUS_POLICY
local catalog=P.Catalog({target={[0]=1,[1]=11},second={[0]=2},filler={[0]=3}})
local function Input()
    return {catalog=catalog,plan=P.Plan(catalog,{{spellId=1,stacks=1},{spellId=2,stacks=1}}),
        owned=P.Owned(catalog,{}),cards={{spellId=1},{spellId=2},{spellId=3}},horizon=2,
        charges={trustworthy=true,banish=0,reroll=1,freeze=1},allowFreeze=true,allowBanish=true,allowReroll=true}
end
local view={banishesSinceReroll=0}
local pair=C.Get('banish-pair')
Check(pair.decide(P,Input(),view).type=='freeze','pair Freeze does not require a Banish')
local input=Input();input.pending=true
Check(pair.decide(P,input,view).type=='wait','pending guard')
input=Input();input.ordinaryBoardAllowed=false
Check(pair.decide(P,input,view).type=='wait','Orb guard')
input=Input();input.allowFreeze=false
Check(pair.decide(P,input,view).type=='take','Freeze permission')
input=Input();input.cards[2].spellId=1
Check(pair.decide(P,input,view).type=='take','no surplus duplicate Freeze')
input=Input();input.cards[1].isGuaranteed=true;input.cards[2].isGuaranteed=true
Check(pair.decide(P,input,view).type=='take','no protected Freeze')
input=Input();input.cards={{spellId=11},{spellId=3},{spellId=3}};input.charges.banish=2
local safe=C.Get('banish-family-safe-pair').decide(P,input,view)
Check(safe.type=='banish' and safe.spellId==3,'quality siblings protected')
local spy={id='observation-only',decide=function(adapter,input,view)
    Check(view.seed==nil and view.draws==nil and view.result==nil and view.Draw==nil,'no future oracle')
    for key in pairs(view) do Check(key=='profile' or key=='pool' or key=='banishesSinceReroll','bounded candidate input') end
    return adapter.Decide(input)
end}
Sim.Run(P,Corpus.All()[1],spy)
Check(Nexus.EchoWeaver.NEXUS_POLICY==defaults,'global options restored')
Check(Random.Uniform(71,'a',1,1)==Random.Uniform(71,'a',1,1),'random repeatability')
Check(Random.Uniform(71,'a',1,1)~=Random.Uniform(71,'b',1,1),'stream separation')
print('PASS policy lab checks='..checks..' calibration and 72 workloads x 15 candidates')
