-- ============================================================================
-- SUITE 130 — Precificação (R5) + REVISÃO DE SEGURANÇA formal da emenda 4
-- ============================================================================

select tests.reset_results();

-- Autoridade ATIVA (sem pino de versao): depois do P0-3 resolve para a
-- versao tecnica 3 / SF-v1.4.
select public.calculate_niche_contract_pricing('pharmacy', false) as p12 \gset
select public.calculate_niche_contract_pricing('supermarket', false) as p24 \gset
select public.calculate_niche_contract_pricing('pharmacy', true) as f12 \gset
select public.calculate_niche_contract_pricing('supermarket', true) as f24 \gset

-- Autoridade HISTORICA V2, pinada explicitamente. Serve as asserções cuja
-- finalidade declarada e provar a economia V2, que nao governa mais contrato
-- novo mas continua integralmente legivel.
select public.calculate_niche_contract_pricing('pharmacy', false, 2) as p12v2 \gset
select public.calculate_niche_contract_pricing('supermarket', false, 2) as p24v2 \gset
select public.calculate_niche_contract_pricing('pharmacy', true, 2) as f12v2 \gset
select public.calculate_niche_contract_pricing('supermarket', true, 2) as f24v2 \gset

-- ---------------------------------------------------------------------------
-- HISTORICAL_V2 — valores canônicos do lançamento V2, em versao pinada.
-- Os centavos originais permanecem inalterados.
-- ---------------------------------------------------------------------------
select tests.check('V2 historica: nao fidelizado 12 = R$ 19.999,00',
    ((:'p12v2')::jsonb ->> 'economic_value_cents')::bigint = 1999900);
select tests.check('V2 historica: nao fidelizado 24 = R$ 35.587,00',
    ((:'p24v2')::jsonb ->> 'economic_value_cents')::bigint = 3558700);
select tests.check('V2 historica: fidelizado 12 = R$ 15.588,00',
    ((:'f12v2')::jsonb ->> 'economic_value_cents')::bigint = 1558800);
select tests.check('V2 historica: fidelizado 24 = R$ 31.176,00',
    ((:'f24v2')::jsonb ->> 'economic_value_cents')::bigint = 3117600);
select tests.check('V2 historica: pool comum = R$ 13.354,59',
    ((:'p12v2')::jsonb ->> 'contractual_pool_cents')::bigint = 1335459);
select tests.check('V2 historica: devido BDFlow comum = R$ 6.644,41',
    ((:'p12v2')::jsonb ->> 'bdflow_due_cents')::bigint = 664441);
select tests.check('V2 historica: pool supermercado = R$ 25.543,05',
    ((:'p24v2')::jsonb ->> 'contractual_pool_cents')::bigint = 2554305);
select tests.check('V2 historica: devido BDFlow supermercado = R$ 10.043,95',
    ((:'p24v2')::jsonb ->> 'bdflow_due_cents')::bigint = 1004395);
-- Os fidelizados da V2 derivam da MESMA razao exata, por aritmetica inteira.
select tests.check('V2 historica: pool fidelizado comum = R$ 10.409,08',
    ((:'f12v2')::jsonb ->> 'contractual_pool_cents')::bigint = 1040908
    and ((:'f12v2')::jsonb ->> 'bdflow_due_cents')::bigint = 517892);
select tests.check('V2 historica: pool fidelizado supermercado = R$ 22.376,99',
    ((:'f24v2')::jsonb ->> 'contractual_pool_cents')::bigint = 2237699
    and ((:'f24v2')::jsonb ->> 'bdflow_due_cents')::bigint = 879901);

