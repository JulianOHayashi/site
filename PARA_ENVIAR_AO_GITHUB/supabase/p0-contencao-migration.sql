-- ============================================================================
-- p0-contencao-migration.sql
-- Pacote P0 — contenção de segurança. VERSÃO CORRIGIDA (revisão 2).
-- REVISAR ANTES DE EXECUTAR MANUALMENTE.
--
-- Revoga a execução pública/autenticada de três funções mutáveis:
--   1) public.registrar_cancelamento(uuid,text,text)   — risco P0 (auditoria)
--   2) public.recalcular_pedido(uuid)                  — risco P0 (auditoria)
--   3) public.create_my_partner_owner_registration(...) — RPC de cadastro
--      estruturalmente incompatível com o schema atual (referencia
--      site_partner_members, que a auditoria não encontrou remotamente)
--
-- Correção desta revisão: a pré-checagem e a assertiva final resolvem os
-- OIDs via to_regprocedure() com a assinatura CANÔNICA (só tipos, sem nomes
-- de parâmetro nem DEFAULT) — nunca comparam por texto livre nem por
-- proname isolado, para não misturar sobrecargas. Além da ACL (aclexplode),
-- a assertiva final verifica a PERMISSÃO EFETIVA com
-- has_function_privilege('anon', oid, 'EXECUTE') e o mesmo para
-- 'authenticated': só é considerada bem-sucedida se AMBAS as checagens
-- (ACL e efetiva) confirmarem ausência de acesso.
--
-- NÃO faz:
--   • DROP de função, tabela ou dado;
--   • CREATE OR REPLACE (a lógica das funções não muda, só o acesso);
--   • criação de tabela nova, temporária ou permanente;
--   • criação de site_partner_members ou de owner_user_id;
--   • qualquer tentativa de "consertar" a RPC antiga;
--   • alteração de RPCs públicas somente-leitura de território/formação;
--   • qualquer concessão ou revogação para service_role (não é tocada).
--
-- Cada REVOKE usa assinatura EXPLÍCITA (nunca "ALL FUNCTIONS IN SCHEMA").
--
-- Execução manual: SQL Editor do projeto SiteDBFLOW, DEPOIS de revisar o
-- resultado do preflight linha a linha. Transacional: qualquer falha aborta
-- tudo (nenhuma revogação parcial fica presa).
-- ============================================================================

begin;

-- ---------------------------------------------------------------------------
-- 0) Pré-checagem fail-closed: as três funções precisam existir com a
--    assinatura canônica exata. to_regprocedure() usa somente os TIPOS dos
--    parâmetros — nomes de parâmetro e DEFAULT não afetam a resolução, o
--    que evita o falso negativo que uma comparação textual teria. Sem isso,
--    a migration para aqui — nada é revogado às cegas.
-- ---------------------------------------------------------------------------
do $$
begin
  if to_regprocedure('public.registrar_cancelamento(uuid,text,text)') is null then
    raise exception
      'P0_CONTENCAO_ABORTADA: public.registrar_cancelamento(uuid,text,text) nao existe ou tem assinatura diferente da esperada. Confirme com o preflight antes de reexecutar.';
  end if;

  if to_regprocedure('public.recalcular_pedido(uuid)') is null then
    raise exception
      'P0_CONTENCAO_ABORTADA: public.recalcular_pedido(uuid) nao existe ou tem assinatura diferente da esperada. Confirme com o preflight antes de reexecutar.';
  end if;

  if to_regprocedure(
    'public.create_my_partner_owner_registration(text,text,text,text,text,text,text)'
  ) is null then
    raise exception
      'P0_CONTENCAO_ABORTADA: public.create_my_partner_owner_registration(text,text,text,text,text,text,text) nao existe ou tem assinatura diferente da esperada. Confirme com o preflight antes de reexecutar (a assinatura local pode ter divergido da remota).';
  end if;
end $$;

-- ---------------------------------------------------------------------------
-- 1) Revogações — assinatura explícita, sem wildcard, sem tocar no corpo.
--    As assinaturas abaixo resolvem exatamente aos OIDs já confirmados no
--    passo 0 (mesma assinatura canônica, portanto mesmo objeto).
-- ---------------------------------------------------------------------------
revoke execute on function public.registrar_cancelamento(uuid,text,text)
  from public, anon, authenticated;

