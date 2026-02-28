#!/bin/bash
# RALPH+ Hook System
# Execute user-defined hooks at key lifecycle points

# Run a hook if configured
run_hook() {
    local hook_name=$1
    local hook_path=$2
    shift 2

    if [[ -z "$hook_path" ]]; then
        return 0
    fi

    if [[ ! -f "$hook_path" ]] && [[ ! -x "$hook_path" ]]; then
        [[ "$VERBOSE" == "true" ]] && echo -e "${YELLOW}[HOOK] $hook_name not found: $hook_path${NC}"
        return 0
    fi

    [[ "$VERBOSE" == "true" ]] && echo -e "${CYAN}[HOOK] Running $hook_name...${NC}"

    # Export context for hook
    export RALPH_HOOK_NAME="$hook_name"
    export RALPH_HOOK_ARGS="$*"

    if bash "$hook_path" "$@" 2>/dev/null; then
        [[ "$VERBOSE" == "true" ]] && echo -e "${GREEN}[HOOK] $hook_name completed${NC}"
        return 0
    else
        echo -e "${YELLOW}[HOOK] $hook_name failed (non-blocking)${NC}"
        return 0  # Hooks don't block execution
    fi
}

# Pre-iteration hook
hook_pre_iteration() {
    export RALPH_ITERATION="$1"
    export RALPH_STORY_ID="$2"
    export RALPH_MODE="$3"

    run_hook "pre-iteration" "$HOOK_PRE_ITERATION" "$@"
}

# Post-iteration hook
hook_post_iteration() {
    export RALPH_ITERATION="$1"
    export RALPH_STORY_ID="$2"
    export RALPH_STORY_STATUS="$3"
    export RALPH_MODE="$4"

    run_hook "post-iteration" "$HOOK_POST_ITERATION" "$@"
}

# On error hook
hook_on_error() {
    export RALPH_ITERATION="$1"
    export RALPH_STORY_ID="$2"
    export RALPH_ERROR="$3"

    run_hook "on-error" "$HOOK_ON_ERROR" "$@"
}

# On complete hook (all stories done)
hook_on_complete() {
    export RALPH_ITERATION="$1"
    export RALPH_MODE="$2"

    run_hook "on-complete" "$HOOK_ON_COMPLETE" "$@"
}

# On story complete hook
hook_on_story_complete() {
    export RALPH_STORY_ID="$1"
    export RALPH_ITERATION="$2"

    run_hook "on-story-complete" "$HOOK_ON_STORY_COMPLETE" "$@"
}
