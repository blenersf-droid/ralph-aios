# RALPH+ ↔ Synkra AIOS Integration Guide

## Visão Geral

O RALPH+ funciona em dois modos:

| Modo | Detecção | Stories | Agentes | Memória |
|------|----------|---------|---------|---------|
| **AIOS** | `.aios-core/` existe | `docs/stories/*.story.md` | @dev, @qa, @devops | progress.txt + MEMORY.md |
| **Standalone** | `.aios-core/` não existe | `prd.json` | Claude direto | progress.txt |

## Detecção Automática

```bash
# Na inicialização, RALPH+ verifica:
if [ -d ".aios-core" ] && [ -f ".aios-core/constitution.md" ]; then
    MODE="aios"
else
    MODE="standalone"
fi
```

## Modo AIOS — Fluxo Completo

### 1. Leitura de Stories

RALPH+ escaneia `docs/stories/` para stories com status `Ready` ou `In Progress`:

```bash
# Scan: docs/stories/**/*.story.md
# Parse: Status, AC, Dev Agent Record
# Select: Primeira Ready (ou In Progress se retomando)
```

### 2. Geração do Prompt

O prompt injetado no Claude Code inclui:

```markdown
# Instruções RALPH+ (Modo AIOS)

Você está operando dentro do Synkra AIOS.

1. Ative o agente @dev com: @dev
2. Execute: *develop {STORY_ID} yolo
3. O agente @dev vai:
   - Ler a story em {STORY_PATH}
   - Implementar os Acceptance Criteria
   - Rodar quality checks (lint, typecheck, test)
   - Commitar com mensagem convencional
   - Atualizar Dev Agent Record
4. Depois, ative @qa com: @qa
5. Execute: *review {STORY_ID}
6. Se QA passou, reporte:
   {"status":"COMPLETE","exit_signal":true,"story_id":"{STORY_ID}"}
```

### 3. Handoff entre Agentes

Quando RALPH+ detecta transição de agente (ex: @dev → @qa), ele gera um handoff artifact:

```yaml
handoff:
  from_agent: "dev"
  to_agent: "qa"
  story_context:
    story_id: "{STORY_ID}"
    story_path: "docs/stories/..."
    story_status: "In Review"
    current_task: "QA Review"
  decisions:
    - "Implemented via..."
  files_modified:
    - "src/..."
  next_action: "Run *review {STORY_ID}"
```

### 4. Atualização de Stories

Após cada iteração bem-sucedida:

```bash
# 1. Atualizar checkboxes de AC
sed -i 's/- \[ \] AC N/- [x] AC N/' "$STORY_FILE"

# 2. Atualizar status
sed -i 's/Status: In Progress/Status: Done/' "$STORY_FILE"

# 3. Atualizar Dev Agent Record (File List, Debug Log)
```

### 5. Memória

RALPH+ alimenta duas fontes de memória:

1. **progress.txt** — Learnings gerais por iteração (padrão Ralph)
2. **Agent MEMORY.md** — Padrões confirmados por agente (padrão AIOS)

## Modo Standalone — Fluxo

Quando `.aios-core/` não existe, RALPH+ opera como um Ralph melhorado:

1. Lê `prd.json` com formato padrão Ralph
2. Seleciona story com maior prioridade e `passes: false`
3. Spawna Claude Code com prompt standalone
4. Claude implementa, testa, commita
5. Atualiza `passes: true` no prd.json
6. Verifica se todas as stories estão done

## Mapeamento de Comandos

| Fase | Comando AIOS | Comando Standalone |
|------|-------------|-------------------|
| Implementar | `@dev *develop {id} yolo` | Implementação direta |
| Testar | `npm test && npm run lint` | `npm test && npm run lint` |
| Revisar | `@qa *review {id}` | Verificação automática |
| Commitar | `git commit` (via @dev) | `git commit` (direto) |
| Push | `@devops *push` | `git push` (direto) |

## Respeito às Regras do AIOS

RALPH+ respeita:

1. **Agent Authority** — Não faz `git push` direto; delega a @devops
2. **Constitutional Gates** — Não desenvolve sem story (Article III)
3. **Story-Driven Development** — Toda iteração opera sobre uma story
4. **Quality First** — Não commita código que falhe lint/test/typecheck

## Configuração

No `.ralphrc`, opções específicas para integração AIOS:

```bash
# AIOS Integration
AIOS_ENABLED=auto          # auto|true|false
AIOS_STORY_DIR=docs/stories
AIOS_DEV_MODE=yolo         # yolo|interactive|preflight
AIOS_QA_ENABLED=true       # Run QA gate after dev
AIOS_PUSH_ENABLED=false    # Auto-push via @devops (default: false)
AIOS_MEMORY_SYNC=true      # Sync learnings to MEMORY.md
AIOS_HANDOFF_DIR=.aios/handoffs
```

---

*RALPH+ AIOS Integration v1.0*
