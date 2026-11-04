# Etapa B — plano de publicação coordenada (posições, Calçados, Outros e segmentos)

> **Status: PREPARADO, NÃO EXECUTADO.** Nada deste plano foi aplicado em
> Production. Cada passo marcado 🔒 exige autorização explícita do
> responsável antes de rodar.

Branch: `feat/commercial-positions-segments-20261103` (base `main` = `86a73b3`).
Migration: `supabase/migrations/20261103120000_commercial_positions_segments.sql`
— revisão final: blob git `2d9fd44f639f4e0e32bdd8884dbaf4de0f5bb688`,
sha256 `3a6436a3f9645545bb201be70c99bff02e87d261cc977f2cfaedb568cf1af3b1`.

> **Sobre o sha256.** No patch (`git format-patch`) o arquivo aparece **duas
> vezes**: criado no commit 1/5 (blob `8a7a495…`, sha256 `8dfad66c…`) e
> alterado no 3/5 (preservação de ACL). O sha256 aplicável é o da revisão
> final, que é o que fica na árvore do HEAD. Para conferir:
> `git show <HEAD>:supabase/migrations/20261103120000_commercial_positions_segments.sql | sha256sum`.
> O registro de versão (§3, passo 8) **não confia** nesse texto: ele exige a
> impressão digital das 28 funções criadas pela migration
> (`33d122ef4ed5c0af806c9d27f61ba7fb/28`) e aborta se ela não bater.

## 1. Estado de Production revalidado (somente SELECT; 2026-11-03 e de novo em 2026-11-04)

`supabase/ops/20261103_precheck_readonly.sql` → 10/10 itens `ok = true` (snapshot de 2026-11-04):

| Item | Valor |
|---|---|
| Histórico | 62 linhas, hash `f13ee66f…` (pré-reconciliação) |
| Catálogo | 6 nichos antigos ativos, 24 + 5×12 = 84 |
| Calçados F/M | só a GV nº 1 (`forming`), duas oportunidades `available` |
| Referências a calçados F/M | 0 |
| Intents/pedidos/pré-compras/fila/fidelidade/provisionamento | 0/0/0/0/0/0 |
| Objetos novos | inexistentes |
| 12 funções substituídas, normalizadas | `154f4fa1…/12`, igual ao repositório (sem deriva) |
| `cfr_unico` | presente |
| `site_admins` | 1 |
| ACL authenticated (reserva/fila/manual) | **false**/true/true |

A reserva de checkout está **fechada** para `authenticated` em Production
(só `postgres`). A migration preserva a ACL de cada ambiente: ela não reabre
a reserva. Reabrir é uma decisão à parte (§8).

## 2. Divergência do histórico de migrations

- 62 registros em Production e 63 arquivos no repositório (o 63º é a migration nova).
- **31 versões diferentes**, todas a partir de `commercial_checkout_reservation`.
  Elas foram aplicadas por `apply_migration`, que grava o **horário da
  aplicação** como versão. Os nomes batem 1:1.
- Conteúdo: 19 das 31 com md5 idêntico. 12 foram aplicadas em forma
  encurtada (sem comentários).
- Equivalência funcional auditada: 159/159 funções com hash normalizado igual
  (3 diferenças cosméticas de literais concatenados). Colunas, índices,
  gatilhos e políticas são idênticos. Constraints diferem só na formatação
  PG17×PG16.

**Consequência:** um `supabase db push` hoje veria 31 remotas desconhecidas e
31 locais pendentes, e tentaria reaplicar migrations já aplicadas. **Proibido.**

### Procedimento revisado (sem `db push` cego)

`supabase/ops/20261103_reconcile_migration_history.sql`:

- muda **apenas** `supabase_migrations.schema_migrations.version` das 31
  linhas, casando pelo `name`. Não mexe em DDL, `statements` nem `name`;
- tem trava de tabela e pré-condição dentro da transação: 62 linhas, hash
  `f13ee66f…`, mapa com 31 entradas e destinos livres. Qualquer desvio aborta;
- pós-condição antes do COMMIT: 62 linhas e 31 versões do repositório;
- hash final esperado: `c9924f1092689753d1bdfb59670aa8c4` (igual ao conjunto
  de arquivos do repositório, sem a migration nova);
- reversão: `…_revert.sql` (troca inversa, mesmas travas).

Ensaio: `scripts/db-test/reconcile-history-check.sh` com a fixture
`scripts/db-test/fixtures-prod-migration-history-20261103.txt` (lida de
Production). **PASS:** ida, segunda execução recusada, reversão exata e
`statements` intacto.

## 3. Ordem de publicação

