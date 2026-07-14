-- =====================================================================
-- WEBSITE SUPABASE — SCHEMA CANÔNICO v2 (BDFlow/Site separation spec)
-- Rodar no SQL Editor do projeto Supabase DO SITE (não no do app).
--
-- ESCOPO: comércio do site (produtos, personalização, pedidos,
-- pagamentos/notas placeholders, parceiros mensais/anúncios,
-- documentos, contato). NENHUMA tabela de QR/benefícios aqui —
-- essas pertencem ao projeto do APP e são acessadas só via RPCs.
--
-- Se os scripts ANTIGOS (schema.sql / precificacao.sql) já rodaram
-- neste projeto, descomente o bloco abaixo para removê-los antes
-- (não há dados de produção; ambiente ainda em demonstração):
-- drop table if exists public.orders cascade;
-- drop table if exists public.products cascade;
-- drop table if exists public.profiles cascade;
-- =====================================================================

-- ============ HELPERS ============

create or replace function public.somente_digitos(t text)
returns text language sql immutable as
$$ select regexp_replace(coalesce(t, ''), '\D', '', 'g') $$;

-- Admin do site: usuários listados aqui podem gerenciar tudo.
-- (Adicione seu auth user id via painel após criar sua conta.)
create table if not exists public.site_admins (
  user_id uuid primary key references auth.users(id) on delete cascade,
  created_at timestamptz default now()
);
alter table public.site_admins enable row level security;
-- sem policies = ninguém lê/edita pelo frontend; gerencie pelo painel.

create or replace function public.is_site_admin()
returns boolean language sql stable security definer as
$$ select exists (select 1 from public.site_admins where user_id = auth.uid()) $$;

-- ============ CONFIG DE PRECIFICAÇÃO (regras já decididas) ============

create table if not exists public.config (
  chave text primary key,
  valor numeric not null
);
insert into public.config (chave, valor) values
  ('desconto_fidelidade_pct', 10),   -- ⚠️ A DEFINIR
  ('quantidade_minima', 10)
on conflict (chave) do nothing;

create table if not exists public.faixas_quantidade (
  min_qtd integer primary key check (min_qtd > 0),
  desconto_pct numeric not null check (desconto_pct >= 0 and desconto_pct < 100)
);
insert into public.faixas_quantidade (min_qtd, desconto_pct) values
  (10, 0), (20, 5), (50, 10), (100, 15)   -- ⚠️ A DEFINIR
on conflict (min_qtd) do nothing;

alter table public.config enable row level security;
alter table public.faixas_quantidade enable row level security;
do $$ begin
  create policy "config_public_read" on public.config for select using (true);
exception when duplicate_object then null; end $$;
do $$ begin
  create policy "faixas_public_read" on public.faixas_quantidade for select using (true);
exception when duplicate_object then null; end $$;

-- ============ PART 1 — WEBSITE COMMERCE ============

-- 1. site_profiles
create table if not exists public.site_profiles (
  id uuid primary key default gen_random_uuid(),
  auth_user_id uuid null references auth.users(id) on delete set null,
  customer_type text null,
  name text,
  company_name text,
  cnpj text,
  email text,
  phone text,
  created_at timestamptz default now(),
  updated_at timestamptz default now()
);
create index if not exists idx_site_profiles_auth on public.site_profiles(auth_user_id);
create index if not exists idx_site_profiles_cnpj on public.site_profiles(cnpj);

-- 2. products (genérico — não só camisas)
create table if not exists public.products (
  id uuid primary key default gen_random_uuid(),
  slug text unique not null,
  name text not null,
  short_description text,
  full_description text,
  product_type text,
  category text,
  active boolean default true,
  base_price_cents integer,
  min_quantity integer default 10,
  stock_quantity integer,
  stock_enabled boolean default true,
  customizable boolean default true,
  display_order integer default 100,
  created_at timestamptz default now(),
  updated_at timestamptz default now()
);

-- 3. product_assets
create table if not exists public.product_assets (
  id uuid primary key default gen_random_uuid(),
  product_id uuid references public.products(id) on delete cascade,
  asset_type text not null,
  title text,
  url text not null,
  alt_text text,
  display_order integer default 100,
  active boolean default true,
  created_at timestamptz default now()
);

-- 4. product_customization_fields
create table if not exists public.product_customization_fields (
  id uuid primary key default gen_random_uuid(),
  product_id uuid references public.products(id) on delete cascade,
  field_key text not null,
  label text not null,
  field_type text not null, -- text | textarea | upload | select | color | number | checkbox
  required boolean default false,
  max_length integer,
  help_text text,
  options jsonb,
  display_order integer default 100,
  active boolean default true,
  created_at timestamptz default now(),
  unique (product_id, field_key)
);

