# Atualização: separação BD do site × BD de QR do app (spec BDFlow)

## O que é
Implementa a especificação de separação de domínios:
- Projeto Supabase do SITE → comércio (14 tabelas da spec + regras
  de precificação/estoque portadas + RLS completo)
- Projeto Supabase do APP → QR/benefícios (INTOCADO; acesso futuro
  apenas via os RPCs listados na spec)

## Arquivos
- supabase/site-schema-v2.sql → schema canônico do projeto do SITE.
  Rodar no SQL Editor do projeto do SITE. Se os scripts antigos já
  rodaram lá, descomente o bloco de DROP no topo (sem dados reais,
  é seguro). Este arquivo SUBSTITUI schema.sql/precificacao.sql.
- src/hooks/useProducts.ts → adaptador: a loja continua idêntica
  visualmente, agora lendo o schema novo (name/base_price_cents/
  stock_quantity + campos de customização). Modo demo intacto.

## Pós-instalação (1 passo importante)
Após criar sua conta de admin no site, adicione seu usuário na
tabela site_admins (Table Editor → site_admins → Insert row com o
seu auth user id, visível em Authentication → Users). Sem isso,
ninguém gerencia catálogo/pedidos/parceiros pelo frontend — por
segurança, o padrão é fechado.

## Como aplicar no GitHub
1. Add file → Upload files → arraste `src` e `supabase`
2. Commit changes → Vercel publica
