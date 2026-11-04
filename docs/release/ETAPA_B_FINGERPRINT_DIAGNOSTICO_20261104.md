# Etapa B — divergência da impressão digital do registro (auditoria de 2026-11-04)

## Relato

Ensaio independente em PostgreSQL 17.6 (staging) com o arquivo exato da
revisão `69802e8` (blob `2d9fd44f…`, sha256 `3a6436a3…`): a migration aplicou,
mas o registro da versão calculou `6e3e7bab1420d99db8ddc8c7642215b6/28` em vez
de `33d122ef4ed5c0af806c9d27f61ba7fb/28` e recusou. A transação foi revertida.

## O que o mecanismo antigo media

Um único md5 sobre as 28 funções:
`regprocedure::text : md5(prosrc) : prosecdef : provolatile : proconfig`.

## Reprodução (PostgreSQL 17.6 real, mesmos binários de versão do staging)

Mesmo arquivo `3a6436a3…`, estado de Production montado do zero, 20
combinações medidas:

| Transporte do arquivo | search_path da sessão do registro | Impressão |
|---|---|---|
| UTF-8, LF (`psql -f` ou consulta única) | `public` / `"$user", public, extensions` / `pg_temp, public` | `33d122ef…` (= esperado) |
| UTF-8, LF | `''` / `pg_catalog` / `extensions` | `a65b1431…` |
| client_encoding LATIN1 | `public` | `c1bc989d…` (e grava "CalÃ§ados") |
| client_encoding LATIN1 | `''` | `9e8eccbd…` |
| CRLF | `public` | `f872abfd…` |
| CRLF | `''` | `33e08343…` |
| CRLF + LATIN1 | `public` / `''` | `0955474d…` / `eb5a0960…` |
| BOM | `public` | `33d122ef…` |
| primeira versão do arquivo (`8dfad66c…`) | `public` / `''` | `33d122ef…` / `a65b1431…` |
| PostgreSQL 16.15 | `public` | `33d122ef…` |

## Causa

1. **Defeito comprovado — dependência de ambiente.** `regprocedure::text`
   qualifica o nome de um tipo quando o schema dele não está no search_path
   da sessão. `cci_resposta_intencao(commercial_checkout_intents, boolean)`
   recebe um tipo de linha de `public`. Sem `public` no caminho, a assinatura
   vira `cci_resposta_intencao(public.commercial_checkout_intents,boolean)` e
   o hash muda (`a65b1431…`). A impressão dependia da sessão, não só do banco.
2. **Sensibilidade comprovada ao transporte.** CRLF e client_encoding
   diferente de UTF-8 mudam os bytes dos corpos (`prosrc`) e, portanto, a
   impressão. Com LATIN1, a migration "dá certo" e grava texto corrompido.
3. **Não é a versão do PostgreSQL.** PG16.15 e PG17.6 dão o mesmo valor, e o
   manifesto novo gerado nos dois motores é byte a byte idêntico.
4. **Não é diferença funcional da migration.** Todas as 28 entradas são
   recriadas pela própria migration (conferido assinatura por assinatura).
   O estado de partida não interfere.

O valor exato do staging (`6e3e7bab…`) **não foi reproduzido** em nenhuma
das 20 combinações. Ele exige, além dos fatores acima, alguma diferença nos
bytes de pelo menos uma função no staging, que não dá para ver daqui (o
staging não está acessível a esta sessão). Por isso o mecanismo novo deixou
de ser um hash único: ele **nomeia** a função e a classe da diferença. Para
fechar o caso no staging, basta aplicar a migration numa transação, rodar
`supabase/ops/20261104_fingerprint_diagnostico.sql` (só SELECT) antes do
ROLLBACK e ler as linhas devolvidas.

## Correção

- **Manifesto por função** (gerado por `scripts/db-test/gen-register-version.py`
  a partir de um banco descartável migrado): assinatura canônica com
  `search_path = pg_catalog` fixo dentro da transação (sempre qualificada,
  independente da sessão), md5 do corpo, md5 normalizado, SECURITY DEFINER,
  volatilidade, configuração e linguagem. Mais 2 tabelas, 6 índices, 8
  gatilhos, 21 restrições e o catálogo (6/84, "Calçados" em bytes UTF-8,
  calçados F/M inativos).
- **Classificação da diferença:** `ausente`, `inesperada`, `atributos(...)`,
  `textual:CR`, `textual:comentarios_ou_espacos`, `codificacao:...`,
  `conteudo:...`. Qualquer classe diferente de `ok` recusa o registro.
- **Integridade do transporte na própria migration (seção Z):** aborta tudo
  se "Calçados" não estiver gravado em UTF-8 ou se corpos tiverem CR ou
  acentuação convertida duas vezes. Os literais da verificação são ASCII.
- **Registro só no fim:** histórico reconciliado (62, `c9924f10…`), manifesto,
  objetos e catálogo, depois o INSERT e a pós-condição de 63 linhas, tudo
  numa transação.

## Evidência do mecanismo novo

`scripts/db-test/register-version-check.sh`, **17/17 em PG17.6 e em PG16.15**:
aceita a migration correta (psql -f e consulta única; search_path de sessão
vazio, `extensions`, `public`; 63 versões no fim). Recusa sem gravar:
- histórico não reconciliado;
- corpo alterado (nomeia `list_commercial_segments() => conteudo`);
- atributo alterado;
- sobrecarga extra;
- índice ausente;
- migration que falhou (D2);
- CRLF;
- LATIN1.