with todos as (
  select public.calculate_niche_contract_pricing(n.code, false, 2) as pr
    from public.commercial_niches n where n.is_active
), somas as (
  select sum((pr->>'economic_value_cents')::bigint) as eco,
         sum((pr->>'contractual_pool_cents')::bigint) as pool,
         sum((pr->>'bdflow_due_cents')::bigint) as devido
    from todos
)
select tests.check('V2 historica: formacao completa economico = R$ 135.582,00', eco = 13558200),
       tests.check('V2 historica: formacao completa pools = R$ 92.316,00', pool = 9231600),
       tests.check('V2 historica: formacao completa devido = R$ 43.266,00', devido = 4326600)
  from somas;

-- ---------------------------------------------------------------------------
-- ACTIVE_V14 — a autoridade vigente da vitrine publica. Centavos congelados
-- do contrato v1.4, inteiros, nao derivaveis de formula por unidade.
-- ---------------------------------------------------------------------------
select tests.check('v1.4 ativa: comum nao fidelizado = R$ 19.999,00',
    ((:'p12')::jsonb ->> 'economic_value_cents')::bigint = 1999900);
select tests.check('v1.4 ativa: supermercado nao fidelizado = R$ 29.999,00',
    ((:'p24')::jsonb ->> 'economic_value_cents')::bigint = 2999900);
select tests.check('v1.4 ativa: comum fidelizado = R$ 16.188,00',
    ((:'f12')::jsonb ->> 'economic_value_cents')::bigint = 1618800);
select tests.check('v1.4 ativa: supermercado fidelizado = R$ 28.176,00',
    ((:'f24')::jsonb ->> 'economic_value_cents')::bigint = 2817600);
select tests.check('v1.4 ativa: pool comum = R$ 11.988,00 e devido = R$ 8.011,00',
    ((:'p12')::jsonb ->> 'contractual_pool_cents')::bigint = 1198800
    and ((:'p12')::jsonb ->> 'bdflow_due_cents')::bigint = 801100);
select tests.check('v1.4 ativa: pool supermercado = R$ 23.976,00 e devido = R$ 6.023,00',
    ((:'p24')::jsonb ->> 'contractual_pool_cents')::bigint = 2397600
    and ((:'p24')::jsonb ->> 'bdflow_due_cents')::bigint = 602300);
-- A taxa principal fidelizada e a MESMA nas duas categorias (R$ 4.200,00) —
-- e exatamente por isso que nenhuma formula por unidade representa a v1.4.
select tests.check('v1.4 ativa: taxa principal fidelizada identica nas duas categorias',
    ((:'f12')::jsonb ->> 'smallflags_main_fee_cents')::bigint = 420000
    and ((:'f24')::jsonb ->> 'smallflags_main_fee_cents')::bigint = 420000);
select tests.check('v1.4 ativa: rotulo legal SF-v1.4 carimbado no retorno',
    ((:'p24')::jsonb ->> 'contract_economics_version') = 'SF-v1.4'
    and ((:'f24')::jsonb ->> 'contract_economics_version') = 'SF-v1.4');
-- A parcela de QA pertence a SmallFlags e esta DENTRO do pool contratual.
select tests.check('v1.4 ativa: remuneracao total = taxa principal + QA',
    ((:'p24')::jsonb ->> 'smallflags_total_remuneration_cents')::bigint
      = ((:'p24')::jsonb ->> 'smallflags_main_fee_cents')::bigint
        + ((:'p24')::jsonb ->> 'smallflags_qa_cents')::bigint);

with todos as (
  select public.calculate_niche_contract_pricing(n.code, false) as pr
    from public.commercial_niches n where n.is_active
), somas as (
  select sum((pr->>'economic_value_cents')::bigint) as eco,
         sum((pr->>'contractual_pool_cents')::bigint) as pool,
         sum((pr->>'bdflow_due_cents')::bigint) as devido
    from todos
)
select tests.check('v1.4 ativa: formacao completa economico = R$ 129.994,00', eco = 12999400),
       tests.check('v1.4 ativa: formacao completa pools = R$ 83.916,00', pool = 8391600),
       tests.check('v1.4 ativa: formacao completa devido = R$ 46.078,00', devido = 4607800)
  from somas;

