# Especificação de integração do APP — Blocos 6 a 11

**Situação:** `APP_REPOSITORY=BLOCKED_APP_REPOSITORY`. O repositório do App não
está neste workspace nem na conta acessível (`list_repos` retorna apenas
`site`, `pixel-perfect`, `sitejuju`), e clonar/adivinhar schema sem
autorização é proibido pelo passe. Nada foi implementado dentro do App.

**O que foi entregue no lugar:** módulos de política **portáveis e
versionados**, com as invariantes provadas por teste executável, prontos para
serem transplantados para o App (ou reimplementados em SQL lá) sem
redesenhar regra de negócio. Esta especificação diz exatamente onde cada peça
encaixa.

Os módulos vivem em `src/domain/operational/` e **não são executados pelo
Site em produção** — o Site não é autoridade operacional. Eles são
POLÍTICA/SPEC: a existência deles no repositório do Site **não** significa que
os blocos operacionais estejam implementados. Ver
`src/domain/operational/README.md`. Eles existem como
fonte de verdade da regra e como prova matemática auditável.

| Arquivo | Bloco | Papel |
|---|---|---|
| `benefitTypes.ts` | 6/8 | 7 benefícios operacionais × 6 nichos comerciais; origem comercial única do supermercado |
| `schedulePolicy.ts` | 6 | matriz canônica 7×7 v1 + validador das invariantes |
| `residualAllocation.ts` | 8 | **ATIVA — política 2**: resíduo determinístico, pool conservado exatamente |
| `benefitDistribution.ts` | 8 | **HISTÓRICA — política 1**: floor sem distribuir resto. Não é o contrato atual |
| `replacementPolicy.ts` | 7 | substituição preservando histórico |
| `stageMinimumPolicy.ts` | 7 | mínimo por etapa correspondente (10/12, 20/24) |
| `manualApprovalPolicy.ts` | 9 | aprovação manual e liberação específica de etapa |

## Errata de precificação — 12 unidades é canônico

O bloco não fidelizado cobre as **primeiras 12 unidades** por R$ 19.999,00;
acima de 12, R$ 1.299,00 por unidade. Fidelizado: R$ 1.299,00 por unidade.
Qualquer material antigo que diga "primeiras 10 unidades" está **superado** e
não é autoridade para alterar código, migration ou teste.

## Regra de precedência ao integrar

O **código atual do App vence** desenhos históricos. Antes de qualquer
alteração lá: auditar migrations/RPCs existentes e **preservar** o que já
funciona (`operational_cycles`, `benefit_entitlements`, `benefit_usage_*`,
gateway Ed25519/trust store, tokens hash-only). Estes módulos descrevem a
REGRA, não impõem nomes de tabela.

## Bloco 6 — cronograma de 84 usuários

- 7 grupos × 12 vagas; 7 etapas; cada usuário recebe 2 etapas de supermercado
  + 5 nichos comuns.
- A matriz v1 é dado versionado; o App deve **rodar o validador** (ou seu
  equivalente SQL) contra a matriz antes de materializar o ciclo — nunca
  confiar no dado estático.
- Invariantes provadas: 84 vagas, 7 grupos, 12 vagas/grupo, 7 etapas/grupo,
  cada nicho uma vez por grupo, S1 e S2 uma vez cada, S1 antes de S2, S1 e S2
  nunca consecutivas, supermercado = 24 e cada comum = 12 em toda etapa de
  calendário.
- **Seleção de usuários é MANUAL** no v1: operação administrativa protegida
  no App (autoridade real de admin do App, sem confiar em metadata do
  cliente), auditando quem selecionou, respeitando capacidade e impedindo
  ocupação dupla de vaga ativa. Não construir o ranking automático agora.

## Bloco 7 — substituição e mínimo contratual

- Vaga = (grupo, número). O cronograma **não é recalculado** na substituição.
- Quem sai: conserva histórico e benefícios conquistados; futuros não
  conquistados são cancelados por estado legítimo do domínio (nunca DELETE);
  permanece elegível a ciclos futuros.
- Quem entra: mesma vaga, **somente etapas não iniciadas**; não herda horas,
  documentos, conclusão nem benefícios. Se a etapa corrente já começou, entra
  na seguinte.
- **Não reutilizar** o RPC de atribuição inicial que cria sempre 7
  participações: isso daria etapas passadas ao substituto. Criar transição
  própria de substituição.
