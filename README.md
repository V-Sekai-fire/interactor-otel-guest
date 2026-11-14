# interactor-otel-guest

Spans, metrics and logs as OTLP/JSON bodies, built in a sandbox guest. It ports the engine's `open_telemetry` module; the host sends the bodies.

- `otel.sgd`: the guest.
- `tests/otel_gate.gd`: the gate and its planted controls.
- `tools/otlp_post.exs`: posts a drained body to a collector.
- `docs/otel.md`: the calls and what differs from the module.
