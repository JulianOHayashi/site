-- ===========================================================================
-- 297 — R4.1: nenhuma guarda é íntegra só por ter o nome esperado.
-- Migration 20261113200000. Contraprovas reais, sempre em transações
-- revertidas:
--   1. estado: ENABLE REPLICA (R), ENABLE ALWAYS (A), DISABLE (D), ausente e
--      session_replication_role = replica são recusados;
--   2. definição: mesmo nome e mesmo estado com OUTRA função executada,
--      função de mesmo nome com outro corpo, outro evento, condição WHEN,
--      argumentos, gatilho a mais e privilégio de execução alterado;
--   3. executor técnico × aprovação de lançamento (documento externo);
--   4. pré-requisito da QA na ativação.
-- Aprovações e procedimentos aqui são FIXTURES [QA FICTICIO], revertidas.
-- ===========================================================================
\set ON_ERROR_STOP on
select tests.reset_results();
select tests.fechar_portao_autoatendimento_qa();

-- O manifesto VIGENTE é o mais recente (R4.2 em diante acrescentam linhas;
-- o R4.1 continua como linha histórica publicada).
create or replace view pg_temp.manifesto_vigente as
  select * from public.commercial_guard_manifests order by id desc limit 1;
select tests.check('manifesto R4.1 publicado (SHA-256 bc3f7441...) presente; o vigente e igual ao catalogo vivo',
    exists (select 1 from public.commercial_guard_manifests
             where manifest_label = 'R4.1'
               and catalog_sha256 = 'bc3f7441b780b6b66fa6086b21633dc52bd942401f2e61da74ac0a85e1cb11d7')
    and (select catalog from pg_temp.manifesto_vigente) = public.commercial_guard_catalog()
    and public.commercial_guard_integrity_failures() = array[]::text[]);
select tests.check('manifesto cobre TODOS os gatilhos das tabelas guardadas, cada um com estado, definicao, funcao, eventos, argumentos e condicao',
    (select count(*) from jsonb_object_keys((select catalog->'triggers' from pg_temp.manifesto_vigente)))
      = (select count(*) from pg_trigger t
          where not t.tgisinternal
            and t.tgrelid in (select to_regclass(x->>'table')
                                from jsonb_array_elements((select catalog->'tables' from pg_temp.manifesto_vigente)) x))
    and not exists (select 1 from jsonb_each((select catalog->'triggers' from pg_temp.manifesto_vigente)) e
                     where not (e.value ?& array['state', 'definition_sha256', 'function', 'function_sha256',
                                                 'tgtype', 'args_sha256', 'when', 'columns'])
                        or e.value->>'state' <> 'O'
                        or e.value->>'definition_sha256' !~ '^[0-9a-f]{64}$'
                        or e.value->>'function_sha256' !~ '^[0-9a-f]{64}$'));
select tests.check('ninguem alem do dono escreve manifesto, aprovacao de lancamento ou procedimento de QA',
    not exists (
      select 1 from unnest(array['anon','authenticated','service_role']) r,
                    unnest(array['public.commercial_guard_manifests',
                                 'public.commercial_pricing_activation_approvals',
                                 'public.commercial_qa_operational_procedures']) t,
                    unnest(array['INSERT','UPDATE','DELETE','TRUNCATE']) p
       where has_table_privilege(r, t, p)));
select tests.check('nenhuma aprovacao de lancamento ou procedimento de QA real no banco',
    not exists (select 1 from public.commercial_pricing_activation_approvals)
    and not exists (select 1 from public.commercial_qa_operational_procedures));
select tests.check_raises('manifesto aprovado e imutavel',
  $sql$update public.commercial_guard_manifests set manifest_label = 'outro'$sql$, 'manifesto_guardas_imutavel');
select tests.check_raises('manifesto so registra a configuracao VIVA (nao aceita catalogo inventado)',
  $sql$insert into public.commercial_guard_manifests (manifest_label, catalog, source_reference)
       values ('inventado', '{"triggers": {}}'::jsonb, '[QA FICTICIO] manifesto inventado')$sql$,
  'manifesto_guardas_divergente');

