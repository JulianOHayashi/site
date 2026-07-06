-- =========================================================
-- SCHEMA COMPLETO — rodar no SQL Editor do Supabase
-- Camisas Customizadas · Lado Empresarial
-- =========================================================

-- 1. PRODUTOS (com estoque)
create table if not exists public.products (
  id uuid primary key default gen_random_uuid(),
  slug text unique not null,
  nome text not null,
  descricao text,
  preco numeric(10,2) not null,       -- ⚠️ provisório, A DEFINIR
  frase_fixa text not null,           -- ⚠️ A DEFINIR pelo dono
  cor_base text not null default '#FFFFFF',
  estoque integer not null default 0 check (estoque >= 0),
  ativo boolean not null default true,
  criado_em timestamptz not null default now()
);

insert into public.products (slug, nome, descricao, preco, frase_fixa, cor_base, estoque) values
  ('horizonte', 'Modelo Horizonte', 'Camisa em tamanho único com área de estampa horizontal de 49×30cm. Base branca.', 89.90, 'Feito no Espírito Santo', '#FFFFFF', 100),
  ('litoral',   'Modelo Litoral',   'Camisa em tamanho único com área de estampa horizontal de 49×30cm. Base azul-clara.', 94.90, 'Feito no Espírito Santo', '#EAF6FB', 100),
  ('serra',     'Modelo Serra',     'Camisa em tamanho único com área de estampa horizontal de 49×30cm. Base escura.', 99.90, 'Feito no Espírito Santo', '#17121F', 100)
on conflict (slug) do nothing;

-- 2. PEDIDOS
create table if not exists public.orders (
  id uuid primary key default gen_random_uuid(),
  user_id uuid references auth.users(id),
  product_id uuid not null references public.products(id),
  quantidade integer not null default 1 check (quantidade > 0),
  status text not null default 'recebido'
    check (status in ('recebido', 'em_producao', 'enviado')),
  imagem_cliente text,
  imagem_aprovada boolean not null default false,
  frase_customizada text check (char_length(frase_customizada) <= 20),
  preco_final numeric(10,2),
  criado_em timestamptz not null default now()
);

-- 3. BAIXA DE ESTOQUE AUTOMÁTICA E ATÔMICA
-- ⚠️ TODO: quando o pagamento for integrado, mover a baixa
-- para a confirmação do pagamento (webhook).
create or replace function public.baixar_estoque()
returns trigger language plpgsql security definer as $$
begin
  update public.products
     set estoque = estoque - new.quantidade
   where id = new.product_id and estoque >= new.quantidade;
  if not found then
    raise exception 'ESTOQUE_INSUFICIENTE';
  end if;
  return new;
end; $$;

drop trigger if exists trg_baixar_estoque on public.orders;
create trigger trg_baixar_estoque
  before insert on public.orders
  for each row execute function public.baixar_estoque();

create or replace function public.devolver_estoque()
returns trigger language plpgsql security definer as $$
begin
  update public.products
     set estoque = estoque + old.quantidade
   where id = old.product_id;
  return old;
end; $$;

drop trigger if exists trg_devolver_estoque on public.orders;
create trigger trg_devolver_estoque
  before delete on public.orders
  for each row execute function public.devolver_estoque();

-- 4. RLS
alter table public.products enable row level security;
alter table public.orders enable row level security;

create policy "produtos_leitura_publica"
  on public.products for select using (ativo = true);

create policy "pedidos_proprios_select"
  on public.orders for select using (auth.uid() = user_id);

create policy "pedidos_proprios_insert"
  on public.orders for insert with check (auth.uid() = user_id);

-- 5. REALTIME (estoque ao vivo no site)
alter publication supabase_realtime add table public.products;
