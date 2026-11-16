# QA em produtos no benefício direto — análise técnica (R2, A2)

> **SUPERADA pela R3 (13/11/2026).** A decisão comercial foi registrada: QA só
> em produtos no benefício direto e inexistente no dinheiro. A implementação
> está em `QA_MODALIDADES_R3_20261113.md` e na migration `20261113150000`.
> Este documento fica como registro histórico da análise.

- Data: 2026-11-13. Branch `feat/oportunidades-apresentacao-comercial-20261113`.
- **Documento de análise. Nada aqui foi implementado no backend.** A
  alternativa jurídica (QA em produtos) depende de aprovação comercial e
  jurídica. Nenhum preço, contrato, agenda, migration aplicada ou dado de
  Production foi alterado.
- Fonte contratual: pedido presencial `SF-0001` v1.5. Segundo a auditoria do
  usuário, a **cláusula 6.2** prevê, na modalidade de benefício direto, a
  parcela QA cumprida **em produtos**. Observação: nesta sessão o PDF não aparece
  na ferramenta de biblioteca do projeto (`files: []`). A cláusula foi
  registrada conforme o relato do usuário, sem transcrição literal.

## 1. A divergência, em uma linha

O backend vigente (P0-3) cobra **em dinheiro**, no benefício direto, a
remuneração inteira da SmallFlags, com a QA incluída. A SF-0001 v1.5 (cl. 6.2)
manda cumprir a QA **em produtos**. O valor total é o mesmo nas duas leituras.
Muda só o dinheiro devido no benefício direto: R$ 121,68 no Supermercado e
R$ 60,84 em cada posição comum, por contrato.

## 2. Onde a regra atual está codificada

| Camada | Local | Regra hoje (QA em dinheiro) |
|---|---|---|
| Agenda | `commercial_pricing_schedule` (`20261007120000`) | valores por versão, categoria e fidelidade; sem forma de liquidação da QA |
| CHECK do pedido | `ceo_financiamento_v14_coerente` (`20261007120000` §5.2) | `pricing_rule_version >= 3` + `direct_benefits` ⇒ `total_monetary_funding_required_cents = smallflags_total_remuneration_cents` |
| CHECK da intenção | `cci_financiamento_v14_coerente` (idem) | mesma regra na intenção de checkout |
| Gatilhos | `ceo_aplicar_autoridade_v14`, `cci_aplicar_autoridade_v14` | no `direct_benefits`: `total_monetary := smallflags_total_remuneration_cents` |
| RPC pública | `calculate_niche_contract_pricing` (última: `20261103120000`; SF-v1.5: `20261112120000`) | `funding_direct_benefits_cents = smallflags_total_remuneration_cents`; `direct_benefit_deliverable_cents = mei_consideration_cents` |
| Pagamento (provedor) | `open_commercial_payment_attempt`, `prov_confirm_commercial_payment` (`20260917120000`) | cobra e confere `total_monetary_funding_required_cents` do snapshot |
| Pagamento (manual) | `admin_confirm_manual_bdflow_payment` (`20261007130000`) | para `v >= 3`, confere contra `smallflags_total_remuneration_cents` |
| Snapshot e instrumento | `20261007170000`, `20261007190000` | copiam `smallflags_qa_cents` e a decomposição; não registram a forma de liquidação da QA |
| Front: parser | `src/domain/pricing/contractPricing.ts` (`interpretarBloco`) | `versao >= 3` ⇒ `fundingDirect === remun` e `entregavel === mei` |
| Front: apresentação | `src/domain/pricing/beneficiosAppPorOportunidade.ts` (`validaBloco`) | `fundingDirectBenefitsCents === smallflagsTotalRemunerationCents` |
| Front: revisão | `src/pages/RevisaoContratacao.tsx` | texto: "inclusive a parcela de QA, continua devida em dinheiro" |
| Testes SQL | `supabase/tests/240_commercial_pricing_v14.sql`; `290_…sf_v15.sql` (branch SF-v1.5) | asseguram a regra acima |

## 3. O que o R2 já fez no Site (A1)

