# Comercial V2 — Relatório de implementação local

**Data:** 2026-09-06
**Estado:** implementação local completa; **validação em PostgreSQL pendente**.

```
COMMERCIAL_V2_LOCAL_IMPLEMENTATION=PASS
COMMERCIAL_V2_SQL_EXECUTION=NOT_RUN_ENVIRONMENT_BLOCKED
COMMERCIAL_V2_FINAL_RELEASE=NOT_YET_ACCEPTED
DISPLAY_PERCENTAGES_ARE_NON_AUTHORITATIVE=YES
CENT_VALUES_ARE_AUTHORITY=YES
PAYMENT_PROVIDER_INTEGRATED=NO
PAYOUT_TO_USERS_INTEGRATED=NO
```

---

## 1. Identidades

| Marco | Commit | Árvore |
|---|---|---|
| Baseline R16 aceita | `0bf3390a2aa5cc69df25a13b96f62ce084145239` | `3245cf667a2368ab98e326c2d564a45180994a7e` |
| CP0 — rascunho da migration | `b338fe716b16ea6f879af7b09f98d76966a99140` | `520b9f2e6052d93499c039739181fe693d7e0244` |
| CP1 — domínio | `54c113a3cf354cb7d0858016e34da1305dd1d4fb` | `237cf09fa9f37c15d7a30241ad3abdfb2d15227e` |
| CP1b — UI e rota | `21ac7e6efd04eed2a42f988243829b72dab79f6e` | `5bcee1ab22faa2c33a7daf6d19b0e59ee4abbf1f` |

Branch: `recon/post-r16-commercial-v2-checkout`.
`MIGRATIONS=28`, `HISTORICAL_MIGRATIONS_CHANGED=0` — as 27 históricas
permanecem byte a byte idênticas à baseline R16, verificado por
`git diff --name-only 0bf3390 HEAD -- supabase/migrations/`.

---

## 2. Constantes econômicas

```
FOUNDING_BLOCK_UNITS=12          FOUNDING_BLOCK_PRICE_CENTS=1_999_900
EXTRA_UNIT_PRICE_CENTS=129_900   FIDELIZED_UNIT_PRICE_CENTS=129_900

não fidelizado  supermercado  3_558_700 = 2_554_305 + 1_004_395
não fidelizado  comum         1_999_900 = 1_335_459 +   664_441
fidelizado      supermercado  3_117_600 = 2_237_699 +   879_901
fidelizado      comum         1_558_800 = 1_040_908 +   517_892

formação        13_558_200 = 9_231_600 + 4_326_600
                84 usuários, 109_900 centavos por usuário completo
```

A regra antiga de 10 unidades não existe em código, teste, migration ou UI.
Verificado por varredura, com os comentários removidos para que a asserção
mire o código e não a explicação de por que a regra foi aposentada.

---

## 3. Política de razão exata

`pool_bps` inteiro **não representa** a V2:

```
supermercado  2.554.305 / 3.558.700 = 71,7763508...%
comum         1.335.459 / 1.999.900 = 66,7762888...%
```

Arredondar para 7178/6678 produziria centavos diferentes dos aprovados.
A participação é guardada como **razão exata de inteiros**, cujo numerador e
denominador são o próprio par (pool, econômico) do contrato de referência não
fidelizado — reproduz o centavo aprovado por construção, sem resto.

Valores derivados usam divisão inteira por piso:

```
user_pool_cents = floor(economic_value_cents * numerador / denominador)
bdflow_ops_investment_cents = economic_value_cents - user_pool_cents
```

O piso é decisão contratual: o pool nunca excede a participação da categoria,
e o centavo fracionário fica do lado BDFlow.

**Percentuais são rótulos de exibição** — `aprox. 71,7763%` e
`aprox. 66,7763%` — guardados como texto aprovado. Não entram em cálculo, e há
teste provando que a fonte não os converte em número.

---

## 4. Matriz de resíduos 84×6

Cada pool dividido por 84 deixa resto: supermercado 30.408 + 33, comum
15.898 + 27. Base por participante 109.898; resíduos 168 = 84 × 2.

Uma primeira ideia — enfileirar 168 fichas e dar duas a cada participante —
fechava as somas mas permitia que um participante recebesse os dois centavos
do **mesmo** nicho. Substituída por matriz binária determinística: para cada
slot, os dois nichos **distintos** com maior saldo, desempate pela ordem
canônica fixa.

