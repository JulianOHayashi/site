# R4.2.1: proposta de schema para a prontidão da alteração de arte

- Data: 2026-11-16.
- **Proposta. Nada aqui foi implementado.**
- O que foi implementado é o **bloqueio seguro**. `commercial_artwork_change_readiness` responde sempre `ready = false`, com três fatos ausentes:
  - `billing_authorization_fact_not_available`
  - `production_execution_fact_not_available`
  - `new_flag_set_fact_not_available`
- Para trocar o bloqueio por esta proposta é preciso:
  - a decisão comercial dos pontos em aberto da seção 3;
  - uma migration nova;
  - um manifesto novo.

## 1. Por que a autorização não basta

`production_authorized` registra que o administrador **permitiu iniciar** a fabricação. Isso não prova três coisas:

1. que a rubrica do parceiro foi cobrada ou autorizada conforme o fluxo comercial;
2. que o fornecedor fabricou e entregou as peças;
3. que existe um conjunto físico apto, inspecionado, com a arte nova, para a próxima campanha.

Na R4.2, a autorização sozinha liberava a renovação fidelizada com `flag_production_new_units = 0`. A contraprova X1 mostra isso.

## 2. Fatos propostos (append-only, gravados pelo servidor)

| Fato | Tabela proposta | Campos mínimos | Quem grava |
|---|---|---|---|
| Cobrança da rubrica | `commercial_artwork_change_charges` | `request_id`, `accepted_quote_id`, `amount_cents` (= `accepted_total_cents`), `status` (`authorized` → `paid` / `refunded`), `provider_reference`, `confirmed_at` e `confirmed_source` | Webhook do provedor ou confirmação manual auditada, no mesmo padrão de `commercial_payments` |
| Execução da produção | `commercial_artwork_change_production_receipts` | `request_id`, `supplier_delivery_document` (bucket privado, **atestado** como o orçamento), `pieces_delivered`, `delivered_at`, `received_by` | Administrador registra; o SHA-256 é atestado pelo servidor |
| Conjunto novo | `commercial_flag_sets` com `origin_artwork_change_request_id` (hoje o conjunto exige um pedido de origem com produção > 0) e a inspeção em `commercial_flag_set_inspections` | Conjunto ligado à solicitação; inspeção aprovando todas as peças | Administrador e conferente, como nas inspeções da SF-v1.5 |

A prontidão passaria a ser verdadeira só com:

- cobrança no estado exigido pela decisão comercial;
- recibo de entrega atestado, com `pieces_delivered ≥ pieces_count` do orçamento aceito;
- conjunto da solicitação ainda não consumido, com inspeção aprovada.

O gatilho de pedido revalidaria esses fatos na confirmação do pagamento do pedido de renovação, como `ceo_revalidar_reutilizacao_bandeiras` já faz para a reutilização.

## 3. Decisões comerciais que faltam (não inventadas aqui)

1. **Momento da cobrança.** A rubrica é paga antes de fabricar, antes da renovação ou junto com o pedido da renovação? É Pix, cartão ou cobrança separada?
2. **Prova de execução.** Basta o comprovante de entrega do fornecedor ou é exigida inspeção do conjunto novo?
3. **Campanha alvo perdida.** O que acontece com uma alteração autorizada (e talvez paga) quando:
   - o pedido da campanha alvo é cancelado;
   - a campanha é adjudicada a outra empresa;
   - o parceiro não renova?

   As saídas possíveis são reembolso, transferência para a campanha seguinte ou perda.

   Hoje a alteração não migra para outra campanha. As suítes 299 e X2 testam isso.
4. **Custos fora da fabricação.** Matriz, setup, frete, embalagem e instalação são recusados como itens até haver decisão própria (`quote_item_kind_not_allowed`).

## 4. Impacto técnico estimado

- Uma migration com três fatos, a mudança da prontidão e a revalidação na confirmação do pagamento.
- Manifesto novo (R4.2.2 ou posterior).
- Contraprovas e upgrade/rollback no padrão R4.1, R4.2 e R4.2.1.
- No site: a exibição do estado da cobrança e da entrega na página da solicitação.
