-- ===========================================================================
-- M1 — STORAGE PRIVADO PARA DOCUMENTOS EMPRESARIAIS
-- ===========================================================================
-- Bucket PRIVADO. Nunca público. O isolamento é por PASTA: o primeiro
-- segmento do caminho é o id da aplicação, e as policies exigem que essa
-- aplicação pertença ao usuário autenticado.
--
-- Desenho extensível: o material de customização exigido na CONTRATAÇÃO
-- (estágio M3) usará a mesma infraestrutura privada, com outro bucket ou
-- outro prefixo. Ele NÃO bloqueia a application inicial do M1.
-- ===========================================================================

INSERT INTO storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
VALUES (
  'partner-application-docs',
  'partner-application-docs',
  false,
  20971520,
  ARRAY['application/pdf','image/jpeg','image/png','image/webp']
)
ON CONFLICT (id) DO NOTHING;

-- ---------------------------------------------------------------------------
-- Policies sobre storage.objects
-- ---------------------------------------------------------------------------
-- Leitura: o titular provisório lê apenas os arquivos da pasta da própria
-- aplicação. anon não recebe policy alguma neste bucket.
CREATE POLICY m1_partner_docs_titular_select
  ON storage.objects FOR SELECT TO authenticated
  USING (
    bucket_id = 'partner-application-docs'
    AND EXISTS (
      SELECT 1 FROM public.partner_applications a
       WHERE a.account_user_id = auth.uid()
         AND a.id::text = split_part(storage.objects.name, '/', 1)
    )
  );

-- Escrita: apenas na própria pasta e apenas enquanto a solicitação admite
-- envio de documentos.
CREATE POLICY m1_partner_docs_titular_insert
  ON storage.objects FOR INSERT TO authenticated
  WITH CHECK (
    bucket_id = 'partner-application-docs'
    AND EXISTS (
      SELECT 1 FROM public.partner_applications a
       WHERE a.account_user_id = auth.uid()
         AND a.id::text = split_part(storage.objects.name, '/', 1)
         AND a.status IN ('under_review','changes_requested')
    )
  );

CREATE POLICY m1_partner_docs_titular_delete
  ON storage.objects FOR DELETE TO authenticated
  USING (
    bucket_id = 'partner-application-docs'
    AND EXISTS (
      SELECT 1 FROM public.partner_applications a
       WHERE a.account_user_id = auth.uid()
         AND a.id::text = split_part(storage.objects.name, '/', 1)
         AND a.status IN ('under_review','changes_requested')
    )
  );

-- Administrador autorizado lê documentos para análise. Autorização
-- server-side real, não ocultação de botão.
CREATE POLICY m1_partner_docs_admin_select
  ON storage.objects FOR SELECT TO authenticated
  USING (
    bucket_id = 'partner-application-docs'
    AND public.is_site_admin()
  );
