#!/bin/bash
# RALPH+ Core Loop Logic
# Orchestrates the iteration cycle: read story → spawn claude → analyze → update

# Execute one iteration of the loop
run_iteration() {
    local iteration=$1
    local mode=$2
    local story_json=$3
    local retry_count=${4:-0}

    local story_id story_title
    story_id=$(echo "$story_json" | jq -r '.id')
    story_title=$(echo "$story_json" | jq -r '.title // .id')

    # Show iteration header
    show_iteration_header "$iteration" "$MAX_ITERATIONS" "$mode" "$story_id"
    log INFO "Iteration $iteration: Story $story_id ($story_title)"

    # Pre-iteration hook
    hook_pre_iteration "$iteration" "$story_id" "$mode"

    # Build context from memory
    local context
    context=$(build_context)

    # Generate prompt based on mode
    local prompt
    if [[ "$mode" == "aios" ]]; then
        prompt=$(generate_aios_prompt "$story_json" "$iteration" "$MAX_ITERATIONS" "$context")
    else
        prompt=$(generate_standalone_prompt "$story_json" "$iteration" "$MAX_ITERATIONS" "$context")
    fi

    # Update status
    update_status "$iteration" "$story_id" "executing" "$mode"

    # Backup before execution
    create_backup "$iteration"

    # Rate limit check and increment
    rate_increment

    # Calculate timeout in seconds
    local timeout_seconds=$((CLAUDE_TIMEOUT_MINUTES * 60))

    # Spawn Claude Code
    log INFO "Spawning Claude Code (timeout: ${CLAUDE_TIMEOUT_MINUTES}min)..."

    # Compact @dev agent persona for --print mode
    local agent_system_prompt
    agent_system_prompt="You are Dex (@dev), Expert Senior Software Engineer. Persona: pragmatic, concise, solution-focused. Core: story file has ALL info needed, follow existing patterns in squads/, use TypeScript with proper types, absolute imports. Quality: all code must pass typecheck and lint. QA: self-review each AC critically before marking complete."

    local output exit_code
    local output_file="${RALPH_DIR}/output_iter${iteration}.log"

    if [[ "$LIVE_OUTPUT" == "true" ]]; then
        # Live output mode: tee to file and stderr
        output=$(echo "$prompt" | timeout "$timeout_seconds" \
            "$CLAUDE_CODE_CMD" --print --dangerously-skip-permissions \
            --append-system-prompt "$agent_system_prompt" \
            2>&1 | tee "$output_file" /dev/stderr) || true
        exit_code=${PIPESTATUS[0]:-$?}
    else
        # Quiet mode: capture only
        output=$(echo "$prompt" | timeout "$timeout_seconds" \
            "$CLAUDE_CODE_CMD" --print --dangerously-skip-permissions \
            --append-system-prompt "$agent_system_prompt" \
            2>&1) || true
        exit_code=$?
        echo "$output" > "$output_file"
    fi

    # Handle timeout
    if [[ $exit_code -eq 124 ]]; then
        log WARN "Claude Code timed out after ${CLAUDE_TIMEOUT_MINUTES}min"
        hook_on_error "$iteration" "$story_id" "timeout"
        return 2  # Timeout, retry
    fi

    # Detect API rate limit
    if detect_api_limit "$output"; then
        log WARN "API rate limit detected"
        echo -e "${YELLOW}[API] Rate limit hit. Waiting ${API_LIMIT_SLEEP_MINUTES}min...${NC}"
        sleep $((API_LIMIT_SLEEP_MINUTES * 60))
        return 2  # Retry after wait
    fi

    # Analyze response
    local analysis_file
    analysis_file=$(analyze_response "$output")

    local resp_status resp_exit files_modified has_errors has_permission_denials
    resp_status=$(jq -r '.status' "$analysis_file" 2>/dev/null || echo "IN_PROGRESS")
    resp_exit=$(jq -r '.exit_signal' "$analysis_file" 2>/dev/null || echo "false")
    files_modified=$(jq -r '.files_modified' "$analysis_file" 2>/dev/null || echo "0")
    has_errors=$(jq -r '.has_errors' "$analysis_file" 2>/dev/null || echo "false")
    has_permission_denials=$(jq -r '.has_permission_denials' "$analysis_file" 2>/dev/null || echo "false")

    log INFO "Response: status=$resp_status, exit=$resp_exit, files=$files_modified, errors=$has_errors, perm_denials=$has_permission_denials"

    # Record in circuit breaker
    local completion_flag="false"
    [[ "$resp_status" == "COMPLETE" ]] && completion_flag="true"

    if ! cb_record "$iteration" "$files_modified" "$has_errors" "$completion_flag" "$has_permission_denials"; then
        log ERROR "Circuit breaker opened"
        return 3  # Circuit breaker triggered
    fi

    # Handle story completion
    if [[ "$resp_status" == "COMPLETE" ]] || [[ $files_modified -gt 0 ]]; then
        # Story made progress or completed
        local summary
        summary=$(jq -r '.summary // "Implementation completed"' "$analysis_file" 2>/dev/null || echo "Progress made")

        if [[ "$mode" == "aios" ]]; then
            # Update AIOS story
            local story_path
            story_path=$(echo "$story_json" | jq -r '.path')

            if [[ "$resp_status" == "COMPLETE" ]]; then
                update_story_status "$story_path" "In Progress" "Done"
                hook_on_story_complete "$story_id" "$iteration"
            else
                update_story_status "$story_path" "Ready" "In Progress"
            fi
        else
            # Update prd.json
            if [[ "$resp_status" == "COMPLETE" ]]; then
                update_prd_story "$story_id"
                hook_on_story_complete "$story_id" "$iteration"
            fi
        fi

        # Append progress
        append_progress "$iteration" "$story_id" "$resp_status" "$summary" "$files_modified"

        # Show status
        show_inline_status "$iteration" "$mode" "$story_id"

        # Post-iteration hook
        hook_post_iteration "$iteration" "$story_id" "$resp_status" "$mode"

        return 0  # Success
    fi

    # Handle blocked
    if [[ "$resp_status" == "BLOCKED" ]]; then
        log WARN "Story $story_id is BLOCKED"
        append_progress "$iteration" "$story_id" "BLOCKED" "Story blocked" "0"
        hook_on_error "$iteration" "$story_id" "blocked"
        return 4  # Blocked, skip to next story
    fi

    # Handle error
    if [[ "$has_errors" == "true" ]]; then
        log WARN "Errors detected in iteration $iteration"
        hook_on_error "$iteration" "$story_id" "errors"
        return 2  # Error, retry
    fi

    # No progress
    log WARN "No progress detected in iteration $iteration"
    append_progress "$iteration" "$story_id" "NO_PROGRESS" "No changes detected" "0"

    # Post-iteration hook
    hook_post_iteration "$iteration" "$story_id" "NO_PROGRESS" "$mode"

    return 0
}

