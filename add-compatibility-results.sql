-- =====================================================================
-- AI compatibility read
-- =====================================================================
-- One shared result per connection. When two students connect, the
-- generate-compatibility Edge Function asks Claude to compare their
-- profiles and saves the result here. Both students see the same read.
--
-- Only the Edge Function (service role) can write results. Students can
-- read the result for their own connections and mark it as seen.
-- Run this once in the Supabase SQL Editor.
-- =====================================================================

create table public.compatibility_results (
  connection_id bigint primary key
    references public.connections (connection_id) on delete cascade,
  tier text not null
    check (tier in ('Strong match', 'Good match', 'Worth a conversation')),
  -- "Why this could work"
  reasons text[] not null
    check (cardinality(reasons) between 1 and 4),
  -- "Worth talking about": where the two students differ, worded gently
  -- and without revealing either student's exact answers.
  talk_about text[] not null default '{}'
    check (cardinality(talk_about) <= 3),
  conversation_starters text[] not null
    check (cardinality(conversation_starters) between 1 and 4),
  -- Which Claude model wrote this read
  model text not null,
  -- Drives the "New compatibility read" badge for each student
  seen_by_user_1 boolean not null default false,
  seen_by_user_2 boolean not null default false,
  created_at timestamptz not null default now()
);

alter table public.compatibility_results enable row level security;

-- Students can read the result for their own connections only, and not
-- for connections involving a disabled student (same rule as connections).
create policy "Students can read their own compatibility results"
  on public.compatibility_results
  for select
  to authenticated
  using (
    exists (
      select 1
      from public.connections c
      where c.connection_id = compatibility_results.connection_id
        and ((select auth.uid()) = c.user_1 or (select auth.uid()) = c.user_2)
        and not private.is_disabled(c.user_1)
        and not private.is_disabled(c.user_2)
    )
  );

-- No insert, update or delete policies: only the Edge Function writes.
revoke insert, update, delete on public.compatibility_results from anon, authenticated;
revoke select on public.compatibility_results from anon;

-- Mark the compatibility read as seen by the logged-in student. Only
-- flips that student's own flag, and only on their own connections.
create function public.mark_compatibility_seen(p_connection_id bigint)
returns void
language sql
security definer set search_path = ''
as $$
  update public.compatibility_results r
  set seen_by_user_1 = r.seen_by_user_1 or c.user_1 = (select auth.uid()),
      seen_by_user_2 = r.seen_by_user_2 or c.user_2 = (select auth.uid())
  from public.connections c
  where r.connection_id = p_connection_id
    and c.connection_id = r.connection_id
    and (select auth.uid()) in (c.user_1, c.user_2);
$$;

revoke execute on function public.mark_compatibility_seen(bigint) from public, anon;
grant execute on function public.mark_compatibility_seen(bigint) to authenticated;

-- Let the website get new results live (the card appears without a refresh).
alter publication supabase_realtime add table public.compatibility_results;
