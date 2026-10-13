-- Local catalog facts, synthetic fixed-character workloads, declared odds hypotheses.
local M=dofile('tools/echo-policy-sim/catalog_model.lua')
local C={version='catalog-corpus/v4'}
function C.All(data)
    local catalog=M.Catalog(data)
    local ids={};for id in pairs(catalog.rows) do ids[#ids+1]=id end;table.sort(ids)
    local out={}
    for _,exclusion in ipairs({'spell','group'}) do
        for _,dynamics in ipairs({{'neutral','any',1,1},{'any','any',2,0.5},{'product','product',2,0.5}}) do
            for _,lifetime in ipairs({'board','run'}) do
                for _,classBit in ipairs({1,4,128}) do
                    for _,tomes in ipairs({'none','all'}) do
                        local character={classBit=classBit,level=20,knownSpells={},disabledSpells={}}
                        if tomes=='all' then for _,row in pairs(catalog.rows) do
                            if row.requiredSpell>0 then character.knownSpells[row.requiredSpell]=true end
                        end end
                        local pool,eligible={},{}
                        for _,id in ipairs(ids) do if M.Eligible(catalog,id,character,{}) then
                            pool[#pool+1]={spellId=id,weight=1};eligible[#eligible+1]=id
                        end end
                        -- Stable selection independent of draw seeds or policy results.
                        table.sort(eligible,function(a,b)
                            local x,y=(a*8191)%104729,(b*8191)%104729
                            return x==y and a<b or x<y
                        end)
                        for _,w in ipairs({{id='two-targets',targets=2,copies=1,picks=40,b=6,r=4,f=3},
                            {id='six-copies',targets=3,copies=2,picks=70,b=12,r=8,f=4}}) do
                            local targets,groups={},{}
                            for _,id in ipairs(eligible) do
                                if not groups[catalog.familyOf[id]] and catalog.rows[id].maxStack>=w.copies then
                                    targets[#targets+1]={spellId=id,stacks=w.copies};groups[catalog.familyOf[id]]=true
                                    if #targets==w.targets then break end
                                end
                            end
                            assert(#targets==w.targets,'insufficient catalog targets')
                            local name='class'..classBit..'-tomes-'..tomes..'-'..w.id
                            out[#out+1]={id=name,profileID=exclusion..'-'..dynamics[1]..'-'..lifetime,
                                stream=C.version..'/'..name,seed=1,catalogData=data,targets=targets,pool=pool,
                                character=character,picks=w.picks,resources={banish=w.b,reroll=w.r,freeze=w.f},allowFreeze=true,
                                profile={version=4,banishExclusion=exclusion,uniqueOffers=true,capScope='spell',
                                    roleComposition=dynamics[2],selectFamilyBoost=dynamics[3],rerollFamilyPenalty=dynamics[4],
                                    rerollPenaltyLifetime=lifetime,rerollExcludeCurrent=true}}
                        end
                    end
                end
            end
        end
    end
    return out
end
return C
