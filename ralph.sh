#!/bin/bash
# RALPH+ — Autonomous Execution Engine for Synkra AIOS
# A Ralph-based loop that orchestrates AIOS agents (@dev, @qa) autonomously
#
# Usage:
#   ./ralph.sh [options] [max_iterations]
#
# Options:
#   --live          Show Claude Code output in real-time
#   --reset         Reset circuit breaker and start fresh
#   --status        Show current status and exit
#   --verbose       Enable verbose logging
#   --standalone    Force standalone mode (ignore AIOS)
#   --help          Show help

set -eo pipefail

# ─── Resolve Paths ────────────────────────────────────────────
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# ─── Source Components ────────────────────────────────────────
source "$SCRIPT_DIR/config/defaults.sh"
source "$SCRIPT_DIR/config/circuit-breaker.sh"
source "$SCRIPT_DIR/config/aios-bridge.sh"
source "$SCRIPT_DIR/lib/safety.sh"
source "$SCRIPT_DIR/lib/memory.sh"
source "$SCRIPT_DIR/lib/hooks.sh"
source "$SCRIPT_DIR/lib/monitor.sh"
source "$SCRIPT_DIR/lib/loop.sh"

# ─── Load .ralphrc ────────────────────────────────────────────
load_ralphrc() {
    local rc_file=".ralphrc"
    if [[ -f "$rc_file" ]]; then
        source "$rc_file"
        [[ "$VERBOSE" == "true" ]] && echo -e "${CYAN}[CONFIG] Loaded .ralphrc${NC}"
    fi
}

# ─── Parse Arguments ─────────────────────────────────────────
parse_args() {
    local force_standalone=false

    while [[ $# -gt 0 ]]; do
        case $1 in
            --live)
                LIVE_OUTPUT=true
                shift
                ;;
            --reset)
                cb_reset "User requested reset"
                echo "0" > "$CALL_COUNT_FILE" 2>/dev/null
                echo -e "${GREEN}RALPH+ reset complete${NC}"
                exit 0
                ;;
            --status)
                show_status_and_exit
                ;;
            --verbose|-v)
                VERBOSE=true
                shift
                ;;
            --standalone)
                force_standalone=true
                shift
                ;;
            --help|-h)
                show_help
                exit 0
                ;;
            *)
                if [[ "$1" =~ ^[0-9]+$ ]]; then
                    MAX_ITERATIONS="$1"
                fi
                shift
                ;;
        esac
    done

    if [[ "$force_standalone" == "true" ]]; then
        AIOS_ENABLED="false"
    fi
}

# ─── Show Help ────────────────────────────────────────────────
show_help() {
    cat << 'HELPEOF'

  RALPH+ — Autonomous Execution Engine for Synkra AIOS

  Usage:
    ./ralph.sh [options] [max_iterations]

  Options:
    --live          Show Claude Code output in real-time
    --reset         Reset circuit breaker and counters
    --status        Show current status and exit
    --verbose, -v   Enable verbose logging
    --standalone    Force standalone mode (ignore AIOS)
    --help, -h      Show this help

  Configuration:
    Create a .ralphrc file in your project root.
    See .ralphrc.example for all available options.

  Modes:
    AIOS Mode       Detected automatically when .aios-core/ exists
                    Uses @dev and @qa agents, story files, handoffs

    Standalone      When no AIOS detected (or --standalone)
                    Uses prd.json format (classic Ralph)

  Examples:
    ./ralph.sh                    # Auto-detect mode, 20 iterations
    ./ralph.sh 50                 # 50 iterations max
    ./ralph.sh --live             # With real-time output
    ./ralph.sh --standalone 10   # Force standalone, 10 iterations

HELPEOF
}

# ─── Show Status ──────────────────────────────────────────────
show_status_and_exit() {
    local mode
    mode=$(detect_aios)

    echo ""
    echo -e "${WHITE}=================================================================${NC}"
    echo -e "${WHITE}                     RALPH+ STATUS${NC}"
    echo -e "${WHITE}=================================================================${NC}"
    echo ""
    echo -e "  Mode:          ${CYAN}$mode${NC}"
    echo -e "  Stories:       $(get_story_summary "$mode")"
    echo -e "  Rate limit:    $(rate_status)"
    echo ""
    cb_show_status
    echo ""

    # Show recent log entries
    if [[ -f "$LOG_DIR/ralph.log" ]]; then
        echo -e "${BLUE}  Recent Activity:${NC}"
        tail -5 "$LOG_DIR/ralph.log" | sed 's/^/    /'
    fi

    echo ""
    exit 0
}

# ─── Main ─────────────────────────────────────────────────────
main() {
    # Load configuration
    load_ralphrc
    parse_args "$@"

    # Initialize
    mkdir -p "$RALPH_DIR" "$LOG_DIR"
    log_init
    rate_init
    memory_init
    cb_init

    # Validate dependencies
    if ! validate_deps; then
        exit 1
    fi

    # Detect mode
    local mode
    mode=$(detect_aios)

    # Banner
    echo ""
    echo -e "${WHITE}=================================================================${NC}"
    echo -e "${WHITE}     RALPH+ — Autonomous Execution Engine${NC}"
    echo -e "${WHITE}=================================================================${NC}"
    echo -e "  Mode:            ${CYAN}$mode${NC}"
    echo -e "  Max iterations:  ${WHITE}$MAX_ITERATIONS${NC}"
    echo -e "  Rate limit:      ${WHITE}$MAX_CALLS_PER_HOUR/hour${NC}"
    echo -e "  Claude timeout:  ${WHITE}${CLAUDE_TIMEOUT_MINUTES}min${NC}"
    echo -e "  Live output:     ${WHITE}$LIVE_OUTPUT${NC}"

    if [[ "$mode" == "aios" ]]; then
        echo -e "  AIOS dev mode:   ${WHITE}$AIOS_DEV_MODE${NC}"
        echo -e "  AIOS QA:         ${WHITE}$AIOS_QA_ENABLED${NC}"
    fi

    echo -e "  Stories:         $(get_story_summary "$mode")"
    echo -e "${WHITE}=================================================================${NC}"
    echo ""

    log INFO "RALPH+ started: mode=$mode, max_iterations=$MAX_ITERATIONS"

    # Validate stories exist
    if [[ "$mode" == "aios" ]]; then
        local story_count
        story_count=$(read_aios_stories | jq 'length')
        if [[ "$story_count" -eq 0 ]]; then
            echo -e "${RED}[ERROR] No AIOS stories found in $AIOS_STORY_DIR${NC}"
            echo "  Create stories first: @sm *draft"
            exit 1
        fi
    else
        if [[ ! -f "$PRD_FILE" ]]; then
            echo -e "${RED}[ERROR] No prd.json found${NC}"
            echo "  Create a prd.json with your stories. See .ralphrc.example"
            exit 1
        fi
    fi

    # Run the loop
    if run_loop "$mode"; then
        log INFO "RALPH+ completed successfully"
        exit 0
    else
        log ERROR "RALPH+ stopped"
        exit 1
    fi
}

main "$@"
