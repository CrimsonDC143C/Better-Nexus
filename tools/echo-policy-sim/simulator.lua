-- Synthetic executor around the real Nexus.Policy.Decide path.
-- NOT a server model, live adapter, or Orbweaver Automation Run implementation.
local Sim = {schema='nexus-search-order/v1'}
local Random=dofile('tools/echo-policy-sim/random.lua')
local CatalogModel=dofile('tools/echo-policy-sim/catalog_model.lua')
local function Copy(value)
    if type(value) ~= 'table' then return value end
    local out = {}
    for k,v in pairs(value) do out[k] = Copy(v) end
    return out
end
local function Integer(value, name, minimum)
    assert(type(value)=='number' and value<math.huge and value==math.floor(value) and value >= minimum,
        name..' must be an integer >= '..minimum)
    return value
end
function Sim.Prepare(adapter,scenario)
    local catalog=scenario.profile.version==4 and CatalogModel.Catalog(scenario.catalogData) or adapter.Catalog(scenario.families)
    return {catalog=catalog,plan=adapter.Plan(catalog,scenario.targets),families=scenario.families,targets=scenario.targets,catalogData=scenario.catalogData}
end
local function Frozen(card)
    return card and (card.isFrozen or card.isCarried or card.justFrozen)
end
function Sim.Run(adapter, scenario, order, prepared, options)
    local candidate=type(order)=='table' and order or nil
    assert(candidate and type(candidate.id)=='string' and type(candidate.decide)=='function'
        or order=='reroll-first' or order=='banish-first', 'unknown search order')
    if prepared then
        assert(prepared.families==scenario.families and prepared.targets==scenario.targets and prepared.catalogData==scenario.catalogData,'prepared scenario mismatch')
    end
    local s = {}
    for key,value in pairs(scenario) do s[key]=value end
    s.owned=Copy(scenario.owned);s.board=Copy(scenario.board)
    assert(s.profile and (s.profile.version==1 or s.profile.version==2 or s.profile.version==3 or s.profile.version==4), 'versioned mechanics profile required')
    local realCatalog=s.profile.version==4
    local enriched=s.profile.version>=3
    if realCatalog then CatalogModel.Validate(s) end
    if enriched then
        assert(type(s.profile.rerollExcludeCurrent)=='boolean','explicit Reroll exclusion required')
        assert(type(s.profile.selectFamilyBoost)=='number' and s.profile.selectFamilyBoost>=1
            and s.profile.selectFamilyBoost<math.huge,'explicit finite selection boost required')
        assert(type(s.profile.rerollFamilyPenalty)=='number' and s.profile.rerollFamilyPenalty>0
            and s.profile.rerollFamilyPenalty<=1,'explicit family penalty in (0,1] required')
        assert(s.profile.rerollPenaltyLifetime=='board' or s.profile.rerollPenaltyLifetime=='run','explicit penalty lifetime required')
    else
        assert(s.profile.rerollExcludeCurrent==nil and s.profile.selectFamilyBoost==nil
            and s.profile.rerollFamilyPenalty==nil and s.profile.rerollPenaltyLifetime==nil,'v3 mechanics require profile version 3')
    end
    local exclusion = s.profile.banishExclusion
    assert(exclusion=='none' or exclusion=='spell' or exclusion=='family' or realCatalog and exclusion=='group', 'unknown exclusion assumption')
    Integer(s.seed, 'seed', 1)
    Integer(s.picks, 'picks', 1)
    local cap = Integer(s.maxActions or 1000, 'maxActions', 1)
    local catalog = prepared and prepared.catalog or (realCatalog and CatalogModel.Catalog(s.catalogData) or adapter.Catalog(s.families))
    local plan = prepared and prepared.plan or adapter.Plan(catalog,s.targets)
    local owned, board, excluded = s.owned or {}, s.board or {}, {}
    assert((s.profile.version>=2 and not s.board) or #board==3, 'three initial offers required')
    for id,count in pairs(owned) do
        assert(catalog.rows[id],'owned ID outside catalog');Integer(count,'owned copies',0)
        if realCatalog then assert(count<=catalog.rows[id].maxStack,'owned copies exceed catalog cap') end
    end
    for _,card in ipairs(board) do assert(catalog.rows[card.spellId], 'initial offer outside catalog') end
    if s.profile.maxStacks then Integer(s.profile.maxStacks,'maxStacks',1) end
    local charges = {trustworthy=true,banish=0,reroll=0,freeze=0}
    for _,name in ipairs({'banish','reroll','freeze'}) do
        charges[name]=Integer((s.resources or {})[name] or 0,name,0)
    end
    local pool = assert(s.pool, 'explicit synthetic pool required')
    assert(#pool>0, 'empty pool')
    local seen = {}
    for _,entry in ipairs(pool) do
        assert(catalog.rows[entry.spellId], 'pool entry outside catalog')
        assert(not seen[entry.spellId], 'duplicate pool entry')
        seen[entry.spellId]=true
        Integer(entry.weight, 'synthetic draw weight', 1)
    end
    local r = {schema=realCatalog and 'nexus-policy-lab/v4' or enriched and 'nexus-policy-lab/v3' or s.profile.version==2 and 'nexus-policy-lab/v2' or Sim.schema,
        evidence='HYPOTHETICAL',profile=Copy(s.profile),seed=s.seed,
        order=candidate and candidate.id or order,select=0,banish=0,reroll=0,freeze=0,
        draws=0,actions=0,trace={},owned=owned}
    local function Missing()
        local missing=0
        for id,n in pairs(plan.requestedCounts) do missing=missing+math.max(0,n-(owned[id] or 0)) end
        return missing
    end
    local function Key(id)
        return (exclusion=='family' or exclusion=='group') and catalog.familyOf[id] or id
    end
    local ownedFamilies,penalizedFamilies,temporaryExcluded={},Copy(s.penalizedFamilies or {}),{}
    if realCatalog then
        assert(s.penalizedFamilies==nil,'v4 role penalties must use penalizedRoles')
        penalizedFamilies=Copy(s.penalizedRoles or {})
    end
    for id,count in pairs(owned) do if count>0 then ownedFamilies[catalog.familyOf[id]]=true end end
    if realCatalog then ownedFamilies=CatalogModel.OwnedRoles(catalog,owned) end
    local function Weight(entry)
        if realCatalog then return CatalogModel.Weight(catalog,entry,s.profile,ownedFamilies,penalizedFamilies) end
        local weight=entry.weight
        if enriched then
            local family=catalog.familyOf[entry.spellId]
            if ownedFamilies[family] then weight=weight*s.profile.selectFamilyBoost end
            if penalizedFamilies[family] then weight=weight*s.profile.rerollFamilyPenalty end
        end
        return weight
    end
    -- Separate action-conditioned streams keep the kth Reroll's variates
    -- identical across policies, regardless of preceding Banishes.
    local salts={select=104729,banish=130363,reroll=155921}
    local function Eligible(id,slot)
        if excluded[Key(id)] then return false end
        if temporaryExcluded[id] then return false end
        if realCatalog and not CatalogModel.Eligible(catalog,id,s.character,owned) then return false end
        if s.profile.maxStacks and (owned[id] or 0)>=s.profile.maxStacks then return false end
        if s.profile.uniqueOffers then
            for other=1,3 do if other~=slot and board[other] and board[other].spellId==id then return false end end
        end
        return true
    end
    if realCatalog then
        for id,count in pairs(plan.requestedCounts) do
            assert(count<=catalog.rows[id].maxStack,'Wishlist exceeds exact-ID catalog cap')
            assert(seen[id] and CatalogModel.Eligible(catalog,id,s.character,{}),'ineligible Wishlist target')
        end
        for slot,card in ipairs(board) do assert(Eligible(card.spellId,slot),'ineligible initial offer') end
    end
    local function Draw(kind, ordinal, slot)
        local eligible,total={},0
        for _,entry in ipairs(pool) do
            if Eligible(entry.spellId,slot) then
                local weight=Weight(entry)
                total=total+weight
                eligible[#eligible+1]={spellId=entry.spellId,weight=weight}
            end
        end
        assert(total>0,'synthetic pool exhausted')
        local script=s.draws and s.draws[kind] and s.draws[kind][ordinal]
        local id=script and script[slot]
        if id then
            assert(seen[id] and Eligible(id,slot),'scripted draw outside eligible pool')
        else
            local threshold
            if s.profile.version==1 then
                local x=(s.seed+salts[kind]+ordinal*8191+slot*131)%2147483647
                for _=1,3 do x=(x*16807)%2147483647 end
                threshold=x%total
            else
                threshold=Random.Uniform(s.seed,(s.stream or 'scenario')..'/'..kind,ordinal,slot)*total
            end
            for _,entry in ipairs(eligible) do
                threshold=threshold-entry.weight
                if threshold<0 then id=entry.spellId;break end
            end
        end
        r.draws=r.draws+1
        return {spellId=assert(id,'draw failed')}
    end
    if not s.board then
        for slot=1,3 do board[slot]=Draw('initial',0,slot) end
        r.initialDraws=r.draws;r.draws=0
    end
    local sinceReroll=0
    local original=Nexus.EchoWeaver.NEXUS_POLICY
    local options=Copy(original)
    options.banishBeforeReroll=order=='banish-first'
    Nexus.EchoWeaver.NEXUS_POLICY=options
    local ok,err=pcall(function()
        while Missing()>0 and r.select<s.picks and r.actions<cap do
            local input={catalog=catalog,plan=plan,owned=adapter.Owned(catalog,owned),
                locked=adapter.Owned(catalog,{}),cards=board,horizon=s.picks-r.select,
                charges=charges,allowBanish=s.allowBanish~=false,allowReroll=s.allowReroll~=false,
                allowFreeze=s.allowFreeze==true,
                rollingPolicy='released'}
            if realCatalog then input.level=s.character.level;input.disabledLevers=s.character.disabledSpells end
            -- Candidates cannot inspect the seed, scripted stream, draw closure,
            -- terminal result or held-out measurements. Only stated mechanics
            -- and current observations enter the decision seam.
            local action
            if candidate then
                local available={}
                if candidate.needsPool~=false then
                    for _,entry in ipairs(pool) do
                        if not excluded[Key(entry.spellId)] and (not realCatalog or CatalogModel.Eligible(catalog,entry.spellId,s.character,owned)) then
                            local observed=Copy(entry)
                            if realCatalog then observed.weight=Weight(entry) end
                            available[#available+1]=observed
                        end
                    end
                end
                local view={profile=Copy(s.profile),pool=available,banishesSinceReroll=sinceReroll}
                if realCatalog then view.penalizedRoles=Copy(penalizedFamilies)
                elseif enriched then view.penalizedFamilies=Copy(penalizedFamilies) end
                action=candidate.decide(adapter,input,view)
            else action=adapter.Decide(input) end
            local kind,index=action.type=='take' and 'select' or action.type,action.index
            if kind=='wait' then r.stop='POLICY_WAIT';break end
            assert(kind=='select' or kind=='reroll' or kind=='banish' or kind=='freeze','unsupported action')
            local card=index and board[index]
            if kind~='reroll' then assert(card and card.spellId==action.spellId,'invalid action target') end
            r.actions=r.actions+1
            r[kind]=r[kind]+1
            if not (options and options.noTrace) then r.trace[#r.trace+1]=adapter.Line(action) end
            if kind=='select' then
                if realCatalog then assert(CatalogModel.Eligible(catalog,card.spellId,s.character,owned),'selection violates catalog eligibility/cap') end
                owned[card.spellId]=(owned[card.spellId] or 0)+1
                if realCatalog then CatalogModel.AddRoles(catalog,card.spellId,ownedFamilies)
                else ownedFamilies[catalog.familyOf[card.spellId]]=true end
                sinceReroll=0
                if Missing()>0 and r.select<s.picks then
                    if s.profile.version>=2 then
                        for slot=1,3 do if slot==index or not Frozen(board[slot]) then board[slot]=nil end end
                    end
                    for slot=1,3 do
                        if slot==index or not Frozen(board[slot]) then
                            board[slot]=Draw('select',r.select,slot)
                        else
                            board[slot].isCarried=true
                        end
                    end
                end
            else
                assert(kind=='banish' and input.allowBanish or kind=='reroll' and input.allowReroll
                    or kind=='freeze' and input.allowFreeze,'action without permission')
                assert(charges[kind]>0, 'resource overspend')
                charges[kind]=charges[kind]-1
                if kind=='freeze' then
                    assert(not Frozen(card) and not card.isGuaranteed,'protected Freeze target')
                    card.isFrozen=true
                elseif kind=='banish' then
                    assert(not Frozen(card) and not card.isGuaranteed,'protected Banish target')
                    assert((plan.requestedCounts[card.spellId] or 0)<=(owned[card.spellId] or 0),'Banish of needed target')
                    if exclusion~='none' then excluded[Key(card.spellId)]=true end
                    board[index]=Draw('banish',r.banish,index)
                    sinceReroll=sinceReroll+1
                else
                    local held=0
                    for _,c in ipairs(board) do if Frozen(c) then held=held+1 end end
                    assert(held<2,'Reroll prohibited with two frozen offers')
                    if enriched then
                        for _,c in ipairs(board) do
                            if s.profile.rerollExcludeCurrent then temporaryExcluded[c.spellId]=true end
                            if realCatalog then CatalogModel.AddRoles(catalog,c.spellId,penalizedFamilies)
                            else penalizedFamilies[catalog.familyOf[c.spellId]]=true end
                        end
                    end
                    if s.profile.version>=2 then
                        for slot=1,3 do if not Frozen(board[slot]) then board[slot]=nil end end
                    end
                    for slot=1,3 do
                        if not Frozen(board[slot]) then board[slot]=Draw('reroll',r.reroll,slot) end
                    end
                    temporaryExcluded={}
                    if enriched and s.profile.rerollPenaltyLifetime=='board' then penalizedFamilies={} end
                    sinceReroll=0
                end
            end
        end
        r.missing=Missing()
        r.complete=r.missing==0
        r.stop=r.complete and 'COMPLETE' or r.stop or (r.select>=s.picks and 'PICKS_EXHAUSTED' or 'ACTION_LIMIT')
        r.remaining=Copy(charges)
        r.fingerprint=adapter.Fingerprint(r.trace)
    end)
    Nexus.EchoWeaver.NEXUS_POLICY=original
    if not ok then error(err,0) end
    return r
end
function Sim.Line(r)
    return table.concat({r.order,r.seed,r.profile.banishExclusion,r.stop,r.missing,r.select,
        r.banish,r.reroll,r.freeze,r.draws,r.actions,r.fingerprint},'|')
end
return Sim
