#!/usr/bin/env bash
# ============================================================================
# P0-2 — ALOCAÇÃO CONCORRENTE DO SERIAL DO INSTRUMENTO
#
# Por que fora das suítes: o harness SQL roda uma única sessão psql e não pode
# provar nada sobre concorrência. A suíte 260 prova unicidade e monotonicidade
# numa rajada sequencial; o que SÓ este script prova é que várias sessões
# simultâneas nunca recebem o mesmo número.
#
# O que se exige, conforme a decisão do operador:
#   - unicidade;
#   - alocação monotônica;
#   - nenhum reuso de número de instrumento comprometido;
#   - segurança sob concorrência.
# Lacuna NÃO é defeito: transação revertida pode consumir o candidato. A fonte
# congelada não exige ausência de lacunas, e tratá-la como requisito legal
# forçaria serialização global da contratação.
#
# JAMAIS aponte este script para um banco remoto.
# ============================================================================
set -uo pipefail

DB_NAME="${BDFLOW_LOCAL_DB:-bdflow_recon_local}"
SESSOES="${P02_SESSOES:-8}"
POR_SESSAO="${P02_POR_SESSAO:-60}"
REPO_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$REPO_ROOT"

WORK="$(mktemp -d /var/tmp/p02-serial.XXXXXX)"
chmod 755 "$WORK"
trap 'rm -rf "$WORK"' EXIT

q() { su postgres -c "psql -q -d $DB_NAME -At -c \"$1\""; }

if [ -z "$(q "select 1 from pg_class where relname='commercial_instrument_serial' and relkind='S';")" ]; then
  echo "P02_SERIAL=FAIL (sequence commercial_instrument_serial ausente)"
  exit 1
fi

# Tabela de coleta: cada sessão grava os códigos que recebeu.
q "drop table if exists public._p02_serial_colheita;" >/dev/null 2>&1
q "create unlogged table public._p02_serial_colheita (sessao int, codigo text);" >/dev/null

cat > "$WORK/aloca.sql" <<SQL
insert into public._p02_serial_colheita (sessao, codigo)
select :sessao, public.commercial_next_instrument_code()
  from generate_series(1, $POR_SESSAO);
SQL
chmod 644 "$WORK/aloca.sql"

echo "== $SESSOES sessoes simultaneas, $POR_SESSAO alocacoes cada =="
for i in $(seq 1 "$SESSOES"); do
  su postgres -c "psql -q -d $DB_NAME -At -v sessao=$i -f $WORK/aloca.sql" >/dev/null 2>&1 &
done
wait

TOTAL="$(q "select count(*) from public._p02_serial_colheita;")"
DISTINTOS="$(q "select count(distinct codigo) from public._p02_serial_colheita;")"
FORMATO_RUIM="$(q "select count(*) from public._p02_serial_colheita where codigo !~ '^SF-[0-9]{4,}\$';")"
ESPERADO=$(( SESSOES * POR_SESSAO ))

falhas=0
echo "alocados=$TOTAL distintos=$DISTINTOS esperado=$ESPERADO formato_invalido=$FORMATO_RUIM"

if [ "$TOTAL" = "$ESPERADO" ] && [ "$DISTINTOS" = "$ESPERADO" ]; then
  echo "  PASS  unicidade sob concorrencia: nenhum numero repetido"
else
  echo "  FAIL  houve numero repetido ou alocacao perdida sob concorrencia"
  q "select codigo, count(*) from public._p02_serial_colheita
      group by codigo having count(*) > 1 limit 5;"
  falhas=$((falhas+1))
fi

if [ "$FORMATO_RUIM" = "0" ]; then
  echo "  PASS  todo codigo respeita SF- com ao menos quatro digitos"
else
  echo "  FAIL  codigo fora do formato exigido"
  falhas=$((falhas+1))
fi

# Monotonicidade global: o conjunto alocado e um intervalo contiguo de inteiros,
# porque nenhuma transacao foi revertida nesta corrida.
CONTIGUO="$(q "select case when max(n) - min(n) + 1 = count(*) then 'sim' else 'nao' end
                 from (select substring(codigo from 4)::bigint as n
                         from public._p02_serial_colheita) t;")"
if [ "$CONTIGUO" = "sim" ]; then
  echo "  PASS  alocacao monotonica, sem numero perdido nesta corrida"
else
  echo "  FAIL  alocacao nao monotonica"
  falhas=$((falhas+1))
fi

# Nenhum reuso: um numero ja comprometido nunca volta, mesmo apos rollback.
ANTES="$(q "select substring(public.commercial_next_instrument_code() from 4)::bigint;")"
q "begin; select public.commercial_next_instrument_code(); rollback;" >/dev/null 2>&1
DEPOIS="$(q "select substring(public.commercial_next_instrument_code() from 4)::bigint;")"
if [ "$DEPOIS" -gt "$ANTES" ]; then
  echo "  PASS  numero consumido em transacao revertida nao e reutilizado (antes=$ANTES depois=$DEPOIS)"
else
  echo "  FAIL  numero foi reutilizado apos rollback"
  falhas=$((falhas+1))
fi

q "drop table if exists public._p02_serial_colheita;" >/dev/null 2>&1

echo
if [ "$falhas" -gt 0 ]; then
  echo "P02_SERIAL=FAIL ($falhas falha(s))"
  exit 1
fi
echo "P02_SERIAL=PASS (alocacao concorrente) [PG16 TESTE_AUXILIAR_NAO_GATE]"
