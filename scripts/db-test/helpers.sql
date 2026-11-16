-- ============================================================================
-- Helpers de teste SQL (schema tests) — somente harness local, nunca remoto.
--
-- Padrão de uso em supabase/tests/*.sql:
--   select tests.reset_results();
--   ...
--   select tests.check('nome do caso', <condição boolean>);
--   ...
--   select tests.finish('nome do arquivo');   -- ERRO se algum caso falhou
--
-- Impersonação de ator (dentro de transação, efeito até o fim da tx):
--   select tests.impersonate('authenticated', '<uuid>');
--   select tests.impersonate('anon', null);
--   select tests.impersonate('service_role', null);
-- Depois de impersonar um role não-superusuário não é possível voltar a
-- postgres na mesma transação: cada cenário deve rodar em BEGIN ... ROLLBACK.
-- ============================================================================

create schema if not exists tests;

create table if not exists tests.results (
    seq bigint generated always as identity primary key,
    name text not null,
    passed boolean not null,
    noted_at timestamptz not null default clock_timestamp()
);

grant usage on schema tests to anon, authenticated, service_role;

-- R4: contadores que SOBREVIVEM a ROLLBACK. As suítes isolam cenários em
-- transações revertidas; as linhas de tests.results escritas lá dentro somem
-- com o rollback, e o rodapé contava só o que ficou fora delas (ex.: 295
-- imprimia 69 PASS e o rodapé dizia 10). nextval() não é transacional: o
-- rodapé passa a contar exatamente as linhas PASS/FAIL impressas.
create sequence if not exists tests.pass_count;
create sequence if not exists tests.fail_count;
grant usage, select on sequence tests.pass_count, tests.fail_count to anon, authenticated, service_role;

create or replace function tests.reset_results() returns void
    language sql security definer set search_path to 'pg_catalog'
    as $$
      truncate table tests.results restart identity;
      select setval('tests.pass_count', 1, false);
      select setval('tests.fail_count', 1, false);
    $$;

create or replace function tests.check(p_name text, p_cond boolean)
    returns text
    language plpgsql security definer set search_path to 'pg_catalog'
    as $$
begin
  insert into tests.results (name, passed)
  values (p_name, coalesce(p_cond, false));
  if coalesce(p_cond, false) then
    perform nextval('tests.pass_count');
  else
    perform nextval('tests.fail_count');
  end if;
  return case when coalesce(p_cond, false)
              then 'PASS  ' || p_name
              else 'FAIL  ' || p_name end;
end $$;

-- Registra PASS quando a execução de p_sql levanta erro cuja mensagem contém
-- p_expected_error (teste negativo). Executa em sub-bloco: o erro é absorvido.
-- SECURITY INVOKER de propósito: o SQL dinâmico roda com o papel IMPERSONADO
-- (senão todo teste negativo rodaria como postgres e passaria em falso).
create or replace function tests.check_raises(p_name text, p_sql text, p_expected_error text)
    returns text
    language plpgsql set search_path to 'pg_catalog'
    as $$
declare
  v_msg text;
begin
  begin
    execute p_sql;
  exception when others then
    get stacked diagnostics v_msg = message_text;
    if position(p_expected_error in v_msg) > 0 then
      return tests.check(p_name, true);
    end if;
    return tests.check(p_name || ' (erro inesperado: ' || v_msg || ')', false);
  end;
  return tests.check(p_name || ' (nenhum erro levantado)', false);
end $$;

create or replace function tests.finish(p_suite text) returns text
    language plpgsql security definer set search_path to 'pg_catalog'
    as $$
declare
  v_pass int;
  v_fail int;
  v_failed text;
begin
  -- R4: contagem pelas sequências (inclui o que rodou em transações
  -- revertidas); os nomes das falhas vêm da tabela e das linhas FAIL impressas.
  select case when is_called then last_value else 0 end into v_pass from tests.pass_count;
  select case when is_called then last_value else 0 end into v_fail from tests.fail_count;
  if v_fail > 0 then
    select coalesce(string_agg(name, E'\n  '), '(ver linhas FAIL na saida)') into v_failed
      from tests.results where not passed;
    raise exception E'SUITE % FALHOU: % PASS / % FAIL\n  %',
        p_suite, v_pass, v_fail, v_failed;
  end if;
  return format('SUITE %s: %s PASS / 0 FAIL', p_suite, v_pass);
end $$;

create or replace function tests.impersonate(p_role text, p_uid uuid)
    returns void
    language plpgsql
    as $$
begin
  if p_role not in ('anon', 'authenticated', 'service_role') then
    raise exception 'role de teste invalido: %', p_role;
  end if;
  perform set_config('request.jwt.claims',
      case when p_uid is null
           then json_build_object('role', p_role)::text
           else json_build_object('role', p_role, 'sub', p_uid)::text
      end, true);
  perform set_config('role', p_role, true);
end $$;

-- Cria um usuário auth de teste com e-mail derivado e devolve o id.
create or replace function tests.mk_user(p_tag text)
    returns uuid
    language plpgsql security definer set search_path to 'pg_catalog'
    as $$
declare
  v_id uuid := gen_random_uuid();
begin
  insert into auth.users (id, email) values (v_id, p_tag || '@teste.local');
  return v_id;
end $$;

-- ---------------------------------------------------------------------------
-- Acordo Mestre FICTÍCIO de QA.
--
-- POR QUE ESTE HELPER EXISTE
--
-- A regra C2 exige que a versão assinada por uma empresa corresponda a um
-- `master_agreement` efetivamente publicado em `legal_documents`. As fixtures
-- antigas chamavam `admin_register_master_agreement(..., 'v1', ...)` sem que
-- 'v1' existisse como documento publicado, então a função passou a recusar —
-- corretamente. As fixtures é que estavam defasadas em relação ao modelo
-- legal, não a regra.
--
-- O conteúdo aqui é INEQUIVOCAMENTE fictício. O Acordo Mestre congelado de
-- verdade jamais é usado como fixture: um texto de teste não pode ser
-- confundido com instrumento jurídico, nem o hash de QA com o oficial.
--
-- Mantém a relação inteira, que é o que os testes precisam exercitar:
--   empresa -> commercial_master_agreement assinado -> legal_document exato
--           -> versão e hash exatos.
-- ---------------------------------------------------------------------------
create or replace function tests.publicar_mestre_qa(p_version text)
returns uuid
language plpgsql
-- DEFINER: as suites chamam este helper sob impersonacao de admin ou de
-- titular, que nao tem privilegio direto em legal_documents. Isto e
-- infraestrutura de teste, nao caminho de producao: a publicacao real
-- continua passando por admin_publish_legal_document, com m1_exigir_admin.
security definer
as $$
declare
  -- Âncora FIXA, não `now()`. Janelas de vigência derivadas de `now()`
  -- colidem quando várias publicações acontecem na mesma transação ou no
  -- mesmo segundo, e o schema exige effective_to > effective_from. Ancorar
  -- numa data fixa torna as janelas determinísticas e independentes do relógio.
  c_ancora  constant timestamptz := timestamptz '2026-01-01 00:00:00+00';
  c_passo   constant interval    := interval '1 day';
  v_admin   uuid;
  v_id      uuid;
  v_conteudo text;
  v_hash    text;
  v_seq     int;
  v_inicio  timestamptz;
begin
  -- Já publicado: idempotente, para a suíte poder chamar à vontade.
  select id into v_id from public.legal_documents
   where doc_type = 'master_agreement' and version = p_version;
  if found then
    return v_id;
  end if;

  -- site_admins tem apenas user_id e created_at: nao ha coluna de status.
  select user_id into v_admin
    from public.site_admins
   order by created_at
   limit 1;
  if v_admin is null then
    raise exception 'fixture: nenhum site_admin para publicar o Mestre de QA';
  end if;

  v_conteudo := '# DOCUMENTO FICTICIO DE TESTE — NAO E INSTRUMENTO JURIDICO' || E'\n\n'
             || 'Acordo Mestre de QA, versao ' || p_version || '.' || E'\n'
             || 'Gerado pelo harness local para exercitar o vinculo legal. '
             || 'Sem valor contratual. Nao corresponde ao conteudo congelado.';
  -- Hash do conteúdo real deste documento de teste: versão e hash precisam
  -- ser coerentes, porque é exatamente isso que a trava C2 verifica.
  v_hash := encode(extensions.digest(v_conteudo, 'sha256'), 'hex');

  -- Janela monotônica: a n-ésima publicação começa em âncora + n passos.
  -- Como a sequência vem da contagem de linhas já existentes, duas chamadas
  -- nunca recebem o mesmo instante, mesmo dentro da mesma transação.
  select count(*) into v_seq
    from public.legal_documents where doc_type = 'master_agreement';
  v_inicio := c_ancora + (v_seq * c_passo);

  if v_inicio >= now() then
    raise exception 'fixture: janela de vigencia QA ultrapassou o presente (seq=%)', v_seq;
  end if;

  -- Só um master_agreement pode estar vigente por vez. O anterior é encerrado
  -- EXATAMENTE no início do novo: intervalo semiaberto, sem sobreposição e com
  -- effective_to estritamente posterior ao seu próprio effective_from.
  update public.legal_documents
     set effective_to = v_inicio, updated_at = now()
   where doc_type = 'master_agreement'
     and (effective_to is null or effective_to > v_inicio);

  insert into public.legal_documents
    (doc_type, version, title, content, content_hash, status,
     is_material_change, effective_from, published_at, published_by, notes)
  values
    ('master_agreement', p_version,
     '[QA FICTICIO] Acordo Mestre de teste ' || p_version,
     v_conteudo, v_hash, 'published', false,
     v_inicio, v_inicio, v_admin,
     'Fixture do harness local. Conteudo ficticio, sem valor juridico.')
  returning id into v_id;

  return v_id;
end $$;

/**
 * Publica o Mestre de QA e registra a assinatura da empresa contra ELE.
 * Substitui a chamada crua a `admin_register_master_agreement` nas fixtures:
 * garante que o documento exista antes, preservando a cadeia completa.
 */
