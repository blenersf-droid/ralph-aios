#!/bin/bash
# RALPH+ Circuit Breaker
# Based on Michael Nygard's "Release It!" pattern
# Adapted from frankbria/ralph-claude-code with AIOS integration

# Circuit Breaker States
CB_STATE_CLOSED="CLOSED"
CB_STATE_HALF_OPEN="HALF_OPEN"
CB_STATE_OPEN="OPEN"

# Initialize circuit breaker state file
cb_init() {
    if [[ -f "$CB_STATE_FILE" ]]; then
        if ! jq '.' "$CB_STATE_FILE" > /dev/null 2>&1; then
            rm -f "$CB_STATE_FILE"
        fi
    fi

    if [[ ! -f "$CB_STATE_FILE" ]]; then
        cat > "$CB_STATE_FILE" << CBEOF
{
    "state": "$CB_STATE_CLOSED",
    "last_change": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
    "consecutive_no_progress": 0,
    "consecutive_same_error": 0,
    "consecutive_permission_denials": 0,
    "last_progress_loop": 0,
    "total_opens": 0,
    "current_loop": 0,
    "reason": ""
}
CBEOF
    fi

    # Initialize history
    if [[ ! -f "$CB_HISTORY_FILE" ]] || ! jq '.' "$CB_HISTORY_FILE" > /dev/null 2>&1; then
        echo '[]' > "$CB_HISTORY_FILE"
    fi

    # Auto-recovery check
    local current_state
    current_state=$(jq -r '.state' "$CB_STATE_FILE" 2>/dev/null || echo "$CB_STATE_CLOSED")

    if [[ "$current_state" == "$CB_STATE_OPEN" ]]; then
        if [[ "$CB_AUTO_RESET" == "true" ]]; then
            cb_reset "Auto-reset on startup"
        else
            local opened_at
            opened_at=$(jq -r '.opened_at // .last_change // ""' "$CB_STATE_FILE" 2>/dev/null)
            if [[ -n "$opened_at" && "$opened_at" != "null" ]]; then
                local opened_epoch current_epoch elapsed_minutes
                opened_epoch=$(date -d "$opened_at" +%s 2>/dev/null || date -j -f "%Y-%m-%dT%H:%M:%SZ" "$opened_at" +%s 2>/dev/null || echo 0)
                current_epoch=$(date +%s)
                elapsed_minutes=$(( (current_epoch - opened_epoch) / 60 ))

                if [[ $elapsed_minutes -ge $CB_COOLDOWN_MINUTES ]]; then
                    cb_transition "$CB_STATE_HALF_OPEN" "Cooldown elapsed (${elapsed_minutes}m >= ${CB_COOLDOWN_MINUTES}m)" "$(jq -r '.current_loop // 0' "$CB_STATE_FILE")"
                fi
            fi
        fi
    fi
}

# Get current state
cb_state() {
    jq -r '.state' "$CB_STATE_FILE" 2>/dev/null || echo "$CB_STATE_CLOSED"
}

# Check if execution is allowed
cb_can_execute() {
    local state
    state=$(cb_state)
    [[ "$state" != "$CB_STATE_OPEN" ]]
}

# Record loop result and update state
cb_record() {
    local loop_number=$1
    local files_changed=${2:-0}
    local has_errors=${3:-false}
    local has_completion=${4:-false}
    local has_permission_denials=${5:-false}

    local state_data current_state
    state_data=$(cat "$CB_STATE_FILE")
    current_state=$(echo "$state_data" | jq -r '.state')

    local no_progress same_error perm_denials last_progress
    no_progress=$(echo "$state_data" | jq -r '.consecutive_no_progress // 0')
    same_error=$(echo "$state_data" | jq -r '.consecutive_same_error // 0')
    perm_denials=$(echo "$state_data" | jq -r '.consecutive_permission_denials // 0')
    last_progress=$(echo "$state_data" | jq -r '.last_progress_loop // 0')

    # Detect progress
    local has_progress=false
    if [[ $files_changed -gt 0 ]] || [[ "$has_completion" == "true" ]]; then
        has_progress=true
        no_progress=0
        last_progress=$loop_number
    else
        no_progress=$((no_progress + 1))
    fi

    # Track errors
    if [[ "$has_errors" == "true" ]]; then
        same_error=$((same_error + 1))
    else
        same_error=0
    fi

    # Track permission denials
    if [[ "$has_permission_denials" == "true" ]]; then
        perm_denials=$((perm_denials + 1))
    else
        perm_denials=0
    fi

    # State machine transitions
    local new_state="$current_state"
    local reason=""

    case $current_state in
        "$CB_STATE_CLOSED")
            if [[ $perm_denials -ge $CB_PERMISSION_DENIAL_THRESHOLD ]]; then
                new_state="$CB_STATE_OPEN"
                reason="Permission denied $perm_denials consecutive times"
            elif [[ $no_progress -ge $CB_NO_PROGRESS_THRESHOLD ]]; then
                new_state="$CB_STATE_OPEN"
                reason="No progress in $no_progress consecutive loops"
            elif [[ $same_error -ge $CB_SAME_ERROR_THRESHOLD ]]; then
                new_state="$CB_STATE_OPEN"
                reason="Same error repeated $same_error times"
            elif [[ $no_progress -ge 2 ]]; then
                new_state="$CB_STATE_HALF_OPEN"
                reason="Monitoring: $no_progress loops without progress"
            fi
            ;;
        "$CB_STATE_HALF_OPEN")
            if [[ "$has_progress" == "true" ]]; then
                new_state="$CB_STATE_CLOSED"
                reason="Progress detected, circuit recovered"
            elif [[ $no_progress -ge $CB_NO_PROGRESS_THRESHOLD ]]; then
                new_state="$CB_STATE_OPEN"
                reason="No recovery after $no_progress loops"
            fi
            ;;
        "$CB_STATE_OPEN")
            reason="Circuit is open, execution halted"
            ;;
    esac

    local total_opens
    total_opens=$(echo "$state_data" | jq -r '.total_opens // 0')
    if [[ "$new_state" == "$CB_STATE_OPEN" && "$current_state" != "$CB_STATE_OPEN" ]]; then
        total_opens=$((total_opens + 1))
    fi

    # Build opened_at
    local opened_at_field=""
    if [[ "$new_state" == "$CB_STATE_OPEN" && "$current_state" != "$CB_STATE_OPEN" ]]; then
        opened_at_field=", \"opened_at\": \"$(date -u +%Y-%m-%dT%H:%M:%SZ)\""
    elif [[ "$new_state" == "$CB_STATE_OPEN" ]]; then
        local prev_opened
        prev_opened=$(echo "$state_data" | jq -r '.opened_at // ""')
        if [[ -n "$prev_opened" && "$prev_opened" != "null" ]]; then
            opened_at_field=", \"opened_at\": \"$prev_opened\""
        fi
    fi

    cat > "$CB_STATE_FILE" << CBEOF
{
    "state": "$new_state",
    "last_change": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
    "consecutive_no_progress": $no_progress,
    "consecutive_same_error": $same_error,
    "consecutive_permission_denials": $perm_denials,
    "last_progress_loop": $last_progress,
    "total_opens": $total_opens,
    "current_loop": $loop_number,
    "reason": "$reason"$opened_at_field
}
CBEOF

    # Log transition
    if [[ "$new_state" != "$current_state" ]]; then
        cb_log_transition "$current_state" "$new_state" "$reason" "$loop_number"
    fi

    [[ "$new_state" != "$CB_STATE_OPEN" ]]
}

