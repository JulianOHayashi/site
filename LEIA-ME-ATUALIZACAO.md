# Migração: empresa parceira + owner (Supabase do SITE)

## Escopo
SOMENTE banco do site. Nenhuma página nova, nenhum toque em
/parceiros, produtos, checkout, pedidos, /admin, auth do portal,
aplicativo ou Supabase do APP.

## Onde rodar
SQL Editor do projeto do SITE (SiteDBFLOW) → colar
supabase/site-partner-core.sql → Run.
Migração ADITIVA: pode rodar com o banco atual em produção — nada
é excluído, renomeado ou reescrito; registros existentes de
site_monthly_partners (inclusive status 'lead') são preservados.

## O que ela cria/adapta (resumo)
- site_monthly_partners: + owner_user_id; status ganha os valores
  pending/active/suspended/archived via CHECK "NOT VALID" (não
  quebra dados antigos); índices; app_partner_id segue nullable e
  IMUTÁVEL pelo navegador (trigger).
- site_partner_members (NOVA): papéis partner_owner/partner_manager,
  status, CPF normalizado, identity_fingerprint reservado (sem hash
  neste passo), proteção total: papel/vínculo imutáveis fora da
  administração, DELETE bloqueado (use status).
- create_my_partner_owner_registration(...): função transacional e
  idempotente; usa auth.uid() (navegador nunca envia user_id);
  valida e normaliza CPF/CNPJ; empresa nasce 'pending', owner nasce
  'active'; atualiza site_profiles de forma compatível; retorna só
  partner_id, member_id, role, partner_status, member_status.
- RLS: membro vê a própria associação e SOMENTE a própria empresa;
  sem policy de INSERT para o navegador (criação apenas pela
  função); administração via is_site_admin() — sem e-mail fixo.

## Nada de GitHub neste passo
O pacote contém apenas o SQL — nenhuma mudança de frontend.
