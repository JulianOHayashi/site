#!/usr/bin/env python3
"""Gera, a partir de um banco LOCAL onde a migration 20261103120000 acabou de
ser aplicada, os dois scripts operacionais que dependem do que ela cria:

  supabase/ops/20261103_register_positions_segments_version.sql
      registra a versão 63 SÓ se o banco contiver exatamente o que o arquivo
      revisado cria (manifesto por função + objetos + catálogo);
  supabase/ops/20261104_fingerprint_diagnostico.sql
      somente SELECT: compara o banco com o manifesto e classifica cada
      diferença (para auditoria em staging).

Uso: PGPORT=5433 python3 scripts/db-test/gen-register-version.py <db>
O manifesto não depende de versão do PostgreSQL nem de search_path da sessão:
a consulta fixa search_path = pg_catalog (assinaturas sempre qualificadas).
JAMAIS aponte para um banco remoto.
"""
import hashlib, pathlib, re, subprocess, sys

ROOT = pathlib.Path(__file__).resolve().parents[2]
MIG = ROOT / "supabase/migrations/20261103120000_commercial_positions_segments.sql"
OUT_REG = ROOT / "supabase/ops/20261103_register_positions_segments_version.sql"
OUT_DIAG = ROOT / "supabase/ops/20261104_fingerprint_diagnostico.sql"
DB = sys.argv[1]

texto = MIG.read_bytes()
sha = hashlib.sha256(texto).hexdigest()
src = texto.decode("utf-8")
assert "\r" not in src, "migration deve ser LF"

nomes = sorted(set(re.findall(r"(?im)^CREATE (?:OR REPLACE )?FUNCTION public\.([a-z0-9_]+)\(", src)))
tabelas = sorted(set(re.findall(r"(?im)^CREATE TABLE public\.([a-z0-9_]+)", src)))
indices = sorted(set(re.findall(r"(?im)^CREATE (?:UNIQUE )?INDEX ([a-z0-9_]+)", src)))
gatilhos = sorted(set(re.findall(r"(?im)^CREATE TRIGGER ([a-z0-9_]+)", src)))
restricoes = sorted(set(re.findall(r"(?im)ADD CONSTRAINT ([a-z0-9_]+)", src)))

lista = ",".join(f"'{n}'" for n in nomes)
MANIF_SQL = f"""SELECT p.oid::pg_catalog.regprocedure::text AS assinatura,
       pg_catalog.md5(p.prosrc) AS md5_src,
       pg_catalog.md5(pg_catalog.regexp_replace(pg_catalog.regexp_replace(pg_catalog.replace(p.prosrc, pg_catalog.chr(13), ''), '--[^\\n]*', '', 'g'), '\\s+', '', 'g')) AS md5_norm,
       p.prosecdef::text AS secdef, p.provolatile::text AS volat,
       coalesce(pg_catalog.array_to_string(p.proconfig, ','), '') AS config, l.lanname AS lang
  FROM pg_catalog.pg_proc p
  JOIN pg_catalog.pg_namespace n ON n.oid = p.pronamespace
  JOIN pg_catalog.pg_language l ON l.oid = p.prolang
 WHERE n.nspname = 'public' AND p.proname IN ({lista})"""

def psql(sql):
    r = subprocess.run(["su", "postgres", "-c", f"psql -X -v ON_ERROR_STOP=1 -At -F '|' -d {DB} -f -"],
                       input=("SET search_path = pg_catalog;\n" + sql + " ORDER BY 1;\n").encode(),
                       capture_output=True, check=True)
    return [l.split("|") for l in r.stdout.decode().splitlines() if l and l != "SET"]

linhas = psql(MANIF_SQL)
assert len(linhas) >= len(nomes), (len(linhas), len(nomes))
q = lambda s: "'" + s.replace("'", "''") + "'"
manif_values = ",\n      ".join("(" + ", ".join(q(c) for c in l) + ")" for l in linhas)
manif_md5 = hashlib.md5("\n".join("|".join(l) for l in linhas).encode()).hexdigest()
obj_values = ",\n      ".join(
    [f"('tabela', {q(t)})" for t in tabelas] + [f"('indice', {q(i)})" for i in indices]
    + [f"('gatilho', {q(g)})" for g in gatilhos] + [f"('restricao', {q(c)})" for c in restricoes])
