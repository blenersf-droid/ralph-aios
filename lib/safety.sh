#!/bin/bash
# RALPH+ Safety Module
# Rate limiting, validation, and guardrails

# ─── Rate Limiting ───────────────────────────────────────────

# Initialize rate limit tracking
rate_init() {
    mkdir -p "$(dirname "$CALL_COUNT_FILE")"

    if [[ ! -f "$CALL_COUNT_FILE" ]]; then
        echo "0" > "$CALL_COUNT_FILE"
    fi
    if [[ ! -f "$TIMESTAMP_FILE" ]]; then
        date +%s > "$TIMESTAMP_FILE"
    fi
}

# Check if under rate limit
rate_check() {
    rate_init

    local count last_reset current_time elapsed
    count=$(cat "$CALL_COUNT_FILE" 2>/dev/null || echo 0)
    last_reset=$(cat "$TIMESTAMP_FILE" 2>/dev/null || echo 0)
    current_time=$(date +%s)
    elapsed=$(( current_time - last_reset ))

    # Reset hourly
    if [[ $elapsed -ge 3600 ]]; then
        echo "0" > "$CALL_COUNT_FILE"
        date +%s > "$TIMESTAMP_FILE"
        count=0
    fi

    if [[ $count -ge $MAX_CALLS_PER_HOUR ]]; then
        local remaining=$(( 3600 - elapsed ))
        echo -e "${YELLOW}[RATE] Limit reached ($count/$MAX_CALLS_PER_HOUR). Reset in ${remaining}s${NC}"
        return 1
    fi

    return 0
}

# Increment call count
rate_increment() {
    local count
    count=$(cat "$CALL_COUNT_FILE" 2>/dev/null || echo 0)
    echo $((count + 1)) > "$CALL_COUNT_FILE"
}

# Get rate limit status
rate_status() {
    rate_init
    local count last_reset current_time elapsed remaining
    count=$(cat "$CALL_COUNT_FILE" 2>/dev/null || echo 0)
    last_reset=$(cat "$TIMESTAMP_FILE" 2>/dev/null || echo 0)
    current_time=$(date +%s)
    elapsed=$(( current_time - last_reset ))
    remaining=$(( 3600 - elapsed ))
    [[ $remaining -lt 0 ]] && remaining=0
    echo "$count/$MAX_CALLS_PER_HOUR calls (reset in ${remaining}s)"
}

# Wait for rate limit reset
rate_wait() {
    local last_reset current_time elapsed wait_time
    last_reset=$(cat "$TIMESTAMP_FILE" 2>/dev/null || date +%s)
    current_time=$(date +%s)
    elapsed=$(( current_time - last_reset ))
    wait_time=$(( 3600 - elapsed ))

    if [[ $wait_time -gt 0 ]]; then
        echo -e "${YELLOW}[RATE] Waiting ${wait_time}s for rate limit reset...${NC}"
        sleep "$wait_time"
        echo "0" > "$CALL_COUNT_FILE"
        date +%s > "$TIMESTAMP_FILE"
    fi
}

# Detect API 5-hour limit from output
detect_api_limit() {
    local output=$1

    # JSON format detection
    if echo "$output" | grep -q '"rate_limit_event"' 2>/dev/null; then
        return 0
    fi

    # Text format detection
    if echo "$output" | grep -qi "rate.limit\|too many requests\|429\|quota exceeded" 2>/dev/null; then
        return 0
    fi

    return 1
}

# ─── Validation ──────────────────────────────────────────────

# Validate dependencies
validate_deps() {
    local missing=0

    if ! command -v "$CLAUDE_CODE_CMD" &>/dev/null; then
        echo -e "${RED}[ERROR] Claude Code CLI not found: $CLAUDE_CODE_CMD${NC}"
        echo "  Install: npm install -g @anthropic-ai/claude-code"
        missing=1
    fi

    if ! command -v jq &>/dev/null; then
        echo -e "${RED}[ERROR] jq not found${NC}"
        echo "  Install: brew install jq (macOS) or apt install jq (Linux)"
        missing=1
    fi

    if ! command -v git &>/dev/null; then
        echo -e "${RED}[ERROR] git not found${NC}"
        missing=1
    fi

    return $missing
}

# Validate story before starting
validate_story() {
    local mode=$1
    local story_json=$2

    if [[ -z "$story_json" || "$story_json" == "null" ]]; then
        echo -e "${RED}[ERROR] No story available to work on${NC}"
        return 1
    fi

    local story_id
    story_id=$(echo "$story_json" | jq -r '.id // empty')

    if [[ -z "$story_id" ]]; then
        echo -e "${RED}[ERROR] Story has no ID${NC}"
        return 1
    fi

    if [[ "$mode" == "aios" ]]; then
        local story_path status
        story_path=$(echo "$story_json" | jq -r '.path // empty')
        status=$(echo "$story_json" | jq -r '.status // empty')

        if [[ ! -f "$story_path" ]]; then
            echo -e "${RED}[ERROR] Story file not found: $story_path${NC}"
            return 1
        fi

        if [[ "$status" == "Draft" ]]; then
            echo -e "${RED}[ERROR] Story $story_id is Draft — must be Ready or In Progress${NC}"
            return 1
        fi

        if [[ "$status" == "Done" ]]; then
            echo -e "${YELLOW}[SKIP] Story $story_id is already Done${NC}"
            return 1
        fi
    fi

    return 0
}

