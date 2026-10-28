-- Move os aceites de onboarding para depois do cadastro inicial.
-- O cadastro publico deixa de exigir checkbox juridico; a etapa autenticada
-- de conta provisoria passa a concentrar os quatro documentos de onboarding.

CREATE OR REPLACE FUNCTION public.m1_doc_types_solicitacao()
RETURNS text[]
LANGUAGE sql IMMUTABLE
SET search_path TO 'pg_catalog'
AS $$
  SELECT ARRAY[]::text[];
$$;

REVOKE EXECUTE ON FUNCTION public.m1_doc_types_solicitacao() FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.m1_doc_types_solicitacao() FROM service_role;

COMMENT ON FUNCTION public.m1_doc_types_solicitacao() IS
  'Cadastro inicial nao coleta aceite juridico. Os aceites sao coletados apos o cadastro, na ativacao da conta provisoria.';

CREATE OR REPLACE FUNCTION public.m1_doc_types_conta_provisoria()
RETURNS text[]
LANGUAGE sql IMMUTABLE
SET search_path TO 'pg_catalog'
AS $$
  SELECT ARRAY[
    'privacy_notice',
    'provisional_account_terms',
    'truthfulness_declaration',
    'document_analysis_authorization'
  ]::text[];
$$;

REVOKE EXECUTE ON FUNCTION public.m1_doc_types_conta_provisoria() FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.m1_doc_types_conta_provisoria() FROM service_role;

COMMENT ON FUNCTION public.m1_doc_types_conta_provisoria() IS
  'Documentos aceitos explicitamente apos o cadastro e antes do claim da conta provisoria.';
