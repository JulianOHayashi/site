# Relatório final — Reconciliação M1 canônico → M2 (R0–R14)

**Branch:** `recon/m1-m2-launch`
**Base canônica (fundação obrigatória):** `5cf545001367565ff26973eb33f10b6414f9067c`
**HEAD da reconciliação:** ver `inventario/COMMITS.txt` (último commit da série)
**Data:** 2026-08-22

---

## 1. Veredito

A série está **verde localmente** e é **puramente aditiva sobre o M1 canônico**.
Nenhuma migração canônica foi modificada ou removida; nenhum arquivo crítico de
segurança do M1 foi alterado; os 130 testes canônicos do M1 continuam passando
com os arquivos byte a byte idênticos à base.

**O gate final NÃO foi executado.** Ver secção 7.

    SUPABASE_PG17_FINAL_GATE = PENDING_EXTERNAL_EXECUTION

---

## 2. Números

| Métrica | Valor |
|---|---|
| Commits na série (base → HEAD) | 16 |
| Arquivos alterados | 61 (`+10905` / `−52`) |
| Migrações canônicas modificadas | **0** |
| Migrações adicionadas (aditivas) | 11 |
| Testes vitest | **268 PASS / 0 FAIL** (21 arquivos) |
| — dos quais canônicos do M1 | **130 PASS / 0 FAIL** (12 arquivos) |
| Checks SQL executados | **348 PASS / 0 FAIL** (13 suítes) |
| Mutantes plantados / mortos | **8 / 8** |
| Padrões de varredura de segredo | 9 (controles positivo e negativo verdes) |
| `npm run typecheck` | limpo |
| `npm run build` | ok |
| Árvore de trabalho ao final | limpa |

---

## 3. Preservação do M1 canônico (verificado, não afirmado)

| Verificação | Resultado |
|---|---|
| `git diff BASE..HEAD -- supabase/migrations/` | somente linhas `A` (adições) |
| `PortalGuard.tsx` | idêntico à base |
| `safeInternalDestination.ts` | idêntico à base |
| `PortalLogin.tsx`, `App.tsx` | idênticos à base |
| `vite.config.ts`, `vitest.config.ts`, `tsconfig.json` | idênticos à base |
| `package.json` | apenas dois scripts `db:*:aux` acrescentados; **nenhuma dependência alterada** |
| `react-router-dom` | permanece `7.18.2` |
| 13 suítes de teste canônicas | byte a byte idênticas à base |
| `refs/m1/onboarding-fase2a` | intocado, aponta para `5cf5450` |
| Primitivas `m1_*` no banco | presentes (suíte 900, check 7) |

O único arquivo `src/` canônico com mudança de comportamento é
`partnerApplicationService.ts`, e a mudança é a regra de integração central
descrita na secção 4.

---

## 4. A regra de integração: o vínculo durável só **ELEVA**

`obterContextoConta` consulta **primeiro** a RPC canônica de candidatura, que
continua decidindo os vereditos do M1 (`erro`, `provisoria`,
`sem_contexto_parceiro`). Só depois o vínculo durável do M2 é consultado, e ele
só pode transformar o veredito em `parceiro_autorizado`. Falha da RPC, formato
inesperado ou lista vazia **não concedem nada** — o veredito do M1 permanece, e
todo veredito do M1 nega o Portal.

Isso é o que torna a integração segura sem tocar no `PortalGuard`: o guard
canônico não muda porque não precisa mudar.

Coberto por teste de propriedade (nenhuma falha do contexto durável produz
autorização) **e** por mutante: inverter a condição do vínculo durável mata a
suíte `m2ContextoParceiro`.

---

## 5. Achado de segurança corrigido — privilégios isentos de RLS

**Severidade: alta. Origem: baseline canônica. Verificado em campo.**

A baseline traz o padrão do Supabase (`GRANT ALL ON ALL TABLES` e
`ALTER DEFAULT PRIVILEGES ... GRANT ALL ON TABLES`) para `anon` e
`authenticated`.

Para `SELECT/INSERT/UPDATE/DELETE` isso é aceitável, e foi **provado com dados
reais** no harness: semeadas uma linha em `orders` e uma em `payments`, o papel
`anon` enxergou 0 e 0, seu `UPDATE` alterou 0 linhas, seu `DELETE` removeu 0
linhas, e seu `INSERT` foi recusado com *new row violates row-level security
policy*.

