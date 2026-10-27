-- SMALLFLAGS SITE — ONBOARDING LEGAL PUBLICATION V1
-- Staging first. Production requires separate explicit authorization.
-- Publishes canonical onboarding documents and makes privacy_notice visible
-- before partner-application submission.

BEGIN;

CREATE OR REPLACE FUNCTION public.m1_doc_types_solicitacao()
RETURNS text[]
LANGUAGE sql IMMUTABLE
SET search_path TO 'pg_catalog'
AS $$
  SELECT ARRAY[
    'privacy_notice',
    'truthfulness_declaration',
    'document_analysis_authorization'
  ];
$$;

REVOKE EXECUTE ON FUNCTION public.m1_doc_types_solicitacao() FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.m1_doc_types_solicitacao() FROM service_role;

DO $publish$
DECLARE
  v_now timestamptz := pg_catalog.now();
  v_admin uuid;
  v_content text;
  v_hash text;
  v_existing public.legal_documents%ROWTYPE;
BEGIN
  SELECT user_id INTO v_admin
    FROM public.site_admins
   ORDER BY created_at, user_id
   LIMIT 1;

  IF v_admin IS NULL THEN
    RAISE EXCEPTION 'legal publication requires at least one site_admin';
  END IF;

  -- privacy_notice
  v_content := $SFLEGAL1$# SMALLFLAGS — AVISO DE PRIVACIDADE DO SITE E PORTAL DE PARCEIROS

Versão: SF-SITE-PRIVACY-2026-10-27-v1.0

## 1. Controlador e contato

Para os tratamentos próprios do Site e Portal descritos neste Aviso, o controlador é 58.852.870 JULIANO RANGEL NEVES HAYASHI, CNPJ 58.852.870/0001-79, marca SmallFlags.

Endereço: Avenida Minas Gerais, Quadra 19, Casa nº 08, Marcílio de Noronha, Viana/ES, Brasil.

Canal de privacidade e exercício de direitos: privacidade@smallflags.com.br.

## 2. Pessoas abrangidas

Este Aviso se aplica, conforme o fluxo utilizado, a responsáveis por solicitações de parceria, representantes empresariais, owners, managers, convidados do Portal e demais pessoas naturais cujos dados sejam necessários para o funcionamento, a segurança e a auditoria do Site e Portal.

## 3. Dados tratados

Conforme o fluxo, podem ser tratados:

- nome, CPF, cargo ou função, e-mail e telefone;
- CNPJ, razão social, nome fantasia, endereço, cidade, UF, unidade, nicho e região comercial;
- dados de autenticação e conta;
- vínculos de owner ou manager;
- convites, suspensões e revogações;
- documentos enviados no onboarding;
- pedidos de correção e decisões de análise;
- versões e evidências de manifestações jurídicas;
- registros de ações autorizadas no Portal;
- identificadores técnicos e registros mínimos necessários à segurança, prevenção de abuso e auditoria.

A SmallFlags orienta o usuário a não enviar dados pessoais excessivos ou documentos sem relação com a finalidade solicitada.

## 4. Finalidades

Os dados podem ser utilizados, conforme aplicável, para:

- receber e analisar solicitações de parceria;
- verificar identidade, vínculo e autoridade declarados;
- criar e administrar conta provisória;
- receber, revisar e corrigir documentos;
- comunicar andamento e decisões pelos canais ativos;
- administrar empresas aprovadas, owners, managers, unidades e convites;
- autenticar usuários e recuperar acesso;
- permitir operações autorizadas no Portal;
- processar validações relacionadas a benefícios nos limites de autoridade do Site;
- prevenir fraude, abuso e acesso indevido;
- manter segurança, integridade e trilhas de auditoria;
- cumprir obrigações legais ou regulatórias;
- exercer ou defender direitos.

## 5. Bases legais

A base legal depende da finalidade e pode incluir, conforme o caso:

- procedimentos preliminares relacionados a eventual relação contratual, a pedido do titular;
- execução de contrato;
- cumprimento de obrigação legal ou regulatória;
- exercício regular de direitos;
- legítimo interesse, quando aplicável e após avaliação de necessidade, proporcionalidade e direitos do titular;
- consentimento somente quando uma operação específica efetivamente depender dessa base.

A ciência deste Aviso não constitui consentimento genérico para todas as operações de tratamento.

## 6. Prestadores de tecnologia ativos no primeiro lançamento

### Supabase

Utilizado para banco de dados, autenticação e armazenamento privado de documentos. O projeto do Site utiliza infraestrutura principal na região us-east-1, Estados Unidos.

