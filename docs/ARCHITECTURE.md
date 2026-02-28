# RALPH+ Architecture Document

## Visão Geral

O RALPH+ é o **motor de execução autônoma** que orquestra os agentes do Synkra AIOS automaticamente. Ele não substitui o AIOS — ele é o loop que faz o AIOS funcionar sem intervenção humana.

```
                    ┌─────────────────────────────┐
                    │        SYNKRA AIOS           │
                    │  (Planejamento + Agentes)    │
                    └──────────┬──────────────────┘
                               │
                    ┌──────────▼──────────────────┐
                    │         RALPH+               │
                    │   (Motor de Loop Autônomo)   │
                    │                              │
                    │  1. Lê stories do AIOS       │
                    │  2. Spawna Claude Code fresh  │
                    │  3. Ativa @dev → implementa  │
                    │  4. Ativa @qa → valida       │
                    │  5. Commit se passou          │
                    │  6. Atualiza story status     │
                    │  7. Registra learnings        │
                    │  8. Repeat até COMPLETE       │
                    └─────────────────────────────┘
```

## Princípios de Design

1. **AIOS-Native, Standalone-Capable** — Integra nativamente com AIOS mas funciona sem ele (prd.json fallback)
2. **Fresh Context per Iteration** — Cada iteração spawna Claude Code com contexto limpo (técnica Ralph)
3. **Fail-Safe by Default** — Circuit breaker, rate limiting, max retries — nunca fica preso
4. **Observable** — tmux monitoring, logs estruturados, status em tempo real
5. **Configurable** — Tudo via `.ralphrc`, env vars ou defaults sensatos
6. **Bash + jq** — Zero dependências pesadas, funciona em qualquer ambiente Unix

## Arquitetura de Componentes

```
ralph-plus/
├── ralph.sh                 # Entry point — main loop
├── ralph-once.sh            # Single iteration (debug/manual)
├── ralph-status.sh          # Status dashboard
├── install.sh               # Installation script
├── .ralphrc.example         # Configuration template
├── CLAUDE.md                # Prompt template (extends AIOS)
│
├── config/
│   ├── defaults.sh          # Default configuration values
│   ├── circuit-breaker.sh   # Circuit breaker state machine
│   └── aios-bridge.sh       # AIOS story reader/writer
│
├── lib/
│   ├── loop.sh              # Core loop logic
│   ├── memory.sh            # progress.txt + AIOS Memory Layer
│   ├── monitor.sh           # tmux dashboard
│   ├── safety.sh            # Rate limiting, validation, guardrails
│   └── hooks.sh             # Hook system (pre/post iteration)
│
├── templates/
│   ├── prd-fullstack-app.md
│   ├── prd-api-service.md
│   ├── prd-chrome-extension.md
│   ├── prd-saas.md
│   └── prd-automation.md
│
├── docs/
│   ├── README.md
│   ├── ARCHITECTURE.md       # This file
│   ├── RESEARCH.md           # Phase 1 research
│   └── AIOS-INTEGRATION.md  # AIOS integration guide
│
└── tests/
    └── ralph.bats            # bats-core tests
```

## Fluxo de Cada Iteração

```
┌─────────────────────────────────────────────────┐
│              RALPH+ Iteration Loop               │
└─────────────────────────────────────────────────┘

1. PRE-ITERATION CHECKS
   ├── Circuit breaker state → can_execute()?
   ├── Rate limit check → under_limit()?
   ├── Validate .ralphrc configuration
   └── Run pre-iteration hooks

2. READ STORIES
   ├── IF AIOS detected:
   │   ├── Scan docs/stories/**/*.story.md
   │   ├── Parse story status, AC, tasks
   │   └── Select next Ready/In Progress story
   └── ELSE (standalone):
       ├── Read prd.json
       └── Select highest priority with passes=false

3. BUILD CONTEXT
   ├── Read progress.txt (Codebase Patterns first)
   ├── Read previous learnings
   ├── Inject current story context
   └── Generate iteration prompt

4. SPAWN CLAUDE CODE
   ├── claude --print --dangerously-skip-permissions
   ├── Pipe generated prompt via stdin
   ├── Capture stdout + stderr
   ├── Timeout: CLAUDE_TIMEOUT_MINUTES (default 15)
   └── Stream to live.log if --live

5. ANALYZE RESPONSE
   ├── Detect output format (JSON vs text)
   ├── Parse completion signals
   ├── Parse exit signals
   ├── Detect test-only loops
   ├── Detect no-work patterns
   ├── Count files modified
   └── Detect errors/permission denials

6. EVALUATE RESULT
   ├── IF story completed:
   │   ├── IF AIOS: Update story checkboxes + status
   │   ├── ELSE: Set passes=true in prd.json
   │   ├── Append to progress.txt with learnings
   │   ├── Update Codebase Patterns if applicable
   │   └── Run post-success hooks
   │
   ├── IF QA failed:
   │   ├── Increment retry counter
   │   ├── IF retries < MAX_RETRIES:
   │   │   ├── Append failure to progress.txt
   │   │   └── Continue (next iteration will retry)
   │   └── ELSE:
   │       ├── Mark story as blocked
   │       └── Move to next story
   │
   └── IF error/no progress:
       ├── Record in circuit breaker
       └── Continue (circuit breaker will halt if needed)

7. CHECK STOP CONDITIONS
   ├── All stories done → EXIT SUCCESS
   ├── Circuit breaker OPEN → EXIT with status
   ├── Max iterations reached → EXIT with summary
   ├── Rate limit exhausted → SLEEP then continue
   └── ELSE → NEXT ITERATION
```

