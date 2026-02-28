#!/bin/bash
# RALPH+ Installer
# Detects AIOS automatically and sets up RALPH+ in a project

set -eo pipefail

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
WHITE='\033[1;37m'
NC='\033[0m'

RALPH_PLUS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo ""
echo -e "${WHITE}=================================================================${NC}"
echo -e "${WHITE}     RALPH+ Installer${NC}"
echo -e "${WHITE}=================================================================${NC}"
echo ""

# Check dependencies
echo -e "${CYAN}Checking dependencies...${NC}"

missing=0
for cmd in bash jq git; do
    if command -v "$cmd" &>/dev/null; then
        echo -e "  ${GREEN}[OK]${NC} $cmd"
    else
        echo -e "  ${RED}[MISSING]${NC} $cmd"
        missing=1
    fi
done

if command -v claude &>/dev/null; then
    echo -e "  ${GREEN}[OK]${NC} claude (Claude Code CLI)"
else
    echo -e "  ${YELLOW}[WARN]${NC} claude (Claude Code CLI) — install with: npm install -g @anthropic-ai/claude-code"
fi

if command -v tmux &>/dev/null; then
    echo -e "  ${GREEN}[OK]${NC} tmux (optional, for monitoring)"
else
    echo -e "  ${CYAN}[INFO]${NC} tmux not found (optional)"
fi

if [[ $missing -eq 1 ]]; then
    echo ""
    echo -e "${RED}Missing required dependencies. Install them and try again.${NC}"
    exit 1
fi

echo ""

# Detect AIOS
echo -e "${CYAN}Detecting Synkra AIOS...${NC}"

if [[ -d ".aios-core" ]] && [[ -f ".aios-core/constitution.md" ]]; then
    echo -e "  ${GREEN}[FOUND]${NC} Synkra AIOS detected"
    echo -e "  Mode: ${WHITE}AIOS${NC} (will use @dev, @qa agents)"

    # Check for stories
    story_count=0
    if [[ -d "docs/stories" ]]; then
        story_count=$(find docs/stories -name "*.story.md" 2>/dev/null | wc -l | tr -d ' ')
    fi
    echo -e "  Stories found: ${WHITE}$story_count${NC}"

    AIOS_DETECTED=true
else
    AIOS_DETECTED=false
    echo -e "  ${YELLOW}[NOT FOUND]${NC} AIOS not detected"
    echo -e "  Mode: ${WHITE}Standalone${NC} (will use prd.json)"

    # Check for prd.json
    if [[ -f "prd.json" ]]; then
        story_count=$(jq '.userStories | length' prd.json 2>/dev/null || echo 0)
        echo -e "  prd.json found: ${WHITE}$story_count stories${NC}"
    else
        echo -e "  ${YELLOW}[WARN]${NC} No prd.json found — create one to get started"
    fi
fi

echo ""

# Create .ralphrc if not exists
if [[ ! -f ".ralphrc" ]]; then
    echo -e "${CYAN}Creating .ralphrc...${NC}"
    cp "$RALPH_PLUS_DIR/.ralphrc.example" ".ralphrc"
    echo -e "  ${GREEN}[OK]${NC} .ralphrc created (edit to customize)"
else
    echo -e "  ${CYAN}[SKIP]${NC} .ralphrc already exists"
fi

# Create .ralph-plus directory
mkdir -p ".ralph-plus/logs"
echo -e "  ${GREEN}[OK]${NC} .ralph-plus/ directory created"

# Make scripts executable
chmod +x "$RALPH_PLUS_DIR/ralph.sh" 2>/dev/null || true
chmod +x "$RALPH_PLUS_DIR/ralph-once.sh" 2>/dev/null || true
chmod +x "$RALPH_PLUS_DIR/ralph-status.sh" 2>/dev/null || true
echo -e "  ${GREEN}[OK]${NC} Scripts made executable"

# Add to .gitignore
if [[ -f ".gitignore" ]]; then
    if ! grep -q ".ralph-plus/" ".gitignore" 2>/dev/null; then
        echo "" >> ".gitignore"
        echo "# RALPH+ runtime files" >> ".gitignore"
        echo ".ralph-plus/" >> ".gitignore"
        echo -e "  ${GREEN}[OK]${NC} Added .ralph-plus/ to .gitignore"
    fi
fi

