# R16 — Handoff de execução em staging

**Data:** 2026-09-03
**Proveniência deste documento:** `R16_RELEASE_DOC_PROVENANCE=AUTHORED_CURRENT_SESSION_FROM_TRUSTED_CP4_AND_PROMPT`

Este documento descreve passos que um **operador humano autorizado** executa.
Nenhuma ação remota foi realizada na produção deste material:

```
PRODUCTION_DB_WRITES=0   STAGING_DB_WRITES=0   APP_DB_WRITES=0
REAL_CUSTOMER_EMAILS=0   GIT_PUSH=0   GIT_MERGE=0   VERCEL_PRODUCTION_DEPLOY=0
```

---

## A. Identidade do candidato

| Item | Valor |
|---|---|
| Branch | `recon/r16-email-outbox-rebuild` |
| Código aceito (CP4) — HEAD | `8b2f7fa6729f91ab32c1351a6643b673ff27a551` |
| Código aceito (CP4) — TREE | `9e16fa5bbc824e976230b4d47d269eb280b6169e` |
| Correção pós-CP4 (fixture) | `9c85abc08313f22f93a8965e3168c9263481f3d8` |
| Migrations | 27 (nenhuma adicionada; `R16_SCHEMA_CHANGE_REQUIRED=NO`) |
| Bundle final | `BDFLOW_SITE_R16_REBUILT_COMPLETE.bundle` |
| SHA256 do bundle final | Ver `SHA256SUMS.txt` do pacote de transferência — não pode ser embutido aqui sem autorreferência de hash |

**Primeiro passo obrigatório do operador:** restaurar do bundle e conferir
branch, HEAD, TREE, 27 migrations e worktree limpa **antes** de qualquer outra
coisa. Divergência em qualquer um deles: PARE.

---

## B. Variáveis de ambiente — apenas NOMES

Nunca versione valores. Lista completa em `.env.example`.

```
ENVIRONMENT
SUPABASE_URL
SUPABASE_SERVICE_ROLE_KEY
SITE_BASE_URL
SMTP_MODE
SMTP_HOST
SMTP_PORT
SMTP_USERNAME
SMTP_PASSWORD
SMTP_FROM_ADDRESS
SMTP_FROM_NAME
SMTP_CONNECT_TIMEOUT_MS
SMTP_READ_TIMEOUT_MS
WORKER_BATCH_SIZE
WORKER_RECOVERY_RESERVE
WORKER_POLL_INTERVAL_MS
WORKER_ONE_SHOT
STAGING_RECIPIENT_OVERRIDE
STAGING_RECIPIENT_ALLOWLIST
```

Segredo sob prefixo `VITE_` ou `NEXT_PUBLIC_` é **rejeitado na inicialização**.
É a barreira que impede a chave de service_role de alcançar o navegador.

---

## C. Precheck de compatibilidade do provedor SMTP

`R16_PROVIDER_IMPLICIT_TLS_COMPATIBILITY=REQUIRED_BEFORE_SMOKE`

O worker implementa **somente TLS implícito**. Antes de qualquer smoke,
confirme com o provedor:

| Pergunta | Resposta exigida |
|---|---|
| Suporta TLS implícito (cifra desde o primeiro byte)? | SIM |
| Porta para TLS implícito | 465 ou equivalente documentado do provedor |
| Cadeia de certificado válida em CA pública? | SIM |
| Hostname do certificado corresponde ao `SMTP_HOST`? | SIM |
| Se exige autenticação, suporta AUTH PLAIN? | SIM |

Se o provedor **exigir STARTTLS na 587** e não oferecer perfil de TLS
implícito: `PROVIDER_COMPATIBILITY=FAIL`. **PARE antes do smoke.** As saídas
são escolher outro provedor/perfil, ou autorizar separadamente a
implementação de STARTTLS.

**Não enfraqueça o TLS para acomodar provedor.** Não existe caminho de
configuração para isso, e criar um seria regressão de segurança, não ajuste.

---

## D. Segurança de destinatário — obrigatória

Para o **primeiro smoke com provedor real**, `STAGING_RECIPIENT_OVERRIDE` é
obrigatório e deve apontar para caixa controlada pela equipe.

Sem `STAGING_RECIPIENT_OVERRIDE` nem `STAGING_RECIPIENT_ALLOWLIST`, o worker
**não sobe** em `ENVIRONMENT=staging` — é falha de inicialização, não aviso.
As duas juntas também são rejeitadas: ambiguidade não é resolvida por
precedência silenciosa.

**Nenhum destinatário de cliente real.** Sob override, o endereço original
nunca aparece no envelope SMTP nem em log.