### Vercel

Utilizada para hospedagem do Site e execução de funções server-side. A Vercel informa que suas instalações principais de processamento estão nos Estados Unidos e que pode utilizar subprocessadores para prestar o serviço.

Novos fornecedores materiais serão incorporados ao inventário e a este Aviso antes de sua ativação quando isso alterar de forma relevante os tratamentos aqui descritos.

## 7. Tratamento e transferência internacional

A arquitetura do Site pode envolver armazenamento, acesso ou processamento de dados pessoais fora do Brasil, principalmente nos Estados Unidos.

A transferência pode ocorrer por transmissão eletrônica criptografada e pelo armazenamento ou processamento remoto necessários à hospedagem, autenticação, banco de dados, armazenamento privado de documentos, segurança e funcionamento do Site e Portal.

Para os dados necessários ao onboarding empresarial, aos procedimentos preliminares solicitados pelo titular e à execução da relação contratual, a SmallFlags adota, quando caracterizada transferência internacional sujeita à LGPD, o mecanismo previsto no art. 33, IX, combinado com o art. 7º, V, da LGPD.

Se uma futura finalidade ou operação de transferência não puder ser legitimamente enquadrada nesse mecanismo, ela somente deverá ser ativada após a adoção de outro mecanismo válido previsto no art. 33 da LGPD.

Os fornecedores contratados devem tratar os dados de acordo com as instruções e finalidades aplicáveis à prestação dos serviços. Podem ocorrer transferências posteriores a subprocessadores necessários à prestação, sujeitas aos controles contratuais e de segurança dos respectivos fornecedores.

## 8. Responsabilidades e segurança

A SmallFlags decide as finalidades e os meios essenciais dos tratamentos sob sua responsabilidade. Prestadores de infraestrutura tratam dados para a prestação dos serviços contratados, conforme seus contratos e obrigações aplicáveis.

São adotadas medidas técnicas e administrativas compatíveis com os riscos, incluindo autenticação, autorização por escopo, restrição de acesso a documentos, armazenamento privado, segregação entre componentes, criptografia em trânsito quando suportada pelo serviço e trilhas de auditoria.

Nenhum sistema é absolutamente imune a incidentes.

## 9. Integração Site e App

O Site e o App SmallFlags possuem domínios técnicos separados. O Site mantém os registros empresariais e autorizações de parceiro sob sua responsabilidade; o App mantém os estados operacionais de participantes e benefícios sob sua responsabilidade.

A integração é realizada por mecanismos autorizados entre backends, com controles de acesso, integridade e auditoria. Credenciais servidor-servidor não são disponibilizadas ao navegador.

## 10. Retenção

Os dados são mantidos pelo período necessário às finalidades informadas, à análise e manutenção da relação, ao cumprimento de obrigações legais ou regulatórias, à segurança, à auditoria e ao exercício regular de direitos.

Quando a finalidade terminar e não houver fundamento para conservação, serão adotadas medidas juridicamente adequadas de eliminação, anonimização ou outra destinação permitida.

## 11. Direitos do titular

Nos termos e limites da legislação aplicável, o titular poderá solicitar, conforme cabível:

- confirmação da existência de tratamento;
- acesso;
- correção;
- informações sobre compartilhamentos;
- anonimização, bloqueio ou eliminação de dados desnecessários, excessivos ou tratados em desconformidade;
- portabilidade quando regulamentada e cabível;
- eliminação de dados tratados com consentimento, ressalvadas hipóteses legais de conservação;
- informação sobre a possibilidade de não consentir e suas consequências, quando o consentimento for utilizado;
- revogação do consentimento;
- oposição nos casos previstos em lei;
- revisão de decisões tomadas unicamente com base em tratamento automatizado que afetem seus interesses;
- demais direitos assegurados pela LGPD.

Canal: privacidade@smallflags.com.br.

Caso uma solicitação apresentada ao controlador não seja solucionada, o titular poderá utilizar os canais cabíveis da Autoridade Nacional de Proteção de Dados, observados os requisitos aplicáveis.

## 12. Atualizações

Cada versão deste Aviso possui identidade própria. Registros de ciência e aceites históricos não são atribuídos automaticamente a uma versão posterior.

