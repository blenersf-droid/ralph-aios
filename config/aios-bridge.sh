#!/bin/bash
# RALPH+ AIOS Bridge
# Integration layer between RALPH+ loop and Synkra AIOS framework

# Cross-platform sed in-place edit (GNU sed vs BSD sed)
sed_inplace() {
    local expression="$1"
    local file="$2"

    if sed --version >/dev/null 2>&1; then
        # GNU sed
        sed -i "$expression" "$file"
    else
        # BSD sed (macOS)
        sed -i '' "$expression" "$file"
    fi
}

# Detect if AIOS is installed
detect_aios() {
    if [[ "$AIOS_ENABLED" == "false" ]]; then
        echo "standalone"
        return
    fi

    if [[ -d ".aios-core" ]] && [[ -f ".aios-core/constitution.md" ]]; then
        echo "aios"
    else
        echo "standalone"
    fi
}

# Read AIOS stories and return as JSON array
# Output: [{id, title, status, path, epic, ac_total, ac_done, priority}]
read_aios_stories() {
    local story_dir="${AIOS_STORY_DIR:-docs/stories}"
    local stories="[]"

    if [[ ! -d "$story_dir" ]]; then
        echo "$stories"
        return
    fi

    while IFS= read -r -d '' story_file; do
        local content
        content=$(cat "$story_file")

        # Parse story metadata from markdown (POSIX-compatible, no grep -oP)
        local story_id story_title story_status story_epic
        story_id=$(echo "$content" | sed -n 's/^Story ID:[[:space:]]*//p' | head -1 | tr -d '[:space:]')
        if [[ -z "$story_id" ]]; then
            # Try alternative format: # Story {ID}: {Title}
            story_id=$(echo "$content" | sed -n 's/^# Story \([^:]*\):.*/\1/p' | head -1 | tr -d '[:space:]')
        fi
        story_title=$(echo "$content" | sed -n 's/^# Story [^:]*:[[:space:]]*//p' | head -1)
        if [[ -z "$story_title" ]]; then
            story_title=$(echo "$content" | head -1 | sed 's/^# //')
        fi
        story_status=$(echo "$content" | sed -n 's/^.*Status:[[:space:]]*//p' | head -1 | tr -d '[:space:]')
        story_epic=$(echo "$content" | sed -n 's/^.*Epic:[[:space:]]*//p' | head -1 | tr -d '[:space:]')

        # Count acceptance criteria
        local ac_total ac_done
        ac_total=$(echo "$content" | grep -c '^\s*- \[.\] ' 2>/dev/null || echo 0)
        ac_done=$(echo "$content" | grep -c '^\s*- \[x\] ' 2>/dev/null || echo 0)

        # Skip if no valid ID
        [[ -z "$story_id" ]] && continue

        # Build JSON entry
        local entry
        entry=$(jq -n \
            --arg id "$story_id" \
            --arg title "$story_title" \
            --arg status "${story_status:-Draft}" \
            --arg path "$story_file" \
            --arg epic "${story_epic:-}" \
            --argjson ac_total "${ac_total:-0}" \
            --argjson ac_done "${ac_done:-0}" \
            '{id: $id, title: $title, status: $status, path: $path, epic: $epic, ac_total: $ac_total, ac_done: $ac_done}')

        stories=$(echo "$stories" | jq ". += [$entry]")
    done < <(find "$story_dir" -name "*.story.md" -print0 2>/dev/null)

    echo "$stories"
}

# Get next story to work on (Ready or In Progress)
get_next_aios_story() {
    local stories
    stories=$(read_aios_stories)

    # Priority: In Progress first, then Ready
    local next
    next=$(echo "$stories" | jq -r '[.[] | select(.status == "InProgress" or .status == "In Progress")] | .[0] // empty')

    if [[ -z "$next" || "$next" == "null" ]]; then
        next=$(echo "$stories" | jq -r '[.[] | select(.status == "Ready")] | .[0] // empty')
    fi

    echo "$next"
}

# Update story status
update_story_status() {
    local story_path=$1
    local old_status=$2
    local new_status=$3

    if [[ ! -f "$story_path" ]]; then
        echo -e "${RED}[AIOS] Story not found: $story_path${NC}"
        return 1
    fi

    sed_inplace "s/Status: $old_status/Status: $new_status/" "$story_path"

    echo -e "${GREEN}[AIOS] Story status: $old_status -> $new_status${NC}"
}

