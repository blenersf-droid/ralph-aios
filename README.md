# Ralph AIOS — The Autonomous Engine for Synkra AIOS

> The Ralph that speaks AIOS. Loops fresh Claude Code instances orchestrating **@dev**, **@qa**, and **@devops** agents through story-driven development — with circuit breaker, dual exit gates, and memory across iterations.

## Why Ralph AIOS?

The [original Ralph](https://github.com/snarktank/ralph) spawns Claude Code in a loop. **Ralph AIOS** takes that concept and makes it AIOS-native — it understands stories, activates specialized agents, respects agent authority, follows quality gates, and feeds learnings back into the AIOS memory layer.

```
┌─────────────────────────────────────┐
│           SYNKRA AIOS               │
│    Stories · Agents · Workflows     │
└──────────────┬──────────────────────┘
               │
┌──────────────▼──────────────────────┐
│          RALPH AIOS                 │
│     Autonomous Execution Engine     │
│                                     │
│  1. Read next story from AIOS       │
│  2. Spawn fresh Claude Code         │
│  3. @dev implements (yolo mode)     │
│  4. @qa validates (quality gate)    │
│  5. Commit if passed                │
│  6. Update story → Done             │
│  7. Record learnings in memory      │
│  8. Next story until COMPLETE       │
└─────────────────────────────────────┘
```

It also works **standalone** with `prd.json` for projects without AIOS.

## Features

- **AIOS-Native** — Reads stories, activates @dev/@qa agents, respects Agent Authority
- **Standalone Fallback** — Works with `prd.json` in any project without AIOS
- **Circuit Breaker** — 3-state FSM (CLOSED → HALF_OPEN → OPEN) prevents infinite loops
- **Rate Limiting** — Configurable calls/hour with 5h API limit detection
- **Dual Exit Gate** — Structural (all stories done?) + Semantic (Claude confirms?)
- **Dual Memory** — `progress.txt` patterns + AIOS agent MEMORY.md sync
- **Hook System** — pre/post iteration, on-error, on-complete, on-story-complete
- **Story-Driven** — Every iteration works on exactly one story with acceptance criteria
- **Backup & Cleanup** — Auto-backup before each iteration, configurable retention
- **Cross-Platform** — macOS, Linux, WSL2 (POSIX-compatible)
- **Tested** — 50+ bats-core tests

## Quick Start

### With Synkra AIOS (recommended)

```bash
# 1. Clone into your AIOS project
cd your-aios-project/
git clone https://github.com/blenersf-droid/ralph-aios.git ralph-plus

# 2. Install
./ralph-plus/install.sh
# → Detects .aios-core/ automatically
# → Mode: AIOS (will use @dev, @qa agents)

# 3. Make sure you have stories ready
# (created via @sm *draft)

# 4. Run
./ralph-plus/ralph.sh
```

### Standalone (without AIOS)

```bash
# 1. Clone
git clone https://github.com/blenersf-droid/ralph-aios.git ralph-plus

# 2. Install
cd your-project/
./ralph-plus/install.sh

# 3. Create prd.json from a template
cp ralph-plus/templates/prd-fullstack-app.md .
# Edit and create your prd.json

# 4. Run
./ralph-plus/ralph.sh --standalone
```

## How It Works

### AIOS Mode (auto-detected when `.aios-core/` exists)

Each iteration:
1. Scans `docs/stories/*.story.md` for **Ready** or **In Progress** stories
2. Spawns a fresh Claude Code instance with story context
3. Activates **@dev** → `*develop {story-id} yolo` (implements + tests + commits)
4. Activates **@qa** → `*review {story-id}` (quality gate)
5. Updates story status → **Done**, marks AC checkboxes ✓
6. Generates handoff artifacts for agent transitions
7. Syncs learnings to `progress.txt` + agent `MEMORY.md`

### Standalone Mode

Each iteration:
1. Reads `prd.json`, picks highest priority story with `passes: false`
2. Claude implements directly, runs quality checks
3. Sets `passes: true`, commits, appends learnings

## Usage

```bash
# Full loop (default: 20 iterations)
./ralph-plus/ralph.sh

# With live Claude output
./ralph-plus/ralph.sh --live

# Custom iteration count
./ralph-plus/ralph.sh 50

# Single iteration (debug)
./ralph-plus/ralph-once.sh

# Progress dashboard
./ralph-plus/ralph-status.sh

# Reset circuit breaker
./ralph-plus/ralph.sh --reset
```

| Flag | Description |
|------|-------------|
| `--live` | Show Claude Code output in real-time |
| `--reset` | Reset circuit breaker and counters |
| `--status` | Show current status and exit |
| `--verbose, -v` | Enable verbose logging |
| `--standalone` | Force standalone mode (ignore AIOS) |
| `--help, -h` | Show help |

## Configuration (.ralphrc)

```bash
# Core
MAX_ITERATIONS=20
CLAUDE_TIMEOUT_MINUTES=15
MAX_RETRIES_PER_STORY=3

# Rate Limiting
MAX_CALLS_PER_HOUR=100

# Circuit Breaker
CB_NO_PROGRESS_THRESHOLD=3
CB_COOLDOWN_MINUTES=30

# AIOS Integration
AIOS_DEV_MODE=yolo          # yolo|interactive|preflight
AIOS_QA_ENABLED=true
AIOS_PUSH_ENABLED=false     # Auto-push via @devops
AIOS_MEMORY_SYNC=true

# Hooks
HOOK_ON_COMPLETE=./hooks/notify.sh
```

See `.ralphrc.example` for all options. **Precedence:** env vars > `.ralphrc` > defaults

## Architecture

```
ralph-aios/
├── ralph.sh                 # Main loop entry point
├── ralph-once.sh            # Single iteration (debug)
├── ralph-status.sh          # Progress dashboard
├── install.sh               # Project installer
├── CLAUDE.md                # Agent instructions per iteration
├── config/
│   ├── defaults.sh          # Default configuration
│   ├── circuit-breaker.sh   # 3-state circuit breaker
│   └── aios-bridge.sh       # AIOS story reader/writer
├── lib/
│   ├── loop.sh              # Core iteration logic
│   ├── safety.sh            # Rate limiting, validation, analysis
│   ├── memory.sh            # progress.txt + AIOS Memory Layer
│   ├── monitor.sh           # Logging & display
│   └── hooks.sh             # Lifecycle hooks
├── templates/               # 5 PRD templates
├── docs/
│   ├── ARCHITECTURE.md      # Design & flow diagrams
│   ├── RESEARCH.md          # Phase 1 research on Ralph variants
│   └── AIOS-INTEGRATION.md  # Dual-mode integration guide
└── tests/
    └── ralph.bats           # 50+ bats-core tests
```

## Circuit Breaker

Based on Michael Nygard's "Release It!" pattern:

```
      ┌──────────┐
      │  CLOSED   │ ← Normal operation
      └─────┬────┘
            │ no progress >= 2
      ┌─────▼────┐
      │ HALF_OPEN │ ← Monitoring
      └─────┬────┘
    ┌───────┼───────┐
 progress  no prog  perm denied
    │       │        │
  CLOSED   OPEN     OPEN
            │
   cooldown │ >= 30min
            ▼
         HALF_OPEN (retry)
```

## AIOS Agent Flow

```
Ralph AIOS Iteration
├── @dev (via *develop {story-id} yolo)
│   ├── Read story acceptance criteria
│   ├── Implement code
│   ├── Run quality checks (lint, typecheck, test)
│   └── Commit with conventional message
├── @qa (via *review {story-id})
│   ├── Validate implementation vs AC
│   ├── Check test coverage
│   └── Verdict: PASS / FAIL
└── @devops (via *push) — EXCLUSIVE authority
```

## PRD Templates

| Template | Project Type |
|----------|-------------|
| `prd-fullstack-app.md` | React/Next.js web apps |
| `prd-api-service.md` | APIs and microservices |
| `prd-chrome-extension.md` | Chrome extensions |
| `prd-saas.md` | SaaS platforms |
| `prd-automation.md` | Scripts and automations |

## Tests

```bash
# Install bats-core
brew install bats-core  # macOS
apt install bats        # Linux

# Run
bats tests/ralph.bats
```

## Requirements

- bash 3.2+
- jq 1.6+
- git 2.0+
- [Claude Code CLI](https://docs.anthropic.com/en/docs/claude-code) 2.0+
- tmux 3.0+ (optional)

## Credits

Built on:
- [snarktank/ralph](https://github.com/snarktank/ralph) — Original autonomous loop technique
- [frankbria/ralph-claude-code](https://github.com/frankbria/ralph-claude-code) — Circuit breaker, rate limiting, response analysis
- [RobinOppenstam/claude-ralph](https://github.com/RobinOppenstam/claude-ralph) — ralph-once.sh, ralph-status.sh
- [Synkra AIOS](https://github.com/SynkraAI/aios-core) — AI-Orchestrated System framework

## License

[MIT](LICENSE)
