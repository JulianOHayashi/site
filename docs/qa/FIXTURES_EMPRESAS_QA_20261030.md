# Fixtures de empresa QA em Production — auditoria e proposta

**Data:** 2026-10-30 · **Projeto:** SiteDBFLOW `cnsypqynaxdgkcvcmkyx` · **Branch:** `fix/multidevice-session-and-qa-fixtures-20261030`

> **Nada deste documento foi executado em Production.** Toda consulta usada na
> auditoria foi `SELECT`. Os blocos de SQL de escrita abaixo são PROPOSTAS e
> exigem aprovação explícita antes de qualquer execução.

---

## 1. Modelo atual (medido)

```text
site_partner_companies  (empresa legal; 1 por solicitação aprovada)
  ├─ partner_network_bridge_id  UNIQUE  → identidade da REDE no App (imutável)
  ├─ cnpj  UNIQUE enquanto status <> 'archived'   (spc_cnpj_vivo_idx)
  ├─ status ∈ {active, suspended, archived}
  │
  ├─ site_partner_units          (filiais DESTA empresa; company_id FK)
  │     └─ partner_branch_bridge_id UNIQUE → identidade da FILIAL no App
  │
  └─ site_company_members        (owner/managers DESTA empresa; company_id FK)
        ├─ 1 owner vivo por empresa      (scm_um_owner_vivo_idx)
        ├─ 1 empresa como owner por conta (scm_owner_por_conta_idx)
        └─ site_member_unit_bindings  (manager ↔ filial)

Domínio comercial (nicho, exclusividade, pedido, fila) — SEPARADO:
  commercial_exclusivity_orders / commercial_preorders / commercial_sales_waitlist
  commercial_checkout_intents / commercial_master_agreements   (company_id FK)
```

O nicho **não** está em `site_partner_companies`. Ele só existe quando há
pedido, pré-pedido ou fila no domínio comercial.

## 2. As 7 empresas (todas fixtures de QA)

| Empresa (trade_name) | Rede App (`partner_network_bridge_id`) | Unidades ativas | Membros | Tentativas de validação no Site |
|---|---|---:|---|---:|
| BDFlow Gate E Pharmacy Test | `70a07e47-2d90-456e-a710-dfa1263c589a` | 1 | owner (`application_promotion`) | 3 |
| SmallFlags Supermercado Teste | `deb8b2af-3fde-4841-a2d5-d55bdb213a44` | 1 | manager (`manager_invite`) | 0 |
| SmallFlags Vestuário Feminino Teste | `cad36dd1-2398-4594-bb9b-393b30618089` | 1 | manager | 0 |
| SmallFlags Supermercado Etapa 2 Teste | `96f5f908-da7e-4980-918f-a0bf73105a05` | 1 | manager | 0 |
| SmallFlags Vestuário Masculino Teste | `204561e0-0ec5-4a48-be73-4af7a7bfbd78` | 1 | manager | 0 |
| SmallFlags Calçados Femininos Teste | `412b8bf2-b00f-4414-93c0-57b1f1b19952` | 1 | manager | 0 |
| SmallFlags Calçados Masculinos Teste | `dca3e9b5-d4c7-4305-89b2-553a5cc09136` | 1 | manager | 0 |

Referências comerciais dessas 7 empresas: **0** pedidos, **0** pré-pedidos,
**0** fila, **0** checkout intents, **0** acordos mestre.

Observações factuais:
- As seis fixtures de 30/10 têm membro `source = manager_invite`, mas **0**
  linhas em `site_manager_invites`: foram inseridas diretamente para o E2E.
- Todas têm `partner_applications.status = approved` e
  `account_kind = provisional`, como uma candidatura real aprovada.
- Os CNPJs são números de teste válidos no dígito verificador. Enquanto a
  fixture estiver viva, o índice `spc_cnpj_vivo_idx` impede uma empresa real
  com o mesmo CNPJ de ser promovida.

## 3. Isolamento empresa ↔ filial ↔ membro — comprovado

Consulta de verificação: vínculos manager→filial em que a filial pertence a
OUTRA empresa = **0** para as 7 empresas. Cada empresa tem sua própria filial e
seus próprios membros, e o owner da Farmácia não é owner de nenhuma outra (a
regra `scm_owner_por_conta_idx` impede isso). Nenhuma constraint foi relaxada.

## 4. Existe mecanismo para distinguir QA de real?

**Não.** Nenhuma coluna `is_test`, `qa`, `fixture`, `seed`, `sandbox` ou
`environment` existe em `site_partner_companies`, `site_partner_units`,
`site_company_members` ou `partner_applications`. A coluna `environment` que
existe (`commercial_operational_bindings`, `app_provisioning_messages`) indica o
ambiente de PROVISIONAMENTO (`local|staging|production`), não a natureza da
empresa. Reaproveitá-la mudaria o seu sentido, então ela não serve.

## 5. Risco de contaminação — avaliado

| Onde | Fixtures entram hoje? | Por quê |
|---|---|---|
| Métricas de formação (`commercial_formation_gate_report`) | **Não** | Só considera empresas com pedido `signed` |
| Pedidos / pré-pedidos / fila / intents | **Não** | 0 linhas das fixtures |
| Front: listagem admin (`admin_list_partner_applications`) | **Sim** | As 7 solicitações aparecem como `approved`, iguais às reais |
| Fluxos comerciais futuros | **Possível** | Nada impede uma fixture de entrar na fila (`join_my_commercial_future_queue`) ou iniciar checkout |
| Unicidade de CNPJ | **Sim** | O CNPJ da fixture bloqueia o mesmo CNPJ real (seção 2) |

