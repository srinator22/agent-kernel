#!/usr/bin/env bash
# fake-ruff.sh - stands in for ruff in the self-tests, so no self-test reaches a
# real ruff runner or the network (tests/template/lib.sh exports it as
# TEMPLATE_RUFF). It reproduces ruff's exit codes: 0 clean, 1 findings, 2 a
# config or usage error. Controls: FAKE_RUFF_LOG (append "<cwd>|<args>" per
# call), FAKE_RUFF_CHECK_RC, FAKE_RUFF_FORMAT_RC, FAKE_RUFF_SCRATCH_RC (used
# instead of the other two when the cwd is a check.sh scratch root,
# */template-ruff.*), FAKE_RUFF_VERSION_RC.
if [[ -n "${FAKE_RUFF_LOG:-}" ]]; then printf '%s|%s\n' "$PWD" "$*" >> "$FAKE_RUFF_LOG"; fi
case "${1:-}" in
  --version) echo "ruff 0.16.10 (fake-ruff.sh)"; exit "${FAKE_RUFF_VERSION_RC:-0}" ;;
  check|format) ;;
  *) echo "fake-ruff: unknown command: ${1:-}" >&2; exit 2 ;;
esac
if [[ "$PWD" == */template-ruff.* && -n "${FAKE_RUFF_SCRATCH_RC:-}" ]]; then
  rc="$FAKE_RUFF_SCRATCH_RC"
elif [[ "$1" == check ]]; then rc="${FAKE_RUFF_CHECK_RC:-0}"
else rc="${FAKE_RUFF_FORMAT_RC:-0}"
fi
if (( rc == 1 )); then echo "fake-ruff: 1 finding (E702)"; fi
if (( rc == 2 )); then echo "fake-ruff: config error" >&2; fi
exit "$rc"
