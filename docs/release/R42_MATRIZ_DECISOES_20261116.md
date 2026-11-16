# R4.2: inventário e matriz decisão → código (antes dos patches)

- Data: 2026-11-16. Branch `feat/integracao-comercial-r42-20261116`, criada a partir da R4.1 `f319c295157c5ca3b2d25b263904c739be2fbe92`.
- Origem conferida:
  - pacote `r41-entrega-20261115.tar.gz`, sha256 `85700327…f2a9ba`, com `SHA256SUMS` interno ok;
  - bundle completo verificado em repositório vazio: HEAD `f319c29`, árvore `d31259d7c58fc6c2a7d04c90752660916f8e85f2`.
  - Nenhum commit congelado foi reescrito.

## Fontes que não estavam disponíveis nesta sessão

Estes documentos citados na missão **não estavam anexados** e não foram encontrados no projeto nem no ambiente:

- `AUDITORIA_CRUZADA_SMALLFLAGS_R41_E_DECISOES_20261115.md`
- `DECISAO_COMERCIAL_SITE_SF15_CENARIO_A_20261115.md`
- `BDFLOW_SITE_DECISAO_ALTERACAO_ARTE_FIDELIZADO_20261115_V2.md`
- `BDFLOW_SITE_QA_RESPONSAVEIS_APROVADOS_PRAZOS_PROPOSTOS_20261115.md`

Usei **apenas** o texto das decisões A–F da própria missão (`PROMPT_CLAUDE_R42_…_20261116.md`) e a confirmação do usuário na mensagem de 16/11: "Cenário A para DINHEIRO, sem QA"; fidelidade independente da reutilização; custo comprovado do fornecedor sem margem; próxima campanha ou exceção da SmallFlags.

O conteúdo desses documentos não foi inventado. As referências a eles no código são só o **nome** do documento. O hash do documento não está registrado: não o tenho.

## O que já existe (R4.1 sobre `main` 5dde3d0)

| Área | Situação encontrada |
|---|---|
| DINHEIRO | `commercial_settlement_terms` por versão × categoria × fidelidade × modalidade, que a R3 criou. A v4 não tem termos `cash`. O roteiro `supabase/ops/20261113_sf_v15_dinheiro_cenario_a.sql` grava o Cenário A por ato do dono, com a v4 em `prepared`. O roteiro do Cenário B também existe. |
| Front de preço | `apresentacaoComercial.ts`, `beneficiosAppPorOportunidade.ts` e `PainelPreco.tsx` já distinguem as duas formas e mostram o DINHEIRO **só quando o servidor publica**. Na prévia (v3 vigente) o DINHEIRO aparece "pendente". |
| Fidelidade × bandeiras | Na SF-v1.5, `cci/ceo_validar_producao_bandeiras` exigem, no fidelizado, reutilização verificada: conjunto ativo e inspeção mais recente com **todas** as peças aptas. Os CHECKs `cci/ceo_bandeiras_coerente` tornam isso obrigatório. Inspeção com peças inaptas, inclusive `art_incompatible`, devolve `flag_replacement_policy_pending`. **Conflito com a decisão B:** a mudança de arte impede a renovação fidelizada. |
| Upload de imagem | `request_customization_image_path` e `register_customization_image` (`20260822125000`): bucket privado, caminho derivado no servidor, metadado append-only e **substituição imediata** da imagem corrente a qualquer tempo. **Conflito com a decisão D:** não pode substituir a arte em execução. |
| Pedido de alteração de arte | Não existe. |
| QA | É a trava da R4.1. A ativação da v4 exige um procedimento operacional de QA aprovado, e hoje não há nenhum. Preservada. |
| Manifesto | R4.1: 13 tabelas, 50 gatilhos, 49 funções, SHA-256 `bc3f7441…b11d7`. Mexer em qualquer função de gatilho guardada gera um manifesto novo. |

## Matriz

| Decisão | Objetos existentes | Alteração R4.2 | Teste |
|---|---|---|---|
| A. DINHEIRO, Cenário A | `ops/…cenario_a.sql`, `ops/…cenario_b.sql`, `previewSF15.ts`, `beneficiosAppPorOportunidade.ts`, `PainelPreco.tsx` | O roteiro A passa a "decidido". Ele confere os 4 valores aprovados (aborta se divergirem) e QA = 0. O roteiro B passa a ser recusado. A prévia editorial mostra o DINHEIRO A. O valor oficial continua vindo só do servidor. Sem gravar preço em migration. | suíte 298 (A nas 4 condições, separação QA × dinheiro, B recusado); Vitest da prévia |
| B. Fidelidade ≠ reutilização | `cci/ceo_validar_producao_bandeiras`, `ceo_revalidar_reutilizacao_bandeiras`, `commercial_flag_facts_imutaveis`, CHECKs `*_bandeiras_coerente` | Renovação fidelizada sem reutilização verificada passa **só** com uma alteração de arte com produção autorizada para a próxima campanha, da mesma empresa e identidade. Preço-base, participantes e QA fidelizados não mudam. A produção fica em rubrica separada. Peças inaptas sem alteração de arte continuam bloqueadas (E). | 298: fidelidade mantida ao trocar a frase; reutilização parcial bloqueada; uso único; snapshot imutável |
| C. Custo comprovado sem margem | — | Orçamento do fornecedor: documento com SHA-256, escopo, peças, custo, total e **teto**. Valor ao parceiro = total do fornecedor (coluna gerada, margem impossível). Frete, criação de arte, instalação, tributos e serviços ficam listados como **não incluídos**. Aceite só do owner, com o total exato. Novo orçamento derruba o aceite. | 298: sem orçamento não aceita; teto; total divergente; novo orçamento exige novo aceite |
| D. Próxima campanha / exceção | `register_customization_image` | O pedido nasce com alvo `next_campaign` ou `current_campaign`. A campanha atual exige exceção registrada por administrador, com motivo e viabilidade. A imagem do pedido fica **travada** depois que a produção existe ou quando o pedido reutiliza bandeiras: a troca passa a ser por solicitação. | 298: exceção obrigatória; manager sem permissão; dupla solicitação; cancelamento; concorrência por versão |
| Interface | `PortalPedidos.tsx`, `PortalPedidoPersonalizacao.tsx` | Botão "Solicitar alteração de frase ou arte" e página de solicitação/orçamento/aceite. Não troca a arte em execução. Cobrança e produção externas aparecem como indisponíveis. | Vitest da página e do serviço |
| E. Danificadas | `commercial_flag_reuse_resolution` | Nenhuma: o bloqueio seguro continua (`flag_replacement_policy_pending`). | 298 |
| F. QA | trava R4.1 | Nenhuma alteração. Há um documento de alternativas (v4 inteira bloqueada × cash-only futuro). | as suítes 297 e 296 continuam passando |
| Guardas | manifesto R4.1 | **Manifesto R4.2** novo (as funções de gatilho mudam), gravado como segunda linha. Verificação com a lista dos dois SHA-256. | upgrade/rollback R4.2; verificação somente-leitura |
