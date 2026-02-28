# Ralph Agent Memory (Rex)

## Active Patterns
<!-- Current, verified patterns used by this agent -->

### Core Identity
- Rex is the **control layer** over ralph.sh — does NOT implement stories directly
- Delegates to ralph-plus/ bash scripts for all loop operations
- NEVER pushes — delegates to @devops

### Ralph AIOS Scripts
- `ralph-plus/ralph.sh` — Main execution loop (spawns Claude Code instances)
- `ralph-plus/ralph-once.sh` — Single iteration for debugging
- `ralph-plus/ralph-status.sh` — Progress dashboard
- `.ralphrc` — Loop configuration (project root)

### Signal Files
- `.ralph-plus/.stop_signal` — Stops loop after current iteration
- `.ralph-plus/.pause_signal` — Pauses loop (removable to resume)
- `ralph-plus/progress.txt` — Story progress tracking

### Configuration (.ralphrc)
- `MAX_ITERATIONS=20` — Default max loop iterations
- `SLEEP_BETWEEN_ITERATIONS=3` — Seconds between iterations
- `CB_NO_PROGRESS_THRESHOLD=3` — Circuit breaker trips after N iterations without progress
- `AIOS_DEV_MODE=yolo` — Default development mode for spawned agents

### Git Rules
- NEVER push — delegate to @devops
- NEVER commit or stage — spawned agents handle their own git operations
- Read-only git: status, log, diff only

### Common Gotchas
- Windows paths: use forward slashes in bash commands
- ralph-plus/ is a git submodule — update with `git submodule update`
- .ralphrc may not exist on fresh clones — use defaults from ralph-plus/config/defaults.sh
- Circuit breaker state persists in .ralph-plus/ directory
