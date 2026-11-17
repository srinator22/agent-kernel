# Longjob - checkpointed, resumable background work

1. Anything slow (crawls, bulk downloads, migrations, transfers) runs via
   `scripts/bg.sh`, not as a token-burning agent loop (kernel rule 17).
2. The job checkpoints to a file after every small unit so a kill resumes
   exactly where it stopped; never write a long job that starts over.
3. A STATE file in `.work/jobs/` (gitignored) carries: the mandate, a plan
   checklist, running processes with their log and checkpoint paths,
   decisions made and why, and resume instructions. Update it as you go so
   a cold session can pick up where this one stopped.
4. Respect external hosts: honor robots.txt delays, send a descriptive
   User-Agent, pace politely, one process per host.
5. Stall rule (unattended runs and any long job): a tool call or background
   job silent for more than 20 minutes (no output, no checkpoint change) is
   stopped by PID or task id, never by image name (L016), and restarted once
   from its checkpoint. Record the stall, the PID and the restart in the
   STATE file and the TASK.md Progress log. A second stall is not retried:
   stop, keep the best verified artifact, and report it in the file named by
   the task's `Unattended:` field.
6. An unattended task carries `Unattended: yes - <pre-approved actions>;
   report: <path>` in TASK.md (checked by `scripts/tasklint.sh check`). It
   records the owner's per-task approval scope only: kernel rule 15 is
   unchanged, and the field never covers deleting data, force-push or kernel
   edits. Anything outside the listed actions waits for the owner.
7. If usage limits may interrupt the session, schedule a wakeup to resume
   plus a cheap periodic pulse that restarts a stalled job and deletes
   itself when the job completes. This is harness-dependent; degrade to
   documenting the manual resume steps in the STATE file.
