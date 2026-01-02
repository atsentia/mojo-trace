"""
OTLP HTTP Exporter

Exports spans to OpenTelemetry Protocol (OTLP) collectors via HTTP.
Compatible with Jaeger, Tempo, and other OTLP-compatible backends.

Default endpoint: http://localhost:4318/v1/traces

Example:
    var exporter = OtlpHttpExporter("http://localhost:4318")
    exporter.export(spans)

    # Or with configuration
    var config = OtlpExporterConfig(
        endpoint="http://jaeger:4318",
        headers={"Authorization": "Bearer token"},
    )
    var exporter = OtlpHttpExporter(config)
"""

from python import Python

from ..span import Span, SpanKind, SpanStatus
from ..context import TraceContext
from ...mojo_json.src import JsonValue, JsonObject, JsonArray, serialize


# =============================================================================
# OTLP Exporter Configuration
# =============================================================================


@value
struct OtlpExporterConfig:
    """Configuration for OTLP exporter."""

    var endpoint: String
    """OTLP collector endpoint (e.g., http://localhost:4318)."""

    var traces_path: String
    """Path for traces endpoint (default: /v1/traces)."""

    var timeout_ms: Int
    """Request timeout in milliseconds."""

    var headers: Dict[String, String]
    """Custom headers for requests."""

    var compression: String
    """Compression type (none, gzip)."""

    var retry_count: Int
    """Number of retries on failure."""

    var retry_delay_ms: Int
    """Delay between retries in milliseconds."""

    fn __init__(out self, endpoint: String = "http://localhost:4318"):
        """Create default configuration."""
        self.endpoint = endpoint
        self.traces_path = "/v1/traces"
        self.timeout_ms = 30000
        self.headers = Dict[String, String]()
        self.compression = "none"
        self.retry_count = 3
        self.retry_delay_ms = 1000

    fn full_url(self) -> String:
        """Get full URL for traces endpoint."""
        return self.endpoint + self.traces_path


# =============================================================================
# OTLP HTTP Exporter
# =============================================================================


