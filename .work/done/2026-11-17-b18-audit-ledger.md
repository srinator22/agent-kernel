# Test audit ledger: tests/template/*.sh (read-only, 2026-11-17)

Method and limits. Line counts are non-blank lines (scripts/test-budget.sh report, 11058 in total). Every file's header
comment was read; the candidate duplicates below were confirmed by reading the cited lines, the rest of each file was not
re-read line by line. No test was changed or removed. Rule 2 applies to every later action on this ledger: a candidate is
merged or removed only after the "believable bug" named here is shown to be caught by the surviving owner, and never when
it is the only regression guard (check docs/DEFECT_MEMORY.md first).

## 1. Contracts owned per file

| File (lines) | Contract it owns |
|---|---|
| test_adr.sh (261) | adr.sh check (names, contiguous numbers, title, Date/Status, superseded-by, placeholders) and new (next number, slug, template fails check) |
| test_blueprint_parity.sh (99) | BLUEPRINT tree and required-file list agree both ways by full path, at any tree size |
| test_check_always.sh (603) | check.sh "always" section runs in project and template mode, --quick never skips it, each failing sub-check is named and stops the stack block |
| test_ci_watch.sh (238) | expected workflows derived from changed files and push filters; root-commit fallback; --expect/--base; failing job log tail |
| test_codex_hooks.sh (256) | .codex/hooks.json shape and exact commands; each command run with recorded payloads on Unix and Windows; launcher errors |
| test_destructive_guard.sh (765) | forbidden removal targets and destructive git forms from both shells; settings wiring |
| test_doc_eval.sh (81) | question-table validation and the brief never carrying key or sources |
| test_doctor.sh (274) | each tool checked by running it, install hint per system, nothing installed |
| test_dream.sh (1392) | dream digest, once-only offsets, due decision, hygiene report, scorecard |
| test_dream_fleet.sh (170) | fleet digest: UPSTREAM entries, caps and cut notices, transcripts opt-in, read-only |
| test_feedback.sh (291) | feedback hook logging, kind guess, context line, always exit 0 |
| test_find_python.sh (98) | the Python probe skips a Store stub; sourcing scripts leave no variable; no script picks python3 by command -v alone |
| test_fleet.sh (124) | fleet table statuses (OK, BEHIND, BAD-LINE, NO-BASE, MISSING), list parsing, nothing written in projects |
| test_hooks_dispatch.sh (121) | hooks.d dispatch order, skip rules, exit-code passthrough, fail-closed PreToolUse, settings wiring |
| test_kernel_hash.sh (63) | verify/update/drift for the kernel hash, CRLF-insensitive, missing marker |
| test_lessons.sh (632) | lesson cap and fields, PENDING/QUARANTINE entries, skills mirror and cap, rules size, use, expire, stats, match |
| test_new_task.sh (141) | new-task slug/mode validation, refusal during a task, scaffolded TASK.md |
| test_preferences.sh (461) | preference register formats, failures naming file and row, write_rows, port |
| test_private_terms.sh (260) | private-terms check and history, masked output, term text never printed |
| test_profile_tools.sh (46) | profile and library tools keep their own tests green in the template |
| test_profiles.sh (85) | the one Profiles: line parser, allowed and refused forms, parity with template-sync and lessons.sh |
| test_quickgate.sh (32) | quickgate exit 2 without a --quick lane, otherwise delegates and returns check.sh status |
| test_selftest.sh (338) | selftest quarantine, parallel runs, summary counts, signals, exec-bit wiring, no temp leaks |
| test_session_context.sh (364) | mode line, rule-7 reminder, git block, in-progress task, outside-git output |
| test_shell_stdin_hook.sh (104) | the stdin-refusal hook, its wiring and launcher fallbacks |
| test_start_reset_lessons.sh (132) | lessons files reset to headers, --check, idempotence, refusals leave files untouched |
| test_stop_gate.sh (156) | Stop hook allow/block decisions, quick gate only when criteria are ticked, cache by tree state |
| test_taskgraph.sh (164) | taskgraph unknown deps, overlaps, cycles, tier/status values, ready, waves, set |
| test_tasklint.sh (449) | tasklint check/ship rules, evidence for ticked criteria, assumptions, verdict tree match, CRLF |
| test_taste.sh (431) | taste digest and the non-row parts of apply (evidence rule, 160-char cap, once-only) |
| test_taste_project.sh (314) | taste is project-scoped, writes nothing under home, row writer, template-mode refusal |
| test_template_release.sh (217) | release versioning, notes grouping, KERNEL CHANGED line, --tag guards |
| test_template_sync.sh (655) | three-way sync, guards, exit codes, DIFF-only files, skills cap after a sync |
| test_test_budget.sh (105) | test-budget thresholds, raise lines, malformed BUDGET, absent skip, counting rules |
| test_test_files.sh (158) | each test loads lib.sh safely; tracked tests are executable in the index; lib.sh t_check_exec and t_parallel |
| test_tree_id.sh (94) | tree-id equals the committable tree, excludes .work and CHANGELOG, real index untouched |
| test_worker_git_guard.sh (72) | worker commit/push block from both shells and the worker agent wiring |