```
soma por nicho          = [33, 27, 27, 27, 27, 27]
soma por participante   = 2
entradas                ∈ {0, 1}
totais por participante = 109.900 centavos
total distribuído       = 9.231.600 centavos
```

Falha fechada se os saldos não zerarem. Nada de aleatoriedade, relógio, ordem
física de linha, UUID ou entrada do navegador decide alocação — há teste
varrendo a fonte por essas fontes de instabilidade.

Supermercado nas duas etapas do App: piso na etapa 1, restante na etapa 2,
com recomposição exata provada.

O Site não se torna autoridade operacional: elegibilidade e liberação de
benefício continuam sendo do App.

---

## 5. Liquidação × trilho de pagamento — eixos distintos

```
benefit_settlement_mode = direct_benefits | cash      (escolha da empresa)
payment_method          = pix | credit_card           (derivado da fidelidade)
```

| Modo | Fidelidade | Trilho | Cobrança |
|---|---|---|---|
| direct_benefits | não fidelizado | Pix | 1.004.395 |
| cash | não fidelizado | Pix | 3.558.700 |
| direct_benefits | fidelizado | Cartão | 879.901 |
| cash | fidelizado | Cartão | 3.117.600 |

O pedido não fidelizado de supermercado é **um** pagamento em Pix: o bloco de
12 unidades é regra de preço, não fronteira de trilho.

Mudar o modo não altera valor econômico, pool nem fidelidade — só quanto
precisa passar por trilho de pagamento.

Nenhuma afirmação de custódia, segregação ou repasse já executado.

---

## 6. Venda manual ciente de versão

A assinatura de 10 argumentos foi **removida** e substituída por uma única de
11, com `p_benefit_settlement_mode`. Acrescentar o parâmetro sem remover a
anterior criaria uma sobrecarga: as duas ficariam executáveis e a antiga
continuaria capaz de criar pedido V2 sem modo de liquidação. Contrato ambíguo
em função `SECURITY DEFINER` é porta que ninguém lembra de fechar depois.

Nenhum código em `src/` chama essa RPC — conferido antes da remoção.

Servidor deriva: versão da tabela, fidelidade, econômico, pool, parcela
BDFlow, trilho. O chamador informa apenas o modo de liquidação, validado
contra os dois valores aprovados. `pool_bps` grava NULL sob V2.

---

## 7. Confirmação de financiamento — neutra de provedor

`admin_confirm_commercial_funding` é nova. A RPC V1
`admin_confirm_manual_bdflow_payment` é **preservada**: ela codifica a
semântica antiga, em que o cobrado é sempre o devido à BDFlow porque o pool
nunca era aportado em dinheiro. Fazê-la significar "às vezes o econômico
inteiro" sem auditar chamadores mudaria o sentido de uma função existente
pelas costas de quem a usa. Pedido V1 apresentado à RPC V2 é recusado com
`v1_order_use_legacy_rpc`.

O valor esperado sai do **instantâneo imutável** do pedido, nunca do chamador.
Idempotente: repetir a confirmação devolve o estado sem sobrescrever valor,
autor ou instante — o retorno idempotente acontece antes de qualquer `UPDATE`,
e há teste provando essa ordem.

Sem chave Pix, QR, adquirente, webhook ou token de provedor. O retorno inclui
`user_payout_executed: false`: confirmar financiamento não significa que
dinheiro chegou a usuário algum.

---

## 8. Transparência pública

`PainelPreco` mostra, em reais, para as condições fundadora e fidelizada: o
valor econômico, o pool com o percentual declarado como aproximação, e a
parcela BDFlow/operação/investimentos. A formação 12 + 12 unidades é
explícita.

A afirmação incondicional anterior — de que o pool "não é pago à BDFlow" e é
sempre honrado na rede do parceiro — foi removida, porque deixou de ser
universalmente verdadeira sob a V2.

`ResumoFormacao`, montado em `/oportunidades`, mostra os quatro números da
formação completa. Os valores vêm da política canônica do domínio, não de
aritmética escrita na tela: duplicar as contas deixaria a vitrine capaz de
divergir do servidor sem ninguém perceber. O R$ 1.099,00 é qualificado no
próprio texto como alocação de quem cumpre todos os requisitos operacionais —
não saldo automático de cadastro.

---

## 9. Rota `/checkout`

