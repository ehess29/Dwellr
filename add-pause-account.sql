-- =====================================================================
-- Dwellr: Pause Account
--
-- Run this ONCE in the Supabase SQL Editor on a project that already ran
-- schema.sql before this change. (A brand-new project only needs
-- schema.sql, which already includes it.)
--
-- A paused student keeps their profile, photos, connections and chats,
-- but while paused:
--   * Other students don't see them in Find Roommates or in their
--     Connection Requests. Students already connected with them still
--     see their profile and can keep messaging.
--   * They can't swipe or answer connection requests.
--   * Swipes other students make on them (for example from a card that
--     was already loaded) are ignored, so no new connection can form.
--   * Every "yes" from before the pause stays saved and counts again
--     after they unpause.
-- =====================================================================

-- Empty means active. Otherwise it's when the student paused.
-- Private: left out of the profile column grants, like phone and email.
alter table public.profile
  add column if not exists paused_at timestamptz;


-- Hide paused students from everyone except themselves and the students
-- they're already connected with. profile_cards reads profile as the
-- logged-in student, so the swipe deck and requests inbox skip them too.
drop policy if exists "Students can read profiles" on public.profile;
create policy "Students can read active profiles and their connections"
  on public.profile for select to authenticated
  using (
    paused_at is null
    or user_id = (select auth.uid())
    or exists (
      select 1 from public.connections c
      where c.status = 'connected'
        and (select auth.uid()) in (c.user_1, c.user_2)
        and profile.user_id in (c.user_1, c.user_2)
    )
  );


-- Runs on every swipe, including ones that skip decide().
create or replace function public.check_decision_pause()
returns trigger
language plpgsql
security definer set search_path = ''
as $$
begin
  if exists (select 1 from public.profile p where p.user_id = new.decider_id and p.paused_at is not null) then
    raise exception 'Your account is paused';
  end if;
  -- Swiping on a paused student: skip it quietly.
  if exists (select 1 from public.profile p where p.user_id = new.target_id and p.paused_at is not null) then
    return null;
  end if;
  return new;
end;
$$;

drop trigger if exists before_decision_saved on public.decision;
create trigger before_decision_saved
  before insert or update on public.decision
  for each row execute function public.check_decision_pause();


-- Pause (true) or unpause (false) the logged-in student's account.
-- Returns when the account was paused, or null when it's active.
create or replace function public.set_paused(p_paused boolean)
returns timestamptz
language sql
security definer set search_path = ''
as $$
  update public.profile
  set paused_at = case when p_paused then coalesce(paused_at, now()) else null end
  where user_id = (select auth.uid())
  returning paused_at;
$$;

-- When the logged-in student paused, or null when they're active.
create or replace function public.get_my_pause_status()
returns timestamptz
language sql
stable security definer set search_path = ''
as $$
  select p.paused_at from public.profile p where p.user_id = (select auth.uid());
$$;


revoke execute on function public.set_paused(boolean), public.get_my_pause_status() from public, anon;
grant execute on function public.set_paused(boolean), public.get_my_pause_status() to authenticated;
revoke execute on function public.check_decision_pause() from public, anon, authenticated;


-- See who's paused right now:
-- select first_name, last_name, paused_at from public.profile where paused_at is not null;
