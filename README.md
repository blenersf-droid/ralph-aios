# RALPH+ — Autonomous Execution Engine for Claude Code

> A battle-tested loop engine that spawns fresh Claude Code instances to develop software autonomously — with circuit breaker, rate limiting, dual exit gates, and optional AIOS agent orchestration.

## What is RALPH+?

RALPH+ takes the [Ralph technique](https://github.com/snarktank/ralph) (spawning fresh Claude Code instances in a loop) and adds enterprise-grade safety mechanisms. It works in **two modes**:

| Mode | Detection | Stories | How it works |
|------|-----------|---------|-------------|
| **Standalone** | Default | `prd.json` | Claude implements stories directly |
| **AIOS** | `.aios-core/` exists | `docs/stories/*.story.md` | Orchestrates @dev, @qa agents |

```
┌────────────────────────────────────┐
│           RALPH+ Loop              │
│                                    │
│  1. Read next story                │
│  2. Spawn fresh Claude Code        │
│  3. Implement + quality checks     │
│  4. Commit if passed               │
│  5. Update story status            │
│  6. Record learnings               │
│  7. Repeat until COMPLETE          │
└────────────────────────────────────┘
```

## Features

- **Circuit Breaker** — 3-state machine (CLOSED → HALF_OPEN → OPEN) prevents infinite loops
- **Rate Limiting** — Configurable calls/hour with 5h API limit detection
- **Dual Exit Gate** — Structural (all stories done?) + Semantic (Claude confirms?) verification
- **Memory System** — `progress.txt` with codebase patterns carried across iterations
- **Hook System** — pre/post iteration, on-error, on-complete, on-story-complete
- **Backup & Cleanup** — Auto-backup before each iteration, configurable retention
- **Cross-Platform** — macOS, Linux, WSL2 (POSIX-compatible)
- **Configurable** — Everything via `.ralphrc`, env vars, or sensible defaults
- **Tested** — 50+ bats-core tests

## Quick Start

```bash
# 1. Clone into your project
git clone https://github.com/blenersf-droid/ralph-plus.git

# 2. Go to your project and run installer
cd your-project/
/path/to/ralph-plus/install.sh

# 3. Create your PRD (pick a template)
cp /path/to/ralph-plus/templates/prd-fullstack-app.md .
# Edit and convert to prd.json

# 4. Run
/path/to/ralph-plus/ralph.sh
```

Or add as a subdirectory:

```bash
cd your-project/
cp -r /path/to/ralph-plus/ ./ralph-plus/
./ralph-plus/install.sh
./ralph-plus/ralph.sh
```

## Usage

```bash
# Run the full loop (default: 20 iterations)
./ralph-plus/ralph.sh

# With live Claude output
./ralph-plus/ralph.sh --live

# Custom iteration count
./ralph-plus/ralph.sh 50

# Single iteration (debug mode)
./ralph-plus/ralph-once.sh

# Check progress dashboard
./ralph-plus/ralph-status.sh

# Reset circuit breaker
./ralph-plus/ralph.sh --reset

# Force standalone mode (ignore AIOS)
./ralph-plus/ralph.sh --standalone
```

### CLI Options

| Flag | Description |
|------|-------------|
| `--live` | Show Claude Code output in real-time |
| `--reset` | Reset circuit breaker and counters |
| `--status` | Show current status and exit |
| `--verbose, -v` | Enable verbose logging |
| `--standalone` | Force standalone mode |
| `--help, -h` | Show help |

## Configuration (.ralphrc)

Create a `.ralphrc` file in your project root (see `.ralphrc.example`):

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

# Backup
MAX_BACKUPS=10

# Hooks
HOOK_ON_COMPLETE=./hooks/notify.sh
```

**Precedence:** Environment vars > `.ralphrc` > defaults

## prd.json Format

```json
{
  "project": "MyApp",
  "branchName": "ralph/feature-name",
  "description": "Feature description",
  "userStories": [
    {
      "id": "US-001",
      "title": "Add user authentication",
      "description": "Implement login/signup flow",
      "acceptanceCriteria": ["Login form works", "JWT tokens issued"],
      "priority": 1,
      "passes": false,
      "notes": ""
    }
  ]
}
```

## PRD Templates

| Template | Project Type |
|----------|-------------|
| `prd-fullstack-app.md` | React/Next.js web apps |
| `prd-api-service.md` | APIs and microservices |
| `prd-chrome-extension.md` | Chrome extensions |
| `prd-saas.md` | SaaS platforms |
| `prd-automation.md` | Scripts and automations |

## Architecture

```
ralph-plus/
├── ralph.sh                 # Main loop entry point
├── ralph-once.sh            # Single iteration (debug)
├── ralph-status.sh          # Progress dashboard
├── install.sh               # Project installer
├── .ralphrc.example         # Configuration template
├── CLAUDE.md                # Agent instructions per iteration
├── config/
│   ├── defaults.sh          # Default configuration
│   ├── circuit-breaker.sh   # 3-state circuit breaker
│   └── aios-bridge.sh       # AIOS integration layer
├── lib/
│   ├── loop.sh              # Core loop logic
│   ├── safety.sh            # Rate limiting, validation, analysis
│   ├── memory.sh            # Progress tracking & patterns
│   ├── monitor.sh           # Logging & display
│   └── hooks.sh             # Lifecycle hooks
├── templates/               # PRD templates (5 types)
├── docs/                    # Detailed documentation
│   ├── ARCHITECTURE.md
│   ├── RESEARCH.md
│   └── AIOS-INTEGRATION.md
└── tests/
    └── ralph.bats           # bats-core test suite
```

See [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md) for detailed design documentation.

## Circuit Breaker

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
   cooldown │ elapsed
            ▼
         HALF_OPEN
```

## AIOS Integration (Optional)

When RALPH+ detects `.aios-core/` in your project, it automatically switches to AIOS mode:

1. Reads stories from `docs/stories/*.story.md`
2. Activates @dev agent → `*develop {story} yolo`
3. Activates @qa agent → `*review {story}`
4. Generates handoff artifacts between agent transitions
5. Syncs learnings to agent MEMORY.md

See [docs/AIOS-INTEGRATION.md](docs/AIOS-INTEGRATION.md) for details.

## Tests

```bash
# Install bats-core
brew install bats-core  # macOS
apt install bats        # Linux

# Run tests
bats tests/ralph.bats
```

## Requirements

- bash 3.2+
- jq 1.6+
- git 2.0+
- [Claude Code CLI](https://docs.anthropic.com/en/docs/claude-code) 2.0+
- tmux 3.0+ (optional, for monitoring)

## Credits

Built on the shoulders of:
- [snarktank/ralph](https://github.com/snarktank/ralph) — Original autonomous loop technique
- [frankbria/ralph-claude-code](https://github.com/frankbria/ralph-claude-code) — Circuit breaker, rate limiting, response analysis
- [RobinOppenstam/claude-ralph](https://github.com/RobinOppenstam/claude-ralph) — ralph-once.sh, ralph-status.sh

## License

[MIT](LICENSE)
