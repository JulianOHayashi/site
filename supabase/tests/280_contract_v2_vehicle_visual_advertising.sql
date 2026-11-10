-- ===========================================================================
-- 280 — CONTRATOS V2: publicidade visual em veículos (infraestrutura)
--
-- Migration 20261110120000. Nada aqui publica documento, promove a minuta
-- real ou aprova especificação real. Os caminhos completos usam modelo,
-- atividade e especificação INEQUIVOCAMENTE FICTÍCIOS de QA, dentro de
-- transações revertidas sempre que alteram estado compartilhado.
-- ===========================================================================
\set ON_ERROR_STOP on
select tests.reset_results();

-- ---------------------------------------------------------------------------
-- 1. A MIGRATION NÃO PUBLICA, NÃO PROMOVE, NÃO ACEITA
-- ---------------------------------------------------------------------------
select tests.check('nenhuma especificacao tecnica nasce com a migration',
    (select count(*) = 0 from public.commercial_advertising_specs));
select tests.check('minuta real v1.4 continua draft, sem modalidade e sem exigir especificacao',
    (select lifecycle_status = 'draft' and advertising_modality is null
            and requires_advertising_spec = false
       from public.commercial_instrument_templates
      where template_code = 'SF-MINUTA-PRESENCIAL-v1.4'));
select tests.check('nenhum modelo de instrumento exige especificacao por omissao',
    (select count(*) = 0 from public.commercial_instrument_templates
      where requires_advertising_spec));
-- Documentos, aceites e pedidos intactos: provado por comparação de hash dos
-- dados antes/depois em scripts/db-test/contract-v2-upgrade-check.sh (U2).
-- Aqui, o que independe da ordem das suítes: nenhum modelo REAL assinável.
select tests.check('nenhum modelo real assinavel: so fixtures [QA FICTICIO] podem estar',
    (select count(*) = 0 from public.commercial_instrument_templates
      where lifecycle_status = 'signable' and template_code not like '[QA FICTICIO]%'));
select tests.check('anon e authenticated nao leem especificacoes; funcoes internas fechadas',
    not has_table_privilege('anon', 'public.commercial_advertising_specs', 'SELECT')
    and not has_table_privilege('authenticated', 'public.commercial_advertising_specs', 'SELECT')
    and not has_function_privilege('authenticated', 'public.commercial_order_effective_activity(uuid)', 'EXECUTE')
    and not has_function_privilege('anon', 'public.commercial_order_effective_activity(uuid)', 'EXECUTE')
    and not has_function_privilege('authenticated', 'public.commercial_build_instrument_snapshot(uuid,uuid)', 'EXECUTE'));

-- ---------------------------------------------------------------------------
-- 2. AUTORIDADE DA ESPECIFICAÇÃO: aprovação exige responsável; aprovada é imutável
-- ---------------------------------------------------------------------------
select tests.mk_user('admin280@teste.local') as uid_admin \gset
insert into public.site_admins (user_id) values ((:'uid_admin')::uuid) on conflict do nothing;

select tests.check_raises('modalidade fora da lista e recusada',
  $sql$insert into public.commercial_advertising_specs
        (spec_code, spec_version, modality, artwork_reference_width_mm,
         artwork_reference_height_mm, source_hash)
       values ('QA', '1', 'sound_car', 490, 305, repeat('a', 64))$sql$,
  'cas_modality_valida');
select tests.check_raises('aprovar sem responsavel tecnico e laudo e recusado',
  $sql$insert into public.commercial_advertising_specs
        (spec_code, spec_version, modality, artwork_reference_width_mm,
         artwork_reference_height_mm, source_hash, lifecycle_status,
         approved_by, approved_at)
       values ('QA', '1', 'vehicle_roof_visual_flag', 490, 305, repeat('a', 64),
               'approved', gen_random_uuid(), now())$sql$,
  'cas_aprovacao_completa');

begin;
insert into public.commercial_advertising_specs
  (spec_code, spec_version, modality, artwork_reference_width_mm,
   artwork_reference_height_mm, source_hash, lifecycle_status,
   technical_responsible_name, technical_responsible_registration,
   technical_report_hash, approved_by, approved_at, notes)
