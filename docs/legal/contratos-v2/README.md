# Contratos V2 — publicidade visual em veículos (bandeira sobre o teto)

> **Todos os documentos desta pasta são MINUTAS ou ANÁLISES PRELIMINARES.
> Nenhum é assinável, publicado ou juridicamente aprovado.** A aprovação
> jurídica, a validação técnica da bandeira e a autorização de publicação são
> etapas separadas.

| Arquivo | Conteúdo |
|---|---|
| `00_AUDITORIA_SISTEMA_CONTRATUAL_20261110.md` | Como o sistema trata Mestre, Termos, instrumento, aceites, hashes e snapshots, e o que hoje impede a contratação |
| `01_MINUTA_ACORDO_MESTRE_V2_20261110.md` | Acordo Mestre V2 completo, com pendências marcadas |
| `02_MINUTA_TERMOS_PEDIDO_COMERCIAL_V2_20261110.md` | Termos do Pedido V2, em linguagem para o cliente |
| `03_MINUTA_INSTRUMENTO_INDIVIDUAL_V2_20261110.md` | Modelo V2 do instrumento; cada campo é um fato do servidor |
| `04_ANEXO_TECNICO_BANDEIRA_PRELIMINAR_20261110.md` | Anexo técnico preliminar (490 × 305 mm de referência da arte) e lista de confirmações para o responsável técnico |
| `05_MATRIZ_REGULATORIA_GRANDE_VITORIA_20261110.md` | Normas federais e matriz por município, com fontes e situação |
| `06_DECISOES_PENDENTES_20261110.md` | Quadro de decisões jurídicas, de negócio, técnicas e regulatórias |
| `07_PLANO_PUBLICACAO_VERSIONAMENTO_20261110.md` | Ordem exata de publicação e regras de versionamento |

**Código preparatório:**
- `supabase/migrations/20261110120000_contract_v2_vehicle_visual_advertising.sql`
- rollback em `supabase/rollback/`
- suíte `supabase/tests/280_…`
- ensaio `scripts/db-test/contract-v2-upgrade-check.sh`
- testes dos documentos em `src/__tests__/contratosV2Minutas.spec.ts`
