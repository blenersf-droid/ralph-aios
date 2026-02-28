#!/bin/bash
# RALPH+ Monitor Module
# tmux dashboard and logging

# ─── Logging ─────────────────────────────────────────────────

log_init() {
    mkdir -p "$LOG_DIR"
}

log() {
    local level=$1
    shift
    local msg="[$(date '+%Y-%m-%d %H:%M:%S')] [$level] $*"
    echo "$msg" >> "$LOG_DIR/ralph.log"

    case $level in
        INFO)  echo -e "${GREEN}$msg${NC}" ;;
        WARN)  echo -e "${YELLOW}$msg${NC}" ;;
        ERROR) echo -e "${RED}$msg${NC}" ;;
        DEBUG) [[ "$VERBOSE" == "true" ]] && echo -e "${CYAN}$msg${NC}" ;;
    esac
}

# ─── Display ─────────────────────────────────────────────────

# Display iteration header
show_iteration_header() {
    local iteration=$1
    local max=$2
    local mode=$3
    local story_id=$4

    echo ""
    echo -e "${WHITE}=================================================================${NC}"
    echo -e "${WHITE}  RALPH+ Iteration $iteration/$max  |  Mode: $mode  |  Story: $story_id${NC}"
    echo -e "${WHITE}=================================================================${NC}"
    echo ""
}

# Display completion summary
show_completion_summary() {
    local iteration=$1
    local mode=$2

    echo ""
    echo -e "${GREEN}=================================================================${NC}"
    echo -e "${GREEN}  RALPH+ COMPLETE${NC}"
    echo -e "${GREEN}=================================================================${NC}"
    echo -e "  Iterations: $iteration"
    echo -e "  Mode: $mode"
    echo -e "  Stories: $(get_story_summary "$mode")"
    echo -e "  Rate limit: $(rate_status)"
    echo -e "${GREEN}=================================================================${NC}"
    echo ""
}

# Display failure summary
show_failure_summary() {
    local iteration=$1
    local max=$2
    local mode=$3
    local reason=$4

    echo ""
    echo -e "${RED}=================================================================${NC}"
    echo -e "${RED}  RALPH+ STOPPED${NC}"
    echo -e "${RED}=================================================================${NC}"
    echo -e "  Reason: $reason"
    echo -e "  Iterations: $iteration/$max"
    echo -e "  Mode: $mode"
    echo -e "  Stories: $(get_story_summary "$mode")"
    echo -e "  Rate limit: $(rate_status)"
    echo ""
    echo -e "${YELLOW}  Next steps:${NC}"
    echo "    1. Review logs: tail -20 $LOG_DIR/ralph.log"
    echo "    2. Check progress: cat $PROGRESS_FILE"
    echo "    3. Reset and retry: ./ralph.sh --reset"
    echo -e "${RED}=================================================================${NC}"
    echo ""
}

# Display current status (one-liner)
show_inline_status() {
    local iteration=$1
    local mode=$2
    local story_id=$3

    local summary
    summary=$(get_story_summary "$mode")
    local rate
    rate=$(rate_status)
    local cb
    cb=$(cb_state)

    echo -e "${CYAN}[STATUS] Iter $iteration | $summary | Rate: $rate | CB: $cb${NC}"
}
