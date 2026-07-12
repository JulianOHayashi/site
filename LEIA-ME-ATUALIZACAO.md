# Atualização: área de parceiros (login + cadastro + painel)

## O que muda

1. NOVA PÁGINA /parceiros — login e cadastro em abas:
   - Cadastro: nome da empresa + CNPJ (validação real de dígitos)
     + e-mail + senha. O CNPJ fica vinculado à conta — é ele que
     liga o parceiro ao desconto fidelidade automaticamente.
   - Login: e-mail + senha → painel.
   - Se o projeto Supabase estiver com confirmação de e-mail ligada,
     o site avisa "confirme seu e-mail" após o cadastro.

2. NOVO PAINEL /parceiros/painel (protegido — exige login):
   - Saudação com nome da empresa e CNPJ
   - Status de fidelidade (ativo ou "primeira compra libera")
   - Histórico de pedidos (cada parceiro vê SÓ os seus — RLS)
   - Espaços "Materiais do parceiro" (mídia kit, guias de arte)
     marcados ⚠️ A DEFINIR
   - Botão sair

3. NAVEGAÇÃO: link "Parceiros" no cabeçalho e no rodapé da home.

## Pré-requisitos no Supabase (quando conectar)
- Rodar o supabase/precificacao.sql (cria a tabela profiles usada aqui)
- Authentication → Providers → Email: habilitado (padrão)
- Dica para testes: Authentication → Providers → Email →
  desmarcar "Confirm email" agiliza o cadastro (sem link por e-mail)

Em modo demonstração (sem Supabase), a página aparece com os
formulários desativados e um aviso — nada quebra.

## Arquivos desta atualização
- src/pages/Parceiros.tsx        → NOVO
- src/pages/ParceirosPainel.tsx  → NOVO
- src/hooks/useAuth.ts           → NOVO
- src/App.tsx                    → SUBSTITUI (rotas novas)
- src/pages/Home.tsx             → SUBSTITUI (links Parceiros)

## Como aplicar no GitHub (github.com/JulianOHayashi/site)
1. Add file → Upload files
2. Arraste a pasta `src`
3. Confirme os 5 caminhos → Commit changes
4. Vercel publica sozinha em ~1 minuto
