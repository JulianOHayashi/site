# Pacote P0 — Instruções de revisão e execução manual

**Nada neste pacote foi executado remotamente.** Estas instruções são para
quando você decidir aplicar, manualmente, no SQL Editor do projeto Supabase
`SiteDBFLOW`.

## Ordem de execução

1. **Revisar** os três arquivos linha a linha:
   - `supabase/p0-contencao-preflight.sql`
   - `supabase/p0-contencao-migration.sql`
   - `supabase/p0-contencao-verificacao-pos.sql`
2. **Rodar o preflight** (`p0-contencao-preflight.sql`) no SQL Editor.
   - Confira a seção 1 ("veredito objetivo"): as três linhas precisam
     mostrar `ASSINATURA_CONFERE`. Se qualquer uma mostrar
     `AUSENTE_NO_BANCO` ou `ASSINATURA_DIVERGENTE`, **pare** — a migration
     vai abortar sozinha nesse caso, mas é mais seguro descobrir antes.
   - Revise separadamente qualquer sobrecarga apresentada na seção 3. Uma
     sobrecarga divergente não substitui nem invalida por si só a assinatura
     esperada da seção 1, e não deve ser confundida com ela.
   - Leia a seção 10 (inventário de outras candidatas): confirme que nada
     além do documentado em `docs/p0-inventario-funcoes-legadas.md`
     apareceu. Se aparecer algo novo, não inclua na migration — registre
     para uma análise separada.
   - Guarde o resultado da seção 12 (baseline das RPCs territoriais e
     comerciais de leitura) como
     referência para comparar depois da migration.
3. **Rodar a migration** (`p0-contencao-migration.sql`) — só depois de você
   pessoalmente concordar com o resultado do preflight. É transacional: se
   qualquer verificação interna falhar, a transação inteira é desfeita
   (nenhuma revogação parcial fica presa).
4. **Rodar a verificação posterior** (`p0-contencao-verificacao-pos.sql`).
   - Seção 1 precisa retornar **0 linhas** (nenhuma das três funções
     continua executável por PUBLIC/anon/authenticated).
   - Seção 2 precisa retornar **3 linhas**, todas com `definicao_presente =
     true` (nada foi apagado).
   - Seção 3: todas as colunas devem ser `true` (nenhuma tabela sumiu).
   - Seção 4: comparar manualmente com a seção 12 do preflight — devem ser
     idênticas.
   - Seção 5: comparar manualmente com a seção 4 do preflight — a única
     diferença esperada é a ausência das linhas de PUBLIC/anon/authenticated
     que existiam antes.

## O que esta migration NÃO faz (mesmo depois de aplicada)

- Não conserta o cadastro de empresas (isso é o próximo pacote).
- Não cria `partner_applications` nem qualquer tabela nova da Fase 2A.
- Não remove a loja antiga de camisas nem seus dados.
- Não altera preços, desconto progressivo ou fidelidade por CNPJ+UF de
  forma alguma — essas regras continuam no banco exatamente como estão,
  ativas e sem qualquer restrição de acesso adicionada por este pacote. A
  migration revoga EXECUTE de **apenas as três funções nomeadas**
  (`registrar_cancelamento`, `recalcular_pedido`,
  `create_my_partner_owner_registration`); ela não desativa, contém nem
  toca em nenhuma outra parte do backend legado (preços, desconto
  progressivo, fidelidade, ou qualquer outra função de precificação).
- Não impede cancelamento/recálculo de pedido por vias administrativas.
  **Não presuma quem ainda consegue executar essas funções depois da
  migration** — o REVOKE desta migration lista explicitamente apenas
  `public, anon, authenticated`; nenhuma outra role foi tocada. Para saber
  com certeza se `service_role` (ou qualquer outra role) ainda tem
  permissão efetiva, rode a seção 11 do preflight ou a seção 6 da
  verificação posterior — ambas usam
  `has_function_privilege('service_role', oid, 'EXECUTE')` e reportam o
  valor real, em vez de presumir.

## Se algo der errado

A migration é transacional (`begin`/`commit`) e tem duas camadas de
proteção fail-closed:
1. pré-checagem por `to_regprocedure()` antes de qualquer `REVOKE`;
2. assertiva final que reconta privilégios depois do `REVOKE` e aborta a
   transação inteira se sobrar qualquer concessão a PUBLIC/anon/authenticated.

Se a migration abortar, nada foi alterado — é seguro revisar o preflight de
novo e tentar depois de entender a causa.

## Histórico de migrations (registro, não solução)

A auditoria de 2026-08-03 confirmou **zero entradas em
`supabase_migrations`** no projeto `SiteDBFLOW`. Isso significa que não há
hoje um histórico remoto confiável para comparar "o que já foi aplicado" —
e este pacote **não tenta reconstruir esse histórico**.

Os três arquivos deste pacote foram colocados em `supabase/` seguindo a
mesma convenção de nomenclatura plana já usada no projeto (preflight /
migration / verificação-pós), sem inventar uma estrutura de pastas
timestampada que o projeto ainda não usa.

A criação de uma baseline reproduzível de fato (que compare o estado real do
banco, objeto por objeto, com o que está versionado, e produza um histórico
de migrations confiável a partir daí) **deve ser um pacote separado**,
explicitamente autorizado, porque envolve decisões sobre como tratar toda a
divergência já existente entre o repositório e o banco — não apenas as três
funções contidas aqui.
