-- =====================================================================
-- MIGRAÇÃO — EMPRESA PARCEIRA + RESPONSÁVEL (owner) · Supabase do SITE
-- Rodar no SQL Editor do projeto do SITE (SiteDBFLOW).
--
-- ADITIVA E SEGURA: não renomeia, não exclui, não altera dados
-- existentes. site_monthly_partners é REAPROVEITADA como o registro
-- da empresa parceira. Nada do Supabase do APP é tocado.
--
-- Estrutura original encontrada em site_monthly_partners (schema v2):
--   id, app_partner_id (nullable), trade_name, legal_name, cnpj,
--   category, city, state, logo_url, website_url, contact_name,
--   contact_email, contact_phone, status (default 'lead'),
--   created_at, updated_at
-- → razão social (legal_name), nome fantasia (trade_name), CNPJ e
--   telefone (contact_phone) JÁ EXISTEM; faltam owner e novos status.
-- =====================================================================

-- ============ 1. CAMPOS NOVOS EM site_monthly_partners ============

alter table public.site_monthly_partners
  add column if not exists owner_user_id uuid null references auth.users(id);

comment on column public.site_monthly_partners.owner_user_id is
  'Usuário responsável principal (partner_owner). Definido apenas pela função de cadastro ou pela administração — nunca livremente pelo navegador.';

comment on column public.site_monthly_partners.app_partner_id is
  'Ponte futura com o APP (nullable). Preenchida SOMENTE por integração segura de servidor/administração — o navegador não escolhe nem altera este valor.';

-- Status: novos valores pending/active/suspended/archived.
-- O valor legado ''lead'' é preservado; a constraint entra como
-- NOT VALID para NÃO verificar (nem quebrar) registros antigos.
do $$ begin
  alter table public.site_monthly_partners
    add constraint site_partners_status_check
    check (status in ('lead', 'pending', 'active', 'suspended', 'archived'))
    not valid;
exception when duplicate_object then null; end $$;

create index if not exists idx_site_partners_owner
  on public.site_monthly_partners(owner_user_id);
create index if not exists idx_site_partners_cnpj
  on public.site_monthly_partners(cnpj);

-- ============ 2. NOVA TABELA site_partner_members ============

create table if not exists public.site_partner_members (
  id uuid primary key default gen_random_uuid(),
  partner_id uuid not null references public.site_monthly_partners(id) on delete restrict,
  user_id uuid not null references auth.users(id) on delete restrict,
  role text not null check (role in ('partner_owner', 'partner_manager')),
  status text not null default 'active'
    check (status in ('active', 'pending_admin_review', 'suspended', 'archived')),
  full_name text not null,
  cpf text not null,              -- normalizado (somente dígitos); não reexibir completo nas páginas comuns
  phone text,
  identity_fingerprint text null, -- ⚠️ preparado para cálculo futuro por backend seguro (NÃO implementado neste passo; sem hash simples)
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  suspended_at timestamptz null,
  unique (user_id, partner_id)
);

comment on column public.site_partner_members.identity_fingerprint is
  'Reservado para um identity_fingerprint calculado por backend seguro em etapa futura. Não preencher pelo navegador.';

create index if not exists idx_members_user on public.site_partner_members(user_id);
create index if not exists idx_members_partner on public.site_partner_members(partner_id);

-- Apenas UM owner não-arquivado por empresa
create unique index if not exists uq_one_owner_per_partner
  on public.site_partner_members(partner_id)
  where role = 'partner_owner' and status <> 'archived';

-- ============ 3. PROTEÇÕES (imutabilidade e não-exclusão) ============

-- updated_at automático
create or replace function public.tocar_updated_at()
returns trigger language plpgsql as $$
begin
  new.updated_at := now();
  return new;
end $$;

drop trigger if exists trg_members_updated on public.site_partner_members;
create trigger trg_members_updated
  before update on public.site_partner_members
  for each row execute function public.tocar_updated_at();

