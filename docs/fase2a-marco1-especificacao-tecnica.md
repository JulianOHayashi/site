# Fase 2A — Marco 1 · Especificação técnica

**Base autoritativa:** commit `cba451e` da `origin/main`.
**Versão do pacote:** V11.
**Natureza deste marco:** estritamente preparatório — documentação e SQL para
inspeção humana.

> **Nenhum SQL deste marco foi executado.** Não houve conexão de escrita com o
> Supabase, nem `db push`, `db reset`, criação de bucket, alteração de Auth,
> commit, push, PR, merge ou deploy. Nenhuma rota, página ou componente React
> foi alterado.

---

## 0. Princípios invioláveis (limites entre navegador, RPC e backend)

Estes princípios governam todo o desenho abaixo e valem para todos os marcos
seguintes:

- **O navegador não define aprovação.** Estados como `approved`, `active` ou
  `rejected` só mudam por função server-side com verificação de papel real.
- **O navegador não cria papéis administrativos.** `is_site_admin()` e papéis de
  parceiro nunca são derivados de payload do cliente.
- **O navegador não registra diretamente logs confiáveis.** `audit_logs` não
  aceita escrita do cliente: nem por policy, nem por grant.
- **O navegador não envia notificações como confirmação oficial.** O cliente
  pode, no máximo, ler o próprio histórico; status de envio/entrega é escrito
  por backend/provedor.
- **Ações críticas ocorrem por backend, RPC segura ou função autorizada**, com
  `security definer`, `search_path` fixo e grants mínimos.
- **Logs de auditoria são imutáveis.** `UPDATE` e `DELETE` são bloqueados por
  trigger, além de negados por grant.
- **Correções de log ocorrem por novos eventos vinculados aos anteriores**, via
  `audit_logs.corrects_log_id` (append-only, jamais edição).

---

## 1. Separação entre `/parceiros` e `/portal`

| Área | Público | Finalidade |
|---|---|---|
| `/parceiros` | Interessado, conta provisória e `partner_owner` | Entrada comercial, cadastro empresarial, status da solicitação, documentos, correções, waitlists e mensagens |
| `/portal` | `partner_owner` e `partner_manager` | Operação: unidades, convites, perfis, vínculos e validações autorizadas |

Regras: o `partner_manager` acessa **somente** `/portal`. O `partner_owner` usa a
**mesma conta** nas duas áreas, com permissões distintas. O interessado sem
aprovação **não** acessa `/portal`.

Hoje (em `cba451e`) `/parceiros` é login-only e `/portal/cadastro` é o único
cadastro real. A Fase 2A inverte isso: o cadastro nasce em `/parceiros/cadastro`,
público, **antes** de existir conta.

## 2. Destino futuro de `/portal/cadastro`

Em marco posterior (não neste), `/portal/cadastro` passa a ser **redirecionamento
seguro** para `/parceiros/cadastro`, **sem executar a RPC antiga**. Motivos:
evita duplicidade de fluxos de criação de empresa, elimina a exigência de sessão
prévia para se cadastrar, e concentra a análise administrativa em um único
funil. Até lá, a rota permanece como está — este marco **não altera rotas**.

## 3. Preservação temporária da RPC antiga

`create_my_partner_owner_registration(p_full_name, p_cpf, p_phone, p_legal_name,
p_trade_name, p_cnpj, p_company_phone default null)` permanece **intacta**: não
é apagada, renomeada, reescrita nem reutilizada pelo novo fluxo. Ela cria
empresa + owner em um passo, o que é incompatível com o modelo de conta
provisória (cadastro antes da conta, e aprovações separadas). O novo fluxo terá
funções próprias, criadas em marcos futuros. A verificação pós-aplicação checa
inclusive que sua **assinatura permanece idêntica**.

## 4. Modelo da conta provisória

Conta de acesso restrito criada após a confirmação do e-mail e a definição de
senha, mantida **a mesma** durante toda a análise e **promovida** (não recriada)
quando a empresa e o primeiro owner forem aprovados — nunca criando usuário
duplicado.

**Pode:** ver status da solicitação; consultar documentos enviados; responder
pedidos de correção; ver waitlists e posições; registrar nicho principal e até
dois alternativos por região; ler mensagens administrativas; atualizar dados
simples permitidos durante a revisão.

**Não pode:** aceitar oportunidade; iniciar reserva; assinar contrato; pagar;
receber exclusividade; validar benefícios; acessar funções financeiras ou
operacionais do Portal.

Estados previstos da solicitação: `draft`, `email_confirmation_pending`,
`submitted`, `under_review`, `changes_requested`,
`company_approved_owner_pending`, `approved`, `rejected`,
`reconsideration_pending`, `active`, `suspended`, `closed`. As entidades que
materializam esses estados entram no **Marco 2** — não neste.

## 5. Confirmação de e-mail e criação de senha

Sequência: solicitação enviada e **salva** → e-mail confirmado (link/código) →
**só então** entra formalmente na fila administrativa → criação da senha →
conta provisória ativa.

A solicitação existe antes da conta; portanto `site_profiles.auth_user_id`
**permanece nullable** (registros provisórios ainda sem usuário Auth). A
unicidade proposta é **parcial** justamente para permitir isso.

O método concreto (Supabase Auth com confirmação nativa vs. código próprio) e o
provedor de e-mail são **decisões abertas** (§18) — este marco não altera a
configuração de Auth.

## 6. Análise separada da empresa e do primeiro `partner_owner`

Duas aprovações independentes: a da **empresa** (CNPJ, dados, endereço,
documentos, elegibilidade) e a da **autoridade do primeiro owner** para
representar o CNPJ. A ativação comercial exige as duas.

Se o solicitante for rejeitado como owner, o CNPJ aprovado **permanece
aprovado**, o rejeitado mantém acesso restrito aos registros pertinentes, e a
empresa pode indicar outro representante — que passa por comprovação de
autoridade **sem** refazer toda a análise empresarial. Entidades:
`partner_applications`, `application_reviews` e
`partner_owner_authority_reviews`, no **Marco 3**.

## 7. Documentos adaptativos

Todos enviam a base essencial (comprovante de CNPJ; contrato social /
requerimento de empresário / certificado MEI; comprovante de endereço
empresarial; documento oficial com foto e CPF do responsável; documento de
representação). Documentos **adicionais** podem ser exigidos conforme tipo
jurídico, nicho, cidade, filial, procuração, divergência cadastral ou análise de
risco.

Modelagem prevista (Marco 2): `application_documents` com metadados, **versões**,
status (`pending`, `submitted`, `rejected`, `approved`) e **referência** ao
arquivo — nunca o binário no banco.

## 8. Aceites jurídicos versionados

Implementados **neste marco** (fundação):

- `legal_documents` — tipo, versão, título, conteúdo **ou** referência,
  `content_hash`, status (`draft`/`published`/`archived`), **indicação de
  mudança material**, vigência (`effective_from`/`effective_to`), publicação e
  autor administrativo. `notes` é campo **interno** e nunca é exposto.
- `legal_acceptances` — aceite versionado com evidência.

Tipos: `privacy_notice`, `provisional_account_terms`, `truthfulness_declaration`,
`document_analysis_authorization`, `representation_declaration`,
`future_commercial_terms`. Marketing fica **fora** desses aceites — é opcional,
separado e nunca bloqueante.

### 8.1 Aceites pré-auth vinculados à solicitação

O fluxo aprovado cria a **solicitação antes da conta Auth**. Por isso o titular
do aceite **não** é um `user_id NOT NULL REFERENCES auth.users`, e sim o par
`(subject_type, subject_id)`:

| `subject_type` | `subject_id` | Momento |
|---|---|---|
| `partner_application` | id da solicitação | **pré-auth** — antes de existir conta |
| `auth_user` | id do usuário Auth | **pós-auth** |

`subject_id` é `NOT NULL`, **imutável e sem FK**: é a âncora da evidência e
sobrevive ao encerramento técnico da conta. `auth_user_id` é **nullable** e serve
como vínculo vivo. `partner_application_id` já existe como coluna documentada; a
**FK para `partner_applications` será adicionada no Marco 2**, quando a tabela
existir. Até lá, a proteção temporária é feita por CHECK
(`legal_acceptances_subject_coerente`), que exige titular identificável e
coerente com o tipo de sujeito.

**Promoção atômica e única.** A primeira associação com uma conta acontece em
**uma única atualização**: quando `linked_auth_user_id` passa de `NULL` para um
valor, a trigger exige `auth_user_id = linked_auth_user_id` na mesma operação —
não é possível preencher só o vínculo imutável e deixar `auth_user_id` nulo.
Depois disso, `linked_auth_user_id` nunca é apagado nem substituído;
`auth_user_id` pode voltar a `NULL` **apenas** pelo encerramento técnico da conta
(`ON DELETE SET NULL`, exclusivo dessa coluna), preservando o vínculo imutável; e
um eventual novo preenchimento precisa ser exatamente igual a
`linked_auth_user_id`. **Outra conta nunca assume o aceite.** Nenhum registro
novo é criado na promoção.

