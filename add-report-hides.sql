-- =====================================================================
-- Dwellr: Reporting someone means they never show up for you again
--
-- Run this ONCE in the Supabase SQL Editor on a project that already ran
-- schema.sql, add-reports.sql and add-auto-disable.sql before this
-- change. (A brand-new project only needs schema.sql, which already
-- includes it.)
--
-- After you report a student:
--   * Before you've matched: they never appear in your Find Roommates
--     deck again (not even after the 14-day reset for declined
--     profiles) or in your Connection Requests, and the two of you can
--     never be matched, even if you'd both already said yes.
--   * After you've matched: you're unmatched automatically and the chat
--     disappears for both of you. Unlike Unmatch, the messages are kept
--     so our team can review them with the report.
--   * The reported student isn't told. To them it looks like a normal
--     unmatch, or like you never said yes.
-- =====================================================================


-- ---------------------------------------------------------------------
-- Helper: has student A reported student B?
-- Lives in the "private" schema the website can't call directly, so
-- students still can't look up reports. The deck and requests use it.
-- ---------------------------------------------------------------------
create or replace function private.has_reported(p_reporter uuid, p_reported uuid)
returns boolean
language sql
stable security definer set search_path = ''
as $$
  select exists (
    select 1 from public.reports r
    where r.reporter_id = p_reporter and r.reported_id = p_reported
  );
$$;

revoke execute on function private.has_reported(uuid, uuid) from public, anon;
grant execute on function private.has_reported(uuid, uuid) to authenticated;


-- ---------------------------------------------------------------------
-- Find Roommates deck: skip anyone you've reported.
-- Same as before (likes hidden for good, declines come back after 14
-- days), plus the "reported" line.
-- ---------------------------------------------------------------------
create or replace function public.get_deck(p_housing_type text default null, p_household_size int default null)
returns setof public.profile_cards
language sql
stable security invoker set search_path = ''
as $$
  select c.*
  from public.profile_cards c
  join public.profile_cards me on me.user_id = (select auth.uid())
  where c.user_id <> me.user_id
    and c.gender = me.gender
    and (p_housing_type is null or c.housing_type is null or c.housing_type = p_housing_type)
    -- Keep liked profiles hidden permanently.
    -- Declined profiles reappear after 14 days.
    and not exists (
        select 1
        from public.decision d
        where d.decider_id = me.user_id
          and d.target_id = c.user_id
          and (
              d.decision_status = 'yes'
              or (
                  d.decision_status = 'no'
                  and d.date_time > now() - interval '14 days'
              )
          )
    )
    -- Students you've reported never come back.
    and not private.has_reported(me.user_id, c.user_id)
    and (
      c.interests && me.interests
      or c.cleanliness_level = me.cleanliness_level
      or c.sleep_schedule = me.sleep_schedule
      or c.guest_frequency = me.guest_frequency
      or c.friendship_expectation = me.friendship_expectation
    )
  order by
    abs(coalesce(c.household_size, p_household_size, 0) - coalesce(p_household_size, 0)),
    cardinality(array(select unnest(c.interests) intersect select unnest(me.interests))) desc,
    c.user_id
  limit 50;
$$;


-- ---------------------------------------------------------------------
-- Connection Requests: skip requests from anyone you've reported.
-- ---------------------------------------------------------------------
create or replace function public.get_connection_requests()
returns setof public.profile_cards
language sql
stable security invoker set search_path = ''
as $$
  select c.*
  from public.decision d
  join public.profile_cards c on c.user_id = d.decider_id
  where d.target_id = (select auth.uid())
    and d.decision_status = 'yes'
    and not exists (
      select 1 from public.decision mine
      where mine.decider_id = d.target_id and mine.target_id = d.decider_id
    )
    and not private.has_reported(d.target_id, d.decider_id)
  order by d.date_time desc;
$$;


-- ---------------------------------------------------------------------
-- Matching: two students never match if either one reported the other.
-- ---------------------------------------------------------------------
create or replace function public.create_connection_on_match()
returns trigger
language plpgsql
security definer set search_path = ''
as $$
begin
  if new.decision_status = 'yes' and exists (
    select 1
    from public.decision d
    where d.decider_id = new.target_id
      and d.target_id = new.decider_id
      and d.decision_status = 'yes'
  ) and not exists (
    select 1
    from public.reports r
    where (r.reporter_id = new.decider_id and r.reported_id = new.target_id)
       or (r.reporter_id = new.target_id and r.reported_id = new.decider_id)
  ) then
    insert into public.connections (user_1, user_2)
    values (least(new.decider_id, new.target_id), greatest(new.decider_id, new.target_id))
    on conflict (user_1, user_2) do update
      set status = 'connected', connection_date = now()
      where public.connections.status <> 'connected';
  end if;
  return new;
end;
$$;


-- ---------------------------------------------------------------------
-- Reporting a connection unmatches you. The messages stay in the
-- messages table for our team to review; nobody sees the chat anymore
-- because Messages only lists connected chats.
-- ---------------------------------------------------------------------
create or replace function public.unmatch_on_report()
returns trigger
language plpgsql
security definer set search_path = ''
as $$
begin
  update public.connections
  set status = 'unmatched'
  where user_1 = least(new.reporter_id, new.reported_id)
    and user_2 = greatest(new.reporter_id, new.reported_id)
    and status = 'connected';
  return null;
end;
$$;

revoke execute on function public.unmatch_on_report() from public, anon, authenticated;

drop trigger if exists after_report_unmatch on public.reports;
create trigger after_report_unmatch
  after insert on public.reports
  for each row execute function public.unmatch_on_report();
