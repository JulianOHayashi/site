-- ============================================================================
-- p0-contencao-preflight.sql   (SOMENTE LEITURA — não altera nada)
--
-- Pacote P0 — contenção de segurança. VERSÃO CORRIGIDA (revisão 2).
--
-- Correções desta revisão:
--   1) A comparação de assinatura NÃO usa mais texto livre com nomes de
--      parâmetro / DEFAULT. Usa to_regprocedure() com assinatura canônica
--      (só tipos, separados por vírgula, sem espaço) e compara por OID.
--   2) Além da ACL (aclexplode), verifica permissão EFETIVA com
--      has_function_privilege('anon', oid, 'EXECUTE') e o mesmo para
--      'authenticated' — usando o OID exato resolvido, nunca por nome
--      (evita confundir sobrecargas).
--   3) Acrescenta pg_get_functiondef() (definição completa), pg_depend
--      (dependências formais) e pg_trigger (gatilhos associados), além de
--      uma busca heurística por chamadas dentro de outras funções.
--
-- Este preflight NÃO confia no código-fonte local para saber o que existe
-- no banco: a auditoria de 2026-08-03 encontrou ZERO migrations registradas
-- em supabase_migrations, e comprovou que o schema remoto já divergiu do
-- que está versionado no repositório (ex.: a RPC local de cadastro referencia
-- `site_partner_members`, tabela que a auditoria não encontrou remotamente;
-- e `registrar_cancelamento`, alvo desta contenção, não existe em NENHUM
-- arquivo .sql local — só foi observada ao vivo pela auditoria).
--
-- NÃO cria, NÃO altera, NÃO concede, NÃO revoga nada. Somente SELECT.
-- ============================================================================

-- ---------------------------------------------------------------------------
-- 0) Assinaturas canônicas esperadas (referência única, reaproveitada nas
--    seções seguintes). Tipos apenas — sem nomes de parâmetro, sem DEFAULT.
-- ---------------------------------------------------------------------------
-- public.registrar_cancelamento(uuid,text,text)
-- public.recalcular_pedido(uuid)
-- public.create_my_partner_owner_registration(text,text,text,text,text,text,text)

-- ---------------------------------------------------------------------------
-- 1) Resolução por OID via to_regprocedure() — ÚNICA fonte de verdade para
--    "a assinatura confere". to_regprocedure() usa apenas os TIPOS dos
--    parâmetros (posicional), então nomes de parâmetro e DEFAULT não afetam
--    o resultado — corrige o falso ASSINATURA_DIVERGENTE do preflight
--    anterior para create_my_partner_owner_registration.
-- ---------------------------------------------------------------------------
with esperado(function_name, canonical_signature) as (
  values
    ('registrar_cancelamento', 'public.registrar_cancelamento(uuid,text,text)'),
    ('recalcular_pedido', 'public.recalcular_pedido(uuid)'),
    ('create_my_partner_owner_registration',
     'public.create_my_partner_owner_registration(text,text,text,text,text,text,text)')
)
select
  e.function_name,
  e.canonical_signature,
  to_regprocedure(e.canonical_signature) as resolved_oid,
  case
    when to_regprocedure(e.canonical_signature) is null then 'AUSENTE_NO_BANCO'
    else 'ASSINATURA_CONFERE'
  end as veredito
from esperado e
order by e.function_name;

-- ---------------------------------------------------------------------------
-- 2) Detalhe completo de cada função resolvida no passo 1: identidade
--    (pg_get_function_identity_arguments — sem defaults) E argumentos
--    completos com DEFAULT (pg_get_function_arguments — para leitura
--    humana, nunca para comparação), retorno, SECURITY DEFINER,
--    volatilidade, dono, search_path fixo.
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
  n.nspname as schema,
  p.proname as db_function_name,
  pg_get_function_identity_arguments(p.oid) as identity_arguments_sem_default,
  pg_get_function_arguments(p.oid)          as full_arguments_com_default,
  pg_get_function_result(p.oid)             as return_type,
  p.prosecdef                               as is_security_definer,
  p.provolatile                             as volatility,
  pg_get_userbyid(p.proowner)               as owner,
  p.proconfig                               as proconfig_settings
from resolvidas r
join pg_proc p on p.oid = r.oid
join pg_namespace n on n.oid = p.pronamespace
where r.oid is not null
order by r.function_name;

