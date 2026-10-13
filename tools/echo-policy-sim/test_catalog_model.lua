local P=dofile('tests/prototype/policy_adapter.lua');P.Load('.')
local M=dofile('tools/echo-policy-sim/catalog_model.lua')
local Sim=dofile('tools/echo-policy-sim/simulator.lua')
local C=dofile('tools/echo-policy-sim/candidates.lua')
local Fast=dofile('tools/echo-policy-sim/rollout_adapter.lua').Wrap(P)
local function Scenario()
    local s={seed=17,picks=3,profile={version=4,banishExclusion='group',uniqueOffers=true,
        capScope='spell',roleComposition='any',rerollExcludeCurrent=true,
        selectFamilyBoost=4,rerollFamilyPenalty=0.5,rerollPenaltyLifetime='run'},
        character={classBit=1,level=20,knownSpells={},disabledSpells={}},
        catalogData={schema='local-perk-catalog/v1',rows={}},
        resources={banish=1,reroll=1,freeze=1},allowFreeze=true,
        targets={{spellId=108,stacks=2}},pool={},board={{spellId=101},{spellId=102},{spellId=103}}}
    for id=101,110 do
        s.catalogData.rows[id]={maxStack=80,classMask=1,minLevel=1,quality=0,groupId=id,requiredSpell=0,roles={}}
        s.pool[#s.pool+1]={spellId=id,weight=1}
    end
    s.catalogData.rows[101].roles={'Tank','Melee DPS'}
    s.catalogData.rows[102].roles={'Tank'} -- same role, different quality group
    s.catalogData.rows[104].groupId=101;s.catalogData.rows[104].quality=1 -- same group, no roles
    s.catalogData.rows[105].roles={'Melee DPS'}
    return s
end
local s=Scenario();M.Validate(s)
local cat=M.Catalog(s.catalogData)
assert(cat.familyOf[101]==cat.familyOf[104] and cat.familyOf[101]~=cat.familyOf[102])
local ownedRoles=M.OwnedRoles(cat,{[101]=1})
assert(M.Weight(cat,{spellId=101,weight=1},s.profile,ownedRoles,{})==4)
assert(M.Weight(cat,{spellId=102,weight=1},s.profile,ownedRoles,{})==4)
assert(M.Weight(cat,{spellId=104,weight=1},s.profile,ownedRoles,{})==1)
s.profile.roleComposition='product'
assert(M.Weight(cat,{spellId=101,weight=1},s.profile,ownedRoles,{Tank=true})==8)
assert(M.Weight(cat,{spellId=101,weight=1},s.profile,ownedRoles,{Tank=true,['Melee DPS']=true})==4)
assert(M.Weight(cat,{spellId=101,weight=1},s.profile,M.OwnedRoles(cat,{[101]=80}),{})==16,'no per-stack accumulation')
for _,test in ipairs({{'classMask',0},{'classMask',2},{'minLevel',21},{'requiredSpell',9001}}) do
    local t=Scenario();t.catalogData.rows[101][test[1]]=test[2]
    assert(not M.Eligible(M.Catalog(t.catalogData),101,t.character,{}))
end
s=Scenario();s.catalogData.rows[101].requiredSpell=9001;s.character.knownSpells[9001]=true
cat=M.Catalog(s.catalogData);assert(M.Eligible(cat,101,s.character,{}))
s.character.disabledSpells[9001]=true;assert(not M.Eligible(cat,101,s.character,{}))
s=Scenario();s.catalogData.rows[101].maxStack=1;cat=M.Catalog(s.catalogData)
assert(not M.Eligible(cat,101,s.character,{[101]=1}))
assert(M.Eligible(cat,102,s.character,{[102]=79}) and not M.Eligible(cat,102,s.character,{[102]=80}))
local function Script(actions,inspect)
    local at=0
    return {id='test-v4',decide=function(_,input,view)
        at=at+1;if inspect then inspect(input,view,at) end
        local kind,index=unpack(actions[at] or {'take',1})
        return {type=kind,index=index,spellId=index and input.cards[index].spellId}
    end}
end
-- Full-run group exclusion removes the quality sibling, not another role member.
s=Scenario();s.draws={banish={{105}},reroll={{106,107,108}},select={{108,109,110},{108,109,110}}}
local r=Sim.Run(P,s,Script({{'banish',1},{'reroll'},{'take',3},{'take',1}},function(input,view,at)
    assert(view.seed==nil and view.draws==nil and view.penalizedFamilies==nil)
    if at==2 then
        local ids={};for _,entry in ipairs(view.pool) do ids[entry.spellId]=true end
        assert(not ids[101] and not ids[104] and ids[102],'role was conflated with group')
    end
end))
assert(r.complete and r.banish==1 and r.reroll==1 and r.select==2)
-- Role penalties come from all observed offers, not their quality groups.
s=Scenario();s.draws={reroll={{104,105,106}},select={{107,108,109},{108,109,110}}}
Sim.Run(P,s,Script({{'reroll'},{'take',1},{'take',2},{'take',1}},function(_,view,at)
    if at==2 then
        local weights={};for _,entry in ipairs(view.pool) do weights[entry.spellId]=entry.weight end
        assert(weights[104]==1 and weights[105]==0.5,'wrong role penalty identity')
    end
end))
-- Independent first-slot calibration: owned 101 boosts 101,102,105. 104 is not boosted.
local hits=0
for seed=1,3000 do
    s=Scenario();s.board=nil;s.owned={[101]=1};s.seed=seed
    Sim.Run(P,s,Script({},function(input,_,at) if at==1 and input.cards[1].spellId==102 then hits=hits+1 end end))
end
assert(math.abs(hits/3000-4/19)<0.025,'role-weight sampling calibration')
-- Production projection parity on complete runs, not only isolated decisions.
for seed=1,30 do for _,id in ipairs({'released','banish-family-safe-pair','adaptive-0-settle','reroll-pair'}) do
    s=Scenario();s.board=nil;s.seed=seed
    local a=Sim.Run(P,s,C.Get(id));local b=Sim.Run(Fast,s,C.Get(id))
    assert(Sim.Line(a)==Sim.Line(b),'full/fast production seam diverged')
end end
for _,mutate in ipairs({function(t)t.profile.roleComposition=nil end,function(t)t.profile.maxStacks=5 end,
    function(t)t.character.classBit=3 end,function(t)t.targets[1].stacks=81 end,
    function(t)t.owned={[101]=81} end,function(t)t.profile.banishExclusion='family' end}) do
    s=Scenario();mutate(s);assert(not pcall(Sim.Run,P,s,C.Get('released')),'invalid scenario accepted')
end
print('PASS v4: roles/groups, class/level/prerequisites/caps, complete runs, 120 production parity runs, calibration '..hits..'/3000, negative cases')
