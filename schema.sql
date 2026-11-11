-- =====================================================================
-- Dwellr: Supabase database setup
--
-- Paste this whole file into the Supabase SQL Editor and click Run.
-- Run it once on a new project. To start over, run reset.sql first.
--
-- Tables follow the group ERD, with these changes:
--   * Names are lowercase (profile, user_interests, ...) so queries
--     don't need quotes.
--   * living_preferences and housing_preferences are one-to-one with
--     profile, with user_id as the primary key.
--   * housing_preferences gains housing_type and household_size
--     (the "type of housing" and "number of roommates" from the ERD notes).
--   * photos gains display_order (0 is the main photo).
--   * messages.reciever_ID is spelled receiver_id and filled in
--     automatically from the connection.
--   * There is no password or username column. Supabase Auth stores
--     passwords and students log in with their email.
-- =====================================================================


-- ---------------------------------------------------------------------
-- 1. Tables
-- ---------------------------------------------------------------------

create table public.interest (
  interest_id   smallint generated always as identity primary key,
  interest_name text not null unique
);

-- One row per student. user_id is the same ID Supabase Auth gives the account.
-- phone, email, heard_from, paused_at and disabled_at are private: other students can't read them (see section 6).
create table public.profile (
  user_id    uuid primary key references auth.users (id) on delete cascade,
  first_name text not null check (char_length(first_name) between 1 and 50),
  last_name  text not null check (char_length(last_name) between 1 and 50),
  age        smallint not null check (age between 17 and 99),
  phone      text not null check (phone ~ '^[0-9]{10}$'),
  email      text not null,
  gender     text not null check (gender in ('female', 'male')),
  city       text not null check (char_length(city) between 1 and 60),
  state      text not null check (char_length(state) between 1 and 60),
  introduce  text not null check (char_length(introduce) between 50 and 500),
  -- Optional sign-up question: "How did you hear about our website?"
  heard_from text check (heard_from in ('Friend or roommate', 'Social media', 'BYU class or club', 'Flyer or poster', 'Search engine', 'Other')),
  -- Pause Account: empty means active, otherwise when the student paused.
  -- Paused students are hidden from everyone but their connections (section 7).
  paused_at  timestamptz,
  -- Disabled after 3 different students report them (section 3). Empty
  -- means active. Disabled students are hidden from everyone (section 7).
  disabled_at timestamptz,
  created_at timestamptz not null default now()
);

create table public.user_interests (
  user_id     uuid not null references public.profile (user_id) on delete cascade,
  interest_id smallint not null references public.interest (interest_id) on delete cascade,
  primary key (user_id, interest_id)
);

create table public.living_preferences (
  user_id                uuid primary key references public.profile (user_id) on delete cascade,
  cleanliness_level      smallint not null check (cleanliness_level between 1 and 5),
  sleep_schedule         text not null check (sleep_schedule in ('Early bird', 'Night owl', 'Varies')),
  guest_frequency        text not null check (guest_frequency in ('Rarely', 'Sometimes', 'Often')),
  friendship_expectation text not null check (friendship_expectation in ('Want to be friends', 'Prefer independent living'))
);

create table public.housing_preferences (
  user_id         uuid primary key references public.profile (user_id) on delete cascade,
  living_location text not null check (living_location in ('Provo', 'Orem', 'Springville', 'Spanish Fork', 'Vineyard', 'Lindon')),
  move_in_date    date not null,           -- always the 1st of the move-in month
  lease_length    smallint not null check (lease_length in (4, 8, 12)),   -- months
  monthly_budget  text not null check (monthly_budget in ('Under $400', '$400-$550', '$550-$700', 'Over $700')),
  -- Saved from the Find Roommates page, so both start empty.
  housing_type    text check (housing_type in ('apartment', 'house', 'dorms')),
  household_size  smallint check (household_size between 2 and 6)       -- people living together, including the student (6 means 6+)
);

create table public.photos (
  photo_id      bigint generated always as identity primary key,
  user_id       uuid not null default auth.uid() references public.profile (user_id) on delete cascade,
  photo_url     text not null,
  display_order smallint not null default 0 check (display_order between 0 and 4),
  created_at    timestamptz not null default now()
);

