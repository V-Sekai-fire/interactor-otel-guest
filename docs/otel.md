# OpenTelemetry in a guest

This guest is a port of the engine's `open_telemetry` module to SafeGDScript. The module
(`modules/open_telemetry` of the engine source) holds spans, metrics and logs, builds their OTLP/JSON
bodies, and sends them with the engine's `HTTPClient`. A sandbox guest cannot open a socket, so the
guest builds and owns the bodies and the host sends them.

## Calls

| Call | Does |
| --- | --- |
| `reset(service, scope, seed)` | Sets the resource and scope, seeds the id generator, and starts a trace. |
| `new_trace()` | Starts another trace id. |
| `start_span(name, parent, kind, now_ns)` | Returns the 16-hex span id. `parent` is empty for a root. |
| `set_attr_s/i/f/b(id, key, value)` | Adds an attribute as the OTLP `stringValue`, `intValue` (a decimal string), `doubleValue` or `boolValue`. |
| `add_event(id, name, now_ns)`, `set_status(id, code, message)` | As the module's. |
| `end_span(id, now_ns)` | Moves the span to the queue. |
| `drain()` | One `resourceSpans` body of every ended span, or `""` when none. |
| `counter_add`, `gauge_set`, `histogram_record` | One metric for each name, kept until drained. A counter is a delta sum, a gauge keeps its last value, a histogram has the bounds 1, 5, 10, 25, 50, 100, 250, 500 and 1000. |
| `drain_metrics()` | One `resourceMetrics` body, or `""`. |
| `log(level, body, span_id, now_ns)` | Level is `TRACE`, `DEBUG`, `INFO`, `WARN`, `ERROR` or `FATAL`; a span id ties the record to the current trace. |
| `drain_logs()` | One `resourceLogs` body, or `""`. |

Times are decimal strings of Unix nanoseconds, because they pass the largest integer a JSON reader
holds. The host reads the clock; the guest has none that it may trust.

## What differs from the module

- The module's WAL, its sinks and the engine logger hook stay in the host. The guest queues in memory.
- The module put `asDouble` on a histogram point, which OTLP rejects. The guest sends `count`, `sum`,
  `bucketCounts` and `explicitBounds`.
- Ids come from a seeded xorshift the host supplies, so two seeds give two id streams and one seed
  repeats.

## Check

    godot --headless --path . -s tests/otel_gate.gd [-- --control=shortid|orphan|edge|severity|gaugesum|samesalt]

It prints `RESULT: PASS`. Each planted control must print `RESULT: FAIL the planted <name> was caught`.

## Sending

    OTEL_EXPORTER_OTLP_ENDPOINT=<base> OTEL_EXPORTER_OTLP_HEADERS="<header>=<value>" elixir tools/otlp_post.exs traces <body.json>
