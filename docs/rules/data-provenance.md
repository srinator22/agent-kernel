# Data classes, provenance, hashing, what enters git

- Keep raw source, normalized data, features, labels, models, and reports
  distinct; never mix stages in one folder or file.
- No large raw datasets in git unless the repo is explicitly designed for
  them; large or private data lives where Project decisions says it does.
- Commit only minimal approved fixtures, each with linkage to its source.
- External sources are identified by SHA-256 digest in a manifest; never
  by credentials or private URLs.
- Preserve original counts; derive percentages and aggregates
  reproducibly from them, never store only the derived form.
- Never overwrite raw observations with adjusted values; adjustments are
  new columns or new files with their derivation recorded.
- Record absolute-vs-control semantics and units in the schema itself.
- Schemas are versioned; validation is strict; the duplicate policy is
  explicit and written down.