## Circuit Breaker

Baseado no padrão de Michael Nygard, adaptado do frankbria/ralph-claude-code:

```
          ┌──────────┐
          │  CLOSED   │ ← Normal operation
          │ (execute) │
          └─────┬────┘
                │
    no progress │ ≥ 2 loops
                ▼
          ┌──────────┐
          │ HALF_OPEN │ ← Monitoring
          │ (execute) │
          └─────┬────┘
                │
    ┌───────────┼───────────┐
    │           │           │
  progress   no progress  permission
  detected   ≥ threshold   denied
    │           │           │
    ▼           ▼           ▼
  CLOSED      OPEN        OPEN
              (halt)      (halt)
                │
    cooldown   │ ≥ CB_COOLDOWN_MINUTES
    elapsed    │
                ▼
          HALF_OPEN
          (retry)
```

### Thresholds

| Parâmetro | Default | Descrição |
|-----------|---------|-----------|
| `CB_NO_PROGRESS_THRESHOLD` | 3 | Loops sem progresso para abrir |
| `CB_SAME_ERROR_THRESHOLD` | 5 | Loops com mesmo erro para abrir |
| `CB_PERMISSION_DENIAL_THRESHOLD` | 2 | Permission denials para abrir |
| `CB_COOLDOWN_MINUTES` | 30 | Minutos para auto-recovery |
| `CB_AUTO_RESET` | false | Reset on startup |

## AIOS Bridge

O `aios-bridge.sh` é a camada de integração entre RALPH+ e Synkra AIOS:

```
┌─────────────┐          ┌─────────────────┐
│  RALPH+     │          │  SYNKRA AIOS    │
│  Loop       │◄────────►│  Stories/Agents  │
│             │          │                  │
│  read_      │  ─────►  │ docs/stories/    │
│  stories()  │          │ *.story.md       │
│             │          │                  │
│  update_    │  ─────►  │ Story checkboxes │
│  story()    │          │ + status         │
│             │          │                  │
│  get_agent_ │  ─────►  │ Agent commands   │
│  command()  │          │ @dev, @qa        │
│             │          │                  │
│  write_     │  ─────►  │ .aios/handoffs/  │
│  handoff()  │          │                  │
│             │          │                  │
│  update_    │  ─────►  │ progress.txt +   │
│  memory()   │          │ MEMORY.md        │
└─────────────┘          └─────────────────┘
```

### Funções da Bridge

| Função | Descrição |
|--------|-----------|
| `detect_aios()` | Detecta se AIOS está instalado (procura .aios-core/) |
| `read_aios_stories()` | Lê stories do docs/stories/ e retorna JSON |
| `get_next_story()` | Seleciona próxima story Ready/In Progress |
| `update_story_status()` | Atualiza status da story (Ready→In Progress→Done) |
| `update_story_checkboxes()` | Marca checkboxes de AC como [x] |
| `get_agent_command()` | Retorna comando do agente para a fase atual |
| `write_handoff()` | Cria artefato de handoff para troca de agente |
| `read_prd_json()` | Fallback: lê prd.json quando sem AIOS |
| `update_prd_json()` | Fallback: atualiza prd.json |

## Prompt Template (CLAUDE.md)

O prompt gerado para cada iteração contém:

```markdown
# RALPH+ Autonomous Agent Instructions

## Context
- Mode: {AIOS | Standalone}
- Story: {story_id} - {story_title}
- Status: {current_status}
- Iteration: {N} of {MAX}
- Previous Learnings: {from progress.txt}

## Instructions (AIOS Mode)
1. Activate @dev agent
2. Execute: *develop {story_id} yolo
3. Verify implementation against AC
4. Run quality checks (lint, typecheck, test)
5. If quality passes:
   - Commit with: feat: {story_id} - {title}
   - Update story status to "In Review"
6. Activate @qa agent
7. Execute: *review {story_id}
8. If QA passes:
   - Update story status to "Done"
   - Mark all AC checkboxes as [x]
9. Append learnings to progress.txt

## Instructions (Standalone Mode)
1. Read prd.json
2. Pick highest priority story with passes=false
3. Implement the story
4. Run quality checks
5. Commit and set passes=true
6. Append to progress.txt

## Stop Condition
Report status as JSON:
{
  "status": "COMPLETE|IN_PROGRESS|BLOCKED|ERROR",
  "exit_signal": true|false,
  "story_id": "...",
  "files_modified": N,
  "work_type": "implementation|fix|test|review"
}
```

## Rate Limiting

```
Calls/Hour Counter
├── MAX_CALLS_PER_HOUR: 100 (default)
├── Reset: hourly (timestamp-based)
├── 5h API Limit Detection
│   ├── Pattern: "rate_limit_event" in JSON
│   ├── Pattern: "rate limit" in text
│   └── Action: SLEEP 60min then retry
└── Under Limit: continue
    Over Limit: SLEEP until reset
```

## Hook System

```bash
# .ralphrc hooks configuration
HOOK_PRE_ITERATION="./hooks/pre-iteration.sh"
HOOK_POST_ITERATION="./hooks/post-iteration.sh"
HOOK_ON_ERROR="./hooks/on-error.sh"
HOOK_ON_COMPLETE="./hooks/on-complete.sh"
HOOK_ON_STORY_COMPLETE="./hooks/on-story-complete.sh"
```

Hooks recebem variáveis de ambiente:
- `RALPH_ITERATION` — Número da iteração
- `RALPH_STORY_ID` — ID da story atual
- `RALPH_STORY_STATUS` — Status da story
- `RALPH_MODE` — "aios" ou "standalone"

## Decisões de Design

### Por que Bash + jq?

1. **Zero dependências** — Funciona em qualquer Unix
2. **Compatibilidade** — macOS e Linux sem setup
3. **Claude Code CLI** — É um binary chamado via bash
4. **Simplicidade** — Shell scripts são transparentes e debugáveis
5. **Precedente** — Todos os Ralphs usam bash

### Por que Fresh Context per Iteration?

1. **Context window** — Claude tem limite de tokens
2. **Isolation** — Cada iteração começa limpa
3. **Recovery** — Se uma iteração falha, a próxima tenta de novo
4. **Memory** — progress.txt + AIOS Memory Layer preservam learnings

### Por que Dual Exit Gate?

O frankbria demonstrou que single exit (apenas `<promise>COMPLETE</promise>`) é frágil:
- Claude pode emitir prematuramente
- O PR #93 do Ralph original confirma o problema

RALPH+ usa **dual exit gate**:
1. **Structural:** Verificar prd.json/story files — todas stories done?
2. **Semantic:** Claude reporta exit_signal=true + status=COMPLETE?

Ambas condições devem ser verdadeiras para exit.

### Por que AIOS Bridge separada?

1. **Separation of concerns** — Loop é loop, AIOS é AIOS
2. **Testabilidade** — Bridge pode ser testada independentemente
3. **Fallback** — Se AIOS não está instalado, bridge retorna dados do prd.json
4. **Evolução** — AIOS pode mudar formato sem afetar loop

## Compatibilidade

| Plataforma | Status |
|------------|--------|
| macOS | Suportado |
| Linux | Suportado |
| WSL2 | Suportado |
| Windows (Git Bash) | Parcial (sem tmux) |

| Dependência | Versão | Obrigatória |
|-------------|--------|-------------|
| bash | 3.2+ | Sim |
| jq | 1.6+ | Sim |
| git | 2.0+ | Sim |
| claude (CLI) | 2.0+ | Sim |
| tmux | 3.0+ | Não (monitoramento) |
| bats-core | 1.0+ | Não (testes) |

---

*RALPH+ Architecture v1.0 — Aria, arquitetando o futuro*
