# SF-v1.4 — vendas manuais administrativas com o checkout bloqueado (R4, item 4)

- Data: 2026-11-13. Branch `feat/qa-modalidades-r4-20261113`.
- **Proposta. Nada aqui foi implementado.** A R4 não muda o caminho manual.

## 1. O problema

A R3 fechou o autoatendimento no banco: o portão `cci_portao_autoatendimento`
recusa intenções com versão abaixo de 4 (suíte 295, "RPC direta sob a SF-v1.4:
reserva recusada pelo banco"). O caminho administrativo
`admin_register_manual_commercial_order` **não passa por esse portão**. Com a
versão 3 (SF-v1.4) vigente, ele grava pedido SF-v1.4 se houver:

1. Acordo Mestre assinado e elegível (`m2_master_agreement_eligibility`);
2. minuta v1.4 `signable` (`commercial_signable_instrument_template`);
3. atividade contratada aprovada para a posição (a suíte 260 mostra que a minuta
   assinável sozinha não basta).

A suíte 260 prova o caminho: sem minuta assinável o pedido é recusado
(`commercial_instrument_template_not_signable`); com minuta assinável e
atividade aprovada, o pedido manual v1.4 nasce.

## 2. Estado de Production (SELECT somente leitura, 2026-11-13)

| Item | Valor |
|---|---|
| Regras de preço | v1 e v2 `superseded`, **v3 `active`** |
| Minutas de instrumento | uma, versão 1.4, **`draft`**, não fidelizada |
| Pedidos comerciais | **0** |
| Acordos Mestre assinados | **0** |
| Última migration aplicada | `20261111000511` (SF-v1.5, R3 e R4 não aplicadas) |

Hoje o caminho manual está fechado **de fato**, pela minuta em rascunho e pela
falta de Acordo Mestre assinado. Não está fechado **por regra**: basta marcar a
minuta v1.4 como `signable` para reabri-lo, sem nenhuma relação com o portão do
checkout. Pela economia da v1.4, a QA continua embutida na remuneração paga em
dinheiro, nas duas modalidades. Isso é coerente com a v1.4 histórica, mas
diverge da regra comercial da R3 para contratos novos.

## 3. Opções

| | A. Bloqueio por regra | B. Autorização pontual de uso único | C. Manter como está |
|---|---|---|---|
| O que muda | o caminho manual recusa versão < 4, como o checkout | o caminho manual sob versão < 4 exige e consome uma autorização prévia, registrada e imutável | nada; o controle é a minuta continuar `draft` |
| Contrato presencial já assinado sob v1.4 | não pode ser registrado | registrado, com documento e hash conferidos | registrado, sem controle extra |
| Risco de venda v1.4 nova "por engano" | nenhum | só com autorização nominal | alto quando a minuta virar `signable` |
| Trilha de auditoria | — | autorização × pedido × documento assinado | só a do pedido |
| Custo | menor | moderado (1 tabela, 1 verificação na RPC, testes) | zero |

Rascunho da opção B (não aplicado):

```sql
commercial_manual_sale_authorizations (
  id uuid pk,
  opportunity_id uuid not null, company_cnpj text not null,
  pricing_rule_version integer not null,          -- deve ser a vigente no uso
  benefit_settlement_mode text not null,
  signed_document_sha256 text not null,           -- hash do contrato presencial assinado
  authorization_reference text not null, authorized_by uuid not null,
  authorized_at timestamptz not null, expires_at timestamptz not null,
  consumed_by_order_id uuid unique                -- uso único
);
```

Regras de B: insert-only por RPC admin; uso só se oportunidade, CNPJ, versão,
modalidade e `document_hash` do pedido baterem com a autorização; consumo na
mesma transação do pedido; autorização vencida não serve; sem autorização a RPC
retorna `manual_sale_authorization_required` e nada é gravado.

## 4. Recomendação

**B com bloqueio por padrão.** Ela fecha a brecha por regra, como pede a R3, e
continua permitindo registrar contrato presencial já assinado, com prova do
documento. Se a operação confirmar que **não existe** contrato presencial sob a
SF-v1.4 a registrar, **A** é suficiente e mais simples.

Observação: o contrato presencial conhecido (SF-0001) é **v1.5**. Ele não deve
ser registrado sob a economia v1.4 por nenhum dos caminhos. O registro correto
depende da ativação da SF-v1.5, que segue bloqueada pela escolha entre os
Cenários A e B.

## 5. Decisão necessária

1. Existe contrato presencial assinado sob a SF-v1.4 que precise ser registrado?
2. Escolher A, B ou C.
3. Com A ou B, autorizar uma migration própria, com testes, sem aplicação
   remota até nova autorização.
