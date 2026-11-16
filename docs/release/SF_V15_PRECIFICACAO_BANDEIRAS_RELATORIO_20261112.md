# SF-v1.5 — Precificação com bandeiras e reutilização por fidelização

- Data: 2026-11-12.
- Branch: `feat/precificacao-bandeiras-fidelizacao-20261112`, a partir de `main`
  `92f189ec967dccd2943ccfa0f606c678a7a793b9` (HEAD remoto confirmado antes de começar).
- Escopo: auditoria, nova autoridade econômica **preparada** (não ativada),
  modelagem mínima de produção e reutilização, minutas revisadas, testes.
- **Não feito:** nenhuma escrita em Production (só SELECT), nenhuma migration
  remota, nenhum merge, nenhum documento publicado, nenhum modelo promovido,
  nenhuma especificação aprovada, nenhum pedido histórico reprecificado, App
  intocado.

## 1. Auditoria do modelo de preços existente

| Elo | Onde | Achado |
|---|---|---|
| Regra de preço | `commercial_pricing_rules` | Versão 3 (SF-v1.4) `active`; 1 e 2 `superseded`. Status só aceitava `active`/`superseded`: **não havia como preparar uma versão sem ativá-la.** Sem gatilho de proteção. |
| Agenda explícita | `commercial_pricing_schedule` | 4 linhas SF-v1.4 conferidas centavo a centavo. **`service_role` com `arwdDxtm`** (privilégios padrão do schema) e **sem gatilho de proteção**: os centavos da SF-v1.4 eram alteráveis pelo servidor. |
| Cálculo | `calculate_niche_contract_pricing` | Única fonte para reserva, venda manual e preço público; ramo `explicit_schedule` lê a agenda. Aceitava qualquer versão por número. |
| Preço público | `get_public_niche_pricing`, `get_public_formation_economics` | Derivam do cálculo; mudam sozinhos quando a regra ativa muda. |
| Oportunidades / revisão | `PainelPreco.tsx`, `RevisaoContratacao.tsx` | Só exibem o que o servidor manda; parser estrito falha fechado. |
| Reserva | `create_commercial_checkout_intent` + gatilho `cci_aplicar_autoridade_v14` | Preço resolvido no servidor; fidelidade por `is_fidelized_context` (atividade efetiva, CNPJ, cidade). |
| Checkout / cobrança | `open_commercial_payment_attempt`, `paymentCore.ts` | Valor cobrado = `total_monetary_funding_required_cents` da intenção; nada é somado depois. |
| Snapshot do pedido | `finalize_commercial_order_from_intent` + `ceo_aplicar_autoridade_v14` + `ceo_snapshot_v14_imutavel` | Pedido copia a intenção centavo a centavo; snapshot econômico imutável. |
| Instrumento | `commercial_build_instrument_snapshot` | Fatos com proveniência; bloco V2 só para modelos que exigem especificação. **Catálogo de atividades versionado pela economia** (`catalog_version = contract_economics_version`) e **vazio em Production**. |
| Termos e Mestre | `legal_documents` | Nenhum Acordo Mestre nem Termos publicados (contratação falha fechada hoje). |

Divergência de formatação, sem efeito lógico: `cci_aplicar_autoridade_v14` e
`ceo_aplicar_autoridade_v14` estão em Production sem comentários e com outro
espaçamento; a lógica é idêntica ao repo. As funções alteradas aqui conferem
**byte a byte** (md5 do `prosrc`) com Production.

### Controle de produção (item 12 do handoff)

| Necessidade | Existia? |
|---|---|
| Upload de arte | Sim: `commercial_order_customization_images` (por pedido, com checksum e status; 0 registros). |
| Produção / ordens de produção | **Não.** |
| Estoque e reutilização | **Não.** (`products`, `product_state_stock` são da loja de camisas legada e não servem.) |
| Inspeção e conservação | **Não.** |
| Substituição | **Não.** |
| Custo de produção e fornecedor | **Não.** |
| Quantidade por pedido | Só `nominal_quantity` (unidades comerciais 24/12), que **não** é quantidade de bandeiras. |

