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
5. If usage limits may interrupt the session, schedule a wakeup to resume
   plus a cheap periodic pulse that restarts a stalled job and deletes
   itself when the job completes. This is harness-dependent; degrade to
   documenting the manual resume steps in the STATE file.
