-- ===========================================================================
-- SEED STAGING-ONLY — publicação QA do Acordo Mestre v0.9.8 congelado
--
-- ALVO: jbadlzkjugdtivczxwxk (Stagging BDFLOW). NUNCA cnsypqynaxdgkcvcmkyx.
--
-- O QUE ISTO É, E O QUE NÃO É
--
-- O documento anexado está marcado "DRAFT — NÃO PUBLICAR / NÃO ASSINAR AINDA"
-- e lista seis bloqueadores para a versão assinável. Este seed, portanto, NÃO
-- publica um instrumento jurídico: ele cria um registro de QA, com título e
-- versão que tornam o status não-produtivo inequívoco, para exercitar a área
-- legal e o aceite comercial em staging.
--
-- Publicar isto em produção seria apresentar como vigente um texto que o
-- próprio documento declara não assinável. O guard abaixo recusa rodar fora de
-- staging, mas o guard é a segunda linha de defesa: a primeira é não executar.
--
-- IDEMPOTENTE: reexecutar não duplica nem altera linha existente.
-- NÃO MUTA as linhas SANDBOX já existentes (sandbox-2026-09-17-v1 e
-- SANDBOX-MASTER-v1), que são histórico de QA.
--
-- HASH: SHA-256 do conteúdo canônico (UTF-8, LF, sem BOM), 62762 bytes:
--   4faf89c2019cfc36a5e3441a3d73bb73d449a766830131cb5357c9093be9f3d8
-- Reproduzível com:
--   printf '%s' "$(cat ACORDO_MESTRE_v0_9_8.md)" | sha256sum
-- e conferido pelo próprio seed ao final.
-- ===========================================================================

BEGIN;

-- Guard de projeto: recusa execução se o banco não tiver a cara de staging.
-- Produção (SiteDBFLOW) tem a mesma estrutura, então a checagem é por um dado
-- que só staging possui: a linha SANDBOX de QA.
DO $guard$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM public.legal_documents
     WHERE version = 'sandbox-2026-09-17-v1'
  ) THEN
    RAISE EXCEPTION
      'ABORTADO: este seed e STAGING-ONLY e nao encontrou a linha SANDBOX de QA. '
      'Confirme que o alvo e jbadlzkjugdtivczxwxk.';
  END IF;
END
$guard$;

-- Autor da publicação: um admin do Site. Sem admin, aborta — published_by é
-- NOT NULL para linha publicada e inventar um uuid seria falsear autoria.
DO $pub$
DECLARE
  v_admin uuid;
  v_hash  text := '4faf89c2019cfc36a5e3441a3d73bb73d449a766830131cb5357c9093be9f3d8';
  v_calc  text;
