"""
Trace Sampling Strategies

Samplers decide which traces should be recorded and exported.
This helps manage volume and cost in high-throughput systems.

Available Samplers:
- AlwaysOnSampler: Sample everything (100%)
- AlwaysOffSampler: Sample nothing (0%)
- TraceIdRatioSampler: Sample based on trace ID hash (deterministic)
- ParentBasedSampler: Follow parent's sampling decision

Example:
    # Sample 10% of traces
    var sampler = TraceIdRatioSampler(0.1)

    # Or follow parent decision
    var sampler = ParentBasedSampler(root=TraceIdRatioSampler(0.1))
"""

from .context import TraceContext, TraceFlags
from .span import Span


# =============================================================================
# Sampling Result
# =============================================================================


struct SamplingDecision:
    """Sampling decision constants."""

    alias DROP: Int = 0
    """Don't record or export."""

    alias RECORD_ONLY: Int = 1
    """Record locally but don't export."""

    alias RECORD_AND_SAMPLE: Int = 2
    """Record and export."""


@value
struct SamplingResult:
    """Result of a sampling decision."""

    var decision: Int
    """Sampling decision."""

    var trace_state: String
    """Modified trace state (optional)."""

    fn __init__(out self, decision: Int):
        """Create result with decision."""
        self.decision = decision
        self.trace_state = ""

    fn __init__(out self, decision: Int, trace_state: String):
        """Create result with decision and trace state."""
        self.decision = decision
        self.trace_state = trace_state

    fn is_sampled(self) -> Bool:
        """Check if trace should be sampled (recorded and exported)."""
        return self.decision == SamplingDecision.RECORD_AND_SAMPLE

    fn is_recording(self) -> Bool:
        """Check if trace should be recorded (locally or exported)."""
        return self.decision >= SamplingDecision.RECORD_ONLY


# =============================================================================
# Sampler Trait
# =============================================================================


trait Sampler:
    """
    Sampler interface for deciding whether to sample a trace.

    Implement this trait for custom sampling strategies.
    """

    fn should_sample(
        self,
        trace_id: String,
        name: String,
        parent_context: TraceContext,
    ) -> SamplingResult:
        """
        Decide whether to sample a span.

        Args:
            trace_id: Trace ID of the span
            name: Span name
            parent_context: Parent trace context (if any)

        Returns:
            SamplingResult with decision
        """
        ...

    fn description(self) -> String:
        """Human-readable description of sampler."""
        ...


# =============================================================================
# Always On Sampler
# =============================================================================


struct AlwaysOnSampler:
    """Sample everything (100% sampling rate)."""

    fn __init__(out self):
        """Create always-on sampler."""
        pass

    fn should_sample(
        self,
        trace_id: String,
        name: String,
        parent_context: TraceContext,
    ) -> SamplingResult:
        """Always returns RECORD_AND_SAMPLE."""
        return SamplingResult(SamplingDecision.RECORD_AND_SAMPLE)

    fn description(self) -> String:
        """Get sampler description."""
        return "AlwaysOnSampler"


# =============================================================================
# Always Off Sampler
# =============================================================================


struct AlwaysOffSampler:
    """Sample nothing (0% sampling rate)."""

    fn __init__(out self):
        """Create always-off sampler."""
        pass

    fn should_sample(
        self,
        trace_id: String,
        name: String,
        parent_context: TraceContext,
    ) -> SamplingResult:
        """Always returns DROP."""
        return SamplingResult(SamplingDecision.DROP)

    fn description(self) -> String:
        """Get sampler description."""
        return "AlwaysOffSampler"


# =============================================================================
# Trace ID Ratio Sampler
# =============================================================================


struct TraceIdRatioSampler:
    """
    Sample based on trace ID hash.

    Deterministic: same trace ID always gets same decision.
    This ensures all spans in a trace are either all sampled or all dropped.
    """

    var ratio: Float64
    """Sampling ratio (0.0 to 1.0)."""

    var threshold: Int
    """Threshold for sampling (derived from ratio)."""

    fn __init__(out self, ratio: Float64):
        """
        Create ratio-based sampler.

        Args:
            ratio: Sampling ratio (0.0 = none, 1.0 = all)
        """
        self.ratio = min(max(ratio, 0.0), 1.0)
        # Use 32-bit threshold for trace ID comparison
        self.threshold = int(self.ratio * Float64(2147483647))

    fn should_sample(
        self,
        trace_id: String,
        name: String,
        parent_context: TraceContext,
    ) -> SamplingResult:
        """Sample based on trace ID hash."""
        if self.ratio >= 1.0:
            return SamplingResult(SamplingDecision.RECORD_AND_SAMPLE)
        if self.ratio <= 0.0:
            return SamplingResult(SamplingDecision.DROP)

        # Hash last 8 chars of trace ID (last 32 bits)
        var hash_value = self._hash_trace_id(trace_id)

        if hash_value < self.threshold:
            return SamplingResult(SamplingDecision.RECORD_AND_SAMPLE)
        else:
            return SamplingResult(SamplingDecision.DROP)

    fn _hash_trace_id(self, trace_id: String) -> Int:
        """
        Hash trace ID to integer for sampling comparison.

        Uses last 8 characters (32 bits) of trace ID.
        """
        if len(trace_id) < 8:
            return 0

        var hash_str = trace_id[len(trace_id) - 8:]
        var result: Int = 0

        for i in range(8):
            var c = hash_str[i]
            var digit: Int = 0

            if c >= "0" and c <= "9":
                digit = ord(c) - ord("0")
            elif c >= "a" and c <= "f":
                digit = ord(c) - ord("a") + 10
            elif c >= "A" and c <= "F":
                digit = ord(c) - ord("A") + 10

            result = result * 16 + digit

        return result

    fn description(self) -> String:
        """Get sampler description."""
        return "TraceIdRatioSampler{" + str(self.ratio) + "}"