| # | Passo | Quem/como | Gate |
|---|---|---|---|
| 0 | Revisão do PR, gates verdes (§6) | revisor | aprovação |
| 1 🔒 | Merge do PR em `main` e deploy do **frontend** | Vercel | autorização |
| 2 | Verificar o frontend com o backend antigo (§4) | navegador | vitrine com 6 nichos antigos, sem seletor de segmento |
| 3 | Rodar a pré-checagem (somente leitura) | execute_sql | 10/10 ok |
| 4 🔒 | Reconciliar o histórico | SQL Editor ou execute_sql, arquivo exato | hash `c9924f1…` |
| 5 | `supabase db push --dry-run` (opcional, se houver CLI conectado) | CLI | lista **só** `20261103120000` |
| 6 | Pré-checagem de novo | execute_sql | 10/10 ok, hash pós |
| 7 🔒 | Aplicar a migration pelo **conteúdo exato do arquivo** numa única execução (SQL Editor ou execute_sql). **Não** usar `apply_migration` (cria outra versão) nem `db push` | operador | COMMIT sem erro |
| 8 🔒 | Registrar a versão: `supabase/ops/20261103_register_positions_segments_version.sql` (verifica a impressão digital `33d122ef…/28`, o catálogo 6/84 e as tabelas novas) | execute_sql | 63 linhas, `20261103120000` presente |
| 9 | Verificação pós-publicação (§5) | execute_sql e navegador | todos ok |

Por que o frontend vai **antes**:

- o parser de transição aceita o conjunto antigo **ou** o novo de posições,
  nunca uma mistura;
- `acceptsSegment` ausente vale `false`, então o seletor de segmento não
  aparece com o backend antigo;
- `p_segment_id` só é enviado quando existe.

O frontend **antigo** com o backend **novo** falha fechado: o parser rejeita os
códigos `footwear` e `others` e mostra erro na vitrine. Por isso a migration
vem depois e a janela entre os passos 7 e 9 deve ser curta.

Os passos 7 e 8 são duas transações. Se o 8 falhar depois do 7, o banco já
está correto: basta corrigir a causa e repetir o 8, que é idempotente por
pré-condição.

### O que a migration faz em Production (impacto real)

- `commercial_niches`: `womens_footwear` e `mens_footwear` passam a inativos
  (sort 105/106). Entram `footwear` (Calçados, 12, sort 5) e `others`
  (Outros, 12, sort 6). Continuam 6 ativos e 84 unidades. Supermercado continua 24.
- D2: as 2 oportunidades livres da GV nº 1 são **remapeadas** (`womens_footwear`→`footwear`,
  `mens_footwear`→`others`), com 2 linhas em `audit_logs`
  (`commercial_opportunity.position_remapped`). A guarda `d2_bloqueado` aborta
  tudo se houver reserva, pedido, pré-compra, fila ou intenção nessas posições.
- Tabelas novas: `commercial_segments` e `commercial_segment_requests` (vazias).
- Colunas novas de segmento em intents, pedidos, pré-compras e fila (todas nulas).
- Fidelidade: `fidelity_identity` com backfill = `niche_code` (0 linhas hoje).
  `cfr_unico` é trocado por `cfr_identidade_unica`.
- Preço: inalterado. Categoria explícita (supermarket; os cinco de 12 →
  common); qualquer outro código → `pricing_category_unavailable`.
- Provisionamento para o App: falha fechado com `app_contract_v3_required` para
  pedido assinado em Calçados, Outros ou com segmento (D8).
- Instrumento contratual: falha fechado para segmento e Outros
  (`commercial_instrument_segment_activity_unavailable`) até a minuta adaptada
  ser aprovada (D9).
- ACL: as 3 RPCs recriadas herdam as permissões da assinatura antiga **neste
  ambiente**.

### Corpos de função: o que muda byte a byte

Doze funções existentes são **substituídas** por `CREATE OR REPLACE`. Em
Production, 9 delas têm texto diferente do repositório (as migrations
encurtadas, sem comentários), mas o conteúdo **normalizado** (sem comentários
e espaços) é idêntico nas 12. Isso foi conferido por função em 2026-11-04 e
está travado na pré-checagem. Depois da migration, Production passa a ter
exatamente os corpos do repositório, com comentários. O rollback também
restaura as versões do repositório: o resultado é equivalente ao estado
anterior, mas não idêntico byte a byte.

### Superfície pública nova em `get_current_commercial_formation`

A função é `STABLE SECURITY DEFINER SET search_path TO 'public'`, com os
mesmos atributos da versão em Production. O diff do corpo só acrescenta
`accepts_segment`, `requires_segment` e `segment {code, name}` da posição
ocupada (pedido vivo ou reserva vigente). Não saem empresa, valores nem
identificadores. **Ponto de decisão:** o nome do segmento de uma reserva
**ainda não paga** fica visível para quem consulta a vitrine. A vitrine usa
isso para desabilitar o segmento já ocupado. A alternativa é expor só pedidos
vivos e deixar a reserva ser recusada pelo servidor
(`segment_already_in_exclusivity`).

## 4. Verificação do passo 2 (frontend novo, backend antigo)

- `/oportunidades` lista as 6 posições antigas, sem erro.
- `/oportunidades/womens-footwear` abre normalmente e não mostra seletor de segmento.
- `/admin/segmentos` mostra erro de carregamento controlado (as RPCs ainda não existem), sem quebrar a página.

## 5. Verificação pós-publicação (passo 9)

