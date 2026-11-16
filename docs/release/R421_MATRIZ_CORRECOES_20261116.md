# R4.2.1: matriz problema → prova → correção → teste

- Base: R4.2 `89363db` (implementação `20adbce`).
- Correção: migration `20261116180000_commercial_artwork_change_integrity_r421.sql`. É preparatória e **não foi aplicada**.
- Fonte dos problemas: `AUDITORIA_INDEPENDENTE_R42_SMALLFLAGS_20261116.md` e a missão R4.2.1.
- Os quatro documentos originais de decisão **continuam indisponíveis** nesta sessão. O zip citado não chegou. Só foram usadas as regras repetidas na missão e na auditoria:
  - `AUDITORIA_CRUZADA_SMALLFLAGS_R41_E_DECISOES_20261115.md`
  - `DECISAO_COMERCIAL_SITE_SF15_CENARIO_A_20261115.md`
  - `BDFLOW_SITE_DECISAO_ALTERACAO_ARTE_FIDELIZADO_20261115_V2.md`
  - `BDFLOW_SITE_QA_RESPONSAVEIS_APROVADOS_PRAZOS_PROPOSTOS_20261115.md`

## Matriz

| # | Problema (auditoria) | Prova na R4.2 (contraprova) | Correção R4.2.1 | Testes |
|---|---|---|---|---|
| P1-1 | `production_authorized` habilitava a renovação fidelizada sem reutilização, sem cobrança nem fabricação | **X1:** reserva fidelizada `ok: true` apoiada só na autorização | `commercial_artwork_change_readiness` sempre falsa, com 3 fatos ausentes (bloqueio seguro); `commercial_artwork_change_renewal_state` usada na reserva e nos gatilhos de intenção e de pedido; solicitação **pendente** para a campanha também bloqueia. Proposta de schema: `R421_PROPOSTA_PRONTIDAO_ALTERACAO_ARTE.md` | 299 (DINHEIRO, benefício direto, intenção direta, pendente, depois de cancelada); 298 (reserva e venda manual recusadas); X1 R4.2.1 |
| P1-2 | `next_campaign` sem vínculo com uma exclusividade; aplicável a qualquer campanha futura | **X2:** pedido duas campanhas depois usa a alteração | Colunas `base_exclusivity_id`, `target_region_id` e `target_sequence_number`, derivadas no servidor (base + 1) e imutáveis; uma viva por empresa, identidade e campanha (índice); pedido base deve ser o mais recente (`base_order_not_latest`); campanha adjudicada a outra empresa recusada (`target_campaign_unavailable`); trava por empresa e identidade | 299 (derivação, imutabilidade, duas campanhas depois, campanha certa, pedido alvo cancelado não migra, base antiga, adjudicada); `r421-concorrencia.sh` C1–C3; X2 R4.2.1 |
| P1-3 | Tabelas, gatilhos e RPCs novos fora do catálogo das guardas | **X3:** gatilho desabilitado, função trocada, índice removido e coluna gerada desfeita → integridade vazia e verificador R4.2 todo `true` | Catálogo v2 (`smallflags-guard-catalog/2`): 19 tabelas, cada uma com colunas, restrições, índices, RLS, permissões e políticas; 64 gatilhos; 85 funções (as RPCs da alteração de arte e os auxiliares de autorização); Storage (os 2 buckets e as 6 políticas). Manifesto **R4.2.1** `812e47cd…e98e662f`, idêntico em PG16 e PG17; R4.1 e R4.2 preservados. Verificador `20261116_verificar_r421_somente_leitura.sql` | 299 (15 checagens P1-3: 12 adulterações detectadas, pré-verificação da ativação, cobertura, integridade após reverter); X3 R4.2.1; verificador nos dois PG |
| P1-4 | Custo só **declarado**: SHA-256 e total informados pelo administrador; sem conferir peças × unitário | **X4:** orçamento com total 1.500,00 = 40 × 35,00 (que dá 1.400,00) e SHA-256 de documento inexistente aceito | Bucket privado `supplier-quote-documents` (sem UPDATE/DELETE); documento registrado com metadados do Storage; **atestado** só por `service_role` (o núcleo `supplierDocumentAttestation.ts` baixa os bytes e calcula o SHA-256); orçamento itemizado (`flag_pieces`: quantidade × unitário = linha; soma = total; peças = soma das quantidades; preço não linear = vários itens); conciliação no fim da transação; aceite exige o SHA-256 do documento e o objeto inalterado; RPC declarada removida | 299 (23 checagens P1-4: total, item, documento, atestado, objeto trocado, rubrica não autorizada, gravação direta, Storage); Vitest do atestado (9) e da página (17); X4 R4.2.1 |

## Mudanças de expectativa na suíte 298 (R4.2), todas intencionais

| Checagem da 298 | R4.2 | R4.2.1 | Motivo |
|---|---|---|---|
| Estado de partida | manifesto vigente = R4.2 | R4.2 gravado e vigente íntegro | Há um manifesto novo (P1-3) |
| Orçamento sem SHA-256 | `supplier_document_required` | `invalid_sha256` (já no registro do documento) | P1-4 |
| Orçamentos e aceites | RPC declarada | `pg_temp.orcar` / `pg_temp.aceitar`: documento atestado, itens, SHA no aceite | P1-4 |
| Renovação com alteração autorizada | aceita | **recusada** (`artwork_change_not_ready`) na reserva e na venda manual; o caminho "pronta" é exercitado com **prontidão simulada** (fixture `[QA FICTICIO]`, savepoint revertido) | P1-1 |
| Alteração da campanha atual × renovação | `commercial_artwork_change_for_renewal` | `commercial_artwork_change_renewal_state(..., exclusividade k=1)` | Resolvedor sem campanha removido (P1-2) |
| Cancelamento: nova solicitação para o mesmo pedido | aberta (empresa 1) | recusada para a mesma campanha; o fluxo de cancelamento usa a empresa 2 | P1-2 |
| Trilha de eventos | só owner e administrador | inclui o evento `system` do atestado | P1-4 |

Resultado: a 298 tem 61 checagens (58 na R4.2 + 3 novas), todas `PASS`. Os números por servidor estão no relatório.

## O que **não** mudou

- Os valores do Cenário A do DINHEIRO, a recusa do Cenário B, a trava da QA, a ativação da SF-v1.5, o preço-base fidelizado e a regra das bandeiras danificadas.
- Nenhum preço, aprovação, procedimento de QA, solicitação, documento ou orçamento é gravado pela migration. A autoverificação confere isso.
