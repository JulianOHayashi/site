# Atualização: polimento visual + efeito 3D da skill Pro Max

## O que muda

1. HERO — entrada em cascata (badge com pulso → título → subtítulo
   → botões, um após o outro ao carregar). "MOVIMENTO" ganhou um
   grifo amarelo de marca-texto inclinado. CTAs com seta que desliza
   no hover.

2. MAPA EM 3D — o efeito assinatura da sua skill (ContainerScroll)
   adaptado para o seu stack SEM dependências novas: o mapa vive
   dentro de uma "tela" (moldura branca com 3 pontinhos nas cores
   da marca e rótulo brasil.mapa) que entra INCLINADA em 3D e vai
   pousando conforme a rolagem. Respeita "reduzir movimento".

3. BRILHOS DE MARCA — os cards Para empresas / Para anunciantes
   ganham glow magenta / ciano no hover.

4. CTA FINAL — a palavra gigante "MOVIMENTO" em contorno sutil
   atravessa o fundo escuro atrás do título.

5. DETALHES DE ACABAMENTO — seleção de texto amarela (marca),
   barra de rolagem discreta que fica magenta no hover.

## Arquivos desta atualização
- src/components/ScrollTilt.tsx → NOVO (efeito 3D, zero dependências)
- src/pages/Home.tsx            → SUBSTITUI
- src/index.css                 → SUBSTITUI

## Como aplicar no GitHub (github.com/JulianOHayashi/site)
1. Add file → Upload files
2. Arraste a pasta `src`
3. Confirme os 3 caminhos → Commit changes
4. Vercel publica sozinha em ~1 minuto
