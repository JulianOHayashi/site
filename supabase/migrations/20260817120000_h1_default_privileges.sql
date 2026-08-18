-- ===========================================================================
-- H1 — DEFAULT PRIVILEGES (primeira migration pós-baseline)
-- ===========================================================================
-- Objetivo: remover os grants automáticos que objetos FUTUROS criados por
-- `postgres` receberiam por `anon`, `authenticated` e `PUBLIC`, preservando
-- `postgres` e `service_role`.
--
-- Escopo deliberadamente restrito: este arquivo contém SOMENTE
-- ALTER DEFAULT PRIVILEGES. Ele não altera ACL de nenhum objeto histórico,
-- não toca P0/P0B, não altera a baseline e não cria/remove objetos.
--
-- Alvo: FOR ROLE postgres.
-- Justificativa medida no SiteDBFLOW real (auditoria read-only) e
-- reproduzida na reconstrução local da baseline:
--   29/29 tabelas públicas  owner = postgres
--   36/36 funções públicas  owner = postgres
--   0 sequences públicas
--   pg_default_acl: as três entradas problemáticas são FOR ROLE postgres
-- Nenhuma outra role é incluída — não há evidência que a justifique.
--
-- ---------------------------------------------------------------------------
-- POR QUE EXISTEM DUAS FORMAS DE INSTRUÇÃO AQUI
-- ---------------------------------------------------------------------------
-- Defaults per-schema são SOMADOS aos defaults globais; um REVOKE
-- per-schema não consegue subtrair um privilégio de origem global. O
-- EXECUTE embutido de PUBLIC sobre funções novas não pode, portanto, ser
-- removido por um ALTER DEFAULT PRIVILEGES limitado a IN SCHEMA — por isso
-- o H1 altera o default GLOBAL de FUNCTIONS para a role postgres.
--
-- Medido em PostgreSQL 16.14:
--   * com IN SCHEMA public REVOKE ... FROM PUBLIC  -> sem registro em
--     pg_default_acl; a função nova mantém `=X/` (PUBLIC) na proacl;
--   * sem IN SCHEMA (global)                       -> cria a linha global
--     (defaclnamespace = 0) `postgres=X/postgres`; a função nova nasce sem
--     `=X/` e `anon` deixa de executá-la.
--
-- Efeito combinado para uma função nova criada por postgres em public:
--   proacl = postgres=X/postgres, service_role=X/postgres
--
-- Consequência do alcance global: funções criadas por `postgres` em
-- QUALQUER schema deixam de conceder EXECUTE a PUBLIC automaticamente.
-- Objetos históricos não são afetados. Schemas gerenciados pelo Supabase
-- (auth, storage) têm funções de outros owners e seguem intactos; este
-- arquivo não altera defaults de storage.
--
-- Política que permanece obrigatória a partir do M1, mesmo com o default
-- global corrigido: toda função nova declara seus grants explicitamente na
-- própria migration que a cria —
--   REVOKE EXECUTE ON FUNCTION <fn> FROM PUBLIC;
--   GRANT  EXECUTE ON FUNCTION <fn> TO <roles necessárias>;
-- O default é rede de segurança, não substituto de intenção declarada.
-- ===========================================================================

-- TABLES (per-schema) --------------------------------------------------------
ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public"
  REVOKE ALL ON TABLES FROM "anon";
ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public"
  REVOKE ALL ON TABLES FROM "authenticated";

-- SEQUENCES (per-schema) -----------------------------------------------------
ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public"
  REVOKE ALL ON SEQUENCES FROM "anon";
ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public"
  REVOKE ALL ON SEQUENCES FROM "authenticated";

-- FUNCTIONS (per-schema) -----------------------------------------------------
-- Remove os grants nominais concedidos pela baseline no schema public.
ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public"
  REVOKE ALL ON FUNCTIONS FROM "anon";
ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public"
  REVOKE ALL ON FUNCTIONS FROM "authenticated";

-- FUNCTIONS (global) ---------------------------------------------------------
-- Remove o EXECUTE embutido de PUBLIC, inalcançável pela forma per-schema.
ALTER DEFAULT PRIVILEGES FOR ROLE "postgres"
  REVOKE EXECUTE ON FUNCTIONS FROM PUBLIC;
