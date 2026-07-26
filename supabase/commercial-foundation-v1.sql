-- ============================================================================
-- BDFlow Site — Fase 1: Fundação da Arquitetura Comercial
-- ============================================================================
-- Escopo: território, regiões, seis nichos, exclusividades e formação de 84.
--
-- CONVENÇÃO: o projeto NÃO usa supabase/migrations/ com timestamp; usa
-- arquivos temáticos em supabase/ (site-schema-v2.sql, site-partner-core.sql).
-- Esta migration segue esse padrão real.
--
-- SEGURANÇA / EXECUÇÃO:
--   • Migration ADITIVA e ISOLADA. Não edita nem remove estruturas antigas.
--   • Deve ser REVISADA por humano e executada manualmente no SQL Editor.
--   • NÃO executar automaticamente. NÃO db push / db reset.
--   • Idempotente e não-silenciosa: seeds via blocos DO (inserir-se-ausente;
--     seguir se canônico; erro explícito se divergente).
--
-- AUTORIDADE: o banco é a autoridade. O navegador nunca escreve nestas
-- tabelas nem define quantidade, status ou formação. Leitura pública ocorre
-- exclusivamente pelas RPCs security definer ao final do arquivo.
-- ============================================================================

-- Transação explícita: se qualquer instrução falhar, nada é aplicado — não
-- deixa uma fundação parcialmente criada. Sem commit intermediário.
begin;

-- ---------------------------------------------------------------------------
-- 11.0  Helpers de normalização/validação (imutáveis, sem efeitos colaterais)
-- ---------------------------------------------------------------------------
-- commercial_city_key: chave canônica de cidade. A ORDEM é crítica —
-- lower() ANTES da remoção de acentos, para que "VITÓRIA", "Vitória",
-- "Vitoria" e "vitória" convirjam todos para "vitoria". Usa translate
-- (sem depender da extensão unaccent, que NÃO é criada nesta migration).
create or replace function public.commercial_city_key(p_city text)
returns text
language sql
immutable
as $$
  select regexp_replace(
           translate(
             lower(btrim(coalesce(p_city, ''))),
             'áàâãäéèêëíìîïóòôõöúùûüç',
             'aaaaaeeeeiiiiooooouuuuc'
           ),
           '\s+', '-', 'g'
         );
$$;

-- commercial_is_valid_uf: aceita SOMENTE as 27 UFs brasileiras canônicas.
-- Rejeita 'XX', 'ZZ', 'E', 'ESP', vazio e null. Não aceita "duas letras".
create or replace function public.commercial_is_valid_uf(p_uf text)
returns boolean
language sql
immutable
as $$
  select upper(btrim(coalesce(p_uf, ''))) in (
    'AC','AL','AP','AM','BA','CE','DF','ES','GO','MA','MT','MS','MG',
    'PA','PB','PR','PE','PI','RJ','RN','RS','RO','RR','SC','SP','SE','TO'
  );
$$;

-- Lista canônica das 27 UFs, reutilizada nas constraints CHECK abaixo.
--   (Mantida explícita e inline no CHECK para não criar dependência de
--    função em constraint.)

-- ---------------------------------------------------------------------------
-- 11.1  commercial_regions
-- ---------------------------------------------------------------------------
create table if not exists public.commercial_regions (
  id          uuid primary key default gen_random_uuid(),
  uf          text not null,
  name        text not null,
  slug        text not null,
  is_active   boolean not null default false,
  created_at  timestamptz not null default now(),
  updated_at  timestamptz not null default now(),
  constraint commercial_regions_uf_valid check (
    uf in (
      'AC','AL','AP','AM','BA','CE','DF','ES','GO','MA','MT','MS','MG',
      'PA','PB','PR','PE','PI','RJ','RN','RS','RO','RR','SC','SP','SE','TO'
    )
  ),
  constraint commercial_regions_name_not_empty check (length(btrim(name)) > 0),
  constraint commercial_regions_slug_unique_per_uf unique (uf, slug)
);
create index if not exists idx_commercial_regions_uf_active
  on public.commercial_regions (uf, is_active);