-- Projeção da impressão digital da R4 (nome -> estado): o que a R4 via.
create or replace function pg_temp.visao_r4() returns jsonb language sql as $f$
  select jsonb_object_agg(t.tgrelid::regclass::text || '.' || t.tgname, t.tgenabled::text)
    from pg_trigger t where not t.tgisinternal and t.tgrelid::regclass::text like 'commercial_%'
$f$;
create or replace function pg_temp.falhas() returns jsonb language sql as $f$
  select public.commercial_pricing_activation_preflight(4)->'failures'
$f$;

-- ---------------------------------------------------------------------------
-- 1. ESTADO DO GATILHO
-- ---------------------------------------------------------------------------
begin;
select tests.preparar_ativacao_sf_v15_qa('297A', 'A');
select tests.check('linha de base: guardas iguais ao manifesto e pre-verificacao APROVADA',
    (public.commercial_pricing_activation_preflight(4)->>'ok')::boolean);

savepoint replica;
alter table public.commercial_exclusivity_orders enable replica trigger ceo_pagamento_confere_snapshot;
select tests.check('ENABLE REPLICA: estado R, que a R4 aceitava (diferente de D)',
    (select tgenabled from pg_trigger where tgname = 'ceo_pagamento_confere_snapshot') = 'R');
select tests.check('ENABLE REPLICA: pre-verificacao reprova e aponta estado R contra o aprovado O',
    pg_temp.falhas() ? 'guard_trigger_state_not_approved:public.commercial_exclusivity_orders.ceo_pagamento_confere_snapshot:R(aprovado O)');
select tests.check('ENABLE REPLICA: ativacao autorizada e recusada, v4 continua preparada',
    (select (r->>'ok')::boolean = false and r->>'reason' = 'activation_preconditions_pending'
       from (select tests.ativar_sf_v15_qa(4, '[QA FICTICIO] ativacao 297 com gatilho R') r) x)
    and (select status from public.commercial_pricing_rules where version = 4) = 'prepared');
rollback to savepoint replica;

savepoint replica_inerte;
-- Por que R importa: em sessão normal o gatilho R NÃO executa. Com a guarda do
-- registro em R, o INSERT direto deixa de ser barrado por ela...
alter table public.commercial_pricing_activation_log enable replica trigger cpal_somente_pelo_procedimento;
insert into public.commercial_pricing_activation_log (pricing_rule_version, authorization_reference, preflight)
values (4, '[QA FICTICIO] registro gravado com a guarda em R', '{}'::jsonb);
select tests.check('guarda em R fica inerte em sessao normal (o INSERT direto passou por ela)',
    exists (select 1 from public.commercial_pricing_activation_log
             where authorization_reference = '[QA FICTICIO] registro gravado com a guarda em R'));
-- ...mas a configuração não é a aprovada: nada ativa.
select tests.check('... e a pre-verificacao reprova a guarda em R',
    pg_temp.falhas() ? 'guard_trigger_state_not_approved:public.commercial_pricing_activation_log.cpal_somente_pelo_procedimento:R(aprovado O)');
select tests.check_raises('... e a transicao prepared -> active continua recusada',
  $sql$update public.commercial_pricing_rules set status = 'active', effective_from = now() where version = 4$sql$,
  'ativacao_nao_autorizada');
rollback to savepoint replica_inerte;

savepoint always;
alter table public.commercial_pricing_rules enable always trigger cpr_protect;
select tests.check('ENABLE ALWAYS (A): estado nao aprovado, pre-verificacao reprova',
    pg_temp.falhas() ? 'guard_trigger_state_not_approved:public.commercial_pricing_rules.cpr_protect:A(aprovado O)');
select tests.check('ENABLE ALWAYS (A): ativacao recusada',
    (tests.ativar_sf_v15_qa(4, '[QA FICTICIO] ativacao 297 com gatilho A')->>'ok')::boolean = false);
