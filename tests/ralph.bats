#!/usr/bin/env bats
# RALPH+ Test Suite
# Run with: bats tests/ralph.bats

# ─── Setup ────────────────────────────────────────────────────

setup() {
    export TEST_DIR="$(mktemp -d)"
    export RALPH_DIR="$TEST_DIR/.ralph-plus"
    export LOG_DIR="$RALPH_DIR/logs"
    export CB_STATE_FILE="$RALPH_DIR/.circuit_breaker_state"
    export CB_HISTORY_FILE="$RALPH_DIR/.circuit_breaker_history"
    export CALL_COUNT_FILE="$RALPH_DIR/.call_count"
    export TIMESTAMP_FILE="$RALPH_DIR/.last_reset"
    export STATUS_FILE="$RALPH_DIR/status.json"
    export PROGRESS_FILE="$TEST_DIR/progress.txt"
    export PRD_FILE="$TEST_DIR/prd.json"
    export VERBOSE=false

    mkdir -p "$RALPH_DIR" "$LOG_DIR"

    # Source components
    SCRIPT_DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
    source "$SCRIPT_DIR/config/defaults.sh"
    source "$SCRIPT_DIR/config/circuit-breaker.sh"
    source "$SCRIPT_DIR/config/aios-bridge.sh"
    source "$SCRIPT_DIR/lib/safety.sh"
    source "$SCRIPT_DIR/lib/memory.sh"
    source "$SCRIPT_DIR/lib/hooks.sh"
    source "$SCRIPT_DIR/lib/monitor.sh"
}

teardown() {
    rm -rf "$TEST_DIR"
}

# ─── Circuit Breaker Tests ────────────────────────────────────

@test "circuit breaker initializes in CLOSED state" {
    cb_init
    result=$(cb_state)
    [ "$result" = "CLOSED" ]
}

@test "circuit breaker allows execution when CLOSED" {
    cb_init
    cb_can_execute
}

@test "circuit breaker transitions to HALF_OPEN after 2 no-progress loops" {
    cb_init
    cb_record 1 0 false false
    cb_record 2 0 false false
    result=$(cb_state)
    [ "$result" = "HALF_OPEN" ]
}

@test "circuit breaker transitions to OPEN after threshold no-progress loops" {
    CB_NO_PROGRESS_THRESHOLD=3
    cb_init
    cb_record 1 0 false false
    cb_record 2 0 false false
    cb_record 3 0 false false || true
    result=$(cb_state)
    [ "$result" = "OPEN" ]
}

@test "circuit breaker recovers to CLOSED on progress after HALF_OPEN" {
    cb_init
    cb_record 1 0 false false
    cb_record 2 0 false false
    # Now HALF_OPEN
    cb_record 3 5 false false
    result=$(cb_state)
    [ "$result" = "CLOSED" ]
}

@test "circuit breaker denies execution when OPEN" {
    cb_init
    CB_NO_PROGRESS_THRESHOLD=1
    cb_record 1 0 false false || true
    ! cb_can_execute
}

@test "circuit breaker reset works" {
    cb_init
    CB_NO_PROGRESS_THRESHOLD=1
    cb_record 1 0 false false || true
    cb_reset "test reset"
    result=$(cb_state)
    [ "$result" = "CLOSED" ]
}

@test "circuit breaker counts completion as progress" {
    cb_init
    cb_record 1 0 false true  # completion=true
    result=$(jq -r '.consecutive_no_progress' "$CB_STATE_FILE")
    [ "$result" = "0" ]
}

@test "circuit breaker tracks permission denials" {
    cb_init
    cb_record 1 0 false false true  # permission_denial=true
    result=$(jq -r '.consecutive_permission_denials' "$CB_STATE_FILE")
    [ "$result" = "1" ]
}

@test "circuit breaker opens on permission denial threshold" {
    CB_PERMISSION_DENIAL_THRESHOLD=2
    cb_init
    cb_record 1 0 false false true
    cb_record 2 0 false false true || true
    result=$(cb_state)
    [ "$result" = "OPEN" ]
}

@test "circuit breaker resets permission denials on success" {
    cb_init
    cb_record 1 0 false false true  # permission denial
    cb_record 2 5 false false false  # success with files
    result=$(jq -r '.consecutive_permission_denials' "$CB_STATE_FILE")
    [ "$result" = "0" ]
}

@test "circuit breaker history logs transitions" {
    cb_init
    cb_record 1 0 false false
    cb_record 2 0 false false
    # Transitioned to HALF_OPEN, should have history entry
    local count
    count=$(jq 'length' "$CB_HISTORY_FILE")
    [ "$count" -ge 1 ]
}

# ─── Rate Limiting Tests ──────────────────────────────────────

@test "rate limit initializes at zero" {
    rate_init
    local count
    count=$(cat "$CALL_COUNT_FILE")
    [ "$count" = "0" ]
}

