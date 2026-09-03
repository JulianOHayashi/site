# R16 — Relatório final de release local

**Data:** 2026-09-03
**Proveniência deste documento:** `R16_RELEASE_DOC_PROVENANCE=AUTHORED_CURRENT_SESSION_FROM_TRUSTED_CP4_AND_PROMPT`

Todo veredito `PASS` abaixo vem de execução fresca **desta sessão**, com exit
code capturado antes de qualquer pipe. Nenhum valor foi copiado de relatório
anterior.

---

## 1. Identidade Git

| Item | Valor |
|---|---|
| Branch | `recon/r16-email-outbox-rebuild` |
| `R16_RELEASE_CODE_HEAD` | `8b2f7fa6729f91ab32c1351a6643b673ff27a551` |
| `R16_RELEASE_CODE_TREE` | `9e16fa5bbc824e976230b4d47d269eb280b6169e` |
| Correção pós-CP4 (fixture de varredura) | `9c85abc08313f22f93a8965e3168c9263481f3d8` |
| `R16_RELEASE_DOCUMENTATION_PARENT_HEAD` | `9c85abc08313f22f93a8965e3168c9263481f3d8` |
| Migrations | 27 |
| `R16_SCHEMA_CHANGE_REQUIRED` | NO |

**Sobre autorreferência de hash.** O commit que contém este documento não pode
declarar o próprio SHA — escrevê-lo mudaria o commit. O HEAD final de
documentação e o SHA do bundle final aparecem na saída de verificação do
bundle e em `SHA256SUMS.txt`, fora do commit.

### Cadeia R15 → R16

```
b11fa87  docs: relatório do R15 — correções pré-PG17          (base R15)
4be34db  feat(r16): fail-closed template scope with atomic ownership       CP1
5d464ba  feat(r16): add audited two-phase outbox recovery gateway          CP2
a5fa936  feat(r16): smtp wire safety, worker config, rendering, logging    CP3 parcial
3842819  fix(r16): manager invite route; remove weak fingerprint           CP3 findings-fixed
373dfce  test(r16): continuidade de token pós-login e redação de URL
d5c4e38  feat(r16): fronteira server-only de socket e TLS
1407c33  feat(r16): motor de protocolo SMTP
0c80f02  fix(r16): recusa SMTP_MODE=starttls
464ecc4  test(r16): transporte SMTP/TLS concreto
c7f7142  fix(r16): remove literal de senha em fixture                      CP3 final
ef4cb57  feat(r16): linha final do servidor no resultado de envio
dfe35a6  feat(r16): adaptador SMTP para EmailTransport
6da2468  feat(r16): runtime do worker
2b7ebd3  build(r16): build separado do worker
8b2f7fa  test(r16): smoke de processo e entrega operacional                CP4 final
9c85abc  fix(r16): remove literal com forma de service_role em fixture
```

---

## 2. Artefatos de checkpoint

| Checkpoint | Commit | SHA256 do bundle |
|---|---|---|
| CP1 | `4be34db` | Não disponível neste ambiente — o bundle do CP1 não foi transferido para este container |
| CP2 | `5d464ba` | Não disponível neste ambiente — idem |
| CP3 findings-fixed | `3842819` | `2a674b55da34a05cd8290eba7f30cdf8bbfd9e252a6ad656af0dba69f5ff782e` |
| CP3 final | `c7f7142` | `bb3290f8cf54650883cd0830fcbc73cdae23c8aa5ae58e66180814295188e83f` |
| CP4 final | `8b2f7fa` | `bbc5a31330f08d949a2096b4d06daf089353a52987c4806df355cfc81e41b9c4` |

Os SHA256 de CP1 e CP2 estão marcados como indisponíveis em vez de omitidos ou
inventados: os commits estão presentes na história e verificáveis, mas os
arquivos de bundle correspondentes nunca existiram neste container.

---

## 3. Ambiente da execução

```
NODE=v22.22.2
NPM=10.9.7
GIT=2.43.0
OS=Ubuntu 24.04.4 LTS / kernel 6.18.44-fc-v24 / x86_64
SUPABASE_CLI=AUSENTE  (não requerido: nenhuma mudança de schema)
PSQL=AUSENTE
```

---

## 4. Gate final local — resultados frescos