### 8.2 Vínculo imutável com a conta (`linked_auth_user_id`)

A promoção pré-auth acontece **uma única vez em toda a vida do aceite**. A
sequência `NULL → usuário A → NULL → usuário B` é estruturalmente impossível:

| Coluna | Papel | Regras |
|---|---|---|
| `linked_auth_user_id` | **vínculo imutável**, sem FK | começa `NULL` no aceite pré-auth; recebe o UUID da **primeira** conta vinculada; nunca é apagado; nunca é substituído; sobrevive à exclusão da conta |
| `auth_user_id` | **vínculo vivo**, FK `ON DELETE SET NULL` | quando preenchido, é obrigatoriamente **igual** a `linked_auth_user_id` |

Para `subject_type = 'auth_user'`: `subject_id` é a identidade histórica,
`linked_auth_user_id = subject_id`, e `auth_user_id` só pode ficar `NULL` após o
encerramento técnico da conta.

Para `subject_type = 'partner_application'`: `subject_id` e
`partner_application_id` permanecem iguais; `linked_auth_user_id` é preenchido
**uma única vez** na promoção, e qualquer nova tentativa com outro UUID falha.

A FK usa **`ON DELETE SET NULL`**, nunca `RESTRICT`: o encerramento técnico da
conta jamais é bloqueado, e a evidência permanece íntegra porque `subject_id`,
`linked_auth_user_id`, documento, versão, data e conteúdo continuam preservados.

### 8.2.1 Revogação completamente imutável

Antes da revogação, `revoked_at` e `revocation_reason` são **ambos `NULL`**.
Ao revogar, `revocation_reason` é **obrigatória e não vazia** (CHECK). Depois
disso, nenhum dos dois campos pode ser removido ou alterado — a revogação
ocorre **uma única vez**.

### 8.3 Evidência server-side × declaração do cliente

`evidence` é um objeto com duas partes claramente separadas:

- `evidence->'server'` — **evidência confiável**, produzida pelo backend:
  `recorded_at`, `source`, `doc_type`, `doc_version` e `content_hash`.
- `evidence->'client_declared'` — **apenas dados declarados pelo navegador**,
  sem valor probatório autônomo.

A RPC pública `record_legal_acceptance(p_doc_type, p_declared_data)`:

- **o navegador não escolhe o contexto** — `context = 'provisional_account'` é
  fixado server-side (o parâmetro foi removido da assinatura);
- aceita **somente** `privacy_notice` e `provisional_account_terms`. Os
  documentos empresariais (`truthfulness_declaration`,
  `document_analysis_authorization`, `representation_declaration`) serão
  registrados pelo **backend do Marco 2**, vinculados a uma
  `partner_application` real — assim a RPC pública não pode criar aceite ligado
  a uma solicitação inexistente;
- resolve a **versão vigente server-side**, usa `auth.uid()` como identidade e
  fixa `accepted_at = now()` e `origin = 'rpc'`;
- limita `p_declared_data` a **1024 caracteres** e a uma **allowlist** de chaves
  escalares não sensíveis (`ui_locale`, `form_version`, `screen`,
  `client_timezone`);
- usa **conflito explícito** — `on conflict (subject_type, subject_id,
  legal_document_id, context) where revoked_at is null` — correspondente ao
  índice parcial de aceite ativo, em vez de `ON CONFLICT` genérico.

A tabela ainda impõe `jsonb_typeof(evidence) = 'object'` e limite de 8192
caracteres.

### 8.4 Ciclo de vida, vigência e imutabilidade

**Ciclo:** `draft → published → archived`. Um **rascunho interno nunca aparece
como histórico jurídico**:

- `draft` **não** transiciona diretamente para `archived`;
- `archived` só é alcançado **a partir de `published`**;
- `archived` exige `published_at`, `published_by`, `content_hash`,
  `effective_from` **e** `effective_to` não nulo;
- `effective_to` não pode estar no futuro no momento do arquivamento (só se
  arquiva vigência **já encerrada**);
- um documento **não pode nascer** `archived` (bloqueado no INSERT).

A versão vigente é resolvida por `current_legal_document(doc_type)` com
`effective_from <= now() AND (effective_to IS NULL OR effective_to > now())`,
ordenando por `effective_from desc`, `published_at desc`, `id`.

- **Sem sobreposição histórica:** índice único parcial (uma versão publicada
  sem término por tipo) mais trigger que recusa interseção de intervalos
  considerando **`published` E `archived`** — uma versão arquivada continua
  sendo vigência histórica e não pode ser sobreposta por nova publicação. O
  trigger dispara em INSERT e UPDATE cujo novo status seja `published` ou
  `archived`, exclui a própria linha por `id` e usa `pg_advisory_xact_lock` por
  `doc_type` para serializar publicações concorrentes. *(Alternativa futura:
  `EXCLUDE USING gist` + `btree_gist`.)*
- **Imutável após publicar:** `doc_type`, `version`, `title`, `content`,
  `content_url`, `content_hash`, `is_material_change`, `effective_from`,
  `published_at`, `published_by`.
- **`effective_to`:** define-se **uma vez**, sempre posterior a
  `effective_from`; não é removido nem reescrito.
- **Arquivado:** congelado em todos os campos jurídicos, incluindo
  `effective_to`, e não retorna para `draft` ou `published`.

**Histórico sem versões futuras:** `legal_document_versions(doc_type)` retorna
apenas `published`/`archived` com `effective_from <= now()`. Uma versão
**agendada para o futuro** não é visível ao usuário comum — ficará acessível
somente por futura função administrativa.

Renovação de aceite: **apenas mudanças materiais** exigem novo aceite; mudanças
editoriais não.

## 9. Autenticação adicional para ações sensíveis

Decisão aprovada: ações sensíveis exigirão **confirmação da senha atual** +
**código temporário enviado ao e-mail confirmado**. Aplica-se a: troca de owner,
concessão de acesso financeiro, remoção de manager, suspensão de unidade,
alteração de documentos críticos, aceite de contrato e autorização de produção
(fases futuras) e alteração de dados bancários.

Arquitetura necessária (documentada, **não implementada**): tabela de desafios
(`sensitive_action_challenges`) com ação-alvo, `challenge_id`, **hash** do
código, expiração curta, tentativas, consumo único e vínculo ao usuário; emissão
e verificação por RPC `security definer`; o código **nunca** trafega em log ou
URL persistente; a ação só executa dentro da mesma transação/validação do
desafio consumido. Nada disso entra neste marco.

## 10. Camada abstrata de notificações

`notification_events` é **independente de fornecedor**: canal (`email`,
`whatsapp`, `in_app`), destinatário, `template_key` + `template_data`, status,
tentativas, agendamento, envio, entrega, leitura interna, erro, **fornecedor
opcional**, chave de idempotência e correlação.

**Destinatário identificável:** `in_app` exige `recipient_user_id` e não usa
endereço externo; `email`/`whatsapp` exigem `recipient_user_id` **ou**
`recipient_address`, com endereço obrigatório assim que o envio começa.
**Coexistência de canais:** cada canal é uma linha, e a idempotência é **por
canal** (`unique (channel, idempotency_key)`). E-mail é obrigatório nos eventos
críticos; a ausência de WhatsApp **nunca** bloqueia cadastro, convite, prazo ou
acesso.

**Congelamento no início do processamento** — considera-se iniciado quando o
estado **ANTIGO ou o NOVO** atende `attempt_count > 0` **ou** status fora de
`pending`/`scheduled`. Avaliar os dois estados impede que destinatário,
template, `template_data` e correlação sejam alterados **na mesma atualização**
que inicia o processamento. Congelam:
`channel`, `idempotency_key`, `recipient_user_id`, `recipient_address`,
`template_key`, **`template_data`**, `correlation_entity_type`,
`correlation_entity_id` e `created_at`. (`channel`, `idempotency_key` e
`created_at` são imutáveis desde sempre.)

**Timestamps preenchidos não são removidos nem reescritos**, e há coerência
mínima entre status e datas: `scheduled` exige `scheduled_for`; `sent` exige
`sent_at`; `delivered` exige `sent_at` e `delivered_at`; `read` exige `sent_at`,
`delivered_at` e `read_at`; `failed` exige `failed_at`; `delivered_at >=
sent_at`; `read_at >= delivered_at`. `attempt_count` **nunca diminui**.

**Matriz explícita de transições** (validada na trigger; qualquer par fora dela
é recusado):

| De | Para |
|---|---|
| `pending` | `scheduled`, `sending`, `cancelled`, `failed` |
| `scheduled` | `sending`, `cancelled`, `failed` |
| `sending` | `sent`, `failed`, `cancelled` |
| `sent` | `delivered`, `failed` |
| `delivered` | `read` |
| `failed` | `scheduled`, `cancelled` |
| `read`, `cancelled` | — (terminais) |

