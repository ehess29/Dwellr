-- =====================================================================
-- Dwellr: Disable an account after 3 reports
--
-- Run this ONCE in the Supabase SQL Editor on a project that already ran
-- schema.sql and add-reports.sql before this change. (A brand-new
-- project only needs schema.sql, which already includes it.)
--
-- When 3 DIFFERENT students have reported someone, their account is
-- disabled automatically and permanently:
--   * Reports our team marks 'dismissed' don't count. One student
--     reporting the same person several times counts once.
--   * A disabled student can still log in, but only sees a screen saying
--     their account is disabled. They can't swipe, message, report,
--     answer requests or close their account.
--   * They're hidden from everyone, including students already connected
--     with them. Those connections and chats disappear from the other
--     student's Messages, and new messages can't be sent either way.
--   * There's no re-enable step. Our team can also disable someone by
--     hand by filling in disabled_at on their profile row.
--
-- To track reports, open Table Editor > report_summary: one row per
-- reported student with how many students reported them and whether
-- they're disabled. Each report is still in Table Editor > reports.
-- =====================================================================

-- Empty means active. Otherwise it's when the account was disabled.
-- Private: left out of the profile column grants, like phone and email,
-- and students have no update access to profile, so they can't clear it.
alter table public.profile
  add column if not exists disabled_at timestamptz;


-- ---------------------------------------------------------------------
-- Helper: is this student disabled?
-- Lives in a "private" schema the website can't call directly, so
-- students can't use it to look up who's been disabled. Security rules
-- and triggers use it.
-- ---------------------------------------------------------------------
create schema if not exists private;
grant usage on schema private to authenticated;

create or replace function private.is_disabled(p_user uuid)
returns boolean
language sql
stable security definer set search_path = ''
as $$
  select exists (
    select 1 from public.profile p
    where p.user_id = p_user and p.disabled_at is not null
  );
$$;

revoke execute on function private.is_disabled(uuid) from public, anon;
grant execute on function private.is_disabled(uuid) to authenticated;


-- ---------------------------------------------------------------------
-- The 3-strikes rule: after each new report (or a change to a report's
-- status), count the different students with reports that aren't
-- dismissed. At 3 or more, disable the account.
-- ---------------------------------------------------------------------
create or replace function public.disable_after_reports()
returns trigger
language plpgsql
security definer set search_path = ''
as $$
begin
  -- Lock the reported student's row so two reports sent at the same
  -- moment are counted one after the other, not both as the 2nd.
  perform 1 from public.profile where user_id = new.reported_id for update;

  if (
    select count(distinct r.reporter_id)
    from public.reports r
    where r.reported_id = new.reported_id
      and r.status <> 'dismissed'
  ) >= 3 then
    update public.profile
    set disabled_at = now()
    where user_id = new.reported_id
      and disabled_at is null;
  end if;
  return null;
end;
$$;

drop trigger if exists after_report_saved on public.reports;
create trigger after_report_saved
  after insert or update of status on public.reports
  for each row execute function public.disable_after_reports();


-- ---------------------------------------------------------------------
-- What a disabled student can't do
-- ---------------------------------------------------------------------

-- Swipes: a disabled (or paused) student can't swipe, and swipes on a
-- disabled (or paused) student are skipped quietly.
create or replace function public.check_decision_pause()
returns trigger
language plpgsql
security definer set search_path = ''
as $$
begin
  if exists (select 1 from public.profile p where p.user_id = new.decider_id and p.disabled_at is not null) then
    raise exception 'Your account is disabled';
  end if;
  if exists (select 1 from public.profile p where p.user_id = new.decider_id and p.paused_at is not null) then
    raise exception 'Your account is paused';
  end if;
  if exists (select 1 from public.profile p where p.user_id = new.target_id and (p.paused_at is not null or p.disabled_at is not null)) then
    return null;
  end if;
  return new;
end;
$$;

