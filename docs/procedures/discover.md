# Discover - capability discovery before start

Run once per project, before `docs/procedures/start.md` (its step 0 calls
this); re-run only when the capability map is stale (a retro finds it wrong).
Output is `docs/CAPABILITY_MAP.md`; start reads it. Cost: an hour here
saves days later. The PCB project found it needed a routability checker,
a fan-out generator and a board-from-netlist builder only after weeks of
manual work; each was a half-day tool. Find such gaps now, not midway.

Back to back with start there is ONE batched interview, not two: discover's
one-paragraph description question is merged into start's batch, profiles are
chosen once (discover suggests, start records), the risk register is written
once, and step 8 below is part of the same reply as start's questions. Tool
inventory runs per activity with the stack named in the description, or "any"
when it is unknown; start re-checks the stack-specific tools.

Input: the owner's one-paragraph project description. If missing, ask
for exactly that and nothing else.

1. Activities. List every activity the project will contain: design,
   build, test, document, measure, publish, operate (add others the
   description implies). Classify each as automate (agent does and a
   check proves it), semi-automate (agent does, human checks a named
   artefact), or human only (judgment, physical action, sign-off). Write
   the reason for each class in one line.
2. Tool inventory. Per activity, list:
   - CLI tools that exist; verify each with `<tool> --version` and record
     the output. Not installed is a finding, not an assumption.
   - MCP servers that exist. Policy: CLI over MCP (manifest.md). An MCP
     server needs an ADR with the reason no CLI works, and is reviewed as
     attack surface (docs/rules/security.md).
   - What is missing: activities with no tool, or only a manual route.
3. Tool-building list. For each missing tool that would remove a manual
   step or a late-discovered defect class, one row: name, inputs,
   outputs, pass criteria (what proves the tool is right), estimate in
   hours, hours saved over the project. Rank by hours saved divided by
   hours to build. Rows go to `BACKLOG.md` as the first tasks after
   start, before feature work.
4. Harness and model plan. Assign tiers (docs/rules/models.md) to roles:
   advisor, worker, reviewer, monitor, explorer. List the harness
   features the project relies on (background jobs, workflows, hooks,
   scheduled tasks) and the fallback when a harness lacks each one. Mark
   every claim about harness limits VERIFY with today's date.
5. Profiles. Read `docs/profiles/README.md`; pick every profile whose
   scope the project touches (a project may take several). Record each
   profile with the reason, and the gates and tools it adds. Profile
   tools join the step 3 list.
6. Risk register. Name what AI must never do unasked in this project:
   orders and purchases, deploys, uploads to devices or hosts, deletions,
   external messages, publishing, cost changes, physical actuation. Each
   row states the action, why it is gated, and who approves (kernel rules
   12 and 15). Flag any action whose approval must be per-instance.
7. Write `docs/CAPABILITY_MAP.md` with the date and six sections that
   match steps 1 to 6, in the same order and with the same headings. A
   section with nothing to say states "none" and the reason; never omit
   it.
8. Hand-off: tell the owner the three highest-ranked tools, the profiles
   chosen, and the risk-register rows needing a standing decision. Start
   copies the profile choice and risk rows into Project decisions.

Reread the map at each retro; a tool built or a gap closed updates it in
the same commit.