BEGIN
  -- site_admins tem apenas user_id e created_at: nao ha coluna de status.
  SELECT user_id INTO v_admin
    FROM public.site_admins
   ORDER BY created_at
   LIMIT 1;

  IF v_admin IS NULL THEN
    RAISE EXCEPTION 'ABORTADO: nenhum site_admin para figurar como published_by.';
  END IF;

  IF EXISTS (
    SELECT 1 FROM public.legal_documents
     WHERE doc_type = 'master_agreement'
       AND version  = 'QA-STAGING-MASTER-DRAFT-v0.9.8'
  ) THEN
    RAISE NOTICE 'Ja existe: nada a fazer (idempotente).';
    RETURN;
  END IF;

  INSERT INTO public.legal_documents
    (doc_type, version, title, content, content_hash, status,
     is_material_change, effective_from, published_at, published_by, notes)
  VALUES
    ('master_agreement',
     'QA-STAGING-MASTER-DRAFT-v0.9.8',
     '[QA STAGING — NÃO ASSINÁVEL] Acordo Mestre de Parceria Comercial (minuta v0.9.8 congelada)',
     $ACORDO_MESTRE_V098$# ACORDO MESTRE DE PARCERIA COMERCIAL — SMALLFLAGS

**Versão de trabalho:** MASTER-DRAFT-2026-10-05-v0.9.8-CENARIOS-EXTREMOS-CONGELADO  
**Status:** DRAFT — CONTEÚDO COMERCIAL CONGELADO PARA REVISÃO JURÍDICA/CONTÁBIL FINAL — NÃO PUBLICAR / NÃO ASSINAR AINDA  
**Marca:** SmallFlags  
**Operador:** 58.852.870 JULIANO RANGEL NEVES HAYASHI, CNPJ 58.852.870/0001-79  
**Endereço do operador:** Avenida Minas Gerais, Quadra 19, Casa nº 08, Marcílio de Noronha, Viana/ES, Brasil  
**Parceira:** [RAZÃO SOCIAL], CNPJ [CNPJ]  
**Representante autorizado / partner_owner:** [NOME COMPLETO], [QUALIFICAÇÃO / PODERES]

> Este Acordo estabelece a relação comercial geral entre a SmallFlags e a empresa parceira. Cada exclusividade comercial específica depende de Pedido Comercial próprio, dos dados comerciais congelados pelos sistemas autorizados e das demais etapas aplicáveis. Este Acordo, por si só, não compra, reserva ou concede uma exclusividade.

## 1. Objeto e natureza do Acordo

**1.1.** O presente Acordo Mestre estabelece as regras gerais e permanentes da relação comercial entre a SmallFlags e a PARCEIRA, incluindo cadastro e representação, uso do Site e do Portal, formação comercial, pedidos, produção, comunicação, segurança, tratamento de dados, intermediação das atividades dos participantes MEI e integração com o SmallFlags App.

**1.2.** Este Acordo não constitui, isoladamente, Pedido Comercial, reserva de oportunidade, pagamento, autorização de produção, autorização genérica para representação da PARCEIRA em qualquer negócio ou garantia de disponibilidade futura.

**1.3.** Cada contratação específica será formalizada por Pedido Comercial vinculado a nicho, região e exclusividade comercial, com identificação das condições econômicas, modalidade de contraprestação, empresa/CNPJ tomador e demais dados aplicáveis.

**1.4.** Em caso de divergência entre este Acordo e um Pedido Comercial específico, prevalecerão, para aquele pedido, os dados individualizados e as condições específicas validamente aceitas, sem afastar as regras gerais deste Acordo que não forem incompatíveis.

**1.5. Definição de dia útil.** Para os prazos previstos neste Acordo, considera-se dia útil aquele que não seja sábado, domingo, feriado nacional, feriado estadual do Espírito Santo ou feriado municipal de Viana/ES, salvo quando norma obrigatória, autoridade competente, meio de pagamento ou provedor financeiro aplicável imponha calendário diverso para o ato específico.

## 2. Representação e poderes

**2.1.** A PARCEIRA declara que o representante identificado como partner_owner possui poderes suficientes para celebrar este Acordo e praticar os atos que lhe sejam reservados.

**2.2.** A SmallFlags poderá solicitar comprovação atualizada dos poderes de representação sempre que houver dúvida razoável, alteração societária, troca de responsável, ação sensível ou exigência legal.

**2.3.** Managers e demais usuários convidados poderão executar apenas as funções liberadas no sistema. A condição de manager não confere, por si só, poderes para celebrar Pedidos Comerciais, alterar condições financeiras, cancelar pedido, autorizar produção antecipada, conceder mandato, revogar mandato ou assumir obrigações em nome da PARCEIRA.

**2.4.** A PARCEIRA deverá comunicar prontamente qualquer alteração de seus representantes, poderes, unidades, dados cadastrais ou contatos relevantes.

**2.5.** A autorização para a SmallFlags formalizar instrumentos digitais em nome da PARCEIRA deverá ser expressa, específica, vigente, comprovável e vinculada ao Pedido Comercial ou a instrumento complementar identificável.

## 3. Intermediação, contratação dos MEIs e representação limitada

**3.1.** A PARCEIRA contrata a SmallFlags para intermediar e organizar a execução das atividades descritas nos Pedidos Comerciais, as quais serão prestadas pelos participantes MEI nos instrumentos específicos aceitos com a própria PARCEIRA identificada como tomadora/contraparte, quando assim previsto para a participação.

**3.2.** Dentro de autorização expressa, específica, vigente e comprovável, a PARCEIRA poderá autorizar a SmallFlags a apresentar e formalizar, **em nome da PARCEIRA**, os instrumentos digitais de contratação dos MEIs relacionados ao Pedido Comercial. Este Acordo, isoladamente, não constitui mandato genérico ou ilimitado.

**3.3.** A autorização deverá permitir identificar, no mínimo, a empresa e o CNPJ representados, o representante e seus poderes, o Pedido Comercial, a região, o nicho, as atividades, a modalidade de contraprestação, os valores aplicáveis e o período de validade.

**3.4.** A SmallFlags não poderá alterar unilateralmente empresa/CNPJ tomador, objeto material da atividade, modalidade de contraprestação ou obrigação econômica aprovada. Alteração material exigirá nova autorização empresarial válida e, quando afetar participação já ofertada ou aceita, nova manifestação do MEI.

**3.5.** A SmallFlags e o backend autorizado do SmallFlags App administrarão seleção, elegibilidade, distribuição, sequência, alocação, substituições e registros operacionais dos participantes. A PARCEIRA poderá definir requisitos objetivos da atividade, acesso e segurança e verificar fatos e resultados pelos canais autorizados, mas não poderá alterar unilateralmente registros operacionais ou critérios individuais de elegibilidade.

**3.6.** Nos instrumentos individuais aplicáveis, a PARCEIRA será identificada como contratante/tomadora da atividade do MEI e a SmallFlags atuará como intermediadora e representante autorizada nos limites da outorga. A denominação contratual não afastará a legislação nem as circunstâncias reais da prestação.

**3.7.** A autorização concedida por um CNPJ não se estende automaticamente a outro CNPJ, filial, empresa do grupo, franquia ou terceiro. Cada entidade que figure como tomadora deverá estar devidamente identificada e validamente representada.

**3.8.** A PARCEIRA deverá comunicar alteração, revogação ou expiração dos poderes concedidos. A SmallFlags deverá impedir novas formalizações que dependam de autorização ausente, expirada, incompatível ou revogada. A revogação não prejudicará obrigações legitimamente constituídas nem serviços já executados antes de sua eficácia.

**3.9.** As evidências da contratação digital deverão permitir demonstrar, conforme o fluxo homologado, a identidade do MEI, a PARCEIRA representada, a versão integral dos termos, a autorização vigente, data e hora, condições econômicas, manifestação afirmativa e integridade do conteúdo aceito.

**3.10.** A descrição do serviço em cada participação e nos documentos fiscais deverá corresponder à atividade efetivamente executada e à ocupação/CNAE informados pelo MEI para aquela atividade. O registro contratual, operacional e fiscal deverá refletir a realidade da execução.

**3.11. Ausência de pessoalidade obrigatória.** A contratação da participação recai sobre o MEI identificado, não sendo exigida, como regra do modelo SmallFlags, a execução pessoal pelo titular pessoa física do MEI. A atividade poderá ser executada pelo próprio titular ou por pessoa **legitimamente vinculada, contratada ou autorizada pelo MEI segundo relação juridicamente permitida**, identificada para fins de acesso e segurança quando necessário. O MEI permanece responsável por sua organização empresarial, pela regularidade da relação com o executante e pelas obrigações trabalhistas, previdenciárias, fiscais, civis e de segurança que lhe sejam aplicáveis.

**3.12. Liberdade de aceitação.** Antes da formalização de cada participação, o MEI poderá aceitar ou recusar a oferta apresentada. **A recusa de uma oferta futura, isoladamente, não produzirá punição, bloqueio ou piora de ranking.** Uma vez aceita a participação, deverão ser cumpridos o objeto, os requisitos objetivos, os períodos aplicáveis, as evidências e as demais condições previamente informadas.

**3.13. Ausência de horário fixo pessoal.** A SmallFlags não impõe ao titular do MEI horário fixo diário ou jornada pessoal predeterminada. Os registros de sessões, horas e períodos no SmallFlags App destinam-se a comprovar a execução objetiva da participação empresarial aceita, dentro das janelas e requisitos operacionais aplicáveis, e não constituem, por si sós, controle de jornada pessoal do titular.

**3.14. Ausência de subordinação hierárquica.** A SmallFlags e a PARCEIRA não exercerão direção hierárquica pessoal sobre o titular do MEI ou sobre o executante designado. Orientações permitidas limitam-se ao objeto contratado, requisitos de acesso, segurança, integridade, qualidade objetiva, uso correto dos sistemas e procedimentos necessários à execução e comprovação da participação.

**3.15. Substituição efetiva.** A possibilidade de execução por pessoa legitimamente vinculada, contratada ou autorizada pelo MEI deverá existir de forma real na operação e nos sistemas. O SmallFlags App não exigirá execução pessoal pelo titular do MEI como condição geral da participação. Eventual requisito específico de identificação individual imposto por lei, segurança ou acesso ao estabelecimento deverá ser objetivo, previamente informado e não será utilizado para criar pessoalidade geral do modelo. A identificação do executante para acesso e segurança não o transforma, por si só, em credor da PARCEIRA ou da SmallFlags; a contraprestação permanece vinculada ao MEI contratado, salvo estrutura futura validada em sentido diverso.

**3.16. Evidência fotográfica operacional.** Eventual fotografia exigida para início, continuidade ou encerramento de jornada terá finalidade de documentar objeto, material, ambiente, instalação, condição ou outra evidência objetiva relacionada à execução da atividade. Essa fotografia não terá por finalidade registrar o rosto, a identidade biométrica ou comprovar presença pessoal do titular do MEI.

**3.17. Realidade operacional.** As disposições desta cláusula descrevem características objetivas do modelo operacional. Se a operação vier a ser modificada de forma material para exigir execução pessoal do titular, horário fixo pessoal, comando hierárquico contínuo ou outra característica incompatível com este desenho, a mudança deverá ser previamente revisada e refletida nos instrumentos aplicáveis.

## 4. Estrutura comercial, nichos e exclusividade de marca

**4.1.** A formação comercial-base é composta por seis posições e 84 MEIs distintos de referência:

- supermercado: capacidade-base de 24 participantes simultâneos;
- farmácia: capacidade-base de 12 participantes simultâneos;
- roupas femininas: capacidade-base de 12 participantes simultâneos;
- roupas masculinas: capacidade-base de 12 participantes simultâneos;
- calçados femininos: capacidade-base de 12 participantes simultâneos;
- calçados masculinos: capacidade-base de 12 participantes simultâneos.

**4.2.** Cada posição é contratada integralmente, salvo expansão expressamente prevista em Pedido Comercial futuro ou aditivo próprio.

**4.3.** Cada nicho é comercialmente exclusivo dentro da respectiva região e exclusividade comercial. Durante a vigência aplicável, somente uma marca ou rede comercial poderá ocupar aquela posição de nicho.

**4.4.** A opção **OUTROS** poderá substituir uma das seis posições existentes. Não cria automaticamente uma sétima posição. O Pedido Comercial deverá identificar a posição substituída e as condições específicas do nicho efetivo.

**4.5.** Enquanto a exclusividade de determinado nicho estiver vigente, a SmallFlags não admitirá, para o mesmo nicho, região e período, outra marca ou rede concorrente distinta da PARCEIRA titular daquela posição.

**4.6.** A exclusividade é vinculada ao nicho, região e período específico. Não constitui exclusividade nacional, estadual, permanente ou para formações futuras, salvo previsão expressa em instrumento próprio.

**4.7.** Empresas, filiais ou CNPJs sob a mesma marca ou rede comercial poderão ser considerados integrantes da mesma identidade econômica para proteção da exclusividade quando efetivamente vinculados ao mesmo grupo, rede, franquia ou identidade comercial relevante. CNPJs distintos não poderão ser utilizados para contornar exclusividade validamente concedida.

**4.8.** Um mesmo CNPJ poderá contratar apenas uma posição de nicho dentro da mesma exclusividade comercial, sem prejuízo da regra adicional de exclusividade de marca.

**4.9.** O bloqueio comercial da posição de nicho, região e formação somente começa quando existirem, cumulativamente, **Pedido Comercial válido e pagamento oficialmente confirmado**. Waitlist, convite, reserva não concluída, início de checkout, comprovante isolado ou tentativa de pagamento não produzem bloqueio comercial nem exclusividade.

**4.9-A.** A partir do bloqueio comercial, a SmallFlags deixará de disponibilizar a mesma posição de nicho, região e formação a outra marca ou rede concorrente enquanto o Pedido Comercial permanecer válido. Esse bloqueio pré-operacional não antecipa o período operacional de 28 dias.

**4.9-B.** A **exclusividade operacional de 28 (vinte e oito) dias** começa somente com o **início operacional confirmado** da formação. Se o Pedido for cancelado validamente antes do início operacional, o bloqueio comercial termina com a eficácia do cancelamento e da correspondente resolução financeira, inclusive reembolso ou crédito quando devido, sem gerar período operacional de exclusividade.

**4.10.** O início operacional depende da contratação das seis posições e do cumprimento das condições de pagamento, produção pronta, autorização operacional, segurança e demais requisitos aplicáveis.

**4.11.** Este Acordo não garante preço, disponibilidade, posição em fila, data de início ou renovação futura. Esses elementos pertencem ao Pedido Comercial ou oportunidade específica.

## 5. Período operacional, participações e carga horária agregada

**5.1.** O período operacional de referência da exclusividade será de 28 (vinte e oito) dias.

**5.2.** O SmallFlags App subdividirá o período operacional de referência em sete etapas de 4 (quatro) dias, segundo as regras operacionais homologadas.

**5.3.** Para o MEI que percorra integralmente a formação-base, estão previstas duas participações de supermercado em etapas não consecutivas para esse participante e uma participação em cada uma das outras cinco posições, totalizando sete participações ordinárias.

**5.4.** Para o nicho supermercado, a carga horária agregada de referência do período operacional é de 5.376 (cinco mil trezentas e setenta e seis) horas.

**5.5.** Para cada uma das demais posições, a carga horária agregada de referência é de 2.688 (duas mil seiscentas e oitenta e oito) horas.

**5.6.** Será considerado cumprido o requisito quantitativo agregado do contrato do nicho quando o total de horas reconhecidas durante o período operacional atingir, no mínimo, 80% da respectiva carga horária agregada de referência.

**5.7.** Em consequência:

- supermercado: mínimo agregado de 4.300 horas e 48 minutos;
- cada uma das demais posições: mínimo agregado de 2.150 horas e 24 minutos.

**5.8.** O critério agregado não reduz, substitui, compensa nem elimina a carga horária mínima exigida para cada participação no SmallFlags App. Essa carga horária é requisito objetivo da participação contratada com o MEI e não significa, por si só, jornada pessoal do titular. O cumprimento poderá ocorrer pelo titular ou por executante validamente designado pelo MEI, conforme a cláusula 3 e os controles operacionais aplicáveis. A aferição contratual da exclusividade e a aferição individual de cada participação são controles distintos.

**5.9.** Para apuração contratual, somente serão consideradas horas reconhecidas pelos registros e regras do backend operacional autorizado. Registros manuais ou declarações isoladas não substituem a fonte operacional de verdade.

**5.10.** O cumprimento quantitativo agregado não afasta as demais obrigações materiais, de segurança, documentação, integridade, pagamento ou conduta.

**5.11.** Caso o limite agregado de 80% não seja atingido, ficará caracterizado o não atingimento do requisito quantitativo do respectivo nicho. Consequências comerciais específicas dependerão do Pedido Comercial ou de instrumento de resolução aplicável; este Acordo não cria penalidade automática não expressamente pactuada.

## 6. Contraprestações, envelope econômico, documentos e modalidades

**6.1.** A elegibilidade individual de cada participação é independente do critério agregado previsto na cláusula 5.

**6.2.** Cada participação ordinária executada e aprovada terá valor econômico de **R$ 141,99**. O MEI que executar e tiver aprovadas as sete participações ordinárias terá contraprestações que totalizam **R$ 993,93**.

**6.3.** Na formação-base completa, o valor econômico de referência associado às sete participações e à parcela de QA da SmallFlags é de **R$ 83.916,00**, composto por:

- **R$ 83.490,12** de contraprestações ordinárias dos MEIs; e
- **R$ 425,88** de parcela própria da SmallFlags destinada internamente a QA, testes e validações operacionais.

**6.4.** Para fins de composição econômica do Pedido Comercial, a referência de **R$ 999,00 por participante-equivalente** é formada por **R$ 993,93** de contraprestações ordinárias e **R$ 5,07** de parcela QA própria da SmallFlags. Os R$ 5,07 não constituem oitava participação, crédito do MEI, obrigação de repasse ao MEI ou saldo pertencente à PARCEIRA.

**6.5.** Cada participação é economicamente independente. A participação executada e aprovada gera contraprestação de R$ 141,99, ainda que outra participação do mesmo MEI não seja concluída ou aprovada.

**6.6.** Na formação-base, a composição é:

| Pedido | Contraprestações ordinárias dos MEIs | Parcela QA SmallFlags | Referência econômica conjunta |
|---|---:|---:|---:|
| Supermercado | R$ 23.854,32 | R$ 121,68 | R$ 23.976,00 |
| Cada uma das outras cinco posições | R$ 11.927,16 | R$ 60,84 | R$ 11.988,00 |
| Formação completa | R$ 83.490,12 | R$ 425,88 | R$ 83.916,00 |

**6.7.** A fidelização comercial não reduz o valor de R$ 141,99 de cada participação nem a parcela QA. A diferença entre condição fidelizada e não fidelizada incide sobre a parcela operacional principal da SmallFlags.

**6.8.** Cada Pedido Comercial deverá indicar expressamente uma das modalidades aplicáveis:

[  ] **DINHEIRO**  
[  ] **BENEFÍCIO DIRETO**

**6.9. Modalidade DINHEIRO.** A PARCEIRA pagará à SmallFlags o valor monetário total do Pedido Comercial. Entre as partes, a parcela correspondente às contraprestações dos MEIs será tratada separadamente da remuneração contratual da SmallFlags e permanecerá identificável para fins de repasse e conciliação.

**6.10.** Na modalidade DINHEIRO, após a aprovação da participação e da documentação fiscal aplicável, a SmallFlags realizará e documentará o repasse de **R$ 141,99** ao MEI em até **2 (dois) dias úteis**, sem prejuízo de prazo legal mais favorável ou obrigação legal específica.

**6.11. Insuficiência de recursos na modalidade DINHEIRO.** Identificada falta de recursos necessários ao cumprimento das obrigações da PARCEIRA, a SmallFlags notificará formalmente a PARCEIRA, que terá **2 (dois) dias úteis** para regularização. Esse prazo de correção não prorroga automaticamente contraprestações já exigíveis nem elimina direitos relativos a serviços já prestados.

**6.12. Modalidade BENEFÍCIO DIRETO.** A PARCEIRA fornecerá diretamente ao MEI o benefício especificado para cada participação ordinária, com valor econômico de **R$ 141,99**, e responderá por sua disponibilização efetiva nas condições contratadas. Descrição, valor, locais, limites, forma de validação e demais condições materiais deverão estar disponíveis ao MEI antes do aceite.

**6.13. Pagamento monetário à SmallFlags no BENEFÍCIO DIRETO.** Mesmo quando a contraprestação ordinária dos MEIs for cumprida por BENEFÍCIO DIRETO, a PARCEIRA pagará em dinheiro à SmallFlags a parcela operacional principal do Pedido Comercial **acrescida da parcela QA própria da SmallFlags**. A parcela QA não será paga aos MEIs em benefício e não será convertida em crédito individual de participante.

**6.13-A. Limites do BENEFÍCIO DIRETO na primeira versão.** O benefício ficará restrito à própria PARCEIRA ou à rede/unidades contratualmente identificadas, será pessoal ao vínculo empresarial do MEI com a participação e **não poderá ser transferido entre usuários, negociado em P2P, sacado, convertido livremente em dinheiro por funcionalidade do App ou utilizado como carteira de pagamento generalista**. Antes do aceite deverão estar congelados produtos/serviços elegíveis, referência econômica, unidades habilitadas, período, exclusões, eventuais limites, responsável ou mecanismo de validação e procedimento de indisponibilidade. Não poderá existir tarifa ou copagamento oculto não informado previamente.

**6.14. Falha na contraprestação da PARCEIRA.** Considera-se falha na contraprestação qualquer ação ou omissão imputável à PARCEIRA que impeça, inviabilize ou retarde indevidamente a disponibilização ou fruição de benefício exigível nas condições contratadas.

**6.15.** São exemplos de falha operacional capaz de caracterizar falha na contraprestação, quando produzirem o efeito descrito na cláusula 6.14: ausência de pessoa autorizada para validar o benefício; falta de cadastro, habilitação ou manutenção de managers necessários; vinculação incorreta de managers às unidades; inexistência de owner, manager ou outro responsável habilitado disponível para concluir o procedimento; indisponibilidade do produto, serviço ou crédito prometido; recusa sem fundamento contratual; erro cadastral não corrigido; alteração unilateral de local, limite ou condição material; ou falha interna da PARCEIRA que torne o benefício inutilizável.

**6.16.** A ausência de manager, isoladamente, não configura inadimplemento automático se existir owner ou outro responsável autorizado e operacionalmente apto a concluir a validação. Ela será considerada falha quando impedir ou retardar indevidamente a contraprestação exigível e não houver mecanismo alternativo apto a concluí-la.

**6.17. Cumprimento do BENEFÍCIO DIRETO.** Para fins deste Acordo, uma contraprestação em BENEFÍCIO DIRETO será considerada cumprida quando o benefício de **R$ 141,99** correspondente à participação estiver efetivamente disponibilizado ao MEI, no local, período e condições previamente contratados, e estiver materialmente apto à utilização. A mera exibição de status interno, crédito nominal ou indicação no aplicativo sem possibilidade real de fruição não caracteriza cumprimento.

**6.18.** Se o benefício tiver sido corretamente disponibilizado e estiver efetivamente utilizável nas condições contratadas, a decisão exclusiva do MEI de não utilizá-lo não caracteriza falha da PARCEIRA e não gera conversão automática para dinheiro.

**6.18-A. Integralidade do BENEFÍCIO DIRETO.** Cada contraprestação em BENEFÍCIO DIRETO corresponde integralmente a **R$ 141,99 por participação**. Disponibilização parcial, saldo inferior, fruição condicionada a pagamento adicional não previamente contratado ou qualquer composição que deixe parcela econômica da participação sem cobertura não caracteriza cumprimento integral. O sistema não deverá registrar quitação total enquanto o valor econômico contratado não estiver efetivamente disponível nas condições aceitas.

**6.19. Regularização.** Identificada falha relativa a BENEFÍCIO DIRETO, a SmallFlags notificará formalmente a PARCEIRA, que terá **2 (dois) dias úteis** para regularizar integralmente a situação. O prazo de regularização não constitui carência adicional para obrigação já exigível.

**6.20. Conversão do saldo não cumprido.** Encerrado o prazo da cláusula 6.19 sem regularização integral, **somente o saldo econômico das contraprestações ordinárias ainda não cumpridas** no Pedido Comercial afetado será convertido em obrigação de pagamento em moeda corrente nacional. Valores de benefícios validamente cumpridos permanecerão reconhecidos e não serão cobrados novamente.

**6.21.** Para fins da cláusula 6.20, o saldo máximo sujeito a conversão corresponde, antes de qualquer cumprimento, a **R$ 23.854,32** no Pedido Comercial de supermercado e a **R$ 11.927,16** em cada Pedido Comercial das outras cinco posições. O valor efetivamente convertido será reduzido pelas contraprestações já validamente cumpridas.

**6.22.** O saldo convertido será imediatamente exigível e deverá ser integralmente transferido pela PARCEIRA à SmallFlags até o final do **primeiro dia útil subsequente** ao término do prazo de regularização. A SmallFlags receberá esse valor **exclusivamente para operacionalizar as contraprestações ordinárias de R$ 141,99 que venham a se tornar exigíveis**, mantendo-o identificado por Pedido Comercial e separado de sua remuneração contratual própria.

**6.23.** A conversão do saldo não cumprido não extinguirá nem suspenderá automaticamente o Pedido Comercial. Estando a produção pronta e a operação iniciada, os participantes continuarão suas atividades conforme a programação operacional, preservadas condições materiais, legais e de segurança.

**6.24.** A conversão não transforma o saldo do pedido em remuneração indistinta ou antecipada de participantes. Cada MEI continuará tendo direito somente à contraprestação de **R$ 141,99** correspondente a cada participação executada e aprovada, observados os registros de quais participações foram cumpridas por benefício e quais foram liquidadas em dinheiro.

**6.25.** O não pagamento do saldo convertido no prazo da cláusula 6.22 constituirá descumprimento contratual adicional, sem eliminar contraprestações ou demais obrigações já constituídas.

**6.26. Sequência fiscal e documental da participação.** Salvo exigência legal ou fiscal específica mais adequada, a sequência operacional adotada será: (a) execução da participação; (b) conclusão dos requisitos e horas aplicáveis; (c) emissão pelo MEI do documento fiscal da participação, no valor de R$ 141,99, contra o CNPJ da empresa efetivamente tomadora; (d) envio do documento pelo SmallFlags App; (e) análise documental e operacional pela SmallFlags; (f) correção ou reenvio, quando cabível; (g) aprovação da participação; e (h) liquidação da contraprestação, por repasse em DINHEIRO ou por BENEFÍCIO DIRETO efetivamente disponibilizado.

**6.27. Documento fiscal do MEI.** Para cada participação executada, o MEI emitirá o documento fiscal aplicável para o CNPJ da empresa efetivamente tomadora, com identificação e valor compatíveis com a participação, conforme procedimento fiscal validado. Na trajetória integral serão sete documentos por MEI: dois relativos às participações de supermercado e um para cada uma das outras cinco posições.

**6.28. Remuneração da SmallFlags e documento fiscal.** A SmallFlags emitirá seu documento fiscal exclusivamente sobre sua **remuneração contratual própria** decorrente do Pedido Comercial, incluindo a parcela operacional principal e a parcela QA que lhe pertence. Os R$ 141,99 destinados a cada participação do MEI não integrarão o valor faturado pela SmallFlags apenas por transitarem operacionalmente por sua conta para fins de repasse, sujeito à validação contábil e fiscal do procedimento.

**6.29.** Documento fiscal do MEI ilegível, inconsistente, incompatível, cancelado ou que não corresponda à participação poderá ser devolvido para correção ou reenvio segundo procedimento auditável. A emissão do documento fiscal, isoladamente, não comprova os demais requisitos operacionais.

**6.29-A. Documento fiscal e resultado NÃO AUTORIZADA.** Se documento fiscal já tiver sido emitido e a participação vier a ser definitivamente encerrada como **NÃO AUTORIZADA**, a SmallFlags deverá orientar e registrar o procedimento fiscal aplicável de cancelamento, substituição, correção ou outro ajuste admitido pelas regras tributárias vigentes, sem manter deliberadamente documento incompatível com o evento final da participação.

**6.30.** Os rótulos econômicos deste Acordo expressam a alocação comercial definida pelas partes, mas não substituem a classificação contábil, fiscal ou tributária obrigatória. O procedimento de escrituração, retenções, emissão fiscal, intermediação financeira e tratamento de contraprestação não monetária deverá ser validado pelo profissional contábil responsável antes da operação em produção.

**6.31. Reconciliação final dos recursos dos MEIs.** Valores recebidos pela SmallFlags exclusivamente para contraprestações dos MEIs — inclusive recursos originalmente recebidos na modalidade DINHEIRO e saldos convertidos de BENEFÍCIO DIRETO — não integram sua remuneração contratual. Encerrado definitivamente o Pedido Comercial, eventual saldo que não corresponda a contraprestação legitimamente constituída será reconciliado e **devolvido ou creditado à PARCEIRA**, descontadas apenas obrigações efetivamente constituídas, estornos, chargebacks ou ajustes documentados aplicáveis.

**6.32. Ledger mínimo.** A SmallFlags manterá trilha suficiente para identificar, conforme aplicável: origem do recurso, Pedido Comercial, participação, MEI beneficiário, valor recebido, status, valor exigível, repasse, estorno, devolução ou crédito e saldo final reconciliado.

## 7. Formação comercial, data prevista e extensão

**7.1.** Cada Pedido Comercial informará ou fará referência à data prevista para o início operacional.

**7.2.** Para a primeira formação comercial abrangida por este modelo, a data prevista de início é **19 de outubro de 2026**, condicionada à contratação das seis posições e ao atendimento das demais condições contratuais, de produção, segurança, pagamento e autorização operacional.

**7.3.** Se, em 19 de outubro de 2026, a formação ainda não estiver concluída por falta de contratação das seis posições, haverá uma única extensão automática de 7 (sete) dias corridos.

**7.4.** A nova data prevista será **26 de outubro de 2026**. A extensão não altera automaticamente preço, nicho, região, modalidade, condição de fidelidade ou demais condições econômicas já contratadas.

**7.5.** Se a formação for concluída durante a extensão, o início operacional ocorrerá apenas quando as demais condições estiverem satisfeitas, inclusive produção física concluída e pronta para uso.

**7.6.** Se, ao término da extensão, a formação ainda não estiver concluída, a SmallFlags comunicará a PARCEIRA e apresentará as alternativas disponíveis.

**7.7.** A PARCEIRA poderá escolher por escrito entre:

- permanecer na formação e aceitar nova previsão expressa;
- transferir o Pedido Comercial para a próxima formação comercial equivalente disponível; ou
- cancelar o Pedido Comercial afetado. Se a produção não tiver sido iniciada, o reembolso será integral; se a produção já tiver sido iniciada, o cancelamento continuará permitido, mas a apuração do valor restituível observará as cláusulas 10.9 a 10.11 e a seção 11, inclusive somente custos diretos, reais, comprovados e não recuperáveis quando juridicamente admitidos.

**7.8.** Na transferência para formação equivalente, os valores pagos serão preservados como crédito integral. Para a mesma combinação de CNPJ, cidade e nicho, as condições econômicas originalmente contratadas serão preservadas, salvo mudança de escopo solicitada ou condição diferente expressamente aceita.

**7.9.** Nenhuma transferência será automática ou realizada contra a vontade da PARCEIRA.

**7.10.** Para formações futuras, o Pedido Comercial poderá indicar outras datas, preservada a mesma lógica salvo condição expressamente diversa aceita pelas partes.

## 8. Pedidos, preços, fidelidade, expansão e reservas comerciais

**8.1.** A primeira compra válida da combinação **CNPJ + cidade + nicho** será tratada como compra fundadora / não fidelizada. A fidelidade comercial para compras posteriores somente produzirá efeito após reconhecimento pelo backend autorizado.

**8.2.** Para a formação-base:

| Posição | Quantidade-base | Não fidelizado | Fidelizado | Contraprestações dos MEIs | QA SmallFlags |
|---|---:|---:|---:|---:|---:|
| Supermercado | 24 | R$ 29.999,00 | R$ 28.176,00 | R$ 23.854,32 | R$ 121,68 |
| Cada uma das outras cinco posições | 12 | R$ 19.999,00 | R$ 16.188,00 | R$ 11.927,16 | R$ 60,84 |

**8.3.** A parcela operacional principal da SmallFlags será:

| Posição | Não fidelizado | Fidelizado |
|---|---:|---:|
| Supermercado | R$ 6.023,00 | R$ 4.200,00 |
| Cada uma das outras cinco posições | R$ 8.011,00 | R$ 4.200,00 |

**8.4.** Somada a parcela QA que pertence à SmallFlags, sua remuneração contratual total por Pedido Comercial será:

| Posição | Não fidelizado | Fidelizado |
|---|---:|---:|
| Supermercado | **R$ 6.144,68** | **R$ 4.321,68** |
| Cada uma das outras cinco posições | **R$ 8.071,84** | **R$ 4.260,84** |

**8.5.** Na formação-base completa de seis Pedidos Comerciais:

| Condição | Valor econômico total | Contraprestações dos MEIs | Parcela QA SmallFlags | Parcela operacional principal SF | Remuneração contratual total SF |
|---|---:|---:|---:|---:|---:|
| Não fidelizado | R$ 129.994,00 | R$ 83.490,12 | R$ 425,88 | R$ 46.078,00 | **R$ 46.503,88** |
| Fidelizado | R$ 109.116,00 | R$ 83.490,12 | R$ 425,88 | R$ 25.200,00 | **R$ 25.625,88** |

**8.6.** A fidelização reduz somente a parcela operacional principal da SmallFlags. Não reduz as contraprestações ordinárias de R$ 141,99 nem a parcela QA de R$ 5,07 por participante-equivalente.

**8.7.** Em futura expansão expressamente contratada, cada unidade adicional acrescentará **R$ 1.299,00** ao valor econômico do pedido, composto, como referência, por:

- **R$ 993,93** de contraprestações ordinárias relacionadas às sete participações;
- **R$ 5,07** de parcela QA própria da SmallFlags; e
- **R$ 300,00** de parcela operacional principal da SmallFlags.

**8.8.** Consequentemente, cada unidade adicional representa **R$ 993,93** destinados economicamente às participações e **R$ 305,07** de remuneração contratual da SmallFlags, sem alterar participações já congeladas.

**8.9.** Para supermercado, eventual expansão aplica-se às unidades acima de 24; para cada uma das demais posições, às unidades acima de 12. A formação inicial não será ampliada automaticamente e qualquer expansão dependerá de previsão expressa em Pedido Comercial próprio ou aditivo.

**8.10.** O nicho OUTROS seguirá a quantidade-base e a referência econômica da posição que substituir, salvo regra específica expressamente aprovada. A formação continuará com seis posições.

**8.11.** Preço, quantidade, nicho, região, condição de fidelidade, exclusividade, modalidade, envelope operacional, parcela da SmallFlags, versão dos termos e demais dados materiais deverão ser registrados e congelados pelo backend autorizado no momento contratual aplicável.

**8.12.** Waitlist, convite, reserva, início de checkout ou tentativa de pagamento não geram fidelidade, contratação ou direito adquirido à exclusividade.

**8.13.** Quando oportunidade real for oferecida e aceita, poderá existir reserva temporária pelo prazo informado. A reserva não equivale a pagamento ou contratação concluída.

**8.14.** Alterações materiais de preço, quantidade, nicho, região, modalidade, tomador ou objeto exigem novo aceite ou instrumento quando aplicável.

## 9. Pagamentos

**9.1.** Os meios monetários de pagamento à SmallFlags serão aqueles oficialmente apresentados no Pedido Comercial ou checkout vigente. A referência comercial atual é Pix e cartão, sem boleto; primeira compra não fidelizada à vista e compra fidelizada com possibilidade de parcelamento em até 6 vezes quando tecnicamente disponível e expressamente apresentado.

**9.2.** Na modalidade DINHEIRO, a PARCEIRA transferirá à SmallFlags o valor monetário total do Pedido Comercial. A SmallFlags deverá manter segregação contábil e operacional suficiente para distinguir sua remuneração contratual das quantias recebidas para posterior repasse aos MEIs.

**9.3.** Na modalidade BENEFÍCIO DIRETO, a PARCEIRA cumprirá diretamente perante os MEIs as contraprestações ordinárias de R$ 141,99 por participação e pagará em dinheiro à SmallFlags sua remuneração contratual, composta pela parcela operacional principal e pela parcela QA. Para a formação-base não fidelizada, o pagamento monetário à SmallFlags corresponde a R$ 6.144,68 no supermercado e R$ 8.071,84 em cada uma das outras posições.

**9.4.** A confirmação de pagamento depende do backend e, quando aplicável, do provedor financeiro. Comprovante isolado ou informação apresentada no navegador não substitui a confirmação oficial.

**9.5.** Suspeita de fraude, contestação, chargeback ou inconsistência relevante poderá suspender os efeitos ainda não executados do Pedido e impedir o início da produção enquanto durar a análise, sem eliminar direitos já constituídos. Chargeback, estorno, contestação do meio de pagamento ou reversão financeira posterior não extinguem obrigação comercial validamente constituída, contraprestação de MEI já exigível ou outra obrigação que subsista segundo este Acordo.

**9.5-A. Impedimento de repasse por dados do MEI ou PSP.** Se repasse já aprovado não puder ser concluído por chave Pix, conta ou dado de pagamento inválido/incompleto fornecido pelo MEI, ou por indisponibilidade externa comprovada do provedor de serviços de pagamento, a SmallFlags registrará a tentativa e notificará o MEI quando aplicável. Enquanto o impedimento não for imputável à SmallFlags, o prazo de repasse não caracterizará mora da SmallFlags. Sanado o impedimento, o repasse deverá ser concluído em até **2 (dois) dias úteis**.

**9.6.** Os rótulos econômicos deste Acordo não substituem a classificação contábil, fiscal ou tributária de cada fluxo.

## 10. Produção, início operacional, cancelamento e continuidade

**10.1.** A produção física relacionada ao Pedido Comercial poderá ser terceirizada e somente será iniciada quando as condições comerciais, de segurança e de pagamento aplicáveis estiverem atendidas.

**10.2.** Nas primeiras 48 (quarenta e oito) horas contadas da confirmação oficial do pagamento, a produção física não será iniciada.

**10.3.** Depois das primeiras 48 horas e até o término do 7º (sétimo) dia corrido contado da confirmação do pagamento, a produção somente poderá começar mediante autorização antecipada, expressa e destacada do partner_owner em instrumento posterior e separado do Pedido Comercial inicial.

**10.4.** Sem autorização antecipada, a produção poderá começar após o término do 7º dia corrido, desde que não exista impedimento operacional, antifraude, contratual, financeiro ou de segurança.

**10.5. Condição obrigatória para atuação dos MEIs.** As atividades dos participantes MEI vinculadas ao Pedido Comercial **somente poderão começar depois que a produção física necessária à operação estiver concluída e pronta para utilização**. Nenhum participante deverá iniciar atividade do pedido enquanto a produção correspondente estiver pendente.

**10.6.** O início da produção física não equivale ao início operacional dos MEIs. A SmallFlags deverá registrar a conclusão da produção e sua disponibilidade operacional antes de autorizar o início das atividades no SmallFlags App.

**10.7.** O período operacional somente poderá começar quando, cumulativamente, a produção necessária estiver pronta, a formação comercial estiver apta, as condições financeiras estiverem regulares, houver autorização operacional válida e existirem condições adequadas de acesso e segurança.

**10.8.** Cancelamento validamente solicitado antes do início da produção dará direito ao reembolso integral dos valores pagos relativos ao Pedido Comercial, ressalvada regra legal obrigatória diferente. Nesse estágio, não haverá serviços dos MEIs executados em razão daquele pedido.

**10.9.** Se o cancelamento ocorrer após o início da produção, poderão ser considerados exclusivamente custos diretos, reais, comprovados e não recuperáveis relacionados ao Pedido, na extensão juridicamente permitida. Não haverá multa ou retenção genérica desvinculada de custo efetivamente incorrido.

**10.10.** Quando a produção tiver sido iniciada antecipadamente entre 48 horas e o 7º dia, a retenção prevista na cláusula 10.9 somente poderá ser aplicada se existir a autorização antecipada válida e destacada exigida pela cláusula 10.3.

**10.11.** Produtos ou materiais já concluídos poderão ser entregues à PARCEIRA quando compatível com o cancelamento e as condições aplicáveis.

**10.12.** Depois do início operacional, cada participação executada e aprovada produzirá seus próprios efeitos econômicos e documentais. Cancelamento, suspensão ou encerramento posterior não eliminarão contraprestações legitimamente constituídas.

**10.12-A. Aquisição da remuneração da SmallFlags.** Antes do início operacional válido do Pedido Comercial, a remuneração contratual própria da SmallFlags permanecerá sujeita às regras de cancelamento e reembolso deste Acordo, sem prejuízo dos custos físicos legítimos previstos. **A partir da autorização e do início operacional válido do Pedido, a parcela operacional principal e a parcela QA do respectivo Pedido ficam contratualmente adquiridas pela SmallFlags**, em razão dos serviços de formação, intermediação, preparação, sistemas e ativação já executados. Se o encerramento decorrer de inadimplemento material imputável à própria SmallFlags, haverá apuração específica e, quando cabível, restituição proporcional, sem retenção absoluta por falha da própria SmallFlags. A classificação contábil e tributária seguirá as regras aplicáveis independentemente deste marco comercial.

**10.13.** A conversão do BENEFÍCIO DIRETO prevista na cláusula 6 não autorizará, por si só, a PARCEIRA a interromper unilateralmente a operação. Os participantes continuarão segundo a programação operacional, desde que permaneçam presentes condições financeiras, materiais, legais e de segurança adequadas.

**10.14. Força maior e impossibilidade externa.** Nenhuma disposição obriga a continuidade da atividade em situação de risco grave, ordem de autoridade, desastre, fechamento obrigatório ou outra impossibilidade material, jurídica ou operacional não imputável à PARCEIRA, ao MEI ou à SmallFlags. Quando materialmente possível, a execução será suspensa e reprogramada dentro da mesma relação contratual; tudo o que já tiver sido efetivamente executado e validamente constituído será preservado. Atividade não executada não gera automaticamente contraprestação integral. Se a impossibilidade for definitiva, a participação ou o Pedido afetado será encerrado com registro específico e reconciliação aplicável, sem atribuição artificial de culpa.

**10.15. Impossibilidade causada exclusivamente pela PARCEIRA após aceite.** Se uma participação já aceita tornar-se impossível por ação ou omissão exclusiva da PARCEIRA — incluindo fechamento voluntário da unidade, impedimento de acesso, cancelamento unilateral da atividade ou criação de obstáculo equivalente — não haverá transferência automática do MEI para outro parceiro, CNPJ, nicho ou participação. O evento será registrado como **cancelamento imputável à PARCEIRA**. Não será criada prestação fictícia nem exigida NFS-e de R$ 141,99 se nenhum serviço tiver sido executado. O que tiver sido efetivamente executado permanecerá preservado e será apurado segundo a realidade da prestação; eventual compensação específica por cancelamento será tratada separadamente da contraprestação ordinária e sujeita ao tratamento jurídico/fiscal aplicável.

**10.16. Indisponibilidade material do SmallFlags App/Site.** Indisponibilidade comprovadamente imputável à SmallFlags que impeça execução registrada, upload documental, correção ou contestação suspenderá o prazo afetado e não poderá, por si só, gerar condição NÃO AUTORIZADA, perda de contraprestação ou perda de direito de correção/contestação. A SmallFlags deverá admitir evidência alternativa adequada ou reenvio após a restauração. O prazo voltará a correr no primeiro dia útil após a normalização e a disponibilização/comunicação necessária.

## 11. Reembolsos

**11.1. Reconciliação.** Constituído o direito da PARCEIRA ao reembolso, a SmallFlags concluirá a reconciliação financeira e documental necessária para apurar o valor líquido efetivamente restituível em até **10 (dez) dias úteis**, contados do primeiro dia útil subsequente ao evento que constituiu esse direito, ressalvada necessidade objetiva de informação ou documento cuja obtenção dependa da própria PARCEIRA ou de terceiro indispensável.

**11.2. Pagamento do reembolso.** Concluída a reconciliação prevista na cláusula 11.1, a SmallFlags efetuará o pagamento do valor apurado em até **10 (dez) dias úteis**, salvo se legislação aplicável, meio de pagamento ou provedor financeiro impuser prazo menor ou procedimento obrigatório, hipótese em que prevalecerá a regra obrigatória aplicável.

**11.3.** O reembolso será realizado, sempre que tecnicamente possível, pelo mesmo meio de pagamento ou por meio alternativo seguro acordado com a PARCEIRA.

**11.4.** Nenhum reembolso comercial eliminará contraprestações legitimamente constituídas por participações executadas e aprovadas ou outros direitos já exigíveis.

**11.5.** Os componentes do Pedido deverão permanecer identificáveis de modo a distinguir parcela operacional principal da SmallFlags, parcela QA própria da SmallFlags, produção física, contraprestações ordinárias dos MEIs, valores recebidos para repasse e valores efetivamente repassados.

## 12. SmallFlags Site, Portal e SmallFlags App

**12.1.** O SmallFlags Site será a referência comercial para cadastro empresarial, representação, poderes do partner_owner, owners e managers, unidades, oportunidades, exclusividades, Pedidos Comerciais, preços, fidelidade, pagamentos, produção, cancelamentos, reembolsos e demais registros da relação comercial.

**12.2.** O SmallFlags App e seu backend operacional serão a referência para a jornada dos participantes, incluindo alocação, etapas, sessões, horas reconhecidas, progressão, documentação vinculada às participações, elegibilidade, benefícios, confirmações de uso e conclusão operacional.

**12.3.** A atribuição de competências aos sistemas não altera as relações jurídicas definidas neste Acordo e nos instrumentos específicos. A PARCEIRA continuará sendo identificada como tomadora/contraparte quando assim estabelecido no instrumento individual, e a SmallFlags exercerá intermediação e representação somente dentro dos poderes validamente concedidos.

**12.4.** O SmallFlags Site não poderá alterar diretamente registros operacionais cuja autoridade pertença ao SmallFlags App. O SmallFlags App não poderá criar ou modificar unilateralmente preço, Pedido Comercial, modalidade, empresa representada ou poderes de representação mantidos pelo Site.

**12.5.** A comunicação entre os sistemas ocorrerá exclusivamente por mecanismos autorizados de backend, com autenticação, limitação de escopo, proteção contra repetição indevida, idempotência e auditoria.

**12.6.** O navegador utilizado pela PARCEIRA, pelo MEI ou por terceiro não terá autoridade para criar ou alterar diretamente vínculos privados entre os bancos dos dois sistemas.

**12.7.** Antes da formalização digital de uma participação, deverão estar disponíveis as informações necessárias para identificar, no mínimo, PARCEIRA representada, CNPJ tomador, autorização vigente, atividade, participação, modalidade e valor individual aplicável.

**12.8.** Autorização ausente, expirada, revogada ou incompatível impedirá novas formalizações em nome da PARCEIRA até regularização.

**12.9.** Ajustes exclusivamente operacionais que preservem empresa tomadora, objeto, modalidade, valor e demais condições materiais não exigirão novo contrato comercial. Alterações materiais dependerão das manifestações e autorizações aplicáveis.

## 13. Ausência de garantia de resultado econômico

**13.1.** A SmallFlags obriga-se às prestações assumidas nos instrumentos aplicáveis, mas não garante faturamento, lucro, aumento de vendas, número específico de clientes, retorno sobre investimento ou resultado econômico determinado para a PARCEIRA.

**13.2.** A PARCEIRA é responsável por sua própria operação empresarial, atendimento, estoque, obrigações fiscais, trabalhistas, regulatórias e demais deveres que lhe sejam próprios.

## 14. Marca, materiais e propriedade intelectual

**14.1.** Cada parte permanece titular de suas marcas, nomes, conteúdos, sistemas, documentos, métodos e demais direitos preexistentes.

**14.2.** Quando a PARCEIRA fornecer marca, logotipo, imagem, arte ou outro material para personalização, declara possuir os direitos ou autorizações necessários para o uso informado.

**14.3.** A PARCEIRA concede à SmallFlags licença limitada, não exclusiva e restrita ao tempo e à finalidade necessários para executar o Pedido Comercial, produzir materiais contratados, exibi-los nos ambientes aplicáveis e prestar suporte relacionado à operação.

**14.4.** O uso da marca da PARCEIRA para publicidade, testemunho, campanha institucional ou marketing da SmallFlags dependerá de autorização separada, salvo uso estritamente necessário à execução contratual.

**14.5.** Havendo alegação plausível de violação de direito de terceiro, a SmallFlags poderá suspender o uso ou a produção do material questionado enquanto o caso for esclarecido.

## 15. Confidencialidade

**15.1.** As partes protegerão informações empresariais não públicas recebidas em razão da relação, utilizando-as apenas para execução, suporte, segurança, auditoria, cumprimento legal ou defesa de direitos.

**15.2.** Não serão consideradas confidenciais informações que sejam públicas sem violação deste Acordo, já fossem legitimamente conhecidas pela parte receptora, tenham sido obtidas licitamente de terceiro ou devam ser divulgadas por obrigação legal ou ordem de autoridade.

**15.3.** A obrigação de confidencialidade sobre informação que permaneça legitimamente sigilosa continuará enquanto essa natureza subsistir.

## 16. Dados pessoais e segurança

**16.1.** O tratamento de dados pessoais observará o Aviso de Privacidade SmallFlags vigente e a legislação aplicável.

**16.2.** Cada parte é responsável pelos tratamentos de dados que realizar sob sua própria autoridade e finalidade.

**16.3.** A PARCEIRA deverá limitar o acesso de owners, managers e colaboradores às pessoas que efetivamente necessitem utilizar o serviço.

**16.4.** Suspeitas de comprometimento de credenciais, fraude ou acesso indevido deverão ser comunicadas sem demora indevida.

## 17. Comunicações, notificações e registros

**17.1.** Comunicações comerciais, operacionais e contratuais poderão ser realizadas pelo Portal SmallFlags, endereço eletrônico cadastrado e demais canais oficiais expressamente disponibilizados pela SmallFlags.

**17.2.** A PARCEIRA deverá manter atualizados seus contatos e dados de representantes e acompanhar as comunicações relacionadas aos Pedidos Comerciais.

**17.3.** Quando este Acordo estabelecer prazo contado de notificação, a SmallFlags conservará evidência suficiente do envio e, quando exigido pela natureza do ato, de sua entrega ou disponibilização ao destinatário.

**17.4.** Notificações relativas à insuficiência de recursos ou falha na contraprestação em BENEFÍCIO DIRETO deverão identificar a ocorrência, o Pedido Comercial afetado, a falha observada e, quando possível, as participações impactadas, de forma suficientemente clara para permitir regularização.

**17.5.** O prazo de 2 (dois) dias úteis para regularização previsto na cláusula 6 será contado em dias úteis e não constituirá nova carência para obrigações já vencidas ou exigíveis.

**17.6.** Poderão ser conservados registros de versão, identidade do signatário, data e hora, referência documental, hash criptográfico, eventos de envio, aceite, autorização, revogação e demais evidências pertinentes.

**17.7. Fallback de comunicação.** O App/Portal continuará sendo o canal primário quando assim definido para o ato. Se houver indisponibilidade material que impeça a regular disponibilização de comunicação capaz de iniciar prazo, será utilizado canal oficial alternativo registrado, como e-mail cadastrado, quando tecnicamente disponível e adequado; não sendo possível, o prazo somente começará após a restauração e a regular disponibilização, sem prejuízo do destinatário.

## 18. Vigência, suspensão e encerramento

**18.1.** Este Acordo entrará em vigor com sua assinatura ou aceite válido e permanecerá vigente enquanto existir relação comercial, salvo substituição ou encerramento regular.

**18.2.** Nova versão somente substituirá a versão vigente após manifestação válida da PARCEIRA e registro da nova versão. Versões anteriores permanecerão preservadas quando necessárias para histórico, prova e auditoria.

**18.3.** O encerramento do Acordo impedirá novas contratações futuras, mas não extinguirá automaticamente Pedidos Comerciais, participações, pagamentos, produção, reembolsos ou demais obrigações legitimamente constituídas antes de sua eficácia.

**18.4.** A revogação da autorização para representação impedirá novas formalizações em nome da PARCEIRA após sua eficácia, sem prejudicar contratos validamente celebrados, serviços já prestados ou obrigações econômicas já constituídas.

**18.5.** A SmallFlags poderá suspender novas contratações ou funcionalidades diante de fraude, risco de segurança, insuficiência de poderes, inadimplemento relevante ou obrigação legal, adotando medida compatível com a natureza do risco e mantendo registro da decisão.

**18.6.** A suspensão não autorizará eliminação ou alteração retroativa de registros, participações ou contraprestações existentes.

**18.7.** Na modalidade BENEFÍCIO DIRETO, a obrigação de pagamento do saldo não cumprido validamente convertido sobreviverá a eventual pedido posterior de encerramento ou revogação da relação.

**18.8.** A conversão não interromperá, por si só, as atividades de operação já iniciada. A PARCEIRA permanecerá obrigada a fornecer condições necessárias à execução enquanto a continuidade for material, jurídica e operacionalmente possível.

**18.9.** Obrigações referentes a serviços já executados, contraprestações, saldo convertido, produção realizada, reembolsos, proteção de dados, confidencialidade, auditoria e demais deveres que, por sua natureza, devam subsistir permanecerão vigentes após o encerramento.

## 19. Formalização, assinatura e evidências

**19.1.** Este Acordo, os Pedidos Comerciais, autorizações de representação e demais instrumentos vinculados poderão ser formalizados por meio físico ou eletrônico, desde que o procedimento permita comprovar adequadamente a manifestação das partes.

**19.2.** Nas primeiras contratações presenciais, o instrumento assinado fisicamente poderá ser digitalizado integralmente e registrado no SmallFlags Site com identificação, versão, data e demais evidências pertinentes.

**19.3.** A outorga expressa de representação prevista no Pedido Comercial deverá ser assinada ou aceita de forma destacada pelo partner_owner ou por representante com poderes suficientes e deverá identificar, no mínimo: local e data; qualificação do outorgante e da SmallFlags; empresa/CNPJ representado; Pedido Comercial abrangido; período de validade; poder específico para apresentar e formalizar contratos digitais de participação de MEIs em nome da PARCEIRA; atividade, nicho, região e CNPJ tomador; valor de **R$ 141,99 por participação** e limite econômico máximo do Pedido; modalidade DINHEIRO ou BENEFÍCIO DIRETO; e proibição de modificar esses elementos sem nova autorização válida.

**19.4.** A assinatura geral de um pedido não será interpretada como autorização genérica e ilimitada para modificar empresa tomadora, objeto, modalidade, valores ou contratar em nome de CNPJs não abrangidos pela autorização existente.

**19.5.** Nos instrumentos eletrônicos, deverão ser preservados elementos suficientes para demonstrar, conforme o procedimento homologado: identidade ou referência do signatário; empresa representada; poderes aplicáveis; versão integral; data e hora; manifestação afirmativa; e integridade do conteúdo aceito.

**19.6.** A versão final de cada instrumento poderá receber hash criptográfico ou mecanismo equivalente de integridade associado à referência documental armazenada.

**19.7.** Alterações materiais posteriores à assinatura ou aceite exigirão nova manifestação válida quando modificarem direitos, obrigações ou condições dependentes de concordância.

**19.8.** É vedada substituição silenciosa do conteúdo de instrumento já formalizado. Versões anteriores deverão permanecer preservadas quando necessárias à prova, auditoria ou cumprimento de obrigações.

**19.9.** O MEI deverá ter acesso às condições específicas de suas participações antes do respectivo aceite, inclusive empresa/CNPJ tomador, atividade, local, período, modalidade e valor econômico aplicável. O fluxo utilizará **dois níveis de consentimento**: (a) aceite geral do Termo Digital do MEI, uma vez por versão; e (b) **aceite individual e separado de cada participação**, inclusive supermercado etapa 1 e supermercado etapa 2, com `participation_id`, snapshot das condições, data/hora, versão/hash e manifestação afirmativa próprios. A recusa de uma oferta específica não equivalerá a recusa do Termo geral nem autorizará punição automática.

**19.10.** O procedimento definitivo de assinatura eletrônica e guarda das evidências somente será habilitado em produção após validação jurídica e homologação técnica.

## 20. Lei aplicável, boa-fé e solução de divergências

**20.1.** Este Acordo é regido pelas leis da República Federativa do Brasil.

**20.2.** As partes atuarão segundo deveres de boa-fé, probidade, cooperação e lealdade na formação, execução e encerramento da relação.

**20.3.** Antes de medida judicial, as partes buscarão resolver divergências comerciais por comunicação formal e tentativa de composição, sem impedir medida urgente ou exercício de direito que não admita espera.

**20.4.** Fica eleito o foro da Comarca de Viana, Estado do Espírito Santo, para controvérsias decorrentes deste Acordo que não sejam resolvidas consensualmente, ressalvadas competências obrigatórias e regras legais aplicáveis.

---

## ASSINATURAS — MODELO

**SMALLFLAGS / OPERADOR**  
58.852.870 JULIANO RANGEL NEVES HAYASHI  
CNPJ 58.852.870/0001-79  
Endereço: Avenida Minas Gerais, Quadra 19, Casa nº 08, Marcílio de Noronha, Viana/ES, Brasil  
Representante: ______________________________  
Data: ____/____/________  
Assinatura / referência: ______________________________

**PARCEIRA**  
Razão social: ______________________________  
CNPJ: ______________________________  
partner_owner / representante: ______________________________  
CPF: ______________________________  
Cargo / poderes: ______________________________  
Data: ____/____/________  
Assinatura / referência: ______________________________

---

## BLOQUEADORES REMANESCENTES PARA VERSÃO ASSINÁVEL

1. Revisão jurídica profissional final e dirigida da representação da PARCEIRA, contratação dos MEIs, revogação, autonomia operacional, efeitos de cancelamento/encerramento e mecanismo de conversão do saldo não cumprido no BENEFÍCIO DIRETO.
2. Revisão contábil/fiscal final e dirigida do procedimento de NFS-e dos MEIs para o CNPJ tomador, trânsito de valores de terceiros pela SmallFlags, escrituração dos repasses, BENEFÍCIO DIRETO e faturamento exclusivo da receita própria da SmallFlags.
3. Definir com o contador o procedimento de desenquadramento da SmallFlags como MEI e a adequação de CNAEs/regime tributário. Como política empresarial interna, o gatilho pretendido é a conclusão dos seis contratos iniciais, salvo obrigação legal anterior.
4. Homologar tecnicamente no App e no Site: R$ 141,99 por participação; R$ 993,93 de contraprestações ordinárias por trajetória completa; parcela QA de R$ 5,07 pertencente à SmallFlags; ledger dos repasses; snapshots imutáveis; aceite geral do Termo e sete aceites individuais por participação; versão/hash; poderes ativos; ledger/reconciliação; sequência fiscal/documental; e fluxo de falha/regularização/conversão do saldo.
5. Auditar os seis contratos presenciais e o contrato digital do MEI contra esta versão consolidada.
6. Obter revisão jurídica e contábil final antes de retirar a marcação de MINUTA e habilitar assinatura/aceite em produção.
$ACORDO_MESTRE_V098$,
     v_hash,
     'published',
     false,
     pg_catalog.now(),
     pg_catalog.now(),
     v_admin,
     'Publicacao de QA em staging a partir do conteudo congelado v0.9.8. '
     'NAO e instrumento assinavel: o documento declara DRAFT e lista '
     'bloqueadores pendentes de revisao juridica e contabil.');

  -- Conferência do hash contra o conteúdo efetivamente gravado.
  SELECT pg_catalog.encode(
           extensions.digest(d.content, 'sha256'), 'hex')
    INTO v_calc
    FROM public.legal_documents d
   WHERE d.doc_type = 'master_agreement'
     AND d.version  = 'QA-STAGING-MASTER-DRAFT-v0.9.8';

  IF v_calc IS DISTINCT FROM v_hash THEN
    RAISE EXCEPTION
      'ABORTADO: hash gravado nao confere com o conteudo (esperado %, obtido %). '
      'Requer a extensao pgcrypto; sem ela, confira o hash fora do banco.',
      v_hash, v_calc;
  END IF;

  RAISE NOTICE 'Publicado em staging: master_agreement QA-STAGING-MASTER-DRAFT-v0.9.8';
END
$pub$;

COMMIT;
