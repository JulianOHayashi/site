# Estado atual do Site BDFlow

**Atualizado em:** 2026-08-05  
**Precedência:** este arquivo orienta a leitura do repositório. Decisões de
negócio posteriores e expressamente aprovadas prevalecem sobre documentos
históricos.

## Fonte ativa

- O frontend compilado está exclusivamente em `src/`.
- O ponto de entrada é `src/main.tsx`.
- A configuração do projeto fica na raiz.
- Os artefatos de banco mantidos ficam em `supabase/` e devem ser
  classificados antes de qualquer execução.
- Pacotes de upload, patches consolidados e cópias paralelas do projeto não
  pertencem à fonte ativa.

## Regras vigentes relevantes

- A formação comercial de referência possui 84 unidades:
  supermercado 24 e cinco nichos com 12 unidades cada.
- Existem seis nichos: supermercado, farmácia, roupas femininas, roupas
  masculinas, calçados femininos e calçados masculinos.
- Um nicho é contratado integralmente; unidades internas não são vendidas
  separadamente.
- Não existe desconto progressivo por quantidade.
- O ciclo comercial do Site e o ciclo operacional do App são domínios
  diferentes.
- O navegador não é autoridade para preço, reserva, contrato, pagamento,
  permissão ou validação.

## Estado funcional

| Área | Estado atual |
|---|---|
| Home e navegação pública | Implementadas |
| Localidade comercial | Implementada |
| Oportunidades e formação 84 | Implementadas para consulta |
| Login de parceiros | Implementado |
| Portal com sessão do Supabase do Site | Implementado parcialmente |
| Cadastro inicial de owner/empresa | Frontend existente; backend transitório ainda requer reconciliação |
| Admin | Autorização implementada; módulos operacionais ainda não implementados |
| Managers, convites e revogação | Não implementados na fonte ativa |
| Unidades/filiais | Não implementadas na fonte ativa |
| Waitlists novas | Não implementadas na fonte ativa |
| Contratos, reservas e pagamento | Não implementados |
| Gateway Site↔App | Não implementado |

Não confunda tela existente, SQL proposto ou verificação histórica com recurso
operacional de ponta a ponta.

## Rotas

As rotas vigentes são `/`, `/selecionar-localidade`,
`/oportunidades`, `/parceiros`, `/portal` e `/admin`, incluindo suas
subrotas.

Rotas antigas de loja permanecem somente como redirecionamentos temporários:
`/classica`, `/produtos`, `/produto/:slug`,
`/personalizar/:slug`, `/checkout` e `/selecionar-estado`.

## Supabase

- `commercial-foundation-v1.sql`: fundação comercial atual.
- `fase2a-marco1-*.sql`: fundação, hardening, preflight e verificações do
  Marco 1; consulte os documentos correspondentes antes de qualquer uso.
- `site-partner-core.sql`: transição cadastral anterior que ainda explica a
  RPC usada pelo frontend; não representa sozinho o fluxo final da Fase 2A.
- Os schemas da antiga loja foram removidos do repositório.

Excluir um arquivo SQL do Git não exclui tabelas, funções ou permissões já
existentes no projeto remoto. A limpeza do banco exige migration própria,
inventário de dependências, revisão de privilégios e verificação posterior.

## Regras para auditorias

1. Leia este arquivo primeiro.
2. Audite somente a fonte ativa e as migrations identificadas como relevantes.
3. Classifique cada requisito como implementado, parcial, ausente, não
   aplicável ou decisão aberta.
4. Cite rota, arquivo, tabela, RPC, policy, migration e teste.
5. Não presuma Mercado Pago, frete, tradução, blog, desconto progressivo ou
   qualquer requisito genérico de e-commerce.
