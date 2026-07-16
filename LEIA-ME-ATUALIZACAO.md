# Atualização: /portal conectado aos RPCs do APP Supabase (BDFlow)

## O que muda
O /portal deixa de ser esqueleto e vira o portal funcional do
PARCEIRO COMERCIAL (mercado/farmácia/loja que valida QR), usando
EXCLUSIVAMENTE o Supabase do APP via RPCs — zero acesso a tabelas.

Rotas novas (canônicas):
- /portal/login         → auth do APP + get_my_partner_context();
                          sem vínculo mostra a mensagem exata da spec
- /portal/dashboard     → get_my_partner_context() +
                          get_partner_cycle_status(); nome do
                          estabelecimento, papel, ciclo, atalhos
- /portal/validar?qt=   → validate_partner_wallet_qr(qt); botão
                          "Solicitar uso do benefício" →
                          create_partner_redemption_request(qt)
- /portal/solicitacoes  → get_my_partner_redemption_requests();
                          Cancelar (só pendentes) →
                          cancel_partner_redemption_request(id)
- /portal e /portal/painel redirecionam para as novas rotas

Segurança implementada:
- Client próprio: src/lib/appSupabaseClient.ts com storage key
  bdflow_partner_portal_auth (sessão separada do site)
- Envs usadas: SOMENTE VITE_APP_SUPABASE_URL/ANON_KEY
- RPC-only: nenhuma chamada .from() a tabelas do app
- Frontend NÃO envia amount_cents/user_id/partner_id/grant_id
- Exibição defensiva: somente campos seguros (nome de exibição,
  documento parcial se o RPC devolver, valores, status); nunca CPF
  completo, telefone, e-mail, endereço, GPS, fotos, Pix/banco
- Sem sessão em /portal/validar?qt=... → login preservando o qt e
  retorno automático à validação

Estados de UI cobertos: carregando, não logado, sem vínculo, erro
de RPC em português, lista vazia ("Nenhuma solicitação encontrada.").

## Arquivos
- src/lib/appSupabaseClient.ts        → NOVO (client canônico)
- src/hooks/usePortalAuth.ts          → NOVO
- src/pages/portal/portalUi.tsx       → NOVO (helpers/estados)
- src/pages/portal/PortalLogin.tsx    → NOVO
- src/pages/portal/PortalDashboard.tsx→ NOVO
- src/pages/portal/PortalValidar.tsx  → NOVO
- src/pages/portal/PortalSolicitacoes.tsx → NOVO
- src/App.tsx                         → SUBSTITUI (rotas)

Obs.: os arquivos antigos src/pages/Portal.tsx, PortalPainel.tsx,
src/lib/supabaseApp.ts e src/hooks/useAuthApp.ts ficam órfãos (nada
os importa) — podem ser apagados do repositório quando quiser.

## Como aplicar no GitHub
Add file → Upload files → arraste a pasta src → Commit changes.
(Nenhuma mudança no Supabase; as 4 envs da Vercel já existem.)