-- One row per swipe. Swiping again on the same person updates the row.
create table public.decision (
  decision_id     bigint generated always as identity primary key,
  decider_id      uuid not null references public.profile (user_id) on delete cascade,
  target_id       uuid not null references public.profile (user_id) on delete cascade,
  decision_status text not null check (decision_status in ('yes', 'no')),
  date_time       timestamptz not null default now(),
  unique (decider_id, target_id),
  check (decider_id <> target_id)
);

-- Created automatically when two students both say yes (section 3).
-- user_1 is always the smaller ID, so each pair has exactly one row.

-- Created when two students both say yes.
-- Each student can separately confirm plans to room together.
create table public.connections (
  connection_id   bigint generated always as identity primary key,
  user_1          uuid not null references public.profile (user_id) on delete cascade,
  user_2          uuid not null references public.profile (user_id) on delete cascade,
  connection_date timestamptz not null default now(),
  status          text not null default 'connected'
                  check (status in ('connected', 'unmatched')),

  -- Roommate planning confirmations
  user_1_plan_at  timestamptz,
  user_2_plan_at  timestamptz,

  unique (user_1, user_2),
  check (user_1 < user_2)
);


create table public.messages (
  message_id    bigint generated always as identity primary key,
  connection_id bigint not null references public.connections (connection_id) on delete cascade,
  sender_id     uuid not null default auth.uid() references public.profile (user_id) on delete cascade,
  receiver_id   uuid not null references public.profile (user_id) on delete cascade,
  text_message  text not null check (char_length(btrim(text_message)) between 1 and 2000),
  message_date  timestamptz not null default now()
);

-- A student reporting another student (Report button on a full profile
-- or in a chat). Students can file reports but never read them.
create table public.reports (
  report_id   bigint generated always as identity primary key,
  reporter_id uuid not null default auth.uid() references public.profile (user_id) on delete cascade,
  reported_id uuid not null references public.profile (user_id) on delete cascade,
  reason      text not null check (reason in (
                'Fake profile', 'Inappropriate photos', 'Harassment or rude messages',
                'Spam or scam', 'Makes me feel unsafe', 'Other')),
  details     text not null check (char_length(btrim(details)) between 20 and 1000),
  status      text not null default 'open' check (status in ('open', 'reviewed', 'dismissed')),
  created_at  timestamptz not null default now(),
  check (reporter_id <> reported_id)
);

create index decision_target_idx    on public.decision (target_id);
create index connections_user_2_idx on public.connections (user_2);
create index messages_connection_idx on public.messages (connection_id, message_date);
create index messages_sender_idx    on public.messages (sender_id);
create index reports_reported_idx   on public.reports (reported_id);
create index reports_reporter_idx   on public.reports (reporter_id);
create index messages_receiver_idx  on public.messages (receiver_id);
create index photos_user_idx        on public.photos (user_id, display_order);
create index user_interests_interest_idx on public.user_interests (interest_id);


-- ---------------------------------------------------------------------
-- 2. The 50 interests shown on the sign-up page
-- ---------------------------------------------------------------------

insert into public.interest (interest_name) values
  ('Hiking'), ('Rock climbing'), ('Skiing'), ('Snowboarding'), ('Running'),
  ('Cycling'), ('Mountain biking'), ('Basketball'), ('Volleyball'), ('Soccer'),
  ('Pickleball'), ('Tennis'), ('Swimming'), ('Weightlifting'), ('Yoga'),
  ('Camping'), ('Fishing'), ('Kayaking'), ('Disc golf'), ('Spikeball'),
  ('Skateboarding'), ('Cooking'), ('Baking'), ('Trying new restaurants'), ('Board games'),
  ('Video games'), ('Chess'), ('Puzzles'), ('Reading'), ('Writing'),
  ('Photography'), ('Painting'), ('Drawing'), ('Crafting'), ('Playing guitar'),
  ('Playing piano'), ('Singing'), ('Dancing'), ('Concerts'), ('Theater'),
  ('Movies'), ('Anime'), ('Podcasts'), ('Thrifting'), ('Gardening'),
  ('Volunteering'), ('Learning languages'), ('Coding'), ('Traveling'), ('Road trips');