# Mark an acceptance criterion as done
mark_ac_done() {
    local story_path=$1
    local ac_text=$2

    if [[ ! -f "$story_path" ]]; then
        return 1
    fi

    # Escape special characters for sed
    local escaped_text
    escaped_text=$(printf '%s\n' "$ac_text" | sed 's/[[\.*^$()+?{|]/\\&/g')

    sed_inplace "s/- \[ \] $escaped_text/- [x] $escaped_text/" "$story_path"
}

# Read prd.json (standalone fallback)
read_prd_stories() {
    local prd_file="${PRD_FILE:-prd.json}"

    if [[ ! -f "$prd_file" ]]; then
        echo "[]"
        return
    fi

    jq '.userStories // []' "$prd_file" 2>/dev/null || echo "[]"
}

# Get next story from prd.json
get_next_prd_story() {
    local prd_file="${PRD_FILE:-prd.json}"

    if [[ ! -f "$prd_file" ]]; then
        echo ""
        return
    fi

    jq -r '[.userStories[] | select(.passes == false)] | sort_by(.priority) | .[0] // empty' "$prd_file" 2>/dev/null
}

# Update prd.json story as passed
update_prd_story() {
    local story_id=$1
    local prd_file="${PRD_FILE:-prd.json}"

    if [[ ! -f "$prd_file" ]]; then
        return 1
    fi

    local tmp
    tmp=$(mktemp)
    jq --arg id "$story_id" '(.userStories[] | select(.id == $id)).passes = true' "$prd_file" > "$tmp" && mv "$tmp" "$prd_file"

    echo -e "${GREEN}[PRD] Story $story_id marked as passed${NC}"
}

# Check if all stories are complete
all_stories_done() {
    local mode=$1

    if [[ "$mode" == "aios" ]]; then
        local stories
        stories=$(read_aios_stories)
        local pending
        pending=$(echo "$stories" | jq '[.[] | select(.status != "Done")] | length')
        [[ "$pending" -eq 0 ]]
    else
        local prd_file="${PRD_FILE:-prd.json}"
        if [[ ! -f "$prd_file" ]]; then
            return 1
        fi
        local incomplete
        incomplete=$(jq '[.userStories[] | select(.passes == false)] | length' "$prd_file" 2>/dev/null || echo 1)
        [[ "$incomplete" -eq 0 ]]
    fi
}

# Get story count summary
get_story_summary() {
    local mode=$1

    if [[ "$mode" == "aios" ]]; then
        local stories
        stories=$(read_aios_stories)
        local total done in_progress ready
        total=$(echo "$stories" | jq 'length')
        done=$(echo "$stories" | jq '[.[] | select(.status == "Done")] | length')
        in_progress=$(echo "$stories" | jq '[.[] | select(.status == "InProgress" or .status == "In Progress")] | length')
        ready=$(echo "$stories" | jq '[.[] | select(.status == "Ready")] | length')
        echo "$done/$total done, $in_progress in progress, $ready ready"
    else
        local prd_file="${PRD_FILE:-prd.json}"
        if [[ ! -f "$prd_file" ]]; then
            echo "No prd.json found"
            return
        fi
        local total complete
        total=$(jq '.userStories | length' "$prd_file" 2>/dev/null || echo 0)
        complete=$(jq '[.userStories[] | select(.passes == true)] | length' "$prd_file" 2>/dev/null || echo 0)
        echo "$complete/$total complete"
    fi
}

