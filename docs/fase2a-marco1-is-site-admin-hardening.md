# Fase 2A — Marco 1 — Hardening isolado de `public.is_site_admin()`

**Projeto:** Site BDFlow
**Base autoritativa:** commit `cba451e`
**Branch:** `fase2a/marco1-especificacao-sql`
**Revisão:** V2
**Status deste pacote:** *preparado para revisão — nenhum SQL executado, nenhuma escrita no Supabase, nenhum commit/push/merge/deploy.*

> **Não execute nada ainda.** Este documento descreve o que a migration *fará no futuro*, quando autorizada em comando separado. A ordem de execução está no final.

---

## 0. Resumo em uma frase

A fundação V9 está bloqueada apenas porque `public.is_site_admin()` é `SECURITY DEFINER`
sem `search_path` fixo. O hardening resolve isso com **uma única alteração** —
`ALTER FUNCTION ... SET search_path = pg_catalog` — **sem tocar** no corpo, na
assinatura, no proprietário nem nas ACLs da função.

---

## 1. Por que `SECURITY DEFINER` sem `search_path` fixo é um bloqueio

Uma função `SECURITY DEFINER` executa com os privilégios do seu **proprietário**, não
os do chamador. Se ela não fixa `search_path`, a resolução de nomes não qualificados
passa a depender do `search_path` **do chamador** (ou do papel corrente) no momento da
chamada. Um chamador hostil pode antepor um schema controlado (por exemplo via
`pg_temp`) e "sequestrar" a resolução de uma tabela ou função referenciada sem
qualificação, executando código arbitrário com os privilégios elevados do proprietário.
Esse é o padrão de ataque clássico de *search_path hijacking* em funções definer.
Por isso a fundação V9 trata a ausência de `search_path` fixo como um bloqueio duro.

## 2. Por que o corpo atual pode permanecer intacto

O corpo autoritativo (commit `cba451e`) é:

```sql
select exists (
  select 1
  from public.site_admins
  where user_id = auth.uid()
);
```

Ele **não faz uso de nenhum nome não qualificado sensível**: a tabela é referenciada
como `public.site_admins` e a função como `auth.uid()`. Portanto o vetor de ataque não
está no corpo — está apenas na *configuração* da função (`search_path` livre). Fixar o
`search_path` fecha o vetor sem qualquer necessidade de reescrever o corpo.

## 3. `public.site_admins` e `auth.uid()` já estão qualificados

Confirmado na definição autoritativa:

- `public.site_admins` — schema explícito;
- `auth.uid()` — schema explícito.

Não há referência a `site_admins` sem o prefixo `public.`, não há `uid()` sem o prefixo
`auth.`, e não há dependência de `pg_temp`. O preflight e a verificação posterior checam
isso lexicalmente sobre o corpo normalizado.

## 4. Por que `pg_catalog` é suficiente como `search_path`

Com `search_path = pg_catalog`, todos os nomes **não qualificados** resolvem apenas
contra o catálogo do sistema, que não é gravável por papéis comuns e não pode ser
antecedido por um schema controlado pelo atacante. Como o corpo **já qualifica**
tudo o que precisa (`public.site_admins`, `auth.uid()`), essas referências continuam
resolvendo corretamente independentemente do `search_path`. `pg_catalog` é o valor
mínimo, estável e seguro: elimina o vetor de hijacking sem introduzir dependência de
`public` ou de qualquer schema gravável. (Observação: `pg_catalog` está sempre
implicitamente no caminho; fixá-lo explicitamente remove qualquer schema adicional
herdado do chamador.)

## 5. `ALTER FUNCTION` não reescreve o corpo

`ALTER FUNCTION public.is_site_admin() SET search_path = pg_catalog` altera **somente**
`pg_proc.proconfig`. Não recompila, não substitui e não reescreve `pg_proc.prosrc`.
O `OID`, o corpo, a assinatura, o retorno, a linguagem, a volatilidade e o atributo
`SECURITY DEFINER` permanecem idênticos. Por isso **não** se usa `CREATE OR REPLACE`:
recriar a função poderia, por descuido, alterar corpo, proprietário ou privilégios.

