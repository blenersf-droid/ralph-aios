#!/bin/bash
# RALPH+ Default Configuration
# All values can be overridden via .ralphrc or environment variables

# ─── Core Loop ───────────────────────────────────────────────
MAX_ITERATIONS=${MAX_ITERATIONS:-20}
SLEEP_BETWEEN_ITERATIONS=${SLEEP_BETWEEN_ITERATIONS:-3}
MAX_RETRIES_PER_STORY=${MAX_RETRIES_PER_STORY:-3}
CLAUDE_TIMEOUT_MINUTES=${CLAUDE_TIMEOUT_MINUTES:-15}
CLAUDE_CODE_CMD=${CLAUDE_CODE_CMD:-claude}

# ─── Rate Limiting ───────────────────────────────────────────
MAX_CALLS_PER_HOUR=${MAX_CALLS_PER_HOUR:-100}
API_LIMIT_SLEEP_MINUTES=${API_LIMIT_SLEEP_MINUTES:-60}

# ─── Circuit Breaker ─────────────────────────────────────────
CB_NO_PROGRESS_THRESHOLD=${CB_NO_PROGRESS_THRESHOLD:-3}
CB_SAME_ERROR_THRESHOLD=${CB_SAME_ERROR_THRESHOLD:-5}
CB_PERMISSION_DENIAL_THRESHOLD=${CB_PERMISSION_DENIAL_THRESHOLD:-2}
CB_COOLDOWN_MINUTES=${CB_COOLDOWN_MINUTES:-30}
CB_AUTO_RESET=${CB_AUTO_RESET:-false}

# ─── AIOS Integration ────────────────────────────────────────
AIOS_ENABLED=${AIOS_ENABLED:-auto}
AIOS_STORY_DIR=${AIOS_STORY_DIR:-docs/stories}
AIOS_DEV_MODE=${AIOS_DEV_MODE:-yolo}
AIOS_QA_ENABLED=${AIOS_QA_ENABLED:-true}
AIOS_PUSH_ENABLED=${AIOS_PUSH_ENABLED:-false}
AIOS_MEMORY_SYNC=${AIOS_MEMORY_SYNC:-true}
AIOS_HANDOFF_DIR=${AIOS_HANDOFF_DIR:-.aios/handoffs}

# ─── Paths ────────────────────────────────────────────────────
RALPH_DIR=${RALPH_DIR:-.ralph-plus}
PROGRESS_FILE=${PROGRESS_FILE:-progress.txt}
PRD_FILE=${PRD_FILE:-prd.json}
LOG_DIR="${RALPH_DIR}/logs"
STATUS_FILE="${RALPH_DIR}/status.json"
LIVE_LOG_FILE="${RALPH_DIR}/live.log"
CB_STATE_FILE="${RALPH_DIR}/.circuit_breaker_state"
CB_HISTORY_FILE="${RALPH_DIR}/.circuit_breaker_history"
CALL_COUNT_FILE="${RALPH_DIR}/.call_count"
TIMESTAMP_FILE="${RALPH_DIR}/.last_reset"

# ─── Backup ──────────────────────────────────────────────────
MAX_BACKUPS=${MAX_BACKUPS:-10}    # Keep only the last N backups

# ─── Exit Detection ──────────────────────────────────────────
EXIT_METHOD=${EXIT_METHOD:-dual}  # dual|structural|semantic
MAX_CONSECUTIVE_NO_WORK=${MAX_CONSECUTIVE_NO_WORK:-3}

# ─── Monitoring ───────────────────────────────────────────────
LIVE_OUTPUT=${LIVE_OUTPUT:-false}
USE_TMUX=${USE_TMUX:-false}
VERBOSE=${VERBOSE:-false}

# ─── Hooks ────────────────────────────────────────────────────
HOOK_PRE_ITERATION=${HOOK_PRE_ITERATION:-}
HOOK_POST_ITERATION=${HOOK_POST_ITERATION:-}
HOOK_ON_ERROR=${HOOK_ON_ERROR:-}
HOOK_ON_COMPLETE=${HOOK_ON_COMPLETE:-}
HOOK_ON_STORY_COMPLETE=${HOOK_ON_STORY_COMPLETE:-}

# ─── Colors ───────────────────────────────────────────────────
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
WHITE='\033[1;37m'
NC='\033[0m'
