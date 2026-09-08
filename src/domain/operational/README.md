# Políticas operacionais — POLÍTICA/SPEC, não implementação do App

**Classificação obrigatória:** os módulos deste diretório são a **regra de
negócio versionada e provada**, com testes executáveis. Eles **não são** a
implementação operacional do App e **não devem ser apresentados como tal**.

    APP_REPOSITORY=BLOCKED_APP_REPOSITORY

O Site **não executa** estes módulos em produção: o Site não é autoridade
operacional. Eles existem para (a) congelar a regra sem ambiguidade,
(b) provar as invariantes matematicamente e (c) permitir transplante para o
App sem redesenhar decisão de negócio.

| Arquivo | Papel |
|---|---|
| `benefitTypes.ts` | 7 benefícios operacionais sobre 6 nichos comerciais; as duas etapas de supermercado têm origem comercial ÚNICA |
| `schedulePolicy.ts` | matriz canônica 7×7 v1 + validador das invariantes |
| `residualAllocation.ts` | **ATIVA (política 2)** — pool → benefício individual com resíduo determinístico; 109.900 centavos por participante completo |
| `benefitDistribution.ts` | **HISTÓRICA (política 1)** — floor sem distribuir resto; para em 109.898. Mantida para regressão, não usar em caminho novo |
| `replacementPolicy.ts` | substituição preservando vaga e histórico |
| `stageMinimumPolicy.ts` | mínimo por etapa correspondente (10/12 e 20/24) |
| `manualApprovalPolicy.ts` | aprovação manual e liberação específica de etapa |

## Invariantes provadas (67 casos)

- 84 usuários = 7 grupos × 12 vagas; 7 etapas por grupo.
- Cada nicho comum uma vez por grupo; S1 uma vez; S2 uma vez.
- **S1 precede S2** e S1/S2 **nunca são consecutivas**.
- Em toda etapa de calendário: supermercado = 24 e cada nicho comum = 12.
- Distribuição **ativa (política 2)**: matriz binária determinística 84×6;
  cada participante recebe exatamente dois centavos de resíduo, um por nicho
  distinto; o pool é conservado **exatamente** e o participante completo
  fecha em **109.900** centavos. Supermercado dividido em `floor(total/2)` +
  `total - floor(total/2)`; **soma ≤ pool** de origem sempre.
- Distribuição **histórica (política 1)**: `floor(pool / alvo)` com o resto
  **não distribuído**, fechando em 109.898. Preservada em
  `benefitDistribution.ts` como referência, não como comportamento atual.
- Substituição: vaga e cronograma fixos, histórico preservado, futuros não
  conquistados cancelados, entrante **sem etapas passadas** e sem herança.
- Mínimo **por etapa correspondente**, sem média entre etapas; tolerância
  futura de ~5% **inativa**.
- Aprovação manual libera **somente** a etapa aprovada, é idempotente e não
  sobrescreve estado já consumido.

O validador detecta mutações deliberadas (S1/S2 adjacentes, ordem invertida,
benefício repetido, capacidade errada, grupo faltando).

## O que falta no App (não implementado aqui)

Ciclo operacional, grupos e vagas reais, participações, entitlements,
liberação de benefício, gateway de uso e o E2E — tudo depende do repositório
do App, indisponível. Ver `docs/APP_INTEGRATION_SPEC.md`.
