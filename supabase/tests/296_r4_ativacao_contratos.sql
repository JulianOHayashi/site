-- ===========================================================================
-- 296 — R4: ativação só pelo procedimento (inclusive contra registro forjado
-- com todas as travas ligadas e pré-verificação aprovada), aprovação jurídica
-- correspondente por minuta × economia × liquidação. Migration 20261113180000.
--
-- A concorrência entre retirada/reprovação de bandeiras e pedido/confirmação
-- é provada com DUAS sessões reais em scripts/db-test/r4-concorrencia-bandeiras.sh
-- (não cabe numa sessão só).
--
-- Preços do DINHEIRO e aprovações jurídicas aqui são FIXTURES de teste,
-- sempre dentro de transações revertidas. O rodapé conta pelas sequências
-- de tests (inclui o que rodou dentro das transações revertidas).
-- ===========================================================================
\set ON_ERROR_STOP on
select tests.reset_results();
select tests.fechar_portao_autoatendimento_qa();

select tests.check('estado de partida: v3 vigente, v4 preparada, nenhuma ativacao, nenhuma aprovacao juridica',
    (select status from public.commercial_pricing_rules where version = 3) = 'active'
    and (select status from public.commercial_pricing_rules where version = 4) = 'prepared'
    and not exists (select 1 from public.commercial_pricing_activation_log)
    and not exists (select 1 from public.commercial_instrument_template_approvals));
select tests.check('fora do procedimento a pilha nao e reconhecida como ativacao',
    not public.commercial_activation_called_by_procedure());
select tests.check('ninguem alem do dono escreve aprovacoes juridicas nem registro de ativacao',
    not exists (
      select 1 from unnest(array['anon','authenticated','service_role']) r,
                    unnest(array['public.commercial_instrument_template_approvals',
                                 'public.commercial_pricing_activation_log']) t,
                    unnest(array['INSERT','UPDATE','DELETE','TRUNCATE']) p
       where has_table_privilege(r, t, p)));

-- ---------------------------------------------------------------------------
-- 1. ATIVAÇÃO — item 1 da auditoria
-- ---------------------------------------------------------------------------
begin;
select tests.preparar_ativacao_sf_v15_qa('296A', 'A');
select tests.check('pre-condicao do ataque: pre-verificacao APROVADA e nenhum gatilho desligado',
    (public.commercial_pricing_activation_preflight(4)->>'ok')::boolean
    and not exists (select 1 from pg_trigger where not tgisinternal and tgenabled = 'D'
                     and tgrelid::regclass::text like 'public.commercial%'));
select tests.check_raises('ATAQUE 1: INSERT direto no registro de ativacao (operador privilegiado) e recusado',
  $sql$insert into public.commercial_pricing_activation_log (pricing_rule_version, authorization_reference, preflight, guard_fingerprint)
       values (4, 'registro forjado por operador', public.commercial_pricing_activation_preflight(4),
               public.commercial_activation_guard_fingerprint())$sql$,
  'activation_log_somente_pelo_procedimento');
select tests.check_raises('ATAQUE 2: UPDATE direto de status sem o procedimento e recusado',
  $sql$update public.commercial_pricing_rules set status = 'active', effective_from = now() where version = 4$sql$,
  'ativacao_nao_autorizada');
select tests.check_raises('ATAQUE 3: superar a versao vigente por UPDATE direto e recusado',
  $sql$update public.commercial_pricing_rules set status = 'superseded' where version = 3$sql$,
  'superacao_nao_autorizada');

savepoint atalho;
create function public.ativar_por_atalho(p integer) returns void language plpgsql as $f$
begin
  insert into public.commercial_pricing_activation_log (pricing_rule_version, authorization_reference, preflight, guard_fingerprint)
  values (p, 'atalho com outro nome', public.commercial_pricing_activation_preflight(p),
          public.commercial_activation_guard_fingerprint());
end $f$;
select tests.check_raises('ATAQUE 4: funcao propria (outro nome) gravando o registro e recusada',
  $sql$select public.ativar_por_atalho(4)$sql$, 'activation_log_somente_pelo_procedimento');
rollback to savepoint atalho;

savepoint homonimo;
create schema atalho296;
create function atalho296.admin_activate_pricing_rule(p integer, r text) returns void language plpgsql as $f$
begin
  insert into public.commercial_pricing_activation_log (pricing_rule_version, authorization_reference, preflight, guard_fingerprint)
  values (p, r, public.commercial_pricing_activation_preflight(p), public.commercial_activation_guard_fingerprint());
