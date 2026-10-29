-- =====================================================================
-- Dwellr: add the "How did you hear about our website?" question
--
-- Run this ONCE in the Supabase SQL Editor on a project that already ran
-- schema.sql before this change. (A brand-new project only needs
-- schema.sql, which already includes it.)
--
-- Answers are private: they're left out of the profile column grants, so
-- other students can't read them. See them in Table Editor > profile,
-- or run the query at the bottom.
-- =====================================================================

alter table public.profile
  add column if not exists heard_from text
  check (heard_from in ('Friend or roommate', 'Social media', 'BYU class or club', 'Flyer or poster', 'Search engine', 'Other'));

-- Same sign-up trigger as schema.sql, now also saving heard_from.
create or replace function public.handle_new_user()
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

-- Optional: count the answers so far.
-- select coalesce(heard_from, 'No answer') as heard_from, count(*)
-- from public.profile group by 1 order by 2 desc;
