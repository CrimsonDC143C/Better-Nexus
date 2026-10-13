-- Lab-only rollout improvement. Samples are generated from observed state;
-- they are independent of the executor seed and its future draws.
local Sim=dofile('tools/echo-policy-sim/simulator.lua')
local Fast=dofile('tools/echo-policy-sim/rollout_adapter.lua')
local Planning={}
local function Held(c) return c.isFrozen or c.isCarried or c.justFrozen end
function Planning.Build(id,samples,base)
    local preparedCache=setmetatable({},{__mode='k'})
    local fastAdapter
    return {id=id,decide=function(P,input,context)
        local original=base.decide(P,input,context)
        if original.type=='wait' then return original end
        local remaining,wanted={},{}
        for echo,count in pairs(input.plan.requestedCounts) do
            remaining[echo]=math.max(0,count-(input.owned.bySpell[echo] or 0))
        end
        local actions,seen={},{}
        local function Add(kind,index)
            local key=kind..':'..tostring(index)
            if not seen[key] then
                seen[key]=true
                actions[#actions+1]={type=kind,index=index,spellId=index and input.cards[index].spellId,
                    planner=id,reason='Observation-only complete-run rollout'}
            end
        end
        Add(original.type,original.index)
        local held=0
        for i,c in ipairs(input.cards) do
            if Held(c) then held=held+1 end
            if (remaining[c.spellId] or 0)>0 then wanted[#wanted+1]=i end
        end
        -- This bounded planner is not an exhaustive solver. Keep the real
        -- incumbent plus useful selections, useful preservation, and search.
        for _,i in ipairs(wanted) do Add('take',i) end
        if #wanted==0 then
            for i=1,3 do Add('take',i) end -- Save charges by spending a pick.
        end
        for i,c in ipairs(input.cards) do
            if not Held(c) and not c.isGuaranteed then
                if input.allowBanish and input.charges.banish>0 and (remaining[c.spellId] or 0)==0 then
                    local safe=true
                    if context.profile.banishExclusion=='family' then
                        for echo,need in pairs(remaining) do
                            if need>0 and input.catalog.familyOf[echo]==input.catalog.familyOf[c.spellId] then safe=false end
                        end
                    end
                    if safe then Add('banish',i) end
                end
                if input.allowFreeze and input.charges.freeze>0 and input.horizon>1
                    and (remaining[c.spellId] or 0)>0 and held<2 then Add('freeze',i) end
            end
        end
        if input.allowReroll and input.charges.reroll>0 and held<2 then Add('reroll') end
        if #actions==1 then return original end
        fastAdapter=fastAdapter or Fast.Wrap(P)
        local prepared=preparedCache[input.plan]
        if not prepared then
            local families,targets={},{}
            for echo,row in pairs(input.catalog.rows) do
                local family=input.catalog.familyOf[echo]
                families[family]=families[family] or {}
                families[family][row.quality or 0]=echo
            end
            for echo,count in pairs(input.plan.requestedCounts) do targets[#targets+1]={spellId=echo,stacks=count} end
            prepared={catalog=input.catalog,plan=input.plan,families=families,targets=targets}
            preparedCache[input.plan]=prepared
        end
        local tokens={input.horizon,input.charges.banish,input.charges.reroll,input.charges.freeze}
        for _,c in ipairs(input.cards) do
            tokens[#tokens+1]=c.spellId;tokens[#tokens+1]=Held(c) and 1 or 0
        end
        local ids={};for echo in pairs(input.owned.bySpell) do ids[#ids+1]=echo end;table.sort(ids)
        for _,echo in ipairs(ids) do tokens[#tokens+1]=echo;tokens[#tokens+1]=input.owned.bySpell[echo] end
        local hash=tonumber(P.Fingerprint({table.concat(tokens,':')}),16)
        local scenario={profile=context.profile,pool=context.pool,board=input.cards,owned=input.owned.bySpell,
            picks=input.horizon,resources=input.charges,allowBanish=input.allowBanish,allowReroll=input.allowReroll,
            allowFreeze=input.allowFreeze,families=prepared.families,targets=prepared.targets,stream='planning/v1',
            penalizedFamilies=context.penalizedFamilies}
        local best,bestValue=original,nil
        for _,action in ipairs(actions) do
            local value={0,0,0}
            for sample=1,samples do
                scenario.seed=(hash+sample*7919)%2147483646+1
                local first=true
                local rollout={id='planning-continuation',needsPool=false,decide=function(adapter,observation,view)
                    if first then first=false;return action end
                    return base.decide(adapter,observation,view)
                end}
                local result=Sim.Run(fastAdapter,scenario,rollout,prepared,{noTrace=true})
                assert(result.stop=='COMPLETE' or result.stop=='PICKS_EXHAUSTED','unsettled planning rollout')
                value[1]=value[1]+(result.complete and 1 or 0)
                value[2]=value[2]-result.missing
                value[3]=value[3]-result.banish-result.reroll-result.freeze
            end
            local better=not bestValue
            if bestValue then
                for i=1,3 do if value[i]~=bestValue[i] then better=value[i]>bestValue[i];break end end
            end
            if better then best,bestValue=action,value end
        end
        return best
    end}
end
return Planning