N = len(linhas)

COMPARA = f"""WITH esperado(assinatura, md5_src, md5_norm, secdef, volat, config, lang) AS (
    VALUES
      {manif_values}
), observado AS (
{MANIF_SQL}
), cmp AS (
  SELECT coalesce(e.assinatura, o.assinatura) AS assinatura,
         CASE
           WHEN o.assinatura IS NULL THEN 'ausente'
           WHEN e.assinatura IS NULL THEN 'inesperada'
           WHEN (o.secdef, o.volat, o.config, o.lang) IS DISTINCT FROM (e.secdef, e.volat, e.config, e.lang)
             THEN 'atributos(secdef=' || o.secdef || ',volat=' || o.volat || ',config=' || o.config || ',lang=' || o.lang || ')'
           WHEN o.md5_src = e.md5_src THEN 'ok'
           WHEN o.md5_norm = e.md5_norm AND pg_catalog.strpos(src.prosrc, pg_catalog.chr(13)) > 0
             THEN 'textual:CR(fim de linha CRLF no transporte)'
           WHEN o.md5_norm = e.md5_norm THEN 'textual:comentarios_ou_espacos'
           WHEN src.prosrc ~ ('[' || pg_catalog.chr(194) || pg_catalog.chr(195) || '][' || pg_catalog.chr(128) || '-' || pg_catalog.chr(191) || ']')
             THEN 'codificacao:acentuacao convertida duas vezes (client_encoding nao UTF8)'
           ELSE 'conteudo:corpo diferente do arquivo revisado'
         END AS classe
    FROM esperado e
    FULL JOIN observado o ON o.assinatura = e.assinatura
    LEFT JOIN LATERAL (SELECT p.prosrc FROM pg_catalog.pg_proc p
                        WHERE p.oid = pg_catalog.to_regprocedure(o.assinatura)) src ON true
), obj AS (
  SELECT x.tipo, x.nome,
         CASE x.tipo
           WHEN 'tabela' THEN pg_catalog.to_regclass('public.' || x.nome) IS NOT NULL
           WHEN 'indice' THEN pg_catalog.to_regclass('public.' || x.nome) IS NOT NULL
           WHEN 'gatilho' THEN EXISTS (SELECT 1 FROM pg_catalog.pg_trigger t WHERE t.tgname = x.nome AND NOT t.tgisinternal)
           ELSE EXISTS (SELECT 1 FROM pg_catalog.pg_constraint c WHERE c.conname = x.nome)
         END AS presente
    FROM (VALUES
      {obj_values}) AS x(tipo, nome)
)"""

CABEC = f"""-- Arquivo: supabase/migrations/20261103120000_commercial_positions_segments.sql
-- sha256 do arquivo revisado: {sha}
-- Manifesto: {N} funções (md5 do manifesto {manif_md5}), {len(tabelas)} tabelas,
-- {len(indices)} índices, {len(gatilhos)} gatilhos, {len(restricoes)} restrições.
-- Gerado por scripts/db-test/gen-register-version.py (não editar à mão)."""