values ('[QA FICTICIO] ESPEC-BANDEIRA', '0.0-qa', 'vehicle_roof_visual_flag', 490, 305,
        encode(extensions.digest('[QA FICTICIO] anexo tecnico', 'sha256'), 'hex'),
        'approved', '[QA FICTICIO] Responsavel', '[QA] REGISTRO-0000',
        encode(extensions.digest('[QA FICTICIO] laudo', 'sha256'), 'hex'),
        (:'uid_admin')::uuid, now(), 'QA: nao representa homologacao real')
returning id as spec_qa \gset
select tests.check_raises('segunda especificacao aprovada para a mesma modalidade e recusada',
  $sql$insert into public.commercial_advertising_specs
        (spec_code, spec_version, modality, artwork_reference_width_mm,
         artwork_reference_height_mm, source_hash, lifecycle_status,
         technical_responsible_name, technical_responsible_registration,
         technical_report_hash, approved_by, approved_at)
       values ('[QA FICTICIO] OUTRA', '0.1', 'vehicle_roof_visual_flag', 490, 305, repeat('b', 64),
               'approved', 'x', 'y', repeat('c', 64), gen_random_uuid(), now())$sql$,
  'cas_uma_aprovada_por_modalidade_uidx');
select tests.check_raises('conteudo de especificacao aprovada nao muda',
  format($sql$update public.commercial_advertising_specs set artwork_reference_width_mm = 600
               where id = %L$sql$, :'spec_qa'),
  'advertising_spec_imutavel');
select tests.check_raises('especificacao aprovada nao e apagada',
  format($sql$delete from public.commercial_advertising_specs where id = %L$sql$, :'spec_qa'),
  'advertising_spec_imutavel');
update public.commercial_advertising_specs
   set lifecycle_status = 'archived', archived_at = now() where id = (:'spec_qa')::uuid;
select tests.check('aprovada so pode ir para arquivada, preservando o conteudo',
    (select lifecycle_status = 'archived' and artwork_reference_width_mm = 490
       from public.commercial_advertising_specs where id = (:'spec_qa')::uuid));
select tests.check_raises('arquivada e definitiva',
  format($sql$update public.commercial_advertising_specs set notes = 'x' where id = %L$sql$, :'spec_qa'),
  'advertising_spec_imutavel');
rollback;

-- ---------------------------------------------------------------------------
-- 3. Fixtures de pedido (padrão da suíte 260)
-- ---------------------------------------------------------------------------
select tests.mk_user('titular280@teste.local') as uid_t \gset
select r.id as reg280, r.name as reg280_nome from public.commercial_regions r
  join public.commercial_region_cities c on c.region_id = r.id
 where c.uf = 'ES' and c.city_key = 'viana' limit 1 \gset
insert into public.commercial_exclusivities (region_id, sequence_number, status, is_current)
values ((:'reg280')::uuid, 280, 'forming', false) returning id as excl280 \gset
insert into public.commercial_opportunities (exclusivity_id, niche_code, contracted_quantity, status)
values ((:'excl280')::uuid, 'pharmacy', 12, 'available') returning id as opp280 \gset
insert into public.commercial_opportunities (exclusivity_id, niche_code, contracted_quantity, status)
values ((:'excl280')::uuid, 'others', 12, 'available') returning id as opp280o \gset

insert into public.partner_applications (cnpj, legal_name, trade_name, contact_email, city, uf)
values ('28010001000136','Empresa 280 LTDA','Marca 280','e280@teste.local','Viana','ES')
returning id as app280 \gset
insert into public.partner_application_representatives
  (application_id, full_name, cpf, email, role_title, authority_status, is_current, decided_at)
values ((:'app280')::uuid, 'Representante 280', '52998224725', 'rep280@teste.local',
        'Socio administrador', 'approved', true, now() - interval '2 days');
insert into public.site_partner_companies
  (source_application_id, cnpj, legal_name, trade_name, contact_email, city, uf, status)
values ((:'app280')::uuid,'28010001000136','Empresa 280 LTDA','Marca 280',
        'e280@teste.local','Viana','ES','active') returning id as comp280 \gset
insert into public.site_company_members
  (company_id, auth_user_id, role, full_name, cpf, source, status)
