"""
Example: Distributed Tracing (OpenTelemetry)

Demonstrates:
- Creating spans with attributes
- Parent-child relationships
- Context propagation (W3C Trace Context)
- Exporting to OTLP collectors
"""

from mojo_trace import Tracer, TraceContext, Span
from mojo_trace import SpanKind, SpanStatus
from mojo_trace import generate_trace_id, generate_span_id
from mojo_trace import ConsoleExporter, OtlpHttpExporter


fn basic_tracing_example() raises:
    """Create and use spans."""
    print("=== Basic Tracing ===")

    # Create tracer for service
    var tracer = Tracer("gateway-service")

    # Start root span
    var span = tracer.start_span("handle_request")
    span.set_attribute("http.method", "POST")
    span.set_attribute("http.url", "/api/orders")
    span.set_attribute("http.status_code", "201")

    print("Created span: " + span.name)
    print("Trace ID: " + span.trace_id[:16] + "...")
    print("Span ID: " + span.span_id)

    # Add events (timestamped logs)
    span.add_event("Started processing")
    span.add_event("Validation complete")
    span.add_event("Order created", order_id="ORD-123")

    # End span
    span.set_ok()
    span.end()

    print("Span ended with OK status")
    print("")


fn parent_child_spans() raises:
    """Create span hierarchies."""
    print("=== Parent-Child Spans ===")

    var tracer = Tracer("order-service")

    # Root span
    var root = tracer.start_span("process_order")
    root.set_attribute("order.id", "ORD-456")

    # Child span 1
    var validate = tracer.start_span("validate_order", parent=root)
    validate.set_attribute("validation.type", "schema")
    validate.end()
    print("Child span: validate_order")

    # Child span 2
    var save = tracer.start_span("save_to_database", parent=root)
    save.set_attribute("db.system", "postgres")
    save.set_attribute("db.statement", "INSERT INTO orders...")
    save.end()
    print("Child span: save_to_database")

    # Child span 3
    var notify = tracer.start_span("send_notification", parent=root)
    notify.set_attribute("notification.type", "email")
    notify.end()
    print("Child span: send_notification")

    root.end()
    print("Root span: process_order")
    print("")


fn context_propagation_example() raises:
    """Propagate context across services."""
    print("=== Context Propagation (W3C Trace Context) ===")

    var tracer = Tracer("service-a")

    # Start span in Service A
    var span = tracer.start_span("call_service_b")

    # Inject context into HTTP headers (outgoing request)
    var headers = tracer.inject_context(span)
    print("Outgoing headers:")
    print("  traceparent: " + headers.get("traceparent", ""))
    print("  tracestate: " + headers.get("tracestate", ""))

    # === Simulate Service B receiving request ===

    # Extract context from incoming headers
    var ctx = TraceContext.from_headers(headers)

    # Create child span in Service B with parent context
    var tracer_b = Tracer("service-b")
    var child = tracer_b.start_span("process_request", parent_context=ctx)
    print("\nService B received trace:")
    print("  Parent Trace ID: " + ctx.trace_id[:16] + "...")
    print("  New Span ID: " + child.span_id)

    child.end()
    span.end()
    print("")


fn exporter_example() raises:
    """Export spans to collectors."""
    print("=== Exporting Spans ===")

    var tracer = Tracer("demo-service")

    # Create some spans
    var span1 = tracer.start_span("operation1")
    span1.end()
    var span2 = tracer.start_span("operation2")
    span2.end()

    # Console exporter (for debugging)
    var console = ConsoleExporter()
    console.export(tracer.spans())
    print("Console export: prints span details to stdout")

    # OTLP HTTP exporter (for Jaeger, Tempo, etc.)
    var otlp = OtlpHttpExporter("http://jaeger:4318/v1/traces")
    # otlp.export(tracer.spans())  # Uncomment with real collector
    print("OTLP export: sends to http://jaeger:4318/v1/traces")
    print("")


fn main() raises:
    print("mojo-trace: Distributed Tracing (OpenTelemetry Compatible)\n")

    basic_tracing_example()
    parent_child_spans()
    context_propagation_example()
    exporter_example()

    print("=" * 50)
    print("Collectors:")
    print("  - Jaeger: http://jaeger:4318/v1/traces")
    print("  - Tempo: http://tempo:4318/v1/traces")
    print("  - OpenTelemetry Collector: http://otel:4318/v1/traces")
