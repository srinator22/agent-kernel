# Security, secrets, exposure

- Private by default: proprietary code and data stay private until a human
  authorizes otherwise.
- Never commit passwords, tokens, keys, certificates, connection strings,
  or production data. The gitleaks scan in check.sh is not optional.
- Secrets live in the approved store for the project - never in code, in
  committed config, in logs, in build artifacts, or in screenshots.
- Least privilege per identity: each token and service account is scoped
  to what that identity actually needs.
- Widening exposure requires explicit human authorization first: making a
  repo public, removing auth, widening network access, opening a public
  endpoint.
- Validate imports and uploads: file type, size, recursion depth, and
  decompression limits before processing.
- Normalize paths; reject traversal; never write outside the intended
  root.
- Never execute imported content; never interpolate untrusted data into
  shell commands.
- Review every lockfile change; dependencies are an attack surface.
- An exposed secret is rotated immediately; then the exposure path is
  fixed and a check added.
