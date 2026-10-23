# Article - the writing and editorial workflow

Adopt by copying this file to `docs/procedures/article.md`, together with the
`writer` and `engineering-reviewer` agents and the `article` skill. Paths below
are defaults; change them in this one file if the project uses others.

States: Idea -> Research gathering -> Outline -> Draft -> Technical review
-> Editorial review -> Approved -> Published. The state lives in the
article's frontmatter and its folder under `articles/`. The human holds final
approval; nothing is published, uploaded or posted without the human's
explicit permission per article (kernel rule 15; no standing override exists
for publishing unless the human records one in Project decisions).

Layout: `articles/ideas/`, `articles/drafts/`, `articles/review/`,
`articles/approved/`, `articles/published/`, `articles/approved-examples/`,
plus `articles/README.md` (pipeline, categories, frontmatter) and
`articles/STYLE.md` (editorial preference memory).

Frontmatter every article carries: `title`, `state`, `category`, `sources`
(record IDs and paths), `evidence check status`, `drafted date`,
`reviewed by`.

1. Idea. One file in `articles/ideas/` with the category, the period it
   covers and the records it would draw on.
2. Research gathering. The writer agent lists what the records say
   happened in the period: experiments, decisions, knowledge changes,
   failures, git log, the human's notes. Gaps are listed as gaps, never
   filled by inference.
3. Outline. Sections with the record IDs each will cite. The human reads
   the outline and corrects emphasis.
4. Draft. Frontmatter as above, every factual statement traceable,
   evidence levels in plain words where they matter (see
   `docs/procedures/evidence-levels.md`). Approved `articles/STYLE.md`
   preferences applied; Proposed ones not.
5. Technical review. The `engineering-reviewer` agent checks every claim
   against its record and that no simulation reads as a test and nothing
   is fabricated. FAIL returns to Draft with the findings in the file.
6. Editorial review. The writer checks readability, structure, narrative,
   voice and style against the Approved preferences. The human edits.
7. Learning from the human's edits. The writer diffs original and edited
   drafts, separates one-off edits from durable preferences, and appends
   candidates to the Proposed section of `articles/STYLE.md` with the
   evidence (draft and line), a confidence and the date. Only the human
   moves a row to Approved, retires one, or changes one. A preference never
   overrides technical accuracy or the documentation requirements. This is
   the same gate as `docs/lessons/PENDING.md` (kernel rule 9); style memory
   stays in `articles/STYLE.md` so it never competes with process lessons.
8. Approved. The human states approval in chat; the file moves to
   `articles/approved/` with an `approved:` date. Passages the human names
   as exemplary go to `articles/approved-examples/`.
9. Published. Only on the human's explicit instruction naming the
   platform. Record the URL and date in the frontmatter; move the file to
   `articles/published/`. Short-form social updates are derived only from
   an Approved or Published article and go through the same approval.

Integrity rules: facts recorded in the project are distinguished from
commentary; never fabricate progress, measurements, photographs, experiments
or experiences; never present a simulation as a physical test.

Images: renders, screenshots and photographs are referenced by path and
listed in the frontmatter. Third-party or proprietary reference images are
never included in any article.

Style baseline for the writer (the project sets the voice in `STYLE.md`):
clear, personal but credible, honest about failures and uncertainty, detailed
where explanation adds value, no hype, no repetitive transitions, no
rhetorical padding, in the project's language variant, plain hyphens only.