create or replace function tests.assinar_mestre_qa(
  p_company_id uuid,
  p_version    text default 'v1',
  p_signed_at  timestamptz default null,
  p_signatario text default 'Responsavel QA',
  p_referencia text default null
) returns jsonb
language plpgsql
security definer
as $$
declare
  v_r jsonb;
begin
  perform tests.publicar_mestre_qa(p_version);
  v_r := public.admin_register_master_agreement(
           p_company_id, p_version,
           coalesce(p_signed_at, now() - interval '1 day'),
           p_signatario, p_referencia);
  if (v_r ->> 'ok') is distinct from 'true' then
    raise exception 'fixture: assinatura do Mestre de QA falhou: %', v_r ->> 'reason';
  end if;
  return v_r;
end $$;

grant execute on function
    tests.publicar_mestre_qa(text),
    tests.assinar_mestre_qa(uuid, text, timestamptz, text, text),
    tests.reset_results(),
    tests.check(text, boolean),
    tests.check_raises(text, text, text),
    tests.finish(text),
    tests.impersonate(text, uuid),
    tests.mk_user(text)
  to anon, authenticated, service_role;

-- ---------------------------------------------------------------------------
-- Modelo de instrumento FICTICIO para QA.
--
-- A minuta v1.4 real esta registrada como `draft` porque a propria fonte
-- congelada diz "NAO ASSINAR AINDA". Usar o rascunho legal real como se fosse
-- aprovado, para fazer teste passar, seria tratar como assinavel exatamente o
-- documento que manda nao assinar. Este helper cria um modelo INEQUIVOCAMENTE
-- ficticio, com hash proprio derivado do texto de QA, e marca ele como
-- assinavel — nunca o real.
-- ---------------------------------------------------------------------------
create or replace function tests.criar_modelo_instrumento_qa(
  p_fidelized boolean default false,
  p_sufixo    text    default 'A'
) returns uuid
language plpgsql
security definer
set search_path to public, extensions, pg_catalog
as $$
declare
  v_id    uuid;
  v_texto text;
  v_code  text;
