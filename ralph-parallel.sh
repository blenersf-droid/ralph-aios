#!/bin/bash
# RALPH+ Parallel Execution Engine
# Spawns multiple Claude Code instances in parallel for independent stories
# Stories are grouped into "waves" — all stories in a wave run simultaneously
# After all waves complete, @devops handles centralized commit + push
#
# Usage:
#   ./ralph-plus/ralph-parallel.sh --wave "15.1,15.3,15.4,15.5,15.6,16.2,16.3,16.4" --wave "15.2" --wave "16.1,16.5,16.6"
#   ./ralph-plus/ralph-parallel.sh --config waves.conf
#   ./ralph-plus/ralph-parallel.sh --wave "15.1,15.3" --dry-run

set -euo pipefail

# ─── Resolve directories ────────────────────────────────────────
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
cd "$PROJECT_ROOT"

# ─── Source Ralph dependencies ──────────────────────────────────
source "$SCRIPT_DIR/config/defaults.sh"

# Load .ralphrc if exists
if [[ -f ".ralphrc" ]]; then
    set -a
    source ".ralphrc"
    set +a
fi

source "$SCRIPT_DIR/config/aios-bridge.sh"

# ─── Parallel-specific defaults ─────────────────────────────────
MAX_PARALLEL=${MAX_PARALLEL:-8}
WAVE_SLEEP=${WAVE_SLEEP:-5}
PARALLEL_LOG_DIR="${RALPH_DIR}/parallel"
PARALLEL_TIMEOUT_MINUTES=${PARALLEL_TIMEOUT_MINUTES:-${CLAUDE_TIMEOUT_MINUTES:-30}}

# ─── Globals ────────────────────────────────────────────────────
declare -a WAVES=()
DRY_RUN=false
SKIP_INSTALL=false
TOTAL_STORIES=0
COMPLETED_STORIES=0
FAILED_STORIES=0
STORIES_CACHE_FILE=""
STORIES_CACHE_LOADED=false

# ─── Logging ────────────────────────────────────────────────────
log_parallel() {
    local level=$1
    shift
    local msg="$*"
    local ts
    ts=$(date '+%Y-%m-%d %H:%M:%S')
    echo -e "[$ts] [$level] $msg" >> "${LOG_DIR}/ralph-parallel.log"

    # Output to stderr to avoid polluting stdout (important for $() subshells)
    case "$level" in
        INFO)  echo -e "${GREEN}[PARALLEL]${NC} $msg" >&2 ;;
        WARN)  echo -e "${YELLOW}[PARALLEL]${NC} $msg" >&2 ;;
        ERROR) echo -e "${RED}[PARALLEL]${NC} $msg" >&2 ;;
        *)     echo -e "[PARALLEL] $msg" >&2 ;;
    esac
}

