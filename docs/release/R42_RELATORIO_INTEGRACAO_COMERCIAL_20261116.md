# R4.2: integração comercial (somente local)

- Data: 2026-11-16.
- Branch `feat/integracao-comercial-r42-20261116`, sobre a R4.1 `f319c295157c5ca3b2d25b263904c739be2fbe92`.
  - Implementação e testes: `20adbce2cec6abf5942dbcb32a2e159be1eb89a2` (árvore `a39ce85273dbad9c3d45e08d956e983eedba8e8c`).
  - Este relatório está no commit seguinte, que contém só documentos.
- **Origem conferida:**
  - pacote R4.1 com sha256 `85700327…f2a9ba` e `SHA256SUMS` interno ok;
  - bundle completo verificado em repositório vazio: `f319c29`, árvore `d31259d7…`;
  - nenhum commit congelado foi reescrito.
- **O que não foi feito:** nenhum push, merge, deploy ou SQL remoto. Production e o App não foram tocados. A SF-v1.5 não foi ativada. Nenhuma aprovação real ou fictícia fora de testes revertidos.
- **Fontes ausentes:** quatro documentos citados na missão não estavam disponíveis (lista em `R42_MATRIZ_DECISOES_20261116.md`). Usei só o texto das decisões A–F da missão e a confirmação do usuário de 16/11. Nenhum conteúdo foi inventado.

## 1. O que foi implementado e testado

### A. DINHEIRO = Cenário A

O preço **não** foi gravado em migration: ele é gravado por ato do dono, com a v4 em `prepared`, pelo roteiro revisado da R3 (`supabase/ops/20261113_sf_v15_dinheiro_cenario_a.sql`). Agora o roteiro:
- exige a decisão explícita na transação e grava a referência `DECISAO_COMERCIAL_SITE_SF15_CENARIO_A_20261115`;
- confere os **4 valores aprovados** e aborta se a agenda produzir qualquer outro:

  | | Supermercado novo | Supermercado fidelizado | Demais novos | Demais fidelizados |
  |---|---|---|---|---|
  | DINHEIRO | R$ 32.817,32 | R$ 28.054,32 | R$ 22.878,16 | R$ 16.127,16 |
  | Benefício direto | R$ 32.939,00 | R$ 28.176,00 | R$ 22.939,00 | R$ 16.188,00 |

- confere QA = 0 (sem substituto monetário), ajuste = 0 e parcela principal igual à do benefício direto;
- grava o preço sem ativar: a pré-verificação continua reprovando pela trava da QA.

`…cenario_b.sql` agora recusa qualquer execução (`cenario_b_rejeitado`).

No site, a prévia editorial (v3 vigente) mostra o DINHEIRO do Cenário A, distinto do benefício direto, e não afirma igualdade. Na v4 o valor continua vindo só do servidor. A prévia segue **não contratável**.

Provas:
- `scripts/db-test/r42-cenario-a.sh`: 4 condições, recusas, B recusado e histórico ≤ v3 intacto;
- Vitest: `previaPrecosBandeiras`, `apresentacaoComercialOportunidades`.

### B. Fidelidade ≠ reutilização das bandeiras

A condição fidelizada continua decidida só pelas regras do servidor (`is_fidelized_context`); a R4.2 não a altera.

Na renovação fidelizada da SF-v1.5, uma **alteração de arte com produção autorizada para a próxima campanha**, da mesma empresa e identidade, substitui a reutilização verificada das bandeiras antigas.
- **Preço e QA inalterados:** preço-base, participantes e QA são os fidelizados.
- **Produção:** `flag_production_new_units = 0`; a produção da nova arte fica na rubrica separada (orçamento aceito).
- **Vínculo:** `artwork_change_request_id`, imutável e de uso único (índice).
- **Mesma regra em todos os caminhos:** reserva (`create_commercial_checkout_intent`), gatilhos de intenção e de pedido, e venda manual.
- **Decisão E preservada:** peças danificadas **sem** alteração de arte continuam bloqueadas (`flag_replacement_policy_pending`).