**Significado exato de `attempt_count`.** Ele conta **tentativas efetivamente
iniciadas**, não agendamentos. Aumenta **exatamente uma unidade** e **somente**
ao entrar em envio (`pending → sending` ou `scheduled → sending`); nenhuma outra
transição o altera — inclusive `failed → scheduled`, que apenas agenda a próxima
tentativa. São recusados: aumento fora da entrada em `sending`, diminuição,
salto maior que uma unidade e entrada em `sending` sem incremento.

Invariantes por estado (usadas também na verificação posterior):

| Estado | `attempt_count` | Observações |
|---|---|---|
| `pending` | exatamente `0` | estado inicial; sem histórico de falha |
| `scheduled` **inicial** | exatamente `0` | `first_failed_at` e `last_failed_at` nulos |
| `scheduled` **após `failed → scheduled`** | pode ser `>= 1` | contador **preservado**; `first_failed_at` e `last_failed_at` preenchidos; `sent_at`, `delivered_at` e `provider_message_id` nulos |
| `sending`, `sent`, `delivered`, `read` | `>= 1` | houve entrada em envio |
| `failed` **sem** envio externo | pode ser `0` | falha direta de `pending`/`scheduled` |
| `failed` **com** `sent_at` ou `provider_message_id` | `>= 1` | houve entrada anterior em `sending` |
| `cancelled` | `0` ou mais | conforme o histórico |

Não há contradição entre reagendar e o contador: `failed → scheduled` **preserva**
`attempt_count`, de modo que um `scheduled` legítimo pode ter `attempt_count >= 1`
desde que carregue o histórico de falha e nenhum envio externo. A verificação
posterior aplica exatamente essas invariantes e **não reprova** esse caso.

**Agendamento inicial e reagendamento.** `scheduled_for` só pode ser definido ou
alterado em **duas** transições: `pending → scheduled` (agendamento inicial) e
`failed → scheduled` (reagendamento). Em todas as demais — incluindo a entrada
em `sending`, `sent`, `delivered`, `read`, `failed` e `cancelled` — permanece
inalterado: não pode ser preenchido se antes era `NULL`, nem alterado, nem
removido.

**Histórico de falhas: `first_failed_at` e `last_failed_at`.** Um único
`failed_at` imutável impediria registrar a segunda falha. O modelo adotado é:
na **primeira** entrada em `failed`, ambos são preenchidos na mesma atualização;
`first_failed_at` nunca muda depois; em **nova** entrada em `failed`,
`last_failed_at` deve **avançar** (nunca retroceder); fora de uma transição
válida para `failed`, ambos são imutáveis — de modo que `failed → scheduled`
preserva o histórico e **nenhuma tentativa anterior é apagada silenciosamente**.
`failed` exige os dois preenchidos (CHECK), e ambos existem juntos ou não
existem.

**Proteção dos dados internos do fornecedor.** `provider` e
`provider_message_id` podem ser preenchidos **apenas** durante `sending` ou
`sent` e, uma vez preenchidos, não são removidos nem substituídos. `error_code`
e `error_message` só podem ser definidos **na entrada em `failed`** (podendo
mudar em uma nova falha válida) e não são alteráveis em outras transições; ambos
têm limite de tamanho (100 e 2000 caracteres). Nenhum desses campos aparece nas
RPCs do usuário.

**Timestamps de progresso** (`sent_at`, `delivered_at`, `read_at`) nunca são
removidos nem reescritos, e a coerência status↔data é garantida por CHECK.
`attempt_count` nunca diminui. Nenhum envio externo é implementado neste marco.

## 10.1 Exposição sanitizada por RPCs (sem views)

Dados pessoais **não** passam por views: uma view executa com privilégios do
proprietário e é fácil de expor por engano. Esta proposta usa **RPCs
`SECURITY DEFINER`** com `auth.uid()` obrigatório, colunas de retorno explícitas,
`search_path` fixo e **sem SQL dinâmico**.

Todas as tabelas brutas recebem `REVOKE ALL ... FROM PUBLIC, anon,
authenticated` e **nenhum grant é reaberto**. O cliente acessa somente:

| RPC | Papel | Expõe |
|---|---|---|
| `get_current_legal_documents()` | `anon`, `authenticated` | apenas versões **atualmente vigentes**, campos públicos |
| `legal_document_versions(doc_type)` | `authenticated` | histórico `published`/`archived` com `effective_from <= now()` |
| `get_my_legal_acceptances()` | `authenticated` | comprovante dos próprios aceites |
| `get_my_notifications()` | `authenticated` | notificações internas próprias, status reduzido |
| `record_legal_acceptance(...)` | `authenticated` | grava aceite com versão e identidade server-side |

Nunca expostos: `notes`, `published_by`, `status` administrativo, `error_*`,
`provider*`, `template_data`, `evidence`, `ip`, `user_agent`, `subject_id`.

**Ausência obrigatória das views antigas.** `my_notifications`,
`my_legal_acceptances` e `legal_documents_public` pertencem às propostas
anteriores baseadas em views e **não podem coexistir** com esta versão. O
preflight e a guarda da fundação tratam sua presença como **bloqueio**: listam,
interrompem e exigem análise manual — nada é removido automaticamente. A
verificação posterior também falha se qualquer uma delas existir.

### 10.2 `service_role`: BYPASSRLS e GRANT são **ambos** necessários

- **BYPASSRLS não substitui GRANT.** Ignorar a RLS não concede privilégio SQL:
  sem `GRANT`, a `service_role` não lê nem escreve.
- **GRANT não substitui BYPASSRLS neste desenho.** Não existe policy para
  `service_role`; sem `rolbypassrls = true`, a RLS bloquearia todas as linhas
  mesmo com privilégio concedido.

Por isso o preflight e a guarda da fundação **bloqueiam** quando a
`service_role` não existir **ou** não tiver `rolbypassrls = true`.

Antes dos `GRANT`, a migration executa `REVOKE ALL ON TABLE ... FROM
service_role` nas quatro tabelas, garantindo que os privilégios sejam
**realmente mínimos** e que nada herdado permaneça:

| Tabela | `service_role` |
|---|---|
| `legal_documents` | `SELECT`, `INSERT`, `UPDATE` |
| `legal_acceptances` | `SELECT`, `INSERT`, `UPDATE` |
| `audit_logs` | `SELECT`, `INSERT` |
| `notification_events` | `SELECT`, `INSERT`, `UPDATE` |

A `service_role` **não conserva** `DELETE`, `TRUNCATE`, `REFERENCES` nem
`TRIGGER`. `EXECUTE` explícito apenas em `write_audit_log(...)` e
`current_legal_document(text)`. As funções de trigger não são executáveis por
ninguém — nem pela `service_role`.

A `service_role` é **exclusiva do backend**; sua chave **nunca** aparece no
frontend. A verificação posterior confirma os privilégios efetivos e a
**ausência de qualquer privilégio adicional**, usando `has_table_privilege`,
`has_function_privilege` e, sobretudo, a leitura direta das ACLs
(`pg_class.relacl`, `pg_proc.proacl`, `aclexplode`, `acldefault`), que distingue
grant direto de privilégio herdado de `PUBLIC`.

### 10.3 `search_path` restrito das novas funções

Todas as funções criadas por este marco usam **`SET search_path = pg_catalog`**
— não `public`. Todo objeto fora de `pg_catalog` é **totalmente qualificado**
(`public.legal_documents`, `public.current_legal_document(...)`, `auth.uid()`,
`auth.users`). O mesmo padrão vale para as funções de trigger. Isso elimina a
possibilidade de captura de objeto por um schema gravável no caminho de busca.

**`public.is_site_admin()` não é alterada neste marco**, mas é validada pelo
preflight **e** pela guarda da fundação: assinatura exata, retorno `boolean`,
`SECURITY DEFINER` e `search_path` completo — rejeitando `pg_temp`, `"$user"` e
qualquer schema não confiável.

**Verificação real do `CREATE` em `public`.** `PUBLIC` é um **pseudo-papel**:
`has_schema_privilege('public', …)` seria interpretado como *nome de papel* e
poderia cair no tratamento de `undefined_object`, deixando o privilégio sem
verificação. Por isso a checagem lê a **ACL real** do schema —
`pg_namespace.nspacl` com `aclexplode`, usando `acldefault` quando `nspacl` for
`NULL`, e reconhecendo `grantee = 0` como `PUBLIC`. Para `anon` e
`authenticated`, além da ACL direta, confere-se o privilégio **efetivo**
(cobrindo herança por associação de papéis). Qualquer `CREATE` encontrado é
**bloqueio**, porque permitiria *shadowing* dos objetos usados pelas funções
`SECURITY DEFINER` quando `public` integra o `search_path`.

### 10.4 ACLs exatas de tabelas e funções