| Verificação | Exit | Resultado |
|---|---:|---|
| `git diff --check` | 0 | limpo |
| `check-no-legacy` | 0 | `CHECK_LEGADO_LIMPO` |
| Contagem de migrations | — | 27 |
| Regressão de despacho R13 (`m2EmailOutbox`) | 0 | 13 testes |
| R16 claim atômico | 0 | 14 testes |
| R16 recuperação de crash (CP2) | 0 | 30 testes |
| R16 convite de gerente | 0 | 30 testes |
| R16 wire/parser SMTP | 0 | 43 testes |
| R16 SMTP/TLS concreto | 0 | 70 testes |
| R16 render/config/log | 0 | 46 testes |
| R16 runtime do worker + adaptador | 0 | 53 testes |
| **Suíte Vitest completa** | 0 | **30 arquivos, 554 testes** |
| TypeScript `tsc --noEmit` | 0 | PASS |
| Build web | 0 | PASS |
| Build do worker | 0 | `dist-worker/main.mjs`, ESM, target node22 |
| Isolamento do bundle de navegador | 0 | 13 padrões, controles positivo e negativo verdes |
| Auditoria do artefato do worker | 0 | sem superfície de navegador, sem valor de segredo |
| Smoke de processo do worker | 0 | 7 cenários |
| `secret-scan.sh` (rastreado) | 0 | 9 padrões, controles verdes |
| Heurística auxiliar em português | 0 | 3 achados, todos `TEST_FIXTURE` |
| `npm audit --omit=dev` | 0 | 0 vulnerabilidades |

### Testes por arquivo (contagem fresca)

```
aceiteJuridico 8            adminSolicitacoes 9         contaProvisoriaAtivacao 8
jornadaProvisoria 10        loginRedirectSinks 11       m2BenefitDistribution 13
m2ContextoParceiro 22       m2EmailOutbox 13            m2ManualApproval 11
m2OperationalSchedule 23    m2PonteProvisionamento 7    m2PortalValidar 8
m2Precificacao 21           m2ReplacementAndMinimum 20  navegacaoSegura 4
onboardingFase2a 8          onboardingRecuperacao 9     portalGuardFailClosed 9
r16AtomicClaim 14           r16ConfigRenderLog 46       r16CrashRecovery 30
r16ManagerInvite 30         r16NodeSmtpTls 31           r16SmtpEmailTransport 22
r16SmtpTransport 39         r16SmtpWire 43              r16WorkerRuntime 31
substituirRepresentante 8   uploadDocumentoContrato 6
```

### Heurística auxiliar de segredo em português

Padrão focado em atribuição: termo + separador + literal com 12+ caracteres.
Controles positivo e negativo verdes. **Valores não são impressos.**

| Arquivo | Linha | Classificação |
|---|---:|---|
| `src/__tests__/r16ConfigRenderLog.spec.ts` | 20 | `TEST_FIXTURE` |
| `src/__tests__/r16NodeSmtpTls.spec.ts` | 152 | `TEST_FIXTURE` |
| `src/__tests__/r16SmtpTransport.spec.ts` | 29 | `TEST_FIXTURE` |

```
SECRET_SCAN_LANGUAGE_COVERAGE=KNOWN_LIMITATION
PORTUGUESE_SECRET_HEURISTIC_REAL_SECRET_RISK=0
```

O `secret-scan.sh` rastreado **não** é completo em idiomas. A heurística acima
foi executada como auxiliar efêmero em `/tmp`
(`R16_FINAL_AUX_AUDIT_HELPERS=EPHEMERAL_NOT_SHIPPED`).

---

## 5. Vereditos críticos finais

