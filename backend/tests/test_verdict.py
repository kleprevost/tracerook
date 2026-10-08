from __future__ import annotations

import copy

import pytest

from tracerook_backend.verdict import InvalidVerdict, validate_verdict

# Reference verdict shared with the client contract tests.
GOOD = {
    "schema_version": 1, "category": ["unsafe_action", "agent_misbehavior"], "severity": "high",
    "confidence": 0.83, "suspicious": True,
    "rationale": "This network operation does not appear related to the developer's task.",
    "evidence": ["Requested task is scoped to README edit", "Tool action requests an external upload"],
    "recommended_action": "request_approval", "session_drift": True,
    "limitations": ["Intent cannot be determined from available redacted context"],
}


def mutated(**changes):
    v = copy.deepcopy(GOOD)
    for k, val in changes.items():
        if val is ...:
            del v[k]
        else:
            v[k] = val
    return v


def test_spec_example_is_valid():
    assert validate_verdict(copy.deepcopy(GOOD)) == GOOD


@pytest.mark.parametrize("bad", [
    mutated(extra=1), mutated(severity=...), mutated(schema_version=2), mutated(schema_version=True),
    mutated(category=[]), mutated(category=["unsafe_action"] * 3), mutated(category=["unsafe_action", "unsafe_action"]),
    mutated(category=["nope"]), mutated(severity="catastrophic"),
    mutated(confidence=1.01), mutated(confidence=-0.1), mutated(confidence=float("nan")), mutated(confidence=True),
    mutated(confidence="0.5"), mutated(suspicious="yes"), mutated(session_drift=None),
    mutated(rationale="x" * 2049), mutated(rationale=3),
    mutated(evidence=["e"] * 11), mutated(evidence=["x" * 513]), mutated(limitations=[1]),
    mutated(recommended_action="deny"), mutated(recommended_action="unavailable"),
    "not an object", None, [],
])
def test_invalid_verdicts_rejected(bad):
    with pytest.raises(InvalidVerdict):
        validate_verdict(bad)


def test_boundary_values_accepted():
    ok = mutated(confidence=0, rationale="é" * 1024, evidence=["x" * 512] * 10, limitations=[], category=["agent_misbehavior"])
    validate_verdict(ok)
    validate_verdict(mutated(confidence=1))