begin
  v_code := '[QA FICTICIO] MODELO-INSTRUMENTO-' || p_sufixo
            || case when p_fidelized then '-FIDELIZADO' else '-FUNDADOR' end;
  v_texto := 'TEXTO DE QA INTEIRAMENTE FICTICIO. Nao e minuta, nao e documento '
          || 'juridico, nao tem valor contratual algum. Serve somente para '
          || 'provar o comportamento do banco. ' || v_code;

  insert into public.commercial_instrument_templates
    (template_code, template_version, template_date, source_hash,
     lifecycle_status, applies_to_fidelized, allows_outros_niche,
     required_snapshot_fields, notes)
  values
    (v_code, '0.0-qa', current_date,
     encode(extensions.digest(v_texto, 'sha256'), 'hex'),
     'signable', p_fidelized, false,
     (select required_snapshot_fields
        from public.commercial_instrument_templates
       where template_code = 'SF-MINUTA-PRESENCIAL-v1.4'),
     'Fixture de QA. NAO e a minuta v1.4. Criado assinavel de proposito para '
     'exercitar o caminho completo sem promover o rascunho legal real.')
  returning id into v_id;

  return v_id;
end;
$$;

-- ---------------------------------------------------------------------------
-- Atividade contratada FICTICIA para QA.
--
-- Substitui o antigo tests.fatos_instrumento_qa(): o construtor do snapshot
-- deixou de aceitar fato de chamador, e por isso a atividade de teste tem de
-- existir como LINHA APROVADA no catalogo, exatamente como existiria em
-- producao. O texto e inequivocamente ficticio e nenhuma linha de producao e
-- promovida por este helper.
-- ---------------------------------------------------------------------------
create or replace function tests.aprovar_atividade_qa(
  p_niche_code      text,
  p_catalog_version text default 'SF-v1.4'
) returns uuid
language plpgsql
security definer
set search_path to public, extensions, pg_catalog
as $$
declare
  v_id    uuid;
  v_texto text;
