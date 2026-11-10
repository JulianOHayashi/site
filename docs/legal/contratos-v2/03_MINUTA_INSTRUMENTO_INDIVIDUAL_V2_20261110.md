# ⚠️ MINUTA — NÃO ASSINAR — NÃO PUBLICAR — SUJEITA A REVISÃO JURÍDICA

**Instrumento Individual de Contratação de Publicidade Visual em Veículos — Modelo V2**

- Data da minuta: 2026-11-10.
- Status: **RASCUNHO**. Este modelo **não** está registrado em
  `commercial_instrument_templates`. Quando for aprovado, entrará como **novo
  modelo**, `draft` até a promoção deliberada, com `advertising_modality =
  'vehicle_roof_visual_flag'` e `requires_advertising_spec = true`. A minuta
  v1.4 permanece intocada.
- **Fonte dos campos:** cada campo entre chaves duplas é um fato do **snapshot do instrumento**
  emitido pelo servidor (`commercial_build_instrument_snapshot`), com
  procedência declarada. Nenhum valor é digitado à mão ou calculado no
  navegador. `{{instrument_code}}` e `{{instrument_snapshot_hash}}` são do
  próprio pedido emitido.
- **Reconcilia** a adaptação posição × segmento
  (`docs/legal/MINUTA_ADAPTACAO_POSICAO_SEGMENTO_RASCUNHO_20261103.md`) com a
  finalidade de publicidade visual (`docs/legal/MINUTA_PUBLICIDADE_VEICULAR_BANDEIRA_20261110.md`).

---

**Instrumento nº `{{instrument_code}}`** — Pedido `{{order_id}}`

Modelo `{{instrument_template_code}}`, versão `{{instrument_template_version}}`,
hash do modelo `{{instrument_template_source_hash}}`. Hash deste instrumento:
`{{instrument_snapshot_hash}}`.

Vinculado ao **Acordo Mestre** versão `{{master_agreement_version}}`, documento
`{{master_legal_document_id}}`, hash `{{master_document_hash}}`.

## 1. Partes

1.1. **CONTRATANTE:** `{{company_legal_name}}` (nome fantasia
`{{company_trade_name}}`), CNPJ `{{company_cnpj}}`, com sede cadastral em
`{{city}}`/`{{uf}}`. É representada por `{{representative_full_name}}`, CPF
`{{representative_cpf}}`, `{{representative_role_title}}`, cuja autoridade foi
verificada pela SmallFlags.

1.2. **Unidade de execução da contratante:** `{{execution_unit_name}}`
(`{{execution_unit_city}}`/`{{execution_unit_uf}}`).

1.3. **Tomador da NFS-e:** CNPJ `{{nfse_taker_cnpj}}`.

1.4. **CONTRATADA:** SmallFlags, qualificada no Acordo Mestre.

## 2. Objeto

2.1. A CONTRATADA organizará a **exibição visual** da marca ou da mensagem da
CONTRATANTE por meio de **bandeira publicitária instalada sobre veículos** de
divulgadores habilitados (modalidade `{{advertising_modality}}`), nas condições
deste instrumento.

2.2. **O objeto não inclui:**
- publicidade sonora, alto-falante, carro de som, áudio, tela ou luminoso;
- transporte;
- circulação irrestrita;
- rota, horário, audiência ou resultado de vendas.

## 3. Região, exclusividade, posição e atividade efetiva

3.1. **Região comercial:** `{{region_name}}` (`{{region_uf}}`), identificador
`{{region_id}}`.

3.2. **Exclusividade:** nº `{{exclusivity_sequence_number}}`, identificador
`{{exclusivity_id}}`. A formação tem seis posições e 84 unidades no total.

3.3. **Posição comercial contratada:** `{{position_code}}`.

3.4. **Atividade efetiva:** `{{effective_activity_kind}}`, com identidade
`{{effective_activity_identity}}`. Para nicho, a identidade é o próprio nicho.
Para segmento autorizado, é `segment:<classificação>`, tomada do **snapshot
congelado** do pedido. **Dois nomes comerciais com a mesma classificação são a
mesma atividade.** A distinção entre atividades nunca é feita pelo nome.

3.5. **Atividade contratada (descrição jurídica):** `{{activity_description}}`
(código `{{activity_code}}`), conforme o catálogo aprovado de atividades.

3.6. **Exclusividade de atividade:** durante o período deste instrumento, a
CONTRATADA não contratará, na mesma exclusividade, outra posição para atividade
de mesma classificação.

