# RALPH+ Research Report — Fase 1

## 1. Ralph Original (snarktank/ralph)

**Repo:** https://github.com/snarktank/ralph (9.2k+ stars)

### Arquitetura

O Ralph implementa a técnica de Geoffrey Huntley: um bash loop que spawna instâncias fresh do Claude Code (ou Amp) iterativamente até completar todas as stories de um PRD.

### Componentes

| Arquivo | Função |
|---------|--------|
| `ralph.sh` | Loop principal — suporta `--tool amp\|claude`, max iterations, archivamento de runs anteriores |
| `CLAUDE.md` | Prompt template para Claude Code — instruções para ler prd.json, implementar 1 story, commitar, atualizar progress |
| `prompt.md` | Prompt template para Amp (similar ao CLAUDE.md) |
| `prd.json.example` | Formato de stories: `{project, branchName, userStories: [{id, title, description, acceptanceCriteria, priority, passes, notes}]}` |
| `skills/prd/` | Skill para gerar PRD a partir de requisitos |
| `skills/ralph/` | Skill do loop |
| `flowchart/` | Visualização React do fluxo |

### Fluxo do Loop

```
1. Parse args (--tool, max_iterations)
2. Archive previous run se branch mudou
3. Initialize progress.txt
4. FOR i in 1..MAX_ITERATIONS:
   a. Se amp: pipe prompt.md → amp --dangerously-allow-all
   b. Se claude: pipe CLAUDE.md → claude --dangerously-skip-permissions --print
   c. Capture OUTPUT
   d. Se OUTPUT contém "<promise>COMPLETE</promise>" → EXIT SUCCESS
   e. Sleep 2s
5. Se max iterations → EXIT FAILURE
```

### Formato prd.json

```json
{
  "project": "MyApp",
  "branchName": "ralph/task-priority",
  "description": "Task Priority System",
  "userStories": [
    {
      "id": "US-001",
      "title": "Add priority field to database",
      "description": "...",
      "acceptanceCriteria": ["...", "..."],
      "priority": 1,
      "passes": false,
      "notes": ""
    }
  ]
}
```

### Prompt Template (CLAUDE.md) — Fluxo

1. Ler prd.json
2. Ler progress.txt (Codebase Patterns primeiro)
3. Verificar branch correto
4. Pegar story com maior prioridade onde `passes: false`
5. Implementar UMA story
6. Rodar quality checks (lint, test, typecheck)
7. Atualizar CLAUDE.md com learnings
8. Commit com mensagem padronizada: `feat: [Story ID] - [Story Title]`
9. Setar `passes: true` no prd.json
10. Append progress no progress.txt
11. Se TODAS stories passes=true → `<promise>COMPLETE</promise>`

### Memória entre Iterações

- **progress.txt** — Log append-only com learnings por story
- **Codebase Patterns** — Seção no topo do progress.txt com padrões reusáveis
- **CLAUDE.md** — Atualizado com learnings locais por diretório

### Limitações

- Sem circuit breaker
- Sem rate limiting
- Detecção de completude frágil (`<promise>COMPLETE</promise>` pode ser emitido prematuramente)
- Sem monitoramento em tempo real
- Sem configuração externa (tudo hardcoded)
- Sem recuperação de falhas

---

## 2. Variantes do Ralph

### 2.1 frankbria/ralph-claude-code

**Repo:** https://github.com/frankbria/ralph-claude-code
**Status:** v0.11.5, 566 testes, desenvolvimento ativo

A variante mais completa e robusta do Ralph. Adiciona:

#### Circuit Breaker (lib/circuit_breaker.sh)

Implementação baseada no padrão de Michael Nygard ("Release It!"):

- **3 estados:** CLOSED (normal) → HALF_OPEN (monitorando) → OPEN (halted)
- **Thresholds configuráveis:**
  - `CB_NO_PROGRESS_THRESHOLD=3` — Abre após N loops sem progresso
  - `CB_SAME_ERROR_THRESHOLD=5` — Abre após N loops com mesmo erro
  - `CB_OUTPUT_DECLINE_THRESHOLD=70` — Abre se output declina >70%
  - `CB_PERMISSION_DENIAL_THRESHOLD=2` — Abre após N permission denials
  - `CB_COOLDOWN_MINUTES=30` — Minutos para auto-recovery OPEN → HALF_OPEN
  - `CB_AUTO_RESET=false` — Reset on startup
- **State file:** `.ralph/.circuit_breaker_state` (JSON)
- **History file:** `.ralph/.circuit_breaker_history` (JSON array)
- **Auto-recovery:** Cooldown timer transitions OPEN → HALF_OPEN automaticamente

#### Response Analyzer (lib/response_analyzer.sh)

Análise semântica do output do Claude:

