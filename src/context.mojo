"""
Trace Context - W3C Trace Context Propagation

Implements W3C Trace Context specification (https://www.w3.org/TR/trace-context/)
for distributed tracing context propagation across service boundaries.

Headers:
- traceparent: Contains trace ID, span ID, and flags
- tracestate: Optional vendor-specific key-value pairs

Format:
    traceparent: {version}-{trace-id}-{parent-span-id}-{flags}
    Example: 00-4bf92f3577b34da6a3ce929d0e0e4736-00f067aa0ba902b7-01

Flags:
    - 00: Not sampled
    - 01: Sampled

Example:
    # Extract from incoming request
    var ctx = TraceContext.from_headers(request.headers)
    if ctx.is_valid():
        var span = tracer.start_span("handle", parent=ctx)

    # Inject into outgoing request
    var headers = ctx.to_headers()
    client.get(url, headers=headers)
"""

from .id_generator import (
    generate_trace_id,
    generate_span_id,
    is_valid_trace_id,
    is_valid_span_id,
    INVALID_TRACE_ID,
    INVALID_SPAN_ID,
)


# =============================================================================
# Trace Flags
# =============================================================================


struct TraceFlags:
    """W3C trace flags."""

    alias NONE: Int = 0
    """Not sampled."""

    alias SAMPLED: Int = 1
    """Sampled - should be recorded and exported."""

    @staticmethod
    fn to_string(flags: Int) -> String:
        """Convert flags to 2-char hex string."""
        if flags == TraceFlags.SAMPLED:
            return "01"
        return "00"

    @staticmethod
    fn from_string(s: String) -> Int:
        """Parse flags from 2-char hex string."""
        if s == "01":
            return TraceFlags.SAMPLED
        return TraceFlags.NONE


# =============================================================================
# Trace Context
# =============================================================================


@value
struct TraceContext:
    """
    W3C Trace Context for distributed tracing.

    Carries trace/span IDs and sampling decision across service boundaries.
    """

    var trace_id: String
    """32-character hex trace ID."""

    var span_id: String
    """16-character hex span/parent ID."""

    var trace_flags: Int
    """Trace flags (sampling decision)."""

    var trace_state: String
    """Optional vendor-specific state (tracestate header)."""

    fn __init__(out self):
        """Create empty (invalid) context."""
        self.trace_id = INVALID_TRACE_ID
        self.span_id = INVALID_SPAN_ID
        self.trace_flags = TraceFlags.NONE
        self.trace_state = ""

    fn __init__(out self, trace_id: String, span_id: String):
        """Create context with IDs."""
        self.trace_id = trace_id
        self.span_id = span_id
        self.trace_flags = TraceFlags.SAMPLED
        self.trace_state = ""

    fn __init__(
        out self,
        trace_id: String,
        span_id: String,
        trace_flags: Int,
        trace_state: String = "",
    ):
        """Create context with all fields."""
        self.trace_id = trace_id
        self.span_id = span_id
        self.trace_flags = trace_flags
        self.trace_state = trace_state

    # -------------------------------------------------------------------------
    # Validation
    # -------------------------------------------------------------------------

    fn is_valid(self) -> Bool:
        """Check if context is valid (has valid trace and span IDs)."""
        return is_valid_trace_id(self.trace_id) and is_valid_span_id(self.span_id)

    fn is_sampled(self) -> Bool:
        """Check if trace is sampled."""
        return (self.trace_flags & TraceFlags.SAMPLED) != 0

    fn is_remote(self) -> Bool:
        """Check if context came from a remote parent."""
        # In a full implementation, this would track whether context was extracted
        # from incoming request headers vs created locally
        return self.is_valid()

    # -------------------------------------------------------------------------
    # Traceparent Header
    # -------------------------------------------------------------------------

    fn to_traceparent(self) -> String:
        """
        Format context as traceparent header value.

        Format: {version}-{trace-id}-{span-id}-{flags}
        Example: 00-4bf92f3577b34da6a3ce929d0e0e4736-00f067aa0ba902b7-01
        """
        return (
            "00-"
            + self.trace_id
            + "-"
            + self.span_id
            + "-"
            + TraceFlags.to_string(self.trace_flags)
        )

    @staticmethod
    fn from_traceparent(header: String) -> TraceContext:
        """
        Parse traceparent header value.

        Args:
            header: traceparent header value

        Returns:
            TraceContext (invalid if parsing fails)
        """
        var ctx = TraceContext()

        # Must be exactly 55 characters: 00-{32}-{16}-{2}
        if len(header) != 55:
            return ctx

        # Check delimiters
        if header[2] != "-" or header[35] != "-" or header[52] != "-":
            return ctx

        # Parse version (must be "00")
        var version = header[:2]
        if version != "00":
            # Future versions might have different formats
            # For now, only support version 00
            return ctx

        # Parse trace ID
        var trace_id = header[3:35]
        if not is_valid_trace_id(trace_id):
            return ctx

        # Parse span ID
        var span_id = header[36:52]
        if not is_valid_span_id(span_id):
            return ctx

        # Parse flags
        var flags_str = header[53:55]
        var flags = TraceFlags.from_string(flags_str)

        ctx.trace_id = trace_id
        ctx.span_id = span_id
        ctx.trace_flags = flags

        return ctx

    # -------------------------------------------------------------------------
    # Header Injection/Extraction
    # -------------------------------------------------------------------------

    fn to_headers(self) -> Dict[String, String]:
        """
        Create headers dict for outgoing request.

        Returns dict with traceparent (and tracestate if present).
        """
        var headers = Dict[String, String]()

        if self.is_valid():
            headers["traceparent"] = self.to_traceparent()
            if len(self.trace_state) > 0:
                headers["tracestate"] = self.trace_state

        return headers

    @staticmethod
    fn from_headers(headers: Dict[String, String]) -> TraceContext:
        """
        Extract trace context from incoming request headers.

        Looks for traceparent and tracestate headers.
        """
        var traceparent = ""
        var tracestate = ""

        # Case-insensitive header lookup
        for key in headers:
            var lower = key[].lower()
            if lower == "traceparent":
                traceparent = headers[key[]]
            elif lower == "tracestate":
                tracestate = headers[key[]]

        if len(traceparent) == 0:
            return TraceContext()

        var ctx = TraceContext.from_traceparent(traceparent)
        ctx.trace_state = tracestate

        return ctx

    # -------------------------------------------------------------------------
    # Context Creation
    # -------------------------------------------------------------------------

    @staticmethod
    fn new_root() -> TraceContext:
        """Create new root trace context."""
        return TraceContext(generate_trace_id(), generate_span_id(), TraceFlags.SAMPLED)

    @staticmethod
    fn new_child(parent: TraceContext) -> TraceContext:
        """Create child context from parent."""
        return TraceContext(
            parent.trace_id,
            generate_span_id(),
            parent.trace_flags,
            parent.trace_state,
        )

    fn child(self) -> TraceContext:
        """Create child context from this context."""
        return TraceContext.new_child(self)

    # -------------------------------------------------------------------------
    # Span Creation Helper
    # -------------------------------------------------------------------------

    fn with_span_id(self, new_span_id: String) -> TraceContext:
        """Create new context with different span ID."""
        return TraceContext(self.trace_id, new_span_id, self.trace_flags, self.trace_state)


