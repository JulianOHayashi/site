# R16 — Worker do outbox de e-mail: operação

Documento de entrega operacional do Checkpoint 4. Descreve como executar,
como interpretar a saída e o que **não** está pronto.

---

## 1. O que o worker faz

Transmite os e-mails transacionais do outbox do Site. Escopo restrito a três
templates, e a restrição é estrutural, não de configuração:

```
partner_application_email_verification
partner_application_account_claim
manager_invite
```

Só esses três têm operação canônica de **posse atômica** (`svc_mint_*`). Sem
posse, o worker não transmite — descobrir uma linha nunca autoriza enviá-la.
Qualquer outro template é contabilizado como `unsupported` e fica inteiramente
fora do domínio do worker: nada é enviado, reivindicado, marcado ou
reagendado.

Sequência obrigatória por evento:

```
descobrir → svc_mint_* (claim) → renderizar → transmitir por SMTP
          → svc_mark_notification_sent | _failed + svc_reschedule
```

Nenhum `UPDATE` direto em `notification_events`. Teto de tentativas e
expiração de lease são autoridade exclusiva do banco.

---

## 2. Build e execução

```bash
npm ci
npm run build:worker      # gera dist-worker/main.mjs (ESM, target node22)
npm run worker:once       # um ciclo e sai — uso previsto: cron
npm run worker            # polling até SIGINT/SIGTERM
```

`dist-worker/` não é versionado. Dependências ficam **externas** ao bundle:
`node_modules` precisa existir no runtime, e a versão em uso continua sendo a
do lockfile em vez de uma cópia embutida.

Runtime declarado: **Node 22**.

---

## 3. Modos

| Modo | Ativação | Comportamento |
|---|---|---|
| one-shot | `--once` ou `WORKER_ONE_SHOT=1\|true` | Exatamente **um** ciclo, mesmo que sobre trabalho. Previsível para cron. |
| polling | padrão | Ciclos separados por `WORKER_POLL_INTERVAL_MS`, até receber sinal. |

---

## 4. Códigos de saída

| Código | Significado | Reiniciar resolve? |
|---:|---|---|
| 0 | Ciclo concluído, ou parada cordial atendida | — |
| 1 | Exceção não tratada (código padrão do Node) | Talvez; investigar |
| 2 | Configuração inválida | **Não.** Exige intervenção |
| 3 | Falha de infraestrutura em execução (descoberta, RPC) | Provavelmente; use backoff |

`1` é deixado para o Node de propósito: distinguir falha declarada nossa de
exceção imprevista tem valor operacional.

Em código 2, a saída traz apenas o **código** do erro de configuração
(`missing_required_env`, `unsupported_smtp_mode`, `insecure_site_base_url`,
`staging_recipient_safety_missing`, …) — nunca o valor ofensor.

---

## 5. Parada cordial

`SIGINT` e `SIGTERM` pedem parada. O sinal é conferido entre ciclos e cancela
a espera do intervalo, mas **um ciclo já iniciado termina**.

Abortar no meio deixaria eventos em `sending` com posse concedida e sem
desfecho registrado — órfãos até o lease expirar. Esperar o ciclo é mais lento
e mais correto. Dimensione o `terminationGracePeriod` do orquestrador acima da
duração típica de um ciclo.

Um segundo sinal não altera o motivo do primeiro nem acelera a parada.

Falha de infraestrutura **interrompe** o laço com código 3 em vez de repetir a
cada intervalo. Insistir esconderia a falha em log repetido; a decisão de
reinício com backoff pertence ao orquestrador.

---

## 6. Configuração

Nomes completos em `.env.example`. Pontos que falham fechado:

- **Segredo sob prefixo público** (`VITE_*`, `NEXT_PUBLIC_*` contendo
  `SERVICE_ROLE`, `SMTP_PASSWORD`, `SECRET`, …) é **rejeitado**, não aceito com
  aviso. É a barreira que impede a chave de service_role de entrar no bundle
  do navegador.
- **`SITE_BASE_URL`** precisa ser `https` fora de desenvolvimento, sem
  credenciais embutidas. É a única origem permitida nos links de ação.
- **`SMTP_MODE`** aceita `implicit_tls` (produção) e `plaintext_local_only`
  (apenas desenvolvimento, e AUTH é recusado sobre ele).
  `starttls` é **recusado** com `unsupported_smtp_mode` — ver §8.
- **`WORKER_BATCH_SIZE` ≥ 2** e `1 ≤ WORKER_RECOVERY_RESERVE < BATCH_SIZE`.
  A garantia de que trabalho normal e sondagem de recuperação nunca privam um
  ao outro é estrutural, válida em toda consulta, independente de reinícios.
  Valor inválido é rejeitado, nunca normalizado.
- **Staging exige** exatamente uma de `STAGING_RECIPIENT_OVERRIDE` ou
  `STAGING_RECIPIENT_ALLOWLIST`. Sem nenhuma, o worker **não sobe**. Sem isso,
  um smoke de staging apontado para o banco real enviaria e-mail a clientes
  de verdade, e o erro só apareceria depois da entrega.
- **Produção não herda** política de staging: `STAGING_RECIPIENT_*` com
  `ENVIRONMENT=production` é erro de configuração, não atalho.

---

## 7. TLS

