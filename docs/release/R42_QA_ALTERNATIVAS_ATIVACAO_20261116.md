# R4.2: QA adiada. Ativação da SF-v1.5: v4 bloqueada × futura ativação só em DINHEIRO

- Data: 2026-11-16.
- **Documento de avaliação. Nada aqui foi implementado nem ativado.**
- A trava da R4.1 continua intacta e é testada (suítes 296 e 297):
  - sem procedimento operacional de QA aprovado para a economia, a v4 não ativa;
  - nenhum instrumento com QA em produtos é emitido.
- Sem decisão comercial e jurídica, nenhuma alternativa é escolhida.

## 1. Situação

| Item | Estado |
|---|---|
| Quem testa (decisão F) | Aprovado: funcionário ou terceiro credenciado da SmallFlags, com revisor diferente. Registrado só aqui; não há dado no banco. |
| Prazos, valoração, procedimento completo, consequência do não cumprimento | **Adiados**. São propostas, não aprovações. |
| Procedimento de QA no banco (`commercial_qa_operational_procedures`) | Nenhuma linha. A R4.2 não cria nenhuma, nem fictícia. |
| DINHEIRO, Cenário A | Decidido. O roteiro de ops confere os 4 valores e aborta se divergirem. **Não foi aplicado.** |
| Ativação da v4 | Impossível hoje: falta `qa_operational_procedure_missing:SF-v1.5` (e também a aprovação de lançamento e as minutas aprovadas). |

## 2. Alternativa 1: manter toda a v4 bloqueada (situação atual)

A SF-v1.5 só ativa quando houver o procedimento de QA aprovado, com as duas modalidades.

- **Migrations novas:** nenhuma.
- **Riscos:**
  - atraso comercial: nenhuma venda SF-v1.5, nem em DINHEIRO, até a QA sair do papel;
  - a SF-v1.4 continua vigente, com a venda manual SF-v1.4 ainda pendente de decisão (R4, item 4).
- **Vantagens:**
  - nada novo a auditar;
  - nenhuma regra de modalidade nova nos contratos;
  - não há risco de vender benefício direto com QA sem operação.

## 3. Alternativa 2: arquitetura futura "cash-only por modalidade"

A v4 ativaria aceitando **só DINHEIRO**, sem QA. O BENEFÍCIO DIRETO ficaria indisponível até existir o procedimento.

O que exigiria. É só um esboço, **não implementado**:

1. **Fato por versão:** coluna `enabled_settlement_modes text[]` na regra, gravável só enquanto a regra está `prepared`. O manifesto não protege dados.
2. **Pré-verificação:** cobrar o procedimento de QA só se `direct_benefits` estiver habilitado. Exigir minuta aprovada e termos só para as modalidades habilitadas.
3. **Bloqueios verificáveis** em todo caminho de gravação: gatilhos de intenção e de pedido, venda manual e construtor do instrumento. Todos recusariam a modalidade não habilitada (`settlement_mode_not_enabled`).
   - Isso altera funções de gatilho guardadas e exige um **manifesto R4.3** novo.
4. **Público e site:** a RPC publicaria só a modalidade habilitada. Hoje o site libera a contratação só com as **duas** modalidades publicadas (`modalidadesDefinidas` / `permiteCheckoutSF15`). Com um só lado publicado, a contratação continua bloqueada, o que é fail-closed. A alternativa exigiria ajustar a apresentação e a guarda do checkout para "uma modalidade habilitada pelo servidor".
5. **Contratos:** minutas SF-v1.5 só DINHEIRO, aprovadas com `settlement_modes = {cash}`. O modelo de aprovação da R4 já aceita isso. Para uma ativação parcial, a pré-verificação teria de deixar de exigir as duas modalidades.
6. **Reabertura do direto:** um ato próprio de "habilitar modalidade", com o procedimento de QA aprovado registrado. Também sujeito a auditoria.

| Risco | Natureza | Mitigação proposta |
|---|---|---|
| Ativação parcial confundida com ativação completa | Operacional | Fato por versão, com a modalidade ausente recusada no banco e não só na tela |
| Contrato que menciona benefício direto/QA vendido só em dinheiro | **Jurídico** | Minuta própria cash-only, aprovada e com hash vinculado |
| Parceiro fidelizado que hoje recebe em benefício direto | Comercial | Decidir se a renovação fidelizada em DINHEIRO é oferecida a ele |
| Mais superfície de guarda | Técnico | Manifesto R4.3, contraprovas e upgrade/rollback, como na R4.1/R4.2 |
| Fiscal: repasse em dinheiro aos participantes (Cenário A) | **Contábil** | Validação contábil antes de ativar, pendente desde a R3 |

## 4. Recomendação técnica

**Manter a Alternativa 1 agora e preparar a 2 só se a decisão comercial pedir receita SF-v1.5 antes da QA.** Motivos:

- A alternativa 2 não é um ajuste: ela muda a pré-verificação, os gatilhos guardados, a publicação e as minutas. Precisa de auditoria própria, como a R4.1.
- Sem minuta cash-only aprovada, ela não destrava nada, porque a ativação também exige minutas aprovadas.
- A decisão que mais destrava, nas duas alternativas, é aprovar o **procedimento operacional de QA** (prazos, valoração e consequência), que hoje está adiado.

## 5. Decisão necessária

1. Haverá venda SF-v1.5 antes da QA operacional? Se **não**, fica a Alternativa 1 e nada mais se faz. Se **sim**:
2. autorizar o estudo de implementação da Alternativa 2 (R4.3), com minuta cash-only e validação contábil.
