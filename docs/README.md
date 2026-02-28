# RALPH+ — Motor de Execução Autônoma para Synkra AIOS

> Um Ralph melhorado que se integra nativamente com o Synkra AIOS, usando seus agentes (@dev, @qa), formato de stories, comandos e fluxo de trabalho ágil.

## O que é o RALPH+?

O RALPH+ é o **motor de loop autônomo** que orquestra os agentes do Synkra AIOS automaticamente. Ele combina a técnica Ralph (spawnar instâncias fresh do Claude Code em loop) com a inteligência do AIOS (agentes especializados, stories, quality gates).

```
┌─────────────────────────────────┐
│         SYNKRA AIOS             │
│   (Planejamento + Agentes)      │
└──────────┬──────────────────────┘
           │
┌──────────▼──────────────────────┐
│          RALPH+                  │
│    (Motor de Loop Autônomo)     │
│                                  │
│  1. Lê stories do AIOS          │
│  2. Spawna Claude Code fresh    │
│  3. Ativa @dev → implementa    │
│  4. Ativa @qa → valida          │
│  5. Commit se passou             │
│  6. Atualiza story status       │
│  7. Registra learnings          │
│  8. Repeat até COMPLETE         │
└──────────────────────────────────┘
```

## Características

- **Dual Mode:** AIOS nativo + standalone (prd.json) como fallback
- **Circuit Breaker:** Previne loops infinitos (3 estados: CLOSED → HALF_OPEN → OPEN)
- **Rate Limiting:** Controle de chamadas por hora com detecção do limite de 5h do Claude
- **Dual Exit Gate:** Verificação estrutural (stories) + semântica (Claude output)
- **Memory System:** progress.txt + AIOS Memory Layer
- **Hook System:** pre/post iteration, on-error, on-complete
- **Configurável:** Tudo via `.ralphrc`, env vars ou defaults
- **Observable:** Logs estruturados, status em tempo real
- **Testado:** Suite bats-core com 40+ testes

## Instalação Rápida

```bash
# 1. Clone ou copie o ralph-plus/ para seu projeto
cp -r ralph-plus/ /path/to/your/project/

# 2. Execute o instalador
cd /path/to/your/project
./ralph-plus/install.sh

# 3. Configure (opcional)
cp .ralphrc.example .ralphrc
# edite .ralphrc conforme necessário
```

## Uso

### Modo AIOS (automático quando `.aios-core/` existe)

```bash
# Verificar status
./ralph-plus/ralph-status.sh

# Rodar loop completo (20 iterações default)
./ralph-plus/ralph.sh

# Com output ao vivo
./ralph-plus/ralph.sh --live

# Com mais iterações
./ralph-plus/ralph.sh 50

# Iteração única (debug)
./ralph-plus/ralph-once.sh
```

### Modo Standalone (prd.json)

```bash
# Criar prd.json a partir de um template
cp ralph-plus/templates/prd-fullstack-app.md .
# ... edite e crie seu prd.json

# Rodar
./ralph-plus/ralph.sh --standalone
```

### Opções

| Flag | Descrição |
|------|-----------|
| `--live` | Mostra output do Claude em tempo real |
| `--reset` | Reset circuit breaker e contadores |
| `--status` | Mostra status atual e sai |
| `--verbose` | Logging detalhado |
| `--standalone` | Força modo standalone (ignora AIOS) |
| `--help` | Mostra ajuda |

## Configuração (.ralphrc)

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
AIOS_DEV_MODE=yolo       # yolo|interactive|preflight
AIOS_QA_ENABLED=true

# Hooks
HOOK_ON_COMPLETE=./hooks/notify.sh
```

Veja `.ralphrc.example` para todas as opções.

## Arquitetura

Veja [ARCHITECTURE.md](ARCHITECTURE.md) para detalhes completos.

### Componentes

| Componente | Arquivo | Função |
|------------|---------|--------|
| Main Loop | `ralph.sh` | Entry point, parse args, orchestrate |
| Single Run | `ralph-once.sh` | Debug: uma iteração |
| Status | `ralph-status.sh` | Dashboard de progresso |
| Defaults | `config/defaults.sh` | Configuração default |
| Circuit Breaker | `config/circuit-breaker.sh` | State machine anti-loop |
| AIOS Bridge | `config/aios-bridge.sh` | Integração com Synkra AIOS |
| Loop Logic | `lib/loop.sh` | Core loop e iteração |
| Safety | `lib/safety.sh` | Rate limit, validação, análise |
| Memory | `lib/memory.sh` | progress.txt + AIOS Memory |
| Hooks | `lib/hooks.sh` | Sistema de hooks |
| Monitor | `lib/monitor.sh` | Logging e display |

## Integração AIOS

Veja [AIOS-INTEGRATION.md](AIOS-INTEGRATION.md) para detalhes.

Quando o RALPH+ detecta `.aios-core/`:
1. Lê stories de `docs/stories/*.story.md`
2. Ativa @dev para implementar via `*develop {story} yolo`
3. Ativa @qa para revisar via `*review {story}`
4. Respeita Agent Authority (@devops para push)
5. Sincroniza learnings com MEMORY.md

## Templates de PRD

| Template | Tipo de Projeto |
|----------|----------------|
| `prd-fullstack-app.md` | Apps web fullstack (React/Next.js) |
| `prd-api-service.md` | APIs e microsserviços |
| `prd-chrome-extension.md` | Extensões Chrome |
| `prd-saas.md` | Plataformas SaaS |
| `prd-automation.md` | Scripts e automações |

## Testes

```bash
# Instalar bats-core
brew install bats-core  # macOS
apt install bats        # Linux

# Rodar testes
bats tests/ralph.bats
```

## Créditos

Baseado em:
- [snarktank/ralph](https://github.com/snarktank/ralph) — Técnica original do loop autônomo
- [frankbria/ralph-claude-code](https://github.com/frankbria/ralph-claude-code) — Circuit breaker, rate limiting, response analysis
- [RobinOppenstam/claude-ralph](https://github.com/RobinOppenstam/claude-ralph) — ralph-once.sh, ralph-status.sh
- [SynkraAI/aios-core](https://github.com/SynkraAI/aios-core) — Synkra AIOS framework

## Requisitos

- bash 3.2+
- jq 1.6+
- git 2.0+
- Claude Code CLI 2.0+
- tmux 3.0+ (opcional, para monitoramento)

## Licença

MIT

---

*RALPH+ v1.0 — Construído com Synkra AIOS*
