-- Research v4: quality groups are not multi-valued role families.
-- Unknown arithmetic and exclusion semantics must be explicit profile choices.
local M={}
local function Int(n,low,label)
    assert(type(n)=='number' and n<math.huge and n==math.floor(n) and n>=low,label)
end
function M.Catalog(data)
    assert(type(data)=='table' and data.schema=='local-perk-catalog/v1','versioned local catalog required')
    local database,roles={},{}
    for id,row in pairs(data.rows) do
        Int(id,1,'invalid ID')
        for _,key in ipairs({'maxStack','classMask','minLevel','quality','groupId','requiredSpell'}) do
            Int(row[key],(key=='maxStack' or key=='minLevel') and 1 or 0,'invalid catalog '..key)
        end
        assert(row.quality<=4 and row.minLevel<=80,'catalog bounds')
        assert(type(row.roles)=='table','explicit role list required')
        local seen={};roles[id]={}
        for _,role in ipairs(row.roles) do
            assert(type(role)=='string' and role~='' and not seen[role],'invalid role')
            seen[role]=true;roles[id][#roles[id]+1]=role
        end
        database[id]={}
        for k,v in pairs(row) do if k~='roles' then database[id][k]=v end end
        database[id].comment='echo-'..id
    end
    local catalog,why=Nexus.EchoCatalogSource.Materialize(database,nil)
    assert(catalog and catalog.rowCount>0,why or 'empty catalog')
    catalog.rolesOf=roles
    return catalog
end
function M.Validate(s)
    local p=s.profile
    assert(p.version==4 and (p.banishExclusion=='spell' or p.banishExclusion=='group'),'v4 explicit spell/group exclusion required')
    assert(p.roleComposition=='any' or p.roleComposition=='product','explicit multi-role composition required')
    assert(p.capScope=='spell','only explicit exact-ID catalog caps supported')
    assert(p.maxStacks==nil,'v4 cannot replace per-entry caps')
    assert(type(p.uniqueOffers)=='boolean','explicit offer uniqueness required')
    local c=assert(s.character,'explicit character snapshot required')
    Int(c.classBit,1,'class bit required');Int(c.level,1,'level required')
    local validClass=false
    for _,bit in ipairs({1,2,4,8,16,32,64,128,256,1024}) do if c.classBit==bit then validClass=true end end
    assert(validClass,'single supported class bit required')
    assert(c.level<=80 and type(c.knownSpells)=='table' and type(c.disabledSpells)=='table','explicit prerequisite state required')
end
function M.Eligible(catalog,id,character,owned)
    local row=assert(catalog.rows[id],'ID outside catalog')
    return math.floor(row.classMask/character.classBit)%2==1
        and character.level>=row.minLevel
        and (row.requiredSpell==0 or character.knownSpells[row.requiredSpell]==true
            and character.disabledSpells[row.requiredSpell]~=true)
        and (owned[id] or 0)<row.maxStack
end
function M.AddRoles(catalog,id,set)
    for _,role in ipairs(catalog.rolesOf[id]) do set[role]=true end
end
function M.OwnedRoles(catalog,owned)
    local roles={}
    for id,count in pairs(owned) do if count>0 then M.AddRoles(catalog,id,roles) end end
    return roles
end
function M.Weight(catalog,entry,profile,ownedRoles,penalizedRoles)
    local selected,penalized=0,0
    for _,role in ipairs(catalog.rolesOf[entry.spellId]) do
        if ownedRoles[role] then selected=selected+1 end
        if penalizedRoles[role] then penalized=penalized+1 end
    end
    if profile.roleComposition=='any' then selected=math.min(1,selected);penalized=math.min(1,penalized) end
    local weight=entry.weight*profile.selectFamilyBoost^selected*profile.rerollFamilyPenalty^penalized
    assert(weight>0 and weight<math.huge,'non-finite or underflowed role weight')
    return weight
end
return M