Conclusão: **risco atual baixo para métricas, real para listagem admin e para
o futuro.** O mecanismo mínimo abaixo resolve sem tocar regra comercial.

## 6. Proposta mínima (NÃO executada)

### 6.1 Marcar fixtures — migration proposta (seria a 63)

```sql
-- Marca de natureza da empresa. Default false: toda empresa existente e
-- futura é REAL até que alguém marque explicitamente.
alter table public.site_partner_companies
  add column is_qa_fixture boolean not null default false,
  add column qa_fixture_note text,
  add constraint spc_qa_note_coerente
    check (is_qa_fixture = false or length(btrim(coalesce(qa_fixture_note, ''))) >= 3);
```

Efeito: adiciona 2 colunas com default. Nenhuma linha muda de valor e nenhuma
RPC muda de comportamento. Rollback:

```sql
alter table public.site_partner_companies
  drop constraint spc_qa_note_coerente,
  drop column qa_fixture_note,
  drop column is_qa_fixture;
```

### 6.2 Marcar as 7 linhas — UPDATE exato

Pré-checagem (deve retornar exatamente 7 linhas):

```sql
select id, trade_name, partner_network_bridge_id
from public.site_partner_companies
where id in (
  '7b04fed9-4004-4dfb-bde3-f6dc104503b0','fa2f30d0-7d67-4be0-a5dc-52a3fb62ca02',
  'fa3f30d0-7d67-4be0-a5dc-52a3fb62ca02','c4bdd82c-78df-460b-b343-2eee8ad6adc8',
  '4d2c9ed5-a6e4-4361-90d1-b3a6934a912b','e2602a20-380f-4680-a220-8dab9894226c',
  '3e6e42be-d0eb-4b4e-9443-2ca5beb30fd1');
```

```sql
update public.site_partner_companies
   set is_qa_fixture = true,
       qa_fixture_note = 'E2E benefício Site→App 2026-10-29/30; rede App fixa'
 where id in (<os 7 ids acima>)
   and is_qa_fixture = false;           -- idempotente
-- esperado: UPDATE 7
```

Linhas afetadas: **7** em `site_partner_companies`. Status, membros, filiais,
bridge IDs e histórico **não mudam**. O Portal e a validação continuam
funcionando para as contas de teste. Rollback:

```sql
update public.site_partner_companies
   set is_qa_fixture = false, qa_fixture_note = null
 where id in (<os 7 ids>);
```

### 6.3 Filtros (depois de 6.1/6.2, cada um com aprovação própria)

1. **Listagem admin:** `admin_list_partner_applications` passa a devolver
   `is_qa_fixture` (via `site_partner_companies.source_application_id`) e a UI
   exibe o selo "QA". Só exibição.
2. **Métricas comerciais:** acrescentar `and not c.is_qa_fixture` nas
   consultas que JUNTAM empresas a pedidos e relatórios. Hoje não muda nenhum
   número (0 pedidos de fixture).
3. **Entrada comercial (opcional, decisão de produto):** recusar fixtures em
   `join_my_commercial_future_queue`, `create_commercial_checkout_intent` e
   `admin_register_manual_commercial_order`. Isso é REGRA NOVA e por isso não
   está incluída sem decisão explícita.

## 7. Plano de arquivamento futuro (quando os testes terminarem)

Só `UPDATE`, nunca `DELETE`: `benefit_validation_attempts`,
`site_manager_invites` e as tabelas comerciais referenciam essas linhas por FK,
e o histórico E2E fica preservado. Ordem, em uma transação:

```sql
begin;
-- 1) vínculos manager↔filial ativos das fixtures (esperado: 6)
update public.site_member_unit_bindings b
   set status = 'revoked', revoked_at = now(), revocation_reason = 'Arquivamento de fixture QA'
  from public.site_company_members m
 where b.member_id = m.id and b.status = 'active'
   and m.company_id in (<os 7 ids>);
-- 2) membros (esperado: 7 = 1 owner + 6 managers)
update public.site_company_members
   set status = 'archived'
 where company_id in (<os 7 ids>) and status in ('active','suspended');
-- 3) filiais (esperado: 7)
update public.site_partner_units
   set status = 'archived'
 where company_id in (<os 7 ids>) and status <> 'archived';
-- 4) empresas (esperado: 7) — libera os CNPJs de teste
update public.site_partner_companies
   set status = 'archived'
 where id in (<os 7 ids>) and is_qa_fixture = true and status <> 'archived';
commit;
```

Efeito: as contas de teste perdem o acesso ao Portal
(`get_my_partner_context` só autoriza empresa e membro ativos) e as validações
por essas filiais param. Bridge IDs e histórico ficam intactos; o App não é
tocado. Rollback: os mesmos `UPDATE` com `status = 'active'` (para os bindings:
`status = 'active', revoked_at = null, revocation_reason = null`).

## 8. O que este trabalho NÃO fez

Nenhuma escrita em Production, nenhum DELETE, nenhum owner criado, nenhuma
constraint de owner único relaxada, nenhum nicho atribuído a empresa, nenhum
bridge ID alterado, nenhuma exclusividade ou pedido criado.