-- ---------------------------------------------------------------------------
-- 11.2  commercial_region_cities
-- ---------------------------------------------------------------------------
create table if not exists public.commercial_region_cities (
  id          uuid primary key default gen_random_uuid(),
  region_id   uuid not null references public.commercial_regions(id),
  uf          text not null,
  city_name   text not null,
  city_key    text not null,
  is_active   boolean not null default true,
  created_at  timestamptz not null default now(),
  updated_at  timestamptz not null default now(),
  constraint commercial_region_cities_uf_valid check (
    uf in (
      'AC','AL','AP','AM','BA','CE','DF','ES','GO','MA','MT','MS','MG',
      'PA','PB','PR','PE','PI','RJ','RN','RS','RO','RR','SC','SP','SE','TO'
    )
  ),
  constraint commercial_region_cities_city_not_empty check (length(btrim(city_name)) > 0),
  constraint commercial_region_cities_city_unique_per_uf unique (uf, city_name),
  constraint commercial_region_cities_key_unique_per_uf unique (uf, city_key)
);
create index if not exists idx_commercial_region_cities_lookup
  on public.commercial_region_cities (uf, city_key, is_active);
create index if not exists idx_commercial_region_cities_region
  on public.commercial_region_cities (region_id);

-- Garante que região e cidade compartilham a mesma UF (trigger, pois um CHECK
-- não pode consultar outra tabela).
create or replace function public.commercial_region_cities_same_uf()
returns trigger language plpgsql as $$
declare
  v_region_uf text;
begin
  select uf into v_region_uf
    from public.commercial_regions
    where id = new.region_id;
  if v_region_uf is null then
    raise exception 'Região % inexistente.', new.region_id;
  end if;
  if v_region_uf <> new.uf then
    raise exception 'UF da cidade (%) difere da UF da região (%).',
      new.uf, v_region_uf;
  end if;
  return new;
end;
$$;

drop trigger if exists trg_commercial_region_cities_same_uf
  on public.commercial_region_cities;
create trigger trg_commercial_region_cities_same_uf
  before insert or update on public.commercial_region_cities
  for each row execute function public.commercial_region_cities_same_uf();

-- ---------------------------------------------------------------------------
-- 11.3  commercial_niches  (código textual = PK, referenciado por FK)
-- ---------------------------------------------------------------------------
create table if not exists public.commercial_niches (
  code                text primary key,
  display_name        text not null,
  contracted_quantity integer not null,
  sort_order          integer not null,
  is_active           boolean not null default true,
  created_at          timestamptz not null default now(),
  updated_at          timestamptz not null default now(),
  constraint commercial_niches_qty_positive check (contracted_quantity > 0),
  constraint commercial_niches_order_positive check (sort_order > 0),
  constraint commercial_niches_name_not_empty check (length(btrim(display_name)) > 0),
  constraint commercial_niches_code_allowed check (
    code in (
      'supermarket', 'pharmacy',
      'womens_clothing', 'mens_clothing',
      'womens_footwear', 'mens_footwear'
    )
  ),
  -- Ordem canônica: valor entre 1 e 6 e único (seis ordens distintas).
  constraint commercial_niches_sort_order_range check (sort_order between 1 and 6),
  constraint commercial_niches_sort_order_unique unique (sort_order),
  -- Mapeamento canônico completo código → (quantidade, ordem). Trava a
  -- quantidade por nicho (supermarket=24, demais=12) e a ordem canônica.
  constraint commercial_niches_canonical check (
    (code, contracted_quantity, sort_order) in (
      ('supermarket',     24, 1),
      ('pharmacy',        12, 2),
      ('womens_clothing', 12, 3),
      ('mens_clothing',   12, 4),
      ('womens_footwear', 12, 5),
      ('mens_footwear',   12, 6)
    )
  )
);