end $f$;
select tests.check_raises('ATAQUE 5: homonimo em outro schema (mesmo nome e assinatura) e recusado',
  $sql$select atalho296.admin_activate_pricing_rule(4, 'homonimo em outro schema')$sql$,
  'activation_log_somente_pelo_procedimento');
create function public.admin_activate_pricing_rule(p integer, r text, x boolean) returns void language plpgsql as $f$
begin
  insert into public.commercial_pricing_activation_log (pricing_rule_version, authorization_reference, preflight, guard_fingerprint)
  values (p, r, public.commercial_pricing_activation_preflight(p), public.commercial_activation_guard_fingerprint());
end $f$;
select tests.check_raises('ATAQUE 6: sobrecarga com outra assinatura em public e recusada',
  $sql$select public.admin_activate_pricing_rule(4, 'sobrecarga', true)$sql$,
  'activation_log_somente_pelo_procedimento');
rollback to savepoint homonimo;

savepoint gatilho_off;
alter table public.commercial_exclusivity_orders disable trigger ceo_revalidar_reutilizacao_bandeiras;
select tests.check('com uma trava desligada, o procedimento recusa a ativacao e aponta a trava',
    (select (r->>'ok')::boolean = false
            and r->'failures' ? 'guard_trigger_state_not_approved:public.commercial_exclusivity_orders.ceo_revalidar_reutilizacao_bandeiras:D(aprovado O)'
       from (select tests.ativar_sf_v15_qa(4, '[QA FICTICIO] ativacao com trava desligada') r) x));
rollback to savepoint gatilho_off;

select public.commercial_activation_guard_fingerprint() as fp_base \gset
savepoint ddl;
-- R4.1: substituir o procedimento por DDL deixou de bastar. O registro de
-- ativação compara o catálogo vivo com o manifesto aprovado e recusa a
-- função divergente. (O limite do dono, que pode substituir TAMBÉM as
-- guardas, está na suíte 297 e no r4-limite-confianca.sh.)
create or replace function public.admin_activate_pricing_rule(p_version integer, p_authorization_reference text)
returns jsonb language plpgsql security definer set search_path to 'pg_catalog' as $f$
begin
  insert into public.commercial_pricing_activation_log (pricing_rule_version, authorization_reference, preflight, guard_fingerprint)
  values (p_version, p_authorization_reference, '{}'::jsonb, public.commercial_activation_guard_fingerprint());
  update public.commercial_pricing_rules set status = 'superseded' where status = 'active' and version < p_version;
  update public.commercial_pricing_rules set status = 'active' where version = p_version;
  return '{"ok": true}'::jsonb;
end $f$;
select tests.check('R4.1: procedimento substituido por DDL aparece no catalogo como divergente do manifesto',
    public.commercial_guard_integrity_failures() @> array['guard_function_divergent:public.admin_activate_pricing_rule(integer,text)']
    and public.commercial_activation_guard_fingerprint()->'functions'->'public.admin_activate_pricing_rule(integer,text)'
        <> (:'fp_base')::jsonb->'functions'->'public.admin_activate_pricing_rule(integer,text)');
select tests.check_raises('R4.1: procedimento substituido por DDL nao consegue gravar a ativacao',
  $sql$select public.admin_activate_pricing_rule(4, '[QA FICTICIO] procedimento substituido por DDL')$sql$,
  'activation_log_guardas_divergentes');
rollback to savepoint ddl;

select tests.ativar_sf_v15_qa(4, '[QA FICTICIO] ativacao autorizada da suite 296') as r_ok \gset
select tests.check('procedimento autorizado ativa; registro com ator, transacao e impressao digital da linha de base',
    ((:'r_ok')::jsonb->>'ok') = 'true'
    and (select status from public.commercial_pricing_rules where version = 4) = 'active'
    and (select count(*) = 1 and bool_and(actor = session_user and txid = txid_current()
                                          and guard_fingerprint = (:'fp_base')::jsonb
                                          and jsonb_typeof(guard_fingerprint->'functions') = 'object'
                                          and (select count(*) from jsonb_object_keys(guard_fingerprint->'functions')) >= 18)
           from public.commercial_pricing_activation_log));
select tests.check_raises('registro de ativacao continua imutavel',
  $sql$update public.commercial_pricing_activation_log set authorization_reference = 'reescrito'$sql$,
  'activation_log_imutavel');
rollback;
begin;
select tests.encerrar_contexto_contratual_v14_qa();

