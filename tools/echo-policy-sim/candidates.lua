-- Offline policy candidates. No future draws, seed or result is an input.
-- The released control and every search decision use the actual planner.
-- New pair-freeze and target-family protection rules remain lab-only.
local C={}
local function Frozen(c) return c.isFrozen or c.isCarried or c.justFrozen end
local function Copy(t) local out={} for k,v in pairs(t) do out[k]=v end return out end
local function Build(id,order,freeze,reserve,familySafe,oneBanish)
    local spec={id=id,order=order,freeze=freeze,reserve=reserve or 0,
        familySafe=familySafe==true,oneBanish=oneBanish==true}
    local function Decide(P,input,context)
        local adjusted=Copy(input)
        -- This historical comparison varies the released planner's action
        -- order; current runtime defaults to a separate adaptive profile.
        adjusted.rollingPolicy='released'
        local remaining,needed,families={},0,{}
        for echo,count in pairs(input.plan.requestedCounts) do
            remaining[echo]=math.max(0,count-(input.owned.bySpell[echo] or 0))
            needed=needed+remaining[echo]
            families[input.catalog.familyOf[echo]]=true
        end
        local wanted,held={},0
        for i,c in ipairs(input.cards) do
            if Frozen(c) then held=held+1 end
            if (remaining[c.spellId] or 0)>0 then wanted[#wanted+1]=i end
        end
        if reserve and input.horizon>needed*reserve then
            adjusted.allowBanish=false;adjusted.allowReroll=false
        end
        if oneBanish and context.banishesSinceReroll>=1 and input.charges.reroll>0 then
            adjusted.allowBanish=false
        end
        if freeze~='release' then adjusted.allowFreeze=false end
        local options=Copy(Nexus.EchoWeaver.NEXUS_POLICY)
        options.banishBeforeReroll=order=='banish'
            or order=='abundant' and input.charges.banish>input.charges.reroll*(3-held)
        local original=Nexus.EchoWeaver.NEXUS_POLICY
        Nexus.EchoWeaver.NEXUS_POLICY=options
        local ok,action=pcall(P.Decide,adjusted)
        Nexus.EchoWeaver.NEXUS_POLICY=original
        assert(ok,action)
        if action.type=='wait' then return action end
        -- Preserve two useful offers before selection, without spending a
        -- Banish merely to make Freeze available. Do not preserve surplus
        -- copies or Freeze when only one pick remains.
        if freeze=='pair' and action.type=='take' and input.allowFreeze and input.charges.trustworthy
            and input.charges.freeze>0 and input.horizon>=2 and held==0 and #wanted>=2 then
            for _,i in ipairs(wanted) do
                local card=input.cards[i]
                for _,j in ipairs(wanted) do
                    if i~=j and not card.isGuaranteed and card.freezeEligible~=false
                        and (card.spellId~=input.cards[j].spellId or remaining[card.spellId]>=2) then
                        return {type='freeze',index=i,spellId=card.spellId,planner=id,reason='Preserve a second needed offer'}
                    end
                end
            end
        end
        if familySafe and action.type=='banish' and families[input.catalog.familyOf[action.spellId]] then
            for i,card in ipairs(input.cards) do
                if not Frozen(card) and not card.isGuaranteed and card.banishEligible~=false
                    and not families[input.catalog.familyOf[card.spellId]] then
                    return {type='banish',index=i,spellId=card.spellId,planner=id,reason='Protect Wishlist quality siblings'}
                end
            end
            adjusted.allowBanish=false
            original=Nexus.EchoWeaver.NEXUS_POLICY
            Nexus.EchoWeaver.NEXUS_POLICY=options
            ok,action=pcall(P.Decide,adjusted)
            Nexus.EchoWeaver.NEXUS_POLICY=original
            assert(ok,action)
        end
        return action
    end
    return {id=id,decide=Decide,spec=spec,needsPool=false}
end
C.all={
    Build('released','reroll','release'),
    Build('banish-first','banish','release'),
    Build('reroll-no-freeze','reroll','none'),
    Build('banish-no-freeze','banish','none'),
    Build('reroll-pair','reroll','pair'),
    Build('banish-pair','banish','pair'),
    Build('banish-one-pair','banish','pair',nil,false,true),
    Build('abundant-pair','abundant','pair'),
    Build('reroll-reserve2-pair','reroll','pair',2),
    Build('banish-reserve2-pair','banish','pair',2),
    Build('abundant-reserve2-pair','abundant','pair',2),
    Build('reroll-reserve4-pair','reroll','pair',4),
    Build('banish-reserve4-pair','banish','pair',4),
    Build('banish-family-safe-pair','banish','pair',nil,true),
    Build('abundant-family-safe-pair','abundant','pair',nil,true),
}
function C.Get(id)
    for _,candidate in ipairs(C.all) do if candidate.id==id then return candidate end end
    if id=='plan-16' or id=='plan-64' then
        return dofile('tools/echo-policy-sim/planning.lua').Build(id,tonumber(id:match('%d+')),C.Get('banish-family-safe-pair'))
    end
    local reserve,settle=id:match('^adaptive%-(%d+)%-(%a+)$')
    if reserve and (settle=='hold' or settle=='settle') then
        assert(tonumber(reserve)<=4,'adaptive reserve must be 0..4')
        return dofile('tools/echo-policy-sim/adaptive.lua').Build(id,C.Get('reroll-pair'),C.Get('banish-pair'),tonumber(reserve),settle=='settle')
    end
    error('unknown candidate: '..tostring(id))
end
return C
