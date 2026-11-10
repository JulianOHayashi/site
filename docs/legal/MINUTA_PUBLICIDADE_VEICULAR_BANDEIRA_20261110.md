# RASCUNHO PARA REVISÃO JURÍDICA — PUBLICIDADE VEICULAR COM BANDEIRAS
Data: 2026-11-10
Status: **NÃO PUBLICADO / NÃO ASSINÁVEL / SEM EFEITOS CONTRATUAIS**

Esta proposta não substitui Acordo Mestre, instrumento individual, contratos históricos ou regras comerciais. Exige revisão jurídica e técnica antes de entrar no sistema.

## 1. Acordo Mestre — objeto da parceria
**Cláusula proposta:** “A SmallFlags organiza a veiculação de publicidade visual de marcas e mensagens da CONTRATANTE mediante bandeiras publicitárias instaladas na parte superior de veículos utilizados por divulgadores habilitados, conforme a região, período, atividade comercial, exclusividade e quantidade estabelecidos no respectivo instrumento individual. O objeto não compreende, por si, publicidade sonora, serviço de alto-falantes, transporte de passageiros ou mercadorias.”

**Cláusula proposta — natureza da exclusividade:** “O alcance da exclusividade comercial é delimitado pela região, pela posição, pelo nicho ou segmento efetivo e pelas demais condições expressamente definidas no instrumento individual. Não se presumem direitos territoriais, operacionais ou publicitários além daqueles contratados.” Preservar as regras atuais de posição e atividade efetiva, incluindo autorização de segmentos.

## 2. Bandeira e instalação
**Cláusula proposta:** “A peça publicitária tem dimensão nominal de referência de **49 cm de largura por 30,5 cm de altura**. A aprovação desta referência visual não equivale a certificação ou liberação para circulação do conjunto instalado. Materiais, resistência a vento e vibração, método de fixação, compatibilidade com o veículo, altura montada, estabilidade, inspeção e retirada dependem de especificação técnica e de verificação da legislação aplicável.”

Não garantir que as dimensões sejam permitidas em todo veículo ou município. Não definir quem instala ou responde por licenças até a alocação contratual ser validada.

## 3. Arte, marca e conteúdo
**Cláusula proposta:** “A CONTRATANTE deverá fornecer ou aprovar o material publicitário e comprovar, quando necessário, os direitos sobre as marcas, imagens, mensagens e demais elementos. Alterações da arte dependem de procedimento formal de aprovação. O material que apresente risco, violação de direitos de terceiros ou desconformidade legal poderá ter sua exposição suspensa nas condições definidas no instrumento definitivo.”

Precisar quem produz, imprime, substitui e custeia as peças, inclusive para alterações durante o ciclo.

## 4. Segurança, autorizações e restrições
**Cláusula proposta:** “A instalação e a exibição somente ocorrerão quando forem legalmente permitidas e tecnicamente seguras. É vedada instalação que prejudique visibilidade, sinalização, estabilidade do veículo ou segurança do trânsito. O serviço será interrompido diante de avaria, risco de desprendimento, impedimento administrativo ou ausência de autorização exigível.”

**Pendente de definição obrigatória:** responsável por alvarás, taxas e autorizações; obrigação de verificação por município e modalidade; responsabilidade pela fixação, manutenção e inspeção; consequências e remédios contratuais de interrupções. Não atribuir automaticamente tudo ao divulgador, à anunciante ou à SmallFlags.

## 5. Instrumento individual do pedido comercial
**Objeto indicativo:** “A CONTRATADA organizará a exposição visual de marca ou mensagem da CONTRATANTE por meio de bandeiras publicitárias instaladas sobre veículos de divulgadores, no âmbito da região **{region_name}**, exclusividade **{sequence_number}**, posição e atividade efetiva **{activity_name}**, conforme a quantidade, os valores, o período, as autorizações e os anexos técnicos deste instrumento.”

Os placeholders são apenas ilustrativos e não autorizam mudanças em API ou SQL. A individualização deve consumir exclusivamente campos de fonte autoritativa e snapshots existentes. Incluir no contrato aprovado:
- região comercial e identificação da exclusividade, posição e atividade efetiva, segmento autorizado e política de sobreposição quando aplicável;
- quantidade efetiva, preço, condição comercial, modalidade de aporte, pool/QA, ciclo e prazos **sem alterar cálculos existentes**;
- especificação técnica identificada e versão de arte autorizada;
- critérios de evidência operacional, disponibilidade, aferição e conclusão;
- licenças e responsabilidades efetivamente definidas;
- tratamento de interrupções, substituição de peça, segurança e eventuais ajustes devidos, após revisão jurídica;
- referência à versão, data e hash do Acordo Mestre e do instrumento aceitos.

## 6. Relação com divulgadores e App
**Cláusula proposta de escopo:** “O divulgador habilitado realizará a exibição visual de bandeira publicitária no veículo sob sua legítima disponibilidade, somente enquanto houver condições seguras e legais de instalação e circulação, atendidos os requisitos operacionais do aplicativo e os instrumentos aplicáveis.”

Avaliar separadamente autonomia efetiva do MEI, critérios de alocação, evidências, manutenção do dispositivo, incidente, responsabilidade civil, seguros e competência de fiscalização. **Não presumir inexistência de vínculo empregatício apenas por classificação MEI.** O resgate de benefícios ocorre em procedimento distinto da atividade publicitária.

## 7. Riscos e providências
- Validar material, altura montada, estrutura de suporte, resistência mecânica e instalação para cada classe de veículo.
- Validar regras de publicidade em veículo, trânsito, licenciamento e circulação para Vitória, Vila Velha, Serra, Cariacica, Viana e novas localidades, sem presumir regra uniforme.
- Definir quem fabrica, fixa, remove, verifica e custeia as bandeiras.
- Definir o alcance da campanha e critérios probatórios sem prometer audiência, vendas, impressões ou rota que não sejam contratadas.
- Confirmar se a redefinição do objeto é alteração material e qual reaceite será necessário.
- Preservar contratos já assinados e versões históricas sem sobregravação.
- Condicionar publicação a aprovação jurídica e técnica; documentar versão e hash, comprovar testes de emissão/aceite e respeitar o fluxo fail-closed.

## 8. Estado verificado de Production em 2026-11-10
Leitura de `public.legal_documents`: não foram encontrados documentos `master_agreement` ou `commercial_order_terms` em status published/archived. Leitura de `public.commercial_instrument_templates`: template `SF-MINUTA-PRESENCIAL-v1.4` em `draft`. Esta minuta **não** habilita assinatura, checkout ou contratação.

**NÃO EXECUTAR migrações, publicação no banco ou assinatura automática deste rascunho.**
