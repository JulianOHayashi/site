# Pacote de verificação — Schema v2 runtime

1. verificacao-runtime-schema-v2.sql (arquivo separado):
   cole no SQL Editor do Supabase DO SITE e rode. Sai uma lista
   PASS/FAIL cobrindo: 15 tabelas, ausência de tabelas QR, PKs, FKs,
   campos _cents integer, product_type genérico, app_partner_id,
   RLS por tabela, policies-chave, funções/triggers de negócio e
   placeholders MP/Bling. Somente leitura.

2. src/pages/PortalPainel.tsx (correção desta auditoria):
   o exemplo comentado sugeria leitura direta de tabela do app;
   agora referencia apenas os 6 RPCs permitidos pela spec.
   Aplicar via Upload files (pasta src) → commit.
