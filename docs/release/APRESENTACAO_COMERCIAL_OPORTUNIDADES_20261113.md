# Apresentação comercial dos preços — /oportunidades e detalhe

- Data: 2026-11-13.
- Branch: `feat/oportunidades-apresentacao-comercial-20261113`, a partir de
  `main` `5dde3d0dd146aae0951313f6a7bc1a4425551bb1` (HEAD remoto confirmado
  antes de qualquer alteração).
- Production conferido **somente por leitura**: regra 3 (SF-v1.4) `active`;
  agenda só SF-v1.4; última migration `20261111000511`; a migration SF-v1.5
  **não** está aplicada; 0 pedidos e 0 intenções; checkout bloqueado pela
  guarda `CheckoutPrecificacaoGuard` (exige versão 4 nas seis posições).
- **Não alterado:** preços, agenda, checkout, guarda do checkout, versões,
  contratos, App, Supabase. Nenhum merge, nenhuma publicação.

> **R3 (13/11/2026):** a QA passou a existir só em produtos no benefício
> direto e não existe no dinheiro; a igualdade de valor entre as formas só é
> afirmada quando o servidor a publica. Ver `QA_MODALIDADES_R3_20261113.md`.
>
> **R2 (13/11/2026, após auditoria do commit `52b5e0b`):** ver a seção 7. A
> conciliação da QA continua registrada na seção 4 e detalhada em
> `QA_EM_PRODUTOS_ANALISE_TECNICA_20261113.md`. Na tela, o cliente vê só uma
> ressalva.

## 1. Documento de referência

O PDF `SF-0001_PEDIDO_INICIAL_SMALLFLAGS_V1_5_ASSINATURA_REV_2026-10-14_ASSINATURAS_AMPLIADAS_V10(1).pdf`
**não está disponível** nesta sessão (anexos, projeto e histórico verificados).
Foram usadas, como referência provisória, as regras transcritas no handoff de
13/11/2026. Também não está disponível a fonte congelada das minutas v1.4 que
o backend cita (`SMALLFLAGS_SEIS_CONTRATOS_PRESENCIAIS_SF-0001_A_SF-0006_MINUTA_v1_4_CONTEUDO_CONGELADO.md`).

## 2. Diagnóstico da apresentação anterior

| Problema | Onde |
|---|---|
| Três blocos financeiros repetindo os mesmos números (prévia, quadro compacto, quadro completo) | `OpportunityCard`, `PainelPreco`, `QuadroBeneficiosApp` |
| Jargão na primeira leitura: valor econômico, MEI, QA, pool, principal, remuneração | cards e painel |
| Mesmo peso visual para preço e números secundários | cards |
| Parágrafos financeiros longos dentro dos seis cards | `QuadroBeneficiosApp compacto` |
| Parte dos participantes exibida sem explicar as modalidades | cards |
| Benefício direto lido como menor preço (cobrança direta ao lado do total) | `QuadroBeneficiosApp` |
| **Afirmação financeira não conciliada:** "a remuneração da SmallFlags é devida em dinheiro: R$ 9.084,68" no benefício direto | `QuadroBeneficiosApp`, `PainelPreco` |
| Custo de fabricação de bandeiras (R$ 2.940,00) usado como argumento | prévia nos cards e no painel |
| Referência operacional com "Seis benefícios por usuário, um por nicho" | `ReferenciaOperacional` |

## 3. Hierarquia proposta e implementada

**Card (`/oportunidades`)**, nesta ordem:
1. posição, unidades comerciais, situação;
2. **valor total da contratação** em destaque, com o selo "Novo valor proposto
   · ainda não contratável" enquanto a SF-v1.5 não estiver ativa;
3. "Até R$ X deste valor são contraprestações potenciais aos motoristas…
   sua empresa pode cumprir essa parte com benefícios em produtos das suas lojas";
