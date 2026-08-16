


SET statement_timeout = 0;
SET lock_timeout = 0;
SET idle_in_transaction_session_timeout = 0;
SET client_encoding = 'UTF8';
SET standard_conforming_strings = on;
SELECT pg_catalog.set_config('search_path', '', false);
SET check_function_bodies = false;
SET xmloption = content;
SET client_min_messages = warning;
SET row_security = off;


COMMENT ON SCHEMA "public" IS 'standard public schema';



CREATE EXTENSION IF NOT EXISTS "pg_stat_statements" WITH SCHEMA "extensions";






CREATE EXTENSION IF NOT EXISTS "pgcrypto" WITH SCHEMA "extensions";






CREATE EXTENSION IF NOT EXISTS "supabase_vault" WITH SCHEMA "vault";






CREATE EXTENSION IF NOT EXISTS "uuid-ossp" WITH SCHEMA "extensions";






CREATE OR REPLACE FUNCTION "public"."aplicar_item_pedido"() RETURNS "trigger"
    LANGUAGE "plpgsql" SECURITY DEFINER
    AS $$
declare
  v_min integer;
  v_base integer;
  v_stock_enabled boolean;
  v_vol numeric;
begin
  select coalesce(p.min_quantity, 10), p.base_price_cents, coalesce(p.stock_enabled, true)
    into v_min, v_base, v_stock_enabled
    from public.products p where p.id = new.product_id;

  if new.quantity < v_min then
    raise exception 'QUANTIDADE_MINIMA';
  end if;

  v_vol := public.desconto_quantidade(new.quantity);
  new.unit_price_cents := round(v_base * (1 - v_vol / 100.0));
  new.total_price_cents := new.unit_price_cents * new.quantity;

  if v_stock_enabled then
    update public.products
       set stock_quantity = stock_quantity - new.quantity
     where id = new.product_id and stock_quantity >= new.quantity;
    if not found then
      raise exception 'ESTOQUE_INSUFICIENTE';
    end if;
  end if;

  return new;
end $$;


ALTER FUNCTION "public"."aplicar_item_pedido"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."audit_logs_block_mutation"() RETURNS "trigger"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'pg_catalog'
    AS $$
begin
  raise exception
    'audit_logs e append-only: % bloqueado. Registre um NOVO evento com corrects_log_id.', tg_op;
  return null;
end;
$$;


ALTER FUNCTION "public"."audit_logs_block_mutation"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."calcular_preco_pedido"("p_cnpj" "text", "p_state" "text", "p_product_id" "uuid", "p_quantidade" integer) RETURNS "jsonb"
    LANGUAGE "plpgsql" STABLE SECURITY DEFINER
    AS $$
declare
  v_cnpj text := public.somente_digitos(p_cnpj);
  v_state text := upper(p_state);
  v_limiar integer := 10;
  v_pagas integer := 0;
  v_preco_a integer;
  v_preco_b integer;
  v_units_a integer := 0;
  v_units_b integer := 0;
begin
  select coalesce(valor::integer, 10) into v_limiar
    from public.config where chave = 'limiar_fidelidade';

  select coalesce(units_paid, 0) into v_pagas
    from public.cnpj_state_loyalty
    where cnpj = v_cnpj and state = v_state;

  select preco_a_cents, preco_b_cents
    into v_preco_a, v_preco_b
    from public.product_state_stock
    where product_id = p_product_id and state = v_state and active;

  if v_pagas >= v_limiar then
    -- já fidelizado: tudo ao Preço B
    v_units_a := 0;
    v_units_b := p_quantidade;
  elsif v_pagas + p_quantidade <= v_limiar then
    -- ainda dentro do limiar: tudo ao Preço A
    v_units_a := p_quantidade;
    v_units_b := 0;
  else
    -- divisão: completa o limiar com Preço A, resto com Preço B
    v_units_a := v_limiar - v_pagas;
    v_units_b := p_quantidade - v_units_a;
  end if;

  return jsonb_build_object(
    'units_a', v_units_a,
    'preco_a_cents', v_preco_a,
    'units_b', v_units_b,
    'preco_b_cents', v_preco_b,
    'total_cents', (v_units_a * v_preco_a) + (v_units_b * v_preco_b),
    'preco_unitario_exibido',
      case when v_pagas >= v_limiar then v_preco_b else v_preco_a end
  );
end $$;


ALTER FUNCTION "public"."calcular_preco_pedido"("p_cnpj" "text", "p_state" "text", "p_product_id" "uuid", "p_quantidade" integer) OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."commercial_city_key"("p_city" "text") RETURNS "text"
    LANGUAGE "sql" IMMUTABLE
    AS $$
  select regexp_replace(
           translate(
             lower(btrim(coalesce(p_city, ''))),
             'áàâãäéèêëíìîïóòôõöúùûüç',
             'aaaaaeeeeiiiiooooouuuuc'
           ),
           '\s+', '-', 'g'
         );
$$;


ALTER FUNCTION "public"."commercial_city_key"("p_city" "text") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."commercial_formation_summary"("p_exclusivity_id" "uuid") RETURNS "jsonb"
    LANGUAGE "sql" STABLE SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
  select jsonb_build_object(
    'total_opportunities',       count(*),
    'contracted_opportunities',  count(*) filter (where status = 'contracted'),
    'total_units',               coalesce(sum(contracted_quantity), 0),
    'contracted_units',          coalesce(sum(contracted_quantity)
                                   filter (where status = 'contracted'), 0),
    'formation_percent',         case
                                   when count(*) = 0 then 0
                                   else round(
                                     100.0 * count(*) filter (where status = 'contracted')
                                     / count(*)
                                   )
                                 end,
    'is_complete',               (
                                   count(*) filter (where status = 'contracted') = 6
                                   and coalesce(sum(contracted_quantity)
                                     filter (where status = 'contracted'), 0) = 84
                                 )
  )
  from public.commercial_opportunities
  where exclusivity_id = p_exclusivity_id;
$$;


ALTER FUNCTION "public"."commercial_formation_summary"("p_exclusivity_id" "uuid") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."commercial_is_valid_uf"("p_uf" "text") RETURNS boolean
    LANGUAGE "sql" IMMUTABLE
    AS $$
  select upper(btrim(coalesce(p_uf, ''))) in (
    'AC','AL','AP','AM','BA','CE','DF','ES','GO','MA','MT','MS','MG',
    'PA','PB','PR','PE','PI','RJ','RN','RS','RO','RR','SC','SP','SE','TO'
  );
$$;


ALTER FUNCTION "public"."commercial_is_valid_uf"("p_uf" "text") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."commercial_opportunities_canonical_qty"() RETURNS "trigger"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
declare
  v_canonical integer;
begin
  select contracted_quantity into v_canonical
    from public.commercial_niches
    where code = new.niche_code;
  if v_canonical is null then
    raise exception 'Nicho % inexistente em commercial_niches.', new.niche_code;
  end if;
  if new.contracted_quantity <> v_canonical then
    raise exception
      'Quantidade % diverge da canônica % para o nicho %.',
      new.contracted_quantity, v_canonical, new.niche_code;
  end if;
  return new;
end;
$$;


ALTER FUNCTION "public"."commercial_opportunities_canonical_qty"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."commercial_region_cities_same_uf"() RETURNS "trigger"
    LANGUAGE "plpgsql"
    AS $$
declare
  v_region_uf text;
begin
  select uf into v_region_uf
    from public.commercial_regions
    where id = new.region_id;
  if v_region_uf is null then
    raise exception 'Região % inexistente.', new.region_id;
  end if;
  if v_region_uf <> new.uf then
    raise exception 'UF da cidade (%) difere da UF da região (%).',
      new.uf, v_region_uf;
  end if;
  return new;
end;
$$;


ALTER FUNCTION "public"."commercial_region_cities_same_uf"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."create_my_partner_owner_registration"("p_full_name" "text", "p_cpf" "text", "p_phone" "text", "p_legal_name" "text", "p_trade_name" "text", "p_cnpj" "text", "p_company_phone" "text" DEFAULT NULL::"text") RETURNS "jsonb"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
declare
  v_uid uuid := auth.uid();
  v_email text;
  v_cpf text := public.somente_digitos(p_cpf);
  v_cnpj text := public.somente_digitos(p_cnpj);
  v_partner_id uuid;
  v_member_id uuid;
  v_constraint text;
begin
  -- exige usuário autenticado (Supabase do SITE)
  if v_uid is null then
    raise exception 'AUTENTICACAO_OBRIGATORIA';
  end if;

  -- validação dos obrigatórios
  if coalesce(trim(p_full_name), '') = '' then raise exception 'NOME_OBRIGATORIO'; end if;
  if coalesce(trim(p_legal_name), '') = '' then raise exception 'RAZAO_SOCIAL_OBRIGATORIA'; end if;
  if coalesce(trim(p_trade_name), '') = '' then raise exception 'NOME_FANTASIA_OBRIGATORIO'; end if;
  if length(v_cpf) <> 11 then raise exception 'CPF_INVALIDO'; end if;
  if length(v_cnpj) <> 14 then raise exception 'CNPJ_INVALIDO'; end if;

  -- REGRA 1: este usuário já é owner (ativo, pendente OU suspenso)?
  -- Erro seguro: nenhum dado da conta/empresa existente é revelado.
  if exists (
    select 1 from public.site_partner_members
     where user_id = v_uid
       and role = 'partner_owner'
       and status <> 'archived'
  ) then
    raise exception 'USUARIO_JA_POSSUI_EMPRESA_PARCEIRA';
  end if;

  -- REGRA 2: este CPF já está vinculado como owner (mesmo em outra
  -- conta de login)? Erro seguro, sem revelar nada do vínculo.
  if exists (
    select 1 from public.site_partner_members
     where cpf = v_cpf
       and role = 'partner_owner'
       and status <> 'archived'
  ) then
    raise exception 'CPF_JA_VINCULADO_A_EMPRESA_PARCEIRA';
  end if;

  -- CNPJ já cadastrado por outra empresa não-arquivada?
  if exists (
    select 1 from public.site_monthly_partners
     where public.somente_digitos(cnpj) = v_cnpj
       and status <> 'archived'
  ) then
    raise exception 'CNPJ_JA_CADASTRADO';
  end if;

  select email into v_email from auth.users where id = v_uid;

  -- cria a EMPRESA (status inicial: pending)
  insert into public.site_monthly_partners
    (trade_name, legal_name, cnpj, contact_name, contact_email,
     contact_phone, owner_user_id, status)
  values
    (trim(p_trade_name), trim(p_legal_name), v_cnpj, trim(p_full_name),
     v_email, coalesce(p_company_phone, p_phone), v_uid, 'pending')
  returning id into v_partner_id;

  -- cria o OWNER (status: active)
  insert into public.site_partner_members
    (partner_id, user_id, role, status, full_name, cpf, phone)
  values
    (v_partner_id, v_uid, 'partner_owner', 'active',
     trim(p_full_name), v_cpf, p_phone)
  returning id into v_member_id;

  -- atualiza site_profiles apenas de forma compatível com a estrutura
  -- existente (auth_user_id não é único na tabela — sem upsert cego)
  if exists (select 1 from public.site_profiles where auth_user_id = v_uid) then
    update public.site_profiles
       set name = coalesce(name, trim(p_full_name)),
           phone = coalesce(phone, p_phone),
           customer_type = coalesce(customer_type, 'partner_company'),
           updated_at = now()
     where auth_user_id = v_uid;
  else
    insert into public.site_profiles
      (auth_user_id, customer_type, name, cnpj, email, phone)
    values
      (v_uid, 'partner_company', trim(p_full_name), v_cnpj, v_email, p_phone);
  end if;

  return jsonb_build_object(
    'partner_id', v_partner_id,
    'member_id', v_member_id,
    'role', 'partner_owner',
    'partner_status', 'pending',
    'member_status', 'active'
  );

exception
  -- Corrida entre requisições simultâneas: os índices únicos são a
  -- barreira final. Identificamos a constraint responsável via
  -- GET STACKED DIAGNOSTICS e convertemos para erros seguros —
  -- o nome técnico do índice NUNCA chega ao usuário do portal.
  when unique_violation then
    get stacked diagnostics v_constraint = constraint_name;
    if v_constraint = 'uq_site_monthly_partners_cnpj_normalized' then
      raise exception 'CNPJ_JA_CADASTRADO';
    elsif v_constraint = 'uq_owner_por_usuario' then
      raise exception 'USUARIO_JA_POSSUI_EMPRESA_PARCEIRA';
    elsif v_constraint = 'uq_owner_por_cpf' then
      raise exception 'CPF_JA_VINCULADO_A_EMPRESA_PARCEIRA';
    elsif v_constraint = 'uq_one_owner_per_partner' then
      raise exception 'CADASTRO_DUPLICADO';
    else
      raise exception 'CADASTRO_DUPLICADO';
    end if;
end $$;


ALTER FUNCTION "public"."create_my_partner_owner_registration"("p_full_name" "text", "p_cpf" "text", "p_phone" "text", "p_legal_name" "text", "p_trade_name" "text", "p_cnpj" "text", "p_company_phone" "text") OWNER TO "postgres";

SET default_tablespace = '';

SET default_table_access_method = "heap";


CREATE TABLE IF NOT EXISTS "public"."legal_documents" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "doc_type" "text" NOT NULL,
    "version" "text" NOT NULL,
    "title" "text" NOT NULL,
    "content" "text",
    "content_url" "text",
    "content_hash" "text",
    "status" "text" DEFAULT 'draft'::"text" NOT NULL,
    "is_material_change" boolean DEFAULT false NOT NULL,
    "effective_from" timestamp with time zone,
    "effective_to" timestamp with time zone,
    "published_at" timestamp with time zone,
    "published_by" "uuid",
    "notes" "text",
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "updated_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    CONSTRAINT "legal_documents_archived_complete" CHECK ((("status" <> 'archived'::"text") OR (((("content" IS NOT NULL) AND ("length"("btrim"("content")) > 0)) OR (("content_url" IS NOT NULL) AND ("length"("btrim"("content_url")) > 0))) AND ("content_hash" IS NOT NULL) AND ("length"("btrim"("content_hash")) > 0) AND ("published_at" IS NOT NULL) AND ("published_by" IS NOT NULL) AND ("effective_from" IS NOT NULL) AND ("effective_to" IS NOT NULL)))),
    CONSTRAINT "legal_documents_published_complete" CHECK ((("status" <> 'published'::"text") OR (((("content" IS NOT NULL) AND ("length"("btrim"("content")) > 0)) OR (("content_url" IS NOT NULL) AND ("length"("btrim"("content_url")) > 0))) AND ("content_hash" IS NOT NULL) AND ("length"("btrim"("content_hash")) > 0) AND ("published_at" IS NOT NULL) AND ("published_by" IS NOT NULL) AND ("effective_from" IS NOT NULL)))),
    CONSTRAINT "legal_documents_status_allowed" CHECK (("status" = ANY (ARRAY['draft'::"text", 'published'::"text", 'archived'::"text"]))),
    CONSTRAINT "legal_documents_title_nonempty" CHECK (("length"("btrim"("title")) > 0)),
    CONSTRAINT "legal_documents_type_allowed" CHECK (("doc_type" = ANY (ARRAY['privacy_notice'::"text", 'provisional_account_terms'::"text", 'truthfulness_declaration'::"text", 'document_analysis_authorization'::"text", 'representation_declaration'::"text", 'future_commercial_terms'::"text"]))),
    CONSTRAINT "legal_documents_version_nonempty" CHECK (("length"("btrim"("version")) > 0)),
    CONSTRAINT "legal_documents_vigencia_coerente" CHECK ((("effective_to" IS NULL) OR (("effective_from" IS NOT NULL) AND ("effective_to" > "effective_from"))))
);


ALTER TABLE "public"."legal_documents" OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."current_legal_document"("p_doc_type" "text") RETURNS "public"."legal_documents"
    LANGUAGE "sql" STABLE SECURITY DEFINER
    SET "search_path" TO 'pg_catalog'
    AS $$
  select d.*
    from public.legal_documents d
   where d.doc_type = p_doc_type
     and d.status = 'published'
     and d.effective_from <= now()
     and (d.effective_to is null or d.effective_to > now())
   order by d.effective_from desc, d.published_at desc, d.id
   limit 1;