revoke execute on function public.recalcular_pedido(uuid)
  from public, anon, authenticated;

revoke execute on function public.create_my_partner_owner_registration(
  text,text,text,text,text,text,text
) from public, anon, authenticated;

-- ---------------------------------------------------------------------------
-- 2) Assertiva final fail-closed: resolve os MESMOS OIDs de novo por
--    to_regprocedure() (assinatura canônica, nunca proname isolado) e
--    verifica DUAS coisas para cada função:
--      a) ACL direta: nenhuma entrada de EXECUTE para PUBLIC/anon/authenticated;
--      b) permissão EFETIVA: has_function_privilege() para 'anon' e
--         'authenticated' precisa retornar false (cobre herança de role,
--         que a ACL direta sozinha não comprova).
--    Se qualquer uma das duas falhar para qualquer função, a transação
--    INTEIRA é abortada — nada fica "meio revogado".
-- ---------------------------------------------------------------------------
do $$
declare
  v_problemas text[] := array[]::text[];
  v_alvo record;
  v_acl_leftover int;
begin
  for v_alvo in
    select * from (values
      ('registrar_cancelamento', to_regprocedure('public.registrar_cancelamento(uuid,text,text)')),
      ('recalcular_pedido', to_regprocedure('public.recalcular_pedido(uuid)')),
      ('create_my_partner_owner_registration',
       to_regprocedure('public.create_my_partner_owner_registration(text,text,text,text,text,text,text)'))
    ) as t(function_name, oid_alvo)
  loop

    -- (a) ACL direta remanescente para PUBLIC/anon/authenticated.
    select count(*) into v_acl_leftover
    from aclexplode(
      coalesce(
        (select proacl from pg_proc where oid = v_alvo.oid_alvo),
        acldefault('f', (select proowner from pg_proc where oid = v_alvo.oid_alvo))
      )
    ) a(grantor, grantee, privilege_type, is_grantable)
    left join pg_roles gr on gr.oid = a.grantee
    where a.privilege_type = 'EXECUTE'
      and coalesce(gr.rolname, 'PUBLIC') in ('PUBLIC', 'anon', 'authenticated');

    if v_acl_leftover > 0 then
      v_problemas := array_append(v_problemas,
        format('%s (oid %s): %s entrada(s) de ACL ainda concedem EXECUTE a PUBLIC/anon/authenticated',
               v_alvo.function_name, v_alvo.oid_alvo, v_acl_leftover));
    end if;

    -- (b) Permissão efetiva — cobre herança de role, não só ACL direta.
    if has_function_privilege('anon', v_alvo.oid_alvo, 'EXECUTE') then
      v_problemas := array_append(v_problemas,
        format('%s (oid %s): anon AINDA TEM permissão efetiva de EXECUTE', v_alvo.function_name, v_alvo.oid_alvo));
    end if;

    if has_function_privilege('authenticated', v_alvo.oid_alvo, 'EXECUTE') then
      v_problemas := array_append(v_problemas,
        format('%s (oid %s): authenticated AINDA TEM permissão efetiva de EXECUTE', v_alvo.function_name, v_alvo.oid_alvo));
    end if;

  end loop;

  if array_length(v_problemas, 1) is not null then
    raise exception 'P0_CONTENCAO_FALHOU: %', array_to_string(v_problemas, ' | ');
  end if;
end $$;

commit;

-- ============================================================================
-- Nada foi apagado. As três funções continuam existindo com sua definição
-- original — apenas deixaram de ser executáveis por PUBLIC/anon/authenticated.
--
-- service_role NÃO foi tocada por este REVOKE (a lista de roles do REVOKE é
-- só "public, anon, authenticated"). Se service_role ainda conseguir
-- executar essas funções depois desta migration, isso é esperado e NÃO deve
-- ser presumido sem checar: rode a seção 11 do preflight (ou a seção 6 da
-- verificação posterior), ambas com has_function_privilege('service_role',
-- oid, 'EXECUTE'), e reporte o resultado REAL — nunca declare que
-- "service_role continuará executando" sem essa confirmação.
-- ============================================================================