# =============================================================================
# Baggage (Optional)
# =============================================================================


@value
struct Baggage:
    """
    W3C Baggage for cross-service context propagation.

    Carries user-defined key-value pairs across service boundaries.
    Not for tracing - for business context like user ID, tenant ID, etc.
    """

    var items: Dict[String, String]
    """Baggage key-value pairs."""

    fn __init__(out self):
        """Create empty baggage."""
        self.items = Dict[String, String]()

    fn set(inout self, key: String, value: String):
        """Set baggage item."""
        self.items[key] = value

    fn get(self, key: String, default: String = "") -> String:
        """Get baggage item."""
        if key in self.items:
            return self.items[key]
        return default

    fn has(self, key: String) -> Bool:
        """Check if baggage has key."""
        return key in self.items

    fn remove(inout self, key: String):
        """Remove baggage item."""
        if key in self.items:
            # Note: Dict doesn't have pop() - would need to rebuild
            pass

    fn to_header(self) -> String:
        """
        Format baggage as header value.

        Format: key1=value1,key2=value2
        """
        var parts = List[String]()
        for key in self.items:
            parts.append(key[] + "=" + self.items[key[]])

        var result = String("")
        for i in range(len(parts)):
            if i > 0:
                result += ","
            result += parts[i]

        return result

    @staticmethod
    fn from_header(header: String) -> Baggage:
        """Parse baggage header value."""
        var baggage = Baggage()

        if len(header) == 0:
            return baggage

        var pairs = header.split(",")
        for pair in pairs:
            var kv = pair.split("=")
            if len(kv) == 2:
                baggage.items[kv[0].strip()] = kv[1].strip()

        return baggage


# =============================================================================
# Context Storage (Thread-Local Simulation)
# =============================================================================


var _current_context: TraceContext = TraceContext()
"""Current active trace context (global, not thread-local)."""

var _current_baggage: Baggage = Baggage()
"""Current active baggage (global, not thread-local)."""


fn get_current_context() -> TraceContext:
    """Get current active trace context."""
    return _current_context


fn set_current_context(ctx: TraceContext):
    """Set current active trace context."""
    global _current_context
    _current_context = ctx


fn get_current_baggage() -> Baggage:
    """Get current active baggage."""
    return _current_baggage


fn set_current_baggage(baggage: Baggage):
    """Set current active baggage."""
    global _current_baggage
    _current_baggage = baggage


fn clear_context():
    """Clear current context and baggage."""
    global _current_context, _current_baggage
    _current_context = TraceContext()
    _current_baggage = Baggage()