@test "rate limit increments correctly" {
    rate_init
    rate_increment
    rate_increment
    rate_increment
    local count
    count=$(cat "$CALL_COUNT_FILE")
    [ "$count" = "3" ]
}

@test "rate limit check passes under limit" {
    MAX_CALLS_PER_HOUR=100
    rate_init
    rate_check
}

@test "rate limit check fails over limit" {
    MAX_CALLS_PER_HOUR=2
    rate_init
    echo "5" > "$CALL_COUNT_FILE"
    ! rate_check
}

@test "api limit detection finds rate_limit_event" {
    detect_api_limit '{"type":"rate_limit_event"}'
}

@test "api limit detection finds rate limit text" {
    detect_api_limit 'Error: rate limit exceeded'
}

@test "api limit detection ignores normal output" {
    ! detect_api_limit 'Everything is fine, code committed'
}

# ─── AIOS Bridge Tests ───────────────────────────────────────

@test "detect_aios returns standalone when no .aios-core" {
    cd "$TEST_DIR"
    result=$(detect_aios)
    [ "$result" = "standalone" ]
}

@test "detect_aios returns aios when .aios-core exists" {
    cd "$TEST_DIR"
    mkdir -p .aios-core
    echo "# Constitution" > .aios-core/constitution.md
    result=$(detect_aios)
    [ "$result" = "aios" ]
}

@test "detect_aios returns standalone when AIOS_ENABLED=false" {
    cd "$TEST_DIR"
    mkdir -p .aios-core
    echo "# Constitution" > .aios-core/constitution.md
    AIOS_ENABLED=false
    result=$(detect_aios)
    [ "$result" = "standalone" ]
}

@test "read_prd_stories returns empty array for missing file" {
    cd "$TEST_DIR"
    PRD_FILE="$TEST_DIR/nonexistent.json"
    result=$(read_prd_stories)
    [ "$result" = "[]" ]
}

@test "read_prd_stories parses valid prd.json" {
    cd "$TEST_DIR"
    cat > "$PRD_FILE" << 'EOF'
{
  "project": "Test",
  "userStories": [
    {"id": "US-001", "title": "Test Story", "passes": false, "priority": 1}
  ]
}
EOF
    result=$(read_prd_stories | jq 'length')
    [ "$result" = "1" ]
}

@test "get_next_prd_story returns highest priority with passes=false" {
    cd "$TEST_DIR"
    cat > "$PRD_FILE" << 'EOF'
{
  "project": "Test",
  "userStories": [
    {"id": "US-001", "title": "First", "passes": true, "priority": 1},
    {"id": "US-002", "title": "Second", "passes": false, "priority": 2},
    {"id": "US-003", "title": "Third", "passes": false, "priority": 3}
  ]
}
EOF
    result=$(get_next_prd_story | jq -r '.id')
    [ "$result" = "US-002" ]
}

@test "update_prd_story sets passes=true" {
    cd "$TEST_DIR"
    cat > "$PRD_FILE" << 'EOF'
{
  "project": "Test",
  "userStories": [
    {"id": "US-001", "title": "First", "passes": false, "priority": 1}
  ]
}
EOF
    update_prd_story "US-001"
    result=$(jq -r '.userStories[0].passes' "$PRD_FILE")
    [ "$result" = "true" ]
}

@test "all_stories_done returns true when all passed" {
    cd "$TEST_DIR"
    cat > "$PRD_FILE" << 'EOF'
{
  "project": "Test",
  "userStories": [
    {"id": "US-001", "passes": true, "priority": 1},
    {"id": "US-002", "passes": true, "priority": 2}
  ]
}
EOF
    all_stories_done "standalone"
}

@test "all_stories_done returns false when stories pending" {
    cd "$TEST_DIR"
    cat > "$PRD_FILE" << 'EOF'
{
  "project": "Test",
  "userStories": [
    {"id": "US-001", "passes": true, "priority": 1},
    {"id": "US-002", "passes": false, "priority": 2}
  ]
}
EOF
    ! all_stories_done "standalone"
}

# ─── Memory Tests ─────────────────────────────────────────────

@test "memory_init creates progress file" {
    cd "$TEST_DIR"
    memory_init
    [ -f "$PROGRESS_FILE" ]
}

@test "memory_init includes Codebase Patterns section" {
    cd "$TEST_DIR"
    memory_init
    grep -q "Codebase Patterns" "$PROGRESS_FILE"
}

@test "append_progress adds entry" {
    cd "$TEST_DIR"
    memory_init
    append_progress 1 "US-001" "COMPLETE" "Implemented feature" 3
    grep -q "US-001" "$PROGRESS_FILE"
    grep -q "COMPLETE" "$PROGRESS_FILE"
}

@test "build_context includes patterns section" {
    cd "$TEST_DIR"
    memory_init
    result=$(build_context)
    echo "$result" | grep -q "Codebase Patterns"
}

# ─── Validation Tests ─────────────────────────────────────────