# =============================================================================
# Parent-Based Sampler
# =============================================================================


struct ParentBasedSampler:
    """
    Sample based on parent span's decision.

    If parent is sampled, child is sampled.
    If parent is not sampled, child is not sampled.
    If no parent, uses root sampler.
    """

    var root_ratio: Float64
    """Sampling ratio for root spans."""

    var root_sampler: TraceIdRatioSampler
    """Sampler for root spans (no parent)."""

    fn __init__(out self, root_ratio: Float64 = 1.0):
        """
        Create parent-based sampler.

        Args:
            root_ratio: Sampling ratio for root spans (default: 100%)
        """
        self.root_ratio = root_ratio
        self.root_sampler = TraceIdRatioSampler(root_ratio)

    fn should_sample(
        self,
        trace_id: String,
        name: String,
        parent_context: TraceContext,
    ) -> SamplingResult:
        """
        Sample based on parent's decision.

        If parent is sampled, sample this span.
        If parent is not sampled, don't sample this span.
        If no parent, use root sampler.
        """
        # Check if we have a valid parent
        if parent_context.is_valid():
            # Follow parent's sampling decision
            if parent_context.is_sampled():
                return SamplingResult(
                    SamplingDecision.RECORD_AND_SAMPLE,
                    parent_context.trace_state,
                )
            else:
                return SamplingResult(
                    SamplingDecision.DROP,
                    parent_context.trace_state,
                )

        # No parent - use root sampler
        return self.root_sampler.should_sample(trace_id, name, parent_context)

    fn description(self) -> String:
        """Get sampler description."""
        return "ParentBasedSampler{root=" + str(self.root_ratio) + "}"


# =============================================================================
# Rate Limiting Sampler
# =============================================================================


struct RateLimitingSampler:
    """
    Limit sampling to N traces per second.

    Useful for protecting backend systems from trace storms.
    Not deterministic - different spans in same trace might get different decisions.
    Use ParentBasedSampler wrapper for consistency.
    """

    var max_traces_per_second: Int
    """Maximum traces to sample per second."""

    var tokens: Float64
    """Current token count (token bucket)."""

    var last_update_ns: Int
    """Last token refill time."""

    fn __init__(out self, max_traces_per_second: Int):
        """
        Create rate-limiting sampler.

        Args:
            max_traces_per_second: Maximum traces per second
        """
        self.max_traces_per_second = max_traces_per_second
        self.tokens = Float64(max_traces_per_second)
        self.last_update_ns = 0

    fn should_sample(
        inout self,
        trace_id: String,
        name: String,
        parent_context: TraceContext,
    ) -> SamplingResult:
        """Sample up to rate limit per second."""
        from time import perf_counter_ns

        var now = perf_counter_ns()

        # Refill tokens
        if self.last_update_ns > 0:
            var elapsed_ns = now - self.last_update_ns
            var elapsed_sec = Float64(elapsed_ns) / 1_000_000_000.0
            var new_tokens = elapsed_sec * Float64(self.max_traces_per_second)
            self.tokens = min(self.tokens + new_tokens, Float64(self.max_traces_per_second))

        self.last_update_ns = now

        # Try to consume a token
        if self.tokens >= 1.0:
            self.tokens -= 1.0
            return SamplingResult(SamplingDecision.RECORD_AND_SAMPLE)
        else:
            return SamplingResult(SamplingDecision.DROP)

    fn description(self) -> String:
        """Get sampler description."""
        return "RateLimitingSampler{" + str(self.max_traces_per_second) + "/s}"


# =============================================================================
# Convenience Functions
# =============================================================================


fn always_sample() -> AlwaysOnSampler:
    """Create always-on sampler."""
    return AlwaysOnSampler()


fn never_sample() -> AlwaysOffSampler:
    """Create always-off sampler."""
    return AlwaysOffSampler()


fn sample_ratio(ratio: Float64) -> TraceIdRatioSampler:
    """Create ratio-based sampler."""
    return TraceIdRatioSampler(ratio)


fn sample_parent_based(root_ratio: Float64 = 1.0) -> ParentBasedSampler:
    """Create parent-based sampler."""
    return ParentBasedSampler(root_ratio)
