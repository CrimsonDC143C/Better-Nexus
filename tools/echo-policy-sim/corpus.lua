-- Fixed, synthetic corpus. These are distinct workloads, not server captures.
local Corpus={version='rolling-corpus/v2'}
local workloads={
    {id='small-balanced',size=24,picks=8,targets=3,copies=1,b=3,r=2,f=2},
    {id='tight-copies',size=24,picks=6,targets=3,copies=2,b=6,r=3,f=2},
    {id='long-run',size=48,picks=30,targets=6,copies=2,b=8,r=4,f=4},
    {id='rare-targets',size=48,picks=18,targets=4,copies=2,b=8,r=4,f=3,rare=true},
    {id='quality-siblings',size=32,picks=14,targets=4,copies=2,b=8,r=4,f=3,siblings=true},
    {id='reroll-scarce',size=32,picks=14,targets=4,copies=2,b=10,r=1,f=3},
    {id='banish-scarce',size=32,picks=14,targets=4,copies=2,b=1,r=6,f=3},
    {id='freeze-only',size=24,picks=12,targets=3,copies=2,b=0,r=0,f=4},
    {id='already-partial',size=32,picks=8,targets=4,copies=2,b=5,r=3,f=2,partial=true},
    {id='large-pool',size=96,picks=35,targets=6,copies=2,b=10,r=6,f=4},
    {id='single-pick',size=24,picks=1,targets=1,copies=1,b=3,r=2,f=1},
    {id='impossible-completion',size=24,picks=3,targets=4,copies=1,b=5,r=3,f=2},
}
function Corpus.All()
    local out={}
    for _,exclusion in ipairs({'none','spell','family'}) do
        for _,unique in ipairs({false,true}) do
            local profile=exclusion..(unique and '-unique-capped' or '-replacement')
            for _,w in ipairs(workloads) do
                local s={id=w.id,profileID=profile,stream=Corpus.version..'/'..w.id,seed=1,
                    profile={version=2,banishExclusion=exclusion,uniqueOffers=unique,maxStacks=unique and 5 or nil},
                    picks=w.picks,resources={banish=w.b,reroll=w.r,freeze=w.f},allowFreeze=true,
                    families={},targets={},pool={},owned={}}
                for i=1,w.size do
                    local id=1000+i
                    s.families['echo'..i]={[0]=id}
                    s.pool[#s.pool+1]={spellId=id,weight=(w.rare and i<=w.targets) and 1 or 4}
                    if i<=w.targets then
                        s.targets[#s.targets+1]={spellId=id,stacks=w.copies}
                        if w.partial then s.owned[id]=1 end
                        if w.siblings then
                            s.families['echo'..i][1]=2000+i
                            s.pool[#s.pool+1]={spellId=2000+i,weight=8}
                        end
                    end
                end
                out[#out+1]=s
            end
        end
    end
    return out
end
return Corpus