-- ---------------------------------------------------------------------------
-- 11.4  commercial_exclusivities
-- ---------------------------------------------------------------------------
create table if not exists public.commercial_exclusivities (
  id                       uuid primary key default gen_random_uuid(),
  region_id                uuid not null references public.commercial_regions(id),
  sequence_number          integer not null,
  status                   text not null,
  is_current               boolean not null default false,
  planned_start_at         timestamptz null,
  formed_at                timestamptz null,
  operation_authorized_at  timestamptz null,
  operation_started_at     timestamptz null,
  operation_completed_at   timestamptz null,
  created_at               timestamptz not null default now(),
  updated_at               timestamptz not null default now(),
  constraint commercial_exclusivities_seq_positive check (sequence_number > 0),
  constraint commercial_exclusivities_seq_unique_per_region
    unique (region_id, sequence_number),
  constraint commercial_exclusivities_status_allowed check (
    status in (
      'forming', 'formed', 'start_scheduled',
      'operation_authorized', 'operation_started',
      'operation_completed', 'operation_paused'
    )
  )
);
-- No máximo UMA exclusividade atual por região.
create unique index if not exists uq_commercial_exclusivities_current_per_region
  on public.commercial_exclusivities (region_id)
  where is_current;

-- ---------------------------------------------------------------------------
-- 11.5  commercial_opportunities
-- ---------------------------------------------------------------------------
create table if not exists public.commercial_opportunities (
  id                   uuid primary key default gen_random_uuid(),
  exclusivity_id       uuid not null references public.commercial_exclusivities(id),
  niche_code           text not null references public.commercial_niches(code),
  contracted_quantity  integer not null,
  status               text not null default 'available',
  reserved_until       timestamptz null,
  created_at           timestamptz not null default now(),
  updated_at           timestamptz not null default now(),
  constraint commercial_opportunities_qty_positive check (contracted_quantity > 0),
  constraint commercial_opportunities_status_allowed check (
    status in ('available', 'reserved', 'payment_pending', 'contracted')
  ),
  constraint commercial_opportunities_unique_niche_per_exclusivity
    unique (exclusivity_id, niche_code)
);
create index if not exists idx_commercial_opportunities_exclusivity
  on public.commercial_opportunities (exclusivity_id);

-- Quantidade canônica server-side: a oportunidade NÃO pode ter qualquer
-- quantidade positiva — deve casar com a quantidade canônica do nicho em
-- commercial_niches. Não confia em valor do navegador e não corrige em
-- silêncio: gera exceção clara para execução administrativa.
create or replace function public.commercial_opportunities_canonical_qty()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_canonical integer;
begin
  select contracted_quantity into v_canonical
    from public.commercial_niches
    where code = new.niche_code;
  if v_canonical is null then
    raise exception 'Nicho % inexistente em commercial_niches.', new.niche_code;
  end if;
  if new.contracted_quantity <> v_canonical then
    raise exception
      'Quantidade % diverge da canônica % para o nicho %.',
      new.contracted_quantity, v_canonical, new.niche_code;
  end if;
  return new;
end;
$$;

drop trigger if exists trg_commercial_opportunities_canonical_qty
  on public.commercial_opportunities;
create trigger trg_commercial_opportunities_canonical_qty
  before insert or update on public.commercial_opportunities
  for each row execute function public.commercial_opportunities_canonical_qty();

-- ============================================================================
-- SEEDS  (idempotentes e NÃO-silenciosos)
-- ============================================================================
-- Regra por registro: se não existir, inserir; se existir com os valores
-- canônicos, seguir; se existir DIVERGENTE, interromper com erro explícito.
-- Não sobrescreve, não escolhe arbitrariamente, não apaga. Reexecutável após
-- uma execução bem-sucedida sem duplicar.

-- Região: Grande Vitória (ES), ativa.
do $$
declare
  cur record;
begin
  select * into cur from public.commercial_regions
    where uf = 'ES' and slug = 'grande-vitoria';
  if not found then
    insert into public.commercial_regions (uf, name, slug, is_active)
    values ('ES', 'Grande Vitória', 'grande-vitoria', true);
  elsif cur.name <> 'Grande Vitória' or cur.is_active is distinct from true then
    raise exception
      'Seed divergente em commercial_regions (Grande Vitória): name=%, is_active=%.',
      cur.name, cur.is_active;
  end if;
end $$;

-- Cidades da Grande Vitória. A city_key vem da MESMA função da RPC.
do $$
declare
  v_region_id uuid;
  c text;
  v_key text;
  cur record;