# ─── Backup ──────────────────────────────────────────────────

# Create backup before iteration
create_backup() {
    local iteration=$1
    local backup_dir="${RALPH_DIR}/backups"
    mkdir -p "$backup_dir"

    local timestamp
    timestamp=$(date +%Y%m%d_%H%M%S)
    local backup_file="$backup_dir/backup_iter${iteration}_${timestamp}.tar.gz"

    # Backup key files
    local files_to_backup=()
    [[ -f "$PRD_FILE" ]] && files_to_backup+=("$PRD_FILE")
    [[ -f "$PROGRESS_FILE" ]] && files_to_backup+=("$PROGRESS_FILE")
    [[ -f "$STATUS_FILE" ]] && files_to_backup+=("$STATUS_FILE")

    if [[ ${#files_to_backup[@]} -gt 0 ]]; then
        tar -czf "$backup_file" "${files_to_backup[@]}" 2>/dev/null
        [[ "$VERBOSE" == "true" ]] && echo -e "${CYAN}[BACKUP] Created: $backup_file${NC}"
    fi

    # Cleanup old backups, keep only the last MAX_BACKUPS
    cleanup_backups "$backup_dir"
}

# Remove old backups, keeping only the last MAX_BACKUPS files
cleanup_backups() {
    local backup_dir=$1
    local max=${MAX_BACKUPS:-10}

    local backup_count
    backup_count=$(find "$backup_dir" -name "backup_iter*.tar.gz" -type f 2>/dev/null | wc -l | tr -d ' ')

    if [[ $backup_count -gt $max ]]; then
        local to_remove=$((backup_count - max))
        find "$backup_dir" -name "backup_iter*.tar.gz" -type f -print0 2>/dev/null \
            | xargs -0 ls -1t \
            | tail -n "$to_remove" \
            | while IFS= read -r old_backup; do
                rm -f "$old_backup"
                [[ "$VERBOSE" == "true" ]] && echo -e "${CYAN}[BACKUP] Removed old: $(basename "$old_backup")${NC}"
            done
    fi
}

# ─── Response Analysis ───────────────────────────────────────

# Analyze Claude output for completion/error signals
analyze_response() {
    local output=$1
    local result_file="${RALPH_DIR}/.response_analysis"

    local status="IN_PROGRESS"
    local exit_signal="false"
    local files_modified=0
    local has_errors="false"
    local work_type="unknown"

    # Try JSON parsing first
    local json_block
    json_block=$(echo "$output" | grep -oP '\{[^{}]*"status"[^{}]*\}' | tail -1)

    if [[ -n "$json_block" ]] && echo "$json_block" | jq '.' > /dev/null 2>&1; then
        status=$(echo "$json_block" | jq -r '.status // "IN_PROGRESS"')
        exit_signal=$(echo "$json_block" | jq -r '.exit_signal // false')
        files_modified=$(echo "$json_block" | jq -r '.files_modified // 0')
        work_type=$(echo "$json_block" | jq -r '.work_type // "unknown"')
    else
        # Text-based detection
        if echo "$output" | grep -qi "complete\|all.*done\|finished\|all stories" 2>/dev/null; then
            status="COMPLETE"
        fi
        if echo "$output" | grep -qi "error\|failed\|exception\|crash" 2>/dev/null; then
            has_errors="true"
        fi
        if echo "$output" | grep -qi "blocked\|cannot proceed\|stuck" 2>/dev/null; then
            status="BLOCKED"
        fi

        # Count file modifications from git
        files_modified=$(git diff --stat HEAD 2>/dev/null | tail -1 | grep -oP '\d+(?= file)' || echo 0)
    fi

    # Detect permission denials
    local has_permission_denials="false"
    if echo "$output" | grep -qi "permission denied\|not allowed\|access denied" 2>/dev/null; then
        has_permission_denials="true"
    fi

    # Write analysis result
    cat > "$result_file" << RAEOF
{
    "status": "$status",
    "exit_signal": $exit_signal,
    "files_modified": $files_modified,
    "has_errors": $has_errors,
    "has_permission_denials": $has_permission_denials,
    "work_type": "$work_type",
    "analyzed_at": "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
}
RAEOF

    echo "$result_file"
}

# Check structural completion (prd.json or AIOS stories)
check_structural_completion() {
    local mode=$1

    if all_stories_done "$mode"; then
        return 0
    fi
    return 1
}

# Dual exit gate: both structural AND semantic must agree
check_dual_exit() {
    local mode=$1
    local analysis_file=$2

    # Structural check
    if ! check_structural_completion "$mode"; then
        return 1  # Not all stories done
    fi

    # Semantic check
    local status exit_signal
    status=$(jq -r '.status' "$analysis_file" 2>/dev/null || echo "IN_PROGRESS")
    exit_signal=$(jq -r '.exit_signal' "$analysis_file" 2>/dev/null || echo "false")

    if [[ "$status" == "COMPLETE" ]] && [[ "$exit_signal" == "true" ]]; then
        return 0  # Both gates pass
    fi

    # Structural says done but semantic doesn't — trust structural
    # (Claude may not emit exit_signal but all stories are actually done)
    echo -e "${YELLOW}[EXIT] Structural check: PASS, Semantic check: $status/$exit_signal${NC}"
    return 0
}
