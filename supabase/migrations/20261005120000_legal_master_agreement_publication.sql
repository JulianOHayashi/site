-- ---------------------------------------------------------------------------
-- Publicação legal do Acordo Mestre: tipo de documento e leitura histórica
--
-- POR QUE ESTA MIGRATION EXISTE
--
-- `legal_documents` não tinha um doc_type capaz de representar o Acordo Mestre
-- de Parceria Comercial. O que existia era `commercial_master_agreements`, que
-- é coisa diferente: cada linha ali tem `company_id NOT NULL` e registra que
-- UMA empresa ASSINOU um acordo. Isso é prova de assinatura, não publicação.
-- Sem um doc_type próprio, a página pública do Mestre não teria de onde ler, e
-- o aceite comercial não teria como apontar para a versão exata publicada.
--
-- A segunda peça é a leitura de UMA versão histórica. `get_current_legal_documents`
-- devolve só o que está vigente agora, o que basta para a página corrente mas
-- não para um link a um contrato antigo. Um pedido assinado sob a versão X
-- precisa continuar exibindo a versão X depois que a X+1 for publicada — do
-- contrário a página reescreveria, na prática, o contrato já aceito.
--
-- O QUE ESTA MIGRATION NÃO FAZ
--
-- Não publica documento nenhum. Não cria, altera ou arquiva linha de
-- `legal_documents`, e não toca as linhas SANDBOX existentes. Publicação de
-- conteúdo é assunto do seed de staging, separado e marcado como tal.
-- ---------------------------------------------------------------------------

-- 1. doc_type do Acordo Mestre -----------------------------------------------
--
-- A lista anterior é preservada integralmente; só se acrescenta um valor. Os
-- CHECKs de completude (`legal_documents_published_complete` e
-- `legal_documents_archived_complete`) continuam valendo e seguem exigindo
-- conteúdo, content_hash, published_at, published_by e effective_from para
-- qualquer linha publicada — inclusive a do Mestre.

ALTER TABLE public.legal_documents
  DROP CONSTRAINT legal_documents_type_allowed;

ALTER TABLE public.legal_documents
  ADD CONSTRAINT legal_documents_type_allowed
  CHECK (doc_type = ANY (ARRAY[
    'privacy_notice',
    'provisional_account_terms',
    'truthfulness_declaration',
    'document_analysis_authorization',
    'representation_declaration',
    'future_commercial_terms',
    'commercial_order_terms',
    -- Acordo Mestre de Parceria Comercial: regras gerais e permanentes da
    -- relação com a empresa parceira. Não é o Pedido Comercial, que continua
    -- em 'commercial_order_terms'.
    'master_agreement']));

COMMENT ON CONSTRAINT legal_documents_type_allowed ON public.legal_documents IS
  'Tipos de documento legal publicáveis. master_agreement é o texto público do '
  'Acordo Mestre; commercial_master_agreements continua registrando a '
  'assinatura por empresa, que é outra coisa.';

-- 2. Leitura pública de UMA versão, inclusive histórica -----------------------
--
-- SECURITY DEFINER com search_path fixo, como as demais funções públicas deste
-- schema. Devolve somente linhas 'published' ou 'archived': rascunho nunca
-- aparece, nem por versão exata. 'archived' é incluído de propósito — é o
-- estado de uma versão substituída, e é exatamente ela que um contrato antigo
-- precisa poder exibir.
--
-- STABLE e sem escrita: a página pública não muta dado algum.

CREATE OR REPLACE FUNCTION public.get_legal_document_version(
  p_doc_type text,
  p_version  text
)
RETURNS TABLE(
  doc_type           text,
  version            text,
  title              text,
  content            text,
  content_url        text,
  content_hash       text,
  status             text,
  is_material_change boolean,
  effective_from     timestamp with time zone,
  effective_to       timestamp with time zone,
  published_at       timestamp with time zone
)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path TO 'pg_catalog'
AS $$
  SELECT d.doc_type, d.version, d.title, d.content, d.content_url,
         d.content_hash, d.status, d.is_material_change,
         d.effective_from, d.effective_to, d.published_at
    FROM public.legal_documents d
   WHERE d.doc_type = p_doc_type
     AND d.version  = p_version
     -- Rascunho jamais é exposto publicamente.
     AND d.status IN ('published', 'archived')
   LIMIT 1;
$$;

ALTER FUNCTION public.get_legal_document_version(text, text) OWNER TO postgres;

REVOKE EXECUTE ON FUNCTION public.get_legal_document_version(text, text) FROM PUBLIC;
GRANT  EXECUTE ON FUNCTION public.get_legal_document_version(text, text)
  TO anon, authenticated, service_role;

COMMENT ON FUNCTION public.get_legal_document_version(text, text) IS
  'Devolve UMA versão de documento legal, publicada ou arquivada, para a área '
  'legal pública e para links a contratos históricos. Nunca expõe rascunho. '
  'Somente leitura.';
