# R4 — fechamento da auditoria independente da R3

- Data: 2026-11-13. Branch `feat/qa-modalidades-r4-20261113`.
- Base: R3 `049d1c27ca6b219f0506db31c6a9b865ad75cfe7`. Implementação R4:
  commit `25e2b99e1456b8375dee77524f4886a73f092ccc`. Este documento e as duas
  especificações estão no commit seguinte, que só acrescenta documentos.
- Migration nova: `supabase/migrations/20261113180000_commercial_activation_contracts_concurrency_r4.sql`.
  - Preparatória e **não aplicada**. O rollback está em `supabase/rollback/`.
- Nada foi aplicado em Production, e não houve merge nem deploy.
- **Cenário A × B: nenhum foi executado.** As suítes usam preços de DINHEIRO
  fictícios (`[QA FICTICIO]`), sempre dentro de transações revertidas. A
  ativação da SF-v1.5 continua bloqueada no banco até a decisão.

Production, lido só com SELECT em 2026-11-13:

| Item | Valor |
|---|---|
| Regras de preço | v3 (SF-v1.4) `active`; v1 e v2 `superseded`; não há v4 |
| Última migration | `20261111000511`: SF-v1.5, R3 e R4 não aplicadas |
| Pedidos e Acordos Mestre assinados | 0 e 0 |
| Minutas | uma, v1.4, `draft` |
| Papel `postgres` | não é superusuário, mas o supautils o deixa usar `session_replication_role` (ver §1.3) |
| `log_statement` | `ddl`; `pgaudit` não está instalado |

## 0. Resumo

| # | Ponto da auditoria | Resultado | Prova |
|---|---|---|---|
| 1 | Ativação sem o procedimento | **Fechado** para quem não controla o banco. O limite do dono está documentado e é detectado depois do fato | forja R3 × R4; suíte 296 (ataques 1–6); `r4-limite-confianca.sh` |
| 2 | Contrato: conteúdo × economia × liquidação | **Fechado**: aprovação jurídica imutável por minuta | suíte 296, seção 2 |
| 3 | QA operacional | **Especificado**, sem implementação e sem mudança no App | `QA_OPERACIONAL_FLUXO_MINIMO_20261113.md` |
| 4 | Vendas manuais SF-v1.4 | **Proposta** com opções A, B e C; recomendação B | `SF_V14_VENDAS_MANUAIS_PROPOSTA_20261113.md` |
| 5 | Concorrência de bandeiras × pedido | **Fechado**, com duas sessões reais | `r4-concorrencia-bandeiras.sh`: R4 6/0 e R3 1/5 nos dois servidores |
| 6 | 69 linhas × rodapé 10 | **Explicado e corrigido** | `resumo.tsv`: R3 69 × 10; R4 70 × 70 |
| 7 | Portabilidade | **Bundle completo** verificado em repositório vazio, mais um incremental com pré-requisito declarado | `BUNDLES.md` da entrega |

## 1. Ativação (item 1)

### 1.1 O ataque pedido, R3 × R4

Roteiro: `scripts/db-test/r4-forja-registro-ativacao.sql`, igual nos dois
bancos. O operador privilegiado (dono) tem todos os gatilhos ligados e a
pré-verificação aprovada. Ele grava o registro de ativação direto e ativa a v4
**sem** chamar `admin_activate_pricing_rule`.

| | R3 `049d1c2` | R4 |
|---|---|---|
| pré-verificação / gatilhos desligados | `true` / 0 | `true` / 0 |
| INSERT direto no registro | aceito | **recusado**: `activation_log_somente_pelo_procedimento` |
| resultado | `1:superseded,2:superseded,3:superseded,4:active` (**ativou**) | nada muda |

PG16 e PG17 dão o mesmo resultado (`*-forja.log`).

### 1.2 O que a R4 faz

