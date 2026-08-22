-- ============================================================================
-- Shim de compatibilidade Supabase para o harness local nativo (PostgreSQL 16)
--
-- STATUS: TESTE_AUXILIAR_NAO_GATE.
-- Este shim NÃO substitui o gate final, que exige Supabase local PostgreSQL 17
-- real. Ele existe para exercitar rapidamente RLS, ACL, concorrência e
-- invariantes de negócio durante o desenvolvimento.
--
-- Contexto: neste ambiente a política de rede bloqueia o download das imagens
-- Docker do Supabase, então `supabase db reset --local` oficial não roda.
-- Este shim recria, num cluster PostgreSQL nativo, o mínimo que a baseline
-- pressupõe de um projeto Supabase:
--   roles anon / authenticated / service_role
--   schemas auth / extensions / vault / graphql_public
--   auth.users (subconjunto usado pela baseline)
--   auth.uid() / auth.role() / auth.jwt() (semântica oficial via GUC)
--
-- É infraestrutura de TESTE. Nunca aplicar em banco remoto.
-- ============================================================================

do $$
begin
  if not exists (select 1 from pg_roles where rolname = 'anon') then
    create role anon nologin noinherit;
  end if;
  if not exists (select 1 from pg_roles where rolname = 'authenticated') then
    create role authenticated nologin noinherit;
  end if;
  if not exists (select 1 from pg_roles where rolname = 'service_role') then
    -- No Supabase real service_role possui BYPASSRLS.
    create role service_role nologin noinherit bypassrls;
  end if;
end $$;

create schema if not exists auth;
create schema if not exists extensions;
create schema if not exists vault;          -- vazio: supabase_vault indisponível
create schema if not exists graphql_public;

grant usage on schema auth to anon, authenticated, service_role;
grant usage on schema extensions to anon, authenticated, service_role;

-- Subconjunto de auth.users referenciado pela baseline (select email ...).
create table if not exists auth.users (
    id uuid primary key,
    email text,
    raw_user_meta_data jsonb not null default '{}'::jsonb,
    created_at timestamptz not null default now()
);

-- Implementação oficial (gotrue) de auth.uid()/role()/jwt() sobre GUCs.
create or replace function auth.uid() returns uuid
    language sql stable
    as $$
  select coalesce(
      nullif(current_setting('request.jwt.claim.sub', true), ''),
      (nullif(current_setting('request.jwt.claims', true), '')::jsonb ->> 'sub')
  )::uuid
$$;

create or replace function auth.role() returns text
    language sql stable
    as $$
  select coalesce(
      nullif(current_setting('request.jwt.claim.role', true), ''),
      (nullif(current_setting('request.jwt.claims', true), '')::jsonb ->> 'role')
  )
$$;

create or replace function auth.jwt() returns jsonb
    language sql stable
    as $$
  select coalesce(
      nullif(current_setting('request.jwt.claims', true), '')::jsonb,
      '{}'::jsonb
  )
$$;

grant execute on function auth.uid(), auth.role(), auth.jwt()
    to anon, authenticated, service_role;
grant select on auth.users to service_role;

-- ---------------------------------------------------------------------------
-- Storage: subconjunto usado pelo M1 canônico (bucket privado de documentos).
-- Colunas conforme o schema real do Supabase Storage na parte consumida pelas
-- policies do M1 (bucket_id, name, owner) e pelo insert de bucket
-- (id, name, public, file_size_limit, allowed_mime_types).
-- ---------------------------------------------------------------------------
create schema if not exists storage;
grant usage on schema storage to anon, authenticated, service_role;

create table if not exists storage.buckets (
    id text primary key,
    name text not null,
    owner uuid,
    public boolean not null default false,
    file_size_limit bigint,
    allowed_mime_types text[],
    created_at timestamptz not null default now(),
    updated_at timestamptz not null default now()
);

create table if not exists storage.objects (
    id uuid primary key default gen_random_uuid(),
    bucket_id text not null references storage.buckets (id),
    name text not null,
    owner uuid,
    metadata jsonb,
    created_at timestamptz not null default now(),
    updated_at timestamptz not null default now(),
    last_accessed_at timestamptz
);

create unique index if not exists storage_objects_bucket_name_idx
    on storage.objects (bucket_id, name);

-- No Supabase real o RLS de storage.objects já vem habilitado.
alter table storage.objects enable row level security;
grant select, insert, update, delete on storage.objects
    to authenticated, service_role;
grant select on storage.buckets to authenticated, service_role;

-- Publication padrão criada pelo Supabase (a baseline a referencia).
do $$
begin
  if not exists (select 1 from pg_publication where pubname = 'supabase_realtime') then
    create publication supabase_realtime;
  end if;
end $$;