`TRUNCATE`, porém, **não passa por RLS**. Executando como `anon`:

    truncate public.orders cascade;       -> PERMITIDO
      (cascateava para invoices, payments, order_items,
       order_cancellations, order_customization_files)
    truncate public.site_admins cascade;  -> PERMITIDO

`TRIGGER` e `REFERENCES` estavam igualmente concedidos e nenhum cliente
PostgREST precisa deles.

**Alcance honesto:** o PostgREST não expõe `TRUNCATE`, então não havia rota HTTP
direta. O privilégio se tornava explorável por qualquer sink de SQL dinâmico,
função `SECURITY INVOKER` mal escrita ou conexão direta com o papel `anon` — e
violava menor privilégio de qualquer modo.

**Correção** (migração aditiva `20260822130000`, a baseline não é tocada):
revoga `TRUNCATE`, `TRIGGER` e `REFERENCES` de `anon` e `authenticated` em todas
as tabelas de `public`, e ajusta o `ALTER DEFAULT PRIVILEGES` para que tabelas
futuras não nasçam com eles. `SELECT/INSERT/UPDATE/DELETE` **não** foram
alterados: são mediados por RLS e a vitrine pública depende de parte deles —
mexer neles é decisão de produto, não de auditoria.

---

## 6. Metodologia — por que estes verdes valem algo

Um teste verde não prova nada sozinho. Três mecanismos sustentam os números:

**Auditoria de mutação** (`scripts/audit/mutation-audit.sh`). Oito invariantes
reais são quebrados um a um, e a suíte correspondente **precisa** falhar:

| Mutante | Suíte que o mata |
|---|---|
| `PortalGuard`: `default` do switch libera | `portalGuardFailClosed` |
| Contexto durável autoriza por falha | `m2ContextoParceiro` |
| `safeInternalDestination` sem checagem de origem | `safeInternalDestination` |
| Consulta a tabela proibida plantada em `src/` | `check:legacy` |
| Sentinela da ponte deixa de falhar | `m2PonteProvisionamento` |
| `CHECK economic = pool + due` enfraquecido | SQL 140 |
| `REVOKE TRUNCATE` removido | SQL 900 |
| Confirmação manual aceita valor ≠ devido | SQL 160 |

Resultado: **8/8 mortos**. O script recusa rodar em árvore suja e restaura toda
mutação, inclusive em erro ou interrupção.

**Controles positivos nos scanners.** O scanner de legado prova, a cada execução,
que detecta um alvo plantado e que **ignora** menção em comentário. O scanner de
segredos valida os 9 padrões contra amostras sintéticas (positivo) e contra
texto comum (negativo) antes de varrer qualquer coisa; foi verificado
ponta a ponta plantando um token no formato do GitHub num arquivo versionado.

**Igualdade de conjuntos nos dois sentidos** (suíte 900). Para as funções
executáveis por `anon` e para as tabelas do domínio M2, tanto *sumiu algo
declarado* quanto *apareceu algo não declarado* reprovam. Isso importa porque a
baseline concede `ALL ON FUNCTIONS` a `anon` por padrão: **toda função nova nasce
executável por anon** até um `REVOKE` explícito. Sem esse teste, um `REVOKE`
esquecido numa migração futura passaria silencioso.

**Prova de campo em vez de leitura de catálogo.** Onde faz diferença, o teste
executa a operação como o papel real (`TRUNCATE` como `anon`, `INSERT` com CNPJ
inválido) em vez de consultar `information_schema`.

**Concorrência real.** As suítes 100 e 170 abrem uma segunda sessão via `dblink`
para exercitar a serialização por `FOR UPDATE` — não simulam concorrência.

---

## 7. Gate final — NÃO EXECUTADO

    SUPABASE_PG17_FINAL_GATE = PENDING_EXTERNAL_EXECUTION

Evidência da impossibilidade neste ambiente, verificada e não presumida:

| Requisito | Estado |
|---|---|
| Supabase CLI | ausente (`command -v supabase` → nada) |
| Daemon Docker | cliente 29.3.1 presente, **daemon inacessível** (`Cannot connect to the Docker daemon at unix:///var/run/docker.sock`) |
| Imagens Docker do Supabase | bloqueadas pela política de rede do ambiente |
| Cluster PostgreSQL local | **16.13** — binários só em `/usr/lib/postgresql/16` |