- **Registro só pelo procedimento.** O gatilho `cpal_somente_pelo_procedimento`
  (BEFORE INSERT) consulta `commercial_activation_called_by_procedure()`. A
  função lê a pilha de execução (`PG_CONTEXT`) e exige um quadro
  `public.admin_activate_pricing_rule(integer,text)`, com schema, nome e
  assinatura exatos. A regex casa o identificador, não o texto traduzido, então
  vale em qualquer `lc_messages`. Production usa `en_US.UTF-8`, servidor 17.6.
- O gatilho preenche `actor`, `txid` e `created_at`; o chamador não escolhe esses
  valores.
- **Transições só pelo procedimento.** `prepared → active` e a superação da
  vigente também exigem o procedimento na pilha (`ativacao_nao_autorizada`,
  `superacao_nao_autorizada`).
- **Impressão digital das guardas.** O ato grava em `guard_fingerprint` o md5 do
  código, `SECURITY DEFINER`, volatilidade e `search_path` de 20 funções de
  guarda, mais o estado de 19 gatilhos. A linha de base desta versão está em
  `docs/release/R4_IMPRESSAO_DIGITAL_GUARDAS.txt` (md5
  `fd2d2c38f81741a1e79b4178a0cd7ebd`). O ensaio de upgrade confere esse valor
  no PG16 e no PG17.
- O procedimento recusa a ativação com qualquer gatilho de guarda desligado e
  aponta qual.

Suíte 296, seção 1, todos com a pré-verificação aprovada e as travas ligadas:

| Ataque | Resultado |
|---|---|
| 1. INSERT direto no registro | recusado |
| 2. UPDATE direto `prepared → active` | recusado |
| 3. superar a v3 por UPDATE | recusado |
| 4. função própria, com outro nome, gravando o registro | recusado |
| 5. homônimo `atalho296.admin_activate_pricing_rule(integer,text)` | recusado |
| 6. sobrecarga `public.admin_activate_pricing_rule(integer,text,boolean)` | recusado |
| trava desligada | o procedimento recusa e aponta a trava |
| procedimento substituído por DDL | ativa, mas grava impressão digital **diferente** da linha de base (limite, §1.3) |
| ativação autorizada | registro com ator, transação e impressão digital da linha de base; imutável |

### 1.3 Limite de confiança do dono do banco

Um banco não consegue se proteger de quem o controla. A R4 fecha todos os
caminhos que não exigem esse controle e torna detectável o que o exige.

| Poder do dono | Impede? | Detecta? | Prova |
|---|---|---|---|
| Gravar registro / UPDATE direto, travas ligadas | **sim** | — | 296 ataques 1–6 |
| `ALTER TABLE … DISABLE TRIGGER` **antes** de ativar | **sim**: o procedimento recusa | — | 296 |
| `DISABLE TRIGGER` **depois** de ativar | não | **sim**: verificação somente-leitura, linhas 1 e 2 | `r4-limite-confianca.sh` L3 |
| DDL substituindo o procedimento ou uma guarda | não | **sim**: impressão digital ≠ manifesto, no registro (se antes) ou na verificação (se depois) | 296 (DDL) e L4 |
| `SET session_replication_role = replica` + UPDATE, sem registro | não | **sim**: versão ≥ 4 sem registro | L1 |
| `replica` + UPDATE + registro forjado com a impressão digital correta, na mesma transação | não | **não pelo banco**: as seis verificações internas saem `true` | L2 |
| idem | — | **sim pelo recibo externo**: o registro forjado não consta do recibo guardado fora do banco | L2 |

Em Production, `postgres` não é superusuário, mas
`supautils.privileged_role_allowed_configs` inclui `session_replication_role`.
O dono do projeto **pode**, portanto, desligar todos os gatilhos na própria
sessão sem DDL. Não testei isso em Production: a sessão é somente leitura. A
afirmação vem da configuração lida, e o efeito foi demonstrado localmente no
PG16 e no PG17.

**Correção possível respeitando a autoridade do dono.** Ela é procedimental, e
nenhuma parte depende de tirar poder do dono:

