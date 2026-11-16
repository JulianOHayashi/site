# R4.1 — fechamento do verificador de guardas

- Data: 2026-11-15. Branch `feat/guardas-integridade-r41-20261113`, criada sobre a R4 `cd4064ac9e582759efccad4b4a874d84e1011907`.
- Implementação: commit `6ff89f6f9b685ea3d5c62855800113ffbe7f2ee9` (árvore `8197e47304aa9e679b99817ff2b2b4d01e3aa6d2`). Este relatório e o manifesto legível estão no commit seguinte, que só acrescenta documentos.
- A migration nova é `supabase/migrations/20261113200000_commercial_guard_integrity_r41.sql`.
  - É preparatória e **não foi aplicada**.
  - O rollback é `supabase/rollback/20261113200000_…_rollback.sql`.
- A arquitetura da R4 continua a mesma; a R4.1 só a estende. Não mudam:
  - preços e modalidades;
  - contratos e aprovações jurídicas;
  - linhas históricas;
  - o App.

  Nada foi aplicado em Production, não houve merge e a SF-v1.5 não foi ativada.
- **Cenário A × B segue pendente.** Os preços de DINHEIRO, as aprovações e os procedimentos usados nos testes são fixtures `[QA FICTICIO]`, sempre em transações revertidas. Nenhuma aprovação é criada pela migration nem por outro meio fora dos testes.

## Critério de aceite

Uma guarda não é considerada íntegra só por ter o nome esperado. Cada gatilho de cada tabela guardada só passa se estas propriedades forem iguais às da configuração aprovada:
- estado (`tgenabled`);
- definição canônica (`pg_get_triggerdef`);
- função executada: assinatura e SHA-256 de `pg_get_functiondef`;
- `tgtype`, que codifica momento, nível e eventos;
- argumentos, condição `WHEN`, colunas e propriedades de adiamento.

A configuração aprovada é o manifesto `docs/release/R41_MANIFESTO_GUARDAS.json`, com SHA-256 `bc3f7441b780b6b66fa6086b21633dc52bd942401f2e61da74ac0a85e1cb11d7`. Ele tem:
- 13 tabelas;
- **50 gatilhos**, todos no estado aprovado `O`;
- **49 funções**.

O manifesto é idêntico no PostgreSQL 16.15 e no 17.6. A versão legível é `R41_MANIFESTO_GUARDAS_LEGIVEL.txt`.

## 1. Estado dos gatilhos

**Antes:** a pré-verificação da R4 só recusava `tgenabled = 'D'` ou gatilho ausente. `R` (ENABLE REPLICA) e `A` (ENABLE ALWAYS) passavam.

**Agora:** `commercial_guard_integrity_failures()` compara o catálogo vivo com o manifesto aprovado.
- Estado diferente do aprovado gera `guard_trigger_state_not_approved:<tabela>.<gatilho>:<encontrado>(aprovado O)`.
- Gatilho ausente gera `guard_trigger_missing`.
- `session_replication_role <> 'origin'` também reprova, e o procedimento recusa antes de tudo.

A falha é verificada em três pontos:
- na pré-verificação;
- na transição `prepared → active`, que chama a pré-verificação;
- no gatilho do registro de ativação.

**Contraprova real R4 × R4.1.** O roteiro é idêntico nos dois lados (`scripts/db-test/r41-contraprova-gatilhos.sql`), com banco recém-criado de cada lado:

| C1: `ENABLE REPLICA TRIGGER ceo_pagamento_confere_snapshot` | R4 | R4.1 |
|---|---|---|
| estado do gatilho | `R` | `R` |
| pré-verificação | **aprovada** | reprovada |
| ativação autorizada | **ativou** (v4 `active`) | recusada (v4 `prepared`) |

PG16.15 e PG17.6 dão o mesmo resultado (`evidencias/pg1*-r4*-contraprova.log`).

A suíte 297 cobre `R`, `A`, `D`, ausente e `replica`. Ela também mostra **por que** `R` importa: com a guarda do registro em `R`, um INSERT direto deixa de ser barrado por ela. A pré-verificação aponta o estado `R`, e a transição para `active` continua recusada.

## 2. Impressão digital completa

**Antes:** a R4 registrava, por gatilho, só nome, tabela e estado, com md5. A troca da função executada passava despercebida. A lista de funções também não cobria todas as funções de gatilho.