- Detecção de formato (JSON vs text)
- Parse de JSON response com campos estruturados (status, exit_signal, work_type, files_modified)
- Detecção de completion signals (done, complete, finished, all tasks complete)
- Detecção de test-only loops (npm test, pytest, jest)
- Detecção de no-work patterns (nothing to do, no changes, already implemented)
- **Dual-condition exit gate:** Requer TANTO completion indicators QUANTO EXIT_SIGNAL explícito

#### Rate Limiting

- `MAX_CALLS_PER_HOUR=100` — Limite configurável por hora
- Detecção do limite de 5h do Claude API
- Reset automático por hora
- Prompt para usuário quando API limit atingido

#### Session Management

- `--resume <session_id>` — Continuar sessão anterior
- Session expiry configurável (default 24h)
- Session history tracking
- Proteção contra session hijacking

#### Configuração (.ralphrc)

Arquivo de configuração por projeto (sourceable bash):

```bash
MAX_CALLS_PER_HOUR=100
CLAUDE_TIMEOUT_MINUTES=15
CLAUDE_OUTPUT_FORMAT=json
ALLOWED_TOOLS="Write,Read,Edit,Bash(git *),Bash(npm *)"
SESSION_CONTINUITY=true
SESSION_EXPIRY_HOURS=24
CB_NO_PROGRESS_THRESHOLD=3
```

**Precedência:** Environment vars > .ralphrc > defaults

#### Monitoramento (ralph_monitor.sh)

Dashboard tmux em tempo real:
- Status do loop (iteration, calls, status)
- Claude Code progress (indicator, elapsed, last output)
- Recent activity log
- Refresh a cada 2s

#### Estrutura de Pastas (.ralph/)

```
.ralph/
├── PROMPT.md           # Prompt template
├── fix_plan.md         # Fix plan
├── specs/              # Specs
├── logs/               # Structured logs
├── status.json         # Current status
├── progress.json       # Progress tracking
├── live.log            # Live output
├── .circuit_breaker_state
├── .circuit_breaker_history
├── .response_analysis
├── .claude_session_id
├── .ralph_session
└── .ralph_session_history
```

#### Outras Features

- `ralph-enable` — Wizard interativo para setup
- `ralph-enable-ci` — Setup não-interativo para CI
- `ralph-import` — Importar PRD
- `ralph-migrate` — Migrar de versão anterior
- File protection (lib/file_protection.sh)
- Timeout utils (lib/timeout_utils.sh)
- Date utils cross-platform (lib/date_utils.sh)
- 566 testes com bats-core

### 2.2 RobinOppenstam/claude-ralph

**Repo:** https://github.com/RobinOppenstam/claude-ralph

Fork mais simples e direto:

