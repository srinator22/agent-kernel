# ADR - record a decision in docs/decisions/

Record an architecture, tooling, data-policy, methodology or scope decision
that a later session might re-debate, the moment it is made. Not for bug
fixes or routine features. `scripts/adr.sh check` runs in every
`./scripts/check.sh` and enforces the numbering and the format below.

Records live in `docs/decisions/` unless the AGENTS.md Project
decisions line `- Decision records: <folder>` names another folder in the
repository. Records in another known ADR folder (`docs/adr/`, `adr/`,
`doc/adr/`) fail the check
instead of passing unchecked.

1. Create the file with `scripts/adr.sh new "<Decision title>"`. It takes
   the next number (highest `NNNN` plus one, zero-padded to four digits),
   derives a kebab-case slug, writes
   `docs/decisions/NNNN-<slug>.md` from the template and prints the path.
   Read the newest existing ADR first and match its tone.
2. Fill every placeholder; the check fails while a `{{` remains. Format:
   a title line `# NNNN - Decision title`, `Date: YYYY-MM-DD`,
   `Status: accepted`, then three sections. Context: the forces and the
   numbers that made the decision necessary, each serious alternative and
   why it lost. Decision: what was chosen, in a few sentences.
   Consequences: what gets easier or harder, the downsides, open questions.

3. Keep it short and factual: plain hyphens only, quote the numbers,
   observational tone (kernel rule 20).
4. If the decision changes how the system is built, update
   `docs/ARCHITECTURE.md` in the same commit.
5. If it reverses an earlier ADR, change the old one's status line to
   `Status: superseded by NNNN (YYYY-MM-DD)`. An accepted ADR's body is never
   rewritten; the status line is the only in-place edit. A later change to
   what it says is a dated `## Amendment YYYY-MM-DD` section appended at the
   end, or a superseding ADR. The check verifies that the superseding ADR
   exists.
6. Anything that cites the ADR (a procedure, rule or profile file) names it
   as `docs/decisions/NNNN`; `scripts/adr.sh check` verifies the cited file
   exists, so create the ADR in the same change as the citation.
7. Run `scripts/adr.sh check`. With an `origin` remote it fetches the
   default branch (`origin/HEAD`, else `main`) and fails when an ADR this
   branch adds reuses a number that branch already gives another file:
   renumber yours after its last (`git mv`, then fix the title line).
   Offline it prints that the comparison was skipped;
   run it again online before merging. Then commit as
   `docs: add ADR NNNN <short title>` with a body that says why the
   decision was made (kernel rule 6). Never tag or push outside the
   project's recorded git workflow.