### C/D. Solicitação de alteração de frase ou arte

Migration `20261116120000_commercial_artwork_change_fidelity_r42.sql`: 4 tabelas, 12 RPCs, gatilho com máquina de estados.

- **Estados:**
  - fluxo principal: `draft → submitted → under_review → quoted → accepted → production_authorized`;
  - saídas: `rejected` e `cancelled`;
  - orçamento revisado: `accepted → quoted`;
  - nova arte depois do orçamento: `quoted → under_review`.
- **Papéis:**
  - o **owner** cria, envia arte, submete, aceita e cancela;
  - o **administrador do Site** analisa, orça, aprova a exceção, autoriza a produção e recusa;
  - o **manager** só lê.
- **Orçamento:**
  - documento do fornecedor com SHA-256, escopo, peças, custo, total e **teto**;
  - `partner_charge_cents` é **coluna gerada = total do fornecedor**, sem como pôr margem;
  - frete, criação de arte, instalação, tributos e serviços são obrigatoriamente listados como **não incluídos**;
  - a quantidade vem do orçamento: nunca 84 peças automáticas, e R$ 35 não é preço garantido.
- **Aceite:**
  - só o owner aceita, enviando o valor **exato** do orçamento vigente, preso à arte vigente;
  - um orçamento revisado ou uma nova arte derruba o aceite.
- **Vigência:**
  - `next_campaign` é o padrão;
  - `current_campaign` só é autorizada com exceção registrada pelo administrador (motivo e viabilidade, ≥ 10 caracteres cada), e essa alteração **não** serve à renovação.
- **Concorrência e integridade:**
  - cada transição exige a `row_version` vista (`stale_request`);
  - uma solicitação aberta por empresa e identidade (índice);
  - tabelas append-only, e a máquina de estados vale até para o dono.
- **Arte:**
  - fica no bucket privado já existente, com caminho derivado no servidor e preso ao pedido;
  - MIME e tamanho vêm do Storage, e o SHA-256 é calculado no navegador;
  - a imagem do pedido fica **travada** depois que existe produção (ou reutilização/alteração): `artwork_locked_use_change_request`. A arte antiga continua válida, e nada histórico é reescrito.
- **Fim do fluxo:** `production_authorized`. A resposta declara `billing: not_available` e `production_dispatch: not_available`; não há cobrança silenciosa.

**Portal:**
- botão **"Solicitar alteração de frase ou arte"** na lista de pedidos e na tela de personalização;
- página `/portal/pedidos/:orderId/alteracao-arte`, que **não substitui** a arte em execução e não torna nada contratável.

Provas:
- suíte `298_r42_alteracao_arte_fidelidade.sql`;
- Vitest `alteracaoArte.spec.tsx`.

## 2. Guardas e manifesto

A R4.2 altera três funções de gatilho guardadas: `cci_validar_producao_bandeiras`, `ceo_validar_producao_bandeiras` e `commercial_flag_facts_imutaveis`.
- **Novo manifesto R4.2:** `docs/release/R42_MANIFESTO_GUARDAS.json`, SHA-256 `155e055905cde3541da4380179cf6bcdb0685c72de2f09266565d19468f87246`, idêntico no PG16 e no PG17.
- **Gravação:** entra como **segunda linha** de `commercial_guard_manifests`. O R4.1 (`bc3f7441…`) continua gravado e publicado. Não houve simulação de compatibilidade com o hash R4.1.
- **O que muda:** só o hash das 3 funções e o `function_sha256` dos 4 gatilhos que as executam. Estados, definições, eventos e condições não mudam (`R42_MANIFESTO_GUARDAS_LEGIVEL.txt`).
- **Autoverificação:** a migration exige manifesto vigente = R4.2, nenhuma divergência e v4 ainda bloqueada pela QA. Numa base adulterada ela não aplica.
- **Verificação somente leitura:** `supabase/ops/20261116_verificar_r42_somente_leitura.sql`. São 10 itens, aceita os dois manifestos publicados e acrescenta: a renovação com alteração de arte é coerente e de uso único; o aceite e a produção correspondem ao orçamento, sem margem, com exceção quando é a campanha atual.
- **7 funções de texto divergente em Production:** o tratamento da R4.1 está preservado (seção L da R4.1). A R4.2 não mexe nelas.
- **Funções que já existem em Production e serão substituídas** quando a R4.2 for aplicada (comportamento ampliado, ACL preservada): `create_commercial_checkout_intent` (já substituída pela SF-v1.5 pendente), `request_customization_image_path` e `register_customization_image`.