```sql
select count(*)||'/'||sum(contracted_quantity) from commercial_niches where is_active;          -- 6/84
select string_agg(code, ',' order by sort_order) from commercial_niches where is_active;
  -- supermarket,pharmacy,womens_clothing,mens_clothing,footwear,others
select string_agg(niche_code||':'||status, ',' order by niche_code) from commercial_opportunities o
  join commercial_exclusivities e on e.id=o.exclusivity_id where e.sequence_number=1;            -- 6 available, sem *_footwear
select count(*) from audit_logs where action='commercial_opportunity.position_remapped';        -- 2
select has_function_privilege('authenticated','public.create_commercial_checkout_intent(uuid,text,text,uuid)','EXECUTE'); -- false (igual a antes)
select has_function_privilege('anon','public.list_commercial_segments()','EXECUTE');             -- true
select has_function_privilege('anon','public.admin_decide_commercial_segment_request(uuid,text,uuid,text,text,text,text,text,text)','EXECUTE'); -- false
select count(*) from supabase_migrations.schema_migrations;                                      -- 63
```

No navegador: a vitrine mostra Calçados e Outros. Outros exige segmento.
Farmácia, Roupas e Calçados oferecem "contratar como Outros". Supermercado
não oferece.

## 6. Estratégia de testes (executada localmente; ver relatório)

- Suíte SQL `270_commercial_positions_segments.sql`: 72 checks, cobrindo
  catálogo, D2, RLS, solicitação só por owner, decisão só por admin,
  unicidade de segmento por exclusividade (sequencial; a corrida simultânea
  entre duas sessões **não** foi ensaiada: a proteção é o advisory lock na
  reserva mais os índices únicos em pedidos e pré-compras, que valem mesmo
  sob corrida), Supermercado nunca, snapshot imutável, fidelidade por
  identidade, preço preservado, provisionamento e instrumento falhando fechado.
- Testes mutantes no SQL e no frontend: as mutações sobreviventes viraram testes.
- Não-regressão da suíte SQL auxiliar: assinaturas de FAIL e ERROR idênticas às
  do `main` (as 15 suítes que já falhavam no `main` continuam iguais, por
  fixtures antigas; nenhuma falha nova).
- Ensaio de upgrade sobre o estado de Production
  (`scripts/db-test/upgrade-positions-segments-check.sh`):
  - A: upgrade;
  - A2: registro da versão;
  - B: abort pelo D2;
  - C: rollback idêntico (funções, ACL, colunas, constraints, índices, gatilhos e dados);
  - D: rollback recusado com o modelo novo em uso;
  - E: ACL de Production preservada na ida e na volta.
- Aplicação em consulta única (modo SQL Editor/execute_sql) ensaiada: 6/84, 2
  auditorias, mesma impressão digital (`33d122ef…/28`) que via `psql -f`.
- Registro da versão: aborta sem reconciliação, com função adulterada
  (search_path trocado) e na repetição. Grava somente com a impressão correta.
- Frontend: typecheck, Vitest (inclui `commercialSegments.spec.tsx`), build,
  build:worker e validate.

## 7. Rollback

| Situação | Ação |
|---|---|
| Falha durante o passo 7 | Nada a fazer: a transação aborta inteira (provado no cenário B) |
| Passo 7 ok, nenhuma venda nova | 🔒 `supabase/rollback/20261103120000_commercial_positions_segments_rollback.sql` (guarda `rollback_bloqueado`), depois apagar a linha `20261103120000` do histórico e, se quiser, a reversão da reconciliação |
| Modelo novo já em uso (intent, pedido, pré-compra, fila ou fidelidade com Calçados, Outros ou segmento) | O rollback **recusa**. O retorno exige tratamento contratual caso a caso, não reversão de schema |
| Problema só no frontend | Rollback de deploy na Vercel para o build anterior. Ele falha fechado com o backend novo (vitrine com erro), então só faz sentido junto com o rollback do banco |

O rollback restaura:

- o catálogo antigo;
- o remapeamento inverso, com auditoria `position_remap_reverted`;
- as assinaturas e corpos anteriores das funções;
- as ACLs do ambiente;
- `cfr_unico`.

## 8. Decisões que dependem de autorização

1. Merge e deploy do frontend (passo 1).
2. Reconciliação do histórico (passo 4).
3. Aplicação da migration e registro da versão (passos 7 e 8).
4. **ACL da reserva de checkout:** hoje fechada em Production. A migration
   mantém fechada. Abrir a venda pública exige um GRANT explícito e separado,
   fora desta etapa.
5. Integração com o App (contrato v3): ver
   `docs/integracao/APP_CONTRACT_V3_POSICOES_SEGMENTOS_20261103.md`. Até lá,
   pedidos assinados em Calçados, Outros ou com segmento **não** provisionam.
6. Minuta contratual adaptada: ver
   `docs/legal/MINUTA_ADAPTACAO_POSICAO_SEGMENTO_RASCUNHO_20261103.md`. Até a
   aprovação jurídica, o instrumento para segmento e Outros falha fechado.