values ((:'comp280')::uuid, (:'uid_t')::uuid, 'partner_owner', 'Representante 280',
        '52998224725', 'application_promotion', 'active');
insert into public.site_partner_units (company_id, name, city, uf, status)
values ((:'comp280')::uuid, 'Unidade 280', 'Viana', 'ES', 'active');

begin;
select tests.impersonate('authenticated', :'uid_admin');
select tests.assinar_mestre_qa((:'comp280')::uuid, 'AM-280');
commit;

-- Pedido real pelo caminho v1.4 com modelo e atividade FICTÍCIOS de QA.
-- Encerra contexto de QA deixado por suítes anteriores (ordem independente).
select tests.encerrar_contexto_contratual_v14_qa();
select tests.criar_modelo_instrumento_qa(false, '280') as tpl_qa \gset
select tests.aprovar_atividade_qa('pharmacy') as ativ_qa \gset
begin;
select tests.impersonate('authenticated', :'uid_admin');
select public.admin_register_manual_commercial_order(
  (:'opp280')::uuid, (:'comp280')::uuid, 'v1', now() - interval '1 day',
  'Representante 280', (now() + interval '30 days')::date,
  'direct_benefits', 'doc://pedido-280') as r_ord \gset
commit;
select ((:'r_ord')::jsonb ->> 'order_id') as ord280 \gset
select tests.check('fixture: pedido 280 criado com instrumento QA v1.4',
    ((:'r_ord')::jsonb ->> 'ok') = 'true'
    and (select instrument_snapshot is not null from public.commercial_exclusivity_orders
          where id = (:'ord280')::uuid));
select tests.check('modelo v1.4 (sem exigencia) NAO recebe nenhum fato V2',
    (select not (instrument_snapshot ?| array['advertising_modality','advertising_spec_id',
                 'region_name','exclusivity_sequence_number','effective_activity_identity'])
       from public.commercial_exclusivity_orders where id = (:'ord280')::uuid));
select instrument_snapshot::text as snap_v14, instrument_snapshot_hash as hash_v14
  from public.commercial_exclusivity_orders where id = (:'ord280')::uuid \gset

-- ---------------------------------------------------------------------------
-- 4. MODELO V2 FICTÍCIO: exige especificação aprovada (tudo revertido)
-- ---------------------------------------------------------------------------
begin;
-- Um único modelo assinável por condição: o QA v1.4 sai de cena nesta transação.
update public.commercial_instrument_templates set lifecycle_status = 'archived'
 where id = (:'tpl_qa')::uuid;
insert into public.commercial_instrument_templates
  (template_code, template_version, template_date, source_hash, lifecycle_status,
   applies_to_fidelized, allows_outros_niche, required_snapshot_fields, notes,
   advertising_modality, requires_advertising_spec)
select '[QA FICTICIO] MODELO-V2-BANDEIRA', '0.0-qa-v2', current_date,
       encode(extensions.digest('[QA FICTICIO] instrumento v2', 'sha256'), 'hex'),
       'signable', false, false,
       t.required_snapshot_fields || array['advertising_modality','advertising_spec_id',
         'advertising_spec_version','advertising_spec_source_hash',
         'artwork_reference_width_mm','artwork_reference_height_mm','region_name',
         'region_uf','exclusivity_sequence_number','position_code',
         'effective_activity_kind','effective_activity_identity','fidelized',
         'exclusivity_period_days'],
       'QA: modelo ficticio V2', 'vehicle_roof_visual_flag', true
  from public.commercial_instrument_templates t where t.id = (:'tpl_qa')::uuid
returning id as tpl_v2 \gset

select tests.check('V2 sem especificacao aprovada: falha fechada',
    (public.commercial_build_instrument_snapshot((:'ord280')::uuid, (:'tpl_v2')::uuid)
       ->> 'reason') = 'commercial_advertising_spec_not_approved');

insert into public.commercial_advertising_specs
  (spec_code, spec_version, modality, artwork_reference_width_mm,
   artwork_reference_height_mm, source_hash)
values ('[QA FICTICIO] ESPEC-RASCUNHO', '0.0', 'vehicle_roof_visual_flag', 490, 305, repeat('d', 64));
select tests.check('especificacao em RASCUNHO nao habilita emissao',
    (public.commercial_build_instrument_snapshot((:'ord280')::uuid, (:'tpl_v2')::uuid)
       ->> 'reason') = 'commercial_advertising_spec_not_approved');