-- ---------------------------------------------------------------------
-- 3. Automatic behavior (triggers)
-- ---------------------------------------------------------------------

-- Helper: is this student disabled? Lives in a "private" schema the
-- website can't call directly, so students can't use it to look up who's
-- been disabled. Security rules and triggers use it.
create schema if not exists private;
grant usage on schema private to authenticated;

create function private.is_disabled(p_user uuid)
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

-- Has student A reported student B? Used by the deck and requests so a
-- student you've reported never shows up for you again.
create function private.has_reported(p_reporter uuid, p_reported uuid)
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


-- When someone signs up, copy the sign-up form (sent as account metadata)
-- into profile, living_preferences, housing_preferences and user_interests.
-- If anything is invalid the whole sign-up fails, so no half-made accounts.
create function public.handle_new_user()
returns trigger
language plpgsql
security definer set search_path = ''
as $$
declare
  meta   jsonb := coalesce(new.raw_user_meta_data, '{}'::jsonb);
  picked smallint[];
begin
  -- Accounts added by hand in the dashboard have no form data. Skip them.
  if not meta ? 'first_name' then
    return new;
  end if;

  select array_agg(distinct x::smallint) into picked
  from jsonb_array_elements_text(coalesce(meta -> 'interest_ids', '[]'::jsonb)) as x;

  if coalesce(cardinality(picked), 0) not between 3 and 5 then
    raise exception 'Choose between 3 and 5 interests';
  end if;

  insert into public.profile (user_id, first_name, last_name, age, phone, email, gender, city, state, introduce, heard_from)
  values (
    new.id,
    btrim(meta ->> 'first_name'),
    btrim(meta ->> 'last_name'),
    (meta ->> 'age')::smallint,
    meta ->> 'phone',
    new.email,
    meta ->> 'gender',
    btrim(meta ->> 'city'),
    btrim(meta ->> 'state'),
    btrim(meta ->> 'introduce'),
    nullif(meta ->> 'heard_from', '')
  );

  insert into public.living_preferences (user_id, cleanliness_level, sleep_schedule, guest_frequency, friendship_expectation)
  values (
    new.id,
    (meta ->> 'cleanliness_level')::smallint,
    meta ->> 'sleep_schedule',
    meta ->> 'guest_frequency',
    meta ->> 'friendship_expectation'
  );

  insert into public.housing_preferences (user_id, living_location, move_in_date, lease_length, monthly_budget)
  values (
    new.id,
    meta ->> 'living_location',
    date_trunc('month', (meta ->> 'move_in_date')::date)::date,
    (meta ->> 'lease_length')::smallint,
    meta ->> 'monthly_budget'
  );

  insert into public.user_interests (user_id, interest_id)
  select new.id, unnest(picked);

  return new;
end;
$$;

create trigger on_auth_user_created
  after insert on auth.users
  for each row execute function public.handle_new_user();


-- Mutual matching: when two students have both said yes, connect them.
-- If they were connected before and unmatched, reconnect the same row.
create function public.create_connection_on_match()
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
    -- Never match two students if either one reported the other.
    select 1
    from public.reports r
    where (r.reporter_id = new.decider_id and r.reported_id = new.target_id)
       or (r.reporter_id = new.target_id and r.reported_id = new.decider_id)
  ) then
    insert into public.connections (user_1, user_2)
    values (least(new.decider_id, new.target_id), greatest(new.decider_id, new.target_id))
    on conflict (user_1, user_2) do update
      set status = 'connected',
        connection_date = now(),
        user_1_plan_at = null,
        user_2_plan_at = null
      where public.connections.status <> 'connected';
  end if;
  return new;
end;
$$;

create trigger on_decision_made
  after insert or update of decision_status on public.decision
  for each row execute function public.create_connection_on_match();


-- Pause Account and disabled accounts: a paused or disabled student
-- can't swipe, and swipes on one are skipped quietly (for example from a
-- card that was already loaded), so no new connection can form.
create function public.check_decision_pause()
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