## 6. Proprietário e ACLs permanecem inalterados

O hardening **não** altera `proowner` nem `proacl`. A migration captura ambos *antes*
da alteração, aplica exclusivamente o `SET search_path`, e relê *depois* para confirmar,
dentro da mesma transação, que proprietário e ACL não mudaram (comparação
`before == after`, byte a byte). Qualquer divergência aborta com rollback.

## 7. Nenhuma concessão ou revogação de privilégio é executada

A migration **não** executa nenhuma instrução de concessão ou revogação de privilégios.
Os privilégios diretos da função (o `proacl`) são apenas **lidos** para snapshot e
comparação. O arquivo de migration não contém tais instruções — validado estaticamente.

## 8. Nenhuma tabela, índice, trigger ou policy é criada ou alterada

O hardening não cria nem altera tabela, índice, trigger, policy ou RLS. A única mutação
de catálogo é a linha de `proconfig` da própria função. `public.site_admins`, os RPCs
comerciais e as tabelas da Fase 1 permanecem intocados.

## 9. A migration é transacional e *fail-closed*

Toda a migration roda dentro de um único bloco `BEGIN; ... COMMIT;`. Antes de qualquer
mutação, ela repete as checagens essenciais do preflight. Se **qualquer** pré-condição
divergir (função ausente, assinatura, retorno, linguagem, volatilidade, `SECURITY
DEFINER`, hash do corpo, referências seguras, dependências, `proconfig` pré-existente
divergente), a transação lança exceção e **nada** é aplicado.

A comparação de configuração é feita sobre o **`proconfig` integral**, não sobre um
subconjunto filtrado por `search_path=`. Os três estados aceitos são exatamente:

- `proconfig` NULL ou array vazio → segue para o `ALTER` (preflight: `PREFLIGHT_READY`);
- `proconfig` **exatamente** `ARRAY['search_path=pg_catalog']` → interrompe como já
  aplicado (preflight: `ALREADY_APPLIED`);
- **qualquer outro conteúdo** (`search_path` diferente, `search_path` correto acompanhado
  de outra configuração, apenas configurações não relacionadas, múltiplas entradas ou
  valor inesperado) → **bloqueio**, exibindo o `proconfig` integral. Nenhuma configuração
  adicional é preservada silenciosamente.

Após o `ALTER`, exige-se `proconfig IS NOT DISTINCT FROM ARRAY['search_path=pg_catalog']`.

## 10. Qualquer divergência provoca rollback

Após aplicar o `SET search_path`, a migration **re-resolve** a função pela assinatura
exata (`to_regprocedure('public.is_site_admin()')`) e confirma que o **OID resolvido é o
mesmo** de antes. Em seguida relê o estado e compara `before`/`after`. A identidade
estrutural é reconferida: schema continua `public`, nome continua `is_site_admin`, zero
argumentos, `proargtypes` idêntico e *identity arguments* vazios. Se `proconfig` não
ficou exatamente `ARRAY['search_path=pg_catalog']`, ou se OID, assinatura, proprietário,
ACL, corpo, hash, retorno, linguagem, volatilidade ou `SECURITY DEFINER` mudaram, ela
lança exceção. Em um bloco de transação explícito, a exceção deixa a transação em estado
abortado e o `COMMIT` subsequente efetua **rollback** — a base volta ao estado anterior.

## 11. O hardening deve ser aplicado antes do preflight V9

A fundação V9 exige `search_path` fixo em `is_site_admin()` como pré-condição. Portanto:
primeiro o hardening (preflight → migration → verificação posterior), e **só então** o
preflight V9. Rodar o preflight V9 antes do hardening resultará, corretamente, em
bloqueio.

## 12. A fundação V9 permanece bloqueada até a verificação posterior aprovar

