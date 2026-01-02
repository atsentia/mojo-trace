"""
Mojo Trace - Distributed Tracing Library

Pure Mojo implementation of OpenTelemetry-compatible distributed tracing.
Provides spans, context propagation, sampling, and export to OTLP collectors.

Features:
- Span creation with attributes, events, and links
- W3C Trace Context propagation (traceparent/tracestate)
- Multiple sampling strategies (ratio, parent-based, rate-limiting)
- Export to OTLP collectors (Jaeger, Tempo, etc.)
- Console export for debugging

Usage:
    from mojo_trace import Tracer, TraceContext

    # Create tracer
    var tracer = Tracer("gateway-service")

    # Start root span
    var span = tracer.start_span("handle_request")
    span.set_attribute("http.method", "POST")
    span.set_attribute("http.url", "/api/search")

    # Start child span
    var child = tracer.start_span("query_database", parent=span)
    child.set_attribute("db.statement", "SELECT * FROM users")
    child.end()

    # End root span
    span.set_ok()
    span.end()

    # Export spans
    tracer.export()

Context Propagation:
    # Extract from incoming request
    var ctx = TraceContext.from_headers(request.headers)
    var span = tracer.start_span("handle", parent_context=ctx)

    # Inject into outgoing request
    var headers = tracer.inject_context(span)
    client.get(url, headers=headers)

Export to OTLP:
    from mojo_trace.exporters import OtlpHttpExporter

    var exporter = OtlpHttpExporter("http://jaeger:4318")
    exporter.export(spans)
"""

# Core types
from .span import (
    Span,
    SpanBuilder,
    SpanEvent,
    SpanLink,
    SpanStatus,
    SpanKind,
)

# ID generation
from .id_generator import (
    generate_trace_id,
    generate_span_id,
    generate_request_id,
    is_valid_trace_id,
    is_valid_span_id,
    INVALID_TRACE_ID,
    INVALID_SPAN_ID,
)

# Context propagation
from .context import (
    TraceContext,
    TraceFlags,
    Baggage,
    get_current_context,
    set_current_context,
    get_current_baggage,
    set_current_baggage,
    clear_context,
)

# Sampling
from .sampler import (
    Sampler,
    SamplingResult,
    SamplingDecision,
    AlwaysOnSampler,
    AlwaysOffSampler,
    TraceIdRatioSampler,
    ParentBasedSampler,
    RateLimitingSampler,
    always_sample,
    never_sample,
    sample_ratio,
    sample_parent_based,
)

# Tracer
from .tracer import (
    Tracer,
    TracerConfig,
    get_tracer,
    set_global_tracer,
    register_tracer,
    create_tracer,
)

# Exporters
from .exporters import (
    ConsoleExporter,
    ConsoleExporterConfig,
    SimpleLogExporter,
    OtlpHttpExporter,
    OtlpExporterConfig,
    BatchExporter,
    console_exporter,
    pretty_console_exporter,
    simple_log_exporter,
    otlp_exporter,
    batch_exporter,
)