## 2. Divergências entre a nova regra e Production

1. Preço não fidelizado vigente (R$ 29.999,00 / R$ 19.999,00) não inclui a fabricação de 84 bandeiras.
2. Nenhum conceito de peça física: nada distingue 84 bandeiras das 24/12 unidades comerciais.
3. O preço fidelizado não depende de reutilização verificada: não existe conjunto, inspeção nem bloqueio.
4. Reposição de peças não tem tratamento (nem bloqueio, nem política).
5. Agenda de preços gravável pelo `service_role` e sem proteção (risco à SF-v1.4 histórica).
6. Sem estado "preparada" para versão de regra: toda versão nova nasceria vigente.
7. Catálogo de atividades vazio e versionado por economia: a SF-v1.5 exige redação aprovada própria.
8. Texto legado "Seis benefícios por usuário" contradiz as sete participações potenciais.
9. Minutas V2 sem cláusulas de produção, reutilização e reposição.

## 3. O que foi implementado

### Migration `20261112120000_commercial_flag_production_pricing_sf_v15.sql` (aditiva)

- **Regras:** estado `prepared`; gatilho `cpr_protect` (nasce `prepared`;
  transições só `prepared → active → superseded`; valores imutáveis fora de
  `prepared`; publicada não é apagada; TRUNCATE recusado).
- **Agenda:** colunas `new_flag_units`, `flag_unit_reference_cents`,
  `flag_production_charge_cents` (NULL na SF-v1.4); CHECK `cps_bandeiras_coerente`
  (fabricação = peças × unitário ≤ parcela principal; fidelizado = 0 peças;
  não fidelizado > 0); gatilho `cps_protect` (só versão `prepared` é escrita);
  `service_role` reduzido a SELECT.
- **Versão 4 = SF-v1.5, `prepared`.** A fabricação fica **dentro** da parcela
  principal, então as invariantes vigentes (econômico = MEI + QA + principal;
  remuneração = QA + principal; CHECKs de liquidação v1.4) continuam valendo
  sem alteração.
- **Inventário:** `commercial_flag_sets` (conjunto nasce de UM pedido que
  exigiu produção; empresa, identidade e 84 peças derivadas do pedido; só
  aposentável) e `commercial_flag_set_inspections` (append-only; todas as peças;
  hash de evidência; categorias; resultado `reusable`/`replacement_needed`
  gerado). Só leitura para `service_role`; nenhuma RPC.
- **Resolvedor** `commercial_flag_reuse_resolution`: mesmo anunciante, mesma
  identidade, inspeção mais recente aprovando todas as peças e ainda não
  consumida. Recusas: `flag_reuse_not_verified` e `flag_replacement_policy_pending`.
- **Pedido e intenção:** cinco colunas de fatos de produção, CHECK de coerência,
  gatilhos `*_validar_producao_bandeiras` (resolvem da agenda; pedido de
  intenção **copia** a intenção; venda manual resolve igual), imutabilidade,
  índice único "uma inspeção, uma reutilização". Recusam versão `prepared`.
- **Reserva:** `create_commercial_checkout_intent` recusa o fidelizado sem
  reutilização verificada **antes** de tocar na oportunidade (nada reservado,
  nenhum preço).
- **Preço público:** versão preparada não é consultável (nem por versão
  explícita); chaves de bandeira aditivas só quando a economia as prevê. A
  saída da SF-v1.4 é **byte a byte idêntica** (md5 comparado).
- **Instrumento:** fatos `flag_*` no bloco V2, com proveniência; modelo que os
  exige falha fechado em pedido sem eles.
- **Formação:** `commercial_exclusivity_flag_production(exclusividade)` soma os
  **pedidos efetivos** (só `service_role`).
- Autoverificação no fim da migration (SF-v1.4 intacta, totais SF-v1.5) e
  verificação de transporte (UTF-8, sem CR).