create trigger before_decision_saved
  before insert or update on public.decision
  for each row execute function public.check_decision_pause();


-- Fill in receiver_id from the connection, and refuse messages between
-- students who aren't connected or to or from a disabled student.
create function public.set_message_receiver()
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

create trigger before_message_insert
  before insert on public.messages
  for each row execute function public.set_message_receiver();


-- Up to 5 photos per student.
create function public.check_photo_limit()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  if (select count(*) from public.photos p where p.user_id = new.user_id) >= 5 then
    raise exception 'You can have up to 5 photos';
  end if;
  return new;
end;
$$;

create trigger before_photo_insert
  before insert on public.photos
  for each row execute function public.check_photo_limit();


-- 3 strikes: when 3 different students have reports about someone that
-- our team hasn't dismissed, disable their account. Permanent: there's
-- no re-enable step. Checked after every new report and status change.
create function public.disable_after_reports()
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

create trigger after_report_saved
  after insert or update of status on public.reports
  for each row execute function public.disable_after_reports();

-- Reporting a connection unmatches you. Unlike Unmatch, the messages are
-- kept so our team can review them with the report.
create function public.unmatch_on_report()
returns trigger
language plpgsql
security definer set search_path = ''
as $$
begin
  update public.connections
  set status = 'unmatched',
    user_1_plan_at = null,
    user_2_plan_at = null
  where user_1 = least(new.reporter_id, new.reported_id)
    and user_2 = greatest(new.reporter_id, new.reported_id)
    and status = 'connected';
  return null;
end;
$$;

create trigger after_report_unmatch
  after insert on public.reports
  for each row execute function public.unmatch_on_report();


-- ---------------------------------------------------------------------
-- 4. profile_cards: everything other students see about someone, in one row
--    (no phone or email)
-- ---------------------------------------------------------------------

create view public.profile_cards
with (security_invoker = true)
as
select
  p.user_id, p.first_name, p.last_name, p.age, p.gender, p.city, p.state, p.introduce,
  lp.cleanliness_level, lp.sleep_schedule, lp.guest_frequency, lp.friendship_expectation,
  hp.living_location, hp.move_in_date, hp.lease_length, hp.monthly_budget,
  hp.housing_type, hp.household_size,
  coalesce((
    select array_agg(i.interest_name order by i.interest_name)
    from public.user_interests ui
    join public.interest i on i.interest_id = ui.interest_id
    where ui.user_id = p.user_id
  ), '{}') as interests,
  coalesce((
    select array_agg(ph.photo_url order by ph.display_order, ph.photo_id)
    from public.photos ph
    where ph.user_id = p.user_id
  ), '{}') as photo_urls
from public.profile p
join public.living_preferences lp on lp.user_id = p.user_id
join public.housing_preferences hp on hp.user_id = p.user_id;


-- report_summary: our team tracks reports in Table Editor here. One row
-- per reported student, most reported first. Students have no access.
create view public.report_summary
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


-- ---------------------------------------------------------------------
-- 5. Functions the website calls
-- ---------------------------------------------------------------------

-- Record a swipe ('yes' or 'no'). Returns the connection_id if this
-- swipe completed a mutual match, otherwise null.
create function public.decide(p_target uuid, p_status text)
returns bigint
language plpgsql
security invoker set search_path = ''
as $$
declare
  me uuid := (select auth.uid());
  result bigint;
begin
  insert into public.decision (decider_id, target_id, decision_status)
  values (me, p_target, p_status)
  on conflict (decider_id, target_id)
  do update set decision_status = excluded.decision_status, date_time = now();

  if p_status = 'yes' then
    select c.connection_id into result
    from public.connections c
    where c.user_1 = least(me, p_target)
      and c.user_2 = greatest(me, p_target)
      and c.status = 'connected';
  end if;
  return result;
end;
$$;

-- Students to swipe on: same gender, not swiped on yet, and sharing at
-- least one interest or living-preference answer (PRD requirement).
-- Students who haven't picked a housing type yet show up in every search.
create function public.get_deck(p_housing_type text default null, p_household_size int default null)
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

