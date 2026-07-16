# Atualização: navegação moderna + portal BDFlow visível

## O que muda

1. NOVO CABEÇALHO (padrão moderno de sites atuais):
   - Logo à esquerda · links centrais enxutos (Soluções, O mapa,
     Quem somos, FAQ) · ações à direita
   - Dropdown "ENTRAR" separando com clareza as duas áreas:
       🧾 Área de pedidos  → /parceiros (empresas do site)
       🔳 Portal BDFlow    → /portal/login (parceiros que validam QR)
     ← resolve o portal "escondido": agora tem porta na navegação
   - CTA "Loja" em pílula escura destacada (vira magenta no hover)
   - Sombra suave que aparece ao rolar a página
   - MOBILE: menu hambúrguer animado com painel completo (links,
     as duas áreas de entrada e botão da loja)

2. NAVEGAÇÃO UNIFICADA: todas as páginas internas (loja, checkout,
   parceiros, portal...) passam a usar o MESMO cabeçalho moderno —
   o antigo Header simples virou um redirecionamento para o novo.

3. ÂNCORAS UNIVERSAIS: as seções da home ganharam ids (#solucoes,
   #mapa, #time, #faq, #contato) — o menu funciona de QUALQUER
   página do site, não só da home.

## Arquivos desta atualização
- src/components/SiteHeader.tsx → NOVO (navegação moderna)
- src/components/Header.tsx     → SUBSTITUI (compatibilidade)
- src/pages/Home.tsx            → SUBSTITUI (usa SiteHeader + ids)

## Como aplicar no GitHub
Add file → Upload files → arraste a pasta src → Commit changes.
(Nada muda no Supabase.)
