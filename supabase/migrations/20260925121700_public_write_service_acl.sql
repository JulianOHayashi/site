grant execute on function public.register_territorial_waitlist_interest(text,text,text,text,text,text,text,text) to service_role;
grant execute on function public.consume_public_write_rate_limit(text,text,integer,integer) to service_role;
grant select, insert, update, delete on table public.public_write_rate_limits to service_role;