- Histórico de ocupação **append-only**, com um único ocupante corrente.
- Mínimo contratual medido **por etapa correspondente**: comum 10/12,
  supermercado 20/24. Sem média entre etapas. Relatar nominal, mínimo,
  aprovados, resultado, etapa e versão da política. Etapa abaixo do mínimo é
  questão contratual do parceiro e **não pune usuários individuais**.

## Bloco 8 — pool → benefícios individuais

**Política ATIVA: versão 2** (`residualAllocation.ts`). A versão 1 abaixo é
histórica e está registrada apenas para leitura forense.

- Matriz binária determinística 84 × 6. Cada participante recebe exatamente
  **dois** centavos de resíduo, de **nichos distintos**; a soma de cada linha
  de nicho é `[33, 27, 27, 27, 27, 27]`.
- O pool é conservado **exatamente**: nada sobra sem destino e nenhum pool é
  excedido. Participante completo = **109.900** centavos.
- Determinística e estável: sem aleatoriedade, relógio, ordem de linha do
  banco, ordem lexical de UUID ou entrada do navegador.
- Supermercado: `stage_1 = floor(total/2)`, `stage_2 = total - stage_1`.
- Invariante obrigatória: soma dos benefícios normais de um contrato
  **≤ pool** de origem.
- `assigned_amount_cents` é individual e imutável após a atribuição; **não
  existe saldo agregado de carteira**.
- O pedido carimba `benefit_distribution_policy_version` no próprio snapshot.
  O App deriva o benefício do **pool contratual + versão da política**, nunca
  de um valor individual vindo de fora.

<details><summary>Política 1 — histórica, superada</summary>

- `benefício por usuário = floor(pool_cents / alvo_de_participantes)`, resto
  **não distribuído**, fechando em 109.898 por participante completo.
- Valores registrados na época: comum R$ 166,65 (resto R$ 0,70); supermercado
  R$ 317,74 → R$ 158,87 + R$ 158,87 (resto R$ 0,09); usuário completo
  R$ 1.150,99; total não distribuído R$ 3,59.
- Preservada em `benefitDistribution.ts` para regressão. Não é o contrato
  atual e não deve ser usada em caminho novo.

</details>

## Bloco 9 — aprovação manual e liberação

- Operações administrativas protegidas no App (equivalentes a
  `admin_approve_stage_completion` / `admin_release_stage_benefit`), ou
  integração com as RPCs de review já existentes se o comportamento seguro já
  for exatamente esse.
- Específicas de ciclo/usuário/etapa, idempotentes, auditadas com ator,
  momento, motivo e origem `initial_launch_manual`; sem sobrescrita silenciosa
  e sem edição direta de tabela como procedimento normal.
- Aprovar farmácia libera **somente** farmácia. Nunca os sete.
- Não forjar sessões/documentos: a decisão é honestamente registrada como
  aprovação administrativa manual. A automação futura invoca a **mesma**
  transição, trocando apenas a origem.

## Bloco 10 — ponte de provisionamento (lado App)

### Autoridades separadas

Site e App são **bancos e autoridades distintos**. O Site é dono da
exclusividade comercial, do contrato do parceiro, da precificação, da
fidelidade, do estado de pagamento e da **asserção comercial assinável**. O
App é dono do ciclo operacional, dos usuários, do avanço de etapa, dos
entitlements, da carteira e da confirmação de benefício.

**Exclusividade comercial (Site) ≠ ciclo operacional (App).** O vínculo entre
os dois é criado **server-side**, autenticado, idempotente, auditável e
protegido contra replay. **Nenhum frontend pode criar ou mutar esse vínculo**
— o navegador nunca é autoridade sobre modo de liquidação, versão de
política, valor do pool, confirmação de financiamento ou binding.

### Contrato de payload — ATUAL: `bdflow.commercial_provisioning.v2`

Vigente desde a migration
`20260908120000_commercial_v2_provisioning_snapshot_hardening.sql`:

```
schema_version              = "bdflow.commercial_provisioning.v2"
participant_target          = 84
distribution_policy_version = 2
schedule_policy_version     = 1        (matriz 7×7 inalterada)
partners[6].contractual_pool_cents               centavos inteiros exatos
partners[6].benefit_settlement_mode              "direct_benefits" | "cash"
partners[6].benefit_distribution_policy_version  2
```