1. **Recibo externo da ativação.** Logo após a ativação autorizada, quem
   autorizou (não quem executou) registra fora do banco, no documento de
   release ou num ticket, a linha que a verificação lista na seção RECIBOS:
   versão, id do registro, `txid`, `created_at`, ator, referência e md5 da
   impressão digital. Uma ativação sem recibo correspondente é um alarme.
2. **Verificação somente-leitura periódica**
   (`supabase/ops/20261113_verificar_r4_somente_leitura.sql`). Ela confere:
   - impressão digital atual = manifesto;
   - nenhum gatilho de guarda desligado;
   - toda versão ≥ 4 publicada com exatamente um registro;
   - o registro na mesma transação da regra (`xmin`) e com impressão digital do
     manifesto;
   - minutas assináveis aprovadas;
   - pedidos v4 com aprovação no snapshot.

   Por último, lista os recibos.
3. **Trilhas da plataforma** (decisão do dono, não aplicada): `log_statement`
   já registra DDL. Para registrar também `SET session_replication_role` e as
   escritas nessas tabelas, seria preciso `pgaudit` (`misc`, `write`) restrito a
   elas. Também convém reduzir quem tem a senha do papel `postgres`.

### 1.4 Rodapé e contadores

Os contadores PASS/FAIL agora usam sequências (`tests.pass_count` e
`tests.fail_count`). Isso explica os 69 × 10 (item 6, §4).

## 2. Contratos: conteúdo aprovado × versão econômica × liquidação (item 2)

`settlement_model` e `lifecycle_status = 'signable'` dizem o que a minuta
**pretende** ser. A nova tabela `commercial_instrument_template_approvals` diz
o que foi **aprovado**:

| Campo | Amarra |
|---|---|
| `template_id` + `content_sha256` | o conteúdo exato: precisa ser igual ao `source_hash` da minuta na gravação e no uso |
| `contract_economics_version` | a versão econômica (ex.: `SF-v1.5`); única por minuta |
| `settlement_model` | igual ao da minuta (`in_kind_direct_benefits_only`) |
| `settlement_modes` | as modalidades cobertas (`direct_benefits`, `cash`) |
| `applies_to_fidelized` | igual à condição de fidelidade da minuta |
| `legal_approval_reference`, `approved_by_name`, `approved_at` | quem aprovou, quando e o documento da aprovação |

- **Imutável:** gatilho `citap_protect`; UPDATE e DELETE recusados
  (`aprovacao_minuta_imutavel`). Só o dono escreve, por ato próprio
  (migration/ops). `anon`, `authenticated` e `service_role` não têm escrita.
- **Pedido v4:** o construtor do instrumento só individualiza quando aprovação,
  minuta e pedido coincidem em tudo. O snapshot carrega a aprovação (id,
  referência, sha256, modalidades), com proveniência
  `instrument_legal_approval`.
- **Ativação:** a pré-verificação exige, para as duas condições (novo e
  fidelizado), minuta assinável com aprovação de mesmo hash, mesma versão
  econômica, mesmo modelo, **as duas modalidades** e mesma fidelidade.

| Divergência (suíte 296, seção 2) | Resultado |
|---|---|
| sha256 da aprovação ≠ minuta | gravação recusada |
| fidelidade da aprovação ≠ minuta | gravação recusada |
| alterar ou apagar a aprovação | recusado |
| minuta `signable` com `settlement_model`, **sem** aprovação | `commercial_instrument_legal_approval_missing` |
| aprovação para outra versão econômica (SF-v1.4) | `…_legal_approval_missing` |
| aprovação só para BENEFÍCIO DIRETO, pedido em DINHEIRO | `…_legal_settlement_mode_not_covered`, e o pedido direto passa |
| aprovação só para uma modalidade | pré-verificação reprova |
| texto da minuta alterado depois da aprovação | `…_legal_content_mismatch` |
| minuta de outra fidelidade | `commercial_instrument_template_fidelity_mismatch` |
| caso correto | instrumento emitido com a aprovação no snapshot |

**Limite:** o texto da minuta não fica no banco; ele guarda o sha256 da fonte
congelada. A ligação entre o arquivo e o hash é externa e verificável por
qualquer pessoa (`sha256sum` do arquivo aprovado). Por isso a referência da
aprovação jurídica precisa citar o sha256 do arquivo aprovado.

