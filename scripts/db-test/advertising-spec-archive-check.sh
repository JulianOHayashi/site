#!/usr/bin/env bash
# ============================================================================
# Contraprova isolada da máquina de estados de commercial_advertising_specs
# (auditoria de 10/11): cada cenário roda numa transação própria, a partir de
# uma especificação recém-aprovada (draft -> approved), e é revertido.
# Uso: BDFLOW_LOCAL_DB=<banco local já migrado> bash scripts/db-test/advertising-spec-archive-check.sh
# Só banco LOCAL descartável.
# ============================================================================
set -uo pipefail
DB="${BDFLOW_LOCAL_DB:?defina BDFLOW_LOCAL_DB}"
OK=0; RUIM=0
cenario() { # nome esperado(REJEITAR|PERMITIR) sql
  local nome="$1" esperado="$2" sql="$3" saida rc obtido
  saida=$(su postgres -c "psql -X -q -v ON_ERROR_STOP=1 -d $DB -f -" 2>&1 <<SQL
begin;
insert into public.commercial_advertising_specs
  (spec_code, spec_version, modality, artwork_reference_width_mm,
   artwork_reference_height_mm, source_hash, notes)
values ('[QA FICTICIO] ARQ', '0', 'vehicle_roof_visual_flag', 490, 305, repeat('a', 64), 'QA original');
update public.commercial_advertising_specs
   set lifecycle_status = 'approved', technical_responsible_name = '[QA] R',
       technical_responsible_registration = '[QA] 0', technical_report_hash = repeat('c', 64),
       approved_by = gen_random_uuid(), approved_at = now() - interval '1 hour'
 where spec_code = '[QA FICTICIO] ARQ';
$sql
rollback;
SQL
)
  rc=$?
  if [ $rc -eq 0 ]; then obtido=PERMITIR; else obtido=REJEITAR; fi
  if [ "$obtido" = "$esperado" ]; then OK=$((OK+1)); echo "PASS  $nome -> $obtido"
  else RUIM=$((RUIM+1)); echo "FAIL  $nome -> $obtido (esperado $esperado) $(echo "$saida" | grep -m1 ERROR)"; fi
}
W="where spec_code = '[QA FICTICIO] ARQ'"
A="lifecycle_status = 'archived', archived_at = now()"
cenario "approved->archived + id"         REJEITAR "update public.commercial_advertising_specs set $A, id = gen_random_uuid() $W;"
cenario "approved->archived + notes"      REJEITAR "update public.commercial_advertising_specs set $A, notes = 'outra' $W;"
cenario "approved->archived + created_at" REJEITAR "update public.commercial_advertising_specs set $A, created_at = created_at - interval '1 day' $W;"
cenario "approved->archived limpo"        PERMITIR "update public.commercial_advertising_specs set $A $W;"
cenario "archived: alterar notes"         REJEITAR "update public.commercial_advertising_specs set $A $W; update public.commercial_advertising_specs set notes = 'x' $W;"
cenario "archived: voltar a approved"     REJEITAR "update public.commercial_advertising_specs set $A $W; update public.commercial_advertising_specs set lifecycle_status = 'approved', archived_at = null $W;"
cenario "approved: DELETE"                REJEITAR "delete from public.commercial_advertising_specs $W;"
cenario "archived: DELETE"                REJEITAR "update public.commercial_advertising_specs set $A $W; delete from public.commercial_advertising_specs $W;"
cenario "approved: TRUNCATE"              REJEITAR "truncate public.commercial_advertising_specs;"
cenario "INSERT direto como approved"     REJEITAR "update public.commercial_advertising_specs set $A $W; insert into public.commercial_advertising_specs (spec_code, spec_version, modality, artwork_reference_width_mm, artwork_reference_height_mm, source_hash, lifecycle_status, technical_responsible_name, technical_responsible_registration, technical_report_hash, approved_by, approved_at) values ('[QA] B','0','vehicle_roof_visual_flag',490,305,repeat('b',64),'approved','x','y',repeat('d',64),gen_random_uuid(),now());"
cenario "draft->archived direto"          REJEITAR "insert into public.commercial_advertising_specs (spec_code, spec_version, modality, artwork_reference_width_mm, artwork_reference_height_mm, source_hash) values ('[QA] C','0','vehicle_roof_visual_flag',490,305,repeat('b',64)); update public.commercial_advertising_specs set lifecycle_status='archived', archived_at=now(), technical_responsible_name='x', technical_responsible_registration='y', technical_report_hash=repeat('d',64), approved_by=gen_random_uuid(), approved_at=now() where spec_code='[QA] C';"
cenario "draft: edicao legitima"          PERMITIR "insert into public.commercial_advertising_specs (spec_code, spec_version, modality, artwork_reference_width_mm, artwork_reference_height_mm, source_hash) values ('[QA] D','0','vehicle_roof_visual_flag',490,305,repeat('b',64)); update public.commercial_advertising_specs set notes='ok', artwork_reference_width_mm=500, spec_version='1' where spec_code='[QA] D';"
cenario "draft: DELETE"                   PERMITIR "insert into public.commercial_advertising_specs (spec_code, spec_version, modality, artwork_reference_width_mm, artwork_reference_height_mm, source_hash) values ('[QA] E','0','vehicle_roof_visual_flag',490,305,repeat('b',64)); delete from public.commercial_advertising_specs where spec_code='[QA] E';"
for r in anon authenticated service_role; do
  for p in INSERT UPDATE DELETE TRUNCATE; do
    v=$(su postgres -c "psql -X -Atq -d $DB -c \"select has_table_privilege('$r','public.commercial_advertising_specs','$p')\"")
    if [ "$v" = "f" ]; then OK=$((OK+1)); else RUIM=$((RUIM+1)); echo "FAIL  $r tem $p"; fi
  done
done
echo "ADVERTISING_SPEC_ARCHIVE: $OK PASS / $RUIM FAIL"
[ "$RUIM" -eq 0 ]