4. alternativa em dinheiro, com repasses administrados pela SmallFlags;
5. nota discreta (benefício direto não reduz o total; depende do contrato e da
   elegibilidade) e "Ver oportunidade".

**Detalhe (`/oportunidades/:slug`)**:
1. resumo (nome, região, exclusividade, unidades, situação);
2. valor total em destaque; aviso de prévia; **renovação fidelizada** como
   condição aplicada pela SmallFlags, "não é uma opção a escolher",
   reutilização condicionada a inspeção;
3. **Como sua empresa pode cumprir o valor contratado** — dois cartões
   paralelos, ambos começando pelo **mesmo valor total**: Benefício direto
   ("dos quais até R$ X" em produtos) e Dinheiro ("tudo em dinheiro, inclusive
   os R$ X dos motoristas"); faixa "as duas formas têm o mesmo valor total…
   benefício direto não é desconto"; forma de cumprimento ≠ meio de pagamento;
4. **Detalhes da composição do valor** (recolhido, `details/summary`):
   participantes, remuneração SmallFlags, QA como parcela da SmallFlags,
   produção/reutilização das bandeiras sem valores internos, **aviso da QA em
   conciliação**, meio de pagamento;
5. seletor de segmento (Outros), contratação — só com a versão vigente; na
   prévia: "Contratação temporariamente indisponível" e contato.

Sem calculadora, sem seletor de fidelização, sem soma das seis oportunidades.

### Correspondência entre campos e rótulos públicos

| Campo do servidor | Rótulo público |
|---|---|
| `economic_value_cents` (condição não fidelizada) | Valor total da contratação |
| `economic_value_cents` (fidelizada) | Renovação para anunciante fidelizado |
| `mei_consideration_cents` (= 168 ou 84 × `ordinary_participation_value_cents`) | Contraprestações potenciais aos motoristas / dos participantes |
| `smallflags_total_remuneration_cents` | Remuneração contratual da SmallFlags (só na composição) |
| `smallflags_qa_cents` | Parcela de qualidade (QA) da SmallFlags (só na composição) |
| `funding_cash_cents` | Valor integral em dinheiro (= total) |
| `funding_direct_benefits_cents` | **Não exibido** (R2: o servidor ainda não declara `qa_settlement_mode`) |
| `qa_settlement_mode` (R2, ainda não emitido) | ausente = ressalva "valor a pagar em dinheiro nesta forma é confirmado na proposta comercial" e contratação bloqueada |
| `payment_method` | Meio de pagamento (só com versão vigente, na composição) |

Na prévia (versão 3 vigente), os totais SF-v1.5 vêm de `previewSF15.ts`
(editorial, só aparece se o servidor confirmar a SF-v1.4 com os valores
esperados); MEI e QA são os do servidor. Nenhum valor é contratável.

## 4. Conciliação da parcela QA

| | |
|---|---|
| **Contrato presencial SF-0001 v1.5** (transcrição do handoff; PDF indisponível) | Benefício direto: contraprestação dos MEIs em **produtos**; parcela principal da SmallFlags em **dinheiro**; **QA em produtos** para testes locais por usuário autorizado. |
| **Regra do backend** (migration `20261007120000`, P0-3, comentário 5.2) | "BENEFÍCIO DIRETO: a parceira … paga em dinheiro a remuneração **INTEIRA** da SmallFlags, QA inclusa" — atribuída ao "contrato congelado" v1.4 (fonte indisponível). CHECK `ceo_financiamento_v14_coerente`. |
| **RPCs e checkout** | `funding_direct_benefits_cents = smallflags_total_remuneration_cents` (QA inclusa); intenções e pedidos gravam `total_monetary_funding_required_cents` com a QA; `RevisaoContratacao` exibe esse valor como "Valor financeiro da cobrança". |
| **SF-v1.5 proposta** (branch não aplicada) | Mesma regra: QA dentro da remuneração monetária. |

### Diferença financeira por oportunidade (dinheiro devido no benefício direto)

| Versão / condição | Valor total | Backend (QA em dinheiro) | Leitura SF-0001 (QA em produtos) | Diferença |
|---|---|---|---|---|
| SF-v1.5 Supermercado, novo | R$ 32.939,00 | R$ 9.084,68 | R$ 8.963,00 + R$ 121,68 em produtos | R$ 121,68 |
| SF-v1.5 Supermercado, fidelizado | R$ 28.176,00 | R$ 4.321,68 | R$ 4.200,00 + R$ 121,68 em produtos | R$ 121,68 |
| SF-v1.5 comum, novo | R$ 22.939,00 | R$ 11.011,84 | R$ 10.951,00 + R$ 60,84 em produtos | R$ 60,84 |
| SF-v1.5 comum, fidelizado | R$ 16.188,00 | R$ 4.260,84 | R$ 4.200,00 + R$ 60,84 em produtos | R$ 60,84 |
| SF-v1.4 Supermercado, novo (vigente) | R$ 29.999,00 | R$ 6.144,68 | R$ 6.023,00 + R$ 121,68 | R$ 121,68 |
| SF-v1.4 comum, novo (vigente) | R$ 19.999,00 | R$ 8.071,84 | R$ 8.011,00 + R$ 60,84 | R$ 60,84 |
| Formação SF-v1.5, seis novos | R$ 147.634,00 | R$ 64.143,88 | R$ 63.718,00 + R$ 425,88 | R$ 425,88 |

O **valor total** é o mesmo nas duas leituras; muda só a forma de cumprir a QA
(dinheiro ou produtos) e, portanto, o dinheiro pago na modalidade direta. Na
modalidade dinheiro não há divergência: paga-se o total.

### Propostas tecnicamente consistentes (nenhuma escolhida)

- **A. QA em produtos (segue o SF-0001):** antes de ativar a SF-v1.5, incluir
  na própria migration SF-v1.5 (ainda não aplicada) um atributo de liquidação
  da QA por versão (ex.: `qa_settlement = 'in_kind'`), fazer
  `funding_direct_benefits_cents = smallflags_main_fee_cents`, ajustar o CHECK
  de financiamento **somente para a versão 4**, levar o fato ao snapshot e ao
  instrumento, e coordenar com o App quem é o "usuário autorizado" e como a QA
  em produtos é confirmada. A SF-v1.4 histórica fica intacta.
- **B. QA em dinheiro (segue o backend):** nenhuma mudança técnica; revisar o
  modelo presencial e os Termos do Pedido para dizer que, no benefício direto,
  a QA é paga em dinheiro com a parcela principal.

**Decisão necessária (jurídica e comercial):** qual leitura vale para a
SF-v1.5. R2: o usuário confirmou que o PDF SF-0001 v1.5, **cláusula 6.2**,
prevê a QA em produtos no benefício direto. Até a decisão, a contratação fica
bloqueada por fato do servidor, e não por constante do navegador (seção 7). A
trava de backend e o plano completo da alternativa A estão em
`QA_EM_PRODUTOS_ANALISE_TECNICA_20261113.md`.

## 5. Outras divergências entre o contrato presencial e o Site

| Tema | Contrato presencial (transcrição) | Site atual | Tratamento |
|---|---|---|---|
| Objeto | publicidade volante e carro de som | só publicidade visual com bandeiras sobre veículos | nada sonoro reintroduzido (teste `publicidadeVeicularIdentidade`) |
| Meio de pagamento | espécie/Pix | Pix no não fidelizado e cartão no fidelizado (servidor) | forma de cumprimento separada do meio de pagamento na tela |
| Posições | calçados femininos e masculinos | Calçados e Outros | tela segue o servidor (seis posições) |
| Datas | início e extensão da formação de outubro de 2026 | `planned_start_at` só se o servidor informar (hoje nulo) | nenhuma data histórica reutilizada |

## 6. Arquivos

| Arquivo | Mudança |
|---|---|
| `src/domain/pricing/apresentacaoComercial.ts` | novo: modelo de apresentação validado; trava `QA_BENEFICIO_DIRETO_CONCILIADA` |
| `src/components/commercial/OpportunityCard.tsx` | reescrito: hierarquia comercial |
| `src/components/commercial/PainelPreco.tsx` | reescrito: valor, modalidades, composição recolhível, contratação |
| `src/components/commercial/QuadroBeneficiosApp.tsx` | **removido** (repetição e afirmação de QA não conciliada) |
| `src/pages/OportunidadeDetalhe.tsx` | reordenado: resumo, valor, modalidades, segmento, contratação |
| `src/pages/Oportunidades.tsx` | cabeçalho com a mensagem central |
| `src/components/commercial/ReferenciaOperacional.tsx` | sete participações potenciais; seis posições comerciais |
| `src/__tests__/apresentacaoComercialOportunidades.spec.tsx` | novo: requisitos da seção 13 |
| `src/__tests__/fixtures/preco-publico-production-sf-v14-20261113.json`, `formacao-production-grande-vitoria-20261113.json` | respostas reais de Production (md5 conferido) |
| `src/__tests__/commercialV2Ui.spec.tsx` | 3 casos atualizados para o novo fail-closed |

`previewSF15.ts`, `beneficiosAppPorOportunidade.ts`, `contractPricing.ts`,
`pricingGateSF15.ts`, `CheckoutPrecificacaoGuard.tsx` e `RevisaoContratacao.tsx`
**não** foram alterados.

## 7. R2 — correções da auditoria de `52b5e0b`

**A1 — gate da QA.**
- Em `52b5e0b`, com a versão 4 ativa, o detalhe oferecia "Solicitar
  contratação" e `permiteCheckoutSF15` liberava o checkout, mesmo com
  `QA_BENEFICIO_DIRETO_CONCILIADA = false`.
- Agora a liberação depende de um fato declarado pelo servidor:
  - `qa_settlement_mode` é lido em cada bloco por `contractPricing.ts`;
  - `contratavel` exige a versão vigente **e** `"cash"` nas duas condições;
  - a guarda do checkout aplica o mesmo critério nas seis posições;
  - `"in_kind"` e valores desconhecidos falham fechado;
  - a constante foi removida.
- Contraprova: versão 4 sem a chave → valores vigentes, ressalva,
  "Contratação temporariamente indisponível", nenhum link `/checkout` e guarda
  `false`.
- A trava de backend (ativação e intenção) está especificada, mas **não
  aplicada**: ela pertence à migration SF-v1.5, que não está nesta branch.

**A2 — análise técnica da QA em produtos:** `QA_EM_PRODUTOS_ANALISE_TECNICA_20261113.md`.

**A3 — comunicação.**
- A frase interna "em conciliação contratual" saiu da tela. No cartão de
  benefício direto, o cliente lê: "O valor a pagar em dinheiro nesta forma é
  confirmado na proposta comercial, antes da contratação."
- O valor total aparece **uma vez** acima dos dois cartões ("Nas duas formas, o
  valor total é o mesmo: R$ X").
- Os cartões não repetem o total: o de benefício direto mostra "Até R$ Y do
  total" e o de dinheiro mostra "Tudo em dinheiro". A faixa final diz "As duas
  formas têm o mesmo valor total", sem número.
- Fora da composição recolhida, o total do detalhe aparece 2 vezes (antes eram
  4).
- O texto de contratação suspensa distingue a prévia ("novos valores ainda não
  estão ativos") da versão vigente sem liberação ("ainda não foi liberada").

**Não alterado no R2:** design, card de `/oportunidades`, preços, contratos,
Supabase, `RevisaoContratacao`, `CheckoutPrecificacaoGuard.tsx` (só o critério
de `permiteCheckoutSF15` ficou mais restritivo), `previewSF15.ts`,
`beneficiosAppPorOportunidade.ts`.
