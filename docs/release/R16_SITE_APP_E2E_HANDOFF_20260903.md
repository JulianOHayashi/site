# R16 — Handoff do E2E Site ↔ App

**Data:** 2026-09-03
**Proveniência deste documento:** `R16_RELEASE_DOC_PROVENANCE=AUTHORED_CURRENT_SESSION_FROM_TRUSTED_CP4_AND_PROMPT`

**Nenhum código do App é modificado neste release do Site.** Este documento
descreve o menor E2E crítico para lançamento, a ser executado por operador
autorizado nos dois ambientes.

```
SITE_APP_REMOTE_E2E=PENDING_EXTERNAL
```

Nenhum passo abaixo foi executado. A ponte permanece
`BLOCKED_APP_REPOSITORY` enquanto o contrato real da API do App não puder ser
inspecionado.

---

## Formato

Cada passo traz: **sistema dono**, **pré-condição**, **ação**, **resultado
esperado**, **evidência**, **condição de STOP**.

---

### E1 — Parceiro / titular / unidade no Site

- **Dono:** Site
- **Pré-condição:** parceiro aprovado, com titular e unidade consistentes
- **Ação:** criar/confirmar o registro pelo fluxo oficial do Site
- **Esperado:** registro coerente com as regras comerciais fechadas (nicho
  inteiro, exclusividade por CNPJ, cidade dentro do território)
- **Evidência:** id do parceiro e da unidade, redigidos
- **STOP:** registro criado por INSERT manual em vez do fluxo oficial

### E2 — E-mail / outbox do Site, onde aplicável

- **Dono:** Site (worker R16)
- **Pré-condição:** smoke de provedor em staging já aprovado
  (`R16_REAL_PROVIDER_SMOKE`)
- **Ação:** enfileirar e despachar o template correspondente
- **Esperado:** exatamente uma entrega, estado `sent`, sem duplicata na
  reexecução
- **Evidência:** captura do provedor e estado do evento
- **STOP:** duplicata, ou envio sem claim atômico

### E3 — Requisição assinada ao gateway

- **Dono:** Site
- **Pré-condição:** chave de assinatura provisionada fora do repositório
- **Ação:** emitir a asserção/requisição assinada ao App
- **Esperado:** requisição bem formada, com `kid` resolvível
- **Evidência:** cabeçalhos redigidos, **sem** a assinatura completa e **sem**
  a chave
- **STOP:** chave presente em log, artefato ou documento

### E4 — Validação de emissor, audiência, `kid` e ambiente

- **Dono:** App
- **Pré-condição:** App configurado com o emissor e a audiência do Site
- **Ação:** App valida os quatro campos
- **Esperado:** aceite apenas com os quatro corretos; recusa se qualquer um
  divergir, inclusive ambiente
- **Evidência:** decisão registrada nos dois lados
- **STOP:** aceite com ambiente cruzado (staging assinando para produção)

### E5 — Validação de assinatura

- **Dono:** App
- **Ação:** verificar a assinatura
- **Esperado:** assinatura inválida é recusada sem efeito colateral
- **Evidência:** código de recusa
- **STOP:** qualquer efeito no domínio de benefício antes da validação

### E6 — Replay aceito uma vez

- **Dono:** App
- **Ação:** enviar a requisição válida
- **Esperado:** aceita **uma** vez
- **Evidência:** estado canônico do App
- **STOP:** aceite duplicado

### E7 — Replay duplicado recusado

- **Dono:** App
- **Ação:** reenviar a **mesma** requisição
- **Esperado:** recusada por replay, sem mutação adicional
- **Evidência:** código de recusa e estado inalterado
- **STOP:** segunda aplicação do mesmo efeito

### E8 — RPC canônica do domínio de benefício

- **Dono:** App
- **Ação:** executar a RPC canônica do domínio de benefício
- **Esperado:** distribuição conforme as regras fechadas; divisão inteira por
  piso é invariante contratual, não estilo
- **Evidência:** resultado da RPC
- **STOP:** arredondamento diferente de piso, ou distribuição fora da regra

### E9 — Caminho de autorização aceito

- **Dono:** App
- **Ação:** ator autorizado executa a operação
- **Esperado:** sucesso
- **Evidência:** resultado
- **STOP:** —

### E10 — Caminho de autorização negado

- **Dono:** App
- **Ação:** ator **não** autorizado tenta a mesma operação
- **Esperado:** negado, fail-closed, sem efeito parcial
- **Evidência:** código de negação
- **STOP:** qualquer efeito parcial

### E11 — Fronteira de privilégio confirmar/recusar

- **Dono:** App
- **Ação:** testar quem pode confirmar e quem pode recusar
- **Esperado:** a fronteira é respeitada nos dois sentidos; ausência de
  solicitação é estado de **negação**, não de autorização
- **Evidência:** matriz de decisão
- **STOP:** ausência de solicitação tratada como permissão

### E12 — Logs livres de segredo

- **Dono:** Site e App
- **Ação:** auditar toda a saída de E1–E11
- **Esperado:** sem token, sem chave de assinatura, sem service_role, sem
  senha, sem corpo de mensagem, sem PII desnecessária
- **Evidência:** amostra redigida
- **STOP:** qualquer ocorrência

### E13 — Navegador não invoca operação interna de banco

- **Dono:** Site e App
- **Ação:** a partir do navegador, tentar invocar as operações internas
  (`svc_*`, RPCs de domínio do App)
- **Esperado:** **negado**. As operações de serviço não são alcançáveis por
  `anon` nem por `authenticated`
- **Evidência:** respostas de negação
- **STOP:** qualquer alcance a partir do cliente

---

## Estado final

```
SITE_APP_REMOTE_E2E=PENDING_EXTERNAL
APP_CODE_MODIFIED_IN_THIS_RELEASE=NO
```

Este E2E só pode ser marcado concluído por operador autorizado que o execute
de fato. Nenhum resultado dele é presumido por este release.