Mudanças materiais serão apresentadas conforme o fluxo aplicável e, quando necessário, exigirão nova manifestação.
$SFLEGAL1$;
  v_hash := pg_catalog.encode(extensions.digest(v_content, 'sha256'), 'hex');

  SELECT * INTO v_existing
    FROM public.legal_documents
   WHERE doc_type = 'privacy_notice'
     AND version = 'SF-SITE-PRIVACY-2026-10-27-v1.0'
   LIMIT 1;

  IF FOUND THEN
    IF v_existing.content_hash IS DISTINCT FROM v_hash
       OR v_existing.content IS DISTINCT FROM v_content THEN
      RAISE EXCEPTION 'version conflict for privacy_notice SF-SITE-PRIVACY-2026-10-27-v1.0';
    END IF;

    IF v_existing.status <> 'published'
       OR v_existing.effective_to IS NOT NULL THEN
      RAISE EXCEPTION 'existing legal version is not current published: privacy_notice SF-SITE-PRIVACY-2026-10-27-v1.0';
    END IF;
  ELSE
    UPDATE public.legal_documents
       SET status = 'archived',
           effective_to = COALESCE(effective_to, v_now),
           updated_at = v_now
     WHERE doc_type = 'privacy_notice'
       AND status = 'published'
       AND (effective_to IS NULL OR effective_to > v_now);

    INSERT INTO public.legal_documents
      (doc_type, version, title, content, content_url, content_hash,
       status, is_material_change, effective_from, effective_to,
       published_at, published_by, notes)
    VALUES
      ('privacy_notice',
       'SF-SITE-PRIVACY-2026-10-27-v1.0',
       'Aviso de Privacidade do Site e Portal de Parceiros',
       v_content,
       NULL,
       v_hash,
       'published',
       true,
       v_now,
       NULL,
       v_now,
       v_admin,
       'SmallFlags first-GO onboarding legal publication; prepared 2026-10-27.');
  END IF;

  -- truthfulness_declaration
  v_content := $SFLEGAL2$# SMALLFLAGS — DECLARAÇÃO DE VERACIDADE DA SOLICITAÇÃO DE PARCERIA

Versão: SF-SITE-TRUTH-2026-10-27-v1.0

Esta declaração acompanha a solicitação de parceria empresarial enviada à SmallFlags.

Ao marcar a opção correspondente e enviar a solicitação, o responsável declara, sob sua responsabilidade, que:

1. os dados empresariais informados correspondem, segundo seu conhecimento, à situação real da empresa;
2. seus dados pessoais e profissionais são verdadeiros, completos e atualizados;
3. o cargo, função ou vínculo informado com a empresa corresponde à situação existente no momento da solicitação;
4. os documentos enviados são autênticos ou reproduções fiéis dos documentos que representam, sem adulteração intencional;
5. não omitiu deliberadamente informação material solicitada para análise;
6. comunicará ou corrigirá informação relevante caso identifique erro, desatualização ou mudança durante a análise;
7. está ciente de que inconsistências, informações materialmente incorretas, documentos inválidos ou impossibilidade de comprovação podem resultar em pedido de correção, suspensão da análise, rejeição ou encerramento da solicitação, sem prejuízo das medidas cabíveis segundo a legislação aplicável.

Esta declaração não substitui prova de representação ou de poderes quando a SmallFlags exigir comprovação específica; não concede poderes que o declarante não possua; não equivale a aprovação da empresa ou do responsável; e não cria contrato, exclusividade, compra, pagamento ou início de operação.

O aceite fica vinculado ao identificador, à versão e ao hash exatos deste documento. Uma versão posterior não será considerada automaticamente aceita.
$SFLEGAL2$;
  v_hash := pg_catalog.encode(extensions.digest(v_content, 'sha256'), 'hex');

  SELECT * INTO v_existing
    FROM public.legal_documents
   WHERE doc_type = 'truthfulness_declaration'
     AND version = 'SF-SITE-TRUTH-2026-10-27-v1.0'
   LIMIT 1;

  IF FOUND THEN
    IF v_existing.content_hash IS DISTINCT FROM v_hash
       OR v_existing.content IS DISTINCT FROM v_content THEN
      RAISE EXCEPTION 'version conflict for truthfulness_declaration SF-SITE-TRUTH-2026-10-27-v1.0';
    END IF;

    IF v_existing.status <> 'published'
       OR v_existing.effective_to IS NOT NULL THEN
      RAISE EXCEPTION 'existing legal version is not current published: truthfulness_declaration SF-SITE-TRUTH-2026-10-27-v1.0';
    END IF;
  ELSE
    UPDATE public.legal_documents
       SET status = 'archived',
           effective_to = COALESCE(effective_to, v_now),
           updated_at = v_now
     WHERE doc_type = 'truthfulness_declaration'
       AND status = 'published'
       AND (effective_to IS NULL OR effective_to > v_now);

    INSERT INTO public.legal_documents
      (doc_type, version, title, content, content_url, content_hash,
       status, is_material_change, effective_from, effective_to,
       published_at, published_by, notes)
    VALUES
      ('truthfulness_declaration',
       'SF-SITE-TRUTH-2026-10-27-v1.0',
       'Declaração de Veracidade da Solicitação de Parceria',
       v_content,
       NULL,
       v_hash,
       'published',
       true,
       v_now,
       NULL,
       v_now,
       v_admin,
       'SmallFlags first-GO onboarding legal publication; prepared 2026-10-27.');
  END IF;

  -- document_analysis_authorization
  v_content := $SFLEGAL3$# SMALLFLAGS — AUTORIZAÇÃO DE ANÁLISE DOCUMENTAL DA SOLICITAÇÃO DE PARCERIA

