"""
Trace Exporters

Exporters send spans to various backends:
- ConsoleExporter: Output to stdout (debugging)
- OtlpHttpExporter: Send to OTLP collectors (Jaeger, Tempo, etc.)
"""

from .console import (
    ConsoleExporter,
    ConsoleExporterConfig,
    SimpleLogExporter,
    console_exporter,
    pretty_console_exporter,
    simple_log_exporter,
)

from .otlp import (
    OtlpHttpExporter,
    OtlpExporterConfig,
    BatchExporter,
    otlp_exporter,
    batch_exporter,
)
