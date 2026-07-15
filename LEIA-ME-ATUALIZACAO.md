# Atualização: animações reativadas a cada rolagem

## O que muda
Antes, os blocos animavam UMA vez (na primeira descida) e ficavam
estáticos até recarregar a página. Agora:

- REVELAR (fade + subida dos blocos): reanima SEMPRE que o bloco
  volta a entrar na tela — descendo ou subindo a página.
- CONTADORES (números grandes): zeram ao sair da tela e recontam
  do zero a cada retorno, com a mesma suavidade.
- MAPA 3D (ScrollTilt): já era contínuo e segue funcionando nos
  dois sentidos.
- Quem usa "reduzir movimento" no sistema continua vendo tudo
  estático, sem animações (acessibilidade preservada).

## Arquivo desta atualização
- src/pages/Home.tsx → SUBSTITUI

## Como aplicar no GitHub (github.com/JulianOHayashi/site)
1. Add file → Upload files → arraste a pasta src
2. Commit changes → Vercel publica em ~1 minuto