rollback to savepoint always;

savepoint desligado;
alter table public.commercial_payments disable trigger cp_valor_confere_pedido;
select tests.check('DISABLE (D): pre-verificacao reprova e ativacao recusada',
    pg_temp.falhas() ? 'guard_trigger_state_not_approved:public.commercial_payments.cp_valor_confere_pedido:D(aprovado O)'
    and (tests.ativar_sf_v15_qa(4, '[QA FICTICIO] ativacao 297 com gatilho D')->>'ok')::boolean = false);
rollback to savepoint desligado;

savepoint ausente;
drop trigger cfi_bloquear_conjunto on public.commercial_flag_set_inspections;
select tests.check('gatilho AUSENTE: pre-verificacao reprova',
    pg_temp.falhas() ? 'guard_trigger_missing:public.commercial_flag_set_inspections.cfi_bloquear_conjunto');
rollback to savepoint ausente;

savepoint sessao_replica;
set local session_replication_role = replica;
select tests.check('session_replication_role = replica: procedimento recusa antes de tudo',
    (public.admin_activate_pricing_rule(4, '[QA FICTICIO] aprovacao de lancamento 297A')->>'reason')
      = 'session_replication_role_not_origin');
select tests.check('session_replication_role = replica: pre-verificacao reprova',
    pg_temp.falhas() ? 'session_replication_role_not_origin:replica');
rollback to savepoint sessao_replica;
rollback;

-- ---------------------------------------------------------------------------
-- 2. DEFINIÇÃO: mesmo nome, mesmo estado, outra coisa executada
-- ---------------------------------------------------------------------------
begin;
select tests.preparar_ativacao_sf_v15_qa('297B', 'A');
create function public.zz_guarda_inerte_297() returns trigger language plpgsql as $f$
begin
  return coalesce(new, old);
end $f$;
select pg_temp.visao_r4() as visao_r4_base \gset

savepoint outra_funcao;
do $do$
declare d text;
begin
  select pg_get_triggerdef(oid) into d from pg_trigger where tgname = 'ceo_pagamento_confere_snapshot';
  d := replace(d, 'CREATE TRIGGER', 'CREATE OR REPLACE TRIGGER');
  d := regexp_replace(d, 'EXECUTE FUNCTION .*$', 'EXECUTE FUNCTION public.zz_guarda_inerte_297()');
  execute d;
end $do$;
select tests.check('troca da funcao executada: mesmo nome, mesmo estado O, mesmo momento e eventos',
    (select tgenabled = 'O' and tgfoid = 'public.zz_guarda_inerte_297()'::regprocedure
       from pg_trigger where tgname = 'ceo_pagamento_confere_snapshot'));
select tests.check('troca da funcao executada: a impressao digital da R4 (nome e estado) NAO via diferenca',
    pg_temp.visao_r4() = (:'visao_r4_base')::jsonb);
select tests.check('troca da funcao executada: o manifesto detecta (definicao, funcao e SHA-256 da funcao)',
    public.commercial_guard_integrity_failures()
      @> array['guard_trigger_definition_divergent:public.commercial_exclusivity_orders.ceo_pagamento_confere_snapshot:definition_sha256,function,function_sha256']
    and encode(sha256(convert_to(public.commercial_guard_catalog()::text, 'UTF8')), 'hex')
        <> (select catalog_sha256 from pg_temp.manifesto_vigente));
select tests.check('troca da funcao executada: pre-verificacao reprova e ativacao recusada',
    not (public.commercial_pricing_activation_preflight(4)->>'ok')::boolean
    and (tests.ativar_sf_v15_qa(4, '[QA FICTICIO] ativacao 297 com funcao trocada')->>'ok')::boolean = false
    and (select status from public.commercial_pricing_rules where version = 4) = 'prepared');
rollback to savepoint outra_funcao;

savepoint mesmo_nome_outro_corpo;
create or replace function public.ceo_pagamento_confere_snapshot() returns trigger
language plpgsql set search_path to 'pg_catalog' as $f$
begin
  return new;
