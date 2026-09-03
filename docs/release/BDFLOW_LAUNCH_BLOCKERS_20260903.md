# BDFlow — Matriz de bloqueadores de lançamento

**Data:** 2026-09-03
**Proveniência deste documento:** `R16_RELEASE_DOC_PROVENANCE=AUTHORED_CURRENT_SESSION_FROM_TRUSTED_CP4_AND_PROMPT`

Conclusão técnica de um item **não** é liberação de lançamento. Esta matriz
separa o que está tecnicamente pronto do que depende de terceiros, de decisão
comercial ou de execução externa.

```
GO_LIVE=NOT_READY
```

---

## Matriz

| # | Item | Status | Dono | Evidência | Próxima ação | Bloqueia go-live |
|---|---|---|---|---|---|---|
| 1 | `SITE_R15_FOUNDATION` | PASS | Site | Commit `b11fa87`, relatório R15 no repositório | — | NÃO |
| 2 | `SITE_R15_STAGING_SCHEMA` | PASS | Site | `SITE_R15_STAGING_SQL_COMPATIBILITY=PASS`, `SITE_R15_STAGING_FINAL_SCHEMA_STATE=PASS` | — | NÃO |
| 3 | `SITE_EXACT_PRODUCTION_DEPLOY_PATH` | PENDING | Site / operador | `R16_EXACT_PRODUCTION_DEPLOYMENT_PATH_REHEARSAL=NOT_RUN` — sem PG 17.6 descartável neste ambiente | Executar o ensaio de `R16_PRODUCTION_REHEARSAL_HANDOFF_20260903.md` | **SIM** |
| 4 | `R16_FINAL_LOCAL_RELEASE` | PASS | Site | Gate fresco desta sessão: 30 arquivos / 554 testes, typecheck, build web, build worker, smoke de processo, varreduras | — | NÃO |
| 5 | `R16_COMPLETE_BUNDLE` | PASS | Site | `BDFLOW_SITE_R16_REBUILT_COMPLETE.bundle`, verificado e restaurado independentemente | — | NÃO |
| 6 | `R16_REAL_PROVIDER_SMOKE` | PENDING | Operador de staging | Nenhum envio real executado; provas de TLS usam servidor local com material gerado em runtime | Executar §F–§J de `R16_STAGING_EXECUTION_HANDOFF_20260903.md` | **SIM** |
| 7 | `R16_PROVIDER_IMPLICIT_TLS_COMPATIBILITY` | REQUIRED_BEFORE_SMOKE | Comercial / operador | `R16_SMTP_TLS_MODE=IMPLICIT_TLS_ONLY`; STARTTLS não implementado | Confirmar perfil do provedor (§C do handoff de staging) antes do item 6 | **SIM** |
| 8 | `SITE_APP_REMOTE_E2E` | PENDING_EXTERNAL | Site + App | Nenhum passo executado; ponte permanece `BLOCKED_APP_REPOSITORY` | Executar `R16_SITE_APP_E2E_HANDOFF_20260903.md` | **SIM** |
| 9 | `APP_REAL_DB_EXECUTION` | PENDING_EXTERNAL | App | Sem acesso ao banco do App neste release | Operador autorizado do App | **SIM** |
| 10 | `APP_NEWLLY_SHIPPING_SOURCE` | PENDING_EXTERNAL | App | Código-fonte real do App não inspecionável a partir deste repositório | Disponibilizar fonte para auditoria de contrato | **SIM** |
| 11 | `PIX_PROVIDER_SELECTED` | PENDING | Comercial | Provedor de pagamento é decisão **DEFERIDA** no Handoff Mestre V3 | Selecionar provedor | **SIM** |
| 12 | `PIX_PAYMENT_E2E` | PENDING | Comercial + Site | Depende do item 11 | Após seleção, definir e executar E2E | **SIM** |
| 13 | `PIX_CANCEL_REFUND_E2E` | PENDING | Comercial + Site | Depende do item 11; regra de reconsideração única em 10 dias está fechada, o meio de execução não | Definir e executar | **SIM** |
| 14 | `PRODUCTION_LEGAL_CONTENT` | PENDING | Jurídico | Texto jurídico final é decisão **DEFERIDA**; nenhum texto foi inventado neste release | Jurídico produzir e aprovar | **SIM** |
| 15 | `PRODUCTION_WORKER_HOST` | PENDING | Infra | Host de execução do worker não definido; modos one-shot e polling ambos disponíveis | Escolher host e modo (cron ou serviço longo) | **SIM** |
| 16 | `PRODUCTION_REHEARSAL` | PENDING | Operador | Igual ao item 3 | Executar o ensaio | **SIM** |
| 17 | `PRODUCTION_DEPLOY` | NOT_AUTHORIZED | — | Nenhum deploy autorizado por este release | Depende de 3, 6, 8, 11–16 | **SIM** |
| 18 | `GO_LIVE` | **NOT_READY** | — | Onze itens bloqueantes abertos | Resolver os bloqueadores acima | — |

---

## Limitações técnicas aceitas — não bloqueantes

Registradas explicitamente, não escondidas em nota de rodapé.

| Código | Situação |
|---|---|
| `R16_STARTTLS_SUPPORT=NOT_IMPLEMENTED` | Sem upgrade de socket, re-EHLO ou detecção de capacidade. Configuração recusa o modo. **Cria o gate comercial do item 7.** |
| `R16_SMTP_TLS_MODE=IMPLICIT_TLS_ONLY` | Um modo seguro correto em vez de dois incompletos. |
| `R16_AUTH_MECHANISMS=PLAIN_ONLY` | Único mecanismo implementado e testado. |
| `R16_PERMANENT_FAILURE_FAST_FAIL=DEFERRED_ACCEPTED_NON_BLOCKING` | O contrato `SendResult` do R13 não expõe retentabilidade estruturalmente, e `dispatchPending` reagenda toda falha. Recusa 5xx permanente é reagendada até o teto do banco. |
| `R16_PERMANENT_FAILURE_RETRY_BOUND=DATABASE_MAX_ATTEMPTS` | As retentativas são limitadas: a autoridade sobre o teto é a RPC canônica. |
| `R16_PERMANENT_FAILURE_DIAGNOSTIC_PRESERVED=PASS` | A natureza permanente é preservada na coluna de erro como `smtp_permanente_<código>_<fase>`. |
| `R16_GENERIC_NOTIFICATION_CLAIM=DEFERRED` | Ampliar além dos três templates exige RPC de claim genérica e mudança de schema. |
| `SECRET_SCAN_LANGUAGE_COVERAGE=KNOWN_LIMITATION` | O `secret-scan.sh` rastreado reconhece termos em inglês. Heurística auxiliar em português foi executada no gate final: `PORTUGUESE_SECRET_HEURISTIC_REAL_SECRET_RISK=0`. O scanner **não** é completo em idiomas. |

---

## O que esta matriz não afirma

- Não afirma que o E2E remoto Site↔App passou.
- Não afirma que o Pix está completo.
- Não afirma que houve prova de runtime do App/Newlly.
- Não afirma que o caminho exato de deploy de produção foi validado.
- Não afirma que houve envio real de e-mail por provedor externo.

```
PRODUCTION_DB_WRITES=0   STAGING_DB_WRITES=0   APP_DB_WRITES=0
REAL_CUSTOMER_EMAILS=0   GIT_PUSH=0   GIT_MERGE=0   VERCEL_PRODUCTION_DEPLOY=0
```