-- 5. orders
create table if not exists public.orders (
  id uuid primary key default gen_random_uuid(),
  site_profile_id uuid null references public.site_profiles(id),
  status text not null default 'draft',
  -- draft | quote_request | pending_payment | paid | in_production | shipped | completed | cancelled
  customer_name text,
  customer_email text,
  customer_phone text,
  cnpj text,
  subtotal_cents integer default 0,
  volume_discount_cents integer default 0,
  loyalty_discount_cents integer default 0,
  total_cents integer default 0,
  payment_status text default 'not_started',
  invoice_status text default 'not_started',
  notes text,
  created_at timestamptz default now(),
  updated_at timestamptz default now()
);
create index if not exists idx_orders_profile on public.orders(site_profile_id);
create index if not exists idx_orders_cnpj on public.orders(cnpj);

-- 6. order_items
create table if not exists public.order_items (
  id uuid primary key default gen_random_uuid(),
  order_id uuid references public.orders(id) on delete cascade,
  product_id uuid references public.products(id),
  quantity integer not null,
  unit_price_cents integer,
  total_price_cents integer,
  customization jsonb,
  created_at timestamptz default now()
);
create index if not exists idx_order_items_order on public.order_items(order_id);

-- 7. order_customization_files
create table if not exists public.order_customization_files (
  id uuid primary key default gen_random_uuid(),
  order_id uuid references public.orders(id) on delete cascade,
  order_item_id uuid references public.order_items(id) on delete cascade,
  file_url text not null,
  file_type text,
  original_filename text,
  status text default 'uploaded',
  created_at timestamptz default now()
);

-- 8. payments (placeholder Mercado Pago — NÃO integrar ainda)
create table if not exists public.payments (
  id uuid primary key default gen_random_uuid(),
  order_id uuid references public.orders(id) on delete cascade,
  provider text default 'mercado_pago',
  provider_payment_id text,
  status text default 'not_started',
  amount_cents integer,
  paid_at timestamptz,
  raw_webhook jsonb,
  created_at timestamptz default now()
);

-- 9. invoices (placeholder Bling — NÃO integrar ainda)
create table if not exists public.invoices (
  id uuid primary key default gen_random_uuid(),
  order_id uuid references public.orders(id) on delete cascade,
  provider text default 'bling',
  provider_invoice_id text,
  status text default 'not_started',
  invoice_url text,
  issued_at timestamptz,
  raw_response jsonb,
  created_at timestamptz default now()
);

-- ============ PART 2 — MONTHLY SITE PARTNERS ============

-- 10. site_monthly_partners
create table if not exists public.site_monthly_partners (
  id uuid primary key default gen_random_uuid(),
  app_partner_id uuid null, -- ponte OPCIONAL p/ partners.id do APP (documental; nunca join direto no frontend)
  trade_name text not null,
  legal_name text,
  cnpj text,
  category text,
  city text,
  state text,
  logo_url text,
  website_url text,
  contact_name text,
  contact_email text,
  contact_phone text,
  status text default 'lead',
  created_at timestamptz default now(),
  updated_at timestamptz default now()
);

-- 11. site_partner_contracts
create table if not exists public.site_partner_contracts (
  id uuid primary key default gen_random_uuid(),
  site_partner_id uuid references public.site_monthly_partners(id) on delete cascade,
  plan_name text,
  monthly_amount_cents integer,
  starts_at date,
  ends_at date,
  billing_day integer,
  status text default 'pending', -- pending | active | overdue | cancelled | expired
  notes text,
  created_at timestamptz default now(),
  updated_at timestamptz default now()
);

-- 12. site_partner_ads
create table if not exists public.site_partner_ads (
  id uuid primary key default gen_random_uuid(),
  site_partner_id uuid references public.site_monthly_partners(id) on delete cascade,
  contract_id uuid references public.site_partner_contracts(id) on delete set null,
  placement text not null, -- home_hero | home_carousel | product_page | checkout_banner | footer_partner | state_map
  title text,
  description text,
  image_url text,
  target_url text,
  starts_at timestamptz,
  ends_at timestamptz,
  active boolean default true,
  created_at timestamptz default now()
);

-- ============ PART 3 — DOCUMENTS & CONTACT ============

-- 13. site_documents
create table if not exists public.site_documents (
  id uuid primary key default gen_random_uuid(),
  slug text unique not null, -- termos-de-uso | politica-de-privacidade | politica-de-troca | midia-kit | guia-de-arte | proposta-comercial
  title text not null,
  document_type text not null,
  content text,
  file_url text,
  active boolean default true,
  created_at timestamptz default now(),
  updated_at timestamptz default now()
);

