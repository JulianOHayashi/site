# SF-v1.5 — Plano de aplicação segura no Supabase

Nada abaixo foi executado. Cada passo 🔒 exige autorização expressa.

## Fase A — Instalar sem mudar preço (reversível)

| Passo | Ação | Critério |
|---|---|---|
| A1 | Confirmar `main` e o histórico de migrations em Production (última: `20261111000511`). | Igual ao repo |
| A2 🔒 | Aplicar o arquivo exato `supabase/migrations/20261112120000_commercial_flag_production_pricing_sf_v15.sql` numa execução, UTF-8 (a seção Z aborta se o transporte corromper o arquivo). Registrar a versão no histórico como nas migrations anteriores. | COMMIT sem erro; autoverificação passa |
| A3 | Rodar `supabase/ops/20261112_verificar_sf_v15_somente_leitura.sql`. | 10 linhas `ok = true` |
| A4 | Conferir no Site que preços exibidos continuam SF-v1.4. | Supermercado R$ 29.999,00 |

Reversão da fase A: `supabase/rollback/20261112120000_…_rollback.sql`, aceito
só enquanto a versão 4 estiver `prepared` e sem nenhum uso.

## Fase B — Pré-requisitos da ativação (fora do banco)

1. Minutas revisadas (Mestre 7A, Termos 5A, instrumento 6A, anexo 08)
   aprovadas pelo jurídico.
2. Catálogo de atividades `SF-v1.5` aprovado para as posições a vender (D-J11).
3. Procedimento de inspeção aprovado (D-N6) e quem registra conjuntos e
   inspeções definido (D-N8).
4. Decisão sobre reposição (D-N5). Sem ela a ativação é possível, mas todo
   fidelizado com peça inadequada fica bloqueado.
5. Comunicação aos anunciantes do novo preço não fidelizado.

## Fase C — Ativação (irreversível pelo banco)

| Passo | Ação |
|---|---|
| C1 🔒 | Sem reservas vivas. Em uma transação: `SET LOCAL smallflags.autorizacao_ativacao_sf_v15 = 'AUTORIZADO-PELO-OPERADOR';` e executar `supabase/ops/20261112_ativar_precificacao_sf_v15.sql`. Conferir as quatro linhas impressas e só então `COMMIT`. |
| C2 | Repetir a verificação: preço público com `SF-v1.5`, 84 bandeiras, formação 14.763.400. |

Voltar atrás depois de C1 exige migration própria (o gatilho recusa
`active → prepared`).

## Fase D — Operação

- Cada pedido não fidelizado pago gera a necessidade de 84 bandeiras; o
  conjunto é registrado em `commercial_flag_sets` com o `origin_order_id`.
- Antes de cada renovação fidelizada: inspeção de todas as peças em
  `commercial_flag_set_inspections`, com hash do relatório.
- Conciliação: `commercial_exclusivity_flag_production(exclusividade)`.

## Fase E — Modelos V2 (depois de D-T1 e das aprovações)

Os modelos V2 de instrumento passam a exigir `flag_production_new_units`,
`flag_unit_reference_cents` e `flag_production_charge_cents`; o fidelizado
exige também `flag_reuse_set_id` e `flag_reuse_inspection_id`. Ver
`docs/legal/contratos-v2/07_PLANO_PUBLICACAO_VERSIONAMENTO_20261110.md`.
