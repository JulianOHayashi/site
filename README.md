# Camisas que contam a sua marca — Lado Empresarial

E-commerce de camisas customizadas para empresas do Espírito Santo.
Stack: **React + Vite + TypeScript + Tailwind** · Banco: **Supabase** (opcional) · Deploy: **Vercel**.

Identidade visual "Tintas de Serigrafia": magenta `#E5007E` · ciano `#00A8E0` · amarelo `#FFC400` sobre papel `#FBFAF6`.

## Rodando localmente

```bash
npm install
npm run dev
```

Abre em http://localhost:5173. **Funciona imediatamente em modo demonstração** (produtos e pedidos mock) — não precisa de banco pra ver o site.

## Conectando o Supabase (estoque real)

1. Crie um projeto em https://supabase.com
2. No SQL Editor, rode o conteúdo de `supabase/schema.sql`
3. Copie `.env.example` para `.env` e preencha:
   - `VITE_SUPABASE_URL` → Project Settings → API → Project URL
   - `VITE_SUPABASE_ANON_KEY` → Project Settings → API → anon public key
4. Reinicie `npm run dev`

Com isso o estoque passa a vir do banco **em tempo real**: quando um pedido é criado, um trigger atômico desconta o estoque e todos os navegadores abertos veem o número cair sozinho.

## Subindo para o GitHub

```bash
git init
git add .
git commit -m "Site inicial — lado empresarial"
git branch -M main
git remote add origin https://github.com/SEU_USUARIO/NOME_DO_REPO.git
git push -u origin main
```

## Deploy na Vercel

1. https://vercel.com → login com GitHub
2. Add New → Project → selecione o repositório
3. Framework: Vite (detectado automaticamente) → Deploy
4. Em Settings → Environment Variables, adicione `VITE_SUPABASE_URL` e `VITE_SUPABASE_ANON_KEY` (se estiver usando Supabase) e faça redeploy

Cada `git push` na branch `main` atualiza o site automaticamente.

> **Nota (SPA):** se ao atualizar uma rota interna (ex.: /produtos) der 404 na Vercel, crie `vercel.json` na raiz com rewrite de todas as rotas para `/` — já incluído neste projeto.

## Estrutura

```
src/
  pages/        Home (mapa), EmBreve, Produtos, ProdutoDetalhe,
                Personalizar, Checkout, Admin
  components/   BrazilMap, ShirtPreview (49×30), EstoqueBadge, Header
  hooks/        useProducts (Supabase realtime ou mock)
  lib/          cnpj.ts (validação real), supabase.ts, format.ts
  data/         dados de demonstração
supabase/
  schema.sql    tabelas, triggers de estoque, RLS, realtime
```

## Ainda a definir (placeholders no código)

Pagamento (Stripe/Mercado Pago) · parcelamento · % do desconto fidelidade ·
nota fiscal (NFe.io/Bling) · email transacional (Resend/SendGrid) ·
políticas de troca/termos/LGPD · lado Individual · nomes/preços finais dos modelos.