begin
  select id into v_region_id from public.commercial_regions
    where uf = 'ES' and slug = 'grande-vitoria';
  if v_region_id is null then
    raise exception 'Região Grande Vitória ausente ao semear cidades.';
  end if;
  foreach c in array array['Vitória','Vila Velha','Serra','Cariacica','Viana']
  loop
    v_key := public.commercial_city_key(c);
    select * into cur from public.commercial_region_cities
      where uf = 'ES' and city_name = c;
    if not found then
      insert into public.commercial_region_cities
        (region_id, uf, city_name, city_key, is_active)
      values (v_region_id, 'ES', c, v_key, true);
    elsif cur.region_id <> v_region_id
       or cur.city_key <> v_key
       or cur.is_active is distinct from true then
      raise exception 'Seed divergente em commercial_region_cities (%).', c;
    end if;
  end loop;
end $$;

-- Seis nichos canônicos (soma = 84). Divergência de nome/quantidade/ordem para.
do $$
declare
  canon record;
  cur record;
begin
  for canon in
    select * from (values
      ('supermarket',     'Supermercado',        24, 1),
      ('pharmacy',        'Farmácia',            12, 2),
      ('womens_clothing', 'Roupas femininas',    12, 3),
      ('mens_clothing',   'Roupas masculinas',   12, 4),
      ('womens_footwear', 'Calçados femininos',  12, 5),
      ('mens_footwear',   'Calçados masculinos', 12, 6)
    ) as t(code, display_name, contracted_quantity, sort_order)
  loop
    select * into cur from public.commercial_niches where code = canon.code;
    if not found then
      insert into public.commercial_niches
        (code, display_name, contracted_quantity, sort_order)
      values (canon.code, canon.display_name,
              canon.contracted_quantity, canon.sort_order);
    elsif cur.display_name <> canon.display_name
       or cur.contracted_quantity <> canon.contracted_quantity
       or cur.sort_order <> canon.sort_order then
      raise exception
        'Seed divergente em commercial_niches (%): esperado %/%/%, achado %/%/%.',
        canon.code, canon.display_name, canon.contracted_quantity, canon.sort_order,
        cur.display_name, cur.contracted_quantity, cur.sort_order;
    end if;
  end loop;
end $$;

-- Primeira exclusividade da Grande Vitória: sequência 1, forming, atual.
-- Status e is_current são administrativamente mutáveis (a exclusividade evolui);
-- por isso, se já existir a sequência 1, mantém-se como está (sem erro e sem
-- sobrescrever). Sem data de início (não inventar).
do $$
declare
  v_region_id uuid;
  cur record;
begin
  select id into v_region_id from public.commercial_regions
    where uf = 'ES' and slug = 'grande-vitoria';
  select * into cur from public.commercial_exclusivities
    where region_id = v_region_id and sequence_number = 1;
  if not found then
    insert into public.commercial_exclusivities
      (region_id, sequence_number, status, is_current)
    values (v_region_id, 1, 'forming', true);
  end if;
end $$;

-- Seis oportunidades (todas available), quantidade = canônica do nicho.
-- Status da oportunidade é mutável administrativamente; se já existir o par
-- (exclusividade, nicho), só barra se a QUANTIDADE divergir da canônica.
do $$
declare
  v_exc_id uuid;
  n record;
  cur record;
begin
  select e.id into v_exc_id
    from public.commercial_exclusivities e
    join public.commercial_regions r on r.id = e.region_id
    where r.uf = 'ES' and r.slug = 'grande-vitoria' and e.sequence_number = 1;
  if v_exc_id is null then
    raise exception 'Exclusividade seq 1 ausente ao semear oportunidades.';
  end if;
  for n in select code, contracted_quantity from public.commercial_niches loop
    select * into cur from public.commercial_opportunities
      where exclusivity_id = v_exc_id and niche_code = n.code;
    if not found then
      insert into public.commercial_opportunities
        (exclusivity_id, niche_code, contracted_quantity, status)
      values (v_exc_id, n.code, n.contracted_quantity, 'available');
    elsif cur.contracted_quantity <> n.contracted_quantity then
      raise exception
        'Seed divergente em commercial_opportunities (%): quantidade % vs canônica %.',
        n.code, cur.contracted_quantity, n.contracted_quantity;
    end if;
  end loop;
