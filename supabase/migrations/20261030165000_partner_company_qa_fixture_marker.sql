-- Marca empresas de QA sem alterar status, bridge ids ou regras comerciais.
alter table public.site_partner_companies
  add column is_qa_fixture boolean not null default false,
  add column qa_fixture_note text,
  add constraint spc_qa_note_coerente
    check (is_qa_fixture = false or length(btrim(coalesce(qa_fixture_note, ''))) >= 3);

create or replace function public.admin_list_partner_applications(
  p_status text default null,
  p_limit integer default 50,
  p_offset integer default 0
)
returns jsonb
language plpgsql stable
security definer
set search_path to 'pg_catalog'
as $$
declare
  v_itens jsonb;
begin
  perform public.m1_exigir_admin();

  select coalesce(pg_catalog.jsonb_agg(x order by x->>'created_at' desc), '[]'::jsonb)
    into v_itens
    from (
      select pg_catalog.jsonb_build_object(
               'application_id', a.id,
               'cnpj', a.cnpj,
               'legal_name', a.legal_name,
               'city', a.city,
               'uf', a.uf,
               'status', a.status,
               'company_review_status', a.company_review_status,
               'authority_review_status', a.authority_review_status,
               'created_at', a.created_at,
               'is_qa_fixture', coalesce(c.is_qa_fixture, false),
               'representative', (
                  select pg_catalog.jsonb_build_object(
                           'id', r.id, 'full_name', r.full_name,
                           'authority_status', r.authority_status)
                    from public.partner_application_representatives r
                   where r.application_id = a.id and r.is_current)
             ) as x
        from public.partner_applications a
        left join public.site_partner_companies c
          on c.source_application_id = a.id
       where p_status is null or a.status = p_status
       order by a.created_at desc
       limit least(coalesce(p_limit, 50), 200)
      offset greatest(coalesce(p_offset, 0), 0)
    ) s;

  return pg_catalog.jsonb_build_object('ok', true, 'items', v_itens);
end;
$$;

revoke execute on function public.admin_list_partner_applications(text, integer, integer) from public;
grant execute on function public.admin_list_partner_applications(text, integer, integer) to authenticated, service_role;