### Rollback, operações e frontend

- Rollback `supabase/rollback/20261112120000_…_rollback.sql`: só enquanto a
  v4 nunca foi usada; devolve o catálogo idêntico.
- `supabase/ops/20261112_verificar_sf_v15_somente_leitura.sql` (SELECT) e
  `supabase/ops/20261112_ativar_precificacao_sf_v15.sql` (exige
  `smallflags.autorizacao_ativacao_sf_v15`, confere a agenda, recusa reserva viva).
- Frontend: parser aceita os fatos de bandeira e falha fechado se incoerentes;
  vitrine e revisão mostram "dos quais, fabricação de N bandeiras"; reserva
  mostra fabricação ou reutilização; mensagens fixas para as recusas;
  `ReferenciaOperacional` corrigida para sete participações potenciais.

## 4. Tabelas financeiras (centavos são a autoridade)

### Por categoria

| Rubrica | Super SF-v1.4 | Super SF-v1.5 novo | Super SF-v1.5 fidelizado | Comum SF-v1.4 | Comum SF-v1.5 novo | Comum SF-v1.5 fidelizado |
|---|---|---|---|---|---|---|
| Valor econômico | 2.999.900 | **3.293.900** | **2.817.600** | 1.999.900 | **2.293.900** | **1.618.800** |
| Contraprestação MEIs | 2.385.432 | 2.385.432 | 2.385.432 | 1.192.716 | 1.192.716 | 1.192.716 |
| QA SmallFlags | 12.168 | 12.168 | 12.168 | 6.084 | 6.084 | 6.084 |
| Parcela principal | 602.300 | 896.300 | 420.000 | 801.100 | 1.095.100 | 420.000 |
| dos quais, fabricação | — | 294.000 | 0 | — | 294.000 | 0 |
| Remuneração SmallFlags | 614.468 | 908.468 | 432.168 | 807.184 | 1.101.184 | 426.084 |
| Bandeiras novas | — | 84 | 0 | — | 84 | 0 |
| Cobrança benefício direto | 614.468 | 908.468 | 432.168 | 807.184 | 1.101.184 | 426.084 |
| Cobrança dinheiro | 2.999.900 | 3.293.900 | 2.817.600 | 1.999.900 | 2.293.900 | 1.618.800 |
| MEI ÷ econômico (informativo) | 79,52% | **72,42%** | **84,66%** | 59,64% | **52,00%** | **73,68%** |

Em `direct_benefits` a contraprestação é entregue como benefício e não é caixa
da SmallFlags; em `cash` o dinheiro destinado aos MEIs (`mei_cash_funding_cents`)
é distinguível da remuneração. A QA nunca vira dinheiro de terceiros.

### Formações (R$)

| Cenário | Bandeiras | Econômico | MEIs | Remuneração SmallFlags (com QA) | Fabricação (R$ 35,00 × peças) | Saldo após bandeiras | Saldo sem QA | MEI ÷ econ. |
|---|---|---|---|---|---|---|---|---|
| 6 novos | 504 | 147.634,00 | 83.490,12 | 64.143,88 | 17.640,00 | 46.503,88 | 46.078,00 | 56,55% |
| 6 fidelizados (reuso) | 0 | 109.116,00 | 83.490,12 | 25.625,88 | 0,00 | 25.625,88 | 25.200,00 | 76,52% |
| 1 novo (Supermercado) + 5 fidelizados | 84 | 113.879,00 | 83.490,12 | 30.388,88 | 2.940,00 | 27.448,88 | 27.023,00 | 73,31% |
| 1 novo (comum) + 5 fidelizados | 84 | 115.867,00 | 83.490,12 | 32.376,88 | 2.940,00 | 29.436,88 | 29.011,00 | 72,06% |
| 3 novos (Super + 2 comuns) + 3 fidelizados | 252 | 127.381,00 | 83.490,12 | 43.890,88 | 8.820,00 | 35.070,88 | 34.645,00 | 65,54% |
| 3 novos (comuns) + 3 fidelizados (Super entre eles) | 252 | 129.369,00 | 83.490,12 | 45.878,88 | 8.820,00 | 37.058,88 | 36.633,00 | 64,54% |