Os quatro arquivos da fundação V9 continuam **não aplicados** e **não rastreados**. A
V9 só será liberada depois que `HARDENING_IS_SITE_ADMIN_VERIFICADO` for observado na
verificação posterior — e ainda assim mediante autorização separada.

## 13. `RESET search_path` reintroduz o risco — não é rollback operacional recomendado

Um eventual `ALTER FUNCTION public.is_site_admin() RESET search_path` desfaria o
hardening e **reintroduziria** exatamente o vetor de *search_path hijacking* descrito no
item 1. Por isso **não** é recomendado como procedimento de rollback. O rollback
legítimo deste marco é o próprio mecanismo *fail-closed* da migration (que impede
aplicar um estado inválido); uma vez aplicado corretamente, o estado seguro
(`search_path=pg_catalog`) deve ser mantido.

---

## 14. Critérios de aceite

O marco é considerado aceito quando, **em execução futura autorizada**, observarem-se:

1. Preflight retorna `HARDENING_IS_SITE_ADMIN_PREFLIGHT_READY`
   (ou `HARDENING_IS_SITE_ADMIN_ALREADY_APPLIED`, caso já fixado).
2. Migration conclui com `HARDENING_IS_SITE_ADMIN_APLICADO_COM_CORPO_OWNER_E_ACL_INTACTOS`
   (ou aborta com mensagem clara de "já aplicado", sem alterar nada).
3. Verificação posterior retorna `HARDENING_IS_SITE_ADMIN_VERIFICADO`, com:
   - `proconfig` **integral** satisfazendo `IS NOT DISTINCT FROM ARRAY['search_path=pg_catalog']`;
   - MD5 do corpo normalizado igual a `a65d3c1394e3f45b4afdbf6bba6410a3`;
   - referências a `public.site_admins` e `auth.uid()` presentes; sem `pg_temp`;
   - proprietário e ACL exibidos e confrontados com o snapshot do preflight;
   - `dependencia_site_admins_valida`: tabela `public.site_admins` (relkind `r`),
     coluna `user_id` do tipo `uuid` e **SELECT efetivo do proprietário** da função sobre ela;
   - `auth.uid()` presente pela assinatura exata, retornando `uuid` e com zero argumentos;
   - RPCs protegidas presentes **pela assinatura exata** (via `to_regprocedure`, com OID e
     assinatura encontrada exibidos para revisão), sem aceitar homônimos em outro schema
     nem *overloads* com argumentos diferentes:
     - `public.create_my_partner_owner_registration(text,text,text,text,text,text,text)`;
     - `public.resolve_commercial_region(text,text)`;
     - `public.get_current_commercial_formation(text,text)`.

**Normalização de corpo usada em todos os artefatos** (idêntica nos três SQLs):

```
md5( rtrim( regexp_replace( lower(prosrc), '\s', '', 'g' ), ';' ) )
```

ou seja: minúsculas → remoção de todo espaço em branco → remoção de `;` finais → MD5.
Esperado: `a65d3c1394e3f45b4afdbf6bba6410a3`.

---

## 15. Ordem futura de execução (ainda não autorizada)

1. Executar **somente** o preflight do hardening.
2. Revisar o resultado.
3. Autorizar **separadamente** a migration.
4. Executar a verificação posterior.
5. Somente então executar o preflight V9.
6. Revisar o preflight V9.
7. Autorizar a fundação V9 em **outro** comando separado.

Cada passo é um comando explícito e independente. Nada acima está autorizado por este
pacote.

---

## Registro de correção documental (a aplicar no fechamento, sem alterar SQL da V9)

Durante a revisão da V9 foi encontrada uma referência textual residual:

> Esta V8 mantém a proibição de alterar is_site_admin().

Essa frase deverá ser corrigida para:

> Esta V9 mantém a proibição de alterar is_site_admin().

A correção é **exclusivamente textual** e será realizada no fechamento documental,
antes do commit final, **sem alterar o conteúdo SQL da V9**. Neste trabalho os quatro
arquivos da fundação V9 **não** foram modificados.