end $f$;
select tests.check('funcao de mesmo nome com outro corpo: gatilho e funcao divergentes, ativacao recusada',
    public.commercial_guard_integrity_failures()
      @> array['guard_trigger_definition_divergent:public.commercial_exclusivity_orders.ceo_pagamento_confere_snapshot:function_sha256',
               'guard_function_divergent:public.ceo_pagamento_confere_snapshot()']
    and (tests.ativar_sf_v15_qa(4, '[QA FICTICIO] ativacao 297 com corpo trocado')->>'ok')::boolean = false);
rollback to savepoint mesmo_nome_outro_corpo;

savepoint outro_evento;
create or replace trigger cpr_protect before insert or delete on public.commercial_pricing_rules
  for each row execute function public.commercial_pricing_rules_protect();
select tests.check('mesmo nome e funcao, eventos diferentes (sem UPDATE): tgtype e definicao divergentes, ativacao recusada',
    public.commercial_guard_integrity_failures()
      @> array['guard_trigger_definition_divergent:public.commercial_pricing_rules.cpr_protect:definition_sha256,tgtype']
    and (tests.ativar_sf_v15_qa(4, '[QA FICTICIO] ativacao 297 com evento trocado')->>'ok')::boolean = false);
rollback to savepoint outro_evento;

savepoint condicao;
create or replace trigger ceo_pagamento_confere_snapshot before insert or update on public.commercial_exclusivity_orders
  for each row when (false) execute function public.ceo_pagamento_confere_snapshot();
select tests.check('mesmo nome, funcao e eventos, com condicao WHEN (false): divergente, ativacao recusada',
    public.commercial_guard_integrity_failures()
      @> array['guard_trigger_definition_divergent:public.commercial_exclusivity_orders.ceo_pagamento_confere_snapshot:definition_sha256,when']
    and (tests.ativar_sf_v15_qa(4, '[QA FICTICIO] ativacao 297 com condicao')->>'ok')::boolean = false);
rollback to savepoint condicao;

savepoint argumentos;
create or replace trigger cpal_somente_pelo_procedimento before insert on public.commercial_pricing_activation_log
  for each row execute function public.commercial_pricing_activation_log_guard('ignorar');
select tests.check('mesmo nome e funcao com argumentos: divergente',
    public.commercial_guard_integrity_failures()
      @> array['guard_trigger_definition_divergent:public.commercial_pricing_activation_log.cpal_somente_pelo_procedimento:definition_sha256,args_sha256']);
rollback to savepoint argumentos;

savepoint gatilho_extra;
create trigger zz_reescreve_297 before update on public.commercial_pricing_rules
  for each row execute function public.zz_guarda_inerte_297();
select tests.check('gatilho A MAIS numa tabela guardada: nao aprovado, ativacao recusada',
    pg_temp.falhas() ? 'guard_trigger_not_approved:public.commercial_pricing_rules.zz_reescreve_297'
    and (tests.ativar_sf_v15_qa(4, '[QA FICTICIO] ativacao 297 com gatilho extra')->>'ok')::boolean = false);
rollback to savepoint gatilho_extra;

savepoint privilegio;
grant execute on function public.admin_activate_pricing_rule(integer, text) to authenticated;
select tests.check('privilegio de execucao do procedimento alterado: divergente, ativacao recusada',
    pg_temp.falhas() ? 'guard_function_divergent:public.admin_activate_pricing_rule(integer,text)'
    and (tests.ativar_sf_v15_qa(4, '[QA FICTICIO] ativacao 297 com privilegio')->>'ok')::boolean = false);
rollback to savepoint privilegio;

select tests.check('restauradas as guardas, nada sobrou divergente',
    public.commercial_guard_integrity_failures() = array[]::text[]);

-- ---------------------------------------------------------------------------
-- 3. EXECUTOR TÉCNICO × APROVAÇÃO DE LANÇAMENTO
-- ---------------------------------------------------------------------------
select tests.check('sem aprovacao registrada para a referencia: recusada',
    (public.admin_activate_pricing_rule(4, '[QA FICTICIO] referencia nunca aprovada')->>'reason')
      = 'activation_approval_not_registered');
