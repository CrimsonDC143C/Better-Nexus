-- Client-described directions with deliberately hypothetical magnitudes.
-- A multiplier applies once per family, not once per stack/action.
local Base=dofile('tools/echo-policy-sim/corpus.lua')
local C={version='client-sensitivity/v3'}
function C.All()
    local out={}
    for _,s in ipairs(Base.All()) do
        if s.profile.banishExclusion~='none' then
            for _,boost in ipairs({1,2,4}) do
                for _,penalty in ipairs({1,0.5,0.25}) do
                    for _,lifetime in ipairs({'board','run'}) do
                        local n={};for k,v in pairs(s) do n[k]=v end
                        local profile={};for k,v in pairs(s.profile) do profile[k]=v end
                        profile.version=3;profile.rerollExcludeCurrent=true
                        profile.selectFamilyBoost=boost;profile.rerollFamilyPenalty=penalty
                        profile.rerollPenaltyLifetime=lifetime
                        n.profile=profile;n.stream=C.version..'/'..s.id
                        n.profileID=s.profileID..'-boost'..boost..'-penalty'..penalty..'-'..lifetime
                        out[#out+1]=n
                    end
                end
            end
        end
    end
    table.sort(out,function(a,b) return a.profileID==b.profileID and a.id<b.id or a.profileID<b.profileID end)
    return out
end
return C
