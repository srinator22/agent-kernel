# Architecture and boundaries

- Domain and analysis logic stays independent from UI, storage, hosting,
  and vendor SDKs.
- Dependencies point inward through explicit contracts; the core imports
  nothing from the outer layers.
- External systems (APIs, databases, filesystems, clocks, queues) sit
  behind adapters.
- Validate and normalize at the boundary; pass typed values into the core.
  The core never parses raw input.
- Document units, sign conventions, coordinate frames, sampling
  assumptions, and missing-value behavior at the interface where they
  apply.
- Expensive work runs off the UI thread.
- Async UI is guarded against stale results: in-flight requests are
  cancelled or versioned; a late response must not overwrite a newer one.
- Unavailable controls are disabled with a reason or omitted, never left
  to fail on click.
- Boundary rules are enforced mechanically (import/lint rules wired by
  start), not by convention.

Dependency direction:

    UI -> workflows -> pure core
    external systems -> adapters -> contracts (defined by the core)
