-- All weights and mechanics below are synthetic assumptions, not server data.
local F={}
function F.Base(seed, exclusion)
    return {seed=seed or 1,profile={version=1,banishExclusion=exclusion or 'none'},picks=5,
        families={target={[0]=101,[1]=111},other={[0]=102},x={[0]=901},y={[0]=902},z={[0]=903},
            u={[0]=904},v={[0]=905}},
        targets={{spellId=101,stacks=2},{spellId=102,stacks=1}},
        board={{spellId=901},{spellId=902},{spellId=903}},resources={banish=3,reroll=2,freeze=1},
        allowFreeze=true,pool={{spellId=101,weight=1},{spellId=111,weight=1},{spellId=102,weight=1},
            {spellId=901,weight=4},{spellId=902,weight=4},{spellId=903,weight=4},
            {spellId=904,weight=1},{spellId=905,weight=1}}}
end
function F.Example(name)
    local s=F.Base()
    s.picks=1;s.targets={{spellId=101,stacks=1}}
    s.resources={banish=1,reroll=1,freeze=0}
    if name=='saves-reroll' then
        s.draws={banish={{101,101,101}},reroll={{901,902,903}}}
    elseif name=='wastes-banish' then
        s.draws={banish={{901,902,903}},reroll={{101,902,903}}}
    elseif name=='family-exclusion-cost' then
        s.profile.banishExclusion='family'
        s.board[1]={spellId=111}
        s.draws={banish={{901,902,903}}}
        -- Reroll-first retains the needed quality sibling in the pool.
        s.pool={{spellId=101,weight=1000000},{spellId=901,weight=1}}
    else error('unknown example') end
    return s
end
return F
