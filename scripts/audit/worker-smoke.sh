#!/usr/bin/env bash
# ============================================================================
# R16 CP4 — SMOKE DO ARTEFATO CONSTRUÍDO DO WORKER
#
# Executa o bundle REAL (dist-worker/main.mjs), não o código-fonte. O que se
# prova aqui não é lógica de despacho — isso é coberto por Vitest — mas o
# comportamento de PROCESSO, que só existe no artefato: código de saída,
# tratamento de sinal e ausência de vazamento no stderr.
#
# Nenhuma credencial real. Nenhum banco real. Nenhum SMTP real. O PostgREST é
# substituído por um servidor HTTP local que devolve lista vazia.
#
# Códigos esperados:
#   2  configuração inválida
#   3  falha de infraestrutura em execução
#   0  one-shot concluído / parada cordial atendida
# ============================================================================
set -uo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$REPO_ROOT"

BUNDLE=dist-worker/main.mjs
falhas=0

if [ ! -f "$BUNDLE" ]; then
  echo "SMOKE=FAIL artefato ausente: $BUNDLE (rode npm run build:worker)"
  exit 1
fi

# Valores de fixture. Curtos e obviamente inertes; nenhum serviço os aceita.
FAKE_KEY="chave-inerte"
BASE_ENV=(
  "ENVIRONMENT=development"
  "SITE_BASE_URL=http://localhost:5173"
  "SMTP_MODE=plaintext_local_only"
  "SMTP_HOST=127.0.0.1"
  "SMTP_PORT=2525"
  "SMTP_FROM_ADDRESS=nao-responda@bdflow.com.br"
  "WORKER_BATCH_SIZE=4"
  "WORKER_RECOVERY_RESERVE=1"
  "WORKER_POLL_INTERVAL_MS=1000"
)

conferir() {
  local rotulo="$1" esperado="$2" obtido="$3"
  if [ "$esperado" = "$obtido" ]; then
    echo "  OK   $rotulo (exit=$obtido)"
  else
    echo "  FAIL $rotulo esperado=$esperado obtido=$obtido"
    falhas=$((falhas+1))
  fi
}

sem_vazamento() {
  local rotulo="$1" arquivo="$2"
  # Nem valor de fixture, nem stack trace com caminho interno.
  if grep -qF "$FAKE_KEY" "$arquivo"; then
    echo "  FAIL $rotulo valor de configuração apareceu na saída"; falhas=$((falhas+1)); return
  fi
  if grep -qE 'at .*\(/.*node_modules' "$arquivo"; then
    echo "  FAIL $rotulo stack trace cru na saída"; falhas=$((falhas+1)); return
  fi
  echo "  OK   $rotulo sem vazamento na saída"
}

# ---------------------------------------------------------------------------
echo "[1] configuração ausente => EXIT_CONFIG"
# ---------------------------------------------------------------------------
out=$(env -i PATH="$PATH" node "$BUNDLE" --once 2>&1); rc=$?
conferir "config vazia" 2 "$rc"
printf '%s\n' "$out" > /tmp/smoke1.log
grep -q 'worker_config_invalid' /tmp/smoke1.log \
  && echo "  OK   evento worker_config_invalid emitido" \
  || { echo "  FAIL evento worker_config_invalid ausente"; falhas=$((falhas+1)); }
grep -q 'missing_required_env' /tmp/smoke1.log \
  && echo "  OK   código do erro presente" \
  || { echo "  FAIL código do erro ausente"; falhas=$((falhas+1)); }

# ---------------------------------------------------------------------------
echo "[2] SMTP_MODE=starttls => EXIT_CONFIG com código próprio"
# ---------------------------------------------------------------------------
out=$(env -i PATH="$PATH" "${BASE_ENV[@]}" \
  SUPABASE_URL=http://127.0.0.1:1/ \
  SUPABASE_SERVICE_ROLE_KEY="$FAKE_KEY" \
  SMTP_MODE=starttls \
  node "$BUNDLE" --once 2>&1); rc=$?
conferir "modo não implementado" 2 "$rc"
printf '%s\n' "$out" > /tmp/smoke2.log
grep -q 'unsupported_smtp_mode' /tmp/smoke2.log \
  && echo "  OK   unsupported_smtp_mode" \
  || { echo "  FAIL unsupported_smtp_mode ausente"; falhas=$((falhas+1)); }
sem_vazamento "modo não implementado" /tmp/smoke2.log

# ---------------------------------------------------------------------------
echo "[3] banco inalcançável em one-shot => EXIT_RUNTIME"
# ---------------------------------------------------------------------------
# Porta 1 fechada: a descoberta falha, nada é enviado, nada é mutado.
out=$(env -i PATH="$PATH" "${BASE_ENV[@]}" \
  SUPABASE_URL=http://127.0.0.1:1 \
  SUPABASE_SERVICE_ROLE_KEY="$FAKE_KEY" \
  node "$BUNDLE" --once 2>&1); rc=$?
