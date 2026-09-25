revoke execute on function public.consume_public_write_rate_limit(text,text,integer,integer) from public, anon, authenticated;
revoke all on table public.public_write_rate_limits from public, anon, authenticated;
revoke execute on function public.is_site_admin() from public, anon;