end $$;


-- ============================================================================
-- 12. INTEGRIDADE DA FORMAÇÃO  (função interna, somente leitura)
-- ============================================================================
-- Formação completa exige 6 oportunidades CONTRATADAS *e* 84 unidades
-- correspondentes (não basta a soma de unidades). Retorna resumo em jsonb.
create or replace function public.commercial_formation_summary(p_exclusivity_id uuid)
returns jsonb
language sql
stable
security definer
set search_path = public
as $$
  select jsonb_build_object(
    'total_opportunities',       count(*),
    'contracted_opportunities',  count(*) filter (where status = 'contracted'),
    'total_units',               coalesce(sum(contracted_quantity), 0),
    'contracted_units',          coalesce(sum(contracted_quantity)
                                   filter (where status = 'contracted'), 0),
    'formation_percent',         case
                                   when count(*) = 0 then 0
                                   else round(
                                     100.0 * count(*) filter (where status = 'contracted')
                                     / count(*)
                                   )
                                 end,
    'is_complete',               (
                                   count(*) filter (where status = 'contracted') = 6
                                   and coalesce(sum(contracted_quantity)
                                     filter (where status = 'contracted'), 0) = 84
                                 )
  )
  from public.commercial_opportunities
  where exclusivity_id = p_exclusivity_id;
$$;

-- ============================================================================
-- 13. RPC  resolve_commercial_region  (somente leitura)
-- ============================================================================
-- Decisões de segurança:
--   • security definer + search_path fixo em public (evita hijack de schema).
--   • Somente leitura: nenhuma escrita.
--   • Normaliza entrada; rejeita UF inválida e cidade vazia.
--   • Nunca associa cidade desconhecida a nenhuma região; nunca cruza UF.
--   • Não recebe region_id do navegador — resolve pela combinação UF+cidade.
--   • Retorna conjunto vazio (região null) quando não há região ativa.
--   • Não retorna dados privados.
create or replace function public.resolve_commercial_region(p_uf text, p_city text)
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_uf   text := upper(btrim(coalesce(p_uf, '')));
  -- Normalização canônica com caixa correta (lower antes de remover acentos).
  v_key  text := public.commercial_city_key(p_city);
  v_row  record;
begin
  -- UF precisa ser uma das 27 canônicas (rejeita XX, ZZ, E, ESP, vazio, null).
  if not public.commercial_is_valid_uf(p_uf) then
    return jsonb_build_object('region_available', false, 'reason', 'invalid_uf');
  end if;
  if length(v_key) = 0 then
    return jsonb_build_object('region_available', false, 'reason', 'empty_city');
  end if;

  select r.id as region_id, r.name as region_name, r.slug as region_slug,
         c.uf, c.city_name, r.is_active
    into v_row
    from public.commercial_region_cities c
    join public.commercial_regions r on r.id = c.region_id
    where c.uf = v_uf
      and c.city_key = v_key
      and c.is_active
      and r.is_active
    limit 1;

  if v_row.region_id is null then
    return jsonb_build_object('region_available', false, 'uf', v_uf);
  end if;

  return jsonb_build_object(
    'region_available', true,
    'region_id',   v_row.region_id,
    'region_name', v_row.region_name,
    'region_slug', v_row.region_slug,
    'uf',          v_row.uf,
    'city_name',   v_row.city_name,
    'is_active',   v_row.is_active
  );
end;
$$;

-- ============================================================================
-- 14. RPC  get_current_commercial_formation  (somente leitura)
-- ============================================================================
-- Resolve a região no backend, localiza a exclusividade atual e retorna
-- dados PÚBLICOS: região, exclusividade, resumo e as seis oportunidades
-- ordenadas por sort_order. Nunca retorna contratos, CNPJ, reservas
-- privadas ou dados financeiros. Sem fallback mock.
create or replace function public.get_current_commercial_formation(p_uf text, p_city text)
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_region jsonb;
  v_region_id uuid;
  v_exc record;
  v_opportunities jsonb;
  v_summary jsonb;