# ─── Parse arguments ────────────────────────────────────────────
parse_args() {
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --wave)
                shift
                WAVES+=("$1")
                shift
                ;;
            --config)
                shift
                load_wave_config "$1"
                shift
                ;;
            --dry-run)
                DRY_RUN=true
                shift
                ;;
            --skip-install)
                SKIP_INSTALL=true
                shift
                ;;
            --max-parallel)
                shift
                MAX_PARALLEL=$1
                shift
                ;;
            --timeout)
                shift
                PARALLEL_TIMEOUT_MINUTES=$1
                shift
                ;;
            --help|-h)
                show_help
                exit 0
                ;;
            *)
                echo -e "${RED}Unknown argument: $1${NC}"
                show_help
                exit 1
                ;;
        esac
    done

    if [[ ${#WAVES[@]} -eq 0 ]]; then
        echo -e "${RED}Error: No waves defined. Use --wave or --config.${NC}"
        show_help
        exit 1
    fi
}

# ─── Load wave config from file ─────────────────────────────────
load_wave_config() {
    local config_file=$1
    if [[ ! -f "$config_file" ]]; then
        echo -e "${RED}Config file not found: $config_file${NC}"
        exit 1
    fi

    while IFS= read -r line; do
        # Skip comments and empty lines
        [[ "$line" =~ ^#.*$ ]] && continue
        [[ -z "${line// }" ]] && continue
        WAVES+=("$line")
    done < "$config_file"
}

# ─── Help ────────────────────────────────────────────────────────
show_help() {
    cat << 'EOF'
RALPH+ Parallel Execution Engine

Usage:
  ./ralph-plus/ralph-parallel.sh [OPTIONS]

Options:
  --wave "id1,id2,..."    Define a wave of stories to run in parallel
                          Multiple --wave flags define sequential waves
  --config FILE           Load wave definitions from file
  --dry-run               Show execution plan without running
  --skip-install          Skip npm package pre-installation
  --max-parallel N        Max concurrent Claude instances (default: 8)
  --timeout N             Timeout per story in minutes (default: 30)
  --help                  Show this help

Examples:
  # Run 3 waves sequentially, stories within each wave run in parallel
  ./ralph-plus/ralph-parallel.sh \
    --wave "15.1,15.3,15.4,15.5,15.6,16.2,16.3,16.4" \
    --wave "15.2" \
    --wave "16.1,16.5,16.6"

  # Load from config file
  ./ralph-plus/ralph-parallel.sh --config ralph-plus/waves.conf

Wave Config File Format (one wave per line, comma-separated story IDs):
  # Wave 1 - Independent stories
  15.1,15.3,15.4,15.5,15.6,16.2,16.3,16.4
  # Wave 2 - Depends on notification infra
  15.2
  # Wave 3 - Depends on Waves 1-2
  16.1,16.5,16.6
EOF
}

# ─── Generate parallel-specific prompt ──────────────────────────
# Modified prompt: NO git commit, NO npm install (done centrally)
generate_parallel_prompt() {
    local story_json=$1
    local wave_num=$2
    local wave_total=$3

    local story_id story_title story_path story_status
    story_id=$(echo "$story_json" | jq -r '.id')
    story_title=$(echo "$story_json" | jq -r '.title')
    story_path=$(echo "$story_json" | jq -r '.path')
    story_status=$(echo "$story_json" | jq -r '.status')

    cat << PROMPTEOF
# RALPH+ Parallel Agent — Wave $wave_num/$wave_total

## Mode: AIOS Parallel (multiple Claude instances running concurrently)

## Current Story
- **ID:** $story_id
- **Title:** $story_title
- **Path:** $story_path
- **Status:** $story_status

## CRITICAL: Parallel Execution Rules
- You are ONE of multiple Claude instances running simultaneously
- Do NOT run \`npm install\` — packages are pre-installed
- Do NOT run \`git commit\` or \`git add\` — commits handled centrally after all stories complete
- Do NOT modify files outside your story scope (other stories are being worked on in parallel)
- Focus ONLY on implementing YOUR story's acceptance criteria

## Instructions

You are running in non-interactive mode (--print). Do NOT try to activate agents with @ or run * commands. Execute all work directly.

### Phase 1: Preparation
1. Read the complete story file at \`$story_path\`
2. Read the acceptance criteria (AC) and tasks/subtasks carefully
3. Read the Dev Notes section for libraries, patterns, and file references
4. Check existing code in \`squads/\` for patterns to follow

### Phase 2: Implementation
5. Implement each acceptance criterion, one at a time
6. Follow existing code patterns in the project
7. Use TypeScript with proper types — no \`any\` unless absolutely necessary
8. Use absolute imports as per project convention
9. Create NEW files for new components — do NOT edit files that other stories might be editing simultaneously

### Phase 3: Quality Gate (MANDATORY — do NOT skip)
10. Run typecheck: \`cd squads && npx tsc --noEmit -p apps/web/tsconfig.json\`
    - If errors in YOUR files: FIX them
    - If errors in OTHER files (from parallel stories): IGNORE them
11. Run lint on YOUR files only:
    - List the files you created/modified
    - Run: \`cd squads && npx eslint <your-files> --max-warnings 0\` (only on your files)
12. If the story has testable logic (calculators, utils, hooks):
    - Write unit tests
    - Run ONLY your tests: \`cd squads && npx jest <your-test-file> --passWithNoTests\`

### Phase 4: QA Self-Review (MANDATORY)
13. For EACH acceptance criterion, verify:
    - Is it actually implemented? (not just partially)
    - Does it work as described?
    - Are edge cases handled?
14. Check for common issues:
    - No hardcoded strings that should be configurable
    - No missing error handling on async operations
    - No missing loading/empty states in UI
    - No unused imports or dead code
    - Components have proper TypeScript props interfaces

### Phase 5: Completion
15. Update the story file:
    - Mark completed task checkboxes: \`- [ ]\` → \`- [x]\`
    - Change status line to: \`Status: Done\`

## Response Format

After completing your work, output a JSON status block:
\`\`\`json
{
  "status": "COMPLETE|IN_PROGRESS|BLOCKED|ERROR",
  "exit_signal": true,
  "story_id": "$story_id",
  "files_modified": 0,
  "files_created": [],
  "files_edited": [],
  "work_type": "implementation",
  "summary": "Brief description of what was done",
  "quality_gate": {
    "typecheck": "PASS|FAIL|PARTIAL",
    "lint": "PASS|FAIL",
    "tests": "PASS|FAIL|SKIPPED",
    "ac_coverage": "N/N"
  }
}
\`\`\`

## Rules
- Work on ONLY this story
- Do NOT run npm install or git commit
- Do NOT edit shared config files (next.config.ts, layout.tsx, package.json) — flag them in summary if needed
- If a shared file needs changes, list it in the response under "shared_file_changes_needed"
- Do NOT mark COMPLETE unless quality gates pass for YOUR files
- If a dependency is missing: report status as BLOCKED with reason
- Prefer creating new files over editing existing ones (reduces parallel conflicts)
PROMPTEOF
}

# ─── Fast story reader (single jq call) ─────────────────────────
# Builds a TSV temp file first, then converts to JSON array with one jq call
read_aios_stories_fast() {
    local story_dir="${AIOS_STORY_DIR:-docs/stories}"
    local jsonl_tmp
    jsonl_tmp=$(mktemp)

    if [[ ! -d "$story_dir" ]]; then
        echo "[]"
        rm -f "$jsonl_tmp"
        return
    fi

    # Use plain find (no -print0) for Git Bash compatibility
    while IFS= read -r story_file; do
        [[ -z "$story_file" ]] && continue

        local story_id story_title story_status
        story_id=$(sed -n 's/^# Story \([^:]*\):.*/\1/p' "$story_file" | head -1 | tr -d '[:space:]')
        [[ -z "$story_id" ]] && story_id=$(sed -n 's/^Story ID:[[:space:]]*//p' "$story_file" | head -1 | tr -d '[:space:]')
        story_title=$(sed -n 's/^# Story [^:]*:[[:space:]]*//p' "$story_file" | head -1)
        [[ -z "$story_title" ]] && story_title=$(head -1 "$story_file" | sed 's/^# //')
        story_status=$(grep -m1 'Status:' "$story_file" | sed 's/.*Status:[[:space:]]*//' | tr -d '[:space:]')

        local ac_total ac_done
        ac_total=$(grep -c '^\s*- \[.\] ' "$story_file" 2>/dev/null || true)
        [[ -z "$ac_total" ]] && ac_total=0
        ac_done=$(grep -c '^\s*- \[x\] ' "$story_file" 2>/dev/null || true)
        [[ -z "$ac_done" ]] && ac_done=0

        [[ -z "$story_id" ]] && continue

        printf '%s\t%s\t%s\t%s\t\t%s\t%s\n' \
            "$story_id" "$story_title" "${story_status:-Draft}" "$story_file" "${ac_total:-0}" "${ac_done:-0}" \
            >> "$jsonl_tmp"
    done < <(find "$story_dir" -name "*.story.md" 2>/dev/null)

    # Single jq call to convert TSV to JSON array
    jq -Rsn '
        [inputs | split("\n")[] | select(length > 0) | split("\t") |
         {id: .[0], title: .[1], status: .[2], path: .[3], epic: .[4],
          ac_total: (.[5] | tonumber), ac_done: (.[6] | tonumber)}]
    ' "$jsonl_tmp"

    rm -f "$jsonl_tmp"
}

# ─── Load stories cache (call once from main, not from subshell) ─
load_stories_cache() {
    STORIES_CACHE_FILE=$(mktemp)
    log_parallel INFO "Loading stories cache..."
    read_aios_stories_fast > "$STORIES_CACHE_FILE"
    local count
    count=$(jq 'length' "$STORIES_CACHE_FILE")
    log_parallel INFO "Cached $count stories"
}

# ─── Reload cache (after status updates between waves) ──────────
reload_stories_cache() {
    rm -f "$STORIES_CACHE_FILE"
    load_stories_cache
}

# ─── Cleanup temp files on exit ─────────────────────────────────
cleanup_parallel() {
    if [[ -n "${STORIES_CACHE_FILE:-}" && -f "$STORIES_CACHE_FILE" ]]; then
        rm -f "$STORIES_CACHE_FILE"
    fi
    return 0
}
trap cleanup_parallel EXIT

# ─── Find story JSON by ID (uses pre-loaded cache file) ─────────
get_story_by_id() {
    local target_id=$1
    if [[ ! -f "${STORIES_CACHE_FILE:-}" ]]; then
        log_parallel ERROR "Stories cache not loaded. Call load_stories_cache first."
        return 1
    fi
    jq -r --arg id "$target_id" '.[] | select(.id == $id) // empty' "$STORIES_CACHE_FILE"
}

# ─── Pre-install packages for a wave ────────────────────────────
pre_install_packages() {
    local wave_stories=$1

    log_parallel INFO "Scanning stories for required packages..."

    local all_packages=()

    IFS=',' read -ra story_ids <<< "$wave_stories"
    for story_id in "${story_ids[@]}"; do
        story_id=$(echo "$story_id" | tr -d '[:space:]')
        local story_json
        story_json=$(get_story_by_id "$story_id")

        if [[ -z "$story_json" || "$story_json" == "null" ]]; then
            continue
        fi

        local story_path
        story_path=$(echo "$story_json" | jq -r '.path')

        if [[ -f "$story_path" ]]; then
            # Extract package names from Dev Notes section
            local content
            content=$(cat "$story_path")

            # Look for npm package references (e.g., `package-name`, npm install package)
            local packages
            packages=$(echo "$content" | grep -oE '`(@?[a-z][a-z0-9-]*(/[a-z][a-z0-9-]*)?)`' | tr -d '`' | sort -u || true)

            if [[ -n "$packages" ]]; then
                while IFS= read -r pkg; do
                    # Filter out non-package names (commands, paths, etc.)
                    if [[ "$pkg" =~ ^@?[a-z] ]] && [[ ! "$pkg" =~ \.tsx?$ ]] && [[ ! "$pkg" =~ / && ! "$pkg" =~ ^(npm|npx|cd|git|feat|fix)$ ]]; then
                        all_packages+=("$pkg")
                    fi
                done <<< "$packages"
            fi
        fi
    done

    if [[ ${#all_packages[@]} -eq 0 ]]; then
        log_parallel INFO "No packages to pre-install"
        return 0
    fi

    # Deduplicate
    local unique_packages
    unique_packages=$(printf '%s\n' "${all_packages[@]}" | sort -u | tr '\n' ' ')

    log_parallel INFO "Packages detected: $unique_packages"
    log_parallel INFO "Note: Claude instances will install packages as needed — this is advisory only"
}

# ─── Run a single story (spawns Claude) ─────────────────────────
run_story_parallel() {
    local story_id=$1
    local wave_num=$2
    local wave_total=$3
    local output_dir=$4

    local story_json
    story_json=$(get_story_by_id "$story_id")

    if [[ -z "$story_json" || "$story_json" == "null" ]]; then
        echo "ERROR: Story $story_id not found" > "$output_dir/${story_id}.result"
        return 1
    fi

    local story_status
    story_status=$(echo "$story_json" | jq -r '.status')

    # Skip if already Done
    if [[ "$story_status" == "Done" ]]; then
        log_parallel INFO "Story $story_id already Done, skipping"
        echo '{"status":"SKIPPED","story_id":"'"$story_id"'","summary":"Already done"}' > "$output_dir/${story_id}.result"
        return 0
    fi

    # Generate prompt
    local prompt
    prompt=$(generate_parallel_prompt "$story_json" "$wave_num" "$wave_total")

    # Calculate timeout
    local timeout_seconds=$((PARALLEL_TIMEOUT_MINUTES * 60))

    local output_file="$output_dir/${story_id}.log"
    local result_file="$output_dir/${story_id}.result"
    local start_time
    start_time=$(date +%s)

    log_parallel INFO "Spawning Claude for story $story_id..."

    # Build agent system prompt (compact @dev + @qa personas for --print mode)
    local agent_prompt
    agent_prompt=$(cat << 'AGENTEOF'
You are Dex (@dev), Expert Senior Software Engineer. Persona: pragmatic, concise, solution-focused.

## @dev Core Principles
- Story file has ALL info needed. NEVER load PRD/architecture docs unless directed in story notes
- ONLY update story file sections: Task checkboxes, File List, Status
- Follow existing code patterns in squads/ — check before creating new components
- Use TypeScript with proper types, absolute imports, no `any` unless necessary
- Install packages with `cd squads && npm install <pkg> -w apps/web` (or appropriate workspace)

## @dev Development Workflow
1. Read story file completely — understand ACs, tasks, subtasks, Dev Notes
2. Implement each task sequentially, checking off subtasks
3. Follow the coding standards from the tech preset
4. After implementation, run quality checks (typecheck, lint, tests)
5. Update story checkboxes and status

## @qa Quinn — Quality Gate (MANDATORY after implementation)
After implementing, switch to QA mindset as Quinn (@qa), Test Architect & Quality Guardian.

### AC Verification (for EACH acceptance criterion):
- Is it actually implemented end-to-end, not just partially?
- Does it work as described in the story, not just compile?
- Are edge cases and error states handled?
- Would a real user encounter issues with this implementation?

### Code Quality Checklist:
- No hardcoded strings that should be configurable
- No missing error handling on async operations (try/catch, error boundaries)
- No missing loading/empty/error states in UI components
- No unused imports, dead code, or console.logs left behind
- Components have proper TypeScript props interfaces
- No security issues: no dangerouslySetInnerHTML with user input, no exposed API keys/secrets
- Proper data validation on API routes (Zod schemas, input sanitization)

### Quality Standards:
- All code must pass `npx tsc --noEmit` before marking complete
- All code must pass linting before marking complete
- Write tests for testable logic (calculators, utils, hooks)

### Gate Decision (include in your quality_gate JSON):
- PASS: All ACs verified, code quality good, typecheck+lint pass
- CONCERNS: Minor issues noted but functional — document in summary
- FAIL: Critical issues found — fix before marking complete
AGENTEOF
)

    # Spawn Claude Code with @dev + @qa agent personas
    local output exit_code
    output=$(echo "$prompt" | timeout "$timeout_seconds" \
        "$CLAUDE_CODE_CMD" --print --dangerously-skip-permissions \
        --append-system-prompt "$agent_prompt" \
        2>&1) || true
    exit_code=$?

    echo "$output" > "$output_file"

    local end_time elapsed_min
    end_time=$(date +%s)
    elapsed_min=$(( (end_time - start_time) / 60 ))

    # Handle timeout
    if [[ $exit_code -eq 124 ]]; then
        log_parallel WARN "Story $story_id timed out after ${PARALLEL_TIMEOUT_MINUTES}min"
        echo '{"status":"TIMEOUT","story_id":"'"$story_id"'","elapsed_min":'"$elapsed_min"'}' > "$result_file"
        return 2
    fi

    # Extract JSON result from output
    local json_result
    json_result=$(echo "$output" | grep -oP '```json\s*\K\{[^`]*\}' | tail -1 || true)

    if [[ -z "$json_result" ]]; then
        # Try extracting JSON without code fences
        json_result=$(echo "$output" | grep -oP '\{[^{}]*"status"\s*:\s*"[^"]*"[^{}]*\}' | tail -1 || true)
    fi

    if [[ -n "$json_result" ]]; then
        echo "$json_result" > "$result_file"
        local status
        status=$(echo "$json_result" | jq -r '.status' 2>/dev/null || echo "UNKNOWN")
        log_parallel INFO "Story $story_id: status=$status (${elapsed_min}min)"
    else
        log_parallel WARN "Story $story_id: Could not parse JSON result"
        echo '{"status":"UNKNOWN","story_id":"'"$story_id"'","elapsed_min":'"$elapsed_min"',"summary":"No parseable JSON in output"}' > "$result_file"
    fi

    return 0
}

# ─── Execute a single wave ───────────────────────────────────────
execute_wave() {
    local wave_num=$1
    local wave_stories=$2
    local wave_total=${#WAVES[@]}

    log_parallel INFO "═══════════════════════════════════════════════════════"
    log_parallel INFO "Wave $wave_num/$wave_total: stories=[$wave_stories]"
    log_parallel INFO "═══════════════════════════════════════════════════════"

    local output_dir="$PARALLEL_LOG_DIR/wave${wave_num}"
    mkdir -p "$output_dir"

    # Pre-install packages
    if [[ "$SKIP_INSTALL" != "true" ]]; then
        pre_install_packages "$wave_stories"
    fi

    # Parse story IDs
    IFS=',' read -ra story_ids <<< "$wave_stories"
    local num_stories=${#story_ids[@]}

    # Cap concurrency
    local concurrency=$num_stories
    if [[ $concurrency -gt $MAX_PARALLEL ]]; then
        concurrency=$MAX_PARALLEL
        log_parallel WARN "Capping concurrency to $MAX_PARALLEL (requested $num_stories)"
    fi

    log_parallel INFO "Launching $num_stories stories with concurrency=$concurrency"

    # Set stories to InProgress
    for story_id in "${story_ids[@]}"; do
        story_id=$(echo "$story_id" | tr -d '[:space:]')
        local story_json
        story_json=$(get_story_by_id "$story_id")
        if [[ -n "$story_json" && "$story_json" != "null" ]]; then
            local story_path story_status
            story_path=$(echo "$story_json" | jq -r '.path')
            story_status=$(echo "$story_json" | jq -r '.status')
            if [[ "$story_status" == "Ready" ]]; then
                update_story_status "$story_path" "Ready" "InProgress"
            fi
        fi
    done

    # Launch all stories in parallel
    local pids=()
    local pid_to_story=()
    local wave_start
    wave_start=$(date +%s)

    for story_id in "${story_ids[@]}"; do
        story_id=$(echo "$story_id" | tr -d '[:space:]')

        run_story_parallel "$story_id" "$wave_num" "$wave_total" "$output_dir" &
        local pid=$!
        pids+=($pid)
        pid_to_story+=("$pid:$story_id")

        log_parallel INFO "  PID $pid → Story $story_id"

        # Stagger launches slightly to avoid race conditions
        sleep 2
    done

    log_parallel INFO "All $num_stories stories launched. Waiting for completion..."

    # Wait for all processes
    local wave_completed=0
    local wave_failed=0

    for entry in "${pid_to_story[@]}"; do
        local pid="${entry%%:*}"
        local sid="${entry##*:}"

        if wait "$pid" 2>/dev/null; then
            wave_completed=$((wave_completed + 1))
        else
            wave_failed=$((wave_failed + 1))
            log_parallel WARN "Story $sid process exited with error"
        fi
    done

    local wave_end wave_elapsed
    wave_end=$(date +%s)
    wave_elapsed=$(( (wave_end - wave_start) / 60 ))

    # Collect results
    log_parallel INFO "───────────────────────────────────────────────────────"
    log_parallel INFO "Wave $wave_num Results (${wave_elapsed}min total):"

    for story_id in "${story_ids[@]}"; do
        story_id=$(echo "$story_id" | tr -d '[:space:]')
        local result_file="$output_dir/${story_id}.result"

        if [[ -f "$result_file" ]]; then
            local status summary
            status=$(jq -r '.status // "UNKNOWN"' "$result_file" 2>/dev/null || echo "UNKNOWN")
            summary=$(jq -r '.summary // "No summary"' "$result_file" 2>/dev/null || echo "No summary")

            local icon
            case "$status" in
                COMPLETE) icon="✅"; COMPLETED_STORIES=$((COMPLETED_STORIES + 1)) ;;
                SKIPPED)  icon="⏭️"; COMPLETED_STORIES=$((COMPLETED_STORIES + 1)) ;;
                TIMEOUT)  icon="⏱️"; FAILED_STORIES=$((FAILED_STORIES + 1)) ;;
                ERROR)    icon="❌"; FAILED_STORIES=$((FAILED_STORIES + 1)) ;;
                BLOCKED)  icon="🚫"; FAILED_STORIES=$((FAILED_STORIES + 1)) ;;
                *)        icon="❓"; FAILED_STORIES=$((FAILED_STORIES + 1)) ;;
            esac

            log_parallel INFO "  $icon $story_id: $status — $summary"

            # Update story status if complete
            if [[ "$status" == "COMPLETE" ]]; then
                local story_json
                story_json=$(get_story_by_id "$story_id")
                if [[ -n "$story_json" && "$story_json" != "null" ]]; then
                    local story_path
                    story_path=$(echo "$story_json" | jq -r '.path')
                    update_story_status "$story_path" "InProgress" "Done"
                fi
            fi
        else
            log_parallel WARN "  ❓ $story_id: No result file"
            FAILED_STORIES=$((FAILED_STORIES + 1))
        fi
    done

    log_parallel INFO "───────────────────────────────────────────────────────"
    TOTAL_STORIES=$((TOTAL_STORIES + num_stories))

    # Reload cache since statuses changed
    reload_stories_cache

    return 0
}

# ─── Show execution plan (dry run) ──────────────────────────────
show_execution_plan() {
    echo -e "${CYAN}═══════════════════════════════════════════════════════${NC}"
    echo -e "${CYAN}  RALPH+ Parallel Execution Plan${NC}"
    echo -e "${CYAN}═══════════════════════════════════════════════════════${NC}"
    echo ""

    local total=0
    for i in "${!WAVES[@]}"; do
        local wave_num=$((i + 1))
        local wave_stories="${WAVES[$i]}"

        IFS=',' read -ra story_ids <<< "$wave_stories"
        local num=${#story_ids[@]}
        total=$((total + num))

        echo -e "${WHITE}Wave $wave_num${NC} ($num stories in parallel):"

        for story_id in "${story_ids[@]}"; do
            story_id=$(echo "$story_id" | tr -d '[:space:]')
            local story_json
            story_json=$(get_story_by_id "$story_id")

            if [[ -n "$story_json" && "$story_json" != "null" ]]; then
                local title status
                title=$(echo "$story_json" | jq -r '.title')
                status=$(echo "$story_json" | jq -r '.status')
                echo -e "  - $story_id: $title ${CYAN}[$status]${NC}"
            else
                echo -e "  - $story_id: ${RED}NOT FOUND${NC}"
            fi
        done
        echo ""
    done

    echo -e "${WHITE}Total: $total stories across ${#WAVES[@]} waves${NC}"
    echo -e "${WHITE}Timeout per story: ${PARALLEL_TIMEOUT_MINUTES}min${NC}"
    echo -e "${WHITE}Max parallel: ${MAX_PARALLEL}${NC}"
    echo ""
}

# ─── Final summary ──────────────────────────────────────────────
show_final_summary() {
    local total_time=$1

    echo ""
    echo -e "${CYAN}═══════════════════════════════════════════════════════${NC}"
    echo -e "${CYAN}  RALPH+ Parallel Execution Complete${NC}"
    echo -e "${CYAN}═══════════════════════════════════════════════════════${NC}"
    echo -e "  Total stories: $TOTAL_STORIES"
    echo -e "  ${GREEN}Completed: $COMPLETED_STORIES${NC}"
    echo -e "  ${RED}Failed: $FAILED_STORIES${NC}"
    echo -e "  Duration: ${total_time}min"
    echo ""
    echo -e "  ${WHITE}Results in: $PARALLEL_LOG_DIR/${NC}"
    echo ""

    if [[ $FAILED_STORIES -eq 0 ]]; then
        echo -e "  ${GREEN}All stories completed successfully!${NC}"
        echo -e "  ${WHITE}Next step: Activate @devops to commit and push all changes.${NC}"
    else
        echo -e "  ${YELLOW}Some stories failed. Review logs before committing.${NC}"
        echo -e "  ${WHITE}Check: $PARALLEL_LOG_DIR/wave*/\${story_id}.log${NC}"
    fi

    echo ""
    echo -e "${CYAN}═══════════════════════════════════════════════════════${NC}"

    # Write summary file for @devops
    cat > "$PARALLEL_LOG_DIR/summary.json" << SUMEOF
{
  "timestamp": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
  "total_stories": $TOTAL_STORIES,
  "completed": $COMPLETED_STORIES,
  "failed": $FAILED_STORIES,
  "duration_minutes": $total_time,
  "waves": ${#WAVES[@]},
  "ready_for_push": $([ $FAILED_STORIES -eq 0 ] && echo true || echo false)
}
SUMEOF
}

# ─── Main ────────────────────────────────────────────────────────
main() {
    parse_args "$@"

    # Ensure clean environment for spawning Claude
    unset CLAUDECODE 2>/dev/null || true
    unset CLAUDE_CODE_ENTRYPOINT 2>/dev/null || true

    # Setup directories
    mkdir -p "$PARALLEL_LOG_DIR" "$LOG_DIR"

    log_parallel INFO "RALPH+ Parallel Engine started"
    log_parallel INFO "Waves: ${#WAVES[@]}, Max parallel: $MAX_PARALLEL, Timeout: ${PARALLEL_TIMEOUT_MINUTES}min"

    # Detect AIOS
    local mode
    mode=$(detect_aios)
    if [[ "$mode" != "aios" ]]; then
        echo -e "${RED}Error: AIOS not detected. Parallel mode requires AIOS stories.${NC}"
        exit 1
    fi

    # Load stories cache (must be called in main scope, not subshell)
    load_stories_cache

    # Show execution plan
    show_execution_plan

    # Dry run exits here
    if [[ "$DRY_RUN" == "true" ]]; then
        echo -e "${YELLOW}[DRY RUN] No stories will be executed.${NC}"
        exit 0
    fi

    # Execute waves sequentially
    local global_start
    global_start=$(date +%s)

    for i in "${!WAVES[@]}"; do
        local wave_num=$((i + 1))
        local wave_stories="${WAVES[$i]}"

        execute_wave "$wave_num" "$wave_stories"

        # Sleep between waves (except after last)
        if [[ $wave_num -lt ${#WAVES[@]} ]]; then
            log_parallel INFO "Wave $wave_num complete. Sleeping ${WAVE_SLEEP}s before next wave..."
            sleep "$WAVE_SLEEP"
        fi
    done

    local global_end global_elapsed
    global_end=$(date +%s)
    global_elapsed=$(( (global_end - global_start) / 60 ))

    show_final_summary "$global_elapsed"

    log_parallel INFO "RALPH+ Parallel Engine finished: $COMPLETED_STORIES/$TOTAL_STORIES complete in ${global_elapsed}min"

    # Exit with error code if any failed
    [[ $FAILED_STORIES -gt 0 ]] && exit 1
    exit 0
}

main "$@"
