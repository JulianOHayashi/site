# R3 — QA exclusivamente em produtos no benefício direto; sem QA no dinheiro

- Data: 2026-11-13. Branch `feat/qa-modalidades-r3-20261113`.
- Base de trabalho:
  - `e9938fe` (R2 da apresentação, sobre `main` `5dde3d0`);
  - integrada por merge com `f0a2272` (SF-v1.5 preparada, branch local `feat/precificacao-bandeiras-fidelizacao-20261112`, nunca publicada).
- Migration nova: `supabase/migrations/20261113150000_commercial_qa_in_kind_settlement_modes_r3.sql`.
  - Preparatória, **não aplicada**.
  - Tem rollback em `supabase/rollback/20261113150000_…_rollback.sql`.
- **Production não foi alterado nem consultado nesta sessão.** O conector do Supabase falhou (HTTP 502). O estado de referência é a leitura somente-leitura anterior do mesmo dia:
  - regra 3 (SF-v1.4) `active`;
  - SF-v1.5 não aplicada;
  - 0 pedidos e 0 intenções;
  - checkout bloqueado no navegador.

  Precisa ser reconfirmado antes de qualquer aplicação (`supabase/ops/20261113_verificar_r3_somente_leitura.sql`).

## 1. Decisão comercial implementada

A QA existe **exclusivamente** para testes locais de benefícios diretos, com produtos da rede anunciante. Não existe QA em dinheiro. Na modalidade DINHEIRO não há testes com produtos, logo não há QA.

| | BENEFÍCIO DIRETO | DINHEIRO |
|---|---|---|
| Contraprestação dos participantes | em benefícios diretos (produtos) | em dinheiro, repassada pela SmallFlags |
| Parcela principal da SmallFlags | em dinheiro | em dinheiro |
| QA | só em produtos, para testes locais | **inexistente** (`qa_in_kind = qa_cash = 0`) |
| Dinheiro devido | parcela principal | valor total da modalidade |

## 2. Etapa 1 — matriz de regras