Nenhuma aprovação real foi registrada. As da suíte são fixtures de minutas
`[QA FICTICIO]`, criadas por `tests.aprovar_minuta_r3_qa`, que recusa minuta
real.

## 3. Itens 3 e 4

- QA operacional: `docs/release/QA_OPERACIONAL_FLUXO_MINIMO_20261113.md`.
- Vendas manuais SF-v1.4: `docs/release/SF_V14_VENDAS_MANUAIS_PROPOSTA_20261113.md`.

## 4. Concorrência: bandeiras × pedido (item 5)

**Causa:** na R3, a revalidação do pedido lia o conjunto de bandeiras sem
trava. A inspeção reprovadora e a retirada não travavam o conjunto. Assim, um
pedido podia nascer, ou ser confirmado, sobre um conjunto já retirado ou
reprovado em outra transação ainda não efetivada.

**Correção:**
- `cfi_bloquear_conjunto` (BEFORE INSERT na inspeção) trava o conjunto com
  `FOR UPDATE`.
- `ceo_revalidar_reutilizacao_bandeiras` lê o conjunto com `FOR SHARE`.
- A retirada é um UPDATE no conjunto. Ela conflita com `FOR SHARE`, e as duas
  ordens se serializam.

Prova com duas sessões reais (`scripts/db-test/r4-concorrencia-bandeiras.sh`).
B segura a mudança por 3 s, e A começa 1 s depois:

| Cenário | R4 (PG16 e PG17) | R3 (contraprova) |
|---|---|---|
| S1 retirada × criação do pedido | A espera B e falha `flag_reuse_stale` | A não espera; pedido nasce |
| S2 inspeção reprovando × criação | A espera e falha | pedido nasce |
| S3 pedido primeiro × retirada | B espera A; a confirmação posterior é recusada | B não espera (a confirmação posterior é recusada também aqui: o 1 PASS) |
| S4 retirada × confirmação do pagamento | A espera e falha | confirma |
| S5 inspeção reprovando × confirmação | A espera e falha | confirma |
| **Total** | **6 PASS / 0 FAIL** | **1 PASS / 5 FAIL** |

## 5. Evidências: 69 linhas × rodapé 10 (item 6)

**Causa:** na R3, `tests.finish` contava as linhas de `tests.results`. A suíte
295 roda a maior parte dos casos dentro de `begin … rollback`. O ROLLBACK
apagava essas linhas, e só os 10 casos fora das transações revertidas
sobravam para o rodapé. As 69 linhas impressas eram os resultados reais. O
rodapé subcontava, e o sinal de falha da suíte vinha da contagem de `FAIL`
na saída (`run-sql-tests.sh`), não do rodapé.

**Correção:** os contadores passaram a ser as sequências `tests.pass_count` e
`tests.fail_count`. `nextval` não é desfeito por ROLLBACK, então o rodapé
passa a contar tudo o que foi executado.

**Prova** (`resumo.tsv`, contagem por ocorrência, porque um SELECT pode
imprimir vários casos na mesma linha):

| | PG16 | PG17 |
|---|---|---|
| R3, suíte 295 com o helpers da R3 | 69 impressas × rodapé **10** | 69 × **10** |
| R4, suíte 295 | 70 × **70** | 70 × **70** |
| R4, suíte 296 | 27 × 27 | 27 × 27 |
| R4, suíte 290 | 93 × 93 | 93 × 93 |
| suítes com rodapé na R3 que divergiam | **10 de 10** | **10 de 10** |
| suítes com rodapé na R4 que divergem | **0 de 11** | **0 de 11** |

A suíte 295 tem 70 casos na R4. O caso novo verifica que o procedimento recusa
a ativação com uma trava desligada.

