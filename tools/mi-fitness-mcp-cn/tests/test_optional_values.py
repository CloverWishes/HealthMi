"""Regression tests for the optional value helpers (0 must not become None)."""

from mi_fitness_mcp.adapters.mi_fitness_cloud import MiFitnessCloudAdapter


def _adapter() -> MiFitnessCloudAdapter:
    return MiFitnessCloudAdapter(user_id="u1", pass_token="p1")


def test_optional_float_zero_is_preserved():
    adapter = _adapter()
    assert adapter._optional_float(0) == 0.0
    assert adapter._optional_float(0.0) == 0.0
    assert adapter._optional_float("0") == 0.0
    assert adapter._optional_float("0.0") == 0.0


def test_optional_int_zero_is_preserved():
    adapter = _adapter()
    assert adapter._optional_int(0) == 0
    assert adapter._optional_int(0.0) == 0
    assert adapter._optional_int("0") == 0
    assert adapter._optional_int("0.0") == 0


def test_optional_values_missing_is_none():
    adapter = _adapter()
    assert adapter._optional_float(None) is None
    assert adapter._optional_int(None) is None


def test_optional_values_nonzero_passthrough():
    adapter = _adapter()
    assert adapter._optional_float(1.5) == 1.5
    assert adapter._optional_float("3.14") == 3.14
    assert adapter._optional_int(7) == 7
    assert adapter._optional_int("42") == 42