$$;


ALTER FUNCTION "public"."current_legal_document"("p_doc_type" "text") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."desconto_para_cnpj"("p_cnpj" "text") RETURNS numeric
    LANGUAGE "plpgsql" STABLE SECURITY DEFINER
    AS $$
declare
  v_cnpj text := public.somente_digitos(p_cnpj);
  v_pct numeric := 0;
begin
  if length(v_cnpj) <> 14 then return 0; end if;
  if exists (
    select 1 from public.orders o
    where public.somente_digitos(o.cnpj) = v_cnpj
      and o.status not in ('draft', 'cancelled')
  ) then
    select valor into v_pct from public.config where chave = 'desconto_fidelidade_pct';
  end if;
  return coalesce(v_pct, 0);
end $$;


ALTER FUNCTION "public"."desconto_para_cnpj"("p_cnpj" "text") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."desconto_quantidade"("p_qtd" integer) RETURNS numeric
    LANGUAGE "sql" STABLE
    AS $$
  select coalesce((select desconto_pct from public.faixas_quantidade
                   where min_qtd <= p_qtd order by min_qtd desc limit 1), 0);
$$;


ALTER FUNCTION "public"."desconto_quantidade"("p_qtd" integer) OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."devolver_estoque_item"() RETURNS "trigger"
    LANGUAGE "plpgsql" SECURITY DEFINER
    AS $$
begin
  update public.products
     set stock_quantity = stock_quantity + old.quantity
   where id = old.product_id and coalesce(stock_enabled, true);
  return old;
end $$;


ALTER FUNCTION "public"."devolver_estoque_item"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."fase2a_touch_updated_at"() RETURNS "trigger"
    LANGUAGE "plpgsql"
    SET "search_path" TO 'pg_catalog'
    AS $$
begin
  new.updated_at := now();
  return new;
end;
$$;


ALTER FUNCTION "public"."fase2a_touch_updated_at"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."get_current_commercial_formation"("p_uf" "text", "p_city" "text") RETURNS "jsonb"
    LANGUAGE "plpgsql" STABLE SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
declare
  v_region jsonb;
  v_region_id uuid;
  v_exc record;
  v_opportunities jsonb;
  v_summary jsonb;
begin
  v_region := public.resolve_commercial_region(p_uf, p_city);

  if coalesce((v_region->>'region_available')::boolean, false) = false then
    return jsonb_build_object('region_available', false, 'region', v_region);
  end if;

  v_region_id := (v_region->>'region_id')::uuid;

  select e.* into v_exc
    from public.commercial_exclusivities e
    where e.region_id = v_region_id and e.is_current
    limit 1;

  if v_exc.id is null then
    return jsonb_build_object(
      'region_available', true,
      'exclusivity_available', false,
      'region', v_region
    );
  end if;

  select jsonb_agg(
           jsonb_build_object(
             'id',                  o.id,
             'exclusivity_id',      o.exclusivity_id,
             'niche_code',          o.niche_code,
             'display_name',        n.display_name,
             'contracted_quantity', o.contracted_quantity,
             'status',              o.status,
             'sort_order',          n.sort_order
           ) order by n.sort_order
         )
    into v_opportunities
    from public.commercial_opportunities o
    join public.commercial_niches n on n.code = o.niche_code
    where o.exclusivity_id = v_exc.id;

  v_summary := public.commercial_formation_summary(v_exc.id);

  return jsonb_build_object(
    'region_available', true,
    'exclusivity_available', true,
    'region', v_region,
    'exclusivity', jsonb_build_object(
      'id',              v_exc.id,
      'region_id',       v_exc.region_id,
      'sequence_number', v_exc.sequence_number,
      'status',          v_exc.status,
      'is_current',      v_exc.is_current,
      'planned_start_at',v_exc.planned_start_at
    ),
    'summary', v_summary,
    'opportunities', coalesce(v_opportunities, '[]'::jsonb)
  );
end;
$$;


ALTER FUNCTION "public"."get_current_commercial_formation"("p_uf" "text", "p_city" "text") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."get_current_legal_documents"() RETURNS TABLE("doc_type" "text", "version" "text", "title" "text", "content" "text", "content_url" "text", "content_hash" "text", "is_material_change" boolean, "effective_from" timestamp with time zone, "effective_to" timestamp with time zone)
    LANGUAGE "sql" STABLE SECURITY DEFINER
    SET "search_path" TO 'pg_catalog'
    AS $$
  select d.doc_type, d.version, d.title, d.content, d.content_url, d.content_hash,
         d.is_material_change, d.effective_from, d.effective_to
    from public.legal_documents d
   where d.status = 'published'
     and d.effective_from <= now()
     and (d.effective_to is null or d.effective_to > now())
   order by d.doc_type;
$$;


ALTER FUNCTION "public"."get_current_legal_documents"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."get_my_legal_acceptances"() RETURNS TABLE("acceptance_id" "uuid", "doc_type" "text", "version" "text", "title" "text", "content_hash" "text", "is_material_change" boolean, "context" "text", "accepted_at" timestamp with time zone, "revoked_at" timestamp with time zone)
    LANGUAGE "sql" STABLE SECURITY DEFINER
    SET "search_path" TO 'pg_catalog'
    AS $$
  select a.id, d.doc_type, d.version, d.title, d.content_hash,
         d.is_material_change, a.context, a.accepted_at, a.revoked_at
    from public.legal_acceptances a
    join public.legal_documents  d on d.id = a.legal_document_id
   where auth.uid() is not null
     and a.auth_user_id = auth.uid()
   order by a.accepted_at desc;
$$;


ALTER FUNCTION "public"."get_my_legal_acceptances"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."get_my_notifications"() RETURNS TABLE("notification_id" "uuid", "channel" "text", "template_key" "text", "status_publico" "text", "correlation_entity_type" "text", "correlation_entity_id" "text", "created_at" timestamp with time zone, "sent_at" timestamp with time zone, "read_at" timestamp with time zone)
    LANGUAGE "sql" STABLE SECURITY DEFINER
    SET "search_path" TO 'pg_catalog'
    AS $$
  select n.id, n.channel, n.template_key,
         case
           when n.status in ('pending','scheduled','sending') then 'processing'
           when n.status in ('sent','delivered')              then 'delivered'
           when n.status = 'read'                             then 'read'
           when n.status = 'failed'                           then 'failed'
           when n.status = 'cancelled'                        then 'cancelled'
         end,
         n.correlation_entity_type, n.correlation_entity_id,
         n.created_at, n.sent_at, n.read_at
    from public.notification_events n
   where auth.uid() is not null
     and n.recipient_user_id = auth.uid()
   order by n.created_at desc;
$$;


ALTER FUNCTION "public"."get_my_notifications"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."is_site_admin"() RETURNS boolean
    LANGUAGE "sql" STABLE SECURITY DEFINER
    SET "search_path" TO 'pg_catalog'
    AS $$ select exists (select 1 from public.site_admins where user_id = auth.uid()) $$;


ALTER FUNCTION "public"."is_site_admin"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."legal_acceptances_protect"() RETURNS "trigger"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'pg_catalog'
    AS $$
begin
  if tg_op = 'DELETE' then
    raise exception 'Aceite juridico nao pode ser excluido (id=%). Use revogacao.', old.id;
  end if;

  if new.id                     is distinct from old.id
  or new.subject_type           is distinct from old.subject_type
  or new.subject_id             is distinct from old.subject_id
  or new.partner_application_id is distinct from old.partner_application_id
  or new.legal_document_id      is distinct from old.legal_document_id
  or new.accepted_at            is distinct from old.accepted_at
  or new.context                is distinct from old.context
  or new.origin                 is distinct from old.origin
  or new.ip                     is distinct from old.ip
  or new.user_agent             is distinct from old.user_agent
  or new.evidence               is distinct from old.evidence
  or new.created_at             is distinct from old.created_at then
    raise exception
      'Campos de evidencia do aceite sao imutaveis (id=%). Permitido apenas promover o vinculo ou revogar.', old.id;
  end if;

  -- PROMOCAO ATOMICA: a primeira associacao com uma conta deve preencher
  -- linked_auth_user_id E auth_user_id na MESMA atualizacao, com o mesmo valor.
  if old.linked_auth_user_id is null and new.linked_auth_user_id is not null then
    if new.auth_user_id is null then
      raise exception
        'Promocao deve ser atomica (id=%): auth_user_id nao pode ficar NULL ao definir linked_auth_user_id.', old.id;
    end if;
    if new.auth_user_id is distinct from new.linked_auth_user_id then
      raise exception
        'Promocao deve ser atomica (id=%): auth_user_id deve ser igual a linked_auth_user_id.', old.id;
    end if;
  end if;

  if old.linked_auth_user_id is not null
     and new.linked_auth_user_id is distinct from old.linked_auth_user_id then
    raise exception
      'linked_auth_user_id e imutavel (id=%): ja vinculado a %, nao pode ser apagado nem substituido.',
      old.id, old.linked_auth_user_id;
  end if;

  if new.auth_user_id is not null
     and new.auth_user_id is distinct from coalesce(new.linked_auth_user_id, new.auth_user_id) then
    raise exception 'auth_user_id deve ser igual a linked_auth_user_id (id=%).', old.id;
  end if;
  if old.auth_user_id is not null
     and new.auth_user_id is not null
     and new.auth_user_id is distinct from old.auth_user_id then
    raise exception 'auth_user_id ja vinculado nao pode ser trocado por outro (id=%).', old.id;
  end if;
  if old.auth_user_id is null
     and new.auth_user_id is not null
     and old.linked_auth_user_id is not null
     and new.auth_user_id is distinct from old.linked_auth_user_id then
    raise exception
      'Aceite ja vinculado a % nao pode ser revinculado a outra conta (id=%).',
      old.linked_auth_user_id, old.id;
  end if;

  if old.revoked_at is not null then
    if new.revoked_at is distinct from old.revoked_at then
      raise exception 'revoked_at e imutavel apos a revogacao (id=%).', old.id;
    end if;
    if new.revocation_reason is distinct from old.revocation_reason then
      raise exception 'revocation_reason e imutavel apos a revogacao (id=%).', old.id;
    end if;
  end if;

  return new;
end;
$$;


ALTER FUNCTION "public"."legal_acceptances_protect"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."legal_document_versions"("p_doc_type" "text") RETURNS TABLE("doc_type" "text", "version" "text", "title" "text", "content" "text", "content_url" "text", "content_hash" "text", "is_material_change" boolean, "effective_from" timestamp with time zone, "effective_to" timestamp with time zone, "status" "text")
    LANGUAGE "sql" STABLE SECURITY DEFINER
    SET "search_path" TO 'pg_catalog'
    AS $$
  select d.doc_type, d.version, d.title, d.content, d.content_url, d.content_hash,
         d.is_material_change, d.effective_from, d.effective_to, d.status
    from public.legal_documents d
   where auth.uid() is not null
     and d.doc_type = p_doc_type
     and d.status in ('published','archived')
     and d.effective_from is not null
     and d.effective_from <= now()
   order by d.effective_from desc, d.version desc;
$$;


ALTER FUNCTION "public"."legal_document_versions"("p_doc_type" "text") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."legal_documents_check_overlap"() RETURNS "trigger"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'pg_catalog'
    AS $$
declare
  v_conflitos int;
begin
  if new.status not in ('published', 'archived') then
    return new;
  end if;

  perform pg_advisory_xact_lock(hashtext('legal_documents:' || new.doc_type));

  select count(*) into v_conflitos
    from public.legal_documents d
   where d.doc_type = new.doc_type
     and d.status in ('published', 'archived')
     and d.id <> new.id
     and tstzrange(d.effective_from, d.effective_to, '[)')
      && tstzrange(new.effective_from, new.effective_to, '[)');

  if v_conflitos > 0 then
    raise exception
      'Vigencia sobreposta: ja existe versao publicada ou arquivada de "%" cobrindo o intervalo informado.',
      new.doc_type;
  end if;
  return new;
end;
$$;


ALTER FUNCTION "public"."legal_documents_check_overlap"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."legal_documents_protect"() RETURNS "trigger"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'pg_catalog'
    AS $$
begin
  -- DELETE: a imutabilidade juridica abrange exclusao. Neste marco NENHUM
  -- legal_document pode ser excluido — nem rascunho —, porque ainda nao existe
  -- RPC administrativa auditada para exclusao controlada. A exclusao de
  -- rascunhos (nunca publicados e sem aceite) sera criada em migration
  -- separada, com auditoria.
  if tg_op = 'DELETE' then
    raise exception
      'Documento juridico nao pode ser excluido (id=%, status=%). Publicados e arquivados sao imutaveis; a exclusao controlada de rascunhos exige RPC administrativa auditada (migration separada).',
      old.id, old.status;
  end if;

  if tg_op = 'INSERT' then
    if new.status = 'archived' then
      raise exception
        'Documento nao pode ser criado como archived: o arquivamento so ocorre a partir de published.';
    end if;
    return new;
  end if;

  if old.status = 'archived' then
    if new.status <> 'archived' then
      raise exception 'Versao arquivada nao pode retornar para "%" (id=%).', new.status, old.id;
    end if;
    if new.doc_type           is distinct from old.doc_type
    or new.version            is distinct from old.version
    or new.title              is distinct from old.title
    or new.content            is distinct from old.content
    or new.content_url        is distinct from old.content_url
    or new.content_hash       is distinct from old.content_hash
    or new.is_material_change is distinct from old.is_material_change
    or new.effective_from     is distinct from old.effective_from
    or new.effective_to       is distinct from old.effective_to
    or new.published_at       is distinct from old.published_at
    or new.published_by       is distinct from old.published_by then
      raise exception 'Versao arquivada e imutavel (id=%).', old.id;
    end if;
    return new;
  end if;

  if old.status = 'draft' then
    if new.status = 'archived' then
      raise exception
        'Rascunho nao pode ser arquivado (id=%): archived so a partir de published.', old.id;
    end if;
    if new.status not in ('draft','published') then
      raise exception 'Transicao invalida a partir de draft (id=%).', old.id;
    end if;
    return new;
  end if;

  if old.status = 'published' then
    if new.doc_type           is distinct from old.doc_type
    or new.version            is distinct from old.version
    or new.title              is distinct from old.title
    or new.content            is distinct from old.content
    or new.content_url        is distinct from old.content_url
    or new.content_hash       is distinct from old.content_hash
    or new.is_material_change is distinct from old.is_material_change
    or new.effective_from     is distinct from old.effective_from
    or new.published_at       is distinct from old.published_at
    or new.published_by       is distinct from old.published_by then
      raise exception 'Versao publicada e imutavel (id=%). Publique uma NOVA versao.', old.id;
    end if;

    if new.status not in ('published','archived') then
      raise exception 'Transicao invalida a partir de published (id=%).', old.id;
    end if;

    if old.effective_to is not null and new.effective_to is distinct from old.effective_to then
      raise exception 'effective_to ja definido nao pode ser alterado nem removido (id=%).', old.id;
    end if;
    if new.effective_to is not null and new.effective_to <= old.effective_from then
      raise exception 'effective_to deve ser posterior a effective_from (id=%).', old.id;
    end if;

    if new.status = 'archived' then
      if new.effective_to is null then
        raise exception 'Arquivamento exige effective_to definido (id=%).', old.id;
      end if;
      if new.effective_to > now() then
        raise exception
          'Arquivamento exige vigencia ja encerrada; effective_to esta no futuro (id=%).', old.id;
      end if;
    end if;
  end if;

  return new;
end;
$$;


ALTER FUNCTION "public"."legal_documents_protect"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."notification_events_protect"() RETURNS "trigger"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'pg_catalog'
    AS $$
declare
  v_iniciado_old boolean;
  v_iniciado_new boolean;
  v_iniciado     boolean;
  v_transicao    text;
  v_mudou        boolean;
  v_ant          public.notification_events;
  v_filho_id     uuid;
  v_permitidas   text[] := array[
    'pending>scheduled','pending>sending','pending>cancelled','pending>failed',
    'scheduled>sending','scheduled>cancelled','scheduled>failed',
    'sending>sent','sending>failed','sending>cancelled',
    'sent>delivered','sent>failed',
    'delivered>read',
    'failed>scheduled','failed>cancelled'
  ];