O payload é uma **asserção imutável**, montada a partir do snapshot imutável
de cada pedido — jamais reconsultando a tabela de preços vigente para
reconstruir significado histórico. Se algum pedido assinado não declarar modo
de liquidação, ou declarar política diferente de 2, o payload **falha
fechado** (`incompatible_distribution_policy`) em vez de coagir para 2.

O schema **v1** e a política de distribuição **1** são **históricos**. Uma
mensagem v1 ainda pendente não é despachada como se fosse atual: a
reivindicação a recusa com `stale_schema_version`, marca a mensagem `failed`
e libera o reenfileiramento em v2. Mensagens já aceitas ou rejeitadas não são
reavaliadas nem reescritas.

### Modo de liquidação é **por contrato de parceiro**

Cada um dos seis parceiros escolhe `direct_benefits` ou `cash`, e a formação
**pode ser mista**. O Site apenas congela e transporta a escolha.

**A execução de repasse em dinheiro NÃO existe.** Não há custódia, carteira
de saída nem trilho de payout ao usuário implementado em lugar nenhum; a
confirmação de financiamento da V2 devolve `user_payout_executed: false`. O
CP2.4 registra e transporta a escolha para tratamento posterior no App —
nada além disso.

### Minimização de dados

O App recebe uma asserção operacional, **não uma cópia do banco comercial do
Site**. Vão: UUIDs de ponte opacos, nicho, referência do pedido, quantidade
nominal, moeda, janela operacional, filiais e validadores ativos, pool
contratual exato, modo de liquidação e versão da política.

**Não vão:** CNPJ, razão social, CPF, e-mail, telefone, representante legal,
documentos ou texto de contrato; valor econômico, devido à BDFlow,
`cash_user_pool_funding_cents`, `total_monetary_funding_required_cents`,
forma de pagamento, internos de fidelidade, custos ou fila de espera;
tokens de provedor, chaves, URLs de banco ou qualquer segredo.

Os dois campos de financiamento são congelados **no pedido do Site** porque
fazem parte do contrato — mas são contabilidade do Site e por isso ficam fora
do payload. O que o App precisa é pool + modo.

### O que o CP2.4 **não** faz

Não há entrega HTTP, worker de transporte, assinatura Ed25519, endpoint do
App nem criação de ciclo operacional. Camadas 2 a 5 seguem
`BLOCKED_APP_REPOSITORY`. O App precisa:

1. Verificar assinatura pela trust store existente (kid/algoritmo/status),
   issuer/audience, separação de ambiente e expiração curta.
2. Rejeitar replay por JTI/nonce já visto.
3. Validar o payload e **decidir soberanamente** aceitar ou não.
4. Derivar os valores de benefício do **pool contratual + versão da política
   de distribuição** — jamais confiar em valor individual vindo de fora.
5. Criar o vínculo durável `commercial_exclusivity_id` ↔ `operational_cycle_id`
   server-side, único/idempotente, auditado e não gravável pelo navegador.
6. Responder com o `operational_cycle_id` aceito e o resultado.

**Não enfraquecer** o gateway de uso de benefício existente ao adicionar esta
operação: reusar a arquitetura de confiança, sem segundo mecanismo ad-hoc e
sem despachante genérico de RPC arbitrária.

## Bloco 11 — E2E de validação de benefício

Fluxo esperado, com owner **e** manager como validadores legítimos:
entitlement disponível → App gera/rotaciona token seguro → owner/manager abre
no Portal do Site → Site prova validador + unidade + rede → backend do Site
chama o gateway do App → App valida entitlement/token/rede → solicitação fica
pendente de confirmação do usuário → usuário confirma ou recusa → confirmado
vira `used`; recusa/expiração/cancelamento devolve o benefício ao ciclo de
vida vigente.

O lado Site (contexto de validador, unidade, bridge IDs, registro auditado)
está pronto nos Blocos 2 e 10. Os casos negativos exigidos — manager revogado,
manager/unidade suspensos, manager de outro parceiro, unidade errada, rede
errada, token expirado, entitlement já usado, replay, confirmação duplicada,
recusa, expiração da confirmação e concorrência — só podem ser executados
ponta a ponta com o App disponível.

**Status honesto:** `BENEFIT_USAGE_E2E=BLOCKED_APP_UNAVAILABLE`. O que é
verificável apenas no Site (elegibilidade de validador por papel/unidade/
status, negativas de RLS, ausência de PII desnecessária) está coberto pelas
suítes 020 e 060.