savepoint outra_versao;
insert into public.commercial_pricing_activation_approvals
  (pricing_rule_version, approval_reference, approval_document_sha256, approver_as_stated, approved_on_as_stated)
values (3, '[QA FICTICIO] aprovacao da versao 3', repeat('b', 64), '[QA FICTICIO] Aprovador', current_date);
select tests.check('aprovacao de OUTRA versao nao serve',
    (public.admin_activate_pricing_rule(4, '[QA FICTICIO] aprovacao da versao 3')->>'reason')
      = 'activation_approval_not_registered');
rollback to savepoint outra_versao;
select tests.check_raises('aprovacao exige SHA-256 do documento externo',
  $sql$insert into public.commercial_pricing_activation_approvals
         (pricing_rule_version, approval_reference, approval_document_sha256, approver_as_stated, approved_on_as_stated)
       values (4, '[QA FICTICIO] sem hash valido', 'nao-e-hash', '[QA FICTICIO] Aprovador', current_date)$sql$,
  'cpaa_sha256');
select tests.check_raises('aprovacao de lancamento e imutavel',
  $sql$update public.commercial_pricing_activation_approvals set approver_as_stated = 'outra pessoa'$sql$,
  'aprovacao_lancamento_imutavel');
select tests.check_raises('registro forjado com aprovacao valida continua recusado (so o procedimento grava)',
  $sql$insert into public.commercial_pricing_activation_log (pricing_rule_version, authorization_reference, preflight, activation_approval_id)
       select 4, approval_reference, '{}'::jsonb, id from public.commercial_pricing_activation_approvals limit 1$sql$,
  'activation_log_somente_pelo_procedimento');

insert into public.commercial_pricing_activation_approvals
  (pricing_rule_version, approval_reference, approval_document_sha256, approver_as_stated,
   approved_on_as_stated, registered_by_db_role, registered_at, registration_txid)
values (4, '[QA FICTICIO] lancamento 297 aprovado',
        encode(sha256(convert_to('[QA FICTICIO] documento 297', 'UTF8')), 'hex'),
        '[QA FICTICIO] Aprovador do lancamento', current_date,
        'Fulano de Tal (informado pelo chamador)', '2000-01-01', 1)
returning id as apr297 \gset
select tests.check('quem registra a aprovacao e o papel de banco do servidor, nao o informado pelo chamador',
    (select registered_by_db_role = session_user and registered_at > '2000-01-02'
            and registration_txid = txid_current()
       from public.commercial_pricing_activation_approvals where id = (:'apr297')::uuid));
select set_config('request.jwt.claims', '{"sub": "00000000-0000-0000-0000-000000000297"}', true);
select public.admin_activate_pricing_rule(4, '[QA FICTICIO] lancamento 297 aprovado') as r297 \gset
select set_config('request.jwt.claims', '', true);
select tests.check('com as guardas corretas a ativacao autorizada PASSA',
    ((:'r297')::jsonb->>'ok') = 'true'
    and (select status from public.commercial_pricing_rules where version = 4) = 'active');
select tests.check('registro: executor tecnico (papel de banco, sub do JWT) separado da aprovacao (referencia, SHA-256 do documento, aprovador declarado)',
    (select l.actor = session_user and l.executor_db_role = session_user
            and l.executor_jwt_sub = '00000000-0000-0000-0000-000000000297'
            and l.activation_approval_id = (:'apr297')::uuid
            and l.approval_document_sha256 = a.approval_document_sha256
            and l.guard_catalog_sha256 = m.catalog_sha256 and l.guard_manifest_id = m.id
            and l.guard_catalog_sha256 = encode(sha256(convert_to(l.guard_fingerprint::text, 'UTF8')), 'hex')
       from public.commercial_pricing_activation_log l
       join public.commercial_pricing_activation_approvals a on a.id = l.activation_approval_id
       cross join pg_temp.manifesto_vigente m
      where l.pricing_rule_version = 4));