Verificação de certificado e de hostname são fixadas em código, não em
configuração. Não existe caminho — nem variável de ambiente, nem opção de
worker — capaz de produzir `rejectUnauthorized: false`.

Barreiras verificadas antes de cada handshake:

- `rejectUnauthorized: true`, `servername` para SNI e verificação de nome,
  `minVersion: TLSv1.2`;
- `checkServerIdentity` não pode ser substituído;
- `NODE_TLS_REJECT_UNAUTHORIZED=0` no ambiente faz a conexão **falhar** — é um
  interruptor de processo que anularia silenciosamente a opção;
- `tlsSock.authorized` é conferido no `secureConnect` como segunda barreira.

Credencial SMTP nunca trafega fora do estado cifrado aprovado, e a autoridade
sobre "estar cifrado" é o **socket**, não o modo configurado. Mecanismo AUTH
não anunciado no EHLO também impede o envio da credencial.

---

## 8. Log e diagnóstico

Log estruturado em JSON, uma linha por evento, por **allowlist de campos**:
campo desconhecido é descartado, não sanitizado. Senha SMTP e chave de
service_role entram como termos a mascarar — segunda barreira.

Eventos: `worker_start`, `worker_cycle_start`, `worker_cycle_end`,
`worker_event_skipped`, `worker_smtp_outcome`, `worker_row_rejected`,
`worker_cycle_failed`, `worker_shutdown`, `worker_exit`,
`worker_config_invalid`, `worker_unhandled`.

Nunca aparecem em log: token cunhado, endereço do destinatário, corpo da
mensagem, dados do template, credencial, carga AUTH codificada, mensagem crua
de exceção, stack trace.

Não há impressão digital de destinatário. Uma versão anterior emitia um hash
polinomial de 32 bits do local part com o domínio em texto claro e chamava
isso de irreversível — a afirmação era falsa. O campo foi **removido** em vez
de fortalecido:

```
R16_RECIPIENT_FINGERPRINT_POLICY=OMITTED_UNLESS_REQUIRED
```

Etiquetas de erro preservam a natureza do desfecho, e a distinção importa para
diagnóstico:

```
smtp_temporario_<codigo>_<fase>   recusa 4xx do servidor
smtp_permanente_<codigo>_<fase>   recusa 5xx do servidor
smtp_transporte_<codigo>_<fase>   falha de transporte — NÃO é recusa
render_<codigo>                   mensagem não pôde ser montada
recipient_not_in_staging_allowlist  bloqueio de ambiente, zero transmissão
```

`provider_message_id` recebe o texto da resposta final do servidor,
sanitizado e limitado — SMTP não define id canônico, e provedores costumam
embutir a chave da fila ali. Sem texto aproveitável, cai para a chave de
idempotência.

---

## 9. Declarado e adiado

Itens reais, não notas de rodapé. Nenhum deles é contornado em silêncio.

- **`R16_STARTTLS_SUPPORT=NOT_IMPLEMENTED`** — não existe upgrade de socket,
  re-EHLO nem detecção de capacidade. A configuração recusa o modo. Um modo
  seguro correto vale mais que dois incompletos. Provedores que exigem
  STARTTLS na 587 não são atendidos nesta versão; use TLS implícito na 465.
- **`R16_PERMANENT_FAILURE_FAST_FAIL=DEFERRED`** — o contrato
  `EmailTransport` do R13 devolve apenas ok/erro, e `dispatchPending`
  reagenda **toda** falha. Uma recusa 5xx permanente é portanto reagendada
  até o teto de tentativas do banco convertê-la em `failed`. A etiqueta de
  erro registra a natureza permanente na coluna, então o diagnóstico não se
  perde, mas há tentativas inúteis. Corrigir exige mudar o contrato do
  despachante ou acrescentar método ao gateway — fora do escopo do CP4, que
  não altera despacho nem schema.
- **`R16_AUTH_MECHANISMS=PLAIN_ONLY`** — apenas AUTH PLAIN, o único
  implementado e testado. LOGIN, CRAM-MD5 e XOAUTH2 não existem.
- **`R16_GENERIC_NOTIFICATION_CLAIM=DEFERRED`** — ampliar além dos três
  templates exige uma RPC de claim genérica e mudança de schema.
- **`R16_REAL_PROVIDER_SMOKE=PENDING`** — nenhum envio real a provedor
  externo foi executado. As provas de TLS usam servidor local com material de
  teste gerado em runtime. O primeiro smoke contra provedor real precisa
  ocorrer em staging, com `STAGING_RECIPIENT_OVERRIDE` obrigatoriamente
  configurado.

---

## 10. Verificação

```bash
npm run typecheck
npm run test                          # suíte completa
npm run build                         # artefato de navegador
npm run build:worker                  # artefato de worker
bash scripts/audit/secret-scan.sh
bash scripts/audit/worker-smoke.sh    # processo real: exit codes e sinais
node scripts/check-no-legacy.mjs
```

O smoke de worker é a única prova de comportamento de **processo**. Ele existe
porque um defeito dessa classe já passou por toda a suíte unitária: o
temporizador do intervalo era `unref`, o laço de eventos esvaziava e o
processo terminava sozinho depois do primeiro ciclo — com código 0, o que
fazia a falha parecer sucesso. Sob Vitest o processo segue vivo por outros
motivos, então nenhum teste unitário podia detectá-lo.
