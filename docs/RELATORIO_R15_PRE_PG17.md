# R15 — Correções pré-PG17

**Branch:** `recon/m1-m2-launch`
**Base canônica M1:** `5cf545001367565ff26973eb33f10b6414f9067c`
**HEAD antes do R15:** `86ab63522da35d3b8af6a48bc54b0ca979a5d1af`
**Data:** 2026-08-22

---

## 1. Estado inicial (conferido antes de qualquer alteração)

| Item | Esperado | Encontrado | |
|---|---|---|---|
| Branch | `recon/m1-m2-launch` | `recon/m1-m2-launch` | ✅ |
| HEAD | `86ab635` | `86ab63522da35d3b8af6a48bc54b0ca979a5d1af` | ✅ |
| Árvore de trabalho | limpa | limpa | ✅ |
| Tree hash | — | `780b687798aa0d56a99bfbf30dd374f848e0cf1f` | — |
| Migrações canônicas M1 | 15 | 15 | ✅ |
| Migrações aditivas R0–R14 | 11 | 11 | ✅ |
| Total | 26 | 26 | ✅ |
| Migrações canônicas modificadas | 0 | 0 | ✅ |

**Divergência documental (não bloqueante).** Dois documentos citados na tarefa
não existem no repositório: `HANDOFF_CHATGPT_BDFLOW_SITE_2026-08-22.md` (não
localizado em lugar algum deste ambiente) e `RECONCILIATION_REPORT.md` (existe
apenas fora do repositório, no pacote de trabalho anterior). `RELATORIO_FINAL.md`
e `BLOQUEIOS.txt` estão no pacote `AUDIT_RECON_M1_M2`, e `RELATORIO_FINAL.md` é
byte a byte igual a `docs/RELATORIO_RECONCILIACAO_M1_M2.md`, que está versionado.
Como a própria tarefa determina que **o estado real do repositório e a evidência
reproduzível têm precedência sobre suposições narrativas**, e como HEAD, branch,
árvore e inventário de migrações batem exatamente com o esperado, o R15 seguiu a
partir do código. Nenhuma regra foi inferida de documento ausente.

---

## 2. Defeito do vínculo geográfico da fidelidade

### Causa raiz

`supabase/migrations/20260822126000_m2_manual_sale.sql`, linhas 98–101, dentro de
`public.admin_register_manual_commercial_order`:

```sql
SELECT c.city_key INTO v_city_key
  FROM public.commercial_region_cities c
 WHERE c.region_id = v_region.id AND c.is_active
 ORDER BY c.city_name LIMIT 1;
```

A chave da fidelidade vinha da **primeira cidade da região por ordem
alfabética** — não da cidade da empresa. `site_partner_companies.city` já contém
a cidade autoritativa e simplesmente não era lida.

### Por que "primeira cidade da região" estava errado — medido, não argumentado

Na única região semeada (Grande Vitória / ES) as cidades ativas são
Cariacica, Serra, Viana, Vila Velha e Vitória. A primeira por `city_name` é
**Cariacica**. Rodando as fixtures reais do R8 — seis empresas, todas com cidade
autoritativa `Vitória` — o banco ficou assim:

```
FIDELIDADE GRAVADA -> cnpj=70000000000177 uf=ES city_key=cariacica nicho=supermarket
FIDELIDADE GRAVADA -> cnpj=70000137000121 uf=ES city_key=cariacica nicho=pharmacy
FIDELIDADE GRAVADA -> cnpj=70000274000166 uf=ES city_key=cariacica nicho=womens_clothing
FIDELIDADE GRAVADA -> cnpj=70000411000162 uf=ES city_key=cariacica nicho=mens_clothing
FIDELIDADE GRAVADA -> cnpj=70000548000117 uf=ES city_key=cariacica nicho=womens_footwear
FIDELIDADE GRAVADA -> cnpj=70000685000151 uf=ES city_key=cariacica nicho=mens_footwear
EMPRESA REAL       -> cnpj=70000000000177 cidade=Vitória uf=ES
```

O prejuízo é nos dois sentidos, verificado pela função de leitura do domínio:

```
is_fidelized_context('70000000000177','ES','Vitória','supermarket')   = false
is_fidelized_context('70000000000177','ES','Cariacica','supermarket') = true
```

