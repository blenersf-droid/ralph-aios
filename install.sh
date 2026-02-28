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
            local auth_file=".claude/rules/agent-authority.md"
            local tmp_file="${auth_file}.tmp"

            # Build the @ralph block
            local ralph_block
            ralph_block=$(cat <<'RALPH_BLOCK'
### @ralph (Rex) — Autonomous Execution Control

| Operation | Exclusive? | Details |
|-----------|-----------|---------|
| `*run` / `*stop` / `*pause` / `*resume` | YES | Ralph loop lifecycle |
| `*status` / `*logs` | YES | Loop monitoring |
| `*config` / `*reset` | YES | Loop configuration |
| `ralph-plus/*.sh` execution | YES | Script delegation |

| Allowed | Blocked |
|---------|---------|
| `git status`, `git log`, `git diff` (read-only) | `git push` (delegate to @devops) |
| Read/edit `.ralphrc` | `git commit`, `git add` (spawned agents do this) |
| Read `ralph-plus/logs/`, `progress.txt` | `gh pr create/merge` (delegate to @devops) |
| Launch `ralph.sh`, `ralph-once.sh`, `ralph-status.sh` | Direct story file edits (spawned agents do this) |
| Create/remove signal files (`.stop_signal`, `.pause_signal`) | MCP management |

RALPH_BLOCK
)
            # Insert before @aios-master
            awk -v block="$ralph_block" '/^### @aios-master/{print block}1' "$auth_file" > "$tmp_file" && mv "$tmp_file" "$auth_file"

            # Add autonomous execution flow after Epic Flow section
            if ! grep -q 'Autonomous Execution Flow' "$auth_file" 2>/dev/null; then
                sed -i '/^## Escalation Rules/i\### Autonomous Execution Flow\n```\n@ralph *run → (spawns @dev + @qa per story) → @devops *push (when complete)\n```\n' "$auth_file"
            fi

            echo -e "  ${GREEN}[OK]${NC} Added @ralph to agent-authority.md"
        else
            echo -e "  ${CYAN}[SKIP]${NC} @ralph already in agent-authority.md"
        fi
    fi

    # 6. Add @ralph delegation to aios-master agent
    for master_file in ".aios-core/development/agents/aios-master.md" ".claude/commands/AIOS/agents/aios-master.md"; do
        if [[ -f "$master_file" ]]; then
            if ! grep -q '@ralph' "$master_file" 2>/dev/null; then
                # Add to delegated responsibilities
                sed -i '/AI prompt generation.*@architect/a\- **Autonomous loop execution** → @ralph (\\*run, \\*status, \\*stop)' "$master_file"
                # Add to specialized agents list
                sed -i '/Git operations.*@github-devops/a\- Autonomous execution loop → Use @ralph' "$master_file"
            fi
        fi
    done
    if grep -q '@ralph' ".aios-core/development/agents/aios-master.md" 2>/dev/null; then
        echo -e "  ${GREEN}[OK]${NC} Added @ralph delegation to aios-master"
    fi

    # 7. Add @ralph to workflow-chains.yaml
    if [[ -f ".aios-core/data/workflow-chains.yaml" ]]; then
        if ! grep -q 'autonomous-loop' ".aios-core/data/workflow-chains.yaml" 2>/dev/null; then
            local chains_file=".aios-core/data/workflow-chains.yaml"
            local tmp_file="${chains_file}.tmp"
            local ralph_chain
            ralph_chain=$(cat <<'CHAIN_BLOCK'

  # 2.5. Autonomous Execution Loop — RALPH CONTROL
  - id: autonomous-loop
    name: Autonomous Execution Loop
    description: Continuous autonomous story development controlled by @ralph
    chain:
      - step: 1
        agent: "@ralph"
        command: "*run"
        output: Loop launched (spawns @dev + @qa per story)
        condition: Stories in Ready status, .ralphrc configured
      - step: 2
        agent: "@ralph"
        command: "*status"
        output: Progress dashboard (stories, circuit breaker, rate limit)
        condition: Loop is running
      - step: 3
        agent: "@devops"
        command: "*push"
        task: github-devops-pre-push-quality-gate.md
        output: Code pushed to remote
        condition: All stories complete, loop finished

CHAIN_BLOCK
)
            awk -v block="$ralph_chain" '/# 3\. Spec Pipeline/{print block}1' "$chains_file" > "$tmp_file" && mv "$tmp_file" "$chains_file"
            echo -e "  ${GREEN}[OK]${NC} Added @ralph chain to workflow-chains.yaml"
        else
            echo -e "  ${CYAN}[SKIP]${NC} @ralph already in workflow-chains.yaml"
        fi
    fi

    # 8. Add @ralph to agent-config-requirements.yaml
    if [[ -f ".aios-core/data/agent-config-requirements.yaml" ]]; then
        if ! grep -q '^\  ralph:' ".aios-core/data/agent-config-requirements.yaml" 2>/dev/null; then
            local config_file=".aios-core/data/agent-config-requirements.yaml"
            local tmp_file="${config_file}.tmp"
            local ralph_config
            ralph_config=$(cat <<'CONFIG_BLOCK'

  ralph:
    config_sections:
      - ralphrcLocation
      - dataLocation
    files_loaded:
      - path: .ralphrc
        lazy: false
        size: 2KB
      - path: ralph-plus/progress.txt
        lazy: false
        size: variable
    lazy_loading:
      ralph_logs: true         # Load only on *logs command
    performance_target: <50ms

CONFIG_BLOCK
)
            awk -v block="$ralph_config" '/MEDIUM PRIORITY AGENTS/{print block}1' "$config_file" > "$tmp_file" && mv "$tmp_file" "$config_file"
            echo -e "  ${GREEN}[OK]${NC} Added @ralph to agent-config-requirements.yaml"
        else
            echo -e "  ${CYAN}[SKIP]${NC} @ralph already in agent-config-requirements.yaml"
        fi
    fi

    # 9. Add @ralph to agent team bundles
    for team_file in ".aios-core/development/agent-teams/team-fullstack.yaml" \
                     ".aios-core/development/agent-teams/team-ide-minimal.yaml" \
                     ".aios-core/development/agent-teams/team-no-ui.yaml"; do
        if [[ -f "$team_file" ]]; then
            if ! grep -q 'ralph' "$team_file" 2>/dev/null; then
                sed -i '/^workflows:/i\  - ralph' "$team_file"
            fi
        fi
    done
    if [[ -f ".aios-core/development/agent-teams/team-fullstack.yaml" ]]; then
        if grep -q 'ralph' ".aios-core/development/agent-teams/team-fullstack.yaml" 2>/dev/null; then
            echo -e "  ${GREEN}[OK]${NC} Added @ralph to agent team bundles"
        fi
    fi

    # 10. Add ralph execution mode to story-development-cycle.yaml
    if [[ -f ".aios-core/development/workflows/story-development-cycle.yaml" ]]; then
        if ! grep -q 'mode: ralph' ".aios-core/development/workflows/story-development-cycle.yaml" 2>/dev/null; then
            local sdc_file=".aios-core/development/workflows/story-development-cycle.yaml"
            local tmp_file="${sdc_file}.tmp"
            local ralph_mode
            ralph_mode=$(cat <<'SDC_BLOCK'
    - mode: ralph
      description: >-
        Execução autônoma em loop via @ralph — spawna instâncias fresh do Claude Code
        que executam o SDC completo (create → validate → implement → QA) story por story,
        com circuit breaker, rate limiting e memory cross-iteration.
      prompts: 0
      agent: ralph
      command: "*run"
      notes: |
        Ativação: @ralph *run
        Monitoramento: @ralph *status
        Pausa: @ralph *pause / *resume
        Parada: @ralph *stop
        Configuração: .ralphrc
SDC_BLOCK
)
            awk -v block="$ralph_mode" '/prompts: "10-15"/{print; print block; next}1' "$sdc_file" > "$tmp_file" && mv "$tmp_file" "$sdc_file"
            echo -e "  ${GREEN}[OK]${NC} Added ralph mode to story-development-cycle.yaml"
        else
            echo -e "  ${CYAN}[SKIP]${NC} ralph mode already in story-development-cycle.yaml"
        fi
    fi

    # 11. Add @ralph to workflow-execution.md selection guide
    if [[ -f ".claude/rules/workflow-execution.md" ]]; then
        if ! grep -q '@ralph' ".claude/rules/workflow-execution.md" 2>/dev/null; then
            sed -i '/Simple bug fix.*SDC only/a\| Batch stories autonomously | @ralph *run (SDC in loop, zero interaction) |\n| Monitor autonomous progress | @ralph *status |' ".claude/rules/workflow-execution.md"
            echo -e "  ${GREEN}[OK]${NC} Added @ralph to workflow-execution.md"
        else
            echo -e "  ${CYAN}[SKIP]${NC} @ralph already in workflow-execution.md"
        fi
    fi

    # 12. Add @ralph to agent-memory-imports.md
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
