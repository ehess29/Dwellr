-- =====================================================================
-- AI compatibility read: automation trigger
-- =====================================================================
-- When two students connect (a new row in public.connections, or an
-- unmatched pair connecting again), call the generate-compatibility Edge
-- Function in the background. The match itself never waits on the AI.
--
-- The Edge Function skips connections that already have a result, so a
-- pair that reconnects keeps its original read and costs nothing extra.
-- Run this once in the Supabase SQL Editor (after add-compatibility-results.sql).
-- =====================================================================

-- pg_net lets the database make web requests in the background.
create extension if not exists pg_net with schema extensions;

create function public.request_compatibility_read()
returns trigger
language plpgsql
security definer set search_path = ''
as $$
begin
  perform net.http_post(
    url := 'https://duvzemashjejcuysupsd.supabase.co/functions/v1/generate-compatibility',
    body := jsonb_build_object('connection_id', new.connection_id),
    headers := jsonb_build_object('Content-Type', 'application/json'),
    -- Claude usually answers in a few seconds; allow up to 30.
    timeout_milliseconds := 30000
  );
  return new;
end;
$$;

revoke execute on function public.request_compatibility_read() from public, anon, authenticated;

create trigger on_connection_created
  after insert on public.connections
  for each row
  when (new.status = 'connected')
  execute function public.request_compatibility_read();

create trigger on_connection_reconnected
  after update of status on public.connections
  for each row
  when (new.status = 'connected' and old.status is distinct from 'connected')
  execute function public.request_compatibility_read();