# Log state transition
cb_log_transition() {
    local from=$1 to=$2 reason=$3 loop=$4

    local history
    history=$(cat "$CB_HISTORY_FILE")
    local entry="{\"timestamp\":\"$(date -u +%Y-%m-%dT%H:%M:%SZ)\",\"loop\":$loop,\"from\":\"$from\",\"to\":\"$to\",\"reason\":\"$reason\"}"
    echo "$history" | jq ". += [$entry]" > "$CB_HISTORY_FILE"

    case $to in
        "$CB_STATE_OPEN")
            echo -e "${RED}[CB] CIRCUIT BREAKER OPENED — $reason${NC}"
            ;;
        "$CB_STATE_HALF_OPEN")
            echo -e "${YELLOW}[CB] Monitoring mode — $reason${NC}"
            ;;
        "$CB_STATE_CLOSED")
            echo -e "${GREEN}[CB] Normal operation — $reason${NC}"
            ;;
    esac
}

# Transition state directly
cb_transition() {
    local new_state=$1 reason=$2 loop=${3:-0}
    local current_state
    current_state=$(cb_state)

    local state_data
    state_data=$(cat "$CB_STATE_FILE")
    echo "$state_data" | jq \
        --arg state "$new_state" \
        --arg reason "$reason" \
        --arg ts "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
        '.state = $state | .reason = $reason | .last_change = $ts' \
        > "$CB_STATE_FILE"

    cb_log_transition "$current_state" "$new_state" "$reason" "$loop"
}

# Reset circuit breaker
cb_reset() {
    local reason=${1:-"Manual reset"}
    cat > "$CB_STATE_FILE" << CBEOF
{
    "state": "$CB_STATE_CLOSED",
    "last_change": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
    "consecutive_no_progress": 0,
    "consecutive_same_error": 0,
    "consecutive_permission_denials": 0,
    "last_progress_loop": 0,
    "total_opens": 0,
    "current_loop": 0,
    "reason": "$reason"
}
CBEOF
    echo -e "${GREEN}[CB] Circuit breaker reset: $reason${NC}"
}

# Display status
cb_show_status() {
    cb_init
    local state reason no_progress last_progress total_opens
    state=$(jq -r '.state' "$CB_STATE_FILE")
    reason=$(jq -r '.reason' "$CB_STATE_FILE")
    no_progress=$(jq -r '.consecutive_no_progress' "$CB_STATE_FILE")
    last_progress=$(jq -r '.last_progress_loop' "$CB_STATE_FILE")
    total_opens=$(jq -r '.total_opens' "$CB_STATE_FILE")

    local icon color
    case $state in
        "$CB_STATE_CLOSED")  icon="OK" color="$GREEN" ;;
        "$CB_STATE_HALF_OPEN") icon="!!" color="$YELLOW" ;;
        "$CB_STATE_OPEN")    icon="XX" color="$RED" ;;
    esac

    echo -e "${color}[$icon] Circuit Breaker: $state${NC}"
    echo -e "  Reason:             $reason"
    echo -e "  Loops w/o progress: $no_progress"
    echo -e "  Last progress:      Loop #$last_progress"
    echo -e "  Total opens:        $total_opens"
}