Não se presume que um objeto recém-criado tenha apenas o privilégio padrão. A
fundação executa **`REVOKE ALL` de `PUBLIC`, `anon`, `authenticated` e
`service_role`** em todas as quatro tabelas **e nas treze funções** antes de
qualquer concessão; só então aplica a matriz mínima.

| Função | `EXECUTE` |
|---|---|
| `record_legal_acceptance(text, jsonb)` | `authenticated` |
| `get_my_legal_acceptances()` | `authenticated` |
| `get_my_notifications()` | `authenticated` |
| `legal_document_versions(text)` | `authenticated` |
| `get_current_legal_documents()` | `anon`, `authenticated` |
| `current_legal_document(text)` | `service_role` |
| `write_audit_log(…)` | `service_role` |
| 6 funções de trigger | **ninguém** |

A verificação falha quando: existir `EXECUTE` para papel inesperado; houver
privilégio **herdado** por associação de papéis; `PUBLIC` tiver `EXECUTE`
(inclusive por `proacl NULL`, que equivale ao padrão); ou um papel autorizado
tiver privilégio diferente do esperado. Nas tabelas, falha se **qualquer** papel
além do proprietário técnico tiver privilégio direto ou herdado. As checagens
combinam `pg_class.relacl`, `pg_proc.proacl`, `aclexplode`, `acldefault`,
`has_table_privilege` e `has_function_privilege` — estes últimos cobrindo a
herança registrada em `pg_auth_members`. Apenas o **proprietário técnico** é
ignorado.

### 10.5 Policies identificadas por tabela + nome

A identidade de uma policy é o par **tabela + nome**. Comparar só nomes deixaria
passar uma policy esperada criada na tabela errada ou um nome repetido em outra
tabela. A verificação exige o conjunto exato de pares
(`public.legal_documents/legal_documents_admin_all`,
`public.legal_acceptances/legal_acceptances_select_own`,
`public.audit_logs/audit_logs_admin_read`,
`public.notification_events/notification_events_select_own`) e falha se faltar
um par, existir policy adicional, houver nome esperado na tabela errada, ou se
comando, roles, `USING` ou `WITH CHECK` divergirem.

### 10.6 Validação de `auth.users.id`

Antes de criar qualquer objeto, preflight e guarda confirmam que `auth.users`
existe como tabela, que `auth.users.id` existe, é `uuid` e possui **chave
primária ou índice único simples** — pré-requisito da FK
`legal_acceptances.auth_user_id … ON DELETE SET NULL`. Não se espera a instrução
`CREATE TABLE` falhar para descobrir incompatibilidade. A verificação posterior
confirma a FK simples exata e que `auth_user_id` não participa de nenhuma outra
FK.

### 10.7 Defesa em profundidade em `legal_document_versions`

Mesmo com `EXECUTE` restrito a `authenticated`, a função retorna **zero linhas**
quando `auth.uid()` for `NULL`, além de expor apenas `published`/`archived` com
`effective_from <= now()` — sem versões futuras, sem rascunhos e sem colunas
administrativas internas.

### 10.8 Máquina de estados protegida também no INSERT

Aplicar a máquina de estados apenas em `UPDATE` deixaria a porta aberta: um
`INSERT` direto poderia nascer em `sent` ou `delivered`. Por isso o trigger
cobre **`BEFORE INSERT OR UPDATE`**.

**Estados iniciais permitidos:** apenas `pending` (com `scheduled_for` nulo) ou
`scheduled` (com `scheduled_for` preenchido). `attempt_count` **começa sempre em
zero**; `sent_at`, `delivered_at`, `read_at`, `first_failed_at`,
`last_failed_at`, `provider`, `provider_message_id`, `error_code` e
`error_message` devem vir nulos. Criar diretamente em `sending`, `sent`,
`delivered`, `read`, `failed` ou `cancelled` é recusado — inclusive o
cancelamento, que passa a exigir **transição auditável** após a criação.
Constraints complementares garantem que nenhum marco de progresso exista antes
do estado correspondente e que dados do provedor não apareçam em `pending`/
`scheduled`.

### 10.9 Retentativa no mesmo evento × novo evento

Um mesmo `notification_event` não pode representar **vários envios externos**
depois de já ter `sent_at` ou `provider_message_id` — esses campos são imutáveis
e o histórico ficaria ambíguo. A regra é:

- `failed → scheduled` (retentativa **no mesmo evento**) só é permitido quando
  `sent_at`, `delivered_at` e `provider_message_id` forem **todos nulos**;
- se a falha ocorreu **depois** do envio, o evento permanece **terminal** em
  `failed` e a nova tentativa exige um **novo `notification_event`**.

**`retry_of_event_id`** (`uuid REFERENCES public.notification_events(id) ON
DELETE RESTRICT`, com índice `idx_notification_events_retry`) só pode apontar
para um evento que:

- exista e esteja com `status = 'failed'`;
- tenha **evidência de envio externo** — `sent_at` **ou** `provider_message_id`
  não nulos;
- tenha o mesmo `channel`, `recipient_user_id`, `recipient_address`,
  `template_key`, `template_data`, `correlation_entity_type` e
  `correlation_entity_id`.

É recusado apontar para evento em `pending`, `scheduled`, `sending`, `sent`,
`delivered`, `read`, `cancelled` — e também para `failed` **antes** de qualquer
envio externo, porque nesse caso a retentativa deve permanecer no mesmo evento
via `failed → scheduled`. Continuam exigidos: **nova `idempotency_key`** (a
anterior nunca é reutilizada), `provider_message_id` inicial nulo, ausência de
autorreferência e **imutabilidade** de `retry_of_event_id`. A cadeia permanece
auditável; nenhuma tabela adicional de tentativas é criada neste marco.

### 10.10 ACLs herdadas e papéis inesperados

Ausência de ACL direta **não prova** ausência de privilégio: a herança por
associação de papéis (`pg_auth_members`) concede acesso efetivo sem aparecer em
`relacl`/`proacl`. Por isso a verificação **enumera todos os papéis de
`pg_roles`** e, para cada tabela e função nova, confere o privilégio **efetivo**
(`has_table_privilege` / `has_function_privilege`). São ignorados apenas: o
**proprietário técnico** do objeto, os papéis **explicitamente autorizados**
para aquele objeto, e os papéis com `rolsuper = true` — estes últimos apenas
**registrados como informação**, já que superusuário ignora ACL por definição.
Qualquer outro papel com privilégio efetivo é falha.

### 10.11 Validação final antes do COMMIT

A própria `foundation.sql` executa, **dentro da mesma transação e antes do
`COMMIT`**, uma assertiva que confirma: ACLs exatas das quatro tabelas e das
treze funções; ausência de permissão inesperada por *default privileges*
(`proacl NULL` é tratado como `EXECUTE` para `PUBLIC`); RLS habilitada; conjunto
exato de policies; `SECURITY DEFINER` com `search_path = pg_catalog`;
`service_role` só com os privilégios autorizados; `PUBLIC`, `anon` e
`authenticated` sem acesso direto às tabelas brutas; presença do trigger de
`INSERT`/`UPDATE` da máquina de notificações (`tgtype = 23`); e ausência das
views antigas. Qualquer divergência **lança exceção e provoca ROLLBACK
integral** — a fundação nunca fica parcialmente aplicada.

### 10.12 Requisitos exatos de `auth.users.id`

Preflight, guarda e verificação confirmam que `auth.users.id` **existe**, é
**`uuid`**, é **`NOT NULL`** e possui **PK simples ou índice `UNIQUE` simples**
que esteja `indisvalid`, `indisready` e `indislive`, **sem predicado parcial,
sem expressão, sem `INCLUDE`**, com **exatamente uma coluna-chave** e essa
coluna sendo `id`. Índice parcial, inválido, com expressão, composto, com
`INCLUDE` ou não pronto **não** servem de base para a FK. A verificação
posterior confirma que `legal_acceptances.auth_user_id` tem **exatamente uma**
FK simples para `auth.users(id)` com `ON DELETE SET NULL` e não participa de
nenhuma outra FK.

### 10.13 Validação autoritativa de `public.is_site_admin()`

A função **não é alterada neste marco**. Sua definição autoritativa está em
`supabase/site-schema-v2.sql` (base `cba451e`):

```sql
create or replace function public.is_site_admin()
returns boolean language sql stable security definer as
$$ select exists (select 1 from public.site_admins where user_id = auth.uid()) $$;
```

Registro: assinatura `public.is_site_admin()`; retorno `boolean`; linguagem
`sql`; volatilidade `stable`; `SECURITY DEFINER`; **`search_path`: ausente**;
`md5` do corpo normalizado: **`a65d3c1394e3f45b4afdbf6bba6410a3`**; objetos
referenciados: `public.site_admins` e `auth.uid()` — ambos **qualificados por
schema**, sem dependência de tabela temporária.

O preflight e a guarda **bloqueiam** quando a função do banco divergir dessa
definição (hash, assinatura, retorno, linguagem, volatilidade ou
`SECURITY DEFINER`).

