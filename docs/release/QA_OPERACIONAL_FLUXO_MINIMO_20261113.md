# QA em produtos — fluxo operacional mínimo auditável (R4, item 3)

- Data: 2026-11-13. Branch `feat/qa-modalidades-r4-20261113`.
- **Especificação. Nada aqui foi implementado.** O App não foi modificado. O
  modelo de dados da §6 é um rascunho e **não** está em nenhuma migration.
- Vale só para pedidos **SF-v1.5 (versão ≥ 4) na modalidade BENEFÍCIO DIRETO**,
  em que `qa_in_kind_cents > 0`. Na modalidade DINHEIRO não existe QA
  (`qa_in_kind_cents = qa_cash_cents = 0`, garantido por CHECK desde a R3), então
  este fluxo não se aplica a ela.
- Os itens marcados **[DECISÃO]** são escolhas comerciais, jurídicas ou
  contábeis. Este documento não as toma.

## 1. O que o fluxo precisa provar

Para cada pedido elegível, alguém que não participou da operação precisa conseguir
responder, só com registros imutáveis:

1. **Quem autorizou** a QA daquele pedido, quando, e com qual valor de referência
   (`qa_in_kind_cents` do snapshot congelado do pedido, nunca recalculado).
2. **Quem recebeu** os produtos, quando, onde, quais itens e qual valor
   reconhecido.
3. **Que teste local** foi feito com esses produtos, por quem e com que evidência.
4. **Se a obrigação foi cumprida**, ou, se não foi, o que foi registrado e
   decidido. Em nenhum caso a falta vira cobrança em dinheiro automaticamente.

## 2. Atores

| Ator | Papel | Observação |
|---|---|---|
| Anunciante (contratante) | Disponibiliza os produtos | Representante já identificado no Acordo Mestre do pedido |
| Operação SmallFlags | Autoriza, acompanha e encerra | Perfil admin já existente (`m1_exigir_admin`) |
| Usuário autorizado de QA | Recebe os produtos e executa o teste local | **[DECISÃO]** quem pode ser: funcionário SmallFlags, participante do App designado, terceiro contratado. Precisa ser nominal e ter vínculo verificável |
| Revisor | Valida a evidência e encerra a obrigação | Não pode ser o mesmo usuário que executou o teste (segregação mínima) |

## 3. Estados

```
autorizada ──► produtos_disponibilizados ──► recebimento_confirmado ──► teste_registrado ──► evidencia_validada ──► cumprida
     │                    │                          │                         │                      │
     └──────── prazo ─────┴──────── prazo ───────────┴──────── prazo ──────────┘            evidencia_recusada ──► teste_registrado
                                     ▼
                           nao_cumprimento_registrado ──► notificada ──► (cura) ──► recebimento_confirmado
                                                                   └──► resolvida_por_decisao   [DECISÃO]
```

Regras de transição:

- **autorizada** nasce de um pedido `confirmed` com `pricing_rule_version ≥ 4`,
  `benefit_settlement_mode = 'direct_benefits'` e `qa_in_kind_cents > 0`. O valor
  de referência é copiado do snapshot e não muda depois.
- **produtos_disponibilizados**: o anunciante declara o que entregou (itens,
  quantidades e valor unitário). O valor reconhecido pode ser menor ou maior que o
  de referência. **[DECISÃO]** a base do valor: preço de tabela, nota fiscal ou
  valor acordado.
- **recebimento_confirmado**: o usuário autorizado confirma o recebimento. A
  declaração do anunciante sozinha não basta.
- **teste_registrado**: execução do teste local, com evidência anexada.
- **evidencia_validada / evidencia_recusada**: decisão do revisor, com motivo.
- **cumprida**: só quando a soma do valor reconhecido nos recebimentos validados
  for ≥ `qa_in_kind_cents` **e** houver ao menos uma evidência validada.
  **[DECISÃO]** se o excedente gera algum crédito (proposta: não gera).
- **nao_cumprimento_registrado**: prazo vencido em qualquer etapa anterior a
  `cumprida`. Registro factual, sem efeito financeiro.

## 4. Prazos e evidências

| Item | Proposta para decisão |
|---|---|
| Prazo para disponibilizar os produtos | **[DECISÃO]**, contado da confirmação do pedido |
| Prazo para confirmar o recebimento | **[DECISÃO]**, contado da disponibilização |
| Prazo para registrar o teste | **[DECISÃO]**, contado do recebimento |
| Prazo de cura após notificação | **[DECISÃO]** |