begin
  -- =====================================================================
  -- INSERT: a maquina de estados tambem vale na criacao. So se cria em
  -- pending ou scheduled; nenhum marco de progresso pode vir preenchido.
  -- =====================================================================
  if tg_op = 'INSERT' then
    if new.status not in ('pending','scheduled') then
      raise exception
        'Notificacao so pode ser criada como pending ou scheduled (recebido: %). Cancelamento e demais estados exigem transicao auditavel.',
        new.status;
    end if;
    if new.attempt_count <> 0 then
      raise exception 'attempt_count deve comecar em 0 (recebido: %).', new.attempt_count;
    end if;
    if new.status = 'pending' and new.scheduled_for is not null then
      raise exception 'Criacao em pending exige scheduled_for NULL.';
    end if;
    if new.status = 'scheduled' and new.scheduled_for is null then
      raise exception 'Criacao em scheduled exige scheduled_for preenchido.';
    end if;
    if new.sent_at is not null or new.delivered_at is not null or new.read_at is not null
    or new.first_failed_at is not null or new.last_failed_at is not null then
      raise exception
        'Criacao nao pode trazer marcos de envio, entrega, leitura ou falha preenchidos.';
    end if;
    if new.provider is not null or new.provider_message_id is not null
    or new.error_code is not null or new.error_message is not null then
      raise exception
        'Criacao nao pode trazer provider, provider_message_id ou dados de erro preenchidos.';
    end if;

    -- Cadeia de retentativa: o evento anterior precisa justificar um NOVO
    -- evento e ser integralmente equivalente ao atual.
    if new.retry_of_event_id is not null then
      if new.retry_of_event_id = new.id then
        raise exception 'retry_of_event_id nao pode referenciar a propria linha.';
      end if;

      -- BLOQUEIO DE LINHA (FOR SHARE): impede UPDATE/DELETE concorrente do
      -- evento anterior entre a validacao e a insercao desta retentativa.
      -- Sem ele, o anterior poderia sair de 'failed' (p.ex. para 'cancelled')
      -- logo apos a checagem, deixando uma cadeia de retentativa incoerente.
      -- E um bloqueio de LINHA, nunca da tabela inteira.
      select * into v_ant from public.notification_events
       where id = new.retry_of_event_id
       for share;
      if not found then
        raise exception 'retry_of_event_id % nao existe.', new.retry_of_event_id;
      end if;

      -- O anterior tem de estar TERMINAL em failed.
      if v_ant.status <> 'failed' then
        raise exception
          'retry_of_event_id deve apontar para evento com status failed (encontrado: %).', v_ant.status;
      end if;

      -- E precisa haver EVIDENCIA de envio externo: caso contrario a
      -- retentativa deveria permanecer no mesmo evento (failed -> scheduled).
      if v_ant.sent_at is null and v_ant.provider_message_id is null then
        raise exception
          'Evento % falhou ANTES de qualquer envio externo: use a transicao failed -> scheduled no proprio evento, sem criar um novo.',
          v_ant.id;
      end if;

      -- Equivalencia integral com o evento anterior.
      if v_ant.channel is distinct from new.channel then
        raise exception 'Retentativa deve usar o mesmo channel (% vs %).', new.channel, v_ant.channel;
      end if;
      if v_ant.recipient_user_id is distinct from new.recipient_user_id then
        raise exception 'Retentativa deve manter o mesmo recipient_user_id.';
      end if;
      if v_ant.recipient_address is distinct from new.recipient_address then
        raise exception 'Retentativa deve manter o mesmo recipient_address.';
      end if;
      if v_ant.template_key is distinct from new.template_key then
        raise exception 'Retentativa deve manter o mesmo template_key.';
      end if;
      if v_ant.template_data is distinct from new.template_data then
        raise exception 'Retentativa deve manter o mesmo template_data.';
      end if;
      if v_ant.correlation_entity_type is distinct from new.correlation_entity_type
      or v_ant.correlation_entity_id   is distinct from new.correlation_entity_id then
        raise exception 'Retentativa deve preservar a mesma correlacao empresarial.';
      end if;

      -- Nada e reaproveitado do envio anterior.
      if v_ant.idempotency_key = new.idempotency_key then
        raise exception 'Retentativa exige NOVA idempotency_key (a anterior nao pode ser reutilizada).';
      end if;
      if new.provider_message_id is not null then
        raise exception 'Retentativa nao pode reutilizar provider_message_id.';
      end if;
    end if;

    return new;
  end if;

  -- =====================================================================
  -- UPDATE
  -- =====================================================================
  if new.idempotency_key is distinct from old.idempotency_key then
    raise exception 'idempotency_key e imutavel (id=%).', old.id;
  end if;
  if new.channel is distinct from old.channel then
    raise exception 'channel e imutavel (id=%).', old.id;
  end if;
  if new.created_at is distinct from old.created_at then
    raise exception 'created_at e imutavel (id=%).', old.id;
  end if;
  if new.retry_of_event_id is distinct from old.retry_of_event_id then
    raise exception 'retry_of_event_id e imutavel (id=%).', old.id;
  end if;

  -- ---------------------------------------------------------------------
  -- CONGELAMENTO DO EVENTO PAI: se já existe um filho apontando para esta
  -- linha, ela e a ORIGEM de uma cadeia de retentativa e precisa permanecer
  -- coerente com o filho. Le-se o filho com FOR SHARE (bloqueio de LINHA,
  -- nunca da tabela) para impedir que ele seja removido/alterado em paralelo
  -- enquanto validamos.
  -- ---------------------------------------------------------------------
  select f.id into v_filho_id
    from public.notification_events f
   where f.retry_of_event_id = old.id
   limit 1
   for share of f;

  if v_filho_id is not null then
    if new.status <> 'failed' then
      raise exception
        'Evento % e origem da retentativa % e deve permanecer failed (tentativa de ir para %).',
        old.id, v_filho_id, new.status;
    end if;
    if new.sent_at             is distinct from old.sent_at
    or new.provider_message_id is distinct from old.provider_message_id
    or new.channel             is distinct from old.channel
    or new.recipient_user_id   is distinct from old.recipient_user_id
    or new.recipient_address   is distinct from old.recipient_address
    or new.template_key        is distinct from old.template_key
    or new.template_data       is distinct from old.template_data
    or new.correlation_entity_type is distinct from old.correlation_entity_type
    or new.correlation_entity_id   is distinct from old.correlation_entity_id then
      raise exception
        'Evento % possui a retentativa %: os campos usados na validacao de equivalencia (sent_at, provider_message_id, channel, destinatario, template, template_data e correlacao) nao podem ser alterados.',
        old.id, v_filho_id;
    end if;
  end if;

  v_mudou     := new.status is distinct from old.status;
  v_transicao := old.status || '>' || new.status;

  if v_mudou and not (v_transicao = any(v_permitidas)) then
    raise exception 'Transicao de status invalida: % (id=%).', v_transicao, old.id;
  end if;

  -- Retentativa NO MESMO evento so antes de qualquer envio externo.
  if v_transicao = 'failed>scheduled' then
    if old.sent_at is not null
    or old.delivered_at is not null
    or old.provider_message_id is not null then
      raise exception
        'failed -> scheduled nao e permitido apos envio externo (id=%): sent_at/delivered_at/provider_message_id ja existem. Crie um NOVO notification_event com nova idempotency_key e retry_of_event_id apontando para este.',
        old.id;
    end if;
  end if;

  -- attempt_count: +1 exatamente ao entrar em sending.
  if v_mudou and v_transicao in ('pending>sending','scheduled>sending') then
    if new.attempt_count is distinct from old.attempt_count + 1 then
      raise exception
        'Entrada em sending exige attempt_count = anterior + 1 (id=%): % -> %.',
        old.id, old.attempt_count, new.attempt_count;
    end if;
  elsif new.attempt_count is distinct from old.attempt_count then
    raise exception
      'attempt_count so pode mudar ao entrar em sending (id=%, transicao=%): % -> %.',
      old.id, v_transicao, old.attempt_count, new.attempt_count;
  end if;

  -- Congelamento apos o inicio do processamento (estado antigo OU novo).
  v_iniciado_old := (old.attempt_count > 0) or (old.status not in ('pending','scheduled'));
  v_iniciado_new := (new.attempt_count > 0) or (new.status not in ('pending','scheduled'));
  v_iniciado := v_iniciado_old or v_iniciado_new;

  if v_iniciado then
    if new.recipient_user_id       is distinct from old.recipient_user_id
    or new.recipient_address       is distinct from old.recipient_address
    or new.template_key            is distinct from old.template_key
    or new.template_data           is distinct from old.template_data
    or new.correlation_entity_type is distinct from old.correlation_entity_type
    or new.correlation_entity_id   is distinct from old.correlation_entity_id then
      raise exception
        'Destinatario, template, template_data e correlacao congelam no inicio do processamento (id=%).', old.id;
    end if;
  end if;

  -- scheduled_for: apenas pending>scheduled e failed>scheduled.
  if new.scheduled_for is distinct from old.scheduled_for then
    if not (v_mudou and v_transicao in ('pending>scheduled','failed>scheduled')) then
      raise exception
        'scheduled_for so pode ser definido/alterado em pending->scheduled ou failed->scheduled (id=%, transicao=%).',
        old.id, v_transicao;
    end if;
  end if;

  -- Marcos de progresso: preenchidos apenas na transicao correspondente e
  -- nunca removidos ou reescritos.
  if old.sent_at is not null and new.sent_at is distinct from old.sent_at then
    raise exception 'sent_at preenchido nao pode ser removido nem reescrito (id=%).', old.id;
  end if;
  if old.sent_at is null and new.sent_at is not null and v_transicao <> 'sending>sent' then
    raise exception 'sent_at so pode ser preenchido na transicao sending -> sent (id=%).', old.id;
  end if;

  if old.delivered_at is not null and new.delivered_at is distinct from old.delivered_at then
    raise exception 'delivered_at preenchido nao pode ser removido nem reescrito (id=%).', old.id;
  end if;
  if old.delivered_at is null and new.delivered_at is not null and v_transicao <> 'sent>delivered' then
    raise exception 'delivered_at so pode ser preenchido na transicao sent -> delivered (id=%).', old.id;
  end if;

  if old.read_at is not null and new.read_at is distinct from old.read_at then
    raise exception 'read_at preenchido nao pode ser removido nem reescrito (id=%).', old.id;
  end if;
  if old.read_at is null and new.read_at is not null and v_transicao <> 'delivered>read' then
    raise exception 'read_at so pode ser preenchido na transicao delivered -> read (id=%).', old.id;
  end if;

  -- Falhas: first imutavel, last avanca; fora da entrada em failed, imutaveis.
  if v_mudou and new.status = 'failed' then
    if old.first_failed_at is null then
      if new.first_failed_at is null or new.last_failed_at is null then
        raise exception
          'Primeira falha exige first_failed_at e last_failed_at preenchidos (id=%).', old.id;
      end if;
    else
      if new.first_failed_at is distinct from old.first_failed_at then
        raise exception 'first_failed_at e imutavel apos a primeira falha (id=%).', old.id;
      end if;
      if new.last_failed_at is null or new.last_failed_at <= old.last_failed_at then
        raise exception
          'Nova falha exige last_failed_at posterior ao anterior (id=%): % -> %.',
          old.id, old.last_failed_at, new.last_failed_at;
      end if;
    end if;
  else
    if new.first_failed_at is distinct from old.first_failed_at then
      raise exception
        'first_failed_at so pode ser definido na entrada em failed (id=%, transicao=%).', old.id, v_transicao;
    end if;
    if new.last_failed_at is distinct from old.last_failed_at then
      raise exception
        'last_failed_at so pode avancar na entrada em failed (id=%, transicao=%).', old.id, v_transicao;
    end if;
  end if;

  -- Provedor: preenchimento unico, apenas em sending/sent.
  if old.provider is not null and new.provider is distinct from old.provider then
    raise exception 'provider preenchido nao pode ser removido nem substituido (id=%).', old.id;
  end if;
  if old.provider_message_id is not null
     and new.provider_message_id is distinct from old.provider_message_id then
    raise exception 'provider_message_id preenchido nao pode ser removido nem substituido (id=%).', old.id;
  end if;
  if (old.provider is null and new.provider is not null)
     or (old.provider_message_id is null and new.provider_message_id is not null) then
    if new.status not in ('sending','sent') then
      raise exception
        'provider/provider_message_id so podem ser preenchidos em sending ou sent (id=%, status=%).',
        old.id, new.status;
    end if;
  end if;

  -- Erros: apenas na entrada em failed.
  if new.error_code    is distinct from old.error_code
  or new.error_message is distinct from old.error_message then
    if not (v_mudou and new.status = 'failed') then
      raise exception
        'error_code/error_message so podem ser definidos na entrada em failed (id=%, transicao=%).',
        old.id, v_transicao;
    end if;
  end if;

  return new;
end;
$$;


ALTER FUNCTION "public"."notification_events_protect"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."processar_item_pedido"() RETURNS "trigger"
    LANGUAGE "plpgsql" SECURITY DEFINER
    AS $$
declare
  v_order public.orders%rowtype;
  v_cnpj text;
  v_state text;
  v_calc jsonb;
  v_limiar integer := 10;
  v_pagas_antes integer;
  v_total_pos integer;
  v_min integer;
begin
  select * into v_order from public.orders where id = new.order_id;
  v_cnpj := public.somente_digitos(v_order.cnpj);
  v_state := v_order.state;

  select coalesce(valor::integer, 10) into v_limiar
    from public.config where chave = 'limiar_fidelidade';

  select coalesce(p.min_quantity, 10) into v_min
    from public.products p where p.id = new.product_id;

  if new.quantity < v_min then
    raise exception 'QUANTIDADE_MINIMA_%', v_min;
  end if;

  -- Calcular divisão A/B
  v_calc := public.calcular_preco_pedido(v_order.cnpj, v_state, new.product_id, new.quantity);

  new.unit_price_cents := (v_calc->>'preco_unitario_exibido')::integer;
  new.total_price_cents := (v_calc->>'total_cents')::integer;
  new.customization := coalesce(new.customization, '{}'::jsonb)
    || jsonb_build_object(
      'units_a', v_calc->'units_a',
      'preco_a', v_calc->'preco_a_cents',
      'units_b', v_calc->'units_b',
      'preco_b', v_calc->'preco_b_cents'
    );

  -- Atualizar order com as unidades A/B e totais
  update public.orders set
    units_at_price_a = coalesce(units_at_price_a, 0) + (v_calc->>'units_a')::integer,
    units_at_price_b = coalesce(units_at_price_b, 0) + (v_calc->>'units_b')::integer,
    total_a_cents = coalesce(total_a_cents, 0)
      + (v_calc->>'units_a')::integer * (v_calc->>'preco_a_cents')::integer,
    total_b_cents = coalesce(total_b_cents, 0)
      + (v_calc->>'units_b')::integer * (v_calc->>'preco_b_cents')::integer,
    total_cents = coalesce(total_cents, 0) + (v_calc->>'total_cents')::integer,
    updated_at = now()
  where id = new.order_id;

  -- Baixar estoque estadual (atômico)
  if v_order.order_type = 'normal' then
    update public.product_state_stock set
      stock_quantity = stock_quantity - new.quantity,
      updated_at = now()
    where product_id = new.product_id
      and state = v_state
      and stock_quantity >= new.quantity;
    if not found then
      raise exception 'ESTOQUE_INSUFICIENTE_%', v_state;
    end if;
  elsif v_order.order_type = 'pre_order' then
    -- Pré-pedido: reserva sem baixar o estoque atual
    update public.product_state_stock set
      reserved_quantity = reserved_quantity + new.quantity,
      updated_at = now()
    where product_id = new.product_id and state = v_state;
  end if;

  -- Atualizar fidelidade por CNPJ/estado
  select coalesce(units_paid, 0) into v_pagas_antes
    from public.cnpj_state_loyalty
    where cnpj = v_cnpj and state = v_state;

  v_total_pos := v_pagas_antes + new.quantity;

  insert into public.cnpj_state_loyalty (cnpj, state, units_paid, status, fidelized_at)
  values (
    v_cnpj, v_state, new.quantity,
    case when new.quantity >= v_limiar then 'fidelizado' else 'primeira_compra' end,
    case when new.quantity >= v_limiar then now() else null end
  )
  on conflict (cnpj, state) do update set
    units_paid = public.cnpj_state_loyalty.units_paid + new.quantity,
    status = case
      when public.cnpj_state_loyalty.units_paid + new.quantity >= v_limiar
      then 'fidelizado'
      else public.cnpj_state_loyalty.status
    end,
    fidelized_at = case
      when public.cnpj_state_loyalty.status = 'primeira_compra'
        and public.cnpj_state_loyalty.units_paid + new.quantity >= v_limiar
      then now()
      else public.cnpj_state_loyalty.fidelized_at
    end,
    updated_at = now();

  -- Marca como pedido fundador se este pedido cruzou o limiar
  if v_pagas_antes < v_limiar and v_total_pos >= v_limiar then
    update public.orders set is_founding_order = true where id = new.order_id;
  end if;

  return new;