> **Achado bloqueante — requer migration separada.**
> A função existente no banco **corresponde ao corpo autoritativo do commit
> `cba451e`** (md5 `a65d3c1394e3f45b4afdbf6bba6410a3`): o corpo não foi
> adulterado. O problema é **a ausência de `SET search_path` fixo numa função
> `SECURITY DEFINER`**, o que permite manipular o caminho de busca em tempo de
> execução e provocar *shadowing* de `public.site_admins`.
>
> Consequências práticas: **a fundação não será executável** enquanto isso não
> for corrigido; o preflight emite, além do resultado geral
> `PREFLIGHT_FASE2A_MARCO1_BLOQUEADO`, a marca específica
> **`PREFLIGHT_FASE2A_MARCO1_BLOQUEADO_REQUER_HARDENING_IS_SITE_ADMIN`**.
>
> A correção será feita por uma **migration separada**, que altere **somente**
> essa configuração (`ALTER FUNCTION … SET search_path = …`), a ser criada em
> **outro prompt**. **Este pacote (V11) não cria, não altera e não executa essa
> migration**, e não enfraquece o bloqueio.

### 10.14 Alinhamento entre preflight e verificação posterior

Tudo que faria a verificação posterior falhar por ausência prévia agora
**bloqueia o preflight**: ausência ou assinatura divergente de
`create_my_partner_owner_registration(text × 7)`; ausência de qualquer uma das
cinco tabelas comerciais protegidas da Fase 1; ausência das RPCs comerciais
`resolve_commercial_region(text,text)` e
`get_current_commercial_formation(text,text)`; e divergência da definição
autoritativa de `is_site_admin()`. O preflight continua imprimindo os hashes
para comparação manual, mas passa a **bloquear** quando a estrutura protegida
não corresponder à base esperada.

### 10.15 Comparação exata das constraints (precedência preservada)

O verificador carrega um **inventário canônico** com schema, tabela, nome, tipo e
**definição esperada** das 45 constraints. A definição real vem de
`pg_get_constraintdef(oid, FALSE)` — a forma **totalmente parentizada** emitida
pelo catálogo, sem *pretty-printing*.

A normalização remove **apenas**: espaços, casts gerados automaticamente e os
parênteses **externos redundantes** (removidos por varredura de balanceamento, um
par por vez, só quando envolvem toda a expressão). São **integralmente
preservados**: agrupamento interno, precedência de `AND`/`OR`, `NOT`, operadores,
nomes de colunas, valores permitidos, predicados, ações referenciais e casts
semanticamente relevantes. Assim, `a AND (b OR c)` **nunca** colapsa em
`(a AND b) OR c`.

Estratégia **fail-closed**: uma diferença de renderização entre versões do
PostgreSQL produz **falha segura**, com os dois lados impressos, exigindo ajuste
manual do valor esperado. O que **não** é aceitável — e não ocorre — é aprovar
uma definição semanticamente diferente.

`v_ok` só é incrementado quando **nome, tabela, tipo e definição** passam. Cada
grupo do verificador mantém contadores próprios (esperados / aprovados / falhas)
e a palavra `OK` só aparece quando o grupo inteiro passa.

### 10.16 Papéis predefinidos NOLOGIN do PostgreSQL

Papéis como `pg_read_all_data`, `pg_write_all_data`, `pg_monitor`,
`pg_read_all_settings`, `pg_read_all_stats`, `pg_stat_scan_tables` e
`pg_database_owner` possuem capacidades globais **inerentes** e não têm login. A
assertiva não pode falhar apenas porque eles existem — nem se pode ignorar
genericamente todo nome iniciado por `pg_`. Por isso há uma **lista explícita**
de papéis predefinidos conhecidos: sua existência é **registrada** como
informação, não classificada como aplicação inesperada.

O que **bloqueia** é o risco real: `anon`, `authenticated`, `service_role` ou
qualquer papel **com login fora da allowlist** poder **herdar** (`pg_has_role …
'USAGE'`) ou **assumir via `SET ROLE`** (`… 'MEMBER'`) um papel predefinido. Na
validação normal dos objetos, só são avaliados papéis que podem **atuar de fato**
— `rolcanlogin`, membros de um papel com login, ou os papéis de aplicação
conhecidos — ignorando proprietários técnicos e superusuários.

### 10.17 Bloqueio de linha na retentativa

Ao validar `retry_of_event_id` durante o `INSERT`, o evento anterior é lido com
**`FOR SHARE`** — bloqueio de **linha**, nunca da tabela. Sem ele, o evento
anterior poderia sair de `failed` (por exemplo para `cancelled`) entre a
validação e a inserção da nova retentativa, produzindo uma cadeia incoerente. O
`FOR SHARE` impede `UPDATE`/`DELETE` concorrentes daquela linha até o fim da
transação, sem bloquear leituras.

### 10.18 Condições exatas do marcador de hardening

A marca `PREFLIGHT_FASE2A_MARCO1_BLOQUEADO_REQUER_HARDENING_IS_SITE_ADMIN` só é
emitida quando **todas** estas condições são confirmadas: assinatura exata,
retorno `boolean`, linguagem `sql`, volatilidade `stable`, `SECURITY DEFINER`,
hash autoritativo correto, referências qualificadas a `public.site_admins` e
`auth.uid()`, ausência de dependência de `pg_temp` — e a **única** deficiência
ser a ausência de `search_path` fixo. O preflight mantém duas variáveis
separadas (`v_is_admin_autoritativa_ok` e `v_is_admin_sem_search_path`) e um
contador de divergências; `v_requer_hardening` só é verdadeiro quando ambas o
são.

Havendo qualquer outra divergência, o bloqueio geral permanece, **não** se afirma
que a função corresponde ao corpo autoritativo, todas as divergências são
listadas e **não** se recomenda apenas `ALTER FUNCTION`. Esta V11 mantém a
proibição de reescrever `is_site_admin()`; o hardening separado já fixou somente
`search_path = pg_catalog`.

### 10.19 Alinhamento dos objetos comerciais protegidos

Preflight e verificação posterior compartilham o **mesmo conjunto** de objetos
protegidos da base `cba451e`. Na verificação, a ausência ou assinatura divergente
de `public.resolve_commercial_region(text,text)` e
`public.get_current_commercial_formation(text,text)` é **falha** (não aviso):
`v_ok` não é incrementado e o hash é impresso apenas quando presentes. O mesmo
vale para a RPC `create_my_partner_owner_registration(text × 7)` e para as cinco
tabelas comerciais.

### 10.20 Comparação exata dos retornos de função

O tipo de retorno é comparado por **igualdade exata** (`trigger`, `boolean`,
`uuid`, `legal_documents`, `record`) — nunca por substring. Para funções
`RETURNS TABLE`, as colunas de saída são conferidas pelo catálogo
(`proargmodes = 't'`, `proargnames`, `proallargtypes`), comparando **nome, tipo,
ordem e quantidade**. O hash normalizado do corpo continua sendo comparado.

### 10.21 `pg_catalog.gen_random_uuid()` nos defaults

Todos os `DEFAULT` de coluna `id` usam **`pg_catalog.gen_random_uuid()`**
explicitamente. `public.gen_random_uuid()` **não é aceito como alternativa**: o
preflight e a guarda exigem a função do catálogo com assinatura exata e retorno
`uuid`, e a verificação posterior confere a expressão `DEFAULT` de cada coluna
`id`. Isso impede resolução acidental ou *shadowing* por função homônima em
schema pesquisável.

### 10.22 Congelamento do evento que já possui retentativa

Depois que existe um filho com `retry_of_event_id = evento.id`, o evento original
é a **origem da cadeia** e precisa continuar compatível com o filho. No `UPDATE`,
o trigger consulta o filho com `FOR SHARE` (bloqueio de **linha**, nunca da
tabela) e, havendo filho:

- o evento original **deve permanecer `failed`** — `failed → cancelled` e
  qualquer outra transição são recusadas;
- `sent_at`, `provider_message_id`, `channel`, `recipient_user_id`,
  `recipient_address`, `template_key`, `template_data`,
  `correlation_entity_type` e `correlation_entity_id` **não podem ser alterados**,
  porque são exatamente os campos usados para validar a equivalência da cadeia.

A verificação posterior confirma que **todos** os pais referenciados continuam
`failed`, com evidência de envio externo, e coerentes com seus filhos.

### 10.23 Cadeia de retentativas sem ramificação

Cada evento pode ter **no máximo uma** retentativa direta. Isso é garantido por
índice **único parcial**:

```sql
uq_notification_events_retry_parent
  UNIQUE (retry_of_event_id) WHERE retry_of_event_id IS NOT NULL
```

Esse índice **também atende** as consultas por `retry_of_event_id`, portanto o
índice simples anterior (`idx_notification_events_retry`) foi **removido** — não
se mantêm dois índices equivalentes. O total de objetos permanece **47**.

