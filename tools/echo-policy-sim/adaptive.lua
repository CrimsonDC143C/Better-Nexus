-- Model-aware lab heuristic. Weights and exclusion remain explicit hypotheses.
local A={}
local function Held(c) return c.isFrozen or c.isCarried or c.justFrozen end
function A.Build(id,reroll,banish,reserve,settleHeld)
    return {id=id,decide=function(P,input,context)
        local adjusted={};for k,v in pairs(input) do adjusted[k]=v end
        local need,missing,weight,familyWeight={},{},{},{}
        local totalNeed=0
        local groupExclusion=context.profile.banishExclusion=='family' or context.profile.banishExclusion=='group'
        for echo,count in pairs(input.plan.requestedCounts) do
            need[echo]=math.max(0,count-(input.owned.bySpell[echo] or 0));totalNeed=totalNeed+need[echo]
            if need[echo]>0 then missing[input.catalog.familyOf[echo]]=true end
        end
        for _,entry in ipairs(context.pool) do
            local family=input.catalog.familyOf[entry.spellId]
            local w=entry.weight
            if context.profile.version==3 then
                if (input.owned.byFamily[family] or 0)>0 then w=w*context.profile.selectFamilyBoost end
                if context.penalizedFamilies and context.penalizedFamilies[family] then w=w*context.profile.rerollFamilyPenalty end
            end
            weight[entry.spellId]=w
            familyWeight[family]=(familyWeight[family] or 0)+w
        end
        if reserve>0 and input.horizon>totalNeed*reserve then adjusted.allowBanish=false;adjusted.allowReroll=false end
        local candidate=context.profile.banishExclusion=='none' and reroll or banish
        local action=candidate.decide(P,adjusted,context)
        if action.type=='wait' then return action end
        local function Result(kind,index)
            return {type=kind,index=index,spellId=input.cards[index].spellId,planner=id,reason='Model-aware remaining-copy scarcity'}
        end
        local best,bestScore
        local heldWanted,unheldWanted={},{}
        for i,c in ipairs(input.cards) do
            if (need[c.spellId] or 0)>0 then
                local list=Held(c) and heldWanted or unheldWanted;list[#list+1]=i
            end
        end
        if action.type=='take' or action.type=='freeze' then
            local list=#unheldWanted>0 and unheldWanted or heldWanted
            for _,i in ipairs(list) do
                local c=input.cards[i]
                local eligible=action.type=='take'
                if action.type=='freeze' and not Held(c) and not c.isGuaranteed then
                    for _,j in ipairs(unheldWanted) do
                        if j~=i and (input.cards[j].spellId~=c.spellId or need[c.spellId]>=2) then eligible=true end
                    end
                end
                -- Copies per unit draw weight estimate replacement difficulty.
                local score=need[c.spellId]/(weight[c.spellId] or 0.000001)
                if eligible and (not bestScore or score>bestScore) then best,bestScore=i,score end
            end
            if best then return Result(action.type,best) end
        elseif action.type=='banish' then
            if settleHeld and #heldWanted>0 and #unheldWanted==0 then return Result('take',heldWanted[1]) end
            for i,c in ipairs(input.cards) do
                local family=input.catalog.familyOf[c.spellId]
                if not Held(c) and not c.isGuaranteed and (need[c.spellId] or 0)==0
                    and (not groupExclusion or not missing[family]) then
                    local score=groupExclusion and (familyWeight[family] or 0)
                        or context.profile.banishExclusion=='spell' and (weight[c.spellId] or 0) or 0
                    if not bestScore or score>bestScore then best,bestScore=i,score end
                end
            end
            if best then return Result('banish',best) end
            adjusted.allowBanish=false
            return candidate.decide(P,adjusted,context)
        end
        return action
    end}
end
return A