- O servidor passa a ser a única fonte da liquidação da QA: o parser lê a chave
  opcional `qa_settlement_mode` de cada bloco (`founding`, `fidelized`).
  - Ausente ou `null`: liquidação **pendente**.
  - `"cash"`: aceito só com decomposição v1.4+. A invariante existente já exige
    a QA dentro do dinheiro do benefício direto.
  - `"in_kind"` ou qualquer outro valor: **falha fechada**, sem valores. O site
    não sabe validar QA em produtos.
- `apresentacaoOportunidade().contratavel` = versão vigente **e** `"cash"`
  declarado nas duas condições.
- `permiteCheckoutSF15` (guarda do checkout) usa o mesmo critério nas seis
  posições.
- A constante do navegador `QA_BENEFICIO_DIRETO_CONCILIADA` foi removida.
- Hoje nenhuma RPC devolve `qa_settlement_mode`. Por isso, mesmo que a versão 4
  seja ativada sem a mudança de backend da §4, o site **não** oferece
  contratação e a guarda do checkout não abre.
- Isso protege o Site. Sozinho, **não** protege chamadas diretas às RPCs de
  intenção; para isso existe a §4.

## 4. Trava de backend necessária antes de ativar a SF-v1.5 (vale para qualquer decisão)

Deve ir na migration SF-v1.5, que **ainda não foi aplicada** (branch
`feat/precificacao-bandeiras-fidelizacao-20261112`, arquivo
`20261112120000_commercial_flag_production_pricing_sf_v15.sql`), ou numa
migration logo depois dela, antes de qualquer ativação. É um rascunho e não foi
executado:

```sql
-- 4.1 Fato por versão. v1..v3 ficam NULL: histórico intocado
--     (ADD COLUMN sem DEFAULT não reescreve linhas nem dispara gatilhos).
ALTER TABLE public.commercial_pricing_rules
  ADD COLUMN qa_settlement_mode text NULL
  CONSTRAINT cpr_qa_settlement_mode_valido
    CHECK (qa_settlement_mode IN ('cash', 'in_kind'));

-- 4.2 Gatilho de ativação: em commercial_pricing_rules_protect(),
--     no ramo prepared -> active.
IF OLD.status = 'prepared' AND NEW.status = 'active' AND NEW.version >= 4 THEN
  IF NEW.qa_settlement_mode IS NULL THEN
    RAISE EXCEPTION 'ativacao_qa_pendente: versao % sem liquidacao da QA declarada',
      NEW.version USING ERRCODE = 'check_violation';
  END IF;
  IF NEW.qa_settlement_mode <> 'cash' THEN   -- in_kind: sem implementação aprovada
    RAISE EXCEPTION 'ativacao_qa_nao_suportada: %', NEW.qa_settlement_mode
      USING ERRCODE = 'check_violation';
  END IF;
END IF;
-- O valor precisa ser gravado enquanto a regra está 'prepared'. A comparação
-- to_jsonb(NEW) - status - effective_from já impede mudá-lo na transição e depois.

-- 4.3 Defesa em profundidade: cci_aplicar_autoridade_v14 e
--     ceo_aplicar_autoridade_v14 recusam versao >= 4 cuja regra tenha
--     qa_settlement_mode NULL ou não suportado
--     (ERRCODE check_violation, 'liquidacao_qa_pendente').

-- 4.4 calculate_niche_contract_pricing (ramo explicit_schedule):
--     'qa_settlement_mode', v_rule.qa_settlement_mode
--     (a SF-v1.4 continua devolvendo NULL: o Site a trata como pendente,
--      o que só afeta a prévia, já não contratável).

-- 4.5 Script de ativação supabase/ops/20261112_ativar_precificacao_sf_v15.sql:
--     a mesma pré-condição, com mensagem própria, antes do UPDATE de status.
```

Testes negativos exigidos na suíte 290:
- ativar a versão 4 com o modo `NULL` falha;
- ativar com `in_kind` falha;
- alterar o modo depois de `active` falha;
- intenção sob a versão 4 sem modo falha;
- a RPC devolve a chave;
- a resposta da versão 3 é idêntica byte a byte (md5 do jsonb antes e depois).