A verificação confirma: índice válido/pronto/ativo, unicidade, coluna exata
(`retry_of_event_id`), sem `INCLUDE`, sem expressão, predicado exatamente
`retry_of_event_id IS NOT NULL`, e ausência de mais de um filho por evento pai
(checada também na assertiva pré-`COMMIT`).

### 10.24 Proteção de `DELETE` em documentos jurídicos

A imutabilidade passou a abranger `DELETE`: o trigger cobre
**`BEFORE INSERT OR UPDATE OR DELETE`** (`tgtype = 31`). Neste marco **nenhum**
`legal_document` pode ser excluído — nem rascunho. Documentos `published` e
`archived` são imutáveis; documentos com aceites vinculados também estão
protegidos pela FK `ON DELETE RESTRICT` de `legal_acceptances`.

A exclusão controlada de rascunhos (nunca publicados, sem aceite, por fluxo
administrativo autorizado) exige uma **RPC administrativa auditada** e será
criada em **migration separada**. Como este marco ainda não a possui, adotou-se a
opção mais segura: bloquear todo `DELETE`. A assertiva e a verificação conferem o
`tgtype` completo e a função exata.

### 10.25 Mensagens condicionais do verificador

Nenhuma mensagem de aprovação (`OK`, "inventário conferido") é impressa quando
qualquer subchecagem do grupo falhou. Cada grupo — tabelas, colunas, constraints,
índices, funções, triggers, policies, ACLs e objetos comerciais protegidos —
mantém contadores próprios e imprime, por exemplo,
`constraints: 45 esperadas / 45 aprovadas / 0 falhas`. O veredito geral continua
listando **todas** as falhas até o fim.

### 10.26 Papéis internos da plataforma Supabase (correção V10, coerência V11)

**Incidente que motivou a V10.** Numa execução da Fundação **V9**, o preflight
retornou limpo, mas a **assertiva final** encontrou 8 divergências e provocou
**ROLLBACK integral antes do `COMMIT`** — nenhuma tabela da Fundação permaneceu
aplicada. As 8 divergências eram `SELECT` efetivo de `supabase_etl_admin` e
`supabase_read_only_user` sobre `legal_documents`, `legal_acceptances`,
`audit_logs` e `notification_events`. **Causa:** esses são papéis **internos
gerenciados pela Supabase**, que recebem leitura global via `pg_read_all_data`;
a V9 classificou-os, de forma ampla demais, como papéis aplicacionais atuantes
inesperados. **Correção:** modelagem explícita desses papéis de infraestrutura.

**Esclarecimentos.**

- Quando esta especificação diz **"somente `service_role`"**, isso vale **entre
  os papéis de aplicação e de backend do projeto** (`anon`, `authenticated`,
  `service_role`). Não se refere aos papéis internos da plataforma.
- Papéis internos gerenciados pela Supabase **podem** possuir o acesso global de
  leitura necessário à infraestrutura (ETL, réplica de leitura). Esse acesso
  **não** é acessível pelo navegador, **não** substitui policies nem as
  autorizações da aplicação, e é estritamente **`SELECT`** efetivo derivado de
  `pg_read_all_data`.
- A **allowlist é exata e fail-closed**: apenas os dois nomes
  `supabase_etl_admin` e `supabase_read_only_user` recebem esse tratamento —
  **nunca** um padrão amplo por prefixo `supabase_`. A exceção só vale quando o
  papel existente satisfaz o perfil esperado (`rolsuper=false`,
  `rolcanlogin=true`, `rolbypassrls=true`, `rolreplication` = `true` para
  `supabase_etl_admin` e `false` para `supabase_read_only_user`, membro de
  `pg_read_all_data` e **não** membro de `pg_write_all_data`). Perfil divergente
  **bloqueia**; ausência do papel **não** bloqueia (e a migration **não** o cria).
- Para esses papéis, permite-se **exclusivamente `SELECT` efetivo**. Qualquer
  `INSERT`/`UPDATE`/`DELETE`/`TRUNCATE`/`REFERENCES`/`TRIGGER` efetivo, ou
  qualquer **ACL direta** concedida especificamente a eles, continua
  **bloqueando**. A permissão aceita vem **somente** da capacidade global de
  leitura da plataforma.
- **Isolamento preservado:** `anon`, `authenticated` e `service_role` **não**
  podem herdar (`USAGE`) nem assumir (`MEMBER`/`SET ROLE`) esses papéis internos,
  nem `pg_read_all_data`/`pg_write_all_data`. **Papéis desconhecidos continuam
  bloqueados** — nenhum outro papel atuante pode possuir privilégio efetivo nas
  tabelas brutas. A migration **não cria, não altera nem revoga** papéis internos.

**Onde isso vive no pacote.** Preflight (seção `[13]`): apresenta existência,
OID, `rolcanlogin`, `rolsuper`, `rolbypassrls`, `rolreplication`, memberships em
`pg_read_all_data`/`pg_write_all_data` e a possibilidade de herança/assunção
pelos papéis de aplicação — bloqueando perfil divergente. Fundação (assertiva
final `H.0b` e `H.6`): valida perfil/memberships e permite só `SELECT` efetivo.
Verificação posterior (`10b` e matriz `10g`): confirma, por tabela, `SELECT`
efetivo verdadeiro e os demais privilégios falsos, sem ACL direta, sem acusar os
oito `SELECT` esperados como falha.

**Correção de coerência (V11).** A revisão da V10 encontrou um bloqueio residual:
a seção `[10f]` da verificação posterior (papéis com login que podem assumir um
predefinido) ainda capturava `supabase_etl_admin` e `supabase_read_only_user`
como inesperados, pois ambos têm login e são membros de `pg_read_all_data`. A V11
exclui **apenas** esses dois nomes exatos de `[10f]`
(`and not (r.rolname = any(v_supabase_read_roles))`, nunca por prefixo), mantendo
a captura de qualquer terceiro papel com login. A validação dos dois papéis foi
**centralizada** na nova seção `[10h]` (perfil, memberships, isolamento e matriz
por tabela), fail-closed, com cada condição participando do veredito; a seção
`[10b]` apenas os ignora para não gerar falso positivo sobre o `SELECT` global.
A V11 também eliminou a **duplicidade de `[10g]`**: `[10g]` volta a ser
exclusivamente os defaults de `pg_catalog.gen_random_uuid()`, e os papéis
internos passam a `[10h]`. Cada etapa (preflight `[13]`, assertiva `H.0b`/`H.6`,
verificação `[10h]`) valida os mesmos requisitos.

**Matriz de equivalência (papéis internos) — preflight `[13]` · assertiva
`H.0b`/`H.6` · verificação `[10h]`.** Todos os requisitos são validados nas três
etapas:

| # | Requisito | Preflight [13] | Assertiva H.0b/H.6 | Verificação [10h] |
|---|---|---|---|---|
| 1 | Nome exato (allowlist, sem prefixo) | ✔ | ✔ | ✔ |
| 2 | Existência (ausência não bloqueia) | ✔ | ✔ | ✔ |
| 3 | `rolsuper=false` | ✔ | ✔ | ✔ |
| 4 | `rolcanlogin=true` | ✔ | ✔ | ✔ |
| 5 | `rolbypassrls=true` | ✔ | ✔ | ✔ |
| 6 | `rolreplication` (etl=true, read_only=false) | ✔ | ✔ | ✔ |
| 7 | Membro de `pg_read_all_data` | ✔ | ✔ | ✔ |
| 8 | Não membro de `pg_write_all_data` | ✔ | ✔ | ✔ |
| 9 | Isolamento de `anon` (USAGE/MEMBER) | ✔ | ✔ | ✔ |
| 10 | Isolamento de `authenticated` (USAGE/MEMBER) | ✔ | ✔ | ✔ |
| 11 | Isolamento de `service_role` (USAGE/MEMBER) | ✔ | ✔ | ✔ |
| 12 | `SELECT` efetivo por tabela = true | ✔¹ | ✔ | ✔ |
| 13 | Ausência dos seis privilégios adicionais | ✔¹ | ✔ | ✔ |
| 14 | Ausência de ACL direta específica | ✔¹ | ✔² | ✔ |

¹ No preflight, os itens 12–14 usam a mesma lógica, mas as quatro tabelas ainda
não existem antes da fundação; a matriz então não se aplica (curto-circuito por
`to_regclass(...) is null`), permanecendo estruturalmente equivalente.
² Na assertiva, a ACL direta a qualquer papel diferente do proprietário e de
`service_role` já é barrada no laço de grants diretos de `H.6`, o que inclui os
papéis internos.

### 10.27 Marcadores de versão: escopo da conferência

A conferência de marcadores desatualizados é **validação estática do
repositório**, feita por busca textual nos quatro arquivos. O verificador roda no
banco e **não** tem acesso ao conteúdo dos arquivos locais — por isso não afirma
mais nada a respeito, e nenhuma consulta SQL é usada para isso. Marcadores
proibidos quando descrevem a versão atual: `(V7)`, `(V8)`, `esta proposta (V7)`,
`este pacote (V7)`, `esta proposta (V8)`, `este pacote (V8)`. Referências
históricas só permanecem quando explicitamente identificadas como descrição de
versão anterior.