| Camada | Regra atual (antes da R3) | Regra desejada | Impacto | Correção |
|---|---|---|---|---|
| Regra de preço | QA é atributo da economia, igual nas duas modalidades | QA condicionada à modalidade | v4 herdava QA no dinheiro | `commercial_pricing_rules.qa_policy` (v4 = `in_kind_direct_benefits_only`; v1–v3 NULL) |
| Agenda | 1 linha por versão × categoria × fidelidade, com QA | composição por **modalidade** | dinheiro sem preço próprio | `commercial_settlement_terms` (versão × categoria × fidelidade × modalidade), CHECKs, escrita só em `prepared` |
| CHECK do pedido / intenção | `c*_financiamento_v14_coerente` vale para versão ≥ 3 (QA no dinheiro do benefício direto) | v3 histórica intacta; v4 com regra R3 | v4 cobraria a QA em dinheiro | v1.4 re-escopado para `= 3` (expressão idêntica); novos `c*_liquidacao_modalidade_v15` e `c*_liquidacao_v15_so_versao_4` |
| Gatilhos de autoridade | `c*_aplicar_autoridade_v14` resolvem v ≥ 3 pela agenda; aceitam snapshot "já resolvido" | v4 sempre pelos termos da modalidade; pedido = cópia exata da intenção | v4 podia nascer com QA monetária ou números do chamador | v14 deixa v ≥ 4; `cci/ceo_liquidar_modalidade_v15` resolvem, recalculam na troca de modalidade (rascunho) e recusam divergência |
| Imutabilidade | snapshot v1.4 protegido | composição por modalidade congelada | — | `ceo_liquidacao_v15_imutavel`; intenção: `liquidacao_congelada` |
| RPC de preço | blocos com QA dentro da remuneração | `qa_policy` + `settlement_modes` (direto / dinheiro ou `null`) | UI sem dados por modalidade | `calculate_niche_contract_pricing` + `commercial_settlement_public_v15`; v1–v3 byte a byte iguais |
| Pagamento manual | `admin_confirm_manual_bdflow_payment` confere v ≥ 3 contra a remuneração da SmallFlags | valor confirmado = total exigível do snapshot | **pedido em DINHEIRO marcado pago só com a remuneração** (contraprova, §6.3) | conferência pelo snapshot; gatilho `ceo_pagamento_confere_snapshot` na transição para `confirmed` (os três caminhos) |
| Tentativa no provedor | valor do snapshot (correto) | idem, imposto no banco | — | `cp_valor_confere_pedido` |
| Reutilização de bandeiras (A1) | intenção valida a inspeção; pedido copia sem revalidar | revalidar na criação e na confirmação | inspeção obsoleta ou conjunto retirado passavam | `ceo_revalidar_reutilizacao_bandeiras` (AFTER INSERT / transição para `confirmed`) |
| Ativação (A2–A6) | `UPDATE status` basta; pré-condições só no script de ops; catálogo apenas avisado | só pela função autorizada; pré-condições no gatilho | ativação prematura possível | `admin_activate_pricing_rule` + `commercial_pricing_activation_log` + `commercial_pricing_activation_preflight`; `cpr_protect` exige ambos |
| Instrumento (A6) | 1 modelo assinável por fidelidade, sem vínculo com a economia | modelo declara o modelo de liquidação | pedido v4 seria emitido com minuta v1.4 | `commercial_instrument_templates.settlement_model`; construtor recusa divergência e confere a composição |
| Autoatendimento | trava só no navegador | trava no banco | RPC direta reservava sob SF-v1.4 | `commercial_checkout_gate` (mínima 4) + `cci_portao_autoatendimento` |
| Front: parser | v ≥ 3 exige QA no dinheiro do direto; R2 aceitava só `qa_settlement_mode = cash` | v4 lê política e blocos por modalidade, com as mesmas invariantes do CHECK | — | `contractPricing.ts` (`interpretarModalidade`); chave R2 recusada |
| Front: modelo / guarda | contratável com QA "declarada" | contratável só com as **duas** modalidades definidas no servidor | — | `beneficiosAppPorOportunidade.ts`, `apresentacaoComercial.ts`, `pricingGateSF15.ts` |
| Front: apresentação | "as duas formas têm o mesmo valor total"; remuneração com QA (R$ 9.084,68) | igualdade só se o servidor publicar; parcela R$ 8.963,00 + QA R$ 121,68 em produtos | afirmava igualdade não decidida | `PainelPreco.tsx`, `OpportunityCard.tsx` (texto; layout R2 preservado) |
| Front: revisão | "inclusive a parcela de QA, continua devida em dinheiro" | QA em produtos; dinheiro sem QA | — | `RevisaoContratacao.tsx` |

## 3. Modelo de dados e correspondência

Colunas novas em `commercial_exclusivity_orders` e `commercial_checkout_intents` (NULL em toda linha histórica):
- `settlement_terms_id`;
- `qa_policy`;
- `mei_in_kind_cents`;
- `qa_in_kind_cents`;
- `qa_cash_cents`;
- `cash_adjustment_cents`.

Colunas antigas mantêm o nome e, na versão ≥ 4, têm significado declarado:

| Coluna antiga | Versão 3 (histórico) | Versão 4 (R3) |
|---|---|---|
| `smallflags_qa_cents` | QA monetária | QA em produtos (0 no dinheiro) |
| `smallflags_total_remuneration_cents` | principal + QA | remuneração **monetária** = principal |
| `contractual_pool_cents` / `user_pool_cents` | MEI + QA | MEI + QA em produtos |
| `bdflow_due_cents` / `bdflow_ops_investment_cents` | principal | principal + ajuste aprovado |
| `total_monetary_funding_required_cents` | direto: principal + QA; dinheiro: econômico | direto: principal; dinheiro: econômico da modalidade |

**Invariantes (CHECK + gatilho + parser):**
- **Benefício direto:**
  - `mei_in_kind = mei`;
  - `mei_cash = 0`;
  - `qa_cash = 0`;
  - `ajuste = 0`;
  - `econômico = mei + principal + qa_in_kind`;
  - `dinheiro = principal`.
- **Dinheiro:**
  - `qa_in_kind = qa_cash = 0`;
  - `mei_in_kind = 0`;
  - `mei_cash = mei`;
  - `econômico = mei + principal + ajuste`;
  - `dinheiro = econômico`.
