# mojo-trace

Pure Mojo distributed tracing library compatible with OpenTelemetry.

## Features

- **Span Management**: Create, configure, and export spans with attributes, events, and links
- **W3C Trace Context**: Full support for `traceparent` and `tracestate` headers
- **Multiple Samplers**: Always-on, ratio-based, parent-based, and rate-limiting
- **OTLP Export**: Send traces to Jaeger, Tempo, or any OTLP-compatible backend
- **Console Export**: Debug output for development
- **Pure Mojo Core**: Core tracing logic is pure Mojo (OTLP export uses Python httpx)

## Quick Start

```mojo
from mojo_trace import Tracer, TraceContext

# Create tracer for your service
var tracer = Tracer("gateway-service")

# Start a root span
var span = tracer.start_span("handle_request")
span.set_attribute("http.method", "POST")
span.set_attribute("http.url", "/api/search")
span.set_attribute("http.status_code", 200)

# Create a child span
var db_span = tracer.start_span("query_database", parent=span)
db_span.set_attribute("db.system", "postgresql")
db_span.set_attribute("db.statement", "SELECT * FROM users")
db_span.set_ok()
db_span.end()

# Complete the request span
span.set_ok()
span.end()

# Export spans
tracer.export()
```

## Context Propagation

Propagate trace context across service boundaries:

```mojo
from mojo_trace import Tracer, TraceContext

var tracer = Tracer("downstream-service")

# Extract context from incoming request
var incoming_ctx = TraceContext.from_headers(request.headers)
var span = tracer.start_span("process", parent_context=incoming_ctx)

# Inject context into outgoing request
var outgoing_headers = tracer.inject_context(span)
client.post(url, headers=outgoing_headers)

span.end()
```

## Sampling

Control trace volume with samplers:

```mojo
from mojo_trace import TracerConfig, Tracer
from mojo_trace import sample_ratio, sample_parent_based

# Sample 10% of traces
var config = TracerConfig("my-service", sample_ratio=0.1)
var tracer = Tracer(config)

# Or use parent-based sampling
var sampler = sample_parent_based(root_ratio=0.1)
```

## Export to OTLP

Send traces to Jaeger, Tempo, or other OTLP backends:

```mojo
from mojo_trace import Tracer
from mojo_trace.exporters import OtlpHttpExporter, BatchExporter

# Direct export
var exporter = OtlpHttpExporter("http://jaeger:4318")
exporter.export(spans)

# Batch export (more efficient)
var batch = BatchExporter("http://tempo:4318")
batch.add(span)
batch.flush()
```

## Span Attributes

Common semantic conventions:

```mojo
# HTTP
span.set_attribute("http.method", "POST")
span.set_attribute("http.url", "/api/search")
span.set_attribute("http.status_code", 200)
span.set_attribute("http.request_content_length", 1234)

# Database
span.set_attribute("db.system", "postgresql")
span.set_attribute("db.name", "users")
span.set_attribute("db.statement", "SELECT * FROM users")

# Messaging
span.set_attribute("messaging.system", "kafka")
span.set_attribute("messaging.destination", "orders")

# Custom
span.set_attribute("user.id", "12345")
span.set_attribute("tenant.name", "acme")
```

## Span Events

Record notable occurrences:

```mojo
span.add_event("cache_miss")
span.add_event("retry_attempt")

# Record exceptions
span.record_exception("Connection timeout after 30s")
```

## API Reference

### Tracer

| Method | Description |
|--------|-------------|
| `start_span(name)` | Start root span |
| `start_span(name, parent)` | Start child span |
| `start_span(name, context)` | Start from trace context |
| `start_server_span(name)` | Start SERVER kind span |
| `start_client_span(name)` | Start CLIENT kind span |
| `export()` | Export buffered spans |

### Span

| Method | Description |
|--------|-------------|
| `set_attribute(key, value)` | Set attribute |
| `add_event(name)` | Add event |
| `record_exception(message)` | Record exception |
| `set_ok()` | Set status OK |
| `set_error(message)` | Set status ERROR |
| `end()` | End span |

### TraceContext

| Method | Description |
|--------|-------------|
| `from_headers(headers)` | Extract from HTTP headers |
| `to_headers()` | Inject into HTTP headers |
| `to_traceparent()` | Format as traceparent header |
| `new_root()` | Create new root context |
| `child()` | Create child context |

## Architecture

```
mojo-trace/
├── src/
│   ├── span.mojo         # Span, SpanBuilder, SpanEvent, SpanLink
│   ├── context.mojo      # TraceContext, Baggage (W3C)
│   ├── sampler.mojo      # Sampling strategies
│   ├── tracer.mojo       # Tracer, TracerConfig
│   ├── id_generator.mojo # Trace/span ID generation
│   └── exporters/
│       ├── console.mojo  # Console output
│       └── otlp.mojo     # OTLP HTTP export
```

## Dependencies

- **mojo-json**: JSON serialization (pure Mojo)
- **mojo-time**: Timestamps (pure Mojo)
- **httpx** (Python): OTLP HTTP transport

## Comparison with Full OpenTelemetry

This is a **minimal OTLP-compatible** implementation (~2000 LOC) vs full OpenTelemetry SDK (~12,000 LOC).

| Feature | mojo-trace | Full OTEL |
|---------|------------|-----------|
| Spans | ✅ | ✅ |
| Context propagation | ✅ | ✅ |
| Sampling | ✅ Basic | ✅ Full |
| OTLP export | ✅ HTTP | ✅ HTTP + gRPC |
| Metrics | ❌ | ✅ |
| Logs | ❌ | ✅ |
| Auto-instrumentation | ❌ | ✅ |
| Baggage | ✅ Basic | ✅ Full |

## License

Apache 2.0

## Part of mojo-contrib

This library is part of [mojo-contrib](https://github.com/atsentia/mojo-contrib), a collection of pure Mojo libraries.