## 3. Testes executados (PG16.15 e PG17.6, contra a R4.1)

Comando: `bash scripts/db-test/r42-evidencias.sh <saída> <checkout-R4.1-f319c29>`. As evidências foram geradas no commit `20adbce` e estão em `evidencias/` (`resumo.tsv`, logs, `SHA256SUMS`).

| | PG16.15 | PG17.6 |
|---|---|---|
| suíte **298** (nova: B, C, D, QA × dinheiro) | **58 / 0**, rodapé 58 | **58 / 0**, rodapé 58 |
| suítes 290 / 295 / 296 / 297: R4.2 (R4.1) | 93 / 70 / 31 / 46, todas 0 FAIL (iguais) | iguais |
| status e FAIL por suíte, R4.2 × R4.1 (fora a 298) | **idênticos** (as mesmas 15 falhas históricas) | idênticos |
| rodapé ≠ linhas impressas | 0 de 13 | 0 de 13 |
| Cenário A real (`r42-cenario-a.sh`) | **9 / 0** | **9 / 0** |
| upgrade/rollback R4.2 sobre a R4.1 (P1–P5) | **30 / 0** | **30 / 0** |
| upgrade/rollback R4.1 (checkout R4.1, comparação) | 31 / 0 | 31 / 0 |
| contraprova R4.1 (`R` e função trocada) sob R4.1 e R4.2 | recusa nos dois | recusa nos dois |
| registro de ativação forjado | recusado | recusado |
| limite administrativo, R4.2 / R4.1 | 9 / 0 e 9 / 0 | 9 / 0 e 9 / 0 |
| concorrência com duas sessões, R4.2 / R4.1 | 6 / 0 e 6 / 0 | 6 / 0 e 6 / 0 |
| frontend `npm run validate` (typecheck, Vitest, build) | 72 arquivos, 1303 testes ok, 1 ignorado | — |

O que a suíte 298 cobre:
- **Fidelidade e reutilização:** fidelidade mantida ao trocar a frase (preço-base fidelizado R$ 16.188,00 inalterado, sem reutilização); a mesma renovação em DINHEIRO (R$ 16.127,16, QA 0); reutilização parcial (10 peças danificadas) bloqueada sem alteração; uso único; vínculo imutável.
- **Orçamento e aceite:** ausência de orçamento; documento obrigatório; teto; margem impossível (coluna gerada); aceite com valor divergente; aumento posterior derrubando o aceite; nova arte derrubando o orçamento.
- **Permissões e concorrência:** manager e outra empresa sem permissão; dupla solicitação; concorrência por `row_version`.
- **Exceção da campanha atual:** recusada sem exceção; owner e manager não aprovam; motivo e viabilidade obrigatórios; a exceção não serve à renovação.
- **Estados e integridade:** cancelamento com motivo; máquina de estados valendo até para o dono; imagem travada depois da produção; trilha de eventos; manifesto íntegro.

## 4. Plano de rollback (antes de qualquer ativação)