@test "validate_story rejects empty story" {
    ! validate_story "standalone" ""
}

@test "validate_story rejects null story" {
    ! validate_story "standalone" "null"
}

@test "validate_story accepts valid standalone story" {
    validate_story "standalone" '{"id":"US-001","title":"Test","passes":false}'
}

# ─── Response Analysis Tests ──────────────────────────────────

@test "analyze_response detects COMPLETE status in JSON" {
    cd "$TEST_DIR"
    local output='Some output {"status":"COMPLETE","exit_signal":true,"files_modified":5}'
    local result_file
    result_file=$(analyze_response "$output")
    local status
    status=$(jq -r '.status' "$result_file")
    [ "$status" = "COMPLETE" ]
}

@test "analyze_response detects errors in text" {
    cd "$TEST_DIR"
    local output='Error: something failed with an exception'
    local result_file
    result_file=$(analyze_response "$output")
    local errors
    errors=$(jq -r '.has_errors' "$result_file")
    [ "$errors" = "true" ]
}

@test "analyze_response detects BLOCKED status in text" {
    cd "$TEST_DIR"
    local output='Cannot proceed with this story, blocked by dependency'
    local result_file
    result_file=$(analyze_response "$output")
    local status
    status=$(jq -r '.status' "$result_file")
    [ "$status" = "BLOCKED" ]
}

@test "analyze_response detects permission denials" {
    cd "$TEST_DIR"
    local output='Permission denied for this operation'
    local result_file
    result_file=$(analyze_response "$output")
    local denials
    denials=$(jq -r '.has_permission_denials' "$result_file")
    [ "$denials" = "true" ]
}

# ─── Hook Tests ───────────────────────────────────────────────

@test "run_hook skips when no hook configured" {
    run_hook "test" "" "arg1"
}

@test "run_hook executes valid hook script" {
    local hook_script="$TEST_DIR/test-hook.sh"
    echo '#!/bin/bash' > "$hook_script"
    echo 'echo "hook executed"' >> "$hook_script"
    chmod +x "$hook_script"

    run_hook "test" "$hook_script"
}

# ─── Structural Completion Tests ──────────────────────────────

@test "dual exit passes when all stories done and status COMPLETE" {
    cd "$TEST_DIR"
    cat > "$PRD_FILE" << 'EOF'
{
  "project": "Test",
  "userStories": [
    {"id": "US-001", "passes": true, "priority": 1}
  ]
}
EOF
    local analysis="$RALPH_DIR/.response_analysis"
    echo '{"status":"COMPLETE","exit_signal":true}' > "$analysis"
    check_dual_exit "standalone" "$analysis"
}

@test "dual exit fails when stories pending" {
    cd "$TEST_DIR"
    cat > "$PRD_FILE" << 'EOF'
{
  "project": "Test",
  "userStories": [
    {"id": "US-001", "passes": false, "priority": 1}
  ]
}
EOF
    local analysis="$RALPH_DIR/.response_analysis"
    echo '{"status":"COMPLETE","exit_signal":true}' > "$analysis"
    ! check_dual_exit "standalone" "$analysis"
}

# ─── Story Summary Tests ─────────────────────────────────────

@test "cleanup_backups removes old backups beyond MAX_BACKUPS" {
    cd "$TEST_DIR"
    local backup_dir="$RALPH_DIR/backups"
    mkdir -p "$backup_dir"
    MAX_BACKUPS=3

    # Create 5 backups with different timestamps
    for i in 1 2 3 4 5; do
        touch "$backup_dir/backup_iter${i}_2026010${i}_120000.tar.gz"
        sleep 0.1  # Ensure different mtime
    done

    cleanup_backups "$backup_dir"

    local count
    count=$(find "$backup_dir" -name "backup_iter*.tar.gz" -type f | wc -l | tr -d ' ')
    [ "$count" -eq 3 ]
}

@test "cleanup_backups does nothing when under limit" {
    cd "$TEST_DIR"
    local backup_dir="$RALPH_DIR/backups"
    mkdir -p "$backup_dir"
    MAX_BACKUPS=10

    touch "$backup_dir/backup_iter1_20260101_120000.tar.gz"
    touch "$backup_dir/backup_iter2_20260102_120000.tar.gz"

    cleanup_backups "$backup_dir"

    local count
    count=$(find "$backup_dir" -name "backup_iter*.tar.gz" -type f | wc -l | tr -d ' ')
    [ "$count" -eq 2 ]
}

@test "get_story_summary shows correct counts" {
    cd "$TEST_DIR"
    cat > "$PRD_FILE" << 'EOF'
{
  "project": "Test",
  "userStories": [
    {"id": "US-001", "passes": true, "priority": 1},
    {"id": "US-002", "passes": false, "priority": 2},
    {"id": "US-003", "passes": false, "priority": 3}
  ]
}
EOF
    result=$(get_story_summary "standalone")
    echo "$result" | grep -q "1/3"
}
