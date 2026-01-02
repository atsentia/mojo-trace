"""
Trace/Span ID Generation

Generates unique identifiers for traces and spans:
- Trace ID: 32-character hex (128-bit)
- Span ID: 16-character hex (64-bit)

Uses a simple PRNG seeded from system time for uniqueness.
Not cryptographically secure, but sufficient for tracing IDs.
"""

from time import perf_counter_ns


# =============================================================================
# ID Generator State
# =============================================================================


var _seed: Int = 0
"""PRNG seed state."""

var _initialized: Bool = False
"""Whether generator has been seeded."""


fn _init_seed():
    """Initialize seed from system time."""
    global _seed, _initialized
    if not _initialized:
        _seed = perf_counter_ns()
        _initialized = True


fn _next_random() -> Int:
    """
    Generate next pseudo-random number.

    Uses LCG (Linear Congruential Generator) algorithm.
    Not cryptographically secure, but fast and sufficient for IDs.
    """
    global _seed
    _init_seed()

    # LCG parameters (same as glibc)
    alias A: Int = 1103515245
    alias C: Int = 12345
    alias M: Int = 2147483648  # 2^31

    _seed = (A * _seed + C) % M
    return _seed


fn _random_hex_char() -> String:
    """Generate single random hex character."""
    var r = _next_random() % 16
    if r < 10:
        return chr(ord("0") + r)
    else:
        return chr(ord("a") + r - 10)


# =============================================================================
# ID Generation Functions
# =============================================================================


fn generate_trace_id() -> String:
    """
    Generate a 32-character hex trace ID.

    Format: 32 lowercase hex characters (128-bit)
    Example: "4bf92f3577b34da6a3ce929d0e0e4736"
    """
    var result = String("")
    for _ in range(32):
        result += _random_hex_char()
    return result


fn generate_span_id() -> String:
    """
    Generate a 16-character hex span ID.

    Format: 16 lowercase hex characters (64-bit)
    Example: "00f067aa0ba902b7"
    """
    var result = String("")
    for _ in range(16):
        result += _random_hex_char()
    return result


fn generate_request_id() -> String:
    """
    Generate a request ID (8-character hex).

    Shorter ID suitable for logging correlation.
    """
    var result = String("")
    for _ in range(8):
        result += _random_hex_char()
    return result


# =============================================================================
# ID Validation
# =============================================================================


fn is_valid_trace_id(trace_id: String) -> Bool:
    """
    Validate trace ID format.

    Valid if:
    - Exactly 32 characters
    - All lowercase hex characters
    - Not all zeros
    """
    if len(trace_id) != 32:
        return False

    var all_zero = True
    for i in range(32):
        var c = trace_id[i]
        var is_hex = (c >= "0" and c <= "9") or (c >= "a" and c <= "f")
        if not is_hex:
            return False
        if c != "0":
            all_zero = False

    return not all_zero


fn is_valid_span_id(span_id: String) -> Bool:
    """
    Validate span ID format.

    Valid if:
    - Exactly 16 characters
    - All lowercase hex characters
    - Not all zeros
    """
    if len(span_id) != 16:
        return False

    var all_zero = True
    for i in range(16):
        var c = span_id[i]
        var is_hex = (c >= "0" and c <= "9") or (c >= "a" and c <= "f")
        if not is_hex:
            return False
        if c != "0":
            all_zero = False

    return not all_zero


# =============================================================================
# Invalid ID Constants
# =============================================================================


alias INVALID_TRACE_ID: String = "00000000000000000000000000000000"
"""32 zeros - invalid trace ID."""

alias INVALID_SPAN_ID: String = "0000000000000000"
"""16 zeros - invalid span ID."""


fn is_invalid_trace_id(trace_id: String) -> Bool:
    """Check if trace ID is the invalid all-zeros value."""
    return trace_id == INVALID_TRACE_ID or not is_valid_trace_id(trace_id)


fn is_invalid_span_id(span_id: String) -> Bool:
    """Check if span ID is the invalid all-zeros value."""
    return span_id == INVALID_SPAN_ID or not is_valid_span_id(span_id)