- **ralph.sh** — Loop similar ao original, com logging colorido, dependency check, archive de runs
- **ralph-once.sh** — Execução única (debug/manual) com status antes/depois
- **ralph-status.sh** — Mostra progresso com barra visual, lista stories complete/remaining, próxima story
- **install-skills.sh** — Instalador de skills (prd, ralph, dev-browser)
- **skills/dev-browser/** — Skill para browser testing com verify.ts (Playwright)
- **progress.txt.template** — Template para progress
- Usa `claude -p` com `--dangerously-skip-permissions --verbose`
- Muda working directory para PROJECT_ROOT antes de rodar

### 2.3 syuya2036/ralph-loop

**Repo:** https://github.com/syuya2036/ralph-loop

A variante mais minimalista e agnóstica:

- **ralph.sh** — Loop ultra-simples (~50 linhas)
- Aceita QUALQUER agent command como argumento: `./ralph.sh "claude --dangerously-skip-permissions"`
- Suporta Claude, Codex, Gemini, Qwen, qualquer CLI
- Pipe prompt.md via stdin
- Detecção de `<promise>COMPLETE</promise>`
- Sem dependências extras (apenas bash)

---

## 3. PRs Abertos do Ralph Original

### PR #93 — Improve vibe loop (stop condition)

**Melhoria crítica:** Substitui detecção `<promise>COMPLETE</promise>` por verificação direta do prd.json:

```bash
REMAINING_STORIES="$(jq '.userStories[] | select(.passes == false)' "$PRD_FILE")"
if [[ -z "$REMAINING_STORIES" ]]; then
  echo "Ralph completed all tasks!"
  exit 0
fi
```

**Motivação:** Claude às vezes emite `<promise>COMPLETE</promise>` prematuramente. Verificar o JSON é mais confiável.

### PR #78 — User hints injection + robustness

- **`.ralph-hints.txt`** — Arquivo para injetar hints durante execução (útil para controle via Discord bots)
- Tool validation (jq, amp, claude)
- Consecutive error tracking (para após 3 erros)
- Exit code capture (substitui `|| true`)
- `set -o pipefail`

### PR #45 — Retries + fix hanging

- Retries para todas as tools
- Streaming para Claude Code (fix hanging)
- 26 iterações bem-sucedidas em teste

---

## 4. Repos Complementares

### 4.1 smtg-ai/claude-squad

**Repo:** https://github.com/smtg-ai/claude-squad

App terminal em Go para gerenciar múltiplas instâncias Claude Code simultâneas:

- **Workspaces isolados:** Cada task tem seu workspace git separado
- **Modo auto-accept (yolo):** Aceita prompts automaticamente
- **tmux backend:** Gerencia sessions tmux por instância
- **Multi-agent:** Suporta Claude, Codex, Gemini, Aider
- **Review antes de apply:** Revisão de mudanças antes de aplicar
- **Checkout antes de push:** Checkout de mudanças antes de push
- **Interface TUI:** Lista de instâncias com status em terminal

**Padrões úteis para RALPH+:**
- Isolamento de workspaces via git worktrees
- Gerenciamento de múltiplas instâncias tmux
- Auto-accept mode para operação autônoma

### 4.2 Padrões Chave Identificados

| Padrão | Origem | Aplicabilidade RALPH+ |
|--------|--------|----------------------|
| Circuit Breaker (3 estados) | frankbria | ESSENCIAL — previne loops infinitos |
| Response Analyzer semântico | frankbria | ESSENCIAL — detecta completion, stagnation |
| Dual exit gate | frankbria | ALTO — previne exit prematuro |
| .ralphrc config | frankbria | ALTO — configuração por projeto |
| prd.json verification | PR #93 | ALTO — mais confiável que <promise> |
| User hints injection | PR #78 | MÉDIO — controle externo |
| Workspace isolation | claude-squad | ALTO — parallelismo sem conflitos |
| Session continuity | frankbria | MÉDIO — preserva contexto |
| Streaming output | PR #45 | ALTO — previne hanging |
| tmux monitoring | frankbria | MÉDIO — observabilidade |

---

## 5. Synkra AIOS — Pontos de Integração

### 5.1 Sistema de Agentes

| Agente | Papel no RALPH+ |
|--------|-----------------|
| @sm (River) | Cria stories — RALPH+ lê stories criadas |
| @dev (Dex) | Implementa — RALPH+ ativa @dev via `*develop {story-id} yolo` |
| @qa (Quinn) | Valida — RALPH+ ativa @qa via `*review {story-id}` |
| @devops (Gage) | Push — RALPH+ ativa @devops via `*push` (EXCLUSIVO) |
| @po (Pax) | Valida story draft — RALPH+ chama `*validate-story-draft` |

### 5.2 Formato de Stories AIOS

Stories no formato AIOS usam Markdown com checkboxes:

```markdown
# Story {ID}: {Title}
- Status: {Draft|Ready|In Progress|In Review|Done}
- Epic: {Epic ID}

## Acceptance Criteria
- [ ] AC 1
- [ ] AC 2

## Dev Agent Record
- **Dev Status:** [ ] Task 1 | [ ] Task 2
- **File List:** file1.js, file2.js
```

### 5.3 Task System AIOS

Tasks são workflows executáveis em `.aios-core/development/tasks/*.md`:
- `dev-develop-story.md` — @dev implementa story (3 modos: yolo/interactive/preflight)
- `validate-next-story.md` — @po valida story (10 pontos)
- `qa-gate.md` — @qa valida qualidade (7 checks)
- `execute-epic-plan.md` — Execução de epic em waves

### 5.4 Handoff Protocol

Artefatos de handoff (~379 tokens) para transição entre agentes:
- Armazenados em `.aios/handoffs/`
- Contêm story_context, decisions, files_modified, blockers, next_action
- Sugeridos via `workflow-chains.yaml`

### 5.5 ADE (Autonomous Development Engine)

7 Epics relevantes:
- **Epic 1:** Worktree Manager — isolamento de branches por story
- **Epic 3:** Spec Pipeline — requisitos → specs executáveis
- **Epic 4:** Execution Engine — 13 steps + self-critique
- **Epic 5:** Recovery System — recuperação de falhas
- **Epic 6:** QA Evolution — review em 10 fases
- **Epic 7:** Memory Layer — memória persistente

### 5.6 Session State

Persistência de estado em `.aios/{instance-id}-state.yaml`:
- workflow_id, instance_id, status, current_phase
- Steps array com status individual
- Artifacts, decisions, errors
- Resume: CONTINUE / REVIEW / RESTART / DISCARD

### 5.7 Constitutional Gates

3 gates automáticos que BLOQUEIAM violações:
1. Story existe e não é Draft (Article III)
2. Quality checks passam (Article V)
3. Sem features inventadas (Article IV)

---

*Pesquisa concluída em 2026-02-27. Todos os repositórios analisados em profundidade.*