-- ---------------------------------------------------------------------------
-- 3) Sobrecargas DIVERGENTES: qualquer função com o MESMO NOME que NÃO seja
--    o OID resolvido no passo 1. Listadas SEPARADAMENTE — nunca confundidas
--    com a assinatura esperada. Resultado esperado: 0 linhas (indica que não
--    há sobrecarga concorrente enganosa).
-- ---------------------------------------------------------------------------
with esperado(function_name, canonical_signature) as (
  values
    ('registrar_cancelamento', 'public.registrar_cancelamento(uuid,text,text)'),
    ('recalcular_pedido', 'public.recalcular_pedido(uuid)'),
    ('create_my_partner_owner_registration',
     'public.create_my_partner_owner_registration(text,text,text,text,text,text,text)')
),
resolvidas as (
  select e.function_name, to_regprocedure(e.canonical_signature) as oid_esperado
  from esperado e
)
select
  r.function_name as nome_esperado,
  p.oid as oid_encontrado,
  pg_get_function_identity_arguments(p.oid) as assinatura_desta_sobrecarga,
  'SOBRECARGA_DIVERGENTE_DO_ESPERADO' as observacao
from resolvidas r
join pg_proc p
  on p.proname = r.function_name
 and p.pronamespace = 'public'::regnamespace
where r.oid_esperado is distinct from p.oid
order by r.function_name, p.oid;

-- ---------------------------------------------------------------------------
-- 4) ACL bruta (aclexplode) — concessões diretas por role, usando o OID
--    exato resolvido (nunca por nome, para não misturar sobrecargas).
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
  p.oid,
  coalesce(gr.rolname, 'PUBLIC') as grantee_name,
  a.privilege_type
from resolvidas r
join pg_proc p on p.oid = r.oid
cross join lateral aclexplode(coalesce(p.proacl, acldefault('f', p.proowner)))
  a(grantor, grantee, privilege_type, is_grantable)
left join pg_roles gr on gr.oid = a.grantee
where r.oid is not null
  and a.privilege_type = 'EXECUTE'
order by r.function_name, grantee_name;

-- ---------------------------------------------------------------------------
-- 5) PERMISSÃO EFETIVA (não apenas ACL direta) — has_function_privilege()
--    para 'anon' e 'authenticated', usando o OID exato. Esta é a checagem
--    que a migration deve usar na assertiva final: uma role pode ter
--    EXECUTE efetivo por herança de outra role, mesmo sem ACL direta —
--    aclexplode() sozinho não comprova isso.
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
  has_function_privilege('anon', r.oid, 'EXECUTE')          as anon_pode_executar_efetivamente,
  has_function_privilege('authenticated', r.oid, 'EXECUTE') as authenticated_pode_executar_efetivamente,
  has_function_privilege('public', r.oid, 'EXECUTE')        as public_role_pode_executar_efetivamente
from resolvidas r
where r.oid is not null
order by r.function_name;
-- Veredito: qualquer coluna "true" aqui indica que o REVOKE ainda precisa
-- ser aplicado (ou que a revogação anterior não foi suficiente).

-- ---------------------------------------------------------------------------
-- 6) Definição completa das três funções-alvo (pg_get_functiondef) — para
--    revisão humana do corpo antes de decidir a contenção. Não é alterada
--    por este pacote; é só leitura.
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
  pg_get_functiondef(r.oid) as definicao_completa
from resolvidas r
where r.oid is not null
order by r.function_name;

-- ---------------------------------------------------------------------------
-- 7) Dependências formais (pg_depend) das três funções-alvo — objetos dos
--    quais a função depende (tipos, extensões) e objetos que dependem dela
--    (ex.: um trigger cuja tgfoid aponta para a função, capturado também na
--    seção 8 de forma mais legível).
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
  d.classid::regclass as tipo_objeto_dependente,
  d.objid,
  d.refclassid::regclass as tipo_objeto_referenciado,
  d.refobjid,
  d.deptype
from resolvidas r
join pg_depend d
  on (d.objid = r.oid and d.classid = 'pg_proc'::regclass)
  or (d.refobjid = r.oid and d.refclassid = 'pg_proc'::regclass)
where r.oid is not null
order by r.function_name;
-- Nota: pg_depend NÃO registra chamadas feitas dentro do corpo PL/pgSQL de
-- outra função (isso não é uma dependência formal do catálogo). A seção 9
-- faz uma busca heurística por texto para cobrir esse caso.

-- ---------------------------------------------------------------------------
-- 8) Gatilhos (pg_trigger) associados às três funções-alvo, se houver.
--    Nenhuma delas deveria aparecer aqui (nenhuma é trigger function),
--    mas a checagem é explícita para não presumir isso sem confirmar.
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
  t.tgname as trigger_name,
  t.tgrelid::regclass as tabela,
  t.tgenabled
