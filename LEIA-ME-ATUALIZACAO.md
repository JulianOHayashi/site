# Atualização: /portal/cadastro (empresa parceira + owner)

## O que muda
- NOVA rota protegida /portal/cadastro (dentro do PortalGuard):
  · Pré-verificação no banco (RLS): owner existente
    (active/pending_admin_review/suspended) → tela "conta já
    vinculada" com acesso ao painel, SEM formulário e sem exibir CPF;
    vínculo archived → "necessário atendimento administrativo BDFlow".
  · Formulário em 2 seções (Responsável principal / Empresa
    parceira); e-mail vem da sessão; máscaras + validação real de
    CPF (dígitos verificadores), CNPJ (lib existente) e telefone BR.
  · Envio EXCLUSIVO pela RPC create_my_partner_owner_registration
    (nomes de parâmetros conferidos no SQL executado); sem INSERT
    direto; sem user_id; máscaras removidas antes do envio.
  · Anti duplo-clique; sem retry automático; dados sensíveis limpos
    do estado após sucesso; zero console.log.
  · Sucesso: mensagens definidas na spec + status pendente vindo do
    retorno da função. Erros seguros traduzidos (7 códigos + fallback).
- /portal/dashboard: sem vínculo → botão "Cadastrar empresa
  parceira"; com vínculo → card com nome fantasia + status
  (Aguardando análise da BDFlow / Ativa / Suspensa). Resto intacto.
- App.tsx: rota nova registrada.

## Arquivos
- src/lib/cpf.ts                         → NOVO
- src/lib/telefone.ts                    → NOVO
- src/pages/portal/PortalCadastro.tsx    → NOVO
- src/pages/portal/PortalDashboard.tsx   → SUBSTITUI
- src/App.tsx                            → SUBSTITUI

## Como aplicar no GitHub
Add file → Upload files → arraste a pasta src → Commit changes.
Nada muda no Supabase (o banco já está pronto, 7/7 PASS).