# Generate AIOS-aware prompt for Claude Code
generate_aios_prompt() {
    local story_json=$1
    local iteration=$2
    local max_iterations=$3
    local learnings=$4

    local story_id story_title story_path story_status
    story_id=$(echo "$story_json" | jq -r '.id')
    story_title=$(echo "$story_json" | jq -r '.title')
    story_path=$(echo "$story_json" | jq -r '.path')
    story_status=$(echo "$story_json" | jq -r '.status')

    cat << PROMPTEOF
# RALPH+ Autonomous Agent — Iteration $iteration/$max_iterations

## Mode: AIOS (Synkra AIOS detected)

## Current Story
- **ID:** $story_id
- **Title:** $story_title
- **Path:** $story_path
- **Status:** $story_status

## Previous Learnings
$learnings

## Instructions

### Phase 1: Implementation
1. Read the complete story file at \`$story_path\`
2. Activate the @dev agent
3. Execute: \`*develop $story_id yolo\`
4. The @dev agent will:
   - Read acceptance criteria from the story
   - Implement each criterion
   - Run quality checks (lint, typecheck, test)
   - Commit changes with conventional message
   - Update the Dev Agent Record section

### Phase 2: Quality Gate
5. After implementation, activate @qa agent
6. Execute: \`*review $story_id\`
7. If QA identifies issues:
   - Activate @dev again
   - Fix the issues identified by @qa
   - Re-run quality checks

### Phase 3: Completion
8. Once QA passes, update the story status to "Done"
9. Mark all acceptance criteria checkboxes as [x]

## Response Format

After completing your work, output a JSON status block:
\`\`\`json
{
  "status": "COMPLETE|IN_PROGRESS|BLOCKED|ERROR",
  "exit_signal": true,
  "story_id": "$story_id",
  "files_modified": 0,
  "work_type": "implementation",
  "summary": "Brief description of what was done"
}
\`\`\`

## Rules
- Work on ONLY this story per iteration
- Do NOT skip quality checks
- Commit frequently with conventional messages
- Append learnings to progress.txt
- If blocked, report status as BLOCKED with reason
PROMPTEOF
}

# Generate standalone prompt for Claude Code
generate_standalone_prompt() {
    local story_json=$1
    local iteration=$2
    local max_iterations=$3
    local learnings=$4

    local story_id story_title
    story_id=$(echo "$story_json" | jq -r '.id')
    story_title=$(echo "$story_json" | jq -r '.title')

    local ac_list
    ac_list=$(echo "$story_json" | jq -r '.acceptanceCriteria[]? // empty' 2>/dev/null | sed 's/^/- /')

    cat << PROMPTEOF
# RALPH+ Autonomous Agent — Iteration $iteration/$max_iterations

## Mode: Standalone

## Current Story
- **ID:** $story_id
- **Title:** $story_title

## Acceptance Criteria
$ac_list

## Previous Learnings
$learnings

## Instructions

1. Read \`prd.json\` for full story details
2. Read \`progress.txt\` — check Codebase Patterns section first
3. Verify you are on the correct git branch
4. Implement the story: $story_title
5. Run quality checks (typecheck, lint, test)
6. If checks pass:
   - Commit ALL changes: \`feat: [$story_id] - $story_title\`
   - Update prd.json: set \`passes: true\` for $story_id
7. Append progress to progress.txt with learnings

## Response Format

\`\`\`json
{
  "status": "COMPLETE|IN_PROGRESS|BLOCKED|ERROR",
  "exit_signal": true,
  "story_id": "$story_id",
  "files_modified": 0,
  "work_type": "implementation",
  "summary": "Brief description"
}
\`\`\`

## Rules
- Work on ONE story per iteration
- Do NOT commit broken code
- Keep changes focused and minimal
- Follow existing code patterns
PROMPTEOF
}

# Write handoff artifact for agent transition
write_handoff() {
    local from_agent=$1
    local to_agent=$2
    local story_id=$3
    local story_path=$4
    local story_status=$5
    local next_action=$6

    local handoff_dir="${AIOS_HANDOFF_DIR:-.aios/handoffs}"
    mkdir -p "$handoff_dir"

    local timestamp
    timestamp=$(date -u +%Y-%m-%dT%H:%M:%SZ)
    local filename="handoff-${from_agent}-to-${to_agent}-$(date +%s).yaml"

    cat > "$handoff_dir/$filename" << HOEOF
handoff:
  version: "1.0"
  timestamp: "$timestamp"
  consumed: false
  from_agent: "$from_agent"
  to_agent: "$to_agent"
  story_context:
    story_id: "$story_id"
    story_path: "$story_path"
    story_status: "$story_status"
  next_action: "$next_action"
HOEOF

    echo -e "${CYAN}[AIOS] Handoff: @$from_agent -> @$to_agent${NC}"
}