## 5. Caminho B — QA em dinheiro (segue o backend)

- **Técnico:** só a §4, com `qa_settlement_mode = 'cash'` gravado na versão 4
  antes da ativação. CHECKs, gatilhos, pagamentos e front ficam como estão.
- **Jurídico:** a cl. 6.2 do SF-0001 v1.5 contradiz esta leitura. O modelo
  presencial e os Termos do Pedido teriam de ser revistos para dizer que, no
  benefício direto, a QA é paga em dinheiro com a parcela principal. **Não feito:
  depende de aprovação.**

## 6. Caminho A — QA em produtos (segue a SF-0001, cl. 6.2) — não implementado

Tudo o que muda, preservando a SF-v1.4 (versão 3) sem nenhuma alteração de
linha ou de semântica:

1. **Fato por versão:** `qa_settlement_mode = 'in_kind'` na versão 4 (§4.1), e
   a §4.2 passa a aceitar `in_kind`.
2. **Snapshot por pedido e intenção:** novas colunas
   - `qa_settlement_mode`, copiada da regra pelo gatilho;
   - `qa_in_kind_cents`: `= smallflags_qa_cents` no `direct_benefits` +
     `in_kind`; `0` nos demais casos.

   Um CHECK não consulta outra tabela, então o fato precisa estar na própria
   linha.
3. **CHECKs versionados** (nova migration; os arquivos históricos não mudam):
   - `ceo/cci_financiamento_v14_coerente` são recriados com o escopo
     `pricing_rule_version >= 3 AND qa_settlement_mode IS DISTINCT FROM 'in_kind'`.
     Com isso, a versão 3 e o `cash` continuam com a mesma regra.
   - Novo `ceo/cci_financiamento_qa_in_kind`, para `direct_benefits` + `in_kind`:
     - `mei_cash_funding_cents = 0`;
     - `qa_in_kind_cents = smallflags_qa_cents`;
     - `total_monetary_funding_required_cents = smallflags_main_fee_cents`.
   - No `cash`, mesmo com `in_kind` na regra: igual a hoje
     (`total_monetary = economic_value_cents`, `qa_in_kind_cents = 0`).
   - Use `NOT VALID` seguido de `VALIDATE`. Hoje há 0 pedidos e 0 intenções.
4. **Gatilhos `ceo/cci_aplicar_autoridade_v14`:** no ramo `direct_benefits`, se a
   regra for `in_kind`, `total_monetary := smallflags_main_fee_cents` e
   `qa_in_kind_cents := smallflags_qa_cents`. Os ramos da versão 3 ficam
   inalterados.
5. **RPC pública e de cálculo:**
   - `funding_direct_benefits_cents = smallflags_main_fee_cents`;
   - `direct_benefit_deliverable_cents = mei_consideration_cents` (só a parte
     dos participantes);
   - nova chave `qa_in_kind_deliverable_cents = smallflags_qa_cents`.

   A QA nunca se soma à parcela dos participantes. Nova invariante:
   `funding_direct + deliverable + qa_in_kind = economic`.
6. **Pagamentos:**
   - O caminho do provedor não muda, porque lê o snapshot.
   - `admin_confirm_manual_bdflow_payment` precisa conferir contra
     `smallflags_main_fee_cents` quando `direct_benefits` + `in_kind`. Hoje
     confere contra a remuneração inteira e cobraria a QA a mais.
7. **Instrumento e modelos:**
   - a autoridade do snapshot (`20261007190000`) e o modelo do instrumento
     (`20261007170000`) passam a carregar `qa_settlement_mode` e
     `qa_in_kind_cents`;
   - o modelo SF-v1.5 precisa da redação da cl. 6.2 (texto jurídico, **sujeito a
     aprovação**);
   - o catálogo de atividades SF-v1.5 continua pendente, como já registrado no
     relatório da SF-v1.5.
8. **App e operação:** antes de qualquer contrato `in_kind`, é preciso definir:
   - quem é o "usuário autorizado" dos testes locais de QA;
   - como o recebimento dos produtos é confirmado e registrado como evidência;
   - o que acontece se os produtos não forem entregues (cobrança em dinheiro?
     prazo?), o que é uma decisão contratual.

   Sem confirmação no App, a QA em produtos vira uma obrigação que ninguém
   verifica.
