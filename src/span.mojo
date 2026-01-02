"""
Span - Core Tracing Unit

Pure Mojo implementation of OpenTelemetry-compatible spans.
A span represents a single operation within a trace.

Example:
    var tracer = Tracer("gateway-service")
    var span = tracer.start_span("handle_request")
    span.set_attribute("http.method", "POST")
    span.set_attribute("http.url", "/api/search")

    # ... do work ...

    span.set_status(SpanStatus.OK)
    span.end()

Span Hierarchy:
    Trace
    └── Root Span (e.g., "HTTP Request")
        ├── Child Span (e.g., "Parse Request")
        ├── Child Span (e.g., "Query Database")
        │   └── Grandchild Span (e.g., "Execute SQL")
        └── Child Span (e.g., "Serialize Response")
"""

from time import perf_counter_ns

# Use mojo-time for timestamps
from ...mojo_time.src import DateTime, Timestamp, format_rfc3339

# Use mojo-json for attribute serialization
from ...mojo_json.src import JsonValue, JsonObject, serialize


# =============================================================================
# Span Status
# =============================================================================


struct SpanStatus:
    """OpenTelemetry span status codes."""

    alias UNSET: Int = 0
    """Default status - not explicitly set."""

    alias OK: Int = 1
    """Operation completed successfully."""

    alias ERROR: Int = 2
    """Operation failed."""

    @staticmethod
    fn name(code: Int) -> String:
        """Get status name from code."""
        if code == SpanStatus.OK:
            return "OK"
        elif code == SpanStatus.ERROR:
            return "ERROR"
        else:
            return "UNSET"


struct SpanKind:
    """OpenTelemetry span kind values."""

    alias INTERNAL: Int = 0
    """Internal operation (default)."""

    alias SERVER: Int = 1
    """Server-side of synchronous request."""

    alias CLIENT: Int = 2
    """Client-side of synchronous request."""

    alias PRODUCER: Int = 3
    """Producer of async message."""

    alias CONSUMER: Int = 4
    """Consumer of async message."""

    @staticmethod
    fn name(kind: Int) -> String:
        """Get kind name from value."""
        if kind == SpanKind.SERVER:
            return "SERVER"
        elif kind == SpanKind.CLIENT:
            return "CLIENT"
        elif kind == SpanKind.PRODUCER:
            return "PRODUCER"
        elif kind == SpanKind.CONSUMER:
            return "CONSUMER"
        else:
            return "INTERNAL"


# =============================================================================
# Span Event
# =============================================================================


@value
struct SpanEvent:
    """
    An event that occurred during a span's lifetime.

    Events are used to record notable happenings like exceptions,
    log messages, or significant state changes.
    """

    var name: String
    """Event name."""

    var timestamp_ns: Int
    """Timestamp in nanoseconds."""

    var attributes: Dict[String, String]
    """Event attributes."""

    fn __init__(out self, name: String):
        """Create event with name."""
        self.name = name
        self.timestamp_ns = perf_counter_ns()
        self.attributes = Dict[String, String]()

    fn __init__(out self, name: String, timestamp_ns: Int):
        """Create event with name and timestamp."""
        self.name = name
        self.timestamp_ns = timestamp_ns
        self.attributes = Dict[String, String]()

    fn set_attribute(inout self, key: String, value: String):
        """Add attribute to event."""
        self.attributes[key] = value

    fn to_json(self) -> JsonObject:
        """Convert to JSON object."""
        var obj = JsonObject()
        obj["name"] = JsonValue.from_string(self.name)
        obj["timeUnixNano"] = JsonValue.from_string(str(self.timestamp_ns))

        if len(self.attributes) > 0:
            var attrs = JsonObject()
            for key in self.attributes:
                attrs[key[]] = JsonValue.from_string(self.attributes[key[]])
            obj["attributes"] = JsonValue.from_object(attrs)

        return obj


# =============================================================================
# Span Link
# =============================================================================