end $$;


ALTER FUNCTION "public"."processar_item_pedido"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."recalcular_pedido"("p_order" "uuid") RETURNS "void"
    LANGUAGE "plpgsql" SECURITY DEFINER
    AS $$
declare
  v_bruto integer := 0;
  v_com_volume integer := 0;
  v_fid numeric := 0;
  v_cnpj text;
begin
  select coalesce(sum(oi.quantity * p.base_price_cents), 0),
         coalesce(sum(oi.total_price_cents), 0)
    into v_bruto, v_com_volume
    from public.order_items oi
    join public.products p on p.id = oi.product_id
   where oi.order_id = p_order;

  select cnpj into v_cnpj from public.orders where id = p_order;
  v_fid := public.desconto_para_cnpj(v_cnpj);

  update public.orders set
    subtotal_cents = v_bruto,
    volume_discount_cents = v_bruto - v_com_volume,
    loyalty_discount_cents = round(v_com_volume * v_fid / 100.0),
    total_cents = v_com_volume - round(v_com_volume * v_fid / 100.0),
    updated_at = now()
  where id = p_order;
end $$;


ALTER FUNCTION "public"."recalcular_pedido"("p_order" "uuid") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."record_legal_acceptance"("p_doc_type" "text", "p_declared_data" "jsonb" DEFAULT '{}'::"jsonb") RETURNS "uuid"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'pg_catalog'
    AS $$
declare
  v_user      uuid := auth.uid();
  v_doc       public.legal_documents;
  v_id        uuid;
  v_ctx       text := 'provisional_account';   -- FIXO server-side
  v_declarado jsonb := coalesce(p_declared_data, '{}'::jsonb);
  v_chave     text;
  v_allow     text[] := array['ui_locale','form_version','screen','client_timezone'];
begin
  if v_user is null then
    raise exception 'Aceite exige usuario autenticado.';
  end if;

  -- Somente documentos da conta provisória.
  if p_doc_type not in ('privacy_notice','provisional_account_terms') then
    raise exception
      'Tipo de documento "%" nao pode ser aceito por esta RPC publica. Documentos empresariais serao registrados pelo backend do Marco 2, vinculados a uma partner_application real.',
      p_doc_type;
  end if;

  if jsonb_typeof(v_declarado) <> 'object' then
    raise exception 'p_declared_data deve ser um objeto JSON.';
  end if;
  if length(v_declarado::text) > 1024 then
    raise exception 'p_declared_data excede o limite de 1024 caracteres.';
  end if;
  for v_chave in select jsonb_object_keys(v_declarado) loop
    if not (v_chave = any(v_allow)) then
      raise exception
        'Chave "%" nao permitida em p_declared_data. Permitidas: %.', v_chave, array_to_string(v_allow, ', ');
    end if;
    if jsonb_typeof(v_declarado -> v_chave) not in ('string','number','boolean') then
      raise exception 'Valor de "%" deve ser escalar.', v_chave;
    end if;
  end loop;

  v_doc := public.current_legal_document(p_doc_type);
  if v_doc.id is null then
    raise exception 'Nao ha versao publicada e vigente para o documento "%".', p_doc_type;
  end if;

  insert into public.legal_acceptances
    (subject_type, subject_id, linked_auth_user_id, auth_user_id, legal_document_id,
     accepted_at, context, origin, evidence)
  values
    ('auth_user', v_user, v_user, v_user, v_doc.id,
     now(), v_ctx, 'rpc',
     jsonb_build_object(
       'server', jsonb_build_object(
         'recorded_at',  now(),
         'source',       'record_legal_acceptance',
         'doc_type',     v_doc.doc_type,
         'doc_version',  v_doc.version,
         'content_hash', v_doc.content_hash
       ),
       'client_declared', v_declarado
     ))
  -- Alvo EXPLÍCITO correspondente ao índice parcial de aceite ativo.
  on conflict (subject_type, subject_id, legal_document_id, context)
    where revoked_at is null
    do nothing
  returning id into v_id;

  if v_id is null then
    select a.id into v_id
      from public.legal_acceptances a
     where a.subject_type = 'auth_user'
       and a.subject_id = v_user
       and a.legal_document_id = v_doc.id
       and a.context = v_ctx
       and a.revoked_at is null
     limit 1;
  end if;

  return v_id;
end;
$$;


ALTER FUNCTION "public"."record_legal_acceptance"("p_doc_type" "text", "p_declared_data" "jsonb") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."registrar_cancelamento"("p_order_id" "uuid", "p_cancelado_por" "text", "p_motivo" "text" DEFAULT NULL::"text") RETURNS "jsonb"
    LANGUAGE "plpgsql" SECURITY DEFINER
    AS $$
declare
  v_order public.orders%rowtype;
  v_cnpj text;
  v_state text;
  v_limiar integer := 10;
  v_pagas_antes integer;
  v_loyalty_impact text := 'none';
  v_cascade_ids jsonb := '[]'::jsonb;
  v_refund integer := 0;
  v_is_founding boolean := false;
  v_pedidos_em_transito text[] := array['shipped', 'completed'];
begin
  select * into v_order from public.orders where id = p_order_id;

  if not found then
    raise exception 'PEDIDO_NAO_ENCONTRADO';
  end if;

  -- Impede cancelamento amigável se enviado/concluído
  if v_order.status = any(v_pedidos_em_transito) then
    raise exception 'CANCELAMENTO_NAO_PERMITIDO_STATUS_%', v_order.status;
  end if;

  v_cnpj := public.somente_digitos(v_order.cnpj);
  v_state := v_order.state;
  v_refund := v_order.total_cents;

  select coalesce(valor::integer, 10) into v_limiar
    from public.config where chave = 'limiar_fidelidade';

  select coalesce(units_paid, 0) into v_pagas_antes
    from public.cnpj_state_loyalty
    where cnpj = v_cnpj and state = v_state;

  -- Verifica se é o pedido fundador (o que cruzou o limiar)
  v_is_founding := v_order.is_founding_order;

  -- Cancela o pedido principal
  update public.orders set
    status = 'cancelled',
    updated_at = now()
  where id = p_order_id;

  -- Devolve o estoque ao pool estadual
  update public.product_state_stock pss set
    stock_quantity = pss.stock_quantity + oi.quantity,
    reserved_quantity = greatest(0, pss.reserved_quantity - oi.quantity)
  from public.order_items oi
  where oi.order_id = p_order_id
    and pss.product_id = oi.product_id
    and pss.state = v_state;

  -- Lógica de impacto na fidelidade
  if v_is_founding or (v_pagas_antes - coalesce(v_order.units_at_price_a, 0) - coalesce(v_order.units_at_price_b, 0)) < v_limiar then
    -- Pedido fundador ou CNPJ ficaria abaixo do limiar: zera fidelidade
    update public.cnpj_state_loyalty set
      units_paid = greatest(0, units_paid
        - coalesce(v_order.units_at_price_a, 0)
        - coalesce(v_order.units_at_price_b, 0)),
      status = 'primeira_compra',
      fidelized_at = null,
      updated_at = now()
    where cnpj = v_cnpj and state = v_state;
    v_loyalty_impact := 'reset';

    -- Cascata: cancela pedidos fidelizados ativos deste CNPJ/estado
    select jsonb_agg(o.id) into v_cascade_ids
      from public.orders o
      where o.cnpj = v_order.cnpj
        and o.state = v_state
        and o.id <> p_order_id
        and o.units_at_price_b > 0
        and o.status not in ('cancelled', 'shipped', 'completed');

    if v_cascade_ids is not null and jsonb_array_length(v_cascade_ids) > 0 then
      update public.orders set
        status = 'cancelled',
        notes = coalesce(notes, '') ||
          ' | Cancelado em cascata: pedido fundador cancelado.',
        updated_at = now()
      where id in (select (jsonb_array_elements_text(v_cascade_ids))::uuid)
        and status not in ('shipped', 'completed');
      v_loyalty_impact := 'cascade';
    end if;
  else
    -- CNPJ permanece fidelizado; apenas desconta as unidades
    update public.cnpj_state_loyalty set
      units_paid = units_paid
        - coalesce(v_order.units_at_price_a, 0)
        - coalesce(v_order.units_at_price_b, 0),
      updated_at = now()
    where cnpj = v_cnpj and state = v_state;
  end if;

  -- Registra o cancelamento no log
  insert into public.order_cancellations (
    order_id, cancelled_by, reason,
    order_status_at_cancellation, units_affected,
    refund_amount_cents, loyalty_impact,
    cascade_orders_cancelled, cnpj, state
  ) values (
    p_order_id, p_cancelado_por, p_motivo,
    v_order.status,
    coalesce(v_order.units_at_price_a, 0) + coalesce(v_order.units_at_price_b, 0),
    v_refund, v_loyalty_impact,
    v_cascade_ids, v_order.cnpj, v_state
  );

  return jsonb_build_object(
    'order_id', p_order_id,
    'loyalty_impact', v_loyalty_impact,
    'cascade_orders', v_cascade_ids,
    'refund_cents', v_refund,
    'message', case v_loyalty_impact
      when 'cascade' then
        'Ao cancelar este pedido, todos os pedidos ativos com Preço fidelizados por CNPJ serão cancelados até uma nova compra mínima com preço de não fidelizado.'
      when 'reset' then
        'Seu status de fidelidade foi redefinido. A próxima compra terá o preço de entrada.'
      else 'Pedido cancelado com sucesso.'
    end
  );
end $$;


ALTER FUNCTION "public"."registrar_cancelamento"("p_order_id" "uuid", "p_cancelado_por" "text", "p_motivo" "text") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."resolve_commercial_region"("p_uf" "text", "p_city" "text") RETURNS "jsonb"
    LANGUAGE "plpgsql" STABLE SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
declare
  v_uf   text := upper(btrim(coalesce(p_uf, '')));
  -- Normalização canônica com caixa correta (lower antes de remover acentos).
  v_key  text := public.commercial_city_key(p_city);
  v_row  record;
begin
  -- UF precisa ser uma das 27 canônicas (rejeita XX, ZZ, E, ESP, vazio, null).
  if not public.commercial_is_valid_uf(p_uf) then
    return jsonb_build_object('region_available', false, 'reason', 'invalid_uf');
  end if;
  if length(v_key) = 0 then
    return jsonb_build_object('region_available', false, 'reason', 'empty_city');
  end if;

  select r.id as region_id, r.name as region_name, r.slug as region_slug,
         c.uf, c.city_name, r.is_active
    into v_row
    from public.commercial_region_cities c
    join public.commercial_regions r on r.id = c.region_id
    where c.uf = v_uf
      and c.city_key = v_key
      and c.is_active
      and r.is_active
    limit 1;

  if v_row.region_id is null then
    return jsonb_build_object('region_available', false, 'uf', v_uf);
  end if;

  return jsonb_build_object(
    'region_available', true,
    'region_id',   v_row.region_id,
    'region_name', v_row.region_name,
    'region_slug', v_row.region_slug,
    'uf',          v_row.uf,
    'city_name',   v_row.city_name,
    'is_active',   v_row.is_active
  );
end;
$$;


ALTER FUNCTION "public"."resolve_commercial_region"("p_uf" "text", "p_city" "text") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."rls_auto_enable"() RETURNS "event_trigger"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'pg_catalog'
    AS $$
DECLARE
  cmd record;
BEGIN
  FOR cmd IN
    SELECT *
    FROM pg_event_trigger_ddl_commands()
    WHERE command_tag IN ('CREATE TABLE', 'CREATE TABLE AS', 'SELECT INTO')
      AND object_type IN ('table','partitioned table')
  LOOP
     IF cmd.schema_name IS NOT NULL AND cmd.schema_name IN ('public') AND cmd.schema_name NOT IN ('pg_catalog','information_schema') AND cmd.schema_name NOT LIKE 'pg_toast%' AND cmd.schema_name NOT LIKE 'pg_temp%' THEN
      BEGIN
        EXECUTE format('alter table if exists %s enable row level security', cmd.object_identity);
        RAISE LOG 'rls_auto_enable: enabled RLS on %', cmd.object_identity;
      EXCEPTION
        WHEN OTHERS THEN
          RAISE LOG 'rls_auto_enable: failed to enable RLS on %', cmd.object_identity;
      END;
     ELSE
        RAISE LOG 'rls_auto_enable: skip % (either system schema or not in enforced list: %.)', cmd.object_identity, cmd.schema_name;
     END IF;
  END LOOP;
END;
$$;


ALTER FUNCTION "public"."rls_auto_enable"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."somente_digitos"("t" "text") RETURNS "text"
    LANGUAGE "sql" IMMUTABLE
    AS $$ select regexp_replace(coalesce(t, ''), '\D', '', 'g') $$;


ALTER FUNCTION "public"."somente_digitos"("t" "text") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."status_fidelidade"("p_cnpj" "text", "p_state" "text") RETURNS "text"
    LANGUAGE "sql" STABLE SECURITY DEFINER
    AS $$
  select coalesce(
    (select status from public.cnpj_state_loyalty
     where cnpj = public.somente_digitos(p_cnpj) and state = upper(p_state)),
    'primeira_compra'
  );
$$;


ALTER FUNCTION "public"."status_fidelidade"("p_cnpj" "text", "p_state" "text") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."trg_recalcular_pedido"() RETURNS "trigger"
    LANGUAGE "plpgsql" SECURITY DEFINER
    AS $$
begin
  perform public.recalcular_pedido(coalesce(new.order_id, old.order_id));
  return coalesce(new, old);
end $$;


ALTER FUNCTION "public"."trg_recalcular_pedido"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."unidades_pagas_cnpj"("p_cnpj" "text", "p_state" "text") RETURNS integer
    LANGUAGE "sql" STABLE SECURITY DEFINER
    AS $$
  select coalesce(units_paid, 0)
  from public.cnpj_state_loyalty
  where cnpj = public.somente_digitos(p_cnpj)
    and state = upper(p_state);
$$;


ALTER FUNCTION "public"."unidades_pagas_cnpj"("p_cnpj" "text", "p_state" "text") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."verificar_cascata"("p_order_id" "uuid") RETURNS "jsonb"
    LANGUAGE "plpgsql" STABLE SECURITY DEFINER
    AS $$
declare
  v_order public.orders%rowtype;
  v_cascade_count integer := 0;
begin
  select * into v_order from public.orders where id = p_order_id;
  if not found then return jsonb_build_object('cascade', false); end if;

  if v_order.is_founding_order then
    select count(*) into v_cascade_count
      from public.orders o
      where o.cnpj = v_order.cnpj
        and o.state = v_order.state
        and o.id <> p_order_id
        and o.units_at_price_b > 0
        and o.status not in ('cancelled', 'shipped', 'completed');
  end if;

  return jsonb_build_object(
    'cascade', v_cascade_count > 0,
    'affected_orders', v_cascade_count,
    'is_founding_order', v_order.is_founding_order,
    'message', case when v_cascade_count > 0
      then 'Ao cancelar este pedido, todos os pedidos ativos com Preço fidelizados por CNPJ serão cancelados até uma nova compra mínima com preço de não fidelizado.'
      else null
    end
  );
end $$;