-- Invariante em TODAS as combinações
with comb as (
  select public.calculate_niche_contract_pricing(n.code, f.fid) as pr
    from public.commercial_niches n
    cross join (values (true),(false)) as f(fid)
   where n.is_active
)
select tests.check('invariante economico = pool + devido em todas as combinacoes',
    (select count(*) from comb
      where (pr->>'economic_value_cents')::bigint
            <> (pr->>'contractual_pool_cents')::bigint
               + (pr->>'bdflow_due_cents')::bigint) = 0);

-- V2 (HISTORICAL_V2): a participacao do pool e razao exata de inteiros; nao
-- existe ponto-base honesto, entao pool_bps e NULL e o modelo e 'exact_ratio'.
-- A versao e pinada: a V2 nao e mais a autoridade ativa, mas seu modelo de
-- precisao continua exatamente o que sempre foi.
select tests.check('V2 historica: pool_bps NULO e modelo de razao exata',
    (select count(*) from public.commercial_niches n
      where n.is_active
        and ((public.calculate_niche_contract_pricing(n.code,false,2)->>'pool_bps') is not null
             or (public.calculate_niche_contract_pricing(n.code,false,2)->>'pool_precision_model')
                <> 'exact_ratio')) = 0);
-- ACTIVE_V14: a autoridade vigente tambem nao tem ponto-base honesto, mas seu
-- modelo declarado e outro — tabela explicita de centavos congelados.
select tests.check('v1.4 ativa: pool_bps NULO e modelo de agenda explicita',
    (select count(*) from public.commercial_niches n
      where n.is_active
        and ((public.calculate_niche_contract_pricing(n.code,false)->>'pool_bps') is not null
             or (public.calculate_niche_contract_pricing(n.code,false)->>'pool_precision_model')
                <> 'explicit_schedule')) = 0);
-- REGRESSAO HISTORICA: a V1 continua legivel, com os 7500/7000 originais e
-- os centavos que ela sempre produziu. A ativacao da V2 nao reescreveu nada.
select tests.check('V1 historica intacta: 7500 bps supermercado e 7000 demais',
    (select count(*) from public.commercial_niches n
      where n.is_active
        and (public.calculate_niche_contract_pricing(n.code,false,1)->>'pool_bps')::int
            <> case when n.code='supermarket' then 7500 else 7000 end) = 0);
select tests.check('V1 historica preservada na tabela como superseded',
    (select count(*) from public.commercial_pricing_rules
      where version = 1 and status = 'superseded'
        and pool_bps_supermarket = 7500 and pool_bps_common = 7000
        and pool_precision_model = 'basis_points') = 1);
select tests.check('V1 historica ainda produz os centavos da V1',
    (public.calculate_niche_contract_pricing('pharmacy',false,1)
       ->>'contractual_pool_cents')::bigint = 1399930
    and (public.calculate_niche_contract_pricing('supermarket',false,1)
       ->>'contractual_pool_cents')::bigint = 2669025);
select tests.check('bloco de 12 cobre o nicho comum sem unidade extra',
    ((:'p12')::jsonb ->> 'economic_value_cents')::bigint = 1999900
    and ((:'p12')::jsonb ->> 'nominal_quantity')::int = 12);
-- ACTIVE_V14: continua existindo EXATAMENTE uma autoridade ativa; depois do
-- P0-3 ela e a versao tecnica 3. V1 e V2 seguem como superseded.
select tests.check('regra ativa e unica e carimbada no retorno',
    (select count(*) from public.commercial_pricing_rules where status='active') = 1
    and ((:'p24')::jsonb ->> 'pricing_rule_version')::int = 3);
select tests.check('linhagem de versoes: V1 e V2 historicas, V3 unica ativa',
    (select status from public.commercial_pricing_rules where version=1) = 'superseded'
    and (select status from public.commercial_pricing_rules where version=2) = 'superseded'
    and (select status from public.commercial_pricing_rules where version=3) = 'active');

