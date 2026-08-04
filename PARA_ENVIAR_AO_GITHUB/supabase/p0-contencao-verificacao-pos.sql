-- ============================================================================
-- p0-contencao-verificacao-pos.sql   (SOMENTE LEITURA — não altera nada)
-- Pacote P0 — contenção de segurança. VERSÃO CORRIGIDA (revisão 2).
--
-- Rodar DEPOIS da execução manual de p0-contencao-migration.sql no SQL
-- Editor. Confirma que a contenção surtiu efeito e que nada além do
-- pretendido foi alterado. Não executa REVOKE/GRANT/DDL — só SELECT.
--
-- Correção desta revisão: usa OID exato (via to_regprocedure, assinatura
-- canônica só com tipos) em vez de proname, e verifica permissão EFETIVA
-- com has_function_privilege() além da ACL bruta — mesmo padrão do
-- preflight e da migration corrigidos.
-- ============================================================================

-- ---------------------------------------------------------------------------
-- 1) As três funções contidas NÃO podem mais ser executáveis por
--    PUBLIC, anon ou authenticated — checagem por ACL E por permissão
--    efetiva. Resultado esperado: 0 linhas.
-- ---------------------------------------------------------------------------
with esperado(function_name, canonical_signature) as (
  values
    ('registrar_cancelamento', 'public.registrar_cancelamento(uuid,text,text)'),
    ('recalcular_pedido', 'public.recalcular_pedido(uuid)'),
    ('create_my_partner_owner_registration',
     'public.create_my_partner_owner_registration(text,text,text,text,text,text,text)')
),
resolvidas as (
  select e.function_name, to_regprocedure(e.canonical_signature) as oid
  from esperado e
)
select
  r.function_name,
  r.oid,
  'ACL_DIRETA' as origem_do_problema,
  coalesce(gr.rolname, 'PUBLIC') as grantee_ainda_pode_executar
from resolvidas r
join pg_proc p on p.oid = r.oid
cross join lateral aclexplode(coalesce(p.proacl, acldefault('f', p.proowner)))
  a(grantor, grantee, privilege_type, is_grantable)
left join pg_roles gr on gr.oid = a.grantee
where r.oid is not null
  and a.privilege_type = 'EXECUTE'
  and coalesce(gr.rolname, 'PUBLIC') in ('PUBLIC', 'anon', 'authenticated')

union all

select
  r.function_name,
  r.oid,
  'PERMISSAO_EFETIVA' as origem_do_problema,
  'anon' as grantee_ainda_pode_executar
from resolvidas r
where r.oid is not null
  and has_function_privilege('anon', r.oid, 'EXECUTE')

union all

select
  r.function_name,
  r.oid,
  'PERMISSAO_EFETIVA' as origem_do_problema,
  'authenticated' as grantee_ainda_pode_executar
from resolvidas r
where r.oid is not null
  and has_function_privilege('authenticated', r.oid, 'EXECUTE');
-- Veredito: QUALQUER linha aqui = CONTENÇÃO INCOMPLETA (investigar antes de
-- liberar cadastro). O ideal é 0 linhas no total.

-- ---------------------------------------------------------------------------
-- 2) As definições das três funções CONTINUAM presentes (nada foi
--    dropado). Resultado esperado: 3 linhas, todas com corpo não-nulo.
-- ---------------------------------------------------------------------------
with esperado(function_name, canonical_signature) as (
  values
    ('registrar_cancelamento', 'public.registrar_cancelamento(uuid,text,text)'),
    ('recalcular_pedido', 'public.recalcular_pedido(uuid)'),
    ('create_my_partner_owner_registration',
     'public.create_my_partner_owner_registration(text,text,text,text,text,text,text)')
),
resolvidas as (
  select e.function_name, to_regprocedure(e.canonical_signature) as oid
  from esperado e
)
select
  r.function_name,
  r.oid,
  (r.oid is not null) as ainda_existe,
  (p.prosrc is not null and length(p.prosrc) > 0) as definicao_presente,
  p.prosecdef as is_security_definer
from resolvidas r
left join pg_proc p on p.oid = r.oid
order by r.function_name;
-- Veredito: precisa haver exatamente 3 linhas, todas com ainda_existe = true
-- e definicao_presente = true.