**Agora:**
- `commercial_guard_catalog()` gera o catálogo canônico:
  - **todos** os gatilhos das tabelas guardadas (um gatilho a mais é `guard_trigger_not_approved`);
  - as funções da lista explícita mais a função de cada gatilho;
  - em cada função, o SHA-256 da definição completa e, nas que não são de gatilho, quem tem EXECUTE.
- A impressão digital gravada na ativação passa a ser esse catálogo.
- O manifesto aprovado fica em `commercial_guard_manifests`, uma tabela só de inserção. O gatilho dela só aceita um manifesto igual ao catálogo vivo, então aprovar significa congelar o que está lá.
- A migration grava o manifesto R4.1 e se autoverifica. Num ambiente com guarda divergente, ela falha inteira.

**Contraprova: mesmo nome e mesmo estado, outra função executada.** É o C2, com `CREATE OR REPLACE TRIGGER ceo_pagamento_confere_snapshot … EXECUTE FUNCTION public.zz_…()`:

| C2 | R4 | R4.1 |
|---|---|---|
| gatilho | mesmo nome, estado `O`, executando outra função | idem |
| pré-verificação | **aprovada** | reprovada |
| ativação autorizada | **ativou** | recusada |

PG16 e PG17 dão o mesmo resultado.

A suíte 297 demonstra os três pontos pedidos:
1. **O manifesto detecta.** A divergência aparece como `guard_trigger_definition_divergent:…:definition_sha256,function,function_sha256`, o SHA-256 do catálogo muda, e a impressão digital no formato da R4 (nome → estado) continua idêntica.
2. **A pré-verificação reprova** e a ativação é recusada; a v4 fica `prepared`.
3. **A ativação autorizada só passa com as guardas corretas.** Com tudo restaurado, ela passa, e o registro grava `guard_catalog_sha256` igual ao do manifesto.

Também são detectados e recusados:
- função de mesmo nome com outro corpo;
- outro evento (`tgtype`);
- condição `WHEN (false)`;
- argumentos;
- gatilho a mais;
- privilégio de EXECUTE concedido ao procedimento;
- o procedimento substituído por DDL. Na R4 isso ainda ativava; na suíte 296 agora é recusado com `activation_log_guardas_divergentes`.

**Verificação somente leitura** (`supabase/ops/20261113_verificar_r41_somente_leitura.sql`):
- Recalcula o catálogo **só com funções do `pg_catalog`**, sem confiar em nenhuma função do schema `public`, que o dono pode trocar.
- Compara com o SHA-256 publicado.
- Confere se `commercial_guard_catalog()` devolve o mesmo resultado, para detectar que ela foi trocada.
- Confere estado `O`, manifestos, registros, aprovações, minutas e QA nos pedidos.
- Lista para confronto externo: manifestos, aprovações de lançamento, procedimentos de QA e recibos.
- Valor nulo conta como `false`.

## 3. Limite administrativo e identidade do responsável

**O dono do banco pode modificar objetos privilegiados.** Isso continua reconhecido. A R4.1 fecha os caminhos que não exigem esse poder e torna detectável o que exige. O que nenhum mecanismo interno resolve depende do registro externo.

| Ação do dono (`r41-limite-confianca.sh`) | O banco impede? | Detecção |
|---|---|---|
| L1 `replica` + UPDATE, sem registro | não | **verificação**: versão sem registro |
| L2 `replica` + aprovação e registro forjados, com catálogo e SHA-256 corretos | não | **não pelo banco** (8/8 `true`); **sim pelo registro externo**: a aprovação e o recibo não constam dele |
| L3 `ENABLE REPLICA` depois da ativação | — | **verificação**: estado ≠ `O` e catálogo ≠ manifesto |
| L4 troca da função executada depois da ativação | — | **verificação**: catálogo ≠ manifesto |
| L5 DDL anulando a comparação e a guarda do registro | não, e ativa | **verificação**: catálogo ≠ manifesto, estado ≠ `O` |
| L6 L5 + restaurar as funções depois do ato | não | **não pelo banco**; **sim pelo registro externo** |

Resultado: **9 PASS / 0 FAIL** no PG16 e no PG17. O roteiro equivalente da R4, rodado no checkout da R4, dá 6 PASS / 0 FAIL.

**`actor` e a identidade.** `actor` (`session_user`) identifica a conexão PostgreSQL, não uma pessoa. A coluna agora tem comentário dizendo isso. O procedimento passou a separar dois papéis:

- **Executor técnico.** É o que o servidor sabe da conexão:
  - `executor_db_role` (= `actor`);
  - `executor_jwt_sub`, o sub do JWT quando a chamada vem pela API; em SQL direto fica nulo e nunca é inferido;
  - `executor_application_name`;
  - `executor_client_addr`.

  O servidor preenche esses campos e ignora o que o chamador mandar.
- **Aprovação do lançamento.** Fica em `commercial_pricing_activation_approvals`, só de inserção, registrada **antes** do ato:
  - referência;
  - SHA-256 do documento externo;
  - `approver_as_stated`, o aprovador **como consta no documento**: declarado e não verificado pelo banco;
  - data declarada.

  O banco grava `registered_by_db_role`, a transação e a hora. A ativação exige a aprovação daquela versão com a mesma referência. Sem ela, a resposta é `activation_approval_not_registered`.
- **Recibo.** O procedimento devolve `receipt`, com:
  - id do registro, `txid`, hora e executor;
  - referência, SHA-256 e aprovador da aprovação;
  - SHA-256 do catálogo e id do manifesto.

  Quem aprovou (não quem executou) guarda o recibo fora do banco. A verificação lista os recibos para confronto.

Nenhuma identidade humana é derivada do papel de banco.

## 4. Pré-requisito operacional da QA: bloqueio verificável

A proposta foi implementada **no banco**, e só como bloqueio. A tabela `commercial_qa_operational_procedures`, só de inserção, registra o procedimento operacional de QA aprovado por versão econômica:
- referência e SHA-256 do documento;
- aprovador declarado e data;
- cobertura obrigatória de **autorização, recebimento dos produtos, execução dos testes, validação de evidências e não cumprimento**. O CHECK recusa cobertura parcial.

O bloqueio age em dois pontos:
- **Ativação:** se a versão tem QA em produtos (termo `direct_benefits` com `qa_in_kind_cents > 0`) e não há procedimento para a economia, a pré-verificação falha com `qa_operational_procedure_missing:SF-v1.5`.
- **Instrumento:** um pedido v4 de benefício direto com QA não é individualizado sem procedimento (`commercial_qa_operational_procedure_missing`). O pedido em DINHEIRO, que não tem QA, não depende dele. O snapshot carrega id, referência e SHA-256 do procedimento.

Como está hoje: nenhum procedimento existe, a migration não cria nenhum e a autoverificação exige que a v4 continue inapta por esse motivo. O App não foi alterado. O fluxo de §2–§6 de `QA_OPERACIONAL_FLUXO_MINIMO_20261113.md` continua sendo o conteúdo que o documento aprovado precisa cobrir.

## 5. Testes e evidências

`bash scripts/db-test/r41-evidencias.sh <saída> <checkout-R4-cd4064a>`. Saída em `evidencias/`, com `resumo.tsv`, logs, `commit.txt` e `SHA256SUMS`.

| | PG16.15 | PG17.6 |
|---|---|---|
| suíte 297 (nova, R4.1) | **46 / 0**, rodapé 46 | **46 / 0**, rodapé 46 |
| suíte 296 R4.1 / R4 | 31 / 0 / 27 / 0 | 31 / 0 / 27 / 0 |
| suíte 295 R4.1 / R4 | 70 / 0 / 70 / 0 | 70 / 0 / 70 / 0 |
| suíte 290 R4.1 / R4 | 93 / 0 / 93 / 0 | 93 / 0 / 93 / 0 |
| suítes com rodapé ≠ linhas impressas (R4.1 / R4) | 0 de 12 / 0 de 11 | 0 de 12 / 0 de 11 |
| status e FAIL por suíte, R4.1 × R4 (fora a 297) | **idênticos** | **idênticos** |
| upgrade/rollback R4.1 sobre a R4 (P1–P6) | **31 / 0** | **31 / 0** |
| upgrade/rollback R4 (checkout da R4) | 23 / 0 | 23 / 0 |
| contraprova C1 (`R`) e C2 (outra função): R4 / R4.1 | ativa / **recusa** | ativa / **recusa** |
| registro de ativação forjado (ataque da R4) | recusado | recusado |
| limite administrativo R4.1 / R4 | 9 / 0 / 6 / 0 | 9 / 0 / 6 / 0 |
| concorrência com duas sessões, R4.1 / R4 | 6 / 0 / 6 / 0 | 6 / 0 / 6 / 0 |
| frontend `npm run validate` | 71 arquivos, 1291 testes ok, 1 ignorado; build ok | — |