insert into public.commercial_advertising_specs
  (spec_code, spec_version, modality, artwork_reference_width_mm,
   artwork_reference_height_mm, source_hash, lifecycle_status,
   technical_responsible_name, technical_responsible_registration,
   technical_report_hash, approved_by, approved_at)
values ('[QA FICTICIO] ESPEC-BANDEIRA', '0.0-qa', 'vehicle_roof_visual_flag', 490, 305,
        encode(extensions.digest('[QA FICTICIO] anexo tecnico', 'sha256'), 'hex'),
        'approved', '[QA FICTICIO] Responsavel', '[QA] REGISTRO-0000',
        encode(extensions.digest('[QA FICTICIO] laudo', 'sha256'), 'hex'),
        (:'uid_admin')::uuid, now())
returning id as spec_qa, source_hash as spec_hash \gset

select public.commercial_build_instrument_snapshot((:'ord280')::uuid, (:'tpl_v2')::uuid) as r_v2 \gset
select tests.check('V2 com especificacao aprovada individualiza o instrumento',
    ((:'r_v2')::jsonb ->> 'ok') = 'true');
select tests.check('V2: modalidade e de bandeira visual sobre o veiculo (nunca sonora)',
    ((:'r_v2')::jsonb -> 'snapshot' ->> 'advertising_modality') = 'vehicle_roof_visual_flag');
select tests.check('V2: especificacao identificada por id, versao e hash do anexo',
    ((:'r_v2')::jsonb -> 'snapshot' ->> 'advertising_spec_id') = :'spec_qa'
    and ((:'r_v2')::jsonb -> 'snapshot' ->> 'advertising_spec_source_hash') = :'spec_hash'
    and ((:'r_v2')::jsonb -> 'snapshot' ->> 'advertising_spec_version') = '0.0-qa');
select tests.check('V2: dimensoes vem da especificacao como REFERENCIA da arte',
    ((:'r_v2')::jsonb -> 'snapshot' ->> 'artwork_reference_width_mm') = '490'
    and ((:'r_v2')::jsonb -> 'snapshot' ->> 'artwork_reference_height_mm') = '305'
    and not ((:'r_v2')::jsonb -> 'snapshot' ?| array['installed_height_mm','homologation_id']));
select tests.check('V2: regiao, exclusividade e posicao do pedido',
    ((:'r_v2')::jsonb -> 'snapshot' ->> 'region_name') = :'reg280_nome'
    and ((:'r_v2')::jsonb -> 'snapshot' ->> 'region_id') = :'reg280'
    and ((:'r_v2')::jsonb -> 'snapshot' ->> 'exclusivity_sequence_number') = '280'
    and ((:'r_v2')::jsonb -> 'snapshot' ->> 'exclusivity_id') = :'excl280'
    and ((:'r_v2')::jsonb -> 'snapshot' ->> 'position_code') = 'pharmacy');
select tests.check('V2: atividade efetiva do nicho e quantidade preservadas',
    ((:'r_v2')::jsonb -> 'snapshot' ->> 'effective_activity_kind') = 'niche'
    and ((:'r_v2')::jsonb -> 'snapshot' ->> 'effective_activity_identity') = 'pharmacy'
    and ((:'r_v2')::jsonb -> 'snapshot' ->> 'nominal_quantity') = '12');
select tests.check('V2: condicao de fidelizacao registrada (nao fidelizado)',
    ((:'r_v2')::jsonb -> 'snapshot' ->> 'fidelized') = 'false');
select tests.check('V2: TODOS os valores identicos aos do instrumento v1.4 do mesmo pedido',
    (select bool_and(((:'r_v2')::jsonb -> 'snapshot' -> k) = ((:'snap_v14')::jsonb -> k))
       from unnest(array['economic_value_cents','mei_consideration_cents','smallflags_qa_cents',
         'smallflags_main_fee_cents','smallflags_total_remuneration_cents',
         'total_monetary_funding_required_cents','participation_value_cents',
         'pricing_rule_version','contract_economics_version','benefit_settlement_mode',
         'master_agreement_version','master_document_hash','master_legal_document_id']) k));