-- ---------------------------------------------------------------------------
-- 3) Nenhuma tabela relevante foi removida (contagem de objetos, não de
--    linhas — este pacote não mexeu em dados).
-- ---------------------------------------------------------------------------
select
  to_regclass('public.orders')                    is not null as orders_existe,
  to_regclass('public.order_items')                is not null as order_items_existe,
  to_regclass('public.products')                   is not null as products_existe,
  to_regclass('public.site_monthly_partners')      is not null as site_monthly_partners_existe,
  to_regclass('public.commercial_regions')         is not null as commercial_regions_existe,
  to_regclass('public.commercial_region_cities')   is not null as commercial_region_cities_existe,
  to_regclass('public.commercial_niches')          is not null as commercial_niches_existe,
  to_regclass('public.commercial_exclusivities')   is not null as commercial_exclusivities_existe,
  to_regclass('public.commercial_opportunities')   is not null as commercial_opportunities_existe;
-- Veredito: todas as colunas devem ser TRUE (nenhuma tabela sumiu).

-- ---------------------------------------------------------------------------
-- 4) As RPCs territoriais/comerciais somente-leitura continuam com os
--    MESMOS privilégios que tinham no preflight (não devem ter sido
--    tocadas por este pacote) — comparar por ACL e por permissão efetiva.
-- ---------------------------------------------------------------------------
select
  p.proname as function_name,
  p.oid,
  pg_get_function_identity_arguments(p.oid) as argument_signature,
  has_function_privilege('anon', p.oid, 'EXECUTE')          as anon_execute_efetivo,
  has_function_privilege('authenticated', p.oid, 'EXECUTE') as authenticated_execute_efetivo
from pg_proc p
join pg_namespace n on n.oid = p.pronamespace
where n.nspname = 'public'
  and p.proname in (
    'resolve_commercial_region',
    'get_current_commercial_formation',
    'is_site_admin'
  )
order by p.proname;
-- Veredito: comparar manualmente com a seção 12 do preflight — devem ser
-- idênticos (mesmos valores true/false, nada a mais nem a menos).

-- ---------------------------------------------------------------------------
-- 5) Nenhuma concessão ampla/inesperada nova nas três funções contidas —
--    lista completa de grantees restantes por ACL, usando OID exato.
-- ---------------------------------------------------------------------------
with esperado(function_name, canonical_signature) as (
  values
    ('registrar_cancelamento', 'public.registrar_cancelamento(uuid,text,text)'),
    ('recalcular_pedido', 'public.recalcular_pedido(uuid)'),
    ('create_my_partner_owner_registration',
     'public.create_my_partner_owner_registration(text,text,text,text,text,text,text)')
),
resolvidas as (
  select e.function_name, to_regprocedure(e.canonical_signature) as oid
  from esperado e
)
select
  r.function_name,
  r.oid,
  coalesce(gr.rolname, 'PUBLIC') as grantee,
  a.privilege_type
from resolvidas r
join pg_proc p on p.oid = r.oid
cross join lateral aclexplode(coalesce(p.proacl, acldefault('f', p.proowner)))
  a(grantor, grantee, privilege_type, is_grantable)
left join pg_roles gr on gr.oid = a.grantee
where r.oid is not null
order by r.function_name, grantee;
-- Veredito: comparar com a seção 4 do preflight — a única diferença
-- esperada é a AUSÊNCIA das linhas PUBLIC/anon/authenticated que existiam
-- antes. Qualquer role NOVA aparecendo aqui deve ser investigada.

-- ---------------------------------------------------------------------------
-- 6) service_role: relatar (não presumir) a permissão efetiva atual nas
--    três funções, para a documentação afirmar com precisão.
-- ---------------------------------------------------------------------------
with esperado(function_name, canonical_signature) as (
  values
    ('registrar_cancelamento', 'public.registrar_cancelamento(uuid,text,text)'),
    ('recalcular_pedido', 'public.recalcular_pedido(uuid)'),
    ('create_my_partner_owner_registration',
     'public.create_my_partner_owner_registration(text,text,text,text,text,text,text)')
),
resolvidas as (
  select e.function_name, to_regprocedure(e.canonical_signature) as oid
  from esperado e
)
select
  r.function_name,
  r.oid,
  exists (select 1 from pg_roles where rolname = 'service_role') as role_service_role_existe,
  case when exists (select 1 from pg_roles where rolname = 'service_role')
    then has_function_privilege('service_role', r.oid, 'EXECUTE')
    else null
  end as service_role_execute_efetivo
from resolvidas r
where r.oid is not null
order by r.function_name;
