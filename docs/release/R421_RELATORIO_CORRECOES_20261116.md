# R4.2.1: correções direcionadas da auditoria independente da R4.2

- Data: 2026-11-16.
- Branch: `feat/correcoes-r421-20261116`, sobre a R4.2 `89363db`.
- Implementação: `35aa0cb`. Relatório: commit seguinte.
- **Somente local.** Não houve push, merge, deploy nem migration remota. Production, Vercel, App e Supabase remoto não foram tocados. A SF-v1.5 continua **não ativada**, e a trava da QA continua no lugar.

## 1. Fontes

- Lidas por inteiro:
  - a missão `PROMPT_CLAUDE_R421_CORRECOES_DIRECIONADAS_20261116.md`;
  - a auditoria `AUDITORIA_INDEPENDENTE_R42_SMALLFLAGS_20261116.md`.
- **Indisponíveis.** O zip `SMALLFLAGS_R421_MISSAO_E_FONTES_20261116.zip` não chegou à sessão. Os quatro documentos originais continuam ausentes e **o conteúdo deles não foi inventado**:
  - `AUDITORIA_CRUZADA_SMALLFLAGS_R41_E_DECISOES_20261115.md`
  - `DECISAO_COMERCIAL_SITE_SF15_CENARIO_A_20261115.md`
  - `BDFLOW_SITE_DECISAO_ALTERACAO_ARTE_FIDELIZADO_20261115_V2.md`
  - `BDFLOW_SITE_QA_RESPONSAVEIS_APROVADOS_PRAZOS_PROPOSTOS_20261115.md`
- Foram usadas só as regras repetidas na missão e na auditoria:
  - Cenário A;
  - fidelidade independente da arte;
  - custo efetivo comprovado sem margem, com aceite do owner e sem frete nem serviços;
  - próxima campanha, ou exceção auditada;
  - QA com prazos, valoração e consequências adiados.
- **Pendência:** conferir esta entrega contra os quatro documentos assim que forem anexados.

## 2. Implementado e testado

Todos os itens abaixo foram executados em PG 16.15 e 17.6. Os números estão na seção 4.

### P1-1: prontidão física e financeira

- `production_authorized` deixou de bastar.
- `commercial_artwork_change_readiness` responde sempre `ready = false`. Os fatos ausentes são cobrança autorizada, execução da produção e conjunto novo. É um **bloqueio seguro**: nenhum estado foi inventado como aprovado.
- `commercial_artwork_change_renewal_state` é o único resolvedor. Ele é usado na reserva (`create_commercial_checkout_intent`), na intenção (`cci_validar_producao_bandeiras`) e no pedido, inclusive na venda manual (`ceo_validar_producao_bandeiras`).
- Uma solicitação **pendente** ou **não pronta** para a campanha bloqueia a renovação. Nesse caso o sistema não cai para as bandeiras antigas.
- O schema dos fatos ficou só como proposta: `R421_PROPOSTA_PRONTIDAO_ALTERACAO_ARTE.md`.

### P1-2: vínculo com a campanha certa

- O servidor deriva do pedido base a exclusividade base e a campanha alvo:
  - `next_campaign` = sequência + 1, na mesma região;
  - `current_campaign` = a própria campanha.
- A campanha alvo é imutável.
- As regras:
  - uma solicitação viva por empresa, identidade e campanha;
  - o pedido base precisa ser o mais recente da identidade;
  - campanha alvo já adjudicada a outra empresa no nicho é recusada;
  - duas campanhas depois, a alteração **não** vale;
  - pedido alvo cancelado não faz a alteração migrar.
- Uma trava por empresa e identidade serializa a solicitação e a renovação.

### P1-3: cobertura das guardas

