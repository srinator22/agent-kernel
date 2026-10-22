# Evidence levels and typed record IDs

A fixed scale for how strong the evidence behind a quantitative statement is,
and a pattern for typed, never-reused record IDs. The article, component,
decision and experiment procedures and the engineering-reviewer and
researcher agents all refer to this page. Adopt it by copying it to
`docs/procedures/evidence-levels.md`.

This scale answers "how was this number obtained". It is complementary to the
status words of the scientific profile (SC-8), which answer "how far has this
model got". A project using both states both.

## Evidence hierarchy

The scale is fixed. A lower number is stronger evidence.

| Level | Meaning |
|---|---|
| E1 | Verified physical measurement, reproducible, with the raw data stored |
| E2 | Manufacturer datasheet or dimensional specification |
| E3 | Peer-reviewed publication |
| E4 | Authoritative engineering reference or standard |
| E5 | Validated numerical simulation (validated against E1 data) |
| E6 | Reproducible community engineering project or independent test |
| E7 | Preliminary numerical estimate |
| E8 | Unverified claim or hypothesis, including seller and marketing figures |

Reading rules:

- A manufacturer datasheet value is E2 and is labelled as a claim of the
  manufacturer; it is not "measured". A seller listing or marketing figure
  with no datasheet behind it is E8.
- A simulation that has not been checked against measurement is E7, not E5.
  A simulation is never a test.
- An estimate is never stated as a fact. A result that rests on an E7 or E8
  input carries no conclusion stronger than that input supports.
- The level of a derived number is the weakest level among its inputs.

## Rules

1. Every quantitative statement carries units, an evidence level and a
   source. A number with no level and source is not recorded; if it cannot be
   verified it is written `unverified` with the reason (kernel rule 14).
2. Revalidation. When a component, geometry, model, assumption or decision
   changes, every record that lists it as a dependent is marked
   `revalidate <date>` in the same commit. The mark is cleared only by a
   recorded re-check. Nothing is silently kept.
3. IDs are sequential per kind and never reused. A superseded row stays in
   place and gains `superseded by <ID>`.
4. A design decision is logged before it is implemented, and only the human
   approves it.

## Typed record IDs (placeholder pattern)

Each kind of engineering record gets one short prefix chosen by the project
(two or three capital letters) and a zero-padded sequential number, written
`<PREFIX>-nnn`. The prefix identifies the kind, so an ID read in a table or a
commit message says what it points at.

| Record kind | Holds | Home (default, change in one place) |
|---|---|---|
| assumption | A statement used but not yet established as fact, with level and status | `docs/engineering/ASSUMPTIONS.md` |
| knowledge | An established fact with value, units, level, source, revalidate-when | `docs/engineering/KNOWLEDGE.md` |
| hypothesis | A testable statement and what would decide it | `docs/engineering/HYPOTHESES.md` |
| failed experiment | A negative result and what not to repeat | `docs/engineering/FAILED_EXPERIMENTS.md` |
| design decision | A decision logged before implementation, with its evidence chain | `docs/engineering/DESIGN_DECISIONS.md` |
| requirement | A verifiable requirement, grouped by area, with its verification method | `docs/engineering/REQUIREMENTS.md` |
| open question | A question, why it matters and what is needed to answer it | `docs/engineering/OPEN_QUESTIONS.md` |
| experiment | One physical test with its record and immutable raw data | `experiments/INDEX.md` |
| component | One candidate or selected part | `bom/BOM.md` |
| literature | One cited reference | `docs/references/README.md` |
| style preference | One editorial preference (article procedure) | `articles/STYLE.md` |

Project process decisions (architecture, tooling, workflow) are not engineering
decisions; they are ADRs under `docs/decisions/` (see the `adr` skill).

A project records its chosen prefixes in one table in its own copy of this
page, and a test or script can check that every ID cited in a record exists
and that none is reused.