# Install @ralph agent (AIOS only)
if [[ "$AIOS_DETECTED" == "true" ]]; then
    echo -e "${CYAN}Installing @ralph agent...${NC}"

    AGENT_SRC="$RALPH_PLUS_DIR/agent"

    # 1. Copy agent definition to .aios-core/development/agents/
    if [[ -f "$AGENT_SRC/ralph.md" ]]; then
        cp "$AGENT_SRC/ralph.md" ".aios-core/development/agents/ralph.md"
        echo -e "  ${GREEN}[OK]${NC} Agent definition → .aios-core/development/agents/ralph.md"
    fi

    # 2. Copy agent definition to .claude/commands/AIOS/agents/
    if [[ -d ".claude/commands/AIOS/agents" ]] && [[ -f "$AGENT_SRC/ralph.md" ]]; then
        cp "$AGENT_SRC/ralph.md" ".claude/commands/AIOS/agents/ralph.md"
        echo -e "  ${GREEN}[OK]${NC} Agent skill → .claude/commands/AIOS/agents/ralph.md"
    fi

    # 3. Create MEMORY.md
    if [[ -f "$AGENT_SRC/MEMORY.md" ]]; then
        mkdir -p ".aios-core/development/agents/ralph"
        if [[ ! -f ".aios-core/development/agents/ralph/MEMORY.md" ]]; then
            cp "$AGENT_SRC/MEMORY.md" ".aios-core/development/agents/ralph/MEMORY.md"
            echo -e "  ${GREEN}[OK]${NC} Agent memory → .aios-core/development/agents/ralph/MEMORY.md"
        else
            echo -e "  ${CYAN}[SKIP]${NC} MEMORY.md already exists"
        fi
    fi

    # 4. Add @ralph to CLAUDE.md agent table
    if [[ -f ".claude/CLAUDE.md" ]]; then
        if ! grep -q '@ralph' ".claude/CLAUDE.md" 2>/dev/null; then
            # Insert @ralph row after @devops in the agent table
            sed -i 's/| `@devops` | Gage | CI\/CD, git push (EXCLUSIVO) |/| `@devops` | Gage | CI\/CD, git push (EXCLUSIVO) |\n| `@ralph` | Rex | Autonomous execution loop control |/' ".claude/CLAUDE.md"
            # Add @ralph to activation syntax list
            sed -i 's/@sm, @analyst$/@sm, @analyst, @ralph/' ".claude/CLAUDE.md"
            echo -e "  ${GREEN}[OK]${NC} Added @ralph to CLAUDE.md"
        else
            echo -e "  ${CYAN}[SKIP]${NC} @ralph already in CLAUDE.md"
        fi
    fi

    # 5. Add @ralph delegation to agent-authority.md
    if [[ -f ".claude/rules/agent-authority.md" ]]; then
        if ! grep -q '@ralph' ".claude/rules/agent-authority.md" 2>/dev/null; then
            # Insert @ralph section before @aios-master
            sed -i '/### @aios-master/i\### @ralph (Rex) — Autonomous Execution Control\n\n| Operation | Exclusive? | Details |\n|-----------|-----------|----------|\n| `*run` / `*stop` / `*pause` / `*resume` | YES | Ralph loop lifecycle |\n| `*status` / `*logs` | YES | Loop monitoring |\n| `*config` / `*reset` | YES | Loop configuration |\n| `ralph-plus/*.sh` execution | YES | Script delegation |\n\n| Allowed | Blocked |\n|---------|----------|\n| `git status`, `git log`, `git diff` (read-only) | `git push` (delegate to @devops) |\n| Read/edit `.ralphrc` | `git commit`, `git add` (spawned agents do this) |\n| Read `ralph-plus/logs/`, `progress.txt` | `gh pr create/merge` (delegate to @devops) |\n| Launch `ralph.sh`, `ralph-once.sh`, `ralph-status.sh` | Direct story file edits (spawned agents do this) |\n| Create/remove signal files (`.stop_signal`, `.pause_signal`) | MCP management |\n' ".claude/rules/agent-authority.md"

            # Add autonomous execution flow
            if ! grep -q 'Autonomous Execution Flow' ".claude/rules/agent-authority.md" 2>/dev/null; then
                sed -i '/### Epic Flow/{n;n;n;a\\n### Autonomous Execution Flow\n```\n@ralph *run → (spawns @dev + @qa per story) → @devops *push (when complete)\n```\n}' ".claude/rules/agent-authority.md"
            fi

            echo -e "  ${GREEN}[OK]${NC} Added @ralph to agent-authority.md"
        else
            echo -e "  ${CYAN}[SKIP]${NC} @ralph already in agent-authority.md"
        fi
    fi

    # 6. Add @ralph to agent-memory-imports.md
    if [[ -f ".claude/rules/agent-memory-imports.md" ]]; then
        if ! grep -q 'ralph/MEMORY.md' ".claude/rules/agent-memory-imports.md" 2>/dev/null; then
            echo '@import .aios-core/development/agents/ralph/MEMORY.md' >> ".claude/rules/agent-memory-imports.md"
            echo -e "  ${GREEN}[OK]${NC} Added @ralph to agent-memory-imports.md"
        else
            echo -e "  ${CYAN}[SKIP]${NC} @ralph already in agent-memory-imports.md"
        fi
    fi

    echo ""
fi

echo -e "${GREEN}=================================================================${NC}"
echo -e "${GREEN}  RALPH+ installed successfully!${NC}"
echo -e "${GREEN}=================================================================${NC}"
echo ""
echo "  Next steps:"
echo "    1. Edit .ralphrc to customize settings"
echo "    2. Run: ${WHITE}$RALPH_PLUS_DIR/ralph-status.sh${NC}  (check status)"
if [[ "$AIOS_DETECTED" == "true" ]]; then
echo "    3. Use: ${WHITE}@ralph${NC}                          (agent mode)"
echo "    4. Or:  ${WHITE}$RALPH_PLUS_DIR/ralph.sh${NC}         (direct CLI)"
else
echo "    3. Run: ${WHITE}$RALPH_PLUS_DIR/ralph.sh${NC}         (start loop)"
fi
echo ""
