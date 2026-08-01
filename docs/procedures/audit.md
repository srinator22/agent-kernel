# Audit - full-repo review

1. Triggers: after a major architecture change or migration; before first
   real data, customer, or production use; when failures across modules
   suggest systemic problems; before removing a legacy reference
   implementation; when security, CI, or deploy assumptions have
   accumulated unreviewed.
2. Scope: architecture boundaries, data flow, validation, error handling,
   state, concurrency, numerical logic, security, CI, deployment,
   documentation. Parallelize across workers by disjoint area; the advisor
   integrates the findings.
3. Priorities:
   - P0: data loss, security exposure, unsafe behavior - stop and fix
     immediately.
   - P1: wrong core result or broken critical journey - fix before release.
   - P2: material reliability or maintainability defect - plan and fix with
     regression coverage.
   - P3: minor - record in BACKLOG.md and batch.
4. Separate confirmed defects (evidence, impact, reproduction, owning
   layer, verification method) from risks and ideas. Confirmed defects
   enter BACKLOG.md with priority; P0 and P1 become tasks now.
