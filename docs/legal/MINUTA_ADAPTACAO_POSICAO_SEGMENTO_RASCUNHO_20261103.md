# ⚠️ RASCUNHO — NÃO ASSINAR — SUJEITO A REVISÃO JURÍDICA

> Proposta **documental** de adaptação da minuta do instrumento de exclusividade
> à separação **posição × segmento** (D9). Não foi publicada nem tornada
> assinável. Enquanto não for aprovada, o Site **falha fechado**: o instrumento
> não é individualizado para pedido com segmento nem para a posição Outros
> (`commercial_instrument_segment_activity_unavailable`). A redação abaixo é
> indicativa e precisa ser revista por advogado(a).

## 1. Pontos da minuta que precisam mudar

| Cláusula/campo | Hoje | Proposta |
|---|---|---|
| Objeto | exclusividade no **nicho** X | exclusividade na **posição comercial** X, ocupada pela **atividade** Y (nicho próprio ou segmento autorizado) |
| Quantidade | 12 (ou 24 no Supermercado) unidades | sem mudança. A quantidade é da **posição** |
| Região e exclusividade | região + nº da exclusividade | sem mudança |
| Exclusividade de atividade | implícita no nicho | explícita: nenhum outro contrato **da mesma exclusividade** pode ter a mesma atividade efetiva (mesma classificação), qualquer que seja a posição |
| Atividade contratada | catálogo por nicho | catálogo por **atividade efetiva** (nicho ou segmento), com versão e hash. Hoje o catálogo não tem nenhuma linha aprovada |
| Economia | preço da categoria | sem mudança: supermarket ou common. O segmento não altera preço |
| Fidelidade | por nicho | por atividade efetiva + CNPJ + cidade |
| Sobreposição | não prevista | se o segmento se sobrepõe a um nicho canônico, constar a **política de delimitação** aprovada pela SmallFlags (texto do cadastro do segmento) |
| Autorizações | — | declarar que o segmento foi **aprovado pela SmallFlags** antes da contratação (código, nome, data e versão). Solicitação pendente não gera direito |

## 2. Redação indicativa (para revisão)

**Objeto.** "A CONTRATANTE adquire a exclusividade da **Posição Comercial
{position_name}** ({contracted_quantity} unidades) na Exclusividade nº
{sequence_number} da região {region_name}, para a **atividade {activity_name}**
({activity_kind}: nicho próprio | segmento autorizado de Outros)."

**Exclusividade de atividade.** "Durante a vigência, a SmallFlags não contratará,
na mesma Exclusividade, outra posição para atividade de mesma classificação
({classification_key}), ainda que sob denominação diversa."

**Segmento autorizado.** "A atividade {activity_name} foi autorizada pela
SmallFlags em {approved_at} (código {segment_code}). A autorização registrada
no momento da contratação integra este instrumento e não é alterada por
mudanças posteriores no cadastro de segmentos."

**Delimitação** (só quando houver sobreposição a nicho canônico). "As partes
reconhecem a seguinte delimitação entre a atividade contratada e o nicho
{overlaps_niche}: {delimitation_policy}."

**Contratos históricos.** Pedidos assinados antes da adaptação (inclusive os
das posições históricas Calçados femininos e Calçados masculinos, se houver)
continuam regidos pelo instrumento que assinaram. Não há reemissão nem efeito
retroativo.

## 3. Dados que o Site já guarda para preencher

Snapshot imutável no pedido:

- `niche_code` (posição);
- `segment_code_snapshot`, `segment_name_snapshot` e `segment_classification_snapshot`;
- quantidade, preço e categoria;
- região e número da exclusividade.

Cadastro do segmento:

- `delimitation_policy`;
- `overlaps_niche_code`;
- `approved_by`/`approved_at` (auditados em `audit_logs`).

## 4. Para liberar (fora desta etapa)

1. Revisão jurídica e versão nova do template, com hash.
2. Linhas **aprovadas** no catálogo de atividade contratada, por atividade efetiva (inclusive `footwear`).
3. Migration que troca a falha fechada pela individualização com os campos acima.
4. Teste de que o documento emitido contém posição, atividade, quantidade e a cláusula de exclusividade de atividade.
