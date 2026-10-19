"""Call the real Lua candidate functions from model research. No copied policy."""
import sys


class LuaPolicies:
    def __init__(self, lupa_path=None):
        if lupa_path:
            sys.path.insert(0, str(lupa_path.resolve()))
        from lupa.luajit21 import LuaRuntime
        self.lua = LuaRuntime(unpack_returned_tuples=True)
        self.lua.execute("P=dofile('tests/prototype/policy_adapter.lua'); P.Load('.'); C=dofile('tools/echo-policy-sim/candidates.lua')")
        self.factory = self.lua.eval('''function(ids, families, targets, weights, profile, name)
            local definitions, entries = {}, {}
            for i,id in ipairs(ids) do
                local family=tostring(families[i])
                definitions[family]=definitions[family] or {}
                local q=0; while definitions[family][q] do q=q+1 end
                definitions[family][q]=id
                if targets[i]>0 then entries[#entries+1]={spellId=id,stacks=targets[i]} end
            end
            local catalog=P.Catalog(definitions); local plan=P.Plan(catalog,entries)
            local candidate=C.Get(name)
            return function(owned, board, picks, b, r, f, banned, since)
                local bySpell, cards, pool = {}, {}, {}
                for i,id in ipairs(ids) do
                    if owned[i]>0 then bySpell[id]=owned[i] end
                    if not banned[i] then pool[#pool+1]={spellId=id,weight=weights[i]} end
                end
                for i,c in ipairs(board) do cards[i]={spellId=ids[c[1]+1],isFrozen=c[2],isGuaranteed=c[3]} end
                local action=candidate.decide(P,{catalog=catalog,plan=plan,owned=P.Owned(catalog,bySpell),
                    locked=P.Owned(catalog,{}),cards=cards,horizon=picks,
                    charges={trustworthy=true,banish=b,reroll=r,freeze=f},
                    allowBanish=true,allowReroll=true,allowFreeze=true},
                    {profile=profile,pool=pool,banishesSinceReroll=since})
                return action.type, action.index or 0
            end
        end''')

    def table(self, value):
        if isinstance(value, dict):
            return self.lua.table_from({k: self.table(v) for k, v in value.items()})
        if isinstance(value, (list, tuple)):
            return self.lua.table_from([self.table(v) for v in value])
        return value

    def bind(self, model, name):
        fn = self.factory(*[self.table(v) for v in (model.ids, model.families, model.targets, model.weights,
            dict(version=2, banishExclusion=model.exclusion, uniqueOffers=model.unique, maxStacks=model.cap))], name)
        def decide(s):
            kind, index = fn(self.table(s.owned), self.table(s.board), s.picks, s.banish, s.reroll, s.freeze,
                             self.table([bool(s.banned & (1 << i)) for i in range(model.n)]), s.since_reroll)
            return ("select" if kind == "take" else kind), int(index) - 1
        return decide