## 2. Candidate duplicate coverage

Each row: location, what overlaps, the believable bug that justifies KEEPING it, or why it is redundant.

1. test_check_always.sh:245-254 vs test_lessons.sh (rules cap case) - check.sh is asked to fail on a 41-line rules file and
   to report it with and without --quick; the size rule itself is owned by test_lessons.sh. Keep ONE check.sh case (wiring:
   check.sh calls lessons.sh check and stops before the stack block, lines 249-251) and the --quick case (253-254). The
   believable bug for keeping: check.sh drops the lessons call under --quick. Redundant part: the "has 41 lines" message
   assert (249) restates lessons.sh output already asserted in test_lessons.sh.
2. test_check_always.sh:63-64 and :387 ("the always section ran: lessons / task graph") vs the failure cases at :220-232,
   :249-254, :268-269 - the success-line asserts prove only that a sub-check printed a line; each failure case already proves
   the sub-check is wired. Believable bug for keeping 63-64: check.sh prints the line but skips the call in one mode (then
   the failure cases catch it, so 63-64 are weaker). Candidate: keep :387 (template mode), fold :63-64 into one assert.
3. test_check_always.sh:69-76 (SW-15 verify skill) and test_lessons.sh:121-128 (skills mirror drift) - the SW-15 case
   moves both skill copies out only to keep the mirror check quiet (comment at :69), so the two cases are independent by
   construction; no duplicate. Listed so a later pass does not merge them.
4. test_lessons.sh:121-128 (mirror drift) vs test_template_sync.sh:424-478 (skills cap after a sync) - different
   contracts (drift vs cap on sync); not duplicates. test_template_sync.sh:455-478 repeats the cap count across five
   cases (455, 459, 465-466, 477-478, 524); the 459 and 477 not-contains cases are the same bug (cap counted wrongly) seen
   from two sides. Candidate: merge 459 and 477 if one fixture can show both; keep 465-466 and 478 (over-cap, uncounted).
5. test_destructive_guard.sh:788-795 (settings wiring) vs test_shell_stdin_hook.sh:50-54 (same matcher group
   `Bash|PowerShell` read from .claude/settings.json) - both assert the guard command is wired under the same matcher;
   54 re-asserts the destructive guard wiring that destructive_guard owns. Redundant: shell_stdin_hook.sh:54 (and its
   twin count) if destructive_guard.sh:791 stays. Believable bug for keeping 54: the stdin hook's registration replaces
   the guard in the same group (a real merge-conflict shape); keep one such "both remain" assert, drop the other.
6. test_destructive_guard.sh:56-70 (per-shell loop over both shells) and test_worker_git_guard.sh (payloads from both
   shells) - same loop shape, different guards; keep both. Within test_destructive_guard.sh:60-65, the root, root-glob and
   home targets, each with -rf and -fr spellings, are variants of one contract (root or home target refused). Believable
   bug for keeping each: a pattern that handles `/` but not `/*`, or `-rf` but not `-fr`; those are distinct, so keep all
   of them; they are cheap table rows, not duplicates.
7. test_taste_project.sh:331-332 (template mode refuses apply) vs test_preferences.sh:419, :511, :514 (template mode
   refuses write_rows, port dry run, port --apply) and test_template_release.sh (template-mode refusal) - the refusal is
   implemented separately in each script, so each owns its own. Candidate inside test_preferences.sh: 511 and 514 (dry run
   and --apply refused) share one guard; merge into one case with two asserts only if they share a fixture.
