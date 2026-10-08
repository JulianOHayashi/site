-- Alinha o acesso direto a legal_documents ao modelo vigente em produção.
-- Leitura pública continua exclusivamente pelas RPCs SECURITY DEFINER
-- (get_current_legal_documents / get_legal_document_version), que filtram
-- status e versão. Nenhum cliente público precisa SELECT direto na tabela.

REVOKE ALL ON TABLE public.legal_documents FROM PUBLIC, anon, authenticated, service_role;
GRANT SELECT, INSERT, UPDATE ON TABLE public.legal_documents TO service_role;
