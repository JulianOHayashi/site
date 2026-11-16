-- ===========================================================================
-- R4 / item 1 — ataque pedido pela auditoria, roteiro idêntico na R3 e na R4:
-- operador privilegiado (dono) com TODOS os gatilhos ligados e pré-verificação
-- APROVADA grava o registro de ativação direto e ativa a versão 4 sem chamar
-- public.admin_activate_pricing_rule. Transação revertida; banco descartável.
--   R3 (049d1c2): esperado "resultado|1:superseded,2:superseded,3:superseded,4:active"
--   R4:           esperado ERROR activation_log_somente_pelo_procedimento
-- Sem ON_ERROR_STOP: o erro da R4 é o resultado; o ROLLBACK roda nos dois.
-- ===========================================================================
begin;
\o /dev/null
select tests.preparar_ativacao_sf_v15_qa('FORJA', 'A');
\o
select 'preflight_ok', (public.commercial_pricing_activation_preflight(4)->>'ok');
select 'gatilhos_desligados', count(*)::text from pg_trigger
 where not tgisinternal and tgenabled = 'D' and tgrelid::regclass::text like 'public.commercial%';
select 'chamou_o_procedimento', 'nao';
insert into public.commercial_pricing_activation_log (pricing_rule_version, authorization_reference, preflight)
values (4, 'registro forjado por operador', public.commercial_pricing_activation_preflight(4));
update public.commercial_pricing_rules set status = 'superseded' where version = 3;
update public.commercial_pricing_rules set status = 'active', effective_from = now() where version = 4;
select 'resultado', string_agg(version || ':' || status, ',' order by version) from public.commercial_pricing_rules;
rollback;