8. test_fleet.sh:5 (CRLF list files, comments) vs test_dream_fleet.sh:5 (CRLF and comments in the list) and
   test_template_sync.sh:588 (the ledger read with CRLF, comments, blank lines) - three list parsers with the same
   input shape. If fleet.sh and dream/fleet.py share a parser, one test owns it and the other keeps only the digest
   contract; if not, keep both. Action for the campaign: check whether the parser is shared first.
9. test_test_files.sh:59-77 and :146-167 (t_check_exec names a non-executable script; T_EXEC_CHECK=1 on a platform without
   bits) vs test_selftest.sh:337-353 (selftest exports T_EXEC_CHECK=1 and the probe to every file) vs test_check_always.sh:495-496
   (check.sh refuses a test file without the bit in the index) - three layers: helper, exporter, index gate. Not
   duplicates; the believable bugs differ (helper misses a script; selftest forgets to export; check.sh stops reading the
   index). Note test_test_files.sh:52-55 (tracked tests are executable) overlaps check.sh step 5g, which is the real gate;
   it is the weaker owner and a candidate to drop IF test_check_always.sh:495 stays and CI runs step 5g first (L018).
10. test_stop_gate.sh:83-109 (quick gate run counts) vs test_quickgate.sh (delegation and exit passthrough) - stop_gate uses
    a fake quickgate.sh (line 38), so it owns "when to run it"; quickgate owns "what it runs". No duplicate.
11. test_find_python.sh:105-107 (no `command -v python3` pick remains anywhere in scripts or tests) vs the per-script
    cases in the same file that source find-python.sh - the repository-wide grep already proves every script uses the
    helper, so the per-script cases (dream.sh, feedback-log.sh, check.sh 5f) prove behaviour with a Store stub, which the grep
    cannot. Keep both; believable bug: a script sources the helper but ignores its result.
12. test_tasklint.sh:452-471 (CRLF block, six asserts) vs test_tasklint.sh:420 (CRLF verdict) - two CRLF assert groups
    in one file for the same normalisation; the :456-463 group already runs check and ship paths. Candidate: drop :420 if
    :467 (CRLF autopilot PASS verdict on ship) covers the verdict comparison; believable bug for keeping 420: the
    "Reviewed tree:" line keeps its CR so the tree compare fails.
13. test_adr.sh (83 asserts, 261 lines) vs test_check_always.sh:276 - check.sh only needs one case that a failing adr.sh
    fails the gate; adr.sh's own rules stay in test_adr.sh. Already this shape (single assert at :276); no action.
14. test_dream.sh (1392 lines, 405 asserts) vs test_taste.sh (431) and test_taste_project.sh (314) - three files over the
    same dream/ python package. test_taste.sh and test_taste_project.sh both build synthetic transcripts and notes and both
    assert once-only offsets (taste.sh header: once-only offsets, once-only application) while test_taste_project.sh
    asserts project scope and no home writes. Largest candidate for consolidation by line count: audit the fixture
    builders first (shared builder would cut lines without removing a contract). test_dream.sh:547-603 (scorecard
    matcher cases with escaped pipes) are intricate parsing contracts; keep.
15. Within-file style duplication, not contract duplication: "cp_script check.sh kernel-hash.sh lessons.sh profiles.sh
    taskgraph.sh adr.sh tasklint.sh doc-eval.sh" repeats at test_check_always.sh:53, :286, :331, :569 (four fixtures with
    near-identical script lists). A shared helper in lib.sh would remove lines, not coverage.

## 3. Completed areas

None. This is a read-only first pass; no duplication has been removed.

## 4. Remaining work and unresolved risks

- Rows 1, 2, 4, 5, 7, 8, 9, 12 are concrete candidates needing a confirm-and-merge pass; rows 14 and 15 are the largest line savings.
- Not audited beyond header and sampled regions: test_dream.sh, test_template_sync.sh, test_preferences.sh, test_lessons.sh
  (the four largest after check_always). A later pass should read each fully.
- Fixtures (tests/template/fixtures/*, counted by the budget) include a byte copy of check.sh; its lines count twice by
  design and cannot be consolidated.
- Mutation evidence (a believable bug run against each owner) was not run for any candidate; the "believable bug" entries
  are hypotheses until run.
