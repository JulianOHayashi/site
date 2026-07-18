# Atualização: mapa como primeira tela + UF comercial única

## Fluxo novo
Visitante sem UF salva → /selecionar-estado (mapa + grade de 27
estados) → escolhe a UF → salva validada no navegador → segue ao
destino original (Home ou rota comercial acessada direto). Visitante
com UF válida entra direto na loja; UF inválida volta à seleção.

## O que muda
- NOVA tela /selecionar-estado: identidade da marca, título
  "Escolha seu estado", mapa BrazilMap REUTILIZADO (com fallback
  interno) + grade acessível (teclado, aria, foco visível,
  aria-live), feedback de seleção, ?next= preservando o destino.
- Home SEM o mapa: seção do mapa, faixa de presença e callbacks
  removidos; FAQ ajustado; link "O mapa" saiu do menu.
- FONTE ÚNICA da UF: src/lib/estado.ts (localStorage
  'camisas_uf_selecionada', validação contra as 27 siglas; valor
  estranho é descartado). Sem fallback automático para "ES".
- EstadoGuard protege /, /produtos, /produto/:slug,
  /personalizar/:slug e /checkout — acesso direto sem UF leva à
  seleção e retorna ao destino. /portal, /parceiros e /admin NÃO
  passam pelo mapa.
- Troca de estado: pill discreta "📍 UF · Alterar" no cabeçalho
  (desktop e mobile) + botão na vitrine; a troca refaz as consultas
  (hooks reconsultam pela nova UF; sem cache do estado anterior).
- Consultas estaduais em TODAS as páginas comerciais: detalhe,
  personalização e checkout migraram do hook global para
  useProductsByState(UF) — estoque/preço de product_state_stock,
  disponível = estoque − reservado. Checkout exibe o estado
  comercial no resumo.
- Estado sem produtos: "Ainda não temos produtos disponíveis para
  este estado." + botão para escolher outro (sem inventar estoque).

## Arquivos
NOVOS: src/lib/estado.ts · src/components/EstadoGuard.tsx ·
src/pages/SelecionarEstado.tsx
SUBSTITUEM: src/pages/Home.tsx · src/components/SiteHeader.tsx ·
src/pages/Produtos.tsx · src/pages/ProdutoDetalhe.tsx ·
src/pages/Personalizar.tsx · src/pages/Checkout.tsx · src/App.tsx

## Aplicar no GitHub
Add file → Upload files → arraste a pasta src → Commit.
NADA muda no Supabase (nenhum SQL, env ou dado alterado).
