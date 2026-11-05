# Contrato de integração Site → App — v3 (posição × segmento)

> **Status: PROPOSTA para revisão.** O App **não** foi modificado (D8).
> Até a v3 ser implementada e aceita dos dois lados, o Site **falha fechado**:
> `build_app_provisioning_payload` devolve `app_contract_v3_required` se a
> exclusividade tiver pedido assinado em `footwear`, em `others` ou com
> segmento. Nenhuma formação incompatível chega ao App.

## 1. O que mudou no Site (migration 20261103120000)

| Conceito | Antes (v2) | Agora |
|---|---|---|
| Posição comercial | `niche_code` ∈ {supermarket, pharmacy, womens_clothing, mens_clothing, womens_footwear, mens_footwear} | `niche_code` ∈ {supermarket, pharmacy, womens_clothing, mens_clothing, **footwear**, **others**}. Os calçados F/M ficam **históricos** e inativos |
| Quem ocupa a posição | sempre o próprio nicho | o nicho **ou** um **segmento** aprovado de Outros (pharmacy, womens_clothing, mens_clothing e footwear aceitam; others exige; supermarket nunca) |
| Quantidade | 24 + 5×12 = 84 | **inalterado**: 24 + 5×12 = 84, 6 posições |
| Preço | categoria por nicho | **inalterado**: supermarket e common (os cinco de 12) |
| Unicidade | 1 pedido por posição | 1 pedido por posição **e** 1 segmento por exclusividade |
| Fidelidade | (cnpj, uf, cidade, nicho) | (cnpj, uf, cidade, **identidade efetiva**). A identidade é `niche_code` ou `segment:<classification_key>` |

**Posição ≠ segmento.** A posição é a vaga física na formação: o slot da
matriz e a quantidade. O segmento é a atividade comercial efetiva de quem
ocupa a vaga. Dois nomes diferentes que caem na mesma `classification_key`
são o mesmo segmento.

## 2. Payload proposto `bdflow.commercial_provisioning.v3`

Aditivo em relação à v2. Os campos que não aparecem abaixo continuam iguais
(`partner_network_bridge_id`, pools em centavos, `benefit_settlement_mode`,
branches, validators etc.).

```jsonc
{
  "schema_version": "bdflow.commercial_provisioning.v3",
  "participant_target": 84,
  "distribution_policy_version": 2,
  "schedule_policy_version": 2,            // ver §4: matriz por POSIÇÃO
  "position_catalog_version": "positions.2026-11-03",
  "partners": [
    {
      "position_code": "pharmacy",         // NOVO nome explícito; = niche_code
      "niche_code": "pharmacy",            // mantido por compatibilidade
      "contracted_quantity": 12,
      "pricing_category": "common",        // "supermarket" | "common"
      "occupant": {                        // NOVO
        "kind": "segment",                 // "niche" | "segment"
        "segment_code": "papelaria",       // null quando kind = "niche"
        "segment_name": "Papelaria",       // snapshot imutável do pedido
        "segment_classification": "papelaria",
        "effective_identity": "segment:papelaria"   // = fidelity_identity
      }
      // ... demais campos da v2
    }
  ]
}
```

Regras do payload, todas verificadas pelo Site antes de emitir:

1. Exatamente 6 `partners`, com `position_code` distintos e iguais ao conjunto ativo.
2. Soma de `contracted_quantity` = 84. `supermarket` = 24, os demais = 12.
3. `supermarket.occupant.kind` = `"niche"` sempre.
4. `others.occupant.kind` = `"segment"` sempre.
5. `effective_identity` distinta entre os 6 partners.
6. Os snapshots vêm do pedido (`segment_*_snapshot`). Nunca da tabela viva de segmentos.
7. Pedido em código histórico (`womens_footwear` ou `mens_footwear`) nunca entra
   numa v3. Uma formação antiga, se existir, continua v2 e o App a recebe como v2.

## 3. O que o App precisa aceitar (lado App, a implementar lá)

- **Novos códigos** `footwear` e `others` no catálogo operacional de nichos do App.
  O App não deve criar nicho operacional para cada segmento: o slot é a posição.
- **Rótulo exibido** ao usuário final: `occupant.segment_name`, quando houver;
  senão, o nome da posição.
- **Recusa** de v3 que viole qualquer regra do §2, com `invalid_v3_payload`.
  Não deve coagir.
- **Reivindicação**: mensagem v2 pendente cuja exclusividade tenha Calçados,
  Outros ou segmento não existe hoje, porque o Site não a emite. Se aparecer,
  recusar com `stale_schema_version`.
- **Idempotência e replay**: os mesmos mecanismos da v2 (gateway Ed25519, trust store).

## 4. Impacto nos 7 tipos de benefício e na matriz de agenda

- **Matriz 7×7** (7 grupos × 12 vagas × 7 etapas): a invariante é por **posição**.
  O conteúdo não muda: cada usuário passa por S1 e S2 e pelas 5 posições
  comuns. Só os **rótulos** de 2 colunas mudam (`womens_footwear` → `footwear`,
  `mens_footwear` → `others`). Por isso a versão de agenda sobe para 2. O
  validador da matriz deve rodar com os novos códigos antes de materializar o ciclo.
- **Tipos de benefício**: continuam ligados ao **parceiro** e ao modo de
  liquidação. Nada é derivado do segmento. O segmento só altera o rótulo e a
  identidade de fidelidade.
- **Fidelidade**: o App não recalcula. Recebe `effective_identity` como dado.
- **Validação de benefício** (`benefit_usage_*`): sem mudança, porque a
  autoridade continua sendo o parceiro e a filial.

## 5. Sequência sugerida

1. App: aceitar v3 em modo leitura (parser e validação), com testes contra
   fixtures geradas pelo Site.
2. Site: migration que troca a falha `app_contract_v3_required` pela emissão v3
   (mais a `schedule_policy_version` 2 e o validador da matriz com os códigos novos).
3. E2E Site → gateway → App em ambiente não produtivo.
4. Só então liberar o provisionamento de exclusividades com Calçados, Outros ou segmento.

## 6. Pendências em aberto

- Nome e lugar do catálogo de posições no App. Precisa auditar o código atual
  do App, que **vence** desenhos históricos.
- Se o App exibe o nome do segmento para o consumidor final ou só para a operação.
- Política de revisão quando um segmento é **arquivado** depois de vendido.
  No Site o snapshot é imutável: o pedido continua com o nome antigo.
