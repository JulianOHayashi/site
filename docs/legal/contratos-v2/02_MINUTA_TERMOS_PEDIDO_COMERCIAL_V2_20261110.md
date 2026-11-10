# ⚠️ MINUTA — NÃO ASSINAR — NÃO PUBLICAR — SUJEITA A REVISÃO JURÍDICA

**Termos Comerciais do Pedido — SmallFlags — Versão proposta V2**

- Data da minuta: 2026-11-10.
- Status: **RASCUNHO**. Destina-se a uma versão futura de `legal_documents` do
  tipo `commercial_order_terms`.
- **Não** deve ser publicado nem aceito antes de aprovação jurídica e de
  autorização expressa.
- Os campos entre `{{…}}` não fazem parte do texto publicado. Eles indicam as
  informações que a tela de revisão do pedido já mostra a partir do servidor
  antes do aceite. O texto publicado é um documento único e versionado. Os
  fatos de cada pedido ficam no instrumento individual.

---

## Antes de aceitar, confira

**1. O que você está contratando.** Publicidade **visual** da sua marca por
meio de **bandeira publicitária instalada sobre veículos** de divulgadores
habilitados pela SmallFlags.

- Este pedido **não é** carro de som. Não inclui alto-falante, áudio, tela ou
  luminoso.
- Não inclui transporte nem garante circulação irrestrita, rota, horário,
  audiência ou vendas.

**2. Onde e em que formação.**
- Região comercial: `{{region_name}}`.
- Exclusividade nº `{{exclusivity_sequence_number}}`.
- A formação tem seis posições e 84 unidades no total.

**3. O que você ocupa.**
- Posição: `{{position_code}}`.
- Atividade efetiva: o nicho da posição ou o segmento autorizado
  `{{effective_activity_identity}}`.
- Dentro da mesma exclusividade, nenhuma outra posição será contratada para
  atividade de mesma classificação, mesmo com outro nome comercial.

**4. Quanto e por quanto tempo.**
- Quantidade contratual: `{{nominal_quantity}}` unidades.
- Período de exclusividade: `{{exclusivity_period_days}}` dias.
- Início previsto da operação: `{{expected_operation_start}}`.

**5. Valores.** Os valores do seu pedido (`{{economic_value_cents}}` e a
composição exibida na revisão) são **calculados pelo servidor da SmallFlags**
segundo a regra comercial vigente para a sua condição (fidelizado ou não
fidelizado). A modalidade de pagamento é a escolhida na revisão. Estes Termos
**não** alteram preço, forma de cálculo ou condição de fidelização.

**6. Condições técnicas e autorizações.**
- A exibição depende de **especificação técnica aprovada** por responsável
  técnico para a bandeira e o suporte. A referência visual da arte é de
  **49 cm × 30,5 cm**.
- Essa medida é só uma **referência**: **não** é homologação nem autorização
  de circulação.
- A exibição também depende das **autorizações exigidas** pelo município e
  pela legislação de trânsito.
- Sem essas condições, a exibição não começa ou é suspensa.

**7. O que pode impedir ou suspender a exibição.** Avaria, risco de
desprendimento, condição insegura de via ou de clima, determinação de
autoridade, ausência de autorização exigível e arte recusada por risco ou
ilegalidade.

**PENDENTE DE DECISÃO (D-J3):** o efeito dessas situações sobre prazo e valores.
As regras atuais de valor e de cancelamento continuam valendo.

**8. Sua arte.**
- Você fornece ou aprova a arte e responde pelos direitos de marcas, imagens e
  textos.
- Alterações dependem de nova aprovação.

**PENDENTE DE DECISÃO (D-N3):** limites e custos de alteração.

**9. O que rege este pedido.**
- (i) O **Acordo Mestre de Parceria Comercial**, na versão `{{master_agreement_version}}`
  (hash `{{master_document_hash}}`), assinado pela sua empresa.
- (ii) Estes Termos, na versão publicada e aceita (versão e hash registrados no
  aceite).
- (iii) O **instrumento individual** do pedido, emitido pelo servidor com os
  fatos acima e identificado por código, versão do modelo e hash.
- (iv) O **Anexo Técnico** na versão aprovada que o instrumento identifica.

**10. Aceite.** O aceite é eletrônico, feito pelo responsável da empresa
autenticado. Ele fica registrado com data, versão e hash destes Termos, e,
quando disponíveis, com endereço de rede e navegador. O aceite vale **somente**
para este pedido e para esta versão.

**PENDENTE DE DECISÃO (D-J8):** se a mudança de objeto exige novo aceite de
pedidos já aceitos sob versão anterior. Hoje não há nenhum: nenhuma versão dos
Termos foi publicada.

---

### Notas de implementação (não fazem parte do texto publicado)

- **Tela de revisão:** `RevisaoContratacao.tsx` já mostra região, posição,
  segmento, quantidade e valores vindos do servidor. Os itens 1, 6 e 7 exigem
  apenas o texto publicado; nenhum cálculo novo.
- **Aceite:** `accept_commercial_order_terms` resolve no servidor a versão
  vigente e grava o aceite com `legal_document_id` e hash. Nada muda nessa
  função.
- **Publicação:** pelo caminho canônico `admin_publish_legal_document`, como
  nova versão e com `is_material_change` conforme a decisão D-J8.
