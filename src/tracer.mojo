"""
Tracer - Main Entry Point for Tracing

The Tracer is the primary interface for creating spans and managing traces.
Each service typically has one Tracer instance.

Example:
    # Create tracer for service
    var tracer = Tracer("gateway-service")

    # Start root span
    var span = tracer.start_span("handle_request")
    span.set_attribute("http.method", "POST")

    # Start child span
    var child = tracer.start_span("query_database", parent=span)
    child.set_attribute("db.statement", "SELECT * FROM users")

    # End spans (LIFO order)
    child.end()
    span.end()

    # Export spans
    tracer.export()
"""

from time import perf_counter_ns

from .span import Span, SpanKind, SpanStatus, SpanBuilder
from .context import TraceContext, TraceFlags, get_current_context, set_current_context
from .sampler import (
    Sampler,
    SamplingResult,
    SamplingDecision,
    AlwaysOnSampler,
    TraceIdRatioSampler,
    ParentBasedSampler,
)
from .id_generator import generate_trace_id, generate_span_id

# Use mojo-json for export
from ...mojo_json.src import JsonValue, JsonObject, JsonArray, serialize


# =============================================================================
# Tracer Configuration
# =============================================================================


@value
struct TracerConfig:
    """Configuration for tracer behavior."""

    var service_name: String
    """Service/application name."""

    var service_version: String
    """Service version."""

    var environment: String
    """Deployment environment (dev, staging, prod)."""

    var max_spans: Int
    """Maximum spans to buffer before export."""

    var sample_ratio: Float64
    """Sampling ratio (0.0 to 1.0)."""

    var export_timeout_ms: Int
    """Export timeout in milliseconds."""

    fn __init__(out self, service_name: String):
        """Create config with service name."""
        self.service_name = service_name
        self.service_version = ""
        self.environment = ""
        self.max_spans = 1000
        self.sample_ratio = 1.0
        self.export_timeout_ms = 30000

    fn __init__(
        out self,
        service_name: String,
        service_version: String = "",
        environment: String = "",
        sample_ratio: Float64 = 1.0,
    ):
        """Create config with all options."""
        self.service_name = service_name
        self.service_version = service_version
        self.environment = environment
        self.max_spans = 1000
        self.sample_ratio = sample_ratio
        self.export_timeout_ms = 30000


# =============================================================================
# Tracer
# =============================================================================