1. **Antes de aplicar:** rodar `scripts/db-test/r42-upgrade-check.sh` contra uma cópia do banco-alvo. Exige catálogo = manifesto R4.2 publicado, verificação 10/10 e rollback idêntico.
2. **Para reverter:** `supabase/rollback/20261116120000_…_rollback.sql`.
   - **Recusa** reverter se existir solicitação de alteração de arte ou intenção/pedido vinculado a uma.
   - Volta com o texto exato da R4.1: 6 funções e 2 CHECKs.
   - Retira a linha do manifesto R4.2, com a trava religada na mesma transação.
   - O ensaio P3 confere que o catálogo fica idêntico ao da R4.1 (2130 linhas).
3. **Preço do DINHEIRO:** enquanto a v4 estiver `prepared`, os termos `cash` podem ser retirados pelo dono. Depois da ativação, não. Por isso o Cenário A só deve ser gravado imediatamente antes da ativação autorizada.
4. **Ordem obrigatória de aplicação:** SF-v1.5 → R3 → R4 → R4.1 → R4.2, byte a byte a partir dos arquivos.

## 5. O que ficou só especificado ou pendente

| Tema | Situação |
|---|---|
| Tela do administrador (análise, orçamento, exceção, autorização) | RPCs prontas e testadas. **Não há tela**: o uso é pelo SQL/RPC do administrador. |
| Cobrança da produção da nova arte | **Não implementada.** Fica indisponível e declarada na resposta. |
| Registro da produção da nova arte como conjunto de bandeiras | **Não implementado.** `commercial_flag_sets` só aceita origem em pedido com produção > 0. Assim, a renovação **seguinte** à da alteração não consegue reutilizar as bandeiras novas: exigiria outra alteração ou um ajuste para "origem = solicitação". É uma decisão de produto e operação. |
| Aplicação da arte na campanha atual (exceção) | Termina em `production_authorized`. A troca física e o registro da aplicação não foram implementados. |
| SHA-256 da arte | Calculado no navegador. O banco confere o formato; o conteúdo do objeto não é rehashado no servidor. O objeto é imutável: sem upsert e sem DELETE. |
| Bandeiras danificadas (E) | Bloqueio seguro mantido. Política, responsabilidade e preço por peça estão pendentes. |
| QA (F) | Trava preservada. Alternativas em `R42_QA_ALTERNATIVAS_ATIVACAO_20261116.md`, sem escolha. |
| 15 suítes históricas com falha | As mesmas da R4.1, por problemas de fixtures. Não foram mascaradas nem viraram regressões. |

## 6. Decisões que ainda faltam

| # | Decisão | Bloqueia |
|---|---|---|
| 1 | **Procedimento operacional de QA:** prazos, valoração e consequência do não cumprimento, e seu registro real | Ativação da SF-v1.5 (qualquer modalidade) |
| 2 | Venda SF-v1.5 antes da QA? (Alternativa 1 × estudo da 2, cash-only) | Caminho de ativação |
| 3 | Minutas SF-v1.5 (novo e fidelizado) com a QA só no direto, o DINHEIRO A e a alteração de arte; aprovação jurídica com hash | Ativação; contratos |
| 4 | Aprovação de lançamento real e quem guarda os recibos | Ativação |
| 5 | Como registrar a produção da nova arte (origem = solicitação) e a cobrança da rubrica separada | Renovação seguinte à alteração; cobrança |
| 6 | Política de bandeiras danificadas (E) | Renovação com peças inaptas |
| 7 | Tela de administração da alteração de arte | Operação sem SQL |
| 8 | Validação contábil (repasse em dinheiro no Cenário A, rubrica de produção) | Ativação do DINHEIRO |
| 9 | Vendas manuais SF-v1.4 (R4, item 4) | Caminho manual |
| 10 | Aplicação das migrations e merge | Tudo em Production |

**Menor próxima decisão necessária:** aprovar o **procedimento operacional de QA**, mesmo que mínimo: prazo, valoração e consequência. É a única trava que impede **qualquer** ativação da SF-v1.5 e não depende de código. Os demais itens dependem dela ou correm em paralelo.
