"""
Console Exporter

Exports spans to console/stdout for debugging and development.
Useful for local development and testing.

Example:
    var exporter = ConsoleExporter()
    exporter.export(spans)
"""

from ..span import Span, SpanKind, SpanStatus
from ...mojo_json.src import JsonValue, JsonObject, serialize


# =============================================================================
# Console Exporter Configuration
# =============================================================================


@value
struct ConsoleExporterConfig:
    """Configuration for console exporter."""

    var pretty_print: Bool
    """Whether to pretty-print JSON output."""

    var include_timestamps: Bool
    """Whether to include timestamps in output."""

    var color_output: Bool
    """Whether to use ANSI colors."""

    var prefix: String
    """Prefix for each line."""

    fn __init__(out self):
        """Create default configuration."""
        self.pretty_print = False
        self.include_timestamps = True
        self.color_output = False
        self.prefix = "[TRACE]"


# =============================================================================
# Console Exporter
# =============================================================================


struct ConsoleExporter:
    """
    Exports spans to console output.

    Each span is printed as a JSON object on a single line.
    Useful for debugging and development.
    """

    var config: ConsoleExporterConfig
    """Exporter configuration."""

    var spans_exported: Int
    """Total spans exported."""

    fn __init__(out self):
        """Create console exporter with defaults."""
        self.config = ConsoleExporterConfig()
        self.spans_exported = 0

    fn __init__(out self, config: ConsoleExporterConfig):
        """Create console exporter with configuration."""
        self.config = config
        self.spans_exported = 0

    fn export(inout self, spans: List[Span]) -> Int:
        """
        Export spans to console.

        Args:
            spans: List of spans to export

        Returns:
            Number of spans exported
        """
        for i in range(len(spans)):
            self._export_span(spans[i])
            self.spans_exported += 1

        return len(spans)

    fn export(inout self, span: Span) -> Int:
        """Export single span to console."""
        self._export_span(span)
        self.spans_exported += 1
        return 1

    fn _export_span(self, span: Span):
        """Export single span."""
        var output = self.config.prefix + " "

        if self.config.color_output:
            output += self._color_for_status(span.status_code)

        if self.config.pretty_print:
            output += self._format_pretty(span)
        else:
            output += span.to_json_string()

        if self.config.color_output:
            output += "\033[0m"  # Reset color

        print(output)

    fn _format_pretty(self, span: Span) -> String:
        """Format span as pretty-printed output."""
        var lines = List[String]()

        lines.append("Span: " + span.name)
        lines.append("  TraceID: " + span.trace_id)
        lines.append("  SpanID:  " + span.span_id)

        if len(span.parent_span_id) > 0:
            lines.append("  Parent:  " + span.parent_span_id)

        lines.append("  Kind:    " + SpanKind.name(span.kind))
        lines.append("  Status:  " + SpanStatus.name(span.status_code))
        lines.append("  Duration: " + str(span.duration_ms()) + "ms")

        if len(span.attributes) > 0:
            lines.append("  Attributes:")
            for key in span.attributes:
                lines.append("    " + key[] + ": " + span.attributes[key[]])

        if len(span.events) > 0:
            lines.append("  Events: " + str(len(span.events)))

        var result = String("")
        for i in range(len(lines)):
            if i > 0:
                result += "\n"
            result += lines[i]

        return result

    fn _color_for_status(self, status: Int) -> String:
        """Get ANSI color code for status."""
        if status == SpanStatus.OK:
            return "\033[32m"  # Green
        elif status == SpanStatus.ERROR:
            return "\033[31m"  # Red
        else:
            return "\033[33m"  # Yellow

    fn shutdown(self):
        """Shutdown exporter (no-op for console)."""
        pass

    fn force_flush(self):
        """Force flush (no-op for console)."""
        pass


# =============================================================================
# Simple Logging Exporter
# =============================================================================


struct SimpleLogExporter:
    """
    Minimal exporter that logs span summaries.

    Output format: [TRACE] {name} ({duration}ms) - {status}
    """

    var spans_exported: Int

    fn __init__(out self):
        """Create simple log exporter."""
        self.spans_exported = 0

    fn export(inout self, spans: List[Span]) -> Int:
        """Export spans as log lines."""
        for i in range(len(spans)):
            var span = spans[i]
            var line = (
                "[TRACE] "
                + span.name
                + " ("
                + str(span.duration_ms())
                + "ms) - "
                + SpanStatus.name(span.status_code)
            )

            if span.has_parent():
                line += " [parent: " + span.parent_span_id[:8] + "...]"

            print(line)
            self.spans_exported += 1

        return len(spans)


# =============================================================================
# Convenience Functions
# =============================================================================


fn console_exporter() -> ConsoleExporter:
    """Create default console exporter."""
    return ConsoleExporter()


fn pretty_console_exporter() -> ConsoleExporter:
    """Create pretty-printing console exporter."""
    var config = ConsoleExporterConfig()
    config.pretty_print = True
    return ConsoleExporter(config)


fn simple_log_exporter() -> SimpleLogExporter:
    """Create simple log exporter."""
    return SimpleLogExporter()
