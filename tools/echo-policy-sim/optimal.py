"""Exact finite-model reference. No server probabilities or future draws are inputs.

Backward induction enumerates every safe legal action and every draw outcome.
Values are (completion probability, -expected missing, -expected search actions).
All arithmetic in a certificate is rational. A limit raises, never approximates.
"""
import argparse
from dataclasses import dataclass, replace
from fractions import Fraction as F
import json
from pathlib import Path


class SearchLimit(RuntimeError):
    pass


class InvalidModel(ValueError):
    pass


@dataclass(frozen=True)
class State:
    owned: tuple
    board: tuple  # (zero-based pool index, held, guaranteed), in observed slot order
    picks: int
    banish: int = 0
    reroll: int = 0
    freeze: int = 0
    banned: int = 0
    since_reroll: int = 0


class Model:
    def __init__(self, weights, targets, families=None, exclusion="none", unique=False,
                 cap=None, ids=None):
        self.weights, self.targets = tuple(weights), tuple(targets)
        self.n = len(weights)
        self.families = tuple(families if families is not None else range(self.n))
        self.ids = tuple(ids if ids is not None else range(1001, 1001 + self.n))
        self.exclusion, self.unique, self.cap = exclusion, unique, cap
        if (not self.n or len(targets) != self.n or len(self.families) != self.n
                or len(self.ids) != self.n or len(set(self.ids)) != self.n
                or any(type(w) is not int or w < 1 for w in weights)
                or any(type(t) is not int or t < 0 for t in targets)
                or not any(targets) or exclusion not in ("none", "spell", "family")
                or cap is not None and (type(cap) is not int or cap < 1)):
            raise InvalidModel("invalid finite mechanics profile")

    def state(self, board, picks, banish=0, reroll=0, freeze=0, owned=None):
        cards = tuple((c, False, False) if isinstance(c, int) else tuple(c) for c in board)
        s = State(tuple(owned or [0] * self.n), cards, picks, banish, reroll, freeze)
        if (len(cards) != 3 or len(s.owned) != self.n
                or any(not 0 <= c[0] < self.n for c in cards)
                or any(type(v) is not int or v < 0 for v in (*s.owned, picks, banish, reroll, freeze))):
            raise InvalidModel("invalid observed state")
        return s

    def missing(self, s):
        return sum(max(0, t - o) for t, o in zip(self.targets, s.owned))

    def terminal(self, s):
        return not s.picks or not self.missing(s)

    def value(self, s):
        m = self.missing(s)
        return F(m == 0), F(-m), F(0)

    def actions(self, s):
        if self.terminal(s):
            return ()
        actions = [("select", i) for i in range(3)]
        for i, (echo, held, guaranteed) in enumerate(s.board):
            if not held and not guaranteed:
                if s.banish and s.owned[echo] >= self.targets[echo]:
                    actions.append(("banish", i))
                if s.freeze:
                    actions.append(("freeze", i))
        if s.reroll and sum(c[1] for c in s.board) < 2:
            actions.append(("reroll", -1))
        return tuple(actions)

    def eligible(self, s, board):
        present = {c[0] for c in board if c is not None} if self.unique else set()
        return tuple(i for i in range(self.n) if not s.banned & (1 << i)
                     and (self.cap is None or s.owned[i] < self.cap) and i not in present)

    def prepare(self, s, action):
        """Deterministic action effects; None slots are the required draw evidence."""
        if action not in self.actions(s):
            raise InvalidModel("illegal action: " + repr(action))
        kind, index = action
        board = list(s.board)
        if kind == "select":
            owned = list(s.owned)
            owned[board[index][0]] += 1
            s = replace(s, owned=tuple(owned), picks=s.picks - 1, since_reroll=0)
            if self.terminal(s):
                return s, ()
            slots = tuple(i for i, c in enumerate(board) if i == index or not c[1])
        elif kind == "freeze":
            echo, _, guaranteed = board[index]
            board[index] = (echo, True, guaranteed)
            return replace(s, board=tuple(board), freeze=s.freeze - 1), ()
        elif kind == "banish":
            echo = board[index][0]
            banned = s.banned
            if self.exclusion != "none":
                for i in range(self.n):
                    if i == echo or self.exclusion == "family" and self.families[i] == self.families[echo]:
                        banned |= 1 << i
            s = replace(s, banned=banned, banish=s.banish - 1, since_reroll=s.since_reroll + 1)
            slots = (index,)
        else:
            s = replace(s, reroll=s.reroll - 1, since_reroll=0)
            slots = tuple(i for i, c in enumerate(board) if not c[1])
        for i in slots:
            board[i] = None
        return replace(s, board=tuple(board)), slots

    def outcomes(self, s, action):
        post, slots = self.prepare(s, action)
        def draw(at, board, probability):
            if at == len(slots):
                yield probability, replace(post, board=tuple(board))
                return
            eligible = self.eligible(post, board)
            total = sum(self.weights[i] for i in eligible)
            if not total:
                raise InvalidModel("synthetic pool exhausted; no certificate for this model")
            for i in eligible:
                updated = list(board)
                updated[slots[at]] = (i, False, False)
                yield from draw(at + 1, updated, probability * F(self.weights[i], total))
        yield from draw(0, post.board, F(1))

    def sample(self, s, action, rng):
        post, slots = self.prepare(s, action)
        board = list(post.board)
        for slot in slots:
            eligible = self.eligible(post, board)
            total = sum(self.weights[i] for i in eligible)
            if not total:
                raise InvalidModel("synthetic pool exhausted")
            threshold = rng.randrange(total)
            for i in eligible:
                threshold -= self.weights[i]
                if threshold < 0:
                    board[slot] = (i, False, False)
                    break
        return replace(post, board=tuple(board))

    def describe(self):
        return dict(weights=self.weights, targets=self.targets, families=self.families,
                    ids=self.ids, exclusion=self.exclusion, unique=self.unique, cap=self.cap,
                    evidence="HYPOTHETICAL", version="finite-normal-board/v1")