- O catálogo passou para a versão 2.
- **Manifesto R4.2.1** `812e47cd2f22b27c27d2cfbeca3cfca8f624bbda87fd6a27f594a411f98e662f`.
- O catálogo foi extraído e comparado byte a byte em PG16 e PG17.
- Os manifestos R4.1 e R4.2 continuam gravados como históricos.
- Cobertura: 19 tabelas, cada uma com colunas, restrições, índices, RLS, permissões e políticas; 64 gatilhos; 85 funções; os 2 buckets e as 6 políticas de Storage.
- Verificador somente leitura `20261116_verificar_r421_somente_leitura.sql`: 14 itens, mais o ESTADO.

### P1-4: custo comprovado

- O documento original fica no bucket privado `supplier-quote-documents`, sem UPDATE nem DELETE.
- O administrador registra o documento, com os metadados lidos do Storage.
- O **atestado** é feito pelo servidor, com `service_role`: o SHA-256 é calculado sobre os bytes baixados (`src/server/artworkChange/supplierDocumentAttestation.ts` e a rota `api/internal/supplier-quote-document-attest.ts`).
- O orçamento é itemizado:
  - em cada item, quantidade × unitário = total da linha;
  - a soma das linhas é o total;
  - a soma das quantidades é o número de peças;
  - preço não linear entra como vários itens.
- A conciliação acontece no fim da transação, valha o caminho que for.
- O aceite exige o SHA-256 do documento e o objeto inalterado no Storage.
- A RPC de orçamento declarado foi removida.

### Frontend

- A página da solicitação mostra os itens, o SHA-256 conferido e o link temporário do documento.
- O aceite envia o SHA-256.
- A leitura recusa a resposta inteira (falha fechada) quando há:
  - soma ou linha divergente;
  - documento não atestado;
  - orçamento sem itens.
- Com a produção autorizada, a página informa que a renovação com a nova arte fica bloqueada enquanto a cobrança e a fabricação não forem registradas.

## 3. Apenas especificado ou pendente (P2 e decisões)

| Item | Estado |
|---|---|
| Fatos de cobrança e de produção (prontidão) | **Só proposta de schema.** Bloqueio seguro em vigor. Depende da decisão do momento da cobrança e da prova de execução. |
| Alteração autorizada cuja campanha alvo foi perdida (pedido cancelado, adjudicada a outra empresa, parceiro não renova) | Fica sem uso e não migra. Destino (reembolso, transferência ou perda) **pendente de decisão**. |
| Itens de fornecedor fora da fabricação (matriz, setup, frete, embalagem, instalação) | Recusados (`quote_item_kind_not_allowed`) até haver decisão própria. |
| Atestado contra o Storage real | Lógica testada com dependências simuladas (Vitest). **Não foi executado contra o Supabase Storage real**, porque não há ambiente remoto nesta missão. |
| SHA-256 da **imagem** da arte (P2-5) | Continua calculado pelo navegador e não é atestado. O mesmo mecanismo pode ser estendido. |
| Interface administrativa (registrar documento, orçar, autorizar) | Não construída (P2-1). Hoje é RPC ou SQL. |
| Cobrança da rubrica e envio físico | Não implementados (P2-2). |
| Cadastro do conjunto novo da alteração de arte | Não implementado (P2-3). Faz parte da proposta de prontidão. |
| Bandeiras danificadas | Inalterado (bloqueio seguro). |
| QA operacional | **Adiada por decisão do proprietário.** Trava intacta, nenhuma aprovação fictícia. A ativação só em DINHEIRO continua apenas como estudo e depende de autorização separada. |
| Minutas SF-v1.5, validação contábil, venda manual SF-v1.4, custódia externa dos recibos | Inalterados (P2-6). |

**Fora do catálogo de guardas, declarado:**
- o privilégio `MAINTAIN` do PG17 (só manutenção, difere entre versões);
- `auth.uid()` (schema `auth`);
- dados operacionais (exclusividades, regiões);
- o conteúdo dos objetos do Storage (coberto pelo atestado, não pelo manifesto).