-- Membros: papel/vínculos são imutáveis fora da administração.
-- O owner NÃO altera o próprio papel nem transfere a propriedade pelo
-- portal — somente a administração BDFlow (is_site_admin) poderá.
create or replace function public.proteger_membro()
returns trigger language plpgsql security definer as $$
begin
  if not public.is_site_admin() then
    if new.role is distinct from old.role
       or new.user_id is distinct from old.user_id
       or new.partner_id is distinct from old.partner_id
       or new.cpf is distinct from old.cpf
       or new.identity_fingerprint is distinct from old.identity_fingerprint then
      raise exception 'ALTERACAO_RESTRITA_A_ADMINISTRACAO';
    end if;
  end if;
  return new;
end $$;

drop trigger if exists trg_proteger_membro on public.site_partner_members;
create trigger trg_proteger_membro
  before update on public.site_partner_members
  for each row execute function public.proteger_membro();

-- Registros de membros NUNCA são apagados (use suspended/archived)
create or replace function public.bloquear_delete_membro()
returns trigger language plpgsql as $$
begin
  raise exception 'MEMBROS_NAO_SAO_APAGADOS_USE_STATUS';
end $$;

drop trigger if exists trg_bloquear_delete_membro on public.site_partner_members;
create trigger trg_bloquear_delete_membro
  before delete on public.site_partner_members
  for each row execute function public.bloquear_delete_membro();

-- Empresa: campos sensíveis imutáveis fora da administração
-- (app_partner_id e owner_user_id jamais mudam pelo navegador)
create or replace function public.proteger_parceiro()
returns trigger language plpgsql security definer as $$
begin
  if not public.is_site_admin() then
    if new.app_partner_id is distinct from old.app_partner_id
       or new.owner_user_id is distinct from old.owner_user_id then
      raise exception 'ALTERACAO_RESTRITA_A_ADMINISTRACAO';
    end if;
  end if;
  return new;
end $$;

drop trigger if exists trg_proteger_parceiro on public.site_monthly_partners;
create trigger trg_proteger_parceiro
  before update on public.site_monthly_partners
  for each row execute function public.proteger_parceiro();

-- ============ 4. FUNÇÃO DE CADASTRO (transacional e idempotente) ====