begin
  v_texto := '[QA FICTICIO] Atividade contratada de teste para o nicho '
          || p_niche_code || '. Nao e redacao juridica, nao foi aprovada por '
          || 'ninguem e nao tem valor contratual algum.';

  insert into public.commercial_contract_activity_catalog
    (catalog_version, niche_code, activity_code, activity_description,
     legal_template_version, status, source_reference, source_hash, approved_at,
     notes)
  values
    (p_catalog_version, p_niche_code, 'QA-' || upper(p_niche_code), v_texto,
     '0.0-qa', 'approved', 'fixture://qa/atividade/' || p_niche_code,
     encode(extensions.digest(v_texto, 'sha256'), 'hex'), now(),
     'Fixture de QA. A redacao legal real de producao continua pendente e '
     'nenhuma linha de producao foi aprovada.')
  on conflict (catalog_version, niche_code, activity_code) do update
     set status = 'approved', approved_at = now()
  returning id into v_id;

  return v_id;
end;
$$;

-- Arquiva as atividades de QA, para que a suite nao vaze aprovacao para as
-- seguintes — o mesmo cuidado do modelo de instrumento assinavel.
create or replace function tests.arquivar_atividades_qa()
returns integer
language plpgsql
security definer
set search_path to public, pg_catalog
as $$
declare v_n integer;
begin
  update public.commercial_contract_activity_catalog
     set status = 'archived', approved_at = null
   where activity_code like 'QA-%' and status = 'approved';
  get diagnostics v_n = row_count;
  return v_n;
end;
$$;

-- ---------------------------------------------------------------------------
-- Contexto contratual FICTICIO completo para suites que testam outros dominios
-- mas precisam criar pedidos sob a autoridade v1.4.
--
-- Nunca promove a minuta real. Cria modelos QA distintos para fundador e
-- fidelizado e atividades QA para os seis nichos canonicos. Cada suite deve
-- chamar `encerrar_contexto_contratual_v14_qa()` ao final para nao contaminar a
-- seguinte. A suite 260 NAO usa este atalho: ela prova o fail-closed sem modelo.
-- ---------------------------------------------------------------------------
create or replace function tests.encerrar_contexto_contratual_v14_qa()
returns void
language plpgsql
security definer
set search_path to public, pg_catalog
as $$
begin
  update public.commercial_instrument_templates
     set lifecycle_status = 'archived'
   where template_code like '[QA FICTICIO]%'
     and lifecycle_status = 'signable';
  perform tests.arquivar_atividades_qa();
end;
$$;

create or replace function tests.preparar_contexto_contratual_v14_qa(
  p_sufixo text
) returns jsonb
language plpgsql
security definer
set search_path to public, pg_catalog
as $$
declare
  v_nf  uuid;
  v_fid uuid;
  v_n   record;
begin
  perform tests.encerrar_contexto_contratual_v14_qa();

  v_nf  := tests.criar_modelo_instrumento_qa(false, p_sufixo);
  v_fid := tests.criar_modelo_instrumento_qa(true,  p_sufixo);

  for v_n in
    select code from public.commercial_niches where is_active order by code
  loop
    perform tests.aprovar_atividade_qa(v_n.code, 'SF-v1.4');
  end loop;

  return pg_catalog.jsonb_build_object(
    'ok', true,
    'founding_template_id', v_nf,
    'fidelized_template_id', v_fid);