- **Sempre:** `econômico = pool + devido`, e a parcela principal é a da agenda nas duas modalidades. A QA nunca vira remuneração por inferência.
- **Ajuste (`cash_adjustment_cents`):** só no dinheiro, só com fundamento (≥ 20 caracteres). É o lugar do Cenário B. Nunca é QA renomeada.

## 4. Etapa 2 — o que foi implementado sem depender do preço

- **Termos do BENEFÍCIO DIRETO da versão 4** gravados, derivados da agenda preparada, sem número novo.
- **Termos do DINHEIRO da versão 4 não gravados.** Sem eles:
  - a pré-verificação reprova;
  - a ativação é recusada;
  - nenhuma reserva ou venda em dinheiro nasce na v4.
- **Ativação:** `admin_activate_pricing_rule(versao, referencia)` é o único caminho. O gatilho exige registro na mesma transação e pré-verificação aprovada:
  - termos das duas modalidades;
  - minutas assináveis com `settlement_model`;
  - catálogo de atividades da economia para todas as posições;
  - travas ligadas;
  - nenhuma reserva viva.
- **Superar a versão vigente** também só ocorre dentro de uma ativação registrada.
- **Script de ops `20261112_ativar_precificacao_sf_v15.sql`:** passa a chamar a função.
- **Cenários A e B:** prontos em `supabase/ops/20261113_sf_v15_dinheiro_cenario_{a,b}.sql`, exigindo decisão e referência. O B exige ainda fundamento, e recusa fundamento que mencione QA.

## 5. Etapa 3 — os dois cenários do DINHEIRO (nenhum aprovado)

| Condição | Valor com benefício direto | Participantes | Parcela SmallFlags (dinheiro) | QA em produtos (direto) | Dinheiro devido (direto) | Obrigação não monetária (direto) | **DINHEIRO — Cenário A** | **DINHEIRO — Cenário B** | Diferença A × B |
|---|---|---|---|---|---|---|---|---|---|
| Supermercado, novo | R$ 32.939,00 | R$ 23.854,32 | R$ 8.963,00 | R$ 121,68 | R$ 8.963,00 | R$ 23.854,32 em benefícios + R$ 121,68 em produtos | R$ 32.817,32 | R$ 32.939,00 (ajuste R$ 121,68) | R$ 121,68 |
| Supermercado, fidelizado | R$ 28.176,00 | R$ 23.854,32 | R$ 4.200,00 | R$ 121,68 | R$ 4.200,00 | idem | R$ 28.054,32 | R$ 28.176,00 (ajuste R$ 121,68) | R$ 121,68 |
| Demais, novo | R$ 22.939,00 | R$ 11.927,16 | R$ 10.951,00 | R$ 60,84 | R$ 10.951,00 | R$ 11.927,16 + R$ 60,84 em produtos | R$ 22.878,16 | R$ 22.939,00 (ajuste R$ 60,84) | R$ 60,84 |
| Demais, fidelizado | R$ 16.188,00 | R$ 11.927,16 | R$ 4.200,00 | R$ 60,84 | R$ 4.200,00 | idem | R$ 16.127,16 | R$ 16.188,00 (ajuste R$ 60,84) | R$ 60,84 |

- **DINHEIRO, nos dois cenários:**
  - QA = 0;
  - participantes financiados em dinheiro (23.854,32 / 11.927,16);
  - parcela principal igual à do benefício direto;
  - dinheiro devido = valor total da modalidade.
- **Antes da R3:** o dinheiro devido no benefício direto era 9.084,68 / 4.321,68 / 11.011,84 / 4.260,84 (QA cobrada em dinheiro). Agora é 8.963,00 / 4.200,00 / 10.951,00 / 4.200,00.
- **Formação com seis novos (referência interna; o site não publica somas):**
  - benefício direto R$ 147.634,00, dos quais R$ 63.718,00 em dinheiro e R$ 425,88 de QA em produtos;
  - DINHEIRO A R$ 147.208,12; B R$ 147.634,00.

