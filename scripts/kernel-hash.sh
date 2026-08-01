#!/usr/bin/env bash
# kernel-hash.sh - the only sanctioned way to touch .kernel.hash.
#   --verify  recompute the kernel hash and compare it to .kernel.hash
#   --update  recompute and overwrite .kernel.hash (belongs in a human-approved commit)
# The kernel is the block in AGENTS.md from <!-- KERNEL:BEGIN --> through
# <!-- KERNEL:END --> inclusive. The extraction logic lives here and only here;
# check.sh calls this script rather than duplicating it.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
AGENTS="$ROOT/AGENTS.md"
HASH_FILE="$ROOT/.kernel.hash"

extract_kernel() {
  awk '/<!-- KERNEL:BEGIN -->/{f=1} f{print} /<!-- KERNEL:END -->/{exit}' "$AGENTS" | tr -d '\r'
}

compute_hash() {
  local block
  block="$(extract_kernel)"
  if ! printf '%s\n' "$block" | grep -q 'KERNEL:END'; then
    echo "ERROR: kernel markers not found in AGENTS.md" >&2
    exit 1
  fi
  printf '%s\n' "$block" | sha256sum | awk '{print $1}'
}

case "${1:-}" in
  --verify)
    if [[ ! -f "$HASH_FILE" ]]; then
      echo "ERROR: .kernel.hash is missing. Restore it, or run scripts/kernel-hash.sh --update in a human-approved commit." >&2
      exit 1
    fi
    current="$(compute_hash)"
    recorded="$(tr -d '[:space:]' < "$HASH_FILE")"
    if [[ "$current" != "$recorded" ]]; then
      cat >&2 <<'MSG'
========================================================================
KERNEL DRIFT DETECTED

The kernel block in AGENTS.md does not match .kernel.hash. The kernel
governs how this repository works and learns; it must never change
silently or as a side effect of another edit.

If the change is intentional and human-approved, run:
    scripts/kernel-hash.sh --update
and commit AGENTS.md together with .kernel.hash in the same commit,
noting the human approval in the commit body.

If you did not mean to touch the kernel, restore it:
    git diff AGENTS.md
    git checkout -- AGENTS.md
========================================================================
MSG
      exit 1
    fi
    echo "kernel-hash: OK ($current)"
    ;;
  --update)
    compute_hash > "$HASH_FILE"
    echo "kernel-hash: .kernel.hash updated to $(cat "$HASH_FILE")"
    echo "REMINDER: kernel edits require human approval; commit AGENTS.md and .kernel.hash together."
    ;;
  *)
    echo "usage: scripts/kernel-hash.sh --verify | --update" >&2
    exit 2
    ;;
esac
