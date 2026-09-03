# R16 — Handoff de ensaio de produção

**Data:** 2026-09-03
**Proveniência deste documento:** `R16_RELEASE_DOC_PROVENANCE=AUTHORED_CURRENT_SESSION_FROM_TRUSTED_CP4_AND_PROMPT`

---

## 0. O que este documento NÃO afirma

A prova de migration em staging do R15 **não é** prova do caminho exato de
produção. Confundir as duas é a falha que este documento existe para impedir.

```
SITE_R15_STAGING_SQL_COMPATIBILITY=PASS
SITE_R15_STAGING_FINAL_SCHEMA_STATE=PASS
SITE_EXACT_PRODUCTION_DEPLOY_PATH=PENDING
R16_EXACT_PRODUCTION_DEPLOYMENT_PATH_REHEARSAL=NOT_RUN
```

`NOT_RUN` é literal. Não há runtime PostgreSQL 17.6 descartável neste
ambiente — não há `psql` nem Supabase CLI instalados, e nenhuma ação remota é
autorizada. Marcar PASS aqui seria fabricação.

---

## 1. Escopo do ensaio

O ensaio é executado por **operador autorizado**, contra um alvo descartável
equivalente a produção. Objetivo: provar que a sequência exata de comandos
pretendida para produção funciona, antes de apontá-la para produção.

---

## 2. Sequência do ensaio

| # | Etapa | Critério de sucesso |
|---|---|---|
| 1 | Restaurar do bundle final `BDFLOW_SITE_R16_REBUILT_COMPLETE.bundle` em diretório novo | branch, HEAD, TREE, 27 migrations e worktree limpa conferem |
| 2 | `npm ci` | exit 0, sem resolução divergente do lockfile |
| 3 | Provisionar alvo descartável **PostgreSQL 17.6** | versão confirmada por consulta, não por suposição |
| 4 | Aplicar migrations pelo **comando exato pretendido para produção** | registrar o comando literal; nada de variação "equivalente" |
| 5 | Tratamento consciente da baseline | a baseline não pode ser reaplicada sobre schema já existente |
| 6 | Verificar histórico de migrations | 27 registradas, ordem correta, nenhuma 28 |
| 7 | Sondagens pós-deploy | tabelas, colunas, as três RPCs de mint, mark sent, mark failed, reschedule, trigger de proteção |
| 8 | Partida segura do worker | subir com `WORKER_ONE_SHOT=1` e fila vazia; exit 0 |
| 9 | Captura de evidência redigida | sem valores de segredo, sem string de conexão, sem chave |

---

## 3. Comando exato de deploy

**A ser preenchido pelo operador no ensaio.** Este documento deliberadamente
não inventa o comando: escrever aqui um `supabase db push` plausível que
ninguém executou criaria a aparência de procedimento verificado.

O que o ensaio deve registrar literalmente:

- o comando exato, com todas as flags;
- a versão da ferramenta que o executou;
- a saída completa, redigida;
- o exit code, capturado **antes** de qualquer pipe.

---

## 4. Condições de aborto e rollback

Aborte imediatamente e **não prossiga para produção** se:

- a versão do alvo não for 17.6;
- a baseline tentar reaplicar sobre schema existente;
- o histórico de migrations divergir das 27;
- qualquer sondagem do passo 7 falhar;
- surgir necessidade de migration 28;
- o worker não subir com fila vazia;
- qualquer evidência contiver segredo.

Rollback: o alvo é descartável — destrua e recomece. Nenhum rollback é
definido contra produção porque **nenhum deploy de produção é autorizado por
este release**.

---

## 5. Restrições permanentes

```
Nenhuma ação remota no Supabase.  Nenhuma escrita em banco de staging.
Nenhuma escrita em produção.      Nenhuma escrita no banco do App.
Nenhum e-mail a cliente real.     Nenhum deploy de produção na Vercel.
Nenhum git push.  Nenhum merge.   Nenhuma migration 28.
```

---

## 6. Estado final

```
R16_EXACT_PRODUCTION_DEPLOYMENT_PATH_REHEARSAL=NOT_RUN
SITE_EXACT_PRODUCTION_DEPLOY_PATH=PENDING
PRODUCTION_REHEARSAL=PENDING_EXTERNAL_OPERATOR
```

Enquanto o ensaio não for executado e aprovado, o caminho de deploy de
produção permanece **não provado**.