Cada evidência é um arquivo guardado fora do banco (Storage privado), com o
banco guardando só os metadados. Mínimo por evidência:

- `sha256` do arquivo, gravado no momento do envio e conferido na validação;
- tipo (`foto_recebimento`, `nota_ou_romaneio`, `registro_do_teste`,
  `outro`), autor, data/hora do servidor;
- pedido e etapa a que pertence.

Sem `sha256` conferido a evidência não vale. Arquivo substituído gera evidência
nova; a anterior não é apagada.

## 5. Não cumprimento

1. O vencimento de prazo gera `nao_cumprimento_registrado`, com etapa, data e
   valores (referência × reconhecido).
2. A operação notifica o anunciante pelo canal contratual e registra a
   notificação (data, canal, referência do documento).
3. Abre-se o prazo de cura. Se houver entrega e validação dentro dele, o fluxo
   volta ao caminho normal.
4. Sem cura, a consequência é **[DECISÃO] contratual** e precisa estar escrita na
   minuta SF-v1.5 antes da aprovação jurídica. Opções que a minuta pode prever:
   cobrança do saldo em dinheiro mediante documento próprio, compensação em
   ciclo futuro ou registro sem efeito financeiro.
5. **Proibido por desenho:** nenhum gatilho, job ou RPC converte QA em dinheiro
   sozinho, nem altera o snapshot, o valor exigível ou o status do pedido. Uma
   eventual cobrança é um ato administrativo separado, com autorização própria e
   referência ao registro de não cumprimento.

## 6. Rascunho de modelo de dados (NÃO aplicado)

Tabelas append-only, no padrão das guardas atuais: escrita só por RPC
`SECURITY DEFINER` com `m1_exigir_admin` ou com o usuário autorizado; UPDATE e
DELETE recusados por gatilho; RLS sem escrita para `anon` e `authenticated`.

```sql
-- Rascunho. Não aplicar.
commercial_qa_obligations (
  id uuid pk, order_id uuid unique references commercial_exclusivity_orders,
  qa_reference_cents bigint not null,            -- cópia de qa_in_kind_cents do snapshot
  authorized_by uuid not null, authorized_at timestamptz not null,
  authorized_tester_id uuid not null,            -- [DECISÃO] cadastro do usuário autorizado
  due_dates jsonb not null                       -- prazos vigentes na autorização
);
commercial_qa_events (                            -- trilha de estados, só INSERT
  id uuid pk, obligation_id uuid not null, state text not null,
  actor uuid not null, at timestamptz not null default now(),
  recognized_cents bigint, reason text, payload jsonb
);
commercial_qa_evidences (
  id uuid pk, event_id uuid not null, kind text not null,
  storage_path text not null, sha256 text not null check (sha256 ~ '^[0-9a-f]{64}$'),
  uploaded_by uuid not null, uploaded_at timestamptz not null default now()
);
```

Invariantes a testar quando (e se) for implementado:

- obrigação só existe para v ≥ 4 + `direct_benefits` + `qa_in_kind_cents > 0`;
- `qa_reference_cents` igual ao snapshot do pedido;
- `cumprida` exige soma reconhecida ≥ referência e evidência validada por
  revisor ≠ executor;
- nenhuma transição altera `commercial_exclusivity_orders`;
- a verificação somente-leitura lista obrigações vencidas sem evento de não
  cumprimento.

## 7. O que o App precisaria (fora do escopo, sem aprovação)

Só como referência para uma decisão futura: uma tela do usuário autorizado para
confirmar o recebimento e enviar evidências, e uma fila da operação para validar
ou recusar. **Nenhuma alteração foi feita no App.**

## 8. Antes de qualquer contrato SF-v1.5 em benefício direto

1. Decidir os itens **[DECISÃO]** acima.
2. Escrever na minuta SF-v1.5 a obrigação de QA em produtos, os prazos e a
   consequência do não cumprimento. Essa minuta passa pela aprovação jurídica
   da R4 (`commercial_instrument_template_approvals`), que amarra o hash do
   texto aprovado.
3. Implementar o modelo da §6 com testes, em missão própria e autorizada.