-- 14. site_contact_messages
create table if not exists public.site_contact_messages (
  id uuid primary key default gen_random_uuid(),
  name text,
  email text,
  phone text,
  company text,
  message text,
  status text default 'new',
  created_at timestamptz default now()
);

-- ============ FUNÇÕES DE NEGÓCIO (portadas das regras decididas) ============

create or replace function public.desconto_quantidade(p_qtd integer)
returns numeric language sql stable as $$
  select coalesce((select desconto_pct from public.faixas_quantidade
                   where min_qtd <= p_qtd order by min_qtd desc limit 1), 0);
$$;
grant execute on function public.desconto_quantidade(integer) to anon, authenticated;

-- Fidelidade: CNPJ com pedido anterior efetivo (fora draft/cancelled)
create or replace function public.desconto_para_cnpj(p_cnpj text)
returns numeric language plpgsql security definer stable as $$
declare
  v_cnpj text := public.somente_digitos(p_cnpj);
  v_pct numeric := 0;
begin
  if length(v_cnpj) <> 14 then return 0; end if;
  if exists (
    select 1 from public.orders o
    where public.somente_digitos(o.cnpj) = v_cnpj
      and o.status not in ('draft', 'cancelled')
  ) then
    select valor into v_pct from public.config where chave = 'desconto_fidelidade_pct';
  end if;
  return coalesce(v_pct, 0);
end $$;
grant execute on function public.desconto_para_cnpj(text) to anon, authenticated;

-- Item de pedido: valida mínimo, precifica com volume e baixa estoque (atômico)
create or replace function public.aplicar_item_pedido()
returns trigger language plpgsql security definer as $$
declare
  v_min integer;
  v_base integer;
  v_stock_enabled boolean;
  v_vol numeric;
begin
  select coalesce(p.min_quantity, 10), p.base_price_cents, coalesce(p.stock_enabled, true)
    into v_min, v_base, v_stock_enabled
    from public.products p where p.id = new.product_id;

  if new.quantity < v_min then
    raise exception 'QUANTIDADE_MINIMA';
  end if;

  v_vol := public.desconto_quantidade(new.quantity);
  new.unit_price_cents := round(v_base * (1 - v_vol / 100.0));
  new.total_price_cents := new.unit_price_cents * new.quantity;

  if v_stock_enabled then
    update public.products
       set stock_quantity = stock_quantity - new.quantity
     where id = new.product_id and stock_quantity >= new.quantity;
    if not found then
      raise exception 'ESTOQUE_INSUFICIENTE';
    end if;
  end if;

  return new;
end $$;

drop trigger if exists trg_item_pedido on public.order_items;
create trigger trg_item_pedido before insert on public.order_items
for each row execute function public.aplicar_item_pedido();

-- Devolve estoque ao remover item
create or replace function public.devolver_estoque_item()
returns trigger language plpgsql security definer as $$
begin
  update public.products
     set stock_quantity = stock_quantity + old.quantity
   where id = old.product_id and coalesce(stock_enabled, true);
  return old;
end $$;

drop trigger if exists trg_devolver_item on public.order_items;
create trigger trg_devolver_item before delete on public.order_items
for each row execute function public.devolver_estoque_item();

-- Recalcula totais do pedido (subtotal, volume, fidelidade em cascata)
create or replace function public.recalcular_pedido(p_order uuid)
returns void language plpgsql security definer as $$
declare
  v_bruto integer := 0;
  v_com_volume integer := 0;
  v_fid numeric := 0;
  v_cnpj text;
begin
  select coalesce(sum(oi.quantity * p.base_price_cents), 0),
         coalesce(sum(oi.total_price_cents), 0)
    into v_bruto, v_com_volume
    from public.order_items oi
    join public.products p on p.id = oi.product_id
   where oi.order_id = p_order;

  select cnpj into v_cnpj from public.orders where id = p_order;
  v_fid := public.desconto_para_cnpj(v_cnpj);

  update public.orders set
    subtotal_cents = v_bruto,
    volume_discount_cents = v_bruto - v_com_volume,
    loyalty_discount_cents = round(v_com_volume * v_fid / 100.0),
    total_cents = v_com_volume - round(v_com_volume * v_fid / 100.0),
    updated_at = now()
  where id = p_order;
end $$;

create or replace function public.trg_recalcular_pedido()
returns trigger language plpgsql security definer as $$
begin
  perform public.recalcular_pedido(coalesce(new.order_id, old.order_id));
  return coalesce(new, old);