```
R16_SUPPORTED_TEMPLATE_SOURCE_OF_TRUTH=PASS
R16_SUPPORTED_TEMPLATE_KEYS=3
R16_UNSUPPORTED_TEMPLATE_POLICY=FAIL_CLOSED_NOT_PROCESSED
R16_GENERIC_NOTIFICATION_CLAIM=DEFERRED
R16_OUTBOX_ATOMIC_CLAIM=PASS_SUPPORTED_SCOPE
R16_OUTBOX_TWO_WORKER_DUPLICATE_PROTECTION=PASS_SUPPORTED_SCOPE
R16_CRASH_RECOVERY_CONTRACT=PASS
R16_MAX_ATTEMPTS_AUTHORITY=DATABASE_RPC_ONLY
R16_EMAIL_ACTION_ROUTE_AUDIT=PASS
R16_MANAGER_INVITE_ACCEPTANCE_UI=PASS
R16_MANAGER_INVITE_TOKEN_HANDLING=PASS
R16_MANAGER_INVITE_POST_LOGIN_TOKEN_CONTINUITY=PASS
R16_MANAGER_INVITE_URL_REDACTION_ROUTER_PROOF=PASS
R16_SMTP_PROTOCOL_AUDIT=PASS
R16_TLS_AUDIT=PASS
R16_SMTP_DATA_SAFETY=PASS
R16_INJECTION_AUDIT=PASS
R16_URL_ORIGIN_AUDIT=PASS
R16_SECRET_AUDIT=PASS
R16_LOG_REDACTION_AUDIT=PASS
R16_RECIPIENT_FINGERPRINT_POLICY=OMITTED_UNLESS_REQUIRED
R16_STAGING_RECIPIENT_SAFETY=PASS
R16_NODE_RUNTIME_TYPES_AUDIT=PASS
R16_BROWSER_BUNDLE_ISOLATION=PASS
R16_WORKER_RUNTIME_IMPLEMENTED=PASS
R16_WORKER_BUILD=PASS
R16_WORKER_ONE_SHOT=PASS
R16_WORKER_POLLING=PASS
R16_WORKER_SHUTDOWN=PASS
R16_WORKER_EXIT_BEHAVIOR=PASS
R16_WORKER_SMOKE=PASS
R16_STARTTLS_SUPPORT=NOT_IMPLEMENTED
R16_SMTP_TLS_MODE=IMPLICIT_TLS_ONLY
R16_AUTH_MECHANISMS=PLAIN_ONLY
R16_PERMANENT_FAILURE_FAST_FAIL=DEFERRED_ACCEPTED_NON_BLOCKING
R16_PERMANENT_FAILURE_RETRY_BOUND=DATABASE_MAX_ATTEMPTS
R16_PERMANENT_FAILURE_DIAGNOSTIC_PRESERVED=PASS
R16_REAL_PROVIDER_SMOKE=PENDING
R16_PROVIDER_IMPLICIT_TLS_COMPATIBILITY=REQUIRED_BEFORE_SMOKE
TYPECHECK=PASS
WEB_BUILD=PASS
WORKER_BUILD=PASS
SECRET_SCAN=PASS
NPM_AUDIT_OMIT_DEV=PASS
MIGRATIONS_BEFORE=27
MIGRATIONS_AFTER=27
R16_SCHEMA_CHANGE_REQUIRED=NO
WORKTREE=CLEAN
```

---

## 6. Testes nomeados que sustentam os vereditos críticos

- **Posse atômica e duplicata:** `r16AtomicClaim`, `r16CrashRecovery` — dois
  workers não entregam duas vezes; `lease_held` é recusa respeitada.
- **Escopo fail-closed:** `r16ConfigRenderLog` e `r16WorkerRuntime` — template
  fora dos três não é enviado, reivindicado, marcado, reagendado, nem tem
  `attempt_count` tocado.
- **Continuidade de token pós-login:** `r16ManagerInvite` — caminho não
  autenticado completo, com `onAuthStateChange` real emitido; `p_token`
  idêntico byte a byte; RPC exatamente uma vez.
- **Redação de URL pelo roteador:** `r16ManagerInvite` — prova que a rota
  começou com o segredo e que a localização corrente do roteador não o contém;
  parâmetros vizinhos preservados; `replace: true` para não deixar o segredo
  alcançável pelo botão voltar.
- **TLS real:** `r16NodeSmtpTls` — transação SMTP completa sobre handshake
  verificado; certificado não confiável recusado; hostname divergente recusado
  com cadeia confiável; barreiras provadas **ligadas** ao caminho de conexão.
- **Segurança de dados SMTP:** `r16SmtpWire`, `r16SmtpTransport` —
  dot-stuffing, terminador único, injeção de cabeçalho e de envelope,
  backpressure, limpeza determinística.
- **Segurança de destinatário:** `r16SmtpEmailTransport` — fora da allowlist,
  **zero bytes** vão para a rede, nem o EHLO; sob override, o endereço
  original nunca aparece no envelope.
- **Comportamento de processo:** `scripts/audit/worker-smoke.sh` — códigos de
  saída, SIGINT, SIGTERM, one-shot por flag e por ambiente.

---

## 7. Limitações aceitas

```
R16_STARTTLS_SUPPORT=NOT_IMPLEMENTED
R16_AUTH_MECHANISMS=PLAIN_ONLY
R16_PERMANENT_FAILURE_FAST_FAIL=DEFERRED_ACCEPTED_NON_BLOCKING
R16_GENERIC_NOTIFICATION_CLAIM=DEFERRED
R16_REAL_PROVIDER_SMOKE=PENDING
SECRET_SCAN_LANGUAGE_COVERAGE=KNOWN_LIMITATION
```