O fundador **não** recebia a fidelidade na cidade em que de fato opera, e a
fidelidade passava a valer numa cidade onde **nada foi contratado**. Quanto mais
cidades a região tiver, maior o erro; com uma região de cidade única o defeito
fica invisível — foi assim que atravessou treze suítes.

**Por que nenhuma suíte pegou:** a asserção do R8 (suíte 160) olhava apenas
`cnpj` e `niche_code`, nunca a `city_key` gravada.

### Correção implementada

Migração **aditiva** `20260822140000_r15_fidelity_city_binding.sql`:

1. **`m2_resolve_company_fidelity_city(company_id, region_id)`** — lê a cidade
   autoritativa em `site_partner_companies`, normaliza pela convenção que já
   existia no projeto (`public.commercial_city_key`: minúsculas, sem acentos,
   espaços viram hífen) e **exige** que a cidade normalizada pertença à região
   da oportunidade, com a UF conferida.
2. `admin_register_manual_commercial_order` passa a usar o resolvedor
   (`CREATE OR REPLACE`, preservando os GRANTs auditados).
3. O CNPJ gravado passa por `somente_digitos`, alinhando **escrita** e
   **leitura**: `m1_cnpj_valido` aceita formatação, então um CNPJ formatado
   gravaria uma chave que `is_fidelized_context` jamais encontraria.
4. A leitura na venda deixa de ser um `EXISTS` duplicado e passa a ser a mesma
   `is_fidelized_context` do resto do domínio — as duas não podem mais divergir.

### Comportamento fail-closed

| Situação | Retorno | Efeito |
|---|---|---|
| Cidade ausente ou só espaços | `company_city_missing` | venda recusada, nenhum registro |
| Cidade não resolvível na região | `city_not_in_region` | venda recusada, nenhum registro |
| UF da empresa inválida | `company_uf_invalid` | venda recusada |
| Chave de cidade ambígua | `city_ambiguous` | venda recusada (defesa em profundidade) |
| Empresa/região inexistente | `company_not_found` / `region_not_found` | venda recusada |

Nenhum caminho substitui a cidade da empresa por outra.

### Testes adicionados — suíte `910_r15_fidelity_city_binding.sql`

**34 asserções, 0 falhas.** Fixtures criadas pelo fluxo canônico do M1, com
empresas em **cidades diferentes da mesma região**:

- **Caso A** — empresa em Vitória: chave = `vitoria`; explicitamente **não**
  `cariacica`, `serra`, `viana` nem `vila-velha`; leitura reconhece Vitória e
  **não** vaza para outra cidade da região.
- **Caso B** — segunda empresa em Serra: chave = `serra`; asserção direta de que
  as duas empresas **não colapsam** na mesma cidade.
- **Caso C** — empresa em Guarapari (ES válido, fora da região): recusa
  `city_not_in_region`, **nenhum** registro de fidelidade e **nenhum** pedido.
- **Caso D** — cidade em branco → `company_city_missing`; cidade inexistente →
  `city_not_in_region`; nenhum registro em qualquer um dos dois.
- **Caso E** — normalização: `VITÓRIA`, `vitoria` e `  Vila   Velha  ` resolvem
  corretamente (acento, caixa e espaços).
- **Caso F** — a ambiguidade é impedida pela restrição única `(uf, city_key)` da
  baseline; o teste prova **a restrição**, em vez de fabricar um cenário
  impossível.
- **Controle positivo do critério** — a região tem mais de uma cidade ativa e a
  primeira por `city_name` **não** é Vitória. Sem isso os casos A e B poderiam
  passar por coincidência.
- Escrita e leitura concordam na chave; CNPJ formatado grava e lê em dígitos.

A asserção do R8 na suíte 160 foi **reforçada** (agora compara a `city_key`
gravada com `commercial_city_key` da cidade real da empresa), nunca afrouxada.

### Mutação adicionada

Reintroduz exatamente o defeito original no resolvedor:

```
-  v_key := public.commercial_city_key(v_company.city);
+  v_key := (SELECT c.city_key FROM public.commercial_region_cities c
+             WHERE c.region_id = p_region_id AND c.is_active
+             ORDER BY c.city_name LIMIT 1);
```