-- People who said yes to you that you haven't answered yet.
create function public.get_connection_requests()
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

-- The logged-in student's own phone and email.
create function public.get_my_contact()
returns table (phone text, email text)
language sql
stable security definer set search_path = ''
as $$
  select p.phone, p.email from public.profile p where p.user_id = (select auth.uid());
$$;

-- Unmatch (PRD): removes the chat for both students and blocks new
-- messages. Their swipes are cleared so either one can match again later.
create function public.unmatch(p_connection_id bigint)
returns void
language plpgsql
security definer set search_path = ''
as $$
declare
  me uuid := (select auth.uid());
  c public.connections;
begin
  select * into c
  from public.connections
  where connection_id = p_connection_id
    and me in (user_1, user_2)
    and status = 'connected';

  if not found then
    raise exception 'Connection not found';
  end if;

  update public.connections
  set status = 'unmatched',
    user_1_plan_at = null,
    user_2_plan_at = null
  where connection_id = c.connection_id;
  delete from public.messages where connection_id = c.connection_id;
  delete from public.decision
  where (decider_id = c.user_1 and target_id = c.user_2)
     or (decider_id = c.user_2 and target_id = c.user_1);
end;
$$;


  -- Planning to Room Together:
  -- Each connected student can confirm or withdraw their own agreement.
  -- Both timestamps must be present for the plan to be confirmed.
  create function public.set_roommate_plan(
    p_connection_id bigint,
    p_confirm boolean
  )
  returns void
  language plpgsql
  security definer set search_path = ''
  as $$
  declare
    me uuid := (select auth.uid());
  begin
    if me is null then
      raise exception 'Not authenticated';
    end if;

    if p_confirm is null then
      raise exception 'Confirmation must be true or false';
    end if;

    update public.connections c
    set
      user_1_plan_at =
        case
          when c.user_1 = me
            then case when p_confirm then now() else null end
          else c.user_1_plan_at
        end,
      user_2_plan_at =
        case
          when c.user_2 = me
            then case when p_confirm then now() else null end
          else c.user_2_plan_at
        end
    where c.connection_id = p_connection_id
      and c.status = 'connected'
      and me in (c.user_1, c.user_2)
      and not private.is_disabled(c.user_1)
      and not private.is_disabled(c.user_2);

    if not found then
      raise exception 'Connection not found or unavailable';
    end if;
  end;
  $$;


-- Close account. The website deletes the student's photo files first,
-- because Supabase won't delete an account that still owns stored files.
-- Deleting the auth account removes every row that belongs to it.
-- Disabled students can't, so they can't erase their reports and sign up
-- again with the same email.
create function public.delete_my_account()
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

-- Pause Account: pause (true) or unpause (false). Returns when the
-- account was paused, or null when it's active. Nothing is deleted.
create function public.set_paused(p_paused boolean)
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
create function public.get_my_pause_status()
returns timestamptz
language sql
stable security definer set search_path = ''
as $$
  select p.paused_at from public.profile p where p.user_id = (select auth.uid());
$$;

-- When the logged-in student's account was disabled, or null when it isn't.
create function public.get_my_disabled_status()
returns timestamptz
language sql
stable security definer set search_path = ''
as $$
  select p.disabled_at from public.profile p where p.user_id = (select auth.uid());
$$;


-- ---------------------------------------------------------------------
-- 6. Who can use which tables and functions
--    Start from no access, then grant only what the website needs.
-- ---------------------------------------------------------------------

revoke all on public.interest, public.profile, public.user_interests,
  public.living_preferences, public.housing_preferences, public.photos,
  public.decision, public.connections, public.messages, public.reports,
  public.profile_cards, public.report_summary
  from anon, authenticated;

-- The sign-up page loads the interest list before the account exists.
grant select on public.interest to anon, authenticated;

-- Every profile column except phone, email, heard_from, paused_at and disabled_at.
grant select (user_id, first_name, last_name, age, gender, city, state, introduce, created_at)
  on public.profile to authenticated;

grant select on public.user_interests, public.living_preferences,
  public.housing_preferences, public.profile_cards to authenticated;