-- Registra a empresa + primeiro owner numa única transação.
-- - Usa auth.uid() internamente: o navegador NUNCA envia user_id.
-- - Idempotente: se o usuário já é owner ativo, retorna o vínculo
--   existente em vez de duplicar.
-- - Se qualquer etapa falhar, TUDO reverte (função = 1 transação):
--   nunca fica empresa sem owner.
create or replace function public.create_my_partner_owner_registration(
  p_full_name text,
  p_cpf text,
  p_phone text,
  p_legal_name text,
  p_trade_name text,
  p_cnpj text,
  p_company_phone text default null
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_uid uuid := auth.uid();
  v_email text;
  v_cpf text := public.somente_digitos(p_cpf);
  v_cnpj text := public.somente_digitos(p_cnpj);
  v_partner_id uuid;
  v_member_id uuid;
  v_existente record;
begin
  -- exige usuário autenticado (Supabase do SITE)
  if v_uid is null then
    raise exception 'AUTENTICACAO_OBRIGATORIA';
  end if;

  -- validação dos obrigatórios
  if coalesce(trim(p_full_name), '') = '' then raise exception 'NOME_OBRIGATORIO'; end if;
  if coalesce(trim(p_legal_name), '') = '' then raise exception 'RAZAO_SOCIAL_OBRIGATORIA'; end if;
  if coalesce(trim(p_trade_name), '') = '' then raise exception 'NOME_FANTASIA_OBRIGATORIO'; end if;
  if length(v_cpf) <> 11 then raise exception 'CPF_INVALIDO'; end if;
  if length(v_cnpj) <> 14 then raise exception 'CNPJ_INVALIDO'; end if;

  -- IDEMPOTÊNCIA: usuário já é owner não-arquivado? Retorna o existente.
  select m.id as member_id, m.partner_id, m.role, m.status as member_status,
         p.status as partner_status
    into v_existente
    from public.site_partner_members m
    join public.site_monthly_partners p on p.id = m.partner_id
   where m.user_id = v_uid
     and m.role = 'partner_owner'
     and m.status <> 'archived'
   limit 1;

  if found then
    return jsonb_build_object(
      'partner_id', v_existente.partner_id,
      'member_id', v_existente.member_id,
      'role', v_existente.role,
      'partner_status', v_existente.partner_status,
      'member_status', v_existente.member_status
    );
  end if;

  -- CNPJ já cadastrado por outra empresa não-arquivada?
  if exists (
    select 1 from public.site_monthly_partners
     where public.somente_digitos(cnpj) = v_cnpj
       and status <> 'archived'
  ) then
    raise exception 'CNPJ_JA_CADASTRADO';
  end if;

  select email into v_email from auth.users where id = v_uid;

  -- cria a EMPRESA (status inicial: pending)
  insert into public.site_monthly_partners
    (trade_name, legal_name, cnpj, contact_name, contact_email,
     contact_phone, owner_user_id, status)
  values
    (trim(p_trade_name), trim(p_legal_name), v_cnpj, trim(p_full_name),
     v_email, coalesce(p_company_phone, p_phone), v_uid, 'pending')
  returning id into v_partner_id;

  -- cria o OWNER (status: active)
  insert into public.site_partner_members
    (partner_id, user_id, role, status, full_name, cpf, phone)
  values
    (v_partner_id, v_uid, 'partner_owner', 'active',
     trim(p_full_name), v_cpf, p_phone)
  returning id into v_member_id;

  -- atualiza site_profiles apenas de forma compatível com a estrutura
  -- existente (auth_user_id não é único na tabela — sem upsert cego)
  if exists (select 1 from public.site_profiles where auth_user_id = v_uid) then
    update public.site_profiles
       set name = coalesce(name, trim(p_full_name)),
           phone = coalesce(phone, p_phone),
           customer_type = coalesce(customer_type, 'partner_company'),
           updated_at = now()
     where auth_user_id = v_uid;
  else
    insert into public.site_profiles
      (auth_user_id, customer_type, name, cnpj, email, phone)
    values
      (v_uid, 'partner_company', trim(p_full_name), v_cnpj, v_email, p_phone);
  end if;

  return jsonb_build_object(
    'partner_id', v_partner_id,
    'member_id', v_member_id,
    'role', 'partner_owner',
    'partner_status', 'pending',
    'member_status', 'active'
  );
end $$;

-- somente usuários autenticados executam; navegantes anônimos não
revoke all on function public.create_my_partner_owner_registration(text, text, text, text, text, text, text) from public;
grant execute on function public.create_my_partner_owner_registration(text, text, text, text, text, text, text) to authenticated;

-- ============ 5. RLS ============

alter table public.site_partner_members enable row level security;
-- (site_monthly_partners já tem RLS habilitado no schema v2)

-- Membro consulta a PRÓPRIA associação
do $$ begin
  create policy "members_select_own" on public.site_partner_members
    for select using (user_id = auth.uid() or public.is_site_admin());
exception when duplicate_object then null; end $$;

-- Administração gerencia pelo modelo seguro existente (is_site_admin)
do $$ begin
  create policy "members_admin_all" on public.site_partner_members
    for all using (public.is_site_admin()) with check (public.is_site_admin());
exception when duplicate_object then null; end $$;

-- Membro consulta SOMENTE a empresa à qual está vinculado
-- (soma-se à policy admin já existente "partners_admin")
do $$ begin
  create policy "partners_select_member" on public.site_monthly_partners
    for select using (
      public.is_site_admin() or exists (
        select 1 from public.site_partner_members m
        where m.partner_id = site_monthly_partners.id
          and m.user_id = auth.uid()
          and m.status <> 'archived'
      )
    );
exception when duplicate_object then null; end $$;

-- IMPORTANTE: nenhuma policy de INSERT para 'authenticated' nas duas
-- tabelas → INSERT direto pelo navegador é NEGADO pelo RLS. A criação
-- acontece exclusivamente pela função security definer acima.
