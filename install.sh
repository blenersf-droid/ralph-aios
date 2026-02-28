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
    story_count=$(find docs/stories -name "*.story.md" 2>/dev/null | wc -l | tr -d ' ')
    echo -e "  Stories found: ${WHITE}$story_count${NC}"
else
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

echo ""
echo -e "${GREEN}=================================================================${NC}"
echo -e "${GREEN}  RALPH+ installed successfully!${NC}"
echo -e "${GREEN}=================================================================${NC}"
echo ""
echo "  Next steps:"
echo "    1. Edit .ralphrc to customize settings"
echo "    2. Run: ${WHITE}$RALPH_PLUS_DIR/ralph-status.sh${NC}  (check status)"
echo "    3. Run: ${WHITE}$RALPH_PLUS_DIR/ralph.sh${NC}         (start loop)"
echo ""
