-- ============================================================================
-- APOSENTADORIA EXPLÍCITA DA RPC LEGADA DE CADASTRO DE OWNER
--
-- EVIDÊNCIA QUE ORIGINOU ESTA MIGRATION
-- O `supabase db lint --linked --schema public --level error` no projeto de
-- staging real devolveu exatamente um erro:
--
--   public.create_my_partner_owner_registration referencia a relação
--   public.site_partner_members, que não existe.
--
-- DIAGNÓSTICO
-- Não é defeito da Comercial V2. A função vem da baseline histórica
-- 20260814115600_baseline_sitedbflow.sql e lê/escreve em
-- public.site_partner_members — tabela que o schema canônico do M1
-- deliberadamente NÃO possui, e cuja ausência a suíte 000 afirma como
-- invariante. O caminho está morto desde o M1: a interface de cadastro de
-- parceiro usa o domínio canônico de candidatura, e nenhuma role de API pode
-- executar esta função.
--
-- Ou seja: um corpo inválido sobrevivia sem ser notado porque ninguém o
-- alcançava. O lint hospedado enxerga o texto da função, não o alcance dela —
-- e está certo em reclamar. Uma referência pendente a uma tabela inexistente
-- é dívida que só piora com o tempo.
--
-- O QUE ESTA MIGRATION FAZ, E O QUE NÃO FAZ
-- Substitui o corpo por uma falha fechada determinística. Não restaura
-- site_partner_members, não cria fluxo de cadastro novo, não devolve sucesso
-- silencioso e não fabrica identificador de parceiro ou de membro.
--
-- POR QUE SUBSTITUIR EM VEZ DE REMOVER (DROP)
-- A assinatura de sete argumentos é verificada como PRESENTE E INTACTA pelos
-- pré-flights históricos do projeto (supabase/fase2a-marco1-preflight.sql).
-- Derrubar a função quebraria essa verificação e apagaria a evidência de que
-- o caminho existiu e foi aposentado de propósito. Aposentar é mais honesto
-- que sumir: quem chamar recebe um erro que explica o estado do sistema.
--
-- ADITIVA. Nenhuma das 28 migrations anteriores é editada.
-- ============================================================================

-- ----------------------------------------------------------------------------
-- 1. Corpo aposentado — falha fechada, sem tocar em tabela alguma
--
-- Os nomes e a ordem dos parâmetros são preservados na íntegra: CREATE OR
-- REPLACE recusa renomear parâmetro de entrada, e a assinatura é justamente
-- o que os pré-flights conferem. O DEFAULT de p_company_phone permanece.
--
-- search_path passa de 'public' para 'pg_catalog', o padrão endurecido do
-- projeto. É seguro precisamente porque o corpo não resolve nome algum de
-- aplicação: ele levanta exceção antes de qualquer acesso.
-- ----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.create_my_partner_owner_registration(
  p_full_name     text,
  p_cpf           text,
  p_phone         text,
  p_legal_name    text,
  p_trade_name    text,
  p_cnpj          text,
  p_company_phone text DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql VOLATILE SECURITY DEFINER
SET search_path TO 'pg_catalog'
AS $$
BEGIN
  -- Erro determinístico e imediato. Nenhuma leitura, nenhuma escrita,
  -- nenhuma consulta à identidade do chamador, nenhum dado de entrada
  -- ecoado de volta. O corpo inteiro cabe nesta exceção de propósito: a
  -- asserção canônica varre prosrc, e um token de tabela ou de identidade
  -- citado aqui — ainda que só em comentário — reprova, como deve.
  RAISE EXCEPTION 'RPC_LEGADA_DESATIVADA'
    USING ERRCODE = '0A000',
          DETAIL  = 'create_my_partner_owner_registration foi aposentada no M1.',
          HINT    = 'Use o dominio canonico de candidatura de parceiro.';
END;
$$;

COMMENT ON FUNCTION public.create_my_partner_owner_registration(
  text, text, text, text, text, text, text) IS
  'APOSENTADA no M1. Assinatura preservada para os pre-flights historicos; '
  'o corpo falha fechado com RPC_LEGADA_DESATIVADA (SQLSTATE 0A000) e nao '
  'acessa tabela alguma. A implementacao original dependia de '
  'public.site_partner_members, que o schema canonico nao possui e que NAO '
  'deve ser restaurada. O cadastro de parceiro ocorre pelo dominio canonico '
  'de candidatura.';

-- ----------------------------------------------------------------------------
-- 2. Privilégios — reafirmados, jamais alargados
--
-- CREATE OR REPLACE preserva a ACL existente; estes comandos apenas tornam a
-- intenção explícita no próprio arquivo que altera a função, como a política
-- do projeto exige. Nada é concedido aqui que já não valesse antes:
--   - PUBLIC, anon e authenticated seguem SEM EXECUTE (a suíte 000 afirma
--     isso como invariante canônica);
--   - service_role mantém o EXECUTE que a baseline concedeu. Revogá-lo seria
--     mudança de contrato sem defeito que a justifique, e é justamente por
--     esse caminho administrativo que a falha fechada pode ser provada.
-- ----------------------------------------------------------------------------
REVOKE EXECUTE ON FUNCTION public.create_my_partner_owner_registration(
  text, text, text, text, text, text, text) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.create_my_partner_owner_registration(
  text, text, text, text, text, text, text) FROM anon;
REVOKE EXECUTE ON FUNCTION public.create_my_partner_owner_registration(
  text, text, text, text, text, text, text) FROM authenticated;
GRANT  EXECUTE ON FUNCTION public.create_my_partner_owner_registration(
  text, text, text, text, text, text, text) TO service_role;