## 11. Política de auditoria

`audit_logs` registra ator, papel, ação, entidade, identificador, estado anterior
e posterior, justificativa, correlação, data/hora, origem técnica e metadados.

Imutabilidade em duas camadas: **triggers** que bloqueiam `UPDATE`/`DELETE` (para
qualquer papel, inclusive administrador) e **ausência de grants** de escrita para
`anon`/`authenticated`. Leitura é administrativa via RLS (`is_site_admin()`).
Gravação apenas por `write_audit_log(...)`, `security definer`, **revogada de
todos os papéis do cliente** — chamável somente por outras funções server-side
ou pela `service_role` do backend. Correções são **novos registros** ligados ao
anterior por `corrects_log_id`.

## 12. Política provisória de retenção

| Categoria | Prazo operacional provisório |
|---|---|
| Histórico comercial | 5 anos após o encerramento |
| Logs administrativos e de auditoria | 10 anos |
| Documentos de solicitação rejeitada sem contrato | 180 dias, salvo disputa, fraude ou obrigação aplicável |
| Documentos de empresa aprovada | Durante a relação + 5 anos |
| Dados desnecessários | Eliminar ou anonimizar antes dos prazos quando não houver finalidade |

**Provisório:** exige revisão jurídica e de proteção de dados antes do lançamento
público. Nenhuma rotina de expurgo é criada neste marco.

## 13. Integração futura com Storage privado

Hoje **não existe bucket algum** no projeto. Previsto para o Marco 2: bucket
**privado** (ex.: `partner-documents`), sem leitura pública; caminho por
solicitação (`{application_id}/{document_id}/{versao}`); upload e download por
**URL assinada de curta duração**, emitida server-side após checagem de
permissão; metadados e status em `application_documents`; nenhum documento
pessoal completo trafega por e-mail ou WhatsApp. Este marco **não cria nem
altera buckets**.

## 14. Riscos de contas órfãs

Risco: criar usuário no Auth sem solicitação empresarial correspondente (ou o
inverso), gerando contas sem vínculo, cobrança de suporte e confusão na análise.

Mitigações previstas: a solicitação **precede** a conta; a conta provisória só é
criada após confirmação do e-mail vinculada a uma solicitação existente;
promoção da mesma conta na aprovação (**nunca** criar usuário duplicado);
reconciliação administrativa listando usuários Auth sem solicitação e
solicitações sem usuário; e o índice único parcial deste marco impedindo dois
perfis para o mesmo usuário. Enquanto o novo fluxo não existir, `/parceiros`
segue **login-only** e o cadastro público continua desativado.

## 15. Riscos de duplicidade de `auth_user_id`

Hoje a coluna é `null` com **índice comum** (`idx_site_profiles_auth`), sem
unicidade: dois perfis podem apontar para o mesmo usuário, quebrando "uma conta
por pessoa", RLS baseada em perfil e a promoção da conta provisória.

Tratamento: **preflight obrigatório** detecta duplicidades e emite
`PREFLIGHT_FASE2A_MARCO1_BLOQUEADO` com as linhas para revisão; a migration
**repete a defesa** e **interrompe com exceção** se houver conflito — não
corrige, não mescla, não exclui, não escolhe vencedor. Em caso limpo, cria
`uq_site_profiles_auth_user_id` **UNIQUE ... WHERE auth_user_id IS NOT NULL**,
sem tornar a coluna `NOT NULL` e sem apagar índices existentes.

## 16. Plano incremental dos marcos posteriores

| Marco | Entrega | Banco |
|---|---|---|
| **1 (este)** | Especificação + fundação transversal + preflight/verificação | `legal_documents`, `legal_acceptances`, `audit_logs`, `notification_events`, índice único parcial |
| 2 | Cadastro e conta provisória | `partner_applications`, `application_documents`; bucket privado |
| 3 | Admin de empresa e owner | `application_reviews`, `partner_owner_authority_reviews` |
| 4 | Waitlists | `territorial_waitlist_entries`, `sales_waitlist_entries`, `waitlist_events`, `waitlist_rotation_policies`, calendário de feriados e horas úteis server-side |
| 5 | Unidades e managers | `partner_units`, `unit_member_permissions`, `manager_invitations`, `state_managers` |
| 6 | Segurança e notificações | desafios de ação sensível, encerramento de sessões, integração de canal |
| 7 | Homologação | typecheck, build, testes, rotas, refresh, mobile, concorrência, segurança |

Cada marco: SQL apresentado antes de qualquer execução, portão de autorização,
branch separada e `main` limpa.

## 17. Migration fail-closed e rollback conceitual

**A migration NÃO é idempotente — por decisão de projeto.** A estratégia é
*fail-closed*:

- não usa `CREATE OR REPLACE` para as funções deste marco;
- não usa `DROP TRIGGER IF EXISTS` nem `DROP POLICY IF EXISTS`;
- não usa `CREATE ... IF NOT EXISTS` para os objetos deste marco;
- um **bloco de guarda inicial** interrompe a execução se qualquer objeto
  proposto (tabela, view, índice, função, trigger ou policy) já existir, listando
  os conflitos. Nada é substituído, removido ou adaptado automaticamente;
- reexecutar depois de uma aplicação bem-sucedida **falha de propósito** — o que
  é o comportamento desejado: uma segunda execução significa estado inesperado.

O arquivo é transacional (`begin/commit`): se qualquer instrução falhar, nada é
aplicado. É aditivo — sem `DROP TABLE`, `TRUNCATE`, `DELETE` ou `UPDATE` de
dados pré-existentes; a única alteração sobre objeto anterior é a **criação** do
índice único parcial em `site_profiles`.

**Rollback:** remover policies e triggers criados, `drop table` das quatro
tabelas novas, `drop function` das funções novas (incluindo as RPCs sanitizadas)
e `drop index uq_site_profiles_auth_user_id`. Esta proposta não cria views. Nenhum objeto
pré-existente precisa ser restaurado, porque nenhum foi modificado. Atenção: se
as tabelas já contiverem aceites ou logs, **exporte antes** — têm valor
probatório.

### 17.1 Limitações reais e estratégia de verificação

A verificação confere **estrutura e definição**, não comportamento:

- **não prova** que a RLS bloqueia um cliente real (exigiria JWT de
  `anon`/`authenticated` em runtime, previsto para os marcos seguintes);
- **não testa concorrência** (publicação simultânea, corrida de idempotência,
  retentativa paralela);
- **não valida** conteúdo jurídico nem regra de negócio.

**Estratégia de hash das funções.** Assinatura, retorno, linguagem,
volatilidade, `SECURITY DEFINER` e `search_path` não bastam para provar que uma
RPC é segura: o corpo poderia ter sido reescrito. Por isso o verificador
carrega o **md5 esperado de `pg_proc.prosrc`** de cada uma das 13 funções,
calculado a partir do corpo exato definido na fundação. Qualquer alteração do
corpo é detectada — inclusive reformatação sem mudança semântica, o que é
**intencional**: qualquer divergência exige nova revisão humana. Além do hash,
há checagens estruturais independentes (presença de `auth.uid()`, filtro pelo
usuário autenticado, `published`/`archived` na sobreposição, conflito explícito,
contexto fixo) e a confirmação de que colunas internas (`evidence`, `ip`,
`user_agent`, `template_data`, `provider`, `error_*`, `notes`, `published_by`)
**não** aparecem no corpo das RPCs sanitizadas.

**Demais reforços da verificação.** Índices são lidos pelos catálogos
(`indkey`, `indnkeyatts`, `indnatts`, `pg_get_indexdef(oid, posição, true)`,
`pg_get_expr(indpred, ...)`) — sem parsing textual do `indexdef` — conferindo
validade (`indisvalid`/`indisready`/`indislive`), método de acesso, unicidade,
ordem exata das colunas, predicado e ausência de `INCLUDE` ou expressões
inesperadas. FKs usam `attnum = ANY(conkey)`, cobrindo FKs compostas. Triggers
comparam o **`tgtype` integral** e o `tgfoid` resolvido por `to_regprocedure`.
Policies exigem o **conjunto exato** (nenhuma adicional), roles exatas e
comparação canônica de `USING` e `WITH CHECK` **avaliados separadamente**. ACLs
são lidas de `relacl`/`proacl` com `aclexplode` e `acldefault`, distinguindo
grant direto de privilégio herdado de `PUBLIC`.

Objeto ou coluna ausente vira **falha** e a execução continua até o fim;
consultas dinâmicas só rodam após confirmar tabela **e** colunas; `v_ok` só
incrementa quando todas as checagens do objeto passam. Predicados e expressões
são comparados de forma **canônica** (minúsculas, sem espaços e sem
parênteses), o que preserva colunas, operadores, valores e ordem, mas ignora a
parentetização.

