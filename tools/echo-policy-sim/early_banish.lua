-- Exact-reference-inspired challenger. Only declared run-long exclusion can
-- justify spending a Banish before selecting a currently useful offer.
local E={}
local function Held(c) return c.isFrozen or c.isCarried or c.justFrozen end
function E.Build(base)
    return {id='early-banish',decide=function(P,input,context)
        local action=base.decide(P,input,context)
        if action.type~='take' or context.profile.banishExclusion=='none' or not input.allowBanish
            or not input.charges.trustworthy or input.charges.banish<=0 or input.horizon<=1 then return action end
        local needs,families,total={},{},0
        for echo,count in pairs(input.plan.requestedCounts) do
            needs[echo]=math.max(0,count-(input.owned.bySpell[echo] or 0))
            total=total+needs[echo]
            if needs[echo]>0 then families[input.catalog.familyOf[echo]]=true end
        end
        if total<=1 or (needs[action.spellId] or 0)==0 then return action end
        local mass={}
        for _,entry in ipairs(context.pool) do
            local family=input.catalog.familyOf[entry.spellId]
            local key=context.profile.banishExclusion=='family' and family or entry.spellId
            local weight=entry.weight
            if context.profile.version==3 then
                if (input.owned.byFamily[family] or 0)>0 then weight=weight*context.profile.selectFamilyBoost end
                if context.penalizedFamilies and context.penalizedFamilies[family] then weight=weight*context.profile.rerollFamilyPenalty end
            end
            mass[key]=(mass[key] or 0)+weight
        end
        local best,bestMass=nil,0
        for i,c in ipairs(input.cards) do
            local family=input.catalog.familyOf[c.spellId]
            local key=context.profile.banishExclusion=='family' and family or c.spellId
            if not Held(c) and not c.isGuaranteed and (needs[c.spellId] or 0)==0
                and (context.profile.banishExclusion~='family' or not families[family])
                and (mass[key] or 0)>bestMass then best,bestMass=i,mass[key] end
        end
        if best then return {type='banish',index=best,spellId=input.cards[best].spellId,
            planner='early-banish',reason='Test earlier safe run-long exclusion before a useful selection'} end
        return action
    end}
end
return E
