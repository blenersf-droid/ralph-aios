#!/bin/bash
# RALPH+ Memory Module
# Manages progress.txt and AIOS Memory Layer integration

# Initialize progress file
memory_init() {
    if [[ ! -f "$PROGRESS_FILE" ]]; then
        cat > "$PROGRESS_FILE" << MEMEOF
## Codebase Patterns

(Patterns will be added as they are discovered)

---

# Ralph+ Progress Log
Started: $(date)
Mode: $(detect_aios)
---
MEMEOF
    fi
}

# Read codebase patterns from progress.txt
read_patterns() {
    if [[ ! -f "$PROGRESS_FILE" ]]; then
        echo "(No patterns yet)"
        return
    fi

    # Extract Codebase Patterns section
    local patterns
    patterns=$(sed -n '/^## Codebase Patterns/,/^---$/p' "$PROGRESS_FILE" | head -30)

    if [[ -n "$patterns" ]]; then
        echo "$patterns"
    else
        echo "(No patterns yet)"
    fi
}

# Read recent learnings (last 3 entries)
read_recent_learnings() {
    if [[ ! -f "$PROGRESS_FILE" ]]; then
        echo "(No learnings yet)"
        return
    fi

    # Get last 3 iteration entries
    tail -60 "$PROGRESS_FILE" | head -45
}

# Build iteration context (patterns + recent learnings)
build_context() {
    local patterns learnings
    patterns=$(read_patterns)
    learnings=$(read_recent_learnings)

    cat << CTXEOF
### Codebase Patterns (learn these first)
$patterns

### Recent Learnings (from previous iterations)
$learnings
CTXEOF
}

# Append iteration result to progress.txt
append_progress() {
    local iteration=$1
    local story_id=$2
    local status=$3
    local summary=$4
    local files_modified=${5:-0}

    cat >> "$PROGRESS_FILE" << PROGEOF

## [$(date '+%Y-%m-%d %H:%M')] — Iteration $iteration — $story_id
- **Status:** $status
- **Files modified:** $files_modified
- **Summary:** $summary
---
PROGEOF
}

# Add a codebase pattern
add_pattern() {
    local pattern=$1

    if [[ ! -f "$PROGRESS_FILE" ]]; then
        memory_init
    fi

    # Check if pattern already exists
    if grep -qF "$pattern" "$PROGRESS_FILE" 2>/dev/null; then
        return 0
    fi

    # Insert pattern after "## Codebase Patterns" line
    local tmp
    tmp=$(mktemp)
    awk -v pat="- $pattern" '
        /^## Codebase Patterns/ { print; getline; print pat; }
        { print }
    ' "$PROGRESS_FILE" > "$tmp" && mv "$tmp" "$PROGRESS_FILE"

    [[ "$VERBOSE" == "true" ]] && echo -e "${CYAN}[MEMORY] Pattern added: $pattern${NC}"
}

# Sync learnings to AIOS Memory Layer (if AIOS mode)
sync_to_aios_memory() {
    local mode=$1
    local agent_id=${2:-dev}

    if [[ "$mode" != "aios" ]] || [[ "$AIOS_MEMORY_SYNC" != "true" ]]; then
        return 0
    fi

    local memory_file=".aios-core/development/agents/${agent_id}/MEMORY.md"

    if [[ ! -f "$memory_file" ]]; then
        [[ "$VERBOSE" == "true" ]] && echo -e "${CYAN}[MEMORY] AIOS memory file not found: $memory_file${NC}"
        return 0
    fi

    # Read patterns from progress.txt
    local patterns
    patterns=$(read_patterns)

    # Append new patterns to MEMORY.md if not already there
    while IFS= read -r line; do
        line=$(echo "$line" | sed 's/^- //')
        [[ -z "$line" ]] && continue
        [[ "$line" == *"Patterns"* ]] && continue
        [[ "$line" == *"will be added"* ]] && continue

        if ! grep -qF "$line" "$memory_file" 2>/dev/null; then
            echo "- $line" >> "$memory_file"
            [[ "$VERBOSE" == "true" ]] && echo -e "${CYAN}[MEMORY] Synced to @${agent_id}: $line${NC}"
        fi
    done <<< "$patterns"
}

# Update status file
update_status() {
    local iteration=$1
    local story_id=$2
    local status=$3
    local mode=$4

    mkdir -p "$(dirname "$STATUS_FILE")"

    cat > "$STATUS_FILE" << STEOF
{
    "iteration": $iteration,
    "max_iterations": $MAX_ITERATIONS,
    "story_id": "$story_id",
    "status": "$status",
    "mode": "$mode",
    "rate_limit": "$(rate_status)",
    "circuit_breaker": "$(cb_state)",
    "stories": "$(get_story_summary "$mode")",
    "updated_at": "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
}
STEOF
}