select r.id as reg from public.commercial_regions r
  join public.commercial_region_cities c on c.region_id = r.id
 where c.uf = 'ES' and c.city_key = 'viana' limit 1 \gset

select tests.mk_user('admin296') as uid_adm \gset
insert into public.site_admins (user_id) values ((:'uid_adm')::uuid) on conflict do nothing;

-- Doze empresas em Viana, cada uma com titular.
create temp table emp296 (n int primary key, cnpj text, comp uuid, uid uuid) on commit drop;
do $$
declare
  v_cnpjs text[] := array['29000001000118','29000002000162','29000003000107','29000004000151',
                          '29000005000104','29000006000140','29000007000195','29000008000130',
                          '29000009000184','29000010000109','29000011000153','29000012000106'];
  v_i int; v_app uuid; v_comp uuid; v_uid uuid;
begin
  for v_i in 1..12 loop
    v_uid := tests.mk_user('titular296.' || v_i);
    insert into public.partner_applications (cnpj, legal_name, contact_email, city, uf)
    values (v_cnpjs[v_i], 'Empresa 296-' || v_i, 'e296' || v_i || '@teste.local', 'Viana', 'ES')
    returning id into v_app;
    insert into public.partner_application_representatives
      (application_id, full_name, cpf, email, role_title, authority_status, is_current, decided_at)
    values (v_app, 'Titular 296-' || v_i, '52998224725', 'rep296' || v_i || '@teste.local',
            'Socio administrador', 'approved', true, now() - interval '2 days');
    insert into public.site_partner_companies
      (source_application_id, cnpj, legal_name, trade_name, contact_email, city, uf, status)
    values (v_app, v_cnpjs[v_i], 'Empresa 296-' || v_i, 'Loja 296-' || v_i,
            'e296' || v_i || '@teste.local', 'Viana', 'ES', 'active')
    returning id into v_comp;
    insert into public.site_company_members
      (company_id, auth_user_id, role, full_name, cpf, source, status)
    values (v_comp, v_uid, 'partner_owner', 'Titular 296-' || v_i, '52998224725',
            'application_promotion', 'active');
    insert into public.site_partner_units (company_id, name, city, uf, status)
    values (v_comp, 'Unidade 296-' || v_i, 'Viana', 'ES', 'active');
    insert into emp296 values (v_i, v_cnpjs[v_i], v_comp, v_uid);
  end loop;
end $$;

-- As tabelas temporárias da suíte são lidas também sob o papel impersonado.
grant select on emp296 to authenticated;
select tests.impersonate('authenticated', :'uid_adm');
select tests.assinar_mestre_qa(e.comp, 'AM-296-' || e.n) from emp296 e;
select (public.admin_create_commercial_segment('pet_shop_296','Pet shop 296','pet_shop_296')->>'segment_id') as seg \gset
reset role;
select set_config('request.jwt.claims', '', true);

-- Exclusividades E0 (reservas), E1..E4 (cenários) e E5 (instrumento), cada
-- uma com as seis posições.
create temp table exc296 (k int primary key, id uuid) on commit drop;
select set_config('tests.reg296', :'reg', true);
do $$
declare v_k int; v_id uuid;
begin
  for v_k in 0..5 loop
    insert into public.commercial_exclusivities (region_id, sequence_number, status, is_current)
    values (current_setting('tests.reg296')::uuid, 2960 + v_k, 'forming', false)
    returning id into v_id;
    insert into exc296 values (v_k, v_id);
  end loop;
end $$;
grant select on exc296 to authenticated;
insert into public.commercial_opportunities (exclusivity_id, niche_code, contracted_quantity, status)
select x.id, n.code, n.contracted_quantity, 'available'
  from exc296 x cross join public.commercial_niches n where n.is_active;

create or replace function pg_temp.tornar_corrente(p_k int) returns void language sql as $f$
  update public.commercial_exclusivities set is_current = false
   where region_id = (select region_id from public.commercial_exclusivities
                       where id = (select id from exc296 where k = p_k)) and is_current;
  update public.commercial_exclusivities set is_current = true
   where id = (select id from exc296 where k = p_k);
$f$;

-- Pedido direto (caminho administrativo): os números vêm dos gatilhos.
create or replace function pg_temp.pedido(p_k int, p_n int, p_niche text, p_fid boolean,
                                          p_mode text default 'direct_benefits')
returns uuid language plpgsql as $f$
declare v_id uuid; v_excl uuid := (select id from exc296 where k = p_k);
        v_comp uuid := (select comp from emp296 where n = p_n);
        v_seg public.commercial_segments%rowtype;