**Efeitos:**
- **Checkout:**
  - o banco cobra o total do snapshot da modalidade;
  - no Cenário A, o valor exibido em destaque (benefício direto) difere do valor do DINHEIRO; a interface mostra o valor de cada forma e deixa de afirmar a igualdade;
  - no B, a igualdade volta a ser afirmada, porque o servidor a publica.
- **Contratos:**
  - a minuta SF-v1.5 precisa redigir a QA em produtos só no benefício direto e a ausência de QA no dinheiro;
  - no Cenário B, precisa também nomear e fundamentar o componente;
  - nenhuma minuta foi alterada; o banco exige `settlement_model` na minuta.
- **Impostos e documentação fiscal — validação contábil necessária, não decidida aqui:**
  - no Cenário B, a natureza do componente para fins de NFS-e;
  - o tratamento dos produtos de QA fornecidos pela anunciante para testes;
  - o tratamento dos repasses aos participantes no DINHEIRO.
- **Documentação:** Termos do Pedido, FAQ e material comercial devem refletir a regra R3.

**Recomendação técnica (não é decisão):** o **Cenário A** é o mais consistente com a regra.
- Fecha sem componente novo: `econômico = participantes + principal`.
- Mantém a invariante de que nenhuma obrigação inexistente integra o preço.
- Não exige justificar um valor sem contrapartida.
- Custo: valores diferentes entre as formas, que a interface já apresenta corretamente.

O Cenário B exige fundamento contratual e fiscal próprio para o componente. Sem ele, o banco o recusa.

## 6. Testes e evidências

### 6.1 SQL (PostgreSQL 16.15 e 17.6, harness local)

| Suíte | Base (`a8f5e51`) | R3 |
|---|---|---|
| `290_flag_production_pricing_sf_v15` | 92 PASS / 0 FAIL | **93 PASS / 0 FAIL** (ativação autorizada; números da QA conforme R3) |
| `295_qa_modalidades_r3` (nova) | — | **69 PASS / 0 FAIL** |
| Demais 24 suítes | 15 já falhavam na base (fixtures pré-existentes) | as **mesmas 15**, no mesmo ponto e com as mesmas contagens; nenhuma regressão |

Resultados idênticos em PG16 e PG17. Ensaio de upgrade e rollback (`scripts/db-test/r3-upgrade-check.sh`): **25 PASS / 0 FAIL** em PG16 e PG17.
- Histórico (SF-v1.4, preço público, cálculo v1–v3, documentos, catálogo, fidelidade) idêntico.
- 7 funções estendidas com ACL e atributos preservados.
- Rollback devolve o catálogo idêntico (1911 linhas).
- Rollback recusado depois de uma ativação.

### 6.2 Requisitos da missão × prova

| Requisito | Prova |
|---|---|
| Benefício direto com QA em produtos só após configuração válida | 295: preparada não reserva; política ausente recusa termos; ativação só com pré-requisitos |
| Benefício direto com QA em dinheiro rejeitado na v4 | 295: `cst_beneficio_direto`, `cst_sem_qa_em_dinheiro`, `cci_liquidacao_modalidade_v15` (gatilho desligado) |
| DINHEIRO com QA monetária ≠ 0 rejeitado | 295: `cst_sem_qa_em_dinheiro` |
| DINHEIRO com QA em produtos ≠ 0 rejeitado | 295: `cst_dinheiro`; `ceo_liquidacao_modalidade_v15` (gatilho desligado) |
| Contraprestação mantida nas duas modalidades | 295: reserva direta (`mei_in_kind` 23.854,32) e em dinheiro (`mei_cash` 11.927,16) |
| Nenhum centavo duas vezes; econômico fecha em centavos | 295: `econômico = mei + principal + qa_in_kind + ajuste = pool + devido` |
| Pagamento = snapshot; manual insuficiente rejeitado; provedor = admin | 295: confirmação só com a remuneração e com 1 centavo a menos recusadas; tentativa no provedor recusada; esperado manual = valor da tentativa |
| Troca de modalidade só recalculando e congelando | 295: recálculo pelos termos; alteração de valor recusada; fora do rascunho recusada |
| Pedido sem modalidade compatível | 295: v4 sem modalidade; v3 com campos R3; troca de modalidade no pedido |
| SF-v1.4 inalterada | 295: md5 do preço público = Production; md5 do cálculo v3 antes/depois da ativação; ensaio P2 |
| v4 sem configuração não ativa; UPDATE privilegiado não contorna | 295: A2/A3/A4; registro forjado com trava de pagamento desligada recusado |
| Inspeção obsoleta não reutiliza | 295: inspeção mais nova reprovando; conjunto retirado antes do pedido e antes do pagamento |
| RPC direta não contorna a trava | 295: reserva sob SF-v1.4 recusada no banco (`checkout_bloqueado`) |
| Frontend rejeita resposta inconsistente | Vitest: 12 variações de resposta v4 incoerente → sem valores e sem link de checkout |
| Valores fecham para novos e fidelizados | 295 (direto e Cenário A); Vitest (fixtures A e B do banco local) |