ALTER FUNCTION "public"."verificar_cascata"("p_order_id" "uuid") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."write_audit_log"("p_action" "text", "p_entity_type" "text", "p_entity_id" "text" DEFAULT NULL::"text", "p_actor_user_id" "uuid" DEFAULT NULL::"uuid", "p_actor_role" "text" DEFAULT NULL::"text", "p_previous_state" "jsonb" DEFAULT NULL::"jsonb", "p_new_state" "jsonb" DEFAULT NULL::"jsonb", "p_justification" "text" DEFAULT NULL::"text", "p_correlation_id" "uuid" DEFAULT NULL::"uuid", "p_source" "text" DEFAULT 'backend'::"text", "p_metadata" "jsonb" DEFAULT '{}'::"jsonb", "p_corrects_log_id" "uuid" DEFAULT NULL::"uuid") RETURNS "uuid"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'pg_catalog'
    AS $$
declare
  v_id uuid;
begin
  insert into public.audit_logs
    (action, entity_type, entity_id, actor_user_id, actor_role,
     previous_state, new_state, justification, correlation_id, source,
     metadata, corrects_log_id)
  values
    (p_action, p_entity_type, p_entity_id,
     coalesce(p_actor_user_id, auth.uid()), p_actor_role,
     p_previous_state, p_new_state, p_justification, p_correlation_id, p_source,
     coalesce(p_metadata, '{}'::jsonb), p_corrects_log_id)
  returning id into v_id;
  return v_id;
end;
$$;


ALTER FUNCTION "public"."write_audit_log"("p_action" "text", "p_entity_type" "text", "p_entity_id" "text", "p_actor_user_id" "uuid", "p_actor_role" "text", "p_previous_state" "jsonb", "p_new_state" "jsonb", "p_justification" "text", "p_correlation_id" "uuid", "p_source" "text", "p_metadata" "jsonb", "p_corrects_log_id" "uuid") OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."audit_logs" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "occurred_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "actor_user_id" "uuid",
    "actor_role" "text",
    "action" "text" NOT NULL,
    "entity_type" "text" NOT NULL,
    "entity_id" "text",
    "previous_state" "jsonb",
    "new_state" "jsonb",
    "justification" "text",
    "correlation_id" "uuid",
    "source" "text",
    "metadata" "jsonb" DEFAULT '{}'::"jsonb" NOT NULL,
    "corrects_log_id" "uuid",
    CONSTRAINT "audit_logs_action_nonempty" CHECK (("length"("btrim"("action")) > 0)),
    CONSTRAINT "audit_logs_entity_type_nonempty" CHECK (("length"("btrim"("entity_type")) > 0)),
    CONSTRAINT "audit_logs_metadata_objeto" CHECK (("jsonb_typeof"("metadata") = 'object'::"text")),
    CONSTRAINT "audit_logs_nao_corrige_a_si" CHECK ((("corrects_log_id" IS NULL) OR ("corrects_log_id" <> "id")))
);


ALTER TABLE "public"."audit_logs" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."cnpj_state_loyalty" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "cnpj" "text" NOT NULL,
    "state" "text" NOT NULL,
    "units_paid" integer DEFAULT 0 NOT NULL,
    "status" "text" DEFAULT 'primeira_compra'::"text" NOT NULL,
    "fidelized_at" timestamp with time zone,
    "created_at" timestamp with time zone DEFAULT "now"(),
    "updated_at" timestamp with time zone DEFAULT "now"()
);


ALTER TABLE "public"."cnpj_state_loyalty" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."commercial_exclusivities" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "region_id" "uuid" NOT NULL,
    "sequence_number" integer NOT NULL,
    "status" "text" NOT NULL,
    "is_current" boolean DEFAULT false NOT NULL,
    "planned_start_at" timestamp with time zone,
    "formed_at" timestamp with time zone,
    "operation_authorized_at" timestamp with time zone,
    "operation_started_at" timestamp with time zone,
    "operation_completed_at" timestamp with time zone,
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "updated_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    CONSTRAINT "commercial_exclusivities_seq_positive" CHECK (("sequence_number" > 0)),
    CONSTRAINT "commercial_exclusivities_status_allowed" CHECK (("status" = ANY (ARRAY['forming'::"text", 'formed'::"text", 'start_scheduled'::"text", 'operation_authorized'::"text", 'operation_started'::"text", 'operation_completed'::"text", 'operation_paused'::"text"])))
);


ALTER TABLE "public"."commercial_exclusivities" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."commercial_niches" (
    "code" "text" NOT NULL,
    "display_name" "text" NOT NULL,
    "contracted_quantity" integer NOT NULL,
    "sort_order" integer NOT NULL,
    "is_active" boolean DEFAULT true NOT NULL,
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "updated_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    CONSTRAINT "commercial_niches_canonical" CHECK (((((((("code" = 'supermarket'::"text") AND ("contracted_quantity" = 24) AND ("sort_order" = 1)) OR (("code" = 'pharmacy'::"text") AND ("contracted_quantity" = 12) AND ("sort_order" = 2))) OR (("code" = 'womens_clothing'::"text") AND ("contracted_quantity" = 12) AND ("sort_order" = 3))) OR (("code" = 'mens_clothing'::"text") AND ("contracted_quantity" = 12) AND ("sort_order" = 4))) OR (("code" = 'womens_footwear'::"text") AND ("contracted_quantity" = 12) AND ("sort_order" = 5))) OR (("code" = 'mens_footwear'::"text") AND ("contracted_quantity" = 12) AND ("sort_order" = 6)))),
    CONSTRAINT "commercial_niches_code_allowed" CHECK (("code" = ANY (ARRAY['supermarket'::"text", 'pharmacy'::"text", 'womens_clothing'::"text", 'mens_clothing'::"text", 'womens_footwear'::"text", 'mens_footwear'::"text"]))),
    CONSTRAINT "commercial_niches_name_not_empty" CHECK (("length"("btrim"("display_name")) > 0)),
    CONSTRAINT "commercial_niches_order_positive" CHECK (("sort_order" > 0)),
    CONSTRAINT "commercial_niches_qty_positive" CHECK (("contracted_quantity" > 0)),
    CONSTRAINT "commercial_niches_sort_order_range" CHECK ((("sort_order" >= 1) AND ("sort_order" <= 6)))
);


ALTER TABLE "public"."commercial_niches" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."commercial_opportunities" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "exclusivity_id" "uuid" NOT NULL,
    "niche_code" "text" NOT NULL,
    "contracted_quantity" integer NOT NULL,
    "status" "text" DEFAULT 'available'::"text" NOT NULL,
    "reserved_until" timestamp with time zone,
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "updated_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    CONSTRAINT "commercial_opportunities_qty_positive" CHECK (("contracted_quantity" > 0)),
    CONSTRAINT "commercial_opportunities_status_allowed" CHECK (("status" = ANY (ARRAY['available'::"text", 'reserved'::"text", 'payment_pending'::"text", 'contracted'::"text"])))
);


ALTER TABLE "public"."commercial_opportunities" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."commercial_region_cities" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "region_id" "uuid" NOT NULL,
    "uf" "text" NOT NULL,
    "city_name" "text" NOT NULL,
    "city_key" "text" NOT NULL,
    "is_active" boolean DEFAULT true NOT NULL,
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "updated_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    CONSTRAINT "commercial_region_cities_city_not_empty" CHECK (("length"("btrim"("city_name")) > 0)),
    CONSTRAINT "commercial_region_cities_uf_valid" CHECK (("uf" = ANY (ARRAY['AC'::"text", 'AL'::"text", 'AP'::"text", 'AM'::"text", 'BA'::"text", 'CE'::"text", 'DF'::"text", 'ES'::"text", 'GO'::"text", 'MA'::"text", 'MT'::"text", 'MS'::"text", 'MG'::"text", 'PA'::"text", 'PB'::"text", 'PR'::"text", 'PE'::"text", 'PI'::"text", 'RJ'::"text", 'RN'::"text", 'RS'::"text", 'RO'::"text", 'RR'::"text", 'SC'::"text", 'SP'::"text", 'SE'::"text", 'TO'::"text"])))
);


ALTER TABLE "public"."commercial_region_cities" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."commercial_regions" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "uf" "text" NOT NULL,
    "name" "text" NOT NULL,
    "slug" "text" NOT NULL,
    "is_active" boolean DEFAULT false NOT NULL,
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "updated_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    CONSTRAINT "commercial_regions_name_not_empty" CHECK (("length"("btrim"("name")) > 0)),
    CONSTRAINT "commercial_regions_uf_valid" CHECK (("uf" = ANY (ARRAY['AC'::"text", 'AL'::"text", 'AP'::"text", 'AM'::"text", 'BA'::"text", 'CE'::"text", 'DF'::"text", 'ES'::"text", 'GO'::"text", 'MA'::"text", 'MT'::"text", 'MS'::"text", 'MG'::"text", 'PA'::"text", 'PB'::"text", 'PR'::"text", 'PE'::"text", 'PI'::"text", 'RJ'::"text", 'RN'::"text", 'RS'::"text", 'RO'::"text", 'RR'::"text", 'SC'::"text", 'SP'::"text", 'SE'::"text", 'TO'::"text"])))
);


ALTER TABLE "public"."commercial_regions" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."config" (
    "chave" "text" NOT NULL,
    "valor" numeric NOT NULL
);


ALTER TABLE "public"."config" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."faixas_quantidade" (
    "min_qtd" integer NOT NULL,
    "desconto_pct" numeric NOT NULL,
    CONSTRAINT "faixas_quantidade_desconto_pct_check" CHECK ((("desconto_pct" >= (0)::numeric) AND ("desconto_pct" < (100)::numeric))),
    CONSTRAINT "faixas_quantidade_min_qtd_check" CHECK (("min_qtd" > 0))
);


ALTER TABLE "public"."faixas_quantidade" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."invoices" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "order_id" "uuid",
    "provider" "text" DEFAULT 'bling'::"text",
    "provider_invoice_id" "text",
    "status" "text" DEFAULT 'not_started'::"text",
    "invoice_url" "text",
    "issued_at" timestamp with time zone,
    "raw_response" "jsonb",
    "created_at" timestamp with time zone DEFAULT "now"()
);


ALTER TABLE "public"."invoices" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."legal_acceptances" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "subject_type" "text" NOT NULL,
    "subject_id" "uuid" NOT NULL,
    "linked_auth_user_id" "uuid",
    "auth_user_id" "uuid",
    "partner_application_id" "uuid",
    "legal_document_id" "uuid" NOT NULL,
    "accepted_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "context" "text" NOT NULL,
    "origin" "text" DEFAULT 'server'::"text" NOT NULL,
    "ip" "inet",
    "user_agent" "text",
    "evidence" "jsonb" DEFAULT '{}'::"jsonb" NOT NULL,
    "revoked_at" timestamp with time zone,
    "revocation_reason" "text",
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    CONSTRAINT "legal_acceptances_context_allowed" CHECK (("context" = ANY (ARRAY['partner_application'::"text", 'provisional_account'::"text", 'owner_authority'::"text", 'manager_invite'::"text", 'commercial_contract'::"text"]))),
    CONSTRAINT "legal_acceptances_evidence_limite" CHECK (("length"(("evidence")::"text") <= 8192)),
    CONSTRAINT "legal_acceptances_evidence_objeto" CHECK (("jsonb_typeof"("evidence") = 'object'::"text")),
    CONSTRAINT "legal_acceptances_link_coerente" CHECK ((("auth_user_id" IS NULL) OR (("linked_auth_user_id" IS NOT NULL) AND ("auth_user_id" = "linked_auth_user_id")))),
    CONSTRAINT "legal_acceptances_revocacao_coerente" CHECK (((("revoked_at" IS NULL) AND ("revocation_reason" IS NULL)) OR (("revoked_at" IS NOT NULL) AND ("revocation_reason" IS NOT NULL) AND ("length"("btrim"("revocation_reason")) > 0)))),
    CONSTRAINT "legal_acceptances_subject_allowed" CHECK (("subject_type" = ANY (ARRAY['auth_user'::"text", 'partner_application'::"text"]))),
    CONSTRAINT "legal_acceptances_subject_coerente" CHECK (((("subject_type" = 'auth_user'::"text") AND ("partner_application_id" IS NULL) AND ("linked_auth_user_id" IS NOT NULL) AND ("linked_auth_user_id" = "subject_id")) OR (("subject_type" = 'partner_application'::"text") AND ("partner_application_id" IS NOT NULL) AND ("partner_application_id" = "subject_id"))))
);


ALTER TABLE "public"."legal_acceptances" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."notification_events" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "channel" "text" NOT NULL,
    "recipient_user_id" "uuid",
    "recipient_address" "text",
    "template_key" "text" NOT NULL,
    "template_data" "jsonb" DEFAULT '{}'::"jsonb" NOT NULL,
    "status" "text" DEFAULT 'pending'::"text" NOT NULL,
    "attempt_count" integer DEFAULT 0 NOT NULL,
    "scheduled_for" timestamp with time zone,
    "sent_at" timestamp with time zone,
    "delivered_at" timestamp with time zone,
    "read_at" timestamp with time zone,
    "first_failed_at" timestamp with time zone,
    "last_failed_at" timestamp with time zone,
    "error_code" "text",
    "error_message" "text",
    "provider" "text",
    "provider_message_id" "text",
    "idempotency_key" "text" NOT NULL,
    "retry_of_event_id" "uuid",
    "correlation_entity_type" "text",
    "correlation_entity_id" "text",
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "updated_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    CONSTRAINT "notification_events_attempt_nao_neg" CHECK (("attempt_count" >= 0)),
    CONSTRAINT "notification_events_channel_allowed" CHECK (("channel" = ANY (ARRAY['email'::"text", 'whatsapp'::"text", 'in_app'::"text"]))),
    CONSTRAINT "notification_events_data_limite" CHECK (("length"(("template_data")::"text") <= 8192)),
    CONSTRAINT "notification_events_data_objeto" CHECK (("jsonb_typeof"("template_data") = 'object'::"text")),
    CONSTRAINT "notification_events_delivered_estado" CHECK ((("delivered_at" IS NULL) OR ("status" = ANY (ARRAY['delivered'::"text", 'read'::"text"])))),
    CONSTRAINT "notification_events_destinatario" CHECK (((("channel" = 'in_app'::"text") AND ("recipient_user_id" IS NOT NULL) AND ("recipient_address" IS NULL)) OR (("channel" = ANY (ARRAY['email'::"text", 'whatsapp'::"text"])) AND (("recipient_user_id" IS NOT NULL) OR ("recipient_address" IS NOT NULL))))),
    CONSTRAINT "notification_events_endereco_no_envio" CHECK ((("channel" = 'in_app'::"text") OR ("status" = ANY (ARRAY['pending'::"text", 'scheduled'::"text", 'cancelled'::"text"])) OR ("recipient_address" IS NOT NULL))),
    CONSTRAINT "notification_events_erro_tamanho" CHECK (((("error_code" IS NULL) OR ("length"("error_code") <= 100)) AND (("error_message" IS NULL) OR ("length"("error_message") <= 2000)))),
    CONSTRAINT "notification_events_falha_par" CHECK ((("first_failed_at" IS NULL) = ("last_failed_at" IS NULL))),
    CONSTRAINT "notification_events_idem_nonempty" CHECK (("length"("btrim"("idempotency_key")) > 0)),
    CONSTRAINT "notification_events_provider_estado" CHECK (((("provider_message_id" IS NULL) AND ("provider" IS NULL)) OR ("status" <> ALL (ARRAY['pending'::"text", 'scheduled'::"text"])))),
    CONSTRAINT "notification_events_read_estado" CHECK ((("read_at" IS NULL) OR ("status" = 'read'::"text"))),
    CONSTRAINT "notification_events_retry_nao_self" CHECK ((("retry_of_event_id" IS NULL) OR ("retry_of_event_id" <> "id"))),
    CONSTRAINT "notification_events_sent_estado" CHECK ((("sent_at" IS NULL) OR ("status" <> ALL (ARRAY['pending'::"text", 'scheduled'::"text", 'sending'::"text"])))),
    CONSTRAINT "notification_events_st_delivered" CHECK ((("status" <> 'delivered'::"text") OR (("sent_at" IS NOT NULL) AND ("delivered_at" IS NOT NULL)))),
    CONSTRAINT "notification_events_st_failed" CHECK ((("status" <> 'failed'::"text") OR (("first_failed_at" IS NOT NULL) AND ("last_failed_at" IS NOT NULL)))),
    CONSTRAINT "notification_events_st_read" CHECK ((("status" <> 'read'::"text") OR (("sent_at" IS NOT NULL) AND ("delivered_at" IS NOT NULL) AND ("read_at" IS NOT NULL)))),
    CONSTRAINT "notification_events_st_scheduled" CHECK ((("status" <> 'scheduled'::"text") OR ("scheduled_for" IS NOT NULL))),
    CONSTRAINT "notification_events_st_sent" CHECK ((("status" <> 'sent'::"text") OR ("sent_at" IS NOT NULL))),
    CONSTRAINT "notification_events_status_allowed" CHECK (("status" = ANY (ARRAY['pending'::"text", 'scheduled'::"text", 'sending'::"text", 'sent'::"text", 'delivered'::"text", 'read'::"text", 'failed'::"text", 'cancelled'::"text"]))),
    CONSTRAINT "notification_events_template_nonempty" CHECK (("length"("btrim"("template_key")) > 0)),
    CONSTRAINT "notification_events_ts_delivered" CHECK ((("delivered_at" IS NULL) OR (("sent_at" IS NOT NULL) AND ("delivered_at" >= "sent_at")))),
    CONSTRAINT "notification_events_ts_first_failed" CHECK ((("first_failed_at" IS NULL) OR ("first_failed_at" >= "created_at"))),
    CONSTRAINT "notification_events_ts_last_failed" CHECK ((("last_failed_at" IS NULL) OR (("first_failed_at" IS NOT NULL) AND ("last_failed_at" >= "first_failed_at")))),
    CONSTRAINT "notification_events_ts_read" CHECK ((("read_at" IS NULL) OR (("delivered_at" IS NOT NULL) AND ("read_at" >= "delivered_at")))),
    CONSTRAINT "notification_events_ts_sent" CHECK ((("sent_at" IS NULL) OR ("sent_at" >= "created_at")))
);