select tests.check('V2: versao e hash do modelo e do Mestre aplicaveis no snapshot',
    ((:'r_v2')::jsonb -> 'snapshot' ->> 'instrument_template_code') = '[QA FICTICIO] MODELO-V2-BANDEIRA'
    and ((:'r_v2')::jsonb -> 'snapshot' ->> 'instrument_template_source_hash')
        = (select source_hash from public.commercial_instrument_templates where id = (:'tpl_v2')::uuid)
    and ((:'r_v2')::jsonb -> 'snapshot' ->> 'master_document_hash')
        = (select a.document_hash from public.commercial_master_agreements a
             join public.commercial_exclusivity_orders o on o.master_agreement_id = a.id
            where o.id = (:'ord280')::uuid));
select tests.check('V2: todo fato novo tem procedencia declarada',
    (select bool_and((:'r_v2')::jsonb -> 'snapshot' -> 'field_provenance' ? k)
       from unnest(array['advertising_modality','advertising_spec_id','region_name',
         'exclusivity_sequence_number','position_code','effective_activity_identity',
         'fidelized','exclusivity_period_days']) k));
select tests.check('V2: hash do instrumento difere do hash do modelo e do v1.4',
    ((:'r_v2')::jsonb ->> 'snapshot_hash') <> ((:'r_v2')::jsonb ->> 'template_source_hash')
    and ((:'r_v2')::jsonb ->> 'snapshot_hash') <> :'hash_v14');

-- Instrumento já emitido não é reescrito pelo modelo novo.
select tests.check_raises('instrumento emitido e imutavel (nao vira V2 retroativamente)',
  format($sql$update public.commercial_exclusivity_orders
                set instrument_snapshot = %L::jsonb where id = %L$sql$,
         (:'r_v2')::jsonb -> 'snapshot', :'ord280'),
  'imut');
select tests.check('instrumento v1.4 do pedido continua o original',
    (select instrument_snapshot_hash = :'hash_v14'
       from public.commercial_exclusivity_orders where id = (:'ord280')::uuid));

-- Modelo V2 em DRAFT não assina; modelo V2 de fidelizado não rege não fidelizado.
update public.commercial_instrument_templates set lifecycle_status = 'draft' where id = (:'tpl_v2')::uuid;
select tests.check('modelo V2 em draft nao individualiza',
    (public.commercial_build_instrument_snapshot((:'ord280')::uuid, (:'tpl_v2')::uuid)
       ->> 'reason') = 'commercial_instrument_template_not_signable');
update public.commercial_instrument_templates
   set lifecycle_status = 'signable', applies_to_fidelized = true where id = (:'tpl_v2')::uuid;
select tests.check('modelo V2 de fidelizado nao rege pedido nao fidelizado',
    (public.commercial_build_instrument_snapshot((:'ord280')::uuid, (:'tpl_v2')::uuid)
       ->> 'reason') = 'commercial_instrument_template_fidelity_mismatch');
rollback;

select tests.check('rollback: nenhuma especificacao e nenhum modelo V2 sobram',
    (select count(*) = 0 from public.commercial_advertising_specs)
    and (select count(*) = 0 from public.commercial_instrument_templates where requires_advertising_spec));

-- ---------------------------------------------------------------------------
-- 5. SEGMENTO: atividade efetiva pela CLASSIFICAÇÃO congelada; D9 continua
-- ---------------------------------------------------------------------------
begin;
select tests.impersonate('authenticated', :'uid_admin');
select public.admin_create_commercial_segment('pet_shop_280', 'Pet Shop 280', 'pet_shop_280',
  'Comercio varejista de artigos para animais', null, null) as r_seg \gset
reset role;
select ((:'r_seg')::jsonb ->> 'segment_id') as seg280 \gset
-- Só para fabricar o pedido de segmento: sem os gatilhos de instrumento (D9
-- bloqueia o instrumento de segmento) — dentro da transação revertida.
alter table public.commercial_exclusivity_orders disable trigger ceo_exigir_instrumento;
alter table public.commercial_exclusivity_orders disable trigger ceo_emitir_instrumento;
insert into public.partner_applications (cnpj, legal_name, trade_name, contact_email, city, uf)
values ('28020002000161','Empresa 280B LTDA','Marca 280B','e280b@teste.local','Viana','ES')
returning id as app280b \gset
insert into public.site_partner_companies
  (source_application_id, cnpj, legal_name, trade_name, contact_email, city, uf, status)
