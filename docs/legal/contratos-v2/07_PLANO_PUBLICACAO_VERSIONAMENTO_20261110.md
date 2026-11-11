# Plano de publicação e versionamento — Contratos V2

> **Etapa preparatória §1 executada em Production em 2026-11-10 (horário local), registrada no histórico do Supabase com a versão `20261111000511` (UTC).** As etapas jurídicas e operacionais §§2–5 NÃO foram executadas. Cada passo futuro com 🔒 exige aprovação e autorização específicas.

## 0. Pré-condições (todas obrigatórias)

1. Revisão jurídica aprovou o texto final do Acordo Mestre V2, dos Termos V2 e
   do modelo de instrumento V2, com as decisões D-J resolvidas ou expressamente
   aceitas como estão.
2. Responsável técnico aprovou o Anexo Técnico (D-T1, D-T2), com laudo e
   registro profissional.
3. Cada município de operação tem autorização confirmada, ou a execução foi
   restrita aos municípios confirmados (D-J2, D-R*).
4. Decisões D-N1 a D-N4 tomadas.
5. A migration preparatória foi aplicada em Production e registrada como `20261111000511` (ver §1); não reaplicar.

## 1. Migration preparatória (independe das aprovações; não ativa nada)

| Passo | Ação | Gate |
|---|---|---|
| 1.1 | Revisão independente do PR | Aprovação |
| 1.2 🔒 | Merge | Autorização |
| 1.3 | Pré-checagem só leitura em Production: 63 migrations; md5 do construtor `a722d810fabc327f8fbfac9c008efced`; tabela `commercial_advertising_specs` inexistente; template v1.4 em draft | Todos ok |
| 1.4 CONCLUÍDO | O SQL idêntico ao arquivo Git foi executado uma vez em Production via Supabase `apply_migration`. O histórico recebeu automaticamente `20261111000511`; o arquivo Git foi renomeado para esse prefixo. **Não executar novamente.** | Aplicação retornou sucesso e objetos foram verificados |
| 1.5 CONCLUÍDO | Registro criado pela ferramenta com `version = 20261111000511`, `name = contract_v2_vehicle_visual_advertising`; **não inserir registro adicional** para `20261110120000`. | Histórico consultado depois da aplicação |
| 1.6 CONCLUÍDO | Tabela vazia, sem especificação aprovada; v1.4 continua draft com `requires_advertising_spec = false`; nenhum Acordo Mestre ou Termos publicados; nenhum pedido; nenhum modelo signable; gatilhos e permissões conferidos. | Consultas pós-aplicação PASS |

**Rollback:** `supabase/rollback/20261110120000_contract_v2_vehicle_visual_advertising_rollback.sql` (nome histórico original, mantido; versão aplicada `20261111000511`).
Ele só roda se a infraestrutura V2 não tiver sido usada. Ensaio:
`scripts/db-test/contract-v2-upgrade-check.sh` devolve o catálogo idêntico ao
anterior.

## 2. Publicação dos documentos (depois das pré-condições §0)

| Passo | Ação | Detalhe |
|---|---|---|
| 2.1 | Congelar o texto final | Gerar SHA-256 de cada documento final (UTF-8, LF). O hash vai para `legal_documents.content_hash` e para os registros abaixo. |
| 2.2 🔒 | Publicar o **Acordo Mestre V2** | `admin_publish_legal_document('master_agreement', versão, título, conteúdo, hash, effective_from, is_material_change)`. Nova linha; nenhuma versão anterior é editada. |
| 2.3 🔒 | Publicar os **Termos do Pedido V2** | Mesmo caminho, `doc_type = 'commercial_order_terms'`. `is_material_change` conforme D-J8. |
| 2.4 | Verificar | `/legal/acordo-mestre-parceiros` mostra a V2. `?versao=` mostra cada versão histórica. Os Termos vigentes são resolvidos por `accept_commercial_order_terms`. |

## 3. Especificação técnica (depois de D-T1 e D-T2)

| Passo | Ação |
|---|---|
| 3.1 🔒 | Inserir a especificação em `commercial_advertising_specs` como `draft` (o gatilho recusa inserção já aprovada ou arquivada). `source_hash` = SHA-256 do Anexo Técnico aprovado. Conferir o rascunho. |
| 3.1b 🔒 | Aprovar com um único `UPDATE` `draft → approved`, preenchendo responsável, registro, hash do laudo, `approved_by` e `approved_at` (o CHECK recusa a falta de qualquer um). Depois disso a linha é imutável: correção exige nova versão e arquivamento da anterior. |
| 3.2 | Conferir que existe uma única especificação aprovada para `vehicle_roof_visual_flag` |

## 4. Modelos de instrumento V2 (depois de §2 e §3)

| Passo | Ação |
|---|---|
| 4.1 🔒 | Inserir **dois** modelos V2, um não fidelizado e um fidelizado, em **draft**, com `advertising_modality = 'vehicle_roof_visual_flag'`, `requires_advertising_spec = true`, `source_hash` = SHA-256 do texto final do modelo e `required_snapshot_fields` = campos da v1.4 menos `activity_location` (que o construtor não produz; ver auditoria §3.6), mais os campos V2 (modalidade, especificação, região, exclusividade, posição, atividade efetiva, fidelização, prazo). |
| 4.2 🔒 | Ensaio em banco descartável: com os modelos V2 assináveis e a especificação aprovada, emitir um instrumento de teste e conferir os fatos. A suíte 280 já cobre o caminho com dados fictícios. |
| 4.3 🔒 | Promover os modelos V2 de `draft` para `signable` por ato administrativo deliberado. O índice garante no máximo um assinável por condição. A v1.4 continua draft, ou passa a archived por decisão própria. |
| 4.4 🔒 | Aprovar no catálogo de atividades as linhas de atividade contratada, por nicho, com texto jurídico, versão e hash. Sem elas o construtor recusa (`commercial_activity_description_unavailable`). |

## 5. Segmento e Outros (só depois de D-J4)

Exige uma migration própria, que:
- acrescenta ao modelo uma capacidade explícita de segmento;
- define a fonte da atividade contratada do segmento;
- troca o bloqueio D9 por uma verificação positiva.

**Não está nesta branch.**

## 6. Regras permanentes de versionamento

- Documento publicado nunca é editado: cada mudança é uma versão nova, com hash
  novo.
- Pedido e aceite apontam para o `legal_document_id` e o hash exatos.
- O instrumento emitido é imutável (`ceo_instrumento_imutavel`). Um modelo novo
  não reescreve instrumento antigo.
- Nenhum aceite é criado por migration, seed ou script. Só pelo fluxo
  autenticado do responsável da empresa.
- Nenhum modelo é promovido para `signable` e nenhuma especificação é aprovada
  por RPC: só por ato administrativo deliberado, registrado e autorizado.
