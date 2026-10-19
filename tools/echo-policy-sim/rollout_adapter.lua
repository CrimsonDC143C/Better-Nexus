-- Research-only projection for complete synthetic ordinary-board rollouts.
-- Calls the SAME Nexus.Policy.Decide. Omits Model.Support, Orb/save state and
-- annotations inputs which that production path does not read. Never a live adapter.
local Fast={}
function Fast.Wrap(P)
    local out={};for k,v in pairs(P) do out[k]=v end
    function out.Decide(input)
        local cards={}
        for i,c in ipairs(input.cards) do
            local row=input.catalog.rows[c.spellId]
            cards[i]={spellId=c.spellId,quality=c.quality or row.quality or 0,
                family=input.catalog.familyOf[c.spellId],isFrozen=c.isFrozen,isCarried=c.isCarried,
                justFrozen=c.justFrozen,isGuaranteed=c.isGuaranteed}
        end
        return Nexus.Policy.Decide({catalog=input.catalog,plan=input.plan,owned=input.owned,locked=input.locked,
            board={cards=cards},horizon=input.horizon,charges=input.charges,level=20,
            allowBanish=input.allowBanish==true,allowReroll=input.allowReroll==true,allowFreeze=input.allowFreeze==true,
            canFreeze=input.allowFreeze==true,ordinaryBoardAllowed=input.ordinaryBoardAllowed~=false,
            pending=input.pending,pendingAction=input.pendingAction,
            searchRefused={banish=false,reroll=input.allowReroll~=true}})
    end
    return out
end
return Fast
