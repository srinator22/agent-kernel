# Destructive actions

Repo artifacts are archived, never deleted (kernel rule 11): move to
`.archive/` with a one-line reason, only during a maintenance pass, never
mid-task. Everything else destructive - deleting files or data outside
git, overwriting, dropping tables, force operations - follows all seven
steps, in order:

1. State the exact, absolute target and what will happen to it.
2. Verify the target read-only first (ls, stat, SELECT, dry-run) in the
   same session; confirm it is what you think it is.
3. Refuse forbidden targets outright: filesystem roots, home directories,
   the workspace root, broad globs, and any path containing an unresolved
   variable.
4. Prefer the recoverable form: trash over rm, archive over delete,
   rename over overwrite, soft-delete over hard-delete, transaction over
   autocommit.
5. Use the narrowest operation that achieves the goal: one file not the
   folder, one row not the table.
6. Get human approval for anything irreversible or outward-facing (kernel
   rule 15) before executing.
7. Verify the result afterward and report exactly what was removed or
   changed, and how to recover it.

Examples of refused targets: `rm -rf /`, `rm -rf ~`, `rm -rf .` at the
workspace root, `git clean -fdx` on the workspace root, `DROP DATABASE`
without a verified backup, `rm "$BUILD_DIR"/*` while BUILD_DIR may be
empty or unset.
