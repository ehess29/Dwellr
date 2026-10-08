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
-- phone and email are private: only the student can read them (see section 7).
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
create table public.connections (
  connection_id   bigint generated always as identity primary key,
  user_1          uuid not null references public.profile (user_id) on delete cascade,
  user_2          uuid not null references public.profile (user_id) on delete cascade,
  connection_date timestamptz not null default now(),
  status          text not null default 'connected' check (status in ('connected', 'unmatched')),
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

create index decision_target_idx    on public.decision (target_id);
create index connections_user_2_idx on public.connections (user_2);
create index messages_connection_idx on public.messages (connection_id, message_date);
create index messages_sender_idx    on public.messages (sender_id);
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

  insert into public.profile (user_id, first_name, last_name, age, phone, email, gender, city, state, introduce)
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
    btrim(meta ->> 'introduce')
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

create trigger on_decision_made
  after insert or update of decision_status on public.decision
  for each row execute function public.create_connection_on_match();


-- Fill in receiver_id from the connection, and refuse messages between
-- students who aren't connected.
create function public.set_message_receiver()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  select case when c.user_1 = new.sender_id then c.user_2 else c.user_1 end
    into new.receiver_id
  from public.connections c
  where c.connection_id = new.connection_id
    and c.status = 'connected'
    and new.sender_id in (c.user_1, c.user_2);

  if new.receiver_id is null then
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
    and not exists (
      select 1 from public.decision d
      where d.decider_id = me.user_id and d.target_id = c.user_id
    )
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

  update public.connections set status = 'unmatched' where connection_id = c.connection_id;
  delete from public.messages where connection_id = c.connection_id;
  delete from public.decision
  where (decider_id = c.user_1 and target_id = c.user_2)
     or (decider_id = c.user_2 and target_id = c.user_1);
end;
$$;

-- Close account. The website deletes the student's photo files first,
-- because Supabase won't delete an account that still owns stored files.
-- Deleting the auth account removes every row that belongs to it.
create function public.delete_my_account()
returns void
language sql
security definer set search_path = ''
as $$
  delete from auth.users where id = (select auth.uid());
$$;


-- ---------------------------------------------------------------------
-- 6. Who can use which tables and functions
--    Start from no access, then grant only what the website needs.
-- ---------------------------------------------------------------------

revoke all on public.interest, public.profile, public.user_interests,
  public.living_preferences, public.housing_preferences, public.photos,
  public.decision, public.connections, public.messages, public.profile_cards
  from anon, authenticated;

-- The sign-up page loads the interest list before the account exists.
grant select on public.interest to anon, authenticated;

-- Every profile column except phone and email.
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

grant usage on all sequences in schema public to authenticated;
grant all on all tables in schema public to service_role;
grant usage, select on all sequences in schema public to service_role;

revoke execute on function
  public.decide(uuid, text), public.get_deck(text, int), public.get_connection_requests(),
  public.get_my_contact(), public.unmatch(bigint), public.delete_my_account()
  from public, anon;
grant execute on function
  public.decide(uuid, text), public.get_deck(text, int), public.get_connection_requests(),
  public.get_my_contact(), public.unmatch(bigint), public.delete_my_account()
  to authenticated;

-- Trigger functions only run as triggers, never called directly.
revoke execute on function
  public.handle_new_user(), public.create_connection_on_match(),
  public.set_message_receiver(), public.check_photo_limit()
  from public, anon, authenticated;


-- ---------------------------------------------------------------------
-- 7. Row Level Security: which rows each student can see and change
-- ---------------------------------------------------------------------

alter table public.interest            enable row level security;
alter table public.profile             enable row level security;
alter table public.user_interests      enable row level security;
alter table public.living_preferences  enable row level security;
alter table public.housing_preferences enable row level security;
alter table public.photos              enable row level security;
alter table public.decision            enable row level security;
alter table public.connections         enable row level security;
alter table public.messages            enable row level security;

create policy "Anyone can read the interest list"
  on public.interest for select to anon, authenticated using (true);

create policy "Students can read profiles"
  on public.profile for select to authenticated using (true);

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

create policy "Students can see their own connections"
  on public.connections for select to authenticated
  using ((select auth.uid()) in (user_1, user_2));

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