**O limite do dono do banco continua.** Um papel com DDL pode anular as guardas e restaurá-las depois; quem detecta isso é o confronto com o registro externo (R4.1, `r41-limite-confianca.sh`).

## 4. Resultados

Evidências de `35aa0cb` em PG 16.15 e 17.6 (bancos locais descartáveis), em `evidencias/` do pacote, com `SHA256SUMS`. Os resultados foram idênticos nos dois servidores.

| Ensaio | PG16 | PG17 |
|---|---|---|
| 299 R4.2.1 (nova) | 53 / 0 | 53 / 0 |
| 298 R4.2, adaptada (58 → 61) | 61 / 0 | 61 / 0 |
| 290, 295, 296, 297 (SF-v1.5, R3, R4, R4.1) | 93, 70, 31, 46 / 0 | idem |
| Contraprovas R4.2 × R4.2.1 (X1–X4: lacuna demonstrada na R4.2 e fechada na R4.2.1) | 8 / 0 | 8 / 0 |
| Concorrência alteração × renovação (gate, R4.2.1) | 3 / 0 | 3 / 0 |
| Mesma concorrência sobre a R4.2 (**controle**) | 1 / 2: C1 e C2 mostram a corrida | idem |
| Upgrade R4.2 → R4.2.1, estrutura = banco novo, rollback idêntico à R4.2, reaplicação | 6 / 0 | 6 / 0 |
| Cenário A real (roteiro de ops, não aplicado remotamente) | 9 / 0 | 9 / 0 |
| Limite administrativo do dono (R4.1, agora com o verificador R4.2.1) | 9 / 0 | 9 / 0 |
| Concorrência das bandeiras (R4) | 6 / 0 | 6 / 0 |
| Verificador somente leitura R4.2.1 | 14 / 0 | 14 / 0 |

**Suítes completas, comparadas suíte a suíte com a R4.2 no mesmo servidor:**
- Há 15 suítes históricas com falha. É **o mesmo conjunto e as mesmas contagens** na R4.2 e na R4.2.1. Nenhuma regressão, nenhuma falha mascarada.
- As únicas diferenças são a 298 (58/0 → 61/0) e a 299 (nova, 53/0).

**Frontend (`npm run validate`):**
- typecheck, Vitest e os dois builds passaram: 73 arquivos, 1.318 testes;
- `alteracaoArte` passou de 11 para 17 testes;
- `supplierDocumentAttestation` é novo, com 9 testes;
- `secret-scan` passou.

## 5. Prova de que nada foi ativado

O verificador somente leitura, rodado nos bancos recém-criados com a R4.2.1, imprime nos dois servidores:

```
estado|v1=superseded,v2=superseded,v3=active,v4=prepared|0|0|0
```

Isto é: a SF-v1.5 (v4) está **preparada, não ativa**; há 0 registros de ativação, 0 termos de DINHEIRO e 0 procedimentos de QA.

A autoverificação da migration recusa aplicar se encontrar qualquer um destes:
- preço, ativação ou aprovação;
- procedimento de QA;
- solicitação ou documento de fornecedor.

A pré-verificação da v4 continua acusando `qa_operational_procedure_missing:SF-v1.5`.

As ativações que aparecem nas suítes são fixtures `[QA FICTICIO]`, dentro de transações revertidas. A suíte termina conferindo que nada vazou.

## 6. Menor próxima decisão

A QA continua adiada, e nada nesta entrega presume a aprovação dela. A decisão que destrava a renovação com a nova arte é de produto:

**Quando a rubrica da alteração é cobrada, e qual prova de execução (comprovante de entrega do fornecedor, inspeção do conjunto novo, ou ambos) torna a alteração "pronta" para a renovação.**

Com essa decisão, a proposta de schema vira a próxima migration (R4.2.2). Separado disso, falta decidir o destino de uma alteração cuja campanha alvo foi perdida.
