-- ============================================================================
-- CONTEXTO DE CLIENTE DO PROVEDOR, DERIVADO NO SERVIDOR
--
-- A API V5 do Pagar.me exige `customer` ou `customer_id` na criação do pedido,
-- e para conta PSP exige o objeto completo, com endereço e telefone. O
-- adaptador atual criava o pedido Pix sem nenhum dos dois — defeito que mock
-- algum revelaria, porque o mock aceita qualquer corpo.
--
-- A fonte do cliente é o dado de onboarding que a BDFlow já possui: a empresa
-- durável e a candidatura que a originou. O navegador não fornece nada disso,
-- e não há por onde fornecer: esta função recebe SÓ o id do pagamento.
--
-- FUNÇÃO ESTREITA, NÃO CONSULTA GENÉRICA
-- Ela resolve um caminho fixo — pagamento -> pedido -> empresa -> candidatura
-- — e devolve exatamente os campos necessários para montar o cliente do
-- provedor. Nenhum nome de tabela, coluna ou filtro vem de parâmetro.
--
-- ADITIVA. Nenhuma das 35 migrations anteriores é editada.
-- ============================================================================

CREATE FUNCTION public.prov_get_commercial_payment_customer_context(
  p_payment_id uuid
)
RETURNS jsonb
LANGUAGE plpgsql STABLE SECURITY DEFINER
SET search_path TO 'pg_catalog'
AS $$
DECLARE
  v_p    public.commercial_payments%ROWTYPE;
  v_o    public.commercial_exclusivity_orders%ROWTYPE;
  v_c    public.site_partner_companies%ROWTYPE;
  v_a    public.partner_applications%ROWTYPE;
  v_email text;
  v_fone  text;
BEGIN
  IF coalesce(auth.role(), current_user::text) <> 'service_role' THEN
    RETURN pg_catalog.jsonb_build_object('ok', false, 'reason', 'not_authorized');
  END IF;

  SELECT * INTO v_p FROM public.commercial_payments WHERE id = p_payment_id;
  IF NOT FOUND THEN
    RETURN pg_catalog.jsonb_build_object('ok', false, 'reason', 'payment_not_found');
  END IF;
  SELECT * INTO v_o FROM public.commercial_exclusivity_orders
   WHERE id = v_p.commercial_order_id;
  SELECT * INTO v_c FROM public.site_partner_companies WHERE id = v_o.company_id;
  IF NOT FOUND THEN
    RETURN pg_catalog.jsonb_build_object('ok', false, 'reason', 'company_not_found');
  END IF;
  SELECT * INTO v_a FROM public.partner_applications WHERE id = v_c.source_application_id;

  -- A empresa é a fonte preferida; a candidatura completa o que falta. Nada
  -- é inventado: campo ausente vira NULL e o chamador falha fechado.
  v_email := nullif(pg_catalog.btrim(
    coalesce(nullif(pg_catalog.btrim(coalesce(v_c.contact_email, '')), ''),
             coalesce(v_a.contact_email, ''))), '');
  v_fone := nullif(pg_catalog.btrim(
    coalesce(nullif(pg_catalog.btrim(coalesce(v_c.contact_phone, '')), ''),
             coalesce(v_a.contact_phone, ''))), '');

  RETURN pg_catalog.jsonb_build_object(
    'ok', true,
    -- Cliente pessoa jurídica: a contratante é a empresa, não uma pessoa.
    'legal_name', v_c.legal_name,
    'cnpj', v_c.cnpj,
    'email', v_email,
    'phone', v_fone,
    'address', pg_catalog.jsonb_build_object(
      'postal_code', nullif(pg_catalog.btrim(coalesce(v_a.postal_code, '')), ''),
      'street', nullif(pg_catalog.btrim(coalesce(v_a.street, '')), ''),
      'street_number', nullif(pg_catalog.btrim(coalesce(v_a.street_number, '')), ''),
      'complement', nullif(pg_catalog.btrim(coalesce(v_a.complement, '')), ''),
      'district', nullif(pg_catalog.btrim(coalesce(v_a.district, '')), ''),
      -- Cidade e UF da candidatura, com a empresa como reserva.
      'city', coalesce(nullif(pg_catalog.btrim(coalesce(v_a.city, '')), ''), v_c.city),
      'uf', coalesce(nullif(pg_catalog.btrim(coalesce(v_a.uf, '')), ''), v_c.uf)));
END;
$$;

REVOKE EXECUTE ON FUNCTION public.prov_get_commercial_payment_customer_context(uuid)
  FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.prov_get_commercial_payment_customer_context(uuid)
  FROM anon, authenticated;
GRANT  EXECUTE ON FUNCTION public.prov_get_commercial_payment_customer_context(uuid)
  TO service_role;

COMMENT ON FUNCTION public.prov_get_commercial_payment_customer_context(uuid) IS
  'Contexto de cliente do provedor derivado no servidor a partir do pagamento '
  'local: pedido -> empresa -> candidatura de origem. Recebe apenas o id do '
  'pagamento; nenhum dado de cliente vem de HTTP. Campo ausente volta NULL '
  'para que o chamador falhe fechado em vez de enviar dado inventado.';