grant update (housing_type, household_size) on public.housing_preferences to authenticated;

grant select, insert, delete on public.photos to authenticated;
grant update (display_order) on public.photos to authenticated;

grant select on public.decision to authenticated;
grant insert (decider_id, target_id, decision_status) on public.decision to authenticated;
grant update (decision_status, date_time) on public.decision to authenticated;

grant select on public.connections to authenticated;

grant select on public.messages to authenticated;
grant insert (connection_id, text_message) on public.messages to authenticated;

-- Students can file a report but never read one.
grant insert (reported_id, reason, details) on public.reports to authenticated;

grant usage on all sequences in schema public to authenticated;
grant all on all tables in schema public to service_role;
grant usage, select on all sequences in schema public to service_role;

revoke execute on function
  public.decide(uuid, text), public.get_deck(text, int), public.get_connection_requests(),
  public.get_my_contact(), public.unmatch(bigint), public.delete_my_account(),
  public.set_paused(boolean), public.get_my_pause_status(), public.get_my_disabled_status()
  from public, anon;
grant execute on function
  public.decide(uuid, text), public.get_deck(text, int), public.get_connection_requests(),
  public.get_my_contact(), public.unmatch(bigint), public.delete_my_account(),
  public.set_paused(boolean), public.get_my_pause_status(), public.get_my_disabled_status()
  to authenticated;

  -- Allow authenticated students to confirm roommate plans.
revoke execute on function public.set_roommate_plan(bigint, boolean)
  from public, anon;

grant execute on function public.set_roommate_plan(bigint, boolean)
  to authenticated;

-- Trigger functions only run as triggers, never called directly.
revoke execute on function
  public.handle_new_user(), public.create_connection_on_match(),
  public.set_message_receiver(), public.check_photo_limit(),
  public.check_decision_pause(), public.disable_after_reports(),
  public.unmatch_on_report()
  from public, anon, authenticated;


-- ---------------------------------------------------------------------
-- 7. Row Level Security: which rows each student can see and change
-- ---------------------------------------------------------------------

alter table public.interest            enable row level security;
alter table public.profile             enable row level security;
alter table public.user_interests      enable row level security;
alter table public.reports             enable row level security;
alter table public.living_preferences  enable row level security;
alter table public.housing_preferences enable row level security;
alter table public.photos              enable row level security;
alter table public.decision            enable row level security;
alter table public.connections         enable row level security;
alter table public.messages            enable row level security;

create policy "Anyone can read the interest list"
  on public.interest for select to anon, authenticated using (true);

-- You always see your own profile. Disabled students are hidden from
-- everyone else. Paused students are hidden from everyone except the
-- students they're already connected with. profile_cards reads profile
-- as the logged-in student, so the deck and requests inbox skip them too.
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

create policy "Students can read interests"
  on public.user_interests for select to authenticated using (true);

create policy "Students can read living preferences"
  on public.living_preferences for select to authenticated using (true);

create policy "Students can read housing preferences"
  on public.housing_preferences for select to authenticated using (true);
create policy "Students can update their own housing preferences"
  on public.housing_preferences for update to authenticated
  using (user_id = (select auth.uid())) with check (user_id = (select auth.uid()));

create policy "Students can see photos"
  on public.photos for select to authenticated using (true);
create policy "Students can add their own photos"
  on public.photos for insert to authenticated with check (user_id = (select auth.uid()));
create policy "Students can reorder their own photos"
  on public.photos for update to authenticated
  using (user_id = (select auth.uid())) with check (user_id = (select auth.uid()));
create policy "Students can delete their own photos"
  on public.photos for delete to authenticated using (user_id = (select auth.uid()));