A suíte 910 acusa **19 asserções falhando** (log verbatim em
`logs/07_prova_mutante_r15_cidade.log`). Mutante **morto**.

---

## 3. Ciclo de vida da fidelidade do fundador

Reconstruído do código e das migrações vigentes, não presumido.

| Evento | Estado do pedido | Estado da fidelidade | Pedido posterior pode usar? | Evidência |
|---|---|---|---|---|
| Nenhuma venda ainda | — | `not_fidelized` | Não | nenhuma linha em `commercial_fidelity_records`; nada mais no schema escreve nessa tabela |
| Lista de espera, convite, reserva, início de checkout, tentativa de pagamento | — | `not_fidelized` | Não | **nenhum desses fluxos existe** no Site; o único gravador é `admin_register_manual_commercial_order` |
| `admin_register_manual_commercial_order` recusado (cidade, documento, data, exclusividade, CNPJ repetido) | não criado | `not_fidelized` | Não | retorno `{ok:false, reason}`; suíte 910 casos C e D provam que nada é gravado |
| `admin_register_manual_commercial_order` aceito | `signed`, `payment_status='pending'` | **`fidelized`** — registro criado | **Sim** | `INSERT INTO commercial_fidelity_records ... VALUES (..., v_id)` na mesma transação; suíte 910 “a fidelidade já existe no estado signed” |
| Efeito na oportunidade | oportunidade → `payment_pending` | `fidelized` | Sim | `UPDATE commercial_opportunities SET status='payment_pending'` |
| O **próprio** pedido fundador | `signed` | `fidelized` para os **futuros** | — | fundador sai com `fidelized=false` e preço não fidelizado (R$ 35.587,00 em 24 un.); suítes 160 e 910 |
| `admin_confirm_manual_bdflow_payment` aceito | `payment_status='confirmed'`, oportunidade → `contracted` | `fidelized` (inalterada) | Sim | suíte 910 “confirmação de pagamento não muda a chave de fidelidade” |
| Pedido fundador `cancelled` | `cancelled` | **não honrada** | **Não** | guarda R15 em `is_fidelized_context`; suíte 910 “fundador cancelado deixa de sustentar fidelidade” e “pedido futuro volta a preço NÃO fidelizado” |

### Ponto de ativação

**FIDELITY_LIFECYCLE=PROVED**

O ponto de ativação vigente é **`signed`** — a assinatura do instrumento
comercial, com evidência documental obrigatória (`document_reference` ou
`document_hash`), signatário e data de assinatura no passado. Não foi escolhido
por mim; está determinado por três fontes concordantes já existentes:

1. o código do R8, que insere o registro de fidelidade na mesma transação que
   cria o pedido em `status='signed'`;
2. o comentário do próprio R8: *“O primeiro contrato do contexto estabelece a
   fidelidade dos próximos.”*;
3. a asserção auditada da suíte 160: *“pedido nasce assinado e registra
   fidelidade futura.”*

Isso é coerente com as restrições assentadas: lista de espera, convite, reserva,
início de checkout e tentativa de pagamento **não** concedem fidelidade — nenhum
deles existe como fluxo, e nenhum deles escreve na tabela. O primeiro
engajamento comercial válido é o contrato assinado.

O R15 **preservou** esse ponto. Não o moveu para `payment_confirmed`.

### Invariante do fundador

A exigência é que uma compra fundadora que falhe ou seja cancelada **não** possa
deixar fidelidade válida indefinidamente.

**Auditoria do que existia:** `'cancelled'` é um status previsto no `CHECK` do
pedido, o gatilho de imutabilidade diz textualmente *“Use cancelamento”* — e
**nenhuma RPC de cancelamento existe**. Ou seja: não havia caminho de rollback,
mas também não havia evento de cancelamento alcançável. O cenário perigoso era
inalcançável por ausência, não por proteção.

**O que o R15 fez, sem inventar política:** a política de cancelamento/estorno
não é decidida aqui (está fora de escopo e permanece
`BLOCKED_PRODUCT_DECISION`). O que é inequívoco sob as regras já assentadas —
*um pedido cancelado não é engajamento comercial válido* — virou guarda
estrutural na única função de leitura do domínio:

```sql
AND NOT EXISTS (
      SELECT 1 FROM public.commercial_exclusivity_orders o
       WHERE o.id = f.established_by_order_id
         AND o.status = 'cancelled')
```