values ((:'app280b')::uuid,'28020002000161','Empresa 280B LTDA','Marca 280B',
        'e280b@teste.local','Viana','ES','active') returning id as comp280b \gset
insert into public.site_partner_units (company_id, name, city, uf, status)
values ((:'comp280b')::uuid, 'Unidade 280B', 'Viana', 'ES', 'active');
select tests.impersonate('authenticated', :'uid_admin');
select tests.assinar_mestre_qa((:'comp280b')::uuid, 'AM-280');
select public.admin_register_manual_commercial_order(
  (:'opp280o')::uuid, (:'comp280b')::uuid, 'v1', now() - interval '1 day',
  'Titular 280B', (now() + interval '30 days')::date,
  'direct_benefits', 'doc://pedido-280-seg', p_segment_id => (:'seg280')::uuid) as r_seg_ord \gset
reset role;
select ((:'r_seg_ord')::jsonb ->> 'order_id') as ord_seg \gset
select tests.check('fixture: pedido de Outros com segmento',
    ((:'r_seg_ord')::jsonb ->> 'ok') = 'true');
select public.commercial_order_effective_activity((:'ord_seg')::uuid) as ef \gset
select tests.check('segmento: identidade = classificacao congelada, nao o nome comercial',
    ((:'ef')::jsonb ->> 'kind') = 'segment'
    and ((:'ef')::jsonb ->> 'identity') = 'segment:pet_shop_280'
    and ((:'ef')::jsonb ->> 'position_code') = 'others'
    and position('Pet Shop' in ((:'ef')::jsonb ->> 'identity')) = 0);
select tests.check('segmento: identidade igual a da fidelidade (mesma regra)',
    ((:'ef')::jsonb ->> 'identity')
      = public.commercial_fidelity_identity('others', (:'seg280')::uuid));
-- Nome e classificação do segmento são imutáveis (Etapa B); arquivá-lo depois
-- não muda a atividade já congelada no pedido.
select tests.check_raises('segmento: renomear e proibido (identidade imutavel)',
  format($sql$update public.commercial_segments set display_name = 'Outro Nome' where id = %L$sql$, :'seg280'),
  'commercial_segment_immutable');
select tests.impersonate('authenticated', :'uid_admin');
select public.admin_archive_commercial_segment((:'seg280')::uuid) as r_arq \gset
reset role;
select tests.check('segmento: arquivar depois nao muda a atividade do pedido',
    ((:'r_arq')::jsonb ->> 'ok') = 'true' and
    (public.commercial_order_effective_activity((:'ord_seg')::uuid) ->> 'identity')
      = 'segment:pet_shop_280');
-- D9 continua: nem modelo assinável individualiza segmento/Outros.
select tests.check('D9 mantido: instrumento de segmento/Outros continua bloqueado',
    (public.commercial_build_instrument_snapshot((:'ord_seg')::uuid, (:'tpl_qa')::uuid)
       ->> 'reason') = 'commercial_instrument_segment_activity_unavailable');
rollback;

-- ---------------------------------------------------------------------------
-- 6. NADA DE ACEITE AUTOMÁTICO OU RETROATIVO
-- ---------------------------------------------------------------------------
select tests.check('esta suite nao criou aceite de Termos (contratacao manual nao aceita termos)',
    (select count(*) = 0 from public.legal_acceptances a
       join public.commercial_exclusivity_orders o on o.legal_acceptance_id = a.id
      where o.company_id = (:'comp280')::uuid));
select tests.encerrar_contexto_contratual_v14_qa();
select tests.check('ao final: nenhuma especificacao, nenhum modelo V2, nenhum modelo assinavel',
    (select count(*) = 0 from public.commercial_advertising_specs)
    and (select count(*) = 0 from public.commercial_instrument_templates where requires_advertising_spec)
    and (select count(*) = 0 from public.commercial_instrument_templates where lifecycle_status = 'signable'));

select tests.finish('280_contract_v2_vehicle_visual_advertising');