ALTER TABLE "public"."notification_events" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."order_cancellations" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "order_id" "uuid" NOT NULL,
    "cancelled_by" "text" NOT NULL,
    "reason" "text",
    "order_status_at_cancellation" "text",
    "units_affected" integer,
    "refund_amount_cents" integer,
    "loyalty_impact" "text",
    "cascade_orders_cancelled" "jsonb",
    "cnpj" "text",
    "state" "text",
    "notes" "text",
    "created_at" timestamp with time zone DEFAULT "now"()
);


ALTER TABLE "public"."order_cancellations" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."order_customization_files" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "order_id" "uuid",
    "order_item_id" "uuid",
    "file_url" "text" NOT NULL,
    "file_type" "text",
    "original_filename" "text",
    "status" "text" DEFAULT 'uploaded'::"text",
    "created_at" timestamp with time zone DEFAULT "now"()
);


ALTER TABLE "public"."order_customization_files" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."order_items" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "order_id" "uuid",
    "product_id" "uuid",
    "quantity" integer NOT NULL,
    "unit_price_cents" integer,
    "total_price_cents" integer,
    "customization" "jsonb",
    "created_at" timestamp with time zone DEFAULT "now"()
);


ALTER TABLE "public"."order_items" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."orders" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "site_profile_id" "uuid",
    "status" "text" DEFAULT 'draft'::"text" NOT NULL,
    "customer_name" "text",
    "customer_email" "text",
    "customer_phone" "text",
    "cnpj" "text",
    "subtotal_cents" integer DEFAULT 0,
    "volume_discount_cents" integer DEFAULT 0,
    "loyalty_discount_cents" integer DEFAULT 0,
    "total_cents" integer DEFAULT 0,
    "payment_status" "text" DEFAULT 'not_started'::"text",
    "invoice_status" "text" DEFAULT 'not_started'::"text",
    "notes" "text",
    "created_at" timestamp with time zone DEFAULT "now"(),
    "updated_at" timestamp with time zone DEFAULT "now"(),
    "state" "text",
    "order_type" "text" DEFAULT 'normal'::"text" NOT NULL,
    "is_founding_order" boolean DEFAULT false NOT NULL,
    "units_at_price_a" integer DEFAULT 0,
    "units_at_price_b" integer DEFAULT 0,
    "total_a_cents" integer DEFAULT 0,
    "total_b_cents" integer DEFAULT 0
);


ALTER TABLE "public"."orders" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."payments" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "order_id" "uuid",
    "provider" "text" DEFAULT 'mercado_pago'::"text",
    "provider_payment_id" "text",
    "status" "text" DEFAULT 'not_started'::"text",
    "amount_cents" integer,
    "paid_at" timestamp with time zone,
    "raw_webhook" "jsonb",
    "created_at" timestamp with time zone DEFAULT "now"()
);


ALTER TABLE "public"."payments" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."product_assets" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "product_id" "uuid",
    "asset_type" "text" NOT NULL,
    "title" "text",
    "url" "text" NOT NULL,
    "alt_text" "text",
    "display_order" integer DEFAULT 100,
    "active" boolean DEFAULT true,
    "created_at" timestamp with time zone DEFAULT "now"()
);


ALTER TABLE "public"."product_assets" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."product_customization_fields" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "product_id" "uuid",
    "field_key" "text" NOT NULL,
    "label" "text" NOT NULL,
    "field_type" "text" NOT NULL,
    "required" boolean DEFAULT false,
    "max_length" integer,
    "help_text" "text",
    "options" "jsonb",
    "display_order" integer DEFAULT 100,
    "active" boolean DEFAULT true,
    "created_at" timestamp with time zone DEFAULT "now"()
);


ALTER TABLE "public"."product_customization_fields" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."product_state_stock" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "product_id" "uuid" NOT NULL,
    "state" "text" NOT NULL,
    "stock_quantity" integer DEFAULT 0 NOT NULL,
    "reserved_quantity" integer DEFAULT 0 NOT NULL,
    "restock_date" "date",
    "preco_a_cents" integer NOT NULL,
    "preco_b_cents" integer NOT NULL,
    "active" boolean DEFAULT true NOT NULL,
    "created_at" timestamp with time zone DEFAULT "now"(),
    "updated_at" timestamp with time zone DEFAULT "now"(),
    CONSTRAINT "product_state_stock_reserved_quantity_check" CHECK (("reserved_quantity" >= 0)),
    CONSTRAINT "product_state_stock_stock_quantity_check" CHECK (("stock_quantity" >= 0))
);


ALTER TABLE "public"."product_state_stock" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."products" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "slug" "text" NOT NULL,
    "name" "text" NOT NULL,
    "short_description" "text",
    "full_description" "text",
    "product_type" "text",
    "category" "text",
    "active" boolean DEFAULT true,
    "base_price_cents" integer,
    "min_quantity" integer DEFAULT 10,
    "stock_quantity" integer,
    "stock_enabled" boolean DEFAULT true,
    "customizable" boolean DEFAULT true,
    "display_order" integer DEFAULT 100,
    "created_at" timestamp with time zone DEFAULT "now"(),
    "updated_at" timestamp with time zone DEFAULT "now"()
);


ALTER TABLE "public"."products" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."site_admins" (
    "user_id" "uuid" NOT NULL,
    "created_at" timestamp with time zone DEFAULT "now"()
);


ALTER TABLE "public"."site_admins" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."site_contact_messages" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "name" "text",
    "email" "text",
    "phone" "text",
    "company" "text",
    "message" "text",
    "status" "text" DEFAULT 'new'::"text",
    "created_at" timestamp with time zone DEFAULT "now"()
);


ALTER TABLE "public"."site_contact_messages" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."site_documents" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "slug" "text" NOT NULL,
    "title" "text" NOT NULL,
    "document_type" "text" NOT NULL,
    "content" "text",
    "file_url" "text",
    "active" boolean DEFAULT true,
    "created_at" timestamp with time zone DEFAULT "now"(),
    "updated_at" timestamp with time zone DEFAULT "now"()
);


ALTER TABLE "public"."site_documents" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."site_monthly_partners" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "app_partner_id" "uuid",
    "trade_name" "text" NOT NULL,
    "legal_name" "text",
    "cnpj" "text",
    "category" "text",
    "city" "text",
    "state" "text",
    "logo_url" "text",
    "website_url" "text",
    "contact_name" "text",
    "contact_email" "text",
    "contact_phone" "text",
    "status" "text" DEFAULT 'lead'::"text",
    "created_at" timestamp with time zone DEFAULT "now"(),
    "updated_at" timestamp with time zone DEFAULT "now"()
);


ALTER TABLE "public"."site_monthly_partners" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."site_partner_ads" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "site_partner_id" "uuid",
    "contract_id" "uuid",
    "placement" "text" NOT NULL,
    "title" "text",
    "description" "text",
    "image_url" "text",
    "target_url" "text",
    "starts_at" timestamp with time zone,
    "ends_at" timestamp with time zone,
    "active" boolean DEFAULT true,
    "created_at" timestamp with time zone DEFAULT "now"()
);


ALTER TABLE "public"."site_partner_ads" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."site_partner_contracts" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "site_partner_id" "uuid",
    "plan_name" "text",
    "monthly_amount_cents" integer,
    "starts_at" "date",
    "ends_at" "date",
    "billing_day" integer,
    "status" "text" DEFAULT 'pending'::"text",
    "notes" "text",
    "created_at" timestamp with time zone DEFAULT "now"(),
    "updated_at" timestamp with time zone DEFAULT "now"()
);


ALTER TABLE "public"."site_partner_contracts" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."site_profiles" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "auth_user_id" "uuid",
    "customer_type" "text",
    "name" "text",
    "company_name" "text",
    "cnpj" "text",
    "email" "text",
    "phone" "text",
    "created_at" timestamp with time zone DEFAULT "now"(),
    "updated_at" timestamp with time zone DEFAULT "now"()
);


ALTER TABLE "public"."site_profiles" OWNER TO "postgres";


ALTER TABLE ONLY "public"."audit_logs"
    ADD CONSTRAINT "audit_logs_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."cnpj_state_loyalty"
    ADD CONSTRAINT "cnpj_state_loyalty_cnpj_state_key" UNIQUE ("cnpj", "state");



ALTER TABLE ONLY "public"."cnpj_state_loyalty"
    ADD CONSTRAINT "cnpj_state_loyalty_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."commercial_exclusivities"
    ADD CONSTRAINT "commercial_exclusivities_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."commercial_exclusivities"
    ADD CONSTRAINT "commercial_exclusivities_seq_unique_per_region" UNIQUE ("region_id", "sequence_number");



ALTER TABLE ONLY "public"."commercial_niches"
    ADD CONSTRAINT "commercial_niches_pkey" PRIMARY KEY ("code");



ALTER TABLE ONLY "public"."commercial_niches"
    ADD CONSTRAINT "commercial_niches_sort_order_unique" UNIQUE ("sort_order");



ALTER TABLE ONLY "public"."commercial_opportunities"
    ADD CONSTRAINT "commercial_opportunities_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."commercial_opportunities"
    ADD CONSTRAINT "commercial_opportunities_unique_niche_per_exclusivity" UNIQUE ("exclusivity_id", "niche_code");



ALTER TABLE ONLY "public"."commercial_region_cities"
    ADD CONSTRAINT "commercial_region_cities_city_unique_per_uf" UNIQUE ("uf", "city_name");



ALTER TABLE ONLY "public"."commercial_region_cities"
    ADD CONSTRAINT "commercial_region_cities_key_unique_per_uf" UNIQUE ("uf", "city_key");



ALTER TABLE ONLY "public"."commercial_region_cities"
    ADD CONSTRAINT "commercial_region_cities_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."commercial_regions"
    ADD CONSTRAINT "commercial_regions_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."commercial_regions"
    ADD CONSTRAINT "commercial_regions_slug_unique_per_uf" UNIQUE ("uf", "slug");



ALTER TABLE ONLY "public"."config"
    ADD CONSTRAINT "config_pkey" PRIMARY KEY ("chave");



ALTER TABLE ONLY "public"."faixas_quantidade"
    ADD CONSTRAINT "faixas_quantidade_pkey" PRIMARY KEY ("min_qtd");



ALTER TABLE ONLY "public"."invoices"
    ADD CONSTRAINT "invoices_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."legal_acceptances"
    ADD CONSTRAINT "legal_acceptances_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."legal_documents"
    ADD CONSTRAINT "legal_documents_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."legal_documents"
    ADD CONSTRAINT "legal_documents_type_version_unique" UNIQUE ("doc_type", "version");



ALTER TABLE ONLY "public"."notification_events"
    ADD CONSTRAINT "notification_events_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."order_cancellations"
    ADD CONSTRAINT "order_cancellations_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."order_customization_files"
    ADD CONSTRAINT "order_customization_files_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."order_items"
    ADD CONSTRAINT "order_items_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."orders"
    ADD CONSTRAINT "orders_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."payments"
    ADD CONSTRAINT "payments_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."product_assets"
    ADD CONSTRAINT "product_assets_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."product_customization_fields"
    ADD CONSTRAINT "product_customization_fields_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."product_customization_fields"
    ADD CONSTRAINT "product_customization_fields_product_id_field_key_key" UNIQUE ("product_id", "field_key");



ALTER TABLE ONLY "public"."product_state_stock"
    ADD CONSTRAINT "product_state_stock_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."product_state_stock"
    ADD CONSTRAINT "product_state_stock_product_id_state_key" UNIQUE ("product_id", "state");



ALTER TABLE ONLY "public"."products"
    ADD CONSTRAINT "products_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."products"
    ADD CONSTRAINT "products_slug_key" UNIQUE ("slug");



ALTER TABLE ONLY "public"."site_admins"
    ADD CONSTRAINT "site_admins_pkey" PRIMARY KEY ("user_id");



ALTER TABLE ONLY "public"."site_contact_messages"
    ADD CONSTRAINT "site_contact_messages_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."site_documents"
    ADD CONSTRAINT "site_documents_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."site_documents"
    ADD CONSTRAINT "site_documents_slug_key" UNIQUE ("slug");



ALTER TABLE ONLY "public"."site_monthly_partners"
    ADD CONSTRAINT "site_monthly_partners_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."site_partner_ads"
    ADD CONSTRAINT "site_partner_ads_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."site_partner_contracts"
    ADD CONSTRAINT "site_partner_contracts_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."site_profiles"
    ADD CONSTRAINT "site_profiles_pkey" PRIMARY KEY ("id");



CREATE INDEX "idx_audit_logs_actor" ON "public"."audit_logs" USING "btree" ("actor_user_id");



CREATE INDEX "idx_audit_logs_correlation" ON "public"."audit_logs" USING "btree" ("correlation_id");



CREATE INDEX "idx_audit_logs_entity" ON "public"."audit_logs" USING "btree" ("entity_type", "entity_id");



CREATE INDEX "idx_audit_logs_occurred" ON "public"."audit_logs" USING "btree" ("occurred_at");



CREATE INDEX "idx_commercial_opportunities_exclusivity" ON "public"."commercial_opportunities" USING "btree" ("exclusivity_id");



CREATE INDEX "idx_commercial_region_cities_lookup" ON "public"."commercial_region_cities" USING "btree" ("uf", "city_key", "is_active");



CREATE INDEX "idx_commercial_region_cities_region" ON "public"."commercial_region_cities" USING "btree" ("region_id");



CREATE INDEX "idx_commercial_regions_uf_active" ON "public"."commercial_regions" USING "btree" ("uf", "is_active");



CREATE INDEX "idx_legal_acceptances_auth_user" ON "public"."legal_acceptances" USING "btree" ("auth_user_id");



CREATE INDEX "idx_legal_acceptances_doc" ON "public"."legal_acceptances" USING "btree" ("legal_document_id");



CREATE INDEX "idx_legal_acceptances_linked" ON "public"."legal_acceptances" USING "btree" ("linked_auth_user_id");



CREATE INDEX "idx_legal_acceptances_subject" ON "public"."legal_acceptances" USING "btree" ("subject_type", "subject_id");



CREATE INDEX "idx_legal_documents_type_status" ON "public"."legal_documents" USING "btree" ("doc_type", "status", "effective_from");



CREATE INDEX "idx_loyalty_cnpj_state" ON "public"."cnpj_state_loyalty" USING "btree" ("cnpj", "state");