Versão: SF-SITE-DOC-AUTH-2026-10-27-v1.0

Esta autorização disciplina a análise dos dados e documentos apresentados na solicitação de parceria empresarial. Ela não constitui contrato comercial e não garante aprovação.

Ao marcar a opção correspondente e enviar a solicitação, o responsável autoriza a SmallFlags, no limite necessário ao processo de onboarding, a:

1. receber, armazenar, organizar e revisar os documentos enviados;
2. verificar legibilidade, integridade aparente, validade, coerência e correspondência entre documentos e dados informados;
3. conferir dados cadastrais da empresa, do responsável e da representação declarada;
4. comparar as informações apresentadas com documentos enviados e, quando necessário e juridicamente permitido, com cadastros públicos, registros públicos e fontes oficiais pertinentes;
5. solicitar esclarecimentos, correções, complementações ou substituição de documentos;
6. registrar histórico da análise, incluindo versões substituídas, pedidos de correção, decisões e evidências;
7. permitir acesso aos documentos somente a pessoas e prestadores autorizados que deles necessitem para análise, segurança, auditoria, suporte técnico ou cumprimento de obrigação legal aplicável.

Esta autorização não constitui autorização genérica para qualquer tratamento de dados e, por si só, não autoriza consulta indiscriminada a bases privadas, acesso a informações protegidas por sigilo legal, consulta a bureau ou score de crédito, marketing ou compartilhamento sem finalidade e fundamento jurídico.

O tratamento de dados pessoais continua sujeito à LGPD, ao Aviso de Privacidade vigente e às bases legais aplicáveis. Esta autorização procedimental não substitui as bases legais exigidas pela legislação.

O aceite fica vinculado ao identificador, à versão e ao hash exatos deste documento.
$SFLEGAL3$;
  v_hash := pg_catalog.encode(extensions.digest(v_content, 'sha256'), 'hex');

  SELECT * INTO v_existing
    FROM public.legal_documents
   WHERE doc_type = 'document_analysis_authorization'
     AND version = 'SF-SITE-DOC-AUTH-2026-10-27-v1.0'
   LIMIT 1;

  IF FOUND THEN
    IF v_existing.content_hash IS DISTINCT FROM v_hash
       OR v_existing.content IS DISTINCT FROM v_content THEN
      RAISE EXCEPTION 'version conflict for document_analysis_authorization SF-SITE-DOC-AUTH-2026-10-27-v1.0';
    END IF;

    IF v_existing.status <> 'published'
       OR v_existing.effective_to IS NOT NULL THEN
      RAISE EXCEPTION 'existing legal version is not current published: document_analysis_authorization SF-SITE-DOC-AUTH-2026-10-27-v1.0';
    END IF;
  ELSE
    UPDATE public.legal_documents
       SET status = 'archived',
           effective_to = COALESCE(effective_to, v_now),
           updated_at = v_now
     WHERE doc_type = 'document_analysis_authorization'
       AND status = 'published'
       AND (effective_to IS NULL OR effective_to > v_now);

    INSERT INTO public.legal_documents
      (doc_type, version, title, content, content_url, content_hash,
       status, is_material_change, effective_from, effective_to,
       published_at, published_by, notes)
    VALUES
      ('document_analysis_authorization',
       'SF-SITE-DOC-AUTH-2026-10-27-v1.0',
       'Autorização de Análise Documental da Solicitação de Parceria',
       v_content,
       NULL,
       v_hash,
       'published',
       true,
       v_now,
       NULL,
       v_now,
       v_admin,
       'SmallFlags first-GO onboarding legal publication; prepared 2026-10-27.');
  END IF;

  -- provisional_account_terms
  v_content := $SFLEGAL4$# SMALLFLAGS — TERMOS DA CONTA PROVISÓRIA DE PARCEIRO