begin
  if p_niche = 'others' then
    select * into v_seg from public.commercial_segments where code = 'pet_shop_296';
  end if;
  insert into public.commercial_exclusivity_orders
    (exclusivity_id, opportunity_id, company_id, master_agreement_id, region_id,
     niche_code, nominal_quantity, fidelized, status, expected_operation_start,
     registered_by, pricing_rule_version, benefit_settlement_mode,
     economic_value_cents, contractual_pool_cents, bdflow_due_cents,
     segment_id, segment_code_snapshot, segment_name_snapshot, segment_classification_snapshot)
  values
    (v_excl,
     (select id from public.commercial_opportunities where exclusivity_id = v_excl and niche_code = p_niche),
     v_comp,
     (select id from public.commercial_master_agreements where company_id = v_comp and status = 'signed'),
     (select region_id from public.commercial_exclusivities where id = v_excl),
     p_niche, (select contracted_quantity from public.commercial_niches where code = p_niche),
     p_fid, 'draft', (now() + interval '30 days')::date,
     (select user_id from public.site_admins limit 1), 4, p_mode,
     -- valores propositalmente errados: a autoridade os substitui
     1, 1, 0,
     v_seg.id, v_seg.code, v_seg.display_name, v_seg.classification_key)
  returning id into v_id;
  return v_id;
end $f$;

create or replace function pg_temp.conjunto(p_order uuid, p_dias int) returns uuid language sql as $f$
  insert into public.commercial_flag_sets
    (origin_order_id, company_id, fidelity_identity, pieces_count, produced_at,
     supplier_name, unit_cost_cents, recorded_by)
  values (p_order, gen_random_uuid(), 'qualquer_coisa', 1, now() - make_interval(days => p_dias),
          '[QA FICTICIO] Fornecedor', 3500, (select user_id from public.site_admins limit 1))
  returning id;
$f$;

create or replace function pg_temp.inspecao(p_set uuid, p_dias int, p_unfit int default 0,
                                            p_cats text[] default '{}')
returns uuid language sql as $f$
  insert into public.commercial_flag_set_inspections
    (flag_set_id, inspected_at, inspector_name, evidence_hash, pieces_inspected,
     pieces_fit, pieces_unfit, unfit_categories, recorded_by)
  values (p_set, now() - make_interval(days => p_dias), '[QA FICTICIO] Conferente',
          encode(extensions.digest('[QA] inspecao ' || p_set || p_dias, 'sha256'), 'hex'),
          84, 84 - p_unfit, p_unfit, p_cats, (select user_id from public.site_admins limit 1))
  returning id;
$f$;


-- ---------------------------------------------------------------------------
-- 2. CONTRATOS — item 2 da auditoria (dentro da transação das fixtures)
-- ---------------------------------------------------------------------------
select tests.preparar_ativacao_sf_v15_qa('296C', 'A') as prep \gset
select ((:'prep')::jsonb->>'founding_template_id') as tpl_nf, ((:'prep')::jsonb->>'fidelized_template_id') as tpl_fid \gset
select tests.ativar_sf_v15_qa(4, '[QA FICTICIO] ativacao para contratos 296');

select tests.check_raises('aprovacao de conteudo diferente do da minuta (sha256) e recusada',
  format($sql$insert into public.commercial_instrument_template_approvals (template_id, content_sha256,
         contract_economics_version, settlement_model, settlement_modes, applies_to_fidelized,
         legal_approval_reference, approved_by_name, approved_at)
         values (%L, repeat('0', 64), 'SF-v1.4', 'in_kind_direct_benefits_only', array['cash'], false,
                 '[QA FICTICIO] conteudo errado', 'Revisor QA', now())$sql$, :'tpl_nf'),
  'o conteudo aprovado nao e o conteudo da minuta');
select tests.check_raises('aprovacao com fidelidade diferente da minuta e recusada',
  format($sql$insert into public.commercial_instrument_template_approvals (template_id, content_sha256,
         contract_economics_version, settlement_model, settlement_modes, applies_to_fidelized,
         legal_approval_reference, approved_by_name, approved_at)
         select id, source_hash, 'SF-v1.4', 'in_kind_direct_benefits_only', array['cash'], true,
                '[QA FICTICIO] fidelidade errada', 'Revisor QA', now()
           from public.commercial_instrument_templates where id = %L$sql$, :'tpl_nf'),
  'condicao de fidelidade diverge');