-- You see your own swipes, and the "yes" swipes other people made on you
-- (that's your requests inbox). Nobody can see who said no to them.
create policy "Students can see their swipes and yeses on them"
  on public.decision for select to authenticated
  using (
    decider_id = (select auth.uid())
    or (target_id = (select auth.uid()) and decision_status = 'yes')
  );
create policy "Students can swipe as themselves"
  on public.decision for insert to authenticated with check (decider_id = (select auth.uid()));
create policy "Students can change their own swipes"
  on public.decision for update to authenticated
  using (decider_id = (select auth.uid())) with check (decider_id = (select auth.uid()));

-- Connections with a disabled student disappear for both students.
create policy "Students can see their own connections"
  on public.connections for select to authenticated
  using (
    (select auth.uid()) in (user_1, user_2)
    and not private.is_disabled(user_1)
    and not private.is_disabled(user_2)
  );

-- Messaging (PRD): only connected students can message each other.
create policy "Students can read their own messages"
  on public.messages for select to authenticated
  using ((select auth.uid()) in (sender_id, receiver_id));
create policy "Connected students can send messages"
  on public.messages for insert to authenticated
  with check (
    sender_id = (select auth.uid())
    and exists (
      select 1 from public.connections c
      where c.connection_id = messages.connection_id
        and c.status = 'connected'
        and (select auth.uid()) in (c.user_1, c.user_2)
    )
  );

-- Disabled students can't file reports.
create policy "Students can report as themselves"
  on public.reports for insert to authenticated
  with check (
    reporter_id = (select auth.uid())
    and not private.is_disabled((select auth.uid()))
  );


-- ---------------------------------------------------------------------
-- 8. Photo storage
--    Files live at profile-photos/<user_id>/<file>. The bucket is public
--    so photos load by URL; students can only add or delete files in
--    their own folder.
-- ---------------------------------------------------------------------

insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('profile-photos', 'profile-photos', true, 5242880,
        array['image/jpeg', 'image/png', 'image/webp', 'image/gif'])
on conflict (id) do nothing;

create policy "Students upload to their own photo folder"
  on storage.objects for insert to authenticated
  with check (bucket_id = 'profile-photos' and (storage.foldername(name))[1] = (select auth.uid()::text));

create policy "Students can see their own photo files"
  on storage.objects for select to authenticated
  using (bucket_id = 'profile-photos' and (storage.foldername(name))[1] = (select auth.uid()::text));

create policy "Students delete their own photo files"
  on storage.objects for delete to authenticated
  using (bucket_id = 'profile-photos' and (storage.foldername(name))[1] = (select auth.uid()::text));


-- ---------------------------------------------------------------------
-- 9. Realtime: push new messages and new matches to the website
-- ---------------------------------------------------------------------

alter publication supabase_realtime add table public.messages, public.connections;


-- ---------------------------------------------------------------------
-- 10. AI compatibility read
-- ---------------------------------------------------------------------
-- When two students connect, a trigger calls the generate-compatibility
-- Edge Function (supabase/functions/generate-compatibility). It asks
-- Claude to compare the two profiles and saves one shared read here.
-- Needs the ANTHROPIC_API_KEY secret (Edge Functions > Secrets).

create table public.compatibility_results (
  connection_id bigint primary key
    references public.connections (connection_id) on delete cascade,
  tier text not null
    check (tier in ('Strong match', 'Good match', 'Worth a conversation')),
  -- "Why this could work"
  reasons text[] not null
    check (cardinality(reasons) between 1 and 4),
  -- "Worth talking about": differences, worded without saying who answered what
  talk_about text[] not null default '{}'
    check (cardinality(talk_about) <= 3),
  conversation_starters text[] not null
    check (cardinality(conversation_starters) between 1 and 4),
  model text not null,  -- which Claude model wrote it
  seen_by_user_1 boolean not null default false,  -- drives the "New read" badge
  seen_by_user_2 boolean not null default false,
  created_at timestamptz not null default now()
);

alter table public.compatibility_results enable row level security;

-- Only the two students in the connection can read it (not if either is disabled).
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

-- Only the Edge Function writes results.
revoke insert, update, delete on public.compatibility_results from anon, authenticated;
revoke select on public.compatibility_results from anon;

-- Clears the logged-in student's own "New read" badge.
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

alter publication supabase_realtime add table public.compatibility_results;

-- Call the Edge Function in the background when two students connect (or
-- an unmatched pair reconnects). The function skips connections that
-- already have a read. Change the URL if you use a different project.
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
