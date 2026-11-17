#!/usr/bin/env bash
# check.sh always section, a started (adopted) project: template-only real-
# tree assertions skip there.
# Shared fixtures: check_always_lib.sh.
set -uo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/check_always_lib.sh" || { echo "$0: cannot load check_always_lib.sh; stopped before writing anything" >&2; exit 2; }

sec_started() {
# ---- a started project: real-tree parity both ways; the copy runs in CI ----
# A fact about the template's own tree, so it runs only in template mode. In a
# started project this repository IS the started project, and its own
# ./scripts/check.sh run is the proof; copying it again would recurse and test
# the project's tree against the template's expectations.
if t_started; then
  t_na "a started project passes check.sh with tests/template kept: this repository is a started project (.start-done); covered by its own ./scripts/check.sh run"
else
  # Both branches of the real-tree parity case are asserted: here, on the
  # template tree, it runs; in the adopted-project CI copy it prints n/a. The
  # executable-bit check is off for this run: where chmod cannot set the bit it
  # prints its own n/a line, which says nothing about the parity case.
  run env T_EXEC_CHECK= bash "$T_ROOT/tests/template/test_blueprint_parity.sh"
  assert_contains "on the template tree the real parity case runs" "ok   the real blueprint and required list agree"
  assert_not_contains "on the template tree no case is n/a" "n/a  "
  # The started copy of this tree (lessons reset, stack wired, Template line,
  # .start-done) running the full gate with tests/template kept is the
  # adopted-project CI job, which also asserts the nested n/a lines this file
  # and test_blueprint_parity.sh print there. Running that copy here as well
  # ran the whole suite a second time inside every check.sh (2220 s of a
  # local run, 2026-11-18) for no coverage the job lacks.
  t_ok "the started-project copy runs in the adopted-project CI job (ci.yml)"
  t_check_exec "started project"
  t_cleanup
fi
}

sec_started
t_finish
