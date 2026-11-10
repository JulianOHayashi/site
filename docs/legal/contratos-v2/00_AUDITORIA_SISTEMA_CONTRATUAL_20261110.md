# Auditoria do sistema contratual — SmallFlags (2026-11-10)

Escopo: repositório `JulianOHayashi/site` no `main` `97b74ef77cfe4b81eb332b11c47ff72083fd75aa`
e Supabase Production (`SiteDBFLOW`), **somente leitura** (SELECT), em 2026-11-10.
Nenhuma escrita remota foi feita.

## 1. Estado confirmado de Production

| Item | Estado |
|---|---|
| Histórico de migrations | 63 registros; última `20261103120000` (Etapa B aplicada) |
| Posições ativas | supermarket 24, pharmacy 12, womens_clothing 12, mens_clothing 12, footwear 12, others 12 = 6 posições, 84 unidades |
| `legal_documents` publicados | 4: `privacy_notice`, `provisional_account_terms`, `document_analysis_authorization`, `truthfulness_declaration` (todos `SF-SITE-…-2026-10-27-v1.0`) |
| Acordo Mestre (`master_agreement`) | **nenhum** documento publicado ou arquivado |
| Termos do Pedido (`commercial_order_terms`) | **nenhum** documento publicado ou arquivado |
| `commercial_instrument_templates` | 1 linha: `SF-MINUTA-PRESENCIAL-v1.4`, **draft**, não fidelizado, `allows_outros_niche=false`, source_hash `03f36670…0c73` |
| `commercial_master_agreements` | 0 linhas |
| `legal_acceptances` | 0 linhas |
| Pedidos (`commercial_exclusivity_orders`) | 0 |
| Reservas (`commercial_checkout_intents`) | 0 |
| Construtor do snapshot em Production | md5(prosrc) `a722d810fabc327f8fbfac9c008efced`, igual ao do repositório |

Conclusão: hoje **nenhuma contratação nova consegue nascer**. O fluxo para em
mais de um ponto, todos falhando fechado (§3).

## 2. Como cada peça é tratada hoje

### 2.1 Acordo Mestre de Parceria Comercial
- **Texto público:** linha de `legal_documents` com `doc_type = 'master_agreement'`,
  publicada por `admin_publish_legal_document`. A allowlist inclui o tipo desde
  `20261005140000`. Para publicar, o CHECK exige conteúdo, `content_hash`,
  `published_at`, `published_by` e `effective_from`.
- **Leitura pública:** `/legal/acordo-mestre-parceiros` (`LegalAcordoMestre.tsx`).
  Mostra a versão vigente ou, com `?versao=X`, a versão histórica X, via
  `get_legal_document_version`. Falha fechado e nunca injeta HTML.
- **Assinatura por empresa:** `commercial_master_agreements` (uma linha por
  empresa), registrada por `admin_register_master_agreement`. O gatilho
  `cma_exigir_coerencia_legal` exige que `agreement_version` e `document_hash`
  correspondam a um documento **publicado** em `legal_documents`
  (`legal_document_id`).
- **Imposição:** `p01_master_enforcement_lock` e `p01_master_eligibility_resolver`
  impedem a contratação sem um Mestre vigente assinado pela empresa
  (`get_governing_master_for_intent`).

### 2.2 Termos Comerciais do Pedido
- `doc_type = 'commercial_order_terms'` (`20260916120000`).
- O aceite é feito por `accept_commercial_order_terms(p_intent_id)`. A função:
  - exige o dono da empresa;
  - exige a intenção em `awaiting_contract` e com reserva vigente;
  - resolve **no servidor** a versão vigente publicada;
  - grava em `legal_acceptances`, com `legal_document_id`, `context = 'commercial_contract'`,
    evidência (versão, `content_hash`), IP e user-agent quando o gateway os repassa;
  - é idempotente por documento e intenção.
- Sem Termos publicados, a função devolve `terms_not_published` e o fluxo para.