CREATE INDEX "idx_notification_events_correl" ON "public"."notification_events" USING "btree" ("correlation_entity_type", "correlation_entity_id");



CREATE INDEX "idx_notification_events_recip" ON "public"."notification_events" USING "btree" ("recipient_user_id");



CREATE INDEX "idx_notification_events_status" ON "public"."notification_events" USING "btree" ("status", "scheduled_for");



CREATE INDEX "idx_order_items_order" ON "public"."order_items" USING "btree" ("order_id");



CREATE INDEX "idx_orders_cnpj" ON "public"."orders" USING "btree" ("cnpj");



CREATE INDEX "idx_orders_profile" ON "public"."orders" USING "btree" ("site_profile_id");



CREATE INDEX "idx_site_profiles_auth" ON "public"."site_profiles" USING "btree" ("auth_user_id");



CREATE INDEX "idx_site_profiles_cnpj" ON "public"."site_profiles" USING "btree" ("cnpj");



CREATE UNIQUE INDEX "uq_commercial_exclusivities_current_per_region" ON "public"."commercial_exclusivities" USING "btree" ("region_id") WHERE "is_current";



CREATE UNIQUE INDEX "uq_legal_acceptances_ativo" ON "public"."legal_acceptances" USING "btree" ("subject_type", "subject_id", "legal_document_id", "context") WHERE ("revoked_at" IS NULL);



CREATE UNIQUE INDEX "uq_legal_documents_vigente" ON "public"."legal_documents" USING "btree" ("doc_type") WHERE (("status" = 'published'::"text") AND ("effective_to" IS NULL));



CREATE UNIQUE INDEX "uq_notification_events_idempotency" ON "public"."notification_events" USING "btree" ("channel", "idempotency_key");



CREATE UNIQUE INDEX "uq_notification_events_retry_parent" ON "public"."notification_events" USING "btree" ("retry_of_event_id") WHERE ("retry_of_event_id" IS NOT NULL);



CREATE UNIQUE INDEX "uq_site_monthly_partners_cnpj_normalized" ON "public"."site_monthly_partners" USING "btree" ("regexp_replace"("cnpj", '[^0-9]'::"text", ''::"text", 'g'::"text")) WHERE (("cnpj" IS NOT NULL) AND ("regexp_replace"("cnpj", '[^0-9]'::"text", ''::"text", 'g'::"text") <> ''::"text"));



CREATE UNIQUE INDEX "uq_site_profiles_auth_user_id" ON "public"."site_profiles" USING "btree" ("auth_user_id") WHERE ("auth_user_id" IS NOT NULL);



CREATE OR REPLACE TRIGGER "trg_audit_logs_no_delete" BEFORE DELETE ON "public"."audit_logs" FOR EACH ROW EXECUTE FUNCTION "public"."audit_logs_block_mutation"();



CREATE OR REPLACE TRIGGER "trg_audit_logs_no_update" BEFORE UPDATE ON "public"."audit_logs" FOR EACH ROW EXECUTE FUNCTION "public"."audit_logs_block_mutation"();



CREATE OR REPLACE TRIGGER "trg_commercial_opportunities_canonical_qty" BEFORE INSERT OR UPDATE ON "public"."commercial_opportunities" FOR EACH ROW EXECUTE FUNCTION "public"."commercial_opportunities_canonical_qty"();



CREATE OR REPLACE TRIGGER "trg_commercial_region_cities_same_uf" BEFORE INSERT OR UPDATE ON "public"."commercial_region_cities" FOR EACH ROW EXECUTE FUNCTION "public"."commercial_region_cities_same_uf"();



CREATE OR REPLACE TRIGGER "trg_devolver_item" BEFORE DELETE ON "public"."order_items" FOR EACH ROW EXECUTE FUNCTION "public"."devolver_estoque_item"();



CREATE OR REPLACE TRIGGER "trg_item_pedido" BEFORE INSERT ON "public"."order_items" FOR EACH ROW EXECUTE FUNCTION "public"."aplicar_item_pedido"();



CREATE OR REPLACE TRIGGER "trg_legal_acceptances_protect_del" BEFORE DELETE ON "public"."legal_acceptances" FOR EACH ROW EXECUTE FUNCTION "public"."legal_acceptances_protect"();



CREATE OR REPLACE TRIGGER "trg_legal_acceptances_protect_upd" BEFORE UPDATE ON "public"."legal_acceptances" FOR EACH ROW EXECUTE FUNCTION "public"."legal_acceptances_protect"();



CREATE OR REPLACE TRIGGER "trg_legal_documents_overlap" BEFORE INSERT OR UPDATE ON "public"."legal_documents" FOR EACH ROW EXECUTE FUNCTION "public"."legal_documents_check_overlap"();



CREATE OR REPLACE TRIGGER "trg_legal_documents_protect" BEFORE INSERT OR DELETE OR UPDATE ON "public"."legal_documents" FOR EACH ROW EXECUTE FUNCTION "public"."legal_documents_protect"();



CREATE OR REPLACE TRIGGER "trg_legal_documents_updated" BEFORE UPDATE ON "public"."legal_documents" FOR EACH ROW EXECUTE FUNCTION "public"."fase2a_touch_updated_at"();



CREATE OR REPLACE TRIGGER "trg_notification_events_protect" BEFORE INSERT OR UPDATE ON "public"."notification_events" FOR EACH ROW EXECUTE FUNCTION "public"."notification_events_protect"();



CREATE OR REPLACE TRIGGER "trg_notification_events_updated" BEFORE UPDATE ON "public"."notification_events" FOR EACH ROW EXECUTE FUNCTION "public"."fase2a_touch_updated_at"();



CREATE OR REPLACE TRIGGER "trg_processar_item" BEFORE INSERT ON "public"."order_items" FOR EACH ROW EXECUTE FUNCTION "public"."processar_item_pedido"();



CREATE OR REPLACE TRIGGER "trg_totais_pedido" AFTER INSERT OR DELETE OR UPDATE ON "public"."order_items" FOR EACH ROW EXECUTE FUNCTION "public"."trg_recalcular_pedido"();



ALTER TABLE ONLY "public"."audit_logs"
    ADD CONSTRAINT "audit_logs_corrects_log_id_fkey" FOREIGN KEY ("corrects_log_id") REFERENCES "public"."audit_logs"("id") ON DELETE RESTRICT;



ALTER TABLE ONLY "public"."commercial_exclusivities"
    ADD CONSTRAINT "commercial_exclusivities_region_id_fkey" FOREIGN KEY ("region_id") REFERENCES "public"."commercial_regions"("id");



ALTER TABLE ONLY "public"."commercial_opportunities"
    ADD CONSTRAINT "commercial_opportunities_exclusivity_id_fkey" FOREIGN KEY ("exclusivity_id") REFERENCES "public"."commercial_exclusivities"("id");



ALTER TABLE ONLY "public"."commercial_opportunities"
    ADD CONSTRAINT "commercial_opportunities_niche_code_fkey" FOREIGN KEY ("niche_code") REFERENCES "public"."commercial_niches"("code");



ALTER TABLE ONLY "public"."commercial_region_cities"
    ADD CONSTRAINT "commercial_region_cities_region_id_fkey" FOREIGN KEY ("region_id") REFERENCES "public"."commercial_regions"("id");



ALTER TABLE ONLY "public"."invoices"
    ADD CONSTRAINT "invoices_order_id_fkey" FOREIGN KEY ("order_id") REFERENCES "public"."orders"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."legal_acceptances"
    ADD CONSTRAINT "legal_acceptances_auth_user_id_fkey" FOREIGN KEY ("auth_user_id") REFERENCES "auth"."users"("id") ON DELETE SET NULL;



ALTER TABLE ONLY "public"."legal_acceptances"
    ADD CONSTRAINT "legal_acceptances_legal_document_id_fkey" FOREIGN KEY ("legal_document_id") REFERENCES "public"."legal_documents"("id") ON DELETE RESTRICT;



ALTER TABLE ONLY "public"."notification_events"
    ADD CONSTRAINT "notification_events_retry_of_event_id_fkey" FOREIGN KEY ("retry_of_event_id") REFERENCES "public"."notification_events"("id") ON DELETE RESTRICT;



ALTER TABLE ONLY "public"."order_cancellations"
    ADD CONSTRAINT "order_cancellations_order_id_fkey" FOREIGN KEY ("order_id") REFERENCES "public"."orders"("id");



ALTER TABLE ONLY "public"."order_customization_files"
    ADD CONSTRAINT "order_customization_files_order_id_fkey" FOREIGN KEY ("order_id") REFERENCES "public"."orders"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."order_customization_files"
    ADD CONSTRAINT "order_customization_files_order_item_id_fkey" FOREIGN KEY ("order_item_id") REFERENCES "public"."order_items"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."order_items"
    ADD CONSTRAINT "order_items_order_id_fkey" FOREIGN KEY ("order_id") REFERENCES "public"."orders"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."order_items"
    ADD CONSTRAINT "order_items_product_id_fkey" FOREIGN KEY ("product_id") REFERENCES "public"."products"("id");



ALTER TABLE ONLY "public"."orders"
    ADD CONSTRAINT "orders_site_profile_id_fkey" FOREIGN KEY ("site_profile_id") REFERENCES "public"."site_profiles"("id");



ALTER TABLE ONLY "public"."payments"
    ADD CONSTRAINT "payments_order_id_fkey" FOREIGN KEY ("order_id") REFERENCES "public"."orders"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."product_assets"
    ADD CONSTRAINT "product_assets_product_id_fkey" FOREIGN KEY ("product_id") REFERENCES "public"."products"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."product_customization_fields"
    ADD CONSTRAINT "product_customization_fields_product_id_fkey" FOREIGN KEY ("product_id") REFERENCES "public"."products"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."product_state_stock"
    ADD CONSTRAINT "product_state_stock_product_id_fkey" FOREIGN KEY ("product_id") REFERENCES "public"."products"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."site_admins"
    ADD CONSTRAINT "site_admins_user_id_fkey" FOREIGN KEY ("user_id") REFERENCES "auth"."users"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."site_partner_ads"
    ADD CONSTRAINT "site_partner_ads_contract_id_fkey" FOREIGN KEY ("contract_id") REFERENCES "public"."site_partner_contracts"("id") ON DELETE SET NULL;



ALTER TABLE ONLY "public"."site_partner_ads"
    ADD CONSTRAINT "site_partner_ads_site_partner_id_fkey" FOREIGN KEY ("site_partner_id") REFERENCES "public"."site_monthly_partners"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."site_partner_contracts"
    ADD CONSTRAINT "site_partner_contracts_site_partner_id_fkey" FOREIGN KEY ("site_partner_id") REFERENCES "public"."site_monthly_partners"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."site_profiles"
    ADD CONSTRAINT "site_profiles_auth_user_id_fkey" FOREIGN KEY ("auth_user_id") REFERENCES "auth"."users"("id") ON DELETE SET NULL;



CREATE POLICY "ads_admin_write" ON "public"."site_partner_ads" USING ("public"."is_site_admin"()) WITH CHECK ("public"."is_site_admin"());



CREATE POLICY "ads_public_read" ON "public"."site_partner_ads" FOR SELECT USING ((("active" = true) OR "public"."is_site_admin"()));



CREATE POLICY "assets_admin_write" ON "public"."product_assets" USING ("public"."is_site_admin"()) WITH CHECK ("public"."is_site_admin"());



CREATE POLICY "assets_public_read" ON "public"."product_assets" FOR SELECT USING ((("active" = true) OR "public"."is_site_admin"()));



ALTER TABLE "public"."audit_logs" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "audit_logs_admin_read" ON "public"."audit_logs" FOR SELECT TO "authenticated" USING ("public"."is_site_admin"());



CREATE POLICY "cancellations_admin" ON "public"."order_cancellations" USING ("public"."is_site_admin"()) WITH CHECK ("public"."is_site_admin"());



CREATE POLICY "cancellations_owner_read" ON "public"."order_cancellations" FOR SELECT USING ((EXISTS ( SELECT 1
   FROM ("public"."orders" "o"
     JOIN "public"."site_profiles" "sp" ON (("sp"."id" = "o"."site_profile_id")))
  WHERE (("o"."id" = "order_cancellations"."order_id") AND ("sp"."auth_user_id" = "auth"."uid"())))));



ALTER TABLE "public"."cnpj_state_loyalty" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."commercial_exclusivities" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."commercial_niches" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."commercial_opportunities" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."commercial_region_cities" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."commercial_regions" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."config" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "config_public_read" ON "public"."config" FOR SELECT USING (true);



CREATE POLICY "contact_admin_all" ON "public"."site_contact_messages" USING ("public"."is_site_admin"()) WITH CHECK ("public"."is_site_admin"());



CREATE POLICY "contact_public_insert" ON "public"."site_contact_messages" FOR INSERT WITH CHECK (true);



CREATE POLICY "contracts_admin" ON "public"."site_partner_contracts" USING ("public"."is_site_admin"()) WITH CHECK ("public"."is_site_admin"());



CREATE POLICY "custfields_admin_write" ON "public"."product_customization_fields" USING ("public"."is_site_admin"()) WITH CHECK ("public"."is_site_admin"());



CREATE POLICY "custfields_public_read" ON "public"."product_customization_fields" FOR SELECT USING ((("active" = true) OR "public"."is_site_admin"()));



CREATE POLICY "documents_admin_write" ON "public"."site_documents" USING ("public"."is_site_admin"()) WITH CHECK ("public"."is_site_admin"());



CREATE POLICY "documents_public_read" ON "public"."site_documents" FOR SELECT USING ((("active" = true) OR "public"."is_site_admin"()));



CREATE POLICY "faixas_public_read" ON "public"."faixas_quantidade" FOR SELECT USING (true);



ALTER TABLE "public"."faixas_quantidade" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "files_owner" ON "public"."order_customization_files" USING (("public"."is_site_admin"() OR (EXISTS ( SELECT 1
   FROM ("public"."orders" "o"
     JOIN "public"."site_profiles" "sp" ON (("sp"."id" = "o"."site_profile_id")))
  WHERE (("o"."id" = "order_customization_files"."order_id") AND ("sp"."auth_user_id" = "auth"."uid"())))))) WITH CHECK (("public"."is_site_admin"() OR (EXISTS ( SELECT 1
   FROM ("public"."orders" "o"
     JOIN "public"."site_profiles" "sp" ON (("sp"."id" = "o"."site_profile_id")))
  WHERE (("o"."id" = "order_customization_files"."order_id") AND ("sp"."auth_user_id" = "auth"."uid"()))))));



ALTER TABLE "public"."invoices" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "invoices_admin" ON "public"."invoices" USING ("public"."is_site_admin"()) WITH CHECK ("public"."is_site_admin"());



CREATE POLICY "items_owner" ON "public"."order_items" USING (("public"."is_site_admin"() OR (EXISTS ( SELECT 1
   FROM ("public"."orders" "o"
     JOIN "public"."site_profiles" "sp" ON (("sp"."id" = "o"."site_profile_id")))
  WHERE (("o"."id" = "order_items"."order_id") AND ("sp"."auth_user_id" = "auth"."uid"())))))) WITH CHECK (("public"."is_site_admin"() OR (EXISTS ( SELECT 1
   FROM ("public"."orders" "o"
     JOIN "public"."site_profiles" "sp" ON (("sp"."id" = "o"."site_profile_id")))
  WHERE (("o"."id" = "order_items"."order_id") AND ("sp"."auth_user_id" = "auth"."uid"()))))));



ALTER TABLE "public"."legal_acceptances" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "legal_acceptances_select_own" ON "public"."legal_acceptances" FOR SELECT TO "authenticated" USING ((("auth_user_id" = "auth"."uid"()) OR "public"."is_site_admin"()));



ALTER TABLE "public"."legal_documents" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "legal_documents_admin_all" ON "public"."legal_documents" TO "authenticated" USING ("public"."is_site_admin"()) WITH CHECK ("public"."is_site_admin"());



ALTER TABLE "public"."notification_events" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "notification_events_select_own" ON "public"."notification_events" FOR SELECT TO "authenticated" USING ((("recipient_user_id" = "auth"."uid"()) OR "public"."is_site_admin"()));



