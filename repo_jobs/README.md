# repo_jobs

Multi-step task orders for Claude, managed by Claude Deck (Jobs view).

Each folder is one job:

- `job.json`: name, description, defaults, pivots, and the ordered steps with their expectations
- `context.md`: shared brief given to Claude at the start of a run
- `steps/<id>.md`: the prompt for each step

Steps run in order in one continuing Claude conversation. After each step, every
`command` expectation is run (it must exit 0); failures are fed back for another
attempt, up to `maxAttempts`. Pivots tell Claude what to do instead when a known
obstacle comes up.