-- Falha fechada (contrato jsonb do M1: ok=false, sem inventar preço)
select tests.check('nicho invalido nao produz preco',
    (public.calculate_niche_contract_pricing('bakery', false) ->> 'ok') = 'false'
    and (public.calculate_niche_contract_pricing('bakery', false) ->> 'reason')
        = 'invalid_niche');
select tests.check('versao de regra inexistente falha fechada',
    (public.calculate_niche_contract_pricing('pharmacy', false, 99) ->> 'reason')
        = 'pricing_rule_unavailable');

-- ===========================================================================
-- REVISÃO DE SEGURANÇA (emenda 4) — cada item provado
-- ===========================================================================
create temporary table fn_preco (nome text primary key, args text);
insert into fn_preco values
  ('calculate_niche_contract_pricing','text,boolean,integer'),
  ('get_public_niche_pricing',''),
  ('get_public_formation_economics',''),
  ('is_fidelized_context','text,text,text,text');

-- 1. search_path fixo e seguro
select tests.check('SEG-1: toda funcao de preco tem search_path fixo pg_catalog',
    (select count(*) from fn_preco f
       join pg_proc p on p.proname = f.nome
       join pg_namespace n on n.oid = p.pronamespace and n.nspname='public'
      where coalesce(array_to_string(p.proconfig,','),'') <> 'search_path=pg_catalog') = 0);

-- 2. REVOKE de PUBLIC
select tests.check('SEG-2: nenhuma funcao de preco e executavel por PUBLIC',
    (select count(*) from fn_preco f
       join pg_proc p on p.proname = f.nome
       join pg_namespace n on n.oid = p.pronamespace and n.nspname='public'
      where has_function_privilege('public', p.oid, 'EXECUTE')) = 0);

-- 3. Grants mínimos EXATOS (igualdade de conjunto, não contagem)
select tests.check('SEG-3: grants exatos da vitrine publica',
    (select array_agg(r order by r) from (
       select unnest(array['anon','authenticated','service_role']) as r) t
      where has_function_privilege(r, 'public.get_public_niche_pricing()', 'EXECUTE'))
    = array['anon','authenticated','service_role']);
select tests.check('SEG-3: fidelidade NAO e publica (anon fora)',
    has_function_privilege('anon','public.is_fidelized_context(text,text,text,text)','EXECUTE') = false
    and has_function_privilege('authenticated','public.is_fidelized_context(text,text,text,text)','EXECUTE') = true);

-- 4. Sem escalonamento: as funções não leem identidade nem escrevem
select tests.check('SEG-4: funcoes de preco sao STABLE (nao escrevem)',
    (select count(*) from fn_preco f
       join pg_proc p on p.proname = f.nome
       join pg_namespace n on n.oid = p.pronamespace and n.nspname='public'
      where p.provolatile <> 's') = 0);
select tests.check('SEG-4: calculo publico nao consulta auth.uid nem dado pessoal',
    (select prosrc !~* '(auth\.uid|partner_application|site_company_members|cpf|cnpj)'
       from pg_proc p join pg_namespace n on n.oid=p.pronamespace
      where n.nspname='public' and p.proname='calculate_niche_contract_pricing'));

-- 5. Tabelas de preço não são legíveis direto por role de API
-- A agenda v1.4 e um objeto NOVO de preco e por isso entra na matriz de
-- seguranca junto das outras duas tabelas de preco.
select tests.check('SEG-5: tabelas de preco sem grant a role de API',
    (select count(*) from information_schema.role_table_grants
      where table_name in ('commercial_pricing_rules','commercial_pricing_schedule')
        and grantee in ('anon','authenticated')) = 0);
