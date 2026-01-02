"""
Tests for mojo-trace

Tests ID generation, span creation, and context propagation.
"""

from testing import assert_true, assert_equal

from ..src import generate_trace_id, generate_span_id
from ..src import is_valid_trace_id, is_valid_span_id
from ..src import INVALID_TRACE_ID, INVALID_SPAN_ID
from ..src import SpanStatus, SpanKind


# =============================================================================
# ID Generation Tests
# =============================================================================


fn test_generate_trace_id() raises:
    """Test trace ID generation."""
    var id1 = generate_trace_id()
    var id2 = generate_trace_id()

    # Should be 32 characters
    assert_equal(len(id1), 32)
    assert_equal(len(id2), 32)

    # Should be different
    assert_true(id1 != id2, "Trace IDs should be unique")

    # Should be valid hex
    assert_true(is_valid_trace_id(id1), "Trace ID should be valid hex")
    print("test_generate_trace_id: PASS")


fn test_generate_span_id() raises:
    """Test span ID generation."""
    var id1 = generate_span_id()
    var id2 = generate_span_id()

    # Should be 16 characters
    assert_equal(len(id1), 16)
    assert_equal(len(id2), 16)

    # Should be different
    assert_true(id1 != id2, "Span IDs should be unique")

    # Should be valid hex
    assert_true(is_valid_span_id(id1), "Span ID should be valid hex")
    print("test_generate_span_id: PASS")


fn test_invalid_ids() raises:
    """Test invalid ID constants."""
    assert_equal(INVALID_TRACE_ID, "00000000000000000000000000000000")
    assert_equal(INVALID_SPAN_ID, "0000000000000000")

    # Invalid IDs should not be valid
    assert_true(not is_valid_trace_id(INVALID_TRACE_ID), "Invalid trace ID should fail validation")
    assert_true(not is_valid_span_id(INVALID_SPAN_ID), "Invalid span ID should fail validation")
    print("test_invalid_ids: PASS")


fn test_id_validation() raises:
    """Test ID validation."""
    # Valid IDs
    assert_true(is_valid_trace_id("4bf92f3577b34da6a3ce929d0e0e4736"))
    assert_true(is_valid_span_id("a3ce929d0e0e4736"))

    # Invalid - wrong length
    assert_true(not is_valid_trace_id("short"))
    assert_true(not is_valid_span_id("short"))

    # Invalid - non-hex characters
    assert_true(not is_valid_trace_id("gggggggggggggggggggggggggggggggg"))
    assert_true(not is_valid_span_id("gggggggggggggggg"))
    print("test_id_validation: PASS")


# =============================================================================
# Span Status Tests
# =============================================================================


fn test_span_status() raises:
    """Test span status codes."""
    assert_equal(SpanStatus.UNSET, 0)
    assert_equal(SpanStatus.OK, 1)
    assert_equal(SpanStatus.ERROR, 2)

    assert_equal(SpanStatus.name(SpanStatus.OK), "OK")
    assert_equal(SpanStatus.name(SpanStatus.ERROR), "ERROR")
    assert_equal(SpanStatus.name(SpanStatus.UNSET), "UNSET")
    print("test_span_status: PASS")


fn test_span_kind() raises:
    """Test span kind values."""
    assert_equal(SpanKind.INTERNAL, 0)
    assert_equal(SpanKind.SERVER, 1)
    assert_equal(SpanKind.CLIENT, 2)
    assert_equal(SpanKind.PRODUCER, 3)
    assert_equal(SpanKind.CONSUMER, 4)

    assert_equal(SpanKind.name(SpanKind.SERVER), "SERVER")
    assert_equal(SpanKind.name(SpanKind.CLIENT), "CLIENT")
    assert_equal(SpanKind.name(SpanKind.PRODUCER), "PRODUCER")
    assert_equal(SpanKind.name(SpanKind.CONSUMER), "CONSUMER")
    assert_equal(SpanKind.name(SpanKind.INTERNAL), "INTERNAL")
    print("test_span_kind: PASS")


# =============================================================================
# Main
# =============================================================================


fn main() raises:
    print("Running mojo-trace tests...\n")

    test_generate_trace_id()
    test_generate_span_id()
    test_invalid_ids()
    test_id_validation()
    test_span_status()
    test_span_kind()

    print("\nAll tests passed!")