# Main loop
run_loop() {
    local mode=$1
    local blocked_stories=()
    local current_retry=0

    for iteration in $(seq 1 "$MAX_ITERATIONS"); do
        # Check stop signal
        if [[ -f "${RALPH_DIR}/.stop_signal" ]]; then
            rm -f "${RALPH_DIR}/.stop_signal"
            log INFO "Stop signal received. Halting loop after iteration $((iteration - 1))."
            echo -e "${YELLOW}[RALPH] Stop signal received. Loop halted.${NC}"
            hook_on_complete "$((iteration - 1))" "$mode"
            return 0
        fi

        # Check pause signal
        if [[ -f "${RALPH_DIR}/.pause_signal" ]]; then
            log INFO "Pause signal received. Waiting for resume..."
            echo -e "${YELLOW}[RALPH] Paused. Remove ${RALPH_DIR}/.pause_signal or use @ralph *resume to continue.${NC}"
            while [[ -f "${RALPH_DIR}/.pause_signal" ]]; do
                sleep 5
                # Also check for stop signal while paused
                if [[ -f "${RALPH_DIR}/.stop_signal" ]]; then
                    rm -f "${RALPH_DIR}/.stop_signal" "${RALPH_DIR}/.pause_signal"
                    log INFO "Stop signal received while paused. Halting loop."
                    echo -e "${YELLOW}[RALPH] Stop signal received while paused. Loop halted.${NC}"
                    return 0
                fi
            done
            log INFO "Resumed from pause."
            echo -e "${GREEN}[RALPH] Resumed.${NC}"
        fi

        # Pre-checks
        if ! cb_can_execute; then
            cb_show_status
            show_failure_summary "$iteration" "$MAX_ITERATIONS" "$mode" "Circuit breaker opened"
            return 1
        fi

        if ! rate_check; then
            rate_wait
        fi

        # Get next story
        local story_json
        if [[ "$mode" == "aios" ]]; then
            story_json=$(get_next_aios_story)
        else
            story_json=$(get_next_prd_story)
        fi

        # Validate story
        if ! validate_story "$mode" "$story_json"; then
            # Check if all done
            if all_stories_done "$mode"; then
                show_completion_summary "$iteration" "$mode"
                hook_on_complete "$iteration" "$mode"
                return 0
            fi

            # No valid stories left
            show_failure_summary "$iteration" "$MAX_ITERATIONS" "$mode" "No valid stories available"
            return 1
        fi

        local story_id
        story_id=$(echo "$story_json" | jq -r '.id')

        # Skip blocked stories
        local is_blocked=false
        for blocked in "${blocked_stories[@]}"; do
            if [[ "$blocked" == "$story_id" ]]; then
                is_blocked=true
                break
            fi
        done

        if [[ "$is_blocked" == "true" ]]; then
            log INFO "Skipping blocked story: $story_id"
            continue
        fi

        # Execute iteration
        local result
        run_iteration "$iteration" "$mode" "$story_json" "$current_retry"
        result=$?

        case $result in
            0)  # Success
                current_retry=0
                ;;
            2)  # Retry
                current_retry=$((current_retry + 1))
                if [[ $current_retry -ge $MAX_RETRIES_PER_STORY ]]; then
                    log WARN "Max retries ($MAX_RETRIES_PER_STORY) reached for $story_id"
                    blocked_stories+=("$story_id")
                    current_retry=0
                fi
                ;;
            3)  # Circuit breaker
                cb_show_status
                show_failure_summary "$iteration" "$MAX_ITERATIONS" "$mode" "Circuit breaker opened"
                return 1
                ;;
            4)  # Blocked
                blocked_stories+=("$story_id")
                current_retry=0
                ;;
        esac

        # Check completion (dual exit gate)
        if check_dual_exit "$mode" "${RALPH_DIR}/.response_analysis" 2>/dev/null; then
            show_completion_summary "$iteration" "$mode"
            hook_on_complete "$iteration" "$mode"
            return 0
        fi

        # Sync memory to AIOS
        sync_to_aios_memory "$mode"

        # Sleep between iterations
        if [[ $iteration -lt $MAX_ITERATIONS ]]; then
            sleep "$SLEEP_BETWEEN_ITERATIONS"
        fi
    done

    # Max iterations reached
    show_failure_summary "$MAX_ITERATIONS" "$MAX_ITERATIONS" "$mode" "Max iterations reached"
    return 1
}