mais uma chave estrangeira `cfr_pedido_fundador_fk`, que impede um registro de
fidelidade apontar para um pedido inexistente. Assim, **qualquer** política de
cancelamento que venha a ser decidida já nasce sem deixar fidelidade órfã
válida — sem que o R15 tenha decidido quando, por quem ou com que consequência
financeira um pedido pode ser cancelado.

Mutação correspondente: remover a guarda faz a suíte 910 falhar. Mutante morto.

---

## 4. Correção de documentação (R10)

| | |
|---|---|
| Arquivo | `docs/APP_INTEGRATION_SPEC.md`, linha 102 (adicionado pelo commit R10 `8670e53`) |
| Referência obsoleta | `docs/SITE_APP_BRIDGE.md` **e** a migração `20260821184000_site_app_bridge.sql` |
| Estado real | nenhum dos dois existe na série R0–R14 — resíduo da reconstrução anterior ao M1 canônico |
| Referência correta | `20260822128000_m2_provisioning_outbox.sql` |

O texto passou a explicitar também **camada 1 de 5** e `BLOCKED_APP_REPOSITORY`,
que era justamente a informação que a referência quebrada escondia. Nenhuma
migração foi renomeada, reescrita, reordenada ou duplicada. Após a correção não
resta nenhuma referência órfã aos dois nomes no repositório.

---

## 5. Arquivos modificados

| Arquivo | Tipo | O que mudou |
|---|---|---|
| `supabase/migrations/20260822140000_r15_fidelity_city_binding.sql` | **novo** | resolvedor de cidade, venda manual corrigida, guarda do fundador cancelado, FK |
| `supabase/tests/910_r15_fidelity_city_binding.sql` | **novo** | 34 asserções: casos A–F, ciclo de vida, invariante, ACL |
| `supabase/tests/160_m2_manual_sale.sql` | modificado | asserção **reforçada**: passa a comparar a `city_key` gravada com a cidade real da empresa |
| `docs/APP_INTEGRATION_SPEC.md` | modificado | referência de migração corrigida (secção 4) |
| `scripts/audit/mutation-audit.sh` | modificado | dois mutantes R15 + correção de um falso positivo do próprio harness (secção 7) |
| `docs/RELATORIO_R15_PRE_PG17.md` | **novo** | este relatório |

Nenhum arquivo `src/` foi tocado: a venda manual é uma RPC administrativa
server-side sem consumidor no front-end, e a calculadora de preço da vitrine
(`src/domain/pricing/contractPricing.ts`) não participa da chave de fidelidade.

---

## 6. Migração

| | |
|---|---|
| Nome | `20260822140000_r15_fidelity_city_binding.sql` |
| Propósito | resolver a cidade da fidelidade pela cidade autoritativa da empresa, validada contra a região; normalizar o CNPJ da chave; unificar a leitura; impedir que fidelidade sobreviva a pedido fundador cancelado |
| Por que aditiva | as migrações R0–R14 já têm série de patches, evidência de auditoria, evidência de mutação e hashes de pacote publicados. Reescrevê-las apagaria a cadeia de evidência e deixaria a correção invisível no histórico. `CREATE OR REPLACE` preserva os GRANTs já auditados das funções existentes. |

**Contagem final: 15 canônicas M1 + 11 R0–R14 + 1 R15 = 27 migrações.**

---

## 7. Resultados de teste — contagens reais

| Gate | Resultado |
|---|---|
| `npm run validate` | **PASS** (`CHECK_LEGADO_LIMPO` + typecheck + testes + build) |
| `npm run typecheck` | **PASS**, 0 erros |
| Arquivos de teste Vitest | **21 passed (21)** |
| Testes Vitest | **268 passed (268)**, 0 falhas |
| `npm run build` | **PASS** |
| Testes canônicos M1 isolados | **130 passed (130)** em **12 arquivos**, 0 falhas |
| Suítes SQL auxiliares | **14/14 PASS**, **383 asserções PASS / 0 FAIL** |
| — específicas do R15 (suíte 910) | **34 asserções PASS / 0 FAIL** |
| — reforço na suíte 160 | 24 PASS (era 23) |
| Auditoria de mutação | **10/10 mutantes mortos** (8 anteriores + 2 do R15) |
| Varredura de segredos | **PASS** — 9 padrões, controles positivo e negativo verdes |