end;
$$;

-- ---------------------------------------------------------------------------
-- R3: portão do autoatendimento. A migration R3 trava no banco a reserva sob
-- versão abaixo da mínima (4). Suítes que exercitam a reserva da SF-v1.4
-- abrem o portão para a versão 3 só durante a própria execução e o fecham ao
-- final — exatamente o que nenhum caminho de produção faz.
-- ---------------------------------------------------------------------------
create or replace function tests.abrir_portao_autoatendimento_qa(p_min integer default 3)
returns void
language sql
security definer
set search_path to public, pg_catalog
as $$
  update public.commercial_checkout_gate
     set min_pricing_rule_version = p_min,
         reason = '[QA FICTICIO] portao aberto para a suite de teste';
$$;

create or replace function tests.fechar_portao_autoatendimento_qa()
returns void
language sql
security definer
set search_path to public, pg_catalog
as $$
  update public.commercial_checkout_gate
     set min_pricing_rule_version = 4,
         reason = 'R3 2026-11-13: autoatendimento so com a SF-v1.5 ativada pelo procedimento autorizado';
$$;

-- ---------------------------------------------------------------------------
-- R3: pré-requisitos FICTÍCIOS da ativação da SF-v1.5, só dentro da transação
-- de teste: minutas QA com o modelo de liquidação R3, atividades QA no
-- catálogo SF-v1.5 para as posições ativas e preço FICTÍCIO da modalidade
-- dinheiro no cenário pedido ('A' sem a QA; 'B' preço mantido com componente
-- fundamentado). Nada disso é decisão: é fixture.
-- ---------------------------------------------------------------------------
-- R4: aprovação jurídica FICTÍCIA de uma minuta QA (conteúdo = source_hash
-- da própria minuta). Nunca usada para minuta real.
create or replace function tests.aprovar_minuta_r3_qa(
  p_template_id uuid,
  p_modes       text[] default array['direct_benefits', 'cash'],
  p_econ        text   default 'SF-v1.5'
) returns uuid
language plpgsql
security definer
set search_path to public, pg_catalog
as $$
declare v_id uuid;
begin
  insert into public.commercial_instrument_template_approvals
    (template_id, content_sha256, contract_economics_version, settlement_model,
     settlement_modes, applies_to_fidelized, legal_approval_reference,
     approved_by_name, approved_at)
  select t.id, t.source_hash, p_econ, t.settlement_model, p_modes, t.applies_to_fidelized,
         '[QA FICTICIO] aprovacao de teste, sem valor juridico', '[QA FICTICIO] Revisor', now()
    from public.commercial_instrument_templates t
   where t.id = p_template_id and t.template_code like '[QA FICTICIO]%'
  returning id into v_id;
  if v_id is null then
    raise exception 'aprovar_minuta_r3_qa: so minutas [QA FICTICIO]';
  end if;
  return v_id;
end;
$$;

-- ---------------------------------------------------------------------------
-- R4.1: fixtures de aprovação de lançamento e de procedimento operacional de
-- QA. SEMPRE marcadas [QA FICTICIO], só para transações de teste revertidas;
-- recusam referência sem a marca. Não são aprovações reais.
-- ---------------------------------------------------------------------------
create or replace function tests.registrar_procedimento_qa_ficticio(
  p_econ   text default 'SF-v1.5',
  p_sufixo text default 'QA'
) returns uuid
language plpgsql
security definer
set search_path to public, pg_catalog
as $$
declare v_id uuid;
begin
  insert into public.commercial_qa_operational_procedures
    (contract_economics_version, procedure_reference, procedure_document_sha256,
     covers_authorization, covers_product_receipt, covers_test_execution,
     covers_evidence_validation, covers_noncompliance, approver_as_stated, approved_on_as_stated)
  values (p_econ, '[QA FICTICIO] procedimento de QA ' || p_sufixo || ' ' || p_econ,
          encode(sha256(convert_to('[QA FICTICIO] procedimento ' || p_sufixo || p_econ, 'UTF8')), 'hex'),
          true, true, true, true, true, '[QA FICTICIO] Aprovador', current_date)
  returning id into v_id;
  return v_id;
end;
$$;