struct OtlpHttpExporter:
    """
    Exports spans to OTLP collector via HTTP/JSON.

    Uses Python httpx for HTTP transport.
    Formats spans according to OTLP JSON specification.
    """

    var config: OtlpExporterConfig
    """Exporter configuration."""

    var spans_exported: Int
    """Total spans exported."""

    var export_failures: Int
    """Total export failures."""

    var _httpx: PythonObject
    """httpx module."""

    fn __init__(out self, endpoint: String = "http://localhost:4318") raises:
        """Create OTLP exporter with endpoint."""
        self.config = OtlpExporterConfig(endpoint)
        self.spans_exported = 0
        self.export_failures = 0
        self._httpx = Python.import_module("httpx")

    fn __init__(out self, config: OtlpExporterConfig) raises:
        """Create OTLP exporter with configuration."""
        self.config = config
        self.spans_exported = 0
        self.export_failures = 0
        self._httpx = Python.import_module("httpx")

    fn export(inout self, spans: List[Span]) raises -> Int:
        """
        Export spans to OTLP collector.

        Args:
            spans: List of spans to export

        Returns:
            Number of spans successfully exported
        """
        if len(spans) == 0:
            return 0

        # Build OTLP request body
        var body = self._build_request_body(spans)
        var json_body = serialize(JsonValue.from_object(body))

        # Prepare headers
        var py_headers = Python.dict()
        py_headers["Content-Type"] = "application/json"

        for key in self.config.headers:
            py_headers[key[]] = self.config.headers[key[]]

        # Send request with retries
        var success = False
        for attempt in range(self.config.retry_count + 1):
            try:
                var response = self._httpx.post(
                    self.config.full_url(),
                    content=json_body,
                    headers=py_headers,
                    timeout=Float64(self.config.timeout_ms) / 1000.0,
                )

                var status = int(response.status_code)
                if status >= 200 and status < 300:
                    success = True
                    break
                elif status >= 500:
                    # Retryable error
                    if attempt < self.config.retry_count:
                        self._sleep_ms(self.config.retry_delay_ms)
                        continue
                else:
                    # Non-retryable error
                    print("[OTLP] Export failed: " + str(status))
                    break
            except e:
                if attempt < self.config.retry_count:
                    self._sleep_ms(self.config.retry_delay_ms)
                    continue
                print("[OTLP] Export error: " + str(e))

        if success:
            self.spans_exported += len(spans)
            return len(spans)
        else:
            self.export_failures += 1
            return 0

    fn _build_request_body(self, spans: List[Span]) -> JsonObject:
        """
        Build OTLP request body from spans.

        OTLP format:
        {
            "resourceSpans": [{
                "resource": { "attributes": [...] },
                "scopeSpans": [{
                    "scope": { "name": "..." },
                    "spans": [...]
                }]
            }]
        }
        """
        # Build resource attributes
        var resource_attrs = JsonObject()
        resource_attrs["service.name"] = JsonValue.from_string(
            spans[0].service_name if len(spans) > 0 else "unknown"
        )

        var resource = JsonObject()
        resource["attributes"] = self._attributes_to_otlp(resource_attrs)

        # Build spans array
        var spans_array = List[JsonValue]()
        for i in range(len(spans)):
            spans_array.append(JsonValue.from_object(self._span_to_otlp(spans[i])))

        # Build scope spans
        var scope = JsonObject()
        scope["name"] = JsonValue.from_string("mojo-trace")
        scope["version"] = JsonValue.from_string("1.0.0")

        var scope_spans = JsonObject()
        scope_spans["scope"] = JsonValue.from_object(scope)
        scope_spans["spans"] = JsonValue.from_array(spans_array)

        var scope_spans_array = List[JsonValue]()
        scope_spans_array.append(JsonValue.from_object(scope_spans))

        # Build resource spans
        var resource_spans = JsonObject()
        resource_spans["resource"] = JsonValue.from_object(resource)
        resource_spans["scopeSpans"] = JsonValue.from_array(scope_spans_array)

        var resource_spans_array = List[JsonValue]()
        resource_spans_array.append(JsonValue.from_object(resource_spans))

        # Build final request
        var body = JsonObject()
        body["resourceSpans"] = JsonValue.from_array(resource_spans_array)

        return body

    fn _span_to_otlp(self, span: Span) -> JsonObject:
        """Convert span to OTLP format."""
        var obj = JsonObject()

        # IDs (hex strings)
        obj["traceId"] = JsonValue.from_string(span.trace_id)
        obj["spanId"] = JsonValue.from_string(span.span_id)

        if len(span.parent_span_id) > 0:
            obj["parentSpanId"] = JsonValue.from_string(span.parent_span_id)

        # Name and kind
        obj["name"] = JsonValue.from_string(span.name)
        obj["kind"] = JsonValue.from_number(Float64(self._kind_to_otlp(span.kind)))

        # Timestamps (nanoseconds as strings for precision)
        obj["startTimeUnixNano"] = JsonValue.from_string(str(span.start_time_ns))
        obj["endTimeUnixNano"] = JsonValue.from_string(str(span.end_time_ns))

        # Status
        var status = JsonObject()
        status["code"] = JsonValue.from_number(Float64(self._status_to_otlp(span.status_code)))
        if len(span.status_message) > 0:
            status["message"] = JsonValue.from_string(span.status_message)
        obj["status"] = JsonValue.from_object(status)

        # Attributes
        if len(span.attributes) > 0:
            var attrs = JsonObject()
            for key in span.attributes:
                attrs[key[]] = JsonValue.from_string(span.attributes[key[]])
            obj["attributes"] = self._attributes_to_otlp(attrs)

        # Events
        if len(span.events) > 0:
            var events_array = List[JsonValue]()
            for i in range(len(span.events)):
                var event = span.events[i]
                var event_obj = JsonObject()
                event_obj["name"] = JsonValue.from_string(event.name)
                event_obj["timeUnixNano"] = JsonValue.from_string(str(event.timestamp_ns))
                if len(event.attributes) > 0:
                    var evt_attrs = JsonObject()
                    for k in event.attributes:
                        evt_attrs[k[]] = JsonValue.from_string(event.attributes[k[]])
                    event_obj["attributes"] = self._attributes_to_otlp(evt_attrs)
                events_array.append(JsonValue.from_object(event_obj))
            obj["events"] = JsonValue.from_array(events_array)

        return obj

    fn _attributes_to_otlp(self, attrs: JsonObject) -> JsonValue:
        """
        Convert attributes to OTLP format.

        OTLP uses: [{"key": "...", "value": {"stringValue": "..."}}]
        """
        var array = List[JsonValue]()

        for key in attrs:
            var attr = JsonObject()
            attr["key"] = JsonValue.from_string(key[])

            var value = JsonObject()
            value["stringValue"] = attrs[key[]]
            attr["value"] = JsonValue.from_object(value)

            array.append(JsonValue.from_object(attr))

        return JsonValue.from_array(array)

    fn _kind_to_otlp(self, kind: Int) -> Int:
        """Convert SpanKind to OTLP kind value."""
        # OTLP uses 1-indexed kinds
        # INTERNAL=1, SERVER=2, CLIENT=3, PRODUCER=4, CONSUMER=5
        return kind + 1

    fn _status_to_otlp(self, status: Int) -> Int:
        """Convert SpanStatus to OTLP status code."""
        # OTLP: UNSET=0, OK=1, ERROR=2
        return status

    fn _sleep_ms(self, ms: Int):
        """Sleep for milliseconds."""
        try:
            var time_mod = Python.import_module("time")
            time_mod.sleep(Float64(ms) / 1000.0)
        except:
            pass

    fn shutdown(inout self):
        """Shutdown exporter."""
        pass

    fn force_flush(inout self) raises:
        """Force flush pending exports."""
        pass


# =============================================================================
# Batch Exporter
# =============================================================================


struct BatchExporter:
    """
    Batches spans for efficient export.

    Collects spans and exports them in batches to reduce overhead.
    """

    var inner: OtlpHttpExporter
    """Inner exporter."""

    var batch: List[Span]
    """Current batch of spans."""

    var max_batch_size: Int
    """Maximum spans per batch."""

    var max_queue_size: Int
    """Maximum spans in queue."""

    fn __init__(out self, endpoint: String = "http://localhost:4318") raises:
        """Create batch exporter."""
        self.inner = OtlpHttpExporter(endpoint)
        self.batch = List[Span]()
        self.max_batch_size = 512
        self.max_queue_size = 2048

    fn add(inout self, span: Span) raises:
        """Add span to batch."""
        self.batch.append(span)

        if len(self.batch) >= self.max_batch_size:
            self.flush()

    fn flush(inout self) raises -> Int:
        """Flush current batch."""
        if len(self.batch) == 0:
            return 0

        var count = self.inner.export(self.batch)
        self.batch.clear()
        return count

    fn shutdown(inout self) raises:
        """Shutdown and flush remaining spans."""
        _ = self.flush()
        self.inner.shutdown()


# =============================================================================
# Convenience Functions
# =============================================================================


fn otlp_exporter(endpoint: String = "http://localhost:4318") raises -> OtlpHttpExporter:
    """Create OTLP HTTP exporter."""
    return OtlpHttpExporter(endpoint)


fn batch_exporter(endpoint: String = "http://localhost:4318") raises -> BatchExporter:
    """Create batch OTLP exporter."""
    return BatchExporter(endpoint)