@value
struct SpanLink:
    """
    A link to another span, possibly in a different trace.

    Links are used for batch operations or fan-out patterns
    where one span triggers multiple downstream spans.
    """

    var trace_id: String
    """Linked span's trace ID."""

    var span_id: String
    """Linked span's ID."""

    var attributes: Dict[String, String]
    """Link attributes."""

    fn __init__(out self, trace_id: String, span_id: String):
        """Create link to another span."""
        self.trace_id = trace_id
        self.span_id = span_id
        self.attributes = Dict[String, String]()

    fn set_attribute(inout self, key: String, value: String):
        """Add attribute to link."""
        self.attributes[key] = value

    fn to_json(self) -> JsonObject:
        """Convert to JSON object."""
        var obj = JsonObject()
        obj["traceId"] = JsonValue.from_string(self.trace_id)
        obj["spanId"] = JsonValue.from_string(self.span_id)

        if len(self.attributes) > 0:
            var attrs = JsonObject()
            for key in self.attributes:
                attrs[key[]] = JsonValue.from_string(self.attributes[key[]])
            obj["attributes"] = JsonValue.from_object(attrs)

        return obj


# =============================================================================
# Span
# =============================================================================


struct Span:
    """
    A span represents a single operation within a trace.

    Spans track:
    - Operation name and timing
    - Parent-child relationships
    - Attributes (key-value metadata)
    - Events (timestamped occurrences)
    - Status (success/error)

    Thread Safety: This implementation is NOT thread-safe.
    For concurrent access, use external synchronization.
    """

    var trace_id: String
    """32-character hex trace ID."""

    var span_id: String
    """16-character hex span ID."""

    var parent_span_id: String
    """Parent span ID (empty for root spans)."""

    var name: String
    """Operation name."""

    var kind: Int
    """Span kind (INTERNAL, SERVER, CLIENT, etc.)."""

    var start_time_ns: Int
    """Start timestamp in nanoseconds."""

    var end_time_ns: Int
    """End timestamp in nanoseconds (0 if not ended)."""

    var status_code: Int
    """Status code (UNSET, OK, ERROR)."""

    var status_message: String
    """Status message (typically for errors)."""

    var attributes: Dict[String, String]
    """Span attributes."""

    var events: List[SpanEvent]
    """Span events."""

    var links: List[SpanLink]
    """Links to other spans."""

    var service_name: String
    """Service/resource name."""

    var ended: Bool
    """Whether span has ended."""

    var sampled: Bool
    """Whether span is sampled for export."""

    fn __init__(
        out self,
        trace_id: String,
        span_id: String,
        name: String,
        service_name: String = "",
    ):
        """Create a new span."""
        self.trace_id = trace_id
        self.span_id = span_id
        self.parent_span_id = ""
        self.name = name
        self.kind = SpanKind.INTERNAL
        self.start_time_ns = perf_counter_ns()
        self.end_time_ns = 0
        self.status_code = SpanStatus.UNSET
        self.status_message = ""
        self.attributes = Dict[String, String]()
        self.events = List[SpanEvent]()
        self.links = List[SpanLink]()
        self.service_name = service_name
        self.ended = False
        self.sampled = True

    fn __init__(
        out self,
        trace_id: String,
        span_id: String,
        parent_span_id: String,
        name: String,
        service_name: String = "",
    ):
        """Create a child span."""
        self.trace_id = trace_id
        self.span_id = span_id
        self.parent_span_id = parent_span_id
        self.name = name
        self.kind = SpanKind.INTERNAL
        self.start_time_ns = perf_counter_ns()
        self.end_time_ns = 0
        self.status_code = SpanStatus.UNSET
        self.status_message = ""
        self.attributes = Dict[String, String]()
        self.events = List[SpanEvent]()
        self.links = List[SpanLink]()
        self.service_name = service_name
        self.ended = False
        self.sampled = True

    # -------------------------------------------------------------------------
    # Attribute Methods
    # -------------------------------------------------------------------------

    fn set_attribute(inout self, key: String, value: String):
        """Set string attribute."""
        if not self.ended:
            self.attributes[key] = value

    fn set_attribute(inout self, key: String, value: Int):
        """Set integer attribute."""
        if not self.ended:
            self.attributes[key] = str(value)

    fn set_attribute(inout self, key: String, value: Float64):
        """Set float attribute."""
        if not self.ended:
            self.attributes[key] = str(value)

    fn set_attribute(inout self, key: String, value: Bool):
        """Set boolean attribute."""
        if not self.ended:
            self.attributes[key] = "true" if value else "false"

    fn get_attribute(self, key: String, default: String = "") -> String:
        """Get attribute value."""
        if key in self.attributes:
            return self.attributes[key]
        return default

    fn has_attribute(self, key: String) -> Bool:
        """Check if attribute exists."""
        return key in self.attributes

    # -------------------------------------------------------------------------
    # Event Methods
    # -------------------------------------------------------------------------

    fn add_event(inout self, name: String):
        """Add event to span."""
        if not self.ended:
            self.events.append(SpanEvent(name))

    fn add_event(inout self, event: SpanEvent):
        """Add event to span."""
        if not self.ended:
            self.events.append(event)

    fn record_exception(inout self, message: String):
        """Record an exception event."""
        if not self.ended:
            var event = SpanEvent("exception")
            event.set_attribute("exception.message", message)
            self.events.append(event)
            self.set_status(SpanStatus.ERROR, message)

    # -------------------------------------------------------------------------
    # Link Methods
    # -------------------------------------------------------------------------

    fn add_link(inout self, trace_id: String, span_id: String):
        """Add link to another span."""
        if not self.ended:
            self.links.append(SpanLink(trace_id, span_id))

    fn add_link(inout self, link: SpanLink):
        """Add link to span."""
        if not self.ended:
            self.links.append(link)

    # -------------------------------------------------------------------------
    # Status Methods
    # -------------------------------------------------------------------------

    fn set_status(inout self, code: Int, message: String = ""):
        """Set span status."""
        if not self.ended:
            self.status_code = code
            self.status_message = message

    fn set_ok(inout self):
        """Set status to OK."""
        self.set_status(SpanStatus.OK)

    fn set_error(inout self, message: String = ""):
        """Set status to ERROR."""
        self.set_status(SpanStatus.ERROR, message)

    # -------------------------------------------------------------------------
    # Span Kind
    # -------------------------------------------------------------------------

    fn set_kind(inout self, kind: Int):
        """Set span kind."""
        if not self.ended:
            self.kind = kind

    fn set_server(inout self):
        """Set span kind to SERVER."""
        self.set_kind(SpanKind.SERVER)

    fn set_client(inout self):
        """Set span kind to CLIENT."""
        self.set_kind(SpanKind.CLIENT)

    # -------------------------------------------------------------------------
    # Lifecycle Methods
    # -------------------------------------------------------------------------

    fn end(inout self):
        """End the span with current timestamp."""
        if not self.ended:
            self.end_time_ns = perf_counter_ns()
            self.ended = True

    fn end(inout self, end_time_ns: Int):
        """End the span with specific timestamp."""
        if not self.ended:
            self.end_time_ns = end_time_ns
            self.ended = True

    fn is_ended(self) -> Bool:
        """Check if span has ended."""
        return self.ended

    fn is_recording(self) -> Bool:
        """Check if span is recording (not ended and sampled)."""
        return not self.ended and self.sampled

    fn duration_ns(self) -> Int:
        """Get span duration in nanoseconds."""
        if self.end_time_ns > 0:
            return self.end_time_ns - self.start_time_ns
        return perf_counter_ns() - self.start_time_ns

    fn duration_ms(self) -> Float64:
        """Get span duration in milliseconds."""
        return Float64(self.duration_ns()) / 1_000_000.0

    # -------------------------------------------------------------------------
    # Hierarchy Methods
    # -------------------------------------------------------------------------

    fn is_root(self) -> Bool:
        """Check if this is a root span (no parent)."""
        return len(self.parent_span_id) == 0

    fn has_parent(self) -> Bool:
        """Check if span has a parent."""
        return len(self.parent_span_id) > 0

    # -------------------------------------------------------------------------
    # Serialization
    # -------------------------------------------------------------------------

    fn to_json(self) -> JsonObject:
        """
        Convert span to JSON object (OTLP-compatible format).

        Returns JSON object suitable for OTLP HTTP export.
        """
        var obj = JsonObject()

        # IDs
        obj["traceId"] = JsonValue.from_string(self.trace_id)
        obj["spanId"] = JsonValue.from_string(self.span_id)
        if len(self.parent_span_id) > 0:
            obj["parentSpanId"] = JsonValue.from_string(self.parent_span_id)

        # Name and kind
        obj["name"] = JsonValue.from_string(self.name)
        obj["kind"] = JsonValue.from_number(Float64(self.kind))

        # Timestamps (as strings for large numbers)
        obj["startTimeUnixNano"] = JsonValue.from_string(str(self.start_time_ns))
        if self.end_time_ns > 0:
            obj["endTimeUnixNano"] = JsonValue.from_string(str(self.end_time_ns))

        # Status
        var status = JsonObject()
        status["code"] = JsonValue.from_number(Float64(self.status_code))
        if len(self.status_message) > 0:
            status["message"] = JsonValue.from_string(self.status_message)
        obj["status"] = JsonValue.from_object(status)

        # Attributes
        if len(self.attributes) > 0:
            var attrs = JsonObject()
            for key in self.attributes:
                attrs[key[]] = JsonValue.from_string(self.attributes[key[]])
            obj["attributes"] = JsonValue.from_object(attrs)

        # Events
        if len(self.events) > 0:
            var events_array = List[JsonValue]()
            for i in range(len(self.events)):
                var event_json = self.events[i].to_json()
                events_array.append(JsonValue.from_object(event_json))
            obj["events"] = JsonValue.from_array(events_array)

        # Links
        if len(self.links) > 0:
            var links_array = List[JsonValue]()
            for i in range(len(self.links)):
                var link_json = self.links[i].to_json()
                links_array.append(JsonValue.from_object(link_json))
            obj["links"] = JsonValue.from_array(links_array)

        return obj

    fn to_json_string(self) -> String:
        """Convert span to JSON string."""
        var obj = self.to_json()
        return serialize(JsonValue.from_object(obj))