select tests.check('SEG-5: RLS ligada nas tabelas novas de preco',
    (select count(*) from pg_class c join pg_namespace n on n.oid=c.relnamespace
      where n.nspname='public'
        and c.relname in ('commercial_pricing_rules','commercial_fidelity_records',
                          'commercial_pricing_schedule')
        and not c.relrowsecurity) = 0);

-- 6. MATRIZ DE ATORES
begin;
select tests.impersonate('anon', null);
select public.get_public_niche_pricing() as vit \gset
select tests.check('ATOR anon: le a vitrine (exposicao publica intencional)',
    ((:'vit')::jsonb ->> 'ok') = 'true'
    and jsonb_array_length((:'vit')::jsonb -> 'niches') = 6);
select tests.check('ATOR anon: vitrine expoe valor, pool e devido',
    ((:'vit')::jsonb -> 'niches' -> 0 -> 'founding' ->> 'economic_value_cents') is not null
    and ((:'vit')::jsonb -> 'niches' -> 0 -> 'founding' ->> 'contractual_pool_cents') is not null
    and ((:'vit')::jsonb -> 'niches' -> 0 -> 'founding' ->> 'bdflow_due_cents') is not null);
select tests.check_raises('ATOR anon: NAO le a tabela de regras',
    'select count(*) from public.commercial_pricing_rules', 'permission denied');
select tests.check_raises('ATOR anon: NAO le a agenda de precos v1.4',
    'select count(*) from public.commercial_pricing_schedule', 'permission denied');
select tests.check_raises('ATOR anon: NAO le fidelidade',
    'select count(*) from public.commercial_fidelity_records', 'permission denied');
select tests.check_raises('ATOR anon: NAO consulta contexto de fidelidade',
    $sql$select public.is_fidelized_context('11222333000181','ES','Vitória','pharmacy')$sql$,
    'permission denied');
select tests.check_raises('ATOR anon: NAO altera regra de preco',
    $sql$update public.commercial_pricing_rules set block_price_cents = 1$sql$,
    'permission denied');
rollback;

select tests.mk_user('preco_user') as uid_user \gset
begin;
select tests.impersonate('authenticated', :'uid_user');
select tests.check('ATOR authenticated: le a vitrine',
    (public.get_public_niche_pricing() ->> 'ok') = 'true');
select tests.check('ATOR authenticated: nao ve fidelidade de terceiros (RLS admin)',
    (select count(*) from public.commercial_fidelity_records) = 0);
select tests.check_raises('ATOR authenticated: NAO altera regra de preco',
    $sql$update public.commercial_pricing_rules set block_price_cents = 1$sql$,
    'permission denied');
rollback;

begin;
select tests.impersonate('authenticated', (select user_id from public.site_admins limit 1));
select tests.check_raises('ATOR admin: NEM admin escreve preco por DML (so migration)',
    $sql$update public.commercial_pricing_rules set block_price_cents = 1$sql$,
    'permission denied');
rollback;

begin;
select tests.impersonate('service_role', null);
select tests.check('ATOR service_role: calcula preco (uso do backend)',
    (public.calculate_niche_contract_pricing('supermarket', false) ->> 'ok') = 'true');
rollback;

-- 7. Fidelidade: contexto correto e sem vazamento entre chaves
insert into public.commercial_fidelity_records (cnpj, uf, city_key, niche_code)
values ('11222333000181','ES', public.commercial_city_key('Vitória'), 'pharmacy');
select tests.check('fidelidade reconhecida no contexto exato',
    public.is_fidelized_context('11222333000181','ES','VITÓRIA','pharmacy') = true);
select tests.check('fidelidade nao vaza para outro nicho/cidade/CNPJ',
    public.is_fidelized_context('11222333000181','ES','Vitória','supermarket') = false
    and public.is_fidelized_context('11222333000181','ES','Serra','pharmacy') = false
    and public.is_fidelized_context('19131243000197','ES','Vitória','pharmacy') = false);
delete from public.commercial_fidelity_records where niche_code = 'pharmacy';

select tests.finish('130_m2_pricing');