Superfície de **revisão**, em `src/pages/RevisaoContratacao.tsx`, sob
`CommercialTerritoryGuard`. Não cria pedido: o ciclo aceito é manual-first, e
uma rota pública que criasse pedido contornaria essa autoridade.

Mostra composição, condição comercial e trilho como **leitura derivada** — não
há seletor Pix/cartão. O seletor de liquidação usa `radio` real, é operável
por teclado, e a seleção não é comunicada só por cor.

Nenhum valor é aceito por query string; nada lê armazenamento do navegador.

**O arquivo não se chama `Checkout.tsx`.** Esse caminho pertence à loja de
camisas revogada e `check:legacy` o proíbe. O guarda estava certo; o módulo
foi renomeado em vez de o controle ser afrouxado. A rota pública continua
`/checkout`.

---

## 10. Segurança

- `commercial_checkout_intents` e `commercial_pool_share_ratios` com RLS
  habilitada e `REVOKE ALL` de `PUBLIC`, `anon`, `authenticated`,
  `service_role`; só `SELECT` para `authenticated`, filtrado por titularidade
  ativa via `site_company_members`. Escrita apenas por RPC.
- Funções novas `SECURITY DEFINER` com `search_path` fixado em `pg_catalog` e
  referências qualificadas.
- `REVOKE EXECUTE ... FROM PUBLIC` e `FROM anon` explícitos nas três RPCs.
- Trigger de imutabilidade do instantâneo fora de `draft`.
- Nenhum privilégio foi ampliado para fazer teste passar.

---

## 11. Execução local

| Comando | Exit | Resultado |
|---|---:|---|
| `npm run typecheck` | 0 | PASS |
| `npx vitest run` | 0 | 32 arquivos, 631 testes |
| `npm run build` | 0 | PASS |
| `npm run build:worker` | 0 | PASS |
| `npm run check:legacy` | 0 | `CHECK_LEGADO_LIMPO` |
| `scripts/audit/secret-scan.sh` | 0 | PASS |
| `npm audit --omit=dev` | 0 | 0 vulnerabilidades |
| `git diff --check` | 0 | limpo |
| isolamento do bundle de navegador | 0 | PASS |
| auditoria do artefato do worker | 0 | PASS |
| smoke de processo do worker | 0 | PASS |

O worker R16 não foi modificado; os gates dele foram reexecutados porque a
configuração de build é compartilhada.

---

## 12. SQL — escrito, não executado

`supabase/tests/200_commercial_v2.sql` cobre versionamento, centavos exatos
não fidelizados e fidelizados, invariante econômica, agregado da formação,
semântica de `pool_bps` por versão, preservação dos pedidos V1, invariantes da
intenção de checkout, assinatura única da venda manual sem parâmetro de valor,
existência e segurança da confirmação V2, fronteiras de privilégio e
imutabilidade do instantâneo.

**Nenhuma asserção foi observada passando.** Não há `psql`, cluster
PostgreSQL, Supabase CLI nem Docker neste ambiente. A migration não foi sequer
parseada.

```
COMMERCIAL_V2_SQL_EXECUTION=NOT_RUN_ENVIRONMENT_BLOCKED
COMMERCIAL_V2_MIGRATION_PARSE=NOT_RUN_ENVIRONMENT_BLOCKED
COMMERCIAL_V2_SQL_REGRESSION=NOT_RUN_ENVIRONMENT_BLOCKED
```

---

## 13. Ações remotas

```
PRODUCTION_DB_WRITES=0   STAGING_DB_WRITES=0   APP_DB_WRITES=0
REAL_PAYMENT_PROVIDER_CALLS=0   REAL_CUSTOMER_EMAILS=0
GIT_PUSH=0   GIT_MERGE=0   VERCEL_PRODUCTION_DEPLOY=0
```

---

## 14. Bloqueadores antes do aceite em staging

1. Execução da migration 28 e da suíte SQL contra PostgreSQL 17.6 descartável.
2. Seleção do provedor de pagamento — Pix e cartão continuam não integrados.
3. Arquitetura de repasse ao usuário no modo dinheiro: custódia, razão
   contábil e trilho de pagamento não existem. Nenhuma tela afirma que existem.
4. Texto jurídico final da escolha de liquidação.
5. Contrato de integração Site → App para propagar o instantâneo comercial
   imutável, incluindo `benefit_settlement_mode` e a versão da política de
   distribuição.