### 2.3 Instrumento individualizado
- **Autoridade de modelos:** `commercial_instrument_templates`, com ciclo de vida
  `draft/signable/archived`.
  - No máximo um modelo `signable` por condição de fidelidade
    (`cit_signable_por_fidelidade_uidx`).
  - `required_snapshot_fields` lista os fatos que o modelo exige.
  - Promover para `signable` exige DML administrativa deliberada. Não há RPC
    para isso.
- **Emissão (`20261008120000`):** em pedido assinado com `pricing_rule_version ≥ 3`,
  os gatilhos `ceo_exigir_instrumento_quando_assinavel` e `ceo_emitir_instrumento`
  chamam `commercial_build_instrument_snapshot(order, template)` **na mesma transação**.
  Se faltar qualquer fato, o pedido inteiro é abortado.
- **Snapshot:** reúne os fatos de registros canônicos, com procedência declarada
  campo a campo. O hash (`instrument_snapshot_hash`) é calculado sobre `jsonb::text`
  normalizado e é diferente do `source_hash` do modelo.
- **Código:** `SF-0001…` vem de uma SEQUENCE global, sem reuso.
- **Imutabilidade:** `ceo_instrumento_imutavel` proíbe reescrever o instrumento emitido.

### 2.4 Fatos materiais e vínculos
Empresa, representante com autoridade, unidade de execução e tomador da NFS-e
vêm de registros canônicos (P0-2). A economia vem de `commercial_pricing_schedule`,
pela versão de preço e de economia, pela categoria e pela fidelização. A
atividade contratada vem de `commercial_contract_activity_catalog`, que **não
tem nenhuma linha aprovada**. O pedido também carrega região, exclusividade,
posição (`niche_code`) e, desde a Etapa B, o segmento congelado:
`segment_code_snapshot`, `segment_name_snapshot` e `segment_classification_snapshot`.

### 2.5 Fidelização
- Duas condições, cada uma com o seu modelo (`applies_to_fidelized`).
- O construtor recusa a divergência com `commercial_instrument_template_fidelity_mismatch`.
- A identidade de fidelidade é o nicho, ou `segment:<classificação>`
  (`commercial_fidelity_identity`, Etapa B).

### 2.6 Responsabilidades Site × App
- **O Site** é a autoridade comercial e contratual: empresas, Mestre, termos,
  pedidos, preço e instrumento.
- **O App** é a autoridade operacional: divulgadores (MEIs), agenda, benefícios
  e evidências.
- O provisionamento para o App fica bloqueado para posições e segmentos novos até
  o contrato v3 (`app_contract_v3_required`).
- Nada no sistema contratual do Site registra hoje evidência de exibição de
  bandeira, instalação, vistoria ou incidente. Isso pertence à operação (App) e
  ainda **não tem contrato de integração**.

## 3. Impedimentos atuais para emitir contratos (todos fail-closed)

1. **Sem Acordo Mestre publicado:** nenhuma empresa consegue assinar o Mestre
   (`cma_exigir_coerencia_legal`), e sem Mestre não há elegibilidade.
2. **Sem Termos do Pedido publicados:** `accept_commercial_order_terms` → `terms_not_published`.
3. **Sem modelo `signable`:** `commercial_signable_instrument_template` → `commercial_instrument_template_unavailable`.
4. **Sem atividade aprovada no catálogo:** o construtor devolve `commercial_activity_description_unavailable`.
5. **Segmento e Outros:** o construtor devolve `commercial_instrument_segment_activity_unavailable` (D9).
6. **Achado — a v1.4 real seria inemissível mesmo se promovida:** o
   `required_snapshot_fields` dela inclui `activity_location`, que o construtor
   **nunca** produz. A emissão falharia fechado com `instrument_snapshot_material_fact_missing`.
   Não é risco de segurança, mas confirma que a v1.4 não serve de base para publicação.
7. **Achado — não existe representação técnica da peça publicitária:** nenhuma
   tabela ou fato descreve a bandeira, a especificação técnica, a modalidade de
   publicidade ou a aprovação técnica. Sem isso, um instrumento não consegue
   identificar "a especificação técnica aprovada" (pedido da missão, §5).
   Esta lacuna foi tratada pela migration preparatória (§5).