Na 296, a R4.1 tem 4 casos a mais:
- o procedimento substituído por DDL agora gera dois casos, catálogo divergente e ativação recusada, no lugar do caso de "limite" da R4;
- o instrumento carrega o procedimento de QA;
- sem procedimento, o instrumento com QA não é emitido; o de DINHEIRO não depende dele.

Duas chaves de erro mudaram nas suítes 295 e 296. Quando a trava está desligada, a falha agora é `guard_trigger_state_not_approved:…:D(aprovado O)` em vez de `guard_trigger_disabled:…`. As ativações das suítes passam por `tests.ativar_sf_v15_qa`, que registra a aprovação fictícia e chama o procedimento real.

O ensaio de upgrade R4.1 roda seis passos:
- P1 aplica numa transação única.
- P2 confere que, entre os objetos que já existiam, só mudaram as 5 funções previstas, com segurança e ACL iguais. Histórico, preços ≤ v3, preço público e cálculos ficam idênticos. O catálogo e o manifesto gravado são iguais ao publicado, a verificação dá 8/8 `true` e não nasce aprovação, procedimento nem ativação.
- P3: o rollback devolve um catálogo idêntico ao da R4 (2052 linhas).
- P4: o rollback é recusado depois de aprovação e ativação.
- P5: numa base com guarda adulterada (`R`, ou outra função), a migration **não aplica e nada muda**.
- P6: numa base com texto divergente como o de Production, a migration aplica e o manifesto confere.

As mesmas 15 suítes da base falham na R4 e na R4.1, por problemas de fixtures, sem regressão (§7).

## 6. Preparação operacional antes do merge (Production lido só com SELECT)

| Verificação em Production (17.6) | Resultado |
|---|---|
| gatilhos de guarda que já existem e não mudam com as migrations pendentes | 17 de 17 com **definição idêntica** ao manifesto, todos `O` |
| funções de guarda que já existem e não mudam com as migrations pendentes | 6 de 13 idênticas byte a byte; **7 com texto diferente**: CRLF, comentários removidos, espaços, literal concatenado |
| essas 7, normalizadas (sem comentários, sem espaços, literais adjacentes unidos) | **iguais** ao repositório: só a forma diverge |
| ACL das funções e privilégios padrão do papel `postgres` | iguais aos locais |

Consequência: como o manifesto é byte a byte, a R4.1 **seria recusada em Production** com `manifesto_guardas_divergente`. Isso falharia fechado, mas impediria o merge operacional. A correção está na seção L da migration: ela reafirma as 7 funções com o texto exato do repositório, sem mudar comportamento. O ensaio P6 cria uma base com o texto divergente (CRLF, sem comentários); a R4.1 aplica e o catálogo bate com o manifesto.

**Condição de aplicação:** as migrations pendentes (SF-v1.5, R3, R4 e R4.1) precisam ser aplicadas **byte a byte** a partir dos arquivos do repositório, sem reformatar o SQL. Qualquer reformatação de uma guarda faz a R4.1 recusar, como deve.

## 7. Limitações

1. **Dono do banco.** Forja completa em `replica` (L2), ou anular e restaurar as guardas por DDL em torno do ato (L6), só são detectadas pelo registro externo de aprovações e recibos. Esse é o limite real.
2. **Identidade humana.** O banco registra o aprovador como declarado no documento externo; não o autentica. A segregação entre aprovador e executor é procedimental.
3. **Ligação documento ↔ SHA-256** (aprovação de lançamento, procedimento de QA, minuta): fica fora do banco e qualquer um pode conferir com `sha256sum`.
4. **Manifesto estrito.** Qualquer migration futura que mude uma guarda, ou o EXECUTE de uma função guardada, precisa gravar um manifesto novo (outra linha em `commercial_guard_manifests`), publicá-lo e acrescentar o SHA-256 dele à lista da verificação.
5. **Reafirmação em Production.** A seção L troca o texto, não o comportamento, de 7 funções em Production quando aplicada. O rollback da R4.1 não volta à formatação antiga.
6. **15 suítes da base** continuam falhando por fixtures, e as mesmas falham na R4 (§5).

## 8. Decisões pendentes (nenhuma tomada aqui)

1. Cenário A ou B para o preço do DINHEIRO.
2. Documento do procedimento operacional de QA e seu registro real.
3. Documento de aprovação do lançamento da SF-v1.5 e quem guarda os recibos.
4. Vendas manuais SF-v1.4, opções A/B/C da R4.
5. Aplicação das migrations SF-v1.5, R3, R4 e R4.1, e o merge.