select tests.check_raises('aprovacao juridica e imutavel',
  format($sql$update public.commercial_instrument_template_approvals set settlement_modes = array['cash']
         where template_id = %L$sql$, :'tpl_nf'),
  'aprovacao_minuta_imutavel');
select tests.check_raises('aprovacao juridica nao e apagada',
  format($sql$delete from public.commercial_instrument_template_approvals where template_id = %L$sql$, :'tpl_nf'),
  'aprovacao_minuta_imutavel');

select pg_temp.tornar_corrente(5);
select id as opp_pha from public.commercial_opportunities
 where exclusivity_id = (select id from exc296 where k = 5) and niche_code = 'pharmacy' \gset
select id as opp_wom from public.commercial_opportunities
 where exclusivity_id = (select id from exc296 where k = 5) and niche_code = 'womens_clothing' \gset
select tests.impersonate('authenticated', :'uid_adm');
select public.admin_register_manual_commercial_order(
  (:'opp_pha')::uuid, (select comp from emp296 where n = 12), 'v1', now() - interval '1 day',
  'Titular 296-12', (now() + interval '30 days')::date, 'cash', 'doc://pedido-296-dinheiro') as m_cash \gset
select public.admin_register_manual_commercial_order(
  (:'opp_wom')::uuid, (select comp from emp296 where n = 11), 'v1', now() - interval '1 day',
  'Titular 296-11', (now() + interval '30 days')::date, 'direct_benefits', 'doc://pedido-296-direto') as m_dir \gset
reset role; select set_config('request.jwt.claims', '', true);
select ((:'m_cash')::jsonb->>'order_id') as om_cash, ((:'m_dir')::jsonb->>'order_id') as om_dir \gset
select tests.check('instrumento v4 emitido carrega a aprovacao juridica: id, referencia, hash = hash da minuta, modalidades',
    ((:'m_cash')::jsonb->>'ok') = 'true' and ((:'m_dir')::jsonb->>'ok') = 'true'
    and (select o.instrument_snapshot->>'instrument_legal_approval_id' = a.id::text
                and o.instrument_snapshot->>'instrument_legal_content_sha256' = t.source_hash
                and o.instrument_snapshot->>'instrument_template_source_hash' = t.source_hash
                and o.instrument_snapshot->>'contract_economics_version' = a.contract_economics_version
                and o.instrument_snapshot->>'benefit_settlement_mode' = 'cash'
                and o.instrument_snapshot->'instrument_legal_settlement_modes' ? 'cash'
                and o.instrument_snapshot->'field_provenance'->>'instrument_legal_approval_id' = 'instrument_legal_approval'
           from public.commercial_exclusivity_orders o
           join public.commercial_instrument_templates t on t.id = o.instrument_template_id
           join public.commercial_instrument_template_approvals a
             on a.template_id = t.id and a.contract_economics_version = o.contract_economics_version
          where o.id = (:'om_cash')::uuid));

-- Minuta alternativa (assinável no lugar da aprovada) para cada divergência.
create or replace function pg_temp.minuta_alternativa(p_sufixo text) returns uuid language plpgsql as $f$
declare v uuid;
begin
  update public.commercial_instrument_templates set lifecycle_status = 'archived'
   where lifecycle_status = 'signable' and not applies_to_fidelized;
  v := tests.criar_modelo_instrumento_qa(false, p_sufixo);
  update public.commercial_instrument_templates set settlement_model = 'in_kind_direct_benefits_only' where id = v;
  return v;
end $f$;

savepoint sem_aprovacao;
select pg_temp.minuta_alternativa('296-SEM') as alt \gset
select tests.check('minuta assinavel com settlement_model, mas SEM aprovacao juridica: pedido v4 nao e individualizado',
    (public.commercial_build_instrument_snapshot((:'om_cash')::uuid, (:'alt')::uuid)->>'reason')
      = 'commercial_instrument_legal_approval_missing');
rollback to savepoint sem_aprovacao;

savepoint outra_economia;
select pg_temp.minuta_alternativa('296-V14') as alt \gset
select tests.aprovar_minuta_r3_qa((:'alt')::uuid, array['direct_benefits','cash'], 'SF-v1.4');
select tests.check('aprovacao para OUTRA versao economica (SF-v1.4) nao serve a pedido SF-v1.5',
    (public.commercial_build_instrument_snapshot((:'om_cash')::uuid, (:'alt')::uuid)->>'reason')
      = 'commercial_instrument_legal_approval_missing');