end $$;

drop trigger if exists trg_totais_pedido on public.order_items;
create trigger trg_totais_pedido after insert or update or delete on public.order_items
for each row execute function public.trg_recalcular_pedido();

-- ============ PART 7 — RLS ============

alter table public.site_profiles enable row level security;
alter table public.products enable row level security;
alter table public.product_assets enable row level security;
alter table public.product_customization_fields enable row level security;
alter table public.orders enable row level security;
alter table public.order_items enable row level security;
alter table public.order_customization_files enable row level security;
alter table public.payments enable row level security;
alter table public.invoices enable row level security;
alter table public.site_monthly_partners enable row level security;
alter table public.site_partner_contracts enable row level security;
alter table public.site_partner_ads enable row level security;
alter table public.site_documents enable row level security;
alter table public.site_contact_messages enable row level security;

-- leitura pública do que é ativo
do $$ begin
  create policy "products_public_read" on public.products
    for select using (active = true or public.is_site_admin());
exception when duplicate_object then null; end $$;
do $$ begin
  create policy "assets_public_read" on public.product_assets
    for select using (active = true or public.is_site_admin());
exception when duplicate_object then null; end $$;
do $$ begin
  create policy "custfields_public_read" on public.product_customization_fields
    for select using (active = true or public.is_site_admin());
exception when duplicate_object then null; end $$;
do $$ begin
  create policy "documents_public_read" on public.site_documents
    for select using (active = true or public.is_site_admin());
exception when duplicate_object then null; end $$;
do $$ begin
  create policy "ads_public_read" on public.site_partner_ads
    for select using (active = true or public.is_site_admin());
exception when duplicate_object then null; end $$;

-- contato: público insere; só admin lê/gerencia
do $$ begin
  create policy "contact_public_insert" on public.site_contact_messages
    for insert with check (true);
exception when duplicate_object then null; end $$;
do $$ begin
  create policy "contact_admin_all" on public.site_contact_messages
    for all using (public.is_site_admin()) with check (public.is_site_admin());
exception when duplicate_object then null; end $$;

-- perfil: dono gerencia o próprio; admin tudo
do $$ begin
  create policy "profile_self" on public.site_profiles
    for all using (auth.uid() = auth_user_id or public.is_site_admin())
    with check (auth.uid() = auth_user_id or public.is_site_admin());
exception when duplicate_object then null; end $$;

-- pedidos: cliente autenticado lê/cria os próprios; admin tudo
do $$ begin
  create policy "orders_owner_select" on public.orders
    for select using (
      public.is_site_admin() or exists (
        select 1 from public.site_profiles sp
        where sp.id = orders.site_profile_id and sp.auth_user_id = auth.uid()
      )
    );
exception when duplicate_object then null; end $$;
do $$ begin
  create policy "orders_owner_insert" on public.orders
    for insert with check (
      public.is_site_admin() or exists (
        select 1 from public.site_profiles sp
        where sp.id = orders.site_profile_id and sp.auth_user_id = auth.uid()
      )
    );
exception when duplicate_object then null; end $$;
do $$ begin
  create policy "orders_admin_update" on public.orders
    for update using (public.is_site_admin()) with check (public.is_site_admin());
exception when duplicate_object then null; end $$;

-- itens e arquivos: seguem a posse do pedido
do $$ begin
  create policy "items_owner" on public.order_items
    for all using (
      public.is_site_admin() or exists (
        select 1 from public.orders o
        join public.site_profiles sp on sp.id = o.site_profile_id
        where o.id = order_items.order_id and sp.auth_user_id = auth.uid()
      )
    ) with check (
      public.is_site_admin() or exists (
        select 1 from public.orders o
        join public.site_profiles sp on sp.id = o.site_profile_id
        where o.id = order_items.order_id and sp.auth_user_id = auth.uid()
      )
    );
exception when duplicate_object then null; end $$;
do $$ begin
  create policy "files_owner" on public.order_customization_files
    for all using (
      public.is_site_admin() or exists (
        select 1 from public.orders o
        join public.site_profiles sp on sp.id = o.site_profile_id
        where o.id = order_customization_files.order_id and sp.auth_user_id = auth.uid()
      )
    ) with check (
      public.is_site_admin() or exists (
        select 1 from public.orders o
        join public.site_profiles sp on sp.id = o.site_profile_id
        where o.id = order_customization_files.order_id and sp.auth_user_id = auth.uid()
      )
    );
exception when duplicate_object then null; end $$;

