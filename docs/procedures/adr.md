# ADR - record a decision in docs/decisions/

Record an architecture, tooling, data-policy, methodology or scope decision
that a later session might re-debate, the moment it is made. Not for bug
fixes or routine features: commit bodies and the changelog carry those.
The record is permanent and short. `scripts/adr.sh check` runs in every
`./scripts/check.sh` and enforces the numbering and the format below.

The records live in `docs/decisions/` unless the AGENTS.md Project
decisions line `- Decision records: <folder>` names another folder inside
the repository (a project that already kept ADRs in, say, `docs/adr/`).
Every path below means that folder. Records found in another known ADR
folder (`docs/adr/`, `adr/`, `doc/adr/` and the like) fail the check
instead of passing unchecked.

1. Create the file with `scripts/adr.sh new "<Decision title>"`. It takes
   the next number (highest `NNNN` plus one, zero-padded to four digits),
   derives a lowercase kebab-case slug, writes
   `docs/decisions/NNNN-<slug>.md` from the template and prints the path.
   Read the newest existing ADR first and match its tone.
2. Fill every placeholder; the check fails while a `{{` remains. The
   format:

   ```markdown
   # NNNN - Decision title

   Date: YYYY-MM-DD
   Status: accepted

   ## Context

   The situation and the forces at play, with the numbers that made the
   decision necessary. Facts, not justification. Name the version that
   shipped it, if any. Each alternative that was seriously on the table,
   and the specific reason it lost, goes here too; if nothing else was
   considered, say so and say why.

   ## Decision

   What was chosen, stated plainly in a few sentences.

   ## Consequences

   What gets easier, what gets harder, what we are now committed to,
   honest about the downsides, and any open question the decision leaves.
   ```

3. Keep it short and factual: plain hyphens only, quote the numbers,
   observational tone (kernel rule 20).
4. If the decision changes how the system is built, update
   `docs/ARCHITECTURE.md` in the same commit.
5. If it reverses an earlier ADR, change the old one's status line to
   `Status: superseded by NNNN (YYYY-MM-DD)`. That status line is the only
   edit ever made to an accepted ADR; its body is never rewritten. The
   check verifies that the superseding ADR exists.
6. Anything that cites the ADR (a procedure, rule or profile file) names it
   as `docs/decisions/NNNN`; `scripts/adr.sh check` verifies the cited file
   exists, in template mode and after start alike, so create the ADR in the
   same change as the citation.
7. Run `scripts/adr.sh check`. With an `origin` remote it fetches the
   default branch (`origin/HEAD`, else `main`) and fails when an ADR this
   branch adds reuses a number that branch already gives another file:
   renumber yours after its last (`git mv`, then fix the title line).
   Offline or without a remote it prints that the comparison was skipped;
   run it again online before merging. Then commit as
   `docs: add ADR NNNN <short title>` with a body that says why the
   decision was made (kernel rule 6). Never tag or push outside the
   project's recorded git workflow.