class Solver:
    def __init__(self, model, limit=200000, policy=None):
        self.model, self.limit, self.policy = model, limit, policy
        self.cache, self.decisions, self.visited = {}, {}, 0

    def action_value(self, s, action):
        value = [F(0), F(0), F(-int(action[0] != "select"))]
        for probability, child in self.model.outcomes(s, action):
            for i, v in enumerate(self.solve(child)):
                value[i] += probability * v
        return tuple(value)

    def solve(self, s):
        if self.model.terminal(s):
            return self.model.value(s)
        if s in self.cache:
            return self.cache[s]
        self.visited += 1
        if self.visited > self.limit:
            raise SearchLimit(f"exact state budget exceeded: {self.limit}")
        actions = (self.policy(s),) if self.policy else self.model.actions(s)
        if actions == (("wait", -1),):
            value, action = self.model.value(s), actions[0]
        else:
            # Strict tuple comparison implements the approved priority, without weights.
            scored = [(self.action_value(s, a), a) for a in actions]
            value = max(v for v, _ in scored)
            action = next(a for v, a in scored if v == value)
        self.cache[s], self.decisions[s] = value, action
        return value

    def certificate(self, s):
        value = self.solve(s)  # Any incomplete search raises before a claim is emitted.
        return dict(status="EXACT_MODEL_OPTIMUM" if self.policy is None else "EXACT_POLICY_VALUE",
                    value=[str(v) for v in value], action=self.decisions.get(s),
                    states=len(self.cache), model=self.model.describe(), state=s.__dict__,
                    proof="Finite backward induction; each action consumes one pick or charge; all chance outcomes enumerated.")


def benchmarks():
    cases = []
    for exclusion in ("none", "spell", "family"):
        m = Model([1, 1, 1, 1], [1, 0, 0, 0], [0, 0, 1, 2], exclusion)
        cases.append(("one-pick-" + exclusion, m, m.state([1, 2, 3], 1, banish=1, reroll=1)))
    m = Model([1, 1, 2], [1, 1, 0])
    cases.append(("preserve-two-targets", m, m.state([0, 1, 2], 2, freeze=1)))
    m = Model([1, 3, 2], [2, 0, 0])
    cases.append(("needed-duplicate", m, m.state([0, 0, 2], 2, freeze=1)))
    return cases


def main():
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument("--output", type=Path, default=Path("build/optimal-reference.json"))
    p.add_argument("--lupa-path", type=Path)
    p.add_argument("--limit", type=int, default=200000)
    p.add_argument("--scenario", type=Path, help="JSON with model constructor fields and state() fields; solve a supplied observed state")
    args = p.parse_args()
    if args.scenario:
        data = json.loads(args.scenario.read_text(encoding='utf-8'))
        model = Model(**data['model'])
        state = model.state(**data['state'])
        certificate = Solver(model, args.limit).certificate(state)
        args.output.parent.mkdir(parents=True, exist_ok=True)
        args.output.write_text(json.dumps(certificate, indent=2) + '\n', encoding='utf-8')
        print(json.dumps({k:certificate[k] for k in ('status','value','action','states')}))
        return
    from lua_bridge import LuaPolicies
    bridge = LuaPolicies(args.lupa_path)
    report = []
    for name, model, state in benchmarks():
        record = dict(name=name, optimal=Solver(model, args.limit).certificate(state), policies={})
        for policy in ("released", "banish-family-safe-pair"):
            record["policies"][policy] = Solver(model, args.limit, bridge.bind(model, policy)).certificate(state)
        report.append(record)
        print(name, record["optimal"]["value"], flush=True)
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(report, indent=2) + "\n", encoding="utf-8")


if __name__ == "__main__":
    main()