Versão: SF-SITE-PROVISIONAL-2026-10-27-v1.0

## 1. Conta provisória

A conta provisória é um acesso temporário ao ambiente SmallFlags destinado exclusivamente ao acompanhamento da solicitação de parceria empresarial.

Ela é utilizada depois das etapas de confirmação de identidade e antes da conclusão da análise da empresa e da autoridade do responsável.

A existência da conta provisória não significa aprovação da parceria.

## 2. Uso permitido

Enquanto a solicitação estiver em análise, a conta provisória poderá permitir, conforme o estado do processo:

- consultar andamento e pendências;
- enviar ou reenviar documentos;
- responder pedidos de correção;
- acompanhar decisões;
- desistir da solicitação quando o fluxo aplicável permitir;
- executar outras ações estritamente relacionadas ao onboarding.

## 3. Limitações

A conta provisória:

- não equivale a conta de parceiro aprovado;
- não confere automaticamente função de owner;
- não concede acesso reservado a parceiro aprovado;
- não cria exclusividade comercial;
- não reserva oportunidade comercial;
- não cria contrato, compra ou obrigação de pagamento;
- não autoriza início de produção;
- não cria ou altera ciclo operacional no App;
- não garante aprovação futura.

## 4. Análise e correções

A SmallFlags poderá analisar separadamente a empresa, a autoridade declarada do responsável e os documentos apresentados.

Poderá solicitar esclarecimentos, documentos complementares, substituições ou correções. O envio de correção não implica aprovação automática.

## 5. Segurança

O usuário deve manter credenciais e links de uso único sob seu controle, não compartilhar senha ou mecanismo pessoal de acesso, comunicar suspeita de comprometimento e utilizar a conta somente no contexto para o qual estiver autorizado.

A SmallFlags poderá aplicar bloqueio temporário, invalidação de token, encerramento de sessão ou exigência de nova autenticação diante de risco, abuso ou inconsistência.

## 6. Documentos e privacidade

O usuário deve enviar apenas documentos pertinentes ao processo. Reenvios poderão preservar histórico técnico e de auditoria.

O tratamento de dados pessoais relacionado à conta provisória segue o Aviso de Privacidade vigente.

## 7. Ausência de contratação comercial nesta etapa

A conta provisória integra o onboarding.

Qualquer contratação comercial futura dependerá de instrumentos, aprovações e condições próprias. Estes Termos não substituem Acordo Mestre, Pedido Comercial, instrumento de pagamento ou outro contrato específico.

## 8. Versão e aceite

O aceite será registrado em relação à versão exata deste documento, com identificador e hash correspondentes.

Uma nova versão não será considerada automaticamente aceita.
$SFLEGAL4$;
  v_hash := pg_catalog.encode(extensions.digest(v_content, 'sha256'), 'hex');

  SELECT * INTO v_existing
    FROM public.legal_documents
   WHERE doc_type = 'provisional_account_terms'
     AND version = 'SF-SITE-PROVISIONAL-2026-10-27-v1.0'
   LIMIT 1;

  IF FOUND THEN
    IF v_existing.content_hash IS DISTINCT FROM v_hash
       OR v_existing.content IS DISTINCT FROM v_content THEN
      RAISE EXCEPTION 'version conflict for provisional_account_terms SF-SITE-PROVISIONAL-2026-10-27-v1.0';
    END IF;

    IF v_existing.status <> 'published'
       OR v_existing.effective_to IS NOT NULL THEN
      RAISE EXCEPTION 'existing legal version is not current published: provisional_account_terms SF-SITE-PROVISIONAL-2026-10-27-v1.0';
    END IF;
  ELSE
    UPDATE public.legal_documents
       SET status = 'archived',
           effective_to = COALESCE(effective_to, v_now),
           updated_at = v_now
     WHERE doc_type = 'provisional_account_terms'
       AND status = 'published'
       AND (effective_to IS NULL OR effective_to > v_now);

    INSERT INTO public.legal_documents
      (doc_type, version, title, content, content_url, content_hash,
       status, is_material_change, effective_from, effective_to,
       published_at, published_by, notes)
    VALUES
      ('provisional_account_terms',
       'SF-SITE-PROVISIONAL-2026-10-27-v1.0',
       'Termos da Conta Provisória de Parceiro',
       v_content,
       NULL,
       v_hash,
       'published',
       true,
       v_now,
       NULL,
       v_now,
       v_admin,
       'SmallFlags first-GO onboarding legal publication; prepared 2026-10-27.');
  END IF;

END
$publish$;

COMMIT;