ALTER TABLE "public"."order_cancellations" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."order_customization_files" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."order_items" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."orders" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "orders_admin_update" ON "public"."orders" FOR UPDATE USING ("public"."is_site_admin"()) WITH CHECK ("public"."is_site_admin"());



CREATE POLICY "orders_owner_insert" ON "public"."orders" FOR INSERT WITH CHECK (("public"."is_site_admin"() OR (EXISTS ( SELECT 1
   FROM "public"."site_profiles" "sp"
  WHERE (("sp"."id" = "orders"."site_profile_id") AND ("sp"."auth_user_id" = "auth"."uid"()))))));



CREATE POLICY "orders_owner_select" ON "public"."orders" FOR SELECT USING (("public"."is_site_admin"() OR (EXISTS ( SELECT 1
   FROM "public"."site_profiles" "sp"
  WHERE (("sp"."id" = "orders"."site_profile_id") AND ("sp"."auth_user_id" = "auth"."uid"()))))));



CREATE POLICY "partners_admin" ON "public"."site_monthly_partners" USING ("public"."is_site_admin"()) WITH CHECK ("public"."is_site_admin"());



ALTER TABLE "public"."payments" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "payments_admin" ON "public"."payments" USING ("public"."is_site_admin"()) WITH CHECK ("public"."is_site_admin"());



ALTER TABLE "public"."product_assets" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."product_customization_fields" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."product_state_stock" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."products" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "products_admin_write" ON "public"."products" USING ("public"."is_site_admin"()) WITH CHECK ("public"."is_site_admin"());



CREATE POLICY "products_public_read" ON "public"."products" FOR SELECT USING ((("active" = true) OR "public"."is_site_admin"()));



CREATE POLICY "profile_self" ON "public"."site_profiles" USING ((("auth"."uid"() = "auth_user_id") OR "public"."is_site_admin"())) WITH CHECK ((("auth"."uid"() = "auth_user_id") OR "public"."is_site_admin"()));



ALTER TABLE "public"."site_admins" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."site_contact_messages" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."site_documents" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."site_monthly_partners" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."site_partner_ads" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."site_partner_contracts" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."site_profiles" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "stock_admin_write" ON "public"."product_state_stock" USING ("public"."is_site_admin"()) WITH CHECK ("public"."is_site_admin"());



CREATE POLICY "stock_public_read" ON "public"."product_state_stock" FOR SELECT USING ((("active" = true) OR "public"."is_site_admin"()));





ALTER PUBLICATION "supabase_realtime" OWNER TO "postgres";






ALTER PUBLICATION "supabase_realtime" ADD TABLE ONLY "public"."product_state_stock";



ALTER PUBLICATION "supabase_realtime" ADD TABLE ONLY "public"."products";



GRANT USAGE ON SCHEMA "public" TO "postgres";
GRANT USAGE ON SCHEMA "public" TO "anon";
GRANT USAGE ON SCHEMA "public" TO "authenticated";
GRANT USAGE ON SCHEMA "public" TO "service_role";






















































































































































REVOKE ALL ON FUNCTION "public"."aplicar_item_pedido"() FROM PUBLIC;



REVOKE ALL ON FUNCTION "public"."audit_logs_block_mutation"() FROM PUBLIC;



REVOKE ALL ON FUNCTION "public"."calcular_preco_pedido"("p_cnpj" "text", "p_state" "text", "p_product_id" "uuid", "p_quantidade" integer) FROM PUBLIC;



REVOKE ALL ON FUNCTION "public"."commercial_city_key"("p_city" "text") FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."commercial_city_key"("p_city" "text") TO "service_role";



REVOKE ALL ON FUNCTION "public"."commercial_formation_summary"("p_exclusivity_id" "uuid") FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."commercial_formation_summary"("p_exclusivity_id" "uuid") TO "service_role";



REVOKE ALL ON FUNCTION "public"."commercial_is_valid_uf"("p_uf" "text") FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."commercial_is_valid_uf"("p_uf" "text") TO "service_role";



REVOKE ALL ON FUNCTION "public"."commercial_opportunities_canonical_qty"() FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."commercial_opportunities_canonical_qty"() TO "service_role";



REVOKE ALL ON FUNCTION "public"."commercial_region_cities_same_uf"() FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."commercial_region_cities_same_uf"() TO "service_role";



REVOKE ALL ON FUNCTION "public"."create_my_partner_owner_registration"("p_full_name" "text", "p_cpf" "text", "p_phone" "text", "p_legal_name" "text", "p_trade_name" "text", "p_cnpj" "text", "p_company_phone" "text") FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."create_my_partner_owner_registration"("p_full_name" "text", "p_cpf" "text", "p_phone" "text", "p_legal_name" "text", "p_trade_name" "text", "p_cnpj" "text", "p_company_phone" "text") TO "service_role";



GRANT SELECT,INSERT,UPDATE ON TABLE "public"."legal_documents" TO "service_role";



REVOKE ALL ON FUNCTION "public"."current_legal_document"("p_doc_type" "text") FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."current_legal_document"("p_doc_type" "text") TO "service_role";



REVOKE ALL ON FUNCTION "public"."desconto_para_cnpj"("p_cnpj" "text") FROM PUBLIC;



REVOKE ALL ON FUNCTION "public"."desconto_quantidade"("p_qtd" integer) FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."desconto_quantidade"("p_qtd" integer) TO "service_role";



REVOKE ALL ON FUNCTION "public"."devolver_estoque_item"() FROM PUBLIC;



REVOKE ALL ON FUNCTION "public"."fase2a_touch_updated_at"() FROM PUBLIC;



REVOKE ALL ON FUNCTION "public"."get_current_commercial_formation"("p_uf" "text", "p_city" "text") FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."get_current_commercial_formation"("p_uf" "text", "p_city" "text") TO "anon";
GRANT ALL ON FUNCTION "public"."get_current_commercial_formation"("p_uf" "text", "p_city" "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."get_current_commercial_formation"("p_uf" "text", "p_city" "text") TO "service_role";



REVOKE ALL ON FUNCTION "public"."get_current_legal_documents"() FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."get_current_legal_documents"() TO "anon";
GRANT ALL ON FUNCTION "public"."get_current_legal_documents"() TO "authenticated";



REVOKE ALL ON FUNCTION "public"."get_my_legal_acceptances"() FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."get_my_legal_acceptances"() TO "authenticated";



REVOKE ALL ON FUNCTION "public"."get_my_notifications"() FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."get_my_notifications"() TO "authenticated";



GRANT ALL ON FUNCTION "public"."is_site_admin"() TO "anon";
GRANT ALL ON FUNCTION "public"."is_site_admin"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."is_site_admin"() TO "service_role";



REVOKE ALL ON FUNCTION "public"."legal_acceptances_protect"() FROM PUBLIC;



REVOKE ALL ON FUNCTION "public"."legal_document_versions"("p_doc_type" "text") FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."legal_document_versions"("p_doc_type" "text") TO "authenticated";



REVOKE ALL ON FUNCTION "public"."legal_documents_check_overlap"() FROM PUBLIC;



REVOKE ALL ON FUNCTION "public"."legal_documents_protect"() FROM PUBLIC;



REVOKE ALL ON FUNCTION "public"."notification_events_protect"() FROM PUBLIC;



REVOKE ALL ON FUNCTION "public"."processar_item_pedido"() FROM PUBLIC;



REVOKE ALL ON FUNCTION "public"."recalcular_pedido"("p_order" "uuid") FROM PUBLIC;



REVOKE ALL ON FUNCTION "public"."record_legal_acceptance"("p_doc_type" "text", "p_declared_data" "jsonb") FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."record_legal_acceptance"("p_doc_type" "text", "p_declared_data" "jsonb") TO "authenticated";



REVOKE ALL ON FUNCTION "public"."registrar_cancelamento"("p_order_id" "uuid", "p_cancelado_por" "text", "p_motivo" "text") FROM PUBLIC;



REVOKE ALL ON FUNCTION "public"."resolve_commercial_region"("p_uf" "text", "p_city" "text") FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."resolve_commercial_region"("p_uf" "text", "p_city" "text") TO "anon";
GRANT ALL ON FUNCTION "public"."resolve_commercial_region"("p_uf" "text", "p_city" "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."resolve_commercial_region"("p_uf" "text", "p_city" "text") TO "service_role";



REVOKE ALL ON FUNCTION "public"."rls_auto_enable"() FROM PUBLIC;



REVOKE ALL ON FUNCTION "public"."somente_digitos"("t" "text") FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."somente_digitos"("t" "text") TO "service_role";



REVOKE ALL ON FUNCTION "public"."status_fidelidade"("p_cnpj" "text", "p_state" "text") FROM PUBLIC;



REVOKE ALL ON FUNCTION "public"."trg_recalcular_pedido"() FROM PUBLIC;



REVOKE ALL ON FUNCTION "public"."unidades_pagas_cnpj"("p_cnpj" "text", "p_state" "text") FROM PUBLIC;



REVOKE ALL ON FUNCTION "public"."verificar_cascata"("p_order_id" "uuid") FROM PUBLIC;



REVOKE ALL ON FUNCTION "public"."write_audit_log"("p_action" "text", "p_entity_type" "text", "p_entity_id" "text", "p_actor_user_id" "uuid", "p_actor_role" "text", "p_previous_state" "jsonb", "p_new_state" "jsonb", "p_justification" "text", "p_correlation_id" "uuid", "p_source" "text", "p_metadata" "jsonb", "p_corrects_log_id" "uuid") FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."write_audit_log"("p_action" "text", "p_entity_type" "text", "p_entity_id" "text", "p_actor_user_id" "uuid", "p_actor_role" "text", "p_previous_state" "jsonb", "p_new_state" "jsonb", "p_justification" "text", "p_correlation_id" "uuid", "p_source" "text", "p_metadata" "jsonb", "p_corrects_log_id" "uuid") TO "service_role";


















GRANT SELECT,INSERT ON TABLE "public"."audit_logs" TO "service_role";



GRANT ALL ON TABLE "public"."cnpj_state_loyalty" TO "anon";
GRANT ALL ON TABLE "public"."cnpj_state_loyalty" TO "authenticated";
GRANT ALL ON TABLE "public"."cnpj_state_loyalty" TO "service_role";



GRANT ALL ON TABLE "public"."commercial_exclusivities" TO "service_role";



GRANT ALL ON TABLE "public"."commercial_niches" TO "service_role";



GRANT ALL ON TABLE "public"."commercial_opportunities" TO "service_role";



GRANT ALL ON TABLE "public"."commercial_region_cities" TO "service_role";



GRANT ALL ON TABLE "public"."commercial_regions" TO "service_role";



GRANT ALL ON TABLE "public"."config" TO "anon";
GRANT ALL ON TABLE "public"."config" TO "authenticated";
GRANT ALL ON TABLE "public"."config" TO "service_role";



GRANT ALL ON TABLE "public"."faixas_quantidade" TO "anon";
GRANT ALL ON TABLE "public"."faixas_quantidade" TO "authenticated";
GRANT ALL ON TABLE "public"."faixas_quantidade" TO "service_role";



GRANT ALL ON TABLE "public"."invoices" TO "anon";
GRANT ALL ON TABLE "public"."invoices" TO "authenticated";
GRANT ALL ON TABLE "public"."invoices" TO "service_role";



GRANT SELECT,INSERT,UPDATE ON TABLE "public"."legal_acceptances" TO "service_role";



GRANT SELECT,INSERT,UPDATE ON TABLE "public"."notification_events" TO "service_role";



GRANT ALL ON TABLE "public"."order_cancellations" TO "anon";
GRANT ALL ON TABLE "public"."order_cancellations" TO "authenticated";
GRANT ALL ON TABLE "public"."order_cancellations" TO "service_role";



GRANT ALL ON TABLE "public"."order_customization_files" TO "anon";
GRANT ALL ON TABLE "public"."order_customization_files" TO "authenticated";
GRANT ALL ON TABLE "public"."order_customization_files" TO "service_role";



GRANT ALL ON TABLE "public"."order_items" TO "anon";
GRANT ALL ON TABLE "public"."order_items" TO "authenticated";
GRANT ALL ON TABLE "public"."order_items" TO "service_role";



GRANT ALL ON TABLE "public"."orders" TO "anon";
GRANT ALL ON TABLE "public"."orders" TO "authenticated";
GRANT ALL ON TABLE "public"."orders" TO "service_role";



GRANT ALL ON TABLE "public"."payments" TO "anon";
GRANT ALL ON TABLE "public"."payments" TO "authenticated";
GRANT ALL ON TABLE "public"."payments" TO "service_role";



GRANT ALL ON TABLE "public"."product_assets" TO "anon";
GRANT ALL ON TABLE "public"."product_assets" TO "authenticated";
GRANT ALL ON TABLE "public"."product_assets" TO "service_role";



GRANT ALL ON TABLE "public"."product_customization_fields" TO "anon";
GRANT ALL ON TABLE "public"."product_customization_fields" TO "authenticated";
GRANT ALL ON TABLE "public"."product_customization_fields" TO "service_role";



GRANT ALL ON TABLE "public"."product_state_stock" TO "anon";
GRANT ALL ON TABLE "public"."product_state_stock" TO "authenticated";
GRANT ALL ON TABLE "public"."product_state_stock" TO "service_role";



GRANT ALL ON TABLE "public"."products" TO "anon";
GRANT ALL ON TABLE "public"."products" TO "authenticated";
GRANT ALL ON TABLE "public"."products" TO "service_role";



GRANT ALL ON TABLE "public"."site_admins" TO "anon";
GRANT ALL ON TABLE "public"."site_admins" TO "authenticated";
GRANT ALL ON TABLE "public"."site_admins" TO "service_role";



GRANT ALL ON TABLE "public"."site_contact_messages" TO "anon";
GRANT ALL ON TABLE "public"."site_contact_messages" TO "authenticated";
GRANT ALL ON TABLE "public"."site_contact_messages" TO "service_role";



GRANT ALL ON TABLE "public"."site_documents" TO "anon";
GRANT ALL ON TABLE "public"."site_documents" TO "authenticated";
GRANT ALL ON TABLE "public"."site_documents" TO "service_role";



GRANT ALL ON TABLE "public"."site_monthly_partners" TO "anon";
GRANT ALL ON TABLE "public"."site_monthly_partners" TO "authenticated";
GRANT ALL ON TABLE "public"."site_monthly_partners" TO "service_role";



GRANT ALL ON TABLE "public"."site_partner_ads" TO "anon";
GRANT ALL ON TABLE "public"."site_partner_ads" TO "authenticated";
GRANT ALL ON TABLE "public"."site_partner_ads" TO "service_role";



GRANT ALL ON TABLE "public"."site_partner_contracts" TO "anon";
GRANT ALL ON TABLE "public"."site_partner_contracts" TO "authenticated";
GRANT ALL ON TABLE "public"."site_partner_contracts" TO "service_role";



GRANT ALL ON TABLE "public"."site_profiles" TO "anon";
GRANT ALL ON TABLE "public"."site_profiles" TO "authenticated";
GRANT ALL ON TABLE "public"."site_profiles" TO "service_role";









ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON SEQUENCES TO "postgres";
ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON SEQUENCES TO "anon";
ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON SEQUENCES TO "authenticated";
ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON SEQUENCES TO "service_role";






ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON FUNCTIONS TO "postgres";
ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON FUNCTIONS TO "anon";
ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON FUNCTIONS TO "authenticated";
ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON FUNCTIONS TO "service_role";






ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON TABLES TO "postgres";
ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON TABLES TO "anon";
ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON TABLES TO "authenticated";
ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON TABLES TO "service_role";




































-- ---------------------------------------------------------------------------
-- BDFlow baseline reconstruction
-- supabase db dump 2.114.0 intentionally omits event triggers.
-- This project-owned event trigger exists in the captured remote database.
-- ---------------------------------------------------------------------------

CREATE EVENT TRIGGER "ensure_rls"
    ON ddl_command_end
    WHEN TAG IN ('CREATE TABLE', 'CREATE TABLE AS', 'SELECT INTO')
    EXECUTE FUNCTION "public"."rls_auto_enable"();

ALTER EVENT TRIGGER "ensure_rls" OWNER TO "postgres";
ALTER EVENT TRIGGER "ensure_rls" ENABLE;