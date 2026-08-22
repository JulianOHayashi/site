#!/usr/bin/env bash
# ============================================================================
# VARREDURA DE SEGREDOS (R14)
#
# Percorre TODOS os arquivos versionados e TODO o diff da série de commits
# (M1 canônico -> HEAD) procurando material sensível. Inclui controle
# positivo: se o scanner não acusar um segredo plantado em memória, ele
# reprova a si mesmo em vez de dar um verde falso.
#
# Nenhum valor sensível é impresso: apenas arquivo, linha e o rótulo do
# padrão que casou.
# ============================================================================
set -uo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$REPO_ROOT"
BASE="${BDFLOW_M1_BASE:-5cf545001367565ff26973eb33f10b6414f9067c}"

# rótulo|regex
PADROES=(
  'JWT (service_role/anon)|eyJ[A-Za-z0-9_-]{10,}\.eyJ[A-Za-z0-9_-]{10,}\.'
  'chave Supabase sb_|sb_(secret|publishable)_[A-Za-z0-9_-]{16,}'
  'token GitHub|gh[pousr]_[A-Za-z0-9]{30,}'
  'chave privada PEM|BEGIN [A-Z ]*PRIVATE KEY-----'
  'URI Postgres com senha|postgres(ql)?://[^:@/[:space:]]+:[^@/[:space:]]+@'
  'AWS access key|AKIA[0-9A-Z]{16}'
  'token Vercel|vercel_[A-Za-z0-9]{20,}'
  'chave de e-mail (Resend/SendGrid)|(re_[A-Za-z0-9]{20,}|SG\.[A-Za-z0-9_-]{16,}\.)'
  'atribuicao de segredo literal|(?i)(service_role_key|api_?key|secret|password|passwd|signing_key)["'"'"']?\s*[:=]\s*["'"'"'](?!env\()[^"'"'"'${}()[:space:]]{16,}["'"'"']'
)

falhas=0

# --- controle positivo: cada padrao precisa acusar uma amostra sintetica ---
declare -a AMOSTRAS=(
  'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJyb2xlIjoic2VydmljZV9yb2xlIn0.x'
  'sb_secret_ABCDEFGHIJKLMNOPQRSTUV'
  'ghp_ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789'
  '-----BEGIN RSA PRIVATE KEY-----'
  'postgresql://usuario:senhasecreta@db.host:5432/postgres'
  'AKIAIOSFODNN7EXAMPLE'
  'vercel_ABCDEFGHIJKLMNOPQRSTUVWX'
  're_ABCDEFGHIJKLMNOPQRSTUVWX'
  'const apiKey = "ABCDEFGHIJKLMNOPQRSTUVWX"'
)
for i in "${!PADROES[@]}"; do
  rotulo="${PADROES[$i]%%|*}"
  regex="${PADROES[$i]#*|}"
  if ! printf '%s\n' "${AMOSTRAS[$i]}" | grep -qPI "$regex"; then
    echo "CONTROLE POSITIVO FALHOU: padrao nao detecta amostra -> $rotulo"
    falhas=$((falhas+1))
  fi
done
# --- controle negativo: texto comum nao pode acusar ---
for i in "${!PADROES[@]}"; do
  regex="${PADROES[$i]#*|}"
  if printf '%s\n' 'const nome = "parceiro autorizado do portal";' | grep -qPI "$regex"; then
    echo "CONTROLE NEGATIVO FALHOU: padrao acusa texto comum -> ${PADROES[$i]%%|*}"
    falhas=$((falhas+1))
  fi
done

# --- 1. arquivos versionados ---
mapfile -t ARQUIVOS < <(git ls-files)
for entrada in "${PADROES[@]}"; do
  rotulo="${entrada%%|*}"; regex="${entrada#*|}"
  # O proprio scanner contem as amostras; ele se exclui da varredura.
  achados="$(grep -nPI --exclude='secret-scan.sh' "$regex" "${ARQUIVOS[@]}" 2>/dev/null \
             | grep -v '^scripts/audit/secret-scan.sh:' || true)"
  if [ -n "$achados" ]; then
    echo "SEGREDO POSSIVEL EM ARQUIVO VERSIONADO [$rotulo]:"
    printf '%s\n' "$achados" | cut -d: -f1,2 | sed 's/^/  /'
    falhas=$((falhas+1))
  fi
done

# --- 2. todo o diff da serie de commits ---
DIFF="$(git diff "$BASE"..HEAD 2>/dev/null)"
for entrada in "${PADROES[@]}"; do
  rotulo="${entrada%%|*}"; regex="${entrada#*|}"
  # As amostras do proprio scanner aparecem no diff; sao descontadas.
  fora="$(printf '%s\n' "$DIFF" | grep -PI "$regex" 2>/dev/null | grep -vc 'AMOSTRAS\|amostra' || true)"
  fora="${fora:-0}"
  if [ "$fora" -gt 0 ]; then
    if true; then
      echo "SEGREDO POSSIVEL NO DIFF DA SERIE [$rotulo]: $fora ocorrencia(s)"
      falhas=$((falhas+1))
    fi
  fi
done

# --- 3. arquivos de ambiente jamais versionados ---
env_real="$(git ls-files | grep -E '(^|/)\.env($|\.(local|production|development))' || true)"
if [ -n "$env_real" ]; then
  echo "ARQUIVO DE AMBIENTE REAL VERSIONADO:"; printf '%s\n' "$env_real" | sed 's/^/  /'
  falhas=$((falhas+1))
fi
# Templates sao permitidos, mas TODA chave precisa estar sem valor.
for tpl in $(git ls-files | grep -E '(^|/)\.env\.(example|sample|template)$' || true); do
  com_valor="$(grep -nE '^[A-Za-z_][A-Za-z0-9_]*=.+' "$tpl" || true)"
  if [ -n "$com_valor" ]; then
    echo "TEMPLATE DE AMBIENTE COM VALOR PREENCHIDO em $tpl:"
    printf '%s\n' "$com_valor" | cut -d: -f1 | sed 's/^/  linha /'
    falhas=$((falhas+1))
  fi
done

echo
if [ "$falhas" -gt 0 ]; then
  echo "SECRET_SCAN=FAIL ($falhas achado(s))"
  exit 1
fi
echo "SECRET_SCAN=PASS (${#PADROES[@]} padroes, controles positivo e negativo verdes)"