Detalhamento e consequências operacionais em
`docs/R16_WORKER_OPERACAO.md` §9 e em
`docs/release/BDFLOW_LAUNCH_BLOCKERS_20260903.md`.

---

## 8. Incidente de proveniência

```
R16_PROVENANCE_INCIDENT_UNTRACKED_FILES=CONTAINED
R16_UNTRACKED_PROVENANCE_INCIDENT=CONFIRMED
R16_UNTRACKED_SUSPECT_COUNT=6
R16_UNKNOWN_FILES_ADOPTED=0
R16_UNKNOWN_EXECUTABLES_EXECUTED=0
R16_UNTRACKED_SUSPECT_SEMANTICALLY_READ=0
R16_UNTRACKED_QUARANTINE_CREATED=PASS
R16_UNTRACKED_QUARANTINE_SHA256=09e60ffbe5624200eca11d1d11f95264872f0d8da062c033d17451aeecb6fd5b
R16_FINAL_AUX_AUDIT_HELPERS=EPHEMERAL_NOT_SHIPPED
```

Após o CP4 aceito, seis arquivos não rastreados apareceram na árvore de
trabalho: quatro markdown em `docs/release/` com os nomes exatos exigidos por
este release, e dois shell scripts executáveis em `scripts/audit/`. A
identidade rastreada do CP4 permaneceu inalterada — HEAD, TREE e o diff de
arquivos rastreados intactos.

Contenção aplicada, sem especulação sobre origem:

- nenhum dos seis foi executado;
- nenhum dos seis foi lido semanticamente;
- nenhum dos seis foi adotado ou commitado;
- metadados congelados (caminho, tamanho, modo, mtime, SHA256) antes de
  qualquer movimentação;
- cópia binária preservada como evidência fora da árvore de trabalho, e essa
  evidência **não** entra no repositório nem no bundle final;
- os seis removidos da árvore, com verificação de que nada rastreado mudou;
- os documentos deste release foram escritos do zero a partir do repositório
  em `8b2f7fa`, da instrução de release e de saídas de comando executadas
  agora;
- os auxiliares de auditoria usados no gate final viveram em `/tmp` e não
  foram versionados, para que controles de release não virem superfície
  executável nova no repositório no último instante.

---

## 9. Um achado do próprio gate final

O `secret-scan.sh` reprovou nesta execução, em
`src/__tests__/r16SmtpEmailTransport.spec.ts`, por um literal com forma de
chave de service_role adjacente a `SUPABASE_SERVICE_ROLE_KEY:`. O valor era
fixture inerte, mas o padrão é exatamente o que o controle deve acusar.

**Por que não apareceu no gate do CP4.** O scanner varre arquivos
**versionados** e o diff `BASE..HEAD`. No gate do CP4 esse arquivo ainda
estava por rastrear e as mudanças não estavam commitadas — nenhuma das duas
varreduras o alcançava. O `SECRET_SCAN=PASS` relatado no CP4 era verdadeiro
para a árvore daquele instante e **insuficiente** como garantia sobre o
conteúdo prestes a ser commitado.

Correção aplicada ao procedimento, não só ao arquivo: a varredura de segredos
passa a rodar **depois** do commit. O gate pós-commit desta release é o
veredito válido.

---

## 10. Atividade remota

```
PRODUCTION_DB_WRITES=0
STAGING_DB_WRITES=0
APP_DB_WRITES=0
REAL_CUSTOMER_EMAILS=0
GIT_PUSH=0
GIT_MERGE=0
VERCEL_PRODUCTION_DEPLOY=0
MIGRATION_28=0
SUPABASE_REMOTE_ACTIONS=0
```

---

## 11. Conclusão

O release local do R16 está tecnicamente completo e verificado. **Não está
liberado para lançamento.**

```
R16_FINAL_LOCAL_RELEASE=PASS
GO_LIVE=NOT_READY
```

Onze itens bloqueantes permanecem abertos, listados em
`docs/release/BDFLOW_LAUNCH_BLOCKERS_20260903.md`. Os três mais próximos do
caminho crítico: compatibilidade do provedor com TLS implícito, smoke com
provedor real em staging, e o ensaio do caminho exato de deploy de produção.