Todos os resultados SQL vêm do harness auxiliar rotulado
`[PG16 TESTE_AUXILIAR_NAO_GATE]`.

### Correção de um falso positivo do próprio harness de mutação

Ao adicionar o mutante do R15 descobri um defeito na auditoria de mutação
introduzida no R14: `sql_suite` rodava a suíte alvo **isolada**. Como várias
suítes dependem de fixtures das anteriores (o admin de teste nasce na suíte
000), uma suíte isolada falha por não conseguir sequer começar — e o harness
contava isso como *“mutante morto”*. Os mutantes SQL do R14 estavam sendo
declarados mortos pela razão errada.

Correção: o encadeamento real das suítes é reproduzido até a suíte alvo, o
veredito olha **somente** a saída do alvo, uma suíte anterior que também
observe o mutante não interrompe o encadeamento (`tests.finish()` só levanta no
fim do arquivo, com o estado do banco já aplicado), e um erro duro antes do alvo
é reportado como **INCONCLUSIVO** — nunca como morte. Sob o harness corrigido,
os dez mutantes seguem mortos, agora por observação real.

---

## 8. Prova de preservação

| Verificação | Resultado |
|---|---|
| Migrações canônicas M1 byte a byte idênticas | **15 / 15**, 0 alteradas |
| Fontes de teste canônicas M1 byte a byte idênticas | **13 / 13**, 0 alteradas |
| `PortalGuard.tsx` | idêntico à base — não enfraquecido |
| `safeInternalDestination.ts` | idêntico à base — não removido |
| `PortalLogin.tsx`, `App.tsx` | idênticos à base |
| `vite.config.ts`, `vitest.config.ts`, `tsconfig.json` | idênticos à base |
| `partner_applications` recriada | **não** — nenhuma migração M2/R14/R15 a recria |
| Fluxo legado de cadastro de owner reabilitado publicamente | **não** — `check:legacy` verde, sem rota nova |
| Endurecimento R14 (`REVOKE TRUNCATE, TRIGGER, REFERENCES`) | presente e provado pela suíte 900 (15 PASS) e por mutante |

### Regras de negócio assentadas — medidas no banco

| Critério | Medição | |
|---|---|---|
| `FIRST_12_PRESERVED` | farmácia 12 un. não fidelizada = **1.999.900** (R$ 19.999,00); supermercado 24 un. = **3.558.700** (R$ 35.587,00) | ✅ |
| `FIDELIZED_PRICING_PRESERVED` | farmácia 12 un. fidelizada = **1.558.800** (R$ 15.588,00); supermercado 24 un. = **3.117.600** (R$ 31.176,00) | ✅ |
| `POOL_75_70_PRESERVED` | supermercado `pool_bps=7500`; farmácia `pool_bps=7000` | ✅ |
| `ECONOMIC_POOL_DUE_INVARIANT` | `economic = pool + due` verdadeiro; `CHECK` no schema; mutante morto | ✅ |
| `FORMATION_84_PRESERVED` | **84 unidades em 6 nichos** (super 24, demais 12) | ✅ |
| `SITE_6_APP_7_PRESERVED` | 6 nichos comerciais; `BENEFIT_TYPES` com 7 entradas, `supermarket_stage_1/2 → supermarket` | ✅ |
| `R10_POLICY_SPEC_PRESERVED` | `src/domain/operational/README.md` mantém `APP_REPOSITORY=BLOCKED_APP_REPOSITORY` | ✅ |
| `R11_LAYER_1_BOUNDARY_PRESERVED` | camada 1 implementada; 2–5 bloqueadas; sentinela da ponte com mutante | ✅ |

---

## 9. Gate PostgreSQL 17

```
SUPABASE_PG17_FINAL_GATE=PENDING_EXTERNAL_EXECUTION
```

Reverificado neste ambiente, não presumido:

| Requisito | Estado |
|---|---|
| Supabase CLI | ausente (`command -v supabase` não retorna nada) |
| Daemon Docker | cliente presente, **daemon inacessível** (`Cannot connect to the Docker daemon at unix:///var/run/docker.sock`) |
| Cluster PostgreSQL local | **16.13**; binários apenas em `/usr/lib/postgresql/16` |