select tests.check('recibo devolvido para guarda externa: ids, transacao, executor, aprovacao e catalogo',
    (select (:'r297')::jsonb->'receipt' ?& array['activation_log_id', 'txid', 'created_at', 'executor_db_role',
              'executor_jwt_sub', 'approval_reference', 'approval_document_sha256', 'approver_as_stated',
              'guard_catalog_sha256', 'guard_manifest_id'])
    and ((:'r297')::jsonb->'receipt'->>'approver_as_stated') = '[QA FICTICIO] Aprovador do lancamento'
    and ((:'r297')::jsonb->'receipt'->>'guard_catalog_sha256')
        = (select catalog_sha256 from pg_temp.manifesto_vigente));
rollback;

-- ---------------------------------------------------------------------------
-- 4. PRÉ-REQUISITO DA QA NA ATIVAÇÃO
-- ---------------------------------------------------------------------------
begin;
select tests.preparar_ativacao_sf_v15_qa('297Q', 'A');
-- Simula "sem procedimento aprovado": remove a fixture desligando a trava só
-- nesta transação revertida e religando em seguida.
alter table public.commercial_qa_operational_procedures disable trigger cqop_protect;
delete from public.commercial_qa_operational_procedures;
alter table public.commercial_qa_operational_procedures enable trigger cqop_protect;
select tests.check('sem procedimento operacional de QA aprovado: pre-verificacao reprova',
    pg_temp.falhas() ? 'qa_operational_procedure_missing:SF-v1.5'
    and public.commercial_guard_integrity_failures() = array[]::text[]);
select tests.check('sem procedimento operacional de QA aprovado: ativacao recusada',
    (tests.ativar_sf_v15_qa(4, '[QA FICTICIO] ativacao 297 sem QA')->>'ok')::boolean = false
    and (select status from public.commercial_pricing_rules where version = 4) = 'prepared');
select tests.check_raises('procedimento que nao cobre nao cumprimento e recusado',
  $sql$insert into public.commercial_qa_operational_procedures
         (contract_economics_version, procedure_reference, procedure_document_sha256, covers_authorization,
          covers_product_receipt, covers_test_execution, covers_evidence_validation, covers_noncompliance,
          approver_as_stated, approved_on_as_stated)
       values ('SF-v1.5', '[QA FICTICIO] procedimento incompleto', repeat('c', 64), true, true, true, true, false,
               '[QA FICTICIO] Aprovador', current_date)$sql$,
  'cqop_cobertura_completa');
savepoint outra_economia;
select tests.registrar_procedimento_qa_ficticio('SF-v1.4', '297');
select tests.check('procedimento de outra versao economica nao serve',
    pg_temp.falhas() ? 'qa_operational_procedure_missing:SF-v1.5');
rollback to savepoint outra_economia;
select tests.registrar_procedimento_qa_ficticio('SF-v1.5', '297Q2');
select tests.check('com procedimento aprovado para a SF-v1.5 a pre-verificacao passa',
    (public.commercial_pricing_activation_preflight(4)->>'ok')::boolean);
select tests.check_raises('procedimento de QA registrado e imutavel',
  $sql$delete from public.commercial_qa_operational_procedures$sql$, 'procedimento_qa_imutavel');
rollback;

select tests.check('apos a suite: nada vazou (v4 preparada, sem ativacao, aprovacao, procedimento, gatilho ou funcao de teste)',
    (select status from public.commercial_pricing_rules where version = 4) = 'prepared'
    and not exists (select 1 from public.commercial_pricing_activation_log)
    and not exists (select 1 from public.commercial_pricing_activation_approvals)
    and not exists (select 1 from public.commercial_qa_operational_procedures)
    and to_regprocedure('public.zz_guarda_inerte_297()') is null
    and public.commercial_guard_integrity_failures() = array[]::text[]);

select tests.finish('297_r41_integridade_guardas');