struct Tracer:
    """
    Creates and manages spans for distributed tracing.

    Thread Safety: This implementation is NOT thread-safe.
    For concurrent access, use external synchronization.
    """

    var config: TracerConfig
    """Tracer configuration."""

    var sampler: ParentBasedSampler
    """Sampling strategy."""

    var spans: List[Span]
    """Buffer of completed spans for export."""

    var active_spans: List[Span]
    """Currently active (not ended) spans."""

    fn __init__(out self, service_name: String):
        """Create tracer with service name."""
        self.config = TracerConfig(service_name)
        self.sampler = ParentBasedSampler(1.0)
        self.spans = List[Span]()
        self.active_spans = List[Span]()

    fn __init__(out self, config: TracerConfig):
        """Create tracer with configuration."""
        self.config = config
        self.sampler = ParentBasedSampler(config.sample_ratio)
        self.spans = List[Span]()
        self.active_spans = List[Span]()

    # -------------------------------------------------------------------------
    # Span Creation
    # -------------------------------------------------------------------------

    fn start_span(inout self, name: String) -> Span:
        """
        Start a new root span.

        Args:
            name: Span name (operation being traced)

        Returns:
            New span (already started)
        """
        var trace_id = generate_trace_id()
        var span_id = generate_span_id()

        # Check sampling decision
        var result = self.sampler.should_sample(trace_id, name, TraceContext())

        var span = Span(trace_id, span_id, name, self.config.service_name)
        span.sampled = result.is_sampled()

        self.active_spans.append(span)
        return span

    fn start_span(inout self, name: String, parent: Span) -> Span:
        """
        Start a child span.

        Args:
            name: Span name
            parent: Parent span

        Returns:
            New child span
        """
        var span_id = generate_span_id()

        var span = Span(
            parent.trace_id,
            span_id,
            parent.span_id,
            name,
            self.config.service_name,
        )
        span.sampled = parent.sampled

        self.active_spans.append(span)
        return span

    fn start_span(inout self, name: String, parent_context: TraceContext) -> Span:
        """
        Start a span from trace context (e.g., from incoming request).

        Args:
            name: Span name
            parent_context: Parent trace context

        Returns:
            New span continuing the trace
        """
        var trace_id = parent_context.trace_id
        var span_id = generate_span_id()

        # Check sampling decision
        var result = self.sampler.should_sample(trace_id, name, parent_context)

        var span = Span(
            trace_id,
            span_id,
            parent_context.span_id,
            name,
            self.config.service_name,
        )
        span.sampled = result.is_sampled()

        self.active_spans.append(span)
        return span

    fn start_span_with_kind(inout self, name: String, kind: Int) -> Span:
        """Start a span with specific kind."""
        var span = self.start_span(name)
        span.kind = kind
        return span

    fn start_server_span(inout self, name: String) -> Span:
        """Start a SERVER span (for incoming requests)."""
        return self.start_span_with_kind(name, SpanKind.SERVER)

    fn start_client_span(inout self, name: String) -> Span:
        """Start a CLIENT span (for outgoing requests)."""
        return self.start_span_with_kind(name, SpanKind.CLIENT)

    # -------------------------------------------------------------------------
    # Span Completion
    # -------------------------------------------------------------------------

    fn end_span(inout self, inout span: Span):
        """
        End a span and add to export buffer.

        Args:
            span: Span to end
        """
        if not span.ended:
            span.end()

        # Add to export buffer if sampled
        if span.sampled:
            self.spans.append(span)

        # Remove from active spans
        # Note: List doesn't have remove() - would need manual handling
        # For now, just clear ended spans periodically

        # Check if we should auto-export
        if len(self.spans) >= self.config.max_spans:
            self._flush_to_console()

    # -------------------------------------------------------------------------
    # Context Helpers
    # -------------------------------------------------------------------------

    fn current_context(self, span: Span) -> TraceContext:
        """
        Get trace context for a span.

        Use this to propagate context to downstream services.
        """
        return TraceContext(span.trace_id, span.span_id, TraceFlags.SAMPLED if span.sampled else TraceFlags.NONE)

    fn extract_context(self, headers: Dict[String, String]) -> TraceContext:
        """Extract trace context from incoming headers."""
        return TraceContext.from_headers(headers)

    fn inject_context(self, span: Span) -> Dict[String, String]:
        """Inject trace context into outgoing headers."""
        return self.current_context(span).to_headers()

    # -------------------------------------------------------------------------
    # Export
    # -------------------------------------------------------------------------

    fn export(inout self) -> Int:
        """
        Export all buffered spans.

        Returns number of spans exported.
        """
        var count = len(self.spans)
        if count > 0:
            self._flush_to_console()
        return count

    fn _flush_to_console(inout self):
        """Flush spans to console (simple exporter)."""
        for i in range(len(self.spans)):
            var span = self.spans[i]
            var json = span.to_json_string()
            print("[TRACE] " + json)

        self.spans.clear()

    fn flush(inout self):
        """Alias for export()."""
        _ = self.export()

    fn shutdown(inout self):
        """Shutdown tracer and export remaining spans."""
        _ = self.export()

    # -------------------------------------------------------------------------
    # Statistics
    # -------------------------------------------------------------------------

    fn pending_spans(self) -> Int:
        """Get number of spans pending export."""
        return len(self.spans)

    fn active_span_count(self) -> Int:
        """Get number of active (not ended) spans."""
        return len(self.active_spans)


# =============================================================================
# Global Tracer Registry
# =============================================================================


var _global_tracer: Tracer = Tracer("default")
"""Global default tracer."""

var _tracers: Dict[String, Tracer] = Dict[String, Tracer]()
"""Named tracer registry."""


fn get_tracer(name: String = "default") -> Tracer:
    """Get tracer by name."""
    if name == "default":
        return _global_tracer
    if name in _tracers:
        return _tracers[name]
    return _global_tracer


fn set_global_tracer(tracer: Tracer):
    """Set global default tracer."""
    global _global_tracer
    _global_tracer = tracer


fn register_tracer(name: String, tracer: Tracer):
    """Register named tracer."""
    global _tracers
    _tracers[name] = tracer


# =============================================================================
# Convenience Functions
# =============================================================================


fn trace[F: fn() -> None](name: String, f: F):
    """
    Trace a function call.

    Example:
        trace("process_data", fn():
            process_data()
        )
    """
    var tracer = get_tracer()
    var span = tracer.start_span(name)
    try:
        f()
        span.set_ok()
    except e:
        span.record_exception(str(e))
    span.end()


fn create_tracer(service_name: String) -> Tracer:
    """Create a new tracer for a service."""
    return Tracer(service_name)


fn create_tracer(config: TracerConfig) -> Tracer:
    """Create a new tracer with configuration."""
    return Tracer(config)
