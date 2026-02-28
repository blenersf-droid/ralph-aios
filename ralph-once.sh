#!/bin/bash
# RALPH+ Single Iteration — Debug/Manual Mode
# Runs exactly one iteration for testing and debugging
#
# Usage: ./ralph-once.sh [--live] [--standalone]

set -eo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Source components
source "$SCRIPT_DIR/config/defaults.sh"
source "$SCRIPT_DIR/config/circuit-breaker.sh"
source "$SCRIPT_DIR/config/aios-bridge.sh"
source "$SCRIPT_DIR/lib/safety.sh"
source "$SCRIPT_DIR/lib/memory.sh"
source "$SCRIPT_DIR/lib/hooks.sh"
source "$SCRIPT_DIR/lib/monitor.sh"
source "$SCRIPT_DIR/lib/loop.sh"

# Load .ralphrc
[[ -f ".ralphrc" ]] && source ".ralphrc"

# Parse args
while [[ $# -gt 0 ]]; do
    case $1 in
        --live) LIVE_OUTPUT=true; shift ;;
        --standalone) AIOS_ENABLED=false; shift ;;
        --verbose|-v) VERBOSE=true; shift ;;
        *) shift ;;
    esac
done

# Initialize
mkdir -p "$RALPH_DIR" "$LOG_DIR"
log_init
rate_init
memory_init
cb_init

# Validate
if ! validate_deps; then
    exit 1
fi

# Detect mode
mode=$(detect_aios)

echo ""
echo -e "${BLUE}=================================================================${NC}"
echo -e "${YELLOW}           RALPH+ SINGLE ITERATION${NC}"
echo -e "${BLUE}=================================================================${NC}"
echo -e "  Mode: ${CYAN}$mode${NC}"
echo -e "  Stories: $(get_story_summary "$mode")"
echo ""

# Get next story
story_json=""
if [[ "$mode" == "aios" ]]; then
    story_json=$(get_next_aios_story)
else
    story_json=$(get_next_prd_story)
fi

if ! validate_story "$mode" "$story_json"; then
    if all_stories_done "$mode"; then
        echo -e "${GREEN}All stories already complete!${NC}"
    else
        echo -e "${RED}No valid stories to work on${NC}"
    fi
    exit 0
fi

story_id=$(echo "$story_json" | jq -r '.id')
echo -e "  Next story: ${WHITE}$story_id${NC}"
echo ""

# Run single iteration
run_iteration 1 "$mode" "$story_json"
result=$?

echo ""
echo -e "${BLUE}=================================================================${NC}"

if [[ $result -eq 0 ]]; then
    echo -e "${GREEN}  Iteration completed successfully${NC}"
else
    echo -e "${YELLOW}  Iteration result: $result${NC}"
fi

echo -e "  Stories: $(get_story_summary "$mode")"
echo -e "${BLUE}=================================================================${NC}"
echo ""

[[ $result -eq 0 ]] && echo "Run again: ./ralph-once.sh" || echo "Check logs: tail -20 $LOG_DIR/ralph.log"