3.7. **Segmento autorizado e Outros.** **PENDENTE DE DECISÃO (D-J4):** enquanto
não houver redação aprovada de atividade contratada por segmento (com a
política de delimitação, quando houver sobreposição a nicho), o servidor
**recusa** emitir este instrumento para segmento ou para a posição Outros
(`commercial_instrument_segment_activity_unavailable`). A redação proposta, a
aplicar quando liberada, é:

> "A atividade efetiva `{{effective_activity_identity}}` foi autorizada pela
> SmallFlags antes desta contratação. A autorização registrada no pedido
> integra este instrumento e não é alterada por mudanças posteriores no
> cadastro de segmentos."

## 4. Quantidade, prazo e condição

4.1. **Quantidade contratual:** `{{nominal_quantity}}` unidades.

4.2. **Período de exclusividade:** `{{exclusivity_period_days}}` dias.
**Início previsto da operação:** `{{expected_operation_start}}`.

4.3. **Condição de fidelização:** `{{fidelized}}`.

- **Pedido não fidelizado** (primeira contratação desta atividade efetiva,
  CNPJ e cidade): é regido pelo modelo V2 de condição **não fidelizada**.
- **Pedido fidelizado:** é regido pelo modelo V2 de condição **fidelizada**.

Um modelo de uma condição **nunca** rege pedido da outra: o servidor recusa
com `commercial_instrument_template_fidelity_mismatch`. A fidelização segue a
atividade efetiva, o CNPJ e a cidade, e não a posição.

## 5. Valores

Valores calculados pelo servidor segundo a regra vigente (regra
`{{pricing_rule_version}}`, economia `{{contract_economics_version}}`):

| Item | Valor (centavos) |
|---|---|
| Valor econômico total | `{{economic_value_cents}}` |
| Contraprestação dos MEIs | `{{mei_consideration_cents}}` |
| Parcela de QA da SmallFlags | `{{smallflags_qa_cents}}` |
| Remuneração principal da SmallFlags | `{{smallflags_main_fee_cents}}` |
| Remuneração total da SmallFlags | `{{smallflags_total_remuneration_cents}}` |
| Aporte monetário total exigido | `{{total_monetary_funding_required_cents}}` |
| Valor de participação | `{{participation_value_cents}}` |

**Modalidade de liquidação dos benefícios:** `{{benefit_settlement_mode}}`.

Este instrumento **não altera** preço, contraprestação dos MEIs, pool, QA ou
remuneração. Ele só reproduz os valores do servidor.

## 6. Bandeira e especificação técnica aprovada

6.1. **Especificação técnica aprovada que rege este pedido:**
`{{advertising_spec_code}}`, versão `{{advertising_spec_version}}`, hash
`{{advertising_spec_source_hash}}`.

6.2. **Dimensão de referência da arte:** `{{artwork_reference_width_mm}}` mm ×
`{{artwork_reference_height_mm}}` mm. É uma **referência da arte**. A dimensão
final do material, o suporte, a fixação e a altura instalada são os da
especificação aprovada. A referência **não equivale a homologação** nem a
autorização de circulação.

6.3. **Sem especificação aprovada, este instrumento não é emitido.** O servidor
recusa com `commercial_advertising_spec_not_approved`.

## 7. Instalação, exibição e comprovação

7.1. A instalação e a exibição seguem a especificação aprovada e a legislação
aplicável no município de circulação (ver a Matriz Regulatória).

7.2. **PENDENTE DE DECISÃO (D-N1, D-N2):** quem instala, inspeciona e remove;
quais evidências comprovam a exibição; e como o CONTRATANTE tem acesso a elas.

7.3. **Interrupção.** Ver Acordo Mestre, cláusula 8.4.
**PENDENTE DE DECISÃO (D-J3):** efeitos da interrupção sobre prazo e valores.

## 8. Responsabilidades e restrições

8.1. A CONTRATANTE responde pela arte e pelos direitos sobre ela (Acordo Mestre,
cláusula 4).

8.2. **PENDENTE DE DECISÃO (D-J1, D-J2, D-J5):** responsabilidades por
incidentes, licenças e seguros. Este instrumento não cria multa, garantia nem
responsabilidade que não tenha sido definida.

## 9. Aceite e integridade

9.1. Aceito eletronicamente em `{{acceptance_at}}` pelo responsável autenticado
da CONTRATANTE.

9.2. Este instrumento é **imutável** depois de emitido. Uma nova versão do
modelo ou do Acordo Mestre não o reescreve.
