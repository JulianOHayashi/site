-- ============================================================================
-- AUTORIDADE DE USO DE BENEFÍCIO — pacote autoritativo para o fluxo síncrono
--
-- POR QUE UMA RPC NOVA
-- O endpoint serverless precisa, numa única prova, de tudo que o App exige:
-- os três identificadores de ponte, o papel do validador e os cinco campos de
-- apresentação. Nenhuma função atual entrega isso:
--
--   get_my_validator_context  devolve papel e unidades, mas não a ponte de
--                             REDE, nem cidade, nem UF, nem nome do parceiro.
--   prepare_benefit_validation devolve as pontes, mas nenhum campo de
--                             apresentação, e exige que o chamador já saiba a
--                             empresa.
--
-- Compor as duas no servidor exigiria confiar num company_id vindo do
-- navegador. Aqui a EMPRESA É DERIVADA DA UNIDADE, e a unidade é conferida
-- contra o vínculo do usuário autenticado: o navegador escolhe qual unidade,
-- nunca quem ele é.
--
-- SEGURANÇA
-- SECURITY DEFINER com search_path fixo, concedida apenas a `authenticated`.
-- Não recebe token, não escreve nada, não é acessível a anon nem a
-- service_role — o endpoint atua SEMPRE como o usuário logado, e por isso não
-- precisa de autoridade ampla de banco.
--
-- A auditoria continua sendo feita por prepare_benefit_validation, que grava
-- a tentativa com hash unidirecional do token. Esta função não vê o token.
--
-- ADITIVA. Nenhuma das 30 migrations anteriores é editada.
-- ============================================================================

CREATE FUNCTION public.get_my_benefit_usage_authority(p_unit_id uuid)
RETURNS jsonb
LANGUAGE plpgsql STABLE SECURITY DEFINER
SET search_path TO 'pg_catalog'
AS $$
DECLARE
  v_uid    uuid := auth.uid();
  v_unit   public.site_partner_units%ROWTYPE;
  v_comp   public.site_partner_companies%ROWTYPE;
  v_member public.site_company_members%ROWTYPE;
BEGIN
  IF v_uid IS NULL THEN
    RETURN pg_catalog.jsonb_build_object('ok', false, 'reason', 'not_authenticated');
  END IF;

  SELECT * INTO v_unit FROM public.site_partner_units
   WHERE id = p_unit_id AND status = 'active';
  IF NOT FOUND THEN
    -- Motivo genérico: distinguir "unidade inexistente" de "unidade de outro
    -- parceiro" entregaria um oráculo de enumeração a quem não tem vínculo.
    RETURN pg_catalog.jsonb_build_object('ok', true, 'authorized', false,
                                         'reason', 'not_authorized');
  END IF;

  -- A EMPRESA VEM DA UNIDADE, nunca do chamador.
  SELECT * INTO v_comp FROM public.site_partner_companies
   WHERE id = v_unit.company_id AND status = 'active';
  IF NOT FOUND THEN
    RETURN pg_catalog.jsonb_build_object('ok', true, 'authorized', false,
                                         'reason', 'not_authorized');
  END IF;

  SELECT * INTO v_member FROM public.site_company_members
   WHERE company_id = v_comp.id AND auth_user_id = v_uid AND status = 'active';
  IF NOT FOUND THEN
    RETURN pg_catalog.jsonb_build_object('ok', true, 'authorized', false,
                                         'reason', 'not_authorized');
  END IF;

  -- Gestor só valida na unidade a que está vinculado; responsável alcança
  -- todas as unidades da própria empresa. Mesma regra de
  -- prepare_benefit_validation, para que as duas portas não divirjam.
  IF v_member.role = 'partner_manager' AND NOT EXISTS (
      SELECT 1 FROM public.site_member_unit_bindings b
       WHERE b.member_id = v_member.id AND b.unit_id = v_unit.id
         AND b.status = 'active') THEN
    RETURN pg_catalog.jsonb_build_object('ok', true, 'authorized', false,
                                         'reason', 'not_authorized');
  END IF;

  RETURN pg_catalog.jsonb_build_object(
    'ok', true,
    'authorized', true,
    'company_id', v_comp.id,
    'unit_id', v_unit.id,
    -- Identidades de ponte: as MESMAS colunas do domínio durável de parceiro,
    -- não identificadores novos.
    'partner_network_bridge_id', v_comp.partner_network_bridge_id,
    'partner_branch_bridge_id',  v_unit.partner_branch_bridge_id,
    'validator_bridge_id',       v_member.validator_bridge_id,
    'validator_role',            v_member.role,
    -- Apresentação, contrato versão 1. O rótulo de localização é DERIVADO:
    -- criar coluna para concatenar dois campos existentes seria inventar
    -- estado que pode divergir da fonte.
    'snapshot_presentation_version', 1,
    'snapshot_partner_display_name',
      coalesce(nullif(pg_catalog.btrim(coalesce(v_comp.trade_name, '')), ''),
               v_comp.legal_name),
    'snapshot_branch_display_name',  v_unit.name,
    'snapshot_branch_city_name',     v_unit.city,
    'snapshot_branch_state_code',    v_unit.uf,
    'snapshot_branch_location_label', v_unit.city || '/' || v_unit.uf);
END;
$$;

REVOKE EXECUTE ON FUNCTION public.get_my_benefit_usage_authority(uuid) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.get_my_benefit_usage_authority(uuid)
  FROM anon, service_role;
GRANT  EXECUTE ON FUNCTION public.get_my_benefit_usage_authority(uuid)
  TO authenticated;

COMMENT ON FUNCTION public.get_my_benefit_usage_authority(uuid) IS
  'Pacote autoritativo de uso de beneficio para o endpoint sincrono do Site: '
  'pontes de rede/filial/validador, papel e campos de apresentacao V1. A '
  'empresa e derivada da unidade e conferida contra o vinculo do usuario '
  'autenticado; o navegador escolhe apenas QUAL unidade. Nao recebe token, '
  'nao escreve, e nao e executavel por anon nem por service_role.';