-- Messages: nobody can message to or from a disabled student.
create or replace function public.set_message_receiver()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  if private.is_disabled(new.sender_id) then
    raise exception 'Your account is disabled';
  end if;

  select case when c.user_1 = new.sender_id then c.user_2 else c.user_1 end
    into new.receiver_id
  from public.connections c
  where c.connection_id = new.connection_id
    and c.status = 'connected'
    and new.sender_id in (c.user_1, c.user_2);

  if new.receiver_id is null or private.is_disabled(new.receiver_id) then
    raise exception 'You can only message students you are connected with';
  end if;
  return new;
end;
$$;

-- Close account: a disabled student can't delete their account (and
-- their reports with it) and sign up again with the same email.
create or replace function public.delete_my_account()
returns void
language plpgsql
security definer set search_path = ''
as $$
begin
  if private.is_disabled((select auth.uid())) then
    raise exception 'Your account is disabled';
  end if;
  delete from auth.users where id = (select auth.uid());
end;
$$;

-- When the logged-in student's account was disabled, or null when it isn't.
create or replace function public.get_my_disabled_status()
returns timestamptz
language sql
stable security definer set search_path = ''
as $$
  select p.disabled_at from public.profile p where p.user_id = (select auth.uid());
$$;

revoke execute on function public.get_my_disabled_status() from public, anon;
grant execute on function public.get_my_disabled_status() to authenticated;
revoke execute on function public.disable_after_reports() from public, anon, authenticated;


-- ---------------------------------------------------------------------
-- Hide disabled students from everyone
-- ---------------------------------------------------------------------

-- Profiles: you always see your own. Others must not be disabled, and
-- paused students are still visible only to their connections.
-- profile_cards reads profile as the logged-in student, so the swipe
-- deck and requests inbox skip disabled students too.
drop policy if exists "Students can read active profiles and their connections" on public.profile;
create policy "Students can read active profiles and their connections"
  on public.profile for select to authenticated
  using (
    user_id = (select auth.uid())
    or (
      disabled_at is null
      and (
        paused_at is null
        or exists (
          select 1 from public.connections c
          where c.status = 'connected'
            and (select auth.uid()) in (c.user_1, c.user_2)
            and profile.user_id in (c.user_1, c.user_2)
        )
      )
    )
  );

-- Connections with a disabled student disappear for both students.
drop policy if exists "Students can see their own connections" on public.connections;
create policy "Students can see their own connections"
  on public.connections for select to authenticated
  using (
    (select auth.uid()) in (user_1, user_2)
    and not private.is_disabled(user_1)
    and not private.is_disabled(user_2)
  );

-- Reports: a disabled student can't file reports.
drop policy if exists "Students can report as themselves" on public.reports;
create policy "Students can report as themselves"
  on public.reports for insert to authenticated
  with check (
    reporter_id = (select auth.uid())
    and not private.is_disabled((select auth.uid()))
  );


-- ---------------------------------------------------------------------
-- report_summary: track reports in Table Editor
-- One row per reported student, most reported first. Only our team can
-- see it (students have no access).
-- ---------------------------------------------------------------------
create or replace view public.report_summary
with (security_invoker = true)
as
select
  p.first_name || ' ' || p.last_name as student,
  p.email,
  count(distinct r.reporter_id) filter (where r.status <> 'dismissed') as students_reporting,
  count(*) as total_reports,
  count(*) filter (where r.status = 'open') as open_reports,
  count(*) filter (where r.status = 'dismissed') as dismissed_reports,
  max(r.created_at) as last_reported_at,
  p.disabled_at,
  p.user_id
from public.reports r
join public.profile p on p.user_id = r.reported_id
group by p.user_id, p.first_name, p.last_name, p.email, p.disabled_at
order by students_reporting desc, last_reported_at desc;

revoke all on public.report_summary from anon, authenticated;
grant select on public.report_summary to service_role;
