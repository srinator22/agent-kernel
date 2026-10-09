# Profile: data-analysis

## Purpose and risk

For projects that import raw instrument files or device logs and turn them into
findings. Risk: edited or corrupted evidence, silently guessed rows, captions
that overstate a source, a configured interval read as the real one, conclusions
drawn from one unexplained run, and analysis code that cannot be re-run.
Promote `docs/rules/data-provenance.md` into the AGENTS.md rules index; stack
with `scientific` when a claim is quantitative.

## Rules

- DA-1 Raw files are imported unchanged, never edited or overwritten; the import
  copy is hash-verified (SHA-256) against the source, and an existing file is
  never replaced.
- DA-2 Raw data paths are marked `-text` in `.gitattributes`, so line-ending
  normalisation cannot alter evidence; staged and blob hashes are compared.
- DA-3 Each imported session records, next to the raw file, a path and SHA-256
  row, the date, condition, firmware or software version, load or configuration
  (`Unknown` when unknown), and the gate re-checks every hash.
- DA-4 Malformed, impossible, or partial rows are listed with file and line,
  never guessed, repaired or dropped silently.
- DA-5 Analysers exit 0 success, 1 read or parse error, 2 no usable data or
  needs review; exit 2 is never a pass, and a count mismatch returns 2.
- DA-6 Every graph and table caption states source file, producing version, and
  population (which runs, doses or cycles); wording is not reused outside its scope.
- DA-7 A configured interval, timeout or gap is a floor; the real interval is
  derived from consecutive logged rows and reported with its spread.
- DA-8 Run identity is confirmed from data (a header line, a session id, the
  logged version), never from a folder or file name alone.
- DA-9 Records of different kinds are not mixed: an operator decision logged by
  the device, an exact controller observation, and a reconstructed trace are
  labelled separately; a reconstruction is directional evidence only.
- DA-10 A counterfactual replay states that recorded outputs cannot predict the
  plant's response to changed commands.
- DA-11 Conclusions are proportional to independent experiments; no parameter
  is tuned from one unexplained run, and the independent count is stated.
- DA-12 An analysis report is committed with a date in its name and a row in the
  reports index; it is standalone, with data inline and no public hosting.
- DA-13 Code a report needs a second time becomes a CLI command with tests and
  documentation, not a one-off script.
- DA-14 Output directories are new; analysers refuse an existing output path.
- DA-15 A sensor quirk found in data is recorded as a knowledge note with a
  detection run on load; a detection prompts before any removal.
- DA-16 Full raw captures stay out of git; only the labelled subset, manifests,
  counts and evidence enter, per Project decisions.

## Gates

| Gate | Command (project supplies) | Pass | Rule |
|---|---|---|---|
| Hash re-check | script walks session READMEs | every listed file exists and its SHA-256 matches | DA-1, DA-3 |
| Attribute check | `git check-attr text -- <raw path>` | `unset` for raw data | DA-2 |
| Parser regression | analyser tests on malformed, empty, partial, duplicate files | exit codes 0, 1, 2 as specified; malformed rows listed | DA-4, DA-5 |
| Caption check (build) | script scans reports for source, version, population fields | all present | DA-6 |
| Report index | every `docs/reports/*.html` has an index row | no orphan | DA-12 |
| Output-dir guard | analyser run on an existing path | refuses, exit 1 | DA-14 |
| Sensor-quirk detection | load fixture with known quirk | detected and reported | DA-15 |

## Tools

- Import tool (copy, verify hash, write session README row, several files per
  call): `exists in a prior embedded controller firmware project, port on
  adoption`.
- Per-format analysers with per-run, per-cycle, whole-run and cross-run output,
  JSON export, recomputed pass/fail labels: `exists in a prior embedded
  controller firmware project, port on adoption`; `build` for a new log schema.
- Experiment CLI with prepare, audit and inspect commands: `exists in a prior
  vibration analysis project, port on adoption`.
- Replay tool for counterfactual command comparison: `exists in a prior
  embedded controller firmware project, port on adoption`.

## Playbooks

- Test-data workflow: preserve, import, parse, summarise, check malformed rows,
  overflow, impossible periods, missing bursts, partial runs, sample counts,
  order, cold or warm state, configuration version; distinguish average error,
  stability failure, sensor noise, controller response, unknown disturbance.
- Store concise identity, results, graphs, limitations and next evidence with
  the raw file.
- `docs/procedures/bughunt.md` for analysis defects; this profile lists no
  defect patterns of its own, so the generic hunts of
  bughunt.md steps 2 and 3 apply.

## Agents and skills

- Skills: test-data-analyst (carries the workflow above).
- `reviewer` re-derives two headline numbers from the raw file independently.

## Parameters and records

- Session layout: `raw/`, README with hash table, summary CSVs, graphs,
  limitations. Category folders by data kind (full runs, dry runs).
- `docs/reports/YYYY-MM-DD-<slug>.html` plus `docs/reports/README.md` index.
- Knowledge notes for sensor quirks, with the detection named.
- Analyser thresholds (sensitivity, merge gap, minimum pulse) are parameters
  with defaults recorded and overridable by flag.

## Done means

- Raw file untouched and hash-checked; malformed rows listed; exit status 0.
- Caption on every figure; independent count and limitations stated.
- Report committed, dated and indexed; reusable code promoted to a command.

## Lessons carried in

- Git line-ending normalisation changed raw scientific files; mark raw paths
  `-text`.
- A graph caption overstated its source; every caption names source, version and
  population.
- Configured gaps read as fixed but varied with storage latency; derive the real
  interval from the rows.
- An export bug duplicated a large share of adjacent rows, doubling the apparent
  sample rate; gyro bias under vibration integrates into phantom drift.
- One report script was needed again and became a tested command.

## Sources

Sources: distilled from four prior projects of the template owner (embedded
firmware, controller PCB, vibration data analysis, CAD add-in); project records
stay in those repositories.
