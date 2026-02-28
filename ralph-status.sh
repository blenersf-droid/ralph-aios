#!/bin/bash
# RALPH+ Status — Progress Dashboard
# Shows current progress of stories (AIOS format + prd.json)
#
# Usage: ./ralph-status.sh

set -eo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Source only what we need
source "$SCRIPT_DIR/config/defaults.sh"
source "$SCRIPT_DIR/config/circuit-breaker.sh"
source "$SCRIPT_DIR/config/aios-bridge.sh"
source "$SCRIPT_DIR/lib/safety.sh"

# Load .ralphrc
[[ -f ".ralphrc" ]] && source ".ralphrc"

# Detect mode
mode=$(detect_aios)

echo ""
echo -e "${WHITE}=================================================================${NC}"
echo -e "${CYAN}                     RALPH+ STATUS${NC}"
echo -e "${WHITE}=================================================================${NC}"
echo ""

# Mode info
echo -e "${YELLOW}Mode:${NC} $mode"

if [[ "$mode" == "aios" ]]; then
    # AIOS mode: show stories from docs/stories/
    echo -e "${YELLOW}Story dir:${NC} $AIOS_STORY_DIR"
    echo ""

    stories=$(read_aios_stories)
    total=$(echo "$stories" | jq 'length')
    done_count=$(echo "$stories" | jq '[.[] | select(.status == "Done")] | length')
    in_progress=$(echo "$stories" | jq '[.[] | select(.status == "InProgress" or .status == "In Progress")] | length')
    ready=$(echo "$stories" | jq '[.[] | select(.status == "Ready")] | length')
    draft=$(echo "$stories" | jq '[.[] | select(.status == "Draft")] | length')

    # Progress bar
    if [[ $total -gt 0 ]]; then
        percent=$((done_count * 100 / total))
        bar_width=40
        filled=$((percent * bar_width / 100))
        empty=$((bar_width - filled))

        echo -ne "${YELLOW}Progress:${NC} ["
        for ((i=0; i<filled; i++)); do echo -ne "${GREEN}#${NC}"; done
        for ((i=0; i<empty; i++)); do echo -ne "."; done
        echo -e "] ${percent}%"
    fi

    echo ""
    echo -e "${GREEN}Done:${NC}        $done_count"
    echo -e "${CYAN}In Progress:${NC} $in_progress"
    echo -e "${YELLOW}Ready:${NC}       $ready"
    echo -e "${WHITE}Draft:${NC}       $draft"
    echo -e "${BLUE}Total:${NC}       $total"
    echo ""

    # List stories
    echo -e "${WHITE}=================================================================${NC}"
    echo -e "${CYAN}                       STORIES${NC}"
    echo -e "${WHITE}=================================================================${NC}"
    echo ""

    echo "$stories" | jq -r '.[] |
        if .status == "Done" then
            "  [x] \(.id): \(.title) (Done)"
        elif .status == "InProgress" or .status == "In Progress" then
            "  [>] \(.id): \(.title) (In Progress)"
        elif .status == "Ready" then
            "  [ ] \(.id): \(.title) (Ready)"
        else
            "  [-] \(.id): \(.title) (\(.status))"
        end'

else
    # Standalone mode: show stories from prd.json
    if [[ ! -f "$PRD_FILE" ]]; then
        echo -e "${RED}No prd.json found${NC}"
        exit 1
    fi

    project=$(jq -r '.project // "Unknown"' "$PRD_FILE")
    branch=$(jq -r '.branchName // "Unknown"' "$PRD_FILE")
    echo -e "${YELLOW}Project:${NC} $project"
    echo -e "${YELLOW}Branch:${NC}  $branch"
    echo ""

    total=$(jq '.userStories | length' "$PRD_FILE")
    complete=$(jq '[.userStories[] | select(.passes == true)] | length' "$PRD_FILE")
    remaining=$((total - complete))

    # Progress bar
    if [[ $total -gt 0 ]]; then
        percent=$((complete * 100 / total))
        bar_width=40
        filled=$((percent * bar_width / 100))
        empty=$((bar_width - filled))

        echo -ne "${YELLOW}Progress:${NC} ["
        for ((i=0; i<filled; i++)); do echo -ne "${GREEN}#${NC}"; done
        for ((i=0; i<empty; i++)); do echo -ne "."; done
        echo -e "] ${percent}%"
    fi

    echo ""
    echo -e "${GREEN}Complete:${NC}  $complete"
    echo -e "${YELLOW}Remaining:${NC} $remaining"
    echo -e "${BLUE}Total:${NC}     $total"
    echo ""

    # List stories
    echo -e "${WHITE}=================================================================${NC}"
    echo -e "${CYAN}                       STORIES${NC}"
    echo -e "${WHITE}=================================================================${NC}"
    echo ""

    jq -r '.userStories[] |
        if .passes then
            "  [x] \(.id): \(.title)"
        else
            "  [ ] \(.id): \(.title)"
        end' "$PRD_FILE"

    # Next story
    if [[ $remaining -gt 0 ]]; then
        echo ""
        next=$(jq -r '[.userStories[] | select(.passes == false)] | sort_by(.priority) | .[0] | "\(.id): \(.title)"' "$PRD_FILE")
        echo -e "${YELLOW}Next up:${NC} $next"
    fi
fi

# Circuit breaker status
echo ""
echo -e "${WHITE}=================================================================${NC}"
echo -e "${CYAN}                   SYSTEM STATUS${NC}"
echo -e "${WHITE}=================================================================${NC}"
echo ""

# Initialize CB if needed
mkdir -p "$RALPH_DIR"
cb_init 2>/dev/null
cb_show_status

echo ""
echo -e "  Rate limit: $(rate_status 2>/dev/null || echo 'N/A')"

# Recent activity
if [[ -f "$LOG_DIR/ralph.log" ]]; then
    echo ""
    echo -e "${BLUE}  Recent Activity:${NC}"
    tail -5 "$LOG_DIR/ralph.log" 2>/dev/null | sed 's/^/    /'
fi

echo ""
