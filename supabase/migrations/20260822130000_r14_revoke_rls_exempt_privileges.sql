-- ============================================================================
-- R14 — Menor privilégio: retirada dos privilégios ISENTOS DE RLS dos papéis
--       públicos (anon, authenticated).
--
-- ACHADO DE AUDITORIA (baseline canônica, verificado em campo)
-- ------------------------------------------------------------------
-- A baseline traz o padrão do Supabase:
--     GRANT ALL ON ALL TABLES IN SCHEMA public TO anon, authenticated;
--     ALTER DEFAULT PRIVILEGES ... GRANT ALL ON TABLES TO anon, authenticated;
--
-- Para SELECT/INSERT/UPDATE/DELETE isso é aceitável: RLS está habilitada em
-- todas as tabelas e foi verificada em campo — o papel anon enxerga 0 linhas
-- de orders/payments, seu UPDATE não altera nada e seu INSERT é recusado com
-- "new row violates row-level security policy".
--
-- TRUNCATE, porém, NÃO é submetido a RLS. Com o GRANT ALL, o papel anon podia
-- executar:
--     truncate public.orders cascade;   -- cascateia para invoices,
--                                       -- payments, order_items,
--                                       -- order_cancellations,
--                                       -- order_customization_files
--     truncate public.site_admins cascade;
-- e ambos foram PERMITIDOS no harness. TRIGGER e REFERENCES são igualmente
-- privilégios de esquema que nenhum cliente PostgREST precisa.
--
-- Alcance real: o PostgREST não expõe TRUNCATE, então não há rota HTTP direta
-- hoje. O privilégio se torna explorável por qualquer sink de SQL dinâmico,
-- função SECURITY INVOKER mal escrita ou conexão direta com o papel anon —
-- e viola menor privilégio de qualquer modo.
--
-- O QUE ESTA MIGRAÇÃO FAZ (e o que deliberadamente NÃO faz)
-- ------------------------------------------------------------------
-- FAZ.....: revoga TRUNCATE, TRIGGER e REFERENCES de anon e authenticated,
--           nas tabelas existentes e no padrão para tabelas futuras.
-- NÃO FAZ.: não mexe em SELECT/INSERT/UPDATE/DELETE — são mediados por RLS e
--           a vitrine pública legitimamente depende de parte deles. Alterá-los
--           é decisão de produto, não de auditoria.
-- NÃO FAZ.: não altera a baseline canônica (migração puramente aditiva).
-- NÃO FAZ.: não derruba schema legado.
--
-- PENDÊNCIA REGISTRADA (não resolvida aqui): o ALTER DEFAULT PRIVILEGES da
-- baseline continua concedendo ALL ON FUNCTIONS a anon, de modo que toda nova
-- função nasce executável por anon até que se faça REVOKE explícito. Todas as
-- funções M2 fazem esse REVOKE; a suíte 900 verifica isso por igualdade de
-- conjuntos. Inverter o padrão global é mudança de postura e fica para
-- decisão do responsável.
-- ============================================================================

DO $$
DECLARE
  r record;
BEGIN
  FOR r IN
    SELECT c.relname
      FROM pg_class c
      JOIN pg_namespace n ON n.oid = c.relnamespace
     WHERE n.nspname = 'public'
       AND c.relkind IN ('r', 'p')
  LOOP
    EXECUTE format(
      'REVOKE TRUNCATE, TRIGGER, REFERENCES ON TABLE public.%I FROM anon, authenticated',
      r.relname
    );
  END LOOP;
END $$;

-- Tabelas futuras criadas por postgres em public não nascem mais com esses
-- privilégios para os papéis públicos.
ALTER DEFAULT PRIVILEGES FOR ROLE postgres IN SCHEMA public
  REVOKE TRUNCATE, TRIGGER, REFERENCES ON TABLES FROM anon;
ALTER DEFAULT PRIVILEGES FOR ROLE postgres IN SCHEMA public
  REVOKE TRUNCATE, TRIGGER, REFERENCES ON TABLES FROM authenticated;