9. **Front:**
   - `contractPricing.ts`: aceitar `in_kind` só com versão ≥ 4, decomposição,
     `fundingDirect === taxa`, `entregavel === mei` e
     `qa_in_kind_deliverable_cents === qa`; continuar recusando
     `in_kind` + `fundingDirect === remun`;
   - `beneficiosAppPorOportunidade.validaBloco`: escolher o ramo de
     `fundingDirectBenefitsCents` conforme o modo;
   - `pricingGateSF15.liquidacaoQaDeclarada`: aceitar `in_kind`;
   - `RevisaoContratacao.tsx`: a frase "inclusive a parcela de QA, continua
     devida em dinheiro" passa a depender do modo;
   - `PainelPreco`: com o modo declarado, a página pode informar o valor em
     dinheiro do benefício direto vindo do servidor.
10. **Testes:**
    - a suíte 240 roda sem mudança, como regressão da SF-v1.4;
    - a suíte 290 ganha os casos `in_kind`;
    - nova suíte para os CHECKs versionados, com negativos: `in_kind` cobrando
      a QA em dinheiro, `cash` com `qa_in_kind_cents > 0`, versão 3 com
      `in_kind`, conferência manual com o valor antigo.

**Preservação da SF-v1.4:**
- a versão 3 mantém `qa_settlement_mode` NULL;
- nenhuma linha histórica recebe UPDATE;
- os CHECKs recriados mantêm, para a versão 3, a mesma expressão lógica;
- a prova é o md5 das respostas da versão 3 antes e depois e a suíte 240
  inalterada.

## 7. Diferença financeira (dinheiro devido no benefício direto, por contrato)

| Versão / condição | Valor total | Hoje (QA em dinheiro) | SF-0001 cl. 6.2 (QA em produtos) | Diferença |
|---|---|---|---|---|
| SF-v1.5 Supermercado, novo | R$ 32.939,00 | R$ 9.084,68 | R$ 8.963,00 + R$ 121,68 em produtos | R$ 121,68 |
| SF-v1.5 Supermercado, fidelizado | R$ 28.176,00 | R$ 4.321,68 | R$ 4.200,00 + R$ 121,68 em produtos | R$ 121,68 |
| SF-v1.5 comum, novo | R$ 22.939,00 | R$ 11.011,84 | R$ 10.951,00 + R$ 60,84 em produtos | R$ 60,84 |
| SF-v1.5 comum, fidelizado | R$ 16.188,00 | R$ 4.260,84 | R$ 4.200,00 + R$ 60,84 em produtos | R$ 60,84 |
| SF-v1.4 Supermercado, novo (vigente) | R$ 29.999,00 | R$ 6.144,68 | — (histórico preservado) | — |
| SF-v1.4 comum, novo (vigente) | R$ 19.999,00 | R$ 8.071,84 | — (histórico preservado) | — |
| Formação SF-v1.5, seis novos | R$ 147.634,00 | R$ 64.143,88 | R$ 63.718,00 + R$ 425,88 em produtos | R$ 425,88 |

Na modalidade dinheiro não há divergência: paga-se o valor total.

## 8. Observação fora do escopo, para conferência

`admin_confirm_manual_bdflow_payment` (`20261007130000`), no `cash` sob a
versão 3 ou superior, confere contra a remuneração da SmallFlags, com o
comentário "a SmallFlags NÃO custodia o pool". O caminho do provedor cobra
`total_monetary = economic_value_cents`, e a página diz que, no dinheiro, "a
SmallFlags administra os repasses". Convém confirmar qual caminho é o correto
antes da ativação. Nada foi alterado.

## 9. Decisão pendente

1. **A ou B:** leitura da QA na SF-v1.5. É uma decisão jurídica e comercial.
2. Em qualquer caso, a trava da §4 vai para a migration SF-v1.5 antes da
   ativação.

Até lá, o Site mantém a contratação bloqueada. Hoje isso acontece por dois
motivos: a versão 3 está vigente e a liquidação da QA não foi declarada.
