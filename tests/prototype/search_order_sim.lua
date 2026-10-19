-- Complete offline search-order experiments use the real production policy.
local P=dofile('tests/prototype/policy_adapter.lua'); P.Load()
local checks=0
local function check(value,message) assert(value,message); checks=checks+1 end
local catalog=P.Catalog({target={[0]=101},other={[0]=102},x={[0]=901},y={[0]=902},z={[0]=903}})
local plan=P.Plan(catalog,{{spellId=101,stacks=1}})
local function Input()
 return {catalog=catalog,plan=plan,horizon=1,cards={{spellId=901},{spellId=902},{spellId=903}},
  owned=P.Owned(catalog,{}),locked=P.Owned(catalog,{}),
  charges={trustworthy=true,banish=1,freeze=0,reroll=1},allowBanish=true,allowReroll=true,
  rollingPolicy='released'}
end
local defaults=Nexus.EchoWeaver.NEXUS_POLICY
check(P.Decide(Input()).type=='reroll','released profile control: Reroll precedes legal Banish')
local experiment={}
for k,v in pairs(defaults) do experiment[k]=v end
experiment.banishBeforeReroll=true
Nexus.EchoWeaver.NEXUS_POLICY=experiment
local action=P.Decide(Input())
Nexus.EchoWeaver.NEXUS_POLICY=defaults
check(action.type=='banish' and action.index==1,'opt-in Banish-first must replace the first legal unwanted offer before Reroll')
local function Experimental(input)
 Nexus.EchoWeaver.NEXUS_POLICY=experiment
 local ok,result=pcall(P.Decide,input)
 Nexus.EchoWeaver.NEXUS_POLICY=defaults
 assert(ok,result)
 return result
end
local input=Input();input.allowBanish=false
check(Experimental(input).type=='reroll','Banish permission respected')
input=Input();input.charges.banish=0
check(Experimental(input).type=='reroll','Banish resource respected')
input=Input();input.charges.trustworthy=false
check(Experimental(input).type~='banish','untrusted resource cannot Banish')
input=Input();input.pending=true
check(Experimental(input).type=='wait','pending action blocks search')
input=Input();input.ordinaryBoardAllowed=false
check(Experimental(input).type=='wait','Orb context blocks normal search')
input=Input();input.cards[1]={spellId=101}
check(Experimental(input).type=='take','needed offer wins over search')
input=Input();input.cards[1].isFrozen=true
check(Experimental(input).index~=1,'frozen offer protected')
input=Input();input.cards[1].isGuaranteed=true
check(Experimental(input).index~=1,'observed guaranteed offer protected')
input=Input();input.cards[1].isFrozen=true;input.cards[2].isFrozen=true
check(Experimental(input).type~='reroll','two frozen offers block Reroll')
local Sim=dofile('tools/echo-policy-sim/simulator.lua')
local F=dofile('tools/echo-policy-sim/scenarios.lua')
local function Pair(name)
 local s=F.Example(name)
 return Sim.Run(P,s,'reroll-first'),Sim.Run(P,s,'banish-first')
end
local a,b=Pair('saves-reroll')
check(a.complete and b.complete and a.reroll==1 and b.reroll==0 and b.banish==1,'Banish first can save a Reroll')
a,b=Pair('wastes-banish')
check(a.complete and b.complete and a.banish==0 and b.banish==1 and a.reroll==b.reroll,'Banish first can waste a Banish')
a,b=Pair('family-exclusion-cost')
check(a.complete and not b.complete,'unproven family exclusion can remove a needed quality sibling')
for _,exclusion in ipairs({'none','spell','family'}) do
 for seed=1,30 do
  for _,order in ipairs({'reroll-first','banish-first'}) do
   local s=F.Base(seed,exclusion)
   local r=Sim.Run(P,s,order)
   check(Sim.Line(r)==Sim.Line(Sim.Run(P,s,order)),'seeded run repeatability')
   check(r.actions==r.select+r.reroll+r.banish+r.freeze and r.select<=s.picks,'complete action accounting')
   for _,kind in ipairs({'banish','freeze','reroll'}) do
    check(r[kind]+r.remaining[kind]==s.resources[kind],'resource conservation')
   end
   check(s.board[1].spellId==901 and not s.owned and s.resources.banish==3,'input preserved')
   check(Nexus.EchoWeaver.NEXUS_POLICY==defaults,'policy options restored')
  end
 end
end
local s=F.Example('saves-reroll');s.maxActions=1
check(Sim.Run(P,s,'banish-first').stop=='ACTION_LIMIT','bounded execution does not claim completion')
s=F.Example('saves-reroll');s.draws.banish[1][1]=999
check(not pcall(Sim.Run,P,s,'banish-first'),'invalid scripted evidence fails')
check(Nexus.EchoWeaver.NEXUS_POLICY==defaults,'options restored on failure')
s=F.Example('saves-reroll');s.profile.banishExclusion='spell';s.pool={{spellId=901,weight=1}}
check(not pcall(Sim.Run,P,s,'banish-first'),'pool exhaustion fails instead of fabricating an offer')
s=F.Base();s.profile.version=99
check(not pcall(Sim.Run,P,s,'banish-first'),'unsupported mechanics version rejected')
check(P.Decide(Input()).type=='reroll','released profile still Reroll first after all experiments')
print('PASS search order policy and complete-run checks='..checks)