REG = f"""-- ============================================================================
-- Registro da versão 20261103120000 (63ª) no histórico do CLI, DEPOIS de
-- aplicar a migration pelo conteúdo exato do arquivo, numa única execução.
--
-- Só grava se TUDO abaixo for verdade; senão aborta sem gravar nada:
--   1. histórico reconciliado: 62 linhas, hash c9924f10… e a versão ainda
--      não registrada;
--   2. cada uma das {N} funções que a migration cria está no banco com o
--      MESMO corpo (md5 de prosrc), SECURITY DEFINER, volatilidade,
--      search_path e linguagem do manifesto — e nenhuma a mais com esses
--      nomes. A comparação é por função, com assinatura canônica
--      (search_path fixo em pg_catalog), então não depende da versão do
--      PostgreSQL nem da sessão; a mensagem de erro diz QUAL função difere e
--      COMO (CR, comentários, codificação, conteúdo, atributos);
--   3. tabelas, índices, gatilhos e restrições da migration presentes;
--   4. catálogo: 6 posições ativas, 84 unidades, Calçados gravado em UTF-8,
--      calçados F/M inativos.
--
{CABEC}
-- ============================================================================
BEGIN;
SET LOCAL search_path = pg_catalog;
LOCK TABLE supabase_migrations.schema_migrations IN SHARE ROW EXCLUSIVE MODE;
DO $reg$
DECLARE v_n int; v_h text; v_dif text; v_ndif int; v_obj text;
BEGIN
  SELECT count(*), md5(string_agg(version || ':' || name, ',' ORDER BY version || ':' || name))
    INTO v_n, v_h FROM supabase_migrations.schema_migrations;
  IF v_n <> 62 OR v_h <> 'c9924f1092689753d1bdfb59670aa8c4' THEN
    RAISE EXCEPTION 'registro_abortado: historico nao esta no estado reconciliado (linhas=%, hash=%)', v_n, v_h;
  END IF;

  {COMPARA.replace(chr(10), chr(10) + '  ')}
  SELECT count(*) FILTER (WHERE classe <> 'ok'),
         string_agg(assinatura || ' => ' || classe, '; ' ORDER BY assinatura) FILTER (WHERE classe <> 'ok'),
         (SELECT string_agg(tipo || ':' || nome, ', ' ORDER BY tipo, nome) FROM obj WHERE NOT presente)
    INTO v_ndif, v_dif, v_obj
    FROM cmp;
  IF v_ndif > 0 THEN
    RAISE EXCEPTION 'registro_abortado: % funcao(oes) diferem do arquivo revisado: %', v_ndif, v_dif;
  END IF;
  IF v_obj IS NOT NULL THEN
    RAISE EXCEPTION 'registro_abortado: objetos da migration ausentes: %', v_obj;
  END IF;

  IF (SELECT count(*) FROM public.commercial_niches WHERE is_active) <> 6
  OR (SELECT sum(contracted_quantity) FROM public.commercial_niches WHERE is_active) <> 84
  OR (SELECT convert_to(display_name, 'UTF8') FROM public.commercial_niches WHERE code = 'footwear')
       IS DISTINCT FROM '\\x43616cc3a761646f73'::bytea
  OR EXISTS (SELECT 1 FROM public.commercial_niches
              WHERE code IN ('womens_footwear', 'mens_footwear') AND is_active) THEN
    RAISE EXCEPTION 'registro_abortado: catalogo de posicoes diferente do esperado';
  END IF;

  INSERT INTO supabase_migrations.schema_migrations (version, name, statements, created_by)
  VALUES ('20261103120000', 'commercial_positions_segments',
          ARRAY['-- aplicado pelo conteudo exato do arquivo do repositorio; sha256 {sha}; manifesto {N} funcoes md5 {manif_md5} verificado'],
          'etapa-b-publicacao-coordenada');

  IF (SELECT count(*) FROM supabase_migrations.schema_migrations) <> 63 THEN
    RAISE EXCEPTION 'registro_abortado: historico nao ficou com 63 versoes';
  END IF;
END $reg$;
COMMIT;
"""

DIAG = f"""-- ============================================================================
-- DIAGNÓSTICO SOMENTE LEITURA da migration 20261103120000.
-- Rodar num banco onde ela foi aplicada (ou dentro da transação do ensaio,
-- antes do ROLLBACK). Uma linha por função ou objeto que NÃO bate com o
-- arquivo revisado, com a classe da diferença; zero linhas = idêntico.
--
{CABEC}
-- ============================================================================
SET search_path = pg_catalog;
{COMPARA}
SELECT 'funcao' AS tipo, assinatura AS nome, classe FROM cmp WHERE classe <> 'ok'
UNION ALL
SELECT tipo, nome, 'ausente' FROM obj WHERE NOT presente
ORDER BY 1, 2;
"""

OUT_REG.write_text(REG)
OUT_DIAG.write_text(DIAG)
print("ok", N, "funcoes", "sha", sha, "manifesto", manif_md5,
      len(tabelas), len(indices), len(gatilhos), len(restricoes))
