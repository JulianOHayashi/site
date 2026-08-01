# BDFlow Site — Fase 2A · Marco 1 · Verificação posterior V14 (somente leitura)

**Base autoritativa:** commit `cba451e`. **Versão:** V14. **Natureza:** estritamente somente leitura.

A V14 substitui o normalizador lexical de constraints da V13 por **comparação exata integral** (byte a byte) das 45 renderizações reais do catálogo, exportadas do banco (PostgreSQL 17.6) via `pg_catalog.pg_get_constraintdef(oid, false)`, com MD5 exato. Preserva integralmente a correção de hash exato das 13 funções (V13) e todas as demais checagens. Não cria Foundation nem migration; Foundation V11, Hardening V2 e os pacotes V12/V13 permanecem inalterados.

## Arquivos

- `docs/fase2a-marco1-verificacao-pos-v14.md`
- `supabase/fase2a-marco1-verificacao-pos-v14.sql` (veredito por `raise notice`)
- `supabase/fase2a-marco1-verificacao-pos-v14-veredito-visivel.sql` (veredito por exceção `P0001`)

## Comparação exata das constraints (abordagem A)

Para cada uma das 45 constraints, o gabarito embute `table_name`, `constraint_name`, `expected_contype`, a `catalog_definition_pretty_false` integral e o `md5_exact_definition`. A definição real é obtida de `pg_catalog.pg_get_constraintdef(oid, false)`, normalizada **apenas** em CRLF/LF, e a aprovação exige: (1) tabela existe; (2) constraint existe; (3) `contype` real == esperado; (4) definição integral **exatamente** igual ao gabarito; (5) MD5 da definição integral **exatamente** igual ao hash exportado. Nenhuma transformação canonicalizante (`lower`/`translate`/`regexp_replace`), remoção de whitespace, casts, parênteses ou reordenação. Qualquer divergência → `CONSTRAINT_DEFINICAO_EXATA_DIVERGENTE` (o DETAIL mostra tabela, constraint, tipo real/esperado, definição real, definição esperada, MD5 real e MD5 esperado).

**Inventário:** exatamente 45 constraints (44 `c` + 1 `u`); nenhum gabarito duplicado; nenhuma constraint extra nas quatro tabelas. A única UNIQUE esperada é `public.legal_documents.legal_documents_type_version_unique = UNIQUE (doc_type, version)` (não convertida em índice/CHECK).

### Os 45 MD5 esperados

