# Pacote P0 — Inventário de funções legadas

**Escopo:** funções do schema `public` candidatas a legado mutável exposto
(SECURITY DEFINER, retorno diferente de `trigger`, executável por
PUBLIC/anon/authenticated). Fonte: leitura do código local (`supabase/*.sql`)
+ achados da auditoria de 2026-08-03 (leitura do banco remoto).

## Divergência importante registrada antes de qualquer alteração

O código-fonte local **não é fiel ao banco remoto**. A auditoria confirmou
zero migrations registradas em `supabase_migrations`, e isso se reflete em
pelo menos dois pontos comprovados nesta análise:

- `public.registrar_cancelamento(uuid, text, text)` — **não existe em nenhum
  arquivo `.sql` do repositório**. Só é conhecida pela auditoria (observação
  ao vivo do banco). O preflight deste pacote descobre essa função em tempo
  de execução via `pg_catalog`, sem depender de fonte local.
- `public.verificar_cascata`, `public.status_fidelidade`,
  `public.unidades_pagas_cnpj` (achados P1 da auditoria) — também **não
  existem em nenhum arquivo `.sql` local**. Documentadas abaixo como
  candidatas não comprovadas por fonte local; **não foram alteradas** neste
  pacote (a auditoria as classifica como P1 — vazamento de leitura, não
  mutação — e o prompt exige comprovação antes de conter qualquer função
  além das duas nomeadas).
- `public.create_my_partner_owner_registration(...)` (local, em
  `supabase/site-partner-core.sql`) referencia `public.site_partner_members`
  e `site_monthly_partners.owner_user_id` — **tabelas/colunas que a
  auditoria não encontrou no banco remoto**. Confirma, de forma
  independente, que o schema remoto divergiu da fonte versionada.

## 1. Contidas nesta migration (revogação de EXECUTE de PUBLIC/anon/authenticated)

| Função | Assinatura | Fonte local | Motivo |
|---|---|---|---|
| `registrar_cancelamento` | `(uuid, text, text)` | **ausente** (só auditoria) | P0 — SECURITY DEFINER, `anon` pode cancelar pedido, devolver estoque, alterar fidelidade, sem checar `auth.uid()` nem propriedade |
| `recalcular_pedido` | `(uuid)` | `supabase/site-schema-v2.sql:367` | P0 — SECURITY DEFINER, sem `search_path` fixo, `anon`/`authenticated` podem recalcular totais de um pedido arbitrário sem checar identidade/propriedade |
| `create_my_partner_owner_registration` | `(text, text, text, text, text, text, text)` | `supabase/site-partner-core.sql:195` | RPC de cadastro estruturalmente incompatível com o schema remoto atual (ver divergência acima); mantém o formulário quebrado no ar enquanto continuar pública |

A migration (`p0-contencao-migration.sql`) usa `to_regprocedure()` para
confirmar existência + assinatura exata de cada uma **antes** de revogar, e
aborta com mensagem clara (`P0_CONTENCAO_ABORTADA: ...`) se qualquer uma não
bater — sem `IF EXISTS` mascarando divergência.

## 2. Identificadas, mas **não alteradas** neste pacote

### 2.1 Trigger functions (não são RPC diretamente exploráveis)

Todas com `returns trigger`; chamar diretamente fora de um gatilho gera erro
nativo do Postgres ("trigger functions can only be called as triggers"), o
que as torna estruturalmente diferentes de `recalcular_pedido`/
`registrar_cancelamento` (que `returns void`/`jsonb` e são chamáveis livremente):

| Função | Fonte | Gatilho anexado |
|---|---|---|
| `baixar_estoque()` | `supabase/schema.sql:44` | `trg_baixar_estoque` (before insert em `orders`) |
| `devolver_estoque()` | `supabase/schema.sql:61` | `trg_devolver_estoque` (before delete em `orders`) |
| `aplicar_item_pedido()` | `supabase/site-schema-v2.sql:316` | `trg_item_pedido` (before insert em `order_items`) |
| `devolver_estoque_item()` | `supabase/site-schema-v2.sql:353` | `trg_devolver_item` (before delete em `order_items`) |
| `trg_recalcular_pedido()` | `supabase/site-schema-v2.sql:394` | `trg_totais_pedido` (after i/u/d em `order_items`) |
| `tocar_updated_at()` | `supabase/site-partner-core.sql:112` | (uso genérico de `updated_at`) |
| `proteger_membro()` | `supabase/site-partner-core.sql:127` | proteção de `site_partner_members` |
| `bloquear_delete_membro()` | `supabase/site-partner-core.sql:156` | proteção de `site_partner_members` |
| `proteger_parceiro()` | `supabase/site-partner-core.sql:169` | proteção de `site_monthly_partners` |

**Por que não contidas:** não são executáveis como RPC pública (retorno
`trigger`); conter aqui exigiria alterar triggers/DDL, fora do escopo deste
pacote (que só revoga EXECUTE de RPCs mutáveis diretamente chamáveis).

### 2.2 Funções de leitura, deliberadamente públicas (não mutam dados)

| Função | Fonte | Observação |
|---|---|---|
| `desconto_quantidade(integer)` | `supabase/site-schema-v2.sql:289` | `language sql stable`, só `SELECT`; `grant execute` explícito a `anon, authenticated` já existente |
| `desconto_para_cnpj(text)` | `supabase/site-schema-v2.sql:297` | `security definer stable`, só `SELECT`; `grant execute` explícito já existente |
| `is_site_admin()` | `supabase/site-schema-v2.sql:33` | `stable security definer`; usada pelas policies de RLS administrativas — **não tocar** |

Não mutam dados; a auditoria não as classifica como P0/P1 mutáveis. Ficam
fora da contenção.

### 2.3 Candidatas citadas pela auditoria (P1) sem fonte local — não comprovadas para conter

| Função | Achado da auditoria | Por que não contida agora |
|---|---|---|
| `verificar_cascata(uuid)` | Consulta pedido arbitrário sem autenticação (P1 — vazamento de leitura) | Sem fonte local para confirmar assinatura/comportamento exato; o prompt exige comprovação antes de alterar qualquer função além das duas nomeadas. O preflight (seção 10) a descobre ao vivo, se existir, para decisão em pacote futuro. |
| `status_fidelidade(cnpj, uf)` | Consultável anonimamente (P1) | Idem — sem fonte local; mesma cautela. |
| `unidades_pagas_cnpj(cnpj, uf)` | Consultável anonimamente (P1) | Idem. |

Essas três são risco **P1** (vazamento de leitura), não **P0** (mutação sem
autenticação) — a auditoria já as separa dessa forma, e o prompt deste
pacote pede contenção comprovada apenas das mutáveis P0 nomeadas
explicitamente. Ficam documentadas para decisão em pacote futuro, com
preflight pronto para revalidá-las.

## 3. O que a seção 10 do preflight pode revelar de novo

A seção 10 de `p0-contencao-preflight.sql` roda uma descoberta genérica (não
depende de nomes fixos): qualquer função `public.*`, `SECURITY DEFINER`,
retorno ≠ `trigger`, com `EXECUTE` concedido a PUBLIC/anon/authenticated.
Se aparecerem funções além das listadas acima, **não estão comprovadas por
este documento** — precisam de uma nova rodada de análise antes de qualquer
contenção adicional.
