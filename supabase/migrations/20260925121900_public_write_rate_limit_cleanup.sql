create index if not exists public_write_rate_limits_window_started_at_idx
  on public.public_write_rate_limits (window_started_at);

create or replace function public.consume_public_write_rate_limit(
  p_action text,
  p_fingerprint text,
  p_window_seconds integer,
  p_limit integer
)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog
as $$
declare
  v_bucket timestamptz;
  v_count integer;
begin
  if p_action is null or length(btrim(p_action)) < 1 or length(p_action) > 96 then
    return jsonb_build_object('ok', false, 'reason', 'invalid_action');
  end if;
  if p_fingerprint is null or p_fingerprint !~ '^[0-9a-f]{64}$' then
    return jsonb_build_object('ok', false, 'reason', 'invalid_fingerprint');
  end if;
  if p_window_seconds is null or p_window_seconds < 60 or p_window_seconds > 86400 then
    return jsonb_build_object('ok', false, 'reason', 'invalid_window');
  end if;
  if p_limit is null or p_limit < 1 or p_limit > 1000 then
    return jsonb_build_object('ok', false, 'reason', 'invalid_limit');
  end if;

  delete from public.public_write_rate_limits
   where window_started_at < clock_timestamp() - interval '2 days';

  v_bucket := to_timestamp(
    floor(extract(epoch from clock_timestamp()) / p_window_seconds) * p_window_seconds
  );

  insert into public.public_write_rate_limits(
    action, fingerprint, window_started_at, request_count, created_at, updated_at
  )
  values (
    p_action, p_fingerprint, v_bucket, 1, clock_timestamp(), clock_timestamp()
  )
  on conflict (action, fingerprint, window_started_at)
  do update
     set request_count = public.public_write_rate_limits.request_count + 1,
         updated_at = clock_timestamp()
  returning request_count into v_count;

  return jsonb_build_object(
    'ok', true,
    'allowed', v_count <= p_limit,
    'count', v_count,
    'limit', p_limit
  );
end;
$$;

revoke execute on function public.consume_public_write_rate_limit(text, text, integer, integer)
  from public, anon, authenticated;

grant execute on function public.consume_public_write_rate_limit(text, text, integer, integer)
  to service_role;

revoke all on table public.public_write_rate_limits from public, anon, authenticated;

grant select, insert, update, delete on table public.public_write_rate_limits to service_role;
