# Claude Code rules for the WarrantyOS repo

These rules govern how Claude Code should execute work in this repo.
They are project-specific behavioral constraints. For project context
(tech stack, current phase, architectural decisions), see the docs/
directory and the project's handoff documents.

## Execution discipline

**One command at a time.** Execute commands sequentially, one per
turn. Report output back. Wait for the next instruction before
proceeding. Do not batch commands in a single tool call. Do not
run commands in parallel.

**No chaining without explicit permission.** Shell operators like
`&&`, `||`, `;`, and `|` chain commands together. Do not chain
commands unless the user has explicitly asked for chaining in the
current turn. Pipes (`|`) for processing a single command's output
(e.g., `command | head -20`) are acceptable; chaining multiple
distinct commands is not.

**Execute what the user sent.** If the user provides an exact
command to run, run that command. If you believe a different
command would be better, surface the proposed substitution and
ask before running it. Do not silently rewrite commands.

**Show raw output.** When the user asks for the output of a
command, show the literal output of the command. Summaries and
interpretations are useful additions but they do not replace the
raw output.

**Walk through commits before executing them.** Before any
`git commit`, propose the commit message and the reasoning
behind it (subject line choice, body content, references).
Wait for approval. Before any `git push`, confirm the branch
state with `git status` and `git log --oneline -3`, and
confirm the user wants to push. Commit message explanations
are required per commit (Approach 2).

**Diagnose before fixing.** When a command returns an
unexpected output, propose a diagnosis of the cause before
proposing a fix. If the diagnosis has multiple possible
causes, name all of them and ask which to investigate first.
Do not skip from "command failed" to "here's the fix" — the
intermediate "here's why I think it failed" step is required.

## Architectural discipline

**Do not re-propose closed decisions.** Architectural decisions
recorded in `docs/session-handoffs/` and `docs/architecture-reference.md`
are closed unless the user explicitly reopens them. If a closed
decision seems wrong, surface the concern and ask before acting on
it. Do not silently revisit the decision by listing rejected
alternatives as if they are live options.

**Do not re-verify established state.** If a prior session
verified state (CLI installed, dependency present, prerequisite
met), do not re-verify in the current session unless the user
asks for re-verification or the state plausibly changed.
Established state is captured in session handoff documents.

## Stop-point discipline

**Surface prerequisite problems, do not work around them.** If a
required tool is missing, a dependency is unavailable, or a
prerequisite is unmet, name the problem and stop. Do not propose
alternative approaches that bypass the missing prerequisite. The
user decides whether to install the prerequisite or to revisit the
approach.

**Hosted database migration hazard — STOP before any remote push.**
The hosted/remote Supabase database's migration history is NOT
baselined: it has no record of 000_baseline or migrations 001-004,
because the initial tables were created manually in the SQL Editor
before the migrations directory existed. Therefore: do NOT run
`supabase db push`, `supabase db remote commit`, `supabase migration
up --linked`, or any command that applies local migrations to the
hosted/remote/production database — until the remote has been
baselined via `supabase migration repair` (marking 000_baseline and
001-004 as already-applied without running them). If asked to push
migrations to the remote, STOP, state this hazard, and confirm the
remote has been baselined first. This is expected to be handled in
Phase 4. Surface it; do not work around it.
