# Atualização: /portal migrado para o Supabase do SITE

## O que muda (somente autenticação do portal)
- /portal/login autentica no Supabase do SITE (mesmo projeto de
  /parceiros e /admin) — e-mail+senha, logout, sessão reativa,
  redirecionamento com ?next= preservado.
- NOVO PortalGuard protege /portal/dashboard, /portal/validar e
  /portal/solicitacoes: sem sessão → /portal/login?next=<origem
  COM parâmetros> (o ?qt= da validação sobrevive ao login).
  Durante a checagem: "Carregando portal...".
- A sessão antiga do app (chave bdflow_partner_portal_auth) é
  removida do navegador ao carregar o portal — a sessão normal do
  site NÃO é tocada.
- As 6 RPCs do Supabase do APP foram DESATIVADAS no navegador.
  Estados reais desta etapa (sem dados falsos):
  · dashboard  → "Cadastro comercial em preparação"
  · validar    → "Integração com benefícios ainda não configurada"
                 (mostra o código qt recebido, preservado)
  · solicitações → "Nenhuma solicitação encontrada."
- Rotas e visual preservados; /portal e /portal/painel seguem
  redirecionando.
- Arquivos antigos (appSupabaseClient.ts, usePortalAuth.ts etc.)
  NÃO foram apagados — apenas deixaram de ser usados pelas rotas
  ativas, para revisão em etapa futura.

## Arquivos desta atualização
- src/hooks/usePortalSiteAuth.ts          → NOVO
- src/components/PortalGuard.tsx          → NOVO
- src/pages/portal/PortalLogin.tsx        → SUBSTITUI
- src/pages/portal/PortalDashboard.tsx    → SUBSTITUI
- src/pages/portal/PortalValidar.tsx      → SUBSTITUI
- src/pages/portal/PortalSolicitacoes.tsx → SUBSTITUI
- src/pages/portal/portalUi.tsx           → SUBSTITUI (sem vínculos com o app)
- src/App.tsx                             → SUBSTITUI (rotas com PortalGuard)

## Como aplicar no GitHub
Add file → Upload files → arraste a pasta src → Commit changes.
Nada muda no Supabase nem nas variáveis da Vercel.
(As envs VITE_APP_* podem permanecer na Vercel — nada mais as lê
no portal; a remoção pode ser feita em etapa futura.)