create or replace function tests.registrar_aprovacao_ativacao_qa(
  p_version   integer,
  p_reference text
) returns uuid
language plpgsql
security definer
set search_path to public, pg_catalog
as $$
declare v_id uuid;
begin
  if p_reference not like '[QA FICTICIO]%' then
    raise exception 'registrar_aprovacao_ativacao_qa: so referencias [QA FICTICIO]';
  end if;
  select id into v_id from public.commercial_pricing_activation_approvals
   where approval_reference = p_reference and pricing_rule_version = p_version;
  if v_id is null then
    insert into public.commercial_pricing_activation_approvals
      (pricing_rule_version, approval_reference, approval_document_sha256,
       approver_as_stated, approved_on_as_stated)
    values (p_version, p_reference, encode(sha256(convert_to(p_reference, 'UTF8')), 'hex'),
            '[QA FICTICIO] Aprovador do lancamento', current_date)
    returning id into v_id;
  end if;
  return v_id;
end;
$$;

-- Registra a aprovação FICTÍCIA e chama o procedimento real. A pilha passa por
-- public.admin_activate_pricing_rule(integer,text), como na operação.
create or replace function tests.ativar_sf_v15_qa(
  p_version   integer,
  p_reference text
) returns jsonb
language plpgsql
set search_path to public, pg_catalog
as $$
begin
  if length(btrim(coalesce(p_reference, ''))) >= 10 then
    perform tests.registrar_aprovacao_ativacao_qa(p_version, p_reference);
  end if;
  return public.admin_activate_pricing_rule(p_version, p_reference);
end;
$$;

create or replace function tests.preparar_ativacao_sf_v15_qa(
  p_sufixo  text,
  p_cenario text default 'A'
) returns jsonb
language plpgsql
security definer
set search_path to public, pg_catalog
as $$
declare
  v_nf  uuid;
  v_fid uuid;
  v_n   record;
begin
  if p_cenario not in ('A', 'B') then
    raise exception 'cenario de teste invalido: %', p_cenario;
  end if;
  perform tests.encerrar_contexto_contratual_v14_qa();
  -- A ativação exige nenhuma reserva viva (pré-verificação). Suítes
  -- anteriores que falham no meio (falhas pré-existentes da base) deixam
  -- reservas vivas no banco compartilhado: encerradas aqui, na transação de
  -- teste, que é revertida.
  update public.commercial_checkout_intents set status = 'cancelled'
   where status in ('draft', 'awaiting_contract')
     and reserved_until is not null and reserved_until > now();
  v_nf  := tests.criar_modelo_instrumento_qa(false, p_sufixo || '-R3');
  v_fid := tests.criar_modelo_instrumento_qa(true,  p_sufixo || '-R3');
  update public.commercial_instrument_templates
     set settlement_model = 'in_kind_direct_benefits_only'
   where id in (v_nf, v_fid);
  -- R4: aprovação jurídica FICTÍCIA do conteúdo de cada minuta QA, para a
  -- SF-v1.5 e as duas modalidades.
  perform tests.aprovar_minuta_r3_qa(v_nf);
  perform tests.aprovar_minuta_r3_qa(v_fid);
  for v_n in select code from public.commercial_niches where is_active order by code loop
    perform tests.aprovar_atividade_qa(v_n.code, 'SF-v1.5');
  end loop;

  insert into public.commercial_settlement_terms
    (pricing_rule_version, contract_economics_version, commercial_category, fidelized,
     benefit_settlement_mode, economic_value_cents, mei_consideration_cents,
     mei_in_kind_cents, mei_cash_cents, smallflags_main_fee_cents, qa_in_kind_cents,
     qa_cash_cents, cash_adjustment_cents, cash_adjustment_basis,
     total_monetary_funding_required_cents, ordinary_participation_value_cents,
     decision_reference, notes)
  select s.pricing_rule_version, s.contract_economics_version, s.commercial_category, s.fidelized,
         'cash',
         case when p_cenario = 'A' then s.mei_consideration_cents + s.smallflags_main_fee_cents
              else s.economic_value_cents end,
         s.mei_consideration_cents, 0, s.mei_consideration_cents, s.smallflags_main_fee_cents, 0,
         0,
         case when p_cenario = 'A' then 0
              else s.economic_value_cents - s.mei_consideration_cents - s.smallflags_main_fee_cents end,
         case when p_cenario = 'A' then null
              else '[QA FICTICIO] componente de teste, sem decisao comercial' end,
         case when p_cenario = 'A' then s.mei_consideration_cents + s.smallflags_main_fee_cents
              else s.economic_value_cents end,
         s.ordinary_participation_value_cents,
         '[QA FICTICIO] cenario ' || p_cenario || ', somente teste',
         'Fixture de QA: NAO e preco aprovado da modalidade dinheiro.'
    from public.commercial_pricing_schedule s
   where s.pricing_rule_version = 4;

  -- R4.1: procedimento operacional de QA FICTÍCIO (fixture, transação
  -- revertida). Sem ele a SF-v1.5 não ativa.
  perform tests.registrar_procedimento_qa_ficticio('SF-v1.5', p_sufixo);
  -- R4.1: aprovação de lançamento FICTÍCIA registrada antes do ato (a
  -- pré-verificação exige uma; a ativação exige a da referência usada).
  perform tests.registrar_aprovacao_ativacao_qa(4, '[QA FICTICIO] aprovacao de lancamento ' || p_sufixo);

  return pg_catalog.jsonb_build_object('ok', true, 'founding_template_id', v_nf,
    'fidelized_template_id', v_fid, 'cenario', p_cenario);