## 18. Objetos existentes que permanecerão intocados

`create_my_partner_owner_registration(...)`; `commercial-foundation-v1.sql` e as
cinco tabelas comerciais da Fase 1 (`commercial_regions`,
`commercial_region_cities`, `commercial_niches`, `commercial_exclusivities`,
`commercial_opportunities`) e suas RPCs; `site-schema-v2.sql` e
`site-partner-core.sql` (incluindo `site_profiles`, `site_monthly_partners`,
`site_partner_members`, `is_site_admin`, `somente_digitos` e triggers de
proteção); preços, fidelidade, contratos, pagamentos; rotas antigas
(`/classica`, `/produtos`, `/produto/:slug`, `/personalizar/:slug`, `/checkout`,
`/selecionar-estado`); `src/App.tsx`, páginas React, guards e hooks de
autenticação; Storage remoto e configuração do Supabase Auth; `package.json` e
`package-lock.json`.

**Isolamento do legado (apenas documentado, sem remoção):** as regras revogadas —
loja de camisas, formações 100/90, farmácia com 18, ciclo de 30 dias, venda
parcial, desconto progressivo (`desconto_para_cnpj`, `desconto_quantidade`,
`faixas_quantidade`), mais de um nicho por CNPJ na mesma exclusividade, waitlist
única e Site administrando a jornada operacional — **não devem ser reutilizadas**
por nenhum código da Fase 2A. Nenhuma tabela, função ou rota antiga é removida,
alterada ou limpa neste marco.

## 19. Critérios de aceite do Marco 1

1. Base em `cba451e`; branch `fase2a/marco1-especificacao-sql`; apenas quatro
   arquivos novos; nenhum arquivo existente modificado.
2. Preflight **somente leitura**, roda por completo mesmo sem
   `site_profiles`/`auth_user_id`, com Seção B comentada.
3. Preflight e guarda **BLOQUEIAM** quando faltar `anon`, `authenticated`,
   `service_role`, `auth.uid()` (retornando `uuid`), `auth.users` (tabela com
   `id uuid`), `gen_random_uuid()`, ou quando `service_role` não tiver
   `rolbypassrls = true`, ou quando `is_site_admin()` não for `boolean`,
   `SECURITY DEFINER` e com `search_path` seguro (sem `pg_temp`, sem `"$user"`,
   sem schema não confiável; com `public` apenas se `PUBLIC`/`anon`/
   `authenticated` não tiverem `CREATE`).
4. Objetos propostos já existentes **e** os artefatos antigos
   (`my_notifications`, `my_legal_acceptances`, `legal_documents_public`) são
   **BLOQUEIO** — listados, sem remoção automática, exigindo análise manual.
5. Fundação transacional e **fail-closed**, repetindo as dependências
   essenciais antes de criar qualquer objeto.
6. Novas funções com **`search_path = pg_catalog`** e objetos externos
   totalmente qualificados.
7. `legal_documents`: `draft` nunca vai a `archived`; `archived` só a partir de
   `published`, com vigência encerrada; sobreposição barrada contra
   `published` **e** `archived`; histórico sem versões futuras.
8. `legal_acceptances`: `linked_auth_user_id` imutável sem FK; `auth_user_id`
   com `ON DELETE SET NULL`; promoção única; revogação imutável com motivo
   obrigatório.
9. `notification_events`: congelamento avaliando estado **antigo ou novo**;
   `sending` exige aumento de `attempt_count`; `scheduled_for` reescrito apenas
   em `failed → scheduled`; matriz explícita de transições; terminais não
   retornam.
10. RPC pública de aceite **sem contexto escolhido pelo navegador**, restrita a
    `privacy_notice` e `provisional_account_terms`, com conflito explícito.
11. Nenhuma view; nenhuma tabela bruta acessível a `PUBLIC`/`anon`/
    `authenticated`; `service_role` com `REVOKE ALL` prévio e privilégios
    exatos, sem `DELETE`/`TRUNCATE`/`REFERENCES`/`TRIGGER`.
12. Verificação posterior somente leitura, continua até o fim, e confere ACLs
    diretas, índices por catálogo, FKs por `ANY(conkey)`, triggers por `tgtype`
    e `tgfoid`, policies exatas e **md5 do corpo** de todas as 13 funções.
13. `npm ci`, typecheck, build e a suíte atual passam.
14. Nenhum SQL executado; nenhum commit, push, PR, merge ou deploy.

## 20. Decisões ainda abertas (bloqueiam marcos seguintes, não este)

- Provedor de e-mail transacional e mecanismo concreto de confirmação de e-mail
  (Auth nativo vs. código próprio).
- Nome e política do bucket privado de documentos.
- Fonte oficial de feriados nacionais/estaduais/municipais para as 48 horas
  úteis.
- Provedor de WhatsApp.
- Textos jurídicos definitivos — hoje **placeholders**; nenhum conteúdo jurídico
  foi redigido neste marco.
- Regra de dezembro.
- Destino final de `/classica` e do schema de desconto progressivo.
- **Exclusão de sobreposição de vigência:** manter a trigger com advisory lock
  ou adotar `EXCLUDE USING gist` com a extensão `btree_gist` (exige habilitar a
  extensão no projeto).
- **Acesso administrativo às tabelas brutas:** hoje só por `service_role`; falta
  decidir se o Marco 3 usará RPCs administrativas dedicadas ou grants explícitos
  a um role de administrador.
- **Retenção de aceites de contas encerradas:** exclusão de `auth.users` apenas
  desvincula (`SET NULL`); falta definir política de anonimização.

## 21. Inventário completo dos objetos criados (cobertura fail-closed)

Todo objeto criado pela fundação aparece no **inventário fail-closed do**
**preflight**, na **guarda inicial da fundação** e na **verificação posterior**.
A tabela abaixo é o inventário canônico desta proposta.

### 21.1 Tabelas (4)

- `public.legal_documents`
- `public.legal_acceptances`
- `public.audit_logs`
- `public.notification_events`

### 21.2 Índices (17)

- `uq_legal_documents_vigente` *(unique)*
- `idx_legal_documents_type_status`
- `uq_legal_acceptances_ativo` *(unique)*
- `idx_legal_acceptances_subject`
- `idx_legal_acceptances_auth_user`
- `idx_legal_acceptances_linked`
- `idx_legal_acceptances_doc`
- `idx_audit_logs_entity`
- `idx_audit_logs_actor`
- `idx_audit_logs_occurred`
- `idx_audit_logs_correlation`
- `uq_notification_events_idempotency` *(unique)*
- `idx_notification_events_status`
- `idx_notification_events_recip`
- `idx_notification_events_correl`
- `uq_notification_events_retry_parent` *(unique, parcial: `WHERE retry_of_event_id IS NOT NULL`)*
- `uq_site_profiles_auth_user_id` *(unique)*

### 21.3 Funções (13)

- `public.fase2a_touch_updated_at()`
- `public.legal_documents_check_overlap()`
- `public.legal_documents_protect()`
- `public.legal_acceptances_protect()`
- `public.audit_logs_block_mutation()`
- `public.notification_events_protect()`
- `public.current_legal_document(p_doc_type text)`
- `public.get_current_legal_documents()`
- `public.legal_document_versions(p_doc_type text)`
- `public.get_my_legal_acceptances()`
- `public.get_my_notifications()`
- `public.record_legal_acceptance(p_doc_type text, p_declared_data jsonb)`
- `public.write_audit_log(...)`

### 21.4 Triggers (9)

- `trg_legal_documents_updated` — `BEFORE UPDATE` em `public.legal_documents`
- `trg_legal_documents_overlap` — `BEFORE INSERT OR UPDATE` em `public.legal_documents`
- `trg_legal_documents_protect` — `BEFORE INSERT OR UPDATE OR DELETE` em `public.legal_documents`
- `trg_legal_acceptances_protect_upd` — `BEFORE UPDATE` em `public.legal_acceptances`
- `trg_legal_acceptances_protect_del` — `BEFORE DELETE` em `public.legal_acceptances`
- `trg_audit_logs_no_update` — `BEFORE UPDATE` em `public.audit_logs`
- `trg_audit_logs_no_delete` — `BEFORE DELETE` em `public.audit_logs`
- `trg_notification_events_updated` — `BEFORE UPDATE` em `public.notification_events`
- `trg_notification_events_protect` — `BEFORE INSERT OR UPDATE` em `public.notification_events`

### 21.5 Policies (4)

- `legal_documents_admin_all` em `public.legal_documents`
- `legal_acceptances_select_own` em `public.legal_acceptances`
- `audit_logs_admin_read` em `public.audit_logs`
- `notification_events_select_own` em `public.notification_events`

**Total: 47 objetos.** Nenhum objeto criado fica sem cobertura nos três
arquivos. A matriz `objeto | preflight | guarda | pós-verificação` é conferida
a cada revisão do pacote.