from resolvidas r
join pg_trigger t on t.tgfoid = r.oid
where r.oid is not null
order by r.function_name;
-- Resultado esperado: 0 linhas (nenhuma das três é usada como gatilho).

-- ---------------------------------------------------------------------------
-- 9) Busca heurística: outras funções do schema public cujo CORPO (prosrc)
--    menciona textualmente o nome de uma das três funções-alvo — candidato
--    a chamador indireto. É uma heurística de texto, não uma prova formal
--    de dependência (pg_depend não cobre chamadas dentro de PL/pgSQL).
--    Nenhuma função aqui é alterada; é só levantamento para revisão.
-- ---------------------------------------------------------------------------
with esperado(function_name) as (
  values ('registrar_cancelamento'), ('recalcular_pedido'),
         ('create_my_partner_owner_registration')
)
select
  e.function_name as funcao_alvo_mencionada,
  n.nspname as schema,
  p.proname as funcao_que_menciona,
  pg_get_function_identity_arguments(p.oid) as assinatura_de_quem_menciona
from esperado e
join pg_proc p
  on p.prosrc ilike '%' || e.function_name || '%'
join pg_namespace n on n.oid = p.pronamespace
where n.nspname = 'public'
  and p.proname <> e.function_name  -- exclui a própria função-alvo
order by e.function_name, p.proname;

-- ---------------------------------------------------------------------------
-- 10) Inventário de OUTRAS funções candidatas a legado mutável exposto:
--     SECURITY DEFINER, retorno diferente de 'trigger' (chamável
--     diretamente, não apenas via gatilho), com EXECUTE concedido a
--     PUBLIC/anon/authenticated — verificado por ACL E por permissão
--     efetiva (has_function_privilege). Inclui definição completa e
--     gatilhos associados (se houver) de cada candidata para a revisão.
--     Cobre também funções sem fonte local (ex.: verificar_cascata,
--     status_fidelidade, unidades_pagas_cnpj) — se existirem no banco,
--     aparecem aqui mesmo sem estarem versionadas.
-- ---------------------------------------------------------------------------
select
  n.nspname as schema,
  p.proname as function_name,
  p.oid,
  pg_get_function_identity_arguments(p.oid) as argument_signature,
  pg_get_function_result(p.oid) as return_type,
  p.prosecdef as is_security_definer,
  p.provolatile as volatility,
  has_function_privilege('anon', p.oid, 'EXECUTE')          as anon_execute_efetivo,
  has_function_privilege('authenticated', p.oid, 'EXECUTE') as authenticated_execute_efetivo,
  (select count(*) from pg_trigger t where t.tgfoid = p.oid) as qtd_gatilhos_associados,
  pg_get_functiondef(p.oid) as definicao_completa
from pg_proc p
join pg_namespace n on n.oid = p.pronamespace
where n.nspname = 'public'
  and p.prosecdef = true                          -- SECURITY DEFINER
  and pg_get_function_result(p.oid) <> 'trigger'   -- chamável diretamente
  and p.proname not in (
    'registrar_cancelamento', 'recalcular_pedido', 'create_my_partner_owner_registration'
  )
  and (
    has_function_privilege('anon', p.oid, 'EXECUTE')
    or has_function_privilege('authenticated', p.oid, 'EXECUTE')
    or exists (
      select 1
      from aclexplode(coalesce(p.proacl, acldefault('f', p.proowner))) a(grantor, grantee, privilege_type, is_grantable)
      where a.privilege_type = 'EXECUTE' and a.grantee = 0  -- grantee 0 = PUBLIC
    )
  )
order by p.proname;

-- ---------------------------------------------------------------------------
-- 11) service_role: permissão efetiva de EXECUTE nas três funções-alvo.
--     Apenas REPORTA — este pacote NÃO concede nem revoga nada de
--     service_role. Serve para a documentação afirmar com precisão se
--     service_role continua podendo executar (em vez de presumir).
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
  -- só avalia se a role 'service_role' existir neste projeto; caso não
  -- exista, retorna NULL em vez de lançar erro.
  case when exists (select 1 from pg_roles where rolname = 'service_role')
    then has_function_privilege('service_role', r.oid, 'EXECUTE')
    else null
  end as service_role_execute_efetivo,
  exists (select 1 from pg_roles where rolname = 'service_role') as role_service_role_existe
from resolvidas r
where r.oid is not null
order by r.function_name;

-- ---------------------------------------------------------------------------
-- 12) Baseline das RPCs territoriais/comerciais somente-leitura que este
--     pacote NÃO deve tocar — para comparar com a verificação posterior.
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