**Suítes que já falhavam antes.** As mesmas 15 suítes falham na R3 e na R4,
com as mesmas mensagens. O status por suíte é idêntico nas duas, exceto pela
296, que é nova e passa. São fixtures da base:
- vigência sobreposta de documento legal (100);
- fixtures que não criam as linhas esperadas: `\gset` sem linha ou candidatura não criada (110–190, 200_m2, 910);
- fatos materiais do instrumento (220, 230, 250);
- contaminação entre suítes, por uma minuta assinável deixada por suíte
  anterior (260).

Com o banco recém-criado, a 260 dá 72 PASS / 0 FAIL no PG16 e no PG17
(`evidencias-isoladas/`). Não há regressão da R4. A correção dessas suítes
fica para uma missão própria.

| Outras provas | PG16 | PG17 |
|---|---|---|
| upgrade/rollback R4 sobre a R3 (`r4-upgrade-check.sh`) | 23 / 0 | 23 / 0 |
| upgrade/rollback R3 (`r3-upgrade-check.sh`, checkout R3) | 25 / 0 | 25 / 0 |
| limite de confiança (`r4-limite-confianca.sh`) | 6 / 0 | 6 / 0 |
| frontend (`npm run validate`) | 71 arquivos, 1291 passaram, 1 ignorado; build ok | — |

O ensaio de upgrade R4 confere quatro coisas:
- só mudaram as 5 funções estendidas, e com a mesma segurança;
- a tabela histórica e os preços ≤ v3 ficaram idênticos;
- a impressão digital é igual ao manifesto;
- o rollback devolve o catálogo idêntico (2020 linhas) e é recusado depois de
  uma ativação.

Para reproduzir:
`bash scripts/db-test/r4-evidencias.sh <saida> <checkout-R3-049d1c2>`.
A saída traz `resumo.tsv`, um log por etapa, `commit.txt` e `SHA256SUMS`.

## 6. Portabilidade (item 7)

O repositório remoto não tem a R3 nem a R4 (o push dá 403). A entrega tem:

1. `r4-completo.bundle`: **sem pré-requisitos**. Traz o histórico inteiro de
   `main` até a R4, além de `main` (`5dde3d0`) como referência. Foi verificado
   em diretório vazio com `git init` + `git bundle verify` + `git fetch` +
   `git fsck`.
2. `r4-incremental.bundle`: só `049d1c2..R4`. **Pré-requisito declarado:** o
   commit `049d1c27ca6b219f0506db31c6a9b865ad75cfe7` (bundle da R3). Foi
   verificado sobre um clone do bundle completo cortado na R3.
3. `r4.patch` e `r4.diff` (`049d1c2..R4`), com `SHA256SUMS` de tudo.

Passo a passo e hashes: `BUNDLES.md` da entrega.

## 7. Riscos remanescentes

1. **Forja completa pelo dono em `replica`** só é detectada pelo recibo
   externo. Sem a disciplina do recibo, o banco não distingue. Esse é o
   limite real.
2. **Ligação arquivo ↔ hash da minuta** é externa ao banco (§2).
3. **15 suítes da base falhando** por fixtures. Não são regressões, mas
   reduzem a cobertura útil da execução completa.
4. **Caminho manual SF-v1.4** fechado só de fato (minuta em rascunho), não por
   regra, até a decisão do item 4.
5. **QA em produtos sem modelo no banco** até a implementação do fluxo do
   item 3.
6. A impressão digital muda em qualquer migration futura que toque uma
   guarda. O manifesto precisa ser regenerado e versionado junto com ela.

## 8. Decisões pendentes (nenhuma tomada aqui)

1. Preço da modalidade DINHEIRO na SF-v1.5: Cenário A ou B.
2. Redação jurídica das minutas SF-v1.5 (novo e fidelizado) e registro das
   aprovações reais com o sha256 dos arquivos aprovados.
3. Vendas manuais SF-v1.4: A, B ou C.
4. QA operacional: os itens marcados [DECISÃO] na especificação.
5. Trilhas da plataforma (`pgaudit`) e o responsável pelo recibo externo.
6. Aplicação das migrations SF-v1.5, R3 e R4 e o merge. Não autorizados.
