# Checks and the per-issue ledger (hardware-pcb profile)

The question this file answers: has every issue we have had been logged and
converted into a test? The answer is a ledger with one row per issue and an
honest status, not a feeling. The pattern comes from a prior controller PCB
project whose ledger was a read-only inventory (test names and tool code were
read, not executed, so a named test proves a check exists, not that it passes
today).

## 1. Ledger pattern

One Markdown table per section, one row per issue, these columns:

| Column | Content |
|---|---|
| ID | Section letter plus number (A01), never reused |
| Issue | One sentence: what went wrong |
| Found | Date and the record where it was found |
| Logged | Where it is recorded (decision, question, rule, record) |
| Automated check today | Tool and test names that would flag it again, or `none` |
| Status | `covered`, `planned`, `not testable`, or `open gap` |
| Gap | What the check misses, the planned step, or the reason it cannot be tested |

Status definitions, each checkable:
- `covered`: a named tool or test in the gate would flag the issue again.
  `covered (partial)` states in Gap what it misses or that it runs by hand and
  not in the gate.
- `planned`: names the step and the tool that will check it (for example S0
  `check_routability`); a planned row with no step is invalid.
- `not testable`: Gap gives the reason (physical sample, bench, field, firmware,
  vendor claim, human walk, wrong hypothesis).
- `open gap`: a machine check is conceivable, none exists and none is planned.
  This fourth status exists because the honest total does not fit three.

Sections that worked: A records, documents and process; B schematic and
electrical findings; C layout rules and DRC; D routing method, tools and
process; E mechanical, parts and service access.

## 2. Rules

- PCB-L1 Every escaped issue gets a ledger row before its fix is made; the
  fix commit cites the ID.
- PCB-L2 A new check or test updates the Automated check column and the status
  in the same commit.
- PCB-L3 The summary counts equal the row counts; a script recomputes them and
  fails on a mismatch (`build`: `check_ledger`, exit 1 on a mismatch or an
  invalid row, 2 when the file cannot be parsed).
- PCB-L4 Open gaps are reported to the owner with a count and the highest-value
  few, never left to age silently.
- PCB-L5 A prose figure that appears in several documents (a count, a rating)
  is a ledger issue until a check ties it to the netlist or parameters file.
- PCB-L6 The ledger is regenerated or re-read at each milestone of the review
  ladder; stale `planned` rows are re-dated or closed.

## 3. Summary shape

The summary at the top of a ledger has one row per status and one count per
section; the cells below are placeholders, not data.

| Status | Rows | Meaning |
|---|---|---|
| covered | `<n>` (full, partial) | an automated check would flag it again |
| planned | `<n>` | a step of the layout plan or a prepared rule file will check it |
| not testable | `<n>` | no machine check possible |
| open gap | `<n>` | conceivable, no check, no plan |
| total | `<n>` | equals the number of rows |

Reading: the share of issues with neither a test nor a plan (open gaps) is the
number to drive down; the planned share shows what is already in motion. The
weight of severity is not in these counts, so the top few open gaps are named
beside them.

Example rows (illustrative, abridged from the pattern):

| ID | Issue | Check today | Status |
|---|---|---|---|
| A01 | Documents keep stale statements after a design change | `check_doc_sync` superseded terms, holes, connector edge (partial: only listed terms; history-word lines skipped) | covered (partial) |
| A02 | WARN lines with no owner | none | open gap |
| A03 | En and em dashes fail the repository CI | `check_doc_sync` typography | covered |
| A07 | A decision left "Proposed" after the board was built from it | `check_decisions` sees inconsistency only | not testable |
| A12 | The gate rewrites a tracked file in a read-only review | none | open gap |

Typical highest-value open gaps: DRC without zone refill in the gate, a
WARN-owner check, unit tests for the session tools, a net parser for the
planner, and a service-lane checker for parts a technician must reach.

## 4. Check inventory pattern

- Count the tools and tests by script (`check_*`, `sim_*`, test methods) and
  list which are gate steps and which run by hand; a check that is not a gate
  step is a gap (a prior project's ledger found simulations that ran by hand).
- Session tools without tests are listed explicitly (a guided routing session
  and a scripted router driver had none).
- The layout-rules table has a check column (a DRC rule, a script, partial,
  pending, review, none). The column is prose, so a ledger row tracks it going
  stale; a check comparing the column with the rule names would close it.
- Each planned row names its closing tool in a section "Checks to write", so
  planned never means "someone will think of something".

## Sources

Sources: distilled from four prior projects of the template owner (embedded
firmware, controller PCB, vibration data analysis, CAD add-in); project records
stay in those repositories.
