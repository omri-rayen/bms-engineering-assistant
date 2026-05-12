"""YAML rule loader + tiny safe expression evaluator.

A rule file looks like:

    rules:
      - id: DC-MASTER-EXEC
        category: dead_code
        when: coverage.bms_master.execution.dead_pct > policy.thresholds.D.exec_dead
        bind:
          model: bms_master
          metric: execution
          value: coverage.bms_master.execution.dead_pct
          limit: policy.thresholds.D.exec_dead
        severity: critical
        finding: "{model} execution dead = {value:.2f}% (limit {limit:.1f}%)"
        reasoning: >
          ...
        recommend:
          - "..."
        refs: ["ISO 26262-6:2018, table 7"]

The premise (`when`) is parsed by `ast` and evaluated under a strict
whitelist (Compare / BoolOp / UnaryOp / Constant / Name / Attribute).
Names + attribute chains are resolved as dotted paths against the working
context. Any missing fact => premise is False (rule simply doesn't fire).
"""
from __future__ import annotations

import ast
import operator
from dataclasses import dataclass, field
from pathlib import Path
from typing import Any

import yaml

from .facts import lookup, is_missing


_BIN_OPS = {
    ast.Eq:    operator.eq,
    ast.NotEq: operator.ne,
    ast.Lt:    operator.lt,
    ast.LtE:   operator.le,
    ast.Gt:    operator.gt,
    ast.GtE:   operator.ge,
    ast.In:    lambda a, b: a in b,
    ast.NotIn: lambda a, b: a not in b,
}


@dataclass
class Rule:
    id: str
    category: str
    when: str
    severity: str = "info"
    finding: str = ""
    reasoning: str = ""
    bind: dict = field(default_factory=dict)
    recommend: list = field(default_factory=list)
    refs: list = field(default_factory=list)
    # Optional iteration: {'var': 'name', 'in': 'dotted.path.to.list'}.
    # When set, the rule fires once per item in the list (item is bound
    # under `var` in the working context for the premise + bindings).
    for_each: dict | None = None
    # Pre-parsed AST for the premise.
    _ast: ast.AST | None = None
    # Originating YAML file (for diagnostics).
    source: str = ""


def load_rules(kb_dir: Path) -> tuple[list[Rule], dict]:
    """Load every *.yaml rule file under `kb_dir`. Returns (rules, policy).

    `asil_policy.yaml` is treated as data, not as rules: its content is
    returned alongside so it can be merged into the engine context.
    """
    rules: list[Rule] = []
    policy: dict = {}
    for path in sorted(kb_dir.glob("*.yaml")):
        with path.open("r", encoding="utf-8") as f:
            doc = yaml.safe_load(f) or {}
        if path.name == "asil_policy.yaml":
            policy = doc
            continue
        for r in doc.get("rules", []):
            rule = Rule(
                id=r["id"],
                category=r.get("category", path.stem),
                when=r["when"],
                severity=r.get("severity", "info"),
                finding=r.get("finding", ""),
                reasoning=r.get("reasoning", "").strip(),
                bind=r.get("bind", {}) or {},
                recommend=list(r.get("recommend", []) or []),
                refs=list(r.get("refs", []) or []),
                for_each=r.get("forEach"),
                source=path.name,
            )
            rule._ast = ast.parse(rule.when, mode="eval").body
            rules.append(rule)
    rules.sort(key=lambda x: (x.category, x.id))
    return rules, policy


# --------------------------------------------------------------------------
# Safe expression evaluator
# --------------------------------------------------------------------------

def _dotted(node: ast.AST) -> str | None:
    """Return the dotted path for a Name/Attribute chain, else None."""
    parts = []
    cur = node
    while isinstance(cur, ast.Attribute):
        parts.append(cur.attr)
        cur = cur.value
    if isinstance(cur, ast.Name):
        parts.append(cur.id)
        return ".".join(reversed(parts))
    return None


def _resolve(node: ast.AST, ctx: dict, used: list[str]):
    """Evaluate an expression node. Returns the value, or _missing._"""
    if isinstance(node, ast.Constant):
        return node.value
    if isinstance(node, (ast.Name, ast.Attribute)):
        path = _dotted(node)
        if path is None:
            raise ValueError(f"unsupported attribute target: {ast.dump(node)}")
        used.append(path)
        return lookup(ctx, path)
    if isinstance(node, ast.UnaryOp) and isinstance(node.op, ast.Not):
        v = _resolve(node.operand, ctx, used)
        return False if is_missing(v) else (not v)
    if isinstance(node, ast.BoolOp):
        vals = [_resolve(v, ctx, used) for v in node.values]
        # Treat missing as False (degrades gracefully).
        vals = [False if is_missing(v) else v for v in vals]
        if isinstance(node.op, ast.And):
            return all(vals)
        if isinstance(node.op, ast.Or):
            return any(vals)
    if isinstance(node, ast.Compare):
        left = _resolve(node.left, ctx, used)
        if is_missing(left):
            return False
        for op, comp in zip(node.ops, node.comparators):
            right = _resolve(comp, ctx, used)
            if is_missing(right):
                return False
            fn = _BIN_OPS.get(type(op))
            if fn is None:
                raise ValueError(f"unsupported comparator: {type(op).__name__}")
            if not fn(left, right):
                return False
            left = right
        return True
    raise ValueError(f"unsupported expression node: {type(node).__name__}")


def evaluate_premise(rule: Rule, ctx: dict) -> tuple[bool, list[str]]:
    """Return (fired, fact_paths_used)."""
    used: list[str] = []
    try:
        result = _resolve(rule._ast, ctx, used)
    except Exception as e:                       # pragma: no cover
        raise RuntimeError(f"rule {rule.id}: bad premise '{rule.when}': {e}")
    return bool(result), used


def resolve_bindings(rule: Rule, ctx: dict) -> tuple[dict, list[str]]:
    """Resolve `bind:` entries. Literals pass through; strings that look like
    dotted paths (model.x.y) are looked up in `ctx` -- if the lookup fails
    they are kept as the literal string."""
    out: dict[str, Any] = {}
    used: list[str] = []
    for k, v in rule.bind.items():
        if isinstance(v, str) and v and v[0].isalpha() and "." in v:
            val = lookup(ctx, v)
            if is_missing(val):
                out[k] = v       # literal string fallback
            else:
                out[k] = val
                used.append(v)
        else:
            out[k] = v
    return out, used