| Tabela | Constraint | Tipo | MD5 exato |
|---|---|---|---|
| `audit_logs` | `audit_logs_action_nonempty` | `c` | `ffdcda57591f92e19512236d8dcc288e` |
| `audit_logs` | `audit_logs_entity_type_nonempty` | `c` | `eb7e0447ad940bffc68eadd0fbe8ec7f` |
| `audit_logs` | `audit_logs_metadata_objeto` | `c` | `fa278f88e142c2799f6ee09e4b429646` |
| `audit_logs` | `audit_logs_nao_corrige_a_si` | `c` | `190a091aeed0190eef54656057ce6bfe` |
| `legal_acceptances` | `legal_acceptances_context_allowed` | `c` | `f4fd70de899fe80bc9bf8cd9ecb3afa8` |
| `legal_acceptances` | `legal_acceptances_evidence_limite` | `c` | `25cfa595a51a78ee1a9924b73ecb6075` |
| `legal_acceptances` | `legal_acceptances_evidence_objeto` | `c` | `d1135ccf63d7ebc522890622b8d27ff6` |
| `legal_acceptances` | `legal_acceptances_link_coerente` | `c` | `7e5e6c670958cdd70e621a4f82bd2b35` |
| `legal_acceptances` | `legal_acceptances_revocacao_coerente` | `c` | `c4679571b0565669d8e2d7b17c6ae7e3` |
| `legal_acceptances` | `legal_acceptances_subject_allowed` | `c` | `576f3ac65f092c9dee303286c168a8d6` |
| `legal_acceptances` | `legal_acceptances_subject_coerente` | `c` | `62bcd9cf5b081ae6518d53a4bcdeddb1` |
| `legal_documents` | `legal_documents_archived_complete` | `c` | `776822306b1d84d60962bae615dbbecd` |
| `legal_documents` | `legal_documents_published_complete` | `c` | `261fe71528fb07a301de9078ba6748ca` |
| `legal_documents` | `legal_documents_status_allowed` | `c` | `10cff5c766ac5bea792bbc573a098ca6` |
| `legal_documents` | `legal_documents_title_nonempty` | `c` | `1950f394886189039cc457b420d8e511` |
| `legal_documents` | `legal_documents_type_allowed` | `c` | `cf7069313902d2ca952b42e1e0ca99bb` |
| `legal_documents` | `legal_documents_type_version_unique` | `u` | `88bc98285af92159e1afdf82bc867f74` |
| `legal_documents` | `legal_documents_version_nonempty` | `c` | `dc2404768d98d284b29a44e92fc4db11` |
| `legal_documents` | `legal_documents_vigencia_coerente` | `c` | `58246d384b7768ace627785f8282a5e3` |
| `notification_events` | `notification_events_attempt_nao_neg` | `c` | `d20cf8ce7b1715b5e0b7c272d3c0afc4` |
| `notification_events` | `notification_events_channel_allowed` | `c` | `0adc6c7f3135dc73fc24bd35f221e8e1` |
| `notification_events` | `notification_events_data_limite` | `c` | `d6c34196f5f4c89d47ac247768bb7293` |
| `notification_events` | `notification_events_data_objeto` | `c` | `67481cc7de7e2e9f28d392af29f73794` |
| `notification_events` | `notification_events_delivered_estado` | `c` | `9dca9cbcf9722e456fd8f8604b6ce065` |
| `notification_events` | `notification_events_destinatario` | `c` | `56838d1949e2e548749d0440d99e4bee` |
| `notification_events` | `notification_events_endereco_no_envio` | `c` | `56d2b57ff18c0aff6a3c08e11c21bc60` |
| `notification_events` | `notification_events_erro_tamanho` | `c` | `308f2887f25eaedd4e4af7da9d329357` |
| `notification_events` | `notification_events_falha_par` | `c` | `1a08b9234746367f5e11c473f33a41e2` |
| `notification_events` | `notification_events_idem_nonempty` | `c` | `25fc3a3e3b5ffc4089a1efc98f98bf5d` |
| `notification_events` | `notification_events_provider_estado` | `c` | `1f6bdb0c1330a8ff4d23c1290fe5793d` |
| `notification_events` | `notification_events_read_estado` | `c` | `d3e5db8b8aff9028d735241b04898060` |
| `notification_events` | `notification_events_retry_nao_self` | `c` | `6c59dec4d927de19c526877fa02c6f02` |
| `notification_events` | `notification_events_sent_estado` | `c` | `02940ea1e95b9de376113affe7be24dd` |
| `notification_events` | `notification_events_st_delivered` | `c` | `ae94ffd67a83ad0c24d580130dd35a50` |
| `notification_events` | `notification_events_st_failed` | `c` | `e4aee8b9ef4c83bc11e93004c4682426` |
| `notification_events` | `notification_events_st_read` | `c` | `9c11258e82023c86a49682784bb9deed` |
| `notification_events` | `notification_events_st_scheduled` | `c` | `4f9c887c61d58f8397b8ed1cccffe26c` |
| `notification_events` | `notification_events_st_sent` | `c` | `a58860433476ba64a48f31334b760e02` |
| `notification_events` | `notification_events_status_allowed` | `c` | `e4484aed890cb6b7b9269e706a4fdfc3` |
| `notification_events` | `notification_events_template_nonempty` | `c` | `067496307c808ecab6b7ce5f26549907` |
| `notification_events` | `notification_events_ts_delivered` | `c` | `fbe4242dd975663b60da24008b7f61bc` |
| `notification_events` | `notification_events_ts_first_failed` | `c` | `6da5e2a0fb544fc73376f908a675fdf2` |
| `notification_events` | `notification_events_ts_last_failed` | `c` | `4a9966faccf53ce6361e152272bbee54` |
| `notification_events` | `notification_events_ts_read` | `c` | `83a0738844d862559c9270f4d4b9b82b` |
| `notification_events` | `notification_events_ts_sent` | `c` | `bd41a23baf688374d90466aa322af67e` |

## Funções — hash exato preservado da V13

As 13 funções seguem verificadas por `md5(replace(replace(prosrc, E'\r\n', E'\n'), E'\r', E'\n'))` — sem `lower`/`translate`/remoção de whitespace. `record_legal_acceptance(text,jsonb) = c9545e89b58ca524443e0161127f74ba`. Mudança em string, comentário, espaço, comando, operador, literal, capitalização ou pontuação altera o hash.

## Correções da V13 preservadas

Proprietário técnico via `pg_database.datdba` (exclusão só dele em `[10f]`); ownership das 4 tabelas e 13 funções; isolamento de `anon`/`authenticated`/`service_role`; papéis internos `[10h]`; defaults UUID; inventário dos 47 objetos; ACLs, RLS, grants, `search_path`, `SECURITY DEFINER`, assinaturas, triggers, policies, índices, retry, imutabilidade jurídica, integridade de `auth.users.id`, RPCs comerciais; veredito visível por exceção `P0001`; natureza estritamente somente leitura.

## Como executar

Ambos os arquivos são somente leitura. A variante visível exibe `POST_FASE2A_MARCO1_OK` / `POST_FASE2A_MARCO1_COM_FALHAS` por exceção `P0001`, com DETAIL contendo as checagens aprovadas, o número de falhas e a lista integral. Nada é escrito no banco.

## Resultado da execução remota (confirmado)

A Verificação Posterior V14 foi executada **manualmente** no projeto Supabase do
Site BDFlow e retornou:

- **`POST_FASE2A_MARCO1_OK`**
- **Checagens aprovadas: 214 · Falhas: 0 · nenhuma divergência.**

O `P0001` foi intencional, apenas para exibir o veredito (a execução permaneceu
estritamente somente leitura; nenhuma escrita ocorreu). Estado consolidado do
Marco 1:

- Hardening de `public.is_site_admin()` (V2) aplicado e verificado;
- Fundação V11 aplicada;
- Verificação posterior V14 aprovada (214 PASS / 0 FAIL);
- nenhuma migration corretiva necessária;
- nenhum SQL deve ser reexecutado.

*Registro documental apenas — nenhuma alteração de objeto remoto e nenhum SQL
executado por este pacote.*