Nenhuma afirmação de equivalência é feita. O harness PG16 **não** é
“efetivamente PG17”, nem “compatível com PG17”, nem “pronto para produção”.

O candidato final a ser submetido ao gate real contém **27 migrações**
(15 M1 + 11 R0–R14 + 1 R15). Nenhuma operação em Supabase remoto foi realizada
ou tentada.

---

## 10. Bloqueios remanescentes, por classe

### `BLOCKED_APP_REPOSITORY`
- Repositório do App não inspecionável. Sem implementação operacional do App,
  sem E2E Site→App, sem contratos de API inventados.
- Ponte de provisionamento: camada 1 (banco/outbox do Site) implementada;
  camadas 2 (worker assinado), 3 (transporte HTTP), 4 (vínculo/resposta do App)
  e 5 (E2E) bloqueadas.
- `src/domain/operational/*` permanece POLÍTICA/SPEC.

### `BLOCKED_EXTERNAL`
- Credencial de provedor de e-mail indisponível: `HttpApiTransport` implementado
  e testado, envio real não exercitado. Nenhum segredo lido, impresso ou
  commitado.
- Textos jurídicos definitivos e assinatura eletrônica dependem de terceiros:
  prontidão técnica sim, operacional não.
- Gate Supabase PostgreSQL 17 real (secção 9).

### `BLOCKED_PRODUCT_DECISION`
- **Política de cancelamento/estorno do pedido de exclusividade.** O status
  `'cancelled'` existe no schema e o gatilho de imutabilidade instrui *“Use
  cancelamento”*, mas nenhuma RPC de cancelamento existe. Decisão necessária:
  quem pode cancelar, em que estados (antes da assinatura, após a assinatura,
  após o pagamento confirmado), com que consequência financeira, e o que
  acontece com a oportunidade e com a vaga na exclusividade.
  **Não bloqueia a segurança do R15:** a guarda estrutural garante que, seja
  qual for a política escolhida, um fundador cancelado não deixa fidelidade
  válida.

### `PENDING_SECURITY_DECISION`
- `ALTER DEFAULT PRIVILEGES` da baseline continua concedendo `ALL ON FUNCTIONS`
  a `anon`: toda função nova nasce executável por `anon` até um `REVOKE`
  explícito. Todas as funções M2 e a nova função R15 fazem esse `REVOKE`, e a
  suíte 900 vigia por igualdade de conjuntos nos dois sentidos. Inverter o
  padrão global é mudança de postura, fora do escopo do R15.
- Privilégios DML legados (`SELECT/INSERT/UPDATE/DELETE`) de `anon` e
  `authenticated` nas tabelas legadas seguem concedidos e mediados por RLS
  (provado em campo no R14). Apenas os privilégios **isentos de RLS** foram
  revogados.

### Informativo (herdado, não corrigido)
- `src/__tests__/commercial.test.ts` existe na base canônica mas **nunca roda**:
  o `include` do Vitest é `src/**/*.spec.{ts,tsx}`. Condição herdada do M1; não
  corrigida por ser configuração canônica.

---

## Critérios de sucesso do R15

```
FIDELITY_CITY_BINDING=PASS
FIRST_12_PRESERVED=PASS
FIDELIZED_PRICING_PRESERVED=PASS
POOL_75_70_PRESERVED=PASS
ECONOMIC_POOL_DUE_INVARIANT=PASS
FORMATION_84_PRESERVED=PASS
SITE_6_APP_7_PRESERVED=PASS
R10_POLICY_SPEC_PRESERVED=PASS
R11_LAYER_1_BOUNDARY_PRESERVED=PASS
BLOCKED_APP_REPOSITORY=PRESERVED
R14_SECURITY_HARDENING_PRESERVED=PASS
M1_CANONICAL_PRESERVED=PASS
LOCAL_TESTS=PASS
R15_MUTATION=PASS
SECRET_SCAN=PASS
FIDELITY_LIFECYCLE=PROVED
SUPABASE_PG17_FINAL_GATE=PENDING_EXTERNAL_EXECUTION
```

Nenhuma operação remota foi tentada: sem `git push`, sem escrita via API do
GitHub, sem PR, sem merge, sem branch remoto, sem deploy, sem Supabase remoto.