# =============================================================================
# Span Builder (Fluent API)
# =============================================================================


struct SpanBuilder:
    """
    Fluent builder for creating spans.

    Example:
        var span = SpanBuilder("process_request")
            .with_parent(parent_span_id)
            .with_kind(SpanKind.SERVER)
            .with_attribute("http.method", "POST")
            .start()
    """

    var name: String
    var trace_id: String
    var parent_span_id: String
    var kind: Int
    var service_name: String
    var attributes: Dict[String, String]
    var links: List[SpanLink]
    var sampled: Bool

    fn __init__(out self, name: String):
        """Create builder with span name."""
        self.name = name
        self.trace_id = ""
        self.parent_span_id = ""
        self.kind = SpanKind.INTERNAL
        self.service_name = ""
        self.attributes = Dict[String, String]()
        self.links = List[SpanLink]()
        self.sampled = True

    fn with_trace_id(inout self, trace_id: String) -> Self:
        """Set trace ID."""
        self.trace_id = trace_id
        return self

    fn with_parent(inout self, parent_span_id: String) -> Self:
        """Set parent span ID."""
        self.parent_span_id = parent_span_id
        return self

    fn with_kind(inout self, kind: Int) -> Self:
        """Set span kind."""
        self.kind = kind
        return self

    fn with_service(inout self, service_name: String) -> Self:
        """Set service name."""
        self.service_name = service_name
        return self

    fn with_attribute(inout self, key: String, value: String) -> Self:
        """Add attribute."""
        self.attributes[key] = value
        return self

    fn with_link(inout self, trace_id: String, span_id: String) -> Self:
        """Add link to another span."""
        self.links.append(SpanLink(trace_id, span_id))
        return self

    fn with_sampled(inout self, sampled: Bool) -> Self:
        """Set sampled flag."""
        self.sampled = sampled
        return self

    fn start(self) -> Span:
        """Build and start the span."""
        from .id_generator import generate_trace_id, generate_span_id

        var trace_id = self.trace_id
        if len(trace_id) == 0:
            trace_id = generate_trace_id()

        var span_id = generate_span_id()

        var span: Span
        if len(self.parent_span_id) > 0:
            span = Span(trace_id, span_id, self.parent_span_id, self.name, self.service_name)
        else:
            span = Span(trace_id, span_id, self.name, self.service_name)

        span.kind = self.kind
        span.sampled = self.sampled

        # Copy attributes
        for key in self.attributes:
            span.attributes[key[]] = self.attributes[key[]]

        # Copy links
        for i in range(len(self.links)):
            span.links.append(self.links[i])

        return span
