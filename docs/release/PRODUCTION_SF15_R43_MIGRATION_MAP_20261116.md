# Production SmallFlags — SF-v1.5 / R4.3 (2026-11-16)

**Estado técnico:** R4.3.1 implantada no Vercel e as 7 migrations preparatórias foram aplicadas no Supabase `cnsypqynaxdgkcvcmkyx` (PostgreSQL 17.6). A versão 3 da precificação continua `active` e a versão 4 permanece `prepared`. **Não ativar vendas, QA, BENEFÍCIO DIRETO ou cobrança.** A API automática de pagamento está fora do escopo atual.

## Reconciliação obrigatória das migrations

O conector Supabase `apply_migration` usou timestamps da **execução**, diferentes dos prefixos dos arquivos Git. **Não reaplicar estas sete migrations. Não executar `supabase db push` sem reconciliar antes o histórico em `supabase_migrations.schema_migrations`. Não reescrever o histórico sem autorização específica.**

| Prefixo original no Git | Versão efetiva no Supabase | Migration |
|---|---|---|
| 20261112120000 | 20261116230447 | commercial_flag_production_pricing_sf_v15 |
| 20261113150000 | 20261116230510 | commercial_qa_in_kind_settlement_modes_r3 |
| 20261113180000 | 20261116230519 | commercial_activation_contracts_concurrency_r4 |
| 20261113200000 | 20261116230530 | commercial_guard_integrity_r41 |
| 20261116120000 | 20261116230540 | commercial_artwork_change_fidelity_r42 |
| 20261116180000 | 20261116233848 | commercial_artwork_change_integrity_r421 |
| 20261116210000 | 20261116233916 | commercial_cash_only_enablement_r43 |

## Ajuste de compatibilidade necessário

A primeira tentativa da R4.2.1 encontrou diferença no manifesto aprovado: faltava `EXECUTE` para `authenticated` na função `create_commercial_checkout_intent(uuid,text,text,uuid)`. O SQL canônico dessa migration foi corrigido em `fdf6e4e1b788211544c75322039f911aff0a8afc` adicionando o GRANT *antes* da inserção do manifesto. Diagnóstico SQL descartado por rollback confirmou igualdade exata do catálogo com o manifesto SHA-256 `812e47cd2f22b27c27d2cfbeca3cfca8f624bbda87fd6a27f594a411f98e662f`. O acesso `anon` permanece negado.

## Verificações pós-aplicação

- `commercial_guard_integrity_failures()` retornou `[]`.
- Manifesto vigente R4.3 SHA-256 `0cab0fb36136652841593665b3cc481ab57454cfd939d389204df8f789198a79`.
- Preços: v3 `active`, v4 `prepared` com `enabled_settlement_modes = NULL`; não foram gravados os termos Cenário A nem habilitado somente DINHEIRO.
- Sem novas ativações, procedimentos QA, intenções ou pedidos comerciais.
- Vercel reportou sucesso. CI para o commit de correção teve um timeout de teste ESM na primeira tentativa; reexecução específica do job `validate` (tentativa 2) terminou em sucesso.
- Uso futuro de venda manual: somente com documentos, assinaturas e comprovantes reais, usando as rotinas administrativas existentes. Não simular assinaturas ou pagamentos.

**Regra operacional:** qualquer ação de ativação, migração adicional, reconciliação destrutiva do histórico ou alteração jurídica requer autorização específica.