-- pagamentos / notas / parceiros / contratos: SÓ admin
do $$ begin
  create policy "payments_admin" on public.payments
    for all using (public.is_site_admin()) with check (public.is_site_admin());
exception when duplicate_object then null; end $$;
do $$ begin
  create policy "invoices_admin" on public.invoices
    for all using (public.is_site_admin()) with check (public.is_site_admin());
exception when duplicate_object then null; end $$;
do $$ begin
  create policy "partners_admin" on public.site_monthly_partners
    for all using (public.is_site_admin()) with check (public.is_site_admin());
exception when duplicate_object then null; end $$;
do $$ begin
  create policy "contracts_admin" on public.site_partner_contracts
    for all using (public.is_site_admin()) with check (public.is_site_admin());
exception when duplicate_object then null; end $$;

-- gestão admin do catálogo/documentos/anúncios (escrita)
do $$ begin
  create policy "products_admin_write" on public.products
    for all using (public.is_site_admin()) with check (public.is_site_admin());
exception when duplicate_object then null; end $$;
do $$ begin
  create policy "assets_admin_write" on public.product_assets
    for all using (public.is_site_admin()) with check (public.is_site_admin());
exception when duplicate_object then null; end $$;
do $$ begin
  create policy "custfields_admin_write" on public.product_customization_fields
    for all using (public.is_site_admin()) with check (public.is_site_admin());
exception when duplicate_object then null; end $$;
do $$ begin
  create policy "documents_admin_write" on public.site_documents
    for all using (public.is_site_admin()) with check (public.is_site_admin());
exception when duplicate_object then null; end $$;
do $$ begin
  create policy "ads_admin_write" on public.site_partner_ads
    for all using (public.is_site_admin()) with check (public.is_site_admin());
exception when duplicate_object then null; end $$;

-- ============ REALTIME (estoque ao vivo) ============
do $$ begin
  alter publication supabase_realtime add table public.products;
exception when duplicate_object then null; end $$;

-- ============ SEED (3 produtos de demonstração — ⚠️ A DEFINIR) ============
insert into public.products
  (slug, name, short_description, product_type, category, base_price_cents, min_quantity, stock_quantity, display_order)
values
  ('horizonte', 'Modelo Horizonte', 'Produto customizável com área de estampa 49×30cm. Base branca.', 'camisa', 'vestuario', 8990, 10, 100, 1),
  ('litoral',   'Modelo Litoral',   'Produto customizável com área de estampa 49×30cm. Base azul-clara.', 'camisa', 'vestuario', 9490, 10, 100, 2),
  ('serra',     'Modelo Serra',     'Produto customizável com área de estampa 49×30cm. Base escura.', 'camisa', 'vestuario', 9990, 10, 100, 3)
on conflict (slug) do nothing;

-- campos de customização por produto (inclui frase fixa e cor de preview)
insert into public.product_customization_fields
  (product_id, field_key, label, field_type, required, max_length, options, display_order)
select p.id, v.field_key, v.label, v.field_type, v.required, v.max_length, v.options::jsonb, v.display_order
from public.products p
cross join (values
  ('arte', 'Sua arte', 'upload', true, null, null, 1),
  ('frase_cliente', 'Sua frase', 'text', false, 20, null, 2),
  ('frase_fixa', 'Frase fixa do modelo', 'text', false, null, '{"fixed_value": "Feito no Espírito Santo", "readonly": true}', 3),
  ('cor_base', 'Cor de base do preview', 'color', false, null, null, 4)
) as v(field_key, label, field_type, required, max_length, options, display_order)
on conflict (product_id, field_key) do nothing;

-- cores de preview por produto
update public.product_customization_fields f set options = jsonb_build_object('fixed_value',
  case (select slug from public.products where id = f.product_id)
    when 'horizonte' then '#FFFFFF'
    when 'litoral' then '#EAF6FB'
    when 'serra' then '#17121F'
  end, 'readonly', true)
where f.field_key = 'cor_base';

-- documentos placeholder
insert into public.site_documents (slug, title, document_type, content) values
  ('termos-de-uso', 'Termos de Uso', 'legal', '⚠️ A DEFINIR'),
  ('politica-de-privacidade', 'Política de Privacidade', 'legal', '⚠️ A DEFINIR'),
  ('politica-de-troca', 'Política de Troca', 'legal', '⚠️ A DEFINIR'),
  ('midia-kit', 'Mídia Kit', 'commercial', '⚠️ A DEFINIR'),
  ('guia-de-arte', 'Guia de Arte', 'commercial', '⚠️ A DEFINIR')
on conflict (slug) do nothing;
