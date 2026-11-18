-- Run this in the Supabase SQL Editor after creating profile_update_events.
-- The table holds private activity data. Students can add only their own
-- events; they cannot read, edit, or delete anyone's events from the site.

alter table public.profile_update_events enable row level security;

revoke all on public.profile_update_events from public, anon, authenticated;
grant insert on public.profile_update_events to authenticated;

drop policy if exists "Students record their own profile updates"
  on public.profile_update_events;
create policy "Students record their own profile updates"
  on public.profile_update_events for insert to authenticated
  with check (user_id = (select auth.uid()));
