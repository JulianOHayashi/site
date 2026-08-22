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

create or replace function tests.reset_results() returns void
    language sql security definer set search_path to 'pg_catalog'
    as $$ truncate table tests.results restart identity; $$;

create or replace function tests.check(p_name text, p_cond boolean)
    returns text
    language plpgsql security definer set search_path to 'pg_catalog'
    as $$
begin
  insert into tests.results (name, passed)
  values (p_name, coalesce(p_cond, false));
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
  select count(*) filter (where passed),
         count(*) filter (where not passed)
    into v_pass, v_fail
    from tests.results;
  if v_fail > 0 then
    select string_agg(name, E'\n  ') into v_failed
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

grant execute on function
    tests.reset_results(),
    tests.check(text, boolean),
    tests.check_raises(text, text, text),
    tests.finish(text),
    tests.impersonate(text, uuid),
    tests.mk_user(text)
  to anon, authenticated, service_role;
