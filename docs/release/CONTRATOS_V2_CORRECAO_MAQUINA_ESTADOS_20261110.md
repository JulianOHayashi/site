# Contratos V2 — correção da máquina de estados de `commercial_advertising_specs`

- Data: 2026-11-10.
- Origem: auditoria independente do bundle `contratos-publicidade-veicular-v2-20261110.bundle`
  (HEAD `d37c65561ae578d63e30b8d498581865ecfc539e`).
- Escopo: só a migration `20261110120000` (ainda não aplicada em nenhum
  ambiente remoto), o rollback, a suíte 280, um ensaio novo e documentos da
  pasta `docs/legal/contratos-v2/`. Nada em Production foi escrito. Nenhum
  contrato publicado, nenhum merge.

## Achado da auditoria (confirmado)

`commercial_advertising_specs_protect()` comparava uma lista fixa de colunas
no arquivamento: `id`, `notes` e `created_at` podiam mudar junto com
`approved → archived`.

## Achados adicionais desta revisão (confirmados por execução na versão auditada)

| # | Achado | Efeito |
|---|---|---|
| A2 | `INSERT` aceitava linha já `approved` ou `archived` | aprovação sem passar pela transição |
| A3 | `draft → archived` direto era aceito | "arquivada" sem nunca ter sido aprovada |
| A4 | `id` e `created_at` mutáveis também em `draft` | identidade e auditoria alteráveis |
| A5 | `TRUNCATE` não dispara gatilho de linha | aprovada/arquivada apagável |
| A6 | privilégios padrão do schema `public` (Production: `postgres` concede `arwdDxtm` a `service_role`, consultado só por leitura em `pg_default_acl`) | `service_role`, que ignora RLS, tinha INSERT/UPDATE/DELETE/TRUNCATE |

## Correção (no gatilho, não em comentário)

- `cas_protect` passa a ser `BEFORE INSERT OR UPDATE OR DELETE`:
  - INSERT só como `draft`;
  - `id` e `created_at` imutáveis em qualquer estado;
  - `draft → draft` (edição) e `draft → approved` permitidos; qualquer outro destino a partir de `draft`, recusado;
  - `approved → archived` só se `to_jsonb(NEW) - 'lifecycle_status' - 'archived_at'`
    for igual ao mesmo recorte de `OLD`, e `archived_at >= approved_at`;
  - `approved → qualquer outro`, `archived → qualquer`, recusados;
  - DELETE só de `draft`.
- `cas_protect_truncate` (`BEFORE TRUNCATE`, por instrução): recusa se houver
  linha que não seja `draft`.
- `REVOKE ALL ... FROM PUBLIC, anon, authenticated, service_role` e depois
  `GRANT SELECT` ao `service_role`. Nenhuma permissão ou RPC nova.

### Auditoria da técnica `to_jsonb`

| Tipo atual | Representação | Conclusão |
|---|---|---|
| `uuid`, `text` | string JSON exata | qualquer diferença detectada |
| `integer` | número JSON (igualdade numérica exata) | correto para inteiros |
| `timestamptz` | string ISO 8601 com microssegundos, na mesma sessão para OLD e NEW | 1 µs detectado (teste) |
| `NULL` | JSON `null`, distinto de `''` | texto → NULL detectado (teste) |

`jsonb - text` remove só a chave nomeada; a igualdade de `jsonb` não depende
da ordem das chaves. Coluna acrescentada no futuro entra automaticamente na
comparação (teste com `ALTER TABLE ADD COLUMN` dentro de savepoint).

## Resultados (execução real)

| Gate | PG 16.15 | PG 17.6 |
|---|---|---|
| Suíte 280 (linhas PASS impressas) | 68 PASS / 0 FAIL | 68 PASS / 0 FAIL |
| `advertising-spec-archive-check.sh` (cenários isolados) | 25 PASS / 0 FAIL | 25 PASS / 0 FAIL |
| `contract-v2-upgrade-check.sh` (instala, escopo, rollback idêntico, rollback bloqueado) | 9 PASS / 0 FAIL | 9 PASS / 0 FAIL |
| Todas as suítes SQL | 15/24 falham, **conjunto e contagem idênticos ao HEAD auditado** (fixtures antigas, pré-existentes) | mesmo conjunto |

- `npm run validate`: 66 arquivos, 1190 testes PASS (1 skipped), typecheck, build e build:worker OK.
- `scripts/audit/secret-scan.sh`: PASS.

### Contraprovas por mutação

| Versão | Resultado |
|---|---|
| Migration auditada original (`d37c655`), cenários isolados | 15 PASS / **10 FAIL**: id, notes e created_at no arquivamento; TRUNCATE; INSERT aprovado; draft → archived; 4 privilégios de escrita do service_role |
| Sem a comparação `to_jsonb` | suíte 280 com 6 FAIL |
| Sem a guarda de `id`/`created_at` | suíte 280 com 18 FAIL |
| `service_role` com privilégios padrão | suíte 280 com 1 FAIL |
| Sem gatilho de TRUNCATE | suíte 280 com 10 FAIL |
| INSERT aprovado e `draft → archived` liberados | suíte 280 com 4 FAIL |

## Preservado

Bloqueio contratual (D9 e `commercial_advertising_spec_not_approved`), preços,
documentos publicados, contratos históricos, App, posições e segmentos: sem
alteração. O plano de publicação passou a registrar a especificação como
`draft` e aprová-la por `UPDATE` (passos 3.1 e 3.1b).