conferir "infra indisponível" 3 "$rc"
printf '%s\n' "$out" > /tmp/smoke3.log
grep -q 'worker_cycle_failed' /tmp/smoke3.log \
  && echo "  OK   worker_cycle_failed registrado" \
  || { echo "  FAIL worker_cycle_failed ausente"; falhas=$((falhas+1)); }
sem_vazamento "infra indisponível" /tmp/smoke3.log

# ---------------------------------------------------------------------------
# PostgREST substituto: devolve lista vazia para qualquer consulta.
# ---------------------------------------------------------------------------
cat > /tmp/fake_rest.mjs <<'EOF'
import http from "node:http";
const s = http.createServer((req, res) => {
  res.writeHead(200, { "content-type": "application/json" });
  res.end("[]");
});
s.listen(0, "127.0.0.1", () => {
  console.log(s.address().port);
});
EOF
node /tmp/fake_rest.mjs > /tmp/fake_rest.port 2>/dev/null &
REST_PID=$!
sleep 1
PORT="$(head -1 /tmp/fake_rest.port | tr -d '[:space:]')"
if [ -z "$PORT" ]; then
  echo "  FAIL não foi possível subir o PostgREST substituto"; falhas=$((falhas+1)); PORT=1
fi

# ---------------------------------------------------------------------------
echo "[4] one-shot com fila vazia => EXIT_OK e exatamente um ciclo"
# ---------------------------------------------------------------------------
out=$(env -i PATH="$PATH" "${BASE_ENV[@]}" \
  SUPABASE_URL="http://127.0.0.1:$PORT" \
  SUPABASE_SERVICE_ROLE_KEY="$FAKE_KEY" \
  node "$BUNDLE" --once 2>&1); rc=$?
conferir "one-shot fila vazia" 0 "$rc"
printf '%s\n' "$out" > /tmp/smoke4.log
ciclos=$(grep -c 'worker_cycle_start' /tmp/smoke4.log)
if [ "$ciclos" = "1" ]; then echo "  OK   exatamente 1 ciclo"; else
  echo "  FAIL ciclos=$ciclos esperado=1"; falhas=$((falhas+1)); fi
grep -q '"event":"worker_exit"' /tmp/smoke4.log \
  && echo "  OK   worker_exit emitido" \
  || { echo "  FAIL worker_exit ausente"; falhas=$((falhas+1)); }
sem_vazamento "one-shot" /tmp/smoke4.log

# ---------------------------------------------------------------------------
echo "[5] WORKER_ONE_SHOT=1 equivale a --once"
# ---------------------------------------------------------------------------
out=$(env -i PATH="$PATH" "${BASE_ENV[@]}" \
  SUPABASE_URL="http://127.0.0.1:$PORT" \
  SUPABASE_SERVICE_ROLE_KEY="$FAKE_KEY" \
  WORKER_ONE_SHOT=1 \
  node "$BUNDLE" 2>&1); rc=$?
conferir "one-shot por ambiente" 0 "$rc"

# ---------------------------------------------------------------------------
echo "[6] polling + SIGTERM => parada cordial com EXIT_OK"
# ---------------------------------------------------------------------------
env -i PATH="$PATH" "${BASE_ENV[@]}" \
  SUPABASE_URL="http://127.0.0.1:$PORT" \
  SUPABASE_SERVICE_ROLE_KEY="$FAKE_KEY" \
  node "$BUNDLE" > /tmp/smoke6.log 2>&1 &
W_PID=$!
sleep 2
kill -TERM "$W_PID" 2>/dev/null
wait "$W_PID"; rc=$?
conferir "SIGTERM cordial" 0 "$rc"
grep -q '"event":"worker_shutdown"' /tmp/smoke6.log \
  && echo "  OK   worker_shutdown emitido" \
  || { echo "  FAIL worker_shutdown ausente"; falhas=$((falhas+1)); }
grep -q 'SIGTERM' /tmp/smoke6.log \
  && echo "  OK   motivo da parada registrado" \
  || { echo "  FAIL motivo da parada ausente"; falhas=$((falhas+1)); }
sem_vazamento "polling" /tmp/smoke6.log

# ---------------------------------------------------------------------------
echo "[7] polling + SIGINT => parada cordial com EXIT_OK"
# ---------------------------------------------------------------------------
env -i PATH="$PATH" "${BASE_ENV[@]}" \
  SUPABASE_URL="http://127.0.0.1:$PORT" \
  SUPABASE_SERVICE_ROLE_KEY="$FAKE_KEY" \
  node "$BUNDLE" > /tmp/smoke7.log 2>&1 &
W_PID=$!
sleep 2
kill -INT "$W_PID" 2>/dev/null
wait "$W_PID"; rc=$?
conferir "SIGINT cordial" 0 "$rc"

kill "$REST_PID" 2>/dev/null
wait "$REST_PID" 2>/dev/null

echo
if [ "$falhas" -gt 0 ]; then
  echo "R16_WORKER_SMOKE=FAIL ($falhas achado(s))"
  exit 1
fi
echo "R16_WORKER_SMOKE=PASS (7 cenários de processo)"
