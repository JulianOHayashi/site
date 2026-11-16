# R4.3: bloqueios para publicar a primeira contratação em DINHEIRO

- Data: 2026-11-16.
- Branch `feat/dinheiro-primeira-contratacao-20261116`, sobre a R4.2.1 `4c1270f`:
  - `1bc440c`: patch P0 de fidelidade do proprietário;
  - `45f3a18`: R4.3.
- **Implementação preparatória.** Não houve push, merge, deploy, migration remota nem ativação, e nenhuma aprovação foi criada.
- O BENEFÍCIO DIRETO e a QA operacional continuam bloqueados.
- Também continuam bloqueados, com os mesmos impedimentos de antes: renovação com nova arte, danos e campanhas perdidas.

## 1. O que está pronto no código (testado localmente, PG16 e PG17)

### Banco (migration `20261116210000`)

- A habilitação por modalidade fica na própria versão de preço (`enabled_settlement_modes`).
  - Só pode ser gravada enquanto a versão está `prepared`; depois da ativação é imutável.
  - Vazio significa as duas modalidades, como antes.
- Com **somente DINHEIRO**, a pré-verificação deixa de exigir o procedimento de QA para ativar a v4. A QA não é aprovada, criada nem dispensada: o benefício direto simplesmente não é vendido.
- O benefício direto é recusado na reserva, na intenção e no pedido, inclusive na venda manual (`settlement_mode_not_enabled`).
- Manifesto de guardas R4.3.
- O rollback volta exatamente à R4.2.1.

### Roteiros de operação

- `supabase/ops/20261113_sf_v15_dinheiro_cenario_a.sql`: grava o DINHEIRO do Cenário A e confere os quatro valores (inalterado).
- `supabase/ops/20261116_sf_v15_habilitar_somente_dinheiro.sql` (novo): marca a v4 como somente DINHEIRO.
  - Exige autorização e referência na transação, e confere os quatro preços do Cenário A.
  - **Não ativa a versão.**
- Ensaio local nos dois PG, com rollback. Depois do ensaio, as pendências da v4 ficam só nestas:
  - `instrument_template_missing:novo`
  - `instrument_template_missing:fidelizado`
  - `activity_catalog_incomplete:0/6`
  - `activation_approval_missing`

### Site

- A vitrine mostra o valor **em dinheiro** como valor da contratação e marca "Benefício direto · indisponível no momento".
- O `/checkout` oferece só DINHEIRO.
- A leitura do preço falha fechada com lista de modalidades inválida.
- As recusas do servidor têm mensagens próprias.

### Primeira contratação de ponta a ponta (suíte 300)

Usa as RPCs reais do Site e a mesma autenticação do Portal. As aprovações jurídicas e de lançamento são fixtures `[QA FICTICIO]` numa transação revertida.

1. A reserva em DINHEIRO do anunciante novo sai pelo Cenário A: supermercado R$ 32.817,32, com 84 bandeiras e sem QA.
2. O cliente avança, aceita os termos publicados e o pedido é finalizado; o pedido copia a reserva centavo a centavo.
3. O instrumento é emitido com a minuta aprovada para DINHEIRO.
4. Pix da primeira contratação no valor exigível.
5. A confirmação do provedor confere valor e método.
6. O titular recebe o caminho para enviar a arte das bandeiras.

O benefício direto é recusado na reserva e no pedido.

## 2. Bloqueios para publicar (lista exata)

O estado de Production abaixo foi lido só com consultas `SELECT` em 16/11/2026.