Referências projetadas, **não** lucro líquido nem caixa. Preservados:
R$ 141,99 × 588 participações potenciais (168 no Supermercado, 84 em cada
outra posição) = R$ 83.490,12; QA R$ 425,88 (121,68 + 5 × 60,84).

## 5. Fidelizado com peças danificadas

- Conjunto sem inspeção, com inspeção já consumida ou inexistente →
  `flag_reuse_not_verified`: **sem reserva e sem preço**; a fidelidade não muda.
- Inspeção com qualquer peça inadequada → `flag_replacement_policy_pending`:
  **sem reserva, sem preço, sem cobrança** de 84 peças ou das peças afetadas.
- Ponto de bloqueio: na **reserva** (antes de segurar a oportunidade) e, por
  defesa em profundidade, nos gatilhos de intenção e pedido (venda manual
  inclusa).
- Opções para a política de reposição (D-N5), **nenhuma autorizada**:
  (a) custo por peça substituída; (b) SmallFlags; (c) anunciante, por causa
  atribuível; (d) mista por peça (desgaste normal com a SmallFlags, troca de
  arte e perda imputável com o anunciante).
- Para habilitar qualquer opção: decisão D-N5 + cláusula D-J10 + nova versão
  econômica ou componente explícito na agenda, testada. Nada no navegador.

## 6. Testes (execução real)

| Gate | PG 16.15 | PG 17.6 |
|---|---|---|
| Suíte 290 (nova) | 92 PASS / 0 FAIL | 92 PASS / 0 FAIL |
| Ensaio de upgrade/rollback `flag-pricing-upgrade-check.sh` | 23 PASS / 0 FAIL | 23 PASS / 0 FAIL |
| Todas as suítes SQL | 15/25 falham — **mesmo conjunto e mesma contagem de FAIL por suíte da base `92f189e`** (fixtures antigas); 290 passa | idem |

Contraprovas por mutação (suíte 290 sobre a base + migration mutante): versão
preparada consultável; fidelizado presumindo reuso; inspeção reutilizada;
reposição com preço; `service_role` escrevendo a agenda; agenda sem proteção;
adicional cobrado em dobro — **todas detectadas**; controle com a migration
correta: 92 PASS / 0 FAIL.

- `npm run validate`: typecheck OK; Vitest **67 arquivos, 1.231 testes PASS**
  (1 skipped; base: 66 arquivos, 1.190), incluindo `precificacaoBandeiras.spec.tsx`
  (32, contra respostas reais do servidor) e 9 novos em `contratosV2Minutas.spec.ts`;
  build e build:worker OK.
- `scripts/audit/secret-scan.sh`: PASS.
- sha256 da migration: `1aabc8e3706b91558421535bd90ce561680d977db9a8f930704fee44b2f19056`
  (UTF-8, LF); rollback: `181010e8ee07f380a59b1761d0bebd50d0c5b52bb9cb4f7eb68257a4ab2e2b68`.

## 7. Pendências que exigem decisão do operador

- **D-N5** política de reposição; **D-J10** cláusula correspondente.
- **D-N6** procedimento de inspeção (quem, critérios, evidência, prazo).
- **D-N7** custos fora do valor do fornecedor (frete, embalagem, instalação, suporte, tributos, perdas).
- **D-N8** interface administrativa para conjuntos e inspeções (hoje só ato do dono do banco).
- **D-J11** redação de atividade no catálogo `SF-v1.5`.
- Autorizações para: aplicar a migration em Production; ativar a SF-v1.5;
  publicar as minutas revisadas.
- Momento da produção física em relação ao pagamento (o banco só exige que o
  pedido de origem não esteja cancelado).