end;
$$;

-- ---------------------------------------------------------------------------
-- R4.3: preparação da ativação SOMENTE DINHEIRO (Cenário A) — FIXTURE.
-- Minutas e aprovação jurídica [QA FICTICIO] cobrindo SÓ o DINHEIRO,
-- atividades fictícias, preço de DINHEIRO do Cenário A, habilitação {cash} e
-- aprovação de lançamento fictícia. NÃO registra procedimento de QA.
-- Só para transações de teste revertidas.
-- ---------------------------------------------------------------------------
create or replace function tests.preparar_ativacao_sf_v15_somente_dinheiro_qa(p_sufixo text)
returns jsonb
language plpgsql
security definer
set search_path to public, pg_catalog
as $$
declare
  v_nf  uuid;
  v_fid uuid;
  v_n   record;
begin
  perform tests.encerrar_contexto_contratual_v14_qa();
  update public.commercial_checkout_intents set status = 'cancelled'
   where status in ('draft', 'awaiting_contract')
     and reserved_until is not null and reserved_until > now();
  v_nf  := tests.criar_modelo_instrumento_qa(false, p_sufixo || '-R43');
  v_fid := tests.criar_modelo_instrumento_qa(true,  p_sufixo || '-R43');
  update public.commercial_instrument_templates
     set settlement_model = 'in_kind_direct_benefits_only'
   where id in (v_nf, v_fid);
  perform tests.aprovar_minuta_r3_qa(v_nf, array['cash']);
  perform tests.aprovar_minuta_r3_qa(v_fid, array['cash']);
  for v_n in select code from public.commercial_niches where is_active order by code loop
    perform tests.aprovar_atividade_qa(v_n.code, 'SF-v1.5');
  end loop;
  -- Preço do DINHEIRO = fórmula do Cenário A (o roteiro real de ops confere
  -- os quatro valores; aqui a mesma fórmula, marcada fixture).
  insert into public.commercial_settlement_terms
    (pricing_rule_version, contract_economics_version, commercial_category, fidelized,
     benefit_settlement_mode, economic_value_cents, mei_consideration_cents,
     mei_in_kind_cents, mei_cash_cents, smallflags_main_fee_cents, qa_in_kind_cents,
     qa_cash_cents, cash_adjustment_cents, cash_adjustment_basis,
     total_monetary_funding_required_cents, ordinary_participation_value_cents,
     decision_reference, notes)
  select s.pricing_rule_version, s.contract_economics_version, s.commercial_category, s.fidelized,
         'cash', s.mei_consideration_cents + s.smallflags_main_fee_cents, s.mei_consideration_cents,
         0, s.mei_consideration_cents, s.smallflags_main_fee_cents, 0, 0, 0, null,
         s.mei_consideration_cents + s.smallflags_main_fee_cents, s.ordinary_participation_value_cents,
         '[QA FICTICIO] cenario A, somente teste', 'Fixture de QA: NAO e preco aprovado.'
    from public.commercial_pricing_schedule s
   where s.pricing_rule_version = 4;
  update public.commercial_pricing_rules set enabled_settlement_modes = array['cash']
   where version = 4 and status = 'prepared';
  perform tests.registrar_aprovacao_ativacao_qa(4, '[QA FICTICIO] aprovacao de lancamento ' || p_sufixo);
  return pg_catalog.jsonb_build_object('ok', true, 'founding_template_id', v_nf, 'fidelized_template_id', v_fid);
end;
$$;