| # | Bloqueio | Tipo | Estado em Production | O que destrava |
|---|---|---|---|---|
| 1 | Aplicar as migrations pendentes, em ordem: `20261112120000` (SF-v1.5), `20261113150000` (R3), `20261113180000` (R4), `20261113200000` (R4.1), `20261116120000` (R4.2), `20261116180000` (R4.2.1), `20261116210000` (R4.3) | Técnico + autorização | Última aplicada: `20261111000511`. A v4 não existe; v3 está `active` | Autorização para migrations remotas e janela de aplicação. Ensaio de upgrade feito só localmente |
| 2 | Deploy do Site com esta branch (vitrine, checkout somente DINHEIRO, mensagens) | Técnico + autorização | Site publicado sem a R4.3 | Merge e deploy autorizados. Pode ir antes ou depois do item 1: sem a chave `enabled_settlement_modes`, o site entende as duas modalidades e, sem a v4 ativa, o checkout continua bloqueado como hoje |
| 3 | Gravar o DINHEIRO do Cenário A na v4 (roteiro de ops) | Operação autorizada | Sem v4 | Execução autorizada do roteiro em Production |
| 4 | Habilitar somente DINHEIRO na v4 (roteiro novo) | Operação autorizada | — | Autorização específica para Production (a desta missão vale só para local/staging) |
| 5 | **Minutas SF-v1.5** (anunciante novo e fidelizado) com **aprovação jurídica real** cobrindo DINHEIRO, gravada como aprovação do mesmo conteúdo (SHA-256) | Jurídico | 1 minuta em `draft` (não fidelizado), 0 aprovações | Texto aprovado pelo jurídico e registro da aprovação real |
| 6 | **Catálogo de atividades contratadas SF-v1.5** aprovado para as 6 posições | Jurídico/editorial | 0 aprovadas | Redação aprovada por posição (D-J11) |
| 7 | **Termos do pedido comercial** (`commercial_order_terms`) publicados | Jurídico | Não publicados; só os 4 documentos do onboarding | Texto aprovado e publicação pelo administrador. Sem eles, o aceite falha (`terms_not_published`) |
| 8 | **Acordo Mestre** publicado e **assinado** pelo anunciante, registrado no sistema | Jurídico + ato administrativo | 0 acordos mestres assinados | Assinatura real e registro (`admin_register_master_agreement`). Sem isso, o pedido falha (`master_agreement_missing`) |
| 9 | **Aprovação de lançamento** da v4 registrada e ativação pelo procedimento (`admin_activate_pricing_rule`) | Administrativo | Nenhuma | Aprovação real do proprietário. A ativação só passa com 1–8 resolvidos e as guardas íntegras |
| 10 | Pagar.me configurado em Production (chave e webhook) | Técnico + configuração | **Não verificado.** O endpoint público não é acessível desta sessão | Conferir `/api/payments/availability` = `payment_available: true` e o webhook apontando para `/api/payments/webhook` |
| 11 | Validação contábil do repasse em DINHEIRO aos participantes (Cenário A) | Contábil | Pendente desde a R3 | Parecer contábil |

**Ordem mínima:** 11 e 5–8 (fora do sistema) → 1 → 3 → 4 → registrar 5 e 6 → 9 → 2 → 10 → primeira contratação.

## 3. Continua bloqueado de propósito (não implementado agora)

- Benefício direto e QA operacional. Reabrir exige nova versão de preço, com o procedimento de QA aprovado.
- Renovação com nova arte: prontidão sempre falsa (R4.2.1).
- Danos (`flag_replacement_policy_pending`).
- Alteração cuja campanha alvo foi perdida.
- Itens de fornecedor fora da fabricação.
- Não há tela de administração para registrar minutas, aprovações e o Acordo Mestre; hoje é RPC ou SQL de ato do dono.

## 4. Testes executados (evidências do commit `45f3a18`, em `evidencias/` do pacote)

| Ensaio | PG 16.15 | PG 17.6 |
|---|---|---|
| Suíte 300, nova (somente DINHEIRO e primeira contratação de ponta a ponta) | 24 / 0 | 24 / 0 |
| Suítes 290, 295, 296, 297, 298 e 299 | OK | OK |
| Suítes completas | as **mesmas 15** falhas históricas da R4.2.1; nenhuma nova | idem |
| Verificador somente leitura R4.3 (estado: v4 `prepared`, sem ativação, sem DINHEIRO gravado, sem procedimento de QA) | 15 / 0 | 15 / 0 |
| Ensaio dos roteiros de ops (Cenário A + somente DINHEIRO), revertido | OK, v4 volta a `padrao` / `prepared` | idem |
| Cenário A real | 9 / 0 | 9 / 0 |
| Upgrade R4.2.1 → R4.3, rollback e reaplicação | 6 / 0 | 6 / 0 |

- Frontend: `npm run validate` passou (typecheck, 74 arquivos, 1.327 testes, builds); `secret-scan` passou.
- Testes novos: `somenteDinheiroR43.spec.tsx` (9).
- Ajustes ao texto do patch P0: `precificacaoBandeiras` e `apresentacaoComercialOportunidades`.
- Contagem de migrations: 71.
- `live_reservations:9` aparece no ensaio de ops porque o banco de teste compartilhado guarda reservas vivas deixadas pelas suítes históricas que falham. Não acontece em Production, que não tem pedidos.