begin
  v_region := public.resolve_commercial_region(p_uf, p_city);

  if coalesce((v_region->>'region_available')::boolean, false) = false then
    return jsonb_build_object('region_available', false, 'region', v_region);
  end if;

  v_region_id := (v_region->>'region_id')::uuid;

  select e.* into v_exc
    from public.commercial_exclusivities e
    where e.region_id = v_region_id and e.is_current
    limit 1;

  if v_exc.id is null then
    return jsonb_build_object(
      'region_available', true,
      'exclusivity_available', false,
      'region', v_region
    );
  end if;

  select jsonb_agg(
           jsonb_build_object(
             'id',                  o.id,
             'exclusivity_id',      o.exclusivity_id,
             'niche_code',          o.niche_code,
             'display_name',        n.display_name,
             'contracted_quantity', o.contracted_quantity,
             'status',              o.status,
             'sort_order',          n.sort_order
           ) order by n.sort_order
         )
    into v_opportunities
    from public.commercial_opportunities o
    join public.commercial_niches n on n.code = o.niche_code
    where o.exclusivity_id = v_exc.id;

  v_summary := public.commercial_formation_summary(v_exc.id);

  return jsonb_build_object(
    'region_available', true,
    'exclusivity_available', true,
    'region', v_region,
    'exclusivity', jsonb_build_object(
      'id',              v_exc.id,
      'region_id',       v_exc.region_id,
      'sequence_number', v_exc.sequence_number,
      'status',          v_exc.status,
      'is_current',      v_exc.is_current,
      'planned_start_at',v_exc.planned_start_at
    ),
    'summary', v_summary,
    'opportunities', coalesce(v_opportunities, '[]'::jsonb)
  );
end;
$$;

-- ============================================================================
-- 15. RLS E PERMISSÕES
-- ============================================================================
-- Ativa RLS em todas as novas tabelas. NENHUMA policy de escrita é criada
-- (navegador não insere/atualiza/exclui). Não há policy permissiva de
-- escrita. A leitura pública ocorre pelas RPCs security definer acima, que
-- rodam com o dono da função e por isso não dependem de policy de SELECT.
alter table public.commercial_regions        enable row level security;
alter table public.commercial_region_cities  enable row level security;
alter table public.commercial_niches         enable row level security;
alter table public.commercial_exclusivities  enable row level security;
alter table public.commercial_opportunities  enable row level security;

-- Revoga acesso direto às tabelas dos papéis do navegador. O frontend NÃO
-- consulta as tabelas diretamente — apenas via RPC.
revoke all on public.commercial_regions        from anon, authenticated;
revoke all on public.commercial_region_cities  from anon, authenticated;
revoke all on public.commercial_niches         from anon, authenticated;
revoke all on public.commercial_exclusivities  from anon, authenticated;
revoke all on public.commercial_opportunities  from anon, authenticated;

-- Concede execução das RPCs de leitura aos papéis públicos.
-- (A função interna de resumo não é concedida ao público: é usada
-- internamente pela get_current_commercial_formation.)
revoke all on function public.resolve_commercial_region(text, text) from public;
grant execute on function public.resolve_commercial_region(text, text) to anon, authenticated;

revoke all on function public.get_current_commercial_formation(text, text) from public;
grant execute on function public.get_current_commercial_formation(text, text) to anon, authenticated;

revoke all on function public.commercial_formation_summary(uuid) from public;

-- Funções auxiliares NÃO devem ser chamáveis diretamente pelo navegador.
-- Revoga EXECUTE de public/anon/authenticated (as funções de trigger seguem
-- operando internamente, pois são invocadas pelos triggers, não por chamada
-- direta). Assinaturas completas conforme os parâmetros reais.
revoke all on function public.commercial_city_key(text)            from public, anon, authenticated;
revoke all on function public.commercial_is_valid_uf(text)         from public, anon, authenticated;
revoke all on function public.commercial_region_cities_same_uf()   from public, anon, authenticated;
revoke all on function public.commercial_opportunities_canonical_qty() from public, anon, authenticated;

-- Fecha a transação. Qualquer falha acima aborta tudo (nenhum commit parcial).
commit;

-- ============================================================================
-- FIM — revisar e executar manualmente no SQL Editor. Não executada aqui.
-- ============================================================================