## 4. O que muda com a finalidade "publicidade visual com bandeira"

- **Documentos:** o objeto contratual passa a ser publicidade **visual** por
  bandeira sobre o veículo. As minutas novas estão em `docs/legal/contratos-v2/`.
- **Versionamento:** o Mestre e os Termos novos entram como **novas versões**
  dos mesmos `doc_type`, nunca sobrescrevendo versão anterior. Hoje não há versão
  anterior publicada, então não há quem precise de reaceite. Se alguma versão for
  publicada antes da V2, a mudança de objeto é **alteração material**
  (`is_material_change = true`) e exige novo aceite.
- **Instrumento:** o modelo novo (V2) precisa referenciar a especificação
  técnica aprovada, a região, a exclusividade, a posição e a atividade efetiva,
  a fidelização e o prazo, todos como fatos do servidor.

## 5. Alterações preparatórias desta branch (seguras antes da aprovação jurídica)

Migration aditiva `20261110120000_contract_v2_vehicle_visual_advertising.sql`
(detalhes no plano de publicação):
- **`commercial_advertising_specs`:** autoridade versionada da especificação
  técnica, criada **vazia**.
  - A aprovação exige responsável técnico, registro profissional e hash do laudo.
  - Máquina de estados imposta pelo gatilho `cas_protect` (INSERT, UPDATE e
    DELETE) e por `cas_protect_truncate` (TRUNCATE):
    - toda especificação **nasce `draft`**; aprovar é sempre a transição
      `draft → approved`;
    - o rascunho é editável, exceto `id` e `created_at`, e pode ser apagado;
    - `draft → archived` direto é recusado;
    - `approved → archived` só altera `lifecycle_status` e `archived_at`
      (comparação `to_jsonb(NEW)` × `to_jsonb(OLD)` sem essas duas chaves,
      que cobre também colunas futuras), e `archived_at` não pode ser anterior
      a `approved_at`;
    - aprovada e arquivada não são alteradas, apagadas nem truncadas.
  - Só uma versão aprovada por modalidade.
  - Sem acesso para `anon` e `authenticated`; `service_role` **só lê**. Os
    privilégios padrão do schema `public` em Production dariam
    INSERT/UPDATE/DELETE/TRUNCATE ao `service_role`, e a migration os revoga.
- **`commercial_instrument_templates`:** ganha `advertising_modality` e
  `requires_advertising_spec` (padrão `false`). A v1.4 continua idêntica.
- **`commercial_order_effective_activity`:** posição e atividade efetiva lidas
  apenas dos snapshots congelados do pedido. Para segmento, a identidade é a
  classificação, nunca o nome comercial.
- **Construtor do snapshot:**
  - quando o modelo exige especificação, acrescenta modalidade, especificação
    aprovada (id, código, versão, hash, dimensões de referência da arte),
    região, número da exclusividade, posição, atividade efetiva, fidelização e
    prazo, com procedência declarada;
  - sem especificação aprovada, devolve `commercial_advertising_spec_not_approved`;
  - o bloqueio D9 continua antes desse ponto, inalterado.

**Não feito, por depender de decisões pendentes:**
- publicar documentos;
- criar o modelo V2;
- aprovar especificação;
- liberar segmento e Outros no instrumento;
- definir a "atividade contratada" por segmento;
- integrar evidências operacionais com o App.

## 6. Testes que sustentam esta auditoria

- `supabase/tests/280_contract_v2_vehicle_visual_advertising.sql`: 42 checks.
- `scripts/db-test/contract-v2-upgrade-check.sh`:
  - só o construtor muda;
  - a ACL é preservada;
  - o rollback devolve o catálogo idêntico;
  - o rollback é recusado depois de qualquer uso.
- Testes dos documentos: `src/__tests__/contratosV2Minutas.spec.ts`.
- Os resultados de cada execução estão no relatório de entrega.