rollback to savepoint outra_economia;

savepoint so_direto;
select pg_temp.minuta_alternativa('296-DIR') as alt \gset
select tests.aprovar_minuta_r3_qa((:'alt')::uuid, array['direct_benefits']);
select tests.check('aprovacao so para BENEFICIO DIRETO nao individualiza pedido em DINHEIRO',
    (public.commercial_build_instrument_snapshot((:'om_cash')::uuid, (:'alt')::uuid)->>'reason')
      = 'commercial_instrument_legal_settlement_mode_not_covered');
select tests.check('a mesma aprovacao individualiza o pedido de beneficio direto',
    (public.commercial_build_instrument_snapshot((:'om_dir')::uuid, (:'alt')::uuid)->>'ok')::boolean);
select tests.check('pre-verificacao exige minuta aprovada para as DUAS modalidades',
    public.commercial_pricing_activation_preflight(4)->'failures' ? 'instrument_template_missing:novo');
rollback to savepoint so_direto;

savepoint texto_mudou;
update public.commercial_instrument_templates set source_hash = repeat('a', 64) where id = (:'tpl_nf')::uuid;
select tests.check('texto da minuta alterado depois da aprovacao: aprovacao deixa de valer',
    (public.commercial_build_instrument_snapshot((:'om_cash')::uuid, (:'tpl_nf')::uuid)->>'reason')
      = 'commercial_instrument_legal_content_mismatch');
rollback to savepoint texto_mudou;

-- R4.1: instrumento com QA em produtos exige procedimento operacional de QA
-- aprovado para a economia. O pedido de BENEFÍCIO DIRETO desta suíte tem QA
-- em produtos; o de DINHEIRO não tem QA.
select tests.check('R4.1: instrumento de beneficio direto com QA carrega o procedimento de QA aprovado (fixture)',
    (select o.qa_in_kind_cents > 0
            and o.instrument_snapshot->>'qa_operational_procedure_id' = q.id::text
            and o.instrument_snapshot->>'qa_operational_procedure_sha256' = q.procedure_document_sha256
            and o.instrument_snapshot->'field_provenance'->>'qa_operational_procedure_id' = 'qa_operational_procedure'
       from public.commercial_exclusivity_orders o
       join public.commercial_qa_operational_procedures q on q.contract_economics_version = o.contract_economics_version
      where o.id = (:'om_dir')::uuid));
savepoint sem_procedimento_qa;
alter table public.commercial_qa_operational_procedures disable trigger cqop_protect;
delete from public.commercial_qa_operational_procedures;
alter table public.commercial_qa_operational_procedures enable trigger cqop_protect;
select tests.check('R4.1: sem procedimento de QA aprovado, instrumento de beneficio direto com QA NAO e individualizado',
    (public.commercial_build_instrument_snapshot((:'om_dir')::uuid, (:'tpl_nf')::uuid)->>'reason')
      = 'commercial_qa_operational_procedure_missing');
select tests.check('R4.1: o pedido em DINHEIRO (sem QA) nao depende do procedimento de QA',
    (select (public.commercial_build_instrument_snapshot((:'om_cash')::uuid, (:'tpl_nf')::uuid)->>'ok')::boolean
            and o.qa_in_kind_cents = 0 and o.qa_cash_cents = 0
       from public.commercial_exclusivity_orders o where o.id = (:'om_cash')::uuid));
rollback to savepoint sem_procedimento_qa;

savepoint fidelizado;
select tests.check('aprovacao da minuta de novo anunciante nao rege pedido de outra fidelidade (minuta propria exigida)',
    (public.commercial_build_instrument_snapshot((:'om_cash')::uuid, (:'tpl_fid')::uuid)->>'reason')
      = 'commercial_instrument_template_fidelity_mismatch');
rollback to savepoint fidelizado;

rollback;

select tests.check('apos a suite: nada vazou (v4 preparada, sem ativacao, sem aprovacao juridica, sem preco de dinheiro)',
    (select status from public.commercial_pricing_rules where version = 4) = 'prepared'
    and not exists (select 1 from public.commercial_pricing_activation_log)
    and not exists (select 1 from public.commercial_instrument_template_approvals)
    and not exists (select 1 from public.commercial_pricing_activation_approvals)
    and not exists (select 1 from public.commercial_qa_operational_procedures)
    and not exists (select 1 from public.commercial_settlement_terms where benefit_settlement_mode = 'cash'));

select tests.finish('296_r4_ativacao_contratos');