---

## E. Prechecks de banco

Contexto conhecido do Site em staging:

```
PROJECT_NAME="Stagging BDFLOW"
PROJECT_REF=jbadlzkjugdtivczxwxk
POSTGRES_VERSION=17.6
```

| # | Verificação | Esperado |
|---|---|---|
| E1 | Versão do PostgreSQL | 17.6 |
| E2 | Histórico de migrations do Site aplicado | consistente com as 27 |
| E3 | Tabela `notification_events` e colunas usadas pelo worker | presentes |
| E4 | `svc_mint_partner_application_token` | presente e executável |
| E5 | `svc_mint_manager_invite_token` | presente e executável |
| E6 | `svc_mark_notification_sent` | presente |
| E7 | `svc_mark_notification_failed` | presente |
| E8 | `svc_reschedule_notification` | presente |
| E9 | Trigger `notification_events_protect` ativo | sim |
| E10 | Nenhuma migration 28 | confirmado |

Falha em E1–E10: **PARE**. O worker não deve subir contra schema divergente.

---

## F. Smoke do primeiro template suportado

Sequência exata, com o worker em modo one-shot:

| Passo | Ação | Resultado esperado | Evidência |
|---|---|---|---|
| F1 | Enfileirar por caminho **oficial** do Site (não INSERT manual) | linha em `pending` | id do evento |
| F2 | `npm run worker:once` | exit 0 | código de saída |
| F3 | Claim atômico | RPC concede posse, status vai a `sending` | log `worker_cycle_start` |
| F4 | Captura no sandbox/provedor | mensagem recebida **exatamente uma vez** | captura do provedor |
| F5 | Estado final | `sent`, com `provider_message_id` preenchido | consulta ao banco |
| F6 | Reexecutar `npm run worker:once` | **nenhuma** duplicata; o evento não é redescoberto | captura vazia |

**STOP** se F4 capturar mais de uma mensagem, ou se F6 produzir segunda
entrega.

---

## G. Recuperação com lease vivo

| Passo | Ação | Resultado esperado |
|---|---|---|
| G1 | Deixar um evento em `sending` com lease **ainda válido** | — |
| G2 | Executar worker one-shot | RPC devolve `lease_held` |
| G3 | Envio | **ZERO**. Contabilizado como `skipped` |

O worker não decide expiração de lease. Ele apenas reapresenta o candidato à
autoridade canônica, que é a RPC.

**STOP** se houver qualquer envio em G3.

---

## H. Recuperação com lease expirado

| Passo | Ação | Resultado esperado |
|---|---|---|
| H1 | Evento em `sending` com lease **expirado** | — |
| H2 | Executar worker one-shot | RPC recupera e concede posse |
| H3 | Envio | **exatamente um**, com um único dono canônico |
| H4 | Estado final | `sent` |

**STOP** se houver mais de um envio, ou dois donos simultâneos.

---

## I. Template não suportado

| Passo | Ação | Resultado esperado |
|---|---|---|
| I1 | Enfileirar evento com `template_key` fora dos três suportados | — |
| I2 | Executar worker one-shot | `unsupported` incrementado |
| I3 | Mutação no banco | **ZERO** — sem claim, sem `sent`, sem `failed`, sem reschedule, sem toque em `attempt_count` |
| I4 | Envio | **ZERO** |

O evento fica inteiramente fora do domínio do worker. `attempt_count`
inalterado é parte do critério: incrementá-lo seria mutação.

**STOP** se qualquer coluna do evento mudar.

---

## J. Auditoria de log

Inspecione toda a saída dos passos F–I. **Não pode aparecer:**

- token cunhado (nem parcial);
- `SUPABASE_SERVICE_ROLE_KEY` ou qualquer valor dele;
- senha SMTP;
- carga AUTH codificada em base64;
- `template_data` cru;
- corpo da mensagem;
- **destinatário original quando o override está ativo**;
- stack trace ou mensagem crua de exceção.

Não existe impressão digital de destinatário:
`R16_RECIPIENT_FINGERPRINT_POLICY=OMITTED_UNLESS_REQUIRED`.

**STOP** ao encontrar qualquer um dos itens acima.

---

## Estado final deste handoff

```
R16_REAL_PROVIDER_SMOKE=PENDING
R16_PROVIDER_IMPLICIT_TLS_COMPATIBILITY=REQUIRED_BEFORE_SMOKE
STAGING_EXECUTION=PENDING_EXTERNAL_OPERATOR
```

Nenhum passo deste documento foi executado. Todos exigem operador autorizado
com acesso ao ambiente de staging.