### 6.3 Contraprova do pagamento manual (base × R3)

`scripts/db-test/r3-pagamento-manual-contraprova.sql`, com o mesmo roteiro nos dois bancos (transação revertida). Pedido SF-v1.4 em DINHEIRO na farmácia, com exigível de R$ 19.999,00, confirmado só com a remuneração (R$ 8.071,84):
- **base:** `{"ok": true}`, pedido `confirmed` com R$ 8.071,84 pagos;
- **R3:** `{"ok": false, "reason": "amount_differs_from_due", "expected_cents": 1999900}`, pedido continua `pending`.

### 6.4 Frontend

`npm run validate` (verificação de legado, typecheck, Vitest, build e worker): resultado no relatório de entrega. Capturas em `r3-entrega/capturas/`:
- prévia atual;
- v4 Cenário A e B (sintéticos do banco local);
- celular com 390 px, sem rolagem horizontal.

## 7. Riscos remanescentes

1. **Production não reconfirmado nesta sessão** (Supabase 502).
2. **Superusuário ainda tem bypass.** Ele pode desligar gatilhos ou forjar o registro de ativação. A pré-verificação detecta trava desligada **no momento da ativação**, e o registro forjado não dispensa as pré-condições. Desligar depois da ativação não é detectado em tempo real: o script de verificação somente-leitura o aponta.
3. **Venda manual administrativa sob a SF-v1.4 não passa pelo portão do autoatendimento.** A decisão está abaixo. Pagamentos manuais, porém, passam a conferir o snapshot.
4. **Caminho manual V1/V2 mudou.** A confirmação manual de pedidos antigos em DINHEIRO passa a exigir o total do snapshot, em vez do devido operacional. Production tem 0 pedidos.
5. **Cumprimento da QA sem modelo no banco.** "Produtos efetivamente disponibilizados + evidência válida do teste" não tem modelo de dados. É um processo do App/operação, que não foi alterado sem aprovação.
6. **Coluna `smallflags_qa_cents` muda de significado entre v3 e v4.** A correspondência está declarada (§3), e consumidores novos devem usar `qa_in_kind_cents` / `qa_cash_cents`.
7. **`get_public_formation_economics` continua somando a agenda.** Na v4, isso é a composição do benefício direto. Não é exibido no site.
8. **Suítes SQL pré-existentes falhando (15).** São fixtures da base, fora do escopo, registradas para correção própria.

## 8. Decisões ainda necessárias

1. **Preço da modalidade DINHEIRO na SF-v1.5:** Cenário A ou B. No B, a natureza e o fundamento contratual e fiscal do componente.
2. **Redação jurídica da minuta SF-v1.5:** QA em produtos só no benefício direto; DINHEIRO sem QA. Depois, as minutas assináveis com `settlement_model`.
3. **Catálogo de atividades SF-v1.5** aprovado para as posições.
4. **Ativação da SF-v1.5 sem DINHEIRO?** Decidir se ela pode ocorrer só com o benefício direto. Hoje o banco exige as duas modalidades.
5. **Venda manual administrativa sob a SF-v1.4:** bloquear também, ou manter para registro de contratos presenciais.
6. **QA no App:** usuário autorizado, evidência do teste e consequência da não entrega dos produtos.
7. **Validação contábil:** QA em produtos, repasses no DINHEIRO e, se houver, o componente do Cenário B.
8. **Aplicação das migrations** (SF-v1.5 e R3) em Production e merge — não autorizados nesta missão.