Portanto **todos** os resultados SQL deste relatório vêm de um harness nativo
PostgreSQL 16 com um shim de compatibilidade Supabase, e estão rotulados em
cada script e em cada saída como:

    [PG16 TESTE_AUXILIAR_NAO_GATE]

O PG16 **não** é equivalente ao gate e não foi relabelado como tal. O que o
harness reproduz: papéis `anon`/`authenticated`/`service_role`, `auth.uid()`,
`auth.role()`, `auth.jwt()` sobre GUCs, `auth.users`, o subconjunto de
`storage.buckets`/`storage.objects` consumido pelas policies do M1, e a
publication `supabase_realtime`. O que ele **não** reproduz: `supabase_vault`
(comentada no stream enviado ao psql, desvio documentado), o comportamento do
PostgREST, o GoTrue real, e qualquer diferença semântica entre PG16 e PG17.

**Ação externa requerida:** rodar `supabase db reset --local` e a suíte completa
num Supabase local PostgreSQL 17 real antes de qualquer promoção.

---

## 8. Bloqueios registrados

| ID | Descrição | Impacto |
|---|---|---|
| `SUPABASE_PG17_FINAL_GATE` | Gate final não executável aqui (secção 7) | **Bloqueia promoção** |
| `BLOCKED_APP_REPOSITORY` | O repositório do App não pôde ser inspecionado. Não há implementação operacional do App, não há E2E Site→App, e nenhum contrato de API do App foi inventado. | Ponte, validação de benefício e políticas operacionais ficam como camada 1 de 5 / POLÍTICA-SPEC |
| `BLOCKED_EXTERNAL` (e-mail) | Sem credencial de provedor real. `HttpApiTransport` implementado e testado; nenhum segredo lido, impresso ou commitado. | Envio real não exercitado |
| `BLOCKED_EXTERNAL` (jurídico) | Textos legais definitivos e assinatura eletrônica dependem de terceiros | Prontidão técnica sim, operacional não |
| Pendência: `ALL ON FUNCTIONS` a `anon` | O `ALTER DEFAULT PRIVILEGES` da baseline segue concedendo. Todas as funções M2 fazem `REVOKE`, e a suíte 900 vigia por igualdade de conjuntos. Inverter o padrão global é mudança de postura. | Decisão do responsável |
| Achado informativo | `src/__tests__/commercial.test.ts` existe na base canônica mas **nunca roda**: o include do vitest é `src/**/*.spec.{ts,tsx}`. Condição herdada do M1, não introduzida aqui. Não corrigida por ser configuração canônica. | Nenhum |

---

## 9. Honestidade sobre a ponte com o App

Nada nesta série implementa o App nem conclui um fluxo Site→App.

- `src/domain/operational/*` está rotulado **POLÍTICA/SPEC**, com
  `APP_REPOSITORY=BLOCKED_APP_REPOSITORY` no README do diretório.
- `bridgeAdapter.ts` expõe `BlockedProvisioningTransport`, uma sentinela que
  **sempre** lança. Configurar as variáveis de ambiente **não** desbloqueia — e
  há mutante provando que a sentinela não pode virar no-op silencioso.
- `PortalValidar` diz ao usuário, em texto: *"Encaminhado — ainda NÃO concluído"*
  e *"nenhum benefício foi consumido"*.
- `prepare_benefit_validation` devolve `app_gateway: 'BLOCKED_APP_REPOSITORY'`.

---

## 10. Segredos

`SECRET_SCAN=PASS`. Nenhum `.env` real versionado; `.env.example` contém apenas
nomes, sem valores (verificado por teste, não por inspeção). Nenhuma chave,
token, senha ou URI com credencial em arquivo versionado ou no diff da série.
A credencial do provedor de e-mail vive em campo privado real de JS (`#apiKey`),
com `toJSON()` explícito para que `JSON.stringify` do transporte nunca a
materialize.

---

## 11. Nenhuma operação remota

Nenhum `git push`, nenhuma escrita via API do GitHub, nenhuma criação ou
alteração de branch remoto, nenhum PR, nenhum merge remoto, nenhum deploy,
nenhuma escrita em Supabase remoto, nenhum `migration repair` remoto.
Toda a série existe apenas localmente, em `recon/m1-m2-launch`.
